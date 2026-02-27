# AUREXIS™ Unified Intelligence Panel — Architecture Specification

## FluxForge Studio — SlotLab Layout Consolidation

### Confidential / Engine-Level Document

---

# 0. PROBLEM STATEMENT

**Trenutno stanje:**
- 11 nezavisnih audio intelligence sistema
- 1000+ konfigurabilnih parametara rasutih po 10+ UI površina
- 5 super-tabova × 4 sub-taba = 20+ panela u Lower Zone
- Plus modalni dijalozi za AutoSpatial, GameConfig, Scenarios
- Dizajner mora da ZNAŽE gde je šta, manualno konfiguriše sve, i razmišlja o interakcijama između sistema

**AUREXIS rešenje:**
- JEDAN koherentan intelligence layer koji AUTOMATSKI orkestrrira SVE sisteme
- Dizajner vidi REZULTAT, ne mehaniku
- "Set the vibe, not the parameters"

---

# 1. AUREXIS FILOZOFIJA

## 1.1 Princip: Profile-Driven Intelligence

```
UMESTO:
  Dizajner → konfiguriši ALE rules
           → konfiguriši AutoSpatial intent rules
           → konfiguriši RTPC bindings
           → konfiguriši Ducking rules
           → konfiguriši Win Tier thresholds
           → konfiguriši Container behaviors
           → MOLI BOGA da sve radi zajedno

AUREXIS:
  Dizajner → izabere PROFILE ("High Volatility Thriller")
           → AUREXIS automatski konfiguriše SVE
           → dizajner TWEAK-uje samo ono što želi drugačije
           → SVE se konzistentno ažurira
```

## 1.2 Princip: Emergent Intelligence

Svaki parametar u AUREXIS-u ne kontroliše jedan sistem — kontroliše **PONAŠANJE** koje se manifestuje kroz više sistema istovremeno.

Primer: Dizajner pomeri slider "TENSION" od 0.3 na 0.8:
- ALE: Pomera se sa L2 na L4 layer
- AutoSpatial: Stereo width raste sa 0.4 na 0.9
- RTPC: LPF cutoff pada sa 12kHz na 6kHz
- Ducking: Muzika se jače duckuje (-3dB → -9dB)
- Win Tier: Rollup ticks ubrzavaju
- Container: Blend se pomera ka intenzivnijem child-u

**Jedan slider — šest sistema se menjaju koherentno.**

## 1.3 Princip: Zero-Config Default

Svaki AUREXIS profil dolazi sa **inteligentnim defaultima** koji rade od prvog momenta. Dizajner ne mora ništa da konfiguriše da dobije profesionalan rezultat. Sav tweaking je opcioni.

## 1.4 Princip: Jurisdiction-Aware by Default

AUREXIS razume regulatorne zahteve za SVAKU jurisdikciju. Dizajner bira tržište — AUREXIS automatski primenjuje pravila:
- UK (UKGC): LDW suppression, celebration duration limits
- Australia (Victoria/NSW): Modified win audio thresholds
- Malta (MGA): Standard EU requirements
- Nevada/New Jersey: GLI-11 compliance
- Ontario: Canadian requirements

**Jedan projekat → više jurisdikcija → automatski compliant audio paketi.**

## 1.5 Princip: Production Pipeline Intelligence

AUREXIS ne samo da konfiguriše audio intelligence — već ubrzava CELU produkciju:
- Re-Theme wizard: zamena audio teme za 10 minuta umesto 2 nedelje
- Memory budget tracking: uvek vidljiv, nikad ne blokira
- Coverage heatmap: vizuelno gde fali audio
- Compliance report: 10 sekundi umesto 5 dana

---

# 2. AUREXIS PANEL — LAYOUT ARCHITECTURE

## 2.1 Nova SlotLab Layout Struktura

```
┌─────────────────────────────────────────────────────────────────────────┐
│ HEADER (56px) — Logo, GDD Import, Templates, FeatureBuilder, Coverage  │
├──────────┬────────────────────────────────────┬─────────────────────────┤
│          │                                    │                         │
│ AUREXIS  │         CENTER                     │    EVENTS               │
│ PANEL    │   (Slot Preview / Timeline)        │    PANEL                │
│ (280px)  │                                    │    (300px)              │
│          │                                    │                         │
│ ┌──────┐ │                                    │  Event List             │
│ │PRFL  │ │                                    │  Audio Browser          │
│ │+JRSD │ │                                    │  Quick Assign           │
│ │──────│ │                                    │                         │
│ │BHRV  │ │                                    │                         │
│ │──────│ │                                    │                         │
│ │TWEAK │ │                                    │                         │
│ │──────│ │                                    │                         │
│ │SCOPE │ │                                    │                         │
│ └──────┘ │                                    │                         │
│ ┌──────┐ │                                    │                         │
│ │BUDGET│ │                                    │                         │
│ │BAR   │ │                                    │                         │
│ └──────┘ │                                    │                         │
│          │                                    │                         │
├──────────┴────────────────────────────────────┴─────────────────────────┤
│ AUDIO BROWSER DOCK (90px, collapsible)                                  │
├─────────────────────────────────────────────────────────────────────────┤
│ LOWER ZONE — Simplified: TIMELINE │ MIX │ EXPORT (3 tabs only)         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Ključne promene:**
- **UltimateAudioPanel (levo, 240px) → AUREXIS Panel (levo, 280px)**
- **Lower Zone: 5 super-tab × 4 sub-tab → 3 taba** (Timeline, Mix, Export)
- **Svi intelligence sistemi → AUREXIS Panel**
- **Modalni dijalozi (AutoSpatial, GameConfig) → integrisani u AUREXIS**

## 2.2 AUREXIS Panel — 4 Sekcije

AUREXIS panel ima 4 vertikalne sekcije, svaka kolapsibilna:

```
┌──────────────────────────────┐
│ ▼ PROFILE                    │  ← 1. Profil selekcija
│   [High Volatility Thriller] │
│   ★★★★☆ Intensity            │
│   Volatility: ████████░░ 0.8 │
│   Tension:    ██████░░░░ 0.6 │
│   Chaos:      ████░░░░░░ 0.4 │
├──────────────────────────────┤
│ ▼ BEHAVIOR                   │  ← 2. Inteligentni parametri
│   ┌─── SPATIAL ──────────┐   │
│   │ Width      ████████░ │   │
│   │ Depth      ██████░░░ │   │
│   │ Movement   ████░░░░░ │   │
│   └──────────────────────┘   │
│   ┌─── DYNAMICS ─────────┐   │
│   │ Escalation ████████░ │   │
│   │ Ducking    ██████░░░ │   │
│   │ Fatigue    ████░░░░░ │   │
│   └──────────────────────┘   │
│   ┌─── MUSIC ────────────┐   │
│   │ Reactivity ████████░ │   │
│   │ Layer Bias ██████░░░ │   │
│   │ Transition ████░░░░░ │   │
│   └──────────────────────┘   │
│   ┌─── VARIATION ────────┐   │
│   │ Pan Drift  ████░░░░░ │   │
│   │ Width Var  ██░░░░░░░ │   │
│   │ Timing Var ██████░░░ │   │
│   └──────────────────────┘   │
├──────────────────────────────┤
│ ▼ TWEAK                     │  ← 3. Per-system override
│   [ALE]  [Spatial]  [RTPC]  │
│   [Duck] [WinTier] [Cont]   │
│   ─────────────────────────  │
│   Selected: ALE              │
│   ┌─ Quick Rules ─────────┐ │
│   │ winTier > 3 → L4      │ │
│   │ momentum > 0.7 → L5   │ │
│   │ + Add Rule             │ │
│   └────────────────────────┘ │
├──────────────────────────────┤
│ ▼ SCOPE                     │  ← 4. Real-time vizualizacija
│   ┌────────────────────────┐ │
│   │  ◉ Stereo Field       │ │
│   │  ⊡ Energy Density     │ │
│   │  ≋ Signal Monitor     │ │
│   │  ◎ Voice Cluster      │ │
│   └────────────────────────┘ │
└──────────────────────────────┘
```

---

# 3. SEKCIJA 1: PROFILE — Intelligence Presets

## 3.1 Šta je AUREXIS Profile?

**Profile = kompletna konfiguracija SVIH 11 sistema u jednom JSON fajlu.**

```dart
class AurexisProfile {
  final String id;
  final String name;
  final String description;
  final AurexisCategory category;
  final double intensity;        // 0.0-1.0 master intensity

  // ═══ Behavior Parameters (meta-controls) ═══
  final AurexisBehaviorConfig behavior;

