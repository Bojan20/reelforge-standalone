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
import '../widgets/common/in_app_file_browser.dart';
import '../services/audio_playback_service.dart';
import '../providers/middleware_provider.dart';
import '../providers/stage_provider.dart';
import '../providers/slot_lab/slot_lab_coordinator.dart';
import '../providers/ale_provider.dart';
import '../services/stage_audio_mapper.dart';
import '../models/stage_models.dart';
import '../models/middleware_models.dart';
import '../models/slot_audio_events.dart';
import '../theme/fluxforge_theme.dart';
import '../widgets/common/inline_toast.dart';
import '../widgets/slot_lab/rtpc_editor_panel.dart';
import '../widgets/slot_lab/bus_hierarchy_panel.dart';
import '../widgets/slot_lab/profiler_panel.dart';
import '../widgets/slot_lab/volatility_dial.dart';
import '../widgets/slot_lab/scenario_controls.dart';
import '../widgets/slot_lab/batch_distribution_dialog.dart';
import '../widgets/slot_lab/resources_panel.dart';
import '../widgets/slot_lab/aux_sends_panel.dart';
import '../widgets/slot_lab/slot_preview_widget.dart';
import '../widgets/slot_lab/premium_slot_preview.dart';
import '../widgets/slot_lab/event_log_panel.dart';
import '../widgets/slot_lab/audio_hover_preview.dart';
import '../widgets/slot_lab/slot_lab_settings_panel.dart' as settings;
import '../src/rust/native_ffi.dart';
import '../services/event_registry.dart';
import '../services/slotlab_track_bridge.dart';
import '../services/waveform_cache_service.dart';
import '../controllers/slot_lab/timeline_drag_controller.dart';
import '../controllers/slot_lab/timeline_controller.dart' as ultimate;
import '../models/timeline/stage_marker.dart' as timeline_models;
import '../models/timeline/audio_region.dart' as timeline_models show AudioRegion;
import '../widgets/slot_lab/timeline_toolbar.dart';
import '../widgets/slot_lab/timeline_grid_overlay.dart';
import '../widgets/slot_lab/draggable_layer_widget.dart';
import '../widgets/slot_lab/timeline/ultimate_timeline_widget.dart';
import '../providers/undo_manager.dart';
import '../widgets/slot_lab/game_model_editor.dart';
import '../widgets/slot_lab/scenario_editor.dart';
import '../widgets/slot_lab/gdd_import_panel.dart';
import '../services/gdd_import_service.dart'; // GddSymbol, SymbolTier
import '../widgets/lower_zone/slotlab_lower_zone_controller.dart';
import '../widgets/lower_zone/slotlab_lower_zone_widget.dart';
import '../widgets/lower_zone/lower_zone_types.dart' show SlotLabSuperTab;
import '../widgets/slot_lab/lower_zone/command_builder_panel.dart';
import '../widgets/slot_lab/lower_zone/event_list_panel.dart';
import '../widgets/slot_lab/lower_zone/bus_meters_panel.dart';
import '../widgets/spatial/auto_spatial_panel.dart';
import '../providers/stage_ingest_provider.dart';
import '../widgets/stage_ingest/stage_ingest_panel.dart';
import '../widgets/slot_lab/gdd_import_wizard.dart';
import '../widgets/slot_lab/gdd_preview_dialog.dart';
import '../widgets/ale/ale_panel.dart';
// import '../widgets/slot_lab/symbol_strip_widget.dart'; // LEGACY - replaced by UltimateAudioPanel
import '../widgets/slot_lab/ultimate_audio_panel.dart';
import '../widgets/slot_lab/events_panel_widget.dart';
// P0 PERFORMANCE: WaveformThumbnail removed from audio browser — too slow for large lists
import '../services/stage_configuration_service.dart';
import '../providers/slot_lab_project_provider.dart';
import '../models/slot_lab_models.dart';
import '../widgets/template/template_gallery_panel.dart';
import '../widgets/slot_lab/project_dashboard_dialog.dart';
import '../widgets/slot_lab/feature_builder_panel.dart';
import '../providers/feature_builder_provider.dart'; // P13.8.6
import '../models/template_models.dart' show BuiltTemplate;

// =============================================================================
// SLOT LAB TRACK ID ISOLATION
// =============================================================================
// CRITICAL: SlotLab uses track IDs starting at 100000 to avoid collision with
// DAW tracks (0, 1, 2...). This prevents SlotLab audio imports from corrupting
// DAW waveform data in the Rust engine.

/// Base offset for SlotLab track IDs (DAW uses 0-999, SlotLab uses 100000+)
const int kSlotLabTrackIdOffset = 100000;

/// Convert local SlotLab track index to FFI track ID
int slotLabTrackIdToFfi(int localTrackIndex) => kSlotLabTrackIdOffset + localTrackIndex;

/// Convert FFI track ID back to local SlotLab track index
int ffiToSlotLabTrackId(int ffiTrackId) => ffiTrackId - kSlotLabTrackIdOffset;

/// Check if an FFI track ID belongs to SlotLab
bool isSlotLabTrackId(int ffiTrackId) => ffiTrackId >= kSlotLabTrackIdOffset;

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

  /// Event ID from MiddlewareProvider (for ID-based lookup)
  /// This is the CRITICAL field that enables reliable sync
  String? eventId;

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
    this.eventId,
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

/// V6 Layout: 7 core tabs + [+] menu
/// Merged from 15 tabs based on role analysis (see SLOTLAB_LOWER_ZONE_ANALYSIS.md)
enum _BottomPanelTab {
  timeline,   // Audio regions, layers, waveforms
  events,     // Event list + RTPC (merged eventList + rtpc)
  mixer,      // Bus hierarchy + Aux sends (merged)
  musicAle,   // ALE rules, signals, transitions
  meters,     // LUFS, peak, correlation
  debug,      // Event log (renamed)
  engine,     // Profiler + resources + stageIngest (merged)
}

/// Plus menu items (opened via popup, not in tab bar)
enum _PlusMenuItem {
  gameConfig,     // gameModel + gddImport
  autoSpatial,    // AutoSpatial panel
  scenarios,      // Scenarios panel
  commandBuilder, // Command Builder
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

class _SlotLabScreenState extends State<SlotLabScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, InlineToastMixin {

  @override
  bool get wantKeepAlive => true;
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  // Timeline drag controller (centralized drag state management)
  TimelineDragController? _dragController;
  TimelineDragController get dragController => _dragController!;

  // Cached middleware reference — avoids Provider.of(context) in dispose()
  // which crashes with "deactivated widget's ancestor" during unmount
  MiddlewareProvider? _middlewareRef;

  // P14: Ultimate Timeline controller (new professional timeline)
  ultimate.TimelineController? _ultimateTimelineController;

  // FFI instance
  final _ffi = NativeFFI.instance;

  // Bridge to DAW TRACK_MANAGER for unified playback
  final _trackBridge = SlotLabTrackBridge.instance;

  // Focus node for keyboard shortcuts
  final FocusNode _focusNode = FocusNode();

  // Slot Lab settings
  settings.SlotLabSettings _slotLabSettings = const settings.SlotLabSettings();

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

  // SPACE key debounce (prevents double-trigger from multiple Focus widgets)
  int _lastSpaceKeyTime = 0;
  static const int _spaceKeyDebounceMs = 200;

  // Track state
  final List<_SlotAudioTrack> _tracks = [];
  int? _selectedTrackIndex;

  // Stage markers (empty by default - user adds them)
  final List<_StageMarker> _stageMarkers = [];

  // Composite events — MiddlewareProvider is the SINGLE SOURCE OF TRUTH
  // SlotLab only keeps UI state (expanded, selected)
  final Map<String, bool> _eventExpandedState = {};
  String? _selectedEventId;

  // DEBUG: Track last drag status for visual feedback
  String _lastDragStatus = '';
  DateTime? _lastDragStatusTime;

  // ═══════════════════════════════════════════════════════════════════════════
  // P2-12: RESPONSIVE PANEL VISIBILITY
  // ═══════════════════════════════════════════════════════════════════════════
  // Breakpoints: <900px = hide right, <1200px = hide left, <700px = hide both
  static const double _breakpointHideRight = 900.0;
  static const double _breakpointHideLeft = 1200.0;
  static const double _breakpointHideBoth = 700.0;
  static const double _minCenterWidth = 400.0;  // Minimum center panel width

  // Manual override (user can toggle panels regardless of breakpoint)
  bool _leftPanelManuallyHidden = false;
  bool _rightPanelManuallyHidden = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // ULTIMATE AUDIO PANEL STATE — now persisted in SlotLabProjectProvider
  // ═══════════════════════════════════════════════════════════════════════════
  // NOTE: _audioAssignments moved to SlotLabProjectProvider for persistence

  // ═══════════════════════════════════════════════════════════════════════════
  // QUICK ASSIGN MODE (P3-19)
  // ═══════════════════════════════════════════════════════════════════════════
  bool _quickAssignMode = true;
  String? _quickAssignSelectedSlot;

  /// P3-19: Handle Quick Assign — reuses existing audio assignment logic
  void _handleQuickAssign(String audioPath, String stage, SlotLabProjectProvider projectProvider) {

    // Update provider (persisted state)
    projectProvider.setAudioAssignment(stage, audioPath);

    // INSTANT: Re-sync ALL audio assignments to EventRegistry
    // This ensures GAME_START and all other assignments are registered
    _syncAudioAssignmentsToRegistry();

    // CRITICAL: Also create/update composite event for timeline visibility
    _ensureCompositeEventForStage(stage, audioPath);
  }

