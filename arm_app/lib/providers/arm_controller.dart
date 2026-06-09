import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/servo_state.dart';
import '../services/mqtt_service.dart';

/// Central state manager for the robot arm controller.
///
/// Manages:
/// - 4 servo states (base, shoulder, elbow, gripper)
/// - MQTT connection lifecycle
/// - Joystick input → angle calculation → MQTT publish
/// - Speed (step angle) setting
/// - Persistent storage of connection settings
class ArmController extends ChangeNotifier {
  final MqttService _mqttService = MqttService();

  // ── Servo States ──────────────────────────────────────────
  final Map<String, ServoState> servos = {
    'base':     ServoState(name: 'base',     currentAngle: 90, isContinuous: true),
    'shoulder': ServoState(name: 'shoulder', currentAngle: 90),
    'elbow':    ServoState(name: 'elbow',    currentAngle: 90),
    'gripper':  ServoState(name: 'gripper',  currentAngle: 90),
  };

  // ── Base 360° continuous servo tracking ─────────────────
  bool _isBaseMoving = false;

  // ── Connection Settings ───────────────────────────────
  String _brokerIP = '192.168.1.100';
  int _port = 1883;
  String _espSSID = 'RobotArm-Setup';

  String get brokerIP => _brokerIP;
  int get port => _port;
  String get espSSID => _espSSID;

  // ── Speed (step angle per joystick tick) ──────────────
  int _speed = 3;
  int get speed => _speed;

  set speed(int value) {
    _speed = value.clamp(1, 10);
    notifyListeners();
  }

  // ── Connection Status ─────────────────────────────────
  MqttConnectionStatus _connectionStatus = MqttConnectionStatus.disconnected;
  MqttConnectionStatus get connectionStatus => _connectionStatus;
  bool get isConnected => _connectionStatus == MqttConnectionStatus.connected;
  
  String _connectionMessage = '';
  String get connectionMessage => _connectionMessage;

  // ── ESP32 Device Status ───────────────────────────────
  bool _esp32Online = false;
  bool get esp32Online => _esp32Online;

  StreamSubscription<MqttConnectionStatus>? _statusSub;
  StreamSubscription<String>? _messageSub;
  StreamSubscription<bool>? _esp32StatusSub;

  // ── Joystick Timer ────────────────────────────────────
  Timer? _joystickTimer;
  double _leftX = 0, _leftY = 0;
  double _rightX = 0, _rightY = 0;

  ArmController() {
    _init();
  }

  /// Initialize: load saved settings and listen to MQTT status changes.
  Future<void> _init() async {
    await loadSettings();
    _statusSub = _mqttService.statusStream.listen((status) {
      _connectionStatus = status;
      // Reset ESP32 status when broker disconnects
      if (status == MqttConnectionStatus.disconnected) {
        _esp32Online = false;
      }
      notifyListeners();
    });
    _messageSub = _mqttService.connectionMessageStream.listen((msg) {
      _connectionMessage = msg;
      notifyListeners();
    });
    _esp32StatusSub = _mqttService.esp32StatusStream.listen((online) {
      _esp32Online = online;
      notifyListeners();
    });
  }

  // ════════════════════════════════════════════════════════
  //  SETTINGS PERSISTENCE
  // ════════════════════════════════════════════════════════

