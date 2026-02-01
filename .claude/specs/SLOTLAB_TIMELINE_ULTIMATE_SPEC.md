# SlotLab Timeline — Ultimate DAW-Style Specification

**Created:** 2026-02-01
**Authority:** Chief Audio Architect + Lead DSP Engineer + UI/UX Expert
**Scope:** Professional waveform timeline for SlotLab section

---

## 🎯 VISION

**Transform SlotLab Timeline from basic track view into industry-standard DAW timeline:**

- **Waveform-first** — Audio visualization, not just regions
- **Multi-track editing** — Professional arrangement workflow
- **Stage-aware** — SlotLab-specific stage markers and automation
- **Real-time metering** — Bus levels, LUFS, peak detection
- **Zoom/Pan mastery** — Instant navigation like Pro Tools
- **Audio-visual sync** — Perfect alignment with slot preview

**Benchmark:** Pro Tools 2024 + Logic Pro X + Cubase 14

---

## 🏗️ ARCHITECTURE — 7-Layer Timeline System

```
┌─────────────────────────────────────────────────────────────┐
│ LAYER 7: Transport & Playhead (Timeline Playback Control)  │
├─────────────────────────────────────────────────────────────┤
│ LAYER 6: Ruler (Time Grid, Markers, Loop Region)           │
├─────────────────────────────────────────────────────────────┤
│ LAYER 5: Master Track (Bus Metering, LUFS, Automation)     │
├─────────────────────────────────────────────────────────────┤
│ LAYER 4: Audio Tracks (Waveforms, Regions, Fades)          │
├─────────────────────────────────────────────────────────────┤
│ LAYER 3: Stage Markers (Visual Stage Boundaries)           │
├─────────────────────────────────────────────────────────────┤
│ LAYER 2: Automation Lanes (Volume, Pan, RTPC)              │
├─────────────────────────────────────────────────────────────┤
│ LAYER 1: Grid & Snapping (Beat Grid, Millisecond Grid)     │
└─────────────────────────────────────────────────────────────┘
```

---

## 📐 LAYER SPECIFICATIONS

### LAYER 1: Grid & Snapping System

**Purpose:** Precision editing with snap-to-grid

| Feature | Implementation | Shortcut |
|---------|----------------|----------|
| Beat Grid | 4/4, 3/4, 5/4 time signatures | `G` toggle |
| Millisecond Grid | 10ms, 50ms, 100ms, 250ms, 500ms | `Shift+G` cycle |
| Frame Grid | 24fps, 30fps, 60fps (video sync) | `Cmd+G` |
| Free Snap | No grid, pixel-level precision | `Cmd+Shift+G` |
| Snap Strength | Magnetic pull radius (5-50px) | Preferences |

**Visual:**
- Grid lines: 10% opacity when snap OFF, 20% when ON
- Snap indicator: Orange highlight when region approaches grid line
- Grid density auto-adjusts with zoom (more lines when zoomed in)

**Technical:**
```dart
class TimelineGridSystem {
  GridMode mode;              // beat, millisecond, frame, free
  double snapStrength;        // 5-50 pixels
  TimeSignature timeSignature; // 4/4, 3/4, etc.

  double snapToGrid(double position, double pixelsPerSecond);
  List<GridLine> generateGridLines(double zoom, double duration);
}
```

---

### LAYER 2: Automation Lanes

**Purpose:** Parameter automation (volume, pan, RTPC)

| Lane Type | Parameters | Display |
|-----------|------------|---------|
| Volume | 0.0-2.0 (−∞ to +6dB) | Orange curve |
| Pan | −1.0 to +1.0 (L/R) | Cyan curve |
| RTPC | Custom range per RTPC | Color-coded |
| Stage Trigger | Boolean on/off | Step graph |

**Interaction:**
- Click to add automation point
- Drag point to adjust value
- Double-click to delete point
- Right-click → context menu (delete, smooth, reset)
- Bezier curve interpolation between points

**Visual:**
- Automation lane: 60px height when expanded
- Curve rendered with CustomPainter
- Value labels on hover
- Color-coded by parameter type

**Technical:**
```dart
class AutomationLane {
  final String parameterId;   // 'volume', 'pan', 'rtpc_winAmount'
  final List<AutomationPoint> points;
  final Color curveColor;
  final double minValue, maxValue;

  double getValueAt(double timeSeconds);
  void addPoint(double time, double value);
  void smoothBetween(int startIndex, int endIndex);
}

class AutomationPoint {
  double time;
  double value;
  CurveType interpolation; // linear, bezier, step
}
```

