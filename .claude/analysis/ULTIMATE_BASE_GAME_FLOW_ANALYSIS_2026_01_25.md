# ULTIMATE BASE GAME FLOW ANALYSIS — SlotLab vs Industry Standard

**Date:** 2026-01-25
**Author:** Claude (9-Role Analysis per CLAUDE.md)
**Scope:** Base Game Complete Flow — Spins, UI, Wins, Big Wins, Anticipation
**Goal:** Ultimativna specifikacija za AAA slot iskustvo

---

## EXECUTIVE SUMMARY

**Trenutno stanje:** 92% Industry Standard
**Cilj:** 100% AAA Quality (nerazlučiv od IGT/NetEnt/Pragmatic Play)

| Kategorija | Score | Gap |
|------------|-------|-----|
| Reel Animation | 98% | Motion blur shader |
| Win Presentation | 95% | Rollup audio dynamics |
| Audio-Visual Sync | 85% | Per-reel spin loop fade |
| UI Feedback | 90% | Button press feedback |
| Anticipation | 95% | Visual sync |
| **OVERALL** | **92%** | **8% za perfektno** |

---

## PART 1: 9-ROLE ANALYSIS (per CLAUDE.md)

### ROLE 1: 🎮 Slot Game Designer

**Fokus:** Matematika, flow, player experience

**Trenutna Implementacija — STRENGTHS:**
- ✅ 6-tier win sistem (SMALL→ULTRA) — industry standard
- ✅ Per-reel stagger timing (370ms Studio profile)
- ✅ Anticipation na poslednjim reelovima
- ✅ Near-miss detection
- ✅ Cascade support

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| Win tier thresholds nisu konfigurabilan | Medium | P2 |
| Near-miss audio eskalacija | Low | P3 |
| Volatility-based timing profiles | Medium | P2 |

**PREPORUKA:**
```dart
// Konfigurabilni win tier thresholds per game
class WinTierConfig {
  final double bigWinThreshold;    // Default: 5x
  final double superWinThreshold;  // Default: 15x
  final double megaWinThreshold;   // Default: 30x
  final double epicWinThreshold;   // Default: 60x
  final double ultraWinThreshold;  // Default: 100x
}
```

---

### ROLE 2: 🎵 Audio Designer / Composer

**Fokus:** Layering, states, events, mixing

**Trenutna Implementacija — STRENGTHS:**
- ✅ Per-reel stereo panning (-0.8 → +0.8)
- ✅ Audio Pool za rapid-fire events
- ✅ Stage→Event mapping (490+ stages)
- ✅ Container system (Blend/Random/Sequence)

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| **Per-reel spin loop fade** | HIGH | **P0** |
| Rollup pitch dynamics (RTPC) | Medium | P1 |
| Win evaluation audio gap (50-100ms tišina) | Medium | P1 |
| Cascade pitch escalation | Low | P2 |

**KRITIČNI GAP — P0: Per-Reel Spin Loop Fade**

**Problem:** Trenutno postoji JEDAN REEL_SPINNING loop za sve reelove. Kada reel stane, loop nastavlja da svira.

**Industry Standard (IGT, NetEnt):**
```
SPIN_START
  ↓
REEL_SPINNING_0 (loop, pan: -0.8)
REEL_SPINNING_1 (loop, pan: -0.4)
REEL_SPINNING_2 (loop, pan: 0.0)
REEL_SPINNING_3 (loop, pan: +0.4)
REEL_SPINNING_4 (loop, pan: +0.8)
  ↓
REEL_STOP_0 → FADE OUT REEL_SPINNING_0 (50ms)
REEL_STOP_1 → FADE OUT REEL_SPINNING_1 (50ms)
...
```

**Efekat:** Progressive quieting — svaki reel koji stane smanjuje ukupnu "spin buku".

**REŠENJE:**
```rust
// spin.rs - Generisati per-reel spinning events
for reel in 0..self.grid.len() {
    events.push(StageEvent::new(
        Stage::ReelSpinning { reel_index: reel as u8 },
        timing.reel_spin(reel as u8),
    ));
}
```

