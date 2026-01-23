# SlotLab Lower Zone — Analiza i Reorganizacija

**Datum:** 2026-01-23
**Status:** Analiza kompletna, čeka mockup i implementaciju

---

## 1. TRENUTNO STANJE: 15 Tabova

```dart
enum _BottomPanelTab {
  timeline,        // 1
  busHierarchy,    // 2
  profiler,        // 3
  rtpc,            // 4
  resources,       // 5
  auxSends,        // 6
  eventLog,        // 7
  gameModel,       // 8
  scenarios,       // 9
  gddImport,       // 10
  commandBuilder,  // 11
  eventList,       // 12
  meters,          // 13
  autoSpatial,     // 14
  stageIngest,     // 15
}
```

**Problem:** 15 tabova je previše za efektivnu navigaciju. Korisnik gubi vreme tražeći pravi tab.

---

## 2. ANALIZA PO ULOGAMA (9 uloga iz CLAUDE.md)

### 2.1 🎮 Slot Game Designer
**Fokus:** Slot layout, math, GDD, feature flow

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| gameModel | ✅ DA | Grid config, symbol setup |
| scenarios | ✅ DA | Test scenarios (Big Win, Free Spins) |
| gddImport | ✅ DA | Import GDD za auto-setup |
| timeline | ⚠️ Ponekad | Pregled stage timinga |

### 2.2 🎵 Audio Designer / Composer
**Fokus:** Layering, states, events, mixing

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| timeline | ✅ DA | Event/layer placement |
| eventList | ✅ DA | Event CRUD, layer editing |
| meters | ✅ DA | Loudness, peak metering |
| busHierarchy | ✅ DA | Bus routing, volume/pan |
| auxSends | ✅ DA | Reverb/delay sends |
| rtpc | ⚠️ Ponekad | RTPC modulation setup |

### 2.3 🧠 Audio Middleware Architect
**Fokus:** Event model, state machines, runtime

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| eventList | ✅ DA | Event structure |
| rtpc | ✅ DA | Parameter bindings |
| busHierarchy | ✅ DA | Bus architecture |
| stageIngest | ✅ DA | Engine integration |
| autoSpatial | ⚠️ Ponekad | Spatial rules |

### 2.4 🛠 Engine / Runtime Developer
**Fokus:** FFI, playback, memory, latency

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| profiler | ✅ DA | DSP load, latency |
| resources | ✅ DA | Memory, voice pool |
| stageIngest | ✅ DA | FFI integration |
| eventLog | ✅ DA | Debug, trace |

### 2.5 🧩 Tooling / Editor Developer
**Fokus:** UI, workflows, batch processing

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| commandBuilder | ✅ DA | Auto-event prototyping |
| gddImport | ✅ DA | Import pipeline |
| stageIngest | ✅ DA | Adapter config |

### 2.6 🎨 UX / UI Designer
**Fokus:** Mental models, discoverability, friction

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| timeline | ✅ DA | Visual preview |
| gameModel | ✅ DA | Grid visualization |
| scenarios | ✅ DA | User flow testing |

### 2.7 🧪 QA / Determinism Engineer
**Fokus:** Reproducibility, validation, testing

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| eventLog | ✅ DA | Trace verification |
| scenarios | ✅ DA | Regression testing |
| profiler | ✅ DA | Performance validation |

### 2.8 🧬 DSP / Audio Processing Engineer
**Fokus:** Filters, dynamics, offline processing

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| profiler | ✅ DA | DSP load analysis |
| meters | ✅ DA | Audio quality |
| busHierarchy | ✅ DA | Processing chain |

### 2.9 🧭 Producer / Product Owner
**Fokus:** Roadmap, priorities, market fit

| Tab | Koristi? | Zašto |
|-----|----------|-------|
| timeline | ⚠️ Demo | Prikazivanje rezultata |
| scenarios | ⚠️ Demo | Showcase features |

---

## 3. MATRICA: Tab × Uloga

