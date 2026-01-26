# DAW Lower Zone — Ultimate Reconstruction Plan

**Status:** 📋 PLANNING
**Created:** 2026-01-22
**Architect:** Claude (Multi-Role Analysis)

---

## Executive Summary

Kompletna rekonstrukcija Lower Zone u DAW sekciji FluxForge Studio-a. Cilj: **ultimativno rešenje** koje kombinuje najbolje od Cubase Pro 14, Pro Tools 2024, Logic Pro X, Studio One 7 i REAPER 7, sa premium FabFilter-inspired vizuelnim jezikom.

---

## 1. ANALIZA PO ULOGAMA

### 1.1 Chief Audio Architect — Vision

**Trenutno stanje:**
- DAW Lower Zone (`layout/lower_zone.dart`) je generički, callback-based sistem
- 6 tab grupa (Mix, Edit, Analyze, Process, Media, Advanced)
- 40+ panela dostupno, ali loša organizacija
- Nema keyboard shortcut sistem kao SlotLab
- Nema state persistence

**Problem:** Lower Zone je "storage drawer" — sve bačeno unutra bez jasne hijerarhije.

**Vizija:** Lower Zone treba biti **Command Center** — sve što audio profesionalac treba na dohvat ruke, organizovano po workflow-u, ne po kategoriji.

### 1.2 Lead DSP Engineer — Technical Assessment

**DSP paneli koji postoje:**
| Kategorija | Paneli | Status |
|------------|--------|--------|
| EQ | pro_eq_panel, analog_eq, linear_phase_eq, spectral_panel, stereo_eq, room_correction | ✅ Postoje |
| Dynamics | dynamics_panel, multiband_panel, deesser_panel, transient_panel, saturation_panel | ✅ Postoje |
| Time/Space | delay_panel, reverb_panel, sidechain_panel, surround_panner, stereo_imager | ✅ Postoje |
| Advanced | convolution_ultra, restoration_panel, pitch_correction, time_stretch, wavelet | ✅ Postoje |
| FabFilter | compressor, limiter, gate, reverb, eq | ✅ Premium quality |

**Problem:** FabFilter paneli su samo u SlotLab, nisu integrisani u DAW Lower Zone!

**Preporuka:**
1. FabFilter paneli kao **primarni DSP** u DAW Lower Zone
2. Ostali paneli kao **Legacy/Advanced** opcije
3. Per-track DSP instantiation (trackId parametar)

### 1.3 Engine Architect — Performance

**Trenutni bottleneck:**
- Svi paneli se renderuju u IndexedStack (heavy memory)
- Nema lazy loading
- Nema virtualization za mixer strip listu

**Rešenje:**
```dart
// Umesto IndexedStack sa svim panelima
IndexedStack(
  index: activeTab,
  children: [/* 40+ widgets always in memory */],
)

// Koristi lazy builder
_buildActivePanel() {
  return switch (activeTab) {
    LowerZoneTab.mixer => const MixerPanel(),
    LowerZoneTab.eq => const FabFilterEqPanel(trackId: selectedTrackId),
    // ... samo active panel se renderuje
  };
}
```

### 1.4 Technical Director — Architecture

**Arhitektura treba biti:**

