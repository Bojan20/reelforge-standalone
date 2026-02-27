# AUREXIS™ — FluxForge Studio Integration Architecture

## Absolute Ultimate Technical Specification

**Version:** 1.0 | **Date:** 2026-02-24 | **Status:** Architecture Spec — Ready for Implementation

---

## 0. EXECUTIVE SUMMARY

AUREXIS™ je **deterministički, matematički-svestan, psihoakustički slot-audio intelligence engine**. Nije DSP efekat, nije mikser, nije spatijalizator — to je **inteligencija** koja prevodi slot matematiku u audio ponašanje.

**Ključna razlika od svega što FluxForge već ima:**

| Sistem | Šta radi | Tip |
|--------|----------|-----|
| **ALE** | Menja layer (L1-L5) na osnovu signala | Execution |
| **RTPC** | Mapira jedan parametar na drugi | Routing |
| **AutoSpatial** | Pozicionira zvuk u stereo polju | Positioning |
| **DSP Chain** | Procesira audio (EQ, kompresija, reverb) | Processing |
| **AUREXIS** | **Orkestrira SVE parametre na osnovu slot matematike** | **Intelligence** |

AUREXIS ne procesira audio — on **govori** ostalim sistemima **šta da rade**.

---

## 1. ARHITEKTURNA POZICIJA

```
┌──────────────────────────────────────────────────────────────────────┐
│                       GAME LOGIC LAYER                               │
│   RTP · Volatility · Feature State · Win Magnitude · Session Time    │
└────────────────────────────────┬─────────────────────────────────────┘
                                 ↓
┌──────────────────────────────────────────────────────────────────────┐
│                    rf-slot-lab (Simulation)                           │
│   SpinResult · WinTier · FeatureProximity · GridState                │
└────────────────────────────────┬─────────────────────────────────────┘
                                 ↓
┌══════════════════════════════════════════════════════════════════════┐
║                                                                      ║
║              ★★★ rf-aurexis — INTELLIGENCE LAYER ★★★                ║
║                                                                      ║
║   Volatility    RTP Pacing    Psycho      Collision    Platform      ║
║   Translator    Model         Regulator   Intelligence Adapter       ║
║       ↓            ↓             ↓            ↓           ↓          ║
║                  DETERMINISTIC PARAMETER MAP                         ║
║                                                                      ║
╚══════════════════════════════════╤═══════════════════════════════════╝
                                   ↓
               ┌───────────────────┼───────────────────┐
               ↓                   ↓                   ↓
        ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
        │   rf-ale    │    │  rf-spatial  │    │  rf-engine  │
        │  (layers)   │    │  (panning)   │    │ (voices)    │
        └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
               ↓                  ↓                  ↓
        ┌─────────────┐                       ┌─────────────┐
        │   rf-dsp    │                       │  rf-bridge  │
        │ (processing)│                       │   (FFI)     │
        └──────┬──────┘                       └──────┬──────┘
               └──────────────────┬──────────────────┘
                                  ↓
                           AUDIO OUTPUT
```

**Kritično:** AUREXIS Advanced Panel modifikuje SAMO koeficijente. DSP nikada ne računa inteligenciju.

---

## 2. OVERLAP ANALIZA SA POSTOJEĆIM SISTEMIMA

### 2.1 Šta FluxForge VEĆ IMA (i AUREXIS koristi kao infrastructure)

| Komponenta | Lokacija | LOC | AUREXIS Koristi Kao |
|------------|----------|-----|---------------------|
| **18+ signala** | `rf-ale/signals.rs` | ~14KB | Input signali za intelligence |
| **Signal normalizacija** | `rf-ale/signals.rs` | — | Sigmoid/linear/asymptotic curves |
| **Context switching** | `rf-ale/context.rs` | ~19KB | Psycho-profile trigger |
| **Layer tranzicije** | `rf-ale/transitions.rs` | ~21KB | Execution target |
| **Stability mehanizmi** | `rf-ale/stability.rs` | ~21KB | Anti-flutter protection |
| **RTPC mapiranje** | `rtpc_modulation_service.dart` | ~350 | Parameter routing |
| **6 RTPC target params** | `rtpc_modulation_service.dart` | — | Modulation targets |
| **Volatility calculator** | `volatility_calculator.dart` | — | Input signal |
| **Win tier system** | `win_tier_config.dart` | ~1,350 | Escalation trigger |
| **Stage config** | `stage_configuration_service.dart` | ~650 | Priority/bus data |
| **Audio context** | `audio_context_service.dart` | ~310 | Context classification |
| **GDD import** | `gdd_import_service.dart` | ~1,500 | RTP/volatility extraction |
| **30+ intent rules** | `auto_spatial.dart` | ~2,296 | Pan base values |
| **Kalman filter** | `auto_spatial.dart` | — | Smoothing engine |
| **Voice pooling** | `rf-engine/playback.rs` | — | Voice tracking |
| **Deterministic seeds** | `event_profiler_provider.dart` | ~540 | Seed infrastructure |
| **Bus routing (6)** | `playback.rs` | — | Routing targets |
| **Platform profiles** | `timing.rs` | — | Profile framework |

### 2.2 Šta FluxForge NEMA (AUREXIS dodaje)

