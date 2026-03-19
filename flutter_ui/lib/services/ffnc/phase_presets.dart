/// Phase Presets — apply predefined parameter sets to entire phases.
///
/// Each preset defines volume/bus/fade overrides for categories of stages.
/// "Reset to Smart Defaults" uses stage_defaults.dart values.

import 'stage_defaults.dart';

class PhasePreset {
  final String name;
  final String description;
  /// Multipliers applied to Smart Default volumes per category.
  /// Key = stage prefix or wildcard, value = volume multiplier.
  final Map<String, double> volumeMultipliers;
  /// Override fade-in/out for specific categories.
  final Map<String, double> fadeInOverrides;
  final Map<String, double> fadeOutOverrides;

  const PhasePreset({
    required this.name,
    required this.description,
    this.volumeMultipliers = const {},
    this.fadeInOverrides = const {},
    this.fadeOutOverrides = const {},
  });

  /// Apply this preset to a stage: returns modified StageDefault.
  StageDefault applyTo(String stage) {
    final base = StageDefaults.getDefaultForStage(stage);

    // Find best matching multiplier
    double volumeMult = 1.0;
    int bestLen = 0;
    for (final entry in volumeMultipliers.entries) {
      if (entry.key == '*' || stage.startsWith(entry.key)) {
        if (entry.key.length > bestLen || entry.key == '*' && bestLen == 0) {
          volumeMult = entry.value;
          bestLen = entry.key == '*' ? 0 : entry.key.length;
        }
      }
    }

    // Find fade overrides
    double? fadeIn = base.fadeInMs;
    double? fadeOut = base.fadeOutMs;
    for (final entry in fadeInOverrides.entries) {
      if (entry.key == '*' || stage.startsWith(entry.key)) {
        fadeIn = entry.value;
      }
    }
    for (final entry in fadeOutOverrides.entries) {
      if (entry.key == '*' || stage.startsWith(entry.key)) {
        fadeOut = entry.value;
      }
    }

    return StageDefault(
      volume: (base.volume * volumeMult).clamp(0.0, 1.0),
      busId: base.busId,
      fadeInMs: fadeIn,
      fadeOutMs: fadeOut,
      loop: base.loop,
    );
  }
}

class PhasePresets {
  PhasePresets._();

  static const all = [
    standard,
    highEnergy,
    cinematic,
    mobile,
  ];

  static const standard = PhasePreset(
    name: 'Standard Slot',
    description: 'Balanced volumes, standard buses — Smart Defaults as-is',
    // No overrides — uses Smart Defaults directly
  );

  static const highEnergy = PhasePreset(
    name: 'High Energy',
    description: 'Louder wins, punchier impacts, more presence',
    volumeMultipliers: {
      'WIN_PRESENT_': 1.2,
      'BIG_WIN_': 1.1,
      'ROLLUP_': 1.15,
      'JACKPOT_': 1.1,
      'COIN_': 1.15,
      'SCATTER_LAND': 1.15,
      'FEATURE_ENTER': 1.15,
      'FREESPIN_TRIGGER': 1.1,
    },
  );

  static const cinematic = PhasePreset(
    name: 'Cinematic',
    description: 'Longer fades, smoother transitions, ambient emphasis',
    volumeMultipliers: {
      'AMBIENT_': 1.3,
      'MUSIC_TENSION_': 1.2,
      'ANTICIPATION_': 1.15,
      'ATTRACT_': 1.2,
    },
    fadeInOverrides: {
      'FEATURE_ENTER': 300,
      'ANTICIPATION_': 500,
      'AMBIENT_': 800,
      'MUSIC_': 400,
      'TRANSITION_': 200,
    },
    fadeOutOverrides: {
      'FEATURE_EXIT': 400,
      'SPIN_END': 100,
      'BIG_WIN_END': 800,
      'ANTICIPATION_OFF': 400,
    },
  );

  static const mobile = PhasePreset(
    name: 'Mobile',
    description: 'Lower volumes across the board, shorter fades for responsiveness',
    volumeMultipliers: {
      '*': 0.85, // Global 15% reduction
      'UI_': 0.9,
      'AMBIENT_': 0.7,
      'MUSIC_TENSION_': 0.8,
    },
    fadeInOverrides: {
      'ANTICIPATION_': 150,
      'AMBIENT_': 300,
      'FEATURE_ENTER': 50,
    },
    fadeOutOverrides: {
      'REEL_STOP_': 50,
      'BIG_WIN_END': 300,
      'FEATURE_EXIT': 100,
    },
  );
}
