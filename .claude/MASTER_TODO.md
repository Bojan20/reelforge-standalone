# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-02
**Master Spec:** `FLUXFORGE_MASTER_SPEC.md` (consolidated reference)

---

## ALL SYSTEMS COMPLETE — 182/182 ✅

```
COMPLETED SYSTEMS:
  AUREXIS™: 88/88 ✅
  SlotLab Middleware Providers: 19/19 ✅
  Hook Translation: ✅
  Emotional Engine: ✅
  DAW Mixer: Pro Tools 2026-class — ALL 5 PHASES ✅
  DSP Panels: 16/16 premium FabFilter GUIs ✅
  EQ: ProEq unified superset (FF-Q 64) ✅
  Master Bus: 12 insert slots, LUFS + True Peak ✅
  Stereo Imager: 45/45 tasks ✅
  Unified Track Graph: 31/31 tasks ✅
  Naming Bible: Spec complete, AutoBind uses it ✅

  P-SRC: Audio Engine SRC Fixes ✅ (5/5)
  P-GEG: Global Energy Governance ✅ (12/12)
  P-DPM: Dynamic Priority Matrix ✅ (10/10)
  P-SAMCL: Spectral Allocation & Masking ✅ (12/12)
  P-PBSE: Pre-Bake Simulation Engine ✅ (10/10)
  P-AIL: Authoring Intelligence Layer ✅ (8/8)
  P-DRC: DRC, Manifest & Safety Envelope ✅ (12/12)
  P-DEV: Device Preview Engine ✅ (14/14)
  P-SAM: Smart Authoring Mode ✅ (10/10)
  P-UCP: Unified Control Panel ✅ (8/8)
  P-MWUI: SlotLab Middleware UI Views ✅ (8/8)
  P-GAD: Gameplay-Aware DAW ✅ (10/10)
  P-SSS: Scale & Stability Suite ✅ (10/10)

  P-FMC: FluxMacro System ✅ (53/53 — ALL 6 PHASES)
    Phase 1: Foundation (19) ✅
    Phase 2: Core Steps (12) ✅
    Phase 3: CLI + FFI (6) ✅
    Phase 4: Studio UI (9) ✅
    Phase 5: GDD Parser (4) ✅
    Phase 6: CI/CD (3) ✅

ANALYZER: 0 errors, 0 warnings ✅
```

---

## Grand Total

| System | Tasks | Status |
|--------|-------|--------|
| Core Systems (P-SRC...P-SSS) | 129/129 | ✅ |
| P-FMC FluxMacro (6 phases) | 53/53 | ✅ |
| **GRAND TOTAL** | **182/182** | **✅** |

---

## UPCOMING — P-ICF: Intensity Crossfade Auto-Generator

**Status:** 🔲 PLANNED (0/8)
**Priority:** Enhancement — UX convenience over existing RTPC infrastructure
**Rationale:** ReelToReel ima `x-fade-levels` (parametarski crossfade između varijanti). FluxForge već ima RTPC + conditional activation što je superset, ali zahteva ručnu konfiguraciju svakog layera. Auto-generator eliminiše tu kompleksnost i čini RTPC intensity crossfade jednako lakim kao ReelToReel-ov x-fade-levels, ali sa punom RTPC moći (custom krive, multi-parametar, DSP per layer).

**Cilj:** Korisnik selektuje N audio varijanti → wizard auto-generiše:
- RTPC parametar (npr. `intensity`, `tension`, `win_level`)
- N layera sa automatski izračunatim RTPC range-ovima (overlapping za smooth crossfade)
- Crossfade krive per-layer (equal power default, customizable)
- Opcioni DSP chain per varijanta (filter sweep, pitch shift po intenzitetu)

### Tasks

```
P-ICF: Intensity Crossfade Auto-Generator (0/8)
  [ ] P-ICF-1: IntensityCrossfadeWizard UI widget — input: lista audio varijanti, output: RTPC config
  [ ] P-ICF-2: Auto RTPC range calculator — N varijanti → N overlapping rangeova sa configurable overlap %
  [ ] P-ICF-3: Auto SlotCompositeEvent layer generator — kreira N layera sa conditional activation po RTPC range
  [ ] P-ICF-4: Crossfade curve presets — equal power, linear, S-curve, custom — per-layer override
  [ ] P-ICF-5: Live preview — real-time slider za RTPC parametar sa vizuelnim prikazom koji layer je aktivan i sa kojim volumenom
  [ ] P-ICF-6: DSP auto-chain opcija — opcioni filter LP sweep (veći intenzitet = otvoreniji filter) i pitch offset per varijanta
  [ ] P-ICF-7: Template save/load — sačuvaj intensity crossfade konfiguraciju kao reusable preset
  [ ] P-ICF-8: Integration sa StageConfigurationService — auto-bind RTPC parametar na stage transitions (npr. win tier → intensity)
```

**Superiornost nad x-fade-levels:**
- x-fade-levels: 1 parametar, linear crossfade, samo volume
- P-ICF: bilo koji RTPC, bilo koja kriva, volume + filter + pitch + DSP chain
- Ista jednostavnost korišćenja (wizard), 10x više mogućnosti

---

## UPCOMING — P-RTE: Recursive Trigger Expansion

