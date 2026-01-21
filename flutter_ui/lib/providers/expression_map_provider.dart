// Expression Map Provider
//
// Cubase-style expression maps for orchestral/instrument articulation:
// - Map keyswitches, program changes, CCs to articulations
// - Visual articulation lane in piano roll
// - Direction articulations (sustain, staccato, legato)
// - Attribute articulations (accent, vibrato, tremolo)
// - Multiple output mappings per articulation
// - Library presets for popular sample libraries
//
// Designed to match Cubase Pro 14 Expression Maps feature.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS & TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Articulation category
enum ArticulationCategory {
  direction,    // Sustaining techniques (legato, staccato, sustain)
  attribute,    // Note modifiers (accent, vibrato, trill)
}

/// Output type for articulation
enum ArticulationOutputType {
  noteOn,       // Trigger keyswitch note
  programChange, // MIDI program change
  controlChange, // MIDI CC message
  pitchBend,    // Pitch bend
  channelPressure, // Channel aftertouch
}

/// Common articulation types
enum ArticulationType {
  // Sustaining (Direction)
  sustain,
  legato,
  portamento,
  tremolo,
  trill,
  harmonics,
  flutter,
  ponticello,
  tasto,
  colLegno,

  // Short (Direction)
  staccato,
  staccatissimo,
  spiccato,
  pizzicato,
  marcato,
  tenuto,

  // Attribute
  accent,
  sforzando,
  vibrato,
  nonVibrato,
  crescendo,
  diminuendo,
  mute,
  open,

  // Custom
  custom,
}

/// Get default name for articulation type
String getArticulationTypeName(ArticulationType type) {
  switch (type) {
    case ArticulationType.sustain:
      return 'Sustain';
    case ArticulationType.legato:
      return 'Legato';
    case ArticulationType.portamento:
      return 'Portamento';
    case ArticulationType.tremolo:
      return 'Tremolo';
    case ArticulationType.trill:
      return 'Trill';
    case ArticulationType.harmonics:
      return 'Harmonics';
    case ArticulationType.flutter:
      return 'Flutter Tongue';
    case ArticulationType.ponticello:
      return 'Sul Ponticello';
    case ArticulationType.tasto:
      return 'Sul Tasto';
    case ArticulationType.colLegno:
      return 'Col Legno';
    case ArticulationType.staccato:
      return 'Staccato';
    case ArticulationType.staccatissimo:
      return 'Staccatissimo';
    case ArticulationType.spiccato:
      return 'Spiccato';
    case ArticulationType.pizzicato:
      return 'Pizzicato';
    case ArticulationType.marcato:
      return 'Marcato';
    case ArticulationType.tenuto:
      return 'Tenuto';
    case ArticulationType.accent:
      return 'Accent';
    case ArticulationType.sforzando:
      return 'Sforzando';
    case ArticulationType.vibrato:
      return 'Vibrato';
    case ArticulationType.nonVibrato:
      return 'Non Vibrato';
    case ArticulationType.crescendo:
      return 'Crescendo';
    case ArticulationType.diminuendo:
      return 'Diminuendo';
    case ArticulationType.mute:
      return 'Mute';
    case ArticulationType.open:
      return 'Open';
    case ArticulationType.custom:
      return 'Custom';
  }
}

/// Get default symbol for articulation
String getArticulationSymbol(ArticulationType type) {
  switch (type) {
    case ArticulationType.sustain:
      return '-';
    case ArticulationType.legato:
      return '⌒';
    case ArticulationType.staccato:
      return '.';
    case ArticulationType.staccatissimo:
      return '▾';
    case ArticulationType.spiccato:
      return '•';
    case ArticulationType.pizzicato:
      return '+';
    case ArticulationType.marcato:
      return '^';
    case ArticulationType.tenuto:
      return '–';
    case ArticulationType.accent:
      return '>';
    case ArticulationType.sforzando:
      return 'sf';
    case ArticulationType.tremolo:
      return '≋';
    case ArticulationType.trill:
      return 'tr';
    case ArticulationType.vibrato:
      return '~';
    default:
      return '○';
  }
}

