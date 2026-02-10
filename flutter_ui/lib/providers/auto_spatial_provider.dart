/// AutoSpatial Provider — State management for AutoSpatialEngine
///
/// Provides UI-friendly access to the AutoSpatialEngine with:
/// - Custom intent rules editing
/// - Bus policy customization
/// - Real-time stats monitoring
/// - Anchor registry access
/// - Configuration management
/// - Rule templates (presets for common scenarios)
///
/// Optionally uses Rust FFI for lower-latency spatial processing.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../spatial/auto_spatial.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RULE TEMPLATES
// ═══════════════════════════════════════════════════════════════════════════

/// Pre-defined rule templates for common slot scenarios
class SpatialRuleTemplates {
  SpatialRuleTemplates._();

  /// Cascade/Tumble wins - symbols falling from top
  static IntentRule cascadeStep({String intent = 'cascade_step'}) => IntentRule(
    intent: intent,
    defaultAnchorId: 'reels_center',
    wAnchor: 0.3,
    wMotion: 0.6,
    wIntent: 0.1,
    width: 0.6,
    deadzone: 0.05,
    maxPan: 0.9,
    smoothingTauMs: 40, // Fast for cascade
    enableDoppler: true,
    dopplerScale: 0.8,
    baseReverbSend: 0.15,
    distanceReverbScale: 0.4,
    lifetimeMs: 300,
    motionEasing: EasingFunction.easeOutQuad,
  );

  /// Big Win celebration - wide, impactful
  static IntentRule bigWin({String intent = 'win_big'}) => IntentRule(
    intent: intent,
    defaultAnchorId: 'win_display',
    wAnchor: 0.7,
    wMotion: 0.1,
    wIntent: 0.2,
    width: 1.0, // Full stereo
    deadzone: 0.02,
    maxPan: 0.4, // Keep somewhat centered
    smoothingTauMs: 100,
    enableDoppler: false,
    baseReverbSend: 0.4, // More reverb for impact
    distanceReverbScale: 0.2,
    lifetimeMs: 3000,
    motionEasing: EasingFunction.easeOutBounce,
  );

  /// Jackpot trigger - maximum impact
  static IntentRule jackpot({String intent = 'jackpot'}) => IntentRule(
    intent: intent,
    defaultAnchorId: 'jackpot_display',
    wAnchor: 0.8,
    wMotion: 0.1,
    wIntent: 0.1,
    width: 1.0,
    deadzone: 0.0, // No deadzone for dramatic effect
    maxPan: 0.3,
    smoothingTauMs: 150,
    enableDoppler: false,
    baseReverbSend: 0.6, // Heavy reverb
    distanceReverbScale: 0.1,
    lifetimeMs: 5000,
    motionEasing: EasingFunction.easeOutElastic,
  );

  /// Reel spin loop - consistent, wide
  static IntentRule reelSpin({String intent = 'reel_spin'}) => IntentRule(
    intent: intent,
    defaultAnchorId: 'reels_center',
    wAnchor: 0.4,
    wMotion: 0.4,
    wIntent: 0.2,
    width: 0.8,
    deadzone: 0.08,
    maxPan: 0.7,
    smoothingTauMs: 80,
    enableDoppler: true,
    dopplerScale: 0.3,
    baseReverbSend: 0.1,
    distanceReverbScale: 0.3,
    lifetimeMs: 10000, // Long for loop
    motionEasing: EasingFunction.linear,
  );

  /// Reel stop - per-reel positioning
  static IntentRule reelStop({required int reelIndex, String? intent}) => IntentRule(
    intent: intent ?? 'reel_stop_$reelIndex',
    defaultAnchorId: 'reel_$reelIndex',
    wAnchor: 0.9,
    wMotion: 0.05,
    wIntent: 0.05,
    width: 0.3, // Tight for precise positioning
    deadzone: 0.02,
    maxPan: 1.0, // Full range for reel spread
    smoothingTauMs: 30, // Fast
    enableDoppler: false,
    baseReverbSend: 0.08,
    distanceReverbScale: 0.2,
    lifetimeMs: 500,
    motionEasing: EasingFunction.easeOutCubic,
  );

