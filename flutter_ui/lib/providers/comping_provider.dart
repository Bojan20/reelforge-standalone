// Comping Provider
//
// Multi-take recording and comping state management (Cubase/Pro Tools style):
// - Recording lane management (create, delete, activate)
// - Take management (create, rate, mute, delete)
// - Comp region management (select regions from takes for final comp)
// - Crossfade editing between comp regions
// - Flatten comp to single clip
//
// Integration with rf-core/comping.rs via FFI

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/comping_models.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class CompingProvider extends ChangeNotifier {
  // Per-track comp states
  final Map<String, CompState> _compStates = {};

  // Global state
  bool _enabled = true;
  bool _showLanesExpanded = false; // Global preference for expanded lanes
  bool _autoCreateLane = true; // Auto-create lane on first record
  double _defaultCrossfade = 0.01; // 10ms default

  // Selection
  String? _selectedTakeId;
  String? _selectedRegionId;
  final Set<String> _selectedTakeIds = {};

  // Crossfade editor state
  String? _editingCrossfadeRegionId;

  // Recording state
  String? _recordingTrackId;
  double? _recordingStartTime;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  bool get showLanesExpanded => _showLanesExpanded;
  bool get autoCreateLane => _autoCreateLane;
  double get defaultCrossfade => _defaultCrossfade;
  String? get selectedTakeId => _selectedTakeId;
  String? get selectedRegionId => _selectedRegionId;
  Set<String> get selectedTakeIds => Set.unmodifiable(_selectedTakeIds);
  String? get editingCrossfadeRegionId => _editingCrossfadeRegionId;
  bool get isRecording => _recordingTrackId != null;
  String? get recordingTrackId => _recordingTrackId;

  /// Get list of track IDs with comp states
  List<String> get tracksWithComping => _compStates.keys.toList();

  /// Get comp state for track
  CompState? getCompState(String trackId) => _compStates[trackId];

  /// Get or create comp state for track
  CompState getOrCreateCompState(String trackId) {
    return _compStates.putIfAbsent(
      trackId,
      () => CompState(trackId: trackId),
    );
  }

  /// Check if track has lanes
  bool hasLanes(String trackId) =>
      (_compStates[trackId]?.lanes.length ?? 0) > 0;

  /// Check if track has multiple lanes
  bool hasMultipleLanes(String trackId) =>
      (_compStates[trackId]?.lanes.length ?? 0) > 1;

  /// Check if track is in comp mode
  bool isCompMode(String trackId) =>
      _compStates[trackId]?.mode == CompMode.comp;

  /// Get active lane for track
  RecordingLane? getActiveLane(String trackId) =>
      _compStates[trackId]?.activeLane;

  /// Get all takes for track
  List<Take> getAllTakes(String trackId) =>
      _compStates[trackId]?.allTakes ?? [];

  /// Get takes at a specific time
  List<Take> getTakesAt(String trackId, double time) =>
      _compStates[trackId]?.takesAt(time) ?? [];

  /// Get comp regions for track
  List<CompRegion> getCompRegions(String trackId) =>
      _compStates[trackId]?.compRegions ?? [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GLOBAL CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void toggleEnabled() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void setShowLanesExpanded(bool value) {
    _showLanesExpanded = value;
    // Update all tracks
    for (final trackId in _compStates.keys) {
      _compStates[trackId] =
          _compStates[trackId]!.copyWith(lanesExpanded: value);
    }
    notifyListeners();
  }

  void toggleShowLanesExpanded() {
    setShowLanesExpanded(!_showLanesExpanded);
  }

  void setAutoCreateLane(bool value) {
    _autoCreateLane = value;
    notifyListeners();
  }

  void setDefaultCrossfade(double value) {
    _defaultCrossfade = value.clamp(0.001, 0.5); // 1ms to 500ms
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LANE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new lane for track
  RecordingLane createLane(String trackId, {String? name, Color? color}) {
    var state = getOrCreateCompState(trackId);

    // Sync to engine
    final engineTrackId = int.tryParse(trackId) ?? 0;
    if (engineTrackId > 0) {
      _syncCreateLaneToEngine(engineTrackId);
    }

    final laneId = 'lane-${DateTime.now().millisecondsSinceEpoch}';
    final newLane = RecordingLane(
      id: laneId,
      trackId: trackId,
      index: state.lanes.length,
      name: name ?? '',
      isActive: state.lanes.isEmpty, // First lane is active by default
      color: color,
    );

    state = state.copyWith(
      lanes: [...state.lanes, newLane],
      activeLaneIndex: state.lanes.isEmpty ? 0 : state.activeLaneIndex,
    );

    _compStates[trackId] = state;
    notifyListeners();
    return newLane;
  }

  void _syncCreateLaneToEngine(int trackId) {
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      ffi.compingCreateLane(trackId);
    } catch (e) {
      debugPrint('Failed to sync lane to engine: $e');
    }
  }

  /// Delete a lane
  void deleteLane(String trackId, String laneId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final lanes = state.lanes.where((l) => l.id != laneId).toList();

    // Reindex lanes
    final reindexedLanes = lanes.asMap().entries.map((entry) {
      return entry.value.copyWith(index: entry.key);
    }).toList();

    // Adjust active index
    var activeIndex = state.activeLaneIndex;
    if (activeIndex >= reindexedLanes.length) {
      activeIndex = reindexedLanes.isEmpty ? 0 : reindexedLanes.length - 1;
    }

    // Remove comp regions that reference takes from deleted lane
    final deletedTakeIds =
        state.lanes.firstWhere((l) => l.id == laneId).takes.map((t) => t.id);
    final compRegions = state.compRegions
        .where((r) => !deletedTakeIds.contains(r.takeId))
        .toList();

    _compStates[trackId] = state.copyWith(
      lanes: reindexedLanes,
      activeLaneIndex: activeIndex,
      compRegions: compRegions,
    );
    notifyListeners();
  }

  /// Set active lane
  void setActiveLane(String trackId, int index) {
    final state = _compStates[trackId];
    if (state == null) return;

    // Sync to engine
    final engineTrackId = int.tryParse(trackId) ?? 0;
    if (engineTrackId > 0) {
      _syncSetActiveLaneToEngine(engineTrackId, index);
    }

    _compStates[trackId] = state.setActiveLane(index);
    notifyListeners();
  }

  void _syncSetActiveLaneToEngine(int trackId, int index) {
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      ffi.compingSetActiveLane(trackId, index);
    } catch (e) {
      debugPrint('Failed to sync active lane to engine: $e');
    }
  }

  /// Toggle lane mute
  void toggleLaneMute(String trackId, String laneId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final lanes = state.lanes.map((l) {
      if (l.id == laneId) {
        return l.copyWith(muted: !l.muted);
      }
      return l;
    }).toList();

    _compStates[trackId] = state.copyWith(lanes: lanes);
    notifyListeners();
  }

  /// Toggle lane visibility
  void toggleLaneVisible(String trackId, String laneId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final lanes = state.lanes.map((l) {
      if (l.id == laneId) {
        return l.copyWith(visible: !l.visible);
      }
      return l;
    }).toList();

    _compStates[trackId] = state.copyWith(lanes: lanes);
    notifyListeners();
  }

  /// Set lane height
  void setLaneHeight(String trackId, String laneId, double height) {
    final state = _compStates[trackId];
    if (state == null) return;

    final clampedHeight = height.clamp(kMinLaneHeight, kMaxLaneHeight);

    final lanes = state.lanes.map((l) {
      if (l.id == laneId) {
        return l.copyWith(height: clampedHeight);
      }
      return l;
    }).toList();

    _compStates[trackId] = state.copyWith(lanes: lanes);
    notifyListeners();
  }

  /// Rename lane
  void renameLane(String trackId, String laneId, String name) {
    final state = _compStates[trackId];
    if (state == null) return;

    final lanes = state.lanes.map((l) {
      if (l.id == laneId) {
        return l.copyWith(name: name);
      }
      return l;
    }).toList();

    _compStates[trackId] = state.copyWith(lanes: lanes);
    notifyListeners();
  }

  /// Toggle lanes expanded for track
  void toggleLanesExpanded(String trackId) {
    final state = _compStates[trackId];
    if (state == null) return;

    _compStates[trackId] = state.toggleLanesExpanded();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAKE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a take to active lane
  Take addTake(
    String trackId, {
    required String sourcePath,
    required double startTime,
    required double duration,
    String? laneId,
  }) {
    var state = getOrCreateCompState(trackId);

    // Create lane if needed
    if (state.lanes.isEmpty) {
      createLane(trackId);
      state = _compStates[trackId]!;
    }

    final targetLaneId = laneId ?? state.activeLane?.id;
    if (targetLaneId == null) {
      throw StateError('No lane available for take');
    }

    // Sync to engine
    final engineTrackId = int.tryParse(trackId) ?? 0;
    if (engineTrackId > 0) {
      _syncAddTakeToEngine(engineTrackId, sourcePath, startTime, duration);
    }

    final takeId = 'take-${DateTime.now().millisecondsSinceEpoch}';
    final take = Take(
      id: takeId,
      laneId: targetLaneId,
      trackId: trackId,
      takeNumber: state.nextTakeNumber,
      startTime: startTime,
      duration: duration,
      sourcePath: sourcePath,
      sourceDuration: duration,
      recordedAt: DateTime.now(),
    );

    _compStates[trackId] = state.addTake(take, laneId: targetLaneId);
    notifyListeners();
    return take;
  }

  void _syncAddTakeToEngine(int trackId, String sourcePath, double startTime, double duration) {
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      ffi.compingAddTake(trackId, sourcePath, startTime, duration);
    } catch (e) {
      debugPrint('Failed to sync take to engine: $e');
    }
  }

  /// Delete a take
  void deleteTake(String trackId, String takeId) {
    final state = _compStates[trackId];
    if (state == null) return;

    // Remove take from lane
    final lanes = state.lanes.map((l) {
      return l.copyWith(
        takes: l.takes.where((t) => t.id != takeId).toList(),
      );
    }).toList();

    // Remove comp regions that reference this take
    final compRegions =
        state.compRegions.where((r) => r.takeId != takeId).toList();

    _compStates[trackId] = state.copyWith(
      lanes: lanes,
      compRegions: compRegions,
    );

    // Clear selection if deleted take was selected
    if (_selectedTakeId == takeId) {
      _selectedTakeId = null;
    }
    _selectedTakeIds.remove(takeId);

    notifyListeners();
  }

  /// Set take rating
  void setTakeRating(String trackId, String takeId, TakeRating rating) {
    _updateTake(trackId, takeId, (t) => t.copyWith(rating: rating));
  }

  /// Toggle take mute
  void toggleTakeMute(String trackId, String takeId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final take = state.allTakes.firstWhere((t) => t.id == takeId);
    _updateTake(trackId, takeId, (t) => t.copyWith(muted: !take.muted));
  }

  /// Toggle take in comp
  void toggleTakeInComp(String trackId, String takeId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final take = state.allTakes.firstWhere((t) => t.id == takeId);
    _updateTake(trackId, takeId, (t) => t.copyWith(inComp: !take.inComp));
  }

  /// Set take gain
  void setTakeGain(String trackId, String takeId, double gain) {
    _updateTake(
        trackId, takeId, (t) => t.copyWith(gain: gain.clamp(0.0, 2.0)));
  }

  /// Set take fade in
  void setTakeFadeIn(String trackId, String takeId, double fadeIn) {
    _updateTake(trackId, takeId,
        (t) => t.copyWith(fadeIn: fadeIn.clamp(0.0, t.duration / 2)));
  }

  /// Set take fade out
  void setTakeFadeOut(String trackId, String takeId, double fadeOut) {
    _updateTake(trackId, takeId,
        (t) => t.copyWith(fadeOut: fadeOut.clamp(0.0, t.duration / 2)));
  }

  /// Rename take
  void renameTake(String trackId, String takeId, String name) {
    _updateTake(trackId, takeId, (t) => t.copyWith(name: name));
  }

  /// Lock/unlock take
  void setTakeLocked(String trackId, String takeId, bool locked) {
    _updateTake(trackId, takeId, (t) => t.copyWith(locked: locked));
  }

  void _updateTake(String trackId, String takeId, Take Function(Take) updater) {
    final state = _compStates[trackId];
    if (state == null) return;

    final lanes = state.lanes.map((l) {
      final takes = l.takes.map((t) {
        if (t.id == takeId) {
          return updater(t);
        }
        return t;
      }).toList();
      return l.copyWith(takes: takes);
    }).toList();

    _compStates[trackId] = state.copyWith(lanes: lanes);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMP REGION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a comp region from a take selection
  CompRegion createCompRegion(
    String trackId,
    String takeId,
    double startTime,
    double endTime,
  ) {
    var state = getOrCreateCompState(trackId);

    // Sync to engine
    final engineTrackId = int.tryParse(trackId) ?? 0;
    final engineTakeId = int.tryParse(takeId.replaceAll('take-', '')) ?? 0;
    if (engineTrackId > 0) {
      _syncCreateRegionToEngine(engineTrackId, engineTakeId, startTime, endTime);
    }

    final regionId = 'region-${DateTime.now().millisecondsSinceEpoch}';
    final region = CompRegion(
      id: regionId,
      trackId: trackId,
      takeId: takeId,
      startTime: startTime,
      endTime: endTime,
      crossfadeIn: _defaultCrossfade,
      crossfadeOut: _defaultCrossfade,
    );

    _compStates[trackId] = state.addCompRegion(region);
    notifyListeners();
    return region;
  }

  void _syncCreateRegionToEngine(int trackId, int takeId, double startTime, double endTime) {
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      ffi.compingCreateRegion(trackId, takeId, startTime, endTime);
    } catch (e) {
      debugPrint('Failed to sync comp region to engine: $e');
    }
  }

  /// Delete a comp region
  void deleteCompRegion(String trackId, String regionId) {
    final state = _compStates[trackId];
    if (state == null) return;

    _compStates[trackId] = state.removeCompRegion(regionId);

    if (_selectedRegionId == regionId) {
      _selectedRegionId = null;
    }
    if (_editingCrossfadeRegionId == regionId) {
      _editingCrossfadeRegionId = null;
    }

    notifyListeners();
  }

  /// Set comp region crossfade in
  void setRegionCrossfadeIn(String trackId, String regionId, double duration) {
    _updateRegion(trackId, regionId,
        (r) => r.copyWith(crossfadeIn: duration.clamp(0.0, r.duration / 2)));
  }

  /// Set comp region crossfade out
  void setRegionCrossfadeOut(String trackId, String regionId, double duration) {
    _updateRegion(trackId, regionId,
        (r) => r.copyWith(crossfadeOut: duration.clamp(0.0, r.duration / 2)));
  }

  /// Set comp region crossfade type
  void setRegionCrossfadeType(
      String trackId, String regionId, CompCrossfadeType type) {
    _updateRegion(trackId, regionId, (r) => r.copyWith(crossfadeType: type));
  }

  /// Adjust comp region boundaries
  void setRegionBoundaries(
      String trackId, String regionId, double startTime, double endTime) {
    _updateRegion(trackId, regionId,
        (r) => r.copyWith(startTime: startTime, endTime: endTime));
  }

  void _updateRegion(
      String trackId, String regionId, CompRegion Function(CompRegion) updater) {
    final state = _compStates[trackId];
    if (state == null) return;

    final regions = state.compRegions.map((r) {
      if (r.id == regionId) {
        return updater(r);
      }
      return r;
    }).toList();

    _compStates[trackId] = state.copyWith(compRegions: regions);
    notifyListeners();
  }

  /// Clear all comp regions for track
  void clearComp(String trackId) {
    final state = _compStates[trackId];
    if (state == null) return;

    _compStates[trackId] = state.clearComp();
    _selectedRegionId = null;
    _editingCrossfadeRegionId = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMP MODE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set comp mode for track
  void setCompMode(String trackId, CompMode mode) {
    final state = _compStates[trackId];
    if (state == null) return;

    // Sync to engine
    final engineTrackId = int.tryParse(trackId) ?? 0;
    if (engineTrackId > 0) {
      _syncCompModeToEngine(engineTrackId, mode);
    }

    _compStates[trackId] = state.copyWith(mode: mode);
    notifyListeners();
  }

  void _syncCompModeToEngine(int trackId, CompMode mode) {
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      final modeIndex = switch (mode) {
        CompMode.single => 0,
        CompMode.comp => 1,
        CompMode.auditAll => 2,
      };
      ffi.compingSetMode(trackId, modeIndex);
    } catch (e) {
      debugPrint('Failed to sync comp mode to engine: $e');
    }
  }

  /// Toggle between single and comp mode
  void toggleCompMode(String trackId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final newMode =
        state.mode == CompMode.comp ? CompMode.single : CompMode.comp;
    setCompMode(trackId, newMode);
  }

  /// Enable audit all mode (play all lanes stacked)
  void enableAuditAll(String trackId) {
    setCompMode(trackId, CompMode.auditAll);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  void selectTake(String takeId) {
    _selectedTakeId = takeId;
    _selectedRegionId = null;
    notifyListeners();
  }

  void deselectTake() {
    _selectedTakeId = null;
    notifyListeners();
  }

  void selectRegion(String regionId) {
    _selectedRegionId = regionId;
    _selectedTakeId = null;
    notifyListeners();
  }

  void deselectRegion() {
    _selectedRegionId = null;
    notifyListeners();
  }

  void addToTakeSelection(String takeId) {
    _selectedTakeIds.add(takeId);
    notifyListeners();
  }

  void removeFromTakeSelection(String takeId) {
    _selectedTakeIds.remove(takeId);
    notifyListeners();
  }

  void toggleTakeSelection(String takeId) {
    if (_selectedTakeIds.contains(takeId)) {
      _selectedTakeIds.remove(takeId);
    } else {
      _selectedTakeIds.add(takeId);
    }
    notifyListeners();
  }

  void clearTakeSelection() {
    _selectedTakeIds.clear();
    notifyListeners();
  }

  void clearAllSelection() {
    _selectedTakeId = null;
    _selectedRegionId = null;
    _selectedTakeIds.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CROSSFADE EDITOR
  // ═══════════════════════════════════════════════════════════════════════════

  void startEditingCrossfade(String regionId) {
    _editingCrossfadeRegionId = regionId;
    notifyListeners();
  }

  void stopEditingCrossfade() {
    _editingCrossfadeRegionId = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start recording on track
  void startRecording(String trackId, double startTime) {
    var state = getOrCreateCompState(trackId);

    // Create lane if needed and autoCreateLane is enabled
    if (state.lanes.isEmpty && _autoCreateLane) {
      createLane(trackId);
      state = _compStates[trackId]!;
    }

    _recordingTrackId = trackId;
    _recordingStartTime = startTime;
    _compStates[trackId] = state.startRecording(startTime);
    notifyListeners();
  }

  /// Stop recording and create take
  void stopRecording(String sourcePath, double duration) {
    if (_recordingTrackId == null || _recordingStartTime == null) return;

    final trackId = _recordingTrackId!;
    final startTime = _recordingStartTime!;

    // Add the take
    addTake(
      trackId,
      sourcePath: sourcePath,
      startTime: startTime,
      duration: duration,
    );

    // Clear recording state
    final state = _compStates[trackId];
    if (state != null) {
      _compStates[trackId] = state.copyWith(
        isRecording: false,
        recordingStartTime: null,
      );
    }

    _recordingTrackId = null;
    _recordingStartTime = null;
    notifyListeners();
  }

  /// Cancel recording without creating take
  void cancelRecording() {
    if (_recordingTrackId == null) return;

    final state = _compStates[_recordingTrackId!];
    if (state != null) {
      _compStates[_recordingTrackId!] = state.copyWith(
        isRecording: false,
        recordingStartTime: null,
      );
    }

    _recordingTrackId = null;
    _recordingStartTime = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLATTEN COMP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Flatten comp regions to a single clip (returns the new clip path)
  /// This would typically call into Rust to render the comp
  Future<String?> flattenComp(String trackId, String outputPath) async {
    final state = _compStates[trackId];
    if (state == null || state.compRegions.isEmpty) return null;

    // TODO: Call Rust FFI to render comp regions to single file
    // This would involve:
    // 1. For each region, get audio from the referenced take
    // 2. Apply crossfades between regions
    // 3. Render to output file

    // For now, return null (not implemented)
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BULK OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Delete all takes with "bad" rating
  void deleteBadTakes(String trackId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final lanes = state.lanes.map((l) {
      return l.copyWith(
        takes: l.takes.where((t) => t.rating != TakeRating.bad).toList(),
      );
    }).toList();

    _compStates[trackId] = state.copyWith(lanes: lanes);
    notifyListeners();
  }

  /// Promote "best" takes to comp
  void promoteBestTakes(String trackId) {
    final state = _compStates[trackId];
    if (state == null) return;

    final bestTakes =
        state.allTakes.where((t) => t.rating == TakeRating.best).toList();

    // Sort by start time
    bestTakes.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Clear existing comp and create regions from best takes
    var newState = state.clearComp();

    for (final take in bestTakes) {
      final region = CompRegion(
        id: 'region-${DateTime.now().millisecondsSinceEpoch}-${take.id}',
        trackId: trackId,
        takeId: take.id,
        startTime: take.startTime,
        endTime: take.endTime,
        crossfadeIn: _defaultCrossfade,
        crossfadeOut: _defaultCrossfade,
      );
      newState = newState.addCompRegion(region);
    }

    _compStates[trackId] = newState;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'showLanesExpanded': _showLanesExpanded,
      'autoCreateLane': _autoCreateLane,
      'defaultCrossfade': _defaultCrossfade,
      'compStates': _compStates.map((trackId, state) {
        return MapEntry(trackId, _compStateToJson(state));
      }),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? true;
    _showLanesExpanded = json['showLanesExpanded'] ?? false;
    _autoCreateLane = json['autoCreateLane'] ?? true;
    _defaultCrossfade = (json['defaultCrossfade'] ?? 0.01).toDouble();

    _compStates.clear();
    if (json['compStates'] != null) {
      final states = json['compStates'] as Map<String, dynamic>;
      for (final entry in states.entries) {
        _compStates[entry.key] =
            _compStateFromJson(entry.value as Map<String, dynamic>);
      }
    }

    notifyListeners();
  }

  Map<String, dynamic> _compStateToJson(CompState state) {
    return {
      'trackId': state.trackId,
      'mode': state.mode.index,
      'lanesExpanded': state.lanesExpanded,
      'activeLaneIndex': state.activeLaneIndex,
      'nextTakeNumber': state.nextTakeNumber,
      'lanes': state.lanes.map((l) => _laneToJson(l)).toList(),
      'compRegions': state.compRegions.map((r) => _regionToJson(r)).toList(),
    };
  }

  CompState _compStateFromJson(Map<String, dynamic> json) {
    return CompState(
      trackId: json['trackId'],
      mode: CompMode.values[json['mode'] ?? 0],
      lanesExpanded: json['lanesExpanded'] ?? false,
      activeLaneIndex: json['activeLaneIndex'] ?? 0,
      nextTakeNumber: json['nextTakeNumber'] ?? 1,
      lanes: (json['lanes'] as List?)
              ?.map((l) => _laneFromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      compRegions: (json['compRegions'] as List?)
              ?.map((r) => _regionFromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> _laneToJson(RecordingLane lane) {
    return {
      'id': lane.id,
      'trackId': lane.trackId,
      'index': lane.index,
      'name': lane.name,
      'height': lane.height,
      'visible': lane.visible,
      'isActive': lane.isActive,
      'isCompLane': lane.isCompLane,
      'muted': lane.muted,
      'color': lane.color?.toARGB32(),
      'takes': lane.takes.map((t) => _takeToJson(t)).toList(),
    };
  }

  RecordingLane _laneFromJson(Map<String, dynamic> json) {
    return RecordingLane(
      id: json['id'],
      trackId: json['trackId'],
      index: json['index'] ?? 0,
      name: json['name'] ?? '',
      height: (json['height'] ?? 60.0).toDouble(),
      visible: json['visible'] ?? true,
      isActive: json['isActive'] ?? false,
      isCompLane: json['isCompLane'] ?? false,
      muted: json['muted'] ?? false,
      color: json['color'] != null ? Color(json['color']) : null,
      takes: (json['takes'] as List?)
              ?.map((t) => _takeFromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> _takeToJson(Take take) {
    return {
      'id': take.id,
      'laneId': take.laneId,
      'trackId': take.trackId,
      'takeNumber': take.takeNumber,
      'name': take.name,
      'startTime': take.startTime,
      'duration': take.duration,
      'sourcePath': take.sourcePath,
      'sourceOffset': take.sourceOffset,
      'sourceDuration': take.sourceDuration,
      'rating': take.rating.index,
      'recordedAt': take.recordedAt.millisecondsSinceEpoch,
      'inComp': take.inComp,
      'gain': take.gain,
      'fadeIn': take.fadeIn,
      'fadeOut': take.fadeOut,
      'muted': take.muted,
      'locked': take.locked,
    };
  }

  Take _takeFromJson(Map<String, dynamic> json) {
    return Take(
      id: json['id'],
      laneId: json['laneId'],
      trackId: json['trackId'],
      takeNumber: json['takeNumber'] ?? 1,
      name: json['name'],
      startTime: (json['startTime'] ?? 0.0).toDouble(),
      duration: (json['duration'] ?? 0.0).toDouble(),
      sourcePath: json['sourcePath'] ?? '',
      sourceOffset: (json['sourceOffset'] ?? 0.0).toDouble(),
      sourceDuration: (json['sourceDuration'] ?? 0.0).toDouble(),
      rating: TakeRating.values[json['rating'] ?? 0],
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
          json['recordedAt'] ?? DateTime.now().millisecondsSinceEpoch),
      inComp: json['inComp'] ?? false,
      gain: (json['gain'] ?? 1.0).toDouble(),
      fadeIn: (json['fadeIn'] ?? 0.0).toDouble(),
      fadeOut: (json['fadeOut'] ?? 0.0).toDouble(),
      muted: json['muted'] ?? false,
      locked: json['locked'] ?? false,
    );
  }

  Map<String, dynamic> _regionToJson(CompRegion region) {
    return {
      'id': region.id,
      'trackId': region.trackId,
      'takeId': region.takeId,
      'startTime': region.startTime,
      'endTime': region.endTime,
      'crossfadeIn': region.crossfadeIn,
      'crossfadeOut': region.crossfadeOut,
      'crossfadeType': region.crossfadeType.index,
    };
  }

  CompRegion _regionFromJson(Map<String, dynamic> json) {
    return CompRegion(
      id: json['id'],
      trackId: json['trackId'],
      takeId: json['takeId'],
      startTime: (json['startTime'] ?? 0.0).toDouble(),
      endTime: (json['endTime'] ?? 0.0).toDouble(),
      crossfadeIn: (json['crossfadeIn'] ?? 0.01).toDouble(),
      crossfadeOut: (json['crossfadeOut'] ?? 0.01).toDouble(),
      crossfadeType: CompCrossfadeType.values[json['crossfadeType'] ?? 1],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _compStates.clear();
    _enabled = true;
    _showLanesExpanded = false;
    _autoCreateLane = true;
    _defaultCrossfade = 0.01;
    _selectedTakeId = null;
    _selectedRegionId = null;
    _selectedTakeIds.clear();
    _editingCrossfadeRegionId = null;
    _recordingTrackId = null;
    _recordingStartTime = null;
    notifyListeners();
  }

  /// Remove comp state for track
  void removeTrack(String trackId) {
    _compStates.remove(trackId);
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
