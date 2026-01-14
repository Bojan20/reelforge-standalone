# FluxForge Studio — MIXER Deep Dive

> Detaljne specifikacije mixer arhitekture iz Pro Tools, REAPER i Cubase

---

## 1. INSERT ARCHITECTURE (Pro Tools Standard)

### 1.1 Problem koji rešava

```
TRADICIONALNI PROBLEM:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Većina DAW-ova ima samo PRE-FADER inserts:                    │
│                                                                  │
│  Input → [Insert 1] → [Insert 2] → FADER → Output              │
│                                                                  │
│  Problem 1: Saturation posle fader-a                            │
│  • Fader down = saturation se menja                            │
│  • Nema konzistentnog zvuka                                    │
│                                                                  │
│  Problem 2: Creative effects posle fader-a                      │
│  • Reverb send posle fader-a — fader menja reverb amount       │
│  • Ovo NEKAD želiš, nekad NE                                   │
│                                                                  │
│  Problem 3: Cue mixes                                           │
│  • Artist treba dry signal u headphones                        │
│  • Ali main mix ima wet reverb                                 │
│  • Sa samo post-fader sends — nemoguće razdvojiti              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Pro Tools Signal Flow

```
PRO TOOLS INSERT ARCHITECTURE — INDUSTRY STANDARD
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ╔════════════════════════════════════════════════════════════╗ │
│  ║                        INPUT                                ║ │
│  ╚════════════════════════════════════════════════════════════╝ │
│                             ↓                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ CLIP GAIN (Pro Tools exclusive)                            │ │
│  │ • Pre-everything gain adjustment                           │ │
│  │ • Per-region, not per-track                                │ │
│  │ • -144dB to +36dB range                                    │ │
│  │ • Non-destructive                                          │ │
│  │ • Visible as waveform overlay line                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             ↓                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ INPUT TRIM                                                  │ │
│  │ • Track-level gain (before all processing)                 │ │
│  │ • -24dB to +24dB                                           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             ↓                                    │
│  ╔════════════════════════════════════════════════════════════╗ │
│  ║ PRE-FADER INSERTS (A-E) — 5 Slots                          ║ │
│  ╠════════════════════════════════════════════════════════════╣ │
│  ║ Slot A: [Gate/Expander]         ← First in chain           ║ │
│  ║ Slot B: [EQ]                    ← Corrective EQ            ║ │
│  ║ Slot C: [Compressor]            ← Dynamics control         ║ │
│  ║ Slot D: [De-esser]              ← Frequency-specific       ║ │
│  ║ Slot E: [Saturation]            ← Color/warmth             ║ │
│  ╚════════════════════════════════════════════════════════════╝ │
│                             ↓                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ PRE-FADER SENDS (A-E) — 5 Sends                            │ │
│  │                                                             │ │
│  │ Use cases:                                                  │ │
│  │ • Cue mixes (artist headphones — dry signal)               │ │
│  │ • Parallel compression (before fader!)                     │ │
│  │ • Drum room mic blend                                      │ │
│  │                                                             │ │
│  │ Key: Signal level INDEPENDENT of fader position            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             ↓                                    │
│  ╔════════════════════════════════════════════════════════════╗ │
│  ║                        FADER                                ║ │
│  ║                                                             ║ │
│  ║  Range: -∞ to +12dB                                        ║ │
│  ║  Resolution: 0.1dB steps                                   ║ │
│  ║  Unity gain: 0dB (default position)                        ║ │
│  ║                                                             ║ │
│  ╚════════════════════════════════════════════════════════════╝ │
│                             ↓                                    │
│  ╔════════════════════════════════════════════════════════════╗ │
│  ║ POST-FADER INSERTS (F-J) — 5 Slots                         ║ │
│  ╠════════════════════════════════════════════════════════════╣ │
│  ║ Slot F: [Limiter]               ← Safety limiting          ║ │
│  ║ Slot G: [Creative Saturation]   ← Fader-dependent color    ║ │
│  ║ Slot H: [Stereo Imager]         ← Width processing         ║ │
│  ║ Slot I: [Metering]              ← Final level check        ║ │
│  ║ Slot J: [Dither]                ← If going to lower bitdepth║ │
│  ╚════════════════════════════════════════════════════════════╝ │
│                             ↓                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ POST-FADER SENDS (F-J) — 5 Sends                           │ │
│  │                                                             │ │
│  │ Use cases:                                                  │ │
│  │ • Reverb (follows fader — quieter track = less reverb)     │ │
│  │ • Delay (follows fader)                                    │ │
│  │ • Parallel FX (fader-dependent amount)                     │ │
│  │                                                             │ │
│  │ Key: Signal level FOLLOWS fader position                   │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             ↓                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ PAN                                                         │ │
│  │ • Mono → Stereo: L/R position                              │ │
│  │ • Stereo → Stereo: Balance + Width                         │ │
│  │ • Surround: Joystick + Divergence                          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             ↓                                    │
│  ╔════════════════════════════════════════════════════════════╗ │
│  ║                       OUTPUT                                ║ │
│  ╚════════════════════════════════════════════════════════════╝ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 FluxForge Rust Implementation