```
                      │ Game │ Audio │ Middleware │ Engine │ Tool │ UX │ QA │ DSP │ Prod │
                      │ Desg │ Desgn │ Architect  │  Dev   │ Dev  │    │    │ Eng │      │
──────────────────────┼──────┼───────┼────────────┼────────┼──────┼────┼────┼─────┼──────┤
timeline              │  ⚠️   │   ✅   │            │        │      │ ✅  │    │     │  ⚠️   │
busHierarchy          │      │   ✅   │     ✅      │        │      │    │    │  ✅  │      │
profiler              │      │       │            │   ✅    │      │    │ ✅  │  ✅  │      │
rtpc                  │      │   ⚠️   │     ✅      │        │      │    │    │     │      │
resources             │      │       │            │   ✅    │      │    │    │     │      │
auxSends              │      │   ✅   │            │        │      │    │    │     │      │
eventLog              │      │       │            │   ✅    │      │    │ ✅  │     │      │
gameModel             │  ✅   │       │            │        │      │ ✅  │    │     │      │
scenarios             │  ✅   │       │            │        │      │ ✅  │ ✅  │     │  ⚠️   │
gddImport             │  ✅   │       │            │        │  ✅   │    │    │     │      │
commandBuilder        │      │       │            │        │  ✅   │    │    │     │      │
eventList             │      │   ✅   │     ✅      │        │      │    │    │     │      │
meters                │      │   ✅   │            │        │      │    │    │  ✅  │      │
autoSpatial           │      │       │     ⚠️      │        │      │    │    │     │      │
stageIngest           │      │       │     ✅      │   ✅    │  ✅   │    │    │     │      │
```

**Legenda:** ✅ = Primarni korisnik | ⚠️ = Sekundarni/povremeni

---

## 4. ANALIZA: Šta Zadržati, Šta Spojiti, Šta Ukloniti

### 4.1 ✅ ZADRŽATI (Core tabs — koriste ih multiple uloge)

| Tab | Razlog |
|-----|--------|
| **Timeline** | Centralni workspace, 5+ uloga ga koristi |
| **Events** (eventList) | Audio dizajn, middleware — core workflow |
| **Event Log** | Debug, QA — esencijalan za troubleshooting |
| **Meters** | Audio kvalitet — quick reference |

### 4.2 🔗 SPOJITI (Redundantni tabovi → grupisati)

| Grupa | Tabovi | Nova kategorija |
|-------|--------|-----------------|
| **Mixing** | busHierarchy + auxSends | → "Mixer" ili u desni panel |
| **Game Setup** | gameModel + gddImport | → "Game Config" |
| **Engine Debug** | profiler + resources | → "Engine Stats" |
| **Integration** | stageIngest + commandBuilder | → "Integration" |

### 4.3 ⚠️ PREMESTITI (Ne pripada Lower Zone)

| Tab | Gde premestiti | Razlog |
|-----|----------------|--------|
| **autoSpatial** | Desni panel / Settings | Retko se koristi, config-style |
| **rtpc** | Desni panel uz Events | Direktno vezan za evente |
| **scenarios** | Toolbar / Play mode | Ne treba stalno vidljiv |
| **gameModel** | Desni panel | Setup, ne workflow |
| **gddImport** | Modal dialog | One-time import |

### 4.4 ❌ POTENCIJALNO UKLONITI

| Tab | Razlog |
|-----|--------|
| **commandBuilder** | Auto Event Builder — možda prebaciti u modal ili wizard |

---

## 5. PREDLOG: Nova Struktura Lower Zone

### 5.1 Opcija A: 6 Core Tabova (Minimalistički)

```
Lower Zone Tabs:
┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
│ Timeline │  Events  │  Mixer   │  Meters  │ Event Log│  Engine  │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
     │          │          │          │          │          │
     │          │          │          │          │          └── Profiler + Resources + Stage Ingest
     │          │          │          │          └── Live trace, debug
     │          │          │          └── LUFS, Peak, Correlation
     │          │          └── Bus Hierarchy + Aux Sends
     │          └── Event List + RTPC (merged)
     └── Audio regions, layers
```

**Pros:** Čisto, pregledano, lako za navigaciju
**Cons:** Skriva neke funkcije dublje

### 5.2 Opcija B: 8 Tabova sa Grupama (Balanced)

```
Lower Zone Tabs:
┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
│ Timeline │  Events  │  Mixer   │   ALE    │  Meters  │ Event Log│  Engine  │  Setup   │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
     │          │          │          │          │          │          │          │
     │          │          │          │          │          │          │          └── Game Model + GDD Import
     │          │          │          │          │          │          └── Profiler + Resources
     │          │          │          │          │          └── Live trace
     │          │          │          │          └── LUFS, Peak
     │          │          │          └── Music Layers Rules/Signals/Transitions
     │          │          └── Bus + Aux
     │          └── Event List + RTPC
     └── Audio regions
```

**Pros:** ALE ima svoj tab, Setup je logično grupisano
**Cons:** 8 tabova je još uvek dosta

### 5.3 Opcija C: Dinamički Tabovi po Kontekstu (Advanced)

