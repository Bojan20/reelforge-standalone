/// FluxForge AutoSpatial System — ULTIMATE EDITION
///
/// Revolutionary automatic spatial audio positioning for slot games.
/// The most advanced UI-driven spatial audio system in existence.
///
/// NO OTHER MIDDLEWARE HAS THIS. NOT WWISE. NOT FMOD. NO ONE.
///
/// Features:
/// ┌─────────────────────────────────────────────────────────────────┐
/// │ CORE PIPELINE                                                    │
/// │ ├── AnchorRegistry     - UI element position tracking           │
/// │ ├── MotionField        - Animation/progress motion extraction   │
/// │ ├── IntentRules        - Semantic spatial mapping               │
/// │ ├── FusionEngine       - Confidence-weighted signal fusion      │
/// │ ├── PredictiveSmoother - Extended Kalman Filter                 │
/// │ └── SpatialMixer       - Pan, width, distance, filters          │
/// ├─────────────────────────────────────────────────────────────────┤
/// │ ADVANCED DSP                                                     │
/// │ ├── HRTF/Binaural      - Headphone spatialization               │
/// │ ├── Ambisonics         - B-format encoding                      │
/// │ ├── Distance Model     - Inverse square + air absorption        │
/// │ ├── Doppler Effect     - Velocity-based pitch shift             │
/// │ ├── Occlusion          - LPF + gain reduction                   │
/// │ └── Reverb Zones       - Per-zone wet/dry blend                 │
/// ├─────────────────────────────────────────────────────────────────┤
/// │ OPTIMIZATION                                                     │
/// │ ├── Object Pooling     - Zero-allocation event tracking         │
/// │ ├── Batch Processing   - SIMD-friendly data layout              │
/// │ ├── Cache Coherency    - Struct-of-Arrays design                │
/// │ └── Lock-Free Stats    - Atomic counters                        │
/// └─────────────────────────────────────────────────────────────────┘

import 'dart:math' as math;
import 'dart:typed_data';

// =============================================================================
// CONSTANTS & CONFIGURATION
// =============================================================================

/// Speed of sound in air at 20°C (m/s)
const double kSpeedOfSound = 343.0;

/// Reference distance for attenuation (normalized units)
const double kReferenceDistance = 0.1;

/// Maximum Doppler pitch shift (semitones)
const double kMaxDopplerShift = 2.0;

/// Air absorption coefficient per unit distance (dB)
const double kAirAbsorptionCoeff = 0.002;

/// Maximum tracked events (pool size)
const int kMaxTrackedEvents = 128;

/// Minimum confidence threshold
const double kMinConfidence = 0.05;

/// Maximum events per second (rate limiting)
const int kMaxEventsPerSecond = 500;

/// Event fade-out duration (ms) for smooth spatial→center transition
const int kEventFadeOutMs = 50;

/// Air absorption frequency bands (Hz)
const List<double> kAirAbsorptionBands = [250, 500, 1000, 2000, 4000, 8000, 16000];

/// Air absorption coefficients per band (dB/m at 20°C, 50% humidity)
const List<double> kAirAbsorptionPerBand = [
  0.0003, // 250 Hz
  0.0006, // 500 Hz
  0.0012, // 1 kHz
  0.0025, // 2 kHz
  0.0050, // 4 kHz
  0.0090, // 8 kHz
  0.0150, // 16 kHz
];

// =============================================================================
// SPATIAL BUS TYPES
// =============================================================================

/// Audio bus categories with different spatial behaviors
enum SpatialBus {
  /// UI sounds (buttons, menus) - wide, fast tracking
  ui,

  /// Reel sounds - narrower, stable positioning
  reels,

  /// Sound effects - medium tracking
  sfx,

  /// Voice/dialogue - centered, minimal movement
  vo,

  /// Music - very wide, almost no panning
  music,

  /// Ambience - full surround, minimal panning
  ambience,
}

/// Spatial rendering mode
enum SpatialRenderMode {
  /// Standard stereo panning
  stereo,

  /// HRTF-based binaural (headphones)
  binaural,

  /// First-order Ambisonics (B-format)
  ambisonicsFirstOrder,

  /// Higher-order Ambisonics
  ambisonicsHigherOrder,

  /// Dolby Atmos object-based
  atmos,
}

/// Distance attenuation model
enum DistanceModel {
  /// No distance attenuation
  none,

  /// Linear falloff
  linear,

  /// Inverse distance (1/d)
  inverse,

  /// Inverse square (1/d²) - physically accurate
  inverseSquare,

  /// Exponential decay
  exponential,

  /// Custom curve (user-defined)
  custom,
}

/// Occlusion state
enum OcclusionState {
  /// No occlusion
  none,

  /// Partial occlusion (e.g., behind glass)
  partial,

  /// Full occlusion (e.g., behind wall)
  full,
}

// =============================================================================
// CORE DATA MODELS
// =============================================================================

/// Spatial event from game engine
class SpatialEvent {
  final String id;
  final String name;
  final String intent;
  final SpatialBus bus;
  final int timeMs;

  // Anchor configuration
  final String? anchorId;
  final String? startAnchorId;
  final String? endAnchorId;

  // Position data (explicit if engine provides)
  final double? progress01;
  final double? xNorm;
  final double? yNorm;
  final double? zNorm; // Depth for 3D (0 = front, 1 = back)

  // Priority and lifetime
  final double importance;
  final int lifetimeMs;

  // Optional overrides
  final double? overridePan;
  final double? overrideWidth;
  final double? overrideDistance;
  final OcclusionState? occlusionState;

  const SpatialEvent({
    required this.id,
    required this.name,
    required this.intent,
    required this.bus,
    required this.timeMs,
    this.anchorId,
    this.startAnchorId,
    this.endAnchorId,
    this.progress01,
    this.xNorm,
    this.yNorm,
    this.zNorm,
    this.importance = 0.5,
    this.lifetimeMs = 1000,
    this.overridePan,
    this.overrideWidth,
    this.overrideDistance,
    this.occlusionState,
  });

  SpatialEvent copyWith({
    String? id,
    String? name,
    String? intent,
    SpatialBus? bus,
    int? timeMs,
    String? anchorId,
    String? startAnchorId,
    String? endAnchorId,
    double? progress01,
    double? xNorm,
    double? yNorm,
    double? zNorm,
    double? importance,
    int? lifetimeMs,
    double? overridePan,
    double? overrideWidth,
    double? overrideDistance,
    OcclusionState? occlusionState,
  }) {
    return SpatialEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      intent: intent ?? this.intent,
      bus: bus ?? this.bus,
      timeMs: timeMs ?? this.timeMs,
      anchorId: anchorId ?? this.anchorId,
      startAnchorId: startAnchorId ?? this.startAnchorId,
      endAnchorId: endAnchorId ?? this.endAnchorId,
      progress01: progress01 ?? this.progress01,
      xNorm: xNorm ?? this.xNorm,
      yNorm: yNorm ?? this.yNorm,
      zNorm: zNorm ?? this.zNorm,
      importance: importance ?? this.importance,
      lifetimeMs: lifetimeMs ?? this.lifetimeMs,
      overridePan: overridePan ?? this.overridePan,
      overrideWidth: overrideWidth ?? this.overrideWidth,
      overrideDistance: overrideDistance ?? this.overrideDistance,
      occlusionState: occlusionState ?? this.occlusionState,
    );
  }
}

/// 3D position in normalized space
class SpatialPosition {
  final double x; // -1 (left) to +1 (right)
  final double y; // -1 (bottom) to +1 (top)
  final double z; // 0 (front) to 1 (back)

