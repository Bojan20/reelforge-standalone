# Claude Code — FluxForge Studio

---

## 🚫 NIKAD PLAN MODE 🚫

**NIKADA ne koristi `EnterPlanMode` tool.** Direktno radi — istraži, analiziraj, implementiraj. Bez planiranja, bez čekanja potvrde plana. Korisnik želi akciju, ne planove.

---

## 🚫 APSOLUTNA ZABRANA SHIPOVANJA 🚫

**NEMA SHIPOVANJA DOK:**

1. **100% FUNKCIONALNO** — SVE funkcionalnosti moraju raditi bez izuzetka
2. **100% IMPLEMENTIRANO** — SVE planirane feature-e moraju biti ubačene (P0, P1, P2, P3, P4)
3. **100% TESTIRANO** — SVE mora proći kroz kompletno testiranje:
   - `flutter analyze` = 0 errors
   - `cargo test` = 100% pass
   - `flutter test` = 100% pass
   - Manual QA = sve sekcije proverene
   - Regression tests = svi prolaze

**TRENUTNI STATUS:** Proveri `.claude/MASTER_TODO.md` za tačan procenat.

**SHIP KRITERIJUM:** 100% across the board — NIŠTA MANJE.

**AKO NISI SIGURAN DA LI JE SPREMNO → NIJE SPREMNO.**

---

## 📋 PROCEDURA POSLE ZADATKA

**Posle taska:** Pitaj "Da li da commitujem?" i čekaj potvrdu.

**Dokumentaciju (MASTER_TODO, README, .claude/) ažuriraj SAMO ako:**
- Task završava PLANNED/IN PROGRESS stavku iz MASTER_TODO
- Task menja arhitekturu ili dodaje nov sistem
- Korisnik eksplicitno traži ažuriranje

**NIKADA:**
- ❌ NE commituj bez pitanja
- ❌ NE ažuriraj dokumentaciju posle rutinskih taskova (bugfix, UI tweak, refactor)

---

## 🎰 SLOTLAB — ZABRANA HARDKODIRANJA 🎰

**NIŠTA VEZANO ZA SLOTLAB NE SME BITI HARDKODIRANO!**

- ❌ NE hardkodirati win tier labele ("BIG WIN!", "MEGA WIN!", itd.)
- ❌ NE hardkodirati boje, ikone, ili stilove za win tierove
- ❌ NE hardkodirati rollup trajanja, thresholds, ili multiplier ranges
- ✅ Koristi jednostavne tier identifikatore: "WIN 1", "WIN 2", "WIN 3", "WIN 4", "WIN 5"
- ✅ Sve konfiguracije treba da budu data-driven (iz P5 WinTierConfig sistema)

---

## ⚠️ STOP — OBAVEZNO PRE SVAKE AKCIJE ⚠️

**NIKADA ne menjaj kod dok ne uradiš OVO:**

```
1. flutter analyze    → MORA biti 0 errors
2. Tek onda edituj
3. flutter analyze    → MORA biti 0 errors
4. Tek onda pokreni
```

**Ako `flutter analyze` ima ERROR → POPRAVI PRE POKRETANJA**
**NIKADA ne pokreći app ako ima compile error!**

---

## 🔴 KRITIČNO — FULL BUILD PROCEDURA 🔴

**PRE SVAKOG POKRETANJA APLIKACIJE — OBAVEZNO URADI SVE KORAKE:**

```bash
# KORAK 1: KILL PRETHODNE PROCESE
pkill -f "FluxForge" 2>/dev/null || true
pkill -f "flutter run" 2>/dev/null || true
sleep 1

# KORAK 2: BUILD RUST BIBLIOTEKE
cd "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio"
cargo build --release

# KORAK 3: KOPIRAJ DYLIB-ove (KRITIČNO!)
cp target/release/librf_bridge.dylib flutter_ui/macos/Frameworks/
cp target/release/librf_engine.dylib flutter_ui/macos/Frameworks/

# KORAK 4: FLUTTER ANALYZE (MORA PROĆI)
cd flutter_ui
flutter analyze

# KORAK 5: BUILD MACOS APP (xcodebuild, NE flutter run)
cd macos
find Pods -name '._*' -type f -delete 2>/dev/null || true
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FluxForge-macos build

# KORAK 5.5: KOPIRAJ DYLIB-ove U APP BUNDLE (xcodebuild NE KOPIRA!)
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_bridge.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_engine.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/

# KORAK 6: POKRENI APLIKACIJU
open ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app
```

**NIKADA:**
- ❌ `flutter run` direktno (codesign fail na ext. disku)
- ❌ Pokretanje bez kopiranja dylib-ova
- ❌ Pokretanje bez `cargo build --release`
- ❌ Pokretanje ako `flutter analyze` ima errors

