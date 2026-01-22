// FluxForge Studio Main Layout
//
// Master layout wrapper combining:
// - ControlBar (top)
// - LeftZone (project explorer)
// - CenterZone (main editor)
// - RightZone (inspector)
// - LowerZone (mixer/editor/browser)
//
// 1:1 migration from React MainLayout.tsx

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/fluxforge_theme.dart';
import '../models/layout_models.dart';
import '../models/timeline_models.dart' as timeline;
import '../widgets/layout/control_bar.dart';
import '../widgets/layout/left_zone.dart' show LeftZone, LeftZoneTab;
import '../widgets/layout/right_zone.dart' show RightZone, InspectedObjectType;
import '../widgets/layout/lower_zone.dart' show LowerZone;
import '../widgets/layout/lower_zone_glass.dart' show LowerZoneGlass;
import '../widgets/mixer/ultimate_mixer.dart' as ultimate;
import '../providers/mixer_provider.dart';
import '../widgets/layout/project_tree.dart' show ProjectTreeNode, TreeItemType;
import '../widgets/glass/glass_app_shell.dart';
import '../widgets/glass/glass_control_bar.dart';
import '../widgets/glass/glass_panels.dart';
import '../widgets/glass/glass_left_zone.dart';
import '../providers/theme_mode_provider.dart';

class MainLayout extends StatefulWidget {
  // PERFORMANCE: Custom control bar widget that handles its own provider listening
  // When provided, this replaces the default ControlBar to avoid rebuilding MainLayout
  // on every transport state change
  final Widget? customControlBar;

  // Control bar props (used only if customControlBar is null)
  final EditorMode editorMode;
  final ValueChanged<EditorMode>? onEditorModeChange;
  final bool isPlaying;
  final bool isRecording;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final double tempo;
  final ValueChanged<double>? onTempoChange;
  final TimeSignature timeSignature;
  final double currentTime;
  final TimeDisplayMode timeDisplayMode;
  final VoidCallback? onTimeDisplayModeChange;
  final bool loopEnabled;
  final VoidCallback? onLoopToggle;
  final bool snapEnabled;
  final double snapValue;
  final VoidCallback? onSnapToggle;
  final ValueChanged<double>? onSnapValueChange;
  final bool metronomeEnabled;
  final VoidCallback? onMetronomeToggle;
  final double cpuUsage;
  final double memoryUsage;
  final String projectName;
  final VoidCallback? onSave;
  final MenuCallbacks? menuCallbacks;

  // Left zone props
  final List<ProjectTreeNode> projectTree;
  final String? selectedProjectId;
  final void Function(String id, TreeItemType type, dynamic data)?
      onProjectSelect;
  final void Function(String id, TreeItemType type, dynamic data)?
      onProjectDoubleClick;
  final String projectSearchQuery;
  final ValueChanged<String>? onProjectSearchChange;
  final void Function(TreeItemType type)? onProjectAdd;
  final LeftZoneTab activeLeftTab;
  final ValueChanged<LeftZoneTab>? onLeftTabChange;
  final Set<String>? expandedFolderIds;
  final void Function(String id)? onToggleFolderExpanded;
  final ChannelStripData? channelData;
  final void Function(String channelId, double volume)? onChannelVolumeChange;
  final void Function(String channelId, double pan)? onChannelPanChange;
  final void Function(String channelId, double pan)? onChannelPanRightChange;
  final void Function(String channelId)? onChannelMuteToggle;
  final void Function(String channelId)? onChannelSoloToggle;
  final void Function(String channelId)? onChannelArmToggle;
  final void Function(String channelId)? onChannelMonitorToggle;
  final void Function(String channelId, int slotIndex)? onChannelInsertClick;
  final void Function(String channelId, int sendIndex)? onChannelSendClick;
  final void Function(String channelId, int sendIndex, double level)?
      onChannelSendLevelChange;
  final void Function(String channelId)? onChannelEQToggle;
  final void Function(String channelId)? onChannelOutputClick;
  final void Function(String channelId)? onChannelInputClick;
  final void Function(String channelId, int slotIndex, bool bypassed)? onChannelInsertBypassToggle;
  final void Function(String channelId, int slotIndex, double wetDry)? onChannelInsertWetDryChange;
  final void Function(String channelId, int slotIndex)? onChannelInsertRemove;
  final void Function(String channelId, int slotIndex)? onChannelInsertOpenEditor;

