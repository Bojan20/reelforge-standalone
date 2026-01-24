/// Droppable Slot Preview — Premium Slot Preview with Drop Targets
///
/// Wraps PremiumSlotPreview UI elements with DropTargetWrapper for
/// audio asset drag-drop functionality.
///
/// Drop Zones:
/// - Spin button → "ui.spin"
/// - Auto-spin button → "ui.autospin"
/// - Turbo button → "ui.turbo"
/// - Reel area → "reel.surface"
/// - Individual reel columns → "reel.0" - "reel.4" (0-indexed)
/// - Win display overlay → "overlay.win"
/// - Jackpot displays → "overlay.jackpot.mini/minor/major/grand"
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section A.2
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../theme/fluxforge_theme.dart';
import 'drop_target_wrapper.dart';

// =============================================================================
// DROP ZONE DEFINITIONS
// =============================================================================

/// Factory for creating slot preview drop targets
class SlotDropZones {
  // UI Buttons
  static DropTarget spinButton() => DropTarget(
        targetId: 'ui.spin',
        targetType: TargetType.uiButton,
        targetTags: const ['primary', 'cta', 'spin'],
        stageContext: StageContext.global,
        interactionSemantics: const ['press', 'release'],
      );

  static DropTarget autoSpinButton() => DropTarget(
        targetId: 'ui.autospin',
        targetType: TargetType.uiToggle,
        targetTags: const ['secondary', 'autospin'],
        stageContext: StageContext.global,
        interactionSemantics: const ['toggle_on', 'toggle_off'],
      );

  static DropTarget turboButton() => DropTarget(
        targetId: 'ui.turbo',
        targetType: TargetType.uiToggle,
        targetTags: const ['secondary', 'turbo', 'speed'],
        stageContext: StageContext.global,
        interactionSemantics: const ['toggle_on', 'toggle_off'],
      );

  static DropTarget maxBetButton() => DropTarget(
        targetId: 'ui.maxbet',
        targetType: TargetType.uiButton,
        targetTags: const ['secondary', 'bet'],
        stageContext: StageContext.global,
        interactionSemantics: const ['press'],
      );

  static DropTarget betSelector(String direction) => DropTarget(
        targetId: 'ui.bet.$direction',
        targetType: TargetType.uiButton,
        targetTags: const ['secondary', 'bet', 'selector'],
        stageContext: StageContext.global,
        interactionSemantics: const ['press'],
      );

  // Reel Zones
  static DropTarget reelSurface() => DropTarget(
        targetId: 'reel.surface',
        targetType: TargetType.reelSurface,
        targetTags: const ['reels', 'main', 'spin'],
        stageContext: StageContext.global,
        interactionSemantics: const ['spin_start', 'spin_stop', 'anticipation'],
      );

  static DropTarget reelColumn(int index) => DropTarget(
        targetId: 'reel.$index',
        targetType: TargetType.reelStopZone,
        targetTags: ['reels', 'column', 'reel_$index'],
        stageContext: StageContext.global,
        interactionSemantics: const ['reel_stop', 'anticipation_on', 'anticipation_off'],
      );

  // Win Overlays
  static DropTarget winOverlay(String tier) => DropTarget(
        targetId: 'overlay.win.$tier',
        targetType: TargetType.overlay,
        targetTags: ['win', tier, 'celebration'],
        stageContext: StageContext.global,
        interactionSemantics: const ['show', 'hide', 'pulse', 'tier_up'],
      );

  static DropTarget jackpotDisplay(String tier) => DropTarget(
        targetId: 'overlay.jackpot.$tier',
        targetType: TargetType.overlay,
        targetTags: ['jackpot', tier, 'progressive'],
        stageContext: StageContext.global,
        interactionSemantics: const ['hit', 'tick', 'near_hit'],
      );

  // Feature Zones
  static DropTarget featureIndicator(String feature) => DropTarget(
        targetId: 'feature.$feature',
        targetType: TargetType.featureContainer,
        targetTags: ['feature', feature],
        stageContext: StageContext.global,
        interactionSemantics: const ['enter', 'exit', 'progress'],
      );

