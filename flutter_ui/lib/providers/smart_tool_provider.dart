// Smart Tool Provider — Ultimate Edition
//
// Combined best-of-all from Cubase + Pro Tools + Logic Pro X:
// - Pro Tools 6-zone Smart Tool (upper=range, lower=move)
// - Cubase volume handle (top-center) + sizing sub-modes
// - Logic Pro X loop handle (mid-right) + auto-crossfade mode
//
// ┌──────────────────────────────────────────────────────────────────┐
// │ ◢ FADE IN        ● VOLUME HANDLE            FADE OUT ◣          │ ← Zone 1-3: Top row (20%)
// │                                                                  │
// │              RANGE SELECT / SCRUB                                │ ← Zone 4: Upper body (30%)
// │              (I-beam cursor)                                     │
// ├──────────────────────────────────────────────────────────────────┤ ← 50% midpoint
// │              MOVE / SELECT                                       │ ← Zone 5: Lower body (30%)
// │              (Arrow/Hand cursor)                                 │
// │                                                                  │
// │ ◣ TRIM L ◢              ● LOOP                   ◢ TRIM R ◣     │ ← Zone 6-8: Bottom row (20%)
// └──────────────────────────────────────────────────────────────────┘
//                    ↕ CROSSFADE (between clips)                       ← Zone 9
//
// 9 Zones (priority order):
// 1. FADE IN (top-left corner)         — Drag = adjust fade in
// 2. FADE OUT (top-right corner)       — Drag = adjust fade out
// 3. VOLUME (top-center edge)          — Drag vertical = clip gain (Cubase)
// 4. TRIM LEFT (bottom-left edge)      — Drag = trim start
// 5. TRIM RIGHT (bottom-right edge)    — Drag = trim end
// 6. LOOP (bottom-center-right)        — Click = toggle loop (Logic)
// 7. CROSSFADE (between clips)         — Drag = crossfade duration
// 8. RANGE SELECT (upper body 50%)     — Click+drag = range selection (Pro Tools)
// 9. MOVE/SELECT (lower body 50%)      — Click = select, drag = move
//
// Modifiers (Combined best of Cubase + Pro Tools + Logic):
// - Shift: Constrain to time/track axis
// - Alt/Option + drag (Move): Copy clip
// - Alt/Option + click (Move): Split at cursor (Cubase)
// - Alt+Shift + drag (Move): Slip content (Cubase)
// - Alt + drag (Trim): Sizing moves contents (Cubase)
// - Ctrl/Cmd + drag: Fine adjustment (bypass snap)
// - Ctrl + click (Range): Scrub audio (Pro Tools)
//
// Edit Modes (5):
// - Shuffle (F1): True ripple — delete closes gap, insert pushes (Pro Tools)
// - Slip (F2): Free movement, overlap allowed
// - Spot (F3): Timecode dialog popup
// - Grid (F4): Snap to grid (absolute/relative sub-modes) (Cubase)
// - X-Fade (F5): Overlap auto-creates crossfade (Logic Pro X)
//
// Snap System (Combined):
// - Smart Snap: Adaptive to zoom level (Logic)
// - Grid snap: Bar/beat/division
// - Events snap: To other clip edges (Cubase)
// - Cursor snap: To playhead (Cubase)
// - Relative snap: Maintain offset from grid (Cubase Grid Relative)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Cubase-style clip movement constraint mode
///
/// Controls HOW clips behave during drag/move operations.
/// Separate concept from tool selection — modes modify drag behavior.
///
/// ┌──────────┬──────────┬──────────┬──────────┐
/// │ Shuffle  │  Slip    │  Spot    │  Grid    │
/// └──────────┴──────────┴──────────┴──────────┘
enum TimelineEditMode {
  /// Shuffle: True ripple editing (Pro Tools).
  /// Move pushes adjacent clips. Delete closes gap. Insert pushes right.
  shuffle,

  /// Slip: Drag adjusts audio content within clip boundaries.
  /// Clip position stays fixed, sourceOffset changes.
  slip,

  /// Spot: Clips snap to absolute timecode position on drop.
  /// Uses SMPTE-style positioning (frame-accurate).
  spot,

  /// Grid: Clips snap to grid positions during movement.
  /// Sub-modes: Absolute (snap TO grid) or Relative (maintain offset FROM grid).
  grid,