```rust
// crates/rf-engine/src/mixer/channel_strip.rs

use std::sync::Arc;
use parking_lot::RwLock;
use rtrb::{Consumer, Producer};

// ═══════════════════════════════════════════════════════════════════════════
// INSERT SLOT
// ═══════════════════════════════════════════════════════════════════════════

/// Single insert slot in the channel strip
#[derive(Clone)]
pub struct InsertSlot {
    /// Processor in this slot (None = bypassed/empty)
    processor: Option<Arc<dyn Processor>>,

    /// Bypass state
    bypassed: bool,

    /// Wet/dry mix (0.0 = fully dry, 1.0 = fully wet)
    mix: f64,

    /// Slot position
    position: InsertPosition,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum InsertPosition {
    PreFaderA,
    PreFaderB,
    PreFaderC,
    PreFaderD,
    PreFaderE,
    PostFaderF,
    PostFaderG,
    PostFaderH,
    PostFaderI,
    PostFaderJ,
}

impl InsertPosition {
    pub fn is_pre_fader(&self) -> bool {
        matches!(self,
            Self::PreFaderA | Self::PreFaderB | Self::PreFaderC |
            Self::PreFaderD | Self::PreFaderE
        )
    }

    pub fn slot_index(&self) -> usize {
        match self {
            Self::PreFaderA => 0,
            Self::PreFaderB => 1,
            Self::PreFaderC => 2,
            Self::PreFaderD => 3,
            Self::PreFaderE => 4,
            Self::PostFaderF => 5,
            Self::PostFaderG => 6,
            Self::PostFaderH => 7,
            Self::PostFaderI => 8,
            Self::PostFaderJ => 9,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SEND
// ═══════════════════════════════════════════════════════════════════════════

/// Send to aux/bus
#[derive(Clone)]
pub struct Send {
    /// Destination bus ID
    destination: u32,

    /// Send level (-inf to +12dB)
    level_db: f64,

    /// Pan position for send
    pan: f64,

    /// Pre or post fader
    pre_fader: bool,

    /// Mute state
    muted: bool,
}

impl Send {
    /// Calculate send gain (linear)
    #[inline]
    pub fn gain(&self) -> f64 {
        if self.muted {
            0.0
        } else {
            db_to_linear(self.level_db)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP (Pro Tools-style)
// ═══════════════════════════════════════════════════════════════════════════

/// Complete channel strip with Pro Tools signal flow
pub struct ChannelStrip {
    /// Track ID
    pub id: u32,

    /// Track name
    pub name: String,

    // ─────────────────────────────────────────────────────────────────────
    // INPUT SECTION
    // ─────────────────────────────────────────────────────────────────────

    /// Input source (physical input, bus, or track output)
    pub input_source: InputSource,

    /// Clip gain (per-region, stored separately)
    /// This is applied in the timeline, not here

    /// Input trim (-24 to +24 dB)
    pub input_trim_db: f64,

    /// Phase invert
    pub phase_invert: bool,

    // ─────────────────────────────────────────────────────────────────────
    // PRE-FADER SECTION
    // ─────────────────────────────────────────────────────────────────────

    /// Pre-fader insert slots (A-E)
    pub pre_fader_inserts: [InsertSlot; 5],

    /// Pre-fader sends (A-E)
    pub pre_fader_sends: [Option<Send>; 5],

    // ─────────────────────────────────────────────────────────────────────
    // FADER SECTION
    // ─────────────────────────────────────────────────────────────────────

    /// Fader level (-inf to +12 dB)
    pub fader_db: f64,

    /// Mute state
    pub muted: bool,

    /// Solo state
    pub soloed: bool,

    // ─────────────────────────────────────────────────────────────────────
    // POST-FADER SECTION
    // ─────────────────────────────────────────────────────────────────────

    /// Post-fader insert slots (F-J)
    pub post_fader_inserts: [InsertSlot; 5],

    /// Post-fader sends (F-J)
    pub post_fader_sends: [Option<Send>; 5],

    // ─────────────────────────────────────────────────────────────────────
    // OUTPUT SECTION
    // ─────────────────────────────────────────────────────────────────────

    /// Pan position (-1.0 = L, 0.0 = C, 1.0 = R)
    pub pan: f64,

    /// Stereo width (0.0 = mono, 1.0 = full stereo, >1.0 = widened)
    pub width: f64,

    /// Output destination
    pub output_destination: OutputDestination,

    // ─────────────────────────────────────────────────────────────────────
    // METERING
    // ─────────────────────────────────────────────────────────────────────

    /// Input metering point
    pub input_meter: MeterData,

    /// Pre-fader metering point
    pub pre_fader_meter: MeterData,

    /// Post-fader metering point (output)
    pub output_meter: MeterData,
}

impl ChannelStrip {
    /// Process audio through channel strip
    /// CRITICAL: No allocations in this function!
    #[inline(always)]
    pub fn process(
        &mut self,
        input: &[&[f64]],      // Multi-channel input
        output: &mut [&mut [f64]], // Multi-channel output
        send_buffers: &mut [SendBuffer], // Pre-allocated send buffers
    ) {
        let num_samples = input[0].len();
        let num_channels = input.len().min(output.len());

        // ─────────────────────────────────────────────────────────────────
        // STEP 1: Input Trim + Phase
        // ─────────────────────────────────────────────────────────────────
        let trim_gain = db_to_linear(self.input_trim_db);
        let phase_mult = if self.phase_invert { -1.0 } else { 1.0 };
        let input_gain = trim_gain * phase_mult;

        // Copy input to output with gain (working buffer)
        for ch in 0..num_channels {
            for i in 0..num_samples {
                output[ch][i] = input[ch][i] * input_gain;
            }
        }

        // Update input meter
        self.input_meter.update(output);

        // ─────────────────────────────────────────────────────────────────
        // STEP 2: Pre-fader Inserts (A-E)
        // ─────────────────────────────────────────────────────────────────
        for slot in &mut self.pre_fader_inserts {
            if !slot.bypassed {
                if let Some(ref mut proc) = slot.processor {
                    proc.process(output);

                    // Apply wet/dry mix if not 100% wet
                    if slot.mix < 1.0 {
                        // Mix would require dry buffer — skip for now
                        // In real impl: store dry, mix after
                    }
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        // STEP 3: Pre-fader Sends (A-E)
        // ─────────────────────────────────────────────────────────────────
        for (idx, send) in self.pre_fader_sends.iter().enumerate() {
            if let Some(s) = send {
                if s.pre_fader && !s.muted {
                    let gain = s.gain();
                    let buffer = &mut send_buffers[idx];

                    for ch in 0..num_channels {
                        for i in 0..num_samples {
                            buffer.add_sample(ch, i, output[ch][i] * gain);
                        }
                    }
                }
            }
        }

        // Update pre-fader meter
        self.pre_fader_meter.update(output);

        // ─────────────────────────────────────────────────────────────────
        // STEP 4: Fader + Mute
        // ─────────────────────────────────────────────────────────────────
        let fader_gain = if self.muted {
            0.0
        } else {
            db_to_linear(self.fader_db)
        };

        for ch in 0..num_channels {
            for i in 0..num_samples {
                output[ch][i] *= fader_gain;
            }
        }

        // ─────────────────────────────────────────────────────────────────
        // STEP 5: Post-fader Inserts (F-J)
        // ─────────────────────────────────────────────────────────────────
        for slot in &mut self.post_fader_inserts {
            if !slot.bypassed {
                if let Some(ref mut proc) = slot.processor {
                    proc.process(output);
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        // STEP 6: Post-fader Sends (F-J)
        // ─────────────────────────────────────────────────────────────────
        for (idx, send) in self.post_fader_sends.iter().enumerate() {
            if let Some(s) = send {
                if !s.pre_fader && !s.muted {
                    let gain = s.gain();
                    let buffer = &mut send_buffers[5 + idx]; // Offset for post-fader

                    for ch in 0..num_channels {
                        for i in 0..num_samples {
                            buffer.add_sample(ch, i, output[ch][i] * gain);
                        }
                    }
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        // STEP 7: Pan
        // ─────────────────────────────────────────────────────────────────
        if num_channels == 2 {
            // Stereo balance + width
            apply_stereo_pan(output, self.pan, self.width);
        } else if num_channels == 1 && output.len() >= 2 {
            // Mono to stereo panning
            apply_mono_pan(output, self.pan);
        }

        // Update output meter
        self.output_meter.update(output);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

#[inline(always)]
fn db_to_linear(db: f64) -> f64 {
    if db <= -144.0 {
        0.0
    } else {
        10.0_f64.powf(db / 20.0)
    }
}

#[inline(always)]
fn apply_stereo_pan(output: &mut [&mut [f64]], pan: f64, width: f64) {
    // Constant power pan law
    let left_gain = ((1.0 - pan) * 0.5 * std::f64::consts::FRAC_PI_2).cos();
    let right_gain = ((1.0 + pan) * 0.5 * std::f64::consts::FRAC_PI_2).cos();

    // Width processing (mid/side)
    let mid_gain = (1.0 - width * 0.5).max(0.0);
    let side_gain = width;

    for i in 0..output[0].len() {
        let left = output[0][i];
        let right = output[1][i];

        // Convert to mid/side
        let mid = (left + right) * 0.5;
        let side = (left - right) * 0.5;

        // Apply width
        let new_mid = mid * mid_gain;
        let new_side = side * side_gain;

        // Convert back to L/R with pan
        output[0][i] = (new_mid + new_side) * left_gain;
        output[1][i] = (new_mid - new_side) * right_gain;
    }
}

#[inline(always)]
fn apply_mono_pan(output: &mut [&mut [f64]], pan: f64) {
    let left_gain = ((1.0 - pan) * 0.5 * std::f64::consts::FRAC_PI_2).cos();
    let right_gain = ((1.0 + pan) * 0.5 * std::f64::consts::FRAC_PI_2).cos();

    for i in 0..output[0].len() {
        let mono = output[0][i];
        output[0][i] = mono * left_gain;
        output[1][i] = mono * right_gain;
    }
}
```

### 1.4 Flutter Dart Implementation