  /// UI click - tight, dry
  static IntentRule uiClick({String intent = 'ui_click'}) => IntentRule(
    intent: intent,
    defaultAnchorId: null, // Use event position
    wAnchor: 0.9,
    wMotion: 0.0,
    wIntent: 0.1,
    width: 0.15, // Very tight
    deadzone: 0.1,
    maxPan: 0.6,
    smoothingTauMs: 20,
    enableDoppler: false,
    baseReverbSend: 0.0, // Dry
    distanceReverbScale: 0.0,
    lifetimeMs: 200,
    motionEasing: EasingFunction.linear,
  );

  /// Coin/chip fly animation - follows motion
  static IntentRule coinFly({String intent = 'coin_fly'}) => IntentRule(
    intent: intent,
    defaultAnchorId: null,
    wAnchor: 0.2,
    wMotion: 0.7, // Heavy motion tracking
    wIntent: 0.1,
    width: 0.5,
    deadzone: 0.03,
    maxPan: 1.0,
    smoothingTauMs: 25, // Very responsive
    enableDoppler: true,
    dopplerScale: 1.2, // Exaggerated Doppler
    baseReverbSend: 0.1,
    distanceReverbScale: 0.5,
    lifetimeMs: 800,
    motionEasing: EasingFunction.easeInOutQuad,
  );

  /// Anticipation/near miss - building tension
  static IntentRule anticipation({String intent = 'anticipation'}) => IntentRule(
    intent: intent,
    defaultAnchorId: 'reels_center',
    wAnchor: 0.5,
    wMotion: 0.2,
    wIntent: 0.3,
    width: 0.7,
    deadzone: 0.05,
    maxPan: 0.5,
    smoothingTauMs: 200, // Slow, building
    enableDoppler: false,
    baseReverbSend: 0.25,
    distanceReverbScale: 0.4,
    lifetimeMs: 2000,
    motionEasing: EasingFunction.easeInQuad,
  );

  /// Free spins trigger - exciting, wide
  static IntentRule freeSpinsTrigger({String intent = 'fs_trigger'}) => IntentRule(
    intent: intent,
    defaultAnchorId: 'scatter_display',
    wAnchor: 0.6,
    wMotion: 0.2,
    wIntent: 0.2,
    width: 1.0,
    deadzone: 0.02,
    maxPan: 0.5,
    smoothingTauMs: 120,
    enableDoppler: false,
    baseReverbSend: 0.35,
    distanceReverbScale: 0.3,
    lifetimeMs: 2500,
    motionEasing: EasingFunction.easeOutBounce,
  );

  /// Wild symbol land - punchy
  static IntentRule wildLand({String intent = 'wild_land'}) => IntentRule(
    intent: intent,
    defaultAnchorId: null,
    wAnchor: 0.8,
    wMotion: 0.1,
    wIntent: 0.1,
    width: 0.5,
    deadzone: 0.03,
    maxPan: 0.95,
    smoothingTauMs: 35,
    enableDoppler: false,
    baseReverbSend: 0.2,
    distanceReverbScale: 0.3,
    lifetimeMs: 600,
    motionEasing: EasingFunction.easeOutBounce,
  );

  /// Voice over / announcer - centered, clear
  static IntentRule voiceOver({String intent = 'voice_over'}) => IntentRule(
    intent: intent,
    defaultAnchorId: 'center',
    wAnchor: 1.0,
    wMotion: 0.0,
    wIntent: 0.0,
    width: 0.3,
    deadzone: 0.2, // Large deadzone keeps centered
    maxPan: 0.2,
    smoothingTauMs: 100,
    enableDoppler: false,
    baseReverbSend: 0.05, // Very dry for clarity
    distanceReverbScale: 0.1,
    lifetimeMs: 5000,
    motionEasing: EasingFunction.linear,
  );

