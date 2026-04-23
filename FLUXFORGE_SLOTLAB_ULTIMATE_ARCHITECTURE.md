# FluxForge SlotLab — Ultimativna Arhitektura 2026–2030
> Autor: Corti (CORTEX AI) | Datum: 2026-04-14
> Verzija: 1.0 — Vizija pre implementacije
> Namena: Go-to-market strategija, arhitekturalni blueprint, futuristički product roadmap

---

## EXECUTIVE SUMMARY — Zašto bi kompanije kupile FluxForge

Postoji jedan fundamentalni problem u slot industriji koji svi ignorišu:

> **Audio dizajneri kreiraju slot zvukove u alatima koji ništa ne znaju o slot mašinama. Slot matematičari prave math modele u alatima koji ne mogu da reprodukuju zvuk. Između tih svetova ne postoji most — osim Excel tabela i Google Meets-a.**

FluxForge **jeste** taj most. Jedini DAW na svetu koji je istovremeno:
- Profesionalni audio authoring alat (Wwise nivo)
- Kompletni slot game simulator sa pravim Rust math engine-om
- AI sistem koji razume psihologiju igrača i automatski adaptira audio

**Nijedan konkurent ne radi sva tri.** Wwise zna audio, ne zna slot matiku. FMOD je engine, ne simulator. IGT Playa je framework za deployment, ne authoring alat.

---

## DEO 1: TRENUTNO STANJE — Ground Truth

### Šta FluxForge već ima (i zašto je to impresivno)

```
RUST ENGINE (rf-slot-lab crate)
├── SlotEngineV1 — 966 linija, kompletna slot logika
├── SlotEngineV2 — GameModel-driven, 6 feature chapters
│   ├── FreeSpinsChapter (state mašina)
│   ├── CascadesChapter (iterativni cascade sim)
│   ├── HoldAndWinChapter (grid locking, sticky wilds)
│   ├── JackpotChapter (4 tiera, contribution calc)
│   ├── GambleChapter (double-up, risk curve)
│   └── PickBonusChapter (tiered reveals, multiplier)
├── GDD Parser — JSON/YAML → GameModel
├── Scenario System — 5 preseta + custom
├── P5 Win Tiers — dinamička evaluacija
├── FFI — 120+ C funkcija, thread-safe
└── Paytable — 20 payline-ova, scatter, wild

FLUTTER AI SISTEM (35 provajdera)
├── AIL (Adaptive Intelligence Layer) — 10 domena
├── BehaviorTree — 22 node tipa, vizuelno programiranje
├── EmotionalStateProvider — 8 stanja (NEUTRAL→PEAK_EXCITEMENT)
├── PacingEngine — math metrike → audio mood mapping
├── PBSE SimulationEngine — 6 simulacionih modova
├── AurexisProvider — adaptivni music sistem
├── CompositeEventSystem — multi-layer event kompozicija
├── RTPC System — real-time parameter curves
├── MixerDSP — full bus hierarchy, 60fps metering
├── GameFlowProvider — 20-state FSM
└── ... 25 više provajdera

FLUTTER UI (97 widgeta)
├── PremiumSlotPreview — casino-grade vizuelni preview
├── ProfessionalReelAnimation — phase-based reel animacija
├── Hold&Win Visualizer
├── UCP (Universal Control Panel) — 8 monitora
├── BehaviorTree Editor — node-based vizuelni editor
├── SFX Pipeline — 6-step workflow wizard
├── FFNC Renaming — Levenshtein fuzzy matching
├── GDD Import — PDF + JSON/YAML wizard
└── ... mnogo više
```

**Skor vs IGT Playa: 18:3 u korist FluxForge** (detalji u SLOTLAB_VS_PLAYA_ANALYSIS.md)

### Kritični problemi — STATUS

| # | Problem | Status | Datum |
|---|---------|--------|-------|
| 1 | Gamble/PickBonus UI koristi `dart:math` umesto Rust FFI | ✅ REŠENO — Rust FFI wired | 2026-04-15 |
| 2 | JackpotTicker je fake Timer (+0.01/50ms) | ✅ REŠENO — Ispravni growth rates | 2026-04-15 |
| 3 | UCP monitoring paneli pokazuju nule | ✅ REŠENO — Live AUREXIS + VoicePool | 2026-04-15 |
| 4 | GameModel editor ne persistira podatke | ✅ REŠENO — FFI wired kroz SlotEngineProvider | 2026-04-15 |
| 5 | Nema compliance event sistema | ⚠️ DELIMIČNO — Jurisdiction + Audit postoji, fali RGAR export | 2026-04-15 |

### Compliance infrastruktura koja POSTOJI (a nije bila dokumentovana)

```
AUREXIS JURISDICTION SYSTEM (aurexis_jurisdiction.dart)
├── 6 jurisdikcija: UKGC, MGA, GLI-11, Ontario, Australia, Unrestricted
├── JurisdictionRules per jurisdikcija:
│   ├── maxCelebrationDurationS (UK: 5s, AU: 3s)
│   ├── ldwSuppression (UK/Ontario/AU: YES)
│   ├── autoplayWarningMinutes (UK: 60min, Ontario/AU: 30min)
│   ├── maxWinVolumeBoostDb (UK: 6dB, GLI: 12dB)
│   ├── maxEscalationMultiplier (UK: 3x, AU: 2.5x)
│   ├── minFatigueRegulation (AU: 60%)
│   └── requireDeterministicVerification (GLI-11: YES)
├── JurisdictionComplianceEngine — auto-audit + auto-fix
├── ComplianceReportWidget — pass/fail per rule, JSON export
└── MultiJurisdictionReportWidget — svih 6 odjednom

AUDIT TRAIL (aurexis_audit.dart)
├── AuditSession sa sequential ID, timestamp, severity
├── deterministicSeed per entry (GLI-11 replay)
├── AuditActionType: 12 tipova (jurisdictionChange, complianceCheck, ...)
└── toJsonString() export za regulatory submission

QA FRAMEWORK (aurexis_qa.dart)
├── 6 kategorija: config, coverage, determinism, performance, compliance, audioQuality
└── QaReport sa passPercent, fail/warn counts, JSON export

EXPORT SERVISI (services/export/)
├── FMOD Studio exporter
├── Wwise exporter
├── Unity exporter
├── Unreal exporter
├── Godot exporter
├── Howler.js exporter
└── CSV stage asset exporter (stage_asset_csv_exporter.dart)
```

**Zaključak**: Compliance je 70% gotov — fale RGAR report i ComplianceMetadataExporter.

---

## DEO 2: VIZIJA — Šta FluxForge treba da postane

### Paradigma: "Slot Intelligence Platform"

FluxForge nije DAW koji razume slot. FluxForge je **Slot Intelligence Platform** koja se dešava da ima DAW u sebi.

Razlika je fundamentalna:
- **DAW sa slot plugin-om**: Wwise + slot extension → uvek će biti ograničen jer DAW arhitektura nije slot-native
- **Slot Intelligence Platform**: Arhitektura je izgrađena oko slot koncepta, audio engine je subsistem

```
╔══════════════════════════════════════════════════════════════╗
║            FLUXFORGE SLOT INTELLIGENCE PLATFORM              ║
║                                                              ║
║  ┌─────────────────────────────────────────────────────┐    ║
║  │              MATH INTELLIGENCE LAYER                 │    ║
║  │  Math model import → RTP simulation → Audio mapping  │    ║
║  └─────────────────────────────────────────────────────┘    ║
║  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐     ║
║  │  EMOTIONAL   │  │  BEHAVIORAL  │  │  COMPLIANCE   │     ║
║  │  AI ENGINE   │  │  SIMULATION  │  │  GUARDIAN     │     ║
║  └──────────────┘  └──────────────┘  └───────────────┘     ║
║  ┌─────────────────────────────────────────────────────┐    ║
║  │              AUDIO AUTHORING ENGINE                  │    ║
║  │     Rust DSP + Behavior Trees + RTPC + Mixing        │    ║
║  └─────────────────────────────────────────────────────┘    ║
║  ┌─────────────────────────────────────────────────────┐    ║
║  │              EXPORT & DEPLOYMENT LAYER               │    ║
║  │      UCP Protocol → Any casino platform              │    ║
║  └─────────────────────────────────────────────────────┘    ║
╚══════════════════════════════════════════════════════════════╝
```

---

## DEO 3: FUTURISTIČKI STUBOVI — 10 Ideja koje niko nema

### STUB 1: NeuroAudio™ — AI koji čita igrača i adaptira zvuk u realnom vremenu

**Problem koji rešava**: Slot audio je statičan. Isti zvuk čuje gubitnik i dobitnik, anxious igrač i relaxed igrač.

**Šta je to**: AI model koji na osnovu behavioral signala (brzina klika, pauze između spina, session trajanje, win/loss streak) automatski prilagođava ceo audio mix u realnom vremenu.

