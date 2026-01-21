/// Scale Assistant Provider - Cubase-style scale and key helper
///
/// Features:
/// - Scale detection from audio/MIDI
/// - Key signature management
/// - Scale-constrained MIDI editing
/// - Chord suggestions based on scale
/// - Parallel key suggestions
/// - Modal interchange helpers

import 'package:flutter/foundation.dart';

/// Musical note (pitch class)
enum NoteName {
  c,
  cSharp,
  d,
  dSharp,
  e,
  f,
  fSharp,
  g,
  gSharp,
  a,
  aSharp,
  b;

  String get displayName {
    switch (this) {
      case NoteName.c:
        return 'C';
      case NoteName.cSharp:
        return 'C#';
      case NoteName.d:
        return 'D';
      case NoteName.dSharp:
        return 'D#';
      case NoteName.e:
        return 'E';
      case NoteName.f:
        return 'F';
      case NoteName.fSharp:
        return 'F#';
      case NoteName.g:
        return 'G';
      case NoteName.gSharp:
        return 'G#';
      case NoteName.a:
        return 'A';
      case NoteName.aSharp:
        return 'A#';
      case NoteName.b:
        return 'B';
    }
  }

  String get flatName {
    switch (this) {
      case NoteName.cSharp:
        return 'Db';
      case NoteName.dSharp:
        return 'Eb';
      case NoteName.fSharp:
        return 'Gb';
      case NoteName.gSharp:
        return 'Ab';
      case NoteName.aSharp:
        return 'Bb';
      default:
        return displayName;
    }
  }

  int get semitone => index;

  static NoteName fromSemitone(int semitone) =>
      NoteName.values[semitone % 12];
}

/// Scale type/mode
enum ScaleType {
  // Diatonic modes
  major,
  minor, // Natural minor (Aeolian)
  dorian,
  phrygian,
  lydian,
  mixolydian,
  locrian,

  // Minor variants
  harmonicMinor,
  melodicMinor,

  // Pentatonic
  majorPentatonic,
  minorPentatonic,

  // Blues
  blues,
  majorBlues,

  // Other common scales
  wholeTone,
  diminished, // Half-whole
  diminishedWhole, // Whole-half
  chromatic,

  // Exotic
  hungarian,
  spanish,
  japanese,
  arabian,
  persian,
  byzantine;

  String get displayName {
    switch (this) {
      case ScaleType.major:
        return 'Major (Ionian)';
      case ScaleType.minor:
        return 'Natural Minor (Aeolian)';
      case ScaleType.dorian:
        return 'Dorian';
      case ScaleType.phrygian:
        return 'Phrygian';
      case ScaleType.lydian:
        return 'Lydian';
      case ScaleType.mixolydian:
        return 'Mixolydian';
      case ScaleType.locrian:
        return 'Locrian';
      case ScaleType.harmonicMinor:
        return 'Harmonic Minor';
      case ScaleType.melodicMinor:
        return 'Melodic Minor';
      case ScaleType.majorPentatonic:
        return 'Major Pentatonic';
      case ScaleType.minorPentatonic:
        return 'Minor Pentatonic';
      case ScaleType.blues:
        return 'Blues';
      case ScaleType.majorBlues:
        return 'Major Blues';
      case ScaleType.wholeTone:
        return 'Whole Tone';
      case ScaleType.diminished:
        return 'Diminished (H-W)';
      case ScaleType.diminishedWhole:
        return 'Diminished (W-H)';
      case ScaleType.chromatic:
        return 'Chromatic';
      case ScaleType.hungarian:
        return 'Hungarian Minor';
      case ScaleType.spanish:
        return 'Spanish (Phrygian Dominant)';
      case ScaleType.japanese:
        return 'Japanese (In)';
      case ScaleType.arabian:
        return 'Arabian';
      case ScaleType.persian:
        return 'Persian';
      case ScaleType.byzantine:
        return 'Byzantine';
    }
  }

