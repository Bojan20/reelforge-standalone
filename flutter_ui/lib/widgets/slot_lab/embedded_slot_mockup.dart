/// Embedded Slot Mockup V3
///
/// Premium casino-grade slot UI following industry rules:
/// - GameState: Idle → Spinning → Anticipation → Revealing → Celebrating
/// - WinType: NoWin, SmallWin(<10x), MediumWin(10-50x), BigWin(50-100x), MegaWin(100-500x), EpicWin(>500x)
/// - Jackpot tickers with smooth value updates (no rolling digits)
/// - Proper spin lifecycle with staggered reel stops
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../providers/slot_lab_provider.dart';
import '../../src/rust/native_ffi.dart';

// =============================================================================
// THEME - Casino Grade Dark Premium
// =============================================================================

class _T {
  // Backgrounds
  static const bg1 = Color(0xFF030308);
  static const bg2 = Color(0xFF080810);
  static const bg3 = Color(0xFF101018);
  static const bg4 = Color(0xFF181822);
  static const bg5 = Color(0xFF20202C);

  // Metals
  static const gold = Color(0xFFFFD700);
  static const goldBright = Color(0xFFFFE966);
  static const goldDark = Color(0xFFB8860B);
  static const silver = Color(0xFFB0B0B8);

  // Jackpots
  static const jpGrand = Color(0xFFFFD700);
  static const jpMajor = Color(0xFFFF1744);
  static const jpMinor = Color(0xFF7C4DFF);
  static const jpMini = Color(0xFF00E676);

  // Wins
  static const winSmall = Color(0xFF42A5F5);
  static const winMedium = Color(0xFF66BB6A);
  static const winBig = Color(0xFFFFCA28);
  static const winMega = Color(0xFFFF7043);
  static const winEpic = Color(0xFFE040FB);

  // UI
  static const spin = Color(0xFF00E676);
  static const spinBright = Color(0xFF69F0AE);
  static const border = Color(0xFF303040);
  static const borderLight = Color(0xFF404055);
  static const text = Colors.white;
  static const textDim = Color(0xFF808090);
  static const textMuted = Color(0xFF505060);

  // Gradients
  static const headerGradient = [Color(0xFF1A1A28), Color(0xFF101018)];
  static const reelBgGradient = [Color(0xFF0A0A14), Color(0xFF050508)];
  static const cellGradient = [Color(0xFF1E1E2A), Color(0xFF141420)];
}

// =============================================================================
// GAME STATE ENUM (from middleware guide)
// =============================================================================

enum GameState {
  idle,        // 0 - Waiting for spin
  spinning,    // 1 - Reels spinning
  anticipation,// 2 - Last reel, potential win
  revealing,   // 3 - Revealing result
  celebrating, // 4 - Win animation
  bonusGame,   // 5 - Bonus game active
}

enum WinType {
  noWin,       // 0 - No win
  smallWin,    // 1 - < 10x
  mediumWin,   // 2 - 10-50x
  bigWin,      // 3 - 50-100x
  megaWin,     // 4 - 100-500x
  epicWin,     // 5 - > 500x
}

// =============================================================================
// SYMBOLS
// =============================================================================

class _Sym {
  final String icon;
  final Color c1, c2;
  final bool isWild, isScatter, isBonus;

  const _Sym(this.icon, this.c1, this.c2,
      {this.isWild = false, this.isScatter = false, this.isBonus = false});

  bool get isSpecial => isWild || isScatter || isBonus;

  static const list = [
    _Sym('⭐', Color(0xFFFFE082), Color(0xFFFFD700), isWild: true),
    _Sym('💎', Color(0xFFE1BEE7), Color(0xFF9C27B0), isScatter: true),
    _Sym('🎰', Color(0xFFFFCDD2), Color(0xFFE91E63), isBonus: true),
    _Sym('7️⃣', Color(0xFFFF8A80), Color(0xFFFF1744)),
    _Sym('🔔', Color(0xFFFFF59D), Color(0xFFFFEB3B)),
    _Sym('🍒', Color(0xFFFF8A65), Color(0xFFFF5722)),
    _Sym('🍋', Color(0xFFE6EE9C), Color(0xFFCDDC39)),
    _Sym('🍊', Color(0xFFFFCC80), Color(0xFFFF9800)),
    _Sym('🍇', Color(0xFFCE93D8), Color(0xFF9C27B0)),
    _Sym('💰', Color(0xFFFFE082), Color(0xFFFFA000)),
  ];