| Komponenta | AUREXIS Sekcija | Opis | Prioritet |
|------------|-----------------|------|-----------|
| **Volatility → Audio Translation** | §4.1 | Mapira volatility index na stereo elasticity, energy density, escalation rate | P0 |
| **RTP Emotional Distribution** | §4.2 | RTP → pacing structure, build speed, peak stability | P1 |
| **Feature Probability Anticipation** | §4.3 | Prediktivno pre-widening/harmonic lift pre vizuelnog klimaksa | P1 |
| **Attention Vector Engine** | §5.2 | `attention = Σ(eventWeight × screenPosition × priority)` | P1 |
| **Voice Collision Intelligence** | §6 | Pan redistribution, Z-displacement, width compression, center limits | P0 |
| **Session Psycho Regulation** | §7 | RMS/HF/transient fatigue monitoring, HF attenuation, transient smoothing | P0 |
| **Micro-Variation Engine** | §8 | Deterministic `hash(spriteId + eventTime + gameState + sessionIndex)` | P1 |
| **Win Escalation Intelligence** | §9 | Single asset → infinite scaling (width, harmonics, reverb, sub, transients) | P0 |
| **Platform Adaptation System** | §10 | Desktop/Mobile/Headphones/Cabinet profile modifikacije | P2 |
| **QA Framework** | §12 | Deterministic replay, volatility simulation, fatigue stress test | P2 |
| **Advanced Panel** | §13 | 6 sekcija + 5 live visualizers | P1 |

### 2.3 Precizna Razlika: AUREXIS vs Postojeći Sistemi

```
ALE kaže:        "Player je na winning streak → prebaci na L4 layer"
AUREXIS kaže:    "Volatility=0.8 + WinXbet=15 + Session=45min →
                  WIDTH +0.15, HF_ATTEN -2.3dB, REVERB_SEND +0.12,
                  PAN_DRIFT ±0.03, TRANSIENT_SHARP +0.08"

ALE bira KOJI layer. AUREXIS bira KAKO taj layer zvuči.
```

```
AutoSpatial kaže:  "Reel 3 stop → pan at 0.0 (center)"
AUREXIS kaže:      "Reel 3 stop, ali 2 voicea su već u centru →
                    redistribute to -0.1, collision Z-depth +0.3,
                    duck center by -2dB for 50ms"
```

```
RTPC mapira:       "winTier=5 → volume=0.9"
AUREXIS mapira:    "winTier=5 + volatility=high + session=80min →
                    volume=0.85, width=1.4, harmonicExcite=1.3,
                    reverbTail=+800ms, subReinforce=+3dB,
                    transientSharp=1.2, hfAtten=-1.5dB(fatigue)"
```

---

## 3. RUST CRATE STRUKTURA

### 3.1 Novi Crate: `rf-aurexis`

