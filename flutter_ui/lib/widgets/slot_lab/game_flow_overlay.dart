/// Game Flow Overlay — Feature-aware UI overlay for SlotLab
///
/// Renders reactive overlays based on active GameFlowState:
/// - Free Spins counter + multiplier
/// - Cascade depth + progressive multiplier trail
/// - Hold & Win coin grid + respin counter
/// - Bonus Game pick/wheel/trail panel
/// - Gamble double-up panel
/// - Jackpot presentation sequence
/// - Collector meter bars
///
/// Sits on top of SlotPreviewWidget inside PremiumSlotPreview.
/// Consumes GameFlowProvider via ChangeNotifierProvider.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/game_flow_models.dart';
import '../../providers/slot_lab/game_flow_provider.dart';
import '../../services/event_registry.dart';
import '../../theme/fluxforge_theme.dart';
import 'bonus_game_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MAIN OVERLAY — Dispatches to feature-specific widgets
// ═══════════════════════════════════════════════════════════════════════════

class GameFlowOverlay extends StatelessWidget {
  const GameFlowOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameFlowProvider>(
      builder: (context, flow, _) {
        return Stack(
          children: [
            // Feature indicators bar (top)
            if (flow.isInFeature)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _FeatureStatusBar(flow: flow),
              ),

            // Feature-specific overlays
            ..._buildFeatureOverlays(flow),

            // Feature queue indicator
            if (flow.hasQueuedFeatures)
              Positioned(
                bottom: 8,
                right: 8,
                child: _QueueIndicator(
                  count: flow.featureQueue.length,
                ),
              ),

            // Scene transition overlay (full-screen, above everything)
            if (flow.isInTransition)
              Positioned.fill(
                child: _SceneTransitionOverlay(
                  transition: flow.activeTransition!,
                  onDismiss: () => flow.dismissTransition(),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildFeatureOverlays(GameFlowProvider flow) {
    final widgets = <Widget>[];

    switch (flow.currentState) {
      case GameFlowState.freeSpins:
        final fs = flow.freeSpinsState;
        if (fs != null) {
          widgets.add(Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: _FreeSpinsOverlay(state: fs),
          ));
        }

      case GameFlowState.cascading:
        final cs = flow.cascadeState;
        if (cs != null) {
          widgets.add(Positioned(
            top: 40,
            right: 8,
            child: _CascadeOverlay(state: cs),
          ));
        }

      case GameFlowState.holdAndWin:
        final hw = flow.holdAndWinState;
        if (hw != null) {
          widgets.add(Positioned.fill(
            child: _HoldAndWinOverlay(state: hw),
          ));
        }

      case GameFlowState.bonusGame:
        final bg = flow.bonusGameState;
        if (bg != null) {
          widgets.add(Positioned.fill(
            child: _BonusGameOverlay(state: bg),
          ));
        }

      case GameFlowState.gamble:
        final gs = flow.gambleState;
        if (gs != null) {
          widgets.add(Positioned.fill(
            child: _GambleOverlay(state: gs, flow: flow),
          ));
        }

      case GameFlowState.respin:
        final rs = flow.respinState;
        if (rs != null) {
          widgets.add(Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: _RespinOverlay(state: rs),
          ));
        }

      case GameFlowState.jackpotPresentation:
        final jp = flow.getFeatureState('jackpot');
        if (jp != null) {
          widgets.add(Positioned.fill(
            child: _JackpotOverlay(state: jp),
          ));
        }

      case GameFlowState.winPresentation:
        widgets.add(Positioned.fill(
          child: _WinPresentationOverlay(flow: flow),
        ));

      default:
        break;
    }

    // Modifier feature indicators (visible during base game / free spins)
    final wildState = flow.wildFeaturesState;
    final multState = flow.multiplierState;
    if (wildState != null || multState != null) {
      widgets.add(Positioned(
        top: flow.isInFeature ? 72 : 8,
        right: 8,
        child: _ModifierIndicators(
          wildState: wildState,
          multiplierState: multState,
        ),
      ));
    }

    // Collector meters (always visible if collector is active)
    final collector = flow.getFeatureState('collector');
    if (collector != null) {
      widgets.add(Positioned(
        bottom: 40,
        left: 8,
        right: 8,
        child: _CollectorMeters(state: collector),
      ));
    }

    return widgets;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE STATUS BAR — Top bar showing current state
// ═══════════════════════════════════════════════════════════════════════════

class _FeatureStatusBar extends StatelessWidget {
  final GameFlowProvider flow;

  const _FeatureStatusBar({required this.flow});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _colorForState(flow.currentState).withValues(alpha: 0.9),
            _colorForState(flow.currentState).withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Row(
        children: [
          Icon(
            _iconForState(flow.currentState),
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            flow.currentState.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (flow.featureDepth > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Depth: ${flow.featureDepth}',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Color _colorForState(GameFlowState state) {
    return switch (state) {
      GameFlowState.freeSpins => const Color(0xFF4CAF50),
      GameFlowState.cascading => const Color(0xFF2196F3),
      GameFlowState.holdAndWin => const Color(0xFFFF9800),
      GameFlowState.bonusGame => const Color(0xFF9C27B0),
      GameFlowState.gamble => const Color(0xFFF44336),
      GameFlowState.respin => const Color(0xFF00BCD4),
      GameFlowState.jackpotPresentation => const Color(0xFFFFD700),
      GameFlowState.winPresentation => const Color(0xFF4CAF50),
      _ => FluxForgeTheme.accentCyan,
    };
  }

  IconData _iconForState(GameFlowState state) {
    return switch (state) {
      GameFlowState.freeSpins => Icons.star,
      GameFlowState.cascading => Icons.waterfall_chart,
      GameFlowState.holdAndWin => Icons.lock,
      GameFlowState.bonusGame => Icons.casino,
      GameFlowState.gamble => Icons.swap_vert,
      GameFlowState.respin => Icons.replay,
      GameFlowState.jackpotPresentation => Icons.emoji_events,
      GameFlowState.winPresentation => Icons.monetization_on,
      _ => Icons.play_arrow,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FREE SPINS OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _FreeSpinsOverlay extends StatefulWidget {
  final FeatureState state;

  const _FreeSpinsOverlay({required this.state});

  @override
  State<_FreeSpinsOverlay> createState() => _FreeSpinsOverlayState();
}

class _FreeSpinsOverlayState extends State<_FreeSpinsOverlay>
    with TickerProviderStateMixin {
  late AnimationController _multBumpController;
  late Animation<double> _multBumpScale;
  late AnimationController _multGlowController;
  late Animation<double> _multGlow;
  late AnimationController _spinsAddedController;
  late Animation<double> _spinsAddedScale;
  double _prevMultiplier = 1.0;
  int _prevTotalSpins = 0;

  @override
  void initState() {
    super.initState();
    _prevMultiplier = widget.state.currentMultiplier;
    _prevTotalSpins = widget.state.totalSpins;

    // Multiplier bump: elastic overshoot 1.0 → 1.35 → 1.0 (400ms)
    _multBumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _multBumpScale = Tween<double>(begin: 1.0, end: 1.0).animate(_multBumpController);

    // Multiplier glow pulse (continuous while multiplier > 1)
    _multGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _multGlow = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _multGlowController, curve: Curves.easeInOut),
    );
    if (widget.state.currentMultiplier > 1.0) {
      _multGlowController.repeat(reverse: true);
    }

    // Spins added bump (retrigger)
    _spinsAddedController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _spinsAddedScale = Tween<double>(begin: 1.0, end: 1.0).animate(_spinsAddedController);
  }

  @override
  void didUpdateWidget(_FreeSpinsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Multiplier increased → bump animation + start glow
    if (widget.state.currentMultiplier > _prevMultiplier) {
      _multBumpScale = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.95), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 40),
      ]).animate(CurvedAnimation(parent: _multBumpController, curve: Curves.easeOut));
      _multBumpController.forward(from: 0);

      if (!_multGlowController.isAnimating) {
        _multGlowController.repeat(reverse: true);
      }
    }
    // Multiplier dropped to 1.0 or below → stop glow
    if (widget.state.currentMultiplier <= 1.0 && _multGlowController.isAnimating) {
      _multGlowController.stop();
      _multGlowController.reset();
    }
    _prevMultiplier = widget.state.currentMultiplier;

    // Spins added (retrigger) → bump spin counter
    if (widget.state.totalSpins > _prevTotalSpins && _prevTotalSpins > 0) {
      _spinsAddedScale = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.95), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 40),
      ]).animate(CurvedAnimation(parent: _spinsAddedController, curve: Curves.easeOut));
      _spinsAddedController.forward(from: 0);
    }
    _prevTotalSpins = widget.state.totalSpins;
  }

  @override
  void dispose() {
    _multBumpController.dispose();
    _multGlowController.dispose();
    _spinsAddedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final showMultiplier = state.currentMultiplier > 1.0;
    final retriggersUsed = state.customData['retriggersUsed'] as int? ?? 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Spin counter with retrigger bump
        AnimatedBuilder(
          animation: _spinsAddedController,
          builder: (_, child) => Transform.scale(
            scale: _spinsAddedScale.value,
            child: child,
          ),
          child: _OverlayBadge(
            icon: Icons.star,
            label: 'SPINS',
            value: '${state.spinsRemaining} / ${state.totalSpins}',
            color: const Color(0xFF4CAF50),
          ),
        ),
        const SizedBox(width: 12),

        // Accumulated win
        _OverlayBadge(
          icon: Icons.monetization_on,
          label: 'TOTAL WIN',
          value: state.accumulatedWin > 0
              ? state.accumulatedWin.toStringAsFixed(2)
              : '0.00',
          color: const Color(0xFF2196F3),
        ),

        // Multiplier with bump + glow animation
        if (showMultiplier) ...[
          const SizedBox(width: 12),
          AnimatedBuilder(
            animation: Listenable.merge([_multBumpController, _multGlowController]),
            builder: (_, child) {
              return Transform.scale(
                scale: _multBumpScale.value,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: _multGlow.value),
                        blurRadius: 12 + (_multGlow.value * 8),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
            },
            child: _OverlayBadge(
              icon: Icons.close,
              label: 'MULTIPLIER',
              value: '${state.currentMultiplier.toStringAsFixed(1)}x',
              color: const Color(0xFFFFD700),
            ),
          ),
        ],

        // Retrigger count
        if (retriggersUsed > 0) ...[
          const SizedBox(width: 12),
          _OverlayBadge(
            icon: Icons.refresh,
            label: 'RETRIGGER',
            value: '$retriggersUsed',
            color: const Color(0xFFFF9800),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CASCADE OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _CascadeOverlay extends StatelessWidget {
  final FeatureState state;

  const _CascadeOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _OverlayBadge(
          icon: Icons.waterfall_chart,
          label: 'CASCADE',
          value: '${state.cascadeDepth}',
          color: const Color(0xFF2196F3),
        ),
        if (state.currentMultiplier > 1.0) ...[
          const SizedBox(height: 4),
          _OverlayBadge(
            icon: Icons.close,
            label: 'MULT',
            value: '${state.currentMultiplier.toStringAsFixed(1)}x',
            color: const Color(0xFFFFD700),
          ),
        ],
        const SizedBox(height: 4),
        _OverlayBadge(
          icon: Icons.monetization_on,
          label: 'WIN',
          value: state.accumulatedWin.toStringAsFixed(2),
          color: const Color(0xFF4CAF50),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HOLD & WIN OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _HoldAndWinOverlay extends StatelessWidget {
  final FeatureState state;

  const _HoldAndWinOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar: respins + total win
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _OverlayBadge(
                icon: Icons.replay,
                label: 'RESPINS',
                value: '${state.respinsRemaining}',
                color: const Color(0xFFFF9800),
              ),
              _OverlayBadge(
                icon: Icons.grid_view,
                label: 'FILLED',
                value: '${state.gridPositionsFilled} / ${state.gridPositionsTotal}',
                color: const Color(0xFF2196F3),
              ),
              _OverlayBadge(
                icon: Icons.monetization_on,
                label: 'TOTAL',
                value: state.accumulatedWin.toStringAsFixed(2),
                color: const Color(0xFF4CAF50),
              ),
            ],
          ),
        ),

        // Coin grid visualization
        Expanded(
          child: _CoinGrid(
            coins: state.lockedCoins,
            totalPositions: state.gridPositionsTotal,
            reelCount: _inferReelCount(state),
            rowCount: _inferRowCount(state),
          ),
        ),
      ],
    );
  }

  int _inferReelCount(FeatureState state) {
    if (state.lockedCoins.isEmpty) return 5;
    int maxReel = 0;
    for (final coin in state.lockedCoins) {
      if (coin.reel > maxReel) maxReel = coin.reel;
    }
    return maxReel + 1;
  }

  int _inferRowCount(FeatureState state) {
    if (state.gridPositionsTotal <= 0) return 3;
    final reels = _inferReelCount(state);
    return reels > 0 ? state.gridPositionsTotal ~/ reels : 3;
  }
}

class _CoinGrid extends StatelessWidget {
  final List<CoinPosition> coins;
  final int totalPositions;
  final int reelCount;
  final int rowCount;