  /// X-Fade: Like Slip but overlap auto-creates crossfade (Logic Pro X).
  /// When two clips overlap, a crossfade is automatically generated.
  xFade,
}

/// Grid snap sub-mode (Cubase)
enum GridSnapMode {
  /// Snap clip TO exact grid positions
  absolute,

  /// Maintain clip's offset FROM grid during movement (Cubase Grid Relative)
  relative,
}

/// Snap targets — can be combined (Cubase-style cumulative snap)
enum SnapTarget {
  /// Snap to grid lines (bar/beat/division)
  grid,

  /// Snap to other clip edges (Cubase Events snap)
  events,

  /// Snap to playhead position (Cubase Magnetic Cursor)
  cursor,

  /// Snap to markers
  markers,

  /// Snap to detected transients (Pro Tools)
  transients,
}

/// Smart snap resolution — adaptive to zoom level (Logic Pro X)
enum SmartSnapResolution {
  /// Very far zoom: snap to bar boundaries
  bar,

  /// Far zoom: snap to beat boundaries
  beat,

  /// Medium zoom: snap to sub-beat divisions
  division,

  /// Close zoom: snap to ticks
  tick,

  /// Very close zoom: sample-level precision
  sample,
}

/// Cubase-style explicit tool selection (toolbar buttons / number keys)
enum TimelineEditTool {
  /// Smart Tool — context-aware (Pro Tools style, combines all modes)
  smart,

  /// Object Selection (V / 1) — select, move, resize clips
  objectSelect,

  /// Range Selection (R / 2) — select time ranges across tracks
  rangeSelect,

  /// Split / Scissors (S / 3) — split clips at click position
  split,

  /// Glue (G / 4) — join adjacent clips
  glue,

  /// Erase (E / 5) — delete clips on click
  erase,

  /// Zoom (Z / 6) — click to zoom in, Alt+click to zoom out
  zoom,

  /// Mute (M / 7) — mute/unmute clips on click
  mute,

  /// Draw / Pencil (D / 8) — draw automation, create empty clips
  draw,

  /// Play (P / 9) — click timeline position to start playback
  play,
}

/// Current tool determined by cursor position (9-zone system)
enum SmartToolMode {
  /// Move/select tool (lower body of clip — Pro Tools Grabber)
  select,

  /// Range select (upper body of clip — Pro Tools Selector)
  rangeSelectBody,

  /// Trim left edge (bottom-left)
  trimLeft,

  /// Trim right edge (bottom-right)
  trimRight,

  /// Fade in handle (top-left corner)
  fadeIn,

  /// Fade out handle (top-right corner)
  fadeOut,

  /// Volume handle (top-center edge — Cubase exclusive)
  volumeHandle,

  /// Loop handle (bottom-center-right — Logic Pro X exclusive)
  loopHandle,

  /// Crossfade between clips
  crossfade,

  /// Range selection (timeline background, outside clips)
  rangeSelect,

  /// Slip content (Alt+Shift drag — Cubase)
  slipContent,

  /// Scrub (Ctrl+click in range zone — Pro Tools)
  scrub,

  /// No specific tool (default arrow)
  none,
}

/// Mouse cursor for each tool mode
const Map<SmartToolMode, MouseCursor> kSmartToolCursors = {
  SmartToolMode.select: SystemMouseCursors.move,
  SmartToolMode.rangeSelectBody: SystemMouseCursors.text, // I-beam like Pro Tools Selector
  SmartToolMode.trimLeft: SystemMouseCursors.resizeLeft,
  SmartToolMode.trimRight: SystemMouseCursors.resizeRight,
  SmartToolMode.fadeIn: SystemMouseCursors.resizeUpLeft,
  SmartToolMode.fadeOut: SystemMouseCursors.resizeUpRight,
  SmartToolMode.volumeHandle: SystemMouseCursors.resizeUpDown, // Vertical drag for volume
  SmartToolMode.loopHandle: SystemMouseCursors.resizeRight, // Drag right to extend loop
  SmartToolMode.crossfade: SystemMouseCursors.resizeColumn,
  SmartToolMode.rangeSelect: SystemMouseCursors.cell,
  SmartToolMode.slipContent: SystemMouseCursors.resizeLeftRight, // H-resize for slip
  SmartToolMode.scrub: SystemMouseCursors.text,
  SmartToolMode.none: SystemMouseCursors.basic,
};

/// Zone configuration for smart tool detection (9-zone system)
class SmartToolZones {
  /// Percentage of clip width for trim zones (left/right edges)
  final double trimZonePercent;

