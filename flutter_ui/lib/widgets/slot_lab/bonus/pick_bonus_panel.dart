// ═══════════════════════════════════════════════════════════════════════════════
// PICK BONUS PANEL — Interactive pick bonus simulator
// ═══════════════════════════════════════════════════════════════════════════════
//
// Visual "pick an item to reveal a prize" bonus game:
// - Grid of hidden items (boxes, eggs, cards, treasure)
// - Tap to reveal prizes (coins, multipliers, jackpots, end game)
// - Running total and multiplier display
// - Animation for reveal
//
// All RNG via Rust FFI — zero dart:math.Random usage.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../src/rust/native_ffi.dart';
import '../../../theme/fluxforge_theme.dart';

/// Prize type in pick bonus
enum PickPrizeType {
  coins,
  multiplier,
  extraPicks,
  jackpot,
  endGame,
  collect;

  bool get isTerminal => this == endGame || this == collect;

  Color get color => switch (this) {
        coins => Colors.amber,
        multiplier => Colors.purple,
        extraPicks => Colors.blue,
        jackpot => Colors.red,
        endGame => Colors.grey,
        collect => Colors.green,
      };

  IconData get icon => switch (this) {
        coins => Icons.monetization_on,
        multiplier => Icons.close,
        extraPicks => Icons.add_circle,
        jackpot => Icons.diamond,
        endGame => Icons.close,
        collect => Icons.check_circle,
      };
}

/// A single pickable item in the grid
class PickBonusItem {
  final int index;
  PickPrizeType prizeType;
  double value;
  bool revealed;

  PickBonusItem({
    required this.index,
    this.prizeType = PickPrizeType.coins,
    this.value = 0,
    this.revealed = false,
  });
}

/// Pick bonus configuration
class PickBonusConfig {
  final int totalItems;
  final int endGameCount;
  final double baseBet;
  final List<double> coinValues;
  final List<double> multiplierValues;

  const PickBonusConfig({
    this.totalItems = 12,
    this.endGameCount = 3,
    this.baseBet = 1.0,
    this.coinValues = const [10, 25, 50, 100, 250, 500],
    this.multiplierValues = const [2, 3, 5, 10],
  });
}

/// Pick Bonus Panel Widget — uses Rust FFI for all RNG
class PickBonusPanel extends StatefulWidget {
  final PickBonusConfig config;
  final VoidCallback? onComplete;
  final void Function(double totalWin)? onWinUpdated;

  const PickBonusPanel({
    super.key,
    this.config = const PickBonusConfig(),
    this.onComplete,
    this.onWinUpdated,
  });

  @override
  State<PickBonusPanel> createState() => _PickBonusPanelState();
}

