// Track Versions Provider
//
// Cubase-style track versions (similar to Pro Tools Playlists):
// - Multiple versions of content per track
// - Quick A/B comparison between takes
// - Non-destructive version switching
// - Version naming and color coding
// - Create version from selection
// - Duplicate/delete versions
//
// Use cases:
// - Keep multiple vocal takes, comp the best
// - Try different MIDI arrangements
// - Before/after comparison

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Content type in a version
enum VersionContentType {
  audio,    // Audio clips
  midi,     // MIDI events
  mixed,    // Both (for instrument tracks)
}

/// A clip snapshot within a version
class VersionClip {
  final String id;
  final String originalClipId;  // Reference to actual clip
  final int startTick;          // Position in PPQ ticks
  final int lengthTick;         // Length in PPQ ticks
  final double gain;            // Clip gain
  final double fadeInLength;    // Fade in (seconds)
  final double fadeOutLength;   // Fade out (seconds)
  final bool muted;

  const VersionClip({
    required this.id,
    required this.originalClipId,
    required this.startTick,
    required this.lengthTick,
    this.gain = 1.0,
    this.fadeInLength = 0.0,
    this.fadeOutLength = 0.0,
    this.muted = false,
  });

  VersionClip copyWith({
    String? id,
    String? originalClipId,
    int? startTick,
    int? lengthTick,
    double? gain,
    double? fadeInLength,
    double? fadeOutLength,
    bool? muted,
  }) {
    return VersionClip(
      id: id ?? this.id,
      originalClipId: originalClipId ?? this.originalClipId,
      startTick: startTick ?? this.startTick,
      lengthTick: lengthTick ?? this.lengthTick,
      gain: gain ?? this.gain,
      fadeInLength: fadeInLength ?? this.fadeInLength,
      fadeOutLength: fadeOutLength ?? this.fadeOutLength,
      muted: muted ?? this.muted,
    );
  }
}

/// A single track version
class TrackVersion {
  final String id;
  final String name;
  final String? description;
  final Color color;
  final DateTime createdAt;
  final DateTime modifiedAt;

  // Content
  final List<VersionClip> clips;
  final VersionContentType contentType;

  // State
  final bool isActive;
  final bool isLocked;     // Prevent accidental changes

  const TrackVersion({
    required this.id,
    required this.name,
    this.description,
    this.color = const Color(0xFF4A9EFF),
    required this.createdAt,
    required this.modifiedAt,
    this.clips = const [],
    this.contentType = VersionContentType.audio,
    this.isActive = false,
    this.isLocked = false,
  });

  TrackVersion copyWith({
    String? id,
    String? name,
    String? description,
    Color? color,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<VersionClip>? clips,
    VersionContentType? contentType,
    bool? isActive,
    bool? isLocked,
  }) {
    return TrackVersion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      clips: clips ?? this.clips,
      contentType: contentType ?? this.contentType,
      isActive: isActive ?? this.isActive,
      isLocked: isLocked ?? this.isLocked,
    );
  }

  /// Get clip count
  int get clipCount => clips.length;

  /// Get total duration in ticks
  int get totalDuration {
    if (clips.isEmpty) return 0;
    return clips.map((c) => c.startTick + c.lengthTick).reduce((a, b) => a > b ? a : b);
  }
}

/// Track version container (all versions for a track)
class TrackVersionContainer {
  final int trackId;
  final List<TrackVersion> versions;
  final String? activeVersionId;

  // Comparison mode
  final String? compareVersionId;  // Version to compare with active

  const TrackVersionContainer({
    required this.trackId,
    this.versions = const [],
    this.activeVersionId,
    this.compareVersionId,
  });

  TrackVersionContainer copyWith({
    int? trackId,
    List<TrackVersion>? versions,
    String? activeVersionId,
    String? compareVersionId,
  }) {
    return TrackVersionContainer(
      trackId: trackId ?? this.trackId,
      versions: versions ?? this.versions,
      activeVersionId: activeVersionId ?? this.activeVersionId,
      compareVersionId: compareVersionId ?? this.compareVersionId,
    );
  }

