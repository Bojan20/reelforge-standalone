/// Timeline Drag Controller
///
/// Centralized state machine for all timeline drag operations.
/// Survives widget rebuilds by tracking items by ID, not object reference.
///
/// Key Design Decisions:
/// - All drag state lives HERE, not in widget state
/// - Items tracked by ID (String), not object reference
/// - Drag delta accumulated during drag, synced to provider on end
/// - No provider updates during drag (prevents rebuild storms)
///
/// Usage:
///   final controller = TimelineDragController(middleware: provider);
///
///   // In gesture handler:
///   controller.startLayerDrag(layerEventId, regionId, startOffset);
///   controller.updateLayerDrag(deltaSeconds);
///   controller.endLayerDrag(); // Syncs to provider
///
/// Architecture:
///   User Drag → Controller (accumulates delta) → Provider (on drag end)
///                    ↓
///   Widget queries controller.isDraggingLayer(id) for visual state

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../../providers/middleware_provider.dart';

/// Available grid intervals for snap-to-grid (in milliseconds)
enum GridInterval {
  ms10(10, '10ms'),
  ms25(25, '25ms'),
  ms50(50, '50ms'),
  ms100(100, '100ms'),
  ms250(250, '250ms'),
  ms500(500, '500ms'),
  s1(1000, '1s');

  final int ms;
  final String label;
  const GridInterval(this.ms, this.label);

  double get seconds => ms / 1000.0;
}

/// Controller for timeline drag operations
/// Survives widget rebuilds, manages all drag state by ID
class TimelineDragController extends ChangeNotifier {
  final MiddlewareProvider _middleware;

  TimelineDragController({required MiddlewareProvider middleware})
      : _middleware = middleware;

  // ═══════════════════════════════════════════════════════════════════════════
  // SNAP-TO-GRID STATE
  // ═══════════════════════════════════════════════════════════════════════════

  bool _snapEnabled = false;
  GridInterval _gridInterval = GridInterval.ms100;

  /// Whether snap-to-grid is enabled
  bool get snapEnabled => _snapEnabled;

  /// Current grid interval
  GridInterval get gridInterval => _gridInterval;

  /// Toggle snap-to-grid on/off
  void toggleSnap() {
    _snapEnabled = !_snapEnabled;
    notifyListeners();
  }

  /// Set snap enabled state
  void setSnapEnabled(bool enabled) {
    if (_snapEnabled != enabled) {
      _snapEnabled = enabled;
      notifyListeners();
    }
  }

  /// Set grid interval
  void setGridInterval(GridInterval interval) {
    if (_gridInterval != interval) {
      _gridInterval = interval;
      notifyListeners();
    }
  }

