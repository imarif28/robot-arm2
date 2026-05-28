import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/arm_controller.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';

/// Entry point for the Arm Controller Flutter application.
///
/// Sets up the Provider-based state management and navigates
/// to Settings if not yet configured, otherwise to Dashboard.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const ArmControllerApp());
  });
}

class ArmControllerApp extends StatelessWidget {
  const ArmControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ArmController(),
      child: MaterialApp(
        title: 'Arm Controller',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorSchemeSeed: const Color(0xFF818CF8),
          fontFamily: 'Roboto',
          useMaterial3: true,
        ),
        // Define named routes
        initialRoute: '/',
        routes: {
          '/': (context) => const DashboardScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}
