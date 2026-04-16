import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// FluxForge SlotLab — 5×3 Professional Slot Cabinet Widget
///
/// Production Flutter implementation of slotlab_ultimate.html mockup.
/// Features:
/// - 5×3 reel grid with 8 symbol types
/// - IGT-style staggered reel stops
/// - Anticipation animation on reels 4-5 for big outcomes
/// - Jackpot bar (Mini/Major/Grand/Mega)
/// - Win presenter overlay with tier display
/// - Bet controls, balance tracking
/// - Phase-system spin button (Spin → Stop → Skip)
/// - Win line highlight, feature badges
///
/// Design language: #06060A bg, gold accents, glass morphism, JetBrains Mono
class SlotCabinetWidget extends StatefulWidget {
  /// Callback when a spin completes with outcome data
  final void Function(SpinOutcome outcome)? onSpinComplete;

  /// Callback when stage changes (idle, base, anticipation, win_small, etc.)
  final void Function(String stage)? onStageChange;

  /// External forced outcome (null = random)
  final String? forcedOutcome;

  const SlotCabinetWidget({
    super.key,
    this.onSpinComplete,
    this.onStageChange,
    this.forcedOutcome,
  });

  @override
  State<SlotCabinetWidget> createState() => _SlotCabinetWidgetState();
}

// ═══════════════════════════════════════════════════════════════════════════
// SYMBOL DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

enum SymbolType {
  diamond('💎', 'Diamond', Color(0xFF1888DD), Color(0xFF8AF0FF)),
  seven('7️⃣', 'Seven', Color(0xFFE8A800), Color(0xFFFFE880)),
  bell('🔔', 'Bell', Color(0xFFCC8000), Color(0xFFFFD090)),
  bar('📊', 'Bar', Color(0xFF5070D0), Color(0xFFD0E0FF)),
  cherry('🍒', 'Cherry', Color(0xFFDD2020), Color(0xFFFF9090)),
  lemon('🍋', 'Lemon', Color(0xFFB0C000), Color(0xFFF8F880)),
  wild('⚡', 'Wild', Color(0xFF9010E0), Color(0xFFF090FF)),
  scatter('🌟', 'Scatter', Color(0xFF00B880), Color(0xFF80FFE8));

  final String icon;
  final String name;
  final Color primary;
  final Color highlight;
  const SymbolType(this.icon, this.name, this.primary, this.highlight);
}

// ═══════════════════════════════════════════════════════════════════════════
// SPIN OUTCOME
// ═════════════════════════���════════════════════════════��════════════════════

class SpinOutcome {
  final List<List<SymbolType>> grid; // 5 reels × 3 rows
  final String tier; // 'base', 'ws', 'wb', 'ft', 'jk'
  final double winAmount;
  final List<int> winningPositions; // flat indices 0-14 that are part of win