```
ULAZ (Behavioral Signals):
├── Click velocity (ms između klika i spin-a)
├── Pause patterns (duže pauze = frustration signal)
├── Win/loss streak history
├── Session duration + time of day
├── Bet size changes (povećanje = chasing, smanjenje = cooling down)
└── Near-miss frequency exposure

NEUROAUDIO AI MODEL:
├── 8 dimenzionalni Emotional State Vector
├── Player Arousal Level (0.0–1.0)
├── Risk Tolerance Score
├── Engagement Probability
└── Churn Prediction Score

IZLAZ (Real-time Audio Adaptation):
├── Music tempo ±30% (Aurexis BPM adaptation)
├── Reverb depth (intimacy vs grandeur)
├── Compression ratio (energetska gustina)
├── Win sound magnitude (relativan prema session state-u)
├── Near-miss tension calibration
└── Volume envelope sculpting
```

**Zašto bi ga kupili**: Operatori mogu da dokažu regulatoru da audio ne provocira problem gambling — jer sistem automatski smanjuje tenziju kod high-risk igrača. Compliance AND engagement u jednom sistemu.

**Arhitektura u FluxForge**:
- AIL provajder već ima 10-domain analizu → proširiti sa player input stream-om
- EmotionalState već ima 8 stanja → mapira direktno na player arousal
- RTPC system već postoji → NeuroAudio piše u RTPC parametre

---

### STUB 2: MathAudio Bridge™ — Direktan import math modela → automatska audio mapa

**Problem koji rešava**: Math dizajner kreira paytable u Excelу/posebnom alatu. Audio dizajner dobija PDF. Ručno mapiraju sound triggere. Traje nedelje. Greške su garantovane.

**Šta je to**: FluxForge direktno importuje PAR file, PAR+ file, ili CSV paytable export i automatski:
1. Generiše kompletnu event mapu (svi win kombinovani, scatter counts, bonus triggers)
2. Procenjuje "audio težinu" svakog eventa na osnovu RTP doprinosa
3. Predlaže sound tier za svaki event (WIN_1–WIN_5 pragovi kalibrisani prema RTP distribuciji)
4. Simulira 1M spinova i generiše audio event frequency heatmap

```
MATH FILE IMPORT:
├── PAR (Probability Accounting Report) — industrijski standard
├── PAR+ (extended format sa feature trigger probabilities)
├── CSV paytable exports (AGS, Konami, Aristocrat format)
├── GDD JSON (naš format — već postoji)
└── YAML (naš format — već postoji)

AUTO-GENERATED AUDIO MAP:
├── 847 events → kategorisani po RTP doprinosu
├── Win tier thresholds auto-kalibrisan na distribuciju (ne hardkodovan)
├── Feature trigger rate → anticipation audio density
├── Jackpot contribution → tension curve shape
└── Free spin frequency → bonus audio investment level

SIMULATION OUTPUT:
├── 1M spin audio event timeline (vizuelizovan)
├── Peak simultaneous voices (voice budget validacija)
├── "Dry spells" — periodi bez audio eventa > Xs (engagement dip signal)
└── RNG-weighted win sound distribution pie chart
```

**Zašto bi ga kupili**: Drastično smanjuje vreme razvoja. Ono što je trajalo 3 nedelje rade za 3 sata.

**Arhitektura u FluxForge**:
- GDD Parser već postoji za JSON/YAML → proširiti na PAR format
- Scenario System vec postoji → proširiti sa 1M spin batch mode
- P5 Win Tiers → auto-kalibracija umesto hardkodovanih pragova

---

### STUB 3: Responsible Gaming Audio Intelligence (RGAI)™

**Problem koji rešava**: Regulatori širom sveta (UK GC, Malta MGA, Ontario iGaming) sve strože zahtevaju dokaze da audio ne provocira problem gambling. Ne postoji alat koji to može dokazati kvantitativno.

**Šta je to**: Compliance modul koji kvantitativno analizira svaki audio asset i generiše **Responsible Gaming Audio Report** (RGAR) za regulative.

```
RGAR ANALIZA (po audio asetu):
├── Arousal Coefficient (0.0–1.0) — merenje stimulativnosti zvuka
├── Near-Miss Deception Index — koliko zvuk sugerira "skoro pobeda"
├── Loss-Disguise Score — da li gubitak zvuči kao dobitak
├── Temporal Distortion Factor — da li zvuk distorzira percepciju vremena
└── Addiction Risk Rating (LOW / MEDIUM / HIGH / PROHIBITED)

REGULATORNI EXPORTI:
├── PDF RGAR report (MGA Malta format)
├── XML compliance package (UK GC format)
├── JSON audit trail (sve promene sa timestamps-ima)
└── Digital signature za tamper-proof audit

AUTO-REMEDIATION:
├── Flagovani aseti → auto-sugestija parametra koji treba promeniti
├── "Safe Mode" preset — svi parametri u regulatorno-bezbednom opsegu
└── A/B comparison: original vs compliant verzija
```

**Zašto bi ga kupili**: U UK tržištu, operatori plaćaju milione za compliance consultante. FluxForge zamenjuje 80% toga sa automatizovanim alatom.

**Arhitektura u FluxForge**:
- AIL već analizira arousal i fatigue → ovo je outputovanje tih metrika
- EmotionalState provider → mapira na RGAR kategorije
- Novi RGAI Provider koji agregatira sve AIL domene u compliance score

---

### STUB 4: ProcedualAudio™ Engine — AI generiše slot soundscape iz opisa

**Problem koji rešava**: Audio dizajneri troše mesece na kreiranje sound paketa. Svaki slot zahteva potpuno novi set zvukova. Custom zvuci koštaju $50,000–$200,000 po slot titlu.

**Šta je to**: On-device AI audio generator koji prima text prompt + slot parametrove i generiše funkcionalne audio asete direktno u FluxForge.

```
INPUT:
├── Text prompt: "Ancient Egyptian slot, mystical, desert wind, scarab beetles"
├── Slot parametri: 5-reels, 25-paylines, RTP 96.5%, medium volatility
├── Emotion target: TENSION za anticipation, PEAK_EXCITEMENT za big win
└── Duration specs: reel spin 0.8s, win cel 2.4s, ambient loop

AI GENERATION PIPELINE:
├── Text → Style latent vector (CLAP embedding)
├── Style + Slot params → Audio spec (duration, frequency, dynamics)
├── Audio spec → Waveform generation (Rust AudioCraft port ili API call)
├── Post-processing: loudness normalization (-14 LUFS), format conversion
└── Auto-categorization u FFNC naming sistem

OUTPUT:
├── Reel spin sound (per-reel variations)
├── Win celebration tier 1–5
├── Near-miss anticipation ramp
├── Ambient soundscape loop (seamless)
├── UI button clicks
└── Bonus trigger fanfare
```

**Zašto bi ga kupili**: Indie studio sa $50K budžetom sada može da napravi slot sa professional-grade audio za $0 extra. Mid-size studiji smanjuju audio budget za 60%.

**Arhitektura u FluxForge**:
- FFNC naming sistem već postoji → auto-kategorizacija generisanih aseta
- SFX Pipeline već postoji → generisani aseti idu kroz isti workflow
- Novi AI Generation Provider (cloud API ili local model, switchable)

---

### STUB 5: Universal Casino Protocol (UCP) Export™

**Problem koji rešava**: Svaka casino platforma ima sopstveni audio integration API. Wwise projekt ne radi u Unreal. FMOD projekt ne radi u HTML5. Audio dizajner mora da repakuje isti sadržaj 5 puta za 5 platformi.

**Šta je to**: FluxForge-native format koji se exportuje u SVE casino delivery formate sa jednim klikom.

```
FLUXFORGE → EXPORT TARGETS:

Web/HTML5:
├── Howler.js AudioSprite JSON (Playa kompatibilan format)
├── Web Audio API graph JSON
└── PWA-ready asset manifest

Native Desktop:
├── Wwise .bnk bank files (reverse-engineered format)
├── FMOD .bank files
└── Custom C API header + dylib

Mobile:
├── iOS: AVFoundation asset bundle
├── Android: ExoPlayer asset manifest
└── React Native bridge JSON

Server-Side Rendering:
├── Unity AudioMixer export
└── Unreal MetaSound graph

Casino-Specific:
├── IGT Playa AudioSprite format
├── Scientific Games audio manifest
├── Aristocrat NEON format (tamo gde je dokumentovan)
└── Generic JSON (za custom engines)
```

**Zašto bi ga kupili**: "Buy once, deploy everywhere." Ovo je ono što Wwise radi za game audio, ali za slot specifično sa razumevanjem slot event semantike.

**Arhitektura u FluxForge**:
- Novi Export Engine kao Rust crate (`rf-slot-export`)
- Export targets su pluggable — nova platforma = novi Rust trait impl
- FluxForge binary format (FFB) kao pivot format iz kojeg svi exporti idu

---

### STUB 6: Collaborative Cloud Authoring™

**Problem koji rešava**: Audio dizajner i math dizajner su u različitim gradovima. Sinhronizacija je email + Slack + "koja je poslednja verzija?". Version control za binary audio fajlove ne postoji u game industrijskom workflow-u.

**Šta je to**: Git-inspired cloud collaboration sistem za FluxForge projekte.

