/// ALE Auto Configurator
///
/// Configures Adaptive Layer Engine (ALE) profile from template.
/// Sets up music layering system with context-aware transitions via FFI.
///
/// P3-12: Template Gallery
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/template_models.dart';
import '../../providers/ale_provider.dart';
import '../service_locator.dart';

/// Configures ALE system from template
class AleAutoConfigurator {
  /// Configure ALE profile from template
  ///
  /// Returns the number of contexts configured
  int configureAll(BuiltTemplate template) {
    final aleProvider = sl<AleProvider>();

    // Build ALE profile JSON from template
    final profileJson = _buildProfileJson(template);

    // Load profile via FFI
    final success = aleProvider.loadProfile(jsonEncode(profileJson));

    if (success) {
      debugPrint('[AleAutoConfigurator] ✅ Loaded ALE profile with ${template.source.aleContexts.length} contexts');
      return template.source.aleContexts.isNotEmpty
          ? template.source.aleContexts.length
          : 5; // Default context count
    } else {
      debugPrint('[AleAutoConfigurator] ⚠️ Failed to load ALE profile, creating new');

      // Try creating a new profile
      final created = aleProvider.createNewProfile(
        gameName: template.source.name,
        author: template.source.author,
      );

      if (created) {
        debugPrint('[AleAutoConfigurator] ✅ Created new ALE profile');
        return 5; // Default contexts
      }

      debugPrint('[AleAutoConfigurator] ❌ Failed to create ALE profile');
      return 0;
    }
  }

  /// Build ALE profile JSON from template
  Map<String, dynamic> _buildProfileJson(BuiltTemplate template) {
    final contexts = template.source.aleContexts.isNotEmpty
        ? template.source.aleContexts.map((c) => _contextToJson(c)).toList()
        : _buildDefaultContexts();

    return {
      'version': '1.0',
      'game': template.source.name,
      'author': template.source.author,
      'contexts': contexts,
      'signals': _buildDefaultSignals(),
      'rules': _buildDefaultRules(template),
      'stability': _buildStabilityConfig(),
      'transitions': _buildTransitionProfiles(),
    };
  }

  /// Convert template context to ALE JSON format
  Map<String, dynamic> _contextToJson(TemplateAleContext context) {
    return {
      'id': context.id,
      'name': context.name,
      'layers': context.layers.map((layer) => {
        'index': layer.index,
        'asset_id': layer.assetPattern,
        'base_volume': layer.baseVolume,
      }).toList(),
      'entry_stages': context.entryStages,
      'exit_stages': context.exitStages,
      'entry_transition': 'crossfade', // Default transition
      'exit_transition': 'crossfade',
    };
  }

  /// Build default contexts for slot games
  List<Map<String, dynamic>> _buildDefaultContexts() {
    return [
      {
        'id': 'base_game',
        'name': 'Base Game',
        'layers': [
          {'index': 0, 'asset_id': 'ambient_bed', 'base_volume': 0.8},
          {'index': 1, 'asset_id': 'light_rhythm', 'base_volume': 0.85},
          {'index': 2, 'asset_id': 'medium_energy', 'base_volume': 0.9},
          {'index': 3, 'asset_id': 'high_energy', 'base_volume': 0.95},
          {'index': 4, 'asset_id': 'full_intensity', 'base_volume': 1.0},
        ],
        'entry_transition': 'crossfade',
        'exit_transition': 'crossfade',
      },
      {
        'id': 'free_spins',
        'name': 'Free Spins',
        'layers': [
          {'index': 0, 'asset_id': 'fs_intro', 'base_volume': 0.9},
          {'index': 1, 'asset_id': 'fs_building', 'base_volume': 0.92},
          {'index': 2, 'asset_id': 'fs_action', 'base_volume': 0.95},
          {'index': 3, 'asset_id': 'fs_climax', 'base_volume': 0.98},
          {'index': 4, 'asset_id': 'fs_peak', 'base_volume': 1.0},
        ],
        'entry_transition': 'beat_sync',
        'exit_transition': 'bar_sync',
      },
      {
        'id': 'big_win',
        'name': 'Big Win',
        'layers': [
          {'index': 0, 'asset_id': 'win_fanfare', 'base_volume': 1.0},
          {'index': 1, 'asset_id': 'win_celebration', 'base_volume': 1.0},
          {'index': 2, 'asset_id': 'win_epic', 'base_volume': 1.0},
        ],
        'entry_transition': 'immediate',
        'exit_transition': 'crossfade',
      },
      {
        'id': 'hold_win',
        'name': 'Hold & Win',
        'layers': [
          {'index': 0, 'asset_id': 'hold_suspense', 'base_volume': 0.85},
          {'index': 1, 'asset_id': 'hold_building', 'base_volume': 0.9},
          {'index': 2, 'asset_id': 'hold_tension', 'base_volume': 0.95},
          {'index': 3, 'asset_id': 'hold_climax', 'base_volume': 1.0},
        ],
        'entry_transition': 'beat_sync',
        'exit_transition': 'phrase_sync',
      },
      {
        'id': 'bonus',
        'name': 'Bonus Game',
        'layers': [
          {'index': 0, 'asset_id': 'bonus_intro', 'base_volume': 0.9},
          {'index': 1, 'asset_id': 'bonus_active', 'base_volume': 0.92},
          {'index': 2, 'asset_id': 'bonus_exciting', 'base_volume': 0.95},
          {'index': 3, 'asset_id': 'bonus_peak', 'base_volume': 1.0},
        ],
        'entry_transition': 'immediate',
        'exit_transition': 'bar_sync',
      },
    ];
  }

