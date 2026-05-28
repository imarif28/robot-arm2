import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/arm_controller.dart';
import '../services/mqtt_service.dart';
import '../widgets/connection_indicator.dart';

/// Settings screen for configuring MQTT broker connection.
///
/// Allows user to input:
/// - MQTT Broker IP address
/// - Port number
/// - ESP32 WiFiManager SSID (informational)
///
/// Settings are persisted via SharedPreferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _ssidController;

  @override
  void initState() {
    super.initState();
    final controller = context.read<ArmController>();
    _ipController   = TextEditingController(text: controller.brokerIP);
    _portController = TextEditingController(text: controller.port.toString());
    _ssidController = TextEditingController(text: controller.espSSID);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _ssidController.dispose();
    super.dispose();
  }

  /// Validate, save settings, and attempt MQTT connection.
  Future<void> _saveAndConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = context.read<ArmController>();
    final ip   = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 1883;
    final ssid = _ssidController.text.trim();

    final success = await controller.saveAndConnect(ip, port, ssid);

    if (mounted) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                success
                    ? 'Connected to MQTT broker!'
                    : 'Failed to connect. Check IP & port.',
              ),
            ],
          ),
          backgroundColor: success
              ? const Color(0xFF059669)
              : const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );

      if (success) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: const Color(0xFFF1F5F9),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Connection Status Card ──
              Consumer<ArmController>(
                builder: (context, ctrl, _) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wifi, color: Color(0xFF94A3B8), size: 22),
                            const SizedBox(width: 12),
                            const Text(
                              'MQTT Status',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            ConnectionIndicator(status: ctrl.connectionStatus),
                          ],
                        ),
                        if (ctrl.connectionMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            ctrl.connectionMessage,
                            style: const TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ]
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              // ── Section Title ──
              const _SectionTitle(icon: Icons.dns, label: 'MQTT Broker'),
              const SizedBox(height: 12),

              // ── Broker IP Field ──
              _StyledTextField(
                controller: _ipController,
                label: 'Broker IP Address',
                hint: '192.168.1.100',
                icon: Icons.lan,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'IP address is required';
                  }
                  final parts = value.split('.');
                  if (parts.length != 4) return 'Invalid IP format';
                  for (final p in parts) {
                    final n = int.tryParse(p);
                    if (n == null || n < 0 || n > 255) return 'Invalid IP format';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Port Field ──
              _StyledTextField(
                controller: _portController,
                label: 'Port',
                hint: '1883',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Port is required';
                  final port = int.tryParse(value);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Port must be 1–65535';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // ── ESP32 Section ──
              const _SectionTitle(icon: Icons.memory, label: 'ESP32 WiFiManager'),
              const SizedBox(height: 12),

              _StyledTextField(
                controller: _ssidController,
                label: 'ESP32 AP SSID',
                hint: 'RobotArm-Setup',
                icon: Icons.wifi_tethering,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'SSID is required';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF818CF8).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF818CF8), size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Connect to this SSID on your phone WiFi settings to configure the ESP32 WiFi connection.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              Consumer<ArmController>(
                builder: (context, ctrl, _) {
                  final isConnecting = ctrl.connectionStatus == MqttConnectionStatus.connecting;
                  return SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: isConnecting ? null : _saveAndConnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF818CF8),
                        disabledBackgroundColor: const Color(0xFF4338CA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: isConnecting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  ctrl.connectionStatus == MqttConnectionStatus.disconnected && ctrl.connectionMessage.contains('Failed')
                                      ? Icons.refresh
                                      : Icons.save,
                                  size: 20
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  ctrl.connectionStatus == MqttConnectionStatus.disconnected && ctrl.connectionMessage.contains('Failed')
                                      ? 'Retry Connection'
                                      : 'Save & Connect',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // ── Disconnect Button ──
              Consumer<ArmController>(
                builder: (context, ctrl, _) {
                  if (ctrl.connectionStatus == MqttConnectionStatus.disconnected) {
                    return const SizedBox.shrink();
                  }
                  return SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => ctrl.disconnectMqtt(),
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Disconnect'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF87171),
                        side: const BorderSide(color: Color(0xFFF87171)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section Title Helper Widget ──
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF818CF8), size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ── Styled Text Field Helper Widget ──
class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _StyledTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
        labelStyle: const TextStyle(color: Color(0xFF64748B)),
        hintStyle: const TextStyle(color: Color(0xFF475569)),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
