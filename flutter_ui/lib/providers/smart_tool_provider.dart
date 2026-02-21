// Smart Tool Provider
//
// Pro Tools-style Smart Tool that combines multiple tools into one
// with context-aware cursor behavior based on position within clip.
//
// ┌────────────────────────────────────────────────────────────────┐
// │  CLIP                                                          │
// │  ┌──────┬──────────────────────────────────────────────┬──────┤
// │  │ TRIM │              SELECT/MOVE                     │ TRIM │
// │  │ LEFT │              (middle zone)                   │RIGHT │
// │  │      │                                              │      │
// │  └──────┴──────────────────────────────────────────────┴──────┤
// │  ├─10%──┼────────────────80%──────────────────────────┼──10%─┤
// │                                                                │
// │  ┌─────────────────────────FADE ZONE───────────────────────────┤
// │  │ Top 20% of clip = Fade handles                              │
// │  │ Drag to create/adjust fades                                 │
// │  └─────────────────────────────────────────────────────────────┤
// └────────────────────────────────────────────────────────────────┘
//
// Tool Zones:
// 1. SELECT (middle 80%): Click to select, drag to move
// 2. TRIM (left/right 10%): Drag to trim clip boundaries
// 3. FADE (top 20%): Drag to create/adjust fade in/out
// 4. CROSSFADE (between two clips): Drag to adjust crossfade
//
// Modifiers:
// - Shift: Constrain to time/track axis
// - Alt/Option: Copy while dragging
// - Cmd/Ctrl: Fine adjustment (disable snap)

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
  /// Shuffle: Moving a clip pushes adjacent clips to make room.
  /// Maintains relative order — clips never overlap.
  shuffle,

  /// Slip: Drag adjusts audio content within clip boundaries.
  /// Clip position stays fixed, sourceOffset changes.
  slip,

  /// Spot: Clips snap to absolute timecode position on drop.
  /// Uses SMPTE-style positioning (frame-accurate).
  spot,

  /// Grid: Clips snap to grid positions during movement.
  /// Uses the snap grid value from the toolbar.
  grid,
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

/// Current tool determined by cursor position
enum SmartToolMode {
  /// Selection/move tool (middle of clip)
  select,

  /// Trim left edge
  trimLeft,

  /// Trim right edge
  trimRight,

  /// Fade in handle (top-left corner)
  fadeIn,

  /// Fade out handle (top-right corner)
  fadeOut,

  /// Crossfade between clips
  crossfade,

  /// Range selection (timeline background)
  rangeSelect,

  /// Scrub (Command+click)
  scrub,

  /// No specific tool (default arrow)
  none,
}

/// Mouse cursor for each tool mode
const Map<SmartToolMode, MouseCursor> kSmartToolCursors = {
  SmartToolMode.select: SystemMouseCursors.move,
  SmartToolMode.trimLeft: SystemMouseCursors.resizeLeft,
  SmartToolMode.trimRight: SystemMouseCursors.resizeRight,
  SmartToolMode.fadeIn: SystemMouseCursors.resizeUpLeft,
  SmartToolMode.fadeOut: SystemMouseCursors.resizeUpRight,
  SmartToolMode.crossfade: SystemMouseCursors.resizeColumn,
  SmartToolMode.rangeSelect: SystemMouseCursors.cell,
  SmartToolMode.scrub: SystemMouseCursors.text, // Vertical bar like scrub
  SmartToolMode.none: SystemMouseCursors.basic,
};

/// Zone configuration for smart tool detection
class SmartToolZones {
  /// Percentage of clip width for trim zones (left/right edges)
  final double trimZonePercent;

  /// Percentage of clip height for fade zone (top)
  final double fadeZonePercent;

  /// Minimum pixel width for trim zone (even on short clips)
  final double minTrimZonePixels;

  /// Minimum pixel height for fade zone
  final double minFadeZonePixels;

  const SmartToolZones({
    this.trimZonePercent = 0.10, // 10% each side
    this.fadeZonePercent = 0.20, // Top 20%
    this.minTrimZonePixels = 8.0,
    this.minFadeZonePixels = 10.0,
  });
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

  // ═══ Cubase-style edit mode (clip movement constraint) ═══
  TimelineEditMode _activeEditMode = TimelineEditMode.grid;

