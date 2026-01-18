/// Slot Preview Widget
///
/// Full-screen slot reels - NO header/footer, maximum visibility
/// - Reels fill entire available space
/// - Smooth vertical spinning animation
/// - Premium 3D symbols
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../providers/slot_lab_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

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
  late List<AnimationController> _spinControllers;
  late AnimationController _winPulseController;
  late Animation<double> _winPulseAnimation;

  List<List<int>> _displayGrid = [];
  List<List<int>> _targetGrid = [];
  bool _isSpinning = false;
  Set<int> _winningReels = {};

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
    _spinControllers = List.generate(widget.reels, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 1000 + (index * 250)),
      );
    });

    _winPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _winPulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _winPulseController, curve: Curves.easeInOut),
    );

    _spinSymbols = List.generate(
      widget.reels,
      (_) => List.generate(20, (_) => _random.nextInt(10)),
    );
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
    for (final c in _spinControllers) {
      c.dispose();
    }
    _winPulseController.dispose();
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    _disposeControllers();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    final result = widget.provider.lastResult;
    final isPlaying = widget.provider.isPlayingStages;
    final stages = widget.provider.lastStages;

    if (isPlaying && stages.isNotEmpty && !_isSpinning) {
      final hasSpinStart = stages.any((s) => s.stageType == 'spin_start');
      if (hasSpinStart) {
        _startSpin(result);
      }
    }

    if (!isPlaying && result != null && _isSpinning) {
      _finalizeSpin(result);
    }
  }

  void _startSpin(SlotLabSpinResult? result) {
    if (_isSpinning) return;

    setState(() {
      _isSpinning = true;
      _winningReels = {};
    });

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

    _spinSymbols = List.generate(
      widget.reels,
      (_) => List.generate(20, (_) => _random.nextInt(10)),
    );

    for (int i = 0; i < _spinControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (mounted && _isSpinning) {
          _spinControllers[i].forward(from: 0.0);
        }
      });
    }
  }

  void _finalizeSpin(SlotLabSpinResult result) {
    setState(() {
      for (int r = 0; r < widget.reels && r < result.grid.length; r++) {
        for (int row = 0; row < widget.rows && row < result.grid[r].length; row++) {
          _displayGrid[r][row] = result.grid[r][row];
        }
      }

      _isSpinning = false;

      if (result.isWin) {
        for (final lineWin in result.lineWins) {
          for (final pos in lineWin.positions) {
            if (pos.isNotEmpty) _winningReels.add(pos[0]);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use ClipRect to prevent any overflow
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D0D14), Color(0xFF080810), Color(0xFF050508)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _winningReels.isNotEmpty
                    ? FluxForgeTheme.accentGreen.withOpacity(0.6)
                    : _isSpinning
                        ? FluxForgeTheme.accentBlue.withOpacity(0.4)
                        : const Color(0xFF2A2A38),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _buildReelTable(constraints.maxWidth - 12, constraints.maxHeight - 12),
            ),
          ),
        );
      },
    );
  }

  /// Build reel grid using Table for precise layout without overflow
  Widget _buildReelTable(double availableWidth, double availableHeight) {
    // Calculate cell size based on available space
    final cellWidth = availableWidth / widget.reels;
    final cellHeight = availableHeight / widget.rows;
    final cellSize = math.min(cellWidth, cellHeight) * 0.95; // 95% to leave small gap

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

  Widget _buildSymbolCell(int reelIndex, int rowIndex, double cellSize) {
    final controller = _spinControllers[reelIndex];
    final isWinning = _winningReels.contains(reelIndex);
    final isSpinning = controller.isAnimating;

    return AnimatedBuilder(
      animation: Listenable.merge([controller, _winPulseAnimation]),
      builder: (context, child) {
        return Container(
          width: cellSize,
          height: cellSize,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: const Color(0xFF08080C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isWinning
                  ? FluxForgeTheme.accentGreen.withOpacity(_winPulseAnimation.value)
                  : const Color(0xFF2A2A38),
              width: isWinning ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: isSpinning
              ? _buildSpinningSymbolContent(reelIndex, rowIndex, cellSize, controller.value)
              : _buildStaticSymbolContent(reelIndex, rowIndex, cellSize, isWinning),
        );
      },
    );
  }

  Widget _buildSpinningSymbolContent(int reelIndex, int rowIndex, double cellSize, double animationValue) {
    final spinSyms = _spinSymbols[reelIndex];
    final totalSymbols = spinSyms.length;
    final scrollProgress = Curves.easeOutCubic.transform(animationValue);
    final currentIndex = ((1 - scrollProgress) * (totalSymbols - widget.rows)).floor();
    final symbolId = currentIndex + rowIndex < totalSymbols
        ? spinSyms[currentIndex + rowIndex]
        : _targetGrid[reelIndex][rowIndex];

    return Stack(
      children: [
        _buildSymbolContent(symbolId, cellSize, false),
        // Motion blur overlay
        if (animationValue < 0.8)
          Container(
            color: Colors.black.withOpacity(0.3 * (1 - animationValue)),
          ),
      ],
    );
  }

  Widget _buildStaticSymbolContent(int reelIndex, int rowIndex, double cellSize, bool isWinning) {
    final symbolId = _displayGrid[reelIndex][rowIndex];
    return _buildSymbolContent(symbolId, cellSize, isWinning);
  }

  Widget _buildSymbolContent(int symbolId, double cellSize, bool isWinning) {
    final symbol = SlotSymbol.getSymbol(symbolId);
    final fontSize = (cellSize * 0.5).clamp(12.0, 60.0);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: symbol.gradientColors,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Text(
          symbol.displayChar,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2, offset: const Offset(1, 1)),
            ],
          ),
        ),
      ),
    );
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