---

### LAYER 3: Stage Markers

**Purpose:** Visualize SlotLab stage boundaries

| Marker Type | Color | Position |
|-------------|-------|----------|
| SPIN_START | Green | Top of timeline |
| REEL_STOP_0..4 | Blue | Per-reel markers |
| WIN_PRESENT | Gold | Win tier boundaries |
| BIG_WIN_INTRO | Orange | Major celebration |
| FEATURE_ENTER | Purple | Feature triggers |
| Custom | Gray | User-defined |

**Visual:**
- Vertical line from top to bottom
- Stage name label at top (rotated 90° when zoomed out)
- Color-coded border (2px width)
- Hover → tooltip with stage metadata

**Interaction:**
- Click marker → jump playhead to stage
- Right-click → edit marker properties
- Drag to reposition (if custom marker)
- Double-click → toggle stage mute

**Technical:**
```dart
class StageMarker {
  final String stageId;       // 'REEL_STOP_0'
  final double timeSeconds;
  final Color color;
  final String label;
  final bool isMuted;

  static StageMarker fromStageEvent(StageEvent event);
}
```

---

### LAYER 4: Audio Tracks (Core — Waveform Rendering)

**Purpose:** Professional audio track display

#### 4A: Waveform Rendering

**Multi-LOD System (Real Rust FFI, NO placeholders):**

| Zoom Level | Samples/Pixel | LOD | Rendering |
|------------|---------------|-----|-----------|
| < 1x | 4096 | LOD 0 | Min/Max peaks |
| 1x - 4x | 1024 | LOD 1 | RMS + peaks |
| 4x - 16x | 256 | LOD 2 | Half-wave |
| > 16x | 64 | LOD 3 | Full samples |

**Visual Styles:**
```dart
enum WaveformStyle {
  peaks,        // Min/Max peaks (default)
  rms,          // RMS envelope
  halfWave,     // Top half only (like Pro Tools)
  filled,       // Solid fill
  outline,      // Outline only
}
```

**Color Coding:**
```dart
class WaveformColors {
  Color normal;     // #4A9EFF (FluxForge blue)
  Color selected;   // #FF9040 (FluxForge orange)
  Color muted;      // #808080 (gray)
  Color clipping;   // #FF4060 (red, > 0dBFS)
  Color lowLevel;   // #40C8FF (cyan, < −40dBFS)
}
```

**Technical:**
```dart
class WaveformRenderer {
  final Uint8List waveformData;  // From Rust FFI
  final int sampleRate;
  final int channels;

  void paint(Canvas canvas, Size size, {
    required double startTime,
    required double endTime,
    required WaveformStyle style,
    required WaveformColors colors,
  });

  // LOD selection based on zoom
  int selectLOD(double pixelsPerSecond);
}
```

#### 4B: Track Header

**Fixed-width left panel (120px):**

| Element | Size | Content |
|---------|------|---------|
| Track Name | 80px | Editable text field |
| Mute/Solo | 20px | M/S buttons |
| Record Arm | 20px | R button |
| Volume Fader | 60px | Vertical mini-fader |
| Pan Knob | 40px | Mini rotary knob |
| Bus Routing | 60px | Dropdown (SFX/Music/etc.) |
| Track Color | 20px | Color picker strip |

**Visual:**
- Background: #1A1A22
- Border: 1px #FFFFFF10
- Selected track: Orange left border (4px)

#### 4C: Region Editing

**Region Manipulations:**

| Action | Shortcut | Behavior |
|--------|----------|----------|
| Move | Drag | Snap to grid if enabled |
| Trim Start | Drag left edge | Non-destructive |
| Trim End | Drag right edge | Non-destructive |
| Fade In | Drag top-left corner | 0-2000ms |
| Fade Out | Drag top-right corner | 0-2000ms |
| Split | `S` | Split at playhead |
| Delete | `Delete` | Remove region |
| Duplicate | `Cmd+D` | Copy region |
| Normalize | `Cmd+N` | Peak normalization |

**Fade Curves:**
- Linear
- Exponential
- Logarithmic
- S-Curve
- Equal Power (default)

