/// Slot Preview Widget
///
/// Premium slot machine preview with:
/// - Animated reel spinning (blur effect)
/// - Graphic symbol icons instead of text
/// - Win line highlight overlay
/// - Anticipation visual effects
/// - Animated balance/win countup
/// - Near miss highlighting
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../providers/slot_lab_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT SYMBOL DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Symbol visual data for slot machine display
class SlotSymbol {
  final int id;
  final String name;
  final IconData icon;
  final List<Color> gradientColors;
  final double payMultiplier;
  final bool isWild;
  final bool isScatter;
  final bool isBonus;

  const SlotSymbol({
    required this.id,
    required this.name,
    required this.icon,
    required this.gradientColors,
    this.payMultiplier = 1.0,
    this.isWild = false,
    this.isScatter = false,
    this.isBonus = false,
  });

  /// Standard slot symbols with casino-grade graphics
  static const Map<int, SlotSymbol> symbols = {
    0: SlotSymbol(
      id: 0,
      name: 'WILD',
      icon: Icons.stars,
      gradientColors: [Color(0xFFFFD700), Color(0xFFFFA500)],
      payMultiplier: 10.0,
      isWild: true,
    ),
    1: SlotSymbol(
      id: 1,
      name: 'SCATTER',
      icon: Icons.scatter_plot,
      gradientColors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
      payMultiplier: 5.0,
      isScatter: true,
    ),
    2: SlotSymbol(
      id: 2,
      name: 'BONUS',
      icon: Icons.card_giftcard,
      gradientColors: [Color(0xFF40C8FF), Color(0xFF00BCD4)],
      payMultiplier: 8.0,
      isBonus: true,
    ),
    3: SlotSymbol(
      id: 3,
      name: 'SEVEN',
      icon: Icons.filter_7,
      gradientColors: [Color(0xFFFF4080), Color(0xFFE91E63)],
      payMultiplier: 7.0,
    ),
    4: SlotSymbol(
      id: 4,
      name: 'BAR',
      icon: Icons.view_headline,
      gradientColors: [Color(0xFF4CAF50), Color(0xFF8BC34A)],
      payMultiplier: 5.0,
    ),
    5: SlotSymbol(
      id: 5,
      name: 'BELL',
      icon: Icons.notifications,
      gradientColors: [Color(0xFFFFEB3B), Color(0xFFFFC107)],
      payMultiplier: 4.0,
    ),
    6: SlotSymbol(
      id: 6,
      name: 'CHERRY',
      icon: Icons.local_florist,
      gradientColors: [Color(0xFFFF5722), Color(0xFFFF9800)],
      payMultiplier: 3.0,
    ),
    7: SlotSymbol(
      id: 7,
      name: 'LEMON',
      icon: Icons.brightness_5,
      gradientColors: [Color(0xFFFFEB3B), Color(0xFFCDDC39)],
      payMultiplier: 2.0,
    ),
    8: SlotSymbol(
      id: 8,
      name: 'ORANGE',
      icon: Icons.circle,
      gradientColors: [Color(0xFFFF9800), Color(0xFFFF5722)],
      payMultiplier: 2.0,
    ),
    9: SlotSymbol(
      id: 9,
      name: 'GRAPE',
      icon: Icons.blur_circular,
      gradientColors: [Color(0xFF9C27B0), Color(0xFF673AB7)],
      payMultiplier: 1.5,
    ),
  };

