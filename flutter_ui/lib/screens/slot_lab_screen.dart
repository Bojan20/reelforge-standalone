// FluxForge Slot Lab - Fullscreen Slot Audio Sandbox
//
// Premium "casino-grade" UI for slot game audio design.
// Inspired by Wwise + FMOD but 100% focused on slot games.
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
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/middleware_provider.dart';
import '../providers/stage_provider.dart';
import '../providers/slot_lab_provider.dart';
import '../services/stage_audio_mapper.dart';
import '../models/stage_models.dart';
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
import '../widgets/slot_lab/event_log_panel.dart';
// audio_hover_preview.dart prepared for audio browser integration
import '../widgets/slot_lab/forced_outcome_panel.dart';
import '../src/rust/native_ffi.dart';
import '../services/event_registry.dart';

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
  final String audioPath;
  final String name;
  final int? ffiClipId;
  double volume;
  double delay;
  double offset; // Individual horizontal offset within region (in seconds)

  _RegionLayer({
    required this.id,
    required this.audioPath,
    required this.name,
    this.ffiClipId,
    this.volume = 1.0,
    this.delay = 0.0,
    this.offset = 0.0,
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

class _CompositeEvent {
  String id;
  String name;
  String stage;
  List<_CompositeLayer> layers;
  bool isExpanded;

  _CompositeEvent({
    required this.id,
    required this.name,
    required this.stage,
    List<_CompositeLayer>? layers,
    this.isExpanded = false,
  }) : layers = layers ?? [];
}

class _CompositeLayer {
  String id;
  String audioPath;
  String name;
  double volume;
  double pan;
  double delay;
  int busId;

  _CompositeLayer({
    required this.id,
    required this.audioPath,
    required this.name,
    this.volume = 1.0,
    this.pan = 0.0,
    this.delay = 0.0,
    this.busId = 2,
  });
}

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

  // FFI instance
  final _ffi = NativeFFI.instance;

  // Focus node for keyboard shortcuts
  final FocusNode _focusNode = FocusNode();

  // Game spec state
  int _reelCount = 5;
  int _rowCount = 3;
  VolatilityLevel _volatilityLevel = VolatilityLevel.medium;
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

  // Composite events
  final List<_CompositeEvent> _compositeEvents = [];
  String? _selectedEventId;

  // Bottom panel
  _BottomPanelTab _selectedBottomTab = _BottomPanelTab.timeline;
  double _bottomPanelHeight = 280.0;
  bool _bottomPanelCollapsed = false;

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
  double? _layerDragStartOffset;
  double? _layerDragDelta;

  // Event → Region mapping (for auto-update when layer added to event)
  final Map<String, String> _eventToRegionMap = {}; // eventId → regionId

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
  }

  /// Restore state from provider (survives screen switches)
  void _restorePersistedState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final provider = Provider.of<SlotLabProvider>(context, listen: false);

        // Restore audio pool
        if (provider.persistedAudioPool.isNotEmpty) {
          setState(() {
            _audioPool = List.from(provider.persistedAudioPool);
          });
        }

        // Restore composite events
        if (provider.persistedCompositeEvents.isNotEmpty) {
          setState(() {
            _compositeEvents.clear();
            for (final eventData in provider.persistedCompositeEvents) {
              _compositeEvents.add(_CompositeEvent(
                id: eventData['id'] as String,
                name: eventData['name'] as String,
                stage: eventData['stage'] as String,
                layers: (eventData['layers'] as List<dynamic>?)?.map((l) {
                  final layerData = l as Map<String, dynamic>;
                  return _CompositeLayer(
                    id: layerData['id'] as String,
                    audioPath: layerData['audioPath'] as String,
                    name: layerData['name'] as String,
                    volume: (layerData['volume'] as num?)?.toDouble() ?? 1.0,
                    pan: (layerData['pan'] as num?)?.toDouble() ?? 0.0,
                    delay: (layerData['delay'] as num?)?.toDouble() ?? 0.0,
                    busId: layerData['busId'] as int? ?? 0,
                  );
                }).toList(),
                isExpanded: eventData['isExpanded'] as bool? ?? false,
              ));
            }
          });
          // Re-sync to event registry
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
                        audioPath: layerData['audioPath'] as String,
                        name: layerData['name'] as String,
                        volume: (layerData['volume'] as num?)?.toDouble() ?? 1.0,
                        delay: (layerData['delay'] as num?)?.toDouble() ?? 0.0,
                        offset: (layerData['offset'] as num?)?.toDouble() ?? 0.0,
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

        debugPrint('[SlotLab] Restored persisted state');
      } catch (e) {
        debugPrint('[SlotLab] Error restoring state: $e');
      }
    });
  }

  /// Persist state to provider (survives screen switches)
  void _persistState() {
    try {
      final provider = Provider.of<SlotLabProvider>(context, listen: false);

      // Persist audio pool
      provider.persistedAudioPool = List.from(_audioPool);

      // Persist composite events
      provider.persistedCompositeEvents = _compositeEvents.map((event) => {
        'id': event.id,
        'name': event.name,
        'stage': event.stage,
        'isExpanded': event.isExpanded,
        'layers': event.layers.map((layer) => {
          'id': layer.id,
          'audioPath': layer.audioPath,
          'name': layer.name,
          'volume': layer.volume,
          'pan': layer.pan,
          'delay': layer.delay,
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
            'audioPath': layer.audioPath,
            'name': layer.name,
            'volume': layer.volume,
            'delay': layer.delay,
            'offset': layer.offset,
          }).toList(),
        }).toList(),
      }).toList();

      // Persist event to region mapping
      provider.persistedEventToRegionMap = Map.from(_eventToRegionMap);

      debugPrint('[SlotLab] Persisted state: ${_audioPool.length} audio, ${_compositeEvents.length} events, ${_tracks.length} tracks');
    } catch (e) {
      debugPrint('[SlotLab] Error persisting state: $e');
    }
  }

  void _initializeSlotEngine() {
    // Get or create SlotLabProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _slotLabProviderNullable = Provider.of<SlotLabProvider>(context, listen: false);

        // Initialize engine for audio testing mode
        _engineInitialized = _slotLabProvider.initialize(audioTestMode: true);

        if (_engineInitialized) {
          // Connect to middleware for audio triggering
          final middleware = Provider.of<MiddlewareProvider>(context, listen: false);
          _slotLabProvider.connectMiddleware(middleware);

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

    // No demo data - start empty, user imports audio files
    setState(() {
      _audioPool = [];
    });
  }

  @override
  void dispose() {
    // Persist state before disposing
    _persistState();

    // Remove slot lab listener
    if (_engineInitialized && _hasSlotLabProvider) {
      _slotLabProvider.removeListener(_onSlotLabUpdate);
    }
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

    return Focus(
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KEYBOARD SHORTCUTS
  // ═══════════════════════════════════════════════════════════════════════════

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    // Keys that allow repeat (hold key for continuous adjustment)
    final isZoomKey = key == LogicalKeyboardKey.keyG || key == LogicalKeyboardKey.keyH;
    final isArrowKey = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;

    // Accept KeyDownEvent and KeyRepeatEvent (for zoom and arrows)
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Only allow repeat for zoom and arrow keys
    if (event is KeyRepeatEvent && !isZoomKey && !isArrowKey) return KeyEventResult.ignored;

    // Space = Play/Stop (no repeat)
    if (key == LogicalKeyboardKey.space) {
      _togglePlayback();
      return KeyEventResult.handled;
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

    return KeyEventResult.ignored;
  }

  void _deleteSelectedRegions() {
    setState(() {
      for (final track in _tracks) {
        track.regions.removeWhere((r) => r.isSelected);
      }
    });
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

          const SizedBox(width: 8),
        ],
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
      // Clear triggered layers tracking for new playback
      _triggeredLayers.clear();
      _lastPlayheadPosition = _playheadPosition;

      // Check which layers should already be playing at current position
      _triggerLayersAtPosition(_playheadPosition);

      debugPrint('[SlotLab] Playback started at ${_playheadPosition}s');

      _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted || !_isPlaying) {
          timer.cancel();
          return;
        }
        setState(() {
          final prevPosition = _playheadPosition;
          _playheadPosition += 0.033;

          // Check and trigger any layers that playhead crossed
          _checkAndTriggerLayers(prevPosition, _playheadPosition);

          // Determine loop boundaries
          final loopEnd = (_isLooping && _loopEnd != null) ? _loopEnd! : _timelineDuration;
          final loopStart = (_isLooping && _loopStart != null) ? _loopStart! : 0.0;

          if (_playheadPosition >= loopEnd) {
            if (_isLooping) {
              _playheadPosition = loopStart;
              // Reset triggered layers for loop
              _triggeredLayers.clear();
              _triggerLayersAtPosition(loopStart);
            } else {
              _isPlaying = false;
              timer.cancel();
              _stopAllLayerAudio();
            }
          }
        });
      });
    } else {
      _playbackTimer?.cancel();
      // Stop all layer audio
      _stopAllLayerAudio();
      // Stop audio engine playback
      if (_ffi.isLoaded) {
        try {
          _ffi.stop();
        } catch (e) {
          debugPrint('[SlotLab] FFI stop error: $e');
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
    _stopAllLayerAudio();
  }

  /// Calculate the absolute start time of a layer on the timeline
  double _getLayerStartTime(_AudioRegion region, _RegionLayer layer) {
    return region.start + layer.offset;
  }

  /// Trigger layers that should be playing at the given position
  void _triggerLayersAtPosition(double position) {
    for (final track in _tracks) {
      if (track.isMuted) continue;

      for (final region in track.regions) {
        if (region.isMuted) continue;

        for (final layer in region.layers) {
          final layerStart = _getLayerStartTime(region, layer);
          final layerEnd = layerStart + region.duration;

          // If playhead is within this layer's time range
          if (position >= layerStart && position < layerEnd) {
            if (!_triggeredLayers.contains(layer.id)) {
              _triggeredLayers.add(layer.id);
              // Calculate offset into the audio file
              final audioOffset = position - layerStart;
              _playLayerAudio(layer, audioOffset);
            }
          }
        }
      }
    }
  }

  /// Check and trigger layers that the playhead crossed between prevPos and currentPos
  void _checkAndTriggerLayers(double prevPos, double currentPos) {
    for (final track in _tracks) {
      if (track.isMuted) continue;

      for (final region in track.regions) {
        if (region.isMuted) continue;

        for (final layer in region.layers) {
          final layerStart = _getLayerStartTime(region, layer);

          // If playhead crossed the layer start point
          if (prevPos < layerStart && currentPos >= layerStart) {
            if (!_triggeredLayers.contains(layer.id)) {
              _triggeredLayers.add(layer.id);
              _playLayerAudio(layer, 0.0); // Start from beginning
              debugPrint('[SlotLab] Triggered layer: ${layer.name} at ${layerStart}s');
            }
          }
        }
      }
    }
  }

  /// Play audio for a specific layer using Rust engine
  Future<void> _playLayerAudio(_RegionLayer layer, double offsetSeconds) async {
    if (layer.audioPath.isEmpty) return;

    try {
      // Play via dedicated PreviewEngine (separate from main timeline)
      final voiceId = NativeFFI.instance.previewAudioFile(
        layer.audioPath,
        volume: layer.volume,
      );
      if (voiceId >= 0) {
        _activeLayerIds.add(layer.id);
      }

      debugPrint('[SlotLab] Playing ${layer.name} at offset ${offsetSeconds}s (voice $voiceId)');
    } catch (e) {
      debugPrint('[SlotLab] Error playing layer audio: $e');
    }
  }

  /// Stop all currently playing layer audio
  Future<void> _stopAllLayerAudio() async {
    try {
      NativeFFI.instance.previewStop();
      _activeLayerIds.clear();
    } catch (e) {
      debugPrint('[SlotLab] Error stopping audio: $e');
    }
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
    // Check if FFI is loaded
    if (!_ffi.isLoaded) {
      debugPrint('[SlotLab] FFI not loaded, cannot preview');
      return;
    }

    // Stop any existing preview first
    _stopAudioPreview();

    setState(() {
      _previewingAudioPath = path;
      _isPreviewPlaying = true;
    });

    try {
      // Find the audio info
      final audioInfo = _audioPool.firstWhere(
        (a) => a['path'] == path,
        orElse: () => {'path': path, 'name': path.split('/').last, 'duration': 1.0},
      );
      final duration = (audioInfo['duration'] as num?)?.toDouble() ?? 1.0;

      // Create preview track if not exists
      if (_previewTrackId == null || _previewTrackId == 0) {
        _previewTrackId = _ffi.createTrack('_preview', 0xFF808080, 2); // Hidden preview track
        debugPrint('[SlotLab] Created preview track: $_previewTrackId');
      }

      if (_previewTrackId != null && _previewTrackId! > 0) {
        // Import audio file and play
        _previewClipId = _ffi.importAudio(path, _previewTrackId!, 0.0);
        debugPrint('[SlotLab] Imported audio clip: $_previewClipId');

        if (_previewClipId != null && _previewClipId! > 0) {
          _ffi.seek(0.0);
          _ffi.play();
          debugPrint('[SlotLab] Playing preview: $path (${duration}s)');
        }
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

    final wasPlaying = _isPreviewPlaying;

    setState(() {
      _previewingAudioPath = null;
      _isPreviewPlaying = false;
    });

    try {
      // Stop playback if FFI is loaded
      if (_ffi.isLoaded && wasPlaying) {
        _ffi.stop();
      }

      // Delete the preview clip to clean up
      if (_previewClipId != null && _previewClipId! > 0) {
        _ffi.deleteClip(_previewClipId!);
        _previewClipId = null;
      }

      debugPrint('[SlotLab] Preview stopped');
    } catch (e) {
      debugPrint('[SlotLab] Stop preview error: $e');
    }
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
                          _volatilityLevel = level;
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
              // Playhead indicator on ruler
              Positioned(
                left: (_playheadPosition / _timelineDuration) * constraints.maxWidth - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: Colors.white,
                ),
              ),
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
        } else if (details.data is _CompositeEvent) {
          // Handle composite event drop on timeline
          _handleEventDrop(details.data as _CompositeEvent, details.offset);
        }
      },
      onWillAcceptWithDetails: (details) => details.data is String || details.data is _CompositeEvent,
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

                    // Playhead visual (IgnorePointer - just visual, no interaction)
                    IgnorePointer(
                      child: Positioned(
                        left: (_playheadPosition / _timelineDuration) * zoomedWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: Colors.white,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
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
        onTap: () => setState(() => region.isSelected = !region.isSelected),
        onDoubleTap: () => setState(() => region.isExpanded = false),
        onSecondaryTapDown: (details) => _showRegionContextMenu(details.globalPosition, region),
        child: _buildAudioRegionVisual(region, track.color, track.isMuted, regionWidth, trackHeight),
      );
    }

    // When collapsed, drag the whole region
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
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
          final newStart = (_regionDragStartX ?? region.start) + _regionDragOffsetX!;
          final clampedStart = newStart.clamp(0.0, _timelineDuration - duration);
          region.start = clampedStart;
          region.end = clampedStart + duration;
        });
      },
      onPanEnd: (details) {
        _clearRegionDrag();
      },
      onTap: () => setState(() => region.isSelected = !region.isSelected),
      onDoubleTap: region.layers.length > 1
          ? () => setState(() => region.isExpanded = !region.isExpanded)
          : null,
      onSecondaryTapDown: (details) => _showRegionContextMenu(details.globalPosition, region),
      child: _buildAudioRegionVisual(region, track.color, track.isMuted, regionWidth, trackHeight),
    );
  }

  void _clearRegionDrag() {
    setState(() {
      _draggingRegion = null;
      _draggingRegionTrackIndex = null;
      _regionDragStartX = null;
      _regionDragOffsetX = null;
    });
  }

  /// Calculate track height based on expanded regions
  /// Collapsed = single layer height, Expanded = all layers equal height
  double _getTrackHeight(_SlotAudioTrack track) {
    const singleLayerHeight = 36.0;  // Height for one layer
    const layerHeight = 28.0;  // Height per layer when expanded

    // Check if any region is expanded with multiple layers
    for (final region in track.regions) {
      if (region.isExpanded && region.layers.length > 1) {
        // Expanded: all layers equal height
        return region.layers.length * layerHeight;
      }
    }
    return singleLayerHeight;
  }

  /// Visual-only widget for audio region (no gestures - handled by parent for whole region drag)
  /// When expanded, each layer can be dragged individually across entire timeline
  Widget _buildAudioRegionVisual(_AudioRegion region, Color trackColor, bool muted, double regionWidth, double trackHeight) {
    final width = regionWidth.clamp(20.0, 4000.0);
    final hasLayers = region.layers.isNotEmpty;
    final layerCount = region.layers.length;
    final isExpanded = region.isExpanded && layerCount > 1;

    if (isExpanded) {
      // EXPANDED: No border, layers are shown as free-floating tracks
      return SizedBox(
        width: width,
        height: trackHeight,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: region.layers.asMap().entries.map((entry) {
            final index = entry.key;
            final layer = entry.value;
            return Expanded(
              child: _buildDraggableLayerRow(layer, region, index, region.color, muted, width),
            );
          }).toList(),
        ),
      );
    }

    // COLLAPSED: Normal region with border
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
        child: hasLayers
            ? _buildLayerRow(region.layers.first, region.color, muted, true, layerCount)
            : _buildEmptyRegionRow(region, muted),
      ),
    );
  }

  /// Build a draggable layer row - can be moved freely across entire timeline
  Widget _buildDraggableLayerRow(_RegionLayer layer, _AudioRegion region, int layerIndex, Color color, bool muted, double regionWidth) {
    final isDragging = _draggingLayer == layer;
    final pixelsPerSecond = regionWidth / region.duration;
    final offsetPixels = layer.offset * pixelsPerSecond;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) {
        setState(() {
          _draggingLayer = layer;
          _draggingLayerRegion = region;
          _layerDragStartOffset = layer.offset;
          _layerDragDelta = 0;
        });
      },
      onHorizontalDragUpdate: (details) {
        if (_draggingLayer != layer) return;
        final timeDelta = details.delta.dx / pixelsPerSecond;
        setState(() {
          _layerDragDelta = (_layerDragDelta ?? 0) + timeDelta;
          final newOffset = (_layerDragStartOffset ?? 0) + _layerDragDelta!;
          // No clamping - allow free movement across entire timeline
          // Limit only to prevent going before timeline start or after timeline end
          final minOffset = -region.start; // Can't go before 0
          final maxOffset = _timelineDuration - region.start - 0.1; // Can't go past end
          layer.offset = newOffset.clamp(minOffset, maxOffset);
        });
      },
      onHorizontalDragEnd: (details) {
        _clearLayerDrag();
      },
      child: MouseRegion(
        cursor: isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Layer content positioned with offset - each layer as mini-track
            Positioned(
              left: offsetPixels,
              top: 1,
              bottom: 1,
              width: regionWidth, // Fixed width, moves with offset
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

  void _clearLayerDrag() {
    setState(() {
      _draggingLayer = null;
      _draggingLayerRegion = null;
      _layerDragStartOffset = null;
      _layerDragDelta = null;
    });
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

  /// Get waveform data for an audio path from the pool or generate from FFI
  List<double>? _getWaveformForPath(String audioPath) {
    // First try to find in audio pool
    for (final item in _audioPool) {
      final path = item['path'] as String? ?? '';
      if (path == audioPath || path.endsWith(audioPath.split('/').last)) {
        final waveform = item['waveform'];
        if (waveform is List && waveform.isNotEmpty) {
          return waveform.map((e) => (e as num).toDouble()).toList();
        }
      }
    }

    // Try to find clip ID in existing regions and load from FFI
    for (final track in _tracks) {
      for (final region in track.regions) {
        for (final layer in region.layers) {
          if (layer.audioPath == audioPath && layer.ffiClipId != null && layer.ffiClipId! > 0) {
            return _loadWaveformForClip(layer.ffiClipId!);
          }
        }
      }
    }

    return null;
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

    final duration = (audioInfo['duration'] as num?)?.toDouble() ?? 1.0;
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
  List<double>? _loadWaveformForClip(int clipId) {
    if (clipId <= 0 || !_ffi.isLoaded) return null;
    try {
      final peaks = _ffi.getWaveformPeaks(clipId, maxPeaks: 200);
      if (peaks.isNotEmpty) {
        debugPrint('[SlotLab] Loaded waveform with ${peaks.length} peaks');
        return peaks;
      }
    } catch (e) {
      debugPrint('[SlotLab] Waveform load error: $e');
    }
    return null;
  }

  void _handleEventDrop(_CompositeEvent event, Offset globalPosition) {
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
            layer.delay, // startTime = delay offset from start
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
        id: ffiClipId > 0 ? 'ffi_$ffiClipId' : 'layer_${DateTime.now().millisecondsSinceEpoch}',
        audioPath: layer.audioPath,
        name: layer.name,
        ffiClipId: ffiClipId > 0 ? ffiClipId : null,
        volume: layer.volume,
        delay: layer.delay,
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

    setState(() {
      _tracks.add(newTrack);
      _tracks.last.regions.add(region);
      _selectedTrackIndex = _tracks.length - 1;
      // Map event to region for auto-update
      _eventToRegionMap[event.id] = region.id;
    });

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
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A22), Color(0xFF0D0D10), Color(0xFF1A1A22)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          // Reels
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: List.generate(
                  _reelCount,
                  (i) => Expanded(child: _buildReel(i)),
                ),
              ),
            ),
          ),
          // Controls
          Container(
            width: 120,
            padding: const EdgeInsets.all(6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSlotButton('SPIN', const Color(0xFF40FF90), _handleSpin),
                      const SizedBox(height: 4),
                      // Forced outcome buttons (only when engine is active)
                      if (_engineInitialized) ...[
                        _buildSmallButton('BIG WIN', const Color(0xFFFF9040),
                            () => _handleEngineSpin(forcedOutcome: ForcedOutcome.bigWin)),
                        const SizedBox(height: 3),
                        _buildSmallButton('MEGA', const Color(0xFFFF4080),
                            () => _handleEngineSpin(forcedOutcome: ForcedOutcome.megaWin)),
                        const SizedBox(height: 3),
                        _buildSmallButton('FREE', const Color(0xFF40C8FF),
                            () => _handleEngineSpin(forcedOutcome: ForcedOutcome.freeSpins)),
                        const SizedBox(height: 3),
                        _buildSmallButton('JACKPOT', const Color(0xFFFFD700),
                            () => _handleEngineSpin(forcedOutcome: ForcedOutcome.jackpotGrand)),
                      ] else ...[
                        _buildSlotButton('TURBO', const Color(0xFFFFAA00), () {}),
                      ],
                    ],
                  ),
                );
              },
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
                '${_compositeEvents.length} events',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
        Expanded(
          child: _compositeEvents.isEmpty
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
                  itemCount: _compositeEvents.length,
                  itemBuilder: (context, index) => _buildCompositeEventItem(_compositeEvents[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildCompositeEventItem(_CompositeEvent event) {
    final isSelected = _selectedEventId == event.id;

    // Make event draggable to timeline
    return Draggable<_CompositeEvent>(
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
          _addLayerToEvent(event, details.data);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedEventId = event.id;
              event.isExpanded = !event.isExpanded;
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

  Widget _buildCompositeEventContent(_CompositeEvent event, bool isSelected) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(
                event.isExpanded ? Icons.expand_more : Icons.chevron_right,
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
                      'Stage: ${event.stage} • Drag audio here',
                      style: const TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ],
                ),
              ),
              Text(
                '${event.layers.length} layers',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
        ),
        if (event.isExpanded)
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
                    children: event.layers.map((layer) => _buildLayerItem(layer)).toList(),
                  ),
          ),
      ],
    );
  }

  void _addLayerToEvent(_CompositeEvent event, String audioPath) {
    final audioInfo = _audioPool.firstWhere(
      (a) => a['path'] == audioPath,
      orElse: () => {'path': audioPath, 'name': audioPath.split('/').last, 'duration': 1.0},
    );

    final newLayer = _CompositeLayer(
      id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
      audioPath: audioPath,
      name: audioInfo['name'] as String,
    );

    setState(() {
      event.layers.add(newLayer);
      event.isExpanded = true;

      // Auto-update timeline region if this event is already on timeline
      final regionId = _eventToRegionMap[event.id];
      if (regionId != null) {
        _updateTimelineRegionFromEvent(event, regionId, audioInfo);
      }
    });

    // Sinhronizuj sa Event Registry
    _syncEventToRegistry(event);
  }

  /// Update timeline region when audio is added to mapped event
  void _updateTimelineRegionFromEvent(_CompositeEvent event, String regionId, Map<String, dynamic> audioInfo) {
    // Find the region in tracks
    for (final track in _tracks) {
      final regionIndex = track.regions.indexWhere((r) => r.id == regionId);
      if (regionIndex >= 0) {
        final region = track.regions[regionIndex];
        final layerDuration = (audioInfo['duration'] as num?)?.toDouble() ?? 1.0;

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
          audioPath: audioInfo['path'] as String? ?? '',
          name: audioInfo['name'] as String? ?? 'Audio',
          ffiClipId: ffiClipId > 0 ? ffiClipId : null,
        ));

        // Extend region duration if new layer is longer
        if (region.start + layerDuration > region.end) {
          region.end = region.start + layerDuration;
        }

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

  Widget _buildLayerItem(_CompositeLayer layer) {
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
        ],
      ),
    );
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
                  items: const [
                    DropdownMenuItem(value: 'SPIN_START', child: Text('SPIN_START')),
                    DropdownMenuItem(value: 'REEL_SPIN', child: Text('REEL_SPIN (loop)')),
                    DropdownMenuItem(value: 'REEL_STOP', child: Text('REEL_STOP (all)')),
                    DropdownMenuItem(value: 'REEL_STOP_0', child: Text('REEL_STOP_0')),
                    DropdownMenuItem(value: 'REEL_STOP_1', child: Text('REEL_STOP_1')),
                    DropdownMenuItem(value: 'REEL_STOP_2', child: Text('REEL_STOP_2')),
                    DropdownMenuItem(value: 'REEL_STOP_3', child: Text('REEL_STOP_3')),
                    DropdownMenuItem(value: 'REEL_STOP_4', child: Text('REEL_STOP_4')),
                    DropdownMenuItem(value: 'ANTICIPATION', child: Text('ANTICIPATION')),
                    DropdownMenuItem(value: 'WIN_PRESENT', child: Text('WIN_PRESENT')),
                    DropdownMenuItem(value: 'BIGWIN', child: Text('BIGWIN')),
                    DropdownMenuItem(value: 'FEATURE_ENTER', child: Text('FEATURE_ENTER')),
                    DropdownMenuItem(value: 'FEATURE_EXIT', child: Text('FEATURE_EXIT')),
                    DropdownMenuItem(value: 'JACKPOT', child: Text('JACKPOT')),
                    DropdownMenuItem(value: 'CASCADE', child: Text('CASCADE')),
                    DropdownMenuItem(value: 'CUSTOM', child: Text('CUSTOM')),
                  ],
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
    if (name.isEmpty) name = 'Event ${_compositeEvents.length + 1}';

    final newEvent = _CompositeEvent(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      stage: stage,
    );

    setState(() {
      _compositeEvents.add(newEvent);
      _selectedEventId = newEvent.id;
    });

    // Registruj u centralni Event Registry
    _syncEventToRegistry(newEvent);
  }

  /// Sinhronizuj composite event sa centralnim Event Registry
  void _syncEventToRegistry(_CompositeEvent compositeEvent) {
    final audioEvent = AudioEvent(
      id: compositeEvent.id,
      name: compositeEvent.name,
      stage: compositeEvent.stage,
      layers: compositeEvent.layers.map((l) => AudioLayer(
        id: l.id,
        audioPath: l.audioPath,
        name: l.name,
        volume: l.volume,
        pan: l.pan,
        delay: l.delay,
        busId: l.busId,
      )).toList(),
    );
    eventRegistry.registerEvent(audioEvent);
  }

  /// Sinhronizuj sve evente sa registry-jem
  void _syncAllEventsToRegistry() {
    for (final event in _compositeEvents) {
      _syncEventToRegistry(event);
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
    }
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
    // Stage Trace Widget with full timeline visualization
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Stage trace (animated marker through stages)
          StageTraceWidget(
            provider: _slotLabProvider,
            height: 80,
            showMiniProgress: true,
          ),
          const SizedBox(height: 4),
          // Forced Outcome - plain text line
          QuickOutcomeBar(provider: _slotLabProvider),
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _WaveformPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1;

    final midY = size.height / 2;
    final sampleWidth = size.width / data.length;

    for (int i = 0; i < data.length; i++) {
      final x = i * sampleWidth;
      final amplitude = data[i] * midY * 0.8;
      canvas.drawLine(
        Offset(x, midY - amplitude),
        Offset(x, midY + amplitude),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
