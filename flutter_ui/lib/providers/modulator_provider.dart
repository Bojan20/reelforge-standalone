// Modulator Provider
//
// Cubase-style parameter modulators:
// - LFO (Low Frequency Oscillator) — sine, triangle, saw, square, random
// - Envelope Follower — extract dynamics from audio and apply to parameters
// - Step Modulator — programmable step sequencer for modulation
// - Random Modulator — controlled randomization
//
// Each modulator can target any automatable parameter on any track.

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS & TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// LFO waveform shapes
enum LfoWaveform {
  sine,       // Smooth sine wave
  triangle,   // Linear triangle
  saw,        // Sawtooth (ramp up)
  sawDown,    // Reverse sawtooth (ramp down)
  square,     // Square wave
  pulse,      // Variable pulse width
  random,     // Sample & hold random
  smoothRandom, // Smoothed random (perlin-like)
}

/// Modulator sync mode
enum ModulatorSyncMode {
  free,       // Free-running (Hz)
  tempo,      // Synced to project tempo (note values)
}

/// Envelope follower mode
enum EnvelopeFollowerMode {
  peak,       // Peak detection
  rms,        // RMS level
  transient,  // Transient detection
}

/// Modulator target parameter
class ModulatorTarget {
  final int trackId;
  final String parameterName;
  final double depth;      // Modulation depth (0-1)
  final bool bipolar;      // Bipolar (±depth) or unipolar (0-depth)
  final bool inverted;     // Invert modulation

  const ModulatorTarget({
    required this.trackId,
    required this.parameterName,
    this.depth = 0.5,
    this.bipolar = true,
    this.inverted = false,
  });

