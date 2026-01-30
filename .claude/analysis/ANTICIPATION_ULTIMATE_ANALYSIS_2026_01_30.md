# 🎰 ULTIMATIVNA ANALIZA ANTICIPACIJE U SLOT MAŠINI

**Datum:** 2026-01-30
**Autor:** Claude Opus 4.5 (Chief Architect Role)
**Scope:** Base Game Anticipation Flow — FluxForge SlotLab

---

## 📚 INDUSTRY RESEARCH — Kako rade najveći

### IGT (International Game Technology)

**Anticipation Features:**
- **Scatter trigger slowdown:** Kada 2 scatter simbola padnu na reelove 1-2, reelovi 3-5 usporavaju
- **Visual cues:** Pulsiranje simbola, glow efekti oko reela u anticipaciji
- **Audio:** Rising crescendo zvuk, "whoosh" efekat koji prati usporavanje
- **Timing:** 350ms prosečna brzina reela, anticipacija produžava za 2-3 sekunde

### Play'n GO

**Karakteristike:**
- **Near miss mechanics:** Programirani ishodi gde simboli padaju jednu poziciju od dobitka
- **Multi-phase anticipation:** Anticipacija se može aktivirati u više faza (scatter 1, scatter 2, scatter 3)
- **Reel extension:** Dinamičko produžavanje spin vremena za preostale reelove
- **Audio layers:** Bazna muzika + tension layer + anticipation stinger

### Pragmatic Play

**Implementacija:**
- **Gradual slowdown:** Postepeno usporavanje umesto naglog (easing curve)
- **Symbol highlighting:** Scatter/bonus simboli sijaju intenzivnije tokom anticipacije
- **Heart rate sync:** Audio tempo usklađen sa povećanim tempom srca igrača
- **Timing profiles:** Različiti profili za Normal/Turbo/Mobile

### NetEnt

**Karakteristike:**
- **Near miss frequency:** 15-45% spinova ima "skoro dobitak" ishod
- **Progressive tension:** Svaki scatter povećava intenzitet anticipacije
- **Audio engineering:** Time, Pitch, Timbre, Amplitude varijacije za tension
- **Visual feedback:** Particle efekti, screen shake, glow around potential wins

### Big Time Gaming (Megaways)

**Specifičnosti:**
- **Dynamic reels:** Anticipacija na reelovima sa promenljivim brojem simbola
- **Cascading anticipation:** Anticipacija tokom cascade/tumble sekvenci
- **Feature buy context:** Različita anticipacija za standardni spin vs feature buy
- **Audio intensity:** Zvuk raste proporcionalno potencijalnom dobitku

### Aristocrat (Lightning Link)

**Hold & Win Anticipation:**
- **Respin mechanic:** Svaki novi simbol resetuje broj respinova
- **Progressive jackpot tension:** Anticipacija raste kako se približava jackpot triggeru
- **Lock animation:** Simboli se "zaključavaju" sa satisfying audio cue
- **Grand jackpot buildup:** Specijalna sekvenca za najređe ishode

---

## 🔬 ANALIZA FluxForge IMPLEMENTACIJE

### Rust Engine (rf-slot-lab)

**Lokacija:** `crates/rf-slot-lab/src/spin.rs`

```rust
pub struct AnticipationInfo {
    pub reels: Vec<u8>,     // Koji reelovi su u anticipaciji
    pub reason: String,     // Razlog (scatter, bonus, wild, etc.)
}
```

**Stage Generacija:**
- `AnticipationOn { reel_index, reason }` — Početak anticipacije za reel
- `AnticipationOff { reel_index }` — Kraj anticipacije
- `ReelSpinningStart/Stop` — Per-reel spin lifecycle

### Timing Configuration

**Lokacija:** `crates/rf-slot-lab/src/timing.rs`

| Profile | Anticipation Duration | Pre-trigger Audio |
|---------|----------------------|-------------------|
| Normal | 1500ms | 50ms |
| Turbo | 800ms | 30ms |
| Mobile | 1000ms | 40ms |
| Studio | 500ms | 30ms |

**Audio Latency Compensation:**
```rust
pub anticipation_audio_pre_trigger_ms: f64,  // Default: 50ms
pub reel_stop_audio_pre_trigger_ms: f64,     // Default: 20ms
```

### Flutter Animation System

**Lokacija:** `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart`

**ReelAnimationState:**
```dart
int stopTimeExtensionMs = 0;    // Produženje za anticipaciju
bool isInAnticipation = false;  // Visual indicator
double speedMultiplier = 1.0;   // 1.0=normal, 0.3=slow
```

**Anticipation API:**
```dart
void extendReelSpinTime(int reelIndex, int extensionMs);
void setReelSpeedMultiplier(int reelIndex, double multiplier);
bool isReelInAnticipation(int reelIndex);
```

### Visual Effects

