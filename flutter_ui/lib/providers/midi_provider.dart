// MIDI Provider
//
// MIDI recording and editing state management:
// - MIDI clip management (create, delete, edit)
// - Recording state (arm, punch in/out, count-in)
// - Input device selection (MIDI controllers)
// - Quantization settings (pre/post record)
// - Note editing operations (transpose, velocity scale)
// - Clipboard operations (copy, paste, duplicate)
//
// Integration with rf-core/track.rs and piano_roll FFI

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// MIDI clip on timeline
class MidiClip {
  final String id;
  final String trackId;
  final String name;
  final double startTime; // seconds
  final double duration; // seconds
  final Color color;
  final List<MidiNoteData> notes;
  final bool muted;
  final bool locked;
  final bool selected;
  final int loopCount; // 0 = no loop, >0 = loop iterations
  final double loopLength; // in seconds, if looping

  const MidiClip({
    required this.id,
    required this.trackId,
    required this.name,
    required this.startTime,
    required this.duration,
    this.color = const Color(0xFF9B59B6), // Purple for MIDI
    this.notes = const [],
    this.muted = false,
    this.locked = false,
    this.selected = false,
    this.loopCount = 0,
    this.loopLength = 0,
  });

  double get endTime => startTime + duration;
  int get noteCount => notes.length;
  bool get isEmpty => notes.isEmpty;
  bool get isLooped => loopCount > 0;

  /// Get notes within time range
  List<MidiNoteData> notesInRange(double start, double end) {
    return notes.where((n) => n.startTime < end && n.endTime > start).toList();
  }

  /// Get lowest and highest pitch in clip
  (int, int) get pitchRange {
    if (notes.isEmpty) return (60, 72); // Default C4-C5
    int low = 127, high = 0;
    for (final note in notes) {
      if (note.pitch < low) low = note.pitch;
      if (note.pitch > high) high = note.pitch;
    }
    return (low, high);
  }

  MidiClip copyWith({
    String? id,
    String? trackId,
    String? name,
    double? startTime,
    double? duration,
    Color? color,
    List<MidiNoteData>? notes,
    bool? muted,
    bool? locked,
    bool? selected,
    int? loopCount,
    double? loopLength,
  }) {
    return MidiClip(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      color: color ?? this.color,
      notes: notes ?? this.notes,
      muted: muted ?? this.muted,
      locked: locked ?? this.locked,
      selected: selected ?? this.selected,
      loopCount: loopCount ?? this.loopCount,
      loopLength: loopLength ?? this.loopLength,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'name': name,
        'startTime': startTime,
        'duration': duration,
        'color': color.value,
        'notes': notes.map((n) => n.toJson()).toList(),
        'muted': muted,
        'locked': locked,
        'loopCount': loopCount,
        'loopLength': loopLength,
      };

  factory MidiClip.fromJson(Map<String, dynamic> json) => MidiClip(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        startTime: (json['startTime'] as num).toDouble(),
        duration: (json['duration'] as num).toDouble(),
        color: Color(json['color'] as int),
        notes: (json['notes'] as List?)
                ?.map((n) => MidiNoteData.fromJson(n as Map<String, dynamic>))
                .toList() ??
            [],
        muted: json['muted'] as bool? ?? false,
        locked: json['locked'] as bool? ?? false,
        loopCount: json['loopCount'] as int? ?? 0,
        loopLength: (json['loopLength'] as num?)?.toDouble() ?? 0,
      );
}

/// MIDI note data
class MidiNoteData {
  final String id;
  final int pitch; // 0-127
  final double startTime; // seconds relative to clip start
  final double duration; // seconds
  final double velocity; // 0.0-1.0
  final int channel; // 0-15
  final bool muted;

  const MidiNoteData({
    required this.id,
    required this.pitch,
    required this.startTime,
    required this.duration,
    this.velocity = 0.8,
    this.channel = 0,
    this.muted = false,
  });

  double get endTime => startTime + duration;

  /// Get note name (e.g., "C4", "F#5")
  String get noteName {
    const noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B'
    ];
    final octave = (pitch ~/ 12) - 1;
    final note = noteNames[pitch % 12];
    return '$note$octave';
  }

