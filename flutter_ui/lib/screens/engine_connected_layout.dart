// Engine Connected Layout
//
// Connects MainLayout to the Rust EngineProvider.
// Bridges UI callbacks to engine API calls.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/native_file_picker.dart';

import '../providers/engine_provider.dart';
import '../providers/global_shortcuts_provider.dart';
import '../providers/meter_provider.dart';
import '../providers/mixer_provider.dart';
import '../providers/recording_provider.dart';
import '../models/layout_models.dart';
import '../models/editor_mode_config.dart';
import '../models/middleware_models.dart';
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
import '../widgets/meters/advanced_metering_panel.dart';
import '../widgets/eq/pultec_eq.dart';
import '../widgets/eq/api550_eq.dart';
import '../widgets/debug/debug_console.dart';
import '../widgets/eq/neve1073_eq.dart';
import '../widgets/common/context_menu.dart';
import '../widgets/editor/clip_editor.dart' as clip_editor;
import '../widgets/editors/crossfade_editor.dart';
import '../widgets/timeline/automation_lane.dart';
import '../widgets/dsp/time_stretch_panel.dart';
import '../widgets/dsp/delay_panel.dart';
import '../widgets/dsp/reverb_panel.dart';
import '../widgets/dsp/dynamics_panel.dart';
import '../widgets/dsp/spatial_panel.dart';
import '../widgets/dsp/spectral_panel.dart';
import '../widgets/dsp/pitch_correction_panel.dart';
import '../widgets/dsp/transient_panel.dart';
import '../widgets/dsp/multiband_panel.dart';
import '../widgets/dsp/saturation_panel.dart';
import '../widgets/dsp/analog_eq_panel.dart';
import '../widgets/dsp/sidechain_panel.dart';
import '../widgets/dsp/wavelet_panel.dart';
import '../widgets/dsp/channel_strip_panel.dart';
import '../widgets/dsp/surround_panner_panel.dart';
import '../widgets/dsp/linear_phase_eq_panel.dart';
import '../widgets/dsp/stereo_eq_panel.dart';
import '../widgets/dsp/pro_eq_panel.dart';
import '../widgets/dsp/ultra_eq_panel.dart';
import '../widgets/dsp/room_correction_panel.dart';
import '../widgets/dsp/stereo_imager_panel.dart';
import '../widgets/dsp/convolution_ultra_panel.dart';
import '../widgets/dsp/gpu_settings_panel.dart';
import '../widgets/dsp/ml_processor_panel.dart';
import '../widgets/dsp/mastering_panel.dart';
import '../widgets/dsp/restoration_panel.dart';
import '../widgets/midi/piano_roll_widget.dart';
import '../widgets/mixer/ultimate_mixer.dart' as ultimate;
import '../widgets/mixer/control_room_panel.dart' as control_room;
import '../widgets/input_bus/input_bus_panel.dart' as input_bus;
import '../widgets/recording/recording_panel.dart' as recording;
import '../widgets/routing/routing_panel.dart' as routing;
import '../widgets/plugin/plugin_browser.dart';
import '../widgets/metering/metering_bridge.dart';
import '../widgets/meters/pdc_display.dart';
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
// Advanced panel imports
import '../widgets/panels/logical_editor_panel.dart';
import '../widgets/panels/scale_assistant_panel.dart';
import '../widgets/panels/groove_quantize_panel.dart';
import '../widgets/panels/audio_alignment_panel.dart';
import '../widgets/panels/track_versions_panel.dart';
import '../widgets/panels/macro_controls_panel.dart';
import '../widgets/panels/clip_gain_envelope_panel.dart';
import '../widgets/demo/liquid_glass_demo.dart';

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

  const EngineConnectedLayout({
    super.key,
    this.projectName,
  });

  @override
  State<EngineConnectedLayout> createState() => _EngineConnectedLayoutState();
}

class _EngineConnectedLayoutState extends State<EngineConnectedLayout> {
  // Debug console state
  bool _showDebugConsole = false;

  // Zone state
  bool _leftVisible = true;
  bool _rightVisible = true;
  bool _lowerVisible = true;
  late String _activeLowerTab;
  LeftZoneTab _activeLeftTab = LeftZoneTab.project;

  // Local UI state
  EditorMode _editorMode = EditorMode.daw; // DAW default
  TimeDisplayMode _timeDisplayMode = TimeDisplayMode.bars;
  bool _metronomeEnabled = false;
  bool _snapEnabled = true;
  double _snapValue = 1;

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
  bool _middlewareGridView = false; // false = list view, true = grid view

  // Current action being edited (header controls)
  String _headerActionType = 'Play';
  String _headerAssetId = 'music_main';
  String _headerBus = 'Music';
  String _headerScope = 'Global';
  String _headerPriority = 'Normal';
  String _headerFadeCurve = 'Linear';
  double _headerFadeTime = 0.1;
  double _headerGain = 1.0;
  bool _headerLoop = false;

  // Loudness meter state
  LoudnessTarget _loudnessTarget = LoudnessTarget.streaming;

  // Selected track for Channel tab (DAW mode)
  String? _selectedTrackId;

  // Meter decay state - Cubase-style: meters decay to 0 when playback stops
  bool _wasPlaying = false;
  Timer? _meterDecayTimer;
  double _decayMasterL = 0.0;
  double _decayMasterR = 0.0;
  double _decayMasterPeak = 0.0;

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
  List<ProjectTreeNode> _buildProjectTree() {
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

      // MixConsole (Buses) - always 5 buses
      tree.add(const ProjectTreeNode(
        id: 'mixconsole',
        type: TreeItemType.folder,
        label: 'MixConsole',
        count: 5,
        children: [
          ProjectTreeNode(id: 'bus-master', type: TreeItemType.bus, label: 'Master'),
          ProjectTreeNode(id: 'bus-sfx', type: TreeItemType.bus, label: 'SFX'),
          ProjectTreeNode(id: 'bus-music', type: TreeItemType.bus, label: 'Music'),
          ProjectTreeNode(id: 'bus-voice', type: TreeItemType.bus, label: 'Voice'),
          ProjectTreeNode(id: 'bus-ui', type: TreeItemType.bus, label: 'UI'),
        ],
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

      // Events folder - from imported JSON routes (starts empty or from routes)
      tree.add(ProjectTreeNode(
        id: 'events',
        type: TreeItemType.folder,
        label: 'Events',
        count: _routeEvents.length,
        children: _routeEvents
            .map((name) => ProjectTreeNode(
                  id: 'evt-$name',
                  type: TreeItemType.event,
                  label: name,
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

    // Set default tab based on initial mode
    _activeLowerTab = getDefaultTabForMode(_editorMode);

    // Initialize empty timeline (no demo data)
    _initEmptyTimeline();

    // Initialize demo middleware data (for Middleware tab only)
    _initDemoMiddlewareData();

    // Register meters and setup shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final meters = context.read<MeterProvider>();
      meters.registerMeter('master');
      meters.registerMeter('sfx');
      meters.registerMeter('music');
      meters.registerMeter('voice');

      // Wire up import audio shortcut
      final shortcuts = context.read<GlobalShortcutsProvider>();
      shortcuts.actions.onImportAudioFiles = _openFilePicker;
      shortcuts.actions.onExport = _handleExportAudio;

      // Wire up Advanced panel shortcuts (Shift+Cmd)
      shortcuts.actions.onShowLogicalEditor = () => _showAdvancedPanel('logical-editor');
      shortcuts.actions.onShowScaleAssistant = () => _showAdvancedPanel('scale-assistant');
      shortcuts.actions.onShowGrooveQuantize = () => _showAdvancedPanel('groove-quantize');
      shortcuts.actions.onShowAudioAlignment = () => _showAdvancedPanel('audio-alignment');
      shortcuts.actions.onShowTrackVersions = () => _showAdvancedPanel('track-versions');
      shortcuts.actions.onShowMacroControls = () => _showAdvancedPanel('macro-controls');
      shortcuts.actions.onShowClipGainEnvelope = () => _showAdvancedPanel('clip-gain-envelope');
    });
  }

  @override
  void dispose() {
    _meterDecayTimer?.cancel();
    super.dispose();
  }

  /// Start meter decay animation when playback stops
  void _startMeterDecay() {
    _meterDecayTimer?.cancel();
    _meterDecayTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      // Decay factor: 0.85 gives smooth ~300ms decay
      const decay = 0.85;
      setState(() {
        _decayMasterL *= decay;
        _decayMasterR *= decay;
        _decayMasterPeak *= decay;
      });
      // Stop when meters reach near-zero
      if (_decayMasterL < 0.001 && _decayMasterR < 0.001) {
        _meterDecayTimer?.cancel();
        _meterDecayTimer = null;
        setState(() {
          _decayMasterL = 0;
          _decayMasterR = 0;
          _decayMasterPeak = 0;
        });
      }
    });
  }

  void _initEmptyTimeline() {
    // Start with empty tracks - user will add tracks and import audio
    _tracks = [];
    _clips = [];
    _markers = [];
    _crossfades = [];
    _loopRegion = const timeline.LoopRegion(start: 0.0, end: 8.0);
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

    setState(() {
      _tracks = _tracks.where((t) => t.id != trackId).toList();
      _clips = _clips.where((c) => c.trackId != trackId).toList();
    });
  }

  /// Delete track by ID (alias for timeline callback)
  void _handleDeleteTrackById(String trackId) => _handleDeleteTrack(trackId);

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

  /// Handle double-click on pool item - creates NEW track with audio file
  void _handlePoolItemDoubleClick(String id, TreeItemType type, dynamic data) {
    debugPrint('[UI] Pool item double-clicked: $id, type: $type');

    // Check if it's a pool audio file
    if (id.startsWith('pool-') && data is timeline.PoolAudioFile) {
      // ALWAYS create NEW track on double-click (Cubase behavior)
      _addPoolFileToNewTrack(data);
    }
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

    debugPrint('[UI] Added ${poolFile.name} to track ${track.name} at $insertTime');
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

    debugPrint('[UI] Created new track "$trackName" with ${poolFile.name} at $startTime (channels: $channelCount)');
    _showSnackBar('Created track "$trackName" with ${poolFile.name}');
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

    // Get waveform peaks (will use demo waveform if empty)
    final peaks = await engine.getWaveformPeaks(clipId: clipInfo.clipId);
    final waveform = peaks.isNotEmpty
        ? Float32List.fromList(peaks.map((v) => v.toDouble()).toList().cast<double>())
        : timeline.generateDemoWaveform();

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
    debugPrint('[UI] Opened project: $path');
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
    debugPrint('[Timeline] Selected all ${_clips.length} clips');
  }

  /// Deselect All (Escape)
  void _handleDeselectAll() {
    setState(() {
      _clips = _clips.map((c) => c.copyWith(selected: false)).toList();
    });
    debugPrint('[Timeline] Deselected all clips');
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
    debugPrint('[UI] Opening folder picker...');

    final result = await NativeFilePicker.pickAudioFolder();

    debugPrint('[UI] Folder picker result: $result');

    if (result == null) {
      debugPrint('[UI] No folder selected');
      return;
    }

    // Scan folder for audio files
    final audioExtensions = ['wav', 'mp3', 'flac', 'ogg', 'aiff', 'aif', 'm4a'];
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
      debugPrint('[UI] Error scanning folder: $e');
      _showSnackBar('Error scanning folder: $e');
      return;
    }

    if (audioFiles.isEmpty) {
      _showSnackBar('No audio files found in folder');
      return;
    }

    debugPrint('[UI] Found ${audioFiles.length} audio files');

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

    // Generate demo waveform
    final waveform = timeline.generateDemoWaveform(samples: 2000);

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
      );

      setState(() {
        _clips.add(newClip);
      });

      _showSnackBar('Added "${file.name}" to timeline');
    } catch (e) {
      _showSnackBar('Error loading audio file: $e');
      debugPrint('[AudioPool] Error loading file: $e');
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
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: FluxForgeTheme.bgElevated,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Open file picker dialog to import audio files to Pool
  Future<void> _openFilePicker() async {
    debugPrint('[UI] Opening file picker...');

    final paths = await NativeFilePicker.pickAudioFiles();

    debugPrint('[UI] File picker result: ${paths.length} files');

    if (paths.isEmpty) {
      debugPrint('[UI] No files selected');
      return;
    }

    // Import files to Pool (not timeline)
    for (final path in paths) {
      await _addFileToPool(path);
    }

    _showSnackBar('Added ${paths.length} file(s) to Pool');
  }

  /// Add a file to the Audio Pool
  Future<void> _addFileToPool(String filePath) async {
    debugPrint('[UI] Adding to pool: $filePath');

    final fileName = filePath.split('/').last;
    final ext = fileName.split('.').last.toLowerCase();
    final fileId = 'pool-${DateTime.now().millisecondsSinceEpoch}-${_audioPool.length}';

    // Get actual audio metadata from engine (reads header only, very fast)
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
        debugPrint('[UI] Audio metadata: duration=$duration, sampleRate=$sampleRate, channels=$channels');
      } catch (e) {
        debugPrint('[UI] Failed to parse audio metadata: $e');
      }
    }

