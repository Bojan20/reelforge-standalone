# Slot Lab UI/UX — Ultimate Multi-Role Analysis

> Kompleksna analiza dizajna kroz 7 ekspertskih perspektiva.
> Fokus: Intuitivnost za slot igrače, casino estetika, profesionalni audio workflow.

**Datum:** 2026-01-20
**Analizirani fajlovi:** 12 widgeta, 1 screen, 1 provider

---

## Executive Summary

Slot Lab je **fullscreen audio sandbox** za slot game audio dizajn. Kombinuje:
- **Casino-grade vizuale** — Premium slot machine sa 3D simbolima i animacijama
- **DAW-level workflow** — Timeline, tracks, regions, waveforms
- **Wwise/FMOD integraciju** — Composite events, RTPC, bus hierarchy
- **Rapid testing** — Forced outcomes sa keyboard shortcuts

**Ključna vrednost:** Audio dizajner može testirati zvuk za bilo koji slot scenario (Big Win, Free Spins, Jackpot) u roku od 2 sekunde.

---

## 🎰 Perspektiva 1: SLOT IGRAČ (Casino Gamer UX)

### Šta slot igrač očekuje od vizuala?

**Implementirano ✅:**

1. **Premium Reels Display** ([slot_preview_widget.dart](flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart))
   - 5x3 grid sa smooth vertical spin animacijom
   - 10 slot simbola sa gradijent bojama i glow efektima:
     - WILD (★) — Zlatni, `isSpecial: true`
     - SCATTER (◆) — Magenta, `isSpecial: true`
     - BONUS (♦) — Cyan, `isSpecial: true`
     - SEVEN (7) — Crveni
     - BAR (▬) — Zeleni
     - BELL (🔔), CHERRY (🍒), LEMON (🍋), ORANGE (🍊), GRAPE (🍇)
   - **Per-reel stagger delay**: 120ms između startovanja svakog reel-a
   - **Win highlighting**: Zeleni glow border oko dobitnih reel-ova

2. **Anticipation Feel**
   - Reels sa različitim duration-ima: `1000 + (index * 250)ms`
   - Poslednji reel se vrti najduže = "hoće li biti win?" napetost
   - Motion blur overlay tokom spina (opacity fade)

3. **Win Celebration Feedback**
   - `_winPulseController` — pulsirajuća animacija 0.6→1.0
   - Border menja boju: spinning=blue, win=green
   - Tile scale na aktivnim simbolima

**Nedostaci ❌:**

| Problem | Impact | Preporuka |
|---------|--------|-----------|
| Nema coin shower animacije | Big Win feels flat | Dodati particle system |
| Nema win amount display overlay | User ne vidi koliko je dobio | Overlay sa animated counter |
| Sound-to-visual sync hardcoded | Može biti off na sporijim uređajima | Koristiti P0.1 timing config |

### Igrački Mental Model

```
SPIN → Napetost → Reels Stop → Win/Lose → Celebration
                   ↓
              Anticipation
              (poslednji reel)
```

Slot Lab korektno prati ovaj flow kroz stage events.

---

## 🎨 Perspektiva 2: UI/UX DIZAJNER (Visual Design)

### Color Palette Analysis

**FluxForge Theme** (Pro Audio Dark):

```
Backgrounds:
├── bgDeepest: #0A0A0C
├── bgDeep:    #121216
├── bgMid:     #1A1A20
└── bgSurface: #242430

Accents:
├── accentBlue:   #4A9EFF (focus, selection)
├── accentGreen:  #40FF90 (positive, win)
├── accentOrange: #FF9040 (active, warning)
├── accentRed:    #FF4060 (clip, error)
├── accentCyan:   #40C8FF (spectrum, info)
├── accentPurple: #E040FB (features)
└── accentYellow: #FFD700 (jackpot, gold)
```

### Glass Morphism System ([glass_slot_lab.dart](flutter_ui/lib/widgets/glass/glass_slot_lab.dart))

Premium liquid glass aesthetic sa 10 specijalizovanih wrapper-a:

| Wrapper | Namena | Blur | Border |
|---------|--------|------|--------|
| `GlassSlotPreviewWrapper` | Reel display | 12σ | 2px on win |
| `GlassReelWrapper` | Individual reel | 4σ | Green glow on win |
| `GlassStageTraceWrapper` | Event timeline | 8σ | Cyan when playing |
| `GlassStageEventWrapper` | Stage dot | 4σ | Color by stage type |
| `GlassEventLogWrapper` | Log panel | 6σ | Subtle |
| `GlassForcedOutcomeButtonWrapper` | Test buttons | 4σ | Per-outcome color |
| `GlassWinCelebrationWrapper` | Win overlay | 16σ | Dual glow |
| `GlassAudioPoolStats` | Pool stats | 4σ | Hit rate color |

**Stage Color Mapping:**

```dart
spin_*       → accentBlue
reel_*       → accentCyan
win_*        → accentGreen
anticipation → accentYellow
cascade      → accentCyan
feature      → accentPurple
jackpot      → accentOrange
```

### Typography Hierarchy

```
Header:     9-10px, UPPERCASE, letterSpacing: 1, bold
Label:      10-11px, medium weight
Body:       11-12px, normal
Timestamp:  9px, monospace, white38
Badge:      7-8px, bold, colored
```

### Layout Pattern

```
┌─────────────────────────────────────────────────────────┐
│ HEADER: Title + Controls + Status                    32px│
├─────────────────────────────────────────────────────────┤
│                                                         │
│  MAIN CONTENT                                          │
│  (Reel Preview / Timeline / List)                      │
│                                                    flex │
├─────────────────────────────────────────────────────────┤
│ FOOTER: Status bar / Mini controls                 20px │
└─────────────────────────────────────────────────────────┘
```

---

## 🎧 Perspektiva 3: AUDIO DIZAJNER (Professional Workflow)

### Event Registry Integration

**Central Audio System** ([event_registry.dart](flutter_ui/lib/services/event_registry.dart)):

```
STAGE → EventRegistry.trigger() → AudioEvent → Layer[] → Playback
                                      ↓
                               Per-layer:
                               - delay
                               - offset
                               - volume
                               - pan
                               - busId
```

### Slot Lab Workflow

1. **Import Audio** → Audio Browser Panel sa hover preview
2. **Create Event** → Composite events sa multiple layers
3. **Map to Stage** → EventRegistry binding
4. **Test** → Forced outcomes (1-0 shortcuts)
5. **Iterate** → Event Log za debugging

### Audio Browser ([audio_hover_preview.dart](flutter_ui/lib/widgets/slot_lab/audio_hover_preview.dart))

```dart
AudioBrowserItem:
├── Hover → 500ms delay → Auto-preview start
├── Drag → Feedback widget → Drop to timeline
├── Format colors (WAV=blue, FLAC=green, MP3=orange)
├── Mini waveform with playback progress
└── Tags display
```

**Hover Preview Flow:**
```
Mouse Enter → Start 500ms Timer → Play Audio → Show Waveform
                                      ↓
                              AnimationController syncs
                              playback progress
Mouse Exit → Cancel Timer → Stop Audio → Hide Waveform
```

### Event Log ([event_log_panel.dart](flutter_ui/lib/widgets/slot_lab/event_log_panel.dart))

6 event tipova sa color-coding:

| Type | Color | Icon | Use Case |
|------|-------|------|----------|
| STAGE | Blue | timeline | spin_start, reel_stop |
| MW | Orange | send | Post Event calls |
| RTPC | Green | tune | Parameter changes |
| STATE | Purple | toggle_on | State/Switch changes |
| AUDIO | Cyan | volume_up | Playback events |
| ERROR | Red | error_outline | Failures |

**Features:**
- Auto-scroll sa manual pause
- Type filtering (toggle chips)
- Search through eventName/details
- Copy to clipboard (formatted)
- Max 500 entries (ring buffer)

---

## 🧪 Perspektiva 4: QA ENGINEER (Testing Workflow)

### Forced Outcome Panel ([forced_outcome_panel.dart](flutter_ui/lib/widgets/slot_lab/forced_outcome_panel.dart))

**10 testable outcomes sa keyboard shortcuts:**