  /// Velocity as MIDI value (0-127)
  int get velocityMidi => (velocity * 127).round().clamp(0, 127);

  MidiNoteData copyWith({
    String? id,
    int? pitch,
    double? startTime,
    double? duration,
    double? velocity,
    int? channel,
    bool? muted,
  }) {
    return MidiNoteData(
      id: id ?? this.id,
      pitch: pitch ?? this.pitch,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      velocity: velocity ?? this.velocity,
      channel: channel ?? this.channel,
      muted: muted ?? this.muted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pitch': pitch,
        'startTime': startTime,
        'duration': duration,
        'velocity': velocity,
        'channel': channel,
        'muted': muted,
      };

  factory MidiNoteData.fromJson(Map<String, dynamic> json) => MidiNoteData(
        id: json['id'] as String,
        pitch: json['pitch'] as int,
        startTime: (json['startTime'] as num).toDouble(),
        duration: (json['duration'] as num).toDouble(),
        velocity: (json['velocity'] as num?)?.toDouble() ?? 0.8,
        channel: json['channel'] as int? ?? 0,
        muted: json['muted'] as bool? ?? false,
      );
}

/// MIDI input device
class MidiInputDevice {
  final String id;
  final String name;
  final bool isConnected;
  final bool isEnabled;

  const MidiInputDevice({
    required this.id,
    required this.name,
    this.isConnected = true,
    this.isEnabled = true,
  });
}

/// Quantization value
enum QuantizeValue {
  off,
  bar,
  half,
  quarter,
  eighth,
  sixteenth,
  thirtySecond,
  eighthTriplet,
  sixteenthTriplet,
}

extension QuantizeValueExt on QuantizeValue {
  String get label {
    switch (this) {
      case QuantizeValue.off:
        return 'Off';
      case QuantizeValue.bar:
        return '1 Bar';
      case QuantizeValue.half:
        return '1/2';
      case QuantizeValue.quarter:
        return '1/4';
      case QuantizeValue.eighth:
        return '1/8';
      case QuantizeValue.sixteenth:
        return '1/16';
      case QuantizeValue.thirtySecond:
        return '1/32';
      case QuantizeValue.eighthTriplet:
        return '1/8T';
      case QuantizeValue.sixteenthTriplet:
        return '1/16T';
    }
  }

  /// Ticks at 960 PPQN
  int get ticks {
    switch (this) {
      case QuantizeValue.off:
        return 1;
      case QuantizeValue.bar:
        return 960 * 4;
      case QuantizeValue.half:
        return 960 * 2;
      case QuantizeValue.quarter:
        return 960;
      case QuantizeValue.eighth:
        return 480;
      case QuantizeValue.sixteenth:
        return 240;
      case QuantizeValue.thirtySecond:
        return 120;
      case QuantizeValue.eighthTriplet:
        return 320;
      case QuantizeValue.sixteenthTriplet:
        return 160;
    }
  }
}

/// Recording mode
enum MidiRecordMode {
  replace, // Replace existing notes
  merge, // Merge with existing notes
  overdub, // Overdub on top
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class MidiProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // Per-track clip states
  final Map<String, List<MidiClip>> _clipsByTrack = {};

  // Global settings
  bool _midiThru = true; // Pass-through input to output
  bool _recordEnabled = false;
  bool _countInEnabled = true;
  int _countInBars = 1;
  QuantizeValue _inputQuantize = QuantizeValue.off;
  QuantizeValue _recordQuantize = QuantizeValue.sixteenth;
  MidiRecordMode _recordMode = MidiRecordMode.merge;
  double _defaultVelocity = 0.8;
  double _defaultNoteDuration = 0.25; // quarter note at 120bpm
  int _defaultChannel = 0;

  // Recording state
  String? _recordingTrackId;
  String? _recordingClipId;
  double? _recordingStartTime;
  final List<MidiNoteData> _recordingNotes = [];
  final Set<int> _heldNotes = {}; // Currently held note pitches

  // Selection state
  String? _selectedClipId;
  final Set<String> _selectedNoteIds = {};
  MidiClip? _editingClip; // Clip currently open in piano roll

  // Clipboard
  List<MidiNoteData>? _clipboard;
  double? _clipboardStartTime;

