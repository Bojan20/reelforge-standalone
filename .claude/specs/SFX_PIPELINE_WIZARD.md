# SlotLab SFX Pipeline Wizard — Ultimate Specification

**Version:** 1.1
**Date:** 2026-03-10
**Status:** DRAFT — QA PASS — čeka odobrenje pre implementacije
**QA:** Verifikovane sve API reference, CLAUDE.md compliance, edge cases

---

## 1. VIZIJA

Jedan wizard u FluxForge Studio koji uzima **sirove SFX fajlove** (bilo koji format, bilo koji loudness, stereo/mono, neimenovane) i kroz **6 konfigurisanih koraka** proizvodi **slot-ready audio paket** — trimovan, normalizovan, mono, imenovan po stage konvenciji, exportovan u tačnom formatu, i opciono auto-assign-ovan na SlotLab stage-ove.

**Princip:** Svaki parametar je vidljiv i promenljiv. Ništa se ne dešava magično u pozadini bez korisnikovog znanja. Ali default-ovi su toliko dobri da u 90% slučajeva korisnik samo klikne "Process All" i dobije savršen rezultat.

---

## 2. ENTRY POINTS (kako korisnik otvara wizard)

| Lokacija | Akcija | Kontekst |
|---|---|---|
| SlotLab → ASSIGN tab → toolbar | Dugme `⚡ SFX Pipeline` | Otvara wizard sa svim stage-ovima iz projekta |
| SlotLab → ASSIGN tab → folder drop | Drop ceo folder na ASSIGN panel | Otvara wizard sa auto-detektovanim fajlovima |
| DAW → Deliver tab → toolbar | Dugme `SFX Pipeline` | Otvara wizard bez SlotLab konteksta (generic batch) |
| Command Palette | `sfx.pipeline.wizard` | Otvara wizard, pita za source folder |

---

