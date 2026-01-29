// Layout Models
//
// Core data types matching React TypeScript interfaces:
// - TreeNode (project explorer)
// - InspectorSection
// - LowerZoneTab
// - TabGroup
// - ChannelStripData
// - MenuCallbacks

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
  final Widget? content;
  final Widget Function()? contentBuilder; // For dynamic content that needs fresh callbacks
  final bool closable;
  final String? groupId;

  const LowerZoneTab({
    required this.id,
    required this.label,
    this.icon,
    this.content,
    this.contentBuilder,
    this.closable = false,
    this.groupId,
  }) : assert(content != null || contentBuilder != null, 'Either content or contentBuilder must be provided');

  /// Get the content widget (builds fresh if using contentBuilder)
  Widget getContent() => contentBuilder?.call() ?? content!;
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
  final bool isPreFader;
  final double wetDry; // 0.0 to 1.0
  final Map<String, dynamic>? params;

  const InsertSlot({
    required this.id,
    required this.name,
    required this.type,
    this.bypassed = false,
    this.isPreFader = false,
    this.wetDry = 1.0,
    this.params,
  });

  /// Wet/dry as percentage (0-100)
  int get wetDryPercent => (wetDry * 100).round();

  /// Create an empty insert slot
  factory InsertSlot.empty(int index, {bool isPreFader = false}) => InsertSlot(
    id: 'empty_$index',
    name: '',
    type: 'empty',
    isPreFader: isPreFader,
  );

  bool get isEmpty => type == 'empty' || name.isEmpty;

  InsertSlot copyWith({
    String? id,
    String? name,
    String? type,
    bool? bypassed,
    bool? isPreFader,
    double? wetDry,
    Map<String, dynamic>? params,
  }) {
    return InsertSlot(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      bypassed: bypassed ?? this.bypassed,
      isPreFader: isPreFader ?? this.isPreFader,
      wetDry: wetDry ?? this.wetDry,
      params: params ?? this.params,
    );
  }
}

/// Send slot for mixer/channel strip
class SendSlot {
  final String id;
  final String? destination; // bus id or null if not assigned
  final double level; // 0-1
  final bool preFader;
  final bool enabled;

  const SendSlot({
    required this.id,
    this.destination,
    this.level = 0,
    this.preFader = false,
    this.enabled = true,
  });

  bool get isEmpty => destination == null || destination!.isEmpty;