```
┌─────────────────────────────────────────────────────────────────┐
│ LOWER ZONE HEADER (36px)                                         │
│ ┌─────────┬─────────┬─────────┬─────────┬─────────┬───────────┐ │
│ │ MIX [1] │ EDIT [2]│ DSP [3] │ANALYZE[4]│MEDIA [5]│ ≡ Options │ │
│ └─────────┴─────────┴─────────┴─────────┴─────────┴───────────┘ │
├─────────────────────────────────────────────────────────────────┤
│ SUB-TAB BAR (28px) — Context-dependent                          │
│ ┌─────┬────────┬──────┬────────┐                                │
│ │Mixer│Inspector│Routing│Metering│  (shown when MIX active)     │
│ └─────┴────────┴──────┴────────┘                                │
├─────────────────────────────────────────────────────────────────┤
│ CONTENT AREA (variable, 100-500px)                              │
│                                                                  │
│   [Active panel content — lazy loaded]                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.5 UI/UX Expert — Workflow Analysis

**Pro Tools workflow (post-production):**
- F1-F4 Edit Modes stalno pristupačni
- Keyboard Focus za single-key edits
- Lower Zone = Edit Window (clip editor, MIDI editor)

**Cubase workflow (music production):**
- Lower Zone = MixConsole (full mixer)
- Channel Inspector uvek vidljiv desno
- Modulators, Logical Editor, Chord Pads

**Logic Pro workflow (creative):**
- Lower Zone = Piano Roll / Step Sequencer / Drummer
- Live Loops session view
- Browser + Apple Loops

**FluxForge Best-Of-All:**

| Tab | Shortcut | Primary Content | Secondary |
|-----|----------|-----------------|-----------|
| **MIX** | 1 | Channel Strip + Mini Mixer | Routing Matrix |
| **EDIT** | 2 | Clip Editor + Piano Roll | Fade Editor |
| **DSP** | 3 | FabFilter Chain (EQ→Comp→Limit) | Insert Rack |
| **ANALYZE** | 4 | Pro Metering (LUFS, TP, Correlation) | Spectrum |
| **MEDIA** | 5 | Browser + Audio Pool | Loop Browser |

### 1.6 Graphics Engineer — Visual Design

**Current problem:**
- Inconsistent panel styling
- No unified color language
- Tab buttons too small, no visual hierarchy

**FabFilter-Inspired Solution:**

```
COLOR PALETTE — LOWER ZONE:

Tab Headers:
├── MIX:     #4A9EFF (Blue)
├── EDIT:    #FF9040 (Orange)
├── DSP:     #A040FF (Purple)
├── ANALYZE: #40FF90 (Green)
└── MEDIA:   #FFCC40 (Yellow)

Backgrounds:
├── Header:  #0D0D12 (deepest)
├── SubTab:  #121218 (deep)
├── Content: #1A1A22 (mid)
└── Panels:  #242432 (surface)

Active States:
├── Tab glow: color @ 20% opacity
├── Border:   color @ 50% opacity
└── Text:     color @ 100%
```

**Visual Hierarchy:**
1. **Primary tabs** — Large (32px height), icon + label + shortcut badge
2. **Sub-tabs** — Medium (24px), label + count badge
3. **Panel content** — Full height minus headers

### 1.7 Security Expert — Input Validation

**Keyboard input:**
- Validate shortcut conflicts before registration
- Escape key always closes/cancels
- No shortcuts that conflict with OS (Cmd+Q, Cmd+W, etc.)

**State persistence:**
- Sanitize JSON before parsing
- Clamp height values to valid range
- Default to safe state on parse error

---

## 2. PROPOSED TAB STRUCTURE

### 2.1 Primary Tabs (1-5 shortcuts)

```dart
enum LowerZoneMainTab {
  mix,      // [1] Channel Strip, Mini Mixer, Routing
  edit,     // [2] Clip Editor, Piano Roll, Fade Editor
  dsp,      // [3] FabFilter Chain, Insert Rack
  analyze,  // [4] Metering, Spectrum, Correlation
  media,    // [5] Browser, Audio Pool, Favorites
}
```

### 2.2 Sub-Tabs per Main Tab

```dart
// MIX sub-tabs
enum MixSubTab {
  channelStrip,  // Selected track's channel strip
  miniMixer,     // 8-16 track mini mixer
  routing,       // Routing matrix
  sends,         // Send/Return routing
}

// EDIT sub-tabs
enum EditSubTab {
  clipEditor,    // Waveform + fade handles
  pianoRoll,     // MIDI note editor
  automation,    // Automation lanes
  fadeEditor,    // Crossfade curve editor
}