  const SpinOutcome({
    required this.grid,
    required this.tier,
    required this.winAmount,
    this.winningPositions = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SPIN PHASE
// ═══════════════════════════════���═══════════════════════���═══════════════════

enum SpinPhase { spin, stop, skip }

// ═══════════════════════════════════════════════════════════════════════════
// STATE
// ═════��═══════════��═════════════════════════════��═══════════════════════════

class _SlotCabinetWidgetState extends State<SlotCabinetWidget>
    with TickerProviderStateMixin {
  final _rng = math.Random();

  // Reel state
  static const int _reelCount = 5;
  static const int _rowCount = 3;

  // Reel strips (symbol indices for each reel)
  late final List<List<SymbolType>> _reelStrips;

  // Current visible symbols (5 reels × 3 visible)
  List<List<SymbolType>> _visibleGrid = [];

  // Animation
  late List<AnimationController> _reelControllers;
  late List<Animation<double>> _reelAnimations;
  List<bool> _reelSpinning = List.filled(5, false);
  List<bool> _reelAnticipating = List.filled(5, false);

  // Game state
  SpinPhase _phase = SpinPhase.spin;
  bool _spinning = false;
  double _balance = 1247.60;
  int _betIdx = 1;
  static const List<double> _bets = [0.10, 0.20, 0.50, 1.00, 2.00, 5.00, 10.00];
  double _lastWin = 0;
  String _stage = 'idle';
  SpinOutcome? _lastOutcome;
  bool _showWinPresenter = false;
  bool _showWinLine = false;
  List<int> _winPositions = [];

  // Jackpot values
  double _jpMini = 42.80;
  double _jpMajor = 1248.50;
  double _jpGrand = 48920.00;
  double _jpMega = 312741.22;

  // Jackpot tick timer
  Timer? _jpTimer;

  @override
  void initState() {
    super.initState();
    _initReelStrips();
    _initGrid();
    _initAnimations();
    _startJackpotTicker();
  }

  void _initReelStrips() {
    // Each reel has a strip of symbols that cycle
    final types = SymbolType.values;
    _reelStrips = List.generate(_reelCount, (r) {
      return List.generate(20, (i) => types[(i + r * 3) % types.length]);
    });
  }

  void _initGrid() {
    _visibleGrid = List.generate(_reelCount, (r) {
      return List.generate(_rowCount, (row) => _reelStrips[r][(row + 2) % _reelStrips[r].length]);
    });
  }

  void _initAnimations() {
    _reelControllers = List.generate(_reelCount, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 600 + i * 350),
      );
    });
    _reelAnimations = _reelControllers.map((c) {
      return CurvedAnimation(parent: c, curve: Curves.easeOutBack);
    }).toList();
  }

