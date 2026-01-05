/// Layout Models
///
/// Core data types matching React TypeScript interfaces:
/// - TreeNode (project explorer)
/// - InspectorSection
/// - LowerZoneTab
/// - TabGroup
/// - ChannelStripData
/// - MenuCallbacks

import 'package:flutter/material.dart';

/// Project explorer tree node
class TreeNode {
  final String id;
  final String name;
  final String type; // 'folder', 'event', 'bus', 'file'
  final IconData? icon;
  final List<TreeNode> children;
  final bool expanded;
  final Map<String, dynamic>? metadata;

  const TreeNode({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.children = const [],
    this.expanded = false,
    this.metadata,
  });

  TreeNode copyWith({
    String? id,
    String? name,
    String? type,
    IconData? icon,
    List<TreeNode>? children,
    bool? expanded,
    Map<String, dynamic>? metadata,
  }) {
    return TreeNode(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      children: children ?? this.children,
      expanded: expanded ?? this.expanded,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Inspector panel section
class InspectorSection {
  final String id;
  final String title;
  final bool expanded;
  final Widget content;

  const InspectorSection({
    required this.id,
    required this.title,
    this.expanded = true,
    required this.content,
  });
}

/// Lower zone tab
class LowerZoneTab {
  final String id;
  final String label;
  final IconData? icon;
  final Widget content;
  final bool closable;
  final String? groupId;

  const LowerZoneTab({
    required this.id,
    required this.label,
    this.icon,
    required this.content,
    this.closable = false,
    this.groupId,
  });
}

/// Tab group for organizing lower zone tabs
class TabGroup {
  final String id;
  final String label;
  final List<String> tabs;

  const TabGroup({
    required this.id,
    required this.label,
    required this.tabs,
  });
}

/// Insert slot for mixer/channel strip
class InsertSlot {
  final String id;
  final String name;
  final String type; // 'eq', 'comp', 'reverb', 'delay', 'filter', 'fx', 'utility', 'custom', 'empty'
  final bool bypassed;
  final Map<String, dynamic>? params;

  const InsertSlot({
    required this.id,
    required this.name,
    required this.type,
    this.bypassed = false,
    this.params,
  });

  bool get isEmpty => type == 'empty';

  InsertSlot copyWith({
    String? id,
    String? name,
    String? type,
    bool? bypassed,
    Map<String, dynamic>? params,
  }) {
    return InsertSlot(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      bypassed: bypassed ?? this.bypassed,
      params: params ?? this.params,
    );
  }
}

/// Send slot for mixer/channel strip
class SendSlot {
  final String id;
  final String destination; // bus id
  final double level; // 0-1
  final bool preFader;
  final bool enabled;

  const SendSlot({
    required this.id,
    required this.destination,
    this.level = 0,
    this.preFader = false,
    this.enabled = true,
  });
}

/// EQ band for channel strip
class EQBand {
  final int index;
  final String type; // 'lowcut', 'lowshelf', 'bell', 'highshelf', 'highcut'
  final double frequency;
  final double gain; // dB
  final double q;
  final bool enabled;

  const EQBand({
    required this.index,
    required this.type,
    required this.frequency,
    this.gain = 0,
    this.q = 1,
    this.enabled = true,
  });
}

/// Channel strip data (for DAW mode)
class ChannelStripData {
  final String id;
  final String name;
  final String type; // 'audio', 'instrument', 'bus', 'master'
  final Color color;
  final double volume; // dB
  final double pan; // -1 to 1
  final bool mute;
  final bool solo;
  final double meterL;
  final double meterR;
  final double peakL;
  final double peakR;
  final List<InsertSlot> inserts;
  final List<SendSlot> sends;
  final bool eqEnabled;
  final List<EQBand> eqBands;
  final String input;
  final String output;

  const ChannelStripData({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    this.volume = 0,
    this.pan = 0,
    this.mute = false,
    this.solo = false,
    this.meterL = 0,
    this.meterR = 0,
    this.peakL = 0,
    this.peakR = 0,
    this.inserts = const [],
    this.sends = const [],
    this.eqEnabled = false,
    this.eqBands = const [],
    this.input = 'No Input',
    this.output = 'Stereo Out',
  });
}

/// Editor mode enum
enum EditorMode {
  daw,
  middleware,
  slot,
}

/// Mode configuration
class ModeConfig {
  final EditorMode mode;
  final String name;
  final String description;
  final String icon;
  final String shortcut;
  final Color accentColor;

  const ModeConfig({
    required this.mode,
    required this.name,
    required this.description,
    required this.icon,
    required this.shortcut,
    required this.accentColor,
  });
}

/// Menu callbacks
class MenuCallbacks {
  // File menu
  final VoidCallback? onNewProject;
  final VoidCallback? onOpenProject;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveProjectAs;
  final VoidCallback? onImportJSON;
  final VoidCallback? onExportJSON;
  final VoidCallback? onImportAudioFolder;
  final VoidCallback? onImportAudioFiles;
  final VoidCallback? onExportAudio;
  // Edit menu
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onDelete;
  final VoidCallback? onSelectAll;
  // View menu
  final VoidCallback? onToggleLeftPanel;
  final VoidCallback? onToggleRightPanel;
  final VoidCallback? onToggleLowerPanel;
  final VoidCallback? onResetLayout;
  // Project menu
  final VoidCallback? onProjectSettings;
  final VoidCallback? onValidateProject;
  final VoidCallback? onBuildProject;
  // Studio menu
  final VoidCallback? onAudioSettings;
  final VoidCallback? onMidiSettings;
  final VoidCallback? onPluginManager;

  const MenuCallbacks({
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onImportJSON,
    this.onExportJSON,
    this.onImportAudioFolder,
    this.onImportAudioFiles,
    this.onExportAudio,
    this.onUndo,
    this.onRedo,
    this.onCut,
    this.onCopy,
    this.onPaste,
    this.onDelete,
    this.onSelectAll,
    this.onToggleLeftPanel,
    this.onToggleRightPanel,
    this.onToggleLowerPanel,
    this.onResetLayout,
    this.onProjectSettings,
    this.onValidateProject,
    this.onBuildProject,
    this.onAudioSettings,
    this.onMidiSettings,
    this.onPluginManager,
  });
}

/// Time display mode
enum TimeDisplayMode {
  bars,
  timecode,
  samples,
}

/// Time signature
class TimeSignature {
  final int numerator;
  final int denominator;

  const TimeSignature(this.numerator, this.denominator);

  @override
  String toString() => '$numerator/$denominator';
}

/// Loop region
class LoopRegion {
  final double start;
  final double end;

  const LoopRegion({required this.start, required this.end});

  double get duration => end - start;
}

/// Event data for Middleware mode
class EventData {
  final String id;
  final String name;
  final String category;
  final List<ActionData> actions;
  final bool isExpanded;

  const EventData({
    required this.id,
    required this.name,
    this.category = 'General',
    this.actions = const [],
    this.isExpanded = false,
  });

  EventData copyWith({
    String? id,
    String? name,
    String? category,
    List<ActionData>? actions,
    bool? isExpanded,
  }) {
    return EventData(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      actions: actions ?? this.actions,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}

/// Action data for Events
class ActionData {
  final String id;
  final String type; // 'play', 'stop', 'fade', 'pause', 'set_bus_gain', 'stop_all', 'execute'
  final String? targetAsset;
  final String? targetBus;
  final Map<String, dynamic>? params;

  const ActionData({
    required this.id,
    required this.type,
    this.targetAsset,
    this.targetBus,
    this.params,
  });
}