  ModulatorTarget copyWith({
    int? trackId,
    String? parameterName,
    double? depth,
    bool? bipolar,
    bool? inverted,
  }) {
    return ModulatorTarget(
      trackId: trackId ?? this.trackId,
      parameterName: parameterName ?? this.parameterName,
      depth: depth ?? this.depth,
      bipolar: bipolar ?? this.bipolar,
      inverted: inverted ?? this.inverted,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LFO MODULATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Low Frequency Oscillator modulator
class LfoModulator {
  final String id;
  final String name;
  final bool enabled;

  // Waveform
  final LfoWaveform waveform;
  final double pulseWidth;   // For pulse waveform (0-1)

  // Timing
  final ModulatorSyncMode syncMode;
  final double rate;         // Hz (free) or note value (tempo)
  final double phase;        // Phase offset (0-1)

  // Shape
  final double fadeIn;       // Fade in time (seconds)
  final double delay;        // Start delay (seconds)
  final bool retrigger;      // Retrigger on transport start

  // Smoothing
  final double smoothing;    // Output smoothing (0-1)

  // Targets
  final List<ModulatorTarget> targets;

  // Runtime state
  final double currentValue;
  final double currentPhase;

  const LfoModulator({
    required this.id,
    this.name = 'LFO',
    this.enabled = true,
    this.waveform = LfoWaveform.sine,
    this.pulseWidth = 0.5,
    this.syncMode = ModulatorSyncMode.free,
    this.rate = 1.0,
    this.phase = 0.0,
    this.fadeIn = 0.0,
    this.delay = 0.0,
    this.retrigger = true,
    this.smoothing = 0.0,
    this.targets = const [],
    this.currentValue = 0.0,
    this.currentPhase = 0.0,
  });

  LfoModulator copyWith({
    String? id,
    String? name,
    bool? enabled,
    LfoWaveform? waveform,
    double? pulseWidth,
    ModulatorSyncMode? syncMode,
    double? rate,
    double? phase,
    double? fadeIn,
    double? delay,
    bool? retrigger,
    double? smoothing,
    List<ModulatorTarget>? targets,
    double? currentValue,
    double? currentPhase,
  }) {
    return LfoModulator(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      waveform: waveform ?? this.waveform,
      pulseWidth: pulseWidth ?? this.pulseWidth,
      syncMode: syncMode ?? this.syncMode,
      rate: rate ?? this.rate,
      phase: phase ?? this.phase,
      fadeIn: fadeIn ?? this.fadeIn,
      delay: delay ?? this.delay,
      retrigger: retrigger ?? this.retrigger,
      smoothing: smoothing ?? this.smoothing,
      targets: targets ?? this.targets,
      currentValue: currentValue ?? this.currentValue,
      currentPhase: currentPhase ?? this.currentPhase,
    );
  }

  /// Calculate waveform value at given phase (0-1)
  double calculateValue(double ph) {
    // Normalize phase to 0-1
    final p = ph - ph.floor();

    switch (waveform) {
      case LfoWaveform.sine:
        return math.sin(p * 2 * math.pi);

      case LfoWaveform.triangle:
        if (p < 0.25) return p * 4;
        if (p < 0.75) return 2 - p * 4;
        return p * 4 - 4;

      case LfoWaveform.saw:
        return p * 2 - 1;

      case LfoWaveform.sawDown:
        return 1 - p * 2;

      case LfoWaveform.square:
        return p < 0.5 ? 1.0 : -1.0;

      case LfoWaveform.pulse:
        return p < pulseWidth ? 1.0 : -1.0;

      case LfoWaveform.random:
        // Sample & hold — value changes at each cycle
        return (p.hashCode % 1000) / 500.0 - 1.0;

      case LfoWaveform.smoothRandom:
        // Simplified smooth random
        final seed = (p * 10).floor();
        final t = (p * 10) - seed;
        final v1 = ((seed * 12345) % 1000) / 500.0 - 1.0;
        final v2 = (((seed + 1) * 12345) % 1000) / 500.0 - 1.0;
        return v1 + (v2 - v1) * t * t * (3 - 2 * t); // Smooth interpolation
    }
  }

  /// Get tempo-synced rate in Hz
  double getEffectiveRate(double bpm) {
    if (syncMode == ModulatorSyncMode.free) return rate;

    // Convert note value to Hz
    // rate: 1 = quarter note, 0.5 = half note, 2 = eighth note, etc.
    final beatsPerSecond = bpm / 60.0;
    return beatsPerSecond * rate;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENVELOPE FOLLOWER
// ═══════════════════════════════════════════════════════════════════════════════

/// Envelope follower — extracts dynamics from audio
class EnvelopeFollower {
  final String id;
  final String name;
  final bool enabled;

  // Source
  final int sourceTrackId;  // Track to analyze (-1 = master)

  // Detection
  final EnvelopeFollowerMode mode;
  final double attack;      // Attack time (ms)
  final double release;     // Release time (ms)
  final double threshold;   // Threshold (0-1)
  final double ratio;       // Compression ratio for detection

  // Output
  final double gain;        // Output gain multiplier
  final double offset;      // DC offset (-1 to 1)
  final bool inverted;      // Invert output

  // Targets
  final List<ModulatorTarget> targets;

  // Runtime
  final double currentValue;
  final double envelope;

  const EnvelopeFollower({
    required this.id,
    this.name = 'Envelope',
    this.enabled = true,
    this.sourceTrackId = -1,
    this.mode = EnvelopeFollowerMode.rms,
    this.attack = 10.0,
    this.release = 100.0,
    this.threshold = 0.0,
    this.ratio = 1.0,
    this.gain = 1.0,
    this.offset = 0.0,
    this.inverted = false,
    this.targets = const [],
    this.currentValue = 0.0,
    this.envelope = 0.0,
  });

  EnvelopeFollower copyWith({
    String? id,
    String? name,
    bool? enabled,
    int? sourceTrackId,
    EnvelopeFollowerMode? mode,
    double? attack,
    double? release,
    double? threshold,
    double? ratio,
    double? gain,
    double? offset,
    bool? inverted,
    List<ModulatorTarget>? targets,
    double? currentValue,
    double? envelope,
  }) {
    return EnvelopeFollower(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      sourceTrackId: sourceTrackId ?? this.sourceTrackId,
      mode: mode ?? this.mode,
      attack: attack ?? this.attack,
      release: release ?? this.release,
      threshold: threshold ?? this.threshold,
      ratio: ratio ?? this.ratio,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      inverted: inverted ?? this.inverted,
      targets: targets ?? this.targets,
      currentValue: currentValue ?? this.currentValue,
      envelope: envelope ?? this.envelope,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEP MODULATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Step sequencer modulator
class StepModulator {
  final String id;
  final String name;
  final bool enabled;

  // Steps
  final List<double> steps;     // Step values (-1 to 1)
  final int currentStep;

  // Timing
  final ModulatorSyncMode syncMode;
  final double rate;            // Steps per beat (tempo) or Hz (free)

  // Shape
  final double glide;           // Glide/portamento between steps (0-1)
  final bool pingPong;          // Ping-pong mode

  // Targets
  final List<ModulatorTarget> targets;

  // Runtime
  final double currentValue;

  const StepModulator({
    required this.id,
    this.name = 'Steps',
    this.enabled = true,
    this.steps = const [0, 0.5, 1, 0.5, 0, -0.5, -1, -0.5],
    this.currentStep = 0,
    this.syncMode = ModulatorSyncMode.tempo,
    this.rate = 4.0,
    this.glide = 0.0,
    this.pingPong = false,
    this.targets = const [],
    this.currentValue = 0.0,
  });

  StepModulator copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<double>? steps,
    int? currentStep,
    ModulatorSyncMode? syncMode,
    double? rate,
    double? glide,
    bool? pingPong,
    List<ModulatorTarget>? targets,
    double? currentValue,
  }) {
    return StepModulator(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      steps: steps ?? this.steps,
      currentStep: currentStep ?? this.currentStep,
      syncMode: syncMode ?? this.syncMode,
      rate: rate ?? this.rate,
      glide: glide ?? this.glide,
      pingPong: pingPong ?? this.pingPong,
      targets: targets ?? this.targets,
      currentValue: currentValue ?? this.currentValue,
    );
  }

  /// Set step value
  StepModulator setStep(int index, double value) {
    if (index < 0 || index >= steps.length) return this;
    final newSteps = List<double>.from(steps);
    newSteps[index] = value.clamp(-1.0, 1.0);
    return copyWith(steps: newSteps);
  }

  /// Add step
  StepModulator addStep([double value = 0]) {
    return copyWith(steps: [...steps, value.clamp(-1.0, 1.0)]);
  }

  /// Remove step
  StepModulator removeStep(int index) {
    if (steps.length <= 2) return this; // Minimum 2 steps
    final newSteps = List<double>.from(steps);
    newSteps.removeAt(index);
    return copyWith(steps: newSteps);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RANDOM MODULATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Controlled random modulation
class RandomModulator {
  final String id;
  final String name;
  final bool enabled;

  // Parameters
  final double rate;          // Rate of change (Hz or tempo-synced)
  final ModulatorSyncMode syncMode;
  final double smoothing;     // Output smoothing (0-1)
  final double min;           // Minimum output value (-1 to 1)
  final double max;           // Maximum output value (-1 to 1)

  // Targets
  final List<ModulatorTarget> targets;

  // Runtime
  final double currentValue;
  final double targetValue;

  const RandomModulator({
    required this.id,
    this.name = 'Random',
    this.enabled = true,
    this.rate = 1.0,
    this.syncMode = ModulatorSyncMode.free,
    this.smoothing = 0.5,
    this.min = -1.0,
    this.max = 1.0,
    this.targets = const [],
    this.currentValue = 0.0,
    this.targetValue = 0.0,
  });

  RandomModulator copyWith({
    String? id,
    String? name,
    bool? enabled,
    double? rate,
    ModulatorSyncMode? syncMode,
    double? smoothing,
    double? min,
    double? max,
    List<ModulatorTarget>? targets,
    double? currentValue,
    double? targetValue,
  }) {
    return RandomModulator(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      rate: rate ?? this.rate,
      syncMode: syncMode ?? this.syncMode,
      smoothing: smoothing ?? this.smoothing,
      min: min ?? this.min,
      max: max ?? this.max,
      targets: targets ?? this.targets,
      currentValue: currentValue ?? this.currentValue,
      targetValue: targetValue ?? this.targetValue,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODULATOR PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class ModulatorProvider extends ChangeNotifier {
  // All modulators by ID
  final Map<String, LfoModulator> _lfos = {};
  final Map<String, EnvelopeFollower> _envelopes = {};
  final Map<String, StepModulator> _stepMods = {};
  final Map<String, RandomModulator> _randomMods = {};

  // Project tempo (for sync)
  double _bpm = 120.0;

  // Sample rate
  double _sampleRate = 48000.0;

  // Global enable
  bool _enabled = true;

  // Selected modulator for editing
  String? _selectedId;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  double get bpm => _bpm;
  double get sampleRate => _sampleRate;
  String? get selectedId => _selectedId;

  List<LfoModulator> get lfos => _lfos.values.toList();
  List<EnvelopeFollower> get envelopes => _envelopes.values.toList();
  List<StepModulator> get stepMods => _stepMods.values.toList();
  List<RandomModulator> get randomMods => _randomMods.values.toList();

  LfoModulator? getLfo(String id) => _lfos[id];
  EnvelopeFollower? getEnvelope(String id) => _envelopes[id];
  StepModulator? getStepMod(String id) => _stepMods[id];
  RandomModulator? getRandomMod(String id) => _randomMods[id];

  /// Get all modulators targeting a specific parameter
  List<dynamic> getModulatorsForTarget(int trackId, String paramName) {
    final result = <dynamic>[];

    for (final lfo in _lfos.values) {
      if (lfo.targets.any((t) => t.trackId == trackId && t.parameterName == paramName)) {
        result.add(lfo);
      }
    }
    for (final env in _envelopes.values) {
      if (env.targets.any((t) => t.trackId == trackId && t.parameterName == paramName)) {
        result.add(env);
      }
    }
    for (final step in _stepMods.values) {
      if (step.targets.any((t) => t.trackId == trackId && t.parameterName == paramName)) {
        result.add(step);
      }
    }
    for (final rand in _randomMods.values) {
      if (rand.targets.any((t) => t.trackId == trackId && t.parameterName == paramName)) {
        result.add(rand);
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLOBAL CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void toggleEnabled() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void setBpm(double bpm) {
    _bpm = bpm.clamp(20.0, 300.0);
    notifyListeners();
  }

  void setSampleRate(double rate) {
    _sampleRate = rate;
  }

  void selectModulator(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LFO MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add new LFO
  LfoModulator addLfo({String? name}) {
    final id = 'lfo_${DateTime.now().millisecondsSinceEpoch}';
    final lfo = LfoModulator(
      id: id,
      name: name ?? 'LFO ${_lfos.length + 1}',
    );
    _lfos[id] = lfo;
    notifyListeners();
    return lfo;
  }

  /// Update LFO
  void updateLfo(LfoModulator lfo) {
    _lfos[lfo.id] = lfo;
    notifyListeners();
  }

  /// Remove LFO
  void removeLfo(String id) {
    _lfos.remove(id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  /// Add target to LFO
  void addLfoTarget(String lfoId, ModulatorTarget target) {
    final lfo = _lfos[lfoId];
    if (lfo == null) return;

    _lfos[lfoId] = lfo.copyWith(targets: [...lfo.targets, target]);
    notifyListeners();
  }

  /// Remove target from LFO
  void removeLfoTarget(String lfoId, int targetIndex) {
    final lfo = _lfos[lfoId];
    if (lfo == null || targetIndex >= lfo.targets.length) return;

    final newTargets = List<ModulatorTarget>.from(lfo.targets);
    newTargets.removeAt(targetIndex);
    _lfos[lfoId] = lfo.copyWith(targets: newTargets);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENVELOPE FOLLOWER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add new envelope follower
  EnvelopeFollower addEnvelopeFollower({String? name, int sourceTrack = -1}) {
    final id = 'env_${DateTime.now().millisecondsSinceEpoch}';
    final env = EnvelopeFollower(
      id: id,
      name: name ?? 'Env ${_envelopes.length + 1}',
      sourceTrackId: sourceTrack,
    );
    _envelopes[id] = env;
    notifyListeners();
    return env;
  }

  /// Update envelope follower
  void updateEnvelopeFollower(EnvelopeFollower env) {
    _envelopes[env.id] = env;
    notifyListeners();
  }

  /// Remove envelope follower
  void removeEnvelopeFollower(String id) {
    _envelopes.remove(id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  /// Add target to envelope follower
  void addEnvelopeTarget(String envId, ModulatorTarget target) {
    final env = _envelopes[envId];
    if (env == null) return;

    _envelopes[envId] = env.copyWith(targets: [...env.targets, target]);
    notifyListeners();
  }

  /// Remove target from envelope follower
  void removeEnvelopeTarget(String envId, int targetIndex) {
    final env = _envelopes[envId];
    if (env == null || targetIndex >= env.targets.length) return;

    final newTargets = List<ModulatorTarget>.from(env.targets);
    newTargets.removeAt(targetIndex);
    _envelopes[envId] = env.copyWith(targets: newTargets);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP MODULATOR MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add new step modulator
  StepModulator addStepModulator({String? name, int stepCount = 8}) {
    final id = 'step_${DateTime.now().millisecondsSinceEpoch}';
    final steps = List<double>.filled(stepCount, 0.0);
    final stepMod = StepModulator(
      id: id,
      name: name ?? 'Steps ${_stepMods.length + 1}',
      steps: steps,
    );
    _stepMods[id] = stepMod;
    notifyListeners();
    return stepMod;
  }

  /// Update step modulator
  void updateStepModulator(StepModulator stepMod) {
    _stepMods[stepMod.id] = stepMod;
    notifyListeners();
  }

  /// Remove step modulator
  void removeStepModulator(String id) {
    _stepMods.remove(id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  /// Set step value
  void setStepValue(String stepModId, int stepIndex, double value) {
    final stepMod = _stepMods[stepModId];
    if (stepMod == null) return;

    _stepMods[stepModId] = stepMod.setStep(stepIndex, value);
    notifyListeners();
  }

  /// Add step target
  void addStepTarget(String stepModId, ModulatorTarget target) {
    final stepMod = _stepMods[stepModId];
    if (stepMod == null) return;

    _stepMods[stepModId] = stepMod.copyWith(targets: [...stepMod.targets, target]);
    notifyListeners();
  }

  /// Remove step target
  void removeStepTarget(String stepModId, int targetIndex) {
    final stepMod = _stepMods[stepModId];
    if (stepMod == null || targetIndex >= stepMod.targets.length) return;

    final newTargets = List<ModulatorTarget>.from(stepMod.targets);
    newTargets.removeAt(targetIndex);
    _stepMods[stepModId] = stepMod.copyWith(targets: newTargets);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANDOM MODULATOR MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add new random modulator
  RandomModulator addRandomModulator({String? name}) {
    final id = 'rand_${DateTime.now().millisecondsSinceEpoch}';
    final randMod = RandomModulator(
      id: id,
      name: name ?? 'Random ${_randomMods.length + 1}',
    );
    _randomMods[id] = randMod;
    notifyListeners();
    return randMod;
  }

  /// Update random modulator
  void updateRandomModulator(RandomModulator randMod) {
    _randomMods[randMod.id] = randMod;
    notifyListeners();
  }

  /// Remove random modulator
  void removeRandomModulator(String id) {
    _randomMods.remove(id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  /// Add random target
  void addRandomTarget(String randModId, ModulatorTarget target) {
    final randMod = _randomMods[randModId];
    if (randMod == null) return;

    _randomMods[randModId] = randMod.copyWith(targets: [...randMod.targets, target]);
    notifyListeners();
  }

  /// Remove random target
  void removeRandomTarget(String randModId, int targetIndex) {
    final randMod = _randomMods[randModId];
    if (randMod == null || targetIndex >= randMod.targets.length) return;

    final newTargets = List<ModulatorTarget>.from(randMod.targets);
    newTargets.removeAt(targetIndex);
    _randomMods[randModId] = randMod.copyWith(targets: newTargets);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALCULATE MODULATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate total modulation for a parameter at current time
  double calculateModulation(int trackId, String paramName, double timeSeconds) {
    if (!_enabled) return 0.0;

    double totalMod = 0.0;

    // LFOs
    for (final lfo in _lfos.values) {
      if (!lfo.enabled) continue;

      for (final target in lfo.targets) {
        if (target.trackId == trackId && target.parameterName == paramName) {
          final effectiveRate = lfo.getEffectiveRate(_bpm);
          final phase = (timeSeconds * effectiveRate + lfo.phase) % 1.0;
          var value = lfo.calculateValue(phase);

          if (target.inverted) value = -value;
          if (!target.bipolar) value = (value + 1) / 2;

          totalMod += value * target.depth;
        }
      }
    }

    // Envelope followers (use stored envelope value)
    for (final env in _envelopes.values) {
      if (!env.enabled) continue;

      for (final target in env.targets) {
        if (target.trackId == trackId && target.parameterName == paramName) {
          var value = env.currentValue;
          if (target.inverted) value = -value;
          if (!target.bipolar) value = (value + 1) / 2;

          totalMod += value * target.depth;
        }
      }
    }

    // Step modulators
    for (final stepMod in _stepMods.values) {
      if (!stepMod.enabled || stepMod.steps.isEmpty) continue;

      for (final target in stepMod.targets) {
        if (target.trackId == trackId && target.parameterName == paramName) {
          var value = stepMod.currentValue;
          if (target.inverted) value = -value;
          if (!target.bipolar) value = (value + 1) / 2;

          totalMod += value * target.depth;
        }
      }
    }

    // Random modulators
    for (final randMod in _randomMods.values) {
      if (!randMod.enabled) continue;

      for (final target in randMod.targets) {
        if (target.trackId == trackId && target.parameterName == paramName) {
          var value = randMod.currentValue;
          if (target.inverted) value = -value;
          if (!target.bipolar) value = (value + 1) / 2;

          totalMod += value * target.depth;
        }
      }
    }

    return totalMod.clamp(-1.0, 1.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'bpm': _bpm,
      'lfos': _lfos.values.map((l) => _lfoToJson(l)).toList(),
      'envelopes': _envelopes.values.map((e) => _envToJson(e)).toList(),
      'stepMods': _stepMods.values.map((s) => _stepToJson(s)).toList(),
      'randomMods': _randomMods.values.map((r) => _randToJson(r)).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? true;
    _bpm = (json['bpm'] ?? 120.0).toDouble();

    _lfos.clear();
    _envelopes.clear();
    _stepMods.clear();
    _randomMods.clear();

    if (json['lfos'] != null) {
      for (final l in json['lfos']) {
        final lfo = _lfoFromJson(l);
        _lfos[lfo.id] = lfo;
      }
    }
    if (json['envelopes'] != null) {
      for (final e in json['envelopes']) {
        final env = _envFromJson(e);
        _envelopes[env.id] = env;
      }
    }
    if (json['stepMods'] != null) {
      for (final s in json['stepMods']) {
        final stepMod = _stepFromJson(s);
        _stepMods[stepMod.id] = stepMod;
      }
    }
    if (json['randomMods'] != null) {
      for (final r in json['randomMods']) {
        final randMod = _randFromJson(r);
        _randomMods[randMod.id] = randMod;
      }
    }

    notifyListeners();
  }

  // JSON helpers
  Map<String, dynamic> _lfoToJson(LfoModulator lfo) {
    return {
      'id': lfo.id,
      'name': lfo.name,
      'enabled': lfo.enabled,
      'waveform': lfo.waveform.index,
      'pulseWidth': lfo.pulseWidth,
      'syncMode': lfo.syncMode.index,
      'rate': lfo.rate,
      'phase': lfo.phase,
      'fadeIn': lfo.fadeIn,
      'delay': lfo.delay,
      'retrigger': lfo.retrigger,
      'smoothing': lfo.smoothing,
      'targets': lfo.targets.map((t) => _targetToJson(t)).toList(),
    };
  }

  LfoModulator _lfoFromJson(Map<String, dynamic> json) {
    return LfoModulator(
      id: json['id'],
      name: json['name'] ?? 'LFO',
      enabled: json['enabled'] ?? true,
      waveform: LfoWaveform.values[json['waveform'] ?? 0],
      pulseWidth: (json['pulseWidth'] ?? 0.5).toDouble(),
      syncMode: ModulatorSyncMode.values[json['syncMode'] ?? 0],
      rate: (json['rate'] ?? 1.0).toDouble(),
      phase: (json['phase'] ?? 0.0).toDouble(),
      fadeIn: (json['fadeIn'] ?? 0.0).toDouble(),
      delay: (json['delay'] ?? 0.0).toDouble(),
      retrigger: json['retrigger'] ?? true,
      smoothing: (json['smoothing'] ?? 0.0).toDouble(),
      targets: (json['targets'] as List?)?.map((t) => _targetFromJson(t)).toList() ?? [],
    );
  }

  Map<String, dynamic> _envToJson(EnvelopeFollower env) {
    return {
      'id': env.id,
      'name': env.name,
      'enabled': env.enabled,
      'sourceTrackId': env.sourceTrackId,
      'mode': env.mode.index,
      'attack': env.attack,
      'release': env.release,
      'threshold': env.threshold,
      'ratio': env.ratio,
      'gain': env.gain,
      'offset': env.offset,
      'inverted': env.inverted,
      'targets': env.targets.map((t) => _targetToJson(t)).toList(),
    };
  }

  EnvelopeFollower _envFromJson(Map<String, dynamic> json) {
    return EnvelopeFollower(
      id: json['id'],
      name: json['name'] ?? 'Envelope',
      enabled: json['enabled'] ?? true,
      sourceTrackId: json['sourceTrackId'] ?? -1,
      mode: EnvelopeFollowerMode.values[json['mode'] ?? 0],
      attack: (json['attack'] ?? 10.0).toDouble(),
      release: (json['release'] ?? 100.0).toDouble(),
      threshold: (json['threshold'] ?? 0.0).toDouble(),
      ratio: (json['ratio'] ?? 1.0).toDouble(),
      gain: (json['gain'] ?? 1.0).toDouble(),
      offset: (json['offset'] ?? 0.0).toDouble(),
      inverted: json['inverted'] ?? false,
      targets: (json['targets'] as List?)?.map((t) => _targetFromJson(t)).toList() ?? [],
    );
  }

  Map<String, dynamic> _stepToJson(StepModulator stepMod) {
    return {
      'id': stepMod.id,
      'name': stepMod.name,
      'enabled': stepMod.enabled,
      'steps': stepMod.steps,
      'syncMode': stepMod.syncMode.index,
      'rate': stepMod.rate,
      'glide': stepMod.glide,
      'pingPong': stepMod.pingPong,
      'targets': stepMod.targets.map((t) => _targetToJson(t)).toList(),
    };
  }

  StepModulator _stepFromJson(Map<String, dynamic> json) {
    return StepModulator(
      id: json['id'],
      name: json['name'] ?? 'Steps',
      enabled: json['enabled'] ?? true,
      steps: (json['steps'] as List?)?.map((s) => (s as num).toDouble()).toList() ??
          List<double>.filled(8, 0.0),
      syncMode: ModulatorSyncMode.values[json['syncMode'] ?? 0],
      rate: (json['rate'] ?? 4.0).toDouble(),
      glide: (json['glide'] ?? 0.0).toDouble(),
      pingPong: json['pingPong'] ?? false,
      targets: (json['targets'] as List?)?.map((t) => _targetFromJson(t)).toList() ?? [],
    );
  }

  Map<String, dynamic> _randToJson(RandomModulator randMod) {
    return {
      'id': randMod.id,
      'name': randMod.name,
      'enabled': randMod.enabled,
      'rate': randMod.rate,
      'syncMode': randMod.syncMode.index,
      'smoothing': randMod.smoothing,
      'min': randMod.min,
      'max': randMod.max,
      'targets': randMod.targets.map((t) => _targetToJson(t)).toList(),
    };
  }

  RandomModulator _randFromJson(Map<String, dynamic> json) {
    return RandomModulator(
      id: json['id'],
      name: json['name'] ?? 'Random',
      enabled: json['enabled'] ?? true,
      rate: (json['rate'] ?? 1.0).toDouble(),
      syncMode: ModulatorSyncMode.values[json['syncMode'] ?? 0],
      smoothing: (json['smoothing'] ?? 0.5).toDouble(),
      min: (json['min'] ?? -1.0).toDouble(),
      max: (json['max'] ?? 1.0).toDouble(),
      targets: (json['targets'] as List?)?.map((t) => _targetFromJson(t)).toList() ?? [],
    );
  }

  Map<String, dynamic> _targetToJson(ModulatorTarget target) {
    return {
      'trackId': target.trackId,
      'parameterName': target.parameterName,
      'depth': target.depth,
      'bipolar': target.bipolar,
      'inverted': target.inverted,
    };
  }

  ModulatorTarget _targetFromJson(Map<String, dynamic> json) {
    return ModulatorTarget(
      trackId: json['trackId'] ?? 0,
      parameterName: json['parameterName'] ?? 'volume',
      depth: (json['depth'] ?? 0.5).toDouble(),
      bipolar: json['bipolar'] ?? true,
      inverted: json['inverted'] ?? false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _lfos.clear();
    _envelopes.clear();
    _stepMods.clear();
    _randomMods.clear();
    _enabled = true;
    _selectedId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