  static _Sym get(int i) => list[i % list.length];
}

// =============================================================================
// MAIN WIDGET
// =============================================================================

class EmbeddedSlotMockup extends StatefulWidget {
  final SlotLabProvider provider;
  final int reels;
  final int rows;
  final VoidCallback? onSpin;
  final void Function(ForcedOutcome)? onForcedSpin;

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC CALLBACKS — Trigger stages exactly when visual events occur
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when SPIN button is pressed (visual spin start)
  final VoidCallback? onSpinStart;

  /// Called when each reel visually stops (reelIndex: 0-4)
  final void Function(int reelIndex)? onReelStop;

  /// Called when anticipation state begins (last reel)
  final VoidCallback? onAnticipation;

  /// Called when all reels have stopped and result is revealing
  final VoidCallback? onReveal;

  /// Called when win celebration starts (with win tier)
  final void Function(WinType winType, double amount)? onWinStart;

  /// Called when win celebration ends
  final VoidCallback? onWinEnd;

  const EmbeddedSlotMockup({
    super.key,
    required this.provider,
    this.reels = 5,
    this.rows = 3,
    this.onSpin,
    this.onForcedSpin,
    this.onSpinStart,
    this.onReelStop,
    this.onAnticipation,
    this.onReveal,
    this.onWinStart,
    this.onWinEnd,
  });

  @override
  State<EmbeddedSlotMockup> createState() => _EmbeddedSlotMockupState();
}