  // Center zone (main content)
  final Widget child;

  // Right zone props (Middleware mode)
  final InspectedObjectType inspectorType;
  final String? inspectorName;
  final List<InspectorSection> inspectorSections;

  // Clip inspector props (DAW mode)
  final timeline.TimelineClip? selectedClip;
  final timeline.TimelineTrack? selectedClipTrack;
  final ValueChanged<timeline.TimelineClip>? onClipChanged;
  final VoidCallback? onOpenClipFxEditor;

  // Lower zone props
  final List<LowerZoneTab> lowerTabs;
  final List<TabGroup>? lowerTabGroups;
  final String? activeLowerTabId;
  final ValueChanged<String>? onLowerTabChange;

  /// Custom Lower Zone widget (replaces default LowerZone tabs system)
  /// When provided, this widget is used instead of the generic tab-based LowerZone
  /// Use this for section-specific Lower Zones (DAW, Middleware, SlotLab)
  final Widget? customLowerZone;

  // Zone visibility (optional - uses internal state if not provided)
  final bool? leftZoneVisible;
  final bool? rightZoneVisible;
  final bool? lowerZoneVisible;
  final VoidCallback? onLeftZoneToggle;
  final VoidCallback? onRightZoneToggle;
  final VoidCallback? onLowerZoneToggle;