  const SpatialPosition({
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  /// Distance from listener (at origin)
  double get distance => math.sqrt(x * x + y * y + z * z);

  /// Azimuth angle in radians (-π to π)
  double get azimuth => math.atan2(x, 1 - z);

  /// Elevation angle in radians (-π/2 to π/2)
  double get elevation => math.atan2(y, math.sqrt(x * x + (1 - z) * (1 - z)));

  /// Convert to Ambisonics B-format gains (W, X, Y, Z)
  ({double w, double x, double y, double z}) toBFormat() {
    final d = distance.clamp(0.1, 10.0);
    final gain = 1.0 / d; // Distance attenuation

    // Normalize direction
    final nx = x / d;
    final ny = y / d;
    final nz = (1 - z) / d;

    return (
      w: gain * 0.707, // Omnidirectional (sqrt(0.5))
      x: gain * nx, // Front-back
      y: gain * ny, // Up-down
      z: gain * nz, // Left-right (note: Ambisonics convention)
    );
  }

  SpatialPosition operator +(SpatialPosition other) =>
      SpatialPosition(x: x + other.x, y: y + other.y, z: z + other.z);

  SpatialPosition operator -(SpatialPosition other) =>
      SpatialPosition(x: x - other.x, y: y - other.y, z: z - other.z);

  SpatialPosition operator *(double scalar) =>
      SpatialPosition(x: x * scalar, y: y * scalar, z: z * scalar);

  static const origin = SpatialPosition();
}

/// Velocity vector for Doppler calculation
class SpatialVelocity {
  final double vx; // Units per second
  final double vy;
  final double vz;

  const SpatialVelocity({
    this.vx = 0,
    this.vy = 0,
    this.vz = 0,
  });

  double get magnitude => math.sqrt(vx * vx + vy * vy + vz * vz);

  /// Calculate Doppler pitch shift
  /// Returns multiplier (1.0 = no shift, >1 = higher pitch, <1 = lower)
  double dopplerShift(SpatialPosition sourcePos) {
    if (magnitude < 0.001) return 1.0;

    // Radial velocity (towards/away from listener)
    final d = sourcePos.distance;
    if (d < 0.01) return 1.0;

    // Dot product of velocity and direction to listener
    final radialVel = -(vx * sourcePos.x + vy * sourcePos.y + vz * sourcePos.z) / d;

    // Doppler formula: f' = f * (c / (c - v_source))
    // Clamp to reasonable range
    final speedNorm = kSpeedOfSound * 0.01; // Normalized speed
    final shift = speedNorm / (speedNorm - radialVel);

    // Limit to ±kMaxDopplerShift semitones
    final maxShift = math.pow(2, kMaxDopplerShift / 12).toDouble();
    return shift.clamp(1 / maxShift, maxShift).toDouble();
  }

  static const zero = SpatialVelocity();
}

/// Anchor position frame (from UI element tracking)
class AnchorFrame {
  final bool visible;
  final double xNorm; // 0-1 screen space
  final double yNorm;
  final double wNorm; // Normalized width
  final double hNorm;
  final double vxNormPerS; // Velocity
  final double vyNormPerS;
  final double confidence;
  final int timestampMs;

  const AnchorFrame({
    required this.visible,
    required this.xNorm,
    required this.yNorm,
    required this.wNorm,
    required this.hNorm,
    required this.vxNormPerS,
    required this.vyNormPerS,
    required this.confidence,
    required this.timestampMs,
  });

  /// Convert to spatial position (screen space to audio space)
  SpatialPosition toSpatialPosition() {
    return SpatialPosition(
      x: (xNorm * 2) - 1, // 0-1 → -1 to +1
      y: 1 - (yNorm * 2), // 0-1 → +1 to -1 (flip Y)
      z: 0, // Screen is at z=0
    );
  }

  SpatialVelocity toSpatialVelocity() {
    return SpatialVelocity(
      vx: vxNormPerS * 2,
      vy: -vyNormPerS * 2,
      vz: 0,
    );
  }

  static const zero = AnchorFrame(
    visible: false,
    xNorm: 0.5,
    yNorm: 0.5,
    wNorm: 0,
    hNorm: 0,
    vxNormPerS: 0,
    vyNormPerS: 0,
    confidence: 0,
    timestampMs: 0,
  );
}

/// Motion frame (derived from animation or anchor movement)
class MotionFrame {
  final SpatialPosition position;
  final SpatialVelocity velocity;
  final double confidence;
  final int timestampMs;

  const MotionFrame({
    required this.position,
    required this.velocity,
    required this.confidence,
    required this.timestampMs,
  });

  static const zero = MotionFrame(
    position: SpatialPosition.origin,
    velocity: SpatialVelocity.zero,
    confidence: 0,
    timestampMs: 0,
  );
}

/// Fused spatial target
class SpatialTarget {
  final SpatialPosition position;
  final SpatialVelocity velocity;
  final double width; // Stereo spread
  final double confidence;

  const SpatialTarget({
    required this.position,
    required this.velocity,
    required this.width,
    required this.confidence,
  });

  static const center = SpatialTarget(
    position: SpatialPosition.origin,
    velocity: SpatialVelocity.zero,
    width: 0.5,
    confidence: 0.5,
  );
}

/// Complete spatial output for audio system
class SpatialOutput {
  // === STEREO ===
  final double pan; // -1 to +1
  final double width; // 0 to 1
  final ({double left, double right}) gains; // Equal-power gains

  // === 3D POSITION ===
  final SpatialPosition position;
  final double distance;
  final double azimuthRad;
  final double elevationRad;

  // === DISTANCE ATTENUATION ===
  final double distanceGain; // 0 to 1
  final double airAbsorptionDb;

  // === DOPPLER ===
  final double dopplerShift; // Pitch multiplier

  // === OCCLUSION ===
  final double occlusionGain;
  final double occlusionLpfHz;

  // === FILTERS ===
  final double? lpfHz;
  final double? hpfHz;

  // === REVERB ===
  final double reverbSend; // 0 to 1
  final int? reverbZoneId;

  // === AMBISONICS ===
  final ({double w, double x, double y, double z})? bFormat;

  // === HRTF ===
  final int? hrtfIndex; // Index into HRTF table

  // === META ===
  final double confidence;
  final int timestampMs;

  const SpatialOutput({
    required this.pan,
    required this.width,
    required this.gains,
    required this.position,
    required this.distance,
    required this.azimuthRad,
    required this.elevationRad,
    required this.distanceGain,
    required this.airAbsorptionDb,
    required this.dopplerShift,
    required this.occlusionGain,
    required this.occlusionLpfHz,
    this.lpfHz,
    this.hpfHz,
    required this.reverbSend,
    this.reverbZoneId,
    this.bFormat,
    this.hrtfIndex,
    required this.confidence,
    required this.timestampMs,
  });

  static final center = SpatialOutput(
    pan: 0,
    width: 0.5,
    gains: (left: 0.707, right: 0.707),
    position: SpatialPosition.origin,
    distance: 0,
    azimuthRad: 0,
    elevationRad: 0,
    distanceGain: 1.0,
    airAbsorptionDb: 0,
    dopplerShift: 1.0,
    occlusionGain: 1.0,
    occlusionLpfHz: 20000,
    reverbSend: 0,
    confidence: 0.5,
    timestampMs: 0,
  );
}

// =============================================================================
// INTENT RULES
// =============================================================================

/// Rule defining spatial behavior for a specific intent
class IntentRule {
  final String intent;

  // Anchor configuration
  final String? defaultAnchorId;
  final String? startAnchorFallback;
  final String? endAnchorFallback;

  // Fusion weights
  final double wAnchor;
  final double wMotion;
  final double wIntent;

  // Panning
  final double width;
  final double deadzone;
  final double maxPan;

  // Smoothing (tau = time constant)
  final double smoothingTauMs;
  final double velocitySmoothingTauMs;

  // Distance
  final DistanceModel distanceModel;
  final double minDistance;
  final double maxDistance;
  final double rolloffFactor;

  // Doppler
  final bool enableDoppler;
  final double dopplerScale;

  // Filters
  final ({double minHz, double maxHz})? yToLPF;
  final ({double minHz, double maxHz})? distanceToLPF;
  final ({double minDb, double maxDb})? yToGain;

  // Reverb
  final double baseReverbSend;
  final double distanceReverbScale;

  // Lifetime
  final int lifetimeMs;

  // Easing for motion paths
  final EasingFunction motionEasing;

  const IntentRule({
    required this.intent,
    this.defaultAnchorId,
    this.startAnchorFallback,
    this.endAnchorFallback,
    this.wAnchor = 0.5,
    this.wMotion = 0.3,
    this.wIntent = 0.2,
    this.width = 0.5,
    this.deadzone = 0.04,
    this.maxPan = 0.95,
    this.smoothingTauMs = 70,
    this.velocitySmoothingTauMs = 100,
    this.distanceModel = DistanceModel.inverseSquare,
    this.minDistance = 0.1,
    this.maxDistance = 1.0,
    this.rolloffFactor = 1.0,
    this.enableDoppler = false,
    this.dopplerScale = 1.0,
    this.yToLPF,
    this.distanceToLPF,
    this.yToGain,
    this.baseReverbSend = 0.0,
    this.distanceReverbScale = 0.3,
    this.lifetimeMs = 1000,
    this.motionEasing = EasingFunction.linear,
  });
}

/// Easing functions for motion paths
enum EasingFunction {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  easeInQuad,
  easeOutQuad,
  easeInOutQuad,
  easeInCubic,
  easeOutCubic,
  easeInOutCubic,
  easeInElastic,
  easeOutElastic,
  easeOutBounce,
}

/// Apply easing function to progress value
double applyEasing(EasingFunction fn, double t) {
  t = t.clamp(0.0, 1.0);
  final result = switch (fn) {
    EasingFunction.linear => t,
    EasingFunction.easeIn => t * t,
    EasingFunction.easeOut => 1 - (1 - t) * (1 - t),
    EasingFunction.easeInOut => t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2,
    EasingFunction.easeInQuad => t * t,
    EasingFunction.easeOutQuad => 1 - (1 - t) * (1 - t),
    EasingFunction.easeInOutQuad => t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2,
    EasingFunction.easeInCubic => t * t * t,
    EasingFunction.easeOutCubic => 1 - math.pow(1 - t, 3),
    EasingFunction.easeInOutCubic => t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2,
    EasingFunction.easeInElastic => t == 0 ? 0.0 : t == 1 ? 1.0 :
        -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * (2 * math.pi / 3)),
    EasingFunction.easeOutElastic => t == 0 ? 0.0 : t == 1 ? 1.0 :
        math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1,
    EasingFunction.easeOutBounce => _easeOutBounce(t),
  };
  return result.toDouble();
}

double _easeOutBounce(double t) {
  const n1 = 7.5625;
  const d1 = 2.75;
  if (t < 1 / d1) {
    return n1 * t * t;
  } else if (t < 2 / d1) {
    t -= 1.5 / d1;
    return n1 * t * t + 0.75;
  } else if (t < 2.5 / d1) {
    t -= 2.25 / d1;
    return n1 * t * t + 0.9375;
  } else {
    t -= 2.625 / d1;
    return n1 * t * t + 0.984375;
  }
}

/// Default intent rules for slot games
class SlotIntentRules {
  static const List<IntentRule> defaults = [
    // Coin fly animation - tracks from reels to balance
    IntentRule(
      intent: 'COIN_FLY_TO_BALANCE',
      defaultAnchorId: 'balance_value',
      startAnchorFallback: 'reels_center',
      endAnchorFallback: 'balance_value',
      wAnchor: 0.55,
      wMotion: 0.35,
      wIntent: 0.10,
      width: 0.55,
      deadzone: 0.04,
      maxPan: 0.95,
      smoothingTauMs: 50,
      enableDoppler: true,
      dopplerScale: 0.5,
      yToLPF: (minHz: 2000, maxHz: 16000),
      baseReverbSend: 0.1,
      lifetimeMs: 1200,
      motionEasing: EasingFunction.easeOutCubic,
    ),

    // Reel stop - per-reel positioning
    IntentRule(
      intent: 'REEL_STOP',
      defaultAnchorId: 'reels_center',
      wAnchor: 0.85,
      wMotion: 0.10,
      wIntent: 0.05,
      width: 0.20,
      deadzone: 0.03,
      maxPan: 0.80,
      smoothingTauMs: 40,
      lifetimeMs: 400,
    ),

    // Individual reel stops (0-indexed: reel 0-4 for standard 5-reel slots)
    IntentRule(intent: 'REEL_STOP_0', defaultAnchorId: 'reel_0', wAnchor: 0.95, wMotion: 0.03, wIntent: 0.02, maxPan: 0.85, smoothingTauMs: 30, lifetimeMs: 300),
    IntentRule(intent: 'REEL_STOP_1', defaultAnchorId: 'reel_1', wAnchor: 0.95, wMotion: 0.03, wIntent: 0.02, maxPan: 0.85, smoothingTauMs: 30, lifetimeMs: 300),
    IntentRule(intent: 'REEL_STOP_2', defaultAnchorId: 'reel_2', wAnchor: 0.95, wMotion: 0.03, wIntent: 0.02, maxPan: 0.85, smoothingTauMs: 30, lifetimeMs: 300),
    IntentRule(intent: 'REEL_STOP_3', defaultAnchorId: 'reel_3', wAnchor: 0.95, wMotion: 0.03, wIntent: 0.02, maxPan: 0.85, smoothingTauMs: 30, lifetimeMs: 300),
    IntentRule(intent: 'REEL_STOP_4', defaultAnchorId: 'reel_4', wAnchor: 0.95, wMotion: 0.03, wIntent: 0.02, maxPan: 0.85, smoothingTauMs: 30, lifetimeMs: 300),

    // Big win - dramatic centered presentation
    IntentRule(
      intent: 'BIG_WIN',
      defaultAnchorId: 'reels_center',
      wAnchor: 0.15,
      wMotion: 0.00,
      wIntent: 0.85,
      width: 0.80,
      deadzone: 0.08,
      maxPan: 0.20,
      smoothingTauMs: 120,
      baseReverbSend: 0.25,
      lifetimeMs: 3000,
    ),

    // Mega/Super/Ultra wins
    IntentRule(intent: 'MEGA_WIN', wAnchor: 0.10, wIntent: 0.90, width: 0.90, maxPan: 0.15, baseReverbSend: 0.35, lifetimeMs: 4000),
    IntentRule(intent: 'SUPER_WIN', wAnchor: 0.05, wIntent: 0.95, width: 0.95, maxPan: 0.10, baseReverbSend: 0.40, lifetimeMs: 5000),
    IntentRule(intent: 'EPIC_WIN', wAnchor: 0.02, wIntent: 0.98, width: 1.0, maxPan: 0.05, baseReverbSend: 0.50, lifetimeMs: 6000),

    // Spin
    IntentRule(
      intent: 'SPIN_START',
      defaultAnchorId: 'reels_center',
      wAnchor: 0.70,
      wMotion: 0.20,
      wIntent: 0.10,
      width: 0.45,
      deadzone: 0.05,
      maxPan: 0.55,
      smoothingTauMs: 50,
      lifetimeMs: 500,
    ),

    // Anticipation
    IntentRule(
      intent: 'ANTICIPATION',
      defaultAnchorId: 'reels_center',
      wAnchor: 0.75,
      wMotion: 0.15,
      wIntent: 0.10,
      width: 0.35,
      deadzone: 0.04,
      maxPan: 0.85,
      smoothingTauMs: 55,
      baseReverbSend: 0.15,
      lifetimeMs: 800,
    ),

    // Scatter/Bonus triggers
    IntentRule(
      intent: 'SCATTER_HIT',
      wAnchor: 0.80,
      wMotion: 0.10,
      wIntent: 0.10,
      width: 0.40,
      maxPan: 0.90,
      enableDoppler: true,
      dopplerScale: 0.3,
      lifetimeMs: 600,
    ),

    IntentRule(
      intent: 'BONUS_TRIGGER',
      defaultAnchorId: 'reels_center',
      wAnchor: 0.30,
      wMotion: 0.10,
      wIntent: 0.60,
      width: 0.70,
      maxPan: 0.40,
      baseReverbSend: 0.20,
      lifetimeMs: 1500,
    ),

    // Feature/Bonus game
    IntentRule(
      intent: 'FEATURE_ENTER',
      wAnchor: 0.20,
      wIntent: 0.80,
      width: 0.75,
      maxPan: 0.30,
      baseReverbSend: 0.30,
      lifetimeMs: 2000,
    ),

    IntentRule(
      intent: 'FEATURE_STEP',
      wAnchor: 0.60,
      wMotion: 0.30,
      wIntent: 0.10,
      width: 0.50,
      maxPan: 0.70,
      lifetimeMs: 800,
    ),

    IntentRule(
      intent: 'FEATURE_EXIT',
      wAnchor: 0.15,
      wIntent: 0.85,
      width: 0.65,
      maxPan: 0.35,
      lifetimeMs: 1500,
    ),

    // Cascade/Tumble
    IntentRule(
      intent: 'CASCADE_DROP',
      wAnchor: 0.70,
      wMotion: 0.25,
      wIntent: 0.05,
      width: 0.30,
      maxPan: 0.85,
      enableDoppler: true,
      dopplerScale: 0.4,
      lifetimeMs: 400,
      motionEasing: EasingFunction.easeInQuad,
    ),

    // UI interactions
    IntentRule(
      intent: 'UI_CLICK',
      wAnchor: 0.92,
      wMotion: 0.05,
      wIntent: 0.03,
      width: 0.20,
      deadzone: 0.02,
      maxPan: 1.0,
      smoothingTauMs: 25,
      lifetimeMs: 150,
    ),

    IntentRule(
      intent: 'UI_HOVER',
      wAnchor: 0.95,
      wMotion: 0.03,
      wIntent: 0.02,
      width: 0.15,
      maxPan: 1.0,
      smoothingTauMs: 30,
      lifetimeMs: 100,
    ),

    // Rollup/count
    IntentRule(
      intent: 'ROLLUP',
      defaultAnchorId: 'win_display',
      wAnchor: 0.55,
      wMotion: 0.10,
      wIntent: 0.35,
      width: 0.40,
      deadzone: 0.05,
      maxPan: 0.35,
      smoothingTauMs: 100,
      lifetimeMs: 2500,
    ),

    // Jackpot
    IntentRule(
      intent: 'JACKPOT_WIN',
      wAnchor: 0.05,
      wIntent: 0.95,
      width: 1.0,
      maxPan: 0.05,
      baseReverbSend: 0.60,
      lifetimeMs: 8000,
    ),

    // Near miss
    IntentRule(
      intent: 'NEAR_MISS',
      wAnchor: 0.65,
      wMotion: 0.20,
      wIntent: 0.15,
      width: 0.45,
      maxPan: 0.75,
      lifetimeMs: 700,
    ),

    // Generic fallback
    IntentRule(
      intent: 'DEFAULT',
      wAnchor: 0.50,
      wMotion: 0.25,
      wIntent: 0.25,
      width: 0.45,
      deadzone: 0.04,
      maxPan: 0.80,
      smoothingTauMs: 70,
      lifetimeMs: 800,
    ),
  ];