  void _startJackpotTicker() {
    _jpTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(() {
        _jpMini += _rng.nextDouble() * 0.03;
        _jpMajor += _rng.nextDouble() * 0.12;
        _jpGrand += _rng.nextDouble() * 0.55;
        _jpMega += _rng.nextDouble() * 1.10;
      });
    });
  }

  @override
  void dispose() {
    _jpTimer?.cancel();
    for (final c in _reelControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SPIN MECHANICS
  // ═══════════════════════════════════════════════════════════════════════

  void _handleSpinClick() {
    switch (_phase) {
      case SpinPhase.spin:
        _startSpin();
      case SpinPhase.stop:
        _stopReelsEarly();
      case SpinPhase.skip:
        _closeWinPresenter();
    }
  }

  void _startSpin() {
    if (_spinning) return;
    final bet = _bets[_betIdx] * 25; // 25 lines
    if (_balance < bet) return;

    setState(() {
      _spinning = true;
      _phase = SpinPhase.stop;
      _balance -= bet;
      _lastWin = 0;
      _showWinPresenter = false;
      _showWinLine = false;
      _winPositions = [];
      _reelSpinning = List.filled(5, true);
      _reelAnticipating = List.filled(5, false);
      _stage = 'base';
    });
    widget.onStageChange?.call('base');

    // Determine outcome
    final forced = widget.forcedOutcome;
    final outcome = _determineOutcome(forced);
    final isBig = outcome == 'wb' || outcome == 'ft' || outcome == 'jk';

    // Generate result grid
    final resultGrid = _generateResultGrid(outcome);

    // Staggered reel stops
    final delays = [
      680, 1030, 1380,
      isBig ? 2000 : 1760,
      isBig ? 2520 : 2140,
    ];

    for (int r = 0; r < _reelCount; r++) {
      // Anticipation on reels 3-4 for big outcomes
      if (isBig && r >= 3) {
        Future.delayed(Duration(milliseconds: delays[r] - 380), () {
          if (!mounted) return;
          setState(() => _reelAnticipating[r] = true);
          if (r == 3) {
            setState(() => _stage = 'anticipation');
            widget.onStageChange?.call('anticipation');
          }
        });
      }

      Future.delayed(Duration(milliseconds: delays[r]), () {
        if (!mounted) return;
        _stopReel(r, resultGrid, r == _reelCount - 1, outcome);
      });
    }
  }

  String _determineOutcome(String? forced) {
    if (forced != null && forced != 'r') return forced;
    final v = _rng.nextDouble();
    if (v < 0.44) return 'base';
    if (v < 0.62) return 'ws';
    if (v < 0.76) return 'wb';
    if (v < 0.86) return 'ft';
    if (v < 0.92) return 'jk';
    return 'base';
  }

  List<List<SymbolType>> _generateResultGrid(String outcome) {
    final grid = List.generate(_reelCount, (r) {
      return List.generate(_rowCount, (_) => SymbolType.values[_rng.nextInt(8)]);
    });

    // For winning outcomes, place matching symbols on center row
    switch (outcome) {
      case 'ws': // Small win — 3 matching
        final sym = SymbolType.values[_rng.nextInt(6)]; // Low symbols
        for (int r = 0; r < 3; r++) grid[r][1] = sym;
      case 'wb': // Big win — 4+ matching
        final sym = [SymbolType.diamond, SymbolType.seven, SymbolType.bell][_rng.nextInt(3)];
        for (int r = 0; r < 4 + (_rng.nextBool() ? 1 : 0); r++) grid[r][1] = sym;
      case 'ft': // Feature trigger — scatters
        final scatterPositions = [0, 2, 4]; // Reels 1, 3, 5
        for (final r in scatterPositions) {
          grid[r][_rng.nextInt(3)] = SymbolType.scatter;
        }
      case 'jk': // Jackpot — 5 diamonds
        for (int r = 0; r < 5; r++) grid[r][1] = SymbolType.diamond;
    }

    return grid;
  }

  void _stopReel(int r, List<List<SymbolType>> resultGrid, bool isLast, String outcome) {
    if (!mounted) return;

    setState(() {
      _reelSpinning[r] = false;
      _reelAnticipating[r] = false;
      _visibleGrid[r] = resultGrid[r];
    });

    // Bounce animation
    _reelControllers[r].reset();
    _reelControllers[r].forward();

    if (isLast) {
      _onAllReelsStopped(resultGrid, outcome);
    }
  }

  void _stopReelsEarly() {
    // Quick stop all
    for (int r = 0; r < _reelCount; r++) {
      if (_reelSpinning[r]) {
        setState(() {
          _reelSpinning[r] = false;
          _reelAnticipating[r] = false;
        });
      }
    }
  }

  void _onAllReelsStopped(List<List<SymbolType>> grid, String outcome) {
    final bet = _bets[_betIdx] * 25;
    double win = 0;
    List<int> winPos = [];

    switch (outcome) {
      case 'ws':
        win = bet * (1.5 + _rng.nextDouble() * 3);
        winPos = [1, 6, 11]; // Center row first 3
        _stage = 'win_small';
      case 'wb':
        win = bet * (8 + _rng.nextDouble() * 20);
        winPos = [1, 6, 11, 16]; // Center row 4+
        if (_rng.nextBool()) winPos.add(21);
        _stage = 'win_big';
      case 'ft':
        win = bet * (5 + _rng.nextDouble() * 10);
        winPos = [0, 10, 20]; // Scatter positions
        _stage = 'feature';
      case 'jk':
        win = bet * (50 + _rng.nextDouble() * 200);
        winPos = [1, 6, 11, 16, 21]; // All center row
        _stage = 'jackpot';
      default:
        _stage = 'idle';
    }

    _balance += win;

    final spinOutcome = SpinOutcome(
      grid: grid,
      tier: outcome,
      winAmount: win,
      winningPositions: winPos,
    );

    setState(() {
      _spinning = false;
      _lastWin = win;
      _lastOutcome = spinOutcome;
      _winPositions = winPos;

      if (win > 0) {
        _showWinLine = true;
        if (outcome != 'base' && outcome != 'ws') {
          _phase = SpinPhase.skip;
          _showWinPresenter = true;
        } else {
          _phase = SpinPhase.spin;
        }
      } else {
        _phase = SpinPhase.spin;
      }
    });

    widget.onStageChange?.call(_stage);
    widget.onSpinComplete?.call(spinOutcome);
  }

  void _closeWinPresenter() {
    setState(() {
      _showWinPresenter = false;
      _phase = SpinPhase.spin;
    });
  }

  void _changeBet(int delta) {
    setState(() {
      _betIdx = (_betIdx + delta).clamp(0, _bets.length - 1);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════��═════════════════════════════════��═══════════════

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF06060A),
        ),
        child: Center(
          child: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildJackpotBar(),
                const SizedBox(height: 7),
                _buildCabinet(),
                const SizedBox(height: 5),
                _buildWinBar(),
                const SizedBox(height: 3),
                _buildFeatureBadges(),
                const SizedBox(height: 5),
                _buildControlBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _handleSpinClick();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // JACKPOT BAR
  // ════════════════════════════════���══════════════════════════════��═══════

  Widget _buildJackpotBar() {
    return Row(
      children: [
        _buildJackpotTier('MINI', _jpMini, const Color(0xFF4CAF50), 13),
        const SizedBox(width: 4),
        _buildJackpotTier('MAJOR', _jpMajor, const Color(0xFF8B5CF6), 13),
        const SizedBox(width: 4),
        _buildJackpotTier('GRAND', _jpGrand, const Color(0xFFFFA500), 14),
        const SizedBox(width: 4),
        _buildJackpotTier('MEGA', _jpMega, const Color(0xFFFF5050), 16),
      ],
    );
  }

  Widget _buildJackpotTier(String label, double value, Color color, double fontSize) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 7,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: color.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '€ ${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},')}',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══���═════════════════════════════════════════════════════���══════════════
  // CABINET — The main reel window
  // ══════════════════��════════════════════════════════════════════════════

  Widget _buildCabinet() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C1C2C), Color(0xFF111120), Color(0xFF0A0A16)],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.75), blurRadius: 50, offset: const Offset(0, 12)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          // Reel window
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF020208),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.95), blurRadius: 12, offset: const Offset(0, 3)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(4, 0)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(-4, 0)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  // Reel grid
                  _buildReelGrid(),
                  // Win line highlight
                  if (_showWinLine)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 78.0, // Center row position
                      height: 78,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFFFFD700).withValues(alpha: 0.02),
                              const Color(0xFFFFD700).withValues(alpha: 0.07),
                              const Color(0xFFFFD700).withValues(alpha: 0.02),
                            ],
                          ),
                          border: Border(
                            top: BorderSide(color: const Color(0xFFFFD700).withValues(alpha: 0.12)),
                            bottom: BorderSide(color: const Color(0xFFFFD700).withValues(alpha: 0.12)),
                          ),
                        ),
                      ),
                    ),
                  // Top depth fade
                  Positioned(
                    top: 0, left: 0, right: 0,
                    height: 90,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF020208).withValues(alpha: 0.92),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Bottom depth fade
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    height: 90,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            const Color(0xFF020208).withValues(alpha: 0.92),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Win presenter overlay
          if (_showWinPresenter) _buildWinPresenter(),
        ],
      ),
    );
  }

  // ��══════════════════════════════════════════════════════════════════════
  // REEL GRID — 5×3 symbol matrix
  // ════��══════════���═════════════════════════════════════��═════════════════

  Widget _buildReelGrid() {
    return SizedBox(
      height: 234,
      child: Row(
        children: List.generate(_reelCount * 2 - 1, (i) {
          if (i.isOdd) {
            // Separator rail
            return Container(
              width: 7,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF121220).withValues(alpha: 0.95),
                    const Color(0xFF1E1E32).withValues(alpha: 0.85),
                    const Color(0xFF0E0E1A).withValues(alpha: 0.95),
                  ],
                ),
              ),
            );
          }
          final r = i ~/ 2;
          return Expanded(child: _buildReelColumn(r));
        }),
      ),
    );
  }

  Widget _buildReelColumn(int reelIndex) {
    final isSpinning = _reelSpinning[reelIndex];
    final isAnticipating = _reelAnticipating[reelIndex];

    return AnimatedBuilder(
      animation: _reelAnimations[reelIndex],
      builder: (context, child) {
        return Container(
          decoration: isSpinning
              ? BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4296FF).withValues(alpha: 0.06),
                      blurRadius: 30,
                    ),
                  ],
                )
              : null,
          child: Column(
            children: List.generate(_rowCount, (row) {
              final sym = _visibleGrid[reelIndex][row];
              final flatIdx = reelIndex * (_rowCount + 2) + row; // approximate
              final isWin = _winPositions.contains(reelIndex * 5 + row);

              return _buildSymbolCell(
                sym,
                isSpinning: isSpinning,
                isAnticipating: isAnticipating,
                isWin: isWin && _showWinLine,
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildSymbolCell(
    SymbolType sym, {
    bool isSpinning = false,
    bool isAnticipating = false,
    bool isWin = false,
  }) {
    return SizedBox(
      height: 78,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: RadialGradient(
              center: const Alignment(-0.36, -0.44),
              radius: 0.9,
              colors: [sym.highlight, sym.primary, sym.primary.withValues(alpha: 0.6)],
            ),
            boxShadow: [
              BoxShadow(
                color: sym.primary.withValues(alpha: isWin ? 0.7 : 0.35),
                blurRadius: isWin ? 26 : 10,
                offset: const Offset(0, 2),
              ),
              if (isWin)
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                  blurRadius: 50,
                ),
            ],
            border: sym == SymbolType.wild || sym == SymbolType.scatter
                ? Border.all(color: sym.highlight.withValues(alpha: 0.45))
                : null,
          ),
          child: Stack(
            children: [
              // Shine overlay
              Positioned(
                top: 0, left: 0, right: 0,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.04),
                      ],
                    ),
                  ),
                ),
              ),
              // Symbol icon
              Center(
                child: isSpinning
                    ? const SizedBox.shrink()
                    : Text(
                        sym.icon,
                        style: const TextStyle(fontSize: 32, height: 1),
                      ),
              ),
              // Win golden border
              if (isWin)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.7),
                        width: 2,
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

  // ═══════════════════════════════════════════════════════════════════════
  // WIN PRESENTER
  // ══════════════��══════════════════════════════════���═════════════════════

  Widget _buildWinPresenter() {
    final outcome = _lastOutcome;
    if (outcome == null) return const SizedBox.shrink();

    final tierLabel = switch (outcome.tier) {
      'ws' => 'WIN',
      'wb' => 'BIG WIN',
      'ft' => 'FREE SPINS',
      'jk' => 'JACKPOT',
      _ => 'WIN',
    };
    final tierColor = switch (outcome.tier) {
      'ws' => const Color(0xFFFFD700),
      'wb' => const Color(0xFFFFD700),
      'ft' => const Color(0xFF42D4FF),
      'jk' => const Color(0xFFFF5050),
      _ => const Color(0xFFFFD700),
    };

    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeWinPresenter,
        child: Container(
          color: Colors.black.withValues(alpha: 0.65),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tierLabel,
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: tierColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '€ ${outcome.winAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFFD700),
                    shadows: [
                      Shadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                        blurRadius: 40,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(outcome.winAmount / (_bets[_betIdx] * 25)).toStringAsFixed(1)}× BET',
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildWpButton('COLLECT', const Color(0xFFFFD700), _closeWinPresenter),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWpButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.08)],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: color,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WIN BAR
  // ══════════════════════════════════════════════��════════════════════════

  Widget _buildWinBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF080812).withValues(alpha: 0.9),
            const Color(0xFF05050C).withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildWinBarItem('BALANCE', '€ ${_balance.toStringAsFixed(2)}', false),
          Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.08)),
          _buildWinBarItem('WIN', '€ ${_lastWin.toStringAsFixed(2)}', _lastWin > 0),
          Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.08)),
          _buildWinBarItem('BET', '€ ${(_bets[_betIdx] * 25).toStringAsFixed(2)}', false),
        ],
      ),
    );
  }

  Widget _buildWinBarItem(String label, String value, bool isGold) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 7,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Colors.white.withValues(alpha: 0.28),
          ),
        ),
        const SizedBox(height: 1),
        SizedBox(
          width: 100,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isGold ? const Color(0xFFFFD700) : Colors.white.withValues(alpha: 0.93),
              shadows: isGold
                  ? [Shadow(color: const Color(0xFFFFD700).withValues(alpha: 0.4), blurRadius: 10)]
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FEATURE BADGES
  // ���════════════════════════════════════════════════════════��═════════════

  Widget _buildFeatureBadges() {
    final outcome = _lastOutcome;
    if (outcome == null || outcome.tier == 'base') return const SizedBox(height: 22);

    return SizedBox(
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (outcome.tier == 'ft')
            _buildBadge('FREE SPINS', const Color(0xFF42D4FF)),
          if (outcome.tier == 'wb')
            _buildBadge('BIG WIN', const Color(0xFFFFA500)),
          if (outcome.tier == 'jk')
            _buildBadge('JACKPOT', const Color(0xFFFF5050)),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Space Grotesk',
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CONTROL BAR — Bet controls + Spin button
  // ��══════════════��═══════════════════════════════════════════════════════

  Widget _buildControlBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Bet controls
        _buildBetGroup(),
        // Spin button
        _buildSpinButton(),
        // Info button
        Column(
          children: [
            _buildControlButton('ℹ', 'INFO'),
            const SizedBox(height: 4),
            _buildControlButton('⚡', 'TURBO'),
          ],
        ),
      ],
    );
  }

  Widget _buildBetGroup() {
    return Column(
      children: [
        Text(
          'BET / LINE',
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 7,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Colors.white.withValues(alpha: 0.28),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            _buildBetButton('−', () => _changeBet(-1)),
            const SizedBox(width: 4),
            SizedBox(
              width: 54,
              child: Text(
                '€ ${_bets[_betIdx].toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFD700),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _buildBetButton('+', () => _changeBet(1)),
          ],
        ),
      ],
    );
  }

  Widget _buildBetButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinButton() {
    final (ringColors, innerColor, iconColor, labelColor, icon, label) = switch (_phase) {
      SpinPhase.spin => (
        [const Color(0xFF1848AA), const Color(0xFF3A80FF), const Color(0xFF5AACFF), const Color(0xFF1848AA)],
        const Color(0xFF162C70),
        const Color(0xFFC8DEFF),
        const Color(0xFF80AAFF),
        '⟳',
        'SPIN',
      ),
      SpinPhase.stop => (
        [const Color(0xFFAA1818), const Color(0xFFFF3838), const Color(0xFFFF6060), const Color(0xFFAA1818)],
        const Color(0xFF701616),
        const Color(0xFFFFCCCC),
        const Color(0xFFFF8888),
        '⏹',
        'STOP',
      ),
      SpinPhase.skip => (
        [const Color(0xFFA07200), const Color(0xFFFFD700), const Color(0xFFFFE44C), const Color(0xFFA07200)],
        const Color(0xFF483200),
        const Color(0xFFFFF090),
        const Color(0xFFFFD000),
        '⏭',
        'SKIP',
      ),
    };

    return GestureDetector(
      onTap: _handleSpinClick,
      child: SizedBox(
        width: 70,
        height: 70,
        child: Stack(
          children: [
            // Ring
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: ringColors),
                ),
              ),
            ),
            // Inner
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: innerColor,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(icon, style: TextStyle(fontSize: 20, color: iconColor)),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: labelColor,
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
    );
  }

  Widget _buildControlButton(String icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 6,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
        ],
      ),
    );
  }
}
