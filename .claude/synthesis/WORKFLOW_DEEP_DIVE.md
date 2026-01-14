# FluxForge Workflow — Deep Dive: Best-in-Class Features

> Tehnička specifikacija za implementaciju workflow feature-a
> Keyboard Focus, Edit Modes, Smart Tool, Razor Editing, Swipe Comping, Modulators

---

## 1. KEYBOARD FOCUS MODE (PRO TOOLS)

### 1.1 Koncept

```
┌─────────────────────────────────────────────────────────────┐
│ KEYBOARD FOCUS MODE — PRO TOOLS EXCLUSIVE                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Problem u svim DAW-ovima:                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  User hoće da pritisne "S" za Split                     ││
│  │                                                          ││
│  │  ALI: Ako je fokus na text field (track name, marker)   ││
│  │       "S" upisuje slovo umesto da splituje              ││
│  │                                                          ││
│  │  Standardno rešenje:                                     ││
│  │  • Ctrl+S ili Cmd+S = Split                             ││
│  │  • Više tastera = sporiji workflow                      ││
│  │  • Teže zapamtiti sve kombinacije                       ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Pro Tools rešenje — KEYBOARD FOCUS MODE:                    │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Toggle dugme: [a...z] u Edit window                    ││
│  │                                                          ││
│  │  [OFF] — Normalan rad                                   ││
│  │          Shortcuts rade samo sa modifierima             ││
│  │          Text input radi normalno                       ││
│  │                                                          ││
│  │  [ON]  — KEYBOARD FOCUS ACTIVE                          ││
│  │          SVAKI TASTER = KOMANDA                         ││
│  │          A = Trim Start                                 ││
│  │          B = Beat Detective                             ││
│  │          S = Split                                      ││
│  │          D = Duplicate                                  ││
│  │          ...                                            ││
│  │          Text input DISABLED (mora kliknuti field)      ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Zašto je ovo REVOLUCIONARNO:                                │
│  • Post-production: 1000+ edita po danu                     │
│  • Jedan taster vs Ctrl+taster = 2x brže                   │
│  • Muscle memory: "S" = Split, uvek                        │
│  • Razlog zašto Hollywood koristi Pro Tools                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Pro Tools Keyboard Focus Mapping

```
┌─────────────────────────────────────────────────────────────┐
│ PRO TOOLS KEYBOARD FOCUS — COMPLETE MAPPING                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  EDITING KEYS:                                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ A = Trim Start to Insertion (or Selection Start)       ││
│  │ B = Beat Detective                                      ││
│  │ C = Copy (standard)                                     ││
│  │ D = Duplicate                                           ││
│  │ E = Fade Editor / Zoom to Selection (toggle)           ││
│  │ F = Create Fades                                        ││
│  │ G = Group Selected Clips                                ││
│  │ H = Heal Separation                                     ││
│  │ I = Identify Beat (Beat Detective)                      ││
│  │ J = Previous/Next Transient (Shift+J)                  ││
│  │ K = Link Selection (Track/Edit)                        ││
│  │ L = Loop Playback Toggle                                ││
│  │ M = Mute Clip                                           ││
│  │ N = New Tracks Dialog                                   ││
│  │ O = (varies)                                            ││
│  │ P = Pencil Tool                                         ││
│  │ Q = Quantize                                            ││
│  │ R = Rename                                              ││
│  │ S = Separate (Split) Clip                               ││
│  │ T = Trim End to Insertion (or Selection End)           ││
│  │ U = Undo                                                ││
│  │ V = Paste (standard)                                    ││
│  │ W = Strip Silence Window                                ││
│  │ X = Cut (standard)                                      ││
│  │ Y = Redo                                                ││
│  │ Z = Zoom Tool (horizontal)                              ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  TOOL KEYS:                                                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ F1 = Shuffle Mode                                       ││
│  │ F2 = Slip Mode                                          ││
│  │ F3 = Spot Mode                                          ││
│  │ F4 = Grid Mode                                          ││
│  │                                                          ││
│  │ F5 = Zoomer Tool                                        ││
│  │ F6 = Trimmer Tool                                       ││
│  │ F7 = Selector Tool                                      ││
│  │ F8 = Grabber Tool                                       ││
│  │ F9 = Scrubber Tool                                      ││
│  │ F10 = Pencil Tool                                       ││
│  │ F11 = Smart Tool (toggle)                               ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  MEMORY LOCATIONS (Markers):                                 │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ 0-9 = Jump to Memory Location 0-9                       ││
│  │ . (period) + number = Jump to location                  ││
│  │ Enter = Create new Memory Location                      ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  TRANSPORT:                                                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Spacebar = Play/Stop                                    ││
│  │ Enter (numpad) = Play from Start                        ││
│  │ 0 (numpad) = Stop and Return to Start                  ││
│  │ 3 (numpad) = Record                                     ││
│  │ 1 (numpad) = Rewind                                     ││
│  │ 2 (numpad) = Fast Forward                               ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 FluxForge Implementation

```dart
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — KEYBOARD FOCUS IMPLEMENTATION                   │
├─────────────────────────────────────────────────────────────┤

// flutter_ui/lib/providers/keyboard_focus_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard Focus Mode state
enum KeyboardFocusMode {
  /// Normal mode - shortcuts require modifiers
  normal,

  /// Focus mode - single keys = commands
  commands,
}

/// Provider for Keyboard Focus Mode (Pro Tools style)
class KeyboardFocusProvider extends ChangeNotifier {
  KeyboardFocusMode _mode = KeyboardFocusMode.normal;

  KeyboardFocusMode get mode => _mode;
  bool get isCommandMode => _mode == KeyboardFocusMode.commands;

  /// Toggle between modes
  void toggle() {
    _mode = _mode == KeyboardFocusMode.normal
        ? KeyboardFocusMode.commands
        : KeyboardFocusMode.normal;
    notifyListeners();
  }

  /// Set specific mode
  void setMode(KeyboardFocusMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
  }
}

/// Keyboard Focus command mapping
class KeyboardFocusCommands {
  static const Map<LogicalKeyboardKey, String> commandMap = {
    // Editing
    LogicalKeyboardKey.keyA: 'trim_start_to_cursor',
    LogicalKeyboardKey.keyB: 'beat_detective',
    LogicalKeyboardKey.keyC: 'copy',
    LogicalKeyboardKey.keyD: 'duplicate',
    LogicalKeyboardKey.keyE: 'zoom_to_selection',
    LogicalKeyboardKey.keyF: 'create_fades',
    LogicalKeyboardKey.keyG: 'group_clips',
    LogicalKeyboardKey.keyH: 'heal_separation',
    LogicalKeyboardKey.keyI: 'identify_beat',
    LogicalKeyboardKey.keyJ: 'next_transient',
    LogicalKeyboardKey.keyK: 'link_selection',
    LogicalKeyboardKey.keyL: 'loop_toggle',
    LogicalKeyboardKey.keyM: 'mute_clip',
    LogicalKeyboardKey.keyN: 'new_tracks',
    LogicalKeyboardKey.keyP: 'pencil_tool',
    LogicalKeyboardKey.keyQ: 'quantize',
    LogicalKeyboardKey.keyR: 'rename',
    LogicalKeyboardKey.keyS: 'split',
    LogicalKeyboardKey.keyT: 'trim_end_to_cursor',
    LogicalKeyboardKey.keyU: 'undo',
    LogicalKeyboardKey.keyV: 'paste',
    LogicalKeyboardKey.keyW: 'strip_silence',
    LogicalKeyboardKey.keyX: 'cut',
    LogicalKeyboardKey.keyY: 'redo',
    LogicalKeyboardKey.keyZ: 'zoom_tool',

    // Edit modes
    LogicalKeyboardKey.f1: 'mode_shuffle',
    LogicalKeyboardKey.f2: 'mode_slip',
    LogicalKeyboardKey.f3: 'mode_spot',
    LogicalKeyboardKey.f4: 'mode_grid',

    // Tools
    LogicalKeyboardKey.f5: 'tool_zoom',
    LogicalKeyboardKey.f6: 'tool_trim',
    LogicalKeyboardKey.f7: 'tool_select',
    LogicalKeyboardKey.f8: 'tool_grab',
    LogicalKeyboardKey.f9: 'tool_scrub',
    LogicalKeyboardKey.f10: 'tool_pencil',
    LogicalKeyboardKey.f11: 'tool_smart',

    // Memory locations
    LogicalKeyboardKey.digit0: 'goto_marker_0',
    LogicalKeyboardKey.digit1: 'goto_marker_1',
    LogicalKeyboardKey.digit2: 'goto_marker_2',
    LogicalKeyboardKey.digit3: 'goto_marker_3',
    LogicalKeyboardKey.digit4: 'goto_marker_4',
    LogicalKeyboardKey.digit5: 'goto_marker_5',
    LogicalKeyboardKey.digit6: 'goto_marker_6',
    LogicalKeyboardKey.digit7: 'goto_marker_7',
    LogicalKeyboardKey.digit8: 'goto_marker_8',
    LogicalKeyboardKey.digit9: 'goto_marker_9',
  };

  /// Get command for key in focus mode
  static String? getCommand(LogicalKeyboardKey key) {
    return commandMap[key];
  }
}

/// Widget that handles keyboard focus mode
class KeyboardFocusHandler extends StatelessWidget {
  final Widget child;
  final KeyboardFocusProvider focusProvider;
  final Function(String command) onCommand;

  const KeyboardFocusHandler({
    super.key,
    required this.child,
    required this.focusProvider,
    required this.onCommand,
  });

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;

        // Check if in command mode
        if (!focusProvider.isCommandMode) return;

        // Check if text field is focused (allow typing)
        final focus = FocusManager.instance.primaryFocus;
        if (focus?.context?.widget is EditableText) return;

        // Look up command
        final command = KeyboardFocusCommands.getCommand(event.logicalKey);
        if (command != null) {
          onCommand(command);
        }
      },
      child: child,
    );
  }
}

└─────────────────────────────────────────────────────────────┘
```