  // ═══ Underlying System Configs (auto-generated from behavior) ═══
  final AleProfileConfig ale;
  final AutoSpatialProfileConfig spatial;
  final RtpcProfileConfig rtpc;
  final DuckingProfileConfig ducking;
  final WinTierProfileConfig winTiers;
  final ContainerProfileConfig containers;
  final FatigueProfileConfig fatigue;
  final MicroVariationConfig variation;
  final CollisionConfig collision;
  final PlatformProfileConfig platform;
}
```

## 3.2 Built-in Profiles (12)

| # | Profile | Category | Intensity | Use Case |
|---|---------|----------|-----------|----------|
| 1 | **Calm Classic** | classic | 0.3 | Low volatility, gentle transitions |
| 2 | **Standard Video** | video | 0.5 | Standard video slot |
| 3 | **High Volatility Thriller** | highVol | 0.8 | Aggressive escalation, wide stereo |
| 4 | **Megaways Chaos** | megaways | 0.9 | Maximum variation, fast transitions |
| 5 | **Hold & Win Tension** | holdWin | 0.7 | Building suspense, locking focus |
| 6 | **Jackpot Hunter** | jackpot | 0.85 | Progressive buildup, epic payoff |
| 7 | **Cascade Flow** | cascade | 0.6 | Escalating pitch/width per cascade step |
| 8 | **Asian Premium** | themed | 0.5 | Cultural audio conventions |
| 9 | **Mobile Optimized** | platform | 0.4 | Compressed stereo, reduced fatigue |
| 10 | **Headphone Spatial** | platform | 0.6 | Exaggerated width, HRTF hints |
| 11 | **Cabinet Mono-Safe** | platform | 0.3 | Mono-compatible, bass managed |
| 12 | **Silent Mode** | utility | 0.0 | All intelligence OFF (manual only) |

## 3.3 Profile UI

```
┌──────────────────────────────┐
│ AUREXIS PROFILE              │
│ ┌──────────────────────────┐ │
│ │ ▾ High Volatility Thrill │ │  ← Dropdown: built-in + custom
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ 🌍 ▾ UK (UKGC)          │ │  ← Jurisdiction dropdown (NEW)
│ └──────────────────────────┘ │
│                              │
│ Intensity ██████████░░ 0.85  │  ← Master slider (scales ALL behaviors)
│                              │
│ ┌─ Quick Dials ────────────┐ │
│ │ Volatility  ●────────○   │ │  ← 3 primary macro dials
│ │ Tension     ●──────○     │ │     (auto-derived from game math
│ │ Energy      ●────○       │ │      but manually overridable)
│ └──────────────────────────┘ │
│                              │
│ [Save As...] [Reset] [A|B]  │  ← Save custom, reset to preset, A/B compare
│                              │
│ ┌─ Memory Budget ─────────┐ │
│ │ ████████░░ 4.2/6.0 MB   │ │  ← Always-visible (NEW)
│ │ 📱 Mobile                │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

**Interaction:**
- Dropdown selektuje profil → SVE se menja instant
- Intensity slider skalira sve behavior parametrre proporcionalno
- Quick Dials menjaju GRUPU parametara (kao RTPC Macro)
- A/B dugme pamti dva profil snapshot-a za instant poređenje

## 3.4 Auto-Detection from GDD

Kada korisnik importuje GDD:
```
GDD Import:
  volatility: "high"
  rtp: 96.5
  mechanic: "megaways"
  features: [freeSpins, cascade, multiplierWilds]

AUREXIS auto-selects:
  Profile: "Megaways Chaos" (closest match)
  Intensity: 0.85 (from volatility)
  Tension: derived from feature count
  Energy: derived from RTP (higher RTP → lower energy cycling)
```

---

# 4. SEKCIJA 2: BEHAVIOR — Meta-Controls

## 4.1 Behavior Architecture

**Behavior parametri su APSTRAKTNI — opisuju PONAŠANJE, ne implementaciju.**

Svaki behavior parametar mapira se na VIŠE underlying sistema:

```
BEHAVIOR PARAM          → SYSTEM MAPPINGS
─────────────────────────────────────────────────────
spatial.width           → AutoSpatial.globalWidthScale
                        → ALE context layer width
                        → Container blend range

spatial.depth           → AutoSpatial distance attenuation
                        → Reverb send level scaling

spatial.movement        → AutoSpatial.smoothingTauMs (inverse)
                        → MicroVariation.panDriftRange
                        → Container sequence timing variation

dynamics.escalation     → WinTier audio intensity scaling
                        → RTPC win escalation curve steepness
                        → ALE rule threshold aggressiveness
                        → Cascade pitch/volume step size

dynamics.ducking        → DuckingRule amount scaling
                        → DuckingRule attack/release timing
                        → Bus priority weighting

dynamics.fatigue        → HF attenuation onset time
                        → Transient smoothing rate
                        → Width compression over time

music.reactivity        → ALE stability.cooldownMs (inverse)
                        → ALE rule evaluation frequency
                        → Layer transition speed

music.layerBias         → ALE base level offset
                        → Default layer intensity

music.transition        → ALE transition profile (beat/bar/phrase)
                        → Crossfade duration

variation.panDrift      → MicroVariation pan amplitude
                        → Per-voice pan jitter seed range

variation.widthVar      → MicroVariation width amplitude
                        → Stereo field micro-oscillation

variation.timingVar     → MicroVariation timing offset range
                        → Container random pitch/volume variation
```

## 4.2 Behavior Groups (4)

### SPATIAL (3 params)

```dart
class SpatialBehavior {
  double width;      // 0.0-1.0 — Koliko široko stereo polje
  double depth;      // 0.0-1.0 — Koliko duboko zvučno polje (reverb, distance)
  double movement;   // 0.0-1.0 — Koliko se zvuk kreće (pan drift, motion)
}
```

**Kako mapira:**

| width Value | AutoSpatial.globalWidthScale | ALE layer width | Description |
|-------------|------------------------------|-----------------|-------------|
| 0.0 | 0.2 (almost mono) | narrow | Compact, focused |
| 0.5 | 0.6 (standard) | medium | Normal stereo |
| 1.0 | 1.0 (full width) | wide | Panoramic |

### DYNAMICS (3 params)

```dart
class DynamicsBehavior {
  double escalation;  // 0.0-1.0 — Koliko agresivno raste intenzitet
  double ducking;     // 0.0-1.0 — Koliko agresivno ducking radi
  double fatigue;     // 0.0-1.0 — Koliko agresivno se smanjuje umor sluha
}
```

**escalation Mapping:**

| escalation | Win Tier audio intensity | RTPC curve | ALE transitions |
|------------|------------------------|------------|-----------------|
| 0.0 | Linear, subtle | gentle slope | slow, gradual |
| 0.5 | Quadratic, noticeable | moderate | medium speed |
| 1.0 | Exponential, dramatic | steep | instant jumps |

### MUSIC (3 params)

```dart
class MusicBehavior {
  double reactivity;   // 0.0-1.0 — Koliko brzo muzika reaguje na gameplay
  double layerBias;    // 0.0-1.0 — Default energetski nivo (L1=0.0, L5=1.0)
  double transition;   // 0.0-1.0 — Koliko duge tranzicije (instant→phrase-length)
}
```

**reactivity Mapping:**

| reactivity | ALE cooldownMs | ALE evaluation | Description |
|------------|---------------|----------------|-------------|
| 0.0 | 5000ms | Every 10 spins | Very slow, background feel |
| 0.3 | 2000ms | Every 5 spins | Gradual response |
| 0.5 | 1000ms | Every 2-3 spins | Standard |
| 0.8 | 300ms | Every spin | Highly reactive |
| 1.0 | 50ms | Sub-spin | Instant tracking |

### VARIATION (3 params)

```dart
class VariationBehavior {
  double panDrift;    // 0.0-1.0 — Micro pan oscilacija
  double widthVar;    // 0.0-1.0 — Micro width oscilacija
  double timingVar;   // 0.0-1.0 — Micro timing varijacija
}
```

**Deterministic!** Sve varijacije koriste seed = `hash(spriteId + eventTime + gameState)`. Identičan rezultat na svakom uređaju.

## 4.3 Behavior UI

```
┌──────────────────────────────────────┐
│ BEHAVIOR                              │
│                                       │
│ ┌─ SPATIAL ────────────────────────┐  │
│ │ Width     ●═══════════════○ 0.75 │  │
│ │ Depth     ●══════════○     0.60 │  │
│ │ Movement  ●═════○          0.40 │  │
│ └──────────────────────────────────┘  │
│                                       │
│ ┌─ DYNAMICS ───────────────────────┐  │
│ │ Escalation●═══════════════○ 0.80 │  │
│ │ Ducking   ●══════════○     0.55 │  │
│ │ Fatigue   ●══════○         0.45 │  │
│ └──────────────────────────────────┘  │
│                                       │
│ ┌─ MUSIC ──────────────────────────┐  │
│ │ Reactivity●═══════════○    0.65 │  │
│ │ Layer Bias●═══════○        0.50 │  │
│ │ Transition●════════════○   0.70 │  │
│ └──────────────────────────────────┘  │
│                                       │
│ ┌─ VARIATION ──────────────────────┐  │
│ │ Pan Drift ●════○           0.30 │  │
│ │ Width Var ●══○             0.20 │  │
│ │ Timing Var●═══════○        0.45 │  │
│ └──────────────────────────────────┘  │
│                                       │
│ [Lock: Spatial ◉] [Lock: Music ◉]    │
│ ← Locks prevent profile changes       │
└──────────────────────────────────────┘
```

**Key interactions:**
- Svaki slider = instant real-time preview (čuješ promenu odmah)
- Sekcija headers su kolapsibilni (klik na "SPATIAL" → collapse)
- Lock ikona: zaključava grupu parametara — profil promena ih ne menja
- Double-click na slider: reset na profil default
- Right-click na slider: otvori underlying system (TWEAK sekcija)

---

# 5. SEKCIJA 3: TWEAK — Per-System Override

## 5.1 Koncept

Behavior parametri kontrolišu 90% slučajeva. Ali ponekad dizajner želi da fino podesi TAČNO jedan aspekt jednog sistema. TWEAK sekcija to omogućava.

## 5.2 System Picker

```
┌──────────────────────────────────────┐
│ TWEAK                                 │
│                                       │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐         │
│ │ ALE│ │SPAT│ │RTPC│ │DUCK│         │
│ └────┘ └────┘ └────┘ └────┘         │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐         │
│ │ WIN│ │CONT│ │FATG│ │ VAR│         │
│ └────┘ └────┘ └────┘ └────┘         │
│ ═══════════════════════════════       │
│                                       │
│ ← System-specific compact editor →    │
│                                       │
└──────────────────────────────────────┘
```