```
CLOUD FEATURES:

Real-time collaboration:
├── Multiple audio designers, jedan projekt
├── Track locking (ko radi na čemu — prevent conflicts)
├── Live cursor visibility (vidiš gde drugi rade)
└── Comment annotations na timeline

Version Control:
├── Commit history za FluxForge projekte
├── Branch/merge za audio variante (A/B testing)
├── Diff view — šta se promenilo između verzija
└── Rollback na bilo koji commit

Asset CDN:
├── Binary aseti se ne commituju — čuvaju se u CDN
├── Content-addressed storage (SHA256) — nema duplikata
└── Bandwidth optimizacija (delta sync)

Math-Audio Bridge:
├── Math dizajner commituje PAR file
├── FluxForge detektuje promenu → auto-rekalibracija win tier pragova
└── Audio dizajner dobija notification sa predlogom promena
```

**Zašto bi ga kupili**: Enterprise tier pricing. Studio od 20 ljudi plaća $500/mesec. Samo ušteda na Slack konfuziji opravdava cenu.

---

### STUB 7: A/B Testing Analytics Engine™

**Problem koji rešava**: Ne postoji način da se izmeri koji slot sound paket generiše više angažmana pre deployment-a. Audio izbori su intuitivni, ne data-driven.

**Šta je to**: Integrisani sistem koji A/B testira audio pakete na simuliranoj populaciji igrača pre nego što idu na production.

```
A/B TEST FRAMEWORK:

Setup:
├── Definiši Variant A (audio paket 1) i Variant B (audio paket 2)
├── Definiši simuliranu player populaciju:
│   ├── Player archetypes (casual, regular, high-roller)
│   ├── Session parameters (duration, budget, risk tolerance)
│   └── Sample size (default: 10,000 simulated players)
└── Definiši success metrics

Simulation (Rust engine):
├── 10,000× simulated player sessions per variant
├── Per-player behavioral model (click timing, pause patterns, re-engagement)
├── Audio-behavioral correlation measurement
└── Statistical significance calculator

Output Metrics:
├── Session Duration Score (Variant A vs B)
├── Re-engagement Rate (came back next session)
├── Voluntary Session End Rate (player chose to stop vs forced stop)
├── Near-miss tolerance (kako igrač reaguje na near-miss audio)
├── Win celebration satisfaction score
└── Statistical significance (p-value, confidence interval)

RESPONSIBLE GAMING CHECK:
├── Automatska provera: da li Variant A/B povećava problem gambling indicators?
├── Flag ako Variant X pokazuje >10% veće session extension kod high-risk players
└── RGAR report za oba varijanta
```

**Zašto bi ga kupili**: Data-driven audio odluke. "Naš sound paket povećava session duration za 12% sa 99% statističkom pouzdanošću" — ovo je argument koji kupuje C-suite.

---

### STUB 8: Neural Waveform Fingerprinting™

**Problem koji rešava**: Casino operatori kradu sound pakete. Nema načina da se dokaže da je ukraden zvuk originalan ili kopija.

**Šta je to**: Invisible watermarking sistem koji u svaki exportovani audio asset ugrađuje neuralni fingerprint specifičan za studio, projekt, i datum exporta.

```
FINGERPRINT EMBEDDING:
├── Perceptually invisible modulation (ispod praga čujnosti)
├── Survives: MP3/AAC compression, resampling, loudness normalization
├── Embeds: Studio ID, Project ID, Export timestamp, License type
└── Tamper detection: ako je zvuk izmenjen > threshold, fingerprint se detektuje ali je broken

VERIFICATION:
├── Upload any audio file → FluxForge cloud analizira
├── Detektuje fingerprint ako postoji
├── Vraća: "This file was exported from Studio X, Project Y, on Date Z"
└── Legal-grade chain of custody report

ANTI-PIRACY:
├── Honeypot exports — specijalno označene "leak" verzije za praćenje distribucije
└── Batch verification API — operator može proveriti celu svoju library
```

**Zašto bi ga kupili**: Studios koji imaju krađu zvukova — a svi imaju — odmah plaćaju za ovo. Legal department approved.

---

### STUB 9: 3D Spatial Audio dla VR/AR Slots™

**Problem koji rešava**: VR casino tržište raste 40% godišnje. Ne postoji authoring alat za VR slot audio.

**Šta je to**: Prostorni audio authoring modul koji kreira 3D sound experience za VR i AR slot machine deployment.

```
3D SLOT AUDIO AUTHORING:

Environment Design:
├── 3D casino floor scene editor (top-down view)
├── Slot machine placement u 3D prostoru
├── Wall/floor/ceiling material acoustics (carpet vs marble vs glass)
└── Crowd density simulator (more people = more ambient noise)

Per-Reel Spatialization:
├── Svaki reel ima svoju 3D poziciju u prostoru
├── Reel stop sounds come from physical reel location
├── Win presentation travels across reel positions (left-to-right payline audio)
└── Jackpot: sound expands from machine to fill room

Head Tracking:
├── HRTF (Head-Related Transfer Function) personalizacija
├── Player head position → real-time audio update
├── Haptic integration API (controller vibration sync sa audio)
└── Room correction (player's actual room acoustics)

Export:
├── Spatial audio metadata export (Ambisonics B-format)
├── Meta Quest SDK format
├── Apple Vision Pro AudioGraph format
└── PlayStation VR2 format
```

**Zašto bi ga kupili**: Prva mover advantage. VR casino tržište 2026–2030 je greenfield. Koji studio hoće da napravi VR slot sa 2D audio toolflowitom?

---

### STUB 10: Slot Game AI Co-Pilot™

**Problem koji rešava**: Junior audio dizajner ne zna kako da napravi "Las Vegas feel" ili "Ancient Egypt mystery". Iskusni dizajner ne može da bude na 50 projekata odjednom.

**Šta je to**: AI asistent specifično treniran na slot audio best practices koji daje real-time savete unutar FluxForge.

```
CO-PILOT CAPABILITIES:

Context-Aware Suggestions:
├── "This win celebration is 4.2 seconds — above average for tier WIN_3. 
│    Industry standard: 2.4–2.8s. Shorten?"
├── "Your near-miss anticipation has 0.3s gap between reel 2 and 3 stop.
│    This may not register cognitively. Recommended: <0.15s"
└── "Ambient loop at -8 LUFS will be noticed during reel spin. 
│    Duck to -22 LUFS during spin using RTPC."

Genre Intelligence:
├── 300+ slot themes analyzed (Egyptian, Viking, Fruit, Sci-Fi, etc.)
├── Per-theme audio palette recommendations
├── Competitive analysis: "Pragmatic Play Egyptian slots use modal scales"
└── Auto-suggestion: 5 instrument combinations that match your theme

Math-Aware Suggestions:
├── "Your game has 96.5% RTP with high volatility.
│    High-vol slots need stronger anticipation audio — yours is weak."
├── "Free spin trigger probability is 1/150. 
│    Anticipation should start building at 2 scatters, not 3."
└── "Jackpot contribution: 0.5% of bets. 
│    Your jackpot meter animation is too subtle for this math."

One-Click Fixes:
├── "Apply industry standard" → auto-apply recommendation
├── "Compare with similar slots" → side-by-side A/B view
└── "Generate alternative" → AI creates competing option
```

**Zašto bi ga kupili**: Junior audio designers produce senior-quality work. Studios hire fewer specialists. Each designer covers more titles.

---

## DEO 4: ARHITEKTURALNI BLUEPRINT

### Arhitekturalni Principi

```
1. MATH-FIRST DESIGN
   Svaki audio parametar ima veze sa math modelom.
   Nema magic numbers — sve je kalibrioano na RTP distribuciju.

2. SIMULATION AS GROUND TRUTH  
   Ne pričamo o zvuku u teoriji — simuliramo 1M spinna i merimo.
   Sve audio odluke su data-driven, ne intuitivne.

3. COMPLIANCE BY DESIGN
   RGAI nije opcioni modul — ugrađen je u export pipeline.
   Ne možeš eksportovati bez compliance score-a.

4. OPEN DEPLOYMENT
   UCP Export Layer garantuje da FluxForge projekat radi na bilo kojoj platformi.
   Vendor lock-in nije naša strategija — vrednost je u authoring alatu.

5. AI AUGMENTATION (ne AI replacement)
   AI asistira dizajnera, ne zamenjuje ga.
   Svaka AI sugestija je editable, skippable, dokumentovana.
```

