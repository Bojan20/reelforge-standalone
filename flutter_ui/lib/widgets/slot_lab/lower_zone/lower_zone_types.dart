/// SlotLab Lower Zone Types — Super-Tab and Sub-Tab Definitions
///
/// Defines the hierarchical tab structure:
/// - 7 Super-tabs (STAGES, EVENTS, MIX, MUSIC/ALE, DSP, BAKE, ENGINE)
/// - Plus menu (Command Builder, Game Config, AutoSpatial, Scenarios)
/// - Each super-tab has sub-tabs
///
/// Based on CLAUDE.md specification and MASTER_TODO.md SL-LZ-P0.2
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SUPER-TAB ENUM
// ═══════════════════════════════════════════════════════════════════════════

/// Main super-tab categories for Lower Zone
enum SuperTab {
  stages,   // Timeline, Event Debug
  events,   // Event List, RTPC, Composite Editor
  mix,      // Bus Hierarchy, Aux Sends, Meters
  musicAle, // ALE Rules, Signals, Transitions
  dsp,      // EQ, Compressor, Limiter, Gate, Reverb
  bake,     // Batch Export, Validation, Package
  engine,   // Profiler, Resources, Stage Ingest
  menu,     // [+] Menu: Command Builder, Game Config, AutoSpatial, Scenarios
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-TAB ENUMS (per super-tab)
// ═══════════════════════════════════════════════════════════════════════════

/// Sub-tabs for STAGES super-tab
enum StagesSubTab {
  timeline,    // Stage trace timeline
  eventDebug,  // Event debugger/tracer
}

/// Sub-tabs for EVENTS super-tab
enum EventsSubTab {
  eventList,       // Event list browser
  rtpc,            // RTPC debugger
  compositeEditor, // Composite event editor
}

/// Sub-tabs for MIX super-tab
enum MixSubTab {
  busHierarchy, // Bus hierarchy panel
  auxSends,     // Aux sends panel
  meters,       // Audio bus meters
}

/// Sub-tabs for MUSIC/ALE super-tab
enum MusicAleSubTab {
  aleRules,      // ALE rules editor
  signals,       // Signal catalog
  transitions,   // Transition editor
  stability,     // Stability config
}

/// Sub-tabs for DSP super-tab
enum DspSubTab {
  eq,         // Pro-Q style EQ (placeholder for now)
  compressor, // Pro-C style compressor
  limiter,    // Pro-L style limiter
  gate,       // Pro-G style gate
  reverb,     // Pro-R style reverb
}

/// Sub-tabs for BAKE super-tab
enum BakeSubTab {
  batchExport, // Batch export panel
  validation,  // Validation checks
  package,     // Package builder
}

/// Sub-tabs for ENGINE super-tab
enum EngineSubTab {
  profiler,    // DSP profiler
  resources,   // Resource dashboard
  stageIngest, // Stage ingest panel
}

/// Sub-tabs for MENU (popup items, not actual tabs)
enum MenuSubTab {
  commandBuilder, // Command builder panel
  gameConfig,     // Game configuration
  autoSpatial,    // AutoSpatial panel
  scenarios,      // Scenario panel
}

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for a super-tab
class SuperTabConfig {
  final SuperTab tab;
  final String label;
  final IconData icon;
  final String? shortcut; // e.g., "Ctrl+Shift+T"
  final Color accentColor;
  final String description;

  const SuperTabConfig({
    required this.tab,
    required this.label,
    required this.icon,
    this.shortcut,
    required this.accentColor,
    required this.description,
  });
}

/// Configuration for a sub-tab
class SubTabConfig {
  final String id;       // Unique identifier
  final String label;
  final IconData icon;
  final String? shortcutKey; // Single key like '1', '2', etc.
  final String description;