class _PickBonusPanelState extends State<PickBonusPanel>
    with TickerProviderStateMixin {
  NativeFFI? _ffi;
  List<PickBonusItem> _items = [];
  double _totalWin = 0;
  double _multiplier = 1.0;
  int _picksRemaining = 0;
  int _endGamesHit = 0;
  bool _gameOver = false;
  int? _lastRevealedIndex;

  late AnimationController _revealController;
  late Animation<double> _revealAnimation;

  @override
  void initState() {
    super.initState();

    try {
      _ffi = GetIt.instance<NativeFFI>();
    } catch (_) {}

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutBack,
    );
    _initializeGame();
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  void _initializeGame() {
    final config = widget.config;

    // Trigger pick bonus in Rust engine
    _ffi?.pickBonusForceTrigger();

    // Build unrevealed grid — Rust decides prizes on each pick
    _items = List.generate(
      config.totalItems,
      (i) => PickBonusItem(index: i),
    );

    _totalWin = 0;
    _multiplier = 1.0;
    _endGamesHit = 0;
    _gameOver = false;
    _lastRevealedIndex = null;
    _picksRemaining = config.totalItems;

    setState(() {});
  }

  PickPrizeType _parsePrizeType(String? type) {
    switch (type) {
      case 'coins': return PickPrizeType.coins;
      case 'multiplier': return PickPrizeType.multiplier;
      case 'extra_picks': return PickPrizeType.extraPicks;
      case 'jackpot': return PickPrizeType.jackpot;
      case 'end_game': return PickPrizeType.endGame;
      case 'collect': return PickPrizeType.collect;
      default: return PickPrizeType.coins;
    }
  }

  void _onItemTap(int index) {
    if (_gameOver) return;

    final item = _items.firstWhere((i) => i.index == index);
    if (item.revealed) return;

    // Ask Rust for the prize via FFI
    final result = _ffi?.pickBonusMakePick();

    // Parse: {"prize_type": "coins", "prize_value": 100.0, "game_over": false}
    final prizeType = _parsePrizeType(result?['prize_type'] as String?);
    final prizeValue = (result?['prize_value'] as num?)?.toDouble() ?? 0.0;
    final ffiGameOver = result?['game_over'] as bool? ?? false;

    setState(() {
      item.revealed = true;
      item.prizeType = prizeType;
      item.value = prizeValue;
      _lastRevealedIndex = index;
      _picksRemaining--;

      switch (prizeType) {
        case PickPrizeType.coins:
          _totalWin += prizeValue * _multiplier;
          break;
        case PickPrizeType.multiplier:
          _multiplier *= prizeValue;
          break;
        case PickPrizeType.extraPicks:
          _picksRemaining += prizeValue.toInt();
          break;
        case PickPrizeType.jackpot:
          _totalWin += prizeValue * _multiplier;
          break;
        case PickPrizeType.endGame:
          _endGamesHit++;
          break;
        case PickPrizeType.collect:
          _gameOver = true;
          break;
      }

      if (ffiGameOver || _endGamesHit >= widget.config.endGameCount) {
        _gameOver = true;
      }

      // Sync totals from Rust (authoritative)
      if (_ffi != null) {
        _totalWin = _ffi!.pickBonusTotalWin();
        _multiplier = _ffi!.pickBonusMultiplier();
      }
    });

    _revealController.forward(from: 0);
    widget.onWinUpdated?.call(_totalWin);

    if (_gameOver) {
      // Complete in Rust and get final payout
      _ffi?.pickBonusComplete();
      Future.delayed(const Duration(milliseconds: 800), () {
        widget.onComplete?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _gameOver
              ? Colors.green.withOpacity(0.5)
              : FluxForgeTheme.borderSubtle,
          width: _gameOver ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildGrid(),
          const SizedBox(height: 16),
          _buildStats(),
          if (_gameOver) ...[
            const SizedBox(height: 16),
            _buildGameOverSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          Icons.grid_view,
          color: _gameOver ? Colors.green : Colors.purple,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'PICK BONUS',
          style: TextStyle(
            color: _gameOver ? Colors.green : Colors.purple,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (!_gameOver)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app, size: 14, color: Colors.purple),
                const SizedBox(width: 4),
                Text(
                  '$_picksRemaining',
                  style: const TextStyle(
                    color: Colors.purple,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const Text(
                  ' PICKS',
                  style: TextStyle(
                    color: Colors.purple,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 14, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'COMPLETE',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildGrid() {
    const columns = 4;
    final rows = (widget.config.totalItems / columns).ceil();
    const cellSize = 70.0;

    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(rows, (row) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(columns, (col) {
                final index = row * columns + col;
                if (index >= _items.length) {
                  return const SizedBox(width: cellSize, height: cellSize);
                }
                return _buildCell(_items[index], cellSize);
              }),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCell(PickBonusItem item, double size) {
    final isRevealed = item.revealed;
    final isLastRevealed = item.index == _lastRevealedIndex;

    return GestureDetector(
      onTap: () => _onItemTap(item.index),
      child: AnimatedBuilder(
        animation: _revealAnimation,
        builder: (context, child) {
          final scale = isLastRevealed && isRevealed
              ? 0.8 + _revealAnimation.value * 0.2
              : 1.0;

          return Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isRevealed
                    ? item.prizeType.color.withOpacity(0.2)
                    : Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isRevealed
                      ? item.prizeType.color
                      : Colors.purple.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: isRevealed
                    ? [
                        BoxShadow(
                          color: item.prizeType.color.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: isRevealed
                  ? _buildRevealedContent(item)
                  : _buildHiddenContent(item.index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHiddenContent(int index) {
    return Center(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.3),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.help_outline,
          color: Colors.purple,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildRevealedContent(PickBonusItem item) {
    String label = '';
    switch (item.prizeType) {
      case PickPrizeType.coins:
        label = _formatValue(item.value);
        break;
      case PickPrizeType.multiplier:
        label = '${item.value.toInt()}x';
        break;
      case PickPrizeType.extraPicks:
        label = '+${item.value.toInt()}';
        break;
      case PickPrizeType.jackpot:
        label = 'JP';
        break;
      case PickPrizeType.endGame:
        label = 'X';
        break;
      case PickPrizeType.collect:
        label = '✓';
        break;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          item.prizeType.icon,
          color: item.prizeType.color,
          size: 24,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: item.prizeType.color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'TOTAL WIN',
            _formatValue(_totalWin),
            Icons.attach_money,
            Colors.amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'MULTIPLIER',
            '${_multiplier.toStringAsFixed(_multiplier == _multiplier.floor() ? 0 : 1)}x',
            Icons.close,
            Colors.purple,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'END GAMES',
            '$_endGamesHit/${widget.config.endGameCount}',
            Icons.warning,
            Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              const Text(
                'BONUS COMPLETE!',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Total Win: ${_formatValue(_totalWin)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _initializeGame,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('PLAY AGAIN'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          ),
        ),
      ],
    );
  }

  String _formatValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else if (value >= 100) {
      return value.toStringAsFixed(0);
    } else {
      return value.toStringAsFixed(2);
    }
  }
}