### 1.4 UI Integration

```
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE UI — KEYBOARD FOCUS INDICATOR                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Toolbar Mockup:                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  │  ┌─────────┐   ││
│  │ │ Shuf │ │ Slip │ │ Spot │ │ Grid │  │  │ [a...z] │   ││
│  │ │  F1  │ │  F2  │ │  F3  │ │  F4  │  │  │ FOCUS   │   ││
│  │ └──────┘ └──────┘ └──────┘ └──────┘  │  └─────────┘   ││
│  │                                       │   ↑             ││
│  │  Edit Modes                           │   Keyboard      ││
│  │                                       │   Focus Toggle  ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  When FOCUS MODE is ON:                                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  │  ┌─────────┐   ││
│  │ │ Shuf │ │ Slip │ │ Spot │ │ Grid │  │  │ [a...z] │   ││
│  │ │  F1  │ │  F2  │ │  F3  │ │  F4  │  │  │ ●ACTIVE │   ││
│  │ └──────┘ └──────┘ └──────┘ └──────┘  │  └─────────┘   ││
│  │                                       │   ORANGE       ││
│  │                                       │   HIGHLIGHT    ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  On-Screen Help (optional overlay when learning):            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  KEYBOARD FOCUS ACTIVE                                   ││
│  │  ─────────────────────                                   ││
│  │  S = Split    D = Duplicate    F = Fades                ││
│  │  A = Trim ←   T = Trim →       G = Group                ││
│  │  M = Mute     R = Rename       H = Heal                 ││
│  │  U = Undo     Y = Redo         L = Loop                 ││
│  │                                                          ││
│  │  [Press ESC to exit focus mode]                         ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. EDIT MODES (PRO TOOLS)

### 2.1 Four Edit Modes Explained

```
┌─────────────────────────────────────────────────────────────┐
│ EDIT MODES — INDUSTRY STANDARD WORKFLOW                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  MODE 1: SHUFFLE (F1)                                    ││
│  │  ════════════════════                                    ││
│  │                                                          ││
│  │  Behavior: Clips "shuffle" to fill gaps                 ││
│  │                                                          ││
│  │  Before delete:                                          ││
│  │  [Clip A][Clip B][Clip C][Clip D]                       ││
│  │                                                          ││
│  │  Delete Clip B:                                          ││
│  │  [Clip A][Clip C][Clip D]← ← ←                          ││
│  │          ↑                                               ││
│  │          C i D pomereni levo da popune gap              ││
│  │                                                          ││
│  │  Before insert:                                          ││
│  │  [Clip A][Clip C][Clip D]                               ││
│  │                                                          ││
│  │  Insert Clip X after A:                                  ││
│  │  [Clip A][Clip X][Clip C][Clip D]                       ││
│  │                  → → → →                                 ││
│  │          ↑                                               ││
│  │          C i D pomereni desno da naprave prostor        ││
│  │                                                          ││
│  │  USE CASE:                                               ││
│  │  • Dialogue editing (remove ums, ahs)                   ││
│  │  • Podcast editing                                      ││
│  │  • Voiceover cleanup                                    ││
│  │  • Radio production                                     ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  MODE 2: SLIP (F2)                                       ││
│  │  ═════════════════                                       ││
│  │                                                          ││
│  │  Behavior: Clips move freely, can overlap               ││
│  │                                                          ││
│  │  Before:                                                 ││
│  │  [Clip A]    [Clip B]    [Clip C]                       ││
│  │                                                          ││
│  │  Move Clip B left:                                       ││
│  │  [Clip A][Clip B]        [Clip C]                       ││
│  │          ↑                                               ││
│  │          B pomeren, ostali NEPROMENJENI                 ││
│  │                                                          ││
│  │  Move Clip B over A:                                     ││
│  │  [Clip A]                                                ││
│  │     [Clip B]             [Clip C]                       ││
│  │     ↑                                                    ││
│  │     B preklapa A (overlap allowed)                      ││
│  │                                                          ││
│  │  USE CASE:                                               ││
│  │  • Music production (loop arrangement)                  ││
│  │  • Sound design                                         ││
│  │  • Any non-linear editing                               ││
│  │  • Default mode for most work                           ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  MODE 3: SPOT (F3)                                       ││
│  │  ═════════════════                                       ││
│  │                                                          ││
│  │  Behavior: Click to place at EXACT timecode             ││
│  │                                                          ││
│  │  Click on clip → Dialog appears:                        ││
│  │  ┌────────────────────────────────────────────┐         ││
│  │  │ SPOT DIALOG                                │         ││
│  │  │                                            │         ││
│  │  │ Original Time Code: 01:23:45:12            │         ││
│  │  │ User Time Code:     [01:24:00:00]          │         ││
│  │  │                                            │         ││
│  │  │ Start:  [01:24:00:00]                      │         ││
│  │  │ Sync:   [01:24:00:00]                      │         ││
│  │  │ End:    [01:24:02:15]                      │         ││
│  │  │                                            │         ││
│  │  │ Duration: 00:00:02:15                      │         ││
│  │  │                                            │         ││
│  │  │        [Cancel]  [OK]                      │         ││
│  │  └────────────────────────────────────────────┘         ││
│  │                                                          ││
│  │  USE CASE:                                               ││
│  │  • Film/TV post (sync to timecode)                      ││
│  │  • ADR (automated dialogue replacement)                 ││
│  │  • Foley (sync to picture)                              ││
│  │  • Sound effects to picture                             ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  MODE 4: GRID (F4)                                       ││
│  │  ═════════════════                                       ││
│  │                                                          ││
│  │  Behavior: All operations snap to grid                  ││
│  │                                                          ││
│  │  Grid resolution (selectable):                           ││
│  │  • Bars                                                 ││
│  │  • Beats (1/4, 1/8, 1/16, 1/32, 1/64)                  ││
│  │  • Ticks (MIDI resolution)                              ││
│  │  • Samples                                              ││
│  │  • Timecode frames                                      ││
│  │  • Minutes:Seconds                                      ││
│  │  • Milliseconds                                         ││
│  │                                                          ││
│  │  Sub-modes:                                              ││
│  │                                                          ││
│  │  ABSOLUTE GRID:                                          ││
│  │  • Clip start snaps to grid lines                       ││
│  │  • Example: Drag to 1.2.3 → Snaps to 1.2.0             ││
│  │                                                          ││
│  │  RELATIVE GRID:                                          ││
│  │  • Clip moves BY grid amounts                           ││
│  │  • Preserves original offset                            ││
│  │  • Example: Clip at 1.1.2.050                          ││
│  │             Move 1 beat → 1.2.2.050                     ││
│  │                                                          ││
│  │  USE CASE:                                               ││
│  │  • Music production                                     ││
│  │  • Beat-based editing                                   ││
│  │  • Loop arrangement                                     ││
│  │  • Quantized workflows                                  ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 FluxForge Implementation

