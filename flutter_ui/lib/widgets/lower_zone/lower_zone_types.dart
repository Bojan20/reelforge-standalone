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

/// Height of the context bar when expanded (super-tabs + sub-tabs)
const double kContextBarHeight = 60.0;

/// Height of the context bar when collapsed (super-tabs only)
const double kContextBarCollapsedHeight = 32.0;

/// Height of the action strip
const double kActionStripHeight = 36.0;

/// Height of the resize handle
const double kResizeHandleHeight = 4.0;

/// Height of the spin control bar (SlotLab only)
const double kSpinControlBarHeight = 32.0;

/// Height of the slot context bar (Middleware only)
const double kSlotContextBarHeight = 28.0;

/// Animation duration for expand/collapse
const Duration kLowerZoneAnimationDuration = Duration(milliseconds: 200);

// ═══════════════════════════════════════════════════════════════════════════════
// TYPOGRAPHY — P0.1 Font sizes (minimum 10px for accessibility)
// ═══════════════════════════════════════════════════════════════════════════════

class LowerZoneTypography {
  LowerZoneTypography._();

  /// Title/Header size (was 11-12px)
  static const double sizeTitle = 13.0;

  /// Label size (was 9-10px)
  static const double sizeLabel = 11.0;

  /// Value/content size (was 10px)
  static const double sizeValue = 11.0;

  /// Badge/chip size (was 8-9px)
  static const double sizeBadge = 10.0;

  /// Small/muted size (was 8px) — minimum accessible
  static const double sizeSmall = 10.0;

  /// Tiny size for shortcuts (minimum)
  static const double sizeTiny = 9.0;