  SendSlot copyWith({
    String? id,
    String? destination,
    double? level,
    bool? preFader,
    bool? enabled,
  }) {
    return SendSlot(
      id: id ?? this.id,
      destination: destination ?? this.destination,
      level: level ?? this.level,
      preFader: preFader ?? this.preFader,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// LUFS loudness metering data
class LUFSData {
  final double momentary;
  final double shortTerm;
  final double integrated;
  final double truePeak;
  final double? range;

  const LUFSData({
    required this.momentary,
    required this.shortTerm,
    required this.integrated,
    required this.truePeak,
    this.range,
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
  final double pan; // -1 to 1 (left pan for stereo)
  final double panRight; // -1 to 1 (right pan for stereo, same as pan for mono)
  final bool isStereo; // true for stereo pan (L/R independent)
  final bool mute;
  final bool solo;
  final bool armed;
  final bool inputMonitor;
  final bool phaseInverted; // Phase/polarity invert (Ø)
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
  final LUFSData? lufs;

  const ChannelStripData({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    this.volume = 0,
    this.pan = 0,
    this.panRight = 0,
    this.isStereo = false,
    this.mute = false,
    this.solo = false,
    this.armed = false,
    this.inputMonitor = false,
    this.phaseInverted = false,
    this.meterL = 0,
    this.meterR = 0,
    this.peakL = 0,
    this.peakR = 0,
    this.inserts = const [],
    this.sends = const [],
    this.eqEnabled = false,
    this.eqBands = const [],
    this.input = '',
    this.output = 'Master',
    this.lufs,
  });

  ChannelStripData copyWith({
    String? id,
    String? name,
    String? type,
    Color? color,
    double? volume,
    double? pan,
    double? panRight,
    bool? isStereo,
    bool? mute,
    bool? solo,
    bool? armed,
    bool? inputMonitor,
    bool? phaseInverted,
    double? meterL,
    double? meterR,
    double? peakL,
    double? peakR,
    List<InsertSlot>? inserts,
    List<SendSlot>? sends,
    bool? eqEnabled,
    List<EQBand>? eqBands,
    String? input,
    String? output,
    LUFSData? lufs,
  }) {
    return ChannelStripData(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      color: color ?? this.color,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      panRight: panRight ?? this.panRight,
      isStereo: isStereo ?? this.isStereo,
      mute: mute ?? this.mute,
      solo: solo ?? this.solo,
      armed: armed ?? this.armed,
      inputMonitor: inputMonitor ?? this.inputMonitor,
      phaseInverted: phaseInverted ?? this.phaseInverted,
      meterL: meterL ?? this.meterL,
      meterR: meterR ?? this.meterR,
      peakL: peakL ?? this.peakL,
      peakR: peakR ?? this.peakR,
      inserts: inserts ?? this.inserts,
      sends: sends ?? this.sends,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqBands: eqBands ?? this.eqBands,
      input: input ?? this.input,
      output: output ?? this.output,
      lufs: lufs ?? this.lufs,
    );
  }
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
  final VoidCallback? onSaveAsTemplate;  // P3.2: Save as Template
  final VoidCallback? onImportJSON;
  final VoidCallback? onExportJSON;
  final VoidCallback? onImportAudioFolder;
  final VoidCallback? onImportAudioFiles;
  final VoidCallback? onExportAudio;
  final VoidCallback? onBatchExport;
  final VoidCallback? onExportPresets;
  final VoidCallback? onBounce;
  final VoidCallback? onRenderInPlace;
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
  final VoidCallback? onShowAudioPool;
  final VoidCallback? onShowMarkers;
  final VoidCallback? onShowMidiEditor;
  // Project menu
  final VoidCallback? onProjectSettings;
  final VoidCallback? onValidateProject;
  final VoidCallback? onBuildProject;
  final VoidCallback? onTrackTemplates;
  final VoidCallback? onVersionHistory;
  final VoidCallback? onFreezeSelectedTracks;
  // Studio menu
  final VoidCallback? onAudioSettings;
  final VoidCallback? onMidiSettings;
  final VoidCallback? onPluginManager;
  final VoidCallback? onKeyboardShortcuts;
  // Audio menu
  final VoidCallback? onDirectOfflineProcessing;
  // Track operations
  final VoidCallback? onAddTrack;
  final VoidCallback? onDeleteTrack;
  // Zoom operations
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  // Advanced panels
  final VoidCallback? onShowLogicalEditor;
  final VoidCallback? onShowScaleAssistant;
  final VoidCallback? onShowGrooveQuantize;
  final VoidCallback? onShowAudioAlignment;
  final VoidCallback? onShowTrackVersions;
  final VoidCallback? onShowMacroControls;
  final VoidCallback? onShowClipGainEnvelope;

  const MenuCallbacks({
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onSaveAsTemplate,  // P3.2
    this.onImportJSON,
    this.onExportJSON,
    this.onImportAudioFolder,
    this.onImportAudioFiles,
    this.onExportAudio,
    this.onBatchExport,
    this.onExportPresets,
    this.onBounce,
    this.onRenderInPlace,
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
    this.onShowAudioPool,
    this.onShowMarkers,
    this.onShowMidiEditor,
    this.onAddTrack,
    this.onDeleteTrack,
    this.onZoomIn,
    this.onZoomOut,
    this.onProjectSettings,
    this.onValidateProject,
    this.onBuildProject,
    this.onTrackTemplates,
    this.onVersionHistory,
    this.onFreezeSelectedTracks,
    this.onAudioSettings,
    this.onMidiSettings,
    this.onPluginManager,
    this.onKeyboardShortcuts,
    this.onDirectOfflineProcessing,
    this.onShowLogicalEditor,
    this.onShowScaleAssistant,
    this.onShowGrooveQuantize,
    this.onShowAudioAlignment,
    this.onShowTrackVersions,
    this.onShowMacroControls,
    this.onShowClipGainEnvelope,
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