  // Callbacks
  void Function(SmartToolDragState)? onDragStart;
  void Function(SmartToolDragState)? onDragUpdate;
  void Function(SmartToolDragState)? onDragEnd;
  void Function(String clipId)? onClipSelected;
  void Function(String clipId, bool copyMode)? onClipMoved;
  void Function(String clipId, double newStart)? onClipTrimLeft;
  void Function(String clipId, double newEnd)? onClipTrimRight;
  void Function(String clipId, double fadeInDuration)? onFadeInChanged;
  void Function(String clipId, double fadeOutDuration)? onFadeOutChanged;

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
    }
  }

  /// Get icon for an edit mode
  static IconData editModeIcon(TimelineEditMode mode) {
    switch (mode) {
      case TimelineEditMode.shuffle: return Icons.swap_horiz;
      case TimelineEditMode.slip: return Icons.unfold_more;
      case TimelineEditMode.spot: return Icons.my_location;
      case TimelineEditMode.grid: return Icons.grid_4x4;
    }
  }

  /// Get tooltip for an edit mode
  static String editModeTooltip(TimelineEditMode mode) {
    switch (mode) {
      case TimelineEditMode.shuffle:
        return 'Shuffle — clips push adjacent clips when moved';
      case TimelineEditMode.slip:
        return 'Slip — drag adjusts audio content within clip';
      case TimelineEditMode.spot:
        return 'Spot — clips snap to absolute timecode position';
      case TimelineEditMode.grid:
        return 'Grid — clips snap to grid lines during movement';
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

  // ═══ Hit Testing ═══

  /// Determine tool mode based on position within clip
  SmartToolHitResult hitTest({
    required Offset position,
    required Rect clipBounds,
    String? clipId,
    String? trackId,
    bool hasLeftNeighbor = false,
    bool hasRightNeighbor = false,
    double? fadeInEnd,
    double? fadeOutStart,
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
    final trimZoneWidth = (width * _zones.trimZonePercent)
        .clamp(_zones.minTrimZonePixels, width * 0.25);
    final fadeZoneHeight = (height * _zones.fadeZonePercent)
        .clamp(_zones.minFadeZonePixels, height * 0.4);

    // Check fade zones first (top priority)
    if (local.dy < fadeZoneHeight) {
      // In fade zone
      if (local.dx < width * 0.5) {
        // Fade in (left half)
        return SmartToolHitResult(
          mode: SmartToolMode.fadeIn,
          cursor: SystemMouseCursors.resizeUpLeft,
          clipId: clipId,
          trackId: trackId,
          localPosition: local,
          clipBounds: clipBounds,
        );
      } else {
        // Fade out (right half)
        return SmartToolHitResult(
          mode: SmartToolMode.fadeOut,
          cursor: SystemMouseCursors.resizeUpRight,
          clipId: clipId,
          trackId: trackId,
          localPosition: local,
          clipBounds: clipBounds,
        );
      }
    }

    // Check trim zones (edges)
    if (local.dx < trimZoneWidth) {
      // Left trim zone
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

    if (local.dx > width - trimZoneWidth) {
      // Right trim zone
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

    // Default: Select/Move zone (middle)
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

    _dragState = SmartToolDragState(
      mode: hitResult.mode,
      clipId: hitResult.clipId,
      startPosition: position,
      currentPosition: position,
      originalBounds: clipBounds,
      isShiftHeld: isShift,
      isAltHeld: isAlt,
      isCmdHeld: isCmd,
    );

    onDragStart?.call(_dragState!);
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

    onDragUpdate?.call(_dragState!);
    notifyListeners();
  }

  /// End drag operation
  void endDrag() {
    if (_dragState == null) return;

    final finalState = _dragState!;
    onDragEnd?.call(finalState);

    // Apply the operation based on mode
    _applyDragOperation(finalState);

    _dragState = null;
    notifyListeners();
  }

  /// Cancel drag operation
  void cancelDrag() {
    _dragState = null;
    notifyListeners();
  }

  /// Apply the drag operation based on mode
  void _applyDragOperation(SmartToolDragState state) {
    if (state.clipId == null) return;

    final delta = state.constrainedDelta;

    switch (state.mode) {
      case SmartToolMode.select:
        // Move operation
        onClipMoved?.call(state.clipId!, state.isAltHeld);
        break;

      case SmartToolMode.trimLeft:
        final newStart = state.originalBounds.left + delta.dx;
        onClipTrimLeft?.call(state.clipId!, newStart);
        break;

      case SmartToolMode.trimRight:
        final newEnd = state.originalBounds.right + delta.dx;
        onClipTrimRight?.call(state.clipId!, newEnd);
        break;

      case SmartToolMode.fadeIn:
        // Calculate fade duration from drag
        final fadeInDuration = delta.dx.abs();
        onFadeInChanged?.call(state.clipId!, fadeInDuration);
        break;

      case SmartToolMode.fadeOut:
        final fadeOutDuration = (-delta.dx).abs();
        onFadeOutChanged?.call(state.clipId!, fadeOutDuration);
        break;

      case SmartToolMode.crossfade:
        // Crossfade adjustment handled separately
        break;

      default:
        break;
    }
  }

  // ═══ Selection ═══

  /// Handle click (for selection)
  void handleClick(SmartToolHitResult hitResult) {
    if (hitResult.clipId != null) {
      onClipSelected?.call(hitResult.clipId!);
    }
  }

  // ═══ UI Helpers ═══

  /// Get display name for current mode
  String get modeDisplayName {
    switch (_currentMode) {
      case SmartToolMode.select:
        return 'Select/Move';
      case SmartToolMode.trimLeft:
        return 'Trim Left';
      case SmartToolMode.trimRight:
        return 'Trim Right';
      case SmartToolMode.fadeIn:
        return 'Fade In';
      case SmartToolMode.fadeOut:
        return 'Fade Out';
      case SmartToolMode.crossfade:
        return 'Crossfade';
      case SmartToolMode.rangeSelect:
        return 'Range Select';
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
      case SmartToolMode.trimLeft:
      case SmartToolMode.trimRight:
        return Icons.content_cut;
      case SmartToolMode.fadeIn:
      case SmartToolMode.fadeOut:
        return Icons.gradient;
      case SmartToolMode.crossfade:
        return Icons.compare_arrows;
      case SmartToolMode.rangeSelect:
        return Icons.select_all;
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

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Smart Tool Gesture Detector
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete gesture detector for smart tool operations
class SmartToolGestureDetector extends StatelessWidget {
  final SmartToolProvider provider;
  final Widget child;
  final Rect Function(Offset position)? getClipBoundsAt;
  final String? Function(Offset position)? getClipIdAt;
  final bool Function(String clipId)? hasLeftNeighbor;
  final bool Function(String clipId)? hasRightNeighbor;

  const SmartToolGestureDetector({
    super.key,
    required this.provider,
    required this.child,
    this.getClipBoundsAt,
    this.getClipIdAt,
    this.hasLeftNeighbor,
    this.hasRightNeighbor,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (!provider.enabled) return;

        final position = event.localPosition;
        final clipId = getClipIdAt?.call(position);
        final clipBounds = getClipBoundsAt?.call(position);

        if (clipId != null && clipBounds != null) {
          final hitResult = provider.hitTest(
            position: position,
            clipBounds: clipBounds,
            clipId: clipId,
            hasLeftNeighbor: hasLeftNeighbor?.call(clipId) ?? false,
            hasRightNeighbor: hasRightNeighbor?.call(clipId) ?? false,
          );

          provider.startDrag(
            hitResult: hitResult,
            position: position,
            clipBounds: clipBounds,
          );
        }
      },
      onPointerMove: (event) {
        if (provider.isDragging) {
          provider.updateDrag(event.localPosition);
        } else {
          // Update hover
          final position = event.localPosition;
          final clipId = getClipIdAt?.call(position);
          final clipBounds = getClipBoundsAt?.call(position);

          if (clipId != null && clipBounds != null) {
            final hitResult = provider.hitTest(
              position: position,
              clipBounds: clipBounds,
              clipId: clipId,
              hasLeftNeighbor: hasLeftNeighbor?.call(clipId) ?? false,
              hasRightNeighbor: hasRightNeighbor?.call(clipId) ?? false,
            );
            provider.updateHover(hitResult);
          } else {
            provider.clearHover();
          }
        }
      },
      onPointerUp: (event) {
        if (provider.isDragging) {
          provider.endDrag();
        }
      },
      onPointerCancel: (event) {
        provider.cancelDrag();
      },
      child: SmartToolCursor(
        provider: provider,
        child: child,
      ),
    );
  }
}
