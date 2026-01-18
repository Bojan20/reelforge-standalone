/// FluxForge Event Sync Service
///
/// Provides two-way synchronization between:
/// - EventRegistry (Slot Lab) — AudioEvent with AudioLayers
/// - MiddlewareProvider — SlotCompositeEvent with SlotEventLayers
///
/// When an event is created/modified in Slot Lab, it automatically
/// syncs to Middleware (appears in Events folder with timeline tracks).
/// Changes in Middleware propagate back to Slot Lab.

import 'package:flutter/material.dart';
import '../models/slot_audio_events.dart';
import '../providers/middleware_provider.dart';
import 'event_registry.dart';

/// Service that synchronizes events between Slot Lab and Middleware
class EventSyncService extends ChangeNotifier {
  final EventRegistry _registry;
  final MiddlewareProvider _middleware;

  // Track sync state to avoid infinite loops
  bool _syncing = false;

  EventSyncService({
    required EventRegistry registry,
    required MiddlewareProvider middleware,
  })  : _registry = registry,
        _middleware = middleware {
    // Listen to EventRegistry changes
    _registry.addListener(_onRegistryChanged);

    // Listen to Middleware changes
    _middleware.addListener(_onMiddlewareChanged);
  }

  /// Sync all events from EventRegistry to Middleware
  void syncAllFromRegistry() {
    if (_syncing) return;
    _syncing = true;

    try {
      for (final event in _registry.allEvents) {
        _syncEventToMiddleware(event);
      }
    } finally {
      _syncing = false;
    }
  }

  /// Sync all composite events from Middleware to EventRegistry
  void syncAllFromMiddleware() {
    if (_syncing) return;
    _syncing = true;

    try {
      for (final composite in _middleware.compositeEvents) {
        _syncCompositeToRegistry(composite);
      }
    } finally {
      _syncing = false;
    }
  }

  /// Create or update event in both systems
  void createEvent({
    required String id,
    required String name,
    required String stage,
    required List<AudioLayer> layers,
    String category = 'Slot',
    bool loop = false,
    int priority = 0,
  }) {
    if (_syncing) return;
    _syncing = true;

    try {
      // Create AudioEvent for EventRegistry
      final audioEvent = AudioEvent(
        id: id,
        name: name,
        stage: stage,
        layers: layers,
        duration: _calculateTotalDuration(layers),
        loop: loop,
        priority: priority,
      );

      // Register in EventRegistry
      _registry.registerEvent(audioEvent);

      // Sync to Middleware
      _syncEventToMiddleware(audioEvent);
    } finally {
      _syncing = false;
    }

    notifyListeners();
  }

  /// Add a layer/sound to an existing event
  void addLayerToEvent({
    required String eventId,
    required String audioPath,
    required String name,
    double volume = 1.0,
    double pan = 0.0,
    double delayMs = 0.0,
    double offsetSeconds = 0.0,
    int busId = 0,
  }) {
    if (_syncing) return;
    _syncing = true;

    try {
      final existingEvent = _registry.getEventById(eventId);
      if (existingEvent == null) {
        debugPrint('[EventSyncService] Event not found: $eventId');
        return;
      }

      // Create new layer
      final newLayer = AudioLayer(
        id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
        audioPath: audioPath,
        name: name,
        volume: volume,
        pan: pan,
        delay: delayMs,
        offset: offsetSeconds,
        busId: busId,
      );

      // Create updated event with new layer
      final updatedEvent = AudioEvent(
        id: existingEvent.id,
        name: existingEvent.name,
        stage: existingEvent.stage,
        layers: [...existingEvent.layers, newLayer],
        duration: existingEvent.duration,
        loop: existingEvent.loop,
        priority: existingEvent.priority,
      );

      // Update in EventRegistry
      _registry.registerEvent(updatedEvent);

      // Sync to Middleware
      _syncEventToMiddleware(updatedEvent);
    } finally {
      _syncing = false;
    }

    notifyListeners();
  }

  /// Update layer parameters
  void updateLayer({
    required String eventId,
    required String layerId,
    double? volume,
    double? pan,
    double? delayMs,
    double? offsetSeconds,
    int? busId,
  }) {
    if (_syncing) return;
    _syncing = true;

    try {
      final existingEvent = _registry.getEventById(eventId);
      if (existingEvent == null) return;

      // Find and update the layer
      final updatedLayers = existingEvent.layers.map((layer) {
        if (layer.id == layerId) {
          return AudioLayer(
            id: layer.id,
            audioPath: layer.audioPath,
            name: layer.name,
            volume: volume ?? layer.volume,
            pan: pan ?? layer.pan,
            delay: delayMs ?? layer.delay,
            offset: offsetSeconds ?? layer.offset,
            busId: busId ?? layer.busId,
          );
        }
        return layer;
      }).toList();

      final updatedEvent = AudioEvent(
        id: existingEvent.id,
        name: existingEvent.name,
        stage: existingEvent.stage,
        layers: updatedLayers,
        duration: existingEvent.duration,
        loop: existingEvent.loop,
        priority: existingEvent.priority,
      );

      _registry.registerEvent(updatedEvent);
      _syncEventToMiddleware(updatedEvent);
    } finally {
      _syncing = false;
    }

    notifyListeners();
  }