  /// Interval pattern (semitones from root)
  List<int> get intervals {
    switch (this) {
      case ScaleType.major:
        return [0, 2, 4, 5, 7, 9, 11];
      case ScaleType.minor:
        return [0, 2, 3, 5, 7, 8, 10];
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
      case ScaleType.harmonicMinor:
        return [0, 2, 3, 5, 7, 8, 11];
      case ScaleType.melodicMinor:
        return [0, 2, 3, 5, 7, 9, 11];
      case ScaleType.majorPentatonic:
        return [0, 2, 4, 7, 9];
      case ScaleType.minorPentatonic:
        return [0, 3, 5, 7, 10];
      case ScaleType.blues:
        return [0, 3, 5, 6, 7, 10];
      case ScaleType.majorBlues:
        return [0, 2, 3, 4, 7, 9];
      case ScaleType.wholeTone:
        return [0, 2, 4, 6, 8, 10];
      case ScaleType.diminished:
        return [0, 1, 3, 4, 6, 7, 9, 10];
      case ScaleType.diminishedWhole:
        return [0, 2, 3, 5, 6, 8, 9, 11];
      case ScaleType.chromatic:
        return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
      case ScaleType.hungarian:
        return [0, 2, 3, 6, 7, 8, 11];
      case ScaleType.spanish:
        return [0, 1, 4, 5, 7, 8, 10];
      case ScaleType.japanese:
        return [0, 1, 5, 7, 8];
      case ScaleType.arabian:
        return [0, 2, 4, 5, 6, 8, 10];
      case ScaleType.persian:
        return [0, 1, 4, 5, 6, 8, 11];
      case ScaleType.byzantine:
        return [0, 1, 4, 5, 7, 8, 11];
    }
  }
}

/// Chord quality
enum ChordQuality {
  major,
  minor,
  diminished,
  augmented,
  major7,
  minor7,
  dominant7,
  diminished7,
  halfDiminished7,
  minorMajor7,
  sus2,
  sus4,
  add9,
  add11;

  String get symbol {
    switch (this) {
      case ChordQuality.major:
        return '';
      case ChordQuality.minor:
        return 'm';
      case ChordQuality.diminished:
        return 'dim';
      case ChordQuality.augmented:
        return 'aug';
      case ChordQuality.major7:
        return 'maj7';
      case ChordQuality.minor7:
        return 'm7';
      case ChordQuality.dominant7:
        return '7';
      case ChordQuality.diminished7:
        return 'dim7';
      case ChordQuality.halfDiminished7:
        return 'm7b5';
      case ChordQuality.minorMajor7:
        return 'mMaj7';
      case ChordQuality.sus2:
        return 'sus2';
      case ChordQuality.sus4:
        return 'sus4';
      case ChordQuality.add9:
        return 'add9';
      case ChordQuality.add11:
        return 'add11';
    }
  }

  /// Intervals from root
  List<int> get intervals {
    switch (this) {
      case ChordQuality.major:
        return [0, 4, 7];
      case ChordQuality.minor:
        return [0, 3, 7];
      case ChordQuality.diminished:
        return [0, 3, 6];
      case ChordQuality.augmented:
        return [0, 4, 8];
      case ChordQuality.major7:
        return [0, 4, 7, 11];
      case ChordQuality.minor7:
        return [0, 3, 7, 10];
      case ChordQuality.dominant7:
        return [0, 4, 7, 10];
      case ChordQuality.diminished7:
        return [0, 3, 6, 9];
      case ChordQuality.halfDiminished7:
        return [0, 3, 6, 10];
      case ChordQuality.minorMajor7:
        return [0, 3, 7, 11];
      case ChordQuality.sus2:
        return [0, 2, 7];
      case ChordQuality.sus4:
        return [0, 5, 7];
      case ChordQuality.add9:
        return [0, 4, 7, 14];
      case ChordQuality.add11:
        return [0, 4, 7, 17];
    }
  }
}

/// Chord definition
class ChordInfo {
  final NoteName root;
  final ChordQuality quality;

  /// Scale degree (1-7 for diatonic)
  final int? scaleDegree;

  /// Roman numeral (I, ii, III, etc.)
  final String? romanNumeral;

  const ChordInfo({
    required this.root,
    required this.quality,
    this.scaleDegree,
    this.romanNumeral,
  });

  String get name => '${root.displayName}${quality.symbol}';

  List<int> get midiNotes {
    final rootMidi = root.semitone + 60; // Middle C octave
    return quality.intervals.map((i) => rootMidi + i).toList();
  }

  Map<String, dynamic> toJson() => {
        'root': root.name,
        'quality': quality.name,
        'scaleDegree': scaleDegree,
        'romanNumeral': romanNumeral,
      };

  factory ChordInfo.fromJson(Map<String, dynamic> json) => ChordInfo(
        root: NoteName.values.firstWhere((n) => n.name == json['root']),
        quality: ChordQuality.values
            .firstWhere((q) => q.name == json['quality']),
        scaleDegree: json['scaleDegree'] as int?,
        romanNumeral: json['romanNumeral'] as String?,
      );
}

