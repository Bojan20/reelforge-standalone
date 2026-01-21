// FluxForge Slot Lab - Fullscreen Slot Audio Sandbox
//
// Premium "casino-grade" UI for slot game audio design.
// Inspired by Wwise + FMOD but 100% focused on slot games.
//
// ═══════════════════════════════════════════════════════════════════════════════
// SLOT LAB ↔ MIDDLEWARE UNIFIED DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════
//
// SINGLE SOURCE OF TRUTH: MiddlewareProvider.compositeEvents
//
// DATA FLOW:
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │  MIDDLEWARE (Actions Table)          │  SLOT LAB (Timeline)                 │
// │  └─ List view of layers              │  └─ Visual timeline with waveforms   │
// │  └─ Columns: Type, Asset, Bus, etc.  │  └─ Regions positioned by offsetMs   │
// │                                      │  └─ Duration from durationSeconds    │
// ├──────────────────────────────────────┴──────────────────────────────────────┤
// │                    SAME DATA: SlotCompositeEvent.layers                     │
// │                                                                             │
// │  SlotEventLayer:                                                            │
// │  ├─ audioPath    → Region audio + waveform                                  │
// │  ├─ offsetMs     → Region position on timeline                              │
// │  ├─ durationSeconds → Region width                                          │
// │  ├─ volume/pan   → Region display properties                                │
// │  └─ muted/solo   → Playback control                                         │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// PERSISTENCE:
// - waveformCache, clipIdCache → SlotLabProvider (survives screen switches)
// - tracks/regions → SlotLabProvider.persistedTracks
// - compositeEvents → MiddlewareProvider (single source)
//
// When layer is added in Middleware → appears on Slot Lab timeline
// When region is moved on timeline → updates layer.offsetMs in provider
// ═══════════════════════════════════════════════════════════════════════════════
//
// Features:
// - Audio tracks timeline with drag & drop
// - Stage markers ruler (SPIN_START, REEL_STOP, etc.)
// - Composite events editor
// - Bottom panel with Timeline, Bus, Profiler, RTPC, Resources, Aux tabs
// - Shared audio pool integration with DAW/Middleware
// - Real-time audio preview
// - Transport controls

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/native_file_picker.dart';
import '../services/audio_playback_service.dart';
import '../providers/middleware_provider.dart';
import '../providers/stage_provider.dart';
import '../providers/slot_lab_provider.dart';
import '../providers/ale_provider.dart';
import '../services/stage_audio_mapper.dart';
import '../models/stage_models.dart';
import '../models/middleware_models.dart';
import '../models/slot_audio_events.dart';
import '../theme/fluxforge_theme.dart';
import '../widgets/slot_lab/rtpc_editor_panel.dart';
import '../widgets/slot_lab/bus_hierarchy_panel.dart';
import '../widgets/slot_lab/profiler_panel.dart';
import '../widgets/slot_lab/volatility_dial.dart';
import '../widgets/slot_lab/scenario_controls.dart';
import '../widgets/slot_lab/resources_panel.dart';
import '../widgets/slot_lab/aux_sends_panel.dart';
import '../widgets/slot_lab/stage_trace_widget.dart';
import '../widgets/slot_lab/slot_preview_widget.dart';
import '../widgets/slot_lab/fullscreen_slot_preview.dart';
import '../widgets/slot_lab/event_log_panel.dart';
import '../widgets/slot_lab/audio_hover_preview.dart';
import '../widgets/slot_lab/forced_outcome_panel.dart';
import '../widgets/slot_lab/slot_lab_settings_panel.dart';
import '../widgets/glass/glass_slot_lab.dart';
import '../src/rust/native_ffi.dart';
import '../services/event_registry.dart';
import '../services/audio_pool.dart';
import '../services/slotlab_track_bridge.dart';
import '../services/waveform_cache_service.dart';
import '../controllers/slot_lab/timeline_drag_controller.dart';
import '../providers/undo_manager.dart';
import '../widgets/slot_lab/game_model_editor.dart';
import '../widgets/slot_lab/scenario_editor.dart';
import '../widgets/slot_lab/gdd_import_panel.dart';

// =============================================================================
// RTPC IDS FOR SLOT AUDIO
// =============================================================================

class SlotRtpcIds {
  static const int betLevel = 1;
  static const int tension = 2;
  static const int winMultiplier = 3;
  static const int featureProgress = 4;
  static const int reelSpeed = 5;
}

// =============================================================================
// STAGE MARKER MODEL
// =============================================================================

class _StageMarker {
  final double position; // 0.0 - 1.0
  final String name;
  final Color color;
  bool isSelected;

  _StageMarker({
    required this.position,
    required this.name,
    required this.color,
    this.isSelected = false,
  });
}

// =============================================================================
// AUDIO REGION MODEL
// =============================================================================

/// Layer within a region (for composite events with multiple sounds)
class _RegionLayer {
  final String id;
  final String? eventLayerId; // Maps to SlotEventLayer.id for syncing
  final String audioPath;
  final String name;
  final int? ffiClipId;
  double volume;
  double delay;
  double offset; // Individual horizontal offset within region (in seconds)
  double duration; // REAL audio file duration in seconds

  _RegionLayer({
    required this.id,
    this.eventLayerId,
    required this.audioPath,
    required this.name,
    this.ffiClipId,
    this.volume = 1.0,
    this.delay = 0.0,
    this.offset = 0.0,
    this.duration = 1.0, // Default, should be set from FFI/pool
  });
}

class _AudioRegion {
  String id;
  double start; // In seconds
  double end;   // In seconds
  String name;
  String? audioPath;
  Color color;
  List<double>? waveformData;
  bool isSelected;
  bool isMuted;
  bool isExpanded; // For expanding multi-layer regions

  /// Multiple layers for composite events (middleware-style)
  List<_RegionLayer> layers;

  _AudioRegion({
    required this.id,
    required this.start,
    required this.end,
    required this.name,
    this.audioPath,
    required this.color,
    this.waveformData,
    this.isSelected = false,
    this.isMuted = false,
    this.isExpanded = false,
    List<_RegionLayer>? layers,
  }) : layers = layers ?? [];

  double get duration => end - start;
  bool get hasMultipleLayers => layers.length > 1;
}

// =============================================================================
// AUDIO TRACK MODEL
// =============================================================================

class _SlotAudioTrack {
  String id;
  String name;
  Color color;
  List<_AudioRegion> regions;
  bool isMuted;
  bool isSolo;
  double volume;
  int outputBusId;

  _SlotAudioTrack({
    required this.id,
    required this.name,
    required this.color,
    List<_AudioRegion>? regions,
    this.isMuted = false,
    this.isSolo = false,
    this.volume = 1.0,
    this.outputBusId = 2, // Default to SFX bus
  }) : regions = regions ?? [];
}

// =============================================================================
// COMPOSITE EVENT MODEL
// =============================================================================
// NOTE: No wrapper classes needed - using SlotCompositeEvent and SlotEventLayer
// directly from MiddlewareProvider (single source of truth)
// =============================================================================

// =============================================================================
// BOTTOM PANEL TAB ENUM
// =============================================================================

enum _BottomPanelTab {
  timeline,
  busHierarchy,
  profiler,
  rtpc,
  resources,
  auxSends,
  eventLog,
  gameModel,
  scenarios,
  gddImport,
}

// =============================================================================
// SLOT LAB SCREEN
// =============================================================================

/// Fullscreen Slot Lab interface
class SlotLabScreen extends StatefulWidget {
  final VoidCallback onClose;
  final List<Map<String, dynamic>>? audioPool;

  const SlotLabScreen({
    super.key,
    required this.onClose,
    this.audioPool,
  });

  @override
  State<SlotLabScreen> createState() => _SlotLabScreenState();
}

