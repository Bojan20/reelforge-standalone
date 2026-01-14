// Razor Editing Provider
//
// Cubase-style Razor Editing tool for quick range selection and editing:
//
// ## What is Razor Editing?
// Hold Alt+drag to select a range across multiple tracks without selecting
// whole clips. The selected range can then be:
// - Deleted (gaps close in shuffle mode)
// - Cut/Copied to clipboard
// - Split into separate clip
// - Moved to another position
// - Processed with effects (Direct Offline Processing)
//
// ## Key Features:
// 1. Multi-track range selection (single drag across tracks)
// 2. Non-destructive (doesn't modify clips until action)
// 3. Snaps to grid when enabled
// 4. Visual razor selection overlay
// 5. Works with audio and MIDI clips
//
// ## Workflow:
// 1. Hold Alt key
// 2. Drag across timeline to select range
// 3. Release to finalize selection
// 4. Apply action (delete, split, process, etc.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Razor selection state
enum RazorState {
  /// No selection active
  idle,

  /// Currently dragging to create selection
  selecting,

  /// Selection complete, ready for action
  selected,
}

/// A single razor selection region
class RazorRegion {
  /// Unique ID
  final String id;

  /// Track ID this region is on
  final String trackId;

  /// Start time in seconds
  final double startTime;

  /// End time in seconds
  final double endTime;

  /// Color for this region
  final Color color;

  const RazorRegion({
    required this.id,
    required this.trackId,
    required this.startTime,
    required this.endTime,
    this.color = const Color(0x80FF9040), // Semi-transparent orange
  });

  /// Duration in seconds
  double get duration => endTime - startTime;

  /// Check if a time is within this region
  bool containsTime(double time) => time >= startTime && time <= endTime;

  RazorRegion copyWith({
    String? id,
    String? trackId,
    double? startTime,
    double? endTime,
    Color? color,
  }) {
    return RazorRegion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      color: color ?? this.color,
    );
  }
}

/// Complete razor selection (can span multiple tracks)
class RazorSelection {
  /// All regions in this selection
  final List<RazorRegion> regions;

  /// Overall start time
  final double startTime;

  /// Overall end time
  final double endTime;

  /// Track IDs included
  final List<String> trackIds;

  const RazorSelection({
    required this.regions,
    required this.startTime,
    required this.endTime,
    required this.trackIds,
  });

  /// Total duration
  double get duration => endTime - startTime;

  /// Number of tracks
  int get trackCount => trackIds.length;

  /// Check if empty
  bool get isEmpty => regions.isEmpty;

  /// Check if single track
  bool get isSingleTrack => trackIds.length == 1;

  /// Create empty selection
  static const empty = RazorSelection(
    regions: [],
    startTime: 0,
    endTime: 0,
    trackIds: [],
  );
}

/// Action to perform on razor selection
enum RazorAction {
  /// Delete selected range
  delete,

  /// Split clips at selection boundaries
  split,

  /// Cut to clipboard
  cut,

  /// Copy to clipboard
  copy,

  /// Mute selected range
  mute,

  /// Apply processing (Direct Offline Processing)
  process,

  /// Bounce/render selection
  bounce,

  /// Create new clip from selection
  createClip,
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Razor Editing Provider
///
/// Manages Cubase-style razor selection tool for quick range editing.
class RazorEditProvider extends ChangeNotifier {
  // State
  RazorState _state = RazorState.idle;
  RazorSelection _selection = RazorSelection.empty;

  // Drag tracking
  Offset? _dragStart;
  Offset? _dragCurrent;
  double? _dragStartTime;
  double? _dragCurrentTime;
  String? _dragStartTrackId;
  String? _dragCurrentTrackId;

  // Settings
  bool _enabled = true;
  bool _snapToGrid = true;
  Color _selectionColor = const Color(0x80FF9040);

  // Callbacks
  void Function(RazorSelection)? onSelectionChanged;
  void Function(RazorAction, RazorSelection)? onActionRequested;
  double Function(double)? snapToGridFunction;
  String? Function(double y)? getTrackIdAtY;
  List<String> Function(double startY, double endY)? getTracksInRange;

  // ═══ Getters ═══

  RazorState get state => _state;
  RazorSelection get selection => _selection;
  bool get enabled => _enabled;
  bool get snapToGrid => _snapToGrid;
  bool get hasSelection => _state == RazorState.selected && !_selection.isEmpty;
  bool get isSelecting => _state == RazorState.selecting;
  Color get selectionColor => _selectionColor;

  // Drag info for UI
  Offset? get dragStart => _dragStart;
  Offset? get dragCurrent => _dragCurrent;

  // ═══ Settings ═══

  void setEnabled(bool enabled) {
    if (_enabled != enabled) {
      _enabled = enabled;
      if (!enabled) {
        clearSelection();
      }
      notifyListeners();
    }
  }

  void setSnapToGrid(bool snap) {
    if (_snapToGrid != snap) {
      _snapToGrid = snap;
      notifyListeners();
    }
  }