    // Generate demo waveform (real waveform would come from engine)
    final waveform = timeline.generateDemoWaveform();

    setState(() {
      _audioPool.add(timeline.PoolAudioFile(
        id: fileId,
        path: filePath,
        name: fileName,
        duration: duration,
        sampleRate: sampleRate,
        channels: channels,
        format: ext,
        waveform: waveform,
        importedAt: DateTime.now(),
        defaultBus: timeline.OutputBus.master,
      ));
    });

    debugPrint('[UI] Added to pool: $fileName (${_audioPool.length} files total)');
  }

  void _initDemoMiddlewareData() {
    // Create demo events with actions
    _middlewareEvents = [
      MiddlewareEvent(
        id: 'evt-play-music',
        name: 'Play_Music',
        category: 'Music',
        actions: [
          const MiddlewareAction(
            id: 'act-1',
            type: ActionType.play,
            assetId: 'music_main',
            bus: 'Music',
            fadeTime: 0.5,
            loop: true,
          ),
        ],
      ),
      MiddlewareEvent(
        id: 'evt-stop-music',
        name: 'Stop_Music',
        category: 'Music',
        actions: [
          const MiddlewareAction(
            id: 'act-2',
            type: ActionType.stop,
            assetId: 'music_main',
            bus: 'Music',
            fadeTime: 1.0,
          ),
        ],
      ),
      MiddlewareEvent(
        id: 'evt-bigwin',
        name: 'BigWin_Start',
        category: 'Wins',
        actions: [
          const MiddlewareAction(
            id: 'act-3',
            type: ActionType.setVolume,
            bus: 'Music',
            gain: 0.3,
            fadeTime: 0.2,
          ),
          const MiddlewareAction(
            id: 'act-4',
            type: ActionType.play,
            assetId: 'sfx_jackpot',
            bus: 'Wins',
            priority: ActionPriority.high,
          ),
          const MiddlewareAction(
            id: 'act-5',
            type: ActionType.play,
            assetId: 'vo_bigwin',
            bus: 'VO',
            delay: 0.5,
          ),
        ],
      ),
      MiddlewareEvent(
        id: 'evt-spin-start',
        name: 'Spin_Start',
        category: 'Gameplay',
        actions: [
          const MiddlewareAction(
            id: 'act-6',
            type: ActionType.play,
            assetId: 'sfx_spin',
            bus: 'SFX',
          ),
        ],
      ),
      MiddlewareEvent(
        id: 'evt-ui-click',
        name: 'UI_Click',
        category: 'UI',
        actions: [
          const MiddlewareAction(
            id: 'act-7',
            type: ActionType.play,
            assetId: 'sfx_click',
            bus: 'UI',
            scope: ActionScope.gameObject,
          ),
        ],
      ),
    ];

    // Set default selected event
    if (_middlewareEvents.isNotEmpty) {
      _selectedEventId = _middlewareEvents.first.id;
      _routeEvents = _middlewareEvents.map((e) => e.name).toList();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIDDLEWARE CRUD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  MiddlewareEvent? get _selectedEvent {
    if (_selectedEventId.isEmpty) return null;
    return _middlewareEvents.cast<MiddlewareEvent?>().firstWhere(
      (e) => e?.id == _selectedEventId,
      orElse: () => null,
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
      loop: _headerLoop,
    );

    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == _selectedEventId) {
          return e.copyWith(actions: [...e.actions, newAction]);
        }
        return e;
      }).toList();
      _selectedActionIndex = _selectedEvent!.actions.length; // Select new action
    });
  }

  void _deleteAction(int index) {
    if (_selectedEvent == null) return;

    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == _selectedEventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          newActions.removeAt(index);
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();
      _selectedActionIndex = -1;
    });
  }

  void _duplicateAction(int index) {
    if (_selectedEvent == null || index < 0 || index >= _selectedEvent!.actions.length) return;

    final original = _selectedEvent!.actions[index];
    final duplicate = original.copyWith(
      id: 'act-${DateTime.now().millisecondsSinceEpoch}',
    );

    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == _selectedEventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          newActions.insert(index + 1, duplicate);
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();
      _selectedActionIndex = index + 1;
    });
  }

  void _updateAction(int index, MiddlewareAction updated) {
    if (_selectedEvent == null) return;

    setState(() {
      _middlewareEvents = _middlewareEvents.map((e) {
        if (e.id == _selectedEventId) {
          final newActions = List<MiddlewareAction>.from(e.actions);
          newActions[index] = updated;
          return e.copyWith(actions: newActions);
        }
        return e;
      }).toList();
    });
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
        _headerLoop = action.loop;
      }
    });
  }

  void _previewEvent() {
    if (_selectedEvent == null) return;
    // TODO: Connect to engine - for now just print
    debugPrint('Preview event: ${_selectedEvent!.name}');
    debugPrint('Actions: ${_selectedEvent!.actions.map((a) => a.type.displayName).join(', ')}');
  }

  void _exportEventsToJson() async {
    final json = jsonEncode({
      'version': '1.0',
      'events': _middlewareEvents.map((e) => e.toJson()).toList(),
    });

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: json));
    debugPrint('Events exported to clipboard');
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
      debugPrint('Imported ${events.length} events from clipboard');
    } catch (e) {
      debugPrint('Import failed: $e');
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
    // PERFORMANCE: No Consumer wrapper - prevents entire layout rebuild on every engine update
    // Use context.read() for callbacks and Selector for reactive parts only

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Shift+Cmd+I - Import Audio Files
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true, shift: true): const _ImportAudioIntent(),
        // Also support Ctrl+Shift+I for non-Mac
        const SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true): const _ImportAudioIntent(),
        // Ctrl+Shift+D toggles debug console
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true): const _ToggleDebugIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true): const _ToggleDebugIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ImportAudioIntent: CallbackAction<_ImportAudioIntent>(
            onInvoke: (_) {
              _openFilePicker();
              return null;
            },
          ),
          _ToggleDebugIntent: CallbackAction<_ToggleDebugIntent>(
            onInvoke: (_) {
              setState(() => _showDebugConsole = !_showDebugConsole);
              return null;
            },
          ),
        },
        child: FocusScope(
          autofocus: true,
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            child: Stack(
        children: [
          MainLayout(
            // PERFORMANCE: Use custom control bar that handles its own provider listening
            // This isolates control bar rebuilds from the rest of the layout
            customControlBar: EngineConnectedControlBar(
              editorMode: _editorMode,
              onEditorModeChange: (mode) => setState(() {
                _editorMode = mode;
                _activeLowerTab = getDefaultTabForMode(mode);
                _activeLeftTab = LeftZoneTab.project;
              }),
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
              onSnapToggle: () => setState(() => _snapEnabled = !_snapEnabled),
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
            ),

            // These props are no longer used when customControlBar is provided
            // but we keep minimal values for compatibility
            editorMode: _editorMode,

            // Left zone - mode-aware tree
            projectTree: _buildProjectTree(),
            activeLeftTab: _activeLeftTab,
            onLeftTabChange: (tab) => setState(() => _activeLeftTab = tab),
            onProjectDoubleClick: _handlePoolItemDoubleClick,

            // Channel tab data (DAW mode)
            channelData: _getSelectedChannelData(),
            onChannelVolumeChange: (channelId, volume) {
              final mixerProvider = context.read<MixerProvider>();
              // dB to linear: linear = 10^(dB/20)
              final linear = volume <= -60 ? 0.0 : math.pow(10.0, volume / 20.0).toDouble().clamp(0.0, 1.5);
              mixerProvider.setVolume(channelId, linear);
            },
            onChannelPanChange: (channelId, pan) {
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.setChannelPan(channelId, pan);
            },
            onChannelPanRightChange: (channelId, pan) {
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.setChannelPanRight(channelId, pan);
            },
            onChannelMuteToggle: (channelId) {
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.toggleMute(channelId);
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
            },
            onChannelSoloToggle: (channelId) {
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.toggleSolo(channelId);
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
            onChannelSendClick: (channelId, sendIndex) {
              _onSendClick(channelId, sendIndex);
            },
            onChannelInsertBypassToggle: (channelId, slotIndex, bypassed) {
              // Extract track ID from channel ID (format: "ch_1", "ch_2", etc.)
              final trackId = int.tryParse(channelId.replaceFirst('ch_', '')) ?? 0;
              NativeFFI.instance.insertSetBypass(trackId, slotIndex, bypassed);
              // Update local state
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.updateInsertBypass(channelId, slotIndex, bypassed);
            },
            onChannelInsertWetDryChange: (channelId, slotIndex, wetDry) {
              final trackId = int.tryParse(channelId.replaceFirst('ch_', '')) ?? 0;
              NativeFFI.instance.insertSetMix(trackId, slotIndex, wetDry);
              // Update local state
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.updateInsertWetDry(channelId, slotIndex, wetDry);
            },
            onChannelInsertRemove: (channelId, slotIndex) {
              final trackId = int.tryParse(channelId.replaceFirst('ch_', '')) ?? 0;
              NativeFFI.instance.insertUnloadSlot(trackId, slotIndex);
              // Update local state
              final mixerProvider = context.read<MixerProvider>();
              mixerProvider.removeInsert(channelId, slotIndex);
            },
            onChannelInsertOpenEditor: (channelId, slotIndex) {
              final trackId = int.tryParse(channelId.replaceFirst('ch_', '')) ?? 0;
              // Open plugin editor window via FFI
              NativeFFI.instance.insertOpenEditor(trackId, slotIndex);
            },

            // Center zone - uses Selector internally for playhead
            child: _buildCenterContentOptimized(),

            // Inspector (for middleware mode)
            inspectorType: InspectedObjectType.event,
            inspectorName: 'Play_Music',
            inspectorSections: _buildInspectorSections(),

            // Clip inspector (DAW mode)
            selectedClip: _clips.cast<timeline.TimelineClip?>().firstWhere(
              (c) => c?.selected == true,
              orElse: () => null,
            ),
            selectedClipTrack: _getSelectedClipTrack(),
            onClipChanged: _handleClipInspectorChange,
            onOpenClipFxEditor: _handleOpenClipFxEditor,

            // Lower zone - uses Selector for metering
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
          ),
          // Floating EQ windows - optimized
          ..._buildFloatingEqWindowsOptimized(),

          // Debug Console (toggle with Ctrl+Shift+D)
          if (_showDebugConsole)
            Positioned.fill(
              child: DebugConsole(
                onClose: () => setState(() => _showDebugConsole = false),
              ),
            ),
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

  /// Static lower tabs that don't depend on metering
  List<LowerZoneTab> _buildLowerTabsStatic() {
    final engine = context.read<EngineProvider>();
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
      clips: _clips,
      markers: _markers,
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
        debugPrint('[UI] onClipMoveToTrack: clipId=$clipId, targetTrackId=$targetTrackId, targetTrack.color=${targetTrack.color}');
        setState(() {
          // Auto-select the target track
          _selectedTrackId = targetTrackId;
          _activeLeftTab = LeftZoneTab.channel;

          _clips = _clips.map((c) {
            if (c.id == clipId) {
              debugPrint('[UI] Updating clip $clipId color to ${targetTrack.color}');
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
        debugPrint('[UI] onClipMoveToNewTrack: clipId=$clipId, newTrackIndex=$trackIndex, color=$color');

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
            } catch (e) {
              debugPrint('[ClipResize] Engine error: $e');
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
          } catch (e) {
            debugPrint('[ClipResizeEnd] Engine error: $e');
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
          ));
        });
      },
      onClipDelete: (clipId) {
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
      },
      // Track context menu
      onTrackContextMenu: (trackId, position) {
        _showTrackContextMenu(trackId, position);
      },
      // Transport shortcuts (SPACE)
      onPlayPause: () {
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
    final event = _selectedEvent;
    final eventName = event?.name ?? 'No Event Selected';
    final actionCount = event?.actions.length ?? 0;

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Middleware Toolbar - Full command bar with all options - CONNECTED
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Event selector dropdown - Connected to real events
                  _ToolbarDropdown(
                    icon: Icons.api,
                    label: 'Event',
                    value: eventName,
                    options: _middlewareEvents.map((e) => e.name).toList(),
                    onChanged: (val) {
                      final evt = _middlewareEvents.firstWhere((e) => e.name == val);
                      setState(() {
                        _selectedEventId = evt.id;
                        _selectedActionIndex = -1;
                      });
                    },
                    accentColor: FluxForgeTheme.accentOrange,
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: FluxForgeTheme.borderSubtle),
                  const SizedBox(width: 8),
                  // Action type dropdown - Updates header state
                  _ToolbarDropdown(
                    icon: Icons.flash_on,
                    label: 'Action',
                    value: _headerActionType,
                    options: kActionTypes,
                    onChanged: (val) => setState(() => _headerActionType = val),
                    accentColor: FluxForgeTheme.accentGreen,
                  ),
                  const SizedBox(width: 8),
                  // Asset ID dropdown
                  _ToolbarDropdown(
                    icon: Icons.audiotrack,
                    label: 'Asset',
                    value: _headerAssetId,
                    options: kAllAssetIds,
                    onChanged: (val) => setState(() => _headerAssetId = val),
                    accentColor: FluxForgeTheme.accentCyan,
                  ),
                  const SizedBox(width: 8),
                  // Bus dropdown
                  _ToolbarDropdown(
                    icon: Icons.speaker,
                    label: 'Bus',
                    value: _headerBus,
                    options: kAllBuses,
                    onChanged: (val) => setState(() => _headerBus = val),
                    accentColor: FluxForgeTheme.accentBlue,
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: FluxForgeTheme.borderSubtle),
                  const SizedBox(width: 8),
                  // Scope dropdown
                  _ToolbarDropdown(
                    icon: Icons.scatter_plot,
                    label: 'Scope',
                    value: _headerScope,
                    options: kScopes,
                    onChanged: (val) => setState(() => _headerScope = val),
                    accentColor: FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  // Priority dropdown
                  _ToolbarDropdown(
                    icon: Icons.priority_high,
                    label: 'Priority',
                    value: _headerPriority,
                    options: kPriorities,
                    onChanged: (val) => setState(() => _headerPriority = val),
                    accentColor: FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: FluxForgeTheme.borderSubtle),
                  const SizedBox(width: 8),
                  // Action buttons - ALL CONNECTED
                  _ToolbarButton(icon: Icons.add, label: 'Add', onTap: _addAction),
                  const SizedBox(width: 4),
                  _ToolbarButton(icon: Icons.play_arrow, label: 'Preview', onTap: _previewEvent),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    icon: Icons.copy,
                    label: 'Duplicate',
                    onTap: _selectedActionIndex >= 0 ? () => _duplicateAction(_selectedActionIndex) : () {},
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onTap: _selectedActionIndex >= 0 ? () => _deleteAction(_selectedActionIndex) : () {},
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: FluxForgeTheme.borderSubtle),
                  const SizedBox(width: 8),
                  // View mode toggles - CONNECTED
                  _ToolbarIconButton(
                    icon: Icons.grid_view,
                    tooltip: 'Grid View',
                    onTap: () => setState(() => _middlewareGridView = true),
                  ),
                  _ToolbarIconButton(
                    icon: Icons.list,
                    tooltip: 'List View',
                    onTap: () => setState(() => _middlewareGridView = false),
                  ),
                  // Import/Export - CONNECTED
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'export') _exportEventsToJson();
                      if (val == 'import') _importEventsFromJson();
                    },
                    offset: const Offset(0, 32),
                    color: FluxForgeTheme.bgElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'export',
                        height: 32,
                        child: Row(
                          children: [
                            Icon(Icons.upload, size: 14, color: FluxForgeTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text('Export to Clipboard', style: TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        height: 32,
                        child: Row(
                          children: [
                            Icon(Icons.download, size: 14, color: FluxForgeTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text('Import from Clipboard', style: TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary)),
                          ],
                        ),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.import_export, size: 16, color: FluxForgeTheme.textSecondary),
                    ),
                  ),
                  // Settings - CONNECTED
                  _ToolbarIconButton(icon: Icons.settings, tooltip: 'Settings', onTap: _showSettingsDialog),
                ],
              ),
            ),
          ),
          // Event header with all parameters - CONNECTED TO REAL DATA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Event info - REAL DATA
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.api, size: 16, color: FluxForgeTheme.accentOrange),
                          const SizedBox(width: 8),
                          Text('Event: $eventName', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: FluxForgeTheme.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('$actionCount action(s) • Category: ${event?.category ?? "—"}', style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // All parameter dropdowns - CONNECTED
                  _MiniDropdown(
                    label: 'Priority',
                    value: _headerPriority,
                    options: kPriorities,
                    onChanged: (val) => setState(() => _headerPriority = val),
                  ),
                  const SizedBox(width: 12),
                  _MiniDropdown(
                    label: 'Scope',
                    value: _headerScope,
                    options: kScopes,
                    onChanged: (val) => setState(() => _headerScope = val),
                  ),
                  const SizedBox(width: 12),
                  _MiniDropdown(
                    label: 'Fade Curve',
                    value: _headerFadeCurve,
                    options: kFadeCurves,
                    onChanged: (val) => setState(() => _headerFadeCurve = val),
                  ),
                  const SizedBox(width: 12),
                  // Fade time input - CONNECTED
                  _MiniInput(
                    label: 'Fade',
                    value: '${(_headerFadeTime * 1000).toInt()}ms',
                    onTap: () {
                      // Cycle through common values
                      setState(() {
                        if (_headerFadeTime < 0.1) _headerFadeTime = 0.1;
                        else if (_headerFadeTime < 0.2) _headerFadeTime = 0.2;
                        else if (_headerFadeTime < 0.5) _headerFadeTime = 0.5;
                        else if (_headerFadeTime < 1.0) _headerFadeTime = 1.0;
                        else _headerFadeTime = 0.0;
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  // Gain input - CONNECTED
                  _MiniInput(
                    label: 'Gain',
                    value: '${(_headerGain * 100).toInt()}%',
                    onTap: () {
                      // Cycle through common values
                      setState(() {
                        if (_headerGain >= 1.0) _headerGain = 0.8;
                        else if (_headerGain >= 0.8) _headerGain = 0.5;
                        else if (_headerGain >= 0.5) _headerGain = 0.25;
                        else _headerGain = 1.0;
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  // Loop toggle - CONNECTED
                  _MiniToggle(
                    label: 'Loop',
                    value: _headerLoop,
                    onChanged: (val) => setState(() => _headerLoop = val),
                  ),
                ],
              ),
            ),
          ),
          // Actions table with all columns - REAL DATA & FULLY INTERACTIVE
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildActionsTable(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build actions table with real data and full interactivity
  Widget _buildActionsTable() {
    final event = _selectedEvent;
    if (event == null) {
      return Container(
        width: 900,
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

    return Container(
      width: 950,
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
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Row(
              children: const [
                SizedBox(width: 24, child: Text('#', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 110, child: Text('Action Type', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 130, child: Text('Asset ID', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 80, child: Text('Target Bus', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 50, child: Text('Gain', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 60, child: Text('Fade', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 80, child: Text('Curve', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 90, child: Text('Scope', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 32, child: Text('L', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 80, child: Text('Priority', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 50, child: Text('Actions', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          // Table rows - REAL DATA
          ...event.actions.asMap().entries.map((entry) {
            final idx = entry.key;
            final action = entry.value;
            final isSelected = idx == _selectedActionIndex;
            return GestureDetector(
              onTap: () => _selectAction(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15) : Colors.transparent,
                  border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5)),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text('${idx + 1}', style: TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary))),
                    // Action Type dropdown - CONNECTED
                    SizedBox(
                      width: 110,
                      child: _CellDropdown(
                        value: action.type.displayName,
                        options: kActionTypes,
                        color: _getTypeColor(action.type.displayName),
                        onChanged: (val) => _updateAction(idx, action.copyWith(type: ActionTypeExtension.fromString(val))),
                      ),
                    ),
                    // Asset ID dropdown - CONNECTED
                    SizedBox(
                      width: 130,
                      child: _CellDropdown(
                        value: action.assetId.isEmpty ? '—' : action.assetId,
                        options: kAllAssetIds,
                        color: FluxForgeTheme.accentCyan,
                        onChanged: (val) => _updateAction(idx, action.copyWith(assetId: val == '—' ? '' : val)),
                      ),
                    ),
                    // Bus dropdown - CONNECTED
                    SizedBox(
                      width: 80,
                      child: _CellDropdown(
                        value: action.bus,
                        options: kAllBuses,
                        color: FluxForgeTheme.accentBlue,
                        onChanged: (val) => _updateAction(idx, action.copyWith(bus: val)),
                      ),
                    ),
                    // Gain - display
                    SizedBox(
                      width: 50,
                      child: Text('${(action.gain * 100).toInt()}%', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary, fontFamily: 'monospace')),
                    ),
                    // Fade - display
                    SizedBox(
                      width: 60,
                      child: Text('${(action.fadeTime * 1000).toInt()}ms', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary, fontFamily: 'monospace')),
                    ),
                    // Curve dropdown - CONNECTED
                    SizedBox(
                      width: 80,
                      child: _CellDropdown(
                        value: action.fadeCurve.displayName,
                        options: kFadeCurves,
                        onChanged: (val) => _updateAction(idx, action.copyWith(fadeCurve: FadeCurveExtension.fromString(val))),
                      ),
                    ),
                    // Scope dropdown - CONNECTED
                    SizedBox(
                      width: 90,
                      child: _CellDropdown(
                        value: action.scope.displayName,
                        options: kScopes,
                        onChanged: (val) => _updateAction(idx, action.copyWith(scope: ActionScopeExtension.fromString(val))),
                      ),
                    ),
                    // Loop toggle - CONNECTED
                    SizedBox(
                      width: 32,
                      child: GestureDetector(
                        onTap: () => _updateAction(idx, action.copyWith(loop: !action.loop)),
                        child: Icon(
                          action.loop ? Icons.loop : Icons.trending_flat,
                          size: 14,
                          color: action.loop ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
                        ),
                      ),
                    ),
                    // Priority dropdown - CONNECTED
                    SizedBox(
                      width: 80,
                      child: _CellDropdown(
                        value: action.priority.displayName,
                        options: kPriorities,
                        color: _getPriorityColor(action.priority.displayName),
                        onChanged: (val) => _updateAction(idx, action.copyWith(priority: ActionPriorityExtension.fromString(val))),
                      ),
                    ),
                    // Action buttons - CONNECTED
                    SizedBox(
                      width: 50,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => _duplicateAction(idx),
                            child: Icon(Icons.copy, size: 14, color: FluxForgeTheme.textTertiary),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _deleteAction(idx),
                            child: Icon(Icons.delete_outline, size: 14, color: FluxForgeTheme.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // Add action row - CONNECTED
          GestureDetector(
            onTap: _addAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 14, color: FluxForgeTheme.accentOrange),
                  const SizedBox(width: 8),
                  Text('Add action...', style: TextStyle(fontSize: 11, color: FluxForgeTheme.accentOrange)),
                ],
              ),
            ),
          ),
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

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Highest':
        return FluxForgeTheme.errorRed;
      case 'High':
        return FluxForgeTheme.accentOrange;
      case 'Normal':
        return FluxForgeTheme.textPrimary;
      case 'Low':
        return FluxForgeTheme.textSecondary;
      case 'Lowest':
        return FluxForgeTheme.textTertiary;
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
        debugPrint('[Audition] Play clip $clipId from $startTime to $endTime');
        // Move playhead to start position and play
        final clip = _clips.firstWhere((c) => c.id == clipId, orElse: () => _clips.first);
        engine.seek(clip.startTime + startTime);
        engine.play();
        setState(() => _isAuditioning = true);
      },
      onStopAudition: () {
        debugPrint('[Audition] Stop');
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
        debugPrint('[Layout] onDetectHitpoints callback called');
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
      debugPrint('[ClipEditor] Invalid clip ID for hitpoint detection: ${clip.id}');
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

    debugPrint('[ClipEditor] Detected ${_clipHitpoints.length} hitpoints');
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
      ));
    }

    setState(() {
      _clips = _clips.where((c) => c.id != clipId).toList()..addAll(newClips);
      _clipHitpoints = []; // Clear hitpoints after slicing
    });

    debugPrint('[ClipEditor] Sliced clip into ${newClips.length} parts');
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
        debugPrint('Crossfade config changed: duration=${config.duration}, preset=${config.fadeOut.preset}');
      },
      onApply: () {
        // Apply crossfade to selected crossfade in timeline
        // TODO: Get selected crossfade ID from timeline selection
        debugPrint('Crossfade applied');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Crossfade applied'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      onCancel: () {
        // Revert to original crossfade settings
        debugPrint('Crossfade edit cancelled');
      },
      onAudition: () {
        // Start playback of crossfade region only
        // Use loop region for audition
        debugPrint('Audition crossfade');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Playing crossfade region...'),
            duration: Duration(seconds: 1),
          ),
        );
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

            debugPrint('Automation synced: ${data.points.length} points to engine');
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

  /// Convert bus/channel ID to numeric track ID for FFI
  /// Uses MixerProvider to get actual engine track ID for audio channels
  int _busIdToTrackId(String busId) {
    // Map bus IDs to numeric track IDs (buses use fixed IDs)
    switch (busId) {
      case 'master': return 0;
      case 'sfx': return 1;
      case 'music': return 2;
      case 'voice': return 3;
      case 'amb': return 4;
      case 'ui': return 5;
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
      meterL: channel?.rmsL ?? 0.0,
      meterR: channel?.rmsR ?? 0.0,
      peakL: channel?.peakL ?? 0.0,
      peakR: channel?.peakR ?? 0.0,
      inserts: insertChain.slots.map((slot) => InsertSlot(
        id: '${channelId}_${slot.index}',
        name: slot.plugin?.displayName ?? '',
        type: slot.plugin?.category.name ?? 'empty',
        bypassed: slot.bypassed,
      )).toList(),
      sends: sends,
      eqEnabled: _openEqWindows.containsKey(channelId),
      eqBands: const [],
      input: channel?.inputSource ?? 'Stereo In',
      output: track.outputBus.name.substring(0, 1).toUpperCase() + track.outputBus.name.substring(1),
    );
  }

  Widget _buildMixerContent(dynamic metering, bool isPlaying) {
    // Cubase-style meter decay: when playback stops, meters decay to 0
    if (_wasPlaying && !isPlaying) {
      // Just stopped - start decay from current values
      _decayMasterL = _dbToLinear(metering.masterPeakL);
      _decayMasterR = _dbToLinear(metering.masterPeakR);
      _decayMasterPeak = _dbToLinear(metering.masterTruePeak);
      _startMeterDecay();
    }
    _wasPlaying = isPlaying;

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

    // Determine meter values: live during playback, decay values when stopped
    double meterL, meterR, meterPeak;
    if (isPlaying) {
      meterL = _dbToLinear(metering.masterPeakL);
      meterR = _dbToLinear(metering.masterPeakR);
      meterPeak = _dbToLinear(metering.masterTruePeak);
    } else {
      // Use decay values when stopped
      meterL = _decayMasterL;
      meterR = _decayMasterR;
      meterPeak = _decayMasterPeak;
    }

    // Get channels from MixerProvider and check which tracks have clips
    final mixerProvider = context.watch<MixerProvider>();
    final channelStrips = mixerProvider.channels.map((ch) {
      // Extract track ID from channel ID (ch_trackId format)
      final trackId = ch.id.startsWith('ch_') ? ch.id.substring(3) : ch.id;
      // Check if this track has any clips
      final hasClips = _clips.any((clip) => clip.trackId == trackId);

      return ProMixerStripData(
        id: ch.id,
        name: ch.name,
        trackColor: ch.color,
        type: 'audio',
        volume: ch.volume,
        muted: ch.muted,
        soloed: ch.soloed,
        // Show metering only if track has clips, scale by volume
        meters: MeterData.fromLinear(
          peakL: hasClips ? meterL * ch.volume : 0.0,
          peakR: hasClips ? meterR * ch.volume : 0.0,
          peakHoldL: hasClips ? meterPeak * ch.volume : 0.0,
          peakHoldR: hasClips ? meterPeak * ch.volume : 0.0,
        ),
        inserts: _getInserts(ch.id),
      );
    }).toList();

    // Master strip - always present
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
              onVolumeChange: (v) => mixerProvider.setVolume(strip.id, v),
              onPanChange: (p) => mixerProvider.setChannelPan(strip.id, p),
              onMuteToggle: () => mixerProvider.toggleMute(strip.id),
              onSoloToggle: () => mixerProvider.toggleSolo(strip.id),
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
      final trackId = ch.id.startsWith('ch_') ? ch.id.substring(3) : ch.id;
      final trackIdInt = int.tryParse(trackId) ?? 0;
      final hasClips = _clips.any((clip) => clip.trackId == trackId);

      // Get stereo metering from engine
      final (peakL, peakR) = EngineApi.instance.getTrackPeakStereo(trackIdInt);
      final (rmsL, rmsR) = EngineApi.instance.getTrackRmsStereo(trackIdInt);
      final correlation = EngineApi.instance.getTrackCorrelation(trackIdInt);

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
        inserts: inserts,
        peakL: hasClips && isPlaying ? peakL : 0,
        peakR: hasClips && isPlaying ? peakR : 0,
        rmsL: hasClips && isPlaying ? rmsL : 0,
        rmsR: hasClips && isPlaying ? rmsR : 0,
        correlation: hasClips && isPlaying ? correlation : 1.0,
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

    // Master channel
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
      peakL: isPlaying ? _dbToLinear(metering.masterPeakL) : _decayMasterL,
      peakR: isPlaying ? _dbToLinear(metering.masterPeakR) : _decayMasterR,
      rmsL: isPlaying ? _dbToLinear(metering.masterRmsL) : 0,
      rmsR: isPlaying ? _dbToLinear(metering.masterRmsR) : 0,
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
          mixerProvider.setVolume(id, vol);
        }
      },
      onPanChange: (id, pan) {
        if (id != 'master') {
          mixerProvider.setChannelPan(id, pan);
        }
      },
      onPanRightChange: (id, pan) {
        if (id != 'master') {
          mixerProvider.setChannelPanRight(id, pan);
        }
      },
      onMuteToggle: (id) {
        if (id == 'master') {
          _onBusMuteToggle(id);
        } else {
          mixerProvider.toggleMute(id);
        }
      },
      onSoloToggle: (id) {
        if (id == 'master') {
          _onBusSoloToggle(id);
        } else {
          mixerProvider.toggleSolo(id);
        }
      },
      onInsertClick: (channelId, insertIndex) {
        debugPrint('[UltimateMixer] Insert click: channel=$channelId, slot=$insertIndex');
        _handleUltimateMixerInsertClick(channelId, insertIndex);
      },
      onSendLevelChange: (channelId, sendIndex, level) {
        debugPrint('[UltimateMixer] Send level: channel=$channelId, send=$sendIndex, level=$level');
        engine.setSendLevel(channelId, sendIndex, level);
      },
      onSendMuteToggle: (channelId, sendIndex, muted) {
        debugPrint('[UltimateMixer] Send mute: channel=$channelId, send=$sendIndex, muted=$muted');
        engine.setSendMuted(channelId, sendIndex, muted);
      },
      onSendPreFaderToggle: (channelId, sendIndex, preFader) {
        debugPrint('[UltimateMixer] Send pre-fader: channel=$channelId, send=$sendIndex, preFader=$preFader');
        engine.setSendPreFader(channelId, sendIndex, preFader);
      },
      onSendDestChange: (channelId, sendIndex, destination) {
        debugPrint('[UltimateMixer] Send destination: channel=$channelId, send=$sendIndex, dest=$destination');
        engine.setSendDestinationById(channelId, sendIndex, destination);
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
    final currentSlot = chain.slots[insertIndex];
    final isPreFader = insertIndex < 4;

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
        if (currentSlot.plugin!.category == PluginCategory.eq) {
          _openEqWindow(channelId);
        }
        debugPrint('[Mixer] Open editor for ${currentSlot.plugin!.name}');
      } else if (result == 'bypass') {
        setState(() {
          _busInserts[channelId] = chain.toggleBypass(insertIndex);
        });
        // Sync bypass to engine FFI
        final trackId = _busIdToTrackId(channelId);
        final newBypass = !currentSlot.bypassed;
        NativeFFI.instance.insertSetBypass(trackId, insertIndex, newBypass);
        debugPrint('[Mixer] Bypass toggled for slot $insertIndex on $channelId -> $newBypass');
      } else if (result == 'replace') {
        final plugin = await showPluginSelector(context: context, channelName: channelName, slotIndex: insertIndex, isPreFader: isPreFader);
        if (plugin != null) {
          setState(() { _busInserts[channelId] = chain.setPlugin(insertIndex, plugin); });
          // Load new processor into engine audio path
          final trackId = _busIdToTrackId(channelId);
          final processorName = _pluginIdToProcessorName(plugin.id);
          if (processorName != null) {
            NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
          }
          debugPrint('[Mixer] Replaced with ${plugin.name} on slot $insertIndex');
        }
      } else if (result == 'remove') {
        setState(() { _busInserts[channelId] = chain.removePlugin(insertIndex); });
        // Unload processor from engine audio path
        final trackId = _busIdToTrackId(channelId);
        NativeFFI.instance.insertUnloadSlot(trackId, insertIndex);
        debugPrint('[Mixer] Removed plugin from slot $insertIndex on $channelId');
      }
    } else {
      // Empty slot - show plugin selector
      final plugin = await showPluginSelector(context: context, channelName: channelName, slotIndex: insertIndex, isPreFader: isPreFader);
      if (plugin != null) {
        setState(() { _busInserts[channelId] = chain.setPlugin(insertIndex, plugin); });

        // Ensure insert chain exists and load processor into engine
        final trackId = _busIdToTrackId(channelId);
        NativeFFI.instance.insertCreateChain(trackId);
        final processorName = _pluginIdToProcessorName(plugin.id);
        if (processorName != null) {
          NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
        }
        debugPrint('[UltimateMixer] Inserted ${plugin.name} on slot $insertIndex for $channelId');

        // Auto-open EQ editor
        if (plugin.category == PluginCategory.eq) {
          _openEqWindow(channelId);
        }
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
    // Get real metering data
    final peakL = isPlaying ? _dbToLinear(metering.masterPeakL) : _decayMasterL;
    final peakR = isPlaying ? _dbToLinear(metering.masterPeakR) : _decayMasterR;
    final rmsL = isPlaying ? _dbToLinear(metering.masterRmsL) : 0.0;
    final rmsR = isPlaying ? _dbToLinear(metering.masterRmsR) : 0.0;
    final truePeakL = isPlaying ? _dbToLinear(metering.masterTruePeak) : 0.0;
    final truePeakR = isPlaying ? _dbToLinear(metering.masterTruePeak) : 0.0;

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

  // Insert chains per bus - starts EMPTY (user adds plugins)
  final Map<String, InsertChain> _busInserts = {
    'sfx': InsertChain(channelId: 'sfx'),
    'music': InsertChain(channelId: 'music'),
    'voice': InsertChain(channelId: 'voice'),
    'amb': InsertChain(channelId: 'amb'),
    'ui': InsertChain(channelId: 'ui'),
    'master': InsertChain(channelId: 'master'),
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

  void _onBusMuteToggle(String busId) {
    setState(() {
      _busMuted[busId] = !(_busMuted[busId] ?? false);
    });
    // TODO: Send to Rust engine via FFI
    // engine.setBusMute(busId, _busMuted[busId]);
    debugPrint('[Mixer] Bus $busId muted: ${_busMuted[busId]}');
  }

  void _onBusSoloToggle(String busId) {
    setState(() {
      _busSoloed[busId] = !(_busSoloed[busId] ?? false);
    });
    // TODO: Send to Rust engine via FFI
    // engine.setBusSolo(busId, _busSoloed[busId]);
    debugPrint('[Mixer] Bus $busId soloed: ${_busSoloed[busId]}');
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
      debugPrint('[Mixer] Channel $channelId output set to $result');
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
      debugPrint('[Mixer] Channel $channelId input set to $result');
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
      routingAddSend(fromChannelId, fxIndex, 0);
      debugPrint('[Mixer] Channel $channelId send $sendIndex routed to $result');
    } else if (result == 'None') {
      // Remove send (TODO: Implement routing_remove_send in FFI when unified_routing enabled)
      debugPrint('[Mixer] Channel $channelId send $sendIndex cleared (FFI pending)');
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
      debugPrint('[Mixer] Cleared slot $slotIndex on $busId');
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
          debugPrint('[Mixer] Inserted ${pluginInfo.name} on slot $slotIndex of $busId');
        }
        break;

      case SlotDestinationType.aux:
        // Send to FX bus
        debugPrint('[Mixer] Send slot $slotIndex to AUX $targetId');
        final fromChannelId = _busIdToChannelId(busId);
        final toChannelId = int.tryParse(targetId) ?? 0;
        routingAddSend(fromChannelId, toChannelId, 0);
        break;

      case SlotDestinationType.bus:
        // Route output to bus
        debugPrint('[Mixer] Route $busId output to BUS $targetId');
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
        // Open plugin editor in floating window
        final plugin = currentSlot.plugin!;
        if (plugin.category == PluginCategory.eq) {
          _openEqWindow(busId);
        }
        debugPrint('[Mixer] Open editor for ${plugin.name}');
      } else if (result == 'bypass') {
        // Toggle bypass
        setState(() {
          _busInserts[busId] = chain.toggleBypass(insertIndex);
        });
        // Sync to engine FFI
        final trackId = _busIdToTrackId(busId);
        final newBypass = !currentSlot.bypassed;
        NativeFFI.instance.insertSetBypass(trackId, insertIndex, newBypass);
        debugPrint('[Mixer] Bypass toggled for slot $insertIndex on $busId -> $newBypass');
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
          final processorName = _pluginIdToProcessorName(plugin.id);
          if (processorName != null) {
            final result = NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
            debugPrint('[Mixer] Load processor "$processorName" -> result: $result');
          }
          debugPrint('[Mixer] Replaced with ${plugin.name} on slot $insertIndex');
        }
      } else if (result == 'remove') {
        // Remove plugin from UI state
        setState(() {
          _busInserts[busId] = chain.removePlugin(insertIndex);
        });
        // Unload processor from engine audio path
        final trackId = _busIdToTrackId(busId);
        NativeFFI.instance.insertUnloadSlot(trackId, insertIndex);
        debugPrint('[Mixer] Removed plugin from slot $insertIndex on $busId');
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
        final processorName = _pluginIdToProcessorName(plugin.id);
        if (processorName != null) {
          final result = NativeFFI.instance.insertLoadProcessor(trackId, insertIndex, processorName);
          debugPrint('[Mixer] Load processor "$processorName" -> result: $result');
        }

        debugPrint('[Mixer] Inserted ${plugin.name} on slot $insertIndex');

        // Auto-open EQ editor in floating window if EQ was inserted
        if (plugin.category == PluginCategory.eq) {
          _openEqWindow(busId);
        }
      }
    }
  }

  /// Map plugin ID to Rust processor name
  String? _pluginIdToProcessorName(String pluginId) {
    const mapping = {
      'rf-pro-eq': 'pro-eq',
      'rf-channel-eq': 'pro-eq',  // Use pro-eq as fallback
      'rf-linear-eq': 'pro-eq',   // Use pro-eq as fallback
      'rf-compressor': 'compressor',
      'rf-limiter': 'limiter',
      'rf-gate': 'gate',
      'rf-expander': 'expander',
      'rf-pultec': 'pultec',
      'rf-api550': 'api550',
      'rf-neve1073': 'neve1073',
      'rf-ultra-eq': 'ultra-eq',
      'rf-room-correction': 'room-correction',
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
        final trackId = _busIdToTrackId(channelId);
        NativeFFI.instance.insertLoadProcessor(trackId, i, 'pro-eq');

        debugPrint('[EQ] Auto-created Pro EQ in slot $i for $channelId (trackId: $trackId)');
        return i;
      }
    }

    // No empty slots
    debugPrint('[EQ] No empty slots for $channelId');
    return -1;
  }

  /// Open EQ in floating window
  void _openEqWindow(String channelId) {
    debugPrint('[EQ] Opening floating window for: $channelId');
    setState(() {
      _openEqWindows[channelId] = true;
    });
    debugPrint('[EQ] Open windows: $_openEqWindows');
  }

  /// Close EQ floating window
  void _closeEqWindow(String channelId) {
    setState(() {
      _openEqWindows.remove(channelId);
    });
  }

  /// Build floating EQ windows
  List<Widget> _buildFloatingEqWindows(MeteringState metering, bool isPlaying) {
    // debugPrint('[EQ] Building floating windows, count: ${_openEqWindows.length}');
    return _openEqWindows.entries.map((entry) {
      final channelId = entry.key;
      final channelName = channelId == 'master' ? 'Master' : channelId;

      // Calculate signal level from metering
      double signalLevel = 0.0;
      if (isPlaying) {
        final peakDb = (metering.masterPeakL + metering.masterPeakR) / 2;
        signalLevel = peakDb > -60 ? _dbToLinear(peakDb) : 0.0;
      }

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
                      // UNIFIED EQ ROUTING: All EQ params go through insert chain
                      // Find which slot has the EQ for this channel, or auto-create one
                      var slotIndex = _findEqSlotForChannel(channelId);

                      if (slotIndex < 0) {
                        // Auto-create EQ in first empty insert slot
                        slotIndex = _autoCreateEqSlot(channelId);
                        if (slotIndex < 0) {
                          debugPrint('[EQ] Failed to create EQ slot for $channelId');
                          return;
                        }
                      } else {
                        // Slot exists in UI state but processor may not be loaded in engine
                        // Only load if not already loaded (check first)
                        final trackId = _busIdToTrackId(channelId);
                        if (!NativeFFI.instance.insertIsLoaded(trackId, slotIndex)) {
                          debugPrint('[EQ] Processor not loaded in engine, loading now...');
                          NativeFFI.instance.insertLoadProcessor(trackId, slotIndex, 'pro-eq');
                        }
                      }

                      // Use insert chain params: per band = 11
                      // (freq=0, gain=1, q=2, enabled=3, shape=4,
                      //  dynEnabled=5, dynThreshold=6, dynRatio=7, dynAttack=8, dynRelease=9, dynKnee=10)
                      final trackId = _busIdToTrackId(channelId);
                      final baseParam = bandIndex * 11;

                      // DEBUG: Log EQ band changes
                      debugPrint('[EQ] Band change: channel=$channelId -> trackId=$trackId, slot=$slotIndex, band=$bandIndex');
                      debugPrint('[EQ]   freq=$freq, gain=$gain, q=$q, enabled=$enabled, filterType=$filterType');
                      if (freq != null) {
                        final result = NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 0, freq);
                        debugPrint('[EQ] insertSetParam(track=$trackId, slot=$slotIndex, param=${baseParam + 0}, value=$freq) -> result=$result');
                      }
                      if (gain != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 1, gain);
                      }
                      if (q != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 2, q);
                      }
                      if (enabled != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 3, enabled ? 1.0 : 0.0);
                      }
                      if (filterType != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 4, filterType.toDouble());
                      }
                      // Dynamic EQ parameters
                      if (dynamicEnabled != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 5, dynamicEnabled ? 1.0 : 0.0);
                      }
                      if (dynamicThreshold != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 6, dynamicThreshold);
                      }
                      if (dynamicRatio != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 7, dynamicRatio);
                      }
                      if (dynamicAttack != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 8, dynamicAttack);
                      }
                      if (dynamicRelease != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 9, dynamicRelease);
                      }
                      if (dynamicKnee != null) {
                        NativeFFI.instance.insertSetParam(trackId, slotIndex, baseParam + 10, dynamicKnee);
                      }
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
        debugPrint('MIDI notes changed');
      },
    );
  }

  /// Build Pro EQ content - RF-EQ 64 (64-Band Parametric Equalizer)
  Widget _buildProEqContent(dynamic metering, bool isPlaying) {
    // Convert dB metering to linear for EQ signal level
    double signalLevel = 0.0;
    if (isPlaying) {
      // Use master peak as signal indicator
      final peakDb = (metering.masterPeakL + metering.masterPeakR) / 2;
      signalLevel = peakDb > -60 ? _dbToLinear(peakDb) : 0.0;
    }

    // Use global engine instance from engine_api.dart
    final engineApi = EngineApi.instance;

    // Use RF-EQ 64 - the professional FabFilter-style EQ with Pro EQ DSP
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
            // Send EQ band changes to Pro EQ DSP engine (64-band SVF)
            const trackId = 'master';
            if (enabled != null) {
              engineApi.proEqSetBandEnabled(trackId, bandIndex, enabled);
            }
            if (freq != null) {
              engineApi.proEqSetBandFrequency(trackId, bandIndex, freq);
            }
            if (gain != null) {
              engineApi.proEqSetBandGain(trackId, bandIndex, gain);
            }
            if (q != null) {
              engineApi.proEqSetBandQ(trackId, bandIndex, q);
            }
            if (filterType != null) {
              // Map UI filter type to Pro EQ filter shape
              final shape = ProEqFilterShape.values[filterType.clamp(0, ProEqFilterShape.values.length - 1)];
              engineApi.proEqSetBandShape(trackId, bandIndex, shape);
            }
            // Dynamic EQ parameters - send to engine
            if (dynamicEnabled != null) {
              engineApi.proEqSetBandDynamicEnabled(trackId, bandIndex, dynamicEnabled);
            }
            if (dynamicThreshold != null || dynamicRatio != null ||
                dynamicAttack != null || dynamicRelease != null || dynamicKnee != null) {
              engineApi.proEqSetBandDynamicParams(
                trackId, bandIndex,
                threshold: dynamicThreshold,
                ratio: dynamicRatio,
                attackMs: dynamicAttack,
                releaseMs: dynamicRelease,
                kneeDb: dynamicKnee,
              );
            }
          },
          onBypassChange: (bypass) {
            // Pro EQ doesn't have global bypass, reset all bands instead
            if (bypass) {
              engineApi.proEqReset('master');
            }
          },
          onPhaseModeChange: (mode) {
            // 0=ZeroLatency, 1=Natural, 2=Linear
            engineApi.proEqSetPhaseMode('master', mode);
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
                        debugPrint('[Analysis] Transient detection: sens=$_transientSensitivity algo=$_transientAlgorithm');
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
                        debugPrint('[Analysis] Pitch detection triggered');
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
    debugPrint('[EQ] Syncing ${_eqBands.length} bands to engine');
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
                  debugPrint('[Loudness] Reset integrated LUFS');
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
      // Middleware mode - event/action inspector
      return [
        InspectorSection(
          id: 'action',
          title: 'Action',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InspectorDropdown(
                label: 'Type',
                value: 'Play',
                options: ['Play', 'Stop', 'StopAll', 'Fade', 'Pause', 'SetBusGain'],
              ),
              _InspectorDropdown(
                label: 'Asset',
                value: 'music_main.wav',
                options: ['music_main.wav', 'sfx_click.wav', 'ui_hover.wav'],
              ),
              _InspectorDropdown(
                label: 'Bus',
                value: 'Music',
                options: ['Master', 'Music', 'SFX', 'UI', 'Voice'],
              ),
            ],
          ),
        ),
        InspectorSection(
          id: 'playback',
          title: 'Playback',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InspectorSlider(label: 'Gain', value: 1.0, suffix: '100%'),
              _InspectorSlider(label: 'Pan', value: 0.0, suffix: 'C'),
              _InspectorCheckbox(label: 'Loop', checked: false),
              _InspectorCheckbox(label: 'Allow Overlap', checked: true),
            ],
          ),
        ),
        InspectorSection(
          id: 'timing',
          title: 'Timing',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InspectorField(label: 'Delay', value: '0 ms'),
              _InspectorField(label: 'Fade In', value: '100 ms'),
              _InspectorField(label: 'Fade Out', value: '200 ms'),
            ],
          ),
        ),
      ];
    }
  }

  /// Build all lower zone tabs (matches React LayoutDemo.tsx 1:1)
  /// All tabs are created, then filtered by mode visibility
  List<LowerZoneTab> _buildLowerTabs(dynamic metering, bool isPlaying) {
    final List<LowerZoneTab> tabs = [
      // ========== Timeline (center zone in DAW, hidden in lower) ==========
      LowerZoneTab(
        id: 'timeline',
        label: 'Timeline',
        icon: Icons.view_timeline,
        content: const TimelineTabPlaceholder(),
        groupId: 'mixconsole',
      ),
      // ========== Mixer (MixConsole group) ==========
      // Only Ultimate Mixer - no legacy DAW mixer
      LowerZoneTab(
        id: 'mixer',
        label: 'Mixer',
        icon: Icons.tune,
        content: _buildUltimateMixerContent(metering, isPlaying),
        groupId: 'mixconsole',
      ),
      LowerZoneTab(
        id: 'metering-bridge',
        label: 'Metering Bridge',
        icon: Icons.speed,
        content: _buildMeteringBridgeContent(metering, isPlaying),
        groupId: 'mixconsole',
      ),
      LowerZoneTab(
        id: 'control-room',
        label: 'Control Room',
        icon: Icons.headphones,
        content: _buildControlRoomContent(),
        groupId: 'mixconsole',
      ),
      LowerZoneTab(
        id: 'input-bus',
        label: 'Input Bus',
        icon: Icons.input,
        content: _buildInputBusContent(),
        groupId: 'mixconsole',
      ),
      LowerZoneTab(
        id: 'recording',
        label: 'Recording',
        icon: Icons.fiber_manual_record,
        content: _buildRecordingContent(),
        groupId: 'mixconsole',
      ),
      LowerZoneTab(
        id: 'routing',
        label: 'Routing',
        icon: Icons.device_hub,
        content: _buildRoutingContent(),
        groupId: 'mixconsole',
      ),
      // ========== Clip Editor (Editor group) ==========
      LowerZoneTab(
        id: 'clip-editor',
        label: 'Clip Editor',
        icon: Icons.edit,
        contentBuilder: _buildClipEditorContent, // Dynamic - needs fresh callbacks
        groupId: 'editor',
      ),
      // ========== Crossfade Editor (Editor group) ==========
      LowerZoneTab(
        id: 'crossfade',
        label: 'Crossfade',
        icon: Icons.compare,
        content: _buildCrossfadeEditorContent(),
        groupId: 'editor',
      ),
      // ========== Automation Editor (Editor group) ==========
      LowerZoneTab(
        id: 'automation',
        label: 'Automation',
        icon: Icons.timeline,
        content: _buildAutomationEditorContent(),
        groupId: 'editor',
      ),
      // ========== Piano Roll (Editor group) ==========
      LowerZoneTab(
        id: 'piano-roll',
        label: 'Piano Roll',
        icon: Icons.piano,
        content: _buildPianoRollContent(),
        groupId: 'editor',
      ),
      // ========== Layered Music (Sampler group) ==========
      LowerZoneTab(
        id: 'layers',
        label: 'Layered Music',
        icon: Icons.layers,
        content: const LayeredMusicTabPlaceholder(),
        groupId: 'sampler',
      ),
      // ========== Console (Tools group) ==========
      LowerZoneTab(
        id: 'console',
        label: 'Console',
        icon: Icons.terminal,
        content: const ConsoleTabPlaceholder(),
        groupId: 'tools',
      ),
      // ========== Validation (Tools group) ==========
      LowerZoneTab(
        id: 'validation',
        label: 'Validation',
        icon: Icons.check_circle_outline,
        content: const ValidationTabPlaceholder(),
        groupId: 'tools',
      ),
      // ========== Plugin Browser (Tools group) ==========
      LowerZoneTab(
        id: 'plugins',
        label: 'Plugins',
        icon: Icons.extension,
        content: PluginBrowser(
          onPluginLoad: (plugin) {
            // TODO: Load plugin into selected track/bus insert slot
            debugPrint('Load plugin: ${plugin.name}');
          },
        ),
        groupId: 'tools',
      ),
      // ========== Slot Audio Tabs ==========
      LowerZoneTab(
        id: 'spin-cycle',
        label: 'Spin Cycle',
        icon: Icons.casino,
        content: const SpinCycleTabPlaceholder(),
        groupId: 'slot',
      ),
      LowerZoneTab(
        id: 'win-tiers',
        label: 'Win Tiers',
        icon: Icons.emoji_events,
        content: const WinTiersTabPlaceholder(),
        groupId: 'slot',
      ),
      LowerZoneTab(
        id: 'reel-sequencer',
        label: 'Reel Sequencer',
        icon: Icons.timer,
        content: const ReelSequencerTabPlaceholder(),
        groupId: 'slot',
      ),
      // ========== Audio Features (Features group) ==========
      LowerZoneTab(
        id: 'audio-features',
        label: 'Audio Features',
        icon: Icons.settings,
        content: const AudioFeaturesTabPlaceholder(),
        groupId: 'features',
      ),
      // ========== Pro Features (Features group) ==========
      LowerZoneTab(
        id: 'pro-features',
        label: 'Pro Features',
        icon: Icons.flash_on,
        content: const ProFeaturesTabPlaceholder(),
        groupId: 'features',
      ),
      // ========== Slot Studio (Slot group) ==========
      LowerZoneTab(
        id: 'slot-studio',
        label: 'Slot Studio',
        icon: Icons.headphones,
        content: const SlotStudioTabPlaceholder(),
        groupId: 'slot',
      ),
      // ========== DSP Tabs ==========
      LowerZoneTab(
        id: 'eq',
        label: 'EQ',
        icon: Icons.graphic_eq,
        content: _buildProEqContent(metering, isPlaying),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'analog-eq',
        label: 'Analog EQ',
        icon: Icons.tune,
        content: _buildAnalogEqContent(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'spectrum',
        label: 'Spectrum',
        icon: Icons.show_chart,
        content: const SpectrumAnalyzerDemo(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'loudness',
        label: 'Loudness',
        icon: Icons.surround_sound,
        content: _buildLoudnessContent(metering),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'meters',
        label: 'Meters',
        icon: Icons.speed,
        content: ProMeteringPanel(metering: metering),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'advanced-meters',
        label: 'Advanced',
        icon: Icons.insights,
        content: const AdvancedMeteringPanel(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'pdc',
        label: 'PDC',
        icon: Icons.timer_outlined,
        content: PdcDetailPanel(
          trackIds: _tracks.map((t) => t.id.hashCode).toList(),
          sampleRate: 48000,
        ),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'sidechain',
        label: 'Sidechain',
        icon: Icons.link,
        content: const SidechainTabPlaceholder(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'multiband',
        label: 'Multiband',
        icon: Icons.equalizer,
        content: MultibandPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'analysis',
        label: 'Analysis',
        icon: Icons.analytics,
        content: _buildAnalysisContent(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'timestretch',
        label: 'Time Stretch',
        icon: Icons.speed,
        content: _buildTimeStretchContent(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'fx-presets',
        label: 'FX Presets',
        icon: Icons.auto_fix_high,
        content: const FXPresetsTabPlaceholder(),
        groupId: 'dsp',
      ),
      // ========== DSP Processing Panels ==========
      LowerZoneTab(
        id: 'delay',
        label: 'Delay',
        icon: Icons.timer,
        content: DelayPanel(trackId: 0, bpm: 120.0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'reverb',
        label: 'Reverb',
        icon: Icons.blur_on,
        content: ReverbPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'dynamics',
        label: 'Dynamics',
        icon: Icons.compress,
        content: DynamicsPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'spatial',
        label: 'Spatial',
        icon: Icons.surround_sound,
        content: SpatialPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'spectral',
        label: 'Spectral',
        icon: Icons.waves,
        content: SpectralPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'pitch',
        label: 'Pitch',
        icon: Icons.music_note,
        content: PitchCorrectionPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'transient',
        label: 'Transient',
        icon: Icons.flash_on,
        content: TransientPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'saturation',
        label: 'Saturation',
        icon: Icons.whatshot,
        content: SaturationPanel(trackId: 0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'analog-eq',
        label: 'Analog EQ',
        icon: Icons.graphic_eq,
        content: AnalogEqPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'sidechain',
        label: 'Sidechain',
        icon: Icons.call_split,
        content: SidechainPanel(processorId: 0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'wavelet',
        label: 'Wavelet',
        icon: Icons.waves,
        content: WaveletPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'channel-strip',
        label: 'Channel Strip',
        icon: Icons.tune,
        content: ChannelStripPanel(trackId: 0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'surround-panner',
        label: 'Surround',
        icon: Icons.surround_sound,
        content: SurroundPannerPanel(trackId: 0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'linear-phase-eq',
        label: 'Linear EQ',
        icon: Icons.graphic_eq,
        content: LinearPhaseEqPanel(trackId: 0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'stereo-eq',
        label: 'Stereo EQ',
        icon: Icons.graphic_eq,
        content: StereoEqPanel(trackId: 0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'pro-eq',
        label: 'Pro-EQ 64',
        icon: Icons.auto_graph,
        content: ProEqPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'ultra-eq',
        label: 'Ultra-EQ 256',
        icon: Icons.multiline_chart,
        content: UltraEqPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'room-correction',
        label: 'Room Correct',
        icon: Icons.room_preferences,
        content: RoomCorrectionPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'stereo-imager',
        label: 'Stereo Imager',
        icon: Icons.spatial_audio,
        content: StereoImagerPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      // ========== Phase 2 Ultimate DSP Panels ==========
      LowerZoneTab(
        id: 'convolution-ultra',
        label: 'Convolution Ultra',
        icon: Icons.blur_on,
        content: const ConvolutionUltraPanel(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'gpu-settings',
        label: 'GPU DSP',
        icon: Icons.memory,
        content: const GpuSettingsPanel(),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'ml-processor',
        label: 'ML Processor',
        icon: Icons.psychology,
        content: MlProcessorPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'mastering',
        label: 'Mastering',
        icon: Icons.auto_awesome,
        content: MasteringPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      LowerZoneTab(
        id: 'restoration',
        label: 'Restoration',
        icon: Icons.healing,
        content: RestorationPanel(trackId: 0, sampleRate: 48000.0),
        groupId: 'dsp',
      ),
      // ========== Media Tabs ==========
      LowerZoneTab(
        id: 'audio-browser',
        label: 'Audio Browser',
        icon: Icons.folder_open,
        content: const AudioBrowserTabPlaceholder(),
        groupId: 'media',
      ),
      LowerZoneTab(
        id: 'audio-pool',
        label: 'Audio Pool',
        icon: Icons.library_music,
        content: AudioPoolPanel(
          key: AudioPoolPanelState.globalKey,
          onFileDoubleClick: _handleAudioPoolFileDoubleClick,
        ),
        groupId: 'media',
      ),
      // ========== Project Management Tabs ==========
      LowerZoneTab(
        id: 'track-templates',
        label: 'Track Templates',
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
      // ========== PDC (Tools group) ==========
      LowerZoneTab(
        id: 'pdc-status',
        label: 'PDC Status',
        icon: Icons.timer_outlined,
        content: PdcDetailPanel(
          trackIds: _tracks.map((t) => int.tryParse(t.id) ?? 0).toList(),
          sampleRate: 48000.0,
        ),
        groupId: 'tools',
      ),
      // ========== Debug/Demo Tabs (Tools group) ==========
      LowerZoneTab(
        id: 'drag-drop-lab',
        label: 'D&D Lab',
        icon: Icons.pan_tool,
        content: const DragDropLabPlaceholder(),
        groupId: 'tools',
      ),
      LowerZoneTab(
        id: 'loading-states',
        label: 'Loading',
        icon: Icons.hourglass_empty,
        content: const LoadingStatesPlaceholder(),
        groupId: 'tools',
      ),
      // ========== Advanced DAW Features (Advanced group) ==========
      LowerZoneTab(
        id: 'logical-editor',
        label: 'Logical Editor',
        icon: Icons.code,
        content: const LogicalEditorPanel(),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'scale-assistant',
        label: 'Scale Assistant',
        icon: Icons.music_note,
        content: const ScaleAssistantPanel(),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'groove-quantize',
        label: 'Groove Quantize',
        icon: Icons.grid_on,
        content: const GrooveQuantizePanel(),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'audio-alignment',
        label: 'Audio Alignment',
        icon: Icons.align_horizontal_left,
        content: const AudioAlignmentPanel(),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'track-versions',
        label: 'Track Versions',
        icon: Icons.history,
        content: const TrackVersionsPanel(),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'macro-controls',
        label: 'Macro Controls',
        icon: Icons.tune,
        content: const MacroControlsPanel(),
        groupId: 'advanced',
      ),
      LowerZoneTab(
        id: 'clip-gain-envelope',
        label: 'Clip Gain',
        icon: Icons.show_chart,
        content: const ClipGainEnvelopePanel(),
        groupId: 'advanced',
      ),
      // ========== Design Demos ==========
      LowerZoneTab(
        id: 'liquid-glass',
        label: 'Liquid Glass',
        icon: Icons.blur_on,
        content: const LiquidGlassDemo(),
        groupId: 'tools',
      ),
    ];

    // Filter tabs based on mode visibility
    return filterTabsForMode(tabs, _editorMode, (t) => t.id);
  }

  /// Build tab groups (matches React LayoutDemo.tsx 1:1)
  /// All groups are created, then filtered by mode visibility
  List<TabGroup> _buildTabGroups() {
    final List<TabGroup> allGroups = [
      // ========== DAW MODE GROUPS (Cubase-style) ==========
      // MixConsole - Full mixer (like Cubase MixConsole in Lower Zone)
      const TabGroup(
        id: 'mixconsole',
        label: 'MixConsole',
        tabs: ['mixer', 'ultimate-mixer', 'metering-bridge', 'recording', 'routing'], // NOTE: timeline is in center zone, not lower
      ),
      // Editor - Clip Editor, Crossfade, Automation, Piano Roll (like Cubase Lower Zone editors)
      const TabGroup(
        id: 'editor',
        label: 'Editor',
        tabs: ['clip-editor', 'crossfade', 'automation', 'piano-roll'],
      ),
      // Sampler - Layered music system (like Cubase Sampler Control)
      const TabGroup(
        id: 'sampler',
        label: 'Sampler',
        tabs: ['layers'],
      ),
      // Media - Audio Browser & Pool (like Cubase MediaBay)
      const TabGroup(
        id: 'media',
        label: 'Media',
        tabs: ['audio-browser', 'audio-pool'],
      ),
      // DSP - Professional audio processing
      const TabGroup(
        id: 'dsp',
        label: 'DSP',
        tabs: ['eq', 'analog-eq', 'spectrum', 'loudness', 'meters', 'sidechain', 'multiband', 'analysis', 'timestretch', 'fx-presets', 'delay', 'reverb', 'dynamics', 'spatial', 'spectral', 'pitch', 'transient', 'saturation', 'wavelet', 'channel-strip', 'surround-panner', 'linear-phase-eq', 'stereo-eq', 'pro-eq', 'ultra-eq', 'room-correction', 'stereo-imager', 'convolution-ultra', 'gpu-settings', 'ml-processor', 'mastering', 'restoration'],
      ),

      // ========== MIDDLEWARE MODE GROUPS ==========
      // Slot - All slot-specific audio tools
      const TabGroup(
        id: 'slot',
        label: 'Slot Audio',
        tabs: ['spin-cycle', 'win-tiers', 'reel-sequencer', 'slot-studio'],
      ),
      // Features - Audio features and pro tools
      const TabGroup(
        id: 'features',
        label: 'Features',
        tabs: ['audio-features', 'pro-features'],
      ),
      // Tools - Validation, console, debug, demos
      const TabGroup(
        id: 'tools',
        label: 'Tools',
        tabs: ['validation', 'console', 'drag-drop-lab', 'loading-states', 'liquid-glass'],
      ),
      // Advanced - Pro DAW features (Cubase-inspired)
      const TabGroup(
        id: 'advanced',
        label: 'Advanced',
        tabs: ['logical-editor', 'scale-assistant', 'groove-quantize', 'audio-alignment', 'track-versions', 'macro-controls', 'clip-gain-envelope'],
      ),
    ];

    // Filter groups based on mode visibility
    return filterTabGroupsForMode(allGroups, _editorMode, (g) => g.id);
  }

  double _dbToLinear(double db) {
    if (db <= -60) return 0;
    return ((db + 60) / 60).clamp(0.0, 1.0);
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

// ============ Middleware Widgets ============

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 6 : 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentOrange,
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

// NOTE: _ActionsTableFull and _ActionsTableWithDropdowns removed - replaced by _buildActionsTable method

class _CellDropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final Color? color;
  final ValueChanged<String> onChanged;

  const _CellDropdown({
    required this.value,
    required this.options,
    this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 24),
      color: FluxForgeTheme.bgElevated,
      padding: EdgeInsets.zero,
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
              color: isSelected ? (color ?? FluxForgeTheme.accentBlue) : FluxForgeTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                style: TextStyle(fontSize: 10, color: color ?? FluxForgeTheme.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 12, color: FluxForgeTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

// NOTE: _ActionsTable, _TableHeader, _TableCell, _TableCellDropdown removed - unused legacy widgets

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

/// Intent for toggling debug console (Shift+Cmd+D)
class _ToggleDebugIntent extends Intent {
  const _ToggleDebugIntent();
}