### Revised System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FLUXFORGE STUDIO APP                              │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    SLATE (Main UI)                            │   │
│  │  Timeline │ Mixer │ SlotLab │ BehaviorTree │ Analytics        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                INTELLIGENCE LAYER (Flutter)                   │   │
│  │                                                               │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────────────┐   │   │
│  │  │ NeuroAudio  │ │ RGAI Guard  │ │  AI CoPilot Engine   │   │   │
│  │  │  Provider   │ │  Provider   │ │  Provider            │   │   │
│  │  └─────────────┘ └─────────────┘ └──────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────────────┐   │   │
│  │  │ AIL (10D)   │ │ BehavTree   │ │  EmotionalState (8)  │   │   │
│  │  │ Provider    │ │ Provider    │ │  Provider            │   │   │
│  │  └─────────────┘ └─────────────┘ └──────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────────────┐   │   │
│  │  │ PBSE Sim    │ │ Pacing      │ │  Aurexis Music       │   │   │
│  │  │ Engine      │ │ Engine      │ │  System              │   │   │
│  │  └─────────────┘ └─────────────┘ └──────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                   RUST ENGINE (FFI)                           │   │
│  │                                                               │   │
│  │  ┌────────────┐ ┌──────────────┐ ┌──────────────────────┐   │   │
│  │  │rf-slot-lab │ │ rf-engine    │ │  rf-slot-export      │   │   │
│  │  │ (math sim) │ │ (audio dsp)  │ │  (UCP export)  [NEW] │   │   │
│  │  └────────────┘ └──────────────┘ └──────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌────────────┐ ┌──────────────┐ ┌──────────────────────┐   │   │
│  │  │rf-neuro    │ │ rf-ab-sim    │ │  rf-fingerprint      │   │   │
│  │  │ (AI model) │ │ (batch sim)  │ │  (watermark)   [NEW] │   │   │
│  │  │  [NEW]     │ │  [NEW]       │ │                      │   │   │
│  │  └────────────┘ └──────────────┘ └──────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │  CLOUD SERVICES   │
                    │  (Optional tier)  │
                    ├───────────────────┤
                    │ - Asset CDN       │
                    │ - Collab server   │
                    │ - AI model API    │
                    │ - Fingerprint DB  │
                    └───────────────────┘
```

### Novi Rust Crate-ovi

#### `rf-slot-export` — UCP Export Engine
```rust
pub trait ExportTarget {
    fn export(&self, project: &FluxForgeProject) -> Result<ExportBundle>;
    fn format_name(&self) -> &'static str;
    fn format_version(&self) -> &'static str;
}

pub struct HowlerAudioSpriteExporter;  // Playa compatible
pub struct WwiseBankExporter;          // Wwise .bnk
pub struct FModBankExporter;           // FMOD .bank
pub struct UnityAudioMixerExporter;    // Unity
pub struct UnrealMetaSoundExporter;    // Unreal

impl ExportTarget for HowlerAudioSpriteExporter {
    fn export(&self, project: &FluxForgeProject) -> Result<ExportBundle> {
        // Generiše AudioSprite JSON + sprite sheet audio file
        // Kompatibilan sa IGT Playa formatom
    }
}
```

#### `rf-ab-sim` — Batch Simulation za A/B Testing
```rust
pub struct AbTestConfig {
    pub variant_a: AudioPackage,
    pub variant_b: AudioPackage,
    pub player_population: PlayerPopulationConfig,
    pub sample_size: usize,           // default: 10_000
    pub math_model: GameModel,
    pub success_metrics: Vec<SuccessMetric>,
}

pub struct AbTestResult {
    pub variant_a_metrics: PlayerBehaviorMetrics,
    pub variant_b_metrics: PlayerBehaviorMetrics,
    pub statistical_significance: f64,  // p-value
    pub confidence_interval: (f64, f64),
    pub winner: Option<AbVariant>,
    pub responsible_gaming_flags: Vec<RgFlag>,
}
```

#### `rf-fingerprint` — Neural Audio Watermarking
```rust
pub struct FingerprintEmbedder {
    pub studio_id: Uuid,
    pub strength: f32,  // 0.0–1.0, default: 0.3 (perceptually invisible)
}

impl FingerprintEmbedder {
    pub fn embed(&self, audio: &AudioBuffer, metadata: FingerprintMetadata) -> AudioBuffer;
    pub fn verify(audio: &AudioBuffer) -> Option<FingerprintMetadata>;
    pub fn strength_at_compression_level(compression_ratio: f32) -> f32;
}
```

---

## DEO 5: PHASED IMPLEMENTATION ROADMAP

### TIER 0 — ✅ KOMPLETIRAN (2026-04-15)

| Task | Status | Detalji |
|------|--------|---------|
| T0.1 | ✅ DONE | `gamble_simulator.dart` → Rust FFI (`gambleForceTrigger`, `gambleMakeChoice`, `gambleCollect`) |
| T0.2 | ✅ DONE | `pick_bonus_panel.dart` → Rust FFI (`pickBonusForceTrigger`, `pickBonusMakePick`, `pickBonusComplete`) |
| T0.3 | ✅ DONE | `bonus_game_widgets.dart` → Ispravni progressive growth rates |
| T0.4 | ✅ DONE | UCP live data: `voice_priority_monitor` → VoicePoolProvider, `spectral_heatmap` → AUREXIS 10 banda, `fatigue_stability_dashboard` → AUREXIS, `energy_emotional_monitor` → AUREXIS 5 domena |
| T0.5 | ✅ DONE | `game_model_editor.dart` → FFI wired kroz `SlotEngineProvider.updateGameModel` |

### TIER 1 — Compliance Foundation (1 mesec)
*Bez compliance-a nema enterprise sales.*
*UPDATE: 70% već postoji — fokus na RGAR + export gate*

| Task | Šta | Prioritet | Status |
|------|-----|-----------|--------|
| T1.1 | RGAI Provider — Arousal Coefficient calculator | KRITIČNO | NOVO |
| T1.2 | Near-Miss Deception Index (spectral analysis aseta) | KRITIČNO | NOVO |
| T1.3 | Loss-Disguise Score (win vs loss sound similarity metric) | KRITIČNO | NOVO |
| T1.4 | PDF RGAR Report generator | HIGH | NOVO |
| T1.5 | Export gate: ne možeš exportovati bez compliance score | HIGH | NOVO |
| T1.6 | ComplianceMetadataExporter (audit trail → regulatory format) | HIGH | NOVO |
| T1.7 | Compliance overlay u audio editor | MEDIUM | NOVO |

#### T1.1–T1.3 DETALJNA SPECIFIKACIJA: RGAI Provider

**Fajl**: `flutter_ui/lib/providers/slot_lab/rgai_provider.dart` (NOVI)

RGAI (Responsible Gaming Audio Intelligence) agregatira podatke iz:
- `AurexisProvider` → energyDensity, escalation, fatigue, spectral
- `EmotionalStateProvider` → 8 stanja, arousal nivo
- `PacingEngineProvider` → RTP, volatility, hitFrequency
- `CompositeEventSystemProvider` → event layers, durations
- `SlotEngineProvider` → math model, win tiers

```dart
class RgaiProvider extends ChangeNotifier {
  // ═══ T1.1: Arousal Coefficient (0.0–1.0) ═══
  // Formula: weighted average od:
  //   0.3 × aurexis.energyDensity (koliko je zvuk energetski gust)
  //   0.2 × aurexis.escalation (koliko zvuk eskalira tokom sesije)
  //   0.2 × normalizedBPM (tempo relativno na baseline 120bpm)
  //   0.15 × winCelebrationIntensity (loudness delta win vs ambient)
  //   0.15 × dynamicRange (razlika najtiši–najglasniji momenat)
  double get arousalCoefficient;
  
  // ═══ T1.2: Near-Miss Deception Index (0.0–1.0) ═══
  // Meri koliko near-miss zvuk obmanjuje igrača da je "skoro pobedio"
  // Formula:
  //   0.4 × spectralSimilarity(nearMissSound, winSound) // MFCC cosine distance
  //   0.3 × anticipationBuildupRate // koliko brzo raste tenzija
  //   0.2 × resolveDisappointmentRatio // koliko dugo traje "razočaravajući" zvuk
  //   0.1 × reelStopTimingVariance // da li zadnji reel namerno kasni
  double get nearMissDeceptionIndex;
  
  // ═══ T1.3: Loss-Disguise Score (0.0–1.0) ═══
  // Meri koliko gubitak zvuči kao dobitak (LDW — Loss Disguised as Win)
  // Formula:
  //   0.5 × spectralSimilarity(lossSound, winSound) // osnovna sličnost
  //   0.25 × positiveTonality(lossSound) // da li koristi major key/bright timbres
  //   0.25 × celebratoryElements(lossSound) // fanfare, chimes, jingles u loss eventu
  double get lossDisguiseScore;
  
  // ═══ COMPOSITE: Addiction Risk Rating ═══
  // LOW:        arousal < 0.3 AND nmdi < 0.2 AND lds < 0.2
  // MEDIUM:     arousal < 0.6 AND nmdi < 0.5 AND lds < 0.4
  // HIGH:       any metric > 0.6
  // PROHIBITED: any metric > 0.8 AND jurisdikcija zahteva suppression
  AddictionRiskRating get riskRating;
  