  // Pre-built TextStyles for consistency
  static const TextStyle title = TextStyle(
    fontSize: sizeTitle,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  static const TextStyle label = TextStyle(
    fontSize: sizeLabel,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle value = TextStyle(
    fontSize: sizeValue,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle badge = TextStyle(
    fontSize: sizeBadge,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle small = TextStyle(
    fontSize: sizeSmall,
    fontWeight: FontWeight.normal,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// COLORS — P0.3 Improved contrast for accessibility (WCAG AA)
// ═══════════════════════════════════════════════════════════════════════════════

class LowerZoneColors {
  LowerZoneColors._();

  // Backgrounds
  static const Color bgDeepest = Color(0xFF0A0A0C);
  static const Color bgDeep = Color(0xFF121216);
  static const Color bgMid = Color(0xFF1A1A20);
  static const Color bgSurface = Color(0xFF242430);

  // Text — P0.3: Improved contrast ratios
  // textPrimary on bgDeep = 15.5:1 ✓
  static const Color textPrimary = Color(0xFFFFFFFF);
  // textSecondary on bgDeep = 7.2:1 ✓ (was 0xFFA0A0B0)
  static const Color textSecondary = Color(0xFFB8B8C8);
  // textTertiary on bgDeep = 4.8:1 ✓ (was 0xFF606070)
  static const Color textTertiary = Color(0xFF808090);
  // textMuted on bgDeep = 4.5:1 ✓ (was 0xFF404050 = 2.4:1)
  static const Color textMuted = Color(0xFF909098);

  // Borders
  static const Color border = Color(0xFF303040);
  static const Color borderSubtle = Color(0xFF252530);

  // Focus indicator — P0.2: For keyboard navigation
  static const Color focusRing = Color(0xFF4A9EFF);
  static const double focusRingWidth = 2.0;

  // Section accents
  static const Color dawAccent = Color(0xFF4A9EFF);      // Blue
  static const Color middlewareAccent = Color(0xFFFF9040); // Orange
  static const Color slotLabAccent = Color(0xFF40C8FF);   // Cyan

  // Status
  static const Color success = Color(0xFF40FF90);
  static const Color warning = Color(0xFFFFD040);  // Slightly more orange for better contrast
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
enum DawEditSubTab { timeline, pianoRoll, fades, grid }
enum DawMixSubTab { mixer, sends, pan, automation }
enum DawProcessSubTab { eq, comp, limiter, fxChain }
enum DawDeliverSubTab { export, stems, bounce, archive }

extension DawBrowseSubTabX on DawBrowseSubTab {
  String get label => ['Files', 'Presets', 'Plugins', 'History'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension DawEditSubTabX on DawEditSubTab {
  String get label => ['Timeline', 'Piano Roll', 'Fades', 'Grid'][index];
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

enum MiddlewareEventsSubTab { browser, editor, triggers, debug }
enum MiddlewareContainersSubTab { random, sequence, blend, switchTab }
enum MiddlewareRoutingSubTab { buses, ducking, matrix, priority }
enum MiddlewareRtpcSubTab { curves, bindings, meters, profiler }
enum MiddlewareDeliverSubTab { bake, soundbank, validate, package }

extension MiddlewareEventsSubTabX on MiddlewareEventsSubTab {
  String get label => ['Browser', 'Editor', 'Triggers', 'Debug'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension MiddlewareContainersSubTabX on MiddlewareContainersSubTab {
  String get label => ['Random', 'Sequence', 'Blend', 'Switch'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension MiddlewareRoutingSubTabX on MiddlewareRoutingSubTab {
  String get label => ['Buses', 'Ducking', 'Matrix', 'Priority'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension MiddlewareRtpcSubTabX on MiddlewareRtpcSubTab {
  String get label => ['Curves', 'Bindings', 'Meters', 'Profiler'][index];
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
enum SlotLabEventsSubTab { folder, editor, layers, pool, auto }
enum SlotLabMixSubTab { buses, sends, pan, meter }
enum SlotLabDspSubTab { chain, eq, comp, reverb }
enum SlotLabBakeSubTab { export, stems, variations, package }

extension SlotLabStagesSubTabX on SlotLabStagesSubTab {
  String get label => ['Trace', 'Timeline', 'Symbols', 'Timing'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
}

extension SlotLabEventsSubTabX on SlotLabEventsSubTab {
  String get label => ['Folder', 'Editor', 'Layers', 'Pool', 'Auto'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T'][index];
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
        eventsSubTab = SlotLabEventsSubTab.values[index.clamp(0, 4)];
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

// ═══════════════════════════════════════════════════════════════════════════════
// P0.2: FOCUS INDICATOR WIDGET — Keyboard navigation support
// ═══════════════════════════════════════════════════════════════════════════════

/// Wrapper that adds focus ring when widget is focused via keyboard
class LowerZoneFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Color? focusColor;
  final BorderRadius? borderRadius;

  const LowerZoneFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.focusColor,
    this.borderRadius,
  });

  @override
  State<LowerZoneFocusable> createState() => _LowerZoneFocusableState();
}

class _LowerZoneFocusableState extends State<LowerZoneFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() => _isFocused = hasFocus);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
            border: _isFocused
                ? Border.all(
                    color: widget.focusColor ?? LowerZoneColors.focusRing,
                    width: LowerZoneColors.focusRingWidth,
                  )
                : null,
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: (widget.focusColor ?? LowerZoneColors.focusRing)
                          .withValues(alpha: 0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P0.4: ERROR STATE WIDGETS — User feedback for failures
// ═══════════════════════════════════════════════════════════════════════════════

/// Error severity levels
enum LowerZoneErrorSeverity { info, warning, error }

/// Inline error banner for panels
class LowerZoneErrorBanner extends StatelessWidget {
  final String message;
  final LowerZoneErrorSeverity severity;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  const LowerZoneErrorBanner({
    super.key,
    required this.message,
    this.severity = LowerZoneErrorSeverity.error,
    this.onDismiss,
    this.onRetry,
  });

  Color get _color => switch (severity) {
        LowerZoneErrorSeverity.info => LowerZoneColors.dawAccent,
        LowerZoneErrorSeverity.warning => LowerZoneColors.warning,
        LowerZoneErrorSeverity.error => LowerZoneColors.error,
      };

  IconData get _icon => switch (severity) {
        LowerZoneErrorSeverity.info => Icons.info_outline,
        LowerZoneErrorSeverity.warning => Icons.warning_amber,
        LowerZoneErrorSeverity.error => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: _color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                color: _color,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: LowerZoneTypography.sizeBadge,
                    fontWeight: FontWeight.bold,
                    color: _color,
                  ),
                ),
              ),
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: _color),
            ),
          ],
        ],
      ),
    );
  }
}

/// Empty state placeholder with optional action
class LowerZoneEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accentColor;

  const LowerZoneEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.actionLabel,
    this.onAction,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? LowerZoneColors.textMuted;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: color.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: LowerZoneTypography.sizeTitle,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                color: LowerZoneColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: LowerZoneTypography.sizeLabel,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading state placeholder
class LowerZoneLoadingState extends StatelessWidget {
  final String? message;
  final Color? accentColor;

  const LowerZoneLoadingState({
    super.key,
    this.message,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? LowerZoneColors.dawAccent;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                color: LowerZoneColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P1.1: DRAG-AND-DROP WIDGETS — File/Audio drag support
// ═══════════════════════════════════════════════════════════════════════════════

/// Data transferred during drag operations
class LowerZoneDragData {
  final String type; // 'audio', 'preset', 'event', 'plugin'
  final String path;
  final String name;
  final Map<String, dynamic>? metadata;

  const LowerZoneDragData({
    required this.type,
    required this.path,
    required this.name,
    this.metadata,
  });
}

/// Draggable item wrapper for lists
class LowerZoneDraggable extends StatelessWidget {
  final Widget child;
  final LowerZoneDragData data;
  final Widget? feedback;
  final Color? accentColor;

  const LowerZoneDraggable({
    super.key,
    required this.child,
    required this.data,
    this.feedback,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<LowerZoneDragData>(
      data: data,
      feedback: feedback ?? _buildDefaultFeedback(),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }

  Widget _buildDefaultFeedback() {
    final color = accentColor ?? LowerZoneColors.dawAccent;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForType(data.type),
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              data.name,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'audio' => Icons.audio_file,
      'preset' => Icons.tune,
      'event' => Icons.music_note,
      'plugin' => Icons.extension,
      _ => Icons.insert_drive_file,
    };
  }
}

/// Drop target wrapper
class LowerZoneDropTarget extends StatefulWidget {
  final Widget child;
  final List<String> acceptedTypes; // e.g., ['audio', 'preset']
  final void Function(LowerZoneDragData data)? onAccept;
  final Color? accentColor;
  final String? hintText;

  const LowerZoneDropTarget({
    super.key,
    required this.child,
    required this.acceptedTypes,
    this.onAccept,
    this.accentColor,
    this.hintText,
  });

  @override
  State<LowerZoneDropTarget> createState() => _LowerZoneDropTargetState();
}

class _LowerZoneDropTargetState extends State<LowerZoneDropTarget> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? LowerZoneColors.dawAccent;

    return DragTarget<LowerZoneDragData>(
      onWillAcceptWithDetails: (details) {
        final willAccept = widget.acceptedTypes.contains(details.data.type);
        if (willAccept && !_isDragOver) {
          setState(() => _isDragOver = true);
        }
        return willAccept;
      },
      onLeave: (_) {
        setState(() => _isDragOver = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isDragOver = false);
        widget.onAccept?.call(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: _isDragOver
                ? Border.all(color: color, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            color: _isDragOver
                ? color.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: Stack(
            children: [
              widget.child,
              if (_isDragOver && widget.hintText != null)
                Positioned.fill(
                  child: Container(
                    color: LowerZoneColors.bgDeep.withValues(alpha: 0.8),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline, size: 32, color: color),
                          const SizedBox(height: 8),
                          Text(
                            widget.hintText!,
                            style: TextStyle(
                              fontSize: LowerZoneTypography.sizeLabel,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P1.3: CONTEXT MENU WIDGET — Right-click menu support
// ═══════════════════════════════════════════════════════════════════════════════

/// Context menu action
class LowerZoneContextAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isDividerBefore;

  const LowerZoneContextAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.isDestructive = false,
    this.isDividerBefore = false,
  });
}

/// Wrapper that shows context menu on right-click
class LowerZoneContextMenu extends StatelessWidget {
  final Widget child;
  final List<LowerZoneContextAction> actions;
  final Color? accentColor;

  const LowerZoneContextMenu({
    super.key,
    required this.child,
    required this.actions,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      onLongPress: () {
        // For touch devices
        final box = context.findRenderObject() as RenderBox;
        final position = box.localToGlobal(Offset.zero);
        _showContextMenu(context, position + const Offset(20, 20));
      },
      child: child,
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final color = accentColor ?? LowerZoneColors.dawAccent;

    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: LowerZoneColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: LowerZoneColors.border),
      ),
      items: actions.map((action) {
        return PopupMenuItem<void>(
          onTap: action.onTap,
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: action.isDividerBefore
                ? const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: LowerZoneColors.border),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 16,
                  color: action.isDestructive
                      ? LowerZoneColors.error
                      : action.onTap != null
                          ? color
                          : LowerZoneColors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: LowerZoneTypography.sizeLabel,
                    color: action.isDestructive
                        ? LowerZoneColors.error
                        : action.onTap != null
                            ? LowerZoneColors.textPrimary
                            : LowerZoneColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Pre-defined context menu actions
class LowerZoneContextActions {
  /// Audio file context menu
  static List<LowerZoneContextAction> forAudioFile({
    VoidCallback? onPlay,
    VoidCallback? onAddToTimeline,
    VoidCallback? onAddToEvent,
    VoidCallback? onShowInFinder,
    VoidCallback? onDelete,
  }) => [
    LowerZoneContextAction(label: 'Play', icon: Icons.play_arrow, onTap: onPlay),
    LowerZoneContextAction(label: 'Add to Timeline', icon: Icons.add_to_queue, onTap: onAddToTimeline),
    LowerZoneContextAction(label: 'Add to Event', icon: Icons.music_note, onTap: onAddToEvent),
    LowerZoneContextAction(label: 'Show in Finder', icon: Icons.folder_open, onTap: onShowInFinder, isDividerBefore: true),
    LowerZoneContextAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true, isDividerBefore: true),
  ];

  /// Event context menu
  static List<LowerZoneContextAction> forEvent({
    VoidCallback? onPlay,
    VoidCallback? onEdit,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
  }) => [
    LowerZoneContextAction(label: 'Play', icon: Icons.play_arrow, onTap: onPlay),
    LowerZoneContextAction(label: 'Edit', icon: Icons.edit, onTap: onEdit),
    LowerZoneContextAction(label: 'Duplicate', icon: Icons.copy, onTap: onDuplicate, isDividerBefore: true),
    LowerZoneContextAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true, isDividerBefore: true),
  ];

  /// Container context menu
  static List<LowerZoneContextAction> forContainer({
    VoidCallback? onTest,
    VoidCallback? onEdit,
    VoidCallback? onDuplicate,
    VoidCallback? onExport,
    VoidCallback? onDelete,
  }) => [
    LowerZoneContextAction(label: 'Test', icon: Icons.play_arrow, onTap: onTest),
    LowerZoneContextAction(label: 'Edit', icon: Icons.edit, onTap: onEdit),
    LowerZoneContextAction(label: 'Duplicate', icon: Icons.copy, onTap: onDuplicate, isDividerBefore: true),
    LowerZoneContextAction(label: 'Export Preset', icon: Icons.upload, onTap: onExport),
    LowerZoneContextAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true, isDividerBefore: true),
  ];
}
