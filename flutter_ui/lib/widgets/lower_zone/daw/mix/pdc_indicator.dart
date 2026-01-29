/// PDC Indicator (P1.3) — Cubase-style per-track latency display
///
/// Shows plugin delay compensation (PDC) for each track.
/// Displays latency in samples when > 0, with tooltip showing ms.
///
/// Created: 2026-01-29
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../src/rust/native_ffi.dart';

class PdcIndicator extends StatelessWidget {
  final int trackId;

  /// Optional sample rate for ms calculation (defaults to 48000)
  final double sampleRate;

  const PdcIndicator({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
  });

  @override
  Widget build(BuildContext context) {
    // Get PDC samples from FFI
    final pdcSamples = NativeFFI.instance.pdcGetTrackLatency(trackId);

    // Don't show if no latency
    if (pdcSamples <= 0) return const SizedBox.shrink();

    // Calculate milliseconds for tooltip
    final pdcMs = (pdcSamples / sampleRate) * 1000.0;

    return Tooltip(
      message: 'Plugin Delay: $pdcSamples samples (${pdcMs.toStringAsFixed(2)} ms)',
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: LowerZoneColors.warning.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: LowerZoneColors.warning, width: 1),
        ),
        child: Text(
          'PDC $pdcSamples',
          style: const TextStyle(
            fontSize: 8,
            color: LowerZoneColors.warning,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Compact PDC badge for tight spaces (shows only when latency > threshold)
class PdcBadge extends StatelessWidget {
  final int trackId;

  /// Minimum samples to display badge (default: 64 = ~1.3ms at 48kHz)
  final int minSamplesToShow;

  const PdcBadge({
    super.key,
    required this.trackId,
    this.minSamplesToShow = 64,
  });

  @override
  Widget build(BuildContext context) {
    final pdcSamples = NativeFFI.instance.pdcGetTrackLatency(trackId);

    if (pdcSamples < minSamplesToShow) return const SizedBox.shrink();

    return Tooltip(
      message: 'PDC: $pdcSamples samples',
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: LowerZoneColors.warning.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: LowerZoneColors.warning, width: 1),
        ),
        child: const Center(
          child: Text(
            'D',
            style: TextStyle(
              fontSize: 9,
              color: LowerZoneColors.warning,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