**VERIFIKACIJA:** Dylib datumi MORAJU biti DANAS u sve tri lokacije (target/release, Frameworks, App Bundle).

---

## ⚡ QUICK RUN COMMAND — "pokreni"

**Kada korisnik napiše "pokreni", "run", "start app" → ODMAH pokreni CELU SEKVENCU:**

```bash
pkill -f "FluxForge" 2>/dev/null || true
cd "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio" && \
cargo build --release && \
cp target/release/librf_bridge.dylib flutter_ui/macos/Frameworks/ && \
cp target/release/librf_engine.dylib flutter_ui/macos/Frameworks/ && \
cd flutter_ui/macos && \
find Pods -name '._*' -type f -delete 2>/dev/null || true && \
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FluxForge-macos build && \
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_bridge.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/ && \
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_engine.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/ && \
open ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app
```

**KRITIČNO:** UVEK `~/Library/Developer/Xcode/DerivedData/` (HOME), NIKADA `/Library/Developer/`

---

## CORE REFERENCES (must-read, in this order)

1. .claude/00_AUTHORITY.md — Truth hierarchy
2. .claude/00_MODEL_USAGE_POLICY.md — **Pročitaj prvo!**
3. .claude/01_BUILD_MATRIX.md
4. .claude/02_DOD_MILESTONES.md
5. .claude/03_SAFETY_GUARDRAILS.md

**Quick References:**
- .claude/guides/MODEL_SELECTION_CHEAT_SHEET.md — 3-second model decision
- .claude/guides/PRE_TASK_CHECKLIST.md — Mandatory validation before tasks
- .claude/guides/PROVIDER_ACCESS_PATTERN.md — Code standard for Provider usage

**Active Roadmaps:**
- .claude/tasks/P4_COMPLETE_VERIFICATION_2026_01_30.md — ALL P4 COMPLETE (26/26 ✅)
- .claude/tasks/P9_AUDIO_PANEL_CONSOLIDATION_2026_01_31.md — P9 COMPLETE (12/12 ✅)
- .claude/tasks/P13_FEATURE_BUILDER_INTEGRATION_2026_02_01.md — P13.8 Apply & Build (5/9 ✅)
- .claude/tasks/P14_TIMELINE_COMPLETE_2026_02_01.md — P14 COMPLETE (17/17 ✅)

**Architecture Documentation:**
- .claude/architecture/SSL_CHANNEL_STRIP_ORDERING.md — SSL signal flow
- .claude/architecture/HAAS_DELAY_AND_STEREO_IMAGER.md — Stereo processing
- .claude/architecture/ANTICIPATION_SYSTEM.md — Per-reel tension L1-L4
- .claude/architecture/SLOT_LAB_AUDIO_FEATURES.md — P0.1-P0.22, P1.1-P1.5
- .claude/architecture/EVENT_SYNC_SYSTEM.md — Stage→Event mapping
- .claude/architecture/SLOT_LAB_SYSTEM.md — Full SlotLab architecture
- .claude/architecture/TEMPLATE_GALLERY_SYSTEM.md — P3-12 Template system
- .claude/architecture/AUREXIS_UNIFIED_PANEL_ARCHITECTURE.md — AUREXIS intelligence panel
- .claude/architecture/UNIFIED_TRACK_GRAPH.md — DAW ↔ SlotLab shared engine architecture
- .claude/specs/SLOTLAB_TIMELINE_ULTIMATE_SPEC.md — P14 Timeline spec

---

## 📚 DETAILED REFERENCE DOCS (read on-demand, NOT always loaded)

Sledeći fajlovi sadrže detaljnu dokumentaciju. Claude čita ih SAMO kada su relevantni za trenutni task:

| Doc | Sadržaj | Kada čitati |
|-----|---------|-------------|
| `.claude/docs/IMPLEMENTED_FEATURES.md` | Sve implementirane feature-e (4300+ linija) | Kad treba detalj o nekom feature-u |
| `.claude/docs/DEPENDENCY_INJECTION.md` | GetIt registracija, svi provideri, layeri | Kad radis sa DI/GetIt/providerima |
| `.claude/docs/TECH_STACK_AND_ARCHITECTURE.md` | Tech stack, 7-layer arch, workspace, crates | Kad treba arhitekturni pregled |
| `.claude/docs/BUILD_AND_DEPENDENCIES.md` | Cargo/Flutter deps, build commands, EQ spec | Kad treba dependency info |
| `.claude/docs/PERFORMANCE_OPTIMIZATION.md` | SIMD, metering, UI provider optimization | Kad radis na performansama |
| `.claude/docs/TROUBLESHOOTING.md` | SlotLab audio debugging, 9 poznatih problema | Kad SlotLab audio ne radi |
| `.claude/docs/SLOTLAB_STAGE_FLOW.md` | Stage flow, timeline drag, reel phases | Kad radis na SlotLab stage sistemu |
| `.claude/docs/CICD_PIPELINE.md` | GitHub Actions, build matrix, regression tests | Kad radis na CI/CD |
| `.claude/docs/SYSTEM_ANALYSIS_PROTOCOL.md` | "Komplet analiza" procedura, SlotLab summary | Kad korisnik traži system review |
| `.claude/docs/MODEL_SELECTION.md` | Opus vs Sonnet decision tree, task assignments | Kad treba odluka o modelu |
| `.claude/docs/CLAUDE_MD_FULL_BACKUP_2026_02_27.md` | Kompletan originalni CLAUDE.md (7938 linija) | Ako nešto fali iz reference fajlova |

---

## REVIEW MODE

Kada korisnik napiše "review", "gate", "check", "audit", "pass/fail" → automatski ulaziš u REVIEW MODE definisan u `.claude/REVIEW_MODE.md`. Ne implementiraš — samo PASS/FAIL.

---

## DEBUGGING

**KORISNIK NEMA PRISTUP KONZOLI/LOGU.**

- NE koristi `debugPrint` ili `print` za debugging
- NE pitaj korisnika šta piše u logu
- Ako treba debug info, prikaži ga u samom UI-u (overlay, snackbar, ili debug panel)
- Ili: analiziraj kod logički bez oslanjanja na runtime log

---

## KRITIČNA PRAVILA

### 1. Ti si VLASNIK ovog koda
- Znaš sve o njemu, ne praviš iste greške dva puta, ne čekaš podsećanje

### 2. 🧠 GOD MODE

| Prefiks | Značenje |
|---------|----------|
| `Implement:` | Kreiraj |
| `Fix:` | Popravi |
| `Add:` | Dodaj |
| `Change:` | Izmeni |
| `Audio:` | Audio |
| `Flow:` | Game flow |
| `UI:` | UI |

| Modifikator | Efekat |
|-------------|--------|
| `Do it.` | Bez potvrde |
| `Silent.` | Samo kod |
| `Minimal.` | Najmanji diff |
| `+commit` | Auto-commit |

**Pravila:** CLAUDE.md UVEK važi. GOD MODE ne skip-uje STOP/BUILD/SHIP.
**Escape:** Arch decision → 1 pitanje.
**Default:** Bez prefiksa = normalan rad.

### 3. UVEK pretraži prvo
```
Kada menjaš BILO ŠTA:
1. Grep/Glob PRVO — pronađi SVE instance
2. Ažuriraj SVE — ne samo prvi fajl
3. Build — cargo build posle SVAKE promene
```

### 4. Rešavaj kao LEAD, ne kao junior
- Biraj NAJBOLJE rešenje, ne najsigurnije
- Pronađi ROOT CAUSE, ne simptom
- Implementiraj PRAVO rešenje, ne workaround
- **NIKADA jednostavno rešenje — UVEK najbolje rešenje**

### 5. UVEK čitaj CLAUDE.md pre rada
```
Pre SVAKOG zadatka (ne samo posle reset-a):
1. Pročitaj CLAUDE.md ako nisi u ovoj sesiji
2. Proveri .claude/ folder za relevantne domene
3. Tek onda počni sa radom
```

### 6. Pre pokretanja builda — ZATVORI prethodne
```bash
pkill -f "flutter run" 2>/dev/null || true
sleep 1
pkill -f "target/debug" 2>/dev/null || true
pkill -f "target/release" 2>/dev/null || true
```

### 7. Koristi helper skripte
```bash
./scripts/run.sh           # Flutter run sa auto-cleanup
./scripts/run.sh --clean   # Flutter run sa fresh build
```

### 8. Eksterni disk (ExFAT) build
Projekat je na eksternom SSD-u. macOS kreira AppleDouble (`._*`) fajlove → codesign greške.
**REŠENJE:** xcodebuild sa derived data na internom disku. **NIKADA `flutter run` direktno.**

### 9. desktop_drop Plugin — DropTarget Overlay Fix (KRITIČNO)
`desktop_drop` dodaje fullscreen DropTarget NSView → presreće SVE mouse evente.
**Rešenje:** `MainFlutterWindow.swift` koristi Timer (2s) koji uklanja non-Flutter subview-ove.
**NIKADA** jednokratno uklanjanje — plugin ponovo dodaje overlay dinamički.