// DSP sub-tabs
enum DspSubTab {
  eq,           // FabFilter EQ Panel
  compressor,   // FabFilter Compressor
  limiter,      // FabFilter Limiter
  reverb,       // FabFilter Reverb
  gate,         // FabFilter Gate
  insertChain,  // Full insert chain view
}

// ANALYZE sub-tabs
enum AnalyzeSubTab {
  metering,      // LUFS, True Peak, LRA
  spectrum,      // Real-time spectrum analyzer
  correlation,   // Stereo correlation meter
  loudness,      // Loudness history graph
}

// MEDIA sub-tabs
enum MediaSubTab {
  browser,       // File browser
  audioPool,     // Project audio pool
  favorites,     // Starred items
  loops,         // Loop browser with preview
}
```

### 2.3 Keyboard Shortcut Map

| Key | Action | Context |
|-----|--------|---------|
| `1` | MIX tab | Global |
| `2` | EDIT tab | Global |
| `3` | DSP tab | Global |
| `4` | ANALYZE tab | Global |
| `5` | MEDIA tab | Global |
| `` ` `` | Toggle expand/collapse | Global |
| `Q` | Channel Strip | MIX active |
| `W` | Mini Mixer | MIX active |
| `E` | Routing | MIX active |
| `Q` | EQ | DSP active |
| `W` | Compressor | DSP active |
| `E` | Limiter | DSP active |
| `R` | Reverb | DSP active |
| `T` | Gate | DSP active |
| `Cmd+Up` | Increase height | Global |
| `Cmd+Down` | Decrease height | Global |
| `Esc` | Close/Collapse | Global |

---

## 3. COMPONENT ARCHITECTURE

### 3.1 Controller (ChangeNotifier)

```dart
class DawLowerZoneController extends ChangeNotifier {
  // State
  LowerZoneMainTab _mainTab = LowerZoneMainTab.mix;
  Map<LowerZoneMainTab, int> _subTabIndices = {};
  bool _isExpanded = true;
  double _height = 300.0;
  int? _selectedTrackId;

  // Getters
  LowerZoneMainTab get mainTab => _mainTab;
  int getSubTabIndex(LowerZoneMainTab tab) => _subTabIndices[tab] ?? 0;
  bool get isExpanded => _isExpanded;
  double get height => _height;
  int? get selectedTrackId => _selectedTrackId;

  // Actions
  void switchMainTab(LowerZoneMainTab tab) {
    if (_mainTab == tab && _isExpanded) {
      _isExpanded = false;
    } else {
      _mainTab = tab;
      _isExpanded = true;
    }
    notifyListeners();
  }

  void switchSubTab(int index) {
    _subTabIndices[_mainTab] = index;
    notifyListeners();
  }

  void setSelectedTrack(int? trackId) {
    _selectedTrackId = trackId;
    notifyListeners();
  }

  void toggle() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  void setHeight(double h) {
    _height = h.clamp(kMinHeight, kMaxHeight);
    notifyListeners();
  }

  // Keyboard handling
  KeyEventResult handleKeyEvent(KeyEvent event) {
    // ... shortcut logic
  }

  // Persistence
  Map<String, dynamic> toJson() => {
    'mainTab': _mainTab.index,
    'subTabIndices': _subTabIndices.map((k, v) => MapEntry(k.index.toString(), v)),
    'isExpanded': _isExpanded,
    'height': _height,
  };

  void fromJson(Map<String, dynamic> json) {
    // ... restore logic with validation
  }
}
```

### 3.2 Main Widget Structure