  const MainLayout({
    super.key,
    // Custom control bar (replaces default ControlBar for performance)
    this.customControlBar,
    // Control bar (used only if customControlBar is null)
    this.editorMode = EditorMode.daw,
    this.onEditorModeChange,
    this.isPlaying = false,
    this.isRecording = false,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
    this.tempo = 120,
    this.onTempoChange,
    this.timeSignature = const TimeSignature(4, 4),
    this.currentTime = 0,
    this.timeDisplayMode = TimeDisplayMode.bars,
    this.onTimeDisplayModeChange,
    this.loopEnabled = false,
    this.onLoopToggle,
    this.snapEnabled = true,
    this.snapValue = 1,
    this.onSnapToggle,
    this.onSnapValueChange,
    this.metronomeEnabled = false,
    this.onMetronomeToggle,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.projectName = 'Untitled',
    this.onSave,
    this.menuCallbacks,
    // Left zone
    this.projectTree = const [],
    this.selectedProjectId,
    this.onProjectSelect,
    this.onProjectDoubleClick,
    this.projectSearchQuery = '',
    this.onProjectSearchChange,
    this.onProjectAdd,
    this.activeLeftTab = LeftZoneTab.project,
    this.onLeftTabChange,
    this.expandedFolderIds,
    this.onToggleFolderExpanded,
    this.channelData,
    this.onChannelVolumeChange,
    this.onChannelPanChange,
    this.onChannelPanRightChange,
    this.onChannelMuteToggle,
    this.onChannelSoloToggle,
    this.onChannelArmToggle,
    this.onChannelMonitorToggle,
    this.onChannelInsertClick,
    this.onChannelSendClick,
    this.onChannelSendLevelChange,
    this.onChannelEQToggle,
    this.onChannelOutputClick,
    this.onChannelInputClick,
    this.onChannelInsertBypassToggle,
    this.onChannelInsertWetDryChange,
    this.onChannelInsertRemove,
    this.onChannelInsertOpenEditor,
    // Center zone
    required this.child,
    // Right zone (Middleware)
    this.inspectorType = InspectedObjectType.none,
    this.inspectorName,
    this.inspectorSections = const [],
    // Clip inspector (DAW)
    this.selectedClip,
    this.selectedClipTrack,
    this.onClipChanged,
    this.onOpenClipFxEditor,
    // Lower zone
    this.lowerTabs = const [],
    this.lowerTabGroups,
    this.activeLowerTabId,
    this.onLowerTabChange,
    this.customLowerZone,
    // Zone visibility
    this.leftZoneVisible,
    this.rightZoneVisible,
    this.lowerZoneVisible,
    this.onLeftZoneToggle,
    this.onRightZoneToggle,
    this.onLowerZoneToggle,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with TickerProviderStateMixin {
  // Internal zone visibility state
  bool _internalLeftVisible = true;
  bool _internalRightVisible = true;
  bool _internalLowerVisible = true; // Mixer visible by default
  double _lowerZoneHeight = 500; // Default to max height

  // Use external or internal state
  bool get _leftVisible => widget.leftZoneVisible ?? _internalLeftVisible;
  bool get _rightVisible => widget.rightZoneVisible ?? _internalRightVisible;
  bool get _lowerVisible => widget.lowerZoneVisible ?? _internalLowerVisible;

  void _toggleLeft() {
    if (widget.onLeftZoneToggle != null) {
      widget.onLeftZoneToggle!();
    } else {
      setState(() => _internalLeftVisible = !_internalLeftVisible);
    }
  }

  void _toggleRight() {
    if (widget.onRightZoneToggle != null) {
      widget.onRightZoneToggle!();
    } else {
      setState(() => _internalRightVisible = !_internalRightVisible);
    }
  }

  void _toggleLower() {
    if (widget.onLowerZoneToggle != null) {
      widget.onLowerZoneToggle!();
    } else {
      setState(() => _internalLowerVisible = !_internalLowerVisible);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Ignore if typing in input
    // Note: In Flutter, focus handling is different but we can still check modifiers

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Cmd+Shift+I - Import Audio Files
    if (isCtrl && isShift && key == LogicalKeyboardKey.keyI) {
      widget.menuCallbacks?.onImportAudioFiles?.call();
      return KeyEventResult.handled;
    }

    // Zone toggles
    if (isCtrl && key == LogicalKeyboardKey.keyL) {
      _toggleLeft();
      return KeyEventResult.handled;
    } else if (isCtrl && key == LogicalKeyboardKey.keyR) {
      _toggleRight();
      return KeyEventResult.handled;
    } else if (isCtrl && key == LogicalKeyboardKey.keyB) {
      _toggleLower();
      return KeyEventResult.handled;
    }

    // Transport shortcuts
    // Space = Play/Pause toggle (onPlay callback handles the toggle logic)
    // In DAW mode: toggles playback
    // In Middleware mode: triggers event preview (handled by callback)
    if (key == LogicalKeyboardKey.space) {
      debugPrint('[MainLayout] SPACE pressed, editorMode=${widget.editorMode}, onPlay=${widget.onPlay != null}');
      if (widget.editorMode == EditorMode.daw || widget.editorMode == EditorMode.middleware) {
        widget.onPlay?.call();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.period &&
        !isCtrl &&
        widget.editorMode == EditorMode.daw) {
      widget.onStop?.call();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyR && !isCtrl) {
      widget.onRecord?.call();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyK) {
      widget.onMetronomeToggle?.call();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.comma) {
      widget.onRewind?.call();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.slash) {
      widget.onForward?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeModeProvider>();
    final isGlassMode = themeMode.isGlassMode;

    // Build content based on theme mode
    Widget content = isGlassMode
        ? _buildGlassLayout()
        : _buildClassicLayout();

    // Wrap with appropriate shell
    // Note: Both modes need Scaffold for ScaffoldMessenger.showSnackBar to work
    return Focus(
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: isGlassMode
            ? GlassAppShell(child: content)
            : Container(
                color: FluxForgeTheme.bgDeepest,
                child: content,
              ),
      ),
    );
  }

  /// Build Glass-themed layout with all Glass components
  Widget _buildGlassLayout() {
    return Column(
      children: [
        // Glass Control Bar
        widget.customControlBar ?? GlassControlBar(
          editorMode: widget.editorMode,
          onEditorModeChange: widget.onEditorModeChange,
          isPlaying: widget.isPlaying,
          isRecording: widget.isRecording,
          onPlay: widget.onPlay,
          onStop: widget.onStop,
          onRecord: widget.onRecord,
          onRewind: widget.onRewind,
          onForward: widget.onForward,
          tempo: widget.tempo,
          onTempoChange: widget.onTempoChange,
          timeSignature: widget.timeSignature,
          currentTime: widget.currentTime,
          timeDisplayMode: widget.timeDisplayMode,
          onTimeDisplayModeChange: widget.onTimeDisplayModeChange,
          loopEnabled: widget.loopEnabled,
          onLoopToggle: widget.onLoopToggle,
          metronomeEnabled: widget.metronomeEnabled,
          onMetronomeToggle: widget.onMetronomeToggle,
          cpuUsage: widget.cpuUsage,
          memoryUsage: widget.memoryUsage,
          projectName: widget.projectName,
          onSave: widget.onSave,
          onToggleLeftZone: _toggleLeft,
          onToggleRightZone: _toggleRight,
          onToggleLowerZone: _toggleLower,
          menuCallbacks: widget.menuCallbacks,
        ),

        // Main Content Area
        Expanded(
          child: Row(
            children: [
              // Left Zone - Glass Browser + Channel
              if (_leftVisible)
                GlassLeftZone(
                  editorMode: widget.editorMode,
                  tree: widget.projectTree,
                  selectedId: widget.selectedProjectId,
                  onSelect: widget.onProjectSelect,
                  onDoubleClick: widget.onProjectDoubleClick,
                  searchQuery: widget.projectSearchQuery,
                  onSearchChange: widget.onProjectSearchChange,
                  onAdd: widget.onProjectAdd,
                  onToggleCollapse: _toggleLeft,
                  activeTab: widget.activeLeftTab,
                  onTabChange: widget.onLeftTabChange,
                  channelData: widget.channelData,
                  onChannelVolumeChange: widget.onChannelVolumeChange,
                  onChannelPanChange: widget.onChannelPanChange,
                  onChannelPanRightChange: widget.onChannelPanRightChange,
                  onChannelMuteToggle: widget.onChannelMuteToggle,
                  onChannelSoloToggle: widget.onChannelSoloToggle,
                  onChannelArmToggle: widget.onChannelArmToggle,
                  onChannelMonitorToggle: widget.onChannelMonitorToggle,
                  onChannelInsertClick: widget.onChannelInsertClick,
                  onChannelSendClick: widget.onChannelSendClick,
                  onChannelSendLevelChange: widget.onChannelSendLevelChange,
                  onChannelEQToggle: widget.onChannelEQToggle,
                  onChannelOutputClick: widget.onChannelOutputClick,
                  onChannelInputClick: widget.onChannelInputClick,
                  onChannelInsertBypassToggle: widget.onChannelInsertBypassToggle,
                  onChannelInsertWetDryChange: widget.onChannelInsertWetDryChange,
                  onChannelInsertRemove: widget.onChannelInsertRemove,
                  onChannelInsertOpenEditor: widget.onChannelInsertOpenEditor,
                  selectedClip: widget.selectedClip,
                  selectedClipTrack: widget.selectedClipTrack,
                  onClipChanged: widget.onClipChanged,
                ),

              // Center Zone + Lower Zone Container
              Expanded(
                child: Column(
                  children: [
                    // Center Zone with glass styling
                    Expanded(
                      child: _buildGlassCenterZone(),
                    ),

                    // Lower Zone - Glass version
                    LowerZoneGlass(
                      collapsed: !_lowerVisible,
                      tabs: widget.lowerTabs,
                      tabGroups: widget.lowerTabGroups,
                      activeTabId: widget.activeLowerTabId,
                      onTabChange: widget.onLowerTabChange,
                      onToggleCollapse: _toggleLower,
                      height: _lowerZoneHeight,
                      onHeightChange: (h) =>
                          setState(() => _lowerZoneHeight = h),
                      minHeight: 300,
                      maxHeight: 500,
                    ),
                  ],
                ),
              ),

              // Right Zone - Glass Inspector (only for non-DAW modes)
              if (widget.editorMode != EditorMode.daw && _rightVisible)
                SizedBox(
                  width: 280,
                  child: GlassInspector(
                    title: widget.inspectorName ?? 'Inspector',
                    sections: widget.inspectorSections.map((s) =>
                      GlassInspectorSection(
                        title: s.title,
                        child: s.content,
                      )
                    ).toList(),
                    onClose: _toggleRight,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build Glass-styled center zone
  Widget _buildGlassCenterZone() {
    // No extra BackdropFilter here - child widgets (timeline, mixer) have their own
    // Adding another BackdropFilter causes visual artifacts (white rays/stripes)
    return RepaintBoundary(
      child: widget.child,
    );
  }

  /// Build Classic layout (original implementation)
  Widget _buildClassicLayout() {
    return Column(
      children: [
        // Control Bar - use custom if provided (for performance isolation)
        widget.customControlBar ?? ControlBar(
          editorMode: widget.editorMode,
          onEditorModeChange: widget.onEditorModeChange,
          isPlaying: widget.isPlaying,
          isRecording: widget.isRecording,
          onPlay: widget.onPlay,
          onStop: widget.onStop,
          onRecord: widget.onRecord,
          onRewind: widget.onRewind,
          onForward: widget.onForward,
          tempo: widget.tempo,
          onTempoChange: widget.onTempoChange,
          timeSignature: widget.timeSignature,
          currentTime: widget.currentTime,
          timeDisplayMode: widget.timeDisplayMode,
          onTimeDisplayModeChange: widget.onTimeDisplayModeChange,
          loopEnabled: widget.loopEnabled,
          onLoopToggle: widget.onLoopToggle,
          snapEnabled: widget.snapEnabled,
          snapValue: widget.snapValue,
          onSnapToggle: widget.onSnapToggle,
          onSnapValueChange: widget.onSnapValueChange,
          metronomeEnabled: widget.metronomeEnabled,
          onMetronomeToggle: widget.onMetronomeToggle,
          cpuUsage: widget.cpuUsage,
          memoryUsage: widget.memoryUsage,
          projectName: widget.projectName,
          onSave: widget.onSave,
          onToggleLeftZone: _toggleLeft,
          onToggleRightZone: _toggleRight,
          onToggleLowerZone: _toggleLower,
          menuCallbacks: widget.menuCallbacks != null
              ? MenuCallbacks(
                  onNewProject: widget.menuCallbacks?.onNewProject,
                  onOpenProject: widget.menuCallbacks?.onOpenProject,
                  onSaveProject: widget.menuCallbacks?.onSaveProject,
                  onSaveProjectAs: widget.menuCallbacks?.onSaveProjectAs,
                  onImportJSON: widget.menuCallbacks?.onImportJSON,
                  onExportJSON: widget.menuCallbacks?.onExportJSON,
                  onImportAudioFolder: widget.menuCallbacks?.onImportAudioFolder,
                  onImportAudioFiles: widget.menuCallbacks?.onImportAudioFiles,
                  onUndo: widget.menuCallbacks?.onUndo,
                  onRedo: widget.menuCallbacks?.onRedo,
                  onCut: widget.menuCallbacks?.onCut,
                  onCopy: widget.menuCallbacks?.onCopy,
                  onPaste: widget.menuCallbacks?.onPaste,
                  onDelete: widget.menuCallbacks?.onDelete,
                  onSelectAll: widget.menuCallbacks?.onSelectAll,
                  onToggleLeftPanel: _toggleLeft,
                  onToggleRightPanel: _toggleRight,
                  onToggleLowerPanel: _toggleLower,
                  onResetLayout: widget.menuCallbacks?.onResetLayout,
                  onProjectSettings: widget.menuCallbacks?.onProjectSettings,
                  onValidateProject: widget.menuCallbacks?.onValidateProject,
                  onBuildProject: widget.menuCallbacks?.onBuildProject,
                )
              : null,
        ),

        // Main Content Area
        Expanded(
          child: Row(
            children: [
              // Left Zone (Browser) - all modes
              LeftZone(
                editorMode: widget.editorMode,
                collapsed: !_leftVisible,
                tree: widget.projectTree,
                selectedId: widget.selectedProjectId,
                onSelect: widget.onProjectSelect,
                onDoubleClick: widget.onProjectDoubleClick,
                searchQuery: widget.projectSearchQuery,
                onSearchChange: widget.onProjectSearchChange,
                onAdd: widget.onProjectAdd,
                onToggleCollapse: _toggleLeft,
                activeTab: widget.activeLeftTab,
                onTabChange: widget.onLeftTabChange,
                channelData: widget.channelData,
                onChannelVolumeChange: widget.onChannelVolumeChange,
                onChannelPanChange: widget.onChannelPanChange,
                onChannelPanRightChange: widget.onChannelPanRightChange,
                onChannelMuteToggle: widget.onChannelMuteToggle,
                onChannelSoloToggle: widget.onChannelSoloToggle,
                onChannelArmToggle: widget.onChannelArmToggle,
                onChannelMonitorToggle: widget.onChannelMonitorToggle,
                onChannelInsertClick: widget.onChannelInsertClick,
                onChannelSendClick: widget.onChannelSendClick,
                onChannelSendLevelChange: widget.onChannelSendLevelChange,
                onChannelEQToggle: widget.onChannelEQToggle,
                onChannelOutputClick: widget.onChannelOutputClick,
                onChannelInputClick: widget.onChannelInputClick,
                onChannelInsertBypassToggle: widget.onChannelInsertBypassToggle,
                onChannelInsertWetDryChange: widget.onChannelInsertWetDryChange,
                onChannelInsertRemove: widget.onChannelInsertRemove,
                onChannelInsertOpenEditor: widget.onChannelInsertOpenEditor,
                // Pass clip data for combined inspector
                selectedClip: widget.selectedClip,
                selectedClipTrack: widget.selectedClipTrack,
                onClipChanged: widget.onClipChanged,
                // External folder expansion state (from AudioAssetManager)
                expandedFolderIds: widget.expandedFolderIds,
                onToggleFolderExpanded: widget.onToggleFolderExpanded,
              ),

              // Center Zone + Lower Zone Container
              Expanded(
                child: Column(
                  children: [
                    // Center Zone - Full width edge-to-edge (no borders, no padding)
                    Expanded(
                      child: widget.child,
                    ),

                    // Lower Zone
                    // Use custom Lower Zone widget if provided, otherwise fall back to generic tabs
                    if (_lowerVisible && widget.customLowerZone != null)
                      widget.customLowerZone!
                    else
                      LowerZone(
                        collapsed: !_lowerVisible,
                        tabs: widget.lowerTabs,
                        tabGroups: widget.lowerTabGroups,
                        activeTabId: widget.activeLowerTabId,
                        onTabChange: widget.onLowerTabChange,
                        onToggleCollapse: _toggleLower,
                        height: _lowerZoneHeight,
                        onHeightChange: (h) =>
                            setState(() => _lowerZoneHeight = h),
                        minHeight: 300,
                        maxHeight: 500,
                      ),
                  ],
                ),
              ),

              // Right Zone (Inspector) - Middleware/Slot modes
              if (widget.editorMode != EditorMode.daw)
                RightZone(
                  collapsed: !_rightVisible,
                  objectType: widget.inspectorType,
                  objectName: widget.inspectorName,
                  sections: widget.inspectorSections,
                  onToggleCollapse: _toggleRight,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============ Demo Layout for Testing ============

/// Demo version of MainLayout with mock data for quick testing
class DemoMainLayout extends StatefulWidget {
  const DemoMainLayout({super.key});

  @override
  State<DemoMainLayout> createState() => _DemoMainLayoutState();
}

class _DemoMainLayoutState extends State<DemoMainLayout> {
  // Transport state
  bool _isPlaying = false;
  bool _isRecording = false;
  bool _loopEnabled = true;
  bool _metronomeEnabled = false;
  double _currentTime = 0;
  double _tempo = 120;
  EditorMode _editorMode = EditorMode.daw;
  TimeDisplayMode _timeDisplayMode = TimeDisplayMode.bars;
  bool _snapEnabled = true;
  double _snapValue = 1;

  // Zone state
  bool _leftVisible = true;
  bool _rightVisible = true;
  bool _lowerVisible = false;
  String _activeLowerTab = 'mixer';
  LeftZoneTab _activeLeftTab = LeftZoneTab.project;

  // Project tree demo data
  final List<ProjectTreeNode> _projectTree = [
    ProjectTreeNode(
      id: 'audio',
      type: TreeItemType.folder,
      label: 'Audio',
      children: [
        ProjectTreeNode(
          id: 'drums',
          type: TreeItemType.folder,
          label: 'Drums',
          children: [
            const ProjectTreeNode(
              id: 'kick',
              type: TreeItemType.sound,
              label: 'Kick.wav',
            ),
            const ProjectTreeNode(
              id: 'snare',
              type: TreeItemType.sound,
              label: 'Snare.wav',
            ),
          ],
        ),
        const ProjectTreeNode(
          id: 'bass',
          type: TreeItemType.sound,
          label: 'Bass.wav',
        ),
      ],
    ),
    ProjectTreeNode(
      id: 'events',
      type: TreeItemType.folder,
      label: 'Events',
      children: [
        const ProjectTreeNode(
          id: 'play_music',
          type: TreeItemType.event,
          label: 'Play_Music',
        ),
        const ProjectTreeNode(
          id: 'stop_all',
          type: TreeItemType.event,
          label: 'Stop_All',
        ),
      ],
    ),
    ProjectTreeNode(
      id: 'buses',
      type: TreeItemType.folder,
      label: 'Buses',
      children: [
        const ProjectTreeNode(
          id: 'master',
          type: TreeItemType.bus,
          label: 'Master',
        ),
        const ProjectTreeNode(
          id: 'music',
          type: TreeItemType.bus,
          label: 'Music',
        ),
        const ProjectTreeNode(
          id: 'sfx',
          type: TreeItemType.bus,
          label: 'SFX',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      // Control bar
      editorMode: _editorMode,
      onEditorModeChange: (mode) => setState(() => _editorMode = mode),
      isPlaying: _isPlaying,
      isRecording: _isRecording,
      onPlay: () => setState(() => _isPlaying = !_isPlaying),
      onStop: () => setState(() {
        _isPlaying = false;
        _currentTime = 0;
      }),
      onRecord: () => setState(() => _isRecording = !_isRecording),
      onRewind: () => setState(() => _currentTime = 0),
      onForward: () => setState(() => _currentTime = 32),
      tempo: _tempo,
      onTempoChange: (t) => setState(() => _tempo = t),
      timeSignature: const TimeSignature(4, 4),
      currentTime: _currentTime,
      timeDisplayMode: _timeDisplayMode,
      onTimeDisplayModeChange: () => setState(() {
        switch (_timeDisplayMode) {
          case TimeDisplayMode.bars:
            _timeDisplayMode = TimeDisplayMode.timecode;
          case TimeDisplayMode.timecode:
            _timeDisplayMode = TimeDisplayMode.samples;
          case TimeDisplayMode.samples:
            _timeDisplayMode = TimeDisplayMode.bars;
        }
      }),
      loopEnabled: _loopEnabled,
      onLoopToggle: () => setState(() => _loopEnabled = !_loopEnabled),
      snapEnabled: _snapEnabled,
      snapValue: _snapValue,
      onSnapToggle: () => setState(() => _snapEnabled = !_snapEnabled),
      onSnapValueChange: (v) => setState(() => _snapValue = v),
      metronomeEnabled: _metronomeEnabled,
      onMetronomeToggle: () =>
          setState(() => _metronomeEnabled = !_metronomeEnabled),
      cpuUsage: 15,
      memoryUsage: 35,
      projectName: 'Demo Project',

      // Left zone
      projectTree: _projectTree,
      activeLeftTab: _activeLeftTab,
      onLeftTabChange: (tab) => setState(() => _activeLeftTab = tab),

      // Center zone
      child: _buildCenterContent(),

      // Inspector (for middleware mode)
      inspectorType: InspectedObjectType.event,
      inspectorName: 'Play_Music',
      inspectorSections: [
        InspectorSection(
          id: 'general',
          title: 'General',
          content: const Text(
            'Event settings will appear here',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],

      // Lower zone
      lowerTabs: [
        LowerZoneTab(
          id: 'mixer',
          label: 'Mixer',
          icon: Icons.tune,
          content: _buildMixerContent(),
        ),
        LowerZoneTab(
          id: 'editor',
          label: 'Editor',
          icon: Icons.edit,
          content: const Center(
            child: Text(
              'Editor View',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ),
        ),
        LowerZoneTab(
          id: 'browser',
          label: 'Browser',
          icon: Icons.folder,
          content: const Center(
            child: Text(
              'Browser View',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ),
        ),
      ],
      activeLowerTabId: _activeLowerTab,
      onLowerTabChange: (id) => setState(() => _activeLowerTab = id),

      // Zone visibility
      leftZoneVisible: _leftVisible,
      rightZoneVisible: _rightVisible,
      lowerZoneVisible: _lowerVisible,
      onLeftZoneToggle: () => setState(() => _leftVisible = !_leftVisible),
      onRightZoneToggle: () => setState(() => _rightVisible = !_rightVisible),
      onLowerZoneToggle: () => setState(() => _lowerVisible = !_lowerVisible),
    );
  }

  Widget _buildCenterContent() {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'FluxForge Studio DAW',
              style: FluxForgeTheme.h1,
            ),
            const SizedBox(height: 8),
            Text(
              'Flutter UI Migration Demo',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Press Ctrl+L/R/B to toggle zones',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            Text(
              'Space to play/pause, R to record',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build mixer content - uses UltimateMixer with MixerProvider
  Widget _buildMixerContent() {
    return Consumer<MixerProvider>(
      builder: (context, mixerProvider, _) {
        final channels = mixerProvider.channels.map((ch) {
          return ultimate.UltimateMixerChannel(
            id: ch.id,
            name: ch.name,
            type: ultimate.ChannelType.audio,
            color: ch.color,
            volume: ch.volume,
            pan: ch.pan,
            panRight: ch.panRight,
            isStereo: ch.isStereo,
            muted: ch.muted,
            soloed: ch.soloed,
            armed: ch.armed,
            peakL: ch.peakL,
            peakR: ch.peakR,
            rmsL: ch.rmsL,
            rmsR: ch.rmsR,
          );
        }).toList();

        final buses = mixerProvider.buses.map((bus) {
          return ultimate.UltimateMixerChannel(
            id: bus.id,
            name: bus.name,
            type: ultimate.ChannelType.bus,
            color: bus.color,
            volume: bus.volume,
            pan: bus.pan,
            muted: bus.muted,
            soloed: bus.soloed,
            peakL: bus.peakL,
            peakR: bus.peakR,
          );
        }).toList();

        final auxes = mixerProvider.auxes.map((aux) {
          return ultimate.UltimateMixerChannel(
            id: aux.id,
            name: aux.name,
            type: ultimate.ChannelType.aux,
            color: aux.color,
            volume: aux.volume,
            pan: aux.pan,
            muted: aux.muted,
            soloed: aux.soloed,
            peakL: aux.peakL,
            peakR: aux.peakR,
          );
        }).toList();

        final master = ultimate.UltimateMixerChannel(
          id: mixerProvider.master.id,
          name: 'Master',
          type: ultimate.ChannelType.master,
          color: const Color(0xFFFF9040),
          volume: mixerProvider.master.volume,
          peakL: mixerProvider.master.peakL,
          peakR: mixerProvider.master.peakR,
        );

        return ultimate.UltimateMixer(
          channels: channels,
          buses: buses,
          auxes: auxes,
          vcas: const [],
          master: master,
          showInserts: true,
          showSends: true,
          onVolumeChange: (id, volume) => mixerProvider.setChannelVolume(id, volume),
          onPanChange: (id, pan) => mixerProvider.setChannelPan(id, pan),
          onPanRightChange: (id, pan) => mixerProvider.setChannelPanRight(id, pan),
          onMuteToggle: (id) => mixerProvider.toggleChannelMute(id),
          onSoloToggle: (id) => mixerProvider.toggleChannelSolo(id),
          onArmToggle: (id) => mixerProvider.toggleChannelArm(id),
        );
      },
    );
  }
}