  // Input devices
  final List<MidiInputDevice> _inputDevices = [];
  String? _activeInputDeviceId;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get midiThru => _midiThru;
  bool get recordEnabled => _recordEnabled;
  bool get countInEnabled => _countInEnabled;
  int get countInBars => _countInBars;
  QuantizeValue get inputQuantize => _inputQuantize;
  QuantizeValue get recordQuantize => _recordQuantize;
  MidiRecordMode get recordMode => _recordMode;
  double get defaultVelocity => _defaultVelocity;
  double get defaultNoteDuration => _defaultNoteDuration;
  int get defaultChannel => _defaultChannel;

  bool get isRecording => _recordingTrackId != null;
  String? get recordingTrackId => _recordingTrackId;
  String? get recordingClipId => _recordingClipId;

  String? get selectedClipId => _selectedClipId;
  Set<String> get selectedNoteIds => Set.unmodifiable(_selectedNoteIds);
  MidiClip? get editingClip => _editingClip;
  bool get hasSelection => _selectedNoteIds.isNotEmpty;

  List<MidiInputDevice> get inputDevices => List.unmodifiable(_inputDevices);
  String? get activeInputDeviceId => _activeInputDeviceId;
  MidiInputDevice? get activeInputDevice => _inputDevices
      .cast<MidiInputDevice?>()
      .firstWhere((d) => d?.id == _activeInputDeviceId, orElse: () => null);

  bool get hasClipboard => _clipboard != null && _clipboard!.isNotEmpty;

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all clips for a track
  List<MidiClip> getClipsForTrack(String trackId) {
    return _clipsByTrack[trackId] ?? [];
  }

  /// Get clip by ID
  MidiClip? getClip(String clipId) {
    for (final clips in _clipsByTrack.values) {
      final clip = clips.cast<MidiClip?>().firstWhere(
            (c) => c?.id == clipId,
            orElse: () => null,
          );
      if (clip != null) return clip;
    }
    return null;
  }

  /// Get clips at a specific time
  List<MidiClip> getClipsAt(String trackId, double time) {
    return getClipsForTrack(trackId)
        .where((c) => c.startTime <= time && c.endTime > time)
        .toList();
  }

  /// Create new MIDI clip
  MidiClip createClip({
    required String trackId,
    required double startTime,
    double duration = 4.0, // 4 seconds default
    String? name,
    Color? color,
    List<MidiNoteData>? notes,
  }) {
    final clip = MidiClip(
      id: _generateId(),
      trackId: trackId,
      name: name ?? 'MIDI ${(_clipsByTrack[trackId]?.length ?? 0) + 1}',
      startTime: startTime,
      duration: duration,
      color: color ?? const Color(0xFF9B59B6),
      notes: notes ?? [],
    );

    _clipsByTrack.putIfAbsent(trackId, () => []).add(clip);
    notifyListeners();
    return clip;
  }

  /// Delete clip
  void deleteClip(String clipId) {
    for (final clips in _clipsByTrack.values) {
      clips.removeWhere((c) => c.id == clipId);
    }
    if (_selectedClipId == clipId) {
      _selectedClipId = null;
    }
    if (_editingClip?.id == clipId) {
      _editingClip = null;
    }
    notifyListeners();
  }

  /// Update clip
  void updateClip(String clipId, MidiClip Function(MidiClip) update) {
    for (final entry in _clipsByTrack.entries) {
      final idx = entry.value.indexWhere((c) => c.id == clipId);
      if (idx >= 0) {
        entry.value[idx] = update(entry.value[idx]);
        if (_editingClip?.id == clipId) {
          _editingClip = entry.value[idx];
        }
        notifyListeners();
        return;
      }
    }
  }

  /// Move clip to new position
  void moveClip(String clipId, double newStartTime, {String? newTrackId}) {
    final clip = getClip(clipId);
    if (clip == null) return;

    if (newTrackId != null && newTrackId != clip.trackId) {
      // Move to different track
      _clipsByTrack[clip.trackId]?.removeWhere((c) => c.id == clipId);
      final movedClip = clip.copyWith(
        trackId: newTrackId,
        startTime: newStartTime,
      );
      _clipsByTrack.putIfAbsent(newTrackId, () => []).add(movedClip);
    } else {
      // Same track, just update position
      updateClip(clipId, (c) => c.copyWith(startTime: newStartTime));
    }
    notifyListeners();
  }