  /// All available templates
  static List<({String name, String description, IntentRule Function() builder})> get all => [
    (name: 'Cascade Step', description: 'Tumbling symbols falling', builder: () => cascadeStep()),
    (name: 'Big Win', description: 'Wide, impactful celebration', builder: () => bigWin()),
    (name: 'Jackpot', description: 'Maximum impact, heavy reverb', builder: () => jackpot()),
    (name: 'Reel Spin', description: 'Consistent spinning loop', builder: () => reelSpin()),
    (name: 'Reel Stop 0', description: 'First reel (left)', builder: () => reelStop(reelIndex: 0)),
    (name: 'Reel Stop 1', description: 'Second reel', builder: () => reelStop(reelIndex: 1)),
    (name: 'Reel Stop 2', description: 'Center reel', builder: () => reelStop(reelIndex: 2)),
    (name: 'Reel Stop 3', description: 'Fourth reel', builder: () => reelStop(reelIndex: 3)),
    (name: 'Reel Stop 4', description: 'Fifth reel (right)', builder: () => reelStop(reelIndex: 4)),
    (name: 'UI Click', description: 'Tight, dry button clicks', builder: () => uiClick()),
    (name: 'Coin Fly', description: 'Motion-tracked coins', builder: () => coinFly()),
    (name: 'Anticipation', description: 'Building tension', builder: () => anticipation()),
    (name: 'Free Spins Trigger', description: 'Exciting feature trigger', builder: () => freeSpinsTrigger()),
    (name: 'Wild Land', description: 'Punchy wild symbol', builder: () => wildLand()),
    (name: 'Voice Over', description: 'Centered, clear VO', builder: () => voiceOver()),
  ];
}

/// Provider for AutoSpatialEngine state management
class AutoSpatialProvider extends ChangeNotifier {
  /// Singleton instance
  static final AutoSpatialProvider instance = AutoSpatialProvider._internal();
  factory AutoSpatialProvider() => instance;
  AutoSpatialProvider._internal();

  /// The underlying Dart engine
  late AutoSpatialEngine _engine;
  bool _initialized = false;

  /// Whether FFI (Rust) spatial processing is available
  bool _ffiAvailable = false;

  /// Custom intent rules (editable copy)
  final Map<String, IntentRule> _customRules = {};

  /// Custom bus policies (editable copy)
  final Map<SpatialBus, BusPolicy> _customPolicies = {};

  /// Real-time stats
  AutoSpatialStats _stats = const AutoSpatialStats();

  /// Stats refresh timer
  Timer? _statsTimer;

  /// Selected rule for editing
  String? _selectedRuleIntent;

  /// Selected bus for editing
  SpatialBus? _selectedBus;

  /// Whether editing is enabled
  bool _editingEnabled = false;

  /// A/B Comparison state
  bool _abCompareEnabled = false;
  Map<String, IntentRule>? _snapshotARules;
  Map<String, IntentRule>? _snapshotBRules;
  bool _abShowingB = false;

  // === GETTERS ===

  bool get isInitialized => _initialized;
  bool get ffiAvailable => _ffiAvailable;
  AutoSpatialEngine get engine => _engine;
  AnchorRegistry get anchorRegistry => _engine.anchorRegistry;
  AutoSpatialStats get stats => _stats;
  AutoSpatialConfig get config => _engine.config;

  /// Get all intent rules (custom + defaults)
  Map<String, IntentRule> get allRules => Map.unmodifiable(_customRules);

  /// Get all bus policies
  Map<SpatialBus, BusPolicy> get allPolicies => Map.unmodifiable(_customPolicies);

  /// Selected rule for editing
  String? get selectedRuleIntent => _selectedRuleIntent;
  IntentRule? get selectedRule =>
      _selectedRuleIntent != null ? _customRules[_selectedRuleIntent] : null;

  /// Selected bus for editing
  SpatialBus? get selectedBus => _selectedBus;
  BusPolicy? get selectedBusPolicy =>
      _selectedBus != null ? _customPolicies[_selectedBus] : null;

  bool get editingEnabled => _editingEnabled;

  /// A/B Comparison getters
  bool get abCompareEnabled => _abCompareEnabled;
  bool get abShowingB => _abShowingB;
  bool get hasSnapshotA => _snapshotARules != null;
  bool get hasSnapshotB => _snapshotBRules != null;

  /// Get active event count
  int get activeEventCount => _engine.activeCount;

  /// Get all registered anchor IDs
  Iterable<String> get anchorIds => anchorRegistry.anchorIds;

  /// Get anchor count
  int get anchorCount => anchorRegistry.count;

  // === INITIALIZATION ===

