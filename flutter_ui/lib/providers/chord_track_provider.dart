// Chord Track Provider
//
// Cubase-style chord track for intelligent composition:
// - Define chord progression on dedicated track
// - MIDI tracks can follow chord track
// - Voicing options (close, open, drop 2, etc.)
// - Tension control (add9, sus4, etc.)
// - Key/scale detection and suggestions
// - Chord assistant for circle of fifths navigation
//
// Key concepts:
// - ChordEvent: A chord at a specific time with voicing settings
// - ChordSymbol: Root + quality + extensions
// - VoicingPreset: How to voice the chord (drop2, spread, etc.)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS & TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Chord root notes
enum ChordRoot {
  c, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b,
}

/// Get note name for root
String getRootName(ChordRoot root, {bool useFlats = false}) {
  if (useFlats) {
    return const ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'][root.index];
  }
  return const ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][root.index];
}

/// Chord quality (major, minor, etc.)
enum ChordQuality {
  major,
  minor,
  diminished,
  augmented,
  sus2,
  sus4,
  dominant7,
  major7,
  minor7,
  minorMajor7,
  diminished7,
  halfDiminished7,
  augmented7,
  power5,
}

/// Get quality suffix for display
String getQualitySuffix(ChordQuality quality) {
  switch (quality) {
    case ChordQuality.major:
      return '';
    case ChordQuality.minor:
      return 'm';
    case ChordQuality.diminished:
      return 'dim';
    case ChordQuality.augmented:
      return 'aug';
    case ChordQuality.sus2:
      return 'sus2';
    case ChordQuality.sus4:
      return 'sus4';
    case ChordQuality.dominant7:
      return '7';
    case ChordQuality.major7:
      return 'maj7';
    case ChordQuality.minor7:
      return 'm7';
    case ChordQuality.minorMajor7:
      return 'mMaj7';
    case ChordQuality.diminished7:
      return 'dim7';
    case ChordQuality.halfDiminished7:
      return 'm7b5';
    case ChordQuality.augmented7:
      return 'aug7';
    case ChordQuality.power5:
      return '5';
  }
}

/// Chord intervals for each quality (semitones from root)
List<int> getQualityIntervals(ChordQuality quality) {
  switch (quality) {
    case ChordQuality.major:
      return [0, 4, 7];
    case ChordQuality.minor:
      return [0, 3, 7];
    case ChordQuality.diminished:
      return [0, 3, 6];
    case ChordQuality.augmented:
      return [0, 4, 8];
    case ChordQuality.sus2:
      return [0, 2, 7];
    case ChordQuality.sus4:
      return [0, 5, 7];
    case ChordQuality.dominant7:
      return [0, 4, 7, 10];
    case ChordQuality.major7:
      return [0, 4, 7, 11];
    case ChordQuality.minor7:
      return [0, 3, 7, 10];
    case ChordQuality.minorMajor7:
      return [0, 3, 7, 11];
    case ChordQuality.diminished7:
      return [0, 3, 6, 9];
    case ChordQuality.halfDiminished7:
      return [0, 3, 6, 10];
    case ChordQuality.augmented7:
      return [0, 4, 8, 10];
    case ChordQuality.power5:
      return [0, 7];
  }
}

/// Chord tensions (extensions)
enum ChordTension {
  none,
  add9,
  add11,
  add13,
  flat9,
  sharp9,
  sharp11,
  flat13,
}

/// Get tension interval
int? getTensionInterval(ChordTension tension) {
  switch (tension) {
    case ChordTension.none:
      return null;
    case ChordTension.add9:
      return 14; // 2 + 12
    case ChordTension.add11:
      return 17; // 5 + 12
    case ChordTension.add13:
      return 21; // 9 + 12
    case ChordTension.flat9:
      return 13;
    case ChordTension.sharp9:
      return 15;
    case ChordTension.sharp11:
      return 18;
    case ChordTension.flat13:
      return 20;
  }
}

/// Voicing presets
enum VoicingPreset {
  close,        // Close position (tight)
  open,         // Open position (spread)
  drop2,        // Drop 2nd voice down an octave
  drop3,        // Drop 3rd voice down an octave
  drop24,       // Drop 2nd and 4th voices
  spread,       // Wide spread voicing
  guitar,       // Guitar-friendly voicing
  piano,        // Piano-friendly voicing
  pad,          // Sustained pad voicing
}