  /// Duplicate clip
  MidiClip duplicateClip(String clipId, {double? atTime}) {
    final source = getClip(clipId);
    if (source == null) throw StateError('Clip not found: $clipId');

    return createClip(
      trackId: source.trackId,
      startTime: atTime ?? source.endTime,
      duration: source.duration,
      name: '${source.name} (copy)',
      color: source.color,
      notes: source.notes.map((n) => n.copyWith(id: _generateId())).toList(),
    );
  }

  /// Split clip at time
  (MidiClip, MidiClip) splitClip(String clipId, double atTime) {
    final clip = getClip(clipId);
    if (clip == null) throw StateError('Clip not found: $clipId');
    if (atTime <= clip.startTime || atTime >= clip.endTime) {
      throw StateError('Split time must be within clip bounds');
    }

    final splitPoint = atTime - clip.startTime;
    final notesLeft =
        clip.notes.where((n) => n.startTime < splitPoint).map((n) {
      if (n.endTime > splitPoint) {
        return n.copyWith(duration: splitPoint - n.startTime);
      }
      return n;
    }).toList();

    final notesRight =
        clip.notes.where((n) => n.endTime > splitPoint).map((n) {
      final newStart = (n.startTime - splitPoint).clamp(0.0, double.infinity);
      if (n.startTime < splitPoint) {
        return n.copyWith(
          id: _generateId(),
          startTime: 0,
          duration: n.endTime - splitPoint,
        );
      }
      return n.copyWith(
        id: _generateId(),
        startTime: newStart,
      );
    }).toList();

    // Update original clip (left part)
    updateClip(clipId, (c) => c.copyWith(
          duration: splitPoint,
          notes: notesLeft,
        ));

    // Create new clip (right part)
    final rightClip = createClip(
      trackId: clip.trackId,
      startTime: atTime,
      duration: clip.duration - splitPoint,
      name: '${clip.name} (R)',
      color: clip.color,
      notes: notesRight,
    );

    return (getClip(clipId)!, rightClip);
  }

