// Engine Connected Layout
//
// Connects MainLayout to the Rust EngineProvider.
// Bridges UI callbacks to engine API calls.
//
// ═══════════════════════════════════════════════════════════════════════════════
// MIDDLEWARE ↔ SLOT LAB BIDIRECTIONAL SYNC — ARCHITECTURE OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════
//
// SINGLE SOURCE OF TRUTH: MiddlewareProvider.compositeEvents
//
// DATA FLOW:
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │  LEFT PANEL (Events Folder)                                                  │
// │  └─ _buildProjectTree(compositeEvents) → displays event list with layer count│
// │     └─ On select → _selectedCompositeEventId = event.id                      │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │  CENTER PANEL (Actions Table)                                                │
// │  └─ _buildLayersAsActionsTable() → displays SlotCompositeEvent.layers        │
// │     └─ Uses original Wwise-style Actions UI (columns: #, Type, Asset, Bus...)│
// │     └─ Data source: SlotCompositeEvent.layers (NOT MiddlewareEvent.actions)  │
// │     └─ On add/edit → MiddlewareProvider.addLayerToEvent/updateLayer          │
// │                    → notifyListeners() → UI rebuilds                         │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │  RIGHT PANEL (Slot Lab Composite Events)                                     │
// │  └─ Consumer<MiddlewareProvider> → watches same compositeEvents              │
// │     └─ Automatically synced — no manual sync needed                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// KEY FUNCTIONS:
// - _buildProjectTree()         → Left panel event tree (accepts compositeEvents param)
// - _buildLayersAsActionsTable()→ Center panel layers with Actions UI appearance
// - _updateLayer()              → Updates layer via provider, triggers rebuild
// - _duplicateLayer()           → Duplicates layer via provider
// - _deleteLayer()              → Removes layer via provider
// - _showAddLayerToCompositeDialog() → Dialog to add new layer
// - _selectedComposite          → Gets composite event from _selectedEventId
// - _selectedLayer              → Gets selected layer from composite
// - _updateSelectedLayer()      → Updates layer field via MiddlewareProvider
// - _buildInspectorSections()   → Inspector connected to _selectedLayer
//
// ID FORMAT:
// - Composite IDs: "event_xxx" (e.g., "event_spin_start")
// - Middleware IDs: "mw_event_xxx" (auto-generated via _syncCompositeToMiddleware)
//
// IMPORTANT: context.watch<MiddlewareProvider>() must be called in build()
// to trigger rebuilds. Passing compositeEvents as parameter ensures this.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/native_file_picker.dart';
import '../services/audio_playback_service.dart';
import '../services/service_locator.dart';
import '../services/unified_search_service.dart';
import '../utils/path_validator.dart';

import '../providers/dsp_chain_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/global_shortcuts_provider.dart';
import '../providers/meter_provider.dart';
import '../providers/middleware_provider.dart';
import '../providers/mixer_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/slot_lab/slot_lab_coordinator.dart';
import '../providers/stage_provider.dart';
import '../services/audio_asset_manager.dart';
import '../models/stage_models.dart' as stage;
import '../models/layout_models.dart';
import '../models/editor_mode_config.dart';
import '../models/middleware_models.dart';
import '../models/slot_audio_events.dart' show SlotCompositeEvent, SlotEventLayer;
import '../widgets/common/audio_waveform_picker_dialog.dart';
import '../models/timeline_models.dart' as timeline;
import '../theme/fluxforge_theme.dart';
import '../widgets/layout/left_zone.dart' show LeftZoneTab;
import '../widgets/layout/project_tree.dart' show ProjectTreeNode, TreeItemType;
import '../widgets/layout/engine_connected_control_bar.dart';
import '../widgets/mixer/pro_mixer_strip.dart';
import '../widgets/mixer/plugin_selector.dart';
import '../models/plugin_models.dart';
// piano_roll.dart is now replaced by midi/piano_roll_widget.dart
import '../widgets/editors/eq_editor.dart' as generic_eq;
import '../widgets/eq/pro_eq_editor.dart' as rf_eq;
import '../widgets/layout/right_zone.dart' show InspectedObjectType;
import '../widgets/tabs/tab_placeholders.dart';
import '../widgets/timeline/timeline.dart' as timeline_widget;
import '../widgets/spectrum/spectrum_analyzer.dart';
import '../widgets/meters/loudness_meter.dart';
import '../widgets/meters/pro_metering_panel.dart';
import '../widgets/eq/pultec_eq.dart';
import '../widgets/eq/api550_eq.dart';
import '../widgets/eq/neve1073_eq.dart';
import '../widgets/common/context_menu.dart';
import '../widgets/editor/clip_editor.dart' as clip_editor;
import '../widgets/editors/crossfade_editor.dart';
import '../widgets/timeline/automation_lane.dart';
import 'slot_lab_screen.dart';
import '../widgets/dsp/time_stretch_panel.dart';
import '../widgets/dsp/delay_panel.dart';
import '../widgets/dsp/dynamics_panel.dart';
import '../widgets/dsp/spatial_panel.dart';
import '../widgets/dsp/spectral_panel.dart';
import '../widgets/dsp/pitch_correction_panel.dart';
import '../widgets/dsp/transient_panel.dart';
import '../widgets/dsp/multiband_panel.dart';
import '../widgets/dsp/saturation_panel.dart';
import '../widgets/dsp/sidechain_panel.dart';
import '../widgets/dsp/channel_strip_panel.dart';
import '../widgets/dsp/ml_processor_panel.dart';
import '../widgets/dsp/mastering_panel.dart';
import '../widgets/dsp/restoration_panel.dart';
import '../widgets/dsp/internal_processor_editor_window.dart';
import '../widgets/fabfilter/fabfilter.dart';
import '../widgets/midi/piano_roll_widget.dart';
import '../widgets/mixer/ultimate_mixer.dart' as ultimate;
import '../widgets/mixer/control_room_panel.dart' as control_room;
import '../widgets/input_bus/input_bus_panel.dart' as input_bus;
import '../widgets/recording/recording_panel.dart' as recording;
import '../widgets/routing/routing_panel.dart' as routing;
import '../widgets/plugin/plugin_browser.dart';
import '../widgets/metering/metering_bridge.dart';
import '../src/rust/engine_api.dart';
import '../src/rust/native_ffi.dart';
import '../services/waveform_cache.dart';
import '../dialogs/export_audio_dialog.dart';
import '../dialogs/batch_export_dialog.dart';
import '../dialogs/export_presets_dialog.dart';
import '../dialogs/bounce_dialog.dart';
import '../dialogs/render_in_place_dialog.dart';
import 'settings/audio_settings_screen.dart';
import 'settings/midi_settings_screen.dart';
import 'settings/plugin_manager_screen.dart';
import 'settings/shortcuts_settings_screen.dart';
import 'project/project_settings_screen.dart';
import 'main_layout.dart';
import '../widgets/project/track_templates_panel.dart';
import '../widgets/project/project_versions_panel.dart';
import '../widgets/timeline/freeze_track_overlay.dart';
import '../widgets/browser/audio_pool_panel.dart';
import '../providers/undo_manager.dart';
import '../widgets/middleware/events_folder_panel.dart';
import '../widgets/middleware/event_editor_panel.dart';
import '../widgets/ale/ale_panel.dart';
import '../services/unified_playback_controller.dart';
import '../providers/timeline_playback_provider.dart';
// P3 Future Services and Widgets
import '../services/cloud_sync_service.dart';
import '../services/ai_mixing_service.dart';
import '../widgets/common/collaboration_panel.dart';
import '../widgets/common/asset_cloud_panel.dart';
import '../widgets/common/marketplace_panel.dart';
import '../widgets/common/crdt_sync_panel.dart';
// Section-specific Lower Zone imports (DAW and Middleware)
// SlotLab uses its own fullscreen layout with dedicated bottom panel
import '../widgets/lower_zone/daw_lower_zone_widget.dart';
import '../widgets/lower_zone/daw_lower_zone_controller.dart';
import '../widgets/lower_zone/lower_zone_types.dart';
import '../widgets/lower_zone/middleware_lower_zone_widget.dart';
import '../widgets/lower_zone/middleware_lower_zone_controller.dart';

/// PERFORMANCE: Data class for Timeline Selector - only rebuilds when transport values change
class _TimelineTransportData {
  final double playheadPosition;
  final bool isPlaying;
  final bool loopEnabled;
  final double tempo;
  final int timeSigNum;
  final int timeSigDenom;

  const _TimelineTransportData({
    required this.playheadPosition,
    required this.isPlaying,
    required this.loopEnabled,
    required this.tempo,
    required this.timeSigNum,
    required this.timeSigDenom,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _TimelineTransportData &&
        other.playheadPosition == playheadPosition &&
        other.isPlaying == isPlaying &&
        other.loopEnabled == loopEnabled &&
        other.tempo == tempo &&
        other.timeSigNum == timeSigNum &&
        other.timeSigDenom == timeSigDenom;
  }

  @override
  int get hashCode => Object.hash(
        playheadPosition,
        isPlaying,
        loopEnabled,
        tempo,
        timeSigNum,
        timeSigDenom,
      );
}

class EngineConnectedLayout extends StatefulWidget {
  final String? projectName;
  final VoidCallback? onBackToLauncher;
  final EditorMode? initialEditorMode;

  const EngineConnectedLayout({
    super.key,
    this.projectName,
    this.onBackToLauncher,
    this.initialEditorMode,
  });

  @override
  State<EngineConnectedLayout> createState() => _EngineConnectedLayoutState();
}

class _EngineConnectedLayoutState extends State<EngineConnectedLayout>
    with WidgetsBindingObserver {
  // Native menu channel
  static const _menuChannel = MethodChannel('fluxforge/menu');

  // Zone state
  bool _leftVisible = true;
  bool _rightVisible = true;
  bool _lowerVisible = true;
  late String _activeLowerTab;
  LeftZoneTab _activeLeftTab = LeftZoneTab.project;

  // Section-specific Lower Zone controllers (DAW and Middleware)
  // SlotLab uses its own fullscreen layout with dedicated bottom panel
  late final DawLowerZoneController _dawLowerZoneController;
  late final MiddlewareLowerZoneController _middlewareLowerZoneController;

  // Local UI state
  late EditorMode _editorMode;
  TimeDisplayMode _timeDisplayMode = TimeDisplayMode.bars;
  bool _metronomeEnabled = false;
  bool _snapEnabled = true;
  double _snapValue = 1;
  bool _tripletGrid = false; // P0.2: Triplet grid mode

  // Analog EQ state
  int _selectedAnalogEq = 0; // 0=Pultec, 1=API, 2=Neve
  PultecParams _pultecParams = const PultecParams();
  Api550Params _apiParams = const Api550Params();
  Neve1073Params _neveParams = const Neve1073Params();

  // Timeline state
  double _timelineZoom = 50; // pixels per second
  double _timelineScrollOffset = 0;
  List<timeline.TimelineTrack> _tracks = [];
  List<timeline.TimelineClip> _clips = [];
  List<timeline.TimelineMarker> _markers = [];
  List<timeline.Crossfade> _crossfades = [];
  timeline.LoopRegion? _loopRegion;

  // Event-centric timeline state
  List<timeline.TimelineEventFilter> _eventFilters = [];
  String? _currentEventId; // null = show all clips (no filter)

  // Stage markers from game engine (shown on timeline ruler)
  List<timeline.StageMarker> _stageMarkers = [];

  // Audio Pool - Cubase-style imported files (not on timeline yet)
  List<timeline.PoolAudioFile> _audioPool = [];
  String? _selectedPoolFileId;

  // Dynamic data for project tree
  List<String> _timelineTracks = [];

  // Routes/events from imported JSON (middleware mode)
  List<String> _routeEvents = [];

  // Middleware state - Full event/action management
  List<MiddlewareEvent> _middlewareEvents = [];
  String _selectedEventId = '';
  int _selectedActionIndex = -1;
  int _selectedLayerIndex = -1; // For SlotCompositeEvent layers
  bool _middlewareGridView = false; // false = list view, true = grid view

  // Middleware Timeline state
  double _middlewareTimelineZoom = 1.0;
  double _middlewarePlayheadPosition = 0.0; // In seconds
  final ScrollController _middlewareTimelineScrollController = ScrollController();
  static const double _kMiddlewarePixelsPerSecond = 100.0;
  static const double _kMiddlewareTrackHeight = 48.0;
  static const double _kMiddlewareRulerHeight = 24.0;
  static const double _kMiddlewareTrackHeaderWidth = 140.0;

  // Current action being edited (header controls)
  String _headerActionType = 'Play';
  String _headerAssetId = ''; // Empty by default - user selects from imported sounds
  String _headerBus = 'Music';
  String _headerScope = 'Global';
  String _headerPriority = 'Normal';
  String _headerFadeCurve = 'Linear';
  double _headerFadeTime = 0.1;
  double _headerGain = 1.0;
  double _headerPan = 0.0;  // -1.0 (L) to 1.0 (R), 0.0 = Center
  double _headerDelay = 0.0;
  bool _headerLoop = false;
  // NEW: FadeIn/FadeOut/Trim/AudioPath controls
  double _headerFadeInMs = 0.0;
  double _headerFadeOutMs = 0.0;
  CrossfadeCurve _headerFadeInCurve = CrossfadeCurve.linear;
  CrossfadeCurve _headerFadeOutCurve = CrossfadeCurve.linear;
  double _headerTrimStartMs = 0.0;
  double _headerTrimEndMs = 0.0;
  String _headerAudioPath = '';

  // Loudness meter state
  LoudnessTarget _loudnessTarget = LoudnessTarget.streaming;

  // Selected track for Channel tab (DAW mode)
  String? _selectedTrackId;

  // Selected event for timeline (middleware mode)
  String? _selectedEventForTimeline;

  // Track action count for auto-sync (when event changes externally)
  int _lastSyncedActionCount = 0;

  // Floating EQ windows - key is channel/bus ID
  final Map<String, bool> _openEqWindows = {};

  // Clip resize throttle - prevent FFI spam during drag
  Timer? _resizeThrottleTimer;
  Map<String, dynamic>? _pendingResize;

  // Analysis state (Transient/Pitch detection)
  double _transientSensitivity = 0.5;
  int _transientAlgorithm = 2; // 0=Energy, 1=Spectral, 2=Enhanced, 3=Onset, 4=ML
  // Analysis state - used by transient/pitch detection UI (future)
  // ignore: unused_field
  double _detectedPitch = 0.0;
  // ignore: unused_field
  int _detectedMidi = -1;
  // ignore: unused_field
  List<int> _detectedTransients = [];

  // Clip Editor Hitpoint state (Cubase-style sample editor)
  List<clip_editor.Hitpoint> _clipHitpoints = [];
  bool _showClipHitpoints = false;
  double _clipHitpointSensitivity = 0.5;
  clip_editor.HitpointAlgorithm _clipHitpointAlgorithm = clip_editor.HitpointAlgorithm.enhanced;

  // Audition state (Cubase-style clip preview)
  bool _isAuditioning = false;

  // Control Room state (now managed by ControlRoomProvider)

  /// Build mode-aware project tree (matches React LayoutDemo.tsx 1:1)
  ///
  /// MIDDLEWARE SYNC: `compositeEvents` must be passed from build() where
  /// `context.watch[MiddlewareProvider]()` is called. This ensures UI rebuilds
  /// when layers are added/modified. Do NOT call context.watch inside this method.
  List<ProjectTreeNode> _buildProjectTree(List<SlotCompositeEvent> compositeEvents) {
    final List<ProjectTreeNode> tree = [];

    if (_editorMode == EditorMode.daw) {
      // ========== DAW MODE: Cubase-style project browser ==========

      // Audio Pool (imported files) - Cubase-style, files go here first
      // Double-click or drag to add to timeline
      tree.add(ProjectTreeNode(
        id: 'audio-pool',
        type: TreeItemType.folder,
        label: 'Audio Pool',
        count: _audioPool.length,
        children: _audioPool
            .map((file) => ProjectTreeNode(
                  id: 'pool-${file.id}',
                  type: TreeItemType.sound,
                  label: file.name,
                  duration: file.durationFormatted,
                  isSelected: file.id == _selectedPoolFileId,
                  isDraggable: true,
                  data: file, // Pass the PoolAudioFile for drag/drop
                ))
            .toList(),
      ));

      // Tracks folder - starts empty like React
      tree.add(ProjectTreeNode(
        id: 'tracks',
        type: TreeItemType.folder,
        label: 'Tracks',
        count: _timelineTracks.length,
        children: _timelineTracks
            .map((name) => ProjectTreeNode(
                  id: 'track-$name',
                  type: TreeItemType.sound,
                  label: name,
                ))
            .toList(),
      ));

      // MixConsole (Buses) - starts empty, user creates buses
      // No placeholder buses - only show buses user creates in DAW
      tree.add(const ProjectTreeNode(
        id: 'mixconsole',
        type: TreeItemType.folder,
        label: 'MixConsole',
        count: 0,
        children: [],
      ));

      // Markers - starts empty
      tree.add(const ProjectTreeNode(
        id: 'markers',
        type: TreeItemType.folder,
        label: 'Markers',
        count: 0,
        children: [],
      ));

    } else {
      // ========== MIDDLEWARE MODE: Wwise-style event browser ==========

      // Events folder - uses compositeEvents passed from build()
      tree.add(ProjectTreeNode(
        id: 'events',
        type: TreeItemType.folder,
        label: 'Events',
        count: compositeEvents.length,
        children: compositeEvents
            .map((event) => ProjectTreeNode(
                  id: 'evt-${event.id}',
                  type: TreeItemType.event,
                  label: '${event.name} (${event.layers.length})',
                ))
            .toList(),
      ));

      // Buses - always 5 buses
      tree.add(const ProjectTreeNode(
        id: 'buses',
        type: TreeItemType.folder,
        label: 'Buses',
        count: 5,
        children: [
          ProjectTreeNode(id: 'bus-master', type: TreeItemType.bus, label: 'Master'),
          ProjectTreeNode(id: 'bus-sfx', type: TreeItemType.bus, label: 'SFX'),
          ProjectTreeNode(id: 'bus-music', type: TreeItemType.bus, label: 'Music'),
          ProjectTreeNode(id: 'bus-voice', type: TreeItemType.bus, label: 'Voice'),
          ProjectTreeNode(id: 'bus-ui', type: TreeItemType.bus, label: 'UI'),
        ],
      ));

      // Game Syncs - States (fixed 3 like React)
      tree.add(const ProjectTreeNode(
        id: 'states',
        type: TreeItemType.folder,
        label: 'States',
        count: 3,
        children: [
          ProjectTreeNode(id: 'state-gameplay', type: TreeItemType.state, label: 'Gameplay'),
          ProjectTreeNode(id: 'state-menu', type: TreeItemType.state, label: 'Menu'),
          ProjectTreeNode(id: 'state-cutscene', type: TreeItemType.state, label: 'Cutscene'),
        ],
      ));

      // Game Syncs - Switches (fixed 2 like React)
      tree.add(const ProjectTreeNode(
        id: 'switches',
        type: TreeItemType.folder,
        label: 'Switches',
        count: 2,
        children: [
          ProjectTreeNode(id: 'switch-surface', type: TreeItemType.switch_, label: 'Surface Type'),
          ProjectTreeNode(id: 'switch-weather', type: TreeItemType.switch_, label: 'Weather'),
        ],
      ));

      // Audio Files - same as DAW audio pool
      tree.add(ProjectTreeNode(
        id: 'audio-files',
        type: TreeItemType.folder,
        label: 'Audio Files',
        count: _audioPool.length,
        children: _audioPool
            .map((file) => ProjectTreeNode(
                  id: 'pool-${file.id}',
                  type: TreeItemType.sound,
                  label: file.name,
                  duration: file.durationFormatted,
                  isDraggable: true,
                  data: file,
                ))
            .toList(),
      ));
    }

    return tree;
  }

  /// Convert FadeCurve enum to int for engine FFI
  /// Engine uses: 0=Linear, 1=EqualPower (sCurve), 2=SCurve, etc.
  int _curveToInt(FadeCurve curve) {
    switch (curve) {
      case FadeCurve.linear:
        return 0;
      case FadeCurve.sCurve:
        return 1; // Engine "EqualPower"
      case FadeCurve.exp1:
      case FadeCurve.exp3:
        return 2; // Exponential
      case FadeCurve.log1:
      case FadeCurve.log3:
        return 3; // Logarithmic
      case FadeCurve.sine:
        return 4;
      case FadeCurve.invSCurve:
        return 5;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set initial editor mode (from widget parameter or default to DAW)
    _editorMode = widget.initialEditorMode ?? EditorMode.daw;

    // Set default tab based on initial mode
    _activeLowerTab = getDefaultTabForMode(_editorMode);

    // Initialize Section-specific Lower Zone controllers (DAW and Middleware)
    _dawLowerZoneController = DawLowerZoneController();
    _middlewareLowerZoneController = MiddlewareLowerZoneController();

    // Load Lower Zone states from persistent storage
    // If no persisted state, set height to half screen in addPostFrameCallback
    _dawLowerZoneController.loadFromStorage().then((hadPersistedState) {
      if (!hadPersistedState && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final screenHeight = MediaQuery.of(context).size.height;
            _dawLowerZoneController.setHeightToHalfScreen(screenHeight);
          }
        });
      }
    });
    _middlewareLowerZoneController.loadFromStorage().then((hadPersistedState) {
      if (!hadPersistedState && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final screenHeight = MediaQuery.of(context).size.height;
            _middlewareLowerZoneController.setHeightToHalfScreen(screenHeight);
          }
        });
      }
    });

    // Initialize empty timeline (no demo data)
    _initEmptyTimeline();

    // Initialize demo middleware data (for Middleware tab only)
    _initDemoMiddlewareData();

    // Setup native menu handler (macOS menu bar)
    _setupNativeMenuHandler();

    // Register meters and setup shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final meters = context.read<MeterProvider>();
      meters.registerMeter('master');
      meters.registerMeter('sfx');
      meters.registerMeter('music');
      meters.registerMeter('voice');

      // Register EventSearchProvider (P1.1)
      _registerEventSearchProvider();

      // Initialize P2 search providers with data callbacks
      _initializeP2SearchProviders();

      // Wire up all keyboard shortcuts
      final shortcuts = context.read<GlobalShortcutsProvider>();
      final engine = context.read<EngineProvider>();

      // File menu shortcuts
      shortcuts.actions.onNew = () => _handleNewProject(engine);
      shortcuts.actions.onOpen = () => _handleOpenProject(engine);
      shortcuts.actions.onSave = () => _handleSaveProject(engine);
      shortcuts.actions.onSaveAs = () => _handleSaveProjectAs(engine);
      shortcuts.actions.onImportJSON = _handleImportJSON;
      shortcuts.actions.onExportJSON = _handleExportJSON;
      shortcuts.actions.onImportAudioFolder = _handleImportAudioFolder;
      shortcuts.actions.onImportAudioFiles = _openFilePicker;
      shortcuts.actions.onExport = _handleExportAudio;
      shortcuts.actions.onBatchExport = _handleBatchExport;
      shortcuts.actions.onBounceToFile = _handleBounce;
      shortcuts.actions.onRenderInPlace = _handleRenderInPlace;

      // View panel shortcuts
      shortcuts.actions.onToggleLeftPanel = () => setState(() => _leftVisible = !_leftVisible);
      shortcuts.actions.onToggleRightPanel = () => setState(() => _rightVisible = !_rightVisible);
      shortcuts.actions.onToggleLowerPanel = () => setState(() => _lowerVisible = !_lowerVisible);
      shortcuts.actions.onShowAudioPool = _handleShowAudioPool;
      shortcuts.actions.onShowMarkers = _handleShowMarkers;
      shortcuts.actions.onShowMidiEditor = _handleShowMidiEditor;
      shortcuts.actions.onResetLayout = _handleResetLayout;

      // Project menu shortcuts
      shortcuts.actions.onProjectSettings = _handleProjectSettings;
      shortcuts.actions.onTrackTemplates = _handleTrackTemplates;
      shortcuts.actions.onVersionHistory = _handleVersionHistory;
      shortcuts.actions.onFreezeSelectedTracks = _handleFreezeSelectedTracks;
      shortcuts.actions.onValidateProject = _handleValidateProject;
      shortcuts.actions.onBuildProject = _handleBuildProject;

      // Studio menu shortcuts
      shortcuts.actions.onAudioSettings = _handleAudioSettings;
      shortcuts.actions.onMidiSettings = _handleMidiSettings;
      shortcuts.actions.onPluginManager = _handlePluginManager;
      shortcuts.actions.onKeyboardShortcuts = _handleKeyboardShortcuts;

      // Advanced panel shortcuts (Shift+Cmd)
      shortcuts.actions.onShowLogicalEditor = () => _showAdvancedPanel('logical-editor');
      shortcuts.actions.onShowScaleAssistant = () => _showAdvancedPanel('scale-assistant');
      shortcuts.actions.onShowGrooveQuantize = () => _showAdvancedPanel('groove-quantize');
      shortcuts.actions.onShowAudioAlignment = () => _showAdvancedPanel('audio-alignment');
      shortcuts.actions.onShowTrackVersions = () => _showAdvancedPanel('track-versions');
      shortcuts.actions.onShowMacroControls = () => _showAdvancedPanel('macro-controls');
      shortcuts.actions.onShowClipGainEnvelope = () => _showAdvancedPanel('clip-gain-envelope');

      // Listen to StageProvider for live game engine events
      final stageProvider = context.read<StageProvider>();
      stageProvider.addListener(_onStageEventsChanged);

      // Initialize StageAudioMapper — connects STAGES protocol to Middleware audio
      // This must happen AFTER providers are available but BEFORE live events arrive
      final middleware = context.read<MiddlewareProvider>();
      stageProvider.initializeAudioMapper(middleware);

      // Listen to MiddlewareProvider for Events Folder selection sync
      middleware.addListener(_onMiddlewareSelectionChanged);

      // Set up bidirectional sync: Mixer channel order → Timeline track order
      final mixerProvider = context.read<MixerProvider>();
      mixerProvider.onChannelOrderChanged = _onMixerChannelOrderChanged;
    });
  }

  /// Handle mixer channel reorder → sync to timeline tracks
  void _onMixerChannelOrderChanged(List<String> channelIds) {
    if (!mounted) return;
    // Map channel IDs back to track IDs (ch_xxx → xxx)
    final trackIds = channelIds
        .where((id) => id.startsWith('ch_'))
        .map((id) => id.substring(3)) // Remove 'ch_' prefix
        .toList();

    // Reorder _tracks to match the new channel order
    final newTracks = <timeline.TimelineTrack>[];
    for (final trackId in trackIds) {
      final track = _tracks.firstWhere(
        (t) => t.id == trackId,
        orElse: () => _tracks.first,
      );
      newTracks.add(track);
    }

    // Add any tracks that aren't in the channel order (shouldn't happen, but defensive)
    for (final track in _tracks) {
      if (!newTracks.contains(track)) {
        newTracks.add(track);
      }
    }

    setState(() {
      _tracks = newTracks;
    });
  }

  /// Sync Events Folder selection → center panel dropdown
  void _onMiddlewareSelectionChanged() {
    if (!mounted) return;
    final middleware = context.read<MiddlewareProvider>();
    final selectedCompositeId = middleware.selectedCompositeEventId;

    if (selectedCompositeId != null && selectedCompositeId.isNotEmpty) {
      // Convert composite ID to middleware event ID
      final middlewareEventId = 'mw_$selectedCompositeId';

      // Update center panel selection
      if (_selectedEventId != middlewareEventId) {
        final composite = middleware.compositeEvents
            .where((e) => e.id == selectedCompositeId)
            .firstOrNull;
        setState(() {
          _selectedEventId = middlewareEventId;
          _selectedActionIndex = -1;
          // Auto-select first layer so header/inspector controls work
          _selectedLayerIndex = (composite != null && composite.layers.isNotEmpty) ? 0 : -1;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncHeaderFromSelectedLayer();
        });
      }
    }
  }

  /// Convert StageProvider events to timeline StageMarkers
  void _onStageEventsChanged() {
    final stageProvider = context.read<StageProvider>();
    final events = stageProvider.liveEvents;

    setState(() {
      _stageMarkers = events.map((e) => _stageEventToMarker(e)).toList();
    });
  }

  /// Convert a StageEvent to a StageMarker for timeline display
  timeline.StageMarker _stageEventToMarker(stage.StageEvent event) {
    // Determine marker type based on stage type
    final markerType = _getMarkerTypeForStage(event.stage);
    final color = timeline.stageMarkerTypeColor(markerType);

    return timeline.StageMarker(
      id: 'stage_${event.timestampMs.toInt()}',
      time: event.timestampMs / 1000.0, // Convert ms to seconds
      stageName: event.typeName,
      type: markerType,
      color: color,
    );
  }

  /// Map Stage type to StageMarkerType
  timeline.StageMarkerType _getMarkerTypeForStage(stage.Stage stg) {
    final typeName = stg.typeName.toLowerCase();
    if (typeName.contains('spin')) return timeline.StageMarkerType.spin;
    if (typeName.contains('win')) return timeline.StageMarkerType.win;
    if (typeName.contains('feature')) return timeline.StageMarkerType.feature;
    if (typeName.contains('bonus')) return timeline.StageMarkerType.bonus;
    if (typeName.contains('jackpot')) return timeline.StageMarkerType.jackpot;
    return timeline.StageMarkerType.generic;
  }

  /// Setup handler for native macOS menu bar actions
  void _setupNativeMenuHandler() {
    _menuChannel.setMethodCallHandler((call) async {
      if (call.method == 'menuAction') {
        final action = call.arguments as String;
        _handleNativeMenuAction(action);
      }
    });
  }

  /// Handle action from native macOS menu bar
  void _handleNativeMenuAction(String action) {
    final callbacks = _buildMenuCallbacks();

    switch (action) {
      // FILE MENU
      case 'newProject':
        callbacks.onNewProject?.call();
      case 'openProject':
        callbacks.onOpenProject?.call();
      case 'save':
        callbacks.onSaveProject?.call();
      case 'saveAs':
        callbacks.onSaveProjectAs?.call();
      case 'importJSON':
        callbacks.onImportJSON?.call();
      case 'exportJSON':
        callbacks.onExportJSON?.call();
      case 'importAudioFolder':
        callbacks.onImportAudioFolder?.call();
      case 'importAudioFiles':
        callbacks.onImportAudioFiles?.call();
      case 'exportAudio':
        callbacks.onExportAudio?.call();
      case 'batchExport':
        callbacks.onBatchExport?.call();
      case 'exportPresets':
        callbacks.onExportPresets?.call();
      case 'bounce':
        callbacks.onBounce?.call();
      case 'renderInPlace':
        callbacks.onRenderInPlace?.call();

      // EDIT MENU
      case 'undo':
        callbacks.onUndo?.call();
      case 'redo':
        callbacks.onRedo?.call();
      case 'cut':
        callbacks.onCut?.call();
      case 'copy':
        callbacks.onCopy?.call();
      case 'paste':
        callbacks.onPaste?.call();
      case 'delete':
        callbacks.onDelete?.call();
      case 'selectAll':
        callbacks.onSelectAll?.call();

      // VIEW MENU
      case 'toggleLeftPanel':
        callbacks.onToggleLeftPanel?.call();
      case 'toggleRightPanel':
        callbacks.onToggleRightPanel?.call();
      case 'toggleLowerPanel':
        callbacks.onToggleLowerPanel?.call();
      case 'showAudioPool':
        callbacks.onShowAudioPool?.call();
      case 'showMarkers':
        callbacks.onShowMarkers?.call();
      case 'showMidiEditor':
        callbacks.onShowMidiEditor?.call();
      case 'showLogicalEditor':
        callbacks.onShowLogicalEditor?.call();
      case 'showScaleAssistant':
        callbacks.onShowScaleAssistant?.call();
      case 'showGrooveQuantize':
        callbacks.onShowGrooveQuantize?.call();
      case 'showAudioAlignment':
        callbacks.onShowAudioAlignment?.call();
      case 'showTrackVersions':
        callbacks.onShowTrackVersions?.call();
      case 'showMacroControls':
        callbacks.onShowMacroControls?.call();
      case 'showClipGainEnvelope':
        callbacks.onShowClipGainEnvelope?.call();
      case 'resetLayout':
        callbacks.onResetLayout?.call();

      // PROJECT MENU
      case 'projectSettings':
        callbacks.onProjectSettings?.call();
      case 'trackTemplates':
        callbacks.onTrackTemplates?.call();
      case 'versionHistory':
        callbacks.onVersionHistory?.call();
      case 'freezeSelectedTracks':
        callbacks.onFreezeSelectedTracks?.call();
      case 'validateProject':
        callbacks.onValidateProject?.call();
      case 'buildProject':
        callbacks.onBuildProject?.call();

      // STUDIO MENU
      case 'audioSettings':
        callbacks.onAudioSettings?.call();
      case 'midiSettings':
        callbacks.onMidiSettings?.call();
      case 'pluginManager':
        callbacks.onPluginManager?.call();
      case 'keyboardShortcuts':
        callbacks.onKeyboardShortcuts?.call();
    }
  }

  @override
  void dispose() {
    // Remove StageProvider listener
    try {
      final stageProvider = context.read<StageProvider>();
      stageProvider.removeListener(_onStageEventsChanged);
    } catch (_) {
      // Provider may not be available during dispose
    }
    // Remove MiddlewareProvider listener
    try {
      final middleware = context.read<MiddlewareProvider>();
      middleware.removeListener(_onMiddlewareSelectionChanged);
    } catch (_) {
      // Provider may not be available during dispose
    }
    // Remove MixerProvider channel order callback
    try {
      final mixerProvider = context.read<MixerProvider>();
      mixerProvider.onChannelOrderChanged = null;
    } catch (_) {
      // Provider may not be available during dispose
    }
    // Dispose Lower Zone controllers
    _dawLowerZoneController.dispose();
    _middlewareLowerZoneController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // macOS window restored from minimize — reset focus to prevent UI blocking.
      // Without this, stale FocusNodes or modal barriers can absorb all input.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Pop any stale dialogs/overlays that survived minimization
        final nav = Navigator.of(context, rootNavigator: true);
        while (nav.canPop()) {
          nav.pop();
        }
        // Reset focus to root scope so input isn't trapped
        FocusScope.of(context).unfocus();
        FocusScope.of(context).requestFocus();
      });
    }
  }

  void _initEmptyTimeline() {
    // Start with empty tracks - user will add tracks and import audio
    _tracks = [];
    _clips = [];
    _markers = [];
    _crossfades = [];
    _loopRegion = const timeline.LoopRegion(start: 0.0, end: 8.0);
    _eventFilters = [];
    _currentEventId = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH PROVIDER REGISTRATION (P1.1)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register EventSearchProvider with callback to access MiddlewareProvider
  void _registerEventSearchProvider() {
    final search = sl<UnifiedSearchService>();
    final middleware = context.read<MiddlewareProvider>();

    // Create and initialize EventSearchProvider
    final eventProvider = EventSearchProvider();
    eventProvider.init(
      getEvents: () {
        // Convert SlotCompositeEvents to searchable format
        return middleware.compositeEvents.map((event) {
          return {
            'id': event.id,
            'name': event.name,
            'stages': event.triggerStages,
            'layers': event.layers.map((l) => {
              'audioPath': l.audioPath,
              'busId': l.busId,
            }).toList(),
            'containerType': event.containerType.name,
          };
        }).toList();
      },
      onEventSelect: () {
        // Navigation handled by search result onSelect
      },
    );

    search.registerProvider(eventProvider);
  }

  /// Initialize P2 search providers with data callbacks (P2.1, P2.2, P2.3)
  void _initializeP2SearchProviders() {
    final search = sl<UnifiedSearchService>();
    final middleware = context.read<MiddlewareProvider>();
    final assetManager = sl<AudioAssetManager>();

    // P2.1: Initialize FileSearchProvider
    final fileProvider = search.getProvider<FileSearchProvider>();
    if (fileProvider != null) {
      fileProvider.init(
        getAssets: () {
          return assetManager.assets.map((asset) => {
            'path': asset.path,
            'name': asset.name,
            'folder': asset.folder,
            'duration': (asset.duration * 1000).round(), // seconds → ms
            'sampleRate': asset.sampleRate,
            'channels': asset.channels,
          }).toList();
        },
        onFileSelect: (path) {
          // Could navigate to asset browser or import
        },
      );
    }

    // P2.2: Initialize TrackSearchProvider
    final trackProvider = search.getProvider<TrackSearchProvider>();
    if (trackProvider != null) {
      trackProvider.init(
        getTracks: () {
          // Return DAW tracks from timeline
          return _tracks.map((track) => {
            'id': track.id,
            'name': track.name,
            'type': track.trackType.name,
            'isMuted': track.muted,
            'isSolo': track.soloed,
            'isArmed': track.armed,
          }).toList();
        },
        onTrackSelect: (trackId) {
          setState(() {
            _selectedTrackId = trackId;
          });
        },
      );
    }

    // P2.3: Initialize PresetSearchProvider
    final presetProvider = search.getProvider<PresetSearchProvider>();
    if (presetProvider != null) {
      presetProvider.init(
        getPresets: () {
          // Return DSP presets from middleware
          // For now, return blend/random/sequence containers as "presets"
          final presets = <Map<String, dynamic>>[];

          // Add blend containers
          for (final blend in middleware.blendContainers) {
            presets.add({
              'id': 'blend_${blend.id}',
              'name': blend.name,
              'plugin': 'Blend Container',
              'category': 'Containers',
            });
          }

          // Add random containers
          for (final random in middleware.randomContainers) {
            presets.add({
              'id': 'random_${random.id}',
              'name': random.name,
              'plugin': 'Random Container',
              'category': 'Containers',
            });
          }

          // Add sequence containers
          for (final seq in middleware.sequenceContainers) {
            presets.add({
              'id': 'seq_${seq.id}',
              'name': seq.name,
              'plugin': 'Sequence Container',
              'category': 'Containers',
            });
          }

          return presets;
        },
        onPresetSelect: (presetId) {
          // Could open preset editor
        },
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT-CENTRIC TIMELINE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get clips filtered by current event (or all if no event selected)
  List<timeline.TimelineClip> get _filteredClips {
    if (_currentEventId == null) {
      return _clips; // No filter - show all clips
    }
    return _clips.where((c) => c.eventId == _currentEventId).toList();
  }

  /// Create a new event filter
  void _createEventFilter(String name, {String? description}) {
    final colorIndex = _eventFilters.length % timeline.kEventColors.length;
    final filter = timeline.TimelineEventFilter(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      color: timeline.kEventColors[colorIndex],
      createdAt: DateTime.now(),
    );

    setState(() {
      _eventFilters = [..._eventFilters, filter];
      // Auto-select the new event filter
      _currentEventId = filter.id;
    });
  }

  /// Select an event (filters timeline to show only this event's clips)
  void _selectEvent(String? eventId) {
    setState(() {
      _currentEventId = eventId;
    });
  }

  /// Delete an event and optionally its clips
  void _deleteEvent(String eventId, {bool deleteClips = false}) {
    setState(() {
      _eventFilters = _eventFilters.where((e) => e.id != eventId).toList();

      if (deleteClips) {
        // Remove clips belonging to this event
        _clips = _clips.where((c) => c.eventId != eventId).toList();
      } else {
        // Orphan clips - set eventId to null
        _clips = _clips.map((c) {
          if (c.eventId == eventId) {
            return c.copyWith(eventId: null);
          }
          return c;
        }).toList();
      }

      // Clear selection if deleted event was selected
      if (_currentEventId == eventId) {
        _currentEventId = null;
      }
    });
  }

  /// Rename an event
  void _renameEvent(String eventId, String newName) {
    setState(() {
      _eventFilters = _eventFilters.map((e) {
        if (e.id == eventId) {
          return e.copyWith(name: newName);
        }
        return e;
      }).toList();
    });
  }

  /// Assign a clip to an event
  void _assignClipToEvent(String clipId, String? eventId) {
    setState(() {
      _clips = _clips.map((c) {
        if (c.id == clipId) {
          return c.copyWith(eventId: eventId);
        }
        return c;
      }).toList();
    });
  }

  /// Assign all selected clips to current event
  void _assignSelectedClipsToCurrentEvent() {
    if (_currentEventId == null) return;

    setState(() {
      _clips = _clips.map((c) {
        if (c.selected) {
          return c.copyWith(eventId: _currentEventId);
        }
        return c;
      }).toList();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Default track color - all new tracks use this (Cubase style)
  static Color get _defaultTrackColor => FluxForgeTheme.trackBlue;

  /// Add a new track
  void _handleAddTrack() {
    final trackIndex = _tracks.length;
    final color = _defaultTrackColor;
    final trackName = 'Audio ${trackIndex + 1}';
    final trackId = engine.createTrack(
      name: trackName,
      color: color.value,
      busId: 0, // Master
    );

    // Create corresponding mixer channel (Cubase-style auto-fader)
    // Empty tracks default to stereo
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.createChannelFromTrack(trackId, trackName, color, channels: 2);

    setState(() {
      _tracks = [
        ..._tracks,
        timeline.TimelineTrack(
          id: trackId,
          name: trackName,
          color: color,
          outputBus: timeline.OutputBus.master,
          channels: 2, // Empty tracks default to stereo
        ),
      ];
    });
  }

  /// Delete a track
  void _handleDeleteTrack(String trackId) {
    EngineApi.instance.deleteTrack(trackId);

    // Remove mixer channel (Cubase-style: track delete = fader delete)
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.deleteChannel('ch_$trackId');

    // In middleware mode, sync deletion to event actions
    final isMiddlewareTrack = _editorMode == EditorMode.middleware && trackId.startsWith('evt_track_');
    if (isMiddlewareTrack) {
      _syncTrackDeletionToEvent(trackId);
    }

    setState(() {
      _tracks = _tracks.where((t) => t.id != trackId).toList();
      _clips = _clips.where((c) => c.trackId != trackId).toList();
    });

    // After syncing, reload timeline to update indices
    if (isMiddlewareTrack && _selectedEventId.isNotEmpty) {
      Future.microtask(() => _loadEventToTimeline(_selectedEventId));
    }
  }

  /// Delete track by ID (alias for timeline callback)
  void _handleDeleteTrackById(String trackId) => _handleDeleteTrack(trackId);

  /// Handle track reorder (bidirectional sync with mixer channels)
  void _handleTrackReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tracks.length) return;
    if (newIndex < 0 || newIndex >= _tracks.length) return;
    if (oldIndex == newIndex) return;

    // Reorder tracks list
    setState(() {
      final track = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, track);
    });

    // Sync to MixerProvider (bidirectional sync with mixer)
    // Channel IDs are prefixed with 'ch_' followed by track ID
    final mixerProvider = context.read<MixerProvider>();
    final newChannelOrder = _tracks.map((t) => 'ch_${t.id}').toList();
    mixerProvider.setChannelOrder(newChannelOrder, notifyTimeline: false);
  }

  /// Sync track deletion to middleware event (removes corresponding action)
  void _syncTrackDeletionToEvent(String trackId) {
    // Extract action index from track ID (evt_track_0 → 0)
    final indexStr = trackId.substring('evt_track_'.length);
    final actionIndex = int.tryParse(indexStr) ?? -1;
    if (actionIndex < 0) return;

    final event = _selectedEvent;
    if (event == null || actionIndex >= event.actions.length) return;

    final actionToRemove = event.actions[actionIndex];
    final eventId = _selectedEventId;

    // Update local state
    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == eventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          if (actionIndex < newActions.length) {
            newActions.removeAt(actionIndex);
          }
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();
      // Reset selection
      _selectedActionIndex = -1;
    });

    // Sync to MiddlewareProvider → triggers SlotLab sync
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.removeActionFromEvent(eventId, actionToRemove.id);
  }

  /// Sync clip deletion to middleware event (removes corresponding action)
  void _syncClipDeletionToEvent(String clipId) {
    // Extract action index from clip ID (evt_clip_0 → 0)
    if (!clipId.startsWith('evt_clip_')) return;

    final indexStr = clipId.substring('evt_clip_'.length);
    final actionIndex = int.tryParse(indexStr) ?? -1;
    if (actionIndex < 0) return;

    final event = _selectedEvent;
    if (event == null || actionIndex >= event.actions.length) return;

    final actionToRemove = event.actions[actionIndex];
    final eventId = _selectedEventId;

    // Update local state
    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == eventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          if (actionIndex < newActions.length) {
            newActions.removeAt(actionIndex);
          }
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();
      // Reset selection
      _selectedActionIndex = -1;
    });

    // Sync to MiddlewareProvider → triggers SlotLab sync
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.removeActionFromEvent(eventId, actionToRemove.id);
  }

  /// Duplicate a track with all its clips
  void _handleDuplicateTrack(String trackId) {
    final track = _tracks.firstWhere((t) => t.id == trackId);
    final trackClips = _clips.where((c) => c.trackId == trackId).toList();

    // Create new track with unique ID
    final newTrackId = 'track-${DateTime.now().millisecondsSinceEpoch}';
    final newTrack = track.copyWith(id: newTrackId, name: '${track.name} (copy)');

    // Duplicate clips
    final newClips = trackClips.map((c) => c.copyWith(
      id: '${c.id}-copy-${DateTime.now().millisecondsSinceEpoch}',
      trackId: newTrackId,
    )).toList();

    setState(() {
      _tracks = [..._tracks, newTrack];
      _clips = [..._clips, ...newClips];
    });

    // Create mixer channel for the duplicated track (same channel count as original)
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.createChannelFromTrack(newTrackId, newTrack.name, track.color, channels: track.channels);

    _showSnackBar('Track duplicated');
  }

  /// Show track context menu with Cubase-style options
  void _showTrackContextMenu(String trackId, Offset position) {
    final track = _tracks.firstWhere((t) => t.id == trackId);

    final menuItems = ContextMenus.track(
      onRename: () {
        // TODO: Show rename dialog
      },
      onDuplicate: () {
        _handleDuplicateTrack(trackId);
      },
      onMute: () {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) return t.copyWith(muted: !t.muted);
            return t;
          }).toList();
        });
      },
      onSolo: () {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) return t.copyWith(soloed: !t.soloed);
            return t;
          }).toList();
        });
      },
      onFreeze: () {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) return t.copyWith(frozen: !t.frozen);
            return t;
          }).toList();
        });
      },
      onColor: () {
        _showTrackColorPicker(trackId, track.color);
      },
      onDelete: () {
        _handleDeleteTrack(trackId);
      },
      isMuted: track.muted,
      isSoloed: track.soloed,
      isFrozen: track.frozen,
    );

    showContextMenu(
      context: context,
      position: position,
      items: menuItems,
    );
  }

  /// Show color picker dialog for track
  void _showTrackColorPicker(String trackId, Color currentColor) {
    // Cubase-style track colors
    final colors = [
      const Color(0xFF4A9EFF), // Blue
      const Color(0xFF40FF90), // Green
      const Color(0xFFFF4060), // Red
      const Color(0xFFAA40FF), // Purple
      const Color(0xFFFF9040), // Orange
      const Color(0xFF40C8FF), // Cyan
      const Color(0xFFFFFF40), // Yellow
      const Color(0xFFFF40AA), // Pink
      const Color(0xFF8B5A2B), // Brown
      const Color(0xFF607D8B), // Blue Grey
      const Color(0xFF9E9E9E), // Grey
      const Color(0xFF00BFA5), // Teal
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: Text(
          'Track Color',
          style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 14),
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in colors)
              GestureDetector(
                onTap: () {
                  // Update track color FIRST (this also updates clips and mixer channel)
                  _handleTrackColorChange(trackId, color);
                  // Then close dialog
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: currentColor.value == color.value
                        ? Border.all(color: Colors.white, width: 2)
                        : Border.all(color: Colors.black26, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Handle track color change - updates track, clips, and mixer channel
  void _handleTrackColorChange(String trackId, Color color) {
    EngineApi.instance.updateTrack(trackId, color: color.value);

    setState(() {
      // Update track color
      _tracks = _tracks.map((t) {
        if (t.id == trackId) {
          return t.copyWith(color: color);
        }
        return t;
      }).toList();
      // Update all clips on this track to match new color
      _clips = _clips.map((c) {
        if (c.trackId == trackId) {
          return c.copyWith(color: color);
        }
        return c;
      }).toList();
    });

    // Update mixer channel color
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.updateChannelColor(trackId, color);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POOL & TIMELINE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handle single-click on pool/tree item - selects and loads event to timeline
  void _handlePoolItemClick(String id, TreeItemType type, dynamic data) {
    // Event click in middleware mode - load to timeline
    if (id.startsWith('evt-')) {
      final eventId = id.substring(4); // Remove 'evt-' prefix
      _loadEventToTimeline(eventId);
    }
  }

  /// Handle double-click on pool item - creates NEW track with audio file
  void _handlePoolItemDoubleClick(String id, TreeItemType type, dynamic data) {
    // Check if it's a pool audio file
    if (id.startsWith('pool-') && data is timeline.PoolAudioFile) {
      // ALWAYS create NEW track on double-click (Cubase behavior)
      _addPoolFileToNewTrack(data);
    }

    // Check if it's an event from Events folder (middleware mode)
    if (id.startsWith('evt-')) {
      final eventId = id.substring(4); // Remove 'evt-' prefix
      if (_editorMode == EditorMode.middleware) {
        _showRenameEventDialog(eventId);
      } else {
        _loadEventToTimeline(eventId);
      }
    }
  }

  /// Load event's sounds to timeline as separate tracks
  void _loadEventToTimeline(String eventId) {
    final provider = context.read<MiddlewareProvider>();

    // First try composite events (SlotCompositeEvent from Slot Lab)
    final compositeEvent = provider.compositeEvents.where((e) => e.id == eventId).firstOrNull;

    if (compositeEvent != null) {
      // Select this composite event in provider
      provider.selectCompositeEvent(eventId);

      // Load composite event layers as tracks
      _loadCompositeEventToTimeline(compositeEvent);
      return;
    }

    // Fallback to MiddlewareEvent (legacy)
    final event = provider.events.firstWhere(
      (e) => e.id == eventId,
      orElse: () => MiddlewareEvent(id: '', name: ''),
    );

    if (event.id.isEmpty) {
      return;
    }

    // Normalize ID - ensure mw_ prefix for center panel sync
    final middlewareId = event.id.startsWith('mw_') ? event.id : 'mw_${event.id}';

    // If event has no actions, still allow viewing with empty track
    if (event.actions.isEmpty) {
      // Create single empty track for the event
      setState(() {
        _tracks = [
          timeline.TimelineTrack(
            id: 'evt_track_0',
            name: event.name,
            color: _getTrackColor(0),
            height: 80,
          ),
        ];
        _clips = [];
        _selectedEventForTimeline = eventId;
        _selectedEventId = middlewareId;
      });
      return;
    }

    // Load event's actions as tracks
    final newTracks = <timeline.TimelineTrack>[];
    final newClips = <timeline.TimelineClip>[];

    for (int i = 0; i < event.actions.length; i++) {
      final action = event.actions[i];
      final trackId = 'evt_track_$i';
      final clipId = 'evt_clip_$i';

      // Find matching audio file from pool for duration and waveform
      timeline.PoolAudioFile? poolFile;
      if (action.assetId.isNotEmpty && action.assetId != '—') {
        final assetId = action.assetId;
        final filename = assetId.split('/').last;

        // Try multiple matching strategies:
        // 1. Full path match
        poolFile = _audioPool.cast<timeline.PoolAudioFile?>().firstWhere(
          (f) => f?.path == assetId,
          orElse: () => null,
        );

        // 2. Match by filename (without extension comparison)
        poolFile ??= _audioPool.cast<timeline.PoolAudioFile?>().firstWhere(
          (f) => f?.name == filename,
          orElse: () => null,
        );

        // 3. Match by name without extension
        if (poolFile == null) {
          final nameNoExt = filename.replaceAll(RegExp(r'\.(wav|mp3|ogg|flac|aiff|aif|m4a)$', caseSensitive: false), '');
          poolFile = _audioPool.cast<timeline.PoolAudioFile?>().firstWhere(
            (f) {
              if (f == null) return false;
              final poolNameNoExt = f.name.replaceAll(RegExp(r'\.(wav|mp3|ogg|flac|aiff|aif|m4a)$', caseSensitive: false), '');
              return poolNameNoExt == nameNoExt;
            },
            orElse: () => null,
          );
        }

        // 4. Partial path match (end of path)
        poolFile ??= _audioPool.cast<timeline.PoolAudioFile?>().firstWhere(
          (f) => f?.path.endsWith(filename) ?? false,
          orElse: () => null,
        );
      }

      // Use real duration from pool file, or default to 2 seconds
      final clipDuration = poolFile?.duration ?? 2.0;

      // Determine track name
      String trackName;
      if (action.assetId.isNotEmpty) {
        trackName = action.assetId.split('/').last
            .replaceAll('.wav', '')
            .replaceAll('.mp3', '')
            .replaceAll('.ogg', '');
      } else {
        trackName = '${action.type.displayName} ${i + 1}';
      }

      // Create track for this action
      newTracks.add(timeline.TimelineTrack(
        id: trackId,
        name: trackName,
        color: _getTrackColor(i),
        height: 80,
        muted: false,
        soloed: false,
        armed: false,
        outputBus: timeline.OutputBus.sfx,
      ));

      // Create clip with real duration and waveform from pool
      newClips.add(timeline.TimelineClip(
        id: clipId,
        trackId: trackId,
        name: action.assetId.isNotEmpty ? action.assetId.split('/').last : trackName,
        startTime: action.delay,
        duration: clipDuration,
        color: _getTrackColor(i),
        sourceFile: action.assetId.isNotEmpty ? action.assetId : null,
        waveform: poolFile?.waveform,
        sourceDuration: poolFile?.duration,
        gain: action.gain,
      ));
    }

    // Check if this is a reload of same event (don't show snackbar)
    final isReload = _selectedEventForTimeline == eventId;
    final preserveIndex = isReload ? _selectedActionIndex : -1;

    setState(() {
      _tracks = newTracks;
      _clips = newClips;
      _selectedEventForTimeline = eventId;
      _selectedEventId = middlewareId; // Sync with middleware dropdown (with mw_ prefix)
      // Preserve selection if same event, reset otherwise
      _selectedActionIndex = (preserveIndex >= 0 && preserveIndex < newTracks.length)
          ? preserveIndex
          : -1;
      // Update synced action count to prevent infinite reload loop
      _lastSyncedActionCount = event.actions.length;
    });

  }

  /// Load SlotCompositeEvent layers to timeline (Wwise-style)
  void _loadCompositeEventToTimeline(SlotCompositeEvent event) {
    // Even if event has no layers, show empty timeline with event name
    if (event.layers.isEmpty) {
      setState(() {
        _tracks = [
          timeline.TimelineTrack(
            id: 'evt_track_0',
            name: '${event.name} (empty)',
            color: event.color,
            height: 80,
          ),
        ];
        _clips = [];
        _selectedEventForTimeline = event.id;
        _selectedEventId = 'mw_${event.id}'; // Must include mw_ prefix
        _selectedLayerIndex = -1;
      });
      return;
    }

    // Load layers as tracks
    final newTracks = <timeline.TimelineTrack>[];
    final newClips = <timeline.TimelineClip>[];

    for (int i = 0; i < event.layers.length; i++) {
      final layer = event.layers[i];
      final trackId = 'evt_track_$i';
      final clipId = 'evt_clip_$i';

      // Find matching audio file from pool
      timeline.PoolAudioFile? poolFile;
      if (layer.audioPath.isNotEmpty) {
        final filename = layer.audioPath.split('/').last;
        poolFile = _audioPool.cast<timeline.PoolAudioFile?>().firstWhere(
          (f) => f?.path == layer.audioPath || f?.name == filename,
          orElse: () => null,
        );
      }

      final trackName = layer.name.isNotEmpty ? layer.name : 'Layer ${i + 1}';
      final layerDuration = layer.durationSeconds ?? 0.0;
      final clipDuration = layerDuration > 0 ? layerDuration : (poolFile?.duration ?? 1.0);

      newTracks.add(timeline.TimelineTrack(
        id: trackId,
        name: trackName,
        color: _getTrackColor(i),
        height: 80,
        volume: layer.volume,
        pan: layer.pan,
        muted: layer.muted,
        soloed: layer.solo,
      ));

      // Only add clip if there's an asset
      if (layer.audioPath.isNotEmpty) {
        newClips.add(timeline.TimelineClip(
          id: clipId,
          trackId: trackId,
          name: layer.name.isNotEmpty ? layer.name : layer.audioPath.split('/').last,
          startTime: layer.offsetMs / 1000.0, // Convert ms to seconds
          duration: clipDuration,
          color: _getTrackColor(i),
          sourceFile: layer.audioPath,
          waveform: poolFile?.waveform,
          sourceDuration: poolFile?.duration,
          gain: layer.volume,
        ));
      }
    }

    setState(() {
      _tracks = newTracks;
      _clips = newClips;
      _selectedEventForTimeline = event.id;
      _selectedEventId = 'mw_${event.id}'; // Must include mw_ prefix for center panel
      _selectedActionIndex = -1;
      _selectedLayerIndex = event.layers.isNotEmpty ? 0 : -1;
    });
  }

  Color _getTrackColor(int index) {
    const colors = [
      Color(0xFF4A9EFF), // Blue
      Color(0xFFFF9040), // Orange
      Color(0xFF40FF90), // Green
      Color(0xFFFF4060), // Red
      Color(0xFF40C8FF), // Cyan
      Color(0xFFFFFF40), // Yellow
      Color(0xFFFF40FF), // Magenta
      Color(0xFF90FF40), // Lime
    ];
    return colors[index % colors.length];
  }

  /// Add pool file to a NEW track (double-click behavior)
  /// Uses same logic as drag-drop for consistency
  Future<void> _addPoolFileToNewTrack(timeline.PoolAudioFile poolFile) async {
    final transport = context.read<EngineProvider>().transport;
    final insertTime = transport.positionSeconds;

    // Delegate to _createTrackWithClip which properly creates native track first
    await _createTrackWithClip(poolFile, insertTime, poolFile.defaultBus);
  }

  /// Add a pool file to timeline (Cubase-style drag & drop behavior)
  ///
  /// Cubase/Pro Tools/Logic standard behavior:
  /// - Drop on existing track → add clip to that track
  /// - Drop below all tracks (empty space) → create new track with clip
  /// - No target specified → create new track with clip
  Future<void> _addPoolFileToTimeline(timeline.PoolAudioFile poolFile, {
    String? targetTrackId,
    double? startTime,
    timeline.OutputBus? bus,
  }) async {
    final transport = context.read<EngineProvider>().transport;
    final insertTime = startTime ?? transport.positionSeconds;

    // CASE 1: No target track specified = drop on empty space → CREATE NEW TRACK
    // This is the Cubase behavior: dropping below existing tracks creates a new track
    if (targetTrackId == null) {
      await _createTrackWithClip(poolFile, insertTime, bus);
      return;
    }

    // CASE 2: Target track specified → add clip to that track
    final track = _tracks.cast<timeline.TimelineTrack?>().firstWhere(
      (t) => t?.id == targetTrackId,
      orElse: () => null,
    );

    // Track not found (shouldn't happen, but safety check)
    if (track == null) {
      await _createTrackWithClip(poolFile, insertTime, bus);
      return;
    }

    // Import audio to native engine (this loads into playback cache)
    final clipInfo = await engine.importAudioFile(
      filePath: poolFile.path,
      trackId: track.id,
      startTime: insertTime,
    );

    final clipBus = bus ?? poolFile.defaultBus;
    final clipId = clipInfo?.clipId ?? 'clip-${DateTime.now().millisecondsSinceEpoch}';

    // Get real waveform from engine (or fallback to pool waveform)
    Float32List? waveform = poolFile.waveform;
    if (clipInfo != null) {
      final peaks = await engine.getWaveformPeaks(clipId: clipInfo.clipId);
      if (peaks.isNotEmpty) {
        waveform = Float32List.fromList(peaks.map((v) => v.toDouble()).toList().cast<double>());
      }
    }

    setState(() {
      _clips = [
        ..._clips,
        timeline.TimelineClip(
          id: clipId,
          trackId: track.id,
          name: poolFile.name,
          startTime: insertTime,
          duration: clipInfo?.duration ?? poolFile.duration,
          sourceDuration: clipInfo?.sourceDuration ?? poolFile.duration,
          sourceFile: poolFile.path,
          waveform: waveform,
          color: track.color,
          eventId: _currentEventId, // Assign to current event
        ),
      ];

      // Update track bus if different
      if (track.outputBus != clipBus) {
        final trackIndex = _tracks.indexWhere((t) => t.id == track.id);
        if (trackIndex >= 0) {
          _tracks[trackIndex] = track.copyWith(outputBus: clipBus);
        }
      }
    });

    _showSnackBar('Added ${poolFile.name} to ${track.name}');
    _updateActiveBuses();

    // Refresh Audio Pool panel to show correct duration
    triggerAudioPoolRefresh();
  }

  /// Create a new track with a clip (used for empty space drops and double-click)
  Future<void> _createTrackWithClip(
    timeline.PoolAudioFile poolFile,
    double startTime, [
    timeline.OutputBus? bus,
  ]) async {
    final trackIndex = _tracks.length;
    final color = _defaultTrackColor;
    final clipBus = bus ?? poolFile.defaultBus;

    // Create track with audio file name (without extension)
    final trackName = poolFile.name.replaceAll(RegExp(r'\.[^.]+$'), '');

    // Create track in native engine first
    final nativeTrackId = engine.createTrack(
      name: trackName,
      color: color.value,
      busId: clipBus.index,
    );

    final newTrack = timeline.TimelineTrack(
      id: nativeTrackId,
      name: trackName,
      color: color,
      outputBus: clipBus,
      channels: poolFile.channels,
    );

    // Import audio to native engine (this loads into playback cache)
    final clipInfo = await engine.importAudioFile(
      filePath: poolFile.path,
      trackId: nativeTrackId,
      startTime: startTime,
    );

    final clipId = clipInfo?.clipId ?? 'clip-${DateTime.now().millisecondsSinceEpoch}-$trackIndex';

    // Get real waveform from engine (or fallback to pool waveform)
    Float32List? waveform = poolFile.waveform;
    if (clipInfo != null) {
      final peaks = await engine.getWaveformPeaks(clipId: clipInfo.clipId);
      if (peaks.isNotEmpty) {
        waveform = Float32List.fromList(peaks.map((v) => v.toDouble()).toList().cast<double>());
      }
    }

    final newClip = timeline.TimelineClip(
      id: clipId,
      trackId: nativeTrackId,
      name: poolFile.name,
      startTime: startTime,
      duration: clipInfo?.duration ?? poolFile.duration,
      sourceDuration: clipInfo?.sourceDuration ?? poolFile.duration,
      sourceFile: poolFile.path,
      waveform: waveform,
      color: color,
      eventId: _currentEventId, // Assign to current event
    );

    setState(() {
      _tracks = [..._tracks, newTrack];
      // Deselect all existing clips, select the new one
      _clips = _clips.map((c) => c.copyWith(selected: false)).toList();
      _clips = [..._clips, newClip.copyWith(selected: true)];

      // Auto-select new track and open Channel tab
      _selectedTrackId = nativeTrackId;
      _activeLeftTab = LeftZoneTab.channel;

      // Update _audioPool with real duration from engine
      if (clipInfo != null) {
        final poolIndex = _audioPool.indexWhere((f) => f.path == poolFile.path);
        if (poolIndex >= 0) {
          _audioPool[poolIndex] = _audioPool[poolIndex].copyWith(
            duration: clipInfo.duration,
          );
        }
      }
    });

    // Create mixer channel for the new track (Cubase-style: track = fader)
    // Use channels from clipInfo if available, fallback to poolFile
    final channelCount = clipInfo?.channels ?? poolFile.channels;
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.createChannelFromTrack(nativeTrackId, trackName, color, channels: channelCount);

    _updateActiveBuses();

    // Auto-zoom to fit clip in timeline (zoom out to show entire clip)
    final clipDuration = clipInfo?.duration ?? poolFile.duration;
    if (clipDuration > 0) {
      const timelineWidth = 800.0; // Approximate
      final fitZoom = (timelineWidth / clipDuration).clamp(5.0, 500.0);
      setState(() {
        _timelineZoom = fitZoom;
        _timelineScrollOffset = 0;
      });
    }

    // Refresh Audio Pool panel to show correct duration
    triggerAudioPoolRefresh();
  }

  /// Update engine active buses based on current playhead position and clips
  void _updateActiveBuses() {
    final engineApi = context.read<EngineProvider>();
    final currentTime = engineApi.transport.positionSeconds;

    // Find all clips at current position
    final activeClips = _clips.where((clip) =>
        !clip.muted &&
        currentTime >= clip.startTime &&
        currentTime < clip.endTime).toList();

    // Build bus activity map
    // Bus indices: 0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=UI
    final Map<int, double> busActivity = {};

    for (final clip in activeClips) {
      // Find track for this clip
      final track = _tracks.firstWhere(
        (t) => t.id == clip.trackId,
        orElse: () => timeline.TimelineTrack(id: '', name: ''),
      );

      if (track.id.isEmpty || track.muted) continue;

      // Convert OutputBus to index
      final busIndex = _busToIndex(track.outputBus);

      // Add activity (volume-weighted)
      final clipGain = clip.gain * track.volume;
      busActivity[busIndex] = (busActivity[busIndex] ?? 0) + clipGain;
    }

    // Clamp and set
    busActivity.updateAll((key, value) => value.clamp(0.0, 1.0));

    engine.setActiveBuses(busActivity);
  }

  /// Convert OutputBus enum to bus index
  int _busToIndex(timeline.OutputBus bus) {
    switch (bus) {
      case timeline.OutputBus.master:
        return 0;
      case timeline.OutputBus.music:
        return 1;
      case timeline.OutputBus.sfx:
        return 2;
      case timeline.OutputBus.voice:
        return 3;
      case timeline.OutputBus.ambience:
        return 4;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO IMPORT (Legacy - for direct file import)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import audio file to a track at specified time
  Future<void> _handleImportAudio(String filePath, String trackId, double startTime) async {
    final clipInfo = await engine.importAudioFile(
      filePath: filePath,
      trackId: trackId,
      startTime: startTime,
    );

    if (clipInfo == null) {
      print('[UI] Failed to import audio: $filePath');
      return;
    }

    // Get waveform peaks from engine
    final peaks = await engine.getWaveformPeaks(clipId: clipInfo.clipId);
    final waveform = peaks.isNotEmpty
        ? Float32List.fromList(peaks.map((v) => v.toDouble()).toList().cast<double>())
        : null;

    setState(() {
      _clips = [
        ..._clips,
        timeline.TimelineClip(
          id: clipInfo.clipId,
          trackId: clipInfo.trackId,
          name: clipInfo.name,
          startTime: clipInfo.startTime,
          duration: clipInfo.duration,
          sourceDuration: clipInfo.sourceDuration,
          waveform: waveform,
          color: _tracks.firstWhere((t) => t.id == trackId).color,
          eventId: _currentEventId, // Assign to current event
        ),
      ];
    });

    // Refresh Audio Pool panel to show newly imported file
    triggerAudioPoolRefresh();
  }

  /// Handle file drop on timeline
  Future<void> _handleFileDrop(String filePath, String? targetTrackId, double startTime) async {
    // If no track exists, create one first
    if (_tracks.isEmpty) {
      _handleAddTrack();
    }

    // Use target track or first track
    final trackId = targetTrackId ?? _tracks.first.id;

    // Import the audio file
    await _handleImportAudio(filePath, trackId, startTime);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE SWITCH PLAYBACK ISOLATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stop all playback from ALL sections when switching modes
  /// This prevents audio bleeding between DAW/Middleware/SlotLab
  void _stopAllPlaybackOnModeSwitch() {
    // 1. Stop DAW timeline playback
    final playbackProvider = context.read<TimelinePlaybackProvider>();
    if (playbackProvider.isPlaying) {
      playbackProvider.stop();
    }

    // 2. Stop SlotLab stage playback
    final slotLabProvider = context.read<SlotLabProvider>();
    slotLabProvider.stopAllPlayback();

    // 3. Stop Middleware events
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.stopAllEvents(fadeMs: 50);

    // 4. Release any active section in UnifiedPlaybackController
    final controller = UnifiedPlaybackController.instance;
    if (controller.activeSection != null) {
      controller.stop(releaseAfterStop: true);
    }

  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILE MENU HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// New Project - creates fresh project
  void _handleNewProject(EngineProvider engine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: const Text('New Project', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Create a new project?', style: TextStyle(color: FluxForgeTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Unsaved changes will be lost.', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              engine.newProject('Untitled Project');
              setState(() {
                _tracks = [];
                _clips = [];
                _markers = [];
                _crossfades = [];
                _loopRegion = const timeline.LoopRegion(start: 0.0, end: 8.0);
              });
            },
            child: Text('Create', style: TextStyle(color: FluxForgeTheme.accentBlue)),
          ),
        ],
      ),
    );
  }

  /// Open Project - file picker for .rfp files
  Future<void> _handleOpenProject(EngineProvider engine) async {
    final path = await NativeFilePicker.pickJsonFile();
    if (path == null) return;

    await engine.loadProject(path);
  }

  /// Save Project
  Future<void> _handleSaveProject(EngineProvider engine) async {
    // TODO: Get last saved path from engine
    await engine.saveProject('project.rfp');
    _showSnackBar('Project saved');
  }

  /// Save Project As - file picker for save location
  Future<void> _handleSaveProjectAs(EngineProvider engine) async {
    final path = await NativeFilePicker.saveFile(
      suggestedName: '${engine.project.name}.rfp',
      fileType: 'json',
    );

    if (path == null) return;
    await engine.saveProject(path);
    _showSnackBar('Project saved to: $path');
  }

  /// Select All Clips (Cmd+A)
  void _handleSelectAllClips() {
    if (_clips.isEmpty) return;
    setState(() {
      _clips = _clips.map((c) => c.copyWith(selected: true)).toList();
    });
  }

  /// Deselect All (Escape)
  void _handleDeselectAll() {
    setState(() {
      _clips = _clips.map((c) => c.copyWith(selected: false)).toList();
    });
  }

  /// Import JSON routes (Middleware mode)
  Future<void> _handleImportJSON() async {
    final path = await NativeFilePicker.pickJsonFile();
    if (path == null) return;

    // Read and parse JSON
    // TODO: Load routes from file
    _showSnackBar('Imported routes from: $path');
  }

  /// Export JSON routes (Middleware mode)
  void _handleExportJSON() {
    _exportEventsToJson();
    _showSnackBar('Routes exported to clipboard');
  }

  /// Import entire audio folder to Pool
  Future<void> _handleImportAudioFolder() async {
    final result = await NativeFilePicker.pickAudioFolder();

    if (result == null) {
      return;
    }

    // Scan folder for audio files
    final audioExtensions = PathValidator.allowedExtensions;
    final dir = Directory(result);
    final audioFiles = <FileSystemEntity>[];

    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (audioExtensions.contains(ext)) {
            audioFiles.add(entity);
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error scanning folder: $e');
      return;
    }

    if (audioFiles.isEmpty) {
      _showSnackBar('No audio files found in folder');
      return;
    }

    // Sort alphabetically by filename to match individual file import order
    audioFiles.sort((a, b) {
      final nameA = a.path.split('/').last.toLowerCase();
      final nameB = b.path.split('/').last.toLowerCase();
      return nameA.compareTo(nameB);
    });

    // Import all files to Pool (not timeline)
    for (final file in audioFiles) {
      await _addFileToPool(file.path);
    }

    _showSnackBar('Added ${audioFiles.length} files to Pool');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDIT MENU HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Undo last action (UI or Engine)
  void _handleUndo() {
    // Try UI undo first, then engine
    if (UiUndoManager.instance.canUndo) {
      UiUndoManager.instance.undo();
    } else if (engine.canUndo) {
      engine.undo();
    }
  }

  /// Redo last undone action (UI or Engine)
  void _handleRedo() {
    // Try UI redo first, then engine
    if (UiUndoManager.instance.canRedo) {
      UiUndoManager.instance.redo();
    } else if (engine.canRedo) {
      engine.redo();
    }
  }

  /// Cut selected clips
  void _handleCut() {
    _handleCopy();
    _handleDelete();
  }

  /// Copy selected clips to clipboard
  void _handleCopy() {
    final selectedClips = _clips.where((c) => c.selected).toList();
    if (selectedClips.isEmpty) return;

    // Store in clipboard (simplified - could use system clipboard with JSON)
    _clipboardClips = selectedClips;
    _showSnackBar('Copied ${selectedClips.length} clip(s)');
  }

  List<timeline.TimelineClip> _clipboardClips = [];

  // EQ state
  List<generic_eq.EqBand> _eqBands = [];
  // ignore: unused_field
  String? _selectedEqBandId;

  /// Paste clips from clipboard
  void _handlePaste() {
    if (_clipboardClips.isEmpty) return;
    if (_tracks.isEmpty) {
      _handleAddTrack();
    }

    final transport = context.read<EngineProvider>().transport;
    final pasteTime = transport.positionSeconds;

    // Calculate offset from first clip
    final minStart = _clipboardClips.map((c) => c.startTime).reduce((a, b) => a < b ? a : b);

    setState(() {
      for (final clip in _clipboardClips) {
        final newId = 'clip-${DateTime.now().millisecondsSinceEpoch}-${clip.id}';
        final offset = clip.startTime - minStart;
        // Get target track color
        final targetTrack = _tracks.firstWhere(
          (t) => t.id == clip.trackId,
          orElse: () => _tracks.first,
        );
        _clips.add(timeline.TimelineClip(
          id: newId,
          trackId: clip.trackId,
          name: '${clip.name} (copy)',
          startTime: pasteTime + offset,
          duration: clip.duration,
          sourceDuration: clip.sourceDuration,
          sourceOffset: clip.sourceOffset,
          color: targetTrack.color, // Sync with track color
          waveform: clip.waveform,
          gain: clip.gain,
          fadeIn: clip.fadeIn,
          fadeOut: clip.fadeOut,
          eventId: _currentEventId, // Assign to current event
        ));
      }
    });
    _showSnackBar('Pasted ${_clipboardClips.length} clip(s)');
  }

  /// Delete selected clips
  void _handleDelete() {
    final selectedIds = _clips.where((c) => c.selected).map((c) => c.id).toSet();
    if (selectedIds.isEmpty) return;

    // Delete from engine and invalidate waveform cache
    final cache = WaveformCache();
    for (final id in selectedIds) {
      engine.deleteClip(id);
      cache.remove(id); // Invalidate waveform cache entry
    }

    setState(() {
      _clips = _clips.where((c) => !c.selected).toList();
    });
    _showSnackBar('Deleted ${selectedIds.length} clip(s)');
  }

  /// Select all clips
  void _handleSelectAll() {
    setState(() {
      _clips = _clips.map((c) => c.copyWith(selected: true)).toList();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP INSPECTOR HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get track of selected clip
  timeline.TimelineTrack? _getSelectedClipTrack() {
    final selectedClip = _clips.cast<timeline.TimelineClip?>().firstWhere(
      (c) => c?.selected == true,
      orElse: () => null,
    );
    if (selectedClip == null) return null;
    return _tracks.cast<timeline.TimelineTrack?>().firstWhere(
      (t) => t?.id == selectedClip.trackId,
      orElse: () => null,
    );
  }

  /// Handle changes from clip inspector panel
  void _handleClipInspectorChange(timeline.TimelineClip updatedClip) {
    // Find old clip to detect what changed
    final oldClip = _clips.firstWhere((c) => c.id == updatedClip.id);

    setState(() {
      _clips = _clips.map((c) {
        if (c.id == updatedClip.id) return updatedClip;
        return c;
      }).toList();
    });

    // Sync fade changes to audio engine
    if (oldClip.fadeIn != updatedClip.fadeIn) {
      EngineApi.instance.fadeInClip(updatedClip.id, updatedClip.fadeIn);
    }
    if (oldClip.fadeOut != updatedClip.fadeOut) {
      EngineApi.instance.fadeOutClip(updatedClip.id, updatedClip.fadeOut);
    }
    // Sync gain changes to audio engine (linear gain: 0-2, where 1 = unity)
    if (oldClip.gain != updatedClip.gain) {
      EngineApi.instance.setClipGain(updatedClip.id, updatedClip.gain);
    }
    // Sync mute state to audio engine
    if (oldClip.muted != updatedClip.muted) {
      EngineApi.instance.setClipMuted(updatedClip.id, updatedClip.muted);
    }
    // Note: locked is UI-only state, no engine sync needed
  }

  /// Open FX editor for selected clip
  void _handleOpenClipFxEditor() {
    final selectedClip = _clips.cast<timeline.TimelineClip?>().firstWhere(
      (c) => c?.selected == true,
      orElse: () => null,
    );
    if (selectedClip == null) return;

    // Switch to lower zone with Clip FX tab
    setState(() {
      _lowerVisible = true;
      _activeLowerTab = 'clip-editor';
    });
    _showSnackBar('Clip FX: ${selectedClip.name}');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO POOL HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handle double-click on audio file in pool
  Future<void> _handleAudioPoolFileDoubleClick(AudioFileInfo file) async {
    // Create track if none exists
    if (_tracks.isEmpty) {
      _handleAddTrack();
      // Wait for track creation to complete
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Get first track
    final track = _tracks.first;

    // Get playback position (default to 0 for now)
    final startTime = 0.0;

    // Generate REAL waveform from audio file via FFI (SIMD-optimized in Rust)
    Float32List? waveform;

    // Try to parse existing waveform data if available
    if (file.waveformData != null && file.waveformData!.isNotEmpty) {
      final (left, _) = timeline.parseWaveformFromJson(file.waveformData);
      waveform = left;
    }

    // Fallback to FFI generation if no cached waveform
    if (waveform == null) {
      final cacheKey = 'clip-${file.id}';
      final waveformJson = NativeFFI.instance.generateWaveformFromFile(file.path, cacheKey);
      if (waveformJson != null) {
        final (left, _) = timeline.parseWaveformFromJson(waveformJson);
        waveform = left;
      }
    }

    try {
      final clipId = 'clip-${DateTime.now().millisecondsSinceEpoch}';

      final newClip = timeline.TimelineClip(
        id: clipId,
        trackId: track.id,
        name: file.name,
        startTime: startTime,
        duration: file.duration,
        sourceDuration: file.duration,
        sourceOffset: 0,
        sourceFile: file.path,
        color: track.color,
        waveform: waveform,
        gain: 1.0,
        fadeIn: 0.01,
        fadeOut: 0.01,
        selected: false,
        eventId: _currentEventId, // Assign to current event
      );

      setState(() {
        _clips.add(newClip);
      });

      _showSnackBar('Added "${file.name}" to timeline');
    } catch (e) {
      _showSnackBar('Error loading audio file: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIEW MENU HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reset layout to defaults
  void _handleResetLayout() {
    setState(() {
      _leftVisible = true;
      _rightVisible = true;
      _lowerVisible = true;
      _timelineZoom = 50;
      _timelineScrollOffset = 0;
    });
    _showSnackBar('Layout reset to defaults');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-CROSSFADE SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Detect overlap with another clip on the same track and create crossfade
  /// Returns the created crossfade ID, or null if no overlap
  String? _createAutoCrossfadeIfOverlap(String movedClipId, String trackId) {
    final movedClip = _clips.firstWhere(
      (c) => c.id == movedClipId,
      orElse: () => _clips.first,
    );

    // Find clips on the same track (excluding moved clip)
    final trackClips = _clips
        .where((c) => c.trackId == trackId && c.id != movedClipId)
        .toList();

    for (final otherClip in trackClips) {
      // Check for overlap
      final movedStart = movedClip.startTime;
      final movedEnd = movedClip.startTime + movedClip.duration;
      final otherStart = otherClip.startTime;
      final otherEnd = otherClip.startTime + otherClip.duration;

      // Calculate overlap region
      final overlapStart = movedStart > otherStart ? movedStart : otherStart;
      final overlapEnd = movedEnd < otherEnd ? movedEnd : otherEnd;
      final overlapDuration = overlapEnd - overlapStart;

      // If there's actual overlap (positive duration)
      if (overlapDuration > 0.01) {
        // Determine which clip is first (clipA) and which is second (clipB)
        final String clipAId;
        final String clipBId;
        if (movedStart < otherStart) {
          // Moved clip is first
          clipAId = movedClipId;
          clipBId = otherClip.id;
        } else {
          // Other clip is first
          clipAId = otherClip.id;
          clipBId = movedClipId;
        }

        // Check if crossfade already exists between these clips
        final existingCrossfade = _crossfades.any(
          (x) => x.trackId == trackId &&
              ((x.clipAId == clipAId && x.clipBId == clipBId) ||
               (x.clipAId == clipBId && x.clipBId == clipAId)),
        );

        if (!existingCrossfade) {
          // Create new crossfade
          final crossfadeId = 'xfade-${DateTime.now().millisecondsSinceEpoch}';
          final newCrossfade = timeline.Crossfade(
            id: crossfadeId,
            trackId: trackId,
            clipAId: clipAId,
            clipBId: clipBId,
            startTime: overlapStart,
            duration: overlapDuration,
            curveType: timeline.CrossfadeCurve.equalPower,
          );

          setState(() {
            _crossfades = [..._crossfades, newCrossfade];
          });

          return crossfadeId;
        } else {
          // Update existing crossfade position/duration
          setState(() {
            _crossfades = _crossfades.map((x) {
              if (x.trackId == trackId &&
                  ((x.clipAId == clipAId && x.clipBId == clipBId) ||
                   (x.clipAId == clipBId && x.clipBId == clipAId))) {
                return x.copyWith(
                  startTime: overlapStart,
                  duration: overlapDuration,
                );
              }
              return x;
            }).toList();
          });
        }

        // Only process one overlap at a time
        return null;
      }
    }

    // No overlap found - remove any crossfades involving this clip that no longer overlap
    _removeStaleClipCrossfades(movedClipId);
    return null;
  }

  /// Remove crossfades that no longer have overlapping clips
  void _removeStaleClipCrossfades(String clipId) {
    final clip = _clips.firstWhere(
      (c) => c.id == clipId,
      orElse: () => _clips.first,
    );
    final clipStart = clip.startTime;
    final clipEnd = clip.startTime + clip.duration;

    setState(() {
      _crossfades = _crossfades.where((xfade) {
        // Keep crossfades not involving this clip
        if (xfade.clipAId != clipId && xfade.clipBId != clipId) return true;

        // Find the other clip in the crossfade
        final otherClipId = xfade.clipAId == clipId ? xfade.clipBId : xfade.clipAId;
        final otherClip = _clips.firstWhere(
          (c) => c.id == otherClipId,
          orElse: () => _clips.first,
        );
        if (otherClip.id != otherClipId) return false; // Other clip not found

        final otherStart = otherClip.startTime;
        final otherEnd = otherClip.startTime + otherClip.duration;

        // Check if still overlapping
        final overlapStart = clipStart > otherStart ? clipStart : otherStart;
        final overlapEnd = clipEnd < otherEnd ? clipEnd : otherEnd;
        final stillOverlapping = (overlapEnd - overlapStart) > 0.01;

        return stillOverlapping;
      }).toList();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT MENU HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Show project settings dialog
  // ignore: unused_element
  void _showProjectSettingsDialog(EngineProvider engine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: const Text('Project Settings', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsRow(label: 'Project Name', value: engine.project.name),
              _SettingsRow(label: 'Sample Rate', value: '${engine.project.sampleRate} Hz'),
              _SettingsRow(label: 'Tempo', value: '${engine.transport.tempo.toStringAsFixed(1)} BPM'),
              _SettingsRow(label: 'Time Signature', value: '${engine.transport.timeSigNum}/${engine.transport.timeSigDenom}'),
              _SettingsRow(label: 'Tracks', value: '${_tracks.length}'),
              _SettingsRow(label: 'Clips', value: '${_clips.length}'),
              _SettingsRow(label: 'Buses', value: '${engine.project.busCount}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: FluxForgeTheme.accentBlue)),
          ),
        ],
      ),
    );
  }

  /// Validate project
  void _handleValidateProject() {
    final issues = <String>[];

    // Check for common issues
    if (_tracks.isEmpty) {
      issues.add('No tracks in project');
    }
    if (_clips.isEmpty) {
      issues.add('No audio clips in project');
    }

    // Check for overlapping clips on same track
    for (final track in _tracks) {
      final trackClips = _clips.where((c) => c.trackId == track.id).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      for (int i = 0; i < trackClips.length - 1; i++) {
        if (trackClips[i].endTime > trackClips[i + 1].startTime) {
          issues.add('Overlapping clips on track "${track.name}"');
          break;
        }
      }
    }

    // Check for clips beyond project duration
    for (final clip in _clips) {
      if (clip.startTime < 0) {
        issues.add('Clip "${clip.name}" starts before timeline');
      }
    }

    // Show results
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: Row(
          children: [
            Icon(
              issues.isEmpty ? Icons.check_circle : Icons.warning,
              color: issues.isEmpty ? FluxForgeTheme.accentGreen : FluxForgeTheme.warningOrange,
            ),
            const SizedBox(width: 8),
            Text(
              issues.isEmpty ? 'Validation Passed' : 'Validation Issues',
              style: const TextStyle(color: FluxForgeTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: issues.isEmpty
              ? [Text('No issues found.', style: TextStyle(color: FluxForgeTheme.textSecondary))]
              : issues.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 14, color: FluxForgeTheme.warningOrange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(i, style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12))),
                    ],
                  ),
                )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: FluxForgeTheme.accentBlue)),
          ),
        ],
      ),
    );
  }

  /// Build/Export project - opens export dialog
  void _handleBuildProject() async {
    final engine = context.read<EngineProvider>();
    final projectName = engine.project.name.isNotEmpty
        ? engine.project.name
        : (widget.projectName ?? 'Untitled');

    // Compute duration in seconds from samples
    final projectDuration = engine.project.sampleRate > 0
        ? engine.project.durationSamples / engine.project.sampleRate
        : 60.0;

    final result = await ExportAudioDialog.show(
      context,
      projectName: projectName,
      projectDuration: projectDuration,
    );

    if (result != null && result.success) {
      _showSnackBar('Build complete: ${result.outputPath}');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDIO MENU HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Open Audio Settings screen
  void _handleAudioSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AudioSettingsScreen(),
      ),
    );
  }

  /// Open MIDI Settings screen
  void _handleMidiSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const MidiSettingsScreen(),
      ),
    );
  }

  /// Open Plugin Manager screen
  void _handlePluginManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PluginManagerScreen(),
      ),
    );
  }

  /// Open Project Settings screen
  void _handleProjectSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ProjectSettingsScreen(),
      ),
    );
  }

  /// Open Keyboard Shortcuts settings screen
  void _handleKeyboardShortcuts() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ShortcutsSettingsScreen(),
      ),
    );
  }

  /// Open Audio Export dialog
  void _handleExportAudio() async {
    final engine = context.read<EngineProvider>();
    final projectName = engine.project.name.isNotEmpty
        ? engine.project.name
        : (widget.projectName ?? 'Untitled');
    // Compute duration in seconds from samples
    final projectDuration = engine.project.sampleRate > 0
        ? engine.project.durationSamples / engine.project.sampleRate
        : 60.0;

    final result = await ExportAudioDialog.show(
      context,
      projectName: projectName,
      projectDuration: projectDuration,
    );

    if (result != null && result.success) {
      _showSnackBar('Audio exported to ${result.outputPath}');
    }
  }

  /// Quick export — delegates to full audio export
  void _handleQuickExport() {
    _handleExportAudio();
  }

  /// Show export dialog — delegates to full audio export
  void _showExportDialog() {
    _handleExportAudio();
  }

  /// Batch export dialog
  void _handleBatchExport() {
    // Create batch export items from tracks
    final items = _tracks.map((track) => BatchExportItem(
      id: track.id,
      name: track.name,
      type: BatchExportType.track,
      trackId: track.id,
    )).toList();

    showDialog(
      context: context,
      builder: (ctx) => BatchExportDialog(items: items),
    );
  }

  /// Export presets dialog
  void _handleExportPresets() {
    showDialog(
      context: context,
      builder: (ctx) => const ExportPresetsDialog(),
    );
  }

  /// Bounce to disk dialog
  void _handleBounce() async {
    final engine = context.read<EngineProvider>();
    final projectDuration = engine.project.sampleRate > 0
        ? engine.project.durationSamples / engine.project.sampleRate
        : 60.0;

    final result = await BounceDialog.show(
      context,
      projectStart: 0,
      projectEnd: projectDuration,
      projectSampleRate: engine.project.sampleRate > 0 ? engine.project.sampleRate.toInt() : 48000,
    );

    if (result != null) {
      _showSnackBar('Bounce started with options: ${result.format.name}');
    }
  }

  /// Render in place dialog
  void _handleRenderInPlace() async {
    // Get selected clips
    final selectedClips = _clips.where((c) => c.selected).toList();
    if (selectedClips.isEmpty) {
      _showSnackBar('Please select clips to render');
      return;
    }

    final result = await RenderInPlaceDialog.show(
      context,
      clipName: selectedClips.first.name,
      hasClipFx: true,
      hasInserts: true,
    );

    if (result != null) {
      _showSnackBar('Rendered ${selectedClips.length} clip(s) in place');
    }
  }

  /// Show Audio Pool panel in lower zone
  void _handleShowAudioPool() {
    setState(() {
      _lowerVisible = true;
      _activeLowerTab = 'pool';
    });
  }

  /// Show Markers in lower zone
  void _handleShowMarkers() {
    setState(() {
      _lowerVisible = true;
      _activeLowerTab = 'markers';
    });
  }

  /// Show MIDI Editor in lower zone
  void _handleShowMidiEditor() {
    setState(() {
      _lowerVisible = true;
      _activeLowerTab = 'midi';
    });
  }

  /// Show Advanced panel in lower zone (triggered by keyboard shortcuts)
  void _showAdvancedPanel(String tabId) {
    setState(() {
      _lowerVisible = true;
      _activeLowerTab = tabId;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P3 CLOUD MENU HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cloud Sync Settings dialog (P3-01)
  void _showCloudSyncDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        child: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_sync, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 12),
                    const Text('Cloud Sync Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: CloudSyncService.instance,
                  builder: (context, _) {
                    final service = CloudSyncService.instance;
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildCloudStatusTile('Status', service.status.name),
                        _buildCloudStatusTile('Provider', service.provider.name),
                        _buildCloudStatusTile('Auto-sync', service.isEnabled ? 'Enabled' : 'Disabled'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync Now'),
                          onPressed: () => service.syncProject('current'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloudStatusTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// Collaboration dialog (P3-04)
  void _showCollaborationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        child: SizedBox(
          width: 600,
          height: 500,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    const CollaborationStatusBadge(),
                    const SizedBox(width: 12),
                    const Text('Real-time Collaboration', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Expanded(child: CollaborationPanel()),
            ],
          ),
        ),
      ),
    );
  }

  /// Asset Cloud dialog (P3-06)
  void _showAssetCloudDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        child: SizedBox(
          width: 800,
          height: 600,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    const AssetCloudStatusBadge(),
                    const SizedBox(width: 12),
                    const Text('Asset Cloud Library', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Expanded(child: AssetCloudPanel()),
            ],
          ),
        ),
      ),
    );
  }

  /// Marketplace dialog (P3-11)
  void _showMarketplaceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        child: SizedBox(
          width: 900,
          height: 700,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    const MarketplaceStatusBadge(),
                    const SizedBox(width: 12),
                    const Text('Plugin Marketplace', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Expanded(child: MarketplacePanel()),
            ],
          ),
        ),
      ),
    );
  }

  /// AI Mixing Assistant dialog (P3-03)
  void _showAiMixingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        child: SizedBox(
          width: 600,
          height: 500,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_fix_high, color: Color(0xFF9370DB)),
                    const SizedBox(width: 12),
                    const Text('AI Mixing Assistant', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: AiMixingService.instance,
                  builder: (context, _) {
                    final service = AiMixingService.instance;
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildCloudStatusTile('Status', service.isAnalyzing ? 'Analyzing...' : 'Ready'),
                        _buildCloudStatusTile('Model', service.currentModel),
                        _buildCloudStatusTile('Suggestions', '${service.suggestions.length}'),
                        const SizedBox(height: 16),
                        if (service.suggestions.isNotEmpty) ...[
                          const Text('Suggestions:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ...service.suggestions.take(5).map((s) => Card(
                            color: Colors.white.withOpacity(0.05),
                            child: ListTile(
                              leading: Icon(_getAiSuggestionIcon(s.type.name), color: const Color(0xFF9370DB)),
                              title: Text(s.title, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(s.description, style: TextStyle(color: Colors.white.withOpacity(0.6))),
                              trailing: TextButton(
                                onPressed: () => service.applySuggestion(s),
                                child: const Text('APPLY'),
                              ),
                            ),
                          )),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.analytics),
                          label: const Text('Analyze Project'),
                          onPressed: () => service.analyzeProject(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getAiSuggestionIcon(String type) {
    switch (type) {
      case 'eq': return Icons.equalizer;
      case 'compression': return Icons.compress;
      case 'volume': return Icons.volume_up;
      case 'pan': return Icons.swap_horiz;
      case 'reverb': return Icons.waves;
      default: return Icons.auto_fix_high;
    }
  }

  /// CRDT Sync dialog (P3-13)
  void _showCrdtSyncDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        child: SizedBox(
          width: 700,
          height: 550,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  children: [
                    const CrdtSyncStatusBadge(size: 24),
                    const SizedBox(width: 12),
                    const Text('Collaborative Project Sync', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Expanded(child: CrdtSyncPanel()),
            ],
          ),
        ),
      ),
    );
  }

  /// Track templates dialog
  void _handleTrackTemplates() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        child: SizedBox(
          width: 500,
          height: 600,
          child: TrackTemplatesPanel(
            onTrackCreated: (trackId) {
              Navigator.pop(ctx);
              _showSnackBar('Created track from template');
            },
          ),
        ),
      ),
    );
  }

  /// Version history dialog
  void _handleVersionHistory() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        child: SizedBox(
          width: 800,
          height: 600,
          child: ProjectVersionsPanel(
            onVersionRestored: () {
              Navigator.pop(ctx);
              _showSnackBar('Version restored');
            },
          ),
        ),
      ),
    );
  }

  /// Freeze selected tracks
  void _handleFreezeSelectedTracks() async {
    if (_tracks.isEmpty) {
      _showSnackBar('No tracks to freeze');
      return;
    }

    // Use first track as example
    final track = _tracks.first;

    showDialog<void>(
      context: context,
      builder: (ctx) => FreezeOptionsDialog(
        trackName: track.name,
        plugins: ['EQ', 'Compressor', 'Reverb'], // Example plugins
        onFreeze: (options) {
          Navigator.pop(ctx);
          _showSnackBar('Froze track: ${track.name}');
        },
      ),
    );
  }

  /// Show snackbar message
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFFF4060) : null,
        duration: Duration(milliseconds: isError ? 2000 : 1500),
      ),
    );
  }

  /// Open file picker dialog to import audio files to Pool
  ///
  /// **INSTANT IMPORT** — Files appear immediately, metadata loads in background
  Future<void> _openFilePicker() async {
    final paths = await NativeFilePicker.pickAudioFiles();

    if (paths.isEmpty) {
      return;
    }

    // ⚡ INSTANT: Add all files immediately with placeholders
    _addFilesToPoolInstant(paths);

    _showSnackBar('Added ${paths.length} file(s) to Pool');

    // Background: Load metadata for all files in parallel
    _loadMetadataInBackground(paths);
  }

  /// **INSTANT ADD** — Add files to pool immediately with placeholder data
  ///
  /// NO FFI calls, NO blocking — pure in-memory operation
  void _addFilesToPoolInstant(List<String> paths) {
    final newFiles = <timeline.PoolAudioFile>[];

    for (final filePath in paths) {
      // Skip if already exists
      if (_audioPool.any((f) => f.path == filePath)) continue;

      final fileName = filePath.split('/').last;
      final ext = fileName.split('.').last.toLowerCase();
      final fileId = 'pool-${DateTime.now().millisecondsSinceEpoch}-${newFiles.length}-${filePath.hashCode}';

      newFiles.add(timeline.PoolAudioFile(
        id: fileId,
        path: filePath,
        name: fileName,
        duration: 0.0,  // Placeholder — loaded async
        sampleRate: 48000,
        channels: 2,
        format: ext,
        waveform: null,  // Placeholder — loaded on-demand
        importedAt: DateTime.now(),
        defaultBus: timeline.OutputBus.master,
      ));
    }

    if (newFiles.isNotEmpty) {
      setState(() {
        _audioPool.addAll(newFiles);
      });
    }
  }

  /// **BACKGROUND METADATA LOADING** — Load metadata for files in parallel
  ///
  /// Called after instant add. Updates pool entries with real metadata.
  void _loadMetadataInBackground(List<String> paths) {
    // Process all files in PARALLEL using Future.wait
    Future.wait(
      paths.map((path) => _loadMetadataForPoolFile(path)),
    ).then((_) {
      // All metadata loaded — UI already updated incrementally
    });
  }

  /// Load metadata for a single pool file (called in parallel)
  Future<void> _loadMetadataForPoolFile(String filePath) async {
    final index = _audioPool.indexWhere((f) => f.path == filePath);
    if (index < 0) return;

    // Get metadata from FFI (header only — fast, ~5ms per file)
    double duration = 0.0;
    int sampleRate = 48000;
    int channels = 2;

    final metadataJson = NativeFFI.instance.audioGetMetadata(filePath);
    if (metadataJson.isNotEmpty) {
      try {
        final metadata = jsonDecode(metadataJson);
        duration = (metadata['duration'] as num?)?.toDouble() ?? 0.0;
        sampleRate = (metadata['sample_rate'] as num?)?.toInt() ?? 48000;
        channels = (metadata['channels'] as num?)?.toInt() ?? 2;
      } catch (_) {
        // Use default values on parse failure
      }
    }

    // Fallback duration
    if (duration <= 0.0) {
      final fallbackDuration = NativeFFI.instance.getAudioFileDuration(filePath);
      if (fallbackDuration > 0) {
        duration = fallbackDuration;
      }
    }

    // Update pool entry with metadata (NO waveform — loaded on-demand)
    final file = _audioPool[index];
    final updated = timeline.PoolAudioFile(
      id: file.id,
      path: file.path,
      name: file.name,
      duration: duration,
      sampleRate: sampleRate,
      channels: channels,
      format: file.format,
      waveform: file.waveform,  // Keep existing waveform if any
      importedAt: file.importedAt,
      defaultBus: file.defaultBus,
    );

    setState(() {
      _audioPool[index] = updated;
    });
  }

  /// **LEGACY METHOD** — Add a file to the Audio Pool (kept for compatibility)
  ///
  /// Note: Use _addFilesToPoolInstant() for better performance
  Future<void> _addFileToPool(String filePath) async {
    // Use instant add + background metadata
    _addFilesToPoolInstant([filePath]);
    await _loadMetadataForPoolFile(filePath);
  }

  void _initDemoMiddlewareData() {
    // No placeholder events - events are created by user or synced from Slot Lab
    _middlewareEvents = [];
    _routeEvents = [];
  }

  /// Sync audio pool from SlotLabProvider to DAW _audioPool
  /// This ensures sounds imported in Slot Lab appear in DAW Audio Pool
  ///
  /// **INSTANT SYNC** — No waveform generation during sync (loaded on-demand)
  void _syncAudioPoolFromSlotLab(SlotLabProvider slotLabProvider) {
    final slotLabPool = slotLabProvider.persistedAudioPool;
    if (slotLabPool.isEmpty) return;

    final newPaths = <String>[];

    // Add any new files from Slot Lab that aren't already in DAW pool
    for (final item in slotLabPool) {
      final path = item['path'] as String? ?? '';
      if (path.isEmpty) continue;

      // Check if already in DAW pool
      final exists = _audioPool.any((f) => f.path == path);
      if (exists) continue;

      // ⚡ INSTANT: Add immediately with placeholder (NO waveform generation)
      final name = item['name'] as String? ?? path.split('/').last;
      final duration = (item['duration'] as num?)?.toDouble() ?? 0.0;
      final fileId = 'pool-${DateTime.now().millisecondsSinceEpoch}-${_audioPool.length}';

      _audioPool.add(timeline.PoolAudioFile(
        id: fileId,
        path: path,
        name: name,
        duration: duration,
        sampleRate: (item['sampleRate'] as num?)?.toInt() ?? 48000,
        channels: (item['channels'] as num?)?.toInt() ?? 2,
        format: path.split('.').last,
        waveform: null,  // Waveform loaded on-demand
        importedAt: DateTime.now(),
        defaultBus: timeline.OutputBus.master,
      ));

      newPaths.add(path);
    }

    // Background: Load metadata for new files if needed
    if (newPaths.isNotEmpty) {
      _loadMetadataInBackground(newPaths);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNIFIED AUDIO ASSET MANAGER SYNC (SINGLE SOURCE OF TRUTH)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync from AudioAssetManager (central source of truth) to local _audioPool
  /// This ensures all modes (DAW, Middleware, SlotLab) share the same assets
  ///
  /// **INSTANT SYNC** — No blocking FFI calls (waveform loaded on-demand)
  void _syncFromAssetManager(AudioAssetManager assetManager) {
    final assets = assetManager.assets;
    final newPaths = <String>[];

    // Sync: AssetManager → local _audioPool
    for (final asset in assets) {
      final exists = _audioPool.any((f) => f.path == asset.path);
      if (exists) continue;

      // ⚡ INSTANT: Add immediately with NO waveform (loaded on-demand)
      _audioPool.add(timeline.PoolAudioFile(
        id: asset.id,
        path: asset.path,
        name: asset.name,
        duration: asset.duration,
        sampleRate: asset.sampleRate,
        channels: asset.channels,
        format: asset.format,
        waveform: null,  // Waveform loaded on-demand
        importedAt: asset.importedAt,
        defaultBus: timeline.OutputBus.master,
      ));
    }

    // Reverse sync: local _audioPool → AssetManager (for assets added elsewhere)
    for (final poolFile in _audioPool) {
      if (!assetManager.hasAsset(poolFile.path)) {
        assetManager.addAssetFromPoolFile(
          id: poolFile.id,
          path: poolFile.path,
          name: poolFile.name,
          duration: poolFile.duration,
          sampleRate: poolFile.sampleRate,
          channels: poolFile.channels,
          format: poolFile.format,
          folder: 'Audio Pool',
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIDDLEWARE CRUD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  MiddlewareEvent? get _selectedEvent {
    if (_selectedEventId.isEmpty) return null;
    final provider = context.read<MiddlewareProvider>();

    // Check if selected ID is a composite event (mw_event_xxx)
    if (_selectedEventId.startsWith('mw_event_')) {
      final compositeId = _selectedEventId.substring(3); // Remove 'mw_' prefix
      final composite = provider.getCompositeEvent(compositeId);
      if (composite != null) {
        // Return synced MiddlewareEvent or create empty one
        final synced = provider.events.cast<MiddlewareEvent?>().firstWhere(
          (e) => e?.id == _selectedEventId,
          orElse: () => null,
        );
        if (synced != null) return synced;
        // Create empty MiddlewareEvent for display (no layers yet)
        return MiddlewareEvent(
          id: _selectedEventId,
          name: composite.name,
          category: 'Slot_${composite.category}',
          actions: [],
        );
      }
    }

    // Fallback: check provider events directly
    final providerEvent = provider.events.cast<MiddlewareEvent?>().firstWhere(
      (e) => e?.id == _selectedEventId,
      orElse: () => null,
    );
    if (providerEvent != null) return providerEvent;

    // Fallback to local events
    return _middlewareEvents.cast<MiddlewareEvent?>().firstWhere(
      (e) => e?.id == _selectedEventId,
      orElse: () => null,
    );
  }

  /// Get the currently selected action (for Inspector) - LEGACY, use _selectedLayer instead
  MiddlewareAction? get _selectedAction {
    final event = _selectedEvent;
    if (event == null || _selectedActionIndex < 0 || _selectedActionIndex >= event.actions.length) {
      return null;
    }
    return event.actions[_selectedActionIndex];
  }

  /// Get the currently selected layer from composite event (for Inspector)
  /// This is the NEW way - layers from SlotCompositeEvent, not MiddlewareEvent.actions
  SlotEventLayer? get _selectedLayer {
    final composite = _selectedComposite;
    if (composite == null || _selectedLayerIndex < 0 || _selectedLayerIndex >= composite.layers.length) {
      return null;
    }
    return composite.layers[_selectedLayerIndex];
  }

  /// Get selected composite event from MiddlewareProvider
  /// Extracts composite ID from _selectedEventId (which has mw_ prefix)
  SlotCompositeEvent? get _selectedComposite {
    if (_selectedEventId.isEmpty) return null;

    // Extract composite ID from _selectedEventId
    // Format: mw_event_xxx → event_xxx
    String compositeId;
    if (_selectedEventId.startsWith('mw_')) {
      compositeId = _selectedEventId.substring(3); // Remove 'mw_' prefix
    } else {
      compositeId = _selectedEventId;
    }

    final middleware = context.read<MiddlewareProvider>();
    return middleware.compositeEvents
        .where((e) => e.id == compositeId)
        .firstOrNull;
  }

  /// Update a field of the selected layer via MiddlewareProvider
  /// Calls setState to ensure inspector panel (outside Consumer) rebuilds
  void _updateSelectedLayer(SlotEventLayer Function(SlotEventLayer) updater) {
    final composite = _selectedComposite;
    final layer = _selectedLayer;
    if (composite == null || layer == null) {
      return;
    }
    final updatedLayer = updater(layer);
    final middleware = context.read<MiddlewareProvider>();
    middleware.updateEventLayer(composite.id, updatedLayer);
    // Trigger setState so inspector (outside Consumer) sees updated data
    setState(() {});
    // Sync header/layer row so all UI stays in sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncHeaderFromSelectedLayer();
    });
  }

  /// Sync header controls from selected SlotEventLayer (for quick editing)
  void _syncHeaderFromSelectedLayer() {
    final layer = _selectedLayer;
    final composite = _selectedComposite;
    if (layer == null) return;

    setState(() {
      _headerGain = layer.volume;
      _headerPan = layer.pan;
      _headerDelay = layer.offsetMs;
      _headerLoop = layer.loop;
      _headerFadeInMs = layer.fadeInMs;
      _headerFadeOutMs = layer.fadeOutMs;
      _headerFadeInCurve = layer.fadeInCurve;
      _headerFadeOutCurve = layer.fadeOutCurve;
      _headerTrimStartMs = layer.trimStartMs;
      _headerTrimEndMs = layer.trimEndMs;
      _headerAudioPath = layer.audioPath;
      // Map busId to header bus name
      _headerBus = _busIdToName(layer.busId);
    });
  }

  /// Convert bus ID to bus name for header display
  String _busIdToName(int? busId) {
    switch (busId) {
      case 0: return 'Master';
      case 1: return 'Music';
      case 2: return 'SFX';
      case 3: return 'Voice';
      case 4: return 'UI';
      case 5: return 'Ambience';
      default: return 'Music';
    }
  }

  /// Convert bus name to bus ID for layer update
  int _busNameToId(String busName) {
    switch (busName) {
      case 'Master': return 0;
      case 'Music': return 1;
      case 'SFX': return 2;
      case 'Voice': return 3;
      case 'UI': return 4;
      case 'Ambience': return 5;
      default: return 1;
    }
  }

  /// Apply action type from toolbar dropdown to selected layer
  void _applyHeaderActionType(String actionType) {
    final composite = _selectedComposite;
    if (composite == null || _selectedLayerIndex < 0) return;
    if (_selectedLayerIndex >= composite.layers.length) return;
    final layer = composite.layers[_selectedLayerIndex];
    final mw = context.read<MiddlewareProvider>();
    _updateLayer(composite, _selectedLayerIndex, layer.copyWith(actionType: actionType), mw);
  }

  /// Apply bus from toolbar dropdown to selected layer
  void _applyHeaderBus(String busName) {
    final composite = _selectedComposite;
    if (composite == null || _selectedLayerIndex < 0) return;
    if (_selectedLayerIndex >= composite.layers.length) return;
    final layer = composite.layers[_selectedLayerIndex];
    final mw = context.read<MiddlewareProvider>();
    _updateLayer(composite, _selectedLayerIndex, layer.copyWith(busId: _busNameToId(busName)), mw);
  }

  /// Select a layer and sync header values
  void _selectLayerAndSync(int index) {
    setState(() {
      _selectedLayerIndex = index;
    });
    // Sync header values from selected layer (delayed to ensure state is updated)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncHeaderFromSelectedLayer();
    });
  }

  /// Update a specific field of the selected action
  void _updateSelectedAction(MiddlewareAction Function(MiddlewareAction) updater) {
    final event = _selectedEvent;
    if (event == null || _selectedActionIndex < 0 || _selectedActionIndex >= event.actions.length) return;

    final eventId = _selectedEventId;
    final currentAction = event.actions[_selectedActionIndex];
    final updatedAction = updater(currentAction);

    // Update directly in MiddlewareProvider (single source of truth)
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.updateActionInEvent(eventId, updatedAction);

    // Also update local _middlewareEvents and header values for immediate UI feedback
    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == eventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          if (_selectedActionIndex < newActions.length) {
            newActions[_selectedActionIndex] = updatedAction;
          }
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();

      // Sync header values for command track display
      _headerActionType = updatedAction.type.displayName;
      _headerAssetId = updatedAction.assetId;
      _headerBus = updatedAction.bus;
      _headerScope = updatedAction.scope.displayName;
      _headerPriority = updatedAction.priority.displayName;
      _headerFadeCurve = updatedAction.fadeCurve.displayName;
      _headerFadeTime = updatedAction.fadeTime;
      _headerGain = updatedAction.gain;
      _headerPan = updatedAction.pan;
      _headerDelay = updatedAction.delay;
      _headerLoop = updatedAction.loop;
    });

    // Reload timeline to reflect changes (preserves selection now)
    _loadEventToTimeline(eventId);
  }

  /// Show dialog to create new composite event
  void _showCreateCompositeEventDialog() {
    final nameController = TextEditingController(text: 'New Event');
    String selectedCategory = 'ui';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          title: Row(
            children: [
              Icon(Icons.add_circle_outline, color: FluxForgeTheme.accentGreen, size: 20),
              const SizedBox(width: 8),
              Text('Create New Event', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: TextStyle(color: FluxForgeTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Event Name',
                    labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                    filled: true,
                    fillColor: FluxForgeTheme.bgDeep,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Category', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    dropdownColor: FluxForgeTheme.bgMid,
                    underline: const SizedBox(),
                    items: ['spin', 'win', 'bigWin', 'feature', 'bonus', 'ui', 'ambient', 'music'].map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat.toUpperCase(), style: TextStyle(color: FluxForgeTheme.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCategory = val);
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: FluxForgeTheme.accentGreen),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  final provider = context.read<MiddlewareProvider>();
                  final newEvent = provider.createCompositeEvent(name: name, category: selectedCategory);
                  // Select the new event
                  setState(() {
                    _selectedEventId = newEvent.id;
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  /// Add layer directly to composite event (no dialog - creates empty track)
  void _addLayerToComposite(SlotCompositeEvent event) {
    final provider = context.read<MiddlewareProvider>();
    final layerName = 'Layer ${event.layers.length + 1}';

    // Add empty layer with default parameters
    provider.addLayerToEvent(
      event.id,
      audioPath: '', // Empty - user will set via inspector
      name: layerName,
      durationSeconds: 2.0, // Default 2 seconds
    );

    // Select the new layer
    setState(() {
      _selectedLayerIndex = event.layers.length; // Will be the new index after add
    });
  }

  /// Preview composite event audio
  void _previewCompositeEvent(SlotCompositeEvent event) {
    final provider = context.read<MiddlewareProvider>();

    setState(() {
      _isPreviewingEvent = !_isPreviewingEvent;
    });

    if (_isPreviewingEvent) {
      // Play all layers via provider
      provider.previewCompositeEvent(event.id);
    } else {
      // Stop all voices for this event
      provider.stopCompositeEvent(event.id);
    }
  }

  /// Preview MiddlewareEvent (play all actions)
  void _previewMiddlewareEvent(MiddlewareEvent event) {
    final provider = context.read<MiddlewareProvider>();

    setState(() {
      _isPreviewingEvent = !_isPreviewingEvent;
    });

    if (_isPreviewingEvent) {
      // Play event via provider (EventRegistry handles the audio)
      provider.postEvent(event.name);
    } else {
      // Stop event playback
      provider.stopEventByName(event.name);
    }
  }

  /// Duplicate selected layer in composite event
  void _duplicateLayer(SlotCompositeEvent event, int layerIndex) {
    if (layerIndex < 0 || layerIndex >= event.layers.length) return;

    final provider = context.read<MiddlewareProvider>();
    final sourceLayer = event.layers[layerIndex];

    // Create duplicate layer
    provider.addLayerToEvent(
      event.id,
      audioPath: sourceLayer.audioPath,
      name: '${sourceLayer.name} (Copy)',
      durationSeconds: sourceLayer.durationSeconds,
    );

    // Select the duplicated layer
    setState(() {
      _selectedLayerIndex = event.layers.length; // New layer index
    });
  }

  /// Delete selected layer from composite event
  void _deleteLayer(SlotCompositeEvent event, int layerIndex) {
    if (layerIndex < 0 || layerIndex >= event.layers.length) return;

    final provider = context.read<MiddlewareProvider>();
    final layerId = event.layers[layerIndex].id;

    provider.removeLayerFromEvent(event.id, layerId);

    // Clear selection or select previous
    setState(() {
      if (event.layers.length <= 1) {
        _selectedLayerIndex = -1;
      } else if (_selectedLayerIndex >= event.layers.length - 1) {
        _selectedLayerIndex = event.layers.length - 2;
      }
    });
  }

  /// Show dialog to add layer to composite event
  void _showAddLayerToCompositeDialog(SlotCompositeEvent? event) {
    if (event == null) return;
    final provider = context.read<MiddlewareProvider>();
    provider.addLayerToEvent(
      event.id,
      audioPath: '',
      name: 'Layer ${event.layers.length + 1}',
    );
  }

  void _addAction() {
    if (_selectedEvent == null) return;

    final newAction = MiddlewareAction(
      id: 'act-${DateTime.now().millisecondsSinceEpoch}',
      type: ActionTypeExtension.fromString(_headerActionType),
      assetId: _headerAssetId,
      bus: _headerBus,
      scope: ActionScopeExtension.fromString(_headerScope),
      priority: ActionPriorityExtension.fromString(_headerPriority),
      fadeCurve: FadeCurveExtension.fromString(_headerFadeCurve),
      fadeTime: _headerFadeTime,
      gain: _headerGain,
      pan: _headerPan,
      delay: _headerDelay,
      loop: _headerLoop,
    );

    final eventId = _selectedEventId;

    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == eventId) {
          return e.copyWith(actions: [...e.actions, newAction]);
        }
        return e;
      }).toList();
      _selectedActionIndex = _selectedEvent!.actions.length; // Select new action
    });

    // Sync to MiddlewareProvider → triggers SlotLab sync
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.addActionToEvent(eventId, newAction);

    // Reload timeline to show new action
    _loadEventToTimeline(eventId);
  }

  /// Show inline rename dialog for an event
  void _showRenameEventDialog(String eventId) {
    final middleware = context.read<MiddlewareProvider>();
    final event = middleware.compositeEvents.where((e) => e.id == eventId).firstOrNull;
    if (event == null) return;
    final controller = TextEditingController(text: event.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: Text('Rename Event', style: TextStyle(fontSize: 13, color: FluxForgeTheme.textPrimary)),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(fontSize: 12, color: FluxForgeTheme.textPrimary),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              isDense: true,
            ),
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) {
                middleware.updateCompositeEvent(event.copyWith(name: val.trim()));
              }
              Navigator.of(ctx).pop();
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                middleware.updateCompositeEvent(event.copyWith(name: val));
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Rename', style: TextStyle(fontSize: 11, color: FluxForgeTheme.accentOrange)),
          ),
        ],
      ),
    );
  }

  /// Create a new empty event and select it
  void _createNewEvent(MiddlewareProvider middleware) {
    final event = middleware.createCompositeEvent(
      name: 'New Event ${middleware.compositeEvents.length + 1}',
    );
    final middlewareId = 'mw_${event.id}';
    setState(() {
      _selectedEventId = middlewareId;
      _selectedActionIndex = -1;
      _selectedLayerIndex = -1;
    });
    middleware.selectCompositeEvent(event.id);
  }

  /// Show Add Action dialog with all options
  void _showAddActionDialog() {
    // Direktno dodaj akciju BEZ popup-a
    // Default: Play tip, zelena boja
    _addAction();
  }

  void _deleteAction(int index) {
    if (_selectedEvent == null) return;

    final eventId = _selectedEventId;
    final actionId = _selectedEvent!.actions[index].id;

    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == eventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          newActions.removeAt(index);
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();
      _selectedActionIndex = -1;
    });

    // Sync to MiddlewareProvider → triggers SlotLab sync
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.removeActionFromEvent(eventId, actionId);

    // Reload timeline
    _loadEventToTimeline(eventId);
  }

  void _duplicateAction(int index) {
    if (_selectedEvent == null || index < 0 || index >= _selectedEvent!.actions.length) return;

    final eventId = _selectedEventId;
    final original = _selectedEvent!.actions[index];
    final duplicate = original.copyWith(
      id: 'act-${DateTime.now().millisecondsSinceEpoch}',
    );

    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == eventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          newActions.insert(index + 1, duplicate);
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();
      _selectedActionIndex = index + 1;
    });

    // Sync to MiddlewareProvider → triggers SlotLab sync
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.addActionToEvent(eventId, duplicate);

    // Reload timeline
    _loadEventToTimeline(eventId);
  }

  void _updateAction(int index, MiddlewareAction updated) {
    if (_selectedEvent == null) return;

    final eventId = _selectedEventId;

    // Sync to MiddlewareProvider first (single source of truth)
    final middlewareProvider = context.read<MiddlewareProvider>();
    middlewareProvider.updateActionInEvent(eventId, updated);

    // Update local state for immediate UI feedback
    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == eventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          newActions[index] = updated;
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();

      // Sync header values if this is the selected action
      if (index == _selectedActionIndex) {
        _headerActionType = updated.type.displayName;
        _headerAssetId = updated.assetId;
        _headerBus = updated.bus;
        _headerScope = updated.scope.displayName;
        _headerPriority = updated.priority.displayName;
        _headerFadeCurve = updated.fadeCurve.displayName;
        _headerFadeTime = updated.fadeTime;
        _headerGain = updated.gain;
        _headerPan = updated.pan;
        _headerDelay = updated.delay;
        _headerLoop = updated.loop;
      }
    });

    // Reload timeline (preserves selection now)
    _loadEventToTimeline(eventId);
  }

  void _selectAction(int index) {
    setState(() {
      _selectedActionIndex = index;
      if (_selectedEvent != null && index >= 0 && index < _selectedEvent!.actions.length) {
        final action = _selectedEvent!.actions[index];
        _headerActionType = action.type.displayName;
        _headerAssetId = action.assetId;
        _headerBus = action.bus;
        _headerScope = action.scope.displayName;
        _headerPriority = action.priority.displayName;
        _headerFadeCurve = action.fadeCurve.displayName;
        _headerFadeTime = action.fadeTime;
        _headerGain = action.gain;
        _headerPan = action.pan;
        _headerDelay = action.delay;
        _headerLoop = action.loop;
      }
    });
  }

  bool _isPreviewingEvent = false;
  int _previewSessionId = 0; // Incremented each preview to invalidate old timers

  void _previewEvent() {
    // Use SlotCompositeEvent.layers as source of truth (not MiddlewareEvent.actions)
    final composite = _selectedComposite;
    if (composite == null || composite.layers.isEmpty) return;

    if (_isPreviewingEvent) {
      // Stop preview
      _stopEventPreview();
      return;
    }

    // CRITICAL: Acquire middleware section so Rust engine doesn't filter out voices
    UnifiedPlaybackController.instance.acquireSection(PlaybackSection.middleware);
    UnifiedPlaybackController.instance.ensureStreamRunning();

    // Increment session ID to invalidate any pending timers from previous preview
    _previewSessionId++;
    final currentSession = _previewSessionId;

    // Play all layers with their delays (offsetMs)
    _isPreviewingEvent = true;
    setState(() {});

    final isLooping = composite.looping;

    // Calculate max end time while playing layers
    double maxEndTime = 0.0;

    for (final layer in composite.layers) {
      if (layer.audioPath.isEmpty) continue;
      if (layer.muted) continue; // Skip muted layers

      final filePath = layer.audioPath;

      // Get REAL duration from FFI (authoritative source)
      double duration = NativeFFI.instance.getAudioFileDuration(filePath);
      if (duration <= 0) {
        // Fallback to layer duration or pool lookup
        duration = layer.durationSeconds ?? 0.0;
        if (duration <= 0) {
          final poolFile = _audioPool.cast<timeline.PoolAudioFile?>().firstWhere(
            (f) => f != null && (f.path == filePath || f.name == filePath.split('/').last),
            orElse: () => null,
          );
          duration = (poolFile?.duration ?? 0) > 0 ? poolFile!.duration : 3.0;
        }
      }

      // Calculate end time for this layer (only for non-looping)
      if (!isLooping) {
        final delaySeconds = layer.offsetMs / 1000.0;
        final endTime = delaySeconds + duration;
        if (endTime > maxEndTime) maxEndTime = endTime;
      }

      // Schedule playback with delay (offsetMs is in milliseconds)
      final delayMs = layer.offsetMs.toInt();
      Future.delayed(Duration(milliseconds: delayMs), () {
        // Check both preview state AND session ID to avoid stale callbacks
        if (!_isPreviewingEvent || _previewSessionId != currentSession) return;

        try {
          if (isLooping) {
            // Use looping playback for looping events
            AudioPlaybackService.instance.playLoopingToBus(
              filePath,
              volume: layer.volume,
              pan: layer.pan,
              busId: layer.busId ?? 0,
              source: PlaybackSource.middleware,
              eventId: composite.id,
              layerId: layer.id,
            );
          } else {
            // One-shot playback with full parameters (pan, layerId, eventId)
            AudioPlaybackService.instance.playFileToBus(
              filePath,
              volume: layer.volume,
              pan: layer.pan,
              busId: layer.busId ?? 0,
              source: PlaybackSource.middleware,
              eventId: composite.id,
              layerId: layer.id,
            );
          }
        } catch (_) {
          // Ignore playback errors
        }
      });
    }

    // Auto-stop timer only for non-looping events
    // Looping events play until user clicks stop
    if (!isLooping) {
      maxEndTime += 0.3;
      Future.delayed(Duration(milliseconds: (maxEndTime * 1000).toInt()), () {
        if (_isPreviewingEvent && _previewSessionId == currentSession) {
          _stopEventPreview();
        }
      });
    }
  }

  void _stopEventPreview() {
    _isPreviewingEvent = false;
    // Stop via unified service
    AudioPlaybackService.instance.stopSource(PlaybackSource.middleware);
    setState(() {});
  }


  void _exportEventsToJson() async {
    final json = jsonEncode({
      'version': '1.0',
      'events': _middlewareEvents.map((e) => e.toJson()).toList(),
    });

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: json));
  }

  void _importEventsFromJson() async {
    // Read from clipboard
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;

    try {
      final json = jsonDecode(data!.text!) as Map<String, dynamic>;
      final events = (json['events'] as List<dynamic>?)
          ?.map((e) => MiddlewareEvent.fromJson(e as Map<String, dynamic>))
          .toList() ?? [];

      setState(() {
        _middlewareEvents = events;
        _routeEvents = events.map((e) => e.name).toList();
        if (events.isNotEmpty) {
          _selectedEventId = events.first.id;
        }
      });
    } catch (_) {
      // Ignore import errors
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: Text('Middleware Settings', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Events: ${_middlewareEvents.length}', style: TextStyle(color: FluxForgeTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Total Actions: ${_middlewareEvents.fold<int>(0, (sum, e) => sum + e.actions.length)}',
                style: TextStyle(color: FluxForgeTheme.textSecondary)),
            const SizedBox(height: 16),
            Text('View Mode: ${_middlewareGridView ? 'Grid' : 'List'}',
                style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: FluxForgeTheme.accentBlue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch MiddlewareProvider for Events folder updates in left panel
    // This ensures new events from Slot Lab appear immediately
    final middlewareProvider = context.watch<MiddlewareProvider>();

    // ═══════════════════════════════════════════════════════════════════════════
    // DIRECT SYNC FROM PROVIDER (backup for listener in case of timing issues)
    // ═══════════════════════════════════════════════════════════════════════════
    if (_editorMode == EditorMode.middleware) {
      final providerSelectedId = middlewareProvider.selectedCompositeEventId;
      if (providerSelectedId != null && providerSelectedId.isNotEmpty) {
        final expectedLocalId = 'mw_$providerSelectedId';
        // Only sync if different to avoid infinite loops
        if (_selectedEventId != expectedLocalId) {
          // Schedule setState for next frame to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedEventId != expectedLocalId) {
              setState(() {
                _selectedEventId = expectedLocalId;
                _selectedActionIndex = -1;
              });
            }
          });
        }
      }
    }

    // Auto-sync timeline when selected event's actions change externally
    // (e.g., when action is added from another source like MiddlewareProvider)
    if (_editorMode == EditorMode.middleware && _selectedEventId.isNotEmpty) {
      final currentEvent = middlewareProvider.events.cast<MiddlewareEvent?>().firstWhere(
        (e) => e?.id == _selectedEventId,
        orElse: () => null,
      );
      if (currentEvent != null) {
        final currentActionCount = currentEvent.actions.length;
        if (currentActionCount != _lastSyncedActionCount) {
          // Action count changed - schedule timeline reload
          _lastSyncedActionCount = currentActionCount;
          Future.microtask(() {
            if (mounted) _loadEventToTimeline(_selectedEventId);
          });
        }
      }
    }

    // Sync audio pool from SlotLabProvider (sounds imported in Slot Lab appear in DAW)
    final slotLabProvider = context.watch<SlotLabProvider>();
    _syncAudioPoolFromSlotLab(slotLabProvider);

    // ═══════════════════════════════════════════════════════════════════════════
    // UNIFIED AUDIO ASSET MANAGER SYNC
    // All modes share the same audio assets via AudioAssetManager
    // ═══════════════════════════════════════════════════════════════════════════
    final assetManager = context.watch<AudioAssetManager>();
    _syncFromAssetManager(assetManager);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Shift+Cmd+I - Import Audio Files
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true, shift: true): const _ImportAudioIntent(),
        // Also support Ctrl+Shift+I for non-Mac
        const SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true): const _ImportAudioIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ImportAudioIntent: CallbackAction<_ImportAudioIntent>(
            onInvoke: (_) {
              _openFilePicker();
              return null;
            },
          ),
        },
        child: FocusScope(
          autofocus: false,
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            onKeyEvent: (node, event) {
              // Handle SPACE for middleware preview at this level
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.space &&
                  _editorMode == EditorMode.middleware) {
                _previewEvent();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            // SLOT LAB MODE: Fullscreen slot lab when slot mode is active
            child: _editorMode == EditorMode.slot
                ? Builder(
                    builder: (context) {
                      return SlotLabScreen(
                        onClose: () => setState(() => _editorMode = EditorMode.middleware),
                        audioPool: _audioPool.map((f) => <String, dynamic>{
                          'path': f.path,
                          'name': f.name,
                          'duration': f.duration,
                          'sampleRate': f.sampleRate,
                          'channels': f.channels,
                        }).toList(),
                      );
                    },
                  )
                : Stack(
        children: [
          MainLayout(
            // PERFORMANCE: Use custom control bar that handles its own provider listening
            // This isolates control bar rebuilds from the rest of the layout
            customControlBar: EngineConnectedControlBar(
              editorMode: _editorMode,
              onEditorModeChange: (mode) {
                // CRITICAL: Stop all playback from ALL sections when switching modes
                // This prevents audio bleeding between DAW/Middleware/SlotLab
                _stopAllPlaybackOnModeSwitch();

                setState(() {
                  _editorMode = mode;
                  _activeLowerTab = getDefaultTabForMode(mode);
                  _activeLeftTab = LeftZoneTab.project;
                });
              },
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
              snapEnabled: _snapEnabled,
              snapValue: _snapValue,
              onSnapToggle: () {
                setState(() => _snapEnabled = !_snapEnabled);
                _dawLowerZoneController.setEditSubTab(DawEditSubTab.grid);
              },
              onSnapValueChange: (v) => setState(() => _snapValue = v),
              metronomeEnabled: _metronomeEnabled,
              onMetronomeToggle: () {
                final newState = !_metronomeEnabled;
                NativeFFI.instance.clickSetEnabled(newState);
                setState(() => _metronomeEnabled = newState);
              },
              memoryUsage: NativeFFI.instance.getMemoryUsage(),
              onToggleLeftZone: () => setState(() => _leftVisible = !_leftVisible),
              onToggleRightZone: () => setState(() => _rightVisible = !_rightVisible),
              onToggleLowerZone: () => setState(() => _lowerVisible = !_lowerVisible),
              menuCallbacks: _buildMenuCallbacks(),
              onBackToLauncher: widget.onBackToLauncher,
              onBackToMiddleware: _editorMode == EditorMode.slot
                  ? () => setState(() {
                      _editorMode = EditorMode.middleware;
                      _activeLowerTab = getDefaultTabForMode(EditorMode.middleware);
                    })
                  : null,
              // P3 Cloud callbacks
              onCloudSyncTap: _showCloudSyncDialog,
              onCollaborationTap: _showCollaborationDialog,
              onCrdtSyncTap: _showCrdtSyncDialog,
            ),

            // These props are no longer used when customControlBar is provided
            // but we keep minimal values for compatibility
            editorMode: _editorMode,

            // Left zone - mode-aware tree (pass compositeEvents for proper Provider listening)
            projectTree: _buildProjectTree(middlewareProvider.compositeEvents),
            activeLeftTab: _activeLeftTab,
            onLeftTabChange: (tab) => setState(() => _activeLeftTab = tab),
            onProjectSelect: _handlePoolItemClick,
            onProjectDoubleClick: _handlePoolItemDoubleClick,
            // External folder expansion from AudioAssetManager
            expandedFolderIds: assetManager.expandedFolderIds,
            onToggleFolderExpanded: assetManager.toggleFolder,

            // Channel tab data (DAW mode)
            channelData: _getSelectedChannelData(),
            onChannelVolumeChange: (channelId, volume) {
              final mixerProvider = context.read<MixerProvider>();
              // dB to linear: linear = 10^(dB/20)
              final linear = volume <= -60 ? 0.0 : math.pow(10.0, volume / 20.0).toDouble().clamp(0.0, 1.5);
              if (channelId == 'master') {
                mixerProvider.setMasterVolumeWithUndo(linear);
              } else {
                mixerProvider.setChannelVolumeWithUndo(channelId, linear);
              }
            },
            onChannelPanChange: (channelId, pan) {
              final mixerProvider = context.read<MixerProvider>();
              if (channelId == 'master') {
                // Master pan not commonly changed, but route to setChannelPan
                // which will be no-op — master pan is typically center
              } else {
                mixerProvider.setChannelPanWithUndo(channelId, pan);
              }
            },
            onChannelPanRightChange: (channelId, pan) {
              final mixerProvider = context.read<MixerProvider>();
              if (channelId != 'master') {
                mixerProvider.setChannelPanRightWithUndo(channelId, pan);
              }
            },
            onChannelMuteToggle: (channelId) {
              final mixerProvider = context.read<MixerProvider>();
              if (channelId == 'master') {
                return; // Master mute not commonly used
              } else {
                mixerProvider.toggleChannelMuteWithUndo(channelId);
                // Sync back to _tracks for track header
                final trackId = channelId.replaceFirst('ch_', '');
                final channel = mixerProvider.getChannel(channelId);
                if (channel != null) {
                  setState(() {
                    _tracks = _tracks.map((t) {
                      if (t.id == trackId) return t.copyWith(muted: channel.muted);
                      return t;
                    }).toList();
                  });
                }
              }
            },
            onChannelSoloToggle: (channelId) {
              final mixerProvider = context.read<MixerProvider>();
              if (channelId == 'master') return; // Master has no solo
              mixerProvider.toggleChannelSoloWithUndo(channelId);
              // Sync back to _tracks for track header
              final trackId = channelId.replaceFirst('ch_', '');
              final channel = mixerProvider.getChannel(channelId);
              if (channel != null) {
                setState(() {
                  _tracks = _tracks.map((t) {
                    if (t.id == trackId) return t.copyWith(soloed: channel.soloed);
                    return t;
                  }).toList();
                });
              }
            },
            onChannelInsertClick: (channelId, slotIndex) {
              _onInsertClick(channelId, slotIndex);
            },
            onChannelSendLevelChange: (channelId, sendIndex, level) {
              EngineApi.instance.setSendLevel(channelId, sendIndex, level);
            },
            onChannelEQToggle: (channelId) {
              setState(() {
                if (_openEqWindows.containsKey(channelId)) {
                  _openEqWindows.remove(channelId);
                } else {
                  _openEqWindows[channelId] = true;
                }
              });
            },
            onChannelOutputClick: (channelId) {
              _onOutputClick(channelId);
            },
            onChannelInputClick: (channelId) {
              _onInputClick(channelId);
            },
            onChannelArmToggle: (channelId) {
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.toggleArm(channelId);
              // Sync back to _tracks for track header
              final trackId = channelId.replaceFirst('ch_', '');
              final channel = mixerProvider.getChannel(channelId);
              if (channel != null) {
                setState(() {
                  _tracks = _tracks.map((t) {
                    if (t.id == trackId) return t.copyWith(armed: channel.armed);
                    return t;
                  }).toList();
                });
              }
            },
            onChannelMonitorToggle: (channelId) {
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.toggleInputMonitor(channelId);
              // Sync back to _tracks for track header
              final trackId = channelId.replaceFirst('ch_', '');
              final channel = mixerProvider.getChannel(channelId);
              if (channel != null) {
                setState(() {
                  _tracks = _tracks.map((t) {
                    if (t.id == trackId) return t.copyWith(inputMonitor: channel.monitorInput);
                    return t;
                  }).toList();
                });
              }
            },
            onChannelPhaseInvertToggle: (channelId) {
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.togglePhaseInvert(channelId);
            },
            onChannelSendClick: (channelId, sendIndex) {
              _onSendClick(channelId, sendIndex);
            },
            onChannelInsertBypassToggle: (channelId, slotIndex, bypassed) {
              final trackId = _busIdToTrackId(channelId);
              NativeFFI.instance.insertSetBypass(trackId, slotIndex, bypassed);
              // Update local state
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.updateInsertBypass(channelId, slotIndex, bypassed);
            },
            onChannelInsertWetDryChange: (channelId, slotIndex, wetDry) {
              final trackId = _busIdToTrackId(channelId);
              NativeFFI.instance.insertSetMix(trackId, slotIndex, wetDry);
              // Update local state
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.updateInsertWetDry(channelId, slotIndex, wetDry);
            },
            onChannelInsertRemove: (channelId, slotIndex) {
              final trackId = _busIdToTrackId(channelId);
              NativeFFI.instance.insertUnloadSlot(trackId, slotIndex);
              // Update local state
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.removeInsert(channelId, slotIndex);
            },
            onChannelInsertOpenEditor: (channelId, slotIndex) {
              // Resolve trackId: master='0', buses use _busIdToTrackId, channels use ch_N
              final trackId = _busIdToTrackId(channelId);

              // Check if this is an internal processor (from DspChainProvider)
              final chain = DspChainProvider.instance.getChain(trackId);
              if (slotIndex < chain.nodes.length) {
                final node = chain.nodes[slotIndex];
                // Show internal processor editor window
                InternalProcessorEditorWindow.show(
                  context: context,
                  trackId: trackId,
                  slotIndex: slotIndex,
                  node: node,
                );
              } else {
                // Check insert chain for plugin info
                final insertChain = _busInserts[channelId];
                if (insertChain != null && slotIndex < insertChain.slots.length) {
                  final slot = insertChain.slots[slotIndex];
                  if (!slot.isEmpty && slot.plugin != null) {
                    _openProcessorEditor(channelId, slotIndex, slot.plugin!);
                    return;
                  }
                }
                // External plugin - open via FFI
                NativeFFI.instance.insertOpenEditor(trackId, slotIndex);
              }
            },

            // Center zone - uses Selector internally for playhead
            child: _buildCenterContentOptimized(),

            // Inspector (for middleware mode) - only show when event is selected
            inspectorType: _selectedEvent != null ? InspectedObjectType.event : InspectedObjectType.none,
            inspectorName: _selectedEvent?.name,
            inspectorSections: _selectedEvent != null ? _buildInspectorSections() : const [],

            // Clip inspector (DAW mode)
            selectedClip: _clips.cast<timeline.TimelineClip?>().firstWhere(
              (c) => c?.selected == true,
              orElse: () => null,
            ),
            selectedClipTrack: _getSelectedClipTrack(),
            onClipChanged: _handleClipInspectorChange,
            onOpenClipFxEditor: _handleOpenClipFxEditor,

            // Lower zone - uses Section-specific Lower Zone widgets
            customLowerZone: _buildCustomLowerZone(),
            // Fallback tabs (used if customLowerZone returns null)
            lowerTabs: _buildLowerTabsOptimized(),
            lowerTabGroups: _buildTabGroups(),
            activeLowerTabId: _activeLowerTab,
            onLowerTabChange: (id) => setState(() => _activeLowerTab = id),

            // Zone visibility
            leftZoneVisible: _leftVisible,
            rightZoneVisible: _rightVisible,
            lowerZoneVisible: _lowerVisible,
            onLeftZoneToggle: () => setState(() => _leftVisible = !_leftVisible),
            onRightZoneToggle: () => setState(() => _rightVisible = !_rightVisible),
            onLowerZoneToggle: () => setState(() => _lowerVisible = !_lowerVisible),

            // Transport - SPACE key handling
            onPlay: () {
              // In middleware mode, SPACE triggers event preview
              if (_editorMode == EditorMode.middleware) {
                _previewEvent();
                return;
              }
              // In DAW mode, SPACE toggles playback
              final engine = context.read<EngineProvider>();
              if (engine.transport.isPlaying) {
                engine.pause();
              } else {
                engine.play();
              }
            },
          ),
          // Floating EQ windows - optimized
          ..._buildFloatingEqWindowsOptimized(),
        ],
      ),
          ),
        ),
      ),
    );
  }

  /// PERFORMANCE: Build menu callbacks using context.read() instead of Consumer
  MenuCallbacks _buildMenuCallbacks() {
    return MenuCallbacks(
      // FILE MENU
      onNewProject: () => _handleNewProject(context.read<EngineProvider>()),
      onOpenProject: () => _handleOpenProject(context.read<EngineProvider>()),
      onSaveProject: () => _handleSaveProject(context.read<EngineProvider>()),
      onSaveProjectAs: () => _handleSaveProjectAs(context.read<EngineProvider>()),
      onImportJSON: () => _handleImportJSON(),
      onExportJSON: () => _handleExportJSON(),
      onImportAudioFolder: () => _handleImportAudioFolder(),
      onImportAudioFiles: _openFilePicker,
      onExportAudio: () => _handleExportAudio(),
      onBatchExport: () => _handleBatchExport(),
      onExportPresets: () => _handleExportPresets(),
      onBounce: () => _handleBounce(),
      onRenderInPlace: () => _handleRenderInPlace(),
      // EDIT MENU
      onUndo: () => _handleUndo(),
      onRedo: () => _handleRedo(),
      onCut: () => _handleCut(),
      onCopy: () => _handleCopy(),
      onPaste: () => _handlePaste(),
      onDelete: () => _handleDelete(),
      onSelectAll: () => _handleSelectAll(),
      // VIEW MENU
      onToggleLeftPanel: () => setState(() => _leftVisible = !_leftVisible),
      onToggleRightPanel: () => setState(() => _rightVisible = !_rightVisible),
      onToggleLowerPanel: () => setState(() => _lowerVisible = !_lowerVisible),
      onResetLayout: () => _handleResetLayout(),
      onShowAudioPool: () => _handleShowAudioPool(),
      onShowMarkers: () => _handleShowMarkers(),
      onShowMidiEditor: () => _handleShowMidiEditor(),
      // PROJECT MENU
      onProjectSettings: () => _handleProjectSettings(),
      onTrackTemplates: () => _handleTrackTemplates(),
      onVersionHistory: () => _handleVersionHistory(),
      onFreezeSelectedTracks: () => _handleFreezeSelectedTracks(),
      onValidateProject: () => _handleValidateProject(),
      onBuildProject: () => _handleBuildProject(),
      // STUDIO MENU
      onAudioSettings: () => _handleAudioSettings(),
      onMidiSettings: () => _handleMidiSettings(),
      onPluginManager: () => _handlePluginManager(),
      onKeyboardShortcuts: () => _handleKeyboardShortcuts(),
      // ADVANCED PANELS
      onShowLogicalEditor: () => _showAdvancedPanel('logical-editor'),
      onShowScaleAssistant: () => _showAdvancedPanel('scale-assistant'),
      onShowGrooveQuantize: () => _showAdvancedPanel('groove-quantize'),
      onShowAudioAlignment: () => _showAdvancedPanel('audio-alignment'),
      onShowTrackVersions: () => _showAdvancedPanel('track-versions'),
      onShowMacroControls: () => _showAdvancedPanel('macro-controls'),
      onShowClipGainEnvelope: () => _showAdvancedPanel('clip-gain-envelope'),
      // CLOUD MENU (P3 Services)
      onCloudSync: () => _showCloudSyncDialog(),
      onCollaboration: () => _showCollaborationDialog(),
      onAssetCloud: () => _showAssetCloudDialog(),
      onMarketplace: () => _showMarketplaceDialog(),
      onAiMixing: () => _showAiMixingDialog(),
      onCrdtSync: () => _showCrdtSyncDialog(),
    );
  }

  /// PERFORMANCE: Center content without Consumer wrapper
  /// Uses the existing _buildDAWCenterContent which already has Selector inside
  Widget _buildCenterContentOptimized() {
    // Get transport data using read() - not reactive here, Timeline has its own Selector
    final engine = context.read<EngineProvider>();
    final transport = engine.transport;
    final metering = engine.metering;

    if (_editorMode == EditorMode.daw) {
      return _buildDAWCenterContent(transport, metering);
    } else {
      return _buildMiddlewareCenterContent();
    }
  }

  /// PERFORMANCE: Lower tabs without Consumer - use Selector for metering
  List<LowerZoneTab> _buildLowerTabsOptimized() {
    // Build tabs without metering dependency for static tabs
    // Metering tabs will use their own Selector internally
    return _buildLowerTabsStatic();
  }

  /// Build section-specific custom Lower Zone widget based on current editor mode
  Widget? _buildCustomLowerZone() {
    switch (_editorMode) {
      case EditorMode.daw:
        // Get selected track info for DSP panels and display
        final selectedTrackId = _selectedTrackId != null
            ? int.tryParse(_selectedTrackId!)
            : null;
        String? selectedTrackName;
        Color? selectedTrackColor;
        if (_selectedTrackId == '0' || _selectedTrackId == 'master') {
          selectedTrackName = 'Stereo Out';
          selectedTrackColor = const Color(0xFFFF9040);
        } else if (_selectedTrackId != null) {
          final track = _tracks.cast<timeline.TimelineTrack?>().firstWhere(
            (t) => t?.id == _selectedTrackId,
            orElse: () => null,
          );
          if (track != null) {
            selectedTrackName = track.name;
            selectedTrackColor = track.color;
          }
        }
        return DawLowerZoneWidget(
          controller: _dawLowerZoneController,
          selectedTrackId: selectedTrackId,
          selectedTrackName: selectedTrackName,
          selectedTrackColor: selectedTrackColor,
          onDspAction: (action, params) {
            switch (action) {
              case 'splitClip':
                // Split selected clip at playhead
                final selectedClip = _clips.cast<timeline.TimelineClip?>().firstWhere(
                  (c) => c?.selected == true,
                  orElse: () => null,
                );
                if (selectedClip != null) {
                  final transport = context.read<EngineProvider>().transport;
                  final splitTime = transport.positionSeconds;
                  if (splitTime > selectedClip.startTime && splitTime < selectedClip.endTime) {
                    final newClipId = engine.splitClip(clipId: selectedClip.id, atTime: splitTime);
                    if (newClipId != null) {
                      final leftDuration = splitTime - selectedClip.startTime;
                      final rightDuration = selectedClip.endTime - splitTime;
                      final rightOffset = selectedClip.sourceOffset + leftDuration;
                      setState(() {
                        _clips = _clips.where((c) => c.id != selectedClip.id).toList();
                        _clips.add(selectedClip.copyWith(duration: leftDuration));
                        _clips.add(timeline.TimelineClip(
                          id: newClipId,
                          trackId: selectedClip.trackId,
                          name: '${selectedClip.name} (2)',
                          startTime: splitTime,
                          duration: rightDuration,
                          color: selectedClip.color,
                          waveform: selectedClip.waveform,
                          sourceOffset: rightOffset,
                          sourceDuration: selectedClip.sourceDuration,
                          eventId: selectedClip.eventId,
                        ));
                      });
                      _showSnackBar('Split clip at ${splitTime.toStringAsFixed(2)}s');
                    }
                  }
                }
              case 'duplicateSelection':
                // Duplicate all selected clips
                final selectedClips = _clips.where((c) => c.selected).toList();
                for (final clip in selectedClips) {
                  final newClipId = engine.duplicateClip(clip.id);
                  if (newClipId != null) {
                    setState(() {
                      _clips.add(timeline.TimelineClip(
                        id: newClipId,
                        trackId: clip.trackId,
                        name: '${clip.name} (copy)',
                        startTime: clip.endTime,
                        duration: clip.duration,
                        color: clip.color,
                        waveform: clip.waveform,
                        sourceOffset: clip.sourceOffset,
                        sourceDuration: clip.sourceDuration,
                        eventId: clip.eventId,
                      ));
                    });
                  }
                }
                if (selectedClips.isNotEmpty) {
                  _showSnackBar('Duplicated ${selectedClips.length} clip(s)');
                }
              case 'deleteSelection':
                // Delete all selected clips
                _handleDelete();
              case 'addToProject':
                // Add audio file from Browse tab to timeline
                final path = params?['path'] as String?;
                if (path != null && path.isNotEmpty) {
                  _addFileToPool(path);
                  _showSnackBar('Added to project: ${path.split('/').last}');
                }
              case 'trackCreated':
                // Refresh timeline after track creation
                final trackId = params?['id'] as String?;
                if (trackId != null) {
                  _showSnackBar('Track created');
                }
              case 'copyDspSettings':
                // Copy DSP processor settings (placeholder — show feedback)
                final nodeType = params?['nodeType'] as String?;
                _showSnackBar('Copied ${nodeType ?? 'DSP'} settings');
              case 'quickExport':
                // Quick export with default settings
                _showSnackBar('Quick export started...');
                _handleQuickExport();
              case 'showExportDialog':
                // Open full export dialog
                _showExportDialog();
            }
          },
          // P0.2: Grid/Snap Settings
          snapEnabled: _snapEnabled,
          snapValue: _snapValue,
          tripletGrid: _tripletGrid,
          onSnapEnabledChanged: (v) => setState(() => _snapEnabled = v),
          onSnapValueChanged: (v) => setState(() => _snapValue = v),
          onTripletGridChanged: (v) => setState(() => _tripletGrid = v),
        );
      case EditorMode.middleware:
        return MiddlewareLowerZoneWidget(
          controller: _middlewareLowerZoneController,
        );
      case EditorMode.slot:
        // Slot mode uses fullscreen SlotLabScreen, not MainLayout
        // Return null to use default tabs (shouldn't reach here)
        return null;
    }
  }

  /// Lower tabs with live metering — watches EngineProvider so meters
  /// zero when transport stops (isPlaying → false triggers rebuild)
  List<LowerZoneTab> _buildLowerTabsStatic() {
    final engine = context.watch<EngineProvider>();
    final metering = engine.metering;
    final isPlaying = engine.transport.isPlaying;
    return _buildLowerTabs(metering, isPlaying);
  }

  /// PERFORMANCE: Floating EQ windows without Consumer
  List<Widget> _buildFloatingEqWindowsOptimized() {
    final engine = context.read<EngineProvider>();
    final metering = engine.metering;
    final isPlaying = engine.transport.isPlaying;
    return _buildFloatingEqWindows(metering, isPlaying);
  }

  Widget _buildCenterContent(dynamic transport, dynamic metering) {
    if (_editorMode == EditorMode.daw) {
      return _buildDAWCenterContent(transport, metering);
    } else {
      return _buildMiddlewareCenterContent();
    }
  }

  /// DAW Mode: Timeline in center - uses real Timeline widget
  Widget _buildDAWCenterContent(dynamic transport, dynamic metering) {
    // Convert TimeDisplayMode from layout_models to timeline_models
    timeline.TimeDisplayMode timelineDisplayMode;
    switch (_timeDisplayMode) {
      case TimeDisplayMode.bars:
        timelineDisplayMode = timeline.TimeDisplayMode.bars;
      case TimeDisplayMode.timecode:
        timelineDisplayMode = timeline.TimeDisplayMode.timecode;
      case TimeDisplayMode.samples:
        timelineDisplayMode = timeline.TimeDisplayMode.samples;
    }

    // PERFORMANCE: Use Selector for playhead position to avoid rebuilding entire timeline
    // when only playhead moves. This is critical for smooth performance with many tracks.
    return Selector<EngineProvider, double>(
      selector: (_, engine) => engine.transport.positionSeconds,
      builder: (context, playheadPosition, child) => timeline_widget.Timeline(
      tracks: _tracks,
      clips: _filteredClips, // Event-filtered clips
      markers: _markers,
      stageMarkers: _stageMarkers, // Game engine stage events
      crossfades: _crossfades,
      loopRegion: _loopRegion,
      loopEnabled: transport.loopEnabled,
      playheadPosition: playheadPosition,
      tempo: transport.tempo,
      timeSignatureNum: transport.timeSigNum,
      timeSignatureDenom: transport.timeSigDenom,
      zoom: _timelineZoom,
      scrollOffset: _timelineScrollOffset,
      totalDuration: 120,
      timeDisplayMode: timelineDisplayMode,
      sampleRate: 48000,
      snapEnabled: _snapEnabled,
      snapValue: _snapValue,
      isPlaying: transport.isPlaying, // For R button pulsing animation
      selectedTrackId: _selectedTrackId, // Sync track selection with Timeline
      // Import audio shortcut (Shift+Cmd+I)
      onImportAudio: _openFilePicker,
      // Export audio shortcut (Alt+Cmd+E)
      onExportAudio: _handleExportAudio,
      // File shortcuts (Cmd+S, Cmd+Shift+S, Cmd+O, Cmd+N)
      onSave: () => _handleSaveProject(context.read<EngineProvider>()),
      onSaveAs: () => _handleSaveProjectAs(context.read<EngineProvider>()),
      onOpen: () => _handleOpenProject(context.read<EngineProvider>()),
      onNew: () => _handleNewProject(context.read<EngineProvider>()),
      // Edit shortcuts
      onSelectAll: _handleSelectAllClips,
      onDeselect: _handleDeselectAll,
      // Track shortcuts (Cmd+T)
      onAddTrack: _handleAddTrack,
      // Playhead callbacks
      onPlayheadChange: (time) {
        final engine = context.read<EngineProvider>();
        engine.seek(time);
        // Auto-scroll only if content is wider than timeline
        const timelineWidth = 800.0;
        final maxEndTime = _clips.isEmpty ? 0.0 : _clips.map((c) => c.endTime).reduce((a, b) => a > b ? a : b);
        final contentWidth = maxEndTime * _timelineZoom;
        if (contentWidth > timelineWidth) {
          final centerOffset = time - (timelineWidth / 2) / _timelineZoom;
          setState(() {
            _timelineScrollOffset = centerOffset.clamp(0.0, double.infinity);
          });
        }
      },
      onPlayheadScrub: (time) {
        final engine = context.read<EngineProvider>();
        engine.scrubSeek(time); // Use throttled scrub seek
      },
      // Zoom/scroll callbacks
      onZoomChange: (zoom) => setState(() => _timelineZoom = zoom),
      onScrollChange: (offset) => setState(() => _timelineScrollOffset = offset),
      // Loop callbacks
      onLoopRegionChange: (region) {
        if (region != null) {
          engine.setLoopRegion(region.start, region.end);
        }
        setState(() => _loopRegion = region);
      },
      onLoopToggle: () {
        engine.toggleLoop();
      },
      // Clip callbacks
      onClipSelect: (clipId, multiSelect) {
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(selected: !c.selected || !multiSelect);
            }
            return multiSelect ? c : c.copyWith(selected: false);
          }).toList();

          // Auto-set loop region to selected clip bounds when loop is enabled
          final selectedClip = _clips.cast<timeline.TimelineClip?>().firstWhere(
            (c) => c?.id == clipId,
            orElse: () => null,
          );
          if (selectedClip != null && engine.transport.loopEnabled) {
            final clipStart = selectedClip.startTime;
            final clipEnd = selectedClip.startTime + selectedClip.duration;
            _loopRegion = timeline.LoopRegion(start: clipStart, end: clipEnd);
            engine.setLoopRegion(clipStart, clipEnd);
          }
        });
      },
      onClipMove: (clipId, newStartTime) {
        final clip = _clips.firstWhere((c) => c.id == clipId);
        final oldStartTime = clip.startTime;

        // Record undo action
        UiUndoManager.instance.record(GenericUndoAction(
          description: 'Move clip',
          onExecute: () {
            engine.moveClip(clipId: clipId, targetTrackId: clip.trackId, startTime: newStartTime);
            setState(() {
              _clips = _clips.map((c) => c.id == clipId ? c.copyWith(startTime: newStartTime) : c).toList();
            });
          },
          onUndo: () {
            engine.moveClip(clipId: clipId, targetTrackId: clip.trackId, startTime: oldStartTime);
            setState(() {
              _clips = _clips.map((c) => c.id == clipId ? c.copyWith(startTime: oldStartTime) : c).toList();
            });
          },
        ));

        // Execute move
        engine.moveClip(clipId: clipId, targetTrackId: clip.trackId, startTime: newStartTime);
        setState(() {
          _clips = _clips.map((c) => c.id == clipId ? c.copyWith(startTime: newStartTime) : c).toList();
        });

        // Auto-create crossfade if clip overlaps with another clip on same track
        _createAutoCrossfadeIfOverlap(clipId, clip.trackId);
      },
      onClipMoveToTrack: (clipId, targetTrackId, newStartTime) {
        // Move clip to a different track
        engine.moveClip(
          clipId: clipId,
          targetTrackId: targetTrackId,
          startTime: newStartTime,
        );
        // Get target track's color
        final targetTrack = _tracks.firstWhere(
          (t) => t.id == targetTrackId,
          orElse: () => _tracks.first,
        );
        setState(() {
          // Auto-select the target track
          _selectedTrackId = targetTrackId;
          _activeLeftTab = LeftZoneTab.channel;

          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(
                trackId: targetTrackId,
                startTime: newStartTime,
                color: targetTrack.color, // Sync clip color with target track
                selected: true, // Select the moved clip
              );
            }
            // Deselect other clips
            return c.copyWith(selected: false);
          }).toList();
        });
      },
      onClipMoveToNewTrack: (clipId, newStartTime) {
        // Create a new track - use engine's returned ID
        final trackIndex = _tracks.length;
        final trackName = 'Audio ${trackIndex + 1}';
        final color = _defaultTrackColor;

        // Get channel count from original clip's track
        final clip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
        final originalTrack = _tracks.firstWhere(
          (t) => t.id == clip.trackId,
          orElse: () => _tracks.first,
        );
        final channels = originalTrack.channels;

        // Create track in native engine - GET THE REAL ID
        final newTrackId = engine.createTrack(
          name: trackName,
          color: color.value,
          busId: 0,
        );

        // Create mixer channel for the new track (must use real engine ID)
        final mixerProvider = context.read<MixerProvider>();
        mixerProvider.createChannelFromTrack(newTrackId, trackName, color, channels: channels);

        // Move clip to new track in engine
        engine.moveClip(
          clipId: clipId,
          targetTrackId: newTrackId,
          startTime: newStartTime,
        );

        setState(() {
          // Add the new track
          _tracks = [
            ..._tracks,
            timeline.TimelineTrack(
              id: newTrackId,
              name: trackName,
              color: color,
              outputBus: timeline.OutputBus.master,
              channels: channels, // Preserve channel count from original
            ),
          ];

          // Auto-select the new track
          _selectedTrackId = newTrackId;
          _activeLeftTab = LeftZoneTab.channel;

          // Update clip's track assignment and color
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(
                trackId: newTrackId,
                startTime: newStartTime,
                color: color, // Sync clip color with new track
                selected: true, // Select the moved clip
              );
            }
            // Deselect other clips
            return c.copyWith(selected: false);
          }).toList();
        });
      },
      onClipResize: (clipId, newStartTime, newDuration, newOffset) {
        // Validate resize parameters
        if (newDuration < 0.01 || newStartTime < 0) return;

        // Find clip for validation
        final clip = _clips.firstWhere(
          (c) => c.id == clipId,
          orElse: () => timeline.TimelineClip(
            id: '', trackId: '', name: '', startTime: 0, duration: 0,
          ),
        );
        if (clip.id.isEmpty) return;

        final effectiveOffset = newOffset ?? clip.sourceOffset;
        if (clip.sourceDuration != null && effectiveOffset > clip.sourceDuration!) return;

        // Update UI immediately for smooth visual feedback
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(
                startTime: newStartTime,
                duration: newDuration,
                sourceOffset: effectiveOffset,
              );
            }
            return c;
          }).toList();
        });

        // Throttle FFI calls - only call engine every 100ms during drag
        _pendingResize = {
          'clipId': clipId,
          'startTime': newStartTime,
          'duration': newDuration,
          'sourceOffset': effectiveOffset,
        };

        _resizeThrottleTimer ??= Timer(const Duration(milliseconds: 100), () {
          _resizeThrottleTimer = null;
          if (_pendingResize != null) {
            try {
              engine.resizeClip(
                clipId: _pendingResize!['clipId'],
                startTime: _pendingResize!['startTime'],
                duration: _pendingResize!['duration'],
                sourceOffset: _pendingResize!['sourceOffset'],
              );
            } catch (_) {
              // Ignore resize errors
            }
            _pendingResize = null;
          }
        });
      },
      onClipResizeEnd: (clipId) {
        // Final FFI commit when resize drag ends
        _resizeThrottleTimer?.cancel();
        _resizeThrottleTimer = null;
        if (_pendingResize != null && _pendingResize!['clipId'] == clipId) {
          try {
            engine.resizeClip(
              clipId: _pendingResize!['clipId'],
              startTime: _pendingResize!['startTime'],
              duration: _pendingResize!['duration'],
              sourceOffset: _pendingResize!['sourceOffset'],
            );
          } catch (_) {
            // Ignore resize end errors
          }
          _pendingResize = null;
        }
      },
      onClipGainChange: (clipId, gain) {
        // Notify engine
        engine.setClipGain(clipId, gain);
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(gain: gain);
            }
            return c;
          }).toList();
        });
      },
      onClipFadeChange: (clipId, fadeIn, fadeOut) {
        // Update Flutter state
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(fadeIn: fadeIn, fadeOut: fadeOut);
            }
            return c;
          }).toList();
        });
        // Sync to audio engine (use EngineApi.instance for clip operations)
        EngineApi.instance.fadeInClip(clipId, fadeIn);
        EngineApi.instance.fadeOutClip(clipId, fadeOut);
      },
      onClipRename: (clipId, newName) {
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(name: newName);
            }
            return c;
          }).toList();
        });
      },
      onClipSlipEdit: (clipId, newSourceOffset) {
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(sourceOffset: newSourceOffset);
            }
            return c;
          }).toList();
        });
      },
      onClipOpenAudioEditor: (clipId) {
        // Find clip and open audio editor dialog
        final clip = _clips.where((c) => c.id == clipId).firstOrNull;
        if (clip == null) return;

        // Open audio editor in dialog with StatefulBuilder for local state
        showDialog(
          context: context,
          builder: (dialogContext) => _AudioEditorDialog(
            initialClip: clip,
            onClipChanged: (updatedClip) {
              setState(() {
                _clips = _clips.map((c) {
                  if (c.id == updatedClip.id) return updatedClip;
                  return c;
                }).toList();
              });
            },
            curveToInt: _curveToInt,
          ),
        );
      },
      onClipSplit: (clipId) {
        // Split clip at playhead
        final clip = _clips.firstWhere((c) => c.id == clipId);
        final splitTime = transport.positionSeconds;
        if (splitTime <= clip.startTime || splitTime >= clip.endTime) return;

        // Notify engine - returns new clip ID
        final newClipId = engine.splitClip(clipId: clipId, atTime: splitTime);
        if (newClipId == null) return;

        final leftDuration = splitTime - clip.startTime;
        final rightDuration = clip.endTime - splitTime;
        final rightOffset = clip.sourceOffset + leftDuration;

        setState(() {
          _clips = _clips.where((c) => c.id != clipId).toList();
          _clips.add(clip.copyWith(duration: leftDuration));
          _clips.add(timeline.TimelineClip(
            id: newClipId,
            trackId: clip.trackId,
            name: '${clip.name} (2)',
            startTime: splitTime,
            duration: rightDuration,
            color: clip.color,
            waveform: clip.waveform,
            sourceOffset: rightOffset,
            sourceDuration: clip.sourceDuration,
            eventId: clip.eventId, // Preserve original event
          ));
        });
      },
      onClipDuplicate: (clipId) {
        final clip = _clips.firstWhere((c) => c.id == clipId);

        // Notify engine - returns new clip ID
        final newClipId = engine.duplicateClip(clipId);
        if (newClipId == null) return;

        setState(() {
          _clips.add(timeline.TimelineClip(
            id: newClipId,
            trackId: clip.trackId,
            name: '${clip.name} (copy)',
            startTime: clip.endTime,
            duration: clip.duration,
            color: clip.color,
            waveform: clip.waveform,
            sourceOffset: clip.sourceOffset,
            sourceDuration: clip.sourceDuration,
            eventId: clip.eventId, // Preserve original event
          ));
        });
      },
      onClipDelete: (clipId) {
        // In middleware mode, sync deletion to event actions FIRST
        // (before removing clip from list, as we need to find the track)
        if (_editorMode == EditorMode.middleware && clipId.startsWith('evt_clip_')) {
          _syncClipDeletionToEvent(clipId);
          // After syncing, reload timeline to update indices
          final eventId = _selectedEventId;
          if (eventId.isNotEmpty) {
            // Defer reload to after setState completes
            Future.microtask(() => _loadEventToTimeline(eventId));
          }
        }
        // Notify engine and invalidate waveform cache
        engine.deleteClip(clipId);
        WaveformCache().remove(clipId);
        setState(() {
          _clips = _clips.where((c) => c.id != clipId).toList();
        });
      },
      // Track callbacks - SYNC both _tracks AND MixerProvider
      onTrackMuteToggle: (trackId) {
        final track = _tracks.firstWhere((t) => t.id == trackId);
        final newMuted = !track.muted;
        // INSTANT UI feedback first
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(muted: newMuted);
            }
            return t;
          }).toList();
        });
        // Then sync with engine and MixerProvider
        engine.updateTrack(trackId, muted: newMuted);
        context.read<MixerProvider>().setMuted('ch_$trackId', newMuted);
      },
      onTrackSoloToggle: (trackId) {
        final track = _tracks.firstWhere((t) => t.id == trackId);
        final newSoloed = !track.soloed;
        // INSTANT UI feedback first
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(soloed: newSoloed);
            }
            return t;
          }).toList();
        });
        // Then sync with engine and MixerProvider
        engine.updateTrack(trackId, soloed: newSoloed);
        context.read<MixerProvider>().setSoloed('ch_$trackId', newSoloed);
      },
      onTrackArmToggle: (trackId) {
        final track = _tracks.firstWhere((t) => t.id == trackId);
        final newArmed = !track.armed;
        // INSTANT UI feedback first
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(armed: newArmed);
            }
            return t;
          }).toList();
        });
        // Then sync with engine, MixerProvider, and RecordingProvider
        engine.updateTrack(trackId, armed: newArmed);
        context.read<MixerProvider>().setArmed('ch_$trackId', newArmed);
        // Sync with RecordingProvider for recording panel
        final trackIdInt = int.tryParse(trackId) ?? 0;
        final recordingProvider = context.read<RecordingProvider>();
        if (newArmed) {
          recordingProvider.armTrack(trackIdInt, numChannels: track.isStereo ? 2 : 1);
        } else {
          recordingProvider.disarmTrack(trackIdInt);
        }
      },
      onTrackVolumeChange: (trackId, volume) {
        engine.updateTrack(trackId, volume: volume);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(volume: volume);
            }
            return t;
          }).toList();
        });
      },
      onTrackPanChange: (trackId, pan) {
        engine.updateTrack(trackId, pan: pan);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(pan: pan);
            }
            return t;
          }).toList();
        });
      },
      onTrackColorChange: (trackId, color) {
        _handleTrackColorChange(trackId, color);
      },
      onTrackBusChange: (trackId, bus) {
        engine.updateTrack(trackId, busId: bus.index);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(outputBus: bus);
            }
            return t;
          }).toList();
        });
      },
      onTrackRename: (trackId, newName) {
        engine.updateTrack(trackId, name: newName);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(name: newName);
            }
            return t;
          }).toList();
        });
      },
      onTrackFreezeToggle: (trackId) {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(frozen: !t.frozen);
            }
            return t;
          }).toList();
        });
      },
      onTrackLockToggle: (trackId) {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(locked: !t.locked);
            }
            return t;
          }).toList();
        });
      },
      onTrackHideToggle: (trackId) {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(hidden: !t.hidden);
            }
            return t;
          }).toList();
        });
      },
      onTrackHeightChange: (trackId, height) {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(height: height);
            }
            return t;
          }).toList();
        });
      },
      onTrackMonitorToggle: (trackId) {
        final track = _tracks.firstWhere((t) => t.id == trackId);
        final newMonitor = !track.inputMonitor;
        // INSTANT UI feedback first
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(inputMonitor: newMonitor);
            }
            return t;
          }).toList();
        });
        // Then sync with MixerProvider
        context.read<MixerProvider>().setInputMonitor('ch_$trackId', newMonitor);
      },
      // Marker callback
      onMarkerClick: (markerId) {
        final marker = _markers.firstWhere((m) => m.id == markerId);
        final engine = context.read<EngineProvider>();
        engine.seek(marker.time);
      },
      // Crossfade callbacks
      onCrossfadeUpdate: (crossfadeId, duration) {
        setState(() {
          _crossfades = _crossfades.map((x) {
            if (x.id == crossfadeId) {
              return x.copyWith(duration: duration);
            }
            return x;
          }).toList();
        });
      },
      onCrossfadeFullUpdate: (crossfadeId, startTime, duration) {
        setState(() {
          _crossfades = _crossfades.map((x) {
            if (x.id == crossfadeId) {
              return x.copyWith(startTime: startTime, duration: duration);
            }
            return x;
          }).toList();
        });
      },
      onCrossfadeDelete: (crossfadeId) {
        setState(() {
          _crossfades = _crossfades.where((x) => x.id != crossfadeId).toList();
        });
      },
      // File drop callback for drag & drop audio files from system
      onFileDrop: (filePath, trackId, startTime) {
        _handleFileDrop(filePath, trackId, startTime);
      },
      // Pool file drop callback for drag & drop from Audio Pool
      onPoolFileDrop: (poolFile, trackId, startTime) {
        if (poolFile is timeline.PoolAudioFile) {
          _addPoolFileToTimeline(
            poolFile,
            targetTrackId: trackId,
            startTime: startTime,
          );
        }
      },
      // Track duplicate/delete
      onTrackDuplicate: (trackId) => _handleDuplicateTrack(trackId),
      onTrackDelete: (trackId) => _handleDeleteTrackById(trackId),
      // Track reorder (bidirectional sync with mixer)
      onTrackReorder: (oldIndex, newIndex) => _handleTrackReorder(oldIndex, newIndex),
      // Track selection for Channel tab - auto switch to Channel tab
      // Also auto-select first clip on this track to show Gain & Fades section
      onTrackSelect: (trackId) {
        setState(() {
          _selectedTrackId = trackId;
          _activeLeftTab = LeftZoneTab.channel;

          // Auto-select first clip on this track (for Gain & Fades section)
          // First deselect all clips
          _clips = _clips.map((c) => c.copyWith(selected: false)).toList();

          // Find first clip on this track and select it
          final trackClips = _clips.where((c) => c.trackId == trackId).toList();
          if (trackClips.isNotEmpty) {
            // Sort by start time and select first
            trackClips.sort((a, b) => a.startTime.compareTo(b.startTime));
            final firstClip = trackClips.first;
            _clips = _clips.map((c) {
              if (c.id == firstClip.id) return c.copyWith(selected: true);
              return c;
            }).toList();
          }
        });

        // In middleware mode, track selection = action selection
        // Track IDs are "evt_track_0", "evt_track_1", etc. - extract index
        if (_editorMode == EditorMode.middleware && trackId.startsWith('evt_track_')) {
          final indexStr = trackId.substring('evt_track_'.length);
          final actionIndex = int.tryParse(indexStr) ?? -1;
          if (actionIndex >= 0) {
            _selectAction(actionIndex);
          }
        }
      },
      // Track context menu
      onTrackContextMenu: (trackId, position) {
        _showTrackContextMenu(trackId, position);
      },
      // Transport shortcuts (SPACE)
      onPlayPause: () {
        // In middleware mode, SPACE triggers event preview
        if (_editorMode == EditorMode.middleware) {
          _previewEvent();
          return;
        }
        // In DAW mode, SPACE toggles playback
        if (engine.transport.isPlaying) {
          engine.pause();
        } else {
          engine.play();
        }
      },
      onStop: () => engine.stop(),
      // Undo/Redo shortcuts (Cmd+Z, Cmd+Shift+Z) - always enabled
      onUndo: () => _handleUndo(),
      onRedo: () => _handleRedo(),
      // Automation lane callbacks - sync with Rust engine
      onAutomationLaneChanged: (trackId, laneData) {
        // Update local state
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              final updatedLanes = t.automationLanes.map((l) {
                if (l.id == laneData.id) return laneData;
                return l;
              }).toList();
              return t.copyWith(automationLanes: updatedLanes);
            }
            return t;
          }).toList();
        });

        // Sync points to Rust engine
        final trackIdInt = int.tryParse(trackId) ?? 0;
        final paramName = laneData.parameterName.toLowerCase();
        final ffi = NativeFFI.instance;

        // Clear existing lane in engine and re-add all points
        ffi.automationClearLane(trackIdInt, paramName);

        for (final point in laneData.points) {
          final timeSamples = (point.time * 48000).toInt(); // 48kHz sample rate
          ffi.automationAddPoint(
            trackIdInt,
            paramName,
            timeSamples,
            point.value,
            curveType: point.curveType.index,
          );
        }
      },
      onAddAutomationLane: (trackId, parameter) {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              final newLane = AutomationLaneData(
                id: 'lane_${DateTime.now().millisecondsSinceEpoch}',
                parameter: parameter,
                parameterName: _getParameterName(parameter),
                points: [],
                mode: AutomationMode.read,
                color: _getParameterColor(parameter),
              );
              return t.copyWith(
                automationLanes: [...t.automationLanes, newLane],
                automationExpanded: true,
              );
            }
            return t;
          }).toList();
        });
      },
      onRemoveAutomationLane: (trackId, laneId) {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              final updatedLanes = t.automationLanes
                  .where((l) => l.id != laneId)
                  .toList();
              return t.copyWith(automationLanes: updatedLanes);
            }
            return t;
          }).toList();
        });

        // Clear lane in Rust engine
        final lane = _tracks
            .firstWhere((t) => t.id == trackId)
            .automationLanes
            .firstWhere((l) => l.id == laneId, orElse: () => AutomationLaneData(
              id: '',
              parameter: AutomationParameter.volume,
              parameterName: '',
            ));
        if (lane.id.isNotEmpty) {
          final trackIdInt = int.tryParse(trackId) ?? 0;
          NativeFFI.instance.automationClearLane(trackIdInt, lane.parameterName.toLowerCase());
        }
      },
    ),
    ); // Close Selector wrapper
  }

  // Complete Wwise/FMOD-style action types
  static const List<String> kActionTypes = [
    'Play', 'PlayAndContinue', 'Stop', 'StopAll', 'Pause', 'PauseAll',
    'Resume', 'ResumeAll', 'Break', 'Mute', 'Unmute', 'SetVolume',
    'SetPitch', 'SetLPF', 'SetHPF', 'SetBusVolume', 'SetState',
    'SetSwitch', 'SetRTPC', 'ResetRTPC', 'Seek', 'Trigger', 'PostEvent',
  ];

  // Complete bus list (for middleware mode dropdowns)
  // ignore: unused_field
  static const List<String> kBuses = [
    'Master', 'Music', 'SFX', 'Voice', 'UI', 'Ambience', 'Reels', 'Wins', 'VO',
  ];

  // Complete event list (for middleware mode dropdowns)
  // ignore: unused_field
  static const List<String> kEvents = [
    'Play_Music', 'Stop_Music', 'Play_SFX', 'Stop_All', 'Pause_All',
    'Set_State', 'Trigger_Win', 'Spin_Start', 'Spin_Stop', 'Reel_Land',
    'BigWin_Start', 'BigWin_Loop', 'BigWin_End', 'Bonus_Enter', 'Bonus_Exit',
    'UI_Click', 'UI_Hover', 'Ambient_Start', 'Ambient_Stop', 'VO_Play',
  ];

  // Asset IDs (for middleware mode dropdowns)
  // ignore: unused_field
  static const List<String> kAssetIds = [
    'music_main', 'music_bonus', 'music_freespins', 'music_bigwin',
    'sfx_spin', 'sfx_reel_land', 'sfx_win_small', 'sfx_win_medium', 'sfx_win_big',
    'sfx_click', 'sfx_hover', 'sfx_coins', 'sfx_jackpot',
    'amb_casino', 'amb_nature', 'amb_crowd',
    'vo_bigwin', 'vo_megawin', 'vo_jackpot', 'vo_freespins',
    '—',
  ];

  // Scope options
  static const List<String> kScopes = [
    'Global', 'Game Object', 'Emitter', 'All', 'First Only', 'Random',
  ];

  // Priority options
  static const List<String> kPriorities = [
    'Highest', 'High', 'Above Normal', 'Normal', 'Below Normal', 'Low', 'Lowest',
  ];

  // Fade curve types
  static const List<String> kFadeCurves = [
    'Linear', 'Log3', 'Sine', 'Log1', 'InvSCurve', 'SCurve', 'Exp1', 'Exp3',
  ];

  // State groups (Wwise-style) - for middleware dropdowns
  // ignore: unused_field
  static const List<String> kStateGroups = [
    'GameState', 'MusicState', 'PlayerState', 'BonusState', 'Intensity',
  ];

  // States per group - for middleware dropdowns
  // ignore: unused_field
  static const Map<String, List<String>> kStates = {
    'GameState': ['Menu', 'BaseGame', 'Bonus', 'FreeSpins', 'Paused'],
    'MusicState': ['Normal', 'Suspense', 'Action', 'Victory', 'Defeat'],
    'PlayerState': ['Idle', 'Spinning', 'Winning', 'Waiting'],
    'BonusState': ['None', 'Triggered', 'Active', 'Ending'],
    'Intensity': ['Low', 'Medium', 'High', 'Extreme'],
  };

  // Switch groups - for middleware dropdowns
  // ignore: unused_field
  static const List<String> kSwitchGroups = [
    'Surface', 'Footsteps', 'Material', 'Weapon', 'Environment',
  ];

  /// Middleware Mode: Events Editor in center - FULLY FUNCTIONAL
  Widget _buildMiddlewareCenterContent() {
    // Use Consumer to rebuild when MiddlewareProvider changes
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        // Get selected event from provider (single source of truth)
        final selectedCompositeId = middleware.selectedCompositeEventId;
        final compositeEvents = middleware.compositeEvents;

        // Auto-select first event if nothing is selected and events exist
        if (selectedCompositeId == null && compositeEvents.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final first = compositeEvents.first;
            middleware.selectCompositeEvent(first.id);
            setState(() {
              _selectedEventId = 'mw_${first.id}';
              _selectedActionIndex = -1;
              _selectedLayerIndex = first.layers.isNotEmpty ? 0 : -1;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _syncHeaderFromSelectedLayer();
            });
          });
        }

        // Find currently selected composite event
        SlotCompositeEvent? selectedComposite = selectedCompositeId != null
            ? compositeEvents.where((e) => e.id == selectedCompositeId).firstOrNull
            : null;

        // If provider has selection but we don't have local sync yet, sync now
        if (selectedComposite != null && _selectedEventId.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _selectedEventId = 'mw_${selectedComposite.id}';
              _selectedLayerIndex = selectedComposite.layers.isNotEmpty ? 0 : -1;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _syncHeaderFromSelectedLayer();
            });
          });
        }

        // Get MiddlewareEvent for display (synced or empty)
        MiddlewareEvent? event;
        if (selectedComposite != null) {
          final middlewareId = 'mw_${selectedComposite.id}';
          event = middleware.events.where((e) => e.id == middlewareId).firstOrNull;
          // Create empty event if not synced yet (no layers)
          event ??= MiddlewareEvent(
            id: middlewareId,
            name: selectedComposite.name,
            category: 'Slot_${selectedComposite.category}',
            actions: [],
          );
          // NOTE: Local state sync is now handled in build() method
        }

        final eventName = event?.name ?? 'No Event Selected';
        final actionCount = event?.actions.length ?? 0;

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Unified Layer Command Bar — responsive, grouped, all params
          Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // ── EVENT SELECTOR GROUP ──
                      _CommandGroup(
                        children: [
                          Builder(
                            builder: (context) {
                              final eventNames = compositeEvents.map((e) => e.name).toList();
                              if (eventNames.isEmpty) {
                                return _CommandChip(
                                  icon: Icons.api,
                                  label: 'No Events',
                                  color: FluxForgeTheme.textTertiary,
                                );
                              }
                              return _ToolbarDropdown(
                                icon: Icons.api,
                                label: '',
                                value: eventName,
                                options: eventNames,
                                onChanged: (val) {
                                  final composite = compositeEvents.firstWhere((e) => e.name == val);
                                  final middlewareId = 'mw_${composite.id}';
                                  setState(() {
                                    _selectedEventId = middlewareId;
                                    _selectedActionIndex = -1;
                                    _selectedLayerIndex = composite.layers.isNotEmpty ? 0 : -1;
                                  });
                                  middleware.selectCompositeEvent(composite.id);
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _syncHeaderFromSelectedLayer();
                                  });
                                },
                                accentColor: FluxForgeTheme.accentOrange,
                              );
                            },
                          ),
                          _CommandChip(
                            label: '$actionCount',
                            icon: Icons.layers,
                            color: FluxForgeTheme.textSecondary,
                          ),
                        ],
                      ),

                      // ── ACTION BUTTONS ──
                      _CommandGroup(
                        children: [
                          _CommandIconBtn(icon: Icons.note_add_rounded, tooltip: 'New Event', onTap: () => _createNewEvent(middleware), color: FluxForgeTheme.accentOrange),
                          _CommandIconBtn(icon: Icons.add, tooltip: 'Add Layer', onTap: () => _showAddActionDialog(), color: FluxForgeTheme.accentGreen),
                          _CommandIconBtn(icon: Icons.play_arrow_rounded, tooltip: 'Preview', onTap: _previewEvent, color: FluxForgeTheme.accentCyan),
                          _CommandIconBtn(icon: Icons.copy_rounded, tooltip: 'Duplicate', onTap: _selectedActionIndex >= 0 ? () => _duplicateAction(_selectedActionIndex) : null),
                          _CommandIconBtn(icon: Icons.delete_outline_rounded, tooltip: 'Delete Layer', onTap: () {
                            final comp = selectedComposite;
                            final li = _selectedLayerIndex;
                            if (comp == null || li < 0 || li >= comp.layers.length) return;
                            _deleteLayer(comp, li);
                          }, color: FluxForgeTheme.accentRed),
                        ],
                      ),

                      // ── UTILITIES ──
                      _CommandGroup(
                        children: [
                          _CommandIconBtn(icon: _middlewareGridView ? Icons.grid_view_rounded : Icons.view_list_rounded, tooltip: 'Toggle View', onTap: () => setState(() => _middlewareGridView = !_middlewareGridView)),
                          PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'export') _exportEventsToJson();
                              if (val == 'import') _importEventsFromJson();
                            },
                            offset: const Offset(0, 28),
                            color: FluxForgeTheme.bgElevated,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: FluxForgeTheme.borderSubtle)),
                            itemBuilder: (context) => [
                              PopupMenuItem(value: 'export', height: 28, child: Row(children: [Icon(Icons.upload, size: 13, color: FluxForgeTheme.textSecondary), const SizedBox(width: 6), Text('Export', style: TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary))])),
                              PopupMenuItem(value: 'import', height: 28, child: Row(children: [Icon(Icons.download, size: 13, color: FluxForgeTheme.textSecondary), const SizedBox(width: 6), Text('Import', style: TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary))])),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.import_export, size: 14, color: FluxForgeTheme.textSecondary),
                            ),
                          ),
                          _CommandIconBtn(icon: Icons.settings, tooltip: 'Settings', onTap: _showSettingsDialog),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Layers table styled as Actions - uses SlotCompositeEvent.layers but with original UI
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: _buildLayersAsActionsTable(constraints.maxWidth, selectedComposite, middleware),
                );
              },
            ),
          ),
        ],
      ),
    );
      },
    );  // End Consumer
  }

  /// Build Timeline UI for Middleware - DAW-style with tracks and time ruler
  Widget _buildMiddlewareTimeline(SlotCompositeEvent? event) {
    if (event == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 48, color: FluxForgeTheme.textTertiary),
            const SizedBox(height: 12),
            Text('Select an event to view timeline', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ],
        ),
      );
    }

    // Calculate timeline dimensions from layers
    final layers = event.layers;
    final totalDuration = event.totalDurationSeconds.clamp(2.0, 60.0);
    final totalWidth = totalDuration * _kMiddlewarePixelsPerSecond * _middlewareTimelineZoom;

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Timeline toolbar with zoom controls
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                // Event info
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  event.name,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: FluxForgeTheme.textPrimary),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${layers.length} layers',
                    style: TextStyle(fontSize: 10, color: FluxForgeTheme.accentBlue),
                  ),
                ),
                const Spacer(),
                // Zoom controls
                IconButton(
                  icon: Icon(Icons.remove, size: 16, color: FluxForgeTheme.textSecondary),
                  onPressed: () => setState(() => _middlewareTimelineZoom = (_middlewareTimelineZoom * 0.8).clamp(0.25, 4.0)),
                  tooltip: 'Zoom out',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                Text(
                  '${(_middlewareTimelineZoom * 100).round()}%',
                  style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
                ),
                IconButton(
                  icon: Icon(Icons.add, size: 16, color: FluxForgeTheme.textSecondary),
                  onPressed: () => setState(() => _middlewareTimelineZoom = (_middlewareTimelineZoom * 1.25).clamp(0.25, 4.0)),
                  tooltip: 'Zoom in',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                const SizedBox(width: 8),
                // Fit to view
                IconButton(
                  icon: Icon(Icons.fit_screen, size: 16, color: FluxForgeTheme.textSecondary),
                  onPressed: () => setState(() => _middlewareTimelineZoom = 1.0),
                  tooltip: 'Fit to view',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          // Timeline content
          Expanded(
            child: Row(
              children: [
                // Track headers (fixed width)
                SizedBox(
                  width: _kMiddlewareTrackHeaderWidth,
                  child: Column(
                    children: [
                      // Ruler header
                      Container(
                        height: _kMiddlewareRulerHeight,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgElevated,
                          border: Border(
                            bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
                            right: BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                        ),
                        child: Center(
                          child: Text('Time', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
                        ),
                      ),
                      // Track headers
                      Expanded(
                        child: ListView.builder(
                          itemCount: layers.length,
                          itemBuilder: (context, index) {
                            final layer = layers[index];
                            final isSelected = index == _selectedLayerIndex;
                            return _buildLayerTrackHeader(event, layer, index, isSelected);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Timeline area (scrollable)
                Expanded(
                  child: Column(
                    children: [
                      // Time ruler
                      _buildMiddlewareTimeRuler(totalDuration, totalWidth),
                      // Tracks with regions
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _middlewareTimelineScrollController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: totalWidth + 100,
                            child: Stack(
                              children: [
                                // Grid background
                                CustomPaint(
                                  size: Size(totalWidth + 100, layers.length * _kMiddlewareTrackHeight),
                                  painter: _MiddlewareTimelineGridPainter(
                                    zoom: _middlewareTimelineZoom,
                                    pixelsPerSecond: _kMiddlewarePixelsPerSecond,
                                    trackHeight: _kMiddlewareTrackHeight,
                                    trackCount: layers.length,
                                  ),
                                ),
                                // Layer regions
                                ...layers.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final layer = entry.value;
                                  final isSelected = index == _selectedLayerIndex;
                                  return _buildLayerRegion(layer, index, isSelected, totalWidth, totalDuration);
                                }),
                                // Playhead
                                Positioned(
                                  left: _middlewarePlayheadPosition * _kMiddlewarePixelsPerSecond * _middlewareTimelineZoom,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 2,
                                    color: FluxForgeTheme.accentGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Track header for layer in middleware timeline
  Widget _buildLayerTrackHeader(SlotCompositeEvent event, SlotEventLayer layer, int index, bool isSelected) {
    final layerColor = FluxForgeTheme.accentBlue;

    return GestureDetector(
      onTap: () => _selectLayerAndSync(index),
      child: Container(
        height: _kMiddlewareTrackHeight,
        decoration: BoxDecoration(
          color: isSelected ? layerColor.withValues(alpha: 0.15) : FluxForgeTheme.bgMid,
          border: Border(
            bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5),
            right: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Index number
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: layerColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: layerColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Layer name and audio file
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layer.name,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: FluxForgeTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (layer.audioPath.isNotEmpty)
                    Text(
                      layer.audioPath.split('/').last,
                      style: TextStyle(fontSize: 9, color: FluxForgeTheme.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Mute/Solo buttons
            IconButton(
              icon: Icon(
                layer.muted ? Icons.volume_off : Icons.volume_up,
                size: 14,
                color: layer.muted ? FluxForgeTheme.accentRed : FluxForgeTheme.textTertiary,
              ),
              onPressed: () {
                context.read<MiddlewareProvider>().toggleLayerMute(event.id, layer.id);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              tooltip: layer.muted ? 'Unmute' : 'Mute',
            ),
            IconButton(
              icon: Icon(
                Icons.headphones,
                size: 14,
                color: layer.solo ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
              ),
              onPressed: () {
                context.read<MiddlewareProvider>().toggleLayerSolo(event.id, layer.id);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              tooltip: layer.solo ? 'Unsolo' : 'Solo',
            ),
          ],
        ),
      ),
    );
  }

  /// Time ruler for middleware timeline
  Widget _buildMiddlewareTimeRuler(double duration, double totalWidth) {
    return Container(
      height: _kMiddlewareRulerHeight,
      color: FluxForgeTheme.bgElevated,
      child: SingleChildScrollView(
        controller: _middlewareTimelineScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth + 100,
          child: CustomPaint(
            painter: _MiddlewareTimeRulerPainter(
              duration: duration,
              zoom: _middlewareTimelineZoom,
              pixelsPerSecond: _kMiddlewarePixelsPerSecond,
            ),
          ),
        ),
      ),
    );
  }

  /// Layer region on timeline (audio clip visualization)
  Widget _buildLayerRegion(SlotEventLayer layer, int index, bool isSelected, double totalWidth, double totalDuration) {
    final layerColor = FluxForgeTheme.accentBlue;
    final offsetSeconds = layer.offsetMs / 1000.0;
    final durationSecs = layer.durationSeconds ?? 1.0;
    final startX = offsetSeconds * _kMiddlewarePixelsPerSecond * _middlewareTimelineZoom;
    final regionWidth = durationSecs * _kMiddlewarePixelsPerSecond * _middlewareTimelineZoom;
    final topY = index * _kMiddlewareTrackHeight + 4;

    return Positioned(
      left: startX,
      top: topY,
      child: GestureDetector(
        onTap: () => _selectLayerAndSync(index),
        onHorizontalDragUpdate: (details) {
          // Drag to change offset - TODO: implement via provider
        },
        child: Container(
          width: regionWidth.clamp(40.0, totalWidth),
          height: _kMiddlewareTrackHeight - 8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                layerColor.withValues(alpha: isSelected ? 0.9 : 0.7),
                layerColor.withValues(alpha: isSelected ? 0.6 : 0.4),
              ],
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? Colors.white : layerColor,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: layerColor.withValues(alpha: 0.5), blurRadius: 8)]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            children: [
              // Audio waveform placeholder
              Container(
                width: 16,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Icon(Icons.graphic_eq, size: 12, color: Colors.white70),
              ),
              const SizedBox(width: 6),
              // Layer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      layer.name,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${durationSecs.toStringAsFixed(2)}s',
                      style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              // Volume indicator
              if (layer.volume != 1.0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '${(layer.volume * 100).toInt()}%',
                    style: const TextStyle(fontSize: 7, color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get color for action type
  Color _getActionTypeColor(ActionType type) {
    return switch (type) {
      ActionType.play => FluxForgeTheme.accentGreen,
      ActionType.playAndContinue => const Color(0xFF66FF99),
      ActionType.stop => FluxForgeTheme.accentRed,
      ActionType.stopAll => const Color(0xFFFF6666),
      ActionType.pause => FluxForgeTheme.accentOrange,
      ActionType.pauseAll => const Color(0xFFFFAA66),
      ActionType.resume => FluxForgeTheme.accentBlue,
      ActionType.resumeAll => const Color(0xFF66AAFF),
      ActionType.break_ => const Color(0xFFFFFF66),
      ActionType.mute => const Color(0xFF888888),
      ActionType.unmute => const Color(0xFFAAAAAA),
      ActionType.setVolume => FluxForgeTheme.accentCyan,
      ActionType.setPitch => const Color(0xFFE040FB),
      ActionType.setLPF => const Color(0xFFFF8866),
      ActionType.setHPF => const Color(0xFF66FF88),
      ActionType.setBusVolume => const Color(0xFF40C8FF),
      ActionType.setState => const Color(0xFF9C27B0),
      ActionType.setSwitch => const Color(0xFF00BCD4),
      ActionType.setRTPC => const Color(0xFFFFD700),
      ActionType.resetRTPC => const Color(0xFFCCAA00),
      ActionType.seek => const Color(0xFFFF66FF),
      ActionType.trigger => FluxForgeTheme.accentOrange,
      ActionType.postEvent => const Color(0xFF66FFFF),
    };
  }

  /// Update action delay (from drag)
  void _updateActionDelay(int index, double newDelay) {
    final provider = context.read<MiddlewareProvider>();
    final event = _selectedEvent;
    if (event == null || index >= event.actions.length) return;

    final updatedActions = List<MiddlewareAction>.from(event.actions);
    updatedActions[index] = updatedActions[index].copyWith(delay: newDelay);

    provider.updateEvent(event.copyWith(actions: updatedActions));
  }


  /// Update layer in composite event
  /// Also syncs header if this is the currently selected layer
  void _updateLayer(SlotCompositeEvent event, int layerIndex, SlotEventLayer updatedLayer, MiddlewareProvider provider) {
    final updatedLayers = event.layers.asMap().entries.map((e) {
      return e.key == layerIndex ? updatedLayer : e.value;
    }).toList();
    provider.updateCompositeEvent(event.copyWith(layers: updatedLayers));
    // Sync header if user changed the currently selected layer via table
    if (layerIndex == _selectedLayerIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncHeaderFromSelectedLayer();
      });
    }
    // Also auto-select this layer for header/inspector sync
    if (_selectedLayerIndex != layerIndex) {
      setState(() => _selectedLayerIndex = layerIndex);
    }
  }

  /// Build layers table styled as original Actions table
  /// Uses SlotCompositeEvent.layers as data source but displays with original UI style
  Widget _buildLayersAsActionsTable(double availableWidth, SlotCompositeEvent? event, MiddlewareProvider provider) {
    if (event == null) {
      return Container(
        width: availableWidth - 24,
        height: 200,
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Center(
          child: Text('No event selected', style: TextStyle(color: FluxForgeTheme.textSecondary)),
        ),
      );
    }

    final poolSounds = _audioPool.map((f) => f.name).toList();
    final assetOptions = ['', ...poolSounds];

    return Container(
      width: availableWidth - 24,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table header — single row layout
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: const SizedBox.shrink(),
          ),
          // Add layer button row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _showAddLayerToCompositeDialog(event),
                  icon: Icon(Icons.add, size: 14, color: event.color),
                  label: Text('Add', style: TextStyle(fontSize: 11, color: event.color)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${event.layers.length} layers', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
              ],
            ),
          ),
          // Table rows - from SlotCompositeEvent.layers
          if (event.layers.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No layers. Click "Add" to create one.', style: TextStyle(color: FluxForgeTheme.textTertiary)),
              ),
            )
          else
            ...event.layers.asMap().entries.map((entry) {
              final idx = entry.key;
              final layer = entry.value;
              final isSelected = idx == _selectedLayerIndex;

              final assetName = layer.audioPath.isEmpty ? '' : layer.audioPath.split('/').last;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedLayerIndex = idx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _syncHeaderFromSelectedLayer();
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? FluxForgeTheme.accentBlue.withValues(alpha: 0.10) : Colors.transparent,
                    border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Index
                        SizedBox(width: 18, child: Center(child: Text('${idx + 1}', style: TextStyle(fontSize: 11, color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary, fontWeight: FontWeight.w700)))),
                        // Type dropdown with label — fixed width
                        SizedBox(width: 72, child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Type', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600, height: 1)),
                          const SizedBox(height: 2),
                          _CellDropdown(value: layer.actionType, options: kActionTypes, color: _getTypeColor(layer.actionType), onChanged: (val) => _updateLayer(event, idx, layer.copyWith(actionType: val), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); }),
                        ])),
                        const SizedBox(width: 3),
                        // Bus dropdown with label — fixed width
                        SizedBox(width: 68, child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Bus', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600, height: 1)),
                          const SizedBox(height: 2),
                          _CellDropdown(value: _busIdToName(layer.busId), options: const ['Master', 'Music', 'SFX', 'Voice', 'UI', 'Ambience'], color: FluxForgeTheme.accentCyan, onChanged: (val) => _updateLayer(event, idx, layer.copyWith(busId: _busNameToId(val)), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); }),
                        ])),
                        const SizedBox(width: 3),
                        // Asset dropdown with label — fixed width
                        SizedBox(width: 120, child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Asset', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600, height: 1)),
                          const SizedBox(height: 2),
                          _CellDropdown(value: assetName, options: assetOptions, color: FluxForgeTheme.accentCyan, onChanged: (val) {
                            final path = val.isEmpty ? '' : _audioPool.firstWhere((f) => f.name == val, orElse: () => _audioPool.first).path;
                            _updateLayer(event, idx, layer.copyWith(audioPath: path), provider);
                          }, onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); }),
                        ])),
                        const SizedBox(width: 4),
                        // All param boxes — expand to fill available space
                        Expanded(flex: 5, child: Builder(builder: (context) {
                          final durMs = (layer.durationSeconds ?? 60.0) * 1000.0;
                          return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _ParamBox(label: 'Vol', value: layer.volume, min: 0, max: 1, color: FluxForgeTheme.accentGreen, format: (v) => v >= 1.0 ? '1' : v.toStringAsFixed(2), onChanged: (v) => _updateLayer(event, idx, layer.copyWith(volume: v), provider), defaultValue: 1.0, onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); })),
                            const SizedBox(width: 2),
                            Expanded(child: _ParamBox(label: 'Pan', value: layer.pan, min: -1, max: 1, color: FluxForgeTheme.accentCyan, format: (v) => v.abs() < 0.01 ? 'C' : (v < 0 ? 'L${(-v * 100).toInt()}' : 'R${(v * 100).toInt()}'), onChanged: (v) => _updateLayer(event, idx, layer.copyWith(pan: v), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); })),
                            const SizedBox(width: 2),
                            Expanded(child: _ParamBox(label: 'Dly', value: layer.offsetMs, min: 0, max: durMs, color: FluxForgeTheme.accentOrange, format: (v) => '${v.toInt()}', onChanged: (v) => _updateLayer(event, idx, layer.copyWith(offsetMs: v), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); })),
                            const SizedBox(width: 2),
                            Expanded(child: _ParamBox(label: 'FdIn', value: layer.fadeInMs, min: 0, max: durMs, color: const Color(0xFF845EF7), format: (v) => '${v.toInt()}', onChanged: (v) => _updateLayer(event, idx, layer.copyWith(fadeInMs: v), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); })),
                            const SizedBox(width: 2),
                            Expanded(child: _ParamBox(label: 'FdOut', value: layer.fadeOutMs, min: 0, max: durMs, color: const Color(0xFF845EF7), format: (v) => '${v.toInt()}', onChanged: (v) => _updateLayer(event, idx, layer.copyWith(fadeOutMs: v), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); })),
                            const SizedBox(width: 2),
                            Expanded(child: _ParamBox(label: 'TrS', value: layer.trimStartMs, min: 0, max: durMs, color: FluxForgeTheme.accentBlue, format: (v) => '${v.toInt()}', onChanged: (v) => _updateLayer(event, idx, layer.copyWith(trimStartMs: v), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); })),
                            const SizedBox(width: 2),
                            Expanded(child: _ParamBox(label: 'TrE', value: layer.trimEndMs, min: 0, max: durMs, color: FluxForgeTheme.accentBlue, format: (v) => '${v.toInt()}', onChanged: (v) => _updateLayer(event, idx, layer.copyWith(trimEndMs: v), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); })),
                          ],
                        ); })),
                        const SizedBox(width: 4),
                        // M/S/L — aligned with param boxes (label spacer + 2px + control)
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 11), // match label height (9px text + 2px gap)
                          _LayerToggle(label: 'M', value: layer.muted, activeColor: FluxForgeTheme.accentRed, onTap: () => _updateLayer(event, idx, layer.copyWith(muted: !layer.muted), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); }),
                        ]),
                        const SizedBox(width: 2),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 11),
                          _LayerToggle(label: 'S', value: layer.solo, activeColor: FluxForgeTheme.accentOrange, onTap: () => _updateLayer(event, idx, layer.copyWith(solo: !layer.solo), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); }),
                        ]),
                        const SizedBox(width: 2),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 11),
                          _LayerToggle(label: 'L', value: layer.loop, activeColor: FluxForgeTheme.accentGreen, onTap: () => _updateLayer(event, idx, layer.copyWith(loop: !layer.loop), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); }),
                        ]),
                        const SizedBox(width: 2),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 11),
                          _LayerToggle(label: 'O', value: layer.overlap, activeColor: FluxForgeTheme.accentCyan, onTap: () => _updateLayer(event, idx, layer.copyWith(overlap: !layer.overlap), provider), onInteract: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); }),
                        ]),
                        const SizedBox(width: 4),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 11),
                          GestureDetector(onTap: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); _duplicateLayer(event, idx); }, child: const Icon(Icons.copy, size: 13, color: FluxForgeTheme.textTertiary)),
                        ]),
                        const SizedBox(width: 3),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 11),
                          GestureDetector(onTap: () { setState(() => _selectedLayerIndex = idx); _syncHeaderFromSelectedLayer(); _deleteLayer(event, idx); }, child: const Icon(Icons.delete_outline, size: 13, color: FluxForgeTheme.textTertiary)),
                        ]),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }


  Color _getTypeColor(String type) {
    switch (type) {
      case 'Play':
      case 'PlayAndContinue':
        return FluxForgeTheme.accentGreen;
      case 'Stop':
      case 'StopAll':
      case 'Break':
        return FluxForgeTheme.errorRed;
      case 'Pause':
      case 'PauseAll':
        return FluxForgeTheme.accentOrange;
      case 'Resume':
      case 'ResumeAll':
        return FluxForgeTheme.accentCyan;
      case 'SetVolume':
      case 'SetBusVolume':
      case 'SetPitch':
        return FluxForgeTheme.accentBlue;
      case 'SetState':
      case 'SetSwitch':
      case 'SetRTPC':
        return const Color(0xFF845EF7); // Purple
      case 'Mute':
      case 'Unmute':
        return FluxForgeTheme.textSecondary;
      default:
        return FluxForgeTheme.textPrimary;
    }
  }


  /// Get selected clip from timeline
  timeline.TimelineClip? get _selectedClip {
    return _clips.cast<timeline.TimelineClip?>().firstWhere(
      (c) => c?.selected == true,
      orElse: () => null,
    );
  }

  /// Build clip editor content connected to selected timeline clip
  Widget _buildClipEditorContent() {
    final clip = _selectedClip;
    final engine = context.read<EngineProvider>();
    final transport = engine.transport;

    return clip_editor.ConnectedClipEditor(
      selectedClipId: clip?.id,
      clipName: clip?.name,
      clipDuration: clip?.duration,
      clipWaveform: clip?.waveform,
      fadeIn: clip?.fadeIn ?? 0,
      fadeOut: clip?.fadeOut ?? 0,
      fadeInCurve: clip?.fadeInCurve ?? FadeCurve.linear,
      fadeOutCurve: clip?.fadeOutCurve ?? FadeCurve.linear,
      gain: clip?.gain ?? 0,
      clipColor: clip?.color,
      sourceOffset: clip?.sourceOffset ?? 0,
      sourceDuration: clip?.sourceDuration,
      playheadPosition: transport.positionSeconds - (clip?.startTime ?? 0),
      snapEnabled: _snapEnabled,
      snapValue: _snapValue,
      onFadeInChange: (clipId, fadeIn) {
        // Notify engine
        final currentClip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
        EngineApi.instance.fadeInClip(clipId, fadeIn, curveType: _curveToInt(currentClip.fadeInCurve));
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(fadeIn: fadeIn);
            }
            return c;
          }).toList();
        });
      },
      onFadeOutChange: (clipId, fadeOut) {
        // Notify engine
        final currentClip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
        EngineApi.instance.fadeOutClip(clipId, fadeOut, curveType: _curveToInt(currentClip.fadeOutCurve));
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(fadeOut: fadeOut);
            }
            return c;
          }).toList();
        });
      },
      onFadeInCurveChange: (clipId, curve) {
        // Notify engine with updated curve
        final currentClip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
        EngineApi.instance.fadeInClip(clipId, currentClip.fadeIn, curveType: _curveToInt(curve));
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(fadeInCurve: curve);
            }
            return c;
          }).toList();
        });
      },
      onFadeOutCurveChange: (clipId, curve) {
        // Notify engine with updated curve
        final currentClip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
        EngineApi.instance.fadeOutClip(clipId, currentClip.fadeOut, curveType: _curveToInt(curve));
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(fadeOutCurve: curve);
            }
            return c;
          }).toList();
        });
      },
      onGainChange: (clipId, gain) {
        // Notify engine
        EngineApi.instance.setClipGain(clipId, gain);
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(gain: gain);
            }
            return c;
          }).toList();
        });
      },
      onNormalize: (clipId) {
        // Call Rust normalize function via FFI
        engine.normalizeClip(clipId, targetDb: -3.0);
      },
      onReverse: (clipId) {
        // Call Rust reverse function via FFI
        engine.reverseClip(clipId);
      },
      // Audition - play clip preview
      isAuditioning: _isAuditioning,
      onAudition: (clipId, startTime, endTime) {
        // Move playhead to start position and play
        final clip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
        engine.seek(clip.startTime + startTime);
        engine.play();
        setState(() => _isAuditioning = true);
      },
      onStopAudition: () {
        engine.pause();
        setState(() => _isAuditioning = false);
      },
      onTrimToSelection: (clipId, selection) {
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(
                sourceOffset: c.sourceOffset + selection.start,
                duration: selection.length,
              );
            }
            return c;
          }).toList();
        });
      },
      onSplitAtPosition: (clipId, position) {
        final clip = _clips.firstWhere((c) => c.id == clipId);
        if (position <= 0 || position >= clip.duration) return;

        final leftDuration = position;
        final rightDuration = clip.duration - position;
        final rightOffset = clip.sourceOffset + position;

        setState(() {
          _clips = _clips.where((c) => c.id != clipId).toList();
          _clips.add(clip.copyWith(duration: leftDuration, selected: false));
          _clips.add(timeline.TimelineClip(
            id: '${clipId}_split',
            trackId: clip.trackId,
            name: '${clip.name} (2)',
            startTime: clip.startTime + leftDuration,
            duration: rightDuration,
            sourceOffset: rightOffset,
            sourceDuration: clip.sourceDuration,
            color: clip.color,
            waveform: clip.waveform,
            selected: true,
            eventId: clip.eventId, // Preserve original event
          ));
        });
      },
      onSlipEdit: (clipId, newSourceOffset) {
        // Slip edit: move source content within clip bounds
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(sourceOffset: newSourceOffset);
            }
            return c;
          }).toList();
        });
      },
      onPlayheadChange: (localPosition) {
        final clip = _selectedClip;
        if (clip != null) {
          engine.seek(clip.startTime + localPosition);
        }
      },
      // Hitpoint callbacks (Cubase-style sample editor)
      hitpoints: _clipHitpoints,
      showHitpoints: _showClipHitpoints,
      hitpointSensitivity: _clipHitpointSensitivity,
      hitpointAlgorithm: _clipHitpointAlgorithm,
      onShowHitpointsChange: (show) {
        setState(() => _showClipHitpoints = show);
      },
      onHitpointSensitivityChange: (sensitivity) {
        setState(() => _clipHitpointSensitivity = sensitivity);
      },
      onHitpointAlgorithmChange: (algorithm) {
        setState(() => _clipHitpointAlgorithm = algorithm);
      },
      onDetectHitpoints: () {
        _detectClipHitpoints();
      },
      onHitpointsChange: (hitpoints) {
        setState(() => _clipHitpoints = hitpoints);
      },
      onDeleteHitpoint: (index) {
        if (index >= 0 && index < _clipHitpoints.length) {
          setState(() {
            _clipHitpoints = List.from(_clipHitpoints)..removeAt(index);
          });
        }
      },
      onMoveHitpoint: (index, newPosition) {
        if (index >= 0 && index < _clipHitpoints.length) {
          setState(() {
            final hp = _clipHitpoints[index];
            _clipHitpoints = List.from(_clipHitpoints)
              ..[index] = hp.copyWith(position: newPosition);
          });
        }
      },
      onAddHitpoint: (samplePosition) {
        setState(() {
          _clipHitpoints = List.from(_clipHitpoints)
            ..add(clip_editor.Hitpoint(
              position: samplePosition,
              strength: 1.0,
              isManual: true,
            ))
            ..sort((a, b) => a.position.compareTo(b.position));
        });
      },
      onSliceAtHitpoints: (clipId, hitpoints) {
        _sliceClipAtHitpoints(clipId, hitpoints);
      },
    );
  }

  /// Detect hitpoints in selected clip using Rust engine
  void _detectClipHitpoints() {
    final clip = _selectedClip;
    if (clip == null) return;

    // Parse clip ID to get the numeric clip ID for FFI
    final clipIdNumeric = int.tryParse(clip.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (clipIdNumeric == 0) {
      return;
    }

    // Call FFI to detect transients
    final ffi = NativeFFI.instance;
    final results = ffi.detectClipTransients(
      clipIdNumeric,
      sensitivity: _clipHitpointSensitivity,
      algorithm: _clipHitpointAlgorithm.index,
      minGapMs: 20.0,
    );

    // Convert to Hitpoint objects
    setState(() {
      _clipHitpoints = results
          .map((r) => clip_editor.Hitpoint(
                position: r.position,
                strength: r.strength,
                isManual: false,
              ))
          .toList();
      _showClipHitpoints = true;
    });
  }

  /// Slice clip at hitpoint positions (creates multiple clips)
  void _sliceClipAtHitpoints(String clipId, List<clip_editor.Hitpoint> hitpoints) {
    if (hitpoints.isEmpty) return;

    final clip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
    final sampleRate = 48000; // TODO: get from clip

    // Sort hitpoints by position
    final sortedHitpoints = List<clip_editor.Hitpoint>.from(hitpoints)
      ..sort((a, b) => a.position.compareTo(b.position));

    // Create slices
    final newClips = <timeline.TimelineClip>[];
    double prevTime = 0;

    for (int i = 0; i < sortedHitpoints.length; i++) {
      final hp = sortedHitpoints[i];
      final sliceTime = hp.position / sampleRate;

      if (sliceTime > prevTime && sliceTime < clip.duration) {
        newClips.add(timeline.TimelineClip(
          id: '${clipId}_slice_$i',
          trackId: clip.trackId,
          name: '${clip.name} (${i + 1})',
          startTime: clip.startTime + prevTime,
          duration: sliceTime - prevTime,
          sourceOffset: clip.sourceOffset + prevTime,
          sourceDuration: clip.sourceDuration,
          color: clip.color,
          waveform: clip.waveform,
          eventId: clip.eventId, // Preserve original event
        ));
        prevTime = sliceTime;
      }
    }

    // Add final slice
    if (prevTime < clip.duration) {
      newClips.add(timeline.TimelineClip(
        id: '${clipId}_slice_${sortedHitpoints.length}',
        trackId: clip.trackId,
        name: '${clip.name} (${sortedHitpoints.length + 1})',
        startTime: clip.startTime + prevTime,
        duration: clip.duration - prevTime,
        sourceOffset: clip.sourceOffset + prevTime,
        sourceDuration: clip.sourceDuration,
        color: clip.color,
        waveform: clip.waveform,
        eventId: clip.eventId, // Preserve original event
      ));
    }

    setState(() {
      _clips = _clips.where((c) => c.id != clipId).toList()..addAll(newClips);
      _clipHitpoints = []; // Clear hitpoints after slicing
    });
  }

  /// Build Crossfade Editor content
  Widget _buildCrossfadeEditorContent() {
    // Find any selected crossfade between clips
    // For now, show a placeholder with default config
    return CrossfadeEditor(
      initialConfig: const CrossfadeConfig(
        fadeOut: FadeCurveConfig(
          preset: CrossfadePreset.equalPower,
        ),
        fadeIn: FadeCurveConfig(
          preset: CrossfadePreset.equalPower,
        ),
        duration: 1.0,
        centerOffset: 0.0,
        linked: true,
      ),
      onConfigChanged: (config) {
        // Live preview - apply crossfade changes in real-time
      },
      onApply: () {
        // Apply crossfade
      },
      onCancel: () {
        // Cancel crossfade edit
      },
      onAudition: () {
        // Audition crossfade
      },
    );
  }

  /// Build Automation Editor content
  Widget _buildAutomationEditorContent() {
    // Demo automation data
    final automationData = AutomationLaneData(
      id: 'vol',
      parameter: AutomationParameter.volume,
      parameterName: 'Volume',
      color: const Color(0xFF4A9EFF),
      mode: AutomationMode.read,
      points: [
        const AutomationPoint(id: '1', time: 0, value: 0.75),
        const AutomationPoint(id: '2', time: 2.0, value: 0.9),
        const AutomationPoint(id: '3', time: 4.0, value: 0.5),
        const AutomationPoint(id: '4', time: 8.0, value: 0.75),
      ],
      minValue: 0.0,
      maxValue: 1.0,
    );

    // Get sample rate for time-to-samples conversion
    final sampleRate = NativeFFI.instance.getSampleRate();

    return LayoutBuilder(
      builder: (context, constraints) {
        return AutomationLane(
          data: automationData,
          zoom: _timelineZoom,
          scrollOffset: _timelineScrollOffset,
          width: constraints.maxWidth,
          onDataChanged: (data) {
            // Sync automation changes to engine
            // Convert parameter type to string
            final paramName = data.parameter.name;

            // Clear existing lane and add all points
            NativeFFI.instance.automationClearLane(1, paramName); // Track 1 for demo

            for (final point in data.points) {
              final timeSamples = (point.time * sampleRate).round();
              final curveType = _curveTypeToInt(point.curveType);
              NativeFFI.instance.automationAddPoint(1, paramName, timeSamples, point.value, curveType: curveType);
            }
          },
        );
      },
    );
  }

  /// Convert UI curve type to FFI curve type
  int _curveTypeToInt(AutomationCurveType type) {
    switch (type) {
      case AutomationCurveType.linear: return 0;
      case AutomationCurveType.bezier: return 1;
      case AutomationCurveType.step: return 4;
      case AutomationCurveType.scurve: return 5;
    }
  }

  /// Check if busId is an OUTPUT BUS (not an audio track)
  /// Output buses: master, sfx, music, voice, amb, ui
  /// Audio tracks: ch_xxx (use track InsertChain)
  bool _isBusChannel(String busId) {
    return busId == 'master' || busId == 'sfx' || busId == 'music' ||
           busId == 'voice' || busId == 'amb' || busId == 'ui';
  }

  /// Get bus ID for Bus InsertChain FFI
  /// 0=Master routing, 1=Music, 2=Sfx, 3=Voice, 4=Amb, 5=Aux/UI
  int _getBusId(String busId) {
    switch (busId) {
      case 'master': return 0;
      case 'music': return 1;
      case 'sfx': return 2;
      case 'voice': return 3;
      case 'amb': return 4;
      case 'ui': return 5;
      default: return 0;
    }
  }

  /// Convert bus/channel ID to numeric track ID for FFI
  /// Uses MixerProvider to get actual engine track ID for audio channels
  /// NOTE: For OUTPUT BUSES (master, sfx, music, voice, amb, ui) use busInsertXxx functions!
  int _busIdToTrackId(String busId) {
    // NOTE: For buses, use _getBusId() with busInsertXxx FFI functions
    // This function is for AUDIO TRACKS only now
    switch (busId) {
      case 'master': return 0; // Master uses master_insert, not bus_inserts
      case 'sfx':
      case 'music':
      case 'voice':
      case 'amb':
      case 'ui':
        // WARNING: Buses should use busInsertXxx functions, not insertXxx
        // Return bus ID for backwards compatibility but log warning
        return _getBusId(busId);
      default:
        // For audio channels (ch_xxx), get trackIndex from MixerProvider
        // This is the actual engine track ID from createTrack() FFI call
        final mixerProv = context.read<MixerProvider>();
        final channel = mixerProv.getChannel(busId);
        if (channel != null && channel.trackIndex != null) {
          return channel.trackIndex!;
        }
        // Fallback: try to parse numeric ID
        if (busId.startsWith('ch_')) {
          return int.tryParse(busId.substring(3)) ?? 0;
        }
        return int.tryParse(busId) ?? 0;
    }
  }

  /// Convert bus ID to routing channel ID for FFI
  int _busIdToChannelId(String busId) {
    // Routing channels use same mapping as tracks for now
    // Master=0, SFX=1, Music=2, Voice=3, Amb=4, UI=5
    return _busIdToTrackId(busId);
  }

  /// Get ChannelStripData for selected track (used by Channel tab in LeftZone)
  ChannelStripData? _getSelectedChannelData() {
    if (_selectedTrackId == null) return null;

    // Master bus — special handling (not in _tracks list)
    if (_selectedTrackId == '0' || _selectedTrackId == 'master') {
      return _getMasterChannelData();
    }

    // Find track in timeline
    final track = _tracks.cast<timeline.TimelineTrack?>().firstWhere(
      (t) => t?.id == _selectedTrackId,
      orElse: () => null,
    );
    if (track == null) return null;

    // Get mixer channel data - use watch to rebuild when pan changes
    final mixerProvider = context.watch<MixerProvider>();
    final channelId = 'ch_${track.id}';
    final channel = mixerProvider.getChannel(channelId);

    // Get insert chain
    if (!_busInserts.containsKey(channelId)) {
      _busInserts[channelId] = InsertChain(channelId: channelId);
    }
    final insertChain = _busInserts[channelId]!;

    // Convert volume from linear (0-1.5) to dB
    // Formula: dB = 20 * log10(linear), where linear=1.0 -> 0dB
    final volumeLinear = channel?.volume ?? 1.0;
    double volumeDb;
    if (volumeLinear <= 0.001) {
      volumeDb = -70.0; // Effectively -infinity
    } else {
      volumeDb = 20.0 * (volumeLinear > 0 ? (volumeLinear).clamp(0.001, 4.0) : 0.001);
      // Proper log conversion: 20 * log10(linear)
      volumeDb = 20.0 * _log10(volumeLinear.clamp(0.001, 4.0));
    }
    volumeDb = volumeDb.clamp(-70.0, 12.0);

    // Build sends list from mixer channel
    final sends = <SendSlot>[];
    if (channel != null) {
      for (int i = 0; i < 4; i++) {
        if (i < channel.sends.length) {
          final send = channel.sends[i];
          sends.add(SendSlot(
            id: '${channelId}_send_$i',
            destination: send.auxId, // auxId is the destination
            level: send.level,
            preFader: send.preFader,
            enabled: send.enabled,
          ));
        } else {
          sends.add(SendSlot(id: '${channelId}_send_$i'));
        }
      }
    } else {
      // Empty sends
      for (int i = 0; i < 4; i++) {
        sends.add(SendSlot(id: '${channelId}_send_$i'));
      }
    }

    return ChannelStripData(
      id: channelId,
      name: track.name,
      type: 'audio',
      color: track.color,
      volume: volumeDb,
      pan: channel?.pan ?? -1.0, // Pro Tools: L defaults to hard left
      panRight: channel?.panRight ?? 1.0, // Pro Tools: R defaults to hard right
      // Stereo tracks get dual pan knobs (Pro Tools style), mono gets single pan
      isStereo: track.isStereo,
      mute: channel?.muted ?? false,
      solo: channel?.soloed ?? false,
      armed: channel?.armed ?? false,
      inputMonitor: channel?.monitorInput ?? false,
      phaseInverted: channel?.phaseInverted ?? false,
      meterL: channel?.rmsL ?? 0.0,
      meterR: channel?.rmsR ?? 0.0,
      peakL: channel?.peakL ?? 0.0,
      peakR: channel?.peakR ?? 0.0,
      inserts: insertChain.slots.map((slot) => InsertSlot(
        id: '${channelId}_${slot.index}',
        name: slot.plugin?.displayName ?? '',
        type: slot.plugin?.category.name ?? 'empty',
        bypassed: slot.bypassed,
        isPreFader: slot.isPreFader,
      )).toList(),
      sends: sends,
      eqEnabled: _openEqWindows.containsKey(channelId),
      eqBands: const [],
      input: channel?.inputSource ?? 'Stereo In',
      output: track.outputBus.name.substring(0, 1).toUpperCase() + track.outputBus.name.substring(1),
    );
  }

  /// Build ChannelStripData for the master bus.
  /// Master is not in the _tracks list — uses MixerProvider.master directly.
  ChannelStripData _getMasterChannelData() {
    final mixerProvider = context.watch<MixerProvider>();
    final master = mixerProvider.master;
    const channelId = 'master';

    // Get or create insert chain for master
    if (!_busInserts.containsKey(channelId)) {
      _busInserts[channelId] = InsertChain(channelId: channelId);
    }
    final insertChain = _busInserts[channelId]!;

    // Convert volume from linear (0-1.5) to dB
    final volumeLinear = master.volume;
    double volumeDb;
    if (volumeLinear <= 0.001) {
      volumeDb = -70.0;
    } else {
      volumeDb = 20.0 * _log10(volumeLinear.clamp(0.001, 4.0));
    }
    volumeDb = volumeDb.clamp(-70.0, 12.0);

    return ChannelStripData(
      id: channelId,
      name: master.name, // 'Stereo Out'
      type: 'master',
      color: master.color, // Orange #FF9040
      volume: volumeDb,
      pan: master.pan,
      panRight: master.panRight,
      isStereo: true,
      mute: master.muted,
      solo: false, // Master has no solo
      armed: false, // Master has no record arm
      inputMonitor: false, // Master has no input monitor
      phaseInverted: master.phaseInverted,
      meterL: master.rmsL,
      meterR: master.rmsR,
      peakL: master.peakL,
      peakR: master.peakR,
      inserts: insertChain.slots.map((slot) => InsertSlot(
        id: '${channelId}_${slot.index}',
        name: slot.plugin?.displayName ?? '',
        type: slot.plugin?.category.name ?? 'empty',
        bypassed: slot.bypassed,
        isPreFader: slot.isPreFader,
      )).toList(),
      sends: const [], // Master has no sends
      eqEnabled: _openEqWindows.containsKey(channelId),
      eqBands: const [],
      input: 'Sum', // Master sums all buses
      output: 'Main Out',
    );
  }

  Widget _buildMixerContent(dynamic metering, bool isPlaying) {
    // Convert InsertChain to ProInsertSlot list
    List<ProInsertSlot> _getInserts(String channelId) {
      // Auto-create insert chain for any channel
      if (!_busInserts.containsKey(channelId)) {
        _busInserts[channelId] = InsertChain(channelId: channelId);
      }
      final chain = _busInserts[channelId]!;
      return chain.slots.map((slot) => ProInsertSlot(
        id: '${channelId}_${slot.index}',
        name: slot.plugin?.displayName,
        bypassed: slot.bypassed,
        isPreFader: slot.isPreFader,
      )).toList();
    }

    // Always pass real metering — GpuMeter handles smooth decay internally
    // Use direct FFI for linear amplitude (no dB conversion)
    final (tMeterL, tMeterR) = NativeFFI.instance.getBusPeak(0);
    final meterL = tMeterL;
    final meterR = tMeterR;
    final meterPeak = (tMeterL > tMeterR) ? tMeterL : tMeterR;

    // Get channels from MixerProvider and check which tracks have clips
    final mixerProvider = context.watch<MixerProvider>();
    final channelStrips = mixerProvider.channels.map((ch) {
      // Use native engine track ID (set by createTrack FFI) for metering calls
      final trackId = ch.id.startsWith('ch_') ? ch.id.substring(3) : ch.id;
      final trackIdInt = int.tryParse(trackId) ?? 0;
      final engineTrackId = ch.trackIndex ?? trackIdInt;

      // Get real per-track metering from engine — no fakes, no isPlaying guard
      // GpuMeter handles smooth decay when engine naturally outputs 0
      final (peakL, peakR) = EngineApi.instance.getTrackPeakStereo(engineTrackId);

      return ProMixerStripData(
        id: ch.id,
        name: ch.name,
        trackColor: ch.color,
        type: 'audio',
        volume: ch.volume,
        muted: ch.muted,
        soloed: ch.soloed,
        meters: MeterData.fromLinear(
          peakL: peakL,
          peakR: peakR,
          peakHoldL: 0,
          peakHoldR: 0,
        ),
        inserts: _getInserts(ch.id),
      );
    }).toList();

    // Master strip - always present, real metering only
    final masterStrip = ProMixerStripData(
      id: 'master',
      name: 'Stereo Out',
      trackColor: FluxForgeTheme.warningOrange,
      type: 'master',
      volume: _busVolumes['master'] ?? 1.0,
      muted: _busMuted['master'] ?? false,
      meters: MeterData.fromLinear(
        peakL: meterL,
        peakR: meterR,
        peakHoldL: meterPeak,
        peakHoldR: meterPeak,
      ),
      inserts: _getInserts('master'),
    );

    return Container(
      color: FluxForgeTheme.bgDeepest,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Track channel strips (from timeline tracks)
          ...channelStrips.map((strip) => Padding(
            padding: const EdgeInsets.only(right: 1),
            child: ProMixerStrip(
              data: strip,
              compact: true,
              onVolumeChange: (v) => mixerProvider.setChannelVolumeWithUndo(strip.id, v),
              onPanChange: (p) => mixerProvider.setChannelPanWithUndo(strip.id, p),
              onMuteToggle: () => mixerProvider.toggleChannelMuteWithUndo(strip.id),
              onSoloToggle: () => mixerProvider.toggleChannelSoloWithUndo(strip.id),
              onOutputClick: () => _onOutputClick(strip.id),
              onInsertClick: (idx) => _onInsertClick(strip.id, idx),
              onSlotDestinationChange: (slotIndex, type, targetId) =>
                  _onSlotDestinationChange(strip.id, slotIndex, type, targetId),
            ),
          )),
          // Spacer to push master to right
          const Spacer(),
          // Master strip (always rightmost)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ProMixerStrip(
              data: masterStrip,
              compact: true,
              onVolumeChange: (v) => _onBusVolumeChange('master', v),
              onMuteToggle: () => _onBusMuteToggle('master'),
              onSoloToggle: () => _onBusSoloToggle('master'),
              onInsertClick: (idx) => _onInsertClick('master', idx),
              onSlotDestinationChange: (slotIndex, type, targetId) =>
                  _onSlotDestinationChange('master', slotIndex, type, targetId),
            ),
          ),
        ],
      ),
    );
  }

  /// Build Ultimate Mixer content with all channels and metering
  Widget _buildUltimateMixerContent(dynamic metering, bool isPlaying) {
    // Collect channels from timeline tracks
    final mixerProvider = context.watch<MixerProvider>();
    final channels = <ultimate.UltimateMixerChannel>[];

    for (final ch in mixerProvider.channels) {
      // Use native engine track ID (set by createTrack FFI) for metering calls
      final trackId = ch.id.startsWith('ch_') ? ch.id.substring(3) : ch.id;
      final trackIdInt = int.tryParse(trackId) ?? 0;
      final engineTrackId = ch.trackIndex ?? trackIdInt;

      // Always pass real metering — GpuMeter handles smooth decay internally
      final (peakL, peakR) = EngineApi.instance.getTrackPeakStereo(engineTrackId);
      final (rmsL, rmsR) = EngineApi.instance.getTrackRmsStereo(engineTrackId);
      final correlation = EngineApi.instance.getTrackCorrelation(engineTrackId);

      // Get inserts for this channel
      final channelInserts = _busInserts[ch.id]?.slots ?? [];
      final inserts = channelInserts.map((slot) => ultimate.InsertData(
        index: slot.index,
        pluginName: slot.plugin?.shortName ?? slot.plugin?.name,
        bypassed: slot.bypassed,
        isPreFader: slot.isPreFader,
      )).toList();

      channels.add(ultimate.UltimateMixerChannel(
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
        input: ultimate.InputSection(phaseInvert: ch.phaseInverted),
        inserts: inserts,
        trackIndex: engineTrackId, // Native engine track ID for FFI + PDC
        peakL: peakL,
        peakR: peakR,
        rmsL: rmsL,
        rmsR: rmsR,
        correlation: correlation,
      ));
    }

    // No hardcoded buses - only track channels + master
    // Buses will be created dynamically when needed

    // Master channel inserts
    final masterInsertChain = _busInserts['master']?.slots ?? [];
    final masterInserts = masterInsertChain.map((slot) => ultimate.InsertData(
      index: slot.index,
      pluginName: slot.plugin?.shortName ?? slot.plugin?.name,
      bypassed: slot.bypassed,
      isPreFader: slot.isPreFader,
    )).toList();

    // Master channel — read DIRECT FFI linear amplitude (same as tracks)
    // getBusPeak(0) = master bus, returns linear amplitude 0.0-1.0+
    final (dMasterPeakL, dMasterPeakR) = NativeFFI.instance.getBusPeak(0);
    final (dMasterRmsL, dMasterRmsR) = NativeFFI.instance.getRmsMeters();
    final masterChannel = ultimate.UltimateMixerChannel(
      id: 'master',
      name: 'MASTER',
      type: ultimate.ChannelType.master,
      color: FluxForgeTheme.warningOrange,
      volume: _busVolumes['master'] ?? 1.0,
      pan: 0,
      muted: _busMuted['master'] ?? false,
      soloed: false,
      inserts: masterInserts,
      peakL: dMasterPeakL,
      peakR: dMasterPeakR,
      rmsL: dMasterRmsL,
      rmsR: dMasterRmsR,
      correlation: metering.correlation,
      lufsShort: metering.masterLufsS,
      lufsIntegrated: metering.masterLufsI,
    );

    // All channels are audio tracks (no hardcoded buses)
    return ultimate.UltimateMixer(
      channels: channels,
      buses: const [], // No hardcoded buses
      auxes: const [],
      vcas: const [],
      master: masterChannel,
      compact: true,
      onVolumeChange: (id, vol) {
        if (id == 'master') {
          _onBusVolumeChange(id, vol);
        } else {
          mixerProvider.setChannelVolumeWithUndo(id, vol);
        }
      },
      onPanChange: (id, pan) {
        if (id != 'master') {
          mixerProvider.setChannelPan(id, pan);
        }
      },
      onPanChangeEnd: (id, pan) {
        if (id != 'master') {
          mixerProvider.setChannelPanWithUndo(id, pan);
        }
      },
      onPanRightChange: (id, pan) {
        if (id != 'master') {
          mixerProvider.setChannelPanRightWithUndo(id, pan);
        }
      },
      onMuteToggle: (id) {
        if (id == 'master') {
          _onBusMuteToggle(id);
        } else {
          mixerProvider.toggleChannelMuteWithUndo(id);
        }
      },
      onSoloToggle: (id) {
        if (id == 'master') {
          _onBusSoloToggle(id);
        } else {
          mixerProvider.toggleChannelSoloWithUndo(id);
        }
      },
      onArmToggle: (id) {
        if (id != 'master') {
          mixerProvider.toggleChannelArm(id);
        }
      },
      onChannelSelect: (id) {
        setState(() {
          if (id == 'master') {
            _selectedTrackId = '0';
          } else {
            _selectedTrackId = id;
          }
        });
      },
      onInsertClick: (channelId, insertIndex) {
        _handleUltimateMixerInsertClick(channelId, insertIndex);
      },
      onSendLevelChange: (channelId, sendIndex, level) {
        engine.setSendLevel(channelId, sendIndex, level);
      },
      onSendMuteToggle: (channelId, sendIndex, muted) {
        engine.setSendMuted(channelId, sendIndex, muted);
      },
      onSendPreFaderToggle: (channelId, sendIndex, preFader) {
        engine.setSendPreFader(channelId, sendIndex, preFader);
      },
      onSendDestChange: (channelId, sendIndex, destination) {
        engine.setSendDestinationById(channelId, sendIndex, destination);
      },
      onPhaseToggle: (id) {
        if (id != 'master') {
          mixerProvider.togglePhaseInvert(id);
        }
      },
      // Channel reorder (bidirectional sync with timeline tracks)
      onChannelReorder: (oldIndex, newIndex) {
        mixerProvider.reorderChannel(oldIndex, newIndex);
      },
    );
  }

  /// Build Middleware Mixer - simplified bus masters only (no track channels)
  /// Used in Middleware/Slot modes for game audio mixing
  Widget _buildMiddlewareMixerContent(dynamic metering, bool isPlaying) {
    // Middleware mixer: buses only (Music, SFX, Voice, UI, Ambience, Reels, Wins, VO) + Master
    // No track channels, no recording, just bus mixing

    final List<ultimate.UltimateMixerChannel> buses = [];

    // Define middleware buses with colors
    final middlewareBuses = [
      ('Music', FluxForgeTheme.accentBlue, Icons.music_note),
      ('SFX', FluxForgeTheme.accentGreen, Icons.volume_up),
      ('Voice', FluxForgeTheme.accentPurple, Icons.record_voice_over),
      ('UI', FluxForgeTheme.accentCyan, Icons.touch_app),
      ('Ambience', FluxForgeTheme.textSecondary, Icons.nature),
      ('Reels', FluxForgeTheme.warningOrange, Icons.casino),
      ('Wins', FluxForgeTheme.successGreen, Icons.emoji_events),
      ('VO', FluxForgeTheme.accentPink, Icons.mic),
    ];

    for (final (name, color, _) in middlewareBuses) {
      final busId = name.toLowerCase();

      // Get inserts for this bus
      final busInsertChain = _busInserts[busId]?.slots ?? [];
      final busInserts = busInsertChain.map((slot) => ultimate.InsertData(
        index: slot.index,
        pluginName: slot.plugin?.shortName ?? slot.plugin?.name,
        bypassed: slot.bypassed,
        isPreFader: slot.isPreFader,
      )).toList();

      // Get real per-bus peak metering from engine
      final engineBusIdx = _busIdToEngineBusIndex(busId);
      double busPeakL = 0, busPeakR = 0;
      if (engineBusIdx >= 0) {
        final (pl, pr) = NativeFFI.instance.getBusPeak(engineBusIdx);
        busPeakL = pl;
        busPeakR = pr;
      }

      buses.add(ultimate.UltimateMixerChannel(
        id: busId,
        name: name.toUpperCase(),
        type: ultimate.ChannelType.bus,
        color: color,
        volume: _busVolumes[busId] ?? 1.0,
        pan: _busPan[busId] ?? -1.0, // L channel pan: hard left default
        panRight: _busPanRight[busId] ?? 1.0, // R channel pan: hard right default
        isStereo: true, // True stereo dual pan knobs (L/R) like DAW mixer
        muted: _busMuted[busId] ?? false,
        soloed: _busSoloed[busId] ?? false,
        inserts: busInserts,
        // Real per-bus peak metering from engine (GpuMeter handles smooth decay)
        peakL: busPeakL,
        peakR: busPeakR,
        rmsL: busPeakL * 0.7, // Approximate RMS from peak
        rmsR: busPeakR * 0.7,
        correlation: 1.0,
      ));
    }

    // Master channel inserts
    final masterInsertChain = _busInserts['master']?.slots ?? [];
    final masterInserts = masterInsertChain.map((slot) => ultimate.InsertData(
      index: slot.index,
      pluginName: slot.plugin?.shortName ?? slot.plugin?.name,
      bypassed: slot.bypassed,
      isPreFader: slot.isPreFader,
    )).toList();

    // Master channel — read DIRECT FFI linear amplitude (same as tracks)
    final (mwMasterPeakL, mwMasterPeakR) = NativeFFI.instance.getBusPeak(0);
    final (mwMasterRmsL, mwMasterRmsR) = NativeFFI.instance.getRmsMeters();
    final masterChannel = ultimate.UltimateMixerChannel(
      id: 'master',
      name: 'MASTER',
      type: ultimate.ChannelType.master,
      color: FluxForgeTheme.warningOrange,
      volume: _busVolumes['master'] ?? 1.0,
      pan: 0,
      muted: _busMuted['master'] ?? false,
      soloed: false,
      inserts: masterInserts,
      peakL: mwMasterPeakL,
      peakR: mwMasterPeakR,
      rmsL: mwMasterRmsL,
      rmsR: mwMasterRmsR,
      correlation: metering.correlation,
      lufsShort: metering.masterLufsS,
      lufsIntegrated: metering.masterLufsI,
    );

    // Middleware mixer: buses only (in channels), no aux/VCA
    return ultimate.UltimateMixer(
      channels: const [], // No track channels in middleware
      buses: buses, // All buses shown
      auxes: const [],
      vcas: const [],
      master: masterChannel,
      compact: true,
      onVolumeChange: (id, vol) => _onBusVolumeChange(id, vol),
      onPanChange: (id, pan) => _onBusPanChange(id, pan),
      onPanRightChange: (id, pan) => _onBusPanRightChange(id, pan),
      onMuteToggle: (id) => _onBusMuteToggle(id),
      onSoloToggle: (id) => _onBusSoloToggle(id),
      onInsertClick: (busId, insertIndex) {
        _handleUltimateMixerInsertClick(busId, insertIndex);
      },
      onSendLevelChange: (busId, sendIndex, level) {
      },
      onSendMuteToggle: (busId, sendIndex, muted) {
      },
      onSendPreFaderToggle: (busId, sendIndex, preFader) {
      },
      onSendDestChange: (busId, sendIndex, destination) {
      },
    );
  }

  /// Build Control Room panel content
  Widget _buildControlRoomContent() {
    return const control_room.ControlRoomPanel();
  }

  Widget _buildInputBusContent() {
    return const input_bus.InputBusPanel();
  }

  Widget _buildRecordingContent() {
    return const recording.RecordingPanel();
  }

  Widget _buildRoutingContent() {
    return const routing.RoutingPanel();
  }

  /// Handle insert click from Ultimate Mixer
  void _handleUltimateMixerInsertClick(String channelId, int insertIndex) async {
    // Ensure insert chain exists for this channel
    if (!_busInserts.containsKey(channelId)) {
      _busInserts[channelId] = InsertChain(channelId: channelId);
    }
    final chain = _busInserts[channelId]!;
    if (insertIndex >= chain.slots.length) return;
    final currentSlot = chain.slots[insertIndex];
    final isPreFader = currentSlot.isPreFader;

    // Get friendly channel name
    final mixerProv = context.read<MixerProvider>();
    final channelName = mixerProv.getChannel(channelId)?.name ?? channelId;

    // If slot has plugin, show options menu (same as _onInsertClick)
    if (!currentSlot.isEmpty) {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgElevated,
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgSurface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  child: Row(
                    children: [
                      Icon(currentSlot.plugin!.category.icon, size: 16, color: currentSlot.plugin!.category.color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(currentSlot.plugin!.name, style: FluxForgeTheme.label, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                _InsertMenuOption(icon: Icons.open_in_new, label: 'Open Editor', onTap: () => Navigator.pop(ctx, 'open')),
                _InsertMenuOption(icon: currentSlot.bypassed ? Icons.toggle_on : Icons.toggle_off, label: currentSlot.bypassed ? 'Enable' : 'Bypass', onTap: () => Navigator.pop(ctx, 'bypass')),
                _InsertMenuOption(icon: Icons.swap_horiz, label: 'Replace', onTap: () => Navigator.pop(ctx, 'replace')),
                _InsertMenuOption(icon: Icons.delete_outline, label: 'Remove', color: FluxForgeTheme.errorRed, onTap: () => Navigator.pop(ctx, 'remove')),
              ],
            ),
          ),
        ),
      );

      if (result == 'open') {
        _openProcessorEditor(channelId, insertIndex, currentSlot.plugin!);
      } else if (result == 'bypass') {
        setState(() {
          _busInserts[channelId] = chain.toggleBypass(insertIndex);
        });
        // Sync bypass to engine FFI
        final trackId = _busIdToTrackId(channelId);
        final newBypass = !currentSlot.bypassed;
        NativeFFI.instance.insertSetBypass(trackId, insertIndex, newBypass);
      } else if (result == 'replace') {
        final plugin = await showPluginSelector(context: context, channelName: channelName, slotIndex: insertIndex, isPreFader: isPreFader);
        if (plugin != null) {
          setState(() { _busInserts[channelId] = chain.setPlugin(insertIndex, plugin); });
          // Load new processor into engine audio path
          final trackId = _busIdToTrackId(channelId);
          if (plugin.format == PluginFormat.internal) {
            final processorName = _pluginIdToProcessorName(plugin.id);
            if (processorName != null) {
              NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
            }
          } else {
            NativeFFI.instance.pluginInsertLoad(trackId, plugin.id);
          }
        }
      } else if (result == 'remove') {
        setState(() { _busInserts[channelId] = chain.removePlugin(insertIndex); });
        // Unload processor from engine audio path
        final trackId = _busIdToTrackId(channelId);
        NativeFFI.instance.insertUnloadSlot(trackId, insertIndex);
      }
    } else {
      // Empty slot - show plugin selector
      final plugin = await showPluginSelector(context: context, channelName: channelName, slotIndex: insertIndex, isPreFader: isPreFader);
      if (plugin != null) {
        setState(() { _busInserts[channelId] = chain.setPlugin(insertIndex, plugin); });

        // Ensure insert chain exists and load processor into engine
        final trackId = _busIdToTrackId(channelId);
        NativeFFI.instance.insertCreateChain(trackId);
        if (plugin.format == PluginFormat.internal) {
          final processorName = _pluginIdToProcessorName(plugin.id);
          if (processorName != null) {
            NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
          }
        } else {
          NativeFFI.instance.pluginInsertLoad(trackId, plugin.id);
        }

        // Auto-open processor editor for newly inserted plugin
        _openProcessorEditor(channelId, insertIndex, plugin);
      }
    }
  }

  Color _getBusColor(String busId) {
    switch (busId) {
      case 'sfx': return FluxForgeTheme.accentBlue;
      case 'music': return FluxForgeTheme.accentCyan;
      case 'voice': return FluxForgeTheme.warningOrange;
      case 'amb': return FluxForgeTheme.accentGreen;
      case 'ui': return FluxForgeTheme.accentBlue.withValues(alpha: 0.7);
      default: return FluxForgeTheme.accentBlue;
    }
  }

  /// Build Metering Bridge content with K-System and Goniometer
  Widget _buildMeteringBridgeContent(dynamic metering, bool isPlaying) {
    // Get real metering data — direct FFI, linear amplitude, no isPlaying guard
    // GpuMeter handles smooth decay when engine naturally outputs 0
    final (mbPeakL, mbPeakR) = NativeFFI.instance.getBusPeak(0);
    final (mbRmsL, mbRmsR) = NativeFFI.instance.getRmsMeters();
    // True peak returns dBTP — convert to linear for MeteringBridge widget
    final (mbTpLdB, mbTpRdB) = NativeFFI.instance.getTruePeakMeters();
    final peakL = mbPeakL;
    final peakR = mbPeakR;
    final rmsL = mbRmsL;
    final rmsR = mbRmsR;
    final truePeakL = mbTpLdB <= -60 ? 0.0 : math.pow(10, mbTpLdB / 20).toDouble();
    final truePeakR = mbTpRdB <= -60 ? 0.0 : math.pow(10, mbTpRdB / 20).toDouble();

    return MeteringBridge(
      peakL: peakL,
      peakR: peakR,
      rmsL: rmsL,
      rmsR: rmsR,
      truePeakL: truePeakL,
      truePeakR: truePeakR,
      correlation: metering.correlation,
      balance: (peakL - peakR).clamp(-1.0, 1.0),
      lufsMomentary: metering.lufsMomentary,
      lufsShort: metering.lufsShort,
      lufsIntegrated: metering.lufsIntegrated,
      kSystem: KSystemType.k14,
      showGoniometer: true,
      showLoudnessHistory: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIXER CALLBACKS - Connected to bus state
  // ═══════════════════════════════════════════════════════════════════════════

  // Bus state - maps bus ID to volume/mute/solo
  // Default volume = 1.0 (0dB) for all buses
  final Map<String, double> _busVolumes = {
    'sfx': 1.0, 'music': 1.0, 'voice': 1.0, 'amb': 1.0, 'ui': 1.0, 'master': 1.0
  };
  final Map<String, bool> _busMuted = {};
  final Map<String, bool> _busSoloed = {};
  final Map<String, double> _busPan = {}; // Bus L channel pan: -1.0 (L) to 1.0 (R)
  final Map<String, double> _busPanRight = {}; // Bus R channel pan: -1.0 (L) to 1.0 (R)

  // Insert chains per bus - starts EMPTY (user adds plugins)
  final Map<String, InsertChain> _busInserts = {
    'sfx': InsertChain(channelId: 'sfx'),
    'music': InsertChain(channelId: 'music'),
    'voice': InsertChain(channelId: 'voice'),
    'amb': InsertChain(channelId: 'amb'),
    'ui': InsertChain(channelId: 'ui'),
    'master': InsertChain(
      channelId: 'master',
      slots: List.generate(12, (i) => InsertState(
        index: i,
        isPreFader: i < 8, // 8 pre-fader + 4 post-fader
      )),
    ),
  };

  void _onBusVolumeChange(String busId, double volume) {
    // Cubase-style: 0.0 = -inf, 1.0 = 0dB, 1.5 = +6dB
    // No rounding, no snapping - direct 1:1 mapping from fader
    final clampedVolume = volume.clamp(0.0, 1.5);

    setState(() {
      _busVolumes[busId] = clampedVolume;
    });

    // Send to Rust engine
    _sendBusVolumeToEngine(busId, clampedVolume);
  }

  void _sendBusVolumeToEngine(String busId, double volume) {
    // Convert linear to dB for Rust engine
    // volume: 0.0 = -inf, 1.0 = 0dB, 1.5 = +3.5dB (approx)
    double volumeDb;
    if (volume <= 0.001) {
      volumeDb = -60.0;
    } else {
      // 20 * log10(volume)
      volumeDb = 20 * _log10(volume);
    }

    try {
      if (busId == 'master') {
        // Master uses dedicated mixer_set_master_volume
        engine.mixerSetMasterVolume(volumeDb);
      } else {
        // Other buses use bus index
        final busIndex = _busIdToIndex(busId);
        if (busIndex >= 0) {
          engine.mixerSetBusVolume(busIndex, volumeDb);
        }
      }
    } catch (e) {
      // Engine not ready yet
    }
  }

  /// log10(x) = ln(x) / ln(10)
  double _log10(double x) {
    if (x <= 0) return -60.0;
    return math.log(x) / math.ln10;
  }

  int _busIdToIndex(String busId) {
    const busMap = {
      'music': 0,
      'sfx': 1,
      'dialog': 2,
      'voice': 3,
      'amb': 4,
      'ui': 5,
      'master': 6,
    };
    return busMap[busId] ?? -1;
  }

  /// Map bus string ID to Rust engine bus index for metering
  /// Rust OutputBus: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
  int _busIdToEngineBusIndex(String busId) {
    const busMap = {
      'master': 0,
      'music': 1,
      'sfx': 2,
      'voice': 3,
      'ambience': 4,
      'ui': 5,     // UI → Aux bus
      'reels': 2,  // Reels → Sfx bus
      'wins': 2,   // Wins → Sfx bus
      'vo': 3,     // VO → Voice bus
    };
    return busMap[busId] ?? -1;
  }

  void _onBusMuteToggle(String busId) {
    setState(() {
      _busMuted[busId] = !(_busMuted[busId] ?? false);
    });
    // Send to Rust engine via FFI
    final engineIdx = _busIdToIndex(busId);
    if (engineIdx >= 0) {
      NativeFFI.instance.setBusMute(engineIdx, _busMuted[busId] ?? false);
    }
  }

  void _onBusSoloToggle(String busId) {
    setState(() {
      _busSoloed[busId] = !(_busSoloed[busId] ?? false);
    });
    // Send to Rust engine via FFI
    final engineIdx = _busIdToIndex(busId);
    if (engineIdx >= 0) {
      NativeFFI.instance.setBusSolo(engineIdx, _busSoloed[busId] ?? false);
    }
  }

  void _onBusPanChange(String busId, double pan) {
    // L channel pan (stereo left)
    final clampedPan = pan.clamp(-1.0, 1.0);
    setState(() {
      _busPan[busId] = clampedPan;
    });
    // Send to Rust engine
    _sendBusPanToEngine(busId, clampedPan);
  }

  void _onBusPanRightChange(String busId, double pan) {
    // R channel pan (stereo right)
    final clampedPan = pan.clamp(-1.0, 1.0);
    setState(() {
      _busPanRight[busId] = clampedPan;
    });
    // Send to Rust engine (R channel)
    _sendBusPanRightToEngine(busId, clampedPan);
  }

  void _sendBusPanRightToEngine(String busId, double pan) {
    try {
      final busIndex = _busIdToIndex(busId);
      if (busIndex >= 0) {
        NativeFFI.instance.mixerSetBusPanRight(busIndex, pan);
      }
    } catch (e) {
      // Engine not ready yet
    }
  }

  void _sendBusPanToEngine(String busId, double pan) {
    try {
      final busIndex = _busIdToIndex(busId);
      if (busIndex >= 0) {
        engine.mixerSetBusPan(busIndex, pan);
      }
    } catch (e) {
      // Engine not ready yet
    }
  }

  /// Handle output routing click
  void _onOutputClick(String channelId) async {
    final mixerProvider = context.read<MixerProvider>();

    // Available output destinations
    final outputs = [
      'Master',
      'Bus 1',
      'Bus 2',
      'Bus 3',
      'Bus 4',
      'Out 1-2',
      'Out 3-4',
    ];

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: Text('Output Routing', style: FluxForgeTheme.label),
        content: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: outputs.map((output) => ListTile(
              dense: true,
              title: Text(output, style: TextStyle(fontSize: 12, color: FluxForgeTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, output),
            )).toList(),
          ),
        ),
      ),
    );

    if (result != null) {
      mixerProvider.setChannelOutput(channelId, result);
    }
  }

  /// Handle input routing click
  void _onInputClick(String channelId) async {
    final mixerProvider = context.read<MixerProvider>();

    // Available input sources
    final inputs = [
      'None',
      'Input 1',
      'Input 2',
      'Input 1-2 (Stereo)',
      'Input 3',
      'Input 4',
      'Input 3-4 (Stereo)',
      'Bus 1',
      'Bus 2',
    ];

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: Text('Input Source', style: FluxForgeTheme.label),
        content: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: inputs.map((input) => ListTile(
              dense: true,
              title: Text(input, style: TextStyle(fontSize: 12, color: FluxForgeTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, input),
            )).toList(),
          ),
        ),
      ),
    );

    if (result != null) {
      mixerProvider.setChannelInput(channelId, result);
    }
  }

  /// Handle send slot click - show routing options
  void _onSendClick(String channelId, int sendIndex) async {
    // Available send destinations (FX buses)
    final sends = [
      'None',
      'FX 1 - Reverb',
      'FX 2 - Delay',
      'FX 3 - Chorus',
      'FX 4 - Aux',
    ];

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: Text('Send ${sendIndex + 1} Destination', style: FluxForgeTheme.label),
        content: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: sends.map((send) => ListTile(
              dense: true,
              title: Text(send, style: TextStyle(fontSize: 12, color: FluxForgeTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, send),
            )).toList(),
          ),
        ),
      ),
    );

    if (result != null && result != 'None') {
      // Extract FX bus index from "FX N - Name" format
      final fxIndex = int.tryParse(result.split(' ')[1]) ?? 1;
      final fromChannelId = _busIdToChannelId(channelId);
      final success = routingAddSend(fromChannelId, fxIndex, 0);
      if (success == 1) {
        _showSnackBar('Send $sendIndex → $result');
      } else {
        _showSnackBar('Failed to route send $sendIndex', isError: true);
      }
    } else if (result == 'None') {
      // Remove send via FFI
      final fromChannelId = _busIdToChannelId(channelId);
      final success = routingRemoveSend(fromChannelId, sendIndex);
      if (success == 1) {
        _showSnackBar('Send $sendIndex removed');
      } else {
        _showSnackBar('Failed to remove send $sendIndex', isError: true);
      }
    }
  }

  /// Handle insert slot destination change from popup menu
  void _onSlotDestinationChange(
    String busId,
    int slotIndex,
    SlotDestinationType type,
    String? targetId,
  ) {
    final chain = _busInserts[busId];
    if (chain == null) return;

    if (targetId == null) {
      // Clear slot
      setState(() {
        _busInserts[busId] = chain.removePlugin(slotIndex);
      });
      return;
    }

    switch (type) {
      case SlotDestinationType.insert:
        // Insert plugin - map name to PluginInfo
        final pluginInfo = _getPluginInfoByName(targetId);
        if (pluginInfo != null) {
          setState(() {
            _busInserts[busId] = chain.setPlugin(slotIndex, pluginInfo);
            // Auto-open EQ editor
            if (pluginInfo.category == PluginCategory.eq) {
              _activeLowerTab = 'eq';
            }
          });
        }
        break;

      case SlotDestinationType.aux:
        // Send to FX bus
        final fromChannelId = _busIdToChannelId(busId);
        final toChannelId = int.tryParse(targetId) ?? 0;
        final success = routingAddSend(fromChannelId, toChannelId, 0);
        if (success != 1) {
          _showSnackBar('Failed to route to AUX', isError: true);
        }
        break;

      case SlotDestinationType.bus:
        // Route output to bus
        final fromId = _busIdToChannelId(busId);
        final toId = int.tryParse(targetId) ?? 0;
        routingSetOutput(fromId, 1, toId);  // dest_type=1 (channel)
        break;
    }
  }

  /// Map plugin name to PluginInfo
  PluginInfo? _getPluginInfoByName(String name) {
    final plugins = {
      'RF-EQ 64': PluginInfo(
        id: 'rf-eq-64',
        name: 'RF-EQ 64',
        vendor: 'FluxForge Studio',
        category: PluginCategory.eq,
        format: PluginFormat.internal,
      ),
      'RF-COMP': PluginInfo(
        id: 'rf-comp',
        name: 'RF-COMP',
        vendor: 'FluxForge Studio',
        category: PluginCategory.dynamics,
        format: PluginFormat.internal,
      ),
      'RF-LIMIT': PluginInfo(
        id: 'rf-limit',
        name: 'RF-LIMIT',
        vendor: 'FluxForge Studio',
        category: PluginCategory.dynamics,
        format: PluginFormat.internal,
      ),
      'RF-GATE': PluginInfo(
        id: 'rf-gate',
        name: 'RF-GATE',
        vendor: 'FluxForge Studio',
        category: PluginCategory.dynamics,
        format: PluginFormat.internal,
      ),
      'RF-VERB': PluginInfo(
        id: 'rf-verb',
        name: 'RF-VERB',
        vendor: 'FluxForge Studio',
        category: PluginCategory.reverb,
        format: PluginFormat.internal,
      ),
      'RF-DELAY': PluginInfo(
        id: 'rf-delay',
        name: 'RF-DELAY',
        vendor: 'FluxForge Studio',
        category: PluginCategory.delay,
        format: PluginFormat.internal,
      ),
      'RF-SAT': PluginInfo(
        id: 'rf-sat',
        name: 'RF-SAT',
        vendor: 'FluxForge Studio',
        category: PluginCategory.saturation,
        format: PluginFormat.internal,
      ),
    };
    return plugins[name];
  }

  void _onInsertClick(String busId, int insertIndex) async {
    // Get current insert state
    final chain = _busInserts[busId];
    if (chain == null) return;

    final currentSlot = chain.slots[insertIndex];
    final isPreFader = insertIndex < 4;

    // Get friendly bus name
    final busNames = {
      'sfx': 'SFX',
      'music': 'Music',
      'voice': 'Voice',
      'amb': 'Ambient',
      'ui': 'UI',
      'master': 'Master',
    };
    final busName = busNames[busId] ?? busId;

    // If slot has plugin, show options menu
    if (!currentSlot.isEmpty) {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgElevated,
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Plugin name header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgSurface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        currentSlot.plugin!.category.icon,
                        size: 16,
                        color: currentSlot.plugin!.category.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentSlot.plugin!.name,
                          style: FluxForgeTheme.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Options
                _InsertMenuOption(
                  icon: Icons.open_in_new,
                  label: 'Open Editor',
                  onTap: () => Navigator.pop(ctx, 'open'),
                ),
                _InsertMenuOption(
                  icon: currentSlot.bypassed ? Icons.toggle_on : Icons.toggle_off,
                  label: currentSlot.bypassed ? 'Enable' : 'Bypass',
                  onTap: () => Navigator.pop(ctx, 'bypass'),
                ),
                _InsertMenuOption(
                  icon: Icons.swap_horiz,
                  label: 'Replace',
                  onTap: () => Navigator.pop(ctx, 'replace'),
                ),
                _InsertMenuOption(
                  icon: Icons.delete_outline,
                  label: 'Remove',
                  color: FluxForgeTheme.errorRed,
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              ],
            ),
          ),
        ),
      );

      if (result == 'open') {
        // Open processor editor in floating window
        _openProcessorEditor(busId, insertIndex, currentSlot.plugin!);
      } else if (result == 'bypass') {
        // Toggle bypass
        setState(() {
          _busInserts[busId] = chain.toggleBypass(insertIndex);
        });
        // Sync to engine FFI
        final trackId = _busIdToTrackId(busId);
        final newBypass = !currentSlot.bypassed;
        NativeFFI.instance.insertSetBypass(trackId, insertIndex, newBypass);
      } else if (result == 'replace') {
        // Show plugin selector for replacement
        final plugin = await showPluginSelector(
          context: context,
          channelName: busName,
          slotIndex: insertIndex,
          isPreFader: isPreFader,
        );
        if (plugin != null) {
          setState(() {
            _busInserts[busId] = chain.setPlugin(insertIndex, plugin);
          });
          // Load new processor into engine audio path
          final trackId = _busIdToTrackId(busId);
          if (plugin.format == PluginFormat.internal) {
            final processorName = _pluginIdToProcessorName(plugin.id);
            if (processorName != null) {
              NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
            }
          } else {
            NativeFFI.instance.pluginInsertLoad(trackId, plugin.id);
          }
        }
      } else if (result == 'remove') {
        // Remove plugin from UI state
        setState(() {
          _busInserts[busId] = chain.removePlugin(insertIndex);
        });
        // Unload processor from engine audio path
        final trackId = _busIdToTrackId(busId);
        NativeFFI.instance.insertUnloadSlot(trackId, insertIndex);
      }
    } else {
      // Empty slot - show plugin selector
      final plugin = await showPluginSelector(
        context: context,
        channelName: busName,
        slotIndex: insertIndex,
        isPreFader: isPreFader,
      );

      if (plugin != null) {
        setState(() {
          _busInserts[busId] = chain.setPlugin(insertIndex, plugin);
        });

        // Ensure insert chain exists in engine FFI
        final trackId = _busIdToTrackId(busId);
        NativeFFI.instance.insertCreateChain(trackId);

        // Load processor into engine audio path
        if (plugin.format == PluginFormat.internal) {
          final processorName = _pluginIdToProcessorName(plugin.id);
          if (processorName != null) {
            NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
          }
        } else {
          NativeFFI.instance.pluginInsertLoad(trackId, plugin.id);
        }

        // Auto-open processor editor for newly inserted plugin
        _openProcessorEditor(busId, insertIndex, plugin);
      }
    }
  }

  /// Convert a PluginInfo from the insert chain to a DspNodeType for the editor window.
  /// Returns null for external plugins that don't map to internal editor panels.
  DspNodeType? _pluginInfoToDspNodeType(PluginInfo plugin) {
    // Map by plugin ID first (most precise)
    const idMapping = {
      'rf-pro-eq': DspNodeType.eq,
      'rf-ultra-eq': DspNodeType.eq,
      'rf-linear-eq': DspNodeType.eq,
      'rf-pultec': DspNodeType.pultec,
      'rf-api550': DspNodeType.api550,
      'rf-neve1073': DspNodeType.neve1073,
      'rf-compressor': DspNodeType.compressor,
      'rf-limiter': DspNodeType.limiter,
      'rf-gate': DspNodeType.gate,
      'rf-expander': DspNodeType.expander,
      'rf-deesser': DspNodeType.deEsser,
      'rf-reverb': DspNodeType.reverb,
      'rf-delay': DspNodeType.delay,
      'rf-saturation': DspNodeType.saturation,
    };
    final byId = idMapping[plugin.id];
    if (byId != null) return byId;

    // Fallback: map by category for internal plugins
    if (plugin.format == PluginFormat.internal) {
      switch (plugin.category) {
        case PluginCategory.eq: return DspNodeType.eq;
        case PluginCategory.dynamics: return DspNodeType.compressor;
        case PluginCategory.reverb: return DspNodeType.reverb;
        case PluginCategory.delay: return DspNodeType.delay;
        case PluginCategory.saturation: return DspNodeType.saturation;
        default: return null;
      }
    }
    return null;
  }

  /// Open the correct processor editor window for an insert slot.
  /// Uses InternalProcessorEditorWindow for internal plugins (all 9 FabFilter panels + vintage),
  /// falls back to FFI pluginOpenEditor for external VST3/AU/CLAP plugins.
  void _openProcessorEditor(String channelId, int slotIndex, PluginInfo plugin) {
    final trackId = _busIdToTrackId(channelId);
    final nodeType = _pluginInfoToDspNodeType(plugin);

    if (nodeType != null) {
      // Internal processor — open FabFilter panel in floating window
      final node = DspNode(
        id: '${channelId}_slot_$slotIndex',
        type: nodeType,
        name: plugin.name,
      );

      // Sync with DspChainProvider so the panel can read/write params
      final dspChain = DspChainProvider.instance;
      if (!dspChain.hasChain(trackId)) {
        dspChain.initializeChain(trackId);
      }
      // Ensure the node exists in the chain at this slot
      final chain = dspChain.getChain(trackId);
      if (slotIndex >= chain.nodes.length) {
        dspChain.addNode(trackId, nodeType);
      }

      InternalProcessorEditorWindow.show(
        context: context,
        trackId: trackId,
        slotIndex: slotIndex,
        node: node,
      );
    } else if (plugin.format != PluginFormat.internal) {
      // External plugin — open via FFI
      NativeFFI.instance.insertOpenEditor(trackId, slotIndex);
    }
  }

  /// Map plugin ID to Rust processor name
  /// Only plugins listed here have working Rust engine backends
  String? _pluginIdToProcessorName(String pluginId) {
    const mapping = {
      // EQ
      'rf-pro-eq': 'pro-eq',
      'rf-ultra-eq': 'ultra-eq',
      'rf-linear-eq': 'linear-phase-eq',
      'rf-pultec': 'pultec',
      'rf-api550': 'api550',
      'rf-neve1073': 'neve1073',
      // Dynamics
      'rf-compressor': 'compressor',
      'rf-limiter': 'limiter',
      'rf-gate': 'gate',
      'rf-expander': 'expander',
      'rf-deesser': 'deesser',
      // Effects
      'rf-reverb': 'reverb',
      'rf-delay': 'delay',
      'rf-saturation': 'saturation',
    };
    return mapping[pluginId];
  }

  /// Find which insert slot contains an EQ for given channel
  /// Returns slot index (0-7) or -1 if not found
  int _findEqSlotForChannel(String channelId) {
    final chain = _busInserts[channelId];
    if (chain == null) return -1;

    for (int i = 0; i < chain.slots.length; i++) {
      final slot = chain.slots[i];
      if (slot.plugin != null && slot.plugin!.category == PluginCategory.eq) {
        return i;
      }
    }
    return -1;
  }

  /// Auto-create EQ in first empty insert slot for channel
  /// Returns slot index or -1 if failed
  int _autoCreateEqSlot(String channelId) {
    // Ensure insert chain exists for this channel
    if (!_busInserts.containsKey(channelId)) {
      _busInserts[channelId] = InsertChain(channelId: channelId);
    }

    final chain = _busInserts[channelId]!;

    // Find first empty slot
    for (int i = 0; i < chain.slots.length; i++) {
      if (chain.slots[i].plugin == null) {
        // Create Pro EQ plugin in this slot
        final proEq = PluginInfo(
          id: 'rf-pro-eq-${channelId.hashCode}-$i',
          name: 'Pro EQ',
          category: PluginCategory.eq,
          format: PluginFormat.internal,
          vendor: 'FluxForge Studio',
        );

        setState(() {
          chain.slots[i] = chain.slots[i].copyWith(plugin: proEq);
        });

        // Load EQ into Rust engine insert chain
        // Use correct FFI based on whether it's a bus or track
        if (_isBusChannel(channelId)) {
          final busId = _getBusId(channelId);
          NativeFFI.instance.busInsertLoadProcessor(busId, i, 'pro-eq');
        } else {
          final trackId = _busIdToTrackId(channelId);
          NativeFFI.instance.insertLoadProcessor(trackId, i, 'pro-eq');
        }
        return i;
      }
    }

    // No empty slots
    return -1;
  }

  /// Open EQ in floating window
  void _openEqWindow(String channelId) {
    setState(() {
      _openEqWindows[channelId] = true;
    });
  }

  /// Close EQ floating window
  void _closeEqWindow(String channelId) {
    setState(() {
      _openEqWindows.remove(channelId);
    });
  }

  /// Build floating EQ windows
  List<Widget> _buildFloatingEqWindows(MeteringState metering, bool isPlaying) {
    return _openEqWindows.entries.map((entry) {
      final channelId = entry.key;
      final channelName = channelId == 'master' ? 'Master' : channelId;

      // Calculate signal level from direct FFI — linear amplitude
      final (eqPeakL, eqPeakR) = NativeFFI.instance.getBusPeak(0);
      final signalLevel = (eqPeakL + eqPeakR) / 2;

      final engineApi = EngineApi.instance;

      return Positioned(
        left: 100 + (_openEqWindows.keys.toList().indexOf(channelId) * 50),
        top: 80 + (_openEqWindows.keys.toList().indexOf(channelId) * 30),
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(8),
          color: Colors.transparent,
          child: Container(
            width: 900,
            height: 500,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF404048)),
              boxShadow: [
                BoxShadow(
                  color: FluxForgeTheme.bgVoid.withValues(alpha: 0.8),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Window title bar
                GestureDetector(
                  onPanUpdate: (details) {
                    // TODO: Implement window dragging
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF252528),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.graphic_eq, size: 16, color: Color(0xFFFFB347)),
                        const SizedBox(width: 8),
                        Text(
                          'RF-EQ 64 — $channelName',
                          style: const TextStyle(
                            color: Color(0xFFB0B0B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Color(0xFF707078)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () => _closeEqWindow(channelId),
                        ),
                      ],
                    ),
                  ),
                ),
                // EQ content - Pro EQ DSP (64-band SVF)
                Expanded(
                  child: rf_eq.ProEqEditor(
                    trackId: channelId,
                    width: 900,
                    height: 468,
                    signalLevel: signalLevel,
                    // Pass real spectrum data from engine metering
                    spectrumData: metering.spectrum.isNotEmpty
                        ? metering.spectrum.map((e) => e.toDouble()).toList()
                        : null,
                    onBandChange: (bandIndex, {
                      enabled, freq, gain, q, filterType,
                      dynamicEnabled, dynamicThreshold, dynamicRatio,
                      dynamicAttack, dynamicRelease, dynamicKnee,
                    }) {
                      // UNIFIED EQ ROUTING: Buses use busInsertXxx, Tracks use insertXxx
                      // Find which slot has the EQ for this channel, or auto-create one
                      var slotIndex = _findEqSlotForChannel(channelId);
                      final isBus = _isBusChannel(channelId);

                      if (slotIndex < 0) {
                        // Auto-create EQ in first empty insert slot
                        slotIndex = _autoCreateEqSlot(channelId);
                        if (slotIndex < 0) {
                          return;
                        }
                      } else {
                        // Slot exists in UI state but processor may not be loaded in engine
                        // Use correct FFI based on whether it's a bus or track
                        if (isBus) {
                          final busId = _getBusId(channelId);
                          if (!NativeFFI.instance.busInsertIsLoaded(busId, slotIndex)) {
                            NativeFFI.instance.busInsertLoadProcessor(busId, slotIndex, 'pro-eq');
                          }
                        } else {
                          final trackId = _busIdToTrackId(channelId);
                          if (!NativeFFI.instance.insertIsLoaded(trackId, slotIndex)) {
                            NativeFFI.instance.insertLoadProcessor(trackId, slotIndex, 'pro-eq');
                          }
                        }
                      }

                      // Use insert chain params: per band = 11
                      // (freq=0, gain=1, q=2, enabled=3, shape=4,
                      //  dynEnabled=5, dynThreshold=6, dynRatio=7, dynAttack=8, dynRelease=9, dynKnee=10)
                      final baseParam = bandIndex * 11;

                      // Use correct FFI based on whether it's a bus or track
                      void setParam(int paramOffset, double value) {
                        if (isBus) {
                          final busId = _getBusId(channelId);
                          NativeFFI.instance.busInsertSetParam(busId, slotIndex, baseParam + paramOffset, value);
                        } else {
                          final trackId = _busIdToTrackId(channelId);
                          NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + paramOffset, value);
                        }
                      }

                      if (freq != null) setParam(0, freq);
                      if (gain != null) setParam(1, gain);
                      if (q != null) setParam(2, q);
                      if (enabled != null) setParam(3, enabled ? 1.0 : 0.0);
                      if (filterType != null) setParam(4, filterType.toDouble());
                      // Dynamic EQ parameters
                      if (dynamicEnabled != null) setParam(5, dynamicEnabled ? 1.0 : 0.0);
                      if (dynamicThreshold != null) setParam(6, dynamicThreshold);
                      if (dynamicRatio != null) setParam(7, dynamicRatio);
                      if (dynamicAttack != null) setParam(8, dynamicAttack);
                      if (dynamicRelease != null) setParam(9, dynamicRelease);
                      if (dynamicKnee != null) setParam(10, dynamicKnee);
                    },
                    onBypassChange: (bypass) {
                      if (bypass) {
                        engineApi.proEqReset(channelId);
                      }
                    },
                    onPhaseModeChange: (mode) {
                      // 0=ZeroLatency, 1=Natural, 2=Linear
                      engineApi.proEqSetPhaseMode(channelId, mode);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  /// Build Piano Roll content - Professional MIDI editor
  Widget _buildPianoRollContent() {
    // Use clip ID 1 as default MIDI clip
    return PianoRollWidget(
      clipId: 1,
      lengthBars: 8,
      bpm: 120.0,
      onNotesChanged: () {
      },
    );
  }

  /// Build Pro EQ content - RF-EQ 64 (64-Band Parametric Equalizer)
  /// Uses DspCommand queue for real-time audio processing (NOT PRO_EQS HashMap!)
  Widget _buildProEqContent(dynamic metering, bool isPlaying) {
    // Signal level for EQ analyzer — direct FFI, linear amplitude
    final (eqSigL, eqSigR) = NativeFFI.instance.getBusPeak(0);
    final signalLevel = (eqSigL + eqSigR) / 2;

    // Use NativeFFI for real-time DSP command queue
    // IMPORTANT: eqSetBand* goes through DspCommand queue → audio callback
    // vs proEqSetBand* which goes to PRO_EQS HashMap (never processed!)
    final ffi = NativeFFI.instance;

    // Use FF-Q 64 - the professional parametric EQ with Pro EQ DSP
    return LayoutBuilder(
      builder: (context, constraints) {
        return rf_eq.ProEqEditor(
          trackId: 'master',
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          signalLevel: signalLevel,
          onBandChange: (bandIndex, {
            enabled, freq, gain, q, filterType,
            dynamicEnabled, dynamicThreshold, dynamicRatio,
            dynamicAttack, dynamicRelease, dynamicKnee,
          }) {
            // Send EQ band changes via DspCommand queue (processes audio!)
            // trackId 0 = master in DspStorage
            const trackId = 0;
            if (enabled != null) {
              ffi.eqSetBandEnabled(trackId, bandIndex, enabled);
            }
            if (freq != null) {
              ffi.eqSetBandFrequency(trackId, bandIndex, freq);
            }
            if (gain != null) {
              ffi.eqSetBandGain(trackId, bandIndex, gain);
            }
            if (q != null) {
              ffi.eqSetBandQ(trackId, bandIndex, q);
            }
            if (filterType != null) {
              // Map UI filter type to EQ filter shape (0-9)
              ffi.eqSetBandShape(trackId, bandIndex, filterType.clamp(0, 9));
            }
            // Dynamic EQ parameters - TODO: add DspCommand support
            // Currently dynamic EQ is UI-only, needs DspCommand extension
          },
          onBypassChange: (bypass) {
            // Global EQ bypass via DspCommand
            ffi.eqSetBypass(0, bypass);
          },
          onPhaseModeChange: (mode) {
            // Phase mode - TODO: add DspCommand support
            // 0=ZeroLatency, 1=Natural, 2=Linear
          },
        );
      },
    );
  }

  /// Build Analog EQ content - Pultec, API 550, Neve 1073
  Widget _buildAnalogEqContent() {
    return Container(
      color: const Color(0xFF0A0A0C),
      child: Column(
        children: [
          // EQ Type selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              border: Border(
                bottom: BorderSide(color: FluxForgeTheme.textPrimary.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                _buildAnalogEqTab('Pultec EQP-1A', 0),
                const SizedBox(width: 8),
                _buildAnalogEqTab('API 550A', 1),
                const SizedBox(width: 8),
                _buildAnalogEqTab('Neve 1073', 2),
                const Spacer(),
                Text(
                  'Vintage Analog EQ Models',
                  style: TextStyle(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // EQ Content
          Expanded(
            child: Center(
              child: _selectedAnalogEq == 0
                  ? PultecEq(
                      initialParams: _pultecParams,
                      onParamsChanged: (params) {
                        setState(() => _pultecParams = params);
                      },
                    )
                  : _selectedAnalogEq == 1
                      ? Api550Eq(
                          initialParams: _apiParams,
                          onParamsChanged: (params) {
                            setState(() => _apiParams = params);
                          },
                        )
                      : Neve1073Eq(
                          initialParams: _neveParams,
                          onParamsChanged: (params) {
                            setState(() => _neveParams = params);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalogEqTab(String label, int index) {
    final isSelected = _selectedAnalogEq == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedAnalogEq = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textPrimary.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Build Time Stretch content - RF-Elastic Pro
  Widget _buildTimeStretchContent() {
    // Get selected clip ID, default to 1 for demo
    final selectedClipId = _clips.isNotEmpty
        ? int.tryParse(_clips.first.id) ?? 1
        : 1;

    return Container(
      color: const Color(0xFF0A0A0C),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time Stretch Panel
          Expanded(
            flex: 2,
            child: TimeStretchPanel(
              clipId: selectedClipId,
              sampleRate: NativeFFI.instance.getSampleRate().toDouble(),
              onSettingsChanged: () {
                // Trigger waveform redraw when stretch changes
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 16),
          // Info Panel
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A2A30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RF-Elastic Pro',
                    style: TextStyle(
                      color: Color(0xFF4A9EFF),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ultimate Time-Stretching Engine',
                    style: TextStyle(color: Color(0xFFB0B0B8), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('STN Decomposition', 'Sines + Transients + Noise'),
                  _buildInfoRow('Phase Vocoder', 'Peak-locked phase coherence'),
                  _buildInfoRow('Transient Lock', 'WSOLA with preservation'),
                  _buildInfoRow('Noise Morphing', 'Magnitude interpolation'),
                  _buildInfoRow('Quality', 'Better than élastique Pro'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A9EFF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF4A9EFF), size: 14),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Select a clip and adjust stretch/pitch parameters.',
                            style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF40FF90), size: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFFE0E0E8), fontSize: 11)),
                Text(value, style: const TextStyle(color: Color(0xFF808088), fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build Analysis content - Transient & Pitch Detection
  Widget _buildAnalysisContent() {
    // Sample rate available via NativeFFI.instance.getSampleRate() when needed

    return Container(
      color: const Color(0xFF0A0A0C),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Transient Detection Panel
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FluxForgeTheme.textPrimary.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flash_on, color: FluxForgeTheme.accentOrange, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Transient Detection',
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Detects transients in audio clips for:\n'
                    '• Automatic beat slicing\n'
                    '• Tempo detection\n'
                    '• Quantization points',
                    style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  // Sensitivity slider
                  Text('Sensitivity', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
                  Slider(
                    value: _transientSensitivity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => setState(() => _transientSensitivity = v),
                    activeColor: FluxForgeTheme.accentOrange,
                  ),
                  // Algorithm selector
                  Text('Algorithm', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
                  const SizedBox(height: 4),
                  DropdownButton<int>(
                    value: _transientAlgorithm,
                    dropdownColor: FluxForgeTheme.bgMid,
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                    underline: Container(height: 1, color: FluxForgeTheme.borderSubtle),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('High Emphasis')),
                      DropdownMenuItem(value: 1, child: Text('Low Emphasis')),
                      DropdownMenuItem(value: 2, child: Text('Enhanced (Default)')),
                      DropdownMenuItem(value: 3, child: Text('Spectral Flux')),
                      DropdownMenuItem(value: 4, child: Text('Complex Domain')),
                    ],
                    onChanged: (v) => setState(() => _transientAlgorithm = v ?? 2),
                  ),
                  const Spacer(),
                  // Detect button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Detect Transients'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FluxForgeTheme.accentOrange,
                        foregroundColor: FluxForgeTheme.textPrimary,
                      ),
                      onPressed: () {
                        // TODO: Get audio data from selected clip
                        // final positions = NativeFFI.instance.transientDetect(samples, sampleRate, sensitivity: _transientSensitivity, algorithm: _transientAlgorithm);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Pitch Detection Panel
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FluxForgeTheme.textPrimary.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.music_note, color: FluxForgeTheme.accentCyan, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Pitch Detection',
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Detects pitch in audio clips for:\n'
                    '• Audio to MIDI conversion\n'
                    '• Key detection\n'
                    '• Melodyne-style editing',
                    style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  // Detected pitch display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgVoid,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Detected Pitch', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
                              Text(
                                _detectedPitch > 0 ? '${_detectedPitch.toStringAsFixed(1)} Hz' : '-- Hz',
                                style: TextStyle(
                                  color: FluxForgeTheme.accentCyan,
                                  fontSize: 20,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('MIDI Note', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
                              Text(
                                _detectedMidi >= 0 ? _midiNoteToName(_detectedMidi) : '--',
                                style: TextStyle(
                                  color: FluxForgeTheme.accentGreen,
                                  fontSize: 20,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Detect button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.piano, size: 16),
                      label: const Text('Detect Pitch'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FluxForgeTheme.accentCyan,
                        foregroundColor: FluxForgeTheme.textPrimary,
                      ),
                      onPressed: () {
                        // TODO: Get audio data from selected clip
                        // _detectedPitch = NativeFFI.instance.pitchDetect(samples, sampleRate);
                        // _detectedMidi = NativeFFI.instance.pitchDetectMidi(samples, sampleRate);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Convert MIDI note number to name (e.g., 60 -> "C4")
  String _midiNoteToName(int midi) {
    if (midi < 0 || midi > 127) return '--';
    const notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi ~/ 12) - 1;
    final note = notes[midi % 12];
    return '$note$octave';
  }

  /// Get human-readable name for automation parameter
  String _getParameterName(AutomationParameter parameter) {
    switch (parameter) {
      case AutomationParameter.volume:
        return 'Volume';
      case AutomationParameter.pan:
        return 'Pan';
      case AutomationParameter.mute:
        return 'Mute';
      case AutomationParameter.send1:
        return 'Send 1';
      case AutomationParameter.send2:
        return 'Send 2';
      case AutomationParameter.send3:
        return 'Send 3';
      case AutomationParameter.send4:
        return 'Send 4';
      case AutomationParameter.eq1Gain:
        return 'EQ 1 Gain';
      case AutomationParameter.eq1Freq:
        return 'EQ 1 Freq';
      case AutomationParameter.eq2Gain:
        return 'EQ 2 Gain';
      case AutomationParameter.eq2Freq:
        return 'EQ 2 Freq';
      case AutomationParameter.compThreshold:
        return 'Comp Threshold';
      case AutomationParameter.compRatio:
        return 'Comp Ratio';
      case AutomationParameter.custom:
        return 'Custom';
    }
  }

  /// Get color for automation parameter
  Color _getParameterColor(AutomationParameter parameter) {
    switch (parameter) {
      case AutomationParameter.volume:
        return const Color(0xFF4A9EFF); // Blue
      case AutomationParameter.pan:
        return const Color(0xFFFF9040); // Orange
      case AutomationParameter.mute:
        return const Color(0xFFFF4060); // Red
      case AutomationParameter.send1:
      case AutomationParameter.send2:
      case AutomationParameter.send3:
      case AutomationParameter.send4:
        return const Color(0xFF40FF90); // Green
      case AutomationParameter.eq1Gain:
      case AutomationParameter.eq1Freq:
      case AutomationParameter.eq2Gain:
      case AutomationParameter.eq2Freq:
        return const Color(0xFFFFFF40); // Yellow
      case AutomationParameter.compThreshold:
      case AutomationParameter.compRatio:
        return const Color(0xFF40C8FF); // Cyan
      case AutomationParameter.custom:
        return const Color(0xFF8B5CF6); // Purple
    }
  }

  /// Get default EQ bands (for generic EQ - kept for backwards compatibility)
  // ignore: unused_element
  List<generic_eq.EqBand> _getDefaultEqBands() {
    return [
      const generic_eq.EqBand(id: '1', frequency: 80, gain: 0, q: 0.7, type: generic_eq.FilterType.lowShelf, enabled: true),
      const generic_eq.EqBand(id: '2', frequency: 250, gain: 0, q: 1.5, type: generic_eq.FilterType.bell, enabled: true),
      const generic_eq.EqBand(id: '3', frequency: 1000, gain: 0, q: 1.0, type: generic_eq.FilterType.bell, enabled: true),
      const generic_eq.EqBand(id: '4', frequency: 4000, gain: 0, q: 2.0, type: generic_eq.FilterType.bell, enabled: true),
      const generic_eq.EqBand(id: '5', frequency: 12000, gain: 0, q: 0.7, type: generic_eq.FilterType.highShelf, enabled: true),
    ];
  }

  /// Sync EQ state to Rust DSP engine
  // ignore: unused_element
  void _syncEqToEngine() {
    // TODO: Call Rust engine via FFI when ready
    // engine.setMasterEq(_eqBands.map((b) => b.toMap()).toList());
  }

  /// Build Loudness meter content (LUFS + True Peak)
  Widget _buildLoudnessContent(MeteringState metering) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main loudness meter
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LoudnessMeter(
                metering: metering,
                target: _loudnessTarget,
                showHistory: false,
                onTargetChanged: (target) {
                  setState(() => _loudnessTarget = target);
                },
                onResetIntegrated: () {
                  // TODO: Call engine.resetLufsIntegrated()
                },
              ),
            ),
          ),

          // Right panel - info and recommendations
          Container(
            width: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              border: Border(
                left: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Target Standards',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildTargetInfoRow('Broadcast (R128)', '-23 LUFS', '-1 dBTP'),
                _buildTargetInfoRow('Streaming', '-14 LUFS', '-2 dBTP'),
                _buildTargetInfoRow('Cinema (ATSC)', '-24 LUFS', '-2 dBTP'),
                const Spacer(),
                // Current status
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Reading',
                        style: TextStyle(
                          fontSize: 9,
                          color: FluxForgeTheme.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'LUFS-I',
                            style: TextStyle(
                              fontSize: 10,
                              color: FluxForgeTheme.textSecondary,
                            ),
                          ),
                          Text(
                            metering.masterLufsI > -70
                                ? '${metering.masterLufsI.toStringAsFixed(1)} LUFS'
                                : '-∞',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: FluxForgeTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'True Peak',
                            style: TextStyle(
                              fontSize: 10,
                              color: FluxForgeTheme.textSecondary,
                            ),
                          ),
                          Text(
                            metering.masterTruePeak > -70
                                ? '${metering.masterTruePeak.toStringAsFixed(1)} dBTP'
                                : '-∞',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: metering.masterTruePeak > -1
                                  ? const Color(0xFFFF4040)
                                  : FluxForgeTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetInfoRow(String name, String lufs, String tp) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          Text(
            lufs,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tp,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// Build inspector sections based on mode
  List<InspectorSection> _buildInspectorSections() {
    if (_editorMode == EditorMode.daw) {
      // DAW mode - clip/track inspector
      return [
        InspectorSection(
          id: 'clip',
          title: 'Clip Properties',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InspectorField(label: 'Name', value: 'Audio_01.wav'),
              _InspectorField(label: 'Duration', value: '00:04.250'),
              _InspectorField(label: 'Sample Rate', value: '48000 Hz'),
              _InspectorField(label: 'Channels', value: 'Stereo'),
            ],
          ),
        ),
        InspectorSection(
          id: 'gain',
          title: 'Gain & Fades',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InspectorField(label: 'Clip Gain', value: '0.0 dB'),
              _InspectorField(label: 'Fade In', value: '0 ms'),
              _InspectorField(label: 'Fade Out', value: '0 ms'),
            ],
          ),
        ),
      ];
    } else {
      // ═══════════════════════════════════════════════════════════════════════════
      // MIDDLEWARE MODE — Inspector connected to selected LAYER (not action)
      // Single source of truth: MiddlewareProvider.compositeEvents[].layers[]
      // ═══════════════════════════════════════════════════════════════════════════
      final layer = _selectedLayer;
      final hasLayer = layer != null;
      final composite = _selectedComposite;

      // Asset options from audio pool - real sounds only, empty first
      final poolAssets = _audioPool.map((f) => f.name).toList();
      final assetOptions = ['', ...poolAssets]; // Empty first, then real sounds

      return [
        // Event info (if no layer selected)
        if (!hasLayer && composite != null)
          InspectorSection(
            id: 'event-info',
            title: 'Event',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InspectorEditableField(
                  label: 'Name',
                  value: composite.name,
                  onChanged: (newName) {
                    if (newName.isNotEmpty) {
                      final mw = context.read<MiddlewareProvider>();
                      mw.updateCompositeEvent(composite.copyWith(name: newName));
                    }
                  },
                ),
                _InspectorField(label: 'Category', value: composite.category.isEmpty ? 'General' : composite.category),
                _InspectorField(label: 'Layers', value: '${composite.layers.length}'),
                const SizedBox(height: 8),
                Text(
                  'Select a layer to edit properties',
                  style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),

        // Layer section - matches command bar order: Type, Bus, Asset, Vol, Pan, Dly, FdIn, FdOut, TrS, TrE, M, S, L
        InspectorSection(
          id: 'layer',
          title: hasLayer ? 'Layer #${_selectedLayerIndex + 1}' : 'Layer',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name (editable)
              _InspectorTextFieldInteractive(
                label: 'Name',
                value: hasLayer ? layer.name : '',
                enabled: hasLayer,
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(name: v)),
              ),
              // Action Type
              _InspectorDropdownInteractive(
                label: 'Type',
                value: hasLayer ? layer.actionType : 'Play',
                options: kActionTypes,
                enabled: hasLayer,
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(actionType: v)),
              ),
              // Bus
              _InspectorDropdownInteractive(
                label: 'Bus',
                value: hasLayer && layer.busId != null && layer.busId! < kAllBuses.length
                    ? kAllBuses[layer.busId!]
                    : 'SFX',
                options: kAllBuses,
                enabled: hasLayer,
                onChanged: (v) {
                  final busIndex = kAllBuses.indexOf(v);
                  _updateSelectedLayer((l) => l.copyWith(busId: busIndex >= 0 ? busIndex : null));
                },
              ),
              // Asset
              Builder(builder: (context) {
                String displayValue = '';
                if (hasLayer && layer.audioPath.isNotEmpty) {
                  displayValue = layer.audioPath.contains('/')
                      ? layer.audioPath.split('/').last
                      : layer.audioPath;
                }
                if (!assetOptions.contains(displayValue)) {
                  displayValue = '';
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InspectorDropdownInteractive(
                      label: 'Asset',
                      value: displayValue,
                      options: assetOptions,
                      enabled: hasLayer,
                      onChanged: (v) {
                        final poolFile = _audioPool.where((f) => f.name == v).firstOrNull;
                        final newPath = poolFile?.path ?? v;
                        _updateSelectedLayer((l) => l.copyWith(audioPath: newPath));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 24,
                        child: TextButton.icon(
                          onPressed: hasLayer ? () async {
                            final path = await AudioWaveformPickerDialog.show(
                              context,
                              title: 'Select Audio File',
                              initialDirectory: layer.audioPath.isNotEmpty
                                  ? layer.audioPath.substring(0, layer.audioPath.lastIndexOf('/'))
                                  : null,
                            );
                            if (path != null) {
                              _updateSelectedLayer((l) => l.copyWith(audioPath: path));
                            }
                          } : null,
                          icon: const Icon(Icons.folder_open, size: 12),
                          label: const Text('Browse...', style: TextStyle(fontSize: 10)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              // Volume
              _InspectorSliderInteractive(
                label: 'Volume',
                value: hasLayer ? layer.volume : 1.0,
                min: 0.0,
                max: 2.0,
                enabled: hasLayer,
                formatValue: (v) => v <= 0.001 ? '-∞ dB' : '${(20 * math.log(v) / math.ln10).toStringAsFixed(1)} dB',
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(volume: v)),
                defaultValue: 1.0,
              ),
              // Pan
              _InspectorSliderInteractive(
                label: 'Pan',
                value: hasLayer ? layer.pan : 0.0,
                min: -1.0,
                max: 1.0,
                enabled: hasLayer,
                formatValue: (v) => v == 0 ? 'C' : (v < 0 ? 'L${(-v * 100).toInt()}' : 'R${(v * 100).toInt()}'),
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(pan: v)),
              ),
              // Delay
              Builder(builder: (context) {
                final durSec = layer?.durationSeconds ?? 60.0;
                return _InspectorSliderInteractive(
                  label: 'Delay',
                  value: hasLayer ? layer.offsetMs / 1000.0 : 0.0,
                  min: 0.0,
                  max: durSec,
                  enabled: hasLayer,
                  formatValue: (v) => '${(v * 1000).toInt()} ms',
                  onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(offsetMs: v * 1000.0)),
                );
              }),
              // Fade In
              Builder(builder: (context) {
                final durSec = layer?.durationSeconds ?? 60.0;
                return _InspectorSliderInteractive(
                  label: 'Fade In',
                  value: hasLayer ? layer.fadeInMs / 1000.0 : 0.0,
                  min: 0.0,
                  max: durSec,
                  enabled: hasLayer,
                  formatValue: (v) => '${(v * 1000).toInt()} ms',
                  onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(fadeInMs: v * 1000.0)),
                );
              }),
              // Fade In Curve
              _InspectorDropdownInteractive(
                label: 'Fade In Curve',
                value: hasLayer ? layer.fadeInCurve.name : CrossfadeCurve.linear.name,
                options: CrossfadeCurve.values.map((c) => c.name).toList(),
                enabled: hasLayer,
                onChanged: (v) {
                  final curve = CrossfadeCurve.values.firstWhere(
                    (c) => c.name == v,
                    orElse: () => CrossfadeCurve.linear,
                  );
                  _updateSelectedLayer((l) => l.copyWith(fadeInCurve: curve));
                },
              ),
              // Fade Out
              Builder(builder: (context) {
                final durSec = layer?.durationSeconds ?? 60.0;
                return _InspectorSliderInteractive(
                  label: 'Fade Out',
                  value: hasLayer ? layer.fadeOutMs / 1000.0 : 0.0,
                  min: 0.0,
                  max: durSec,
                  enabled: hasLayer,
                  formatValue: (v) => '${(v * 1000).toInt()} ms',
                  onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(fadeOutMs: v * 1000.0)),
                );
              }),
              // Fade Out Curve
              _InspectorDropdownInteractive(
                label: 'Fade Out Curve',
                value: hasLayer ? layer.fadeOutCurve.name : CrossfadeCurve.linear.name,
                options: CrossfadeCurve.values.map((c) => c.name).toList(),
                enabled: hasLayer,
                onChanged: (v) {
                  final curve = CrossfadeCurve.values.firstWhere(
                    (c) => c.name == v,
                    orElse: () => CrossfadeCurve.linear,
                  );
                  _updateSelectedLayer((l) => l.copyWith(fadeOutCurve: curve));
                },
              ),
              // Trim Start
              Builder(builder: (context) {
                final durSec = layer?.durationSeconds ?? 60.0;
                return _InspectorSliderInteractive(
                  label: 'Trim Start',
                  value: hasLayer ? layer.trimStartMs / 1000.0 : 0.0,
                  min: 0.0,
                  max: durSec,
                  enabled: hasLayer,
                  formatValue: (v) => '${(v * 1000).toInt()} ms',
                  onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(trimStartMs: v * 1000.0)),
                );
              }),
              // Trim End
              Builder(builder: (context) {
                final durSec = layer?.durationSeconds ?? 60.0;
                return _InspectorSliderInteractive(
                  label: 'Trim End',
                  value: hasLayer ? layer.trimEndMs / 1000.0 : 0.0,
                  min: 0.0,
                  max: durSec,
                  enabled: hasLayer,
                  formatValue: (v) => '${(v * 1000).toInt()} ms',
                  onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(trimEndMs: v * 1000.0)),
                );
              }),
              const SizedBox(height: 8),
              // Muted
              _InspectorCheckboxInteractive(
                label: 'Muted',
                checked: hasLayer ? layer.muted : false,
                enabled: hasLayer,
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(muted: v)),
              ),
              // Solo
              _InspectorCheckboxInteractive(
                label: 'Solo',
                checked: hasLayer ? layer.solo : false,
                enabled: hasLayer,
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(solo: v)),
              ),
              // Loop (per-layer)
              _InspectorCheckboxInteractive(
                label: 'Loop',
                checked: hasLayer ? layer.loop : false,
                enabled: hasLayer,
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(loop: v)),
              ),
              // Overlap (per-layer)
              _InspectorCheckboxInteractive(
                label: 'Overlap',
                checked: hasLayer ? layer.overlap : false,
                enabled: hasLayer,
                onChanged: (v) => _updateSelectedLayer((l) => l.copyWith(overlap: v)),
              ),
            ],
          ),
        ),
      ];
    }
  }

  /// Build all lower zone tabs (matches React LayoutDemo.tsx 1:1)
  /// All tabs are created, then filtered by mode visibility
  List<LowerZoneTab> _buildLowerTabs(dynamic metering, bool isPlaying) {
    // ═══════════════════════════════════════════════════════════════════════
    // REORGANIZED LOWER ZONE - Clean, Intuitive, Professional
    // ═══════════════════════════════════════════════════════════════════════
    // 6 Groups, ~25 Tabs (down from 52+)
    // ═══════════════════════════════════════════════════════════════════════
    final List<LowerZoneTab> tabs = [
      // ══════════════════════════════════════════════════════════════════════
      // GROUP 1: MIX — Core mixing tools
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'mixer',
        label: _editorMode == EditorMode.daw ? 'Mixer' : 'Bus Mix',
        icon: Icons.tune,
        // DAW mode: full mixer with track channels
        // Middleware/Slot mode: simplified bus masters only
        content: _editorMode == EditorMode.daw
            ? _buildUltimateMixerContent(metering, isPlaying)
            : _buildMiddlewareMixerContent(metering, isPlaying),
        groupId: 'mix',
      ),
      LowerZoneTab(
        id: 'control-room',
        label: 'Control Room',
        icon: Icons.headphones,
        content: _buildControlRoomContent(),
        groupId: 'mix',
      ),
      LowerZoneTab(
        id: 'recording',
        label: 'Recording',
        icon: Icons.fiber_manual_record,
        content: _buildRecordingContent(),
        groupId: 'mix',
      ),

      // ══════════════════════════════════════════════════════════════════════
      // GROUP 2: EDIT — Clip and arrangement editing
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'clip-editor',
        label: 'Clip Editor',
        icon: Icons.edit,
        contentBuilder: _buildClipEditorContent,
        groupId: 'edit',
      ),
      LowerZoneTab(
        id: 'crossfade',
        label: 'Crossfade',
        icon: Icons.compare,
        content: _buildCrossfadeEditorContent(),
        groupId: 'edit',
      ),
      LowerZoneTab(
        id: 'automation',
        label: 'Automation',
        icon: Icons.timeline,
        content: _buildAutomationEditorContent(),
        groupId: 'edit',
      ),
      LowerZoneTab(
        id: 'piano-roll',
        label: 'Piano Roll',
        icon: Icons.piano,
        content: _buildPianoRollContent(),
        groupId: 'edit',
      ),

      // ══════════════════════════════════════════════════════════════════════
      // GROUP 3: ANALYZE — Metering and analysis
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'meters',
        label: 'Meters',
        icon: Icons.speed,
        content: ProMeteringPanel(metering: metering),
        groupId: 'analyze',
      ),
      LowerZoneTab(
        id: 'loudness',
        label: 'Loudness',
        icon: Icons.surround_sound,
        content: _buildLoudnessContent(metering),
        groupId: 'analyze',
      ),
      LowerZoneTab(
        id: 'spectrum',
        label: 'Spectrum',
        icon: Icons.show_chart,
        content: const SpectrumAnalyzerDemo(),
        groupId: 'analyze',
      ),

      // ══════════════════════════════════════════════════════════════════════
      // GROUP 4: PROCESS — DSP processors
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'eq',
        label: 'EQ',
        icon: Icons.graphic_eq,
        content: _buildProEqContent(metering, isPlaying),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'dynamics',
        label: 'Dynamics',
        icon: Icons.compress,
        content: DynamicsPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'spatial',
        label: 'Spatial',
        icon: Icons.spatial_audio,
        content: SpatialPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'reverb',
        label: 'Reverb',
        icon: Icons.blur_on,
        content: FabFilterReverbPanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'delay',
        label: 'Delay',
        icon: Icons.timer,
        content: DelayPanel(trackId: 0, bpm: 120.0, sampleRate: 48000.0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'pitch',
        label: 'Pitch',
        icon: Icons.music_note,
        content: PitchCorrectionPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'spectral',
        label: 'Spectral',
        icon: Icons.waves,
        content: SpectralPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'saturation',
        label: 'Saturation',
        icon: Icons.whatshot,
        content: SaturationPanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'transient',
        label: 'Transient',
        icon: Icons.flash_on,
        content: TransientPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'process',
      ),

      // ══════════════════════════════════════════════════════════════════════
      // FF DSP PANELS — Premium DSP interfaces
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'ff-eq',
        label: 'FF-Q',
        icon: Icons.equalizer,
        content: FabFilterEqPanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'ff-comp',
        label: 'FF-C',
        icon: Icons.compress,
        content: FabFilterCompressorPanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'ff-limiter',
        label: 'FF-L',
        icon: Icons.trending_flat,
        content: FabFilterLimiterPanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'ff-reverb',
        label: 'FF-R',
        icon: Icons.waves,
        content: FabFilterReverbPanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'ff-gate',
        label: 'FF-G',
        icon: Icons.door_sliding,
        content: FabFilterGatePanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'ff-delay',
        label: 'FF-D',
        icon: Icons.timer,
        content: FabFilterDelayPanel(trackId: 0),
        groupId: 'process',
      ),
      LowerZoneTab(
        id: 'ff-sat',
        label: 'FF-SAT',
        icon: Icons.whatshot,
        content: FabFilterSaturationPanel(trackId: 0),
        groupId: 'process',
      ),

      // ══════════════════════════════════════════════════════════════════════
      // GROUP 5: MEDIA — Browser, pool, templates
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'audio-browser',
        label: 'Browser',
        icon: Icons.folder_open,
        content: const AudioBrowserTabPlaceholder(),
        groupId: 'media',
      ),
      LowerZoneTab(
        id: 'audio-pool',
        label: 'Pool',
        icon: Icons.library_music,
        content: AudioPoolPanel(
          key: AudioPoolPanelState.globalKey,
          onFileDoubleClick: _handleAudioPoolFileDoubleClick,
        ),
        groupId: 'media',
      ),
      LowerZoneTab(
        id: 'plugins',
        label: 'Plugins',
        icon: Icons.extension,
        content: PluginBrowser(
          onPluginLoad: (plugin) {
          },
        ),
        groupId: 'media',
      ),
      LowerZoneTab(
        id: 'track-templates',
        label: 'Templates',
        icon: Icons.content_copy,
        content: TrackTemplatesPanel(
          onTrackCreated: (trackId) => setState(() {}),
        ),
        groupId: 'media',
      ),
      LowerZoneTab(
        id: 'project-versions',
        label: 'Versions',
        icon: Icons.history,
        content: ProjectVersionsPanel(
          onVersionRestored: () => setState(() {}),
        ),
        groupId: 'media',
      ),

      // ══════════════════════════════════════════════════════════════════════
      // GROUP 6: ADVANCED — Pro features, routing, mastering
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'routing',
        label: 'Routing',
        icon: Icons.device_hub,
        content: _buildRoutingContent(),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'sidechain',
        label: 'Sidechain',
        icon: Icons.call_split,
        content: SidechainPanel(processorId: 0),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'multiband',
        label: 'Multiband',
        icon: Icons.equalizer,
        content: MultibandPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'channel-strip',
        label: 'Channel Strip',
        icon: Icons.tune,
        content: ChannelStripPanel(trackId: 0),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'mastering',
        label: 'Mastering',
        icon: Icons.auto_awesome,
        content: MasteringPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'restoration',
        label: 'Restoration',
        icon: Icons.healing,
        content: RestorationPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'ml-processor',
        label: 'ML/AI',
        icon: Icons.psychology,
        content: MlProcessorPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'advanced',
      ),

      // ══════════════════════════════════════════════════════════════════════
      // GROUP 7: MIDDLEWARE — Game audio middleware (Wwise-style)
      // ══════════════════════════════════════════════════════════════════════
      LowerZoneTab(
        id: 'events-folder',
        label: 'Events Folder',
        icon: Icons.folder_special,
        content: const EventsFolderPanel(),
        groupId: 'middleware',
      ),
      LowerZoneTab(
        id: 'event-editor',
        label: 'Event Editor',
        icon: Icons.edit_note,
        content: const EventEditorPanel(),
        groupId: 'middleware',
      ),
      LowerZoneTab(
        id: 'ale',
        label: 'ALE',
        icon: Icons.auto_awesome,
        content: const AlePanel(),
        groupId: 'middleware',
      ),
    ];

    // Filter tabs based on mode visibility
    return filterTabsForMode(tabs, _editorMode, (t) => t.id);
  }

  /// Build tab groups (matches React LayoutDemo.tsx 1:1)
  /// All groups are created, then filtered by mode visibility
  List<TabGroup> _buildTabGroups() {
    // ═══════════════════════════════════════════════════════════════════════
    // REORGANIZED TAB GROUPS - Clean, Intuitive, Professional
    // ═══════════════════════════════════════════════════════════════════════
    // 6 Groups (down from 9) - Logical workflow order
    // ═══════════════════════════════════════════════════════════════════════
    final List<TabGroup> allGroups = [
      // GROUP 1: MIX — Core mixing workflow
      const TabGroup(
        id: 'mix',
        label: 'Mix',
        tabs: ['mixer', 'control-room', 'recording'],
      ),
      // GROUP 2: EDIT — Clip and arrangement editing
      const TabGroup(
        id: 'edit',
        label: 'Edit',
        tabs: ['clip-editor', 'crossfade', 'automation', 'piano-roll'],
      ),
      // GROUP 3: ANALYZE — Metering and analysis
      const TabGroup(
        id: 'analyze',
        label: 'Analyze',
        tabs: ['meters', 'loudness', 'spectrum'],
      ),
      // GROUP 4: PROCESS — DSP processors (consolidated + FF premium)
      const TabGroup(
        id: 'process',
        label: 'Process',
        tabs: [
          'eq', 'dynamics', 'spatial', 'reverb', 'delay', 'pitch', 'spectral', 'saturation', 'transient',
          // FF premium DSP panels
          'ff-eq', 'ff-comp', 'ff-limiter', 'ff-reverb', 'ff-gate', 'ff-delay', 'ff-sat',
        ],
      ),
      // GROUP 5: MEDIA — Browser, pool, plugins, templates
      const TabGroup(
        id: 'media',
        label: 'Media',
        tabs: ['audio-browser', 'audio-pool', 'plugins', 'track-templates', 'project-versions'],
      ),
      // GROUP 6: ADVANCED — Pro features, routing, mastering
      const TabGroup(
        id: 'advanced',
        label: 'Advanced',
        tabs: ['routing', 'sidechain', 'multiband', 'channel-strip', 'mastering', 'restoration', 'ml-processor'],
      ),
      // GROUP 7: MIDDLEWARE — Game audio middleware (Wwise-style)
      const TabGroup(
        id: 'middleware',
        label: 'Middleware',
        tabs: ['events-folder', 'event-editor', 'ale'],
      ),
    ];

    // Filter groups based on mode visibility
    return filterTabGroupsForMode(allGroups, _editorMode, (g) => g.id);
  }

}

// ignore: unused_element
class _MeterRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MeterRow({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                  color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: TextStyle(
                color: FluxForgeTheme.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _StatusIndicator extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _StatusIndicator({
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : FluxForgeTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? color : FluxForgeTheme.textTertiary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ============ Inspector Field Widgets ============

class _InspectorField extends StatelessWidget {
  final String label;
  final String value;

  const _InspectorField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Text(
                value,
                style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorEditableField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _InspectorEditableField({required this.label, required this.value, required this.onChanged});

  @override
  State<_InspectorEditableField> createState() => _InspectorEditableFieldState();
}

class _InspectorEditableFieldState extends State<_InspectorEditableField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _InspectorEditableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(widget.label, style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: FluxForgeTheme.bgDeepest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: FluxForgeTheme.accentBlue)),
              ),
              onSubmitted: (v) => widget.onChanged(v),
              onTapOutside: (_) {
                if (_controller.text != widget.value) {
                  widget.onChanged(_controller.text);
                }
                FocusScope.of(context).unfocus();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;

  const _InspectorDropdown({
    required this.label,
    required this.value,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value,
                    style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                  ),
                  Icon(Icons.arrow_drop_down, size: 14, color: FluxForgeTheme.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorSlider extends StatelessWidget {
  final String label;
  final double value;
  final String suffix;

  const _InspectorSlider({
    required this.label,
    required this.value,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      suffix,
                      style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorCheckbox extends StatelessWidget {
  final String label;
  final bool checked;

  const _InspectorCheckbox({required this.label, required this.checked});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: checked ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: checked ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: checked
                ? Icon(Icons.check, size: 12, color: FluxForgeTheme.textPrimary)
                : null,
          ),
        ],
      ),
    );
  }
}

// ============ Interactive Inspector Widgets ============

/// Interactive dropdown for Inspector - connected to real data
class _InspectorDropdownInteractive extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _InspectorDropdownInteractive({
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: PopupMenuButton<String>(
              enabled: enabled,
              onSelected: onChanged,
              offset: const Offset(0, 24),
              color: FluxForgeTheme.bgElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
              itemBuilder: (context) => options.map((option) {
                final isSelected = option == value;
                return PopupMenuItem<String>(
                  value: option,
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      if (isSelected)
                        Icon(Icons.check, size: 12, color: FluxForgeTheme.accentOrange)
                      else
                        const SizedBox(width: 12),
                      const SizedBox(width: 8),
                      Text(
                        option,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? FluxForgeTheme.accentOrange : FluxForgeTheme.textPrimary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: enabled ? FluxForgeTheme.bgDeepest : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: enabled ? FluxForgeTheme.borderSubtle : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 11,
                          color: enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive slider for Inspector - uses local state during drag to prevent rebuild interruption
class _InspectorSliderInteractive extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;
  final double defaultValue;

  const _InspectorSliderInteractive({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.formatValue,
    required this.onChanged,
    this.defaultValue = 0.0,
  });

  @override
  State<_InspectorSliderInteractive> createState() => _InspectorSliderInteractiveState();
}

class _InspectorSliderInteractiveState extends State<_InspectorSliderInteractive> {
  bool _isDragging = false;
  double _localValue = 0.0;

  double get _displayValue => _isDragging ? _localValue : widget.value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: widget.enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                inactiveTrackColor: FluxForgeTheme.bgDeepest,
                thumbColor: widget.enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: GestureDetector(
                onDoubleTap: widget.enabled ? () {
                  setState(() {
                    _isDragging = false;
                    _localValue = widget.defaultValue;
                  });
                  widget.onChanged(widget.defaultValue);
                } : null,
                child: Slider(
                  value: _displayValue.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  onChanged: widget.enabled ? (v) {
                    setState(() {
                      _isDragging = true;
                      _localValue = v;
                    });
                    widget.onChanged(v);
                  } : null,
                  onChangeEnd: widget.enabled ? (v) {
                    setState(() {
                      _isDragging = false;
                    });
                    widget.onChanged(v);
                  } : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              widget.formatValue(_displayValue),
              style: TextStyle(
                fontSize: 10,
                color: widget.enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive checkbox for Inspector - connected to real data
class _InspectorCheckboxInteractive extends StatelessWidget {
  final String label;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _InspectorCheckboxInteractive({
    required this.label,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          GestureDetector(
            onTap: enabled ? () => onChanged(!checked) : null,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: checked
                    ? (enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary)
                    : FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: checked
                      ? (enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary)
                      : (enabled ? FluxForgeTheme.borderSubtle : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
                ),
              ),
              child: checked
                  ? Icon(Icons.check, size: 12, color: FluxForgeTheme.textPrimary)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive text field for Inspector - connected to real data
class _InspectorTextFieldInteractive extends StatefulWidget {
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _InspectorTextFieldInteractive({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_InspectorTextFieldInteractive> createState() => _InspectorTextFieldInteractiveState();
}

class _InspectorTextFieldInteractiveState extends State<_InspectorTextFieldInteractive> {
  late TextEditingController _controller;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_InspectorTextFieldInteractive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isFocused) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Focus(
              onFocusChange: (focused) {
                setState(() => _isFocused = focused);
                if (!focused) {
                  widget.onChanged(_controller.text);
                }
              },
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                style: TextStyle(
                  color: widget.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                  fontSize: 11,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  filled: true,
                  fillColor: FluxForgeTheme.bgDeepest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                  ),
                ),
                onSubmitted: widget.onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ Middleware Widgets ============

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 6 : 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: FluxForgeTheme.textPrimary),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarIconButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16, color: FluxForgeTheme.textSecondary),
        ),
      ),
    );
  }
}

class _ToolbarDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final Color accentColor;

  const _ToolbarDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 32),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      itemBuilder: (context) => options.map((option) {
        final isSelected = option == value;
        return PopupMenuItem<String>(
          value: option,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (isSelected)
                Icon(Icons.check, size: 14, color: accentColor)
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Text(
                option,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? accentColor : FluxForgeTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: accentColor),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
              const SizedBox(width: 4),
            ],
            Text(value, style: TextStyle(fontSize: 10, color: accentColor, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: accentColor),
          ],
        ),
      ),
    );
  }
}

class _MiniDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _MiniDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 28),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      itemBuilder: (context) => options.map((option) {
        final isSelected = option == value;
        return PopupMenuItem<String>(
          value: option,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            option,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 12, color: FluxForgeTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _MiniInput extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _MiniInput({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(fontSize: 10, color: FluxForgeTheme.accentCyan, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;

  const _MiniSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: FluxForgeTheme.accentCyan,
                inactiveTrackColor: FluxForgeTheme.borderSubtle,
                thumbColor: FluxForgeTheme.accentCyan,
                overlayColor: FluxForgeTheme.accentCyan.withAlpha(40),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              formatValue(value),
              style: TextStyle(fontSize: 9, color: FluxForgeTheme.accentCyan, fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _MiniToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2) : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.loop : Icons.trending_flat,
              size: 12,
              color: value ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: value ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Visually groups command bar controls with a subtle background
class _CommandGroup extends StatelessWidget {
  final List<Widget> children;
  const _CommandGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest.withAlpha(120),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Compact info chip (non-interactive)
class _CommandChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  const _CommandChip({required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
          ],
          Text(label, style: TextStyle(fontSize: 10, color: c)),
        ],
      ),
    );
  }
}

/// Compact icon button for command bar
class _CommandIconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  const _CommandIconBtn({required this.icon, required this.tooltip, this.onTap, this.color});

  @override
  State<_CommandIconBtn> createState() => _CommandIconBtnState();
}

class _CommandIconBtnState extends State<_CommandIconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.onTap != null ? (widget.color ?? FluxForgeTheme.textSecondary) : FluxForgeTheme.textTertiary;
    final c = _hovered && widget.onTap != null ? (widget.color ?? FluxForgeTheme.accentBlue) : baseColor;
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: _hovered && widget.onTap != null ? c.withAlpha(20) : Colors.transparent,
            ),
            child: Icon(widget.icon, size: 14, color: c),
          ),
        ),
      ),
    );
  }
}

/// Compact toggle for M/S/L buttons
class _CommandToggle extends StatefulWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final VoidCallback onTap;
  const _CommandToggle({required this.label, required this.value, required this.activeColor, required this.onTap});

  @override
  State<_CommandToggle> createState() => _CommandToggleState();
}

class _CommandToggleState extends State<_CommandToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.value ? widget.activeColor.withAlpha(50) : (_hovered ? widget.activeColor.withAlpha(20) : Colors.transparent),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: widget.value ? widget.activeColor : (_hovered ? widget.activeColor.withAlpha(120) : FluxForgeTheme.borderSubtle), width: widget.value ? 1.5 : 1),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: widget.value ? widget.activeColor : (_hovered ? widget.activeColor : FluxForgeTheme.textTertiary),
            ),
          ),
        ),
      ),
    );
  }
}


/// Compact parameter box: label above, clickable value tile, popup slider on tap.
/// Designed for single-row layer parameter display.
class _ParamBox extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color color;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final double width;
  final double defaultValue;
  final VoidCallback? onInteract;

  const _ParamBox({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.format,
    required this.onChanged,
    this.width = 38,
    this.defaultValue = 0,
    this.onInteract,
  });

  @override
  State<_ParamBox> createState() => _ParamBoxState();
}

class _ParamBoxState extends State<_ParamBox> {
  bool _editing = false;
  bool _hovered = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) {
        _commitEdit();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _textController.text = widget.format(widget.value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _textController.selection = TextSelection(baseOffset: 0, extentOffset: _textController.text.length);
    });
  }

  void _commitEdit() {
    final text = _textController.text.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final parsed = double.tryParse(text);
    if (parsed != null) {
      final isPan = widget.label == 'Pan' && widget.min == -1 && widget.max == 1;
      final value = isPan ? (parsed / 100.0) : parsed;
      widget.onChanged(value.clamp(widget.min, widget.max));
    }
    setState(() => _editing = false);
  }

  void _showSliderPopup(RenderBox box) {
    final overlay = Overlay.of(context);
    final pos = box.localToGlobal(Offset.zero);
    late OverlayEntry entry;
    double current = widget.value.clamp(widget.min, widget.max);
    final bool isVolume = widget.label == 'Vol' && widget.min == 0 && widget.max == 1;
    // Volume fader curve: slider position (0-1 linear) ↔ volume (0-1 logarithmic)
    // x² gives standard audio fader feel (more resolution at top)
    double volToSlider(double v) => math.sqrt(v.clamp(0.0, 1.0));
    double sliderToVol(double s) => s * s;

    entry = OverlayEntry(builder: (ctx) {
      return StatefulBuilder(builder: (ctx2, setPopup) {
        final double sliderVal = isVolume ? volToSlider(current) : current;
        return Stack(
          children: [
            Positioned.fill(child: GestureDetector(onTap: () => entry.remove(), behavior: HitTestBehavior.opaque, child: const SizedBox.expand())),
            Positioned(
              left: (pos.dx - 50).clamp(0, MediaQuery.of(ctx2).size.width - 200),
              top: pos.dy + box.size.height + 6,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 190,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A24),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.color.withAlpha(120), width: 1.2),
                    boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.label, style: TextStyle(fontSize: 11, color: widget.color, fontWeight: FontWeight.w700)),
                          Text(widget.format(current), style: TextStyle(fontSize: 12, color: widget.color, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 24,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: widget.color,
                            inactiveTrackColor: FluxForgeTheme.borderSubtle,
                            thumbColor: widget.color,
                            overlayColor: widget.color.withAlpha(30),
                          ),
                          child: GestureDetector(
                            onDoubleTap: () {
                              setPopup(() => current = widget.defaultValue);
                              widget.onChanged(widget.defaultValue);
                            },
                            child: Slider(
                              value: sliderVal,
                              min: isVolume ? 0.0 : widget.min,
                              max: isVolume ? 1.0 : widget.max,
                              onChanged: (v) {
                                final actual = isVolume ? sliderToVol(v) : v;
                                setPopup(() => current = actual);
                                widget.onChanged(actual);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      });
    });
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(widget.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: _hovered ? widget.color : FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600, height: 1)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () {
              widget.onInteract?.call();
              if (_editing) return;
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) _showSliderPopup(box);
            },
            onDoubleTap: () {
              widget.onInteract?.call();
              if (!_editing) _startEditing();
            },
            child: Container(
              constraints: BoxConstraints(minWidth: widget.width),
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hovered ? widget.color.withAlpha(15) : FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _hovered ? widget.color.withAlpha(140) : widget.color.withAlpha(70), width: 0.8),
              ),
              child: _editing
                ? EditableText(
                    controller: _textController,
                    focusNode: _focusNode,
                    style: TextStyle(fontSize: 10, color: widget.color, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    cursorColor: widget.color,
                    backgroundCursorColor: Colors.transparent,
                    selectionColor: widget.color.withAlpha(80),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onSubmitted: (_) => _commitEdit(),
                  )
                : Text(
                    widget.format(widget.value),
                    style: TextStyle(fontSize: 10, color: widget.color, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                    overflow: TextOverflow.clip,
                    maxLines: 1,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerToggle extends StatefulWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final VoidCallback onTap;
  final VoidCallback? onInteract;
  const _LayerToggle({required this.label, required this.value, required this.activeColor, required this.onTap, this.onInteract});

  @override
  State<_LayerToggle> createState() => _LayerToggleState();
}

class _LayerToggleState extends State<_LayerToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.value ? widget.activeColor : widget.activeColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () { widget.onInteract?.call(); widget.onTap(); },
        child: Container(
          width: 22,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.value ? widget.activeColor.withAlpha(50) : (_hovered ? hoverColor.withAlpha(20) : Colors.transparent),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: widget.value ? widget.activeColor : (_hovered ? hoverColor.withAlpha(120) : FluxForgeTheme.borderSubtle), width: widget.value ? 1.5 : 1),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: widget.value ? widget.activeColor : (_hovered ? hoverColor : FluxForgeTheme.textTertiary),
            ),
          ),
        ),
      ),
    );
  }
}

class _CellDropdown extends StatefulWidget {
  final String value;
  final List<String> options;
  final Color? color;
  final ValueChanged<String> onChanged;
  final VoidCallback? onInteract;

  const _CellDropdown({
    required this.value,
    required this.options,
    this.color,
    required this.onChanged,
    this.onInteract,
  });

  @override
  State<_CellDropdown> createState() => _CellDropdownState();
}

class _CellDropdownState extends State<_CellDropdown> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.color ?? FluxForgeTheme.accentBlue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<String>(
        onOpened: () => widget.onInteract?.call(),
        onSelected: widget.onChanged,
        offset: const Offset(0, 24),
        color: FluxForgeTheme.bgElevated,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
        itemBuilder: (context) => widget.options.map((option) {
          final isSelected = option == widget.value;
          final displayText = option.isEmpty ? '(none)' : option;
          return PopupMenuItem<String>(
            value: option,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? accentColor
                    : (option.isEmpty ? FluxForgeTheme.textTertiary : FluxForgeTheme.textPrimary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontStyle: option.isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: _hovered ? accentColor.withAlpha(15) : FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: _hovered ? accentColor.withAlpha(120) : FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.value.isEmpty ? '(select)' : widget.value,
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.value.isEmpty
                        ? FluxForgeTheme.textTertiary
                        : (_hovered ? accentColor : (widget.color ?? FluxForgeTheme.textPrimary)),
                    fontStyle: widget.value.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 12, color: _hovered ? accentColor : FluxForgeTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// NOTE: _ActionsTable, _TableHeader, _TableCell, _TableCellDropdown removed - unused legacy widgets

/// Compact inline text field for table cells
class _CellTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  const _CellTextField({
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  State<_CellTextField> createState() => _CellTextFieldState();
}

class _CellTextFieldState extends State<_CellTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
      if (!_focusNode.hasFocus && _controller.text != widget.value) {
        widget.onChanged(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(_CellTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasFocus && oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _hasFocus ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: widget.hint,
          hintStyle: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5)),
        ),
        onSubmitted: (val) => widget.onChanged(val),
      ),
    );
  }
}

/// Compact inline number field for table cells
class _CellNumberField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final double min;
  final double max;
  final int decimals;

  const _CellNumberField({
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min = 0,
    this.max = 9999,
    this.decimals = 0,
  });

  @override
  State<_CellNumberField> createState() => _CellNumberFieldState();
}

class _CellNumberFieldState extends State<_CellNumberField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
      if (!_focusNode.hasFocus) {
        _commitValue();
      }
    });
  }

  String _formatValue(double val) {
    if (widget.decimals == 0) {
      return val.round().toString();
    }
    return val.toStringAsFixed(widget.decimals);
  }

  void _commitValue() {
    final parsed = double.tryParse(_controller.text);
    if (parsed != null) {
      final clamped = parsed.clamp(widget.min, widget.max);
      if (clamped != widget.value) {
        widget.onChanged(clamped);
      }
    }
    _controller.text = _formatValue(widget.value);
  }

  @override
  void didUpdateWidget(_CellNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasFocus && oldWidget.value != widget.value) {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _hasFocus ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _commitValue(),
            ),
          ),
          if (widget.suffix != null)
            Text(
              widget.suffix!,
              style: TextStyle(fontSize: 9, color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7)),
            ),
        ],
      ),
    );
  }
}

/// Compact inline slider for table cells
class _CellSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;
  final Color? color;

  const _CellSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
    this.color,
  });

  @override
  State<_CellSlider> createState() => _CellSliderState();
}

class _CellSliderState extends State<_CellSlider> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(_CellSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _currentValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.color ?? FluxForgeTheme.accentOrange;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Show popup slider for precise control — avoids horizontal drag conflicts
        _showSliderPopup(context, effectiveColor);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini progress bar
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ((_currentValue - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: effectiveColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Value text
            Text(
              widget.formatValue(_currentValue),
              style: TextStyle(
                fontSize: 9,
                color: effectiveColor,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSliderPopup(BuildContext context, Color color) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: position.dx - 20,
            top: position.dy - 40,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 140,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: StatefulBuilder(
                  builder: (context, setPopupState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.formatValue(_currentValue),
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: color,
                            inactiveTrackColor: FluxForgeTheme.bgDeepest,
                            thumbColor: color,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: _currentValue.clamp(widget.min, widget.max),
                            min: widget.min,
                            max: widget.max,
                            onChanged: (v) {
                              setState(() => _currentValue = v);
                              setPopupState(() {});
                            },
                            onChangeEnd: (v) {
                              widget.onChanged(v);
                              Navigator.of(ctx).pop();
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings row for project settings dialog
class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;

  const _SettingsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 13)),
          Text(value, style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Insert menu option for existing plugin context menu
class _InsertMenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _InsertMenuOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color ?? FluxForgeTheme.textSecondary),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: color ?? FluxForgeTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Audio Editor Dialog with local state management
class _AudioEditorDialog extends StatefulWidget {
  final timeline.TimelineClip initialClip;
  final void Function(timeline.TimelineClip) onClipChanged;
  final int Function(FadeCurve) curveToInt;

  const _AudioEditorDialog({
    required this.initialClip,
    required this.onClipChanged,
    required this.curveToInt,
  });

  @override
  State<_AudioEditorDialog> createState() => _AudioEditorDialogState();
}

class _AudioEditorDialogState extends State<_AudioEditorDialog> {
  late timeline.TimelineClip _clip;
  double _zoom = 100;
  double _scrollOffset = 0;
  bool _initialZoomSet = false;

  @override
  void initState() {
    super.initState();
    _clip = widget.initialClip;
  }

  void _updateClip(timeline.TimelineClip newClip) {
    setState(() {
      _clip = newClip;
    });
    widget.onClipChanged(newClip);
  }

  @override
  Widget build(BuildContext context) {
    // Calculate dialog dimensions
    final dialogWidth = MediaQuery.of(context).size.width * 0.9;
    final dialogHeight = MediaQuery.of(context).size.height * 0.8;

    // Waveform area width (dialog - sidebar - padding)
    // Sidebar is 200px, plus some padding
    final waveformWidth = dialogWidth - 200 - 32;

    // Calculate zoom to fit entire clip duration
    // Only set initial zoom once
    if (!_initialZoomSet && _clip.duration > 0 && waveformWidth > 0) {
      _zoom = waveformWidth / _clip.duration;
      _scrollOffset = 0;
      _initialZoomSet = true;
    }

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: clip_editor.ClipEditor(
          clip: clip_editor.ClipEditorClip(
            id: _clip.id,
            name: _clip.name,
            duration: _clip.duration,
            sampleRate: 48000,
            channels: 2,
            bitDepth: 24,
            fadeIn: _clip.fadeIn,
            fadeOut: _clip.fadeOut,
            fadeInCurve: _clip.fadeInCurve,
            fadeOutCurve: _clip.fadeOutCurve,
            gain: _clip.gain,
            color: _clip.color,
            sourceOffset: _clip.sourceOffset,
            sourceDuration: _clip.sourceDuration ?? _clip.duration,
            waveform: _clip.waveform,
          ),
          zoom: _zoom,
          scrollOffset: _scrollOffset,
          onZoomChange: (zoom) => setState(() => _zoom = zoom),
          onScrollChange: (offset) => setState(() => _scrollOffset = offset),
          onFadeInChange: (id, fadeIn) {
            EngineApi.instance.fadeInClip(id, fadeIn, curveType: widget.curveToInt(_clip.fadeInCurve));
            _updateClip(_clip.copyWith(fadeIn: fadeIn));
          },
          onFadeOutChange: (id, fadeOut) {
            EngineApi.instance.fadeOutClip(id, fadeOut, curveType: widget.curveToInt(_clip.fadeOutCurve));
            _updateClip(_clip.copyWith(fadeOut: fadeOut));
          },
          onFadeInCurveChange: (id, curve) {
            EngineApi.instance.fadeInClip(id, _clip.fadeIn, curveType: widget.curveToInt(curve));
            _updateClip(_clip.copyWith(fadeInCurve: curve));
          },
          onFadeOutCurveChange: (id, curve) {
            EngineApi.instance.fadeOutClip(id, _clip.fadeOut, curveType: widget.curveToInt(curve));
            _updateClip(_clip.copyWith(fadeOutCurve: curve));
          },
          onGainChange: (id, gain) {
            EngineApi.instance.setClipGain(id, gain);
            _updateClip(_clip.copyWith(gain: gain));
          },
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SHORTCUT INTENTS
// ════════════════════════════════════════════════════════════════════════════

/// Intent for importing audio files (Shift+Cmd+I)
class _ImportAudioIntent extends Intent {
  const _ImportAudioIntent();
}

/// Dropdown row for dialogs
class _DialogDropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _DialogDropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure value is in options, fallback to first option if not
    final effectiveValue = options.contains(value) ? value : options.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: DropdownButton<String>(
            value: effectiveValue,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: FluxForgeTheme.bgElevated,
            style: TextStyle(fontSize: 12, color: FluxForgeTheme.textPrimary),
            items: options.map((o) => DropdownMenuItem(
              value: o,
              child: Text(
                o.isEmpty ? '(none)' : o,
                style: TextStyle(
                  color: o.isEmpty ? FluxForgeTheme.textTertiary : FluxForgeTheme.textPrimary,
                  fontStyle: o.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            )).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// MIDDLEWARE TIMELINE PAINTERS
// =============================================================================

/// Time ruler painter for middleware timeline
class _MiddlewareTimeRulerPainter extends CustomPainter {
  final double duration;
  final double zoom;
  final double pixelsPerSecond;

  _MiddlewareTimeRulerPainter({
    required this.duration,
    required this.zoom,
    required this.pixelsPerSecond,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      fontSize: 9,
      color: FluxForgeTheme.textSecondary,
    );

    final scaledPixelsPerSecond = pixelsPerSecond * zoom;

    // Determine tick interval based on zoom
    double majorInterval = 1.0; // 1 second
    if (zoom < 0.5) majorInterval = 2.0;
    if (zoom < 0.25) majorInterval = 5.0;
    if (zoom > 2.0) majorInterval = 0.5;
    if (zoom > 3.0) majorInterval = 0.25;

    // Draw ticks
    for (double t = 0; t <= duration; t += majorInterval / 4) {
      final x = t * scaledPixelsPerSecond;
      final isMajor = (t % majorInterval).abs() < 0.001;
      final isMinor = (t % (majorInterval / 2)).abs() < 0.001;

      if (isMajor) {
        // Major tick with time label
        canvas.drawLine(Offset(x, size.height - 12), Offset(x, size.height), paint);

        final textSpan = TextSpan(text: _formatTime(t), style: textStyle);
        final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 3, 2));
      } else if (isMinor) {
        // Minor tick
        canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paint..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.5));
      } else {
        // Sub-tick
        canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), paint..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3));
      }
    }

    // Draw bottom line
    paint.color = FluxForgeTheme.borderSubtle;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), paint);
  }

  String _formatTime(double seconds) {
    if (seconds < 1) {
      return '${(seconds * 1000).round()}ms';
    }
    final secs = seconds.floor();
    final ms = ((seconds - secs) * 100).round();
    if (ms > 0) {
      return '${secs}.${ms.toString().padLeft(2, '0')}s';
    }
    return '${secs}s';
  }

  @override
  bool shouldRepaint(covariant _MiddlewareTimeRulerPainter oldDelegate) {
    return duration != oldDelegate.duration ||
        zoom != oldDelegate.zoom ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond;
  }
}

/// Grid painter for middleware timeline
class _MiddlewareTimelineGridPainter extends CustomPainter {
  final double zoom;
  final double pixelsPerSecond;
  final double trackHeight;
  final int trackCount;

  _MiddlewareTimelineGridPainter({
    required this.zoom,
    required this.pixelsPerSecond,
    required this.trackHeight,
    required this.trackCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1;

    final scaledPixelsPerSecond = pixelsPerSecond * zoom;

    // Determine grid interval based on zoom
    double gridInterval = 1.0; // 1 second
    if (zoom < 0.5) gridInterval = 2.0;
    if (zoom < 0.25) gridInterval = 5.0;
    if (zoom > 2.0) gridInterval = 0.5;
    if (zoom > 3.0) gridInterval = 0.25;

    // Draw vertical grid lines (time)
    final totalSeconds = size.width / scaledPixelsPerSecond;
    for (double t = 0; t <= totalSeconds; t += gridInterval / 2) {
      final x = t * scaledPixelsPerSecond;
      final isMajor = (t % gridInterval).abs() < 0.001;

      paint.color = isMajor
          ? FluxForgeTheme.borderSubtle.withValues(alpha: 0.4)
          : FluxForgeTheme.borderSubtle.withValues(alpha: 0.15);

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal grid lines (tracks)
    for (int i = 0; i <= trackCount; i++) {
      final y = i * trackHeight;
      paint.color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw alternating track backgrounds
    for (int i = 0; i < trackCount; i++) {
      if (i % 2 == 1) {
        final rect = Rect.fromLTWH(0, i * trackHeight, size.width, trackHeight);
        canvas.drawRect(rect, Paint()..color = FluxForgeTheme.bgMid.withValues(alpha: 0.3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiddlewareTimelineGridPainter oldDelegate) {
    return zoom != oldDelegate.zoom ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        trackHeight != oldDelegate.trackHeight ||
        trackCount != oldDelegate.trackCount;
  }
}