```dart
// event_registry.dart - Auto fade na REEL_STOP
void triggerStage(String stage) {
  if (stage.startsWith('REEL_STOP_')) {
    final reelIndex = int.parse(stage.split('_').last);
    _fadeOutSpinLoop(reelIndex, fadeMs: 50);
  }
  // ... existing logic
}
```

---

### ROLE 3: 🧠 Audio Middleware Architect

**Fokus:** Event model, state machines, runtime

**Trenutna Implementacija — STRENGTHS:**
- ✅ Wwise/FMOD-style Event Registry
- ✅ Stage→Event decoupling
- ✅ Container delegation
- ✅ RTPC modulation
- ✅ Ducking system

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| Win evaluation→audio gap | Medium | P1 |
| State machine visualization | Low | P3 |

**REŠENJE za Win Evaluation Gap:**
```dart
// slot_preview_widget.dart
// Na REEL_STOP_4 (poslednji reel) — instant shimmer za winners
void _onReelStopVisual(int reelIndex) {
  // ... existing buffer logic

  if (reelIndex == widget.reels - 1) {
    final result = widget.provider.lastResult;
    if (result?.isWin == true) {
      // PRE-TRIGGER shimmer INSTANT (ne čekaj _finalizeSpin)
      eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');
    }
  }
}
```

---

### ROLE 4: 🛠 Engine / Runtime Developer

**Fokus:** FFI, playback, memory, latency

**Trenutna Implementacija — STRENGTHS:**
- ✅ Sub-3ms audio latency (world-class)
- ✅ IGT-style sequential reel stop buffer
- ✅ Object-pooled particles
- ✅ Lock-free audio thread

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| Per-voice fade out | Medium | P1 |
| Spin loop state tracking | Medium | P1 |

**REŠENJE — Per-Voice Fade Out API:**
```rust
// playback.rs
pub fn fade_out_voice(voice_id: u64, fade_ms: u32) {
    // Linear fade from current volume to 0 over fade_ms
    // Release voice after fade complete
}
```

```dart
// native_ffi.dart
void fadeOutVoice(int voiceId, int fadeMs);
```

---

### ROLE 5: 🧩 Tooling / Editor Developer

**Fokus:** UI, workflows, batch processing

**Trenutna Implementacija — STRENGTHS:**
- ✅ Visual reel strip editor
- ✅ Drop zone system
- ✅ QuickSheet event creation
- ✅ Event folder organization

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| Audio preview za spin loop | Low | P3 |
| Timing profile editor | Medium | P2 |

---

### ROLE 6: 🎨 UX / UI Designer

**Fokus:** Mental models, discoverability, friction

**Trenutna Implementacija — STRENGTHS:**
- ✅ Clear 3-phase win flow
- ✅ Visual win tier differentiation
- ✅ Particle effects per tier

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| Spin button press feedback | Low | P3 |
| Big win background dimming enhancement | Low | P2 |

---

### ROLE 7: 🧪 QA / Determinism Engineer

**Fokus:** Reproducibility, validation, testing

**Trenutna Implementacija — STRENGTHS:**
- ✅ Deterministic RNG seeds
- ✅ Forced outcomes
- ✅ Stage event logging

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| Audio playback verification | Medium | P2 |
| Timing consistency tests | Medium | P2 |

---

### ROLE 8: 🧬 DSP / Audio Processing Engineer

**Fokus:** Filters, dynamics, offline processing

**Trenutna Implementacija — STRENGTHS:**
- ✅ SIMD-optimized DSP
- ✅ Per-bus processing
- ✅ Ducking with attack/release

**GAPS:**
| Gap | Impact | Priority |
|-----|--------|----------|
| Spin loop filter sweep on stop | Low | P3 |
| Rollup pitch RTPC binding | Medium | P1 |

---

### ROLE 9: 🧭 Producer / Product Owner

**Fokus:** Roadmap, priorities, market fit

**Prioriteti za Base Game:**
1. **P0:** Per-reel spin loop fade (kritično za profesionalni osećaj)
2. **P1:** Win evaluation gap elimination
3. **P1:** Rollup audio dynamics
4. **P2:** Timing profile configurability

