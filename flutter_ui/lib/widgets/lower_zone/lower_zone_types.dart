// Lower Zone Types — Section-Specific Type Definitions
//
// Each section (DAW, Middleware, SlotLab) has its OWN Lower Zone
// with completely independent tabs, state, and content.
//
// Based on LOWER_ZONE_ARCHITECTURE.md

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Minimum height of the lower zone content area
const double kLowerZoneMinHeight = 150.0;

/// Maximum height of the lower zone content area
const double kLowerZoneMaxHeight = 600.0;

/// Default height of the lower zone content area (maximum by default)
const double kLowerZoneDefaultHeight = 500.0;

/// Height of the context bar (super-tabs + sub-tabs)
const double kContextBarHeight = 60.0;

/// Height of the action strip
const double kActionStripHeight = 36.0;

/// Animation duration for expand/collapse
const Duration kLowerZoneAnimationDuration = Duration(milliseconds: 200);

// ═══════════════════════════════════════════════════════════════════════════════
// COLORS
// ═══════════════════════════════════════════════════════════════════════════════

class LowerZoneColors {
  LowerZoneColors._();

  // Backgrounds
  static const Color bgDeepest = Color(0xFF0A0A0C);
  static const Color bgDeep = Color(0xFF121216);
  static const Color bgMid = Color(0xFF1A1A20);
  static const Color bgSurface = Color(0xFF242430);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA0A0B0);
  static const Color textTertiary = Color(0xFF606070);
  static const Color textMuted = Color(0xFF404050);

  // Borders
  static const Color border = Color(0xFF242430);
  static const Color borderSubtle = Color(0xFF1A1A20);

  // Section accents
  static const Color dawAccent = Color(0xFF4A9EFF);      // Blue
  static const Color middlewareAccent = Color(0xFFFF9040); // Orange
  static const Color slotLabAccent = Color(0xFF40C8FF);   // Cyan

  // Status
  static const Color success = Color(0xFF40FF90);
  static const Color warning = Color(0xFFFFFF40);
  static const Color error = Color(0xFFFF4060);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
//
//  DAW LOWER ZONE — Timeline-based audio production
//
// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════

/// DAW Super-tabs: BROWSE, EDIT, MIX, PROCESS, DELIVER
enum DawSuperTab { browse, edit, mix, process, deliver }

extension DawSuperTabX on DawSuperTab {
  String get label => ['BROWSE', 'EDIT', 'MIX', 'PROCESS', 'DELIVER'][index];
  IconData get icon => [Icons.folder_open, Icons.content_cut, Icons.tune, Icons.equalizer, Icons.upload][index];
  String get shortcut => '${index + 1}';
  Color get color => LowerZoneColors.dawAccent;
}

// --- DAW Sub-tabs ---

enum DawBrowseSubTab { files, presets, plugins, history }
enum DawEditSubTab { timeline, clips, fades, grid }
enum DawMixSubTab { mixer, sends, pan, automation }
enum DawProcessSubTab { eq, comp, limiter, fxChain }
enum DawDeliverSubTab { export, stems, bounce, archive }

