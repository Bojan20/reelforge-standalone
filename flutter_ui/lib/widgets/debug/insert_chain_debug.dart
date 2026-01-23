/// Debug widget to show master insert chain status
///
/// Shows:
/// - All loaded processors
/// - Current slot indices
/// - Parameter values
/// - Real-time audio levels

import 'dart:async';
import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';

class InsertChainDebug extends StatefulWidget {
  final int trackId;

  const InsertChainDebug({
    super.key,
    this.trackId = 0, // Default to master bus
  });

  @override
  State<InsertChainDebug> createState() => _InsertChainDebugState();
}

class _InsertChainDebugState extends State<InsertChainDebug> {
  Timer? _refreshTimer;
  final _ffi = NativeFFI.instance;

  @override
  void initState() {
    super.initState();
    // Refresh every 200ms
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A5A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.bug_report, color: Color(0xFF40C8FF), size: 16),
              const SizedBox(width: 8),
              Text(
                'Insert Chain Debug (Track ${widget.trackId}${widget.trackId == 0 ? " = MASTER" : ""})',
                style: const TextStyle(
                  color: Color(0xFF40C8FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF3A3A5A), height: 16),

          // Chain bypass status
          _buildRow('Chain Bypass', chain.bypass ? 'YES (all slots bypassed)' : 'NO'),
          _buildRow('Total Nodes', '${chain.nodes.length}'),
          const SizedBox(height: 8),

          // Each processor
          if (chain.nodes.isEmpty)
            const Text(
              'No processors loaded',
              style: TextStyle(color: Color(0xFFFF8040), fontSize: 11),
            )
          else
            ...chain.nodes.asMap().entries.map((entry) {
              final slotIndex = entry.key;
              final node = entry.value;
              return _buildProcessorInfo(slotIndex, node);
            }),

          const SizedBox(height: 8),

          // Engine-side verification
          const Text(
            'Engine Verification (FFI)',
            style: TextStyle(
              color: Color(0xFF40FF90),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),

          // Read back param values from engine
          ...chain.nodes.asMap().entries.map((entry) {
            final slotIndex = entry.key;
            final node = entry.value;
            return _buildEngineParams(slotIndex, node.type);
          }),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF808090), fontSize: 10),
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Color(0xFFE0E0F0), fontSize: 10, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessorInfo(int slotIndex, DspNode node) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: node.bypass ? const Color(0xFFFF8040) : const Color(0xFF3A3A5A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'Slot $slotIndex',
                  style: const TextStyle(
                    color: Color(0xFF4A9EFF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                node.type.fullName,
                style: const TextStyle(
                  color: Color(0xFFE0E0F0),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (node.bypass) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8040).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'BYPASSED',
                    style: TextStyle(color: Color(0xFFFF8040), fontSize: 8),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          _buildRow('Node ID', node.id.substring(0, 20)),
          _buildRow('Order', '${node.order}'),
          _buildRow('Wet/Dry', '${(node.wetDry * 100).toInt()}%'),

          // Show relevant params for each type
          if (node.params.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              'Params (Dart State):',
              style: TextStyle(color: Color(0xFF808090), fontSize: 9),
            ),
            ...node.params.entries.take(5).map((p) => _buildRow(
              '  ${p.key}',
              p.value is double ? (p.value as double).toStringAsFixed(2) : '${p.value}',
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineParams(int slotIndex, DspNodeType type) {
    // Read back params from engine to verify
    final paramNames = _getParamNames(type);
    final values = <String, double>{};

    for (int i = 0; i < paramNames.length && i < 8; i++) {
      values[paramNames[i]] = _ffi.insertGetParam(widget.trackId, slotIndex, i);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slot $slotIndex (${type.shortName}) - Engine Values:',
            style: const TextStyle(color: Color(0xFF40FF90), fontSize: 9),
          ),
          Wrap(
            spacing: 12,
            children: values.entries.map((e) => Text(
              '${e.key}: ${e.value.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Color(0xFFE0E0F0),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  List<String> _getParamNames(DspNodeType type) {
    return switch (type) {
      DspNodeType.compressor => ['Threshold', 'Ratio', 'Attack', 'Release', 'Makeup', 'Mix', 'Knee', 'Type'],
      DspNodeType.limiter => ['Threshold', 'Ceiling', 'Release', 'Oversampling'],
      DspNodeType.gate => ['Threshold', 'Range', 'Attack', 'Hold', 'Release'],
      DspNodeType.eq => ['Band0_Freq', 'Band0_Gain', 'Band0_Q'],
      DspNodeType.reverb => ['Decay', 'Damping', 'RoomSize', 'PreDelay', 'Mix'],
      _ => ['Param0', 'Param1', 'Param2', 'Param3'],
    };
  }
}