  // ═══ RGAR (Responsible Gaming Audio Report) ═══
  RgarReport generateReport({
    required AurexisJurisdiction jurisdiction,
    required List<SlotCompositeEvent> events,
    required GameModel mathModel,
  });
}
```

**Rust podrška**: Spectral similarity (MFCC cosine distance) se računa u `rf-aurexis`:
- NOVI: `aurexis_spectral_similarity(audio_a_ptr, audio_b_ptr, len)` → `f64`
- NOVI: `aurexis_mfcc_extract(audio_ptr, len, num_coefficients)` → `*mut f64`
- POSTOJEĆI: `aurexis` crate već ima spectral analysis modula

#### T1.4 DETALJNA SPECIFIKACIJA: RGAR PDF Report

**Fajl**: `flutter_ui/lib/services/rgar_report_service.dart` (NOVI)

```
RGAR REPORT STRUKTURA:
├── Header: Studio, Project, Date, Jurisdiction, FluxForge Version
├── Executive Summary: Overall Risk Rating (LOW/MEDIUM/HIGH/PROHIBITED)
├── Section 1: Arousal Analysis
│   ├── Arousal Coefficient: 0.42
│   ├── Breakdown: energy=0.38, escalation=0.45, bpm=0.40, celebration=0.48, dynamics=0.39
│   └── Jurisdiction threshold: 0.60 (UKGC) → PASS ✅
├── Section 2: Near-Miss Audio Analysis
│   ├── NMDI: 0.31
│   ├── Spectral similarity win↔nearMiss: 0.28
│   └── Jurisdiction threshold: 0.50 (UKGC) → PASS ✅
├── Section 3: Loss-Disguise Analysis
│   ├── LDS: 0.18
│   ├── LDW suppression required: YES (UKGC)
│   └── LDW suppression implemented: YES → PASS ✅
├── Section 4: Temporal Analysis
│   ├── Max celebration duration: 4.8s (limit: 5.0s) → PASS ✅
│   ├── Session time cues: ENABLED → PASS ✅
│   └── Autoplay warnings: 60min → PASS ✅
├── Section 5: Per-Asset Breakdown (tabela svih aseta sa individual scores)
├── Section 6: Remediation Recommendations
│   └── "Reduce win celebration intensity at tier WIN_5 by 15%"
├── Section 7: Deterministic Verification (GLI-11)
│   ├── Seed capture: ENABLED
│   └── Replay verification: PASSED (100/100 spins replayed identically)
└── Digital Signature: SHA256 hash + timestamp + studio certificate
```

**Format**: PDF (via `pdf` package) + JSON (machine-readable) + XML (MGA Malta format)

#### T1.5–T1.6 DETALJNA SPECIFIKACIJA: Export Gate + Overlay

**Export Gate** — u `export_service.dart`:
```dart
Future<ExportResult> export(ExportTarget target) async {
  // COMPLIANCE GATE — ne može se zaobići
  final rgai = GetIt.instance<RgaiProvider>();
  final report = rgai.generateReport(
    jurisdiction: activeJurisdiction,
    events: allEvents,
    mathModel: currentModel,
  );
  
  if (report.riskRating == AddictionRiskRating.prohibited) {
    return ExportResult.blocked(
      reason: 'RGAR compliance failed: ${report.violations}',
      report: report,
    );
  }
  
  if (report.riskRating == AddictionRiskRating.high) {
    // Warning, ali dozvoljen export sa potpisom
    attachComplianceWarning(report);
  }
  
  // Attach RGAR report u export bundle
  bundle.addMetadata('rgar_report', report.toJson());
  bundle.addMetadata('rgar_pdf', report.toPdfBytes());
  
  return performExport(target, bundle);
}
```

**Compliance Overlay** — vizuelni indikator u audio editoru:
- Crvena ivica oko aseta sa HIGH/PROHIBITED score
- Tooltip sa tačnim metrikom koji je van opsega
- "Auto-Fix" dugme koje primenjuje jurisdiction-safe parametre

### TIER 2 — MathAudio Bridge™ (1.5 mesec)
*Ovo je ono što DAW-ovi nikad neće imati.*
*UPDATE: GDD Parser (JSON/YAML) + CSV exporter + GddValidatorService već postoje*

| Task | Šta | Prioritet | Status |
|------|-----|-----------|--------|
| T2.1 | PAR file parser (Probability Accounting Report) | KRITIČNO | NOVO |
| T2.2 | Auto-kalibracija win tier pragova iz RTP distribucije | KRITIČNO | NOVO |
| T2.3 | 1M spin batch simulation u Rust (rf-ab-sim crate) | HIGH | NOVO |
| T2.4 | Audio event frequency heatmap visualization | HIGH | NOVO |
| T2.5 | Math-Audio Bridge notification system | MEDIUM | NOVO |
| T2.6 | Peak voice budget prediction iz math modela | MEDIUM | NOVO |
| T2.7 | PAR+ extended format (feature trigger probabilities) | HIGH | NOVO |
| T2.8 | Auto audio map generator (PAR → events) | KRITIČNO | NOVO |

#### T2.1 DETALJNA SPECIFIKACIJA: PAR File Parser

**Fajl (Rust)**: `crates/rf-slot-lab/src/parser/par.rs` (NOVI modul u postojećem parser/)

PAR (Probability Accounting Report) je industrijski standard za matematičke modele slot igara.
Svaka slot kompanija ga generiše za regulatora. Format varira, ali struktura je konzistentna:

```rust
/// PAR file parser — industry standard math model import
pub struct ParParser {
    limits: ParLimits,
}

/// PAR dokument — parsed struktura
pub struct ParDocument {
    // ═══ HEADER ═══
    pub game_name: String,
    pub game_id: String,
    pub rtp_target: f64,              // e.g. 96.50
    pub volatility: VolatilityClass,  // LOW/MEDIUM/HIGH/VERY_HIGH
    pub max_exposure: f64,            // Maksimalni mogući dobitak

    // ═══ GRID ═══
    pub reels: u8,
    pub rows: u8,
    pub paylines: u16,                // 0 = ways-to-win
    pub ways_to_win: Option<u32>,     // e.g. 243, 1024, 117649

    // ═══ SYMBOL TABLE ═══
    pub symbols: Vec<ParSymbol>,
    // ParSymbol { id, name, is_wild, is_scatter, reel_weights: Vec<Vec<u32>> }
    
    // ═══ PAYTABLE ═══
    pub pay_combinations: Vec<PayCombination>,
    // PayCombination { symbol_id, count: 3..=5, payout_multiplier, rtp_contribution }
    
    // ═══ FEATURE TRIGGERS ═══
    pub features: Vec<ParFeature>,
    // ParFeature { type, trigger_probability, avg_payout_multiplier, rtp_contribution }
    
    // ═══ RTP BREAKDOWN ═══
    pub rtp_breakdown: RtpBreakdown,
    // { base_game_rtp, free_spins_rtp, bonus_rtp, jackpot_rtp, gamble_rtp, total_rtp }
    
    // ═══ HIT FREQUENCY ═══
    pub hit_frequency: f64,           // e.g. 0.32 (32% of spins win something)
    pub dead_spin_frequency: f64,     // 1.0 - hit_frequency
}

impl ParParser {
    /// Parse CSV format (AGS, Konami, Aristocrat exports)
    pub fn parse_csv(csv: &str) -> Result<ParDocument>;
    
    /// Parse Excel-derived format (Scientific Games, IGT)
    pub fn parse_xlsx_csv(csv: &str) -> Result<ParDocument>;
    
    /// Parse JSON PAR (naš native format + modern studios)
    pub fn parse_json(json: &str) -> Result<ParDocument>;
    
    /// Convert to GameModel (za SlotEngine V2)
    pub fn to_game_model(&self, doc: &ParDocument) -> GameModel;
    
    /// Validate PAR math (RTP breakdown mora da se slaže sa total)
    pub fn validate(&self, doc: &ParDocument) -> ParValidationReport;
}
```

**Podržani formati**:
- CSV (najčešći — AGS, Konami, Aristocrat, Everi)
- JSON (moderni studiji)
- Auto-detect (heuristika na osnovu header reda)

**FFI (slot_lab_ffi.rs)**:
- `slot_lab_par_parse(data_ptr, data_len, format)` → `*mut c_char` (JSON ParDocument)
- `slot_lab_par_to_game_model(par_json_ptr, par_json_len)` → `*mut c_char` (JSON GameModel)
- `slot_lab_par_validate(par_json_ptr, par_json_len)` → `*mut c_char` (ValidationReport)

**Dart servis**: `flutter_ui/lib/services/par_import_service.dart`
```dart
class ParImportService {
  final NativeFFI _ffi;
  