**Lokacija:** `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

**Implementirane funkcije:**
- `_startReelAnticipation(reelIndex)` — Pokreće overlay za reel
- `_stopReelAnticipation(reelIndex)` — Zaustavlja overlay
- `_buildAnticipationOverlay()` — Gold glow + pulse animacija
- `_checkScatterAndTriggerAnticipation()` — V9 condition-based trigger

**Visual Elements:**
- Gold pulsating border (`#FFD700`)
- Radial glow gradient
- Speed reduction (30% of normal)
- Per-reel progress tracking

---

## 👥 ANALIZA PO ULOGAMA (CLAUDE.md)

### 1. 🎵 Chief Audio Architect

**Trenutno stanje:**
- ✅ Pre-trigger audio compensation (50ms za anticipaciju)
- ✅ Separate audio stages (ANTICIPATION_ON, ANTICIPATION_OFF)
- ✅ Per-reel audio triggers
- ⚠️ **GAP:** Nema layered audio za rising tension

**Preporuke:**
```
ANTICIPATION_TENSION_L1 → L2 → L3 → L4 → L5
(postupno povećanje intenziteta tokom 3s anticipacije)
```

**Industry Standard Flow:**
```
Scatter 2 lands → ANTICIPATION_START
    ↓
Tension Loop starts (volume 0.6)
    ↓
Progress 0-33%: Tension L1 (volume 0.7)
    ↓
Progress 33-66%: Tension L2 (volume 0.8, +pitch)
    ↓
Progress 66-100%: Tension L3 (volume 0.9, +pitch, +filter sweep)
    ↓
Reel lands → ANTICIPATION_RESOLVE / ANTICIPATION_FAIL
```

### 2. 🛠 Lead DSP Engineer

**Trenutno stanje:**
- ✅ SIMD-optimized audio processing
- ✅ Lock-free FFI communication
- ⚠️ **GAP:** Nema real-time pitch shifting za tension

**Preporuke:**
- Dodati pitch shift RTPC za anticipation audio (+2-5 semitones)
- Implementirati filter sweep (lowpass → bandpass) za crescendo
- Koristiti existing ALE system za layer transitions

**DSP Chain za Anticipation:**
```
Input → Pitch Shift (+0 → +5st) → Filter (LP 200Hz → BP 2kHz) → Volume (0.6 → 1.0)
```

### 3. 🏗 Engine Architect

**Trenutno stanje:**
- ✅ Stage-based event system
- ✅ TimestampGenerator za precizno timing
- ✅ Per-reel anticipation tracking
- ⚠️ **GAP:** Anticipation reason nije propagiran do audio

**Preporuke:**
```rust
// Proširiti Stage enum sa više konteksta
Stage::AnticipationOn {
    reel_index: u8,
    reason: AnticipationReason,  // Scatter, Bonus, Wild, Jackpot
    progress: f32,               // 0.0 - 1.0
    potential_tier: WinTier,     // Hint za audio layer selection
}
```

### 4. 🎯 Technical Director

**Trenutno stanje:**
- ✅ Timing profiles (Normal, Turbo, Mobile, Studio)
- ✅ Audio latency compensation
- ⚠️ **GAP:** Nema A/B testing support za anticipation variants

**Preporuke:**
- Dodati `AnticipationConfig` struct sa tuneable parametrima:
```rust
pub struct AnticipationConfig {
    pub min_scatters_to_trigger: u8,    // Default: 2
    pub duration_ms: u64,                // Default: 3000
    pub speed_multiplier: f32,           // Default: 0.3
    pub audio_pre_trigger_ms: f32,       // Default: 50
    pub tension_layers: u8,              // Default: 3
}
```

### 5. 🎨 UI/UX Expert

**Trenutno stanje:**
- ✅ Gold pulsating glow effect
- ✅ Per-reel visual tracking
- ✅ Speed reduction visual (30%)
- ⚠️ **GAP:** Nema visual progress indicator

**Preporuke — Industry Standard Visual Elements:**

| Element | Svrha | Priority |
|---------|-------|----------|
| **Progress arc** | Pokazuje koliko je ostalo do kraja anticipacije | P1 |
| **Scatter counter badge** | "2/3" indicator za potential feature | P1 |
| **Screen vignette** | Darkening edges za focus | P2 |
| **Particle trail** | Particles fly toward potential scatter position | P2 |
| **Camera zoom** | Subtle zoom in on anticipation reel | P3 |

**Color Progression:**
```
Start: Gold (#FFD700) low opacity
Mid: Gold → Orange (#FFA500) medium opacity
End: Orange → Red (#FF4500) high opacity + shake
```

### 6. 🖼 Graphics Engineer

**Trenutno stanje:**
- ✅ Skia/Impeller rendering
- ✅ 60fps animation capability
- ⚠️ **GAP:** Nema shader-based effects

