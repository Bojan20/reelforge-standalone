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
  Set<int> _winningReels = {};
  Set<String> _winningPositions = {}; // "reel,row" format

  // Anticipation/Near Miss state
  bool _isAnticipation = false;
  bool _isNearMiss = false;
  Set<int> _anticipationReels = {}; // Reels showing anticipation
  Set<String> _nearMissPositions = {}; // Positions that "just missed"

  // Cascade state
  bool _isCascading = false;
  Set<String> _cascadePopPositions = {}; // Positions being popped
  int _cascadeStep = 0;

  // Win display state
  double _displayedWinAmount = 0;
  double _targetWinAmount = 0;
  String _winTier = ''; // SMALL, BIG, SUPER, MEGA, EPIC, ULTRA (industry standard)

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
  // BIG is first major tier, SUPER is second tier
  static const Map<String, int> _rollupDurationByTier = {
    'SMALL': 1500,
    'BIG': 2500,     // First major tier
    'SUPER': 4000,   // Second tier (was NICE)
    'MEGA': 7000,    // Third tier
    'EPIC': 12000,   // Fourth tier
    'ULTRA': 20000,  // Maximum
  };

  // Tier-specific rollup tick rate (ticks per second)
  static const Map<String, int> _rollupTickRateByTier = {
    'SMALL': 15,
    'BIG': 12,     // First major tier
    'SUPER': 10,   // Second tier
    'MEGA': 8,     // Third tier
    'EPIC': 6,     // Fourth tier
    'ULTRA': 4,    // Maximum
  };

  // Currency formatter for win display
  static final _currencyFormatter = NumberFormat.currency(
    symbol: '',
    decimalDigits: 0,
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
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC CALLBACKS — Audio triggers on VISUAL reel stop
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when a reel VISUALLY stops - triggers audio for that reel
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

    // Trigger the audio event for this specific reel
    // The EventRegistry will play the audio with correct pan
    debugPrint('[SlotPreview] 🎰 REEL $reelIndex STOPPED → triggering REEL_STOP_$reelIndex');
    eventRegistry.triggerStage('REEL_STOP_$reelIndex');
  }

  /// Called when ALL reels have stopped - trigger win evaluation
  void _onAllReelsStoppedVisual() {
    if (!mounted) return;

    debugPrint('[SlotPreview] ✅ ALL REELS STOPPED → finalize spin');

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
    _stopRollupTicks(); // Clean up rollup audio sequence
    _disposeControllers();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    final result = widget.provider.lastResult;
    final isPlaying = widget.provider.isPlayingStages;
    final stages = widget.provider.lastStages;

    // ═══════════════════════════════════════════════════════════════════════════
    // SPIN START LOGIC — Guard against re-triggering after finalize
    // ═══════════════════════════════════════════════════════════════════════════
    // Conditions to start spin:
    // 1. Provider is playing stages
    // 2. We have stages to process
    // 3. We're not already spinning
    // 4. We haven't just finalized this spin (prevents double-trigger)
    // 5. This is a NEW spin result (different spinId)
    if (isPlaying && stages.isNotEmpty && !_isSpinning && !_spinFinalized) {
      final hasSpinStart = stages.any((s) => s.stageType == 'spin_start');
      final spinId = result?.spinId;

      // Only start if this is a genuinely new spin
      if (hasSpinStart && spinId != null && spinId != _lastProcessedSpinId) {
        debugPrint('[SlotPreview] 🆕 New spin detected: $spinId (last: $_lastProcessedSpinId)');
        _lastProcessedSpinId = spinId;
        _startSpin(result);
      }
    }

    // Reset finalized flag when provider stops playing (ready for next spin)
    if (!isPlaying && _spinFinalized) {
      debugPrint('[SlotPreview] 🔄 Reset finalized flag — ready for next spin');
      _spinFinalized = false;
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

    if (!isPlaying && result != null && _isSpinning) {
      _finalizeSpin(result);
    }
  }

  void _startSpin(SlotLabSpinResult? result) {
    if (_isSpinning) return;

    // Stop any previous win line presentation
    _stopWinLinePresentation();

    setState(() {
      _isSpinning = true;
      _spinFinalized = false; // Clear finalized flag for new spin
      _winningReels = {};
      _winningPositions = {};
      _currentLinePositions = {}; // Clear line presentation positions
      _winTier = '';
      _displayedWinAmount = 0;
      _targetWinAmount = 0;
      _particles.clear();
      // Reset anticipation/near miss state
      _isAnticipation = false;
      _isNearMiss = false;
      _anticipationReels = {};
      _nearMissPositions = {};
      // Clear reel stopped flags for new spin
      _reelStoppedFlags.clear();
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
    debugPrint('[SlotPreview] ✅ FINALIZE SPIN — setting spinFinalized=true');

    // Stop visual animation immediately (in case of external stop via SPACE)
    _reelAnimController.stopImmediately();

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
        // WIN AUDIO FLOW — Simplified sequential presentation (NO plaque)
        // Phase 1: SYMBOL_HIGHLIGHT (1050ms) — Winning symbols glow/bounce
        // Phase 2: TIER PLAQUE + COIN COUNTER ROLLUP (tier-based) — "BIG WIN!" + counter
        // Phase 3: WIN_LINE_SHOW (cycling) — Visual lines ONLY, no symbol info
        // ═══════════════════════════════════════════════════════════════════════

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 1: SYMBOL HIGHLIGHT (0ms - 1050ms)
        // 3 pulse cycles × 350ms = 1050ms total
        // ═══════════════════════════════════════════════════════════════════════
        eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');
        debugPrint('[SlotPreview] 🔊 PHASE 1: WIN_SYMBOL_HIGHLIGHT (tier: $_winTier)');

        // Start symbol pulse animation (repeats 3 times)
        _startSymbolPulseAnimation();

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 2: TIER PLAQUE + COIN COUNTER ROLLUP (starts after Phase 1: 1050ms)
        // Duration: tier-based (1500ms SMALL → 20000ms ULTRA)
        // Prikazuje: "BIG WIN!" + coin counter sa rollup animacijom
        // NE prikazuje: info o simbolima (npr. "3x Grapes = $50")
        // ═══════════════════════════════════════════════════════════════════════
        final rollupDuration = _rollupDurationByTier[_winTier] ?? 1500;

        Future.delayed(const Duration(milliseconds: _symbolHighlightDurationMs), () {
          if (!mounted) return;

          // Trigger tier-specific fanfare
          final tierStage = _winTier.isNotEmpty ? 'WIN_PRESENT_$_winTier' : 'WIN_PRESENT';
          eventRegistry.triggerStage(tierStage);
          debugPrint('[SlotPreview] 🔊 PHASE 2: $tierStage (tier plaque + counter)');

          // Show tier plaque + coin counter overlay
          _winAmountController.forward(from: 0);

          // Start counter rollup with tier-specific duration
          _startTierBasedRollup(_winTier);
        });

        // Spawn particles for bigger wins
        if (_winTier != 'SMALL') {
          _spawnWinParticles(_winTier);
        }

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 3: WIN LINE PRESENTATION (STRICT SEQUENTIAL — after rollup ends)
        // ALL tiers: Win lines start ONLY after rollup completes
        // Prikazuje: SAMO vizualne linije između dobitnih simbola
        // NE prikazuje: info o simbolima (npr. "Line 3: 3x Grapes = $50")
        // ═══════════════════════════════════════════════════════════════════════
        if (result.lineWins.isNotEmpty) {
          // Phase 3 starts strictly AFTER rollup ends
          final totalDelay = _symbolHighlightDurationMs + rollupDuration;

          Future.delayed(Duration(milliseconds: totalDelay), () {
            if (!mounted) return;
            debugPrint('[SlotPreview] 🔊 PHASE 3: WIN_LINE_SHOW starting (after rollup, delay: ${totalDelay}ms)');
            _startWinLinePresentation(result.lineWins);
          });
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // WIN LINE PRESENTATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Start cycling through winning lines one by one
  void _startWinLinePresentation(List<LineWin> lineWins) {
    _lineWinsForPresentation = lineWins;
    _currentPresentingLineIndex = 0;
    _isShowingWinLines = true;

    // ═══════════════════════════════════════════════════════════════════════════
    // SAKRIJ TIER PLAKETU — win lines se prikazuju bez overlay-a
    // Ostaju SAMO vizualne linije, BEZ info o simbolima
    // ═══════════════════════════════════════════════════════════════════════════
    _winAmountController.reverse();

    // Show first line immediately
    _showCurrentWinLine();

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

  /// Advance to next win line in the cycle
  void _advanceToNextWinLine() {
    if (_lineWinsForPresentation.isEmpty) return;

    setState(() {
      _currentPresentingLineIndex =
          (_currentPresentingLineIndex + 1) % _lineWinsForPresentation.length;
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
    if (bet <= 0) return totalWin > 0 ? 'SMALL' : '';

    final ratio = totalWin / bet;
    if (ratio >= 100) return 'ULTRA';
    if (ratio >= 60) return 'EPIC';
    if (ratio >= 30) return 'MEGA';
    if (ratio >= 15) return 'SUPER';
    if (ratio >= 5) return 'BIG';
    if (ratio > 0) return 'SMALL';
    return '';
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
  void _startSymbolPulseAnimation() {
    _symbolPulseCount = 0;
    _runSymbolPulseCycle();
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
  void _startTierBasedRollup(String tier) {
    final duration = _rollupDurationByTier[tier] ?? 1500;
    final tickRate = _rollupTickRateByTier[tier] ?? 10;
    final tickIntervalMs = (1000 / tickRate).round();
    final totalTicks = (duration / tickIntervalMs).round();

    debugPrint('[SlotPreview] 🔊 ROLLUP_START (tier: $tier, duration: ${duration}ms, ticks: $totalTicks)');

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
          eventRegistry.triggerStage('ROLLUP_END');
          debugPrint('[SlotPreview] 🔊 ROLLUP_END (completed $totalTicks ticks)');
        }
        return;
      }

      _rollupTickCount++;
      eventRegistry.triggerStage('ROLLUP_TICK');
    });
  }

  /// Format win amount with currency-style thousand separators
  /// Examples: 1234 → "1,234" | 50 → "50" | 1234567 → "1,234,567"
  String _formatWinAmount(double amount) {
    return _currencyFormatter.format(amount.toInt());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTICIPATION / NEAR MISS EFFECTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start anticipation effect - typically on last reel(s) when potential big win
  void _startAnticipation(SlotLabSpinResult? result) {
    setState(() {
      _isAnticipation = true;
      // Typically anticipation is on the last 1-2 reels
      _anticipationReels = {widget.reels - 2, widget.reels - 1};
    });
  }

  /// Stop anticipation effect
  void _stopAnticipation() {
    setState(() {
      _isAnticipation = false;
      _anticipationReels = {};
    });
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

          return ClipRRect(
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

              // Win amount overlay
              if (_winTier.isNotEmpty)
                Positioned.fill(
                  child: _buildWinOverlay(constraints),
                ),
            ],
          ),
        );
        },
      ),
    );
  }

  /// Handle SPACE key — Skip/stop spin immediately
  void _handleSpaceKey() {
    if (_isSpinning) {
      debugPrint('[SlotPreview] ⏹ SPACE pressed — stopping all reels immediately');

      // Immediately stop all reels via animation controller
      _reelAnimController.stopImmediately();

      // Update display grid to target (final) values
      setState(() {
        for (int r = 0; r < widget.reels && r < _targetGrid.length; r++) {
          for (int row = 0; row < widget.rows && row < _targetGrid[r].length; row++) {
            _displayGrid[r][row] = _targetGrid[r][row];
          }
        }
      });

      // Get the final result to finalize with
      final result = widget.provider.lastResult;
      if (result != null) {
        _finalizeSpin(result);
      }
    }
  }

  Color _getWinBorderColor() {
    final baseColor = switch (_winTier) {
      'ULTRA' => const Color(0xFFFF4080),
      'EPIC' => const Color(0xFFE040FB),
      'MEGA' => const Color(0xFFFFD700),
      'BIG' => FluxForgeTheme.accentGreen,
      _ => FluxForgeTheme.accentGreen,
    };
    return baseColor.withOpacity(_winPulseAnimation.value);
  }

  Color _getWinGlowColor() {
    return switch (_winTier) {
      'ULTRA' => const Color(0xFFFF4080),
      'EPIC' => const Color(0xFFE040FB),
      'MEGA' => const Color(0xFFFFD700),
      'BIG' => FluxForgeTheme.accentGreen,
      _ => FluxForgeTheme.accentGreen,
    };
  }

  Widget _buildWinOverlay(BoxConstraints constraints) {
    return AnimatedBuilder(
      animation: Listenable.merge([_winAmountScale, _winAmountOpacity]),
      builder: (context, child) {
        if (_winAmountOpacity.value < 0.01) return const SizedBox.shrink();

        return Opacity(
          opacity: _winAmountOpacity.value,
          child: Center(
            child: Transform.scale(
              scale: _winAmountScale.value,
              child: _buildWinDisplay(),
            ),
          ),
        );
      },
    );
  }

  /// Win display — Tier plaketa ("BIG WIN!", "MEGA WIN!" itd.) SA coin counterom
  /// NE prikazuje info o simbolima/win linijama (npr. "3x Grapes")
  Widget _buildWinDisplay() {
    // Boje bazirane na tier-u (industry standard progression)
    // BIG je prvi major tier, SUPER je drugi (umesto NICE)
    final tierColors = switch (_winTier) {
      'ULTRA' => [const Color(0xFFFF4080), const Color(0xFFFF66FF), const Color(0xFFFFD700)],
      'EPIC' => [const Color(0xFFE040FB), const Color(0xFFFF66FF), const Color(0xFF40C8FF)],
      'MEGA' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFF9040)],
      'SUPER' => [const Color(0xFF40C8FF), const Color(0xFF81D4FA), const Color(0xFF4FC3F7)],
      'BIG' => [const Color(0xFF40FF90), const Color(0xFF88FF88), const Color(0xFFFFEB3B)],
      _ => [const Color(0xFF40FF90), const Color(0xFF4CAF50)],
    };

    // Tier label tekst — Industry standard (Zynga, NetEnt, Pragmatic)
    // BIG WIN je PRVI major tier, ne srednji
    final tierLabel = switch (_winTier) {
      'ULTRA' => 'ULTRA WIN!',
      'EPIC' => 'EPIC WIN!',
      'MEGA' => 'MEGA WIN!',
      'SUPER' => 'SUPER WIN!',
      'BIG' => 'BIG WIN!',
      'SMALL' => 'WIN!',
      _ => 'WIN!',
    };

    // Font size baziran na tier-u
    final tierFontSize = switch (_winTier) {
      'ULTRA' => 36.0,
      'EPIC' => 32.0,
      'MEGA' => 28.0,
      'SUPER' => 26.0,
      'BIG' => 24.0,
      _ => 20.0,
    };

    final counterFontSize = switch (_winTier) {
      'ULTRA' => 52.0,
      'EPIC' => 48.0,
      'MEGA' => 44.0,
      'SUPER' => 40.0,
      'BIG' => 36.0,
      _ => 32.0,
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // TIER PLAKETA + COIN COUNTER
    // Prikazuje: "BIG WIN!" + "$250.00"
    // NE prikazuje: info o simbolima (npr. "3x Grapes = $50")
    // ═══════════════════════════════════════════════════════════════════════════
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      decoration: BoxDecoration(
        // Gradient background za premium izgled
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withOpacity(0.85),
            tierColors.first.withOpacity(0.3),
            Colors.black.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        // Border u tier boji
        border: Border.all(
          color: tierColors.first.withOpacity(0.8),
          width: 3,
        ),
        // Glow efekat
        boxShadow: [
          BoxShadow(
            color: tierColors.first.withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: tierColors.first.withOpacity(0.3),
            blurRadius: 60,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tier label: "BIG WIN!", "MEGA WIN!", itd.
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: tierColors,
            ).createShader(bounds),
            child: Text(
              tierLabel,
              style: TextStyle(
                fontSize: tierFontSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 4,
                shadows: [
                  Shadow(
                    color: tierColors.first,
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Coin counter sa rollup animacijom
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [Colors.white, tierColors.first, Colors.white],
            ).createShader(bounds),
            child: Text(
              _formatWinAmount(_displayedWinAmount),
              style: TextStyle(
                fontSize: counterFontSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
                shadows: [
                  Shadow(
                    color: tierColors.first.withOpacity(0.8),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
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

    return Center(
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

        return Transform.translate(
          offset: Offset(shakeOffset, bounceOffset),
          child: Transform.scale(
            scale: cascadeScale,
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
                child: isReelSpinning
                    ? _buildProfessionalSpinningContent(
                        reelIndex, rowIndex, symbolSize, reelState,
                        isAnticipation: isAnticipationReel && _isAnticipation,
                      )
                    : _buildStaticSymbolContent(
                        reelIndex, rowIndex, symbolSize, isWinningPosition,
                        isNearMiss: isNearMissPosition && _isNearMiss,
                      ),
              ),
            ),
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
    // VISUAL RENDERING
    // ═══════════════════════════════════════════════════════════════════════════
    return Stack(
      children: [
        // Main symbol with scroll offset
        Transform.translate(
          offset: Offset(0, verticalOffset * 0.4),
          child: _buildSymbolContent(symbolId, cellSize, false, isSpinning: true),
        ),

        // Motion blur overlay - intensity based on phase
        if (blurIntensity > 0.05)
          Container(
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

        // Speed lines effect during spinning phase
        if (reelState.phase == ReelPhase.spinning)
          CustomPaint(
            size: Size(cellSize, cellSize),
            painter: _SpeedLinesPainter(intensity: 0.3),
          ),

        // Anticipation golden glow overlay
        if (isAnticipation)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFD700).withOpacity(_anticipationPulse.value * 0.4),
                  Colors.transparent,
                ],
              ),
            ),
          )
        // Acceleration glow effect
        else if (reelState.phase == ReelPhase.accelerating)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  FluxForgeTheme.accentBlue.withOpacity(reelState.phaseProgress * 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
      ],
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
