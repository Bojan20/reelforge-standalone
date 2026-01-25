/// Slot Preview Widget
///
/// Full-screen slot reels - NO header/footer, maximum visibility
/// - Reels fill entire available space
/// - Smooth vertical spinning animation
/// - Premium 3D symbols
/// - Win amount overlay with animated counter
/// - Particle system for Big Win celebrations
/// - Enhanced symbol animations (bounce, glow)
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../../providers/slot_lab_provider.dart';
import '../../services/event_registry.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import 'professional_reel_animation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT SYMBOL DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

class SlotSymbol {
  final int id;
  final String name;
  final String displayChar;
  final List<Color> gradientColors;
  final Color glowColor;
  final bool isSpecial;

  const SlotSymbol({
    required this.id,
    required this.name,
    required this.displayChar,
    required this.gradientColors,
    required this.glowColor,
    this.isSpecial = false,
  });

  static const Map<int, SlotSymbol> symbols = {
    0: SlotSymbol(
      id: 0, name: 'WILD', displayChar: '★',
      gradientColors: [Color(0xFFFFE55C), Color(0xFFFFD700), Color(0xFFCC9900)],
      glowColor: Color(0xFFFFD700), isSpecial: true,
    ),
    1: SlotSymbol(
      id: 1, name: 'SCATTER', displayChar: '◆',
      gradientColors: [Color(0xFFFF66FF), Color(0xFFE040FB), Color(0xFF9C27B0)],
      glowColor: Color(0xFFE040FB), isSpecial: true,
    ),
    2: SlotSymbol(
      id: 2, name: 'BONUS', displayChar: '♦',
      gradientColors: [Color(0xFF80EEFF), Color(0xFF40C8FF), Color(0xFF0088CC)],
      glowColor: Color(0xFF40C8FF), isSpecial: true,
    ),
    3: SlotSymbol(
      id: 3, name: 'SEVEN', displayChar: '7',
      gradientColors: [Color(0xFFFF6699), Color(0xFFFF4080), Color(0xFFCC0044)],
      glowColor: Color(0xFFFF4080),
    ),
    4: SlotSymbol(
      id: 4, name: 'BAR', displayChar: '▬',
      gradientColors: [Color(0xFF88FF88), Color(0xFF4CAF50), Color(0xFF2E7D32)],
      glowColor: Color(0xFF4CAF50),
    ),
    5: SlotSymbol(
      id: 5, name: 'BELL', displayChar: '🔔',
      gradientColors: [Color(0xFFFFFF88), Color(0xFFFFEB3B), Color(0xFFCCAA00)],
      glowColor: Color(0xFFFFEB3B),
    ),
    6: SlotSymbol(
      id: 6, name: 'CHERRY', displayChar: '🍒',
      gradientColors: [Color(0xFFFF8866), Color(0xFFFF5722), Color(0xFFBB3300)],
      glowColor: Color(0xFFFF5722),
    ),
    7: SlotSymbol(
      id: 7, name: 'LEMON', displayChar: '🍋',
      gradientColors: [Color(0xFFFFFF99), Color(0xFFFFEB3B), Color(0xFFAFB42B)],
      glowColor: Color(0xFFCDDC39),
    ),
    8: SlotSymbol(
      id: 8, name: 'ORANGE', displayChar: '🍊',
      gradientColors: [Color(0xFFFFCC66), Color(0xFFFF9800), Color(0xFFCC6600)],
      glowColor: Color(0xFFFF9800),
    ),
    9: SlotSymbol(
      id: 9, name: 'GRAPE', displayChar: '🍇',
      gradientColors: [Color(0xFFCC66FF), Color(0xFF9C27B0), Color(0xFF6A1B9A)],
      glowColor: Color(0xFF9C27B0),
    ),
  };

  static SlotSymbol getSymbol(int id) => symbols[id % symbols.length] ?? symbols[9]!;
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT PREVIEW WIDGET - FULLSCREEN REELS
// ═══════════════════════════════════════════════════════════════════════════

class SlotPreviewWidget extends StatefulWidget {
  final SlotLabProvider provider;
  final int reels;
  final int rows;

  const SlotPreviewWidget({
    super.key,
    required this.provider,
    this.reels = 5,
    this.rows = 3,
  });

  @override
  State<SlotPreviewWidget> createState() => _SlotPreviewWidgetState();
}

class _SlotPreviewWidgetState extends State<SlotPreviewWidget>
    with TickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════════════════════
  // PROFESSIONAL REEL ANIMATION SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════
  late ProfessionalReelAnimationController _reelAnimController;
  Ticker? _animationTicker;
  final Set<int> _reelStoppedFlags = {}; // Track which reels have triggered audio

  // ═══════════════════════════════════════════════════════════════════════════
  // IGT-STYLE SEQUENTIAL REEL STOP BUFFER
  // Animation callbacks can fire OUT OF ORDER. We must trigger audio SEQUENTIALLY.
  // If Reel 4 finishes before Reel 3, we buffer it and wait for Reel 3.
  // ═══════════════════════════════════════════════════════════════════════════
  int _nextExpectedReelIndex = 0; // Which reel we're waiting for (0, 1, 2, 3, 4)
  final Set<int> _pendingReelStops = {}; // Buffered out-of-order reel stops

  // Legacy controllers (kept for win effects)
  late AnimationController _winPulseController;
  late Animation<double> _winPulseAnimation;

  // Win amount overlay animations
  late AnimationController _winAmountController;
  late Animation<double> _winAmountScale;
  late Animation<double> _winAmountOpacity;
  late AnimationController _winCounterController;

  // Symbol bounce animation for wins
  late AnimationController _symbolBounceController;
  late Animation<double> _symbolBounceAnimation;

  // Particle system with object pool (eliminates GC pressure)
  final List<_WinParticle> _particles = [];
  final _ParticlePool _particlePool = _ParticlePool();
  late AnimationController _particleController;

  // Anticipation/Near Miss animations
  late AnimationController _anticipationController;
  late Animation<double> _anticipationPulse;
  late AnimationController _nearMissController;
  late Animation<double> _nearMissShake;

  // Cascade animations
  late AnimationController _cascadePopController;
  late Animation<double> _cascadePopAnimation;

  List<List<int>> _displayGrid = [];
  List<List<int>> _targetGrid = [];
  bool _isSpinning = false;
  bool _spinFinalized = false; // Prevents re-trigger after finalize
  String? _lastProcessedSpinId; // Track which spin result we've processed
  int _spinStartTimeMs = 0; // Timestamp when spin started (for Event Log ordering)
  Set<int> _winningReels = {};
  Set<String> _winningPositions = {}; // "reel,row" format

  // ═══════════════════════════════════════════════════════════════════════════
  // PER-REEL ANTICIPATION SYSTEM — Condition-based (scatter detection)
  // Industry standard: Anticipation triggers when 2+ scatters land, extends remaining reels
  // ═══════════════════════════════════════════════════════════════════════════
  bool _isAnticipation = false;
  bool _isNearMiss = false;
  Set<int> _anticipationReels = {}; // Reels currently showing anticipation
  Set<String> _nearMissPositions = {}; // Positions that "just missed"
  final Map<int, Timer> _anticipationTimers = {}; // Per-reel anticipation timers
  final Map<int, double> _anticipationProgress = {}; // Per-reel progress (0.0 → 1.0)
  static const int _anticipationDurationMs = 3000; // 3 seconds per reel
  static const int _scatterSymbolId = 2; // SCATTER symbol ID (matches Rust SymbolType::Scatter = 2)
  static const int _scattersNeededForAnticipation = 2; // 2 scatters needed to trigger
  Set<int> _scatterReels = {}; // Reels that have landed with scatter symbols

  // Cascade state
  bool _isCascading = false;
  Set<String> _cascadePopPositions = {}; // Positions being popped
  int _cascadeStep = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // V2: LANDING IMPACT EFFECT — Industry standard "punch" on reel stop
  // ═══════════════════════════════════════════════════════════════════════════
  final Map<int, double> _landingFlashProgress = {}; // Per-reel flash (0.0 - 1.0)
  final Map<int, double> _landingPopScale = {}; // Per-reel scale pop (1.0 - 1.05 - 1.0)
  bool _screenShakeActive = false; // Screen shake on last reel (big wins only)

  // ═══════════════════════════════════════════════════════════════════════════
  // V6: ENHANCED SYMBOL HIGHLIGHT — Staggered popup for winning symbols
  // Industry standard: individual symbol "pop" on first highlight
  // ═══════════════════════════════════════════════════════════════════════════
  final Map<String, double> _symbolPopScale = {}; // Per-position popup scale (1.0 → 1.15 → 1.0)
  final Map<String, double> _symbolPopRotation = {}; // Micro-rotation wiggle (radians)
  static const double _symbolPopMaxScale = 1.15; // Peak popup scale
  static const int _symbolPopStaggerMs = 50; // Delay between each symbol's popup

  // ═══════════════════════════════════════════════════════════════════════════
  // V7: ROLLUP VISUAL FEEDBACK — Meter + counter shake for engaging rollup
  // Industry standard: visual feedback makes rollup feel substantial
  // ═══════════════════════════════════════════════════════════════════════════
  double _rollupProgress = 0.0; // 0.0 to 1.0 for progress meter
  double _counterShakeScale = 1.0; // Scale pulse on tick (1.0 → 1.08 → 1.0)
  bool _isRollingUp = false; // Currently in rollup phase

  // ═══════════════════════════════════════════════════════════════════════════
  // V8: ENHANCED WIN PLAQUE — Screen flash, dramatic entrance, particles
  // Industry standard: NetEnt, Pragmatic Play dramatic win celebration
  // ═══════════════════════════════════════════════════════════════════════════
  late AnimationController _screenFlashController;
  late Animation<double> _screenFlashOpacity;
  late AnimationController _plaqueGlowController;
  late Animation<double> _plaqueGlowPulse;
  bool _showScreenFlash = false; // True during initial flash

  // Win display state
  double _displayedWinAmount = 0;
  double _targetWinAmount = 0;
  String _winTier = ''; // BIG, SUPER, MEGA, EPIC, ULTRA (no plaque for small wins)

  // ═══════════════════════════════════════════════════════════════════════════
  // TIER PROGRESSION SYSTEM — Progressive reveal from BIG to final tier
  // Each tier displays for 4 seconds, building excitement to the final tier
  // ═══════════════════════════════════════════════════════════════════════════
  String _currentDisplayTier = ''; // Currently shown tier label on plaque
  Timer? _tierProgressionTimer;
  int _tierProgressionIndex = 0;
  List<String> _tierProgressionList = []; // Tiers to progress through (e.g., ['BIG', 'SUPER', 'MEGA'])
  bool _isInTierProgression = false;

  // Tier progression timing constants
  static const int _bigWinIntroDurationMs = 500;  // BIG_WIN_INTRO duration
  static const int _tierDisplayDurationMs = 4000;  // Each tier shows for 4s
  static const int _bigWinEndDurationMs = 4000;    // BIG_WIN_END duration

  // All possible tiers in order
  static const List<String> _allTiersInOrder = ['BIG', 'SUPER', 'MEGA', 'EPIC', 'ULTRA'];

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN LINE PRESENTATION — Cycles through each winning line
  // ═══════════════════════════════════════════════════════════════════════════
  List<LineWin> _lineWinsForPresentation = [];
  int _currentPresentingLineIndex = 0;
  bool _isShowingWinLines = false;
  Timer? _winLineCycleTimer;
  Set<String> _currentLinePositions = {}; // Positions for currently shown line
  static const Duration _winLineCycleDuration = Duration(milliseconds: 1500);

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN AUDIO FLOW — 3-Phase sequential presentation
  // Phase 1: Symbol Highlight (1050ms) — winning symbols glow/bounce
  // Phase 2: Tier Plaque + Coin Counter Rollup — "BIG WIN!" + counter animation
  // Phase 3: Win Lines (visual lines only, NO symbol info like "3x Grapes")
  // Win lines start AFTER rollup completes (strict sequential)
  // ═══════════════════════════════════════════════════════════════════════════
  Timer? _rollupTickTimer;
  int _rollupTickCount = 0;
  static const int _rollupTicksTotal = 15; // Default ~1.5s rollup duration at 100ms intervals

  // Timing constants
  static const int _symbolHighlightDurationMs = 1050; // 3 cycles × 350ms
  static const int _symbolPulseCycleMs = 350;
  static const int _symbolPulseCycles = 3;

  // Tier-specific rollup durations (ms) — Industry standard progression
  // Empty string ('') uses default for small wins (< 5x)
  static const Map<String, int> _rollupDurationByTier = {
    'BIG': 2500,     // First major tier (5x-15x)
    'SUPER': 4000,   // Second tier (15x-30x)
    'MEGA': 7000,    // Third tier (30x-60x)
    'EPIC': 12000,   // Fourth tier (60x-100x)
    'ULTRA': 20000,  // Maximum (100x+)
  };
  static const int _defaultRollupDuration = 1500;  // Small wins

  // Tier-specific rollup tick rate (ticks per second)
  static const Map<String, int> _rollupTickRateByTier = {
    'BIG': 12,     // First major tier
    'SUPER': 10,   // Second tier
    'MEGA': 8,     // Third tier
    'EPIC': 6,     // Fourth tier
    'ULTRA': 4,    // Maximum
  };
  static const int _defaultRollupTickRate = 15;  // Small wins — fast ticks

  // Currency formatter for win display — Industry standard: 2 decimal places
  // Examples: 1234.50 → "1,234.50" | 50.00 → "50.00" | 1234567.89 → "1,234,567.89"
  static final _currencyFormatter = NumberFormat.currency(
    symbol: '',
    decimalDigits: 2,
    locale: 'en_US',
  );