  /// Get active version
  TrackVersion? get activeVersion {
    if (activeVersionId == null) return versions.isNotEmpty ? versions.first : null;
    return versions.cast<TrackVersion?>().firstWhere(
      (v) => v?.id == activeVersionId,
      orElse: () => versions.isNotEmpty ? versions.first : null,
    );
  }

  /// Get compare version
  TrackVersion? get compareVersion {
    if (compareVersionId == null) return null;
    return versions.cast<TrackVersion?>().firstWhere(
      (v) => v?.id == compareVersionId,
      orElse: () => null,
    );
  }

  /// Get version by ID
  TrackVersion? getVersion(String id) {
    return versions.cast<TrackVersion?>().firstWhere(
      (v) => v?.id == id,
      orElse: () => null,
    );
  }

  /// Check if in compare mode
  bool get isComparing => compareVersionId != null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class TrackVersionsProvider extends ChangeNotifier {
  // Version containers per track
  final Map<int, TrackVersionContainer> _containers = {};

  // Global state
  bool _enabled = true;
  bool _showVersionLane = false;  // Show version lane in track header

  // Selected for batch operations
  final Set<String> _selectedVersionIds = {};

  // Undo history per track
  final Map<int, List<TrackVersion>> _undoHistory = {};
  final Map<int, List<TrackVersion>> _redoHistory = {};

  // Version naming counter
  int _versionCounter = 1;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  bool get showVersionLane => _showVersionLane;
  Set<String> get selectedVersionIds => Set.unmodifiable(_selectedVersionIds);

  /// Get list of track IDs that have versions
  List<int> get tracksWithVersions => _containers.keys.toList();

  /// Get container for track
  TrackVersionContainer? getContainer(int trackId) => _containers[trackId];

  /// Get all versions for track
  List<TrackVersion> getVersions(int trackId) =>
      _containers[trackId]?.versions ?? [];

  /// Get active version for track
  TrackVersion? getActiveVersion(int trackId) =>
      _containers[trackId]?.activeVersion;

  /// Get compare version for track
  TrackVersion? getCompareVersion(int trackId) =>
      _containers[trackId]?.compareVersion;

  /// Check if track has multiple versions
  bool hasMultipleVersions(int trackId) =>
      (_containers[trackId]?.versions.length ?? 0) > 1;

  /// Check if track is in compare mode
  bool isComparing(int trackId) =>
      _containers[trackId]?.isComparing ?? false;

  /// Can undo for track
  bool canUndo(int trackId) =>
      (_undoHistory[trackId]?.isNotEmpty ?? false);

  /// Can redo for track
  bool canRedo(int trackId) =>
      (_redoHistory[trackId]?.isNotEmpty ?? false);

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

  void setShowVersionLane(bool value) {
    _showVersionLane = value;
    notifyListeners();
  }

  void toggleShowVersionLane() {
    _showVersionLane = !_showVersionLane;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VERSION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create new version for track
  TrackVersion createVersion(
    int trackId, {
    String? name,
    String? description,
    Color? color,
    List<VersionClip>? clips,
    VersionContentType contentType = VersionContentType.audio,
    bool activate = true,
  }) {
    final id = 'version_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    final version = TrackVersion(
      id: id,
      name: name ?? 'Version ${_versionCounter++}',
      description: description,
      color: color ?? _getDefaultColor(_containers[trackId]?.versions.length ?? 0),
      createdAt: now,
      modifiedAt: now,
      clips: clips ?? [],
      contentType: contentType,
      isActive: activate,
    );

    // Get or create container
    var container = _containers[trackId];
    if (container == null) {
      container = TrackVersionContainer(
        trackId: trackId,
        versions: [version],
        activeVersionId: version.id,
      );
    } else {
      // Deactivate current active if activating new
      var versions = container.versions;
      if (activate) {
        versions = versions.map((v) => v.copyWith(isActive: false)).toList();
      }
      versions = [...versions, version];

      container = container.copyWith(
        versions: versions,
        activeVersionId: activate ? version.id : container.activeVersionId,
      );
    }

    _containers[trackId] = container;
    notifyListeners();
    return version;
  }

  /// Duplicate version
  TrackVersion duplicateVersion(int trackId, String versionId) {
    final container = _containers[trackId];
    if (container == null) throw StateError('No versions for track');

    final original = container.getVersion(versionId);
    if (original == null) throw StateError('Version not found');

    return createVersion(
      trackId,
      name: '${original.name} (Copy)',
      description: original.description,
      color: original.color,
      clips: original.clips.map((c) => c.copyWith(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}_${c.id}',
      )).toList(),
      contentType: original.contentType,
      activate: false,
    );
  }