```
crates/rf-aurexis/
├── Cargo.toml
├── src/
│   ├── lib.rs                          # Public API, AurexisEngine
│   │
│   ├── core/
│   │   ├── mod.rs
│   │   ├── engine.rs                   # AurexisEngine struct — main orchestrator
│   │   ├── state.rs                    # AurexisState — complete runtime state
│   │   ├── config.rs                   # AurexisConfig — all tunable coefficients
│   │   └── parameter_map.rs            # DeterministicParameterMap — output
│   │
│   ├── volatility/
│   │   ├── mod.rs
│   │   ├── translator.rs              # VolatilityTranslator
│   │   │   ├── stereo_elasticity()    # volatility → stereo field behavior
│   │   │   ├── energy_density()       # volatility → energy envelope
│   │   │   ├── escalation_rate()      # volatility → ramp speed
│   │   │   └── micro_dynamics()       # volatility → micro movement intensity
│   │   └── profiles.rs               # VolatilityProfile (low/med/high/extreme)
│   │
│   ├── rtp/
│   │   ├── mod.rs
│   │   ├── mapper.rs                  # RtpEmotionalMapper
│   │   │   ├── pacing_curve()         # RTP → build/peak/release timing
│   │   │   ├── spike_frequency()      # RTP → micro-spike density
│   │   │   └── peak_elasticity()      # RTP → peak magnitude flexibility
│   │   └── models.rs                  # RtpProfile, PacingCurve
│   │
│   ├── psycho/
│   │   ├── mod.rs
│   │   ├── fatigue.rs                 # SessionFatigueTracker
│   │   │   ├── tick()                 # Per-block update
│   │   │   ├── rms_exposure()         # Running RMS average
│   │   │   ├── hf_exposure()          # Cumulative HF energy
│   │   │   ├── transient_density()    # Transients per minute
│   │   │   └── stereo_fatigue()       # Stereo width time-on
│   │   ├── regulation.rs             # PsychoRegulator
│   │   │   ├── hf_attenuation()      # Fatigue → HF shelf dB
│   │   │   ├── transient_smoothing()  # Fatigue → transient ratio
│   │   │   ├── width_narrowing()      # Fatigue → stereo width
│   │   │   └── micro_variation()      # Fatigue → subtle changes
│   │   └── thresholds.rs             # FatigueThresholds (configurable)
│   │
│   ├── collision/
│   │   ├── mod.rs
│   │   ├── priority.rs               # VoiceCollisionResolver
│   │   │   ├── register_voice()       # Add voice to scene
│   │   │   ├── unregister_voice()     # Remove voice
│   │   │   └── resolve()              # Compute redistribution
│   │   ├── redistribution.rs         # PanRedistributor
│   │   │   ├── pan_spread()           # Spread overlapping voices
│   │   │   ├── z_displacement()       # Push to different depths
│   │   │   ├── width_compression()    # Narrow width for space
│   │   │   └── ducking_bias()         # Automatic ducking
│   │   └── clustering.rs             # VoiceDensityAnalyzer
│   │       ├── center_occupancy()     # Max 2 voices in front
│   │       └── density_map()          # Spatial density heatmap
│   │
│   ├── escalation/
│   │   ├── mod.rs
│   │   ├── win.rs                     # WinEscalationEngine
│   │   │   ├── compute()              # (winAmount, betMultiplier, jackpotProximity) → params
│   │   │   ├── width_growth()         # Exponential stereo growth
│   │   │   ├── harmonic_excite()      # Harmonic density scaling
│   │   │   ├── reverb_extension()     # Reverb tail growth
│   │   │   ├── sub_reinforce()        # Sub frequency boost
│   │   │   └── transient_sharp()      # Transient emphasis curve
│   │   └── curves.rs                 # EscalationCurve (linear, exp, log, custom)
│   │
│   ├── geometry/
│   │   ├── mod.rs
│   │   └── attention.rs              # AttentionVectorEngine
│   │       ├── register_event()       # Add event with screen position
│   │       ├── compute_vector()       # attention = Σ(weight × pos × priority)
│   │       └── get_audio_center()     # Current audio gravity center
│   │
│   ├── variation/
│   │   ├── mod.rs
│   │   ├── deterministic.rs          # DeterministicVariationEngine
│   │   │   ├── seed()                 # hash(spriteId + eventTime + gameState + sessionIndex)
│   │   │   ├── pan_drift()            # ± pan micro offset
│   │   │   ├── width_variance()       # ± width micro shift
│   │   │   ├── harmonic_shift()       # ± harmonic micro change
│   │   │   └── reflection_weight()    # ± early reflection bias
│   │   └── hash.rs                   # xxhash-based deterministic seed
│   │
│   ├── platform/
│   │   ├── mod.rs
│   │   ├── profiles.rs               # PlatformProfile
│   │   │   ├── desktop()              # Full range, extended depth
│   │   │   ├── mobile()               # Stereo compression, mono safety
│   │   │   ├── headphones()           # Width enhancement, M/S boost
│   │   │   └── cabinet()              # Bass management, phase-safe center
│   │   └── adaptation.rs             # PlatformAdapter — applies profile
│   │
│   └── qa/
│       ├── mod.rs
│       ├── determinism.rs            # ReplayVerifier — exact reproducibility
│       ├── simulation.rs             # VolatilitySimulator — stress test
│       └── profiling.rs              # PerformanceProfiler — CPU tracking
│
└── tests/
    ├── determinism_tests.rs          # Identical output across runs
    ├── volatility_tests.rs           # Correct parameter mapping
    ├── fatigue_tests.rs              # Session regulation accuracy
    ├── collision_tests.rs            # Voice redistribution correctness
    └── escalation_tests.rs           # Win scaling verification
```

### 3.2 Cargo.toml

```toml
[package]
name = "rf-aurexis"
version = "0.1.0"
edition = "2021"
description = "AUREXIS™ — Deterministic Slot Audio Intelligence Engine"

[dependencies]
rf-core = { path = "../rf-core" }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
parking_lot = { workspace = true }
log = { workspace = true }
thiserror = { workspace = true }

# Deterministic hashing (no random)
xxhash-rust = { version = "0.8", features = ["xxh3"] }

# Lock-free RT communication
rtrb = { workspace = true }

[dev-dependencies]
approx = "0.5"
```

**Nema** zavisnosti na rf-ale, rf-engine, rf-dsp, rf-spatial — AUREXIS je **čist intelligence layer** koji šalje parametre, ne poziva tuđe API-je.

### 3.3 FFI Bridge — `crates/rf-bridge/src/aurexis_ffi.rs`

