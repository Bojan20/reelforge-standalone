/// Drop Target Wrapper — Visual Feedback for Auto Event Builder
///
/// Wraps any SlotLab UI element to make it a drop target for audio assets.
/// Provides visual feedback:
/// - Hover glow when dragging over
/// - Pulse animation on valid drop
/// - Event count badge
/// - Target type indicator
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 15.4
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../theme/fluxforge_theme.dart';
import 'quick_sheet.dart';

/// Wrapper widget that adds drop target functionality to any child
class DropTargetWrapper extends StatefulWidget {
  /// The child widget to wrap
  final Widget child;

  /// Drop target configuration
  final DropTarget target;

  /// Whether to show the event count badge
  final bool showBadge;

  /// Badge position
  final Alignment badgeAlignment;

  /// Custom glow color (defaults to target type color)
  final Color? glowColor;

  /// Called when an asset is dropped and committed
  final void Function(CommittedEvent event)? onEventCreated;

  const DropTargetWrapper({
    super.key,
    required this.child,
    required this.target,
    this.showBadge = true,
    this.badgeAlignment = Alignment.topRight,
    this.glowColor,
    this.onEventCreated,
  });

  @override
  State<DropTargetWrapper> createState() => _DropTargetWrapperState();
}

class _DropTargetWrapperState extends State<DropTargetWrapper>
    with SingleTickerProviderStateMixin {
  bool _isDragOver = false;
  bool _showPulse = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutCubic),
    );
    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        setState(() => _showPulse = false);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _targetColor {
    if (widget.glowColor != null) return widget.glowColor!;

    switch (widget.target.targetType) {
      case TargetType.uiButton:
      case TargetType.uiToggle:
        return FluxForgeTheme.accentBlue;
      case TargetType.reelSurface:
      case TargetType.reelStopZone:
        return FluxForgeTheme.accentOrange;
      case TargetType.symbol:
        return FluxForgeTheme.accentGreen;
      case TargetType.overlay:
      case TargetType.featureContainer:
        return FluxForgeTheme.accentCyan;
      case TargetType.hudCounter:
      case TargetType.hudMeter:
        return const Color(0xFFFFD700); // Gold
      case TargetType.screenZone:
        return FluxForgeTheme.textSecondary;
    }
  }

  void _triggerPulse() {
    setState(() => _showPulse = true);
    _pulseController.forward(from: 0);
  }

  void _handleDrop(AudioAsset asset, Offset globalPosition) {
    final provider = context.read<AutoEventBuilderProvider>();

    // Create draft
    provider.createDraft(asset, widget.target);

    // Show QuickSheet popup
    showQuickSheet(
      context: context,
      asset: asset,
      target: widget.target,
      position: globalPosition,
      onCommit: () {
        final event = provider.commitDraft();
        if (event != null) {
          _triggerPulse();
          widget.onEventCreated?.call(event);
        }
      },
      onCancel: provider.cancelDraft,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final eventCount = provider.getEventCountForTarget(widget.target.targetId);

        return DragTarget<AudioAsset>(
          onWillAcceptWithDetails: (details) {
            setState(() => _isDragOver = true);
            return true;
          },
          onLeave: (_) {
            setState(() => _isDragOver = false);
          },
          onAcceptWithDetails: (details) {
            setState(() => _isDragOver = false);
            _handleDrop(details.data, details.offset);
          },
          builder: (context, candidateData, rejectedData) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Main content with glow effect
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _showPulse ? _pulseAnimation.value : 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _isDragOver
                              ? [
                                  BoxShadow(
                                    color: _targetColor.withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: _targetColor.withValues(alpha: 0.2),
                                    blurRadius: 32,
                                    spreadRadius: 4,
                                  ),
                                ]
                              : _showPulse
                                  ? [
                                      BoxShadow(
                                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5),
                                        blurRadius: 20,
                                        spreadRadius: 3,
                                      ),
                                    ]
                                  : null,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: _isDragOver
                          ? Border.all(
                              color: _targetColor.withValues(alpha: 0.8),
                              width: 2,
                            )
                          : null,
                    ),
                    child: widget.child,
                  ),
                ),

                // Drop indicator overlay
                if (_isDragOver)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: _targetColor.withValues(alpha: 0.1),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                size: 32,
                                color: _targetColor.withValues(alpha: 0.8),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: FluxForgeTheme.bgDeep.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Drop to create event',
                                  style: TextStyle(
                                    color: _targetColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Event count badge
                if (widget.showBadge && eventCount > 0)
                  Positioned(
                    top: widget.badgeAlignment == Alignment.topRight ||
                            widget.badgeAlignment == Alignment.topLeft
                        ? -6
                        : null,
                    bottom: widget.badgeAlignment == Alignment.bottomRight ||
                            widget.badgeAlignment == Alignment.bottomLeft
                        ? -6
                        : null,
                    right: widget.badgeAlignment == Alignment.topRight ||
                            widget.badgeAlignment == Alignment.bottomRight
                        ? -6
                        : null,
                    left: widget.badgeAlignment == Alignment.topLeft ||
                            widget.badgeAlignment == Alignment.bottomLeft
                        ? -6
                        : null,
                    child: _EventCountBadge(
                      count: eventCount,
                      color: _targetColor,
                    ),
                  ),

                // Target type indicator (subtle)
                if (_isDragOver)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: _targetColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        widget.target.targetType.displayName,
                        style: TextStyle(
                          color: _targetColor.withValues(alpha: 0.8),
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// EVENT COUNT BADGE
// =============================================================================

class _EventCountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _EventCountBadge({
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          count > 99 ? '99+' : count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DRAGGABLE AUDIO ASSET
// =============================================================================

/// Draggable wrapper for audio assets (use in Browser)
class DraggableAudioAsset extends StatelessWidget {
  final Widget child;
  final AudioAsset asset;
  final Widget? feedback;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  const DraggableAudioAsset({
    super.key,
    required this.child,
    required this.asset,
    this.feedback,
    this.onDragStarted,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<AudioAsset>(
      data: asset,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd?.call(),
      feedback: feedback ?? _DefaultDragFeedback(asset: asset),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: child,
      ),
      child: child,
    );
  }
}

class _DefaultDragFeedback extends StatelessWidget {
  final AudioAsset asset;

  const _DefaultDragFeedback({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _getAssetColor(asset.assetType).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getAssetIcon(asset.assetType),
              size: 16,
              color: _getAssetColor(asset.assetType),
            ),
            const SizedBox(width: 8),
            Text(
              asset.displayName,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getAssetIcon(AssetType type) {
    switch (type) {
      case AssetType.sfx:
        return Icons.surround_sound;
      case AssetType.music:
        return Icons.music_note;
      case AssetType.vo:
        return Icons.mic;
      case AssetType.amb:
        return Icons.waves;
    }
  }

  Color _getAssetColor(AssetType type) {
    switch (type) {
      case AssetType.sfx:
        return FluxForgeTheme.accentBlue;
      case AssetType.music:
        return FluxForgeTheme.accentOrange;
      case AssetType.vo:
        return FluxForgeTheme.accentGreen;
      case AssetType.amb:
        return FluxForgeTheme.accentCyan;
    }
  }
}

// =============================================================================
// PREDEFINED DROP TARGETS
// =============================================================================

/// Factory for creating common SlotLab drop targets
class SlotLabDropTargets {
  /// Spin button target
  static DropTarget spinButton({StageContext context = StageContext.global}) =>
      DropTarget(
        targetId: 'ui.spin',
        targetType: TargetType.uiButton,
        targetTags: const ['primary', 'cta', 'spin'],
        stageContext: context,
        interactionSemantics: const ['press', 'release', 'hover'],
      );

  /// Auto-spin button target
  static DropTarget autoSpinButton({StageContext context = StageContext.global}) =>
      DropTarget(
        targetId: 'ui.autospin',
        targetType: TargetType.uiButton,
        targetTags: const ['secondary', 'autospin'],
        stageContext: context,
        interactionSemantics: const ['press', 'toggle_on', 'toggle_off'],
      );

  /// Reel surface target (entire reel area)
  static DropTarget reelSurface({StageContext context = StageContext.global}) =>
      DropTarget(
        targetId: 'reel.surface',
        targetType: TargetType.reelSurface,
        targetTags: const ['reel', 'main'],
        stageContext: context,
        interactionSemantics: const ['spin_start', 'spin_stop'],
      );

  /// Individual reel stop zone
  static DropTarget reelStopZone(int reelIndex, {StageContext context = StageContext.global}) =>
      DropTarget(
        targetId: 'reel.$reelIndex',
        targetType: TargetType.reelStopZone,
        targetTags: ['reel', 'stop', 'reel_$reelIndex'],
        stageContext: context,
        interactionSemantics: const ['reel_stop', 'anticipation_on', 'anticipation_off'],
      );

  /// Win display overlay
  static DropTarget winDisplay({
    String tier = 'small',
    StageContext context = StageContext.global,
  }) =>
      DropTarget(
        targetId: 'overlay.win.$tier',
        targetType: TargetType.overlay,
        targetTags: ['win', tier, 'celebration'],
        stageContext: context,
        interactionSemantics: const ['show', 'hide', 'pulse', 'tier_up'],
      );

  /// Feature trigger area
  static DropTarget featureTrigger(String featureName, {StageContext context = StageContext.global}) =>
      DropTarget(
        targetId: 'feature.$featureName.trigger',
        targetType: TargetType.featureContainer,
        targetTags: ['feature', featureName, 'trigger'],
        stageContext: context,
        interactionSemantics: const ['enter', 'exit', 'trigger'],
      );

  /// Balance/bet counter
  static DropTarget balanceCounter({StageContext context = StageContext.global}) =>
      DropTarget(
        targetId: 'hud.balance',
        targetType: TargetType.hudCounter,
        targetTags: const ['balance', 'counter', 'hud'],
        stageContext: context,
        interactionSemantics: const ['value_change', 'increment', 'decrement'],
      );

  /// Generic UI button
  static DropTarget uiButton(String buttonId, {
    List<String> tags = const [],
    StageContext context = StageContext.global,
  }) =>
      DropTarget(
        targetId: 'ui.$buttonId',
        targetType: TargetType.uiButton,
        targetTags: ['button', ...tags],
        stageContext: context,
      );
}
