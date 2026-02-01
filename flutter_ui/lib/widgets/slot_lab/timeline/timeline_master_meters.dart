// Timeline Master Meters — Professional Metering Display
//
// Master bus metering for timeline:
// - LUFS (Integrated/Short-term/Momentary)
// - True Peak (8x oversampling)
// - L/R Peak + RMS meters
// - Phase correlation

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../models/timeline/timeline_state.dart';

class TimelineMasterMeters extends StatelessWidget {
  final double lufsIntegrated;
  final double lufsShortTerm;
  final double lufsMomentary;
  final double truePeakL;
  final double truePeakR;
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double phaseCorrelation;

  const TimelineMasterMeters({
    super.key,
    this.lufsIntegrated = -23.0,
    this.lufsShortTerm = -23.0,
    this.lufsMomentary = -23.0,
    this.truePeakL = -20.0,
    this.truePeakR = -20.0,
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.rmsL = 0.0,
    this.rmsR = 0.0,
    this.phaseCorrelation = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          // LUFS meters
          Expanded(
            flex: 2,
            child: _buildLUFSMeters(),
          ),

          const SizedBox(height: 8),

          // L/R peak meters
          Expanded(
            flex: 3,
            child: _buildPeakMeters(),
          ),

          const SizedBox(height: 8),

          // Phase correlation
          SizedBox(
            height: 30,
            child: _buildPhaseCorrelation(),
          ),
        ],
      ),
    );
  }

  Widget _buildLUFSMeters() {
    return Row(
      children: [
        // Labels
        const SizedBox(
          width: 60,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('INT', style: TextStyle(fontSize: 9, color: Colors.white70)),
              Text('SHORT', style: TextStyle(fontSize: 9, color: Colors.white70)),
              Text('MOM', style: TextStyle(fontSize: 9, color: Colors.white70)),
            ],
          ),
        ),

        // Meters
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildHorizontalMeter(lufsIntegrated, -40, 0, 'I'),
              _buildHorizontalMeter(lufsShortTerm, -40, 0, 'S'),
              _buildHorizontalMeter(lufsMomentary, -40, 0, 'M'),
            ],
          ),
        ),

        // Values
        SizedBox(
          width: 50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('${lufsIntegrated.toStringAsFixed(1)}', style: const TextStyle(fontSize: 9, color: Colors.white)),
              Text('${lufsShortTerm.toStringAsFixed(1)}', style: const TextStyle(fontSize: 9, color: Colors.white)),
              Text('${lufsMomentary.toStringAsFixed(1)}', style: const TextStyle(fontSize: 9, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalMeter(double valueDb, double minDb, double maxDb, String label) {
    final normalized = ((valueDb - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);

    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            // Meter fill
            FractionallySizedBox(
              widthFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF40FF90), // Green
                      const Color(0xFFFFFF40), // Yellow
                      const Color(0xFFFF4060), // Red
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeakMeters() {
    return Row(
      children: [
        const SizedBox(
          width: 60,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('L', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
              SizedBox(height: 4),
              Text('R', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
            ],
          ),
        ),

        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildVerticalMeter(peakL, rmsL, truePeakL, 'L'),
              const SizedBox(height: 4),
              _buildVerticalMeter(peakR, rmsR, truePeakR, 'R'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalMeter(double peak, double rms, double truePeak, String channel) {
    final peakDb = peak > 0 ? 20 * math.log(peak) / math.ln10 : -60.0;
    final rmsDb = rms > 0 ? 20 * math.log(rms) / math.ln10 : -60.0;

    final peakNormalized = ((peakDb + 60) / 60).clamp(0.0, 1.0);
    final rmsNormalized = ((rmsDb + 60) / 60).clamp(0.0, 1.0);

    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            // RMS (background)
            FractionallySizedBox(
              widthFactor: rmsNormalized,
              child: Container(color: const Color(0xFF40FF90).withOpacity(0.5)),
            ),

            // Peak (foreground)
            FractionallySizedBox(
              widthFactor: peakNormalized,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF40FF90),
                      const Color(0xFFFFFF40),
                      const Color(0xFFFF4060),
                    ],
                    stops: const [0.0, 0.8, 1.0],
                  ),
                ),
              ),
            ),

            // dB markers
            ..._buildDbMarkers(),

            // True peak indicator
            if (truePeak > -0.1) // Clipping
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.warning, size: 12, color: Color(0xFFFF4060)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDbMarkers() {
    // Draw markers at -60, -40, -20, -6, 0 dB
    final markers = [-60.0, -40.0, -20.0, -6.0, 0.0];

    return markers.map((db) {
      final normalized = ((db + 60) / 60).clamp(0.0, 1.0);

      return Positioned(
        left: normalized * 1000, // Will be constrained
        top: 0,
        bottom: 0,
        child: Container(
          width: 1,
          color: Colors.white.withOpacity(0.2),
        ),
      );
    }).toList();
  }

  Widget _buildPhaseCorrelation() {
    return Row(
      children: [
        const SizedBox(
          width: 60,
          child: Text('PHASE', style: TextStyle(fontSize: 9, color: Colors.white70)),
        ),

        Expanded(
          child: Container(
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A22),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Stack(
              children: [
                // Gradient background (−1 to +1)
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFF4060), // -1 (out of phase)
                        Color(0xFFFFFF40), // 0 (mono)
                        Color(0xFF40FF90), // +1 (in phase)
                      ],
                    ),
                  ),
                ),

                // Center marker (0)
                Positioned(
                  left: 0.5 * 1000, // Will be constrained
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),

                // Correlation indicator
                Positioned(
                  left: ((phaseCorrelation + 1) / 2) * 1000, // −1..+1 → 0..1
                  top: 2,
                  bottom: 2,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(
          width: 50,
          child: Text(
            phaseCorrelation.toStringAsFixed(2),
            style: const TextStyle(fontSize: 9, color: Colors.white),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _formatTime(double timeSeconds, TimeDisplayMode mode) {
    switch (mode) {
      case TimeDisplayMode.milliseconds:
        return '${(timeSeconds * 1000).toInt()}ms';
      case TimeDisplayMode.seconds:
        return '${timeSeconds.toStringAsFixed(3)}s';
      case TimeDisplayMode.beats:
        return '1.1.1';
      case TimeDisplayMode.timecode:
        final minutes = (timeSeconds ~/ 60);
        final seconds = (timeSeconds % 60).floor();
        final frames = ((timeSeconds % 1) * 60).floor();
        return '${minutes.toString().padLeft(2, '0')}:'
            '${seconds.toString().padLeft(2, '0')}:'
            '${frames.toString().padLeft(2, '0')}';
    }
  }
}