  ParImportResult importFromFile(String path);
  ParImportResult importFromCsv(String csvContent);
  GameModel convertToGameModel(ParDocument par);
  ParValidationReport validate(ParDocument par);
}
```

#### T2.2 DETALJNA SPECIFIKACIJA: Auto-kalibracija Win Tier Pragova

**Princip**: Win tier pragovi (WIN_1–WIN_5 thresholds) NE smeju biti hardkodovani.
Moraju se izračunati iz RTP distribucije specifične za tu igru.

**Rust (rf-slot-lab/src/model/win_tiers.rs — PROŠIRENJE)**:
```rust
/// Auto-kalibriši win tier pragove iz PAR distribucije
pub fn auto_calibrate_win_tiers(par: &ParDocument) -> Vec<RegularWinTier> {
    // 1. Sortiraj sve pay_combinations po payout_multiplier
    // 2. Grupiši u percentile klastere:
    //    WIN_1: 0-50th percentile (najčešći, najmanji dobitci)
    //    WIN_2: 50-75th percentile
    //    WIN_3: 75-90th percentile
    //    WIN_4: 90-97th percentile
    //    WIN_5: 97-100th percentile (najređi, najveći)
    // 3. Svaki tier dobija from/to multiplier na osnovu klastera
    // 4. Audio intenzitet proporcionalan RTP doprinosu
    //    (tier koji doprinosi više RTP-u = glasniji/duži celebration)
    // 5. Rollup duration kalibrisana na payout veličinu:
    //    WIN_1: 0.5s, WIN_2: 1.0s, WIN_3: 2.0s, WIN_4: 3.5s, WIN_5: 5.0s
}
```

**Ovo zamenjuje** ručno podešavanje thresholds-a u GameModel editoru.
Dizajner importuje PAR → FluxForge automatski kalibriše → dizajner fine-tune-uje.

#### T2.3 DETALJNA SPECIFIKACIJA: 1M Spin Batch Simulation

**Rust crate**: `crates/rf-ab-sim/` (NOVI crate)

```rust
pub struct BatchSimConfig {
    pub game_model: GameModel,
    pub spin_count: u64,           // default: 1_000_000
    pub audio_events: Vec<AudioEventDef>,
    pub player_archetypes: Vec<PlayerArchetype>,
    pub threads: u8,               // default: num_cpus
}

pub struct BatchSimResult {
    pub actual_rtp: f64,
    pub event_frequency_map: HashMap<String, EventFrequency>,
    // EventFrequency { count, avg_per_1000_spins, peak_concurrent, min_gap_ms }
    pub peak_simultaneous_voices: u32,
    pub dry_spell_analysis: DrySpellReport,
    // DrySpellReport { max_dry_spins, avg_dry_spins, dry_spell_histogram }
    pub win_distribution: WinDistribution,
    // WinDistribution { per_tier_count, per_tier_rtp_contribution }
    pub timeline_samples: Vec<TimelineSample>,
    // Za vizuelizaciju: svaki 1000-ti spin sa event listom
}

impl BatchSimulator {
    /// Paralelna simulacija sa Rayon
    pub fn run(config: &BatchSimConfig) -> BatchSimResult;
    
    /// Progress callback za UI (svakih 10000 spinova)
    pub fn run_with_progress(config: &BatchSimConfig, cb: impl Fn(f64)) -> BatchSimResult;
}
```

**FFI**:
- `slot_lab_batch_sim_start(config_json)` → task_id
- `slot_lab_batch_sim_progress(task_id)` → `f64` (0.0–1.0)
- `slot_lab_batch_sim_result(task_id)` → `*mut c_char` (JSON BatchSimResult)
- `slot_lab_batch_sim_cancel(task_id)`

#### T2.4 DETALJNA SPECIFIKACIJA: Audio Event Frequency Heatmap

**Widget**: `flutter_ui/lib/widgets/slot_lab/analytics/event_frequency_heatmap.dart` (NOVI)

Vizuelizacija rezultata batch simulacije:
```
┌──────────────────────────────────────────────────────────────┐
│ AUDIO EVENT FREQUENCY HEATMAP (1M spins)                     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  REEL_SPIN      ████████████████████████████████  1000/1000  │
│  REEL_STOP      ████████████████████████████████  1000/1000  │
│  WIN_1          ██████████████████░░░░░░░░░░░░░░  186/1000   │
│  WIN_2          ████████░░░░░░░░░░░░░░░░░░░░░░░░  84/1000    │
│  WIN_3          ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░  31/1000    │
│  WIN_4          █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  7/1000     │
│  WIN_5          ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0.8/1000   │
│  FREE_SPIN_TRG  ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  6.7/1000   │
│  NEAR_MISS      ████████████░░░░░░░░░░░░░░░░░░░░  120/1000   │
│  JACKPOT        ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0.01/1000  │
│                                                              │
│  🔴 Peak voices: 14/48 (29%)  ⚠️ Max dry spell: 47 spins    │
│  📊 Actual RTP: 96.48% (target: 96.50%)                     │
└──────────────────────────────────────────────────────────────┘
```

#### T2.8 DETALJNA SPECIFIKACIJA: Auto Audio Map Generator

**Servis**: `flutter_ui/lib/services/math_audio_bridge_service.dart` (NOVI)

Ovo je SRCE MathAudio Bridge-a. Kada se importuje PAR:

```dart
class MathAudioBridgeService {
  /// PAR → kompletna event mapa (svi trigeri, svi win tieri, sve features)
  AudioEventMap generateEventMap(ParDocument par) {
    // 1. Base game events:
    //    - SPIN_START, REEL_SPIN, REEL_STOP_0..N, SPIN_END
    //    - WIN_LOW (< 1x bet), WIN_EQUAL (1x), WIN_1..WIN_5 (auto-calibrated)
    //    - NEAR_MISS (2/3 scatter, reel-specific)
    //    - DEAD_SPIN (no win)
    
    // 2. Feature triggers (iz par.features):
    //    - FREE_SPIN_TRIGGER, FREE_SPIN_RETRIGGER
    //    - BONUS_TRIGGER
    //    - HOLD_AND_WIN_TRIGGER
    //    - JACKPOT_WON_MINI/MINOR/MAJOR/GRAND
    //    - CASCADE_START, CASCADE_WIN
    //    - GAMBLE_AVAILABLE
    
    // 3. Audio weight per event (RTP contribution based):
    //    event.audioWeight = event.rtpContribution / totalRtp
    //    Veći audioWeight = glasnija, duža, impresivnija celebracija
    
    // 4. Suggested tier za svaki event:
    //    audioWeight < 0.01 → subtle (background SFX)
    //    audioWeight 0.01-0.05 → standard (normal celebration)
    //    audioWeight 0.05-0.15 → prominent (big win territory)
    //    audioWeight > 0.15 → flagship (jackpot-level audio)
    
    return AudioEventMap(events, warnings, coverage);
  }
  
  /// Simuliraj i prikaži voice budget predictions
  VoiceBudgetPrediction predictVoiceBudget(ParDocument par, AudioEventMap map);
}

### TIER 3 — Export Layer (1 mesec)
*"Buy once, deploy everywhere" — ovo prodaje.*

| Task | Šta | Prioritet |
|------|-----|-----------|
| T3.1 | rf-slot-export crate sa ExportTarget trait | KRITIČNO |
| T3.2 | Howler.js AudioSprite exporter (Playa compat) | KRITIČNO |
| T3.3 | Wwise .bnk exporter (reverse engineered) | HIGH |
| T3.4 | FMOD .bank exporter | HIGH |
| T3.5 | Generic JSON exporter (custom engines) | MEDIUM |
| T3.6 | Export validation: test roundtrip svaki format | HIGH |

### TIER 4 — NeuroAudio™ (2 meseca)
*Jedinstvenost koja ne može biti kopirana bez godina rada.*
*UPDATE: EmotionalState (8), AIL (10D), PacingEngine, AUREXIS već postoje — NeuroAudio je PROŠIRENJE*

| Task | Šta | Prioritet | Status |
|------|-----|-----------|--------|
| T4.1 | Player behavioral signal input stream (click timing, pause patterns) | KRITIČNO | NOVO |
| T4.2 | Real-time Player State Vector (8D) od behavioral signals | KRITIČNO | NOVO |
| T4.3 | NeuroAudio → RTPC mapping (Player State → audio parameters) | KRITIČNO | NOVO |
| T4.4 | BPM adaptation u Aurexis na osnovu player arousal | HIGH | NOVO |
| T4.5 | Responsible Gaming mode: auto-reduce tenziju kod high-risk igrača | HIGH | NOVO |
| T4.6 | Player State visualization u UCP | MEDIUM | NOVO |
| T4.7 | Churn Prediction Score (predviđanje da igrač napušta) | HIGH | NOVO |
| T4.8 | NeuroAudio Authoring Mode (dizajner preview-uje player states) | KRITIČNO | NOVO |

#### T4.1–T4.2 DETALJNA SPECIFIKACIJA: Player Behavioral Signal Stream

**Rust crate**: `crates/rf-neuro/` (NOVI crate)

