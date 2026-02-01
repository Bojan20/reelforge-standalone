/// Stem Routing Provider (P10.1.2)
///
/// Manages stem routing for batch export:
/// - Track → Stem assignments (many-to-many)
/// - Stem definitions (7 built-in + custom)
/// - Auto-detect drum/bass/melody/vocal tracks
/// - Export integration
///
/// Created: 2026-02-02

import 'package:flutter/material.dart';

// =============================================================================
// STEM TYPE
// =============================================================================

/// Stem type definitions for batch export workflow.
enum StemType {
  drums('Drums', Color(0xFFFF5252), 'Drum and percussion tracks'),
  bass('Bass', Color(0xFF448AFF), 'Bass guitar, synth bass tracks'),
  melody('Melody', Color(0xFF69F0AE), 'Lead instruments, synths, guitars'),
  vocals('Vocals', Color(0xFFE040FB), 'Vocals, voice-overs, dialogue'),
  fx('FX', Color(0xFF00E5FF), 'Sound effects, foley, impacts'),
  ambience('Ambience', Color(0xFFFFD740), 'Pads, atmos, ambient layers'),
  master('Master', Color(0xFFFFFFFF), 'Full mix output'),
  custom('Custom', Color(0xFF9E9E9E), 'User-defined stem');

  final String label;
  final Color color;
  final String description;
  const StemType(this.label, this.color, this.description);

  /// Short 3-letter code for compact display.
  String get code => switch (this) {
        StemType.drums => 'DRM',
        StemType.bass => 'BAS',
        StemType.melody => 'MEL',
        StemType.vocals => 'VOX',
        StemType.fx => 'FX',
        StemType.ambience => 'AMB',
        StemType.master => 'MST',
        StemType.custom => 'CST',
      };

  /// Icon for this stem type.
  IconData get icon => switch (this) {
        StemType.drums => Icons.circle,
        StemType.bass => Icons.graphic_eq,
        StemType.melody => Icons.music_note,
        StemType.vocals => Icons.mic,
        StemType.fx => Icons.auto_awesome,
        StemType.ambience => Icons.cloud,
        StemType.master => Icons.speaker,
        StemType.custom => Icons.tune,
      };
}

// =============================================================================
// STEM ROUTING MODEL
// =============================================================================

/// Routing assignment for a single track.
class StemRouting {
  final String trackId;
  final String trackName;
  final bool isTrack; // true = audio track, false = bus
  final Set<StemType> stems;

  const StemRouting({
    required this.trackId,
    required this.trackName,
    required this.isTrack,
    this.stems = const {},
  });

  StemRouting copyWith({Set<StemType>? stems}) => StemRouting(
        trackId: trackId,
        trackName: trackName,
        isTrack: isTrack,
        stems: stems ?? this.stems,
      );

  /// Check if routed to specific stem.
  bool isRoutedTo(StemType stem) => stems.contains(stem);

  /// Toggle routing to a stem.
  StemRouting toggle(StemType stem) {
    final newStems = Set<StemType>.from(stems);
    if (newStems.contains(stem)) {
      newStems.remove(stem);
    } else {
      newStems.add(stem);
    }
    return copyWith(stems: newStems);
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'trackName': trackName,
        'isTrack': isTrack,
        'stems': stems.map((s) => s.name).toList(),
      };

  factory StemRouting.fromJson(Map<String, dynamic> json) => StemRouting(
        trackId: json['trackId'] as String,
        trackName: json['trackName'] as String,
        isTrack: json['isTrack'] as bool? ?? true,
        stems: (json['stems'] as List<dynamic>?)
                ?.map((s) => StemType.values.firstWhere(
                      (t) => t.name == s,
                      orElse: () => StemType.custom,
                    ))
                .toSet() ??
            {},
      );
}

// =============================================================================
// STEM ROUTING PROVIDER
// =============================================================================

/// Provider for stem routing configuration.
///
/// Manages track-to-stem assignments for batch export workflow.
class StemRoutingProvider extends ChangeNotifier {
  /// Track/bus → stem routing.
  final Map<String, StemRouting> _routing = {};