```
Default Tabs:    [Timeline] [Events] [Mixer] [Meters] [Event Log]

Kad se klikne na MUSIC LAYERS sekciju u Symbol Strip:
                 [Timeline] [Events] [Mixer] [Meters] [Event Log] [ALE ▼]
                                                                    │
                                                              ALE Editor se otvori

Kad se klikne na GDD Import button:
                 [Timeline] [Events] [Mixer] [Meters] [Event Log] [GDD Import ▼]

Kad se poveže sa engine-om:
                 [Timeline] [Events] [Mixer] [Meters] [Event Log] [Stage Ingest ▼]
```

**Pros:** Context-aware, manje kognitivnog opterećenja
**Cons:** Kompleksnije za implementaciju

---

## 6. PREPORUKA: Opcija B sa Modifikacijama

### 6.1 Finalna Lower Zone Struktura

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ Lower Zone                                                                      │
├────────────────────────────────────────────────────────────────────────────────┤
│ [Timeline] [Events] [Mixer] [Music/ALE] [Meters] [Debug] [Engine] [+]          │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  (Tab content area)                                                            │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Tab Definicije

| # | Tab | Sadrži | Keyboard |
|---|-----|--------|----------|
| 1 | **Timeline** | Audio regions, waveforms, layer positioning | T |
| 2 | **Events** | Event list, RTPC bindings, stages | E |
| 3 | **Mixer** | Bus hierarchy, aux sends, volume/pan | M |
| 4 | **Music/ALE** | Music layers rules, signals, transitions | A |
| 5 | **Meters** | LUFS, peak, correlation, waveform | - |
| 6 | **Debug** | Event log, trace history, latency | L |
| 7 | **Engine** | Profiler, resources, stage ingest | - |
| 8 | **[+]** | Add tab menu: Game Config, AutoSpatial, Scenarios | - |

### 6.3 Tabovi Premešteni u Desni Panel

| Panel | Sadržaj |
|-------|---------|
| **Events Panel** (desno) | Event folders, selected event details |
| **Audio Browser** (desno, toggle) | File browser sa preview |
| **Properties** (desno, context) | Selected event/layer properties |

### 6.4 Tabovi Premešteni u Modalne Dijaloge

| Dijalog | Trigger |
|---------|---------|
| **GDD Import Wizard** | File → Import GDD |
| **Game Model Setup** | Settings → Game Config |
| **Scenarios** | Play → Test Scenarios |

---

## 7. UPOREDBA: Pre vs Posle

### 7.1 Trenutno (LOŠE)

```
15 tabova u Lower Zone:
Timeline | Bus Hierarchy | Profiler | RTPC | Resources | Aux Sends |
Event Log | Game Model | Scenarios | GDD Import | Command Builder |
Events | Meters | AutoSpatial | Stage Ingest

Problemi:
- Cognitive overload (15 choices)
- No clear grouping
- Mix of frequent and rare tasks
- Hard to find the right tab
```

### 7.2 Predloženo (DOBRO)

```
7 tabova u Lower Zone + [+] menu:
Timeline | Events | Mixer | Music/ALE | Meters | Debug | Engine | [+]

+ Plus menu:
  - Game Config (Game Model + GDD Import)
  - AutoSpatial
  - Scenarios

Prednosti:
- Clear purpose per tab
- Grouped by workflow
- Rare tasks in [+] menu
- 7 is "magic number" for human memory
```

---

## 8. DESNI PANEL STRUKTURA

```
┌─────────────────────────────┐
│ DESNI PANEL                 │
├─────────────────────────────┤
│ ▼ EVENTS FOLDER             │
│   📁 Spin Sounds            │
│   📁 Win Sounds             │
│   📁 Feature Sounds         │
│   📁 Music                  │
│   + Add Folder              │
├─────────────────────────────┤
│ ▼ SELECTED EVENT            │
│   Name: [Spin Start     ]   │
│   Stage: SPIN_START         │
│   Category: [Spin ▼]        │
│   ─────────────────         │
│   LAYERS:                   │
│   🔊 spin_whoosh.wav        │
│      Vol: [===|====] -3dB   │
│      Pan: [==|======] L20   │
│   + Add Layer               │
├─────────────────────────────┤
│ ▼ AUDIO BROWSER [Toggle]    │
│   📁 /Audio/Slot/Spins/     │
│   🔊 spin_01.wav            │
│   🔊 spin_02.wav            │
│   🔊 spin_turbo.wav         │
└─────────────────────────────┘
```

---