| Key | Outcome | Description | Expected Stages |
|-----|---------|-------------|-----------------|
| 1 | LOSE | No wins | spin_start → reel_stop → spin_end |
| 2 | SMALL WIN | <5x bet | + win_present, rollup |
| 3 | BIG WIN | 10-25x | + anticipation, bigwin_tier |
| 4 | MEGA WIN | 25-50x | + anticipation, bigwin_tier |
| 5 | EPIC WIN | >50x | + anticipation, bigwin_tier |
| 6 | FREE SPINS | Feature trigger | + feature_enter/step/exit |
| 7 | JACKPOT | Progressive | + jackpot_trigger/present |
| 8 | NEAR MISS | Almost won | + anticipation (no win) |
| 9 | CASCADE | Tumbling reels | + cascade_start/step/end |
| 0 | ULTRA WIN | 100x+ | + all celebrations |

**Outcome History:**
- Timestamped entries
- Win amount tracking
- Duration measurement
- Horizontal scroll strip

### Stage Trace Widget ([stage_trace_widget.dart](flutter_ui/lib/widgets/slot_lab/stage_trace_widget.dart))

Visual timeline kroz stage events:

```
Stage Trace Layout:

[Header: STAGE TRACE | 5/12 | REEL_STOP]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ●───────●───────●───────◉───────○
  SPIN    REEL    REEL   CURRENT  PENDING
  START   STOP    STOP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[SPI REE WIN ANT CAS] <- unique type chips
```

**Features:**
- Animated playhead (green line)
- Pulsing active stage dot
- Color-coded stage types (21 types mapped)
- Click to trigger specific stage
- Compact `StageProgressBar` variant

---

## ⚡ Perspektiva 5: PERFORMANCE ENGINEER (Optimization)

### Animation Controllers

```dart
SlotPreviewWidget:
├── _spinControllers: List<AnimationController> (5 reels)
│   └── Duration: 1000 + (index * 250)ms each
└── _winPulseController: 600ms, repeat(reverse: true)

StageTraceWidget:
├── _pulseController: 600ms, repeat(reverse: true)
└── _playheadController: 100ms (smooth updates)

ForcedOutcomePanel:
└── _pulseController: 800ms (triggering feedback)
```

### Widget Rebuild Strategy

1. **ListenableBuilder** za provider updates (granular rebuilds)
2. **AnimatedBuilder** za animations (isolated repaints)
3. **AnimatedContainer** za state transitions (150ms)
4. **ClipRRect** sa `Clip.antiAlias` (GPU-accelerated)

### Potential Bottlenecks

| Area | Concern | Mitigation |
|------|---------|------------|
| BackdropFilter blur | GPU intensive | Cached filter, minimal blur (4-12σ) |
| Waveform painting | Custom painter | Paint only visible portion |
| Event log | Many entries | ListView.builder + ring buffer (500 max) |
| Stage trace | Many dots | LayoutBuilder caching |

---

## 🎮 Perspektiva 6: GAME DESIGNER (Slot Mechanics)

### Supported Slot Concepts

1. **Base Game**
   - spin_start, reel_spinning, reel_stop (per-reel)
   - evaluate_wins, win_present, win_line_show

2. **Anticipation**
   - anticipation_on (pre-trigger sa P0.6)
   - anticipation_off
   - Near miss escalation (P1.2)

3. **Win Tiers**
   - bigwin_tier (nice/super/mega/epic/ultra)
   - Layered audio struktura (P0.7)

4. **Features**
   - feature_enter, feature_step, feature_exit
   - Free spins state tracking

5. **Cascade/Tumble**
   - cascade_start, cascade_step (dynamic timing P0.4), cascade_end

6. **Jackpots**
   - jackpot_trigger, jackpot_present
   - Progressive support ready

### Stage Flow Visualization

```
                    ┌─────────────┐
                    │ SPIN_START  │
                    └──────┬──────┘
                           │
               ┌───────────┴───────────┐
               │                       │
         ┌─────┴─────┐           ┌─────┴─────┐
         │REEL_SPIN  │           │ANTICIPATION│
         │  (loop)   │           │    ON      │
         └─────┬─────┘           └─────┬─────┘
               │                       │
         ┌─────┴─────┐           ┌─────┴─────┐
         │REEL_STOP  │           │ANTICIPATION│
         │  0→4      │           │    OFF     │
         └─────┬─────┘           └─────┬─────┘
               │                       │
               └───────────┬───────────┘
                           │
                    ┌──────┴──────┐
                    │EVALUATE_WINS│
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
  ┌─────┴─────┐     ┌─────┴─────┐     ┌─────┴─────┐
  │   LOSE    │     │ WIN_TIER  │     │  FEATURE  │
  │(spin_end) │     │ ROLLUP    │     │  TRIGGER  │
  └───────────┘     └───────────┘     └───────────┘
```