```dart
class DawLowerZone extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<DawLowerZoneController>(
      builder: (context, controller, _) {
        return Column(
          children: [
            // Resize handle
            _ResizeHandle(controller: controller),

            // Main tab bar (MIX, EDIT, DSP, ANALYZE, MEDIA)
            _MainTabBar(controller: controller),

            // Animated content area
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: controller.isExpanded ? controller.height : 0,
              curve: Curves.easeOutCubic,
              child: ClipRect(
                child: Column(
                  children: [
                    // Sub-tab bar (context-dependent)
                    _SubTabBar(controller: controller),

                    // Active panel (lazy loaded)
                    Expanded(
                      child: _buildActivePanel(controller),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActivePanel(DawLowerZoneController controller) {
    final trackId = controller.selectedTrackId ?? 0;

    return switch (controller.mainTab) {
      LowerZoneMainTab.mix => _buildMixPanel(controller, trackId),
      LowerZoneMainTab.edit => _buildEditPanel(controller, trackId),
      LowerZoneMainTab.dsp => _buildDspPanel(controller, trackId),
      LowerZoneMainTab.analyze => _buildAnalyzePanel(controller),
      LowerZoneMainTab.media => _buildMediaPanel(controller),
    };
  }

  Widget _buildDspPanel(DawLowerZoneController controller, int trackId) {
    final subTab = controller.getSubTabIndex(LowerZoneMainTab.dsp);

    return switch (DspSubTab.values[subTab]) {
      DspSubTab.eq => FabFilterEqPanel(trackId: trackId),
      DspSubTab.compressor => FabFilterCompressorPanel(trackId: trackId),
      DspSubTab.limiter => FabFilterLimiterPanel(trackId: trackId),
      DspSubTab.reverb => FabFilterReverbPanel(trackId: trackId),
      DspSubTab.gate => FabFilterGatePanel(trackId: trackId),
      DspSubTab.insertChain => InsertChainPanel(trackId: trackId),
    };
  }
}
```

### 3.3 Tab Button Design

```dart
class _MainTabButton extends StatefulWidget {
  final LowerZoneMainTab tab;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final config = _tabConfigs[tab]!;

    return Tooltip(
      message: '${config.label} (${config.shortcut})',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                ? config.color.withOpacity(0.15)
                : _hovering
                  ? Colors.white.withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isActive
                ? Border.all(color: config.color.withOpacity(0.4))
                : null,
              boxShadow: isActive ? [
                BoxShadow(
                  color: config.color.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: -2,
                ),
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(config.icon, size: 16, color: isActive ? config.color : Colors.white60),
                const SizedBox(width: 8),
                Text(
                  config.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? config.color : Colors.white70,
                  ),
                ),
                const SizedBox(width: 6),
                // Shortcut badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    config.shortcut,
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: isActive ? config.color : Colors.white38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## 4. PANEL SPECIFICATIONS

### 4.1 MIX Tab — Channel Strip

**Sadržaj:**
- Selected track's channel strip (vertical layout)
- Input gain → Insert chain → EQ curve → Dynamics meter → Fader → Pan → Sends → Output

**Layout (horizontal):**
```
┌─────────────────────────────────────────────────────────────────┐
│ ┌───────┐ ┌─────────────────┐ ┌────────┐ ┌──────┐ ┌──────────┐ │
│ │ INPUT │ │   INSERT RACK   │ │ EQ     │ │DYNAM │ │  FADER   │ │
│ │ GAIN  │ │ [1] [2] [3] [4] │ │ CURVE  │ │METER │ │  + PAN   │ │
│ │ +12dB │ │                 │ │        │ │      │ │  + SENDS │ │
│ └───────┘ └─────────────────┘ └────────┘ └──────┘ └──────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 MIX Tab — Mini Mixer