**Technical:**
```dart
class AudioRegion {
  String audioPath;
  double startTime;           // Timeline position
  double duration;            // Visible duration
  double trimStart;           // Offset into audio file
  double trimEnd;             // Trim from end
  double fadeInMs;
  double fadeOutMs;
  FadeCurve fadeInCurve;
  FadeCurve fadeOutCurve;
  double volume;              // 0.0-2.0
  double pan;                 // −1.0 to +1.0
  Color regionColor;
}
```

---

### LAYER 5: Master Track

**Purpose:** Overall mix monitoring

| Display | Position | Content |
|---------|----------|---------|
| LUFS Meter | Top 40px | Integrated/Short-term/Momentary |
| True Peak | Below LUFS | dBTP with 8x oversampling |
| L/R Meters | Center 80px | Peak + RMS bars |
| Phase Correlation | Bottom 40px | Stereo phase scope |

**Visual:**
- Horizontal meters (full timeline width)
- Color gradient: Green → Yellow → Red
- Clip indicators (hold 2 seconds)
- Numeric readouts on hover

**Technical:**
```dart
class MasterTrackMetering {
  Stream<LUFSData> lufsStream;
  Stream<PeakData> peakStream;
  Stream<double> correlationStream;

  void paintMeters(Canvas canvas, Size size);
}
```

---

### LAYER 6: Ruler

**Purpose:** Time reference and navigation

| Zone | Height | Content |
|------|--------|---------|
| Main Ruler | 30px | Time units (ms, seconds, beats) |
| Loop Region | 20px | Loop start/end handles |
| Markers Row | 15px | Stage markers (compact) |

**Time Display Modes:**
- Milliseconds: `1000ms`, `2000ms`
- Seconds: `1.0s`, `2.5s`
- Beats: `1.1.1`, `2.1.1` (bar.beat.tick)
- Timecode: `00:00:01:00` (SMPTE)

**Visual:**
- Major ticks: Every second or beat
- Minor ticks: Every 100ms or 1/4 beat
- Numbers: 10px font, white 70% opacity

**Technical:**
```dart
class TimelineRuler {
  TimeDisplayMode mode;
  double pixelsPerSecond;

  void paint(Canvas canvas, Size size, {
    required double startTime,
    required double endTime,
  });
}
```

---

### LAYER 7: Transport & Playhead

**Purpose:** Playback control and position indicator

| Element | Visual | Interaction |
|---------|--------|-------------|
| Playhead | Red vertical line (2px) | Follows playback |
| Playhead Handle | Triangle at top | Drag to scrub |
| Play/Pause | Green button | Space bar |
| Stop | Red button | `0` key |
| Loop Toggle | Orange button | `L` key |
| Record | Red dot | `R` key |

**Playhead Behavior:**
- Scrubbing: Drag handle → audio preview
- Auto-scroll: Follow playhead when playing
- Manual scroll: Click ruler to jump

**Technical:**
```dart
class TimelineTransport {
  double playheadPosition;    // Current time in seconds
  bool isPlaying;
  bool isLooping;
  bool isRecording;

  void play();
  void pause();
  void stop();
  void seek(double timeSeconds);
  void toggleLoop();
}
```

---

## 🎨 VISUAL DESIGN — Pro Tools Inspired

### Color Palette

```dart
class TimelineColors {
  // Background layers
  static const background = Color(0xFF0A0A0C);
  static const trackBg = Color(0xFF121216);
  static const selectedTrack = Color(0xFF1A1A20);

  // Waveforms
  static const waveformNormal = Color(0xFF4A9EFF);
  static const waveformSelected = Color(0xFF FF9040);
  static const waveformMuted = Color(0xFF808080);

  // UI Elements
  static const playhead = Color(0xFFFF4060);
  static const loopRegion = Color(0xFFFF9040);
  static const gridLines = Color(0xFFFFFFFF); // 10% opacity
  static const markers = Color(0xFF40FF90);

  // Metering
  static const meterGreen = Color(0xFF40FF90);
  static const meterYellow = Color(0xFFFFFF40);
  static const meterRed = Color(0xFFFF4060);
}
```

### Typography

```dart
class TimelineTypography {
  static const trackName = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const rulerTime = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: Color(0xFFFFFFFFB3), // 70% opacity
  );

  static const automation = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w400,
    color: Color(0xFFFFFFFF99), // 60% opacity
  );
}
```

---