```dart
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — EDIT MODES IMPLEMENTATION                       │
├─────────────────────────────────────────────────────────────┤

// flutter_ui/lib/providers/edit_mode_provider.dart

/// Edit mode (Pro Tools style)
enum EditMode {
  /// Clips shuffle to fill gaps
  shuffle,

  /// Free movement, overlaps allowed
  slip,

  /// Click to place at exact timecode
  spot,

  /// Snap to grid
  grid,
}

/// Grid mode sub-type
enum GridMode {
  /// Snap to absolute grid positions
  absolute,

  /// Move by grid amounts, preserve offset
  relative,
}

/// Grid resolution
enum GridResolution {
  bars,
  beats,
  halfBeats,      // 1/8
  quarterBeats,   // 1/16
  eighthBeats,    // 1/32
  ticks,
  samples,
  frames,         // Timecode frames
  seconds,
  milliseconds,
}

/// Edit Mode Provider
class EditModeProvider extends ChangeNotifier {
  EditMode _mode = EditMode.slip;  // Default
  GridMode _gridMode = GridMode.absolute;
  GridResolution _gridResolution = GridResolution.beats;

  EditMode get mode => _mode;
  GridMode get gridMode => _gridMode;
  GridResolution get gridResolution => _gridResolution;

  /// Set edit mode
  void setMode(EditMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
  }

  /// Cycle to next mode
  void cycleMode() {
    final modes = EditMode.values;
    final nextIndex = (modes.indexOf(_mode) + 1) % modes.length;
    setMode(modes[nextIndex]);
  }

  /// Toggle grid absolute/relative
  void toggleGridMode() {
    _gridMode = _gridMode == GridMode.absolute
        ? GridMode.relative
        : GridMode.absolute;
    notifyListeners();
  }

  /// Set grid resolution
  void setGridResolution(GridResolution resolution) {
    if (_gridResolution != resolution) {
      _gridResolution = resolution;
      notifyListeners();
    }
  }

  /// Get grid size in samples
  int getGridSizeInSamples(double sampleRate, double bpm) {
    final samplesPerBeat = (sampleRate * 60.0) / bpm;

    switch (_gridResolution) {
      case GridResolution.bars:
        return (samplesPerBeat * 4).round();  // Assume 4/4
      case GridResolution.beats:
        return samplesPerBeat.round();
      case GridResolution.halfBeats:
        return (samplesPerBeat / 2).round();
      case GridResolution.quarterBeats:
        return (samplesPerBeat / 4).round();
      case GridResolution.eighthBeats:
        return (samplesPerBeat / 8).round();
      case GridResolution.ticks:
        return (samplesPerBeat / 480).round();  // 480 PPQ
      case GridResolution.samples:
        return 1;
      case GridResolution.frames:
        return (sampleRate / 30).round();  // 30fps
      case GridResolution.seconds:
        return sampleRate.round();
      case GridResolution.milliseconds:
        return (sampleRate / 1000).round();
    }
  }

  /// Snap position to grid
  int snapToGrid(int position, double sampleRate, double bpm) {
    if (_mode != EditMode.grid) return position;

    final gridSize = getGridSizeInSamples(sampleRate, bpm);

    if (_gridMode == GridMode.absolute) {
      // Snap to nearest grid line
      return ((position / gridSize).round() * gridSize);
    } else {
      // Relative - preserve offset (handled differently in move operations)
      return position;
    }
  }
}

/// Clip operations with edit mode awareness
class ClipOperations {
  final EditModeProvider editMode;
  final TimelineProvider timeline;

  ClipOperations(this.editMode, this.timeline);

  /// Delete clip(s) with mode-appropriate behavior
  void deleteClips(List<Clip> clips) {
    switch (editMode.mode) {
      case EditMode.shuffle:
        // Delete and shuffle remaining clips left
        _deleteAndShuffle(clips);
        break;

      case EditMode.slip:
      case EditMode.spot:
      case EditMode.grid:
        // Simple delete, leave gaps
        _deleteSimple(clips);
        break;
    }
  }

  /// Move clip with mode-appropriate behavior
  void moveClip(Clip clip, int newPosition) {
    switch (editMode.mode) {
      case EditMode.shuffle:
        // Insert at position, shuffle others
        _moveAndShuffle(clip, newPosition);
        break;

      case EditMode.slip:
        // Free movement
        clip.position = newPosition;
        break;

      case EditMode.spot:
        // Show dialog for exact position
        _showSpotDialog(clip);
        break;

      case EditMode.grid:
        // Snap to grid
        final snapped = editMode.snapToGrid(
          newPosition,
          timeline.sampleRate,
          timeline.bpm
        );
        clip.position = snapped;
        break;
    }
  }

  void _deleteAndShuffle(List<Clip> clips) {
    // Sort by position
    clips.sort((a, b) => a.position.compareTo(b.position));

    for (final clip in clips) {
      final track = clip.track;
      final deletedStart = clip.position;
      final deletedLength = clip.length;

      // Remove clip
      track.clips.remove(clip);

      // Shuffle remaining clips left
      for (final remaining in track.clips) {
        if (remaining.position > deletedStart) {
          remaining.position -= deletedLength;
        }
      }
    }
  }

  void _deleteSimple(List<Clip> clips) {
    for (final clip in clips) {
      clip.track.clips.remove(clip);
    }
  }
}

└─────────────────────────────────────────────────────────────┘
```

---

## 3. SMART TOOL (PRO TOOLS)

### 3.1 Koncept

```
┌─────────────────────────────────────────────────────────────┐
│ SMART TOOL — CONTEXT-AWARE MULTI-FUNCTION CURSOR            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Problem sa tradicionalnim alatima:                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Hoćeš da:                                               ││
│  │  1. Selektuješ → Klikni Selector tool                   ││
│  │  2. Pomeriš → Klikni Grabber tool                       ││
│  │  3. Skratiš → Klikni Trimmer tool                       ││
│  │  4. Fadeiraš → Klikni Fade tool                         ││
│  │                                                          ││
│  │  = Stalno menjanje alata = SPORO                        ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Smart Tool rešenje:                                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  JEDAN TOOL — funkcija zavisi od POZICIJE kursora       ││
│  │                                                          ││
│  │  Clip anatomy:                                           ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │                                                      │││
│  │  │  ┌──────────────────────────────────────────────┐   │││
│  │  │  │▲            ▲                            ▲│   │││
│  │  │  │ FADE IN    │    SELECTOR (I-beam)       │FADE│   │││
│  │  │  │ Zone       │    Zone (top half)         │OUT │   │││
│  │  │  │            │                            │Zone│   │││
│  │  │  ├────────────┼────────────────────────────┼────┤   │││
│  │  │  │ TRIM       │    GRABBER (hand)          │TRIM│   │││
│  │  │  │ Zone       │    Zone (bottom half)      │Zone│   │││
│  │  │  │ (resize ←) │    (move entire clip)      │(→) │   │││
│  │  │  └────────────┴────────────────────────────┴────┘   │││
│  │  │                                                      │││
│  │  │  Below clip: AUTOMATION (pencil)                    │││
│  │  │                                                      │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Zone breakdown (Pro Tools):                                 │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  TOP ROW (upper ~30% of clip):                          ││
│  │  • Top-left corner → Fade In handle                     ││
│  │  • Top-center → Selector (I-beam)                       ││
│  │  • Top-right corner → Fade Out handle                   ││
│  │                                                          ││
│  │  BOTTOM ROW (lower ~70% of clip):                       ││
│  │  • Left edge → Trim start                               ││
│  │  • Center → Grabber (move)                              ││
│  │  • Right edge → Trim end                                ││
│  │                                                          ││
│  │  BELOW CLIP:                                             ││
│  │  • Automation lane → Pencil for drawing                 ││
│  │                                                          ││
│  │  ABOVE CLIP:                                             ││
│  │  • Track header area → Track selection                  ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 FluxForge Implementation

```dart
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — SMART TOOL IMPLEMENTATION                       │
├─────────────────────────────────────────────────────────────┤

