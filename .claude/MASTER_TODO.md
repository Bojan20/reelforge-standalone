# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-10 | **Analyzer:** 0 errors

## Key File Map

| System | Entry Point | Big Files |
|--------|------------|-----------|
| DAW UI | `main_layout.dart` | `timeline_screen.dart` |
| SlotLab | `slot_lab_screen.dart` (13K+ lines) | `slot_lab_coordinator.dart` |
| SlotLab providers | `slot_engine_provider.dart`, `slot_stage_provider.dart`, `slot_audio_provider.dart` | |
| Mixer | `engine_connected_layout.dart` | `mixer_provider.dart` |
| FFI | `native_ffi.dart` (21K+ lines) | `crates/rf-bridge/src/lib.rs` |
| Offline DSP | `offline_processing_provider.dart` | `crates/rf-offline/src/pipeline.rs` |
| SFX Pipeline | `sfx_pipeline_service.dart`, `sfx_pipeline_wizard.dart` | `sfx_pipeline_config.dart` |
| DI | `service_locator.dart` | `main.dart` (provider tree) |
| Commands | `command_registry.dart` | |

## Active Traps

- `slot_lab_screen.dart` — 13K+ lines, NE MOŽE se razbiti (Dart State class limitation)
- `native_ffi.dart` — 21K+ lines, auto-generated, READ ONLY
- `OfflineOutputFormat` enum nema OGG/AAC — SFX pipeline koristi raw FFI format ID-jeve
- `slot_lab_provider.dart` je MRTAV KOD — koristi se `SlotLabCoordinator` (typedef)
- Dirty files: `rf-plugin/`, `plugin_provider.dart`, `plugins_scanner_panel.dart` — VST hosting WIP

## ASSIGN Tab — Potpuna Rekonstrukcija (2026-03-21)

### Layout analiza

**Trenutni layout:** LEFT (260px) | CENTER (slot machine preview) | RIGHT (300px)
- Levi panel: ASSIGN / CUSTOM / AUREXIS tabovi
- Desni panel: CONFIG / POOL tabovi
- Breakpoints: <700 oba sakrivena, <900 desni sakriven, <1200 levi sakriven
- Panel resize: min 200px, max 500px (drag handle)
- Center minimum: 400px

**Problem:** 260px za ASSIGN slot = label 80px + separator 1px + waveform 52px + filename flex + badges ~40px + controls ~30px = gužva. Label se odseca, bus/priority se ne vide, prazan slot prikazuje samo "—".

**Odluka:** Layout ostaje (levi/desni/center) — drag&drop ergonomija iz POOL u ASSIGN zahteva bliže panele. Rešenje je dvored slot rendering.

### Faza 1: Dvored Slot Rendering (`_buildSlot` rekonstrukcija)

Trenutno (jednoredni, 28px):
```
[Label 80px | sep | Waveform+Filename / "—" | xN | ● | 2L | ⚠ | ▶ | ✕]
```

Novo (dvored, 40px):
```
┌────────────────────────────────────────────────┐
│ 🔊 Spin Loop                       P0  ▶  ✕  │  Red 1: bus dot + label (FULL width) + priority + hover controls
│    ░░▓▓█▓░░  reel_spin_loop.wav  x3  2L  ⚠   │  Red 2: waveform + filename + badges
└────────────────────────────────────────────────┘
```

Prazan slot:
```
┌────────────────────────────────────────────────┐
│ 🔊 Spin Loop                              P0  │
│    REEL_SPIN_LOOP                         drop │
└────────────────────────────────────────────────┘
```

Stavke za implementaciju:

- [x] **Dvored layout** — Column sa dva Row-a, mainAxisSize.min
- [x] **Red 1 (gornji):** Bus dot (5px) + Label (Expanded) + Priority badge + Play/Clear (hover-only)
- [x] **Red 2 (donji):** 10px indent + WaveformThumbnail (44x14px) + Filename + badges
- [x] **Prazan slot Red 2:** Stage ID u monospace + "← drop audio" u quick assign
- [x] **Tooltip** — label + stage + bus + priority
- [x] **Uklonjen zeleni status dot** — redundantan
- [x] **Uklonjen `showQuickAssignHighlight`** — dead variable
- [x] **Left border = bus color** — vizuelni identitet po busu