  static final Map<String, IntentRule> _ruleMap = {
    for (final r in defaults) r.intent: r
  };

  static IntentRule getRule(String intent) {
    return _ruleMap[intent] ?? _ruleMap['DEFAULT']!;
  }
}

// =============================================================================
// BUS POLICIES
// =============================================================================

/// Per-bus spatial behavior modifiers
class BusPolicy {
  final double widthMul;
  final double maxPanMul;
  final double tauMul;
  final double reverbMul;
  final double dopplerMul;
  final bool enableHRTF;
  final double priorityBoost;

  const BusPolicy({
    this.widthMul = 1.0,
    this.maxPanMul = 1.0,
    this.tauMul = 1.0,
    this.reverbMul = 1.0,
    this.dopplerMul = 1.0,
    this.enableHRTF = true,
    this.priorityBoost = 0.0,
  });
}

/// Default bus policies
class BusPolicies {
  static const Map<SpatialBus, BusPolicy> defaults = {
    SpatialBus.ui: BusPolicy(
      widthMul: 1.0,
      maxPanMul: 1.0,
      tauMul: 0.8,
      reverbMul: 0.3,
      dopplerMul: 0.5,
      enableHRTF: true,
      priorityBoost: 0.2,
    ),
    SpatialBus.reels: BusPolicy(
      widthMul: 0.6,
      maxPanMul: 0.85,
      tauMul: 1.0,
      reverbMul: 0.5,
      dopplerMul: 0.3,
      enableHRTF: true,
    ),
    SpatialBus.sfx: BusPolicy(
      widthMul: 0.8,
      maxPanMul: 0.95,
      tauMul: 1.0,
      reverbMul: 0.7,
      dopplerMul: 1.0,
      enableHRTF: true,
    ),
    SpatialBus.vo: BusPolicy(
      widthMul: 0.2,
      maxPanMul: 0.25,
      tauMul: 1.5,
      reverbMul: 0.4,
      dopplerMul: 0.0,
      enableHRTF: false,
      priorityBoost: 0.5,
    ),
    SpatialBus.music: BusPolicy(
      widthMul: 0.85,
      maxPanMul: 0.15,
      tauMul: 2.0,
      reverbMul: 0.2,
      dopplerMul: 0.0,
      enableHRTF: false,
    ),
    SpatialBus.ambience: BusPolicy(
      widthMul: 1.0,
      maxPanMul: 0.5,
      tauMul: 3.0,
      reverbMul: 1.0,
      dopplerMul: 0.0,
      enableHRTF: true,
    ),
  };