## ⌨️ KEYBOARD SHORTCUTS — Pro Tools Standard

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Navigation** | | |
| Zoom In | `Cmd/Ctrl + =` | Horizontal zoom in |
| Zoom Out | `Cmd/Ctrl + -` | Horizontal zoom out |
| Zoom to Fit | `Cmd/Ctrl + 0` | Fit all tracks |
| Zoom to Selection | `Cmd/Ctrl + E` | Zoom to selected region |
| Scroll Left | `←` | Pan timeline left |
| Scroll Right | `→` | Pan timeline right |
| **Playback** | | |
| Play/Pause | `Space` | Toggle playback |
| Stop | `0` (numpad) | Stop and return to start |
| Loop Toggle | `L` | Enable/disable loop |
| Record | `R` | Start/stop recording |
| **Editing** | | |
| Split | `S` | Split region at playhead |
| Delete | `Delete` | Remove selected regions |
| Duplicate | `Cmd/Ctrl + D` | Duplicate regions |
| Fade In | `Cmd/Ctrl + F` | Add fade in |
| Fade Out | `Cmd/Ctrl + Shift + F` | Add fade out |
| Normalize | `Cmd/Ctrl + N` | Peak normalize |
| **Selection** | | |
| Select All | `Cmd/Ctrl + A` | Select all regions |
| Deselect All | `Cmd/Ctrl + Shift + A` | Clear selection |
| Select Next | `Tab` | Next region |
| Select Previous | `Shift + Tab` | Previous region |
| **Tracks** | | |
| New Track | `Cmd/Ctrl + T` | Add audio track |
| Delete Track | `Cmd/Ctrl + Shift + T` | Remove track |
| Mute Track | `M` | Toggle mute |
| Solo Track | `S` | Toggle solo |
| Record Arm | `R` | Arm for recording |
| **Grid & Snap** | | |
| Toggle Snap | `G` | Grid snap on/off |
| Cycle Grid | `Shift + G` | Beat/ms/frame/free |
| **Markers** | | |
| Add Marker | `;` | Create marker at playhead |
| Delete Marker | `Shift + ;` | Remove nearest marker |
| Next Marker | `'` | Jump to next |
| Previous Marker | `Shift + '` | Jump to previous |

---

## 🔧 TECHNICAL IMPLEMENTATION

### File Structure

```
flutter_ui/lib/
├── widgets/slot_lab/timeline/
│   ├── ultimate_timeline_widget.dart        # Main timeline container (~800 LOC)
│   ├── timeline_ruler.dart                  # Ruler with time grid (~300 LOC)
│   ├── timeline_track.dart                  # Single audio track (~500 LOC)
│   ├── timeline_waveform_painter.dart       # Waveform CustomPainter (~400 LOC)
│   ├── timeline_automation_lane.dart        # Automation editor (~350 LOC)
│   ├── timeline_stage_markers.dart          # Stage marker overlay (~250 LOC)
│   ├── timeline_transport.dart              # Playback controls (~200 LOC)
│   ├── timeline_master_meters.dart          # Master metering (~300 LOC)
│   ├── timeline_grid_painter.dart           # Grid rendering (~150 LOC)
│   └── timeline_context_menu.dart           # Right-click menu (~200 LOC)
│
├── models/timeline/
│   ├── timeline_state.dart                  # State management (~200 LOC)
│   ├── audio_region.dart                    # Region model (~150 LOC)
│   ├── automation_lane.dart                 # Automation data (~100 LOC)
│   └── stage_marker.dart                    # Marker model (~50 LOC)
│
└── controllers/slot_lab/
    └── timeline_controller.dart             # Controller logic (~400 LOC)
```

**Total Estimate:** ~4,150 LOC

---

## 🚀 IMPLEMENTATION PHASES

### Phase 1: Foundation (Day 1) — ~1,000 LOC

| Task | File | LOC |
|------|------|-----|
| Data models | `timeline_state.dart`, `audio_region.dart` | 350 |
| Grid system | `timeline_grid_painter.dart` | 150 |
| Ruler | `timeline_ruler.dart` | 300 |
| Basic layout | `ultimate_timeline_widget.dart` | 200 |

**Goal:** Timeline canvas with grid and ruler

---

### Phase 2: Waveform Rendering (Day 2) — ~900 LOC

| Task | File | LOC |
|------|------|-----|
| FFI waveform loading | `timeline_controller.dart` | 200 |
| Waveform painter | `timeline_waveform_painter.dart` | 400 |
| Track widget | `timeline_track.dart` | 300 |