  final _random = math.Random();
  List<List<int>> _spinSymbols = [];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeGrid();
    widget.provider.addListener(_onProviderUpdate);
  }

  @override
  void didUpdateWidget(SlotPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reels != widget.reels || oldWidget.rows != widget.rows) {
      _disposeControllers();
      _initializeControllers();
      _initializeGrid();
    }
  }

  void _initializeControllers() {
    // ═══════════════════════════════════════════════════════════════════════════
    // PROFESSIONAL REEL ANIMATION - Phase-based with precise timing
    // ═══════════════════════════════════════════════════════════════════════════
    _reelAnimController = ProfessionalReelAnimationController(
      reelCount: widget.reels,
      rowCount: widget.rows,
      profile: ReelTimingProfile.studio, // Matches timing.rs studio() values
    );

    // Connect reel stop callback to audio triggering
    _reelAnimController.onReelStop = _onReelStopVisual;
    _reelAnimController.onAllReelsStopped = _onAllReelsStoppedVisual;

    // Create ticker for continuous animation updates
    _animationTicker = createTicker((_) {
      _reelAnimController.tick();
      if (mounted) setState(() {}); // Trigger rebuild for visual update
    });
    _animationTicker!.start();

    _winPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _winPulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _winPulseController, curve: Curves.easeInOut),
    );

    // Win amount overlay animation
    _winAmountController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _winAmountScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _winAmountController,
        curve: Curves.elasticOut,
      ),
    );
    _winAmountOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _winAmountController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    // Win counter rollup animation
    _winCounterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(_updateWinCounter);

    // Symbol bounce for winning symbols — Industry standard: 3 pulse cycles × 350ms = 1050ms
    _symbolBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _symbolPulseCycleMs),
    );
    _symbolBounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _symbolBounceController, curve: Curves.easeInOut),
    );

    // Particle system controller
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..addListener(_updateParticles);

    // Anticipation animation - glowing pulse effect
    _anticipationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
    _anticipationPulse = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _anticipationController, curve: Curves.easeInOut),
    );

    // Near miss shake animation
    _nearMissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _nearMissShake = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _nearMissController, curve: Curves.elasticOut),
    );

    // Cascade pop animation (symbols exploding/popping)
    _cascadePopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _cascadePopAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _cascadePopController, curve: Curves.easeInBack),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // V8: SCREEN FLASH + PLAQUE GLOW — Dramatic entrance animations
    // Industry standard: Flash on entrance, pulsing glow during display
    // ═══════════════════════════════════════════════════════════════════════════
    _screenFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _screenFlashOpacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _screenFlashController, curve: Curves.easeOut),
    );

    // Pulsing glow effect for plaque (faster than win pulse)
    _plaqueGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
    _plaqueGlowPulse = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _plaqueGlowController, curve: Curves.easeInOut),
    );

    _spinSymbols = List.generate(
      widget.reels,
      (_) => List.generate(20, (_) => _random.nextInt(10)),
    );
  }

  void _updateWinCounter() {
    if (!mounted) return;
    setState(() {
      _displayedWinAmount = ui.lerpDouble(0, _targetWinAmount, _winCounterController.value) ?? 0;
    });
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (final particle in _particles) {
        particle.update();
      }
      // Return dead particles to pool before removing
      final deadParticles = _particles.where((p) => p.isDead).toList();
      _particlePool.releaseAll(deadParticles);
      _particles.removeWhere((p) => p.isDead);
    });
  }

  void _initializeGrid() {
    _displayGrid = List.generate(
      widget.reels,
      (_) => List.generate(widget.rows, (_) => _random.nextInt(10)),
    );
    _targetGrid = List.generate(
      widget.reels,
      (r) => List.from(_displayGrid[r]),
    );
  }

  void _disposeControllers() {
    // Dispose professional animation controller
    _animationTicker?.stop();
    _animationTicker?.dispose();
    _reelAnimController.dispose();

    // Dispose legacy effect controllers
    _winPulseController.dispose();
    _winAmountController.dispose();
    _winCounterController.dispose();
    _symbolBounceController.dispose();
    _particleController.dispose();
    _anticipationController.dispose();
    _nearMissController.dispose();
    _cascadePopController.dispose();

    // Cancel per-reel anticipation timers
    for (final timer in _anticipationTimers.values) {
      timer.cancel();
    }
    _anticipationTimers.clear();

    // V8: Dispose enhanced plaque controllers
    _screenFlashController.dispose();
    _plaqueGlowController.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC CALLBACKS — Audio triggers on VISUAL reel stop
  // IGT STANDARD: Reels MUST stop in order 0→1→2→3→4, audio fires sequentially
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when a reel VISUALLY stops - uses IGT-style sequential buffer
  /// Animation callbacks can fire OUT OF ORDER. We must trigger audio SEQUENTIALLY.
  void _onReelStopVisual(int reelIndex) {
    if (!mounted) return;

    // Prevent duplicate triggers
    if (_reelStoppedFlags.contains(reelIndex)) return;
    _reelStoppedFlags.add(reelIndex);

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: Update _displayGrid IMMEDIATELY when reel stops
    // This ensures the symbols shown during bouncing stay after stopped phase
    // ═══════════════════════════════════════════════════════════════════════════
    setState(() {
      if (reelIndex < _targetGrid.length && reelIndex < _displayGrid.length) {
        for (int row = 0; row < widget.rows && row < _targetGrid[reelIndex].length; row++) {
          _displayGrid[reelIndex][row] = _targetGrid[reelIndex][row];
        }
      }
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // V2: LANDING IMPACT EFFECT — Flash + Scale Pop on reel stop
    // Industry standard "punch" visual when reel lands
    // ═══════════════════════════════════════════════════════════════════════════
    _triggerLandingImpact(reelIndex);

    // ═══════════════════════════════════════════════════════════════════════════
    // IGT-STYLE SEQUENTIAL BUFFER
    // If this reel is the next expected one, trigger audio immediately
    // If not, buffer it and wait for the expected one
    // ═══════════════════════════════════════════════════════════════════════════
    if (reelIndex == _nextExpectedReelIndex) {
      // This is the next expected reel — trigger immediately
      _triggerReelStopAudio(reelIndex);
      _nextExpectedReelIndex++;

      // Flush any buffered reels that are now in sequence
      _flushPendingReelStops();
    } else {
      // Out of order — buffer it for later
      debugPrint('[SlotPreview] 📦 REEL $reelIndex BUFFERED (waiting for reel $_nextExpectedReelIndex)');
      _pendingReelStops.add(reelIndex);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V2: LANDING IMPACT — Industry standard visual "punch" on reel landing
  // Flash overlay (50ms) + Scale pop (1.05x over 100ms)
  // ═══════════════════════════════════════════════════════════════════════════
  void _triggerLandingImpact(int reelIndex) {
    // Start flash at full intensity
    setState(() {
      _landingFlashProgress[reelIndex] = 1.0;
      _landingPopScale[reelIndex] = 1.08; // Start at peak scale
    });

    // Animate flash decay (50ms)
    Future.delayed(const Duration(milliseconds: 20), () {
      if (!mounted) return;
      setState(() => _landingFlashProgress[reelIndex] = 0.6);
    });
    Future.delayed(const Duration(milliseconds: 40), () {
      if (!mounted) return;
      setState(() => _landingFlashProgress[reelIndex] = 0.3);
    });
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() => _landingFlashProgress[reelIndex] = 0.0);
    });

    // Animate scale pop decay (100ms)
    Future.delayed(const Duration(milliseconds: 30), () {
      if (!mounted) return;
      setState(() => _landingPopScale[reelIndex] = 1.05);
    });
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() => _landingPopScale[reelIndex] = 1.02);
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() => _landingPopScale[reelIndex] = 1.0);
    });

    // Screen shake on LAST REEL for potential big wins
    if (reelIndex == widget.reels - 1) {
      _triggerScreenShake();
    }
  }

  /// Brief screen shake when last reel lands (anticipation effect)
  void _triggerScreenShake() {
    if (!mounted) return;
    setState(() => _screenShakeActive = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() => _screenShakeActive = false);
    });
  }

  /// Triggers REEL_STOP audio for a specific reel with correct timestamp
  void _triggerReelStopAudio(int reelIndex) {
    // Stop anticipation for this reel if active
    _stopReelAnticipation(reelIndex);

    // Get RUST PLANNED timestamp for correct Event Log ordering
    double timestampMs = 0.0;
    try {
      final stages = widget.provider.lastStages;
      final matchingStage = stages.firstWhere(
        (s) => s.stageType.toUpperCase() == 'REEL_STOP' && s.rawStage['reel_index'] == reelIndex,
        orElse: () => stages.firstWhere(
          (s) => s.stageType.toUpperCase() == 'REEL_STOP',
          orElse: () => throw StateError('No REEL_STOP stage found'),
        ),
      );
      timestampMs = matchingStage.timestampMs;
    } catch (e) {
      // Fallback to elapsed time if stage not found
      timestampMs = (DateTime.now().millisecondsSinceEpoch - _spinStartTimeMs).toDouble();
    }

    debugPrint('[SlotPreview] 🎰 REEL $reelIndex STOPPED → triggering REEL_STOP_$reelIndex (rust_ts: ${timestampMs.toStringAsFixed(0)}ms)');
    eventRegistry.triggerStage('REEL_STOP_$reelIndex', context: {'timestamp_ms': timestampMs});

    // ═══════════════════════════════════════════════════════════════════════════
    // V9: CONDITION-BASED ANTICIPATION — Detect scatters, trigger on 2nd scatter
    // Industry standard: Anticipation only activates when there's potential for 3rd scatter
    // Example: 2 scatters landed on reels 0,1 → anticipation on remaining reels 2,3,4
    // ═══════════════════════════════════════════════════════════════════════════
    _checkScatterAndTriggerAnticipation(reelIndex);
  }

  /// Check if the stopped reel has scatter symbols and trigger anticipation if 2+ found
  void _checkScatterAndTriggerAnticipation(int reelIndex) {
    // Check if this reel has any scatter symbols
    if (reelIndex < _targetGrid.length) {
      final reelSymbols = _targetGrid[reelIndex];
      final hasScatter = reelSymbols.any((symbolId) => symbolId == _scatterSymbolId);

      if (hasScatter) {
        _scatterReels.add(reelIndex);
        debugPrint('[SlotPreview] ◆ SCATTER detected on reel $reelIndex (total: ${_scatterReels.length})');

        // Trigger anticipation when we have 2 scatters and remaining reels exist
        if (_scatterReels.length >= _scattersNeededForAnticipation) {
          // Find remaining reels that haven't stopped yet
          final remainingReels = <int>[];
          for (int r = 0; r < widget.reels; r++) {
            if (!_reelStoppedFlags.contains(r) && !_scatterReels.contains(r)) {
              remainingReels.add(r);
            }
          }

          if (remainingReels.isNotEmpty) {
            debugPrint('[SlotPreview] 🎯 ANTICIPATION TRIGGERED! Scatters: $_scatterReels, extending reels: $remainingReels');

            // Extend spin time for remaining reels by 3000ms (3 seconds)
            for (final remainingReel in remainingReels) {
              _reelAnimController.extendReelSpinTime(remainingReel, _anticipationDurationMs);
              // Also trigger visual anticipation overlay
              _startReelAnticipation(remainingReel);
            }

            // Trigger anticipation audio stage
            eventRegistry.triggerStage('ANTICIPATION_ON');
            setState(() {
              _isAnticipation = true;
            });
          }
        }
      }
    }
  }

  /// Flush buffered reel stops that are now in sequence
  void _flushPendingReelStops() {
    while (_pendingReelStops.contains(_nextExpectedReelIndex)) {
      final reelToFlush = _nextExpectedReelIndex;
      _pendingReelStops.remove(reelToFlush);
      debugPrint('[SlotPreview] 📤 FLUSHING BUFFERED REEL $reelToFlush');
      _triggerReelStopAudio(reelToFlush);
      _nextExpectedReelIndex++;
    }
  }

  /// Called when ALL reels have stopped - trigger win evaluation
  void _onAllReelsStoppedVisual() {
    if (!mounted) return;

    // CRITICAL: Guard against multiple calls (stopImmediately also fires this callback)
    if (_spinFinalized || !_isSpinning) {
      debugPrint('[SlotPreview] ⚠️ _onAllReelsStoppedVisual SKIPPED: already finalized=$_spinFinalized, spinning=$_isSpinning');
      return;
    }

    debugPrint('[SlotPreview] ✅ ALL REELS STOPPED → finalize spin');

    // ═══════════════════════════════════════════════════════════════════════════
    // NOTIFY PROVIDER: Reels no longer spinning (for STOP button visibility)
    // This MUST be called before any win presentation starts
    // ═══════════════════════════════════════════════════════════════════════════
    widget.provider.onAllReelsVisualStop();

    // Now finalize with the result
    final result = widget.provider.lastResult;
    if (result != null) {
      _finalizeSpin(result);
    }
  }

  @override
  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    _winLineCycleTimer?.cancel();
    _tierProgressionTimer?.cancel(); // Clean up tier progression
    _stopRollupTicks(); // Clean up rollup audio sequence
    _disposeControllers();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    final result = widget.provider.lastResult;
    final isPlaying = widget.provider.isPlayingStages;
    final stages = widget.provider.lastStages;
    final spinId = result?.spinId;

    // ═══════════════════════════════════════════════════════════════════════════
    // DETAILED DEBUG — Track every state change
    // ═══════════════════════════════════════════════════════════════════════════
    debugPrint('╔══════════════════════════════════════════════════════════════╗');
    debugPrint('║ [SlotPreview] _onProviderUpdate                              ║');
    debugPrint('╠══════════════════════════════════════════════════════════════╣');
    debugPrint('║ Provider state:');
    debugPrint('║   isPlayingStages = $isPlaying');
    debugPrint('║   stages.length = ${stages.length}');
    debugPrint('║   result.spinId = $spinId');
    debugPrint('║ Widget state:');
    debugPrint('║   _isSpinning = $_isSpinning');
    debugPrint('║   _spinFinalized = $_spinFinalized');
    debugPrint('║   _lastProcessedSpinId = $_lastProcessedSpinId');
    debugPrint('╚══════════════════════════════════════════════════════════════╝');

    // ═══════════════════════════════════════════════════════════════════════════
    // SPIN START LOGIC — Guard against re-triggering after finalize
    // ═══════════════════════════════════════════════════════════════════════════
    // Conditions to start spin:
    // 1. Provider is playing stages
    // 2. We have stages to process
    // 3. We're not already spinning
    // 4. We haven't just finalized this spin (prevents double-trigger)
    // 5. This is a NEW spin result (different spinId)

    final canStartSpin = isPlaying && stages.isNotEmpty && !_isSpinning && !_spinFinalized;
    debugPrint('[SlotPreview] canStartSpin=$canStartSpin (isPlaying=$isPlaying, stages=${stages.length}, !spinning=${!_isSpinning}, !finalized=${!_spinFinalized})');

    if (canStartSpin) {
      final hasSpinStart = stages.any((s) => s.stageType == 'spin_start');

      // DEBUG: Log stage types for verification
      if (stages.isNotEmpty) {
        debugPrint('[SlotPreview] Stage types: ${stages.map((s) => s.stageType).take(5).join(", ")}...');
      }
      debugPrint('[SlotPreview] hasSpinStart=$hasSpinStart, spinId=$spinId, lastProcessed=$_lastProcessedSpinId');

      // Only start if this is a genuinely new spin
      if (hasSpinStart && spinId != null && spinId != _lastProcessedSpinId) {
        debugPrint('[SlotPreview] 🆕 NEW SPIN DETECTED: $spinId');
        _lastProcessedSpinId = spinId;
        _startSpin(result);
      } else if (!hasSpinStart) {
        debugPrint('[SlotPreview] ⚠️ BLOCKED: No spin_start stage found!');
      } else if (spinId == _lastProcessedSpinId) {
        debugPrint('[SlotPreview] ⚠️ BLOCKED: Same spinId as last processed ($spinId)');
      } else if (spinId == null) {
        debugPrint('[SlotPreview] ⚠️ BLOCKED: spinId is null');
      }
    } else {
      // Log WHY we can't start spin
      if (!isPlaying) debugPrint('[SlotPreview] ⏸️ Not starting: isPlaying=false');
      if (stages.isEmpty) debugPrint('[SlotPreview] ⏸️ Not starting: stages empty');
      if (_isSpinning) debugPrint('[SlotPreview] ⏸️ Not starting: already spinning');
      if (_spinFinalized) debugPrint('[SlotPreview] ⏸️ Not starting: spinFinalized=true');
    }

    // Reset finalized flag when provider stops playing (ready for next spin)
    if (!isPlaying && _spinFinalized) {
      debugPrint('[SlotPreview] 🔄 RESET: spinFinalized false → ready for next spin');
      _spinFinalized = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STOP BUTTON HANDLER — If provider stopped but reels are still spinning,
    // force-stop ALL reels immediately
    // ═══════════════════════════════════════════════════════════════════════════
    if (!isPlaying && _isSpinning) {
      debugPrint('[SlotPreview] ⏹️ STOP DETECTED: Provider stopped while reels spinning → force stop all reels');

      // Stop the visual animation immediately
      if (_reelAnimController.isSpinning) {
        _reelAnimController.stopImmediately();
      }

      // Stop all anticipation animations
      _stopAnticipation();

      // Update display grid to target (final) values
      for (int r = 0; r < widget.reels && r < _targetGrid.length; r++) {
        for (int row = 0; row < widget.rows && row < _targetGrid[r].length; row++) {
          _displayGrid[r][row] = _targetGrid[r][row];
        }
      }

      // Finalize the spin if we have a result
      if (result != null) {
        _finalizeSpin(result);
      } else {
        // No result - just reset state
        setState(() {
          _isSpinning = false;
          _spinFinalized = true;
        });
      }
    }

    // Check for anticipation events
    if (isPlaying && stages.isNotEmpty) {
      final anticipationOn = stages.any((s) =>
          s.stageType.toLowerCase().contains('anticipation') &&
          s.stageType.toLowerCase().contains('on'));
      final anticipationOff = stages.any((s) =>
          s.stageType.toLowerCase().contains('anticipation') &&
          s.stageType.toLowerCase().contains('off'));

      if (anticipationOn && !_isAnticipation) {
        _startAnticipation(result);
      } else if (anticipationOff && _isAnticipation) {
        _stopAnticipation();
      }

      // Check for near miss events
      final nearMiss = stages.any((s) =>
          s.stageType.toLowerCase().contains('near') &&
          s.stageType.toLowerCase().contains('miss'));
      if (nearMiss && !_isNearMiss) {
        _triggerNearMiss(result);
      }

      // Check for cascade events
      final cascadeStart = stages.any((s) =>
          s.stageType.toLowerCase().contains('cascade') &&
          s.stageType.toLowerCase().contains('start'));
      final cascadeStep = stages.any((s) =>
          s.stageType.toLowerCase().contains('cascade') &&
          s.stageType.toLowerCase().contains('step'));
      if (cascadeStart && !_isCascading) {
        _startCascade(result);
      } else if (cascadeStep && _isCascading) {
        _cascadeStepAnimation(result);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REMOVED: Early finalize when provider stops playing
    // REASON: Visual animation may still be running!
    // CORRECT: Only call _finalizeSpin() from _onAllReelsStoppedVisual()
    // This ensures ALL reels land visually BEFORE win evaluation starts
    // ═══════════════════════════════════════════════════════════════════════════
    // OLD CODE (WRONG):
    // if (!isPlaying && result != null && _isSpinning) {
    //   _finalizeSpin(result);
    // }
  }

  void _startSpin(SlotLabSpinResult? result) {
    debugPrint('[SlotPreview] 🎬 _startSpin() called, _isSpinning=$_isSpinning');
    if (_isSpinning) {
      debugPrint('[SlotPreview] ❌ _startSpin BLOCKED: already spinning!');
      return;
    }
    debugPrint('[SlotPreview] ✅ _startSpin PROCEEDING — will set _isSpinning=true');

    // Stop any previous win line presentation and tier progression
    _stopWinLinePresentation();
    _stopTierProgression();

    // Capture spin start time for Event Log timestamp ordering
    _spinStartTimeMs = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _isSpinning = true;
      _spinFinalized = false; // Clear finalized flag for new spin
      _winningReels = {};
      _winningPositions = {};
      _currentLinePositions = {}; // Clear line presentation positions
      _winTier = '';
      _currentDisplayTier = ''; // Reset display tier for new spin
      _displayedWinAmount = 0;
      _targetWinAmount = 0;
      _particles.clear();
      // Reset anticipation/near miss state
      _isAnticipation = false;
      _isNearMiss = false;
      _anticipationReels = {};
      _nearMissPositions = {};
      // V9: Reset scatter tracking for condition-based anticipation
      _scatterReels = {};
      // Clear reel stopped flags for new spin
      _reelStoppedFlags.clear();
      // Reset IGT-style sequential buffer for new spin
      _nextExpectedReelIndex = 0;
      _pendingReelStops.clear();
    });

    // Hide win overlay
    _winAmountController.reverse();
    _winCounterController.reset();

    // Set target grid for final display
    if (result != null) {
      _targetGrid = List.generate(widget.reels, (r) {
        if (r < result.grid.length) {
          return List.generate(widget.rows, (row) {
            if (row < result.grid[r].length) return result.grid[r][row];
            return _random.nextInt(10);
          });
        }
        return List.generate(widget.rows, (_) => _random.nextInt(10));
      });
    }

    // Generate random symbols for spinning blur effect
    _spinSymbols = List.generate(
      widget.reels,
      (_) => List.generate(30, (_) => _random.nextInt(10)),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // PROFESSIONAL ANIMATION START
    // Set target symbols and start spin via controller
    // ═══════════════════════════════════════════════════════════════════════════
    _reelAnimController.setTargetGrid(_targetGrid);
    _reelAnimController.startSpin();

    // NOTE: SPIN_START audio is triggered by SlotLabProvider._playStage()
    // DO NOT trigger here - causes double trigger!
    debugPrint('[SlotPreview] 🎰 SPIN STARTED (visual only, audio via provider)');
  }

  void _finalizeSpin(SlotLabSpinResult result) {
    debugPrint('[SlotPreview] ✅ FINALIZE SPIN — _isSpinning=$_isSpinning, _spinFinalized=$_spinFinalized');

    // Guard against double finalize
    if (_spinFinalized) {
      debugPrint('[SlotPreview] ⚠️ _finalizeSpin SKIPPED: already finalized');
      return;
    }

    // Stop visual animation ONLY if still spinning (avoid duplicate callback from stopImmediately)
    if (_reelAnimController.isSpinning) {
      debugPrint('[SlotPreview] Stopping animation controller...');
      _reelAnimController.stopImmediately();
    } else {
      debugPrint('[SlotPreview] Animation already stopped, skipping stopImmediately()');
    }

    // Stop any existing win line presentation
    _stopWinLinePresentation();

    setState(() {
      for (int r = 0; r < widget.reels && r < result.grid.length; r++) {
        for (int row = 0; row < widget.rows && row < result.grid[r].length; row++) {
          _displayGrid[r][row] = result.grid[r][row];
        }
      }

      _isSpinning = false;
      _spinFinalized = true; // CRITICAL: Prevent re-trigger in _onProviderUpdate

      if (result.isWin) {
        // Collect all winning positions (for total highlight if needed)
        for (final lineWin in result.lineWins) {
          for (final pos in lineWin.positions) {
            if (pos.length >= 2) {
              _winningReels.add(pos[0]);
              _winningPositions.add('${pos[0]},${pos[1]}');
            } else if (pos.isNotEmpty) {
              _winningReels.add(pos[0]);
            }
          }
        }

        // Determine win tier and show overlay
        _targetWinAmount = result.totalWin.toDouble();
        _winTier = _getWinTier(result.totalWin);

        // ═══════════════════════════════════════════════════════════════════════
        // V9: WIN PRESENTATION SYSTEM
        // Per user spec:
        // - SMALL wins: "WIN!" plaque with counter (this IS the total win plaque)
        // - BIG+ wins: Tier progression (BIG WIN! → SUPER WIN! → ...) with counter
        //   The big win plaque IS the total win for big wins (no separate plaque)
        // ═══════════════════════════════════════════════════════════════════════

        // Store lineWins for later use in callback
        final lineWinsForPhase3 = result.lineWins;

        // Symbol highlight duration before plaque starts
        const symbolHighlightMs = 1050; // 3 cycles × 350ms

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 1: SYMBOL HIGHLIGHT (0ms → symbolHighlightMs)
        // Winning symbols glow and pulse - builds anticipation
        // ═══════════════════════════════════════════════════════════════════════
        eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');
        _startSymbolPulseAnimation();
        _triggerStaggeredSymbolPopups(); // V6: Staggered popup effect

        // ═══════════════════════════════════════════════════════════════════════
        // WIN PRESENTATION AUDIO — Single audio tier based on win/bet ratio
        // Triggers WIN_PRESENT_1 through WIN_PRESENT_6 with varying durations
        // This IS the win sound — no other win audio stages needed
        // ═══════════════════════════════════════════════════════════════════════
        final winPresentTier = _getWinPresentTier(result.totalWin);
        final winPresentDuration = _getWinPresentDurationMs(winPresentTier);
        eventRegistry.triggerStage('WIN_PRESENT_$winPresentTier');
        debugPrint('[SlotPreview] 🔊 WIN_PRESENT_$winPresentTier (ratio: ${(result.totalWin / widget.provider.betAmount).toStringAsFixed(2)}x, duration: ${winPresentDuration}ms)');

        debugPrint('[SlotPreview] 🎰 PHASE 1: Symbol highlight (tier: ${_winTier.isEmpty ? "SMALL" : _winTier}, duration: ${symbolHighlightMs}ms)');

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 2: WIN PLAQUE (after symbol highlight)
        // ═══════════════════════════════════════════════════════════════════════
        Future.delayed(const Duration(milliseconds: symbolHighlightMs), () {
          if (!mounted) return;

          if (_winTier.isEmpty) {
            // ═══════════════════════════════════════════════════════════════════
            // SMALL WIN (< 5x): "WIN!" total win plaque with counter, then win lines
            // Audio already triggered above via WIN_PRESENT_N
            // ═══════════════════════════════════════════════════════════════════
            debugPrint('[SlotPreview] 💰 PHASE 2: Total win plaque (win: ${result.totalWin})');

            // Show plaque with "WIN!" label (empty tier = small win)
            setState(() {
              _currentDisplayTier = '';
            });
            _winAmountController.forward(from: 0);

            // Start rollup with callback for win lines
            _startTierBasedRollupWithCallback('', () {
              if (!mounted) return;

              // Fade out plaque
              _winAmountController.reverse().then((_) {
                if (!mounted) return;

                // Start win line presentation
                if (lineWinsForPhase3.isNotEmpty) {
                  debugPrint('[SlotPreview] 🎰 PHASE 3: Win lines (after small win)');
                  _startWinLinePresentation(lineWinsForPhase3);
                }
              });
            });
          } else {
            // ═══════════════════════════════════════════════════════════════════
            // BIG+ WIN: Tier progression plaque with counter (this IS the total win)
            // BIG_WIN_INTRO → BIG → SUPER → ... → BIG_WIN_END → Win lines
            // No separate "total win" plaque — the tier plaque shows the counter
            // ═══════════════════════════════════════════════════════════════════
            debugPrint('[SlotPreview] 🎰 PHASE 2: Tier progression (${result.totalWin}) → $_winTier');

            // Start tier progression — this handles everything:
            // - BIG_WIN_INTRO
            // - Each tier display (4s each)
            // - BIG_WIN_END
            // - Plaque fade-out
            // - Win lines (Phase 3)
            _startTierProgression(_winTier, lineWinsForPhase3, null);
          }
        });

        // Spawn particles for ALL wins (bigger = more particles)
        _spawnWinParticles(_winTier);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // WIN LINE PRESENTATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Start cycling through winning lines one by one
  void _startWinLinePresentation(List<LineWin> lineWins) {
    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Must use setState() to trigger rebuild and show win lines!
    // Without setState(), _isShowingWinLines and _currentLinePositions changes
    // are not reflected in the UI
    // ═══════════════════════════════════════════════════════════════════════════
    setState(() {
      _lineWinsForPresentation = lineWins;
      _currentPresentingLineIndex = 0;
      _isShowingWinLines = true;
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // SAKRIJ TIER PLAKETU — win lines se prikazuju bez overlay-a
    // Ostaju SAMO vizualne linije, BEZ info o simbolima
    // ═══════════════════════════════════════════════════════════════════════════
    _winAmountController.reverse();

    // Show first line immediately (also needs setState for _currentLinePositions)
    _showCurrentWinLineWithSetState();

    // Start cycling timer
    _winLineCycleTimer?.cancel();
    _winLineCycleTimer = Timer.periodic(_winLineCycleDuration, (_) {
      if (!mounted || !_isShowingWinLines) {
        _winLineCycleTimer?.cancel();
        return;
      }
      _advanceToNextWinLine();
    });

    debugPrint('[SlotPreview] 🎯 Started win line presentation: ${lineWins.length} lines (counter hidden)');
  }

  /// Stop win line presentation
  void _stopWinLinePresentation() {
    _winLineCycleTimer?.cancel();
    _winLineCycleTimer = null;
    _stopRollupTicks(); // Also stop any ongoing rollup audio
    _isShowingWinLines = false;
    _lineWinsForPresentation = [];
    _currentPresentingLineIndex = 0;
    _currentLinePositions = {};
  }

  /// Advance to next win line — NO LOOPING, single pass through all lines
  void _advanceToNextWinLine() {
    if (_lineWinsForPresentation.isEmpty) return;

    final nextIndex = _currentPresentingLineIndex + 1;

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: NO LOOPING — stop after showing all unique lines ONCE
    // When last line is reached, stop the timer and end presentation
    // ═══════════════════════════════════════════════════════════════════════════
    if (nextIndex >= _lineWinsForPresentation.length) {
      debugPrint('[SlotPreview] 🏁 Win line presentation COMPLETE (${_lineWinsForPresentation.length} lines shown once)');
      _stopWinLinePresentation();
      return;
    }

    setState(() {
      _currentPresentingLineIndex = nextIndex;
      _showCurrentWinLine(); // Audio triggered inside _showCurrentWinLine()
    });
  }

  /// Update visual state for currently shown win line
  void _showCurrentWinLine({bool triggerAudio = true}) {
    if (_lineWinsForPresentation.isEmpty) return;

    final currentLine = _lineWinsForPresentation[_currentPresentingLineIndex];

    // Update positions for current line only
    _currentLinePositions = {};
    for (final pos in currentLine.positions) {
      if (pos.length >= 2) {
        _currentLinePositions.add('${pos[0]},${pos[1]}');
      }
    }

    // Trigger WIN_LINE_SHOW audio (for first line and cycling)
    if (triggerAudio) {
      eventRegistry.triggerStage('WIN_LINE_SHOW');
    }

    debugPrint('[SlotPreview] 🎯 Showing line ${_currentPresentingLineIndex + 1}/${_lineWinsForPresentation.length}: '
        '${currentLine.symbolName} x${currentLine.matchCount} = ${currentLine.winAmount}');
  }

  /// Update visual state for currently shown win line WITH setState
  /// Used for initial line presentation to trigger UI rebuild
  void _showCurrentWinLineWithSetState({bool triggerAudio = true}) {
    if (_lineWinsForPresentation.isEmpty) return;

    final currentLine = _lineWinsForPresentation[_currentPresentingLineIndex];

    // Update positions for current line only - WITH setState to trigger rebuild
    setState(() {
      _currentLinePositions = {};
      for (final pos in currentLine.positions) {
        if (pos.length >= 2) {
          _currentLinePositions.add('${pos[0]},${pos[1]}');
        }
      }
    });

    // Trigger WIN_LINE_SHOW audio (for first line and cycling)
    if (triggerAudio) {
      eventRegistry.triggerStage('WIN_LINE_SHOW');
    }

    debugPrint('[SlotPreview] 🎯 [setState] Showing line ${_currentPresentingLineIndex + 1}/${_lineWinsForPresentation.length}: '
        '${currentLine.symbolName} x${currentLine.matchCount} = ${currentLine.winAmount}');
  }

  /// Get current line win for display (or null if no presentation active)
  LineWin? get _currentPresentingLine {
    if (!_isShowingWinLines || _lineWinsForPresentation.isEmpty) return null;
    return _lineWinsForPresentation[_currentPresentingLineIndex];
  }

  /// Get win tier based on win-to-bet ratio (industry standard)
  /// Industry standard progression (Zynga, NetEnt, Pragmatic Play):
  /// - SMALL: < 5x — no plaque, just counter
  /// - BIG WIN: 5x - 15x — FIRST major tier (industry standard)
  /// - SUPER WIN: 15x - 30x — second tier
  /// - MEGA WIN: 30x - 60x — third tier
  /// - EPIC WIN: 60x - 100x — fourth tier
  /// - ULTRA WIN: 100x+ — maximum celebration
  String _getWinTier(double totalWin) {
    // Use bet from provider, fallback to 1.0 for ratio calculation
    final bet = widget.provider.betAmount;
    if (bet <= 0) return ''; // No bet = no tier

    final ratio = totalWin / bet;
    if (ratio >= 100) return 'ULTRA';
    if (ratio >= 50) return 'EPIC';
    if (ratio >= 25) return 'MEGA';
    if (ratio >= 10) return 'SUPER';
    if (ratio >= 5) return 'BIG';
    // Small wins (below 5x) return empty - no plaque shown
    return '';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN PRESENTATION TIER SYSTEM — Audio based on win/bet ratio
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // WIN_PRESENT_1: win ≤ 1x bet   — 0.5s duration (tiny win)
  // WIN_PRESENT_2: 1x < win ≤ 2x  — 1.0s duration
  // WIN_PRESENT_3: 2x < win ≤ 4x  — 1.5s duration
  // WIN_PRESENT_4: 4x < win ≤ 8x  — 2.0s duration
  // WIN_PRESENT_5: 8x < win ≤ 13x — 3.0s duration
  // WIN_PRESENT_6: win > 13x      — 4.0s duration (mega/epic/ultra)
  //
  // This is THE win presentation audio — replaces all other win sound stages
  // Visual tier (BIG WIN!, MEGA WIN!, etc.) is handled separately
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get WIN_PRESENT tier (1-6) based on win/bet ratio
  /// Returns tier number for stage name: WIN_PRESENT_1, WIN_PRESENT_2, etc.
  int _getWinPresentTier(double totalWin) {
    final bet = widget.provider.betAmount;
    if (bet <= 0) return 1; // Fallback to tier 1

    final ratio = totalWin / bet;
    if (ratio > 13) return 6;      // WIN_PRESENT_6: > 13x (mega/epic/ultra)
    if (ratio > 8) return 5;       // WIN_PRESENT_5: > 8x and ≤ 13x
    if (ratio > 4) return 4;       // WIN_PRESENT_4: > 4x and ≤ 8x
    if (ratio > 2) return 3;       // WIN_PRESENT_3: > 2x and ≤ 4x
    if (ratio > 1) return 2;       // WIN_PRESENT_2: > 1x and ≤ 2x
    return 1;                       // WIN_PRESENT_1: ≤ 1x (tiny win)
  }

  /// Get WIN_PRESENT duration in milliseconds for the given tier
  int _getWinPresentDurationMs(int tier) {
    return switch (tier) {
      1 => 500,   // 0.5s
      2 => 1000,  // 1.0s
      3 => 1500,  // 1.5s
      4 => 2000,  // 2.0s
      5 => 3000,  // 3.0s
      6 => 4000,  // 4.0s
      _ => 500,   // fallback
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN AUDIO FLOW — Rollup tick sequence
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start rollup tick audio sequence during win counter animation
  void _startRollupTicks() {
    _rollupTickCount = 0;
    _rollupTickTimer?.cancel();

    // Fire ROLLUP_TICK at ~100ms intervals during the counter animation
    _rollupTickTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _rollupTickCount >= _rollupTicksTotal) {
        timer.cancel();
        if (mounted) {
          // ROLLUP_END when counter finishes
          eventRegistry.triggerStage('ROLLUP_END');
          debugPrint('[SlotPreview] 🔊 ROLLUP_END');
        }
        return;
      }

      _rollupTickCount++;
      eventRegistry.triggerStage('ROLLUP_TICK');
    });

    debugPrint('[SlotPreview] 🔊 ROLLUP started ($_rollupTicksTotal ticks)');
  }

  /// Stop rollup ticks (on early interrupt)
  void _stopRollupTicks() {
    _rollupTickTimer?.cancel();
    _rollupTickTimer = null;
    _rollupTickCount = 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 1: SYMBOL PULSE ANIMATION — Industry standard 3 cycles
  // ═══════════════════════════════════════════════════════════════════════════

  int _symbolPulseCount = 0;

  /// Start symbol pulse animation with 3 cycles (industry standard)
  /// V6: Now includes staggered popup effect for winning symbols
  void _startSymbolPulseAnimation() {
    _symbolPulseCount = 0;

    // V6: Start staggered popup for each winning position
    _triggerStaggeredSymbolPopups();

    _runSymbolPulseCycle();
  }

  /// V6: Trigger staggered popup animations for winning symbols
  /// Each symbol pops 50ms after the previous one (left to right, top to bottom)
  void _triggerStaggeredSymbolPopups() {
    // Sort win positions for consistent left-to-right, top-to-bottom order
    // Format is "reel,row"
    final sortedPositions = _winningPositions.toList()..sort((a, b) {
      final partsA = a.split(',').map(int.parse).toList();
      final partsB = b.split(',').map(int.parse).toList();
      // Sort by reel (column) first, then row
      if (partsA[0] != partsB[0]) return partsA[0].compareTo(partsB[0]);
      return partsA[1].compareTo(partsB[1]);
    });

    // Clear any previous popup state
    _symbolPopScale.clear();
    _symbolPopRotation.clear();

    // Trigger staggered popups
    for (int i = 0; i < sortedPositions.length; i++) {
      final position = sortedPositions[i];
      final delay = i * _symbolPopStaggerMs;

      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        _animateSymbolPop(position);
      });
    }
  }

  /// V6: Animate a single symbol popup (scale 1.0 → 1.15 → 1.0 with micro-wiggle)
  void _animateSymbolPop(String position) {
    // Phase 1: Scale up to max (60ms)
    setState(() {
      _symbolPopScale[position] = _symbolPopMaxScale;
      _symbolPopRotation[position] = 0.03; // Small rotation (radians)
    });

    // Phase 2: Wiggle (40ms)
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() {
        _symbolPopRotation[position] = -0.03; // Wiggle other direction
      });
    });

    // Phase 3: Scale back to normal (100ms)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() {
        _symbolPopScale[position] = 1.05; // Ease down
        _symbolPopRotation[position] = 0.015;
      });
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _symbolPopScale[position] = 1.0;
        _symbolPopRotation[position] = 0.0;
      });
    });
  }

  /// Run single pulse cycle, repeats until 3 cycles complete
  void _runSymbolPulseCycle() {
    if (!mounted || _symbolPulseCount >= _symbolPulseCycles) {
      debugPrint('[SlotPreview] ✅ Symbol pulse complete ($_symbolPulseCount cycles)');
      return;
    }

    _symbolPulseCount++;
    _symbolBounceController.forward(from: 0).then((_) {
      if (mounted) {
        _symbolBounceController.reverse().then((_) {
          if (mounted) {
            _runSymbolPulseCycle(); // Recurse for next cycle
          }
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 2: TIER-BASED ROLLUP — Variable duration by win size
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start tier-based rollup with appropriate duration and tick rate
  /// V7: Now includes visual feedback (progress meter + counter shake)
  void _startTierBasedRollup(String tier) {
    _startTierBasedRollupWithCallback(tier, null);
  }

  /// Start tier-based rollup with completion callback
  /// Used for sequential win flow where win lines start after plaque fade-out
  void _startTierBasedRollupWithCallback(String tier, VoidCallback? onComplete) {
    final duration = _rollupDurationByTier[tier] ?? _defaultRollupDuration;
    final tickRate = _rollupTickRateByTier[tier] ?? _defaultRollupTickRate;
    final tickIntervalMs = (1000 / tickRate).round();
    final totalTicks = (duration / tickIntervalMs).round();

    debugPrint('[SlotPreview] 🔊 ROLLUP_START (tier: $tier, duration: ${duration}ms, ticks: $totalTicks)');

    // V7: Initialize rollup visual state
    setState(() {
      _isRollingUp = true;
      _rollupProgress = 0.0;
    });

    // Update counter controller duration dynamically
    _winCounterController.duration = Duration(milliseconds: duration);
    _winCounterController.forward(from: 0);

    // Start tick audio
    eventRegistry.triggerStage('ROLLUP_START');

    _rollupTickCount = 0;
    _rollupTickTimer?.cancel();
    _rollupTickTimer = Timer.periodic(Duration(milliseconds: tickIntervalMs), (timer) {
      if (!mounted || _rollupTickCount >= totalTicks) {
        timer.cancel();
        if (mounted) {
          // V7: End rollup visual state
          setState(() {
            _isRollingUp = false;
            _rollupProgress = 1.0;
            _counterShakeScale = 1.0;
          });
          eventRegistry.triggerStage('ROLLUP_END');
          debugPrint('[SlotPreview] 🔊 ROLLUP_END (completed $totalTicks ticks)');

          // Call completion callback if provided
          onComplete?.call();
        }
        return;
      }

      _rollupTickCount++;

      // V7: Update progress and trigger counter shake
      setState(() {
        _rollupProgress = _rollupTickCount / totalTicks;
        _counterShakeScale = 1.08; // Pulse up
      });

      // V7: Counter shake decay (quick pulse down)
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          setState(() => _counterShakeScale = 1.0);
        }
      });

      eventRegistry.triggerStage('ROLLUP_TICK');
    });
  }

  /// Start rollup tick audio for tier progression
  /// Used when tier plaque IS the total win (BIG+ wins)
  void _startTierProgressionRollupTicks(int totalDurationMs) {
    // Use tick rate based on final tier (or 8 tps as default for big wins)
    const tickRate = 8; // Slower, more dramatic ticks for big wins
    final tickIntervalMs = (1000 / tickRate).round();
    final totalTicks = (totalDurationMs / tickIntervalMs).round();

    debugPrint('[SlotPreview] 🔊 Tier progression rollup: ${totalDurationMs}ms, $totalTicks ticks');

    _rollupTickCount = 0;
    _rollupTickTimer?.cancel();
    _rollupTickTimer = Timer.periodic(Duration(milliseconds: tickIntervalMs), (timer) {
      if (!mounted || _rollupTickCount >= totalTicks) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isRollingUp = false;
            _rollupProgress = 1.0;
          });
          eventRegistry.triggerStage('ROLLUP_END');
          debugPrint('[SlotPreview] 🔊 Tier rollup ROLLUP_END');
        }
        return;
      }

      _rollupTickCount++;
      setState(() {
        _rollupProgress = _rollupTickCount / totalTicks;
        _counterShakeScale = 1.06; // Subtle pulse
      });

      // Counter shake decay
      Future.delayed(const Duration(milliseconds: 40), () {
        if (mounted) setState(() => _counterShakeScale = 1.0);
      });

      eventRegistry.triggerStage('ROLLUP_TICK');
    });
  }

  /// Format win amount with currency-style thousand separators + 2 decimals
  /// Industry standard: NetEnt, Pragmatic Play, IGT all use 2 decimal places
  /// Examples: 1234.50 → "1,234.50" | 50.00 → "50.00" | 1234567.89 → "1,234,567.89"
  String _formatWinAmount(double amount) {
    return _currencyFormatter.format(amount);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIER PROGRESSION — Progressive reveal from BIG to final tier
  // Flow: BIG_WIN_INTRO (0.5s) → BIG (4s) → SUPER (4s) → ... → BIG_WIN_END (4s) → Fade → Win Lines
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build list of tiers to progress through, from BIG up to finalTier
  List<String> _buildTierProgressionList(String finalTier) {
    final finalIndex = _allTiersInOrder.indexOf(finalTier);
    if (finalIndex < 0) return ['BIG']; // Fallback to just BIG
    return _allTiersInOrder.sublist(0, finalIndex + 1);
  }

  /// Start the tier progression sequence
  /// This shows BIG_WIN_INTRO, then progresses through each tier, then BIG_WIN_END
  /// The tier plaque IS the total win plaque — includes counter rollup
  void _startTierProgression(String finalTier, List<LineWin> lineWinsForPhase3, VoidCallback? onComplete) {
    // Build the list of tiers to show
    _tierProgressionList = _buildTierProgressionList(finalTier);
    _tierProgressionIndex = 0;
    _isInTierProgression = true;

    debugPrint('[SlotPreview] 🏆 Starting tier progression: $_tierProgressionList');

    // ═══════════════════════════════════════════════════════════════════════════
    // CALCULATE TOTAL ROLLUP DURATION
    // Rollup spans entire tier progression: intro + all tiers + most of end
    // ═══════════════════════════════════════════════════════════════════════════
    final numTiers = _tierProgressionList.length;
    final totalProgressionMs = _bigWinIntroDurationMs +
                               (numTiers * _tierDisplayDurationMs) +
                               (_bigWinEndDurationMs - 500); // Leave 500ms before fade

    debugPrint('[SlotPreview] 🏆 Rollup duration: ${totalProgressionMs}ms (${numTiers} tiers)');

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 1: BIG_WIN_INTRO (0.5s) — Entry fanfare
    // ═══════════════════════════════════════════════════════════════════════════
    eventRegistry.triggerStage('BIG_WIN_INTRO');

    // Show plaque immediately with first tier
    setState(() {
      _currentDisplayTier = _tierProgressionList.first;
      _isRollingUp = true;
      _rollupProgress = 0.0;
    });
    _winAmountController.forward(from: 0);

    // ═══════════════════════════════════════════════════════════════════════════
    // START COUNTER ROLLUP — The tier plaque IS the total win plaque
    // Counter animation + ROLLUP audio run throughout tier progression
    // ═══════════════════════════════════════════════════════════════════════════
    _winCounterController.duration = Duration(milliseconds: totalProgressionMs);
    _winCounterController.forward(from: 0);

    // Start ROLLUP audio
    eventRegistry.triggerStage('ROLLUP_START');
    _startTierProgressionRollupTicks(totalProgressionMs);

    // V8: Screen flash for dramatic entrance
    setState(() => _showScreenFlash = true);
    _screenFlashController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showScreenFlash = false);
    });

    // V8: Spawn celebration particles
    _spawnPlaqueCelebrationParticles(_tierProgressionList.first);

    debugPrint('[SlotPreview] 🏆 BIG_WIN_INTRO → showing ${_tierProgressionList.first}');

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 2: After intro (0.5s), start tier display sequence
    // ═══════════════════════════════════════════════════════════════════════════
    Future.delayed(const Duration(milliseconds: _bigWinIntroDurationMs), () {
      if (!mounted) return;
      _advanceTierProgression(lineWinsForPhase3, onComplete);
    });
  }

  /// Advance to the next tier in progression, or finish if done
  void _advanceTierProgression(List<LineWin> lineWinsForPhase3, VoidCallback? onComplete) {
    if (!mounted || !_isInTierProgression) return;

    // Trigger visual tier stage (optional — main audio is WIN_PRESENT_N)
    final currentTier = _tierProgressionList[_tierProgressionIndex];
    eventRegistry.triggerStage('WIN_TIER_$currentTier');
    debugPrint('[SlotPreview] 🏆 Tier ${_tierProgressionIndex + 1}/${_tierProgressionList.length}: $currentTier');

    // Update display
    setState(() {
      _currentDisplayTier = currentTier;
    });

    // Spawn particles for this tier
    _spawnWinParticles(currentTier);

    // ═══════════════════════════════════════════════════════════════════════════
    // After tier display duration (4s), advance to next tier or finish
    // ═══════════════════════════════════════════════════════════════════════════
    _tierProgressionTimer?.cancel();
    _tierProgressionTimer = Timer(const Duration(milliseconds: _tierDisplayDurationMs), () {
      if (!mounted) return;

      _tierProgressionIndex++;

      // Check if we have more tiers to show
      if (_tierProgressionIndex < _tierProgressionList.length) {
        // Show next tier
        _advanceTierProgression(lineWinsForPhase3, onComplete);
      } else {
        // All tiers shown — proceed to BIG_WIN_END
        _finishTierProgression(lineWinsForPhase3, onComplete);
      }
    });
  }

  /// Finish tier progression: show BIG_WIN_END, then fade plaque, then win lines
  void _finishTierProgression(List<LineWin> lineWinsForPhase3, VoidCallback? onComplete) {
    if (!mounted) return;

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 3: BIG_WIN_END (4s) — Exit celebration
    // ═══════════════════════════════════════════════════════════════════════════
    eventRegistry.triggerStage('BIG_WIN_END');
    debugPrint('[SlotPreview] 🏆 BIG_WIN_END — final tier: $_currentDisplayTier');

    _tierProgressionTimer?.cancel();
    _tierProgressionTimer = Timer(const Duration(milliseconds: _bigWinEndDurationMs), () {
      if (!mounted) return;

      _isInTierProgression = false;

      // ═══════════════════════════════════════════════════════════════════════
      // STEP 4: Fade out plaque
      // ═══════════════════════════════════════════════════════════════════════
      debugPrint('[SlotPreview] 🏆 Tier progression complete — fading plaque');
      _winAmountController.reverse().then((_) {
        if (!mounted) return;

        // ═══════════════════════════════════════════════════════════════════
        // STEP 5: Start win line presentation
        // ═══════════════════════════════════════════════════════════════════
        if (lineWinsForPhase3.isNotEmpty) {
          debugPrint('[SlotPreview] 🎰 PHASE 3: Win lines (after tier progression)');
          _startWinLinePresentation(lineWinsForPhase3);
        }

        onComplete?.call();
      });
    });
  }

  /// Stop tier progression (on early interrupt/new spin)
  void _stopTierProgression() {
    _tierProgressionTimer?.cancel();
    _tierProgressionTimer = null;
    _rollupTickTimer?.cancel(); // Also stop rollup ticks
    _isInTierProgression = false;
    _isRollingUp = false;
    _tierProgressionList = [];
    _tierProgressionIndex = 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PER-REEL ANTICIPATION EFFECTS — 2 seconds per reel with visual overlay
  // Industry standard: Anticipation slows down specific reels with visual cue
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start anticipation on a specific reel (2 second duration)
  /// Called from stage processing when ANTICIPATION_ON_X is detected
  void _startReelAnticipation(int reelIndex) {
    if (_anticipationReels.contains(reelIndex)) return; // Already anticipating

    debugPrint('[SlotPreview] 🎯 ANTICIPATION START: Reel $reelIndex (${_anticipationDurationMs}ms)');

    setState(() {
      _isAnticipation = true;
      _anticipationReels.add(reelIndex);
      _anticipationProgress[reelIndex] = 0.0;
    });

    // Trigger audio stage
    eventRegistry.triggerStage('ANTICIPATION_ON_$reelIndex', context: {'reel_index': reelIndex});

    // Update progress periodically for smooth animation
    const updateInterval = 50; // 50ms updates
    int elapsed = 0;
    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers[reelIndex] = Timer.periodic(
      const Duration(milliseconds: updateInterval),
      (timer) {
        elapsed += updateInterval;
        final progress = (elapsed / _anticipationDurationMs).clamp(0.0, 1.0);

        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _anticipationProgress[reelIndex] = progress;
        });

        // End anticipation after 2 seconds
        if (elapsed >= _anticipationDurationMs) {
          timer.cancel();
          _endReelAnticipation(reelIndex);
        }
      },
    );
  }

  /// End anticipation on a specific reel
  void _endReelAnticipation(int reelIndex) {
    debugPrint('[SlotPreview] 🎯 ANTICIPATION END: Reel $reelIndex');

    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers.remove(reelIndex);

    if (!mounted) return;

    setState(() {
      _anticipationReels.remove(reelIndex);
      _anticipationProgress.remove(reelIndex);
      // Update global flag
      _isAnticipation = _anticipationReels.isNotEmpty;
    });

    // Trigger audio stage
    eventRegistry.triggerStage('ANTICIPATION_OFF_$reelIndex', context: {'reel_index': reelIndex});
  }

  /// Start anticipation effect - auto-starts on last reel(s) when potential big win
  void _startAnticipation(SlotLabSpinResult? result) {
    // Start anticipation on last 1-2 reels sequentially
    final anticipationReels = [widget.reels - 2, widget.reels - 1];

    for (int i = 0; i < anticipationReels.length; i++) {
      final reelIndex = anticipationReels[i];
      if (reelIndex >= 0) {
        // Stagger start times slightly for more dramatic effect
        Future.delayed(Duration(milliseconds: i * 200), () {
          if (mounted && _isSpinning) {
            _startReelAnticipation(reelIndex);
          }
        });
      }
    }
  }

  /// Stop all anticipation effects
  void _stopAnticipation() {
    // Cancel all timers
    for (final timer in _anticipationTimers.values) {
      timer.cancel();
    }
    _anticipationTimers.clear();

    setState(() {
      _isAnticipation = false;
      _anticipationReels = {};
      _anticipationProgress.clear();
    });
  }

  /// Stop anticipation on a specific reel (e.g., when it lands)
  void _stopReelAnticipation(int reelIndex) {
    if (!_anticipationReels.contains(reelIndex)) return;
    _endReelAnticipation(reelIndex);
  }

  /// Trigger near miss visual effect
  void _triggerNearMiss(SlotLabSpinResult? result) {
    setState(() {
      _isNearMiss = true;
      // Near miss typically highlights the symbol that "just missed"
      // Usually the last reel, middle row
      _nearMissPositions = {'${widget.reels - 1},1'};
    });

    _nearMissController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _isNearMiss = false;
          _nearMissPositions = {};
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CASCADE / TUMBLE EFFECTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start cascade/tumble sequence
  void _startCascade(SlotLabSpinResult? result) {
    setState(() {
      _isCascading = true;
      _cascadeStep = 0;
      // Mark winning positions for pop animation
      _cascadePopPositions = Set.from(_winningPositions);
    });
  }

  /// Animate a cascade step (symbols popping and new ones falling)
  void _cascadeStepAnimation(SlotLabSpinResult? result) {
    setState(() {
      _cascadeStep++;
    });

    // Pop animation for winning symbols
    _cascadePopController.forward(from: 0).then((_) {
      if (mounted) {
        // After pop, spawn particles and reset
        _spawnCascadeParticles();
        setState(() {
          _cascadePopPositions = {};
        });
        _cascadePopController.reset();
      }
    });
  }

  /// Spawn particles for cascade pop effect
  void _spawnCascadeParticles() {
    for (final pos in _cascadePopPositions) {
      final parts = pos.split(',');
      if (parts.length != 2) continue;
      final reelIdx = int.tryParse(parts[0]) ?? 0;
      final rowIdx = int.tryParse(parts[1]) ?? 0;

      // Calculate normalized position
      final x = (reelIdx + 0.5) / widget.reels;
      final y = (rowIdx + 0.5) / widget.rows;

      // Spawn burst of particles at symbol position
      for (int i = 0; i < 5; i++) {
        _particles.add(_particlePool.acquire(
          x: x,
          y: y,
          vx: (_random.nextDouble() - 0.5) * 0.03,
          vy: (_random.nextDouble() - 0.5) * 0.03,
          size: _random.nextDouble() * 6 + 3,
          color: const Color(0xFFFFD700),
          type: _ParticleType.sparkle,
          rotation: _random.nextDouble() * math.pi * 2,
          rotationSpeed: (_random.nextDouble() - 0.5) * 0.3,
        ));
      }
    }
    _particleController.forward(from: 0);
  }

  /// End cascade sequence
  void _endCascade() {
    setState(() {
      _isCascading = false;
      _cascadeStep = 0;
      _cascadePopPositions = {};
    });
  }

  void _spawnWinParticles(String tier) {
    final particleCount = switch (tier) {
      'ULTRA' => 60,
      'EPIC' => 45,
      'MEGA' => 30,
      'BIG' => 20,
      _ => 10,
    };

    // Use object pool to avoid GC pressure during win animations
    for (int i = 0; i < particleCount; i++) {
      _particles.add(_particlePool.acquire(
        x: _random.nextDouble(),
        y: _random.nextDouble() * 0.3 + 0.35, // Spawn around center
        vx: (_random.nextDouble() - 0.5) * 0.02,
        vy: -_random.nextDouble() * 0.015 - 0.005,
        size: _random.nextDouble() * 8 + 4,
        color: _getParticleColor(tier),
        type: _random.nextBool() ? _ParticleType.coin : _ParticleType.sparkle,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.2,
      ));
    }

    _particleController.forward(from: 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V8: PLAQUE CELEBRATION PARTICLES — Burst from center on plaque entrance
  // Industry standard: explosion of gold coins and sparkles for dramatic effect
  // ═══════════════════════════════════════════════════════════════════════════
  void _spawnPlaqueCelebrationParticles(String tier) {
    final particleCount = switch (tier) {
      'ULTRA' => 80,
      'EPIC' => 60,
      'MEGA' => 45,
      'SUPER' => 30,
      'BIG' => 20,
      _ => 10,
    };

    // Burst from center outward in all directions
    for (int i = 0; i < particleCount; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 0.02 + _random.nextDouble() * 0.03;

      _particles.add(_particlePool.acquire(
        x: 0.5, // Center X
        y: 0.45, // Center Y (slightly above middle for plaque position)
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 0.01, // Slight upward bias
        size: _random.nextDouble() * 10 + 5,
        color: _getParticleColor(tier),
        type: i % 3 == 0 ? _ParticleType.coin : _ParticleType.sparkle,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.4,
      ));
    }

    _particleController.forward(from: 0);
  }

  Color _getParticleColor(String tier) {
    final colors = switch (tier) {
      'ULTRA' => [const Color(0xFFFF4080), const Color(0xFFFF66FF), const Color(0xFFFFD700)],
      'EPIC' => [const Color(0xFFE040FB), const Color(0xFFFF66FF), const Color(0xFF40C8FF)],
      'MEGA' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFF9040)],
      'BIG' => [const Color(0xFF40FF90), const Color(0xFF4CAF50), const Color(0xFFFFEB3B)],
      _ => [const Color(0xFFFFD700)],
    };
    return colors[_random.nextInt(colors.length)];
  }

  @override
  Widget build(BuildContext context) {
    // Check for reduced motion preference (accessibility)
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // ═══════════════════════════════════════════════════════════════════════════
    // KEYBOARD HANDLING — SPACE to stop/skip spin
    // ═══════════════════════════════════════════════════════════════════════════
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
          _handleSpaceKey();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final borderColor = _winningReels.isNotEmpty
              ? _getWinBorderColor()
              : _isSpinning
                  ? FluxForgeTheme.accentBlue.withOpacity(0.4)
                  : const Color(0xFF2A2A38);

          // ═══════════════════════════════════════════════════════════════════════
          // V2: Screen Shake — subtle shake when last reel lands
          // ═══════════════════════════════════════════════════════════════════════
          final shakeOffsetX = _screenShakeActive ? (_random.nextDouble() - 0.5) * 4 : 0.0;
          final shakeOffsetY = _screenShakeActive ? (_random.nextDouble() - 0.5) * 3 : 0.0;

          return Transform.translate(
          offset: Offset(shakeOffsetX, shakeOffsetY),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              // Main slot container
              Container(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0D0D14), Color(0xFF080810), Color(0xFF050508)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 2),
                  boxShadow: _winningReels.isNotEmpty
                      ? [
                          BoxShadow(
                            color: _getWinGlowColor().withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _buildReelTable(constraints.maxWidth - 12, constraints.maxHeight - 12),
                ),
              ),

              // ═══════════════════════════════════════════════════════════════════════
              // V5: BIG WIN BACKGROUND EFFECT — Industry standard celebration atmosphere
              // Vignette (dark edges) + Color wash (tier-colored glow)
              // Only shows for BIG tier and above
              // ═══════════════════════════════════════════════════════════════════════
              if (_winTier.isNotEmpty && !reduceMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _winPulseAnimation,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _BigWinBackgroundPainter(
                            tier: _winTier,
                            pulseValue: _winPulseAnimation.value,
                            tierColor: _getWinGlowColor(),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Win line layer — draws connecting lines between winning symbols
              if (_isShowingWinLines && _currentPresentingLine != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WinLinePainter(
                      positions: _currentPresentingLine!.positions,
                      reelCount: widget.reels,
                      rowCount: widget.rows,
                      pulseValue: _winPulseAnimation.value,
                      lineColor: _getWinGlowColor(),
                    ),
                  ),
                ),

              // Particle layer (respects reduced motion preference)
              if (_particles.isNotEmpty && !reduceMotion)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ParticlePainter(particles: _particles),
                  ),
                ),

              // ═══════════════════════════════════════════════════════════════════════
              // V8: SCREEN FLASH — Dramatic entrance effect for BIG+ wins
              // Quick white/gold flash when plaque appears
              // ═══════════════════════════════════════════════════════════════════════
              if (_showScreenFlash && !reduceMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _screenFlashOpacity,
                      builder: (context, _) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 0.8,
                              colors: [
                                _getWinGlowColor().withOpacity(_screenFlashOpacity.value * 0.7),
                                Colors.white.withOpacity(_screenFlashOpacity.value * 0.3),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Win amount overlay — shown for ALL wins (small and big)
              // The overlay itself checks _winAmountOpacity.value to hide when faded out
              // BUG FIX: Previously only showed for _winTier.isNotEmpty (big wins)
              // Now shows when: tier exists OR win amount is being displayed
              if (_winTier.isNotEmpty || _targetWinAmount > 0)
                Positioned.fill(
                  child: _buildWinOverlay(constraints),
                ),
            ],
          ),
        ),
        ); // Close Transform.translate for screen shake
        },
      ),
    );
  }

  /// Handle SPACE key — Skip/stop spin immediately
  void _handleSpaceKey() {
    if (_isSpinning) {
      debugPrint('[SlotPreview] ⏹ SPACE pressed — stopping all reels immediately');

      // 1. Stop visual animation immediately
      _reelAnimController.stopImmediately();

      // 2. Update display grid to target (final) values
      setState(() {
        for (int r = 0; r < widget.reels && r < _targetGrid.length; r++) {
          for (int row = 0; row < widget.rows && row < _targetGrid[r].length; row++) {
            _displayGrid[r][row] = _targetGrid[r][row];
          }
        }
      });

      // 3. Finalize spin (sets _spinFinalized = true, _isSpinning = false)
      final result = widget.provider.lastResult;
      if (result != null) {
        _finalizeSpin(result);
      }

      // 4. THEN stop provider stage timers (notifies listeners)
      // CRITICAL ORDER: _finalizeSpin() MUST be called BEFORE stopStagePlayback()!
      // This way _onProviderUpdate() sees _spinFinalized = true when !isPlaying,
      // allowing it to reset _spinFinalized = false for the next spin.
      widget.provider.stopStagePlayback();
    }
  }

  /// Get the tier to display (current tier during progression, or final tier)
  String get _displayTier => _currentDisplayTier.isNotEmpty ? _currentDisplayTier : _winTier;

  Color _getWinBorderColor() {
    final baseColor = switch (_displayTier) {
      'ULTRA' => const Color(0xFFFF4080),
      'EPIC' => const Color(0xFFE040FB),
      'MEGA' => const Color(0xFFFFD700),
      'BIG' => FluxForgeTheme.accentGreen,
      _ => FluxForgeTheme.accentGreen,
    };
    return baseColor.withOpacity(_winPulseAnimation.value);
  }

  Color _getWinGlowColor() {
    return switch (_displayTier) {
      'ULTRA' => const Color(0xFFFF4080),
      'EPIC' => const Color(0xFFE040FB),
      'MEGA' => const Color(0xFFFFD700),
      'BIG' => FluxForgeTheme.accentGreen,
      _ => FluxForgeTheme.accentGreen,
    };
  }

  Widget _buildWinOverlay(BoxConstraints constraints) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _winAmountScale,
        _winAmountOpacity,
        _winPulseAnimation,
        _plaqueGlowPulse, // V8: Enhanced glow animation
      ]),
      builder: (context, child) {
        if (_winAmountOpacity.value < 0.01) return const SizedBox.shrink();

        // ═══════════════════════════════════════════════════════════════════════
        // V8: ENHANCED PLAQUE ENTRANCE — More dramatic slide + scale + glow
        // Industry standard: NetEnt, Pragmatic Play dramatic celebration
        // ═══════════════════════════════════════════════════════════════════════

        // Get current display tier for visual calculations
        final tier = _displayTier;

        // Slide from above: starts at -80px for BIG+ wins
        const slideDistance = -80.0;
        final slideProgress = Curves.elasticOut.transform(_winAmountScale.value.clamp(0.0, 1.0));
        final slideOffset = (1.0 - slideProgress) * slideDistance;

        // V8: Scale with tier-based overshoot (bigger tiers = bigger overshoot)
        final scaleMultiplier = switch (tier) {
          'ULTRA' => 1.25,
          'EPIC' => 1.2,
          'MEGA' => 1.15,
          'SUPER' => 1.12,
          'BIG' => 1.1,
          _ => 1.0,
        };
        final scale = _winAmountScale.value * scaleMultiplier;

        // V8: Pulsing scale effect during display (subtle breathing)
        final pulseScale = 1.0 + (_plaqueGlowPulse.value - 0.85) * 0.03;

        return Opacity(
          opacity: _winAmountOpacity.value,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // V4: BURST EFFECT — Radiating lines behind plaque
                if (_winAmountScale.value > 0.5)
                  CustomPaint(
                    size: Size(constraints.maxWidth * 0.8, constraints.maxHeight * 0.6),
                    painter: _PlaqueBurstPainter(
                      progress: _winAmountScale.value,
                      pulseValue: _winPulseAnimation.value,
                      tierColor: _getWinGlowColor(),
                      rayCount: tier == 'ULTRA' || tier == 'EPIC' ? 16 : 12,
                    ),
                  ),
                // Main plaque with slide + scale + pulse
                Transform.translate(
                  offset: Offset(0, slideOffset),
                  child: Transform.scale(
                    scale: (scale * pulseScale).clamp(0.0, 1.35), // Allow larger scale for dramatic effect
                    child: _buildWinDisplay(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Win display — Tier plaketa ("BIG WIN!", "MEGA WIN!" itd.) SA coin counterom
  /// NE prikazuje info o simbolima/win linijama (npr. "3x Grapes")
  /// Uses _displayTier which updates during tier progression
  Widget _buildWinDisplay() {
    // Get current tier for display (updates during progression)
    final tier = _displayTier;

    // Boje bazirane na tier-u (industry standard progression)
    // BIG je prvi major tier, SUPER je drugi (umesto NICE)
    final tierColors = switch (tier) {
      'ULTRA' => [const Color(0xFFFF4080), const Color(0xFFFF66FF), const Color(0xFFFFD700)],
      'EPIC' => [const Color(0xFFE040FB), const Color(0xFFFF66FF), const Color(0xFF40C8FF)],
      'MEGA' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFF9040)],
      'SUPER' => [const Color(0xFF40C8FF), const Color(0xFF81D4FA), const Color(0xFF4FC3F7)],
      'BIG' => [const Color(0xFF40FF90), const Color(0xFF88FF88), const Color(0xFFFFEB3B)],
      _ => [const Color(0xFF40FF90), const Color(0xFF4CAF50)],
    };

    // Tier label tekst — Industry standard (Zynga, NetEnt, Pragmatic)
    // SMALL = "WIN!" (total win plaque), BIG+ = tier labels
    // BIG WIN plaque IS the total win for big wins (no separate plaque)
    final tierLabel = switch (tier) {
      'ULTRA' => 'ULTRA WIN!',
      'EPIC' => 'EPIC WIN!',
      'MEGA' => 'MEGA WIN!',
      'SUPER' => 'SUPER WIN!',
      'BIG' => 'BIG WIN!',
      _ => 'WIN!',         // Small wins and fallback
    };

    // Font size baziran na tier-u — ENHANCED za bolju vidljivost
    final tierFontSize = switch (tier) {
      'ULTRA' => 48.0,
      'EPIC' => 44.0,
      'MEGA' => 40.0,
      'SUPER' => 36.0,
      'BIG' => 32.0,
      _ => 28.0,  // Small wins and fallback
    };

    // Counter font size — POVEĆAN za bolju vidljivost
    final counterFontSize = switch (tier) {
      'ULTRA' => 72.0,
      'EPIC' => 64.0,
      'MEGA' => 56.0,
      'SUPER' => 52.0,
      'BIG' => 48.0,
      _ => 40.0,  // Small wins and fallback
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // V9: PREMIUM TIER PLAKETA + COIN COUNTER
    // Clean, modern design without loading simulation
    // Industry standard: NetEnt, Pragmatic Play, Big Time Gaming
    // ═══════════════════════════════════════════════════════════════════════════

    // V8: Animated glow intensity based on plaque pulse
    final glowIntensity = _plaqueGlowPulse.value;
    final borderOpacity = 0.6 + (glowIntensity * 0.4); // 0.6 to 1.0
    final shadowIntensity = 0.3 + (glowIntensity * 0.4); // 0.3 to 0.7

    // V8: Tier-based glow radius (bigger tiers = bigger glow)
    final baseGlowRadius = switch (tier) {
      'ULTRA' => 60.0,
      'EPIC' => 55.0,
      'MEGA' => 50.0,
      'SUPER' => 45.0,
      'BIG' => 40.0,
      _ => 30.0,
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // V10: ULTRA PREMIUM WIN PLAQUE — Casino-quality visual presentation
    // Inspired by: NetEnt, Pragmatic Play, Big Time Gaming premium slots
    // Features: Metallic gradients, glossy highlights, dramatic glow, decorative stars
    // ═══════════════════════════════════════════════════════════════════════════

    return Stack(
      alignment: Alignment.center,
      children: [
        // LAYER 1: Outer dramatic glow (largest, most diffuse)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              // Massive ambient glow
              BoxShadow(
                color: tierColors.first.withOpacity(shadowIntensity * 0.6),
                blurRadius: baseGlowRadius * 4,
                spreadRadius: 30,
              ),
              // Secondary color glow for richness
              if (tierColors.length > 1)
                BoxShadow(
                  color: tierColors[1].withOpacity(shadowIntensity * 0.3),
                  blurRadius: baseGlowRadius * 3,
                  spreadRadius: 20,
                ),
            ],
          ),
        ),

        // LAYER 2: Main plaque container with premium styling
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          decoration: BoxDecoration(
            // Premium multi-layer gradient background
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                // Top: Lighter for glossy effect
                tierColors.first.withOpacity(0.35),
                // Upper middle: Rich tier color
                tierColors.first.withOpacity(0.15),
                // Lower middle: Dark for depth
                Colors.black.withOpacity(0.85),
                // Bottom: Slight tier tint
                tierColors.first.withOpacity(0.1),
              ],
              stops: const [0.0, 0.2, 0.6, 1.0],
            ),
            borderRadius: BorderRadius.circular(24),
            // Double border effect - outer glow + inner metallic
            border: Border.all(
              color: tierColors.first.withOpacity(borderOpacity),
              width: 3,
            ),
            boxShadow: [
              // Inner shadow for depth (inset effect)
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 15,
                spreadRadius: -5,
                offset: const Offset(0, 5),
              ),
              // Primary tier glow
              BoxShadow(
                color: tierColors.first.withOpacity(shadowIntensity * 0.9),
                blurRadius: baseGlowRadius * 1.5,
                spreadRadius: 5,
              ),
              // Pulsing outer glow
              BoxShadow(
                color: tierColors.first.withOpacity(shadowIntensity * 0.6 * glowIntensity),
                blurRadius: baseGlowRadius * 2.5 * glowIntensity,
                spreadRadius: 12 * glowIntensity,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ═══════════════════════════════════════════════════════════════
              // DECORATIVE STARS ROW — Above tier label
              // ═══════════════════════════════════════════════════════════════
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDecorativeStar(tierColors.first, 16, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 20, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 24, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 20, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 16, glowIntensity),
                ],
              ),
              const SizedBox(height: 8),

              // ═══════════════════════════════════════════════════════════════
              // TIER LABEL — Premium metallic text with enhanced styling
              // ═══════════════════════════════════════════════════════════════
              Stack(
                children: [
                  // Background glow layer
                  ShaderMask(
                    shaderCallback: (bounds) => RadialGradient(
                      colors: [
                        tierColors.first,
                        tierColors.first.withOpacity(0.5),
                        Colors.transparent,
                      ],
                    ).createShader(bounds),
                    child: Text(
                      tierLabel,
                      style: TextStyle(
                        fontSize: tierFontSize + 2,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(0.3),
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                  // Main text with metallic gradient
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        tierColors.first,
                        tierColors.length > 1 ? tierColors[1] : tierColors.first,
                        Colors.white.withOpacity(0.9),
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ).createShader(bounds),
                    child: Text(
                      tierLabel,
                      style: TextStyle(
                        fontSize: tierFontSize,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 5,
                        shadows: [
                          // Sharp inner shadow for emboss effect
                          Shadow(
                            color: Colors.black.withOpacity(0.8),
                            blurRadius: 2,
                            offset: const Offset(1, 2),
                          ),
                          // Primary tier glow
                          Shadow(
                            color: tierColors.first,
                            blurRadius: 25,
                          ),
                          // Outer ambient glow
                          Shadow(
                            color: tierColors.first.withOpacity(0.7),
                            blurRadius: 40,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ═══════════════════════════════════════════════════════════════
              // WIN AMOUNT COUNTER — Ultra premium styling
              // ═══════════════════════════════════════════════════════════════
              Transform.scale(
                scale: 1.0 + (_plaqueGlowPulse.value - 0.85) * 0.06,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    // Subtle background for counter area
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.4),
                        tierColors.first.withOpacity(0.1),
                        Colors.black.withOpacity(0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: tierColors.first.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        const Color(0xFFFFD700), // Gold
                        tierColors.first,
                        Colors.white,
                      ],
                      stops: const [0.0, 0.25, 0.75, 1.0],
                    ).createShader(bounds),
                    child: Text(
                      _formatWinAmount(_targetWinAmount),
                      style: TextStyle(
                        fontSize: counterFontSize,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 3,
                        height: 1.1,
                        shadows: [
                          // Crisp inner highlight
                          const Shadow(
                            color: Colors.white,
                            blurRadius: 4,
                          ),
                          // Deep shadow for 3D effect
                          Shadow(
                            color: Colors.black.withOpacity(0.9),
                            blurRadius: 3,
                            offset: const Offset(2, 3),
                          ),
                          // Primary glow
                          Shadow(
                            color: tierColors.first.withOpacity(0.95),
                            blurRadius: 35,
                          ),
                          // Gold accent glow
                          const Shadow(
                            color: Color(0xFFFFD700),
                            blurRadius: 25,
                          ),
                          // Pulsing outer glow
                          Shadow(
                            color: tierColors.first.withOpacity(glowIntensity * 0.9),
                            blurRadius: 60 * glowIntensity,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ═══════════════════════════════════════════════════════════════
              // DECORATIVE STARS ROW — Below counter
              // ═══════════════════════════════════════════════════════════════
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDecorativeStar(tierColors.first, 14, glowIntensity),
                  const SizedBox(width: 6),
                  _buildDecorativeStar(tierColors.first, 18, glowIntensity),
                  const SizedBox(width: 6),
                  _buildDecorativeStar(tierColors.first, 14, glowIntensity),
                ],
              ),
            ],
          ),
        ),

        // LAYER 3: Glossy highlight overlay (top shine)
        Positioned(
          top: 0,
          left: 20,
          right: 20,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.25),
                  Colors.white.withOpacity(0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build decorative star for premium plaque
  /// Animated with glow pulse for dynamic effect
  Widget _buildDecorativeStar(Color color, double size, double glowIntensity) {
    return Container(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow behind star
          Container(
            width: size * 0.8,
            height: size * 0.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6 * glowIntensity),
                  blurRadius: size * 0.5,
                  spreadRadius: size * 0.1,
                ),
              ],
            ),
          ),
          // Star icon
          Icon(
            Icons.star,
            size: size,
            color: color,
            shadows: [
              Shadow(
                color: Colors.white.withOpacity(0.8),
                blurRadius: 2,
              ),
              Shadow(
                color: color,
                blurRadius: 8,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build reel grid using Table for precise layout without overflow
  Widget _buildReelTable(double availableWidth, double availableHeight) {
    // Calculate SQUARE cell size - leave space on sides for other elements
    final cellWidth = availableWidth / widget.reels;
    final cellHeight = availableHeight / widget.rows;
    final cellSize = math.min(cellWidth, cellHeight) * 0.82; // Smaller to leave space L/R

    // Calculate table dimensions for overlay positioning
    final tableWidth = cellSize * widget.reels;
    final tableHeight = cellSize * widget.rows;
    final tableOffsetX = (availableWidth - tableWidth) / 2;
    final tableOffsetY = (availableHeight - tableHeight) / 2;

    return Stack(
      children: [
        // Main table
        Center(
          child: Table(
            defaultColumnWidth: FixedColumnWidth(cellSize),
            children: List.generate(widget.rows, (rowIndex) {
              return TableRow(
                children: List.generate(widget.reels, (reelIndex) {
                  return _buildSymbolCell(reelIndex, rowIndex, cellSize);
                }),
              );
            }),
          ),
        ),

        // Per-reel anticipation overlays
        ..._anticipationReels.map((reelIndex) {
          final progress = _anticipationProgress[reelIndex] ?? 0.0;
          final reelX = tableOffsetX + (reelIndex * cellSize);

          return Positioned(
            left: reelX,
            top: tableOffsetY - 30, // Above the reel
            width: cellSize,
            child: _buildAnticipationOverlay(reelIndex, progress, cellSize, tableHeight),
          );
        }),
      ],
    );
  }

  /// Build anticipation overlay for a specific reel
  Widget _buildAnticipationOverlay(int reelIndex, double progress, double width, double tableHeight) {
    final pulseValue = _anticipationPulse.value;
    final color = const Color(0xFFFFD700); // Gold

    return AnimatedBuilder(
      animation: _anticipationPulse,
      builder: (context, child) {
        // Glowing border animation around the reel - no progress bar or loading sign
        return Container(
          width: width + 8, // Slightly wider than reel for border visibility
          height: tableHeight + 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // Pulsing outer glow
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(pulseValue * 0.8),
                blurRadius: 20 + (pulseValue * 15),
                spreadRadius: 2 + (pulseValue * 4),
              ),
              BoxShadow(
                color: color.withOpacity(pulseValue * 0.5),
                blurRadius: 40 + (pulseValue * 20),
                spreadRadius: 4 + (pulseValue * 6),
              ),
            ],
            // Animated gradient border
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withOpacity(pulseValue * 0.15),
                Colors.transparent,
                color.withOpacity(pulseValue * 0.15),
              ],
            ),
            border: Border.all(
              color: color.withOpacity(0.7 + pulseValue * 0.3),
              width: 3 + pulseValue * 2,
            ),
          ),
        );
      },
    );
  }

  /// Rectangular cell version - allows non-square cells to fill more space
  /// Uses PROFESSIONAL REEL ANIMATION SYSTEM for precise timing
  Widget _buildSymbolCellRect(int reelIndex, int rowIndex, double cellWidth, double cellHeight) {
    final reelState = _reelAnimController.getReelState(reelIndex);
    final posKey = '$reelIndex,$rowIndex';

    // When win line presentation is active, only highlight CURRENT line positions
    // Otherwise highlight all winning positions
    final isWinningPosition = _isShowingWinLines
        ? _currentLinePositions.contains(posKey)
        : _winningPositions.contains(posKey);
    final isWinningReel = _winningReels.contains(reelIndex);
    final isAnticipationReel = _anticipationReels.contains(reelIndex);
    final isNearMissPosition = _nearMissPositions.contains(posKey);
    final isCascadePopPosition = _cascadePopPositions.contains(posKey);

    // Determine if reel is visually spinning
    final isReelSpinning = reelState.phase != ReelPhase.idle &&
                           reelState.phase != ReelPhase.stopped;

    // For symbol content, use the smaller dimension to keep symbols proportional
    final symbolSize = math.min(cellWidth, cellHeight);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _winPulseAnimation,
        _symbolBounceAnimation,
        _anticipationPulse,
        _nearMissShake,
        _cascadePopAnimation,
      ]),
      builder: (context, child) {
        // Calculate bounce offset for winning symbols
        double bounceOffset = 0;
        double glowIntensity = 0;
        double shakeOffset = 0;
        double cascadeScale = 1.0;
        double cascadeOpacity = 1.0;

        // Professional bounce landing from animation controller
        if (reelState.phase == ReelPhase.bouncing) {
          bounceOffset = reelState.bounceOffset;
        } else if (isWinningPosition && !isReelSpinning) {
          final bounceValue = _symbolBounceAnimation.value;
          bounceOffset = math.sin(bounceValue * math.pi) * -8;
          glowIntensity = _winPulseAnimation.value;
        }

        if (isNearMissPosition && _isNearMiss) {
          shakeOffset = math.sin(_nearMissShake.value * math.pi * 6) * 4 *
              (1 - _nearMissShake.value);
        }

        if (isCascadePopPosition && _isCascading) {
          cascadeScale = _cascadePopAnimation.value;
          cascadeOpacity = _cascadePopAnimation.value;
        }

        Color borderColor;
        double borderWidth;

        if (isWinningPosition) {
          borderColor = _getWinGlowColor().withOpacity(_winPulseAnimation.value);
          borderWidth = 2.5;
        } else if (isNearMissPosition && _isNearMiss) {
          borderColor = const Color(0xFFFF4060).withOpacity(0.8);
          borderWidth = 2.5;
        } else if (isAnticipationReel && _isAnticipation && isReelSpinning) {
          borderColor = const Color(0xFFFFD700).withOpacity(_anticipationPulse.value);
          borderWidth = 2.0;
        } else if (isWinningReel) {
          borderColor = FluxForgeTheme.accentGreen.withOpacity(_winPulseAnimation.value * 0.5);
          borderWidth = 1.5;
        } else {
          borderColor = const Color(0xFF2A2A38);
          borderWidth = 1;
        }

        List<BoxShadow>? shadows;
        if (isWinningPosition && glowIntensity > 0) {
          shadows = [
            BoxShadow(
              color: _getWinGlowColor().withOpacity(glowIntensity * 0.6),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ];
        } else if (isNearMissPosition && _isNearMiss) {
          shadows = [
            BoxShadow(
              color: const Color(0xFFFF4060).withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 3,
            ),
          ];
        } else if (isAnticipationReel && _isAnticipation && isReelSpinning) {
          shadows = [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(_anticipationPulse.value * 0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ];
        }

        // ═══════════════════════════════════════════════════════════════════════
        // V2: Landing Impact — Get landing scale for this reel
        // ═══════════════════════════════════════════════════════════════════════
        final landingScale = _landingPopScale[reelIndex] ?? 1.0;
        final flashIntensity = _landingFlashProgress[reelIndex] ?? 0.0;

        // ═══════════════════════════════════════════════════════════════════════
        // V6: Enhanced Symbol Highlight — Staggered popup scale + micro-rotation
        // ═══════════════════════════════════════════════════════════════════════
        final symbolPopScale = _symbolPopScale[posKey] ?? 1.0;
        final symbolPopRotation = _symbolPopRotation[posKey] ?? 0.0;

        return Transform.translate(
          offset: Offset(shakeOffset, bounceOffset),
          child: Transform.rotate(
            angle: symbolPopRotation, // V6: Micro-rotation wiggle
            child: Transform.scale(
              scale: cascadeScale * landingScale * symbolPopScale, // V2 + V6: Combined scales
            child: Opacity(
              opacity: cascadeOpacity,
              child: Container(
                width: cellWidth,
                height: cellHeight,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: const Color(0xFF08080C),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isCascadePopPosition && _isCascading
                        ? const Color(0xFFFFD700).withOpacity(cascadeOpacity)
                        : borderColor,
                    width: borderWidth,
                  ),
                  boxShadow: isCascadePopPosition && _isCascading
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.6 * cascadeOpacity),
                            blurRadius: 16 * cascadeScale,
                            spreadRadius: 4 * cascadeScale,
                          ),
                        ]
                      : shadows,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Main symbol content
                    isReelSpinning
                        ? _buildProfessionalSpinningContent(
                            reelIndex, rowIndex, symbolSize, reelState,
                            isAnticipation: isAnticipationReel && _isAnticipation,
                          )
                        : _buildStaticSymbolContent(
                            reelIndex, rowIndex, symbolSize, isWinningPosition,
                            isNearMiss: isNearMissPosition && _isNearMiss,
                          ),
                    // V2: Landing Flash Overlay — white flash on reel stop
                    if (flashIntensity > 0)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.white.withOpacity(flashIntensity * 0.7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ), // V6: Close Transform.rotate
        ),
        );
      },
    );
  }

  Widget _buildSymbolCell(int reelIndex, int rowIndex, double cellSize) {
    return _buildSymbolCellRect(reelIndex, rowIndex, cellSize, cellSize);
  }

  /// PROFESSIONAL SPINNING CONTENT
  /// Phase-based animation with realistic acceleration, blur, and deceleration
  Widget _buildProfessionalSpinningContent(
    int reelIndex,
    int rowIndex,
    double cellSize,
    ReelAnimationState reelState, {
    bool isAnticipation = false,
  }) {
    final spinSyms = _spinSymbols[reelIndex];
    final totalSymbols = spinSyms.length;

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE-BASED SYMBOL SELECTION
    // ═══════════════════════════════════════════════════════════════════════════
    int symbolId;
    double verticalOffset = 0;
    double blurIntensity = 0;

    switch (reelState.phase) {
      case ReelPhase.accelerating:
        // During acceleration: show blur transition, random symbols
        final accelProgress = reelState.phaseProgress;
        blurIntensity = accelProgress * 0.6; // Build up blur
        final symbolIndex = (accelProgress * 10).floor() % totalSymbols;
        symbolId = spinSyms[(symbolIndex + rowIndex) % totalSymbols];
        verticalOffset = (accelProgress * cellSize * 2) % cellSize;

      case ReelPhase.spinning:
        // Full speed: maximum blur, fast cycling symbols
        blurIntensity = 0.7; // High blur during full speed
        final cyclePosition = (reelState.spinCycles * totalSymbols).floor();
        symbolId = spinSyms[(cyclePosition + rowIndex) % totalSymbols];
        verticalOffset = (reelState.spinCycles * cellSize * 3) % cellSize;

      case ReelPhase.decelerating:
        // Slowing down: reduce blur, approach target
        final decelProgress = reelState.phaseProgress;
        blurIntensity = (1 - decelProgress) * 0.5; // Fade blur

        // Interpolate towards target symbol
        if (decelProgress > 0.7) {
          symbolId = _targetGrid[reelIndex][rowIndex];
          verticalOffset = (1 - decelProgress) * cellSize * 0.3;
        } else {
          final remaining = ((1 - decelProgress) * 5).floor();
          symbolId = spinSyms[(remaining + rowIndex) % totalSymbols];
          verticalOffset = (1 - decelProgress) * cellSize;
        }

      case ReelPhase.bouncing:
        // Bouncing: show target symbol with bounce offset
        symbolId = _targetGrid[reelIndex][rowIndex];
        blurIntensity = 0;
        verticalOffset = 0; // Bounce is handled by parent transform

      case ReelPhase.idle:
      case ReelPhase.stopped:
        // Static display
        symbolId = _displayGrid[reelIndex][rowIndex];
        blurIntensity = 0;
        verticalOffset = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VISUAL RENDERING — Fixed size container to prevent layout instability
    // V9: Wrapped in SizedBox + ClipRect to ensure cells never change size during spin
    // ═══════════════════════════════════════════════════════════════════════════
    return SizedBox(
      width: cellSize,
      height: cellSize,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Main symbol with scroll offset — clipped to cell bounds
            Transform.translate(
              offset: Offset(0, verticalOffset * 0.4),
              child: SizedBox(
                width: cellSize,
                height: cellSize,
                child: _buildSymbolContent(symbolId, cellSize, false, isSpinning: true),
              ),
            ),

            // Motion blur overlay - intensity based on phase
            if (blurIntensity > 0.05)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(blurIntensity * 0.6),
                        Colors.black.withOpacity(blurIntensity * 0.2),
                        Colors.black.withOpacity(blurIntensity * 0.6),
                      ],
                    ),
                  ),
                ),
              ),

            // Speed lines effect during spinning phase
            if (reelState.phase == ReelPhase.spinning)
              Positioned.fill(
                child: CustomPaint(
                  size: Size(cellSize, cellSize),
                  painter: _SpeedLinesPainter(intensity: 0.3),
                ),
              ),

            // Anticipation golden glow overlay
            if (isAnticipation)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFD700).withOpacity(_anticipationPulse.value * 0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              )
            // Acceleration glow effect
            else if (reelState.phase == ReelPhase.accelerating)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        FluxForgeTheme.accentBlue.withOpacity(reelState.phaseProgress * 0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Legacy spinning content (kept for reference)
  Widget _buildSpinningSymbolContent(
    int reelIndex,
    int rowIndex,
    double cellSize,
    double animationValue, {
    bool isAnticipation = false,
  }) {
    final spinSyms = _spinSymbols[reelIndex];
    final totalSymbols = spinSyms.length;

    // Enhanced easing for more realistic reel feel
    final scrollProgress = Curves.easeOutCubic.transform(animationValue);
    final currentIndex = ((1 - scrollProgress) * (totalSymbols - widget.rows)).floor();
    final symbolId = currentIndex + rowIndex < totalSymbols
        ? spinSyms[currentIndex + rowIndex]
        : _targetGrid[reelIndex][rowIndex];

    // Calculate vertical offset for smooth scrolling effect
    final fractionalProgress = ((1 - scrollProgress) * (totalSymbols - widget.rows)) % 1.0;
    final verticalOffset = fractionalProgress * cellSize;

    // Speed-based blur intensity
    final speed = animationValue < 0.5
        ? animationValue * 2  // Speeding up
        : (1 - animationValue) * 2;  // Slowing down
    final blurIntensity = speed * 0.4;

    return Stack(
      children: [
        // Main symbol with scroll offset
        Transform.translate(
          offset: Offset(0, verticalOffset * 0.3),  // Subtle vertical movement
          child: _buildSymbolContent(symbolId, cellSize, false, isSpinning: true),
        ),
        // Motion blur overlay - stronger during fast spin
        if (blurIntensity > 0.05)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(blurIntensity * 0.5),
                  Colors.transparent,
                  Colors.black.withOpacity(blurIntensity * 0.5),
                ],
              ),
            ),
          ),
        // Anticipation golden glow overlay
        if (isAnticipation)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFD700).withOpacity(_anticipationPulse.value * 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          )
        // Normal spin glow effect
        else if (animationValue < 0.3)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  FluxForgeTheme.accentBlue.withOpacity((0.3 - animationValue) * 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStaticSymbolContent(
    int reelIndex,
    int rowIndex,
    double cellSize,
    bool isWinning, {
    bool isNearMiss = false,
  }) {
    final symbolId = _displayGrid[reelIndex][rowIndex];
    return _buildSymbolContent(
      symbolId,
      cellSize,
      isWinning,
      isNearMiss: isNearMiss,
    );
  }

  Widget _buildSymbolContent(
    int symbolId,
    double cellSize,
    bool isWinning, {
    bool isSpinning = false,
    bool isNearMiss = false,
  }) {
    final symbol = SlotSymbol.getSymbol(symbolId);
    final fontSize = (cellSize * 0.5).clamp(12.0, 60.0);

    // Enhanced glow for winning symbols or near miss
    List<Color> glowColors;
    if (isNearMiss) {
      // Near miss - desaturated red tint
      glowColors = [
        const Color(0xFFFF4060).withOpacity(0.7),
        const Color(0xFF802030),
        const Color(0xFF401020),
      ];
    } else if (isWinning) {
      glowColors = [
        symbol.glowColor.withOpacity(0.8),
        symbol.gradientColors.first,
        symbol.gradientColors.last,
      ];
    } else {
      glowColors = symbol.gradientColors;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: glowColors,
        ),
        borderRadius: BorderRadius.circular(3),
        boxShadow: isWinning
            ? [
                BoxShadow(
                  color: symbol.glowColor.withOpacity(0.6),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : isNearMiss
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF4060).withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
      ),
      child: Stack(
        children: [
          // Inner glow for special symbols
          if (symbol.isSpecial)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      symbol.glowColor.withOpacity(isSpinning ? 0.1 : 0.3),
                      Colors.transparent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          // Symbol character
          Center(
            child: Text(
              symbol.displayChar,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black.withOpacity(0.6), blurRadius: 3, offset: const Offset(1, 1)),
                  if (isWinning || symbol.isSpecial)
                    Shadow(color: symbol.glowColor.withOpacity(0.8), blurRadius: 8),
                ],
              ),
            ),
          ),
          // Win shimmer effect
          if (isWinning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _winPulseAnimation,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1 + _winPulseAnimation.value * 2, -1),
                        end: Alignment(1 + _winPulseAnimation.value * 2, 1),
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.15),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                },
              ),
            ),
          // Near miss X overlay
          if (isNearMiss)
            Positioned.fill(
              child: Center(
                child: Text(
                  '✕',
                  style: TextStyle(
                    fontSize: fontSize * 1.2,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFF4060).withOpacity(0.9),
                    shadows: const [
                      Shadow(
                        color: Color(0xFFFF4060),
                        blurRadius: 12,
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

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT SLOT MINI PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// PARTICLE SYSTEM FOR WIN CELEBRATIONS
// ═══════════════════════════════════════════════════════════════════════════

enum _ParticleType { coin, sparkle }

class _WinParticle {
  double x = 0, y = 0;
  double vx = 0, vy = 0;
  double size = 4;
  Color color = const Color(0xFFFFD700);
  _ParticleType type = _ParticleType.coin;
  double rotation = 0;
  double rotationSpeed = 0;
  double life = 1.0;
  double gravity = 0.0005;

  /// Reset particle for reuse from pool
  void reset({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double size,
    required Color color,
    required _ParticleType type,
    required double rotation,
    required double rotationSpeed,
  }) {
    this.x = x;
    this.y = y;
    this.vx = vx;
    this.vy = vy;
    this.size = size;
    this.color = color;
    this.type = type;
    this.rotation = rotation;
    this.rotationSpeed = rotationSpeed;
    life = 1.0;
    gravity = 0.0005;
  }

  void update() {
    x += vx;
    y += vy;
    vy += gravity; // Gravity pulls down
    rotation += rotationSpeed;
    life -= 0.015; // Fade out

    // Slow down horizontal movement
    vx *= 0.99;
  }

  bool get isDead => life <= 0 || y > 1.2 || x < -0.1 || x > 1.1;
}

/// Object pool for particles - eliminates GC pressure during win animations
class _ParticlePool {
  final List<_WinParticle> _available = [];
  static const int maxPoolSize = 100;

  /// Acquire a particle from the pool or create new if pool is empty
  _WinParticle acquire({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double size,
    required Color color,
    required _ParticleType type,
    required double rotation,
    required double rotationSpeed,
  }) {
    final particle = _available.isNotEmpty ? _available.removeLast() : _WinParticle();
    particle.reset(
      x: x, y: y, vx: vx, vy: vy,
      size: size, color: color, type: type,
      rotation: rotation, rotationSpeed: rotationSpeed,
    );
    return particle;
  }

  /// Return a particle to the pool for reuse
  void release(_WinParticle particle) {
    if (_available.length < maxPoolSize) {
      _available.add(particle);
    }
  }

  /// Release multiple particles
  void releaseAll(Iterable<_WinParticle> particles) {
    for (final p in particles) {
      release(p);
    }
  }
}

/// Speed lines painter for spinning reel effect
class _SpeedLinesPainter extends CustomPainter {
  final double intensity;

  _SpeedLinesPainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity < 0.1) return;

    final paint = Paint()
      ..color = Colors.white.withOpacity(intensity * 0.15)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw vertical speed lines
    final lineCount = 5;
    final spacing = size.width / (lineCount + 1);

    for (int i = 0; i < lineCount; i++) {
      final x = spacing * (i + 1);
      // Vary line lengths for more natural look
      final startY = size.height * (0.1 + (i % 3) * 0.1);
      final endY = size.height * (0.9 - (i % 2) * 0.1);

      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter oldDelegate) {
    return oldDelegate.intensity != intensity;
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_WinParticle> particles;

  _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withOpacity((p.life * 0.8).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      final x = p.x * size.width;
      final y = p.y * size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation);

      if (p.type == _ParticleType.coin) {
        // Draw coin shape
        final coinPaint = Paint()
          ..color = p.color.withOpacity((p.life * 0.9).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;

        // Outer circle
        canvas.drawCircle(Offset.zero, p.size, coinPaint);

        // Inner highlight
        final highlightPaint = Paint()
          ..color = Colors.white.withOpacity((p.life * 0.4).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(-p.size * 0.2, -p.size * 0.2), p.size * 0.3, highlightPaint);

        // Edge shadow
        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity((p.life * 0.3).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset.zero, p.size, shadowPaint);
      } else {
        // Draw sparkle/star shape
        final path = Path();
        final outerRadius = p.size;
        final innerRadius = p.size * 0.4;

        for (int i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final radius = i.isEven ? outerRadius : innerRadius;
          final px = math.cos(angle) * radius;
          final py = math.sin(angle) * radius;
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();

        canvas.drawPath(path, paint);

        // Center glow
        final glowPaint = Paint()
          ..color = Colors.white.withOpacity((p.life * 0.6).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(Offset.zero, p.size * 0.3, glowPaint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// WIN LINE PAINTER — Draws connecting lines through winning positions
// ═══════════════════════════════════════════════════════════════════════════

class _WinLinePainter extends CustomPainter {
  final List<List<int>> positions; // [[reel, row], ...]
  final int reelCount;
  final int rowCount;
  final double pulseValue; // 0.0 - 1.0 for animation
  final Color lineColor;

  _WinLinePainter({
    required this.positions,
    required this.reelCount,
    required this.rowCount,
    required this.pulseValue,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty || positions.length < 2) return;

    // Calculate grid layout (must match _buildReelTable logic)
    // Available space = size - padding (4*2=8) - border (2*2=4) = size - 12
    final availableWidth = size.width - 12;
    final availableHeight = size.height - 12;
    final cellWidth = availableWidth / reelCount;
    final cellHeight = availableHeight / rowCount;
    final cellSize = math.min(cellWidth, cellHeight) * 0.82;

    // Calculate offset to center the table
    final tableWidth = cellSize * reelCount;
    final tableHeight = cellSize * rowCount;
    final offsetX = (size.width - tableWidth) / 2;
    final offsetY = (size.height - tableHeight) / 2;

    // Convert positions to pixel coordinates
    final points = <Offset>[];
    for (final pos in positions) {
      if (pos.length >= 2) {
        final reelIndex = pos[0];
        final rowIndex = pos[1];
        // Center of the cell
        final x = offsetX + (reelIndex + 0.5) * cellSize;
        final y = offsetY + (rowIndex + 0.5) * cellSize;
        points.add(Offset(x, y));
      }
    }

    if (points.length < 2) return;

    // Draw outer glow (thicker, more transparent)
    final glowPaint = Paint()
      ..color = lineColor.withOpacity(0.3 + pulseValue * 0.2)
      ..strokeWidth = 14 + pulseValue * 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, glowPaint);

    // Draw main line (solid, colored)
    final linePaint = Paint()
      ..color = lineColor.withOpacity(0.8 + pulseValue * 0.2)
      ..strokeWidth = 5 + pulseValue * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    // Draw inner highlight (white core)
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.4 + pulseValue * 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, highlightPaint);

    // Draw dots at each position
    for (final point in points) {
      // Outer glow dot
      final dotGlowPaint = Paint()
        ..color = lineColor.withOpacity(0.5 + pulseValue * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(point, 12 + pulseValue * 4, dotGlowPaint);

      // Main dot
      final dotPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, 8 + pulseValue * 2, dotPaint);

      // White center
      final dotCenterPaint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, 3 + pulseValue, dotCenterPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WinLinePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
           oldDelegate.positions != positions;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// V4: PLAQUE BURST PAINTER — Radiating lines behind win plaque
// ═══════════════════════════════════════════════════════════════════════════

class _PlaqueBurstPainter extends CustomPainter {
  final double progress;
  final double pulseValue;
  final Color tierColor;
  final int rayCount;

  _PlaqueBurstPainter({
    required this.progress,
    required this.pulseValue,
    required this.tierColor,
    required this.rayCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Ray length grows with progress
    final maxRayLength = math.max(size.width, size.height) * 0.6;
    final rayLength = maxRayLength * progress;

    // Opacity fades in then pulses
    final baseOpacity = (progress * 0.3).clamp(0.0, 0.3);
    final opacity = baseOpacity * (0.6 + pulseValue * 0.4);

    final rayPaint = Paint()
      ..color = tierColor.withOpacity(opacity)
      ..strokeWidth = 3 + pulseValue * 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Draw radiating rays
    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * math.pi - math.pi / 2; // Start from top
      final startRadius = 30.0; // Start away from center for donut effect
      final startX = centerX + math.cos(angle) * startRadius;
      final startY = centerY + math.sin(angle) * startRadius;
      final endX = centerX + math.cos(angle) * rayLength;
      final endY = centerY + math.sin(angle) * rayLength;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), rayPaint);
    }

    // Inner glow circle
    final glowPaint = Paint()
      ..color = tierColor.withOpacity(opacity * 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(Offset(centerX, centerY), 40 + pulseValue * 10, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _PlaqueBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.pulseValue != pulseValue ||
           oldDelegate.tierColor != tierColor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// V5: BIG WIN BACKGROUND PAINTER — Vignette + Color wash for celebration
// ═══════════════════════════════════════════════════════════════════════════

class _BigWinBackgroundPainter extends CustomPainter {
  final String tier;
  final double pulseValue;
  final Color tierColor;

  _BigWinBackgroundPainter({
    required this.tier,
    required this.pulseValue,
    required this.tierColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ═══════════════════════════════════════════════════════════════════════
    // VIGNETTE — Dark gradient at edges (more intense for higher tiers)
    // ═══════════════════════════════════════════════════════════════════════
    final vignetteIntensity = switch (tier) {
      'ULTRA' => 0.6,
      'EPIC' => 0.5,
      'MEGA' => 0.4,
      'SUPER' => 0.3,
      'BIG' => 0.2,
      _ => 0.15,
    };

    final vignetteOpacity = vignetteIntensity * (0.7 + pulseValue * 0.3);

    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withOpacity(vignetteOpacity * 0.3),
          Colors.black.withOpacity(vignetteOpacity),
        ],
        stops: const [0.0, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);

    // ═══════════════════════════════════════════════════════════════════════
    // COLOR WASH — Tier-colored glow pulsing from center
    // ═══════════════════════════════════════════════════════════════════════
    final colorWashIntensity = switch (tier) {
      'ULTRA' => 0.25,
      'EPIC' => 0.20,
      'MEGA' => 0.18,
      'SUPER' => 0.12,
      'BIG' => 0.08,
      _ => 0.05,
    };

    final colorWashOpacity = colorWashIntensity * (0.6 + pulseValue * 0.4);

    final colorWashPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8 + pulseValue * 0.2,
        colors: [
          tierColor.withOpacity(colorWashOpacity),
          tierColor.withOpacity(colorWashOpacity * 0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), colorWashPaint);

    // ═══════════════════════════════════════════════════════════════════════
    // LIGHT RAYS — Subtle rays from center (MEGA and above)
    // ═══════════════════════════════════════════════════════════════════════
    if (tier == 'ULTRA' || tier == 'EPIC' || tier == 'MEGA') {
      final rayOpacity = switch (tier) {
        'ULTRA' => 0.15,
        'EPIC' => 0.10,
        'MEGA' => 0.08,
        _ => 0.05,
      };

      final rayCount = switch (tier) {
        'ULTRA' => 12,
        'EPIC' => 8,
        'MEGA' => 6,
        _ => 4,
      };

      final rayPaint = Paint()
        ..color = tierColor.withOpacity(rayOpacity * (0.5 + pulseValue * 0.5))
        ..strokeWidth = 2 + pulseValue * 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final centerX = size.width / 2;
      final centerY = size.height / 2;
      final maxRadius = math.max(size.width, size.height) * 0.8;

      for (int i = 0; i < rayCount; i++) {
        final angle = (i / rayCount) * 2 * math.pi + (pulseValue * math.pi * 0.1);
        final endX = centerX + math.cos(angle) * maxRadius;
        final endY = centerY + math.sin(angle) * maxRadius;

        canvas.drawLine(
          Offset(centerX, centerY),
          Offset(endX, endY),
          rayPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BigWinBackgroundPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
           oldDelegate.tier != tier ||
           oldDelegate.tierColor != tierColor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT SLOT MINI PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

class SlotMiniPreview extends StatelessWidget {
  final SlotLabProvider provider;
  final double size;

  const SlotMiniPreview({
    super.key,
    required this.provider,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, child) {
        final result = provider.lastResult;
        final grid = result?.grid ?? [];

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A4C), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: 15,
              itemBuilder: (context, index) {
                final reel = index % 5;
                final row = index ~/ 5;
                final symbolId = (grid.length > reel && grid[reel].length > row)
                    ? grid[reel][row]
                    : (reel + row) % 10;
                final symbol = SlotSymbol.getSymbol(symbolId);

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: symbol.gradientColors),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Center(
                    child: Text(symbol.displayChar, style: const TextStyle(fontSize: 8)),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