8 sistema, svaki sa KOMPAKTNIM inline editorom (ne full panel — samo ključne kontrole).

## 5.3 Per-System Compact Editors

### ALE Compact Editor
```
┌─ ALE ──────────────────────────────┐
│ Context: [BASE ▾]                   │
│ Level:   L1 ○ L2 ● L3 ○ L4 ○ L5 ○│
│ ────────────────────────────────── │
│ Quick Rules (3 most important):     │
│  ├ winTier > 3 → L4  [×]          │
│  ├ momentum > 0.7 → L5  [×]       │
│  └ consecutiveLosses > 5 → L1 [×] │
│ [+ Add Rule]                        │
│ ────────────────────────────────── │
│ Stability: Cooldown [500ms]         │
│           Hold     [2000ms]         │
│ [Full Editor ↗]                     │
└────────────────────────────────────┘
```

### Spatial Compact Editor
```
┌─ SPATIAL ──────────────────────────┐
│ Global Width  ●════════○ 0.75      │
│ Global Pan    ●════════○ 0.90      │
│ ────────────────────────────────── │
│ Bus Overrides:                      │
│  SFX:   width ×1.2  pan ×1.0      │
│  Music: width ×0.6  pan ×0.5      │
│  UI:    width ×0.3  pan ×0.2      │
│ [Full Editor ↗]                     │
└────────────────────────────────────┘
```

### RTPC Compact Editor
```
┌─ RTPC ─────────────────────────────┐
│ Active RTPCs:                       │
│  ├ winTier     ████████░░ 0.78     │
│  ├ momentum    ██████░░░░ 0.55     │
│  └ cascadeDepth██░░░░░░░░ 0.15     │
│ ────────────────────────────────── │
│ Quick Bind: [winTier] → [volume ▾] │
│  Curve: linear ▾  Range: 0.5-1.0  │
│ [Full Editor ↗]                     │
└────────────────────────────────────┘
```

### Ducking Compact Editor
```
┌─ DUCKING ──────────────────────────┐
│ Active Rules: 3                     │
│  ├ Wins → Music   -6dB  50/500ms  │
│  ├ Voice → Music  -9dB  30/800ms  │
│  └ Jackpot → All  -12dB 10/1000ms │
│ [+ Quick Rule]                      │
│ [Matrix View ↗]                     │
└────────────────────────────────────┘
```

### Win Tier Compact Editor
```
┌─ WIN TIERS ────────────────────────┐
│ Preset: [Standard ▾]               │
│ Big Win Threshold: [20x ▾]         │
│ ────────────────────────────────── │
│ Regular: WIN_1-6 ████████ 8 tiers  │
│ Big Win: TIER_1-5 █████ 5 tiers    │
│ ────────────────────────────────── │
│ Audio Intensity: ●════════○ 0.80   │
│ Rollup Speed:    ●══════○   0.65   │
│ [Full Editor ↗]                     │
└────────────────────────────────────┘
```

### Container Compact Editor
```
┌─ CONTAINERS ───────────────────────┐
│ Blend:    2 active  [RtpcSlider]   │
│ Random:   5 active  [WeightPie]    │
│ Sequence: 1 active  [Timeline]     │
│ ────────────────────────────────── │
│ Global Smoothing: [300ms]          │
│ Deterministic:    [ON]             │
│ [Full Editor ↗]                     │
└────────────────────────────────────┘
```

### Fatigue Compact Editor (NOVO)
```
┌─ FATIGUE ──────────────────────────┐
│ Session Time:    ████░░░░ 12m 34s  │
│ HF Exposure:     ██████░░ MEDIUM   │
│ Transient Density:████░░░ LOW      │
│ ────────────────────────────────── │
│ HF Attenuation:  ●══════○ 0.45    │
│ Onset Time:      [30 min ▾]       │
│ Max Reduction:   [-3 dB ▾]        │
│ Transient Smooth: ●════○  0.35    │
└────────────────────────────────────┘
```

### Micro-Variation Compact Editor (NOVO)
```
┌─ VARIATION ────────────────────────┐
│ Seed Mode: [Deterministic ▾]       │
│ ────────────────────────────────── │
│ Pan Drift Range:   ±0.05           │
│ Width Variance:    ±0.03           │
│ Timing Offset:     ±8ms            │
│ Harmonic Shift:    ±0.02           │
│ ────────────────────────────────── │
│ Preview: [▶ Hear Variation]        │
└────────────────────────────────────┘
```

## 5.4 "Full Editor ↗" Navigation

Klik na "Full Editor ↗" otvara full-size panel u LOWER ZONE (ne modal). Lower Zone automatski se expand-uje i selektuje odgovarajući tab.

---

# 6. SEKCIJA 4: SCOPE — Real-Time Visualization

## 6.1 Vizualizacija Modes (4)

```
┌──────────────────────────────────────┐
│ SCOPE                                 │
│ ◉Stereo ○Energy ○Signal ○Voices      │
│ ┌────────────────────────────────┐   │
│ │                                │   │
│ │    ╭─────╮                     │   │
│ │   ╱       ╲  Active voices     │   │
│ │  │  L   R  │  shown as dots   │   │
│ │   ╲       ╱  in stereo field  │   │
│ │    ╰─────╯                     │   │
│ │                                │   │
│ └────────────────────────────────┘   │
│ W: 0.75  D: 0.40  Voices: 8/48      │
└──────────────────────────────────────┘
```

### Mode 1: Stereo Field (default)
- 2D prikaz aktivnih glasova u stereo polju
- X = pan (-1 do +1), Y = depth (front/back)
- Veličina tačke = volume, boja = bus
- Collision zone crveno obojena kad se glasovi preklapaju

### Mode 2: Energy Density
- Horizontalni bar-ovi po frequency bandovima
- Prikazuje gde je energetski "gust" signal
- AUREXIS automatski redistribuira energiju

### Mode 3: Signal Monitor
- Sparkline-ovi za top 4 ALE signala (winTier, momentum, etc.)
- Pokazuje kako se signali menjaju tokom sesije
- Threshold linije za ALE pravila

### Mode 4: Voice Cluster
- Pie chart glasova po busu
- Collision counter (koliko glasova se preklapa)
- Priority stack (koji glas bi se ugasio sledeći)

---

# 7. LOWER ZONE — SIMPLIFICATION

## 7.1 Stari Layout (20+ panela)

```
STAGES:    StageTrace │ EventTimeline │ Symbols │ StageIngest
EVENTS:    EventFolder│ CompositeEdit │ EventLog│ BatchExport
MIX:       BusMixer   │ BusMeters     │ AuxSends│ MiniMixer
DSP:       EQ         │ Compressor    │ Limiter │ Gate/Reverb
BAKE:      Validate   │ BakeAll       │ Package │ Stems
```

## 7.2 Novi Layout (3 taba, maksimalno 4 sub-taba)

```
TIMELINE:  StageTrace │ EventTimeline │ EventLog
MIX:       BusMixer   │ AuxSends      │ BusMeters
EXPORT:    Validate    │ Package       │ Stems    │ Batch
```

**Šta se desilo sa uklonjenim panelima?**

| Stari Panel | Nova Lokacija | Razlog |
|-------------|---------------|--------|
| Symbols | AUREXIS → Audio Slots (zamenjuje UltimateAudioPanel) | Integrisano |
| StageIngest | Plus Menu (modal) | Retko korišćen |
| EventFolder | Events Panel (desno) | Već tu |
| CompositeEdit | Events Panel (desno, inspector) | Već tu |
| BatchExport | EXPORT tab | Pomereno |
| EQ/Comp/Lim/Gate/Reverb | Channel Tab / Processor Editor Windows | DSP je per-track, ne globalan |
| MiniMixer | Uklonjen (redundantan sa BusMixer) | Duplikat |

## 7.3 Audio Slots — Integrisani u AUREXIS

UltimateAudioPanel (408 slotova, ~12 sekcija) se **ne uklanja** — menja se u AUREXIS-ov "AUDIO" mode.

AUREXIS Panel ima **mode toggle** u header-u:

```
┌──────────────────────────────┐
│ AUREXIS  [🧠 Intel│🎵 Audio] │  ← Mode toggle
│ ═══════════════════════════  │
│                              │
│ (Intel mode = Profile+Behav+ │
│  Tweak+Scope)                │
│                              │
│ (Audio mode = Audio Slots    │
│  sa Quick Assign, 12 sekcija)│
│                              │
└──────────────────────────────┘
```

- **Intel mode (🧠):** AUREXIS intelligence — Profile, Behavior, Tweak, Scope
- **Audio mode (🎵):** Audio assignment — UltimateAudioPanel sadržaj (408 slotova)
- **Keyboard shortcut:** `Tab` toggles between modes
- Panel **pamti scroll poziciju** za svaki mode nezavisno

---

# 8. AUREXIS ENGINE — Behavioral Parameter Resolution

## 8.1 Resolution Pipeline

Kada dizajner promeni BILO KOJI behavior slider:

```
Behavior Change (e.g., dynamics.escalation = 0.8)
    ↓
AurexisResolver.resolve(profile, behaviorOverrides)
    ↓
┌─────────────────────────────────────────────────────┐
│ FOR EACH underlying system:                          │
│                                                       │
│ 1. Start with profile base values                    │
│ 2. Apply behavior multipliers                        │
│ 3. Apply per-system tweak overrides                  │
│ 4. Apply lock constraints                            │
│ 5. Clamp to valid ranges                             │
│ 6. Push to provider/FFI                              │
└─────────────────────────────────────────────────────┘
    ↓
AleProvider.updateFromAurexis(config)
AutoSpatialProvider.updateFromAurexis(config)
RtpcSystemProvider.updateFromAurexis(config)
DuckingSystemProvider.updateFromAurexis(config)
WinTierConfig.updateFromAurexis(config)
ContainerService.updateFromAurexis(config)
```

## 8.2 Mapping Functions

Svaki behavior parametar ima **mapping function** koja konvertuje 0.0-1.0 u konkretne sistemske vrednosti:

```dart
// Primer: dynamics.escalation → ALE rules
double aleRuleThresholdFromEscalation(double escalation) {
  // escalation 0.0 → thresholds su visoki (teže se aktivira)
  // escalation 1.0 → thresholds su niski (lako se aktivira)
  return lerp(0.9, 0.2, escalation);
}

// Primer: dynamics.ducking → DuckingRule.duckAmountDb
double duckAmountFromDucking(double ducking) {
  // ducking 0.0 → -2dB (subtilno)
  // ducking 1.0 → -18dB (agresivno)
  return lerp(-2.0, -18.0, ducking);
}

// Primer: spatial.width → AutoSpatial.globalWidthScale
double widthScaleFromSpatialWidth(double width) {
  return lerp(0.15, 1.0, width);
}

// Primer: music.reactivity → ALE.stability.cooldownMs
int cooldownFromReactivity(double reactivity) {
  // reactivity 0.0 → 5000ms cooldown (spor)
  // reactivity 1.0 → 50ms cooldown (instant)
  return lerp(5000.0, 50.0, pow(1 - reactivity, 2)).round();
}
```

## 8.3 Lock System

Kada dizajner zaključa grupu (npr. Lock: Spatial):
- Profil promena NE menja spatial parametre
- Behavior slider promene u drugim grupama NE utiču na spatial
- Samo DIREKTNA promena spatial slidera menja spatial
- Visual: Lock ikona + dimmed overlay na zaključanim sliderima

```dart
class AurexisBehaviorLocks {
  bool spatialLocked = false;
  bool dynamicsLocked = false;
  bool musicLocked = false;
  bool variationLocked = false;

  // Per-system tweak locks
  final Set<String> lockedSystems = {};  // e.g., {'ale', 'ducking'}
}
```

---

# 9. NOVI LOWER ZONE TABOVI

## 9.1 Tab TIMELINE

```
Sub-tabs: Stage Trace │ Event Timeline │ Event Log
```

**Stage Trace** — Animated timeline through stage events (existing)
**Event Timeline** — Waveform timeline sa regions (existing)
**Event Log** — Real-time audio event log (existing)

## 9.2 Tab MIX

```
Sub-tabs: Bus Mixer │ Aux Sends │ Bus Meters
```

**Bus Mixer** — Horizontal fader strips per bus (existing)
**Aux Sends** — Send/return routing (existing)
**Bus Meters** — Real-time bus level meters (existing)

## 9.3 Tab EXPORT

```
Sub-tabs: Validate │ Package │ Stems │ Batch
```

**Validate** — Run all validation checks (existing)
**Package** — Export to Unity/Unreal/Howler (existing)
**Stems** — Export per-bus stems (existing)
**Batch** — Batch audio operations (existing)

---

# 10. JURISDICTION ENGINE — Regulatorna Inteligencija

## 10.1 Problem

UK Gambling Commission zabranila je celebratory audio na LDW (Loss Disguised as Win) spinovima — win < bet. Australija (Victoria/NSW), Ontario, i mnoge US jurisdikcije imaju specifične audio zahteve. GLI-11 standard definiše baseline. **Nijedan alat na tržištu ne automatizuje ovo.**

Dizajneri trenutno ručno prave separate audio build-ove per jurisdikcija — troši dane do nedelja.

## 10.2 Jurisdiction Profile Model

```dart
class JurisdictionProfile {
  final String id;              // 'uk_ukgc', 'au_victoria', 'us_nevada'
  final String name;            // 'United Kingdom (UKGC)'
  final String flag;            // '🇬🇧'
  final String regulatoryBody;  // 'UK Gambling Commission'
  final JurisdictionRules rules;
}

class JurisdictionRules {
  // ═══ LDW (Loss Disguised as Win) ═══
  final bool suppressLdwCelebration;        // true = no celebration when win < bet
  final LdwBehavior ldwBehavior;            // silence | reducedSfx | neutralTone

  // ═══ Celebration Duration ═══
  final int? maxCelebrationDurationMs;      // null = unlimited, UK: 8000ms
  final int? maxRollupDurationMs;           // null = unlimited
  final double? minSpinDurationSec;         // UK: 2.5 seconds minimum

  // ═══ Audio Content ═══
  final bool allowLoopingWinAudio;          // Some jurisdictions restrict
  final bool allowEscalatingPitch;          // Pitch escalation restrictions
  final double? maxWinAudioDb;              // Peak loudness ceiling

  // ═══ Responsible Gaming ═══
  final bool requireFatigueMitigation;      // Mandatory fatigue reduction
  final int? mandatoryFatigueOnsetMinutes;  // e.g., 30 min
  final bool requireAudioMuteOption;        // Player must be able to mute

  // ═══ Export ═══
  final List<String> requiredDocumentation; // Required compliance docs
  final String? auditStandard;              // 'GLI-11', 'BMM-100'
}

enum LdwBehavior { silence, reducedSfx, neutralTone, standard }
```

## 10.3 Built-in Jurisdictions (9)

| # | Jurisdiction | ID | Flag | Key Rules |
|---|-------------|-----|------|-----------|
| 1 | **UK (UKGC)** | `uk_ukgc` | 🇬🇧 | LDW suppression, 2.5s min spin, 8s max celebration |
| 2 | **Malta (MGA)** | `mt_mga` | 🇲🇹 | Standard EU, fatigue recommended |
| 3 | **Nevada (NGC)** | `us_nevada` | 🇺🇸 | GLI-11 compliance |
| 4 | **New Jersey (DGE)** | `us_nj` | 🇺🇸 | GLI-11 + NJ-specific |
| 5 | **Ontario (AGCO)** | `ca_ontario` | 🇨🇦 | LDW awareness, RG features |
| 6 | **Victoria (VCGLR)** | `au_victoria` | 🇦🇺 | LDW suppression, strict limits |
| 7 | **NSW (L&GNSW)** | `au_nsw` | 🇦🇺 | Similar to Victoria |
| 8 | **Isle of Man (GSC)** | `im_gsc` | 🇮🇲 | UK-adjacent rules |
| 9 | **Curacao (GCB)** | `cw_gcb` | 🇨🇼 | Minimal restrictions |

**Default:** `Unrestricted` (no jurisdiction rules applied — development mode)

## 10.4 LDW Detection

```dart
/// Called on every spin result evaluation
class LdwDetector {
  /// Returns true if this spin is an LDW
  static bool isLdw(double winAmount, double betAmount) {
    return winAmount > 0 && winAmount < betAmount;
  }

  /// Returns modified audio behavior for current jurisdiction
  static AudioBehavior getAudioBehavior({
    required double winAmount,
    required double betAmount,
    required JurisdictionRules rules,
  }) {
    if (!isLdw(winAmount, betAmount)) {
      return AudioBehavior.normal;  // Not LDW — play as designed
    }

    if (!rules.suppressLdwCelebration) {
      return AudioBehavior.normal;  // Jurisdiction allows LDW audio
    }

    return switch (rules.ldwBehavior) {
      LdwBehavior.silence     => AudioBehavior.mute,
      LdwBehavior.reducedSfx  => AudioBehavior.reduced,
      LdwBehavior.neutralTone => AudioBehavior.neutral,
      _                       => AudioBehavior.normal,
    };
  }
}
```

**Integration u EventRegistry:**
```
EVALUATE_WINS → LdwDetector.isLdw(win, bet)
    ↓ isLdw=true && jurisdiction.suppressLdwCelebration
    ↓
Suppress: WIN_PRESENT_*, ROLLUP_*, BIG_WIN_*
Replace:  WIN_PRESENT_NEUTRAL (simple coin count, no celebration)
Log:      "LDW detected: win=2.50, bet=5.00 — celebration suppressed per UK UKGC"
```

## 10.5 Celebration Duration Limiter

```dart
class CelebrationLimiter {
  final int? maxDurationMs;
  Timer? _fadeOutTimer;

  void startCelebration(int tierDurationMs) {
    if (maxDurationMs == null) return;  // No limit

    final effectiveDuration = tierDurationMs.clamp(0, maxDurationMs!);

    if (tierDurationMs > maxDurationMs!) {
      // Schedule fade-out at limit
      _fadeOutTimer = Timer(
        Duration(milliseconds: maxDurationMs! - 500),  // 500ms fade
        () => _fadeOutAllCelebrationAudio(),
      );
    }
  }
}
```

## 10.6 UI Integration

Jurisdiction dropdown u PROFILE sekciji — **jedna selekcija, sve automatski:**

```
┌─ Jurisdiction ──────────────────────┐
│ 🌍 ▾ UK (UKGC)                     │
│                                      │
│ Rules Active:                        │
│  ✅ LDW suppression                 │
│  ✅ Min spin: 2.5s                  │
│  ✅ Max celebration: 8s             │
│  ✅ Fatigue mitigation: mandatory   │
│                                      │
│ [Multi-Jurisdiction Export ↗]        │
└──────────────────────────────────────┘
```