```dart
// flutter_ui/lib/providers/mixer/channel_strip_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../src/rust/engine_api.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INSERT POSITION ENUM
// ═══════════════════════════════════════════════════════════════════════════

enum InsertPosition {
  preFaderA(0, 'A', true),
  preFaderB(1, 'B', true),
  preFaderC(2, 'C', true),
  preFaderD(3, 'D', true),
  preFaderE(4, 'E', true),
  postFaderF(5, 'F', false),
  postFaderG(6, 'G', false),
  postFaderH(7, 'H', false),
  postFaderI(8, 'I', false),
  postFaderJ(9, 'J', false);

  final int index;
  final String label;
  final bool isPreFader;

  const InsertPosition(this.index, this.label, this.isPreFader);

  static InsertPosition fromIndex(int index) {
    return InsertPosition.values.firstWhere((e) => e.index == index);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT SLOT STATE
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class InsertSlotState {
  final InsertPosition position;
  final String? pluginId;
  final String? pluginName;
  final bool bypassed;
  final double mix; // 0.0 - 1.0

  const InsertSlotState({
    required this.position,
    this.pluginId,
    this.pluginName,
    this.bypassed = false,
    this.mix = 1.0,
  });

  bool get isEmpty => pluginId == null;

  InsertSlotState copyWith({
    String? pluginId,
    String? pluginName,
    bool? bypassed,
    double? mix,
  }) {
    return InsertSlotState(
      position: position,
      pluginId: pluginId ?? this.pluginId,
      pluginName: pluginName ?? this.pluginName,
      bypassed: bypassed ?? this.bypassed,
      mix: mix ?? this.mix,
    );
  }

  InsertSlotState clear() {
    return InsertSlotState(position: position);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SEND STATE
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class SendState {
  final int index;
  final int? destinationBusId;
  final String? destinationName;
  final double levelDb; // -inf to +12
  final double pan; // -1.0 to 1.0
  final bool preFader;
  final bool muted;

  const SendState({
    required this.index,
    this.destinationBusId,
    this.destinationName,
    this.levelDb = -6.0,
    this.pan = 0.0,
    required this.preFader,
    this.muted = false,
  });

  bool get isEmpty => destinationBusId == null;

  SendState copyWith({
    int? destinationBusId,
    String? destinationName,
    double? levelDb,
    double? pan,
    bool? preFader,
    bool? muted,
  }) {
    return SendState(
      index: index,
      destinationBusId: destinationBusId ?? this.destinationBusId,
      destinationName: destinationName ?? this.destinationName,
      levelDb: levelDb ?? this.levelDb,
      pan: pan ?? this.pan,
      preFader: preFader ?? this.preFader,
      muted: muted ?? this.muted,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP STATE
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class ChannelStripState {
  final int trackId;
  final String name;

  // Input section
  final double inputTrimDb;
  final bool phaseInvert;

  // Pre-fader section
  final List<InsertSlotState> preFaderInserts;
  final List<SendState> preFaderSends;

  // Fader section
  final double faderDb;
  final bool muted;
  final bool soloed;

  // Post-fader section
  final List<InsertSlotState> postFaderInserts;
  final List<SendState> postFaderSends;

  // Output section
  final double pan;
  final double width;
  final int? outputBusId;

  // Metering
  final double inputLevel;
  final double preFaderLevel;
  final double outputLevel;

  const ChannelStripState({
    required this.trackId,
    required this.name,
    this.inputTrimDb = 0.0,
    this.phaseInvert = false,
    required this.preFaderInserts,
    required this.preFaderSends,
    this.faderDb = 0.0,
    this.muted = false,
    this.soloed = false,
    required this.postFaderInserts,
    required this.postFaderSends,
    this.pan = 0.0,
    this.width = 1.0,
    this.outputBusId,
    this.inputLevel = -144.0,
    this.preFaderLevel = -144.0,
    this.outputLevel = -144.0,
  });

  factory ChannelStripState.initial(int trackId, String name) {
    return ChannelStripState(
      trackId: trackId,
      name: name,
      preFaderInserts: List.generate(
        5,
        (i) => InsertSlotState(position: InsertPosition.fromIndex(i)),
      ),
      preFaderSends: List.generate(
        5,
        (i) => SendState(index: i, preFader: true),
      ),
      postFaderInserts: List.generate(
        5,
        (i) => InsertSlotState(position: InsertPosition.fromIndex(i + 5)),
      ),
      postFaderSends: List.generate(
        5,
        (i) => SendState(index: i + 5, preFader: false),
      ),
    );
  }

  ChannelStripState copyWith({
    String? name,
    double? inputTrimDb,
    bool? phaseInvert,
    List<InsertSlotState>? preFaderInserts,
    List<SendState>? preFaderSends,
    double? faderDb,
    bool? muted,
    bool? soloed,
    List<InsertSlotState>? postFaderInserts,
    List<SendState>? postFaderSends,
    double? pan,
    double? width,
    int? outputBusId,
    double? inputLevel,
    double? preFaderLevel,
    double? outputLevel,
  }) {
    return ChannelStripState(
      trackId: trackId,
      name: name ?? this.name,
      inputTrimDb: inputTrimDb ?? this.inputTrimDb,
      phaseInvert: phaseInvert ?? this.phaseInvert,
      preFaderInserts: preFaderInserts ?? this.preFaderInserts,
      preFaderSends: preFaderSends ?? this.preFaderSends,
      faderDb: faderDb ?? this.faderDb,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      postFaderInserts: postFaderInserts ?? this.postFaderInserts,
      postFaderSends: postFaderSends ?? this.postFaderSends,
      pan: pan ?? this.pan,
      width: width ?? this.width,
      outputBusId: outputBusId ?? this.outputBusId,
      inputLevel: inputLevel ?? this.inputLevel,
      preFaderLevel: preFaderLevel ?? this.preFaderLevel,
      outputLevel: outputLevel ?? this.outputLevel,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════

class ChannelStripNotifier extends StateNotifier<ChannelStripState> {
  ChannelStripNotifier(ChannelStripState initial) : super(initial);

  // ─────────────────────────────────────────────────────────────────────────
  // INPUT SECTION
  // ─────────────────────────────────────────────────────────────────────────

  void setInputTrim(double db) {
    state = state.copyWith(inputTrimDb: db.clamp(-24.0, 24.0));
    _syncToEngine('input_trim', state.inputTrimDb);
  }

  void togglePhaseInvert() {
    state = state.copyWith(phaseInvert: !state.phaseInvert);
    _syncToEngine('phase_invert', state.phaseInvert);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FADER SECTION
  // ─────────────────────────────────────────────────────────────────────────

  void setFader(double db) {
    state = state.copyWith(faderDb: db.clamp(-144.0, 12.0));
    _syncToEngine('fader', state.faderDb);
  }

  void toggleMute() {
    state = state.copyWith(muted: !state.muted);
    _syncToEngine('mute', state.muted);
  }

  void toggleSolo() {
    state = state.copyWith(soloed: !state.soloed);
    _syncToEngine('solo', state.soloed);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INSERT MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  void loadPlugin(InsertPosition position, String pluginId, String pluginName) {
    if (position.isPreFader) {
      final inserts = List<InsertSlotState>.from(state.preFaderInserts);
      final idx = position.index;
      inserts[idx] = inserts[idx].copyWith(
        pluginId: pluginId,
        pluginName: pluginName,
        bypassed: false,
      );
      state = state.copyWith(preFaderInserts: inserts);
    } else {
      final inserts = List<InsertSlotState>.from(state.postFaderInserts);
      final idx = position.index - 5;
      inserts[idx] = inserts[idx].copyWith(
        pluginId: pluginId,
        pluginName: pluginName,
        bypassed: false,
      );
      state = state.copyWith(postFaderInserts: inserts);
    }
    _syncInsertToEngine(position, pluginId);
  }

  void removePlugin(InsertPosition position) {
    if (position.isPreFader) {
      final inserts = List<InsertSlotState>.from(state.preFaderInserts);
      inserts[position.index] = inserts[position.index].clear();
      state = state.copyWith(preFaderInserts: inserts);
    } else {
      final inserts = List<InsertSlotState>.from(state.postFaderInserts);
      inserts[position.index - 5] = inserts[position.index - 5].clear();
      state = state.copyWith(postFaderInserts: inserts);
    }
    _syncInsertToEngine(position, null);
  }

  void toggleBypass(InsertPosition position) {
    if (position.isPreFader) {
      final inserts = List<InsertSlotState>.from(state.preFaderInserts);
      final idx = position.index;
      inserts[idx] = inserts[idx].copyWith(bypassed: !inserts[idx].bypassed);
      state = state.copyWith(preFaderInserts: inserts);
    } else {
      final inserts = List<InsertSlotState>.from(state.postFaderInserts);
      final idx = position.index - 5;
      inserts[idx] = inserts[idx].copyWith(bypassed: !inserts[idx].bypassed);
      state = state.copyWith(postFaderInserts: inserts);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEND MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  void configureSend(int index, int busId, String busName) {
    if (index < 5) {
      final sends = List<SendState>.from(state.preFaderSends);
      sends[index] = sends[index].copyWith(
        destinationBusId: busId,
        destinationName: busName,
      );
      state = state.copyWith(preFaderSends: sends);
    } else {
      final sends = List<SendState>.from(state.postFaderSends);
      sends[index - 5] = sends[index - 5].copyWith(
        destinationBusId: busId,
        destinationName: busName,
      );
      state = state.copyWith(postFaderSends: sends);
    }
  }

  void setSendLevel(int index, double db) {
    if (index < 5) {
      final sends = List<SendState>.from(state.preFaderSends);
      sends[index] = sends[index].copyWith(levelDb: db.clamp(-144.0, 12.0));
      state = state.copyWith(preFaderSends: sends);
    } else {
      final sends = List<SendState>.from(state.postFaderSends);
      sends[index - 5] = sends[index - 5].copyWith(levelDb: db.clamp(-144.0, 12.0));
      state = state.copyWith(postFaderSends: sends);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OUTPUT SECTION
  // ─────────────────────────────────────────────────────────────────────────

  void setPan(double pan) {
    state = state.copyWith(pan: pan.clamp(-1.0, 1.0));
    _syncToEngine('pan', state.pan);
  }

  void setWidth(double width) {
    state = state.copyWith(width: width.clamp(0.0, 2.0));
    _syncToEngine('width', state.width);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // METERING UPDATE (called from Rust via FFI)
  // ─────────────────────────────────────────────────────────────────────────

  void updateMeters(double input, double preFader, double output) {
    state = state.copyWith(
      inputLevel: input,
      preFaderLevel: preFader,
      outputLevel: output,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ENGINE SYNC
  // ─────────────────────────────────────────────────────────────────────────

  void _syncToEngine(String param, dynamic value) {
    EngineApi.setChannelParam(state.trackId, param, value);
  }

  void _syncInsertToEngine(InsertPosition position, String? pluginId) {
    EngineApi.setInsert(state.trackId, position.index, pluginId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final channelStripProvider = StateNotifierProvider.family<
    ChannelStripNotifier, ChannelStripState, int>(
  (ref, trackId) {
    final initial = ChannelStripState.initial(trackId, 'Track $trackId');
    return ChannelStripNotifier(initial);
  },
);
```