  /// Snap a position to the nearest grid point
  /// Returns the original position if snap is disabled
  double snapToGrid(double positionSeconds) {
    if (!_snapEnabled) return positionSeconds;
    final intervalSeconds = _gridInterval.seconds;
    return (positionSeconds / intervalSeconds).round() * intervalSeconds;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JUST-ENDED DRAG TRACKING (prevents race condition with provider sync)
  // When drag ends, we update provider which triggers rebuild. But we need
  // to keep reporting isDragging=true until AFTER that rebuild completes.
  // ═══════════════════════════════════════════════════════════════════════════

  String? _justEndedLayerId; // Layer that just finished dragging (cleared next frame)

  // ═══════════════════════════════════════════════════════════════════════════
  // REGION DRAG STATE (whole region movement)
  // ═══════════════════════════════════════════════════════════════════════════

  String? _draggingRegionId;
  String? _draggingRegionEventId; // Event ID for provider sync
  double _regionDragStartSeconds = 0;
  double _regionDragDelta = 0;

  /// Start dragging a region
  void startRegionDrag({
    required String regionId,
    required String eventId,
    required double startSeconds,
  }) {
    _draggingRegionId = regionId;
    _draggingRegionEventId = eventId;
    _regionDragStartSeconds = startSeconds;
    _regionDragDelta = 0;
    notifyListeners();
  }

  /// Update region drag position
  /// [deltaSeconds] is the time delta from drag movement
  void updateRegionDrag(double deltaSeconds) {
    if (_draggingRegionId == null) return;
    _regionDragDelta += deltaSeconds;
    notifyListeners();
  }

  /// End region drag and sync to provider
  /// Applies snap-to-grid if enabled
  void endRegionDrag() {
    if (_draggingRegionId == null || _draggingRegionEventId == null) {
      _clearRegionDrag();
      return;
    }

    // Calculate new position with snap applied
    final rawPosition = _regionDragStartSeconds + _regionDragDelta;
    final snappedPosition = snapToGrid(rawPosition);
    final newStartMs = (snappedPosition * 1000).clamp(0.0, double.infinity);

    // Sync all layers in the event to new base offset
    final event = _middleware.compositeEvents
        .where((e) => e.id == _draggingRegionEventId)
        .firstOrNull;

    if (event != null) {
      // Calculate the delta in milliseconds (using snapped position)
      final deltaMs = (snappedPosition - _regionDragStartSeconds) * 1000;

      // Update each layer's offset by the delta
      for (final layer in event.layers) {
        final newOffsetMs = (layer.offsetMs + deltaMs).clamp(0.0, double.infinity);
        _middleware.setLayerOffset(event.id, layer.id, newOffsetMs);
      }

      debugPrint('[TimelineDragController] Region "${event.name}" moved by ${deltaMs.toStringAsFixed(0)}ms');
    }

    _clearRegionDrag();
  }

  /// Cancel region drag without syncing (keeps original position)
  /// Call this on ESC key press to revert to original position
  void cancelRegionDrag() {
    if (_draggingRegionId != null) {
      debugPrint('[TimelineDragController] Region drag CANCELLED - reverting to original position');
    }
    _clearRegionDrag();
  }

  void _clearRegionDrag() {
    _draggingRegionId = null;
    _draggingRegionEventId = null;
    _regionDragStartSeconds = 0;
    _regionDragDelta = 0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER DRAG STATE (individual layer within expanded region)
  // Uses ABSOLUTE positioning to avoid relative offset calculation bugs
  // ═══════════════════════════════════════════════════════════════════════════

  String? _draggingLayerEventId; // SlotEventLayer.id (unique)
  String? _draggingLayerParentEventId; // Parent SlotCompositeEvent.id
  String? _draggingLayerRegionId; // Parent region ID (for visual state)
  double _absoluteStartSeconds = 0; // ABSOLUTE start position (from provider)
  double _layerDragDelta = 0; // Accumulated drag delta in seconds
  double _regionDurationAtStart = 0; // CAPTURED at drag start - for stable visual
  double _layerDurationAtStart = 0; // CAPTURED at drag start - for stable width

  /// Start dragging a layer
  /// NOW USES ABSOLUTE positioning - pass the absolute offset from provider directly
  void startLayerDrag({
    required String layerEventId,
    required String parentEventId,
    required String regionId,
    required double absoluteOffsetSeconds, // ABSOLUTE position from provider (offsetMs/1000)
    required double regionDuration, // CAPTURE for stable visual
    required double layerDuration, // CAPTURE for stable width
  }) {
    _draggingLayerEventId = layerEventId;
    _draggingLayerParentEventId = parentEventId;
    _draggingLayerRegionId = regionId;
    _absoluteStartSeconds = absoluteOffsetSeconds;
    _layerDragDelta = 0;
    _regionDurationAtStart = regionDuration;
    _layerDurationAtStart = layerDuration;
    notifyListeners();
  }

  /// Update layer drag position
  /// [deltaSeconds] is the time delta from drag movement
  void updateLayerDrag(double deltaSeconds) {
    if (_draggingLayerEventId == null) return;
    _layerDragDelta += deltaSeconds;
    notifyListeners();
  }

  /// Get current ABSOLUTE position during drag (in seconds)
  /// Does NOT apply snap - use getSnappedAbsolutePosition() for snapped value
  double getAbsolutePosition() {
    return (_absoluteStartSeconds + _layerDragDelta).clamp(0.0, double.infinity);
  }

  /// Get current ABSOLUTE position with snap applied (for visual feedback during drag)
  double getSnappedAbsolutePosition() {
    final raw = getAbsolutePosition();
    return snapToGrid(raw);
  }

  /// Get current layer offset during drag (for visual feedback)
  /// Returns the offset relative to region start (DEPRECATED - use getAbsolutePosition)
  double getLayerDragCurrentOffset() {
    return _layerDragDelta; // Just the delta now
  }

  /// Get current layer position during drag (relative to region, in seconds)
  double getLayerCurrentPosition() {
    return _layerDragDelta; // Just the delta for backward compat
  }

  /// End layer drag and sync to provider
  /// Applies snap-to-grid if enabled
  void endLayerDrag() {
    debugPrint('[DRAG-END] ═══════════════════════════════════════════════════');
    debugPrint('[DRAG-END] _draggingLayerEventId=$_draggingLayerEventId');
    debugPrint('[DRAG-END] _draggingLayerParentEventId=$_draggingLayerParentEventId');
    debugPrint('[DRAG-END] _absoluteStartSeconds=$_absoluteStartSeconds');
    debugPrint('[DRAG-END] _layerDragDelta=$_layerDragDelta');

    if (_draggingLayerEventId == null || _draggingLayerParentEventId == null) {
      debugPrint('[DRAG-END] ❌ ABORT: null eventId or parentEventId');
      _clearLayerDrag();
      return;
    }

    // Calculate new absolute offset - apply snap if enabled
    final snappedPosition = getSnappedAbsolutePosition();
    final newAbsoluteOffsetMs = snappedPosition * 1000;
    debugPrint('[DRAG-END] snappedPosition=${snappedPosition}s, newAbsoluteOffsetMs=$newAbsoluteOffsetMs');

    // Sync to provider
    debugPrint('[DRAG-END] Calling setLayerOffset($_draggingLayerParentEventId, $_draggingLayerEventId, $newAbsoluteOffsetMs)');
    _middleware.setLayerOffset(
      _draggingLayerParentEventId!,
      _draggingLayerEventId!,
      newAbsoluteOffsetMs,
    );
    debugPrint('[DRAG-END] ✅ setLayerOffset completed');

    // CRITICAL: Keep reporting isDragging=true until AFTER the rebuild triggered by setLayerOffset
    _justEndedLayerId = _draggingLayerEventId;

    _clearLayerDrag();

    // Clear the just-ended flag after the next frame (when rebuild is complete)
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _justEndedLayerId = null;
    });
  }