  /// Delete version
  void deleteVersion(int trackId, String versionId) {
    final container = _containers[trackId];
    if (container == null) return;

    final versions = container.versions.where((v) => v.id != versionId).toList();

    if (versions.isEmpty) {
      // Remove container if no versions left
      _containers.remove(trackId);
    } else {
      // Update active if deleted version was active
      var activeId = container.activeVersionId;
      if (activeId == versionId) {
        activeId = versions.first.id;
        versions[0] = versions[0].copyWith(isActive: true);
      }

      _containers[trackId] = container.copyWith(
        versions: versions,
        activeVersionId: activeId,
        compareVersionId: container.compareVersionId == versionId ? null : container.compareVersionId,
      );
    }

    _selectedVersionIds.remove(versionId);
    notifyListeners();
  }

  /// Rename version
  void renameVersion(int trackId, String versionId, String newName) {
    _updateVersion(trackId, versionId, (v) => v.copyWith(name: newName));
  }

  /// Set version description
  void setVersionDescription(int trackId, String versionId, String? description) {
    _updateVersion(trackId, versionId, (v) => v.copyWith(description: description));
  }

  /// Set version color
  void setVersionColor(int trackId, String versionId, Color color) {
    _updateVersion(trackId, versionId, (v) => v.copyWith(color: color));
  }

  /// Lock/unlock version
  void setVersionLocked(int trackId, String versionId, bool locked) {
    _updateVersion(trackId, versionId, (v) => v.copyWith(isLocked: locked));
  }

  /// Toggle version lock
  void toggleVersionLocked(int trackId, String versionId) {
    final version = _containers[trackId]?.getVersion(versionId);
    if (version != null) {
      setVersionLocked(trackId, versionId, !version.isLocked);
    }
  }