  static SlotSymbol getSymbol(int id) {
    return symbols[id % symbols.length] ?? symbols[9]!;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIN LINE DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Payline path for win highlighting
class WinLine {
  final int lineId;
  final List<int> positions; // Row positions for each reel (0-2)
  final Color color;

  const WinLine({
    required this.lineId,
    required this.positions,
    required this.color,
  });

  /// Standard 5-reel paylines
  static const List<WinLine> standardLines = [
    WinLine(lineId: 0, positions: [1, 1, 1, 1, 1], color: Color(0xFFFF4080)), // Middle
    WinLine(lineId: 1, positions: [0, 0, 0, 0, 0], color: Color(0xFF40FF90)), // Top
    WinLine(lineId: 2, positions: [2, 2, 2, 2, 2], color: Color(0xFF4A9EFF)), // Bottom
    WinLine(lineId: 3, positions: [0, 1, 2, 1, 0], color: Color(0xFFFFD700)), // V-shape
    WinLine(lineId: 4, positions: [2, 1, 0, 1, 2], color: Color(0xFFE040FB)), // Inverted V
    WinLine(lineId: 5, positions: [0, 0, 1, 2, 2], color: Color(0xFF40C8FF)), // Diagonal down
    WinLine(lineId: 6, positions: [2, 2, 1, 0, 0], color: Color(0xFFFF9040)), // Diagonal up
    WinLine(lineId: 7, positions: [1, 0, 0, 0, 1], color: Color(0xFF8BC34A)), // U-shape top
    WinLine(lineId: 8, positions: [1, 2, 2, 2, 1], color: Color(0xFF00BCD4)), // U-shape bottom
    WinLine(lineId: 9, positions: [0, 1, 1, 1, 0], color: Color(0xFFFF5722)), // Flat top
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT PREVIEW WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class SlotPreviewWidget extends StatefulWidget {
  final SlotLabProvider provider;
  final int reels;
  final int rows;
  final double reelWidth;
  final double symbolHeight;
  final bool showPaylines;
  final bool showWinAmount;

  const SlotPreviewWidget({
    super.key,
    required this.provider,
    this.reels = 5,
    this.rows = 3,
    this.reelWidth = 80,
    this.symbolHeight = 70,
    this.showPaylines = true,
    this.showWinAmount = true,
  });

  @override
  State<SlotPreviewWidget> createState() => _SlotPreviewWidgetState();
}

class _SlotPreviewWidgetState extends State<SlotPreviewWidget>
    with TickerProviderStateMixin {
  // Animation controllers
  late List<AnimationController> _reelControllers;
  late AnimationController _winPulseController;
  late AnimationController _anticipationController;
  late AnimationController _countupController;

  // Animations
  late Animation<double> _winPulseAnimation;
  late Animation<double> _anticipationAnimation;

  // State
  List<List<int>> _displayGrid = [];
  List<List<int>> _previousGrid = [];
  bool _isSpinning = false;
  bool _isAnticipation = false;
  int _anticipationReelIndex = -1;
  List<int> _winningReels = [];
  List<int> _activePaylines = [];
  double _displayWinAmount = 0;
  double _targetWinAmount = 0;
  String? _winTier;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeGrid();
    widget.provider.addListener(_onProviderUpdate);
  }

  void _initializeControllers() {
    // Individual reel spin controllers with staggered timing
    _reelControllers = List.generate(widget.reels, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 800 + (index * 200)),
      );
    });

    // Win pulse animation
    _winPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _winPulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _winPulseController, curve: Curves.easeInOut),
    );

    // Anticipation shake animation
    _anticipationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _anticipationAnimation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _anticipationController, curve: Curves.elasticIn),
    );

    // Win countup animation
    _countupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _countupController.addListener(() {
      setState(() {
        _displayWinAmount = _targetWinAmount * _countupController.value;
      });
    });
  }

  void _initializeGrid() {
    _displayGrid = List.generate(
      widget.reels,
      (_) => List.generate(widget.rows, (_) => math.Random().nextInt(10)),
    );
    _previousGrid = List.generate(
      widget.reels,
      (r) => List.from(_displayGrid[r]),
    );
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    for (final controller in _reelControllers) {
      controller.dispose();
    }
    _winPulseController.dispose();
    _anticipationController.dispose();
    _countupController.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    final result = widget.provider.lastResult;
    final isPlaying = widget.provider.isPlayingStages;
    final currentStageIndex = widget.provider.currentStageIndex;
    final stages = widget.provider.lastStages;

    // Check if we're spinning
    if (isPlaying && currentStageIndex >= 0 && currentStageIndex < stages.length) {
      final currentStage = stages[currentStageIndex];

      if (currentStage.stageType == 'spin_start' && !_isSpinning) {
        _startSpin();
      } else if (currentStage.stageType == 'reel_stop') {
        // Stop a reel
        final reelIndex = currentStage.payload['reel_index'] as int? ?? 0;
        _stopReel(reelIndex, result);
      } else if (currentStage.stageType == 'anticipation_on') {
        _startAnticipation(currentStage.payload['reel_index'] as int? ?? widget.reels - 1);
      } else if (currentStage.stageType == 'anticipation_off') {
        _stopAnticipation();
      } else if (currentStage.stageType == 'win_present') {
        _showWin(result);
      } else if (currentStage.stageType == 'bigwin_tier') {
        _winTier = currentStage.payload['tier'] as String? ?? 'BIG WIN';
      }
    }

    // Handle spin result when all stages complete
    if (!isPlaying && result != null && _isSpinning) {
      _finalizeSpin(result);
    }
  }

  void _startSpin() {
    setState(() {
      _isSpinning = true;
      _winningReels = [];
      _activePaylines = [];
      _displayWinAmount = 0;
      _targetWinAmount = 0;
      _winTier = null;
      _previousGrid = List.generate(
        widget.reels,
        (r) => List.from(_displayGrid[r]),
      );
    });

    // Start all reels spinning with stagger
    for (int i = 0; i < _reelControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) {
          _reelControllers[i].repeat();
        }
      });
    }
  }

  void _stopReel(int reelIndex, SlotLabSpinResult? result) {
    if (reelIndex >= 0 && reelIndex < _reelControllers.length) {
      _reelControllers[reelIndex].stop();
      _reelControllers[reelIndex].reset();

      // Update grid for this reel if we have result
      // grid is List<List<int>> where grid[reel][row]
      if (result != null && reelIndex < result.grid.length) {
        setState(() {
          final reelColumn = result.grid[reelIndex];
          for (int row = 0; row < widget.rows && row < reelColumn.length; row++) {
            _displayGrid[reelIndex][row] = reelColumn[row];
          }
        });
      }
    }
  }

  void _startAnticipation(int reelIndex) {
    setState(() {
      _isAnticipation = true;
      _anticipationReelIndex = reelIndex;
    });
    _anticipationController.repeat(reverse: true);
  }

  void _stopAnticipation() {
    setState(() {
      _isAnticipation = false;
      _anticipationReelIndex = -1;
    });
    _anticipationController.stop();
    _anticipationController.reset();
  }

  void _showWin(SlotLabSpinResult? result) {
    if (result == null) return;

    setState(() {
      _targetWinAmount = result.totalWin;
      // Determine winning reels from lineWins
      final winPositions = <int>{};
      for (final lineWin in result.lineWins) {
        // lineWin.positions is List<List<int>> where each is [reel, row]
        for (final pos in lineWin.positions) {
          if (pos.isNotEmpty) {
            winPositions.add(pos[0]); // reel index
          }
        }
      }
      _winningReels = winPositions.toList();
      // Extract payline IDs from lineWins
      _activePaylines = result.lineWins.map((lw) => lw.lineIndex).toList();
    });

    _countupController.forward(from: 0);
  }

  void _finalizeSpin(SlotLabSpinResult result) {
    // Stop all reels
    for (final controller in _reelControllers) {
      controller.stop();
      controller.reset();
    }

    // Update full grid from result
    // grid is List<List<int>> where grid[reel][row]
    setState(() {
      _isSpinning = false;
      for (int reel = 0; reel < widget.reels && reel < result.grid.length; reel++) {
        final reelColumn = result.grid[reel];
        for (int row = 0; row < widget.rows && row < reelColumn.length; row++) {
          _displayGrid[reel][row] = reelColumn[row];
        }
      }
    });

    _stopAnticipation();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.reels * widget.reelWidth + (widget.reels - 1) * 4;
    final totalHeight = widget.rows * widget.symbolHeight + 60; // Extra for win display

    return Container(
      width: totalWidth + 40,
      height: totalHeight + 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A24),
            Color(0xFF0A0A10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isSpinning
              ? FluxForgeTheme.accentBlue.withOpacity(0.5)
              : FluxForgeTheme.borderSubtle,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
          if (_winningReels.isNotEmpty)
            BoxShadow(
              color: FluxForgeTheme.accentGreen.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 10,
            ),
        ],
      ),
      child: Column(
        children: [
          // Slot machine frame header
          _buildFrameHeader(),

          // Reels area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                children: [
                  // Reel columns
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.reels, (reelIndex) {
                      return Padding(
                        padding: EdgeInsets.only(
                          right: reelIndex < widget.reels - 1 ? 4 : 0,
                        ),
                        child: _buildReel(reelIndex),
                      );
                    }),
                  ),

                  // Payline overlay
                  if (widget.showPaylines && _activePaylines.isNotEmpty)
                    ..._activePaylines.map((lineId) => _buildPaylineOverlay(lineId)),

                  // Win tier overlay
                  if (_winTier != null) _buildWinTierOverlay(),
                ],
              ),
            ),
          ),

          // Win amount display
          if (widget.showWinAmount) _buildWinDisplay(),
        ],
      ),
    );
  }

  Widget _buildFrameHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2A2A3A), Color(0xFF1A1A24)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          // Slot machine icon
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.casino, size: 12, color: Colors.black),
          ),
          const SizedBox(width: 8),
          Text(
            'SLOT PREVIEW',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _isSpinning
                  ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                  : _winningReels.isNotEmpty
                      ? FluxForgeTheme.accentGreen.withOpacity(0.2)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isSpinning
                    ? FluxForgeTheme.accentBlue
                    : _winningReels.isNotEmpty
                        ? FluxForgeTheme.accentGreen
                        : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: Text(
              _isSpinning
                  ? 'SPINNING'
                  : _winningReels.isNotEmpty
                      ? 'WIN!'
                      : 'READY',
              style: TextStyle(
                color: _isSpinning
                    ? FluxForgeTheme.accentBlue
                    : _winningReels.isNotEmpty
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.textSecondary,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReel(int reelIndex) {
    final controller = _reelControllers[reelIndex];
    final isAnticipatingThisReel = _isAnticipation && _anticipationReelIndex == reelIndex;
    final isWinningReel = _winningReels.contains(reelIndex);

    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        _winPulseAnimation,
        if (isAnticipatingThisReel) _anticipationAnimation,
      ]),
      builder: (context, child) {
        // Calculate shake offset for anticipation
        final shakeOffset = isAnticipatingThisReel
            ? _anticipationAnimation.value
            : 0.0;

        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: Container(
            width: widget.reelWidth,
            height: widget.rows * widget.symbolHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isWinningReel
                    ? FluxForgeTheme.accentGreen
                        .withOpacity(_winPulseAnimation.value)
                    : isAnticipatingThisReel
                        ? FluxForgeTheme.accentOrange
                        : FluxForgeTheme.borderSubtle,
                width: isWinningReel || isAnticipatingThisReel ? 2 : 1,
              ),
              boxShadow: [
                if (isWinningReel)
                  BoxShadow(
                    color: FluxForgeTheme.accentGreen.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                if (isAnticipatingThisReel)
                  BoxShadow(
                    color: FluxForgeTheme.accentOrange.withOpacity(0.5),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                // Symbols column
                Column(
                  children: List.generate(widget.rows, (rowIndex) {
                    return _buildSymbol(
                      reelIndex,
                      rowIndex,
                      controller.isAnimating,
                      isWinningReel,
                    );
                  }),
                ),

                // Spin blur overlay
                if (controller.isAnimating)
                  Positioned.fill(
                    child: _buildSpinBlurOverlay(reelIndex),
                  ),

                // Anticipation glow
                if (isAnticipatingThisReel)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            FluxForgeTheme.accentOrange.withOpacity(0.2),
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
      },
    );
  }

  Widget _buildSymbol(int reelIndex, int rowIndex, bool isSpinning, bool isWinning) {
    final symbolId = _displayGrid[reelIndex][rowIndex];
    final symbol = SlotSymbol.getSymbol(symbolId);
    final isWinningPosition = isWinning && _checkWinningPosition(reelIndex, rowIndex);

    return AnimatedBuilder(
      animation: _winPulseAnimation,
      builder: (context, child) {
        return Container(
          width: widget.reelWidth,
          height: widget.symbolHeight,
          decoration: BoxDecoration(
            gradient: isSpinning
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      symbol.gradientColors[0].withOpacity(isWinningPosition ? 0.3 : 0.1),
                      symbol.gradientColors[1].withOpacity(isWinningPosition ? 0.2 : 0.05),
                    ],
                  ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Symbol icon with glow
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: symbol.gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: symbol.gradientColors[0].withOpacity(
                        isWinningPosition ? 0.6 * _winPulseAnimation.value : 0.3,
                      ),
                      blurRadius: isWinningPosition ? 12 : 6,
                      spreadRadius: isWinningPosition ? 2 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  symbol.icon,
                  size: 28,
                  color: Colors.white,
                ),
              ),

              // Symbol label
              Positioned(
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    symbol.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Special symbol badges
              if (symbol.isWild || symbol.isScatter || symbol.isBonus)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: symbol.isWild
                          ? Colors.amber
                          : symbol.isScatter
                              ? Colors.purple
                              : Colors.cyan,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      symbol.isWild
                          ? 'W'
                          : symbol.isScatter
                              ? 'S'
                              : 'B',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 6,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Win highlight ring
              if (isWinningPosition)
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: FluxForgeTheme.accentGreen.withOpacity(_winPulseAnimation.value),
                      width: 3,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _checkWinningPosition(int reelIndex, int rowIndex) {
    // Check if this position is part of a winning combination
    final result = widget.provider.lastResult;
    if (result == null) return false;

    // Check lineWins for matching position
    for (final lineWin in result.lineWins) {
      for (final pos in lineWin.positions) {
        if (pos.length >= 2 && pos[0] == reelIndex && pos[1] == rowIndex) {
          return true;
        }
      }
    }
    return false;
  }

  Widget _buildSpinBlurOverlay(int reelIndex) {
    // Generate random symbols for blur effect
    final random = math.Random(reelIndex * DateTime.now().millisecond);

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 20,
      itemBuilder: (context, index) {
        final symbolId = random.nextInt(10);
        final symbol = SlotSymbol.getSymbol(symbolId);
        final offset = (DateTime.now().millisecondsSinceEpoch / 50 + index * 30) % 400 - 200;

        return Transform.translate(
          offset: Offset(0, offset),
          child: Opacity(
            opacity: 0.4,
            child: Container(
              height: widget.symbolHeight * 0.8,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: symbol.gradientColors,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(symbol.icon, size: 24, color: Colors.white54),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaylineOverlay(int lineId) {
    if (lineId >= WinLine.standardLines.length) return const SizedBox();

    final line = WinLine.standardLines[lineId];

    return CustomPaint(
      size: Size(
        widget.reels * widget.reelWidth + (widget.reels - 1) * 4,
        widget.rows * widget.symbolHeight,
      ),
      painter: _PaylinePainter(
        positions: line.positions,
        color: line.color,
        reelWidth: widget.reelWidth,
        symbolHeight: widget.symbolHeight,
        pulseValue: _winPulseAnimation.value,
      ),
    );
  }

  Widget _buildWinTierOverlay() {
    return AnimatedBuilder(
      animation: _winPulseAnimation,
      builder: (context, child) {
        return Center(
          child: Transform.scale(
            scale: 0.8 + 0.3 * _winPulseAnimation.value,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFD700).withOpacity(0.9),
                    const Color(0xFFFFA500).withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Text(
                _winTier ?? 'WIN!',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWinDisplay() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _displayWinAmount > 0
                ? FluxForgeTheme.accentGreen.withOpacity(0.2)
                : const Color(0xFF1A1A24),
            const Color(0xFF0A0A10),
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_displayWinAmount > 0) ...[
            Icon(
              Icons.monetization_on,
              color: FluxForgeTheme.accentGreen,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'WIN: ',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            AnimatedBuilder(
              animation: _countupController,
              builder: (context, child) {
                return Text(
                  _displayWinAmount.toStringAsFixed(2),
                  style: TextStyle(
                    color: FluxForgeTheme.accentGreen,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                );
              },
            ),
          ] else
            Text(
              'READY TO SPIN',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAYLINE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _PaylinePainter extends CustomPainter {
  final List<int> positions;
  final Color color;
  final double reelWidth;
  final double symbolHeight;
  final double pulseValue;

  _PaylinePainter({
    required this.positions,
    required this.color,
    required this.reelWidth,
    required this.symbolHeight,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6 + 0.4 * pulseValue)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final reelSpacing = 4.0;

    for (int i = 0; i < positions.length; i++) {
      final x = i * (reelWidth + reelSpacing) + reelWidth / 2;
      final y = positions[i] * symbolHeight + symbolHeight / 2;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw dots at each position
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < positions.length; i++) {
      final x = i * (reelWidth + reelSpacing) + reelWidth / 2;
      final y = positions[i] * symbolHeight + symbolHeight / 2;
      canvas.drawCircle(Offset(x, y), 4 + 2 * pulseValue, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaylinePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT SLOT MINI PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

/// Small compact slot preview for sidebar/header use
class SlotMiniPreview extends StatelessWidget {
  final SlotLabProvider provider;
  final double size;

  const SlotMiniPreview({
    super.key,
    required this.provider,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, child) {
        final result = provider.lastResult;
        final isSpinning = provider.isPlayingStages;

        return Container(
          width: size,
          height: size * 0.6,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSpinning
                  ? FluxForgeTheme.accentBlue
                  : result != null && result.totalWin > 0
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final symbolSize = ((constraints.maxWidth - 8) / 5).clamp(10.0, 14.0);
                final hasWin = result != null && result.totalWin > 0;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mini symbol row - show middle row of grid
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (reelIndex) {
                        // grid is List<List<int>> where grid[reel][row]
                        // Show middle row (row index 1 for 3-row grid)
                        int symbolId = reelIndex;
                        if (result?.grid != null && reelIndex < result!.grid.length) {
                          final reelColumn = result.grid[reelIndex];
                          if (reelColumn.length > 1) {
                            symbolId = reelColumn[1]; // Middle row
                          } else if (reelColumn.isNotEmpty) {
                            symbolId = reelColumn[0];
                          }
                        }
                        final symbol = SlotSymbol.getSymbol(symbolId);

                        return Container(
                          width: symbolSize,
                          height: symbolSize,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: symbol.gradientColors),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Icon(symbol.icon, size: symbolSize * 0.6, color: Colors.white),
                        );
                      }),
                    ),
                    // Win amount (only if fits)
                    if (hasWin && constraints.maxHeight > 30)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'WIN: ${result.totalWin.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: FluxForgeTheme.accentGreen,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
