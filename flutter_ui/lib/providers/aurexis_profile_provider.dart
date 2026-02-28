import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/aurexis_profile.dart';
import '../models/aurexis_jurisdiction.dart';
import 'aurexis_provider.dart';

/// Manages AUREXIS profile selection, A/B comparison, and custom profiles.
///
/// Sits on top of [AurexisProvider] — translates profile behavior parameters
/// into engine configuration and applies them.
///
/// Register as GetIt singleton (Layer 5.9.4, after AurexisProvider).
class AurexisProfileProvider extends ChangeNotifier {
  final AurexisProvider _engine;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Currently active profile.
  AurexisProfile _activeProfile = AurexisBuiltInProfiles.standardVideo;

  /// Custom user profiles.
  final List<AurexisProfile> _customProfiles = [];

  /// A/B comparison state.
  AurexisProfileSnapshot? _snapshotA;
  AurexisProfileSnapshot? _snapshotB;
  bool _abActive = false;
  bool _showingB = false;

  /// Per-group lock state. When a group is locked, profile changes
  /// do not affect that group's behavior parameters.
  bool _lockSpatial = false;
  bool _lockDynamics = false;
  bool _lockMusic = false;
  bool _lockVariation = false;

  /// Whether behavior has been modified from the active profile's defaults.
  bool _modified = false;

  /// Active jurisdiction.
  AurexisJurisdiction _jurisdiction = AurexisJurisdiction.none;

  /// Cached compliance report.
  JurisdictionComplianceReport? _complianceReport;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  AurexisProfile get activeProfile => _activeProfile;
  List<AurexisProfile> get customProfiles => List.unmodifiable(_customProfiles);
  bool get abActive => _abActive;
  bool get showingB => _showingB;
  bool get modified => _modified;
  bool get lockSpatial => _lockSpatial;
  bool get lockDynamics => _lockDynamics;
  bool get lockMusic => _lockMusic;
  bool get lockVariation => _lockVariation;
  AurexisProfileSnapshot? get snapshotA => _snapshotA;
  AurexisProfileSnapshot? get snapshotB => _snapshotB;
  AurexisJurisdiction get jurisdiction => _jurisdiction;
  JurisdictionComplianceReport? get complianceReport => _complianceReport;
  JurisdictionRules get jurisdictionRules => JurisdictionDatabase.getRules(_jurisdiction);

  /// All available profiles (built-in + custom).
  List<AurexisProfile> get allProfiles => [
    ...AurexisBuiltInProfiles.all,
    ..._customProfiles,
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  AurexisProfileProvider({required AurexisProvider engine}) : _engine = engine;

  // ═══════════════════════════════════════════════════════════════════════════
  // PROFILE SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select and apply a profile by ID.
  void selectProfile(String profileId) {
    AurexisProfile? profile = AurexisBuiltInProfiles.findById(profileId);
    profile ??= _customProfiles.cast<AurexisProfile?>().firstWhere(
      (p) => p?.id == profileId,
      orElse: () => null,
    );
    if (profile == null) return;
    _applyProfile(profile);
  }

  /// Apply a profile directly.
  void applyProfile(AurexisProfile profile) => _applyProfile(profile);

  void _applyProfile(AurexisProfile profile) {
    // Build new behavior, respecting locks
    AurexisBehaviorConfig newBehavior = profile.behavior;

    if (_lockSpatial) {
      newBehavior = newBehavior.copyWith(spatial: _activeProfile.behavior.spatial);
    }
    if (_lockDynamics) {
      newBehavior = newBehavior.copyWith(dynamics: _activeProfile.behavior.dynamics);
    }
    if (_lockMusic) {
      newBehavior = newBehavior.copyWith(music: _activeProfile.behavior.music);
    }
    if (_lockVariation) {
      newBehavior = newBehavior.copyWith(variation: _activeProfile.behavior.variation);
    }

    _activeProfile = profile.copyWith(behavior: newBehavior);
    _modified = false;
    _pushToEngine();
    notifyListeners();
  }

  /// Set the master intensity and re-apply.
  void setIntensity(double intensity) {
    _activeProfile = _activeProfile.copyWith(
      intensity: intensity.clamp(0.0, 1.0),
    );
    _modified = true;
    _pushToEngine();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BEHAVIOR SETTERS (individual parameter tweaks)
  // ═══════════════════════════════════════════════════════════════════════════

  void setSpatialWidth(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      spatial: _activeProfile.behavior.spatial.copyWith(width: value.clamp(0.0, 1.0)),
    ),
  );

  void setSpatialDepth(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      spatial: _activeProfile.behavior.spatial.copyWith(depth: value.clamp(0.0, 1.0)),
    ),
  );