### 10. Split View u Lower Zone — Default OFF
`DawLowerZoneController.loadFromStorage()` forsira `splitEnabled = false` pri startu.

### 11. Split View FFI Resource Sharing — Reference Counting
Dva split panela sa istim `trackId` → static ref counting map `_engineRefCount`.
Samo poslednji korisnik poziva `destroy()`. Važi za: `audio_warping_panel.dart`, `elastic_audio_panel.dart`.

### 12. Split View Provider Sharing — GetIt Singleton
Svi ChangeNotifier provideri u Lower Zone panelima MORAJU biti GetIt singletoni (ne lokalni `Provider()`).

---

## Jezik

**Srpski (ekavica):** razumem, hteo, video, menjam

---

## Uloge

Elite multi-disciplinary professional sa 20+ godina iskustva:
Chief Audio Architect, Lead DSP Engineer, Engine Architect, Technical Director, UI/UX Expert, Graphics Engineer, Security Expert.

**Domenski fajlovi:** `.claude/domains/audio-dsp.md`, `.claude/domains/engine-arch.md`, `.claude/project/fluxforge-studio.md`

---

## Mindset

- **AAA Quality** — Cubase/Pro Tools/Wwise nivo
- **Best-in-class** — bolje od FabFilter, iZotope
- **Proaktivan** — predlaži poboljšanja
- **Zero Compromise** — ultimativno ili ništa

---

## Flutter UI Pravila (KRITIČNO)

### Modifier Key Detection — Listener vs GestureDetector
- **Modifier key detection** → `Listener.onPointerDown` (trigeruje ODMAH)
- **Simple taps/double-taps** → `GestureDetector`
- **NIKADA** `GestureDetector.onTap` + `HardwareKeyboard.instance` za modifier keys (stale state)

### Keyboard Shortcut Suppression During Text Editing
SVAKI keyboard handler MORA imati EditableText ancestor guard kao PRVU proveru:
```dart
final primaryFocus = FocusManager.instance.primaryFocus;
if (primaryFocus != null && primaryFocus.context != null) {
  final editable = primaryFocus.context!.findAncestorWidgetOfExactType<EditableText>();
  if (editable != null) return KeyEventResult.ignored;
}
```

### Nested Drag — Listener Bypass Pattern
Nested `GestureDetector` za child drag → koristi `Listener.onPointerDown/Move/Up` (zaobilazi gesture arena).
Parent GestureDetector i dalje radi normalno. Koristiti `HitTestBehavior.opaque`.

### Stereo Waveform Display
Threshold: `widget.trackHeight > 60` (ne > 80). Default height = 80px → stereo prikazan.

### Optimistic State Pattern
Nullable `bool? _optimisticActive` za instant button feedback. `didUpdateWidget` čisti kad parent potvrdi.
**NIKADA** `Timer`/`Future.delayed` za UI feedback.

### FocusNode Lifecycle
FocusNode, TextEditingController, ScrollController, AnimationController — SVE u `initState()` + `dispose()`, **NIKADA inline u `build()`**.

---

## DSP Pravila (KRITIČNO)

### Audio Thread Rules — NIKAD NE KRŠI
```rust
// ❌ ZABRANJENO: Heap alokacije, Mutex/RwLock, System calls, Panic
// ✅ DOZVOLJENO: Stack alokacije, Pre-alocirani buffers, Atomics, SIMD
```

### SIMD Dispatch
Runtime detection: avx512f → avx2 → sse4.2 → scalar fallback.

### Biquad Filter — TDF-II
Standard 2-state transposed direct form II. `z1`, `z2` state variables.

### Lock-Free Communication
`rtrb::RingBuffer` za UI→Audio thread (non-blocking push/pop).

---

## Output Format

- Structured, clear, professional
- **Bez fluff** — no over-explaining, kratki odgovori

## Git Commits
```
🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
```

## Finalna Pravila

1. **Grep prvo, pitaj nikad**
2. **Build uvek**
3. **Full files, ne snippets**
4. **Root cause, ne simptom**
5. **Best solution, ne safest**
6. **Short answers, no fluff**
7. **Audio thread = sacred** — zero allocations

---

## 🔓 AUTONOMNI REŽIM — FULL ACCESS

**Claude ima POTPUNU AUTONOMIJU za sve operacije.**

- ✅ Čitanje/pisanje/editovanje SVIH fajlova, SVE bash komande, Git operacije
- ❌ NE pitaj za dozvolu, NE čekaj potvrdu između koraka, NE objašnjavaj pre implementacije

**Korisnik VERUJE Claude-u da donosi ispravne odluke.**
