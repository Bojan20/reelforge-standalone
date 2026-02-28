/// AUREXIS™ Cabinet Simulator — Speaker profiles & ambient noise presets.
///
/// Monitoring-only simulation of how slot audio sounds through
/// different playback hardware and ambient noise environments.
/// Does NOT process audio — only provides data for preview EQ/noise.

/// Speaker profile defining frequency response and imaging characteristics.
enum CabinetSpeakerProfile {
  /// IGT cabinet standard — 80Hz-12kHz, dual 4" + tweeter
  igt,

  /// Aristocrat cabinet — 60Hz-15kHz, 5" woofer + dome tweeter
  aristocrat,

  /// Generic multi-channel cabinet — 70Hz-14kHz, balanced
  generic,

  /// Studio reference monitors — 40Hz-20kHz, flat
  studioReference,

  /// Headphone simulation — 20Hz-20kHz, intimate imaging
  headphone,

  /// Mobile device — 200Hz-16kHz, small speaker roll-off
  mobile,

  /// Tablet device — 120Hz-18kHz, improved bass over mobile
  tablet,

  /// Bar-top terminal — 100Hz-15kHz, single small speaker
  barTop,

  /// Custom user-defined profile
  custom;

  String get label => switch (this) {
        igt => 'IGT Cabinet',
        aristocrat => 'Aristocrat Cabinet',
        generic => 'Generic Cabinet',
        studioReference => 'Studio Reference',
        headphone => 'Headphones',
        mobile => 'Mobile',
        tablet => 'Tablet',
        barTop => 'Bar-Top',
        custom => 'Custom',
      };

  String get shortLabel => switch (this) {
        igt => 'IGT',
        aristocrat => 'ARST',
        generic => 'GEN',
        studioReference => 'REF',
        headphone => 'HP',
        mobile => 'MOB',
        tablet => 'TAB',
        barTop => 'BAR',
        custom => 'USR',
      };

  /// Speaker configuration description.
  String get speakerConfig => switch (this) {
        igt => '2×4" + 1" tweet, mono',
        aristocrat => '5" + dome tweet, stereo',
        generic => '4" full-range, stereo',
        studioReference => '5" + 1" dome, stereo',
        headphone => '40mm drivers, stereo',
        mobile => 'Micro speaker, mono',
        tablet => '2× micro speaker, stereo',
        barTop => '3" full-range, mono',
        custom => 'User defined',
      };

  /// Whether this profile is mono output.
  bool get isMono => switch (this) {
        igt => true,
        mobile => true,
        barTop => true,
        _ => false,
      };
}

/// EQ band for speaker frequency response simulation.
class CabinetEqBand {
  /// Center frequency in Hz.
  final double frequencyHz;

  /// Gain in dB (-24 to +12).
  final double gainDb;

  /// Q factor (bandwidth).
  final double q;

  /// Band type.
  final CabinetBandType type;

  const CabinetEqBand({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    this.type = CabinetBandType.peaking,
  });
}

/// EQ band type for cabinet simulation.
enum CabinetBandType {
  highPass,
  lowPass,
  peaking,
  highShelf,
  lowShelf,
}

/// Complete speaker response profile with EQ bands.
class CabinetSpeakerResponse {
  /// Speaker profile this response belongs to.
  final CabinetSpeakerProfile profile;

  /// EQ bands defining the frequency response curve.
  final List<CabinetEqBand> bands;

  /// Low frequency roll-off point in Hz (-3dB).
  final double lowCutHz;

  /// High frequency roll-off point in Hz (-3dB).
  final double highCutHz;

  /// Stereo width factor (0.0 = mono, 1.0 = full stereo).
  final double stereoWidth;

  /// Center imaging boost in dB (for mono-compatible profiles).
  final double centerBoostDb;

  /// Cabinet resonance frequency (adds coloration).
  final double resonanceHz;

  /// Cabinet resonance Q (narrower = more colored).
  final double resonanceQ;

  /// Resonance gain in dB.
  final double resonanceGainDb;

  const CabinetSpeakerResponse({
    required this.profile,
    required this.bands,
    this.lowCutHz = 20.0,
    this.highCutHz = 20000.0,
    this.stereoWidth = 1.0,
    this.centerBoostDb = 0.0,
    this.resonanceHz = 0.0,
    this.resonanceQ = 1.0,
    this.resonanceGainDb = 0.0,
  });

  /// Total number of filter stages (bands + highpass + lowpass + resonance).
  int get filterCount => bands.length + 2 + (resonanceHz > 0 ? 1 : 0);
}

