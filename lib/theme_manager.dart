import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the theme mode (Light/Dark/System) for the application.
/// Uses ChangeNotifier to notify widgets about theme changes.
/// Stores the selected theme in SharedPreferences for persistence.
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // Default: System setting
  bool _isInitialized = false;

  ThemeMode get themeMode => _themeMode;

  /// Initializes the theme by loading the saved preference from SharedPreferences.
  /// This method should be called once at application startup.
  Future<void> initTheme() async {
    if (_isInitialized) return; // Initialize only once
    final prefs = await SharedPreferences.getInstance();
    final bool? isDarkMode = prefs.getBool('isDarkMode');
    if (isDarkMode != null) {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system; // Or default to Light if nothing is saved
    }
    _isInitialized = true;
    notifyListeners(); // Notify listeners about initialization
  }

  /// Toggles the current theme between Light and Dark mode.
  /// Saves the new preference to SharedPreferences.
  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
      await prefs.setBool('isDarkMode', true);
    } else {
      _themeMode = ThemeMode.light;
      await prefs.setBool('isDarkMode', false);
    }
    notifyListeners(); // Notify listeners about the change
  }

  /// Explicitly sets the theme to Light mode and saves the preference.
  Future<void> setLightMode() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.light;
    await prefs.setBool('isDarkMode', false);
    notifyListeners();
  }

  /// Explicitly sets the theme to Dark mode and saves the preference.
  Future<void> setDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.dark;
    await prefs.setBool('isDarkMode', true);
    notifyListeners();
  }
}