```rust
// ═══════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════
aurexis_init() -> i32
aurexis_shutdown()
aurexis_is_initialized() -> i32

// ═══════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════
aurexis_load_config_json(json: *const c_char) -> i32
aurexis_export_config_json() -> *mut c_char
aurexis_set_coefficient(section: *const c_char, key: *const c_char, value: f64) -> i32

// ═══════════════════════════════════════════════
// VOLATILITY
// ═══════════════════════════════════════════════
aurexis_set_volatility_index(index: f64) -> i32              // 0.0=low, 1.0=extreme
aurexis_get_volatility_map_json() -> *mut c_char             // Current parameter map

// ═══════════════════════════════════════════════
// RTP
// ═══════════════════════════════════════════════
aurexis_set_rtp(rtp_percent: f64) -> i32                     // 88.0-99.0
aurexis_get_pacing_profile_json() -> *mut c_char             // Current pacing

// ═══════════════════════════════════════════════
// WIN ESCALATION
// ═══════════════════════════════════════════════
aurexis_update_win(amount: f64, bet: f64, jackpot_proximity: f64) -> i32
aurexis_get_escalation_params_json() -> *mut c_char          // Width, harmonics, reverb, sub

// ═══════════════════════════════════════════════
// SESSION PSYCHO REGULATION
// ═══════════════════════════════════════════════
aurexis_tick_session(elapsed_ms: u64) -> i32                 // Call every audio block
aurexis_update_rms_level(rms_db: f64) -> i32                 // Current RMS
aurexis_update_hf_energy(hf_db: f64) -> i32                  // Current HF band energy
aurexis_get_fatigue_index() -> f64                           // 0.0=fresh, 1.0=fatigued
aurexis_get_psycho_state_json() -> *mut c_char               // Full fatigue state
aurexis_reset_fatigue() -> i32                                // Reset on feature enter

// ═══════════════════════════════════════════════
// COLLISION INTELLIGENCE
// ═══════════════════════════════════════════════
aurexis_register_voice(voice_id: u32, pan: f32, z_depth: f32, priority: i32) -> i32
aurexis_unregister_voice(voice_id: u32) -> i32
aurexis_resolve_collisions_json() -> *mut c_char             // Redistribution map
aurexis_get_center_occupancy() -> i32                         // Voices in center zone

// ═══════════════════════════════════════════════
// MICRO-VARIATION
// ═══════════════════════════════════════════════
aurexis_set_variation_seed(sprite_id: u64, event_time: u64, game_state: u64, session_idx: u64) -> i32
aurexis_get_variation_json() -> *mut c_char                  // Pan drift, width variance, etc.

// ═══════════════════════════════════════════════
// PLATFORM
// ═══════════════════════════════════════════════
aurexis_set_platform(platform: *const c_char) -> i32         // "desktop"/"mobile"/"headphones"/"cabinet"
aurexis_get_platform_modifiers_json() -> *mut c_char         // Current platform coefficients

// ═══════════════════════════════════════════════
// GEOMETRY & ATTENTION
// ═══════════════════════════════════════════════
aurexis_register_screen_event(event_id: u32, x: f32, y: f32, weight: f32, priority: i32) -> i32
aurexis_clear_screen_events() -> i32
aurexis_get_attention_vector_json() -> *mut c_char           // Audio gravity center

// ═══════════════════════════════════════════════
// MASTER OUTPUT
// ═══════════════════════════════════════════════
aurexis_compute_parameter_map() -> i32                        // Recompute all
aurexis_get_parameter_map_json() -> *mut c_char              // COMPLETE output
aurexis_get_parameter(target: *const c_char) -> f64          // Single parameter

// ═══════════════════════════════════════════════
// QA
// ═══════════════════════════════════════════════
aurexis_start_recording() -> i32                             // Start determinism log
aurexis_stop_recording_json() -> *mut c_char                 // Export session log
aurexis_replay_verify(recording_json: *const c_char) -> i32  // Verify determinism
aurexis_simulate_volatility(volatility: f64, spins: u32, seed: u64) -> *mut c_char

// MEMORY
aurexis_free_string(ptr: *mut c_char)
```

**Total: ~40 FFI funkcija** (prati ale_ffi.rs pattern, ~780 LOC)

---

## 4. DART INTEGRATION

### 4.1 AurexisProvider (`flutter_ui/lib/providers/aurexis_provider.dart`)

```dart
class AurexisProvider extends ChangeNotifier {
  final NativeFFI _ffi;
  Timer? _tickTimer;

  // ═══ STATE ═══
  double _volatilityIndex = 0.5;
  double _rtpPercent = 96.0;
  double _fatigueIndex = 0.0;
  int _centerOccupancy = 0;
  String _platform = 'desktop';

  // ═══ OUTPUT (DeterministicParameterMap) ═══
  double stereoWidth = 1.0;           // 0.0-2.0
  double hfAttenuation = 0.0;         // 0 to -12 dB
  double transientSmoothing = 0.0;    // 0.0-1.0
  double panDrift = 0.0;              // ± offset
  double widthVariance = 0.0;         // ± offset
  double harmonicExcitation = 1.0;    // 1.0-2.0
  double reverbSendBias = 0.0;        // -1.0 to +1.0
  double subReinforcement = 0.0;      // 0 to +12 dB
  double transientSharpness = 1.0;    // 0.5-2.0
  double escalationMultiplier = 1.0;  // 1.0-∞

  // ═══ TICK LOOP ═══
  void startTicking() {
    _tickTimer = Timer.periodic(Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    _ffi.aurexisTickSession(50);  // 50ms per tick
    _refreshState();
    notifyListeners();
  }

  // ═══ INPUTS ═══
  void setVolatility(double index);
  void setRtp(double percent);
  void updateWin(double amount, double bet, {double jackpotProximity = 0.0});
  void updateRmsLevel(double rmsDb);
  void updateHfEnergy(double hfDb);
  void registerVoice(int voiceId, double pan, double zDepth, int priority);
  void unregisterVoice(int voiceId);
  void setPlatform(String platform);
  void registerScreenEvent(int eventId, double x, double y, double weight, int priority);

  // ═══ OUTPUTS ═══
  Map<String, double> get parameterMap;     // Complete output
  double getParameter(String target);        // Single parameter

  // ═══ QA ═══
  void startRecording();
  String stopRecording();
  bool verifyReplay(String recordingJson);
}
```

### 4.2 GetIt Registration (Layer 6)

```dart
// service_locator.dart — Layer 6 (between subsystem providers and bus routing)
sl.registerLazySingleton<AurexisProvider>(() => AurexisProvider(sl<NativeFFI>()));
```

### 4.3 Integration sa Postojećim Providerima

