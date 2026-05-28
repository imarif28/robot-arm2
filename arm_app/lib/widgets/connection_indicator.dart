import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';

/// A small animated dot that indicates the MQTT connection status.
///
/// - Green = connected
/// - Red = disconnected
/// - Orange pulsing = connecting
class ConnectionIndicator extends StatefulWidget {
  final MqttConnectionStatus status;
  final double size;

  const ConnectionIndicator({
    super.key,
    required this.status,
    this.size = 12,
  });

  @override
  State<ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<ConnectionIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.status == MqttConnectionStatus.connecting) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ConnectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == MqttConnectionStatus.connecting) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.status) {
      case MqttConnectionStatus.connected:
        return const Color(0xFF4ADE80); // green
      case MqttConnectionStatus.connecting:
        return const Color(0xFFFBBF24); // amber
      case MqttConnectionStatus.disconnected:
        return const Color(0xFFF87171); // red
    }
  }

  String get _label {
    switch (widget.status) {
      case MqttConnectionStatus.connected:
        return 'Connected';
      case MqttConnectionStatus.connecting:
        return 'Connecting...';
      case MqttConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _color.withValues(alpha: _pulseAnimation.value),
                boxShadow: [
                  BoxShadow(
                    color: _color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _label,
              style: TextStyle(
                color: _color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }
}