---

## 2. UNIFIED TRACK MODEL (REAPER Style)

### 2.1 Problem koji rešava

```
TRADICIONALNI PROBLEM — Previše track tipova:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Pro Tools / Logic / Cubase track tipovi:                       │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 1. Audio Track      — Records audio                        ││
│  │ 2. MIDI Track       — Records MIDI                         ││
│  │ 3. Instrument Track — MIDI + VSTi                          ││
│  │ 4. Aux Track        — Receives signal (returns)            ││
│  │ 5. Bus Track        — Submix destination                   ││
│  │ 6. Group Track      — Folder (no audio)                    ││
│  │ 7. VCA Track        — Control only (no audio)              ││
│  │ 8. Master Track     — Final output                         ││
│  │ 9. Video Track      — Video playback (Pro Tools)           ││
│  │ 10. Folder Track    — Organization (Cubase)                ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Problemi:                                                       │
│  • Mental overhead — koji tip koristiti?                        │
│  • Ograničenja — Audio Track ne može MIDI                       │
│  • Routing confusion — Aux vs Bus vs Group?                     │
│  • Workflow friction — mora se unapred odlučiti                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 REAPER Rešenje — Track = Everything

```
REAPER UNIFIED TRACK MODEL
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  SVAKI TRACK MOŽE SVE:                                          │
│                                                                  │
│  ╔═════════════════════════════════════════════════════════════╗│
│  ║                       REAPER TRACK                          ║│
│  ╠═════════════════════════════════════════════════════════════╣│
│  ║                                                              ║│
│  ║  ┌──────────────────────────────────────────────────────┐   ║│
│  ║  │ RECORDING CAPABILITIES                                │   ║│
│  ║  │ • Audio input → records WAV                          │   ║│
│  ║  │ • MIDI input → records MIDI                          │   ║│
│  ║  │ • BOTH simultaneously → Audio + MIDI items           │   ║│
│  ║  └──────────────────────────────────────────────────────┘   ║│
│  ║                                                              ║│
│  ║  ┌──────────────────────────────────────────────────────┐   ║│
│  ║  │ FX CHAIN (Unlimited slots)                            │   ║│
│  ║  │ • VST/AU/CLAP effects                                │   ║│
│  ║  │ • VSTi instruments (receives MIDI from items)        │   ║│
│  ║  │ • JSFX (realtime scripted)                           │   ║│
│  ║  │ • ReWire                                             │   ║│
│  ║  └──────────────────────────────────────────────────────┘   ║│
│  ║                                                              ║│
│  ║  ┌──────────────────────────────────────────────────────┐   ║│
│  ║  │ ROUTING (128 channels!)                               │   ║│
│  ║  │ • Receive from any track (= Aux behavior)            │   ║│
│  ║  │ • Send to any track (= Bus behavior)                 │   ║│
│  ║  │ • Parent output (= automatic submix)                 │   ║│
│  ║  │ • Hardware output (= Master behavior)                │   ║│
│  ║  └──────────────────────────────────────────────────────┘   ║│
│  ║                                                              ║│
│  ║  ┌──────────────────────────────────────────────────────┐   ║│
│  ║  │ FOLDER BEHAVIOR                                       │   ║│
│  ║  │ • Set as folder parent                               │   ║│
│  ║  │ • Children auto-route to parent                      │   ║│
│  ║  │ • Folder = automatic submix bus                      │   ║│
│  ║  │ • Can still have own items!                          │   ║│
│  ║  └──────────────────────────────────────────────────────┘   ║│
│  ║                                                              ║│
│  ╚═════════════════════════════════════════════════════════════╝│
│                                                                  │
│  REZULTAT:                                                       │
│  • 1 track tip umesto 10                                        │
│  • Fleksibilnost — promeni ponašanje bilo kad                   │
│  • Manje UI clutter — nema "New Aux Track" dialog               │
│  • Power users love it                                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 FluxForge Hybrid Approach