  /// Custom stems (beyond built-in 7).
  final List<String> _customStems = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// All routing entries.
  List<StemRouting> get allRouting => _routing.values.toList();

  /// Get routing for a specific track.
  StemRouting? getRouting(String trackId) => _routing[trackId];

  /// Get stems assigned to a track.
  Set<StemType> getStems(String trackId) => _routing[trackId]?.stems ?? {};

  /// Check if track is routed to stem.
  bool isRoutedTo(String trackId, StemType stem) =>
      _routing[trackId]?.isRoutedTo(stem) ?? false;

  /// Get all tracks routed to a specific stem.
  List<String> getTracksForStem(StemType stem) => _routing.entries
      .where((e) => e.value.stems.contains(stem))
      .map((e) => e.key)
      .toList();

  /// Get track count for a stem (for UI badges).
  int getTrackCountForStem(StemType stem) => getTracksForStem(stem).length;

  /// Get all available stems (built-in + custom).
  List<StemType> get availableStems =>
      StemType.values.where((s) => s != StemType.custom).toList();

  /// Check if any routing exists.
  bool get hasRouting => _routing.values.any((r) => r.stems.isNotEmpty);

  /// Total tracks registered.
  int get trackCount => _routing.length;

  /// Total active routing connections.
  int get connectionCount =>
      _routing.values.fold(0, (sum, r) => sum + r.stems.length);

  // ═══════════════════════════════════════════════════════════════════════════
  // REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a track for stem routing.
  void registerTrack(String trackId, String trackName, {bool isTrack = true}) {
    if (!_routing.containsKey(trackId)) {
      _routing[trackId] = StemRouting(
        trackId: trackId,
        trackName: trackName,
        isTrack: isTrack,
      );
      notifyListeners();
    }
  }

  /// Register multiple tracks.
  void registerTracks(List<({String id, String name, bool isTrack})> tracks) {
    for (final t in tracks) {
      _routing[t.id] = StemRouting(
        trackId: t.id,
        trackName: t.name,
        isTrack: t.isTrack,
      );
    }
    notifyListeners();
  }

  /// Unregister a track.
  void unregisterTrack(String trackId) {
    if (_routing.remove(trackId) != null) {
      notifyListeners();
    }
  }