/// Get default color for articulation type
Color getArticulationColor(ArticulationType type) {
  switch (type) {
    case ArticulationType.sustain:
    case ArticulationType.legato:
    case ArticulationType.portamento:
      return const Color(0xFF40FF90);   // Green - sustaining
    case ArticulationType.staccato:
    case ArticulationType.staccatissimo:
    case ArticulationType.spiccato:
    case ArticulationType.pizzicato:
      return const Color(0xFFFF9040);   // Orange - short
    case ArticulationType.marcato:
    case ArticulationType.accent:
    case ArticulationType.sforzando:
      return const Color(0xFFFF4060);   // Red - accented
    case ArticulationType.tremolo:
    case ArticulationType.trill:
    case ArticulationType.vibrato:
      return const Color(0xFF4A9EFF);   // Blue - effects
    case ArticulationType.harmonics:
    case ArticulationType.flutter:
      return const Color(0xFFAA40FF);   // Purple - special
    default:
      return const Color(0xFF808080);   // Gray - other
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUT MAPPING
// ═══════════════════════════════════════════════════════════════════════════════

/// A single output action for an articulation
class ArticulationOutput {
  final ArticulationOutputType type;
  final int channel;          // MIDI channel (1-16)

  // For noteOn: note number. For CC: controller number. For PC: program number
  final int data1;

  // For noteOn: velocity. For CC: value
  final int data2;

  // Duration for keyswitch notes (ms, 0 = hold)
  final int durationMs;

  // Whether to send note-off
  final bool sendNoteOff;

  const ArticulationOutput({
    required this.type,
    this.channel = 1,
    required this.data1,
    this.data2 = 127,
    this.durationMs = 0,
    this.sendNoteOff = true,
  });

  ArticulationOutput copyWith({
    ArticulationOutputType? type,
    int? channel,
    int? data1,
    int? data2,
    int? durationMs,
    bool? sendNoteOff,
  }) {
    return ArticulationOutput(
      type: type ?? this.type,
      channel: channel ?? this.channel,
      data1: data1 ?? this.data1,
      data2: data2 ?? this.data2,
      durationMs: durationMs ?? this.durationMs,
      sendNoteOff: sendNoteOff ?? this.sendNoteOff,
    );
  }

  String get description {
    switch (type) {
      case ArticulationOutputType.noteOn:
        final noteName = _midiNoteToName(data1);
        return 'Note $noteName (vel: $data2)';
      case ArticulationOutputType.programChange:
        return 'PC $data1';
      case ArticulationOutputType.controlChange:
        return 'CC $data1 = $data2';
      case ArticulationOutputType.pitchBend:
        return 'Pitch Bend $data1';
      case ArticulationOutputType.channelPressure:
        return 'Pressure $data1';
    }
  }

  String _midiNoteToName(int note) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (note ~/ 12) - 1;
    final name = names[note % 12];
    return '$name$octave';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ARTICULATION
// ═══════════════════════════════════════════════════════════════════════════════

/// A single articulation definition
class Articulation {
  final String id;
  final String name;
  final String symbol;        // Display symbol
  final String? description;
  final ArticulationType type;
  final ArticulationCategory category;
  final Color color;

  // Output mappings (can have multiple)
  final List<ArticulationOutput> outputs;

  // Group (for mutual exclusion within direction articulations)
  final int group;

  // Whether this is the default articulation
  final bool isDefault;

  // Keyboard shortcut (note: C0 = 0, C1 = 12, etc.)
  final int? remoteKeyNote;

  // Display order
  final int displayOrder;

  const Articulation({
    required this.id,
    required this.name,
    this.symbol = '○',
    this.description,
    this.type = ArticulationType.custom,
    this.category = ArticulationCategory.direction,
    this.color = const Color(0xFF808080),
    this.outputs = const [],
    this.group = 0,
    this.isDefault = false,
    this.remoteKeyNote,
    this.displayOrder = 0,
  });

  Articulation copyWith({
    String? id,
    String? name,
    String? symbol,
    String? description,
    ArticulationType? type,
    ArticulationCategory? category,
    Color? color,
    List<ArticulationOutput>? outputs,
    int? group,
    bool? isDefault,
    int? remoteKeyNote,
    int? displayOrder,
  }) {
    return Articulation(
      id: id ?? this.id,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      description: description ?? this.description,
      type: type ?? this.type,
      category: category ?? this.category,
      color: color ?? this.color,
      outputs: outputs ?? this.outputs,
      group: group ?? this.group,
      isDefault: isDefault ?? this.isDefault,
      remoteKeyNote: remoteKeyNote ?? this.remoteKeyNote,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  /// Create articulation from type preset
  factory Articulation.fromType(ArticulationType type, {
    required String id,
    int keyswitchNote = 0,
    int group = 0,
    bool isDefault = false,
  }) {
    return Articulation(
      id: id,
      name: getArticulationTypeName(type),
      symbol: getArticulationSymbol(type),
      type: type,
      category: _getCategoryForType(type),
      color: getArticulationColor(type),
      outputs: keyswitchNote > 0 ? [
        ArticulationOutput(
          type: ArticulationOutputType.noteOn,
          data1: keyswitchNote,
          data2: 127,
          durationMs: 10,
        )
      ] : [],
      group: group,
      isDefault: isDefault,
    );
  }

  static ArticulationCategory _getCategoryForType(ArticulationType type) {
    switch (type) {
      case ArticulationType.accent:
      case ArticulationType.sforzando:
      case ArticulationType.vibrato:
      case ArticulationType.nonVibrato:
      case ArticulationType.crescendo:
      case ArticulationType.diminuendo:
        return ArticulationCategory.attribute;
      default:
        return ArticulationCategory.direction;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPRESSION MAP
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete expression map for an instrument
class ExpressionMap {
  final String id;
  final String name;
  final String? description;
  final String? libraryName;      // Sample library name
  final String? instrumentName;   // Instrument within library

  // All articulations
  final List<Articulation> articulations;

  // Default articulation ID (for notes without explicit articulation)
  final String? defaultArticulationId;

  // Remote key range (for keyswitch assignments)
  final int remoteKeyRangeStart;
  final int remoteKeyRangeEnd;

  // Color for track display
  final Color color;

  const ExpressionMap({
    required this.id,
    required this.name,
    this.description,
    this.libraryName,
    this.instrumentName,
    this.articulations = const [],
    this.defaultArticulationId,
    this.remoteKeyRangeStart = 0,
    this.remoteKeyRangeEnd = 23,
    this.color = const Color(0xFF4A9EFF),
  });

  ExpressionMap copyWith({
    String? id,
    String? name,
    String? description,
    String? libraryName,
    String? instrumentName,
    List<Articulation>? articulations,
    String? defaultArticulationId,
    int? remoteKeyRangeStart,
    int? remoteKeyRangeEnd,
    Color? color,
  }) {
    return ExpressionMap(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      libraryName: libraryName ?? this.libraryName,
      instrumentName: instrumentName ?? this.instrumentName,
      articulations: articulations ?? this.articulations,
      defaultArticulationId: defaultArticulationId ?? this.defaultArticulationId,
      remoteKeyRangeStart: remoteKeyRangeStart ?? this.remoteKeyRangeStart,
      remoteKeyRangeEnd: remoteKeyRangeEnd ?? this.remoteKeyRangeEnd,
      color: color ?? this.color,
    );
  }

  /// Get articulation by ID
  Articulation? getArticulation(String id) {
    return articulations.cast<Articulation?>().firstWhere(
      (a) => a?.id == id,
      orElse: () => null,
    );
  }

  /// Get default articulation
  Articulation? get defaultArticulation {
    if (defaultArticulationId != null) {
      return getArticulation(defaultArticulationId!);
    }
    return articulations.cast<Articulation?>().firstWhere(
      (a) => a?.isDefault ?? false,
      orElse: () => articulations.isNotEmpty ? articulations.first : null,
    );
  }

  /// Get direction articulations
  List<Articulation> get directionArticulations =>
      articulations.where((a) => a.category == ArticulationCategory.direction).toList();

  /// Get attribute articulations
  List<Articulation> get attributeArticulations =>
      articulations.where((a) => a.category == ArticulationCategory.attribute).toList();

  /// Get articulations in a group
  List<Articulation> getArticulationsInGroup(int group) =>
      articulations.where((a) => a.group == group).toList();

  /// Find articulation by remote key note
  Articulation? getArticulationByRemoteKey(int note) {
    return articulations.cast<Articulation?>().firstWhere(
      (a) => a?.remoteKeyNote == note,
      orElse: () => null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ARTICULATION EVENT
// ═══════════════════════════════════════════════════════════════════════════════

/// An articulation event on a note or region
class ArticulationEvent {
  final String id;
  final String articulationId;

  // Position (can be note-based or time-based)
  final int startTick;          // PPQ ticks
  final int? endTick;           // For attribute articulations spanning time

  // Associated note ID (if attached to specific note)
  final String? noteId;

  const ArticulationEvent({
    required this.id,
    required this.articulationId,
    required this.startTick,
    this.endTick,
    this.noteId,
  });

  ArticulationEvent copyWith({
    String? id,
    String? articulationId,
    int? startTick,
    int? endTick,
    String? noteId,
  }) {
    return ArticulationEvent(
      id: id ?? this.id,
      articulationId: articulationId ?? this.articulationId,
      startTick: startTick ?? this.startTick,
      endTick: endTick ?? this.endTick,
      noteId: noteId ?? this.noteId,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class ExpressionMapProvider extends ChangeNotifier {
  // All expression maps by ID
  final Map<String, ExpressionMap> _maps = {};

  // Track-to-map assignments
  final Map<int, String> _trackAssignments = {};

  // Articulation events per track
  final Map<int, List<ArticulationEvent>> _trackEvents = {};

  // Currently active articulation per track (for direction articulations)
  final Map<int, String> _activeDirectionArticulations = {};

  // Currently active attributes per track (can have multiple)
  final Map<int, Set<String>> _activeAttributes = {};

  // Selected expression map for editing
  String? _selectedMapId;

  // Selected articulation within map
  String? _selectedArticulationId;

  // Global enable
  bool _enabled = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  String? get selectedMapId => _selectedMapId;
  String? get selectedArticulationId => _selectedArticulationId;

  List<ExpressionMap> get maps => _maps.values.toList();
  ExpressionMap? getMap(String id) => _maps[id];
  ExpressionMap? get selectedMap =>
      _selectedMapId != null ? _maps[_selectedMapId] : null;

  /// Get expression map assigned to track
  ExpressionMap? getMapForTrack(int trackId) {
    final mapId = _trackAssignments[trackId];
    return mapId != null ? _maps[mapId] : null;
  }

  /// Get articulation events for track
  List<ArticulationEvent> getEventsForTrack(int trackId) =>
      _trackEvents[trackId] ?? [];

  /// Get active direction articulation for track
  String? getActiveDirectionArticulation(int trackId) =>
      _activeDirectionArticulations[trackId];

  /// Get active attribute articulations for track
  Set<String> getActiveAttributes(int trackId) =>
      _activeAttributes[trackId] ?? {};

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

  void selectMap(String? mapId) {
    _selectedMapId = mapId;
    _selectedArticulationId = null;
    notifyListeners();
  }

  void selectArticulation(String? articulationId) {
    _selectedArticulationId = articulationId;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPRESSION MAP MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create new expression map
  ExpressionMap createMap({
    required String name,
    String? description,
    String? libraryName,
    String? instrumentName,
  }) {
    final id = 'expmap_${DateTime.now().millisecondsSinceEpoch}';

    final map = ExpressionMap(
      id: id,
      name: name,
      description: description,
      libraryName: libraryName,
      instrumentName: instrumentName,
    );

    _maps[id] = map;
    notifyListeners();
    return map;
  }

  /// Update expression map
  void updateMap(ExpressionMap map) {
    _maps[map.id] = map;
    notifyListeners();
  }

  /// Delete expression map
  void deleteMap(String mapId) {
    _maps.remove(mapId);

    // Remove from track assignments
    _trackAssignments.removeWhere((_, v) => v == mapId);

    if (_selectedMapId == mapId) _selectedMapId = null;
    notifyListeners();
  }

  /// Duplicate expression map
  ExpressionMap duplicateMap(String mapId) {
    final original = _maps[mapId];
    if (original == null) throw StateError('Map not found');

    final newId = 'expmap_${DateTime.now().millisecondsSinceEpoch}';
    final copy = original.copyWith(
      id: newId,
      name: '${original.name} Copy',
    );

    _maps[newId] = copy;
    notifyListeners();
    return copy;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ARTICULATION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add articulation to map
  Articulation addArticulation(
    String mapId, {
    required String name,
    ArticulationType type = ArticulationType.custom,
    ArticulationCategory category = ArticulationCategory.direction,
    int? keyswitchNote,
    int group = 0,
    bool isDefault = false,
  }) {
    final map = _maps[mapId];
    if (map == null) throw StateError('Map not found');

    final artId = 'art_${DateTime.now().millisecondsSinceEpoch}';

    final articulation = Articulation(
      id: artId,
      name: name,
      symbol: getArticulationSymbol(type),
      type: type,
      category: category,
      color: getArticulationColor(type),
      outputs: keyswitchNote != null ? [
        ArticulationOutput(
          type: ArticulationOutputType.noteOn,
          data1: keyswitchNote,
          data2: 127,
        )
      ] : [],
      group: group,
      isDefault: isDefault,
      remoteKeyNote: keyswitchNote,
      displayOrder: map.articulations.length,
    );

    _maps[mapId] = map.copyWith(
      articulations: [...map.articulations, articulation],
      defaultArticulationId: isDefault ? artId : map.defaultArticulationId,
    );

    notifyListeners();
    return articulation;
  }

  /// Update articulation in map
  void updateArticulation(String mapId, Articulation articulation) {
    final map = _maps[mapId];
    if (map == null) return;

    final articulations = map.articulations.map((a) {
      return a.id == articulation.id ? articulation : a;
    }).toList();

    _maps[mapId] = map.copyWith(articulations: articulations);
    notifyListeners();
  }

  /// Delete articulation from map
  void deleteArticulation(String mapId, String articulationId) {
    final map = _maps[mapId];
    if (map == null) return;

    final articulations = map.articulations
        .where((a) => a.id != articulationId)
        .toList();

    _maps[mapId] = map.copyWith(
      articulations: articulations,
      defaultArticulationId: map.defaultArticulationId == articulationId
          ? null
          : map.defaultArticulationId,
    );

    if (_selectedArticulationId == articulationId) {
      _selectedArticulationId = null;
    }

    notifyListeners();
  }

  /// Add output to articulation
  void addArticulationOutput(
    String mapId,
    String articulationId,
    ArticulationOutput output,
  ) {
    final map = _maps[mapId];
    if (map == null) return;

    final articulations = map.articulations.map((a) {
      if (a.id == articulationId) {
        return a.copyWith(outputs: [...a.outputs, output]);
      }
      return a;
    }).toList();

    _maps[mapId] = map.copyWith(articulations: articulations);
    notifyListeners();
  }

  /// Remove output from articulation
  void removeArticulationOutput(
    String mapId,
    String articulationId,
    int outputIndex,
  ) {
    final map = _maps[mapId];
    if (map == null) return;

    final articulations = map.articulations.map((a) {
      if (a.id == articulationId && outputIndex < a.outputs.length) {
        final newOutputs = List<ArticulationOutput>.from(a.outputs);
        newOutputs.removeAt(outputIndex);
        return a.copyWith(outputs: newOutputs);
      }
      return a;
    }).toList();

    _maps[mapId] = map.copyWith(articulations: articulations);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK ASSIGNMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Assign expression map to track
  void assignToTrack(int trackId, String? mapId) {
    if (mapId == null) {
      _trackAssignments.remove(trackId);
      _activeDirectionArticulations.remove(trackId);
      _activeAttributes.remove(trackId);
    } else {
      _trackAssignments[trackId] = mapId;

      // Set default articulation as active
      final map = _maps[mapId];
      if (map?.defaultArticulation != null) {
        _activeDirectionArticulations[trackId] = map!.defaultArticulation!.id;
      }
    }
    notifyListeners();
  }

  /// Get all tracks using a specific map
  List<int> getTracksUsingMap(String mapId) {
    return _trackAssignments.entries
        .where((e) => e.value == mapId)
        .map((e) => e.key)
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ARTICULATION EVENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add articulation event to track
  ArticulationEvent addEvent(
    int trackId, {
    required String articulationId,
    required int startTick,
    int? endTick,
    String? noteId,
  }) {
    final id = 'artevt_${DateTime.now().millisecondsSinceEpoch}';

    final event = ArticulationEvent(
      id: id,
      articulationId: articulationId,
      startTick: startTick,
      endTick: endTick,
      noteId: noteId,
    );

    _trackEvents.putIfAbsent(trackId, () => []);
    _trackEvents[trackId]!.add(event);
    _trackEvents[trackId]!.sort((a, b) => a.startTick.compareTo(b.startTick));

    notifyListeners();
    return event;
  }

  /// Update articulation event
  void updateEvent(int trackId, ArticulationEvent event) {
    final events = _trackEvents[trackId];
    if (events == null) return;

    final index = events.indexWhere((e) => e.id == event.id);
    if (index != -1) {
      events[index] = event;
      events.sort((a, b) => a.startTick.compareTo(b.startTick));
      notifyListeners();
    }
  }

  /// Delete articulation event
  void deleteEvent(int trackId, String eventId) {
    final events = _trackEvents[trackId];
    if (events == null) return;

    events.removeWhere((e) => e.id == eventId);
    notifyListeners();
  }

  /// Clear all events for track
  void clearTrackEvents(int trackId) {
    _trackEvents.remove(trackId);
    notifyListeners();
  }

  /// Get articulation at tick position
  ArticulationEvent? getEventAtTick(int trackId, int tick) {
    final events = _trackEvents[trackId];
    if (events == null) return null;

    // Find the most recent event before or at this tick
    ArticulationEvent? result;
    for (final event in events) {
      if (event.startTick <= tick) {
        result = event;
      } else {
        break;
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVE ARTICULATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set active direction articulation for track
  void setActiveDirectionArticulation(int trackId, String articulationId) {
    _activeDirectionArticulations[trackId] = articulationId;
    notifyListeners();
  }

  /// Toggle attribute articulation for track
  void toggleAttributeArticulation(int trackId, String articulationId) {
    _activeAttributes.putIfAbsent(trackId, () => {});
    final attrs = _activeAttributes[trackId]!;

    if (attrs.contains(articulationId)) {
      attrs.remove(articulationId);
    } else {
      attrs.add(articulationId);
    }
    notifyListeners();
  }

  /// Clear attribute articulations for track
  void clearAttributes(int trackId) {
    _activeAttributes.remove(trackId);
    notifyListeners();
  }

  /// Get MIDI outputs for current articulation state
  List<ArticulationOutput> getCurrentOutputs(int trackId) {
    final mapId = _trackAssignments[trackId];
    if (mapId == null) return [];

    final map = _maps[mapId];
    if (map == null) return [];

    final outputs = <ArticulationOutput>[];

    // Direction articulation
    final dirArtId = _activeDirectionArticulations[trackId];
    if (dirArtId != null) {
      final art = map.getArticulation(dirArtId);
      if (art != null) {
        outputs.addAll(art.outputs);
      }
    }

    // Attribute articulations
    final attrs = _activeAttributes[trackId] ?? {};
    for (final attrId in attrs) {
      final art = map.getArticulation(attrId);
      if (art != null) {
        outputs.addAll(art.outputs);
      }
    }

    return outputs;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create basic orchestral strings preset
  ExpressionMap createStringsPreset() {
    final map = createMap(
      name: 'Orchestral Strings',
      description: 'Basic orchestral strings expression map',
      libraryName: 'Generic',
      instrumentName: 'Strings',
    );

    // Direction articulations
    addArticulation(map.id, name: 'Sustain', type: ArticulationType.sustain, keyswitchNote: 24, isDefault: true);
    addArticulation(map.id, name: 'Legato', type: ArticulationType.legato, keyswitchNote: 25);
    addArticulation(map.id, name: 'Staccato', type: ArticulationType.staccato, keyswitchNote: 26);
    addArticulation(map.id, name: 'Pizzicato', type: ArticulationType.pizzicato, keyswitchNote: 27);
    addArticulation(map.id, name: 'Tremolo', type: ArticulationType.tremolo, keyswitchNote: 28);
    addArticulation(map.id, name: 'Spiccato', type: ArticulationType.spiccato, keyswitchNote: 29);

    // Attribute articulations
    addArticulation(map.id, name: 'Accent', type: ArticulationType.accent, category: ArticulationCategory.attribute);
    addArticulation(map.id, name: 'Vibrato', type: ArticulationType.vibrato, category: ArticulationCategory.attribute);

    return _maps[map.id]!;
  }

  /// Create basic brass preset
  ExpressionMap createBrassPreset() {
    final map = createMap(
      name: 'Orchestral Brass',
      description: 'Basic orchestral brass expression map',
      libraryName: 'Generic',
      instrumentName: 'Brass',
    );

    addArticulation(map.id, name: 'Sustain', type: ArticulationType.sustain, keyswitchNote: 24, isDefault: true);
    addArticulation(map.id, name: 'Staccato', type: ArticulationType.staccato, keyswitchNote: 25);
    addArticulation(map.id, name: 'Marcato', type: ArticulationType.marcato, keyswitchNote: 26);
    addArticulation(map.id, name: 'Mute', type: ArticulationType.mute, keyswitchNote: 27);
    addArticulation(map.id, name: 'Sforzando', type: ArticulationType.sforzando, keyswitchNote: 28);

    return _maps[map.id]!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'maps': _maps.values.map((m) => _mapToJson(m)).toList(),
      'trackAssignments': _trackAssignments.map((k, v) => MapEntry(k.toString(), v)),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? true;

    _maps.clear();
    if (json['maps'] != null) {
      for (final m in json['maps']) {
        final map = _mapFromJson(m);
        _maps[map.id] = map;
      }
    }

    _trackAssignments.clear();
    if (json['trackAssignments'] != null) {
      final assignments = json['trackAssignments'] as Map<String, dynamic>;
      for (final entry in assignments.entries) {
        _trackAssignments[int.parse(entry.key)] = entry.value as String;
      }
    }

    notifyListeners();
  }

  Map<String, dynamic> _mapToJson(ExpressionMap m) {
    return {
      'id': m.id,
      'name': m.name,
      'description': m.description,
      'libraryName': m.libraryName,
      'instrumentName': m.instrumentName,
      'articulations': m.articulations.map((a) => _artToJson(a)).toList(),
      'defaultArticulationId': m.defaultArticulationId,
      'remoteKeyRangeStart': m.remoteKeyRangeStart,
      'remoteKeyRangeEnd': m.remoteKeyRangeEnd,
      'color': m.color.toARGB32(),
    };
  }

  ExpressionMap _mapFromJson(Map<String, dynamic> json) {
    return ExpressionMap(
      id: json['id'],
      name: json['name'] ?? 'Expression Map',
      description: json['description'],
      libraryName: json['libraryName'],
      instrumentName: json['instrumentName'],
      articulations: (json['articulations'] as List?)
              ?.map((a) => _artFromJson(a))
              .toList() ??
          [],
      defaultArticulationId: json['defaultArticulationId'],
      remoteKeyRangeStart: json['remoteKeyRangeStart'] ?? 0,
      remoteKeyRangeEnd: json['remoteKeyRangeEnd'] ?? 23,
      color: Color(json['color'] ?? 0xFF4A9EFF),
    );
  }

  Map<String, dynamic> _artToJson(Articulation a) {
    return {
      'id': a.id,
      'name': a.name,
      'symbol': a.symbol,
      'description': a.description,
      'type': a.type.index,
      'category': a.category.index,
      'color': a.color.toARGB32(),
      'outputs': a.outputs.map((o) => _outputToJson(o)).toList(),
      'group': a.group,
      'isDefault': a.isDefault,
      'remoteKeyNote': a.remoteKeyNote,
      'displayOrder': a.displayOrder,
    };
  }

  Articulation _artFromJson(Map<String, dynamic> json) {
    return Articulation(
      id: json['id'],
      name: json['name'] ?? 'Articulation',
      symbol: json['symbol'] ?? '○',
      description: json['description'],
      type: ArticulationType.values[json['type'] ?? 24],
      category: ArticulationCategory.values[json['category'] ?? 0],
      color: Color(json['color'] ?? 0xFF808080),
      outputs: (json['outputs'] as List?)
              ?.map((o) => _outputFromJson(o))
              .toList() ??
          [],
      group: json['group'] ?? 0,
      isDefault: json['isDefault'] ?? false,
      remoteKeyNote: json['remoteKeyNote'],
      displayOrder: json['displayOrder'] ?? 0,
    );
  }

  Map<String, dynamic> _outputToJson(ArticulationOutput o) {
    return {
      'type': o.type.index,
      'channel': o.channel,
      'data1': o.data1,
      'data2': o.data2,
      'durationMs': o.durationMs,
      'sendNoteOff': o.sendNoteOff,
    };
  }

  ArticulationOutput _outputFromJson(Map<String, dynamic> json) {
    return ArticulationOutput(
      type: ArticulationOutputType.values[json['type'] ?? 0],
      channel: json['channel'] ?? 1,
      data1: json['data1'] ?? 0,
      data2: json['data2'] ?? 127,
      durationMs: json['durationMs'] ?? 0,
      sendNoteOff: json['sendNoteOff'] ?? true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _maps.clear();
    _trackAssignments.clear();
    _trackEvents.clear();
    _activeDirectionArticulations.clear();
    _activeAttributes.clear();
    _selectedMapId = null;
    _selectedArticulationId = null;
    _enabled = true;
    notifyListeners();
  }

}
