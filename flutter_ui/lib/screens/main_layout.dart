/// ReelForge Main Layout
///
/// Master layout wrapper combining:
/// - ControlBar (top)
/// - LeftZone (project explorer)
/// - CenterZone (main editor)
/// - RightZone (inspector)
/// - LowerZone (mixer/editor/browser)
///
/// 1:1 migration from React MainLayout.tsx

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/reelforge_theme.dart';
import '../models/layout_models.dart';
import '../widgets/layout/control_bar.dart';
import '../widgets/layout/left_zone.dart' show LeftZone, LeftZoneTab;
import '../widgets/layout/right_zone.dart' show RightZone, InspectedObjectType;
import '../widgets/layout/lower_zone.dart' show LowerZone, MixerStrip;
import '../widgets/layout/project_tree.dart' show ProjectTreeNode, TreeItemType;

class MainLayout extends StatefulWidget {
  // Control bar props
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
  final ChannelStripData? channelData;
  final void Function(String channelId, double volume)? onChannelVolumeChange;
  final void Function(String channelId, double pan)? onChannelPanChange;
  final void Function(String channelId)? onChannelMuteToggle;
  final void Function(String channelId)? onChannelSoloToggle;
  final void Function(String channelId, int slotIndex)? onChannelInsertClick;
  final void Function(String channelId, int sendIndex, double level)?
      onChannelSendLevelChange;
  final void Function(String channelId)? onChannelEQToggle;
  final void Function(String channelId)? onChannelOutputClick;

  // Center zone (main content)
  final Widget child;

  // Right zone props
  final InspectedObjectType inspectorType;
  final String? inspectorName;
  final List<InspectorSection> inspectorSections;

  // Lower zone props
  final List<LowerZoneTab> lowerTabs;
  final List<TabGroup>? lowerTabGroups;
  final String? activeLowerTabId;
  final ValueChanged<String>? onLowerTabChange;

  // Zone visibility (optional - uses internal state if not provided)
  final bool? leftZoneVisible;
  final bool? rightZoneVisible;
  final bool? lowerZoneVisible;
  final VoidCallback? onLeftZoneToggle;
  final VoidCallback? onRightZoneToggle;
  final VoidCallback? onLowerZoneToggle;

  const MainLayout({
    super.key,
    // Control bar
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
    this.channelData,
    this.onChannelVolumeChange,
    this.onChannelPanChange,
    this.onChannelMuteToggle,
    this.onChannelSoloToggle,
    this.onChannelInsertClick,
    this.onChannelSendLevelChange,
    this.onChannelEQToggle,
    this.onChannelOutputClick,
    // Center zone
    required this.child,
    // Right zone
    this.inspectorType = InspectedObjectType.none,
    this.inspectorName,
    this.inspectorSections = const [],
    // Lower zone
    this.lowerTabs = const [],
    this.lowerTabGroups,
    this.activeLowerTabId,
    this.onLowerTabChange,
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
  bool _internalLowerVisible = false;
  double _lowerZoneHeight = 450;

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

    // Transport shortcuts (only in DAW mode)
    if (key == LogicalKeyboardKey.space &&
        widget.editorMode == EditorMode.daw) {
      if (widget.isPlaying) {
        widget.onStop?.call();
      } else {
        widget.onPlay?.call();
      }
      return KeyEventResult.handled;
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
    return Focus(
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: ReelForgeTheme.bgDeepest,
        body: Column(
          children: [
            // Control Bar
            ControlBar(
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
                  // Left Zone
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
                    onChannelMuteToggle: widget.onChannelMuteToggle,
                    onChannelSoloToggle: widget.onChannelSoloToggle,
                    onChannelInsertClick: widget.onChannelInsertClick,
                    onChannelSendLevelChange: widget.onChannelSendLevelChange,
                    onChannelEQToggle: widget.onChannelEQToggle,
                    onChannelOutputClick: widget.onChannelOutputClick,
                  ),

                  // Center Zone + Lower Zone Container
                  Expanded(
                    child: Column(
                      children: [
                        // Center Zone
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: ReelForgeTheme.bgDeep,
                              border: Border(
                                left: BorderSide(
                                  color: ReelForgeTheme.borderSubtle,
                                ),
                                right: BorderSide(
                                  color: ReelForgeTheme.borderSubtle,
                                ),
                              ),
                            ),
                            child: widget.child,
                          ),
                        ),

                        // Lower Zone
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

                  // Right Zone - Show Inspector in Middleware/Slot modes (not DAW)
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
        ),
      ),
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
            style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
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
              style: TextStyle(color: ReelForgeTheme.textSecondary),
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
              style: TextStyle(color: ReelForgeTheme.textSecondary),
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
      color: ReelForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'ReelForge DAW',
              style: ReelForgeTheme.h1,
            ),
            const SizedBox(height: 8),
            Text(
              'Flutter UI Migration Demo',
              style: TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Press Ctrl+L/R/B to toggle zones',
              style: TextStyle(
                color: ReelForgeTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            Text(
              'Space to play/pause, R to record',
              style: TextStyle(
                color: ReelForgeTheme.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMixerContent() {
    return Row(
      children: [
        MixerStrip(
          id: 'sfx',
          name: 'SFX',
          volume: 1.0,
          meterLevel: 0.3,
          meterLevelR: 0.25,
          inserts: const [
            InsertSlot(id: '1', name: 'EQ', type: 'eq'),
            InsertSlot(id: '2', name: 'Comp', type: 'comp'),
          ],
        ),
        MixerStrip(
          id: 'music',
          name: 'Music',
          volume: 0.8,
          meterLevel: 0.5,
          meterLevelR: 0.45,
        ),
        MixerStrip(
          id: 'voice',
          name: 'Voice',
          volume: 1.0,
          meterLevel: 0.2,
          meterLevelR: 0.2,
        ),
        MixerStrip(
          id: 'master',
          name: 'Master',
          isMaster: true,
          volume: 1.0,
          meterLevel: 0.6,
          meterLevelR: 0.55,
          inserts: const [
            InsertSlot(id: 'm1', name: 'Limiter', type: 'comp'),
          ],
        ),
      ],
    );
  }
}
