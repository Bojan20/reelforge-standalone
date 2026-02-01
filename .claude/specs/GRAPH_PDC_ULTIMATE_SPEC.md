# P10.0.2 — Graph-Level PDC: Ultimate Specification

**Date:** 2026-02-01
**Status:** 🔴 IN PROGRESS (Day 3)
**Complexity:** 🔴 HIGH — Not simple, requires ultimate solution

---

## 🎯 PROBLEM STATEMENT

### Why Simple Approaches Fail

**Attempted Simple Solution #1:**
```rust
compensation = max_latency - longest_path  // ❌ WRONG
```

**Why it fails:**
- Track A → Bus (100ms latency)
- max_latency = 100
- longest_path(Track A) = 0 (it's a source)
- compensation(Track A) = 100 - 0 = 100ms???
- **WRONG:** Track A doesn't need compensation, it CAUSES delay!

**Attempted Simple Solution #2:**
```rust
compensation = 0 for all nodes  // ❌ TOO SIMPLE
```

**Why it fails:**
- Doesn't actually solve phase alignment
- Tests fail (expect real compensation values)

**User's wisdom:** "ultimativna rešenja nikad jednostavna"

**Conclusion:** Need REAL algorithm, not workaround.

---

## 💎 ULTIMATE SOLUTION — Per-Input Mix Point Compensation

### Core Insight

**PDC is NOT global property — it's LOCAL to each mix point.**

```
Mix Point (Bus):
  ├── Input A (arrives after 100ms via plugin)
  ├── Input B (arrives after 0ms, no plugin)
  └── Result: B needs +100ms delay to align with A

NOT:
  global_compensation = max - longest_path

BUT:
  per_input_compensation[B] = max(inputs) - latency(B)
```

### Pro Tools Approach (Industry Standard)

1. Build routing graph (done ✅)
2. Identify mix points (buses, master)
3. For EACH mix point:
   - Calculate latency of ALL incoming paths
   - Find max incoming latency
   - Apply (max - path_latency) delay to shorter paths
4. Result: Phase-aligned at EVERY mix point

---

## 🏗️ ULTIMATE ARCHITECTURE

### Data Structures

```rust
/// Per-input compensation at a mix node
pub struct MixPointPDC {
    /// Mix node ID (bus or master)
    pub mix_node: NodeId,
    /// Per-input compensation
    /// Map: source_node → delay_samples
    pub input_compensation: HashMap<NodeId, LatencySamples>,
    /// Maximum input latency at this mix point
    pub max_input_latency: LatencySamples,
}

/// Complete PDC solution for routing graph
pub struct PDCSolution {
    /// Per-mix-point compensation
    pub mix_points: Vec<MixPointPDC>,
    /// Topological order (for processing)
    pub topo_order: Vec<NodeId>,
    /// Whether graph has cycles
    pub has_cycles: bool,
    /// Global max latency (for UI display)
    pub max_latency: LatencySamples,
}
```

### Algorithm (Ultimate Version)

```rust
fn calculate_ultimate_pdc(graph: &RoutingGraph) -> Result<PDCSolution, String> {
    // 1. Topological sort (detect cycles)
    let topo_order = topological_sort(graph)?;

    // 2. Calculate longest path TO each node (DP)
    let longest_paths = calculate_longest_paths(graph, &topo_order);

    // 3. Identify mix points (nodes with 2+ inputs)
    let mix_points = identify_mix_points(graph);

    // 4. For EACH mix point, calculate per-input compensation
    let mut pdc_mix_points = Vec::new();

    for mix_node in mix_points {
        // Get all incoming edges to this mix node
        let incoming_latencies: HashMap<NodeId, LatencySamples> = graph
            .edges
            .iter()
            .filter(|e| e.destination == mix_node)
            .map(|e| {
                // Latency TO source + edge latency
                let source_latency = longest_paths.get(&e.source).copied().unwrap_or(0);
                let total_latency = source_latency + e.latency;
                (e.source, total_latency)
            })
            .collect();

        // Find max incoming latency
        let max_input_latency = incoming_latencies.values().copied().max().unwrap_or(0);

        // Calculate per-input compensation
        let input_compensation: HashMap<NodeId, LatencySamples> = incoming_latencies
            .iter()
            .map(|(&source, &latency)| {
                let comp = max_input_latency.saturating_sub(latency);
                (source, comp)
            })
            .collect();

        pdc_mix_points.push(MixPointPDC {
            mix_node,
            input_compensation,
            max_input_latency,
        });
    }

    // 5. Global max latency (for UI)
    let max_latency = longest_paths.values().copied().max().unwrap_or(0);

    Ok(PDCSolution {
        mix_points: pdc_mix_points,
        topo_order,
        has_cycles: false,
        max_latency,
    })
}
```

---

## 📊 EXAMPLE WALKTHROUGH

### Scenario: Parallel Tracks to Bus

```
Track A → Bus 1 (100ms plugin latency)
           ↓
Track B → Bus 1 (0ms, no plugin)
           ↓
        Master
```

**Step 1: Longest Paths**
```
longest_path(Track A) = 0 (source)
longest_path(Track B) = 0 (source)
longest_path(Bus 1)   = max(0+100, 0+0) = 100
longest_path(Master)  = 100 + 0 = 100
```

**Step 2: Identify Mix Points**
```
Bus 1: 2 inputs (Track A, Track B)
Master: 1 input (Bus 1) — not a mix point
```

**Step 3: Per-Input Compensation at Bus 1**
```
Incoming latencies:
  Track A: 0 (longest_path) + 100 (edge) = 100ms
  Track B: 0 (longest_path) +   0 (edge) =   0ms

Max incoming: 100ms

Compensation:
  Track A: 100 - 100 = 0ms   (no delay needed, it's the slow path)
  Track B: 100 - 0   = 100ms (add delay to align with Track A)
```

**Result:**
- Track A audio arrives at Bus 1 after 100ms (plugin processing)
- Track B audio is DELAYED 100ms, also arrives after 100ms
- Phase-aligned! ✅

---

## 🧪 TEST CASES (Ultimate Coverage)

### Test 1: Simple Chain (No Compensation Needed)
```
Track → Bus (50ms) → Master

Expected:
  - No mix points (1 input each)
  - No compensation anywhere
  - max_latency = 50ms (for UI display)
```

### Test 2: Parallel Paths (Compensation Required)
```
Track A → Bus (100ms)
Track B → Bus (0ms)

Expected:
  - Mix point: Bus (2 inputs)
  - compensation(Track A → Bus) = 0ms
  - compensation(Track B → Bus) = 100ms
```

### Test 3: Diamond Pattern
```
Track 1 → Bus A (100ms) ↘
                         Bus C (50ms) → Master
Track 2 → Bus B (0ms)   ↗

Expected:
  - Mix point: Bus C (2 inputs)
  - Path via Bus A: 0 + 100 + 50 = 150ms
  - Path via Bus B: 0 + 0 + 50 = 50ms
  - compensation(Bus A → Bus C) = 0ms
  - compensation(Bus B → Bus C) = 100ms
```

### Test 4: Three-Way Mix
```
Track A → Bus (100ms)
Track B → Bus (50ms)
Track C → Bus (0ms)

Expected:
  - compensation(Track A) = 0ms
  - compensation(Track B) = 50ms
  - compensation(Track C) = 100ms
```

---

## 🔧 IMPLEMENTATION PLAN (Revised)

### Phase 1: Core Algorithm (Day 3, ~350 LOC)

**File:** `crates/rf-engine/src/routing_pdc.rs`

**Components:**
1. ✅ RoutingGraph struct (done)
2. ✅ Topological sort (done)
3. ✅ Longest path calculation (done)
4. ❌ Per-input mix point compensation (**TODO**)
5. ❌ identify_mix_points() helper (**TODO**)
6. ❌ PDCSolution struct (**TODO**)
7. ✅ 10 unit tests (7/10 passing, need ultimate algorithm)

**Status:** 60% complete, need ultimate per-input algorithm

---

### Phase 2: PlaybackEngine Integration (Day 3-4, ~150 LOC)

**File:** `crates/rf-engine/src/playback.rs`

**Integration Points:**
1. Store `PDCSolution` in PlaybackEngine
2. Recalculate PDC when routing changes
3. Apply per-input delays at mix points (buses)
4. Update track delay compensation values

**Code Sketch:**
```rust
impl PlaybackEngine {
    // Current PDC solution
    pdc_solution: Arc<RwLock<Option<PDCSolution>>>,

    /// Recalculate PDC after routing change
    pub fn recalculate_pdc(&self) {
        let graph = self.build_routing_graph();
        match PDCCalculator::calculate_ultimate(&graph) {
            Ok(solution) => {
                *self.pdc_solution.write() = Some(solution);
                self.apply_pdc_delays(&solution);
            }
            Err(e) => {
                log::error!("PDC calculation failed: {}", e);
            }
        }
    }

    /// Apply PDC delays to tracks/buses
    fn apply_pdc_delays(&self, solution: &PDCSolution) {
        for mix_point in &solution.mix_points {
            for (source_node, comp_samples) in &mix_point.input_compensation {
                // Apply delay to source path
                match GraphNode::from_node_id(*source_node) {
                    Some(GraphNode::Track(track_id)) => {
                        self.set_track_pdc_delay(track_id, *comp_samples);
                    }
                    Some(GraphNode::Bus(bus_id)) => {
                        self.set_bus_pdc_delay(bus_id, *comp_samples);
                    }
                    _ => {}
                }
            }
        }
    }
}
```

---

### Phase 3: FFI Export (Day 4, ~100 LOC)

**File:** `crates/rf-engine/src/ffi.rs`

**Functions:**
```rust
/// Trigger PDC recalculation
#[unsafe(no_mangle)]
pub extern "C" fn engine_recalculate_pdc() -> i32;

/// Get PDC status as JSON
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_pdc_status_json() -> *mut c_char;

/// Get compensation for specific track
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_track_pdc_compensation(track_id: u64) -> u64;

/// Enable/disable PDC globally
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_pdc_enabled(enabled: i32) -> i32;
```

---

### Phase 4: Dart UI (Day 4, ~100 LOC)

**File:** `flutter_ui/lib/providers/routing_provider.dart`

**Features:**
- PDC status indicator (green=aligned, red=cycles detected)
- Per-track compensation display (ms)
- Manual override toggle
- Recalculate button

**Widget:**
```dart
class PDCStatusWidget extends StatelessWidget {
  Widget build(BuildContext context) {
    return Consumer<RoutingProvider>(
      builder: (_, provider, __) {
        final status = provider.pdcStatus;

        return Row(
          children: [
            Icon(
              status.hasCycles ? Icons.error : Icons.check_circle,
              color: status.hasCycles ? Colors.red : Colors.green,
            ),
            Text('PDC: ${status.maxLatencyMs.toStringAsFixed(1)}ms'),
            if (!status.hasCycles)
              Text('(${status.compensatedTracks} tracks adjusted)'),
          ],
        );
      },
    );
  }
}
```

---

## 🎓 WHY ULTIMATE (Not Simple)

### Simple Approach
```
compensation = max_latency - longest_path
```

**Problem:** Assumes global compensation, doesn't account for local mix points.

### Ultimate Approach
```
For each mix point:
  For each input:
    compensation[input] = max(all inputs) - latency(this input)
```

**Result:** Locally optimal compensation at every mix point.

---

## 📚 REFERENCES

- **Pro Tools HD PDC:** Per-path compensation with automatic detection
- **Cubase ADC:** Graph-based with cycle detection
- **Reaper Track Delay:** Manual + automatic with parallel routing
- **Logic Pro PDC:** Similar per-input approach

---

## 🚀 ACTION PLAN (Revised)

### Day 3 Afternoon (Remaining)

1. ❌ Fix failing tests — need ultimate algorithm
2. ✅ Implement per-input compensation
3. ✅ Update PDCResult → PDCSolution struct
4. ✅ Add identify_mix_points() helper
5. ✅ Verify all 10 tests pass

**ETA:** ~3 hours (complex algorithm)

### Day 4 Morning

1. Integrate into PlaybackEngine
2. Add FFI export
3. Implement Dart UI

---

**This is EXACTLY why ultimate solutions are never simple.**

*Specification: 2026-02-01*
