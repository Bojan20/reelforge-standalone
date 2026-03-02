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

class _FreeSpinsOverlay extends StatelessWidget {
  final FeatureState state;

  const _FreeSpinsOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Spin counter
        _OverlayBadge(
          icon: Icons.star,
          label: 'SPINS',
          value: '${state.spinsRemaining} / ${state.totalSpins}',
          color: const Color(0xFF4CAF50),
        ),
        const SizedBox(width: 12),

        // Multiplier (if active)
        if (state.currentMultiplier > 1.0)
          _OverlayBadge(
            icon: Icons.close,
            label: 'MULTIPLIER',
            value: '${state.currentMultiplier.toStringAsFixed(1)}x',
            color: const Color(0xFFFFD700),
          ),

        // Retrigger count
        if ((state.customData['retriggersUsed'] as int? ?? 0) > 0) ...[
          const SizedBox(width: 12),
          _OverlayBadge(
            icon: Icons.refresh,
            label: 'RETRIGGER',
            value: '${state.customData['retriggersUsed']}',
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
// SCENE TRANSITION OVERLAY — Full-screen transition between game phases
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
  late AnimationController _fadeController;
  late AnimationController _plaqueController;
  late Animation<double> _fadeAnim;
  late Animation<double> _plaqueScale;
  late Animation<double> _plaqueOpacity;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _plaqueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _plaqueScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _plaqueController, curve: Curves.elasticOut),
    );
    _plaqueOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _plaqueController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _plaqueController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _plaqueController.dispose();
    super.dispose();
  }

  Color get _accentColor {
    return switch (widget.transition.toState) {
      GameFlowState.freeSpins => const Color(0xFF00E5FF),
      GameFlowState.bonusGame => const Color(0xFFFFD700),
      GameFlowState.holdAndWin => const Color(0xFFFF6D00),
      GameFlowState.gamble => const Color(0xFFE040FB),
      GameFlowState.jackpotPresentation => const Color(0xFFFF1744),
      _ => const Color(0xFF4A9EFF),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transition;
    final canDismiss = t.config.dismissMode == TransitionDismissMode.clickToContinue ||
        t.config.dismissMode == TransitionDismissMode.timedOrClick;

    return GestureDetector(
      onTap: canDismiss ? widget.onDismiss : null,
      child: AnimatedBuilder(
        animation: _fadeAnim,
        builder: (context, child) {
          return Container(
            color: Colors.black.withValues(alpha: 0.85 * _fadeAnim.value),
            child: Center(
              child: AnimatedBuilder(
                animation: _plaqueController,
                builder: (context, _) {
                  return Opacity(
                    opacity: _plaqueOpacity.value,
                    child: Transform.scale(
                      scale: _plaqueScale.value,
                      child: _buildPlaqueContent(t, canDismiss),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaqueContent(ActiveTransition t, bool canDismiss) {
    final isExit = t.phase == TransitionPhase.exiting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accentColor.withValues(alpha: 0.3),
            const Color(0xFF0A0A14),
            _accentColor.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _accentColor.withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Feature icon
          Icon(
            isExit ? Icons.emoji_events : _featureIcon(t.toState),
            color: _accentColor,
            size: 40,
          ),
          const SizedBox(height: 12),

          // Plaque title
          if (t.config.showPlaque)
            Text(
              t.plaqueText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [
                  Shadow(color: _accentColor, blurRadius: 12),
                ],
              ),
            ),

          // Total win (exit only)
          if (isExit && t.config.showWinOnExit && t.totalWin > 0) ...[
            const SizedBox(height: 16),
            Text(
              'TOTAL WIN',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.totalWin.toStringAsFixed(2),
              style: TextStyle(
                color: _accentColor,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(color: _accentColor, blurRadius: 16),
                ],
              ),
            ),
          ],

          // Click to continue hint
          if (canDismiss) ...[
            const SizedBox(height: 20),
            Text(
              'TAP TO CONTINUE',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

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
