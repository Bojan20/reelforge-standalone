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
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../providers/middleware_provider.dart';
import '../theme/fluxforge_theme.dart';

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
  });

  double get duration => end - start;
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
}

// =============================================================================
// SLOT LAB SCREEN
// =============================================================================

/// Fullscreen Slot Lab interface
class SlotLabScreen extends StatefulWidget {
  final VoidCallback onClose;

  const SlotLabScreen({
    super.key,
    required this.onClose,
  });

  @override
  State<SlotLabScreen> createState() => _SlotLabScreenState();
}

class _SlotLabScreenState extends State<SlotLabScreen> with TickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  // Game spec state
  int _reelCount = 5;
  int _rowCount = 3;
  String _volatility = 'Medium';
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
  double _timelineDuration = 10.0; // Total duration in seconds
  Timer? _playbackTimer;

  // Track state
  final List<_SlotAudioTrack> _tracks = [];
  int? _selectedTrackIndex;

  // Stage markers
  final List<_StageMarker> _stageMarkers = [
    _StageMarker(position: 0.0, name: 'SPIN START', color: const Color(0xFF4A9EFF)),
    _StageMarker(position: 0.12, name: 'REEL 1', color: const Color(0xFF9B59B6)),
    _StageMarker(position: 0.22, name: 'REEL 2', color: const Color(0xFF9B59B6)),
    _StageMarker(position: 0.32, name: 'REEL 3', color: const Color(0xFF9B59B6)),
    _StageMarker(position: 0.42, name: 'ANTIC', color: const Color(0xFFE74C3C)),
    _StageMarker(position: 0.52, name: 'REEL 4', color: const Color(0xFF9B59B6)),
    _StageMarker(position: 0.62, name: 'REEL 5', color: const Color(0xFF9B59B6)),
    _StageMarker(position: 0.70, name: 'WIN', color: const Color(0xFFF1C40F)),
    _StageMarker(position: 0.75, name: 'ROLLUP', color: const Color(0xFF40FF90)),
    _StageMarker(position: 0.90, name: 'BIG WIN', color: const Color(0xFFFF9040)),
    _StageMarker(position: 1.0, name: 'END', color: const Color(0xFF888888)),
  ];

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

  // Drag state
  String? _draggingAudioPath;
  Offset? _dragPosition;

  // Simulated reel symbols
  final List<List<String>> _reelSymbols = [
    ['7', 'BAR', 'BELL', 'CHERRY', 'WILD'],
    ['BAR', '7', 'BONUS', 'BELL', 'CHERRY'],
    ['CHERRY', 'WILD', '7', 'BAR', 'BELL'],
    ['BELL', 'CHERRY', 'BAR', 'BONUS', '7'],
    ['WILD', 'BELL', 'CHERRY', '7', 'BAR'],
  ];

  // Sample audio pool (shared with DAW/Middleware)
  final List<Map<String, dynamic>> _audioPool = [
    {'path': 'sfx/spin_start.wav', 'name': 'Spin Start', 'duration': 0.5, 'folder': 'SFX'},
    {'path': 'sfx/reel_stop_01.wav', 'name': 'Reel Stop 1', 'duration': 0.3, 'folder': 'SFX'},
    {'path': 'sfx/reel_stop_02.wav', 'name': 'Reel Stop 2', 'duration': 0.3, 'folder': 'SFX'},
    {'path': 'sfx/anticipation_loop.wav', 'name': 'Anticipation Loop', 'duration': 2.0, 'folder': 'SFX'},
    {'path': 'sfx/win_small.wav', 'name': 'Win Small', 'duration': 1.0, 'folder': 'SFX'},
    {'path': 'sfx/win_medium.wav', 'name': 'Win Medium', 'duration': 1.5, 'folder': 'SFX'},
    {'path': 'sfx/win_big.wav', 'name': 'Win Big', 'duration': 2.5, 'folder': 'SFX'},
    {'path': 'music/rollup_loop.wav', 'name': 'Rollup Loop', 'duration': 4.0, 'folder': 'Music'},
    {'path': 'music/bigwin_fanfare.wav', 'name': 'Big Win Fanfare', 'duration': 5.0, 'folder': 'Music'},
    {'path': 'music/feature_intro.wav', 'name': 'Feature Intro', 'duration': 3.0, 'folder': 'Music'},
    {'path': 'ambience/crowd_cheer.wav', 'name': 'Crowd Cheer', 'duration': 2.0, 'folder': 'Ambience'},
    {'path': 'ambience/casino_floor.wav', 'name': 'Casino Floor', 'duration': 10.0, 'folder': 'Ambience'},
    {'path': 'ui/button_click.wav', 'name': 'Button Click', 'duration': 0.1, 'folder': 'UI'},
    {'path': 'ui/coin_drop.wav', 'name': 'Coin Drop', 'duration': 0.5, 'folder': 'UI'},
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _initializeTracks();
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _initializeTracks() {
    // Create default empty tracks (no demo regions by default)
    _tracks.addAll([
      _SlotAudioTrack(
        id: 'track_1',
        name: 'SFX Main',
        color: const Color(0xFF40FF90),
        outputBusId: 2,
      ),
      _SlotAudioTrack(
        id: 'track_2',
        name: 'Music',
        color: const Color(0xFF4A9EFF),
        outputBusId: 1,
      ),
      _SlotAudioTrack(
        id: 'track_3',
        name: 'Ambience',
        color: const Color(0xFF9B59B6),
        outputBusId: 2,
      ),
      _SlotAudioTrack(
        id: 'track_4',
        name: 'UI Sounds',
        color: const Color(0xFFF1C40F),
        outputBusId: 4,
      ),
    ]);
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
    return Scaffold(
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

                    // Center: Timeline + Slot View
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // Audio Timeline (main work area)
                          Expanded(
                            flex: 2,
                            child: _buildTimelineArea(),
                          ),
                          // Mock Slot View
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
    );
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

          // Status indicators
          _buildStatusChip('BALANCE', '\$${_balance.toStringAsFixed(0)}', const Color(0xFF40FF90)),
          const SizedBox(width: 8),
          _buildStatusChip('BET', '\$${_bet.toStringAsFixed(2)}', const Color(0xFF4A9EFF)),
          const SizedBox(width: 8),
          _buildStatusChip('WIN', '\$${_lastWin.toStringAsFixed(0)}', const Color(0xFFFFD700)),

          const SizedBox(width: 16),

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

          const SizedBox(width: 12),
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
          const SizedBox(width: 8),
          // Timecode display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatTimecode(_playheadPosition),
              style: const TextStyle(
                color: Color(0xFF40FF90),
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
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

  void _goToStart() {
    setState(() {
      _playheadPosition = 0.0;
    });
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted || !_isPlaying) {
          timer.cancel();
          return;
        }
        setState(() {
          _playheadPosition += 0.033;
          if (_playheadPosition >= _timelineDuration) {
            if (_isLooping) {
              _playheadPosition = 0.0;
            } else {
              _isPlaying = false;
              timer.cancel();
            }
          }
        });
      });
    } else {
      _playbackTimer?.cancel();
    }
  }

  void _stopPlayback() {
    setState(() {
      _isPlaying = false;
      _playheadPosition = 0.0;
    });
    _playbackTimer?.cancel();
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
  // LEFT PANEL - Game Spec & Paytable
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLeftPanel() {
    return Container(
      width: 220,
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
                  _buildSpecRow('Volatility', _volatility),
                  _buildSpecRow('RTP Target', '96.5%'),

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
        ],
      ),
    );
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

  Widget _buildTrackHeaders() {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _tracks.length,
      itemBuilder: (context, index) => _buildTrackHeader(_tracks[index], index),
    );
  }

  Widget _buildTrackHeader(_SlotAudioTrack track, int index) {
    final isSelected = _selectedTrackIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedTrackIndex = index),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 6),
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
            // Color indicator
            Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: track.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            // Track name
            Expanded(
              child: Text(
                track.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 11,
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
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        // Handle audio drop on timeline
        _handleAudioDrop(details.data, details.offset);
      },
      onWillAcceptWithDetails: (details) => true,
      builder: (context, candidateData, rejectedData) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Grid lines
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _TimelineGridPainter(
                    zoom: _timelineZoom,
                    duration: _timelineDuration,
                  ),
                ),

                // Tracks
                ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) => _buildTrackTimeline(
                    _tracks[index],
                    index,
                    constraints.maxWidth,
                  ),
                ),

                // Playhead
                Positioned(
                  left: (_playheadPosition / _timelineDuration) * constraints.maxWidth,
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

                // Click to set playhead
                GestureDetector(
                  onTapDown: (details) {
                    final newPosition = (details.localPosition.dx / constraints.maxWidth) * _timelineDuration;
                    setState(() {
                      _playheadPosition = newPosition.clamp(0.0, _timelineDuration);
                    });
                  },
                  child: Container(color: Colors.transparent),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTrackTimeline(_SlotAudioTrack track, int index, double width) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Stack(
        children: [
          // Regions
          ...track.regions.map((region) {
            final startX = (region.start / _timelineDuration) * width;
            final regionWidth = (region.duration / _timelineDuration) * width;

            return Positioned(
              left: startX,
              top: 4,
              child: _buildAudioRegion(region, track.color, track.isMuted),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAudioRegion(_AudioRegion region, Color trackColor, bool muted) {
    final width = (region.duration / _timelineDuration) * 800 * _timelineZoom;

    return GestureDetector(
      onTap: () => setState(() => region.isSelected = !region.isSelected),
      child: Container(
        width: width.clamp(20.0, 2000.0),
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              (muted ? Colors.grey : region.color).withOpacity(0.3),
              (muted ? Colors.grey : region.color).withOpacity(0.5),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: region.isSelected
                ? Colors.white
                : (muted ? Colors.grey : region.color),
            width: region.isSelected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              // Waveform placeholder
              if (region.waveformData != null)
                CustomPaint(
                  size: Size(width.clamp(20.0, 2000.0), 40),
                  painter: _WaveformPainter(
                    data: region.waveformData!,
                    color: muted ? Colors.grey : region.color,
                  ),
                ),
              // Region name
              Positioned(
                left: 4,
                top: 2,
                child: Text(
                  region.name,
                  style: TextStyle(
                    color: muted ? Colors.grey : Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAudioDrop(String audioPath, Offset globalPosition) {
    // Find which track was dropped on
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPosition = box.globalToLocal(globalPosition);

    // Calculate drop position in timeline
    // This is simplified - in production would need more precise calculations
    final trackIndex = _selectedTrackIndex ?? 0;
    if (trackIndex >= _tracks.length) return;

    // Find the audio info
    final audioInfo = _audioPool.firstWhere(
      (a) => a['path'] == audioPath,
      orElse: () => {'path': audioPath, 'name': audioPath.split('/').last, 'duration': 1.0},
    );

    // Create new region
    final region = _AudioRegion(
      id: 'region_${DateTime.now().millisecondsSinceEpoch}',
      start: _playheadPosition,
      end: _playheadPosition + (audioInfo['duration'] as double),
      name: audioInfo['name'] as String,
      audioPath: audioPath,
      color: _tracks[trackIndex].color,
      waveformData: _generateFakeWaveform(),
    );

    setState(() {
      _tracks[trackIndex].regions.add(region);
      _draggingAudioPath = null;
      _dragPosition = null;
    });
  }

  List<double> _generateFakeWaveform() {
    final random = math.Random();
    return List.generate(100, (i) => random.nextDouble() * 0.8 + 0.2);
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

    final newTrack = _SlotAudioTrack(
      id: 'track_${_tracks.length + 1}',
      name: 'Track ${_tracks.length + 1}',
      color: colors[_tracks.length % colors.length],
    );

    setState(() {
      _tracks.add(newTrack);
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
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSlotButton('SPIN', const Color(0xFF40FF90), _handleSpin),
                const SizedBox(height: 8),
                _buildSlotButton('TURBO', const Color(0xFFFFAA00), () {}),
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
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          _rowCount,
          (row) => _buildSymbol(_reelSymbols[reelIndex][row], isStoppedOrStopping),
        ),
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

  void _handleSpin() {
    if (_isSpinning) return;

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

    return GestureDetector(
      onTap: () => setState(() {
        _selectedEventId = event.id;
        event.isExpanded = !event.isExpanded;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.accentBlue.withOpacity(0.15) : const Color(0xFF1A1A22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentBlue : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Column(
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
                          'Stage: ${event.stage}',
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
                child: Column(
                  children: event.layers.map((layer) => _buildLayerItem(layer)).toList(),
                ),
              ),
          ],
        ),
      ),
    );
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
    final newEvent = _CompositeEvent(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Event ${_compositeEvents.length + 1}',
      stage: 'SPIN_START',
    );

    setState(() {
      _compositeEvents.add(newEvent);
      _selectedEventId = newEvent.id;
    });
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
                setState(() {
                  if (_previewingAudioPath == audio['path']) {
                    _previewingAudioPath = null;
                    _isPreviewPlaying = false;
                  } else {
                    _previewingAudioPath = audio['path'] as String;
                    _isPreviewPlaying = true;
                  }
                });
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
    }
  }

  Widget _buildTimelineTabContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timeline, size: 40, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 8),
          const Text(
            'Timeline Overview',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const Text(
            'Detailed stage timing and event visualization',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildBusHierarchyContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree, size: 40, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 8),
          const Text(
            'Bus Hierarchy',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const Text(
            'Master > Music, SFX, Voice, UI',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilerContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics, size: 40, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 8),
          const Text(
            'Audio Profiler',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const Text(
            'Real-time voice count, CPU usage, memory',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildRtpcContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 40, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 8),
          const Text(
            'RTPC Parameters',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const Text(
            'Bet Level, Tension, Win Multiplier',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildResourcesContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage, size: 40, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 8),
          const Text(
            'Resources',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          Text(
            '${_audioPool.length} audio files loaded',
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildAuxSendsContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_split, size: 40, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 8),
          const Text(
            'Aux Sends',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const Text(
            'Reverb A, Reverb B, Delay',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
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
    final secondWidth = (size.width / duration) * zoom;
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
