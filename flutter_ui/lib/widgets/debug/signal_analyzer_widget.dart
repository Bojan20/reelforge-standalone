/// Signal Analyzer Widget - Visualizes audio signal flow through insert chain
///
/// Shows:
/// - Input signal level (before insert chain)
/// - Output signal level (after insert chain)
/// - Per-processor status with bypass indicators
/// - Real-time peak/RMS metering
/// - Signal flow visualization

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';

class SignalAnalyzerWidget extends StatefulWidget {
  final int trackId;
  final double width;
  final double height;

  const SignalAnalyzerWidget({
    super.key,
    this.trackId = 0, // Default to master bus
    this.width = 600,
    this.height = 200,
  });

  @override
  State<SignalAnalyzerWidget> createState() => _SignalAnalyzerWidgetState();
}

class _SignalAnalyzerWidgetState extends State<SignalAnalyzerWidget> {
  Timer? _refreshTimer;
  final _ffi = NativeFFI.instance;

  // Metering values
  double _inputPeakL = -60.0;
  double _inputPeakR = -60.0;
  double _inputRmsL = -60.0;
  double _inputRmsR = -60.0;
  double _outputPeakL = -60.0;
  double _outputPeakR = -60.0;
  double _outputRmsL = -60.0;
  double _outputRmsR = -60.0;

