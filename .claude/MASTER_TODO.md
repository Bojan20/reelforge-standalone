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

- [x] **rf-connector tokio** — `tokio = { workspace = true, features = ["full"] }`
- [x] **rf-slot-lab rand** — `rand = { workspace = true }`
- [x] **rf-fluxmacro** — `serde_yml = { workspace = true }`, `rand_chacha = { workspace = true }`
- [x] **flutter_rust_bridge** — pubspec `^2.11.1` vs Cargo `2.11` — KOMPATIBILNO, bez akcije
- [x] **Dart SDK constraint** — već na `^3.11.0`
- [ ] **objc 0.2 + objc2 0.5 u rf-plugin** — nekompatibilni, migrirati na `objc2` (Faza 4)
- [ ] **Edition 2021 crate-ovi** — rf-ml, rf-spatial, rf-master, rf-pitch, rf-restore, rf-realtime, rf-plugin-host (Faza 4)

### Faza 1 — Brzi bezbedni wins — ✅ SVE ZAVRŠENO

Svi upgrade-ovi iz Faze 1 su već primenjeni u prethodnim sesijama:
- [x] rustfft 6.4, rayon 1.11, tokio 1.50, portable-atomic 1.13, wasm-bindgen 0.2.114
- [x] get_it ^9.2.1, archive ^4.0.9, media_kit ^1.2.6
- [x] lazy_static → LazyLock (100+ statics migrirano)
- [x] once_cell → OnceLock (2 upotrebe migrirane)

### Faza 2 — Srednji rizik

**Pre Faze 2:** Konsolidovati hardkodirane verzije (rf-connector, rf-slot-lab, rf-fluxmacro) na workspace deps.

**Rust crate-ovi:**

| Crate | Trenutno | Cilj | Crate-ovi | Scope |
|-------|----------|------|-----------|-------|
- [x] `serde_yaml` 0.9 → `serde_yml` 0.0.12 — rf-slot-lab, rf-fluxmacro (3 poziva migrirano)
- [x] `rand` 0.8 → 0.9 — `from_entropy()` → `from_os_rng()`, `gen()` → `random()`, `gen_range()` → `random_range()`, `thread_rng()` → `rng()`
- [x] `rand_chacha` 0.3 → 0.9 — dodat u workspace deps
- rubato 0.16 — BEZ PROMENE (audio thread sacred, 1.0 API rizičan)
- ndarray 0.16 — BEZ PROMENE (0.17 breaking)
- nalgebra 0.33 — BEZ PROMENE (0.34 zahteva ndarray 0.17)

**Flutter paketi:**

| Paket | Trenutno | Cilj | Napomena |
|-------|----------|------|----------|
| `desktop_drop` | 0.5.0 | 0.5.0 | BEZ PROMENE — MainFlutterWindow.swift hack zavisi od 0.5 ponašanja |
| `file_picker` | 9.2.0 | 9.2.0 | BEZ PROMENE — 10.x major bump, previše rizika za sada |
| `syncfusion_flutter_pdf` | 28.2.4 | 28.2.4 | BEZ PROMENE — Syncfusion major bumps zahtevaju license audit |

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