  /// Clear all registrations.
  void clearAll() {
    _routing.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTING OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle stem routing for a track.
  void toggleStemRouting(String trackId, StemType stem) {
    final current = _routing[trackId];
    if (current != null) {
      _routing[trackId] = current.toggle(stem);
      notifyListeners();
    }
  }

  /// Set stem routing for a track (replaces existing).
  void setStemRouting(String trackId, Set<StemType> stems) {
    final current = _routing[trackId];
    if (current != null) {
      _routing[trackId] = current.copyWith(stems: stems);
      notifyListeners();
    }
  }

  /// Add a stem to a track's routing.
  void addStemToTrack(String trackId, StemType stem) {
    final current = _routing[trackId];
    if (current != null && !current.stems.contains(stem)) {
      final newStems = Set<StemType>.from(current.stems)..add(stem);
      _routing[trackId] = current.copyWith(stems: newStems);
      notifyListeners();
    }
  }

  /// Remove a stem from a track's routing.
  void removeStemFromTrack(String trackId, StemType stem) {
    final current = _routing[trackId];
    if (current != null && current.stems.contains(stem)) {
      final newStems = Set<StemType>.from(current.stems)..remove(stem);
      _routing[trackId] = current.copyWith(stems: newStems);
      notifyListeners();
    }
  }

  /// Clear all routing for a track.
  void clearTrackRouting(String trackId) {
    final current = _routing[trackId];
    if (current != null && current.stems.isNotEmpty) {
      _routing[trackId] = current.copyWith(stems: {});
      notifyListeners();
    }
  }

  /// Clear all routing for a stem.
  void clearStemRouting(StemType stem) {
    bool changed = false;
    for (final trackId in _routing.keys.toList()) {
      final current = _routing[trackId]!;
      if (current.stems.contains(stem)) {
        final newStems = Set<StemType>.from(current.stems)..remove(stem);
        _routing[trackId] = current.copyWith(stems: newStems);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select all tracks for a stem based on name patterns.
  void autoSelectDrums() {
    _autoSelectByPattern(StemType.drums, [
      'drum',
      'kick',
      'snare',
      'hihat',
      'hi-hat',
      'cymbal',
      'tom',
      'perc',
      'percussion',
    ]);
  }

  /// Auto-select bass tracks.
  void autoSelectBass() {
    _autoSelectByPattern(StemType.bass, [
      'bass',
      'sub',
      '808',
    ]);
  }

  /// Auto-select melody tracks.
  void autoSelectMelody() {
    _autoSelectByPattern(StemType.melody, [
      'lead',
      'synth',
      'guitar',
      'piano',
      'keys',
      'melody',
      'riff',
      'arp',
    ]);
  }

  /// Auto-select vocal tracks.
  void autoSelectVocals() {
    _autoSelectByPattern(StemType.vocals, [
      'vocal',
      'vox',
      'voice',
      'vo',
      'dialog',
      'dialogue',
      'speak',
      'sing',
    ]);
  }

  /// Auto-select FX tracks.
  void autoSelectFx() {
    _autoSelectByPattern(StemType.fx, [
      'fx',
      'sfx',
      'effect',
      'impact',
      'riser',
      'sweep',
      'woosh',
      'hit',
    ]);
  }

  /// Auto-select ambience tracks.
  void autoSelectAmbience() {
    _autoSelectByPattern(StemType.ambience, [
      'pad',
      'atmos',
      'ambient',
      'ambience',
      'texture',
      'drone',
      'bg',
      'background',
    ]);
  }

  /// Select all tracks to master.
  void selectAllToMaster() {
    for (final trackId in _routing.keys) {
      addStemToTrack(trackId, StemType.master);
    }
  }

  /// Clear all routing.
  void clearAllRouting() {
    bool changed = false;
    for (final trackId in _routing.keys.toList()) {
      final current = _routing[trackId]!;
      if (current.stems.isNotEmpty) {
        _routing[trackId] = current.copyWith(stems: {});
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Auto-detect all tracks based on name patterns.
  void autoDetectAll() {
    autoSelectDrums();
    autoSelectBass();
    autoSelectMelody();
    autoSelectVocals();
    autoSelectFx();
    autoSelectAmbience();
  }

  void _autoSelectByPattern(StemType stem, List<String> patterns) {
    for (final entry in _routing.entries) {
      final name = entry.value.trackName.toLowerCase();
      for (final pattern in patterns) {
        if (name.contains(pattern)) {
          addStemToTrack(entry.key, stem);
          break;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export routing configuration as JSON.
  Map<String, dynamic> toJson() => {
        'routing': _routing.values.map((r) => r.toJson()).toList(),
        'customStems': _customStems,
      };

  /// Import routing configuration from JSON.
  void fromJson(Map<String, dynamic> json) {
    _routing.clear();
    _customStems.clear();

    final routingList = json['routing'] as List<dynamic>?;
    if (routingList != null) {
      for (final r in routingList) {
        final routing = StemRouting.fromJson(r as Map<String, dynamic>);
        _routing[routing.trackId] = routing;
      }
    }

    final customs = json['customStems'] as List<dynamic>?;
    if (customs != null) {
      _customStems.addAll(customs.cast<String>());
    }

    notifyListeners();
  }

  /// Get export-ready stem configuration.
  Map<StemType, List<String>> getExportConfiguration() {
    final config = <StemType, List<String>>{};
    for (final stem in StemType.values) {
      final tracks = getTracksForStem(stem);
      if (tracks.isNotEmpty) {
        config[stem] = tracks;
      }
    }
    return config;
  }
}
