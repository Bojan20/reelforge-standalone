/// Plugin Delay Compensation (PDC) Visualization Widget
///
/// Displays the total latency introduced by plugins in a track/bus chain
/// and shows how FluxForge automatically compensates for it.
///
/// Features:
/// - Per-plugin latency display
/// - Total chain latency
/// - Visual compensation timeline
/// - Warning for excessive latency (>100ms)

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// PDC information for a single plugin
class PluginDelayInfo {
  final String pluginName;
  final String pluginId;
  final int latencySamples;
  final double latencyMs;
  final bool isCompensated;

  PluginDelayInfo({
    required this.pluginName,
    required this.pluginId,
    required this.latencySamples,
    required this.latencyMs,
    this.isCompensated = true,
  });
}

/// PDC indicator widget for plugin chains
class PluginPDCIndicator extends StatelessWidget {
  final List<PluginDelayInfo> plugins;
  final double sampleRate;
  final bool showDetails;

  const PluginPDCIndicator({
    super.key,
    required this.plugins,
    this.sampleRate = 48000.0,
    this.showDetails = true,
  });

  double get totalLatencyMs {
    return plugins.fold(0.0, (sum, plugin) => sum + plugin.latencyMs);
  }

  int get totalLatencySamples {
    return plugins.fold(0, (sum, plugin) => sum + plugin.latencySamples);
  }

  bool get hasWarning => totalLatencyMs > 100.0;

