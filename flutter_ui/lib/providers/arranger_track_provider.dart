// Arranger Track Provider
//
// Cubase-style arranger track for non-linear arrangement:
// - Define sections (intro, verse, chorus, bridge, etc.)
// - Create arranger chains for different playback orders
// - Non-destructive song structure experimentation
// - Jump to sections during playback
// - Loop sections individually
//
// Key concepts:
// - ArrangerSection: Named time region (e.g., "Chorus A" from bar 16-24)
// - ArrangerChain: Ordered list of sections defining playback order
// - ArrangerEvent: Instance of a section in a chain (with repeat count)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES & ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Predefined section types with suggested colors
enum ArrangerSectionType {
  intro,
  verse,
  preChorus,
  chorus,
  bridge,
  breakdown,
  buildup,
  drop,
  outro,
  solo,
  interlude,
  custom,
}

/// Get color for section type
Color getSectionTypeColor(ArrangerSectionType type) {
  switch (type) {
    case ArrangerSectionType.intro:
      return const Color(0xFF4A9EFF);   // Blue
    case ArrangerSectionType.verse:
      return const Color(0xFF40C8FF);   // Cyan
    case ArrangerSectionType.preChorus:
      return const Color(0xFFFF9040);   // Orange
    case ArrangerSectionType.chorus:
      return const Color(0xFFFF4060);   // Red
    case ArrangerSectionType.bridge:
      return const Color(0xFFAA40FF);   // Purple
    case ArrangerSectionType.breakdown:
      return const Color(0xFF808080);   // Gray
    case ArrangerSectionType.buildup:
      return const Color(0xFFFFDD40);   // Yellow
    case ArrangerSectionType.drop:
      return const Color(0xFFFF4040);   // Bright red
    case ArrangerSectionType.outro:
      return const Color(0xFF4A9EFF);   // Blue (like intro)
    case ArrangerSectionType.solo:
      return const Color(0xFFFF40FF);   // Magenta
    case ArrangerSectionType.interlude:
      return const Color(0xFF40FF90);   // Green
    case ArrangerSectionType.custom:
      return const Color(0xFF808080);   // Gray
  }
}

