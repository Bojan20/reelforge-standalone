# FluxForge Studio — MASTER TODO (definitive)

> Ažurirano: 2026-04-25 · Grana: `fix/ci-infra`
> Sinhronizovano sa `FLUX_MASTER_VISION_2026.md` (1,689 linija, 18,057 reči).

---

## IMPERATIVI (uvek, bez izuzetka)

1. **Kompaktnost i brzina su imperativ** — svaki novi widget / panel / flow mora biti jasniji i brži od prethodnog. Bez "samo još jedan tab".
2. **Kvalitet se podrazumeva** — 0 flutter analyze errors, cargo clippy clean, 60fps pod 50+ voice load, zero audio dropout, uvek testovi.
3. **CORTEX OČI / RUKE zakon** — uvek CortexEye/CortexHands, nikad macOS screenshot, nikad Boki klikće.
   - `GET  /eye/snap`, `GET /eye/logs`, `GET /eye/inspect`
   - `POST /hands/tap`, `POST /hands/input`, `POST /hands/swipe`
   - Redosled: impl → CortexEye snap → CortexHands verify → tek onda izveštaj.

---

## FAZA 0 — Nekomitovano / nedovršeno (trenutno)

| # | Zadatak | Fajl(ovi) | Status |
|---|---|---|---|
| 0.1 | CortexEye snap MIX tab sa double-tap verifikacija VoiceDetailEditor | — | ⏳ BuildContext zavisno, CortexHands verify |
| 0.2 | CortexEye snap MIX tab sa long-press verifikacija Radial Action Menu | — | ⏳ BuildContext zavisno, CortexHands verify |
| 0.3 | Posle verifikacije 0.1/0.2 → ako padne, fix; ako radi, commitovano je `830d9cb1` | — | ⏳ |
| 0.4 | CortexEye E2E visual regression baseline | `tools/cortex_e2e/baseline.py` | ✅ a56cf5db — record/verify/list/clean, 6 screens, phash+dhash |

---

## FAZA 1 — P0 BLOKIRAJUĆE (pre v1 release)

> Ne puštamo javno dok ovo ne zatvorimo.

### 1.1 FFI sigurnost (Rust)

| # | Problem | Lokacija | Effort | Status |
|---|---|---|---|---|
| 1.1.1 | ~~8× `CStr::from_ptr` bez null check — crash sa Dart strane~~ | ~~rf-bridge `slot_lab_ffi/container_ffi/slot_lab_export`, rf-engine `render_selection_to_new_clip`, rf-plugin `vst3.rs` ObjC callbacks, rf-plugin-host `scan_callback`~~ | 30 min | ✅ ce2a90a9 + 604ce478 |
| 1.1.2 | BUG #63 scenario validation — dimenzije outcome-a nisu provereno sa aktivnim GameModel | `crates/rf-bridge/src/slot_lab_ffi.rs:1635-1640` | 1 h | ⏳ |
| 1.1.3 | ~~BUG #32 LV2 Mutex poison~~ | ~~`crates/rf-plugin/src/lv2.rs` URID_MAP → parking_lot::Mutex~~ | 30 min | ✅ 604ce478 |
| 1.1.4 | TOCTOU u voice_id array iteration | `crates/rf-bridge/src/dpm_ffi.rs:94-100` | 1 h | ⏳ |
| 1.1.5 | Audit svih 47 `unsafe` blokova u rf-engine + 23 u rf-bridge | — | 2 h | ⏳ |

### 1.2 Event flow (Flutter)

| # | Problem | Lokacija |
|---|---|---|
| 1.2.1 | **Event Registry race** — dva paralelna sistema registracije (`EventRegistry` + `CompositeEventSystemProvider`) — silent audio dropout. CLAUDE.md warning line 40. | `lib/services/event_registry.dart` + `lib/providers/subsystems/composite_event_system_provider.dart` — konsolidovati na JEDAN path kroz `_syncEventToRegistry()` |
| 1.2.2 | Metering lock contention — `lufs_meter.try_write()` / `true_peak_meter.try_write()` silent skip tokom UI interakcije → metering gaps | `crates/rf-engine/src/playback.rs:7322-7335` — decouple metering od audio thread, separate readers |
| 1.2.3 | Cache TOCTOU — check→evict bez atomic CAS | `crates/rf-engine/src/playback.rs:1044-1055` — dedicated RwLock u background eviction thread |

### 1.3 Test pokrivenost UI

| # | Zadatak | Cilj |
|---|---|---|
| 1.3.1 | Widget tests za `engine_connected_layout.dart` (17,292 LOC) | min 30 integration interactions |
| 1.3.2 | Widget tests za `slot_lab_screen.dart` (15,215 LOC) | min 30 |
| 1.3.3 | Widget tests za `helix_screen.dart` (9,735 LOC) | min 30 |
| 1.3.4 | Gesture conflict detection test (820 GestureDetector instances — automatska detekcija arena collision-a) | pass under stress |
| 1.3.5 | Memory leak profiling (30+ min sessions, Ticker/OverlayEntry/Provider disposal) | zero leak |
| 1.3.6 | 60fps perf test pod 50+ channel load | frame drops < 1% |

### 1.4 HELIX stub tabovi (popuniti ili otkloniti)

| # | Super-tab / Sub-tab | Trenutno | Odluka |
|---|---|---|---|
| 1.4.1 | DSP → spatial | "Coming soon" placeholder | Popuniti sa HRTF + Atmos monitoring + HOA 3 controls |
| 1.4.2 | RTPC → sve 4 sub-tabs (curves, macros, dspBinding, debugger) | UI bez FFI binding | Wire real-time parametar curves kroz `rf-bridge/src/rtpc_ffi.rs` |
| 1.4.3 | CONTAINERS → metrics, timeline | UI-only | Rust backend za container synthesis |
| 1.4.4 | MUSIC → segments, stingers, transitions | Skeletal | Interactive music logic (layered, Wwise-style) |
| 1.4.5 | LOGIC → triggers, gate, emotion | Placeholderi | Behavior tree UI + rule editor |
| 1.4.6 | DAW CORTEX → awareness (7-dim) | Enum deklarisan, nema UI | Brisati ili implementirati |
| 1.4.7 | MONITOR → neuro, aiCopilot | AI stubs | Wire sa Faza 4 AI Copilot |

### 1.5 Audio kvalitet