**Multi-Jurisdiction Export:**
- Jedan projekat → checkbox lista jurisdikcija
- Export generiše ODVOJENE pakete per jurisdikcija
- Svaki paket sadrži samo audio koje ta jurisdikcija dozvoljava
- Manifest documentiše šta je suppressed i zašto

## 10.7 Spin Throughput Calculator

```
Prosečna kalkulacija:
  Spin duration:    2.5s (min per UK)
  Win evaluation:   0.3s
  Celebration avg:  3.2s (capped at 8s)
  Idle time:        0.5s
  ═══════════════════════
  Average cycle:    6.5s
  Spins per hour:   ~554

  ⚠️ BIG WIN+ celebrations reduce to ~480 spins/hour
```

---

# 11. MEMORY BUDGET BAR — Always-Visible Resource Monitor

## 11.1 Koncept

Tanka traka (16px visine) na dnu AUREXIS panela — UVEK vidljiva, nikad ne blokira rad.

```
┌─────────────────────────────────┐
│ AUREXIS Panel Content           │
│ ...                             │
├─────────────────────────────────┤
│ 📱 ████████░░ 4.2/6.0 MB (70%) │  ← Memory Budget Bar
└─────────────────────────────────┘
```

## 11.2 Platform Budgets

| Platform | Default Budget | Adjustable | Notes |
|----------|---------------|------------|-------|
| Mobile (default) | 6 MB | ✅ | Playtika/SciPlay standard |
| Mobile Light | 3 MB | ✅ | Low-end devices |
| Web/HTML5 | 4 MB | ✅ | Browser memory constraints |
| Desktop | 24 MB | ✅ | Generous but not unlimited |
| Cabinet | 16 MB | ✅ | Dedicated hardware |

## 11.3 Memory Calculation

```dart
class MemoryBudgetCalculator {
  /// Calculate total audio memory footprint
  static MemoryBreakdown calculate(List<AudioAssignment> assignments) {
    double totalBytes = 0;
    final breakdown = <String, double>{};

    for (final assignment in assignments) {
      final fileInfo = getAudioFileInfo(assignment.audioPath);
      final bytes = fileInfo.sampleRate * fileInfo.channels
                    * fileInfo.bitDepth / 8 * fileInfo.durationSeconds;
      totalBytes += bytes;
      breakdown[assignment.section] =
          (breakdown[assignment.section] ?? 0) + bytes;
    }

    return MemoryBreakdown(
      totalBytes: totalBytes,
      perSection: breakdown,
      budget: currentPlatformBudget,
    );
  }
}
```

## 11.4 Visual States

| Usage | Color | Indicator |
|-------|-------|-----------|
| 0-60% | Zelena `#40FF90` | Normal |
| 60-80% | Žuta `#FFD700` | "Getting close" |
| 80-95% | Narandžasta `#FF9040` | "Optimize soon" |
| 95-100% | Crvena `#FF4060` | "Over budget!" |

## 11.5 Click → Breakdown Popup

```
┌─ Memory Breakdown (📱 Mobile: 6.0 MB) ──┐
│                                            │
│  Base Game Loop   ████████░░  1.8 MB (30%) │
│  Win Presentation ██████░░░░  1.4 MB (23%) │
│  Music & Ambience █████░░░░░  1.2 MB (20%) │
│  Free Spins       ███░░░░░░░  0.6 MB (10%) │
│  Symbols & Lands  ██░░░░░░░░  0.5 MB  (8%) │
│  UI & System      ██░░░░░░░░  0.4 MB  (7%) │
│  Other            █░░░░░░░░░  0.3 MB  (5%) │
│                                            │
│  ═══════════════════════════════           │
│  TOTAL: 4.2 / 6.0 MB                      │
│                                            │
│  💡 Suggestions:                           │
│  • Convert music to 22kHz mono → -1.2 MB  │
│  • Use MP3 for UI sounds → -0.2 MB        │
│  • Share reel_stop across reels → -0.3 MB  │
│                                            │
│  [Apply All Suggestions] [Dismiss]         │
└────────────────────────────────────────────┘
```

**Suggestions su konkretne i actionable** — "Apply" ih primenjuje automatski.

---

# 12. COVERAGE HEATMAP — Visual Gap Detection

## 12.1 Koncept

Peti vizualizacioni mod u SCOPE sekciji — overlay na slot mockup koji pokazuje gde FALI audio.

## 12.2 SCOPE Modes (Updated — 6 modes)

```
┌──────────────────────────────────────┐
│ SCOPE                                 │
│ ◉Stereo ○Energy ○Signal ○Voices      │
│ ○Coverage ○Cabinet                    │  ← 2 nova moda
│ ┌────────────────────────────────┐   │
│ │                                │   │
│ │  Coverage Heatmap:             │   │
│ │                                │   │
│ │  ┌───┬───┬───┬───┬───┐       │   │
│ │  │🟢│🟢│🔴│🟢│🟡│ Reel Stop  │   │
│ │  ├───┼───┼───┼───┼───┤       │   │
│ │  │🟢│🟡│🟢│🟢│🔴│ Symbol Land│   │
│ │  ├───┼───┼───┼───┼───┤       │   │
│ │  │🟢│🟢│🟢│🟢│🟢│ Win Lines  │   │
│ │  └───┴───┴───┴───┴───┘       │   │
│ │                                │   │
│ │  Base Game:  44/44 (100%) 🟢  │   │
│ │  Symbols:    38/46  (83%) 🟡  │   │
│ │  Win:        35/41  (85%) 🟡  │   │
│ │  Free Spins: 12/24  (50%) 🔴  │   │
│ │  Bonus:       8/32  (25%) 🔴  │   │
│ │  Jackpots:    0/26   (0%) 🔴  │   │
│ │                                │   │
│ │  TOTAL: 246/408 (60%)          │   │
│ │  [Show Missing →]              │   │
│ └────────────────────────────────┘   │
└──────────────────────────────────────┘
```

## 12.3 Heatmap Colors

| Status | Color | Meaning |
|--------|-------|---------|
| 🟢 Full | `#40FF90` | Stage ima dedicated audio |
| 🟡 Fallback | `#FFD700` | Stage koristi fallback (REEL_STOP umesto REEL_STOP_3) |
| 🔴 Missing | `#FF4060` | Stage NEMA audio — praznina |
| ⚪ N/A | `#555555` | Stage nije relevantan za ovaj game type |

## 12.4 "Show Missing" Navigation

Klik na "Show Missing →" filtrira Audio mode da prikaže SAMO nedodeljene slotove. Dizajner može odmah da popuni rupe.

## 12.5 Smart Suggestions

```dart
class CoverageSuggestion {
  final String missingStage;      // 'REEL_STOP_3'
  final String? suggestedAudio;   // 'reel_stop_2.wav' (najbliži)
  final String reason;            // 'Similar to REEL_STOP_2 (same section)'
  final double confidence;        // 0.0-1.0
}
```

Kad dizajner klikne na crvenu zonu:
1. Skok na taj slot u Audio mode
2. Suggestion popup: "Koristi reel_stop_2.wav? (90% match)"
3. One-click apply ili ručni izbor

---

# 13. CABINET SIM — Casino Floor Monitoring

## 13.1 Koncept

Šesti vizualizacioni mod u SCOPE — simulira kako audio zvuči na specifičnom hardveru/okruženju.

## 13.2 Monitoring Modes (3)

```
┌──────────────────────────────────────┐
│ SCOPE → Cabinet Sim                   │
│                                       │
│ ◉ 🔊 Cabinet  ○ 🎧 Studio  ○ 📱 Mobile │
│                                       │
│ ┌────────────────────────────────┐   │
│ │                                │   │
│ │  CABINET SIMULATION            │   │
│ │                                │   │
│ │  Speaker: [IGT CrystalDual ▾] │   │
│ │  Ambient: [Casino Floor 85dBA] │   │
│ │                                │   │
│ │  Freq Response:                │   │
│ │  ╭──────────────╮             │   │
│ │  │    ╱────╲    │ 200Hz-12kHz│   │
│ │  │───╱      ╲───│             │   │
│ │  ╰──────────────╯             │   │
│ │                                │   │
│ │  Headroom: -3.2 dB            │   │
│ │  Peak: -1.8 dBTP              │   │
│ │                                │   │
│ │  ⚠️ Win SFX exceeds cabinet   │   │
│ │     speaker range at 14kHz     │   │
│ │                                │   │
│ └────────────────────────────────┘   │
└──────────────────────────────────────┘
```

## 13.3 Speaker Profiles (Built-in)

| # | Profile | Freq Range | Notes |
|---|---------|------------|-------|
| 1 | IGT CrystalDual 27 | 250Hz-10kHz | Standard IGT cabinet |
| 2 | IGT CrystalDual 43 | 200Hz-12kHz | Large IGT cabinet |
| 3 | Aristocrat MarsX | 300Hz-11kHz | Aristocrat standard |
| 4 | Aristocrat Arc | 200Hz-13kHz | Premium Aristocrat |
| 5 | Generic 2.1 Cabinet | 180Hz-14kHz | Typical aftermarket |
| 6 | Headphone Reference | 20Hz-20kHz | Flat reference |
| 7 | Mobile Phone Speaker | 500Hz-8kHz | Worst case |
| 8 | Tablet Speaker | 300Hz-12kHz | Mid-range |
| 9 | Custom | Configurable | User-defined |

## 13.4 Ambient Noise Overlay

