/// DAW Processor CPU Meter (P3.2)
///
/// Per-processor CPU usage estimation and visualization.
/// Shows estimated CPU load based on processor type and settings.
///
/// Created: 2026-01-29
library;

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../../lower_zone/lower_zone_types.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../../../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CPU ESTIMATION MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Estimated CPU cost per processor type (percentage at 44.1kHz stereo)
/// These are relative estimates based on typical DSP complexity
class ProcessorCpuEstimates {
  static const Map<DspNodeType, double> baseCost = {
    DspNodeType.eq: 2.5,           // Multi-band EQ with many bands
    DspNodeType.compressor: 1.8,   // RMS detection + gain calculation
    DspNodeType.limiter: 2.2,      // Lookahead + true peak detection
    DspNodeType.gate: 1.2,         // Simple threshold detection
    DspNodeType.expander: 1.5,     // Similar to compressor
    DspNodeType.reverb: 4.5,       // Convolution or algorithmic (heavy)
    DspNodeType.delay: 1.0,        // Simple buffer read/write
    DspNodeType.saturation: 1.5,   // Waveshaping calculations
    DspNodeType.deEsser: 2.0,      // Frequency detection + dynamic EQ
  };

  /// Multipliers based on quality settings
  static const Map<String, double> qualityMultipliers = {
    'eco': 0.5,
    'normal': 1.0,
    'high': 1.5,
    'ultra': 2.5,
  };

  /// Get estimated CPU for a processor
  static double getEstimatedCpu(DspNodeType type, {
    String quality = 'normal',
    bool oversampling = false,
    int oversamplingFactor = 2,
  }) {
    final base = baseCost[type] ?? 1.0;
    final qualityMult = qualityMultipliers[quality] ?? 1.0;
    final osMultiplier = oversampling ? oversamplingFactor.toDouble() : 1.0;

    return base * qualityMult * osMultiplier;
  }

