// ═══════════════════════════════════════════════════════════════════════════════
// GAMBLE SIMULATOR — Risk/Double-or-Nothing feature
// ═══════════════════════════════════════════════════════════════════════════════
//
// Classic gamble feature for doubling wins:
// - Card Color (Red/Black) - 50% chance
// - Card Suit (Hearts/Diamonds/Clubs/Spades) - 25% chance
// - Coin Flip (Heads/Tails) - 50% chance
// - Ladder Climb - 50% per step
//
// Note: UI-only simulator (no FFI), uses Dart-side logic.

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/fluxforge_theme.dart';

/// Gamble game type
enum GambleGameType {
  cardColor,
  cardSuit,
  coinFlip,
  ladder;

  String get displayName => switch (this) {
        cardColor => 'Card Color',
        cardSuit => 'Card Suit',
        coinFlip => 'Coin Flip',
        ladder => 'Ladder',
      };

  double get winChance => switch (this) {
        cardColor => 0.5,
        cardSuit => 0.25,
        coinFlip => 0.5,
        ladder => 0.5,
      };

  double get winMultiplier => switch (this) {
        cardColor => 2.0,
        cardSuit => 4.0,
        coinFlip => 2.0,
        ladder => 2.0,
      };

  IconData get icon => switch (this) {
        cardColor => Icons.style,
        cardSuit => Icons.favorite,
        coinFlip => Icons.monetization_on,
        ladder => Icons.stairs,
      };
}

/// Gamble choice options
enum GambleChoice {
  red,
  black,
  hearts,
  diamonds,
  clubs,
  spades,
  heads,
  tails,
  higher,
  lower;

  String get label => switch (this) {
        red => 'RED',
        black => 'BLACK',
        hearts => '♥',
        diamonds => '♦',
        clubs => '♣',
        spades => '♠',
        heads => 'HEADS',
        tails => 'TAILS',
        higher => 'HIGHER',
        lower => 'LOWER',
      };

  Color get color => switch (this) {
        red || hearts || diamonds => Colors.red,
        black || clubs || spades => Colors.black87,
        heads => Colors.amber,
        tails => Colors.grey,
        higher => Colors.green,
        lower => Colors.blue,
      };
}

/// Result of a gamble attempt
enum GambleResult { win, lose, draw }

/// Gamble configuration
class GambleConfig {
  final GambleGameType gameType;
  final int maxAttempts;
  final double maxWinCap;
  final double drawChance;

  const GambleConfig({
    this.gameType = GambleGameType.cardColor,
    this.maxAttempts = 5,
    this.maxWinCap = 10000,
    this.drawChance = 0.02,
  });
}

/// Gamble Simulator Widget
class GambleSimulator extends StatefulWidget {
  final GambleConfig config;
  final double initialStake;
  final VoidCallback? onCollect;
  final void Function(double amount, bool won)? onGambleComplete;

  const GambleSimulator({
    super.key,
    this.config = const GambleConfig(),
    required this.initialStake,
    this.onCollect,
    this.onGambleComplete,
  });

  @override
  State<GambleSimulator> createState() => _GambleSimulatorState();
}