  @override
  Widget build(BuildContext context) {
    if (plugins.isEmpty) {
      return const SizedBox();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasWarning ? FluxForgeTheme.accentRed : FluxForgeTheme.borderSubtle,
          width: hasWarning ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          if (showDetails) ...[
            const SizedBox(height: 8),
            _buildTimeline(context),
            const SizedBox(height: 8),
            _buildPluginList(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          hasWarning ? Icons.warning_amber : Icons.timelapse,
          size: 18,
          color: hasWarning ? FluxForgeTheme.accentRed : FluxForgeTheme.accentCyan,
        ),
        const SizedBox(width: 6),
        Text(
          'PDC: ${totalLatencyMs.toStringAsFixed(1)} ms',
          style: theme.textTheme.titleSmall?.copyWith(
            color: hasWarning ? FluxForgeTheme.accentRed : FluxForgeTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentCyan.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: FluxForgeTheme.accentCyan),
          ),
          child: Text(
            '$totalLatencySamples smp',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
        ),
        const Spacer(),
        if (hasWarning)
          Tooltip(
            message: 'High latency may cause audible delay.\nConsider using lower latency plugins or reducing buffer size.',
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: FluxForgeTheme.accentRed,
            ),
          ),
      ],
    );
  }

  Widget _buildTimeline(BuildContext context) {
    return SizedBox(
      height: 60,
      child: CustomPaint(
        painter: _PDCTimelinePainter(
          plugins: plugins,
          totalLatencyMs: totalLatencyMs,
        ),
        child: Container(),
      ),
    );
  }

  Widget _buildPluginList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Plugin Latencies',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        ...plugins.map((plugin) => _buildPluginRow(context, plugin)),
      ],
    );
  }

  Widget _buildPluginRow(BuildContext context, PluginDelayInfo plugin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            plugin.isCompensated ? Icons.check_circle : Icons.error,
            size: 14,
            color: plugin.isCompensated ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              plugin.pluginName,
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${plugin.latencyMs.toStringAsFixed(1)} ms',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PDCTimelinePainter extends CustomPainter {
  final List<PluginDelayInfo> plugins;
  final double totalLatencyMs;

  _PDCTimelinePainter({
    required this.plugins,
    required this.totalLatencyMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (plugins.isEmpty || totalLatencyMs <= 0) return;

    final timelinePaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final compensationPaint = Paint()
      ..color = FluxForgeTheme.accentCyan.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Draw timeline axis
    canvas.drawLine(
      Offset(20, size.height / 2),
      Offset(size.width - 20, size.height / 2),
      timelinePaint,
    );

    // Draw compensation region
    final compRect = Rect.fromLTWH(
      20,
      size.height / 2 - 15,
      size.width - 40,
      30,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(compRect, const Radius.circular(4)),
      compensationPaint,
    );

    // Draw plugin segments
    double currentX = 20;
    final totalWidth = size.width - 40;

    for (final plugin in plugins) {
      final segmentWidth = (plugin.latencyMs / totalLatencyMs) * totalWidth;

      // Draw plugin segment
      final segmentPaint = Paint()
        ..color = _getColorForLatency(plugin.latencyMs)
        ..style = PaintingStyle.fill;

      final segmentRect = Rect.fromLTWH(
        currentX,
        size.height / 2 - 12,
        segmentWidth,
        24,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(segmentRect, const Radius.circular(3)),
        segmentPaint,
      );

      // Draw segment border
      final borderPaint = Paint()
        ..color = FluxForgeTheme.bgDeep
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(
        RRect.fromRectAndRadius(segmentRect, const Radius.circular(3)),
        borderPaint,
      );

      // Draw latency label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${plugin.latencyMs.toStringAsFixed(0)}ms',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      if (segmentWidth > textPainter.width + 4) {
        textPainter.paint(
          canvas,
          Offset(
            currentX + (segmentWidth - textPainter.width) / 2,
            size.height / 2 - textPainter.height / 2,
          ),
        );
      }

      currentX += segmentWidth;
    }

    // Draw start/end markers
    final markerPaint = Paint()
      ..color = FluxForgeTheme.textPrimary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset(20, size.height / 2), 4, markerPaint);
    canvas.drawCircle(Offset(size.width - 20, size.height / 2), 4, markerPaint);

    // Draw "COMPENSATED" label
    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'COMPENSATED',
        style: TextStyle(
          color: FluxForgeTheme.accentCyan,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    labelPainter.layout();
    labelPainter.paint(
      canvas,
      Offset(
        (size.width - labelPainter.width) / 2,
        5,
      ),
    );
  }

  Color _getColorForLatency(double latencyMs) {
    if (latencyMs < 10) return FluxForgeTheme.accentGreen;
    if (latencyMs < 30) return FluxForgeTheme.accentCyan;
    if (latencyMs < 50) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  @override
  bool shouldRepaint(covariant _PDCTimelinePainter oldDelegate) {
    return oldDelegate.plugins != plugins || oldDelegate.totalLatencyMs != totalLatencyMs;
  }
}

/// Compact PDC badge for channel strips
class PluginPDCBadge extends StatelessWidget {
  final double totalLatencyMs;
  final int pluginCount;

  const PluginPDCBadge({
    super.key,
    required this.totalLatencyMs,
    required this.pluginCount,
  });

  @override
  Widget build(BuildContext context) {
    if (totalLatencyMs == 0 || pluginCount == 0) {
      return const SizedBox();
    }

    final hasWarning = totalLatencyMs > 100.0;

    return Tooltip(
      message: '$pluginCount plugin${pluginCount > 1 ? 's' : ''}\n${totalLatencyMs.toStringAsFixed(1)} ms latency\n(Auto-compensated)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: hasWarning
            ? FluxForgeTheme.accentRed.withOpacity(0.2)
            : FluxForgeTheme.accentCyan.withOpacity(0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: hasWarning ? FluxForgeTheme.accentRed : FluxForgeTheme.accentCyan,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timelapse,
              size: 12,
              color: hasWarning ? FluxForgeTheme.accentRed : FluxForgeTheme.accentCyan,
            ),
            const SizedBox(width: 3),
            Text(
              '${totalLatencyMs.toStringAsFixed(0)}ms',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: hasWarning ? FluxForgeTheme.accentRed : FluxForgeTheme.accentCyan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
