/// Editor Mode Layout Configuration
///
/// Defines layout differences between DAW and Middleware modes.
/// 1:1 migration from React editorModeConfig.ts
///
/// DAW Mode:
/// - Timeline-centric editing
/// - Full mixer in lower zone
/// - Audio clip editing focus
/// - Transport bar prominent
/// - Default tab: Mixer
///
/// Middleware Mode:
/// - Event-centric editing
/// - Routing and states focus
/// - Game integration tools
/// - Console/debug prominent
/// - Default tab: Slot Studio

import 'layout_models.dart' show EditorMode;

// ============ Types ============

/// Lower zone configuration per editor mode
class LowerZoneConfig {
  /// Default active tab ID
  final String defaultTab;

  /// Tab groups to show (by group ID)
  final List<String> visibleGroups;

  /// Individual tabs to hide (even if group visible)
  final List<String> hiddenTabs;

  /// Priority order for tab groups (leftmost first)
  final List<String> groupOrder;

  const LowerZoneConfig({
    required this.defaultTab,
    required this.visibleGroups,
    this.hiddenTabs = const [],
    required this.groupOrder,
  });
}

/// Left zone configuration per editor mode
class LeftZoneConfig {
  /// Default expanded folders
  final List<String> defaultExpanded;

  /// Folder visibility
  final List<String> visibleFolders;

  const LeftZoneConfig({
    required this.defaultExpanded,
    required this.visibleFolders,
  });
}

/// Right zone configuration per editor mode
class RightZoneConfig {
  /// Default inspector mode
  final String defaultType;

  /// Available section presets
  final List<String> sectionPresets;

  const RightZoneConfig({
    required this.defaultType,
    required this.sectionPresets,
  });
}

/// Feature flags per editor mode
class EditorModeFeatures {
  final bool showTransport;
  final bool showTempo;
  final bool showTimecode;
  final bool showMusicLayers;
  final bool showSlotTools;
  final bool showGameSync;

  const EditorModeFeatures({
    this.showTransport = true,
    this.showTempo = true,
    this.showTimecode = true,
    this.showMusicLayers = false,
    this.showSlotTools = false,
    this.showGameSync = false,
  });
}

/// Complete layout configuration for an editor mode
class EditorModeLayoutConfig {
  final EditorMode mode;
  final LowerZoneConfig lowerZone;
  final LeftZoneConfig leftZone;
  final RightZoneConfig rightZone;

  /// Center zone default view
  final String centerDefault;

  /// Feature flags for this mode
  final EditorModeFeatures features;

  const EditorModeLayoutConfig({
    required this.mode,
    required this.lowerZone,
    required this.leftZone,
    required this.rightZone,
    required this.centerDefault,
    required this.features,
  });
}

// ============ Mode Configurations ============

/// DAW Mode - Cubase-style layout
///
/// Lower Zone tabs (left to right):
/// - MixConsole (Timeline, Mixer)
/// - Editor (Clip editing)
/// - Sampler (Layered music)
/// - Media (Audio Browser & Pool)
/// - DSP (Processing tools)
const EditorModeLayoutConfig dawModeConfig = EditorModeLayoutConfig(
  mode: EditorMode.daw,
  lowerZone: LowerZoneConfig(
    defaultTab: 'mixer',
    visibleGroups: ['mixconsole', 'clip-editor', 'sampler', 'media', 'dsp'],
    hiddenTabs: ['timeline'], // Timeline is in center zone
    groupOrder: ['mixconsole', 'clip-editor', 'sampler', 'media', 'dsp'],
  ),
  leftZone: LeftZoneConfig(
    defaultExpanded: ['audio-files', 'buses'],
    visibleFolders: ['audio-files', 'buses', 'events'],
  ),
  rightZone: RightZoneConfig(
    defaultType: 'clip',
    sectionPresets: ['clip-properties', 'bus-routing', 'effects'],
  ),
  centerDefault: 'timeline',
  features: EditorModeFeatures(
    showTransport: true,
    showTempo: true,
    showTimecode: true,
    showMusicLayers: true,
    showSlotTools: false,
    showGameSync: false,
  ),
);