/// Bass note option
enum BassOption {
  root,         // Root in bass
  third,        // 3rd in bass (1st inversion)
  fifth,        // 5th in bass (2nd inversion)
  seventh,      // 7th in bass (3rd inversion)
  custom,       // Custom bass note
}

/// Musical scale type
enum ScaleType {
  major,
  naturalMinor,
  harmonicMinor,
  melodicMinor,
  dorian,
  phrygian,
  lydian,
  mixolydian,
  locrian,
  pentatonicMajor,
  pentatonicMinor,
  blues,
}

/// Get scale intervals
List<int> getScaleIntervals(ScaleType scale) {
  switch (scale) {
    case ScaleType.major:
      return [0, 2, 4, 5, 7, 9, 11];
    case ScaleType.naturalMinor:
      return [0, 2, 3, 5, 7, 8, 10];
    case ScaleType.harmonicMinor:
      return [0, 2, 3, 5, 7, 8, 11];
    case ScaleType.melodicMinor:
      return [0, 2, 3, 5, 7, 9, 11];
    case ScaleType.dorian:
      return [0, 2, 3, 5, 7, 9, 10];
    case ScaleType.phrygian:
      return [0, 1, 3, 5, 7, 8, 10];
    case ScaleType.lydian:
      return [0, 2, 4, 6, 7, 9, 11];
    case ScaleType.mixolydian:
      return [0, 2, 4, 5, 7, 9, 10];
    case ScaleType.locrian:
      return [0, 1, 3, 5, 6, 8, 10];
    case ScaleType.pentatonicMajor:
      return [0, 2, 4, 7, 9];
    case ScaleType.pentatonicMinor:
      return [0, 3, 5, 7, 10];
    case ScaleType.blues:
      return [0, 3, 5, 6, 7, 10];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHORD SYMBOL
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete chord symbol definition
class ChordSymbol {
  final ChordRoot root;
  final ChordQuality quality;
  final List<ChordTension> tensions;
  final BassOption bassOption;
  final ChordRoot? customBassNote;

  const ChordSymbol({
    required this.root,
    this.quality = ChordQuality.major,
    this.tensions = const [],
    this.bassOption = BassOption.root,
    this.customBassNote,
  });

  ChordSymbol copyWith({
    ChordRoot? root,
    ChordQuality? quality,
    List<ChordTension>? tensions,
    BassOption? bassOption,
    ChordRoot? customBassNote,
  }) {
    return ChordSymbol(
      root: root ?? this.root,
      quality: quality ?? this.quality,
      tensions: tensions ?? this.tensions,
      bassOption: bassOption ?? this.bassOption,
      customBassNote: customBassNote ?? this.customBassNote,
    );
  }

  /// Get display name (e.g., "Cmaj7", "Dm/F")
  String get displayName {
    final rootName = getRootName(root);
    final suffix = getQualitySuffix(quality);

    // Add tensions
    String tensionStr = '';
    for (final t in tensions) {
      if (t != ChordTension.none) {
        switch (t) {
          case ChordTension.add9:
            tensionStr += 'add9';
            break;
          case ChordTension.add11:
            tensionStr += 'add11';
            break;
          case ChordTension.add13:
            tensionStr += 'add13';
            break;
          case ChordTension.flat9:
            tensionStr += '(b9)';
            break;
          case ChordTension.sharp9:
            tensionStr += '(#9)';
            break;
          case ChordTension.sharp11:
            tensionStr += '(#11)';
            break;
          case ChordTension.flat13:
            tensionStr += '(b13)';
            break;
          case ChordTension.none:
            break;
        }
      }
    }

    // Add bass note if not root
    String bassStr = '';
    if (bassOption != BassOption.root) {
      final bassNote = getBassNote();
      if (bassNote != null && bassNote != root) {
        bassStr = '/${getRootName(bassNote)}';
      }
    }

    return '$rootName$suffix$tensionStr$bassStr';
  }

  /// Get MIDI notes for this chord
  List<int> getMidiNotes({int baseOctave = 4, VoicingPreset voicing = VoicingPreset.close}) {
    final rootMidi = 60 + root.index + (baseOctave - 4) * 12;
    final intervals = getQualityIntervals(quality);

    // Build basic chord
    var notes = intervals.map((i) => rootMidi + i).toList();

    // Add tensions
    for (final t in tensions) {
      final interval = getTensionInterval(t);
      if (interval != null) {
        notes.add(rootMidi + interval);
      }
    }

    // Apply voicing
    notes = _applyVoicing(notes, voicing);

    // Handle bass note
    if (bassOption != BassOption.root) {
      final bassNote = getBassNote();
      if (bassNote != null) {
        final bassMidi = 36 + bassNote.index; // Bass octave (C2)
        // Remove any notes at bass pitch
        notes = notes.where((n) => n % 12 != bassNote.index).toList();
        // Add bass note at bottom
        notes.insert(0, bassMidi);
      }
    }

    return notes..sort();
  }

  /// Get bass note
  ChordRoot? getBassNote() {
    switch (bassOption) {
      case BassOption.root:
        return root;
      case BassOption.third:
        final intervals = getQualityIntervals(quality);
        if (intervals.length > 1) {
          return ChordRoot.values[(root.index + intervals[1]) % 12];
        }
        return root;
      case BassOption.fifth:
        final intervals = getQualityIntervals(quality);
        if (intervals.length > 2) {
          return ChordRoot.values[(root.index + intervals[2]) % 12];
        }
        return root;
      case BassOption.seventh:
        final intervals = getQualityIntervals(quality);
        if (intervals.length > 3) {
          return ChordRoot.values[(root.index + intervals[3]) % 12];
        }
        return root;
      case BassOption.custom:
        return customBassNote ?? root;
    }
  }

  /// Apply voicing transformation
  List<int> _applyVoicing(List<int> notes, VoicingPreset voicing) {
    if (notes.length < 3) return notes;

    switch (voicing) {
      case VoicingPreset.close:
        return notes; // Already close position

      case VoicingPreset.open:
        // Spread notes across 2 octaves
        final result = <int>[notes[0]];
        for (int i = 1; i < notes.length; i++) {
          result.add(notes[i] + (i % 2 == 0 ? 12 : 0));
        }
        return result;

      case VoicingPreset.drop2:
        if (notes.length >= 4) {
          // Drop 2nd voice from top down an octave
          final sorted = List<int>.from(notes)..sort();
          final second = sorted[sorted.length - 2];
          sorted[sorted.length - 2] = second - 12;
          return sorted..sort();
        }
        return notes;

      case VoicingPreset.drop3:
        if (notes.length >= 4) {
          final sorted = List<int>.from(notes)..sort();
          final third = sorted[sorted.length - 3];
          sorted[sorted.length - 3] = third - 12;
          return sorted..sort();
        }
        return notes;

      case VoicingPreset.drop24:
        if (notes.length >= 4) {
          final sorted = List<int>.from(notes)..sort();
          sorted[sorted.length - 2] -= 12;
          sorted[sorted.length - 4] -= 12;
          return sorted..sort();
        }
        return notes;

      case VoicingPreset.spread:
        // Maximum spread
        final result = <int>[];
        for (int i = 0; i < notes.length; i++) {
          result.add(notes[i] + i * 5); // Spread by 5 semitones each
        }
        return result;

      case VoicingPreset.guitar:
        // Guitar-friendly (within 4 fret span usually)
        return notes;

      case VoicingPreset.piano:
        // Piano-friendly with bass and upper structure
        if (notes.isEmpty) return notes;
        final bass = notes[0] - 12;
        return [bass, ...notes];

      case VoicingPreset.pad:
        // Sustained pad - doubled octaves
        final result = <int>[];
        for (final n in notes) {
          result.add(n);
          result.add(n + 12);
        }
        return result;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHORD EVENT
// ═══════════════════════════════════════════════════════════════════════════════

/// A chord event on the chord track
class ChordEvent {
  final String id;
  final ChordSymbol chord;

  // Position (in bars/beats)
  final int startBar;
  final int startBeat;
  final int lengthBars;
  final int lengthBeats;

  // Voicing settings
  final VoicingPreset voicing;
  final int baseOctave;
  final int velocity;

  // Visual
  final Color? color;

  const ChordEvent({
    required this.id,
    required this.chord,
    required this.startBar,
    this.startBeat = 1,
    required this.lengthBars,
    this.lengthBeats = 0,
    this.voicing = VoicingPreset.close,
    this.baseOctave = 4,
    this.velocity = 80,
    this.color,
  });

  ChordEvent copyWith({
    String? id,
    ChordSymbol? chord,
    int? startBar,
    int? startBeat,
    int? lengthBars,
    int? lengthBeats,
    VoicingPreset? voicing,
    int? baseOctave,
    int? velocity,
    Color? color,
  }) {
    return ChordEvent(
      id: id ?? this.id,
      chord: chord ?? this.chord,
      startBar: startBar ?? this.startBar,
      startBeat: startBeat ?? this.startBeat,
      lengthBars: lengthBars ?? this.lengthBars,
      lengthBeats: lengthBeats ?? this.lengthBeats,
      voicing: voicing ?? this.voicing,
      baseOctave: baseOctave ?? this.baseOctave,
      velocity: velocity ?? this.velocity,
      color: color ?? this.color,
    );
  }

  /// Get MIDI notes for this event
  List<int> getMidiNotes() {
    return chord.getMidiNotes(baseOctave: baseOctave, voicing: voicing);
  }

  /// Get end bar
  int get endBar => startBar + lengthBars;

  /// Get display name
  String get displayName => chord.displayName;
}

// ═══════════════════════════════════════════════════════════════════════════════
// KEY SIGNATURE
// ═══════════════════════════════════════════════════════════════════════════════

/// Key signature for the project
class KeySignature {
  final ChordRoot root;
  final ScaleType scale;

  const KeySignature({
    this.root = ChordRoot.c,
    this.scale = ScaleType.major,
  });

  KeySignature copyWith({
    ChordRoot? root,
    ScaleType? scale,
  }) {
    return KeySignature(
      root: root ?? this.root,
      scale: scale ?? this.scale,
    );
  }

  /// Get diatonic chords for this key
  List<ChordSymbol> getDiatonicChords() {
    final intervals = getScaleIntervals(scale);
    final result = <ChordSymbol>[];

    // Standard diatonic chord qualities for major scale
    final majorQualities = [
      ChordQuality.major,    // I
      ChordQuality.minor,    // ii
      ChordQuality.minor,    // iii
      ChordQuality.major,    // IV
      ChordQuality.major,    // V
      ChordQuality.minor,    // vi
      ChordQuality.diminished, // vii°
    ];

    final minorQualities = [
      ChordQuality.minor,    // i
      ChordQuality.diminished, // ii°
      ChordQuality.major,    // III
      ChordQuality.minor,    // iv
      ChordQuality.minor,    // v (or V if harmonic minor)
      ChordQuality.major,    // VI
      ChordQuality.major,    // VII
    ];

    final qualities = scale == ScaleType.major ? majorQualities : minorQualities;

    for (int i = 0; i < intervals.length && i < qualities.length; i++) {
      final chordRoot = ChordRoot.values[(root.index + intervals[i]) % 12];
      result.add(ChordSymbol(root: chordRoot, quality: qualities[i]));
    }

    return result;
  }

  /// Check if chord is diatonic to this key
  bool isChordDiatonic(ChordSymbol chord) {
    final diatonic = getDiatonicChords();
    return diatonic.any((c) => c.root == chord.root && c.quality == chord.quality);
  }

  /// Get display name
  String get displayName {
    final rootName = getRootName(root);
    final scaleName = scale == ScaleType.major ? 'Major' :
                      scale == ScaleType.naturalMinor ? 'Minor' :
                      scale.name;
    return '$rootName $scaleName';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class ChordTrackProvider extends ChangeNotifier {
  // Chord events by ID
  final Map<String, ChordEvent> _events = {};

  // Key signature
  KeySignature _keySignature = const KeySignature();

  // Track settings
  bool _visible = true;
  bool _enabled = true;
  double _trackHeight = 36.0;

  // Selection
  String? _selectedEventId;

  // Playback
  String? _currentEventId;

  // MIDI output settings
  bool _outputMidi = true;
  int _midiChannel = 1;

  // Voicing defaults
  VoicingPreset _defaultVoicing = VoicingPreset.close;
  int _defaultOctave = 4;
  int _defaultVelocity = 80;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get visible => _visible;
  bool get enabled => _enabled;
  double get trackHeight => _trackHeight;
  String? get selectedEventId => _selectedEventId;
  String? get currentEventId => _currentEventId;
  KeySignature get keySignature => _keySignature;
  bool get outputMidi => _outputMidi;
  int get midiChannel => _midiChannel;
  VoicingPreset get defaultVoicing => _defaultVoicing;
  int get defaultOctave => _defaultOctave;
  int get defaultVelocity => _defaultVelocity;

  List<ChordEvent> get events => _events.values.toList()
    ..sort((a, b) => a.startBar.compareTo(b.startBar));

  ChordEvent? getEvent(String id) => _events[id];
  ChordEvent? get selectedEvent =>
      _selectedEventId != null ? _events[_selectedEventId] : null;
  ChordEvent? get currentEvent =>
      _currentEventId != null ? _events[_currentEventId] : null;

  /// Get chord at a specific bar
  ChordEvent? getChordAtBar(int bar) {
    for (final event in _events.values) {
      if (bar >= event.startBar && bar < event.endBar) {
        return event;
      }
    }
    return null;
  }

  /// Get diatonic chords for current key
  List<ChordSymbol> get diatonicChords => _keySignature.getDiatonicChords();

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  void setVisible(bool value) {
    _visible = value;
    notifyListeners();
  }

  void toggleVisible() {
    _visible = !_visible;
    notifyListeners();
  }

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void toggleEnabled() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void setTrackHeight(double height) {
    _trackHeight = height.clamp(24.0, 80.0);
    notifyListeners();
  }

  void setKeySignature(KeySignature key) {
    _keySignature = key;
    notifyListeners();
  }

  void setMidiOutput(bool enabled) {
    _outputMidi = enabled;
    notifyListeners();
  }

  void setMidiChannel(int channel) {
    _midiChannel = channel.clamp(1, 16);
    notifyListeners();
  }

  void setDefaultVoicing(VoicingPreset voicing) {
    _defaultVoicing = voicing;
    notifyListeners();
  }

  void setDefaultOctave(int octave) {
    _defaultOctave = octave.clamp(1, 7);
    notifyListeners();
  }

  void setDefaultVelocity(int velocity) {
    _defaultVelocity = velocity.clamp(1, 127);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a chord event
  ChordEvent addChord({
    required ChordRoot root,
    ChordQuality quality = ChordQuality.major,
    required int startBar,
    int startBeat = 1,
    int lengthBars = 1,
    int lengthBeats = 0,
    VoicingPreset? voicing,
    int? baseOctave,
    int? velocity,
  }) {
    final id = 'chord_${DateTime.now().millisecondsSinceEpoch}';

    final event = ChordEvent(
      id: id,
      chord: ChordSymbol(root: root, quality: quality),
      startBar: startBar,
      startBeat: startBeat,
      lengthBars: lengthBars,
      lengthBeats: lengthBeats,
      voicing: voicing ?? _defaultVoicing,
      baseOctave: baseOctave ?? _defaultOctave,
      velocity: velocity ?? _defaultVelocity,
    );

    _events[id] = event;
    notifyListeners();
    return event;
  }

  /// Add chord event with full ChordSymbol
  ChordEvent addChordEvent({
    required ChordSymbol chord,
    required int startBar,
    int startBeat = 1,
    int lengthBars = 1,
    int lengthBeats = 0,
    VoicingPreset? voicing,
    int? baseOctave,
    int? velocity,
  }) {
    final id = 'chord_${DateTime.now().millisecondsSinceEpoch}';

    final event = ChordEvent(
      id: id,
      chord: chord,
      startBar: startBar,
      startBeat: startBeat,
      lengthBars: lengthBars,
      lengthBeats: lengthBeats,
      voicing: voicing ?? _defaultVoicing,
      baseOctave: baseOctave ?? _defaultOctave,
      velocity: velocity ?? _defaultVelocity,
    );

    _events[id] = event;
    notifyListeners();
    return event;
  }

  /// Update chord event
  void updateEvent(ChordEvent event) {
    _events[event.id] = event;
    notifyListeners();
  }

  /// Delete chord event
  void deleteEvent(String id) {
    _events.remove(id);
    if (_selectedEventId == id) _selectedEventId = null;
    if (_currentEventId == id) _currentEventId = null;
    notifyListeners();
  }

  /// Select event
  void selectEvent(String? id) {
    _selectedEventId = id;
    notifyListeners();
  }

  /// Move chord event
  void moveEvent(String id, int newStartBar, [int? newStartBeat]) {
    final event = _events[id];
    if (event == null) return;

    _events[id] = event.copyWith(
      startBar: newStartBar.clamp(1, 9999),
      startBeat: newStartBeat,
    );
    notifyListeners();
  }

  /// Resize chord event
  void resizeEvent(String id, int newLengthBars, [int? newLengthBeats]) {
    final event = _events[id];
    if (event == null) return;

    _events[id] = event.copyWith(
      lengthBars: newLengthBars.clamp(1, 999),
      lengthBeats: newLengthBeats,
    );
    notifyListeners();
  }

  /// Change chord root
  void changeChordRoot(String id, ChordRoot newRoot) {
    final event = _events[id];
    if (event == null) return;

    _events[id] = event.copyWith(chord: event.chord.copyWith(root: newRoot));
    notifyListeners();
  }

  /// Change chord quality
  void changeChordQuality(String id, ChordQuality newQuality) {
    final event = _events[id];
    if (event == null) return;

    _events[id] = event.copyWith(chord: event.chord.copyWith(quality: newQuality));
    notifyListeners();
  }

  /// Add tension to chord
  void addTension(String id, ChordTension tension) {
    final event = _events[id];
    if (event == null) return;

    final newTensions = [...event.chord.tensions, tension];
    _events[id] = event.copyWith(chord: event.chord.copyWith(tensions: newTensions));
    notifyListeners();
  }

  /// Remove tension from chord
  void removeTension(String id, ChordTension tension) {
    final event = _events[id];
    if (event == null) return;

    final newTensions = event.chord.tensions.where((t) => t != tension).toList();
    _events[id] = event.copyWith(chord: event.chord.copyWith(tensions: newTensions));
    notifyListeners();
  }

  /// Change voicing
  void changeVoicing(String id, VoicingPreset voicing) {
    final event = _events[id];
    if (event == null) return;

    _events[id] = event.copyWith(voicing: voicing);
    notifyListeners();
  }

  /// Duplicate chord event
  ChordEvent duplicateEvent(String id) {
    final original = _events[id];
    if (original == null) throw StateError('Event not found');

    return addChordEvent(
      chord: original.chord,
      startBar: original.endBar,
      lengthBars: original.lengthBars,
      lengthBeats: original.lengthBeats,
      voicing: original.voicing,
      baseOctave: original.baseOctave,
      velocity: original.velocity,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHORD ASSISTANT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get suggested next chords based on current chord
  List<ChordSymbol> getSuggestedChords(ChordSymbol current) {
    final suggestions = <ChordSymbol>[];

    // Circle of fifths - common progressions
    final fifthUp = ChordRoot.values[(current.root.index + 7) % 12];
    final fifthDown = ChordRoot.values[(current.root.index + 5) % 12];

    suggestions.add(ChordSymbol(root: fifthUp, quality: ChordQuality.major));
    suggestions.add(ChordSymbol(root: fifthDown, quality: ChordQuality.major));

    // Relative minor/major
    if (current.quality == ChordQuality.major) {
      final relMinor = ChordRoot.values[(current.root.index + 9) % 12];
      suggestions.add(ChordSymbol(root: relMinor, quality: ChordQuality.minor));
    } else if (current.quality == ChordQuality.minor) {
      final relMajor = ChordRoot.values[(current.root.index + 3) % 12];
      suggestions.add(ChordSymbol(root: relMajor, quality: ChordQuality.major));
    }

    // Add diatonic chords from key
    for (final chord in _keySignature.getDiatonicChords()) {
      if (!suggestions.any((s) => s.root == chord.root && s.quality == chord.quality)) {
        suggestions.add(chord);
      }
    }

    return suggestions;
  }

  /// Detect key from current chord progression
  KeySignature? detectKey() {
    if (_events.isEmpty) return null;

    // Count occurrences of each root note
    final rootCounts = <ChordRoot, int>{};
    for (final event in _events.values) {
      rootCounts[event.chord.root] = (rootCounts[event.chord.root] ?? 0) + 1;
    }

    // Find most common root
    ChordRoot? mostCommon;
    int maxCount = 0;
    for (final entry in rootCounts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        mostCommon = entry.key;
      }
    }

    if (mostCommon == null) return null;

    // Check if progression suggests major or minor
    final hasMinorTonic = _events.values.any((e) =>
        e.chord.root == mostCommon && e.chord.quality == ChordQuality.minor);

    return KeySignature(
      root: mostCommon,
      scale: hasMinorTonic ? ScaleType.naturalMinor : ScaleType.major,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update current chord based on playback position
  void updatePlaybackPosition(int bar, int beat) {
    for (final event in _events.values) {
      if (bar >= event.startBar && bar < event.endBar) {
        if (_currentEventId != event.id) {
          _currentEventId = event.id;
          notifyListeners();
        }
        return;
      }
    }
    if (_currentEventId != null) {
      _currentEventId = null;
      notifyListeners();
    }
  }

  /// Get MIDI notes for current chord
  List<int>? getCurrentMidiNotes() {
    return currentEvent?.getMidiNotes();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'visible': _visible,
      'enabled': _enabled,
      'trackHeight': _trackHeight,
      'keySignature': {
        'root': _keySignature.root.index,
        'scale': _keySignature.scale.index,
      },
      'outputMidi': _outputMidi,
      'midiChannel': _midiChannel,
      'defaultVoicing': _defaultVoicing.index,
      'defaultOctave': _defaultOctave,
      'defaultVelocity': _defaultVelocity,
      'events': _events.values.map((e) => _eventToJson(e)).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _visible = json['visible'] ?? true;
    _enabled = json['enabled'] ?? true;
    _trackHeight = (json['trackHeight'] ?? 36.0).toDouble();

    if (json['keySignature'] != null) {
      _keySignature = KeySignature(
        root: ChordRoot.values[json['keySignature']['root'] ?? 0],
        scale: ScaleType.values[json['keySignature']['scale'] ?? 0],
      );
    }

    _outputMidi = json['outputMidi'] ?? true;
    _midiChannel = json['midiChannel'] ?? 1;
    _defaultVoicing = VoicingPreset.values[json['defaultVoicing'] ?? 0];
    _defaultOctave = json['defaultOctave'] ?? 4;
    _defaultVelocity = json['defaultVelocity'] ?? 80;

    _events.clear();
    if (json['events'] != null) {
      for (final e in json['events']) {
        final event = _eventFromJson(e);
        _events[event.id] = event;
      }
    }

    notifyListeners();
  }

  Map<String, dynamic> _eventToJson(ChordEvent e) {
    return {
      'id': e.id,
      'chord': {
        'root': e.chord.root.index,
        'quality': e.chord.quality.index,
        'tensions': e.chord.tensions.map((t) => t.index).toList(),
        'bassOption': e.chord.bassOption.index,
        'customBassNote': e.chord.customBassNote?.index,
      },
      'startBar': e.startBar,
      'startBeat': e.startBeat,
      'lengthBars': e.lengthBars,
      'lengthBeats': e.lengthBeats,
      'voicing': e.voicing.index,
      'baseOctave': e.baseOctave,
      'velocity': e.velocity,
      'color': e.color?.toARGB32(),
    };
  }

  ChordEvent _eventFromJson(Map<String, dynamic> json) {
    final chordJson = json['chord'] ?? {};
    return ChordEvent(
      id: json['id'],
      chord: ChordSymbol(
        root: ChordRoot.values[chordJson['root'] ?? 0],
        quality: ChordQuality.values[chordJson['quality'] ?? 0],
        tensions: (chordJson['tensions'] as List?)
                ?.map((t) => ChordTension.values[t])
                .toList() ??
            [],
        bassOption: BassOption.values[chordJson['bassOption'] ?? 0],
        customBassNote: chordJson['customBassNote'] != null
            ? ChordRoot.values[chordJson['customBassNote']]
            : null,
      ),
      startBar: json['startBar'] ?? 1,
      startBeat: json['startBeat'] ?? 1,
      lengthBars: json['lengthBars'] ?? 1,
      lengthBeats: json['lengthBeats'] ?? 0,
      voicing: VoicingPreset.values[json['voicing'] ?? 0],
      baseOctave: json['baseOctave'] ?? 4,
      velocity: json['velocity'] ?? 80,
      color: json['color'] != null ? Color(json['color']) : null,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _events.clear();
    _keySignature = const KeySignature();
    _visible = true;
    _enabled = true;
    _selectedEventId = null;
    _currentEventId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
