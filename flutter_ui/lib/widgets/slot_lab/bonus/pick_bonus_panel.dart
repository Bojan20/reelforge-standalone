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
// Note: UI-only simulator (no FFI), uses Dart-side logic.

import 'dart:math';
import 'package:flutter/material.dart';
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
  final PickPrizeType prizeType;
  final double value;
  bool revealed;

  PickBonusItem({
    required this.index,
    required this.prizeType,
    required this.value,
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

/// Pick Bonus Panel Widget
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
  final _random = Random();
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
    _items = [];
    _totalWin = 0;
    _multiplier = 1.0;
    _endGamesHit = 0;
    _gameOver = false;
    _lastRevealedIndex = null;
    _picksRemaining = config.totalItems;

    // Add end game items
    for (int i = 0; i < config.endGameCount; i++) {
      _items.add(PickBonusItem(
        index: i,
        prizeType: PickPrizeType.endGame,
        value: 0,
      ));
    }

    // Add one collect
    _items.add(PickBonusItem(
      index: _items.length,
      prizeType: PickPrizeType.collect,
      value: 0,
    ));

    // Fill remaining with prizes
    final remaining = config.totalItems - config.endGameCount - 1;
    for (int i = 0; i < remaining; i++) {
      final roll = _random.nextDouble();
      PickPrizeType type;
      double value;

      if (roll < 0.02) {
        // 2% jackpot
        type = PickPrizeType.jackpot;
        value = 1000 * (_random.nextInt(4) + 1).toDouble();
      } else if (roll < 0.10) {
        // 8% extra picks
        type = PickPrizeType.extraPicks;
        value = 1;
      } else if (roll < 0.25) {
        // 15% multiplier
        type = PickPrizeType.multiplier;
        value = config.multiplierValues[
            _random.nextInt(config.multiplierValues.length)];
      } else {
        // ~75% coins
        type = PickPrizeType.coins;
        value = config.coinValues[_random.nextInt(config.coinValues.length)] *
            config.baseBet;
      }

      _items.add(PickBonusItem(
        index: _items.length,
        prizeType: type,
        value: value,
      ));
    }

    // Shuffle
    _items.shuffle(_random);
    for (int i = 0; i < _items.length; i++) {
      _items[i] = PickBonusItem(
        index: i,
        prizeType: _items[i].prizeType,
        value: _items[i].value,
        revealed: false,
      );
    }

    setState(() {});
  }

  void _onItemTap(int index) {
    if (_gameOver) return;

    final item = _items.firstWhere((i) => i.index == index);
    if (item.revealed) return;

    setState(() {
      item.revealed = true;
      _lastRevealedIndex = index;
      _picksRemaining--;

      switch (item.prizeType) {
        case PickPrizeType.coins:
          _totalWin += item.value * _multiplier;
          break;
        case PickPrizeType.multiplier:
          _multiplier *= item.value;
          break;
        case PickPrizeType.extraPicks:
          _picksRemaining += item.value.toInt();
          break;
        case PickPrizeType.jackpot:
          _totalWin += item.value * _multiplier;
          break;
        case PickPrizeType.endGame:
          _endGamesHit++;
          break;
        case PickPrizeType.collect:
          _gameOver = true;
          break;
      }

      // Check if game ends
      if (_endGamesHit >= widget.config.endGameCount) {
        _gameOver = true;
      }
    });

    _revealController.forward(from: 0);
    widget.onWinUpdated?.call(_totalWin);

    if (_gameOver) {
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
    final columns = 4;
    final rows = (widget.config.totalItems / columns).ceil();
    final cellSize = 70.0;

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
                  return SizedBox(width: cellSize, height: cellSize);
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
            style: TextStyle(
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