// flutter_ui/lib/widgets/timeline/smart_tool.dart

/// Smart Tool zone detection
enum SmartToolZone {
  /// Top-left corner - fade in
  fadeIn,

  /// Top-center - selection
  selector,

  /// Top-right corner - fade out
  fadeOut,

  /// Left edge - trim start
  trimStart,

  /// Center - grabber (move)
  grabber,

  /// Right edge - trim end
  trimEnd,

  /// Below clip - automation
  automation,

  /// Empty area - range selection
  rangeSelect,
}

/// Smart Tool zone detector
class SmartToolZoneDetector {
  /// Zone thresholds (in pixels)
  static const double cornerWidth = 20.0;
  static const double edgeWidth = 8.0;
  static const double topRowHeight = 0.3;  // 30% of clip height

  /// Detect which zone the cursor is in
  static SmartToolZone detectZone({
    required Offset cursorPosition,
    required Rect clipRect,
    required bool hasAutomation,
  }) {
    // Check if outside clip
    if (!clipRect.contains(cursorPosition)) {
      // Check if in automation lane (below clip)
      if (hasAutomation &&
          cursorPosition.dy > clipRect.bottom &&
          cursorPosition.dx >= clipRect.left &&
          cursorPosition.dx <= clipRect.right) {
        return SmartToolZone.automation;
      }
      return SmartToolZone.rangeSelect;
    }

    // Relative position within clip
    final relX = cursorPosition.dx - clipRect.left;
    final relY = cursorPosition.dy - clipRect.top;
    final clipWidth = clipRect.width;
    final clipHeight = clipRect.height;

    // Top row (upper 30%)
    if (relY < clipHeight * topRowHeight) {
      // Fade in zone (top-left corner)
      if (relX < cornerWidth) {
        return SmartToolZone.fadeIn;
      }
      // Fade out zone (top-right corner)
      if (relX > clipWidth - cornerWidth) {
        return SmartToolZone.fadeOut;
      }
      // Selector zone (top-center)
      return SmartToolZone.selector;
    }

    // Bottom row (lower 70%)
    // Trim start (left edge)
    if (relX < edgeWidth) {
      return SmartToolZone.trimStart;
    }
    // Trim end (right edge)
    if (relX > clipWidth - edgeWidth) {
      return SmartToolZone.trimEnd;
    }
    // Grabber (center)
    return SmartToolZone.grabber;
  }

  /// Get cursor for zone
  static MouseCursor getCursor(SmartToolZone zone) {
    switch (zone) {
      case SmartToolZone.fadeIn:
      case SmartToolZone.fadeOut:
        return SystemMouseCursors.resizeUpDown;

      case SmartToolZone.selector:
        return SystemMouseCursors.text;  // I-beam

      case SmartToolZone.trimStart:
        return SystemMouseCursors.resizeLeft;

      case SmartToolZone.trimEnd:
        return SystemMouseCursors.resizeRight;

      case SmartToolZone.grabber:
        return SystemMouseCursors.grab;

      case SmartToolZone.automation:
        return SystemMouseCursors.precise;  // Crosshair

      case SmartToolZone.rangeSelect:
        return SystemMouseCursors.text;  // I-beam
    }
  }
}

/// Smart Tool widget wrapper
class SmartToolClip extends StatefulWidget {
  final Clip clip;
  final Rect clipRect;
  final bool showAutomation;
  final Function(SmartToolZone zone, Offset position) onInteraction;

  const SmartToolClip({
    super.key,
    required this.clip,
    required this.clipRect,
    required this.showAutomation,
    required this.onInteraction,
  });

  @override
  State<SmartToolClip> createState() => _SmartToolClipState();
}

class _SmartToolClipState extends State<SmartToolClip> {
  SmartToolZone _currentZone = SmartToolZone.grabber;

  void _updateZone(Offset position) {
    final zone = SmartToolZoneDetector.detectZone(
      cursorPosition: position,
      clipRect: widget.clipRect,
      hasAutomation: widget.showAutomation,
    );

    if (zone != _currentZone) {
      setState(() => _currentZone = zone);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SmartToolZoneDetector.getCursor(_currentZone),
      onHover: (event) => _updateZone(event.localPosition),
      child: GestureDetector(
        onPanStart: (details) {
          widget.onInteraction(_currentZone, details.localPosition);
        },
        onPanUpdate: (details) {
          // Handle drag based on zone
          _handleDrag(_currentZone, details);
        },
        child: _buildClipVisual(),
      ),
    );
  }

  void _handleDrag(SmartToolZone zone, DragUpdateDetails details) {
    switch (zone) {
      case SmartToolZone.fadeIn:
        _adjustFadeIn(details.delta.dx);
        break;
      case SmartToolZone.fadeOut:
        _adjustFadeOut(details.delta.dx);
        break;
      case SmartToolZone.trimStart:
        _trimStart(details.delta.dx);
        break;
      case SmartToolZone.trimEnd:
        _trimEnd(details.delta.dx);
        break;
      case SmartToolZone.grabber:
        _moveClip(details.delta);
        break;
      case SmartToolZone.selector:
        _extendSelection(details.delta.dx);
        break;
      case SmartToolZone.automation:
        _drawAutomation(details.localPosition);
        break;
      case SmartToolZone.rangeSelect:
        _extendRangeSelection(details.delta.dx);
        break;
    }
  }

  Widget _buildClipVisual() {
    return CustomPaint(
      painter: ClipPainter(
        clip: widget.clip,
        highlightZone: _currentZone,  // Visual feedback
      ),
      size: widget.clipRect.size,
    );
  }
}

└─────────────────────────────────────────────────────────────┘
```

---

## 4. RAZOR EDITING (REAPER 7)

### 4.1 Koncept

```
┌─────────────────────────────────────────────────────────────┐
│ RAZOR EDITING — REAPER 7 REVOLUTIONARY FEATURE              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Problem sa tradicionalnim editingom:                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Hoćeš da obrišeš DELU više clipova:                    ││
│  │                                                          ││
│  │  Track 1: [====Clip A====][====Clip B====]              ││
│  │  Track 2: [======Clip C======][==Clip D==]              ││
│  │                                                          ││
│  │  Hoćeš da obrišeš sredinu (vertikalno kroz oba tracka): ││
│  │                                                          ││
│  │  Track 1: [====Clip A====][====Clip B====]              ││
│  │  Track 2: [======Clip C======][==Clip D==]              ││
│  │                    ↑    ↑                                ││
│  │                    DELETE THIS REGION                    ││
│  │                                                          ││
│  │  Tradicionalno moraš:                                    ││
│  │  1. Split Clip A na poziciji 1                          ││
│  │  2. Split Clip A na poziciji 2                          ││
│  │  3. Split Clip C na poziciji 1                          ││
│  │  4. Split Clip C na poziciji 2                          ││
│  │  5. Selektuj sva 4 srednja dela                         ││
│  │  6. Delete                                               ││
│  │                                                          ││
│  │  = 6 operacija za jednostavno brisanje!                 ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  RAZOR EDITING rešenje:                                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  1. Alt+Drag da nacrtaš "razor" selekciju:              ││
│  │                                                          ││
│  │  Track 1: [====░░░░░░░░░░░====Clip B====]              ││
│  │  Track 2: [====░░░░░░░░░░░====][==Clip D==]              ││
│  │                ↑         ↑                               ││
│  │                Razor selection (highlighted)             ││
│  │                                                          ││
│  │  2. Press Delete:                                        ││
│  │                                                          ││
│  │  Track 1: [====][====Clip B====]                        ││
│  │  Track 2: [====][==Clip D==]                            ││
│  │                                                          ││
│  │  = 2 operacije! (drag + delete)                         ││
│  │                                                          ││
│  │  Razor selection može:                                   ││
│  │  • Prelaziti granice clipova                            ││
│  │  • Obuhvatati više trackova                             ││
│  │  • Biti nepravilnog oblika (različite dužine po tracku) ││
│  │  • Copy/paste region (ne samo clipove)                  ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Razor Operations