  /// Load connection settings from SharedPreferences.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _brokerIP = prefs.getString('mqtt_broker_ip') ?? '192.168.1.100';
    _port     = prefs.getInt('mqtt_port') ?? 1883;
    _espSSID  = prefs.getString('esp_ssid') ?? 'RobotArm-Setup';
    notifyListeners();
  }

  /// Save connection settings to SharedPreferences.
  Future<void> saveSettings(String ip, int port, String ssid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_broker_ip', ip);
    await prefs.setInt('mqtt_port', port);
    await prefs.setString('esp_ssid', ssid);
    _brokerIP = ip;
    _port = port;
    _espSSID = ssid;
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════
  //  MQTT CONNECTION
  // ════════════════════════════════════════════════════════

  /// Connect to the MQTT broker using current settings.
  Future<bool> connectMqtt() async {
    return await _mqttService.connect(_brokerIP, _port);
  }

  /// Disconnect from the MQTT broker.
  void disconnectMqtt() {
    _mqttService.disconnect();
  }

  /// Save settings and connect to MQTT.
  Future<bool> saveAndConnect(String ip, int port, String ssid) async {
    await saveSettings(ip, port, ssid);
    final success = await connectMqtt();
    if (success) {
      _sendBaseStop();  // Safety: ensure base is stopped on connect
    }
    return success;
  }

  /// Send base:90 (STOP) to ensure continuous servo is not spinning.
  void _sendBaseStop() {
    servos['base']!.baseWriteValue = 90;
    _mqttService.publish('base:90');
    debugPrint('[BASE] Safety STOP sent');
  }

  // ════════════════════════════════════════════════════════
  //  JOYSTICK HANDLING
  // ════════════════════════════════════════════════════════

  /// Update left joystick position (Base X, Shoulder Y).
  /// Starts a periodic timer to send MQTT commands every 100ms.
  void updateLeftJoystick(double x, double y) {
    final wasBaseActive = _leftX.abs() > 0.1;
    _leftX = x;
    _leftY = y;

    // If Base X axis just returned to center, send STOP immediately
    if (wasBaseActive && _leftX.abs() <= 0.1 && _isBaseMoving) {
      _isBaseMoving = false;
      _sendBaseStop();
      notifyListeners();
    }

    _ensureTimerRunning();
  }

  /// Update right joystick position (Elbow Y, Gripper X).
  void updateRightJoystick(double x, double y) {
    _rightX = x;
    _rightY = y;
    _ensureTimerRunning();
  }

  /// Check if any joystick is active (non-zero).
  bool get _anyJoystickActive =>
      _leftX.abs() > 0.1 || _leftY.abs() > 0.1 ||
      _rightX.abs() > 0.1 || _rightY.abs() > 0.1;

  /// Ensure the 100ms periodic timer is running while joysticks are active.
  void _ensureTimerRunning() {
    if (_joystickTimer != null && _joystickTimer!.isActive) return;

    _joystickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_anyJoystickActive) {
        _joystickTimer?.cancel();
        _joystickTimer = null;
        return;
      }
      _processJoystickInput();
    });
  }

  /// Process joystick input: calculate new angles and publish via MQTT.
  void _processJoystickInput() {
    // Left joystick: X → Base (360° continuous), Y → Shoulder (180°)
    if (_leftX.abs() > 0.1) {
      // Base: 360° continuous rotation
      // offset = speed * 5, clamped to keep value in 40–140 range
      int offset = (_leftX * _speed * 5).round();
      int writeValue = (90 + offset).clamp(40, 140);
      servos['base']!.baseWriteValue = writeValue;
      _mqttService.publish(servos['base']!.toPayload());
      _isBaseMoving = true;
    }
    if (_leftY.abs() > 0.1) {
      // Shoulder: 180° positional (Y axis: negative = up, positive = down)
      int step = (-_leftY * _speed).round();
      if (servos['shoulder']!.adjustAngle(step)) {
        _mqttService.publish(servos['shoulder']!.toPayload());
      }
    }

    // Right joystick: Y → Elbow, X → Gripper (both 180° positional)
    if (_rightY.abs() > 0.1) {
      int step = (-_rightY * _speed).round();
      if (servos['elbow']!.adjustAngle(step)) {
        _mqttService.publish(servos['elbow']!.toPayload());
      }
    }
    if (_rightX.abs() > 0.1) {
      int step = (_rightX * _speed).round();
      if (servos['gripper']!.adjustAngle(step)) {
        _mqttService.publish(servos['gripper']!.toPayload());
      }
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _joystickTimer?.cancel();
    _statusSub?.cancel();
    _messageSub?.cancel();
    _esp32StatusSub?.cancel();
    _mqttService.dispose();
    super.dispose();
  }
}