  /// Cancel layer drag without syncing (keeps original position)
  /// Call this on ESC key press to revert to original position
  void cancelLayerDrag() {
    if (_draggingLayerEventId != null) {
      debugPrint('[TimelineDragController] Layer drag CANCELLED - reverting to original position');
    }
    _clearLayerDrag();
  }

  /// Cancel any active drag (layer or region) - for ESC key handling
  /// Returns true if a drag was cancelled
  bool cancelActiveDrag() {
    if (_draggingLayerEventId != null) {
      cancelLayerDrag();
      return true;
    }
    if (_draggingRegionId != null) {
      cancelRegionDrag();
      return true;
    }
    return false;
  }

  void _clearLayerDrag() {
    _draggingLayerEventId = null;
    _draggingLayerParentEventId = null;
    _draggingLayerRegionId = null;
    _absoluteStartSeconds = 0;
    _layerDragDelta = 0;
    _regionDurationAtStart = 0;
    _layerDurationAtStart = 0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUERY STATE (for widgets to check drag status)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a region is being dragged
  bool isDraggingRegion(String regionId) => _draggingRegionId == regionId;

  /// Check if a layer is being dragged (by eventLayerId)
  /// Also returns true for layers that JUST finished dragging (prevents sync race condition)
  bool isDraggingLayer(String layerEventId) =>
      _draggingLayerEventId == layerEventId || _justEndedLayerId == layerEventId;

  /// Check if any drag is in progress
  bool get isDragging => _draggingRegionId != null || _draggingLayerEventId != null;

  /// Check if region drag is in progress
  bool get isRegionDragActive => _draggingRegionId != null;

  /// Check if layer drag is in progress
  bool get isLayerDragActive => _draggingLayerEventId != null;

  /// Get the currently dragging region ID
  String? get draggingRegionId => _draggingRegionId;

  /// Get the currently dragging layer event ID
  String? get draggingLayerEventId => _draggingLayerEventId;

  /// Get the currently dragging layer's parent region ID
  String? get draggingLayerRegionId => _draggingLayerRegionId;

  /// Get region drag delta in seconds
  double get regionDragDelta => _regionDragDelta;

  /// Get layer drag delta in seconds
  double get layerDragDelta => _layerDragDelta;

  /// Get captured region duration at drag start (for stable visual during drag)
  double get regionDurationAtStart => _regionDurationAtStart;

  /// Get captured layer duration at drag start (for stable width during drag)
  double get layerDurationAtStart => _layerDurationAtStart;

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPUTED POSITIONS (for visual feedback during drag)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current region position during drag (in seconds)
  double getRegionCurrentPosition() {
    return _regionDragStartSeconds + _regionDragDelta;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _clearRegionDrag();
    _clearLayerDrag();
    super.dispose();
  }
}