```dart
// ═══ SlotLabProvider → AUREXIS ═══
// U slot_lab_provider.dart, posle svakog spina:
void _onSpinComplete(SpinResult result) {
  final aurexis = sl<AurexisProvider>();

  // Feed win data
  if (result.isWin) {
    aurexis.updateWin(result.totalWin, _betAmount,
        jackpotProximity: _jackpotProgress);
  }

  // Feed volatility (from GDD or calculated)
  aurexis.setVolatility(_currentVolatilityIndex);
}

// ═══ EventRegistry → AUREXIS ═══
// U event_registry.dart, pri svakom triggerStage:
void triggerStage(String stage) {
  final aurexis = sl<AurexisProvider>();

  // Register voice for collision tracking
  final voiceId = _playEvent(event);
  if (voiceId != null) {
    final pan = _calculatePan(stage);
    final priority = _stageToPriority(stage);
    aurexis.registerVoice(voiceId, pan, 0.0, priority);
  }
}

// ═══ AUREXIS → RTPC Modulation ═══
// U rtpc_modulation_service.dart, dodati:
double getAurexisModulatedVolume(String eventId, double baseVolume) {
  final aurexis = sl<AurexisProvider>();

  // Apply psycho-regulation
  double volume = baseVolume;
  volume *= (1.0 + aurexis.subReinforcement / 12.0);  // Sub boost
  volume *= aurexis.escalationMultiplier;                // Win escalation

  return volume.clamp(0.0, 2.0);
}

// ═══ AUREXIS → AutoSpatial ═══
// U auto_spatial.dart, dodati collision awareness:
SpatialOutput computeWithAurexis(String intent, SpatialOutput baseSpatial) {
  final aurexis = sl<AurexisProvider>();

  return SpatialOutput(
    pan: baseSpatial.pan + aurexis.panDrift,
    width: baseSpatial.width * aurexis.stereoWidth,
    // ... ostali parametri
  );
}

// ═══ AUREXIS → DSP Chain ═══
// U fabfilter_eq_panel.dart ili insert chain:
// HF attenuation from fatigue → automatic shelf filter adjustment
void applyAurexisHfAttenuation(int trackId) {
  final aurexis = sl<AurexisProvider>();
  if (aurexis.hfAttenuation < -0.5) {
    // Apply HF shelf: aurexis.hfAttenuation dB at 8kHz
    _ffi.insertSetParam(trackId, eqSlot, hfShelfGainParam, aurexis.hfAttenuation);
  }
}
```

---

## 5. DETERMINISTIČKI PARAMETER MAP — OUTPUT FORMAT

AUREXIS-ov jedini output je `DeterministicParameterMap`:

```rust
pub struct DeterministicParameterMap {
    // ═══ STEREO FIELD ═══
    pub stereo_width: f64,              // 0.0 (mono) — 2.0 (super wide)
    pub stereo_elasticity: f64,         // How much width responds to events
    pub pan_drift: f64,                 // ± micro pan offset
    pub width_variance: f64,            // ± micro width offset

    // ═══ FREQUENCY ═══
    pub hf_attenuation_db: f64,         // 0 to -12 dB (fatigue shelf)
    pub harmonic_excitation: f64,       // 1.0 (neutral) — 2.0 (saturated)
    pub sub_reinforcement_db: f64,      // 0 to +12 dB (win emphasis)

    // ═══ DYNAMICS ═══
    pub transient_smoothing: f64,       // 0.0 (sharp) — 1.0 (smoothed)
    pub transient_sharpness: f64,       // 0.5 (soft) — 2.0 (aggressive)
    pub energy_density: f64,            // 0.0 (sparse) — 1.0 (dense)

    // ═══ SPACE ═══
    pub reverb_send_bias: f64,          // -1.0 (dry) — +1.0 (wet)
    pub reverb_tail_extension_ms: f64,  // Additional tail length
    pub z_depth_offset: f64,            // Front/back positioning
    pub early_reflection_weight: f64,   // ± early reflection bias

    // ═══ ESCALATION ═══
    pub escalation_multiplier: f64,     // 1.0 (neutral) — ∞ (extreme)
    pub escalation_curve: EscalationCurve, // linear/exp/log

    // ═══ ATTENTION ═══
    pub attention_x: f64,               // -1.0 (left) — +1.0 (right)
    pub attention_y: f64,               // -1.0 (bottom) — +1.0 (top)
    pub attention_weight: f64,          // 0.0 (dispersed) — 1.0 (focused)

    // ═══ COLLISION ═══
    pub center_occupancy: u32,          // Voices in front depth
    pub voices_redistributed: u32,      // Voices that got moved
    pub ducking_bias_db: f64,           // Auto-duck amount

    // ═══ PLATFORM ═══
    pub platform_stereo_range: f64,     // 0.0-1.0 (mobile compressed)
    pub platform_mono_safety: f64,      // 0.0-1.0 (mono compatibility)
    pub platform_depth_range: f64,      // 0.0-1.0 (depth compression)

    // ═══ FATIGUE ═══
    pub fatigue_index: f64,             // 0.0 (fresh) — 1.0 (fatigued)
    pub session_duration_s: f64,        // Total seconds
    pub rms_exposure_avg_db: f64,       // Running average
    pub hf_exposure_cumulative: f64,    // Accumulated HF energy
    pub transient_density_per_min: f64, // Transients per minute

    // ═══ SEED ═══
    pub variation_seed: u64,            // Current deterministic seed
    pub is_deterministic: bool,         // Always true in production
}
```

**Svi parametri su f64, deterministički, i JSON-serializabilni.**

---

## 6. ADVANCED PANEL UI

### 6.1 Panel Struktura

