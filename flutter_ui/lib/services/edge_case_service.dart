/// Edge Case Preset Service
///
/// Manages edge case presets for slot testing:
/// - Load/save custom presets
/// - Apply presets to game state
/// - Preset history for quick access
///
/// Created: 2026-01-30 (P4.14)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/edge_case_models.dart';
import '../providers/slot_lab/slot_lab_coordinator.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EDGE CASE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing and applying edge case presets
class EdgeCaseService extends ChangeNotifier {
  EdgeCaseService._();
  static final instance = EdgeCaseService._();

  // State
  List<EdgeCasePreset> _customPresets = [];
  List<String> _recentPresetIds = [];
  EdgeCasePreset? _activePreset;
  bool _isInitialized = false;

  // Getters
  List<EdgeCasePreset> get customPresets => List.unmodifiable(_customPresets);
  List<EdgeCasePreset> get allPresets => [
    ...BuiltInEdgeCasePresets.all(),
    ..._customPresets,
  ];
  List<String> get recentPresetIds => List.unmodifiable(_recentPresetIds);
  EdgeCasePreset? get activePreset => _activePreset;
  bool get isInitialized => _isInitialized;

  /// Get recent presets
  List<EdgeCasePreset> get recentPresets {
    return _recentPresetIds
        .map((id) => getPresetById(id))
        .whereType<EdgeCasePreset>()
        .toList();
  }