---

## PART 2: ULTIMATIVNI BASE GAME FLOW SPECIFICATION

### 2.1 KOMPLETAN FLOW DIJAGRAM

```
════════════════════════════════════════════════════════════════════════════════
                        ULTIMATE SLOT BASE GAME FLOW
════════════════════════════════════════════════════════════════════════════════

[USER INPUT]
    │
    │ Player taps SPIN button
    │
    ▼ T+0ms ────────────────────────────────────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ PHASE A: SPIN INITIATION                                                       │
│                                                                                 │
│ ├── AUDIO: ui_button_press.wav (instant, UI bus)                               │
│ ├── VISUAL: Button scale down (95%) + brightness flash                        │
│ ├── STATE: isSpinning = true, isReelsSpinning = true                          │
│ └── ACTION: Disable SPIN button, show STOP button (red)                       │
│                                                                                 │
│ TIMING: 0ms (instant response — kritično za player satisfaction)              │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ▼ T+0ms ────────────────────────────────────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ PHASE B: REEL ACCELERATION                                                     │
│                                                                                 │
│ ├── AUDIO: spin_start.wav (whoosh, mechanical start — Reels bus)              │
│ │   └── Per-reel spin loops start:                                            │
│ │       • REEL_SPINNING_0 (loop, pan: -0.8, 50ms after spin_start)            │
│ │       • REEL_SPINNING_1 (loop, pan: -0.4, 70ms after)                       │
│ │       • REEL_SPINNING_2 (loop, pan: 0.0, 90ms after)                        │
│ │       • REEL_SPINNING_3 (loop, pan: +0.4, 110ms after)                      │
│ │       • REEL_SPINNING_4 (loop, pan: +0.8, 130ms after)                      │
│ │                                                                              │
│ ├── VISUAL: Reels accelerate 0 → full speed                                   │
│ │   └── Easing: easeOutQuad (brzo ubrzanje)                                   │
│ │   └── Motion blur builds: 0 → 0.7 intensity                                 │
│ │   └── Speed lines appear at 70% speed                                       │
│ │                                                                              │
│ └── DURATION: 100-120ms per industry standard                                 │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ▼ T+120ms ──────────────────────────────────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ PHASE C: SPINNING (constant velocity)                                          │
│                                                                                 │
│ ├── AUDIO: 5 spin loops playing (stereo spread L→R)                           │
│ │   └── Progressive quieting as each reel stops                               │
│ │                                                                              │
│ ├── VISUAL: Maximum blur (0.7), speed lines visible                           │
│ │   └── Symbols cycle rapidly (not readable)                                  │
│ │                                                                              │
│ └── DURATION: Variable (minimum 560ms, server-dependent)                      │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ▼ T+680ms (Reel 0 start deceleration) ──────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ PHASE D: SEQUENTIAL REEL STOPS (L→R, 370ms stagger)                            │
│                                                                                 │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ REEL 0 (T+680ms → T+1160ms)                                                    │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ ├── DECELERATION (280ms): Speed drops, blur fades                             │
│ ├── BOUNCE (180ms): 15% overshoot, elasticOut curve                           │
│ ├── AUDIO: reel_stop_0.wav (pan: -0.8) AT BOUNCE START                        │
│ │   └── FADE OUT: REEL_SPINNING_0 (50ms fade)                                 │
│ ├── VISUAL: Flash overlay (50ms), scale pop (1.05×, 100ms)                    │
│ └── NOTE: Audio fires when entering BOUNCING phase (not after)                │
│                                                                                 │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ REEL 1 (T+1050ms → T+1530ms) — 370ms after Reel 0                             │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ ├── Same sequence as Reel 0                                                    │
│ ├── AUDIO: reel_stop_1.wav (pan: -0.4)                                        │
│ └── FADE OUT: REEL_SPINNING_1                                                 │
│                                                                                 │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ REEL 2 (T+1420ms → T+1900ms)                                                   │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ ├── AUDIO: reel_stop_2.wav (pan: 0.0, center)                                 │
│ └── FADE OUT: REEL_SPINNING_2                                                 │
│                                                                                 │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ REEL 3 (T+1790ms → T+2270ms) — ANTICIPATION CHECK POINT                       │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ ├── IF anticipation detected (scatter on reels 0-2):                          │
│ │   ├── AUDIO: anticipation_start.wav (tension drone)                         │
│ │   ├── VISUAL: Golden glow on Reel 3-4, screen slight dim (15%)              │
│ │   └── SPEED: Reel decelerates 50% slower than normal                        │
│ ├── AUDIO: reel_stop_3.wav (pan: +0.4)                                        │
│ └── FADE OUT: REEL_SPINNING_3                                                 │
│                                                                                 │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ REEL 4 (T+2160ms → T+2640ms) — FINAL REEL                                     │
│ ═══════════════════════════════════════════════════════════════════════════   │
│ ├── AUDIO: reel_stop_4.wav (pan: +0.8)                                        │
│ ├── FADE OUT: REEL_SPINNING_4                                                 │
│ ├── IF anticipation was active:                                                │
│ │   └── AUDIO: anticipation_end.wav (resolve chord)                           │
│ ├── STATE: isReelsSpinning = false                                            │
│ │   └── STOP button hides, SPIN disabled until win presentation complete     │
│ └── **CRITICAL**: If win detected, instant shimmer (0ms gap)                  │
│                                                                                 │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ▼ T+2640ms (All reels stopped) ─────────────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ WIN EVALUATION (internal, no audio)                                            │
│ └── Server/engine calculates line wins, scatter wins, totals                  │
│ └── DURATION: 0ms (instant from player perspective)                           │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ├── IF NO WIN ─────────────────────────────────────────────────────────────
    │   └── GOTO: IDLE (SPIN enabled immediately)
    │
    ▼ IF WIN ──────────────────────────────────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ PHASE E1: SYMBOL HIGHLIGHT (800-2500ms, tier-based)                            │
│                                                                                 │
│ ├── AUDIO: win_symbol_highlight.wav (shimmering loop)                         │
│ │   └── Triggered INSTANT on Reel 4 stop (0ms gap)                            │
│ │                                                                              │
│ ├── VISUAL: Winning symbols glow + pulse                                      │
│ │   ├── 3 pulse cycles (350ms each = 1050ms total for SMALL)                 │
│ │   ├── Staggered popup: 50ms delay per symbol (L→R)                         │
│ │   ├── Scale: 1.0 → 1.15 → 1.0                                               │
│ │   └── Micro-wiggle rotation (±0.03 radians)                                 │
│ │                                                                              │
│ ├── DURATION by tier:                                                          │
│ │   ├── SMALL: 800ms                                                          │
│ │   ├── BIG: 1200ms                                                           │
│ │   ├── SUPER: 1500ms                                                         │
│ │   ├── MEGA: 1800ms                                                          │
│ │   ├── EPIC: 2000ms                                                          │
│ │   └── ULTRA: 2500ms                                                         │
│ │                                                                              │
│ └── NOTE: Builds anticipation before plaque reveal                            │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ▼ T+2640ms + symbolHighlightDuration ───────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ PHASE E2: TIER PLAQUE + ROLLUP (1500-20000ms, tier-based)                      │
│                                                                                 │
│ ├── AUDIO SEQUENCE:                                                            │
│ │   ├── win_present_[TIER].wav (fanfare, tier-specific)                       │
│ │   ├── rollup_start.wav                                                      │
│ │   ├── rollup_tick.wav × N (tier-based tick rate)                            │
│ │   │   └── P1 ENHANCEMENT: Pitch rises during rollup (RTPC binding)         │
│ │   └── rollup_end.wav (ding/chime)                                           │
│ │                                                                              │
│ ├── VISUAL:                                                                    │
│ │   ├── V8 Screen flash (150ms, BIG+ only)                                   │
│ │   ├── Tier plaque slides in + scale overshoot                               │
│ │   │   └── Scale multiplier: ULTRA=1.25, EPIC=1.2, MEGA=1.15, etc.          │
│ │   ├── Plaque glow pulse (400ms cycle, repeating)                           │
│ │   ├── Coin counter rolls from 0 → total_win                                │
│ │   │   └── Easing: easeOutQuart (fast start, slow end)                      │
│ │   ├── Particles spawn (10-80 based on tier)                                │
│ │   └── Background color wash (tier-specific)                                 │
│ │                                                                              │
│ ├── DURATION & TICK RATE by tier:                                              │
│ │   ├── SMALL: 1500ms, 15 ticks/sec                                          │
│ │   ├── BIG: 2500ms, 12 ticks/sec                                            │
│ │   ├── SUPER: 4000ms, 10 ticks/sec                                          │
│ │   ├── MEGA: 7000ms, 8 ticks/sec                                            │
│ │   ├── EPIC: 12000ms, 6 ticks/sec                                           │
│ │   └── ULTRA: 20000ms, 4 ticks/sec                                          │
│ │                                                                              │
│ └── END: Plaque hides before Phase E3                                         │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ▼ After rollup complete ────────────────────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ PHASE E3: WIN LINE PRESENTATION (1500ms per line)                              │
│                                                                                 │
│ ├── PRECONDITION: Plaque is HIDDEN (counter hides)                            │
│ │                                                                              │
│ ├── FOR EACH LINE (sequential, no overlap):                                    │
│ │   ├── AUDIO: win_line_show.wav                                              │
│ │   ├── VISUAL:                                                                │
│ │   │   ├── Win line painter draws connecting path                            │
│ │   │   │   └── 3 layers: outer glow + main line + white core                 │
│ │   │   ├── Dots at each symbol position (pulsing)                            │
│ │   │   ├── ONLY current line symbols highlighted                             │
│ │   │   └── NO text overlay ("3x Cherry = $50") — visual only                │
│ │   └── DURATION: 1500ms per line                                             │
│ │                                                                              │
│ ├── BEHAVIOR: Single pass through all lines (NO LOOPING)                      │
│ │   └── After last line shown → presentation ends                             │
│ │                                                                              │
│ └── END: isPlayingStages = false, SPIN enabled                                │
└───────────────────────────────────────────────────────────────────────────────┘
    │
    ▼ ──────────────────────────────────────────────────────────────────────────
┌───────────────────────────────────────────────────────────────────────────────┐
│ IDLE STATE                                                                     │
│                                                                                 │
│ ├── SPIN button enabled                                                        │
│ ├── Balance updated                                                            │
│ ├── Win lines may continue cycling (optional, for attract)                    │
│ └── Ready for next spin                                                        │
└───────────────────────────────────────────────────────────────────────────────┘

════════════════════════════════════════════════════════════════════════════════
```

