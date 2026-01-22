# AutoSpatial System — Architecture Documentation

## Overview

AutoSpatialEngine is a **UI-driven spatial audio positioning system** designed specifically for slot game audio. Unlike traditional spatial audio that relies on 3D world coordinates, AutoSpatial derives spatial positioning from **UI element positions**, **animation states**, and **semantic intent**.

## Core Philosophy

```
Traditional Spatial Audio:    3D World Position → Audio Panning
AutoSpatial:                  UI Position + Intent + Motion → Intelligent Panning
```

Slot games don't have a 3D world — they have **UI elements** that move, animate, and trigger events. AutoSpatial bridges this gap by:

1. **Tracking UI anchors** (reel positions, win display, buttons)
2. **Understanding semantic intent** (is this a "big win" or "small click"?)
3. **Fusing multiple signals** with confidence weighting
4. **Applying perceptual smoothing** to avoid jarring pans

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            AutoSpatialEngine                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
│  │   Anchor    │    │   Intent    │    │   Motion    │                     │
│  │  Registry   │    │   Rules     │    │  Tracker    │                     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                     │
│         │                  │                  │                             │
│         └─────────────┬────┴────┬─────────────┘                             │
│                       ▼         ▼                                           │
│              ┌─────────────────────────────┐                               │
│              │      Fusion Engine          │                               │
│              │  (Confidence-weighted)      │                               │
│              └─────────────┬───────────────┘                               │
│                            │                                               │
│                            ▼                                               │
│              ┌─────────────────────────────┐                               │
│              │    Kalman Filter (EKF3D)    │                               │
│              │  (Predictive smoothing)     │                               │
│              └─────────────┬───────────────┘                               │
│                            │                                               │
│                            ▼                                               │
│              ┌─────────────────────────────┐                               │
│              │      SpatialOutput          │                               │
│              │  pan, width, distance,      │                               │
│              │  doppler, reverb, HRTF      │                               │
│              └─────────────────────────────┘                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Anchor Registry

Tracks UI element positions in normalized screen space (-1 to +1).

```dart
class AnchorFrame {
  final String id;           // e.g., "reel_0", "win_display", "spin_button"
  final Offset position;     // Normalized (-1..+1, -1..+1)
  final Size size;           // Normalized size
  final Offset velocity;     // Movement velocity
  final double confidence;   // 0.0 - 1.0
  final DateTime timestamp;
}
```

**Registration points:**
- Reel positions (5 reels → `reel_0` through `reel_4`)
- Win display area
- Spin button
- Jackpot ticker
- Bonus meter
- Any custom UI elements

### 2. Intent Rules

30+ pre-defined rules that map semantic intents to spatial behavior.

```dart
class IntentRule {
  // Fusion weights (must sum to 1.0)
  final double wAnchor;    // Weight for anchor position
  final double wMotion;    // Weight for motion/velocity
  final double wIntent;    // Weight for intent-based position

  // Panning behavior
  final double width;      // Stereo spread (0.0 = mono, 1.0 = full)
  final double deadzone;   // Center area with no panning
  final double maxPan;     // Maximum pan amount (0.0 - 1.0)

  // Smoothing
  final double tauMs;      // Exponential smoothing time constant

  // Distance model
  final DistanceModel distanceModel;  // linear, inverse, exponential
  final double rolloff;               // Attenuation rate

  // Doppler
  final bool dopplerEnabled;
  final double dopplerScale;

  // Reverb
  final double reverbBaseLevel;
  final double reverbDistanceScale;

  // Easing
  final EasingFunction easing;  // 13 options
}
```

**Default intents include:**
| Intent | Description | Typical Rule |
|--------|-------------|--------------|
| `spin_start` | Spin button pressed | Center, wide |
| `reel_stop` | Individual reel stops | Per-reel pan |
| `win_small` | Small win celebration | Moderate width |
| `win_big` | Big win | Full width, reverb |
| `jackpot` | Jackpot trigger | Maximum everything |
| `cascade_step` | Cascade animation step | Follow motion |
| `ui_click` | Generic UI interaction | Tight, dry |
| `coin_fly` | Coin animation | Follow trajectory |

### 3. Bus Policies

Per-bus spatial modifiers that apply on top of intent rules.

```dart
class BusPolicy {
  final double widthMul;      // Width multiplier (0.0 - 2.0)
  final double maxPanMul;     // Max pan multiplier
  final double tauMul;        // Smoothing multiplier
  final double reverbMul;     // Reverb multiplier
  final double dopplerMul;    // Doppler multiplier
  final bool enableHRTF;      // HRTF processing
  final int priorityBoost;    // Voice priority adjustment
}
```

**6 spatial buses:**
| Bus | Purpose | Default Policy |
|-----|---------|----------------|
| `ui` | UI interactions | Tight, dry, no HRTF |
| `reels` | Reel sounds | Per-reel panning |
| `sfx` | Sound effects | Wide, some reverb |
| `vo` | Voice/VO | Center, clear |
| `music` | Background music | Stereo, no spatial |
| `ambience` | Ambient sounds | Very wide, reverb |