## 3. WIZARD KORACI (6 koraka)

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ 1.IMPORT │──▶│ 2.TRIM   │──▶│ 3.LOUDNESS│──▶│ 4.FORMAT │──▶│ 5.NAMING │──▶│ 6.EXPORT │
│  & SCAN  │   │ & CLEAN  │   │  & LEVEL  │   │ & CHANNEL│   │ & ASSIGN │   │ & FINISH │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
```

Svaki korak je **nezavisan panel** sa svojim parametrima. Korisnik može:
- Preskočiti bilo koji korak (Skip)
- Vratiti se na prethodni korak (Back)
- Promeniti bilo koji parametar pre procesiranja
- Videti **live preview** promene na jednom odabranom fajlu

---

## 4. KORAK 1: IMPORT & SCAN

### Cilj
Učitaj izvorne SFX fajlove, analiziraj ih, prikaži stanje.

### UI Layout
```
╔══════════════════════════════════════════════════════════════╗
║  ⚡ SFX PIPELINE WIZARD                        Step 1 of 6 ║
║  ─────────────────────────────────────────────────────────  ║
║  IMPORT & SCAN                                              ║
║                                                             ║
║  ┌─ SOURCE ─────────────────────────────────────────────┐  ║
║  │  📂 /path/to/raw_sfx/                    [Browse...] │  ║
║  │  ☑ Uključi podfoldere (recursive)                    │  ║
║  │  ☑ Samo audio fajlovi (.wav .mp3 .flac .ogg .aif)   │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ SCAN REZULTAT ──────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Pronađeno: 47 fajlova                               │  ║
║  │                                                       │  ║
║  │  Format breakdown:                                    │  ║
║  │    WAV 24-bit/48kHz ........... 32 fajla              │  ║
║  │    WAV 16-bit/44.1kHz ........ 8 fajlova              │  ║
║  │    MP3 320kbps ............... 4 fajla                │  ║
║  │    FLAC ....................... 3 fajla                │  ║
║  │                                                       │  ║
║  │  Channel breakdown:                                   │  ║
║  │    Stereo .................... 28 fajlova              │  ║
║  │    Mono ...................... 19 fajlova              │  ║
║  │                                                       │  ║
║  │  Loudness range:                                      │  ║
║  │    Quietest: -32.4 LUFS (ui_click_03.wav)            │  ║
║  │    Loudest:  -8.1 LUFS  (big_win_fanfare.wav)        │  ║
║  │    Average:  -18.7 LUFS                               │  ║
║  │                                                       │  ║
║  │  Duration range:                                      │  ║
║  │    Shortest: 0.08s (click.wav)                        │  ║
║  │    Longest:  12.4s (ambient_loop.wav)                 │  ║
║  │                                                       │  ║
║  │  ⚠ 3 fajla imaju tišinu > 500ms na početku/kraju    │  ║
║  │  ⚠ 2 fajla su ispod -30 LUFS (možda pretihi)        │  ║
║  │  ⚠ 1 fajl ima DC offset > 0.01                       │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ FILE LIST ──────────────────────────────────────────┐  ║
║  │  ☑ │ Filename              │ Format   │ Ch │ LUFS   │  ║
║  │  ──┼───────────────────────┼──────────┼────┼────────│  ║
║  │  ☑ │ sfx_reel_stop.wav     │ WAV24/48 │ St │ -16.2  │  ║
║  │  ☑ │ sfx_wild_land.wav     │ WAV24/48 │ St │ -14.8  │  ║
║  │  ☑ │ click_ui.wav          │ WAV16/44 │ Mo │ -22.1  │  ║
║  │  ☐ │ _backup_old.wav       │ WAV16/44 │ Mo │ -18.0  │  ║  ← korisnik isključio
║  │  ...                                                  │  ║
║  │                                                       │  ║
║  │  [Select All] [Deselect All] [Invert] [Sort ▾]      │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║                              [Cancel]  [Skip ▶]  [Next ▶] ║
╚══════════════════════════════════════════════════════════════╝
```

### Parametri (svi editabilni)

| Parametar | Tip | Default | Opis |
|---|---|---|---|
| `sourcePath` | String (folder picker) | — | Folder sa izvornim SFX |
| `recursive` | bool | `true` | Uključi podfoldere |
| `audioOnly` | bool | `true` | Filtriraj samo audio formate |
| `fileFilter` | glob pattern | `*.{wav,mp3,flac,ogg,aif,aiff}` | Custom filter |
| `selectedFiles` | Set<String> | sve | Korisnik može isključiti fajlove |
| `sortBy` | enum | `name` | name / format / channels / lufs / duration |

### Interni proces
1. Skenira folder → lista fajlova
2. Za svaki fajl: čita header (format, sample rate, bit depth, channels, duration)
3. Quick LUFS scan (integrated) → `LoudnessAnalysisService.analyzeBuffer()`
4. DC offset detekcija (mean of all samples)
5. Silence detekcija na početku/kraju → `StripSilenceService.detectSilence()`
6. Generiše upozorenja (warnings)

### Koristi postojeće servise
- `LoudnessAnalysisService.instance` — `analyzeBuffer()`
  - **PAŽNJA:** Game LUFS target (-18.0) je u `LoudnessTarget.game` enum, NE u `LufsPresets` klasi (koja nema game)
- `StripSilenceService.instance` — `detectSilence()`

### Memorijska strategija (OBAVEZNO)
- `analyzeBuffer()` učitava CEO fajl kao `List<double>` — za 96kHz/32f stereo, 2min = ~92 MB po fajlu
- **Limit:** Max 30 fajlova simultano u memoriji. Ako >30: sekvencijalni scan sa progress bar-om
- Prikaži upozorenje ako procenjena memorija > 50% dostupnog RAM-a
- Scan se radi **jedan po jedan fajl** (učitaj → analiziraj → oslobodi → sledeći)

---

## 5. KORAK 2: TRIM & CLEAN

### Cilj
Ukloni tišinu sa početka/kraja, opciono DC offset, opciono fade in/out.

### UI Layout
```
╔══════════════════════════════════════════════════════════════╗
║  ⚡ SFX PIPELINE WIZARD                        Step 2 of 6 ║
║  ─────────────────────────────────────────────────────────  ║
║  TRIM & CLEAN                                               ║
║                                                             ║
║  ┌─ TRIM SILENCE ───────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  ☑ Trim silence from start                            │  ║
║  │  ☑ Trim silence from end                              │  ║
║  │                                                       │  ║
║  │  Threshold:     [-40 dB ────────●──── 0 dB]          │  ║
║  │                          -40 dB                        │  ║
║  │                                                       │  ║
║  │  Min silence:   [──●─────────────────── 5000ms]       │  ║
║  │                  100 ms                                │  ║
║  │                                                       │  ║
║  │  Padding before: [──●────────────────── 500ms]        │  ║
║  │                    5 ms                                │  ║
║  │                                                       │  ║
║  │  Padding after:  [────●──────────────── 500ms]        │  ║
║  │                    10 ms                               │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ CLEAN ──────────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  ☑ Remove DC offset                                   │  ║
║  │  ☐ Normalize peak to 0 dBFS before LUFS step          │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ FADE ───────────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  ☑ Apply fade-in       Duration: [  2 ] ms            │  ║
║  │  ☑ Apply fade-out      Duration: [ 10 ] ms            │  ║
║  │     Curve: [ Linear ▾ ]  (Linear / Exp / Log / S)    │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ PREVIEW ────────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Selected: sfx_reel_stop.wav                          │  ║
║  │                                                       │  ║
║  │  Before: ░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░  2.4s      │  ║
║  │  After:  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  1.8s      │  ║
║  │                    ▶ Play A/B                         │  ║
║  │                                                       │  ║
║  │  Trimmed: 0.42s start, 0.18s end                     │  ║
║  │  Saved: 0.60s per file (avg)                          │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  Summary: 47 files → trim ~28.2s total silence             ║
║                                                             ║
║                       [◀ Back]  [Skip ▶]  [Next ▶]        ║
╚══════════════════════════════════════════════════════════════╝
```

### Parametri

| Parametar | Tip | Default | Range | Opis |
|---|---|---|---|---|
| `trimStart` | bool | `true` | — | Trim silence sa početka |
| `trimEnd` | bool | `true` | — | Trim silence sa kraja |
| `thresholdDb` | double | `-40.0` | -96..0 | Prag tišine u dB |
| `minSilenceMs` | double | `100.0` | 10..5000 | Min trajanje tišine za detekciju |
| `paddingBeforeMs` | double | `5.0` | 0..500 | Koliko tišine ostaviti pre zvuka |
| `paddingAfterMs` | double | `10.0` | 0..500 | Koliko tišine ostaviti posle zvuka |
| `removeDcOffset` | bool | `true` | — | Ukloni DC offset |
| `preNormalizePeak` | bool | `false` | — | Peak normalize pre LUFS koraka |
| `fadeIn` | bool | `true` | — | Primeni fade-in |
| `fadeInMs` | double | `2.0` | 0..500 | Trajanje fade-in |
| `fadeOut` | bool | `true` | — | Primeni fade-out |
| `fadeOutMs` | double | `10.0` | 0..500 | Trajanje fade-out |
| `fadeCurve` | enum | `linear` | linear/exp/log/sCurve | Kriva fade-a |

### Preview sistem
- Korisnik bira fajl iz liste (iz koraka 1)
- Vidi waveform pre/posle trima
- A/B playback (original vs trimmed)
- Statistika: koliko je uklonjeno po fajlu i ukupno

### Koristi postojeće servise
- `StripSilenceService.instance` — `detectSilence()`, `setThreshold()`, `setMinDuration()`
- `DynamicSplitService.instance` — `padBeforeMs`, `padAfterMs` (samo parametri, NE primena)
- **DC offset:** `DcOffsetProcessor` VEĆ POSTOJI u `rf-offline/src/processors.rs:181-223` (high-pass filter, coeff=0.995) — NIJE nov
- **Fade primena:** `DynamicSplitService` samo ČUVA fade parametre, ne primenjuje ih. Fade se primenjuje u `rf-offline` pipeline (`apply_fade_in/out`)

---

## 6. KORAK 3: LOUDNESS & LEVEL

### Cilj
Normalizuj sve fajlove na isti loudness target. Slot SFX moraju biti konzistentni.

### UI Layout
```
╔══════════════════════════════════════════════════════════════╗
║  ⚡ SFX PIPELINE WIZARD                        Step 3 of 6 ║
║  ─────────────────────────────────────────────────────────  ║
║  LOUDNESS & LEVEL                                           ║
║                                                             ║
║  ┌─ NORMALIZATION MODE ─────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  [ LUFS ]  [ Peak ]  [ TruePeak ]  [ None ]          │  ║
║  │    ^^^^                                                │  ║
║  │  (selected)                                            │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ TARGET ─────────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  LUFS Target:   [-24 ──────────────●──── -6]          │  ║
║  │                              -18.0 LUFS                │  ║
║  │                                                       │  ║
║  │  Presets:  [Streaming -14] [Broadcast -23] [Game -18] │  ║
║  │            [Club -8] [Film -24] [Custom...]           │  ║
║  │                                     ^^^^               │  ║
║  │                                   (selected)           │  ║
║  │                                                       │  ║
║  │  True Peak Ceiling:  [-3 ────────────●── 0 dBTP]     │  ║
║  │                               -1.0 dBTP               │  ║
║  │                                                       │  ║
║  │  ☑ Apply limiter if would clip                        │  ║
║  │  ☐ Allow clipping (destructive)                       │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ PER-CATEGORY OVERRIDES ─────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Ova sekcija omogućava različit target po kategoriji   │  ║
║  │  SFX-a. Ako ne treba, ostavi "Use Global" svuda.     │  ║
║  │                                                       │  ║
║  │  Category          │ Target    │ Override              │  ║
║  │  ──────────────────┼───────────┼───────────            │  ║
║  │  UI / Clicks       │ -20 LUFS  │ [Use Global ▾]       │  ║
║  │  Reel Mechanics    │ -18 LUFS  │ [Use Global ▾]       │  ║
║  │  Win Celebrations  │ -14 LUFS  │ [Custom: -14 ▾]      │  ║
║  │  Ambient / Loops   │ -22 LUFS  │ [Custom: -22 ▾]      │  ║
║  │  Feature Triggers  │ -16 LUFS  │ [Custom: -16 ▾]      │  ║
║  │                                                       │  ║
║  │  Kategorije se auto-detektuju iz filename paterna:    │  ║
║  │  ui_* → UI, reel_* → Reel, win_*/big_* → Win,       │  ║
║  │  amb_*/loop_* → Ambient, fs_*/scatter_* → Feature    │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ ANALYSIS PREVIEW ───────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Before normalization:          After normalization:   │  ║
║  │  ┌──────────────────┐          ┌──────────────────┐   │  ║
║  │  │    ╻              │          │  ╻╻╻╻╻╻╻╻╻╻╻╻╻  │   │  ║
║  │  │  ╻ ┃╻             │          │  ┃┃┃┃┃┃┃┃┃┃┃┃┃  │   │  ║
║  │  │╻ ┃ ┃┃╻╻  ╻       │    →     │  ┃┃┃┃┃┃┃┃┃┃┃┃┃  │   │  ║
║  │  │┃╻┃╻┃┃┃┃╻╻┃╻      │          │  ┃┃┃┃┃┃┃┃┃┃┃┃┃  │   │  ║
║  │  └──────────────────┘          └──────────────────┘   │  ║
║  │  LUFS spread: 24.3 dB          LUFS spread: 2.1 dB   │  ║
║  │  (inconsistent)                 (tight ✓)             │  ║
║  │                                                       │  ║
║  │  Gain changes:                                        │  ║
║  │    Max boost:  +14.2 dB (ui_click_03.wav)            │  ║
║  │    Max cut:    -9.9 dB  (big_win_fanfare.wav)        │  ║
║  │    Avg change: +2.3 dB                                │  ║
║  │    Clip risk:  2 files (limiter will engage)          │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║                       [◀ Back]  [Skip ▶]  [Next ▶]        ║
╚══════════════════════════════════════════════════════════════╝
```

### Parametri

| Parametar | Tip | Default | Range | Opis |
|---|---|---|---|---|
| `normMode` | enum | `lufs` | lufs/peak/truePeak/none | Mod normalizacije |
| `targetLufs` | double | `-18.0` | -24..-6 | LUFS target (za Game preset) |
| `truePeakCeiling` | double | `-1.0` | -3..0 | True peak limit u dBTP |
| `applyLimiter` | bool | `true` | — | Limiter ako bi klipovao |
| `allowClipping` | bool | `false` | — | Dozvoli klipovanje (destruktivno) |
| `perCategoryOverrides` | Map<String, double?> | svi `null` (Use Global) | — | Override LUFS po kategoriji |
| `categoryDetection` | bool | `true` | — | Auto-detect kategorija iz filename-a |

### Kategorije (auto-detect iz filename paterna)

| Kategorija | Filename pattern | Default LUFS override |
|---|---|---|
| UI / Clicks | `ui_*`, `click_*`, `button_*` | null (global) |
| Reel Mechanics | `reel_*`, `spin_*`, `stop_*` | null (global) |
| Win Celebrations | `win_*`, `big_*`, `rollup_*`, `fanfare_*` | null (global) |
| Ambient / Loops | `amb_*`, `loop_*`, `music_*`, `drone_*` | null (global) |
| Feature Triggers | `fs_*`, `scatter_*`, `wild_*`, `bonus_*` | null (global) |
| Anticipation | `anticipation_*`, `tension_*`, `near_*` | null (global) |

### Koristi postojeće servise
- `BatchNormalizationService.instance` — `normalizeFiles()`, `analyzeFiles()`
- `LoudnessAnalysisService.instance` — `analyzeBuffer()`, `LoudnessTarget.game`
- `OfflineProcessingProvider` — `setNormalization()`, `batchProcess()`

---

## 7. KORAK 4: FORMAT & CHANNEL

### Cilj
Konvertuj sve u ciljni format. Slot SFX su tipično WAV 16-bit ili 24-bit, 44.1kHz ili 48kHz, **mono**.

### UI Layout
```
╔══════════════════════════════════════════════════════════════╗
║  ⚡ SFX PIPELINE WIZARD                        Step 4 of 6 ║
║  ─────────────────────────────────────────────────────────  ║
║  FORMAT & CHANNEL                                           ║
║                                                             ║
║  ┌─ OUTPUT FORMAT ──────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Format:   [WAV 16-bit] [WAV 24-bit] [WAV 32f]      │  ║
║  │            [FLAC] [OGG] [MP3 320]                     │  ║
║  │                          ^^^^^^^^^^                    │  ║
║  │                          (selected)                    │  ║
║  │                                                       │  ║
║  │  Sample Rate: [22050] [44100] [48000] [96000]        │  ║
║  │                         ^^^^^                          │  ║
║  │                       (selected)                       │  ║
║  │                                                       │  ║
║  │  ☐ Resample samo ako je drugačiji od source-a         │  ║
║  │  ☑ Anti-alias filter pri downsampling-u               │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ CHANNEL CONFIGURATION ──────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Output channels: [Mono ▾]                            │  ║
║  │                                                       │  ║
║  │  Mono downmix method:                                 │  ║
║  │    (●) Sum (L+R)/2          — standard, phase-safe    │  ║
║  │    ( ) Left only            — uzmi samo levi kanal    │  ║
║  │    ( ) Right only           — uzmi samo desni kanal   │  ║
║  │    ( ) Mid (L+R)            — mono sum, no division   │  ║
║  │    ( ) Side (L-R)           — difference signal       │  ║
║  │                                                       │  ║
║  │  ☑ Skip downmix za fajlove koji su već mono           │  ║
║  │                                                       │  ║
║  │  Per-stage stereo override:                           │  ║
║  │    ☐ Zadrži stereo za: [ MUSIC_BASE_L1-L5 ▾ ]       │  ║
║  │    ☐ Zadrži stereo za: [ AMBIENT loops ▾ ]            │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ MULTI-FORMAT EXPORT ────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  ☐ Export u više formata istovremeno                   │  ║
║  │     (koristi Render Matrix: format × fajl matrica)    │  ║
║  │                                                       │  ║
║  │  Ako uključeno:                                       │  ║
║  │    ☑ WAV 24-bit/48kHz (primary)                       │  ║
║  │    ☑ OGG q8 (web/mobile fallback)                     │  ║
║  │    ☐ MP3 320kbps (legacy)                             │  ║
║  │                                                       │  ║
║  │  Subfolder per format: ☑                              │  ║
║  │    → output/wav24/                                    │  ║
║  │    → output/ogg/                                      │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  Summary: 47 files → WAV 24-bit, 48kHz, Mono (L+R)/2      ║
║           28 stereo → mono, 19 already mono (skip)          ║
║                                                             ║
║                       [◀ Back]  [Skip ▶]  [Next ▶]        ║
╚══════════════════════════════════════════════════════════════╝
```

### Parametri

| Parametar | Tip | Default | Opis |
|---|---|---|---|
| `outputFormat` | enum | `wav24` | wav16/wav24/wav32f/flac/ogg/mp3High |
| `sampleRate` | int | `48000` | 22050/44100/48000/96000 |
| `resampleOnlyIfDifferent` | bool | `false` | Skip resample ako je već target SR |
| `antiAliasFilter` | bool | `true` | Anti-alias pri downsampling-u |
| `outputChannels` | enum | `mono` | mono/stereo/keepOriginal |
| `monoMethod` | enum | `sumHalf` | sumHalf/leftOnly/rightOnly/mid/side |
| `skipMonoDownmix` | bool | `true` | Ne diraj fajlove koji su već mono |
| `stereoOverrideStages` | Set<String> | `{}` | Stage-ovi koji ostaju stereo |
| `multiFormat` | bool | `false` | Export u više formata |
| `multiFormatPresets` | Set<AudioExportFormat> | `{wav24, ogg}` | Formati za multi-export |
| `subfolderPerFormat` | bool | `true` | Kreiraj subfolder po formatu |

### Koristi postojeće servise
- `AudioExportQueueService.instance` — `addBatch()` za konverziju
- `OfflineProcessingProvider` — `setOutputFormat()`, `processFile()`
- **Mono downmix:** `AudioBuffer.to_mono()` VEĆ POSTOJI u `rf-offline/src/pipeline.rs:164-186` (averaging L+R) — samo treba dodati ostale metode (leftOnly, rightOnly, mid, side)
- **Resample:** `convert_sample_rate()` postoji u `rf-offline/src/pipeline.rs`, `resample_to_48k()` u `encoder.rs`
- **Dither:** `apply_dithering()` postoji u `rf-offline/src/encoder.rs:1153+` za bit depth redukciju

---

## 8. KORAK 5: NAMING & ASSIGN

### Cilj
Preimenuj fajlove po SlotLab konvenciji i opciono auto-assign na stage-ove.

### UI Layout
```
╔══════════════════════════════════════════════════════════════╗
║  ⚡ SFX PIPELINE WIZARD                        Step 5 of 6 ║
║  ─────────────────────────────────────────────────────────  ║
║  NAMING & ASSIGN                                            ║
║                                                             ║
║  ┌─ NAMING MODE ────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  [SlotLab Stage ID]  [UCS Standard]  [Custom]  [Keep]│  ║
║  │   ^^^^^^^^^^^^^^^^^                                    │  ║
║  │     (selected)                                         │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ SLOTLAB NAMING ─────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Prefix: [ sfx_ ]                                     │  ║
║  │  Format: sfx_{STAGE_ID}.{ext}                         │  ║
║  │  Example: sfx_REEL_STOP.wav                           │  ║
║  │                                                       │  ║
║  │  ☑ Lowercase stage ID (sfx_reel_stop.wav)             │  ║
║  │  ☐ Keep original name as suffix                       │  ║
║  │     (sfx_reel_stop_original_name.wav)                 │  ║
║  │  ☑ Number duplicates (sfx_reel_stop_01.wav)           │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ AUTO-DETECT MAPPING ────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Filename fuzzy matching rezultat:                    │  ║
║  │                                                       │  ║
║  │  ✅ MATCHED (38/47):                                  │  ║
║  │  ─────────────────────────────────────────────────    │  ║
║  │  Source file             → Stage ID       Confidence  │  ║
║  │  sfx_reel_stop.wav       → REEL_STOP      98%  [✓]  │  ║
║  │  wild_land_01.wav        → WILD_LAND      92%  [✓]  │  ║
║  │  scatter_3.wav           → SCATTER_LAND_3 85%  [✓]  │  ║
║  │  big_win_fanfare.wav     → BIG_WIN_START  78%  [▾]  │  ║
║  │  tension_r3.wav          → ANTICIPATION_  72%  [▾]  │  ║
║  │                            TENSION_R3                 │  ║
║  │  ...                                                  │  ║
║  │                                                       │  ║
║  │  ❓ UNMATCHED (9/47):                                 │  ║
║  │  ─────────────────────────────────────────────────    │  ║
║  │  Source file             → Assign to:                 │  ║
║  │  stinger_01.wav          → [Select stage... ▾]       │  ║
║  │  whoosh_deep.wav         → [Select stage... ▾]       │  ║
║  │  charm_sparkle.wav       → [Select stage... ▾]       │  ║
║  │  ...                                                  │  ║
║  │                                                       │  ║
║  │  [▾] dropdown nudi sve dostupne stage-ove sa         │  ║
║  │  pretraživanjem i kategorijama                        │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ SLOTLAB AUTO-ASSIGN ────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  ☑ Auto-assign na SlotLab stage-ove posle exporta     │  ║
║  │                                                       │  ║
║  │  Ovo će:                                              │  ║
║  │  1. Pozvati projectProvider.setAudioAssignment()      │  ║
║  │  2. Kreirati SlotCompositeEvent za svaki stage        │  ║
║  │  3. Registrovati u EventRegistry                      │  ║
║  │  4. Audio odmah spreman za playback u slot mašini     │  ║
║  │                                                       │  ║
║  │  ⚠ Postojeći assignment-i za matched stage-ove       │  ║
║  │    će biti ZAMENJENI. Potvrdi pre procesiranja.       │  ║
║  │                                                       │  ║
║  │  Conflict resolution:                                 │  ║
║  │    (●) Replace existing    — zameni stari audio       │  ║
║  │    ( ) Add as layer        — dodaj kao novi layer     │  ║
║  │    ( ) Skip if assigned    — preskoči ako već ima     │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  Summary: 38 matched + 9 manual → 47 named & assigned     ║
║                                                             ║
║                       [◀ Back]  [Skip ▶]  [Next ▶]        ║
╚══════════════════════════════════════════════════════════════╝
```

### Parametri

| Parametar | Tip | Default | Opis |
|---|---|---|---|
| `namingMode` | enum | `slotLabStageId` | slotLabStageId/ucs/custom/keepOriginal |
| `prefix` | String | `sfx_` | Prefix za fajlove |
| `lowercase` | bool | `true` | Stage ID u lowercase |
| `keepOriginalSuffix` | bool | `false` | Dodaj originalno ime kao suffix |
| `numberDuplicates` | bool | `true` | Numeriši duplikate (_01, _02...) |
| `stageMapping` | Map<String, String> | auto-detect | source filename → stage ID |
| `autoAssign` | bool | `true` | Auto-assign na SlotLab stage-ove |
| `conflictResolution` | enum | `replace` | replace/addLayer/skipIfAssigned |
| `ucsVendor` | String | `""` | UCS vendor (ako je UCS mode) |
| `ucsProject` | String | `""` | UCS project name |
| `customTemplate` | String | `"{prefix}{stage}{ext}"` | Custom naming template |

### Naming template tokens (Custom mode)
- `{prefix}` — korisnikov prefix
- `{stage}` — stage ID (REEL_STOP)
- `{stage_lower}` — stage id (reel_stop)
- `{original}` — originalno ime fajla (bez ekstenzije)
- `{index}` — redni broj (01, 02...)
- `{category}` — auto-detected kategorija
- `{ext}` — fajl ekstenzija (.wav)
- `{date}` — YYYY-MM-DD
- `{project}` — naziv projekta

### Koristi postojeće servise
- `UcsNamingService.instance` — `generateBatch()`, `parse()`, `detectCategoryIndex()`
- `SlotLabProjectProvider` — `_resolveStageFromFilename()`, `setAudioAssignment(recordUndo: true)`
- `StageGroupService` — `matchFilesToGroup(StageGroup group, List<String> audioPaths)` (NE `performAutoBind` — taj metod ne postoji)
- `MiddlewareProvider` — `addCompositeEvent()`, `updateCompositeEvent()`

### EventRegistry registracija — KRITIČNO
**Wizard NIKADA ne poziva `_syncEventToRegistry()` direktno** — to je PRIVATNA metoda `_SlotLabScreenState`.

Ispravan flow:
1. Wizard poziva `projectProvider.setAudioAssignment(stage, path)`
2. To kreira/ažurira `SlotCompositeEvent` u `MiddlewareProvider`
3. `MiddlewareProvider.notifyListeners()` okida `_onMiddlewareChanged` listener u `SlotLabScreen`
4. Taj listener poziva `_syncEventToRegistry()` — **jedini dozvoljeni put**
5. Wizard NE dodiruje `EventRegistry` direktno

Ovo poštuje CLAUDE.md pravilo: "JEDAN put registracije — samo `_syncEventToRegistry()` u `slot_lab_screen.dart`"

---

## 9. KORAK 6: EXPORT & FINISH

### Cilj
Pokreni celokupni pipeline, prikaži progress, rezultat, i opcije posle.

### UI Layout
```
╔══════════════════════════════════════════════════════════════╗
║  ⚡ SFX PIPELINE WIZARD                        Step 6 of 6 ║
║  ─────────────────────────────────────────────────────────  ║
║  EXPORT & FINISH                                            ║
║                                                             ║
║  ┌─ OUTPUT ─────────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Output folder: [ ~/Desktop/slot_sfx_export/ ] [...]  │  ║
║  │                                                       │  ║
║  │  ☑ Kreiraj subfolder sa datumom (2026-03-10/)         │  ║
║  │  ☐ Overwrite ako postoji                              │  ║
║  │  ☑ Generiši manifest.json (lista fajlova + metadata)  │  ║
║  │  ☑ Generiši LUFS report (.txt)                        │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ PIPELINE SUMMARY ──────────────────────────────────┐   ║
║  │                                                       │  ║
║  │  Input:    47 files from /raw_sfx/                    │  ║
║  │  Trim:     ON (threshold -40dB, pad 5/10ms)           │  ║
║  │  Loudness: LUFS -18.0, ceiling -1.0 dBTP, limiter ON │  ║
║  │  Format:   WAV 24-bit, 48kHz, Mono (L+R)/2           │  ║
║  │  Naming:   SlotLab sfx_{stage_id}.wav                 │  ║
║  │  Assign:   Auto-assign to 38 stages (replace mode)    │  ║
║  │  Output:   ~/Desktop/slot_sfx_export/2026-03-10/      │  ║
║  │                                                       │  ║
║  │  Estimated size: ~12.4 MB                             │  ║
║  │  Estimated time: ~8 seconds                           │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║                                                             ║
║            ┌──────────────────────────────────┐             ║
║            │                                  │             ║
║            │     ⚡ PROCESS ALL (47 files)     │             ║
║            │                                  │             ║
║            └──────────────────────────────────┘             ║
║                                                             ║
║                                                             ║
║  ─── POSLE KLIKA NA "PROCESS ALL" ──────────────────────   ║
║                                                             ║
║  ┌─ PROGRESS ───────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  Overall: ████████████████████░░░░░░░░░░  68%         │  ║
║  │                                                       │  ║
║  │  Step 1/4: Trim & Clean     ✅ Done (2.1s)            │  ║
║  │  Step 2/4: Normalize        ✅ Done (3.4s)            │  ║
║  │  Step 3/4: Convert & Export ⏳ Processing...           │  ║
║  │    → sfx_wild_expand_start.wav (32/47)                │  ║
║  │  Step 4/4: Auto-Assign      ⏸ Pending                │  ║
║  │                                                       │  ║
║  │  Elapsed: 6.8s  |  Remaining: ~3.2s                   │  ║
║  │                                                       │  ║
║  │  [Cancel]                                              │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ─── POSLE ZAVRŠETKA ───────────────────────────────────   ║
║                                                             ║
║  ┌─ RESULTS ────────────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  ✅ COMPLETE — 47/47 files processed successfully     │  ║
║  │                                                       │  ║
║  │  Pipeline stats:                                      │  ║
║  │    Total time:        8.3 seconds                     │  ║
║  │    Silence trimmed:   28.2 seconds total              │  ║
║  │    Avg LUFS delta:    +2.3 dB                         │  ║
║  │    Limiter engaged:   2 files                         │  ║
║  │    Stereo → Mono:     28 files                        │  ║
║  │    Stages assigned:   38 / 47                         │  ║
║  │    Output size:       12.4 MB                         │  ║
║  │                                                       │  ║
║  │  Files with warnings:                                 │  ║
║  │    ⚠ stinger_01.wav — not assigned (no stage match)  │  ║
║  │    ⚠ whoosh_deep.wav — not assigned (no stage match) │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║  ┌─ POST-ACTIONS ───────────────────────────────────────┐  ║
║  │                                                       │  ║
║  │  [📂 Open Output Folder]                              │  ║
║  │  [🎰 Go to SlotLab]     — otvorit ASSIGN tab         │  ║
║  │  [📋 Copy Report]       — LUFS report u clipboard     │  ║
║  │  [💾 Save Preset]       — sačuvaj pipeline config     │  ║
║  │  [🔄 Run Again]         — isti pipeline, novi fajlovi │  ║
║  │                                                       │  ║
║  └──────────────────────────────────────────────────────┘  ║
║                                                             ║
║                                         [Close Wizard]     ║
╚══════════════════════════════════════════════════════════════╝
```

### Parametri

| Parametar | Tip | Default | Opis |
|---|---|---|---|
| `outputPath` | String | `~/Desktop/slot_sfx_export/` | Output folder |
| `createDateSubfolder` | bool | `true` | Kreiraj YYYY-MM-DD subfolder |
| `overwriteExisting` | bool | `false` | Overwrite ako postoji |
| `generateManifest` | bool | `true` | JSON manifest sa metadata |
| `generateLufsReport` | bool | `true` | LUFS report (.txt) |

---

## 10. PIPELINE PRESET SISTEM

Korisnik može **sačuvati celokupnu konfiguraciju** wizard-a kao preset i učitati je sledeći put.

### Preset Model

```dart
class SfxPipelinePreset {
  final String id;
  final String name;
  final DateTime createdAt;