```
┌─────────────────────────────────────────────────────────────┐
│ RAZOR EDITING — OPERACIJE                                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  CREATING RAZOR SELECTIONS:                                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Alt + Left-Click + Drag:                               ││
│  │  • Nacrtaj pravougaonu razor selekciju                  ││
│  │  • Može preko više trackova                             ││
│  │                                                          ││
│  │  Alt + Shift + Left-Click + Drag:                       ││
│  │  • Dodaj na postojeću razor selekciju                   ││
│  │  • Može biti na drugom tracku                           ││
│  │                                                          ││
│  │  Double-click na track (u praznom prostoru):            ││
│  │  • Razor select između najbližih clipova                ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  OPERATIONS ON RAZOR SELECTIONS:                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Delete:                                                 ││
│  │  • Briše sadržaj unutar razor selekcije                 ││
│  │  • Auto-split na granicama                              ││
│  │  • NE pomera ostale clipove (nije shuffle)              ││
│  │                                                          ││
│  │  Ctrl+X (Cut):                                           ││
│  │  • Iseče sadržaj, stavlja na clipboard                  ││
│  │  • Clipboard čuva relativne pozicije                    ││
│  │                                                          ││
│  │  Ctrl+C (Copy):                                          ││
│  │  • Kopira sadržaj, ne briše original                    ││
│  │                                                          ││
│  │  Ctrl+V (Paste):                                         ││
│  │  • Paste na poziciju kursora                            ││
│  │  • Zadržava relativne pozicije između trackova          ││
│  │                                                          ││
│  │  Drag razor selection:                                   ││
│  │  • Pomeri sadržaj na drugu poziciju                     ││
│  │  • Auto-split na granicama                              ││
│  │                                                          ││
│  │  Duplicate (Ctrl+D):                                     ││
│  │  • Kopira i paste odmah posle                           ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  VISUAL FEEDBACK:                                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Razor selection appearance:                             ││
│  │  • Semi-transparent overlay (orange/yellow)             ││
│  │  • Vertical lines at boundaries                         ││
│  │  • Resize handles at edges                              ││
│  │                                                          ││
│  │  Track 1: [====▓▓▓▓▓▓▓▓▓▓====Clip B====]               ││
│  │  Track 2: [====▓▓▓▓▓▓▓▓▓▓====][==Clip D==]               ││
│  │               │          │                               ││
│  │               │          └── Right edge (draggable)     ││
│  │               └───────────── Left edge (draggable)      ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 FluxForge Implementation

```dart
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — RAZOR EDITING IMPLEMENTATION                    │
├─────────────────────────────────────────────────────────────┤

// flutter_ui/lib/models/razor_selection.dart

/// Razor selection on a single track
class TrackRazorSelection {
  final String trackId;
  int startSample;
  int endSample;

  TrackRazorSelection({
    required this.trackId,
    required this.startSample,
    required this.endSample,
  });

  int get length => endSample - startSample;

  /// Check if position is within this selection
  bool contains(int sample) {
    return sample >= startSample && sample < endSample;
  }

  /// Check if overlaps with clip
  bool overlapsClip(Clip clip) {
    return startSample < clip.endSample && endSample > clip.startSample;
  }
}

/// Multi-track razor selection
class RazorSelection {
  final Map<String, TrackRazorSelection> _trackSelections = {};

  bool get isEmpty => _trackSelections.isEmpty;
  bool get isNotEmpty => _trackSelections.isNotEmpty;

  /// Add selection for track
  void addTrackSelection(TrackRazorSelection selection) {
    _trackSelections[selection.trackId] = selection;
  }

  /// Remove selection for track
  void removeTrackSelection(String trackId) {
    _trackSelections.remove(trackId);
  }

  /// Clear all selections
  void clear() {
    _trackSelections.clear();
  }

  /// Get selection for track
  TrackRazorSelection? getTrackSelection(String trackId) {
    return _trackSelections[trackId];
  }

  /// Get all affected tracks
  Iterable<String> get affectedTrackIds => _trackSelections.keys;

  /// Get global start (earliest across all tracks)
  int get globalStart {
    if (isEmpty) return 0;
    return _trackSelections.values
        .map((s) => s.startSample)
        .reduce((a, b) => a < b ? a : b);
  }

  /// Get global end (latest across all tracks)
  int get globalEnd {
    if (isEmpty) return 0;
    return _trackSelections.values
        .map((s) => s.endSample)
        .reduce((a, b) => a > b ? a : b);
  }
}

// flutter_ui/lib/providers/razor_provider.dart

/// Razor editing provider
class RazorProvider extends ChangeNotifier {
  RazorSelection _selection = RazorSelection();
  bool _isDrawing = false;
  String? _drawingStartTrackId;
  int? _drawingStartSample;

  RazorSelection get selection => _selection;
  bool get hasSelection => _selection.isNotEmpty;
  bool get isDrawing => _isDrawing;

  /// Start drawing razor selection
  void startDrawing(String trackId, int sample) {
    _isDrawing = true;
    _drawingStartTrackId = trackId;
    _drawingStartSample = sample;
    _selection.clear();
    notifyListeners();
  }

  /// Update drawing (as mouse moves)
  void updateDrawing(String currentTrackId, int currentSample,
                     List<Track> allTracks) {
    if (!_isDrawing) return;

    final startSample = _drawingStartSample!;
    final endSample = currentSample;

    // Determine sample range
    final minSample = startSample < endSample ? startSample : endSample;
    final maxSample = startSample > endSample ? startSample : endSample;

    // Find tracks in range
    final startTrackIndex = allTracks.indexWhere(
      (t) => t.id == _drawingStartTrackId
    );
    final endTrackIndex = allTracks.indexWhere(
      (t) => t.id == currentTrackId
    );

    final minTrackIndex = startTrackIndex < endTrackIndex
        ? startTrackIndex
        : endTrackIndex;
    final maxTrackIndex = startTrackIndex > endTrackIndex
        ? startTrackIndex
        : endTrackIndex;

    // Create selection for each track in range
    _selection.clear();
    for (int i = minTrackIndex; i <= maxTrackIndex; i++) {
      _selection.addTrackSelection(TrackRazorSelection(
        trackId: allTracks[i].id,
        startSample: minSample,
        endSample: maxSample,
      ));
    }

    notifyListeners();
  }

  /// Finish drawing
  void finishDrawing() {
    _isDrawing = false;
    _drawingStartTrackId = null;
    _drawingStartSample = null;
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selection.clear();
    notifyListeners();
  }

  /// Delete content within razor selection
  void deleteSelection(TimelineProvider timeline) {
    if (!hasSelection) return;

    for (final trackId in _selection.affectedTrackIds) {
      final trackSel = _selection.getTrackSelection(trackId)!;
      final track = timeline.getTrack(trackId);
      if (track == null) continue;

      // Find clips that overlap with selection
      final overlappingClips = track.clips
          .where((c) => trackSel.overlapsClip(c))
          .toList();

      for (final clip in overlappingClips) {
        if (clip.startSample >= trackSel.startSample &&
            clip.endSample <= trackSel.endSample) {
          // Clip entirely within selection - delete it
          track.clips.remove(clip);
        } else if (clip.startSample < trackSel.startSample &&
                   clip.endSample > trackSel.endSample) {
          // Selection is in middle of clip - split into two
          final leftPart = clip.copyWith(
            endSample: trackSel.startSample,
          );
          final rightPart = clip.copyWith(
            startSample: trackSel.endSample,
            sourceOffset: clip.sourceOffset +
                (trackSel.endSample - clip.startSample),
          );
          track.clips.remove(clip);
          track.clips.addAll([leftPart, rightPart]);
        } else if (clip.startSample < trackSel.startSample) {
          // Selection overlaps end of clip - trim end
          clip.endSample = trackSel.startSample;
        } else {
          // Selection overlaps start of clip - trim start
          final trimAmount = trackSel.endSample - clip.startSample;
          clip.sourceOffset += trimAmount;
          clip.startSample = trackSel.endSample;
        }
      }
    }

    _selection.clear();
    notifyListeners();
  }