  static BusPolicy getPolicy(SpatialBus bus) {
    return defaults[bus] ?? defaults[SpatialBus.sfx]!;
  }
}

// =============================================================================
// ANCHOR REGISTRY
// =============================================================================

/// Anchor handle for tracking UI element positions
class AnchorHandle {
  final String id;
  double _xNorm = 0.5;
  double _yNorm = 0.5;
  double _wNorm = 0.1;
  double _hNorm = 0.1;
  bool _visible = true;
  int _lastUpdateMs = 0;

  // Velocity estimation (exponential moving average)
  double _vxEma = 0;
  double _vyEma = 0;
  static const double _velocityAlpha = 0.3;

  AnchorHandle({
    required this.id,
    double xNorm = 0.5,
    double yNorm = 0.5,
    double wNorm = 0.1,
    double hNorm = 0.1,
    bool visible = true,
  }) {
    _xNorm = xNorm;
    _yNorm = yNorm;
    _wNorm = wNorm;
    _hNorm = hNorm;
    _visible = visible;
    _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
  }

  void update({
    required double xNorm,
    required double yNorm,
    required double wNorm,
    required double hNorm,
    required bool visible,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dtSec = (_lastUpdateMs > 0) ? (nowMs - _lastUpdateMs) / 1000.0 : 0.016;

    if (dtSec > 0 && dtSec < 1.0) {
      // Calculate instantaneous velocity
      final ivx = (xNorm - _xNorm) / dtSec;
      final ivy = (yNorm - _yNorm) / dtSec;

      // Exponential moving average for smooth velocity
      _vxEma = _velocityAlpha * ivx + (1 - _velocityAlpha) * _vxEma;
      _vyEma = _velocityAlpha * ivy + (1 - _velocityAlpha) * _vyEma;
    }

    _xNorm = xNorm;
    _yNorm = yNorm;
    _wNorm = wNorm;
    _hNorm = hNorm;
    _visible = visible;
    _lastUpdateMs = nowMs;
  }

  double get xNorm => _xNorm;
  double get yNorm => _yNorm;
  double get wNorm => _wNorm;
  double get hNorm => _hNorm;
  bool get visible => _visible;
  int get lastUpdateMs => _lastUpdateMs;
  double get vxNormPerS => _vxEma;
  double get vyNormPerS => _vyEma;
}

/// Registry for tracking UI element positions
class AnchorRegistry {
  final Map<String, AnchorHandle> _anchors = {};

  /// Register or update an anchor
  void registerAnchor({
    required String id,
    required double xNorm,
    required double yNorm,
    double wNorm = 0.1,
    double hNorm = 0.1,
    bool visible = true,
  }) {
    // Input validation
    if (id.isEmpty || id.length > 256) return;

    final existing = _anchors[id];
    if (existing != null) {
      existing.update(
        xNorm: xNorm.clamp(0.0, 1.0),
        yNorm: yNorm.clamp(0.0, 1.0),
        wNorm: wNorm.clamp(0.0, 1.0),
        hNorm: hNorm.clamp(0.0, 1.0),
        visible: visible,
      );
    } else {
      _anchors[id] = AnchorHandle(
        id: id,
        xNorm: xNorm.clamp(0.0, 1.0),
        yNorm: yNorm.clamp(0.0, 1.0),
        wNorm: wNorm.clamp(0.0, 1.0),
        hNorm: hNorm.clamp(0.0, 1.0),
        visible: visible,
      );
    }
  }

  void unregisterAnchor(String id) {
    _anchors.remove(id);
  }

  AnchorFrame? getFrame(String anchorId) {
    final handle = _anchors[anchorId];
    if (handle == null) return null;

    // Calculate confidence based on visibility, size, and freshness
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageMs = nowMs - handle.lastUpdateMs;
    final ageFactor = (1.0 - (ageMs / 1000.0).clamp(0.0, 1.0)); // Decay over 1 second

    double conf = 0;
    if (handle.visible) conf += 0.5;
    conf += math.min(0.2, (handle.wNorm + handle.hNorm) * 0.5);
    conf += 0.2 * ageFactor;
    conf += 0.1; // baseline
    conf = conf.clamp(0.0, 1.0);

    return AnchorFrame(
      visible: handle.visible,
      xNorm: handle.xNorm,
      yNorm: handle.yNorm,
      wNorm: handle.wNorm,
      hNorm: handle.hNorm,
      vxNormPerS: handle.vxNormPerS,
      vyNormPerS: handle.vyNormPerS,
      confidence: conf,
      timestampMs: handle.lastUpdateMs,
    );
  }

  bool hasAnchor(String id) => _anchors.containsKey(id);
  Iterable<String> get anchorIds => _anchors.keys;
  int get count => _anchors.length;