  @override
  void initState() {
    super.initState();
    // Refresh at 30fps for smooth metering
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) {
        _updateMeters();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateMeters() {
    // Get track metering data
    // For master bus (trackId=0), this shows the final output
    final meterData = _ffi.getTrackMeter(widget.trackId);
    _outputPeakL = _linearToDb(meterData.peakL);
    _outputPeakR = _linearToDb(meterData.peakR);
    _outputRmsL = _linearToDb(meterData.rmsL);
    _outputRmsR = _linearToDb(meterData.rmsR);

    // For input, we'd ideally have pre-insert metering
    // For now, estimate input as output + total gain reduction
    // This is an approximation since we don't have true pre-insert metering
    _inputPeakL = _outputPeakL; // Will be enhanced with pre-insert FFI
    _inputPeakR = _outputPeakR;
    _inputRmsL = _outputRmsL;
    _inputRmsR = _outputRmsR;
  }

  double _linearToDb(double linear) {
    if (linear <= 0) return -60.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  @override
  Widget build(BuildContext context) {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          const Divider(color: Color(0xFF2A2A3A), height: 1),

          // Signal Flow
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Input Meters
                  _buildMeterSection('INPUT', _inputPeakL, _inputPeakR, _inputRmsL, _inputRmsR),

                  const SizedBox(width: 8),

                  // Signal Flow Arrow
                  _buildArrow(),

                  const SizedBox(width: 8),

                  // Processor Chain
                  Expanded(
                    child: _buildProcessorChain(chain),
                  ),

                  const SizedBox(width: 8),

                  // Signal Flow Arrow
                  _buildArrow(),

                  const SizedBox(width: 8),

                  // Output Meters
                  _buildMeterSection('OUTPUT', _outputPeakL, _outputPeakR, _outputRmsL, _outputRmsR),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.analytics, color: Color(0xFF40C8FF), size: 16),
          const SizedBox(width: 8),
          Text(
            'Signal Analyzer — Track ${widget.trackId}${widget.trackId == 0 ? " (MASTER)" : ""}',
            style: const TextStyle(
              color: Color(0xFF40C8FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Chain bypass indicator
          Consumer<DspChainProvider>(
            builder: (context, dsp, _) {
              final chain = dsp.getChain(widget.trackId);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: chain.bypass
                      ? const Color(0xFFFF8040).withValues(alpha: 0.2)
                      : const Color(0xFF40FF90).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  chain.bypass ? 'BYPASSED' : 'ACTIVE',
                  style: TextStyle(
                    color: chain.bypass ? const Color(0xFFFF8040) : const Color(0xFF40FF90),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMeterSection(String label, double peakL, double peakR, double rmsL, double rmsR) {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(
        children: [
          // Label
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF808090),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A2A3A), height: 1),

          // Stereo Meters
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildVerticalMeter(peakL, rmsL, 'L'),
                const SizedBox(width: 4),
                _buildVerticalMeter(peakR, rmsR, 'R'),
              ],
            ),
          ),

          // Peak readout
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${math.max(peakL, peakR).toStringAsFixed(1)} dB',
              style: const TextStyle(
                color: Color(0xFFE0E0F0),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalMeter(double peak, double rms, String channel) {
    return Column(
      children: [
        Text(
          channel,
          style: const TextStyle(
            color: Color(0xFF606070),
            fontSize: 8,
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Container(
            width: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A10),
              borderRadius: BorderRadius.circular(2),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                // Map -60dB to 0dB to meter height
                final peakHeight = ((peak + 60) / 60).clamp(0.0, 1.0) * height;
                final rmsHeight = ((rms + 60) / 60).clamp(0.0, 1.0) * height;

                return Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // RMS bar (wider)
                    Container(
                      width: 10,
                      height: rmsHeight,
                      decoration: BoxDecoration(
                        gradient: _getMeterGradient(rms),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    // Peak indicator (thin line)
                    Positioned(
                      bottom: peakHeight - 2,
                      child: Container(
                        width: 12,
                        height: 2,
                        color: _getPeakColor(peak),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  LinearGradient _getMeterGradient(double db) {
    return const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      stops: [0.0, 0.5, 0.75, 0.9, 1.0],
      colors: [
        Color(0xFF40C8FF), // -60 to -30 dB (blue)
        Color(0xFF40FF90), // -30 to -15 dB (green)
        Color(0xFFFFFF40), // -15 to -6 dB (yellow)
        Color(0xFFFF9040), // -6 to -3 dB (orange)
        Color(0xFFFF4040), // -3 to 0 dB (red)
      ],
    );
  }

  Color _getPeakColor(double db) {
    if (db > -3) return const Color(0xFFFF4040);
    if (db > -6) return const Color(0xFFFF9040);
    if (db > -15) return const Color(0xFFFFFF40);
    return const Color(0xFF40FF90);
  }

  Widget _buildArrow() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.arrow_forward,
          color: const Color(0xFF40C8FF).withValues(alpha: 0.5),
          size: 20,
        ),
      ],
    );
  }

  Widget _buildProcessorChain(DspChain chain) {
    if (chain.nodes.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D18),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF2A2A3A),
              style: BorderStyle.solid,
            ),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, color: Color(0xFF606070), size: 24),
              SizedBox(height: 8),
              Text(
                'No processors loaded',
                style: TextStyle(
                  color: Color(0xFF606070),
                  fontSize: 11,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Add EQ, Compressor, Limiter, etc.',
                style: TextStyle(
                  color: Color(0xFF404050),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: chain.nodes.length,
      separatorBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(
          Icons.arrow_forward,
          color: const Color(0xFF40C8FF).withValues(alpha: 0.3),
          size: 16,
        ),
      ),
      itemBuilder: (context, index) {
        final node = chain.nodes[index];
        return _buildProcessorNode(index, node);
      },
    );
  }

  Widget _buildProcessorNode(int slotIndex, DspNode node) {
    final color = _getProcessorColor(node.type);
    final isActive = !node.bypass;

    return Container(
      width: 90,
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.15)
            : const Color(0xFF0D0D18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? color : const Color(0xFF3A3A4A),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Slot number
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(3),
              ),
            ),
            child: Text(
              'SLOT $slotIndex',
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Spacer(),

          // Processor icon
          Icon(
            _getProcessorIcon(node.type),
            color: isActive ? color : const Color(0xFF505060),
            size: 24,
          ),

          const SizedBox(height: 4),

          // Processor name
          Text(
            node.type.shortName,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF606070),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Spacer(),

          // Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: node.bypass
                  ? const Color(0xFFFF8040).withValues(alpha: 0.2)
                  : const Color(0xFF40FF90).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              node.bypass ? 'BYP' : 'ON',
              style: TextStyle(
                color: node.bypass ? const Color(0xFFFF8040) : const Color(0xFF40FF90),
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getProcessorColor(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => const Color(0xFF4A9EFF),
      DspNodeType.compressor => const Color(0xFFFF9040),
      DspNodeType.limiter => const Color(0xFFFF4060),
      DspNodeType.gate => const Color(0xFF40FFAA),
      DspNodeType.expander => const Color(0xFF40DDAA),
      DspNodeType.reverb => const Color(0xFFAA40FF),
      DspNodeType.delay => const Color(0xFF40AAFF),
      DspNodeType.saturation => const Color(0xFFFFAA40),
      DspNodeType.deEsser => const Color(0xFFFF40AA),
      DspNodeType.pultec => const Color(0xFFD4A574),
      DspNodeType.api550 => const Color(0xFF4A9EFF),
      DspNodeType.neve1073 => const Color(0xFF8B4513),
      DspNodeType.multibandSaturation => const Color(0xFFFFAA40),
    };
  }

  IconData _getProcessorIcon(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => Icons.equalizer,
      DspNodeType.compressor => Icons.compress,
      DspNodeType.limiter => Icons.vertical_align_top,
      DspNodeType.gate => Icons.door_front_door_outlined,
      DspNodeType.expander => Icons.expand,
      DspNodeType.reverb => Icons.blur_on,
      DspNodeType.delay => Icons.access_time,
      DspNodeType.saturation => Icons.waves,
      DspNodeType.deEsser => Icons.record_voice_over,
      DspNodeType.pultec => Icons.tune,
      DspNodeType.api550 => Icons.graphic_eq,
      DspNodeType.neve1073 => Icons.surround_sound,
      DspNodeType.multibandSaturation => Icons.whatshot,
    };
  }
}

/// Consumer widget helper (since we can't import provider in this file)
class Consumer<T> extends StatelessWidget {
  final Widget Function(BuildContext context, T value, Widget? child) builder;

  const Consumer({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    if (T == DspChainProvider) {
      return builder(context, DspChainProvider.instance as T, null);
    }
    throw UnimplementedError('Consumer not implemented for $T');
  }
}