  // Step 1
  final String? lastSourcePath;
  final bool recursive;
  final String fileFilter;

  // Step 2 - Trim
  final bool trimStart;
  final bool trimEnd;
  final double thresholdDb;
  final double minSilenceMs;
  final double paddingBeforeMs;
  final double paddingAfterMs;
  final bool removeDcOffset;
  final bool fadeIn;
  final double fadeInMs;
  final bool fadeOut;
  final double fadeOutMs;
  final String fadeCurve;

  // Step 3 - Loudness
  final String normMode;
  final double targetLufs;
  final double truePeakCeiling;
  final bool applyLimiter;
  final Map<String, double?> perCategoryOverrides;

  // Step 4 - Format
  final String outputFormat;
  final int sampleRate;
  final String outputChannels;
  final String monoMethod;
  final bool multiFormat;
  final Set<String> multiFormatPresets;

  // Step 5 - Naming
  final String namingMode;
  final String prefix;
  final bool lowercase;
  final String conflictResolution;

  // Step 6 - Export
  final String? outputPath;
  final bool createDateSubfolder;
  final bool generateManifest;
  final bool generateLufsReport;
}
```

### Built-in Presets

| Preset | Opis |
|---|---|
| **Slot Game Standard** | LUFS -18, WAV24/48k, Mono, sfx_ prefix, auto-assign ON |
| **Slot Game Mobile** | LUFS -16, OGG q6, Mono, sfx_ prefix, multi-format (OGG + WAV) |
| **Wwise Import Ready** | LUFS -18, WAV24/48k, Mono, UCS naming, no auto-assign |
| **FMOD Import Ready** | LUFS -18, WAV24/48k, Mono, UCS naming, no auto-assign |
| **Quick & Dirty** | No trim, peak normalize only, keep format, keep names |
| **Broadcast SFX** | LUFS -23, WAV24/48k, Stereo, UCS naming |

---

## 11. MANIFEST FORMAT

Wizard generiše `manifest.json` u output folderu:

```json
{
  "generator": "FluxForge Studio SFX Pipeline",
  "version": "1.0",
  "date": "2026-03-10T14:23:45Z",
  "project": "MySlotGame",
  "preset": "Slot Game Standard",

  "pipeline": {
    "trim": { "enabled": true, "thresholdDb": -40, "paddingMs": [5, 10] },
    "normalize": { "mode": "lufs", "target": -18.0, "ceiling": -1.0 },
    "format": { "type": "wav24", "sampleRate": 48000, "channels": "mono" },
    "naming": { "mode": "slotLabStageId", "prefix": "sfx_" }
  },

  "files": [
    {
      "output": "sfx_reel_stop.wav",
      "source": "raw_sfx/reel_stop_v2_final.wav",
      "stage": "REEL_STOP",
      "assigned": true,
      "stats": {
        "originalLufs": -14.8,
        "finalLufs": -18.0,
        "gainApplied": -3.2,
        "limiterEngaged": false,
        "trimmedStartMs": 420,
        "trimmedEndMs": 180,
        "originalDuration": 2.4,
        "finalDuration": 1.8,
        "originalChannels": 2,
        "finalChannels": 1
      }
    }
  ],

  "summary": {
    "totalFiles": 47,
    "successCount": 47,
    "failedCount": 0,
    "totalSilenceTrimmedMs": 28200,
    "avgLufsDelta": 2.3,
    "limiterEngagedCount": 2,
    "stereoToMonoCount": 28,
    "stagesAssigned": 38,
    "outputSizeBytes": 13003776,
    "processingTimeMs": 8300
  }
}
```

---

## 12. LUFS REPORT FORMAT

```
═══════════════════════════════════════════════════
  FluxForge Studio — SFX Pipeline LUFS Report
  Generated: 2026-03-10 14:23:45
  Preset: Slot Game Standard
