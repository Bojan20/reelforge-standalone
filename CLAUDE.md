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
cd "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio"
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