  /// Percentage of clip height for top row (fades + volume)
  final double topRowPercent;

  /// Percentage of clip height for bottom row (trim + loop)
  final double bottomRowPercent;

  /// Percentage of clip width for fade handle corners
  final double fadeCornerPercent;

  /// Percentage of clip width for loop handle zone (from right edge)
  final double loopZonePercent;

  /// Minimum pixel width for trim zone (even on short clips)
  final double minTrimZonePixels;

  /// Minimum pixel height for zone rows
  final double minZoneRowPixels;

  /// Body midpoint — above = range select, below = move/select (Pro Tools split)
  final double bodyMidpoint;

  const SmartToolZones({
    this.trimZonePercent = 0.12, // 12% each side for trim
    this.topRowPercent = 0.20, // Top 20% for fades + volume
    this.bottomRowPercent = 0.20, // Bottom 20% for trim + loop
    this.fadeCornerPercent = 0.20, // 20% width for fade corners
    this.loopZonePercent = 0.15, // 15% width for loop handle
    this.minTrimZonePixels = 8.0,
    this.minZoneRowPixels = 10.0,
    this.bodyMidpoint = 0.50, // 50% of body = range/select split
  });

  /// Get fadeZonePercent (backwards compatibility)
  double get fadeZonePercent => topRowPercent;
}

/// Result of smart tool hit test
class SmartToolHitResult {
  final SmartToolMode mode;
  final MouseCursor cursor;
  final String? clipId;
  final String? trackId;
  final Offset localPosition;
  final Rect? clipBounds;

  const SmartToolHitResult({
    required this.mode,
    required this.cursor,
    this.clipId,
    this.trackId,
    required this.localPosition,
    this.clipBounds,
  });

  static const none = SmartToolHitResult(
    mode: SmartToolMode.none,
    cursor: SystemMouseCursors.basic,
    localPosition: Offset.zero,
  );
}

/// Drag operation state
class SmartToolDragState {
  final SmartToolMode mode;
  final String? clipId;
  final Offset startPosition;
  final Offset currentPosition;
  final Rect originalBounds;
  final bool isShiftHeld;
  final bool isAltHeld;
  final bool isCmdHeld;

  const SmartToolDragState({
    required this.mode,
    this.clipId,
    required this.startPosition,
    required this.currentPosition,
    required this.originalBounds,
    this.isShiftHeld = false,
    this.isAltHeld = false,
    this.isCmdHeld = false,
  });

  /// Get drag delta
  Offset get delta => currentPosition - startPosition;

  /// Get constrained delta (for shift modifier)
  Offset get constrainedDelta {
    if (!isShiftHeld) return delta;

    // Constrain to dominant axis
    if (delta.dx.abs() > delta.dy.abs()) {
      return Offset(delta.dx, 0);
    } else {
      return Offset(0, delta.dy);
    }
  }

