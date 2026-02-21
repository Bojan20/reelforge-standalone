/// Mixer Status Bar — bottom info strip
///
/// Displays: track count, bus count, DSP load, latency, sample rate.
/// Pro Tools style: thin strip at bottom of mixer window.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/mixer_provider.dart';
import '../../src/rust/native_ffi.dart';

class MixerStatusBar extends StatefulWidget {
  const MixerStatusBar({super.key});

  @override
  State<MixerStatusBar> createState() => _MixerStatusBarState();
}

class _MixerStatusBarState extends State<MixerStatusBar> {
  Timer? _refreshTimer;
  double _dspLoad = 0.0;
  double _latencyMs = 0.0;
  int _sampleRate = 48000;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refreshMetrics(),
    );
    _refreshMetrics();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refreshMetrics() {
    if (!mounted) return;
    try {
      final ffi = NativeFFI.instance;
      final load = ffi.profilerGetCurrentLoad();
      setState(() {
        _dspLoad = load;
      });
    } catch (_) {
      // FFI not available
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerProvider>(
      builder: (context, mixer, _) {
        final trackCount = mixer.channels.where(
          (c) => c.type == ChannelType.audio || c.type == ChannelType.instrument,
        ).length;
        final busCount = mixer.channels.where(
          (c) => c.type == ChannelType.bus,
        ).length;
        final auxCount = mixer.channels.where(
          (c) => c.type == ChannelType.aux,
        ).length;
        final vcaCount = mixer.channels.where(
          (c) => c.type == ChannelType.vca,
        ).length;

        return Container(
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0E),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _buildStatChip('$trackCount trk', const Color(0xFF4A9EFF)),
              _buildDot(),
              _buildStatChip('$busCount bus', const Color(0xFF40FF90)),
              if (auxCount > 0) ...[
                _buildDot(),
                _buildStatChip('$auxCount aux', const Color(0xFF9370DB)),
              ],
              if (vcaCount > 0) ...[
                _buildDot(),
                _buildStatChip('$vcaCount vca', const Color(0xFFFF9040)),
              ],
              const Spacer(),
              // DSP load
              _buildStatChip(
                'DSP ${_dspLoad.toStringAsFixed(0)}%',
                _dspLoad > 80
                    ? const Color(0xFFFF4060)
                    : _dspLoad > 50
                        ? const Color(0xFFFF9040)
                        : const Color(0xFF40FF90),
              ),
              _buildDot(),
              // Sample rate
              _buildStatChip(
                '${_sampleRate ~/ 1000}kHz',
                Colors.white.withOpacity(0.4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