---

## 🏗️ Perspektiva 7: SYSTEM ARCHITECT (Code Quality)

### Data Flow Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  SINGLE SOURCE OF TRUTH                  │
│              MiddlewareProvider.compositeEvents          │
└─────────────────────────────┬───────────────────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           │                  │                  │
    ┌──────┴──────┐    ┌──────┴──────┐    ┌──────┴──────┐
    │  SLOT LAB   │    │  MIDDLEWARE │    │   DAW/     │
    │  Timeline   │    │  Actions    │    │  TIMELINE  │
    │  Regions    │    │  Table      │    │            │
    └──────┬──────┘    └──────┬──────┘    └────────────┘
           │                  │
           │    BIDIRECTIONAL SYNC
           └────────┬─────────┘
                    │
           ┌────────┴────────┐
           │  EventRegistry  │
           │  (playback)     │
           └─────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| `SlotLabScreen` | Main fullscreen container, keyboard handling |
| `SlotLabProvider` | Rust engine FFI, spin state, timing config |
| `MiddlewareProvider` | Composite events, RTPC, bus hierarchy |
| `EventRegistry` | Audio playback, voice management |
| `AudioPool` | Voice pooling for rapid-fire events |
| `SlotLabTrackBridge` | DAW integration |

### Code Metrics

| Metric | Value |
|--------|-------|
| slot_lab_screen.dart LOC | ~2500 (large, consider splitting) |
| Widget count | 12 specialized widgets |
| Animation controllers | 15+ total |
| Provider listeners | 3 (SlotLab, Middleware, Stage) |
| FFI bindings | 20+ Slot Lab specific |

---

## Recommendations Summary

### Prioritet 1 (Immediate UX Wins)

| # | Improvement | Impact | Effort |
|---|-------------|--------|--------|
| 1 | Win amount overlay on SlotPreviewWidget | High | Low |
| 2 | Coin particle system for Big Win | High | Medium |
| 3 | Sound-to-visual sync using TimingConfig | Medium | Low |

### Prioritet 2 (Professional Polish)

| # | Improvement | Impact | Effort |
|---|-------------|--------|--------|
| 4 | Waveform preview in audio browser items | Medium | Medium |
| 5 | Drag audio directly to timeline regions | High | Medium |
| 6 | Custom timing profile editor UI | Medium | Medium |

### Prioritet 3 (Future Features)

| # | Improvement | Impact | Effort |
|---|-------------|--------|--------|
| 7 | Volatility curve visualization | Low | Medium |
| 8 | Session statistics graphs | Low | Medium |
| 9 | Export spin log to CSV | Low | Low |
| 10 | WebSocket live engine connection | High | High |

---

## Conclusion

Slot Lab je **profesionalni alat** koji uspešno kombinuje:
- ✅ Casino-authentic vizuale sa premium slot machine preview
- ✅ Intuitivni testing sa keyboard shortcuts (1-0)
- ✅ Kompletan audio workflow (browse → assign → test → iterate)
- ✅ Real-time debugging sa Event Log
- ✅ Bidirectional sync sa Middleware sistemom

**Glavna snaga:** Rapid iteration — audio dizajner može testirati bilo koji scenario u <2 sekunde.

**Glavna slabost:** Nedostatak vizualnih celebracija (particle effects, animated win counters) koji bi zaokružili "casino feel".

---

## Related Documentation

- [SLOT_LAB_SYSTEM.md](SLOT_LAB_SYSTEM.md) — Technical architecture
- [SLOT_LAB_AUDIO_FEATURES.md](SLOT_LAB_AUDIO_FEATURES.md) — P0/P1 audio implementations
- [SLOT_LAB_ULTIMATE_ANALYSIS.md](../analysis/SLOT_LAB_ULTIMATE_ANALYSIS.md) — Full system analysis