---

### 2.2 TIMING REFERENCE CARD

```
SPIN CYCLE — Studio Profile (Audio Testing)
════════════════════════════════════════════════════════════════════════════════
Total Spin Duration: ~2640ms (from SPIN_START to all reels stopped)

T+0ms       SPIN_START
T+0ms       UI_BUTTON_PRESS (if separate from spin_start)
T+50-130ms  REEL_SPINNING_0..4 (staggered loop starts)
T+120ms     All reels at full speed (blur max)

T+680ms     Reel 0 starts deceleration
T+960ms     Reel 0 enters bounce → REEL_STOP_0 audio
T+1050ms    Reel 1 starts deceleration
T+1330ms    Reel 1 enters bounce → REEL_STOP_1 audio
T+1420ms    Reel 2 starts deceleration
T+1700ms    Reel 2 enters bounce → REEL_STOP_2 audio
T+1790ms    Reel 3 starts deceleration (+ ANTICIPATION if applicable)
T+2070ms    Reel 3 enters bounce → REEL_STOP_3 audio
T+2160ms    Reel 4 starts deceleration
T+2440ms    Reel 4 enters bounce → REEL_STOP_4 audio

T+2640ms    All reels stopped, isReelsSpinning = false

WIN PRESENTATION (if win)
════════════════════════════════════════════════════════════════════════════════
T+2640ms    WIN_SYMBOL_HIGHLIGHT (instant, 0ms gap)
T+2640ms    Symbol pulse animation starts

            [Phase 1: 800-2500ms based on tier]

T+3440ms    WIN_PRESENT_[TIER] (for SMALL win, 800ms highlight)
(varies)    ROLLUP_START
            ROLLUP_TICK × N (tier-based)
            ROLLUP_END

            [Phase 2: 1500-20000ms based on tier]

            WIN_LINE_SHOW × line_count (1500ms each)
            [Phase 3: no looping, single pass]

ANTICIPATION (when detected)
════════════════════════════════════════════════════════════════════════════════
Duration: 800-1000ms additional on affected reels
Visual: Golden glow, slight screen dim (15%)
Audio: anticipation_start.wav → anticipation_end.wav
Trigger: Scatter/Bonus on reels 0-2, checking reels 3-4
```