```
FLUXFORGE — BEST OF BOTH WORLDS
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Interno: UNIFIED (kao REAPER)                                  │
│  UI: TYPE HINTS (kao Pro Tools/Logic)                           │
│                                                                  │
│  ╔═════════════════════════════════════════════════════════════╗│
│  ║                   FluxForge Track Model                      ║│
│  ╠═════════════════════════════════════════════════════════════╣│
│  ║                                                              ║│
│  ║  struct Track {                                              ║│
│  ║      id: u32,                                                ║│
│  ║      name: String,                                           ║│
│  ║                                                              ║│
│  ║      // UI hint only — does NOT limit functionality         ║│
│  ║      display_type: TrackDisplayType,                         ║│
│  ║                                                              ║│
│  ║      // Full capabilities — always available                 ║│
│  ║      audio_input: Option<AudioInput>,                        ║│
│  ║      midi_input: Option<MidiInput>,                          ║│
│  ║      fx_chain: Vec<FxSlot>,                                  ║│
│  ║      receives: Vec<Receive>,                                 ║│
│  ║      sends: Vec<Send>,                                       ║│
│  ║      output: TrackOutput,                                    ║│
│  ║      folder_depth: i32,  // Negative = folder parent         ║│
│  ║      channels: u32,      // 1-128                            ║│
│  ║  }                                                           ║│
│  ║                                                              ║│
│  ║  enum TrackDisplayType {                                     ║│
│  ║      Audio,      // Shown with waveform icon                 ║│
│  ║      Instrument, // Shown with keyboard icon                 ║│
│  ║      Aux,        // Shown with return icon                   ║│
│  ║      Bus,        // Shown with bus icon                      ║│
│  ║      Folder,     // Shown with folder icon                   ║│
│  ║      Master,     // Shown with master icon                   ║│
│  ║  }                                                           ║│
│  ║                                                              ║│
│  ╚═════════════════════════════════════════════════════════════╝│
│                                                                  │
│  BENEFITS:                                                       │
│  • Beginners: Familiar track types in UI                        │
│  • Power users: Full REAPER-like flexibility                    │
│  • No limitations: Audio track can receive MIDI                 │
│  • Auto-detect: UI updates based on content                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Rust Implementation

```rust
// crates/rf-engine/src/mixer/track.rs

use std::sync::Arc;
use smallvec::SmallVec;

// ═══════════════════════════════════════════════════════════════════════════
// TRACK DISPLAY TYPE (UI hint only)
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrackDisplayType {
    Audio,
    Instrument,
    Aux,
    Bus,
    Folder,
    Master,
    Video,
}

impl TrackDisplayType {
    /// Auto-detect based on track configuration
    pub fn auto_detect(track: &Track) -> Self {
        // Master: routes to hardware output
        if track.output.is_hardware() && track.folder_depth == 0 {
            return Self::Master;
        }

        // Folder: has children (folder_depth < 0)
        if track.folder_depth < 0 {
            return Self::Folder;
        }

        // Aux: has receives but no items
        if !track.receives.is_empty() && track.items.is_empty() {
            return Self::Aux;
        }

        // Bus: only has sends to it (detected externally)
        // Instrument: has VSTi in FX chain
        if track.has_instrument() {
            return Self::Instrument;
        }

        // Default: Audio
        Self::Audio
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTING
// ═══════════════════════════════════════════════════════════════════════════

/// Receive from another track
#[derive(Clone)]
pub struct Receive {
    /// Source track ID
    pub source_track_id: u32,

    /// Source channel range
    pub source_channels: ChannelRange,

    /// Destination channel range
    pub dest_channels: ChannelRange,

    /// Receive gain
    pub gain_db: f64,

    /// Pan
    pub pan: f64,

    /// Mute
    pub muted: bool,
}

/// Send to another track
#[derive(Clone)]
pub struct Send {
    /// Destination track ID
    pub dest_track_id: u32,

    /// Source channel range
    pub source_channels: ChannelRange,

    /// Destination channel range
    pub dest_channels: ChannelRange,

    /// Send gain
    pub gain_db: f64,

    /// Pan
    pub pan: f64,

    /// Pre or post fader
    pub pre_fader: bool,

    /// Mute
    pub muted: bool,
}

#[derive(Clone, Copy)]
pub struct ChannelRange {
    pub start: u32,
    pub count: u32,
}

impl Default for ChannelRange {
    fn default() -> Self {
        Self { start: 0, count: 2 } // Stereo default
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK OUTPUT
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone)]
pub enum TrackOutput {
    /// Output to parent folder (auto-submix)
    Parent,

    /// Output to specific track
    Track(u32),

    /// Output to hardware
    Hardware {
        device_id: u32,
        channel_offset: u32,
    },

    /// No output (processing only)
    None,
}

impl TrackOutput {
    pub fn is_hardware(&self) -> bool {
        matches!(self, Self::Hardware { .. })
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIFIED TRACK
// ═══════════════════════════════════════════════════════════════════════════

/// Unified track that can do anything (REAPER-style)
pub struct Track {
    // ─────────────────────────────────────────────────────────────────────
    // IDENTITY
    // ─────────────────────────────────────────────────────────────────────
    pub id: u32,
    pub name: String,
    pub color: u32,

    /// UI display type (hint only — does not limit functionality!)
    pub display_type: TrackDisplayType,

    // ─────────────────────────────────────────────────────────────────────
    // INPUT (can have BOTH audio AND midi simultaneously!)
    // ─────────────────────────────────────────────────────────────────────

    /// Audio input configuration
    pub audio_input: Option<AudioInputConfig>,

    /// MIDI input configuration
    pub midi_input: Option<MidiInputConfig>,

    /// Record armed
    pub record_armed: bool,

    /// Record mode (audio, midi, or both)
    pub record_mode: RecordMode,

    /// Input monitoring
    pub input_monitoring: InputMonitoring,

    // ─────────────────────────────────────────────────────────────────────
    // ITEMS (audio AND midi on same track!)
    // ─────────────────────────────────────────────────────────────────────

    /// Media items on this track (audio clips, MIDI clips, video)
    pub items: Vec<MediaItem>,

    // ─────────────────────────────────────────────────────────────────────
    // FX CHAIN (unlimited slots)
    // ─────────────────────────────────────────────────────────────────────

    /// FX chain (VST, AU, CLAP, VSTi, etc.)
    pub fx_chain: Vec<FxSlot>,

    // ─────────────────────────────────────────────────────────────────────
    // ROUTING (128 channels!)
    // ─────────────────────────────────────────────────────────────────────

    /// Number of channels (1-128)
    pub channel_count: u32,

    /// Receives from other tracks (= makes this an Aux)
    pub receives: SmallVec<[Receive; 8]>,

    /// Sends to other tracks (= makes destination a Bus)
    pub sends: SmallVec<[Send; 8]>,

    /// Output destination
    pub output: TrackOutput,

    // ─────────────────────────────────────────────────────────────────────
    // FOLDER STRUCTURE
    // ─────────────────────────────────────────────────────────────────────

    /// Folder depth:
    /// 0 = normal track
    /// -1 = folder parent (1 level)
    /// -2 = folder parent (2 levels)
    /// 1 = child of folder above
    /// 2 = nested child
    pub folder_depth: i32,

    // ─────────────────────────────────────────────────────────────────────
    // MIXER SECTION
    // ─────────────────────────────────────────────────────────────────────

    /// Input trim
    pub input_trim_db: f64,

    /// Phase invert
    pub phase_invert: bool,

    /// Fader position
    pub fader_db: f64,

    /// Pan
    pub pan: f64,

    /// Width
    pub width: f64,

    /// Mute
    pub muted: bool,

    /// Solo
    pub soloed: bool,

    // ─────────────────────────────────────────────────────────────────────
    // AUTOMATION
    // ─────────────────────────────────────────────────────────────────────

    /// Automation envelopes
    pub automation: Vec<AutomationEnvelope>,

    /// Automation mode
    pub automation_mode: AutomationMode,
}

impl Track {
    /// Create new audio track
    pub fn new_audio(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            display_type: TrackDisplayType::Audio,
            audio_input: Some(AudioInputConfig::default()),
            midi_input: None,
            record_mode: RecordMode::Audio,
            ..Self::default_config()
        }
    }

    /// Create new instrument track
    pub fn new_instrument(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            display_type: TrackDisplayType::Instrument,
            audio_input: None,
            midi_input: Some(MidiInputConfig::default()),
            record_mode: RecordMode::Midi,
            ..Self::default_config()
        }
    }

    /// Create new aux/return track
    pub fn new_aux(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            display_type: TrackDisplayType::Aux,
            audio_input: None,
            midi_input: None,
            record_mode: RecordMode::None,
            ..Self::default_config()
        }
    }

    /// Create new bus track
    pub fn new_bus(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            display_type: TrackDisplayType::Bus,
            audio_input: None,
            midi_input: None,
            record_mode: RecordMode::None,
            ..Self::default_config()
        }
    }