  void setSelectionColor(Color color) {
    _selectionColor = color;
    notifyListeners();
  }

  // ═══ Selection Control ═══

  /// Start razor selection (call on Alt+MouseDown)
  void startSelection(Offset position, double timeAtPosition, String? trackId) {
    if (!_enabled) return;

    _state = RazorState.selecting;
    _dragStart = position;
    _dragCurrent = position;
    _dragStartTime = _maybeSnap(timeAtPosition);
    _dragCurrentTime = _dragStartTime;
    _dragStartTrackId = trackId;
    _dragCurrentTrackId = trackId;

    notifyListeners();
  }

  /// Update razor selection (call on MouseMove while Alt held)
  void updateSelection(Offset position, double timeAtPosition, String? trackId) {
    if (_state != RazorState.selecting) return;

    _dragCurrent = position;
    _dragCurrentTime = _maybeSnap(timeAtPosition);
    _dragCurrentTrackId = trackId;

    notifyListeners();
  }

  /// Finish razor selection (call on MouseUp)
  void finishSelection() {
    if (_state != RazorState.selecting) return;

    // Build the selection from drag coordinates
    if (_dragStartTime != null && _dragCurrentTime != null) {
      final startTime = _dragStartTime!.clamp(0.0, double.infinity);
      final endTime = _dragCurrentTime!.clamp(0.0, double.infinity);

      // Normalize to ensure start < end
      final actualStart = startTime < endTime ? startTime : endTime;
      final actualEnd = startTime < endTime ? endTime : startTime;

      // Get affected tracks
      List<String> trackIds = [];
      if (_dragStart != null && _dragCurrent != null && getTracksInRange != null) {
        final startY = _dragStart!.dy < _dragCurrent!.dy
            ? _dragStart!.dy
            : _dragCurrent!.dy;
        final endY = _dragStart!.dy < _dragCurrent!.dy
            ? _dragCurrent!.dy
            : _dragStart!.dy;
        trackIds = getTracksInRange!(startY, endY);
      } else if (_dragStartTrackId != null) {
        trackIds = [_dragStartTrackId!];
      }

      // Create regions for each track
      final regions = trackIds.map((trackId) {
        return RazorRegion(
          id: '${trackId}_${DateTime.now().millisecondsSinceEpoch}',
          trackId: trackId,
          startTime: actualStart,
          endTime: actualEnd,
          color: _selectionColor,
        );
      }).toList();

      if (regions.isNotEmpty && actualEnd > actualStart) {
        _selection = RazorSelection(
          regions: regions,
          startTime: actualStart,
          endTime: actualEnd,
          trackIds: trackIds,
        );
        _state = RazorState.selected;
        onSelectionChanged?.call(_selection);
      } else {
        clearSelection();
      }
    } else {
      clearSelection();
    }

    // Clear drag state
    _dragStart = null;
    _dragCurrent = null;
    _dragStartTime = null;
    _dragCurrentTime = null;
    _dragStartTrackId = null;
    _dragCurrentTrackId = null;

    notifyListeners();
  }

  /// Cancel selection in progress
  void cancelSelection() {
    _state = RazorState.idle;
    _dragStart = null;
    _dragCurrent = null;
    _dragStartTime = null;
    _dragCurrentTime = null;
    _dragStartTrackId = null;
    _dragCurrentTrackId = null;
    notifyListeners();
  }

  /// Clear current selection
  void clearSelection() {
    _state = RazorState.idle;
    _selection = RazorSelection.empty;
    _dragStart = null;
    _dragCurrent = null;
    notifyListeners();
  }

  // ═══ Actions ═══

  /// Execute action on current selection
  void executeAction(RazorAction action) {
    if (!hasSelection) return;
    onActionRequested?.call(action, _selection);

    // Clear selection after destructive actions
    if (action == RazorAction.delete || action == RazorAction.cut) {
      clearSelection();
    }
  }

  /// Delete selected range
  void deleteSelection() => executeAction(RazorAction.delete);

  /// Split clips at selection boundaries
  void splitAtSelection() => executeAction(RazorAction.split);

  /// Cut selection to clipboard
  void cutSelection() => executeAction(RazorAction.cut);

  /// Copy selection to clipboard
  void copySelection() => executeAction(RazorAction.copy);

  /// Mute selected range
  void muteSelection() => executeAction(RazorAction.mute);

  /// Process selection (opens DOP dialog)
  void processSelection() => executeAction(RazorAction.process);

  /// Bounce selection to new clip
  void bounceSelection() => executeAction(RazorAction.bounce);

  // ═══ Helpers ═══

  double _maybeSnap(double time) {
    if (_snapToGrid && snapToGridFunction != null) {
      return snapToGridFunction!(time);
    }
    return time;
  }

  // ═══ Keyboard Handling ═══

  /// Check if Alt key is held (for starting razor selection)
  bool get isAltHeld => HardwareKeyboard.instance.isAltPressed;

  /// Handle key events for razor editing
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;