## 9. KOMPLETNI LAYOUT PREDLOG

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ HEADER: [Logo] Egyptian Riches        [▶ PLAY] [✏️ EDIT]        [⚙️] [?] [X]            │
├────────────────────────────────────────────────────────────────────────────────────────┬┤
│ STATE TABS: [🎰 Base] [⭐ Free Spins] [🔒 Hold&Win] [🎁 Bonus] [💎 Jackpot] [+]        ││
├──────────────┬─────────────────────────────────────────────────────────────────┬───────┤│
│              │                                                                 │       ││
│  SYMBOL      │                      SLOT PREVIEW                               │ EVENTS││
│  STRIP       │                                                                 │ PANEL ││
│              │   ┌─────────────────────────────────────────┐                   │       ││
│  🃏 WILD     │   │                                         │                   │ 📁 Spin││
│   ├─ Land    │   │    ┌───┬───┬───┬───┬───┐               │                   │ 📁 Win ││
│   ├─ Win     │   │    │ A │ 👑│ 💎│ ⭐│ K │               │                   │ 📁 Feat││
│   └─ Expand  │   │    ├───┼───┼───┼───┼───┤               │                   │       ││
│              │   │    │ 🃏│ A │ K │ 👑│ 💎│               │                   │ ──────││
│  ⭐ SCATTER  │   │    ├───┼───┼───┼───┼───┤               │                   │ SEL:  ││
│   ├─ 1x      │   │    │ K │ ⭐│ 🃏│ A │ 👑│               │                   │ Spin  ││
│   ├─ 2x      │   │    └───┴───┴───┴───┴───┘               │                   │ Start ││
│   └─ Trigger │   │                                         │                   │       ││
│              │   │       [ SPIN ]    $1,234.56             │                   │ LAYERS││
│  ────────────│   │                                         │                   │ 🔊wav ││
│              │   └─────────────────────────────────────────┘                   │       ││
│  🎵 MUSIC    │                                                                 │       ││
│   ├─ BASE    │   TRANSITIONS: [Base→FS] [FS→Base] [Base→H&W] ...              │ AUDIO ││
│   │  L1-L5   │                                                                 │ BROWSR││
│   ├─ FS      │                                                                 │ [📁]  ││
│   │  L1-L5   │                                                                 │       ││
│   └─ BIG WIN │                                                                 │       ││
│      L1-L5   │                                                                 │       ││
│              │                                                                 │       ││
├──────────────┴─────────────────────────────────────────────────────────────────┴───────┤│
│ LOWER ZONE                                                                             ││
├────────────────────────────────────────────────────────────────────────────────────────┤│
│ [Timeline] [Events] [Mixer] [Music/ALE] [Meters] [Debug] [Engine] [+]                  ││
├────────────────────────────────────────────────────────────────────────────────────────┤│
│                                                                                        ││
│  TIMELINE (or selected tab content)                                                    ││
│  ┌────────────────────────────────────────────────────────────────────────────────┐   ││
│  │ SPIN_START    [████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]  │   ││
│  │ REEL_STOP_0   [░░░░░░████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]  │   ││
│  │ REEL_STOP_1   [░░░░░░░░░░████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]  │   ││
│  │ WIN_PRESENT   [░░░░░░░░░░░░░░░░░░████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]  │   ││
│  └────────────────────────────────────────────────────────────────────────────────┘   ││
│                                                                                        ││
└────────────────────────────────────────────────────────────────────────────────────────┴┘
```

---

## 10. NEXT STEPS

1. ✅ Analiza kompletna (ovaj dokument)
2. ⏳ Kreirati V6 mockup sa novim layoutom
3. ⏳ Ažurirati SLOTLAB_STAGE_MAP_VISION.md
4. ⏳ Implementirati tab reorganizaciju

---

## 11. OVERFLOW FIXES (2026-01-23) ✅

### Problem
Visual overflow/empty space ispod tabova u collapsed state.

### Rešenje
| Fajl | Promena |
|------|---------|
| `lower_zone_types.dart` | Dodato `kContextBarCollapsedHeight = 32.0` |
| `lower_zone_context_bar.dart` | Dinamička visina: 32px collapsed, 60px expanded |
| `slotlab_lower_zone_controller.dart` | Popravljen `totalHeight` za collapsed state |
| `slotlab_lower_zone_widget.dart` | Uklonjeno `mainAxisSize.min` iz Column-a |

### Verifikacija
`flutter analyze` → 0 errors

### Middleware Lower Zone (isti pattern)

Isti problem (1px overflow) rešen u `middleware_lower_zone_controller.dart` i `middleware_lower_zone_widget.dart`:
- Dodato `kSlotContextBarHeight = 28.0` konstanta
- Popravljen `totalHeight` da uključuje sve komponente
- Dodato `clipBehavior: Clip.hardEdge`

---

*Dokument kreiran: 2026-01-23*
*Ažurirano: 2026-01-23 — Overflow fixes (SlotLab + Middleware)*
*Verzija: 1.2*