```
┌──────────────────────────────────────────────────────────────────────┐
│ AUREXIS™ Intelligence Panel                              [A/B] [?]  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─ VOLATILITY MATRIX ──────────────────────────────────────────┐   │
│  │  Stereo Elasticity  ━━━━━━━━━━━━━━●━━━━━━━━━  0.72          │   │
│  │  Energy Density     ━━━━━━━━━━━━━━━━●━━━━━━━  0.65          │   │
│  │  Escalation Rate    ━━━━━━━━━━━━●━━━━━━━━━━━  0.58          │   │
│  │  Micro Dynamics     ━━━━━━━━━━━━━━━●━━━━━━━━  0.69          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ PSYCHO REGULATOR ──────────────────────────────────────────┐   │
│  │  Fatigue Index      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░  67%           │   │
│  │  HF Attenuation     ━━━━━━━━━━━━━━━━━●━━━━━  -3.2 dB       │   │
│  │  Transient Smooth   ━━━━━━━━●━━━━━━━━━━━━━━  0.42          │   │
│  │  Width Narrowing    ━━━━━━━━━━━●━━━━━━━━━━━  0.88x         │   │
│  │  Session: 47:23     RMS avg: -18.2 dB    HF: 2.4 kJ        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ COLLISION MAP ─────────────────────────────────────────────┐   │
│  │     L ◄━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━► R      │   │
│  │        ○         ●●        ○     ●          ○               │   │
│  │  [voices: 7]  [center: 2/2 MAX]  [redistributed: 3]        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ WIN ESCALATION ────────────────────────────────────────────┐   │
│  │  Width:     ━━━━━━━━━━━━━━━━━━━━●  1.35x                   │   │
│  │  Harmonics: ━━━━━━━━━━━━━━━━━●━━━  1.22x                   │   │
│  │  Reverb:    ━━━━━━━━━━━━━━━━━━━━━━●  +650ms                │   │
│  │  Sub:       ━━━━━━━━━━━━━━━━●━━━━━  +4.2 dB                │   │
│  │  Transient: ━━━━━━━━━━━━━━━━━━●━━━  1.18x                  │   │
│  │  [Curve: exponential]  [Tier: MEGA]  [x42.5 bet]           │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ PLATFORM ──────────────────────────────────────────────────┐   │
│  │  [● Desktop]  [○ Mobile]  [○ Headphones]  [○ Cabinet]      │   │
│  │  Stereo Range: 100%    Mono Safety: OFF    Depth: Full      │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ PREDICTIVE ENERGY ─────────────────────────────────────────┐   │
│  │  Feature Proximity: ━━━━━━━━━━━━━━━━━━●━━  0.73            │   │
│  │  Pre-Widening:      ━━━━━━━━━━━━━━━●━━━━━  +0.08           │   │
│  │  Harmonic Lift:     ━━━━━━━━━━━━━━●━━━━━━  +0.05           │   │
│  │  Anticipation:      ━━━━━━━━━━━━━━━━━●━━━  0.68            │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  LIVE VISUALIZERS:                                                   │
│  [Attention Field] [Energy Density] [Fatigue Meter] [Voice Map]     │
│  [RTP-Emotion Curve]                                                 │
└──────────────────────────────────────────────────────────────────────┘
```

### 6.2 Live Visualizers (5)

| Visualizer | Tip | Opis |
|------------|-----|------|
| **Attention Gravity Field** | 2D heatmap | Gde je audio fokus na ekranu, prati `attention_x/y` |
| **Energy Density Graph** | Sparkline | Energetska gustoća tokom vremena, reaguje na volatility |
| **Fatigue Index Meter** | Vertical bar + history | 0-100% sa crvenom zonom >70% |
| **Active Voice Cluster Map** | Polar/stereo plot | Pozicija svakog aktivnog voice-a, collision indikatori |
| **RTP-to-Emotion Curve** | XY graph | RTP vrednost → emotional pacing profile |

### 6.3 Lokacija u FluxForge UI

```
flutter_ui/lib/widgets/aurexis/
├── aurexis_panel.dart                    # Main panel (~1,200 LOC)
├── volatility_matrix_section.dart        # Volatility controls (~300 LOC)
├── psycho_regulator_section.dart         # Fatigue display (~350 LOC)
├── collision_map_section.dart            # Voice cluster viz (~400 LOC)
├── win_escalation_section.dart           # Escalation curves (~300 LOC)
├── platform_selector_section.dart        # Platform toggle (~150 LOC)
├── predictive_energy_section.dart        # Feature proximity (~250 LOC)
├── visualizers/
│   ├── attention_field_viz.dart          # 2D heatmap (~350 LOC)
│   ├── energy_density_viz.dart           # Sparkline graph (~200 LOC)
│   ├── fatigue_meter_viz.dart            # Vertical meter (~200 LOC)
│   ├── voice_cluster_viz.dart            # Polar plot (~350 LOC)
│   └── rtp_emotion_curve_viz.dart        # XY graph (~250 LOC)
└── aurexis_theme.dart                    # Colors & styles (~100 LOC)
```

**Total UI: ~3,900 LOC**

### 6.4 Integracija u Layout

**SlotLab Lower Zone:**
- Novi super-tab: **AUREXIS** (pored Stages, Events, Mix, DSP, Bake)
- Ili: sub-tab unutar **Mix** super-tab-a

**DAW Lower Zone:**
- Novi sub-tab unutar **Process** super-tab-a
- AUREXIS panel za master bus intelligence

