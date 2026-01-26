/// Compact LUFS Display for Mixer Channel Strip (P0.2)
///
/// Ultra-compact LUFS meter optimized for narrow mixer channel strips.
/// Shows Integrated LUFS with color-coded badge.
///
/// Created: 2026-01-26
library;

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT LUFS DISPLAY
// ═══════════════════════════════════════════════════════════════════════════

class CompactLufsDisplay extends StatelessWidget {
  final double lufsIntegrated;
  final double lufsShort;
  final bool showShortTerm;
  final double width;

  const CompactLufsDisplay({
    super.key,
    required this.lufsIntegrated,
    this.lufsShort = -70.0,
    this.showShortTerm = false,
    this.width = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _getBackgroundColor(lufsIntegrated),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _getBorderColor(lufsIntegrated),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LUFS',
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.bold,
              color: _getTextColor(lufsIntegrated),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatLufs(lufsIntegrated),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _getValueColor(lufsIntegrated),
              fontFamily: 'monospace',
            ),
          ),
          if (showShortTerm) ...[
            const SizedBox(height: 2),
            Text(
              _formatLufs(lufsShort),
              style: TextStyle(
                fontSize: 8,
                color: _getValueColor(lufsShort).withValues(alpha: 0.7),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getBackgroundColor(double lufs) {
    if (lufs > -14.0) return const Color(0xFFFF4060).withValues(alpha: 0.15); // Too loud
    if (lufs > -23.0) return const Color(0xFF40FF90).withValues(alpha: 0.10); // OK
    return const Color(0xFF0A0A0C); // Silence/Quiet
  }

  Color _getBorderColor(double lufs) {
    if (lufs > -14.0) return const Color(0xFFFF4060); // Red
    if (lufs > -23.0) return const Color(0xFF40FF90); // Green
    if (lufs > -70.0) return const Color(0xFF40C8FF); // Cyan
    return const Color(0xFF404040); // Gray
  }

  Color _getTextColor(double lufs) {
    if (lufs > -14.0) return const Color(0xFFFF4060);
    if (lufs > -23.0) return const Color(0xFF40FF90);
    return const Color(0xFF909090);
  }

  Color _getValueColor(double lufs) {
    if (lufs > -14.0) return const Color(0xFFFF4060); // Red (too loud)
    if (lufs > -16.0) return const Color(0xFFFF9040); // Orange (close to target)
    if (lufs > -23.0) return const Color(0xFF40FF90); // Green (streaming OK)
    if (lufs > -70.0) return const Color(0xFF40C8FF); // Cyan (broadcast OK)
    return const Color(0xFF606060); // Gray (silence)
  }

  String _formatLufs(double lufs) {
    if (lufs <= -69.0) return '--';
    return lufs.toStringAsFixed(1);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INLINE LUFS ROW (for horizontal layouts)
// ═══════════════════════════════════════════════════════════════════════════

class InlineLufsRow extends StatelessWidget {
  final double lufsIntegrated;
  final double lufsShort;
  final double lufsMomentary;

  const InlineLufsRow({
    super.key,
    required this.lufsIntegrated,
    this.lufsShort = -70.0,
    this.lufsMomentary = -70.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLufsCell('I', lufsIntegrated),
        const SizedBox(width: 4),
        _buildLufsCell('S', lufsShort),
        const SizedBox(width: 4),
        _buildLufsCell('M', lufsMomentary),
      ],
    );
  }

  Widget _buildLufsCell(String label, double value) {
    final color = _getColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF909090),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            _formatLufs(value),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor(double lufs) {
    if (lufs > -14.0) return const Color(0xFFFF4060); // Red
    if (lufs > -16.0) return const Color(0xFFFF9040); // Orange
    if (lufs > -23.0) return const Color(0xFF40FF90); // Green
    if (lufs > -70.0) return const Color(0xFF40C8FF); // Cyan
    return const Color(0xFF606060); // Gray
  }

  String _formatLufs(double lufs) {
    if (lufs <= -69.0) return '--';
    return lufs.toStringAsFixed(1);
  }
}