    // Delete key deletes selection
    if (event is KeyDownEvent &&
        hasSelection &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace)) {
      deleteSelection();
      return KeyEventResult.handled;
    }

    // Escape clears selection
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_state == RazorState.selecting) {
        cancelSelection();
        return KeyEventResult.handled;
      } else if (hasSelection) {
        clearSelection();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Razor Selection Overlay
// ═══════════════════════════════════════════════════════════════════════════════

/// Overlay that renders the razor selection rectangle
class RazorSelectionOverlay extends StatelessWidget {
  final RazorEditProvider provider;
  final double pixelsPerSecond;
  final double scrollOffset;

  const RazorSelectionOverlay({
    super.key,
    required this.provider,
    required this.pixelsPerSecond,
    required this.scrollOffset,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        // During selection, show drag rectangle
        if (provider.isSelecting &&
            provider.dragStart != null &&
            provider.dragCurrent != null) {
          return _buildDragRect();
        }

        // Show completed selection
        if (provider.hasSelection) {
          return _buildSelectionRegions();
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDragRect() {
    final start = provider.dragStart!;
    final current = provider.dragCurrent!;

    final left = start.dx < current.dx ? start.dx : current.dx;
    final top = start.dy < current.dy ? start.dy : current.dy;
    final width = (current.dx - start.dx).abs();
    final height = (current.dy - start.dy).abs();

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: provider.selectionColor,
          border: Border.all(
            color: const Color(0xFFFF9040),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionRegions() {
    final selection = provider.selection;

    return Stack(
      children: selection.regions.map((region) {
        final left = (region.startTime * pixelsPerSecond) - scrollOffset;
        final width = region.duration * pixelsPerSecond;

        return Positioned(
          left: left,
          top: 0, // Would need track Y position
          child: Container(
            width: width,
            height: 60, // Track height
            decoration: BoxDecoration(
              color: region.color,
              border: Border.all(
                color: const Color(0xFFFF9040),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '${region.duration.toStringAsFixed(2)}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Razor Tool Button
// ═══════════════════════════════════════════════════════════════════════════════

/// Toolbar button for razor editing mode
class RazorToolButton extends StatelessWidget {
  final RazorEditProvider provider;

  const RazorToolButton({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final hasSelection = provider.hasSelection;

        return Tooltip(
          message: 'Razor Edit (Alt+Drag)\n${hasSelection ? "Selection active" : "No selection"}',
          child: GestureDetector(
            onTap: hasSelection ? provider.clearSelection : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasSelection
                    ? const Color(0xFFFF9040).withValues(alpha: 0.2)
                    : const Color(0xFF1a1a20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: hasSelection
                      ? const Color(0xFFFF9040)
                      : const Color(0xFF3a3a40),
                  width: hasSelection ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.carpenter, // Razor-like icon
                    size: 14,
                    color: hasSelection
                        ? const Color(0xFFFF9040)
                        : const Color(0xFF808090),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Razor',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: hasSelection
                          ? const Color(0xFFFF9040)
                          : const Color(0xFF808090),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Razor Context Menu
// ═══════════════════════════════════════════════════════════════════════════════

/// Context menu for razor selection actions
class RazorContextMenu extends StatelessWidget {
  final RazorEditProvider provider;
  final VoidCallback? onClose;

  const RazorContextMenu({
    super.key,
    required this.provider,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (!provider.hasSelection) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3a3a40)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuItem(
            icon: Icons.delete,
            label: 'Delete',
            shortcut: 'Del',
            onTap: () {
              provider.deleteSelection();
              onClose?.call();
            },
          ),
          _MenuItem(
            icon: Icons.content_cut,
            label: 'Cut',
            shortcut: 'Cmd+X',
            onTap: () {
              provider.cutSelection();
              onClose?.call();
            },
          ),
          _MenuItem(
            icon: Icons.copy,
            label: 'Copy',
            shortcut: 'Cmd+C',
            onTap: () {
              provider.copySelection();
              onClose?.call();
            },
          ),
          const Divider(height: 1, color: Color(0xFF3a3a40)),
          _MenuItem(
            icon: Icons.call_split,
            label: 'Split at Boundaries',
            onTap: () {
              provider.splitAtSelection();
              onClose?.call();
            },
          ),
          _MenuItem(
            icon: Icons.volume_off,
            label: 'Mute Selection',
            onTap: () {
              provider.muteSelection();
              onClose?.call();
            },
          ),
          const Divider(height: 1, color: Color(0xFF3a3a40)),
          _MenuItem(
            icon: Icons.auto_fix_high,
            label: 'Process...',
            shortcut: 'Cmd+P',
            onTap: () {
              provider.processSelection();
              onClose?.call();
            },
          ),
          _MenuItem(
            icon: Icons.layers,
            label: 'Bounce Selection',
            onTap: () {
              provider.bounceSelection();
              onClose?.call();
            },
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF808090)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
            if (shortcut != null)
              Text(
                shortcut!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF606070),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