### Faza 2: Header poboljšanja

- [x] **Undo/Redo dugmad** — dodati u header, Tooltip sa opisom, disabled state kad nema istorije

### Faza 3: Duplikati — čišćenje stage ID-ova

- [x] **ANTICIPATION duplikati** — Uklonjeni per-reel/per-level iz BASE GAME LOOP, samo global+miss ostali. Per-reel u ANTICIPATION sekciji.
- [x] **LP/MP WIN duplikati** — Uklonjeni MP1-5_WIN i LP1-5_WIN iz WIN PRESENTATION Per-Symbol Win. Ostali grupni (MP_WIN, LP_WIN) + HP individual + LP6_WIN + BONUS_WIN.

### Faza 4: Bugfixevi

- [x] **`_resolveSlotBus` operator precedence** — Dodane zagrade oko `(s.contains('_LOOP') && !s.contains('REEL'))`.
- [x] **`SKIP` u `_stageDisplayLabels`** — Dodat entry `'SKIP': 'Skip'`.

### Faza 5: Estetika i konzistentnost (po FluxForgeTheme)

- [x] Sve implementirano u okviru Faze 1 (bus dot boje, priority badge, hover state, bus-colored left border, assigned/unassigned kontrast)

## Remaining / Planned

_(dodaj nove taskove ovde)_

---

## Dependency Upgrade Plan (2026-03-12 audit)

### Strukturalni problemi (pre upgrade-a)

- [ ] **6 crate-ova ne koriste workspace deps** — `rf-ml`, `rf-spatial`, `rf-master`, `rf-pitch`, `rf-restore`, `rf-realtime` imaju hardkodirane verzije umesto `workspace = true`. Konsolidovati PRE bilo kakvog upgrade-a.
- [ ] **flutter_rust_bridge verzijski raskorak** — pubspec.yaml `^2.11.1` vs Cargo.toml `"2.7"`. Sinhronizovati.
- [ ] **objc 0.2 + objc2 0.5 u rf-plugin** — nekompatibilni crate-ovi, migrirati sve na `objc2`.
- [ ] **Edition 2021 crate-ovi** — `rf-ml`, `rf-spatial`, `rf-master`, `rf-pitch`, `rf-restore`, `rf-realtime`, `rf-plugin-host` — podići na edition 2024 (osim `rf-wasm` koji ostaje 2021 za wasm-pack).
- [ ] **Dart SDK constraint** — `^3.10.4` → `^3.11.0` (prati instaliranu verziju).

### Faza 1 — Brzi bezbedni wins

| Crate/Paket | Trenutno | Cilj | Crate-ovi | Rizik |
|-------------|----------|------|-----------|-------|
| `rustfft` | 6.2 | 6.4 | rf-dsp, rf-ml, rf-spatial, rf-master, rf-pitch, rf-restore, rf-realtime | NIZAK — semver |
| `rayon` | 1.10 | 1.11 | 7+ crate-ova | NIZAK |
| `tokio` | 1.43 | 1.50 | rf-bridge, rf-ml | NIZAK |
| `portable-atomic` | 1.9 | 1.13 | rf-realtime | NIZAK |
| `wasm-bindgen` | 0.2.92 | 0.2.114 | rf-wasm | NIZAK |
| `get_it` (Flutter) | 9.2.0 | 9.2.1 | service_locator.dart | NIZAK |
| `archive` (Flutter) | 4.0.2 | 4.0.9 | soundbank builder | NIZAK |
| `media_kit` (Flutter) | 1.1.10 | 1.2.6 | video playback | NIZAK |

- [ ] Zameni `lazy_static` → `std::sync::LazyLock` (rf-bridge, rf-engine, rf-plugin) — std od Rust 1.80+
- [ ] Zameni `once_cell` → `std::sync::OnceLock` (rf-bridge, rf-engine) — std od Rust 1.70+