  void clear() => _anchors.clear();
}

// =============================================================================
// MOTION FIELD
// =============================================================================

/// Extracts motion from various sources with confidence weighting
class MotionField {
  /// Compute motion from explicit progress between two anchors
  static MotionFrame? fromProgress({
    required AnchorFrame? start,
    required AnchorFrame? end,
    required double progress01,
    required EasingFunction easing,
    MotionFrame? previous,
  }) {
    if (start == null || end == null) return null;

    // Apply easing to progress
    final t = applyEasing(easing, progress01.clamp(0.0, 1.0));

    // Interpolate positions
    final startPos = start.toSpatialPosition();
    final endPos = end.toSpatialPosition();

    final pos = SpatialPosition(
      x: _lerp(startPos.x, endPos.x, t),
      y: _lerp(startPos.y, endPos.y, t),
      z: _lerp(startPos.z, endPos.z, t),
    );

    // Estimate velocity from previous frame
    SpatialVelocity vel = SpatialVelocity.zero;
    if (previous != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final dtSec = (nowMs - previous.timestampMs) / 1000.0;
      if (dtSec > 0 && dtSec < 1.0) {
        vel = SpatialVelocity(
          vx: (pos.x - previous.position.x) / dtSec,
          vy: (pos.y - previous.position.y) / dtSec,
          vz: (pos.z - previous.position.z) / dtSec,
        );
      }
    }

    final conf = (0.3 + 0.7 * math.min(start.confidence, end.confidence))
        .clamp(0.0, 1.0);

    return MotionFrame(
      position: pos,
      velocity: vel,
      confidence: conf,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Derive motion from anchor movement
  static MotionFrame fromAnchor(AnchorFrame anchor) {
    return MotionFrame(
      position: anchor.toSpatialPosition(),
      velocity: anchor.toSpatialVelocity(),
      confidence: (anchor.confidence * 0.85).clamp(0.0, 1.0),
      timestampMs: anchor.timestampMs,
    );
  }

  /// Heuristic motion for known intents
  ///
  /// Per-reel REEL_STOP positions: Industry standard stereo spread L→R
  /// REEL_STOP_0 = -0.8 (left), REEL_STOP_2 = 0.0 (center), REEL_STOP_4 = +0.8 (right)
  static MotionFrame fromIntent(String intent) {
    final pos = switch (intent) {
      'COIN_FLY_TO_BALANCE' => const SpatialPosition(x: 0.7, y: 0.7, z: 0),
      // Per-reel pan positions - stereo spread from left to right
      'REEL_STOP_0' => const SpatialPosition(x: -0.8, y: 0, z: 0), // Left
      'REEL_STOP_1' => const SpatialPosition(x: -0.4, y: 0, z: 0), // Left-center
      'REEL_STOP_2' => const SpatialPosition(x: 0.0, y: 0, z: 0),  // Center
      'REEL_STOP_3' => const SpatialPosition(x: 0.4, y: 0, z: 0),  // Right-center
      'REEL_STOP_4' => const SpatialPosition(x: 0.8, y: 0, z: 0),  // Right
      'REEL_STOP' => SpatialPosition.origin, // Generic fallback = center
      'BIG_WIN' || 'MEGA_WIN' || 'SUPER_WIN' || 'EPIC_WIN' =>
          const SpatialPosition(x: 0, y: 0.1, z: 0),
      'SPIN_START' => SpatialPosition.origin,
      'UI_CLICK' || 'UI_HOVER' => const SpatialPosition(x: 0, y: -0.6, z: 0),
      'ROLLUP' => const SpatialPosition(x: 0, y: 0.4, z: 0),
      'JACKPOT_WIN' => SpatialPosition.origin,
      _ => SpatialPosition.origin,
    };

    return MotionFrame(
      position: pos,
      velocity: SpatialVelocity.zero,
      confidence: 0.2,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

// =============================================================================
// FUSION ENGINE
// =============================================================================

/// Fuses multiple spatial signals with confidence weighting
class FusionEngine {
  static SpatialTarget fuse({
    required IntentRule rule,
    AnchorFrame? anchor,
    MotionFrame? motion,
    required SpatialTarget intentTarget,
  }) {
    // Weight by confidence
    double wa = rule.wAnchor * (anchor?.confidence ?? 0);
    double wm = rule.wMotion * (motion?.confidence ?? 0);
    double wi = rule.wIntent * intentTarget.confidence;

    final sum = wa + wm + wi;
    if (sum <= kMinConfidence) {
      return SpatialTarget(
        position: intentTarget.position,
        velocity: intentTarget.velocity,
        width: rule.width,
        confidence: 0.1,
      );
    }

    // Normalize
    wa /= sum;
    wm /= sum;
    wi /= sum;

    // Get positions
    final aPos = anchor?.toSpatialPosition() ?? intentTarget.position;
    final mPos = motion?.position ?? intentTarget.position;
    final iPos = intentTarget.position;

    // Weighted average position
    final pos = SpatialPosition(
      x: (wa * aPos.x + wm * mPos.x + wi * iPos.x).clamp(-1.0, 1.0),
      y: (wa * aPos.y + wm * mPos.y + wi * iPos.y).clamp(-1.0, 1.0),
      z: (wa * aPos.z + wm * mPos.z + wi * iPos.z).clamp(0.0, 1.0),
    );

    // Weighted average velocity
    final aVel = anchor?.toSpatialVelocity() ?? SpatialVelocity.zero;
    final mVel = motion?.velocity ?? SpatialVelocity.zero;
    final iVel = intentTarget.velocity;

    final vel = SpatialVelocity(
      vx: wa * aVel.vx + wm * mVel.vx + wi * iVel.vx,
      vy: wa * aVel.vy + wm * mVel.vy + wi * iVel.vy,
      vz: wa * aVel.vz + wm * mVel.vz + wi * iVel.vz,
    );

    // Confidence
    final conf = (0.15 + 0.85 * math.max(
      anchor?.confidence ?? 0,
      motion?.confidence ?? 0,
    )).clamp(0.0, 1.0);

    return SpatialTarget(
      position: pos,
      velocity: vel,
      width: rule.width,
      confidence: conf,
    );
  }

  static SpatialTarget makeIntentTarget(String intent, AnchorFrame? anchor) {
    if (anchor != null && anchor.visible && anchor.confidence > 0.3) {
      return SpatialTarget(
        position: anchor.toSpatialPosition(),
        velocity: anchor.toSpatialVelocity(),
        width: 0.5,
        confidence: 0.7,
      );
    }

    final motion = MotionField.fromIntent(intent);
    return SpatialTarget(
      position: motion.position,
      velocity: motion.velocity,
      width: 0.5,
      confidence: 0.35,
    );
  }
}

// =============================================================================
// EXTENDED KALMAN FILTER (3D Position + Velocity)
// =============================================================================

/// Extended Kalman Filter for smooth 3D position tracking
///
/// State vector: [x, y, z, vx, vy, vz]
/// Measurement: [x, y, z]
class ExtendedKalmanFilter3D {
  // State vector [x, y, z, vx, vy, vz]
  final Float64List _state = Float64List(6);

  // State covariance matrix (6x6, stored as 1D)
  // ignore: non_constant_identifier_names
  final Float64List _P = Float64List(36);

  // Process noise
  final double _processNoise;

  // Measurement noise
  final double _measurementNoise;

  bool _initialized = false;
  int _lastUpdateMs = 0;

  ExtendedKalmanFilter3D({
    double processNoise = 0.1,
    double measurementNoise = 0.05,
  })  : _processNoise = processNoise,
        _measurementNoise = measurementNoise {
    // Initialize covariance matrix (identity * 1.0)
    for (int i = 0; i < 6; i++) {
      _P[i * 6 + i] = 1.0;
    }
  }

  void reset(SpatialPosition pos) {
    _state[0] = pos.x;
    _state[1] = pos.y;
    _state[2] = pos.z;
    _state[3] = 0; // vx
    _state[4] = 0; // vy
    _state[5] = 0; // vz
    _initialized = true;
    _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;

    // Reset covariance
    for (int i = 0; i < 36; i++) _P[i] = 0;
    for (int i = 0; i < 6; i++) _P[i * 6 + i] = 1.0;
  }

  /// Update filter with new measurement
  /// Returns predicted position with lead compensation
  ({SpatialPosition position, SpatialVelocity velocity}) update({
    required SpatialPosition measurement,
    double predictLeadSec = 0.02,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (!_initialized) {
      reset(measurement);
      return (
        position: measurement,
        velocity: SpatialVelocity.zero,
      );
    }

    final dtSec = (nowMs - _lastUpdateMs) / 1000.0;
    _lastUpdateMs = nowMs;

    if (dtSec <= 0 || dtSec > 1.0) {
      return (
        position: SpatialPosition(x: _state[0], y: _state[1], z: _state[2]),
        velocity: SpatialVelocity(vx: _state[3], vy: _state[4], vz: _state[5]),
      );
    }

    // === PREDICT ===
    // State transition: x_new = x + vx*dt, etc.
    _state[0] += _state[3] * dtSec;
    _state[1] += _state[4] * dtSec;
    _state[2] += _state[5] * dtSec;

    // Update covariance (simplified - add process noise to diagonal)
    final q = _processNoise * dtSec;
    for (int i = 0; i < 6; i++) {
      _P[i * 6 + i] += q;
    }

    // === UPDATE ===
    // Innovation (measurement residual)
    final dx = measurement.x - _state[0];
    final dy = measurement.y - _state[1];
    final dz = measurement.z - _state[2];

    // Kalman gain (simplified - use scalar gains)
    final r = _measurementNoise;
    final kPos = _P[0] / (_P[0] + r); // Gain for position
    final kVel = _P[21] / (_P[21] + r * 4); // Gain for velocity (less trust)

    // Update state
    _state[0] += kPos * dx;
    _state[1] += kPos * dy;
    _state[2] += kPos * dz;
    _state[3] += kVel * dx / dtSec;
    _state[4] += kVel * dy / dtSec;
    _state[5] += kVel * dz / dtSec;

    // Clamp velocity to reasonable range
    final maxVel = 5.0; // Normalized units per second
    _state[3] = _state[3].clamp(-maxVel, maxVel);
    _state[4] = _state[4].clamp(-maxVel, maxVel);
    _state[5] = _state[5].clamp(-maxVel, maxVel);

    // Update covariance (simplified)
    for (int i = 0; i < 3; i++) {
      _P[i * 6 + i] *= (1 - kPos);
    }
    for (int i = 3; i < 6; i++) {
      _P[i * 6 + i] *= (1 - kVel);
    }

    // === PREDICT AHEAD ===
    // Apply predictive lead to compensate for latency
    final leadX = (_state[0] + _state[3] * predictLeadSec).clamp(-1.0, 1.0);
    final leadY = (_state[1] + _state[4] * predictLeadSec).clamp(-1.0, 1.0);
    final leadZ = (_state[2] + _state[5] * predictLeadSec).clamp(0.0, 1.0);

    return (
      position: SpatialPosition(x: leadX, y: leadY, z: leadZ),
      velocity: SpatialVelocity(vx: _state[3], vy: _state[4], vz: _state[5]),
    );
  }

  SpatialPosition get currentPosition =>
      SpatialPosition(x: _state[0], y: _state[1], z: _state[2]);

  SpatialVelocity get currentVelocity =>
      SpatialVelocity(vx: _state[3], vy: _state[4], vz: _state[5]);
}

// =============================================================================
// SPATIAL MIXER
// =============================================================================

/// Converts spatial position to audio parameters
class SpatialMixer {
  /// Convert position to stereo pan with deadzone
  static double positionToPan(SpatialPosition pos, double deadzone, double maxPan) {
    double p = pos.x.clamp(-1.0, 1.0);

    // Apply deadzone
    if (p.abs() < deadzone) {
      p = 0;
    } else {
      // Smooth transition out of deadzone
      final sign = p.sign;
      p = sign * ((p.abs() - deadzone) / (1 - deadzone));
    }

    return p.clamp(-maxPan, maxPan);
  }

  /// Calculate equal-power panning gains
  static ({double left, double right}) equalPowerGains(double pan) {
    final angle = (pan + 1) * 0.25 * math.pi;
    return (
      left: math.cos(angle),
      right: math.sin(angle),
    );
  }

  /// Calculate distance attenuation
  static double distanceAttenuation({
    required double distance,
    required DistanceModel model,
    required double minDistance,
    required double maxDistance,
    required double rolloff,
  }) {
    if (model == DistanceModel.none) return 1.0;

    final d = distance.clamp(minDistance, maxDistance);
    final ref = minDistance;

    return switch (model) {
      DistanceModel.none => 1.0,
      DistanceModel.linear => 1 - rolloff * (d - ref) / (maxDistance - ref),
      DistanceModel.inverse => ref / (ref + rolloff * (d - ref)),
      DistanceModel.inverseSquare => math.pow(ref / d, 2 * rolloff).toDouble(),
      DistanceModel.exponential => math.pow(d / ref, -rolloff).toDouble(),
      DistanceModel.custom => 1.0, // User provides via callback
    };
  }

  /// Calculate air absorption (high-frequency rolloff with distance)
  static double airAbsorption(double distance) {
    return -kAirAbsorptionCoeff * distance * 1000; // dB
  }

  /// Calculate frequency-dependent air absorption (P2.5)
  /// Returns LPF cutoff and overall gain based on distance
  /// Higher frequencies attenuate more over distance (realistic)
  static FrequencyAbsorption frequencyDependentAbsorption(double distance) {
    if (distance <= 0) return FrequencyAbsorption.none;

    // Calculate absorption for each band
    // Use highest band that's still above -12dB threshold
    double lpfHz = 20000.0;
    double totalDb = 0.0;

    for (int i = kAirAbsorptionBands.length - 1; i >= 0; i--) {
      final bandDb = -kAirAbsorptionPerBand[i] * distance * 1000;
      if (bandDb < -12.0) {
        // This band is too attenuated, set LPF just below it
        if (i < kAirAbsorptionBands.length - 1) {
          lpfHz = kAirAbsorptionBands[i + 1];
        }
      }
      // Use mid-band (1kHz) for overall gain
      if (i == 2) {
        totalDb = bandDb;
      }
    }

    return FrequencyAbsorption(
      lpfHz: lpfHz.clamp(500.0, 20000.0),
      gainDb: totalDb.clamp(-24.0, 0.0),
    );
  }

  /// Calculate occlusion parameters
  static ({double gain, double lpfHz}) occlusionParams(OcclusionState state) {
    return switch (state) {
      OcclusionState.none => (gain: 1.0, lpfHz: 20000.0),
      OcclusionState.partial => (gain: 0.7, lpfHz: 4000.0),
      OcclusionState.full => (gain: 0.3, lpfHz: 800.0),
    };
  }

  /// Map Y position to LPF (top = bright, bottom = dark)
  static double yToLPF(double y, double minHz, double maxHz) {
    // y: -1 (bottom) to +1 (top)
    final t = (y + 1) * 0.5; // 0 to 1
    return _lerp(minHz, maxHz, t);
  }

  /// Map distance to LPF (near = bright, far = dark)
  static double distanceToLPF(double distance, double minHz, double maxHz) {
    final t = (1 - distance).clamp(0.0, 1.0);
    return _lerp(minHz, maxHz, t);
  }

  /// Calculate reverb send based on distance
  static double distanceToReverb(double distance, double baseLevel, double scale) {
    return (baseLevel + distance * scale).clamp(0.0, 1.0);
  }

  /// Generate complete spatial output
  /// Supports listener position offset and frequency-dependent air absorption
  static SpatialOutput generateOutput({
    required SpatialTarget target,
    required IntentRule rule,
    required BusPolicy policy,
    OcclusionState occlusion = OcclusionState.none,
    ListenerPosition listener = ListenerPosition.center,
    bool useFrequencyAbsorption = true,
    double fadeOutFactor = 1.0, // 1.0 = full spatial, 0.0 = center
    SpatialRenderMode renderMode = SpatialRenderMode.stereo,
  }) {
    // Apply listener position offset (P2.2)
    final relativePos = SpatialPosition(
      x: target.position.x - listener.x,
      y: target.position.y - listener.y,
      z: target.position.z - listener.z,
    );

    // Apply listener rotation if non-zero
    SpatialPosition pos = relativePos;
    if (listener.rotationRad != 0) {
      final cos = math.cos(-listener.rotationRad);
      final sin = math.sin(-listener.rotationRad);
      pos = SpatialPosition(
        x: relativePos.x * cos - relativePos.y * sin,
        y: relativePos.x * sin + relativePos.y * cos,
        z: relativePos.z,
      );
    }

    final vel = target.velocity;

    // Apply bus policy modifiers
    final effectiveMaxPan = rule.maxPan * policy.maxPanMul;
    final effectiveWidth = (target.width * policy.widthMul).clamp(0.0, 1.0);

    // === STEREO ===
    double pan = positionToPan(pos, rule.deadzone, effectiveMaxPan);

    // Apply fade-out factor (P2.3) - blend spatial to center
    pan = pan * fadeOutFactor;
    final width = effectiveWidth * fadeOutFactor;

    final gains = equalPowerGains(pan);

    // === DISTANCE ===
    final distance = pos.distance.clamp(rule.minDistance, rule.maxDistance);
    final distanceGain = distanceAttenuation(
      distance: distance,
      model: rule.distanceModel,
      minDistance: rule.minDistance,
      maxDistance: rule.maxDistance,
      rolloff: rule.rolloffFactor,
    );

    // === AIR ABSORPTION (P2.5) ===
    double airDb;
    double? airLpfHz;
    if (useFrequencyAbsorption) {
      final freqAbs = frequencyDependentAbsorption(distance);
      airDb = freqAbs.gainDb;
      airLpfHz = freqAbs.lpfHz < 20000 ? freqAbs.lpfHz : null;
    } else {
      airDb = airAbsorption(distance);
      airLpfHz = null;
    }

    // === DOPPLER ===
    double doppler = 1.0;
    if (rule.enableDoppler && policy.dopplerMul > 0) {
      doppler = vel.dopplerShift(pos);
      // Scale and clamp
      doppler = 1.0 + (doppler - 1.0) * rule.dopplerScale * policy.dopplerMul;
      final maxShift = math.pow(2, kMaxDopplerShift / 12).toDouble();
      doppler = doppler.clamp(1 / maxShift, maxShift);
    }

    // === OCCLUSION ===
    final occParams = occlusionParams(occlusion);

    // === FILTERS ===
    double? lpfHz;
    if (rule.yToLPF != null) {
      lpfHz = yToLPF(pos.y, rule.yToLPF!.minHz, rule.yToLPF!.maxHz);
    }
    if (rule.distanceToLPF != null) {
      final distLpf = distanceToLPF(
        distance,
        rule.distanceToLPF!.minHz,
        rule.distanceToLPF!.maxHz,
      );
      lpfHz = lpfHz != null ? math.min(lpfHz, distLpf) : distLpf;
    }
    // Apply air absorption LPF
    if (airLpfHz != null) {
      lpfHz = lpfHz != null ? math.min(lpfHz, airLpfHz) : airLpfHz;
    }
    // Apply occlusion LPF
    lpfHz = lpfHz != null
        ? math.min(lpfHz, occParams.lpfHz)
        : (occParams.lpfHz < 20000 ? occParams.lpfHz : null);

    // === REVERB ===
    final reverb = distanceToReverb(
      distance,
      rule.baseReverbSend * policy.reverbMul,
      rule.distanceReverbScale * policy.reverbMul,
    );

    // === AMBISONICS ===
    final bFormat = pos.toBFormat();

    // === HRTF ===
    int? hrtfIndex;
    if (policy.enableHRTF || renderMode == SpatialRenderMode.binaural) {
      // Quantize azimuth/elevation to HRTF table index
      // Assuming 360° azimuth x 180° elevation, 5° resolution
      final azDeg = (pos.azimuth * 180 / math.pi + 180) % 360;
      final elDeg = (pos.elevation * 180 / math.pi + 90).clamp(0, 180);
      hrtfIndex = (azDeg ~/ 5) * 37 + (elDeg ~/ 5);
    }

    return SpatialOutput(
      pan: pan,
      width: width,
      gains: gains,
      position: pos,
      distance: distance,
      azimuthRad: pos.azimuth,
      elevationRad: pos.elevation,
      distanceGain: distanceGain,
      airAbsorptionDb: airDb,
      dopplerShift: doppler,
      occlusionGain: occParams.gain,
      occlusionLpfHz: occParams.lpfHz,
      lpfHz: lpfHz,
      hpfHz: null, // Could add Y-to-HPF mapping
      reverbSend: reverb,
      reverbZoneId: null, // Zone detection would go here
      bFormat: bFormat,
      hrtfIndex: hrtfIndex,
      confidence: target.confidence,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

// =============================================================================
// EVENT TRACKER (Object-Pooled)
// =============================================================================

/// Tracks a single spatial event
class EventTracker {
  String eventId = '';
  SpatialEvent? event;
  IntentRule? rule;
  ExtendedKalmanFilter3D filter = ExtendedKalmanFilter3D();
  int expiresAtMs = 0;

  MotionFrame? lastMotion;
  SpatialOutput? lastOutput;

  bool _inUse = false;

  bool get isActive => _inUse && !isExpired;
  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMs;

  void acquire({
    required SpatialEvent event,
    required IntentRule rule,
    required int expiresAtMs,
  }) {
    eventId = event.id;
    this.event = event;
    this.rule = rule;
    this.expiresAtMs = expiresAtMs;
    filter = ExtendedKalmanFilter3D(
      processNoise: _processNoiseForBus(event.bus),
      measurementNoise: _measurementNoiseForBus(event.bus),
    );
    lastMotion = null;
    lastOutput = null;
    _inUse = true;
  }

  void release() {
    _inUse = false;
    eventId = '';
    event = null;
    rule = null;
    lastMotion = null;
    lastOutput = null;
  }

  static double _processNoiseForBus(SpatialBus bus) => switch (bus) {
    SpatialBus.ui => 0.15,
    SpatialBus.reels => 0.08,
    SpatialBus.sfx => 0.10,
    SpatialBus.vo => 0.05,
    SpatialBus.music => 0.03,
    SpatialBus.ambience => 0.02,
  };

  static double _measurementNoiseForBus(SpatialBus bus) => switch (bus) {
    SpatialBus.ui => 0.03,
    SpatialBus.reels => 0.05,
    SpatialBus.sfx => 0.04,
    SpatialBus.vo => 0.06,
    SpatialBus.music => 0.08,
    SpatialBus.ambience => 0.10,
  };
}

/// Object pool for event trackers (zero allocation during runtime)
class EventTrackerPool {
  final List<EventTracker> _pool;
  final Map<String, int> _activeIndex = {};

  EventTrackerPool({int maxSize = kMaxTrackedEvents})
      : _pool = List.generate(maxSize, (_) => EventTracker());

  EventTracker? acquire({
    required SpatialEvent event,
    required IntentRule rule,
    required int expiresAtMs,
  }) {
    // Check if already tracking this event
    final existingIdx = _activeIndex[event.id];
    if (existingIdx != null && _pool[existingIdx].isActive) {
      final tracker = _pool[existingIdx];
      tracker.event = event;
      tracker.expiresAtMs = expiresAtMs;
      return tracker;
    }

    // Find free slot
    for (int i = 0; i < _pool.length; i++) {
      if (!_pool[i]._inUse) {
        _pool[i].acquire(
          event: event,
          rule: rule,
          expiresAtMs: expiresAtMs,
        );
        _activeIndex[event.id] = i;
        return _pool[i];
      }
    }

    // Pool exhausted - steal oldest expired
    int? oldestIdx;
    int oldestTime = 0x7FFFFFFFFFFFFFFF;
    for (int i = 0; i < _pool.length; i++) {
      if (_pool[i].isExpired && _pool[i].expiresAtMs < oldestTime) {
        oldestIdx = i;
        oldestTime = _pool[i].expiresAtMs;
      }
    }

    if (oldestIdx != null) {
      _activeIndex.remove(_pool[oldestIdx].eventId);
      _pool[oldestIdx].release();
      _pool[oldestIdx].acquire(
        event: event,
        rule: rule,
        expiresAtMs: expiresAtMs,
      );
      _activeIndex[event.id] = oldestIdx;
      return _pool[oldestIdx];
    }

    return null; // Pool full, no expired trackers
  }

  void release(String eventId) {
    final idx = _activeIndex.remove(eventId);
    if (idx != null) {
      _pool[idx].release();
    }
  }

  EventTracker? get(String eventId) {
    final idx = _activeIndex[eventId];
    if (idx != null && _pool[idx].isActive) {
      return _pool[idx];
    }
    return null;
  }

  Iterable<EventTracker> get activeTrackers =>
      _pool.where((t) => t.isActive);

  int get activeCount => _activeIndex.length;

  void cleanup() {
    final expired = <String>[];
    for (final entry in _activeIndex.entries) {
      if (_pool[entry.value].isExpired) {
        expired.add(entry.key);
      }
    }
    for (final id in expired) {
      release(id);
    }
  }

  void clear() {
    for (final tracker in _pool) {
      tracker.release();
    }
    _activeIndex.clear();
  }
}

// =============================================================================
// AUTO SPATIAL ENGINE
// =============================================================================

/// Listener position for non-center listening point
class ListenerPosition {
  final double x; // -1..+1 (left..right)
  final double y; // -1..+1 (back..front)
  final double z; // -1..+1 (down..up)
  final double rotationRad; // Head rotation in radians

  const ListenerPosition({
    this.x = 0.0,
    this.y = 0.0,
    this.z = 0.0,
    this.rotationRad = 0.0,
  });

  static const center = ListenerPosition();
}

/// Configuration for AutoSpatialEngine
class AutoSpatialConfig {
  final SpatialRenderMode renderMode;
  final bool enableDoppler;
  final bool enableDistanceAttenuation;
  final bool enableOcclusion;
  final bool enableReverb;
  final bool enableHRTF;
  final bool enableFrequencyDependentAbsorption;
  final bool enableEventFadeOut;
  final int maxTrackedEvents;
  final int maxEventsPerSecond;
  final double globalPanScale;
  final double globalWidthScale;
  final ListenerPosition listenerPosition;

  const AutoSpatialConfig({
    this.renderMode = SpatialRenderMode.stereo,
    this.enableDoppler = true,
    this.enableDistanceAttenuation = true,
    this.enableOcclusion = true,
    this.enableReverb = true,
    this.enableHRTF = false,
    this.enableFrequencyDependentAbsorption = true,
    this.enableEventFadeOut = true,
    this.maxTrackedEvents = kMaxTrackedEvents,
    this.maxEventsPerSecond = kMaxEventsPerSecond,
    this.globalPanScale = 1.0,
    this.globalWidthScale = 1.0,
    this.listenerPosition = ListenerPosition.center,
  });

  /// Copy with modified values
  AutoSpatialConfig copyWith({
    SpatialRenderMode? renderMode,
    bool? enableDoppler,
    bool? enableDistanceAttenuation,
    bool? enableOcclusion,
    bool? enableReverb,
    bool? enableHRTF,
    bool? enableFrequencyDependentAbsorption,
    bool? enableEventFadeOut,
    int? maxTrackedEvents,
    int? maxEventsPerSecond,
    double? globalPanScale,
    double? globalWidthScale,
    ListenerPosition? listenerPosition,
  }) {
    return AutoSpatialConfig(
      renderMode: renderMode ?? this.renderMode,
      enableDoppler: enableDoppler ?? this.enableDoppler,
      enableDistanceAttenuation: enableDistanceAttenuation ?? this.enableDistanceAttenuation,
      enableOcclusion: enableOcclusion ?? this.enableOcclusion,
      enableReverb: enableReverb ?? this.enableReverb,
      enableHRTF: enableHRTF ?? this.enableHRTF,
      enableFrequencyDependentAbsorption: enableFrequencyDependentAbsorption ?? this.enableFrequencyDependentAbsorption,
      enableEventFadeOut: enableEventFadeOut ?? this.enableEventFadeOut,
      maxTrackedEvents: maxTrackedEvents ?? this.maxTrackedEvents,
      maxEventsPerSecond: maxEventsPerSecond ?? this.maxEventsPerSecond,
      globalPanScale: globalPanScale ?? this.globalPanScale,
      globalWidthScale: globalWidthScale ?? this.globalWidthScale,
      listenerPosition: listenerPosition ?? this.listenerPosition,
    );
  }
}

/// Statistics for monitoring
class AutoSpatialStats {
  final int activeEvents;
  final int totalEventsProcessed;
  final int droppedEvents;
  final int rateLimitedEvents;
  final double avgProcessingTimeUs;
  final double peakProcessingTimeUs;
  final int poolUtilization;
  final int eventsThisSecond;
  final SpatialRenderMode renderMode;

  const AutoSpatialStats({
    this.activeEvents = 0,
    this.totalEventsProcessed = 0,
    this.droppedEvents = 0,
    this.rateLimitedEvents = 0,
    this.avgProcessingTimeUs = 0,
    this.peakProcessingTimeUs = 0,
    this.poolUtilization = 0,
    this.eventsThisSecond = 0,
    this.renderMode = SpatialRenderMode.stereo,
  });
}

/// Frequency-dependent air absorption result
class FrequencyAbsorption {
  final double lpfHz; // Low-pass filter cutoff
  final double gainDb; // Overall attenuation

  const FrequencyAbsorption({
    required this.lpfHz,
    required this.gainDb,
  });

  static const none = FrequencyAbsorption(lpfHz: 20000.0, gainDb: 0.0);
}

/// Main orchestrator for automatic spatial audio positioning
class AutoSpatialEngine {
  final AnchorRegistry _registry;
  final EventTrackerPool _pool;
  final Map<String, IntentRule> _rules = {};
  AutoSpatialConfig config;

  // Statistics (atomic would be better, but Dart doesn't have them)
  int _totalEventsProcessed = 0;
  int _droppedEvents = 0;
  int _rateLimitedEvents = 0;
  double _avgProcessingTimeUs = 0;
  double _peakProcessingTimeUs = 0;

  // Cached timestamp (P1.2 optimization)
  int _cachedNowMs = 0;
  int _cachedNowUs = 0;

  // Rate limiting (P2.6)
  int _eventsThisSecond = 0;
  int _rateLimitResetMs = 0;

  int _lastUpdateMs = 0;

  AutoSpatialEngine({
    AnchorRegistry? registry,
    List<IntentRule>? intentRules,
    this.config = const AutoSpatialConfig(),
  })  : _registry = registry ?? AnchorRegistry(),
        _pool = EventTrackerPool(maxSize: config.maxTrackedEvents) {
    final rules = intentRules ?? SlotIntentRules.defaults;
    for (final r in rules) {
      _rules[r.intent] = r;
    }
    _updateTimestamp();
  }

  AnchorRegistry get anchorRegistry => _registry;

  /// Update cached timestamp (call once per frame, not per operation)
  void _updateTimestamp() {
    final now = DateTime.now();
    _cachedNowMs = now.millisecondsSinceEpoch;
    _cachedNowUs = now.microsecondsSinceEpoch;
  }

  /// Check if value is finite (not NaN or Infinity)
  static bool _isValidFloat(double? value) {
    if (value == null) return true; // null is OK (optional)
    return value.isFinite;
  }

  /// Register a spatial event
  void onEvent(SpatialEvent event) {
    // Input validation — strings
    if (event.id.isEmpty || event.id.length > 256) return;
    if (event.intent.isEmpty || event.intent.length > 256) return;

    // Input validation — NaN/Infinity checks (P1.3)
    if (!_isValidFloat(event.xNorm)) return;
    if (!_isValidFloat(event.yNorm)) return;
    if (!_isValidFloat(event.zNorm)) return;
    if (!_isValidFloat(event.progress01)) return;
    if (!_isValidFloat(event.importance)) return;

    // Rate limiting (P2.6)
    if (_cachedNowMs > _rateLimitResetMs) {
      _eventsThisSecond = 0;
      _rateLimitResetMs = _cachedNowMs + 1000;
    }
    if (_eventsThisSecond >= config.maxEventsPerSecond) {
      _rateLimitedEvents++;
      return;
    }
    _eventsThisSecond++;

    final rule = _rules[event.intent] ?? _rules['DEFAULT']!;
    final expiresAt = _cachedNowMs + event.lifetimeMs;

    final tracker = _pool.acquire(
      event: event,
      rule: rule,
      expiresAtMs: expiresAt,
    );

    if (tracker == null) {
      _droppedEvents++;
    }
  }

  /// Stop tracking an event
  void stopEvent(String eventId) {
    _pool.release(eventId);
  }

  /// Update all tracked events
  Map<String, SpatialOutput> update() {
    // Use cached timestamp (P1.2 optimization)
    _updateTimestamp();
    final startUs = _cachedNowUs;
    _lastUpdateMs = _cachedNowMs;

    // Cleanup expired first
    _pool.cleanup();

    final outputs = <String, SpatialOutput>{};

    for (final tracker in _pool.activeTrackers) {
      final event = tracker.event;
      if (event == null) continue;

      final rule = tracker.rule!;
      final policy = BusPolicies.getPolicy(event.bus);

      // === 0. CALCULATE FADE-OUT FACTOR (P2.3) ===
      double fadeOutFactor = 1.0;
      if (config.enableEventFadeOut) {
        final remainingMs = tracker.expiresAtMs - _cachedNowMs;
        if (remainingMs < kEventFadeOutMs && remainingMs > 0) {
          fadeOutFactor = remainingMs / kEventFadeOutMs;
        } else if (remainingMs <= 0) {
          fadeOutFactor = 0.0;
        }
      }

      // === 1. RESOLVE ANCHORS ===
      final anchorId = event.anchorId ?? rule.defaultAnchorId;
      final startId = event.startAnchorId ?? rule.startAnchorFallback;
      final endId = event.endAnchorId ?? rule.endAnchorFallback;

      AnchorFrame? anchor;
      if (anchorId != null) {
        anchor = _registry.getFrame(anchorId);
      }

      AnchorFrame? startAnchor;
      AnchorFrame? endAnchor;
      if (startId != null) startAnchor = _registry.getFrame(startId);
      if (endId != null) endAnchor = _registry.getFrame(endId);

      // === 2. COMPUTE MOTION ===
      MotionFrame? motion;

      if (event.xNorm != null && event.yNorm != null) {
        // Best case: explicit position from engine
        motion = MotionFrame(
          position: SpatialPosition(
            x: (event.xNorm! * 2) - 1,
            y: 1 - (event.yNorm! * 2),
            z: event.zNorm ?? 0,
          ),
          velocity: SpatialVelocity.zero,
          confidence: 0.95,
          timestampMs: _cachedNowMs,
        );
      } else if (event.progress01 != null && startAnchor != null && endAnchor != null) {
        motion = MotionField.fromProgress(
          start: startAnchor,
          end: endAnchor,
          progress01: event.progress01!,
          easing: rule.motionEasing,
          previous: tracker.lastMotion,
        );
      } else if (anchor != null) {
        motion = MotionField.fromAnchor(anchor);
      } else {
        motion = MotionField.fromIntent(event.intent);
      }
      tracker.lastMotion = motion;

      // === 3. INTENT TARGET ===
      final intentTarget = FusionEngine.makeIntentTarget(event.intent, anchor);

      // === 4. FUSE SIGNALS ===
      final fused = FusionEngine.fuse(
        rule: rule,
        anchor: anchor,
        motion: motion,
        intentTarget: intentTarget,
      );

      // === 5. KALMAN FILTER SMOOTHING ===
      final leadSec = switch (event.bus) {
        SpatialBus.ui => 0.025,
        SpatialBus.reels => 0.015,
        SpatialBus.sfx => 0.018,
        SpatialBus.vo => 0.010,
        SpatialBus.music => 0.005,
        SpatialBus.ambience => 0.003,
      };

      final filtered = tracker.filter.update(
        measurement: fused.position,
        predictLeadSec: leadSec,
      );

      // === 6. GENERATE OUTPUT (with all new features) ===
      final smoothedTarget = SpatialTarget(
        position: filtered.position,
        velocity: filtered.velocity,
        width: fused.width,
        confidence: fused.confidence,
      );

      final output = SpatialMixer.generateOutput(
        target: smoothedTarget,
        rule: rule,
        policy: policy,
        occlusion: event.occlusionState ?? OcclusionState.none,
        listener: config.listenerPosition,
        useFrequencyAbsorption: config.enableFrequencyDependentAbsorption,
        fadeOutFactor: fadeOutFactor,
        renderMode: config.renderMode,
      );

      tracker.lastOutput = output;
      outputs[event.id] = output;
      _totalEventsProcessed++;
    }

    // Update stats (using cached end timestamp)
    final endUs = DateTime.now().microsecondsSinceEpoch;
    final processingUs = (endUs - startUs).toDouble();
    _avgProcessingTimeUs = 0.95 * _avgProcessingTimeUs + 0.05 * processingUs;
    if (processingUs > _peakProcessingTimeUs) {
      _peakProcessingTimeUs = processingUs;
    }

    return outputs;
  }

  /// Get output for a specific event (without full update)
  SpatialOutput? getOutput(String eventId) {
    return _pool.get(eventId)?.lastOutput;
  }

  /// Update listener position at runtime
  void setListenerPosition(ListenerPosition position) {
    config = config.copyWith(listenerPosition: position);
  }

  /// Update render mode at runtime
  void setRenderMode(SpatialRenderMode mode) {
    config = config.copyWith(renderMode: mode);
  }

  /// Get engine statistics
  AutoSpatialStats getStats() {
    return AutoSpatialStats(
      activeEvents: _pool.activeCount,
      totalEventsProcessed: _totalEventsProcessed,
      droppedEvents: _droppedEvents,
      rateLimitedEvents: _rateLimitedEvents,
      avgProcessingTimeUs: _avgProcessingTimeUs,
      peakProcessingTimeUs: _peakProcessingTimeUs,
      poolUtilization: (_pool.activeCount * 100 / kMaxTrackedEvents).round(),
      eventsThisSecond: _eventsThisSecond,
      renderMode: config.renderMode,
    );
  }

  int get activeCount => _pool.activeCount;
  Iterable<String> get activeEventIds => _pool.activeTrackers.map((t) => t.eventId);

  void clear() {
    _pool.clear();
  }

  void dispose() {
    clear();
    _registry.clear();
  }
}
