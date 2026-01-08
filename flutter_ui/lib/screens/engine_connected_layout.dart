/// Engine Connected Layout
///
/// Connects MainLayout to the Rust EngineProvider.
/// Bridges UI callbacks to engine API calls.

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
import '../providers/meter_provider.dart';
import '../providers/mixer_provider.dart';
import '../models/layout_models.dart';
import '../models/editor_mode_config.dart';
import '../models/middleware_models.dart';
import '../models/timeline_models.dart' as timeline;
import '../theme/reelforge_theme.dart';
import '../widgets/layout/left_zone.dart' show LeftZoneTab;
import '../widgets/layout/project_tree.dart' show ProjectTreeNode, TreeItemType;
import '../widgets/mixer/pro_mixer_strip.dart';
import '../widgets/mixer/plugin_selector.dart';
import '../models/plugin_models.dart';
// piano_roll.dart is now replaced by midi/piano_roll_widget.dart
import '../widgets/editors/eq_editor.dart' as generic_eq;
import '../widgets/eq/pro_eq_editor.dart' as rf_eq;
import '../widgets/layout/right_zone.dart' show InspectedObjectType;
import '../widgets/tabs/tab_placeholders.dart';
import '../widgets/timeline/timeline.dart' as timeline_widget;
import '../widgets/eq/eq_editor.dart';
import '../widgets/spectrum/spectrum_analyzer.dart';
import '../widgets/meters/loudness_meter.dart';
import '../widgets/meters/pro_metering_panel.dart';
import '../widgets/meters/advanced_metering_panel.dart';
import '../widgets/eq/pultec_eq.dart';
import '../widgets/eq/api550_eq.dart';
import '../widgets/eq/neve1073_eq.dart';
import '../widgets/common/context_menu.dart';
import '../widgets/editor/clip_editor.dart';
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
import '../widgets/dsp/eq_morph_panel.dart';
import '../widgets/dsp/sidechain_panel.dart';
import '../widgets/dsp/wavelet_panel.dart';
import '../widgets/dsp/channel_strip_panel.dart';
import '../widgets/dsp/surround_panner_panel.dart';
import '../widgets/dsp/linear_phase_eq_panel.dart';
import '../widgets/dsp/stereo_eq_panel.dart';
import '../widgets/dsp/min_phase_eq_panel.dart';
import '../widgets/dsp/pro_eq_panel.dart';
import '../widgets/dsp/ultra_eq_panel.dart';
import '../widgets/dsp/room_correction_panel.dart';
import '../widgets/dsp/stereo_imager_panel.dart';
import '../widgets/dsp/convolution_ultra_panel.dart';
import '../widgets/dsp/gpu_settings_panel.dart';
import '../widgets/dsp/deconvolution_wizard.dart';
import '../widgets/dsp/ml_processor_panel.dart';
import '../widgets/dsp/mastering_panel.dart';
import '../widgets/dsp/restoration_panel.dart';
import '../widgets/midi/piano_roll_widget.dart';
import '../src/rust/engine_api.dart';
import '../src/rust/native_ffi.dart';
import '../dialogs/export_audio_dialog.dart';
import 'settings/audio_settings_screen.dart';
import 'project/project_settings_screen.dart';
import 'main_layout.dart';

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
  // Zone state
  bool _leftVisible = true;
  bool _rightVisible = true;
  bool _lowerVisible = true;
  late String _activeLowerTab;
  LeftZoneTab _activeLeftTab = LeftZoneTab.project;

  // Local UI state
  EditorMode _editorMode = EditorMode.middleware;
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

  // Meter decay state - Cubase-style: meters decay to 0 when playback stops
  bool _wasPlaying = false;
  Timer? _meterDecayTimer;
  double _decayMasterL = 0.0;
  double _decayMasterR = 0.0;
  double _decayMasterPeak = 0.0;

  // Floating EQ windows - key is channel/bus ID
  final Map<String, bool> _openEqWindows = {};

  // Analysis state (Transient/Pitch detection)
  double _transientSensitivity = 0.5;
  int _transientAlgorithm = 2; // 0=Energy, 1=Spectral, 2=Enhanced, 3=Onset, 4=ML
  double _detectedPitch = 0.0;
  int _detectedMidi = -1;
  List<int> _detectedTransients = [];

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

  @override
  void initState() {
    super.initState();
    // Set default tab based on initial mode
    _activeLowerTab = getDefaultTabForMode(_editorMode);

    // Initialize empty timeline (no demo data)
    _initEmptyTimeline();

    // Initialize demo middleware data (for Middleware tab only)
    _initDemoMiddlewareData();

    // Register meters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final meters = context.read<MeterProvider>();
      meters.registerMeter('master');
      meters.registerMeter('sfx');
      meters.registerMeter('music');
      meters.registerMeter('voice');
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

  /// Track colors palette
  static const List<Color> _trackColors = [
    Color(0xFF4A9EFF), // Blue
    Color(0xFFFF9040), // Orange
    Color(0xFF40FF90), // Green
    Color(0xFF40C8FF), // Cyan
    Color(0xFFFF4090), // Pink
    Color(0xFFFFFF40), // Yellow
    Color(0xFFFF4040), // Red
    Color(0xFF9040FF), // Purple
  ];

  /// Add a new track
  void _handleAddTrack() {
    final trackIndex = _tracks.length;
    final color = _trackColors[trackIndex % _trackColors.length];
    final trackName = 'Audio ${trackIndex + 1}';
    final trackId = engine.createTrack(
      name: trackName,
      color: color.value,
      busId: 0, // Master
    );

    // Create corresponding mixer channel (Cubase-style auto-fader)
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.createChannelFromTrack(trackId, trackName, color);

    setState(() {
      _tracks = [
        ..._tracks,
        timeline.TimelineTrack(
          id: trackId,
          name: trackName,
          color: color,
          outputBus: timeline.OutputBus.master,
        ),
      ];
    });
  }

  /// Delete a track
  void _handleDeleteTrack(String trackId) {
    engine.deleteTrack(trackId);

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

    // Create mixer channel for the duplicated track
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.createChannelFromTrack(newTrackId, newTrack.name, track.color);

    _showSnackBar('Track duplicated');
  }

  /// Show track context menu with Cubase-style options
  void _showTrackContextMenu(String trackId, Offset position) {
    final track = _tracks.firstWhere((t) => t.id == trackId);

    final menuItems = ContextMenus.track(
      onRename: () {
        // TODO: Show rename dialog
        Navigator.pop(context);
      },
      onDuplicate: () {
        Navigator.pop(context);
        _handleDuplicateTrack(trackId);
      },
      onMute: () {
        Navigator.pop(context);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) return t.copyWith(muted: !t.muted);
            return t;
          }).toList();
        });
      },
      onSolo: () {
        Navigator.pop(context);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) return t.copyWith(soloed: !t.soloed);
            return t;
          }).toList();
        });
      },
      onFreeze: () {
        Navigator.pop(context);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) return t.copyWith(frozen: !t.frozen);
            return t;
          }).toList();
        });
      },
      onColor: () {
        Navigator.pop(context);
        // Color picker is shown on track header
      },
      onDelete: () {
        Navigator.pop(context);
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
  void _addPoolFileToNewTrack(timeline.PoolAudioFile poolFile) {
    final transport = context.read<EngineProvider>().transport;
    final insertTime = transport.positionSeconds;

    // Create new track with same name as audio file
    final trackIndex = _tracks.length;
    final color = _trackColors[trackIndex % _trackColors.length];
    final trackId = 'track-${DateTime.now().millisecondsSinceEpoch}';

    // Use file's default bus
    final bus = poolFile.defaultBus;

    final newTrack = timeline.TimelineTrack(
      id: trackId,
      name: poolFile.name.replaceAll(RegExp(r'\.[^.]+$'), ''), // Remove extension
      color: color,
      outputBus: bus,
    );

    final clipId = 'clip-${DateTime.now().millisecondsSinceEpoch}-${trackIndex}';
    final newClip = timeline.TimelineClip(
      id: clipId,
      trackId: trackId,
      name: poolFile.name,
      startTime: insertTime,
      duration: poolFile.duration,
      sourceDuration: poolFile.duration,
      waveform: poolFile.waveform,
      color: color,
    );

    setState(() {
      _tracks = [..._tracks, newTrack];
      _clips = [..._clips, newClip];
    });

    debugPrint('[UI] Created new track "${newTrack.name}" with ${poolFile.name}');
    _showSnackBar('Added ${poolFile.name} to new track');
    _updateActiveBuses();
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
  }

  /// Create a new track with a clip (used for empty space drops and double-click)
  Future<void> _createTrackWithClip(
    timeline.PoolAudioFile poolFile,
    double startTime, [
    timeline.OutputBus? bus,
  ]) async {
    final trackIndex = _tracks.length;
    final color = _trackColors[trackIndex % _trackColors.length];
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
      _clips = [..._clips, newClip];
    });

    // Create mixer channel for the new track (Cubase-style: track = fader)
    final mixerProvider = context.read<MixerProvider>();
    mixerProvider.createChannelFromTrack(nativeTrackId, trackName, color);

    debugPrint('[UI] Created new track "$trackName" with ${poolFile.name} at $startTime');
    _showSnackBar('Created track "$trackName" with ${poolFile.name}');
    _updateActiveBuses();
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
        backgroundColor: ReelForgeTheme.bgElevated,
        title: const Text('New Project', style: TextStyle(color: ReelForgeTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Create a new project?', style: TextStyle(color: ReelForgeTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Unsaved changes will be lost.', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ReelForgeTheme.textSecondary)),
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
            child: Text('Create', style: TextStyle(color: ReelForgeTheme.accentBlue)),
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
        _clips.add(timeline.TimelineClip(
          id: newId,
          trackId: clip.trackId,
          name: '${clip.name} (copy)',
          startTime: pasteTime + offset,
          duration: clip.duration,
          sourceDuration: clip.sourceDuration,
          sourceOffset: clip.sourceOffset,
          color: clip.color,
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

    // Delete from engine
    for (final id in selectedIds) {
      engine.deleteClip(id);
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
  void _showProjectSettingsDialog(EngineProvider engine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ReelForgeTheme.bgElevated,
        title: const Text('Project Settings', style: TextStyle(color: ReelForgeTheme.textPrimary)),
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
            child: Text('Close', style: TextStyle(color: ReelForgeTheme.accentBlue)),
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
        backgroundColor: ReelForgeTheme.bgElevated,
        title: Row(
          children: [
            Icon(
              issues.isEmpty ? Icons.check_circle : Icons.warning,
              color: issues.isEmpty ? ReelForgeTheme.accentGreen : ReelForgeTheme.warningOrange,
            ),
            const SizedBox(width: 8),
            Text(
              issues.isEmpty ? 'Validation Passed' : 'Validation Issues',
              style: const TextStyle(color: ReelForgeTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: issues.isEmpty
              ? [Text('No issues found.', style: TextStyle(color: ReelForgeTheme.textSecondary))]
              : issues.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 14, color: ReelForgeTheme.warningOrange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(i, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12))),
                    ],
                  ),
                )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: ReelForgeTheme.accentBlue)),
          ),
        ],
      ),
    );
  }

  /// Build/Export project
  void _handleBuildProject() {
    _showSnackBar('Building project...');
    // TODO: Implement actual build/export
    Future.delayed(const Duration(seconds: 1), () {
      _showSnackBar('Build complete!');
    });
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

  /// Open MIDI Settings (placeholder)
  void _handleMidiSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ReelForgeTheme.bgElevated,
        title: const Text('MIDI Settings', style: TextStyle(color: ReelForgeTheme.textPrimary)),
        content: Text(
          'MIDI settings coming soon...',
          style: TextStyle(color: ReelForgeTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Open Plugin Manager (placeholder)
  void _handlePluginManager() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ReelForgeTheme.bgElevated,
        title: const Text('Plugin Manager', style: TextStyle(color: ReelForgeTheme.textPrimary)),
        content: Text(
          'Plugin Manager coming soon...',
          style: TextStyle(color: ReelForgeTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
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

  /// Show snackbar message
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ReelForgeTheme.bgElevated,
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

    // Generate demo waveform (real waveform would come from engine)
    final waveform = timeline.generateDemoWaveform();

    setState(() {
      _audioPool.add(timeline.PoolAudioFile(
        id: fileId,
        path: filePath,
        name: fileName,
        duration: 5.0, // TODO: Get actual duration from engine
        sampleRate: 48000,
        channels: 2,
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
        backgroundColor: ReelForgeTheme.bgElevated,
        title: Text('Middleware Settings', style: TextStyle(color: ReelForgeTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Events: ${_middlewareEvents.length}', style: TextStyle(color: ReelForgeTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Total Actions: ${_middlewareEvents.fold<int>(0, (sum, e) => sum + e.actions.length)}',
                style: TextStyle(color: ReelForgeTheme.textSecondary)),
            const SizedBox(height: 16),
            Text('View Mode: ${_middlewareGridView ? 'Grid' : 'List'}',
                style: TextStyle(color: ReelForgeTheme.textSecondary)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: ReelForgeTheme.accentBlue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EngineProvider>(
      builder: (context, engine, _) {
        final transport = engine.transport;
        final metering = engine.metering;

        // Update active buses based on current playhead position
        // This ensures metering shows only active buses
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && transport.isPlaying) {
            _updateActiveBuses();
          }
        });

        return Stack(
          children: [
            MainLayout(
          // Control bar - connected to engine
          editorMode: _editorMode,
          onEditorModeChange: (mode) => setState(() {
            _editorMode = mode;
            // Reset active tab to mode default
            _activeLowerTab = getDefaultTabForMode(mode);
            _activeLeftTab = LeftZoneTab.project;
          }),
          isPlaying: transport.isPlaying,
          isRecording: transport.isRecording,
          onPlay: () {
            if (transport.isPlaying) {
              engine.pause();
            } else {
              engine.play();
            }
          },
          onStop: () => engine.stop(),
          onRecord: () => engine.toggleRecord(),
          onRewind: () => engine.seek(0),
          onForward: () => engine.seek(transport.positionSeconds + 10),
          tempo: transport.tempo,
          onTempoChange: (t) => engine.setTempo(t),
          timeSignature:
              TimeSignature(transport.timeSigNum, transport.timeSigDenom),
          currentTime: transport.positionSeconds,
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
          loopEnabled: transport.loopEnabled,
          onLoopToggle: () => engine.toggleLoop(),
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
          cpuUsage: metering.cpuUsage,
          memoryUsage: NativeFFI.instance.getMemoryUsage(),
          projectName: engine.project.name,
          menuCallbacks: MenuCallbacks(
            // ═══════════════════════════════════════════════════════════════
            // FILE MENU - All connected
            // ═══════════════════════════════════════════════════════════════
            onNewProject: () => _handleNewProject(engine),
            onOpenProject: () => _handleOpenProject(engine),
            onSaveProject: () => _handleSaveProject(engine),
            onSaveProjectAs: () => _handleSaveProjectAs(engine),
            onImportJSON: () => _handleImportJSON(),
            onExportJSON: () => _handleExportJSON(),
            onImportAudioFolder: () => _handleImportAudioFolder(),
            onImportAudioFiles: _openFilePicker,
            onExportAudio: () => _handleExportAudio(),
            // ═══════════════════════════════════════════════════════════════
            // EDIT MENU - All connected
            // ═══════════════════════════════════════════════════════════════
            onUndo: engine.canUndo ? () => engine.undo() : null,
            onRedo: engine.canRedo ? () => engine.redo() : null,
            onCut: () => _handleCut(),
            onCopy: () => _handleCopy(),
            onPaste: () => _handlePaste(),
            onDelete: () => _handleDelete(),
            onSelectAll: () => _handleSelectAll(),
            // ═══════════════════════════════════════════════════════════════
            // VIEW MENU - All connected
            // ═══════════════════════════════════════════════════════════════
            onToggleLeftPanel: () => setState(() => _leftVisible = !_leftVisible),
            onToggleRightPanel: () => setState(() => _rightVisible = !_rightVisible),
            onToggleLowerPanel: () => setState(() => _lowerVisible = !_lowerVisible),
            onResetLayout: () => _handleResetLayout(),
            // ═══════════════════════════════════════════════════════════════
            // PROJECT MENU - All connected
            // ═══════════════════════════════════════════════════════════════
            onProjectSettings: () => _handleProjectSettings(),
            onValidateProject: () => _handleValidateProject(),
            onBuildProject: () => _handleBuildProject(),
            // ═══════════════════════════════════════════════════════════════
            // STUDIO MENU - All connected
            // ═══════════════════════════════════════════════════════════════
            onAudioSettings: () => _handleAudioSettings(),
            onMidiSettings: () => _handleMidiSettings(),
            onPluginManager: () => _handlePluginManager(),
          ),

          // Left zone - mode-aware tree
          projectTree: _buildProjectTree(),
          activeLeftTab: _activeLeftTab,
          onLeftTabChange: (tab) => setState(() => _activeLeftTab = tab),
          onProjectDoubleClick: _handlePoolItemDoubleClick,

          // Center zone
          child: _buildCenterContent(transport, metering),

          // Inspector (for middleware mode)
          inspectorType: InspectedObjectType.event,
          inspectorName: 'Play_Music',
          inspectorSections: _buildInspectorSections(),

          // Lower zone - all tabs with mode-based filtering
          lowerTabs: _buildLowerTabs(metering, transport.isPlaying),
          lowerTabGroups: _buildTabGroups(),
          activeLowerTabId: _activeLowerTab,
          onLowerTabChange: (id) => setState(() => _activeLowerTab = id),

          // Zone visibility
          leftZoneVisible: _leftVisible,
          rightZoneVisible: _rightVisible,
          lowerZoneVisible: _lowerVisible,
          onLeftZoneToggle: () => setState(() => _leftVisible = !_leftVisible),
          onRightZoneToggle: () =>
              setState(() => _rightVisible = !_rightVisible),
          onLowerZoneToggle: () =>
              setState(() => _lowerVisible = !_lowerVisible),
        ),
        // Floating EQ windows
        ..._buildFloatingEqWindows(metering, transport.isPlaying),
          ],
        );
      },
    );
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

    return timeline_widget.Timeline(
      tracks: _tracks,
      clips: _clips,
      markers: _markers,
      crossfades: _crossfades,
      loopRegion: _loopRegion,
      loopEnabled: transport.loopEnabled,
      playheadPosition: transport.positionSeconds,
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
      // Playhead callbacks
      onPlayheadChange: (time) {
        final engine = context.read<EngineProvider>();
        engine.seek(time);
      },
      onPlayheadScrub: (time) {
        final engine = context.read<EngineProvider>();
        engine.seek(time);
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
        });
      },
      onClipMove: (clipId, newStartTime) {
        final clip = _clips.firstWhere((c) => c.id == clipId);
        // Notify engine
        engine.moveClip(
          clipId: clipId,
          targetTrackId: clip.trackId,
          startTime: newStartTime,
        );
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(startTime: newStartTime);
            }
            return c;
          }).toList();
        });
      },
      onClipMoveToTrack: (clipId, targetTrackId, newStartTime) {
        // Move clip to a different track
        engine.moveClip(
          clipId: clipId,
          targetTrackId: targetTrackId,
          startTime: newStartTime,
        );
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(
                trackId: targetTrackId,
                startTime: newStartTime,
              );
            }
            return c;
          }).toList();
        });
      },
      onClipMoveToNewTrack: (clipId, newStartTime) {
        // Create a new track - use engine's returned ID
        final trackIndex = _tracks.length;
        final trackName = 'Audio ${trackIndex + 1}';
        final color = _trackColors[trackIndex % _trackColors.length];

        // Create track in native engine - GET THE REAL ID
        final newTrackId = engine.createTrack(
          name: trackName,
          color: color.value,
          busId: 0,
        );

        // Create mixer channel for the new track (must use real engine ID)
        final mixerProvider = context.read<MixerProvider>();
        mixerProvider.createChannelFromTrack(newTrackId, trackName, color);

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
            ),
          ];

          // Update clip's track assignment
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(
                trackId: newTrackId,
                startTime: newStartTime,
              );
            }
            return c;
          }).toList();
        });
      },
      onClipResize: (clipId, newStartTime, newDuration, newOffset) {
        // Notify engine
        engine.resizeClip(
          clipId: clipId,
          startTime: newStartTime,
          duration: newDuration,
          sourceOffset: newOffset ?? 0.0,
        );
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(
                startTime: newStartTime,
                duration: newDuration,
                sourceOffset: newOffset ?? c.sourceOffset,
              );
            }
            return c;
          }).toList();
        });
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
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(fadeIn: fadeIn, fadeOut: fadeOut);
            }
            return c;
          }).toList();
        });
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
        // Notify engine
        engine.deleteClip(clipId);
        setState(() {
          _clips = _clips.where((c) => c.id != clipId).toList();
        });
      },
      // Track callbacks
      onTrackMuteToggle: (trackId) {
        final track = _tracks.firstWhere((t) => t.id == trackId);
        engine.updateTrack(trackId, muted: !track.muted);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(muted: !t.muted);
            }
            return t;
          }).toList();
        });
      },
      onTrackSoloToggle: (trackId) {
        final track = _tracks.firstWhere((t) => t.id == trackId);
        engine.updateTrack(trackId, soloed: !track.soloed);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(soloed: !t.soloed);
            }
            return t;
          }).toList();
        });
      },
      onTrackArmToggle: (trackId) {
        final track = _tracks.firstWhere((t) => t.id == trackId);
        engine.updateTrack(trackId, armed: !track.armed);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(armed: !t.armed);
            }
            return t;
          }).toList();
        });
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
        engine.updateTrack(trackId, color: color.value);
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(color: color);
            }
            return t;
          }).toList();
        });
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
      onTrackMonitorToggle: (trackId) {
        setState(() {
          _tracks = _tracks.map((t) {
            if (t.id == trackId) {
              return t.copyWith(inputMonitor: !t.inputMonitor);
            }
            return t;
          }).toList();
        });
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
      // Undo/Redo shortcuts (Cmd+Z, Cmd+Shift+Z)
      onUndo: engine.canUndo ? () => engine.undo() : null,
      onRedo: engine.canRedo ? () => engine.redo() : null,
    );
  }

  // Complete Wwise/FMOD-style action types
  static const List<String> kActionTypes = [
    'Play', 'PlayAndContinue', 'Stop', 'StopAll', 'Pause', 'PauseAll',
    'Resume', 'ResumeAll', 'Break', 'Mute', 'Unmute', 'SetVolume',
    'SetPitch', 'SetLPF', 'SetHPF', 'SetBusVolume', 'SetState',
    'SetSwitch', 'SetRTPC', 'ResetRTPC', 'Seek', 'Trigger', 'PostEvent',
  ];

  // Complete bus list
  static const List<String> kBuses = [
    'Master', 'Music', 'SFX', 'Voice', 'UI', 'Ambience', 'Reels', 'Wins', 'VO',
  ];

  // Complete event list
  static const List<String> kEvents = [
    'Play_Music', 'Stop_Music', 'Play_SFX', 'Stop_All', 'Pause_All',
    'Set_State', 'Trigger_Win', 'Spin_Start', 'Spin_Stop', 'Reel_Land',
    'BigWin_Start', 'BigWin_Loop', 'BigWin_End', 'Bonus_Enter', 'Bonus_Exit',
    'UI_Click', 'UI_Hover', 'Ambient_Start', 'Ambient_Stop', 'VO_Play',
  ];

  // Asset IDs
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

  // State groups (Wwise-style)
  static const List<String> kStateGroups = [
    'GameState', 'MusicState', 'PlayerState', 'BonusState', 'Intensity',
  ];

  // States per group
  static const Map<String, List<String>> kStates = {
    'GameState': ['Menu', 'BaseGame', 'Bonus', 'FreeSpins', 'Paused'],
    'MusicState': ['Normal', 'Suspense', 'Action', 'Victory', 'Defeat'],
    'PlayerState': ['Idle', 'Spinning', 'Winning', 'Waiting'],
    'BonusState': ['None', 'Triggered', 'Active', 'Ending'],
    'Intensity': ['Low', 'Medium', 'High', 'Extreme'],
  };

  // Switch groups
  static const List<String> kSwitchGroups = [
    'Surface', 'Footsteps', 'Material', 'Weapon', 'Environment',
  ];

  /// Middleware Mode: Events Editor in center - FULLY FUNCTIONAL
  Widget _buildMiddlewareCenterContent() {
    final event = _selectedEvent;
    final eventName = event?.name ?? 'No Event Selected';
    final actionCount = event?.actions.length ?? 0;

    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Column(
        children: [
          // Middleware Toolbar - Full command bar with all options - CONNECTED
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgMid,
              border: Border(bottom: BorderSide(color: ReelForgeTheme.borderSubtle)),
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
                    accentColor: ReelForgeTheme.accentOrange,
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: ReelForgeTheme.borderSubtle),
                  const SizedBox(width: 8),
                  // Action type dropdown - Updates header state
                  _ToolbarDropdown(
                    icon: Icons.flash_on,
                    label: 'Action',
                    value: _headerActionType,
                    options: kActionTypes,
                    onChanged: (val) => setState(() => _headerActionType = val),
                    accentColor: ReelForgeTheme.accentGreen,
                  ),
                  const SizedBox(width: 8),
                  // Asset ID dropdown
                  _ToolbarDropdown(
                    icon: Icons.audiotrack,
                    label: 'Asset',
                    value: _headerAssetId,
                    options: kAllAssetIds,
                    onChanged: (val) => setState(() => _headerAssetId = val),
                    accentColor: ReelForgeTheme.accentCyan,
                  ),
                  const SizedBox(width: 8),
                  // Bus dropdown
                  _ToolbarDropdown(
                    icon: Icons.speaker,
                    label: 'Bus',
                    value: _headerBus,
                    options: kAllBuses,
                    onChanged: (val) => setState(() => _headerBus = val),
                    accentColor: ReelForgeTheme.accentBlue,
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: ReelForgeTheme.borderSubtle),
                  const SizedBox(width: 8),
                  // Scope dropdown
                  _ToolbarDropdown(
                    icon: Icons.scatter_plot,
                    label: 'Scope',
                    value: _headerScope,
                    options: kScopes,
                    onChanged: (val) => setState(() => _headerScope = val),
                    accentColor: ReelForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  // Priority dropdown
                  _ToolbarDropdown(
                    icon: Icons.priority_high,
                    label: 'Priority',
                    value: _headerPriority,
                    options: kPriorities,
                    onChanged: (val) => setState(() => _headerPriority = val),
                    accentColor: ReelForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: ReelForgeTheme.borderSubtle),
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
                  Container(width: 1, height: 20, color: ReelForgeTheme.borderSubtle),
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
                    color: ReelForgeTheme.bgElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: ReelForgeTheme.borderSubtle),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'export',
                        height: 32,
                        child: Row(
                          children: [
                            Icon(Icons.upload, size: 14, color: ReelForgeTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text('Export to Clipboard', style: TextStyle(fontSize: 11, color: ReelForgeTheme.textPrimary)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        height: 32,
                        child: Row(
                          children: [
                            Icon(Icons.download, size: 14, color: ReelForgeTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text('Import from Clipboard', style: TextStyle(fontSize: 11, color: ReelForgeTheme.textPrimary)),
                          ],
                        ),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.import_export, size: 16, color: ReelForgeTheme.textSecondary),
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
              color: ReelForgeTheme.bgMid.withValues(alpha: 0.5),
              border: Border(bottom: BorderSide(color: ReelForgeTheme.borderSubtle)),
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
                          Icon(Icons.api, size: 16, color: ReelForgeTheme.accentOrange),
                          const SizedBox(width: 8),
                          Text('Event: $eventName', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ReelForgeTheme.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('$actionCount action(s) • Category: ${event?.category ?? "—"}', style: TextStyle(fontSize: 11, color: ReelForgeTheme.textSecondary)),
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
          color: ReelForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Center(
          child: Text('No event selected', style: TextStyle(color: ReelForgeTheme.textSecondary)),
        ),
      );
    }

    return Container(
      width: 950,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Row(
              children: const [
                SizedBox(width: 24, child: Text('#', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 110, child: Text('Action Type', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 130, child: Text('Asset ID', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 80, child: Text('Target Bus', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 50, child: Text('Gain', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 60, child: Text('Fade', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 80, child: Text('Curve', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 90, child: Text('Scope', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 32, child: Text('L', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 80, child: Text('Priority', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
                SizedBox(width: 50, child: Text('Actions', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
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
                  color: isSelected ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15) : Colors.transparent,
                  border: Border(bottom: BorderSide(color: ReelForgeTheme.borderSubtle, width: 0.5)),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text('${idx + 1}', style: TextStyle(fontSize: 11, color: ReelForgeTheme.textPrimary))),
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
                        color: ReelForgeTheme.accentCyan,
                        onChanged: (val) => _updateAction(idx, action.copyWith(assetId: val == '—' ? '' : val)),
                      ),
                    ),
                    // Bus dropdown - CONNECTED
                    SizedBox(
                      width: 80,
                      child: _CellDropdown(
                        value: action.bus,
                        options: kAllBuses,
                        color: ReelForgeTheme.accentBlue,
                        onChanged: (val) => _updateAction(idx, action.copyWith(bus: val)),
                      ),
                    ),
                    // Gain - display
                    SizedBox(
                      width: 50,
                      child: Text('${(action.gain * 100).toInt()}%', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textPrimary, fontFamily: 'monospace')),
                    ),
                    // Fade - display
                    SizedBox(
                      width: 60,
                      child: Text('${(action.fadeTime * 1000).toInt()}ms', style: TextStyle(fontSize: 10, color: ReelForgeTheme.textSecondary, fontFamily: 'monospace')),
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
                          color: action.loop ? ReelForgeTheme.accentGreen : ReelForgeTheme.textTertiary,
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
                            child: Icon(Icons.copy, size: 14, color: ReelForgeTheme.textTertiary),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _deleteAction(idx),
                            child: Icon(Icons.delete_outline, size: 14, color: ReelForgeTheme.textTertiary),
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
                  Icon(Icons.add_circle_outline, size: 14, color: ReelForgeTheme.accentOrange),
                  const SizedBox(width: 8),
                  Text('Add action...', style: TextStyle(fontSize: 11, color: ReelForgeTheme.accentOrange)),
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
        return ReelForgeTheme.accentGreen;
      case 'Stop':
      case 'StopAll':
      case 'Break':
        return ReelForgeTheme.errorRed;
      case 'Pause':
      case 'PauseAll':
        return ReelForgeTheme.accentOrange;
      case 'Resume':
      case 'ResumeAll':
        return ReelForgeTheme.accentCyan;
      case 'SetVolume':
      case 'SetBusVolume':
      case 'SetPitch':
        return ReelForgeTheme.accentBlue;
      case 'SetState':
      case 'SetSwitch':
      case 'SetRTPC':
        return const Color(0xFF845EF7); // Purple
      case 'Mute':
      case 'Unmute':
        return ReelForgeTheme.textSecondary;
      default:
        return ReelForgeTheme.textPrimary;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Highest':
        return ReelForgeTheme.errorRed;
      case 'High':
        return ReelForgeTheme.accentOrange;
      case 'Normal':
        return ReelForgeTheme.textPrimary;
      case 'Low':
        return ReelForgeTheme.textSecondary;
      case 'Lowest':
        return ReelForgeTheme.textTertiary;
      default:
        return ReelForgeTheme.textPrimary;
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

    return ConnectedClipEditor(
      selectedClipId: clip?.id,
      clipName: clip?.name,
      clipDuration: clip?.duration,
      clipWaveform: clip?.waveform,
      fadeIn: clip?.fadeIn ?? 0,
      fadeOut: clip?.fadeOut ?? 0,
      gain: clip?.gain ?? 0,
      clipColor: clip?.color,
      playheadPosition: transport.positionSeconds - (clip?.startTime ?? 0),
      snapEnabled: _snapEnabled,
      snapValue: _snapValue,
      onFadeInChange: (clipId, fadeIn) {
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
        setState(() {
          _clips = _clips.map((c) {
            if (c.id == clipId) {
              return c.copyWith(fadeOut: fadeOut);
            }
            return c;
          }).toList();
        });
      },
      onGainChange: (clipId, gain) {
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
      onPlayheadChange: (localPosition) {
        final clip = _selectedClip;
        if (clip != null) {
          engine.seek(clip.startTime + localPosition);
        }
      },
    );
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
        // Apply crossfade changes to timeline
        debugPrint('Crossfade config changed: duration=${config.duration}');
      },
      onAudition: () {
        // Start playback of crossfade region
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

  /// Convert bus ID to numeric track ID for FFI
  int _busIdToTrackId(String busId) {
    // Map bus IDs to numeric track IDs
    switch (busId) {
      case 'master': return 0;
      case 'sfx': return 1;
      case 'music': return 2;
      case 'voice': return 3;
      case 'amb': return 4;
      case 'ui': return 5;
      default:
        // Try to parse numeric ID from channel ID (ch_123)
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
      trackColor: ReelForgeTheme.warningOrange,
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
      color: ReelForgeTheme.bgDeepest,
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
        backgroundColor: ReelForgeTheme.bgElevated,
        title: Text('Output Routing', style: ReelForgeTheme.label),
        content: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: outputs.map((output) => ListTile(
              dense: true,
              title: Text(output, style: TextStyle(fontSize: 12, color: ReelForgeTheme.textPrimary)),
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
        NativeFFI.instance.routingAddSend(fromChannelId, toChannelId, preFader: false);
        break;

      case SlotDestinationType.bus:
        // Route output to bus
        debugPrint('[Mixer] Route $busId output to BUS $targetId');
        final fromId = _busIdToChannelId(busId);
        final toId = int.tryParse(targetId) ?? 0;
        NativeFFI.instance.routingSetOutputChannel(fromId, toId);
        break;
    }
  }

  /// Map plugin name to PluginInfo
  PluginInfo? _getPluginInfoByName(String name) {
    final plugins = {
      'RF-EQ 64': PluginInfo(
        id: 'rf-eq-64',
        name: 'RF-EQ 64',
        vendor: 'ReelForge',
        category: PluginCategory.eq,
        format: PluginFormat.internal,
      ),
      'RF-COMP': PluginInfo(
        id: 'rf-comp',
        name: 'RF-COMP',
        vendor: 'ReelForge',
        category: PluginCategory.dynamics,
        format: PluginFormat.internal,
      ),
      'RF-LIMIT': PluginInfo(
        id: 'rf-limit',
        name: 'RF-LIMIT',
        vendor: 'ReelForge',
        category: PluginCategory.dynamics,
        format: PluginFormat.internal,
      ),
      'RF-GATE': PluginInfo(
        id: 'rf-gate',
        name: 'RF-GATE',
        vendor: 'ReelForge',
        category: PluginCategory.dynamics,
        format: PluginFormat.internal,
      ),
      'RF-VERB': PluginInfo(
        id: 'rf-verb',
        name: 'RF-VERB',
        vendor: 'ReelForge',
        category: PluginCategory.reverb,
        format: PluginFormat.internal,
      ),
      'RF-DELAY': PluginInfo(
        id: 'rf-delay',
        name: 'RF-DELAY',
        vendor: 'ReelForge',
        category: PluginCategory.delay,
        format: PluginFormat.internal,
      ),
      'RF-SAT': PluginInfo(
        id: 'rf-sat',
        name: 'RF-SAT',
        vendor: 'ReelForge',
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
          backgroundColor: ReelForgeTheme.bgElevated,
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
                    color: ReelForgeTheme.bgSurface,
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
                          style: ReelForgeTheme.label,
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
                  color: ReelForgeTheme.errorRed,
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
          debugPrint('[Mixer] Replaced with ${plugin.name} on slot $insertIndex');
        }
      } else if (result == 'remove') {
        // Remove plugin
        setState(() {
          _busInserts[busId] = chain.removePlugin(insertIndex);
        });
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

        debugPrint('[Mixer] Inserted ${plugin.name} on slot $insertIndex');

        // Auto-open EQ editor in floating window if EQ was inserted
        if (plugin.category == PluginCategory.eq) {
          _openEqWindow(busId);
        }
      }
    }
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
    debugPrint('[EQ] Building floating windows, count: ${_openEqWindows.length}');
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
                  color: Colors.black.withOpacity(0.5),
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
                    onBandChange: (bandIndex, {enabled, freq, gain, q, filterType}) {
                      if (enabled != null) {
                        engineApi.proEqSetBandEnabled(channelId, bandIndex, enabled);
                      }
                      if (freq != null) {
                        engineApi.proEqSetBandFrequency(channelId, bandIndex, freq);
                      }
                      if (gain != null) {
                        engineApi.proEqSetBandGain(channelId, bandIndex, gain);
                      }
                      if (q != null) {
                        engineApi.proEqSetBandQ(channelId, bandIndex, q);
                      }
                      if (filterType != null) {
                        final shape = ProEqFilterShape.values[filterType.clamp(0, ProEqFilterShape.values.length - 1)];
                        engineApi.proEqSetBandShape(channelId, bandIndex, shape);
                      }
                    },
                    onBypassChange: (bypass) {
                      if (bypass) {
                        engineApi.proEqReset(channelId);
                      }
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
          onBandChange: (bandIndex, {enabled, freq, gain, q, filterType}) {
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
          },
          onBypassChange: (bypass) {
            // Pro EQ doesn't have global bypass, reset all bands instead
            if (bypass) {
              engineApi.proEqReset('master');
            }
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
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
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
                    color: Colors.grey[600],
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
          color: isSelected ? const Color(0xFF4A9EFF).withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF4A9EFF) : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF4A9EFF) : Colors.grey,
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
    final sampleRate = NativeFFI.instance.getSampleRate();

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
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flash_on, color: const Color(0xFFFF9040), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Transient Detection',
                        style: TextStyle(
                          color: Colors.white,
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
                    style: TextStyle(color: Colors.grey[500], fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  // Sensitivity slider
                  Text('Sensitivity', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Slider(
                    value: _transientSensitivity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => setState(() => _transientSensitivity = v),
                    activeColor: const Color(0xFFFF9040),
                  ),
                  // Algorithm selector
                  Text('Algorithm', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 4),
                  DropdownButton<int>(
                    value: _transientAlgorithm,
                    dropdownColor: const Color(0xFF1A1A20),
                    style: TextStyle(color: Colors.white, fontSize: 12),
                    underline: Container(height: 1, color: Colors.white24),
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
                        backgroundColor: const Color(0xFFFF9040),
                        foregroundColor: Colors.white,
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.music_note, color: const Color(0xFF40C8FF), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Pitch Detection',
                        style: TextStyle(
                          color: Colors.white,
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
                    style: TextStyle(color: Colors.grey[500], fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  // Detected pitch display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0C),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Detected Pitch', style: TextStyle(color: Colors.grey, fontSize: 10)),
                              Text(
                                _detectedPitch > 0 ? '${_detectedPitch.toStringAsFixed(1)} Hz' : '-- Hz',
                                style: TextStyle(
                                  color: const Color(0xFF40C8FF),
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
                              Text('MIDI Note', style: TextStyle(color: Colors.grey, fontSize: 10)),
                              Text(
                                _detectedMidi >= 0 ? _midiNoteToName(_detectedMidi) : '--',
                                style: TextStyle(
                                  color: const Color(0xFF40FF90),
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
                        backgroundColor: const Color(0xFF40C8FF),
                        foregroundColor: Colors.white,
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

  /// Get default EQ bands (for generic EQ - kept for backwards compatibility)
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
  void _syncEqToEngine() {
    // TODO: Call Rust engine via FFI when ready
    // engine.setMasterEq(_eqBands.map((b) => b.toMap()).toList());
    debugPrint('[EQ] Syncing ${_eqBands.length} bands to engine');
  }

  /// Build Loudness meter content (LUFS + True Peak)
  Widget _buildLoudnessContent(MeteringState metering) {
    return Container(
      color: ReelForgeTheme.bgDeep,
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
              color: ReelForgeTheme.bgMid,
              border: Border(
                left: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                    color: ReelForgeTheme.textSecondary,
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
                    color: ReelForgeTheme.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: ReelForgeTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Reading',
                        style: TextStyle(
                          fontSize: 9,
                          color: ReelForgeTheme.textTertiary,
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
                              color: ReelForgeTheme.textSecondary,
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
                              color: ReelForgeTheme.textPrimary,
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
                              color: ReelForgeTheme.textSecondary,
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
                                  : ReelForgeTheme.textPrimary,
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
                color: ReelForgeTheme.textSecondary,
              ),
            ),
          ),
          Text(
            lufs,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: ReelForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tp,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: ReelForgeTheme.textTertiary,
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
      LowerZoneTab(
        id: 'mixer',
        label: 'Mixer',
        icon: Icons.tune,
        content: _buildMixerContent(metering, isPlaying),
        groupId: 'mixconsole',
      ),
      // ========== Clip Editor (Editor group) ==========
      LowerZoneTab(
        id: 'clip-editor',
        label: 'Clip Editor',
        icon: Icons.edit,
        content: _buildClipEditorContent(),
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
        id: 'eq-morph',
        label: 'EQ Morph',
        icon: Icons.compare_arrows,
        content: EqMorphPanel(trackId: 0, sampleRate: 48000.0),
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
        id: 'min-phase-eq',
        label: 'Min Phase EQ',
        icon: Icons.show_chart,
        content: MinPhaseEqPanel(trackId: 0),
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
        content: const AudioPoolTabPlaceholder(),
        groupId: 'media',
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
        tabs: ['mixer'], // NOTE: timeline is in center zone, not lower
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
        tabs: ['eq', 'analog-eq', 'spectrum', 'loudness', 'meters', 'sidechain', 'multiband', 'analysis', 'timestretch', 'fx-presets', 'delay', 'reverb', 'dynamics', 'spatial', 'spectral', 'pitch', 'transient', 'saturation', 'eq-morph', 'wavelet', 'channel-strip', 'surround-panner', 'linear-phase-eq', 'stereo-eq', 'min-phase-eq', 'pro-eq', 'ultra-eq', 'room-correction', 'stereo-imager', 'convolution-ultra', 'gpu-settings', 'ml-processor', 'mastering', 'restoration'],
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
      // Tools - Validation, console, debug
      const TabGroup(
        id: 'tools',
        label: 'Tools',
        tabs: ['validation', 'console', 'drag-drop-lab', 'loading-states'],
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
                  color: ReelForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: ReelForgeTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: TextStyle(
                color: ReelForgeTheme.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

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
            color: active ? color : ReelForgeTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? color : ReelForgeTheme.textTertiary,
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
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: ReelForgeTheme.borderSubtle),
              ),
              child: Text(
                value,
                style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 11),
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
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: ReelForgeTheme.borderSubtle),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value,
                    style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 11),
                  ),
                  Icon(Icons.arrow_drop_down, size: 14, color: ReelForgeTheme.textSecondary),
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
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: ReelForgeTheme.borderSubtle),
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.accentBlue.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      suffix,
                      style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 10),
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
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: checked ? ReelForgeTheme.accentBlue : ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: checked ? ReelForgeTheme.accentBlue : ReelForgeTheme.borderSubtle,
              ),
            ),
            child: checked
                ? const Icon(Icons.check, size: 12, color: Colors.white)
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
          color: ReelForgeTheme.accentOrange,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
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
          child: Icon(icon, size: 16, color: ReelForgeTheme.textSecondary),
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
      color: ReelForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                  color: isSelected ? accentColor : ReelForgeTheme.textPrimary,
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
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: accentColor),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: ReelForgeTheme.textSecondary)),
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
      color: ReelForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: ReelForgeTheme.borderSubtle),
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
              color: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: ReelForgeTheme.textTertiary)),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(fontSize: 10, color: ReelForgeTheme.textPrimary)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 12, color: ReelForgeTheme.textSecondary),
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
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: ReelForgeTheme.textTertiary)),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(fontSize: 10, color: ReelForgeTheme.accentCyan, fontFamily: 'monospace')),
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
          color: value ? ReelForgeTheme.accentGreen.withValues(alpha: 0.2) : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? ReelForgeTheme.accentGreen : ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.loop : Icons.trending_flat,
              size: 12,
              color: value ? ReelForgeTheme.accentGreen : ReelForgeTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: value ? ReelForgeTheme.accentGreen : ReelForgeTheme.textSecondary)),
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
      color: ReelForgeTheme.bgElevated,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: ReelForgeTheme.borderSubtle),
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
              color: isSelected ? (color ?? ReelForgeTheme.accentBlue) : ReelForgeTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                style: TextStyle(fontSize: 10, color: color ?? ReelForgeTheme.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 12, color: ReelForgeTheme.textTertiary),
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
          Text(label, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 13)),
          Text(value, style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
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
          border: Border(bottom: BorderSide(color: ReelForgeTheme.borderSubtle)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color ?? ReelForgeTheme.textSecondary),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: color ?? ReelForgeTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