  /// Remove a layer from an event
  void removeLayerFromEvent({
    required String eventId,
    required String layerId,
  }) {
    if (_syncing) return;
    _syncing = true;

    try {
      final existingEvent = _registry.getEventById(eventId);
      if (existingEvent == null) return;

      final updatedLayers =
          existingEvent.layers.where((l) => l.id != layerId).toList();

      final updatedEvent = AudioEvent(
        id: existingEvent.id,
        name: existingEvent.name,
        stage: existingEvent.stage,
        layers: updatedLayers,
        duration: _calculateTotalDuration(updatedLayers),
        loop: existingEvent.loop,
        priority: existingEvent.priority,
      );

      _registry.registerEvent(updatedEvent);
      _syncEventToMiddleware(updatedEvent);
    } finally {
      _syncing = false;
    }

    notifyListeners();
  }

  /// Delete an event from both systems
  void deleteEvent(String eventId) {
    if (_syncing) return;
    _syncing = true;

    try {
      // Remove from EventRegistry
      _registry.unregisterEvent(eventId);

      // Remove from Middleware
      _middleware.deleteCompositeEvent(eventId);
    } finally {
      _syncing = false;
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL SYNC METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync AudioEvent → SlotCompositeEvent
  void _syncEventToMiddleware(AudioEvent event) {
    // Convert AudioLayers to SlotEventLayers
    final layers = event.layers.map((layer) {
      return SlotEventLayer(
        id: layer.id,
        name: layer.name,
        audioPath: layer.audioPath,
        volume: layer.volume,
        pan: layer.pan,
        offsetMs: layer.delay + (layer.offset * 1000),
        fadeInMs: 0,
        fadeOutMs: 0,
        muted: false,
        solo: false,
        busId: layer.busId,
      );
    }).toList();

    // Check if composite event already exists
    final existing = _middleware.compositeEvents
        .where((e) => e.id == event.id)
        .firstOrNull;

    if (existing != null) {
      // Update existing
      _middleware.updateCompositeEvent(
        existing.copyWith(
          name: event.name,
          layers: layers,
          looping: event.loop,
          modifiedAt: DateTime.now(),
          triggerStages: [event.stage],
        ),
      );
    } else {
      // Create new
      final composite = SlotCompositeEvent(
        id: event.id,
        name: event.name,
        category: _categoryFromStage(event.stage),
        color: _colorFromStage(event.stage),
        layers: layers,
        masterVolume: 1.0,
        looping: event.loop,
        maxInstances: 1,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        triggerStages: [event.stage],
      );

      _middleware.addCompositeEvent(composite);
    }

    debugPrint(
        '[EventSyncService] Synced to Middleware: ${event.name} (${layers.length} layers)');
  }

  /// Sync SlotCompositeEvent → AudioEvent
  void _syncCompositeToRegistry(SlotCompositeEvent composite) {
    // Convert SlotEventLayers to AudioLayers
    final layers = composite.layers.map((layer) {
      return AudioLayer(
        id: layer.id,
        audioPath: layer.audioPath,
        name: layer.name,
        volume: layer.volume,
        pan: layer.pan,
        delay: layer.offsetMs,
        offset: 0, // Combined into delay
        busId: layer.busId ?? 0,
      );
    }).toList();

    // Determine stage from trigger stages or category
    final stage = composite.triggerStages.isNotEmpty
        ? composite.triggerStages.first
        : composite.category.toUpperCase();

    final audioEvent = AudioEvent(
      id: composite.id,
      name: composite.name,
      stage: stage,
      layers: layers,
      duration: composite.totalDurationSeconds,
      loop: composite.looping,
      priority: 0,
    );

    _registry.registerEvent(audioEvent);

    debugPrint(
        '[EventSyncService] Synced to Registry: ${composite.name} (${layers.length} layers)');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LISTENERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _onRegistryChanged() {
    if (_syncing) return;
    // Auto-sync new events to Middleware
    syncAllFromRegistry();
  }

  void _onMiddlewareChanged() {
    if (_syncing) return;
    // Don't auto-sync back to avoid infinite loops
    // Only sync explicitly when user edits in Middleware
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  double _calculateTotalDuration(List<AudioLayer> layers) {
    if (layers.isEmpty) return 0;
    // Estimate from layers - actual duration requires loading audio
    return layers
        .map((l) => l.offset + 2.0) // Assume 2s per sound as default
        .reduce((a, b) => a > b ? a : b);
  }

  String _categoryFromStage(String stage) {
    final lower = stage.toLowerCase();
    if (lower.contains('spin')) return 'spin';
    if (lower.contains('reel')) return 'reelStop';
    if (lower.contains('anticipation')) return 'anticipation';
    if (lower.contains('win') && lower.contains('big')) return 'bigWin';
    if (lower.contains('win')) return 'win';
    if (lower.contains('feature')) return 'feature';
    if (lower.contains('bonus')) return 'bonus';
    if (lower.contains('jackpot')) return 'bigWin';
    return 'general';
  }

  Color _colorFromStage(String stage) {
    final category = _categoryFromStage(stage);
    return switch (category) {
      'spin' => const Color(0xFF4A9EFF),
      'reelStop' => const Color(0xFF9B59B6),
      'anticipation' => const Color(0xFFE74C3C),
      'win' => const Color(0xFFF1C40F),
      'bigWin' => const Color(0xFFFF9040),
      'feature' => const Color(0xFF40FF90),
      'bonus' => const Color(0xFFFF40FF),
      _ => const Color(0xFF888888),
    };
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistryChanged);
    _middleware.removeListener(_onMiddlewareChanged);
    super.dispose();
  }
}

/// Global instance (lazy initialized)
EventSyncService? _eventSyncService;

EventSyncService getEventSyncService(
    EventRegistry registry, MiddlewareProvider middleware) {
  return _eventSyncService ??= EventSyncService(
    registry: registry,
    middleware: middleware,
  );
}
