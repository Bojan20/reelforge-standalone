/// Region Playlist Service — Non-linear Playback
///
/// #26: Define region playback order independently of timeline position.
///
/// Features:
/// - Named playlists with ordered region entries
/// - Each entry references a timeline region by start/end time
/// - Per-entry loop count (0 = no loop, -1 = infinite)
/// - Smooth seek between entries
/// - Play/pause/stop/skip controls
/// - JSON serialization for persistence
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYLIST ENTRY
// ═══════════════════════════════════════════════════════════════════════════════

/// A single entry in a region playlist
class PlaylistEntry {
  final String id;
  String label;

  /// Timeline region bounds (in seconds)
  double startTime;
  double endTime;

  /// Number of times to loop this entry (0 = play once, -1 = infinite)
  int loopCount;

  /// Fade in/out for smooth transitions (milliseconds)
  int fadeInMs;
  int fadeOutMs;

  /// Per-entry gain (1.0 = unity)
  double gain;

  PlaylistEntry({
    required this.id,
    required this.label,
    required this.startTime,
    required this.endTime,
    this.loopCount = 0,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.gain = 1.0,
  });

  double get duration => endTime - startTime;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'startTime': startTime,
    'endTime': endTime,
    'loopCount': loopCount,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'gain': gain,
  };

  factory PlaylistEntry.fromJson(Map<String, dynamic> json) => PlaylistEntry(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    startTime: (json['startTime'] as num?)?.toDouble() ?? 0,
    endTime: (json['endTime'] as num?)?.toDouble() ?? 0,
    loopCount: json['loopCount'] as int? ?? 0,
    fadeInMs: json['fadeInMs'] as int? ?? 0,
    fadeOutMs: json['fadeOutMs'] as int? ?? 0,
    gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// REGION PLAYLIST
// ═══════════════════════════════════════════════════════════════════════════════

/// Playback state
enum PlaylistState { stopped, playing, paused }

/// A named playlist of ordered region entries
class RegionPlaylist {
  final String id;
  String name;
  String? description;
  final List<PlaylistEntry> entries;
  int _currentIndex;
  int _currentLoop;

  RegionPlaylist({
    required this.id,
    required this.name,
    this.description,
    required this.entries,
    int currentIndex = 0,
  }) : _currentIndex = currentIndex, _currentLoop = 0;

  int get currentIndex => _currentIndex;
  int get entryCount => entries.length;
  bool get isEmpty => entries.isEmpty;

  PlaylistEntry? get currentEntry =>
      entries.isEmpty ? null : entries[_currentIndex.clamp(0, entries.length - 1)];

  /// Total playlist duration (all entries, accounting for loops)
  double get totalDuration {
    double total = 0;
    for (final e in entries) {
      final plays = e.loopCount < 0 ? 1 : e.loopCount + 1;
      total += e.duration * plays;
    }
    return total;
  }

  /// Advance to next entry. Returns null if playlist is finished.
  PlaylistEntry? advance() {
    if (entries.isEmpty) return null;
    final entry = currentEntry!;

    // Check if we need to loop current entry
    if (entry.loopCount < 0) {
      // Infinite loop — stay on current
      _currentLoop++;
      return entry;
    }

    if (_currentLoop < entry.loopCount) {
      // More loops remaining
      _currentLoop++;
      return entry;
    }

    // Move to next entry
    _currentLoop = 0;
    _currentIndex++;
    if (_currentIndex >= entries.length) {
      _currentIndex = 0;
      return null; // Playlist finished
    }
    return entries[_currentIndex];
  }

  /// Skip to specific entry index
  void skipTo(int index) {
    if (index >= 0 && index < entries.length) {
      _currentIndex = index;
      _currentLoop = 0;
    }
  }

  /// Reset to first entry
  void reset() {
    _currentIndex = 0;
    _currentLoop = 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'entries': entries.map((e) => e.toJson()).toList(),
    'currentIndex': _currentIndex,
  };

  factory RegionPlaylist.fromJson(Map<String, dynamic> json) => RegionPlaylist(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    entries: (json['entries'] as List<dynamic>?)
        ?.map((e) => PlaylistEntry.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    currentIndex: json['currentIndex'] as int? ?? 0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// REGION PLAYLIST SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for managing and playing region playlists
class RegionPlaylistService extends ChangeNotifier {
  RegionPlaylistService._();
  static final RegionPlaylistService instance = RegionPlaylistService._();

  final Map<String, RegionPlaylist> _playlists = {};
  PlaylistState _state = PlaylistState.stopped;
  String? _activePlaylistId;

  /// Callback for seeking timeline to a position
  void Function(double time)? onSeek;

  /// Callback for starting/stopping timeline playback
  void Function(bool play)? onPlaybackControl;

  // Getters
  List<RegionPlaylist> get playlists => _playlists.values.toList();
  int get count => _playlists.length;
  PlaylistState get state => _state;
  String? get activePlaylistId => _activePlaylistId;

  RegionPlaylist? getPlaylist(String id) => _playlists[id];
  RegionPlaylist? get activePlaylist =>
      _activePlaylistId != null ? _playlists[_activePlaylistId!] : null;

  /// Add a new playlist
  void addPlaylist(RegionPlaylist playlist) {
    _playlists[playlist.id] = playlist;
    notifyListeners();
  }

  /// Remove a playlist
  void removePlaylist(String id) {
    if (_activePlaylistId == id) stop();
    _playlists.remove(id);
    notifyListeners();
  }

  /// Rename a playlist
  void renamePlaylist(String id, String newName) {
    final pl = _playlists[id];
    if (pl == null) return;
    pl.name = newName;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENTRY MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add an entry to a playlist
  void addEntry(String playlistId, PlaylistEntry entry) {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    pl.entries.add(entry);
    notifyListeners();
  }

  /// Remove an entry from a playlist
  void removeEntry(String playlistId, String entryId) {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    pl.entries.removeWhere((e) => e.id == entryId);
    if (pl.currentIndex >= pl.entries.length) {
      pl.reset();
    }
    notifyListeners();
  }

  /// Move entry up
  void moveEntryUp(String playlistId, int index) {
    final pl = _playlists[playlistId];
    if (pl == null || index <= 0 || index >= pl.entries.length) return;
    final entry = pl.entries.removeAt(index);
    pl.entries.insert(index - 1, entry);
    notifyListeners();
  }

  /// Move entry down
  void moveEntryDown(String playlistId, int index) {
    final pl = _playlists[playlistId];
    if (pl == null || index < 0 || index >= pl.entries.length - 1) return;
    final entry = pl.entries.removeAt(index);
    pl.entries.insert(index + 1, entry);
    notifyListeners();
  }

  /// Update entry properties
  void updateEntry(String playlistId, String entryId, {
    String? label,
    double? startTime,
    double? endTime,
    int? loopCount,
    int? fadeInMs,
    int? fadeOutMs,
    double? gain,
  }) {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    final entry = pl.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) return;

    if (label != null) entry.label = label;
    if (startTime != null) entry.startTime = startTime;
    if (endTime != null) entry.endTime = endTime;
    if (loopCount != null) entry.loopCount = loopCount;
    if (fadeInMs != null) entry.fadeInMs = fadeInMs;
    if (fadeOutMs != null) entry.fadeOutMs = fadeOutMs;
    if (gain != null) entry.gain = gain;

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start playing a playlist from current position
  void play(String playlistId) {
    final pl = _playlists[playlistId];
    if (pl == null || pl.isEmpty) return;

    _activePlaylistId = playlistId;
    _state = PlaylistState.playing;

    // Seek to current entry's start
    final entry = pl.currentEntry;
    if (entry != null) {
      onSeek?.call(entry.startTime);
      onPlaybackControl?.call(true);
    }
    notifyListeners();
  }

  /// Pause playback
  void pause() {
    if (_state != PlaylistState.playing) return;
    _state = PlaylistState.paused;
    onPlaybackControl?.call(false);
    notifyListeners();
  }

  /// Resume playback
  void resume() {
    if (_state != PlaylistState.paused) return;
    _state = PlaylistState.playing;
    onPlaybackControl?.call(true);
    notifyListeners();
  }

  /// Stop playback and reset
  void stop() {
    _state = PlaylistState.stopped;
    final pl = activePlaylist;
    pl?.reset();
    _activePlaylistId = null;
    onPlaybackControl?.call(false);
    notifyListeners();
  }

  /// Skip to next entry
  void skipNext() {
    final pl = activePlaylist;
    if (pl == null) return;

    final next = pl.advance();
    if (next == null) {
      stop();
      return;
    }
    onSeek?.call(next.startTime);
    notifyListeners();
  }

  /// Skip to previous entry
  void skipPrevious() {
    final pl = activePlaylist;
    if (pl == null) return;

    final newIndex = (pl.currentIndex - 1).clamp(0, pl.entryCount - 1);
    pl.skipTo(newIndex);
    final entry = pl.currentEntry;
    if (entry != null) {
      onSeek?.call(entry.startTime);
    }
    notifyListeners();
  }

  /// Skip to specific entry
  void skipToEntry(String playlistId, int index) {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    pl.skipTo(index);
    if (_state == PlaylistState.playing) {
      final entry = pl.currentEntry;
      if (entry != null) {
        onSeek?.call(entry.startTime);
      }
    }
    notifyListeners();
  }

  /// Called by timeline when playhead reaches end of current entry
  void onEntryComplete() {
    if (_state != PlaylistState.playing) return;
    skipNext();
  }

  /// Duplicate a playlist
  void duplicatePlaylist(String id) {
    final pl = _playlists[id];
    if (pl == null) return;

    final newId = 'playlist_${DateTime.now().millisecondsSinceEpoch}';
    final json = pl.toJson();
    json['id'] = newId;
    json['name'] = '${pl.name} (Copy)';
    json['currentIndex'] = 0;

    _playlists[newId] = RegionPlaylist.fromJson(json);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'playlists': _playlists.values.map((p) => p.toJson()).toList(),
  };

  void fromJson(Map<String, dynamic> json) {
    _playlists.clear();
    _state = PlaylistState.stopped;
    _activePlaylistId = null;
    final list = json['playlists'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final pl = RegionPlaylist.fromJson(item as Map<String, dynamic>);
        _playlists[pl.id] = pl;
      }
    }
    notifyListeners();
  }
}
