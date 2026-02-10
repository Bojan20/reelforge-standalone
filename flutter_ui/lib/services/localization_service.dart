/// Localization Service — P3-08
///
/// Manages application language settings with persistence.
/// Supports English, Serbian, German with easy extensibility.
///
/// Usage:
///   // Initialize at app startup
///   await LocalizationService.instance.init();
///
///   // Get current locale
///   final locale = LocalizationService.instance.currentLocale;
///
///   // Change language
///   LocalizationService.instance.setLocale(Locale('sr'));
///
///   // Listen for changes
///   LocalizationService.instance.addListener(() => rebuild());
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported locales with display names
class SupportedLocale {
  final Locale locale;
  final String displayName;
  final String nativeName;
  final String flag;

  const SupportedLocale({
    required this.locale,
    required this.displayName,
    required this.nativeName,
    required this.flag,
  });
}

/// Available languages
const List<SupportedLocale> kSupportedLocales = [
  SupportedLocale(
    locale: Locale('en'),
    displayName: 'English',
    nativeName: 'English',
    flag: '🇺🇸',
  ),
  SupportedLocale(
    locale: Locale('sr'),
    displayName: 'Serbian',
    nativeName: 'Srpski',
    flag: '🇷🇸',
  ),
  SupportedLocale(
    locale: Locale('de'),
    displayName: 'German',
    nativeName: 'Deutsch',
    flag: '🇩🇪',
  ),
];

/// Localization service singleton
class LocalizationService extends ChangeNotifier {
  LocalizationService._();
  static final LocalizationService instance = LocalizationService._();

  static const String _prefsKey = 'fluxforge_locale';

  SharedPreferences? _prefs;
  Locale _currentLocale = const Locale('en');
  bool _initialized = false;

  /// Current locale
  Locale get currentLocale => _currentLocale;

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// Get current locale info
  SupportedLocale get currentLocaleInfo {
    return kSupportedLocales.firstWhere(
      (l) => l.locale.languageCode == _currentLocale.languageCode,
      orElse: () => kSupportedLocales.first,
    );
  }

  /// Initialize from SharedPreferences
  Future<void> init() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    final savedCode = _prefs?.getString(_prefsKey);

    if (savedCode != null) {
      final supported = kSupportedLocales.any(
        (l) => l.locale.languageCode == savedCode,
      );
      if (supported) {
        _currentLocale = Locale(savedCode);
      }
    }

    _initialized = true;
    notifyListeners();
  }

  /// Set current locale
  Future<void> setLocale(Locale locale) async {
    // Validate locale is supported
    final isSupported = kSupportedLocales.any(
      (l) => l.locale.languageCode == locale.languageCode,
    );

    if (!isSupported) {
      return;
    }

    if (_currentLocale.languageCode == locale.languageCode) {
      return; // No change
    }

    _currentLocale = locale;
    await _prefs?.setString(_prefsKey, locale.languageCode);

    notifyListeners();
  }

  /// Set locale by language code
  Future<void> setLocaleByCode(String languageCode) async {
    await setLocale(Locale(languageCode));
  }

  /// Get all supported locales
  List<Locale> get supportedLocales {
    return kSupportedLocales.map((l) => l.locale).toList();
  }

  /// Check if a locale is supported
  bool isLocaleSupported(Locale locale) {
    return kSupportedLocales.any(
      (l) => l.locale.languageCode == locale.languageCode,
    );
  }

  /// Get display name for a locale
  String getDisplayName(Locale locale) {
    final info = kSupportedLocales.firstWhere(
      (l) => l.locale.languageCode == locale.languageCode,
      orElse: () => kSupportedLocales.first,
    );
    return info.displayName;
  }

  /// Get native name for a locale
  String getNativeName(Locale locale) {
    final info = kSupportedLocales.firstWhere(
      (l) => l.locale.languageCode == locale.languageCode,
      orElse: () => kSupportedLocales.first,
    );
    return info.nativeName;
  }

  /// Get flag emoji for a locale
  String getFlag(Locale locale) {
    final info = kSupportedLocales.firstWhere(
      (l) => l.locale.languageCode == locale.languageCode,
      orElse: () => kSupportedLocales.first,
    );
    return info.flag;
  }

  /// Reset to default (English)
  Future<void> reset() async {
    await setLocale(const Locale('en'));
  }
}
