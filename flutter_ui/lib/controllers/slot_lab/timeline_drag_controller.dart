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
import '../../providers/middleware_provider.dart';

/// Controller for timeline drag operations
/// Survives widget rebuilds, manages all drag state by ID
class TimelineDragController extends ChangeNotifier {
  final MiddlewareProvider _middleware;

  TimelineDragController({required MiddlewareProvider middleware})
      : _middleware = middleware;

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
  void endRegionDrag() {
    if (_draggingRegionId == null || _draggingRegionEventId == null) {
      _clearRegionDrag();
      return;
    }

    // Calculate new position
    final newStartSeconds = _regionDragStartSeconds + _regionDragDelta;
    final newStartMs = (newStartSeconds * 1000).clamp(0.0, double.infinity);

    // Sync all layers in the event to new base offset
    final event = _middleware.compositeEvents
        .where((e) => e.id == _draggingRegionEventId)
        .firstOrNull;

    if (event != null) {
      // Calculate the delta in milliseconds
      final deltaMs = _regionDragDelta * 1000;

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
  // ═══════════════════════════════════════════════════════════════════════════

  String? _draggingLayerEventId; // SlotEventLayer.id (unique)
  String? _draggingLayerParentEventId; // Parent SlotCompositeEvent.id
  String? _draggingLayerRegionId; // Parent region ID (for visual state)
  double _layerDragStartOffset = 0; // Start offset in seconds (relative to region)
  double _layerDragDelta = 0; // Accumulated drag delta in seconds
  double _regionStartSeconds = 0; // Region start position for absolute calculation

  /// Start dragging a layer
  void startLayerDrag({
    required String layerEventId,
    required String parentEventId,
    required String regionId,
    required double startOffsetSeconds,
    required double regionStartSeconds,
  }) {
    _draggingLayerEventId = layerEventId;
    _draggingLayerParentEventId = parentEventId;
    _draggingLayerRegionId = regionId;
    _layerDragStartOffset = startOffsetSeconds;
    _layerDragDelta = 0;
    _regionStartSeconds = regionStartSeconds;
    notifyListeners();
  }

  /// Update layer drag position
  /// [deltaSeconds] is the time delta from drag movement
  void updateLayerDrag(double deltaSeconds) {
    if (_draggingLayerEventId == null) return;
    _layerDragDelta += deltaSeconds;
    notifyListeners();
  }

  /// Get current layer offset during drag (for visual feedback)
  /// Returns the offset relative to region start
  double getLayerDragCurrentOffset() {
    return _layerDragStartOffset + _layerDragDelta;
  }

  /// End layer drag and sync to provider
  void endLayerDrag() {
    if (_draggingLayerEventId == null || _draggingLayerParentEventId == null) {
      _clearLayerDrag();
      return;
    }

    // Calculate new absolute offset in milliseconds
    // Absolute offset = region start + layer offset within region
    final newRelativeOffset = _layerDragStartOffset + _layerDragDelta;
    final newAbsoluteOffsetMs = (_regionStartSeconds + newRelativeOffset) * 1000;
    final clampedOffsetMs = newAbsoluteOffsetMs.clamp(0.0, double.infinity);

    // Sync to provider
    _middleware.setLayerOffset(
      _draggingLayerParentEventId!,
      _draggingLayerEventId!,
      clampedOffsetMs,
    );

    debugPrint('[TimelineDragController] Layer drag ended: offset=${clampedOffsetMs.toStringAsFixed(0)}ms');

    _clearLayerDrag();
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
    _layerDragStartOffset = 0;
    _layerDragDelta = 0;
    _regionStartSeconds = 0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUERY STATE (for widgets to check drag status)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a region is being dragged
  bool isDraggingRegion(String regionId) => _draggingRegionId == regionId;

  /// Check if a layer is being dragged (by eventLayerId)
  bool isDraggingLayer(String layerEventId) => _draggingLayerEventId == layerEventId;

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

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPUTED POSITIONS (for visual feedback during drag)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current region position during drag (in seconds)
  double getRegionCurrentPosition() {
    return _regionDragStartSeconds + _regionDragDelta;
  }

  /// Get current layer position during drag (relative to region, in seconds)
  double getLayerCurrentPosition() {
    return _layerDragStartOffset + _layerDragDelta;
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