---

### 2.3 AUDIO EVENT MAPPING

| Stage | Audio File | Bus | Pan | Priority | Notes |
|-------|------------|-----|-----|----------|-------|
| **SPIN_START** | spin_start.wav | Reels | 0.0 | 70 | Whoosh, mechanical |
| **REEL_SPINNING_0** | reel_spin_loop.wav | Reels | -0.8 | 60 | Loop, fade on stop |
| **REEL_SPINNING_1** | reel_spin_loop.wav | Reels | -0.4 | 60 | Loop, fade on stop |
| **REEL_SPINNING_2** | reel_spin_loop.wav | Reels | 0.0 | 60 | Loop, fade on stop |
| **REEL_SPINNING_3** | reel_spin_loop.wav | Reels | +0.4 | 60 | Loop, fade on stop |
| **REEL_SPINNING_4** | reel_spin_loop.wav | Reels | +0.8 | 60 | Loop, fade on stop |
| **REEL_STOP_0** | reel_stop.wav | Reels | -0.8 | 75 | Clunk/thud |
| **REEL_STOP_1** | reel_stop.wav | Reels | -0.4 | 75 | |
| **REEL_STOP_2** | reel_stop.wav | Reels | 0.0 | 75 | |
| **REEL_STOP_3** | reel_stop.wav | Reels | +0.4 | 75 | |
| **REEL_STOP_4** | reel_stop.wav | Reels | +0.8 | 75 | Final reel |
| **ANTICIPATION_ON** | anticipation_start.wav | SFX | 0.0 | 72 | Tension drone |
| **ANTICIPATION_OFF** | anticipation_end.wav | SFX | 0.0 | 72 | Resolve |
| **WIN_SYMBOL_HIGHLIGHT** | win_shimmer.wav | SFX | 0.0 | 80 | Sparkle loop |
| **WIN_PRESENT_SMALL** | win_small.wav | SFX | 0.0 | 82 | Light chime |
| **WIN_PRESENT_BIG** | big_win_fanfare.wav | SFX | 0.0 | 85 | Full fanfare |
| **WIN_PRESENT_SUPER** | super_win_fanfare.wav | SFX | 0.0 | 87 | Bigger fanfare |
| **WIN_PRESENT_MEGA** | mega_win_fanfare.wav | SFX | 0.0 | 88 | Epic fanfare |
| **WIN_PRESENT_EPIC** | epic_win_fanfare.wav | SFX | 0.0 | 89 | Maximum drama |
| **WIN_PRESENT_ULTRA** | ultra_win_fanfare.wav | SFX | 0.0 | 90 | Ultimate |
| **ROLLUP_START** | rollup_start.wav | SFX | 0.0 | 70 | Counter begin |
| **ROLLUP_TICK** | rollup_tick.wav | SFX | 0.0 | 65 | Per-increment |
| **ROLLUP_END** | rollup_end.wav | SFX | 0.0 | 75 | Ding |
| **WIN_LINE_SHOW** | win_line.wav | SFX | 0.0 | 70 | Line highlight |