  /// CENTRAL BRIDGE: Ensure a composite event exists in MiddlewareProvider for a stage+audio assignment.
  /// Called from: Quick Assign, onAudioAssign, mount sync — ALL paths converge here.
  /// Creates new event or updates existing one. Auto-detects duration via FFI.
  void _ensureCompositeEventForStage(String stage, String audioPath) {
    final middleware = context.read<MiddlewareProvider>();
    final eventId = 'audio_$stage';

    // Check if already exists — update layer path if needed
    final existing = middleware.compositeEvents.where((e) => e.id == eventId).firstOrNull;

    final stageConfig = StageConfigurationService.instance;
    final busId = _getBusForStage(stage);
    final shouldLoop = stageConfig.isLooping(stage);
    final isMusicBus = busId == 1;
    final shouldOverlap = !isMusicBus && !shouldLoop;
    final crossfadeMs = isMusicBus ? 500 : 0;

    // Auto-detect duration via FFI
    double? durationSec;
    try {
      final dur = NativeFFI.instance.getAudioFileDuration(audioPath);
      if (dur > 0) durationSec = dur;
    } catch (_) {}

    if (existing != null) {
      // Update existing event — replace first layer or add new one
      final updatedLayers = existing.layers.isEmpty
          ? [
              SlotEventLayer(
                id: 'layer_$stage',
                name: audioPath.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), ''),
                audioPath: audioPath,
                volume: 1.0,
                pan: _getPanForStage(stage),
                busId: busId,
                durationSeconds: durationSec,
              ),
            ]
          : existing.layers.map((l) {
              if (l.id == 'layer_$stage') {
                return l.copyWith(
                  audioPath: audioPath,
                  name: audioPath.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), ''),
                  durationSeconds: durationSec ?? l.durationSeconds,
                );
              }
              return l;
            }).toList();
      middleware.updateCompositeEvent(existing.copyWith(
        layers: updatedLayers,
        modifiedAt: DateTime.now(),
      ));
    } else {
      // Create new composite event
      final category = _getCategoryForStage(stage);
      final color = _getColorForCategory(category);
      final now = DateTime.now();

      middleware.addCompositeEvent(SlotCompositeEvent(
        id: eventId,
        name: stage.replaceAll('_', ' ').split(' ').map((w) =>
          w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w
        ).join(' '),
        category: category,
        color: color,
        layers: [
          SlotEventLayer(
            id: 'layer_$stage',
            name: audioPath.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), ''),
            audioPath: audioPath,
            volume: 1.0,
            pan: _getPanForStage(stage),
            busId: busId,
            durationSeconds: durationSec,
          ),
        ],
        triggerStages: [stage],
        targetBusId: busId,
        looping: shouldLoop,
        overlap: shouldOverlap,
        crossfadeMs: crossfadeMs,
        createdAt: now,
        modifiedAt: now,
      ), select: false);
    }
  }

  /// Get stereo pan position for a stage (per-reel panning for REEL_STOP_*)
  double _getPanForStage(String stage) {
    // Per-reel stereo spread: L(-0.8) → C(0.0) → R(+0.8)
    if (stage == 'REEL_STOP_0') return -0.8;
    if (stage == 'REEL_STOP_1') return -0.4;
    if (stage == 'REEL_STOP_2') return 0.0;
    if (stage == 'REEL_STOP_3') return 0.4;
    if (stage == 'REEL_STOP_4') return 0.8;
    // Default: center
    return 0.0;
  }

  /// Get bus ID for a stage based on category
  int _getBusForStage(String stage) {
    // Bus IDs: master=0, music=1, sfx=2, voice=3, ambience=4, aux=5
    final s = stage.toUpperCase();

    // MUSIC BUS (1) — background music and ambience
    if (s.startsWith('MUSIC_') ||
        s.startsWith('ATTRACT_') ||
        s.startsWith('AMBIENT_') ||
        s.startsWith('IDLE_') ||
        s == 'GAME_START' ||
        s == 'BASE_GAME_START') return 1; // Music bus

    // SFX BUS (2) — all other sounds
    if (s.startsWith('UI_') || s.startsWith('MENU_')) return 2;
    if (s.startsWith('WIN_') || s.startsWith('JACKPOT_')) return 2;
    if (s.startsWith('REEL_') || s.startsWith('SPIN_')) return 2;
    if (s.startsWith('ROLLUP_') || s.startsWith('COIN_')) return 2;
    if (s.startsWith('FREESPIN_') || s.startsWith('BONUS_')) return 2;
    if (s.startsWith('CASCADE_') || s.startsWith('HOLD_')) return 2;
    if (s.startsWith('SYMBOL_')) return 2;
    if (s.startsWith('GAMBLE_')) return 2;
    if (s.startsWith('ANTICIPATION_')) return 2;

    // Default: SFX bus
    return 2;
  }

  /// Get category for a stage based on stage name pattern
  String _getCategoryForStage(String stage) {
    final s = stage.toUpperCase();
    if (s.startsWith('SPIN_') || s.startsWith('REEL_')) return 'spin';
    if (s.startsWith('WIN_') || s.startsWith('ROLLUP_')) return 'win';
    if (s.startsWith('FREESPIN_') || s.startsWith('FS_')) return 'feature';
    if (s.startsWith('BONUS_')) return 'bonus';
    if (s.startsWith('CASCADE_') || s.startsWith('TUMBLE_')) return 'cascade';
    if (s.startsWith('JACKPOT_')) return 'jackpot';
    if (s.startsWith('HOLD_') || s.startsWith('RESPIN_')) return 'hold';
    if (s.startsWith('GAMBLE_')) return 'gamble';
    if (s.startsWith('UI_') || s.startsWith('MENU_') || s.startsWith('BUTTON_')) return 'ui';
    if (s.startsWith('MUSIC_') || s.startsWith('AMBIENT_')) return 'music';
    if (s.startsWith('SYMBOL_') || s.startsWith('WILD_') || s.startsWith('SCATTER_')) return 'symbol';
    if (s.startsWith('ANTICIPATION_') || s.startsWith('NEAR_MISS')) return 'anticipation';
    return 'general';
  }

  /// Get color for a category
  Color _getColorForCategory(String category) {
    switch (category) {
      case 'spin':
        return const Color(0xFF4CAF50); // Green
      case 'win':
        return const Color(0xFFFFD700); // Gold
      case 'feature':
        return const Color(0xFF9C27B0); // Purple
      case 'bonus':
        return const Color(0xFFE91E63); // Pink
      case 'cascade':
        return const Color(0xFF00BCD4); // Cyan
      case 'jackpot':
        return const Color(0xFFFF5722); // Deep Orange
      case 'hold':
        return const Color(0xFF3F51B5); // Indigo
      case 'gamble':
        return const Color(0xFFFF9800); // Orange
      case 'ui':
        return const Color(0xFF607D8B); // Blue Grey
      case 'music':
        return const Color(0xFF673AB7); // Deep Purple
      case 'symbol':
        return const Color(0xFF2196F3); // Blue
      case 'anticipation':
        return const Color(0xFFF44336); // Red
      default:
        return const Color(0xFF9E9E9E); // Grey
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DAW-STYLE LOCAL DRAG STATE — ALL ValueNotifiers to avoid ANY setState during drag
  // CRITICAL: setState during drag kills the gesture recognizer!
  // ALL drag state is stored in ValueNotifiers so GestureDetector is NEVER rebuilt.
  // ═══════════════════════════════════════════════════════════════════════════
  final ValueNotifier<String?> _draggingLayerIdNotifier = ValueNotifier<String?>(null);
  String? _draggingEventId;           // Parent event ID (not visual, no notifier needed)
  String? _draggingRegionId;          // Parent region ID (not visual, no notifier needed)
  double _dragStartOffsetMs = 0;      // Absolute offset at drag start (ms)
  double _dragStartMouseX = 0;        // Mouse X at drag start (globalPosition.dx)
  double _dragPixelsPerMs = 1.0;      // Cached conversion factor (pixels per millisecond)
  final ValueNotifier<double> _dragCurrentOffsetNotifier = ValueNotifier<double>(0);
  double _dragRegionDuration = 0;     // Region duration at drag start (for stable visual)
  double _dragLayerDuration = 0;      // Layer duration at drag start (for stable width)

  // Convenience getter for backward compatibility
  String? get _draggingLayerId => _draggingLayerIdNotifier.value;

  // Flag: EventRegistry sync was skipped during playback, needs sync when idle
  bool _pendingRegistrySync = false;

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

  /// Get middleware provider — uses cached reference if available (safe in dispose)
  MiddlewareProvider get _middleware =>
      _middlewareRef ?? Provider.of<MiddlewareProvider>(context, listen: false);

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
  /// CRITICAL: Stage must be non-empty and UPPERCASE for EventRegistry to work
  String _getEventStage(SlotCompositeEvent event) {
    // First try explicit triggerStages (normalize to UPPERCASE)
    if (event.triggerStages.isNotEmpty) {
      return event.triggerStages.first.toUpperCase();
    }

    // Fallback: derive stage from category (already UPPERCASE)
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
  /// Note: _onMiddlewareChanged listener handles _syncEventToRegistry after provider updates
  void _addLayerToMiddlewareEvent(String eventId, String audioPath, String name) {
    _middleware.addLayerToEvent(eventId, audioPath: audioPath, name: name);
    // Don't call _syncEventToRegistry here - _onMiddlewareChanged will sync with fresh data
  }

  /// Remove layer from event via MiddlewareProvider
  /// Note: _onMiddlewareChanged listener handles _syncEventToRegistry after provider updates
  void _removeLayerFromMiddlewareEvent(String eventId, String layerId) {
    _middleware.removeLayerFromEvent(eventId, layerId);
    // Don't call _syncEventToRegistry here - _onMiddlewareChanged will sync with fresh data
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
  /// CRITICAL: Unregisters ALL stage-variants of this event from EventRegistry
  void _deleteMiddlewareEvent(String eventId) {
    // Find the event to get its triggerStages count
    final event = _findEventById(eventId);
    final stageCount = event?.triggerStages.length ?? 1;

    // Unregister base event and all stage variants
    eventRegistry.unregisterEvent(eventId);
    for (int i = 1; i < stageCount; i++) {
      eventRegistry.unregisterEvent('${eventId}_stage_$i');
    }

    _middleware.deleteCompositeEvent(eventId);
  }

  // Bottom panel (legacy)
  _BottomPanelTab _selectedBottomTab = _BottomPanelTab.timeline;
  double _bottomPanelHeight = 280.0;
  bool _bottomPanelCollapsed = false;

  // Lower Zone Controller (new unified bottom panel system with super-tabs)
  late final SlotLabLowerZoneController _lowerZoneController;

  // Fullscreen preview mode
  bool _isPreviewMode = false;

  // Audio browser
  bool _showAudioBrowser = true;
  String _browserSearchQuery = '';
  String _selectedBrowserFolder = 'All';


  // Audio preview state
  String? _previewingAudioPath;
  bool _isPreviewPlaying = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKGROUND AUDIO PRELOAD STATE (for instant UI loading)
  // ═══════════════════════════════════════════════════════════════════════════
  bool _isPreloadingAudio = false;
  int _preloadedCount = 0;
  int _preloadTotalCount = 0;

  // Track expansion state
  bool _allTracksExpanded = false;  // Default: collapsed

  // Drag state for audio browser (supports multi-file drag)
  List<String>? _draggingAudioPaths;
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
  // CRITICAL: Must match StandardSymbolSet in crates/rf-slot-lab/src/symbols.rs
  // Uses HP1-HP4 (high paying), LP1-LP6 (low paying), WILD, SCATTER, BONUS
  final List<List<String>> _fallbackReelSymbols = [
    ['HP1', 'LP1', 'HP2', 'LP2', 'WILD'],
    ['LP1', 'HP1', 'BONUS', 'HP3', 'LP3'],
    ['LP2', 'WILD', 'HP1', 'LP1', 'HP2'],
    ['HP3', 'LP3', 'LP1', 'SCATTER', 'HP1'],
    ['WILD', 'HP2', 'LP2', 'HP1', 'LP1'],
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

  // Flag to prevent persist until restore is complete
  bool _lowerZoneRestoreComplete = false;
  bool _didInitializeEngine = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize SlotLab engine ONCE when dependencies are available
    // This runs synchronously on first build — no delay!
    if (!_didInitializeEngine) {
      _didInitializeEngine = true;
      _initializeSlotEngine();
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize Lower Zone Controller for unified bottom panel with super-tabs
    // NOTE: Listener is added AFTER restore completes to prevent overwriting persisted state
    _lowerZoneController = SlotLabLowerZoneController();

    // P14: Initialize Ultimate Timeline controller
    _ultimateTimelineController = ultimate.TimelineController();

    _initializeTracks();
    _loadAudioPool();
    _restorePersistedState();
    _initWaveformCache();

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Global keyboard handler that doesn't depend on focus
    // This ensures Space key works even when focus is on Lower Zone panels
    // ═══════════════════════════════════════════════════════════════════════════
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);

    // Listen to MiddlewareProvider for bidirectional sync
    // When layers are added in Middleware center panel, Slot Lab updates automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Cache middleware reference for safe dispose()
        _middlewareRef = _middleware;

        // Initialize drag controller with middleware reference
        _dragController = TimelineDragController(middleware: _middlewareRef!);
        _dragController!.addListener(_onDragControllerChanged);

        _middlewareRef!.addListener(_onMiddlewareChanged);
        _focusNode.requestFocus();
      }
    });
  }

  /// OPTIMIZED: Fast sync of audio assignments to EventRegistry only
  /// MiddlewareProvider sync happens separately in _syncAllEventsToRegistry()
  void _syncPersistedAudioAssignments() {
    final projectProvider = context.read<SlotLabProjectProvider>();
    final assignments = projectProvider.audioAssignments;

    if (assignments.isEmpty) return;

    for (final entry in assignments.entries) {
      final stage = entry.key;
      final audioPath = entry.value;
      final eventId = 'audio_$stage';

      // CRITICAL: Check if stage should loop + get proper bus
      final shouldLoop = StageConfigurationService.instance.isLooping(stage);
      final busId = _getBusForStage(stage);

      // Register in EventRegistry for runtime playback
      eventRegistry.registerEvent(AudioEvent(
        id: eventId,
        name: stage.replaceAll('_', ' '),
        stage: stage,
        layers: [
          AudioLayer(
            id: 'layer_$stage',
            name: '${stage.replaceAll('_', ' ')} Audio',
            audioPath: audioPath,
            volume: 1.0,
            pan: _getPanForStage(stage),
            delay: 0.0,
            busId: busId,
          ),
        ],
        loop: shouldLoop,
        targetBusId: busId,
      ));

      // CENTRAL BRIDGE: Ensure composite event exists for timeline visibility
      _ensureCompositeEventForStage(stage, audioPath);
    }
  }

  /// Global keyboard handler — handles Space + Timeline shortcuts
  /// This fixes the bug where Space stops working after clicking on other elements
  bool _globalKeyHandler(KeyEvent event) {
    if (!mounted) return false;
    // Only handle KeyDown, not KeyUp or KeyRepeat
    if (event is! KeyDownEvent) return false;

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: If ANY text field has focus, let it handle ALL key events.
    // This prevents global shortcuts (G, L, 0, Space, etc.) from firing
    // while the user is typing in search bars or text fields.
    // ═══════════════════════════════════════════════════════════════════════════
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context != null) {
      final editable = focus.context!.findAncestorWidgetOfExactType<EditableText>();
      if (editable != null) return false;
    }

    // P14: Ultimate Timeline keyboard shortcuts
    if (_ultimateTimelineController != null) {
      if (_handleUltimateTimelineShortcut(event)) {
        return true; // Handled
      }
    }

    // Only handle Space key below
    if (event.logicalKey != LogicalKeyboardKey.space) return false;

    // Don't handle if we're not mounted or visible
    if (!mounted) return false;

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: Skip global handler ONLY when in FULLSCREEN preview mode!
    // PremiumSlotPreview has its own Focus-based keyboard handler that properly
    // manages spin/stop toggle when in fullscreen (F11) mode. In that mode,
    // PremiumSlotPreview has guaranteed focus.
    //
    // BUT: When in embedded mode, PremiumSlotPreview does NOT have focus
    // (slot_lab_screen's GestureDetector takes focus), so we MUST handle Space here.
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isPreviewMode) {
      return false; // Let PremiumSlotPreview handle it (it has focus in fullscreen)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEBOUNCE CHECK — Prevents double-trigger from multiple Focus widgets
    // Bug: slot_lab_screen Focus AND premium_slot_preview Focus both receive
    // the same SPACE event, causing spin→immediate stop in same frame
    // ═══════════════════════════════════════════════════════════════════════════
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSpaceKeyTime < _spaceKeyDebounceMs) {
      return true; // Handled (debounced)
    }
    _lastSpaceKeyTime = now;


    // ═══════════════════════════════════════════════════════════════════════════
    // SPACE KEY LOGIC (matches premium_slot_preview.dart):
    //
    // - isReelsSpinning = true ONLY while reels are visually spinning
    // - isWinPresentationActive = true ONLY during win presentation
    //
    // Correct behavior (IGT, NetEnt, Pragmatic Play standard):
    // - During reel spin → STOP (stop reels immediately)
    // - During win presentation → SKIP (skip to end, do NOT start new spin!)
    // - Idle → SPIN (start new spin)
    // ═══════════════════════════════════════════════════════════════════════════

    if (!_hasSlotLabProvider) return false;

    // STOP only when reels are actually spinning
    if (_slotLabProvider.isReelsSpinning) {
      _slotLabProvider.stopStagePlayback();
      return true; // Handled
    }

    // SKIP win presentation — do NOT start a new spin!
    if (_slotLabProvider.isWinPresentationActive) {
      // Request skip with empty callback — skip only, no spin after
      _slotLabProvider.requestSkipPresentation(() {
        // No-op: just skip, don't auto-spin
      });
      return true; // Handled — SPIN button appears, user must press again
    }

    // Idle → SPIN
    if (_slotLabProvider.initialized) {
      _slotLabProvider.spin();
      return true; // Handled
    }

    // Fallback: Toggle timeline playback (non-slot contexts)
    _togglePlayback();
    return true; // Handled
  }

  /// Callback when drag controller state changes
  void _onDragControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// P14: Handle Ultimate Timeline keyboard shortcuts
  bool _handleUltimateTimelineShortcut(KeyEvent event) {
    final controller = _ultimateTimelineController;
    if (controller == null) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Zoom shortcuts
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.equal) {
      controller.zoomIn();
      return true;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.minus) {
      controller.zoomOut();
      return true;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit0) {
      controller.zoomToFit();
      return true;
    }

    // Grid shortcuts
    if (event.logicalKey == LogicalKeyboardKey.keyG && !isCtrl && !isShift) {
      controller.toggleSnap();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyG && isShift) {
      controller.cycleGridMode();
      return true;
    }

    // Playback shortcuts (only if not conflicting with slot spin)
    if (event.logicalKey == LogicalKeyboardKey.keyL) {
      controller.toggleLoop();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit0 && !isCtrl) {
      controller.stop();
      return true;
    }

    // Marker shortcuts
    if (event.logicalKey == LogicalKeyboardKey.semicolon && !isShift) {
      // Add marker at playhead
      controller.addMarkerAtPlayhead('CUSTOM_MARKER', 'Marker');
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.quote && !isShift) {
      controller.jumpToNextMarker();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.quote && isShift) {
      controller.jumpToPreviousMarker();
      return true;
    }

    return false; // Not handled
  }

  /// Callback when MiddlewareProvider changes (bidirectional sync)
  void _onMiddlewareChanged() {
    if (!mounted) return;

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Skip EventRegistry sync during playback or drag!
    // Re-registering events during playback can stop audio mid-play.
    // Defer sync until playback ends or drag completes.
    // ═══════════════════════════════════════════════════════════════════════════
    final isPlayingAudio = _hasSlotLabProvider && _slotLabProvider.isPlayingStages;
    final skipRegistrySync = _draggingLayerId != null || isPlayingAudio;

    if (_draggingLayerId != null) {
      for (final event in _compositeEvents) {
        _rebuildRegionForEvent(event);
      }
      _syncLayersToTrackManager();
      _pendingRegistrySync = true;
      return;
    }

    // If pending sync and now idle, do full sync
    if (_pendingRegistrySync && !skipRegistrySync) {
      _pendingRegistrySync = false;
      _syncAllEventsToRegistry();
    }

    // Rebuild region layers to match updated events from MiddlewareProvider
    for (final event in _compositeEvents) {
      _rebuildRegionForEvent(event);
      // Only sync to EventRegistry if not playing (prevents audio cutoff)
      if (!skipRegistrySync) {
        _syncEventToRegistry(event);
      } else {
        _pendingRegistrySync = true;
      }
    }

    // CRITICAL FIX: Sync to TRACK_MANAGER for playback (removes orphaned clips)
    // Without this, deleted layers continue playing on timeline playback
    _syncLayersToTrackManager();

    setState(() {});
  }

  /// Callback when SlotLabLowerZoneController changes (persist tab state)
  void _onLowerZoneChanged() {
    // CRITICAL: Don't persist until restore is complete, otherwise we overwrite saved state
    if (!mounted || !_hasSlotLabProvider || !_lowerZoneRestoreComplete) {
      return;
    }
    // Persist lower zone state to provider (survives screen switches)
    _slotLabProvider.setLowerZoneTabIndex(_lowerZoneController.superTab.index);
    _slotLabProvider.setLowerZoneExpanded(_lowerZoneController.isExpanded);
    _slotLabProvider.setLowerZoneHeight(_lowerZoneController.height);
  }

  // Legacy mapping functions removed — now using SlotLabLowerZoneWidget with super-tabs

  /// Restore state from provider (survives screen switches)
  void _restorePersistedState() {
    // Poll until SlotLabProvider is available (set by _initializeSlotEngine)
    void tryRestore() {
      if (!mounted) return;
      if (_hasSlotLabProvider) {
        _doRestorePersistedState();
      } else {
        // Provider not ready yet, try again next frame
        Future.delayed(const Duration(milliseconds: 16), tryRestore);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => tryRestore());
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
      }
    });
  }

  void _doRestorePersistedState() {
    try {
      final provider = _slotLabProvider;

      // Restore lower zone tab state (survives screen switches)
      // NOTE: We persist SlotLabSuperTab index (0-4: stages, events, mix, dsp, bake)
      final tabIndex = provider.persistedLowerZoneTabIndex;

      if (tabIndex >= 0 && tabIndex < SlotLabSuperTab.values.length) {
        // Restore super-tab via controller WITHOUT changing expand state
        final superTab = SlotLabSuperTab.values[tabIndex];
        _lowerZoneController.restoreSuperTab(superTab);
        // Explicitly set expand state from persisted value
        if (provider.persistedLowerZoneExpanded) {
          _lowerZoneController.expand();
        } else {
          _lowerZoneController.collapse();
        }

        // Check if height is default (250.0) - if so, set to half screen
        final persistedHeight = provider.persistedLowerZoneHeight;
        if (persistedHeight == 250.0) {
          // No persisted height or default - set to half screen
          final screenHeight = MediaQuery.of(context).size.height;
          _lowerZoneController.setHeightToHalfScreen(screenHeight);
        } else {
          _lowerZoneController.setHeight(persistedHeight);
        }

      } else {
        // Still set half screen height for default case
        final screenHeight = MediaQuery.of(context).size.height;
        _lowerZoneController.setHeightToHalfScreen(screenHeight);
      }

      // NOW add listener and set flag - after restore is complete
      _lowerZoneRestoreComplete = true;
      _lowerZoneController.addListener(_onLowerZoneChanged);

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
                  eventId: regionData['eventId'] as String?, // CRITICAL: Restore eventId for lookup
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

      // CRITICAL: Sync region layers to match event layers (remove stale data)
      _syncAllRegionsToEvents();

      // P0 FIX: Restore grid config from imported GDD (if exists)
      final projectProvider = context.read<SlotLabProjectProvider>();
      final gridConfig = projectProvider.gridConfig;
      if (gridConfig != null) {
        setState(() {
          _slotLabSettings = _slotLabSettings.copyWith(
            reels: gridConfig.columns.clamp(3, 10),
            rows: gridConfig.rows.clamp(2, 8),
          );
        });
      }

      // Sync with MiddlewareProvider to get any changes made in Middleware mode
      _syncFromMiddlewareProvider();
    } catch (e) { /* ignored */ }
  }

  /// Sync ALL region layers to match their corresponding event layers
  /// Called after restore to sync with MiddlewareProvider changes
  void _syncAllRegionsToEvents() {
    // First pass: populate eventId in regions from _eventToRegionMap (for old data without eventId)
    for (final entry in _eventToRegionMap.entries) {
      final eventId = entry.key;
      final regionId = entry.value;
      for (final track in _tracks) {
        for (final region in track.regions) {
          if (region.id == regionId && region.eventId == null) {
            region.eventId = eventId;
          }
        }
      }
    }

    for (final track in _tracks) {
      for (final region in track.regions) {
        // CRITICAL FIX: Use region.eventId for lookup (ID-based, not name-based)
        SlotCompositeEvent? event;
        if (region.eventId != null && region.eventId!.isNotEmpty) {
          event = _middleware.getCompositeEvent(region.eventId!);
        }
        // Fallback to name-based for regions without eventId (old data)
        event ??= _compositeEvents.where((e) => e.name == region.name).firstOrNull;

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

    } catch (e) { /* ignored */ }
  }

  /// Check if any event in MiddlewareProvider has new actions and sync to timeline
  void _checkMiddlewareChangesAndSync(MiddlewareProvider middleware) {
    for (final mwEvent in middleware.events) {
      final currentActionCount = mwEvent.actions.length;
      final lastKnownCount = _lastKnownActionCounts[mwEvent.id] ?? 0;

      // Detect new actions added
      if (currentActionCount > lastKnownCount) {

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
              _syncEventLayersToRegion(mwEvent, track.regions[regionIndex], track);
              break;
            }
          }
        } else {
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
        continue;
      }

      // Skip empty asset IDs
      if (action.assetId.isEmpty || action.assetId == '—') {
        continue;
      }


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
      }

      // Skip if we already have a layer with this audioPath
      if (existingPaths.contains(audioPath)) {
        continue;
      }

      // If no clipId or duration, import via FFI to get REAL data
      if (clipId <= 0 || audioDuration <= 0) {
        if (_ffi.isLoaded && audioPath.isNotEmpty) {
          try {
            // Import audio to get real clipId
            // CRITICAL: Use SlotLab track ID offset (100000+) to avoid conflicting with DAW tracks
            final slotLabTrackId = ffiTrackId > 0 ? slotLabTrackIdToFfi(ffiTrackId) : kSlotLabTrackIdOffset;

            clipId = _ffi.importAudio(audioPath, slotLabTrackId, action.delay);
            if (clipId > 0) {
              _clipIdCache[audioPath] = clipId;

              // Get REAL duration from FFI metadata
              if (audioDuration <= 0) {
                audioDuration = _getAudioDuration(audioPath);
              }
            }
          } catch (e) { /* ignored */ }
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

    }

    // If no new layers, nothing to do
    if (newLayers.isEmpty) {
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
          isExpanded: mergedLayers.isNotEmpty, // Auto-expand when any layers (allows single layer drag)
          layers: mergedLayers,
          eventId: region.eventId, // CRITICAL: Preserve eventId for lookup
        );
      });
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
          'eventId': region.eventId, // CRITICAL: Persist eventId for lookup
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
    } catch (e) { /* ignored */ }
  }

  void _initializeSlotEngine() {
    if (!mounted) return;

    try {
      // Get SlotLabProvider synchronously (no postFrameCallback!)
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

        // Setup grid change callback (P0 WF-03)
        _slotLabProvider.onGridDimensionsChanged = (newReelCount) {
          _regenerateReelStages(newReelCount);
        };

        // Connect to ALE for signal sync
        try {
          final ale = Provider.of<AleProvider>(context, listen: false);
          _slotLabProvider.connectAle(ale);
          } catch (e) { /* ignored */ }

          // Set bet amount from UI
          _slotLabProvider.setBetAmount(_bet);

          // Listen to provider changes
          _slotLabProvider.addListener(_onSlotLabUpdate);

        } else {
        }

      // ═══════════════════════════════════════════════════════════════════════
      // CRITICAL: ALL EVENT SYNC HAPPENS HERE (synchronous, no delay!)
      // ═══════════════════════════════════════════════════════════════════════

      // Sync existing events from MiddlewareProvider to EventRegistry
      final middleware = Provider.of<MiddlewareProvider>(context, listen: false);
      final compositeEvents = middleware.compositeEvents;
      if (compositeEvents.isNotEmpty) {
        _syncAllEventsToRegistry();
      }

      // Sync persisted audio assignments from SlotLabProjectProvider
      _syncPersistedAudioAssignments();

      // Re-register symbol audio on screen mount
      _syncSymbolAudioToRegistry();

      // Re-register UltimateAudioPanel audio on mount
      _syncAudioAssignmentsToRegistry();

      // Initialize reel symbols (fallback or empty for engine)
      _reelSymbols = List.from(_fallbackReelSymbols);
      setState(() {});

      // Start background audio preload (does NOT block UI!)
      _startBackgroundAudioPreload();
    } catch (e) {
      _engineInitialized = false;
      _reelSymbols = List.from(_fallbackReelSymbols);
    }
  }

  /// Start background audio preloading without blocking UI
  /// This runs AFTER the UI is rendered, providing instant section switching
  void _startBackgroundAudioPreload() {
    if (_compositeEvents.isEmpty) {
      return;
    }

    final pathCount = eventRegistry.preloadedPathCount;
    if (pathCount == 0) {
      return;
    }

    // Set loading state (UI shows small indicator)
    setState(() {
      _isPreloadingAudio = true;
      _preloadedCount = 0;
      _preloadTotalCount = pathCount;
    });


    // Run preload in async isolate-friendly way (microtask queue)
    // This allows UI to render first, then preload runs
    Future.microtask(() async {
      if (!mounted) return;

      try {
        // Execute preload (this still runs on main isolate but AFTER UI render)
        final result = eventRegistry.preloadAllAudioFiles();

        if (!mounted) return;

        final loaded = result['loaded'] as int? ?? 0;
        final total = result['total'] as int? ?? 0;
        final duration = result['duration_ms'] as int? ?? 0;

        setState(() {
          _isPreloadingAudio = false;
          _preloadedCount = loaded;
          _preloadTotalCount = total;
        });

      } catch (e) {
        if (mounted) {
          setState(() => _isPreloadingAudio = false);
        }
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
  /// CRITICAL: Must match StandardSymbolSet in crates/rf-slot-lab/src/symbols.rs
  /// Symbol IDs from Rust:
  ///   1-4: HP1-HP4 (high paying)
  ///   5-10: LP1-LP6 (low paying)
  ///   11: WILD
  ///   12: SCATTER
  ///   13: BONUS
  List<List<String>> _gridToSymbols(List<List<int>> grid) {
    const symbolMap = {
      0: 'BLANK',
      // High Paying (HP1=highest, HP4=lowest of high tier)
      1: 'HP1',      // Premium symbol 💎
      2: 'HP2',      // 👑
      3: 'HP3',      // 🔔
      4: 'HP4',      // High pay 4
      // Low Paying (LP1=highest of low tier, LP6=lowest)
      5: 'LP1',      // Ace
      6: 'LP2',      // King
      7: 'LP3',      // Queen
      8: 'LP4',      // Jack
      9: 'LP5',      // Ten
      10: 'LP6',     // Nine
      // Special symbols
      11: 'WILD',    // 🃏
      12: 'SCATTER', // ⭐
      13: 'BONUS',   // 🎁
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
      _loadAudioPool();
    }
  }

  void _loadAudioPool() {

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
        return;
      }
    } catch (e) { /* ignored */ }

    // Keep existing audio pool if we have one (don't clear user's imported files)
    // Only initialize to empty if pool is truly uninitialized
    if (_audioPool.isEmpty) {
    } else {
    }
  }

  /// Import audio files via native file picker (faster than file_picker plugin)
  ///
  /// **INSTANT IMPORT** — Files appear immediately, metadata loads in background
  Future<void> _importAudioFiles() async {
    try {
      final paths = await InAppFileBrowser.pickAudioFiles(context);

      if (paths.isEmpty) return;

      // ⚡ INSTANT: Batch add - collect all entries first, then single setState
      final newEntries = <Map<String, dynamic>>[];
      for (final path in paths) {
        if (_audioPool.any((a) => a['path'] == path)) continue; // Skip duplicates
        final name = path.split('/').last;
        newEntries.add(_createAudioPoolEntry(path, name));
      }

      if (newEntries.isEmpty) return;

      // ⚡ INSTANT: Add to pool immediately
      setState(() {
        _audioPool.addAll(newEntries);
      });

      // 🔄 BACKGROUND: Persist state without blocking UI
      Future.microtask(() => _persistState());

      // 🔄 BACKGROUND: Load metadata for duration display
      _loadMetadataInBackground(newEntries.map((e) => e['path'] as String).toList());

    } catch (e) { /* ignored */ }
  }

  /// Import entire folder of audio files (native picker - faster)
  ///
  /// **INSTANT IMPORT** — Files appear immediately, metadata loads in background
  Future<void> _importAudioFolder() async {
    try {
      final result = await InAppFileBrowser.pickDirectory(context, title: 'Select Audio Folder');

      if (result == null) return;

      final dir = Directory(result);
      final audioExtensions = ['.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif', '.m4a', '.wma'];

      // Collect all audio files (sync listSync is faster for local dirs)
      final List<FileSystemEntity> entities;
      try {
        entities = dir.listSync(recursive: true);
      } catch (e) {
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

      // ⚡ INSTANT: Batch add - collect entries
      final newEntries = <Map<String, dynamic>>[];
      for (final file in audioFiles) {
        if (_audioPool.any((a) => a['path'] == file.path)) continue;
        final name = file.path.split('/').last;
        newEntries.add(_createAudioPoolEntry(file.path, name));
      }

      if (newEntries.isEmpty) return;

      // ⚡ INSTANT: Add to pool immediately
      setState(() {
        _audioPool.addAll(newEntries);
      });

      // 🔄 BACKGROUND: Persist state without blocking UI
      Future.microtask(() => _persistState());

      // 🔄 BACKGROUND: Load metadata for duration display
      _loadMetadataInBackground(newEntries.map((e) => e['path'] as String).toList());

    } catch (e) { /* ignored */ }
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

  /// Load metadata in background (duration, sampleRate, channels)
  ///
  /// Called after instant add — updates pool entries with real metadata
  /// P0 PERFORMANCE: Batched setState to avoid 100+ individual rebuilds
  void _loadMetadataInBackground(List<String> paths) {
    // P0 FIX: Load ALL metadata first, then do ONE setState
    Future(() async {
      final updates = <String, double>{};

      for (final path in paths) {
        try {
          final ffi = NativeFFI.instance;
          final duration = ffi.getAudioFileDuration(path);
          if (duration > 0) {
            updates[path] = duration;
          }
        } catch (_) {
          // Skip on error
        }
      }

      // P0 FIX: ONE setState for ALL updates (was doing 1 per file!)
      if (mounted && updates.isNotEmpty) {
        setState(() {
          for (final entry in updates.entries) {
            final index = _audioPool.indexWhere((a) => a['path'] == entry.key);
            if (index >= 0) {
              _audioPool[index] = {
                ..._audioPool[index],
                'duration': entry.value,
              };
            }
          }
        });
      }

    });
  }

  /// Load metadata for a single pool file (legacy - use batched version for multiple)
  Future<void> _loadMetadataForPoolFile(String filePath) async {
    final index = _audioPool.indexWhere((a) => a['path'] == filePath);
    if (index < 0) return;

    // Get duration from FFI (fast, ~5ms per file)
    double duration = 2.0;
    try {
      final ffi = NativeFFI.instance;
      final fileDuration = ffi.getAudioFileDuration(filePath);
      if (fileDuration > 0) {
        duration = fileDuration;
      }
    } catch (e) {
      // Use default duration on error
    }

    // Update pool entry with actual duration
    if (!mounted) return;
    final entry = _audioPool[index];
    if (entry['duration'] != duration) {
      setState(() {
        _audioPool[index] = {
          ...entry,
          'duration': duration,
        };
      });
    }
  }

  /// Add audio file to pool with metadata (legacy - use batch methods for multiple files)
  Future<void> _addAudioToPool(String path, String name) async {
    // Check if already in pool
    if (_audioPool.any((a) => a['path'] == path)) {
      return;
    }

    final entry = _createAudioPoolEntry(path, name);
    setState(() {
      _audioPool.add(entry);
    });

    // Load metadata in background
    _loadMetadataForPoolFile(path);

  }

  @override
  void dispose() {
    // Remove global keyboard handler
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);

    // Persist state before disposing
    _persistState();

    // Remove slot lab listener
    if (_engineInitialized && _hasSlotLabProvider) {
      _slotLabProvider.removeListener(_onSlotLabUpdate);
    }

    // Remove middleware listener (bidirectional sync)
    // Use cached reference — Provider.of(context) is unsafe during dispose()
    _middlewareRef?.removeListener(_onMiddlewareChanged);

    // Dispose drag controller
    _dragController?.removeListener(_onDragControllerChanged);
    _dragController?.dispose();

    // P14: Dispose Ultimate Timeline controller
    _ultimateTimelineController?.dispose();

    _spinTimer?.cancel();
    _playbackTimer?.cancel();
    _previewTimer?.cancel();
    _focusNode.dispose();
    _headersScrollController.dispose();
    _timelineScrollController.dispose();
    _horizontalScrollController.dispose();
    _dragCurrentOffsetNotifier.dispose();  // Dispose drag notifier
    _draggingLayerIdNotifier.dispose();    // Dispose drag ID notifier
    _disposeLayerPlayers(); // Dispose audio players
    disposeToast(); // InlineToastMixin cleanup
    // Only remove listener if it was added (after restore)
    if (_lowerZoneRestoreComplete) {
      _lowerZoneController.removeListener(_onLowerZoneChanged);
    }
    // NOTE: Do NOT dispose _lowerZoneController — it's a singleton that persists
    // across screen rebuilds. Disposing it causes "used after disposed" crash
    // when navigating back to SlotLab.
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
    } catch (e) { /* ignored */ }
  }

  void _setRtpc(int rtpcId, double value) {
    try {
      final mw = Provider.of<MiddlewareProvider>(this.context, listen: false);
      mw.setRtpc(rtpcId, value);
    } catch (e) { /* ignored */ }
  }

  /// Map intent/stage name to priority (0-100)
  int _intentToPriority(String intent) {
    final upper = intent.toUpperCase();
    // Jackpot highest priority
    if (upper.contains('JACKPOT')) return 90;
    // Big wins high priority
    if (upper.contains('ULTRA') || upper.contains('EPIC')) return 85;
    if (upper.contains('MEGA') || upper.contains('BIG_WIN')) return 80;
    // Features
    if (upper.contains('FEATURE') || upper.contains('BONUS')) return 70;
    if (upper.contains('FREE') || upper.contains('FS_')) return 65;
    // Wins
    if (upper.contains('WIN')) return 60;
    // Core gameplay
    if (upper.contains('SPIN')) return 50;
    if (upper.contains('REEL')) return 45;
    if (upper.contains('ANTICIPATION')) return 55;
    // UI lowest
    if (upper.contains('UI_')) return 20;
    // Default
    return 40;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

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
      return PremiumSlotPreview(
        key: ValueKey('fullscreen_slot_${_reelCount}x$_rowCount'),
        onExit: () => setState(() => _isPreviewMode = false),
        reels: _reelCount,
        rows: _rowCount,
        isFullscreen: true, // Fullscreen mode — handles SPACE key internally
        // P5: Pass project provider for dynamic win tier configuration
        projectProvider: context.read<SlotLabProjectProvider>(),
      );
    }

    return ChangeNotifierProvider<SlotLabLowerZoneController>.value(
      value: _lowerZoneController,
      child: GestureDetector(
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

              // Main area - V6 3-Panel Layout with P2-12 Responsive Breakpoints
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;

                    // Determine panel visibility based on breakpoints
                    final showLeftPanel = availableWidth >= _breakpointHideLeft &&
                        !_leftPanelManuallyHidden;
                    final showRightPanel = availableWidth >= _breakpointHideRight &&
                        !_rightPanelManuallyHidden;

                    // Force hide both if extremely narrow
                    final forceHideBoth = availableWidth < _breakpointHideBoth;

                    // Calculate center width to ensure minimum
                    final leftWidth = (showLeftPanel && !forceHideBoth) ? 240.0 : 0.0;
                    final rightWidth = (showRightPanel && !forceHideBoth) ? 300.0 : 0.0;
                    final centerWidth = availableWidth - leftWidth - rightWidth;

                    // If center would be too small, hide side panels
                    final actualShowLeft = showLeftPanel && !forceHideBoth && centerWidth >= _minCenterWidth;
                    final actualShowRight = showRightPanel && !forceHideBoth &&
                        (centerWidth >= _minCenterWidth || !actualShowLeft);

                    return Row(
                      children: [
                        // LEFT: Ultimate Audio Panel (V7 — replaces SymbolStripWidget)
                        if (actualShowLeft)
                          Consumer2<SlotLabProjectProvider, FeatureBuilderProvider>(
                      builder: (context, projectProvider, featureBuilderProvider, _) {
                        // P13.8.6: Get generated stages for instant display
                        final stageResult = featureBuilderProvider.generateStages();
                        final generatedStages = stageResult.isValid ? stageResult.stages : null;

                        return Container(
                          width: 240,
                          clipBehavior: Clip.hardEdge,
                          decoration: const BoxDecoration(),
                          child: UltimateAudioPanel(
                            audioAssignments: projectProvider.audioAssignments,
                            symbols: projectProvider.symbols,
                            contexts: projectProvider.contexts,
                            expandedSections: projectProvider.expandedSections,
                            expandedGroups: projectProvider.expandedGroups,
                            // P5: Dynamic win tier configuration
                            winConfiguration: projectProvider.winConfiguration,
                            // P13.8.6: Feature Builder generated stages (instant display)
                            generatedStages: generatedStages,
                            // P3-19: Quick Assign Mode
                            quickAssignMode: _quickAssignMode,
                            quickAssignSelectedSlot: _quickAssignSelectedSlot,
                            onQuickAssignSlotSelected: (stage) {
                              if (stage == '__TOGGLE__') {
                                // Toggle mode
                                setState(() {
                                  _quickAssignMode = !_quickAssignMode;
                                  if (!_quickAssignMode) {
                                    _quickAssignSelectedSlot = null;
                                  }
                                });
                              } else if (stage == '__UNSELECT__') {
                                // Unselect (toggle off)
                                setState(() => _quickAssignSelectedSlot = null);
                              } else {
                                // Select slot
                                setState(() => _quickAssignSelectedSlot = stage);
                              }
                            },
                            onAudioAssign: (stage, audioPath) {

                              // Update provider (persisted state)
                              projectProvider.setAudioAssignment(stage, audioPath);

                              // ═══════════════════════════════════════════════════════
                              // DETERMINE LOOP & OVERLAP SETTINGS BASED ON STAGE TYPE
                              // ═══════════════════════════════════════════════════════
                              final stageConfig = StageConfigurationService.instance;
                              final busId = _getBusForStage(stage);
                              final shouldLoop = stageConfig.isLooping(stage);
                              final isMusicBus = busId == 1;
                              final shouldOverlap = !isMusicBus && !shouldLoop;
                              final crossfadeMs = isMusicBus ? 500 : 0;

                              // Register event to EventRegistry for instant playback
                              eventRegistry.registerEvent(AudioEvent(
                                id: 'audio_$stage',
                                name: stage.replaceAll('_', ' '),
                                stage: stage,
                                layers: [
                                  AudioLayer(
                                    id: 'layer_$stage',
                                    name: '${stage.replaceAll('_', ' ')} Audio',
                                    audioPath: audioPath,
                                    volume: 1.0,
                                    pan: _getPanForStage(stage),
                                    delay: 0.0,
                                    busId: busId,
                                  ),
                                ],
                                loop: shouldLoop,
                                overlap: shouldOverlap,
                                crossfadeMs: crossfadeMs,
                                targetBusId: busId,
                              ));

                              // CENTRAL BRIDGE: Create/update composite event for timeline + event folder
                              _ensureCompositeEventForStage(stage, audioPath);


                              // SL-INT-P1.1: Show inline toast confirmation
                              if (mounted) {
                                final fileName = audioPath.split('/').last;
                                showToast('Assigned "$fileName" → ${stage.replaceAll("_", " ")}', icon: Icons.audiotrack);
                              }
                            },
                            onAudioClear: (stage) {
                              // Update provider (persisted state)
                              projectProvider.removeAudioAssignment(stage);
                              // Remove from EventRegistry
                              eventRegistry.unregisterEvent('audio_$stage');
                              // Remove from MiddlewareProvider (Event Folder)
                              final middleware = context.read<MiddlewareProvider>();
                              middleware.deleteCompositeEvent('audio_$stage');
                            },
                            onSectionToggle: (sectionId) {
                              projectProvider.toggleSection(sectionId);
                            },
                            onGroupToggle: (groupId) {
                              projectProvider.toggleGroup(groupId);
                            },
                            onBatchDistribute: (matched, unmatched) async {
                              // Show results dialog (SL-LP-P0.3)
                              await BatchDistributionDialog.show(
                                context,
                                matched: matched,
                                unmatched: unmatched,
                              );
                            },
                            // ═══════════════════════════════════════════════════════
                            // P3 RECOMMENDATIONS: Undo/Redo & Bulk Assign
                            // ═══════════════════════════════════════════════════════
                            canUndo: projectProvider.canUndoAudioAssignment,
                            canRedo: projectProvider.canRedoAudioAssignment,
                            undoDescription: projectProvider.undoAudioDescription,
                            redoDescription: projectProvider.redoAudioDescription,
                            onUndo: () {
                              final success = projectProvider.undoAudioAssignment();
                              if (success && mounted) {
                                showToast('Undo successful', type: ToastType.info, icon: Icons.undo);
                              }
                            },
                            onRedo: () {
                              final success = projectProvider.redoAudioAssignment();
                              if (success && mounted) {
                                showToast('Redo successful', type: ToastType.info, icon: Icons.redo);
                              }
                            },
                            onBulkAssign: (baseStage, audioPath) {
                              final expandedStages = projectProvider.bulkAssignToSimilarStages(
                                baseStage,
                                audioPath,
                              );
                              if (expandedStages.isNotEmpty && mounted) {
                                // Register all expanded events to EventRegistry
                                for (final stage in expandedStages) {
                                  final shouldLoop = StageConfigurationService.instance.isLooping(stage);
                                  final busId = _getBusForStage(stage);

                                  eventRegistry.registerEvent(AudioEvent(
                                    id: 'audio_$stage',
                                    name: stage.replaceAll('_', ' '),
                                    stage: stage,
                                    layers: [
                                      AudioLayer(
                                        id: 'layer_$stage',
                                        name: '${stage.replaceAll('_', ' ')} Audio',
                                        audioPath: audioPath,
                                        volume: 1.0,
                                        pan: _getPanForStage(stage),
                                        delay: 0.0,
                                        busId: busId,
                                      ),
                                    ],
                                    loop: shouldLoop,
                                    targetBusId: busId,
                                  ));
                                }
                                showToast('Bulk assigned to ${expandedStages.length} stages', icon: Icons.copy_all);
                              }
                            },
                          ),
                        );
                      },
                    ), // End of if (actualShowLeft) Consumer2 (P13.8.6)

                        // CENTER: Premium Slot Preview
                        Expanded(
                          child: ClipRect(
                            child: _buildMockSlot(),
                          ),
                        ),

                        // RIGHT: Events Panel (V6) — conditional visibility
                        if (actualShowRight)
                          SizedBox(
                            width: 300,
                            child: EventsPanelWidget(
                              selectedEventId: _selectedEventId,
                              onSelectionChanged: (eventId) {
                                setState(() {
                                  _selectedEventId = eventId;
                                });
                              },
                              onAudioDragStarted: (audioPaths) {
                                setState(() {
                                  _draggingAudioPaths = audioPaths;
                                });
                              },
                              // P3-19: Quick Assign Mode — click audio to assign to selected slot
                              onAudioClicked: (audioPath) {
                                if (_quickAssignMode && _quickAssignSelectedSlot != null) {
                                  // Use existing onAudioAssign logic
                                  final projectProvider = context.read<SlotLabProjectProvider>();
                                  _handleQuickAssign(audioPath, _quickAssignSelectedSlot!, projectProvider);
                                  // Clear selection after assign
                                  setState(() => _quickAssignSelectedSlot = null);
                                }
                              },
                              // Connect header toggle to audio browser visibility
                              showAudioBrowser: _showAudioBrowser,
                              onToast: (message, {isWarning = false}) {
                                showToast(message, type: isWarning ? ToastType.warning : ToastType.success);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // Bottom Panel - SlotLabLowerZoneWidget with super-tabs
              SlotLabLowerZoneWidget(
                controller: _lowerZoneController,
                slotLabProvider: _slotLabProvider,
                onSpin: () => _slotLabProvider.spin(),
                onForceOutcome: (outcome) => _slotLabProvider.spinForced(_parseOutcome(outcome)),
                onAudioDropped: null, // Edit Mode removed - audio drop via UltimateAudioPanel
                onPause: () => _slotLabProvider.stopStagePlayback(),
                onResume: () {}, // Resume not implemented
                onStop: () => _slotLabProvider.stopStagePlayback(),
                // P14: Delegate timeline rendering to slot_lab_screen
                onBuildTimelineContent: _buildTimelineContent,
              ),
            ],
          ),

          // Drag overlay (supports multiple files)
          if (_draggingAudioPaths != null && _draggingAudioPaths!.isNotEmpty && _dragPosition != null)
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
                    _draggingAudioPaths!.length > 1
                        ? '${_draggingAudioPaths!.length} files'
                        : _draggingAudioPaths!.first.split('/').last,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),

          // DEBUG: Drag status overlay (shows last drag action)
          if (_lastDragStatus.isNotEmpty &&
              _lastDragStatusTime != null &&
              DateTime.now().difference(_lastDragStatusTime!).inSeconds < 5)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _lastDragStatus.startsWith('✅')
                          ? Colors.green.withOpacity(0.9)
                          : Colors.red.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Text(
                      _lastDragStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KEYBOARD SHORTCUTS
  // ═══════════════════════════════════════════════════════════════════════════

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // If a text field has focus, don't intercept ANY keys (let user type)
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final editable = primaryFocus.context!.findAncestorWidgetOfExactType<EditableText>();
      if (editable != null) return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Keys that allow repeat (hold key for continuous adjustment)
    final isZoomKey = key == LogicalKeyboardKey.keyG || key == LogicalKeyboardKey.keyH;
    final isArrowKey = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;

    // Accept KeyDownEvent and KeyRepeatEvent (for zoom and arrows)
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Only allow repeat for zoom and arrow keys
    if (event is KeyRepeatEvent && !isZoomKey && !isArrowKey) return KeyEventResult.ignored;

    // Space = Handled by global keyboard handler (_globalKeyHandler)
    // This ensures Space works even when focus is lost to Lower Zone panels
    // See initState() for the global handler registration
    if (key == LogicalKeyboardKey.space) {
      // Let global handler handle it — don't double-process
      return KeyEventResult.ignored;
    }

    // Escape = Stop all playback (stages and timeline)
    if (key == LogicalKeyboardKey.escape) {
      var handled = false;
      // P0.3: Stop stage playback if active
      if (_hasSlotLabProvider && (_slotLabProvider.isPlayingStages || _slotLabProvider.isPaused)) {
        _slotLabProvider.stopStagePlayback();
        handled = true;
      }
      // Stop timeline playback if active
      if (_isPlaying) {
        _stopPlayback();
        handled = true;
      }
      if (handled) return KeyEventResult.handled;
    }

    // G = Zoom Out (supports hold for continuous zoom)
    if (key == LogicalKeyboardKey.keyG) {
      setState(() {
        _timelineZoom = (_timelineZoom * 0.85).clamp(0.1, 10.0);
      });
      return KeyEventResult.handled;
    }

    // H = Zoom In (supports hold for continuous zoom)
    if (key == LogicalKeyboardKey.keyH) {
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

    // S = Toggle snap-to-grid
    if (key == LogicalKeyboardKey.keyS && !HardwareKeyboard.instance.isMetaPressed) {
      _dragController?.toggleSnap();
      return KeyEventResult.handled;
    }

    // ESC = Cancel active drag (revert to original position)
    if (key == LogicalKeyboardKey.escape) {
      if (_dragController?.cancelActiveDrag() == true) {
        return KeyEventResult.handled;
      }
      // ESC with no active drag - deselect regions
      _clearAllRegionSelections();
      setState(() {});
      return KeyEventResult.handled;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOWER ZONE SHORTCUTS (1-4 for tabs, backtick for toggle)
    // Only process without modifiers to avoid conflicts with Cmd+1/2/etc.
    // ═══════════════════════════════════════════════════════════════════════════
    final hasModifier = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed;

    if (!hasModifier) {
      // Backtick = Toggle bottom panel expand/collapse
      if (key == LogicalKeyboardKey.backquote) {
        setState(() => _bottomPanelCollapsed = !_bottomPanelCollapsed);
        return KeyEventResult.handled;
      }

      // Note: digit1-4 shortcuts intentionally NOT added here to avoid
      // conflict with ForcedOutcome buttons in QuickOutcomeBar.
      // Users can click tabs or use backtick to toggle.
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BOTTOM PANEL TAB SHORTCUTS (Ctrl+Shift+Letter)
    // Switch between bottom panel tabs
    // ═══════════════════════════════════════════════════════════════════════════
    final isCtrlShift = (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlShift) {
      // V6 Keyboard shortcuts for Lower Zone tabs (now using super-tabs: 1-5)
      // STAGES=1, EVENTS=2, MIX=3, DSP=4, BAKE=5

      // Ctrl+Shift+1 = STAGES tab
      if (key == LogicalKeyboardKey.digit1) {
        _lowerZoneController.setSuperTab(SlotLabSuperTab.stages);
        return KeyEventResult.handled;
      }

      // Ctrl+Shift+2 = EVENTS tab
      if (key == LogicalKeyboardKey.digit2) {
        _lowerZoneController.setSuperTab(SlotLabSuperTab.events);
        return KeyEventResult.handled;
      }

      // Ctrl+Shift+3 = MIX tab
      if (key == LogicalKeyboardKey.digit3) {
        _lowerZoneController.setSuperTab(SlotLabSuperTab.mix);
        return KeyEventResult.handled;
      }

      // Ctrl+Shift+4 = DSP tab
      if (key == LogicalKeyboardKey.digit4) {
        _lowerZoneController.setSuperTab(SlotLabSuperTab.dsp);
        return KeyEventResult.handled;
      }

      // Ctrl+Shift+5 = BAKE tab
      if (key == LogicalKeyboardKey.digit5) {
        _lowerZoneController.setSuperTab(SlotLabSuperTab.bake);
        return KeyEventResult.handled;
      }

      // Ctrl+Shift+C = Command Builder (opens dialog)
      if (key == LogicalKeyboardKey.keyC) {
        _showCommandBuilderDialog();
        return KeyEventResult.handled;
      }
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
      }
    }

    if (event != null) {
      final eventName = event.name;
      final deletedEventId = event.id;


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
        }
      });
    } else {
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

          const SizedBox(width: 16),

          // ═══════════════════════════════════════════════════════════════════
          // P3-15 + P3-16 + M1-4 + P13: Templates, Coverage, Dashboard, Features
          // ═══════════════════════════════════════════════════════════════════
          _buildTemplatesButton(),
          const SizedBox(width: 8),
          _buildCoverageBadge(),
          const SizedBox(width: 8),
          _buildDashboardButton(),
          const SizedBox(width: 8),
          _buildFeatureBuilderButton(),

          const Spacer(),

          // Inline toast — compact, non-intrusive feedback
          buildToastWidget(),

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
                // Background audio preload indicator (shows only during preload)
                if (_isPreloadingAudio) ...[
                  const SizedBox(width: 8),
                  _buildAudioPreloadIndicator(),
                ],
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

          // View toggles
          _buildGlassButton(
            icon: Icons.folder_open,
            onTap: () => setState(() => _showAudioBrowser = !_showAudioBrowser),
            tooltip: 'Audio Browser',
            isActive: _showAudioBrowser,
          ),
          const SizedBox(width: 4),
          _buildGlassButton(
            icon: Icons.upload_file,
            onTap: _showGddImportWizard,
            tooltip: 'Import GDD',
          ),
          const SizedBox(width: 4),
          _buildGlassButton(
            icon: Icons.settings,
            onTap: _showSettingsDialog,
            tooltip: 'Settings',
          ),

          // P2-12: Panel visibility toggles
          const SizedBox(width: 8),
          Container(
            height: 24,
            width: 1,
            color: Colors.white24,
          ),
          const SizedBox(width: 8),
          _buildGlassButton(
            icon: Icons.view_sidebar,
            onTap: _toggleLeftPanel,
            tooltip: _leftPanelManuallyHidden ? 'Show Audio Panel' : 'Hide Audio Panel',
            isActive: !_leftPanelManuallyHidden,
          ),
          const SizedBox(width: 4),
          _buildGlassButton(
            icon: Icons.view_sidebar_outlined,
            onTap: _toggleRightPanel,
            tooltip: _rightPanelManuallyHidden ? 'Show Events Panel' : 'Hide Events Panel',
            isActive: !_rightPanelManuallyHidden,
          ),

          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P3-15: Templates Gallery Button
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTemplatesButton() {
    return Tooltip(
      message: 'Template Gallery',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showTemplateGallery,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF4A9EFF).withOpacity(0.2),
                  const Color(0xFF4A9EFF).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF4A9EFF).withOpacity(0.4),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dashboard_customize, size: 14, color: Color(0xFF4A9EFF)),
                SizedBox(width: 6),
                Text(
                  'Templates',
                  style: TextStyle(
                    color: Color(0xFF4A9EFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTemplateGallery() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 900,
          height: 650,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF333340), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.dashboard_customize, color: Color(0xFF4A9EFF), size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Template Gallery',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Start with a pre-configured slot audio template',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              // Template Gallery Panel
              Expanded(
                child: TemplateGalleryPanel(
                  onTemplateApplied: (builtTemplate) async {
                    Navigator.of(ctx).pop();
                    await _applyTemplate(builtTemplate);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyTemplate(BuiltTemplate builtTemplate) async {
    // ignore: unused_local_variable
    final projectProvider = context.read<SlotLabProjectProvider>();
    final template = builtTemplate.source;

    // Apply template configuration to project
    // This would register stages, create events, set up buses, etc.

    // Update grid settings from template
    setState(() {
      _slotLabSettings = _slotLabSettings.copyWith(
        reels: template.reelCount,
        rows: template.rowCount,
      );
    });

    // Show success
    if (mounted) {
      showToast('Applied template "${template.name}" — ${template.symbols.length} symbols, ${template.coreStages.length} stages');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P3-16: Coverage Indicator Badge
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCoverageBadge() {
    return Consumer<SlotLabProjectProvider>(
      builder: (ctx, provider, _) {
        final counts = provider.getAudioAssignmentCounts();
        final assigned = (counts['symbol_total'] ?? 0) + (counts['music_total'] ?? 0);
        const total = 341; // Total audio slots in UltimateAudioPanel
        final percent = total > 0 ? (assigned / total * 100).round() : 0;

        // Color based on progress
        Color progressColor;
        if (percent < 25) {
          progressColor = const Color(0xFFFF6B6B); // Red
        } else if (percent < 75) {
          progressColor = const Color(0xFFFFAA00); // Orange/Yellow
        } else {
          progressColor = const Color(0xFF40FF90); // Green
        }

        return Tooltip(
          message: 'Audio Coverage: $assigned of $total slots assigned\nClick for breakdown',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showCoverageBreakdown(counts, assigned, total),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: progressColor.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Icon(
                      percent >= 100 ? Icons.check_circle : Icons.pie_chart,
                      size: 12,
                      color: progressColor,
                    ),
                    const SizedBox(width: 6),
                    // Text
                    Text(
                      '$assigned/$total',
                      style: TextStyle(
                        color: progressColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Mini progress bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (percent / 100).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: progressColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Percentage
                    Text(
                      '$percent%',
                      style: TextStyle(
                        color: progressColor.withOpacity(0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCoverageBreakdown(Map<String, int> counts, int assigned, int total) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.pie_chart, color: Color(0xFF4A9EFF), size: 20),
            SizedBox(width: 8),
            Text('Audio Coverage Breakdown', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCoverageRow('Symbol Audio', counts['symbol_total'] ?? 0, 280),
              const SizedBox(height: 8),
              _buildCoverageRow('Music Layers', counts['music_total'] ?? 0, 61),
              const Divider(color: Colors.white24, height: 24),
              _buildCoverageRow('Total', assigned, total, isTotal: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // M1 Task 4: Project Dashboard Button
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDashboardButton() {
    return Tooltip(
      message: 'Project Dashboard\nOverview, validation, and notes',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showProjectDashboard,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF40C8FF).withValues(alpha: 0.2),
                  const Color(0xFF40C8FF).withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF40C8FF).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dashboard, color: Color(0xFF40C8FF), size: 14),
                SizedBox(width: 6),
                Text(
                  'Dashboard',
                  style: TextStyle(
                    color: Color(0xFF40C8FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showProjectDashboard() {
    ProjectDashboardDialog.show(context);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P13: Feature Builder Button
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildFeatureBuilderButton() {
    return Tooltip(
      message: 'Feature Builder\nConfigure slot features and audio stages',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showFeatureBuilder,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF9370DB).withValues(alpha: 0.2),
                  const Color(0xFF9370DB).withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF9370DB).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.extension, color: Color(0xFF9370DB), size: 14),
                SizedBox(width: 6),
                Text(
                  'Features',
                  style: TextStyle(
                    color: Color(0xFF9370DB),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFeatureBuilder() async {
    final result = await FeatureBuilderPanel.show(context);

    if (result != null && mounted) {
      // Apply configuration to SlotLab
      _applyFeatureBuilderResult(result);
    }
  }

  void _applyFeatureBuilderResult(FeatureBuilderResult result) {
    final projectProvider = context.read<SlotLabProjectProvider>();
    final slotLabProvider = context.read<SlotLabProvider>();

    // Update settings with grid configuration
    // The slot machine is already displayed in the center panel via _buildMockSlot()
    // We just update the grid dimensions - NO fullscreen mode needed
    setState(() {
      _slotLabSettings = _slotLabSettings.copyWith(
        reels: result.reelCount,
        rows: result.rowCount,
      );
    });

    // Generate default symbols if needed
    if (projectProvider.symbols.isEmpty) {
      _generateDefaultSymbols(result.symbolCount, projectProvider);
    }

    // Initialize engine with new configuration
    slotLabProvider.updateGridSize(result.reelCount, result.rowCount);

    // Show success message
    if (mounted) {
      showToast('Slot machine built: ${result.reelCount}×${result.rowCount} grid with ${result.symbolCount} symbols');
    }
  }

  void _generateDefaultSymbols(int count, SlotLabProjectProvider provider) {
    // Generate default symbols based on count
    final defaultSymbols = <SymbolDefinition>[];

    // Common slot symbol emojis
    const symbolEmojis = ['🍒', '🍋', '🍊', '🍇', '⭐', '💎', '7️⃣', '🔔', '🍀', '👑', '🎰', '💰'];
    const symbolNames = ['Cherry', 'Lemon', 'Orange', 'Grapes', 'Star', 'Diamond', 'Seven', 'Bell', 'Clover', 'Crown', 'Jackpot', 'Money'];

    for (int i = 0; i < count && i < symbolEmojis.length; i++) {
      final type = i < 2
          ? SymbolType.lowPay
          : i < 5
              ? SymbolType.mediumPay
              : i < 8
                  ? SymbolType.highPay
                  : i == count - 2
                      ? SymbolType.scatter
                      : i == count - 1
                          ? SymbolType.wild
                          : SymbolType.highPay;

      defaultSymbols.add(SymbolDefinition(
        id: 'sym_$i',
        name: symbolNames[i],
        emoji: symbolEmojis[i],
        type: type,
        contexts: const ['land', 'win'],
      ));
    }

    // Add symbols to provider
    for (final symbol in defaultSymbols) {
      provider.addSymbol(symbol);
    }
  }

  Widget _buildCoverageRow(String label, int count, int max, {bool isTotal = false}) {
    final percent = max > 0 ? (count / max * 100).round() : 0;
    final color = percent < 25
        ? const Color(0xFFFF6B6B)
        : percent < 75
            ? const Color(0xFFFFAA00)
            : const Color(0xFF40FF90);

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              color: isTotal ? Colors.white : Colors.white70,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (percent / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                  '$count/$max',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showGddImportWizard() async {
    final result = await GddImportWizard.show(context);

    if (result == null) {
      // User canceled or error
      if (mounted) {
        showToast('GDD import canceled', type: ToastType.info);
      }
      return;
    }

    if (!mounted) return;

    // Show preview dialog with mockup — user can confirm or cancel
    final confirmed = await GddPreviewDialog.show(context, result);

    if (confirmed == true && mounted) {

        // P0 FIX: Store GDD in SlotLabProjectProvider for persistence
        final projectProvider = context.read<SlotLabProjectProvider>();
        projectProvider.importGdd(result.gdd, generatedSymbols: result.generatedSymbols);

        // P0 FIX: Populate dynamic slot symbols from GDD for reel display
        _populateSlotSymbolsFromGdd(result.gdd.symbols);

        // P0 FIX: Initialize Rust engine with GDD to update grid configuration
        // Use toRustJson() which converts to the format rf-slot-lab's GddParser expects
        final slotLabProvider = context.read<SlotLabProvider>();
        final gddJson = jsonEncode(result.gdd.toRustJson());
        final engineInitialized = slotLabProvider.initEngineFromGdd(gddJson);

        final newReels = result.gdd.grid.columns.clamp(3, 10);
        final newRows = result.gdd.grid.rows.clamp(2, 8);

        // Apply GDD grid configuration to local slot settings
        // AND open fullscreen preview to show the new slot machine
        setState(() {
          _slotLabSettings = _slotLabSettings.copyWith(
            reels: newReels,
            rows: newRows,
            volatility: _volatilityFromGdd(result.gdd.math.volatility),
          );
          _isPreviewMode = true;  // Open fullscreen slot machine
        });


        // Show success message with grid info
        if (mounted) {
          showToast(
            'Applied GDD "${result.gdd.name}" — Grid: ${result.gdd.grid.columns}×${result.gdd.grid.rows}, ${result.generatedStages.length} stages',
            durationMs: 3000,
          );
        }
      }
  }

  /// Convert GDD volatility string to VolatilityLevel enum
  VolatilityLevel _volatilityFromGdd(String volatility) {
    final lower = volatility.toLowerCase();
    if (lower.contains('insane') || lower.contains('extreme')) {
      return VolatilityLevel.insane;
    }
    if (lower.contains('very') && lower.contains('high')) {
      return VolatilityLevel.insane;
    }
    if (lower.contains('high')) return VolatilityLevel.high;
    if (lower.contains('low')) return VolatilityLevel.low;
    if (lower.contains('casual')) return VolatilityLevel.casual;
    return VolatilityLevel.medium;
  }

  /// Populate SlotSymbol dynamic registry from GDD symbols
  /// Maps GDD symbols to Rust engine IDs based on tier:
  /// - HP1-HP4 (ID 1-4): premium/high tier symbols
  /// - LP1-LP6 (ID 5-10): mid/low tier symbols
  /// - WILD (ID 11), SCATTER (ID 12), BONUS (ID 13): special symbols
  void _populateSlotSymbolsFromGdd(List<GddSymbol> gddSymbols) {
    if (gddSymbols.isEmpty) {
      SlotSymbol.clearDynamicSymbols();
      return;
    }

    final dynamicSymbols = <int, SlotSymbol>{};

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 1: Categorize GDD symbols by tier/type
    // Industry standard mapping:
    // - Premium → HP1 (highest payer)
    // - High → HP2, HP3, HP4
    // - Mid → LP1, LP2, LP3 (Rust nema MP, ide u LP)
    // - Low → LP4, LP5, LP6
    // - Special types: WILD=11, SCATTER=12, BONUS=13
    // ═══════════════════════════════════════════════════════════════════════════
    final premiumSymbols = <GddSymbol>[];  // premium → HP1
    final highSymbols = <GddSymbol>[];     // high → HP2-HP4
    final midSymbols = <GddSymbol>[];      // mid → LP1-LP3
    final lowSymbols = <GddSymbol>[];      // low → LP4-LP6
    GddSymbol? wildSymbol;
    GddSymbol? scatterSymbol;
    GddSymbol? bonusSymbol;

    for (final gdd in gddSymbols) {
      // Check special types first (by flag OR by tier enum)
      if (gdd.isWild || gdd.tier == SymbolTier.wild) {
        wildSymbol = gdd;
      } else if (gdd.isScatter || gdd.tier == SymbolTier.scatter) {
        scatterSymbol = gdd;
      } else if (gdd.isBonus || gdd.tier == SymbolTier.bonus) {
        bonusSymbol = gdd;
      } else if (gdd.tier == SymbolTier.premium) {
        premiumSymbols.add(gdd);
      } else if (gdd.tier == SymbolTier.high) {
        highSymbols.add(gdd);
      } else if (gdd.tier == SymbolTier.mid) {
        midSymbols.add(gdd);
      } else {
        // low, special (non-wild/scatter/bonus)
        lowSymbols.add(gdd);
      }
    }


    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 2: Assign Rust engine IDs based on category
    // Premium → HP1 (ID 1)
    // High → HP2, HP3, HP4 (ID 2, 3, 4)
    // Mid → LP1, LP2, LP3 (ID 5, 6, 7)
    // Low → LP4, LP5, LP6 (ID 8, 9, 10)
    // Special: WILD = ID 11, SCATTER = ID 12, BONUS = ID 13
    // ═══════════════════════════════════════════════════════════════════════════

    int nextHpId = 1;  // HP starts at 1
    int nextLpId = 5;  // LP starts at 5

    // Premium symbols → HP1 (and HP2 if more than one)
    for (final gdd in premiumSymbols) {
      if (nextHpId > 4) break;  // Max 4 HP symbols
      dynamicSymbols[nextHpId] = _createSlotSymbol(gdd, nextHpId);
      nextHpId++;
    }

    // High symbols → remaining HP slots (HP2, HP3, HP4)
    for (final gdd in highSymbols) {
      if (nextHpId > 4) break;  // Max 4 HP symbols
      dynamicSymbols[nextHpId] = _createSlotSymbol(gdd, nextHpId);
      nextHpId++;
    }

    // Mid symbols → LP1, LP2, LP3 (ID 5, 6, 7)
    for (final gdd in midSymbols) {
      if (nextLpId > 10) break;  // Max 6 LP symbols (ID 5-10)
      final lpNum = nextLpId - 4;  // LP1=5, LP2=6...
      dynamicSymbols[nextLpId] = _createSlotSymbol(gdd, nextLpId);
      nextLpId++;
    }

    // Low symbols → remaining LP slots (LP4, LP5, LP6)
    for (final gdd in lowSymbols) {
      if (nextLpId > 10) break;  // Max 6 LP symbols
      final lpNum = nextLpId - 4;
      dynamicSymbols[nextLpId] = _createSlotSymbol(gdd, nextLpId);
      nextLpId++;
    }

    // Special symbols at fixed IDs
    if (wildSymbol != null) {
      dynamicSymbols[11] = _createSlotSymbol(wildSymbol, 11, isSpecial: true);
    }
    if (scatterSymbol != null) {
      dynamicSymbols[12] = _createSlotSymbol(scatterSymbol, 12, isSpecial: true);
    }
    if (bonusSymbol != null) {
      dynamicSymbols[13] = _createSlotSymbol(bonusSymbol, 13, isSpecial: true);
    }

    // Add blank symbol for ID 0
    dynamicSymbols[0] = const SlotSymbol(
      id: 0,
      name: 'BLANK',
      displayChar: '·',
      gradientColors: [Color(0xFF666666), Color(0xFF444444), Color(0xFF333333)],
      glowColor: Color(0xFF666666),
    );

    SlotSymbol.setDynamicSymbols(dynamicSymbols);
  }

  /// Helper to create SlotSymbol from GddSymbol
  SlotSymbol _createSlotSymbol(GddSymbol gdd, int id, {bool isSpecial = false}) {
    final colors = _getSymbolColorsForTier(gdd.tier, gdd.isWild, gdd.isScatter, gdd.isBonus);
    return SlotSymbol(
      id: id,
      name: gdd.name.isNotEmpty ? gdd.name : gdd.id.toUpperCase(),
      displayChar: gdd.name.isNotEmpty ? gdd.name : gdd.id.toUpperCase(),  // Show name, not emoji
      gradientColors: colors['gradient']!,
      glowColor: colors['glow']!.first,
      isSpecial: isSpecial || gdd.isWild || gdd.isScatter || gdd.isBonus,
    );
  }

  /// Get emoji for symbol reel display based on name/theme
  String _getSymbolEmojiForReel(GddSymbol gdd) {
    final name = gdd.name.toLowerCase();

    // Theme-based emoji mapping (Greek, Egyptian, Asian, etc.)
    if (name.contains('zeus') || name.contains('thunder')) return '⚡';
    if (name.contains('poseidon') || name.contains('trident')) return '🔱';
    if (name.contains('athena') || name.contains('wisdom')) return '🦉';
    if (name.contains('hades') || name.contains('underworld')) return '💀';
    if (name.contains('apollo') || name.contains('sun')) return '☀️';
    if (name.contains('hermes') || name.contains('wing')) return '👟';
    if (name.contains('medusa') || name.contains('snake')) return '🐍';
    if (name.contains('pegasus') || name.contains('horse')) return '🦄';
    if (name.contains('cerberus') || name.contains('dog')) return '🐕';
    if (name.contains('olympus') || name.contains('mountain')) return '⛰️';
    if (name.contains('dragon')) return '🐉';
    if (name.contains('tiger')) return '🐅';
    if (name.contains('phoenix')) return '🔥';
    if (name.contains('koi') || name.contains('fish')) return '🐟';
    if (name.contains('panda')) return '🐼';
    if (name.contains('jade')) return '💚';
    if (name.contains('lotus')) return '🪷';
    if (name.contains('ra') || name.contains('eye')) return '👁️';
    if (name.contains('anubis') || name.contains('jackal')) return '🐺';
    if (name.contains('horus') || name.contains('falcon')) return '🦅';
    if (name.contains('cleopatra') || name.contains('queen')) return '👸';
    if (name.contains('pharaoh') || name.contains('king')) return '👑';
    if (name.contains('scarab') || name.contains('beetle')) return '🪲';
    if (name.contains('pyramid')) return '🔺';
    if (name.contains('odin')) return '🧙';
    if (name.contains('thor') || name.contains('hammer')) return '🔨';
    if (name.contains('freya') || name.contains('love')) return '❤️';
    if (name.contains('loki') || name.contains('trickster')) return '🎭';
    if (name.contains('viking') || name.contains('ship')) return '⛵';
    if (name.contains('leprechaun')) return '🍀';
    if (name.contains('shamrock') || name.contains('clover')) return '☘️';
    if (name.contains('pot') && name.contains('gold')) return '🏆';
    if (name.contains('rainbow')) return '🌈';
    if (name.contains('seven') || name.contains('7')) return '7️⃣';
    if (name.contains('bar')) return '▬';
    if (name.contains('bell')) return '🔔';
    if (name.contains('cherry')) return '🍒';
    if (name.contains('lemon')) return '🍋';
    if (name.contains('orange')) return '🍊';
    if (name.contains('grape')) return '🍇';
    if (name.contains('apple')) return '🍎';
    if (name.contains('strawberry')) return '🍓';
    if (name.contains('blueberry')) return '🫐';
    if (name.contains('watermelon') || name.contains('melon')) return '🍉';
    if (name.contains('diamond')) return '💎';
    if (name.contains('gem') || name.contains('jewel')) return '💎';
    if (name.contains('gold') || name.contains('coin')) return '🪙';
    if (name.contains('treasure') || name.contains('chest')) return '📦';
    if (name.contains('crown')) return '👑';
    if (name.contains('star')) return '⭐';
    if (name.contains('heart')) return '❤️';
    if (name.contains('spade')) return '♠️';
    if (name.contains('club')) return '♣️';
    if (name.contains('ace')) return '🂡';
    if (name.contains('king')) return '🂮';
    if (name.contains('queen')) return '🂭';
    if (name.contains('jack')) return '🂫';
    if (name.contains('10') || name.contains('ten')) return '🔟';
    if (name.contains('9') || name.contains('nine')) return '9️⃣';
    if (name.contains('book')) return '📖';
    if (name.contains('scroll')) return '📜';

    // Wild/Scatter/Bonus
    if (gdd.isWild || gdd.tier == SymbolTier.wild) return '★';
    if (gdd.isScatter || gdd.tier == SymbolTier.scatter) return '◆';
    if (gdd.isBonus || gdd.tier == SymbolTier.bonus) return '♦';

    // Tier-based fallback with HP/MP/LP numbering
    final id = gdd.id.toUpperCase();
    if (id.contains('HP1') || id.contains('HIGH1')) return '👑';
    if (id.contains('HP2') || id.contains('HIGH2')) return '💎';
    if (id.contains('HP3') || id.contains('HIGH3')) return '🔔';
    if (id.contains('HP4') || id.contains('HIGH4')) return '🍒';
    if (id.contains('MP') || id.contains('MED')) return '🎲';
    if (id.contains('LP1') || id.contains('LOW1')) return '🍋';
    if (id.contains('LP2') || id.contains('LOW2')) return '🍊';
    if (id.contains('LP3') || id.contains('LOW3')) return '🍇';
    if (id.contains('LP4') || id.contains('LOW4')) return '🍏';
    if (id.contains('LP5') || id.contains('LOW5')) return '🍓';
    if (id.contains('LP6') || id.contains('LOW6')) return '🫐';

    // Generic tier fallback
    switch (gdd.tier) {
      case SymbolTier.premium: return '👑';
      case SymbolTier.high: return '💎';
      case SymbolTier.mid: return '🎲';
      case SymbolTier.low: return '🃏';
      case SymbolTier.wild: return '★';
      case SymbolTier.scatter: return '◆';
      case SymbolTier.bonus: return '♦';
      case SymbolTier.special: return '✦';
    }
  }

  /// Get gradient colors for symbol tier (for reel rendering)
  /// Uses industry-standard colors with MAXIMUM CONTRAST:
  /// - HP: Precious gems (Ruby, Emerald, Sapphire, Amethyst)
  /// - LP: Fruit colors (Lemon, Orange, Grape, Lime, Strawberry, Blueberry)
  /// - Special: Electric/Neon (Gold, Magenta, Cyan)
  Map<String, List<Color>> _getSymbolColorsForTier(SymbolTier tier, bool isWild, bool isScatter, bool isBonus) {
    // Special symbols override tier colors — MAXIMUM VISUAL IMPACT
    if (isWild || tier == SymbolTier.wild) {
      return {
        'gradient': [const Color(0xFFFFEE77), const Color(0xFFFFD700), const Color(0xFFDD9900)],
        'glow': [const Color(0xFFFFDD00)],
      };
    }
    if (isScatter || tier == SymbolTier.scatter) {
      return {
        'gradient': [const Color(0xFFFF77FF), const Color(0xFFFF00FF), const Color(0xFFAA00AA)],
        'glow': [const Color(0xFFFF44FF)],
      };
    }
    if (isBonus || tier == SymbolTier.bonus) {
      return {
        'gradient': [const Color(0xFF77FFFF), const Color(0xFF00FFFF), const Color(0xFF008B8B)],
        'glow': [const Color(0xFF44FFFF)],
      };
    }

    // Tier-based colors — PRECIOUS gems for HP, FRUIT for LP
    switch (tier) {
      case SymbolTier.premium:
        // RUBY RED — Highest value HP1
        return {
          'gradient': [const Color(0xFFFF4444), const Color(0xFFDC143C), const Color(0xFF8B0000)],
          'glow': [const Color(0xFFFF2222)],
        };
      case SymbolTier.high:
        // EMERALD GREEN — HP2/HP3/HP4 (mapped to Emerald/Sapphire/Amethyst)
        return {
          'gradient': [const Color(0xFF66FFCC), const Color(0xFF50C878), const Color(0xFF006644)],
          'glow': [const Color(0xFF50C878)],
        };
      case SymbolTier.mid:
        // GRAPE PURPLE — LP1/LP2/LP3 (medium tier fruits)
        return {
          'gradient': [const Color(0xFF9966CC), const Color(0xFF6B3FA0), const Color(0xFF3D1F5C)],
          'glow': [const Color(0xFF8855BB)],
        };
      case SymbolTier.low:
        // BLUEBERRY BLUE — LP4/LP5/LP6 (lowest tier)
        return {
          'gradient': [const Color(0xFF7799DD), const Color(0xFF4169E1), const Color(0xFF2E4A8A)],
          'glow': [const Color(0xFF5577CC)],
        };
      case SymbolTier.special:
        // ORANGE — Special/mystery symbols
        return {
          'gradient': [const Color(0xFFFFAA44), const Color(0xFFFF8C00), const Color(0xFFCC5500)],
          'glow': [const Color(0xFFFF9933)],
        };
      default:
        return {
          'gradient': [const Color(0xFF666666), const Color(0xFF444444), const Color(0xFF333333)],
          'glow': [const Color(0xFF666666)],
        };
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: settings.SlotLabSettingsPanel(
          settings: _slotLabSettings,
          onSettingsChanged: (newSettings) {
            final oldSettings = _slotLabSettings;
            setState(() {
              _slotLabSettings = newSettings;
            });

            // Sync timing profile to provider/FFI
            if (oldSettings.timingProfile != newSettings.timingProfile) {
              final providerProfile = _timingProfileToProvider(newSettings.timingProfile);
              final provider = context.read<SlotLabProvider>();
              provider.setTimingProfile(providerProfile);
            }
          },
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// Map UI TimingProfile enum to Provider/FFI TimingProfileType enum
  TimingProfileType _timingProfileToProvider(settings.TimingProfile uiProfile) {
    return switch (uiProfile) {
      settings.TimingProfile.normal => TimingProfileType.normal,
      settings.TimingProfile.turbo => TimingProfileType.turbo,
      settings.TimingProfile.mobile => TimingProfileType.mobile,
      settings.TimingProfile.studio => TimingProfileType.studio,
    };
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

  /// Format milliseconds for drag tooltip display
  String _formatTimeMs(int ms) {
    if (ms < 1000) {
      return '${ms}ms';
    } else if (ms < 60000) {
      final secs = ms / 1000;
      return '${secs.toStringAsFixed(2)}s';
    } else {
      final mins = ms ~/ 60000;
      final secs = (ms % 60000) / 1000;
      return '${mins}m ${secs.toStringAsFixed(1)}s';
    }
  }

  /// Set loop region from selected region or event
  void _setLoopRegion(double start, double end) {
    setState(() {
      _loopStart = start;
      _loopEnd = end;
      _isLooping = true;  // Auto-enable looping when region is set
    });
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
          } catch (_) { /* ignored */ }
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
      // Stop always goes to position 0 (project start), regardless of loop region
      _playheadPosition = 0.0;
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
  /// CRITICAL: This now removes orphaned clips that no longer exist in _tracks
  void _syncLayersToTrackManager() {
    // Step 1: Collect all current layer IDs from _tracks
    final currentLayerIds = <String>{};
    for (final track in _tracks) {
      for (final region in track.regions) {
        for (final layer in region.layers) {
          if (layer.audioPath.isNotEmpty) {
            currentLayerIds.add(layer.id);
          }
        }
      }
    }

    // Step 2: Find and remove orphaned clips (exist in bridge but not in _tracks)
    final registeredIds = _trackBridge.registeredLayerIds;
    final orphanedIds = registeredIds.difference(currentLayerIds);
    for (final orphanId in orphanedIds) {
      _trackBridge.removeLayerClip(orphanId);
    }

    // Step 3: Add/update clips for current layers (skip muted)
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
  }

  /// @deprecated Use _syncLayersToTrackManager() + _trackBridge.play() instead
  void _checkAndTriggerLayers(double prevPos, double currentPos) {
    // DEPRECATED: PLAYBACK_ENGINE handles this automatically
  }

  /// @deprecated Use _syncLayersToTrackManager() + _trackBridge.play() instead
  /// Was used for individual layer playback via PREVIEW_ENGINE
  Future<void> _playLayerAudio(_RegionLayer layer, double offsetSeconds) async {
    // DEPRECATED: PLAYBACK_ENGINE handles clip playback automatically
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

  /// Compact audio preload indicator (shows during background loading)
  Widget _buildAudioPreloadIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF4A9EFF).withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF4A9EFF).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A9EFF)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Caching $_preloadTotalCount...',
            style: TextStyle(
              color: const Color(0xFF4A9EFF).withOpacity(0.9),
              fontSize: 10,
              fontWeight: FontWeight.w500,
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
      } else {
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

          // Timeline toolbar (snap, zoom, etc.)
          TimelineToolbar(
            dragController: dragController,
            zoomLevel: _timelineZoom,
            onZoomChanged: (zoom) => setState(() => _timelineZoom = zoom),
          ),

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

  /// Show dialog to add a new slot symbol
  void _showAddSymbolDialog() {
    final nameController = TextEditingController();
    final emojiController = TextEditingController(text: '🎰');
    SymbolType selectedType = SymbolType.lowPay;
    final selectedContexts = <String>{'land', 'win'};

    // Quick presets with (name, type, emoji, color)
    final symbolPresets = <(String, SymbolType, String, Color)>[
      ('Wild', SymbolType.wild, '🃏', const Color(0xFF9C27B0)),
      ('Scatter', SymbolType.scatter, '⭐', const Color(0xFFFFD700)),
      ('Bonus', SymbolType.bonus, '🎁', const Color(0xFFFF5722)),
      ('High Pay', SymbolType.highPay, '💎', const Color(0xFF2196F3)),
      ('Medium Pay', SymbolType.mediumPay, '🔔', const Color(0xFF4CAF50)),
      ('Low Pay', SymbolType.lowPay, 'A', const Color(0xFF607D8B)),
      ('Multiplier', SymbolType.multiplier, '✖️', const Color(0xFFE91E63)),
      ('Collector', SymbolType.collector, '💰', const Color(0xFFFFC107)),
      ('Mystery', SymbolType.mystery, '❓', const Color(0xFF795548)),
    ];

    // Emoji options for quick selection
    final emojiOptions = [
      // Special
      '🃏', '⭐', '🎁', '❓', '✖️',
      // High pay
      '💎', '👑', '🔔', '7️⃣', '🍀',
      // Themed
      '🦁', '🐯', '🦅', '🐉', '🔥',
      // Fruit
      '🍒', '🍋', '🍊', '🍇', '🍉',
      // Cards
      'A', 'K', 'Q', 'J', '10',
      // Coins
      '🪙', '💰', '💵', '💎', '🏆',
    ];

    // Audio context options (from SymbolAudioContext enum)
    final contextOptions = SymbolAudioContext.values.map((c) => c.name).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A22),
          title: const Text(
            'Add Symbol',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Presets
                  const Text('Quick Presets', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: symbolPresets.map((preset) => GestureDetector(
                      onTap: () => setDialogState(() {
                        nameController.text = preset.$1;
                        selectedType = preset.$2;
                        emojiController.text = preset.$3;
                        // Set default contexts based on type
                        selectedContexts.clear();
                        selectedContexts.addAll({'land', 'win'});
                        if (preset.$2 == SymbolType.wild) {
                          selectedContexts.add('expand');
                        } else if (preset.$2 == SymbolType.scatter || preset.$2 == SymbolType.bonus) {
                          selectedContexts.add('trigger');
                        } else if (preset.$2 == SymbolType.collector) {
                          selectedContexts.addAll({'lock', 'collect'});
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: preset.$4.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: preset.$4.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(preset.$3, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(preset.$1, style: TextStyle(color: preset.$4, fontSize: 10)),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),
                  // Name field
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Symbol Name',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF4A9EFF)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Emoji picker
                  const Text('Emoji', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        // Current selection + text field
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selectedType.defaultColor.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                emojiController.text,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: emojiController,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'Type or pick below',
                                  hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Emoji grid
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: emojiOptions.map((e) => GestureDetector(
                            onTap: () => setDialogState(() => emojiController.text = e),
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: emojiController.text == e
                                    ? const Color(0xFF4A9EFF).withOpacity(0.3)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(e, style: const TextStyle(fontSize: 16)),
                            ),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Symbol type dropdown
                  const Text('Type', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButton<SymbolType>(
                      value: selectedType,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1A22),
                      underline: const SizedBox(),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: [
                        SymbolType.wild,
                        SymbolType.scatter,
                        SymbolType.bonus,
                        SymbolType.highPay,
                        SymbolType.mediumPay,
                        SymbolType.lowPay,
                        SymbolType.multiplier,
                        SymbolType.collector,
                        SymbolType.mystery,
                        SymbolType.custom,
                      ].map((t) => DropdownMenuItem(
                        value: t,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: t.defaultColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(t.displayName),
                          ],
                        ),
                      )).toList(),
                      onChanged: (v) => setDialogState(() {
                        selectedType = v!;
                        // Update emoji to match type default if not custom set
                        if (emojiController.text == '🎰') {
                          emojiController.text = v.defaultEmoji;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Audio contexts
                  const Text('Audio Contexts', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: contextOptions.map((ctx) {
                      final isSelected = selectedContexts.contains(ctx);
                      return FilterChip(
                        label: Text(ctx, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 10)),
                        selected: isSelected,
                        selectedColor: const Color(0xFF4A9EFF),
                        backgroundColor: const Color(0xFF242430),
                        onSelected: (sel) => setDialogState(() {
                          if (sel) selectedContexts.add(ctx);
                          else selectedContexts.remove(ctx);
                        }),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                // Generate ID from name
                final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
                // Check for duplicate ID
                final provider = Provider.of<SlotLabProjectProvider>(this.context, listen: false);
                if (provider.getSymbolById(id) != null) {
                  showToast('Symbol with ID "$id" already exists', type: ToastType.warning);
                  return;
                }
                final symbol = SymbolDefinition(
                  id: id,
                  name: name,
                  emoji: emojiController.text.trim().isNotEmpty ? emojiController.text.trim() : selectedType.defaultEmoji,
                  type: selectedType,
                  contexts: selectedContexts.toList(),
                  sortOrder: provider.symbols.length,
                );
                // Add to provider
                provider.addSymbol(symbol);
                Navigator.pop(ctx);

                // Show confirmation
                showToast('Added symbol: ${symbol.emoji} ${symbol.name}');
              },
              child: const Text('Add Symbol', style: TextStyle(color: Color(0xFF4A9EFF))),
            ),
          ],
        ),
      ),
    );
  }

  /// Show dialog to add a new game context (music layer)
  void _showAddContextDialog() {
    final nameController = TextEditingController();

    // Context type options with icons
    final contextTypeOptions = <(String, ContextType, String, Color)>[
      ('Base Game', ContextType.base, '🎰', const Color(0xFF4A9EFF)),
      ('Free Spins', ContextType.freeSpins, '🎁', const Color(0xFF40FF90)),
      ('Hold & Win', ContextType.holdWin, '🔒', const Color(0xFFFF9040)),
      ('Bonus', ContextType.bonus, '🎯', const Color(0xFFFF40FF)),
      ('Big Win', ContextType.bigWin, '🏆', const Color(0xFFF1C40F)),
      ('Cascade', ContextType.cascade, '💫', const Color(0xFF40C8FF)),
      ('Jackpot', ContextType.jackpot, '💎', const Color(0xFFFFD700)),
      ('Gamble', ContextType.gamble, '🎲', const Color(0xFFE91E63)),
    ];

    // Icon options for custom selection
    final iconOptions = ['🎰', '🎁', '🔒', '🎯', '🏆', '💫', '💎', '🎲', '🎵', '🎶', '🔔', '⭐'];

    ContextType selectedType = ContextType.freeSpins;
    String selectedIcon = '🎁';
    int layerCount = 5;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A22),
          title: const Text(
            'Add Context (Game Chapter)',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Presets
                const Text('Quick Presets', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: contextTypeOptions.map((preset) => GestureDetector(
                    onTap: () => setDialogState(() {
                      nameController.text = preset.$1;
                      selectedType = preset.$2;
                      selectedIcon = preset.$3;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: preset.$4.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: preset.$4.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(preset.$3, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(preset.$1, style: TextStyle(color: preset.$4, fontSize: 10)),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),

                // Name field
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4A9EFF)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),

                // Context Type dropdown
                const Text('Context Type', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<ContextType>(
                    value: selectedType,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1A1A22),
                    underline: const SizedBox(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    items: ContextType.values.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(_contextTypeName(type)),
                    )).toList(),
                    onChanged: (type) {
                      if (type != null) {
                        setDialogState(() => selectedType = type);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Icon picker
                const Text('Icon', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: iconOptions.map((icon) => GestureDetector(
                    onTap: () => setDialogState(() => selectedIcon = icon),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selectedIcon == icon
                            ? FluxForgeTheme.accentBlue.withOpacity(0.3)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selectedIcon == icon ? FluxForgeTheme.accentBlue : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(child: Text(icon, style: const TextStyle(fontSize: 16))),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),

                // Layer count
                Row(
                  children: [
                    const Text('Music Layers: ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => setDialogState(() => layerCount = (layerCount - 1).clamp(1, 8)),
                    ),
                    Text('$layerCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => setDialogState(() => layerCount = (layerCount + 1).clamp(1, 8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                // Generate ID from name
                final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
                final contextDef = ContextDefinition(
                  id: id,
                  displayName: name,
                  icon: selectedIcon,
                  type: selectedType,
                  layerCount: layerCount,
                );
                // Add to provider
                final provider = Provider.of<SlotLabProjectProvider>(this.context, listen: false);
                provider.addContext(contextDef);
                Navigator.pop(ctx);
              },
              child: const Text('Add', style: TextStyle(color: Color(0xFF4A9EFF))),
            ),
          ],
        ),
      ),
    );
  }

  String _contextTypeName(ContextType type) {
    switch (type) {
      case ContextType.base: return 'Base Game';
      case ContextType.freeSpins: return 'Free Spins';
      case ContextType.holdWin: return 'Hold & Win';
      case ContextType.bonus: return 'Bonus';
      case ContextType.bigWin: return 'Big Win';
      case ContextType.cascade: return 'Cascade';
      case ContextType.jackpot: return 'Jackpot';
      case ContextType.gamble: return 'Gamble';
    }
  }

  /// Reset confirmation dialog for edit mode
  void _showResetEventsConfirmation(MiddlewareProvider middleware, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text(
          'Reset All Events?',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          'This will remove $count event${count > 1 ? 's' : ''} created in this session. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Clear all composite events from MiddlewareProvider
              for (final event in [...middleware.compositeEvents]) {
                middleware.deleteCompositeEvent(event.id);
              }
              // Also clear from EventRegistry (unregister each event)
              for (final event in [...eventRegistry.allEvents]) {
                eventRegistry.unregisterEvent(event.id);
              }
              setState(() {});
            },
            child: const Text('Reset All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Separate scroll controllers for synchronized scrolling
  final ScrollController _headersScrollController = ScrollController();
  final ScrollController _timelineScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController(); // For horizontal timeline pan
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
    // P14: Use ULTIMATE TIMELINE (professional DAW-style)
    return LayoutBuilder(
      builder: (context, constraints) {
        // DUAL MODE: Legacy timeline for backward compatibility, Ultimate for new workflow
        // P14: Ultimate Timeline is now the only mode (legacy removed)
        return _buildUltimateTimelineMode(constraints);
      },
    );
  }

  /// P14: Ultimate Timeline Mode (NEW — Professional DAW-style)
  Widget _buildUltimateTimelineMode(BoxConstraints constraints) {
    return Consumer<SlotLabProvider>(
      builder: (context, slotLabProvider, _) {
        // Sync stage markers from SlotLabProvider
        _syncStageMarkersToUltimateTimeline(slotLabProvider);

        // Migrate existing tracks/regions to Ultimate Timeline (one-time)
        _migrateTracksToUltimateTimeline();

        // Wrap in DragTarget for audio browser drops
        return DragTarget<Object>(
          onAcceptWithDetails: (details) {
            if (details.data is String) {
              _handleAudioDropToUltimateTimeline(details.data as String, details.offset);
            } else if (details.data is List<String>) {
              // Multi-file drop
              for (final path in details.data as List<String>) {
                _handleAudioDropToUltimateTimeline(path, details.offset);
              }
            }
          },
          onWillAcceptWithDetails: (details) => details.data is String || details.data is List<String>,
          builder: (context, candidateData, rejectedData) {
            return UltimateTimeline(
              height: constraints.maxHeight,
              controller: _ultimateTimelineController,
            );
          },
        );
      },
    );
  }

  /// Migrate existing _tracks to Ultimate Timeline format (one-time)
  void _migrateTracksToUltimateTimeline() {
    if (_ultimateTimelineController == null) return;
    if (_ultimateTimelineController!.state.tracks.isNotEmpty) return; // Already migrated

    // Convert each _SlotAudioTrack to TimelineTrack
    for (int i = 0; i < _tracks.length; i++) {
      final oldTrack = _tracks[i];

      // Create track in Ultimate Timeline
      _ultimateTimelineController!.addTrack(name: oldTrack.name);

      final newTrack = _ultimateTimelineController!.state.tracks.last;

      // Migrate regions
      for (final oldRegion in oldTrack.regions) {
        // Convert _AudioRegion to timeline's AudioRegion
        final newRegion = timeline_models.AudioRegion(
          id: oldRegion.id,
          trackId: newTrack.id,
          audioPath: oldRegion.audioPath ?? '',
          startTime: oldRegion.start,
          duration: oldRegion.end - oldRegion.start,
          volume: 1.0, // Default
          pan: 0.0,    // Default
        );

        _ultimateTimelineController!.addRegion(newTrack.id, newRegion);

        // Load waveform asynchronously
        if (oldRegion.audioPath != null) {
          _ultimateTimelineController!.loadWaveformForRegion(
            newTrack.id,
            newRegion.id,
            generateWaveformFn: (path, key) async {
              final json = _ffi.generateWaveformFromFile(path, key);
              return json ?? ''; // Return empty string if null
            },
          );
        }
      }
    }

  }

  /// Handle audio drop to Ultimate Timeline
  void _handleAudioDropToUltimateTimeline(String audioPath, Offset globalPosition) {
    if (_ultimateTimelineController == null) return;

    // Get or create first track
    var track = _ultimateTimelineController!.state.tracks.firstOrNull;
    if (track == null) {
      _ultimateTimelineController!.addTrack(name: 'Audio Track 1');
      track = _ultimateTimelineController!.state.tracks.first;
    }

    // Calculate drop position in seconds (account for ruler + track header)
    final state = _ultimateTimelineController!.state;
    final canvasWidth = 1000.0 * state.zoom;
    final dropX = globalPosition.dx - 120; // Track header width
    final dropTime = (dropX / canvasWidth) * state.totalDuration;

    // Create region
    final region = timeline_models.AudioRegion(
      id: 'region_${DateTime.now().millisecondsSinceEpoch}',
      trackId: track.id,
      audioPath: audioPath,
      startTime: dropTime.clamp(0.0, state.totalDuration),
      duration: 2.0, // Placeholder (will be updated from FFI)
      volume: 1.0,
      pan: 0.0,
    );

    _ultimateTimelineController!.addRegion(track.id, region);

    // Load waveform + get real duration
    _loadWaveformAndDuration(track.id, region);

  }

  /// Load waveform and update region duration
  Future<void> _loadWaveformAndDuration(String trackId, timeline_models.AudioRegion region) async {
    try {
      // Get real audio duration from FFI
      final durationSeconds = _ffi.offlineGetAudioDuration(region.audioPath);
      final realDuration = durationSeconds > 0 ? durationSeconds : 2.0;

      // Update region with real duration
      final updatedRegion = region.copyWith(duration: realDuration);
      _ultimateTimelineController!.updateRegion(trackId, region.id, updatedRegion);

      // Load waveform
      await _ultimateTimelineController!.loadWaveformForRegion(
        trackId,
        region.id,
        generateWaveformFn: (path, key) async {
          final json = _ffi.generateWaveformFromFile(path, key);
          return json ?? '';
        },
      );
    } catch (e) { /* ignored */ }
  }

  /// Sync stage markers from SlotLabProvider to Ultimate Timeline
  void _syncStageMarkersToUltimateTimeline(SlotLabProvider provider) {
    if (_ultimateTimelineController == null) return;

    final stages = provider.lastStages;
    if (stages.isEmpty) return;

    // Clear existing markers
    final currentMarkers = _ultimateTimelineController!.state.markers;
    if (currentMarkers.length > 100) {
      // Prevent marker overflow — clear old markers
      for (final marker in currentMarkers.take(currentMarkers.length - 50)) {
        _ultimateTimelineController!.removeMarker(marker.id);
      }
    }

    // Add markers from stage events
    for (final stage in stages) {
      final timeSeconds = stage.timestampMs / 1000.0; // Convert ms to seconds

      // Use timeline_models.StageMarker (to avoid conflict with old _StageMarker)
      final marker = timeline_models.StageMarker.fromStageId(
        stage.stageType,
        timeSeconds,
      );

      _ultimateTimelineController!.addMarker(marker);
    }

    // P5: Add Win Tier boundaries if configured
    _syncWinTierBoundariesToTimeline();
  }

  /// P5: Sync Win Tier boundaries to timeline as visual markers
  void _syncWinTierBoundariesToTimeline() {
    if (_ultimateTimelineController == null) return;

    final projectProvider = context.read<SlotLabProjectProvider>();
    final winConfig = projectProvider.winConfiguration;

    // Add regular win tier boundaries
    for (final tier in winConfig.regularWins.tiers) {
      final marker = timeline_models.StageMarker(
        id: 'win_tier_${tier.tierId}',
        stageId: tier.stageName,
        timeSeconds: 0.0, // Tier boundaries are vertical lines at time=0 (visual reference)
        type: timeline_models.StageMarkerType.win,
        label: tier.displayLabel,
        color: const Color(0xFFFFD700).withOpacity(0.5),
      );

      // Only add if not already present
      final exists = _ultimateTimelineController!.state.markers.any((m) => m.id == marker.id);
      if (!exists) {
        _ultimateTimelineController!.addMarker(marker);
      }
    }

    // Add big win tier boundaries
    for (final tier in winConfig.bigWins.tiers) {
      final marker = timeline_models.StageMarker(
        id: 'big_win_tier_${tier.tierId}',
        stageId: tier.stageName,
        timeSeconds: 0.0,
        type: timeline_models.StageMarkerType.win,
        label: tier.displayLabel,
        color: const Color(0xFFFF9040).withOpacity(0.7),
      );

      final exists = _ultimateTimelineController!.state.markers.any((m) => m.id == marker.id);
      if (!exists) {
        _ultimateTimelineController!.addMarker(marker);
      }
    }
  }

  /// Legacy Timeline Mode (PRESERVED — old implementation)
  Widget _buildLegacyTimelineMode(BoxConstraints constraints) {
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
          builder: (context, legacyConstraints) {
            // Apply zoom to timeline width
            final zoomedWidth = constraints.maxWidth * _timelineZoom;

            // Mouse wheel: Ctrl + scroll = zoom, plain scroll = horizontal pan
            return Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  if (HardwareKeyboard.instance.isControlPressed) {
                    // Ctrl + scroll = zoom
                    final delta = event.scrollDelta.dy;
                    setState(() {
                      if (delta < 0) {
                        // Scroll up = zoom in
                        _timelineZoom = (_timelineZoom * 1.15).clamp(0.1, 10.0);
                      } else {
                        // Scroll down = zoom out
                        _timelineZoom = (_timelineZoom / 1.15).clamp(0.1, 10.0);
                      }
                    });
                  } else if (HardwareKeyboard.instance.isShiftPressed) {
                    // Shift + scroll = horizontal pan
                    if (_horizontalScrollController.hasClients) {
                      final newOffset = _horizontalScrollController.offset + event.scrollDelta.dy;
                      _horizontalScrollController.jumpTo(
                        newOffset.clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                      );
                    }
                  } else {
                    // Plain scroll = horizontal pan (natural for timeline)
                    if (_horizontalScrollController.hasClients) {
                      final newOffset = _horizontalScrollController.offset + event.scrollDelta.dy;
                      _horizontalScrollController.jumpTo(
                        newOffset.clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                      );
                    }
                  }
                }
              },
              child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // CRITICAL: Disable scroll physics so horizontal drag events pass through to layer GestureDetectors
              // Timeline scroll is handled via scroll wheel (without Ctrl) or programmatically
              physics: const NeverScrollableScrollPhysics(),
              controller: _horizontalScrollController,
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

                    // Snap-to-grid overlay (shows when snap is enabled)
                    TimelineGridOverlay(
                      pixelsPerSecond: zoomedWidth / _timelineDuration,
                      durationSeconds: _timelineDuration,
                      dragController: dragController,
                      height: constraints.maxHeight,
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
                              } catch (_) { /* ignored */ }
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
              ), // Close SingleChildScrollView
            ); // Close Listener
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
    // CRITICAL: Get layer count from EVENT (source of truth), NOT from region.layers
    // region.layers may be stale or not synced yet
    final event = _compositeEvents.where((e) => e.name == region.name).firstOrNull;
    final hasLayers = event != null && event.layers.isNotEmpty;
    // FIXED: Always expand if has layers - enables individual layer drag for all regions
    // This matches the logic in _buildAudioRegionVisual and ensures layers are always draggable
    final isExpanded = hasLayers;

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
      // FIXED: Allow expand for ANY region with layers (1+), not just 2+
      // This enables individual layer drag even for single-layer events
      onDoubleTap: hasLayers
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
    // CRITICAL: Don't update region bounds if ANY layer is being dragged
    // Otherwise, moving one layer causes region.start to shift, which resets
    // the layer's relative offset calculation and causes "snapping" behavior
    // ═══════════════════════════════════════════════════════════════════════════
    if (event != null && event.layers.isNotEmpty) {
      // Check if any layer in this event is currently being dragged
      final anyLayerDragging = event.layers.any((l) =>
          _dragController?.isDraggingLayer(l.id) ?? false);

      // Only update region bounds if not dragging region AND no layer is being dragged
      if (_draggingRegion != region && !anyLayerDragging) {
        final minOffsetMs = event.layers.map((l) => l.offsetMs).reduce((a, b) => a < b ? a : b);
        final regionStartFromProvider = minOffsetMs / 1000.0;
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
      // Use provider's durationSeconds if available (more reliable than FFI call)
      final layerDuration = el.durationSeconds ?? _getAudioDuration(el.audioPath);

      final existingLayer = region.layers.firstWhere(
        (rl) => rl.eventLayerId == el.id, // ✅ Use unique eventLayerId, not audioPath
        orElse: () => _RegionLayer(
          id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
          eventLayerId: el.id, // ✅ Store eventLayerId for future matching
          audioPath: el.audioPath,
          name: el.name,
          duration: layerDuration,
        ),
      );

      // Update duration ONLY if current is the default fallback (1.0) and we have a better value
      // This prevents waveform size changes during drag/rebuild
      // Once we get a real duration (> 1.0 or from provider), we keep it
      if (existingLayer.duration <= 1.01 && layerDuration > 1.01) {
        existingLayer.duration = layerDuration;
      }

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
    // FIXED: Always expand if has layers - enables drag for all regions
    // This ensures layers are always draggable without requiring manual double-tap
    final isExpanded = hasLayers;

    if (isExpanded) {
      // EXPANDED: No border, layers are shown as free-floating draggable tracks
      // Works for 1+ layers - all can be individually positioned
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

  /// Build a draggable layer row - DAW-style with proper width and ghost preview
  /// Uses layer.duration for REAL audio file width (not clamped to region)
  ///
  /// ARCHITECTURE — ISOLATED StatefulWidget for drag (like DAW ClipWidget)
  /// - DraggableLayerWidget has its own State, so setState is LOCAL
  /// - Parent widget is NOT rebuilt during drag
  /// - onDragEnd callback notifies parent with final offset
  Widget _buildDraggableLayerRow(_RegionLayer layer, _AudioRegion region, int layerIndex, Color color, bool muted, double regionWidth) {
    final layerId = layer.eventLayerId ?? '';

    // Resolve parent event ID
    String parentEventId = region.eventId ?? '';
    if (parentEventId.isEmpty) {
      for (final entry in _eventToRegionMap.entries) {
        if (entry.value == region.id) {
          parentEventId = entry.key;
          region.eventId = parentEventId;
          break;
        }
      }
    }

    SlotCompositeEvent? parentEvent;
    if (parentEventId.isNotEmpty) {
      parentEvent = _middleware.getCompositeEvent(parentEventId);
    }
    parentEvent ??= _compositeEvents.where((e) => e.name == region.name).firstOrNull;

    // CRITICAL FIX: If parentEvent was found by name, update parentEventId!
    if (parentEvent != null) {
      if (parentEventId.isEmpty) {
        parentEventId = parentEvent.id;
      }
      if (region.eventId == null || region.eventId!.isEmpty) {
        region.eventId = parentEvent.id;
      }
    }

    final eventLayer = parentEvent?.layers.where((l) => l.id == layerId).firstOrNull;
    final realDuration = eventLayer?.durationSeconds ?? layer.duration;
    final currentOffsetMs = eventLayer?.offsetMs ?? 0.0;


    // Use ISOLATED DraggableLayerWidget — setState in it doesn't affect THIS widget
    return DraggableLayerWidget(
      key: ValueKey('drag_layer_$layerId'),
      layerId: layerId,
      eventId: parentEventId,
      regionId: region.id,
      initialOffsetMs: currentOffsetMs,
      regionStart: region.start,
      regionDuration: region.duration,
      layerDuration: realDuration,
      regionWidth: regionWidth,
      color: color,
      muted: muted,
      layerName: layer.name,
      waveformData: _getWaveformForPath(layer.audioPath),
      onDragStart: (lid, eid, startOffsetMs) {
        // CRITICAL: Notify drag controller so region.start doesn't update during drag
        _dragController?.startLayerDrag(
          layerEventId: lid,
          parentEventId: eid,
          regionId: region.id,
          absoluteOffsetSeconds: startOffsetMs / 1000.0,
          regionDuration: region.duration,
          layerDuration: realDuration,
        );
        // Auto-select event so Middleware parameter strip shows the offset
        _middleware.selectCompositeEvent(eid);
      },
      getFreshOffset: (lid, eid) {
        // Callback to get fresh offset from provider
        final event = _middleware.getCompositeEvent(eid);
        final l = event?.layers.where((x) => x.id == lid).firstOrNull;
        final offset = l?.offsetMs ?? 0.0;
        return offset;
      },
      onDragEnd: (lid, eid, finalOffsetMs) {
        // Callback when drag completes — commit to provider
        _middleware.setLayerOffset(eid, lid, finalOffsetMs);
        // End drag in controller
        _dragController?.endLayerDrag();
      },
      onDelete: () => _deleteLayerFromTimeline(region, layer),
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
  ///
  /// CRITICAL: Uses generateWaveformFromFile instead of importAudio to avoid
  /// corrupting DAW waveforms. importAudio modifies Rust engine clip state,
  /// which can overwrite waveform data for clips already loaded in DAW.
  void _loadWaveformAsync(String audioPath) async {
    if (_waveformCache.containsKey(audioPath) || !_ffi.isLoaded) return;

    // First check disk cache before doing expensive FFI generation
    try {
      final diskWaveform = await WaveformCacheService.instance.get(audioPath);
      if (diskWaveform != null && diskWaveform.isNotEmpty) {
        _waveformCache[audioPath] = diskWaveform;
        if (mounted) setState(() {});
        return;
      }
    } catch (_) {
      // Disk cache miss, continue with FFI generation
    }

    try {
      // Generate waveform directly from file WITHOUT importing to engine
      // This prevents corruption of DAW clips that use the same audio file
      final cacheKey = 'slotlab_${audioPath.hashCode}';
      final waveformJson = _ffi.generateWaveformFromFile(audioPath, cacheKey);

      if (waveformJson != null && waveformJson.isNotEmpty) {
        // Parse JSON to extract min/max peaks
        final waveform = _parseWaveformJson(waveformJson);
        if (waveform != null && waveform.isNotEmpty) {
          // Cache in memory and disk
          _cacheWaveform(audioPath, waveform);
          // Trigger rebuild to show waveform
          if (mounted) setState(() {});
        }
      }
    } catch (e) { /* ignored */ }
  }

  /// Parse waveform JSON from generateWaveformFromFile into List of double peaks
  List<double>? _parseWaveformJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final lodLevels = data['lod_levels'] as List<dynamic>?;
      if (lodLevels == null || lodLevels.isEmpty) return null;

      // Use first LOD level (highest detail)
      final lod0 = lodLevels[0] as Map<String, dynamic>;
      final leftChannel = lod0['left'] as List<dynamic>?;
      if (leftChannel == null || leftChannel.isEmpty) return null;

      // Extract min/max pairs
      final result = <double>[];
      for (final bucket in leftChannel) {
        final bucketMap = bucket as Map<String, dynamic>;
        result.add((bucketMap['min'] as num).toDouble());
        result.add((bucketMap['max'] as num).toDouble());
      }
      return result;
    } catch (e) {
      return null;
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
    // CRITICAL: Use SlotLab track ID offset (100000+) to avoid collision with DAW tracks
    int ffiClipId = 0;
    final track = _tracks[trackIndex];
    if (track.id.startsWith('ffi_') && audioPath.isNotEmpty) {
      try {
        final localTrackId = int.parse(track.id.substring(4));
        final slotLabTrackId = slotLabTrackIdToFfi(localTrackId);

        // Use importAudio to actually load the audio file into the engine
        // Start at 0 (beginning of timeline)
        ffiClipId = _ffi.importAudio(
          audioPath,
          slotLabTrackId,
          0.0, // Always start at beginning
        );
      } catch (e) { /* ignored */ }
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
      _draggingAudioPaths = null;
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
        return peaks;
      }
    } catch (e) { /* ignored */ }
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
          return duration;
        }
      }
    } catch (e) { /* ignored */ }
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
    } catch (e) { /* ignored */ }

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
          // CRITICAL: Use SlotLab track ID offset to avoid DAW collision
          final slotLabTrackId = slotLabTrackIdToFfi(ffiTrackId);

          // Use importAudio to actually load the audio file into the engine
          // Region always starts at 0 (beginning of timeline)
          ffiClipId = _ffi.importAudio(
            layer.audioPath,
            slotLabTrackId,
            layer.offsetMs, // startTime = delay offset from start
          );

          // Use first layer's clip for waveform
          if (primaryClipId == 0) {
            primaryClipId = ffiClipId;
          }
        } catch (e) { /* ignored */ }
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
      eventId: event.id, // CRITICAL: Store event ID for reliable lookup
    );


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
    } catch (e) { /* ignored */ }

    final newTrack = _SlotAudioTrack(
      id: ffiTrackId > 0 ? 'ffi_$ffiTrackId' : 'track_${_tracks.length + 1}',
      name: trackName,
      color: trackColor,
    );

    setState(() {
      _tracks.add(newTrack);
    });
  }

  /// Create a new track for a drop-created event (no setState - called from _rebuildRegionForEvent)
  void _createTrackForNewEvent(SlotCompositeEvent event) {
    // Use event color as track color
    final trackColor = event.color;

    // Create track in FFI engine for real audio playback
    int ffiTrackId = 0;
    try {
      ffiTrackId = _ffi.createTrack(event.name, trackColor.value, event.targetBusId ?? SlotBusIds.sfx);
    } catch (e) { /* ignored */ }

    final newTrack = _SlotAudioTrack(
      id: ffiTrackId > 0 ? 'ffi_$ffiTrackId' : 'track_${_tracks.length + 1}',
      name: event.name,
      color: trackColor,
      outputBusId: event.targetBusId ?? SlotBusIds.sfx,
    );

    // Add track directly (no setState - called from _rebuildRegionForEvent which may be in _onMiddlewareChanged)
    _tracks.add(newTrack);
    _selectedTrackIndex = _tracks.length - 1;
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
  // P2-12: RESPONSIVE PANEL TOGGLE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle left panel visibility (manual override)
  void _toggleLeftPanel() {
    setState(() {
      _leftPanelManuallyHidden = !_leftPanelManuallyHidden;
    });
  }

  /// Toggle right panel visibility (manual override)
  void _toggleRightPanel() {
    setState(() {
      _rightPanelManuallyHidden = !_rightPanelManuallyHidden;
    });
  }

  /// Check if left panel is currently visible (considering both auto and manual)
  bool _isLeftPanelVisible(double screenWidth) {
    if (_leftPanelManuallyHidden) return false;
    if (screenWidth < _breakpointHideBoth) return false;
    if (screenWidth < _breakpointHideLeft) return false;
    return true;
  }

  /// Check if right panel is currently visible (considering both auto and manual)
  bool _isRightPanelVisible(double screenWidth) {
    if (_rightPanelManuallyHidden) return false;
    if (screenWidth < _breakpointHideBoth) return false;
    if (screenWidth < _breakpointHideRight) return false;
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOCK SLOT VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMockSlot() {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(), // Required for clipBehavior
      child: PremiumSlotPreview(
        key: ValueKey('premium_slot_${_reelCount}x$_rowCount'),
        onExit: () {}, // Embedded mode - no fullscreen exit
        reels: _reelCount,
        rows: _rowCount,
        isFullscreen: false, // Embedded mode — SPACE handled by global handler
        // P5: Pass project provider for dynamic win tier configuration
        projectProvider: context.read<SlotLabProjectProvider>(),
      ),
    );
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

  /// Parse string outcome to ForcedOutcome enum
  ForcedOutcome _parseOutcome(String outcome) {
    switch (outcome.toLowerCase()) {
      case 'lose':
        return ForcedOutcome.lose;
      case 'smallwin':
      case 'small_win':
        return ForcedOutcome.smallWin;
      case 'mediumwin':
      case 'medium_win':
        return ForcedOutcome.mediumWin;
      case 'bigwin':
      case 'big_win':
        return ForcedOutcome.bigWin;
      case 'megawin':
      case 'mega_win':
        return ForcedOutcome.megaWin;
      case 'epicwin':
      case 'epic_win':
        return ForcedOutcome.epicWin;
      case 'ultrawin':
      case 'ultra_win':
        return ForcedOutcome.ultraWin;
      case 'freespins':
      case 'free_spins':
        return ForcedOutcome.freeSpins;
      case 'jackpotmini':
      case 'jackpot_mini':
        return ForcedOutcome.jackpotMini;
      case 'jackpotminor':
      case 'jackpot_minor':
        return ForcedOutcome.jackpotMinor;
      case 'jackpotmajor':
      case 'jackpot_major':
        return ForcedOutcome.jackpotMajor;
      case 'jackpotgrand':
      case 'jackpot_grand':
        return ForcedOutcome.jackpotGrand;
      case 'nearmiss':
      case 'near_miss':
        return ForcedOutcome.nearMiss;
      case 'cascade':
        return ForcedOutcome.cascade;
      default:
        return ForcedOutcome.lose;
    }
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
              // Rename event button
              InkWell(
                onTap: () => _showRenameEventDialog(event),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A9EFF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF4A9EFF)),
                ),
              ),
              const SizedBox(width: 4),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Container selector row
                _buildContainerSelector(event),
                const SizedBox(height: 8),
                // Layers (if not using container)
                if (!event.usesContainer)
                  event.layers.isEmpty
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
                        )
                else
                  // Show container info when using container
                  _buildContainerInfo(event),
              ],
            ),
          ),
      ],
    );
  }

  /// Container selector for event - allows choosing container type and ID
  Widget _buildContainerSelector(SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 12, color: Colors.purple.shade300),
              const SizedBox(width: 6),
              const Text(
                'Playback Mode',
                style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Mode toggle: Direct Layers vs Container
          Row(
            children: [
              _buildModeRadio(event, middleware, false, 'Direct Layers', Icons.layers),
              const SizedBox(width: 12),
              _buildModeRadio(event, middleware, true, 'Use Container', Icons.account_tree),
            ],
          ),
          // Container type and ID selectors (only if using container)
          if (event.containerType != ContainerType.none) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                // Container Type
                Expanded(
                  child: _buildContainerTypeDropdown(event, middleware),
                ),
                const SizedBox(width: 8),
                // Container ID
                Expanded(
                  child: _buildContainerIdDropdown(event, middleware),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeRadio(SlotCompositeEvent event, MiddlewareProvider middleware, bool useContainer, String label, IconData icon) {
    final isSelected = useContainer ? event.usesContainer : !event.usesContainer;
    return InkWell(
      onTap: () {
        if (useContainer) {
          // Switch to container mode - default to blend
          middleware.updateCompositeEvent(event.copyWith(
            containerType: ContainerType.blend,
          ));
        } else {
          // Switch to direct layers mode
          middleware.updateCompositeEvent(event.copyWith(
            containerType: ContainerType.none,
            containerId: null,
          ));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 12,
              color: isSelected ? Colors.purple.shade300 : Colors.white38,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 12, color: isSelected ? Colors.purple.shade300 : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.purple.shade300 : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContainerTypeDropdown(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: DropdownButton<ContainerType>(
        value: event.containerType == ContainerType.none ? ContainerType.blend : event.containerType,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF1A1A22),
        style: const TextStyle(color: Colors.white, fontSize: 10),
        items: [
          ContainerType.blend,
          ContainerType.random,
          ContainerType.sequence,
        ].map((type) {
          return DropdownMenuItem(
            value: type,
            child: Text(type.displayName, style: const TextStyle(fontSize: 10)),
          );
        }).toList(),
        onChanged: (type) {
          if (type != null) {
            middleware.updateCompositeEvent(event.copyWith(
              containerType: type,
              containerId: null, // Reset container ID when type changes
            ));
          }
        },
      ),
    );
  }

  Widget _buildContainerIdDropdown(SlotCompositeEvent event, MiddlewareProvider middleware) {
    // Get containers based on selected type
    List<({int id, String name})> containers = [];
    switch (event.containerType) {
      case ContainerType.blend:
        containers = middleware.blendContainers.map((c) => (id: c.id, name: c.name)).toList();
        break;
      case ContainerType.random:
        containers = middleware.randomContainers.map((c) => (id: c.id, name: c.name)).toList();
        break;
      case ContainerType.sequence:
        containers = middleware.sequenceContainers.map((c) => (id: c.id, name: c.name)).toList();
        break;
      case ContainerType.none:
        break;
    }

    if (containers.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E14),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: const Text(
          'No containers',
          style: TextStyle(color: Colors.orange, fontSize: 10),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: DropdownButton<int>(
        value: containers.any((c) => c.id == event.containerId) ? event.containerId : null,
        hint: const Text('Select...', style: TextStyle(color: Colors.white38, fontSize: 10)),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF1A1A22),
        style: const TextStyle(color: Colors.white, fontSize: 10),
        items: containers.map((c) {
          return DropdownMenuItem(
            value: c.id,
            child: Text(c.name, style: const TextStyle(fontSize: 10)),
          );
        }).toList(),
        onChanged: (id) {
          if (id != null) {
            middleware.updateCompositeEvent(event.copyWith(containerId: id));
          }
        },
      ),
    );
  }

  /// Show container info when event uses container instead of direct layers
  Widget _buildContainerInfo(SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();
    String containerName = 'Unknown';
    int childCount = 0;

    switch (event.containerType) {
      case ContainerType.blend:
        final container = middleware.blendContainers.where((c) => c.id == event.containerId).firstOrNull;
        if (container != null) {
          containerName = container.name;
          childCount = container.children.length;
        }
        break;
      case ContainerType.random:
        final container = middleware.randomContainers.where((c) => c.id == event.containerId).firstOrNull;
        if (container != null) {
          containerName = container.name;
          childCount = container.children.length;
        }
        break;
      case ContainerType.sequence:
        final container = middleware.sequenceContainers.where((c) => c.id == event.containerId).firstOrNull;
        if (container != null) {
          containerName = container.name;
          childCount = container.steps.length;
        }
        break;
      case ContainerType.none:
        break;
    }

    final typeColor = switch (event.containerType) {
      ContainerType.blend => Colors.purple,
      ContainerType.random => Colors.amber,
      ContainerType.sequence => Colors.teal,
      ContainerType.none => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: typeColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree, size: 14, color: typeColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  containerName,
                  style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${event.containerType.displayName} • $childCount ${event.containerType == ContainerType.sequence ? 'steps' : 'children'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ],
            ),
          ),
          // Open container editor button
          InkWell(
            onTap: () {
              // Navigate to Middleware section to edit container
              final containerTypeName = event.containerType.displayName;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Container "$containerName" is a $containerTypeName container'),
                  duration: const Duration(seconds: 4),
                  action: SnackBarAction(
                    label: 'OPEN IN MIDDLEWARE',
                    textColor: FluxForgeTheme.accentBlue,
                    onPressed: () {
                      // Exit SlotLab and go to Middleware (where container panels are)
                      widget.onClose();
                    },
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.open_in_new, size: 12, color: typeColor),
            ),
          ),
        ],
      ),
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
  /// CRITICAL: Also creates track if not exists (for drop-created events)
  void _rebuildRegionForEvent(SlotCompositeEvent event) {
    // Find track with matching name
    var trackIndex = _tracks.indexWhere((t) => t.name == event.name);

    // If no track exists for this event, CREATE ONE (drop-created events)
    if (trackIndex < 0) {
      _createTrackForNewEvent(event);
      trackIndex = _tracks.indexWhere((t) => t.name == event.name);
      if (trackIndex < 0) return; // Failed to create track
    }

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
          final localTid = int.parse(track.id.substring(4));
          // CRITICAL: Use SlotLab track ID offset to avoid DAW collision
          final slotLabTrackId = slotLabTrackIdToFfi(localTid);
          ffiClipId = _ffi.importAudio(el.audioPath, slotLabTrackId, 0.0);
        } catch (_) { /* ignored */ }
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
      isExpanded: false, // Start collapsed - user can double-tap to expand for individual layer drag
      eventId: event.id, // CRITICAL: Store event ID for reliable lookup
    );

    track.regions.add(newRegion);
    _eventToRegionMap[event.id] = newRegion.id;
  }

  /// Sync region layers to exactly match event layers (remove old, add missing, update offsets)
  void _syncRegionLayersToEvent(_AudioRegion region, SlotCompositeEvent event, _SlotAudioTrack track) {

    // Get event layer IDs for comparison (use ID, not audioPath - allows duplicates)
    final eventLayerIds = event.layers.map((l) => l.id).toSet();

    // Remove region layers whose eventLayerId no longer exists in event
    region.layers.removeWhere((rl) => rl.eventLayerId != null && !eventLayerIds.contains(rl.eventLayerId));

    // CRITICAL FIX: Update offsets for EXISTING layers (for drag sync)
    // Region offset is relative to region.start, so we need to convert from absolute offsetMs
    // NOTE: Only skip layers that are ACTIVELY being dragged, NOT layers that just finished
    // (the isDraggingLayer() includes _justEndedLayerId which was causing sync to be skipped)
    for (final regionLayer in region.layers) {
      if (regionLayer.eventLayerId != null) {
        // CRITICAL FIX: Only check _draggingLayerEventId directly, NOT isDraggingLayer()
        // isDraggingLayer() returns true for _justEndedLayerId (to prevent visual glitch)
        // but we NEED to sync the offset when drag ends, so only skip ACTIVE drags
        final isActivelyDragging = _dragController?.draggingLayerEventId == regionLayer.eventLayerId;

        if (isActivelyDragging) {
          continue; // Skip - drag controller manages this layer's position
        }

        final eventLayer = event.layers.where((el) => el.id == regionLayer.eventLayerId).firstOrNull;
        if (eventLayer != null) {
          // Convert absolute offsetMs to relative offset from region.start
          final absoluteOffsetSec = eventLayer.offsetMs / 1000.0;
          final relativeOffset = absoluteOffsetSec - region.start;
          regionLayer.offset = relativeOffset;
        }
      }
    }

    // Add missing layers from event (by eventLayerId, not audioPath)
    for (final eventLayer in event.layers) {
      final existsInRegion = region.layers.any((rl) => rl.eventLayerId == eventLayer.id);
      if (!existsInRegion) {
        // Import to FFI
        final layerDuration = _getAudioDuration(eventLayer.audioPath);
        int ffiClipId = 0;
        if (track.id.startsWith('ffi_')) {
          try {
            final localTrackId = int.parse(track.id.substring(4));
            // CRITICAL: Use SlotLab track ID offset to avoid DAW collision
            final slotLabTrackId = slotLabTrackIdToFfi(localTrackId);
            ffiClipId = _ffi.importAudio(eventLayer.audioPath, slotLabTrackId, 0.0);
          } catch (e) { /* ignored */ }
        }

        // Convert absolute offsetMs to relative offset from region.start
        final absoluteOffsetSec = eventLayer.offsetMs / 1000.0;
        final relativeOffset = absoluteOffsetSec - region.start;

        region.layers.add(_RegionLayer(
          id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}_${region.layers.length}',
          eventLayerId: eventLayer.id, // Track which event layer this maps to
          audioPath: eventLayer.audioPath,
          name: eventLayer.name,
          ffiClipId: ffiClipId > 0 ? ffiClipId : null,
          duration: layerDuration,
          offset: relativeOffset, // FIXED: Relative offset from region start
        ));
      }
    }

    // Update region duration based on layer durations and offsets
    // But only if no layer drag is active (prevents region bounds from changing mid-drag)
    final anyLayerDragging = event.layers.any((l) =>
        _dragController?.isDraggingLayer(l.id) ?? false);

    if (!anyLayerDragging) {
      double maxEnd = 1.0; // Minimum 1 second
      for (final l in region.layers) {
        final layerEnd = l.offset + l.duration;
        if (layerEnd > maxEnd) maxEnd = layerEnd;
      }
      region.end = region.start + maxEnd;
    }

    // NOTE: Don't auto-expand here - user controls expand state via double-tap
    // Auto-expand was causing unwanted behavior on every sync
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
          final localTrackId = int.parse(track.id.substring(4));
          // CRITICAL: Use SlotLab track ID offset to avoid DAW collision
          final slotLabTrackId = slotLabTrackIdToFfi(localTrackId);
          ffiClipId = _ffi.importAudio(eventLayer.audioPath, slotLabTrackId, 0.0);
        } catch (e) { /* ignored */ }
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
      isExpanded: regionLayers.isNotEmpty, // FIXED: Expand if any layers (allows single layer drag)
      eventId: event.id, // CRITICAL: Store event ID for reliable lookup
    );

    track.regions.add(newRegion);
    _eventToRegionMap[event.id] = newRegion.id;

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
        final localTrackId = int.parse(track.id.substring(4));
        // CRITICAL: Use SlotLab track ID offset to avoid DAW collision
        final slotLabTrackId = slotLabTrackIdToFfi(localTrackId);
        ffiClipId = _ffi.importAudio(audioPath, slotLabTrackId, 0.0);
      } catch (e) { /* ignored */ }
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
      eventId: event.id, // CRITICAL: Store event ID for reliable lookup
    );

    // Load waveform
    if (ffiClipId > 0) {
      newRegion.waveformData = _loadWaveformForClip(ffiClipId);
    }

    track.regions.add(newRegion);
    _eventToRegionMap[event.id] = newRegion.id;

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
          return;
        }

        // Get actual duration from FFI metadata
        final layerDuration = _getAudioDuration(audioPath);

        // Import audio to FFI for playback
        int ffiClipId = 0;
        if (track.id.startsWith('ffi_') && audioInfo['path'] != null) {
          try {
            final localTrackId = int.parse(track.id.substring(4));
            // CRITICAL: Use SlotLab track ID offset to avoid DAW collision
            final slotLabTrackId = slotLabTrackIdToFfi(localTrackId);
            ffiClipId = _ffi.importAudio(
              audioInfo['path'] as String,
              slotLabTrackId,
              0.0, // Start at beginning
            );
          } catch (e) { /* ignored */ }
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

        // Auto-expand to allow layer drag (even single layer)
        if (region.layers.isNotEmpty) {
          region.isExpanded = true;
        }

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
      }

      // Clear selection if this was selected
      if (_selectedEventId == eventId) {
        _selectedEventId = null;
      }
    });

    // Delete from Middleware (single source of truth) and EventRegistry
    _deleteMiddlewareEvent(eventId);

    // CRITICAL: Sync TrackBridge to remove orphaned clips immediately
    // _onMiddlewareChanged will also call this, but we need immediate sync
    // because _tracks is already updated above
    _syncLayersToTrackManager();

    _persistState();
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
    }

    _persistState();
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

      // Remove layer via MiddlewareProvider (single source of truth)
      _removeLayerFromMiddlewareEvent(middlewareEvent.id, layerToRemove.id);


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
    // _onMiddlewareChanged listener handles region rebuild and EventRegistry sync
    _removeLayerFromMiddlewareEvent(event.id, layer.id);
    _persistState();
  }

  /// Show rename dialog for event
  void _showRenameEventDialog(SlotCompositeEvent event) {
    final controller = TextEditingController(text: event.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('Rename Event', style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New name:', style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Enter new name...',
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
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != event.name) {
                  _renameEvent(event.id, newName);
                }
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Current stage: ${_getEventStage(event)}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
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
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != event.name) {
                _renameEvent(event.id, newName);
              }
              Navigator.pop(ctx);
            },
            child: Text('Rename', style: TextStyle(color: FluxForgeTheme.accentBlue)),
          ),
        ],
      ),
    );
  }

  /// Rename event in MiddlewareProvider and re-sync to EventRegistry
  void _renameEvent(String eventId, String newName) {
    // Rename in MiddlewareProvider (single source of truth)
    _middleware.renameCompositeEvent(eventId, newName);

    // Also rename the associated track if it exists
    final trackIndex = _tracks.indexWhere((t) => t.id == eventId || t.name == _findEventById(eventId)?.name);
    if (trackIndex >= 0) {
      setState(() {
        _tracks[trackIndex] = _SlotAudioTrack(
          id: _tracks[trackIndex].id,
          name: newName,
          color: _tracks[trackIndex].color,
          isMuted: _tracks[trackIndex].isMuted,
          isSolo: _tracks[trackIndex].isSolo,
        );
      });
    }

    // Re-sync to EventRegistry (will be handled by _onMiddlewareChanged)
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

    // Registruj u centralni Event Registry (use newEvent directly, not _findEventById)
    _syncEventToRegistry(newEvent);

    // Persist state (including audio pool) after creating event
    _persistState();
  }

  /// Sinhronizuj composite event sa centralnim Event Registry
  /// CRITICAL: Registers event under ALL triggerStages, not just the first one
  /// This allows one event to be triggered by multiple stages (e.g., SPIN_START and REEL_STOP)
  void _syncEventToRegistry(SlotCompositeEvent? event) {
    if (event == null) return;

    // Get all trigger stages (or derive from category if empty)
    // CRITICAL: Normalize to UPPERCASE — SlotLabProvider triggers with .toUpperCase()
    final stages = event.triggerStages.isNotEmpty
        ? event.triggerStages.map((s) => s.toUpperCase()).toList()
        : [_getEventStage(event).toUpperCase()];

    // Skip if no layers (nothing to play)
    if (event.layers.isEmpty) {
      return;
    }

    // Build base layers list once (including fadeIn/fadeOut/trim parameters)
    final layers = event.layers.map((l) => AudioLayer(
      id: l.id,
      audioPath: l.audioPath,
      name: l.name,
      volume: l.volume,
      pan: l.pan,
      delay: l.offsetMs,
      busId: l.busId ?? 2,
      fadeInMs: l.fadeInMs,
      fadeOutMs: l.fadeOutMs,
      trimStartMs: l.trimStartMs,
      trimEndMs: l.trimEndMs,
    )).toList();

    // Register event under EACH trigger stage
    // Each registration uses a unique ID to avoid conflicts
    for (int i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final eventId = i == 0 ? event.id : '${event.id}_stage_$i';

      // Determine target bus from first layer (or default to SFX=2)
      final targetBus = layers.isNotEmpty ? layers.first.busId : 2;

      final audioEvent = AudioEvent(
        id: eventId,
        name: event.name,
        stage: stage,
        layers: layers,
        loop: event.looping,
        overlap: event.overlap,
        crossfadeMs: event.crossfadeMs,
        targetBusId: targetBus,
      );

      eventRegistry.registerEvent(audioEvent);
    }

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
  /// NOTE: Audio preloading moved to async background process for instant UI!
  void _syncAllEventsToRegistry() {
    for (final event in _compositeEvents) {
      _syncEventToRegistry(event);
      // NOTE: _syncEventToMiddleware removed - MiddlewareProvider is the source of truth
    }

    // Audio preload moved to _startBackgroundAudioPreload() for instant UI
    // Old synchronous preload was blocking UI for 1-3 seconds
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// CRITICAL FIX 2026-01-25: Re-register symbol audio to EventRegistry on mount
  /// Symbol audio events are NOT stored in MiddlewareProvider, so they are lost
  /// when the SlotLab screen remounts. This method re-registers them from
  /// SlotLabProjectProvider.symbolAudio which IS persisted.
  /// ═══════════════════════════════════════════════════════════════════════════
  void _syncSymbolAudioToRegistry() {
    try {
      final projectProvider = Provider.of<SlotLabProjectProvider>(context, listen: false);
      final symbolAudio = projectProvider.symbolAudio;

      if (symbolAudio.isEmpty) {
        return;
      }


      for (final assignment in symbolAudio) {
        // Find symbol definition for metadata
        final symbol = projectProvider.symbols.firstWhere(
          (s) => s.id == assignment.symbolId,
          orElse: () => defaultSymbols.first,
        );

        final stageName = assignment.stageName; // Uses correct format per context

        final audioEvent = AudioEvent(
          id: 'symbol_${assignment.symbolId}_${assignment.context}',
          name: '${symbol.name} ${assignment.context}',
          stage: stageName,
          layers: [
            AudioLayer(
              id: 'layer_${assignment.symbolId}_${assignment.context}',
              name: '${symbol.name} Audio',
              audioPath: assignment.audioPath,
              volume: assignment.volume,
              pan: assignment.pan,
              delay: 0.0,
              busId: 1, // SFX bus
            ),
          ],
        );

        eventRegistry.registerEvent(audioEvent);
      }
    } catch (e) { /* ignored */ }
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// CRITICAL FIX 2026-01-31: Re-register UltimateAudioPanel audio to EventRegistry
  /// Audio assignments from UltimateAudioPanel are stored in SlotLabProjectProvider
  /// but NOT in EventRegistry (which is singleton but can be cleared). This method
  /// re-registers all audio assignments on screen mount.
  /// ═══════════════════════════════════════════════════════════════════════════
  void _syncAudioAssignmentsToRegistry() {
    try {
      final projectProvider = Provider.of<SlotLabProjectProvider>(context, listen: false);
      final audioAssignments = projectProvider.audioAssignments;

      if (audioAssignments.isEmpty) {
        return;
      }


      for (final entry in audioAssignments.entries) {
        final stage = entry.key;
        final audioPath = entry.value;

        // CRITICAL: Check if stage should loop (GAME_START, MUSIC_*, etc.)
        final shouldLoop = StageConfigurationService.instance.isLooping(stage);
        final busId = _getBusForStage(stage);

        final audioEvent = AudioEvent(
          id: 'audio_$stage',
          name: stage.replaceAll('_', ' '),
          stage: stage,
          layers: [
            AudioLayer(
              id: 'layer_$stage',
              name: '${stage.replaceAll('_', ' ')} Audio',
              audioPath: audioPath,
              volume: 1.0,
              pan: _getPanForStage(stage),
              delay: 0.0,
              busId: busId,
            ),
          ],
          loop: shouldLoop,
          targetBusId: busId,
        );

        eventRegistry.registerEvent(audioEvent);
      }

    } catch (e) { /* ignored */ }
  }

  /// Handle audio dropped on stage from StageTraceWidget drag & drop
  /// Creates or updates an AudioEvent for the target stage
  void _onAudioDroppedOnStage(AudioFileInfo audio, String stageType) {

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
        loop: StageConfigurationService.instance.isLooping(normalizedStage),
        priority: _getPriorityForStage(normalizedStage),
      );

      eventRegistry.registerEvent(newEvent);
    }

    // Trigger visual feedback
    setState(() {});

    // Show confirmation
    if (mounted) {
      showToast(
        existingEvent != null
            ? 'Added "${audio.name}" to ${_formatEventName(normalizedStage)}'
            : 'Created event for $normalizedStage with "${audio.name}"',
        icon: Icons.check_circle,
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
  /// CRITICAL: Unregisters ALL stage-variants of this event from EventRegistry
  void _deleteEventFromAllSystems(String eventId, String eventName, String stage) {

    // Get event to find all trigger stages before deletion
    final event = _findEventById(eventId);
    final stageCount = event?.triggerStages.length ?? 1;

    // 1. Remove from EventRegistry (base event + all stage variants)
    eventRegistry.unregisterEvent(eventId);
    for (int i = 1; i < stageCount; i++) {
      eventRegistry.unregisterEvent('${eventId}_stage_$i');
    }

    // 2. Remove from MiddlewareProvider
    if (mounted) {
      try {
        final middleware = Provider.of<MiddlewareProvider>(context, listen: false);
        middleware.deleteCompositeEvent(eventId);
      } catch (e) { /* ignored */ }
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
        // Audio list — P0 PERFORMANCE: Fixed height + no per-frame setState
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: searchFiltered.length,
            itemExtent: 40, // P0 FIX: Fixed height for O(1) layout
            cacheExtent: 1000, // Pre-render 1000px for smooth scroll
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemBuilder: (context, index) {
              final audio = searchFiltered[index];
              return _buildAudioBrowserItemFast(audio);
            },
          ),
        ),
      ],
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// P0 PERFORMANCE: ULTRA-FAST AUDIO BROWSER ITEM
  /// - NO onDragUpdate setState (was causing per-frame rebuilds!)
  /// - NO WaveformThumbnail (too slow for large lists)
  /// - Fixed height for O(1) layout
  /// ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAudioBrowserItemFast(Map<String, dynamic> audio) {
    final path = audio['path'] as String;
    final name = audio['name'] as String;
    final duration = audio['duration'] as double? ?? 0.0;
    final isPlaying = _previewingAudioPath == path && _isPreviewPlaying;

    return Draggable<String>(
      data: path,
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
          child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ),
      onDragStarted: () {
        // P0 FIX: Only setState once at drag start
        setState(() => _draggingAudioPaths = [path]);
      },
      onDragEnd: (details) {
        // P0 FIX: Only setState once at drag end
        setState(() {
          _draggingAudioPaths = null;
          _dragPosition = null;
        });
      },
      // P0 FIX: REMOVED onDragUpdate — was causing 60fps setState rebuilds!
      child: Container(
        height: 36, // Fixed height
        padding: const EdgeInsets.symmetric(horizontal: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: isPlaying
              ? FluxForgeTheme.accentGreen.withOpacity(0.1)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isPlaying ? FluxForgeTheme.accentGreen : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Play/Stop button
            InkWell(
              onTap: () {
                if (isPlaying) {
                  _stopAudioPreview();
                } else {
                  _startAudioPreview(path);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isPlaying
                      ? FluxForgeTheme.accentGreen.withOpacity(0.2)
                      : Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 14,
                  color: isPlaying ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentBlue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Name
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isPlaying ? Colors.white : Colors.white70,
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // Duration badge
            if (duration > 0)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  '${duration.toStringAsFixed(1)}s',
                  style: const TextStyle(fontSize: 8, color: Colors.white38, fontFamily: 'monospace'),
                ),
              ),
            const SizedBox(width: 4),
            // Drag handle
            const Icon(Icons.drag_indicator, size: 12, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  // Legacy method kept for compatibility (will be removed in future)
  Widget _buildAudioBrowserItem(Map<String, dynamic> audio) {
    return _buildAudioBrowserItemFast(audio);
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
          // Tabs with horizontal scroll
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _BottomPanelTab.values.map((tab) {
                  final isSelected = _selectedBottomTab == tab;
                  final label = switch (tab) {
                    _BottomPanelTab.timeline => 'Timeline',
                    _BottomPanelTab.events => 'Events',
                    _BottomPanelTab.mixer => 'Mixer',
                    _BottomPanelTab.musicAle => 'Music/ALE',
                    _BottomPanelTab.meters => 'Meters',
                    _BottomPanelTab.debug => 'Debug',
                    _BottomPanelTab.engine => 'Engine',
                  };

                  return InkWell(
                    onTap: () => setState(() => _selectedBottomTab = tab),
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
                }).toList(),
              ),
            ),
          ),
          // [+] Menu button for additional panels
          _buildPlusMenuButton(),
        ],
      ),
    );
  }

  /// Plus menu button for additional panels (Game Config, AutoSpatial, etc.)
  Widget _buildPlusMenuButton() {
    return PopupMenuButton<_PlusMenuItem>(
      icon: const Icon(Icons.add, size: 16, color: Colors.white54),
      tooltip: 'More panels',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: const Color(0xFF1E1E26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _PlusMenuItem.gameConfig,
          child: Row(
            children: [
              Icon(Icons.settings_applications, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Game Config', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _PlusMenuItem.autoSpatial,
          child: Row(
            children: [
              Icon(Icons.surround_sound, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('AutoSpatial', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _PlusMenuItem.scenarios,
          child: Row(
            children: [
              Icon(Icons.theaters, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Scenarios', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _PlusMenuItem.commandBuilder,
          child: Row(
            children: [
              Icon(Icons.terminal, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Command Builder', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ],
      onSelected: _onPlusMenuItemSelected,
    );
  }

  /// Handle plus menu item selection — opens modal dialog
  void _onPlusMenuItemSelected(_PlusMenuItem item) {
    switch (item) {
      case _PlusMenuItem.gameConfig:
        _showGameConfigDialog();
      case _PlusMenuItem.autoSpatial:
        _showAutoSpatialDialog();
      case _PlusMenuItem.scenarios:
        _showScenariosDialog();
      case _PlusMenuItem.commandBuilder:
        _showCommandBuilderDialog();
    }
  }

  void _showGameConfigDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 800,
          height: 600,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D10),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.settings_applications, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Text('Game Config', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    // Game Model tab
                    Expanded(child: _buildGameModelContent()),
                    VerticalDivider(width: 1, color: Colors.white.withOpacity(0.1)),
                    // GDD Import tab
                    Expanded(child: _buildGddImportContent()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAutoSpatialDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 900,
          height: 650,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D10),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.surround_sound, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Text('AutoSpatial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Expanded(child: AutoSpatialPanel()),
            ],
          ),
        ),
      ),
    );
  }

  void _showScenariosDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 700,
          height: 500,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D10),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.theaters, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Text('Scenarios', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildScenariosContent()),
            ],
          ),
        ),
      ),
    );
  }

  void _showCommandBuilderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 700,
          height: 500,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D10),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Text('Command Builder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildCommandBuilderContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    // Use 50% of screen height for lower zone
    final screenHeight = MediaQuery.of(context).size.height;
    final panelHeight = screenHeight * 0.5;

    return Container(
      height: panelHeight,
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
      case _BottomPanelTab.events:
        return _buildEventsTabContent();
      case _BottomPanelTab.mixer:
        return _buildMixerTabContent();
      case _BottomPanelTab.musicAle:
        return _buildMusicAleTabContent();
      case _BottomPanelTab.meters:
        return _buildMetersContent();
      case _BottomPanelTab.debug:
        return _buildEventLogContent();
      case _BottomPanelTab.engine:
        return _buildEngineTabContent();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V6 MERGED TAB CONTENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Events Tab: Event list + RTPC bindings (merged)
  Widget _buildEventsTabContent() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            height: 28,
            color: const Color(0xFF16161C),
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: FluxForgeTheme.accentBlue,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              unselectedLabelStyle: TextStyle(fontSize: 10),
              tabs: [
                Tab(text: 'Events'),
                Tab(text: 'RTPC'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildEventListContent(),
                _buildRtpcContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mixer Tab: Bus hierarchy + Aux sends (merged)
  Widget _buildMixerTabContent() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            height: 28,
            color: const Color(0xFF16161C),
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: FluxForgeTheme.accentBlue,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              unselectedLabelStyle: TextStyle(fontSize: 10),
              tabs: [
                Tab(text: 'Buses'),
                Tab(text: 'Sends'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildBusHierarchyContent(),
                _buildAuxSendsContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Music/ALE Tab: ALE panel with rules, signals, transitions
  Widget _buildMusicAleTabContent() {
    // AlePanel uses context.read<AleProvider>() internally
    return const AlePanel();
  }

  /// Engine Tab: Profiler + Resources + Stage Ingest (merged)
  Widget _buildEngineTabContent() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            height: 28,
            color: const Color(0xFF16161C),
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: FluxForgeTheme.accentBlue,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              unselectedLabelStyle: TextStyle(fontSize: 10),
              tabs: [
                Tab(text: 'Profiler'),
                Tab(text: 'Resources'),
                Tab(text: 'Stage Ingest'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildProfilerContent(),
                _buildResourcesContent(),
                _buildStageIngestContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageIngestContent() {
    return Consumer<StageIngestProvider>(
      builder: (context, provider, _) => StageIngestPanel(
        onTraceSelected: (traceHandle) {
          // When a trace is selected, could trigger audio preview
        },
        onLiveEvent: (event) {
          // When live event arrives, trigger stage audio via global eventRegistry
          eventRegistry.triggerStage(event.stage);
        },
      ),
    );
  }

  Widget _buildEventLogContent() {
    final middleware = context.read<MiddlewareProvider>();
    return EventLogPanel(
      slotLabProvider: _slotLabProvider,
      middlewareProvider: middleware,
      height: _bottomPanelHeight - 8,
    );
  }

  Widget _buildTimelineTabContent() {
    // Full Audio Timeline (moved from center area)
    return _buildTimelineArea();
  }

  /// P0.3: Stage playback control bar (Pause/Resume/Stop)
  Widget _buildStagePlaybackControls() {
    final isPlaying = _slotLabProvider.isPlayingStages;
    final isPaused = _slotLabProvider.isPaused;
    final isActive = isPlaying || isPaused;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF1A1A22)
            : const Color(0xFF121216),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? const Color(0xFF4A9EFF).withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stage label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF4A9EFF).withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'STAGE',
              style: TextStyle(
                color: isActive ? const Color(0xFF4A9EFF) : Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Play/Pause toggle
          Tooltip(
            message: isPaused ? 'Resume (Space)' : (isPlaying ? 'Pause (Space)' : 'No active stages'),
            child: InkWell(
              onTap: isActive
                  ? () => _slotLabProvider.togglePauseResume()
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isPaused
                      ? const Color(0xFFFF9040).withOpacity(0.2)
                      : isPlaying
                          ? const Color(0xFF40FF90).withOpacity(0.2)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  isPaused ? Icons.play_arrow : Icons.pause,
                  size: 16,
                  color: isPaused
                      ? const Color(0xFFFF9040)
                      : isPlaying
                          ? const Color(0xFF40FF90)
                          : Colors.white24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Stop button
          Tooltip(
            message: 'Stop (Esc)',
            child: InkWell(
              onTap: isActive
                  ? () => _slotLabProvider.stopStagePlayback()
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.stop,
                  size: 16,
                  color: isActive ? const Color(0xFFFF4060) : Colors.white24,
                ),
              ),
            ),
          ),
          // Progress indicator (when playing)
          if (isPlaying && !isPaused) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF40FF90).withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${_slotLabProvider.currentStageIndex + 1}/${_slotLabProvider.lastStages.length}',
                style: const TextStyle(
                  color: Color(0xFF40FF90),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          // Paused indicator
          if (isPaused) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9040).withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pause, size: 10, color: Color(0xFFFF9040)),
                  const SizedBox(width: 3),
                  Text(
                    'PAUSED @ ${_slotLabProvider.currentStageIndex + 1}',
                    style: const TextStyle(
                      color: Color(0xFFFF9040),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        // Update provider (FFI sync)
        _slotLabProvider.updateGameModel(model);

        // Extract grid dimensions and sync to local settings
        final grid = model['grid'] as Map<String, dynamic>?;
        if (grid != null) {
          final newReels = grid['reels'] as int? ?? _slotLabSettings.reels;
          final newRows = grid['rows'] as int? ?? _slotLabSettings.rows;

          if (newReels != _slotLabSettings.reels || newRows != _slotLabSettings.rows) {
            setState(() {
              _slotLabSettings = _slotLabSettings.copyWith(
                reels: newReels,
                rows: newRows,
              );
            });
          }
        }
      },
      onClose: () => _lowerZoneController.setSuperTab(SlotLabSuperTab.stages),
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
      onClose: () => _lowerZoneController.setSuperTab(SlotLabSuperTab.stages),
    );
  }

  Widget _buildGddImportContent() {
    return GddImportPanel(
      onModelImported: (model) {
        // Model is already imported via FFI in the panel
        showToast('GDD imported: ${model['info']?['name'] ?? 'Unknown'}');
      },
      onClose: () => _lowerZoneController.setSuperTab(SlotLabSuperTab.stages),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOWER ZONE CONTENT BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCommandBuilderContent() {
    // CommandBuilderPanel uses MiddlewareProvider directly (no wrapper needed)
    return const CommandBuilderPanel();
  }

  Widget _buildEventListContent() {
    // EventListPanel uses MiddlewareProvider directly (no wrapper needed)
    return const EventListPanel();
  }

  Widget _buildMetersContent() {
    return const BusMetersPanel();
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

  /// Regenerate reel-specific stages when grid dimensions change (P0 WF-03)
  void _regenerateReelStages(int newReelCount) {
    final eventRegistry = EventRegistry.instance;

    // Clear old reel-specific events (REEL_STOP_0..old count)
    for (var i = 0; i < 10; i++) {
      // Clear up to 10 reels (max possible)
      eventRegistry.unregisterStage('REEL_STOP_$i');
      eventRegistry.unregisterStage('REEL_SPINNING_START_$i');
      eventRegistry.unregisterStage('REEL_SPINNING_STOP_$i');
    }


    // Note: New reel events will be created when audio is assigned
    // Pan law will be auto-calculated based on new reel count:
    //   pan = (reelIndex - (newReelCount / 2)) * 0.8 / (newReelCount / 2)
    //   Example for 6 reels: reel 0 = -0.8, reel 2.5 = 0.0, reel 5 = +0.8
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