### Faza 2 — Srednji rizik

| Crate/Paket | Trenutno | Cilj | Napomena |
|-------------|----------|------|----------|
| `serde_yaml` | 0.9 | **UKLONI** → `serde_yml` ili prebaci na TOML/JSON | **DEPRECATED** — rf-slot-lab, rf-fluxmacro |
| `rand` | 0.8 | 0.10 | Breaking trait promene — rf-slot-lab, rf-offline, rf-fluxmacro |
| `rand_chacha` | 0.3 | 0.10 | Prati rand upgrade — rf-fluxmacro |
| `rubato` | 0.16 | **1.0.1** | Stabilna 1.0! API promene — rf-offline |
| `ndarray` | 0.16 | 0.17 | rf-ml, rf-spatial, rf-master, rf-pitch, rf-restore |
| `nalgebra` | 0.33 | 0.34 | rf-spatial, rf-pitch |
| `desktop_drop` (Flutter) | 0.5.0 | 0.7.0 | PAŽNJA: MainFlutterWindow.swift hack zavisi od plugin ponašanja |
| `file_picker` (Flutter) | 9.2.0 | 10.3.10 | Major bump — proveriti API migraciju |
| `syncfusion_flutter_pdf` (Flutter) | 28.2.4 | 32.2.9 | Syncfusion kvartalni bumps, obično kompatibilno |

### Faza 3 — Teški ali vredni

| Crate/Paket | Trenutno | Cilj | Napomena |
|-------------|----------|------|----------|
| `cpal` | 0.15 | **0.17.3** | Audio I/O core — rf-audio, rf-bridge, rf-engine. TESTIRATI LATENCY! |
| `wgpu` | 24.0 | **28.0.0** | GPU viz — rf-viz, rf-realtime. 4 major-a, wgpu brzo iterira |
| `wide` | 0.7 | **1.1.1** | SIMD — rf-spatial, rf-realtime. Major verzija |
| `glam` | 0.29 | **0.32.1** | Matematika — rf-viz |
| `candle-core/nn` | 0.8 | 0.9.2 | ML inference — rf-ml (optional) |
| `tract-onnx/core` | 0.21 | 0.23 | ML inference — rf-ml |
| `freezed` (Flutter) | 2.5.8 | **3.2.5** | Code gen major — zahteva `freezed_annotation` 2→3 i `build_runner` regeneraciju |

### Faza 4 — Čišćenje

- [ ] `objc` 0.2 → potpuna migracija na `objc2` 0.5+ u rf-plugin, rf-plugin-host
- [ ] `cocoa` 0.26 — deprecated u korist `objc2-app-kit`. Migrirati kad `objc2` ekosistem sazri.
- [ ] `block` 0.1 (rf-plugin-host) → `block2` (deo objc2 ekosistema)
- [ ] `rust-version` u workspace — 1.85 → 1.95 (prati nightly toolchain)
- [ ] Ukloni `wee_alloc` opciju iz rf-wasm (unmaintained od 2022)

### Aktuelno — NE DIRATI

| Crate | Verzija | Razlog |
|-------|---------|--------|
| serde | 1.0 | Stabilan |
| thiserror | 2.0 | Najnoviji major |
| parking_lot | 0.12 | Stabilan |
| rtrb | 0.3 | Stabilan |
| hound | 3.5 | Stabilan |
| symphonia | 0.5 | Stabilan |
| dasp | 0.11 | Stabilan |
| vst3 | 0.3 | Stabilan |
| anyhow | 1.0 | Stabilan |
| image | 0.25 | Stabilan |
| ffmpeg-next | 8.0 | Stabilan |
| mlua | 0.10 | Stabilan |
| provider (Flutter) | 6.1.5 | Aktuelan |
| flutter_animate | 4.5.2 | Aktuelan |
| flutter_rust_bridge | 2.11.1 | Aktuelan |
| shared_preferences | 2.5.4 | Aktuelan |
| web_socket_channel | 3.0.3 | Aktuelan |