```dart
enum AmbientNoiseProfile {
  casinoFloor,        // 85 dBA pink noise
  casinoFloorBusy,    // 90 dBA
  quietRoom,          // 40 dBA
  mobileOutdoor,      // 70 dBA
  mobileTransit,      // 80 dBA
  none,               // Silent (studio)
}
```

Uključivanje ambient noise-a dodaje odgovarajući nivo pink noise-a u monitoring signal — ne u export. Dizajner odmah čuje da li su win zvukovi dovoljno glasni da se čuju na casino floor-u.

## 13.5 Implementation

**NIL impakt na export** — Cabinet Sim je ČISTO monitoring alat:
- EQ filter koji simulira speaker response (primenjuje se samo na monitoring output)
- Pink noise generator za ambient (mixed samo u monitoring)
- Toggle: ON/OFF, instant
- Ne modifikuje nijedan audio fajl

---

# 14. COMPLIANCE REPORT — One-Click Regulatory Documentation

## 14.1 Koncept

Dugme u EXPORT tabu koje generiše kompletnu compliance dokumentaciju za GLI/BMM submission. **10 sekundi umesto 5 dana ručnog rada.**

## 14.2 Report Contents

```
FluxForge Studio — Compliance Report
═══════════════════════════════════════

Game: Zeus Thunder
Jurisdiction: UK (UKGC)
Generated: 2026-02-27 14:30:00 UTC
AUREXIS Profile: High Volatility Thriller
Tool Version: FluxForge Studio 1.0.0

═══ 1. AUDIO MANIFEST ════════════════

Total Files: 287
Total Size: 4.2 MB (Mobile), 18.7 MB (Desktop)
Formats: WAV 16-bit (SFX), FLAC (Music), MP3 128kbps (UI)

Stage Coverage: 246/408 (60.3%)
  Base Game:     44/44 (100%) ✅
  Win Present:   35/41  (85%) ⚠️
  Free Spins:    12/24  (50%) ⚠️
  [Full list...]

═══ 2. LDW COMPLIANCE ═══════════════

LDW Detection: ENABLED
LDW Behavior: Reduced SFX (neutral tone)
Simulation: 10,000 spins tested
  LDW Occurrence: 34.2% of winning spins
  All LDW spins: Celebration SUPPRESSED ✅
  Verification: Deterministic (seed: 0xA7B3C901)

═══ 3. CELEBRATION DURATIONS ════════

| Tier | Avg Duration | Max Duration | Limit | Status |
|------|-------------|-------------|-------|--------|
| SMALL | 1.5s | 2.0s | 8.0s | ✅ |
| BIG | 2.5s | 4.0s | 8.0s | ✅ |
| SUPER | 4.0s | 6.0s | 8.0s | ✅ |
| MEGA | 7.0s | 7.8s | 8.0s | ✅ |
| EPIC | 7.5s | 8.0s | 8.0s | ✅ |
| ULTRA | 8.0s | 8.0s | 8.0s | ✅ |

Min Spin Duration: 2.8s (limit: 2.5s) ✅
Avg Spins/Hour: 520 (with celebrations)

═══ 4. LOUDNESS ANALYSIS ════════════

Master Bus: -14.2 LUFS integrated, -2.1 dBTP ✅
Music Bus: -18.4 LUFS, -6.2 dBTP ✅
SFX Bus: -11.8 LUFS, -1.2 dBTP ✅
Win Bus: -8.5 LUFS, -0.5 dBTP ⚠️ (close to limit)

═══ 5. FATIGUE MITIGATION ═══════════

Enabled: YES ✅
Onset: 30 minutes
HF Attenuation: -3dB max
Transient Smoothing: Active after 45 min
Session Simulation (2h): PASS ✅
  [Fatigue graph attached]

═══ 6. DETERMINISM VERIFICATION ═════

100 identical sequences tested with seed 0xA7B3C901
Result: ALL 100 runs produce identical output ✅
Micro-variation: Deterministic (seeded) ✅
Random containers: Seeded (reproducible) ✅

═══ 7. RESPONSIBLE GAMING ═══════════

Mute Option: Available ✅
Volume Control: Available ✅
Audio-Off Mode: Functional ✅
No Audio-Only Rewards: Verified ✅

═══ 8. CHANGE LOG ═══════════════════

This submission vs previous (v1.2):
  + 12 new audio files added
  - 3 audio files replaced
  ~ 5 volume levels adjusted
  [Detailed diff attached]
```

## 14.3 Export Formats

| Format | Use Case |
|--------|----------|
| PDF | Human-readable submission to lab |
| JSON | Machine-readable for automated testing |
| CSV | Audio manifest for spreadsheet review |
| HTML | Interactive report with embedded audio players |

## 14.4 Diff Report

Automatski generiše diff između verzija:
```dart
class ComplianceReport {
  static ComplianceDiff generateDiff(
    ComplianceReport previous,
    ComplianceReport current,
  ) {
    return ComplianceDiff(
      addedFiles: current.files.difference(previous.files),
      removedFiles: previous.files.difference(current.files),
      changedVolumes: _compareVolumes(previous, current),
      changedStages: _compareStages(previous, current),
      newLdwBehavior: current.ldwResults != previous.ldwResults,
    );
  }
}
```

---

# 15. RE-THEME WIZARD — Audio Re-Skinning za 10 Minuta

## 15.1 Problem

Playtika, SciPlay i drugi mobile produceri re-skinuju istu igru 3-4x sa različitim temama (Egyptian → Greek → Asian → Norse). Matematika ostaje ista, audio se menja. Ručna zamena 200+ asset-a traje 2-3 nedelje.

## 15.2 Wizard Flow (3 koraka)

```
┌─ RE-THEME WIZARD ──────────────────────────────────┐
│                                                      │
│  Step 1: Source                                      │
│  ┌──────────────────────────────────────────┐       │
│  │ Current Project: "Zeus Thunder"           │       │
│  │ Theme: Greek Mythology                    │       │
│  │ Audio Files: 287 assigned                 │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  Step 2: Target Theme Audio                          │
│  ┌──────────────────────────────────────────┐       │
│  │ 📁 Select Folder: /audio/egyptian_theme/  │       │
│  │ Files Found: 312 audio files              │       │
│  │ Auto-Matched: 241/287 (84%)               │       │
│  │ Unmatched: 46 files need manual assign     │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  Step 3: Review & Apply                              │
│  ┌──────────────────────────────────────────┐       │
│  │ ✅ spin_start.wav → egypt_spin_start.wav  │       │
│  │ ✅ reel_stop.wav → egypt_reel_stop.wav    │       │
│  │ ✅ win_big.wav → egypt_win_big.wav        │       │
│  │ ⚠️ zeus_voice.wav → ??? (no match)       │       │
│  │ ⚠️ thunder_sfx.wav → ??? (no match)      │       │
│  │                                            │       │
│  │ Match Strategy: [Name Pattern ▾]           │       │
│  │ Fuzzy Threshold: [70% ▾]                   │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  [Apply Theme] [Export Mapping JSON] [Cancel]        │
└──────────────────────────────────────────────────────┘
```

## 15.3 Matching Strategies

```dart
enum MatchStrategy {
  namePattern,    // {theme}_spin_start → {newTheme}_spin_start
  stageMapping,   // Match by assigned stage name
  folderStructure,// Match by relative folder position
  manual,         // All manual assignment
}
```

**Name Pattern Matching:**
```
Source: zeus_spin_start.wav    → Stage: SPIN_START
Target: egypt_spin_start.wav   → Match by suffix: "spin_start"
Confidence: 95%

Source: zeus_thunder_boom.wav  → Stage: WILD_LAND
Target: egypt_scarab_glow.wav  → No name match, try stage: WILD_LAND
Target has: egypt_wild_land.wav → Match by stage name!
Confidence: 80%
```

## 15.4 Output

- **Novi projekat** sa istim stage mapping-om ali novim audio fajlovima
- **Gap report:** lista stage-ova koji nemaju match u novoj temi
- **Mapping JSON:** export/import za ponovnu upotrebu
- **AUREXIS profil ostaje isti** — samo audio se menja, intelligence ostaje

## 15.5 Reverse Re-Theme

Mapping JSON može da se primeni u oba smera:
```
Greek → Egyptian (forward)
Egyptian → Greek (reverse)
```

---

# 16. AUDIT TRAIL — Automatic Change Tracking

## 16.1 Princip

Svaka audio promena se automatski loguje u pozadini. **Zero UI surface** dok ne zatreba — potpuno nevidljiv za dizajnera.

## 16.2 Audit Log Model

```dart
class AuditLogEntry {
  final DateTime timestamp;
  final String userId;          // Machine username or configured name
  final AuditAction action;
  final String targetStage;     // e.g., 'SPIN_START'
  final String? oldValue;       // e.g., 'old_spin.wav'
  final String? newValue;       // e.g., 'new_spin.wav'
  final String? reason;         // Optional user comment
  final String projectVersion;  // e.g., 'v1.3'
}

enum AuditAction {
  audioAssigned,        // New audio file assigned to stage
  audioRemoved,         // Audio file removed from stage
  audioReplaced,        // Audio file replaced
  volumeChanged,        // Volume level changed
  panChanged,           // Pan position changed
  profileChanged,       // AUREXIS profile changed
  jurisdictionChanged,  // Jurisdiction changed
  behaviorChanged,      // Behavior slider changed
  tweakChanged,         // Per-system tweak changed
  projectLocked,        // Project locked for submission
  projectUnlocked,      // Project unlocked
  exportGenerated,      // Export package created
  reportGenerated,      // Compliance report created
}
```

## 16.3 Storage