  const SubTabConfig({
    required this.id,
    required this.label,
    required this.icon,
    this.shortcutKey,
    required this.description,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SUPER-TAB CONFIGURATIONS
// ═══════════════════════════════════════════════════════════════════════════

const Map<SuperTab, SuperTabConfig> kSuperTabConfigs = {
  SuperTab.stages: SuperTabConfig(
    tab: SuperTab.stages,
    label: 'STAGES',
    icon: Icons.timeline,
    shortcut: 'Ctrl+Shift+T',
    accentColor: Color(0xFF4A9EFF), // Blue
    description: 'Timeline and event debugging',
  ),
  SuperTab.events: SuperTabConfig(
    tab: SuperTab.events,
    label: 'EVENTS',
    icon: Icons.event_note,
    shortcut: 'Ctrl+Shift+E',
    accentColor: Color(0xFF40FF90), // Green
    description: 'Event list, RTPC, composite editor',
  ),
  SuperTab.mix: SuperTabConfig(
    tab: SuperTab.mix,
    label: 'MIX',
    icon: Icons.tune,
    shortcut: 'Ctrl+Shift+X',
    accentColor: Color(0xFFFF9040), // Orange
    description: 'Bus hierarchy, aux sends, meters',
  ),
  SuperTab.musicAle: SuperTabConfig(
    tab: SuperTab.musicAle,
    label: 'MUSIC',
    icon: Icons.music_note,
    shortcut: 'Ctrl+Shift+A',
    accentColor: Color(0xFF9370DB), // Purple
    description: 'Adaptive Layer Engine',
  ),
  SuperTab.dsp: SuperTabConfig(
    tab: SuperTab.dsp,
    label: 'DSP',
    icon: Icons.graphic_eq,
    shortcut: null,
    accentColor: Color(0xFF40C8FF), // Cyan
    description: 'EQ, compressor, limiter, gate, reverb',
  ),
  SuperTab.bake: SuperTabConfig(
    tab: SuperTab.bake,
    label: 'BAKE',
    icon: Icons.file_download,
    shortcut: null,
    accentColor: Color(0xFFFFD700), // Gold
    description: 'Batch export and packaging',
  ),
  SuperTab.engine: SuperTabConfig(
    tab: SuperTab.engine,
    label: 'ENGINE',
    icon: Icons.memory,
    shortcut: 'Ctrl+Shift+G',
    accentColor: Color(0xFFFF6B6B), // Red
    description: 'Profiler, resources, stage ingest',
  ),
  SuperTab.menu: SuperTabConfig(
    tab: SuperTab.menu,
    label: '+',
    icon: Icons.add,
    shortcut: null,
    accentColor: Color(0xFF808080), // Gray
    description: 'Additional panels',
  ),
};

// ═══════════════════════════════════════════════════════════════════════════
// SUB-TAB CONFIGURATIONS (per super-tab)
// ═══════════════════════════════════════════════════════════════════════════

/// Sub-tabs for STAGES super-tab
const List<SubTabConfig> kStagesSubTabs = [
  SubTabConfig(
    id: 'timeline',
    label: 'Timeline',
    icon: Icons.view_timeline,
    shortcutKey: '1',
    description: 'Stage trace timeline visualization',
  ),
  SubTabConfig(
    id: 'eventDebug',
    label: 'Event Debug',
    icon: Icons.bug_report,
    shortcutKey: '2',
    description: 'Event debugger and tracer',
  ),
];

/// Sub-tabs for EVENTS super-tab
const List<SubTabConfig> kEventsSubTabs = [
  SubTabConfig(
    id: 'eventList',
    label: 'Event List',
    icon: Icons.list_alt,
    shortcutKey: '1',
    description: 'Browse and manage events',
  ),
  SubTabConfig(
    id: 'rtpc',
    label: 'RTPC',
    icon: Icons.show_chart,
    shortcutKey: '2',
    description: 'RTPC debugger panel',
  ),
  SubTabConfig(
    id: 'compositeEditor',
    label: 'Composite',
    icon: Icons.edit,
    shortcutKey: '3',
    description: 'Composite event editor',
  ),
];

/// Sub-tabs for MIX super-tab
const List<SubTabConfig> kMixSubTabs = [
  SubTabConfig(
    id: 'busHierarchy',
    label: 'Buses',
    icon: Icons.account_tree,
    shortcutKey: '1',
    description: 'Bus hierarchy panel',
  ),
  SubTabConfig(
    id: 'auxSends',
    label: 'Aux Sends',
    icon: Icons.call_split,
    shortcutKey: '2',
    description: 'Aux send routing',
  ),
  SubTabConfig(
    id: 'meters',
    label: 'Meters',
    icon: Icons.equalizer,
    shortcutKey: '3',
    description: 'Audio bus meters',
  ),
];

/// Sub-tabs for MUSIC/ALE super-tab
const List<SubTabConfig> kMusicAleSubTabs = [
  SubTabConfig(
    id: 'aleRules',
    label: 'Rules',
    icon: Icons.rule,
    shortcutKey: '1',
    description: 'ALE rules editor',
  ),
  SubTabConfig(
    id: 'signals',
    label: 'Signals',
    icon: Icons.sensors,
    shortcutKey: '2',
    description: 'Signal catalog',
  ),
  SubTabConfig(
    id: 'transitions',
    label: 'Transitions',
    icon: Icons.swap_horiz,
    shortcutKey: '3',
    description: 'Transition editor',
  ),
  SubTabConfig(
    id: 'stability',
    label: 'Stability',
    icon: Icons.balance,
    shortcutKey: '4',
    description: 'Stability configuration',
  ),
];

/// Sub-tabs for DSP super-tab
const List<SubTabConfig> kDspSubTabs = [
  SubTabConfig(
    id: 'eq',
    label: 'EQ',
    icon: Icons.graphic_eq,
    shortcutKey: '1',
    description: 'Pro-Q style EQ',
  ),
  SubTabConfig(
    id: 'compressor',
    label: 'Comp',
    icon: Icons.compress,
    shortcutKey: '2',
    description: 'Pro-C style compressor',
  ),
  SubTabConfig(
    id: 'limiter',
    label: 'Limiter',
    icon: Icons.vertical_align_top,
    shortcutKey: '3',
    description: 'Pro-L style limiter',
  ),
  SubTabConfig(
    id: 'gate',
    label: 'Gate',
    icon: Icons.door_front_door_outlined,
    shortcutKey: '4',
    description: 'Pro-G style gate',
  ),
  SubTabConfig(
    id: 'reverb',
    label: 'Reverb',
    icon: Icons.waves,
    shortcutKey: '5',
    description: 'Pro-R style reverb',
  ),
];

/// Sub-tabs for BAKE super-tab
const List<SubTabConfig> kBakeSubTabs = [
  SubTabConfig(
    id: 'batchExport',
    label: 'Export',
    icon: Icons.file_download,
    shortcutKey: '1',
    description: 'Batch export panel',
  ),
  SubTabConfig(
    id: 'validation',
    label: 'Validate',
    icon: Icons.check_circle,
    shortcutKey: '2',
    description: 'Validation checks',
  ),
  SubTabConfig(
    id: 'package',
    label: 'Package',
    icon: Icons.inventory_2,
    shortcutKey: '3',
    description: 'Package builder',
  ),
];

/// Sub-tabs for ENGINE super-tab
const List<SubTabConfig> kEngineSubTabs = [
  SubTabConfig(
    id: 'profiler',
    label: 'Profiler',
    icon: Icons.speed,
    shortcutKey: '1',
    description: 'DSP profiler',
  ),
  SubTabConfig(
    id: 'resources',
    label: 'Resources',
    icon: Icons.storage,
    shortcutKey: '2',
    description: 'Resource dashboard',
  ),
  SubTabConfig(
    id: 'stageIngest',
    label: 'Stage Ingest',
    icon: Icons.input,
    shortcutKey: '3',
    description: 'Stage ingest panel',
  ),
];

/// Menu items (shown in popup, not as tabs)
const List<SubTabConfig> kMenuItems = [
  SubTabConfig(
    id: 'commandBuilder',
    label: 'Command Builder',
    icon: Icons.construction,
    description: 'Build audio commands',
  ),
  SubTabConfig(
    id: 'gameConfig',
    label: 'Game Config',
    icon: Icons.settings_applications,
    description: 'Game configuration',
  ),
  SubTabConfig(
    id: 'autoSpatial',
    label: 'AutoSpatial',
    icon: Icons.surround_sound,
    description: 'Spatial audio configuration',
  ),
  SubTabConfig(
    id: 'scenarios',
    label: 'Scenarios',
    icon: Icons.movie,
    description: 'Test scenarios',
  ),
];

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Get sub-tabs for a given super-tab
List<SubTabConfig> getSubTabsForSuperTab(SuperTab superTab) {
  switch (superTab) {
    case SuperTab.stages:
      return kStagesSubTabs;
    case SuperTab.events:
      return kEventsSubTabs;
    case SuperTab.mix:
      return kMixSubTabs;
    case SuperTab.musicAle:
      return kMusicAleSubTabs;
    case SuperTab.dsp:
      return kDspSubTabs;
    case SuperTab.bake:
      return kBakeSubTabs;
    case SuperTab.engine:
      return kEngineSubTabs;
    case SuperTab.menu:
      return kMenuItems;
  }
}

/// Get super-tab configuration
SuperTabConfig getSuperTabConfig(SuperTab superTab) {
  return kSuperTabConfigs[superTab]!;
}

/// Check if a key combination matches a super-tab shortcut
SuperTab? getSuperTabForShortcut(LogicalKeyboardKey key, bool ctrl, bool shift, bool alt, bool meta) {
  // We want Ctrl+Shift on Windows/Linux or Cmd+Shift on Mac
  final hasModifier = (ctrl || meta) && shift && !alt;
  if (!hasModifier) return null;

  switch (key) {
    case LogicalKeyboardKey.keyT:
      return SuperTab.stages;
    case LogicalKeyboardKey.keyE:
      return SuperTab.events;
    case LogicalKeyboardKey.keyX:
      return SuperTab.mix;
    case LogicalKeyboardKey.keyA:
      return SuperTab.musicAle;
    case LogicalKeyboardKey.keyG:
      return SuperTab.engine;
    default:
      return null;
  }
}

/// Get sub-tab index from shortcut key (1-9)
int? getSubTabIndexForShortcut(LogicalKeyboardKey key) {
  final keyMap = {
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.digit5: 4,
    LogicalKeyboardKey.digit6: 5,
    LogicalKeyboardKey.digit7: 6,
    LogicalKeyboardKey.digit8: 7,
    LogicalKeyboardKey.digit9: 8,
  };
  return keyMap[key];
}

/// Convert legacy LowerZoneTab to new super-tab + sub-tab index
/// Returns (SuperTab, subTabIndex) tuple
(SuperTab, int) legacyTabToSuperTab(String legacyTab) {
  switch (legacyTab) {
    case 'timeline':
      return (SuperTab.stages, 0);
    case 'commandBuilder':
      return (SuperTab.menu, 0); // Move to menu
    case 'eventList':
      return (SuperTab.events, 0);
    case 'meters':
      return (SuperTab.mix, 2);
    case 'dspCompressor':
      return (SuperTab.dsp, 1);
    case 'dspLimiter':
      return (SuperTab.dsp, 2);
    case 'dspGate':
      return (SuperTab.dsp, 3);
    case 'dspReverb':
      return (SuperTab.dsp, 4);
    default:
      return (SuperTab.stages, 0);
  }
}