**Sadržaj:**
- 8-16 track strips horizontally
- Compact view: Meter + Fader + Pan + Mute/Solo

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ Track 1  │ Track 2  │ Track 3  │ Track 4  │ ... │ Master      │
│ ┌─────┐  │ ┌─────┐  │ ┌─────┐  │ ┌─────┐  │     │ ┌─────────┐ │
│ │     │  │ │     │  │ │     │  │ │     │  │     │ │         │ │
│ │METER│  │ │METER│  │ │METER│  │ │METER│  │     │ │  METER  │ │
│ │     │  │ │     │  │ │     │  │ │     │  │     │ │         │ │
│ ├─────┤  │ ├─────┤  │ ├─────┤  │ ├─────┤  │     │ ├─────────┤ │
│ │FADER│  │ │FADER│  │ │FADER│  │ │FADER│  │     │ │  FADER  │ │
│ ├─────┤  │ ├─────┤  │ ├─────┤  │ ├─────┤  │     │ ├─────────┤ │
│ │ M S │  │ │ M S │  │ │ M S │  │ │ M S │  │     │ │  M  S   │ │
│ └─────┘  │ └─────┘  │ └─────┘  │ └─────┘  │     │ └─────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 DSP Tab — FabFilter Chain

**Novi koncept:** Umesto pojedinačnih panela, prikaži **chain view** sa svim aktivnim procesorima.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ SIGNAL FLOW: Input → [EQ] → [Comp] → [Limit] → Output          │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐ │
│ │   EQ (Pro-Q)    │ │ COMP (Pro-C)    │ │   LIMIT (Pro-L)     │ │
│ │  ┌───────────┐  │ │  ┌───────────┐  │ │  ┌───────────────┐  │ │
│ │  │           │  │ │  │  ╱──────  │  │ │  │ ▓▓▓▓▓▓░░░░░░  │  │ │
│ │  │  SPECTRUM │  │ │  │ ╱        │  │ │  │ LUFS: -14.2   │  │ │
│ │  │           │  │ │  │╱         │  │ │  │ TP: -0.3 dBFS │  │ │
│ │  └───────────┘  │ │  └───────────┘  │ │  └───────────────┘  │ │
│ │  [bypass] [A/B] │ │  [bypass] [A/B] │ │  [bypass] [A/B]     │ │
│ └─────────────────┘ └─────────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Click to expand:** Klik na bilo koji procesor otvara full panel.

### 4.4 ANALYZE Tab — Pro Metering

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐ │
│ │   LOUDNESS       │ │   TRUE PEAK      │ │   CORRELATION    │ │
│ │                  │ │                  │ │                  │ │
│ │ Integrated: -14.2│ │  L: -0.3 dBTP   │ │    ◀──●──▶       │ │
│ │ Short-term: -12.8│ │  R: -0.5 dBTP   │ │      +1.0        │ │
│ │ Momentary: -10.5 │ │                  │ │                  │ │
│ │ LRA: 8.2 LU      │ │  [CLIP] ○        │ │  Stereo Width:   │ │
│ │                  │ │                  │ │      78%         │ │
│ └──────────────────┘ └──────────────────┘ └──────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│ LOUDNESS HISTORY                                                │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁ -14 LUFS │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. IMPLEMENTATION PHASES

### Phase 1: Core Infrastructure (3-4 dana)