  SmartToolDragState copyWith({
    SmartToolMode? mode,
    String? clipId,
    Offset? startPosition,
    Offset? currentPosition,
    Rect? originalBounds,
    bool? isShiftHeld,
    bool? isAltHeld,
    bool? isCmdHeld,
  }) {
    return SmartToolDragState(
      mode: mode ?? this.mode,
      clipId: clipId ?? this.clipId,
      startPosition: startPosition ?? this.startPosition,
      currentPosition: currentPosition ?? this.currentPosition,
      originalBounds: originalBounds ?? this.originalBounds,
      isShiftHeld: isShiftHeld ?? this.isShiftHeld,
      isAltHeld: isAltHeld ?? this.isAltHeld,
      isCmdHeld: isCmdHeld ?? this.isCmdHeld,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Smart Tool Provider
///
/// Manages context-aware tool selection based on cursor position
/// within clips on the timeline.
class SmartToolProvider extends ChangeNotifier {
  // Configuration
  SmartToolZones _zones = const SmartToolZones();

  // Current state
  SmartToolMode _currentMode = SmartToolMode.none;
  MouseCursor _currentCursor = SystemMouseCursors.basic;
  SmartToolDragState? _dragState;
  SmartToolHitResult? _lastHitResult;

  // Smart tool enabled
  bool _enabled = true;

  // ═══ Cubase-style explicit tool selection ═══
  TimelineEditTool _activeTool = TimelineEditTool.smart;

  // ═══ Edit mode (clip movement constraint) — 5 modes ═══
  TimelineEditMode _activeEditMode = TimelineEditMode.grid;

  // ═══ Snap system ═══
  GridSnapMode _gridSnapMode = GridSnapMode.absolute;
  Set<SnapTarget> _activeSnapTargets = {SnapTarget.grid};
  bool _smartSnapEnabled = true; // Logic-style adaptive snap

  // ═══ Getters ═══

  SmartToolZones get zones => _zones;
  SmartToolMode get currentMode => _currentMode;
  MouseCursor get currentCursor => _currentCursor;
  SmartToolDragState? get dragState => _dragState;
  SmartToolHitResult? get lastHitResult => _lastHitResult;
  bool get enabled => _enabled;
  bool get isDragging => _dragState != null;
  TimelineEditTool get activeTool => _activeTool;
  TimelineEditMode get activeEditMode => _activeEditMode;
  GridSnapMode get gridSnapMode => _gridSnapMode;
  Set<SnapTarget> get activeSnapTargets => _activeSnapTargets;
  bool get smartSnapEnabled => _smartSnapEnabled;

  /// Whether the active tool is Smart Tool (context-aware)
  bool get isSmartToolActive => _activeTool == TimelineEditTool.smart;

  /// Whether the active tool is Object Select (acts like smart tool but explicit)
  bool get isObjectSelectActive => _activeTool == TimelineEditTool.objectSelect;

  // ═══ Configuration ═══

  /// Set zone configuration
  void setZones(SmartToolZones zones) {
    _zones = zones;
    notifyListeners();
  }

  /// Enable/disable smart tool
  void setEnabled(bool enabled) {
    if (_enabled != enabled) {
      _enabled = enabled;
      if (!enabled) {
        _currentMode = SmartToolMode.none;
        _currentCursor = SystemMouseCursors.basic;
      }
      notifyListeners();
    }
  }

  /// Toggle smart tool
  void toggle() => setEnabled(!_enabled);

  // ═══ Cubase Tool Selection ═══

  /// Set active edit tool (Cubase-style toolbar)
  void setActiveTool(TimelineEditTool tool) {
    if (_activeTool != tool) {
      _activeTool = tool;
      // Smart tool and object select use context-aware mode
      // All others override cursor
      if (tool == TimelineEditTool.smart || tool == TimelineEditTool.objectSelect) {
        _enabled = true;
      }
      notifyListeners();
    }
  }

  // ═══ Edit Mode (Clip Movement Constraint) ═══

  /// Set active edit mode (Shuffle/Slip/Spot/Grid)
  void setActiveEditMode(TimelineEditMode mode) {
    if (_activeEditMode != mode) {
      _activeEditMode = mode;
      notifyListeners();
    }
  }

  /// Get display name for an edit mode
  static String editModeDisplayName(TimelineEditMode mode) {
    switch (mode) {
      case TimelineEditMode.shuffle: return 'Shuffle';
      case TimelineEditMode.slip: return 'Slip';
      case TimelineEditMode.spot: return 'Spot';
      case TimelineEditMode.grid: return 'Grid';
      case TimelineEditMode.xFade: return 'X-Fade';
    }
  }

  /// Get icon for an edit mode
  static IconData editModeIcon(TimelineEditMode mode) {
    switch (mode) {
      case TimelineEditMode.shuffle: return Icons.swap_horiz;
      case TimelineEditMode.slip: return Icons.unfold_more;
      case TimelineEditMode.spot: return Icons.my_location;
      case TimelineEditMode.grid: return Icons.grid_4x4;
      case TimelineEditMode.xFade: return Icons.compare_arrows;
    }
  }

  /// Get tooltip for an edit mode
  static String editModeTooltip(TimelineEditMode mode) {
    switch (mode) {
      case TimelineEditMode.shuffle:
        return 'Shuffle — true ripple: move pushes, delete closes gap (Pro Tools)';
      case TimelineEditMode.slip:
        return 'Slip — drag adjusts audio content within clip';
      case TimelineEditMode.spot:
        return 'Spot — clips snap to absolute timecode position';
      case TimelineEditMode.grid:
        return 'Grid — clips snap to grid lines (Absolute/Relative)';
      case TimelineEditMode.xFade:
        return 'X-Fade — overlap auto-creates crossfade (Logic Pro X)';
    }
  }

  // ═══ Snap System ═══

  /// Set grid snap sub-mode (Absolute/Relative)
  void setGridSnapMode(GridSnapMode mode) {
    if (_gridSnapMode != mode) {
      _gridSnapMode = mode;
      notifyListeners();
    }
  }

  /// Toggle a snap target on/off
  void toggleSnapTarget(SnapTarget target) {
    if (_activeSnapTargets.contains(target)) {
      _activeSnapTargets = Set.from(_activeSnapTargets)..remove(target);
    } else {
      _activeSnapTargets = Set.from(_activeSnapTargets)..add(target);
    }
    notifyListeners();
  }

  /// Set snap targets
  void setSnapTargets(Set<SnapTarget> targets) {
    _activeSnapTargets = Set.from(targets);
    notifyListeners();
  }

  /// Toggle smart snap (Logic-style adaptive to zoom)
  void toggleSmartSnap() {
    _smartSnapEnabled = !_smartSnapEnabled;
    notifyListeners();
  }

  /// Get smart snap resolution based on zoom level (Logic Pro X)
  SmartSnapResolution getSmartSnapResolution(double pixelsPerBeat) {
    if (pixelsPerBeat < 5) return SmartSnapResolution.bar;
    if (pixelsPerBeat < 15) return SmartSnapResolution.beat;
    if (pixelsPerBeat < 50) return SmartSnapResolution.division;
    if (pixelsPerBeat < 200) return SmartSnapResolution.tick;
    return SmartSnapResolution.sample;
  }

  /// Check if a specific snap target is active
  bool isSnapTargetActive(SnapTarget target) =>
      _activeSnapTargets.contains(target);

  /// Get display name for snap target
  static String snapTargetName(SnapTarget target) {
    switch (target) {
      case SnapTarget.grid: return 'Grid';
      case SnapTarget.events: return 'Events';
      case SnapTarget.cursor: return 'Cursor';
      case SnapTarget.markers: return 'Markers';
      case SnapTarget.transients: return 'Transients';
    }
  }

  /// Get cursor for active tool (when not in smart/objectSelect mode)
  MouseCursor get activeToolCursor {
    switch (_activeTool) {
      case TimelineEditTool.smart:
      case TimelineEditTool.objectSelect:
        return _currentCursor; // Context-aware
      case TimelineEditTool.rangeSelect:
        return SystemMouseCursors.cell;
      case TimelineEditTool.split:
        return SystemMouseCursors.click;
      case TimelineEditTool.glue:
        return SystemMouseCursors.click;
      case TimelineEditTool.erase:
        return SystemMouseCursors.disappearing;
      case TimelineEditTool.zoom:
        return SystemMouseCursors.zoomIn;
      case TimelineEditTool.mute:
        return SystemMouseCursors.click;
      case TimelineEditTool.draw:
        return SystemMouseCursors.precise;
      case TimelineEditTool.play:
        return SystemMouseCursors.click;
    }
  }

  /// Get display name for a tool
  static String toolDisplayName(TimelineEditTool tool) {
    switch (tool) {
      case TimelineEditTool.smart: return 'Smart Tool';
      case TimelineEditTool.objectSelect: return 'Select';
      case TimelineEditTool.rangeSelect: return 'Range';
      case TimelineEditTool.split: return 'Split';
      case TimelineEditTool.glue: return 'Glue';
      case TimelineEditTool.erase: return 'Erase';
      case TimelineEditTool.zoom: return 'Zoom';
      case TimelineEditTool.mute: return 'Mute';
      case TimelineEditTool.draw: return 'Draw';
      case TimelineEditTool.play: return 'Play';
    }
  }

  /// Get icon for a tool
  static IconData toolIcon(TimelineEditTool tool) {
    switch (tool) {
      case TimelineEditTool.smart: return Icons.smart_button;
      case TimelineEditTool.objectSelect: return Icons.near_me;
      case TimelineEditTool.rangeSelect: return Icons.select_all;
      case TimelineEditTool.split: return Icons.content_cut;
      case TimelineEditTool.glue: return Icons.link;
      case TimelineEditTool.erase: return Icons.auto_fix_off;
      case TimelineEditTool.zoom: return Icons.zoom_in;
      case TimelineEditTool.mute: return Icons.volume_off;
      case TimelineEditTool.draw: return Icons.edit;
      case TimelineEditTool.play: return Icons.play_arrow;
    }
  }

  /// Get keyboard shortcut label for a tool
  static String toolShortcut(TimelineEditTool tool) {
    switch (tool) {
      case TimelineEditTool.smart: return '1';
      case TimelineEditTool.objectSelect: return '2';
      case TimelineEditTool.rangeSelect: return '3';
      case TimelineEditTool.split: return '4';
      case TimelineEditTool.glue: return '5';
      case TimelineEditTool.erase: return '6';
      case TimelineEditTool.zoom: return '7';
      case TimelineEditTool.mute: return '8';
      case TimelineEditTool.draw: return '9';
      case TimelineEditTool.play: return '0';
    }
  }

  // ═══ Hit Testing (9-Zone System) ═══

  /// Determine tool mode based on position within clip.
  ///
  /// 9-zone priority order (highest to lowest):
  /// 1. Fade In (top-left corner)
  /// 2. Fade Out (top-right corner)
  /// 3. Volume Handle (top-center)
  /// 4. Trim Left (bottom-left edge)
  /// 5. Trim Right (bottom-right edge)
  /// 6. Loop Handle (bottom-center-right)
  /// 7. Crossfade (between clips)
  /// 8. Range Select (upper body)
  /// 9. Move/Select (lower body)
  SmartToolHitResult hitTest({
    required Offset position,
    required Rect clipBounds,
    String? clipId,
    String? trackId,
    bool hasLeftNeighbor = false,
    bool hasRightNeighbor = false,
    double? fadeInEnd,
    double? fadeOutStart,
    bool isLooping = false,
  }) {
    if (!_enabled) {
      return SmartToolHitResult.none;
    }

    // Check if position is within clip bounds
    if (!clipBounds.contains(position)) {
      return SmartToolHitResult(
        mode: SmartToolMode.rangeSelect,
        cursor: SystemMouseCursors.cell,
        localPosition: position,
      );
    }

    // Calculate local position within clip
    final local = Offset(
      position.dx - clipBounds.left,
      position.dy - clipBounds.top,
    );

    final width = clipBounds.width;
    final height = clipBounds.height;

    // Calculate zone boundaries
    final topRowHeight = (height * _zones.topRowPercent)
        .clamp(_zones.minZoneRowPixels, height * 0.35);
    final bottomRowHeight = (height * _zones.bottomRowPercent)
        .clamp(_zones.minZoneRowPixels, height * 0.35);
    final bottomRowTop = height - bottomRowHeight;
    final fadeCornerWidth = (width * _zones.fadeCornerPercent)
        .clamp(_zones.minTrimZonePixels, width * 0.30);
    final trimZoneWidth = (width * _zones.trimZonePercent)
        .clamp(_zones.minTrimZonePixels, width * 0.25);
    final loopZoneWidth = (width * _zones.loopZonePercent)
        .clamp(_zones.minTrimZonePixels, width * 0.20);

    // Body zone (between top and bottom rows)
    final bodyTop = topRowHeight;
    final bodyBottom = bottomRowTop;
    final bodyHeight = bodyBottom - bodyTop;
    final bodyMidY = bodyTop + bodyHeight * _zones.bodyMidpoint;

    // ─── ZONE 1-3: TOP ROW (fades + volume) ───
    if (local.dy < topRowHeight) {
      // Fade In — top-left corner
      if (local.dx < fadeCornerWidth) {
        return SmartToolHitResult(
          mode: SmartToolMode.fadeIn,
          cursor: SystemMouseCursors.resizeUpLeft,
          clipId: clipId,
          trackId: trackId,
          localPosition: local,
          clipBounds: clipBounds,
        );
      }

      // Fade Out — top-right corner
      if (local.dx > width - fadeCornerWidth) {
        return SmartToolHitResult(
          mode: SmartToolMode.fadeOut,
          cursor: SystemMouseCursors.resizeUpRight,
          clipId: clipId,
          trackId: trackId,
          localPosition: local,
          clipBounds: clipBounds,
        );
      }

      // Volume Handle — top-center (between fade corners)
      return SmartToolHitResult(
        mode: SmartToolMode.volumeHandle,
        cursor: SystemMouseCursors.resizeUpDown,
        clipId: clipId,
        trackId: trackId,
        localPosition: local,
        clipBounds: clipBounds,
      );
    }

    // ─── ZONE 6-8: BOTTOM ROW (trim + loop) ───
    if (local.dy > bottomRowTop) {
      // Trim Left — bottom-left edge
      if (local.dx < trimZoneWidth) {
        // Check for crossfade with left neighbor
        if (hasLeftNeighbor && local.dx < trimZoneWidth * 0.5) {
          return SmartToolHitResult(
            mode: SmartToolMode.crossfade,
            cursor: SystemMouseCursors.resizeColumn,
            clipId: clipId,
            trackId: trackId,
            localPosition: local,
            clipBounds: clipBounds,
          );
        }
        return SmartToolHitResult(
          mode: SmartToolMode.trimLeft,
          cursor: SystemMouseCursors.resizeLeft,
          clipId: clipId,
          trackId: trackId,
          localPosition: local,
          clipBounds: clipBounds,
        );
      }

      // Trim Right — bottom-right edge
      if (local.dx > width - trimZoneWidth) {
        // Check for crossfade with right neighbor
        if (hasRightNeighbor && local.dx > width - trimZoneWidth * 0.5) {
          return SmartToolHitResult(
            mode: SmartToolMode.crossfade,
            cursor: SystemMouseCursors.resizeColumn,
            clipId: clipId,
            trackId: trackId,
            localPosition: local,
            clipBounds: clipBounds,
          );
        }
        return SmartToolHitResult(
          mode: SmartToolMode.trimRight,
          cursor: SystemMouseCursors.resizeRight,
          clipId: clipId,
          trackId: trackId,
          localPosition: local,
          clipBounds: clipBounds,
        );
      }

      // Loop Handle — bottom-center-right area
      if (local.dx > width - trimZoneWidth - loopZoneWidth &&
          local.dx < width - trimZoneWidth) {
        return SmartToolHitResult(
          mode: SmartToolMode.loopHandle,
          cursor: SystemMouseCursors.resizeRight,
          clipId: clipId,
          trackId: trackId,
          localPosition: local,
          clipBounds: clipBounds,
        );
      }

      // Bottom body area (between trim zones) — defaults to move
      return SmartToolHitResult(
        mode: SmartToolMode.select,
        cursor: SystemMouseCursors.move,
        clipId: clipId,
        trackId: trackId,
        localPosition: local,
        clipBounds: clipBounds,
      );
    }

    // ─── ZONE 4-5: BODY (range select upper / move lower) ───
    // Pro Tools-style upper/lower body split
    if (local.dy < bodyMidY) {
      // Upper body — Range Select (Pro Tools Selector / I-beam)
      return SmartToolHitResult(
        mode: SmartToolMode.rangeSelectBody,
        cursor: SystemMouseCursors.text,
        clipId: clipId,
        trackId: trackId,
        localPosition: local,
        clipBounds: clipBounds,
      );
    }

    // Lower body — Move/Select (Pro Tools Grabber / hand)
    return SmartToolHitResult(
      mode: SmartToolMode.select,
      cursor: SystemMouseCursors.move,
      clipId: clipId,
      trackId: trackId,
      localPosition: local,
      clipBounds: clipBounds,
    );
  }

  /// Update cursor based on hover position
  void updateHover(SmartToolHitResult result) {
    _lastHitResult = result;
    _currentMode = result.mode;
    _currentCursor = result.cursor;
    notifyListeners();
  }

  /// Clear hover state
  void clearHover() {
    _lastHitResult = null;
    _currentMode = SmartToolMode.none;
    _currentCursor = SystemMouseCursors.basic;
    notifyListeners();
  }

  // ═══ Drag Operations ═══

  /// Start drag operation
  ///
  /// Modifier key combinations (Cubase + Pro Tools):
  /// - Alt + drag in Move zone = Copy clip
  /// - Alt + Shift + drag in Move zone = Slip content (Cubase)
  /// - Alt + drag in Trim zone = Sizing moves contents
  /// - Ctrl + click in Range zone = Scrub (Pro Tools)
  void startDrag({
    required SmartToolHitResult hitResult,
    required Offset position,
    required Rect clipBounds,
  }) {
    if (!_enabled || hitResult.mode == SmartToolMode.none) return;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    // Modifier-based mode overrides
    SmartToolMode resolvedMode = hitResult.mode;

    // Alt+Shift in move zone = Slip Content (Cubase)
    if (resolvedMode == SmartToolMode.select && isAlt && isShift) {
      resolvedMode = SmartToolMode.slipContent;
    }

    // Ctrl+click in range zone = Scrub (Pro Tools)
    if (resolvedMode == SmartToolMode.rangeSelectBody && isCmd) {
      resolvedMode = SmartToolMode.scrub;
    }

    _dragState = SmartToolDragState(
      mode: resolvedMode,
      clipId: hitResult.clipId,
      startPosition: position,
      currentPosition: position,
      originalBounds: clipBounds,
      isShiftHeld: isShift,
      isAltHeld: isAlt,
      isCmdHeld: isCmd,
    );

    notifyListeners();
  }

  /// Update drag operation
  void updateDrag(Offset position) {
    if (_dragState == null) return;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    _dragState = _dragState!.copyWith(
      currentPosition: position,
      isShiftHeld: isShift,
      isAltHeld: isAlt,
      isCmdHeld: isCmd,
    );

    notifyListeners();
  }

  /// End drag operation
  void endDrag() {
    if (_dragState == null) return;
    _dragState = null;
    notifyListeners();
  }

  /// Cancel drag operation
  void cancelDrag() {
    _dragState = null;
    notifyListeners();
  }

  // ═══ UI Helpers ═══

  /// Get display name for current mode
  String get modeDisplayName {
    switch (_currentMode) {
      case SmartToolMode.select:
        return 'Move';
      case SmartToolMode.rangeSelectBody:
        return 'Range';
      case SmartToolMode.trimLeft:
        return 'Trim Left';
      case SmartToolMode.trimRight:
        return 'Trim Right';
      case SmartToolMode.fadeIn:
        return 'Fade In';
      case SmartToolMode.fadeOut:
        return 'Fade Out';
      case SmartToolMode.volumeHandle:
        return 'Volume';
      case SmartToolMode.loopHandle:
        return 'Loop';
      case SmartToolMode.crossfade:
        return 'Crossfade';
      case SmartToolMode.rangeSelect:
        return 'Range Select';
      case SmartToolMode.slipContent:
        return 'Slip';
      case SmartToolMode.scrub:
        return 'Scrub';
      case SmartToolMode.none:
        return 'Smart Tool';
    }
  }

  /// Get icon for current mode
  IconData get modeIcon {
    switch (_currentMode) {
      case SmartToolMode.select:
        return Icons.open_with;
      case SmartToolMode.rangeSelectBody:
        return Icons.select_all;
      case SmartToolMode.trimLeft:
      case SmartToolMode.trimRight:
        return Icons.content_cut;
      case SmartToolMode.fadeIn:
      case SmartToolMode.fadeOut:
        return Icons.gradient;
      case SmartToolMode.volumeHandle:
        return Icons.volume_up;
      case SmartToolMode.loopHandle:
        return Icons.loop;
      case SmartToolMode.crossfade:
        return Icons.compare_arrows;
      case SmartToolMode.rangeSelect:
        return Icons.select_all;
      case SmartToolMode.slipContent:
        return Icons.unfold_more;
      case SmartToolMode.scrub:
        return Icons.swap_horiz;
      case SmartToolMode.none:
        return Icons.smart_button;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Smart Tool Indicator
// ═══════════════════════════════════════════════════════════════════════════════

/// Visual indicator showing current smart tool mode
class SmartToolIndicator extends StatelessWidget {
  final SmartToolProvider provider;
  final VoidCallback? onTap;

  const SmartToolIndicator({
    super.key,
    required this.provider,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final isActive = provider.enabled;
        final mode = provider.currentMode;

        return GestureDetector(
          onTap: onTap ?? provider.toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF4a9eff).withValues(alpha: 0.1)
                  : const Color(0xFF1a1a20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF4a9eff)
                    : const Color(0xFF3a3a40),
                width: isActive ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  provider.modeIcon,
                  size: 16,
                  color: isActive
                      ? const Color(0xFF4a9eff)
                      : const Color(0xFF808090),
                ),
                const SizedBox(width: 6),
                Text(
                  mode == SmartToolMode.none
                      ? 'Smart'
                      : provider.modeDisplayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? const Color(0xFF4a9eff)
                        : const Color(0xFF808090),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Smart Tool Cursor Wrapper
// ═══════════════════════════════════════════════════════════════════════════════

/// Wrapper widget that applies smart tool cursor
class SmartToolCursor extends StatelessWidget {
  final SmartToolProvider provider;
  final Widget child;

  const SmartToolCursor({
    super.key,
    required this.provider,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        return MouseRegion(
          cursor: provider.currentCursor,
          child: child,
        );
      },
    );
  }
}