═══════════════════════════════════════════════════

Target: -18.0 LUFS (Game preset)
True Peak Ceiling: -1.0 dBTP

─── PER-FILE ANALYSIS ─────────────────────────────

File                        │ LUFS   │ Peak   │ Gain   │ Status
────────────────────────────┼────────┼────────┼────────┼────────
sfx_reel_stop.wav           │ -18.0  │ -1.8   │ -3.2dB │ ✓ OK
sfx_wild_land.wav           │ -18.0  │ -2.1   │ -1.2dB │ ✓ OK
sfx_big_win_start.wav       │ -18.0  │ -1.0   │ -5.8dB │ ⚠ Limiter
sfx_ui_spin_press.wav       │ -18.0  │ -8.2   │ +4.1dB │ ✓ OK
...

─── SUMMARY ────────────────────────────────────────

Total files:      47
All at target:    ✓ Yes
Limiter engaged:  2 files
Max gain applied: +14.2 dB (sfx_ui_click_03.wav)
Min gain applied: -9.9 dB  (sfx_big_win_fanfare.wav)
LUFS spread:      2.1 dB (before: 24.3 dB)

─── COMPLIANCE ─────────────────────────────────────

EBU R128:  ✓ All files within ±1.0 LU of target
ITU-1770:  ✓ True peak below ceiling
Game:      ✓ Suitable for slot game integration
```

---

## 13. ARHITEKTURA IMPLEMENTACIJE

### Novi fajlovi

| Fajl | Tip | Opis |
|---|---|---|
| `services/sfx_pipeline_service.dart` | Service | Orchestrator — poziva postojeće servise redom |
| `models/sfx_pipeline_config.dart` | Model | SfxPipelinePreset, SfxPipelineResult, SfxFileResult |
| `widgets/slot_lab/sfx_pipeline_wizard.dart` | Widget | 6-step wizard UI (modal dialog) |
| `providers/sfx_pipeline_provider.dart` | Provider | State management za wizard (ChangeNotifier) |

### Modifikacije postojećih fajlova

| Fajl | Izmena |
|---|---|
| `slot_lab_screen.dart` | Dodaj `⚡ SFX Pipeline` dugme u ASSIGN toolbar |
| `offline_processing_provider.dart` | Dodaj `monoDownmixMethod` parametar u `OfflineJobConfig` |
| `rf-offline/src/pipeline.rs` | Proširi `AudioBuffer.to_mono()` sa 4 nova metoda (leftOnly/rightOnly/mid/side) — ~30 linija Rust |
| `command_registry.dart` | Registruj `sfx.pipeline.wizard` komandu |
| `slot_lab_project_provider.dart` | Dodaj `batchSetAudioAssignments()` za atomski batch undo (videti sekciju 18) |

### Dependency graph

```
SfxPipelineWizard (UI)
  └── SfxPipelineProvider (state)
        └── SfxPipelineService (orchestrator)
              ├── StripSilenceService        (trim)
              ├── BatchNormalizationService   (LUFS)
              ├── LoudnessAnalysisService     (analysis)
              ├── AudioExportQueueService     (export)
              ├── OfflineProcessingProvider   (format convert + mono + DC offset)
              ├── UcsNamingService            (UCS naming)
              ├── SlotLabProjectProvider      (stage mapping + assign + undo)
              ├── StageGroupService           (fuzzy matching)
              └── MiddlewareProvider          (composite events)
                    └── [indirektno] SlotLabScreen listener → EventRegistry
                        (wizard NIKADA ne pristupa EventRegistry direktno)
