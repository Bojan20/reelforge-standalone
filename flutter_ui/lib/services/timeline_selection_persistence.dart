/// Timeline Selection Persistence Service
///
/// Saves and restores timeline selection state across section switches:
/// - Selected regions/clips
/// - Selection type (single/multi)
/// - Playhead position
/// - Zoom level and scroll position
///
/// Uses SharedPreferences for persistence across app restarts
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Timeline selection state
class TimelineSelectionState {
  final Set<String> selectedRegionIds;
  final String? activeTrackId;
  final double playheadPosition;
  final double zoomLevel;
  final double scrollOffsetX;
  final double scrollOffsetY;
  final DateTime timestamp;

  TimelineSelectionState({
    this.selectedRegionIds = const {},
    this.activeTrackId,
    this.playheadPosition = 0.0,
    this.zoomLevel = 1.0,
    this.scrollOffsetX = 0.0,
    this.scrollOffsetY = 0.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'selectedRegionIds': selectedRegionIds.toList(),
        'activeTrackId': activeTrackId,
        'playheadPosition': playheadPosition,
        'zoomLevel': zoomLevel,
        'scrollOffsetX': scrollOffsetX,
        'scrollOffsetY': scrollOffsetY,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TimelineSelectionState.fromJson(Map<String, dynamic> json) {
    return TimelineSelectionState(
      selectedRegionIds: (json['selectedRegionIds'] as List?)?.cast<String>().toSet() ?? {},
      activeTrackId: json['activeTrackId'] as String?,
      playheadPosition: (json['playheadPosition'] as num?)?.toDouble() ?? 0.0,
      zoomLevel: (json['zoomLevel'] as num?)?.toDouble() ?? 1.0,
      scrollOffsetX: (json['scrollOffsetX'] as num?)?.toDouble() ?? 0.0,
      scrollOffsetY: (json['scrollOffsetY'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Section identifier for timeline state
enum TimelineSection {
  daw,
  slotLab,
  middleware,
}

/// Timeline Selection Persistence Service (Singleton)
class TimelineSelectionPersistence {
  static final TimelineSelectionPersistence _instance = TimelineSelectionPersistence._internal();
  factory TimelineSelectionPersistence() => _instance;
  TimelineSelectionPersistence._internal();

  static TimelineSelectionPersistence get instance => _instance;

  SharedPreferences? _prefs;
  final Map<TimelineSection, TimelineSelectionState> _memoryCache = {};

  /// Initialize service (call once at app startup)
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadFromDisk();
  }

  /// Load all saved states from disk into memory cache
  void _loadFromDisk() {
    if (_prefs == null) return;

    for (final section in TimelineSection.values) {
      final key = _getStorageKey(section);
      final jsonString = _prefs!.getString(key);

      if (jsonString != null) {
        try {
          final json = jsonDecode(jsonString) as Map<String, dynamic>;
          _memoryCache[section] = TimelineSelectionState.fromJson(json);
        } catch (e) {
          // Invalid JSON, ignore
        }
      }
    }
  }

  /// Save timeline selection state for a section
  Future<void> saveState(TimelineSection section, TimelineSelectionState state) async {
    // Update memory cache
    _memoryCache[section] = state;

    // Persist to disk
    if (_prefs != null) {
      final key = _getStorageKey(section);
      final jsonString = jsonEncode(state.toJson());
      await _prefs!.setString(key, jsonString);
    }
  }

  /// Load timeline selection state for a section
  ///
  /// Returns null if no saved state exists
  TimelineSelectionState? loadState(TimelineSection section) {
    return _memoryCache[section];
  }

  /// Clear saved state for a section
  Future<void> clearState(TimelineSection section) async {
    _memoryCache.remove(section);

    if (_prefs != null) {
      final key = _getStorageKey(section);
      await _prefs!.remove(key);
    }
  }

  /// Clear all saved states
  Future<void> clearAll() async {
    _memoryCache.clear();

    if (_prefs != null) {
      for (final section in TimelineSection.values) {
        final key = _getStorageKey(section);
        await _prefs!.remove(key);
      }
    }
  }

  /// Get storage key for a section
  String _getStorageKey(TimelineSection section) {
    return 'timeline_selection_${section.name}';
  }

  /// Check if state exists for a section
  bool hasState(TimelineSection section) {
    return _memoryCache.containsKey(section);
  }

  /// Get all saved states
  Map<TimelineSection, TimelineSelectionState> getAllStates() {
    return Map.unmodifiable(_memoryCache);
  }

  /// Export all states to JSON (for debugging/backup)
  Map<String, dynamic> exportToJson() {
    return {
      for (final entry in _memoryCache.entries)
        entry.key.name: entry.value.toJson(),
    };
  }

  /// Import states from JSON (for debugging/restore)
  Future<void> importFromJson(Map<String, dynamic> json) async {
    _memoryCache.clear();

    for (final entry in json.entries) {
      final sectionName = entry.key;
      final section = TimelineSection.values.firstWhere(
        (s) => s.name == sectionName,
        orElse: () => TimelineSection.daw,
      );

      final state = TimelineSelectionState.fromJson(entry.value as Map<String, dynamic>);
      await saveState(section, state);
    }
  }
}

/// Helper extension for TimelineSelectionState
extension TimelineSelectionStateExtensions on TimelineSelectionState {
  /// Create a copy with updated fields
  TimelineSelectionState copyWith({
    Set<String>? selectedRegionIds,
    String? activeTrackId,
    double? playheadPosition,
    double? zoomLevel,
    double? scrollOffsetX,
    double? scrollOffsetY,
  }) {
    return TimelineSelectionState(
      selectedRegionIds: selectedRegionIds ?? this.selectedRegionIds,
      activeTrackId: activeTrackId ?? this.activeTrackId,
      playheadPosition: playheadPosition ?? this.playheadPosition,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      scrollOffsetX: scrollOffsetX ?? this.scrollOffsetX,
      scrollOffsetY: scrollOffsetY ?? this.scrollOffsetY,
      timestamp: DateTime.now(),
    );
  }

  /// Check if state is empty (no selection)
  bool get isEmpty =>
      selectedRegionIds.isEmpty &&
      activeTrackId == null &&
      playheadPosition == 0.0 &&
      zoomLevel == 1.0 &&
      scrollOffsetX == 0.0 &&
      scrollOffsetY == 0.0;

  /// Get summary string for debugging
  String get summary {
    final parts = <String>[];
    if (selectedRegionIds.isNotEmpty) {
      parts.add('${selectedRegionIds.length} region(s)');
    }
    if (activeTrackId != null) {
      parts.add('track: $activeTrackId');
    }
    if (playheadPosition > 0) {
      parts.add('playhead: ${playheadPosition.toStringAsFixed(2)}s');
    }
    if (zoomLevel != 1.0) {
      parts.add('zoom: ${(zoomLevel * 100).toInt()}%');
    }

    return parts.isEmpty ? 'empty' : parts.join(', ');
  }
}

/// Timeline selection manager (to be used in timeline widgets)
class TimelineSelectionManager {
  final TimelineSection section;
  final TimelineSelectionPersistence _persistence;

  TimelineSelectionState _currentState = TimelineSelectionState();

  TimelineSelectionManager({
    required this.section,
    TimelineSelectionPersistence? persistence,
  }) : _persistence = persistence ?? TimelineSelectionPersistence.instance;

  /// Current selection state
  TimelineSelectionState get currentState => _currentState;

  /// Load saved state for this section
  void loadSavedState() {
    final savedState = _persistence.loadState(section);
    if (savedState != null) {
      _currentState = savedState;
    }
  }

  /// Save current state
  Future<void> saveCurrentState() async {
    await _persistence.saveState(section, _currentState);
  }

  /// Update selection
  void updateSelection(Set<String> regionIds) {
    _currentState = _currentState.copyWith(selectedRegionIds: regionIds);
  }

  /// Update active track
  void updateActiveTrack(String? trackId) {
    _currentState = _currentState.copyWith(activeTrackId: trackId);
  }

  /// Update playhead position
  void updatePlayheadPosition(double position) {
    _currentState = _currentState.copyWith(playheadPosition: position);
  }

  /// Update zoom level
  void updateZoomLevel(double zoom) {
    _currentState = _currentState.copyWith(zoomLevel: zoom);
  }

  /// Update scroll position
  void updateScrollPosition(double x, double y) {
    _currentState = _currentState.copyWith(
      scrollOffsetX: x,
      scrollOffsetY: y,
    );
  }

  /// Clear selection
  void clearSelection() {
    _currentState = _currentState.copyWith(selectedRegionIds: {});
  }

  /// Reset state to defaults
  void reset() {
    _currentState = TimelineSelectionState();
  }
}
