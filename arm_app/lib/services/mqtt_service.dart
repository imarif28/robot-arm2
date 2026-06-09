import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Enum representing MQTT connection status.
enum MqttConnectionStatus { connected, disconnected, connecting }

/// Service class that manages MQTT connection, publishing, and auto-reconnect.
///
/// Exposes a [statusStream] so UI can reactively show connection state,
/// and provides [publish] to send payloads to the robot arm topic.
class MqttService {
  MqttServerClient? _client;
  final String topic = 'robot/arm/control';
  final String statusTopic = 'robot/arm/status';

  // Stream controller for connection status changes
  final StreamController<MqttConnectionStatus> _statusController =
      StreamController<MqttConnectionStatus>.broadcast();

  Stream<MqttConnectionStatus> get statusStream => _statusController.stream;

  MqttConnectionStatus _currentStatus = MqttConnectionStatus.disconnected;
  MqttConnectionStatus get currentStatus => _currentStatus;

  // Stream controller for detailed connection messages (e.g. "Connecting... (attempt 1/3)")
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get connectionMessageStream => _messageController.stream;
  
  String _connectionMessage = '';
  String get connectionMessage => _connectionMessage;

  void _updateMessage(String msg) {
    _connectionMessage = msg;
    _messageController.add(msg);
    debugPrint('[MQTT] $msg');
  }

  // ── ESP32 device status (online/offline via LWT) ──────
  final StreamController<bool> _esp32StatusController =
      StreamController<bool>.broadcast();
  Stream<bool> get esp32StatusStream => _esp32StatusController.stream;
  bool _esp32Online = false;
  bool get esp32Online => _esp32Online;
  Timer? _esp32TimeoutTimer;

  Timer? _reconnectTimer;
  StreamSubscription? _updatesSubscription;  // Track to prevent duplicate listeners
  String? _brokerIP;
  int? _port;
  bool _intentionalDisconnect = false;

  /// Connect to the MQTT broker at [brokerIP]:[port].
  ///
  /// Returns true if connection succeeds, false otherwise.
  Future<bool> connect(String brokerIP, int port) async {
    _brokerIP = brokerIP;
    _port = port;
    _intentionalDisconnect = false;

    _updateStatus(MqttConnectionStatus.connecting);

    for (int attempt = 1; attempt <= 3; attempt++) {
      _updateMessage('Connecting... (attempt $attempt/3)');

      if (_client != null) {
        _client!.disconnect();
        _client = null;
      }

      _client = MqttServerClient.withPort(brokerIP, 'flutter_arm_${DateTime.now().millisecondsSinceEpoch}', port);
      _client!.logging(on: kDebugMode);
      _client!.keepAlivePeriod = 30;
      _client!.autoReconnect = true;
      _client!.onAutoReconnect = _onAutoReconnect;
      _client!.onAutoReconnected = _onAutoReconnected;
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier('flutter_arm_${DateTime.now().millisecondsSinceEpoch}')
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
      _client!.connectionMessage = connMessage;

      try {
        await _client!.connect().timeout(const Duration(seconds: 30));
        
        if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
          _updateMessage('Connected!');
          _updateStatus(MqttConnectionStatus.connected);
          _subscribeToStatusTopic();
          return true;
        }
      } catch (e) {
        debugPrint('[MQTT] Attempt $attempt failed: $e');
        _client?.disconnect();
      }

      if (attempt < 3) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    _updateMessage('Failed to connect. Tap to retry');
    _updateStatus(MqttConnectionStatus.disconnected);
    return false;
  }

  /// Publish a [payload] string to the robot arm control topic.
  void publish(String payload) {
    if (_client == null || _currentStatus != MqttConnectionStatus.connected) {
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    _client!.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
  }

  /// Disconnect from the broker intentionally.
  /// Sends base:90 STOP before disconnecting to prevent continuous servo runaway.
  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _esp32TimeoutTimer?.cancel();
    // Safety: stop continuous servos before disconnecting
    if (_currentStatus == MqttConnectionStatus.connected) {
      publish('base:90');
    }
    _client?.disconnect();
    _updateStatus(MqttConnectionStatus.disconnected);
    _updateEsp32Status(false);
  }

  // ── Internal callbacks ──────────────────────────────────

  void _onConnected() {
    debugPrint('[MQTT] Connected to broker');
    _updateStatus(MqttConnectionStatus.connected);
    _subscribeToStatusTopic();
  }

  void _onDisconnected() {
    debugPrint('[MQTT] Disconnected from broker');
    _updateStatus(MqttConnectionStatus.disconnected);
    _updateEsp32Status(false);
    _esp32TimeoutTimer?.cancel();

    // Auto-reconnect if not intentional
    if (!_intentionalDisconnect && _brokerIP != null && _port != null) {
      _startReconnect();
    }
  }

  void _onAutoReconnect() {
    debugPrint('[MQTT] Auto-reconnecting...');
    _updateStatus(MqttConnectionStatus.connecting);
  }

  void _onAutoReconnected() {
    debugPrint('[MQTT] Auto-reconnected');
    _updateStatus(MqttConnectionStatus.connected);
    _subscribeToStatusTopic();
  }

  void _startReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_currentStatus == MqttConnectionStatus.connected || _intentionalDisconnect) {
        timer.cancel();
        return;
      }
      debugPrint('[MQTT] Attempting reconnect...');
      await connect(_brokerIP!, _port!);
    });
  }

  void _updateStatus(MqttConnectionStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  // ── ESP32 status topic subscription & handling ────────

  /// Subscribe to robot/arm/status and start 5s timeout.
  void _subscribeToStatusTopic() {
    if (_client == null) return;

    _client!.subscribe(statusTopic, MqttQos.atMostOnce);
    debugPrint('[MQTT] Subscribed to status topic: $statusTopic');

    // Cancel any existing listener to prevent duplicate processing
    _updatesSubscription?.cancel();

    // Listen for incoming messages on the status topic
    _updatesSubscription = _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        if (msg.topic == statusTopic) {
          final payload = MqttPublishPayload.bytesToStringAsString(
              (msg.payload as MqttPublishMessage).payload.message);
          debugPrint('[MQTT] ESP32 status: $payload');
          _updateEsp32Status(payload.trim().toLowerCase() == 'online');
        }
      }
    });

    // Start 5s timeout — if no status message received, assume ESP32 offline
    _esp32TimeoutTimer?.cancel();
    _esp32TimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (!_esp32Online) {
        debugPrint('[MQTT] ESP32 status timeout — marking as offline');
        _updateEsp32Status(false);
      }
    });
  }

  void _updateEsp32Status(bool online) {
    _esp32Online = online;
    _esp32StatusController.add(online);
  }

  /// Dispose resources.
  void dispose() {
    _reconnectTimer?.cancel();
    _esp32TimeoutTimer?.cancel();
    _updatesSubscription?.cancel();
    _statusController.close();
    _messageController.close();
    _esp32StatusController.close();
    _client?.disconnect();
  }
}