```

### Procena obima

| Komponenta | Linije koda | Napomena |
|---|---|---|
| `sfx_pipeline_service.dart` | ~400-500 | Orchestrator, poziva gotove API-je |
| `sfx_pipeline_config.dart` | ~200-250 | Modeli, preseti, JSON serialization |
| `sfx_pipeline_wizard.dart` | ~800-1000 | 6 koraka UI, preview, progress |
| `sfx_pipeline_provider.dart` | ~150-200 | State, notifyListeners |
| Mono downmix proširenje (Rust) | ~30 | 4 nova metoda u existing `to_mono()` |
| Izmene existing files | ~100-150 | Dugme, config, command, batch undo |
| **UKUPNO** | **~1700-2100** | 90%+ oslanjanje na gotove servise |

---

## 14. PROCESSING PIPELINE (redosled operacija)

**KRITIČNO: Sva obrada je OFFLINE** — koristi `rf-offline` Rust crate thread pool.
Audio thread (`rf-engine`) ostaje NETAKNUT tokom celokupnog pipeline-a.
Audio thread se kontaktira tek na samom kraju, indirektno, kada `setAudioAssignment()` okine EventRegistry sync.

```
Za svaki fajl:
│
├── 1. READ SOURCE
│   └── Učitaj audio samples u memoriju
│
├── 2. DC OFFSET REMOVAL (ako uključeno)
│   └── Koristi POSTOJEĆI `DcOffsetProcessor` (rf-offline/src/processors.rs:181)
│       High-pass filter sa coeff=0.995, NE naivni mean subtract
│
├── 3. TRIM SILENCE
│   ├── StripSilenceService.detectSilence(samples, sampleRate)
│   ├── Nađi prvu/poslednju non-silent regiju
│   ├── Primeni padding before/after
│   └── Iseci samples
│
├── 4. FADE IN/OUT (ako uključeno)
│   ├── Primeni fade krivulju na prvih N samples
│   └── Primeni fade krivulju na poslednjih N samples
│
├── 5. MONO DOWNMIX (ako stereo → mono)
│   ├── sumHalf: out[i] = (L[i] + R[i]) / 2
│   ├── leftOnly: out[i] = L[i]
│   ├── rightOnly: out[i] = R[i]
│   ├── mid: out[i] = L[i] + R[i]  (bez deljenja)
│   └── side: out[i] = L[i] - R[i]
│
├── 6. NORMALIZE (LUFS/Peak/TruePeak)
│   ├── Analiziraj loudness
│   ├── Izračunaj potreban gain
│   ├── Ako bi klipovao + limiter ON → primeni limiter
│   └── Primeni gain
│
├── 7. FORMAT CONVERT
│   ├── Resample ako je potrebno (anti-alias filter)
│   ├── Bit depth convert (dither ako 24→16)
│   └── Encode u target format
│
├── 8. WRITE OUTPUT
│   ├── Generiši output filename (po naming template)
│   ├── Zapiši fajl na disk
│   └── Dodaj u manifest
│
└── 9. AUTO-ASSIGN (ako uključeno)
    ├── projectProvider.setAudioAssignment(stage, outputPath, recordUndo: true)
    │   └── Interno poziva _ensureCompositeEventForStage()
    ├── MiddlewareProvider.notifyListeners() se okida automatski
    └── SlotLabScreen._onMiddlewareChanged → _syncEventToRegistry()
        (Wizard NIKADA ne poziva EventRegistry direktno — sekcija 8)