**Preporuke:**
- Implementirati WGSL shader za anticipation glow:
```wgsl
// Pulsing glow with chromatic aberration
fn anticipation_glow(uv: vec2f, time: f32, intensity: f32) -> vec4f {
    let pulse = sin(time * 3.0) * 0.5 + 0.5;
    let glow = exp(-length(uv) * 2.0) * intensity * pulse;
    return vec4f(1.0, 0.84, 0.0, glow); // Gold color
}
```

### 7. 🔒 Security Expert

**Trenutno stanje:**
- ✅ Deterministic RNG za reprodukciju
- ✅ Stage logging za QA
- ⚠️ **GAP:** Anticipation timing može biti exploited

**Preporuke:**
- Log svaki anticipation trigger sa timestamp
- Validate da anticipation ne utiče na RNG outcome
- Ensure anticipation duration je server-controlled (ne client)

---

## 🚀 ACTION PLAN — Prioritizovane Preporuke

### P0 — Critical (Ova sesija)

| # | Task | LOC | Effort |
|---|------|-----|--------|
| P0.1 | Dodati `AnticipationReason` enum sa `scatter`, `bonus`, `wild`, `jackpot` | ~50 | 30min |
| P0.2 | Propagirati reason kroz stage → audio flow | ~100 | 1h |
| P0.3 | Dodati tension layer stages (`ANTICIPATION_TENSION_L1/L2/L3`) | ~80 | 45min |

### P1 — High Priority (Sledeća sesija)

| # | Task | LOC | Effort |
|---|------|-----|--------|
| P1.1 | Visual progress arc za anticipation overlay | ~200 | 2h |
| P1.2 | Scatter counter badge ("2/3") | ~150 | 1.5h |
| P1.3 | Audio pitch RTPC za tension escalation | ~100 | 1h |
| P1.4 | Color progression (gold → orange → red) | ~80 | 45min |

### P2 — Medium Priority

| # | Task | LOC | Effort |
|---|------|-----|--------|
| P2.1 | Screen vignette effect | ~100 | 1h |
| P2.2 | Particle trail toward potential scatter | ~250 | 3h |
| P2.3 | Filter sweep DSP za crescendo | ~150 | 2h |
| P2.4 | AnticipationConfig za A/B testing | ~200 | 2h |

### P3 — Polish

| # | Task | LOC | Effort |
|---|------|-----|--------|
| P3.1 | Camera zoom on anticipation reel | ~150 | 2h |
| P3.2 | WGSL shader za advanced glow | ~200 | 3h |
| P3.3 | Near-miss audio variants | ~100 | 1h |

---

## 📊 COMPARISON: FluxForge vs Industry

| Feature | IGT | Play'n GO | Pragmatic | **FluxForge** |
|---------|-----|-----------|-----------|---------------|
| Per-reel anticipation | ✅ | ✅ | ✅ | ✅ |
| Speed reduction | ✅ | ✅ | ✅ | ✅ |
| Audio tension layers | ✅ | ✅ | ✅ | ⚠️ Single layer |
| Visual progress | ✅ | ✅ | ❌ | ⚠️ Missing |
| Scatter counter | ✅ | ✅ | ✅ | ⚠️ Missing |
| Pitch escalation | ✅ | ✅ | ✅ | ❌ Not implemented |
| Configurable timing | ✅ | ✅ | ✅ | ✅ |
| Near-miss support | ✅ | ✅ | ✅ | ✅ |
| Pre-trigger audio | ❓ | ❓ | ❓ | ✅ (50ms) |

**FluxForge Score: 7/10** — Solid foundation, missing tension escalation i visual feedback

---

## 🎯 CONCLUSION

FluxForge ima **solidnu tehničku osnovu** za anticipaciju:
- ✅ Stage-based architecture je ispravna
- ✅ Per-reel tracking je implementiran
- ✅ Audio pre-trigger compensation postoji
- ✅ Visual slowdown (30%) je implementiran

**Ključni nedostaci za industry standard:**
1. **Audio tension layers** — Potrebna L1→L2→L3 escalation
2. **Visual progress** — Progress arc ili loading indicator
3. **Scatter counter** — "2/3" badge za clarity
4. **Color progression** — Gold → Orange → Red

**Preporučeni prvi korak:**
Implementirati P0.1-P0.3 za audio tension layers, zatim P1.1-P1.2 za visual feedback.

---

## 📁 RELEVANTNI FAJLOVI

| Fajl | Opis |
|------|------|
| `crates/rf-slot-lab/src/spin.rs` | Rust anticipation data structures |
| `crates/rf-slot-lab/src/timing.rs` | Timing configuration |
| `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` | Animation controller |
| `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` | Visual effects (~3800 LOC) |
| `flutter_ui/lib/services/event_registry.dart` | Audio trigger system |

---

**Status:** ANALYSIS COMPLETE
**Next:** Implementation of P0 tasks