extension DawBrowseSubTabX on DawBrowseSubTab {
  String get label => ['Files', 'Presets', 'Plugins', 'History'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension DawEditSubTabX on DawEditSubTab {
  String get label => ['Timeline', 'Clips', 'Fades', 'Grid'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension DawMixSubTabX on DawMixSubTab {
  String get label => ['Mixer', 'Sends', 'Pan', 'Auto'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension DawProcessSubTabX on DawProcessSubTab {
  String get label => ['EQ', 'Comp', 'Limiter', 'FX Chain'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension DawDeliverSubTabX on DawDeliverSubTab {
  String get label => ['Export', 'Stems', 'Bounce', 'Archive'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

/// Complete DAW Lower Zone state
class DawLowerZoneState {
  DawSuperTab superTab;
  DawBrowseSubTab browseSubTab;
  DawEditSubTab editSubTab;
  DawMixSubTab mixSubTab;
  DawProcessSubTab processSubTab;
  DawDeliverSubTab deliverSubTab;
  bool isExpanded;
  double height;

  DawLowerZoneState({
    this.superTab = DawSuperTab.edit,
    this.browseSubTab = DawBrowseSubTab.files,
    this.editSubTab = DawEditSubTab.timeline,
    this.mixSubTab = DawMixSubTab.mixer,
    this.processSubTab = DawProcessSubTab.eq,
    this.deliverSubTab = DawDeliverSubTab.export,
    this.isExpanded = true,
    this.height = kLowerZoneDefaultHeight,
  });

  /// Get current sub-tab index for active super-tab
  int get currentSubTabIndex => switch (superTab) {
    DawSuperTab.browse => browseSubTab.index,
    DawSuperTab.edit => editSubTab.index,
    DawSuperTab.mix => mixSubTab.index,
    DawSuperTab.process => processSubTab.index,
    DawSuperTab.deliver => deliverSubTab.index,
  };

  /// Set sub-tab by index for active super-tab
  void setSubTabIndex(int index) {
    switch (superTab) {
      case DawSuperTab.browse:
        browseSubTab = DawBrowseSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.edit:
        editSubTab = DawEditSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.mix:
        mixSubTab = DawMixSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.process:
        processSubTab = DawProcessSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.deliver:
        deliverSubTab = DawDeliverSubTab.values[index.clamp(0, 3)];
    }
  }

  /// Get sub-tab labels for active super-tab
  List<String> get subTabLabels => switch (superTab) {
    DawSuperTab.browse => DawBrowseSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.edit => DawEditSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.mix => DawMixSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.process => DawProcessSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.deliver => DawDeliverSubTab.values.map((e) => e.label).toList(),
  };

  DawLowerZoneState copyWith({
    DawSuperTab? superTab,
    DawBrowseSubTab? browseSubTab,
    DawEditSubTab? editSubTab,
    DawMixSubTab? mixSubTab,
    DawProcessSubTab? processSubTab,
    DawDeliverSubTab? deliverSubTab,
    bool? isExpanded,
    double? height,
  }) {
    return DawLowerZoneState(
      superTab: superTab ?? this.superTab,
      browseSubTab: browseSubTab ?? this.browseSubTab,
      editSubTab: editSubTab ?? this.editSubTab,
      mixSubTab: mixSubTab ?? this.mixSubTab,
      processSubTab: processSubTab ?? this.processSubTab,
      deliverSubTab: deliverSubTab ?? this.deliverSubTab,
      isExpanded: isExpanded ?? this.isExpanded,
      height: height ?? this.height,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'superTab': superTab.index,
    'browseSubTab': browseSubTab.index,
    'editSubTab': editSubTab.index,
    'mixSubTab': mixSubTab.index,
    'processSubTab': processSubTab.index,
    'deliverSubTab': deliverSubTab.index,
    'isExpanded': isExpanded,
    'height': height,
  };

  /// Deserialize from JSON
  factory DawLowerZoneState.fromJson(Map<String, dynamic> json) {
    return DawLowerZoneState(
      superTab: DawSuperTab.values[json['superTab'] as int? ?? 1],
      browseSubTab: DawBrowseSubTab.values[json['browseSubTab'] as int? ?? 0],
      editSubTab: DawEditSubTab.values[json['editSubTab'] as int? ?? 0],
      mixSubTab: DawMixSubTab.values[json['mixSubTab'] as int? ?? 0],
      processSubTab: DawProcessSubTab.values[json['processSubTab'] as int? ?? 0],
      deliverSubTab: DawDeliverSubTab.values[json['deliverSubTab'] as int? ?? 0],
      isExpanded: json['isExpanded'] as bool? ?? true,
      height: (json['height'] as num?)?.toDouble() ?? kLowerZoneDefaultHeight,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
//
//  MIDDLEWARE LOWER ZONE — Wwise/FMOD-style event logic
//
// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════

/// Middleware Super-tabs: EVENTS, CONTAINERS, ROUTING, RTPC, DELIVER
enum MiddlewareSuperTab { events, containers, routing, rtpc, deliver }

extension MiddlewareSuperTabX on MiddlewareSuperTab {
  String get label => ['EVENTS', 'CONTAINERS', 'ROUTING', 'RTPC', 'DELIVER'][index];
  IconData get icon => [Icons.music_note, Icons.inventory_2, Icons.alt_route, Icons.show_chart, Icons.local_fire_department][index];
  String get shortcut => '${index + 1}';
  Color get color => LowerZoneColors.middlewareAccent;
}

// --- Middleware Sub-tabs ---

enum MiddlewareEventsSubTab { browser, editor, triggers, actions }
enum MiddlewareContainersSubTab { random, sequence, blend, switchTab }
enum MiddlewareRoutingSubTab { buses, ducking, matrix, spatial }
enum MiddlewareRtpcSubTab { curves, bindings, meters, debug }
enum MiddlewareDeliverSubTab { bake, soundbank, validate, package }

extension MiddlewareEventsSubTabX on MiddlewareEventsSubTab {
  String get label => ['Browser', 'Editor', 'Triggers', 'Actions'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension MiddlewareContainersSubTabX on MiddlewareContainersSubTab {
  String get label => ['Random', 'Sequence', 'Blend', 'Switch'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension MiddlewareRoutingSubTabX on MiddlewareRoutingSubTab {
  String get label => ['Buses', 'Ducking', 'Matrix', 'Spatial'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension MiddlewareRtpcSubTabX on MiddlewareRtpcSubTab {
  String get label => ['Curves', 'Bindings', 'Meters', 'Debug'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension MiddlewareDeliverSubTabX on MiddlewareDeliverSubTab {
  String get label => ['Bake', 'Soundbank', 'Validate', 'Package'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

/// Complete Middleware Lower Zone state
class MiddlewareLowerZoneState {
  MiddlewareSuperTab superTab;
  MiddlewareEventsSubTab eventsSubTab;
  MiddlewareContainersSubTab containersSubTab;
  MiddlewareRoutingSubTab routingSubTab;
  MiddlewareRtpcSubTab rtpcSubTab;
  MiddlewareDeliverSubTab deliverSubTab;
  bool isExpanded;
  double height;

  MiddlewareLowerZoneState({
    this.superTab = MiddlewareSuperTab.events,
    this.eventsSubTab = MiddlewareEventsSubTab.browser,
    this.containersSubTab = MiddlewareContainersSubTab.random,
    this.routingSubTab = MiddlewareRoutingSubTab.buses,
    this.rtpcSubTab = MiddlewareRtpcSubTab.curves,
    this.deliverSubTab = MiddlewareDeliverSubTab.bake,
    this.isExpanded = true,
    this.height = kLowerZoneDefaultHeight,
  });

  int get currentSubTabIndex => switch (superTab) {
    MiddlewareSuperTab.events => eventsSubTab.index,
    MiddlewareSuperTab.containers => containersSubTab.index,
    MiddlewareSuperTab.routing => routingSubTab.index,
    MiddlewareSuperTab.rtpc => rtpcSubTab.index,
    MiddlewareSuperTab.deliver => deliverSubTab.index,
  };

  void setSubTabIndex(int index) {
    switch (superTab) {
      case MiddlewareSuperTab.events:
        eventsSubTab = MiddlewareEventsSubTab.values[index.clamp(0, 3)];
      case MiddlewareSuperTab.containers:
        containersSubTab = MiddlewareContainersSubTab.values[index.clamp(0, 3)];
      case MiddlewareSuperTab.routing:
        routingSubTab = MiddlewareRoutingSubTab.values[index.clamp(0, 3)];
      case MiddlewareSuperTab.rtpc:
        rtpcSubTab = MiddlewareRtpcSubTab.values[index.clamp(0, 3)];
      case MiddlewareSuperTab.deliver:
        deliverSubTab = MiddlewareDeliverSubTab.values[index.clamp(0, 3)];
    }
  }

  List<String> get subTabLabels => switch (superTab) {
    MiddlewareSuperTab.events => MiddlewareEventsSubTab.values.map((e) => e.label).toList(),
    MiddlewareSuperTab.containers => MiddlewareContainersSubTab.values.map((e) => e.label).toList(),
    MiddlewareSuperTab.routing => MiddlewareRoutingSubTab.values.map((e) => e.label).toList(),
    MiddlewareSuperTab.rtpc => MiddlewareRtpcSubTab.values.map((e) => e.label).toList(),
    MiddlewareSuperTab.deliver => MiddlewareDeliverSubTab.values.map((e) => e.label).toList(),
  };

  MiddlewareLowerZoneState copyWith({
    MiddlewareSuperTab? superTab,
    MiddlewareEventsSubTab? eventsSubTab,
    MiddlewareContainersSubTab? containersSubTab,
    MiddlewareRoutingSubTab? routingSubTab,
    MiddlewareRtpcSubTab? rtpcSubTab,
    MiddlewareDeliverSubTab? deliverSubTab,
    bool? isExpanded,
    double? height,
  }) {
    return MiddlewareLowerZoneState(
      superTab: superTab ?? this.superTab,
      eventsSubTab: eventsSubTab ?? this.eventsSubTab,
      containersSubTab: containersSubTab ?? this.containersSubTab,
      routingSubTab: routingSubTab ?? this.routingSubTab,
      rtpcSubTab: rtpcSubTab ?? this.rtpcSubTab,
      deliverSubTab: deliverSubTab ?? this.deliverSubTab,
      isExpanded: isExpanded ?? this.isExpanded,
      height: height ?? this.height,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'superTab': superTab.index,
    'eventsSubTab': eventsSubTab.index,
    'containersSubTab': containersSubTab.index,
    'routingSubTab': routingSubTab.index,
    'rtpcSubTab': rtpcSubTab.index,
    'deliverSubTab': deliverSubTab.index,
    'isExpanded': isExpanded,
    'height': height,
  };

  /// Deserialize from JSON
  factory MiddlewareLowerZoneState.fromJson(Map<String, dynamic> json) {
    return MiddlewareLowerZoneState(
      superTab: MiddlewareSuperTab.values[json['superTab'] as int? ?? 0],
      eventsSubTab: MiddlewareEventsSubTab.values[json['eventsSubTab'] as int? ?? 0],
      containersSubTab: MiddlewareContainersSubTab.values[json['containersSubTab'] as int? ?? 0],
      routingSubTab: MiddlewareRoutingSubTab.values[json['routingSubTab'] as int? ?? 0],
      rtpcSubTab: MiddlewareRtpcSubTab.values[json['rtpcSubTab'] as int? ?? 0],
      deliverSubTab: MiddlewareDeliverSubTab.values[json['deliverSubTab'] as int? ?? 0],
      isExpanded: json['isExpanded'] as bool? ?? true,
      height: (json['height'] as num?)?.toDouble() ?? kLowerZoneDefaultHeight,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
//
//  SLOTLAB LOWER ZONE — Synthetic slot engine testing
//
// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════

/// SlotLab Super-tabs: STAGES, EVENTS, MIX, DSP, BAKE
enum SlotLabSuperTab { stages, events, mix, dsp, bake }

extension SlotLabSuperTabX on SlotLabSuperTab {
  String get label => ['STAGES', 'EVENTS', 'MIX', 'DSP', 'BAKE'][index];
  IconData get icon => [Icons.theaters, Icons.music_note, Icons.tune, Icons.graphic_eq, Icons.local_fire_department][index];
  String get shortcut => '${index + 1}';
  Color get color => LowerZoneColors.slotLabAccent;
}

// --- SlotLab Sub-tabs ---

enum SlotLabStagesSubTab { trace, timeline, symbols, timing }
enum SlotLabEventsSubTab { folder, editor, layers, pool }
enum SlotLabMixSubTab { buses, sends, pan, meter }
enum SlotLabDspSubTab { chain, eq, comp, reverb }
enum SlotLabBakeSubTab { export, stems, variations, package }

extension SlotLabStagesSubTabX on SlotLabStagesSubTab {
  String get label => ['Trace', 'Timeline', 'Symbols', 'Timing'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension SlotLabEventsSubTabX on SlotLabEventsSubTab {
  String get label => ['Folder', 'Editor', 'Layers', 'Pool'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension SlotLabMixSubTabX on SlotLabMixSubTab {
  String get label => ['Buses', 'Sends', 'Pan', 'Meter'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension SlotLabDspSubTabX on SlotLabDspSubTab {
  String get label => ['Chain', 'EQ', 'Comp', 'Reverb'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension SlotLabBakeSubTabX on SlotLabBakeSubTab {
  String get label => ['Export', 'Stems', 'Variations', 'Package'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

/// Complete SlotLab Lower Zone state
class SlotLabLowerZoneState {
  SlotLabSuperTab superTab;
  SlotLabStagesSubTab stagesSubTab;
  SlotLabEventsSubTab eventsSubTab;
  SlotLabMixSubTab mixSubTab;
  SlotLabDspSubTab dspSubTab;
  SlotLabBakeSubTab bakeSubTab;
  bool isExpanded;
  double height;

  SlotLabLowerZoneState({
    this.superTab = SlotLabSuperTab.stages,
    this.stagesSubTab = SlotLabStagesSubTab.trace,
    this.eventsSubTab = SlotLabEventsSubTab.folder,
    this.mixSubTab = SlotLabMixSubTab.buses,
    this.dspSubTab = SlotLabDspSubTab.chain,
    this.bakeSubTab = SlotLabBakeSubTab.export,
    this.isExpanded = true,
    this.height = kLowerZoneDefaultHeight,
  });

  int get currentSubTabIndex => switch (superTab) {
    SlotLabSuperTab.stages => stagesSubTab.index,
    SlotLabSuperTab.events => eventsSubTab.index,
    SlotLabSuperTab.mix => mixSubTab.index,
    SlotLabSuperTab.dsp => dspSubTab.index,
    SlotLabSuperTab.bake => bakeSubTab.index,
  };

  void setSubTabIndex(int index) {
    switch (superTab) {
      case SlotLabSuperTab.stages:
        stagesSubTab = SlotLabStagesSubTab.values[index.clamp(0, 3)];
      case SlotLabSuperTab.events:
        eventsSubTab = SlotLabEventsSubTab.values[index.clamp(0, 3)];
      case SlotLabSuperTab.mix:
        mixSubTab = SlotLabMixSubTab.values[index.clamp(0, 3)];
      case SlotLabSuperTab.dsp:
        dspSubTab = SlotLabDspSubTab.values[index.clamp(0, 3)];
      case SlotLabSuperTab.bake:
        bakeSubTab = SlotLabBakeSubTab.values[index.clamp(0, 3)];
    }
  }

  List<String> get subTabLabels => switch (superTab) {
    SlotLabSuperTab.stages => SlotLabStagesSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.events => SlotLabEventsSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.mix => SlotLabMixSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.dsp => SlotLabDspSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.bake => SlotLabBakeSubTab.values.map((e) => e.label).toList(),
  };

  SlotLabLowerZoneState copyWith({
    SlotLabSuperTab? superTab,
    SlotLabStagesSubTab? stagesSubTab,
    SlotLabEventsSubTab? eventsSubTab,
    SlotLabMixSubTab? mixSubTab,
    SlotLabDspSubTab? dspSubTab,
    SlotLabBakeSubTab? bakeSubTab,
    bool? isExpanded,
    double? height,
  }) {
    return SlotLabLowerZoneState(
      superTab: superTab ?? this.superTab,
      stagesSubTab: stagesSubTab ?? this.stagesSubTab,
      eventsSubTab: eventsSubTab ?? this.eventsSubTab,
      mixSubTab: mixSubTab ?? this.mixSubTab,
      dspSubTab: dspSubTab ?? this.dspSubTab,
      bakeSubTab: bakeSubTab ?? this.bakeSubTab,
      isExpanded: isExpanded ?? this.isExpanded,
      height: height ?? this.height,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'superTab': superTab.index,
    'stagesSubTab': stagesSubTab.index,
    'eventsSubTab': eventsSubTab.index,
    'mixSubTab': mixSubTab.index,
    'dspSubTab': dspSubTab.index,
    'bakeSubTab': bakeSubTab.index,
    'isExpanded': isExpanded,
    'height': height,
  };

  /// Deserialize from JSON
  factory SlotLabLowerZoneState.fromJson(Map<String, dynamic> json) {
    return SlotLabLowerZoneState(
      superTab: SlotLabSuperTab.values[json['superTab'] as int? ?? 0],
      stagesSubTab: SlotLabStagesSubTab.values[json['stagesSubTab'] as int? ?? 0],
      eventsSubTab: SlotLabEventsSubTab.values[json['eventsSubTab'] as int? ?? 0],
      mixSubTab: SlotLabMixSubTab.values[json['mixSubTab'] as int? ?? 0],
      dspSubTab: SlotLabDspSubTab.values[json['dspSubTab'] as int? ?? 0],
      bakeSubTab: SlotLabBakeSubTab.values[json['bakeSubTab'] as int? ?? 0],
      isExpanded: json['isExpanded'] as bool? ?? true,
      height: (json['height'] as num?)?.toDouble() ?? kLowerZoneDefaultHeight,
    );
  }
}