  void _updateVersion(int trackId, String versionId, TrackVersion Function(TrackVersion) updater) {
    final container = _containers[trackId];
    if (container == null) return;

    final versions = container.versions.map((v) {
      if (v.id == versionId) {
        return updater(v).copyWith(modifiedAt: DateTime.now());
      }
      return v;
    }).toList();

    _containers[trackId] = container.copyWith(versions: versions);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VERSION ACTIVATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Activate version
  void activateVersion(int trackId, String versionId) {
    final container = _containers[trackId];
    if (container == null) return;

    final versions = container.versions.map((v) {
      return v.copyWith(isActive: v.id == versionId);
    }).toList();

    _containers[trackId] = container.copyWith(
      versions: versions,
      activeVersionId: versionId,
    );
    notifyListeners();
  }

  /// Cycle to next version
  void nextVersion(int trackId) {
    final container = _containers[trackId];
    if (container == null || container.versions.length < 2) return;

    final currentIndex = container.versions.indexWhere(
      (v) => v.id == container.activeVersionId
    );
    final nextIndex = (currentIndex + 1) % container.versions.length;
    activateVersion(trackId, container.versions[nextIndex].id);
  }

  /// Cycle to previous version
  void previousVersion(int trackId) {
    final container = _containers[trackId];
    if (container == null || container.versions.length < 2) return;

    final currentIndex = container.versions.indexWhere(
      (v) => v.id == container.activeVersionId
    );
    final prevIndex = (currentIndex - 1 + container.versions.length) % container.versions.length;
    activateVersion(trackId, container.versions[prevIndex].id);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPARE MODE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start comparing with another version
  void startCompare(int trackId, String versionId) {
    final container = _containers[trackId];
    if (container == null) return;

    // Don't compare with active version
    if (versionId == container.activeVersionId) return;

    _containers[trackId] = container.copyWith(compareVersionId: versionId);
    notifyListeners();
  }

  /// Stop comparing
  void stopCompare(int trackId) {
    final container = _containers[trackId];
    if (container == null) return;

    _containers[trackId] = container.copyWith(compareVersionId: null);
    notifyListeners();
  }

  /// Toggle compare with version
  void toggleCompare(int trackId, String versionId) {
    final container = _containers[trackId];
    if (container == null) return;

    if (container.compareVersionId == versionId) {
      stopCompare(trackId);
    } else {
      startCompare(trackId, versionId);
    }
  }

  /// Swap active and compare versions
  void swapVersions(int trackId) {
    final container = _containers[trackId];
    if (container == null || container.compareVersionId == null) return;

    final oldActive = container.activeVersionId;
    final oldCompare = container.compareVersionId;

    final versions = container.versions.map((v) {
      return v.copyWith(isActive: v.id == oldCompare);
    }).toList();

    _containers[trackId] = container.copyWith(
      versions: versions,
      activeVersionId: oldCompare,
      compareVersionId: oldActive,
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add clip to active version
  void addClipToVersion(int trackId, VersionClip clip) {
    final container = _containers[trackId];
    if (container == null) return;

    final activeId = container.activeVersionId;
    if (activeId == null) return;

    final versions = container.versions.map((v) {
      if (v.id == activeId && !v.isLocked) {
        return v.copyWith(
          clips: [...v.clips, clip],
          modifiedAt: DateTime.now(),
        );
      }
      return v;
    }).toList();

    _containers[trackId] = container.copyWith(versions: versions);
    notifyListeners();
  }

  /// Remove clip from active version
  void removeClipFromVersion(int trackId, String clipId) {
    final container = _containers[trackId];
    if (container == null) return;

    final activeId = container.activeVersionId;
    if (activeId == null) return;

    final versions = container.versions.map((v) {
      if (v.id == activeId && !v.isLocked) {
        return v.copyWith(
          clips: v.clips.where((c) => c.id != clipId).toList(),
          modifiedAt: DateTime.now(),
        );
      }
      return v;
    }).toList();

    _containers[trackId] = container.copyWith(versions: versions);
    notifyListeners();
  }

  /// Update clip in active version
  void updateClipInVersion(int trackId, VersionClip clip) {
    final container = _containers[trackId];
    if (container == null) return;

    final activeId = container.activeVersionId;
    if (activeId == null) return;

    final versions = container.versions.map((v) {
      if (v.id == activeId && !v.isLocked) {
        return v.copyWith(
          clips: v.clips.map((c) => c.id == clip.id ? clip : c).toList(),
          modifiedAt: DateTime.now(),
        );
      }
      return v;
    }).toList();

    _containers[trackId] = container.copyWith(versions: versions);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  void selectVersion(String versionId) {
    _selectedVersionIds.add(versionId);
    notifyListeners();
  }

  void deselectVersion(String versionId) {
    _selectedVersionIds.remove(versionId);
    notifyListeners();
  }

  void toggleVersionSelection(String versionId) {
    if (_selectedVersionIds.contains(versionId)) {
      _selectedVersionIds.remove(versionId);
    } else {
      _selectedVersionIds.add(versionId);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedVersionIds.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Color _getDefaultColor(int index) {
    const colors = [
      Color(0xFF4A9EFF),  // Blue
      Color(0xFF40FF90),  // Green
      Color(0xFFFF9040),  // Orange
      Color(0xFFAA40FF),  // Purple
      Color(0xFF40C8FF),  // Cyan
      Color(0xFFFF4060),  // Red
      Color(0xFFFFDD40),  // Yellow
      Color(0xFFFF40FF),  // Magenta
    ];
    return colors[index % colors.length];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'showVersionLane': _showVersionLane,
      'versionCounter': _versionCounter,
      'containers': _containers.entries.map((e) => {
        'trackId': e.key,
        'activeVersionId': e.value.activeVersionId,
        'compareVersionId': e.value.compareVersionId,
        'versions': e.value.versions.map((v) => _versionToJson(v)).toList(),
      }).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? true;
    _showVersionLane = json['showVersionLane'] ?? false;
    _versionCounter = json['versionCounter'] ?? 1;

    _containers.clear();
    if (json['containers'] != null) {
      for (final c in json['containers']) {
        final trackId = c['trackId'] as int;
        final versions = (c['versions'] as List?)
            ?.map((v) => _versionFromJson(v))
            .toList() ?? [];

        _containers[trackId] = TrackVersionContainer(
          trackId: trackId,
          versions: versions,
          activeVersionId: c['activeVersionId'],
          compareVersionId: c['compareVersionId'],
        );
      }
    }

    notifyListeners();
  }

  Map<String, dynamic> _versionToJson(TrackVersion v) {
    return {
      'id': v.id,
      'name': v.name,
      'description': v.description,
      'color': v.color.toARGB32(),
      'createdAt': v.createdAt.toIso8601String(),
      'modifiedAt': v.modifiedAt.toIso8601String(),
      'contentType': v.contentType.index,
      'isActive': v.isActive,
      'isLocked': v.isLocked,
      'clips': v.clips.map((c) => _clipToJson(c)).toList(),
    };
  }

  TrackVersion _versionFromJson(Map<String, dynamic> json) {
    return TrackVersion(
      id: json['id'],
      name: json['name'] ?? 'Version',
      description: json['description'],
      color: Color(json['color'] ?? 0xFF4A9EFF),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      modifiedAt: DateTime.parse(json['modifiedAt'] ?? DateTime.now().toIso8601String()),
      contentType: VersionContentType.values[json['contentType'] ?? 0],
      isActive: json['isActive'] ?? false,
      isLocked: json['isLocked'] ?? false,
      clips: (json['clips'] as List?)
          ?.map((c) => _clipFromJson(c))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> _clipToJson(VersionClip c) {
    return {
      'id': c.id,
      'originalClipId': c.originalClipId,
      'startTick': c.startTick,
      'lengthTick': c.lengthTick,
      'gain': c.gain,
      'fadeInLength': c.fadeInLength,
      'fadeOutLength': c.fadeOutLength,
      'muted': c.muted,
    };
  }

  VersionClip _clipFromJson(Map<String, dynamic> json) {
    return VersionClip(
      id: json['id'],
      originalClipId: json['originalClipId'],
      startTick: json['startTick'] ?? 0,
      lengthTick: json['lengthTick'] ?? 0,
      gain: (json['gain'] ?? 1.0).toDouble(),
      fadeInLength: (json['fadeInLength'] ?? 0.0).toDouble(),
      fadeOutLength: (json['fadeOutLength'] ?? 0.0).toDouble(),
      muted: json['muted'] ?? false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _containers.clear();
    _selectedVersionIds.clear();
    _undoHistory.clear();
    _redoHistory.clear();
    _enabled = true;
    _showVersionLane = false;
    _versionCounter = 1;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