**Middleware Lower Zone:**
- Sub-tab unutar **Routing** ili zasebni super-tab

---

## 7. IMPLEMENTATION FAZE

### Phase M8: Core + Volatility + Collision (P0)

| Task | LOC | Opis |
|------|-----|------|
| rf-aurexis scaffolding | ~200 | Crate setup, lib.rs, Cargo.toml |
| core/engine.rs | ~400 | AurexisEngine struct, tick(), compute() |
| core/state.rs | ~250 | AurexisState, parameter_map.rs |
| core/config.rs | ~300 | AurexisConfig sa default koeficijentima |
| volatility/translator.rs | ~350 | Volatility → 4 audio parametra |
| volatility/profiles.rs | ~150 | Low/Med/High/Extreme presets |
| collision/priority.rs | ~300 | VoiceCollisionResolver |
| collision/redistribution.rs | ~400 | Pan spread, Z-displacement, ducking |
| collision/clustering.rs | ~200 | Center occupancy, density map |
| aurexis_ffi.rs | ~500 | C FFI bindings (15 core functions) |
| aurexis_provider.dart | ~600 | Dart provider + tick loop |
| Unit tests | ~300 | Determinism + volatility + collision |
| **TOTAL M8** | **~3,950** | |

### Phase M9: Psycho Regulator + Platform (P1)

| Task | LOC | Opis |
|------|-----|------|
| psycho/fatigue.rs | ~400 | RMS/HF/transient/stereo tracking |
| psycho/regulation.rs | ~350 | HF atten, transient smooth, width narrow |
| psycho/thresholds.rs | ~150 | Configurable thresholds |
| platform/profiles.rs | ~300 | Desktop/Mobile/Headphones/Cabinet |
| platform/adaptation.rs | ~200 | Profile application |
| FFI additions | ~300 | Psycho + platform FFI functions |
| Dart provider additions | ~300 | Fatigue state, platform switching |
| aurexis_panel.dart (core) | ~600 | Panel sa Volatility + Psycho + Platform |
| Unit tests | ~250 | Fatigue, platform |
| **TOTAL M9** | **~2,850** | |

### Phase M10: Escalation + Predictive + RTP (P1)

| Task | LOC | Opis |
|------|-----|------|
| escalation/win.rs | ~450 | Win → width/harmonics/reverb/sub/transient |
| escalation/curves.rs | ~200 | Linear/exp/log/custom curves |
| rtp/mapper.rs | ~300 | RTP → pacing, spike frequency, elasticity |
| rtp/models.rs | ~150 | RtpProfile, PacingCurve |
| geometry/attention.rs | ~300 | Attention vector computation |
| variation/deterministic.rs | ~250 | Seed-based micro variation |
| variation/hash.rs | ~100 | xxhash wrapper |
| FFI additions | ~300 | Escalation + RTP + attention + variation |
| Dart provider additions | ~300 | Win escalation, RTP, attention |
| Panel additions | ~600 | Escalation + Predictive + Attention |
| Unit tests | ~300 | Escalation, RTP, variation determinism |
| **TOTAL M10** | **~3,250** | |

### Phase M11: QA + Advanced Panel + Visualizers (P2)

| Task | LOC | Opis |
|------|-----|------|
| qa/determinism.rs | ~200 | Replay verification |
| qa/simulation.rs | ~250 | Volatility stress test |
| qa/profiling.rs | ~150 | CPU tracking |
| FFI additions | ~200 | QA functions |
| 5 visualizer widgets | ~1,350 | Attention, Energy, Fatigue, Voice, RTP |
| Panel polish | ~400 | A/B, presets, tooltips |
| Integration tests | ~400 | End-to-end determinism |
| **TOTAL M11** | **~2,950** | |

### TOTAL ESTIMATE

| Phase | LOC | Status |
|-------|-----|--------|
| M8 | ~3,950 | P0 — Critical |
| M9 | ~2,850 | P1 — High |
| M10 | ~3,250 | P1 — High |
| M11 | ~2,950 | P2 — Medium |
| **TOTAL** | **~13,000** | |

---

## 8. PERFORMANCE BUDGET

```
AUREXIS Performance Targets (from spec §11):

┌────────────────────────────────────────────────────────────┐
│  Operation                    │ Budget    │ Thread         │
├───────────────────────────────┼───────────┼────────────────┤
│  tick_session()               │ < 50μs    │ Analysis       │
│  compute_parameter_map()      │ < 100μs   │ Analysis       │
│  resolve_collisions()         │ < 30μs    │ Analysis       │
│  get_variation()              │ < 5μs     │ Any            │
│  update_win()                 │ < 20μs    │ Any            │
│  register_voice()             │ < 10μs    │ Any            │
│  TOTAL per block (20 voices)  │ < 1.5% CPU│ —              │
└────────────────────────────────────────────────────────────┘

Ključna pravila:
- Block-level parameter updates SAMO (ne per-sample)
- Analysis thread ODVOJEN od audio thread-a
- SIMD-optimizovani RMS tracking
- Lightweight FFT SAMO u analysis thread-u
- NULA alokacija u tick() metodi (pre-allocated buffers)
```

---

## 9. DETERMINISM GARANCIJE

