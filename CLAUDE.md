# Claude Code — FluxForge Studio

## Pravila

- **NIKAD Plan Mode** — direktno radi, ne koristi `EnterPlanMode`
- **NE shipuj** dok nije 100% funkcionalno, implementirano, testirano
- **Posle taska:** pitaj "Da li da commitujem?" i cekaj potvrdu
- **Srpski (ekavica)** za komunikaciju
- **Autonomni rezim** — ne pitaj za dozvolu, ne cekaj potvrdu izmedju koraka

## Pre svake akcije

```
1. flutter analyze → MORA 0 errors
2. Edituj
3. flutter analyze → MORA 0 errors
4. Tek onda pokreni
```

## Build procedura

```bash
# KILL prethodne
pkill -9 -f "FluxForge Studio" 2>/dev/null || true
pkill -f "flutter run" 2>/dev/null || true
sleep 1

# BUILD
cd "/Users/vanvinklstudio/Projects/fluxforge-studio"
cargo build --release
cp target/release/librf_bridge.dylib flutter_ui/macos/Frameworks/
cp target/release/librf_engine.dylib flutter_ui/macos/Frameworks/

# ANALYZE
cd flutter_ui && flutter analyze

# XCODEBUILD (nikada flutter run — ExFAT codesign fail)
cd macos
find Pods -name '._*' -type f -delete 2>/dev/null || true
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FluxForge-macos build

# COPY DYLIBS TO APP BUNDLE
cp "../../target/release/librf_bridge.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/
cp "../../target/release/librf_engine.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/

# RUN
open ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app
```

**UVEK** `~/Library/Developer/Xcode/DerivedData/` (HOME), **NIKADA** `/Library/Developer/`

## SlotLab — EventRegistry registracija (KRITIČNO)

- **JEDAN put registracije** — samo `_syncEventToRegistry()` u `slot_lab_screen.dart`
- **NIKADA** dodavati drugu registraciju u `composite_event_system_provider.dart` ili bilo gde drugde
- `_stageToEvent` mapa u EventRegistry ima JEDAN event po stage-u — dva sistema sa razlicitim ID formatima se medjusobno brisu i izazivaju:
  - Kocenje (N × brisanje + registracija + notifyListeners kaskada)
  - Nema zvuka (trka oko `_stageToEvent` — poslednji pisac "pobedi")
- ID format: `event.id` (npr. `audio_REEL_STOP`), **NIKADA** `composite_${id}_${STAGE}`
- `_syncCompositeToMiddleware` sinhronizuje sa MiddlewareEvent sistemom, **NE** sa EventRegistry

## SlotLab — zabrana hardkodiranja

- NE hardkodirati win tier labele, boje, ikone, rollup trajanja, thresholds
- Koristi tier identifikatore: "WIN 1" - "WIN 5"
- Sve konfiguracije data-driven (P5 WinTierConfig)

## Kriticna pravila

1. **Grep prvo** — pronalazi SVE instance pre promene, azuriraj SVE
2. **Root cause** — ne simptom, ne workaround
3. **Best solution** — ne safest, ne simplest
4. **Audio thread = sacred** — zero allocations, zero locks, zero panics
5. **Korisnik nema konzolu** — NE koristi print/debugPrint, prikazuj debug info u UI-u
6. **PROCITAJ PRE PROMENE** — OBAVEZNO procitaj i razumi svaku liniju koda pre editovanja. NIKADA ne menjaj kod koji nisi procitao i razumeo. Razumi kontekst: zasto postoji, sta radi, ko ga poziva, kakve su semantike (npr. pan=-1.0 je hard-left za stereo dual-pan, NE bug). Ako ne razumes — istazi dublje pre nego sto pipnes. Pogresna "popravka" je gora od buga.

## Tehnicke zamke

**ExFAT eksterni disk:** macOS kreira `._*` fajlove → codesign greske. Resenje: xcodebuild sa derived data na internom disku.

**desktop_drop plugin:** Dodaje fullscreen DropTarget NSView → presrece mouse evente. `MainFlutterWindow.swift` Timer (2s) uklanja non-Flutter subview-ove.

**Split View Lower Zone:** Default OFF. FFI resource sharing koristi static ref counting `_engineRefCount`. Provideri MORAJU biti GetIt singletoni.

## Flutter UI pravila

- **Modifier keys** → `Listener.onPointerDown` (NIKADA `GestureDetector.onTap` + `HardwareKeyboard`)
- **FocusNode/Controllers** → `initState()` + `dispose()`, NIKADA inline u `build()`
- **Keyboard handlers** → EditableText ancestor guard kao prva provera
- **Nested drag** → `Listener.onPointerDown/Move/Up` (bypass gesture arena)
- **Stereo waveform** → threshold `trackHeight > 60`
- **Optimistic state** → nullable `bool? _optimisticActive`, NIKADA Timer za UI feedback

## DSP pravila

- **Audio thread:** samo stack alokacije, pre-alocirani buffers, atomics, SIMD
- **SIMD dispatch:** avx512f → avx2 → sse4.2 → scalar fallback
- **Biquad:** TDF-II, `z1`/`z2` state
- **Lock-free:** `rtrb::RingBuffer` za UI→Audio thread

