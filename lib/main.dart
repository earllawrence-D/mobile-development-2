import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_state.dart';
import 'models/network_monitor.dart';
import 'screens/home_dashboard.dart';
import 'screens/activity_one_screen.dart';
import 'screens/activity_two_screen.dart';
import 'screens/network_monitor_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        // NetworkMonitor is global too: it subscribes to the connectivity
        // stream once at app startup and keeps ticking/queuing/resuming
        // simulated requests no matter which screen is on top.
        ChangeNotifierProvider(create: (_) => NetworkMonitor()),
      ],
      child: const LabCompilerApp(),
    ),
  );
}

/// Root widget. Reads the global [AppState] so theme changes made on the
/// Settings screen propagate instantly to every screen in the app.
class LabCompilerApp extends StatelessWidget {
  const LabCompilerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      title: 'Lab Compiler',
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeDashboard(),
        '/activity-one': (context) => const ActivityOneScreen(),
        '/activity-two': (context) => const ActivityTwoScreen(),
        '/network-monitor': (context) => const NetworkMonitorScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}