**Goal:** Display real waveforms from Rust FFI

---

### Phase 3: Region Editing (Day 3) — ~800 LOC

| Task | File | LOC |
|------|------|-----|
| Drag & drop | `timeline_track.dart` | 300 |
| Trim handles | `timeline_track.dart` | 200 |
| Fade editing | `timeline_track.dart` | 150 |
| Context menu | `timeline_context_menu.dart` | 150 |

**Goal:** Full region manipulation

---

### Phase 4: Automation (Day 4) — ~500 LOC

| Task | File | LOC |
|------|------|-----|
| Automation lane | `timeline_automation_lane.dart` | 350 |
| Point editing | `timeline_automation_lane.dart` | 150 |

**Goal:** Volume/pan automation curves

---

### Phase 5: Stage Integration (Day 5) — ~450 LOC

| Task | File | LOC |
|------|------|-----|
| Stage markers | `timeline_stage_markers.dart` | 250 |
| SlotLab provider sync | `timeline_controller.dart` | 200 |

**Goal:** SlotLab-specific features

---

### Phase 6: Transport & Metering (Day 6) — ~500 LOC

| Task | File | LOC |
|------|------|-----|
| Transport controls | `timeline_transport.dart` | 200 |
| Master meters | `timeline_master_meters.dart` | 300 |

**Goal:** Complete playback system

---

## 📊 SUCCESS METRICS

| Metric | Target | Measurement |
|--------|--------|-------------|
| Waveform FPS | 60fps | Flutter DevTools |
| Zoom responsiveness | < 16ms | Profiler |
| FFI waveform load | < 100ms | Benchmark |
| Drag latency | < 10ms | User perception |
| Memory usage | < 50MB | Additional |
| Snap accuracy | ± 1 sample | Unit tests |

---

## 🎯 DIFFERENTIAL ADVANTAGES — Why This is Ultimate

| Feature | Pro Tools 2024 | Logic Pro X | **FluxForge SlotLab** |
|---------|----------------|-------------|------------------------|
| **Waveform Rendering** | 60fps, GPU | 60fps, Metal | ✅ 60fps, Skia/Impeller |
| **Multi-LOD System** | 3 LOD levels | 4 LOD levels | ✅ 4 LOD levels (Rust FFI) |
| **Stage Markers** | ❌ Generic | ❌ Generic | ✅ **SlotLab-specific** |
| **Win Tier Integration** | ❌ | ❌ | ✅ **P5 Win Tier sync** |
| **RTPC Automation** | ❌ | ❌ | ✅ **Game-driven params** |
| **Real-time LUFS** | ✅ | ✅ | ✅ **Per-bus LUFS** |
| **Anticipation Regions** | ❌ | ❌ | ✅ **Visual tension zones** |
| **Audio-Visual Sync** | ❌ | ❌ | ✅ **Slot preview sync** |

**Unique Selling Points:**
1. **Game-aware timeline** — First DAW timeline designed for slot games
2. **Stage-driven workflow** — Markers auto-sync with slot engine
3. **RTPC automation** — Modulate audio based on game signals
4. **Win tier visualization** — See tier boundaries on timeline

---

## 🔒 SAFETY & PERFORMANCE

### Memory Management

```dart
// Waveform cache with LRU eviction
class WaveformCache {
  final int maxCacheSize = 500 * 1024 * 1024; // 500MB
  final Map<String, Uint8List> _cache = {};

  Uint8List? getWaveform(String audioPath);
  void evictLRU();
}
```

### Thread Safety

- **UI Thread:** Painting, user interaction
- **Isolate:** Waveform downsampling (if needed)
- **Rust FFI:** Waveform generation (already threaded)

### Error Handling

```dart
try {
  final waveform = await _ffi.generateWaveformFromFile(path);
} catch (e) {
  // Fallback: Display placeholder waveform
  _showPlaceholder(path);
  _logError('Waveform load failed: $e');
}
```

---

## 📚 DOCUMENTATION REQUIREMENTS

1. **User Guide:** Timeline shortcuts, workflow tips
2. **Developer Docs:** Architecture, FFI integration
3. **Video Tutorial:** 5-minute timeline walkthrough
4. **API Reference:** Public methods, events

---

**End of Specification — Total: ~4,150 LOC across 6 phases**

*Implementation order: Phase 1 → 2 → 3 → 4 → 5 → 6*
