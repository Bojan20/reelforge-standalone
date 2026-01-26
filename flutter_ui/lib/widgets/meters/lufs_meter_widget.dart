/// Real-Time LUFS Meter Widget (P0.2)
///
/// Displays EBU R128 loudness metering:
/// - LUFS-M (Momentary, 400ms)
/// - LUFS-S (Short-term, 3s)
/// - LUFS-I (Integrated, full program)
/// - True Peak (dBTP)
///
/// Polling rate: 200ms (5fps) — sufficient for LUFS
///
/// Created: 2026-01-26
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LUFS DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════

class LufsData {
  final double momentary;   // LUFS-M (400ms)
  final double shortTerm;   // LUFS-S (3s)
  final double integrated;  // LUFS-I (full)
  final double truePeakL;   // True Peak L (dBTP)
  final double truePeakR;   // True Peak R (dBTP)

  const LufsData({
    required this.momentary,
    required this.shortTerm,
    required this.integrated,
    required this.truePeakL,
    required this.truePeakR,
  });

  /// Get max true peak (L/R)
  double get maxTruePeak => momentary > shortTerm ? momentary : shortTerm;

  /// Check if over streaming target (-14 LUFS)
  bool get isOverStreamingTarget => integrated > -14.0;

  /// Check if over broadcast target (-23 LUFS)
  bool get isOverBroadcastTarget => integrated > -23.0;
}

// ═══════════════════════════════════════════════════════════════════════════
// LUFS METER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class LufsMeterWidget extends StatefulWidget {
  final double width;
  final double height;
  final bool showLabels;
  final bool showTruePeak;
  final Color accentColor;

  const LufsMeterWidget({
    super.key,
    this.width = 180,
    this.height = 120,
    this.showLabels = true,
    this.showTruePeak = true,
    this.accentColor = const Color(0xFF4A9EFF),
  });

  @override
  State<LufsMeterWidget> createState() => _LufsMeterWidgetState();
}

class _LufsMeterWidgetState extends State<LufsMeterWidget> {
  Timer? _pollTimer;
  LufsData _lufsData = const LufsData(
    momentary: -70.0,
    shortTerm: -70.0,
    integrated: -70.0,
    truePeakL: -70.0,
    truePeakR: -70.0,
  );

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    // Poll LUFS data at 200ms (5fps) — sufficient for loudness metering
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;

      try {
        final (momentary, shortTerm, integrated) = NativeFFI.instance.getLufsMeters();
        final (truePeakL, truePeakR) = NativeFFI.instance.getTruePeakMeters();

        setState(() {
          _lufsData = LufsData(
            momentary: momentary,
            shortTerm: shortTerm,
            integrated: integrated,
            truePeakL: truePeakL,
            truePeakR: truePeakR,
          );
        });
      } catch (e) {
        debugPrint('[LufsMeter] ❌ Failed to get LUFS data: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20), // bgMid
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF242430), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showLabels) ...[
            Text(
              'LOUDNESS (LUFS)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: widget.accentColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildLufsMeter('M', _lufsData.momentary, -23.0, -14.0),
          const SizedBox(height: 4),
          _buildLufsMeter('S', _lufsData.shortTerm, -23.0, -14.0),
          const SizedBox(height: 4),
          _buildLufsMeter('I', _lufsData.integrated, -23.0, -14.0),
          if (widget.showTruePeak) ...[
            const SizedBox(height: 8),
            _buildTruePeakMeter(),
          ],
        ],
      ),
    );
  }

  Widget _buildLufsMeter(String label, double value, double yellowZone, double redZone) {
    final color = _getLufsColor(value, yellowZone, redZone);

    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Color(0xFF909090),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildMeterBar(value, -70.0, 0.0, color),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 42,
          child: Text(
            _formatLufs(value),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildTruePeakMeter() {
    final maxPeak = _lufsData.truePeakL > _lufsData.truePeakR
        ? _lufsData.truePeakL
        : _lufsData.truePeakR;
    final color = maxPeak > -0.1 ? const Color(0xFFFF4060) : const Color(0xFF40FF90);

    return Row(
      children: [
        const SizedBox(
          width: 12,
          child: Text(
            'TP',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Color(0xFF909090),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildMeterBar(maxPeak, -20.0, 0.0, color),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 42,
          child: Text(
            _formatDb(maxPeak),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildMeterBar(double value, double min, double max, Color color) {
    final normalized = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C), // bgDeepest
        borderRadius: BorderRadius.circular(2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            // Fill bar
            FractionallySizedBox(
              widthFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.6),
                      color,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getLufsColor(double lufs, double yellowZone, double redZone) {
    if (lufs > redZone) return const Color(0xFFFF4060); // Red (too loud)
    if (lufs > yellowZone) return const Color(0xFFFF9040); // Orange (warning)
    if (lufs > -70.0) return const Color(0xFF40FF90); // Green (OK)
    return const Color(0xFF404040); // Gray (silence)
  }

  String _formatLufs(double lufs) {
    if (lufs <= -69.0) return '--';
    return '${lufs.toStringAsFixed(1)}';
  }

  String _formatDb(double db) {
    if (db <= -69.0) return '--';
    return '${db.toStringAsFixed(1)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT LUFS BADGE (for tight spaces)
// ═══════════════════════════════════════════════════════════════════════════

class LufsBadge extends StatefulWidget {
  final double fontSize;
  final bool showIcon;

  const LufsBadge({
    super.key,
    this.fontSize = 10,
    this.showIcon = true,
  });

  @override
  State<LufsBadge> createState() => _LufsBadgeState();
}

class _LufsBadgeState extends State<LufsBadge> {
  Timer? _pollTimer;
  double _integrated = -70.0;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      try {
        final (_, _, integrated) = NativeFFI.instance.getLufsMeters();
        setState(() => _integrated = integrated);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLufsColor(_integrated);
    final text = _integrated <= -69.0 ? '--' : '${_integrated.toStringAsFixed(1)} LUFS';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showIcon) ...[
          Icon(Icons.show_chart, size: widget.fontSize + 2, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Color _getLufsColor(double lufs) {
    if (lufs > -14.0) return const Color(0xFFFF4060); // Too loud
    if (lufs > -23.0) return const Color(0xFF40FF90); // OK
    if (lufs > -70.0) return const Color(0xFF40C8FF); // Quiet
    return const Color(0xFF404040); // Silence
  }
}
