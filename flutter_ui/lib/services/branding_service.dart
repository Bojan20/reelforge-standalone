/// Branding Service
///
/// Manages branding configurations for SlotLab:
/// - CRUD operations for branding configs
/// - Apply/revert branding
/// - Persistence via SharedPreferences
/// - Import/export branding configs
///
/// Created: 2026-01-30 (P4.18)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/branding_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing branding configurations
class BrandingService extends ChangeNotifier {
  BrandingService._();
  static final instance = BrandingService._();

  static const _prefsKeyConfigs = 'branding_configs';
  static const _prefsKeyActiveId = 'branding_active_id';

  // State
  final List<BrandingConfig> _configs = [];
  BrandingConfig? _activeConfig;
  bool _initialized = false;

  // Getters
  List<BrandingConfig> get configs => List.unmodifiable(_configs);
  BrandingConfig? get activeConfig => _activeConfig;
  bool get hasActiveConfig => _activeConfig != null;
  bool get initialized => _initialized;

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load saved configs
      final configsJson = prefs.getString(_prefsKeyConfigs);
      if (configsJson != null) {
        final configsList = jsonDecode(configsJson) as List;
        for (final json in configsList) {
          _configs.add(BrandingConfig.fromJson(json as Map<String, dynamic>));
        }
      }

      // Load active config ID
      final activeId = prefs.getString(_prefsKeyActiveId);
      if (activeId != null) {
        _activeConfig = _configs.firstWhere(
          (c) => c.id == activeId,
          orElse: () => BuiltInBrandingPresets.fluxForgeDefault(),
        );
      }

      // Add built-in presets if not present
      _ensureBuiltInPresets();

      _initialized = true;
      notifyListeners();
    } catch (e) {
      _ensureBuiltInPresets();
      _initialized = true;
    }
  }

  void _ensureBuiltInPresets() {
    final builtInIds = BuiltInBrandingPresets.all().map((c) => c.id).toSet();
    for (final preset in BuiltInBrandingPresets.all()) {
      if (!_configs.any((c) => c.id == preset.id)) {
        _configs.insert(0, preset);
      }
    }
  }

  /// Save configs to SharedPreferences
  Future<void> _saveConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = jsonEncode(_configs.map((c) => c.toJson()).toList());
      await prefs.setString(_prefsKeyConfigs, configsJson);
    } catch (e) { /* ignored */ }
  }

  /// Save active config ID
  Future<void> _saveActiveId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_activeConfig != null) {
        await prefs.setString(_prefsKeyActiveId, _activeConfig!.id);
      } else {
        await prefs.remove(_prefsKeyActiveId);
      }
    } catch (e) { /* ignored */ }
  }

  /// Create a new branding config
  Future<BrandingConfig> createConfig({
    required String name,
    BrandingColors? colors,
    BrandingFonts? fonts,
    BrandingAssets? assets,
    BrandingText? text,
    bool? showWatermark,
    double? watermarkOpacity,
  }) async {
    final config = BrandingConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      colors: colors,
      fonts: fonts,
      assets: assets,
      text: text,
      showWatermark: showWatermark ?? false,
      watermarkOpacity: watermarkOpacity ?? 0.3,
    );

    _configs.add(config);
    await _saveConfigs();
    notifyListeners();

    return config;
  }

  /// Update an existing config
  Future<void> updateConfig(BrandingConfig config) async {
    final index = _configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      _configs[index] = config.copyWith(updatedAt: DateTime.now());

      // Update active if this is the active config
      if (_activeConfig?.id == config.id) {
        _activeConfig = _configs[index];
      }

      await _saveConfigs();
      notifyListeners();
    }
  }

  /// Delete a config
  Future<void> deleteConfig(String configId) async {
    // Don't delete built-in configs
    if (configId.startsWith('fluxforge_') ||
        configId.startsWith('dark_gold_') ||
        configId.startsWith('neon_') ||
        configId.startsWith('classic_') ||
        configId.startsWith('ocean_')) {
      return;
    }

    _configs.removeWhere((c) => c.id == configId);

    // Clear active if this was the active config
    if (_activeConfig?.id == configId) {
      _activeConfig = null;
      await _saveActiveId();
    }

    await _saveConfigs();
    notifyListeners();
  }

  /// Apply a branding config
  Future<void> applyConfig(String configId) async {
    final config = _configs.firstWhere(
      (c) => c.id == configId,
      orElse: () => BuiltInBrandingPresets.fluxForgeDefault(),
    );

    _activeConfig = config;
    await _saveActiveId();
    notifyListeners();
  }

  /// Revert to default branding
  Future<void> revertToDefault() async {
    _activeConfig = null;
    await _saveActiveId();
    notifyListeners();
  }

  /// Duplicate a config
  Future<BrandingConfig> duplicateConfig(String configId) async {
    final source = _configs.firstWhere(
      (c) => c.id == configId,
      orElse: () => BuiltInBrandingPresets.fluxForgeDefault(),
    );

    final duplicate = BrandingConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: '${source.name} (Copy)',
      colors: source.colors,
      fonts: source.fonts,
      assets: source.assets,
      text: source.text,
      showWatermark: source.showWatermark,
      watermarkOpacity: source.watermarkOpacity,
    );

    _configs.add(duplicate);
    await _saveConfigs();
    notifyListeners();

    return duplicate;
  }

  /// Export config to JSON string
  String exportConfig(String configId) {
    final config = _configs.firstWhere(
      (c) => c.id == configId,
      orElse: () => BuiltInBrandingPresets.fluxForgeDefault(),
    );
    return config.toJsonString();
  }

  /// Import config from JSON string
  Future<BrandingConfig?> importConfig(String jsonString) async {
    try {
      final config = BrandingConfig.fromJsonString(jsonString);

      // Generate new ID to avoid conflicts
      final importedConfig = config.copyWith(
        id: 'imported_${DateTime.now().millisecondsSinceEpoch}',
        name: '${config.name} (Imported)',
      );

      _configs.add(importedConfig);
      await _saveConfigs();
      notifyListeners();

      return importedConfig;
    } catch (e) {
      return null;
    }
  }

  /// Get config by ID
  BrandingConfig? getConfig(String configId) {
    try {
      return _configs.firstWhere((c) => c.id == configId);
    } catch (e) {
      return null;
    }
  }

  /// Check if a config is built-in
  bool isBuiltIn(String configId) {
    final builtInIds = BuiltInBrandingPresets.all().map((c) => c.id).toSet();
    return builtInIds.contains(configId);
  }
}