  /// Initialize the provider with an engine instance
  void initialize({AutoSpatialEngine? engine}) {
    if (_initialized) return;

    _engine = engine ?? AutoSpatialEngine();
    _initialized = true;

    // Try to initialize Rust FFI spatial engine
    try {
      if (NativeFFI.instance.isLoaded) {
        _ffiAvailable = NativeFFI.instance.autoSpatialInit();
        if (_ffiAvailable) {
        }
      }
    } catch (e) {
      _ffiAvailable = false;
    }

    // Copy default rules
    for (final rule in SlotIntentRules.defaults) {
      _customRules[rule.intent] = rule;
    }

    // Copy default policies
    for (final entry in BusPolicies.defaults.entries) {
      _customPolicies[entry.key] = entry.value;
    }

    // Start stats timer (10 Hz)
    _statsTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _refreshStats();
    });

    notifyListeners();
  }

  /// Refresh stats from engine
  void _refreshStats() {
    if (!_initialized) return;

    // Use FFI stats if available (more accurate for RT processing)
    if (_ffiAvailable) {
      try {
        final ffiStats = NativeFFI.instance.autoSpatialGetStats();
        final newStats = AutoSpatialStats(
          activeEvents: ffiStats.activeEvents,
          poolUtilization: ffiStats.poolUtilization.toInt(),
          totalEventsProcessed: _stats.totalEventsProcessed, // Not tracked in FFI
          avgProcessingTimeUs: ffiStats.processingTimeUs.toDouble(),
          peakProcessingTimeUs: ffiStats.processingTimeUs.toDouble(),
          droppedEvents: ffiStats.droppedEvents,
          eventsThisSecond: _stats.eventsThisSecond,
          rateLimitedEvents: 0,
        );
        if (newStats.activeEvents != _stats.activeEvents ||
            newStats.poolUtilization != _stats.poolUtilization) {
          _stats = newStats;
          notifyListeners();
        }
        return;
      } catch (e) {
        // Fall back to Dart engine stats
      }
    }

    final newStats = _engine.getStats();
    if (newStats.activeEvents != _stats.activeEvents ||
        newStats.totalEventsProcessed != _stats.totalEventsProcessed ||
        newStats.poolUtilization != _stats.poolUtilization) {
      _stats = newStats;
      notifyListeners();
    }
  }

  // === INTENT RULE MANAGEMENT ===

  /// Select a rule for editing
  void selectRule(String? intent) {
    if (_selectedRuleIntent != intent) {
      _selectedRuleIntent = intent;
      notifyListeners();
    }
  }

  /// Update a rule
  void updateRule(String intent, IntentRule newRule) {
    _customRules[intent] = newRule;
    notifyListeners();
  }

  /// Create a new rule
  void createRule(IntentRule rule) {
    if (!_customRules.containsKey(rule.intent)) {
      _customRules[rule.intent] = rule;
      notifyListeners();
    }
  }

  /// Create a rule from a template
  void createRuleFromTemplate(int templateIndex, {String? customIntent}) {
    if (templateIndex < 0 || templateIndex >= SpatialRuleTemplates.all.length) return;
    final template = SpatialRuleTemplates.all[templateIndex];
    final rule = template.builder();
    final intent = customIntent ?? rule.intent;

    // Ensure unique intent
    var finalIntent = intent;
    var counter = 1;
    while (_customRules.containsKey(finalIntent)) {
      finalIntent = '${intent}_$counter';
      counter++;
    }

    _customRules[finalIntent] = IntentRule(
      intent: finalIntent,
      defaultAnchorId: rule.defaultAnchorId,
      startAnchorFallback: rule.startAnchorFallback,
      endAnchorFallback: rule.endAnchorFallback,
      wAnchor: rule.wAnchor,
      wMotion: rule.wMotion,
      wIntent: rule.wIntent,
      width: rule.width,
      deadzone: rule.deadzone,
      maxPan: rule.maxPan,
      smoothingTauMs: rule.smoothingTauMs,
      velocitySmoothingTauMs: rule.velocitySmoothingTauMs,
      distanceModel: rule.distanceModel,
      minDistance: rule.minDistance,
      maxDistance: rule.maxDistance,
      rolloffFactor: rule.rolloffFactor,
      enableDoppler: rule.enableDoppler,
      dopplerScale: rule.dopplerScale,
      yToLPF: rule.yToLPF,
      distanceToLPF: rule.distanceToLPF,
      yToGain: rule.yToGain,
      baseReverbSend: rule.baseReverbSend,
      distanceReverbScale: rule.distanceReverbScale,
      lifetimeMs: rule.lifetimeMs,
      motionEasing: rule.motionEasing,
    );
    _selectedRuleIntent = finalIntent;
    notifyListeners();
  }

  /// Get list of available templates
  List<({String name, String description})> get availableTemplates =>
      SpatialRuleTemplates.all.map((t) => (name: t.name, description: t.description)).toList();

  /// Duplicate a rule
  void duplicateRule(String sourceIntent, String newIntent) {
    final source = _customRules[sourceIntent];
    if (source != null && !_customRules.containsKey(newIntent)) {
      _customRules[newIntent] = IntentRule(
        intent: newIntent,
        defaultAnchorId: source.defaultAnchorId,
        startAnchorFallback: source.startAnchorFallback,
        endAnchorFallback: source.endAnchorFallback,
        wAnchor: source.wAnchor,
        wMotion: source.wMotion,
        wIntent: source.wIntent,
        width: source.width,
        deadzone: source.deadzone,
        maxPan: source.maxPan,
        smoothingTauMs: source.smoothingTauMs,
        velocitySmoothingTauMs: source.velocitySmoothingTauMs,
        distanceModel: source.distanceModel,
        minDistance: source.minDistance,
        maxDistance: source.maxDistance,
        rolloffFactor: source.rolloffFactor,
        enableDoppler: source.enableDoppler,
        dopplerScale: source.dopplerScale,
        yToLPF: source.yToLPF,
        distanceToLPF: source.distanceToLPF,
        yToGain: source.yToGain,
        baseReverbSend: source.baseReverbSend,
        distanceReverbScale: source.distanceReverbScale,
        lifetimeMs: source.lifetimeMs,
        motionEasing: source.motionEasing,
      );
      notifyListeners();
    }
  }

  /// Delete a rule
  void deleteRule(String intent) {
    if (_customRules.containsKey(intent)) {
      _customRules.remove(intent);
      if (_selectedRuleIntent == intent) {
        _selectedRuleIntent = null;
      }
      notifyListeners();
    }
  }

  /// Reset a rule to default
  void resetRuleToDefault(String intent) {
    final defaultRule = SlotIntentRules.defaults.firstWhere(
      (r) => r.intent == intent,
      orElse: () => SlotIntentRules.defaults.last, // DEFAULT
    );
    _customRules[intent] = defaultRule;
    notifyListeners();
  }

  /// Reset all rules to defaults
  void resetAllRulesToDefaults() {
    _customRules.clear();
    for (final rule in SlotIntentRules.defaults) {
      _customRules[rule.intent] = rule;
    }
    notifyListeners();
  }

  // === A/B COMPARISON ===

  /// Enable A/B comparison mode (snapshot current as A)
  void enableAbComparison() {
    if (_abCompareEnabled) return;
    _abCompareEnabled = true;
    _snapshotARules = Map.from(_customRules);
    _snapshotBRules = null;
    _abShowingB = false;
    notifyListeners();
  }

  /// Disable A/B comparison mode
  void disableAbComparison() {
    _abCompareEnabled = false;
    _snapshotARules = null;
    _snapshotBRules = null;
    _abShowingB = false;
    notifyListeners();
  }

  /// Snapshot current state as B
  void snapshotB() {
    if (!_abCompareEnabled) return;
    _snapshotBRules = Map.from(_customRules);
    notifyListeners();
  }

  /// Toggle between A and B
  void toggleAb() {
    if (!_abCompareEnabled) return;
    if (_abShowingB && _snapshotARules != null) {
      // Switch to A
      _customRules.clear();
      _customRules.addAll(_snapshotARules!);
      _abShowingB = false;
    } else if (!_abShowingB && _snapshotBRules != null) {
      // Switch to B
      _customRules.clear();
      _customRules.addAll(_snapshotBRules!);
      _abShowingB = true;
    }
    notifyListeners();
  }

  /// Show A preset
  void showA() {
    if (!_abCompareEnabled || _snapshotARules == null) return;
    _customRules.clear();
    _customRules.addAll(_snapshotARules!);
    _abShowingB = false;
    notifyListeners();
  }

  /// Show B preset
  void showB() {
    if (!_abCompareEnabled || _snapshotBRules == null) return;
    _customRules.clear();
    _customRules.addAll(_snapshotBRules!);
    _abShowingB = true;
    notifyListeners();
  }

  /// Keep current (A or B) and exit comparison mode
  void keepCurrentAndExitAb() {
    _abCompareEnabled = false;
    _snapshotARules = null;
    _snapshotBRules = null;
    _abShowingB = false;
    notifyListeners();
  }

  // === BUS POLICY MANAGEMENT ===

  /// Select a bus for editing
  void selectBus(SpatialBus? bus) {
    if (_selectedBus != bus) {
      _selectedBus = bus;
      notifyListeners();
    }
  }

  /// Update a bus policy
  void updateBusPolicy(SpatialBus bus, BusPolicy policy) {
    _customPolicies[bus] = policy;
    notifyListeners();
  }

  /// Reset a bus policy to default
  void resetBusPolicyToDefault(SpatialBus bus) {
    _customPolicies[bus] = BusPolicies.defaults[bus]!;
    notifyListeners();
  }

  /// Reset all bus policies to defaults
  void resetAllBusPoliciesToDefaults() {
    _customPolicies.clear();
    for (final entry in BusPolicies.defaults.entries) {
      _customPolicies[entry.key] = entry.value;
    }
    notifyListeners();
  }

  // === CONFIG MANAGEMENT ===

  /// Set render mode
  void setRenderMode(SpatialRenderMode mode) {
    _engine.setRenderMode(mode);
    notifyListeners();
  }

  /// Set listener position
  void setListenerPosition(ListenerPosition position) {
    _engine.setListenerPosition(position);
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialSetListener(
        position.x,
        position.y,
        position.z,
        position.rotationRad, // Already in radians
      );
    }
    notifyListeners();
  }

  /// Update config
  void updateConfig(AutoSpatialConfig newConfig) {
    _engine.config = newConfig;
    notifyListeners();
  }

  /// Toggle Doppler
  void setDopplerEnabled(bool enabled) {
    _engine.config = _engine.config.copyWith(enableDoppler: enabled);
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialSetDopplerEnabled(enabled);
    }
    notifyListeners();
  }

  /// Toggle distance attenuation
  void setDistanceAttenuationEnabled(bool enabled) {
    _engine.config = _engine.config.copyWith(enableDistanceAttenuation: enabled);
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialSetDistanceAttenEnabled(enabled);
    }
    notifyListeners();
  }

  /// Toggle occlusion
  void setOcclusionEnabled(bool enabled) {
    _engine.config = _engine.config.copyWith(enableOcclusion: enabled);
    notifyListeners();
  }

  /// Toggle reverb
  void setReverbEnabled(bool enabled) {
    _engine.config = _engine.config.copyWith(enableReverb: enabled);
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialSetReverbEnabled(enabled);
    }
    notifyListeners();
  }

  /// Toggle HRTF
  void setHRTFEnabled(bool enabled) {
    _engine.config = _engine.config.copyWith(enableHRTF: enabled);
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialSetHrtfEnabled(enabled);
    }
    notifyListeners();
  }

  /// Toggle frequency absorption
  void setFrequencyAbsorptionEnabled(bool enabled) {
    _engine.config = _engine.config.copyWith(enableFrequencyDependentAbsorption: enabled);
    notifyListeners();
  }

  /// Toggle event fade-out
  void setEventFadeOutEnabled(bool enabled) {
    _engine.config = _engine.config.copyWith(enableEventFadeOut: enabled);
    notifyListeners();
  }

  /// Set global pan scale
  void setGlobalPanScale(double scale) {
    _engine.config = _engine.config.copyWith(globalPanScale: scale.clamp(0.0, 2.0));
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialSetPanScale(scale);
    }
    notifyListeners();
  }

  /// Set global width scale
  void setGlobalWidthScale(double scale) {
    _engine.config = _engine.config.copyWith(globalWidthScale: scale.clamp(0.0, 2.0));
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialSetWidthScale(scale);
    }
    notifyListeners();
  }

  // === ANCHOR MANAGEMENT ===

  /// Get anchor frame by ID
  AnchorFrame? getAnchorFrame(String id) {
    return anchorRegistry.getFrame(id);
  }

  /// Register an anchor (for testing/manual)
  void registerAnchor({
    required String id,
    required double xNorm,
    required double yNorm,
    double wNorm = 0.1,
    double hNorm = 0.1,
    bool visible = true,
  }) {
    anchorRegistry.registerAnchor(
      id: id,
      xNorm: xNorm,
      yNorm: yNorm,
      wNorm: wNorm,
      hNorm: hNorm,
      visible: visible,
    );
    notifyListeners();
  }

  /// Unregister an anchor
  void unregisterAnchor(String id) {
    anchorRegistry.unregisterAnchor(id);
    notifyListeners();
  }

  // === EVENT MANAGEMENT ===

  /// Send a test event
  void sendTestEvent({
    required String intent,
    String? anchorId,
    double? xNorm,
    double? yNorm,
    SpatialBus bus = SpatialBus.sfx,
  }) {
    final event = SpatialEvent(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Test Event',
      intent: intent,
      bus: bus,
      timeMs: DateTime.now().millisecondsSinceEpoch,
      anchorId: anchorId,
      xNorm: xNorm,
      yNorm: yNorm,
    );
    _engine.onEvent(event);
    notifyListeners();
  }

  /// Clear all events
  void clearEvents() {
    _engine.clear();
    notifyListeners();
  }

  /// Get output for event
  SpatialOutput? getEventOutput(String eventId) {
    return _engine.getOutput(eventId);
  }

  /// Get all active event IDs
  Iterable<String> get activeEventIds => _engine.activeEventIds;

  // === EDITING MODE ===

  void setEditingEnabled(bool enabled) {
    if (_editingEnabled != enabled) {
      _editingEnabled = enabled;
      notifyListeners();
    }
  }

  // === EXPORT/IMPORT ===

  /// Export rules as JSON
  String exportRulesAsJson() {
    final List<Map<String, dynamic>> rulesJson = _customRules.values.map((r) {
      return {
        'intent': r.intent,
        'defaultAnchorId': r.defaultAnchorId,
        'startAnchorFallback': r.startAnchorFallback,
        'endAnchorFallback': r.endAnchorFallback,
        'wAnchor': r.wAnchor,
        'wMotion': r.wMotion,
        'wIntent': r.wIntent,
        'width': r.width,
        'deadzone': r.deadzone,
        'maxPan': r.maxPan,
        'smoothingTauMs': r.smoothingTauMs,
        'velocitySmoothingTauMs': r.velocitySmoothingTauMs,
        'distanceModel': r.distanceModel.name,
        'minDistance': r.minDistance,
        'maxDistance': r.maxDistance,
        'rolloffFactor': r.rolloffFactor,
        'enableDoppler': r.enableDoppler,
        'dopplerScale': r.dopplerScale,
        'yToLPF': r.yToLPF != null
            ? {'minHz': r.yToLPF!.minHz, 'maxHz': r.yToLPF!.maxHz}
            : null,
        'distanceToLPF': r.distanceToLPF != null
            ? {'minHz': r.distanceToLPF!.minHz, 'maxHz': r.distanceToLPF!.maxHz}
            : null,
        'yToGain': r.yToGain != null
            ? {'minDb': r.yToGain!.minDb, 'maxDb': r.yToGain!.maxDb}
            : null,
        'baseReverbSend': r.baseReverbSend,
        'distanceReverbScale': r.distanceReverbScale,
        'lifetimeMs': r.lifetimeMs,
        'motionEasing': r.motionEasing.name,
      };
    }).toList();
    return const JsonEncoder.withIndent('  ').convert({'rules': rulesJson});
  }

  /// Import rules from JSON
  void importRulesFromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final rulesJson = data['rules'] as List<dynamic>;

      for (final rJson in rulesJson) {
        final r = rJson as Map<String, dynamic>;
        final intent = r['intent'] as String;

        final rule = IntentRule(
          intent: intent,
          defaultAnchorId: r['defaultAnchorId'] as String?,
          startAnchorFallback: r['startAnchorFallback'] as String?,
          endAnchorFallback: r['endAnchorFallback'] as String?,
          wAnchor: (r['wAnchor'] as num?)?.toDouble() ?? 0.5,
          wMotion: (r['wMotion'] as num?)?.toDouble() ?? 0.3,
          wIntent: (r['wIntent'] as num?)?.toDouble() ?? 0.2,
          width: (r['width'] as num?)?.toDouble() ?? 0.5,
          deadzone: (r['deadzone'] as num?)?.toDouble() ?? 0.04,
          maxPan: (r['maxPan'] as num?)?.toDouble() ?? 0.95,
          smoothingTauMs: (r['smoothingTauMs'] as num?)?.toDouble() ?? 70,
          velocitySmoothingTauMs:
              (r['velocitySmoothingTauMs'] as num?)?.toDouble() ?? 100,
          distanceModel: DistanceModel.values.firstWhere(
            (m) => m.name == r['distanceModel'],
            orElse: () => DistanceModel.inverseSquare,
          ),
          minDistance: (r['minDistance'] as num?)?.toDouble() ?? 0.1,
          maxDistance: (r['maxDistance'] as num?)?.toDouble() ?? 1.0,
          rolloffFactor: (r['rolloffFactor'] as num?)?.toDouble() ?? 1.0,
          enableDoppler: r['enableDoppler'] as bool? ?? false,
          dopplerScale: (r['dopplerScale'] as num?)?.toDouble() ?? 1.0,
          yToLPF: r['yToLPF'] != null
              ? (
                  minHz: (r['yToLPF']['minHz'] as num).toDouble(),
                  maxHz: (r['yToLPF']['maxHz'] as num).toDouble(),
                )
              : null,
          distanceToLPF: r['distanceToLPF'] != null
              ? (
                  minHz: (r['distanceToLPF']['minHz'] as num).toDouble(),
                  maxHz: (r['distanceToLPF']['maxHz'] as num).toDouble(),
                )
              : null,
          yToGain: r['yToGain'] != null
              ? (
                  minDb: (r['yToGain']['minDb'] as num).toDouble(),
                  maxDb: (r['yToGain']['maxDb'] as num).toDouble(),
                )
              : null,
          baseReverbSend: (r['baseReverbSend'] as num?)?.toDouble() ?? 0.0,
          distanceReverbScale:
              (r['distanceReverbScale'] as num?)?.toDouble() ?? 0.3,
          lifetimeMs: (r['lifetimeMs'] as num?)?.toInt() ?? 1000,
          motionEasing: EasingFunction.values.firstWhere(
            (e) => e.name == r['motionEasing'],
            orElse: () => EasingFunction.linear,
          ),
        );

        _customRules[intent] = rule;
      }

      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  // === CLEANUP ===

  @override
  void dispose() {
    _statsTimer?.cancel();
    _engine.dispose();
    if (_ffiAvailable) {
      NativeFFI.instance.autoSpatialShutdown();
    }
    super.dispose();
  }

  // === FFI SPATIAL EVENT TRACKING ===

  /// Start tracking an event via FFI (returns event ID, 0 on failure)
  int startFfiEvent(String intent, double x, double y, double z, int busId) {
    if (!_ffiAvailable) return 0;
    return NativeFFI.instance.autoSpatialStartEvent(intent, x, y, z, busId);
  }

  /// Update FFI event position
  bool updateFfiEvent(int eventId, double x, double y, double z) {
    if (!_ffiAvailable) return false;
    return NativeFFI.instance.autoSpatialUpdateEvent(eventId, x, y, z);
  }

  /// Stop FFI event tracking
  bool stopFfiEvent(int eventId) {
    if (!_ffiAvailable) return false;
    return NativeFFI.instance.autoSpatialStopEvent(eventId);
  }

  /// Get FFI spatial output for an event
  SpatialOutputData? getFfiEventOutput(int eventId) {
    if (!_ffiAvailable) return null;
    return NativeFFI.instance.autoSpatialGetOutput(eventId);
  }

  /// Tick FFI engine (call each frame)
  void tickFfi(int dtMs) {
    if (!_ffiAvailable) return;
    NativeFFI.instance.autoSpatialTick(dtMs);
  }
}