/// Get default name for section type
String getSectionTypeName(ArrangerSectionType type) {
  switch (type) {
    case ArrangerSectionType.intro:
      return 'Intro';
    case ArrangerSectionType.verse:
      return 'Verse';
    case ArrangerSectionType.preChorus:
      return 'Pre-Chorus';
    case ArrangerSectionType.chorus:
      return 'Chorus';
    case ArrangerSectionType.bridge:
      return 'Bridge';
    case ArrangerSectionType.breakdown:
      return 'Breakdown';
    case ArrangerSectionType.buildup:
      return 'Buildup';
    case ArrangerSectionType.drop:
      return 'Drop';
    case ArrangerSectionType.outro:
      return 'Outro';
    case ArrangerSectionType.solo:
      return 'Solo';
    case ArrangerSectionType.interlude:
      return 'Interlude';
    case ArrangerSectionType.custom:
      return 'Section';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ARRANGER SECTION
// ═══════════════════════════════════════════════════════════════════════════════

/// A named section in the timeline
class ArrangerSection {
  final String id;
  final String name;
  final ArrangerSectionType type;
  final Color color;

  // Position (in bars or beats depending on timeBase)
  final int startBar;       // Start bar (1-based)
  final int startBeat;      // Start beat within bar (1-based)
  final int lengthBars;     // Length in bars
  final int lengthBeats;    // Additional beats

  // Optional time signature for this section
  final int? timeSignatureNumerator;
  final int? timeSignatureDenominator;

  // Tempo change at section start
  final double? tempo;

  // Notes for this section
  final String notes;

  const ArrangerSection({
    required this.id,
    required this.name,
    this.type = ArrangerSectionType.custom,
    this.color = const Color(0xFF4A9EFF),
    required this.startBar,
    this.startBeat = 1,
    required this.lengthBars,
    this.lengthBeats = 0,
    this.timeSignatureNumerator,
    this.timeSignatureDenominator,
    this.tempo,
    this.notes = '',
  });

  ArrangerSection copyWith({
    String? id,
    String? name,
    ArrangerSectionType? type,
    Color? color,
    int? startBar,
    int? startBeat,
    int? lengthBars,
    int? lengthBeats,
    int? timeSignatureNumerator,
    int? timeSignatureDenominator,
    double? tempo,
    String? notes,
  }) {
    return ArrangerSection(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      color: color ?? this.color,
      startBar: startBar ?? this.startBar,
      startBeat: startBeat ?? this.startBeat,
      lengthBars: lengthBars ?? this.lengthBars,
      lengthBeats: lengthBeats ?? this.lengthBeats,
      timeSignatureNumerator: timeSignatureNumerator ?? this.timeSignatureNumerator,
      timeSignatureDenominator: timeSignatureDenominator ?? this.timeSignatureDenominator,
      tempo: tempo ?? this.tempo,
      notes: notes ?? this.notes,
    );
  }

  /// Get end bar
  int get endBar => startBar + lengthBars;

  /// Convert to time in seconds (requires tempo info)
  double startTimeSeconds(double bpm, int beatsPerBar) {
    final totalBeats = (startBar - 1) * beatsPerBar + (startBeat - 1);
    return totalBeats * 60.0 / bpm;
  }

  double durationSeconds(double bpm, int beatsPerBar) {
    final totalBeats = lengthBars * beatsPerBar + lengthBeats;
    return totalBeats * 60.0 / bpm;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ARRANGER EVENT (Section instance in a chain)
// ═══════════════════════════════════════════════════════════════════════════════

/// An instance of a section in an arranger chain
class ArrangerEvent {
  final String id;
  final String sectionId;   // Reference to ArrangerSection
  final int repeatCount;    // How many times to play (1 = once)
  final bool muted;         // Skip this event in playback

  const ArrangerEvent({
    required this.id,
    required this.sectionId,
    this.repeatCount = 1,
    this.muted = false,
  });

  ArrangerEvent copyWith({
    String? id,
    String? sectionId,
    int? repeatCount,
    bool? muted,
  }) {
    return ArrangerEvent(
      id: id ?? this.id,
      sectionId: sectionId ?? this.sectionId,
      repeatCount: repeatCount ?? this.repeatCount,
      muted: muted ?? this.muted,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ARRANGER CHAIN
// ═══════════════════════════════════════════════════════════════════════════════

/// A sequence of arranger events defining playback order
class ArrangerChain {
  final String id;
  final String name;
  final List<ArrangerEvent> events;
  final bool isFlattened;   // True if chain has been "flattened" to linear arrangement

  const ArrangerChain({
    required this.id,
    required this.name,
    this.events = const [],
    this.isFlattened = false,
  });

  ArrangerChain copyWith({
    String? id,
    String? name,
    List<ArrangerEvent>? events,
    bool? isFlattened,
  }) {
    return ArrangerChain(
      id: id ?? this.id,
      name: name ?? this.name,
      events: events ?? this.events,
      isFlattened: isFlattened ?? this.isFlattened,
    );
  }

  /// Add event to chain
  ArrangerChain addEvent(ArrangerEvent event) {
    return copyWith(events: [...events, event]);
  }

  /// Remove event from chain
  ArrangerChain removeEvent(String eventId) {
    return copyWith(events: events.where((e) => e.id != eventId).toList());
  }

  /// Move event to new position
  ArrangerChain moveEvent(String eventId, int newIndex) {
    final eventIndex = events.indexWhere((e) => e.id == eventId);
    if (eventIndex == -1 || newIndex == eventIndex) return this;

    final newEvents = List<ArrangerEvent>.from(events);
    final event = newEvents.removeAt(eventIndex);
    newEvents.insert(newIndex.clamp(0, newEvents.length), event);
    return copyWith(events: newEvents);
  }

  /// Get total duration in bars
  int getTotalBars(Map<String, ArrangerSection> sections) {
    int total = 0;
    for (final event in events) {
      if (event.muted) continue;
      final section = sections[event.sectionId];
      if (section != null) {
        total += section.lengthBars * event.repeatCount;
      }
    }
    return total;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class ArrangerTrackProvider extends ChangeNotifier {
  // All sections by ID
  final Map<String, ArrangerSection> _sections = {};

  // All chains by ID
  final Map<String, ArrangerChain> _chains = {};

  // Active chain for playback
  String? _activeChainId;

  // Currently playing event index (in active chain)
  int _currentEventIndex = 0;

  // Currently playing repeat (within event)
  int _currentRepeat = 0;

  // Arranger mode enabled
  bool _enabled = false;

  // Track visibility
  bool _visible = true;

  // Track height
  double _trackHeight = 40.0;

  // Selected section/event for editing
  String? _selectedSectionId;
  String? _selectedEventId;

  // Project tempo for calculations
  double _bpm = 120.0;
  int _beatsPerBar = 4;

  // Section counter for naming
  final Map<ArrangerSectionType, int> _sectionCounts = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  bool get visible => _visible;
  double get trackHeight => _trackHeight;
  String? get activeChainId => _activeChainId;
  String? get selectedSectionId => _selectedSectionId;
  String? get selectedEventId => _selectedEventId;
  int get currentEventIndex => _currentEventIndex;
  int get currentRepeat => _currentRepeat;
  double get bpm => _bpm;
  int get beatsPerBar => _beatsPerBar;

  List<ArrangerSection> get sections => _sections.values.toList()
    ..sort((a, b) => a.startBar.compareTo(b.startBar));

  List<ArrangerChain> get chains => _chains.values.toList();

  ArrangerSection? getSection(String id) => _sections[id];
  ArrangerChain? getChain(String id) => _chains[id];
  ArrangerChain? get activeChain =>
      _activeChainId != null ? _chains[_activeChainId] : null;

  /// Get section at a specific bar
  ArrangerSection? getSectionAtBar(int bar) {
    for (final section in _sections.values) {
      if (bar >= section.startBar && bar < section.endBar) {
        return section;
      }
    }
    return null;
  }

  /// Get all sections that overlap a bar range
  List<ArrangerSection> getSectionsInRange(int startBar, int endBar) {
    return _sections.values.where((s) {
      return s.startBar < endBar && s.endBar > startBar;
    }).toList();
  }

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

  void setVisible(bool value) {
    _visible = value;
    notifyListeners();
  }

  void toggleVisible() {
    _visible = !_visible;
    notifyListeners();
  }

  void setTrackHeight(double height) {
    _trackHeight = height.clamp(24.0, 100.0);
    notifyListeners();
  }

  void setBpm(double bpm) {
    _bpm = bpm.clamp(20.0, 300.0);
    notifyListeners();
  }

  void setBeatsPerBar(int beats) {
    _beatsPerBar = beats.clamp(1, 16);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new section
  ArrangerSection addSection({
    required int startBar,
    required int lengthBars,
    ArrangerSectionType type = ArrangerSectionType.custom,
    String? name,
    Color? color,
  }) {
    final id = 'section_${DateTime.now().millisecondsSinceEpoch}';

    // Auto-generate name based on type
    _sectionCounts[type] = (_sectionCounts[type] ?? 0) + 1;
    final autoName = name ?? '${getSectionTypeName(type)} ${_sectionCounts[type]}';

    final section = ArrangerSection(
      id: id,
      name: autoName,
      type: type,
      color: color ?? getSectionTypeColor(type),
      startBar: startBar,
      lengthBars: lengthBars,
    );

    _sections[id] = section;
    notifyListeners();
    return section;
  }

  /// Update a section
  void updateSection(ArrangerSection section) {
    _sections[section.id] = section;
    notifyListeners();
  }

  /// Delete a section
  void deleteSection(String sectionId) {
    _sections.remove(sectionId);

    // Remove from all chains
    for (final chainId in _chains.keys.toList()) {
      final chain = _chains[chainId]!;
      final filtered = chain.events.where((e) => e.sectionId != sectionId).toList();
      if (filtered.length != chain.events.length) {
        _chains[chainId] = chain.copyWith(events: filtered);
      }
    }

    if (_selectedSectionId == sectionId) _selectedSectionId = null;
    notifyListeners();
  }

  /// Select section
  void selectSection(String? sectionId) {
    _selectedSectionId = sectionId;
    _selectedEventId = null;
    notifyListeners();
  }

  /// Move section to new start bar
  void moveSection(String sectionId, int newStartBar) {
    final section = _sections[sectionId];
    if (section == null) return;

    _sections[sectionId] = section.copyWith(startBar: newStartBar.clamp(1, 9999));
    notifyListeners();
  }

  /// Resize section
  void resizeSection(String sectionId, int newLengthBars) {
    final section = _sections[sectionId];
    if (section == null) return;

    _sections[sectionId] = section.copyWith(lengthBars: newLengthBars.clamp(1, 999));
    notifyListeners();
  }

  /// Duplicate section
  ArrangerSection duplicateSection(String sectionId) {
    final original = _sections[sectionId];
    if (original == null) {
      throw StateError('Section not found');
    }

    return addSection(
      startBar: original.endBar,
      lengthBars: original.lengthBars,
      type: original.type,
      name: '${original.name} Copy',
      color: original.color,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAIN MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new chain
  ArrangerChain addChain({String? name}) {
    final id = 'chain_${DateTime.now().millisecondsSinceEpoch}';
    final chain = ArrangerChain(
      id: id,
      name: name ?? 'Chain ${_chains.length + 1}',
    );

    _chains[id] = chain;

    // Auto-activate if first chain
    _activeChainId ??= id;

    notifyListeners();
    return chain;
  }

  /// Update a chain
  void updateChain(ArrangerChain chain) {
    _chains[chain.id] = chain;
    notifyListeners();
  }

  /// Delete a chain
  void deleteChain(String chainId) {
    _chains.remove(chainId);
    if (_activeChainId == chainId) {
      _activeChainId = _chains.isNotEmpty ? _chains.keys.first : null;
    }
    notifyListeners();
  }

  /// Set active chain
  void setActiveChain(String? chainId) {
    _activeChainId = chainId;
    _currentEventIndex = 0;
    _currentRepeat = 0;
    notifyListeners();
  }

  /// Add section to chain
  void addSectionToChain(String chainId, String sectionId, {int repeatCount = 1}) {
    final chain = _chains[chainId];
    if (chain == null) return;

    final event = ArrangerEvent(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      sectionId: sectionId,
      repeatCount: repeatCount,
    );

    _chains[chainId] = chain.addEvent(event);
    notifyListeners();
  }

  /// Remove event from chain
  void removeEventFromChain(String chainId, String eventId) {
    final chain = _chains[chainId];
    if (chain == null) return;

    _chains[chainId] = chain.removeEvent(eventId);
    if (_selectedEventId == eventId) _selectedEventId = null;
    notifyListeners();
  }

  /// Move event in chain
  void moveEventInChain(String chainId, String eventId, int newIndex) {
    final chain = _chains[chainId];
    if (chain == null) return;

    _chains[chainId] = chain.moveEvent(eventId, newIndex);
    notifyListeners();
  }

  /// Update event (repeat count, mute)
  void updateEvent(String chainId, ArrangerEvent event) {
    final chain = _chains[chainId];
    if (chain == null) return;

    final events = chain.events.map((e) {
      return e.id == event.id ? event : e;
    }).toList();

    _chains[chainId] = chain.copyWith(events: events);
    notifyListeners();
  }

  /// Select event
  void selectEvent(String? eventId) {
    _selectedEventId = eventId;
    _selectedSectionId = null;
    notifyListeners();
  }

  /// Create chain from current section order
  ArrangerChain createChainFromSections({String? name}) {
    final chain = addChain(name: name);
    final sortedSections = sections;

    for (final section in sortedSections) {
      addSectionToChain(chain.id, section.id);
    }

    return _chains[chain.id]!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Jump to specific event in active chain
  void jumpToEvent(int eventIndex) {
    if (activeChain == null) return;
    if (eventIndex < 0 || eventIndex >= activeChain!.events.length) return;

    _currentEventIndex = eventIndex;
    _currentRepeat = 0;
    notifyListeners();
  }

  /// Jump to section by ID
  void jumpToSection(String sectionId) {
    final chain = activeChain;
    if (chain == null) return;

    for (int i = 0; i < chain.events.length; i++) {
      if (chain.events[i].sectionId == sectionId) {
        jumpToEvent(i);
        return;
      }
    }
  }

  /// Advance to next event (called by playback system)
  void advanceEvent() {
    final chain = activeChain;
    if (chain == null || chain.events.isEmpty) return;

    final currentEvent = chain.events[_currentEventIndex];

    // Check if we need to repeat
    _currentRepeat++;
    if (_currentRepeat < currentEvent.repeatCount) {
      notifyListeners();
      return;
    }

    // Move to next event
    _currentRepeat = 0;

    // Find next non-muted event
    int nextIndex = _currentEventIndex + 1;
    while (nextIndex < chain.events.length && chain.events[nextIndex].muted) {
      nextIndex++;
    }

    if (nextIndex >= chain.events.length) {
      // Loop back to start or stop
      _currentEventIndex = 0;
      _currentRepeat = 0;
    } else {
      _currentEventIndex = nextIndex;
    }

    notifyListeners();
  }

  /// Get current section being played
  ArrangerSection? get currentSection {
    final chain = activeChain;
    if (chain == null || chain.events.isEmpty) return null;
    if (_currentEventIndex >= chain.events.length) return null;

    final event = chain.events[_currentEventIndex];
    return _sections[event.sectionId];
  }

  /// Get playback position info
  ({ArrangerSection? section, int eventIndex, int repeat, int totalEvents}) get playbackInfo {
    return (
      section: currentSection,
      eventIndex: _currentEventIndex,
      repeat: _currentRepeat,
      totalEvents: activeChain?.events.length ?? 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLATTEN CHAIN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Flatten chain to linear arrangement (destructive)
  /// This converts the chain order into actual timeline positions
  List<ArrangerSection> flattenChain(String chainId) {
    final chain = _chains[chainId];
    if (chain == null) return [];

    final result = <ArrangerSection>[];
    int currentBar = 1;

    for (final event in chain.events) {
      if (event.muted) continue;

      final originalSection = _sections[event.sectionId];
      if (originalSection == null) continue;

      for (int i = 0; i < event.repeatCount; i++) {
        final flattenedSection = ArrangerSection(
          id: 'flat_${DateTime.now().millisecondsSinceEpoch}_$i',
          name: originalSection.name,
          type: originalSection.type,
          color: originalSection.color,
          startBar: currentBar,
          lengthBars: originalSection.lengthBars,
          lengthBeats: originalSection.lengthBeats,
          tempo: originalSection.tempo,
        );
        result.add(flattenedSection);
        currentBar += originalSection.lengthBars;
      }
    }

    // Mark chain as flattened
    _chains[chainId] = chain.copyWith(isFlattened: true);
    notifyListeners();

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'visible': _visible,
      'trackHeight': _trackHeight,
      'activeChainId': _activeChainId,
      'sections': _sections.values.map((s) => _sectionToJson(s)).toList(),
      'chains': _chains.values.map((c) => _chainToJson(c)).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? false;
    _visible = json['visible'] ?? true;
    _trackHeight = (json['trackHeight'] ?? 40.0).toDouble();
    _activeChainId = json['activeChainId'];

    _sections.clear();
    _chains.clear();

    if (json['sections'] != null) {
      for (final s in json['sections']) {
        final section = _sectionFromJson(s);
        _sections[section.id] = section;
      }
    }

    if (json['chains'] != null) {
      for (final c in json['chains']) {
        final chain = _chainFromJson(c);
        _chains[chain.id] = chain;
      }
    }

    notifyListeners();
  }

  Map<String, dynamic> _sectionToJson(ArrangerSection s) {
    return {
      'id': s.id,
      'name': s.name,
      'type': s.type.index,
      'color': s.color.toARGB32(),
      'startBar': s.startBar,
      'startBeat': s.startBeat,
      'lengthBars': s.lengthBars,
      'lengthBeats': s.lengthBeats,
      'timeSignatureNumerator': s.timeSignatureNumerator,
      'timeSignatureDenominator': s.timeSignatureDenominator,
      'tempo': s.tempo,
      'notes': s.notes,
    };
  }

  ArrangerSection _sectionFromJson(Map<String, dynamic> json) {
    return ArrangerSection(
      id: json['id'],
      name: json['name'] ?? 'Section',
      type: ArrangerSectionType.values[json['type'] ?? 11],
      color: Color(json['color'] ?? 0xFF4A9EFF),
      startBar: json['startBar'] ?? 1,
      startBeat: json['startBeat'] ?? 1,
      lengthBars: json['lengthBars'] ?? 4,
      lengthBeats: json['lengthBeats'] ?? 0,
      timeSignatureNumerator: json['timeSignatureNumerator'],
      timeSignatureDenominator: json['timeSignatureDenominator'],
      tempo: json['tempo']?.toDouble(),
      notes: json['notes'] ?? '',
    );
  }

  Map<String, dynamic> _chainToJson(ArrangerChain c) {
    return {
      'id': c.id,
      'name': c.name,
      'events': c.events.map((e) => _eventToJson(e)).toList(),
      'isFlattened': c.isFlattened,
    };
  }

  ArrangerChain _chainFromJson(Map<String, dynamic> json) {
    return ArrangerChain(
      id: json['id'],
      name: json['name'] ?? 'Chain',
      events: (json['events'] as List?)?.map((e) => _eventFromJson(e)).toList() ?? [],
      isFlattened: json['isFlattened'] ?? false,
    );
  }

  Map<String, dynamic> _eventToJson(ArrangerEvent e) {
    return {
      'id': e.id,
      'sectionId': e.sectionId,
      'repeatCount': e.repeatCount,
      'muted': e.muted,
    };
  }

  ArrangerEvent _eventFromJson(Map<String, dynamic> json) {
    return ArrangerEvent(
      id: json['id'],
      sectionId: json['sectionId'],
      repeatCount: json['repeatCount'] ?? 1,
      muted: json['muted'] ?? false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _sections.clear();
    _chains.clear();
    _activeChainId = null;
    _currentEventIndex = 0;
    _currentRepeat = 0;
    _enabled = false;
    _selectedSectionId = null;
    _selectedEventId = null;
    _sectionCounts.clear();
    notifyListeners();
  }
}
