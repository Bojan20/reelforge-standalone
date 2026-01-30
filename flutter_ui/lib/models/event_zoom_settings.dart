/// Event Zoom Settings Model
///
/// Per-event zoom level persistence for timeline views.
/// Allows each event to have its own independent zoom/scroll state.
///
/// Features:
/// - Per-event zoom level storage
/// - Scroll position persistence
/// - View mode preferences
/// - Auto-save on change
///
/// Task: P1-03 Waveform Zoom Per-Event

import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Zoom settings for a single event
class EventZoomSettings {
  final String eventId;
  final double pixelsPerSecond;
  final double scrollOffsetX;
  final double scrollOffsetY;
  final bool showWaveforms;
  final bool showGrid;
  final DateTime lastModified;

  EventZoomSettings({
    required this.eventId,
    this.pixelsPerSecond = 100.0,
    this.scrollOffsetX = 0.0,
    this.scrollOffsetY = 0.0,
    this.showWaveforms = true,
    this.showGrid = true,
    DateTime? lastModified,
  }) : lastModified = lastModified ?? DateTime.now();

  EventZoomSettings copyWith({
    String? eventId,
    double? pixelsPerSecond,
    double? scrollOffsetX,
    double? scrollOffsetY,
    bool? showWaveforms,
    bool? showGrid,
    DateTime? lastModified,
  }) {
    return EventZoomSettings(
      eventId: eventId ?? this.eventId,
      pixelsPerSecond: pixelsPerSecond ?? this.pixelsPerSecond,
      scrollOffsetX: scrollOffsetX ?? this.scrollOffsetX,
      scrollOffsetY: scrollOffsetY ?? this.scrollOffsetY,
      showWaveforms: showWaveforms ?? this.showWaveforms,
      showGrid: showGrid ?? this.showGrid,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'pixelsPerSecond': pixelsPerSecond,
      'scrollOffsetX': scrollOffsetX,
      'scrollOffsetY': scrollOffsetY,
      'showWaveforms': showWaveforms,
      'showGrid': showGrid,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory EventZoomSettings.fromJson(Map<String, dynamic> json) {
    return EventZoomSettings(
      eventId: json['eventId'] as String,
      pixelsPerSecond: (json['pixelsPerSecond'] as num?)?.toDouble() ?? 100.0,
      scrollOffsetX: (json['scrollOffsetX'] as num?)?.toDouble() ?? 0.0,
      scrollOffsetY: (json['scrollOffsetY'] as num?)?.toDouble() ?? 0.0,
      showWaveforms: json['showWaveforms'] as bool? ?? true,
      showGrid: json['showGrid'] as bool? ?? true,
      lastModified: DateTime.parse(json['lastModified'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventZoomSettings &&
          runtimeType == other.runtimeType &&
          eventId == other.eventId;

  @override
  int get hashCode => eventId.hashCode;
}

/// Service for managing per-event zoom settings
class EventZoomService extends ChangeNotifier {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static EventZoomService? _instance;
  static EventZoomService get instance => _instance ??= EventZoomService._();

  EventZoomService._();

  // ─── State ─────────────────────────────────────────────────────────────────
  final Map<String, EventZoomSettings> _settings = {};

  // Default settings
  static const double kDefaultPixelsPerSecond = 100.0;
  static const double kMinPixelsPerSecond = 20.0;
  static const double kMaxPixelsPerSecond = 500.0;

  // ─── Getters ───────────────────────────────────────────────────────────────

  /// Get zoom settings for event (returns default if not found)
  EventZoomSettings getSettings(String eventId) {
    return _settings[eventId] ?? EventZoomSettings(eventId: eventId);
  }

  /// Check if event has custom zoom settings
  bool hasSettings(String eventId) => _settings.containsKey(eventId);

  /// Get all stored settings
  Map<String, EventZoomSettings> get allSettings => Map.unmodifiable(_settings);

  // ===========================================================================
  // SETTERS
  // ===========================================================================

  /// Set complete settings for an event
  void setSettings(EventZoomSettings settings) {
    _settings[settings.eventId] = settings;
    notifyListeners();
  }

  /// Update pixels per second (zoom level) for event
  void setPixelsPerSecond(String eventId, double pixelsPerSecond) {
    final clamped = pixelsPerSecond.clamp(kMinPixelsPerSecond, kMaxPixelsPerSecond);
    final current = getSettings(eventId);
    _settings[eventId] = current.copyWith(
      pixelsPerSecond: clamped,
      lastModified: DateTime.now(),
    );
    notifyListeners();
  }

  /// Update scroll offsets for event
  void setScrollOffsets(String eventId, double scrollX, double scrollY) {
    final current = getSettings(eventId);
    _settings[eventId] = current.copyWith(
      scrollOffsetX: scrollX,
      scrollOffsetY: scrollY,
      lastModified: DateTime.now(),
    );
    notifyListeners();
  }

  /// Zoom in (increase pixels per second)
  void zoomIn(String eventId, {double factor = 0.1}) {
    final current = getSettings(eventId);
    final newZoom = current.pixelsPerSecond * (1 + factor);
    setPixelsPerSecond(eventId, newZoom);
  }

  /// Zoom out (decrease pixels per second)
  void zoomOut(String eventId, {double factor = 0.1}) {
    final current = getSettings(eventId);
    final newZoom = current.pixelsPerSecond * (1 - factor);
    setPixelsPerSecond(eventId, newZoom);
  }

  /// Reset zoom to default
  void resetZoom(String eventId) {
    setPixelsPerSecond(eventId, kDefaultPixelsPerSecond);
  }

  /// Toggle waveform display
  void toggleWaveforms(String eventId) {
    final current = getSettings(eventId);
    _settings[eventId] = current.copyWith(
      showWaveforms: !current.showWaveforms,
      lastModified: DateTime.now(),
    );
    notifyListeners();
  }

  /// Toggle grid display
  void toggleGrid(String eventId) {
    final current = getSettings(eventId);
    _settings[eventId] = current.copyWith(
      showGrid: !current.showGrid,
      lastModified: DateTime.now(),
    );
    notifyListeners();
  }

  /// Remove settings for event (reverts to defaults)
  void removeSettings(String eventId) {
    _settings.remove(eventId);
    notifyListeners();
  }

  /// Clear all settings (for testing/reset)
  void clear() {
    _settings.clear();
    notifyListeners();
  }

  // ===========================================================================
  // PERSISTENCE
  // ===========================================================================

  /// Serialize all settings to JSON
  String toJson() {
    return jsonEncode({
      'version': 1,
      'settings': _settings.values.map((s) => s.toJson()).toList(),
    });
  }

  /// Load settings from JSON
  void fromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final settingsData = data['settings'] as List;

      _settings.clear();

      for (final settingJson in settingsData) {
        final setting = EventZoomSettings.fromJson(settingJson as Map<String, dynamic>);
        _settings[setting.eventId] = setting;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[EventZoomService] Failed to load from JSON: $e');
    }
  }

  /// Calculate zoom level as percentage (for UI display)
  /// 100px/s = 100%, 50px/s = 50%, 200px/s = 200%
  double getZoomPercentage(String eventId) {
    final settings = getSettings(eventId);
    return (settings.pixelsPerSecond / kDefaultPixelsPerSecond) * 100;
  }

  /// Set zoom from percentage
  void setZoomPercentage(String eventId, double percentage) {
    final pixelsPerSecond = (percentage / 100) * kDefaultPixelsPerSecond;
    setPixelsPerSecond(eventId, pixelsPerSecond);
  }
}
