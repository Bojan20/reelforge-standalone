/// PDC Indicator (P1.3)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../src/rust/native_ffi.dart';

class PdcIndicator extends StatelessWidget {
  final int trackId;

  const PdcIndicator({super.key, required this.trackId});

  @override
  Widget build(BuildContext context) {
    // Get PDC samples from FFI (if available)
    // For now, return placeholder
    const pdcSamples = 0;

    if (pdcSamples <= 0) return const SizedBox.shrink();

    return Container(
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
    );
  }
}