class _SlotLabScreenState extends State<SlotLabScreen> with TickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  // Timeline drag controller (centralized drag state management)
  TimelineDragController? _dragController;
  TimelineDragController get dragController => _dragController!;

  // FFI instance
  final _ffi = NativeFFI.instance;

  // Bridge to DAW TRACK_MANAGER for unified playback
  final _trackBridge = SlotLabTrackBridge.instance;

  // Focus node for keyboard shortcuts
  final FocusNode _focusNode = FocusNode();

  // Slot Lab settings
  SlotLabSettings _slotLabSettings = const SlotLabSettings();

  // Game spec state (derived from settings for backward compatibility)
  int get _reelCount => _slotLabSettings.reels;
  int get _rowCount => _slotLabSettings.rows;
  VolatilityLevel get _volatilityLevel => _slotLabSettings.volatility;
  String get _volatility => _volatilityLevel.label;
  double _balance = 10000.0;
  double _bet = 1.0;
  double _lastWin = 0.0;
  bool _isSpinning = false;

  // Spin animation state
  int _currentStoppingReel = -1;
  bool _inAnticipation = false;
  Timer? _spinTimer;
  final math.Random _random = math.Random();

  // Timeline state
  double _timelineZoom = 1.0;
  double _timelineScrollX = 0.0;
  double _playheadPosition = 0.0; // In seconds
  bool _isPlaying = false;
  bool _isLooping = false;
  double? _loopStart;  // null = no loop region
  double? _loopEnd;
  double _timelineDuration = 10.0; // Total duration in seconds
  Timer? _playbackTimer;

  // Track state
  final List<_SlotAudioTrack> _tracks = [];
  int? _selectedTrackIndex;

  // Stage markers (empty by default - user adds them)
  final List<_StageMarker> _stageMarkers = [];

  // Composite events — MiddlewareProvider is the SINGLE SOURCE OF TRUTH
  // SlotLab only keeps UI state (expanded, selected)
  final Map<String, bool> _eventExpandedState = {};
  String? _selectedEventId;

  // ═══════════════════════════════════════════════════════════════════════════
  // ALL AVAILABLE STAGES — Complete list for dropdown
  // ═══════════════════════════════════════════════════════════════════════════
  static const List<String> _allStageOptions = [
    // ─── SPIN CYCLE (most common) ───
    'SPIN_START',
    'REEL_SPIN',
    'REEL_STOP',
    'REEL_STOP_0',
    'REEL_STOP_1',
    'REEL_STOP_2',
    'REEL_STOP_3',
    'REEL_STOP_4',
    // ─── WIN STAGES ───
    'WIN_PRESENT',
    'WIN_SMALL',
    'WIN_MEDIUM',
    'WIN_BIG',
    'WIN_MEGA',
    'WIN_EPIC',
    'WIN_ULTRA',
    'BIGWIN_TIER',
    // ─── ROLLUP ───
    'ROLLUP_START',
    'ROLLUP_TICK',
    'ROLLUP_END',
    // ─── ANTICIPATION ───
    'ANTICIPATION_ON',
    'ANTICIPATION_OFF',
    'ANTICIPATION_REEL_0',
    'ANTICIPATION_REEL_1',
    'ANTICIPATION_REEL_2',
    'ANTICIPATION_REEL_3',
    'ANTICIPATION_REEL_4',
    // ─── FEATURES ───
    'FEATURE_ENTER',
    'FEATURE_STEP',
    'FEATURE_EXIT',
    'FS_TRIGGER',
    'FS_SPIN',
    'FS_RETRIGGER',
    'FS_END',
    // ─── BONUS ───
    'BONUS_ENTER',
    'BONUS_STEP',
    'BONUS_EXIT',
    'BONUS_PICK',
    'BONUS_REVEAL',
    // ─── CASCADE/TUMBLE ───
    'CASCADE_START',
    'CASCADE_STEP',
    'CASCADE_END',
    'TUMBLE_DROP',
    'TUMBLE_LAND',
    // ─── WILDS & SCATTERS ───
    'WILD_LAND',
    'WILD_EXPAND',
    'WILD_STACK',
    'SCATTER_LAND',
    'SCATTER_LAND_3',
    'SCATTER_LAND_4',
    'SCATTER_LAND_5',
    // ─── MULTIPLIERS ───
    'MULT_INCREASE',
    'MULT_APPLY',
    'MULT_RESET',
    // ─── JACKPOT ───
    'JACKPOT_TRIGGER',
    'JACKPOT_MINI',
    'JACKPOT_MINOR',
    'JACKPOT_MAJOR',
    'JACKPOT_GRAND',
    // ─── HOLD & RESPIN ───
    'HOLD_TRIGGER',
    'HOLD_SPIN',
    'HOLD_LAND',
    'HOLD_END',
    // ─── UI EVENTS ───
    'UI_BUTTON_PRESS',
    'UI_BET_UP',
    'UI_BET_DOWN',
    'UI_SPIN_PRESS',
    // ─── MUSIC ───
    'MUSIC_BASE',
    'MUSIC_WIN',
    'MUSIC_FEATURE',
    // ─── AMBIENCE ───
    'AMBIENT_LOOP',
    'IDLE_LOOP',
  ];

  /// Check if stage is commonly used (for highlighting in dropdown)
  bool _isCommonStage(String stage) {
    return const {
      'SPIN_START', 'REEL_SPIN', 'REEL_STOP',
      'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2', 'REEL_STOP_3', 'REEL_STOP_4',
      'WIN_PRESENT', 'WIN_BIG', 'BIGWIN_TIER',
      'ANTICIPATION_ON', 'FEATURE_ENTER', 'BONUS_ENTER',
    }.contains(stage);
  }

  /// Get middleware provider (cached per frame for performance)
  MiddlewareProvider get _middleware =>
      Provider.of<MiddlewareProvider>(context, listen: false);

  /// Get composite events directly from MiddlewareProvider
  /// This is the SINGLE SOURCE OF TRUTH for all events
  List<SlotCompositeEvent> get _compositeEvents => _middleware.compositeEvents;

  /// Alias for _compositeEvents (for backward compatibility in helper methods)
  List<SlotCompositeEvent> get _middlewareEvents => _compositeEvents;

  /// Check if event is expanded (UI-only state)
  bool _isEventExpanded(String eventId) => _eventExpandedState[eventId] ?? false;

  /// Set event expanded state
  void _setEventExpanded(String eventId, bool expanded) {
    setState(() => _eventExpandedState[eventId] = expanded);
  }

  /// Get stage for event (first trigger stage, or derive from category/name)
  /// CRITICAL: Stage must be non-empty for EventRegistry to work
  String _getEventStage(SlotCompositeEvent event) {
    // First try explicit triggerStages
    if (event.triggerStages.isNotEmpty) {
      return event.triggerStages.first;
    }

    // Fallback: derive stage from category
    final category = event.category.toLowerCase();
    return switch (category) {
      'spin' => 'SPIN_START',
      'reelstop' => 'REEL_STOP',
      'anticipation' => 'ANTICIPATION_ON',
      'win' => 'WIN_PRESENT',
      'bigwin' => 'BIGWIN_TIER',
      'feature' => 'FEATURE_ENTER',
      'bonus' => 'BONUS_ENTER',
      'general' => event.name.toUpperCase().replaceAll(' ', '_'),
      _ => event.name.toUpperCase().replaceAll(' ', '_'),
    };
  }

  /// Find event by ID
  SlotCompositeEvent? _findEventById(String id) =>
      _middlewareEvents.where((e) => e.id == id).firstOrNull;

  /// Find event by name
  SlotCompositeEvent? _findEventByName(String name) =>
      _middlewareEvents.where((e) => e.name == name).firstOrNull;

  /// Find event index by ID
  int _findEventIndexById(String id) =>
      _middlewareEvents.indexWhere((e) => e.id == id);

  /// Find event index by name
  int _findEventIndexByName(String name) =>
      _middlewareEvents.indexWhere((e) => e.name == name);

  /// Add layer to event via MiddlewareProvider
  void _addLayerToMiddlewareEvent(String eventId, String audioPath, String name) {
    _middleware.addLayerToEvent(eventId, audioPath: audioPath, name: name);
    _syncEventToRegistry(_findEventById(eventId));
  }

  /// Remove layer from event via MiddlewareProvider
  void _removeLayerFromMiddlewareEvent(String eventId, String layerId) {
    _middleware.removeLayerFromEvent(eventId, layerId);
    _syncEventToRegistry(_findEventById(eventId));
  }

  /// Create new composite event via MiddlewareProvider
  SlotCompositeEvent _createMiddlewareEvent(String name, String stage) {
    final eventId = 'event_${DateTime.now().millisecondsSinceEpoch}';
    final event = SlotCompositeEvent(
      id: eventId,
      name: name,
      category: _categoryFromStage(stage),
      color: _colorFromStage(stage),
      layers: [],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      triggerStages: [stage],
    );
    _middleware.addCompositeEvent(event);
    return event;
  }

  /// Delete composite event via MiddlewareProvider
  void _deleteMiddlewareEvent(String eventId) {
    eventRegistry.unregisterEvent(eventId);
    _middleware.deleteCompositeEvent(eventId);
  }

  // Bottom panel
  _BottomPanelTab _selectedBottomTab = _BottomPanelTab.timeline;
  double _bottomPanelHeight = 280.0;
  bool _bottomPanelCollapsed = false;

  // Fullscreen preview mode
  bool _isPreviewMode = false;

  // Audio browser
  bool _showAudioBrowser = true;
  String _browserSearchQuery = '';
  String _selectedBrowserFolder = 'All';

  // Preview panel
  bool _showPreviewPanel = true;
  String? _previewingAudioPath;
  bool _isPreviewPlaying = false;

  // Track expansion state
  bool _allTracksExpanded = false;  // Default: collapsed

  // Drag state for audio browser
  String? _draggingAudioPath;
  Offset? _dragPosition;

  // Drag state for region repositioning
  _AudioRegion? _draggingRegion;
  int? _draggingRegionTrackIndex;
  double? _regionDragStartX;
  double? _regionDragOffsetX;

  // Drag state for individual layer repositioning within expanded region
  _RegionLayer? _draggingLayer;
  _AudioRegion? _draggingLayerRegion;
  String? _draggingLayerEventId; // Track by eventLayerId to survive rebuilds
  double? _layerDragStartOffset;
  double? _layerDragDelta;

  // Multi-selection state
  _AudioRegion? _lastClickedRegion; // For shift-click range selection
  int? _lastClickedTrackIndex;
  bool _isBoxSelecting = false;
  Offset? _boxSelectStart;
  Offset? _boxSelectEnd;

  // Undo/redo - original positions before drag
  Map<String, ({double start, double end})>? _dragStartPositions;

  // Event → Region mapping (for auto-update when layer added to event)
  final Map<String, String> _eventToRegionMap = {}; // eventId → regionId

  // Middleware sync tracking - to detect when actions added in Middleware mode
  final Map<String, int> _lastKnownActionCounts = {}; // eventId → actionCount

  // Playback tracking - which layers have been triggered in current playback
  final Set<String> _triggeredLayers = {}; // layer.id
  double _lastPlayheadPosition = 0.0;

  // Audio player tracking (using Rust engine via FFI)
  final Set<String> _activeLayerIds = {}; // layer.id → currently playing

  // Simulated reel symbols (fallback when engine not available)
  final List<List<String>> _fallbackReelSymbols = [
    ['7', 'BAR', 'BELL', 'CHERRY', 'WILD'],
    ['BAR', '7', 'BONUS', 'BELL', 'CHERRY'],
    ['CHERRY', 'WILD', '7', 'BAR', 'BELL'],
    ['BELL', 'CHERRY', 'BAR', 'BONUS', '7'],
    ['WILD', 'BELL', 'CHERRY', '7', 'BAR'],
  ];

  // Current reel symbols from engine (or fallback)
  List<List<String>> _reelSymbols = [];

  // Audio pool (loaded from FFI or demo data)
  List<Map<String, dynamic>> _audioPool = [];

  // Waveform cache: path → waveform data
  // Stored in SlotLabProvider for persistence across screen switches
  final Map<String, List<double>> _localWaveformCache = {}; // Fallback before provider init
  Map<String, List<double>> get _waveformCache =>
      _hasSlotLabProvider ? _slotLabProvider.waveformCache : _localWaveformCache;

  // Clip ID cache: path → clip ID (for waveform loading)
  // Stored in SlotLabProvider for persistence across screen switches
  final Map<String, int> _localClipIdCache = {}; // Fallback before provider init
  Map<String, int> get _clipIdCache =>
      _hasSlotLabProvider ? _slotLabProvider.clipIdCache : _localClipIdCache;

  // ─── Synthetic Slot Engine ────────────────────────────────────────────────
  SlotLabProvider? _slotLabProviderNullable;
  SlotLabProvider get _slotLabProvider => _slotLabProviderNullable!;
  bool get _hasSlotLabProvider => _slotLabProviderNullable != null;
  bool _engineInitialized = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();

    _initializeTracks();
    _loadAudioPool();
    _initializeSlotEngine();
    _restorePersistedState();
    _initWaveformCache();

    // Listen to MiddlewareProvider for bidirectional sync
    // When layers are added in Middleware center panel, Slot Lab updates automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Initialize drag controller with middleware reference
        _dragController = TimelineDragController(middleware: _middleware);
        _dragController!.addListener(_onDragControllerChanged);

        _middleware.addListener(_onMiddlewareChanged);
        _focusNode.requestFocus();
      }
    });
  }

  /// Callback when drag controller state changes
  void _onDragControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Callback when MiddlewareProvider changes (bidirectional sync)
  void _onMiddlewareChanged() {
    debugPrint('[SlotLab] _onMiddlewareChanged called, mounted=$mounted');
    if (mounted) {
      // Rebuild region layers to match updated events from MiddlewareProvider
      for (final event in _compositeEvents) {
        _rebuildRegionForEvent(event);
        // CRITICAL: Also sync to EventRegistry so stages trigger audio
        _syncEventToRegistry(event);
      }
      setState(() {});
      debugPrint('[SlotLab] Synced ${_compositeEvents.length} events from MiddlewareProvider (+ EventRegistry)');
    }
  }

  /// Restore state from provider (survives screen switches)
  void _restorePersistedState() {
    // Delay to ensure provider is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Wait a frame for _initializeSlotEngine to complete
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || !_hasSlotLabProvider) return;
        _doRestorePersistedState();
      });
    });
  }

  /// Initialize waveform disk cache and restore any cached waveforms
  void _initWaveformCache() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Initialize disk cache service
      await WaveformCacheService.instance.init();

      // If provider has waveform cache, save it to disk
      if (_hasSlotLabProvider && _slotLabProvider.waveformCache.isNotEmpty) {
        await WaveformCacheService.instance.importFromProvider(_slotLabProvider.waveformCache);
      }

      // Preload waveforms for current audio pool
      final audioPaths = _audioPool
          .map((item) => item['path'] as String?)
          .where((path) => path != null && path.isNotEmpty)
          .cast<String>()
          .toList();

      if (audioPaths.isNotEmpty) {
        await WaveformCacheService.instance.preload(audioPaths);

        // Load any found disk cache entries into provider
        for (final path in audioPaths) {
          final waveform = await WaveformCacheService.instance.get(path);
          if (waveform != null && _hasSlotLabProvider) {
            _slotLabProvider.waveformCache[path] = waveform;
          }
        }

        if (mounted) setState(() {});
        debugPrint('[SlotLab] Waveform cache initialized (${audioPaths.length} paths)');
      }
    });
  }

  void _doRestorePersistedState() {
    try {
      final provider = _slotLabProvider;

      // Restore audio pool
      if (provider.persistedAudioPool.isNotEmpty) {
        setState(() {
          _audioPool = List.from(provider.persistedAudioPool);
        });
      }

      // Restore composite events UI state (expanded) - events themselves come from MiddlewareProvider
      if (provider.persistedCompositeEvents.isNotEmpty) {
        for (final eventData in provider.persistedCompositeEvents) {
          final eventId = eventData['id'] as String;
          final isExpanded = eventData['isExpanded'] as bool? ?? false;
          _eventExpandedState[eventId] = isExpanded;
        }
        // Re-sync to event registry (events from MiddlewareProvider)
        _syncAllEventsToRegistry();
      }

      // Restore tracks
      if (provider.persistedTracks.isNotEmpty) {
        setState(() {
          _tracks.clear();
          for (final trackData in provider.persistedTracks) {
            _tracks.add(_SlotAudioTrack(
              id: trackData['id'] as String,
              name: trackData['name'] as String,
              color: Color(trackData['color'] as int),
              isMuted: trackData['isMuted'] as bool? ?? false,
              isSolo: trackData['isSolo'] as bool? ?? false,
              volume: (trackData['volume'] as num?)?.toDouble() ?? 1.0,
              regions: (trackData['regions'] as List<dynamic>?)?.map((r) {
                final regionData = r as Map<String, dynamic>;
                return _AudioRegion(
                  id: regionData['id'] as String,
                  name: regionData['name'] as String,
                  start: (regionData['start'] as num).toDouble(),
                  end: (regionData['end'] as num).toDouble(),
                  color: Color(regionData['color'] as int),
                  layers: (regionData['layers'] as List<dynamic>?)?.map((l) {
                    final layerData = l as Map<String, dynamic>;
                    return _RegionLayer(
                      id: layerData['id'] as String,
                      eventLayerId: layerData['eventLayerId'] as String?,
                      audioPath: layerData['audioPath'] as String,
                      name: layerData['name'] as String,
                      volume: (layerData['volume'] as num?)?.toDouble() ?? 1.0,
                      delay: (layerData['delay'] as num?)?.toDouble() ?? 0.0,
                      offset: (layerData['offset'] as num?)?.toDouble() ?? 0.0,
                      duration: (layerData['duration'] as num?)?.toDouble() ?? 1.0,
                    );
                  }).toList() ?? [],
                );
              }).toList() ?? [],
            ));
          }
        });
      }

      // Restore event to region mapping
      if (provider.persistedEventToRegionMap.isNotEmpty) {
        _eventToRegionMap.clear();
        _eventToRegionMap.addAll(provider.persistedEventToRegionMap);
      }

      // Count total regions
      int totalRegions = 0;
      for (final track in _tracks) {
        totalRegions += track.regions.length;
      }
      debugPrint('[SlotLab] Restored persisted state: ${_audioPool.length} audio, ${_compositeEvents.length} events, ${_tracks.length} tracks, $totalRegions regions');
      debugPrint('[SlotLab] persistedTracks had ${provider.persistedTracks.length} tracks');

      // CRITICAL: Sync region layers to match event layers (remove stale data)
      _syncAllRegionsToEvents();

      // Sync with MiddlewareProvider to get any changes made in Middleware mode
      _syncFromMiddlewareProvider();
    } catch (e) {
      debugPrint('[SlotLab] Error restoring state: $e');
    }
  }

  /// Sync ALL region layers to match their corresponding event layers
  /// Called after restore to sync with MiddlewareProvider changes
  void _syncAllRegionsToEvents() {
    for (final track in _tracks) {
      for (final region in track.regions) {
        // Find matching event by name
        final event = _compositeEvents.where((e) => e.name == region.name).firstOrNull;

        if (event == null) {
          // Event not found - DON'T clear layers, keep persisted state
          // Event might be loaded later or timing issue
          continue;
        }

        // Get event layer IDs for comparison (use ID, not audioPath - allows duplicates)
        final eventLayerIds = event.layers.map((l) => l.id).toSet();

        // Remove region layers whose eventLayerId no longer exists in event
        region.layers.removeWhere((rl) => rl.eventLayerId != null && !eventLayerIds.contains(rl.eventLayerId));

        // ADD new layers from event that don't exist in region (by eventLayerId)
        for (final eventLayer in event.layers) {
          final existsInRegion = region.layers.any((rl) => rl.eventLayerId == eventLayer.id);
          if (!existsInRegion) {
            final dur = _getAudioDuration(eventLayer.audioPath);
            region.layers.add(_RegionLayer(
              id: 'layer_${DateTime.now().millisecondsSinceEpoch}_${region.layers.length}',
              eventLayerId: eventLayer.id, // Track which event layer this maps to
              audioPath: eventLayer.audioPath,
              name: eventLayer.name,
              volume: eventLayer.volume,
              delay: eventLayer.offsetMs.toDouble(),
              duration: dur > 0 ? dur : 1.0,
            ));
          }
        }

        // Update region end time if needed
        double maxEnd = region.start + 1.0;
        for (final layer in region.layers) {
          final layerEnd = region.start + layer.delay + layer.duration;
          if (layerEnd > maxEnd) maxEnd = layerEnd;
        }
        region.end = maxEnd;
      }
    }
  }

  /// Sync events from MiddlewareProvider (updates made in Middleware timeline mode)
  /// NOTE: MiddlewareProvider is now the single source of truth for composite events.
  /// This rebuilds regions to match current event layers.
  void _syncFromMiddlewareProvider() {
    if (!mounted) return;

    try {
      // Sync all events to registry
      _syncAllEventsToRegistry();

      // CRITICAL: Rebuild ALL regions to match current event layers from MiddlewareProvider
      // This ensures changes made in Middleware mode are reflected in Slot Lab timeline
      for (final event in _compositeEvents) {
        _rebuildRegionForEvent(event);
      }

      debugPrint('[SlotLab] Synced ${_middlewareEvents.length} events from MiddlewareProvider (rebuilt regions)');
    } catch (e) {
      debugPrint('[SlotLab] Error syncing from MiddlewareProvider: $e');
    }
  }

  /// Check if any event in MiddlewareProvider has new actions and sync to timeline
  void _checkMiddlewareChangesAndSync(MiddlewareProvider middleware) {
    for (final mwEvent in middleware.events) {
      final currentActionCount = mwEvent.actions.length;
      final lastKnownCount = _lastKnownActionCounts[mwEvent.id] ?? 0;

      // Detect new actions added
      if (currentActionCount > lastKnownCount) {
        debugPrint('[SlotLab] Middleware event "${mwEvent.name}" has new actions: $lastKnownCount → $currentActionCount');

        // Find if this event is on our timeline - try by ID first, then by name
        String? regionId = _eventToRegionMap[mwEvent.id];

        // If not found by ID, try to find by event name matching region name
        if (regionId == null) {
          for (final track in _tracks) {
            for (final region in track.regions) {
              if (region.name == mwEvent.name) {
                regionId = region.id;
                // Cache this mapping for future
                _eventToRegionMap[mwEvent.id] = regionId;
                debugPrint('[SlotLab] Found region by name match: ${mwEvent.name} → $regionId');
                break;
              }
            }
            if (regionId != null) break;
          }
        }

        if (regionId != null) {
          // Find the region on timeline
          for (final track in _tracks) {
            final regionIndex = track.regions.indexWhere((r) => r.id == regionId);
            if (regionIndex >= 0) {
              // Sync the new layers to the region
              debugPrint('[SlotLab] Syncing to region: $regionId on track ${track.name}');
              _syncEventLayersToRegion(mwEvent, track.regions[regionIndex], track);
              break;
            }
          }
        } else {
          debugPrint('[SlotLab] No matching region found for event "${mwEvent.name}"');
        }

        // Update known count
        _lastKnownActionCounts[mwEvent.id] = currentActionCount;
      } else if (currentActionCount != lastKnownCount) {
        // Just update the count (actions may have been removed)
        _lastKnownActionCounts[mwEvent.id] = currentActionCount;
      }
    }
  }

  /// Sync layers from MiddlewareEvent to an existing region on timeline
  /// INCREMENTAL: Only adds NEW layers, preserves existing ones
  /// Loads REAL waveform and duration via FFI for accurate display
  void _syncEventLayersToRegion(MiddlewareEvent mwEvent, _AudioRegion region, _SlotAudioTrack track) {
    debugPrint('[SlotLab] ═══ SYNC START: "${mwEvent.name}" → region "${region.id}" ═══');
    debugPrint('[SlotLab] Audio pool: ${_audioPool.length} files, Region layers: ${region.layers.length}');

    // Get existing layer IDs and audio paths to avoid duplicates
    final existingLayerIds = region.layers.map((l) => l.id).toSet();
    final existingPaths = region.layers.map((l) => l.audioPath).toSet();

    // Find NEW layers from middleware actions
    final newLayers = <_RegionLayer>[];
    double maxEndTime = region.end - region.start; // Current duration

    // Get FFI track ID from track.id
    int ffiTrackId = 0;
    if (track.id.startsWith('ffi_')) {
      ffiTrackId = int.tryParse(track.id.substring(4)) ?? 0;
    }

    for (final action in mwEvent.actions) {
      // Skip if this action is already synced (by ID)
      if (existingLayerIds.contains(action.id)) {
        debugPrint('[SlotLab] Skip: action ${action.id} already synced');
        continue;
      }

      // Skip empty asset IDs
      if (action.assetId.isEmpty || action.assetId == '—') {
        debugPrint('[SlotLab] Skip: empty assetId');
        continue;
      }

      debugPrint('[SlotLab] Processing NEW action: "${action.assetId}"');

      // Resolve assetId to full path
      String audioPath = action.assetId;
      double audioDuration = 0.0;
      int clipId = 0;

      // Try to find in audio pool
      Map<String, dynamic>? poolFile = _findInAudioPool(action.assetId);

      if (poolFile != null) {
        audioPath = poolFile['path'] as String? ?? action.assetId;
        audioDuration = (poolFile['duration'] as num?)?.toDouble() ?? 0.0;
        clipId = poolFile['clipId'] as int? ?? 0;
        debugPrint('[SlotLab] Found in pool: "$audioPath", dur=$audioDuration, clipId=$clipId');
      }

      // Skip if we already have a layer with this audioPath
      if (existingPaths.contains(audioPath)) {
        debugPrint('[SlotLab] Skip: path already exists');
        continue;
      }

      // If no clipId or duration, import via FFI to get REAL data
      if (clipId <= 0 || audioDuration <= 0) {
        if (_ffi.isLoaded && audioPath.isNotEmpty) {
          try {
            // Import audio to get real clipId
            // CRITICAL: Use SlotLab preview track (99999) if no FFI track assigned
            // to avoid conflicting with DAW tracks (0, 1, 2...)
            const slotLabPreviewTrack = 99999;
            clipId = _ffi.importAudio(audioPath, ffiTrackId > 0 ? ffiTrackId : slotLabPreviewTrack, action.delay);
            if (clipId > 0) {
              _clipIdCache[audioPath] = clipId;
              debugPrint('[SlotLab] FFI imported: clipId=$clipId');

              // Get REAL duration from FFI metadata
              if (audioDuration <= 0) {
                audioDuration = _getAudioDuration(audioPath);
                debugPrint('[SlotLab] FFI duration: ${audioDuration}s');
              }
            }
          } catch (e) {
            debugPrint('[SlotLab] FFI import error: $e');
          }
        }
      }

      // Fallback duration if still unknown
      if (audioDuration <= 0) audioDuration = 1.0;

      // Calculate layer end time
      final layerEndTime = action.delay + audioDuration;
      if (layerEndTime > maxEndTime) {
        maxEndTime = layerEndTime;
      }

      final layerName = audioPath.split('/').last.replaceAll(RegExp(r'\.(wav|mp3|ogg|flac)$', caseSensitive: false), '');

      newLayers.add(_RegionLayer(
        id: action.id.isNotEmpty ? action.id : 'layer_${DateTime.now().millisecondsSinceEpoch}_${newLayers.length}',
        audioPath: audioPath,
        name: layerName,
        ffiClipId: clipId > 0 ? clipId : null,
        volume: action.gain,
        delay: action.delay,
        offset: action.delay,
        duration: audioDuration, // REAL duration from FFI/pool
      ));

      debugPrint('[SlotLab] Added layer: "$layerName", clipId=$clipId, dur=${audioDuration}s');
    }

    // If no new layers, nothing to do
    if (newLayers.isEmpty) {
      debugPrint('[SlotLab] ═══ SYNC END: No new layers ═══');
      return;
    }

    // MERGE existing layers with new layers
    final trackIndex = _tracks.indexOf(track);
    final regionIndex = track.regions.indexOf(region);

    if (trackIndex >= 0 && regionIndex >= 0) {
      setState(() {
        final mergedLayers = [...region.layers, ...newLayers];
        final newEnd = region.start + maxEndTime;

        _tracks[trackIndex].regions[regionIndex] = _AudioRegion(
          id: region.id,
          start: region.start,
          end: newEnd > region.end ? newEnd : region.end,
          name: region.name,
          audioPath: mergedLayers.isNotEmpty ? mergedLayers.first.audioPath : region.audioPath,
          color: region.color,
          waveformData: region.waveformData, // Waveform loaded via _getWaveformForPath per-layer
          isSelected: region.isSelected,
          isMuted: region.isMuted,
          isExpanded: mergedLayers.length > 1, // Auto-expand when multiple layers
          layers: mergedLayers,
        );
      });
      debugPrint('[SlotLab] ═══ SYNC END: Added ${newLayers.length} layers. Total: ${region.layers.length + newLayers.length} ═══');
    }
  }

  /// Helper to find file in audio pool with multiple strategies
  Map<String, dynamic>? _findInAudioPool(String assetId) {
    // Strategy 1: Exact name match
    var poolFile = _audioPool.cast<Map<String, dynamic>?>().firstWhere(
      (f) => f != null && (f['name'] as String?) == assetId,
      orElse: () => null,
    );
    if (poolFile != null) return poolFile;

    // Strategy 2: Full path match
    poolFile = _audioPool.cast<Map<String, dynamic>?>().firstWhere(
      (f) => f != null && (f['path'] as String?) == assetId,
      orElse: () => null,
    );
    if (poolFile != null) return poolFile;

    // Strategy 3: Filename (without extension) match
    final assetName = assetId.split('/').last.replaceAll(RegExp(r'\.(wav|mp3|ogg|flac)$', caseSensitive: false), '');
    poolFile = _audioPool.cast<Map<String, dynamic>?>().firstWhere(
      (f) {
        if (f == null) return false;
        final poolName = (f['name'] as String? ?? '').replaceAll(RegExp(r'\.(wav|mp3|ogg|flac)$', caseSensitive: false), '');
        return poolName == assetName;
      },
      orElse: () => null,
    );
    if (poolFile != null) return poolFile;

    // Strategy 4: Path ends with assetId
    poolFile = _audioPool.cast<Map<String, dynamic>?>().firstWhere(
      (f) {
        if (f == null) return false;
        final path = f['path'] as String? ?? '';
        return path.endsWith('/$assetId') || path.endsWith(assetId);
      },
      orElse: () => null,
    );
    return poolFile;
  }

  /// Persist state to provider (survives screen switches)
  void _persistState() {
    // Try to get provider - use cached reference or fetch from context
    SlotLabProvider? provider;
    if (_hasSlotLabProvider) {
      provider = _slotLabProvider;
    } else {
      // Fallback: try to get from context (may fail during dispose)
      try {
        provider = Provider.of<SlotLabProvider>(context, listen: false);
      } catch (e) {
        debugPrint('[SlotLab] Cannot persist state: no provider available');
        return;
      }
    }
    try {

      // Persist audio pool
      provider.persistedAudioPool = List.from(_audioPool);

      // Persist composite events
      provider.persistedCompositeEvents = _compositeEvents.map((event) => {
        'id': event.id,
        'name': event.name,
        'stage': _getEventStage(event),
        'isExpanded': _isEventExpanded(event.id),
        'layers': event.layers.map((layer) => {
          'id': layer.id,
          'audioPath': layer.audioPath,
          'name': layer.name,
          'volume': layer.volume,
          'pan': layer.pan,
          'delay': layer.offsetMs,
          'busId': layer.busId,
        }).toList(),
      }).toList();

      // Persist tracks
      provider.persistedTracks = _tracks.map((track) => {
        'id': track.id,
        'name': track.name,
        'color': track.color.value,
        'isMuted': track.isMuted,
        'isSolo': track.isSolo,
        'volume': track.volume,
        'regions': track.regions.map((region) => {
          'id': region.id,
          'name': region.name,
          'start': region.start,
          'end': region.end,
          'color': region.color.value,
          'layers': region.layers.map((layer) => {
            'id': layer.id,
            'eventLayerId': layer.eventLayerId,
            'audioPath': layer.audioPath,
            'name': layer.name,
            'volume': layer.volume,
            'delay': layer.delay,
            'offset': layer.offset,
            'duration': layer.duration,
          }).toList(),
        }).toList(),
      }).toList();

      // Persist event to region mapping
      provider.persistedEventToRegionMap = Map.from(_eventToRegionMap);

      // Count total regions
      int totalRegions = 0;
      for (final track in _tracks) {
        totalRegions += track.regions.length;
      }
      debugPrint('[SlotLab] Persisted state: ${_audioPool.length} audio, ${_compositeEvents.length} events, ${_tracks.length} tracks, $totalRegions regions');
    } catch (e) {
      debugPrint('[SlotLab] Error persisting state: $e');
    }
  }

  void _initializeSlotEngine() {
    // Get or create SlotLabProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _slotLabProviderNullable = Provider.of<SlotLabProvider>(context, listen: false);

        // Migrate local cache to provider (in case anything was cached before init)
        if (_localWaveformCache.isNotEmpty) {
          _slotLabProvider.waveformCache.addAll(_localWaveformCache);
          _localWaveformCache.clear();
        }
        if (_localClipIdCache.isNotEmpty) {
          _slotLabProvider.clipIdCache.addAll(_localClipIdCache);
          _localClipIdCache.clear();
        }

        // Initialize engine for audio testing mode
        _engineInitialized = _slotLabProvider.initialize(audioTestMode: true);

        if (_engineInitialized) {
          // Connect to middleware for audio triggering
          final middleware = Provider.of<MiddlewareProvider>(context, listen: false);
          _slotLabProvider.connectMiddleware(middleware);

          // Connect to ALE for signal sync
          try {
            final ale = Provider.of<AleProvider>(context, listen: false);
            _slotLabProvider.connectAle(ale);
          } catch (e) {
            debugPrint('[SlotLab] ALE not available: $e');
          }

          // Set bet amount from UI
          _slotLabProvider.setBetAmount(_bet);

          // Listen to provider changes
          _slotLabProvider.addListener(_onSlotLabUpdate);

          debugPrint('[SlotLab] Synthetic engine initialized');
        } else {
          debugPrint('[SlotLab] Engine init failed, using fallback');
        }

        // Initialize reel symbols (fallback or empty for engine)
        _reelSymbols = List.from(_fallbackReelSymbols);
        setState(() {});
      } catch (e) {
        debugPrint('[SlotLab] Engine init error: $e');
        _engineInitialized = false;
        _reelSymbols = List.from(_fallbackReelSymbols);
      }
    });
  }

  void _onSlotLabUpdate() {
    if (!mounted) return;

    // Update reel symbols from engine result
    final grid = _slotLabProvider.currentGrid;
    if (grid != null && grid.isNotEmpty) {
      setState(() {
        _reelSymbols = _gridToSymbols(grid);
        _lastWin = _slotLabProvider.lastWinAmount;
        if (_slotLabProvider.lastSpinWasWin) {
          _balance += _lastWin;
        }
        _isSpinning = _slotLabProvider.isSpinning;
      });
    }
  }

  /// Convert engine grid (symbol IDs) to display symbols
  List<List<String>> _gridToSymbols(List<List<int>> grid) {
    const symbolMap = {
      0: 'BLANK',
      1: '7',
      2: 'BAR',
      3: 'BELL',
      4: 'CHERRY',
      5: 'WILD',
      6: 'BONUS',
      7: 'SCATTER',
      8: 'DIAMOND',
      9: 'STAR',
    };

    return grid.map((reel) {
      return reel.map((id) => symbolMap[id] ?? '?').toList();
    }).toList();
  }

  @override
  void didUpdateWidget(covariant SlotLabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload audio pool if parent's pool changed
    if (widget.audioPool != oldWidget.audioPool) {
      debugPrint('[SlotLab] Parent audio pool changed, reloading...');
      _loadAudioPool();
    }
  }

  void _loadAudioPool() {
    debugPrint('[SlotLab] _loadAudioPool called, parent pool: ${widget.audioPool?.length ?? 0} items');

    // First try to use audio pool passed from parent (DAW mode's pool)
    if (widget.audioPool != null && widget.audioPool!.isNotEmpty) {
      setState(() {
        _audioPool = widget.audioPool!.map<Map<String, dynamic>>((item) {
          // Determine folder from path or name
          final path = item['path'] as String? ?? '';
          final name = item['name'] as String? ?? path.split('/').last;
          String folder = 'SFX';
          final lowerPath = path.toLowerCase();
          final lowerName = name.toLowerCase();
          if (lowerPath.contains('music') || lowerName.contains('music')) {
            folder = 'Music';
          } else if (lowerPath.contains('ambience') || lowerPath.contains('amb')) {
            folder = 'Ambience';
          } else if (lowerPath.contains('voice') || lowerPath.contains('vo')) {
            folder = 'Voice';
          } else if (lowerPath.contains('ui') || lowerName.contains('button') || lowerName.contains('click')) {
            folder = 'UI';
          }

          return {
            'path': path,
            'name': name,
            'duration': (item['duration'] as num?)?.toDouble() ?? 1.0,
            'folder': folder,
            'sampleRate': item['sampleRate'] ?? item['sample_rate'] ?? 48000,
            'channels': item['channels'] ?? 2,
          };
        }).toList();
      });
      debugPrint('[SlotLab] Loaded ${_audioPool.length} audio files from parent');
      return;
    }

    // Fallback: try FFI
    try {
      final json = _ffi.audioPoolList();
      final list = jsonDecode(json) as List;
      if (list.isNotEmpty) {
        setState(() {
          _audioPool = list.map<Map<String, dynamic>>((e) {
            final item = e as Map<String, dynamic>;
            final path = item['path'] as String? ?? '';
            String folder = 'SFX';
            if (path.contains('music')) folder = 'Music';
            else if (path.contains('ambience') || path.contains('amb')) folder = 'Ambience';
            else if (path.contains('voice') || path.contains('vo')) folder = 'Voice';
            else if (path.contains('ui')) folder = 'UI';

            return {
              'path': path,
              'name': item['name'] ?? path.split('/').last,
              'duration': (item['duration'] as num?)?.toDouble() ?? 1.0,
              'folder': folder,
              'sampleRate': item['sample_rate'] ?? 48000,
              'channels': item['channels'] ?? 2,
            };
          }).toList();
        });
        debugPrint('[SlotLab] Loaded ${_audioPool.length} audio files from FFI');
        return;
      }
    } catch (e) {
      debugPrint('[SlotLab] FFI audio pool error: $e');
    }

    // Keep existing audio pool if we have one (don't clear user's imported files)
    // Only initialize to empty if pool is truly uninitialized
    if (_audioPool.isEmpty) {
      debugPrint('[SlotLab] No external audio pool, keeping local pool (${_audioPool.length} files)');
    } else {
      debugPrint('[SlotLab] Preserving existing local pool with ${_audioPool.length} files');
    }
  }

  /// Import audio files via native file picker (faster than file_picker plugin)
  Future<void> _importAudioFiles() async {
    try {
      final paths = await NativeFilePicker.pickAudioFiles();

      if (paths.isNotEmpty) {
        // Batch add - collect all entries first, then single setState
        final newEntries = <Map<String, dynamic>>[];
        for (final path in paths) {
          if (_audioPool.any((a) => a['path'] == path)) continue; // Skip duplicates
          final name = path.split('/').last;
          newEntries.add(_createAudioPoolEntry(path, name));
        }
        if (newEntries.isNotEmpty) {
          setState(() {
            _audioPool.addAll(newEntries);
          });
          _persistState();
          debugPrint('[SlotLab] Batch added ${newEntries.length} files');
        }
      }
    } catch (e) {
      debugPrint('[SlotLab] File picker error: $e');
    }
  }

  /// Import entire folder of audio files (native picker - faster)
  Future<void> _importAudioFolder() async {
    try {
      final result = await NativeFilePicker.pickAudioFolder();

      if (result != null) {
        final dir = Directory(result);
        final audioExtensions = ['.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif', '.m4a', '.wma'];

        // Collect all audio files (sync listSync is faster for local dirs)
        final List<FileSystemEntity> entities;
        try {
          entities = dir.listSync(recursive: true);
        } catch (e) {
          debugPrint('[SlotLab] Error listing directory: $e');
          return;
        }

        final audioFiles = <File>[];
        for (final entity in entities) {
          if (entity is File) {
            final ext = entity.path.toLowerCase().split('.').last;
            if (audioExtensions.contains('.$ext')) {
              audioFiles.add(entity);
            }
          }
        }

        // Sort alphabetically
        audioFiles.sort((a, b) {
          final nameA = a.path.split('/').last.toLowerCase();
          final nameB = b.path.split('/').last.toLowerCase();
          return nameA.compareTo(nameB);
        });

        // Batch add - single setState
        final newEntries = <Map<String, dynamic>>[];
        for (final file in audioFiles) {
          if (_audioPool.any((a) => a['path'] == file.path)) continue;
          final name = file.path.split('/').last;
          newEntries.add(_createAudioPoolEntry(file.path, name));
        }

        if (newEntries.isNotEmpty) {
          setState(() {
            _audioPool.addAll(newEntries);
          });
          _persistState();
        }
        debugPrint('[SlotLab] Added ${newEntries.length} files from folder');
      }
    } catch (e) {
      debugPrint('[SlotLab] Folder picker error: $e');
    }
  }

  /// Create audio pool entry (no setState - for batch operations)
  Map<String, dynamic> _createAudioPoolEntry(String path, String name) {
    // Determine folder/category from path
    String folder = 'SFX';
    final lowerPath = path.toLowerCase();
    final lowerName = name.toLowerCase();
    if (lowerPath.contains('music') || lowerName.contains('music') || lowerName.contains('mus_')) {
      folder = 'Music';
    } else if (lowerPath.contains('ambience') || lowerPath.contains('amb')) {
      folder = 'Ambience';
    } else if (lowerPath.contains('voice') || lowerPath.contains('vo_') || lowerName.contains('vo_')) {
      folder = 'Voice';
    } else if (lowerPath.contains('ui') || lowerName.contains('button') || lowerName.contains('click')) {
      folder = 'UI';
    }

    return {
      'name': name.replaceAll(RegExp(r'\.(wav|mp3|ogg|flac|aiff|aif|m4a|wma)$', caseSensitive: false), ''),
      'path': path,
      'duration': 2.0, // Default, actual duration determined when played
      'folder': folder,
    };
  }

  /// Add audio file to pool with metadata (legacy - use batch methods for multiple files)
  Future<void> _addAudioToPool(String path, String name) async {
    // Check if already in pool
    if (_audioPool.any((a) => a['path'] == path)) {
      debugPrint('[SlotLab] Audio already in pool: $name');
      return;
    }

    final entry = _createAudioPoolEntry(path, name);
    setState(() {
      _audioPool.add(entry);
    });

    debugPrint('[SlotLab] Added to pool: $name - ${entry['folder']}');
  }

  @override
  void dispose() {
    // Persist state before disposing
    _persistState();

    // Remove slot lab listener
    if (_engineInitialized && _hasSlotLabProvider) {
      _slotLabProvider.removeListener(_onSlotLabUpdate);
    }

    // Remove middleware listener (bidirectional sync)
    _middleware.removeListener(_onMiddlewareChanged);

    // Dispose drag controller
    _dragController?.removeListener(_onDragControllerChanged);
    _dragController?.dispose();

    _spinTimer?.cancel();
    _playbackTimer?.cancel();
    _previewTimer?.cancel();
    _focusNode.dispose();
    _headersScrollController.dispose();
    _timelineScrollController.dispose();
    _disposeLayerPlayers(); // Dispose audio players
    super.dispose();
  }

  void _initializeTracks() {
    // Start with empty tracks - user creates tracks as needed
    // No placeholder tracks by default
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _postAudioEvent(String eventId, {Map<String, dynamic>? context}) {
    try {
      final mw = Provider.of<MiddlewareProvider>(this.context, listen: false);
      mw.postEvent(eventId, context: context ?? {
        'bet_amount': _bet,
        'balance': _balance,
        'volatility': _volatility,
      });
      debugPrint('[SlotLab] Audio: $eventId');
    } catch (e) {
      debugPrint('[SlotLab] Audio error: $e');
    }
  }

  void _setRtpc(int rtpcId, double value) {
    try {
      final mw = Provider.of<MiddlewareProvider>(this.context, listen: false);
      mw.setRtpc(rtpcId, value);
    } catch (e) {
      debugPrint('[SlotLab] RTPC error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Show loading while provider initializes
    if (!_hasSlotLabProvider) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0C),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(FluxForgeTheme.accentBlue),
              ),
              const SizedBox(height: 16),
              Text(
                'Initializing Slot Lab Engine...',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Watch MiddlewareProvider for changes to sync timeline
    final middleware = context.watch<MiddlewareProvider>();
    _checkMiddlewareChangesAndSync(middleware);

    // Fullscreen preview mode - immersive slot testing
    if (_isPreviewMode) {
      return FullscreenSlotPreview(
        onExit: () => setState(() => _isPreviewMode = false),
        reels: _reelCount,
        rows: _rowCount,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0C),
          body: Stack(
          children: [
            // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A0A0C),
                  Color(0xFF121218),
                  Color(0xFF0A0A0C),
                ],
              ),
            ),
          ),

          // Main content
          Column(
            children: [
              // Header
              _buildHeader(),

              // Main area
              Expanded(
                child: Row(
                  children: [
                    // Left: Game Spec & Paytable
                    _buildLeftPanel(),

                    // Center: Timeline + Stage Trace + Slot View
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // Audio Timeline (main work area)
                          Expanded(
                            flex: 2,
                            child: _buildTimelineArea(),
                          ),
                          // Stage Trace Bar (animated stage progress)
                          StageProgressBar(
                            provider: _slotLabProvider,
                            height: 28,
                          ),
                          // Mock Slot View with improved preview
                          Expanded(
                            flex: 1,
                            child: _buildMockSlot(),
                          ),
                        ],
                      ),
                    ),

                    // Right: Event Editor + Audio Browser
                    _buildRightPanel(),
                  ],
                ),
              ),

              // Bottom Panel
              if (!_bottomPanelCollapsed) _buildBottomPanel(),
              _buildBottomPanelHeader(),
            ],
          ),

          // Drag overlay
          if (_draggingAudioPath != null && _dragPosition != null)
            Positioned(
              left: _dragPosition!.dx - 50,
              top: _dragPosition!.dy - 15,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: FluxForgeTheme.accentBlue.withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Text(
                    _draggingAudioPath!.split('/').last,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KEYBOARD SHORTCUTS
  // ═══════════════════════════════════════════════════════════════════════════

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    debugPrint('[SlotLab] Key event: ${key.keyLabel}, type: ${event.runtimeType}');

    // Keys that allow repeat (hold key for continuous adjustment)
    final isZoomKey = key == LogicalKeyboardKey.keyG || key == LogicalKeyboardKey.keyH;
    final isArrowKey = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;

    // Accept KeyDownEvent and KeyRepeatEvent (for zoom and arrows)
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Only allow repeat for zoom and arrow keys
    if (event is KeyRepeatEvent && !isZoomKey && !isArrowKey) return KeyEventResult.ignored;

    // Space = Play/Stop (no repeat)
    if (key == LogicalKeyboardKey.space) {
      debugPrint('[SlotLab] SPACE pressed - toggling playback, isPlaying=$_isPlaying');
      _togglePlayback();
      return KeyEventResult.handled;
    }

    // G = Zoom Out (supports hold for continuous zoom)
    if (key == LogicalKeyboardKey.keyG) {
      debugPrint('[SlotLab] G pressed - zoom out, current=$_timelineZoom');
      setState(() {
        _timelineZoom = (_timelineZoom * 0.85).clamp(0.1, 10.0);
      });
      return KeyEventResult.handled;
    }

    // H = Zoom In (supports hold for continuous zoom)
    if (key == LogicalKeyboardKey.keyH) {
      debugPrint('[SlotLab] H pressed - zoom in, current=$_timelineZoom');
      setState(() {
        _timelineZoom = (_timelineZoom * 1.18).clamp(0.1, 10.0);
      });
      return KeyEventResult.handled;
    }

    // Home = Go to start
    if (key == LogicalKeyboardKey.home) {
      setState(() {
        _playheadPosition = 0.0;
      });
      return KeyEventResult.handled;
    }

    // End = Go to end
    if (key == LogicalKeyboardKey.end) {
      setState(() {
        _playheadPosition = _timelineDuration;
      });
      return KeyEventResult.handled;
    }

    // L = Set loop around selected region AND toggle loop
    if (key == LogicalKeyboardKey.keyL) {
      debugPrint('[SlotLab] L pressed - toggle loop, isLooping=$_isLooping');
      // Find selected region
      _AudioRegion? selectedRegion;
      for (final track in _tracks) {
        for (final region in track.regions) {
          if (region.isSelected) {
            selectedRegion = region;
            break;
          }
        }
        if (selectedRegion != null) break;
      }

      if (selectedRegion != null) {
        // Set loop around selected region
        setState(() {
          _loopStart = selectedRegion!.start;
          _loopEnd = selectedRegion.end;
          _isLooping = true;
        });
      } else if (_loopStart != null && _loopEnd != null) {
        // No selection but loop exists - toggle loop on/off
        setState(() {
          _isLooping = !_isLooping;
        });
      } else {
        // No selection, no loop - just toggle (will do nothing meaningful)
        setState(() {
          _isLooping = !_isLooping;
        });
      }
      return KeyEventResult.handled;
    }

    // Left Arrow = Nudge playhead left (supports repeat)
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        _playheadPosition = (_playheadPosition - 0.1).clamp(0.0, _timelineDuration);
      });
      return KeyEventResult.handled;
    }

    // Right Arrow = Nudge playhead right (supports repeat)
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        _playheadPosition = (_playheadPosition + 0.1).clamp(0.0, _timelineDuration);
      });
      return KeyEventResult.handled;
    }

    // Delete = Delete selected region
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _deleteSelectedRegions();
      return KeyEventResult.handled;
    }

    // M = Toggle mute on selected regions
    if (key == LogicalKeyboardKey.keyM && !HardwareKeyboard.instance.isMetaPressed) {
      _toggleMuteSelectedRegions();
      return KeyEventResult.handled;
    }

    // T = Add new track
    if (key == LogicalKeyboardKey.keyT &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      _addTrack();
      return KeyEventResult.handled;
    }

    // ] = Zoom in timeline
    if (key == LogicalKeyboardKey.bracketRight) {
      setState(() {
        _timelineZoom = (_timelineZoom * 1.2).clamp(0.1, 10.0);
      });
      return KeyEventResult.handled;
    }

    // [ = Zoom out timeline
    if (key == LogicalKeyboardKey.bracketLeft) {
      setState(() {
        _timelineZoom = (_timelineZoom * 0.8).clamp(0.1, 10.0);
      });
      return KeyEventResult.handled;
    }

    // 0 = Reset zoom to 1.0
    if (key == LogicalKeyboardKey.digit0 &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      setState(() {
        _timelineZoom = 1.0;
      });
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+Z = Undo
    if (key == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (UiUndoManager.instance.undo()) {
        setState(() {});
      }
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+Shift+Z = Redo
    if (key == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        HardwareKeyboard.instance.isShiftPressed) {
      if (UiUndoManager.instance.redo()) {
        setState(() {});
      }
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+Y = Redo (alternate)
    if (key == LogicalKeyboardKey.keyY &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      if (UiUndoManager.instance.redo()) {
        setState(() {});
      }
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+A = Select All regions
    if (key == LogicalKeyboardKey.keyA &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      _selectAllRegions();
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+D = Deselect All
    if (key == LogicalKeyboardKey.keyD &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      _clearAllRegionSelections();
      setState(() {});
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+Shift+A = Invert Selection
    if (key == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isShiftPressed &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      _invertRegionSelection();
      return KeyEventResult.handled;
    }

    // F11 = Toggle fullscreen preview mode
    if (key == LogicalKeyboardKey.f11) {
      setState(() => _isPreviewMode = true);
      return KeyEventResult.handled;
    }

    // ESC = Cancel active drag (revert to original position)
    if (key == LogicalKeyboardKey.escape) {
      if (_dragController?.cancelActiveDrag() == true) {
        debugPrint('[SlotLab] ESC pressed - drag cancelled, reverted to original position');
        return KeyEventResult.handled;
      }
      // ESC with no active drag - deselect regions
      _clearAllRegionSelections();
      setState(() {});
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _deleteSelectedRegions() {
    setState(() {
      for (final track in _tracks) {
        // Get selected regions before removing
        final selectedRegions = track.regions.where((r) => r.isSelected).toList();

        // Sync delete to composite events
        for (final region in selectedRegions) {
          _syncRegionDeleteToEvent(region);
        }

        track.regions.removeWhere((r) => r.isSelected);
      }
    });
  }

  /// Deselect all regions (ESC with no active drag)
  void _deselectAllRegions() {
    setState(() {
      for (final track in _tracks) {
        for (final region in track.regions) {
          region.isSelected = false;
        }
      }
    });
  }

  /// When a region is deleted from timeline, DELETE the composite event too
  void _syncRegionDeleteToEvent(_AudioRegion region) {
    debugPrint('[SlotLab] Sync delete for region: "${region.name}" (id=${region.id})');

    // Strategy 1: Find event by ID mapping
    String? eventId;
    for (final entry in _eventToRegionMap.entries) {
      if (entry.value == region.id) {
        eventId = entry.key;
        break;
      }
    }

    // Strategy 2: Find event by name if no ID mapping
    SlotCompositeEvent? event;
    if (eventId != null) {
      event = _findEventById(eventId);
    }
    if (event == null) {
      // Try by name
      event = _findEventByName(region.name);
      if (event != null) {
        eventId = event.id;
        debugPrint('[SlotLab] Found event by name match: ${region.name}');
      }
    }

    if (event != null) {
      final eventName = event.name;
      final deletedEventId = event.id;

      debugPrint('[SlotLab] Deleting composite event: "$eventName"');

      // Remove the mapping
      _eventToRegionMap.remove(deletedEventId);

      // Clear selection if this was selected
      if (_selectedEventId == deletedEventId) {
        _selectedEventId = null;
      }

      // Delete from Middleware (single source of truth) and EventRegistry
      // Use addPostFrameCallback to avoid calling during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _deleteMiddlewareEvent(deletedEventId);
          debugPrint('[SlotLab] Deleted composite event from Middleware: "$eventName"');
        }
      });
    } else {
      debugPrint('[SlotLab] No matching composite event found for region "${region.name}"');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A22), Color(0xFF242430), Color(0xFF1A1A22)],
        ),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFFFD700).withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),

          // Close button
          _buildGlassButton(
            icon: Icons.arrow_back,
            onTap: widget.onClose,
            tooltip: 'Back to DAW',
          ),

          const SizedBox(width: 16),

          // Logo and title
          const Icon(Icons.casino, color: Color(0xFFFFD700), size: 24),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FLUXFORGE SLOT LAB',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'Audio Sandbox',
                style: TextStyle(
                  color: Color(0xFFFFAA00),
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),

          const SizedBox(width: 24),

          // Transport controls
          _buildTransportControls(),

          const Spacer(),

          // Status indicators - wrapped to prevent overflow
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusChip('BALANCE', '\$${_balance.toStringAsFixed(0)}', const Color(0xFF40FF90)),
                const SizedBox(width: 6),
                _buildStatusChip('BET', '\$${_bet.toStringAsFixed(2)}', const Color(0xFF4A9EFF)),
                const SizedBox(width: 6),
                _buildStatusChip('WIN', '\$${_lastWin.toStringAsFixed(0)}', const Color(0xFFFFD700)),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Mini slot preview (shows last spin result)
          SlotMiniPreview(
            provider: _slotLabProvider,
            size: 90,
          ),

          const SizedBox(width: 8),

          // Fullscreen preview button
          _buildPreviewButton(),

          const SizedBox(width: 8),

          // View toggles
          _buildGlassButton(
            icon: Icons.folder_open,
            onTap: () => setState(() => _showAudioBrowser = !_showAudioBrowser),
            tooltip: 'Audio Browser',
            isActive: _showAudioBrowser,
          ),
          const SizedBox(width: 4),
          _buildGlassButton(
            icon: Icons.preview,
            onTap: () => setState(() => _showPreviewPanel = !_showPreviewPanel),
            tooltip: 'Preview Panel',
            isActive: _showPreviewPanel,
          ),
          const SizedBox(width: 4),
          _buildGlassButton(
            icon: Icons.settings,
            onTap: _showSettingsDialog,
            tooltip: 'Settings',
          ),

          const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SlotLabSettingsPanel(
          settings: _slotLabSettings,
          onSettingsChanged: (newSettings) {
            setState(() {
              _slotLabSettings = newSettings;
            });
          },
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildTransportControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTransportButton(Icons.skip_previous, _goToStart),
          _buildTransportButton(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            _togglePlayback,
            isActive: _isPlaying,
          ),
          _buildTransportButton(Icons.stop, _stopPlayback),
          _buildTransportButton(
            Icons.repeat,
            () => setState(() => _isLooping = !_isLooping),
            isActive: _isLooping,
          ),
          // Clear loop region button
          if (_loopStart != null && _loopEnd != null)
            Tooltip(
              message: 'Clear loop region',
              child: InkWell(
                onTap: _clearLoopRegion,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9040).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.close, size: 14, color: Color(0xFFFF9040)),
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Timecode display with loop info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
              border: _loopStart != null && _isLooping
                  ? Border.all(color: const Color(0xFFFF9040).withOpacity(0.5))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimecode(_playheadPosition),
                  style: const TextStyle(
                    color: Color(0xFF40FF90),
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_loopStart != null && _loopEnd != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '⟳${_formatTimecode(_loopStart!)}-${_formatTimecode(_loopEnd!)}',
                    style: TextStyle(
                      color: const Color(0xFFFF9040).withOpacity(0.8),
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportButton(IconData icon, VoidCallback onTap, {bool isActive = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF40FF90).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? const Color(0xFF40FF90) : Colors.white70,
        ),
      ),
    );
  }

  String _formatTimecode(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final frames = ((seconds % 1) * 30).floor(); // 30fps
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  /// Set loop region from selected region or event
  void _setLoopRegion(double start, double end) {
    setState(() {
      _loopStart = start;
      _loopEnd = end;
      _isLooping = true;  // Auto-enable looping when region is set
    });
    debugPrint('[SlotLab] Loop region set: ${start.toStringAsFixed(2)}s - ${end.toStringAsFixed(2)}s');
  }

  /// Clear loop region
  void _clearLoopRegion() {
    setState(() {
      _loopStart = null;
      _loopEnd = null;
    });
  }

  /// Set loop region from selected audio region
  void _setLoopFromRegion(_AudioRegion region) {
    _setLoopRegion(region.start, region.end);
  }

  /// Show context menu for audio region
  void _showRegionContextMenu(Offset position, _AudioRegion region) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'loop',
          child: Row(
            children: [
              Icon(Icons.repeat, size: 16, color: const Color(0xFFFF9040)),
              const SizedBox(width: 8),
              const Text('Set as Loop Region', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 16, color: const Color(0xFF40FF90)),
              const SizedBox(width: 8),
              const Text('Play from Start', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: const Color(0xFFFF4060)),
              const SizedBox(width: 8),
              const Text('Delete Region', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'loop') {
        _setLoopFromRegion(region);
      } else if (value == 'play') {
        setState(() {
          _playheadPosition = region.start;
          _isPlaying = true;
        });
        if (_ffi.isLoaded) {
          try {
            _ffi.seek(region.start);
            _ffi.play();
          } catch (_) {}
        }
      } else if (value == 'delete') {
        setState(() {
          // Sync delete to composite event first
          _syncRegionDeleteToEvent(region);

          for (final track in _tracks) {
            track.regions.removeWhere((r) => r.id == region.id);
          }
        });
      }
    });
  }

  void _goToStart() {
    setState(() {
      // If looping with region, go to loop start
      _playheadPosition = (_isLooping && _loopStart != null) ? _loopStart! : 0.0;
    });
  }

  void _togglePlayback() {
    // Stop any audio preview first
    if (_isPreviewPlaying) {
      _stopAudioPreview();
    }

    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      // ═══════════════════════════════════════════════════════════════════════
      // UNIFIED PLAYBACK: Use PLAYBACK_ENGINE (same as DAW)
      // ═══════════════════════════════════════════════════════════════════════

      // Ensure all SlotLab layers are synced to TRACK_MANAGER as clips
      _syncLayersToTrackManager();

      // Start playback via PLAYBACK_ENGINE
      _trackBridge.play(fromPosition: _playheadPosition);

      debugPrint('[SlotLab] Playback started at ${_playheadPosition}s via PLAYBACK_ENGINE');

      // UI update timer (visual only - audio is handled by PLAYBACK_ENGINE)
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted || !_isPlaying) {
          timer.cancel();
          return;
        }
        setState(() {
          // Sync playhead from PLAYBACK_ENGINE position
          _playheadPosition = _trackBridge.currentPosition;

          // Determine loop boundaries
          final loopEnd = (_isLooping && _loopEnd != null) ? _loopEnd! : _timelineDuration;
          final loopStart = (_isLooping && _loopStart != null) ? _loopStart! : 0.0;

          if (_playheadPosition >= loopEnd) {
            if (_isLooping) {
              _trackBridge.seek(loopStart);
              _playheadPosition = loopStart;
            } else {
              _isPlaying = false;
              timer.cancel();
              _trackBridge.stop();
            }
          }
        });
      });
    } else {
      _playbackTimer?.cancel();
      // Stop via PLAYBACK_ENGINE
      _trackBridge.pause();
    }
  }

  /// Sync all SlotLab layers to TRACK_MANAGER clips for unified playback
  void _syncLayersToTrackManager() {
    for (final track in _tracks) {
      if (track.isMuted) continue;

      for (final region in track.regions) {
        if (region.isMuted) continue;

        for (final layer in region.layers) {
          if (layer.audioPath.isEmpty) continue;

          // Calculate absolute position on timeline
          final absoluteStart = region.start + layer.offset;

          // Add/update clip in TRACK_MANAGER
          _trackBridge.addLayerClip(
            layerId: layer.id,
            audioPath: layer.audioPath,
            startTime: absoluteStart,
            duration: layer.duration,
            volume: layer.volume * track.volume,
          );
        }
      }
    }
    debugPrint('[SlotLab] Synced ${_tracks.length} tracks to TRACK_MANAGER');
  }

  void _stopPlayback() {
    setState(() {
      _isPlaying = false;
      _playheadPosition = 0.0;
    });
    _playbackTimer?.cancel();
    _triggeredLayers.clear();

    // UNIFIED PLAYBACK: Stop via PLAYBACK_ENGINE
    _trackBridge.stop();
  }

  /// Calculate the absolute start time of a layer on the timeline
  double _getLayerStartTime(_AudioRegion region, _RegionLayer layer) {
    return region.start + layer.offset;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEPRECATED: Legacy layer triggering methods (no longer used)
  // PLAYBACK_ENGINE now handles clip playback automatically via TRACK_MANAGER
  // These remain for reference but are not called in unified playback mode
  // ═══════════════════════════════════════════════════════════════════════════

  /// @deprecated Use _syncLayersToTrackManager() + _trackBridge.play() instead
  void _triggerLayersAtPosition(double position) {
    // DEPRECATED: PLAYBACK_ENGINE handles this automatically
    debugPrint('[SlotLab] DEPRECATED: _triggerLayersAtPosition called');
  }

  /// @deprecated Use _syncLayersToTrackManager() + _trackBridge.play() instead
  void _checkAndTriggerLayers(double prevPos, double currentPos) {
    // DEPRECATED: PLAYBACK_ENGINE handles this automatically
    debugPrint('[SlotLab] DEPRECATED: _checkAndTriggerLayers called');
  }

  /// @deprecated Use _syncLayersToTrackManager() + _trackBridge.play() instead
  /// Was used for individual layer playback via PREVIEW_ENGINE
  Future<void> _playLayerAudio(_RegionLayer layer, double offsetSeconds) async {
    // DEPRECATED: PLAYBACK_ENGINE handles clip playback automatically
    debugPrint('[SlotLab] DEPRECATED: _playLayerAudio called for ${layer.name}');
  }

  /// Stop all currently playing layer audio
  /// NOTE: With unified PLAYBACK_ENGINE, this is now handled by _trackBridge.stop()
  Future<void> _stopAllLayerAudio() async {
    // Legacy cleanup - clear tracking state
    _activeLayerIds.clear();
    // UNIFIED PLAYBACK: Stop via PLAYBACK_ENGINE
    _trackBridge.stop();
  }

  /// Dispose all audio players (cleanup)
  void _disposeLayerPlayers() {
    _stopAllLayerAudio();
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Timer? _previewTimer;
  int? _previewTrackId;
  int? _previewClipId;

  void _startAudioPreview(String path) {
    // Stop any existing preview first
    _stopAudioPreview();

    setState(() {
      _previewingAudioPath = path;
      _isPreviewPlaying = true;
    });

    try {
      // Find the audio info for duration
      final audioInfo = _audioPool.firstWhere(
        (a) => a['path'] == path,
        orElse: () => {'path': path, 'name': path.split('/').last, 'duration': 1.0},
      );
      final duration = (audioInfo['duration'] as num?)?.toDouble() ?? 1.0;

      // Use AudioPlaybackService for preview (uses PreviewEngine - isolated)
      final voiceId = AudioPlaybackService.instance.previewFile(
        path,
        source: PlaybackSource.browser,
      );

      if (voiceId >= 0) {
        debugPrint('[SlotLab] Playing preview via AudioPlaybackService: $path (voice: $voiceId, ${duration}s)');
      } else {
        debugPrint('[SlotLab] Preview failed to start for: $path');
        _stopAudioPreview();
        return;
      }

      // Auto-stop after duration
      _previewTimer?.cancel();
      _previewTimer = Timer(Duration(milliseconds: (duration * 1000).toInt() + 100), () {
        if (mounted && _isPreviewPlaying) {
          _stopAudioPreview();
        }
      });
    } catch (e) {
      debugPrint('[SlotLab] Preview error: $e');
      _stopAudioPreview();
    }
  }

  void _stopAudioPreview() {
    _previewTimer?.cancel();
    _previewTimer = null;

    setState(() {
      _previewingAudioPath = null;
      _isPreviewPlaying = false;
    });

    // Stop via AudioPlaybackService (browser source uses PreviewEngine)
    AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
    debugPrint('[SlotLab] Preview stopped');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT PANEL - Game Spec & Paytable
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLeftPanel() {
    return Container(
      width: 240,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF121216).withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          _buildPanelHeader('GAME SPEC', Icons.settings),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSpecRow('Grid', '$_reelCount x $_rowCount'),
                  _buildSpecRow('Pay Model', 'Ways (243)'),
                  _buildSpecRow('RTP Target', '96.5%'),

                  const SizedBox(height: 12),
                  _buildSectionTitle('VOLATILITY'),

                  // Volatility Dial
                  Center(
                    child: VolatilityDial(
                      initialLevel: _volatilityLevel,
                      size: 100,
                      onChanged: (level) {
                        setState(() {
                          _slotLabSettings = _slotLabSettings.copyWith(volatility: level);
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 12),
                  _buildSectionTitle('SCENARIO CONTROLS'),

                  // Scenario Controls
                  ScenarioControls(
                    isSpinning: _isSpinning,
                    onScenarioTriggered: (result) {
                      _triggerScenario(result);
                    },
                    onReplayLastSpin: () {
                      _replayLastSpin();
                    },
                    onBatchPlay: (count) {
                      _batchPlay(count);
                    },
                  ),

                  const SizedBox(height: 12),
                  _buildSectionTitle('PAYTABLE'),

                  _buildPaytableRow('7', '500x', true, true, false),
                  _buildPaytableRow('BAR', '200x', true, true, false),
                  _buildPaytableRow('BELL', '100x', true, false, true),
                  _buildPaytableRow('CHERRY', '50x', true, false, false),
                  _buildPaytableRow('WILD', 'Sub', false, true, true),
                  _buildPaytableRow('BONUS', 'FS', false, false, true),

                  const SizedBox(height: 12),
                  _buildSectionTitle('FEATURE RULES'),

                  _buildFeatureRule('3+ Scatters → 10-20 FS'),
                  _buildFeatureRule('Big Win Tier 1: 50x'),
                  _buildFeatureRule('Big Win Tier 2: 200x'),
                  _buildFeatureRule('Big Win Tier 3: 900x'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Scenario trigger handlers
  void _triggerScenario(ScenarioResult result) {
    debugPrint('[SlotLab] Scenario triggered: ${result.type} - ${result.parameters}');

    final stageProvider = context.read<StageProvider>();
    final multiplier = (result.parameters['multiplier'] as num?)?.toDouble() ?? 1.0;

    // Map scenario to stage events
    switch (result.type) {
      // Win scenarios
      case 'win_small':
        _triggerWinSequence(stageProvider, 'small');
        break;
      case 'win_medium':
        _triggerWinSequence(stageProvider, 'medium');
        break;
      case 'win_big':
        _triggerWinSequence(stageProvider, 'big');
        break;
      case 'force_win':
        final tier = result.parameters['tier'] as String? ?? 'small';
        _triggerWinSequence(stageProvider, tier);
        break;

      // Big Win tiers
      case 'bigwin_nice':
        _triggerBigWinSequence(stageProvider, 1);
        break;
      case 'bigwin_super':
        _triggerBigWinSequence(stageProvider, 2);
        break;
      case 'bigwin_mega':
        _triggerBigWinSequence(stageProvider, 3);
        break;
      case 'bigwin_epic':
        _triggerBigWinSequence(stageProvider, 4);
        break;
      case 'bigwin_ultra':
        _triggerBigWinSequence(stageProvider, 5);
        break;
      case 'force_bigwin':
        final tier = result.parameters['tier'] as int? ?? 1;
        _triggerBigWinSequence(stageProvider, tier);
        break;

      // Feature scenarios
      case 'feature_freespins':
        final spins = result.parameters['spins'] as int? ?? 10;
        _triggerFreeSpinsSequence(stageProvider, spins);
        break;
      case 'feature_pickbonus':
        _triggerFeatureSequence(stageProvider, 'pick_bonus');
        break;
      case 'feature_wheel':
        _triggerFeatureSequence(stageProvider, 'wheel_bonus');
        break;
      case 'jackpot_trigger':
        _triggerJackpotSequence(stageProvider);
        break;
      case 'force_freespins':
        final count = result.parameters['count'] as int? ?? 10;
        _triggerFreeSpinsSequence(stageProvider, count);
        break;

      // Other scenarios
      case 'near_miss':
      case 'force_nearmiss':
        _triggerNearMissSequence(stageProvider);
        break;

      case 'anticipation':
      case 'force_anticipation':
        _triggerAnticipationSequence(stageProvider);
        break;

      case 'reset':
        // Reset to normal play mode
        debugPrint('[SlotLab] Reset to normal mode');
        break;
    }
  }

  void _triggerFeatureSequence(StageProvider provider, String featureType) {
    double ts = 0.0;
    final feature = featureType == 'wheel_bonus' ? FeatureType.wheelBonus : FeatureType.pickBonus;

    final events = [
      StageEvent(stage: const SpinStart(), timestampMs: ts),
      StageEvent(stage: const ReelStop(reelIndex: 0, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 1, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 2, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 3, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 4, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: FeatureEnter(featureType: feature), timestampMs: ts += 100),
    ];

    _playStageSequence(provider, events);
  }

  void _triggerJackpotSequence(StageProvider provider) {
    double ts = 0.0;

    final events = [
      StageEvent(stage: const SpinStart(), timestampMs: ts),
      StageEvent(stage: const ReelStop(reelIndex: 0, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 1, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const AnticipationOn(reelIndex: 2, reason: 'jackpot'), timestampMs: ts += 100),
      StageEvent(stage: const ReelStop(reelIndex: 2, symbols: []), timestampMs: ts += 500),
      StageEvent(stage: const ReelStop(reelIndex: 3, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 4, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const AnticipationOff(reelIndex: 4), timestampMs: ts += 50),
      StageEvent(stage: const JackpotTrigger(tier: JackpotTier.grand), timestampMs: ts += 100),
    ];

    _playStageSequence(provider, events);
  }

  void _triggerWinSequence(StageProvider provider, String tier) {
    // Simulate win sequence with stage events
    final winAmount = tier == 'small' ? 5.0 : (tier == 'medium' ? 25.0 : 100.0);
    double ts = 0.0;

    final events = [
      StageEvent(stage: const SpinStart(), timestampMs: ts),
      StageEvent(stage: const ReelStop(reelIndex: 0, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 1, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 2, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 3, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 4, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: WinPresent(winAmount: winAmount, lineCount: 3), timestampMs: ts += 100),
      StageEvent(stage: RollupStart(targetAmount: winAmount, startAmount: 0), timestampMs: ts += 100),
      StageEvent(stage: RollupEnd(finalAmount: winAmount), timestampMs: ts += 500),
    ];

    _playStageSequence(provider, events);
  }

  void _triggerBigWinSequence(StageProvider provider, int tier) {
    final winAmount = tier == 1 ? 500.0 : (tier == 2 ? 1500.0 : 5000.0);
    final bigWinTier = tier == 1 ? BigWinTier.bigWin : (tier == 2 ? BigWinTier.megaWin : BigWinTier.epicWin);
    double ts = 0.0;

    final events = [
      StageEvent(stage: const SpinStart(), timestampMs: ts),
      StageEvent(stage: const ReelStop(reelIndex: 0, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 1, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 2, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const AnticipationOn(reelIndex: 3), timestampMs: ts += 100),
      StageEvent(stage: const ReelStop(reelIndex: 3, symbols: []), timestampMs: ts += 500),
      StageEvent(stage: const ReelStop(reelIndex: 4, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const AnticipationOff(reelIndex: 4), timestampMs: ts += 50),
      StageEvent(stage: WinPresent(winAmount: winAmount, lineCount: 5), timestampMs: ts += 100),
      StageEvent(stage: BigWinTierStage(tier: bigWinTier, amount: winAmount), timestampMs: ts += 100),
      StageEvent(stage: RollupStart(targetAmount: winAmount, startAmount: 0), timestampMs: ts += 100),
      StageEvent(stage: RollupEnd(finalAmount: winAmount), timestampMs: ts += 2000),
    ];

    _playStageSequence(provider, events);
  }

  void _triggerFreeSpinsSequence(StageProvider provider, int count) {
    double ts = 0.0;

    final events = [
      StageEvent(stage: const SpinStart(), timestampMs: ts),
      StageEvent(stage: const ReelStop(reelIndex: 0, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 1, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 2, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 3, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 4, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: FeatureEnter(featureType: FeatureType.freeSpins, totalSteps: count), timestampMs: ts += 100),
    ];

    _playStageSequence(provider, events);
  }

  void _triggerNearMissSequence(StageProvider provider) {
    double ts = 0.0;

    final events = [
      StageEvent(stage: const SpinStart(), timestampMs: ts),
      StageEvent(stage: const ReelStop(reelIndex: 0, symbols: [7]), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 1, symbols: [7]), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 2, symbols: [7]), timestampMs: ts += 200),
      StageEvent(stage: const AnticipationOn(reelIndex: 3, reason: 'near_miss'), timestampMs: ts += 100),
      StageEvent(stage: const ReelStop(reelIndex: 3, symbols: [7]), timestampMs: ts += 500),
      StageEvent(stage: const ReelStop(reelIndex: 4, symbols: [2]), timestampMs: ts += 200), // Near miss!
      StageEvent(stage: const AnticipationOff(reelIndex: 4), timestampMs: ts += 50),
    ];

    _playStageSequence(provider, events);
  }

  void _triggerAnticipationSequence(StageProvider provider) {
    double ts = 0.0;

    final events = [
      StageEvent(stage: const SpinStart(), timestampMs: ts),
      StageEvent(stage: const ReelStop(reelIndex: 0, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const ReelStop(reelIndex: 1, symbols: []), timestampMs: ts += 200),
      StageEvent(stage: const AnticipationOn(reelIndex: 2, reason: 'bonus_potential'), timestampMs: ts += 100),
      // Hold anticipation for dramatic effect...
    ];

    _playStageSequence(provider, events);
  }

  void _playStageSequence(StageProvider provider, List<StageEvent> events) async {
    final mw = context.read<MiddlewareProvider>();
    final mapper = StageAudioMapper(mw, _ffi);

    for (int i = 0; i < events.length; i++) {
      final event = events[i];

      // Fire stage event to provider
      provider.injectLiveEvent(event);

      // Map to audio and trigger via mapper (handles all audio logic)
      mapper.mapAndTrigger(event);

      // Delay between events for realism
      if (i < events.length - 1) {
        final nextEvent = events[i + 1];
        final delayMs = (nextEvent.timestampMs - event.timestampMs).toInt();
        await Future.delayed(Duration(milliseconds: delayMs.clamp(50, 2000)));
      }
    }
  }

  void _replayLastSpin() {
    debugPrint('[SlotLab] Replaying last spin');
    final stageProvider = context.read<StageProvider>();
    final currentTrace = stageProvider.currentTrace;
    if (currentTrace != null && currentTrace.events.isNotEmpty) {
      _playStageSequence(stageProvider, currentTrace.events);
    } else {
      // Replay from live events if no trace
      final liveEvents = stageProvider.liveEvents;
      if (liveEvents.isNotEmpty) {
        // Get last spin sequence (from last SPIN_START)
        final spinStartIdx = liveEvents.lastIndexWhere((e) => e.stage is SpinStart);
        if (spinStartIdx >= 0) {
          _playStageSequence(stageProvider, liveEvents.sublist(spinStartIdx));
        }
      }
    }
  }

  void _batchPlay(int count) async {
    debugPrint('[SlotLab] Batch play: $count spins');
    final stageProvider = context.read<StageProvider>();

    for (int i = 0; i < count; i++) {
      // Random outcome based on volatility
      final outcome = _generateRandomOutcome();
      _triggerScenario(outcome);
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  ScenarioResult _generateRandomOutcome() {
    final roll = _random.nextDouble();
    final volatilityFactor = _volatilityLevel.value / 4.0; // 0.0 - 1.0

    if (roll < 0.02 * (1 + volatilityFactor)) {
      // Big win (rarer at low volatility)
      return ScenarioResult('force_bigwin', {'tier': _random.nextInt(3) + 1});
    } else if (roll < 0.1) {
      // Regular win
      return ScenarioResult('force_win', {'tier': 'medium'});
    } else if (roll < 0.3) {
      // Small win
      return ScenarioResult('force_win', {'tier': 'small'});
    } else if (roll < 0.35 + (volatilityFactor * 0.1)) {
      // Near miss (more common at high volatility)
      return ScenarioResult('force_nearmiss', {});
    } else {
      // No win (most common)
      return ScenarioResult('force_win', {'tier': 'none'});
    }
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaytableRow(String symbol, String payout, bool sfx, bool music, bool duck) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              symbol,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              payout,
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10),
            ),
          ),
          _buildLedIndicator(sfx, const Color(0xFF40FF90)),
          const SizedBox(width: 3),
          _buildLedIndicator(music, const Color(0xFF4A9EFF)),
          const SizedBox(width: 3),
          _buildLedIndicator(duck, const Color(0xFFFF9040)),
        ],
      ),
    );
  }

  Widget _buildLedIndicator(bool active, Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : color.withOpacity(0.2),
        boxShadow: active
            ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 3)]
            : null,
      ),
    );
  }

  Widget _buildFeatureRule(String rule) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.chevron_right, size: 12, color: Color(0xFFFFAA00)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              rule,
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMELINE AREA
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimelineArea() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Timeline header with stage markers
          _buildTimelineHeader(),

          // Stage markers ruler
          _buildStageMarkersRuler(),

          // Tracks
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,  // Headers + Content start from TOP
              children: [
                // Track headers
                SizedBox(
                  width: 140,
                  child: _buildTrackHeaders(),
                ),
                // Track content
                Expanded(
                  child: _buildTimelineContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline, size: 14, color: Color(0xFFFFD700)),
          const SizedBox(width: 6),
          const Text(
            'AUDIO TIMELINE',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 14),
            color: Colors.white54,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => setState(() => _timelineZoom = (_timelineZoom / 1.2).clamp(0.25, 4.0)),
          ),
          Text(
            '${(_timelineZoom * 100).toInt()}%',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 14),
            color: Colors.white54,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => setState(() => _timelineZoom = (_timelineZoom * 1.2).clamp(0.25, 4.0)),
          ),
          const SizedBox(width: 8),
          // Add marker button
          InkWell(
            onTap: _showAddMarkerDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4A9EFF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF4A9EFF).withOpacity(0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag, size: 12, color: Color(0xFF4A9EFF)),
                  SizedBox(width: 4),
                  Text('Marker', style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 10)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Add track button
          InkWell(
            onTap: _addTrack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF40FF90).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF40FF90).withOpacity(0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 12, color: Color(0xFF40FF90)),
                  SizedBox(width: 4),
                  Text('Track', style: TextStyle(color: Color(0xFF40FF90), fontSize: 10)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Expand/Collapse all tracks button
          InkWell(
            onTap: _toggleAllTracksExpanded,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _allTracksExpanded
                    ? const Color(0xFFFF9040).withOpacity(0.2)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _allTracksExpanded
                      ? const Color(0xFFFF9040).withOpacity(0.5)
                      : Colors.white.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _allTracksExpanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 12,
                    color: _allTracksExpanded ? const Color(0xFFFF9040) : Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _allTracksExpanded ? 'Collapse' : 'Expand',
                    style: TextStyle(
                      color: _allTracksExpanded ? const Color(0xFFFF9040) : Colors.white70,
                      fontSize: 10,
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

  void _showAddMarkerDialog() {
    final TextEditingController nameController = TextEditingController();
    Color selectedColor = const Color(0xFF4A9EFF);

    final markerPresets = [
      ('SPIN START', const Color(0xFF4A9EFF)),
      ('REEL STOP', const Color(0xFF9B59B6)),
      ('ANTICIPATION', const Color(0xFFE74C3C)),
      ('WIN PRESENT', const Color(0xFFF1C40F)),
      ('ROLLUP', const Color(0xFF40FF90)),
      ('BIG WIN', const Color(0xFFFF9040)),
      ('FEATURE', const Color(0xFF40C8FF)),
      ('CUSTOM', Colors.white70),
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A22),
          title: const Text(
            'Add Stage Marker',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick presets:',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: markerPresets.map((preset) {
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          nameController.text = preset.$1;
                          selectedColor = preset.$2;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: preset.$2.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: preset.$2.withOpacity(0.5)),
                        ),
                        child: Text(
                          preset.$1,
                          style: TextStyle(color: preset.$2, fontSize: 9),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Marker Name',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: selectedColor),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Position: ${_playheadPosition.toStringAsFixed(2)}s',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  _addStageMarker(nameController.text, selectedColor);
                  Navigator.pop(context);
                }
              },
              child: Text('Add', style: TextStyle(color: selectedColor)),
            ),
          ],
        ),
      ),
    );
  }

  void _addStageMarker(String name, Color color) {
    setState(() {
      _stageMarkers.add(_StageMarker(
        position: _playheadPosition / _timelineDuration,
        name: name,
        color: color,
      ));
      // Sort markers by position
      _stageMarkers.sort((a, b) => a.position.compareTo(b.position));
    });
  }

  Widget _buildStageMarkersRuler() {
    return Container(
      height: 24,
      margin: const EdgeInsets.only(left: 140),
      decoration: BoxDecoration(
        color: const Color(0xFF151518),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Stage markers
              ..._stageMarkers.map((marker) {
                final x = marker.position * constraints.maxWidth;
                return Positioned(
                  left: x - 30,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => _onStageMarkerTap(marker),
                    onLongPress: () => _onStageMarkerLongPress(marker),
                    child: Container(
                      width: 60,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 2,
                            height: 8,
                            color: marker.color,
                          ),
                          Text(
                            marker.name,
                            style: TextStyle(
                              color: marker.color,
                              fontSize: 7,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              // NOTE: White playhead indicator removed - red DAW-style playhead on timeline is sufficient
            ],
          );
        },
      ),
    );
  }

  void _onStageMarkerTap(_StageMarker marker) {
    setState(() {
      _playheadPosition = marker.position * _timelineDuration;
    });
  }

  void _onStageMarkerLongPress(_StageMarker marker) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: Text(
          'Delete "${marker.name}"?',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: const Text(
          'This marker will be removed from the timeline.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _stageMarkers.remove(marker);
              });
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
  }

  // Separate scroll controllers for synchronized scrolling
  final ScrollController _headersScrollController = ScrollController();
  final ScrollController _timelineScrollController = ScrollController();
  bool _isSyncingScroll = false;

  void _syncHeadersToTimeline() {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    if (_headersScrollController.hasClients && _timelineScrollController.hasClients) {
      _headersScrollController.jumpTo(_timelineScrollController.offset);
    }
    _isSyncingScroll = false;
  }

  void _syncTimelineToHeaders() {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    if (_timelineScrollController.hasClients && _headersScrollController.hasClients) {
      _timelineScrollController.jumpTo(_headersScrollController.offset);
    }
    _isSyncingScroll = false;
  }

  Widget _buildTrackHeaders() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _syncTimelineToHeaders();
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _headersScrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _tracks.asMap().entries.map((entry) {
            return _buildTrackHeader(entry.value, entry.key);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTrackHeader(_SlotAudioTrack track, int index) {
    final isSelected = _selectedTrackIndex == index;
    final trackHeight = _getTrackHeight(track);

    // Check if track has any region with multiple layers
    final hasExpandableLayers = track.regions.any((r) => r.layers.length > 1);
    final isExpanded = track.regions.any((r) => r.isExpanded && r.layers.length > 1);

    return GestureDetector(
      onTap: () => setState(() => _selectedTrackIndex = index),
      child: Container(
        height: trackHeight,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? track.color.withOpacity(0.15)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
            right: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
        ),
        child: Row(
          children: [
            // Expand/Collapse button for tracks with layers
            if (hasExpandableLayers)
              GestureDetector(
                onTap: () {
                  setState(() {
                    final newState = !isExpanded;
                    for (final region in track.regions) {
                      if (region.layers.length > 1) {
                        region.isExpanded = newState;
                      }
                    }
                  });
                },
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: isExpanded ? track.color.withOpacity(0.3) : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(
                    isExpanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 12,
                    color: isExpanded ? track.color : Colors.white54,
                  ),
                ),
              )
            else
              const SizedBox(width: 22),
            // Color indicator
            Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                color: track.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            // Track name
            Expanded(
              child: Text(
                track.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Mute button
            _buildTrackButton(
              icon: Icons.volume_off,
              isActive: track.isMuted,
              color: const Color(0xFFFF4040),
              onTap: () => setState(() => track.isMuted = !track.isMuted),
            ),
            // Solo button
            _buildTrackButton(
              icon: Icons.headphones,
              isActive: track.isSolo,
              color: const Color(0xFFF1C40F),
              onTap: () => setState(() => track.isSolo = !track.isSolo),
            ),
            // Delete track button
            _buildTrackButton(
              icon: Icons.delete_outline,
              isActive: false,
              color: const Color(0xFFFF4040),
              onTap: () => _deleteTrack(track, index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackButton({
    required IconData icon,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? color : Colors.white24,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 12,
          color: isActive ? color : Colors.white38,
        ),
      ),
    );
  }

  Widget _buildTimelineContent() {
    return DragTarget<Object>(
      onAcceptWithDetails: (details) {
        if (details.data is String) {
          // Handle audio drop on timeline
          _handleAudioDrop(details.data as String, details.offset);
        } else if (details.data is SlotCompositeEvent) {
          // Handle composite event drop on timeline
          _handleEventDrop(details.data as SlotCompositeEvent, details.offset);
        }
      },
      onWillAcceptWithDetails: (details) => details.data is String || details.data is SlotCompositeEvent,
      builder: (context, candidateData, rejectedData) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Apply zoom to timeline width
            final zoomedWidth = constraints.maxWidth * _timelineZoom;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: zoomedWidth,
                height: constraints.maxHeight,
                child: Stack(
                  alignment: AlignmentDirectional.topStart,  // Tracks start from TOP
                  children: [
                    // Grid lines (FIRST - bottom layer)
                    CustomPaint(
                      size: Size(zoomedWidth, constraints.maxHeight),
                      painter: _TimelineGridPainter(
                        zoom: _timelineZoom,
                        duration: _timelineDuration,
                      ),
                    ),

                    // Click to set playhead - BEFORE tracks so tracks can intercept drag
                    // Only responds to tap, not drag
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) {
                          // Only set playhead if we're NOT dragging a region
                          if (_draggingRegion == null) {
                            final newPosition = (details.localPosition.dx / zoomedWidth) * _timelineDuration;
                            setState(() {
                              _playheadPosition = newPosition.clamp(0.0, _timelineDuration);
                            });
                            // Seek audio engine to new position
                            if (_ffi.isLoaded) {
                              try {
                                _ffi.seek(_playheadPosition);
                              } catch (_) {}
                            }
                          }
                        },
                      ),
                    ),

                    // Tracks (synchronized with headers via scroll notification) - ABOVE playhead click area
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification) {
                          _syncHeadersToTimeline();
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _timelineScrollController,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _tracks.asMap().entries.map((entry) {
                            return _buildTrackTimeline(
                              entry.value,
                              entry.key,
                              zoomedWidth,
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    // Loop region overlay
                    if (_loopStart != null && _loopEnd != null)
                      Positioned(
                        left: (_loopStart! / _timelineDuration) * zoomedWidth,
                        top: 0,
                        bottom: 0,
                        width: ((_loopEnd! - _loopStart!) / _timelineDuration) * zoomedWidth,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9040).withOpacity(_isLooping ? 0.15 : 0.05),
                              border: Border.symmetric(
                                vertical: BorderSide(
                                  color: const Color(0xFFFF9040).withOpacity(_isLooping ? 0.8 : 0.3),
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9040).withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  'LOOP',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // DAW-style Playhead (Cubase/Pro Tools style with triangle head)
                    Positioned(
                      left: (_playheadPosition / _timelineDuration) * zoomedWidth - 8, // Center the 16px wide playhead
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: 16,
                        child: CustomPaint(
                          size: Size(16, constraints.maxHeight),
                          painter: _SlotLabPlayheadPainter(isDragging: _isPlaying),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTrackTimeline(_SlotAudioTrack track, int index, double width) {
    final trackHeight = _getTrackHeight(track);
    final isDropTarget = _draggingRegion != null && _draggingRegionTrackIndex != index;

    return DragTarget<_AudioRegion>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        // Move region from source track to this track
        final region = details.data;
        final sourceTrackIndex = _draggingRegionTrackIndex;
        if (sourceTrackIndex != null && sourceTrackIndex != index) {
          setState(() {
            // Remove from source track
            _tracks[sourceTrackIndex].regions.remove(region);
            // Update region color to match new track
            region.color = track.color;
            // Add to this track
            track.regions.add(region);
          });
        }
        _clearRegionDrag();
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: trackHeight,
          decoration: BoxDecoration(
            color: isDropTarget ? track.color.withOpacity(0.1) : null,
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              top: isDropTarget ? BorderSide(color: track.color, width: 2) : BorderSide.none,
            ),
          ),
          child: Stack(
            children: [
              // Regions - use FULL height, no padding
              ...track.regions.map((region) {
                final startX = (region.start / _timelineDuration) * width;
                final regionWidth = (region.duration / _timelineDuration) * width;
                final isDragging = _draggingRegion == region;

                return Positioned(
                  left: isDragging ? (_regionDragStartX ?? startX) : startX,
                  top: 0,  // Full height - no padding
                  bottom: 0,  // Full height - no padding
                  child: Opacity(
                    opacity: isDragging ? 0.5 : 1.0,
                    child: _buildDraggableRegion(region, track, index, regionWidth, trackHeight, width),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Build draggable audio region
  /// When collapsed: drag whole region
  /// When expanded: layers handle their own drag (region drag disabled)
  Widget _buildDraggableRegion(_AudioRegion region, _SlotAudioTrack track, int trackIndex, double regionWidth, double trackHeight, double totalWidth) {
    final duration = region.duration;
    final isExpanded = region.isExpanded && region.layers.length > 1;

    // When expanded, don't handle region drag - let individual layers handle it
    if (isExpanded) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Only tap/double-tap for selection/collapse
        onTap: () => _handleRegionTap(region, trackIndex),
        onDoubleTap: () => setState(() => region.isExpanded = false),
        onSecondaryTapDown: (details) => _showRegionContextMenu(details.globalPosition, region),
        child: _buildAudioRegionVisual(region, track.color, track.isMuted, regionWidth, trackHeight),
      );
    }

    // When collapsed, drag the whole region (multi-select drag support)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        // If dragging an unselected region, select only it first
        if (!region.isSelected) {
          _clearAllRegionSelections();
          region.isSelected = true;
        }

        // Store original positions for undo
        final selectedRegions = _getAllSelectedRegions();
        _dragStartPositions = {};
        for (final sr in selectedRegions) {
          _dragStartPositions![sr.id] = (start: sr.start, end: sr.end);
        }

        setState(() {
          _regionDragStartX = region.start;
          _regionDragOffsetX = 0;
          _draggingRegion = region;
          _draggingRegionTrackIndex = trackIndex;
        });
      },
      onPanUpdate: (details) {
        final timeDelta = (details.delta.dx / totalWidth) * _timelineDuration;
        setState(() {
          _regionDragOffsetX = (_regionDragOffsetX ?? 0) + timeDelta;

          // Move ALL selected regions together
          final selectedRegions = _getAllSelectedRegions();
          if (selectedRegions.isNotEmpty) {
            for (final sr in selectedRegions) {
              final newStart = sr.start + timeDelta;
              final clampedStart = newStart.clamp(0.0, _timelineDuration - sr.duration);
              sr.start = clampedStart;
              sr.end = clampedStart + sr.duration;
            }
          } else {
            // Fallback: move just the dragging region
            final newStart = (_regionDragStartX ?? region.start) + _regionDragOffsetX!;
            final clampedStart = newStart.clamp(0.0, _timelineDuration - duration);
            region.start = clampedStart;
            region.end = clampedStart + duration;
          }
        });
      },
      onPanEnd: (details) {
        _clearRegionDragWithUndo();
      },
      onTap: () => _handleRegionTap(region, trackIndex),
      onDoubleTap: region.layers.length > 1
          ? () => setState(() => region.isExpanded = !region.isExpanded)
          : null,
      onSecondaryTapDown: (details) => _showRegionContextMenu(details.globalPosition, region),
      child: _buildAudioRegionVisual(region, track.color, track.isMuted, regionWidth, trackHeight),
    );
  }

  /// Handle region tap with multi-select support (Cmd/Ctrl, Shift)
  void _handleRegionTap(_AudioRegion region, int trackIndex) {
    setState(() {
      final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
                          HardwareKeyboard.instance.isControlPressed;
      final isShift = HardwareKeyboard.instance.isShiftPressed;

      if (isShift && _lastClickedRegion != null && _lastClickedTrackIndex != null) {
        // Shift+click: Select range
        _selectRegionRange(_lastClickedRegion!, _lastClickedTrackIndex!, region, trackIndex);
      } else if (isCtrlOrCmd) {
        // Cmd/Ctrl+click: Toggle selection
        region.isSelected = !region.isSelected;
      } else {
        // Normal click: Select only this region
        _clearAllRegionSelections();
        region.isSelected = true;
      }

      // Remember last clicked for shift-select
      _lastClickedRegion = region;
      _lastClickedTrackIndex = trackIndex;
    });
  }

  /// Clear all region selections across all tracks
  void _clearAllRegionSelections() {
    for (final track in _tracks) {
      for (final region in track.regions) {
        region.isSelected = false;
      }
    }
  }

  /// Get all selected regions across all tracks
  List<_AudioRegion> _getAllSelectedRegions() {
    final selected = <_AudioRegion>[];
    for (final track in _tracks) {
      selected.addAll(track.regions.where((r) => r.isSelected));
    }
    return selected;
  }

  /// Select a range of regions (for shift+click)
  void _selectRegionRange(_AudioRegion startRegion, int startTrackIndex,
                          _AudioRegion endRegion, int endTrackIndex) {
    // Get all regions in order
    final allRegions = <({_AudioRegion region, int trackIndex})>[];
    for (int ti = 0; ti < _tracks.length; ti++) {
      for (final region in _tracks[ti].regions) {
        allRegions.add((region: region, trackIndex: ti));
      }
    }

    // Sort by track index, then by start time
    allRegions.sort((a, b) {
      final trackCmp = a.trackIndex.compareTo(b.trackIndex);
      if (trackCmp != 0) return trackCmp;
      return a.region.start.compareTo(b.region.start);
    });

    // Find indices of start and end
    final startIdx = allRegions.indexWhere((r) => r.region == startRegion);
    final endIdx = allRegions.indexWhere((r) => r.region == endRegion);

    if (startIdx < 0 || endIdx < 0) return;

    // Select range (inclusive)
    final fromIdx = startIdx < endIdx ? startIdx : endIdx;
    final toIdx = startIdx < endIdx ? endIdx : startIdx;

    for (int i = fromIdx; i <= toIdx; i++) {
      allRegions[i].region.isSelected = true;
    }
  }

  /// Select all regions across all tracks
  void _selectAllRegions() {
    setState(() {
      for (final track in _tracks) {
        for (final region in track.regions) {
          region.isSelected = true;
        }
      }
    });
    debugPrint('[SlotLab] Selected all regions');
  }

  /// Invert current region selection
  void _invertRegionSelection() {
    setState(() {
      for (final track in _tracks) {
        for (final region in track.regions) {
          region.isSelected = !region.isSelected;
        }
      }
    });
    debugPrint('[SlotLab] Inverted region selection');
  }

  /// Toggle mute on all selected regions
  void _toggleMuteSelectedRegions() {
    final selected = _getAllSelectedRegions();
    if (selected.isEmpty) return;

    // If any are unmuted, mute all. Otherwise unmute all.
    final anyUnmuted = selected.any((r) => !r.isMuted);
    setState(() {
      for (final region in selected) {
        region.isMuted = anyUnmuted;
      }
    });
    debugPrint('[SlotLab] ${anyUnmuted ? "Muted" : "Unmuted"} ${selected.length} regions');
  }

  void _clearRegionDrag() {
    // Sync region offset to MiddlewareProvider before clearing
    if (_draggingRegion != null) {
      _syncRegionOffsetToProvider(_draggingRegion!);
    }

    setState(() {
      _draggingRegion = null;
      _draggingRegionTrackIndex = null;
      _regionDragStartX = null;
      _regionDragOffsetX = null;
      _dragStartPositions = null;
    });
  }

  /// Clear region drag with undo recording
  void _clearRegionDragWithUndo() {
    if (_draggingRegion == null || _dragStartPositions == null) {
      _clearRegionDrag();
      return;
    }

    // Sync to provider first
    _syncRegionOffsetToProvider(_draggingRegion!);

    // Check if anything actually moved
    final selectedRegions = _getAllSelectedRegions();
    bool hasMoved = false;
    for (final sr in selectedRegions) {
      final original = _dragStartPositions![sr.id];
      if (original != null && (sr.start != original.start || sr.end != original.end)) {
        hasMoved = true;
        break;
      }
    }

    // Record undo action if moved
    if (hasMoved) {
      final oldPositions = Map<String, ({double start, double end})>.from(_dragStartPositions!);
      final newPositions = <String, ({double start, double end})>{};
      for (final sr in selectedRegions) {
        newPositions[sr.id] = (start: sr.start, end: sr.end);
      }

      UiUndoManager.instance.record(GenericUndoAction(
        description: selectedRegions.length > 1
            ? 'Move ${selectedRegions.length} regions'
            : 'Move region',
        onExecute: () {
          setState(() {
            for (final sr in selectedRegions) {
              final pos = newPositions[sr.id];
              if (pos != null) {
                sr.start = pos.start;
                sr.end = pos.end;
              }
            }
          });
        },
        onUndo: () {
          setState(() {
            for (final sr in selectedRegions) {
              final pos = oldPositions[sr.id];
              if (pos != null) {
                sr.start = pos.start;
                sr.end = pos.end;
                _syncRegionOffsetToProvider(sr);
              }
            }
          });
        },
      ));
    }

    setState(() {
      _draggingRegion = null;
      _draggingRegionTrackIndex = null;
      _regionDragStartX = null;
      _regionDragOffsetX = null;
      _dragStartPositions = null;
    });
  }

  /// Sync region offset from timeline drag to MiddlewareProvider
  /// Updates ALL layers in the event with the new base offset
  void _syncRegionOffsetToProvider(_AudioRegion region) {
    // Find event by region name
    final event = _compositeEvents.where((e) => e.name == region.name).firstOrNull;
    if (event == null) return;

    // Region start position in milliseconds is the base offset for all layers
    final baseOffsetMs = region.start * 1000.0;

    // Update each layer's offset
    for (final eventLayer in event.layers) {
      // Find corresponding region layer to get individual offset
      final regionLayer = region.layers.where((l) => l.audioPath == eventLayer.audioPath).firstOrNull;
      final layerLocalOffsetMs = (regionLayer?.offset ?? 0) * 1000.0;

      // Total offset = region start + layer local offset
      final totalOffsetMs = baseOffsetMs + layerLocalOffsetMs;

      _middleware.setLayerOffset(event.id, eventLayer.id, totalOffsetMs);
    }

    debugPrint('[SlotLab] Synced region "${region.name}" to ${baseOffsetMs.toStringAsFixed(0)}ms');
  }

  /// Calculate track height based on expanded regions
  /// Collapsed = single layer height, Expanded = all layers equal height
  /// CRITICAL: Reads layer count from EVENT (source of truth), NOT from region
  double _getTrackHeight(_SlotAudioTrack track) {
    const singleLayerHeight = 36.0;  // Height for one layer
    const layerHeight = 28.0;  // Height per layer when expanded

    // Check if any region is expanded with multiple layers
    for (final region in track.regions) {
      // Get ACTUAL layer count from event
      final event = _compositeEvents.where((e) => e.name == region.name).firstOrNull;
      final actualLayerCount = event?.layers.length ?? 0;

      if (region.isExpanded && actualLayerCount > 1) {
        // Expanded: all layers equal height
        return actualLayerCount * layerHeight;
      }
    }
    return singleLayerHeight;
  }

  /// Visual-only widget for audio region (no gestures - handled by parent for whole region drag)
  /// When expanded, each layer can be dragged individually across entire timeline
  /// IMPORTANT: Reads layers directly from EVENT (source of truth), NOT from region
  Widget _buildAudioRegionVisual(_AudioRegion region, Color trackColor, bool muted, double regionWidth, double trackHeight) {
    final width = regionWidth.clamp(20.0, 4000.0);

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: Get layers from EVENT (source of truth), NOT from region
    // This ensures deleted layers don't appear on timeline
    // ═══════════════════════════════════════════════════════════════════════════
    final event = _compositeEvents.where((e) => e.name == region.name).firstOrNull;

    // ═══════════════════════════════════════════════════════════════════════════
    // SYNC REGION START FROM PROVIDER (source of truth)
    // Region start = minimum offsetMs of all layers (converted to seconds)
    // ═══════════════════════════════════════════════════════════════════════════
    if (event != null && event.layers.isNotEmpty) {
      final minOffsetMs = event.layers.map((l) => l.offsetMs).reduce((a, b) => a < b ? a : b);
      final regionStartFromProvider = minOffsetMs / 1000.0;
      // Only update if not currently dragging this region
      if (_draggingRegion != region) {
        region.start = regionStartFromProvider;
        // Recalculate end based on max layer end
        double maxEnd = region.start + 0.5; // Minimum 0.5s
        for (final layer in event.layers) {
          final layerStart = layer.offsetMs / 1000.0;
          final layerDur = layer.durationSeconds ?? _getAudioDuration(layer.audioPath);
          final layerEnd = layerStart + layerDur;
          if (layerEnd > maxEnd) maxEnd = layerEnd;
        }
        region.end = maxEnd;
      }
    }

    // Build region layers from event layers (live sync)
    // CRITICAL: Use eventLayerId for matching, NOT audioPath (supports duplicates)
    final List<_RegionLayer> liveLayers = (event?.layers ?? []).map((el) {
      // Get offset from provider (source of truth) - convert ms to seconds
      // offsetMs is absolute position, we need relative to region.start
      final providerOffsetSec = el.offsetMs / 1000.0;
      final relativeOffset = providerOffsetSec - region.start;

      // Try to find existing region layer by eventLayerId (unique, supports duplicates)
      final existingLayer = region.layers.firstWhere(
        (rl) => rl.eventLayerId == el.id, // ✅ Use unique eventLayerId, not audioPath
        orElse: () => _RegionLayer(
          id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
          eventLayerId: el.id, // ✅ Store eventLayerId for future matching
          audioPath: el.audioPath,
          name: el.name,
          duration: _getAudioDuration(el.audioPath),
        ),
      );

      // Ensure eventLayerId is set (for layers created before this fix)
      if (existingLayer.eventLayerId == null) {
        // Can't modify final field, but this layer will be replaced next sync
      }

      // CRITICAL: Sync offset from provider (source of truth)
      // But only if not currently dragging this layer (via controller)
      final isDraggingThisLayer = _dragController?.isDraggingLayer(el.id) ?? false;
      if (!isDraggingThisLayer) {
        existingLayer.offset = relativeOffset.clamp(-region.start, _timelineDuration);
      }

      return existingLayer;
    }).toList();

    final hasLayers = liveLayers.isNotEmpty;
    final layerCount = liveLayers.length;
    final isExpanded = region.isExpanded && layerCount > 1;

    if (isExpanded) {
      // EXPANDED: No border, layers are shown as free-floating tracks
      return SizedBox(
        width: width,
        height: trackHeight,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: liveLayers.asMap().entries.map((entry) {
            final index = entry.key;
            final layer = entry.value;
            return Expanded(
              child: _buildDraggableLayerRow(layer, region, index, region.color, muted, width),
            );
          }).toList(),
        ),
      );
    }

    // COLLAPSED: Normal region with border + delete button
    return MouseRegion(
      cursor: _draggingRegion == region ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: Container(
        width: width,
        height: trackHeight,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: region.isSelected
                ? Colors.white
                : (muted ? Colors.grey : region.color),
            width: region.isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            // Region content
            Positioned.fill(
              child: hasLayers
                  ? _buildLayerRow(liveLayers.first, region.color, muted, true, layerCount)
                  : _buildEmptyRegionRow(region, muted),
            ),
            // Delete button for layer - deletes ONLY layer, NOT entire event
            // When collapsed, delete the first (only visible) layer
            if (hasLayers)
              Positioned(
                right: 4,
                top: 4,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _deleteLayerFromTimeline(region, liveLayers.first),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build a draggable layer row - can be moved freely across entire timeline
  /// Uses layer.duration for REAL audio file width, not region width
  /// NOW USES TimelineDragController for centralized drag state management
  Widget _buildDraggableLayerRow(_RegionLayer layer, _AudioRegion region, int layerIndex, Color color, bool muted, double regionWidth) {
    // Use controller for drag state (survives widget rebuilds)
    final isDragging = _dragController?.isDraggingLayer(layer.eventLayerId ?? '') ?? false;
    final pixelsPerSecond = regionWidth / region.duration;

    // During drag, use controller's delta; otherwise use layer.offset from provider
    double currentOffset = layer.offset;
    if (isDragging) {
      currentOffset = dragController.getLayerCurrentPosition();
    }

    final offsetPixels = currentOffset * pixelsPerSecond;
    // Use REAL layer duration for width, not region width
    final layerWidth = layer.duration * pixelsPerSecond;

    // Find parent event ID for controller
    final parentEvent = _compositeEvents.where((e) => e.name == region.name).firstOrNull;
    final parentEventId = parentEvent?.id ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) {
        if (layer.eventLayerId == null) return;
        // Start drag via controller (no setState needed - controller notifies)
        dragController.startLayerDrag(
          layerEventId: layer.eventLayerId!,
          parentEventId: parentEventId,
          regionId: region.id,
          startOffsetSeconds: layer.offset,
          regionStartSeconds: region.start,
        );
      },
      onHorizontalDragUpdate: (details) {
        // Check via controller (survives rebuilds)
        if (!dragController.isDraggingLayer(layer.eventLayerId ?? '')) return;
        final timeDelta = details.delta.dx / pixelsPerSecond;
        // Update via controller (no setState needed)
        dragController.updateLayerDrag(timeDelta);
      },
      onHorizontalDragEnd: (details) {
        // End drag and sync to provider via controller
        dragController.endLayerDrag();
      },
      child: MouseRegion(
        cursor: isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Layer content positioned with offset - width based on REAL duration
            Positioned(
              left: offsetPixels,
              top: 1,
              bottom: 1,
              width: layerWidth.clamp(20.0, regionWidth), // Real duration width, min 20px
              child: Opacity(
                opacity: isDragging ? 0.7 : 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isDragging ? Colors.white : color.withOpacity(0.6),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _buildLayerRowContent(layer, color, muted),
                ),
              ),
            ),
            // Offset indicator when layer is offset
            if (layer.offset.abs() > 0.001)
              Positioned(
                left: offsetPixels + 4,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${layer.offset >= 0 ? '+' : ''}${(layer.offset * 1000).toStringAsFixed(0)}ms',
                    style: const TextStyle(color: Colors.white70, fontSize: 7),
                  ),
                ),
              ),
            // Delete button for layer - positioned at right edge of layer, moves with it
            Positioned(
              left: offsetPixels + layerWidth.clamp(20.0, regionWidth) - 16,
              top: 2,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _deleteLayerFromTimeline(region, layer),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(Icons.close, size: 10, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build layer row content (waveform + name) without border
  Widget _buildLayerRowContent(_RegionLayer layer, Color color, bool muted) {
    final waveformData = _getWaveformForPath(layer.audioPath);
    final hasWaveform = waveformData != null && waveformData.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (muted ? Colors.grey : color).withOpacity(0.4),
            (muted ? Colors.grey : color).withOpacity(0.25),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Waveform background
          if (hasWaveform)
            Positioned.fill(
              child: CustomPaint(
                painter: _WaveformPainter(
                  data: waveformData,
                  color: (muted ? Colors.grey : color).withOpacity(0.6),
                ),
              ),
            ),
          // Layer name
          Positioned(
            left: 4,
            top: 2,
            right: 4,
            child: Text(
              layer.name,
              style: TextStyle(
                color: muted ? Colors.grey : Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEGACY DRAG METHODS (kept for backward compatibility, prefer controller)
  // ═══════════════════════════════════════════════════════════════════════════

  /// @deprecated Use TimelineDragController.endLayerDrag() instead
  void _clearLayerDrag() {
    // Now handled by controller - this is kept for any legacy code paths
    if (_dragController != null) {
      _dragController!.cancelLayerDrag();
      return;
    }

    // Legacy fallback (should not be reached)
    setState(() {
      _draggingLayer = null;
      _draggingLayerRegion = null;
      _draggingLayerEventId = null;
      _layerDragStartOffset = null;
      _layerDragDelta = null;
    });
  }

  /// @deprecated Use TimelineDragController.endLayerDrag() instead
  /// Sync layer offset from timeline drag to MiddlewareProvider
  void _syncLayerOffsetToProvider(_RegionLayer layer, _AudioRegion region) {
    // Now handled by controller - this is kept for any legacy code paths
    final event = _compositeEvents.where((e) => e.name == region.name).firstOrNull;
    if (event == null) return;

    final eventLayer = layer.eventLayerId != null
        ? event.layers.where((l) => l.id == layer.eventLayerId).firstOrNull
        : event.layers.where((l) => l.audioPath == layer.audioPath).firstOrNull;
    if (eventLayer == null) return;

    final totalOffsetMs = (region.start + layer.offset) * 1000.0;
    _middleware.setLayerOffset(event.id, eventLayer.id, totalOffsetMs);
    debugPrint('[SlotLab] Synced layer "${layer.name}" offset: ${totalOffsetMs.toStringAsFixed(0)}ms');
  }

  /// Build a single layer row with waveform and name
  Widget _buildLayerRow(_RegionLayer layer, Color color, bool muted, bool showExpandButton, int totalLayers) {
    final waveformData = _getWaveformForPath(layer.audioPath);
    final hasWaveform = waveformData != null && waveformData.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (muted ? Colors.grey : color).withOpacity(0.4),
            (muted ? Colors.grey : color).withOpacity(0.25),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: color.withOpacity(0.2), width: 0.5),
        ),
      ),
      child: Stack(
        children: [
          // Waveform background
          if (hasWaveform)
            Positioned.fill(
              child: CustomPaint(
                painter: _WaveformPainter(
                  data: waveformData,
                  color: (muted ? Colors.grey : color).withOpacity(0.6),
                ),
              ),
            ),
          // Layer info
          Positioned(
            left: 4,
            top: 2,
            right: 4,
            bottom: 2,
            child: Row(
              children: [
                // Expand button (only on first layer when multiple)
                if (showExpandButton && totalLayers > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.unfold_more,
                      size: 10,
                      color: muted ? Colors.grey : Colors.white54,
                    ),
                  ),
                // Layer name
                Expanded(
                  child: Text(
                    layer.name,
                    style: TextStyle(
                      color: muted ? Colors.grey : Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Layer count badge (only on first layer when collapsed)
                if (showExpandButton && totalLayers > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$totalLayers',
                      style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build empty region row (no layers)
  Widget _buildEmptyRegionRow(_AudioRegion region, bool muted) {
    final hasAudio = region.waveformData != null && region.waveformData!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (muted ? Colors.grey : region.color).withOpacity(0.4),
            (muted ? Colors.grey : region.color).withOpacity(0.25),
          ],
        ),
      ),
      child: Stack(
        children: [
          if (hasAudio)
            Positioned.fill(
              child: CustomPaint(
                painter: _WaveformPainter(
                  data: region.waveformData!,
                  color: muted ? Colors.grey : region.color,
                ),
              ),
            ),
          Positioned(
            left: 4,
            top: 2,
            child: Text(
              region.name,
              style: TextStyle(
                color: muted ? Colors.grey : Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get waveform data for an audio path from cache or load via FFI
  List<double>? _getWaveformForPath(String audioPath) {
    if (audioPath.isEmpty) return null;

    // 1. Check memory cache first (fastest)
    if (_waveformCache.containsKey(audioPath)) {
      return _waveformCache[audioPath];
    }

    // 2. Check disk cache (async, but start loading)
    _checkDiskCacheAsync(audioPath);

    // 3. Try audio pool
    for (final item in _audioPool) {
      final path = item['path'] as String? ?? '';
      if (path == audioPath || path.endsWith(audioPath.split('/').last)) {
        final waveform = item['waveform'];
        if (waveform is List && waveform.isNotEmpty) {
          final data = waveform.map((e) => (e as num).toDouble()).toList();
          _cacheWaveform(audioPath, data);
          return data;
        }
      }
    }

    // 4. Try to find clip ID in existing regions
    for (final track in _tracks) {
      for (final region in track.regions) {
        for (final layer in region.layers) {
          if (layer.audioPath == audioPath && layer.ffiClipId != null && layer.ffiClipId! > 0) {
            final data = _loadWaveformForClip(layer.ffiClipId!);
            if (data != null) {
              _cacheWaveform(audioPath, data);
              return data;
            }
          }
        }
      }
    }

    // 5. Check clip ID cache
    if (_clipIdCache.containsKey(audioPath)) {
      final clipId = _clipIdCache[audioPath]!;
      final data = _loadWaveformForClip(clipId);
      if (data != null) {
        _cacheWaveform(audioPath, data);
        return data;
      }
    }

    // 6. Try to load waveform asynchronously (will be available on next rebuild)
    _loadWaveformAsync(audioPath);

    return null;
  }

  /// Check disk cache for waveform asynchronously
  void _checkDiskCacheAsync(String audioPath) async {
    // Don't re-check if already in memory cache
    if (_waveformCache.containsKey(audioPath)) return;

    try {
      final waveform = await WaveformCacheService.instance.get(audioPath);
      if (waveform != null && waveform.isNotEmpty) {
        // Found in disk cache - add to memory cache
        _waveformCache[audioPath] = waveform;
        if (mounted) setState(() {});
        debugPrint('[SlotLab] Loaded waveform from disk cache: $audioPath');
      }
    } catch (e) {
      // Ignore disk cache errors
    }
  }

  /// Cache waveform in both memory and disk
  void _cacheWaveform(String audioPath, List<double> waveform) {
    // Memory cache
    _waveformCache[audioPath] = waveform;

    // Disk cache (async, fire and forget)
    WaveformCacheService.instance.put(audioPath, waveform);
  }

  /// Asynchronously load waveform for a path
  void _loadWaveformAsync(String audioPath) async {
    if (_clipIdCache.containsKey(audioPath) || !_ffi.isLoaded) return;

    // First check disk cache before doing expensive FFI import
    try {
      final diskWaveform = await WaveformCacheService.instance.get(audioPath);
      if (diskWaveform != null && diskWaveform.isNotEmpty) {
        _waveformCache[audioPath] = diskWaveform;
        if (mounted) setState(() {});
        debugPrint('[SlotLab] Loaded waveform from disk: $audioPath (${diskWaveform.length} peaks)');
        return;
      }
    } catch (_) {
      // Disk cache miss, continue with FFI load
    }

    try {
      // Import audio to get clip ID
      // CRITICAL: Use dedicated SlotLab preview track (ID 99999) to avoid
      // conflicting with DAW tracks (0, 1, 2...). This prevents waveform
      // corruption when switching between DAW and SlotLab.
      const slotLabPreviewTrack = 99999;
      final clipId = _ffi.importAudio(audioPath, slotLabPreviewTrack, 0.0);
      if (clipId > 0) {
        _clipIdCache[audioPath] = clipId;
        final waveform = _loadWaveformForClip(clipId);
        if (waveform != null && waveform.isNotEmpty) {
          // Cache in memory and disk
          _cacheWaveform(audioPath, waveform);
          // Trigger rebuild to show waveform
          if (mounted) setState(() {});
          debugPrint('[SlotLab] Loaded waveform via FFI: $audioPath (${waveform.length} peaks)');
        }
      }
    } catch (e) {
      debugPrint('[SlotLab] Async waveform load error: $e');
    }
  }

  void _handleAudioDrop(String audioPath, Offset globalPosition) {
    // Find which track was dropped on
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPosition = box.globalToLocal(globalPosition);

    // Create track if none exists
    if (_tracks.isEmpty) {
      _addTrack();
    }

    // Calculate drop position in timeline
    final trackIndex = _selectedTrackIndex ?? 0;
    if (trackIndex >= _tracks.length) return;

    // Find the audio info
    final audioInfo = _audioPool.firstWhere(
      (a) => a['path'] == audioPath,
      orElse: () => {'path': audioPath, 'name': audioPath.split('/').last, 'duration': 1.0},
    );

    // Get actual duration from FFI metadata (more accurate than pool data)
    final duration = _getAudioDuration(audioPath);
    final name = audioInfo['name'] as String;

    // Import audio to FFI engine for real playback
    int ffiClipId = 0;
    final track = _tracks[trackIndex];
    if (track.id.startsWith('ffi_') && audioPath.isNotEmpty) {
      try {
        final trackId = int.parse(track.id.substring(4));
        // Use importAudio to actually load the audio file into the engine
        // Start at 0 (beginning of timeline)
        ffiClipId = _ffi.importAudio(
          audioPath,
          trackId,
          0.0, // Always start at beginning
        );
        debugPrint('[SlotLab] Imported audio clip: $ffiClipId to track $trackId');
      } catch (e) {
        debugPrint('[SlotLab] FFI importAudio error: $e');
      }
    }

    // Load real waveform from clip - NO fake waveform for empty clips
    List<double>? waveformData;
    if (ffiClipId > 0) {
      waveformData = _loadWaveformForClip(ffiClipId);
    }
    // DO NOT generate fake waveform - null means no audio visualization

    // Create new region - always starts at 0 (beginning of timeline)
    final region = _AudioRegion(
      id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'region_${DateTime.now().millisecondsSinceEpoch}',
      start: 0.0,  // Always start at beginning
      end: duration,
      name: name,
      audioPath: audioPath,
      color: track.color,
      waveformData: waveformData,
    );

    setState(() {
      _tracks[trackIndex].regions.add(region);
      _draggingAudioPath = null;
      _dragPosition = null;
    });
  }

  /// Load real waveform data from FFI for a clip
  /// Returns min/max pairs for accurate waveform display
  List<double>? _loadWaveformForClip(int clipId) {
    if (clipId <= 0 || !_ffi.isLoaded) return null;
    try {
      // Use higher resolution for better waveform detail (512 peaks = 1024 values for min/max pairs)
      final peaks = _ffi.getWaveformPeaks(clipId, maxPeaks: 512);
      if (peaks.isNotEmpty) {
        debugPrint('[SlotLab] Loaded waveform with ${peaks.length} values (${peaks.length ~/ 2} peaks)');
        return peaks;
      }
    } catch (e) {
      debugPrint('[SlotLab] Waveform load error: $e');
    }
    return null;
  }

  /// Get audio duration from FFI metadata
  double _getAudioDuration(String audioPath) {
    if (audioPath.isEmpty || !_ffi.isLoaded) return 1.0;
    try {
      final metadataJson = NativeFFI.instance.audioGetMetadata(audioPath);
      if (metadataJson.isNotEmpty && metadataJson != 'null') {
        final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
        final duration = (metadata['duration'] as num?)?.toDouble();
        if (duration != null && duration > 0) {
          debugPrint('[SlotLab] Got duration for $audioPath: ${duration}s');
          return duration;
        }
      }
    } catch (e) {
      debugPrint('[SlotLab] Metadata error: $e');
    }
    return 1.0;
  }

  void _handleEventDrop(SlotCompositeEvent event, Offset globalPosition) {
    // Always create a NEW track for each event (middleware-style)
    final colors = [
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentGreen,
      FluxForgeTheme.accentBlue,
      FluxForgeTheme.accentCyan,
      const Color(0xFF9B59B6),
      const Color(0xFFF1C40F),
    ];
    final trackColor = colors[_tracks.length % colors.length];

    // Create FFI track for real playback
    int ffiTrackId = 0;
    try {
      ffiTrackId = _ffi.createTrack(event.name, trackColor.value, 2); // Bus ID 2 = SFX
      debugPrint('[SlotLab] Created event track: $ffiTrackId for ${event.name}');
    } catch (e) {
      debugPrint('[SlotLab] FFI createTrack error: $e');
    }

    final newTrack = _SlotAudioTrack(
      id: ffiTrackId > 0 ? 'ffi_$ffiTrackId' : 'track_${_tracks.length + 1}',
      name: event.name, // Track name = Event name
      color: trackColor,
    );

    // Empty events - create track header only, NO region on timeline
    if (event.layers.isEmpty) {
      setState(() {
        _tracks.add(newTrack);
        _selectedTrackIndex = _tracks.length - 1;
        _eventToRegionMap[event.id] = 'empty_${newTrack.id}'; // Track mapping without region
      });
      debugPrint('[SlotLab] Created empty track header: ${event.name}');
      _persistState();
      return;
    }

    // Calculate total duration from all layers (longest layer wins)
    double totalDuration = 0.0;
    for (final layer in event.layers) {
      final audioInfo = _audioPool.firstWhere(
        (a) => a['path'] == layer.audioPath,
        orElse: () => {'duration': 1.0},
      );
      final layerDuration = (audioInfo['duration'] as num?)?.toDouble() ?? 1.0;
      if (layerDuration > totalDuration) totalDuration = layerDuration;
    }
    if (totalDuration == 0.0) totalDuration = 1.0;

    // Import audio files for EACH layer (so all sounds play together, middleware-style)
    final List<_RegionLayer> regionLayers = [];
    List<double>? waveformData;
    int primaryClipId = 0;

    for (final layer in event.layers) {
      final audioInfo = _audioPool.firstWhere(
        (a) => a['path'] == layer.audioPath,
        orElse: () => {'path': layer.audioPath, 'name': layer.name, 'duration': 1.0},
      );
      final layerDuration = (audioInfo['duration'] as num?)?.toDouble() ?? 1.0;

      int ffiClipId = 0;
      if (ffiTrackId > 0 && layer.audioPath.isNotEmpty) {
        try {
          // Use importAudio to actually load the audio file into the engine
          // Region always starts at 0 (beginning of timeline)
          ffiClipId = _ffi.importAudio(
            layer.audioPath,
            ffiTrackId,
            layer.offsetMs, // startTime = delay offset from start
          );
          debugPrint('[SlotLab] Imported layer audio: $ffiClipId (${layer.name})');

          // Use first layer's clip for waveform
          if (primaryClipId == 0) {
            primaryClipId = ffiClipId;
          }
        } catch (e) {
          debugPrint('[SlotLab] FFI importAudio error: $e');
        }
      }

      regionLayers.add(_RegionLayer(
        id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}_${regionLayers.length}',
        eventLayerId: layer.id, // Track which event layer this maps to
        audioPath: layer.audioPath,
        name: layer.name,
        ffiClipId: ffiClipId > 0 ? ffiClipId : null,
        volume: layer.volume,
        delay: layer.offsetMs,
        duration: layerDuration, // REAL duration from pool
      ));
    }

    // Load real waveform from primary clip ONLY if we have actual audio
    // NO fake waveform - if no audio, waveformData stays null
    if (primaryClipId > 0) {
      waveformData = _loadWaveformForClip(primaryClipId);
    }
    // DO NOT generate fake waveform for empty events

    // Create region with all layers - always starts at 0 (top of timeline)
    final region = _AudioRegion(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      start: 0.0,  // Always start at beginning
      end: totalDuration,
      name: event.name,  // Region name = Event name
      color: trackColor,
      waveformData: waveformData,  // null if no real audio
      layers: regionLayers,
      isExpanded: false, // DEFAULT: collapsed - user expands manually
    );

    debugPrint('[SlotLab] Created region: ${region.name}, layers: ${regionLayers.length}, waveform: ${waveformData != null}');

    setState(() {
      _tracks.add(newTrack);
      _tracks.last.regions.add(region);
      _selectedTrackIndex = _tracks.length - 1;
      // Map event to region for auto-update
      _eventToRegionMap[event.id] = region.id;
    });

    // CRITICAL: Persist state so region survives screen switches
    _persistState();

    // Scroll to show the new track at the bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_headersScrollController.hasClients) {
        _headersScrollController.animateTo(
          _headersScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      if (_timelineScrollController.hasClients) {
        _timelineScrollController.animateTo(
          _timelineScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    debugPrint('[SlotLab] Event "${event.name}" added with ${event.layers.length} layers');
  }

  void _addTrack() {
    final colors = [
      const Color(0xFF40FF90),
      const Color(0xFF4A9EFF),
      const Color(0xFF9B59B6),
      const Color(0xFFF1C40F),
      const Color(0xFFE74C3C),
      const Color(0xFFFF9040),
    ];

    final trackColor = colors[_tracks.length % colors.length];
    final trackName = 'Track ${_tracks.length + 1}';

    // Create track in FFI engine for real audio playback
    int ffiTrackId = 0;
    try {
      ffiTrackId = _ffi.createTrack(trackName, trackColor.value, 2); // Bus ID 2 = SFX
      debugPrint('[SlotLab] Created FFI track: $ffiTrackId');
    } catch (e) {
      debugPrint('[SlotLab] FFI createTrack error: $e');
    }

    final newTrack = _SlotAudioTrack(
      id: ffiTrackId > 0 ? 'ffi_$ffiTrackId' : 'track_${_tracks.length + 1}',
      name: trackName,
      color: trackColor,
    );

    setState(() {
      _tracks.add(newTrack);
    });
  }

  void _toggleAllTracksExpanded() {
    setState(() {
      _allTracksExpanded = !_allTracksExpanded;
      // Expand or collapse all regions that have multiple layers
      for (final track in _tracks) {
        for (final region in track.regions) {
          if (region.layers.length > 1) {
            region.isExpanded = _allTracksExpanded;
          }
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOCK SLOT VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMockSlot() {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          // Premium Slot Preview Widget - fills available space
          Expanded(
            child: GlassSlotPreviewWrapper(
              isSpinning: _isSpinning,
              hasWin: _slotLabProvider.lastResult?.isWin ?? false,
              child: SlotPreviewWidget(
                provider: _slotLabProvider,
                reels: _reelCount,
                rows: _rowCount,
              ),
            ),
          ),
          // Compact Controls
          Container(
            width: 90,
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSlotButton('SPIN', const Color(0xFF40FF90), _handleSpin),
                const SizedBox(height: 4),
                if (_engineInitialized) ...[
                  _buildSmallButton('BIG', const Color(0xFFFF9040),
                      () => _handleEngineSpin(forcedOutcome: ForcedOutcome.bigWin)),
                  const SizedBox(height: 3),
                  _buildSmallButton('MEGA', const Color(0xFFFF4080),
                      () => _handleEngineSpin(forcedOutcome: ForcedOutcome.megaWin)),
                  const SizedBox(height: 3),
                  _buildSmallButton('FREE', const Color(0xFF40C8FF),
                      () => _handleEngineSpin(forcedOutcome: ForcedOutcome.freeSpins)),
                  const SizedBox(height: 3),
                  _buildSmallButton('JACK', const Color(0xFFFFD700),
                      () => _handleEngineSpin(forcedOutcome: ForcedOutcome.jackpotGrand)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReel(int reelIndex) {
    final isStoppedOrStopping = _currentStoppingReel >= reelIndex;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.2),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final symbolHeight = (constraints.maxHeight / _rowCount).clamp(12.0, 30.0);
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              _rowCount,
              (row) => SizedBox(
                height: symbolHeight,
                child: _buildSymbol(_reelSymbols[reelIndex][row], isStoppedOrStopping),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSymbol(String symbol, bool visible) {
    Color symbolColor;
    switch (symbol) {
      case '7':
        symbolColor = const Color(0xFFFF4040);
        break;
      case 'WILD':
        symbolColor = const Color(0xFFFFD700);
        break;
      case 'BONUS':
        symbolColor = const Color(0xFF40FF90);
        break;
      default:
        symbolColor = Colors.white;
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.3,
      child: Text(
        symbol,
        style: TextStyle(
          color: symbolColor,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSlotButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withOpacity(0.7)],
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  /// Small button for forced outcomes
  Widget _buildSmallButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isSpinning ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _isSpinning
                ? [Colors.grey, Colors.grey.shade700]
                : [color, color.withOpacity(0.7)],
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: _isSpinning
              ? []
              : [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _isSpinning ? Colors.grey.shade400 : Colors.black,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  void _handleSpin() {
    if (_isSpinning) return;

    // Use synthetic engine if available
    if (_engineInitialized) {
      _handleEngineSpin();
      return;
    }

    // Fallback to mock spin
    _handleMockSpin();
  }

  /// Spin using the Synthetic Slot Engine (real)
  void _handleEngineSpin({ForcedOutcome? forcedOutcome}) async {
    if (_isSpinning) return;

    // Stop all previous audio to prevent overlapping sounds
    try {
      final mw = Provider.of<MiddlewareProvider>(context, listen: false);
      mw.stopAllEvents(fadeMs: 50);
    } catch (_) {}

    setState(() {
      _isSpinning = true;
      _balance -= _bet;
      _currentStoppingReel = -1;
      _inAnticipation = false;
      _lastWin = 0;
    });

    // Update bet in engine
    _slotLabProvider.setBetAmount(_bet);

    // Execute spin (engine handles audio via stages)
    final result = forcedOutcome != null
        ? await _slotLabProvider.spinForced(forcedOutcome)
        : await _slotLabProvider.spin();

    if (result == null) {
      // Engine error, fallback to mock
      _handleMockSpin();
      return;
    }

    // Update UI with engine result
    _updateFromEngineResult(result);
  }

  void _updateFromEngineResult(SlotLabSpinResult result) {
    // Animate reel stops
    _startEngineReelSequence(result);
  }

  void _startEngineReelSequence(SlotLabSpinResult result) {
    final grid = result.grid;
    int reelIndex = 0;
    const reelDelay = Duration(milliseconds: 350);

    _spinTimer = Timer.periodic(reelDelay, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Check for anticipation (last 2 reels on potential big win)
      if (reelIndex >= 2 && reelIndex < _reelCount - 1 && !_inAnticipation) {
        // Trigger anticipation for big wins or near misses
        if (result.nearMiss || (result.isWin && result.winRatio >= 10.0)) {
          setState(() => _inAnticipation = true);
          // Audio triggered by stage events from engine
        }
      }

      // Update symbols for this reel
      if (reelIndex < grid.length) {
        setState(() {
          _reelSymbols[reelIndex] = _gridToSymbols([grid[reelIndex]])[0];
          _currentStoppingReel = reelIndex;
        });
      }

      reelIndex++;

      if (reelIndex >= _reelCount) {
        timer.cancel();
        _onEngineReelsStopped(result);
      }
    });
  }

  void _onEngineReelsStopped(SlotLabSpinResult result) {
    if (_inAnticipation) {
      setState(() => _inAnticipation = false);
    }

    // Update win display
    if (result.isWin) {
      setState(() {
        _lastWin = result.totalWin;
        _balance += result.totalWin;
      });
    }

    // Spin complete
    setState(() {
      _isSpinning = false;
    });
  }

  /// Mock spin (fallback when engine not available)
  void _handleMockSpin() {
    // Stop all previous audio to prevent overlapping sounds
    try {
      final mw = Provider.of<MiddlewareProvider>(context, listen: false);
      mw.stopAllEvents(fadeMs: 50);
    } catch (_) {}

    setState(() {
      _isSpinning = true;
      _balance -= _bet;
      _currentStoppingReel = -1;
      _inAnticipation = false;
      _lastWin = 0;
    });

    _postAudioEvent('slot_spin_start', context: {
      'bet_amount': _bet,
      'balance': _balance,
    });

    final normalizedBet = (_bet.clamp(0.1, 100) / 100).clamp(0.0, 1.0);
    _setRtpc(SlotRtpcIds.betLevel, normalizedBet);

    _startReelSequence();
  }

  void _startReelSequence() {
    _postAudioEvent('slot_reel_spin');

    int reelIndex = 0;
    const reelDelay = Duration(milliseconds: 400);

    _spinTimer = Timer.periodic(reelDelay, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (reelIndex >= 2 && reelIndex < _reelCount - 1 && !_inAnticipation) {
        if (_random.nextDouble() < 0.3) {
          _inAnticipation = true;
          _postAudioEvent('slot_anticipation_on');
          _setRtpc(SlotRtpcIds.tension, 0.8);
        }
      }

      setState(() {
        _currentStoppingReel = reelIndex;
      });
      _postAudioEvent('slot_reel_stop');

      reelIndex++;

      if (reelIndex >= _reelCount) {
        timer.cancel();
        _onAllReelsStopped();
      }
    });
  }

  void _onAllReelsStopped() {
    if (_inAnticipation) {
      _inAnticipation = false;
      _postAudioEvent('slot_anticipation_off');
      _setRtpc(SlotRtpcIds.tension, 0.0);
    }

    _postAudioEvent('slot_spin_end');

    final hasWin = _random.nextDouble() < 0.4;
    final winMultiplier = hasWin ? (_random.nextDouble() * 50 + 1) : 0.0;
    final winAmount = _bet * winMultiplier;

    if (hasWin && winAmount > 0) {
      _handleWin(winAmount, winMultiplier);
    } else {
      setState(() {
        _isSpinning = false;
        _lastWin = 0;
      });
    }
  }

  void _handleWin(double amount, double multiplier) {
    setState(() {
      _lastWin = amount;
      _balance += amount;
    });

    _setRtpc(SlotRtpcIds.winMultiplier, multiplier.clamp(0.0, 1000.0));

    if (multiplier >= 100) {
      _postAudioEvent('slot_bigwin_tier_epic', context: {
        'win_amount': amount,
        'bet_amount': _bet,
        'multiplier': multiplier,
      });
    } else if (multiplier >= 50) {
      _postAudioEvent('slot_bigwin_tier_mega', context: {
        'win_amount': amount,
        'bet_amount': _bet,
        'multiplier': multiplier,
      });
    } else if (multiplier >= 20) {
      _postAudioEvent('slot_bigwin_tier_super', context: {
        'win_amount': amount,
        'bet_amount': _bet,
        'multiplier': multiplier,
      });
    } else if (multiplier >= 10) {
      _postAudioEvent('slot_bigwin_tier_nice', context: {
        'win_amount': amount,
        'bet_amount': _bet,
        'multiplier': multiplier,
      });
    } else {
      _postAudioEvent('slot_win_present', context: {
        'win_amount': amount,
        'bet_amount': _bet,
      });
    }

    _postAudioEvent('slot_rollup_start');

    final rollupDuration = Duration(milliseconds: (500 + multiplier * 20).toInt().clamp(500, 3000));

    Future.delayed(rollupDuration, () {
      if (mounted) {
        _postAudioEvent('slot_rollup_end');
        _setRtpc(SlotRtpcIds.winMultiplier, 0.0);
        setState(() {
          _isSpinning = false;
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT PANEL - Event Editor + Audio Browser
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRightPanel() {
    return Container(
      width: 280,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF121216).withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Composite Events
          Expanded(
            flex: 2,
            child: _buildCompositeEventsPanel(),
          ),

          const Divider(color: Color(0xFF2A2A35), height: 1),

          // Audio Browser
          if (_showAudioBrowser)
            Expanded(
              flex: 3,
              child: _buildAudioBrowser(),
            ),
        ],
      ),
    );
  }

  Widget _buildCompositeEventsPanel() {
    // Use Consumer to ensure we always get fresh data from MiddlewareProvider
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;
        return Column(
          children: [
            _buildPanelHeader('COMPOSITE EVENTS', Icons.layers),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A22),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: _createCompositeEvent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF40FF90).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF40FF90).withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 12, color: Color(0xFF40FF90)),
                          SizedBox(width: 4),
                          Text('Create Event', style: TextStyle(color: Color(0xFF40FF90), fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${events.length} events',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.layers, size: 32, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(height: 8),
                          const Text(
                            'No composite events',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Drag audio to timeline to create',
                            style: TextStyle(color: Colors.white24, fontSize: 9),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: events.length,
                      itemBuilder: (context, index) => _buildCompositeEventItem(events[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompositeEventItem(SlotCompositeEvent event) {
    final isSelected = _selectedEventId == event.id;

    // Make event draggable to timeline
    return Draggable<SlotCompositeEvent>(
      data: event,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentOrange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: FluxForgeTheme.accentOrange.withOpacity(0.5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.layers, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                event.name,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildCompositeEventContent(event, isSelected),
      ),
      child: DragTarget<String>(
        onAcceptWithDetails: (details) {
          // Audio dropped on event - add as layer
          // Use event.id to get fresh data, not stale closure-captured event
          final freshEvent = _compositeEvents.firstWhere(
            (e) => e.id == event.id,
            orElse: () => event,
          );
          _addLayerToEvent(freshEvent, details.data);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedEventId = event.id;
              _eventExpandedState[event.id] = !_isEventExpanded(event.id);
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isHovering
                    ? FluxForgeTheme.accentGreen.withOpacity(0.2)
                    : (isSelected ? FluxForgeTheme.accentBlue.withOpacity(0.15) : const Color(0xFF1A1A22)),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isHovering
                      ? FluxForgeTheme.accentGreen
                      : (isSelected ? FluxForgeTheme.accentBlue : Colors.white.withOpacity(0.1)),
                  width: isHovering ? 2 : 1,
                ),
              ),
              child: _buildCompositeEventContent(event, isSelected),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompositeEventContent(SlotCompositeEvent event, bool isSelected) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(
                _isEventExpanded(event.id) ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: Colors.white54,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Stage: ${_getEventStage(event)} • Drag audio here',
                      style: const TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ],
                ),
              ),
              Text(
                '${event.layers.length} layers',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
              const SizedBox(width: 8),
              // Delete event button
              InkWell(
                onTap: () => _deleteCompositeEvent(event),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4060).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFFF4060)),
                ),
              ),
            ],
          ),
        ),
        if (_isEventExpanded(event.id))
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
            ),
            child: event.layers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Drop audio files here',
                        style: TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  )
                : Column(
                    children: event.layers.map((layer) => _buildLayerItem(event, layer)).toList(),
                  ),
          ),
      ],
    );
  }

  void _addLayerToEvent(SlotCompositeEvent event, String audioPath) {
    final audioInfo = _audioPool.firstWhere(
      (a) => a['path'] == audioPath,
      orElse: () => {'path': audioPath, 'name': audioPath.split('/').last, 'duration': 1.0},
    );

    // Add layer via MiddlewareProvider (single source of truth)
    // _onMiddlewareChanged listener will automatically rebuild region
    _addLayerToMiddlewareEvent(event.id, audioPath, audioInfo['name'] as String);

    setState(() {
      _eventExpandedState[event.id] = true;
    });

    _persistState();
  }

  /// Rebuild region to exactly match event layers - called after ANY layer change
  void _rebuildRegionForEvent(SlotCompositeEvent event) {
    // Find track with matching name
    final trackIndex = _tracks.indexWhere((t) => t.name == event.name);
    if (trackIndex < 0) return;

    final track = _tracks[trackIndex];

    // Check if region already exists by:
    // 1. Using _eventToRegionMap (primary)
    // 2. Fallback: searching by name
    _AudioRegion? existingRegion;
    final mappedRegionId = _eventToRegionMap[event.id];
    if (mappedRegionId != null) {
      existingRegion = track.regions.where((r) => r.id == mappedRegionId).firstOrNull;
    }
    existingRegion ??= track.regions.where((r) => r.name == event.name).firstOrNull;

    if (existingRegion != null) {
      // Region exists - just sync layers, preserve position
      _syncRegionLayersToEvent(existingRegion, event, track);
      // Ensure map is updated
      _eventToRegionMap[event.id] = existingRegion.id;
      return;
    }

    // No existing region - create new one (only happens on first drop)
    // No region to delete since we checked above
    _eventToRegionMap.remove(event.id);

    // If event has no layers, done (track header only)
    if (event.layers.isEmpty) return;

    // Get region start from provider (source of truth)
    double regionStart = 0.0;
    if (event.layers.isNotEmpty) {
      final minOffsetMs = event.layers.map((l) => l.offsetMs).reduce((a, b) => a < b ? a : b);
      regionStart = minOffsetMs / 1000.0;
    }

    // Create fresh region with EXACTLY event's current layers
    final List<_RegionLayer> regionLayers = [];
    double maxEnd = regionStart + 0.5;

    for (final el in event.layers) {
      final dur = _getAudioDuration(el.audioPath);
      final layerStart = el.offsetMs / 1000.0;
      final layerEnd = layerStart + dur;
      if (layerEnd > maxEnd) maxEnd = layerEnd;

      int ffiClipId = 0;
      if (track.id.startsWith('ffi_')) {
        try {
          final tid = int.parse(track.id.substring(4));
          ffiClipId = _ffi.importAudio(el.audioPath, tid, 0.0);
        } catch (_) {}
      }

      regionLayers.add(_RegionLayer(
        id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}_${regionLayers.length}',
        eventLayerId: el.id, // Track which event layer this maps to
        audioPath: el.audioPath,
        name: el.name,
        ffiClipId: ffiClipId > 0 ? ffiClipId : null,
        duration: dur,
        offset: (el.offsetMs / 1000.0) - regionStart, // Relative offset from region start
      ));
    }

    final newRegion = _AudioRegion(
      id: 'region_${DateTime.now().millisecondsSinceEpoch}',
      name: event.name,
      start: regionStart,
      end: maxEnd,
      color: track.color,
      layers: regionLayers,
      isExpanded: regionLayers.length > 1,
    );

    track.regions.add(newRegion);
    _eventToRegionMap[event.id] = newRegion.id;
  }

  /// Sync region layers to exactly match event layers (remove old, add missing)
  void _syncRegionLayersToEvent(_AudioRegion region, SlotCompositeEvent event, _SlotAudioTrack track) {
    // Get event layer IDs for comparison (use ID, not audioPath - allows duplicates)
    final eventLayerIds = event.layers.map((l) => l.id).toSet();

    // Remove region layers whose eventLayerId no longer exists in event
    region.layers.removeWhere((rl) => rl.eventLayerId != null && !eventLayerIds.contains(rl.eventLayerId));

    // Add missing layers from event (by eventLayerId, not audioPath)
    for (final eventLayer in event.layers) {
      final existsInRegion = region.layers.any((rl) => rl.eventLayerId == eventLayer.id);
      if (!existsInRegion) {
        // Import to FFI
        final layerDuration = _getAudioDuration(eventLayer.audioPath);
        int ffiClipId = 0;
        if (track.id.startsWith('ffi_')) {
          try {
            final trackId = int.parse(track.id.substring(4));
            ffiClipId = _ffi.importAudio(eventLayer.audioPath, trackId, 0.0);
          } catch (e) {
            debugPrint('[SlotLab] FFI import error: $e');
          }
        }

        region.layers.add(_RegionLayer(
          id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}_${region.layers.length}',
          eventLayerId: eventLayer.id, // Track which event layer this maps to
          audioPath: eventLayer.audioPath,
          name: eventLayer.name,
          ffiClipId: ffiClipId > 0 ? ffiClipId : null,
          duration: layerDuration,
          offset: eventLayer.offsetMs / 1000.0, // Sync offset from event
        ));
      }
    }

    // Update region duration
    double maxDuration = 1.0;
    for (final l in region.layers) {
      if (l.duration > maxDuration) maxDuration = l.duration;
    }
    region.end = region.start + maxDuration;

    // Auto-expand if multiple layers
    if (region.layers.length > 1) {
      region.isExpanded = true;
    }
  }

  /// Create region from ALL event layers (not just one)
  void _createRegionFromEventLayers(SlotCompositeEvent event, _SlotAudioTrack track) {

    final List<_RegionLayer> regionLayers = [];
    double maxDuration = 1.0;

    for (final eventLayer in event.layers) {
      final layerDuration = _getAudioDuration(eventLayer.audioPath);
      if (layerDuration > maxDuration) maxDuration = layerDuration;

      // Import to FFI
      int ffiClipId = 0;
      if (track.id.startsWith('ffi_')) {
        try {
          final trackId = int.parse(track.id.substring(4));
          ffiClipId = _ffi.importAudio(eventLayer.audioPath, trackId, 0.0);
        } catch (e) {
          debugPrint('[SlotLab] FFI import error: $e');
        }
      }

      regionLayers.add(_RegionLayer(
        id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}_${regionLayers.length}',
        eventLayerId: eventLayer.id, // Track which event layer this maps to
        audioPath: eventLayer.audioPath,
        name: eventLayer.name,
        ffiClipId: ffiClipId > 0 ? ffiClipId : null,
        duration: layerDuration,
      ));
    }

    final newRegion = _AudioRegion(
      id: 'region_${DateTime.now().millisecondsSinceEpoch}',
      name: event.name,
      start: 0.0,
      end: maxDuration,
      color: track.color,
      layers: regionLayers,
      isExpanded: regionLayers.length > 1,
    );

    track.regions.add(newRegion);
    _eventToRegionMap[event.id] = newRegion.id;

    debugPrint('[SlotLab] Created region "${newRegion.name}" with ${regionLayers.length} layers');
  }

  /// Create a new timeline region for an event (when region was deleted but event still exists)
  void _createRegionForEvent(SlotCompositeEvent event, Map<String, dynamic> audioInfo) {
    // Find track with matching name
    final trackIndex = _tracks.indexWhere((t) => t.name == event.name);
    if (trackIndex < 0) return;

    final track = _tracks[trackIndex];
    final audioPath = audioInfo['path'] as String? ?? '';
    final layerDuration = _getAudioDuration(audioPath);

    // Import to FFI
    int ffiClipId = 0;
    if (track.id.startsWith('ffi_')) {
      try {
        final trackId = int.parse(track.id.substring(4));
        ffiClipId = _ffi.importAudio(audioPath, trackId, 0.0);
        debugPrint('[SlotLab] Created new region - imported audio: $ffiClipId');
      } catch (e) {
        debugPrint('[SlotLab] FFI importAudio error: $e');
      }
    }

    // Create new region
    final newRegion = _AudioRegion(
      id: 'region_${DateTime.now().millisecondsSinceEpoch}',
      name: event.name,
      start: 0.0,
      end: layerDuration,
      color: track.color,
      layers: [
        _RegionLayer(
          id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}',
          audioPath: audioPath,
          name: audioInfo['name'] as String? ?? 'Audio',
          ffiClipId: ffiClipId > 0 ? ffiClipId : null,
          duration: layerDuration,
        ),
      ],
    );

    // Load waveform
    if (ffiClipId > 0) {
      newRegion.waveformData = _loadWaveformForClip(ffiClipId);
    }

    track.regions.add(newRegion);
    _eventToRegionMap[event.id] = newRegion.id;

    debugPrint('[SlotLab] Created new region "${newRegion.name}" for event "${event.name}"');
  }

  /// Update timeline region when audio is added to mapped event
  /// First removes any region layers not in event, then adds the new one
  void _updateTimelineRegionFromEvent(SlotCompositeEvent event, String regionId, Map<String, dynamic> audioInfo) {
    // Find the region in tracks
    for (final track in _tracks) {
      final regionIndex = track.regions.indexWhere((r) => r.id == regionId);
      if (regionIndex >= 0) {
        final region = track.regions[regionIndex];

        // SYNC: Remove any region layers that don't exist in event anymore
        final eventAudioPaths = event.layers.map((l) => l.audioPath).toSet();
        region.layers.removeWhere((rl) => !eventAudioPaths.contains(rl.audioPath));

        // Check if this audio already exists in region (by path)
        final audioPath = audioInfo['path'] as String? ?? '';
        final alreadyExists = region.layers.any((l) => l.audioPath == audioPath);
        if (alreadyExists) {
          debugPrint('[SlotLab] Layer already exists in region, skipping: $audioPath');
          return;
        }

        // Get actual duration from FFI metadata
        final layerDuration = _getAudioDuration(audioPath);

        // Import audio to FFI for playback
        int ffiClipId = 0;
        if (track.id.startsWith('ffi_') && audioInfo['path'] != null) {
          try {
            final trackId = int.parse(track.id.substring(4));
            ffiClipId = _ffi.importAudio(
              audioInfo['path'] as String,
              trackId,
              0.0, // Start at beginning
            );
            debugPrint('[SlotLab] Auto-imported layer audio: $ffiClipId');
          } catch (e) {
            debugPrint('[SlotLab] FFI importAudio error: $e');
          }
        }

        // Add layer to region
        region.layers.add(_RegionLayer(
          id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}',
          audioPath: audioPath,
          name: audioInfo['name'] as String? ?? 'Audio',
          ffiClipId: ffiClipId > 0 ? ffiClipId : null,
          duration: layerDuration, // REAL duration from FFI
        ));

        // Recalculate region duration based on longest layer
        double maxDuration = 0.0;
        for (final l in region.layers) {
          if (l.duration > maxDuration) maxDuration = l.duration;
        }
        region.end = region.start + maxDuration;

        // Load waveform if this is first layer with audio
        if (ffiClipId > 0 && (region.waveformData == null || region.waveformData!.isEmpty)) {
          region.waveformData = _loadWaveformForClip(ffiClipId);
        }

        // Auto-expand to show the new layer
        if (region.layers.length > 1) {
          region.isExpanded = true;
        }

        debugPrint('[SlotLab] Updated region ${region.id} with new layer: ${audioInfo['name']}');
        return;
      }
    }
  }

  Widget _buildLayerItem(SlotCompositeEvent event, SlotEventLayer layer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.audio_file, size: 12, color: Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              layer.name,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${(layer.volume * 100).toInt()}%',
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
          const SizedBox(width: 6),
          // Delete layer button
          InkWell(
            onTap: () => _deleteLayerFromEvent(event, layer),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4060).withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(Icons.close, size: 10, color: Color(0xFFFF4060)),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete entire composite event (also deletes timeline region AND track header)
  void _deleteCompositeEvent(SlotCompositeEvent event) {
    final eventId = event.id;
    final eventName = event.name;

    setState(() {
      // Delete associated timeline region - try by ID mapping first
      String? regionId = _eventToRegionMap[eventId];

      // If no ID mapping, try to find by name
      if (regionId == null) {
        for (final track in _tracks) {
          for (final region in track.regions) {
            if (region.name == eventName) {
              regionId = region.id;
              break;
            }
          }
          if (regionId != null) break;
        }
      }

      // Remove the region from timeline
      if (regionId != null) {
        final localRegionId = regionId;
        for (final track in _tracks) {
          track.regions.removeWhere((r) => r.id == localRegionId);
        }
        _eventToRegionMap.remove(eventId);
      } else {
        // Fallback: remove any region with matching name
        for (final track in _tracks) {
          track.regions.removeWhere((r) => r.name == eventName);
        }
      }

      // Also delete track header with same name
      final trackIndex = _tracks.indexWhere((t) => t.name == eventName);
      if (trackIndex >= 0) {
        _tracks.removeAt(trackIndex);
        // Adjust selection
        if (_selectedTrackIndex == trackIndex) {
          _selectedTrackIndex = _tracks.isNotEmpty ? 0 : null;
        } else if (_selectedTrackIndex != null && _selectedTrackIndex! > trackIndex) {
          _selectedTrackIndex = _selectedTrackIndex! - 1;
        }
        debugPrint('[SlotLab] Also deleted track header: $eventName');
      }

      // Clear selection if this was selected
      if (_selectedEventId == eventId) {
        _selectedEventId = null;
      }
    });

    // Delete from Middleware (single source of truth) and EventRegistry
    _deleteMiddlewareEvent(eventId);

    _persistState();
    debugPrint('[SlotLab] Deleted event, region and track: $eventName');
  }

  /// Delete entire track with all its regions (syncs to composite events)
  void _deleteTrack(_SlotAudioTrack track, int index) {
    // Find event by name before deletion (using Middleware as source of truth)
    final event = _findEventByName(track.name);
    final deletedEventId = event?.id;

    setState(() {
      // Sync delete all regions to composite events
      for (final region in track.regions) {
        _syncRegionDeleteToEvent(region);
      }

      // Clear mapping and selection for this event
      if (deletedEventId != null) {
        _eventToRegionMap.remove(deletedEventId);
        if (_selectedEventId == deletedEventId) {
          _selectedEventId = null;
        }
      }

      // Remove track
      _tracks.removeAt(index);

      // Clear selection if this was selected
      if (_selectedTrackIndex == index) {
        _selectedTrackIndex = _tracks.isNotEmpty ? 0 : null;
      } else if (_selectedTrackIndex != null && _selectedTrackIndex! > index) {
        _selectedTrackIndex = _selectedTrackIndex! - 1;
      }
    });

    // Delete from Middleware (single source of truth) and EventRegistry
    if (deletedEventId != null) {
      _deleteMiddlewareEvent(deletedEventId);
      debugPrint('[SlotLab] Also deleted composite event: ${track.name}');
    }

    _persistState();
    debugPrint('[SlotLab] Deleted track: ${track.name}');
  }

  /// Delete entire region from timeline (syncs to composite event too)
  void _deleteRegionFromTimeline(_AudioRegion region) {
    setState(() {
      // Sync delete to composite event first
      _syncRegionDeleteToEvent(region);

      // Remove region from tracks
      for (final track in _tracks) {
        track.regions.removeWhere((r) => r.id == region.id);
      }
    });

    _persistState();
    debugPrint('[SlotLab] Deleted region from timeline: ${region.name}');
  }

  /// Delete a layer from timeline - removes from event and rebuilds region
  /// Uses MiddlewareProvider as single source of truth
  void _deleteLayerFromTimeline(_AudioRegion region, _RegionLayer layer) {
    // Find event by name from Middleware
    final middlewareEvent = _findEventByName(region.name);
    if (middlewareEvent == null) return;

    // Find layer ID to remove
    final layerToRemove = middlewareEvent.layers.where(
      (l) => l.audioPath == layer.audioPath,
    ).firstOrNull;

    if (layerToRemove != null) {
      debugPrint('[SlotLab] Deleting layer from timeline: ${layer.name}');
      debugPrint('[SlotLab] Event "${middlewareEvent.name}" had ${middlewareEvent.layers.length} layers');

      // Remove layer via MiddlewareProvider (single source of truth)
      _removeLayerFromMiddlewareEvent(middlewareEvent.id, layerToRemove.id);

      debugPrint('[SlotLab] Synced layer deletion to Middleware');

      // Rebuild region from updated event
      setState(() {
        final updatedEvent = _findEventById(middlewareEvent.id);
        if (updatedEvent != null) {
          _rebuildRegionForEvent(updatedEvent);
        }
      });
    }

    _persistState();
  }

  void _deleteLayerFromEvent(SlotCompositeEvent event, SlotEventLayer layer) {
    // Remove layer via MiddlewareProvider (single source of truth)
    _removeLayerFromMiddlewareEvent(event.id, layer.id);

    // Rebuild region from updated event
    setState(() {
      final updatedEvent = _findEventById(event.id);
      if (updatedEvent != null) {
        _rebuildRegionForEvent(updatedEvent);
      }
    });

    _syncEventToRegistry(_findEventById(event.id));
    _persistState();
  }

  void _createCompositeEvent() {
    final controller = TextEditingController(text: 'Event ${_compositeEvents.length + 1}');
    String selectedStage = 'SPIN_START';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          title: const Text('Create Event', style: TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name input
              const Text('Name:', style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Enter event name...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onSubmitted: (_) {
                  _finishCreateEvent(controller.text.trim(), selectedStage);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 12),
              // Stage dropdown
              const Text('Stage:', style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButton<String>(
                  value: selectedStage,
                  isExpanded: true,
                  dropdownColor: FluxForgeTheme.bgDeep,
                  underline: const SizedBox(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  menuMaxHeight: 400,
                  items: _allStageOptions.map((stage) => DropdownMenuItem(
                    value: stage,
                    child: Text(stage, style: TextStyle(
                      color: _isCommonStage(stage) ? Colors.white : Colors.white70,
                      fontWeight: _isCommonStage(stage) ? FontWeight.w600 : FontWeight.normal,
                    )),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedStage = v!),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                _finishCreateEvent(controller.text.trim(), selectedStage);
                Navigator.pop(ctx);
              },
              child: const Text('Create', style: TextStyle(color: FluxForgeTheme.accentBlue)),
            ),
          ],
        ),
      ),
    );
  }

  void _finishCreateEvent(String name, String stage) {
    if (name.isEmpty) name = 'Event ${_middlewareEvents.length + 1}';

    // Create event via MiddlewareProvider (single source of truth)
    final newEvent = _createMiddlewareEvent(name, stage);

    setState(() {
      _selectedEventId = newEvent.id;
    });

    // Registruj u centralni Event Registry
    _syncEventToRegistry(_findEventById(newEvent.id));

    // Persist state (including audio pool) after creating event
    _persistState();
  }

  /// Sinhronizuj composite event sa centralnim Event Registry
  /// MiddlewareProvider is already the source of truth, so no need to sync back
  void _syncEventToRegistry(SlotCompositeEvent? event) {
    if (event == null) return;

    final audioEvent = AudioEvent(
      id: event.id,
      name: event.name,
      stage: _getEventStage(event),
      layers: event.layers.map((l) => AudioLayer(
        id: l.id,
        audioPath: l.audioPath,
        name: l.name,
        volume: l.volume,
        pan: l.pan,
        delay: l.offsetMs,
        busId: l.busId ?? 2,
      )).toList(),
    );

    eventRegistry.registerEvent(audioEvent);
  }

  // NOTE: _syncEventToMiddleware removed - MiddlewareProvider is now the single source of truth

  String _categoryFromStage(String stage) {
    final lower = stage.toLowerCase();
    if (lower.contains('spin')) return 'spin';
    if (lower.contains('reel')) return 'reelStop';
    if (lower.contains('anticipation')) return 'anticipation';
    if (lower.contains('win') && lower.contains('big')) return 'bigWin';
    if (lower.contains('win')) return 'win';
    if (lower.contains('feature')) return 'feature';
    if (lower.contains('bonus')) return 'bonus';
    if (lower.contains('jackpot')) return 'bigWin';
    return 'general';
  }

  Color _colorFromStage(String stage) {
    final category = _categoryFromStage(stage);
    return switch (category) {
      'spin' => const Color(0xFF4A9EFF),
      'reelStop' => const Color(0xFF9B59B6),
      'anticipation' => const Color(0xFFE74C3C),
      'win' => const Color(0xFFF1C40F),
      'bigWin' => const Color(0xFFFF9040),
      'feature' => const Color(0xFF40FF90),
      'bonus' => const Color(0xFFFF40FF),
      _ => const Color(0xFF888888),
    };
  }

  /// Sinhronizuj sve evente sa registry-jem i Middleware
  void _syncAllEventsToRegistry() {
    for (final event in _compositeEvents) {
      _syncEventToRegistry(event);
      // NOTE: _syncEventToMiddleware removed - MiddlewareProvider is the source of truth
    }
  }

  /// Handle audio dropped on stage from StageTraceWidget drag & drop
  /// Creates or updates an AudioEvent for the target stage
  void _onAudioDroppedOnStage(AudioFileInfo audio, String stageType) {
    debugPrint('[SlotLab] Audio dropped on stage: ${audio.name} → $stageType');

    // Normalize stage type to uppercase
    final normalizedStage = stageType.toUpperCase().replaceAll(' ', '_');

    // Check if event already exists for this stage
    final existingEvent = eventRegistry.getEventForStage(normalizedStage);

    if (existingEvent != null) {
      // Add as new layer to existing event
      final newLayer = AudioLayer(
        id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
        audioPath: audio.path,
        name: audio.name,
        volume: 1.0,
        pan: 0.0,
        delay: 0.0,
        busId: _getBusIdForStage(normalizedStage),
      );

      // Create updated event with new layer
      final updatedEvent = AudioEvent(
        id: existingEvent.id,
        name: existingEvent.name,
        stage: existingEvent.stage,
        layers: [...existingEvent.layers, newLayer],
        duration: existingEvent.duration,
        loop: existingEvent.loop,
        priority: existingEvent.priority,
      );

      eventRegistry.registerEvent(updatedEvent);
      debugPrint('[SlotLab] Added layer to existing event: ${existingEvent.name}');
    } else {
      // Create new event for this stage
      final eventId = 'event_${normalizedStage.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';
      final newEvent = AudioEvent(
        id: eventId,
        name: _formatEventName(normalizedStage),
        stage: normalizedStage,
        layers: [
          AudioLayer(
            id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
            audioPath: audio.path,
            name: audio.name,
            volume: 1.0,
            pan: 0.0,
            delay: 0.0,
            busId: _getBusIdForStage(normalizedStage),
          ),
        ],
        duration: audio.duration.inMilliseconds / 1000.0,
        loop: normalizedStage == 'REEL_SPIN', // Loop for reel spin
        priority: _getPriorityForStage(normalizedStage),
      );

      eventRegistry.registerEvent(newEvent);
      debugPrint('[SlotLab] Created new event: ${newEvent.name}');
    }

    // Trigger visual feedback
    setState(() {});

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: FluxForgeTheme.accentGreen, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  existingEvent != null
                      ? 'Added "${audio.name}" to ${_formatEventName(normalizedStage)}'
                      : 'Created event for $normalizedStage with "${audio.name}"',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: FluxForgeTheme.bgMid,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  int _getBusIdForStage(String stage) {
    if (stage.contains('MUSIC')) return 1;
    if (stage.contains('VO') || stage.contains('VOICE')) return 3;
    if (stage.contains('AMBIEN')) return 5;
    return 2; // Default SFX bus
  }

  int _getPriorityForStage(String stage) {
    if (stage.contains('JACKPOT') || stage.contains('ULTRA')) return 100;
    if (stage.contains('EPIC')) return 90;
    if (stage.contains('MEGA')) return 80;
    if (stage.contains('BIG')) return 70;
    if (stage.contains('WIN')) return 60;
    return 50;
  }

  String _formatEventName(String stage) {
    return stage
        .split('_')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : '')
        .join(' ');
  }

  /// Delete event from ALL systems (SlotLab, Middleware, EventRegistry)
  /// Call this when deleting an event to ensure full cleanup
  void _deleteEventFromAllSystems(String eventId, String eventName, String stage) {
    debugPrint('[SlotLab] _deleteEventFromAllSystems: $eventName (id: $eventId, stage: $stage)');

    // 1. Remove from EventRegistry
    eventRegistry.unregisterEvent(eventId);
    debugPrint('[SlotLab] Unregistered from EventRegistry: $eventName');

    // 2. Remove from MiddlewareProvider
    if (mounted) {
      try {
        final middleware = Provider.of<MiddlewareProvider>(context, listen: false);
        middleware.deleteCompositeEvent(eventId);
        debugPrint('[SlotLab] Deleted from Middleware: $eventName');
      } catch (e) {
        debugPrint('[SlotLab] Error deleting from Middleware: $e');
      }
    }

  }

  Widget _buildAudioBrowser() {
    final folders = ['All', 'SFX', 'Music', 'Ambience', 'UI'];
    final filteredAudio = _selectedBrowserFolder == 'All'
        ? _audioPool
        : _audioPool.where((a) => a['folder'] == _selectedBrowserFolder).toList();

    final searchFiltered = _browserSearchQuery.isEmpty
        ? filteredAudio
        : filteredAudio.where((a) =>
            (a['name'] as String).toLowerCase().contains(_browserSearchQuery.toLowerCase())
          ).toList();

    return Column(
      children: [
        _buildPanelHeader('AUDIO BROWSER', Icons.folder_open),
        // Import button row
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A22),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _importAudioFiles,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.accentBlue.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: FluxForgeTheme.accentBlue),
                      SizedBox(width: 4),
                      Text('Import Audio', style: TextStyle(color: FluxForgeTheme.accentBlue, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _importAudioFolder,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open, size: 12, color: Colors.white54),
                      SizedBox(width: 4),
                      Text('Folder', style: TextStyle(color: Colors.white54, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${_audioPool.length} files',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
        // Search bar
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            style: const TextStyle(color: Colors.white, fontSize: 11),
            decoration: InputDecoration(
              hintText: 'Search audio...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
              prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: FluxForgeTheme.accentBlue),
              ),
              filled: true,
              fillColor: Colors.black.withOpacity(0.3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            ),
            onChanged: (value) => setState(() => _browserSearchQuery = value),
          ),
        ),
        // Folder tabs
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: folders.map((folder) {
              final isSelected = _selectedBrowserFolder == folder;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => setState(() => _selectedBrowserFolder = folder),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? FluxForgeTheme.accentBlue
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Text(
                      folder,
                      style: TextStyle(
                        color: isSelected ? FluxForgeTheme.accentBlue : Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Audio list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: searchFiltered.length,
            itemBuilder: (context, index) {
              final audio = searchFiltered[index];
              return _buildAudioBrowserItem(audio);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAudioBrowserItem(Map<String, dynamic> audio) {
    return Draggable<String>(
      data: audio['path'] as String,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue.withOpacity(0.9),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: FluxForgeTheme.accentBlue.withOpacity(0.5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Text(
            audio['name'] as String,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
      onDragStarted: () {
        setState(() {
          _draggingAudioPath = audio['path'] as String;
        });
      },
      onDragEnd: (details) {
        setState(() {
          _draggingAudioPath = null;
          _dragPosition = null;
        });
      },
      onDragUpdate: (details) {
        setState(() {
          _dragPosition = details.globalPosition;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _previewingAudioPath == audio['path']
              ? FluxForgeTheme.accentBlue.withOpacity(0.15)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _previewingAudioPath == audio['path']
                ? FluxForgeTheme.accentBlue
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Preview button
            InkWell(
              onTap: () {
                final path = audio['path'] as String;
                if (_previewingAudioPath == path && _isPreviewPlaying) {
                  // Stop preview
                  _stopAudioPreview();
                } else {
                  // Start preview
                  _startAudioPreview(path);
                }
              },
              child: Icon(
                _previewingAudioPath == audio['path'] && _isPreviewPlaying
                    ? Icons.stop
                    : Icons.play_arrow,
                size: 16,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 8),
            // Audio info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    audio['name'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${(audio['duration'] as double).toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  ),
                ],
              ),
            ),
            // Drag handle
            const Icon(Icons.drag_indicator, size: 14, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomPanelHeader() {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          // Collapse button
          InkWell(
            onTap: () => setState(() => _bottomPanelCollapsed = !_bottomPanelCollapsed),
            child: Container(
              width: 28,
              height: 28,
              child: Icon(
                _bottomPanelCollapsed ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: Colors.white54,
              ),
            ),
          ),
          // Tabs
          ..._BottomPanelTab.values.map((tab) {
            final isSelected = _selectedBottomTab == tab;
            final label = switch (tab) {
              _BottomPanelTab.timeline => 'Timeline',
              _BottomPanelTab.busHierarchy => 'Bus Hierarchy',
              _BottomPanelTab.profiler => 'Profiler',
              _BottomPanelTab.rtpc => 'RTPC',
              _BottomPanelTab.resources => 'Resources',
              _BottomPanelTab.auxSends => 'Aux Sends',
              _BottomPanelTab.eventLog => 'Event Log',
              _BottomPanelTab.gameModel => 'Game Model',
              _BottomPanelTab.scenarios => 'Scenarios',
              _BottomPanelTab.gddImport => 'GDD Import',
            };

            return InkWell(
              onTap: () => setState(() {
                _selectedBottomTab = tab;
                _bottomPanelCollapsed = false;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? FluxForgeTheme.accentBlue : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      height: _bottomPanelHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D10),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: _buildBottomPanelContent(),
    );
  }

  Widget _buildBottomPanelContent() {
    switch (_selectedBottomTab) {
      case _BottomPanelTab.timeline:
        return _buildTimelineTabContent();
      case _BottomPanelTab.busHierarchy:
        return _buildBusHierarchyContent();
      case _BottomPanelTab.profiler:
        return _buildProfilerContent();
      case _BottomPanelTab.rtpc:
        return _buildRtpcContent();
      case _BottomPanelTab.resources:
        return _buildResourcesContent();
      case _BottomPanelTab.auxSends:
        return _buildAuxSendsContent();
      case _BottomPanelTab.eventLog:
        return _buildEventLogContent();
      case _BottomPanelTab.gameModel:
        return _buildGameModelContent();
      case _BottomPanelTab.scenarios:
        return _buildScenariosContent();
      case _BottomPanelTab.gddImport:
        return _buildGddImportContent();
    }
  }

  Widget _buildEventLogContent() {
    final middleware = context.read<MiddlewareProvider>();
    return GlassEventLogWrapper(
      child: EventLogPanel(
        slotLabProvider: _slotLabProvider,
        middlewareProvider: middleware,
        height: _bottomPanelHeight - 8,
      ),
    );
  }

  Widget _buildTimelineTabContent() {
    // Stage Trace Widget with full timeline visualization
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Stage trace (animated marker through stages) with Glass wrapper
          // Supports drag & drop audio assignment to stages
          GlassStageTraceWrapper(
            isPlaying: _slotLabProvider.isPlayingStages,
            child: StageTraceWidget(
              provider: _slotLabProvider,
              height: 80,
              showMiniProgress: true,
              onAudioDropped: _onAudioDroppedOnStage,
            ),
          ),
          const SizedBox(height: 4),
          // Audio Pool Stats + Forced Outcome
          Row(
            children: [
              // Audio Pool performance indicator
              ListenableBuilder(
                listenable: AudioPool.instance,
                builder: (context, _) => GlassAudioPoolStats(
                  statsString: AudioPool.instance.statsString,
                  hitRate: AudioPool.instance.hitRate,
                  activeVoices: AudioPool.instance.activeVoiceCount,
                ),
              ),
              const SizedBox(width: 8),
              // Forced Outcome - plain text line
              Expanded(child: QuickOutcomeBar(provider: _slotLabProvider)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusHierarchyContent() {
    return const BusHierarchyPanel();
  }

  Widget _buildProfilerContent() {
    return const ProfilerPanel();
  }

  Widget _buildRtpcContent() {
    return const RtpcEditorPanel();
  }

  Widget _buildResourcesContent() {
    return ResourcesPanel(audioPool: _audioPool);
  }

  Widget _buildAuxSendsContent() {
    return const AuxSendsPanel();
  }

  Widget _buildGameModelContent() {
    return GameModelEditor(
      initialModel: _slotLabProvider.currentGameModel,
      onModelChanged: (model) {
        _slotLabProvider.updateGameModel(model);
      },
      onClose: () => setState(() => _selectedBottomTab = _BottomPanelTab.timeline),
    );
  }

  Widget _buildScenariosContent() {
    return ScenarioEditorPanel(
      onScenarioSelected: (scenario) {
        _slotLabProvider.loadScenario(scenario.id);
      },
      onScenarioChanged: (scenario) {
        _slotLabProvider.registerScenarioFromDemoScenario(scenario);
      },
      onClose: () => setState(() => _selectedBottomTab = _BottomPanelTab.timeline),
    );
  }

  Widget _buildGddImportContent() {
    return GddImportPanel(
      onModelImported: (model) {
        // Model is already imported via FFI in the panel
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GDD imported: ${model['info']?['name'] ?? 'Unknown'}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      },
      onClose: () => setState(() => _selectedBottomTab = _BottomPanelTab.timeline),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMON WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPanelHeader(String title, IconData icon) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: const Color(0xFFFFD700)),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF888888),
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  /// Preview button - enters fullscreen slot preview mode (F11)
  Widget _buildPreviewButton() {
    return Tooltip(
      message: 'Fullscreen Preview (F11)',
      child: GestureDetector(
        onTap: () => setState(() => _isPreviewMode = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                FluxForgeTheme.accentBlue.withOpacity(0.3),
                FluxForgeTheme.accentBlue.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.accentBlue.withOpacity(0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_filled,
                color: FluxForgeTheme.accentBlue,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'PREVIEW',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool isActive = false,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentBlue.withOpacity(0.2)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? FluxForgeTheme.accentBlue
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? FluxForgeTheme.accentBlue : Colors.white70,
          size: 16,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}

// =============================================================================
// CUSTOM PAINTERS
// =============================================================================

class _TimelineGridPainter extends CustomPainter {
  final double zoom;
  final double duration;

  _TimelineGridPainter({required this.zoom, required this.duration});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    // Vertical grid lines (time markers)
    // size.width is already zoomed, so secondWidth = size.width / duration
    final secondWidth = size.width / duration;
    for (double x = 0; x < size.width; x += secondWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal grid lines (track separators)
    const trackHeight = 48.0;
    for (double y = trackHeight; y < size.height; y += trackHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineGridPainter oldDelegate) =>
      oldDelegate.zoom != zoom || oldDelegate.duration != duration;
}

/// Cubase-style waveform painter with min/max/rms layers
/// Shows: RMS body (darker), peak fill (lighter), peak stroke (bright)
class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  // Cached paths for GPU optimization
  Path? _cachedPeakPath;
  Path? _cachedRmsPath;
  Size? _cachedSize;

  // Pre-allocated paints
  late final Paint _rmsFillPaint;
  late final Paint _peakFillPaint;
  late final Paint _peakStrokePaint;
  late final Paint _centerLinePaint;

  _WaveformPainter({required this.data, required this.color}) {
    _rmsFillPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    _peakFillPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    _peakStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    _centerLinePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;

    // Rebuild paths only when size changes
    if (_cachedPeakPath == null || _cachedSize != size) {
      _rebuildPaths(size);
      _cachedSize = size;
    }

    final centerY = size.height / 2;

    // 1. Draw RMS body (darker, inner) — the "mass" of sound
    if (_cachedRmsPath != null) {
      canvas.drawPath(_cachedRmsPath!, _rmsFillPaint);
    }

    // 2. Draw peak fill — lighter, shows transient extent
    if (_cachedPeakPath != null) {
      canvas.drawPath(_cachedPeakPath!, _peakFillPaint);
    }

    // 3. Draw peak stroke — bright outline for crisp transients
    if (_cachedPeakPath != null) {
      canvas.drawPath(_cachedPeakPath!, _peakStrokePaint);
    }

    // 4. Center line (zero crossing)
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), _centerLinePaint);
  }

  void _rebuildPaths(Size size) {
    final centerY = size.height / 2;
    final amplitude = centerY * 0.85;

    // Data comes as min/max pairs from getWaveformPeaks
    final bool isMinMaxPairs = data.length >= 2 && data.length.isEven;
    final int numPeaks = isMinMaxPairs ? data.length ~/ 2 : data.length;

    if (numPeaks <= 0) return;

    double sampleToX(int i) => numPeaks > 1 ? (i / (numPeaks - 1)) * size.width : size.width / 2;

    // Build peak envelope path
    _cachedPeakPath = Path();

    if (isMinMaxPairs) {
      // Min at even indices, max at odd indices
      _cachedPeakPath!.moveTo(0, centerY - data[1].abs().clamp(0.0, 1.0) * amplitude);

      for (int i = 1; i < numPeaks; i++) {
        final maxVal = data[i * 2 + 1].abs().clamp(0.0, 1.0);
        _cachedPeakPath!.lineTo(sampleToX(i), centerY - maxVal * amplitude);
      }

      for (int i = numPeaks - 1; i >= 0; i--) {
        final minVal = data[i * 2].abs().clamp(0.0, 1.0);
        _cachedPeakPath!.lineTo(sampleToX(i), centerY + minVal * amplitude);
      }
    } else {
      // Single amplitude values (fallback)
      _cachedPeakPath!.moveTo(0, centerY - data[0].abs().clamp(0.0, 1.0) * amplitude);

      for (int i = 1; i < numPeaks; i++) {
        final val = data[i].abs().clamp(0.0, 1.0);
        _cachedPeakPath!.lineTo(sampleToX(i), centerY - val * amplitude);
      }

      for (int i = numPeaks - 1; i >= 0; i--) {
        final val = data[i].abs().clamp(0.0, 1.0);
        _cachedPeakPath!.lineTo(sampleToX(i), centerY + val * amplitude);
      }
    }
    _cachedPeakPath!.close();

    // Build RMS path (smaller body — simulate RMS as 45% of peak)
    const rmsScale = 0.45;
    _cachedRmsPath = Path();

    if (isMinMaxPairs) {
      final firstRms = ((data[0].abs() + data[1].abs()) * 0.5).clamp(0.0, 1.0);
      _cachedRmsPath!.moveTo(0, centerY - firstRms * amplitude * rmsScale);

      for (int i = 1; i < numPeaks; i++) {
        final rms = ((data[i * 2].abs() + data[i * 2 + 1].abs()) * 0.5).clamp(0.0, 1.0);
        _cachedRmsPath!.lineTo(sampleToX(i), centerY - rms * amplitude * rmsScale);
      }

      for (int i = numPeaks - 1; i >= 0; i--) {
        final rms = ((data[i * 2].abs() + data[i * 2 + 1].abs()) * 0.5).clamp(0.0, 1.0);
        _cachedRmsPath!.lineTo(sampleToX(i), centerY + rms * amplitude * rmsScale);
      }
    } else {
      _cachedRmsPath!.moveTo(0, centerY - data[0].abs().clamp(0.0, 1.0) * amplitude * rmsScale);

      for (int i = 1; i < numPeaks; i++) {
        _cachedRmsPath!.lineTo(sampleToX(i), centerY - data[i].abs().clamp(0.0, 1.0) * amplitude * rmsScale);
      }

      for (int i = numPeaks - 1; i >= 0; i--) {
        _cachedRmsPath!.lineTo(sampleToX(i), centerY + data[i].abs().clamp(0.0, 1.0) * amplitude * rmsScale);
      }
    }
    _cachedRmsPath!.close();
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}

/// DAW-style playhead painter with triangle head and vertical line
class _SlotLabPlayheadPainter extends CustomPainter {
  final bool isDragging;

  _SlotLabPlayheadPainter({this.isDragging = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Shadow for depth
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    // Main playhead color
    final paint = Paint()
      ..color = isDragging
          ? FluxForgeTheme.accentRed
          : FluxForgeTheme.accentRed.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    // Line paint
    final linePaint = Paint()
      ..color = isDragging
          ? FluxForgeTheme.accentRed
          : FluxForgeTheme.accentRed.withValues(alpha: 0.8)
      ..strokeWidth = isDragging ? 2.0 : 1.5;

    // Draw vertical line first
    final centerX = size.width / 2;
    canvas.drawLine(
      Offset(centerX, 10), // Start below triangle
      Offset(centerX, size.height),
      linePaint,
    );

    // Triangle head shadow
    final triangleWidth = 12.0;
    final triangleHeight = 10.0;
    final shadowPath = Path()
      ..moveTo(centerX - triangleWidth / 2 + 1, 1)
      ..lineTo(centerX + triangleWidth / 2 + 1, 1)
      ..lineTo(centerX + 1, triangleHeight + 1)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // Triangle head
    final path = Path()
      ..moveTo(centerX - triangleWidth / 2, 0)
      ..lineTo(centerX + triangleWidth / 2, 0)
      ..lineTo(centerX, triangleHeight)
      ..close();
    canvas.drawPath(path, paint);

    // Highlight for 3D effect when dragging
    if (isDragging) {
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final highlightPath = Path()
        ..moveTo(centerX - triangleWidth / 2 + 2, 2)
        ..lineTo(centerX + triangleWidth / 2 - 2, 2)
        ..lineTo(centerX, triangleHeight - 2);
      canvas.drawPath(highlightPath, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(_SlotLabPlayheadPainter oldDelegate) =>
      isDragging != oldDelegate.isDragging;
}