    /// Create new folder track
    pub fn new_folder(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            display_type: TrackDisplayType::Folder,
            folder_depth: -1, // Folder parent
            audio_input: None,
            midi_input: None,
            record_mode: RecordMode::None,
            ..Self::default_config()
        }
    }

    /// Create master track
    pub fn new_master(id: u32) -> Self {
        Self {
            id,
            name: "Master".into(),
            display_type: TrackDisplayType::Master,
            output: TrackOutput::Hardware {
                device_id: 0,
                channel_offset: 0,
            },
            audio_input: None,
            midi_input: None,
            record_mode: RecordMode::None,
            ..Self::default_config()
        }
    }

    fn default_config() -> Self {
        Self {
            id: 0,
            name: String::new(),
            color: 0x808080,
            display_type: TrackDisplayType::Audio,
            audio_input: None,
            midi_input: None,
            record_armed: false,
            record_mode: RecordMode::Audio,
            input_monitoring: InputMonitoring::Auto,
            items: Vec::new(),
            fx_chain: Vec::new(),
            channel_count: 2,
            receives: SmallVec::new(),
            sends: SmallVec::new(),
            output: TrackOutput::Parent,
            folder_depth: 0,
            input_trim_db: 0.0,
            phase_invert: false,
            fader_db: 0.0,
            pan: 0.0,
            width: 1.0,
            muted: false,
            soloed: false,
            automation: Vec::new(),
            automation_mode: AutomationMode::Read,
        }
    }

    /// Check if track has VSTi
    pub fn has_instrument(&self) -> bool {
        self.fx_chain.iter().any(|fx| fx.is_instrument())
    }

    /// Check if track is a folder parent
    pub fn is_folder(&self) -> bool {
        self.folder_depth < 0
    }

    /// Get folder nesting level
    pub fn folder_level(&self) -> u32 {
        (-self.folder_depth).max(0) as u32
    }

    /// Add receive from another track
    pub fn add_receive(&mut self, source_track_id: u32) {
        self.receives.push(Receive {
            source_track_id,
            source_channels: ChannelRange::default(),
            dest_channels: ChannelRange::default(),
            gain_db: 0.0,
            pan: 0.0,
            muted: false,
        });

        // Auto-update display type
        if self.items.is_empty() && self.display_type == TrackDisplayType::Audio {
            self.display_type = TrackDisplayType::Aux;
        }
    }

    /// Add send to another track
    pub fn add_send(&mut self, dest_track_id: u32, pre_fader: bool) {
        self.sends.push(Send {
            dest_track_id,
            source_channels: ChannelRange::default(),
            dest_channels: ChannelRange::default(),
            gain_db: -6.0, // Default -6dB
            pan: 0.0,
            pre_fader,
            muted: false,
        });
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum RecordMode {
    #[default]
    None,
    Audio,
    Midi,
    Both,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum InputMonitoring {
    Off,
    On,
    #[default]
    Auto, // On when armed, off when playing back
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum AutomationMode {
    Off,
    #[default]
    Read,
    Touch,
    Latch,
    Write,
}
```

---

## 3. DIRECT ROUTING (Cubase Multi-Destination)

### 3.1 Problem koji rešava

```
TRADICIONALNI PROBLEM — Jedan output destination:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Standardni DAW:                                                 │
│                                                                  │
│  Track → [1 Output] → Bus                                       │
│                                                                  │
│  Problem 1: Stem delivery za film                               │
│  • Morate duplicate tracks za DX, MX, FX stems                 │
│  • Ili bounceovati više puta                                   │
│                                                                  │
│  Problem 2: A/B comparison                                       │
│  • Track → Bus A (sa saturation)                                │
│  • Track → Bus B (bez saturation)                               │
│  • Standardno: mora se toggle routing ručno                    │
│                                                                  │
│  Problem 3: Parallel processing chains                          │
│  • Track → Clean bus                                            │
│  • Track → Crushed bus                                          │
│  • Track → Distorted bus                                        │
│  • Standardno: potrebni sends (koji imaju fader dependency)     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Cubase Direct Routing Rešenje

```
CUBASE DIRECT ROUTING — MULTI-DESTINATION OUTPUT
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Track Output Section:                                           │
│                                                                  │
│  ╔═════════════════════════════════════════════════════════════╗│
│  ║          DIRECT ROUTING SUMMING MODE                        ║│
│  ║      ┌─────────────────────────────────────────────┐        ║│
│  ║      │ [EXCLUSIVE]        [SUMMING]                │        ║│
│  ║      │   ● OFF              ○ OFF                  │        ║│
│  ║      └─────────────────────────────────────────────┘        ║│
│  ╠═════════════════════════════════════════════════════════════╣│
│  ║                                                              ║│
│  ║  DESTINATION SLOTS (8):                                      ║│
│  ║                                                              ║│
│  ║  ┌──────────────────────────────────────────────────────┐   ║│
│  ║  │ [1] ● Master Bus      ← Always active               │   ║│
│  ║  │ [2] ○ Stem: Dialogue  ← Film DX stem               │   ║│
│  ║  │ [3] ○ Stem: Music     ← Film MX stem               │   ║│
│  ║  │ [4] ○ Parallel Comp   ← Parallel chain              │   ║│
│  ║  │ [5] ○ Reverb Bus      ← Effect send                 │   ║│
│  ║  │ [6] ○ A/B Compare A   ← Comparison                  │   ║│
│  ║  │ [7] ○ A/B Compare B   ← Comparison                  │   ║│
│  ║  │ [8] ○ Headphone Cue   ← Artist monitoring           │   ║│
│  ║  └──────────────────────────────────────────────────────┘   ║│
│  ║                                                              ║│
│  ╠═════════════════════════════════════════════════════════════╣│
│  ║                                                              ║│
│  ║  MODES:                                                      ║│
│  ║                                                              ║│
│  ║  EXCLUSIVE MODE:                                             ║│
│  ║  • Only ONE destination active at a time                    ║│
│  ║  • Click = switch to that destination                       ║│
│  ║  • Use case: A/B comparison between buses                   ║│
│  ║                                                              ║│
│  ║  SUMMING MODE:                                               ║│
│  ║  • ALL checked destinations receive signal                  ║│
│  ║  • Click = toggle on/off                                    ║│
│  ║  • Use case: Multi-stem delivery, parallel chains           ║│
│  ║                                                              ║│
│  ╚═════════════════════════════════════════════════════════════╝│
│                                                                  │
│  FILM POST WORKFLOW EXAMPLE:                                     │
│                                                                  │
│  Dialogue Track → Direct Routing (Summing):                      │
│    [1] ● Master Bus        ← Playback/mix                       │
│    [2] ● DX Stem Bus       ← Dialogue stem export               │
│    [3] ○ DX/MX Stem        ← Combined stem                      │
│    [4] ● Broadcast Bus     ← -24 LUFS normalized               │
│                                                                  │
│  Result: Single track → multiple deliverables simultaneously    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 Rust Implementation

```rust
// crates/rf-engine/src/mixer/direct_routing.rs

use smallvec::SmallVec;

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING MODE
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum DirectRoutingMode {
    /// Only one destination active at a time
    Exclusive,

    /// All enabled destinations receive signal
    #[default]
    Summing,
}

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING SLOT
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone)]
pub struct DirectRoutingSlot {
    /// Destination bus/track ID
    pub destination_id: u32,

    /// Destination name (for display)
    pub destination_name: String,

    /// Is this slot enabled
    pub enabled: bool,

    /// Gain for this destination (0.0 = unity, can be used for level matching)
    pub gain_db: f64,

    /// Delay compensation for this destination (samples)
    pub delay_samples: u32,
}

impl DirectRoutingSlot {
    pub fn new(destination_id: u32, name: impl Into<String>) -> Self {
        Self {
            destination_id,
            destination_name: name.into(),
            enabled: false,
            gain_db: 0.0,
            delay_samples: 0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING MATRIX
// ═══════════════════════════════════════════════════════════════════════════

/// Direct routing configuration for a track (up to 8 destinations)
pub struct DirectRouting {
    /// Routing mode
    pub mode: DirectRoutingMode,

    /// Destination slots (max 8)
    pub slots: SmallVec<[DirectRoutingSlot; 8]>,

    /// Currently active slot index (for Exclusive mode)
    active_slot: usize,
}

impl DirectRouting {
    pub fn new() -> Self {
        Self {
            mode: DirectRoutingMode::Summing,
            slots: SmallVec::new(),
            active_slot: 0,
        }
    }

    /// Add a destination slot
    pub fn add_destination(&mut self, dest_id: u32, name: impl Into<String>) -> Option<usize> {
        if self.slots.len() >= 8 {
            return None; // Max 8 destinations
        }

        let slot = DirectRoutingSlot::new(dest_id, name);
        self.slots.push(slot);
        Some(self.slots.len() - 1)
    }

    /// Remove a destination slot
    pub fn remove_destination(&mut self, index: usize) -> bool {
        if index < self.slots.len() {
            self.slots.remove(index);

            // Adjust active slot if needed
            if self.active_slot >= self.slots.len() && !self.slots.is_empty() {
                self.active_slot = self.slots.len() - 1;
            }
            true
        } else {
            false
        }
    }

    /// Toggle slot enabled state
    pub fn toggle_slot(&mut self, index: usize) {
        if index >= self.slots.len() {
            return;
        }

        match self.mode {
            DirectRoutingMode::Exclusive => {
                // Disable all others, enable this one
                for (i, slot) in self.slots.iter_mut().enumerate() {
                    slot.enabled = i == index;
                }
                self.active_slot = index;
            }
            DirectRoutingMode::Summing => {
                // Toggle just this slot
                self.slots[index].enabled = !self.slots[index].enabled;
            }
        }
    }

    /// Set slot enabled state directly
    pub fn set_slot_enabled(&mut self, index: usize, enabled: bool) {
        if index >= self.slots.len() {
            return;
        }

        match self.mode {
            DirectRoutingMode::Exclusive => {
                if enabled {
                    // Disable all others
                    for (i, slot) in self.slots.iter_mut().enumerate() {
                        slot.enabled = i == index;
                    }
                    self.active_slot = index;
                } else {
                    // Can't disable in exclusive mode — one must be active
                    // (unless we're disabling the active one, then pick first)
                    if self.slots[index].enabled && !self.slots.is_empty() {
                        self.slots[index].enabled = false;
                        self.active_slot = 0;
                        self.slots[0].enabled = true;
                    }
                }
            }
            DirectRoutingMode::Summing => {
                self.slots[index].enabled = enabled;
            }
        }
    }

    /// Set routing mode
    pub fn set_mode(&mut self, mode: DirectRoutingMode) {
        if self.mode == mode {
            return;
        }

        self.mode = mode;

        // When switching to exclusive, keep only active slot enabled
        if mode == DirectRoutingMode::Exclusive {
            // Find first enabled slot, or use slot 0
            let first_enabled = self.slots
                .iter()
                .position(|s| s.enabled)
                .unwrap_or(0);

            for (i, slot) in self.slots.iter_mut().enumerate() {
                slot.enabled = i == first_enabled;
            }
            self.active_slot = first_enabled;
        }
    }

    /// Get all enabled destinations
    pub fn enabled_destinations(&self) -> impl Iterator<Item = &DirectRoutingSlot> {
        self.slots.iter().filter(|s| s.enabled)
    }

    /// Get destination IDs for audio routing
    pub fn get_destination_ids(&self) -> SmallVec<[u32; 8]> {
        self.slots
            .iter()
            .filter(|s| s.enabled)
            .map(|s| s.destination_id)
            .collect()
    }

    /// Check if any destination is enabled
    pub fn has_enabled_destination(&self) -> bool {
        self.slots.iter().any(|s| s.enabled)
    }
}

impl Default for DirectRouting {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTEGRATION WITH TRACK
// ═══════════════════════════════════════════════════════════════════════════

impl Track {
    /// Process direct routing outputs
    /// Sends audio to all enabled destinations
    pub fn process_direct_routing(
        &self,
        post_fader_audio: &[&[f64]],
        destination_buffers: &mut DestinationBufferMap,
    ) {
        for slot in self.direct_routing.enabled_destinations() {
            let gain = db_to_linear(slot.gain_db);

            if let Some(buffer) = destination_buffers.get_mut(slot.destination_id) {
                let num_channels = post_fader_audio.len().min(buffer.len());
                let num_samples = post_fader_audio[0].len();

                for ch in 0..num_channels {
                    for i in 0..num_samples {
                        buffer[ch][i] += post_fader_audio[ch][i] * gain;
                    }
                }
            }
        }
    }
}
```

### 3.4 Flutter UI Implementation

```dart
// flutter_ui/lib/widgets/mixer/direct_routing_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING MODE
// ═══════════════════════════════════════════════════════════════════════════

enum DirectRoutingMode {
  exclusive,
  summing,
}

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING SLOT STATE
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class DirectRoutingSlotState {
  final int index;
  final int? destinationId;
  final String? destinationName;
  final bool enabled;
  final double gainDb;

  const DirectRoutingSlotState({
    required this.index,
    this.destinationId,
    this.destinationName,
    this.enabled = false,
    this.gainDb = 0.0,
  });

  bool get isEmpty => destinationId == null;

  DirectRoutingSlotState copyWith({
    int? destinationId,
    String? destinationName,
    bool? enabled,
    double? gainDb,
  }) {
    return DirectRoutingSlotState(
      index: index,
      destinationId: destinationId ?? this.destinationId,
      destinationName: destinationName ?? this.destinationName,
      enabled: enabled ?? this.enabled,
      gainDb: gainDb ?? this.gainDb,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING STATE
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class DirectRoutingState {
  final int trackId;
  final DirectRoutingMode mode;
  final List<DirectRoutingSlotState> slots;

  const DirectRoutingState({
    required this.trackId,
    this.mode = DirectRoutingMode.summing,
    required this.slots,
  });

  factory DirectRoutingState.initial(int trackId) {
    return DirectRoutingState(
      trackId: trackId,
      slots: List.generate(
        8,
        (i) => DirectRoutingSlotState(index: i),
      ),
    );
  }

  DirectRoutingState copyWith({
    DirectRoutingMode? mode,
    List<DirectRoutingSlotState>? slots,
  }) {
    return DirectRoutingState(
      trackId: trackId,
      mode: mode ?? this.mode,
      slots: slots ?? this.slots,
    );
  }

  int get enabledCount => slots.where((s) => s.enabled).length;
}

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════

class DirectRoutingNotifier extends StateNotifier<DirectRoutingState> {
  DirectRoutingNotifier(DirectRoutingState initial) : super(initial);

  void setMode(DirectRoutingMode mode) {
    if (state.mode == mode) return;

    var slots = List<DirectRoutingSlotState>.from(state.slots);

    if (mode == DirectRoutingMode.exclusive) {
      // Keep only first enabled slot
      final firstEnabled = slots.indexWhere((s) => s.enabled);
      for (var i = 0; i < slots.length; i++) {
        slots[i] = slots[i].copyWith(enabled: i == firstEnabled);
      }
    }

    state = state.copyWith(mode: mode, slots: slots);
  }

  void toggleSlot(int index) {
    if (index < 0 || index >= state.slots.length) return;

    var slots = List<DirectRoutingSlotState>.from(state.slots);

    switch (state.mode) {
      case DirectRoutingMode.exclusive:
        // Enable only this slot
        for (var i = 0; i < slots.length; i++) {
          slots[i] = slots[i].copyWith(enabled: i == index);
        }
        break;

      case DirectRoutingMode.summing:
        // Toggle this slot
        slots[index] = slots[index].copyWith(enabled: !slots[index].enabled);
        break;
    }

    state = state.copyWith(slots: slots);
    _syncToEngine();
  }

  void setDestination(int slotIndex, int destId, String destName) {
    if (slotIndex < 0 || slotIndex >= state.slots.length) return;

    var slots = List<DirectRoutingSlotState>.from(state.slots);
    slots[slotIndex] = slots[slotIndex].copyWith(
      destinationId: destId,
      destinationName: destName,
    );

    state = state.copyWith(slots: slots);
    _syncToEngine();
  }

  void setSlotGain(int slotIndex, double gainDb) {
    if (slotIndex < 0 || slotIndex >= state.slots.length) return;

    var slots = List<DirectRoutingSlotState>.from(state.slots);
    slots[slotIndex] = slots[slotIndex].copyWith(gainDb: gainDb);

    state = state.copyWith(slots: slots);
    _syncToEngine();
  }

  void _syncToEngine() {
    // Sync enabled destinations to Rust engine
    final enabled = state.slots
        .where((s) => s.enabled && s.destinationId != null)
        .map((s) => s.destinationId!)
        .toList();

    EngineApi.setDirectRouting(state.trackId, enabled);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT ROUTING PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class DirectRoutingPanel extends ConsumerWidget {
  final int trackId;

  const DirectRoutingPanel({
    super.key,
    required this.trackId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(directRoutingProvider(trackId));
    final notifier = ref.read(directRoutingProvider(trackId).notifier);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with mode toggle
          Row(
            children: [
              const Text(
                'DIRECT ROUTING',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF808090),
                ),
              ),
              const Spacer(),
              _ModeToggle(
                mode: state.mode,
                onChanged: notifier.setMode,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Destination slots
          ...state.slots.asMap().entries.map((entry) {
            return _DestinationSlot(
              slot: entry.value,
              mode: state.mode,
              onToggle: () => notifier.toggleSlot(entry.key),
              onDestinationTap: () => _showDestinationPicker(
                context,
                entry.key,
                notifier,
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showDestinationPicker(
    BuildContext context,
    int slotIndex,
    DirectRoutingNotifier notifier,
  ) {
    // Show bus/destination picker dialog
    showDialog(
      context: context,
      builder: (context) => DestinationPickerDialog(
        onSelected: (id, name) {
          notifier.setDestination(slotIndex, id, name);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODE TOGGLE
// ═══════════════════════════════════════════════════════════════════════════

class _ModeToggle extends StatelessWidget {
  final DirectRoutingMode mode;
  final ValueChanged<DirectRoutingMode> onChanged;

  const _ModeToggle({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeButton(
          label: 'EXCL',
          selected: mode == DirectRoutingMode.exclusive,
          onTap: () => onChanged(DirectRoutingMode.exclusive),
        ),
        const SizedBox(width: 4),
        _ModeButton(
          label: 'SUM',
          selected: mode == DirectRoutingMode.summing,
          onTap: () => onChanged(DirectRoutingMode.summing),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A9EFF) : const Color(0xFF242430),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : const Color(0xFF808090),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DESTINATION SLOT
// ═══════════════════════════════════════════════════════════════════════════

class _DestinationSlot extends StatelessWidget {
  final DirectRoutingSlotState slot;
  final DirectRoutingMode mode;
  final VoidCallback onToggle;
  final VoidCallback onDestinationTap;

  const _DestinationSlot({
    required this.slot,
    required this.mode,
    required this.onToggle,
    required this.onDestinationTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = slot.isEmpty;
    final isEnabled = slot.enabled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          // Slot number
          SizedBox(
            width: 16,
            child: Text(
              '${slot.index + 1}',
              style: TextStyle(
                fontSize: 10,
                color: isEnabled
                    ? const Color(0xFF4A9EFF)
                    : const Color(0xFF606070),
              ),
            ),
          ),

          // Enable button (radio for exclusive, checkbox for summing)
          GestureDetector(
            onTap: isEmpty ? null : onToggle,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: mode == DirectRoutingMode.exclusive
                    ? BoxShape.circle
                    : BoxShape.rectangle,
                borderRadius: mode == DirectRoutingMode.summing
                    ? BorderRadius.circular(2)
                    : null,
                border: Border.all(
                  color: isEmpty
                      ? const Color(0xFF404050)
                      : const Color(0xFF4A9EFF),
                ),
                color: isEnabled
                    ? const Color(0xFF4A9EFF)
                    : Colors.transparent,
              ),
              child: isEnabled
                  ? const Icon(
                      Icons.check,
                      size: 10,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),

          const SizedBox(width: 8),

          // Destination name
          Expanded(
            child: GestureDetector(
              onTap: onDestinationTap,
              child: Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF242430),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  slot.destinationName ?? '- No Output -',
                  style: TextStyle(
                    fontSize: 10,
                    color: isEmpty
                        ? const Color(0xFF606070)
                        : const Color(0xFFE0E0E0),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final directRoutingProvider = StateNotifierProvider.family<
    DirectRoutingNotifier, DirectRoutingState, int>(
  (ref, trackId) {
    return DirectRoutingNotifier(DirectRoutingState.initial(trackId));
  },
);
```

---

## 4. SUMMARY — FluxForge Mixer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│           FLUXFORGE MIXER — COMBINED BEST PRACTICES             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FROM PRO TOOLS:                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ✓ 10 Insert Slots (5 Pre + 5 Post Fader)                    ││
│  │ ✓ 10 Send Slots (5 Pre + 5 Post Fader)                      ││
│  │ ✓ Clip Gain (per-region, pre-everything)                    ││
│  │ ✓ Clear signal flow (Input → Pre → Fader → Post → Out)     ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  FROM REAPER:                                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ✓ Unified Track Model (one type does everything)           ││
│  │ ✓ 128-channel track capability                              ││
│  │ ✓ Unlimited receives (any track can be aux)                 ││
│  │ ✓ Folder = automatic submix                                 ││
│  │ ✓ Flexible routing matrix                                   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  FROM CUBASE:                                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ✓ Direct Routing (8 simultaneous destinations)             ││
│  │ ✓ Exclusive/Summing modes                                   ││
│  │ ✓ Per-slot gain control                                     ││
│  │ ✓ A/B comparison routing                                    ││
│  │ ✓ Multi-stem delivery workflow                              ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  FLUXFORGE UNIQUE:                                               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ✓ Hybrid track model (unified + UI type hints)             ││
│  │ ✓ Auto-detect track type based on configuration            ││
│  │ ✓ Lock-free audio processing                                ││
│  │ ✓ SIMD-optimized mixing                                     ││
│  │ ✓ 64-bit double precision throughout                        ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0
**Date:** January 2026
**Sources:**
- Pro Tools 2024 Insert Architecture
- REAPER 7 Unified Track Model
- Cubase Pro 14 Direct Routing
- FluxForge rf-engine existing implementation