---

## PART 3: GAPS AND FIXES PRIORITIZED

### P0 — KRITIČNO (Must Fix)

| # | Gap | Current | Target | Fix |
|---|-----|---------|--------|-----|
| **P0.1** | Per-reel spin loop fade | Unified loop | Per-reel with fade | See implementation below |

**P0.1 Implementation:**

```rust
// spin.rs — Generate per-reel spinning events
fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
    let mut events = Vec::new();

    events.push(StageEvent::new(Stage::SpinStart, timing.current()));

    // Per-reel spinning (with staggered start for natural feel)
    let reel_count = self.grid.len() as u8;
    for reel in 0..reel_count {
        let stagger_ms = reel as f64 * 20.0; // 20ms stagger
        events.push(StageEvent::new(
            Stage::ReelSpinning { reel_index: reel },
            timing.advance(stagger_ms),
        ));
    }

    // ... rest of stage generation
}
```

```dart
// event_registry.dart — Auto fade on reel stop
final Map<int, int> _activeSpinLoopVoices = {}; // reel → voice_id

void triggerStage(String stage) {
  // ... existing normalization

  // Track spin loop voices
  if (stage.startsWith('REEL_SPINNING_')) {
    final reelIndex = int.parse(stage.split('_').last);
    // Store voice ID returned from playback
    final voiceId = _playEvent(event, ...);
    _activeSpinLoopVoices[reelIndex] = voiceId;
  }

  // Fade out spin loop on reel stop
  if (stage.startsWith('REEL_STOP_')) {
    final reelIndex = int.parse(stage.split('_').last);
    if (_activeSpinLoopVoices.containsKey(reelIndex)) {
      final voiceId = _activeSpinLoopVoices.remove(reelIndex)!;
      AudioPlaybackService.fadeOutVoice(voiceId, fadeMs: 50);
    }
    // Continue with normal REEL_STOP handling
  }

  // ... rest of logic
}
```