  /// Copy selection to clipboard
  RazorClipboard copySelection(TimelineProvider timeline) {
    // ... implementation
  }

  /// Paste from clipboard
  void pasteFromClipboard(RazorClipboard clipboard, int position,
                          TimelineProvider timeline) {
    // ... implementation
  }
}

└─────────────────────────────────────────────────────────────┘
```

---

## 5. SWIPE COMPING (REAPER 7)

### 5.1 Koncept

```
┌─────────────────────────────────────────────────────────────┐
│ SWIPE COMPING — FASTEST COMPING WORKFLOW                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Scenario: Snimio si 5 take-ova vokala                      │
│  Cilj: Napraviti "comp" (composite) od najboljih delova     │
│                                                              │
│  Tradicionalni workflow:                                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  1. Importuj/snimi sve take-ove na jedan track          ││
│  │  2. Ručno seći na delove (split, split, split...)       ││
│  │  3. Slušaj svaki deo iz svakog take-a                   ││
│  │  4. Mute/delete loše delove                             ││
│  │  5. Pomeri dobre delove da se poklope                   ││
│  │  6. Crossfade na spojevima                              ││
│  │                                                          ││
│  │  = MNOGO posla za standardnu operaciju                  ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  SWIPE COMPING workflow:                                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Fixed Lanes prikaz:                                     ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ ┌─────────────────────────────────────────────────┐│││
│  │  │ │ COMP LANE (rezultat):                           ││││
│  │  │ │ [Take1][Take3][Take2][Take1][Take4]            ││││
│  │  │ └─────────────────────────────────────────────────┘│││
│  │  │ ─────────────────────────────────────────────────── │││
│  │  │ │ Take 1: [═══════════════════════════════════]   ││││
│  │  │ │ Take 2: [═══════════════════════════════════]   ││││
│  │  │ │ Take 3: [═══════════════════════════════════]   ││││
│  │  │ │ Take 4: [═══════════════════════════════════]   ││││
│  │  │ │ Take 5: [═══════════════════════════════════]   ││││
│  │  │ └─────────────────────────────────────────────────┘│││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  │  Workflow:                                               ││
│  │  1. Snimi take-ove (automatski idu na lane-ove)         ││
│  │  2. SWIPE preko lane-ova da izabereš koji deo           ││
│  │     • Click-drag preko Take 3 od bara 5-8               ││
│  │     • Ta sekcija ide u Comp Lane                        ││
│  │  3. Crossfades se auto-generišu                         ││
│  │  4. DONE!                                                ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Detailed Workflow

```
┌─────────────────────────────────────────────────────────────┐
│ SWIPE COMPING — STEP BY STEP                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  RECORDING PHASE:                                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Initial state:                                          ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ Track: [empty]                                      │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  │  After Take 1:                                           ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ Comp:   [Take 1══════════════════════════]          │││
│  │  │ Lane 1: [Take 1══════════════════════════]          │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  │  After Take 2 (loop record):                            ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ Comp:   [Take 2══════════════════════════]          │││
│  │  │ Lane 1: [Take 1══════════════════════════]          │││
│  │  │ Lane 2: [Take 2══════════════════════════]          │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  │  After Take 5:                                           ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ Comp:   [Take 5══════════════════════════]          │││
│  │  │ Lane 1: [Take 1══════════════════════════]          │││
│  │  │ Lane 2: [Take 2══════════════════════════]          │││
│  │  │ Lane 3: [Take 3══════════════════════════]          │││
│  │  │ Lane 4: [Take 4══════════════════════════]          │││
│  │  │ Lane 5: [Take 5══════════════════════════]          │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  COMPING PHASE (swipe):                                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Swipe across Lane 2 (bars 1-4):                        ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ Comp:   [Take 2▓▓▓▓][Take 5════════════]            │││
│  │  │ Lane 1: [Take 1══════════════════════════]          │││
│  │  │ Lane 2: [▓▓▓▓▓▓▓▓▓▓▓][═══════════════════]          │││
│  │  │          ↑ Selected                                  │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  │  Swipe across Lane 3 (bars 5-8):                        ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ Comp:   [Take 2][Take 3▓▓▓▓][Take 5════]            │││
│  │  │ Lane 1: [═══════════════════════════════]           │││
│  │  │ Lane 2: [═══════════════════════════════]           │││
│  │  │ Lane 3: [═════][▓▓▓▓▓▓▓▓▓▓][═══════════]           │││
│  │  │                 ↑ Selected                           │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  │  Final comp:                                             ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ Comp:   [Take 2][Take 3][Take 1][Take 4]            │││
│  │  │         ↗       ↗       ↗       ↗                   │││
│  │  │        Auto crossfades at boundaries                 │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 FluxForge Implementation

```dart
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — SWIPE COMPING IMPLEMENTATION                    │
├─────────────────────────────────────────────────────────────┤

// flutter_ui/lib/models/comp_lane.dart

/// A single take/lane in a comp track
class CompLane {
  final String id;
  final String name;
  final Clip sourceClip;
  final int laneIndex;

  CompLane({
    required this.id,
    required this.name,
    required this.sourceClip,
    required this.laneIndex,
  });
}

/// A segment in the comp (from a specific lane)
class CompSegment {
  final String laneId;
  int startSample;
  int endSample;

  /// Crossfade length at start (samples)
  int fadeInLength;

  /// Crossfade length at end (samples)
  int fadeOutLength;

  CompSegment({
    required this.laneId,
    required this.startSample,
    required this.endSample,
    this.fadeInLength = 0,
    this.fadeOutLength = 0,
  });

  int get length => endSample - startSample;
}

/// Comp track with lanes and segments
class CompTrack {
  final String id;
  final String name;
  final List<CompLane> lanes = [];
  final List<CompSegment> segments = [];

  /// Default crossfade length (samples)
  int defaultCrossfadeLength = 1024;  // ~21ms @ 48kHz

  CompTrack({required this.id, required this.name});

  /// Add a new lane (new take)
  void addLane(Clip clip, String name) {
    final lane = CompLane(
      id: '${id}_lane_${lanes.length}',
      name: name.isEmpty ? 'Take ${lanes.length + 1}' : name,
      sourceClip: clip,
      laneIndex: lanes.length,
    );
    lanes.add(lane);

    // If first lane, create initial segment covering entire clip
    if (lanes.length == 1) {
      segments.add(CompSegment(
        laneId: lane.id,
        startSample: clip.startSample,
        endSample: clip.endSample,
      ));
    }
  }

  /// Swipe to select portion of a lane
  void swipeSelect(String laneId, int startSample, int endSample) {
    // Find existing segments that overlap
    final overlapping = segments.where((s) =>
        s.startSample < endSample && s.endSample > startSample
    ).toList();

    // Remove overlapping segments
    for (final seg in overlapping) {
      // Check if segment should be split
      if (seg.startSample < startSample && seg.endSample > endSample) {
        // Split into two: before and after
        segments.remove(seg);
        segments.add(CompSegment(
          laneId: seg.laneId,
          startSample: seg.startSample,
          endSample: startSample,
          fadeOutLength: defaultCrossfadeLength,
        ));
        segments.add(CompSegment(
          laneId: seg.laneId,
          startSample: endSample,
          endSample: seg.endSample,
          fadeInLength: defaultCrossfadeLength,
        ));
      } else if (seg.startSample < startSample) {
        // Trim end
        seg.endSample = startSample;
        seg.fadeOutLength = defaultCrossfadeLength;
      } else if (seg.endSample > endSample) {
        // Trim start
        seg.startSample = endSample;
        seg.fadeInLength = defaultCrossfadeLength;
      } else {
        // Entirely within selection - remove
        segments.remove(seg);
      }
    }

    // Add new segment from selected lane
    segments.add(CompSegment(
      laneId: laneId,
      startSample: startSample,
      endSample: endSample,
      fadeInLength: defaultCrossfadeLength,
      fadeOutLength: defaultCrossfadeLength,
    ));

    // Sort segments by position
    segments.sort((a, b) => a.startSample.compareTo(b.startSample));

    // Merge adjacent segments from same lane
    _mergeAdjacentSegments();
  }

