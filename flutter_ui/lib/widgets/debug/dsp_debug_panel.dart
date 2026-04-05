/// DSP Debug Panel - Combined signal analyzer and insert chain debug
///
/// Shows:
/// - Signal flow visualization (INPUT → Processors → OUTPUT)
/// - Real-time metering
/// - Per-processor status
/// - Engine-side parameter verification
///
/// Use this panel to debug DSP processing issues.

import 'package:flutter/material.dart';
import 'signal_analyzer_widget.dart';
import 'insert_chain_debug.dart';

class DspDebugPanel extends StatelessWidget {
  final int trackId;

  const DspDebugPanel({
    super.key,
    this.trackId = 0, // Default to master bus
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Signal Analyzer (top)
          SignalAnalyzerWidget(
            trackId: trackId,
            height: 180,
          ),

          const SizedBox(height: 8),

          // Insert Chain Debug (bottom)
          Expanded(
            child: SingleChildScrollView(
              child: InsertChainDebug(
                trackId: trackId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