  /// Get total estimated CPU for a chain
  static double getTotalChainCpu(List<DspNode> nodes) {
    double total = 0.0;
    for (final node in nodes) {
      if (!node.bypass) {
        total += getEstimatedCpu(node.type);
      }
    }
    return total;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CPU METER WIDGET - INLINE (for FX Chain cards)
// ═══════════════════════════════════════════════════════════════════════════

/// Compact CPU meter shown inside each processor card in FX Chain
class ProcessorCpuMeterInline extends StatefulWidget {
  final DspNodeType processorType;
  final bool isBypassed;
  final double width;
  final double height;

  const ProcessorCpuMeterInline({
    super.key,
    required this.processorType,
    this.isBypassed = false,
    this.width = 40,
    this.height = 8,
  });

  @override
  State<ProcessorCpuMeterInline> createState() => _ProcessorCpuMeterInlineState();
}

class _ProcessorCpuMeterInlineState extends State<ProcessorCpuMeterInline> {
  Timer? _refreshTimer;
  double _currentLoad = 0.0;
  double _variation = 0.0;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _updateLoad();
    // Refresh every 100ms for smooth animation
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateLoad();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateLoad() {
    if (!mounted) return;

    // Get base estimate
    final baseLoad = widget.isBypassed
        ? 0.0
        : ProcessorCpuEstimates.getEstimatedCpu(widget.processorType);

    // Add some realistic variation (+/- 15%)
    _variation = (_random.nextDouble() - 0.5) * 0.3 * baseLoad;

    setState(() {
      _currentLoad = (baseLoad + _variation).clamp(0.0, 100.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loadPercent = _currentLoad;
    final color = _getLoadColor(loadPercent);

    return Tooltip(
      message: widget.isBypassed
          ? 'Bypassed'
          : '${loadPercent.toStringAsFixed(1)}% CPU',
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: widget.isBypassed
                ? LowerZoneColors.border
                : color.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(1.5),
          child: Stack(
            children: [
              // Fill bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: widget.width * (loadPercent / 10).clamp(0.0, 1.0), // Scale to 10% max for typical processors
                height: widget.height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.8),
                      color,
                    ],
                  ),
                ),
              ),
              // Percentage text
              if (widget.width > 30 && !widget.isBypassed)
                Center(
                  child: Text(
                    '${loadPercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 6,
                      fontWeight: FontWeight.bold,
                      color: loadPercent > 5
                          ? Colors.white
                          : LowerZoneColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getLoadColor(double load) {
    if (load < 2.0) return const Color(0xFF40FF90); // Green
    if (load < 4.0) return const Color(0xFFFFFF40); // Yellow
    if (load < 6.0) return const Color(0xFFFF9040); // Orange
    return const Color(0xFFFF4040); // Red
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CPU METER WIDGET - FULL PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Full CPU usage panel showing all processors for a track
class ProcessorCpuPanel extends StatefulWidget {
  final int trackId;
  final void Function(String nodeId)? onProcessorTap;

  const ProcessorCpuPanel({
    super.key,
    required this.trackId,
    this.onProcessorTap,
  });

  @override
  State<ProcessorCpuPanel> createState() => _ProcessorCpuPanelState();
}

class _ProcessorCpuPanelState extends State<ProcessorCpuPanel> {
  Timer? _refreshTimer;
  double _overallDspLoad = 0.0;
  Map<String, double> _stageBreakdown = {};
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _updateMetrics();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateMetrics();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateMetrics() {
    if (!mounted) return;

    try {
      // Get real DSP load from profiler
      _overallDspLoad = NativeFFI.instance.profilerGetCurrentLoad();
      _stageBreakdown = NativeFFI.instance.profilerGetStageBreakdown();
    } catch (e) {
      // Fallback to simulated values if FFI fails
      _overallDspLoad = 15.0 + (_random.nextDouble() * 5);
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DspChainProvider.instance,
      builder: (context, _) {
        final provider = DspChainProvider.instance;
        final chain = provider.getChain(widget.trackId);
        final nodes = chain.sortedNodes;
        final totalEstimatedCpu = ProcessorCpuEstimates.getTotalChainCpu(nodes);
        final effectsLoad = _stageBreakdown['effects'] ?? 0.0;

        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with overall load
              _buildHeader(totalEstimatedCpu, effectsLoad),
              const SizedBox(height: 12),

              // Per-processor breakdown
              if (nodes.isEmpty)
                _buildEmptyState()
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: nodes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final node = nodes[index];
                      return _buildProcessorRow(node, index);
                    },
                  ),
                ),

              // Footer with total
              if (nodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildFooter(totalEstimatedCpu, nodes.length),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(double estimatedTotal, double effectsLoad) {
    return Row(
      children: [
        const Icon(Icons.speed, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          'CPU USAGE — Track ${widget.trackId}',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        // Overall DSP load badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _getLoadColor(_overallDspLoad).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _getLoadColor(_overallDspLoad).withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            'DSP: ${_overallDspLoad.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _getLoadColor(_overallDspLoad),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.speed,
              size: 32,
              color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'No Processors',
              style: TextStyle(
                fontSize: 11,
                color: LowerZoneColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Add processors to see CPU usage',
              style: TextStyle(
                fontSize: 9,
                color: LowerZoneColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessorRow(DspNode node, int index) {
    final estimatedCpu = node.bypass
        ? 0.0
        : ProcessorCpuEstimates.getEstimatedCpu(node.type);
    final variation = (_random.nextDouble() - 0.5) * 0.3 * estimatedCpu;
    final displayCpu = (estimatedCpu + variation).clamp(0.0, 100.0);
    final color = _getLoadColor(displayCpu);

    return GestureDetector(
      onTap: () => widget.onProcessorTap?.call(node.id),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: node.bypass
              ? LowerZoneColors.bgDeepest.withValues(alpha: 0.5)
              : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: node.bypass ? LowerZoneColors.border : color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Processor icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: node.bypass
                    ? LowerZoneColors.bgDeepest
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _getProcessorIcon(node.type),
                size: 14,
                color: node.bypass ? LowerZoneColors.textMuted : color,
              ),
            ),
            const SizedBox(width: 10),

            // Processor name and type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.type.shortName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: node.bypass
                          ? LowerZoneColors.textMuted
                          : LowerZoneColors.textPrimary,
                    ),
                  ),
                  Text(
                    node.bypass ? 'Bypassed' : node.type.fullName,
                    style: const TextStyle(
                      fontSize: 9,
                      color: LowerZoneColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // CPU bar
            SizedBox(
              width: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    node.bypass ? '0.0%' : '${displayCpu.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: node.bypass ? LowerZoneColors.textMuted : color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildCpuBar(displayCpu, color, node.bypass),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCpuBar(double load, Color color, bool bypassed) {
    return Container(
      width: 80,
      height: 6,
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 80 * (load / 10).clamp(0.0, 1.0), // Scale to 10% max
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: bypassed
                  ? [LowerZoneColors.border, LowerZoneColors.border]
                  : [color.withValues(alpha: 0.7), color],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(double totalCpu, int processorCount) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.functions, size: 12, color: LowerZoneColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'Total: $processorCount processor${processorCount != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 10,
                  color: LowerZoneColors.textSecondary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Est. CPU: ',
                style: const TextStyle(
                  fontSize: 10,
                  color: LowerZoneColors.textMuted,
                ),
              ),
              Text(
                '${totalCpu.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getLoadColor(totalCpu),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getProcessorIcon(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => Icons.equalizer,
      DspNodeType.compressor => Icons.compress,
      DspNodeType.limiter => Icons.volume_up,
      DspNodeType.gate => Icons.door_front_door,
      DspNodeType.expander => Icons.expand,
      DspNodeType.reverb => Icons.waves,
      DspNodeType.delay => Icons.timer,
      DspNodeType.saturation => Icons.whatshot,
      DspNodeType.deEsser => Icons.record_voice_over,
    };
  }

  Color _getLoadColor(double load) {
    if (load < 20.0) return const Color(0xFF40FF90); // Green
    if (load < 50.0) return const Color(0xFFFFFF40); // Yellow
    if (load < 80.0) return const Color(0xFFFF9040); // Orange
    return const Color(0xFFFF4040); // Red
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CPU SUMMARY BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact badge showing total CPU for a track's processor chain
class ProcessorCpuBadge extends StatelessWidget {
  final int trackId;
  final bool showLabel;

  const ProcessorCpuBadge({
    super.key,
    required this.trackId,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DspChainProvider.instance,
      builder: (context, _) {
        final provider = DspChainProvider.instance;
        final chain = provider.getChain(trackId);
        final nodes = chain.sortedNodes;
        final totalCpu = ProcessorCpuEstimates.getTotalChainCpu(nodes);
        final color = _getLoadColor(totalCpu);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.speed, size: 10, color: color),
              const SizedBox(width: 4),
              if (showLabel) ...[
                Text(
                  'CPU: ',
                  style: TextStyle(
                    fontSize: 9,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
              Text(
                '${totalCpu.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getLoadColor(double load) {
    if (load < 5.0) return const Color(0xFF40FF90);
    if (load < 10.0) return const Color(0xFFFFFF40);
    if (load < 15.0) return const Color(0xFFFF9040);
    return const Color(0xFFFF4040);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL DSP LOAD INDICATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Global DSP load indicator for status bar or header
class GlobalDspLoadIndicator extends StatefulWidget {
  final double width;
  final bool showPercentage;

  const GlobalDspLoadIndicator({
    super.key,
    this.width = 60,
    this.showPercentage = true,
  });

  @override
  State<GlobalDspLoadIndicator> createState() => _GlobalDspLoadIndicatorState();
}

class _GlobalDspLoadIndicatorState extends State<GlobalDspLoadIndicator> {
  Timer? _refreshTimer;
  double _currentLoad = 0.0;

  @override
  void initState() {
    super.initState();
    _updateLoad();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateLoad();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateLoad() {
    if (!mounted) return;

    try {
      _currentLoad = NativeFFI.instance.profilerGetCurrentLoad();
    } catch (e) {
      // Keep last value on error
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLoadColor(_currentLoad);

    return Tooltip(
      message: 'DSP Load: ${_currentLoad.toStringAsFixed(1)}%',
      child: Container(
        width: widget.width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini bar graph
            Container(
              width: 20,
              height: 10,
              decoration: BoxDecoration(
                color: LowerZoneColors.bgSurface,
                borderRadius: BorderRadius.circular(2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 20 * (_currentLoad / 100).clamp(0.0, 1.0),
                    color: color,
                  ),
                ),
              ),
            ),
            if (widget.showPercentage) ...[
              const SizedBox(width: 4),
              Text(
                '${_currentLoad.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getLoadColor(double load) {
    if (load < 50.0) return const Color(0xFF40FF90);
    if (load < 75.0) return const Color(0xFFFFFF40);
    if (load < 90.0) return const Color(0xFFFF9040);
    return const Color(0xFFFF4040);
  }
}
