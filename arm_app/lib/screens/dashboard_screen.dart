import 'package:flutter/material.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:provider/provider.dart';
import '../providers/arm_controller.dart';
import '../services/mqtt_service.dart';
import '../widgets/speed_slider.dart';
import 'settings_screen.dart';

/// Main dashboard screen with dual joystick control for the robot arm.
///
/// Layout:
/// - AppBar: connection indicator + settings button
/// - Servo angle display cards
/// - Dual joystick area (left: elbow/gripper, right: base/shoulder)
/// - Speed slider at bottom
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.precision_manufacturing, color: Color(0xFF818CF8), size: 24),
            SizedBox(width: 10),
            Text(
              'Arm Controller',
              style: TextStyle(
                color: Color(0xFFF1F5F9),
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF94A3B8)),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<ArmController>(
          builder: (context, ctrl, _) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left Joystick (Base / Shoulder) ──
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    child: _JoystickPanel(
                      title: 'Base / Shoulder',
                      xLabel: 'Base',
                      yLabel: 'Shoulder',
                      color: const Color(0xFF6366F1),
                      onStickUpdate: (details) {
                        ctrl.updateLeftJoystick(details.x, details.y);
                      },
                      onStickRelease: () {
                        ctrl.updateLeftJoystick(0, 0);
                      },
                    ),
                  ),
                ),

                // ── Middle Panel (Status, Servos, Speed) ──
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        _DualStatusRow(
                          brokerStatus: ctrl.connectionStatus,
                          esp32Online: ctrl.esp32Online,
                        ),
                        const SizedBox(height: 12),
                        _ServoAngleRow(servos: ctrl.servos),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SpeedSlider(
                            value: ctrl.speed,
                            onChanged: (v) => ctrl.speed = v,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Right Joystick (Elbow / Gripper) ──
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                    child: _JoystickPanel(
                      title: 'Elbow / Gripper',
                      xLabel: 'Gripper',
                      yLabel: 'Elbow',
                      color: const Color(0xFF8B5CF6),
                      onStickUpdate: (details) {
                        ctrl.updateRightJoystick(details.x, details.y);
                      },
                      onStickRelease: () {
                        ctrl.updateRightJoystick(0, 0);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SERVO ANGLE DISPLAY ROW
// ═══════════════════════════════════════════════════════════

class _ServoAngleRow extends StatelessWidget {
  final Map<String, dynamic> servos;

  const _ServoAngleRow({required this.servos});

  @override
  Widget build(BuildContext context) {
    final servoList = servos.entries.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              _buildServoCard(servoList[0].key, servoList[0].value),
              _buildServoCard(servoList[1].key, servoList[1].value),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildServoCard(servoList[2].key, servoList[2].value),
              _buildServoCard(servoList[3].key, servoList[3].value),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildServoCard(String key, dynamic servo) {
    // For continuous rotation servo (Base), show speed/direction
    String displayValue;
    Color valueColor;
    if (servo.isContinuous) {
      final int val = servo.baseWriteValue;
      if (val == 90) {
        displayValue = 'STOP';
        valueColor = const Color(0xFF94A3B8);
      } else if (val < 90) {
        displayValue = 'CW ${90 - val}';
        valueColor = const Color(0xFF4ADE80);
      } else {
        displayValue = 'CCW ${val - 90}';
        valueColor = const Color(0xFF818CF8);
      }
    } else {
      displayValue = '${servo.currentAngle}°';
      valueColor = const Color(0xFFF1F5F9);
    }

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155), width: 1),
        ),
        child: Column(
          children: [
            Text(
              '${_capitalize(key)}${servo.isContinuous ? ' 360°' : ''}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              displayValue,
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ═══════════════════════════════════════════════════════════
//  JOYSTICK PANEL WIDGET
// ═══════════════════════════════════════════════════════════

class _JoystickPanel extends StatelessWidget {
  final String title;
  final String xLabel;
  final String yLabel;
  final Color color;
  final void Function(StickDragDetails) onStickUpdate;
  final VoidCallback onStickRelease;

  const _JoystickPanel({
    required this.title,
    required this.xLabel,
    required this.yLabel,
    required this.color,
    required this.onStickUpdate,
    required this.onStickRelease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Title
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          // Axis labels
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'X: $xLabel',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
              const SizedBox(width: 8),
              Text(
                'Y: $yLabel',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          // Joystick
          Joystick(
            mode: JoystickMode.all,
            period: const Duration(milliseconds: 100),
            listener: onStickUpdate,
            onStickDragEnd: onStickRelease,
            base: JoystickBase(
              decoration: JoystickBaseDecoration(
                color: const Color(0xFF0F172A),
                drawOuterCircle: true,
                outerCircleColor: color.withValues(alpha: 0.25),
                drawInnerCircle: true,
                innerCircleColor: color.withValues(alpha: 0.15),
              ),
              size: 140,
            ),
            stick: JoystickStick(
              decoration: JoystickStickDecoration(
                color: color,
                shadowColor: color.withValues(alpha: 0.5),
              ),
              size: 40,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  DUAL STATUS INDICATORS (Broker + ESP32)
// ═══════════════════════════════════════════════════════════

class _DualStatusRow extends StatelessWidget {
  final MqttConnectionStatus brokerStatus;
  final bool esp32Online;

  const _DualStatusRow({
    required this.brokerStatus,
    required this.esp32Online,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Broker status
          Expanded(
            child: _StatusCard(
              icon: Icons.dns,
              label: 'Broker',
              isOnline: brokerStatus == MqttConnectionStatus.connected,
              isConnecting: brokerStatus == MqttConnectionStatus.connecting,
            ),
          ),
          const SizedBox(width: 10),
          // ESP32 status
          Expanded(
            child: _StatusCard(
              icon: Icons.memory,
              label: 'ESP32',
              isOnline: esp32Online,
              isConnecting: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOnline;
  final bool isConnecting;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.isOnline,
    required this.isConnecting,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    final String statusText;

    if (isConnecting) {
      dotColor = const Color(0xFFFBBF24); // amber
      statusText = 'Connecting...';
    } else if (isOnline) {
      dotColor = const Color(0xFF4ADE80); // green
      statusText = 'Online';
    } else {
      dotColor = const Color(0xFFF87171); // red
      statusText = 'Offline';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF64748B), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: dotColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