### 4. Fusion Engine

Combines multiple spatial signals with confidence weighting.

```
Final Position = wAnchor × AnchorPos × ConfAnchor
               + wMotion × MotionPos × ConfMotion
               + wIntent × IntentPos × ConfIntent
               ─────────────────────────────────────
               wAnchor × ConfAnchor + wMotion × ConfMotion + wIntent × ConfIntent
```

Confidence sources:
- **Anchor confidence**: How recently was the anchor updated?
- **Motion confidence**: Is the velocity stable?
- **Intent confidence**: How well-defined is the intent rule?

### 5. Kalman Filter (EKF3D)

Extended Kalman Filter for predictive smoothing in 3D space.

**State vector:** `[x, y, z, vx, vy, vz]`

**Benefits:**
- Predicts position ahead of updates (reduces latency perception)
- Smooths out jitter from rapid UI updates
- Handles velocity for Doppler calculation

### 6. Spatial Output

Final output applied to audio:

```dart
class SpatialOutput {
  final double pan;           // -1.0 (left) to +1.0 (right)
  final double width;         // 0.0 (mono) to 1.0 (full stereo)
  final double distance;      // 0.0 (near) to 1.0 (far)
  final double dopplerShift;  // Pitch multiplier
  final double reverbSend;    // Reverb send level
  final double lpfCutoff;     // Low-pass filter for distance
  final HrtfParams? hrtf;     // HRTF coefficients (if enabled)
  final AmbisonicsCoeffs? ambi; // Ambisonics (if enabled)
}
```

## Object Pooling

EventTrackerPool provides zero-allocation event tracking:

```dart
class EventTrackerPool {
  static const int poolSize = 128;
  final List<EventTracker> _pool;
  final Set<int> _active;

  EventTracker acquire(String eventId);
  void release(EventTracker tracker);
}
```

**Why pooling?**
- Slot games can fire 100+ events per second during cascades
- Heap allocation in audio path = latency spikes
- Pre-allocated pool ensures O(1) acquire/release

## Render Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `stereo` | Traditional L/R panning | Default, headphones/speakers |
| `binaural` | HRTF-based 3D | Headphone-only, immersive |
| `foa` | First-Order Ambisonics | VR, spatial audio |
| `hoa` | Higher-Order Ambisonics | High-end VR |
| `atmos` | Dolby Atmos compatible | Home theater |

## UI Panel

The AutoSpatial UI Panel provides configuration and monitoring:

| Tab | Purpose |
|-----|---------|
| **Intent Rules** | Create/edit/delete intent rules, JSON export |
| **Bus Policies** | Configure per-bus spatial behavior |
| **Anchors** | Monitor registered UI anchors |
| **Stats & Config** | Engine stats, global toggles, listener position |
| **Visualizer** | Real-time 2D radar of active events |

## File Locations

```
flutter_ui/lib/
├── spatial/
│   └── auto_spatial.dart           # Core engine (2,296 LOC)
├── providers/
│   └── auto_spatial_provider.dart  # State management (~350 LOC)
└── widgets/spatial/
    ├── auto_spatial_panel.dart        # Main panel (~260 LOC)
    ├── intent_rule_editor.dart        # Rules editor (~600 LOC)
    ├── bus_policy_editor.dart         # Bus policies (~350 LOC)
    ├── anchor_monitor.dart            # Anchor viz (~500 LOC)
    ├── spatial_stats_panel.dart       # Stats/config (~500 LOC)
    ├── spatial_event_visualizer.dart  # Radar viz (~550 LOC)
    └── spatial_widgets.dart           # Shared widgets (~250 LOC)
```

## Integration with EventRegistry

AutoSpatial integrates with EventRegistry via `_stageToIntent()`:

```dart
// In event_registry.dart
String? _stageToIntent(String stage) {
  return switch (stage) {
    'SPIN_START' => 'spin_start',
    'REEL_STOP_0' => 'reel_stop_0',
    'REEL_STOP_1' => 'reel_stop_1',
    // ... 300+ mappings
    'JACKPOT_GRAND' => 'jackpot_grand',
    _ => null,
  };
}
```

When an event triggers:
1. EventRegistry looks up the intent
2. AutoSpatialEngine processes with intent rule
3. Final spatial output applied to audio voice

## Performance Characteristics

| Metric | Target | Actual |
|--------|--------|--------|
| Events per tick | 64 | 128 pool size |
| Tick latency | < 1ms | ~0.3ms avg |
| Memory overhead | < 1MB | ~500KB (pooled) |
| Kalman update | < 0.1ms | ~0.05ms |

## Future Enhancements

1. **FFI Bridge**: Connect to Rust spatial processing for lower latency
2. **Rule Templates**: Pre-made presets for common scenarios
3. **A/B Comparison**: Side-by-side spatial config comparison
4. **3D Visualizer**: WebGL-based 3D spatial field visualization
5. **HRTF Profiles**: Multiple HRTF datasets for different head sizes