1. **Create `DawLowerZoneController`** — ChangeNotifier sa state management
2. **Create `DawLowerZone` widget** — Main container sa animated expand
3. **Implement main tab bar** — 5 primary tabs sa shortcuts
4. **Implement sub-tab bar** — Context-dependent secondary tabs
5. **Add keyboard handler** — 1-5 + ` + sub-tab shortcuts

### Phase 2: Panel Integration (4-5 dana)

1. **MIX: Channel Strip** — Port existing channel_inspector_panel
2. **MIX: Mini Mixer** — New compact mixer component
3. **DSP: FabFilter Chain** — Integrate existing FabFilter panels
4. **ANALYZE: Pro Metering** — Port pro_metering_panel
5. **MEDIA: Browser** — Port file browser

### Phase 3: Polish & Persistence (2-3 dana)

1. **Visual polish** — Glow effects, smooth animations
2. **State persistence** — Save/restore to project file
3. **Track selection sync** — Update panels when track selected
4. **Resize optimization** — Debounced height updates
5. **Testing** — Keyboard shortcuts, animations, memory

---

## 6. FILE STRUCTURE

```
flutter_ui/lib/
├── controllers/
│   └── daw/
│       └── lower_zone_controller.dart    # NEW — Main controller
│
├── widgets/
│   └── daw/
│       └── lower_zone/
│           ├── daw_lower_zone.dart       # NEW — Main widget
│           ├── main_tab_bar.dart         # NEW — Primary tabs
│           ├── sub_tab_bar.dart          # NEW — Secondary tabs
│           ├── resize_handle.dart        # NEW — Drag handle
│           │
│           ├── mix/
│           │   ├── channel_strip_panel.dart    # Port from existing
│           │   ├── mini_mixer_panel.dart       # NEW
│           │   ├── routing_panel.dart          # Port from existing
│           │   └── sends_panel.dart            # NEW
│           │
│           ├── edit/
│           │   ├── clip_editor_panel.dart      # Port from existing
│           │   ├── piano_roll_panel.dart       # Port from existing
│           │   ├── automation_panel.dart       # NEW
│           │   └── fade_editor_panel.dart      # NEW
│           │
│           ├── dsp/
│           │   ├── dsp_chain_panel.dart        # NEW — Overview
│           │   └── ... (FabFilter panels already exist)
│           │
│           ├── analyze/
│           │   ├── pro_metering_panel.dart     # Port from existing
│           │   ├── spectrum_panel.dart         # Port from existing
│           │   ├── correlation_panel.dart      # NEW
│           │   └── loudness_history.dart       # NEW
│           │
│           └── media/
│               ├── browser_panel.dart          # Port from existing
│               ├── audio_pool_panel.dart       # ENHANCED — Multi-selection support
│               └── favorites_panel.dart        # NEW

---

## 9. AUDIO POOL MULTI-SELECTION (2026-01-26)

### 9.1 Overview

AudioPoolPanel sada podržava **multi-selection** sa sledećim feature-ima:
- **Ctrl+Click** (Cmd+Click on macOS) — Toggle individual file selection
- **Shift+Click** — Range selection (from last selected to clicked file)
- **Ctrl+A** — Select all files in current section
- **Delete/Backspace** — Remove selected files
- **Escape** — Clear selection
- **Multi-file drag** — Drag multiple selected files at once

### 9.2 State Variables

```dart
// Multi-selection state
Set<String> _selectedFileIds = {};    // Currently selected file IDs
int? _lastSelectedIndex;               // For Shift+click range selection
```

### 9.3 Selection Methods

```dart
void _handleFileSelection(AudioFileInfo file, int index, {bool isCtrlPressed = false, bool isShiftPressed = false}) {
  if (isCtrlPressed) {
    // Toggle selection
    if (_selectedFileIds.contains(file.id)) {
      _selectedFileIds.remove(file.id);
    } else {
      _selectedFileIds.add(file.id);
    }
    _lastSelectedIndex = index;
  } else if (isShiftPressed && _lastSelectedIndex != null) {
    // Range selection
    final start = min(_lastSelectedIndex!, index);
    final end = max(_lastSelectedIndex!, index);
    for (var i = start; i <= end; i++) {
      _selectedFileIds.add(files[i].id);
    }
  } else {
    // Single selection (clears others)
    _selectedFileIds = {file.id};
    _lastSelectedIndex = index;
  }
}

void _selectAll() {
  _selectedFileIds = files.map((f) => f.id).toSet();
}

void _clearSelection() {
  _selectedFileIds.clear();
  _lastSelectedIndex = null;
}

void _removeSelectedFiles() {
  for (final id in _selectedFileIds) {
    widget.onFileRemoved?.call(id);
  }
  _selectedFileIds.clear();
}
```

### 9.4 Multi-File Drag Support

```dart
// Draggable now uses List<AudioFileInfo>
Draggable<List<AudioFileInfo>>(
  data: _selectedFileIds.isEmpty || !_selectedFileIds.contains(file.id)
      ? [file]  // Single file drag
      : files.where((f) => _selectedFileIds.contains(f.id)).toList(),  // Multi drag
  feedback: Material(
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            _selectedFileIds.length > 1
                ? '${_selectedFileIds.length} files'
                : file.name,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ),
  ),
)
```