```rust
/// Real-time player behavioral signal processor
pub struct NeuroEngine {
    state: PlayerStateVector,
    history: VecDeque<BehavioralSample>,  // klizni prozor 5min
    config: NeuroConfig,
}

/// Jedan behavioral uzorak (primljen svaki spin ili klik)
pub struct BehavioralSample {
    pub timestamp_ms: u64,
    pub event_type: BehavioralEvent,
    pub value: f64,
}

pub enum BehavioralEvent {
    SpinClick,                  // igrač kliknuo spin
    SpinResult(SpinOutcome),    // rezultat spina (win/loss/near-miss)
    BetChange(f64),             // promena veličine uloga
    Pause,                      // igrač ne radi ništa (>3s)
    FeatureTriggered,           // bonus/free spins aktiviran
    CashOut,                    // igrač podiže novac (delimično)
    AutoplayToggle(bool),       // uključio/isključio autoplay
}

/// 8-dimenzionalni Player State Vector
/// Svaka dimenzija je 0.0–1.0
pub struct PlayerStateVector {
    pub arousal: f64,           // 0=mirno, 1=uzbuđeno
    pub valence: f64,           // 0=negativno, 1=pozitivno
    pub engagement: f64,        // 0=dosada, 1=potpuno angažovan
    pub risk_tolerance: f64,    // 0=konzervativan, 1=agresivan
    pub frustration: f64,       // 0=nema, 1=visoka
    pub anticipation: f64,      // 0=nema, 1=očekuje veliki dobitak
    pub fatigue: f64,           // 0=svež, 1=umoran
    pub churn_probability: f64, // 0=ostaje, 1=napušta
}

impl NeuroEngine {
    pub fn new(config: NeuroConfig) -> Self;
    
    /// Procesira behavioral event i ažurira Player State Vector
    pub fn process_event(&mut self, sample: BehavioralSample) -> &PlayerStateVector;
    
    /// Batch process za simulaciju (dizajner preview)
    pub fn simulate_session(&mut self, events: &[BehavioralSample]) -> Vec<PlayerStateVector>;
    
    /// Kalkuliši preporučene audio parametre na osnovu stanja
    pub fn compute_audio_adaptation(&self) -> AudioAdaptation;
}

/// NeuroAudio output — direktno mapira na RTPC parametre
pub struct AudioAdaptation {
    pub music_bpm_multiplier: f64,     // 0.7–1.3 (±30% od base BPM)
    pub reverb_depth: f64,             // 0.0–1.0 (intimacy ↔ grandeur)
    pub compression_ratio: f64,        // 1.0–8.0 (energetska gustina)
    pub win_magnitude_bias: f64,       // 0.5–2.0 (relativno prema session state)
    pub tension_calibration: f64,      // 0.0–1.0 (near-miss tension level)
    pub volume_envelope_shape: f64,    // 0.0–1.0 (0=flat, 1=dynamic)
    pub hf_brightness: f64,            // 0.0–1.0 (fatigue → reduce HF)
    pub spatial_width: f64,            // 0.0–1.0 (intimate→wide)
}
```

**Logika procesiranja**:
```
SpinClick timing:
  - avg < 500ms → impulsivan (arousal↑, risk_tolerance↑)
  - avg 500ms–2s → normalan
  - avg > 3s → hesitant (frustration↑, engagement↓)

Pause patterns:
  - Pauza > 5s posle gubitka → frustration↑, churn↑
  - Pauza > 5s posle dobitka → satisfaction (arousal↓, valence↑)
  - Nema pauze 10+ spinna → autopilot (engagement↓, fatigue↑)

Bet changes:
  - Bet↑ posle gubitka → chasing (risk_tolerance↑, frustration↑) → RG FLAG
  - Bet↓ posle gubitka → cooling (risk_tolerance↓)
  - Bet↑ posle dobitka → confidence (arousal↑)

Win/Loss streaks:
  - 10+ gubitaka → frustration↑, churn↑, engagement↓
  - 3+ dobitaka → arousal↑, anticipation↑, engagement↑
  - Near-miss → anticipation↑↑ (ali frustration↑ ako učestalo)
```

**FFI**:
- `neuro_engine_create(config_json)` → `i64` (engine_id)
- `neuro_engine_process(engine_id, event_json)` → `*mut c_char` (PlayerStateVector JSON)
- `neuro_engine_adaptation(engine_id)` → `*mut c_char` (AudioAdaptation JSON)
- `neuro_engine_simulate(engine_id, events_json)` → `*mut c_char` (Vec<PSV> JSON)
- `neuro_engine_destroy(engine_id)`

#### T4.3 DETALJNA SPECIFIKACIJA: NeuroAudio → RTPC Mapping

**Fajl**: `flutter_ui/lib/providers/slot_lab/neuro_audio_provider.dart` (NOVI)

```dart
class NeuroAudioProvider extends ChangeNotifier {
  final NativeFFI _ffi;
  final RtpcProvider _rtpc;
  final AurexisProvider _aurexis;
  final EmotionalStateProvider _emotional;
  
  PlayerStateVector _currentState = PlayerStateVector.neutral();
  AudioAdaptation _currentAdaptation = AudioAdaptation.neutral();
  
  /// Procesira behavioral event iz SlotLab simulatora
  void onBehavioralEvent(BehavioralEvent event) {
    _currentState = _ffi.neuroEngineProcess(_engineId, event);
    _currentAdaptation = _ffi.neuroEngineAdaptation(_engineId);
    
    // MAP adaptation → RTPC parameters
    _rtpc.setParameter('neuro_bpm_mult', _currentAdaptation.musicBpmMultiplier);
    _rtpc.setParameter('neuro_reverb', _currentAdaptation.reverbDepth);
    _rtpc.setParameter('neuro_compression', _currentAdaptation.compressionRatio);
    _rtpc.setParameter('neuro_win_bias', _currentAdaptation.winMagnitudeBias);
    _rtpc.setParameter('neuro_tension', _currentAdaptation.tensionCalibration);
    _rtpc.setParameter('neuro_volume_shape', _currentAdaptation.volumeEnvelopeShape);
    _rtpc.setParameter('neuro_hf_bright', _currentAdaptation.hfBrightness);
    _rtpc.setParameter('neuro_spatial', _currentAdaptation.spatialWidth);
    
    // Responsible Gaming auto-intervention
    if (_currentState.churnProbability > 0.8) {
      _applyResponsibleGamingMode();
    }
    
    notifyListeners();
  }
  
  /// RG mode: automatski smanji tenziju kod high-risk igrača
  void _applyResponsibleGamingMode() {
    _rtpc.setParameter('neuro_tension', 0.1);        // minimalna tenzija
    _rtpc.setParameter('neuro_win_bias', 0.5);        // normalan win zvuk
    _rtpc.setParameter('neuro_bpm_mult', 0.8);        // sporiji tempo
    _rtpc.setParameter('neuro_hf_bright', 0.3);       // mekši zvuk
  }
}
```

#### T4.8 DETALJNA SPECIFIKACIJA: NeuroAudio Authoring Mode

**KLJUČNO**: Audio dizajner mora da čuje kako zvuči igra za različite tipove igrača.

**Widget**: `flutter_ui/lib/widgets/slot_lab/neuro/neuro_authoring_panel.dart` (NOVI)

```
┌──────────────────────────────────────────────────────────────┐
│ NEUROAUDIO™ AUTHORING                                        │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  PLAYER ARCHETYPE: [Casual ▾] [Frustrated ▾] [Whale ▾]      │
│                                                              │
│  ┌──── Player State Vector ────────────────────────────────┐ │
│  │ Arousal     ████████░░░░░░░░  0.52                      │ │
│  │ Valence     ██████░░░░░░░░░░  0.38                      │ │
│  │ Engagement  ██████████████░░  0.87                      │ │
│  │ Risk        ████░░░░░░░░░░░░  0.25                      │ │
│  │ Frustration ██████████░░░░░░  0.62                      │ │
│  │ Anticipatn  ████████░░░░░░░░  0.48                      │ │
│  │ Fatigue     ██░░░░░░░░░░░░░░  0.15                      │ │
│  │ Churn       ████████████████  0.71  ⚠️ HIGH             │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                              │
│  AUDIO ADAPTATION (live preview):                            │
│  🎵 BPM: 96 (-20%)  🎚 Reverb: 0.7  🔊 Win bias: 0.6      │
│  🎛 Compression: 2.1  ⚡ Tension: 0.2  🔈 HF: 0.3          │
│                                                              │
│  [▶ SIMULATE SESSION] [📊 COMPARE ARCHETYPES] [💾 PRESET]   │
└──────────────────────────────────────────────────────────────┘
```

Dizajner može:
1. Izabrati player archetype (Casual/Regular/HighRoller/Frustrated/Addicted)
2. Videti u realnom vremenu kako se menja Player State Vector
3. Čuti live preview audio adaptirano za taj archetype
4. Simulirati celu sesiju (200 spinova) i čuti kako se audio menja tokom vremena
5. Uporediti dva archetype-a side-by-side (A/B)
6. Sačuvati presetove za specifične player profile

### TIER 5 — AI Co-Pilot™ (1.5 mesec)
*Junior designer → senior output.*

| Task | Šta | Prioritet |
|------|-----|-----------|
| T5.1 | Context-aware suggestion engine (rule-based, fast) | HIGH |
| T5.2 | Industry standard database (300+ analyzed slots) | HIGH |
| T5.3 | Math-aware audio suggestions | HIGH |
| T5.4 | One-click "apply industry standard" | MEDIUM |
| T5.5 | LLM integration za natural language queries (optional cloud) | LOW |

### TIER 6 — A/B Analytics + Fingerprinting (1 mesec)
*Enterprise tier features.*

| Task | Šta | Prioritet |
|------|-----|-----------|
| T6.1 | rf-fingerprint crate (watermark embed/verify) | HIGH |
| T6.2 | A/B test setup UI | HIGH |
| T6.3 | Statistical significance calculator | HIGH |
| T6.4 | Fingerprint verification API | MEDIUM |
| T6.5 | Honeypot export mode | LOW |