## SlotLab — Context Bar (ROW 2) iznad levog panela

- ROW 2 sadrži SAMO: **Undo/Redo** (levo) + **Toast** (desno)
- **OBRISANO:** NOTIF badge, ERRORS badge, preload indicator — nepotrebni
- Undo/Redo: `SlotLabProjectProvider.canUndoAudioAssignment` / `canRedoAudioAssignment`
- Toast ostaje (CLAUDE.md pravilo: korisnik nema konzolu)
- Undo/Redo iz ASSIGN header-a ukloniti (prebačeno u ROW 2)

## ⚡ Ultimativni promptovi (kratki → puna akcija)

Kada Boki napiše jedan od ovih, znam TAČNO šta da uradim bez pitanja:

---

### `QA`
```
1. flutter analyze → mora 0 errors
2. cargo test -p rf-aurexis → svi moraju proći
3. cargo test -p rf-slot-lab → svi moraju proći
4. cargo test -p rf-slot-builder → svi moraju proći
Rezime: tabela sa statusom svakog
```

---

### `BUILD`
```
Puna build procedura iz "Build procedura" sekcije.
Ubija prethodnu instancu → cargo build --release → flutter analyze → xcodebuild → copy dylibs → open app
```

---

### `ARCH N` ili `ARCH naziv`
```
Razvijam Part N iz HELIX_ULTIMATE_ARCHITECTURE.md ultimativno:
1. Čitam SLOTLAB_VS_PLAYA_ANALYSIS.md — šta Playa ima, šta mi nemamo
2. Čitam relevantne postojeće crate-ove
3. Implementiram kompletan Rust modul sa svim scenarijima, nula rupa
4. Pišem testove (100% pass rate pre commita)
5. Komitujem i updateujem doc
```

---

### `PLAYA`
```
1. Čitam SLOTLAB_VS_PLAYA_ANALYSIS.md kompletno
2. Čitam IGT playa-core i playa-slot foldere (source + config)
3. Ekstraktujem šta Playa radi bolje od nas
4. Predlažem konkretne unapređenja za trenutni task
5. Primenjujem ako Boki kaže "da"
```

---

### `AUDIT`
```
Kompletan codebase audit:
1. Sve STUB/TODO/FIXME lokacije — lista sa fajl:linija
2. Placeholderi koji ne koriste FFI a trebaju (fake dart:math umesto Rust)
3. Dead code / unreachable branches
4. Nesinhronizovani provideri vs FFI
5. Prioritizovana lista: KRITIČNO → VAŽNO → KOZMETIKA
```

---

### `MOCKUP [opis]`
```
1. Kreiram ultra-futuristički interaktivni HTML/CSS/JS mockup
2. Sve interakcije žive (hover, klik, keyboard)
3. Otvaram u browseru odmah
4. Svaki element ima jasnu namenu
```

---

### `STATUS`
```
Trenutno stanje projekta:
1. git log --oneline -10 (šta je urađeno)
2. Otvoreni TODO-ji iz MASTER_TODO.md
3. QA status (poslednji rezultati)
4. Sledeći korak prema HELIX arhitekturi
```

---

### `COMPLY [jurisdiction]` ili samo `COMPLY`
```
Pokrećem rf-slot-builder Validator na sve blueprinte:
- UKGC, MGA, SE (ili samo [jurisdiction] ako specifikovan)
- Generišem compliance manifest
- Prijavljujem svaki CRITICAL finding sa predlogom fix-a
```

---

### `BLUEPRINT [naziv slota]`
```
Generišem kompletan SlotBlueprint za [naziv]:
1. Čitam Playa + industry best practice za taj tip slota
2. Definiram StageFlow sa svim scenarijima
3. MathConfig sa realnim industry parametrima
4. AudioDna + compliance za UKGC+MGA
5. Exportujem JSON + ComplianceManifest
6. Komitujem
```

---

### `IGT`
```
1. Čitam kompletno playa-core i playa-slot source foldere
2. Tražim šta se promenilo / šta nismo iskoristili
3. Updateujem SLOTLAB_VS_PLAYA_ANALYSIS.md
4. Listu konkretnih uvida za sledeći task
```

---

### `HELIX [broj]`
```
Isto kao ARCH ali specifično za HELIX engine modula:
- Čita postojeće helix_*.rs fajlove
- Nastavlja od tačke [broj] (1.1, 1.4, 2.x, 3.x...)
- Zero rupa, futuristički, sve testirano
```

---

### `SHIP`
```
Priprema za release:
1. QA (flutter analyze + svi testovi)
2. cargo build --release --all
3. Version bump u Cargo.toml + pubspec.yaml
4. Git tag + commit
5. Izveštaj: šta je u ovom release-u
```

---

## Reference (on-demand)

- `.claude/REVIEW_MODE.md` — review/audit procedura
- `.claude/MASTER_TODO.md` — status svih sistema
- `.claude/architecture/` — aktivni architecture docs
- `.claude/docs/DEPENDENCY_INJECTION.md` — GetIt/provideri
- `.claude/docs/TROUBLESHOOTING.md` — poznati problemi
- `.claude/guides/PROVIDER_ACCESS_PATTERN.md` — Provider pattern

## Git commits

```
Co-Authored-By: Claude <noreply@anthropic.com>
```