  /// Build default signal definitions
  List<Map<String, dynamic>> _buildDefaultSignals() {
    return [
      {
        'id': 'winMultiplier',
        'name': 'Win Multiplier',
        'min_value': 0.0,
        'max_value': 1.0,
        'default_value': 0.0,
        'normalization': 'linear',
      },
      {
        'id': 'consecutiveWins',
        'name': 'Consecutive Wins',
        'min_value': 0.0,
        'max_value': 10.0,
        'default_value': 0.0,
        'normalization': 'asymptotic',
        'asymptotic_max': 10.0,
      },
      {
        'id': 'featureProgress',
        'name': 'Feature Progress',
        'min_value': 0.0,
        'max_value': 1.0,
        'default_value': 0.0,
        'normalization': 'linear',
      },
      {
        'id': 'anticipationLevel',
        'name': 'Anticipation Level',
        'min_value': 0.0,
        'max_value': 4.0,
        'default_value': 0.0,
        'normalization': 'linear',
      },
      {
        'id': 'cascadeDepth',
        'name': 'Cascade Depth',
        'min_value': 0.0,
        'max_value': 10.0,
        'default_value': 0.0,
        'normalization': 'sigmoid',
        'sigmoid_k': 0.5,
      },
      {
        'id': 'timeSinceLastWin',
        'name': 'Time Since Last Win',
        'min_value': 0.0,
        'max_value': 60.0,
        'default_value': 0.0,
        'normalization': 'asymptotic',
        'asymptotic_max': 60.0,
      },
    ];
  }

  /// Build default rules based on template features
  List<Map<String, dynamic>> _buildDefaultRules(BuiltTemplate template) {
    final rules = <Map<String, dynamic>>[
      // Win intensity rule
      {
        'id': 'win_intensity',
        'name': 'Win Affects Intensity',
        'signal_id': 'winMultiplier',
        'condition': 'greater_than',
        'threshold': 0.0,
        'action': 'set_level_by_value',
        'cooldown_ms': 500,
      },
      // Consecutive wins energy
      {
        'id': 'consecutive_wins',
        'name': 'Consecutive Wins Energy',
        'signal_id': 'consecutiveWins',
        'condition': 'greater_than',
        'threshold': 2.0,
        'action': 'step_up',
        'cooldown_ms': 1000,
      },
      // Inactivity decay
      {
        'id': 'inactivity_decay',
        'name': 'Inactivity Decay',
        'signal_id': 'timeSinceLastWin',
        'condition': 'greater_than',
        'threshold': 10.0,
        'action': 'step_down',
        'cooldown_ms': 5000,
      },
    ];

    // Add feature-specific rules
    if (template.source.modules.any((f) => f.type == FeatureModuleType.freeSpins)) {
      rules.add({
        'id': 'fs_trigger',
        'name': 'Free Spins Trigger',
        'signal_id': 'featureProgress',
        'condition': 'equals',
        'threshold': 0.0, // Will be triggered by context switch
        'action': 'enter_context',
        'target_context': 'free_spins',
        'cooldown_ms': 0,
      });
    }

    if (template.source.modules.any((f) => f.type == FeatureModuleType.holdWin)) {
      rules.add({
        'id': 'hold_trigger',
        'name': 'Hold & Win Trigger',
        'signal_id': 'featureProgress',
        'condition': 'equals',
        'threshold': 0.0,
        'action': 'enter_context',
        'target_context': 'hold_win',
        'cooldown_ms': 0,
      });
    }

    return rules;
  }

  /// Build stability configuration
  Map<String, dynamic> _buildStabilityConfig() {
    return {
      'global_cooldown_ms': 500,
      'level_hold_ms': 1000,
      'hysteresis_up': 0.1,
      'hysteresis_down': 0.2,
      'decay_enabled': true,
      'decay_delay_ms': 15000,
      'decay_rate': 0.1,
      'prediction_enabled': false,
    };
  }

  /// Build transition profiles
  List<Map<String, dynamic>> _buildTransitionProfiles() {
    return [
      {
        'id': 'immediate',
        'name': 'Immediate',
        'sync_mode': 'immediate',
        'fade_in_ms': 0,
        'fade_out_ms': 0,
        'crossfade_overlap': 0.0,
      },
      {
        'id': 'crossfade',
        'name': 'Crossfade',
        'sync_mode': 'immediate',
        'fade_in_ms': 500,
        'fade_out_ms': 500,
        'crossfade_overlap': 0.5,
        'fade_curve': 'ease_in_out',
      },
      {
        'id': 'beat_sync',
        'name': 'Beat Sync',
        'sync_mode': 'beat',
        'fade_in_ms': 200,
        'fade_out_ms': 200,
        'crossfade_overlap': 0.3,
        'fade_curve': 'ease_out',
      },
      {
        'id': 'bar_sync',
        'name': 'Bar Sync',
        'sync_mode': 'bar',
        'fade_in_ms': 500,
        'fade_out_ms': 500,
        'crossfade_overlap': 0.5,
        'fade_curve': 'ease_in_out',
      },
      {
        'id': 'phrase_sync',
        'name': 'Phrase Sync',
        'sync_mode': 'phrase',
        'fade_in_ms': 1000,
        'fade_out_ms': 1000,
        'crossfade_overlap': 0.7,
        'fade_curve': 's_curve',
      },
    ];
  }
}
