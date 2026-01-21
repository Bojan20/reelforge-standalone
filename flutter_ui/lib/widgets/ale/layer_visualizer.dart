/// Layer Visualizer Widget
///
/// Visual representation of ALE audio layers with volume levels.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';

/// Visual representation of audio layers
class LayerVisualizer extends StatelessWidget {
  final bool showLabels;
  final bool interactive;
  final double height;
  final Axis direction;

  const LayerVisualizer({
    super.key,
    this.showLabels = true,
    this.interactive = true,
    this.height = 200,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        final activeContext = ale.activeContext;
        if (activeContext == null) {
          return _buildEmptyState();
        }

        final layers = activeContext.layers;
        final volumes = ale.layerVolumes;
        final currentLevel = ale.currentLevel;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(activeContext.name, currentLevel, layers.length),

              // Layers
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: direction == Axis.horizontal
                      ? _buildHorizontalLayers(layers, volumes, currentLevel, ale)
                      : _buildVerticalLayers(layers, volumes, currentLevel, ale),
                ),
              ),

              // Level indicator
              _buildLevelIndicator(currentLevel, layers.length, ale),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2a2a35)),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_clear, color: Color(0xFF666666), size: 32),
            SizedBox(height: 8),
            Text(
              'No active context',
              style: TextStyle(color: Color(0xFF666666), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String contextName, int level, int layerCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers, color: Color(0xFF4a9eff), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              contextName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'L${level + 1}/$layerCount',
              style: const TextStyle(
                color: Color(0xFF4a9eff),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalLayers(
    List<AleLayer> layers,
    List<double> volumes,
    int currentLevel,
    AleProvider ale,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(layers.length, (index) {
        final layer = layers[index];
        final volume = index < volumes.length ? volumes[index] : 0.0;
        final isActive = index <= currentLevel;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _LayerBar(
              index: index,
              assetId: layer.assetId,
              volume: volume,
              isActive: isActive,
              isCurrent: index == currentLevel,
              showLabel: showLabels,
              onTap: interactive
                  ? () => ale.setLevel(index)
                  : null,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildVerticalLayers(
    List<AleLayer> layers,
    List<double> volumes,
    int currentLevel,
    AleProvider ale,
  ) {
    return Column(
      children: List.generate(layers.length, (index) {
        final layer = layers[index];
        final volume = index < volumes.length ? volumes[index] : 0.0;
        final isActive = index <= currentLevel;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _LayerRow(
              index: index,
              assetId: layer.assetId,
              volume: volume,
              isActive: isActive,
              isCurrent: index == currentLevel,
              showLabel: showLabels,
              onTap: interactive
                  ? () => ale.setLevel(index)
                  : null,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLevelIndicator(int currentLevel, int layerCount, AleProvider ale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Step down button
          if (interactive)
            _LevelButton(
              icon: Icons.remove,
              onPressed: currentLevel > 0 ? () => ale.stepDown() : null,
            ),

          // Level dots
          const SizedBox(width: 12),
          ...List.generate(layerCount, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: index == currentLevel ? 12 : 8,
                height: index == currentLevel ? 12 : 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index <= currentLevel
                      ? _getLevelColor(index, layerCount)
                      : const Color(0xFF3a3a45),
                  border: index == currentLevel
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: index == currentLevel
                      ? [
                          BoxShadow(
                            color: _getLevelColor(index, layerCount)
                                .withValues(alpha: 0.5),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
              ),
            );
          }),
          const SizedBox(width: 12),

          // Step up button
          if (interactive)
            _LevelButton(
              icon: Icons.add,
              onPressed: currentLevel < layerCount - 1 ? () => ale.stepUp() : null,
            ),
        ],
      ),
    );
  }

  Color _getLevelColor(int level, int maxLevel) {
    if (maxLevel <= 1) return const Color(0xFF4a9eff);

    final t = level / (maxLevel - 1);
    // Gradient from blue to orange to red
    if (t < 0.5) {
      return Color.lerp(
        const Color(0xFF4a9eff),
        const Color(0xFFff9040),
        t * 2,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFff9040),
        const Color(0xFFff4060),
        (t - 0.5) * 2,
      )!;
    }
  }
}

/// Vertical layer bar widget
class _LayerBar extends StatelessWidget {
  final int index;
  final String assetId;
  final double volume;
  final bool isActive;
  final bool isCurrent;
  final bool showLabel;
  final VoidCallback? onTap;

  const _LayerBar({
    required this.index,
    required this.assetId,
    required this.volume,
    required this.isActive,
    required this.isCurrent,
    this.showLabel = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Volume value
          if (showLabel)
            Text(
              '${(volume * 100).toInt()}%',
              style: TextStyle(
                color: isActive ? color : const Color(0xFF666666),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),

          const SizedBox(height: 4),

          // Bar
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF2a2a35),
                border: isCurrent
                    ? Border.all(color: color, width: 2)
                    : null,
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Volume fill
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 150),
                    heightFactor: volume.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            color.withValues(alpha: 0.8),
                            color,
                          ],
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),

                  // Peak indicator
                  if (volume > 0.9)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: const Color(0xFFff4060),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Layer number
          if (showLabel)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isCurrent
                    ? color.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'L${index + 1}',
                style: TextStyle(
                  color: isActive ? color : const Color(0xFF666666),
                  fontSize: 10,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getColor() {
    if (!isActive) return const Color(0xFF666666);

    // Level-based color
    const colors = [
      Color(0xFF4a9eff), // L1 - blue
      Color(0xFF40c8ff), // L2 - cyan
      Color(0xFF40ff90), // L3 - green
      Color(0xFFffff40), // L4 - yellow
      Color(0xFFff9040), // L5 - orange
      Color(0xFFff4060), // L6+ - red
    ];

    return colors[math.min(index, colors.length - 1)];
  }
}

/// Horizontal layer row widget
class _LayerRow extends StatelessWidget {
  final int index;
  final String assetId;
  final double volume;
  final bool isActive;
  final bool isCurrent;
  final bool showLabel;
  final VoidCallback? onTap;

  const _LayerRow({
    required this.index,
    required this.assetId,
    required this.volume,
    required this.isActive,
    required this.isCurrent,
    this.showLabel = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCurrent
              ? color.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isCurrent
              ? Border.all(color: color.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          children: [
            // Layer number
            if (showLabel)
              SizedBox(
                width: 30,
                child: Text(
                  'L${index + 1}',
                  style: TextStyle(
                    color: isActive ? color : const Color(0xFF666666),
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),

            // Volume bar
            Expanded(
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF2a2a35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  children: [
                    AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 150),
                      widthFactor: volume.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            colors: [color.withValues(alpha: 0.8), color],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Volume value
            if (showLabel)
              SizedBox(
                width: 40,
                child: Text(
                  '${(volume * 100).toInt()}%',
                  style: TextStyle(
                    color: isActive ? color : const Color(0xFF666666),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getColor() {
    if (!isActive) return const Color(0xFF666666);

    const colors = [
      Color(0xFF4a9eff),
      Color(0xFF40c8ff),
      Color(0xFF40ff90),
      Color(0xFFffff40),
      Color(0xFFff9040),
      Color(0xFFff4060),
    ];

    return colors[math.min(index, colors.length - 1)];
  }
}

/// Level control button
class _LevelButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _LevelButton({
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onPressed != null
          ? const Color(0xFF2a2a35)
          : const Color(0xFF1a1a20),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: onPressed != null
                ? const Color(0xFF4a9eff)
                : const Color(0xFF444444),
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// Animated fractionally sized box
class AnimatedFractionallySizedBox extends StatelessWidget {
  final Duration duration;
  final double? widthFactor;
  final double? heightFactor;
  final Widget child;

  const AnimatedFractionallySizedBox({
    super.key,
    required this.duration,
    this.widthFactor,
    this.heightFactor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      tween: Tween(begin: 0, end: widthFactor ?? heightFactor ?? 1),
      builder: (context, value, child) {
        return FractionallySizedBox(
          widthFactor: widthFactor != null ? value : null,
          heightFactor: heightFactor != null ? value : null,
          child: child,
        );
      },
      child: child,
    );
  }
}