```dart
class AuditTrailService {
  static final instance = AuditTrailService._();

  final List<AuditLogEntry> _entries = [];
  static const _maxEntries = 10000;  // Ring buffer

  /// Automatically called by providers on any change
  void log(AuditLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    _persistToFile();  // Async write to .ffaudit file
  }

  /// Export for compliance
  String exportCsv() {
    // timestamp, user, action, stage, old_value, new_value, reason, version
  }

  String exportJson() { ... }

  /// Diff between two project versions
  AuditDiff diffVersions(String versionA, String versionB) { ... }
}
```

## 16.4 Project Lock

```dart
class ProjectLock {
  bool isLocked = false;
  String? lockedBy;
  DateTime? lockedAt;
  String? lockReason;  // e.g., 'Submitted to GLI for Zeus Thunder v1.3'

  /// Lock project — all audio changes blocked
  void lock({required String reason}) {
    isLocked = true;
    lockedBy = Platform.localHostname;
    lockedAt = DateTime.now();
    lockReason = reason;
    AuditTrailService.instance.log(AuditLogEntry(
      action: AuditAction.projectLocked,
      reason: reason,
    ));
  }

  /// Unlock requires explicit action + reason
  void unlock({required String reason}) {
    isLocked = false;
    AuditTrailService.instance.log(AuditLogEntry(
      action: AuditAction.projectUnlocked,
      reason: reason,
    ));
  }
}
```

**Kad je projekat zaključan:**
- SVE audio assignment kontrole su disabled (grayed out)
- Banner na vrhu: "🔒 Project locked: Submitted to GLI (2026-02-27)"
- Unlock dugme zahteva potvrdu + razlog

## 16.5 Integration Points

Audit Trail hooks automatski u:
- `MiddlewareProvider` — event/layer changes
- `SlotLabProjectProvider` — symbol/music audio assignments
- `AurexisProvider` — profile/behavior/jurisdiction changes
- `UltimateAudioPanel` — direct slot assignments
- `DropTargetWrapper` — drag-drop assignments

**Zero overhead za dizajnera** — sve radi u pozadini. Jedini surface je u EXPORT tabu: "📋 Export Audit Trail" dugme.

---

# 17. UPDATED LOWER ZONE — EXPORT Tab

## 17.1 EXPORT Tab (Updated sa novim feature-ima)

```
Sub-tabs: Validate │ Package │ Stems │ Report │ Re-Theme │ Batch
```

| Sub-tab | Content | New? |
|---------|---------|------|
| Validate | Run all validation checks | Existing |
| Package | Export to Unity/Unreal/Howler per jurisdiction | Updated |
| Stems | Export per-bus stems | Existing |
| **Report** | **Compliance Report generator** | **NEW** |
| **Re-Theme** | **Audio re-skinning wizard** | **NEW** |
| Batch | Batch audio operations | Existing |
| *(footer)* | *📋 Export Audit Trail* | **NEW** |

---

# 18. IMPLEMENTATION PLAN (UPDATED)

## Phase 1: AUREXIS Provider + Profile System (~800 LOC)

```
flutter_ui/lib/providers/aurexis_provider.dart
flutter_ui/lib/models/aurexis_models.dart
flutter_ui/lib/data/aurexis_profiles/   (12 JSON profiles)
```

- `AurexisProvider` (ChangeNotifier)
- `AurexisProfile` model sa serialization
- `AurexisBehaviorConfig` model (12 behavior params)
- `AurexisResolver` — behavior → system mapping engine
- Profile load/save/export/import
- GetIt Layer 5.6 registration

## Phase 2: AUREXIS Panel Widget (~1,200 LOC)

```
flutter_ui/lib/widgets/aurexis/
  aurexis_panel.dart           — Main panel (mode toggle + 4 sekcije)
  aurexis_profile_section.dart — Profile dropdown + intensity + dials + jurisdiction
  aurexis_behavior_section.dart — 4 behavior groups × 3 sliders
  aurexis_tweak_section.dart   — System picker + compact editors
  aurexis_scope_section.dart   — 6 visualization modes (incl. Coverage + Cabinet)
```

- Replace UltimateAudioPanel position (levo, 280px)
- Intel/Audio mode toggle
- All 4 sections collapsible
- Jurisdiction dropdown u PROFILE sekciji
- Memory Budget Bar (16px) na dnu panela
- Real-time preview on slider change

## Phase 3: Behavior Resolution Engine (~500 LOC)

```
flutter_ui/lib/services/aurexis_resolver.dart
```

- Mapping functions (12 behaviors → 11 systems)
- Lock system
- Profile interpolation (A/B morph)
- Debounced push to providers (50ms)

## Phase 4: System Integration (~600 LOC)

```
Provider updates:
  ale_provider.dart            +updateFromAurexis()
  auto_spatial_provider.dart   +updateFromAurexis()
  rtpc_system_provider.dart    +updateFromAurexis()
  ducking_system_provider.dart +updateFromAurexis()
  slot_lab_project_provider.dart +updateFromAurexis() (win tiers)
  container_service.dart       +updateFromAurexis()
```

- Each provider gains `updateFromAurexis(AurexisSystemConfig)` method
- Config applied as "base + override" pattern
- Manual tweaks preserved as overrides

## Phase 5: Lower Zone Consolidation (~400 LOC)

```
lower_zone_types.dart   — New SlotLabSuperTab enum (3 values)
slotlab_lower_zone_controller.dart — Simplified state
slotlab_lower_zone_widget.dart — 3 tabs instead of 5
```

- Remove DSP super-tab (moved to processor editor windows)
- Remove STAGES super-tab's StageIngest (modal) and Symbols (AUREXIS Audio mode)
- Merge remaining into TIMELINE / MIX / EXPORT (with Report + Re-Theme sub-tabs)

## Phase 6: Jurisdiction Engine (~650 LOC)

```
flutter_ui/lib/models/jurisdiction_models.dart     (~250 LOC)
flutter_ui/lib/services/jurisdiction_service.dart   (~250 LOC)
flutter_ui/lib/services/ldw_detector.dart           (~150 LOC)
```

- `JurisdictionProfile` model + `JurisdictionRules` (9 built-in jurisdictions)
- `JurisdictionService` singleton — active jurisdiction, rule enforcement
- `LdwDetector` — win < bet detection, audio behavior mapping
- `CelebrationLimiter` — auto fade-out at max duration
- Spin Throughput Calculator
- Multi-Jurisdiction Export (per-jurisdiction audio packages)
- Hook into EventRegistry for LDW suppression

## Phase 7: Memory Budget Bar + Coverage Heatmap (~500 LOC)

```
flutter_ui/lib/services/memory_budget_service.dart  (~200 LOC)
flutter_ui/lib/widgets/aurexis/memory_budget_bar.dart (~120 LOC)
flutter_ui/lib/widgets/aurexis/coverage_heatmap.dart  (~180 LOC)
```

- `MemoryBudgetCalculator` — per-platform budget tracking (Mobile/Web/Desktop/Cabinet)
- Always-visible 16px bar at bottom of AUREXIS panel
- Click → breakdown popup with actionable suggestions
- Coverage Heatmap — SCOPE mode 5, grid overlay, per-section percentages
- "Show Missing" navigation → filters Audio mode to unassigned slots
- `CoverageSuggestion` — fuzzy matching for gap filling

## Phase 8: Cabinet Sim + Compliance Report (~550 LOC)

```
flutter_ui/lib/services/cabinet_sim_service.dart     (~180 LOC)
flutter_ui/lib/services/compliance_report_service.dart (~250 LOC)
flutter_ui/lib/widgets/aurexis/cabinet_sim_panel.dart  (~120 LOC)
```

- Cabinet Sim — SCOPE mode 6, 9 speaker profiles, frequency response EQ filter
- Ambient noise overlay (pink noise @ configurable dBA)
- Monitoring-only — zero impact on export
- `ComplianceReportService` — one-click report generation
- 8-section report template (manifest, LDW, durations, loudness, fatigue, determinism, responsible gaming, change log)
- 4 export formats: PDF, JSON, CSV, HTML
- Diff report between project versions

## Phase 9: Re-Theme Wizard + Audit Trail (~650 LOC)

```
flutter_ui/lib/widgets/aurexis/retheme_wizard.dart    (~250 LOC)
flutter_ui/lib/services/audit_trail_service.dart      (~250 LOC)
flutter_ui/lib/models/audit_models.dart               (~150 LOC)
```

- Re-Theme Wizard — 3-step flow (source → target folder → review & apply)
- 4 match strategies (namePattern, stageMapping, folderStructure, manual)
- Fuzzy matching with configurable threshold
- Mapping JSON export/import + reverse re-theme
- `AuditTrailService` — automatic background change logging
- `AuditLogEntry` model + `AuditAction` enum (13 action types)
- Ring buffer (10,000 entries) + async persistence (.ffaudit file)
- `ProjectLock` — freeze project for submission
- Integration hooks into 5 providers

## Phase 10: Dead Code Cleanup (~negative LOC)

- Remove `_buildBottomPanel()` dead code
- Remove `_buildRightPanel()` dead code
- Remove `_BottomPanelTab` unused enum
- Remove scattered panel references

---

# 19. ESTIMATED SIZE (UPDATED)