  void setSpatialMovement(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      spatial: _activeProfile.behavior.spatial.copyWith(movement: value.clamp(0.0, 1.0)),
    ),
  );

  void setDynamicsEscalation(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      dynamics: _activeProfile.behavior.dynamics.copyWith(escalation: value.clamp(0.0, 1.0)),
    ),
  );

  void setDynamicsDucking(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      dynamics: _activeProfile.behavior.dynamics.copyWith(ducking: value.clamp(0.0, 1.0)),
    ),
  );

  void setDynamicsFatigue(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      dynamics: _activeProfile.behavior.dynamics.copyWith(fatigue: value.clamp(0.0, 1.0)),
    ),
  );

  void setMusicReactivity(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      music: _activeProfile.behavior.music.copyWith(reactivity: value.clamp(0.0, 1.0)),
    ),
  );

  void setMusicLayerBias(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      music: _activeProfile.behavior.music.copyWith(layerBias: value.clamp(0.0, 1.0)),
    ),
  );

  void setMusicTransition(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      music: _activeProfile.behavior.music.copyWith(transition: value.clamp(0.0, 1.0)),
    ),
  );

  void setVariationPanDrift(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      variation: _activeProfile.behavior.variation.copyWith(panDrift: value.clamp(0.0, 1.0)),
    ),
  );

  void setVariationWidthVar(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      variation: _activeProfile.behavior.variation.copyWith(widthVar: value.clamp(0.0, 1.0)),
    ),
  );

  void setVariationTimingVar(double value) => _updateBehavior(
    _activeProfile.behavior.copyWith(
      variation: _activeProfile.behavior.variation.copyWith(timingVar: value.clamp(0.0, 1.0)),
    ),
  );

  void _updateBehavior(AurexisBehaviorConfig behavior) {
    _activeProfile = _activeProfile.copyWith(behavior: behavior);
    _modified = true;
    _pushToEngine();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP LOCKS
  // ═══════════════════════════════════════════════════════════════════════════

  void toggleLockSpatial() {
    _lockSpatial = !_lockSpatial;
    notifyListeners();
  }

  void toggleLockDynamics() {
    _lockDynamics = !_lockDynamics;
    notifyListeners();
  }

  void toggleLockMusic() {
    _lockMusic = !_lockMusic;
    notifyListeners();
  }

  void toggleLockVariation() {
    _lockVariation = !_lockVariation;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // A/B COMPARISON
  // ═══════════════════════════════════════════════════════════════════════════

  /// Capture current state as snapshot A.
  void captureA() {
    _snapshotA = AurexisProfileSnapshot(
      profile: _activeProfile,
      engineConfig: _activeProfile.generateEngineConfig(),
    );
    _abActive = _snapshotB != null;
    notifyListeners();
  }

  /// Capture current state as snapshot B.
  void captureB() {
    _snapshotB = AurexisProfileSnapshot(
      profile: _activeProfile,
      engineConfig: _activeProfile.generateEngineConfig(),
    );
    _abActive = _snapshotA != null;
    notifyListeners();
  }

  /// Toggle between A and B snapshots.
  void toggleAB() {
    if (!_abActive) return;
    _showingB = !_showingB;

    final snapshot = _showingB ? _snapshotB : _snapshotA;
    if (snapshot != null) {
      _engine.loadConfig(jsonEncode(snapshot.engineConfig));
    }
    notifyListeners();
  }

  /// Deactivate A/B mode and restore current profile.
  void deactivateAB() {
    _abActive = false;
    _showingB = false;
    _pushToEngine();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOM PROFILES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save current settings as a new custom profile.
  AurexisProfile saveAsCustom(String name, {String description = ''}) {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final custom = _activeProfile.copyWith(
      id: id,
      name: name,
      description: description,
      category: AurexisProfileCategory.custom,
      builtIn: false,
      engineConfig: _activeProfile.generateEngineConfig(),
    );
    _customProfiles.add(custom);
    _activeProfile = custom;
    _modified = false;
    notifyListeners();
    return custom;
  }

  /// Delete a custom profile by ID.
  void deleteCustomProfile(String id) {
    _customProfiles.removeWhere((p) => p.id == id);
    if (_activeProfile.id == id) {
      _applyProfile(AurexisBuiltInProfiles.standardVideo);
    }
    notifyListeners();
  }

  /// Update an existing custom profile with current settings.
  void updateCustomProfile(String id) {
    final index = _customProfiles.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _customProfiles[index] = _activeProfile.copyWith(
      id: id,
      engineConfig: _activeProfile.generateEngineConfig(),
    );
    _modified = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reset current profile to its original (built-in or saved custom) values.
  void resetToDefault() {
    if (_activeProfile.builtIn) {
      final original = AurexisBuiltInProfiles.findById(_activeProfile.id);
      if (original != null) {
        _applyProfile(original);
        return;
      }
    }
    // Custom: reload from saved version
    final saved = _customProfiles.cast<AurexisProfile?>().firstWhere(
      (p) => p?.id == _activeProfile.id,
      orElse: () => null,
    );
    if (saved != null) {
      _applyProfile(saved);
    }
  }

  /// Reset a single behavior parameter to its profile default.
  void resetBehaviorParam(String group, String param) {
    AurexisProfile? original;
    if (_activeProfile.builtIn) {
      original = AurexisBuiltInProfiles.findById(_activeProfile.id);
    } else {
      original = _customProfiles.cast<AurexisProfile?>().firstWhere(
        (p) => p?.id == _activeProfile.id,
        orElse: () => null,
      );
    }
    original ??= AurexisBuiltInProfiles.standardVideo;

    final ob = original.behavior;
    final cb = _activeProfile.behavior;

    AurexisBehaviorConfig newBehavior = cb;
    switch ('$group.$param') {
      case 'spatial.width':
        newBehavior = cb.copyWith(spatial: cb.spatial.copyWith(width: ob.spatial.width));
      case 'spatial.depth':
        newBehavior = cb.copyWith(spatial: cb.spatial.copyWith(depth: ob.spatial.depth));
      case 'spatial.movement':
        newBehavior = cb.copyWith(spatial: cb.spatial.copyWith(movement: ob.spatial.movement));
      case 'dynamics.escalation':
        newBehavior = cb.copyWith(dynamics: cb.dynamics.copyWith(escalation: ob.dynamics.escalation));
      case 'dynamics.ducking':
        newBehavior = cb.copyWith(dynamics: cb.dynamics.copyWith(ducking: ob.dynamics.ducking));
      case 'dynamics.fatigue':
        newBehavior = cb.copyWith(dynamics: cb.dynamics.copyWith(fatigue: ob.dynamics.fatigue));
      case 'music.reactivity':
        newBehavior = cb.copyWith(music: cb.music.copyWith(reactivity: ob.music.reactivity));
      case 'music.layerBias':
        newBehavior = cb.copyWith(music: cb.music.copyWith(layerBias: ob.music.layerBias));
      case 'music.transition':
        newBehavior = cb.copyWith(music: cb.music.copyWith(transition: ob.music.transition));
      case 'variation.panDrift':
        newBehavior = cb.copyWith(variation: cb.variation.copyWith(panDrift: ob.variation.panDrift));
      case 'variation.widthVar':
        newBehavior = cb.copyWith(variation: cb.variation.copyWith(widthVar: ob.variation.widthVar));
      case 'variation.timingVar':
        newBehavior = cb.copyWith(variation: cb.variation.copyWith(timingVar: ob.variation.timingVar));
    }
    _updateBehavior(newBehavior);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-SELECT FROM GDD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Auto-select and apply the best profile based on GDD import data.
  void autoSelectFromGdd({
    required String volatility,
    required double rtp,
    String? mechanic,
    List<String>? features,
  }) {
    final profile = AurexisBuiltInProfiles.autoSelectFromGdd(
      volatility: volatility,
      rtp: rtp,
      mechanic: mechanic,
      features: features,
    );
    _applyProfile(profile);
    // Also push RTP to engine
    _engine.setRtp(rtp);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all custom profiles as JSON.
  String exportCustomProfilesJson() {
    return jsonEncode(_customProfiles.map((p) => p.toJson()).toList());
  }

  /// Import custom profiles from JSON.
  void importCustomProfiles(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    for (final item in list) {
      final profile = AurexisProfile.fromJson(item as Map<String, dynamic>);
      // Avoid duplicates
      if (!_customProfiles.any((p) => p.id == profile.id)) {
        _customProfiles.add(profile);
      }
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JURISDICTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set the active jurisdiction and apply its overrides.
  void setJurisdiction(AurexisJurisdiction jurisdiction) {
    _jurisdiction = jurisdiction;
    _complianceReport = null;
    _pushToEngine();
    notifyListeners();
  }

  /// Run compliance check against current jurisdiction.
  JurisdictionComplianceReport runComplianceCheck() {
    final params = _engine.parameters;
    _complianceReport = JurisdictionComplianceEngine.checkCompliance(
      jurisdiction: _jurisdiction,
      currentEscalationMultiplier: params.escalationMultiplier,
      currentFatigueRegulation: _activeProfile.behavior.dynamics.fatigue,
      currentWinVolumeBoostDb: params.subReinforcementDb,
      currentCelebrationDurationS: 5.0, // Default — will be driven by stage config
      isDeterministic: params.isDeterministic,
      hasLdwSuppression: _jurisdiction != AurexisJurisdiction.none,
      hasSessionTimeCues: _jurisdiction != AurexisJurisdiction.none,
    );
    notifyListeners();
    return _complianceReport!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Push current profile config to the Rust engine, applying jurisdiction overrides.
  void _pushToEngine() {
    if (!_engine.initialized) return;
    final config = _activeProfile.generateEngineConfig();

    // Apply jurisdiction overrides
    if (_jurisdiction != AurexisJurisdiction.none) {
      final overrides = JurisdictionComplianceEngine.getConfigOverrides(_jurisdiction);
      for (final entry in overrides.entries) {
        if (config.containsKey(entry.key) && entry.value is Map) {
          final section = config[entry.key] as Map<String, dynamic>;
          section.addAll((entry.value as Map).cast<String, dynamic>());
        }
      }
    }

    _engine.loadConfig(jsonEncode(config));
    _engine.setVolatility(_activeProfile.behavior.spatial.width);
  }
}