### 9.5 Visual Feedback

| State | Visual |
|-------|--------|
| Unselected | Default background |
| Hovering | Lighter background |
| Selected | Blue border + light blue background |
| Multi-selected | Blue badge with count |

### 9.6 Keyboard Shortcuts

| Key | Action | Context |
|-----|--------|---------|
| `Ctrl+A` | Select all | AudioPoolPanel focused |
| `Delete` / `Backspace` | Remove selected | Files selected |
| `Escape` | Clear selection | Files selected |
| `Ctrl+Click` | Toggle selection | On file item |
| `Shift+Click` | Range selection | On file item |

### 9.7 DragTarget Compatibility

All DragTargets that accept audio files are updated to accept `List<AudioFileInfo>`:

```dart
// stage_trace_widget.dart
DragTarget<List<AudioFileInfo>>(
  onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
  onAcceptWithDetails: (details) {
    // Single file: details.data.first
    // All files: details.data
    _handleBatchAudioDrop(details.data);
  },
)
```

### 9.8 Cross-Section Support

Multi-selection radi u sve tri sekcije:
- **DAW** — Audio Pool u MEDIA tab
- **Middleware** — Audio browser panel
- **SlotLab** — Events panel audio browser

### 9.9 Files Changed

| File | Changes |
|------|---------|
| `audio_pool_panel.dart` | Multi-selection state, keyboard handling, drag support |
| `stage_trace_widget.dart` | Updated DragTarget to accept `List<AudioFileInfo>` |
```

---

## 7. SUCCESS CRITERIA

### Functional
- [ ] 5 main tabs accessible via keyboard (1-5)
- [ ] Sub-tabs accessible via context-sensitive shortcuts
- [ ] Smooth expand/collapse animation (200ms)
- [ ] Resizable via drag (100-500px)
- [ ] State persistence (tab, height, expansion)
- [ ] Track selection updates all panels

### Visual
- [ ] FabFilter-quality aesthetic
- [ ] Color-coded tabs with glow effects
- [ ] Hover states on all interactive elements
- [ ] Shortcut badges visible
- [ ] Consistent spacing and typography

### Performance
- [ ] Lazy panel loading (only active panel rendered)
- [ ] 60fps resize animation
- [ ] < 16ms keyboard response
- [ ] No memory leaks on tab switch

### Integration
- [ ] FabFilter panels work with trackId
- [ ] Channel Strip syncs with timeline selection
- [ ] Metering shows actual audio levels
- [ ] Browser can drag files to timeline

---

## 8. REFERENCES

### Internal Docs
- `.claude/synthesis/BEST_OF_ALL_DAWS.md` — Feature synthesis
- `.claude/architecture/FLUXFORGE_VS_INDUSTRY_ANALYSIS.md` — Competitive analysis
- `.claude/architecture/DAW_WORKFLOW_PATTERNS.md` — Workflow patterns
- `.claude/tasks/FABFILTER_DSP_SUITE.md` — FabFilter implementation

### External Inspiration
- Cubase Pro 14 — Lower Zone MixConsole
- Pro Tools 2024 — Edit Window workflow
- Logic Pro X — Live Loops integration
- Studio One 7 — Browser + Inspector
- REAPER 7 — Customizable docking

---

## APPROVAL

**Čeka se odobrenje korisnika pre implementacije.**

Ovaj dokument definiše:
1. ✅ Kompletnu analizu po svim ulogama
2. ✅ Tab strukturu sa shortcut mappingom
3. ✅ Component arhitekturu
4. ✅ Visual design specifikacije
5. ✅ Panel layouts
6. ✅ Implementation phases
7. ✅ File structure
8. ✅ Success criteria

**Sledeći korak:** Odobrenje → Phase 1 implementacija