/// Built-in speaker response database.
class CabinetSpeakerDatabase {
  CabinetSpeakerDatabase._();

  static CabinetSpeakerResponse getResponse(CabinetSpeakerProfile profile) {
    return switch (profile) {
      CabinetSpeakerProfile.igt => _igt,
      CabinetSpeakerProfile.aristocrat => _aristocrat,
      CabinetSpeakerProfile.generic => _generic,
      CabinetSpeakerProfile.studioReference => _studioReference,
      CabinetSpeakerProfile.headphone => _headphone,
      CabinetSpeakerProfile.mobile => _mobile,
      CabinetSpeakerProfile.tablet => _tablet,
      CabinetSpeakerProfile.barTop => _barTop,
      CabinetSpeakerProfile.custom => _flat,
    };
  }

  /// IGT — harsh mid presence, limited bass, early HF roll-off
  static const _igt = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.igt,
    lowCutHz: 80.0,
    highCutHz: 12000.0,
    stereoWidth: 0.0, // mono
    centerBoostDb: 3.0,
    resonanceHz: 850.0,
    resonanceQ: 2.5,
    resonanceGainDb: 2.5,
    bands: [
      CabinetEqBand(frequencyHz: 80, gainDb: -6, q: 0.7, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 250, gainDb: -2, q: 1.2),
      CabinetEqBand(frequencyHz: 1200, gainDb: 3, q: 0.8),
      CabinetEqBand(frequencyHz: 3500, gainDb: 1.5, q: 1.0),
      CabinetEqBand(frequencyHz: 8000, gainDb: -3, q: 0.6, type: CabinetBandType.highShelf),
      CabinetEqBand(frequencyHz: 12000, gainDb: -12, q: 0.5, type: CabinetBandType.lowPass),
    ],
  );

  /// Aristocrat — wider range, cleaner response
  static const _aristocrat = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.aristocrat,
    lowCutHz: 60.0,
    highCutHz: 15000.0,
    stereoWidth: 0.6,
    centerBoostDb: 1.5,
    resonanceHz: 650.0,
    resonanceQ: 3.0,
    resonanceGainDb: 1.5,
    bands: [
      CabinetEqBand(frequencyHz: 60, gainDb: -4, q: 0.7, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 200, gainDb: -1, q: 1.0),
      CabinetEqBand(frequencyHz: 800, gainDb: 1.5, q: 1.2),
      CabinetEqBand(frequencyHz: 3000, gainDb: 1.0, q: 0.8),
      CabinetEqBand(frequencyHz: 6000, gainDb: -1, q: 1.0),
      CabinetEqBand(frequencyHz: 15000, gainDb: -8, q: 0.5, type: CabinetBandType.lowPass),
    ],
  );

  /// Generic — balanced, typical slot floor cabinet
  static const _generic = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.generic,
    lowCutHz: 70.0,
    highCutHz: 14000.0,
    stereoWidth: 0.5,
    centerBoostDb: 2.0,
    resonanceHz: 750.0,
    resonanceQ: 2.0,
    resonanceGainDb: 1.0,
    bands: [
      CabinetEqBand(frequencyHz: 70, gainDb: -5, q: 0.7, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 300, gainDb: -1.5, q: 1.0),
      CabinetEqBand(frequencyHz: 1000, gainDb: 2, q: 1.0),
      CabinetEqBand(frequencyHz: 4000, gainDb: 0.5, q: 0.8),
      CabinetEqBand(frequencyHz: 10000, gainDb: -4, q: 0.7, type: CabinetBandType.highShelf),
      CabinetEqBand(frequencyHz: 14000, gainDb: -10, q: 0.5, type: CabinetBandType.lowPass),
    ],
  );

  /// Studio Reference — flat, full range
  static const _studioReference = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.studioReference,
    lowCutHz: 40.0,
    highCutHz: 20000.0,
    stereoWidth: 1.0,
    bands: [
      CabinetEqBand(frequencyHz: 40, gainDb: -2, q: 0.7, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 20000, gainDb: -1, q: 0.5, type: CabinetBandType.lowPass),
    ],
  );

  /// Headphones — intimate, wide stereo, presence bump
  static const _headphone = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.headphone,
    lowCutHz: 20.0,
    highCutHz: 20000.0,
    stereoWidth: 1.2, // slightly exaggerated
    bands: [
      CabinetEqBand(frequencyHz: 20, gainDb: -1, q: 0.7, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 100, gainDb: 1, q: 1.2),
      CabinetEqBand(frequencyHz: 2500, gainDb: -1.5, q: 2.0), // ear canal dip
      CabinetEqBand(frequencyHz: 5000, gainDb: 2, q: 1.0), // presence
      CabinetEqBand(frequencyHz: 8000, gainDb: 1.5, q: 0.8),
      CabinetEqBand(frequencyHz: 20000, gainDb: -1, q: 0.5, type: CabinetBandType.lowPass),
    ],
  );

  /// Mobile — very limited bass, boosted mids for intelligibility
  static const _mobile = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.mobile,
    lowCutHz: 200.0,
    highCutHz: 16000.0,
    stereoWidth: 0.0, // mono
    bands: [
      CabinetEqBand(frequencyHz: 200, gainDb: -12, q: 0.5, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 500, gainDb: -3, q: 1.0),
      CabinetEqBand(frequencyHz: 1500, gainDb: 4, q: 0.8), // mid boost for clarity
      CabinetEqBand(frequencyHz: 4000, gainDb: 2, q: 1.0),
      CabinetEqBand(frequencyHz: 8000, gainDb: -2, q: 0.8),
      CabinetEqBand(frequencyHz: 16000, gainDb: -8, q: 0.5, type: CabinetBandType.lowPass),
    ],
    resonanceHz: 1800.0,
    resonanceQ: 4.0,
    resonanceGainDb: 3.0, // small speaker resonance
  );

  /// Tablet — improved bass over mobile, narrow stereo
  static const _tablet = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.tablet,
    lowCutHz: 120.0,
    highCutHz: 18000.0,
    stereoWidth: 0.3,
    bands: [
      CabinetEqBand(frequencyHz: 120, gainDb: -8, q: 0.6, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 400, gainDb: -2, q: 1.0),
      CabinetEqBand(frequencyHz: 1200, gainDb: 3, q: 0.8),
      CabinetEqBand(frequencyHz: 3500, gainDb: 1.5, q: 1.0),
      CabinetEqBand(frequencyHz: 7000, gainDb: -1, q: 0.8),
      CabinetEqBand(frequencyHz: 18000, gainDb: -6, q: 0.5, type: CabinetBandType.lowPass),
    ],
    resonanceHz: 1200.0,
    resonanceQ: 3.0,
    resonanceGainDb: 2.0,
  );

  /// Bar-Top — small single speaker, very limited
  static const _barTop = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.barTop,
    lowCutHz: 100.0,
    highCutHz: 15000.0,
    stereoWidth: 0.0, // mono
    centerBoostDb: 2.5,
    resonanceHz: 1000.0,
    resonanceQ: 3.0,
    resonanceGainDb: 3.5,
    bands: [
      CabinetEqBand(frequencyHz: 100, gainDb: -8, q: 0.6, type: CabinetBandType.highPass),
      CabinetEqBand(frequencyHz: 350, gainDb: -3, q: 1.0),
      CabinetEqBand(frequencyHz: 1000, gainDb: 4, q: 0.7),
      CabinetEqBand(frequencyHz: 3000, gainDb: 2, q: 1.0),
      CabinetEqBand(frequencyHz: 6000, gainDb: -2, q: 0.8),
      CabinetEqBand(frequencyHz: 15000, gainDb: -10, q: 0.5, type: CabinetBandType.lowPass),
    ],
  );

  /// Flat (for custom — user overrides)
  static const _flat = CabinetSpeakerResponse(
    profile: CabinetSpeakerProfile.custom,
    lowCutHz: 20.0,
    highCutHz: 20000.0,
    stereoWidth: 1.0,
    bands: [],
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// AMBIENT NOISE
// ═════════════════════════════════════════════════════════════════════════════

/// Ambient noise environment preset for monitoring.
enum CabinetAmbientPreset {
  /// Silent — no ambient noise (studio monitoring)
  silent,

  /// Quiet casino — low hum, few machines (~40 dB SPL)
  quietCasino,

  /// Moderate casino — typical slot floor (~60 dB SPL)
  moderateCasino,

  /// Busy casino — peak hours, loud (~75 dB SPL)
  busyCasino,

  /// Very noisy floor — event/tournament conditions (~85 dB SPL)
  noisyFloor,

  /// Custom level
  custom;

  String get label => switch (this) {
        silent => 'Silent',
        quietCasino => 'Quiet Casino',
        moderateCasino => 'Moderate Casino',
        busyCasino => 'Busy Casino',
        noisyFloor => 'Noisy Floor',
        custom => 'Custom',
      };

  /// Approximate SPL in dB for this environment.
  double get splDb => switch (this) {
        silent => 0.0,
        quietCasino => 42.0,
        moderateCasino => 60.0,
        busyCasino => 75.0,
        noisyFloor => 85.0,
        custom => 0.0,
      };

  /// Relative mix level (0.0 = silent, 1.0 = full reference level).
  double get mixLevel => switch (this) {
        silent => 0.0,
        quietCasino => 0.12,
        moderateCasino => 0.30,
        busyCasino => 0.55,
        noisyFloor => 0.80,
        custom => 0.0,
      };
}

/// Pink noise spectral shaping for ambient noise simulation.
class CabinetAmbientConfig {
  /// Selected preset.
  final CabinetAmbientPreset preset;

  /// Custom level override (0.0-1.0, only used when preset=custom).
  final double customLevel;

  /// Spectral tilt — 0.0 = white noise, 1.0 = pink (-3 dB/oct),
  /// values > 1.0 = brownian.
  final double spectralTilt;

  /// High-cut filter for ambient (simulates distant noise).
  final double ambientHighCutHz;

  const CabinetAmbientConfig({
    this.preset = CabinetAmbientPreset.silent,
    this.customLevel = 0.0,
    this.spectralTilt = 1.0, // pink noise default
    this.ambientHighCutHz = 8000.0,
  });

  /// Effective mix level considering custom override.
  double get effectiveLevel =>
      preset == CabinetAmbientPreset.custom ? customLevel : preset.mixLevel;

  CabinetAmbientConfig copyWith({
    CabinetAmbientPreset? preset,
    double? customLevel,
    double? spectralTilt,
    double? ambientHighCutHz,
  }) {
    return CabinetAmbientConfig(
      preset: preset ?? this.preset,
      customLevel: customLevel ?? this.customLevel,
      spectralTilt: spectralTilt ?? this.spectralTilt,
      ambientHighCutHz: ambientHighCutHz ?? this.ambientHighCutHz,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CABINET STATE
// ═════════════════════════════════════════════════════════════════════════════

/// Complete cabinet simulator state.
class CabinetSimulatorState {
  /// Whether cabinet simulation is active (monitoring-only).
  final bool enabled;

  /// Selected speaker profile.
  final CabinetSpeakerProfile speakerProfile;

  /// Ambient noise configuration.
  final CabinetAmbientConfig ambient;

  /// Custom EQ bands (only used when speakerProfile=custom).
  final List<CabinetEqBand> customBands;

  /// Custom low cut Hz (only used when speakerProfile=custom).
  final double customLowCutHz;

  /// Custom high cut Hz (only used when speakerProfile=custom).
  final double customHighCutHz;

  /// Custom stereo width (only used when speakerProfile=custom).
  final double customStereoWidth;

  const CabinetSimulatorState({
    this.enabled = false,
    this.speakerProfile = CabinetSpeakerProfile.generic,
    this.ambient = const CabinetAmbientConfig(),
    this.customBands = const [],
    this.customLowCutHz = 20.0,
    this.customHighCutHz = 20000.0,
    this.customStereoWidth = 1.0,
  });

  /// Get the effective speaker response (built-in or custom).
  CabinetSpeakerResponse get effectiveResponse {
    if (speakerProfile == CabinetSpeakerProfile.custom) {
      return CabinetSpeakerResponse(
        profile: CabinetSpeakerProfile.custom,
        lowCutHz: customLowCutHz,
        highCutHz: customHighCutHz,
        stereoWidth: customStereoWidth,
        bands: customBands,
      );
    }
    return CabinetSpeakerDatabase.getResponse(speakerProfile);
  }

  CabinetSimulatorState copyWith({
    bool? enabled,
    CabinetSpeakerProfile? speakerProfile,
    CabinetAmbientConfig? ambient,
    List<CabinetEqBand>? customBands,
    double? customLowCutHz,
    double? customHighCutHz,
    double? customStereoWidth,
  }) {
    return CabinetSimulatorState(
      enabled: enabled ?? this.enabled,
      speakerProfile: speakerProfile ?? this.speakerProfile,
      ambient: ambient ?? this.ambient,
      customBands: customBands ?? this.customBands,
      customLowCutHz: customLowCutHz ?? this.customLowCutHz,
      customHighCutHz: customHighCutHz ?? this.customHighCutHz,
      customStereoWidth: customStereoWidth ?? this.customStereoWidth,
    );
  }
}
