/// Theme Mode Provider
///
/// Manages switching between Classic and Liquid Glass theme modes.

import 'package:flutter/material.dart';

enum AppThemeMode {
  classic,
  liquidGlass,
}

class ThemeModeProvider extends ChangeNotifier {
  // Default to Classic mode
  AppThemeMode _mode = AppThemeMode.classic;

  AppThemeMode get mode => _mode;

  bool get isGlassMode => _mode == AppThemeMode.liquidGlass;
  bool get isClassicMode => _mode == AppThemeMode.classic;

  void setMode(AppThemeMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
  }

  void toggleMode() {
    _mode = _mode == AppThemeMode.classic
        ? AppThemeMode.liquidGlass
        : AppThemeMode.classic;
    notifyListeners();
  }

  void setGlassMode() => setMode(AppThemeMode.liquidGlass);
  void setClassicMode() => setMode(AppThemeMode.classic);

  @override
  void dispose() {
    super.dispose();
  }
}