  const _CoinGrid({
    required this.coins,
    required this.totalPositions,
    required this.reelCount,
    required this.rowCount,
  });

  @override
  Widget build(BuildContext context) {
    final lockedPositions = <String, CoinPosition>{};
    for (final coin in coins) {
      lockedPositions[coin.positionKey] = coin;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: reelCount,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: reelCount * rowCount,
        itemBuilder: (context, index) {
          final reel = index % reelCount;
          final row = index ~/ reelCount;
          final posKey = '$reel,$row';
          final coin = lockedPositions[posKey];

          if (coin != null) {
            return _LockedCoinCell(coin: coin);
          }

          return Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LockedCoinCell extends StatelessWidget {
  final CoinPosition coin;

  const _LockedCoinCell({required this.coin});

  @override
  Widget build(BuildContext context) {
    final isSpecial = coin.specialType != null;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSpecial
              ? [const Color(0xFFFFD700), const Color(0xFFFF8F00)]
              : [const Color(0xFFFFA726), const Color(0xFFFF7043)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: (isSpecial
                    ? const Color(0xFFFFD700)
                    : const Color(0xFFFFA726))
                .withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSpecial)
              Icon(
                _specialIcon(coin.specialType!),
                color: Colors.white,
                size: 14,
              ),
            Text(
              coin.value.toStringAsFixed(0),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _specialIcon(CoinSpecialType type) {
    return switch (type) {
      CoinSpecialType.multiplier => Icons.close,
      CoinSpecialType.collector => Icons.all_inclusive,
      CoinSpecialType.upgrade => Icons.arrow_upward,
      CoinSpecialType.wild => Icons.auto_awesome,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BONUS GAME OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _BonusGameOverlay extends StatelessWidget {
  final FeatureState state;

  const _BonusGameOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    final bonusType = state.customData['bonusType'] as String? ?? 'pick';
    final flow = context.read<GameFlowProvider>();

    return Column(
      children: [
        // Info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _OverlayBadge(
                icon: Icons.casino,
                label: bonusType.toUpperCase(),
                value: _progressText(),
                color: const Color(0xFF9C27B0),
              ),
              _OverlayBadge(
                icon: Icons.monetization_on,
                label: 'PRIZE',
                value: state.accumulatedPrize.toStringAsFixed(2),
                color: const Color(0xFF4CAF50),
              ),
            ],
          ),
        ),

        // Bonus content — dispatches to specific widget
        Expanded(
          child: _buildBonusContent(bonusType, flow),
        ),
      ],
    );
  }

  Widget _buildBonusContent(String bonusType, GameFlowProvider flow) {
    return switch (bonusType) {
      'pick' => PickGameWidget(state: state, flow: flow),
      'wheel' => WheelGameWidget(state: state, flow: flow),
      'trail' => TrailGameWidget(state: state, flow: flow),
      'ladder' => LadderGameWidget(state: state, flow: flow),
      _ => Center(
          child: Text(
            'Bonus Round: $bonusType',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
    };
  }

  String _progressText() {
    if (state.picksRemaining > 0) {
      final total = state.customData['totalPicks'] as int? ?? state.picksRemaining;
      return '${total - state.picksRemaining} / $total';
    }
    if (state.totalLevels > 0) {
      return 'Level ${state.currentLevel + 1} / ${state.totalLevels}';
    }
    return '';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GAMBLE OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _GambleOverlay extends StatelessWidget {
  final FeatureState state;
  final GameFlowProvider flow;

  const _GambleOverlay({required this.state, required this.flow});

  @override
  Widget build(BuildContext context) {
    final gambleType = state.customData['gambleType'] as String? ?? 'card_color';
    final history =
        state.customData['history'] as List<dynamic>? ?? [];

    return Column(
      children: [
        // Stake info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _OverlayBadge(
                icon: Icons.monetization_on,
                label: 'STAKE',
                value: state.currentStake.toStringAsFixed(2),
                color: const Color(0xFFFFD700),
              ),
              _OverlayBadge(
                icon: Icons.layers,
                label: 'ROUND',
                value: '${state.roundsPlayed} / ${state.maxRounds}',
                color: const Color(0xFFF44336),
              ),
            ],
          ),
        ),

        // Gamble area
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _gambleLabel(gambleType),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Collect button
                    _GambleButton(
                      label: 'COLLECT',
                      color: const Color(0xFF4CAF50),
                      onTap: () => flow.triggerManual(
                        TransitionTrigger.playerCollect,
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Gamble button
                    _GambleButton(
                      label: 'GAMBLE',
                      color: const Color(0xFFF44336),
                      onTap: () => flow.triggerManual(
                        TransitionTrigger.playerPick,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // History
        if (history.isNotEmpty)
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: history.map<Widget>((entry) {
                final won = (entry as Map)['won'] as bool? ?? false;
                return Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: won
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                        : const Color(0xFFF44336).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    won ? Icons.check : Icons.close,
                    color: Colors.white,
                    size: 14,
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  String _gambleLabel(String type) {
    return switch (type) {
      'card_color' => 'Red or Black?',
      'card_suit' => 'Pick a Suit',
      'coin_flip' => 'Heads or Tails?',
      'wheel' => 'Spin to Gamble',
      _ => 'Double or Nothing',
    };
  }
}

class _GambleButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _GambleButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.7)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// JACKPOT OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _JackpotOverlay extends StatelessWidget {
  final FeatureState state;

  const _JackpotOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    final tierName =
        state.customData['wonTierName'] as String? ?? 'JACKPOT';
    final wonValue =
        state.customData['wonValue'] as double? ?? state.accumulatedWin;

    // Build tier data for ticker widget
    final tierData = _buildTierData();

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Progressive tickers at top
          if (tierData.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: JackpotTickerWidget(tiers: tierData),
            ),

          const SizedBox(height: 24),

          // Won jackpot display
          const Icon(
            Icons.emoji_events,
            color: Color(0xFFFFD700),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            tierName.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            wonValue.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  List<({String name, double value})> _buildTierData() {
    final tierValues =
        state.customData['tierValues'] as Map<String, dynamic>? ?? {};
    if (tierValues.isEmpty) return [];

    return tierValues.entries.map((e) {
      return (name: e.key, value: (e.value as num).toDouble());
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RESPIN OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _RespinOverlay extends StatelessWidget {
  final FeatureState state;

  const _RespinOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    final triggerType =
        state.customData['triggerType'] as String? ?? 'near_miss';
    final hasNudge = state.customData['nudgeEnabled'] as bool? ?? false;
    final stickyCount =
        (state.customData['stickyPositions'] as List<dynamic>?)?.length ?? 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _OverlayBadge(
          icon: Icons.replay,
          label: 'RESPIN',
          value: '${state.spinsRemaining}',
          color: const Color(0xFF00BCD4),
        ),
        const SizedBox(width: 12),
        _OverlayBadge(
          icon: Icons.info_outline,
          label: 'TYPE',
          value: triggerType.replaceAll('_', ' ').toUpperCase(),
          color: const Color(0xFF607D8B),
        ),
        if (stickyCount > 0) ...[
          const SizedBox(width: 12),
          _OverlayBadge(
            icon: Icons.push_pin,
            label: 'STICKY',
            value: '$stickyCount',
            color: const Color(0xFFFF9800),
          ),
        ],
        if (hasNudge) ...[
          const SizedBox(width: 12),
          _OverlayBadge(
            icon: Icons.swap_vert,
            label: 'NUDGE',
            value: 'ACTIVE',
            color: const Color(0xFF9C27B0),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIN PRESENTATION OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _WinPresentationOverlay extends StatelessWidget {
  final GameFlowProvider flow;

  const _WinPresentationOverlay({required this.flow});

  @override
  Widget build(BuildContext context) {
    final totalWin = flow.totalWin;
    final pipeline = flow.lastWinPipeline;
    final multiplierSources = pipeline?.multiplierSources ?? [];

    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.monetization_on,
              color: Color(0xFFFFD700),
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'WIN',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              totalWin.toStringAsFixed(2),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (multiplierSources.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...multiplierSources.map((source) => Text(
                    source,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 12,
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODIFIER INDICATORS — Wild features + Multiplier active badges
// ═══════════════════════════════════════════════════════════════════════════

class _ModifierIndicators extends StatelessWidget {
  final FeatureState? wildState;
  final FeatureState? multiplierState;

  const _ModifierIndicators({this.wildState, this.multiplierState});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (wildState != null) ..._buildWildIndicators(wildState!),
        if (multiplierState != null &&
            multiplierState!.currentMultiplier > 1.0) ...[
          if (wildState != null) const SizedBox(height: 4),
          _OverlayBadge(
            icon: Icons.close,
            label: 'GLOBAL MULT',
            value:
                '${multiplierState!.currentMultiplier.toStringAsFixed(1)}x',
            color: const Color(0xFFE91E63),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildWildIndicators(FeatureState state) {
    final indicators = <Widget>[];
    final data = state.customData;

    final stickyCount =
        (data['stickyPositions'] as List<dynamic>?)?.length ?? 0;
    final walkingCount =
        (data['walkingPositions'] as List<dynamic>?)?.length ?? 0;

    if (stickyCount > 0) {
      indicators.add(_OverlayBadge(
        icon: Icons.push_pin,
        label: 'STICKY WILDS',
        value: '$stickyCount',
        color: const Color(0xFF4CAF50),
      ));
    }
    if (walkingCount > 0) {
      if (indicators.isNotEmpty) indicators.add(const SizedBox(height: 4));
      indicators.add(_OverlayBadge(
        icon: Icons.directions_walk,
        label: 'WALKING WILDS',
        value: '$walkingCount',
        color: const Color(0xFF2196F3),
      ));
    }

    if (data['hasExpandingWilds'] == true) {
      if (indicators.isNotEmpty) indicators.add(const SizedBox(height: 4));
      indicators.add(const _OverlayBadge(
        icon: Icons.unfold_more,
        label: 'EXPANDING',
        value: 'ON',
        color: Color(0xFF9C27B0),
      ));
    }

    if (state.currentMultiplier > 1.0) {
      if (indicators.isNotEmpty) indicators.add(const SizedBox(height: 4));
      indicators.add(_OverlayBadge(
        icon: Icons.auto_awesome,
        label: 'WILD MULT',
        value: '${state.currentMultiplier.toStringAsFixed(1)}x',
        color: Color(0xFFFFD700),
      ));
    }

    return indicators;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COLLECTOR METERS
// ═══════════════════════════════════════════════════════════════════════════

class _CollectorMeters extends StatelessWidget {
  final FeatureState state;

  const _CollectorMeters({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.meterValues.isEmpty) return const SizedBox.shrink();

    return Row(
      children: state.meterValues.entries.map((entry) {
        final target = state.meterTargets[entry.key] ?? 100;
        final progress = target > 0 ? (entry.value / target).clamp(0.0, 1.0) : 0.0;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color.lerp(
                        const Color(0xFF2196F3),
                        const Color(0xFF4CAF50),
                        progress,
                      )!,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.value} / $target',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// QUEUE INDICATOR — Shows pending features
// ═══════════════════════════════════════════════════════════════════════════

class _QueueIndicator extends StatelessWidget {
  final int count;

  const _QueueIndicator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentCyan.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '+$count features',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED OVERLAY BADGE — Reusable indicator
// ═══════════════════════════════════════════════════════════════════════════

class _OverlayBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _OverlayBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 8,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCENE TRANSITION OVERLAY — Premium casino-quality transition between phases
// Inspired by: NetEnt, Pragmatic Play, Big Time Gaming slot machines
// Features: Burst rays, metallic text, multi-layer glow, staggered animations,
//           feature-specific color palettes, decorative particles
// ═══════════════════════════════════════════════════════════════════════════════

class _SceneTransitionOverlay extends StatefulWidget {
  final ActiveTransition transition;
  final VoidCallback onDismiss;

  const _SceneTransitionOverlay({
    required this.transition,
    required this.onDismiss,
  });

  @override
  State<_SceneTransitionOverlay> createState() => _SceneTransitionOverlayState();
}

class _SceneTransitionOverlayState extends State<_SceneTransitionOverlay>
    with TickerProviderStateMixin {
  // Phase 1: Background fade-in
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // Phase 2: Burst rays expansion
  late AnimationController _burstController;
  late Animation<double> _burstExpand;
  late Animation<double> _burstRotation;

  // Phase 3: Plaque entrance (scale + slide)
  late AnimationController _plaqueController;
  late Animation<double> _plaqueScale;
  late Animation<double> _plaqueSlide;
  late Animation<double> _plaqueOpacity;

  // Phase 4: Glow pulse (continuous loop)
  late AnimationController _glowPulseController;
  late Animation<double> _glowPulse;

  // Phase 5: Shimmer sweep across plaque
  late AnimationController _shimmerController;
  late Animation<double> _shimmerPosition;

  // Phase 6: "TAP TO CONTINUE" blink
  late AnimationController _hintBlinkController;
  late Animation<double> _hintOpacity;

  bool get _isExit => widget.transition.phase == TransitionPhase.exiting;

  /// Duration scale factor relative to default 3000ms
  double get _dScale {
    final ms = widget.transition.config.durationMs.clamp(500, 30000);
    return ms / 3000.0;
  }

  int _scaled(int baseMs) => (_dScale * baseMs).round();

  TransitionStyle get _style => widget.transition.config.style;
  SceneTransitionConfig get _cfg => widget.transition.config;

  /// Per-phase duration: uses override if set, otherwise scales from base
  int _phaseDuration(int? overrideMs, int baseMs) {
    return overrideMs ?? _scaled(baseMs);
  }

  /// Per-phase stagger delay: uses override if set, otherwise scales from base
  int _staggerDelay(int? overrideMs, int baseMs) {
    return overrideMs ?? _scaled(baseMs);
  }

  @override
  void initState() {
    super.initState();

    final s = _dScale;
    final cfg = _cfg;

    // ═══════════════════════════════════════════════════════════════════
    // PHASE 1: Background blackout
    // ═══════════════════════════════════════════════════════════════════
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _phaseDuration(cfg.fadePhaseMs, 350)),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    // ═══════════════════════════════════════════════════════════════════
    // PHASE 2: Burst rays — radiating lines behind plaque
    // ═══════════════════════════════════════════════════════════════════
    _burstController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _phaseDuration(cfg.burstPhaseMs, 750)),
    );
    _burstExpand = Tween<double>(begin: 0.0, end: cfg.burstIntensity).animate(
      CurvedAnimation(parent: _burstController, curve: Curves.easeOutCubic),
    );
    _burstRotation = Tween<double>(begin: 0.0, end: 0.15).animate(
      CurvedAnimation(parent: _burstController, curve: Curves.easeOut),
    );

    // ═══════════════════════════════════════════════════════════════════
    // PHASE 3: Plaque entrance — style-dependent animation
    // ═══════════════════════════════════════════════════════════════════
    _plaqueController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _phaseDuration(cfg.plaquePhaseMs, 700)),
    );
    _setupPlaqueAnimations();

    // ═══════════════════════════════════════════════════════════════════
    // PHASE 4: Glow pulse (continuous) — breathing effect
    // ═══════════════════════════════════════════════════════════════════
    _glowPulseController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: cfg.glowPhaseMs ?? (1600 * s).round().clamp(800, 4000),
      ),
    );
    _glowPulse = Tween<double>(begin: 0.7 * cfg.glowIntensity, end: cfg.glowIntensity).animate(
      CurvedAnimation(parent: _glowPulseController, curve: Curves.easeInOut),
    );

    // ═══════════════════════════════════════════════════════════════════
    // PHASE 5: Shimmer sweep (loops) — glossy highlight
    // ═══════════════════════════════════════════════════════════════════
    _shimmerController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: cfg.shimmerPhaseMs ?? (2000 * s).round().clamp(1000, 5000),
      ),
    );
    _shimmerPosition = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // ═══════════════════════════════════════════════════════════════════
    // PHASE 6: Hint blink (after plaque settles)
    // ═══════════════════════════════════════════════════════════════════
    _hintBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _hintOpacity = Tween<double>(begin: 0.3, end: 0.9).animate(
      CurvedAnimation(parent: _hintBlinkController, curve: Curves.easeInOut),
    );

    // ═══════════════════════════════════════════════════════════════════
    // STAGGERED LAUNCH SEQUENCE — per-phase delay overrides
    // ═══════════════════════════════════════════════════════════════════
    _fadeController.forward();

    if (cfg.showBurst) {
      Future.delayed(Duration(milliseconds: _staggerDelay(cfg.burstDelayMs, 150)), () {
        if (mounted) {
          _burstController.forward();
          _firePhaseAudio(cfg.burstAudioStage);
        }
      });
    }

    Future.delayed(Duration(milliseconds: _staggerDelay(cfg.plaqueDelayMs, 250)), () {
      if (mounted && cfg.showPlaque) {
        _plaqueController.forward();
        _firePhaseAudio(cfg.plaqueAudioStage);
      }
    });

    Future.delayed(Duration(milliseconds: _staggerDelay(cfg.glowDelayMs, 800)), () {
      if (mounted) {
        if (cfg.showGlow) _glowPulseController.repeat(reverse: true);
        _hintBlinkController.repeat(reverse: true);
      }
    });

    Future.delayed(Duration(milliseconds: _staggerDelay(cfg.shimmerDelayMs, 1200)), () {
      if (mounted && cfg.showShimmer) _shimmerController.repeat();
    });
  }

  /// Fire per-phase audio stage if configured
  void _firePhaseAudio(String? audioStage) {
    if (audioStage == null || audioStage.isEmpty) return;
    EventRegistry.instance.triggerStage(audioStage);
  }

  /// Setup plaque entrance animations based on TransitionStyle
  void _setupPlaqueAnimations() {
    switch (_style) {
      case TransitionStyle.fade:
        // Pure fade — no movement, no scale
        _plaqueScale = Tween<double>(begin: 1.0, end: 1.0).animate(_plaqueController);
        _plaqueSlide = Tween<double>(begin: 0.0, end: 0.0).animate(_plaqueController);
        _plaqueOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.easeIn),
        );

      case TransitionStyle.slideUp:
        // Slide from below with elastic bounce
        _plaqueScale = Tween<double>(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.easeOut),
        );
        _plaqueSlide = Tween<double>(begin: 200.0, end: 0.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.easeOutBack),
        );
        _plaqueOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _plaqueController,
            curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
          ),
        );

      case TransitionStyle.slideDown:
        // Slide from above, drop-in feel
        _plaqueScale = Tween<double>(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.easeOut),
        );
        _plaqueSlide = Tween<double>(begin: -200.0, end: 0.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.easeOutCubic),
        );
        _plaqueOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _plaqueController,
            curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
          ),
        );

      case TransitionStyle.zoom:
        // Explosive zoom from center
        _plaqueScale = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.elasticOut),
        );
        _plaqueSlide = Tween<double>(begin: 0.0, end: 0.0).animate(_plaqueController);
        _plaqueOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _plaqueController,
            curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
          ),
        );

      case TransitionStyle.swoosh:
        // Fast horizontal sweep from left with slight rotation
        _plaqueScale = Tween<double>(begin: 0.8, end: 1.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.easeOutBack),
        );
        _plaqueSlide = Tween<double>(begin: -400.0, end: 0.0).animate(
          CurvedAnimation(parent: _plaqueController, curve: Curves.easeOutCubic),
        );
        _plaqueOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _plaqueController,
            curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
          ),
        );
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _burstController.dispose();
    _plaqueController.dispose();
    _glowPulseController.dispose();
    _shimmerController.dispose();
    _hintBlinkController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FEATURE COLOR PALETTES — Rich multi-color palettes per feature type
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary accent color (border, text glow)
  Color get _accentColor {
    final state = _isExit ? widget.transition.fromState : widget.transition.toState;
    return switch (state) {
      GameFlowState.freeSpins => const Color(0xFF00E5FF),
      GameFlowState.bonusGame => const Color(0xFFFFD700),
      GameFlowState.holdAndWin => const Color(0xFFFF6D00),
      GameFlowState.gamble => const Color(0xFFE040FB),
      GameFlowState.jackpotPresentation => const Color(0xFFFF1744),
      _ => const Color(0xFF4A9EFF),
    };
  }

  /// Secondary color (gradient end, burst rays alternate)
  Color get _secondaryColor {
    final state = _isExit ? widget.transition.fromState : widget.transition.toState;
    return switch (state) {
      GameFlowState.freeSpins => const Color(0xFF40C8FF),
      GameFlowState.bonusGame => const Color(0xFFFF9040),
      GameFlowState.holdAndWin => const Color(0xFFFFD700),
      GameFlowState.gamble => const Color(0xFFFF66FF),
      GameFlowState.jackpotPresentation => const Color(0xFFFFD700),
      _ => const Color(0xFF81D4FA),
    };
  }

  /// Metallic gradient colors for text
  List<Color> get _metallicColors {
    return [
      Colors.white,
      _accentColor,
      _secondaryColor,
      Colors.white.withOpacity(0.9),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD — Layered composition: bg → burst → plaque → shimmer → hint
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = widget.transition;
    final canDismiss = t.config.dismissMode == TransitionDismissMode.clickToContinue ||
        t.config.dismissMode == TransitionDismissMode.timedOrClick;

    return GestureDetector(
      onTap: canDismiss ? widget.onDismiss : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _fadeAnim,
          _burstController,
          _plaqueController,
          _glowPulseController,
          _shimmerController,
          _hintBlinkController,
        ]),
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              // Both phases: fully opaque — reels MUST NOT be visible during transitions
              // (industry standard: transition plaque completely covers the reel area)
              const bgOpacity = 1.0;
              return Container(
                color: Colors.black.withOpacity(bgOpacity * _fadeAnim.value),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // LAYER 1: Ambient radial gradient (feature-colored)
                    if (_fadeAnim.value > 0.3)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                _accentColor.withOpacity(0.12 * _fadeAnim.value),
                                Colors.transparent,
                              ],
                              radius: 0.8,
                            ),
                          ),
                        ),
                      ),

                    // LAYER 2: Burst rays (radiating behind plaque)
                    if (_cfg.showBurst && _burstExpand.value > 0.01)
                      CustomPaint(
                        size: Size(
                          constraints.maxWidth * 0.9,
                          constraints.maxHeight * 0.7,
                        ),
                        painter: _TransitionBurstPainter(
                          progress: _burstExpand.value,
                          rotation: _burstRotation.value,
                          pulseValue: _glowPulse.value,
                          primaryColor: _accentColor,
                          secondaryColor: _secondaryColor,
                          rayCount: _cfg.burstRayCount > 0
                              ? _cfg.burstRayCount
                              : (_isExit ? 20 : 16),
                          isExit: _isExit,
                        ),
                      ),

                    // LAYER 3: Outer glow halo (pulsing)
                    if (_cfg.showGlow)
                      Container(
                        width: 400,
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: _accentColor.withOpacity(
                                0.3 * _glowPulse.value * _plaqueOpacity.value,
                              ),
                              blurRadius: 80 * _glowPulse.value,
                              spreadRadius: 20,
                            ),
                            BoxShadow(
                              color: _secondaryColor.withOpacity(
                                0.15 * _glowPulse.value * _plaqueOpacity.value,
                              ),
                              blurRadius: 120 * _glowPulse.value,
                              spreadRadius: 40,
                            ),
                          ],
                        ),
                      ),

                    // LAYER 4: Main plaque with style-dependent entrance
                    Opacity(
                      opacity: _plaqueOpacity.value,
                      child: Transform.translate(
                        offset: _style == TransitionStyle.swoosh
                            ? Offset(_plaqueSlide.value, 0)
                            : Offset(0, _plaqueSlide.value),
                        child: Transform.scale(
                          scale: _plaqueScale.value,
                          child: _buildPremiumPlaque(t, canDismiss),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PREMIUM PLAQUE — Multi-layer container with metallic styling
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPremiumPlaque(ActiveTransition t, bool canDismiss) {
    final glowIntensity = _glowPulse.value.clamp(0.0, 1.0);
    final borderOpacity = (0.6 + glowIntensity * 0.4).clamp(0.0, 1.0);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Main container
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 500),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _accentColor.withOpacity(0.35),
                _accentColor.withOpacity(0.12),
                Colors.black.withOpacity(0.88),
                _accentColor.withOpacity(0.08),
              ],
              stops: const [0.0, 0.2, 0.65, 1.0],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _accentColor.withOpacity(borderOpacity),
              width: 3,
            ),
            boxShadow: [
              // Inner depth
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 15,
                spreadRadius: -5,
                offset: const Offset(0, 5),
              ),
              // Primary glow
              BoxShadow(
                color: _accentColor.withOpacity(0.7 * glowIntensity),
                blurRadius: 40,
                spreadRadius: 5,
              ),
              // Pulsing outer glow
              BoxShadow(
                color: _accentColor.withOpacity(0.4 * glowIntensity),
                blurRadius: 80 * glowIntensity,
                spreadRadius: 12 * glowIntensity,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ═══════════════════════════════════════════════════════════
              // DECORATIVE STARS — Top row
              // ═══════════════════════════════════════════════════════════
              _buildStarRow(glowIntensity, [16, 20, 24, 20, 16]),
              const SizedBox(height: 10),

              // ═══════════════════════════════════════════════════════════
              // FEATURE ICON — Animated with glow
              // ═══════════════════════════════════════════════════════════
              _buildFeatureIcon(t),
              const SizedBox(height: 8),

              // ═══════════════════════════════════════════════════════════
              // TITLE — Metallic gradient text
              // ═══════════════════════════════════════════════════════════
              if (t.config.showPlaque) _buildMetallicTitle(t),

              // ═══════════════════════════════════════════════════════════
              // TOTAL WIN (exit only) — Premium counter display
              // ═══════════════════════════════════════════════════════════
              if (_isExit && t.config.showWinOnExit && t.totalWin > 0)
                _buildTotalWinDisplay(t.totalWin, glowIntensity),

              // ═══════════════════════════════════════════════════════════
              // DECORATIVE STARS — Bottom row
              // ═══════════════════════════════════════════════════════════
              const SizedBox(height: 10),
              _buildStarRow(glowIntensity, [14, 18, 14]),

              // ═══════════════════════════════════════════════════════════
              // TAP TO CONTINUE — Blinking hint
              // ═══════════════════════════════════════════════════════════
              if (canDismiss) ...[
                const SizedBox(height: 16),
                Opacity(
                  opacity: _hintOpacity.value,
                  child: Text(
                    'TAP TO CONTINUE',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Glossy highlight overlay (top shine)
        Positioned(
          top: 0,
          left: 20,
          right: 20,
          child: IgnorePointer(
            child: Container(
              height: 35,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.22),
                    Colors.white.withOpacity(0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Shimmer sweep (diagonal highlight moving across)
        if (_cfg.showShimmer && _shimmerPosition.value > -0.5 && _shimmerPosition.value < 1.5)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment(-1.0 + _shimmerPosition.value * 2, -0.3),
                    end: Alignment(-0.5 + _shimmerPosition.value * 2, 0.3),
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.08 * _cfg.shimmerIntensity),
                      Colors.transparent,
                    ],
                  ).createShader(bounds),
                  blendMode: BlendMode.srcATop,
                  child: Container(color: Colors.white.withOpacity(0.01)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FEATURE ICON — Large, glowing, feature-specific icon
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFeatureIcon(ActiveTransition t) {
    final icon = _isExit ? Icons.emoji_events : _featureIcon(t.toState);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.5 * _glowPulse.value),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: _accentColor,
        size: 44,
        shadows: [
          Shadow(color: Colors.white.withOpacity(0.8), blurRadius: 3),
          Shadow(color: _accentColor, blurRadius: 15),
          Shadow(color: _accentColor.withOpacity(0.6), blurRadius: 30),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METALLIC TITLE — ShaderMask gradient text with emboss shadows
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetallicTitle(ActiveTransition t) {
    final lines = t.plaqueText.split('\n');
    final mainText = lines.first;
    final subText = lines.length > 1 ? lines.sublist(1).join('\n') : null;
    final mainFontSize = _isExit ? 28.0 : 32.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main title — metallic gradient
        _buildMetallicText(mainText, mainFontSize),

        // Sub text (e.g., "10 SPINS WON") — smaller, accent colored
        if (subText != null) ...[
          const SizedBox(height: 8),
          _buildMetallicText(subText, mainFontSize * 0.65),
        ],
      ],
    );
  }

  Widget _buildMetallicText(String text, double fontSize) {
    return Stack(
      children: [
        // Background glow layer
        ShaderMask(
          shaderCallback: (bounds) => RadialGradient(
            colors: [
              _accentColor,
              _accentColor.withOpacity(0.5),
              Colors.transparent,
            ],
          ).createShader(bounds),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize + 2,
              fontWeight: FontWeight.w900,
              color: Colors.white.withOpacity(0.3),
              letterSpacing: 5,
            ),
          ),
        ),
        // Main metallic text
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _metallicColors,
            stops: const [0.0, 0.3, 0.7, 1.0],
          ).createShader(bounds),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 4,
              shadows: [
                // Emboss shadow
                Shadow(
                  color: Colors.black.withOpacity(0.8),
                  blurRadius: 2,
                  offset: const Offset(1, 2),
                ),
                // Primary glow
                Shadow(color: _accentColor, blurRadius: 20),
                // Outer ambient glow
                Shadow(color: _accentColor.withOpacity(0.6), blurRadius: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOTAL WIN DISPLAY — Premium counter with metallic styling (exit only)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTotalWinDisplay(double totalWin, double glowIntensity) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        // "TOTAL WIN" label
        Text(
          'TOTAL WIN',
          style: TextStyle(
            color: _secondaryColor.withOpacity(0.8),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            shadows: [
              Shadow(color: _secondaryColor.withOpacity(0.5), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Win amount with premium styling
        Transform.scale(
          scale: 1.0 + (_glowPulse.value - 0.7) * 0.04,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.5),
                  _accentColor.withOpacity(0.1),
                  Colors.black.withOpacity(0.5),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _accentColor.withOpacity(0.35),
                width: 1,
              ),
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white,
                  const Color(0xFFFFD700),
                  _accentColor,
                  Colors.white,
                ],
                stops: const [0.0, 0.25, 0.75, 1.0],
              ).createShader(bounds),
              child: Text(
                totalWin.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 3,
                  height: 1.1,
                  shadows: [
                    const Shadow(color: Colors.white, blurRadius: 4),
                    Shadow(
                      color: Colors.black.withOpacity(0.9),
                      blurRadius: 3,
                      offset: const Offset(2, 3),
                    ),
                    Shadow(
                      color: _accentColor.withOpacity(0.9),
                      blurRadius: 30,
                    ),
                    const Shadow(
                      color: Color(0xFFFFD700),
                      blurRadius: 20,
                    ),
                    Shadow(
                      color: _accentColor.withOpacity(glowIntensity * 0.8),
                      blurRadius: 50 * glowIntensity,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DECORATIVE STARS ROW — Animated with glow pulse
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStarRow(double glowIntensity, List<double> sizes) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < sizes.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          _buildDecorativeStar(sizes[i], glowIntensity),
        ],
      ],
    );
  }

  Widget _buildDecorativeStar(double size, double glowIntensity) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.8,
            height: size * 0.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withOpacity(0.5 * glowIntensity),
                  blurRadius: size * 0.5,
                  spreadRadius: size * 0.1,
                ),
              ],
            ),
          ),
          Icon(
            Icons.star,
            size: size,
            color: _accentColor,
            shadows: [
              Shadow(color: Colors.white.withOpacity(0.8), blurRadius: 2),
              Shadow(color: _accentColor, blurRadius: 8),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FEATURE ICONS
  // ═══════════════════════════════════════════════════════════════════════════

  IconData _featureIcon(GameFlowState state) {
    return switch (state) {
      GameFlowState.freeSpins => Icons.stars,
      GameFlowState.bonusGame => Icons.casino,
      GameFlowState.holdAndWin => Icons.lock,
      GameFlowState.gamble => Icons.swap_vert,
      GameFlowState.jackpotPresentation => Icons.diamond,
      GameFlowState.respin => Icons.refresh,
      _ => Icons.play_arrow,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BURST RAY PAINTER — Radiating lines behind plaque (casino-standard effect)
// ═══════════════════════════════════════════════════════════════════════════════

class _TransitionBurstPainter extends CustomPainter {
  final double progress;
  final double rotation;
  final double pulseValue;
  final Color primaryColor;
  final Color secondaryColor;
  final int rayCount;
  final bool isExit;

  _TransitionBurstPainter({
    required this.progress,
    required this.rotation,
    required this.pulseValue,
    required this.primaryColor,
    required this.secondaryColor,
    required this.rayCount,
    required this.isExit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.5 * progress;
    if (maxRadius < 1) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final angleStep = (3.14159265 * 2) / rayCount;
    final rayWidth = angleStep * 0.35;

    for (int i = 0; i < rayCount; i++) {
      final angle = i * angleStep;
      final isPrimary = i % 2 == 0;
      final color = isPrimary ? primaryColor : secondaryColor;

      // Pulsing opacity per ray
      final baseOpacity = isPrimary ? 0.35 : 0.2;
      final pulseAdd = (pulseValue - 0.7) * 0.15;
      final opacity = (baseOpacity + pulseAdd).clamp(0.05, 0.5);

      // Ray length varies by index for organic feel
      final lengthMod = 0.85 + (i % 3) * 0.075;
      final rayLength = maxRadius * lengthMod;

      final path = Path();
      path.moveTo(0, 0);
      path.lineTo(
        rayLength * _cos(angle - rayWidth / 2),
        rayLength * _sin(angle - rayWidth / 2),
      );
      path.lineTo(
        rayLength * _cos(angle + rayWidth / 2),
        rayLength * _sin(angle + rayWidth / 2),
      );
      path.close();

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withOpacity(opacity),
            color.withOpacity(opacity * 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rayLength))
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  double _cos(double angle) => _cosApprox(angle);
  double _sin(double angle) => _sinApprox(angle);

  // Fast trig approximation (good enough for visual effects)
  static double _cosApprox(double x) {
    // Normalize to [-pi, pi]
    while (x > 3.14159265) x -= 6.28318530;
    while (x < -3.14159265) x += 6.28318530;
    final x2 = x * x;
    return 1.0 - x2 * 0.5 + x2 * x2 * 0.04166667;
  }

  static double _sinApprox(double x) {
    return _cosApprox(x - 1.57079632);
  }

  @override
  bool shouldRepaint(_TransitionBurstPainter old) =>
      old.progress != progress ||
      old.rotation != rotation ||
      old.pulseValue != pulseValue;
}