```

### Batch paralelizacija

- Koraci 1-8 se mogu paralelizovati po fajlovima (Rust thread pool)
- Korak 9 (auto-assign) MORA biti sekvencijalan (Flutter main thread, notifyListeners)
- Progress callback se šalje posle svakog fajla

---

## 15. ERROR HANDLING

| Scenario | Handling |
|---|---|
| Fajl ne može da se učita | Skip + warning u rezultatu |
| Fajl je prazan (0 samples) | Skip + warning |
| LUFS analiza ne uspeva | Skip normalizaciju za taj fajl + warning |
| Output folder ne postoji | Kreiraj automatski |
| Output fajl već postoji | Prema `overwriteExisting` flag-u |
| Disk full | Prekini pipeline + error |
| Stage ID conflict | Prema `conflictResolution` parametru |
| Nepoznat format | Skip + warning |
| Korisnik klikne Cancel | Zaustavi pipeline — videti sekciju 21 za recovery |
| ExFAT eksterni disk | Prikaži upozorenje, preporuči output na internom disku |
| Spin aktivan u SlotLab | Blokiraj auto-assign do kraja spin-a — videti sekciju 19 |
| Memorija > 50% RAM | Prikaži upozorenje, predloži sekvencijalni scan |

---

## 16. BATCH UNDO SISTEM

### Problem
Ako wizard assign-uje 47 fajlova, korisnik dobija 47 zasebnih undo koraka. To je neupotrebljivo.

### Rešenje
Dodati `batchSetAudioAssignments()` u `SlotLabProjectProvider`:

```dart
/// Atomski batch assign — JEDAN undo entry za ceo batch
void batchSetAudioAssignments(Map<String, String> stageToPath) {
  // 1. Snimi staro stanje svih stage-ova kao JEDAN _AudioBatchUndoEntry
  final oldState = <String, String?>{};
  for (final stage in stageToPath.keys) {
    oldState[stage] = _audioAssignments[stage];
  }
  _audioUndoStack.add(_AudioBatchUndoEntry(oldState, stageToPath));
  _audioRedoStack.clear();

  // 2. Primeni sve assignment-e BEZ individualnog undo recording-a
  for (final entry in stageToPath.entries) {
    setAudioAssignment(entry.key, entry.value, recordUndo: false);
  }

  // 3. Jedan notifyListeners() na kraju
  _markDirty();
  notifyListeners();
}
```

### Undo granularnost
- **Batch undo:** Jedan Ctrl+Z vraća SVIH 47 assignment-a na prethodno stanje
- **Undo stack limit:** Postojeći limit od 50 entry-ja se zadržava
- Batch entry broji kao 1 entry, ne 47

---

## 17. TEMP FILE MANAGEMENT

### Strategija
Pipeline kreira međufajlove tokom obrade. Svi se čuvaju u privremenom folderu.

### Lokacija temp fajlova
```
~/.fluxforge/temp/sfx_pipeline/<session_id>/
  ├── trimmed/          (posle trim koraka)
  ├── normalized/       (posle loudness koraka)
  ├── converted/        (posle format koraka)
  └── final/            (renamed, spreman za kopiranje u output)
