# Anticipation System — Industry Standard Implementation

**Datum:** 2026-01-30
**Verzija:** 1.0
**Status:** ✅ FULLY IMPLEMENTED

---

## Overview

FluxForge Studio implementira **industry-standard anticipation sistem** sa per-reel tension escalation, identičan sistemima u IGT, Pragmatic Play, NetEnt, Big Time Gaming i Play'n GO slot igrama.

**Related Documentation:**
- [SLOT_LAB_SYSTEM.md](./SLOT_LAB_SYSTEM.md) — Main SlotLab documentation
- [BASE_GAME_FLOW_ANALYSIS](../analysis/BASE_GAME_FLOW_ANALYSIS_2026_01_30.md) — Complete Base Game flow
- [SLOT_LAB_AUDIO_FEATURES.md](./SLOT_LAB_AUDIO_FEATURES.md) — P0.6/P0.6.1 anticipation audio features
- [EVENT_SYNC_SYSTEM.md](./EVENT_SYNC_SYSTEM.md) — Stage→Event mapping, anticipation fallback resolution
- [slot-audio-events-master.md](../domains/slot-audio-events-master.md) — ANTICIPATION_* stage catalog

---

## Ključne Karakteristike

| Feature | Implementacija |
|---------|----------------|
| **Trigger** | 2+ scattera na prvim reelovima |
| **Per-Reel** | Svaki preostali reel ima nezavisnu anticipaciju |
| **Tension Levels** | 4 nivoa (L1-L4) sa progresivnom eskalacijom |
| **Color Progression** | Gold → Orange → Red-Orange → Red |
| **Audio Escalation** | Volume 0.6x→0.9x, Pitch +1st→+4st |
| **Visual Effects** | Glow, particles, vignette, speed slowdown |
| **GPU Shader** | `anticipation_glow.frag` za real-time glow |

---

## Architecture

### Layer Stack

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ANTICIPATION SYSTEM LAYERS                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 1: RUST ENGINE (rf-slot-lab/src/spin.rs)                     │     │
│  │                                                                     │     │
│  │  AnticipationInfo::from_scatter_positions()                        │     │
│  │    - Detektuje scatter pozicije                                    │     │
│  │    - Kreira per-reel ReelAnticipation                              │     │
│  │    - Računa tension level po poziciji                              │     │
│  │                                                                     │     │
│  │  SpinResult::generate_stages()                                     │     │
│  │    - Generiše ANTICIPATION_ON/OFF stage-ove                        │     │
│  │    - Generiše ANTICIPATION_TENSION_LAYER stage-ove                 │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                              ↓                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 2: RUST STAGE (rf-stage/src/stage.rs)                        │     │
│  │                                                                     │     │
│  │  Stage::AnticipationOn { reel_index, reason }                      │     │
│  │  Stage::AnticipationOff { reel_index }                             │     │
│  │  Stage::AnticipationTensionLayer {                                 │     │
│  │      reel_index: u8,                                               │     │
│  │      tension_level: u8,     // 1-4                                 │     │
│  │      reason: Option<String>,                                       │     │
│  │      progress: f32,         // 0.0-1.0                             │     │
│  │  }                                                                 │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                              ↓                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 3: FFI BRIDGE (rf-bridge/src/stage_ffi.rs)                   │     │
│  │                                                                     │     │
│  │  stage_create_anticipation_tension_layer()                         │     │
│  │    → JSON payload sa reel_index, tension_level, reason, progress   │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                              ↓                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 4: DART PROVIDER (slot_lab_provider.dart)                    │     │
│  │                                                                     │     │
│  │  _broadcastStages()                                                │     │
│  │    - Poziva onAnticipationStart/End callbacks                      │     │
│  │    - Parsira tension level iz payload-a                            │     │
│  │    - Notificira EventRegistry                                      │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                              ↓                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 5: EVENT REGISTRY (event_registry.dart)                      │     │
│  │                                                                     │     │
│  │  triggerStage('ANTICIPATION_TENSION_R2_L3')                        │     │
│  │    - Fallback chain: R2_L3 → R2 → TENSION → ON                     │     │
│  │    - Audio context enrichment (volume, pitch, color)               │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                              ↓                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 6: STAGE CONFIG (stage_configuration_service.dart)           │     │
│  │                                                                     │     │
│  │  26 anticipation stage registrations                               │     │
│  │    - ANTICIPATION_ON, ANTICIPATION_OFF                             │     │
│  │    - ANTICIPATION_TENSION_R{0-4}_L{1-4}                            │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                              ↓                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 7: UI WIDGET (slot_preview_widget.dart)                      │     │
│  │                                                                     │     │
│  │  Per-reel glow overlay                                             │     │
│  │  Tension level badges                                              │     │
│  │  Speed slowdown (0.3x)                                             │     │
│  │  Particle effects                                                  │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                              ↓                                               │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ LAYER 8: GPU SHADER (shaders/anticipation_glow.frag)               │     │
│  │                                                                     │     │
│  │  Uniforms: uTensionLevel, uProgress, uGlowColor, uReelIndex        │     │
│  │  Effects: Edge glow, radial glow, pulse, chromatic aberration      │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Rust Implementation

