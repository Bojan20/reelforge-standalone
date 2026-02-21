/// Mixer View Models — Pro Tools 2026-class mixer view state
///
/// Enums and state classes for MixerScreen layout, strip width,
/// section visibility, and view presets.

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

/// Strip width mode — controls channel strip pixel width
enum StripWidthMode {
  narrow, // 56px — compact overview, more strips visible
  regular; // 90px — standard working width

  double get pixelWidth => switch (this) {
    StripWidthMode.narrow => 56.0,
    StripWidthMode.regular => 90.0,
  };

  String get label => switch (this) {
    StripWidthMode.narrow => 'N',
    StripWidthMode.regular => 'R',
  };
}

/// Mixer section — groups of strips in the mixer
enum MixerSection {
  tracks,
  buses,
  auxes,
  vcas,
  master;

  String get label => switch (this) {
    MixerSection.tracks => 'TRACKS',
    MixerSection.buses => 'BUSES',
    MixerSection.auxes => 'AUX',
    MixerSection.vcas => 'VCA',
    MixerSection.master => 'MASTER',
  };

  String get shortLabel => switch (this) {
    MixerSection.tracks => 'TRK',
    MixerSection.buses => 'BUS',
    MixerSection.auxes => 'AUX',
    MixerSection.vcas => 'VCA',
    MixerSection.master => 'MST',
  };
}

/// Metering mode for the mixer
enum MixerMeteringMode {
  peak,
  rms,
  lufs;

  String get label => switch (this) {
    MixerMeteringMode.peak => 'Peak',
    MixerMeteringMode.rms => 'RMS',
    MixerMeteringMode.lufs => 'LUFS',
  };
}

/// App-level view mode — controls center zone content
enum AppViewMode {
  edit,  // Standard DAW layout (timeline + lower zone)
  mixer; // Dedicated full-height mixer (MixerScreen)

  String get label => switch (this) {
    AppViewMode.edit => 'Edit',
    AppViewMode.mixer => 'Mix',
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// VIEW STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Mixer view state — persisted across Edit↔Mixer toggles
class MixerViewState {
  final double scrollOffset;
  final Set<MixerSection> visibleSections;
  final StripWidthMode stripWidthMode;
  final MixerMeteringMode meteringMode;
  final String? spillTargetId;
  final String filterQuery;

  const MixerViewState({
    this.scrollOffset = 0.0,
    this.visibleSections = const {
      MixerSection.tracks,
      MixerSection.buses,
      MixerSection.auxes,
      MixerSection.vcas,
      MixerSection.master,
    },
    this.stripWidthMode = StripWidthMode.regular,
    this.meteringMode = MixerMeteringMode.peak,
    this.spillTargetId,
    this.filterQuery = '',
  });

  MixerViewState copyWith({
    double? scrollOffset,
    Set<MixerSection>? visibleSections,
    StripWidthMode? stripWidthMode,
    MixerMeteringMode? meteringMode,
    String? spillTargetId,
    String? filterQuery,
  }) => MixerViewState(
    scrollOffset: scrollOffset ?? this.scrollOffset,
    visibleSections: visibleSections ?? this.visibleSections,
    stripWidthMode: stripWidthMode ?? this.stripWidthMode,
    meteringMode: meteringMode ?? this.meteringMode,
    spillTargetId: spillTargetId ?? this.spillTargetId,
    filterQuery: filterQuery ?? this.filterQuery,
  );

  bool isSectionVisible(MixerSection section) =>
      visibleSections.contains(section);

  Map<String, dynamic> toJson() => {
    'scrollOffset': scrollOffset,
    'visibleSections': visibleSections.map((s) => s.name).toList(),
    'stripWidthMode': stripWidthMode.name,
    'meteringMode': meteringMode.name,
    'filterQuery': filterQuery,
  };

  factory MixerViewState.fromJson(Map<String, dynamic> json) {
    return MixerViewState(
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      visibleSections: (json['visibleSections'] as List<dynamic>?)
          ?.map((s) => MixerSection.values.firstWhere(
                (v) => v.name == s,
                orElse: () => MixerSection.tracks,
              ))
          .toSet() ?? const {
        MixerSection.tracks,
        MixerSection.buses,
        MixerSection.auxes,
        MixerSection.vcas,
        MixerSection.master,
      },
      stripWidthMode: StripWidthMode.values.firstWhere(
        (v) => v.name == json['stripWidthMode'],
        orElse: () => StripWidthMode.regular,
      ),
      meteringMode: MixerMeteringMode.values.firstWhere(
        (v) => v.name == json['meteringMode'],
        orElse: () => MixerMeteringMode.peak,
      ),
      filterQuery: json['filterQuery'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MixerViewState &&
          runtimeType == other.runtimeType &&
          scrollOffset == other.scrollOffset &&
          setEquals(visibleSections, other.visibleSections) &&
          stripWidthMode == other.stripWidthMode &&
          meteringMode == other.meteringMode &&
          spillTargetId == other.spillTargetId &&
          filterQuery == other.filterQuery;

  @override
  int get hashCode => Object.hash(
    scrollOffset,
    Object.hashAll(visibleSections.toList()..sort((a, b) => a.index.compareTo(b.index))),
    stripWidthMode,
    meteringMode,
    spillTargetId,
    filterQuery,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// VIEW PRESETS
// ═══════════════════════════════════════════════════════════════════════════

/// Named mixer view preset
class MixerViewPreset {
  final String name;
  final Set<MixerSection> visibleSections;
  final StripWidthMode stripWidth;

  const MixerViewPreset({
    required this.name,
    required this.visibleSections,
    this.stripWidth = StripWidthMode.regular,
  });

  static const all = MixerViewPreset(
    name: 'All',
    visibleSections: {
      MixerSection.tracks,
      MixerSection.buses,
      MixerSection.auxes,
      MixerSection.vcas,
      MixerSection.master,
    },
  );

  static const tracksOnly = MixerViewPreset(
    name: 'Tracks Only',
    visibleSections: {MixerSection.tracks, MixerSection.master},
  );

  static const busesOnly = MixerViewPreset(
    name: 'Buses Only',
    visibleSections: {MixerSection.buses, MixerSection.master},
  );

  static const routing = MixerViewPreset(
    name: 'Routing',
    visibleSections: {
      MixerSection.buses,
      MixerSection.auxes,
      MixerSection.master,
    },
  );

  static const compact = MixerViewPreset(
    name: 'Compact',
    visibleSections: {
      MixerSection.tracks,
      MixerSection.buses,
      MixerSection.auxes,
      MixerSection.vcas,
      MixerSection.master,
    },
    stripWidth: StripWidthMode.narrow,
  );

  static const List<MixerViewPreset> builtIn = [
    all,
    tracksOnly,
    busesOnly,
    routing,
    compact,
  ];
}