  /// Initialize service
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _loadCustomPresets();
      await _loadRecentHistory();
      _isInitialized = true;
    } catch (e) { /* ignored */ }
  }

  /// Get preset by ID
  EdgeCasePreset? getPresetById(String id) {
    // Check built-in first
    final builtIn = BuiltInEdgeCasePresets.byId(id);
    if (builtIn != null) return builtIn;

    // Check custom
    try {
      return _customPresets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get presets by category
  List<EdgeCasePreset> getPresetsByCategory(EdgeCaseCategory category) {
    return allPresets.where((p) => p.category == category).toList();
  }

  /// Search presets
  List<EdgeCasePreset> searchPresets(String query) {
    final lower = query.toLowerCase();
    return allPresets.where((p) {
      return p.name.toLowerCase().contains(lower) ||
          p.description.toLowerCase().contains(lower) ||
          p.tags.any((t) => t.toLowerCase().contains(lower));
    }).toList();
  }

  /// Apply a preset to the game state
  Future<ApplyResult> applyPreset(
    EdgeCasePreset preset, {
    SlotLabProvider? slotLabProvider,
  }) async {
    try {
      final config = preset.config;
      final changes = <String>[];

      // Apply betting config
      if (config.betAmount != null && slotLabProvider != null) {
        slotLabProvider.setBetAmount(config.betAmount!);
        changes.add('Bet: ${config.betAmount}');
      }

      if (config.maxBet == true && slotLabProvider != null) {
        slotLabProvider.setBetAmount(1000.0); // Max bet value
        changes.add('Max bet applied');
      }

      if (config.minBet == true && slotLabProvider != null) {
        slotLabProvider.setBetAmount(0.01); // Min bet value
        changes.add('Min bet applied');
      }

      // Apply balance config (stored in service, not provider)
      if (config.balance != null) {
        // Balance is visual-only in SlotLab simulation
        changes.add('Balance: ${config.balance}');
      }

      // Apply audio config
      if (config.musicEnabled != null) {
        try {
          NativeFFI.instance.setBusMute(1, !config.musicEnabled!);
          changes.add('Music: ${config.musicEnabled! ? "on" : "off"}');
        } catch (_) { /* ignored */ }
      }

      if (config.sfxEnabled != null) {
        try {
          NativeFFI.instance.setBusMute(2, !config.sfxEnabled!);
          changes.add('SFX: ${config.sfxEnabled! ? "on" : "off"}');
        } catch (_) { /* ignored */ }
      }

      if (config.volume != null) {
        try {
          NativeFFI.instance.setMasterVolume(config.volume!);
          changes.add('Volume: ${(config.volume! * 100).toInt()}%');
        } catch (_) { /* ignored */ }
      }

      // Apply feature config (stored in config, visual-only in simulation)
      if (config.multiplier != null) {
        changes.add('Multiplier: ${config.multiplier}x');
      }

      // Apply turbo mode (noted in changes)
      if (config.turboMode != null) {
        changes.add('Turbo: ${config.turboMode! ? "on" : "off"}');
      }

      // Apply signal overrides (noted in changes)
      if (config.signalOverrides != null) {
        for (final entry in config.signalOverrides!.entries) {
          changes.add('Signal ${entry.key}: ${entry.value}');
        }
      }

      // Track as active preset
      _activePreset = preset;
      _addToRecent(preset.id);
      notifyListeners();


      return ApplyResult(
        success: true,
        preset: preset,
        changes: changes,
      );
    } catch (e) {
      return ApplyResult(
        success: false,
        preset: preset,
        error: e.toString(),
      );
    }
  }

  /// Clear active preset
  void clearActivePreset() {
    _activePreset = null;
    notifyListeners();
  }

  /// Save a custom preset
  Future<void> savePreset(EdgeCasePreset preset) async {
    // Ensure it has a valid ID
    final toSave = preset.id.isEmpty
        ? preset.copyWith(id: 'custom_${DateTime.now().millisecondsSinceEpoch}')
        : preset;

    // Check if updating existing
    final existingIndex = _customPresets.indexWhere((p) => p.id == toSave.id);
    if (existingIndex >= 0) {
      _customPresets[existingIndex] = toSave;
    } else {
      _customPresets.add(toSave);
    }

    await _saveCustomPresets();
    notifyListeners();
  }

  /// Delete a custom preset
  Future<void> deletePreset(String id) async {
    _customPresets.removeWhere((p) => p.id == id);
    _recentPresetIds.remove(id);

    if (_activePreset?.id == id) {
      _activePreset = null;
    }

    await _saveCustomPresets();
    await _saveRecentHistory();
    notifyListeners();
  }

  /// Duplicate a preset
  Future<EdgeCasePreset> duplicatePreset(EdgeCasePreset preset) async {
    final duplicate = preset.copyWith(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: '${preset.name} (Copy)',
      isBuiltIn: false,
      createdAt: DateTime.now(),
    );

    await savePreset(duplicate);
    return duplicate;
  }

  /// Export presets to JSON
  String exportToJson({bool includeBuiltIn = false}) {
    final presets = includeBuiltIn ? allPresets : _customPresets;
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'presets': presets.map((p) => p.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Import presets from JSON
  Future<int> importFromJson(String json) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final presetList = data['presets'] as List<dynamic>;

      var imported = 0;
      for (final presetJson in presetList) {
        final preset = EdgeCasePreset.fromJson(presetJson as Map<String, dynamic>);
        // Skip built-in presets
        if (!preset.isBuiltIn) {
          await savePreset(preset.copyWith(isBuiltIn: false));
          imported++;
        }
      }

      return imported;
    } catch (e) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _addToRecent(String id) {
    _recentPresetIds.remove(id);
    _recentPresetIds.insert(0, id);
    if (_recentPresetIds.length > 10) {
      _recentPresetIds = _recentPresetIds.sublist(0, 10);
    }
    _saveRecentHistory();
  }

  static const String _presetsKey = 'edge_case_custom_presets';
  static const String _recentKey = 'edge_case_recent_history';

  Future<void> _loadCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_presetsKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final presetList = data['presets'] as List<dynamic>;
        _customPresets = presetList
            .map((p) => EdgeCasePreset.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) { /* ignored */ }
  }

  Future<void> _saveCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'version': 1,
        'presets': _customPresets.map((p) => p.toJson()).toList(),
      };
      await prefs.setString(_presetsKey, jsonEncode(data));
    } catch (e) { /* ignored */ }
  }

  Future<void> _loadRecentHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_recentKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _recentPresetIds = (data['recent'] as List<dynamic>).cast<String>();
      }
    } catch (e) { /* ignored */ }
  }

  Future<void> _saveRecentHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {'recent': _recentPresetIds};
      await prefs.setString(_recentKey, jsonEncode(data));
    } catch (e) { /* ignored */ }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// APPLY RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of applying an edge case preset
class ApplyResult {
  final bool success;
  final EdgeCasePreset preset;
  final List<String> changes;
  final String? error;

  const ApplyResult({
    required this.success,
    required this.preset,
    this.changes = const [],
    this.error,
  });

  String get summary {
    if (!success) return 'Failed: ${error ?? "Unknown error"}';
    if (changes.isEmpty) return 'No changes applied';
    return changes.join(', ');
  }
}