### AnticipationInfo (spin.rs)

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnticipationInfo {
    /// Reason for anticipation ("scatter", "bonus", "wild", "jackpot", "near_miss")
    pub reason: String,

    /// Which reels have triggers (e.g., scatter positions)
    pub trigger_positions: Vec<u8>,

    /// Per-reel anticipation data
    pub reel_data: Vec<ReelAnticipation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelAnticipation {
    pub reel_index: u8,
    pub tension_level: u8,      // 1-4
    pub progress: f32,          // 0.0-1.0
    pub duration_ms: f64,
    pub glow_color: (u8, u8, u8), // RGB
}

impl AnticipationInfo {
    /// Create anticipation from scatter positions
    /// 2+ scatters triggers anticipation on ALL remaining reels
    pub fn from_scatter_positions(
        scatter_reels: &[u8],
        total_reels: u8,
        timing: &AnticipationConfig,
    ) -> Option<Self> {
        if scatter_reels.len() < timing.min_scatters_to_trigger as usize {
            return None;
        }

        let max_scatter_reel = *scatter_reels.iter().max()?;
        let mut reel_data = Vec::new();

        // Anticipation on reels AFTER the last scatter
        for reel in (max_scatter_reel + 1)..total_reels {
            let position_in_sequence = (reel - max_scatter_reel - 1) as usize;
            let tension_level = timing.tension_level_for_position(position_in_sequence);
            let progress = position_in_sequence as f32 / (total_reels - max_scatter_reel - 1) as f32;

            reel_data.push(ReelAnticipation {
                reel_index: reel,
                tension_level,
                progress,
                duration_ms: timing.duration_per_reel_ms,
                glow_color: timing.color_for_tension(tension_level),
            });
        }

        Some(Self {
            reason: "scatter".to_string(),
            trigger_positions: scatter_reels.to_vec(),
            reel_data,
        })
    }
}
```

### Stage Enum (stage.rs)

```rust
pub enum Stage {
    // ... other variants ...

    /// Anticipation started on a reel
    AnticipationOn {
        reel_index: u8,
        reason: Option<String>,
    },

    /// Anticipation ended on a reel
    AnticipationOff {
        reel_index: u8,
    },

    /// Per-reel tension layer for industry-standard anticipation
    AnticipationTensionLayer {
        reel_index: u8,
        tension_level: u8,      // 1-4 (L1=Gold, L2=Orange, L3=RedOrange, L4=Red)
        reason: Option<String>, // "scatter", "bonus", "wild", "jackpot", "near_miss"
        progress: f32,          // 0.0-1.0 progress through anticipation
    },
}

impl Stage {
    /// Check if this is a looping stage
    pub fn is_looping(&self) -> bool {
        matches!(
            self,
            Stage::AnticipationOn { .. }
                | Stage::AnticipationTensionLayer { .. }
                // ... other looping stages
        )
    }
}
```

### AnticipationConfig (timing.rs)

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnticipationConfig {
    /// Minimum scatter symbols needed to trigger anticipation (default: 2)
    pub min_scatters_to_trigger: u8,

    /// Duration per reel in anticipation (ms)
    pub duration_per_reel_ms: f64,

    /// Base intensity multiplier for visual/audio effects (0.0-1.0)
    pub base_intensity: f64,

    /// Escalation factor per tension level
    pub escalation_factor: f64,

    /// Number of tension layers (typically 4: L1-L4)
    pub tension_layer_count: u8,

    /// Speed multiplier when in anticipation (0.3 = 30% of normal speed)
    pub speed_multiplier: f64,

    /// Audio pre-trigger offset (ms)
    pub audio_pre_trigger_ms: f64,

    /// Enable color progression (Gold → Orange → Red-Orange → Red)
    pub enable_color_progression: bool,

    /// Enable particle effects
    pub enable_particles: bool,

    /// Enable screen vignette darkening
    pub enable_vignette: bool,
}

impl Default for AnticipationConfig {
    fn default() -> Self {
        Self {
            min_scatters_to_trigger: 2,
            duration_per_reel_ms: 1500.0,
            base_intensity: 0.7,
            escalation_factor: 1.15,
            tension_layer_count: 4,
            speed_multiplier: 0.3,
            audio_pre_trigger_ms: 50.0,
            enable_color_progression: true,
            enable_particles: true,
            enable_vignette: true,
        }
    }
}

impl AnticipationConfig {
    /// Calculate tension level for position in sequence (0-indexed)
    pub fn tension_level_for_position(&self, position: usize) -> u8 {
        ((position + 1) as u8).min(self.tension_layer_count)
    }

    /// Get color for tension level
    pub fn color_for_tension(&self, tension_level: u8) -> (u8, u8, u8) {
        if !self.enable_color_progression {
            return (255, 215, 0); // Gold always
        }
        match tension_level {
            1 => (255, 215, 0),   // Gold #FFD700
            2 => (255, 165, 0),   // Orange #FFA500
            3 => (255, 99, 71),   // Red-Orange #FF6347
            _ => (255, 69, 0),    // Red #FF4500
        }
    }

    /// Get volume multiplier for tension level
    pub fn volume_for_tension(&self, tension_level: u8) -> f64 {
        0.5 + (tension_level.min(self.tension_layer_count) as f64 * 0.1)
    }

    /// Get pitch semitones for tension level
    pub fn pitch_semitones_for_tension(&self, tension_level: u8) -> f64 {
        tension_level.min(self.tension_layer_count) as f64
    }
}
```

---

## Tension Level System

### Color Progression (Industry Standard)

| Level | Color | Hex | RGB | Visual |
|-------|-------|-----|-----|--------|
| L1 | Gold | #FFD700 | (255, 215, 0) | 🟡 |
| L2 | Orange | #FFA500 | (255, 165, 0) | 🟠 |
| L3 | Red-Orange | #FF6347 | (255, 99, 71) | 🔶 |
| L4 | Red | #FF4500 | (255, 69, 0) | 🔴 |

### Audio Escalation

| Level | Volume | Pitch | Intensity |
|-------|--------|-------|-----------|
| L1 | 0.6x | +1 semitone | 0.70 |
| L2 | 0.7x | +2 semitones | 0.81 |
| L3 | 0.8x | +3 semitones | 0.93 |
| L4 | 0.9x | +4 semitones | 1.07 |

Formula: `intensity = base_intensity * escalation_factor^(level-1)`
- base_intensity = 0.7
- escalation_factor = 1.15

---

## Stage Format

### Stage Naming Convention

```
ANTICIPATION_TENSION_R{reel}_L{level}
```

Examples:
- `ANTICIPATION_TENSION_R2_L1` — Reel 2, Tension Level 1 (Gold)
- `ANTICIPATION_TENSION_R3_L2` — Reel 3, Tension Level 2 (Orange)
- `ANTICIPATION_TENSION_R4_L4` — Reel 4, Tension Level 4 (Red)

### Complete Stage List (26 registrations)

```
ANTICIPATION_ON
ANTICIPATION_OFF
ANTICIPATION_TENSION_R0_L1, ANTICIPATION_TENSION_R0_L2, ANTICIPATION_TENSION_R0_L3, ANTICIPATION_TENSION_R0_L4
ANTICIPATION_TENSION_R1_L1, ANTICIPATION_TENSION_R1_L2, ANTICIPATION_TENSION_R1_L3, ANTICIPATION_TENSION_R1_L4
ANTICIPATION_TENSION_R2_L1, ANTICIPATION_TENSION_R2_L2, ANTICIPATION_TENSION_R2_L3, ANTICIPATION_TENSION_R2_L4
ANTICIPATION_TENSION_R3_L1, ANTICIPATION_TENSION_R3_L2, ANTICIPATION_TENSION_R3_L3, ANTICIPATION_TENSION_R3_L4
ANTICIPATION_TENSION_R4_L1, ANTICIPATION_TENSION_R4_L2, ANTICIPATION_TENSION_R4_L3, ANTICIPATION_TENSION_R4_L4
```

### Fallback Chain

EventRegistry koristi fallback chain za fleksibilnost:

```
ANTICIPATION_TENSION_R2_L3
    ↓ (not found)
ANTICIPATION_TENSION_R2
    ↓ (not found)
ANTICIPATION_TENSION
    ↓ (not found)
ANTICIPATION_ON
```

Ovo omogućava audio dizajnerima da:
1. Kreiraju specifičan zvuk za svaki reel+level (najpreciznije)
2. Kreiraju zvuk per-reel (srednja granularnost)
3. Kreiraju jedan "catch-all" anticipation zvuk (najjednostavnije)

---

## Trigger Logic

### Scatter Detection (Dart)

```dart
// slot_preview_widget.dart
void _checkForAnticipation(int reelIndex, List<int> symbols) {
  // Count scatters on this reel
  final scatterCount = symbols.where((s) => _isScatterSymbol(s)).length;
  if (scatterCount > 0) {
    _scatterReels.add(reelIndex);
  }

  // 2+ scatters triggers anticipation on ALL remaining reels
  if (_scatterReels.length >= _scattersNeededForAnticipation) {
    final remainingReels = List.generate(widget.reels, (i) => i)
        .where((r) => !_stoppedReels.contains(r) && !_scatterReels.contains(r));

    for (final reel in remainingReels) {
      _startReelAnticipation(reel);
    }
  }
}

void _startReelAnticipation(int reelIndex) {
  // Calculate tension level based on position
  final positionInSequence = _anticipatingReels.length;
  final tensionLevel = (positionInSequence + 1).clamp(1, 4);

  // Trigger stage
  final stage = 'ANTICIPATION_TENSION_R${reelIndex}_L$tensionLevel';
  eventRegistry.triggerStage(stage, context: {
    'reel_index': reelIndex,
    'tension_level': tensionLevel,
    'reason': 'scatter',
    'progress': positionInSequence / (_remainingReels.length - 1),
  });

  // Visual: slow down reel, add glow
  _reelSpeedMultipliers[reelIndex] = 0.3;
  _reelGlowIntensities[reelIndex] = _getIntensityForTension(tensionLevel);

  _anticipatingReels.add(reelIndex);
}
```

---

## GPU Shader

### anticipation_glow.frag

**Location:** `flutter_ui/shaders/anticipation_glow.frag`

```glsl
#include <flutter/runtime_effect.glsl>

// Uniforms
uniform vec2 uResolution;      // Canvas size
uniform float uTime;           // Animation time for pulsing
uniform float uTensionLevel;   // 1-4 tension level
uniform float uProgress;       // 0-1 progress through anticipation
uniform vec3 uGlowColor;       // Glow color based on tension
uniform float uReelIndex;      // Which reel (0-4)
uniform float uReelCount;      // Total number of reels

out vec4 fragColor;

// Constants
const float PI = 3.14159265359;
const float GLOW_RADIUS = 0.15;
const float PULSE_SPEED = 4.0;
const float PULSE_AMOUNT = 0.3;

// Get tension color if not provided
vec3 getTensionColor(float level) {
    if (level < 1.5) return vec3(1.0, 0.843, 0.0);     // Gold
    else if (level < 2.5) return vec3(1.0, 0.647, 0.0); // Orange
    else if (level < 3.5) return vec3(1.0, 0.388, 0.278); // Red-Orange
    else return vec3(1.0, 0.271, 0.0);                   // Red
}

float getPulse(float time, float speed) {
    return sin(time * speed) * 0.5 + 0.5;
}

float edgeGlow(vec2 uv, float width, float softness) {
    float left = smoothstep(0.0, width, uv.x);
    float right = smoothstep(0.0, width, 1.0 - uv.x);
    float top = smoothstep(0.0, width, uv.y);
    float bottom = smoothstep(0.0, width, 1.0 - uv.y);
    return 1.0 - min(min(left, right), min(top, bottom));
}

float radialGlow(vec2 uv, float intensity) {
    vec2 center = vec2(0.5, 0.5);
    float dist = length(uv - center) * 2.0;
    return pow(1.0 - clamp(dist, 0.0, 1.0), intensity);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;

    float pulse = getPulse(uTime, PULSE_SPEED);
    float intensityMultiplier = 0.55 + (uTensionLevel * 0.15);

    vec3 glowColor = uGlowColor;
    if (length(glowColor) < 0.1) {
        glowColor = getTensionColor(uTensionLevel);
    }

    float edgeWidth = 0.1 + uTensionLevel * 0.02;
    float edge = edgeGlow(uv, edgeWidth, 0.05);
    float radial = radialGlow(uv, 1.5 + uTensionLevel * 0.5);

    float combinedGlow = edge * 0.8 + radial * 0.2;
    float finalIntensity = combinedGlow * (0.5 + pulse * 0.5) * intensityMultiplier;

    // Extra bloom for L3+
    if (uTensionLevel >= 3.0) {
        float bloom = radialGlow(uv, 2.0) * 0.3;
        finalIntensity += bloom * pulse;
    }

    // Outer ring for L4
    if (uTensionLevel >= 4.0) {
        float outerRing = 1.0 - abs(length(uv - 0.5) - 0.45) * 10.0;
        outerRing = clamp(outerRing, 0.0, 1.0) * pulse * 0.4;
        finalIntensity += outerRing;
    }

    // Progress increases brightness
    finalIntensity *= 0.7 + uProgress * 0.3;

    vec3 color = glowColor * finalIntensity;
    float alpha = clamp(finalIntensity * 0.9, 0.0, 0.9);

    // Chromatic aberration at high tension
    if (uTensionLevel >= 3.0) {
        vec2 offset = (uv - 0.5) * 0.02 * (uTensionLevel - 2.0);
        float rOffset = edgeGlow(uv + offset, edgeWidth, 0.05);
        float bOffset = edgeGlow(uv - offset, edgeWidth, 0.05);
        color.r *= 1.0 + (rOffset - edge) * 0.2;
        color.b *= 1.0 + (bOffset - edge) * 0.2;
    }

    fragColor = vec4(color, alpha);
}
```

---

## Audio Context Enrichment

### Context Payload

Kada se trigeruje anticipation stage, EventRegistry obogaćuje context sa audio parametrima:

```dart
// event_registry.dart
Map<String, dynamic> _enrichAnticipationContext(
  String stage,
  Map<String, dynamic>? context,
) {
  final enriched = Map<String, dynamic>.from(context ?? {});

  // Parse tension level from stage name
  final tensionMatch = RegExp(r'_L(\d)$').firstMatch(stage);
  final tensionLevel = tensionMatch != null
      ? int.parse(tensionMatch.group(1)!)
      : 1;

  // Add audio parameters based on tension
  enriched['volume'] = _getVolumeForTension(tensionLevel);
  enriched['pitch_semitones'] = _getPitchForTension(tensionLevel);
  enriched['color'] = _getColorForTension(tensionLevel);
  enriched['intensity'] = _getIntensityForTension(tensionLevel);

  return enriched;
}

double _getVolumeForTension(int level) {
  return 0.5 + (level.clamp(1, 4) * 0.1); // 0.6, 0.7, 0.8, 0.9
}

double _getPitchForTension(int level) {
  return level.clamp(1, 4).toDouble(); // +1, +2, +3, +4 semitones
}

List<int> _getColorForTension(int level) {
  return switch (level) {
    1 => [255, 215, 0],   // Gold
    2 => [255, 165, 0],   // Orange
    3 => [255, 99, 71],   // Red-Orange
    _ => [255, 69, 0],    // Red
  };
}

double _getIntensityForTension(int level) {
  const baseIntensity = 0.7;
  const escalationFactor = 1.15;
  return baseIntensity * pow(escalationFactor, level - 1);
}
```

---

## Industry Comparison

### Feature Parity Score: 9/9 ✅

| Feature | IGT | Pragmatic | NetEnt | BTG | Play'n GO | FluxForge |
|---------|-----|-----------|--------|-----|-----------|-----------|
| Per-reel detection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tension escalation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Color progression | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Speed slowdown | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Audio escalation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Glow effects | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Particle effects | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Configurable trigger | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Pre-trigger audio | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Key Files

| Layer | File | Lines | Description |
|-------|------|-------|-------------|
| Rust Engine | `crates/rf-slot-lab/src/spin.rs` | 187-235 | AnticipationInfo creation |
| Rust Stage | `crates/rf-stage/src/stage.rs` | 484-621 | Stage enum, category, looping |
| Rust Timing | `crates/rf-slot-lab/src/timing.rs` | 26-159 | AnticipationConfig |
| FFI Bridge | `crates/rf-bridge/src/stage_ffi.rs` | — | stage_create_anticipation_tension_layer |
| Dart Provider | `flutter_ui/lib/providers/slot_lab_provider.dart` | — | Callback invocation |
| Event Registry | `flutter_ui/lib/services/event_registry.dart` | 476-488 | Pre-trigger stages |
| Stage Config | `flutter_ui/lib/services/stage_configuration_service.dart` | — | 26 registrations |
| UI Widget | `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` | — | Glow overlay |
| GPU Shader | `flutter_ui/shaders/anticipation_glow.frag` | 1-130 | Pulsing glow effect |

---

## Usage Examples

### Audio Designer: Creating Anticipation Events

```dart
// Create per-level anticipation events
for (int level = 1; level <= 4; level++) {
  final event = AudioEvent(
    id: 'anticipation_l$level',
    stage: 'ANTICIPATION_TENSION', // Catches all ANTICIPATION_TENSION_R*_L*
    layers: [
      AudioLayer(
        audioPath: 'anticipation_layer_$level.wav',
        volume: 0.5 + (level * 0.1), // 0.6 → 0.9
        pan: 0.0,
        busId: 2, // SFX bus
      ),
    ],
    priority: 70 + level, // 71 → 74
  );
  eventRegistry.registerEvent(event);
}
```

### Slot Game Designer: Configuring Anticipation

```dart
// Configure anticipation for high-volatility game
final config = AnticipationConfig(
  minScattersToTrigger: 2,
  durationPerReelMs: 2000, // Longer for drama
  baseIntensity: 0.8,
  escalationFactor: 1.25, // More dramatic escalation
  tensionLayerCount: 4,
  speedMultiplier: 0.25, // Slower
  audioPreTriggerMs: 75, // Earlier audio
  enableColorProgression: true,
  enableParticles: true,
  enableVignette: true,
);

slotLabProvider.setAnticipationConfig(config);
```

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-30 | 1.0 | Initial documentation |

---

**Author:** Claude Opus 4.5
**Last Updated:** 2026-01-30