  // HUD Elements
  static DropTarget balanceDisplay() => DropTarget(
        targetId: 'hud.balance',
        targetType: TargetType.hudCounter,
        targetTags: const ['balance', 'counter'],
        stageContext: StageContext.global,
        interactionSemantics: const ['increment', 'decrement', 'rollup'],
      );

  static DropTarget winDisplay() => DropTarget(
        targetId: 'hud.win',
        targetType: TargetType.hudMeter,
        targetTags: const ['win', 'meter', 'rollup'],
        stageContext: StageContext.global,
        interactionSemantics: const ['show', 'hide', 'rollup_tick', 'rollup_end'],
      );

  // Symbol Zones (B.9)
  static DropTarget symbolZone(String symbolType) => DropTarget(
        targetId: 'symbol.$symbolType',
        targetType: TargetType.symbolZone,
        targetTags: ['symbol', symbolType],
        stageContext: StageContext.global,
        interactionSemantics: const ['land', 'highlight', 'animate', 'win_line'],
      );

  static DropTarget wildSymbol() => symbolZone('wild');
  static DropTarget scatterSymbol() => symbolZone('scatter');
  static DropTarget bonusSymbol() => symbolZone('bonus');
  static DropTarget highPaySymbol(int rank) => symbolZone('hp$rank'); // hp1, hp2, hp3, hp4
  static DropTarget lowPaySymbol(int rank) => symbolZone('lp$rank');  // lp1, lp2, lp3, lp4

  // Music Zones (B.10)
  static DropTarget backgroundMusic(String context) => DropTarget(
        targetId: 'music.$context',
        targetType: TargetType.musicZone,
        targetTags: ['music', 'background', context],
        stageContext: StageContext.global,
        interactionSemantics: const ['play', 'stop', 'crossfade', 'layer'],
      );

  static DropTarget baseGameMusic() => backgroundMusic('base');
  static DropTarget freeSpinsMusic() => backgroundMusic('freespins');
  static DropTarget bonusMusic() => backgroundMusic('bonus');
  static DropTarget bigWinMusic() => backgroundMusic('bigwin');
  static DropTarget anticipationMusic() => backgroundMusic('anticipation');
}

// =============================================================================
// DROPPABLE SPIN BUTTON
// =============================================================================

/// Spin button wrapped with drop target
class DroppableSpinButton extends StatelessWidget {
  final Widget child;
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableSpinButton({
    super.key,
    required this.child,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: SlotDropZones.spinButton(),
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      glowColor: FluxForgeTheme.accentBlue,
      onEventCreated: onEventCreated,
      child: child,
    );
  }
}

// =============================================================================
// DROPPABLE CONTROL BUTTON (Generic)
// =============================================================================

/// Generic control button with drop target
class DroppableControlButton extends StatelessWidget {
  final Widget child;
  final DropTarget target;
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableControlButton({
    super.key,
    required this.child,
    required this.target,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: target,
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      onEventCreated: onEventCreated,
      child: child,
    );
  }
}

// =============================================================================
// DROPPABLE REEL FRAME
// =============================================================================

/// Reel frame with drop zones for individual columns
class DroppableReelFrame extends StatelessWidget {
  final Widget child;
  final int reelCount;
  final void Function(int reelIndex, CommittedEvent event)? onReelEventCreated;
  final void Function(CommittedEvent event)? onSurfaceEventCreated;

