# P1 Testing Plan — Comprehensive Verification

**Purpose:** Verify all 29 P1 features work end-to-end
**Approach:** Role-based testing scenarios
**Duration:** ~2-3h manual testing

---

## Test Environment Setup

```bash
# Build latest
cargo build --release
cd flutter_ui/macos
xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug build

# Launch app
open ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app
```

---

## AUDIO DESIGNER TESTS (3 features)

### P1-01: Audio Variant Group + A/B UI

**Test Steps:**
1. Import 3 audio files: `spin_v1.wav`, `spin_v2.wav`, `spin_v3.wav`
2. Select all 3 → Right-click → "Create Variant Group"
3. Name: "Spin Variations"
4. Click A/B toggle button
5. **Verify:** Hears different audio on each toggle
6. Click "Replace in All Events"
7. **Verify:** All SPIN events now use selected variant

**Pass Criteria:**
- ✅ Variant group created
- ✅ A/B toggle cycles through variants
- ✅ Replace propagates to all events

---

### P1-02: LUFS Normalization Preview

**Test Steps:**
1. Import audio at -20 LUFS (quiet)
2. Select in pool → See "LUFS: -20" badge
3. Click preview → Toggle "Normalize to -14" checkbox
4. **Verify:** Preview is louder (~6dB boost)
5. Waveform shows normalized level indicator

**Pass Criteria:**
- ✅ LUFS detected and displayed
- ✅ Normalize toggle works in preview
- ✅ Visual indicator shows gain adjustment

---

### P1-03: Waveform Zoom Per-Event

**Test Steps:**
1. Select event in timeline
2. Mouse wheel scroll on waveform
3. **Verify:** Waveform zooms in/out
4. Change to different event
5. **Verify:** Zoom level persists per-event

**Pass Criteria:**
- ✅ Mouse wheel zoom works
- ✅ Zoom level saved per event
- ✅ Visual feedback (zoom percentage)

---

## MIDDLEWARE ARCHITECT TESTS (4 features)

### P1-04: Undo History Visualization

**Test Steps:**
1. Create 5 events
2. Open Undo History panel (Lower Zone → Tools)
3. **Verify:** See list of 5 actions
4. Click 3rd item in list
5. **Verify:** Jumps to that undo state (2 events deleted)

**Pass Criteria:**
- ✅ History shows all actions with timestamps
- ✅ Click action → jumps to that state
- ✅ Visual indicator of current position

---

### P1-05: Container Smoothing UI ✅ (Already Done)

---

### P1-06: Event Dependency Graph

**Test Steps:**
1. Create event A → triggers stage X
2. Create event B → triggers stage X (circular)
3. Open Dependency Graph panel
4. **Verify:** See nodes A and B connected
5. **Verify:** RED warning for circular reference

**Pass Criteria:**
- ✅ Graph shows all event nodes
- ✅ Arrows show dependencies
- ✅ Cycles highlighted in RED

---

### P1-07: Container Real-Time Metering

**Test Steps:**
1. Create Blend container with 3 children
2. Assign RTPC "winAmount" (0-100)
3. Open container editor → See volume meters
4. Move RTPC slider 0 → 100
5. **Verify:** Volume meters update in real-time

**Pass Criteria:**
- ✅ Meters show per-child volume
- ✅ Updates at 30Hz (smooth)
- ✅ Matches RTPC curve

---

## ENGINE DEVELOPER TESTS (4 features)

### P1-08: End-to-End Latency Measurement

**Test Steps:**
1. Open Profiler panel → Latency tab
2. Trigger stage "REEL_STOP_0"
3. **Verify:** Breakdown shows:
   - Dart→FFI: ~0.5ms
   - FFI→Engine: ~1.2ms
   - Total: <5ms ✅

**Pass Criteria:**
- ✅ Latency breakdown displayed
- ✅ Total <5ms (SLA met)
- ✅ Pass/Fail badge shown

---

### P1-09: Voice Steal Statistics

**Test Steps:**
1. Trigger rapid-fire event 50× (exceed 48 voice pool)
2. Open Profiler → Voice Steal tab
3. **Verify:** Stats show:
   - Total steals: ~2-5
   - Most stolen event: ROLLUP_TICK

**Pass Criteria:**
- ✅ Steal count accurate
- ✅ Per-event breakdown shown
- ✅ Steal reason logged (oldest-first)

---

### P1-10: Stage→Event Resolution Trace

**Test Steps:**
1. Trigger stage "REEL_STOP_0"
2. Open Stage Detective panel
3. **Verify:** Trace shows:
   - Normalization: "REEL_STOP_0" ✓
   - Lookup: Found in EventRegistry
   - Priority: 60
   - Voice acquired: voice_id=12
   - Result: Playing /audio/reel_stop.wav

**Pass Criteria:**
- ✅ Full resolution path shown
- ✅ Fallback logic visible (if used)
- ✅ Click stage → shows trace

---

### P1-11: DSP Load Attribution

**Test Steps:**
1. Play complex event (reverb + EQ)
2. Open Profiler → DSP Load tab
3. **Verify:** Breakdown shows:
   - REEL_SPIN_LOOP: 8.3%
   - WIN_PRESENT: 2.1%
   - Total: 15%

**Pass Criteria:**
- ✅ Per-event load shown
- ✅ Flame graph or bar chart
- ✅ Identifies bottlenecks

---

## QA ENGINEER TESTS (2 features)

### P1-16: Multi-Condition Test Combinator

