/// Container Visualization Widgets
///
/// Enhanced visualization components for Blend, Random, and Sequence containers.
/// Part of P3.5: Container visualization improvements.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/middleware_models.dart';
import '../../services/event_registry.dart' show ContainerType;
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BLEND CONTAINER VISUALIZATION
// ═══════════════════════════════════════════════════════════════════════════

/// Interactive RTPC slider with real-time blend preview
class BlendRtpcSlider extends StatefulWidget {
  final BlendContainer container;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onPreview;

  const BlendRtpcSlider({
    super.key,
    required this.container,
    required this.value,
    required this.onChanged,
    this.onPreview,
  });

  @override
  State<BlendRtpcSlider> createState() => _BlendRtpcSliderState();
}

class _BlendRtpcSliderState extends State<BlendRtpcSlider> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 16, color: Colors.purple),
              const SizedBox(width: 8),
              Text(
                'RTPC Preview',
                style: TextStyle(
                  color: Colors.purple,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                widget.value.toStringAsFixed(2),
                style: TextStyle(
                  color: Colors.purple,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Slider with child range indicators
          SizedBox(
            height: 40,
            child: Stack(
              children: [
                // Child range backgrounds
                ...widget.container.children.map((child) {
                  final start = child.rtpcStart.clamp(0.0, 1.0);
                  final end = child.rtpcEnd.clamp(0.0, 1.0);
                  return Positioned(
                    left: start * (MediaQuery.of(context).size.width - 80),
                    width: (end - start) * (MediaQuery.of(context).size.width - 80),
                    top: 8,
                    bottom: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
                // Slider
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      activeTrackColor: Colors.purple,
                      inactiveTrackColor: FluxForgeTheme.border,
                      thumbColor: Colors.purple,
                      overlayColor: Colors.purple.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: widget.value,
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Current volumes per child
          _buildChildVolumeMeters(),
          if (widget.onPreview != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: widget.onPreview,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purple),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 16, color: Colors.purple),
                    const SizedBox(width: 4),
                    Text(
                      'Preview Blend',
                      style: TextStyle(color: Colors.purple, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChildVolumeMeters() {
    final children = widget.container.children;
    if (children.isEmpty) return const SizedBox.shrink();

    return Row(
      children: children.map((child) {
        // Calculate volume based on RTPC position
        final volume = _calculateChildVolume(child, widget.value);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Text(
                  child.name,
                  style: TextStyle(
                    color: volume > 0.1 ? Colors.purple : FluxForgeTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: volume > 0.5 ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Volume bar
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: volume,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.withValues(alpha: 0.5),
                            Colors.purple,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(volume * 100).toInt()}%',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 8,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  double _calculateChildVolume(BlendChild child, double rtpcValue) {
    if (rtpcValue < child.rtpcStart || rtpcValue > child.rtpcEnd) {
      return 0.0;
    }
    // Simple linear crossfade within range
    final range = child.rtpcEnd - child.rtpcStart;
    if (range <= 0) return 1.0;

    final position = (rtpcValue - child.rtpcStart) / range;
    // Bell curve-ish: full volume in middle, fade at edges
    final fade = 1.0 - (2 * position - 1).abs();
    return fade;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RANDOM CONTAINER VISUALIZATION
// ═══════════════════════════════════════════════════════════════════════════

/// Pie chart showing weight distribution
class RandomWeightPieChart extends StatelessWidget {
  final RandomContainer container;
  final int? selectedChildId;
  final ValueChanged<int?>? onChildSelected;

  const RandomWeightPieChart({
    super.key,
    required this.container,
    this.selectedChildId,
    this.onChildSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (container.children.isEmpty) {
      return Center(
        child: Text(
          'No children',
          style: TextStyle(color: FluxForgeTheme.textSecondary),
        ),
      );
    }

    final totalWeight = container.children.fold<double>(0, (sum, c) => sum + c.weight);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _PieChartPainter(
                children: container.children,
                totalWeight: totalWeight,
                selectedChildId: selectedChildId,
              ),
              child: GestureDetector(
                onTapDown: (details) {
                  if (onChildSelected == null) return;
                  final center = Offset(size / 2, size / 2);
                  final position = details.localPosition - center;
                  final angle = (math.atan2(position.dy, position.dx) + math.pi / 2) % (2 * math.pi);

                  // Find which child was tapped
                  double currentAngle = 0;
                  for (final child in container.children) {
                    final sweepAngle = (child.weight / totalWeight) * 2 * math.pi;
                    if (angle >= currentAngle && angle < currentAngle + sweepAngle) {
                      onChildSelected!(child.id);
                      return;
                    }
                    currentAngle += sweepAngle;
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<RandomChild> children;
  final double totalWeight;
  final int? selectedChildId;

  static const _colors = [
    Color(0xFFFF9040),
    Color(0xFF40C8FF),
    Color(0xFF40FF90),
    Color(0xFFFF4060),
    Color(0xFFE040FB),
    Color(0xFFFFD700),
    Color(0xFF00CED1),
    Color(0xFFFF69B4),
  ];

  _PieChartPainter({
    required this.children,
    required this.totalWeight,
    this.selectedChildId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;

    double startAngle = -math.pi / 2;

    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final sweepAngle = (child.weight / totalWeight) * 2 * math.pi;
      final color = _colors[i % _colors.length];
      final isSelected = child.id == selectedChildId;

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = isSelected ? color : color.withValues(alpha: 0.7);

      final actualRadius = isSelected ? radius + 5 : radius;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: actualRadius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      // Border
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = isSelected ? Colors.white : Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = isSelected ? 2 : 1;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: actualRadius),
        startAngle,
        sweepAngle,
        true,
        borderPaint,
      );

      // Label
      final labelAngle = startAngle + sweepAngle / 2;
      final labelRadius = radius * 0.6;
      final labelPosition = Offset(
        center.dx + math.cos(labelAngle) * labelRadius,
        center.dy + math.sin(labelAngle) * labelRadius,
      );

      final percentage = (child.weight / totalWeight * 100).toInt();
      if (percentage > 5) { // Only show label if > 5%
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$percentage%',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 2),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          labelPosition - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.children != children ||
           oldDelegate.selectedChildId != selectedChildId;
  }
}

/// Selection history visualization
class RandomSelectionHistory extends StatelessWidget {
  final List<int> history; // List of child IDs in order of selection
  final RandomContainer container;

  const RandomSelectionHistory({
    super.key,
    required this.history,
    required this.container,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'No selection history',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                'Recent Selections',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: history.reversed.take(10).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final childId = entry.value;
              final child = container.children.where((c) => c.id == childId).firstOrNull;
              final opacity = 1.0 - (index * 0.08);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1 * opacity),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3 * opacity),
                  ),
                ),
                child: Text(
                  child?.name ?? 'Unknown',
                  style: TextStyle(
                    color: Colors.amber.withValues(alpha: opacity),
                    fontSize: 9,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SEQUENCE CONTAINER VISUALIZATION
// ═══════════════════════════════════════════════════════════════════════════

/// Enhanced sequence timeline with waveform previews
class SequenceTimelineVisualization extends StatelessWidget {
  final SequenceContainer container;
  final int? currentStepIndex;
  final int? selectedStepIndex;
  final ValueChanged<int?>? onStepSelected;
  final bool isPlaying;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;

  const SequenceTimelineVisualization({
    super.key,
    required this.container,
    this.currentStepIndex,
    this.selectedStepIndex,
    this.onStepSelected,
    this.isPlaying = false,
    this.onPlay,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final totalDuration = _calculateTotalDuration();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Control bar
        Row(
          children: [
            // Play/Stop button
            GestureDetector(
              onTap: isPlaying ? onStop : onPlay,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.teal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isPlaying ? Colors.red : Colors.teal,
                  ),
                ),
                child: Icon(
                  isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 16,
                  color: isPlaying ? Colors.red : Colors.teal,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Total duration
            Text(
              'Duration: ${_formatDuration(totalDuration)}',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${container.steps.length} steps',
              style: TextStyle(
                color: Colors.teal,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // End behavior indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getEndBehaviorColor().withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getEndBehaviorIcon(),
                    size: 12,
                    color: _getEndBehaviorColor(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    container.endBehavior.displayName,
                    style: TextStyle(
                      color: _getEndBehaviorColor(),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Timeline
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FluxForgeTheme.border),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (container.steps.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.queue_music, size: 32, color: FluxForgeTheme.textSecondary),
                        const SizedBox(height: 8),
                        Text(
                          'No steps in sequence',
                          style: TextStyle(color: FluxForgeTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: _SequenceTimelinePainter(
                      steps: container.steps,
                      totalDuration: totalDuration,
                      currentStepIndex: currentStepIndex,
                      selectedStepIndex: selectedStepIndex,
                    ),
                    child: GestureDetector(
                      onTapDown: (details) {
                        if (onStepSelected == null) return;
                        // Calculate which step was tapped
                        final stepIndex = _hitTestStep(
                          details.localPosition,
                          constraints.maxWidth,
                          constraints.maxHeight,
                          totalDuration,
                        );
                        onStepSelected!(stepIndex);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  double _calculateTotalDuration() {
    double total = 0;
    for (final step in container.steps) {
      // Convert from ms to seconds
      final delay = step.delayMs / 1000;
      final duration = step.durationMs / 1000;
      total = math.max(total, delay + duration);
    }
    return total;
  }

  String _formatDuration(double seconds) {
    if (seconds < 1) {
      return '${(seconds * 1000).toInt()}ms';
    }
    return '${seconds.toStringAsFixed(2)}s';
  }

  Color _getEndBehaviorColor() {
    return switch (container.endBehavior) {
      SequenceEndBehavior.stop => Colors.red,
      SequenceEndBehavior.loop => Colors.teal,
      SequenceEndBehavior.holdLast => Colors.orange,
      SequenceEndBehavior.pingPong => Colors.purple,
    };
  }

  IconData _getEndBehaviorIcon() {
    return switch (container.endBehavior) {
      SequenceEndBehavior.stop => Icons.stop,
      SequenceEndBehavior.loop => Icons.loop,
      SequenceEndBehavior.holdLast => Icons.pause,
      SequenceEndBehavior.pingPong => Icons.swap_horiz,
    };
  }

  int? _hitTestStep(Offset position, double width, double height, double totalDuration) {
    if (totalDuration <= 0) return null;

    final stepHeight = height / math.max(container.steps.length, 1);
    final stepIndex = (position.dy / stepHeight).floor();

    if (stepIndex >= 0 && stepIndex < container.steps.length) {
      return stepIndex;
    }
    return null;
  }
}

class _SequenceTimelinePainter extends CustomPainter {
  final List<SequenceStep> steps;
  final double totalDuration;
  final int? currentStepIndex;
  final int? selectedStepIndex;

  static const _stepColors = [
    Color(0xFF40C8FF),
    Color(0xFF40FF90),
    Color(0xFFFF9040),
    Color(0xFFE040FB),
    Color(0xFFFFD700),
    Color(0xFF00CED1),
    Color(0xFFFF69B4),
    Color(0xFF98FB98),
  ];

  _SequenceTimelinePainter({
    required this.steps,
    required this.totalDuration,
    this.currentStepIndex,
    this.selectedStepIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty || totalDuration <= 0) return;

    final stepHeight = size.height / steps.length;
    final pixelsPerSecond = size.width / totalDuration;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final y = i * stepHeight;
      // Convert from ms to seconds
      final delay = step.delayMs / 1000;
      final duration = step.durationMs / 1000;
      final x = delay * pixelsPerSecond;
      final width = duration * pixelsPerSecond;

      final color = _stepColors[i % _stepColors.length];
      final isSelected = i == selectedStepIndex;
      final isCurrent = i == currentStepIndex;

      // Step background
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2, y + 2, width - 4, stepHeight - 4),
        const Radius.circular(4),
      );

      final bgPaint = Paint()
        ..color = color.withValues(alpha: isCurrent ? 0.5 : 0.3);
      canvas.drawRRect(bgRect, bgPaint);

      // Border
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = isSelected ? Colors.white : color
        ..strokeWidth = isSelected ? 2 : 1;
      canvas.drawRRect(bgRect, borderPaint);

      // Step name
      final textPainter = TextPainter(
        text: TextSpan(
          text: step.childName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: width - 8);

      textPainter.paint(
        canvas,
        Offset(x + 6, y + (stepHeight - textPainter.height) / 2),
      );

      // Duration label on right
      final durationPainter = TextPainter(
        text: TextSpan(
          text: '${duration.toStringAsFixed(1)}s',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 8,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      if (width > durationPainter.width + textPainter.width + 20) {
        durationPainter.paint(
          canvas,
          Offset(x + width - durationPainter.width - 6, y + (stepHeight - durationPainter.height) / 2),
        );
      }
    }

    // Grid lines (every 0.5s)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    for (var t = 0.5; t < totalDuration; t += 0.5) {
      final x = t * pixelsPerSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SequenceTimelinePainter oldDelegate) {
    return oldDelegate.steps != steps ||
           oldDelegate.currentStepIndex != currentStepIndex ||
           oldDelegate.selectedStepIndex != selectedStepIndex;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMMON VISUALIZATION HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Container type badge
class ContainerTypeBadge extends StatelessWidget {
  final ContainerType type;
  final bool compact;

  const ContainerTypeBadge({
    super.key,
    required this.type,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final icon = _getIcon();
    final label = _getLabel();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 10 : 12, color: color),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: compact ? 8 : 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getColor() {
    return switch (type) {
      ContainerType.none => FluxForgeTheme.textSecondary,
      ContainerType.blend => Colors.purple,
      ContainerType.random => Colors.amber,
      ContainerType.sequence => Colors.teal,
    };
  }

  IconData _getIcon() {
    return switch (type) {
      ContainerType.none => Icons.audio_file,
      ContainerType.blend => Icons.blur_linear,
      ContainerType.random => Icons.shuffle,
      ContainerType.sequence => Icons.queue_music,
    };
  }

  String _getLabel() {
    return switch (type) {
      ContainerType.none => 'Direct',
      ContainerType.blend => 'Blend',
      ContainerType.random => 'Random',
      ContainerType.sequence => 'Sequence',
    };
  }
}

/// Mini container preview card
class ContainerPreviewCard extends StatelessWidget {
  final String name;
  final ContainerType type;
  final int childCount;
  final VoidCallback? onTap;
  final bool isSelected;

  const ContainerPreviewCard({
    super.key,
    required this.name,
    required this.type,
    required this.childCount,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getTypeColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : FluxForgeTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ContainerTypeBadge(type: type, compact: true),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$childCount ${childCount == 1 ? "child" : "children"}',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: FluxForgeTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor() {
    return switch (type) {
      ContainerType.none => FluxForgeTheme.textSecondary,
      ContainerType.blend => Colors.purple,
      ContainerType.random => Colors.amber,
      ContainerType.sequence => Colors.teal,
    };
  }
}
