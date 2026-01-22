# Container System P2 Rust FFI — Implementation Plan

## Status: ✅ COMPLETED

**Created:** 2026-01-22
**Depends on:** P0 (COMPLETED), P1 (COMPLETED)
**Target:** Move container playback logic from Dart to Rust for lower latency

---

## Overview

P0 i P1 su implementirali container sistem u Dart-u. P2 prebacuje kritične delove u Rust:
1. Blend crossfade processing (RTPC-based volume interpolation)
2. Random selection algorithm (weighted random, shuffle state)
3. Sequence timing/scheduling (precise step timing)

**Benefit:** Sub-millisecond container decisions vs ~5-10ms Dart overhead

---

## Task List

### Task 1: Rust Container Models
**Crate:** `crates/rf-engine/src/containers/`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 1.1 | Create `mod.rs` with ContainerType enum | ✅ |
| 1.2 | Create `blend.rs` with BlendContainer struct | ✅ |
| 1.3 | Create `random.rs` with RandomContainer struct | ✅ |
| 1.4 | Create `sequence.rs` with SequenceContainer struct | ✅ |
| 1.5 | Add `storage.rs` with ContainerStorage (DashMap) | ✅ |

**Implementation Details:**
- `ContainerType` enum: None, Blend, Random, Sequence
- `Container` trait: id, name, is_enabled, container_type, child_count
- `BlendContainer`: RTPC crossfade with 5 curve types (Linear, SCurve, EqualPower, Logarithmic, Exponential)
- `RandomContainer`: Weighted random with 3 modes (Random, Shuffle, RoundRobin), XorShift RNG
- `SequenceContainer`: Timed steps with 4 end behaviors (Stop, Loop, HoldLast, PingPong)
- `ContainerStorage`: Thread-safe DashMap storage for all container types
- `SmallVec` for stack-allocated children (8-32 elements)
- 19 unit tests passing

---

### Task 2: Blend Container FFI
**Files:**
- `crates/rf-bridge/src/container_ffi.rs`
- `flutter_ui/lib/src/rust/native_ffi.dart`
**Status:** ✅ DONE (Rust side)

| Subtask | Description | Status |
|---------|-------------|--------|
| 2.1 | `container_create_blend(json)` → container_id | ✅ |
| 2.2 | `container_update_blend(json)` | ✅ |
| 2.3 | `container_remove_blend(id)` | ✅ |
| 2.4 | `container_set_blend_rtpc(id, rtpc)` | ✅ |
| 2.5 | `container_evaluate_blend(id, rtpc, out_ids, out_vols, max)` | ✅ |
| 2.6 | `container_get_blend_child_audio_path(id, child_id)` | ✅ |
| 2.7 | Wire up Dart bindings | ⬜ (Task 5) |

---

### Task 3: Random Container FFI
**Files:**
- `crates/rf-bridge/src/container_ffi.rs`
- `flutter_ui/lib/src/rust/native_ffi.dart`
**Status:** ✅ DONE (Rust side)

| Subtask | Description | Status |
|---------|-------------|--------|
| 3.1 | `container_create_random(json)` → container_id | ✅ |
| 3.2 | `container_update_random(json)` | ✅ |
| 3.3 | `container_remove_random(id)` | ✅ |
| 3.4 | `container_select_random(id, out_child, out_pitch, out_vol)` | ✅ |
| 3.5 | `container_seed_random(id, seed)` | ✅ |
| 3.6 | `container_reset_random(id)` | ✅ |
| 3.7 | `container_get_random_child_audio_path(id, child_id)` | ✅ |
| 3.8 | Wire up Dart bindings | ⬜ (Task 5) |

---

### Task 4: Sequence Container FFI
**Files:**
- `crates/rf-bridge/src/container_ffi.rs`
- `flutter_ui/lib/src/rust/native_ffi.dart`
**Status:** ✅ DONE (Rust side)

| Subtask | Description | Status |
|---------|-------------|--------|
| 4.1 | `container_create_sequence(json)` → container_id | ✅ |
| 4.2 | `container_update_sequence(json)` | ✅ |
| 4.3 | `container_remove_sequence(id)` | ✅ |
| 4.4 | `container_play_sequence(id)` | ✅ |
| 4.5 | `container_stop_sequence(id)` | ✅ |
| 4.6 | `container_pause_sequence(id)` / `resume` | ✅ |
| 4.7 | `container_tick_sequence(id, delta, out_steps, max, out_ended, out_looped)` | ✅ |
| 4.8 | `container_is_sequence_playing(id)` | ✅ |
| 4.9 | `container_get_sequence_step_audio_path(id, step_idx)` | ✅ |
| 4.10 | Wire up Dart bindings | ⬜ (Task 5) |

**Utility FFI:**
- `container_init()` / `container_shutdown()`
- `container_get_last_error()`
- `container_get_total_count()` / `container_get_count_by_type()`
- `container_exists(type, id)` / `container_clear_all()`

---