/// Key/scale definition
class MusicalKey {
  final String id;
  final NoteName root;
  final ScaleType scale;

  /// Time range this key applies (in ticks, null = global)
  final int? startTick;
  final int? endTick;

  /// Detection confidence (if auto-detected)
  final double? confidence;

  const MusicalKey({
    required this.id,
    required this.root,
    required this.scale,
    this.startTick,
    this.endTick,
    this.confidence,
  });

  String get displayName => '${root.displayName} ${scale.displayName}';

  String get shortName {
    final scaleShort = scale == ScaleType.major
        ? 'maj'
        : scale == ScaleType.minor
            ? 'min'
            : scale.name;
    return '${root.displayName} $scaleShort';
  }

  /// Get all notes in this scale
  List<NoteName> get scaleNotes {
    return scale.intervals
        .map((i) => NoteName.fromSemitone(root.semitone + i))
        .toList();
  }

  /// Check if a MIDI note is in this scale
  bool containsNote(int midiNote) {
    final noteClass = midiNote % 12;
    final rootOffset = (noteClass - root.semitone + 12) % 12;
    return scale.intervals.contains(rootOffset);
  }

  /// Quantize note to nearest scale note
  int quantizeToScale(int midiNote) {
    if (containsNote(midiNote)) return midiNote;

    // Find nearest scale note
    for (var offset = 1; offset <= 6; offset++) {
      if (containsNote(midiNote - offset)) return midiNote - offset;
      if (containsNote(midiNote + offset)) return midiNote + offset;
    }
    return midiNote;
  }

  /// Get diatonic chords in this key
  List<ChordInfo> get diatonicChords {
    final chords = <ChordInfo>[];
    final romanNumerals = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
    final notes = scaleNotes;

    for (var i = 0; i < notes.length && i < 7; i++) {
      final chordRoot = notes[i];

      // Determine chord quality based on scale degree
      ChordQuality quality;
      String roman = romanNumerals[i];

      if (scale == ScaleType.major) {
        switch (i) {
          case 0:
          case 3:
          case 4:
            quality = ChordQuality.major;
            break;
          case 1:
          case 2:
          case 5:
            quality = ChordQuality.minor;
            roman = roman.toLowerCase();
            break;
          case 6:
            quality = ChordQuality.diminished;
            roman = '${roman.toLowerCase()}°';
            break;
          default:
            quality = ChordQuality.major;
        }
      } else if (scale == ScaleType.minor) {
        switch (i) {
          case 0:
          case 3:
          case 4:
            quality = ChordQuality.minor;
            roman = roman.toLowerCase();
            break;
          case 2:
          case 5:
          case 6:
            quality = ChordQuality.major;
            break;
          case 1:
            quality = ChordQuality.diminished;
            roman = '${roman.toLowerCase()}°';
            break;
          default:
            quality = ChordQuality.minor;
        }
      } else {
        // Default to triad analysis for other scales
        quality = _analyzeTriadQuality(notes, i);
        if (quality == ChordQuality.minor ||
            quality == ChordQuality.diminished) {
          roman = roman.toLowerCase();
        }
        if (quality == ChordQuality.diminished) {
          roman += '°';
        } else if (quality == ChordQuality.augmented) {
          roman += '+';
        }
      }

      chords.add(ChordInfo(
        root: chordRoot,
        quality: quality,
        scaleDegree: i + 1,
        romanNumeral: roman,
      ));
    }

    return chords;
  }

  ChordQuality _analyzeTriadQuality(List<NoteName> notes, int degree) {
    if (notes.length < 3) return ChordQuality.major;

    final root = notes[degree].semitone;
    final third = notes[(degree + 2) % notes.length].semitone;
    final fifth = notes[(degree + 4) % notes.length].semitone;

    final thirdInterval = (third - root + 12) % 12;
    final fifthInterval = (fifth - root + 12) % 12;

    if (thirdInterval == 4 && fifthInterval == 7) {
      return ChordQuality.major;
    } else if (thirdInterval == 3 && fifthInterval == 7) {
      return ChordQuality.minor;
    } else if (thirdInterval == 3 && fifthInterval == 6) {
      return ChordQuality.diminished;
    } else if (thirdInterval == 4 && fifthInterval == 8) {
      return ChordQuality.augmented;
    }

    return thirdInterval <= 3 ? ChordQuality.minor : ChordQuality.major;
  }