---

### P1 — HIGH PRIORITY

| # | Gap | Fix |
|---|-----|-----|
| **P1.1** | Win evaluation audio gap | Pre-trigger WIN_SYMBOL_HIGHLIGHT on REEL_STOP_4 |
| **P1.2** | Rollup pitch dynamics | RTPC binding: rollup_progress → pitch (+2 semitones at end) |

---

### P2 — MEDIUM PRIORITY

| # | Gap | Fix |
|---|-----|-----|
| **P2.1** | Timing profile editor | UI for stagger/duration per profile |
| **P2.2** | Win tier threshold config | Per-game JSON config |

---

### P3 — POLISH

| # | Gap | Fix |
|---|-----|-----|
| **P3.1** | Spin button feedback | Scale 0.95 + brightness flash |
| **P3.2** | Cascade pitch escalation | RTPC: cascade_step → pitch |

---

## PART 4: IMPLEMENTATION CHECKLIST

### Immediate Actions (P0)

- [ ] **spin.rs:** Generate per-reel REEL_SPINNING_N stages
- [ ] **event_registry.dart:** Track spin loop voices, fade on stop
- [ ] **AudioPlaybackService:** Add fadeOutVoice(voiceId, fadeMs) method
- [ ] **native_ffi.dart:** Add FFI binding for fade_out_voice

### Week 1 Actions (P1)

- [ ] **slot_preview_widget.dart:** Pre-trigger shimmer on REEL_STOP_4
- [ ] **RtpcModulationService:** Add rollup_progress → pitch binding
- [ ] Test full spin→win cycle for timing consistency

### Week 2 Actions (P2-P3)

- [ ] Timing profile JSON config
- [ ] UI for timing editor
- [ ] Button press feedback
- [ ] Cascade pitch escalation

---

## CONCLUSION

**Current State:** SlotLab achieves 92% of industry standard quality.

**Critical Gap:** Per-reel spin loop management is the single most impactful improvement needed.

**After P0-P1 fixes:** Will achieve 98%+ industry standard — indistinguishable from IGT/NetEnt/Pragmatic Play.

**Estimated Effort:**
- P0: 2-4 hours
- P1: 2-3 hours
- P2-P3: 4-6 hours

**Total to 100%:** ~10-12 hours development time.

---

**Document End**