```rust
// AUREXIS NIKADA ne koristi random()
// SVE varijacije su seed-based:

fn compute_variation(&self) -> MicroVariation {
    let seed = xxh3::xxh3_64(&[
        self.sprite_id.to_le_bytes(),
        self.event_time.to_le_bytes(),
        self.game_state.to_le_bytes(),
        self.session_index.to_le_bytes(),
    ].concat());

    MicroVariation {
        pan_drift: seed_to_range(seed, 0, -0.05, 0.05),
        width_variance: seed_to_range(seed, 1, -0.03, 0.03),
        harmonic_shift: seed_to_range(seed, 2, -0.02, 0.02),
        reflection_weight: seed_to_range(seed, 3, -0.04, 0.04),
    }
}

fn seed_to_range(seed: u64, offset: u32, min: f64, max: f64) -> f64 {
    let sub_seed = xxh3::xxh3_64(&[seed.to_le_bytes(), offset.to_le_bytes()].concat());
    let normalized = (sub_seed as f64) / (u64::MAX as f64);  // 0.0-1.0
    min + normalized * (max - min)
}

// Identičan playback na svim mašinama — GARANTOVANO
```

---

## 10. ENTERPRISE COMPLIANCE

| Zahtev | AUREXIS Rešenje |
|--------|-----------------|
| **Regulated market audits** | Deterministic replay verification |
| **GLI-11 compliance** | No random() — all seed-based |
| **ISO 17025 testing** | Session recording + replay + verify |
| **Reproducibility** | Identical output across platforms |
| **Performance reporting** | Built-in CPU profiling |
| **Fatigue compliance** | Session duration + exposure tracking |
| **Platform certification** | Per-platform audio profiles |

---

## 11. DEPENDENCY GRAPH — FINAL

```
                  ┌─────────────┐
                  │  rf-core    │
                  └──────┬──────┘
                         │
         ┌───────────────┼───────────────┐
         ↓               ↓               ↓
  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
  │  rf-stage   │ │  rf-event   │ │  rf-dsp     │
  └──────┬──────┘ └──────┬──────┘ └─────────────┘
         ↓               ↓
  ┌─────────────┐ ┌─────────────┐
  │rf-slot-lab  │ │  rf-ale     │
  └──────┬──────┘ └──────┬──────┘
         │               │
         └───────┬───────┘
                 ↓
  ╔══════════════════════════╗
  ║    rf-aurexis (NEW)      ║  ← SAMO zavisi od rf-core + serde + xxhash
  ║    Intelligence Layer    ║  ← NEMA zavisnost na rf-ale, rf-engine, rf-dsp
  ╚═════════════╤════════════╝  ← OUTPUT je čist ParameterMap (data only)
                │
         ┌──────┴──────┐
         ↓             ↓
  ┌─────────────┐ ┌─────────────┐
  │  rf-bridge  │ │   (Dart)    │
  │ aurexis_ffi │ │  Provider   │
  └──────┬──────┘ └──────┬──────┘
         │               │
    Consumers:       Consumers:
    rf-engine       ALE Provider
    rf-spatial      RTPC Service
    rf-dsp          AutoSpatial
                    EventRegistry
                    DSP Chain
```

**Ključno:** rf-aurexis NEMA zavisnost na rf-ale ili rf-engine. On je **čist intelligence layer** — prima inpute (volatility, RTP, win, session time), proizvodi output (DeterministicParameterMap). Ko konzumira output odlučuje sam.

---

## 12. SUMARNI PREGLED

### Šta AUREXIS JESTE za FluxForge

1. **Jedini slot-specifičan audio intelligence engine na svetu** — nema konkurent
2. **Deterministički** — identičan rezultat na svim mašinama, svaki put
3. **Matematički-svestan** — razume RTP, volatility, feature probability
4. **Psihoakustički** — upravlja listener fatigue tokom dugih sesija
5. **Enterprise-ready** — compliance sa GLI-11, ISO 17025, regulated markets
6. **Performantan** — < 1.5% CPU za 20 voicea, block-level samo

### Šta AUREXIS DODAJE FluxForge-u (čega NEMA)

| # | Capability | Impact |
|---|-----------|--------|
| 1 | Volatility → stereo/energy/escalation translation | Zvuk se dinamički prilagođava matematici igre |
| 2 | RTP emotional pacing | Različiti ritamski profili za različite RTP-ove |
| 3 | Session psycho regulation | Sprečava audio fatigue kod 30-120 min sesija |
| 4 | Voice collision intelligence | Sprečava mix collapse pod high-density voice stack-ovima |
| 5 | Deterministic micro-variation | Svaki playback je jedinstven ali reproduktivan |
| 6 | Win escalation intelligence | Jedan asset → beskonačno skaliranje (width, harmonics, reverb, sub) |
| 7 | Platform adaptation | Automatska prilagodba Desktop/Mobile/Headphones/Cabinet |
| 8 | Attention vector | Audio centar prati gameplay fokus |
| 9 | Predictive energy | Pre-widening i harmonic lift PRE vizuelnog klimaksa |
| 10 | QA framework | Deterministic replay, volatility simulation, fatigue stress test |

### Šta AUREXIS NE MENJA u FluxForge-u

- ALE i dalje bira layere (L1-L5)
- AutoSpatial i dalje računa bazni pan
- RTPC i dalje rutira parametre
- DSP chain i dalje procesira audio
- EventRegistry i dalje triggeruje stage-ove
- Mixer i dalje miksa

**AUREXIS samo govori svima KOLIKO — na osnovu matematike igre.**

---

*© FluxForge Studio — AUREXIS™ Adaptive Slot Audio Intelligence Architecture*