| # | Zadatak | Lokacija | Effort |
|---|---|---|---|
| 1.5.1 | HRTF bilinear interpolation upgrade (BUG #35 trenutno IDW) | `crates/rf-dsp/src/spatial.rs:118-120` | 2 h |
| 1.5.2 | Plugin crash sandbox — VST3/AU/CLAP/LV2 izolovan u subprocess | `crates/rf-engine/src/plugin/` | 4 h |
| 1.5.3 | True Peak NEON implementacija (trenutno samo AVX2) | `crates/rf-dsp/src/metering_simd.rs` | 2 h |
| 1.5.4 | DSD polyphase resampling (TODO u `dsd/mod.rs:197`) | | 1 dan |

### 1.6 Build / CI

| # | Zadatak | Cilj |
|---|---|---|
| 1.6.1 | `cargo build --release --all` — 0 warnings | clean |
| 1.6.2 | `xcodebuild ... -configuration Release build` | success |
| 1.6.3 | `flutter analyze` — 0 errors | clean |
| 1.6.4 | `cargo test --workspace` — sve pass | 1873+ tests green |
| 1.6.5 | Full Build CI checkpoint (GitHub Action) | green badge |

---

## FAZA 2 — UX / Performance (kompaktnost + brzina imperativi)

### 2.1 Kompaktnost

| # | Zadatak | Zašto |
|---|---|---|
| 2.1.1 | HELIX dock jump-to: Cmd+K palette za skok na bilo koji od 110+ sub-tab statesa | sada 2-3 klika za sub-tab |
| 2.1.2 | SlotVoiceMixer — collapse-by-bus button (6 buseva, svaki collapsible) | 100+ channels trenutno linear scroll |
| 2.1.3 | Engine_connected_layout — 3-panel raspored collapsible (left/right toggle tabovi) | trenutno 3 monitora potrebna |
| 2.1.4 | Keyboard shortcut map overlay (`?` ili `Cmd+/`) | discoverability |
| 2.1.5 | Sub-tab nav shortcuts (1-0 + Q-U) | missing |
| 2.1.6 | Status bar height smanjiti na 22px (trenutno 28px) | više prostora za rad |
| 2.1.7 | HELIX Omnibar inline edit-in-place everywhere (project name, BPM, RTP, tier thresholds) | manje klikova |
| 2.1.8 | Slot preview: toggle fullscreen / 80% / 50% size (Escape cycles) | instant fokus |

### 2.2 Brzina

| # | Zadatak | Cilj |
|---|---|---|
| 2.2.1 | 60fps pod 130-voice live mix | Phase 10 orchestra fazom 10e-2 |
| 2.2.2 | OrbMixer Phase 10e-2 — 5s master ring buffer + WAV export | Problems Inbox replay <200ms |
| 2.2.3 | OrbMixer per-bus FFT isolate za ghost buffer >100 voices | zero frame drop |
| 2.2.4 | Lazy loading za 11 super-tabs × sub-tabs (memo + IndexedStack sa keepAlive=false za neaktivne) | <50ms tab switch |
| 2.2.5 | Waveform cache LRU invalidation (trenutno oversized images BUG #46) | stale waveforms |
| 2.2.6 | Timeline virtualization — samo visible clips render | 10000+ clips project |
| 2.2.7 | Impeller GPU compositing enable za macOS (Flutter 3.30+) | smoother scroll/pan |

### 2.3 Monolith refactor (održivost)

| # | Zadatak | Pre | Cilj |
|---|---|---|---|
| 2.3.1 | Split `engine_connected_layout.dart` | 17,292 LOC | 3 panela × ~2000 LOC |
| 2.3.2 | Split `slot_lab_screen.dart` | 15,215 LOC | Timeline + LowerZone + Overlay sekcije |
| 2.3.3 | Split `premium_slot_preview.dart` | 7,676 LOC | ReelStrip + SymbolOverlay + WinLine + AnticipationGlow painters |
| 2.3.4 | Split `helix_screen.dart` | 9,735 LOC | Omnibar + NeuralCanvas + Dock widgets |
| 2.3.5 | Extract lower zone sub-tab widgets u `widgets/lower_zone/slotlab/` | — | reuse |

### 2.4 Dead code eliminacija

| # | Zadatak | Lokacija |
|---|---|---|
| 2.4.1 | `ValidationErrorCategory.deprecated` ukloniti | `lib/models/validation_error.dart:67` |
| 2.4.2 | `_deprecated_slot_events` v4→v5 migration (posle >6 meseci na v5) | `lib/services/project_migrator.dart:594-604` |
| 2.4.3 | 3 obsolete DAW sub-tabs (video, cyc, ...) | placeholderi 20+ |
| 2.4.4 | `gdd_import_*` legacy format ~800 LOC | ako niko ne importuje GDD više |
| 2.4.5 | Old behavior tree format pre-v11 ~400 LOC | `providers/slot_lab/behavior_tree*` |

---

## FAZA 2B — DAW + HELIX Ultimativna Kompaktnost (Detaljan Plan)

> **Izvor:** Duboki audit 2026-04-25 — engine_connected_layout.dart (17,292 LOC), helix_screen.dart (9,735 LOC), lower_zone_types.dart (1,797 LOC), global_shortcuts_provider.dart (57 shortcuts).
> **Imperativ:** Boki ne sme da traži nešto i ne nađe u < 2 klika / 1 keyboard shortcut. Svaki element mora biti jasan bez labele. Zero confusion.

---

### 2B.1 DAW — Kompaktnost i navigacija

#### Problem #1: EDIT tab ima 31 sub-tabova (jedini super-tab, sve utrpano)
- **Rešenje:** Reorganizovati 31 → 3 grupe sa collapse-expand:
  - **TIMELINE** (6): timeline, pianoRoll, fades, warp, elastic, razorEdit
  - **CLIP** (8): comping, beatDetect, tempoDetect, stripSilence, dynamicSplit, loopEditor, granularSynth, crossfades
  - **ADVANCED** (17): sve ostalo (grid, punch, ucsProjNaming, video, cycleActions, regionPlaylist, ...)
- **Fajl:** `lib/widgets/lower_zone/lower_zone_types.dart:286`, `engine_connected_layout.dart` tab renderers
- **Effort:** 3 h

#### Problem #2: Cmd+K Command Palette postoji za HELIX ali ne za ceo DAW
- **Rešenje:** Globalni `FluxCommandPalette` widget — fuzzy search po svim panelima, sub-tabovima, akcijama, projektima, stage-ovima
  - Trigger: `Cmd+K` ili `/` u focus-modeu
  - Sources: sve 57 global shortcuts + sve sub-tab nazive + sve FFI komande
  - UI: 500×400 glassmorphism popup, real-time filter, arrow navigate, Enter izvršava
- **Fajl:** novi `lib/widgets/command_palette/flux_command_palette.dart` + wire u `main_layout.dart`
- **Effort:** 1 nedelja

#### Problem #3: Left Panel nema jasnu hijerarhiju (Audio Pool + Tracks + MixConsole — nevidljivo koji je aktivan)
- **Rešenje:** Left Panel tabs kao icon+label strip na vrhu (Audio Pool 🎵 / Tracks 📋 / MixConsole 🎛), active tab highlight gold, collapsed state = 40px ikonica kolona
- **Fajl:** `engine_connected_layout.dart:273` `_leftVisible` zone
- **Effort:** 2 h

#### Problem #4: Toolbar je statičan — ne adaptira se na selekciju
- **Rešenje:** Adaptive Toolbar — menja kontekstualne dugmadi prema selekciji:
  - Ništa selektovano → standard (Play/Stop/Record/Undo/Redo)
  - Audio clip selektovan → + Fade/Warp/Normalize/Pitch/Reverse
  - MIDI selektovan → + Quantize/Velocity/CC/PianoRoll
  - Marker selektovan → + Tempo Change/Time Sig/Color
  - Track header → + Arm/Solo/Mute/Color/Rename
- **Fajl:** `engine_connected_layout.dart` toolbar zone
- **Effort:** 3 h

#### Problem #5: Right Panel je uvek Inspector — ne zna kontekst
- **Rešenje:** Smart Contextual Right Panel:
  - Klik track → Track properties (name, color, routing, pre-gain)
  - Klik clip → Clip properties (start/end, gain, pitch, fade lengths, warp markers)
  - Klik marker → Tempo/TimeSig editor
  - Klik plugin insert → Plugin micro-editor (8 most-used params, expand to full)
  - Ništa → Project overview (total tracks, BPM, key, duration)
- **Fajl:** `engine_connected_layout.dart:274` right panel + novi `lib/widgets/inspector/contextual_inspector.dart`
- **Effort:** 1 nedelja

#### Problem #6: Lower Zone CORTEX tab — prazan ili nedovršen
- **Rešenje:** Ili (A) popuniti sa Cortex health dashboard (vitalni znaci, neural signals, reflex actions feed) ili (B) skloniti iz production build (sakriti u `kDebugMode`)
- **Fajl:** `lib/widgets/lower_zone/` CORTEX tab renderer
- **Effort:** 30 min (skip) ili 1 nedelja (implement)

#### Problem #7: Nema Layout Presets (1-monitor, 2-monitor, ultrawide)
- **Rešenje:** Layout Preset system — `Cmd+Shift+1/2/3`:
  - **1-monitor (1440px)**: Left panel 0px (hidden), Center 75%, Right 0%, Lower 35% height
  - **2-monitor primary**: Left 250px, Center max, Right 300px, Lower 30%
  - **Ultrawide (3440px+)**: Left 300px, Center 60%, Right 400px, Lower 300px
  - **Focus mode**: samo Center + mini toolbar (already in 2.1.8 / helix F mode)
- **Fajl:** `lib/providers/layout_provider.dart` (novo ili extend DawLowerZoneController)
- **Effort:** 4 h

#### Problem #8: Mini MixConsole popup — nedostaje
- **Rešenje:** Floating mini mixer (≤ 300×200px, glassmorphism) — trigger: `Cmd+M` ili toolbar ikona
  - Prikazuje aktivan kanal (selektovan track) sa: volume fader, pan, 3 insert slot-a, mute/solo
  - Uvek on-top, Escape da zatvori
- **Fajl:** novi `lib/widgets/mixer/mini_mix_popup.dart`
- **Effort:** 4 h

---

### 2B.2 HELIX — Kompaktnost i navigacija

#### Problem #1: Spine ikone bez labela (5 ikona, nema teksta — konfuzno novim korisnicima)
- **Rešenje:** Spine layout u 2 varijante toggle-om:
  - **Compact** (48px): samo ikone sa 150ms hover tooltip
  - **Expanded** (96px): ikona + 2-word label ispod (AUDIO ASSIGN, GAME CONFIG, AI INTEL, SETTINGS, ANALYTICS)
  - Persist setting u `DawLowerZoneController` / local prefs
- **Fajl:** `helix_screen.dart:835-863`
- **Effort:** 2 h

#### Problem #2: 6 od 12 Command Dock super-tabova su STUBS (SFX, BT, DNA, AI, CLOUD, A/B)
- **Rešenje:** Stub tabovi dobijaju: (A) "⚡ Coming Soon" badge sa estimated ETA, (B) ili budu sakriven iza `kDebugMode` dok nisu gotovi
  - Nikad prazna stranica — uvek nešto vidljivo (progress, teaser, placeholder sa opšim opisom)
- **Fajl:** `helix_screen.dart:2034, 2500, 2838, 3188, 3852, 4114`
- **Effort:** 2 h

#### Problem #3: MONITOR super-tab ima 20 sub-tabova (previše, nema hijerarhije)
- **Rešenje:** Reorganizovati 20 → 5 collapsible kategorija:
  - **LIVE** (4): timeline, energy, voice, spectral
  - **AI** (3): fatigue, neuro, aiCopilot
  - **MATH** (3): mathBridge, rgai, abTest
  - **DEBUG** (4): debug, profiler, profilerAdv, evtDebug
  - **EXPORT** (6): export, ucpExport, fingerprint, spatial, resource, voiceStats
- **Fajl:** `lib/widgets/lower_zone/lower_zone_types.dart:726` + MONITOR tab renderer
- **Effort:** 3 h

#### Problem #4: Command Dock nema Quick Actions Strip
- **Rešenje:** 10px strip iznad tab bar-a sa contextual action buttons (ne zauzima tab space):
  - FLOW tab aktivan → [+ Stage] [+ Transition] [Run Sim] [Export Flow]
  - AUDIO tab → [Snap to Grid] [Solo Bus] [Reset Gain] [Export Mix]
  - MATH tab → [Recalculate RTP] [Lock Math] [Export Blueprint]
  - EXPORT tab → [Quick Package] [Git Commit] [Validate All]
- **Fajl:** `helix_screen.dart:1198-1303` Command Dock
- **Effort:** 4 h

#### Problem #5: Nema Floating Math HUD na Neural Canvas
- **Rešenje:** Kompaktni HUD overlay (gore-desno Neural Canvas-a, semi-transparent):
  - 4 live metrics: `RTP: 96.2% ▲` `VOL: 6.8` `HIT: 1:4.2` `MAX: 2847×`
  - Collapsible sa jednim klikom (→ samo 4 ikone ostaju)
  - Boja se menja: zelena (u target range) / žuta (warn) / crvena (out of range)
- **Fajl:** `helix_screen.dart:869-1014` NeuralCanvas zone + novi `lib/widgets/helix/math_hud_overlay.dart`
- **Effort:** 3 h

#### Problem #6: Reel Context Lens nije dovoljno vidljiv (ne znaš da klikneš)
- **Rešenje:** Affordance poboljšanje:
  - Reel cell hover → 2px gold border + magnifier ikonica (16×16) u uglu
  - Tap → Lens se otvori sa: stage bind info, volume slider, pitch offset, audio waveform preview
  - Long press na lens → Expand u full Voice Editor
- **Fajl:** `helix_screen.dart:1003-1008` + `premium_slot_preview.dart` reel cell
- **Effort:** 4 h

#### Problem #7: HELIX Mini Mode ne postoji (za dual-monitor setup)
- **Rešenje:** `Cmd+Shift+M` → HELIX kolapsira u 200px visoki strip:
  - Strip: Spin button | Stage name | Live RTP | 6 bus meters | Orb mini | Compliance lights
  - Ostatak monitora slobodan za druge alate
  - `Cmd+Shift+M` opet → vraća full view
- **Fajl:** `helix_screen.dart` mode state machine (lines 96, 225-227) — dodati MINI mode = 3
- **Effort:** 1 nedelja

#### Problem #8: Quick Assign Hotbar nedostaje
- **Rešenje:** 5-slot drag target bar iznad NeuralCanvas-a (sakriven dok ASSIGN mode nije aktivan):
  - Drag zvuk direktno na hotbar slot (svaki slot = jedan stage)
  - Highlight-uje staged audio od prvog dropa
  - Pins: stalni shortcut target da ne moraš skrolati event listu
- **Fajl:** `helix_screen.dart` iznad Neural Canvas + `slot_lab_screen.dart` ASSIGN mode
- **Effort:** 3 h

#### Problem #9: Stage Trigger keyboard shortcuts ne postoje u HELIX
- **Rešenje:** Dok je FLOW tab aktivan:
  - `1-8` → triggeruje stage #1-8 direktno (IDLE, BASE_SPIN, STOP, WIN, CASCADE, FREE_SPINS, BONUS, JACKPOT)
  - `Space` → Spin (već postoji u DAW, treba HELIX ekvivalent)
  - `Shift+1-8` → Force-exit feature → dati stage
- **Fajl:** `helix_screen.dart:580-600` keyboard zone
- **Effort:** 2 h

---

### 2B.3 Cross-cutting — Konzistentnost DAW ↔ HELIX

| # | Problem | Rešenje | Effort |
|---|---|---|---|
| 2B.3.1 | **Panel Focus indikator** — ne znaš koji panel prima keyboard evente | Aktivni panel dobija 1px gold border; focus chain: Tab prebacuje fokus između panela | 2 h |
| 2B.3.2 | **Smart Panel Memory** — layout se ne pamti po projektu | `PanelLayoutProvider` pamti active tab/sub-tab + panel visibility per `projectId` u SQLite | 4 h |
| 2B.3.3 | **Layout Snapshots** (`Cmd+Opt+1..9`) | Photoshop Layer Comps za panele — sačuvaj i vrati kompletan panel state jednim tasterom | 1 nedelja |
| 2B.3.4 | **Hover tooltips** uniformni — 150ms delay, kompaktni, sa shortcut hintom | Sve ikone, sve dugmadi, svi slajderi. Format: `"Solo Bus (Cmd+S)"` | 3 h |
| 2B.3.5 | **Keyboard nav između panela** — Tab/Shift+Tab | Tab = sledeći panel fokus, Arrow keys = unutar panela, Enter = primary action | 3 h |
| 2B.3.6 | **Isti Cmd+K u DAW i HELIX** | Jedan globalni `FluxCommandPalette` (2B.1.2) dostupan svuda | 0 h (zavisi od 2B.1.2) |
| 2B.3.7 | **Context menu "Explain this"** — Right-click na bilo koji param | Copilot tooltip: šta je ovaj param, tipične vrednosti, upozorenja. Onboarding bez tutorijala. | 1 nedelja (zavisi od Faza 4) |
| 2B.3.8 | **Selection Memory** (`Cmd+1..9`) | Sačuvaj trenutni view (tab, zoom, selekcija) na slot, vrati jednim tasterom — kao Cmd+1..9 u Photoshop | 4 h |

---

### 2B.4 Merljivi ciljevi (Definition of Done)

| Metrika | Sada | Cilj |
|---------|------|------|
| Klika do EQ na specifičnom stage | 3 klika | 1 (Cmd+K "open EQ stage X") |
| Klika do promene reel count-a | 4 klika | 1 (Omnibar inline edit) |
| Klika do preview zvuka | 2 klika | 1 (Space na selektovanom) |
| Vidljive info simultano (1440px) | 4 zone | 4 zone + HUD float |
| Sub-tab switchovanje | 2-3 klika | 1 keyboard key (1-9) |
| Otvoren panel bez etikete | Spine (5 ikona) | Sve ikone imaju tooltip ≤ 150ms |
| Stub tabovi sa praznom stranicom | 6 u HELIX | 0 (badge ili sakriti) |
| Layout reset posle pomrnje šta je otvoreno | Ručno | Cmd+0 = default layout |

---

## SESIJA: DAW + HELIX Kompaktnost — Puni Implementacioni Specs

> Svaki problem razrađen do nivoa: fajl:linija → šta se menja → kod pattern → before/after ponašanje → test.
> Ovo je radna sesija — krene se redom, svakim problemom završimo pre sledećeg.

---

### SPEC-01 · Globalni `FluxCommandPalette` (Cmd+K)

**Problem:** Nema fuzzy-search za 110+ sub-tabova, 57 shortcuts, projekata. Svaki detalj = 2-4 klika.

**Root cause:** Nema `CommandRegistry` servisa ni palette widgeta. `global_shortcuts_provider.dart` ima shortcuts ali nema unified UI za search.

**Implementacija:**

```
lib/services/command_registry.dart          ← novi singleton
lib/widgets/command_palette/
    flux_command_palette.dart               ← OverlayEntry widget
    command_item.dart                       ← single result row
lib/screens/main_layout.dart               ← wire trigger Cmd+K
```

**`CommandRegistry`** — 5 izvora, sve lazily registrovano:
- `ShortcutSource` → 57 shortcuts iz `GlobalShortcutsProvider` + label + icon
- `HelixTabSource` → sve 110+ HELIX sub-tabovi (super-tab + sub-tab naziv + keyboard key)
- `DAWPanelSource` → svi DAW paneli (left/center/right/lower + sub-tabs)
- `RecentSource` → poslednjih 10 akcija (SQLite persist, session-bound)
- `ActionSource` → dynamic per-context (dodaju ga active provideri)

**`FluxCommandPalette` widget:**
- Trigger: `LogicalKeyboardKey.keyK` + meta, ili `/` kada nema text fokusa
- `OverlayEntry` na `Navigator.overlay` — uvek iznad svega
- Dimenzije: 560×420px, centrisano, glassmorphism `#0D0D12/85%` + gold border 1px
- Enter animacija: `Spring(stiffness: 380, damping: 28)` — 180ms
- Search: real-time Levenshtein + prefix boost + recent boost
- Max 8 rezultata vidljivo, scroll za više
- Row: 36px — `icon (20px) + title (bold) + subtitle (muted) + shortcut badge (right)`
- `ArrowUp/Down` = navigate, `Enter` = execute, `Esc` = dismiss
- Fajl: `main_layout.dart` → `Shortcuts` widget wraps ceo child tree

**Before/After:**
- Pre: HELIX → klik AUDIO super-tab → klik MIX sub-tab → klik DSP chain → klik EQ = 4 klika
- Posle: `Cmd+K` → kucaj "eq" → Enter = 0.5s

**Test:** `flutter_test` — palette se otvori, query "rtp", expected result "MATH → RTP Target", Enter navigira na MATH tab

---

### SPEC-02 · EDIT Tab Reorganizacija (31 → 3 grupe)

**Problem:** DAW Lower Zone EDIT super-tab ima 31 sub-tabova u jednom linearnom scrollable redu — vizuelni chaos, korisnik ne zna šta se gde nalazi.

**Root cause:** `lower_zone_types.dart:286` — `DawEditSubTab` enum sa 31 vrednosti, renderer ih crta redom bez hijerarhije.

**Implementacija:**

```
lib/widgets/lower_zone/lower_zone_types.dart    ← dodati DawEditGroup enum
lib/widgets/lower_zone/daw_lower_zone_widget.dart   ← render grupovano
```

**Nova 3-grupna struktura** (umesto flat liste):
```
TIMELINE  ▼  (expandable, default open)
  timeline · pianoRoll · fades · warp · elastic · razorEdit

CLIP  ▼  (expandable)
  comping · beatDetect · tempoDetect · stripSilence
  dynamicSplit · loopEditor · granularSynth

ADVANCED  ▶  (expandable, default collapsed)
  grid · punch · ucsNaming · video · cycleActions
  regionPlaylist · mixSnapshots · metadataBrowser
  screensets · projectTabs · subProjects · [ostalo]
```

**Group header widget:** 28px visok, `▶/▼` ikona + label (12px uppercase), klik = toggle, persist state u `DawLowerZoneController`

**Before/After:**
- Pre: linearni scroll kroz 31 item-a, gubiš se
- Posle: 3 jasne kategorije, default vidljivo 6 najvažnijih

**Test:** `DawEditGroup.timeline` expand/collapse toggle + persist kroz hot-reload

---

### SPEC-03 · Smart Contextual Right Panel (Inspector++)

**Problem:** Right panel uvek prikazuje isti Inspector bez obzira šta je selektovano. Klik na audio clip = isti view kao klik na marker.

**Root cause:** `engine_connected_layout.dart:274` — `_rightVisible` flag + statičan `InspectorPanel` widget, nema context switching.

**Implementacija:**

```
lib/widgets/inspector/
    contextual_inspector.dart               ← novi wrapper
    track_inspector.dart                    ← track properties
    clip_audio_inspector.dart               ← audio clip
    clip_midi_inspector.dart                ← MIDI clip
    marker_inspector.dart                   ← tempo/timesig marker
    plugin_quick_inspector.dart             ← plugin 8-param micro view
    project_overview_inspector.dart         ← ništa selektovano
```

**`ContextualInspector`** — sluša `SelectionProvider` i ruta na odgovarajući widget:
```dart
switch (selection.type) {
  case SelectionType.track    → TrackInspector(track: selection.track)
  case SelectionType.audioClip → ClipAudioInspector(clip: selection.clip)
  case SelectionType.midiClip  → ClipMidiInspector(clip: selection.clip)
  case SelectionType.marker    → MarkerInspector(marker: selection.marker)
  case SelectionType.plugin    → PluginQuickInspector(plugin: selection.plugin)
  default                      → ProjectOverviewInspector()
}
```

**`TrackInspector`** (kompaktan, 6 rows):
- Name (inline editable), Color (swatch picker), Routing (bus dropdown)
- Pre-gain (slider ±24dB), Lock toggle, Freeze toggle

**`ClipAudioInspector`** (8 rows):
- Start/End time (editable), Duration, Gain slider (±24dB)
- Pitch semitones (slider ±12st), Warp mode (enum dropdown)
- Fade In/Out lengths (dual slider)

**`PluginQuickInspector`** — 8 most-used params sa mini knobs, + "Open Full" dugme

**Before/After:**
- Pre: klik clip → inspector prikazuje generic "Clip Properties" sa ~3 stavke
- Posle: klik clip → sve relevantne opcije odmah vidljive, inline edit bez dialoga

**Test:** selection_provider mock → ContextualInspector ruta na correct widget

---

### SPEC-04 · Adaptive Toolbar (DAW)

**Problem:** Toolbar prikazuje iste alate bez obzira na selekciju. Audio clip selektovan = nema shortcut za Fade/Normalize. MIDI selektovan = nema Quantize.

**Root cause:** `engine_connected_layout.dart` toolbar zona — statičan `Row` sa fiksnim widgetima.

**Implementacija:**

```
lib/widgets/toolbar/
    adaptive_toolbar.dart                   ← wrapper
    toolbar_section_transport.dart          ← Play/Stop/Record (uvek vidljivo)
    toolbar_section_audio_clip.dart         ← Fade/Warp/Normalize/Pitch/Reverse
    toolbar_section_midi_clip.dart          ← Quantize/Velocity/CC/PianoRoll
    toolbar_section_marker.dart             ← Tempo Change/TimeSig/Color
    toolbar_section_track.dart              ← Arm/Solo/Mute/Color/Rename
```

**Layout:**
```
[Transport — uvek]  |  [Contextual sekcija — animirano]  |  [Global: Undo/Redo/Save]
```

**Contextual sekcija tranzicija:** `AnimatedSwitcher` sa `FadeTransition` 150ms + `SlideTransition` Y=8px gore — osećaj da "ispliva" nova sekcija kad se promeni selekcija.

**Before/After:**
- Pre: toolbar isti za sve → tražiš akciju u meniju
- Posle: selektuješ audio clip → fade/pitch/normalize dugmad se pojavljuju odmah, bez menija

---

### SPEC-05 · Layout Presets + Layout Snapshots

**Problem:** Nema brze adaptacije layout-a za 1-monitor, 2-monitor, ultrawide, niti pamćenja custom layout-a.

**Root cause:** `DawLowerZoneController` nema preset logiku; panel visibility state (`_leftVisible`, `_rightVisible`, `_lowerVisible`) je ephemeral.

**Implementacija:**

```
lib/providers/panel_layout_provider.dart    ← novi, replaces ad-hoc bools
lib/models/panel_layout_snapshot.dart       ← serializovani snapshot
```

**`PanelLayoutProvider`** state:
```dart
class PanelLayout {
  bool leftVisible; double leftWidth;    // 250px default
  bool rightVisible; double rightWidth;  // 300px default
  bool lowerVisible; double lowerHeight; // 380px default
  DawSuperTab activeLowerTab;
  DawEditGroup expandedGroup;
  // HELIX
  int helixDockTab; double helixDockHeight;
  bool helixSpineExpanded;
}
```

**Presets (Cmd+Shift+1/2/3/0):**
- `1` → Single monitor: left hidden, right hidden, lower 40% — maksimalan timeline
- `2` → Dual monitor: left 250, right 300, lower 300 — balanced
- `3` → Ultrawide (3440px+): left 320, right 400, lower 280 — sve vidljivo
- `0` → Default factory reset

**Snapshots (Cmd+Opt+1..9):** persist 9 named slots u `~/.fluxforge/layout_snapshots.json`
- Hold `Cmd+Opt+1` 500ms = save (toast potvrda)
- Tap `Cmd+Opt+1` = restore

**Before/After:**
- Pre: svaki put ručno podešavanje panela
- Posle: `Cmd+Shift+1` = produkcija (fokus timeline), `Cmd+Shift+2` = mixing (sve vidljivo)

---

### SPEC-06 · HELIX Spine — Compact/Expanded Toggle

**Problem:** Spine ima 5 ikona bez labela → novi korisnik ne zna šta je šta. Nema tooltip ni labela.

**Root cause:** `helix_screen.dart:835-863` — ikone bez `Tooltip` wrappera, bez label widgeta.

**Implementacija (minimalna promena — nema refaktora):**

1. Wrap svake ikone u `Tooltip(message: 'AUDIO ASSIGN', waitDuration: Duration(ms: 120))`
2. Dodati toggle dugme na dnu Spine-a (ikona `«`/`»` ili double-arrow)
3. Kada expanded (toggle ON): width 96px, ispod svake ikone dodati `Text(label, 10px, brandSteel, letterSpacing: 0.8)`
4. `_spineExpanded` bool persist u `SharedPreferences`

**Animacija:** `AnimatedContainer(width: _expanded ? 96 : 48, duration: 200ms, curve: Curves.easeOutCubic)`

**Before/After:**
- Pre: 5 mystery ikone, ne znaš šta otvara šta
- Posle: hover → tooltip za 120ms, ili expand za stalne labele

**Fajl:** `helix_screen.dart:835-863` — minimalno 20 linija promena

---

### SPEC-07 · HELIX Stub Tabovi — Never Empty

**Problem:** 6 od 12 Command Dock super-tabova (SFX, BT, DNA, AI, CLOUD, A/B) vraćaju praznu stranicu ili "placeholder" bez informacija.

**Root cause:** `helix_screen.dart:2034, 2500, 2838, 3188, 3852, 4114` — `Container()` ili jednostavan `Text('Coming soon')`

**Implementacija — `StubTabPlaceholder` widget:**
```dart
class StubTabPlaceholder extends StatelessWidget {
  final String tabName, description, estimatedPhase;
  final List<String> plannedFeatures; // max 4
  final IconData icon;
}
```

**UI za svaki stub tab:**
```
[ikona  64px  u gold gradient circle]
[TAB NAME  20px  brandGold]
[1-2 rečenica šta će ovde biti]
[Planned: Phase X · Est: Q3 2026]
[──────────────────]
[• Feature 1]
[• Feature 2]
[• Feature 3]
[⚡ Coming in Phase X]
```

**Svaki stub tab dobija opis:**
- **SFX**: "Procedural SFX pipeline — generate sfx_reel_stop, sfx_coin, sfx_bonus iz fizičkih parametara"
- **BT**: "Behavior Tree visual editor — drag-drop logic za slot mehanike bez koda"
- **DNA**: "Slot Sound DNA analysis — spectral fingerprint, automatic stage classification"
- **AI**: "Copilot v1 — voice authoring, gap detection, mix suggestions"
- **CLOUD**: "Multi-studio sync — real-time collab via CRDT, cloud asset library"
- **A/B**: "Live A/B testing — 2 mix varijante u produkciji, player retention metrics"

**Before/After:**
- Pre: prazan container → korisnik misli da je bug
- Posle: lepa placeholder stranica, jasno šta dolazi, kada, zašto

---

### SPEC-08 · HELIX MONITOR Tab — 20 → 5 Kategorija

**Problem:** MONITOR super-tab ima 20 sub-tabova u linearnom scrollable redu — previše za snalaženje.

**Root cause:** `lower_zone_types.dart:726` `SlotLabMonitorSubTab` enum, renderer crta flat.

**Nova struktura (5 collapsible kategorija):**
```
LIVE  ▼  (default open)
  Timeline · Energy · Voice · Spectral

AI  ▶  
  Fatigue · Neuro · AI Copilot

MATH  ▶
  MathBridge · RGAI · A/B Test

DEBUG  ▶
  Debug · Profiler · Profiler Adv · Event Debug

EXPORT  ▶
  Export · UCP Export · Fingerprint · Spatial · Resource · Voice Stats
```

Isti pattern kao SPEC-02 — `SlotLabMonitorGroup` enum + group header widget.

---

### SPEC-09 · HELIX Command Dock — Quick Actions Strip

**Problem:** Nema kontekstualnih quick-action dugmadi po aktivnom tabu — svaka akcija = navigacija u podmeniu.

**Root cause:** `helix_screen.dart:1198-1303` — Command Dock nema akcije iznad tab bar-a.

**Implementacija:**

```dart
// 10px visok strip (isti bg kao dock), između drag handle i tab bar
Widget _buildQuickActionStrip(int activeTab) {
  return AnimatedSwitcher(
    duration: Duration(ms: 200),
    child: _getActionsForTab(activeTab),
  );
}
```

**Akcije po tabu** (max 6 dugmadi, svako 28px visoko, 70-120px široko):
- **FLOW**: `[▶ Sim Run]` `[+ Stage]` `[+ Transition]` `[↩ Reset FSM]`
- **AUDIO**: `[Grid Snap]` `[Solo Bus]` `[Zero Gain]` `[Export Mix]`
- **MATH**: `[🔒 Lock]` `[↺ Recalc]` `[📋 Blueprint]` `[Validate]`
- **INTEL**: `[▶ Full Sim]` `[📊 Coverage]` `[🐛 Diagnostics]`
- **EXPORT**: `[📦 Package]` `[git Commit]` `[✅ Validate All]` `[📧 Send Report]`
- Ostali: po 2-3 najvažnije akcije

**Style:** `TextButton.icon`, 28px, `brandSteel` boja, hover = `brandGold`, compact padding `EdgeInsets.symmetric(h: 8, v: 4)`

**Before/After:**
- Pre: klik na tab → find action u sub-tab → klik
- Posle: action button odmah vidljiv na vrhu dock-a čim je tab aktivan

---

### SPEC-10 · Floating Math HUD na Neural Canvas

**Problem:** RTP, Volatility, Hit Freq, Max Win su u MATH tabu — nevidljivi dok radiš u FLOW/AUDIO tabovima.

**Root cause:** `helix_screen.dart:869-1014` NeuralCanvas — nema overlay sa live math metrics.

**Implementacija:**

```
lib/widgets/helix/math_hud_overlay.dart     ← novi widget
```

**HUD widget:** pozicioniran top-right Neural Canvas-a, `Positioned(top: 12, right: 12)`:
```
[RTP: 96.2% ●] [VOL: 6.8 ●] [HIT: 1:4.2 ●] [MAX: 2847× ●]
```
- Svaka metrika: `Container(68×22px, color: _hudBg)` + vrednost (11px bold) + color dot
- Color dot: `brandGold` = in target, `Colors.amber` = warn ±5%, `Colors.red` = out
- Tap HUD → expand/collapse (height animira 22px → 0px, ikona ostaje)
- Persist collapse state u session

**`_hudBg`:** `Color(0xFF0D0D12).withOpacity(0.72)` — poluprozirno, ne ometa canvas

**`MathHudProvider`** — consumer `NeuroAudioProvider` + `GameModelProvider`, real-time update svake 500ms

**Before/After:**
- Pre: meoriše RTP izvan MATH taba = 3 klika do informacije
- Posle: uvek vidljivo bez prekidanja workflow-a

---

### SPEC-11 · Reel Context Lens Affordance

**Problem:** Reel cell context lens ne znaš da možeš kliknuti — nema vizuelnog hinta.

**Root cause:** `helix_screen.dart:1003-1008` + `premium_slot_preview.dart` reel cells — nema hover state ni affordance indikator.

**Implementacija:**

```dart
// U reel cell widget (premium_slot_preview.dart)
MouseRegion(
  onEnter: (_) => setState(() => _reelHovered[i] = true),
  onExit:  (_) => setState(() => _reelHovered[i] = false),
  child: AnimatedContainer(
    duration: Duration(ms: 120),
    decoration: BoxDecoration(
      border: Border.all(
        color: _reelHovered[i] ? FluxForgeTheme.brandGold.withOpacity(0.7) : Colors.transparent,
        width: 1.5,
      ),
    ),
    child: Stack(children: [
      reelContent,
      if (_reelHovered[i]) Positioned(bottom: 4, right: 4,
        child: Icon(Icons.search, size: 14, color: FluxForgeTheme.brandGold.withOpacity(0.9))),
    ]),
  ),
)
```

**Lens expand sadržaj** (Context Lens panel):
- Stage binding info (naziv stage-a ili "unbound")
- Volume slider (0-200%, real-time FFI update)
- Pitch offset (−12st do +12st)
- 32px waveform preview strip
- Long press na lens → `VoiceDetailEditor.open(layer)`

**Before/After:**
- Pre: korisnik ne zna da može kliknuti reel cell
- Posle: hover → gold border + magnifier → klik → lens sa svim relevantnim kontrolama

---

### SPEC-12 · HELIX Mini Mode (200px strip)

**Problem:** Nema kompaktnog prikaza za dual-monitor setup.

**Root cause:** `helix_screen.dart:96, 225-227` — mode state machine ima COMPOSE(0)/FOCUS(1)/ARCHITECT(2), nedostaje MINI(3).

**Implementacija:**

```dart
// helix_screen.dart — dodati u _HelixMode enum
mini,   // = 3

// Keyboard trigger
case LogicalKeyboardKey.keyM when meta && shift:
  setState(() => _mode = _mode == _HelixMode.mini ? _HelixMode.compose : _HelixMode.mini);
```

**Mini Mode layout (200px visina, full width):**
```
[SPIN ▶]  [FSM: BASE_SPIN]  [RTP 96.2%●]  [VOL 6.8●]  [HIT 1:4.2●]  |  [6× bus meters 8px wide]  |  [Orb 60px]  |  [🟢🟡🔴 compliance]  [Cmd+Shift+M ↗]
```

Animacija: `AnimatedContainer(height: _mode==MINI ? 200 : fullHeight, curve: Curves.easeInOutCubic, duration: Duration(ms: 300))`

**Before/After:**
- Pre: HELIX uvek zauzima ceo ekran
- Posle: `Cmd+Shift+M` = kompresuje u 200px strip, ostatak ekrana slobodan za DAW ili drugu aplikaciju

---

### SPEC-13 · Quick Assign Hotbar

**Problem:** Assign workflow zahteva skrolanje event liste svaki put. Nema "pinned stage" targeta.

**Root cause:** Nema hotbar komponente. Drag-drop postoji ali bez persistent targeta.

**Implementacija:**

```
lib/widgets/helix/quick_assign_hotbar.dart   ← novi
```

**Hotbar:** 5 slotova × 44px, pozicioniran između Omnibar-a i Neural Canvas-a (sakriven dok ASSIGN mode nije aktivan):
```
[REEL_STOP ×] [REEL_SPIN ×] [WIN_SMALL ×] [        ] [        ]
  ↑ bound        ↑ bound       ↑ bound      empty drop  empty drop
```

**Interakcija:**
- Drag zvuk iz event pool-a → drop na hotbar slot → bind direktno (nema more confirmation)
- Tap bound slot → audition preview (Play ikona)
- Long press bound slot → unbind
- `×` dugme = unbind brzo
- Slot se highlightuje gold outline tokom drag-a (drop target feedback)

**Persist:** slots se čuvaju u `SlotLabProjectProvider` kao `List<String?> hotbarBindings` per project

**Before/After:**
- Pre: drag zvuk → skroluješ do pravog stage-a u listi → drop → repeat za svaki
- Posle: drag zvuk → drop na hotbar slot → odmah bound, hotbar ostaje tu za sledeći put

---

### SPEC-14 · Panel Focus Indicator + Keyboard Routing

**Problem:** Keyboard evente prima neizvestan panel. Tab prečice (1-9 u HELIX) ne rade ako je fokus negde drugde.

**Root cause:** Flutter focus system — `FocusNode` nije eksplicitno dodeljen panelima; eventi proppadaju bez garantovanog primaoca.

**Implementacija:**

```
lib/providers/panel_focus_provider.dart     ← koji panel je aktivan
```

**`PanelFocusProvider`:**
```dart
enum FocusedPanel { helix_dock, helix_canvas, helix_spine, daw_timeline, daw_lower, daw_left, daw_right }
```
Klik na panel = `provider.setFocus(panel)` → panel dobija 1px gold border:
```dart
Container(
  decoration: BoxDecoration(
    border: focused ? Border.all(color: FluxForgeTheme.brandGold.withOpacity(0.4), width: 1) : null,
  ),
  child: Focus(focusNode: _panelFocusNode, child: panelContent),
)
```

**Keyboard routing:** `FocusScope` → aktivan panel prima key evente. `Tab` / `Shift+Tab` = `FocusScopeNode.nextFocus()` / `previousFocus()`.

**Before/After:**
- Pre: stisneš `1` u HELIX ali ništa se ne desi jer je fokus na DAW panelu
- Posle: aktivan panel gold-bordered, keyboard uvek ide u pravi panel

---

### SPEC-15 · Selection Memory (Cmd+1..9 — Layout Comps)

**Problem:** Nema brze navigacije između sačuvanih view konfiguracija. Authoring session od 30+ min = ručno vraćanje panela.

**Root cause:** Nema `SelectionMemoryProvider`. Panel state je ephemeral.

**Implementacija:**

```
lib/providers/selection_memory_provider.dart
lib/models/selection_memory_slot.dart
```

**`SelectionMemorySlot`:**
```dart
class SelectionMemorySlot {
  String? name;              // auto: "Slot 1" ili custom
  PanelLayout layout;        // iz SPEC-05 PanelLayoutProvider
  DateTime savedAt;
  String? previewLabel;      // "MATH tab @ RTP 96.2%"
}
```

**Trigger:**
- `Cmd+Shift+[1-9]` (hold 400ms) = **save** slot → toast `"💾 Slot 1 sačuvan"`
- `Cmd+[1-9]` (tap) = **restore** slot → instant layout switch sa 180ms Spring animacijom
- `Cmd+0` = factory default layout

**Persist:** `~/.fluxforge/selection_memory.json` — max 9 slotova, rotira FIFO

**Before/After:**
- Pre: ručno otvaranje/zatvaranje panela pri svakoj promeni konteksta
- Posle: `Cmd+1` = authoring mode, `Cmd+2` = QA mode, `Cmd+3` = presentation mode — 0.2s

---

### SPEC-16 · Uniformni Hover Tooltips (150ms delay)

**Problem:** Razne ikone i dugmadi nemaju tooltip ili imaju ga sa pogrešnim delay-om. Korisnik mora da pogađa.

**Root cause:** Nedosledna upotreba `Tooltip` widgeta — neki imaju, neki nemaju.

**Implementacija:**

Centralizovani `FluxTooltip` wrapper koji zamenjuje sve inline `Tooltip`-e:
```dart
class FluxTooltip extends StatelessWidget {
  final String message;
  final String? shortcutHint;    // npr. "Cmd+K"
  final Widget child;

  // message + newline + "⌘K" ako shortcutHint postoji
  // waitDuration: Duration(ms: 150)
  // style: brandGold background 85% opacity, 11px white text
}
```

**Rollout:** `grep -rn 'Tooltip(' flutter_ui/lib/ | wc -l` → nahodi sve, zameni sa `FluxTooltip`. Plus dodati na sve ikone koje nemaju tooltip (`Spine ikone, Orb buttons, toolbar dugmadi`).

**Before/After:**
- Pre: ikonice su mystery — ne znaš šta radi bez klikanja
- Posle: hover 150ms → kompaktni tooltip sa label + keyboard hint

---

### SPEC-17 · Stage Trigger Keyboard Shortcuts u HELIX

**Problem:** U HELIX FLOW tabu nema direktnih keyboard shortcuta za triggerovanje stage-ova. Svaki trigger = klik na FSM node.

**Root cause:** `helix_screen.dart:580-600` keyboard zone — nema case za stage trigger keys.

**Implementacija:**

```dart
// helix_screen.dart keyboard handler — dodati:
case LogicalKeyboardKey.digit1 when _activeDockTab == HelixDockTab.flow && !isShift:
  gameFlowProvider.triggerStage(GameFlowState.idle); break;
case LogicalKeyboardKey.digit2 when _activeDockTab == HelixDockTab.flow && !isShift:
  gameFlowProvider.triggerStage(GameFlowState.baseSpin); break;
// ... 1-8 za 8 stage-ova
case LogicalKeyboardKey.space when _activeDockTab == HelixDockTab.flow:
  gameFlowProvider.triggerSpin(); break;
case LogicalKeyboardKey.digit1..8 when isShift:
  gameFlowProvider.forceExitToStage(stages[key - 1]); break;
```

**Visual feedback:** Klik shortcut → odgovarajući FSM node u FLOW tabi se pulse-uje (gold glow 300ms Spring) + toast "Stage: BASE_SPIN" 1.5s bottom-center.

**Stage map (1-8):**
1=IDLE · 2=BASE_SPIN · 3=REEL_STOP · 4=WIN · 5=CASCADE · 6=FREE_SPINS · 7=BONUS · 8=JACKPOT

**Before/After:**
- Pre: QA sesija = klik FSM node za svaki test scenario
- Posle: `2` = start spin, `4` = force win, `6` = jump to free spins — 8× brži QA

---

### SESIJA REDOSLED (preporučen za implementaciju)

```
Sprint 1 (kompaktnost, visok impact, niski rizik):     ✅ DONE
  SPEC-06  Spine labele          [2h]                  ✅
  SPEC-07  Stub tab placeholders [2h]                  ✅
  SPEC-16  Tooltips              [3h]                  ✅
  SPEC-17  Stage shortcuts       [2h]                  ✅
  SPEC-11  Reel Context Lens     [4h]                  ✅
  SPEC-10  Math HUD              [3h]                  ✅

Sprint 2 (navigacija, srednji kompleksitet):           ✅ DONE (3ef5afff)
  SPEC-01  Cmd+K Palette         [1 ned]               ✅
  SPEC-02  EDIT tab grupe        [3h]                  ✅
  SPEC-08  MONITOR grupe         [3h]                  ✅
  SPEC-09  Quick Actions Strip   [4h]                  ✅
  SPEC-14  Panel Focus           [3h]                  ✅

Sprint 3 (power features):                             ✅ DONE (8b83940b)
  SPEC-03  Smart Inspector       [1 ned]               ✅ ContextualInspector + 8 sub-inspectors
  SPEC-04  Adaptive Toolbar      [3h]                  ✅ Transport+Context modes
  SPEC-13  Quick Assign Hotbar   [3h]                  ✅ 5 pinned slots in HELIX ASSIGN
  +        SelectionProvider foundation                ✅ 8 SelectionType variants

Sprint 4 (layout memory, power users):                 ✅ DONE (ce2a90a9 + c58c7d04)
  SPEC-05  Layout Presets        [4h]                  ✅ Cmd+Shift+1/2/3 Compose/Focus/Mix
  SPEC-15  Selection Memory      [4h]                  ✅ Cmd+1..9 restore / Cmd+Shift+1..9 save
  SPEC-12  HELIX Mini Mode       [1 ned]               ✅ Cmd+Shift+M, 200px strip
  +        FFI null safety (16 *const c_char)          ✅
  +        SlotLab→SelectionProvider wire (604ce478)   ✅
```

**Sprint 1-4 = COMPLETE. SPEC-01..17 svi implementirani. Sve ostalo: maintenance, FAZA 1 (P0), FAZA 2 (perf), FAZA 3+ (diferencijatori).**

---

## FAZA 3 — Slot Machine Diferenciatori

### 3.1 IGT/Playa parity fixes (iz memorije)

| # | Zadatak | Status | Fajl(ovi) |
|---|---|---|---|
| 3.1.1 | **S1 Feature Wins završni momenti** — CortexEye verifikacija da FsSummary UI overlay triggeruje na FS exit + skip telemetrija log | commit `2b539a0e` postoji, verify nedostaje | `lib/models/stage_models.dart`, `lib/services/stage_audio_mapper.dart`, `crates/rf-stage/src/audio_naming.rs` |
| 3.1.2 | **S2 Splash → Slot animacija** (Boki eksplicitno tražio — profi, kinematska, reel spin-up intro, zlatni sjaj, simboli padaju, dramatski crescendo → tišina) | ⏳ | `lib/screens/splash_screen.dart`, `lib/screens/slot_lab_screen.dart` |
| 3.1.3 | **S3 Reel Loop + Reel Stop audio** — `sfx_reel_spin_r0..r5` (loop) i `sfx_reel_stop_r0..r5` (stinger) engine wire-up | ⏳ | `crates/rf-stage/src/audio_naming.rs`, `lib/services/stage_audio_mapper.dart`, `lib/screens/slot_lab_screen.dart` |
| 3.1.4 | **S4 Audio tab Helix lower zone** — ranije prijavljeno "ništa se ne prikazuje" | ⏳ | CortexEye snap → debug → fix |
| 3.1.5 | Podnaslovi podtabova razlikuju se od naslova | ⏳ | `lib/widgets/helix/helix_lower_zone.dart` |

### 3.2 OrbMixer

| # | Zadatak | Status | Fajl(ovi) |
|---|---|---|---|
| 3.2.1 | **O1** Phase 10e-2 Rust FFI 5s ring buffer + WAV export | ⏳ | `crates/rf-bridge/src/orb_mixer_ffi.rs`, `lib/providers/orb_mixer_provider.dart` |
| 3.2.2 | **O2** Per-bus FFT za precizniji masking + performance isolate >100 voices | ⏳ | `crates/rf-bridge/src/orb_mixer_ffi.rs`, `lib/widgets/slot_lab/orb_mixer_painter.dart` |
| 3.2.3 | **O3** Orb stabilnost — nestaje kada se menja kanal (fix state pop) | ⏳ | CortexEye watch orb kroz switch → state log → fix |
| 3.2.4 | Orb ghost trails 2s → ekspanzija na 10s + dupli-tap = revert (Part V.3 time travel seed) | ⏳ | `lib/widgets/slot_lab/orb_mixer.dart` |

### 3.3 NeuralBindOrb

| # | Zadatak | Status | Fajl |
|---|---|---|---|
| 3.3.1 | **N1** Phase 2 ghost slot indikatori — stage-ovi bez bindinga kao ghost u orbu | ⏳ | `lib/widgets/slot_lab/neural_bind_orb.dart` |
| 3.3.2 | Snap-to-grid visual feedback u drag (trenutno nevidljiv) | ⏳ | `lib/widgets/slot_lab/neural_bind_orb.dart` |

### 3.4 Regulatory (Compliance live)

| # | Zadatak | Cilj |
|---|---|---|
| 3.4.1 | Live compliance meter u omnibaru (UKGC / MGA / SE / NV / NJ traffic lights) | dok autoruje |
| 3.4.2 | Inline tooltips — pravilo koje violira + one-click auto-fix | kontekstualno |
| 3.4.3 | LDW guard u realnom vremenu — celebration duration cap kad win==bet | transparent |
| 3.4.4 | Near-miss quota tracker — "2.1% near-miss, ceiling 3%" | live UI |
| 3.4.5 | Compliance manifest button — jurisdiction picker + signed export | one-click |

### 3.5 Atmos + spatial catch-up

| # | Zadatak | Effort |
|---|---|---|
| 3.5.1 | Atmos object export MVP (bar jedan path) | 3 nedelje |
| 3.5.2 | HOA 3rd–5th order authoring | 1 mesec |
| 3.5.3 | Personalized HRTF via HRTFformer / graph NN | 1 mesec |

---

## FAZA 4 — AI Copilot (Leapfrog)

> Nijedan konkurent ovo nema. Prozor ~12-18 meseci pre Wwise odgovora.

### 4.1 Copilot infrastruktura

| # | Zadatak | Tehn | Effort |
|---|---|---|---|
| 4.1.1 | `rf-copilot` crate sa `Action` trait (svaka sugestija reversibilna) | Rust | 2 nedelje |
| 4.1.2 | Local LLM integracija (Llama 3 8B ili Phi-4) via Metal MPSGraph | MPS | 1 mesec |
| 4.1.3 | Isolate za copilot, FFI kroz `rf-bridge/src/copilot_ffi.rs` | | 1 nedelja |
| 4.1.4 | Dart `CopilotService` + `CopilotPanel` widget | Flutter | 2 nedelje |

### 4.2 Features

| # | Zadatak | Input | Output |
|---|---|---|---|
| 4.2.1 | Generative mix ("make rollup 15% more euphoric") | voice/text | param delta preview branch |
| 4.2.2 | Predictive automation (after 5-10 manual moves) | gesture history | ghost-curve in timeline |
| 4.2.3 | Voice commands ("solo voice bus", "audition next win tier", "export MGA manifest") | WhisperKit local | direct action |
| 4.2.4 | Error prevention (LDW, near-miss, celebration LUFS) | continuous validators | flag before user hears |

### 4.3 Persistent memory (Part V.4)

| # | Zadatak | Skladište |
|---|---|---|
| 4.3.1 | `~/.fluxforge/memory.db` SQLite event log | local only |
| 4.3.2 | Embedding model (sentence-transformers via tract) | Rust |
| 4.3.3 | Style fingerprint export/import `.style` file | portable |
| 4.3.4 | Popuniti `rf-neuro` stubs sa memory substrate | Rust crate |

### 4.4 Predictive Event Routing (Part V.10)

| # | Zadatak | Osnova |
|---|---|---|
| 4.4.1 | Classifier audio features → Stage label | Sonic DNA Layer 2/3 postoji |
| 4.4.2 | Drag file → 85% confidence "reel_stop for bus SFX" | isolate query |
| 4.4.3 | Gap detection — "12 files match FREE_SPIN_START, top 3 suggestion" | list |
| 4.4.4 | Auto-fill proposals (one-click) | provider surface |
| 4.4.5 | Learning from rejections (feed V.4 memory) | cross-session |

---

## FAZA 5 — Generativni layer

### 5.1 Generative Slot Scoring (Part V.6)

| # | Zadatak | Tehn |
|---|---|---|
| 5.1.1 | `rf-generative` crate, ONNX via tract | Rust |
| 5.1.2 | Stable Audio Open Small local inference (30s u 8s na M3) | ONNX |
| 5.1.3 | `generate_stage_audio(stage, style, duration)` FFI | `sam_ffi.rs` |
| 5.1.4 | "GEN" sub-tab u MUSIC ili MONITOR super-tab | UI |
| 5.1.5 | Emotional arc timeline input (tension → excitement → euphoria) | UI |
| 5.1.6 | Style transfer iz reference slota | Model |
| 5.1.7 | Variation generation (5 alternate BIG_WIN stings) | 1 klik |
| 5.1.8 | Auto-compliance validator na generisan audio | `rf-slot-builder` |

### 5.2 Generative Voice / Foley (Part V.9)

| # | Zadatak |
|---|---|
| 5.2.1 | Text-to-SFX ("coin drop, wet marble, bright" → 3s WAV preview) |
| 5.2.2 | Voice cloning za VO draftove (30s sample → generate scripted lines) |
| 5.2.3 | Variation generation (10 pitched alternatives za random container) |
| 5.2.4 | AudioSeal watermark na sve generisano (provenance audit) |

### 5.3 Neural stem separation

| # | Zadatak | Model |
|---|---|---|
| 5.3.1 | Demucs v4 (HT-Demucs) local inference | ONNX via tract |
| 5.3.2 | UI: "extract stems from reference" u DAW PROCESS tab | Flutter |
| 5.3.3 | Kim Vocal 2 za vocal-only extract | alternate model |

---

## FAZA 6 — GPU DSP + spatial pro

### 6.1 GPU compute

| # | Zadatak | Tehnologija |
|---|---|---|
| 6.1.1 | wgpu compute shaderi za partitioned convolution reverb (IR > 2s, 10-50× speed-up) | WebGPU/wgpu |
| 6.1.2 | Metal Performance Shaders za neural inference (copilot + generative) | MPSGraph |
| 6.1.3 | HOA encode/decode na GPU | wgpu |
| 6.1.4 | Fragment shaders za real-time spectrum + heatmap (sada CPU) | Flutter .frag |

### 6.2 End-to-end neural mastering

| # | Zadatak |
|---|---|
| 6.2.1 | Ozone-class quality chain (multiband comp + limiter + EQ + satur) |
| 6.2.2 | Local inference |
| 6.2.3 | Per-jurisdiction LUFS target (UKGC -16 LUFS, MGA -18 LUFS, ...) |

---

## FAZA 7 — Collab + visionOS + Orb Ecosystem

### 7.1 Multi-studio Collab (Part V.7)

| # | Zadatak | Tehn |
|---|---|---|
| 7.1.1 | `rf-crdt` crate — Yjs (wasm) ili Automerge 2.0 (native Rust) | CRDT |
| 7.1.2 | WebRTC transport (Pion ili Flutter plugin) | audio stream + data |
| 7.1.3 | `services/collaboration_service.dart` | Flutter |
| 7.1.4 | Presence indicators na svaki control (cursor, selection) | UI |
| 7.1.5 | Voice chat integracija (LiveKit) | audio |
| 7.1.6 | Roles + permissions (composer / sound designer / QA read-only) | auth |
| 7.1.7 | Comment threads na timeline regione | UI |

### 7.2 Gaze Mix on visionOS (Part V.2)

| # | Zadatak | Tehn |
|---|---|---|
| 7.2.1 | visionOS companion app (Flutter ili SwiftUI) | Xcode |
| 7.2.2 | ARKit eye tracking → gaze coordinates 90Hz | visionOS 2 |
| 7.2.3 | Pinch + drag gesture → volume, pan, width | gesture |
| 7.2.4 | WebRTC ili CRDT channel ka macOS master | transport |
| 7.2.5 | Voice command "solo voice bus" hands-free | WhisperKit |

### 7.3 Orb Ecosystem (Part V.5)

| # | Zadatak |
|---|---|
| 7.3.1 | Refaktor `OrbMixerProvider` → generic `OrbProvider<T>` (T = voice / bus / DSP / container / music) |
| 7.3.2 | `OrbContainerWidget` host any `OrbProvider<T>` |
| 7.3.3 | `OrbGestureService` — centralizovana logika (click/double/long-press) |
| 7.3.4 | Nested orbs — master orb sadrži 6 bus orbova, svaki sadrži voice orbove |
| 7.3.5 | Dock / Float / Merge / Split gestures |
| 7.3.6 | Drag voice orb u bus orb = re-route |

### 7.4 Time-Travel Authoring (Part V.3)

| # | Zadatak |
|---|---|
| 7.4.1 | Ghost trails na orbu (10s fade-out history) |
| 7.4.2 | Session scrub ring — spoljni prsten orba zamenjuje 30s mix-a |
| 7.4.3 | Git-style branches (named save state, branch tree minimap) |
| 7.4.4 | "What did I hear 10 minutes ago?" — mix params rewind, audio replay kroz snapshot |
| 7.4.5 | Audio ring buffer 5min (extension od Phase 10e-2 5s) |
| 7.4.6 | Proširiti `rf-state` za BranchId + persistent tree |

---

## FAZA 8 — Platform Leadership

| # | Zadatak | Outcome |
|---|---|---|
| 8.1 | **Open-source `rf-stage` taxonomy** + SDK za third-party integraciju | ecosystem gravity |
| 8.2 | Plugin SDK — third-party UI paneli, FX, AI modeli | ecosystem pull |
| 8.3 | Marketplace za style fingerprint + generative presete + compliance templates | revenue + lock-in |
| 8.4 | Education platform — embedded tutorials, AI mentor, certifikacija | talent pipeline |
| 8.5 | Regulatory partnerships — pre-validated audio templates per jurisdiction | moat deepening |
| 8.6 | **FluxForge Cloud** — optional cloud sync, collab, version history, compliance archive | SaaS layer |
| 8.7 | Research partnership (university / lab) na perceptual audio + generative slot | frontier R&D |

---

## DAW — Dodatne stavke (Boki će dopunjavati)

> Ostavljeno mesto za nove DAW-specifične poboljšanje zahteve.

- [ ] _(popuniti posle pregleda)_
- [ ] _(popuniti)_

---

## HELIX — Dodatne stavke (Boki će dopunjavati)

> Ostavljeno mesto za nove HELIX-specifične poboljšanje zahteve.

- [ ] _(popuniti)_
- [ ] _(popuniti)_

---

## OPERATIVA & STRATEŠKO (kako radimo, kako se predstavljamo, kako se branimo)

> 10 preporuka koje nisu featuri nego procesi, strateški potezi, micro-UX i risk mitigation. Sve odobreno za TODO.

### Proces razvoja

| # | Stavka | Detalj |
|---|---|---|
| OP1 | **Boki kao patient zero customer** | Svaka Bokijeva live sesija snimljena (CortexEye Vision postoji). Svaki frustration moment (long pause, pogrešan klik, glasna reakcija) = automatski backlog item. Razvoj vođen tvojim stvarnim trenjem, ne pretpostavkom. |
| OP2 | **Release cadence — 2-nedeljni sprintovi sa tematskim imenima** | `release_005_atmos`, `release_006_copilot`, `release_007_collab`. Predvidljiv tempo. Partneri planiraju oko nas. Tema = jedan glavni differentiator po sprintu. |

### Strateški potezi

| # | Stavka | Detalj |
|---|---|---|
| OP3 | **Akademske partnership** | IRCAM (Pariz, audio research), Stanford CCRMA, McGill MIRA, MIT CSAIL audio. Internship pipeline. Istraživački radovi → FluxForge featuri kroz 3-6 mesečne projekte. Free R&D, talent funnel. |
| OP4 | **Open Stage Taxonomy konzorcijum** | Pre nego konkurent forkne, osnuj nezavisan governance body koji vlada `rf-stage` taksonomijom (kao Khronos za grafiku, MMA za MIDI). Wwise i FMOD moraju da slušaju nas, ne obrnuto. Drives industry adoption. |

### UX patterni (mali ali strateški)

| # | Stavka | Detalj |
|---|---|---|
| OP5 | **Inline voice memos** | Pritisneš ikonicu pored bilo kog elementa (track, voice, stage, container) → snimaš 30s voice memo. Sound designer ostavlja white-board notu vezanu za konkretan stage. Niko od konkurenata ovo nema. Jednostavno za implementaciju, masivan UX boost. |
| OP6 | **Selection memory — Cmd+1…9 / Cmd+Shift+1…9** | Photoshop layer comps za audio. Cmd+1 sačuva trenutni view (track + zoom + selected tab + lower zone state) na slot 1; Cmd+Shift+1 vraća. 30+ minuta authoring postaje 30 sekundi recall-a. Crucial za workflow brzinu. |
| OP7 | **Right-click "Explain this"** | Corti objašnjava bilo koji parameter / feature kontekstualno. AI tooltip 2.0. Onboarding bez tutorijala. Onboarding novog tima u studio = nekoliko dana umesto nedelja. Reuses Faza 4 AI Copilot infrastrukturu. |

### Risk mitigation

| # | Stavka | Detalj |
|---|---|---|
| OP8 | **Wwise + FMOD interop layer** | `rf-bridge` može da exportuje u Wwise SoundBank i FMOD bank. Pozicija: "FluxForge je tvoj authoring tool, koristi bilo koji runtime". Studio koji koristi Wwise nema razloga da te odbije — koegzistuješ, ne zameniš. Najefikasnija obrana od pretnje #1 i #2. |

### Operativno

| # | Stavka | Detalj |
|---|---|---|
| OP9 | **Anonymous opt-in telemetry** | Koje funkcije se najčešće koriste, gde korisnik zaglavi (long pause + abandon), šta zatraži pa ne nađe (search query bez rezultata). Data-driven roadmap umesto pretpostavki. UKGC-friendly ako je opt-in + anonimno + agregirano. |

### Brand / pozicioniranje

| # | Stavka | Detalj |
|---|---|---|
| OP10 | **Quarterly "Sound of Slots" report** | Agregirana anonymous statistika iz svih FluxForge projekata: najčešći stages per market, LUFS distribucija, popularne bus konfiguracije, win-tier ratio. Industry benchmark — konkurenti se referenciraju **na nas**. Free press svake 3 meseca. Postavlja FluxForge kao autoritet, ne učesnika. |

---

## MOONSHOTS — Blue-sky inovacije (sve što može biti bolje nego što jeste)

> Boki: "od tebe mi treba sve futurističko i što može da bude bolje nego što jeste".
> Ovo nije roadmap — ovo je open-ended istraživački kanon. Sve napisano je tehnički zamislivo do 2030. Implementacija po prilici, partnerima, prilikama. **Ništa nije preskočeno.**

### M.1 Audio engine inovacije

| # | Stavka | Detalj |
|---|---|---|
| M1.1 | **Differentiable audio engine** | Ceo `rf-engine` postaje differentiable computational graph. Definiš target ("treba da zvuči ovako") + reference audio → engine samosebe trenira da pristigne tu. Ozone-style mastering, ali za mix params. |
| M1.2 | **Neural codec native storage** | Interno sve audio kao DAC/Encodec embeddings (6-12 kbps). Lossless re-encode na export. 50-100× manje storage, instant load, semantic search po sound bibliotekama. |
| M1.3 | **Hybrid CPU+GPU+NPU automatic dispatch** | DSP graf zna gde da pošalje koju operaciju (CPU za simple biquad, GPU za convolution, NPU za neural inference). Auto-balance po platformi. |
| M1.4 | **Time-varying impulse response reverb** | Reverb IR se menja sa game state-om real-time. Bonus mode = bigger room. Free spins = celestial. Bez disclosure latency. |
| M1.5 | **Microsound granular at sample level** | Per-sample granularni shaping ispod sample rate-a. Texture morphing impossible u trenutnoj DSP-u. |
| M1.6 | **Wave function physics modeling** | Slot symbol audio modeluje se kao quantum superposition; "observe" event kolapsuje state. Eksperimentalno. |
| M1.7 | **Sub-millisecond latency mode** | Apple Audio Workgroups + Vulkan compute = <1ms voice→output latency. Headphone live monitoring uživo. |

### M.2 UX paradigme (post-mouse era)

| # | Stavka | Detalj |
|---|---|---|
| M2.1 | **3D spatial UI on Vision Pro** | Orbi u stvarnom 3D prostoru. Mix isfront tebe, EQ levo, automation desno. Telo postaje navigation. |
| M2.2 | **Predictive disclosure** | UI se sažima/proširuje na osnovu šta korisnik **sledeće** radi (LSTM nad gesture history). Kad si na rollup mix-u, automation lane se sam expand-uje. |
| M2.3 | **Touchless gesture** (Leap Motion v2 / camera) | Pomeraš ruku iznad laptopa, knob se okreće. Bez dodira. |
| M2.4 | **Emotional state UI** | Kamera čita Bokijevu mimiku → frustration detected → UI density se smanjuje, Corti predlaže pauzu ili "želiš da preuzmem ovaj rollup?". |
| M2.5 | **Sound-driven UI** | Pevaš melody, sistem prepoznaje, mapira na MIDI clip, postavlja u trenutni stage. Humming = audio sketch input. |
| M2.6 | **Brain-computer interface (Neuralink class)** | Misli komanda → slot reaguje. Eksperimentalno, ne prioritet, ali ostavljeno za 2028+ kad BCI consumer-grade. |
| M2.7 | **Spatial computing keyboard** | Virtuelna tastatura iznad bilo kog uređaja kroz visionOS/AR Glasses. Authoring bez fizičkog laptopa. |
| M2.8 | **Adaptive density per-user** | Junior sound designer dobija pojednostavljen UI; senior dobija sve. Auto-detection po behavioral signature-u. |
| M2.9 | **Single-key universal action** | "Make better" dugme — Corti analizira kontekst i radi 1 najbitniju izmenu. Lazy day mode. |

### M.3 AI infrastruktura

| # | Stavka | Detalj |
|---|---|---|
| M3.1 | **Federated learning** | Boki-jeve mix preferences kombinovane anonimno sa drugim FluxForge korisnicima. Sve corisniki postaju pametniji bez compromise privatnosti. |
| M3.2 | **Agentic LLM execution** | Corti može da pokrene sub-agente: "ti optimizuj voice bus, ti kreiraj 3 variante big-win sting-a, ti validiraj UKGC compliance, vrati mi rezime za 30 minuta". |
| M3.3 | **Multi-modal copilot** | Sluša audio + vidi screen + razume tekst → kombinovano razumevanje. "Ovaj zvuk levo na ekranu, smanji ga 2dB" radi bez specifikacije. |
| M3.4 | **Explainable AI** | Svaka sugestija ima causal chain: "predlažem -3dB na 1.2kHz jer ima peak na 2.5s spina, koincidentan sa near-miss audio cue, što po UKGC test guideline-u može flagovati nepošten signaling". |
| M3.5 | **Adversarial training u kompoziciji** | Jedan Corti pravi mix, drugi ga kritikuje (player umoran, regulator skeptic, igrač neopiranje). Iterativno do nirvane. |
| M3.6 | **Long-context industry memory** | Cela slot audio istorija (svaki popularan slot 2010-2030) u persistent memoriji za referencu. "Šta bi MGM/IGT uradili?" |
| M3.7 | **Self-improving DSP** | DSP algoritmi koje Corti piše/optimizuje sam. Custom EQ topology za specific use case. |
| M3.8 | **Continuous-learning watcher** | Corti gleda Bokija svaki put; svake nedelje šalje "evo 3 stvari koje sam naučio od tebe ove nedelje". |

### M.4 Slot mehanike (audio kao prvoklasna mehanika)

| # | Stavka | Detalj |
|---|---|---|
| M4.1 | **Adaptive volatility** | Slot menja volatility profil na osnovu igračevog state-a (samo gde regulisano dozvoljava). Audio postaje signal koji vodi modulaciju. |
| M4.2 | **Audio-driven RTP** | Soundscape utiče na win frequency u realnom vremenu. Domena gambling research. |
| M4.3 | **Generative paytables** | Corti generiše balanced paytable za zadati RTP target + volatility profile + audio mood. |
| M4.4 | **Cross-game audio motifs** | Shared melodic theme između slot-ova istog studio-a. Brand recognition kao Hollywood franchise. |
| M4.5 | **Time-of-day aware slots** | Različiti audio mix za jutro / popodne / veče. Smiren ujutro, energičan uveče. |
| M4.6 | **Quantum slot mode (eksperimentalno)** | Superpozicija outcome-a; igračeva opservacija kolapsuje. Teoretski model za novu generaciju mehanike. |
| M4.7 | **Synesthesia slot** | Vizuelni feedback (boja simbola, emisija svetlosti) sinhronizovan sa audio nota — ton C = plavo, F# = ljubičasto. |
| M4.8 | **Player-personalized mix** | Svaki igrač ima blago drugačiji audio mix po ML preferences. Privacy-preserving. |

### M.5 Compliance / regulatory budućnost

| # | Stavka | Detalj |
|---|---|---|
| M5.1 | **Explainable RTP** | Svaki spin ima math + audio attribution chain za regulator audit. Why this RTP, why this audio. |
| M5.2 | **Real-time jurisdiction detection** | Geo-IP + cabinet ID → automatic compliance switch (UKGC, MGA, NV, NJ, ON). |
| M5.3 | **Self-mutating compliance** | Kad regulacija changes, slot auto-adjusts (sa human approval gate). |
| M5.4 | **Zero-knowledge player privacy** | Telemetry koja ne otkriva player ID nikom — homomorphic aggregation. |
| M5.5 | **Regulator co-pilot** | Regulator ima view-only Corti sa explanation. "Ovaj slot u ovom mode-u radi ovo, evo proof." |
| M5.6 | **Anti-money-laundering audio fingerprint** | Audio metadata pomaže AML detection (cabinet usage patterns). |
| M5.7 | **Quantum-safe manifest** | Post-quantum signature na svaki compliance manifest (CRYSTALS-Dilithium). Survives 2030+ quantum break. |

### M.6 Production / workflow budućnost

| # | Stavka | Detalj |
|---|---|---|
| M6.1 | **Live remote sound design** | Boki šeta sa AirPods Pro + iPhone, podešava mix glasom dok je u kafiću. WebRTC streaming celog projekta. |
| M6.2 | **Music synchronization to math** | Auto-tune base bed tempo na hit frequency / volatility. Tempo = 120 ako je high vol, 84 ako je low vol. |
| M6.3 | **Polyphonic timelines** | Više simultanih timelines koji se sinhronizuju (slot + bonus + pick + jackpot). Bez dialog-a "switch context". |
| M6.4 | **Project DNA** | Svaki projekat ima cryptographic hash istorije svake odluke. "Ovaj zvuk nastao je iz [genealogy chain] commits, autori X, Y, Z." |
| M6.5 | **Time-machine debugging** | "U kom commitu se ovaj zvuk loše ponašao?" — git bisect za audio. |
| M6.6 | **Intent merging u kolaboraciji** | Ne samo CRDT merge, nego semantičko merging "ti hoćeš punchier, ja hoćeš smoother → kompromis". |
| M6.7 | **A/V sync engine** | Automatska sinhronizacija audio sa svakim video element u slotu. Frame-accurate by default. |
| M6.8 | **Hot reload za sve** | Svaki kod change (Rust + Dart + DSP) — instant reload bez restart-a. State persisted. |

### M.7 Distribution / runtime

| # | Stavka | Detalj |
|---|---|---|
| M7.1 | **WebAssembly slot engine** | Slot kao `.wasm` modul, runs anywhere (browser, mobile, embedded) bez native build. |
| M7.2 | **Edge inference** | Neural copilot deployed na CDN edge — Cloudflare Workers AI. Sub-100ms suggestion latency globally. |
| M7.3 | **P2P self-distribution** | Slot ima embedded P2P delivery (BitTorrent layer). Cabinet pulls bandwidth-optimized. |
| M7.4 | **Lite version u browseru** | Preview slot u Chrome bez instalacije. Sales pitch link click → live preview u 5 sekundi. |
| M7.5 | **VR slot machine experience** | Slot kao VR scene, ne flat UI. Quest 3 / Vision Pro / PSVR2. |
| M7.6 | **Smart TV native** | Tizen / webOS app za TV slot. Cabinet on TV setup. |
| M7.7 | **Dolby Atmos for Home** | Slot u Dolby Atmos format za soundbar / AVR / home theater playback. |

### M.8 Research collaboration

| # | Stavka | Detalj |
|---|---|---|
| M8.1 | **Open dataset za slot audio research** | Anonimno otpakirana FluxForge data za istraživače. Free corpus → academic citations → reputational moat. |
| M8.2 | **Slot Audio Olympics** | Yearly challenge sa scoring leaderboard. Najbolji studio audio dobija nagradu + press. |
| M8.3 | **Cognitive science partnership** | Measurable engagement metrics (HRV, EEG, eye tracking). Da li audio zaista vodi engagement? Empirijski. |
| M8.4 | **Synthetic player** | Psihometrijski model igrača koji testira novi slot pre deployment. "Ovaj je previše agresivan za novog igrača." |
| M8.5 | **Audio-cognition paper publishing** | FluxForge tim objavljuje 2-3 paper-a godišnje (DAFx, AES, ICAD). Akademski autoritet. |

### M.9 Hardware-level moonshots

| # | Stavka | Detalj |
|---|---|---|
| M9.1 | **Holographic slot machine** | 3D pixel space (Looking Glass / autostereoscopic display). Simboli lebde u prostoru. |
| M9.2 | **Haptic vest** | Bass pumping kroz haptic vest (bHaptics, Subpac). Big win = celo telo oseti. |
| M9.3 | **Custom FluxForge hardware controller** | Fizički knob/fader kontroler dizajniran za FluxForge workflow. Kao Push za Ableton. |
| M9.4 | **AirPods Pro 3 head-tracking compose** | Head tilt = pan, head nod = volume confirm, head shake = undo. Zero-keyboard authoring. |
| M9.5 | **Quantum random number** | True quantum RNG za slot mehaniku (IBM Q cloud access). Provably random. |
| M9.6 | **Neural processor co-design** | Ako stignemo do skale — partnerstvo sa silicon vendor-om za FluxForge-optimized NPU. |

### M.10 Blue-sky / 2030+

| # | Stavka | Detalj |
|---|---|---|
| M10.1 | **AGI sound director** | Do 2030, AI radi ceo slot audio sam, čovek samo daje creative brief. FluxForge postaje hiring platform za AI sound directors. |
| M10.2 | **Brain-state-aware mixing** | Biofeedback od igrača utiče na audio (gde regulisano). EEG → mood detection → mix adapt. |
| M10.3 | **Memory-augmented slot** | Slot koji se sećа prošlih spinova svakog igrača i evoluira (privacy-preserving). |
| M10.4 | **Ambient slot — never-loop** | Slot bez ponavljanja audio-a u celom svom životnom veku. Generativna struktura. |
| M10.5 | **Cross-modal generation** | Daš sliku → Corti generiše audio. Daš melody → Corti generiše vizual. |
| M10.6 | **Self-replicating slot studio** | Studio kao kontejner — Corti može da klonira "naš stil rada" i predloži novi slot bez ljudske intervencije. |
| M10.7 | **Speech-of-the-world voice library** | Svaki language u svetu, svaki dialect, svaki ton — gen-on-demand kroz ElevenLabs evolution. |
| M10.8 | **AI Composer Twin** | Digital twin tvog kompozitora — još je živ, ali Corti uči od njega tako da kad ode, zna da održi style. |
| M10.9 | **Post-DAW paradigm** | DAW kao koncept iz 2020-ih nestaje. FluxForge prelazi u "intent-based audio environment" — opisuješ šta hoćeš, sve se desi. |
| M10.10 | **FluxForge OS** | Cela OS layer dizajnirana za audio professionals. Apple Logic + Ableton se gase. |

---

## Futurističko (ideje bez tajm lajna)

> Sve ideje koje su iznad standardnog roadmap-a. Boki je odobrio "sve" → ovde stoje kao kandidati za buduće faze ili kao istraživački pravci.

### Audio + Mix

- **Neural tension arc** — model koji mapira game-theory tension → target LUFS / spektralna kriva real-time. Slot ima emocionalni luk koji se autom prati.
- **Spectral gene editor** — "pomeri bass harmonics +3dB samo pri rollup-u" kroz manipulaciju latent space-a neural reverb-a. Bez parametarskih krivulja, direktno na neural model kao DNA sekvenca.
- **Haptic mixing** (Wacom + Force Touch) — osetiš kad knob stigne do target-a, kad LUFS pređe gate, kad solo prelazi.
- **Voice authoring hands-free** — ceo authoring flow glasom (dictate + commands). Korisnik ne mora ni da gleda u ekran.
- **Procedural ambient bed** — never-loop background koji se generiše real-time iz semantic description-a ("Mediterranean coastal village, sunset, light wind") → 4h jedinstvenog ambijenta bez ponavljanja.
- **Foley sandbox sa fizikom** — fizički simulator (ball drop, water splash, glass shatter) — iz fizičkih parametara generišeš realistic SFX. Niko ne mora da snima foley za prototype.

### Slot specifično

- **Reelovi kao interaktivni audio kontroleri** — svaka pozicija na reelu = touchzone za audio asset. Reel postaje step-sequencer ili parameter modulator. Slot dizajner može da koristi sam reel UI kao audio canvas (rešenje za tvoje pitanje "kako iskoristiti reelove da ne stoje bezveze").
- **AI Demo Reel generator** — daš slot, AI uzme best moments + applause + voice-over → 30s promo audio za sales pitch. Boki ide na sajam, ima 5 demo-a istog dana.

### QA + testing

- **AI regression tester** — Corti igra 10,000 spinova preko noći i prijavljuje audio anomalije koje ljudski QA ne bi nikad uhvatio (habituacija, fatigue, masking u win konstelacijama, near-miss iznad limita).
- **Live Wear Test** — Corti glumi "umorenog igrača" i meri kada audio prelazi u "iritantno" posle 100/500/1000 spinova. Slot mašine žive od dugih sesija; audio mora da izdrži.
- **Real-time A/B u produkciji** — produkcijski slot emituje 2 mix varijante, prikuplja player retention metrike, automatski bira winner. Audio postaje data-driven posle launch-a.

### AI + Memory

- **Cross-project style learn** — Corti prepoznaje "ovo zvuči kao Wrath of Olympus arc" i predlaže pattern preko više slot projekata.
- **Personalized spatial HRTF per-user** — kamera snimak uha → ML generiše individual HRTF dataset (Apple radi to za AirPods Pro).

### Ekosistem + monetizacija

- **Style fingerprint marketplace** — kompozitori prodaju svoj `.style` potpis (iz V.4 persistent memory). Kupac dobija auto-mix u tom stilu. Ekosistem revenue za studio.
- **Compositions-as-code** — slot kao `.ts` ili `.py` skript umesto JSON. Git diffable, peer-review-able, type-safe.

### Compliance + budućnost

- **Compliance as smart contract** — regulator verifikuje cryptographic proof bez pristupa projektu. Cryptographic manifest signed with private key.
- **Quantum-safe compliance audit trail** — post-quantum signature na svaku manifest (CRYSTALS-Dilithium, Falcon). Manifest preživi i nakon kvantnog probojа.

---

## GOTOVO (arhiva)

| Datum | Stavka | Commit |
|---|---|---|
| 2026-04-24 | FLUX_MASTER_VISION_2026 — total-system audit + 5yr roadmap | `ecbb87c2` |
| 2026-04-24 | Orb out-of-card + voice mixer focus-solo + detail editor + radial menu + CortexEye `/eye/voice*` | `830d9cb1` |
| 2026-04-24 | Casino Vault brand palette (5 fajlova) | `2917ae33` |
| 2026-04-24 | FsSummary + UiSkipPress stages + skip telemetry | `2b539a0e` |
| 2026-04-24 | Scene transition early-dismiss | `893c9c9d` |
| 2026-04-24 | AnticipationConfig wire-up (sekvencijalna anticipacija kao IGT) | `e7bca3a8` |
| 2026-04-22 | Slot Flow IGT Parity — Talas 1/2/3 | `1a3b2af7` `3b563438` `47d18a27` |
| 2026-04-22 | OrbMixer Phase 6-10e (9 commits, 2,153 LOC) | višestruki |
| 2026-04-22 | Sonic DNA Classifier Layer 2+3 + FFI + Dart modeli | |
| 2026-04-22 | CortexEye automation infrastruktura | |
| 2026-04-21 | 84/84 QA bagova rešeno | |
| 2026-04-21 | HELIX Auto-Bind QA + Redesign | |
| 2026-04-21 | NeuralBindOrb instant binding | |
| 2026-04-21 | CORTEX Organism refaktor | |

---

## ARHITEKTURA — ključni fajlovi

**Flutter screens:**
- `lib/screens/launcher_screen.dart` (1,144 LOC)
- `lib/screens/splash_screen.dart` (515 LOC)
- `lib/screens/welcome_screen.dart` (597 LOC)
- `lib/screens/daw_hub_screen.dart` (1,037 LOC)
- `lib/screens/engine_connected_layout.dart` (**17,292 LOC** monolith)
- `lib/screens/slot_lab_screen.dart` (**15,215 LOC** monolith)
- `lib/screens/helix_screen.dart` (9,735 LOC)

**SlotLab widgets:**
- `lib/widgets/slot_lab/premium_slot_preview.dart` (7,676 LOC)
- `lib/widgets/slot_lab/slot_voice_mixer.dart` (2,585 LOC)
- `lib/widgets/slot_lab/slotlab_bus_mixer.dart` (933 LOC)
- `lib/widgets/slot_lab/live_play_orb_overlay.dart` (1,174 LOC)
- `lib/widgets/slot_lab/orb_mixer.dart` (534 LOC)
- `lib/widgets/slot_lab/orb_mixer_painter.dart`
- `lib/widgets/slot_lab/neural_bind_orb.dart` (1,340 LOC)
- `lib/widgets/slot_lab/game_flow_overlay.dart` (2,344 LOC)

**Providers:**
- `lib/providers/slot_lab/slot_voice_mixer_provider.dart`
- `lib/providers/orb_mixer_provider.dart`
- `lib/providers/slot_lab/game_flow_provider.dart`
- `lib/providers/subsystems/composite_event_system_provider.dart`

**Services:**
- `lib/services/event_registry.dart`
- `lib/services/stage_audio_mapper.dart`
- `lib/services/cortex_eye_server.dart`

**Lower zone:**
- `lib/widgets/lower_zone/lower_zone_types.dart` (HELIX taxonomy def)
- `lib/widgets/lower_zone/slotlab_lower_zone_widget.dart` (5,338 LOC)

**Theme:**
- `lib/theme/fluxforge_theme.dart` (Casino Vault palette)

**Rust core (48 crates, ~259k LOC):**
- `crates/rf-engine/src/playback.rs` (7,500+ LOC — audio thread entry)
- `crates/rf-dsp/` (eq, dynamics, reverb, delay, spatial, convolution, timestretch)
- `crates/rf-stage/src/{event,stage,timing,trace,audio_naming,taxonomy}.rs`
- `crates/rf-slot-lab/src/{engine,engine_v2}.rs` + `parser/par.rs`
- `crates/rf-bridge/src/*_ffi.rs` (67 FFI files)
- `crates/rf-aurexis/` (SAM)
- `crates/rf-slot-builder/` (compliance)
- `crates/rf-state/` (history / snapshots)
- `crates/rf-neuro/` (stub — popuniti u Fazi 4.3)

---

## REDOSLED IZVRŠAVANJA (default, bez Boki override-a)

```
┌─ FAZA 0  [odmah]     Commit-verify tekući rad
├─ FAZA 1  [0-4 ned]   P0 blokirajuće — FFI safety, event race, widget tests, HELIX stubs
├─ FAZA 2  [2-6 ned]   UX kompaktnost + brzina + monolith refactor
├─ FAZA 3  [6-12 ned]  Slot diferencijatori — S1-S4, O1-O3, N1, compliance, atmos
├─ FAZA 4  [3-6 mes]   AI Copilot — LLM local, predictive routing, persistent memory
├─ FAZA 5  [6-9 mes]   Generativni layer — slot scoring, voice/foley, stem separation
├─ FAZA 6  [9-12 mes]  GPU DSP + end-to-end neural mastering
├─ FAZA 7  [12-18 mes] Collab + visionOS gaze + orb ecosystem + time-travel
└─ FAZA 8  [18+ mes]   Platform leadership — SDK, marketplace, cloud, partnerships
```

Paralelizam: Faze 1+2 idu uvek zajedno. Faza 3 može paralelno sa krajem Faze 1. Faze 4-5 dele `rf-generative` / `rf-copilot` infrastrukturu. Faza 6 može rano da krene ako se nađe GPU-specific low-hanging fruit.

---

**Reference:** `FLUX_MASTER_VISION_2026.md` — svaka stavka iz ovog TODO-a mapira se na sekciju Vision dokumenta. Prioritete menja Boki.