**Status:** 🔲 PLANNED (0/5)
**Priority:** Core — postEvent/trigger ActionType postoje u modelu ali nisu implementirani u EventRegistry
**Rationale:** ReelToReel ima `expandOnce()` — trigger koji sadrži TRIGGER behavior koji referencira drugi trigger, rekurzivno se razvija sa akumuliranim delay-ovima. FluxForge ima `ActionType.postEvent` i `ActionType.trigger` definisane ali EventRegistry ih ignoriše — mrtav kod. Ovo omogućava chain evente: npr. SPIN_START trigeruje BASE_MUSIC koji trigeruje AMBIENCE koji trigeruje UI_FEEDBACK, sve sa kaskadnim delay-ovima.

### Tasks

```
P-RTE: Recursive Trigger Expansion (0/5)
  [ ] P-RTE-1: postEvent handler u EventRegistry — kad layer ima ActionType.postEvent, dispatch-uj referencirani event
  [ ] P-RTE-2: Recursive expansion sa delay accumulation — child event inherit-uje parent delay + own delay
  [ ] P-RTE-3: Max depth limiter (default: 8) — prevencija infinite loop-ova (A→B→A)
  [ ] P-RTE-4: Cycle detection — maintain visited set, log warning + break na cycle
  [ ] P-RTE-5: UI za chain vizualizaciju — prikaz event chain-a kao tree/graph u middleware editoru
```

**Superiornost nad expandOnce():**
- expandOnce(): flat expansion, nema cycle detection, nema depth limit
- P-RTE: runtime dispatch (lazy, ne eager), cycle-safe, depth-limited, vizualni editor

---

## UPCOMING — P-CTR: Co-Timed Event Conflict Resolution

**Status:** 🔲 PLANNED (0/5)
**Priority:** Core — prevencija audio glitch-eva kod simultanih layer-a
**Rationale:** Kada EventRegistry dispatch-uje composite event sa više layera koji targetiraju isti bus/voice u istom trenutku, trenutno svi fire-uju simultano → potencijalni phase cancellation, click/pop, ili nepredvidiv redosled. ReelToReel rešava ovo sa `groupAndResolveConflicts()` — grupiše co-timed evente i dodaje micro-offset (50-100μs) za deterministički redosled po prioritetu.

### Tasks

```
P-CTR: Co-Timed Event Conflict Resolution (0/5)
  [ ] P-CTR-1: Conflict detector — identifikuj layere sa istim scheduled time + istim target bus/voice
  [ ] P-CTR-2: Priority-based ordering — STOP/CANCEL prvo, FADE drugo, PLAY poslednje (kao ReelToReel ali konfigurisano)
  [ ] P-CTR-3: Micro-offset injection — dodaj 50-100μs offset između conflicting layera za clean execution
  [ ] P-CTR-4: Configurable conflict strategy — strict (micro-offset), merge (combine into one), ignore (legacy behavior)
  [ ] P-CTR-5: Conflict log/warning UI — prikaži detektovane konflikte u middleware editoru sa suggested resolution
```

**Superiornost nad groupAndResolveConflicts():**
- ReelToReel: hardkodiran priority redosled, fixed micro-offset
- P-CTR: konfigurisana strategija (strict/merge/ignore), priority iz StageConfigurationService, visual conflict warning

---

## UPCOMING — P-PPL: Production Publish Pipeline

**Status:** 🔲 PLANNED (0/8)
**Priority:** Core — profesionalni publish workflow koji nijedan game audio tool nema kompletno
**Rationale:** ReelToReel ima basic publish (JSON manifest + git commit). Wwise ima SoundBank generate. FMOD ima bank build. Nijedan nema unified validate→build→version→manifest→integrity→tag flow sa multi-target podrškom. FluxForge već ima VersionControlService + ExportService + multi-target exportere (Unity/Unreal/FMOD/Howler/WASM/Godot) — ali su disjunktni. P-PPL ih spaja u one-click atomic publish operation.

**Flow:** One-click → Validate → Build → Version → Manifest → Integrity → Tag & Commit

### Tasks

```
P-PPL: Production Publish Pipeline (0/8)
  [ ] P-PPL-1: PublishPipelineService — orchestrator koji sekvencijalno izvršava sve korake, atomic rollback na fail
  [ ] P-PPL-2: Pre-publish validation gate — DRC certification pass, all events resolved, no missing/orphaned assets, bus routing complete
  [ ] P-PPL-3: Multi-target build step — paralelni build za selektovane targete (Unity/Unreal/FMOD/Howler/WASM/Godot), progress per-target
  [ ] P-PPL-4: Semantic versioning engine — auto-increment (major/minor/patch), version history, auto-changelog iz git diff-a od poslednjeg publish-a
  [ ] P-PPL-5: Production manifest generator — JSON/YAML manifest sa: svim eventima, RTPC definicijama, bus routing grafom, DSP chain-ovima, asset listom, target-specific metadata
  [ ] P-PPL-6: Integrity & signing — SHA256 hash svakog asset-a, manifest checksum, opcioni GPG potpis za supply chain security
  [ ] P-PPL-7: Git tag & commit — atomic git commit sa manifest + tag (v1.2.3), opcioni push to remote, publish metadata u commit message
  [ ] P-PPL-8: Publish UI — one-click button sa live pipeline progress, per-step status, error detail, rollback opcija, publish history log
```

**Superiornost nad ReelToReel publish:**
- ReelToReel: JSON manifest + media.jmm + git commit (3 koraka, 1 target)
- P-PPL: 6 koraka, multi-target, DRC validation, integrity signing, atomic rollback, semantic versioning
- Superiornost nad Wwise/FMOD: oni imaju bank build ali nemaju integrated VCS + DRC + multi-target u jednom flow-u

---

*Last Updated: 2026-03-04 — 182/182 core complete. P-ICF, P-RTE, P-CTR, P-PPL planned.*