  /// Get relative major/minor
  MusicalKey? get relativeKey {
    if (scale == ScaleType.major) {
      // Relative minor is 3 semitones down
      return MusicalKey(
        id: '${id}_rel',
        root: NoteName.fromSemitone(root.semitone - 3),
        scale: ScaleType.minor,
      );
    } else if (scale == ScaleType.minor) {
      // Relative major is 3 semitones up
      return MusicalKey(
        id: '${id}_rel',
        root: NoteName.fromSemitone(root.semitone + 3),
        scale: ScaleType.major,
      );
    }
    return null;
  }

  /// Get parallel major/minor
  MusicalKey? get parallelKey {
    if (scale == ScaleType.major) {
      return MusicalKey(
        id: '${id}_par',
        root: root,
        scale: ScaleType.minor,
      );
    } else if (scale == ScaleType.minor) {
      return MusicalKey(
        id: '${id}_par',
        root: root,
        scale: ScaleType.major,
      );
    }
    return null;
  }

  MusicalKey copyWith({
    String? id,
    NoteName? root,
    ScaleType? scale,
    int? startTick,
    int? endTick,
    double? confidence,
  }) {
    return MusicalKey(
      id: id ?? this.id,
      root: root ?? this.root,
      scale: scale ?? this.scale,
      startTick: startTick ?? this.startTick,
      endTick: endTick ?? this.endTick,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'root': root.name,
        'scale': scale.name,
        'startTick': startTick,
        'endTick': endTick,
        'confidence': confidence,
      };

  factory MusicalKey.fromJson(Map<String, dynamic> json) => MusicalKey(
        id: json['id'] as String,
        root: NoteName.values.firstWhere((n) => n.name == json['root']),
        scale: ScaleType.values.firstWhere((s) => s.name == json['scale']),
        startTick: json['startTick'] as int?,
        endTick: json['endTick'] as int?,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
}

/// Scale constraint mode for MIDI editing
enum ScaleConstraintMode {
  /// No constraint, free editing
  off,

  /// Highlight scale notes, allow all
  highlight,

  /// Snap to nearest scale note on input
  snapOnInput,

  /// Constrain all notes to scale
  strict,
}

/// Scale Assistant Provider
class ScaleAssistantProvider extends ChangeNotifier {
  /// Key signatures (can have multiple for key changes)
  final List<MusicalKey> _keys = [];

  /// Global/default key (when no key change applies)
  MusicalKey _globalKey = MusicalKey(
    id: 'global',
    root: NoteName.c,
    scale: ScaleType.major,
  );

  /// Constraint mode for MIDI editing
  ScaleConstraintMode _constraintMode = ScaleConstraintMode.highlight;

  /// Show scale notes on piano roll
  bool _showScaleNotes = true;

  /// Show chord suggestions
  bool _showChordSuggestions = true;

  /// Auto-detect key from content
  bool _autoDetect = false;

  /// Detection confidence threshold
  double _detectionThreshold = 0.7;

  /// Currently analyzed notes (for detection)
  final Map<int, int> _noteHistogram = {};

  // === Getters ===

  List<MusicalKey> get keys => List.unmodifiable(_keys);
  MusicalKey get globalKey => _globalKey;
  ScaleConstraintMode get constraintMode => _constraintMode;
  bool get showScaleNotes => _showScaleNotes;
  bool get showChordSuggestions => _showChordSuggestions;
  bool get autoDetect => _autoDetect;
  double get detectionThreshold => _detectionThreshold;

  /// Get key at specific position
  MusicalKey getKeyAtPosition(int tick) {
    for (final key in _keys.reversed) {
      if (key.startTick != null && tick >= key.startTick!) {
        if (key.endTick == null || tick < key.endTick!) {
          return key;
        }
      }
    }
    return _globalKey;
  }

  /// Get all scale notes at position
  List<NoteName> getScaleNotesAt(int tick) {
    return getKeyAtPosition(tick).scaleNotes;
  }

  /// Check if note is in scale at position
  bool isNoteInScale(int midiNote, int tick) {
    return getKeyAtPosition(tick).containsNote(midiNote);
  }

  /// Quantize note to scale at position
  int quantizeNote(int midiNote, int tick) {
    if (_constraintMode == ScaleConstraintMode.off) {
      return midiNote;
    }
    return getKeyAtPosition(tick).quantizeToScale(midiNote);
  }

  /// Get diatonic chords at position
  List<ChordInfo> getChordsAt(int tick) {
    return getKeyAtPosition(tick).diatonicChords;
  }

  // === Key Management ===

  /// Set global key
  void setGlobalKey(NoteName root, ScaleType scale) {
    _globalKey = MusicalKey(
      id: 'global',
      root: root,
      scale: scale,
    );
    notifyListeners();
  }

  /// Add key change
  void addKeyChange({
    required NoteName root,
    required ScaleType scale,
    required int startTick,
    int? endTick,
  }) {
    final id = 'key_${DateTime.now().millisecondsSinceEpoch}';
    _keys.add(MusicalKey(
      id: id,
      root: root,
      scale: scale,
      startTick: startTick,
      endTick: endTick,
    ));
    _keys.sort((a, b) => (a.startTick ?? 0).compareTo(b.startTick ?? 0));
    notifyListeners();
  }

  /// Update key change
  void updateKeyChange(
    String keyId, {
    NoteName? root,
    ScaleType? scale,
    int? startTick,
    int? endTick,
  }) {
    final index = _keys.indexWhere((k) => k.id == keyId);
    if (index != -1) {
      _keys[index] = _keys[index].copyWith(
        root: root,
        scale: scale,
        startTick: startTick,
        endTick: endTick,
      );
      _keys.sort((a, b) => (a.startTick ?? 0).compareTo(b.startTick ?? 0));
      notifyListeners();
    }
  }

  /// Remove key change
  void removeKeyChange(String keyId) {
    _keys.removeWhere((k) => k.id == keyId);
    notifyListeners();
  }

  /// Clear all key changes
  void clearKeyChanges() {
    _keys.clear();
    notifyListeners();
  }

  // === Settings ===

  void setConstraintMode(ScaleConstraintMode mode) {
    _constraintMode = mode;
    notifyListeners();
  }

  void setShowScaleNotes(bool show) {
    _showScaleNotes = show;
    notifyListeners();
  }

  void setShowChordSuggestions(bool show) {
    _showChordSuggestions = show;
    notifyListeners();
  }

  void setAutoDetect(bool auto) {
    _autoDetect = auto;
    notifyListeners();
  }

  void setDetectionThreshold(double threshold) {
    _detectionThreshold = threshold.clamp(0.0, 1.0);
    notifyListeners();
  }

  // === Key Detection ===

  /// Add note to histogram for detection
  void addNoteForDetection(int midiNote, {int weight = 1}) {
    final noteClass = midiNote % 12;
    _noteHistogram[noteClass] = (_noteHistogram[noteClass] ?? 0) + weight;

    if (_autoDetect) {
      _detectKey();
    }
  }

  /// Clear detection histogram
  void clearDetectionData() {
    _noteHistogram.clear();
    notifyListeners();
  }

  /// Detect key from histogram
  MusicalKey? _detectKey() {
    if (_noteHistogram.isEmpty) return null;

    double bestScore = 0.0;
    NoteName? bestRoot;
    ScaleType? bestScale;

    // Test all possible keys
    for (final root in NoteName.values) {
      for (final scale in [ScaleType.major, ScaleType.minor]) {
        final score = _calculateKeyScore(root, scale);
        if (score > bestScore) {
          bestScore = score;
          bestRoot = root;
          bestScale = scale;
        }
      }
    }

    if (bestRoot != null &&
        bestScale != null &&
        bestScore >= _detectionThreshold) {
      _globalKey = MusicalKey(
        id: 'detected',
        root: bestRoot,
        scale: bestScale,
        confidence: bestScore,
      );
      notifyListeners();
      return _globalKey;
    }

    return null;
  }

  double _calculateKeyScore(NoteName root, ScaleType scale) {
    final scaleIntervals = scale.intervals;
    final totalWeight =
        _noteHistogram.values.fold<int>(0, (sum, w) => sum + w);
    if (totalWeight == 0) return 0.0;

    int inScaleWeight = 0;

    for (final entry in _noteHistogram.entries) {
      final noteClass = entry.key;
      final weight = entry.value;

      // Calculate interval from proposed root
      final interval = (noteClass - root.semitone + 12) % 12;

      if (scaleIntervals.contains(interval)) {
        inScaleWeight += weight;

        // Bonus for root, fifth, third
        if (interval == 0) {
          inScaleWeight += weight ~/ 2; // Root bonus
        } else if (interval == 7) {
          inScaleWeight += weight ~/ 4; // Fifth bonus
        } else if (interval == 4 || interval == 3) {
          inScaleWeight += weight ~/ 4; // Third bonus
        }
      }
    }

    return inScaleWeight / (totalWeight * 1.5); // Normalize with bonuses
  }

  /// Detect key from MIDI data
  Future<MusicalKey?> detectKeyFromMidi(List<int> midiNotes) async {
    clearDetectionData();

    for (final note in midiNotes) {
      addNoteForDetection(note);
    }

    return _detectKey();
  }

  // === Suggestions ===

  /// Get suggested next chords based on current chord
  List<ChordInfo> getSuggestedChords(ChordInfo currentChord, int tick) {
    final key = getKeyAtPosition(tick);
    final diatonic = key.diatonicChords;
    final suggestions = <ChordInfo>[];

    // Find current chord in diatonic chords
    final currentDegree = diatonic.indexWhere(
      (c) => c.root == currentChord.root && c.quality == currentChord.quality,
    );

    if (currentDegree == -1) {
      // Not diatonic, suggest tonic and dominant
      suggestions.add(diatonic[0]); // I
      if (diatonic.length > 4) suggestions.add(diatonic[4]); // V
      return suggestions;
    }

    // Common progressions based on current chord
    switch (currentDegree) {
      case 0: // I
        if (diatonic.length > 4) suggestions.add(diatonic[4]); // V
        if (diatonic.length > 3) suggestions.add(diatonic[3]); // IV
        if (diatonic.length > 5) suggestions.add(diatonic[5]); // vi
        break;
      case 1: // ii
        suggestions.add(diatonic[4]); // V
        suggestions.add(diatonic[0]); // I
        break;
      case 2: // iii
        if (diatonic.length > 5) suggestions.add(diatonic[5]); // vi
        if (diatonic.length > 3) suggestions.add(diatonic[3]); // IV
        break;
      case 3: // IV
        suggestions.add(diatonic[4]); // V
        suggestions.add(diatonic[0]); // I
        if (diatonic.length > 1) suggestions.add(diatonic[1]); // ii
        break;
      case 4: // V
        suggestions.add(diatonic[0]); // I
        if (diatonic.length > 5) suggestions.add(diatonic[5]); // vi (deceptive)
        break;
      case 5: // vi
        if (diatonic.length > 1) suggestions.add(diatonic[1]); // ii
        if (diatonic.length > 3) suggestions.add(diatonic[3]); // IV
        break;
      case 6: // vii°
        suggestions.add(diatonic[0]); // I
        break;
    }

    return suggestions;
  }

  /// Get modal interchange chords
  List<ChordInfo> getModalInterchangeChords(int tick) {
    final key = getKeyAtPosition(tick);
    final parallelKey = key.parallelKey;
    if (parallelKey == null) return [];

    // Get chords from parallel key that differ
    final currentChords = key.diatonicChords;
    final parallelChords = parallelKey.diatonicChords;

    return parallelChords.where((pc) {
      return !currentChords.any(
        (cc) => cc.root == pc.root && cc.quality == pc.quality,
      );
    }).toList();
  }

  // === Serialization ===

  Map<String, dynamic> toJson() => {
        'globalKey': _globalKey.toJson(),
        'keys': _keys.map((k) => k.toJson()).toList(),
        'constraintMode': _constraintMode.name,
        'showScaleNotes': _showScaleNotes,
        'showChordSuggestions': _showChordSuggestions,
        'autoDetect': _autoDetect,
        'detectionThreshold': _detectionThreshold,
      };

  void loadFromJson(Map<String, dynamic> json) {
    _globalKey = MusicalKey.fromJson(
      json['globalKey'] as Map<String, dynamic>,
    );

    _keys.clear();
    final keysList = json['keys'] as List<dynamic>?;
    if (keysList != null) {
      for (final k in keysList) {
        _keys.add(MusicalKey.fromJson(k as Map<String, dynamic>));
      }
    }

    _constraintMode = ScaleConstraintMode.values.firstWhere(
      (m) => m.name == json['constraintMode'],
      orElse: () => ScaleConstraintMode.highlight,
    );

    _showScaleNotes = json['showScaleNotes'] as bool? ?? true;
    _showChordSuggestions = json['showChordSuggestions'] as bool? ?? true;
    _autoDetect = json['autoDetect'] as bool? ?? false;
    _detectionThreshold =
        (json['detectionThreshold'] as num?)?.toDouble() ?? 0.7;

    notifyListeners();
  }

  /// Clear all data
  void clear() {
    _keys.clear();
    _globalKey = MusicalKey(
      id: 'global',
      root: NoteName.c,
      scale: ScaleType.major,
    );
    _noteHistogram.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
