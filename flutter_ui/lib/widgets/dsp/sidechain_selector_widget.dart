/// Sidechain Input Selector Widget (P0.5)
///
/// Allows selecting which track to use as sidechain input for compressor/gate.
///
/// Created: 2026-01-26
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lower_zone/lower_zone_types.dart';
import '../../providers/mixer_provider.dart';
import '../../src/rust/native_ffi.dart';

class SidechainSelectorWidget extends StatefulWidget {
  final int trackId;
  final int slotIndex;

  const SidechainSelectorWidget({
    super.key,
    required this.trackId,
    required this.slotIndex,
  });

  @override
  State<SidechainSelectorWidget> createState() => _SidechainSelectorWidgetState();
}

class _SidechainSelectorWidgetState extends State<SidechainSelectorWidget> {
  int _currentSource = -1; // -1 = internal

  @override
  void initState() {
    super.initState();
    _currentSource = NativeFFI.instance.insertGetSidechainSource(widget.trackId, widget.slotIndex);
  }

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'SIDECHAIN INPUT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _currentSource,
          isExpanded: true,
          dropdownColor: LowerZoneColors.bgMid,
          style: const TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary),
          items: [
            const DropdownMenuItem(
              value: -1,
              child: Text('Internal (no external sidechain)'),
            ),
            ...mixer.channels.map((ch) {
              final trackId = int.tryParse(ch.id.replaceAll('ch_', '')) ?? 0;
              return DropdownMenuItem(
                value: trackId,
                child: Text('Track: ${ch.name}'),
              );
            }),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _currentSource = value);
              NativeFFI.instance.insertSetSidechainSource(
                widget.trackId,
                widget.slotIndex,
                value,
              );
            }
          },
        ),
        if (_currentSource >= 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LowerZoneColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, size: 12, color: LowerZoneColors.success),
                const SizedBox(width: 6),
                Text(
                  'External sidechain active',
                  style: const TextStyle(fontSize: 9, color: LowerZoneColors.success),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