/// Middleware Mode - Game audio middleware layout
///
/// Lower Zone tabs (left to right):
/// - Slot (Spin cycle, win tiers, reel sequencer, studio)
/// - Features (Audio features, pro tools)
/// - DSP (Processing tools)
/// - Tools (Validation, console, debug)
const EditorModeLayoutConfig middlewareModeConfig = EditorModeLayoutConfig(
  mode: EditorMode.middleware,
  lowerZone: LowerZoneConfig(
    defaultTab: 'slot-studio',
    visibleGroups: ['slot', 'features', 'dsp', 'tools'],
    hiddenTabs: ['timeline', 'mixer', 'layers', 'audio-browser', 'audio-pool'],
    groupOrder: ['slot', 'features', 'dsp', 'tools'],
  ),
  leftZone: LeftZoneConfig(
    defaultExpanded: ['events'],
    visibleFolders: ['events', 'buses', 'states', 'switches', 'rtpc'],
  ),
  rightZone: RightZoneConfig(
    defaultType: 'event',
    sectionPresets: ['event-commands', 'bus-routing', 'game-sync'],
  ),
  centerDefault: 'events',
  features: EditorModeFeatures(
    showTransport: false,
    showTempo: false,
    showTimecode: false,
    showMusicLayers: false,
    showSlotTools: true,
    showGameSync: true,
  ),
);

/// Slot Mode - Slot machine focused layout (extends Middleware)
const EditorModeLayoutConfig slotModeConfig = EditorModeLayoutConfig(
  mode: EditorMode.slot,
  lowerZone: LowerZoneConfig(
    defaultTab: 'spin-cycle',
    visibleGroups: ['slot', 'features', 'dsp', 'tools'],
    hiddenTabs: ['timeline', 'mixer', 'layers', 'audio-browser', 'audio-pool'],
    groupOrder: ['slot', 'features', 'dsp', 'tools'],
  ),
  leftZone: LeftZoneConfig(
    defaultExpanded: ['events'],
    visibleFolders: ['events', 'buses', 'states', 'switches'],
  ),
  rightZone: RightZoneConfig(
    defaultType: 'event',
    sectionPresets: ['event-commands', 'bus-routing', 'slot-config'],
  ),
  centerDefault: 'events',
  features: EditorModeFeatures(
    showTransport: false,
    showTempo: false,
    showTimecode: false,
    showMusicLayers: false,
    showSlotTools: true,
    showGameSync: true,
  ),
);

// ============ Config Map ============

/// Map of editor modes to their layout configurations
const Map<EditorMode, EditorModeLayoutConfig> modeLayoutConfigs = {
  EditorMode.daw: dawModeConfig,
  EditorMode.middleware: middlewareModeConfig,
  EditorMode.slot: slotModeConfig,
};

// ============ Utility Functions ============

/// Get layout config for a given mode
EditorModeLayoutConfig getModeLayoutConfig(EditorMode mode) {
  return modeLayoutConfigs[mode] ?? dawModeConfig;
}

/// Check if a tab should be visible in the given mode
bool isTabVisibleInMode(String tabId, EditorMode mode) {
  final config = getModeLayoutConfig(mode);
  return !config.lowerZone.hiddenTabs.contains(tabId);
}

/// Check if a tab group should be visible in the given mode
bool isTabGroupVisibleInMode(String groupId, EditorMode mode) {
  final config = getModeLayoutConfig(mode);
  return config.lowerZone.visibleGroups.contains(groupId);
}

/// Get the ordered tab groups for a mode
List<String> getOrderedTabGroups(EditorMode mode) {
  return getModeLayoutConfig(mode).lowerZone.groupOrder;
}

/// Get the default tab for a mode
String getDefaultTabForMode(EditorMode mode) {
  return getModeLayoutConfig(mode).lowerZone.defaultTab;
}

/// Filter tab groups based on mode visibility
List<T> filterTabGroupsForMode<T>(
  List<T> groups,
  EditorMode mode,
  String Function(T) getId,
) {
  final config = getModeLayoutConfig(mode);
  final visibleSet = config.lowerZone.visibleGroups.toSet();
  final orderMap = {
    for (var i = 0; i < config.lowerZone.groupOrder.length; i++)
      config.lowerZone.groupOrder[i]: i
  };

  return groups
      .where((g) => visibleSet.contains(getId(g)))
      .toList()
    ..sort((a, b) {
      final aOrder = orderMap[getId(a)] ?? 999;
      final bOrder = orderMap[getId(b)] ?? 999;
      return aOrder.compareTo(bOrder);
    });
}

/// Filter tabs based on mode visibility
List<T> filterTabsForMode<T>(
  List<T> tabs,
  EditorMode mode,
  String Function(T) getId,
) {
  final config = getModeLayoutConfig(mode);
  final hiddenSet = config.lowerZone.hiddenTabs.toSet();
  return tabs.where((t) => !hiddenSet.contains(getId(t))).toList();
}