### TIER 7 — Cloud + 3D Spatial (2 meseca)
*Premium differentiator, ne blokira osnovni product.*

| Task | Šta | Prioritet |
|------|-----|-----------|
| T7.1 | Cloud project sync (Git-like) | MEDIUM |
| T7.2 | 3D scene editor za VR slot positioning | MEDIUM |
| T7.3 | HRTF-based spatialization | MEDIUM |
| T7.4 | Ambisonics export (B-format) | LOW |
| T7.5 | Real-time collaboration | LOW (complex) |

### TIER 8 — Procedural AI Generation (3 meseca+)
*Game changer, ali najkompleksniji.*

| Task | Šta | Prioritet |
|------|-----|-----------|
| T8.1 | Text prompt → audio spec pipeline | MEDIUM |
| T8.2 | Local AI model integration (AudioCraft) ili cloud API | MEDIUM |
| T8.3 | Post-processing pipeline (loudness, format) | LOW |
| T8.4 | Auto-FFNC categorizacija generisanih aseta | LOW |

---

## DEO 6: TRŽIŠNA STRATEGIJA

### Ciljni Kupci

```
TIER A — Enterprise (AAA casino game studios)
Primeri: Scientific Games, IGT, Everi, Aristocrat, AGS
Potrebe: Compliance, export compatibility, team collaboration
Cena: $2,000–$5,000/mesec/studio (enterprise licenca)
Prodajni argument: RGAI compliance, UCP Export (sve platforme), A/B analytics

TIER B — Mid-size iGaming studiji
Primeri: Push Gaming, Thunderkick, ELK Studios, Red Tiger
Potrebe: Professional output sa manjim timom, brži development
Cena: $500–$1,500/mesec/studio
Prodajni argument: AI Co-Pilot (junior → senior output), SFX Pipeline (speed), MathAudio Bridge

TIER C — Indie slot studiji
Primeri: Nezavisni developer timovi koji prodaju na B2B platformama
Potrebe: Jeftin pristup professional-grade alatig
Cena: $99–$299/mesec
Prodajni argument: Procedural AI Generation (nema budget za audio dizajnere), sve funkcije professional DAW-a

TIER D — Regulatorne agencije
Primeri: UK GC, Malta MGA, Ontario iGaming
Potrebe: Compliance audit alat
Cena: Per-audit fee ili godišnja licenca
Prodajni argument: RGAR report — jedini kvantitativni audio compliance alat
```

### Konkurentska Pozicija

```
                    │ Slot-Native │ AI/Adaptive │ Compliance │ Export All │
────────────────────┼─────────────┼─────────────┼────────────┼────────────┤
Wwise               │     NO      │    Partial  │     NO     │  Partial   │
FMOD                │     NO      │     NO      │     NO     │    NO      │
IGT Playa           │    YES      │     NO      │   Partial  │  IGT only  │
Custom engines      │    YES      │     NO      │   Manual   │  1 target  │
────────────────────┼─────────────┼─────────────┼────────────┼────────────┤
FluxForge (target)  │   ██████   │   ██████   │  ██████   │  ██████   │
```

### Jedinstven Prodajni Argument (USP)

> **"FluxForge je jedini alat koji razume i slot matematiku i audio psihologiju — i može da dokaže regulatoru da su oba u skladu sa responsible gaming standardima."**

Ovo je jedina rečenica koja zatapa Wwise, FMOD, i Playa istovremeno.

### Pricing Strategy

```
STARTER (Indie)      — $149/mesec
├── FluxForge core DAW
├── SlotLab (basic)
├── 1 UCP Export target
└── RGAR basic

PROFESSIONAL        — $599/mesec  
├── Sve iz Starter
├── Full SlotLab (svi bonus simulatori)
├── MathAudio Bridge
├── A/B Analytics (1,000 simulations/mesec)
├── 5 UCP Export targets
├── RGAR full report
└── AI Co-Pilot (rule-based)

ENTERPRISE         — $2,499/mesec
├── Sve iz Professional
├── NeuroAudio™ (player adaptation)
├── Unlimited A/B Analytics
├── Collaboration (5 users)
├── All UCP Export targets
├── Neural Fingerprinting
├── Priority support
└── Custom compliance reports

ENTERPRISE+        — Custom pricing
├── Sve iz Enterprise
├── On-premise deployment
├── SLA garantije
├── Custom export formats
└── Regulator audit support
```

---

## DEO 7: KOMPETITIVNE BARIJERE

### Zašto niko ne može kopirati FluxForge u 2 godine

```
1. RUST MATH ENGINE (18+ meseci rada)
   rf-slot-lab crate sa V2 feature chapters — ovo nije trivijalno.
   Competitor koji hoće da napravi isto mora da počne od nule.

2. VERTIKALNA INTEGRACIJA
   DAW + Math Simulator + AI Layer + Export = 4 firme koje bi morale
   da se udruže. Wwise ne zna slot matiku. IGT ne pravi authoring alate.
   Niko ne radi sve četiri.

3. AI TRAINING DATA
   NeuroAudio model treniran na slot-specific behavioral data.
   To se ne može kupiti — mora se sakupiti tokom deployment-a.
   First mover advantage → više podataka → bolji model → više kupaca.

4. COMPLIANCE DATABASE
   Industry standard database (300+ analyzed slots) + RGAR format.
   Svaki novi analizirani slot poboljšava AI Co-Pilot.
   Network effect: više korisnika → više analyzed slots → bolji saveti.

5. SLOT INDUSTRY KNOWLEDGE
   Arhitektura FluxForge je ugrađena sa slot domain znanjem
   (anticipation tiers, near-miss psychology, cascade timing, etc.)
   koji generalist DAW timovi ne mogu steći bez slot industry iskustva.
```

---

## DEO 8: IMMEDIATE ACTION PLAN

### Nedelja 1–2: Tier 0 (Hitno)
Sve placeholder-e zameniti sa pravim FFI pozivima. Bez toga, svaka demo je sramota.

### Nedelja 3–6: Tier 1 (Compliance)
RGAI Provider + RGAR report. Ovo je Tier A enterprise sales key.

### Nedelja 7–10: Tier 2 (MathAudio Bridge)
PAR parser + win tier auto-kalibracija + batch simulation. Ovo je diferencirajući faktor vs Wwise.

### Nedelja 11–14: Tier 3 (Export)
UCP export layer. "Buy once, deploy everywhere" argument.

### Meseci 4–6: Tiers 4–5 (NeuroAudio + Co-Pilot)
Ovo su flagship features za marketing. "AI koji adaptira slot zvuk u realnom vremenu" — novinarska tema.

### Meseci 7–9: Tiers 6–7 (Analytics + Cloud)
Enterprise tier rounding out. Collaborative features za large studios.

### Meseci 10–12: Tier 8 (Procedural AI)
Ako je tržišna validacija dobra, procedural audio je "wow factor" za narednu godinu.

---

## DEO 9: RIZICI I MITIGATION

| Rizik | Verovatnoća | Mitigation |
|-------|------------|------------|
| Wwise lansira slot plugin | MEDIUM | Vertical integration + compliance moat su odbrana. Wwise ne može imati math engine bez slot industrijskog znanja |
| Casino ne prihvata RGAR format | LOW | Raditi sa MGA, UK GC na standardizaciji. Biti autor standarda |
| AI Co-Pilot daje loše savete | HIGH | Sve sugestije su optional + editable. "Apply" je explicit user action. No auto-apply |
| Cloud collab privacy (gaming IP) | HIGH | On-premise deployment opcija za Enterprise+. End-to-end encryption |
| Procedural AI output quality | HIGH | Ovo je Tier 8 — ima vremena za R&D. Ne obećavati pre nego što radi |
| Regulatorna promena (RGAR zastareo) | MEDIUM | Modularni compliance sistem — format je pluggable, update je deployable |

---

## ZAKLJUČAK

FluxForge SlotLab već ima najsnažniju tehničku osnovu od svih alata u slot industriji. Problem nije "šta imamo" — problem je da niko to ne zna i da half of it radi na `dart:math`.

**Posle Tier 0 fixeva**, FluxForge je demonstrabilno superioran od svakog konkurenta na tehničkom nivou.

**Posle Tier 1 (compliance)**, FluxForge može ući u enterprise sales razgovor sa AAA studiima.

**Posle Tier 2 (MathAudio Bridge)**, FluxForge ima jedinstven feature koji Wwise nikad neće imati.

**Posle Tier 3 (Export Layer)**, FluxForge je jedini "write once, deploy everywhere" slot audio authoring alat.

**Posle Tiers 4–5 (NeuroAudio + Co-Pilot)**, FluxForge je platforma koja ne može biti kopirana bez 2+ godina rada.

---

*Dokument kreiran: 2026-04-14*
*Autor: Corti (CORTEX AI)*
*Status: WORKING DOCUMENT — pre implementacije*
*Naredni korak: Tier 0 implementacija*