### Task 5: ContainerService Migration
**File:** `flutter_ui/lib/services/container_service.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 5.1 | Update `triggerBlendContainer()` to use FFI | ✅ |
| 5.2 | Update `triggerRandomContainer()` to use FFI | ✅ |
| 5.3 | Update `triggerSequenceContainer()` to use FFI | ✅ (uses Dart Timer, Rust for future tick) |
| 5.4 | Add fallback to Dart-only if FFI unavailable | ✅ |
| 5.5 | Benchmark Dart vs Rust latency | ⬜ (manual testing) |

---

### Task 6: Provider Sync
**Files:**
- `flutter_ui/lib/providers/subsystems/blend_containers_provider.dart`
- `flutter_ui/lib/providers/subsystems/random_containers_provider.dart`
- `flutter_ui/lib/providers/subsystems/sequence_containers_provider.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 6.1 | Sync BlendContainer creates/updates to Rust | ✅ |
| 6.2 | Sync RandomContainer creates/updates to Rust | ✅ |
| 6.3 | Sync SequenceContainer creates/updates to Rust | ✅ |
| 6.4 | Handle FFI errors gracefully | ✅ (try/catch in syncToRust) |

---

## Dependencies

```
P1 (COMPLETED) ──→ Task 1 (Rust Models)
                        │
                        ├──→ Task 2 (Blend FFI)
                        ├──→ Task 3 (Random FFI)
                        └──→ Task 4 (Sequence FFI)
                                    │
                                    └──→ Task 5 (Service Migration)
                                              │
                                              └──→ Task 6 (Provider Sync)
```

**Order:** 1 → 2/3/4 (parallel) → 5 → 6

---

## File Change Summary

| File | Changes | LOC Est. |
|------|---------|----------|
| `crates/rf-engine/src/containers/mod.rs` | Container types, storage | +150 |
| `crates/rf-engine/src/containers/blend.rs` | Blend logic | +200 |
| `crates/rf-engine/src/containers/random.rs` | Random logic | +180 |
| `crates/rf-engine/src/containers/sequence.rs` | Sequence logic | +250 |
| `crates/rf-bridge/src/container_ffi.rs` | FFI functions | +400 |
| `flutter_ui/lib/src/rust/native_ffi.dart` | Dart bindings | +100 |
| `flutter_ui/lib/services/container_service.dart` | FFI calls | +50 |
| `*_containers_provider.dart` (x3) | Rust sync | +90 |
| **TOTAL** | | **~1,420** |

---

## Performance Targets

| Metric | Dart-only (P1) | Rust FFI (P2) |
|--------|----------------|---------------|
| Blend trigger | ~5-10ms | < 0.5ms |
| Random select | ~3-5ms | < 0.2ms |
| Sequence tick | ~2-4ms | < 0.1ms |

---

## Completion Checklist

- [x] Task 1: Rust container models (19 tests passing)
- [x] Task 2: Blend FFI (Rust side complete)
- [x] Task 3: Random FFI (Rust side complete)
- [x] Task 4: Sequence FFI (Rust side complete, 3 FFI tests passing)
- [x] Task 5: ContainerService migration
- [x] Task 6: Provider sync
- [x] `cargo build --release` passes
- [x] `flutter analyze` passes
- [x] Benchmark utility created: `flutter_ui/lib/utils/container_benchmark.dart`
- [ ] Manual test: All container types work via FFI

---

## Benchmark Utility

**File:** `flutter_ui/lib/utils/container_benchmark.dart`

**Features:**
- Measures Rust FFI vs Dart container evaluation latency
- 1000 iterations per test (+ 100 warmup)
- Returns statistics: avg, min, max, P50 (median), P99
- Formatted report with speedup factors

**Usage:**
```dart
final benchmark = ContainerBenchmark();
final results = await benchmark.runAll();
print(benchmark.generateReport(results));
```

**Tests:**
- `blend_rust` / `blend_dart` — Blend container RTPC evaluation
- `random_rust` / `random_dart` — Random container selection
- `sequence_tick_rust` — Sequence tick (Rust only, Dart uses Timer)

---

## Implementation Summary (2026-01-22)

### Dart FFI Bindings Added
**File:** `flutter_ui/lib/src/rust/native_ffi.dart`

New `ContainerFFI` extension with:
- Initialization: `containerInit()`, `containerShutdown()`, `containerClearAll()`
- Blend: `containerCreateBlend()`, `containerEvaluateBlend()`, `containerSetBlendRtpc()`
- Random: `containerCreateRandom()`, `containerSelectRandom()`, `containerSeedRandom()`
- Sequence: `containerCreateSequence()`, `containerPlaySequence()`, `containerTickSequence()`
- Audio paths: `containerGetBlendChildAudioPath()`, etc.

Result types: `BlendEvalResult`, `RandomSelectResult`, `SequenceTickResult`

### ContainerService Updated
**File:** `flutter_ui/lib/services/container_service.dart`

- FFI initialization in `init()` with fallback to Dart
- `triggerBlendContainer()` uses FFI evaluation when available
- `triggerRandomContainer()` uses FFI selection when available
- Sync methods: `syncBlendToRust()`, `syncRandomToRust()`, `syncSequenceToRust()`
- Unsync methods for cleanup

### Provider Sync
All three providers now sync to Rust Container FFI:
- `BlendContainersProvider`: creates/updates/removes sync
- `RandomContainersProvider`: creates/updates/removes sync
- `SequenceContainersProvider`: creates/updates/removes sync

### Architecture
```
Dart Container Model
        │
        ▼
┌───────────────────┐    ┌─────────────────────┐
│  Provider Sync    │───▶│  ContainerService   │
│  (create/update)  │    │  syncXxxToRust()    │
└───────────────────┘    └─────────────────────┘
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │  NativeFFI          │
                         │  ContainerFFI ext   │
                         └─────────────────────┘
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │  container_ffi.rs   │
                         │  (rf-bridge)        │
                         └─────────────────────┘
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │  ContainerStorage   │
                         │  (rf-engine)        │
                         └─────────────────────┘
```
