/// CORTEX Health Indicator — real-time nervous system health in status bar
///
/// Compact widget showing CORTEX health score with color-coded indicator.
/// Taps to expand into detailed awareness dashboard overlay with:
/// - 7 awareness dimensions (throughput, reliability, responsiveness, coverage, cognition, efficiency, coherence)
/// - Signal throughput & drop rate
/// - Reflex stats
/// - Pattern recognition count
/// Polls CORTEX FFI every 2 seconds (matches awareness_interval).

import 'dart:async';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';

/// Compact CORTEX health indicator for status bars.
/// Shows a colored dot + health percentage. Expands on tap.
class CortexHealthIndicator extends StatefulWidget {
  /// Whether to show the text label (false = dot only, for tight spaces)
  final bool showLabel;

  const CortexHealthIndicator({super.key, this.showLabel = true});

  @override
  State<CortexHealthIndicator> createState() => _CortexHealthIndicatorState();
}

class _CortexHealthIndicatorState extends State<CortexHealthIndicator>
    with SingleTickerProviderStateMixin {
  Timer? _pollTimer;
  double _health = 1.0;
  bool _isDegraded = false;
  int _totalSignals = 0;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _poll(),
    );
    _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _poll() {
    if (!mounted) return;
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      final health = ffi.cortexGetHealth();
      final degraded = ffi.cortexIsDegraded();
      final signals = ffi.cortexGetTotalSignals();

      if (degraded && !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      } else if (!degraded && _pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }

      setState(() {
        _health = health;
        _isDegraded = degraded;
        _totalSignals = signals;
      });
    } catch (_) {}
  }

  Color _healthColor() {
    if (_health >= 0.8) return const Color(0xFF40FF90); // green
    if (_health >= 0.6) return const Color(0xFFFFD740); // amber
    if (_health >= 0.4) return const Color(0xFFFF9040); // orange
    return const Color(0xFFFF4060); // red
  }

  String _healthLabel() {
    final pct = (_health * 100).round();
    return 'CTX $pct%';
  }

  void _showDetails() {
    showDialog(
      context: context,
      builder: (_) => const _CortexDashboardDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _healthColor();

    return GestureDetector(
      onTap: _showDetails,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final opacity = _isDegraded ? _pulseAnimation.value : 1.0;
          return Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Health dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                if (widget.showLabel) ...[
                  const SizedBox(width: 4),
                  Text(
                    _healthLabel(),
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX DASHBOARD DIALOG — Full Nervous System Awareness
// ═══════════════════════════════════════════════════════════════════════════

class _CortexDashboardDialog extends StatefulWidget {
  const _CortexDashboardDialog();

  @override
  State<_CortexDashboardDialog> createState() => _CortexDashboardDialogState();
}

class _CortexDashboardDialogState extends State<_CortexDashboardDialog> {
  Timer? _pollTimer;

  // Health
  double _health = 1.0;
  bool _isDegraded = false;
  int _totalSignals = 0;
  int _totalReflexActions = 0;
  int _totalPatterns = 0;
  double _signalsPerSecond = 0;
  double _dropRate = 0;
  int _activeReflexes = 0;

  // 7 Dimensions
  double _dimThroughput = 0;
  double _dimReliability = 0;
  double _dimResponsiveness = 0;
  double _dimCoverage = 0;
  double _dimCognition = 0;
  double _dimEfficiency = 0;
  double _dimCoherence = 0;

  @override
  void initState() {
    super.initState();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    if (!mounted) return;
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;

      setState(() {
        _health = ffi.cortexGetHealth();
        _isDegraded = ffi.cortexIsDegraded();
        _totalSignals = ffi.cortexGetTotalSignals();
        _totalReflexActions = ffi.cortexGetTotalReflexActions();
        _totalPatterns = ffi.cortexGetTotalPatterns();
        _signalsPerSecond = ffi.cortexGetSignalsPerSecond();
        _dropRate = ffi.cortexGetDropRate();
        _activeReflexes = ffi.cortexGetActiveReflexCount();

        _dimThroughput = ffi.cortexGetDimension(0);
        _dimReliability = ffi.cortexGetDimension(1);
        _dimResponsiveness = ffi.cortexGetDimension(2);
        _dimCoverage = ffi.cortexGetDimension(3);
        _dimCognition = ffi.cortexGetDimension(4);
        _dimEfficiency = ffi.cortexGetDimension(5);
        _dimCoherence = ffi.cortexGetDimension(6);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForHealth(_health);
    final pct = (_health * 100).round();

    return Dialog(
      backgroundColor: const Color(0xFF12121C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ═══ HEADER ═══
              _buildHeader(color, pct),
              const SizedBox(height: 16),

              // ═══ HEALTH BAR ═══
              _buildHealthBar(color),
              const SizedBox(height: 16),

              // ═══ 7 DIMENSIONS ═══
              _buildSectionTitle('AWARENESS DIMENSIONS'),
              const SizedBox(height: 8),
              _buildDimensionRow('Throughput', _dimThroughput, Icons.speed),
              _buildDimensionRow('Reliability', _dimReliability, Icons.verified),
              _buildDimensionRow('Responsiveness', _dimResponsiveness, Icons.flash_on),
              _buildDimensionRow('Coverage', _dimCoverage, Icons.radar),
              _buildDimensionRow('Cognition', _dimCognition, Icons.psychology),
              _buildDimensionRow('Efficiency', _dimEfficiency, Icons.eco),
              _buildDimensionRow('Coherence', _dimCoherence, Icons.hub),
              const SizedBox(height: 16),

              // ═══ SIGNAL STATS ═══
              _buildSectionTitle('NEURAL ACTIVITY'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Signals', _formatNumber(_totalSignals), const Color(0xFF60A0FF))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatCard('Rate', '${_signalsPerSecond.toStringAsFixed(1)}/s', const Color(0xFF40FF90))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatCard('Drop', '${(_dropRate * 100).toStringAsFixed(1)}%',
                      _dropRate > 0.05 ? const Color(0xFFFF4060) : const Color(0xFF40FF90))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Reflexes', '$_activeReflexes active', const Color(0xFFFFD740))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatCard('Fires', _formatNumber(_totalReflexActions), const Color(0xFFFF9040))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatCard('Patterns', _formatNumber(_totalPatterns), const Color(0xFFBB80FF))),
                ],
              ),

              const SizedBox(height: 16),
              // Close
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color color, int pct) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'CORTEX Nervous System',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        if (_isDegraded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4060).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFF4060).withOpacity(0.3)),
            ),
            child: const Text(
              'DEGRADED',
              style: TextStyle(
                color: Color(0xFFFF4060),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHealthBar(Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: _health,
          backgroundColor: Colors.white.withOpacity(0.06),
          color: color,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.3),
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildDimensionRow(String label, double value, IconData icon) {
    final isAvailable = value >= 0;
    final displayValue = isAvailable ? value.clamp(0.0, 1.0) : 0.0;
    final color = isAvailable ? _colorForHealth(displayValue) : Colors.white.withOpacity(0.15);
    final pct = isAvailable ? (displayValue * 100).round() : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color.withOpacity(0.7)),
          const SizedBox(width: 6),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: displayValue,
                  backgroundColor: Colors.white.withOpacity(0.06),
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              isAvailable ? '$pct%' : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  static Color _colorForHealth(double h) {
    if (h >= 0.8) return const Color(0xFF40FF90);
    if (h >= 0.6) return const Color(0xFFFFD740);
    if (h >= 0.4) return const Color(0xFFFF9040);
    return const Color(0xFFFF4060);
  }
}
