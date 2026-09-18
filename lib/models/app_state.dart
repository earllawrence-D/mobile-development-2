import 'package:flutter/material.dart';

/// Holds every piece of state that needs to be shared across screens:
/// the light/dark theme toggle, the user's profile name, and a running
/// log of activity entries recorded from the Activity screens.
///
/// Any widget wrapped in a Consumer/context.watch<AppState>() rebuilds
/// automatically whenever notifyListeners() fires.
class AppState extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  String _profileName = 'Student';
  final List<String> _activityLog = [];

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  String get profileName => _profileName;
  List<String> get activityLog => List.unmodifiable(_activityLog);

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Attempts to set the profile name to [name]. Leading/trailing
  /// whitespace is trimmed and blank names are rejected.
  ///
  /// Returns `true` if the name was applied, or `false` when the input is
  /// empty/whitespace-only. Callers can compare [profileName] before and
  /// after the call to detect whether anything actually changed (for
  /// example, to show feedback in the UI).
  bool updateProfileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    _profileName = trimmed;
    notifyListeners();
    return true;
  }

  void logActivity(String entry) {
    _activityLog.insert(0, entry);
    notifyListeners();
  }
}