  const DroppableReelFrame({
    super.key,
    required this.child,
    this.reelCount = 5,
    this.onReelEventCreated,
    this.onSurfaceEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main reel surface drop target
        DropTargetWrapper(
          target: SlotDropZones.reelSurface(),
          showBadge: true,
          badgeAlignment: Alignment.bottomRight,
          glowColor: FluxForgeTheme.accentOrange,
          onEventCreated: onSurfaceEventCreated,
          child: child,
        ),

        // Individual reel column drop zones (overlay)
        Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth = constraints.maxWidth / reelCount;
                return Row(
                  children: List.generate(reelCount, (index) {
                    return SizedBox(
                      width: columnWidth,
                      child: _ReelColumnDropZone(
                        reelIndex: index,
                        onEventCreated: onReelEventCreated != null
                            ? (event) => onReelEventCreated!(index, event)
                            : null,
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ReelColumnDropZone extends StatelessWidget {
  final int reelIndex;
  final void Function(CommittedEvent event)? onEventCreated;

  const _ReelColumnDropZone({
    required this.reelIndex,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: SlotDropZones.reelColumn(reelIndex),
      showBadge: true,
      badgeAlignment: Alignment.topCenter,
      glowColor: _getReelColor(reelIndex),
      onEventCreated: onEventCreated,
      child: Container(
        // Transparent overlay for drop detection
        color: Colors.transparent,
      ),
    );
  }

  Color _getReelColor(int index) {
    const colors = [
      FluxForgeTheme.accentBlue,
      FluxForgeTheme.accentCyan,
      FluxForgeTheme.accentGreen,
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentRed,
    ];
    return colors[index % colors.length];
  }
}

// =============================================================================
// DROPPABLE WIN DISPLAY
// =============================================================================

/// Win display overlay with drop targets for different win tiers
class DroppableWinDisplay extends StatelessWidget {
  final Widget child;
  final String currentTier;
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableWinDisplay({
    super.key,
    required this.child,
    this.currentTier = 'small',
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: SlotDropZones.winOverlay(currentTier),
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      glowColor: _getTierColor(currentTier),
      onEventCreated: onEventCreated,
      child: child,
    );
  }

  Color _getTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'ultra':
        return const Color(0xFFFF4080);
      case 'epic':
        return const Color(0xFFE040FB);
      case 'mega':
        return const Color(0xFFFFD700);
      case 'big':
        return const Color(0xFF40FF90);
      default:
        return const Color(0xFF40C8FF);
    }
  }
}

// =============================================================================
// DROPPABLE JACKPOT DISPLAY
// =============================================================================

/// Jackpot display with drop targets
class DroppableJackpotDisplay extends StatelessWidget {
  final Widget child;
  final String tier; // mini, minor, major, grand
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableJackpotDisplay({
    super.key,
    required this.child,
    required this.tier,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: SlotDropZones.jackpotDisplay(tier),
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      glowColor: _getJackpotColor(tier),
      onEventCreated: onEventCreated,
      child: child,
    );
  }

  Color _getJackpotColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'grand':
        return const Color(0xFFFFD700); // Gold
      case 'major':
        return const Color(0xFFFF4080); // Magenta
      case 'minor':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFF4CAF50); // Green
    }
  }
}

// =============================================================================
// DROPPABLE FEATURE INDICATOR
// =============================================================================

/// Feature indicator (free spins, bonus, etc) with drop target
class DroppableFeatureIndicator extends StatelessWidget {
  final Widget child;
  final String feature; // 'freespins', 'bonus', 'multiplier', 'cascade'
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableFeatureIndicator({
    super.key,
    required this.child,
    required this.feature,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: SlotDropZones.featureIndicator(feature),
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      glowColor: _getFeatureColor(feature),
      onEventCreated: onEventCreated,
      child: child,
    );
  }

  Color _getFeatureColor(String feature) {
    switch (feature.toLowerCase()) {
      case 'freespins':
        return FluxForgeTheme.accentGreen;
      case 'bonus':
        return FluxForgeTheme.accentOrange;
      case 'multiplier':
        return const Color(0xFFFFD700);
      case 'cascade':
        return FluxForgeTheme.accentCyan;
      default:
        return FluxForgeTheme.accentBlue;
    }
  }
}

// =============================================================================
// DROPPABLE HUD ELEMENT
// =============================================================================

/// Balance/Win display with drop target
class DroppableHudElement extends StatelessWidget {
  final Widget child;
  final String elementType; // 'balance', 'win', 'bet'
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableHudElement({
    super.key,
    required this.child,
    required this.elementType,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    final target = elementType == 'balance'
        ? SlotDropZones.balanceDisplay()
        : SlotDropZones.winDisplay();

    return DropTargetWrapper(
      target: target,
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      glowColor: const Color(0xFFFFD700),
      onEventCreated: onEventCreated,
      child: child,
    );
  }
}

// =============================================================================
// DROPPABLE SYMBOL ZONE (B.9)
// =============================================================================

/// Symbol-specific drop zone for Wild, Scatter, HP, LP symbols
class DroppableSymbolZone extends StatelessWidget {
  final Widget child;
  final String symbolType; // 'wild', 'scatter', 'bonus', 'hp1'-'hp4', 'lp1'-'lp4'
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableSymbolZone({
    super.key,
    required this.child,
    required this.symbolType,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: SlotDropZones.symbolZone(symbolType),
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      glowColor: _getSymbolColor(symbolType),
      onEventCreated: onEventCreated,
      child: child,
    );
  }

  Color _getSymbolColor(String symbolType) {
    switch (symbolType.toLowerCase()) {
      case 'wild':
        return const Color(0xFFFFD700); // Gold
      case 'scatter':
        return const Color(0xFFE040FB); // Magenta
      case 'bonus':
        return const Color(0xFFFF9040); // Orange
      case 'hp1':
        return const Color(0xFFFF4060); // Red
      case 'hp2':
        return const Color(0xFF40C8FF); // Cyan
      case 'hp3':
        return const Color(0xFF40FF90); // Green
      case 'hp4':
        return const Color(0xFF8B5CF6); // Purple
      case 'lp1':
      case 'lp2':
      case 'lp3':
      case 'lp4':
        return const Color(0xFF6B7280); // Gray
      default:
        return FluxForgeTheme.accentBlue;
    }
  }
}

/// Convenience wrappers for common symbol types
class DroppableWildSymbol extends DroppableSymbolZone {
  const DroppableWildSymbol({
    super.key,
    required super.child,
    super.onEventCreated,
  }) : super(symbolType: 'wild');
}

class DroppableScatterSymbol extends DroppableSymbolZone {
  const DroppableScatterSymbol({
    super.key,
    required super.child,
    super.onEventCreated,
  }) : super(symbolType: 'scatter');
}

class DroppableBonusSymbol extends DroppableSymbolZone {
  const DroppableBonusSymbol({
    super.key,
    required super.child,
    super.onEventCreated,
  }) : super(symbolType: 'bonus');
}

// =============================================================================
// DROPPABLE MUSIC ZONE (B.10)
// =============================================================================

/// Background music drop zone for different game contexts
class DroppableMusicZone extends StatelessWidget {
  final Widget child;
  final String musicContext; // 'base', 'freespins', 'bonus', 'bigwin', 'anticipation'
  final void Function(CommittedEvent event)? onEventCreated;

  const DroppableMusicZone({
    super.key,
    required this.child,
    required this.musicContext,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DropTargetWrapper(
      target: SlotDropZones.backgroundMusic(musicContext),
      showBadge: true,
      badgeAlignment: Alignment.topRight,
      glowColor: _getMusicColor(musicContext),
      onEventCreated: onEventCreated,
      child: child,
    );
  }

  Color _getMusicColor(String context) {
    switch (context.toLowerCase()) {
      case 'base':
        return const Color(0xFF4A9EFF); // Blue
      case 'freespins':
        return const Color(0xFF40FF90); // Green
      case 'bonus':
        return const Color(0xFFFF9040); // Orange
      case 'bigwin':
        return const Color(0xFFFFD700); // Gold
      case 'anticipation':
        return const Color(0xFFE040FB); // Magenta
      default:
        return FluxForgeTheme.accentBlue;
    }
  }
}

/// Music zone panel with all context drop zones
class MusicZonePanel extends StatelessWidget {
  final void Function(String context, CommittedEvent event)? onMusicEventCreated;

  const MusicZonePanel({
    super.key,
    this.onMusicEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.music_note, size: 14, color: FluxForgeTheme.accentOrange),
              SizedBox(width: 6),
              Text(
                'Background Music',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MusicDropChip(
                label: 'Base Game',
                context: 'base',
                onEventCreated: onMusicEventCreated != null
                    ? (e) => onMusicEventCreated!('base', e)
                    : null,
              ),
              _MusicDropChip(
                label: 'Free Spins',
                context: 'freespins',
                onEventCreated: onMusicEventCreated != null
                    ? (e) => onMusicEventCreated!('freespins', e)
                    : null,
              ),
              _MusicDropChip(
                label: 'Bonus',
                context: 'bonus',
                onEventCreated: onMusicEventCreated != null
                    ? (e) => onMusicEventCreated!('bonus', e)
                    : null,
              ),
              _MusicDropChip(
                label: 'Big Win',
                context: 'bigwin',
                onEventCreated: onMusicEventCreated != null
                    ? (e) => onMusicEventCreated!('bigwin', e)
                    : null,
              ),
              _MusicDropChip(
                label: 'Anticipation',
                context: 'anticipation',
                onEventCreated: onMusicEventCreated != null
                    ? (e) => onMusicEventCreated!('anticipation', e)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MusicDropChip extends StatelessWidget {
  final String label;
  final String context;
  final void Function(CommittedEvent event)? onEventCreated;

  const _MusicDropChip({
    required this.label,
    required this.context,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context_) {
    return DroppableMusicZone(
      musicContext: context,
      onEventCreated: onEventCreated,
      child: Consumer<AutoEventBuilderProvider>(
        builder: (ctx, provider, _) {
          final count = provider.getEventCountForTarget('music.$context');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: count > 0
                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
                    : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_note,
                  size: 12,
                  color: count > 0 ? FluxForgeTheme.accentGreen : FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: count > 0 ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: count > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: FluxForgeTheme.accentGreen,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// SYMBOL GRID PANEL
// =============================================================================

/// Symbol type drop zone grid
class SymbolZonePanel extends StatelessWidget {
  final void Function(String symbolType, CommittedEvent event)? onSymbolEventCreated;

  const SymbolZonePanel({
    super.key,
    this.onSymbolEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.apps, size: 14, color: FluxForgeTheme.accentCyan),
              SizedBox(width: 6),
              Text(
                'Symbol Audio',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Special Symbols Row
          Row(
            children: [
              _SymbolDropChip(
                label: 'Wild',
                symbolType: 'wild',
                icon: Icons.star,
                color: const Color(0xFFFFD700),
                onEventCreated: onSymbolEventCreated != null
                    ? (e) => onSymbolEventCreated!('wild', e)
                    : null,
              ),
              const SizedBox(width: 6),
              _SymbolDropChip(
                label: 'Scatter',
                symbolType: 'scatter',
                icon: Icons.scatter_plot,
                color: const Color(0xFFE040FB),
                onEventCreated: onSymbolEventCreated != null
                    ? (e) => onSymbolEventCreated!('scatter', e)
                    : null,
              ),
              const SizedBox(width: 6),
              _SymbolDropChip(
                label: 'Bonus',
                symbolType: 'bonus',
                icon: Icons.card_giftcard,
                color: const Color(0xFFFF9040),
                onEventCreated: onSymbolEventCreated != null
                    ? (e) => onSymbolEventCreated!('bonus', e)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // High Pay Row
          Row(
            children: [
              for (int i = 1; i <= 4; i++) ...[
                _SymbolDropChip(
                  label: 'HP$i',
                  symbolType: 'hp$i',
                  icon: Icons.diamond,
                  color: _getHpColor(i),
                  onEventCreated: onSymbolEventCreated != null
                      ? (e) => onSymbolEventCreated!('hp$i', e)
                      : null,
                ),
                if (i < 4) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Low Pay Row
          Row(
            children: [
              for (int i = 1; i <= 4; i++) ...[
                _SymbolDropChip(
                  label: 'LP$i',
                  symbolType: 'lp$i',
                  icon: Icons.casino,
                  color: const Color(0xFF6B7280),
                  onEventCreated: onSymbolEventCreated != null
                      ? (e) => onSymbolEventCreated!('lp$i', e)
                      : null,
                ),
                if (i < 4) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _getHpColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFF4060);
      case 2: return const Color(0xFF40C8FF);
      case 3: return const Color(0xFF40FF90);
      case 4: return const Color(0xFF8B5CF6);
      default: return FluxForgeTheme.accentBlue;
    }
  }
}

class _SymbolDropChip extends StatelessWidget {
  final String label;
  final String symbolType;
  final IconData icon;
  final Color color;
  final void Function(CommittedEvent event)? onEventCreated;

  const _SymbolDropChip({
    required this.label,
    required this.symbolType,
    required this.icon,
    required this.color,
    this.onEventCreated,
  });

  @override
  Widget build(BuildContext context) {
    return DroppableSymbolZone(
      symbolType: symbolType,
      onEventCreated: onEventCreated,
      child: Consumer<AutoEventBuilderProvider>(
        builder: (ctx, provider, _) {
          final count = provider.getEventCountForTarget('symbol.$symbolType');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: count > 0 ? color.withValues(alpha: 0.6) : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: count > 0 ? color : FluxForgeTheme.textMuted,
                    fontSize: 10,
                    fontWeight: count > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 3),
                  Text(
                    '($count)',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 8,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// INTEGRATION HELPER
// =============================================================================

/// Helper widget that shows drop zone indicators in edit mode
class DropZoneIndicator extends StatelessWidget {
  final String label;
  final String targetId;
  final bool isActive;
  final Color color;

  const DropZoneIndicator({
    super.key,
    required this.label,
    required this.targetId,
    this.isActive = false,
    this.color = FluxForgeTheme.accentBlue,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.add_circle_outline,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EVENT COUNT SUMMARY
// =============================================================================

/// Shows summary of events assigned to all slot preview drop zones
class SlotDropZoneSummary extends StatelessWidget {
  const SlotDropZoneSummary({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final counts = <String, int>{
          'Spin': provider.getEventCountForTarget('ui.spin'),
          'Auto': provider.getEventCountForTarget('ui.autospin'),
          'Turbo': provider.getEventCountForTarget('ui.turbo'),
          'Reels': _sumReelCounts(provider),
          'Wins': _sumWinCounts(provider),
          'Jackpots': _sumJackpotCounts(provider),
        };

        final total = counts.values.fold(0, (a, b) => a + b);
        if (total == 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note,
                size: 14,
                color: FluxForgeTheme.accentBlue,
              ),
              const SizedBox(width: 6),
              Text(
                '$total events',
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              ...counts.entries
                  .where((e) => e.value > 0)
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgMid,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${e.key}: ${e.value}',
                            style: TextStyle(
                              color: FluxForgeTheme.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      )),
            ],
          ),
        );
      },
    );
  }

  int _sumReelCounts(AutoEventBuilderProvider provider) {
    int sum = provider.getEventCountForTarget('reel.surface');
    for (int i = 0; i < 5; i++) {
      sum += provider.getEventCountForTarget('reel.$i');
    }
    return sum;
  }

  int _sumWinCounts(AutoEventBuilderProvider provider) {
    int sum = 0;
    for (final tier in ['small', 'big', 'mega', 'epic', 'ultra']) {
      sum += provider.getEventCountForTarget('overlay.win.$tier');
    }
    return sum;
  }

  int _sumJackpotCounts(AutoEventBuilderProvider provider) {
    int sum = 0;
    for (final tier in ['mini', 'minor', 'major', 'grand']) {
      sum += provider.getEventCountForTarget('overlay.jackpot.$tier');
    }
    return sum;
  }
}