class _GambleSimulatorState extends State<GambleSimulator>
    with SingleTickerProviderStateMixin {
  final _random = Random();

  late double _currentAmount;
  int _attemptsUsed = 0;
  GambleResult? _lastResult;
  GambleChoice? _lastChoice;
  GambleChoice? _winningChoice;
  bool _gameOver = false;
  bool _waitingForChoice = true;

  late AnimationController _resultController;
  late Animation<double> _resultAnimation;

  @override
  void initState() {
    super.initState();
    _currentAmount = widget.initialStake;

    _resultController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _resultAnimation = CurvedAnimation(
      parent: _resultController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _resultController.dispose();
    super.dispose();
  }

  List<GambleChoice> get _availableChoices {
    switch (widget.config.gameType) {
      case GambleGameType.cardColor:
        return [GambleChoice.red, GambleChoice.black];
      case GambleGameType.cardSuit:
        return [
          GambleChoice.hearts,
          GambleChoice.diamonds,
          GambleChoice.clubs,
          GambleChoice.spades,
        ];
      case GambleGameType.coinFlip:
        return [GambleChoice.heads, GambleChoice.tails];
      case GambleGameType.ladder:
        return [GambleChoice.higher, GambleChoice.lower];
    }
  }

  void _onChoice(GambleChoice choice) {
    if (!_waitingForChoice || _gameOver) return;

    setState(() {
      _waitingForChoice = false;
      _lastChoice = choice;
    });

    // Determine winning choice
    final choices = _availableChoices;
    _winningChoice = choices[_random.nextInt(choices.length)];

    // Determine result
    final roll = _random.nextDouble();
    GambleResult result;

    if (_lastChoice == _winningChoice) {
      if (roll < widget.config.drawChance) {
        result = GambleResult.draw;
      } else {
        result = GambleResult.win;
      }
    } else {
      result = GambleResult.lose;
    }

    // Animate reveal
    Future.delayed(const Duration(milliseconds: 300), () {
      _resultController.forward(from: 0);

      setState(() {
        _lastResult = result;
        _attemptsUsed++;

        switch (result) {
          case GambleResult.win:
            _currentAmount *= widget.config.gameType.winMultiplier;
            if (_currentAmount > widget.config.maxWinCap) {
              _currentAmount = widget.config.maxWinCap;
            }
            break;
          case GambleResult.lose:
            _currentAmount = 0;
            _gameOver = true;
            break;
          case GambleResult.draw:
            // Keep current amount
            break;
        }

        if (_attemptsUsed >= widget.config.maxAttempts) {
          _gameOver = true;
        }

        if (!_gameOver) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              setState(() {
                _waitingForChoice = true;
              });
            }
          });
        }
      });

      widget.onGambleComplete?.call(
        _currentAmount,
        result == GambleResult.win,
      );
    });
  }

  void _onCollect() {
    widget.onCollect?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lastResult == GambleResult.win
              ? Colors.green.withOpacity(0.5)
              : _lastResult == GambleResult.lose
                  ? Colors.red.withOpacity(0.5)
                  : FluxForgeTheme.borderSubtle,
          width: _lastResult != null ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildAmountDisplay(),
          const SizedBox(height: 20),
          _buildGameArea(),
          const SizedBox(height: 16),
          _buildChoiceButtons(),
          const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 12),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          widget.config.gameType.icon,
          color: Colors.orange,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          widget.config.gameType.displayName.toUpperCase(),
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.5)),
          ),
          child: Text(
            '${(widget.config.gameType.winChance * 100).toInt()}% / ${widget.config.gameType.winMultiplier.toInt()}x',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountDisplay() {
    return AnimatedBuilder(
      animation: _resultAnimation,
      builder: (context, child) {
        Color bgColor = FluxForgeTheme.bgMid;
        Color textColor = Colors.white;

        if (_lastResult == GambleResult.win) {
          bgColor = Color.lerp(
            Colors.green.withOpacity(0.3),
            Colors.green.withOpacity(0.1),
            _resultAnimation.value,
          )!;
          textColor = Colors.green;
        } else if (_lastResult == GambleResult.lose) {
          bgColor = Color.lerp(
            Colors.red.withOpacity(0.3),
            Colors.red.withOpacity(0.1),
            _resultAnimation.value,
          )!;
          textColor = Colors.red;
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _lastResult == GambleResult.win
                  ? Colors.green.withOpacity(0.5)
                  : _lastResult == GambleResult.lose
                      ? Colors.red.withOpacity(0.5)
                      : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Column(
            children: [
              Text(
                'CURRENT STAKE',
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatValue(_currentAmount),
                style: TextStyle(
                  color: textColor,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              if (_lastResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _lastResult == GambleResult.win
                      ? 'YOU WIN!'
                      : _lastResult == GambleResult.lose
                          ? 'YOU LOSE'
                          : 'DRAW',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildGameArea() {
    if (_winningChoice == null) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: const Center(
          child: Text(
            'Make your choice!',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: _winningChoice!.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _winningChoice!.color,
          width: 2,
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _winningChoice!.label,
              style: TextStyle(
                color: _winningChoice!.color == Colors.black87
                    ? Colors.white
                    : _winningChoice!.color,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_lastChoice != null) ...[
              const SizedBox(width: 16),
              Icon(
                _lastChoice == _winningChoice ? Icons.check_circle : Icons.cancel,
                color: _lastChoice == _winningChoice ? Colors.green : Colors.red,
                size: 32,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceButtons() {
    if (_gameOver) {
      return const SizedBox.shrink();
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: _availableChoices.map((choice) {
        final isSelected = _lastChoice == choice;
        final isWinner = _winningChoice == choice;

        return GestureDetector(
          onTap: _waitingForChoice ? () => _onChoice(choice) : null,
          child: Container(
            width: widget.config.gameType == GambleGameType.cardSuit ? 60 : 100,
            height: 50,
            decoration: BoxDecoration(
              color: isSelected
                  ? choice.color.withOpacity(0.3)
                  : choice.color.withOpacity(_waitingForChoice ? 0.15 : 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected || isWinner
                    ? choice.color
                    : choice.color.withOpacity(0.3),
                width: isSelected || isWinner ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                choice.label,
                style: TextStyle(
                  color: choice.color == Colors.black87
                      ? Colors.white
                      : choice.color,
                  fontSize: widget.config.gameType == GambleGameType.cardSuit
                      ? 24
                      : 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'ATTEMPTS',
            '$_attemptsUsed/${widget.config.maxAttempts}',
            Icons.repeat,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'INITIAL',
            _formatValue(widget.initialStake),
            Icons.attach_money,
            Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'POTENTIAL',
            _formatValue(_currentAmount * widget.config.gameType.winMultiplier),
            Icons.trending_up,
            Colors.green,
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
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_gameOver) {
      return ElevatedButton.icon(
        onPressed: _onCollect,
        icon: Icon(
          _currentAmount > 0 ? Icons.check : Icons.close,
          size: 16,
        ),
        label: Text(_currentAmount > 0
            ? 'COLLECT ${_formatValue(_currentAmount)}'
            : 'GAME OVER'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _currentAmount > 0 ? Colors.green : Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _onCollect,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('COLLECT'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: BorderSide(color: Colors.green.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
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
