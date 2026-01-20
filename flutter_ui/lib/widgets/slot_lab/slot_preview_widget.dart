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

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  // Win amount overlay animations
  late AnimationController _winAmountController;
  late Animation<double> _winAmountScale;
  late Animation<double> _winAmountOpacity;
  late AnimationController _winCounterController;

  // Symbol bounce animation for wins
  late AnimationController _symbolBounceController;
  late Animation<double> _symbolBounceAnimation;

  // Particle system
  final List<_WinParticle> _particles = [];
  late AnimationController _particleController;

  // Anticipation/Near Miss animations
  late AnimationController _anticipationController;
  late Animation<double> _anticipationPulse;
  late AnimationController _nearMissController;
  late Animation<double> _nearMissShake;

  List<List<int>> _displayGrid = [];
  List<List<int>> _targetGrid = [];
  bool _isSpinning = false;
  Set<int> _winningReels = {};
  Set<String> _winningPositions = {}; // "reel,row" format

  // Anticipation/Near Miss state
  bool _isAnticipation = false;
  bool _isNearMiss = false;
  Set<int> _anticipationReels = {}; // Reels showing anticipation
  Set<String> _nearMissPositions = {}; // Positions that "just missed"

  // Win display state
  double _displayedWinAmount = 0;
  double _targetWinAmount = 0;
  String _winTier = ''; // SMALL, BIG, MEGA, EPIC, ULTRA

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

    // Symbol bounce for winning symbols
    _symbolBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _symbolBounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _symbolBounceController, curve: Curves.elasticOut),
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
    for (final c in _spinControllers) {
      c.dispose();
    }
    _winPulseController.dispose();
    _winAmountController.dispose();
    _winCounterController.dispose();
    _symbolBounceController.dispose();
    _particleController.dispose();
    _anticipationController.dispose();
    _nearMissController.dispose();
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
      _winningPositions = {};
      _winTier = '';
      _displayedWinAmount = 0;
      _targetWinAmount = 0;
      _particles.clear();
      // Reset anticipation/near miss state
      _isAnticipation = false;
      _isNearMiss = false;
      _anticipationReels = {};
      _nearMissPositions = {};
    });

    // Hide win overlay
    _winAmountController.reverse();
    _winCounterController.reset();

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

        // Trigger win animations
        _winAmountController.forward(from: 0);
        _winCounterController.forward(from: 0);
        _symbolBounceController.forward(from: 0);

        // Spawn particles for bigger wins
        if (_winTier != 'SMALL') {
          _spawnWinParticles(_winTier);
        }
      }
    });
  }

  String _getWinTier(double totalWin) {
    if (totalWin >= 500) return 'ULTRA';
    if (totalWin >= 200) return 'EPIC';
    if (totalWin >= 100) return 'MEGA';
    if (totalWin >= 50) return 'BIG';
    return 'SMALL';
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

  void _spawnWinParticles(String tier) {
    final particleCount = switch (tier) {
      'ULTRA' => 60,
      'EPIC' => 45,
      'MEGA' => 30,
      'BIG' => 20,
      _ => 10,
    };

    for (int i = 0; i < particleCount; i++) {
      _particles.add(_WinParticle(
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
    return LayoutBuilder(
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

              // Particle layer
              if (_particles.isNotEmpty)
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
    );
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

  Widget _buildWinDisplay() {
    final tierColors = switch (_winTier) {
      'ULTRA' => [const Color(0xFFFF4080), const Color(0xFFFF66FF), const Color(0xFFFFD700)],
      'EPIC' => [const Color(0xFFE040FB), const Color(0xFFFF66FF), const Color(0xFF40C8FF)],
      'MEGA' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFF9040)],
      'BIG' => [const Color(0xFF40FF90), const Color(0xFF88FF88), const Color(0xFFFFEB3B)],
      _ => [const Color(0xFF40FF90), const Color(0xFF4CAF50)],
    };

    final fontSize = switch (_winTier) {
      'ULTRA' => 48.0,
      'EPIC' => 44.0,
      'MEGA' => 40.0,
      'BIG' => 36.0,
      _ => 28.0,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.black.withOpacity(0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tierColors.first.withOpacity(0.8),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: tierColors.first.withOpacity(0.4),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Win tier label
          if (_winTier != 'SMALL')
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: tierColors,
              ).createShader(bounds),
              child: Text(
                '$_winTier WIN!',
                style: TextStyle(
                  fontSize: fontSize * 0.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 3,
                ),
              ),
            ),
          if (_winTier != 'SMALL') const SizedBox(height: 8),
          // Win amount counter with currency formatting
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: tierColors,
            ).createShader(bounds),
            child: Text(
              _formatWinAmount(_displayedWinAmount),
              style: TextStyle(
                fontSize: fontSize,
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
    final posKey = '$reelIndex,$rowIndex';
    final isWinningPosition = _winningPositions.contains(posKey);
    final isWinningReel = _winningReels.contains(reelIndex);
    final isSpinning = controller.isAnimating;
    final isAnticipationReel = _anticipationReels.contains(reelIndex);
    final isNearMissPosition = _nearMissPositions.contains(posKey);

    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        _winPulseAnimation,
        _symbolBounceAnimation,
        _anticipationPulse,
        _nearMissShake,
      ]),
      builder: (context, child) {
        // Calculate bounce offset for winning symbols
        double bounceOffset = 0;
        double glowIntensity = 0;
        double shakeOffset = 0;

        if (isWinningPosition && !isSpinning) {
          // Bounce effect - symbols jump up and settle
          final bounceValue = _symbolBounceAnimation.value;
          bounceOffset = math.sin(bounceValue * math.pi) * -8;
          glowIntensity = _winPulseAnimation.value;
        }

        // Near miss shake effect
        if (isNearMissPosition && _isNearMiss) {
          shakeOffset = math.sin(_nearMissShake.value * math.pi * 6) * 4 *
              (1 - _nearMissShake.value); // Dampening shake
        }

        // Determine border color based on state
        Color borderColor;
        double borderWidth;

        if (isWinningPosition) {
          borderColor = _getWinGlowColor().withOpacity(_winPulseAnimation.value);
          borderWidth = 2.5;
        } else if (isNearMissPosition && _isNearMiss) {
          // Near miss - red pulsing border
          borderColor = const Color(0xFFFF4060).withOpacity(0.8);
          borderWidth = 2.5;
        } else if (isAnticipationReel && _isAnticipation && isSpinning) {
          // Anticipation - golden pulsing border
          borderColor = const Color(0xFFFFD700).withOpacity(_anticipationPulse.value);
          borderWidth = 2.0;
        } else if (isWinningReel) {
          borderColor = FluxForgeTheme.accentGreen.withOpacity(_winPulseAnimation.value * 0.5);
          borderWidth = 1.5;
        } else {
          borderColor = const Color(0xFF2A2A38);
          borderWidth = 1;
        }

        // Build box shadows
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
        } else if (isAnticipationReel && _isAnticipation && isSpinning) {
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
          child: Container(
            width: cellSize,
            height: cellSize,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: const Color(0xFF08080C),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: borderColor,
                width: borderWidth,
              ),
              boxShadow: shadows,
            ),
            clipBehavior: Clip.antiAlias,
            child: isSpinning
                ? _buildSpinningSymbolContent(
                    reelIndex, rowIndex, cellSize, controller.value,
                    isAnticipation: isAnticipationReel && _isAnticipation,
                  )
                : _buildStaticSymbolContent(
                    reelIndex, rowIndex, cellSize, isWinningPosition,
                    isNearMiss: isNearMissPosition && _isNearMiss,
                  ),
          ),
        );
      },
    );
  }

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
  double x, y;
  double vx, vy;
  double size;
  Color color;
  _ParticleType type;
  double rotation;
  double rotationSpeed;
  double life = 1.0;
  double gravity = 0.0005;

  _WinParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.type,
    required this.rotation,
    required this.rotationSpeed,
  });

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