| Phase | New LOC | Removed LOC | Net |
|-------|---------|-------------|-----|
| Phase 1: Provider + Models | ~800 | 0 | +800 |
| Phase 2: Panel Widget | ~1,200 | ~400 (UltimateAudioPanel integration) | +800 |
| Phase 3: Resolver Engine | ~500 | 0 | +500 |
| Phase 4: System Integration | ~600 | 0 | +600 |
| Phase 5: LZ Consolidation | ~400 | ~600 (removed panels/tabs) | -200 |
| **Phase 6: Jurisdiction Engine** | **~650** | 0 | **+650** |
| **Phase 7: Budget + Coverage** | **~500** | 0 | **+500** |
| **Phase 8: Cabinet + Report** | **~550** | 0 | **+550** |
| **Phase 9: Re-Theme + Audit** | **~650** | 0 | **+650** |
| Phase 10: Dead Code | 0 | ~800 | -800 |
| **TOTAL** | **~5,850** | **~1,800** | **+4,050** |

**Delta od originalnog plana:** +2,350 LOC neto (7 novih feature-a)

---

# 20. KEY INTERACTIONS

## 20.1 Profil Change Flow

```
User selects "Megaways Chaos" profile
    ↓
AurexisProvider.setProfile('megaways_chaos')
    ↓
Load profile JSON → AurexisProfile
    ↓
Apply intensity scaling to all behaviors
    ↓
Check locks (skip locked groups)
    ↓
AurexisResolver.resolveAll(profile, locks, tweaks)
    ↓
Push to 6+ providers simultaneously
    ↓
All UI updates via notifyListeners()
    ↓
Audio changes audible within 50ms
```

## 20.2 Behavior Slider Change Flow

```
User drags dynamics.escalation slider to 0.85
    ↓
AurexisProvider.setBehavior('dynamics.escalation', 0.85)
    ↓
AurexisResolver.resolveGroup('dynamics', currentProfile, locks, tweaks)
    ↓
Maps to:
  - WinTierConfig.audioIntensity = 1.0 + (0.85 * 0.5) = 1.425
  - RTPC curve steepness = lerp(1.0, 3.0, 0.85) = 2.55
  - ALE rule thresholds *= 0.15 (very sensitive)
  - Cascade pitch step = lerp(0.02, 0.10, 0.85) = 0.088
    ↓
Push changes to relevant providers
    ↓
Next spin: audio is noticeably more aggressive
```

## 20.3 GDD Import → Auto-Profile Flow

```
GDD Import: { volatility: "extreme", mechanic: "megaways", features: 5 }
    ↓
AurexisProvider.autoSelectProfile(gdd)
    ↓
Score each profile against GDD:
  - "Megaways Chaos": volatility=extreme (match), mechanic=megaways (match) → 95%
  - "High Vol Thriller": volatility=high (close), mechanic=any → 70%
  - "Standard Video": volatility=medium → 30%
    ↓
Select best: "Megaways Chaos"
    ↓
Auto-adjust intensity from GDD volatility: 0.9
    ↓
Auto-derive Quick Dials:
  - Volatility: extreme → 0.95
  - Tension: 5 features → 0.8 (more features = more tension points)
  - Energy: RTP 96.5% → 0.6 (higher RTP → moderate energy cycling)
    ↓
Apply profile with auto-derived overrides
```

---

# 21. AUREXIS PROFILE JSON FORMAT

```json
{
  "id": "megaways_chaos",
  "name": "Megaways Chaos",
  "version": 2,
  "category": "megaways",
  "description": "Maximum audio intelligence for dynamic reel slots",
  "intensity": 0.9,
  "jurisdiction": "uk_ukgc",
  "quickDials": {
    "volatility": 0.95,
    "tension": 0.8,
    "energy": 0.6
  },
  "behavior": {
    "spatial": { "width": 0.85, "depth": 0.7, "movement": 0.65 },
    "dynamics": { "escalation": 0.9, "ducking": 0.7, "fatigue": 0.5 },
    "music": { "reactivity": 0.8, "layerBias": 0.5, "transition": 0.4 },
    "variation": { "panDrift": 0.4, "widthVar": 0.3, "timingVar": 0.5 }
  },
  "systemOverrides": {
    "ale": {
      "stability": { "cooldownMs": 300, "holdMs": 1000 },
      "rules": [
        { "signal": "winTier", "op": "gt", "value": 3, "action": "setLevel", "actionValue": 4 },
        { "signal": "cascadeDepth", "op": "gt", "value": 2, "action": "stepUp" }
      ]
    },
    "ducking": {
      "rules": [
        { "source": "sfx", "target": "music", "amount": -9, "attack": 30, "release": 600 }
      ]
    },
    "winTiers": {
      "preset": "highVolatility",
      "bigWinThreshold": 25
    }
  },
  "jurisdictionOverrides": {
    "au_victoria": {
      "behavior": {
        "dynamics": { "escalation": 0.5, "fatigue": 0.8 }
      }
    },
    "us_nevada": {
      "behavior": {
        "dynamics": { "escalation": 0.9, "fatigue": 0.3 }
      }
    }
  },
  "platformOverrides": {
    "mobile": {
      "behavior": {
        "spatial": { "width": 0.5, "movement": 0.3 },
        "dynamics": { "fatigue": 0.7 }
      }
    }
  }
}
```

---

# 22. VIZUALNI IDENTITET

## 22.1 Boja AUREXIS-a

```
AUREXIS Accent: #8B5CF6 (Violet/Purple)
— Razlikuje se od svih postojećih boja:
  - SlotLab: #4A9EFF (Blue)
  - DAW: #40FF90 (Green)
  - Middleware: #FF9040 (Orange)

AUREXIS Gradient: #8B5CF6 → #6366F1 (Purple → Indigo)

Panel Background: #0F0A1A (Deep violet-black)
Section Headers: #8B5CF6 @ 15% opacity
Active Slider: #8B5CF6
Inactive Slider: #3B3552
```

## 22.2 Ikonografija

```
AUREXIS Logo: ◇ (Diamond/Brain icon — intelligence)
Profile:      ★ (Star — preset quality)
Behavior:     ≡ (Lines — parameters)
Tweak:        ⚙ (Gear — fine control)
Scope:        ◎ (Target — visualization)
Intel Mode:   🧠
Audio Mode:   🎵
```

---

# 23. KEYBOARD SHORTCUTS

| Key | Action |
|-----|--------|
| `Tab` | Toggle Intel/Audio mode |
| `1-4` | Select Behavior group (Spatial/Dynamics/Music/Variation) |
| `P` | Open Profile dropdown |
| `J` | Open Jurisdiction dropdown |
| `T` | Toggle Tweak section |
| `S` | Toggle Scope section |
| `5-6` | Select Scope mode (5=Coverage, 6=Cabinet) |
| `A` | A/B profile comparison |
| `R` | Reset current behavior group to profile default |
| `L` | Lock/Unlock current behavior group |
| `M` | Toggle Memory Budget Bar breakdown popup |
| `Ctrl+Z` | Undo behavior change |

---

# 24. MIGRATION PATH

## Od trenutnog stanja do AUREXIS-a

### Step 1: Dodaj AUREXIS panel PORED UltimateAudioPanel (paralelno)
- Oba postoje, korisnik bira koji koristi
- AUREXIS ima "Audio" mode koji prikazuje UltimateAudioPanel sadržaj
- Zero breaking changes

### Step 2: AUREXIS postaje default, UltimateAudioPanel ostaje kao fallback
- Novi projekti koriste AUREXIS
- Stari projekti mogu prebaciti ručno

### Step 3: UltimateAudioPanel se uklanja, Audio mode u AUREXIS-u ga potpuno zamenjuje
- Migracija kompletna

### Lower Zone migracija:
- Step 1: Dodat TIMELINE/MIX/EXPORT pored starih tabova
- Step 2: Stari tabovi dostupni kroz "Legacy" opciju
- Step 3: Stari tabovi uklonjeni

---

# 25. SUMMARY

AUREXIS™ Unified Intelligence Panel transformiše SlotLab od:
- **11 sistema × 10+ UI površina × 1000+ parametara**

U:
- **1 panel × 12 behavior slidera + profili + jurisdiction intelligence + production pipeline**

Sa principima:
1. **Profile-First** — izaberi profil, sve radi
2. **Behavior-Driven** — menjaj ponašanje, ne parametre
3. **Auto-Everything** — GDD import, platform detection, fatigue — sve automatski
4. **Jurisdiction-Aware** — regulatorna pravila automatski primenjena per tržište
5. **Production Pipeline** — re-theme, compliance, audit trail za enterprise workflow
6. **Tweak-When-Needed** — full control dostupan ali NE nametnut
7. **Visual Feedback** — Scope sekcija (6 modova) pokazuje šta AUREXIS radi u real-time

**7 ultimativnih feature-a koje NIJEDAN competitor nema:**

| # | Feature | Industry Impact |
|---|---------|-----------------|
| 1 | **Jurisdiction Engine** | Automatska LDW detekcija, celebration limiting — saves weeks per market |
| 2 | **Compliance Report** | One-click GLI/BMM submission — saves 3-5 days per submission |
| 3 | **Memory Budget Bar** | Always-visible resource monitor — prevents last-minute optimization crunch |
| 4 | **Coverage Heatmap** | Visual gap detection — eliminates "forgot this stage" bugs |
| 5 | **Cabinet Sim** | Casino floor monitoring — catches speaker/ambient issues pre-deploy |
| 6 | **Re-Theme Wizard** | Audio re-skinning in 10 min — saves 2-3 weeks per re-theme |
| 7 | **Audit Trail** | Automatic change tracking + ProjectLock — regulatory compliance built-in |

**Net result: ~4,050 LOC neto, 10 faza, ultimativni slot audio authoring alat.**

---

© FluxForge Studio — AUREXIS™ Unified Intelligence Panel Architecture v2.0