class _EmbeddedSlotMockupState extends State<EmbeddedSlotMockup>
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _reelController;
  late AnimationController _winController;
  Timer? _jackpotTimer;

  // Game State
  GameState _gameState = GameState.idle;
  WinType _winType = WinType.noWin;

  // Balance & Bet
  double _balance = 10000.0;
  double _betPerLine = 0.10;
  int _lines = 25;
  double get _totalBet => _betPerLine * _lines;

  // Jackpots (smooth increment, no rolling)
  double _grandJp = 1234567.89;
  double _majorJp = 123456.78;
  double _minorJp = 12345.67;
  double _miniJp = 1234.56;

  // Reels
  late List<List<int>> _symbols;
  late List<bool> _reelStopped;
  final _rng = math.Random();

  // Win Display
  double _winAmount = 0;
  double _displayedWin = 0; // For rollup animation
  Timer? _rollupTimer;

  // Auto/Turbo
  bool _autoSpin = false;
  bool _turbo = false;

  @override
  void initState() {
    super.initState();
    _initSymbols();
    _initAnimations();
    _startJackpotTicker();
  }

  void _initSymbols() {
    _symbols = List.generate(
        widget.reels, (_) => List.generate(widget.rows, (_) => _rng.nextInt(10)));
    _reelStopped = List.filled(widget.reels, true);
  }

  void _initAnimations() {
    _reelController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _turbo ? 800 : 2000),
    );

    _winController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  void _startJackpotTicker() {
    // Smooth increment every 100ms (no rolling animation)
    _jackpotTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _grandJp += 1.23 + _rng.nextDouble() * 0.77;
        _majorJp += 0.45 + _rng.nextDouble() * 0.25;
        _minorJp += 0.12 + _rng.nextDouble() * 0.08;
        _miniJp += 0.03 + _rng.nextDouble() * 0.02;
      });
    });
  }

  @override
  void dispose() {
    _jackpotTimer?.cancel();
    _rollupTimer?.cancel();
    _reelController.dispose();
    _winController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // SPIN LOGIC (following middleware guide)
  // ===========================================================================

  void _startSpin() {
    if (_gameState != GameState.idle) return;
    if (_balance < _totalBet) return;

    setState(() {
      _gameState = GameState.spinning;
      _winType = WinType.noWin;
      _winAmount = 0;
      _displayedWin = 0;
      _balance -= _totalBet;
      _reelStopped = List.filled(widget.reels, false);
    });

    // VISUAL-SYNC: Trigger SPIN_START stage immediately on visual spin
    widget.onSpinStart?.call();
    widget.onSpin?.call();

    // Update animation duration for turbo
    _reelController.duration = Duration(milliseconds: _turbo ? 800 : 2000);

    // Start spin animation
    _reelController.forward(from: 0).then((_) {
      _revealResult();
    });

    // Staggered reel stops
    _scheduleReelStops();
  }

  void _startForcedSpin(ForcedOutcome outcome) {
    if (_gameState != GameState.idle) return;

    setState(() {
      _gameState = GameState.spinning;
      _winType = WinType.noWin;
      _winAmount = 0;
      _displayedWin = 0;
      _balance -= _totalBet;
      _reelStopped = List.filled(widget.reels, false);
    });

    // VISUAL-SYNC: Trigger SPIN_START stage immediately on visual spin
    widget.onSpinStart?.call();
    widget.onForcedSpin?.call(outcome);

    _reelController.duration = Duration(milliseconds: _turbo ? 800 : 2000);
    _reelController.forward(from: 0).then((_) {
      _revealResult(forcedOutcome: outcome);
    });

    _scheduleReelStops();
  }

  void _scheduleReelStops() {
    final baseDelay = _turbo ? 100 : 250;

    for (int i = 0; i < widget.reels; i++) {
      Future.delayed(Duration(milliseconds: baseDelay * (i + 1)), () {
        if (!mounted) return;
        setState(() {
          _reelStopped[i] = true;
        });

        // ═══════════════════════════════════════════════════════════════════
        // VISUAL-SYNC: Trigger REEL_STOP_i stage IMMEDIATELY when reel visual stops
        // This ensures audio is perfectly synchronized with visual animation
        // ═══════════════════════════════════════════════════════════════════
        widget.onReelStop?.call(i);

        // Check for anticipation on second-to-last reel
        if (i == widget.reels - 2) {
          // Could trigger anticipation based on symbols
          // For now, randomly trigger 20% of the time
          if (_rng.nextDouble() < 0.2) {
            setState(() => _gameState = GameState.anticipation);
            // VISUAL-SYNC: Trigger ANTICIPATION stage
            widget.onAnticipation?.call();
          }
        }
      });
    }
  }

  void _revealResult({ForcedOutcome? forcedOutcome}) {
    // Generate final symbols
    setState(() {
      _symbols = List.generate(
          widget.reels, (_) => List.generate(widget.rows, (_) => _rng.nextInt(10)));
      _gameState = GameState.revealing;
    });

    // VISUAL-SYNC: Trigger reveal stage when all reels stopped
    widget.onReveal?.call();

    // Check provider for actual result
    final result = widget.provider.lastResult;
    if (result != null && result.totalWin > 0) {
      final multiplier = result.totalWin / _totalBet;
      _showWin(result.totalWin, _getWinType(multiplier));
    } else {
      // Simulate wins for forced outcomes
      if (forcedOutcome != null) {
        final simWin = _simulateWinForOutcome(forcedOutcome);
        if (simWin > 0) {
          final multiplier = simWin / _totalBet;
          _showWin(simWin, _getWinType(multiplier));
          return;
        }
      }

      // No win - return to idle
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _gameState = GameState.idle);
          if (_autoSpin) _startSpin();
        }
      });
    }
  }

  WinType _getWinType(double multiplier) {
    if (multiplier >= 500) return WinType.epicWin;
    if (multiplier >= 100) return WinType.megaWin;
    if (multiplier >= 50) return WinType.bigWin;
    if (multiplier >= 10) return WinType.mediumWin;
    if (multiplier > 0) return WinType.smallWin;
    return WinType.noWin;
  }

  double _simulateWinForOutcome(ForcedOutcome outcome) {
    return switch (outcome) {
      ForcedOutcome.lose => 0,
      ForcedOutcome.smallWin => _totalBet * (2 + _rng.nextDouble() * 8),
      ForcedOutcome.mediumWin => _totalBet * (10 + _rng.nextDouble() * 40),
      ForcedOutcome.bigWin => _totalBet * (50 + _rng.nextDouble() * 50),
      ForcedOutcome.megaWin => _totalBet * (100 + _rng.nextDouble() * 400),
      ForcedOutcome.epicWin => _totalBet * (500 + _rng.nextDouble() * 500),
      ForcedOutcome.ultraWin => _totalBet * (1000 + _rng.nextDouble() * 500),
      ForcedOutcome.freeSpins => 0,
      ForcedOutcome.jackpotMini => _miniJp,
      ForcedOutcome.jackpotMinor => _minorJp,
      ForcedOutcome.jackpotMajor => _majorJp,
      ForcedOutcome.jackpotGrand => _grandJp,
      ForcedOutcome.nearMiss => 0,
      ForcedOutcome.cascade => _totalBet * (5 + _rng.nextDouble() * 10),
    };
  }

  void _showWin(double amount, WinType type) {
    setState(() {
      _gameState = GameState.celebrating;
      _winType = type;
      _winAmount = amount;
    });

    // VISUAL-SYNC: Trigger WIN_START stage when celebration begins
    widget.onWinStart?.call(type, amount);

    _winController.forward(from: 0);

    // Rollup animation
    _startRollup(amount);
  }

  void _startRollup(double target) {
    _rollupTimer?.cancel();
    _displayedWin = 0;

    final steps = _winType == WinType.bigWin ||
            _winType == WinType.megaWin ||
            _winType == WinType.epicWin
        ? 60
        : 30;
    final increment = target / steps;
    int step = 0;

    _rollupTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      step++;
      setState(() {
        _displayedWin = (increment * step).clamp(0, target);
      });

      if (step >= steps) {
        timer.cancel();
        setState(() {
          _displayedWin = target;
          _balance += target;
        });

        // Return to idle after celebration
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            // VISUAL-SYNC: Trigger WIN_END stage when celebration finishes
            widget.onWinEnd?.call();

            setState(() {
              _gameState = GameState.idle;
              _winType = WinType.noWin;
            });
            if (_autoSpin) _startSpin();
          }
        });
      }
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_T.bg1, _T.bg2, _T.bg3],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            _buildHeader(),
            _buildJackpotBar(),
            Expanded(child: _buildReelArea()),
            _buildInfoBar(),
            _buildControlBar(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: _T.headerGradient),
        border: Border(bottom: BorderSide(color: _T.border)),
      ),
      child: Row(
        children: [
          // Balance
          _buildInfoChip(
            Icons.account_balance_wallet,
            '\$${_balance.toStringAsFixed(2)}',
            _T.gold,
          ),

          const Spacer(),

          // Game Title
          const Text(
            'FLUXFORGE SLOTS',
            style: TextStyle(
              color: _T.text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),

          const Spacer(),

          // State indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _getStateColor().withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _getStateColor().withOpacity(0.5), width: 2),
            ),
            child: Text(
              _getStateName(),
              style: TextStyle(
                color: _getStateColor(),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStateColor() => switch (_gameState) {
        GameState.idle => _T.textDim,
        GameState.spinning => _T.spin,
        GameState.anticipation => _T.jpMajor,
        GameState.revealing => _T.winMedium,
        GameState.celebrating => _getWinColor(),
        GameState.bonusGame => _T.jpMinor,
      };

  String _getStateName() => switch (_gameState) {
        GameState.idle => 'READY',
        GameState.spinning => 'SPINNING',
        GameState.anticipation => 'ANTICIPATION',
        GameState.revealing => 'REVEALING',
        GameState.celebrating => _winType.name.toUpperCase(),
        GameState.bonusGame => 'BONUS',
      };

  Color _getWinColor() => switch (_winType) {
        WinType.noWin => _T.textDim,
        WinType.smallWin => _T.winSmall,
        WinType.mediumWin => _T.winMedium,
        WinType.bigWin => _T.winBig,
        WinType.megaWin => _T.winMega,
        WinType.epicWin => _T.winEpic,
      };

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // JACKPOT BAR
  // ===========================================================================

  Widget _buildJackpotBar() {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_T.bg2, _T.bg3.withOpacity(0.5)],
        ),
        border: Border(bottom: BorderSide(color: _T.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Expanded(child: _buildJackpot('MINI', _miniJp, _T.jpMini)),
          const SizedBox(width: 12),
          Expanded(child: _buildJackpot('MINOR', _minorJp, _T.jpMinor)),
          const SizedBox(width: 12),
          Expanded(child: _buildJackpot('MAJOR', _majorJp, _T.jpMajor)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _buildJackpot('★ GRAND ★', _grandJp, _T.jpGrand, isGrand: true)),
        ],
      ),
    );
  }

  Widget _buildJackpot(String label, double value, Color color, {bool isGrand = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: isGrand ? 3 : 2),
        boxShadow: isGrand
            ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 24, spreadRadius: 2)]
            : [BoxShadow(color: color.withOpacity(0.2), blurRadius: 12)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: isGrand ? 16 : 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${_formatJackpot(value)}',
            style: TextStyle(
              color: color,
              fontSize: isGrand ? 32 : 22,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              shadows: [Shadow(color: color.withOpacity(0.6), blurRadius: 12)],
            ),
          ),
        ],
      ),
    );
  }

  String _formatJackpot(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(2);
  }

  // ===========================================================================
  // REEL AREA
  // ===========================================================================

  Widget _buildReelArea() {
    return Stack(
      children: [
        // Reel background
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _T.reelBgGradient,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.borderLight, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellW = (constraints.maxWidth - 20) / widget.reels;
                final cellH = (constraints.maxHeight - 20) / widget.rows;
                final cellSize = math.min(cellW, cellH) - 12;

                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(widget.reels, (r) => _buildReel(r, cellSize)),
                  ),
                );
              },
            ),
          ),
        ),

        // Win overlay
        if (_gameState == GameState.celebrating) _buildWinOverlay(),
      ],
    );
  }

  Widget _buildReel(int reelIdx, double cellSize) {
    final isStopped = _reelStopped[reelIdx];
    final isSpinning = _gameState == GameState.spinning ||
        _gameState == GameState.anticipation;

    return AnimatedBuilder(
      animation: _reelController,
      builder: (context, _) {
        return Container(
          width: cellSize + 8,
          decoration: BoxDecoration(
            color: _T.bg1,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: !isStopped && isSpinning ? _T.spin.withOpacity(0.3) : _T.border,
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(widget.rows, (rowIdx) {
              final symbolId = _symbols[reelIdx][rowIdx];

              // During spin, show random symbols
              final displayId = !isStopped && isSpinning
                  ? (_rng.nextInt(10) + (_reelController.value * 100).toInt()) % 10
                  : symbolId;

              final symbol = _Sym.get(displayId);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: cellSize,
                height: cellSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _T.cellGradient,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: symbol.isSpecial
                        ? symbol.c1.withOpacity(0.6)
                        : _T.border.withOpacity(0.5),
                    width: symbol.isSpecial ? 2 : 1,
                  ),
                  boxShadow: symbol.isSpecial
                      ? [BoxShadow(color: symbol.c1.withOpacity(0.4), blurRadius: 12)]
                      : null,
                ),
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 100),
                    opacity: !isStopped && isSpinning ? 0.5 : 1.0,
                    child: Text(
                      symbol.icon,
                      style: TextStyle(
                        fontSize: cellSize * 0.6,
                        shadows: [
                          Shadow(color: symbol.c1.withOpacity(0.8), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // WIN OVERLAY
  // ===========================================================================

  Widget _buildWinOverlay() {
    return AnimatedBuilder(
      animation: _winController,
      builder: (context, _) {
        final scale = 0.6 + _winController.value * 0.4;
        final opacity = _winController.value;
        final color = _getWinColor();

        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85 * opacity),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Win Type Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.7)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(color: color.withOpacity(0.6), blurRadius: 40, spreadRadius: 8),
                      ],
                    ),
                    child: Text(
                      _getWinTypeLabel(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Rollup Amount
                  Text(
                    '\$${_displayedWin.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      shadows: [
                        Shadow(color: color, blurRadius: 30),
                        Shadow(color: color.withOpacity(0.5), blurRadius: 60),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Multiplier
                  Text(
                    '${(_winAmount / _totalBet).toStringAsFixed(1)}x',
                    style: TextStyle(
                      color: color.withOpacity(0.8),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getWinTypeLabel() => switch (_winType) {
        WinType.noWin => '',
        WinType.smallWin => 'WIN',
        WinType.mediumWin => 'NICE WIN',
        WinType.bigWin => 'BIG WIN',
        WinType.megaWin => 'MEGA WIN',
        WinType.epicWin => 'EPIC WIN',
      };

  // ===========================================================================
  // INFO BAR
  // ===========================================================================

  Widget _buildInfoBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: _T.bg4,
        border: Border(
          top: BorderSide(color: _T.border.withOpacity(0.5)),
          bottom: BorderSide(color: _T.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildInfoItem('LINES', '$_lines'),
          _buildInfoDivider(),
          _buildInfoItem('BET/LINE', '\$${_betPerLine.toStringAsFixed(2)}'),
          _buildInfoDivider(),
          _buildInfoItem('TOTAL BET', '\$${_totalBet.toStringAsFixed(2)}', highlight: true),
          _buildInfoDivider(),
          _buildInfoItem(
            'LAST WIN',
            _winAmount > 0 ? '\$${_winAmount.toStringAsFixed(2)}' : '-',
            color: _winAmount > 0 ? _getWinColor() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {bool highlight = false, Color? color}) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(color: _T.textMuted, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? (highlight ? _T.gold : _T.text),
            fontSize: 18,
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildInfoDivider() {
    return Container(width: 2, height: 24, color: _T.border.withOpacity(0.5));
  }

  // ===========================================================================
  // CONTROL BAR
  // ===========================================================================

  Widget _buildControlBar() {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_T.bg4, _T.bg2],
        ),
      ),
      child: Row(
        children: [
          // Auto/Turbo toggles
          _buildToggle('AUTO', _autoSpin, () => setState(() => _autoSpin = !_autoSpin)),
          const SizedBox(width: 12),
          _buildToggle('TURBO', _turbo, () => setState(() => _turbo = !_turbo)),

          const SizedBox(width: 20),

          // Bet adjuster
          _buildBetControl(),

          const Spacer(),

          // SPIN BUTTON
          _buildSpinButton(),

          const Spacer(),

          // Quick outcome buttons
          _buildOutcomeBtn('BIG', _T.winBig, ForcedOutcome.bigWin),
          const SizedBox(width: 10),
          _buildOutcomeBtn('MEGA', _T.winMega, ForcedOutcome.megaWin),
          const SizedBox(width: 10),
          _buildOutcomeBtn('EPIC', _T.winEpic, ForcedOutcome.epicWin),
          const SizedBox(width: 10),
          _buildOutcomeBtn('JP', _T.jpGrand, ForcedOutcome.jackpotGrand),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(colors: [_T.spin, _T.spin.withOpacity(0.7)])
              : null,
          color: active ? null : _T.bg5,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? _T.spin : _T.border, width: active ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _T.textDim,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBetControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _T.bg5,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _T.border),
      ),
      child: Row(
        children: [
          _buildBetBtn(Icons.remove, () {
            if (_betPerLine > 0.05) setState(() => _betPerLine -= 0.05);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '\$${_betPerLine.toStringAsFixed(2)}',
              style: const TextStyle(
                color: _T.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          _buildBetBtn(Icons.add, () {
            if (_betPerLine < 10) setState(() => _betPerLine += 0.05);
          }),
        ],
      ),
    );
  }

  Widget _buildBetBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _T.bg3,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: _T.silver, size: 22),
      ),
    );
  }

  Widget _buildSpinButton() {
    final canSpin = _gameState == GameState.idle && _balance >= _totalBet;

    return GestureDetector(
      onTap: canSpin ? _startSpin : null,
      child: Container(
        width: 200,
        height: 68,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: canSpin
                ? [_T.spinBright, _T.spin]
                : [_T.bg5, _T.bg4],
          ),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(
            color: canSpin ? _T.spinBright : _T.border,
            width: 3,
          ),
          boxShadow: canSpin
              ? [BoxShadow(color: _T.spin.withOpacity(0.5), blurRadius: 30, spreadRadius: 4)]
              : null,
        ),
        child: Center(
          child: _gameState == GameState.spinning ||
                  _gameState == GameState.anticipation
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white),
                )
              : Text(
                  'SPIN',
                  style: TextStyle(
                    color: canSpin ? Colors.white : _T.textMuted,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildOutcomeBtn(String label, Color color, ForcedOutcome outcome) {
    return GestureDetector(
      onTap: () => _startForcedSpin(outcome),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