  void _mergeAdjacentSegments() {
    if (segments.length < 2) return;

    for (int i = segments.length - 1; i > 0; i--) {
      final current = segments[i];
      final previous = segments[i - 1];

      if (current.laneId == previous.laneId &&
          current.startSample == previous.endSample) {
        // Merge
        previous.endSample = current.endSample;
        previous.fadeOutLength = current.fadeOutLength;
        segments.removeAt(i);
      }
    }
  }

  /// Flatten comp to single clip
  Clip flatten(int sampleRate) {
    // Create new audio buffer
    final totalLength = segments.isEmpty ? 0 :
        segments.last.endSample - segments.first.startSample;

    final buffer = Float64List(totalLength);

    for (final segment in segments) {
      final lane = lanes.firstWhere((l) => l.id == segment.laneId);
      final sourceData = lane.sourceClip.audioData;

      // Copy with crossfades
      // ... crossfade implementation
    }

    return Clip(
      id: '${id}_flattened',
      audioData: buffer,
      startSample: segments.first.startSample,
    );
  }
}

// flutter_ui/lib/providers/comp_provider.dart

/// Comp editing provider
class CompProvider extends ChangeNotifier {
  final Map<String, CompTrack> _compTracks = {};
  bool _isSwiping = false;
  String? _swipingTrackId;
  String? _swipingLaneId;
  int? _swipeStartSample;

  /// Start swipe selection
  void startSwipe(String trackId, String laneId, int sample) {
    _isSwiping = true;
    _swipingTrackId = trackId;
    _swipingLaneId = laneId;
    _swipeStartSample = sample;
    notifyListeners();
  }

  /// Update swipe (as mouse moves)
  void updateSwipe(int currentSample) {
    if (!_isSwiping) return;

    // Visual feedback during swipe
    notifyListeners();
  }

  /// Finish swipe and apply selection
  void finishSwipe(int endSample) {
    if (!_isSwiping) return;

    final track = _compTracks[_swipingTrackId];
    if (track != null && _swipingLaneId != null) {
      final start = _swipeStartSample! < endSample
          ? _swipeStartSample!
          : endSample;
      final end = _swipeStartSample! > endSample
          ? _swipeStartSample!
          : endSample;

      track.swipeSelect(_swipingLaneId!, start, end);
    }

    _isSwiping = false;
    _swipingTrackId = null;
    _swipingLaneId = null;
    _swipeStartSample = null;
    notifyListeners();
  }
}

└─────────────────────────────────────────────────────────────┘
```

---

## 6. MODULATORS (CUBASE 14)

### 6.1 Koncept

```
┌─────────────────────────────────────────────────────────────┐
│ MODULATORS — CUBASE 14 GAME-CHANGER                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Šta su Modulators:                                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  SOURCE → TARGET                                         ││
│  │                                                          ││
│  │  Modulator generiše signal koji kontroliše              ││
│  │  BILO KOJI parametar BILO KOG plugina                   ││
│  │                                                          ││
│  │  Primeri:                                                ││
│  │  • LFO → Filter cutoff = Auto-wah                       ││
│  │  • Envelope Follower → Volume = Ducking                 ││
│  │  • Step Modulator → Pan = Auto-pan pattern              ││
│  │  • Envelope Shaper → Reverb send = Dynamic reverb       ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Modulator Types u Cubase:                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  1. LFO (Low Frequency Oscillator)                      ││
│  │     ├── Waveforms: Sine, Triangle, Saw, Square, S&H     ││
│  │     ├── Rate: 0.01 Hz - 100 Hz (ili tempo sync)        ││
│  │     ├── Retrigger: Free, Note-on, Transport            ││
│  │     └── Depth: 0-100%                                   ││
│  │                                                          ││
│  │  2. Envelope Follower                                    ││
│  │     ├── Source: Any track/bus (sidechain)              ││
│  │     ├── Attack: 0.1ms - 500ms                          ││
│  │     ├── Release: 1ms - 5000ms                          ││
│  │     └── Gain/Sensitivity                                ││
│  │                                                          ││
│  │  3. Envelope Shaper (ADSR)                              ││
│  │     ├── Attack: 0.1ms - 10s                            ││
│  │     ├── Decay: 0.1ms - 10s                             ││
│  │     ├── Sustain: 0-100%                                 ││
│  │     ├── Release: 0.1ms - 10s                           ││
│  │     └── Trigger: Note-on, Threshold, Manual            ││
│  │                                                          ││
│  │  4. Step Modulator                                       ││
│  │     ├── Steps: 1-64                                     ││
│  │     ├── Per-step value: -100% to +100%                 ││
│  │     ├── Rate: Tempo sync ili free                      ││
│  │     └── Smooth: Off, Glide, Ramp                       ││
│  │                                                          ││
│  │  5. ModScripter (Lua scripting)                         ││
│  │     ├── Custom Lua scripts                              ││
│  │     ├── Access to: Time, tempo, notes, params          ││
│  │     └── Examples: Random, math functions, logic        ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 Modulation Routing

```
┌─────────────────────────────────────────────────────────────┐
│ MODULATION ROUTING — TARGETS & MAPPING                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Target Selection:                                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Any VST3 plugin parameter can be a target:             ││
│  │                                                          ││
│  │  Track: Vocals                                           ││
│  │  ├── Insert 1: FluxForge EQ                             ││
│  │  │   ├── Band 1 Frequency  ← [Modulator target]        ││
│  │  │   ├── Band 1 Gain                                    ││
│  │  │   ├── Band 1 Q                                       ││
│  │  │   └── ...                                            ││
│  │  ├── Insert 2: FluxForge Compressor                     ││
│  │  │   ├── Threshold         ← [Modulator target]        ││
│  │  │   ├── Ratio                                          ││
│  │  │   ├── Attack                                         ││
│  │  │   └── ...                                            ││
│  │  ├── Volume                ← [Modulator target]         ││
│  │  ├── Pan                   ← [Modulator target]         ││
│  │  ├── Send 1 Level          ← [Modulator target]         ││
│  │  └── ...                                                 ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Modulation Amount & Mapping:                                │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Source → [Amount/Depth] → [Curve/Shape] → Target       ││
│  │                                                          ││
│  │  Amount: How much the modulator affects target          ││
│  │  • Bipolar: -100% to +100%                              ││
│  │  • Example: LFO at 50% depth on filter = ±50% range    ││
│  │                                                          ││
│  │  Curve/Shape: Response curve                             ││
│  │  • Linear (default)                                     ││
│  │  • Exponential                                          ││
│  │  • Logarithmic                                          ││
│  │  • S-Curve                                              ││
│  │  • Custom (drawable)                                    ││
│  │                                                          ││
│  │  Polarity:                                               ││
│  │  • Unipolar (0 to +1) — only positive                  ││
│  │  • Bipolar (-1 to +1) — both directions                ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Multiple Sources → One Target:                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  LFO ─────────┐                                         ││
│  │               │                                          ││
│  │  Env Follow ──┼──► [MIX] ──► Filter Cutoff              ││
│  │               │                                          ││
│  │  Step Mod ────┘                                         ││
│  │                                                          ││
│  │  Mix modes:                                              ││
│  │  • Add (sum)                                            ││
│  │  • Multiply                                             ││
│  │  • Max                                                  ││
│  │  • Min                                                  ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.3 FluxForge Implementation

```rust
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — MODULATION SYSTEM (rf-engine)                   │
├─────────────────────────────────────────────────────────────┤

// crates/rf-engine/src/modulation/mod.rs

/// Modulation source types
pub enum ModulatorType {
    /// Low Frequency Oscillator
    Lfo(LfoConfig),

    /// Envelope Follower (sidechain)
    EnvelopeFollower(EnvFollowerConfig),

    /// ADSR Envelope Shaper
    EnvelopeShaper(AdsrConfig),

    /// Step Sequencer
    StepModulator(StepConfig),

    /// Lua Script
    Script(ScriptConfig),
}

/// LFO Configuration
pub struct LfoConfig {
    pub waveform: LfoWaveform,
    pub rate_hz: f64,          // 0.01 - 100 Hz
    pub tempo_sync: bool,
    pub sync_division: f64,    // 1/4, 1/8, etc.
    pub phase: f64,            // 0-1
    pub retrigger: RetriggerMode,
}

#[derive(Clone, Copy)]
pub enum LfoWaveform {
    Sine,
    Triangle,
    Saw,
    Square,
    SampleAndHold,
}