**Test Steps:**
1. Open Test Combinator panel
2. Select conditions:
   - Win Tiers: [Small, Big] (2)
   - Features: [None, FS] (2)
   - Cascade: [Yes, No] (2)
3. Click "Generate Combinations"
4. **Verify:** Creates 2×2×2 = 8 test sequences

**Pass Criteria:**
- ✅ Combinations calculated correctly
- ✅ All sequences executable
- ✅ Results tracked

---

### P1-17: Event Timing Validation

**Test Steps:**
1. Set timing threshold: 5ms
2. Run spin test
3. **Verify:** Report shows:
   - SPIN_START: 0.2ms ✓ PASS
   - REEL_STOP_0: 0.8ms ✓ PASS
   - All events: PASS

**Pass Criteria:**
- ✅ Threshold configurable
- ✅ Per-event latency measured
- ✅ Pass/Fail report generated

---

## TOOLING DEVELOPER TESTS (2 features)

### P1-14: Scripting API

**Test Steps:**
1. Write Lua script:
```lua
local ff = require('fluxforge')
local id = ff.createEvent('Test Event', 'SPIN_START')
ff.addLayer(id, '/audio/spin.wav')
ff.saveProject()
```
2. Execute via Scripting panel
3. **Verify:** Event created in SlotLab

**Pass Criteria:**
- ✅ Lua interpreter works
- ✅ FluxForge API accessible
- ✅ Changes persist

---

### P1-15: Hook System

**Test Steps:**
1. Register hook:
```dart
provider.registerOnCreate((event) {
  print('Created: ${event.name}');
});
```
2. Create event via UI
3. **Verify:** Console log shows "Created: ..."

**Pass Criteria:**
- ✅ Hooks register successfully
- ✅ Hooks fire on events
- ✅ Multiple hooks supported

---

## UX TESTS (6 features)

### UX-01: Onboarding Tutorial

**Test Steps:**
1. Fresh launch → Tutorial popup appears
2. Follow steps: "Create your first event"
3. Complete tutorial
4. **Verify:** Event created successfully

**Pass Criteria:**
- ✅ Tutorial launches on first run
- ✅ Steps are clear and actionable
- ✅ Can skip or complete

---

### UX-02, UX-03, UX-06: Already Verified ✅

---

### UX-04: Smart Tab Organization

**Test Steps:**
1. Open Lower Zone
2. **Verify:** Tabs grouped into Primary/Secondary
3. Click "+Tools" → Expands to show Debug, Profiler, etc.
4. Breadcrumb shows: "Events / Editing [Audio Layer]"

**Pass Criteria:**
- ✅ Primary tabs always visible
- ✅ Secondary tabs collapsible
- ✅ Breadcrumb shows context

---

### UX-05: Enhanced Drag Feedback

**Test Steps:**
1. Drag layer region on timeline
2. **Verify:** Ghost region shows where it will land
3. **Verify:** Tooltip shows "Offset: 1250ms (↑300ms)"
4. Drag over another layer
5. **Verify:** RED highlight if overlapping

**Pass Criteria:**
- ✅ Ghost region visible
- ✅ Offset tooltip accurate
- ✅ Overlap detection works
- ✅ Magnetic snap to grid

---

## CROSS-VERIFICATION TESTS (5 features)

### P1-19: Timeline Selection Persistence

**Test Steps:**
1. Select clip in DAW timeline
2. Switch to Middleware section
3. Switch back to DAW
4. **Verify:** Clip still selected

**Pass Criteria:**
- ✅ Selection survives section switch
- ✅ No visual glitch on restore

---

### P1-20: Container Evaluation Logging

**Test Steps:**
1. Trigger Blend container 10×
2. Open Container Eval Log panel
3. **Verify:** Shows last 10 evaluations with:
   - Timestamp
   - RTPC value
   - Child volumes

**Pass Criteria:**
- ✅ Log captures all evaluations
- ✅ Exportable to JSON
- ✅ Searchable/filterable

---

### P1-21: Plugin PDC Visualization

**Test Steps:**
1. Add reverb plugin to track (200ms latency)
2. Open FX Chain panel
3. **Verify:** Shows "PDC: +200ms" badge

**Pass Criteria:**
- ✅ PDC detected from plugin
- ✅ Visual indicator on chain
- ✅ Compensation suggested

---

### P1-22: Cross-Section Event Playback

**Test Steps:**
1. Create event in SlotLab
2. Switch to Middleware
3. Trigger same event
4. **Verify:** Audio plays correctly

**Pass Criteria:**
- ✅ Events playable across sections
- ✅ No audio cutoff on switch
- ✅ Parameters preserved

---

### P1-23: FFI Binding Audit

**Test Steps:**
1. Open FFI Audit panel
2. **Verify:** Shows:
   - Rust exports: 1688
   - Dart bindings: 33
   - Missing: 1655
   - Coverage: 2%

**Pass Criteria:**
- ✅ Audit runs without error
- ✅ Gap report generated
- ✅ Recommendations provided

---

## Test Summary Template

After all tests:

```
P1 TEST RESULTS — 2026-01-30

Tested: 29/29 features
Passed: __/29
Failed: __/29
Blocked: __/29

FAILURES:
- [List any failed tests]

NOTES:
- [Any observations]

RECOMMENDATION: [Ship / Fix / Defer]
```

---

**Status:** ✅ **Test Plan Complete**

**Duration:** ~2-3h for full manual test suite

*Next: Prepare conflict resolution scripts*