  /// Merge adjacent clips
  MidiClip? mergeClips(List<String> clipIds) {
    if (clipIds.length < 2) return null;

    final clips =
        clipIds.map((id) => getClip(id)).whereType<MidiClip>().toList();
    if (clips.length < 2) return null;

    // Verify all clips are on same track
    final trackId = clips.first.trackId;
    if (!clips.every((c) => c.trackId == trackId)) {
      throw StateError('Cannot merge clips from different tracks');
    }

    // Sort by start time
    clips.sort((a, b) => a.startTime.compareTo(b.startTime));

    final mergedStart = clips.first.startTime;
    final mergedEnd = clips.last.endTime;
    final mergedNotes = <MidiNoteData>[];

    for (final clip in clips) {
      final offset = clip.startTime - mergedStart;
      for (final note in clip.notes) {
        mergedNotes.add(note.copyWith(
          id: _generateId(),
          startTime: note.startTime + offset,
        ));
      }
    }

    // Delete original clips
    for (final id in clipIds) {
      deleteClip(id);
    }

    // Create merged clip
    return createClip(
      trackId: trackId,
      startTime: mergedStart,
      duration: mergedEnd - mergedStart,
      name: clips.first.name,
      color: clips.first.color,
      notes: mergedNotes,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NOTE EDITING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add note to clip
  MidiNoteData addNote({
    required String clipId,
    required int pitch,
    required double startTime,
    double? duration,
    double? velocity,
    int? channel,
  }) {
    final note = MidiNoteData(
      id: _generateId(),
      pitch: pitch.clamp(0, 127),
      startTime: startTime,
      duration: duration ?? _defaultNoteDuration,
      velocity: velocity ?? _defaultVelocity,
      channel: channel ?? _defaultChannel,
    );

    updateClip(clipId, (clip) {
      final notes = List<MidiNoteData>.from(clip.notes)..add(note);
      // Auto-extend clip if note extends beyond
      final newDuration =
          clip.duration < note.endTime ? note.endTime + 0.1 : clip.duration;
      return clip.copyWith(notes: notes, duration: newDuration);
    });

    // Sync to FFI if clip has piano roll
    _syncNoteToFFI(clipId, note);

    return note;
  }

  /// Delete notes from clip
  void deleteNotes(String clipId, Set<String> noteIds) {
    updateClip(clipId, (clip) {
      final notes = clip.notes.where((n) => !noteIds.contains(n.id)).toList();
      return clip.copyWith(notes: notes);
    });
    _selectedNoteIds.removeAll(noteIds);
    notifyListeners();
  }

  /// Update note properties
  void updateNote(String clipId, String noteId,
      {int? pitch,
      double? startTime,
      double? duration,
      double? velocity,
      bool? muted}) {
    updateClip(clipId, (clip) {
      final notes = clip.notes.map((n) {
        if (n.id == noteId) {
          return n.copyWith(
            pitch: pitch?.clamp(0, 127),
            startTime: startTime,
            duration: duration,
            velocity: velocity?.clamp(0.0, 1.0),
            muted: muted,
          );
        }
        return n;
      }).toList();
      return clip.copyWith(notes: notes);
    });
  }

  /// Transpose selected notes
  void transposeNotes(String clipId, Set<String> noteIds, int semitones) {
    updateClip(clipId, (clip) {
      final notes = clip.notes.map((n) {
        if (noteIds.contains(n.id)) {
          return n.copyWith(pitch: (n.pitch + semitones).clamp(0, 127));
        }
        return n;
      }).toList();
      return clip.copyWith(notes: notes);
    });
  }

  /// Scale velocities
  void scaleVelocities(String clipId, Set<String> noteIds, double factor) {
    updateClip(clipId, (clip) {
      final notes = clip.notes.map((n) {
        if (noteIds.contains(n.id)) {
          return n.copyWith(velocity: (n.velocity * factor).clamp(0.0, 1.0));
        }
        return n;
      }).toList();
      return clip.copyWith(notes: notes);
    });
  }

  /// Quantize notes
  void quantizeNotes(String clipId, Set<String> noteIds, QuantizeValue value,
      {double strength = 1.0}) {
    if (value == QuantizeValue.off) return;

    final ticksPerBeat = 960;
    final gridTicks = value.ticks;

    updateClip(clipId, (clip) {
      final notes = clip.notes.map((n) {
        if (noteIds.contains(n.id)) {
          // Convert to ticks, quantize, convert back
          // Assuming 120 BPM for conversion (should use actual BPM)
          final beatsPerSecond = 120.0 / 60.0;
          final startTicks = (n.startTime * beatsPerSecond * ticksPerBeat).round();
          final quantizedTicks =
              ((startTicks + gridTicks ~/ 2) ~/ gridTicks) * gridTicks;

          // Apply strength (partial quantize)
          final deltaTicks = quantizedTicks - startTicks;
          final finalTicks = startTicks + (deltaTicks * strength).round();
          final newStartTime = finalTicks / ticksPerBeat / beatsPerSecond;

          return n.copyWith(startTime: newStartTime);
        }
        return n;
      }).toList();
      return clip.copyWith(notes: notes);
    });
  }

  /// Humanize notes (add slight timing/velocity variations)
  void humanizeNotes(String clipId, Set<String> noteIds,
      {double timingRange = 0.01, double velocityRange = 0.1}) {
    final random = DateTime.now().millisecondsSinceEpoch;
    var seed = random;

    double nextRandom() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed / 0x7fffffff) * 2 - 1; // -1 to 1
    }

    updateClip(clipId, (clip) {
      final notes = clip.notes.map((n) {
        if (noteIds.contains(n.id)) {
          return n.copyWith(
            startTime: n.startTime + nextRandom() * timingRange,
            velocity: (n.velocity + nextRandom() * velocityRange).clamp(0.0, 1.0),
          );
        }
        return n;
      }).toList();
      return clip.copyWith(notes: notes);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start MIDI recording
  void startRecording(String trackId, double startTime) {
    if (_recordingTrackId != null) {
      stopRecording();
    }

    _recordingTrackId = trackId;
    _recordingStartTime = startTime;
    _recordingNotes.clear();
    _heldNotes.clear();

    // Create or find clip at start time
    final existingClips = getClipsAt(trackId, startTime);
    if (existingClips.isEmpty || _recordMode == MidiRecordMode.replace) {
      final clip = createClip(
        trackId: trackId,
        startTime: startTime,
        duration: 4.0, // Will expand as needed
        name: 'Recording',
      );
      _recordingClipId = clip.id;
    } else {
      _recordingClipId = existingClips.first.id;
    }

    notifyListeners();
  }

  /// Stop MIDI recording
  MidiClip? stopRecording() {
    if (_recordingTrackId == null) return null;

    // End any held notes
    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    for (final pitch in _heldNotes) {
      _endRecordingNote(pitch, currentTime);
    }

    final clipId = _recordingClipId;
    _recordingTrackId = null;
    _recordingClipId = null;
    _recordingStartTime = null;
    _recordingNotes.clear();
    _heldNotes.clear();

    notifyListeners();
    return clipId != null ? getClip(clipId) : null;
  }

  /// Handle incoming MIDI note on
  void onMidiNoteOn(int pitch, int velocity, {int channel = 0}) {
    if (!isRecording) {
      // Just pass through if MIDI thru is enabled
      if (_midiThru) {
        _sendMidiNoteOn(pitch, velocity, channel);
      }
      return;
    }

    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final relativeTime = currentTime - (_recordingStartTime ?? currentTime);

    _heldNotes.add(pitch);

    final note = MidiNoteData(
      id: _generateId(),
      pitch: pitch,
      startTime: relativeTime,
      duration: 0, // Will be set on note off
      velocity: velocity / 127.0,
      channel: channel,
    );
    _recordingNotes.add(note);

    if (_midiThru) {
      _sendMidiNoteOn(pitch, velocity, channel);
    }
  }

  /// Handle incoming MIDI note off
  void onMidiNoteOff(int pitch, {int channel = 0}) {
    if (!isRecording) {
      if (_midiThru) {
        _sendMidiNoteOff(pitch, channel);
      }
      return;
    }

    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _endRecordingNote(pitch, currentTime);
    _heldNotes.remove(pitch);

    if (_midiThru) {
      _sendMidiNoteOff(pitch, channel);
    }
  }

  void _endRecordingNote(int pitch, double currentTime) {
    final relativeTime = currentTime - (_recordingStartTime ?? currentTime);

    // Find the matching note on
    for (int i = _recordingNotes.length - 1; i >= 0; i--) {
      final note = _recordingNotes[i];
      if (note.pitch == pitch && note.duration == 0) {
        final duration = relativeTime - note.startTime;
        _recordingNotes[i] = note.copyWith(duration: duration.clamp(0.01, 60.0));

        // Add to clip
        if (_recordingClipId != null) {
          addNote(
            clipId: _recordingClipId!,
            pitch: note.pitch,
            startTime: note.startTime,
            duration: duration,
            velocity: note.velocity,
            channel: note.channel,
          );
        }
        break;
      }
    }
  }

  void _sendMidiNoteOn(int pitch, int velocity, int channel) {
    // Send via FFI to connected MIDI output device
    final success = _ffi.midiSendNoteOn(channel, pitch, velocity);
    if (!success) {
      debugPrint('MIDI OUT: Failed to send Note On ch$channel $pitch vel$velocity (no output connected)');
    }
  }

  void _sendMidiNoteOff(int pitch, int channel) {
    // Send via FFI to connected MIDI output device
    final success = _ffi.midiSendNoteOff(channel, pitch, 64); // Standard release velocity
    if (!success) {
      debugPrint('MIDI OUT: Failed to send Note Off ch$channel $pitch (no output connected)');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIPBOARD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Copy selected notes to clipboard
  void copyNotes(String clipId, Set<String> noteIds) {
    final clip = getClip(clipId);
    if (clip == null) return;

    _clipboard =
        clip.notes.where((n) => noteIds.contains(n.id)).toList();
    if (_clipboard!.isNotEmpty) {
      _clipboardStartTime =
          _clipboard!.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);
    }
    notifyListeners();
  }

  /// Cut selected notes to clipboard
  void cutNotes(String clipId, Set<String> noteIds) {
    copyNotes(clipId, noteIds);
    deleteNotes(clipId, noteIds);
  }

  /// Paste notes from clipboard
  void pasteNotes(String clipId, double atTime) {
    if (_clipboard == null || _clipboard!.isEmpty) return;

    final offset = atTime - (_clipboardStartTime ?? 0);
    for (final note in _clipboard!) {
      addNote(
        clipId: clipId,
        pitch: note.pitch,
        startTime: note.startTime + offset,
        duration: note.duration,
        velocity: note.velocity,
        channel: note.channel,
      );
    }
  }

  /// Duplicate notes in place
  void duplicateNotes(String clipId, Set<String> noteIds, double offset) {
    final clip = getClip(clipId);
    if (clip == null) return;

    final toDuplicate = clip.notes.where((n) => noteIds.contains(n.id));
    for (final note in toDuplicate) {
      addNote(
        clipId: clipId,
        pitch: note.pitch,
        startTime: note.startTime + offset,
        duration: note.duration,
        velocity: note.velocity,
        channel: note.channel,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select clip
  void selectClip(String? clipId) {
    _selectedClipId = clipId;
    _selectedNoteIds.clear();
    notifyListeners();
  }

  /// Open clip for editing in piano roll
  void openClipForEditing(String clipId) {
    _editingClip = getClip(clipId);
    _selectedNoteIds.clear();
    notifyListeners();
  }

  /// Close piano roll editor
  void closeEditor() {
    _editingClip = null;
    _selectedNoteIds.clear();
    notifyListeners();
  }

  /// Select notes
  void selectNotes(Set<String> noteIds, {bool addToSelection = false}) {
    if (addToSelection) {
      _selectedNoteIds.addAll(noteIds);
    } else {
      _selectedNoteIds.clear();
      _selectedNoteIds.addAll(noteIds);
    }
    notifyListeners();
  }

  /// Deselect notes
  void deselectNotes(Set<String> noteIds) {
    _selectedNoteIds.removeAll(noteIds);
    notifyListeners();
  }

  /// Clear note selection
  void clearNoteSelection() {
    _selectedNoteIds.clear();
    notifyListeners();
  }

  /// Select all notes in clip
  void selectAllNotes(String clipId) {
    final clip = getClip(clipId);
    if (clip == null) return;
    _selectedNoteIds.clear();
    _selectedNoteIds.addAll(clip.notes.map((n) => n.id));
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  void setMidiThru(bool value) {
    _midiThru = value;
    notifyListeners();
  }

  void setRecordEnabled(bool value) {
    _recordEnabled = value;
    notifyListeners();
  }

  void setCountIn(bool enabled, {int? bars}) {
    _countInEnabled = enabled;
    if (bars != null) _countInBars = bars.clamp(1, 4);
    notifyListeners();
  }

  void setInputQuantize(QuantizeValue value) {
    _inputQuantize = value;
    notifyListeners();
  }

  void setRecordQuantize(QuantizeValue value) {
    _recordQuantize = value;
    notifyListeners();
  }

  void setRecordMode(MidiRecordMode mode) {
    _recordMode = mode;
    notifyListeners();
  }

  void setDefaultVelocity(double value) {
    _defaultVelocity = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setDefaultNoteDuration(double value) {
    _defaultNoteDuration = value.clamp(0.01, 8.0);
    notifyListeners();
  }

  void setDefaultChannel(int channel) {
    _defaultChannel = channel.clamp(0, 15);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT DEVICES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scan for MIDI input devices
  Future<void> scanInputDevices() async {
    _inputDevices.clear();

    // Always include virtual keyboard
    _inputDevices.add(const MidiInputDevice(id: 'virtual', name: 'Virtual Keyboard'));

    // Scan real MIDI devices via FFI
    final count = _ffi.midiScanInputDevices();
    final deviceNames = _ffi.midiGetAllInputDevices();

    for (int i = 0; i < deviceNames.length; i++) {
      _inputDevices.add(MidiInputDevice(
        id: 'midi_in_$i',
        name: deviceNames[i],
        isConnected: false,
        isEnabled: false,
      ));
    }

    notifyListeners();
  }

  /// Set active input device
  void setActiveInputDevice(String? deviceId) {
    _activeInputDeviceId = deviceId;
    notifyListeners();
  }

  /// Enable/disable input device
  void setInputDeviceEnabled(String deviceId, bool enabled) {
    final idx = _inputDevices.indexWhere((d) => d.id == deviceId);
    if (idx >= 0) {
      // Extract device index from ID (e.g., "midi_in_0" -> 0)
      final deviceIndex = int.tryParse(deviceId.replaceFirst('midi_in_', ''));

      bool success = true;
      if (deviceId != 'virtual' && deviceIndex != null) {
        if (enabled) {
          success = _ffi.midiConnectInput(deviceIndex);
        } else {
          // Find connection index (simplified - assumes 1:1 mapping)
          success = _ffi.midiDisconnectInput(deviceIndex);
        }
      }

      if (success) {
        _inputDevices[idx] = MidiInputDevice(
          id: _inputDevices[idx].id,
          name: _inputDevices[idx].name,
          isConnected: enabled,
          isEnabled: enabled,
        );
        notifyListeners();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FFI SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  void _syncNoteToFFI(String clipId, MidiNoteData note) {
    // Sync note to Rust piano roll when clip editor is open
    // Only sync if this clip is currently being edited (has an active piano roll)
    if (_editingClip?.id != clipId) return;

    try {
      final clipIdInt = int.tryParse(clipId.replaceFirst('midi_', ''));
      if (clipIdInt != null) {
        // Convert seconds to ticks (960 PPQN, assuming 120 BPM for conversion)
        const ticksPerBeat = 960;
        const beatsPerSecond = 120.0 / 60.0;
        final startTick = (note.startTime * beatsPerSecond * ticksPerBeat).round();
        final durationTicks = (note.duration * beatsPerSecond * ticksPerBeat).round();
        final velocityMidi = (note.velocity * 127).round().clamp(1, 127);

        _ffi.pianoRollAddNote(
          clipIdInt,
          note.pitch,
          startTick,
          durationTicks,
          velocityMidi,
        );
      }
    } catch (e) {
      debugPrint('Failed to sync note to FFI: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
        'midiThru': _midiThru,
        'countInEnabled': _countInEnabled,
        'countInBars': _countInBars,
        'inputQuantize': _inputQuantize.index,
        'recordQuantize': _recordQuantize.index,
        'recordMode': _recordMode.index,
        'defaultVelocity': _defaultVelocity,
        'defaultNoteDuration': _defaultNoteDuration,
        'defaultChannel': _defaultChannel,
        'clips': _clipsByTrack.map((trackId, clips) =>
            MapEntry(trackId, clips.map((c) => c.toJson()).toList())),
      };

  void fromJson(Map<String, dynamic> json) {
    _midiThru = json['midiThru'] as bool? ?? true;
    _countInEnabled = json['countInEnabled'] as bool? ?? true;
    _countInBars = json['countInBars'] as int? ?? 1;
    _inputQuantize =
        QuantizeValue.values[json['inputQuantize'] as int? ?? 0];
    _recordQuantize =
        QuantizeValue.values[json['recordQuantize'] as int? ?? 5];
    _recordMode = MidiRecordMode.values[json['recordMode'] as int? ?? 1];
    _defaultVelocity = (json['defaultVelocity'] as num?)?.toDouble() ?? 0.8;
    _defaultNoteDuration =
        (json['defaultNoteDuration'] as num?)?.toDouble() ?? 0.25;
    _defaultChannel = json['defaultChannel'] as int? ?? 0;

    _clipsByTrack.clear();
    final clipsJson = json['clips'] as Map<String, dynamic>?;
    if (clipsJson != null) {
      for (final entry in clipsJson.entries) {
        final clips = (entry.value as List)
            .map((c) => MidiClip.fromJson(c as Map<String, dynamic>))
            .toList();
        _clipsByTrack[entry.key] = clips;
      }
    }

    notifyListeners();
  }

  /// Clear all MIDI data
  void clear() {
    _clipsByTrack.clear();
    _selectedClipId = null;
    _selectedNoteIds.clear();
    _editingClip = null;
    _recordingTrackId = null;
    _recordingClipId = null;
    _recordingStartTime = null;
    _recordingNotes.clear();
    _heldNotes.clear();
    _clipboard = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  String _generateId() {
    return 'midi_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
  }

  static int _idCounter = 0;

}