#[derive(Clone, Copy)]
pub enum RetriggerMode {
    Free,          // Never reset
    NoteOn,        // Reset on MIDI note
    Transport,     // Reset on play
}

/// Envelope Follower Configuration
pub struct EnvFollowerConfig {
    pub source_bus_id: String,  // Sidechain source
    pub attack_ms: f64,         // 0.1 - 500
    pub release_ms: f64,        // 1 - 5000
    pub sensitivity_db: f64,    // Input gain
}

/// ADSR Configuration
pub struct AdsrConfig {
    pub attack_ms: f64,
    pub decay_ms: f64,
    pub sustain: f64,   // 0-1
    pub release_ms: f64,
    pub trigger: AdsrTrigger,
}

/// Step Modulator Configuration
pub struct StepConfig {
    pub steps: Vec<f64>,   // -1 to +1 per step
    pub rate_hz: f64,
    pub tempo_sync: bool,
    pub smoothing: StepSmoothing,
}

/// Modulation target
pub struct ModulationTarget {
    pub plugin_id: String,
    pub parameter_id: u32,
}

/// Modulation connection
pub struct ModulationConnection {
    pub source: ModulatorType,
    pub target: ModulationTarget,
    pub amount: f64,           // -1 to +1
    pub curve: ModulationCurve,
    pub polarity: Polarity,
}

/// Modulation processor
pub struct ModulationProcessor {
    connections: Vec<ModulationConnection>,
    lfo_phases: Vec<f64>,
    env_states: Vec<f64>,
}

impl ModulationProcessor {
    /// Process one sample of modulation
    pub fn process(&mut self,
                   sample_rate: f64,
                   tempo_bpm: f64,
                   sidechain_inputs: &HashMap<String, f64>)
                   -> Vec<(ModulationTarget, f64)> {
        let mut outputs = Vec::new();

        for (i, conn) in self.connections.iter().enumerate() {
            let raw_value = match &conn.source {
                ModulatorType::Lfo(cfg) => {
                    self.process_lfo(i, cfg, sample_rate, tempo_bpm)
                }
                ModulatorType::EnvelopeFollower(cfg) => {
                    let input = sidechain_inputs
                        .get(&cfg.source_bus_id)
                        .copied()
                        .unwrap_or(0.0);
                    self.process_env_follower(i, cfg, input, sample_rate)
                }
                ModulatorType::EnvelopeShaper(cfg) => {
                    self.process_adsr(i, cfg, sample_rate)
                }
                ModulatorType::StepModulator(cfg) => {
                    self.process_step(i, cfg, sample_rate, tempo_bpm)
                }
                ModulatorType::Script(_) => {
                    // Handled by rf-script
                    0.0
                }
            };

            // Apply amount, curve, and polarity
            let shaped = conn.curve.apply(raw_value);
            let scaled = shaped * conn.amount;
            let final_value = match conn.polarity {
                Polarity::Unipolar => (scaled + 1.0) * 0.5,
                Polarity::Bipolar => scaled,
            };

            outputs.push((conn.target.clone(), final_value));
        }

        outputs
    }

    fn process_lfo(&mut self,
                   index: usize,
                   cfg: &LfoConfig,
                   sample_rate: f64,
                   tempo_bpm: f64) -> f64 {
        // Calculate rate
        let rate = if cfg.tempo_sync {
            (tempo_bpm / 60.0) * cfg.sync_division
        } else {
            cfg.rate_hz
        };

        // Advance phase
        let phase_inc = rate / sample_rate;
        self.lfo_phases[index] = (self.lfo_phases[index] + phase_inc) % 1.0;
        let phase = self.lfo_phases[index];

        // Generate waveform
        match cfg.waveform {
            LfoWaveform::Sine => (phase * std::f64::consts::TAU).sin(),
            LfoWaveform::Triangle => {
                if phase < 0.5 {
                    4.0 * phase - 1.0
                } else {
                    3.0 - 4.0 * phase
                }
            }
            LfoWaveform::Saw => 2.0 * phase - 1.0,
            LfoWaveform::Square => if phase < 0.5 { 1.0 } else { -1.0 },
            LfoWaveform::SampleAndHold => {
                // Update on phase wrap
                // ... implementation
                0.0
            }
        }
    }

    fn process_env_follower(&mut self,
                            index: usize,
                            cfg: &EnvFollowerConfig,
                            input: f64,
                            sample_rate: f64) -> f64 {
        let input_abs = input.abs();
        let current = self.env_states[index];

        let coef = if input_abs > current {
            // Attack
            1.0 - (-1.0 / (cfg.attack_ms * 0.001 * sample_rate)).exp()
        } else {
            // Release
            1.0 - (-1.0 / (cfg.release_ms * 0.001 * sample_rate)).exp()
        };

        let new_value = current + coef * (input_abs - current);
        self.env_states[index] = new_value;

        // Convert to bipolar (-1 to +1)
        (new_value * 2.0 - 1.0).clamp(-1.0, 1.0)
    }
}

└─────────────────────────────────────────────────────────────┘
```

---

## 7. IMPLEMENTATION CHECKLIST

```
┌─────────────────────────────────────────────────────────────┐
│ WORKFLOW FEATURES — IMPLEMENTATION CHECKLIST                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ KEYBOARD FOCUS MODE:                                         │
│ [ ] KeyboardFocusProvider (toggle state)                    │
│ [ ] Command mapping (A-Z, F1-F12, 0-9)                      │
│ [ ] KeyboardFocusHandler widget                             │
│ [ ] UI indicator (toolbar button)                           │
│ [ ] On-screen help overlay                                  │
│ [ ] Preference: custom key mapping                          │
│                                                              │
│ EDIT MODES:                                                  │
│ [ ] EditModeProvider (Shuffle/Slip/Spot/Grid)               │
│ [ ] GridMode (Absolute/Relative)                            │
│ [ ] GridResolution options                                  │
│ [ ] Shuffle behavior (delete/insert)                        │
│ [ ] Spot dialog UI                                          │
│ [ ] Grid snapping logic                                     │
│ [ ] F1-F4 shortcuts                                         │
│                                                              │
│ SMART TOOL:                                                  │
│ [ ] SmartToolZoneDetector                                   │
│ [ ] Zone-specific cursors                                   │
│ [ ] Zone-specific drag handlers                             │
│ [ ] Visual feedback (highlight zones)                       │
│ [ ] Fade handle interaction                                 │
│ [ ] Trim interaction                                        │
│ [ ] Grab/move interaction                                   │
│                                                              │
│ RAZOR EDITING:                                               │
│ [ ] RazorSelection model                                    │
│ [ ] RazorProvider (drawing state)                           │
│ [ ] Alt+Drag to create selection                            │
│ [ ] Multi-track selection                                   │
│ [ ] Delete operation                                        │
│ [ ] Copy/paste operations                                   │
│ [ ] Visual overlay                                          │
│ [ ] Edge resize handles                                     │
│                                                              │
│ SWIPE COMPING:                                               │
│ [ ] CompTrack model                                         │
│ [ ] CompLane model                                          │
│ [ ] CompSegment model                                       │
│ [ ] CompProvider (swipe state)                              │
│ [ ] Lane recording (stacking takes)                         │
│ [ ] Swipe selection gesture                                 │
│ [ ] Auto crossfade generation                               │
│ [ ] Flatten to single clip                                  │
│ [ ] Visual lane display                                     │
│                                                              │
│ MODULATORS:                                                  │
│ [ ] ModulatorType enum                                      │
│ [ ] LFO processor                                           │
│ [ ] Envelope Follower processor                             │
│ [ ] ADSR processor                                          │
│ [ ] Step Modulator processor                                │
│ [ ] Modulation routing system                               │
│ [ ] Target parameter discovery                              │
│ [ ] Modulation amount/curve/polarity                        │
│ [ ] UI: Modulator editor panel                              │
│ [ ] UI: Target assignment                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0
**Date:** January 2026
**Source Analysis:**
- Pro Tools 2024: Keyboard Focus, Edit Modes, Smart Tool
- REAPER 7: Razor Editing, Swipe Comping
- Cubase Pro 14: Modulators