```

### Lifecycle
1. **Kreiranje:** Na početku "Process All" — kreira session folder sa UUID
2. **Popunjavanje:** Svaki pipeline korak piše u odgovarajući subfolder
3. **Kopiranje:** Finalni fajlovi se kopiraju u output folder (korisnikov izbor)
4. **Čišćenje:** Po završetku pipeline-a — briše ceo session folder
5. **Crash recovery:** Na startup-u, proveri `~/.fluxforge/temp/sfx_pipeline/` za stale session-e starije od 24h → automatski obriši

### Parametar

| Parametar | Tip | Default | Opis |
|---|---|---|---|
| `keepIntermediateFiles` | bool | `false` | Zadrži temp fajlove posle završetka |
| `tempDir` | String | `~/.fluxforge/temp/sfx_pipeline/` | Lokacija temp fajlova |

### ExFAT napomena
Ako je source na ExFAT disku, macOS kreira `._*` fajlove. Temp folder je UVEK na internom disku (`~/`), tako da ovo nije problem za processing. Ali output folder može biti na ExFAT-u — wizard čisti `._*` fajlove iz output-a posle kopiranja.

---

## 18. CONCURRENT SAFETY

### Problem: Spin aktivan tokom wizard-a
Ako korisnik otvori wizard dok slot mašina spinuje, auto-assign može izazvati race condition na `EventRegistry._stageToEvent` mapi.

### Guard pravilo
```dart
// Pre pokretanja auto-assign koraka:
if (slotEngineProvider.isSpinning) {
  // Prikaži dialog:
  // "Slot mašina trenutno spinuje. Auto-assign će se pokrenuti
  //  automatski čim se spin završi."
  await slotEngineProvider.waitForSpinComplete();
}
```

### Pravila
1. **Import/Trim/Loudness/Format/Naming** — sigurni tokom spin-a (offline processing, ne dodiruju audio thread)
2. **Auto-Assign** — MORA čekati kraj spin-a (menja MiddlewareProvider → okida EventRegistry sync)
3. **Preview playback** — koristi `AudioPlaybackService` direktno, NE `EventRegistry.triggerStage()`
4. **Split View:** Wizard ne koristi `_engineRefCount` jer je sav processing u `rf-offline` (odvojen od `rf-engine`)

---

## 19. CANCELLATION & RECOVERY

### Scenariji prekida

| Trenutak prekida | Stanje na disku | Stanje u projektu | Recovery |
|---|---|---|---|
| Tokom Trim (korak 1-2/4) | Parcijalni temp fajlovi | Nepromenjeno | Obriši temp → čisto |
| Tokom Normalize (korak 2/4) | Parcijalni temp fajlovi | Nepromenjeno | Obriši temp → čisto |
| Tokom Export (korak 3/4) | Parcijalni output fajlovi | Nepromenjeno | Obriši output + temp → čisto |
| Tokom Auto-Assign (korak 4/4) | Kompletni output fajlovi | **PARCIJALNI assignment-i** | Ponudi "Undo All" |

### Atomicity pravilo
Auto-assign korak je JEDINI koji menja project state. Ako se prekine:
1. Wizard pamti listu stage-ova koji su uspešno assign-ovani
2. Prikaži dialog: "Assign prekinut na fajlu 25/47. Undo svih 24 uspešnih? [Da, Undo] [Ne, zadrži parcijalne]"
3. Ako korisnik izabere Undo: pozovi `batchUndoAudioAssignments(assignedStages)` (sekcija 16)

### Zatvaranje wizard-a pre "Process All"
Ako korisnik zatvori wizard X dugmetom pre nego što klikne "Process All":
- Ništa se nije promenilo (samo konfiguracija u memoriji)
- Dialog: "Sačuvaj konfiguraciju kao preset za sledeći put? [Da] [Ne]"

---

## 20. PRESET PERSISTENCE

### Storage lokacija
- **Built-in preseti:** Hardkodirani u `sfx_pipeline_config.dart` (6 preseta iz sekcije 10)
- **Custom preseti:** `~/.fluxforge/sfx_presets/<name>.json` — globalni, ne po projektu
- **Poslednji korišćen:** `~/.fluxforge/sfx_presets/_last_used.json` — auto-save posle svakog "Process All"

### Zašto globalno a ne u projektu?
Pipeline preseti su workflow konfiguracija, ne project-specifična. Isti sound dizajner koristi iste LUFS targetove na svim projektima. Ako treba project-specifičan override → "Save Preset" iz wizard-a.

---

## 21. WIZARD UI — IMPLEMENTATION NOTES

### Lifecycle (CLAUDE.md compliance)
- Svi `TextEditingController` kreirani u `initState()`, disposed u `dispose()`
- Svi `FocusNode` kreirani u `initState()`, disposed u `dispose()`
- NIKADA inline u `build()`

### Wizard pattern
Koristi isti pattern kao `onboarding_wizard.dart`:
- `StatefulWidget` + `TickerProviderStateMixin`
- Step enum, `_currentStep` int, slide/fade `AnimationController`
- Static `show()` metod za otvaranje kao modal dialog
- Boja: `LowerZoneColors.slotLabAccent` (#40C8FF cyan)

### Keyboard
- Nema modifier key interakcija u wizard-u
- Enter = Next, Escape = Cancel (standardni dialog behavior)

---

## 22. BUDUĆI RAZVOJ (V2+)

Ove features NISU u V1 ali su predviđene za budućnost:

- **Batch A/B Compare** — slušaj original vs processed side-by-side za svaki fajl
- **Waveform diff view** — vizuelni overlay pre/posle
- **AI Stage Detection** — ML model koji detektuje tip zvuka i predlaže stage
- **Watch folder** — monitor folder za nove fajlove, auto-process
- **Template library** — community-shared pipeline preseti
- **Integration sa Wwise/FMOD** — direktan export u SoundBank format
- **Spektrogram preview** — pored waveform-a prikaži i spektrogram

---

## 23. RESOLOVANA PITANJA (ex-OTVORENA)

| # | Pitanje | Odluka | Obrazloženje |
|---|---|---|---|
| 1 | Mono downmix lokacija | **`rf-offline` Rust crate** | `AudioBuffer.to_mono()` već postoji u `pipeline.rs:164`. Samo proširiti sa 4 nova metoda. Rust je bolji za batch processing (SIMD-ready, zero-copy) |
| 2 | Per-category LUFS overrides | **6 fiksnih + Custom** | 6 ugrađenih kategorija pokriva 95% slot SFX. Korisnik bira "Custom" u dropdown-u za bilo šta van toga. V2 može dodati user-defined kategorije |
| 3 | Preview audio | **Direktan `AudioPlaybackService`** | Preview u koraku 2/3 puši temp fajl, NE koristi EventRegistry (jer stage još nije assign-ovan). `AudioPlaybackService.playAudio(path: tempPath)` |
| 4 | Wizard lokacija | **Modal dialog** | Kao `onboarding_wizard.dart`. Modal jer: (a) wizard je privremeni workflow, ne stalni panel; (b) blokira interakciju sa SlotLab-om što je poželjno tokom pipeline-a; (c) konzistentan sa 5 postojećih wizard-a |
| 5 | Preset storage | **Globalno `~/.fluxforge/sfx_presets/`** | Workflow konfiguracija, ne project data. Detaljno u sekciji 20 |
| 6 | Multi-format output | **Subfolder per format** | Default `subfolderPerFormat: true`. Folder struktura: `output/wav24/sfx_reel_stop.wav`, `output/ogg/sfx_reel_stop.ogg`. Čistije za import u Wwise/FMOD koji očekuju folder-per-platform |

---

## 24. QA CHANGELOG (V1.0 → V1.1)

Promene na osnovu QA audita:

### Ispravke netačnih referenci
- `LufsPresets.game` → **ne postoji**. Ispravljeno na `LoudnessTarget.game` enum u `LoudnessAnalysisService`
- `StageGroupService.performAutoBind()` → **ne postoji**. Ispravljeno na `matchFilesToGroup(StageGroup, List<String>)`
- DC offset removal → **VEĆ POSTOJI** u `rf-offline/src/processors.rs:181` (`DcOffsetProcessor`). Uklonjeno "NOVO"
- Mono downmix → **VEĆ POSTOJI** bazni `AudioBuffer.to_mono()` u `rf-offline/src/pipeline.rs:164`. Samo proširenje
- Resample → **VEĆ POSTOJI** `convert_sample_rate()` u `rf-offline`
- Dither → **VEĆ POSTOJI** `apply_dithering()` u `rf-offline/src/encoder.rs:1153`

### Architectural fixes (CLAUDE.md compliance)
- **EventRegistry:** Wizard NIKADA ne poziva `_syncEventToRegistry()` direktno — to je privatna metoda `_SlotLabScreenState`. Flow ide preko `setAudioAssignment()` → MiddlewareProvider → listener → sync (sekcija 8)
- **Audio thread:** Eksplicitno naglašeno da je sav processing OFFLINE u `rf-offline` crate. Audio thread se ne dodiruje (sekcija 14)
- **Split View:** Nema FFI resource konflikta jer wizard koristi `rf-offline`, ne `rf-engine`

### Nove sekcije
- **§16 Batch Undo** — atomski undo za 47 assignment-a jednim klikom
- **§17 Temp File Management** — lifecycle, cleanup, crash recovery, ExFAT
- **§18 Concurrent Safety** — spin guard, preview isolation, Split View safety
- **§19 Cancellation & Recovery** — parcijalni assignment recovery, atomicity
- **§20 Preset Persistence** — globalni storage, last_used auto-save
- **§21 UI Implementation Notes** — controller lifecycle, wizard pattern, boje

### Resolovana pitanja
- Svih 6 otvorenih pitanja resolovano sa obrazloženjem (§23)

---

*Dokument QA-ovan. Sve API reference verifikovane protiv codebase-a. CLAUDE.md pravila ispoštovana. Edge cases pokriveni. Spreman za implementaciju.*
