/// CORTEX Health Indicator — reactive nervous system health in status bar
///
/// Compact widget showing CORTEX health score with color-coded indicator.
/// Taps to expand into detailed awareness dashboard overlay with:
/// - 7 awareness dimensions (throughput, reliability, responsiveness, coverage, cognition, efficiency, coherence)
/// - Signal throughput & drop rate
/// - Reflex stats
/// - Pattern recognition count
/// - Autonomic command stats
/// - Immune system status
///
/// Now powered by CortexProvider (reactive event stream) instead of polling.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cortex_provider.dart';

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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _healthColor(double health) {
    if (health >= 0.8) return const Color(0xFF40FF90); // green
    if (health >= 0.6) return const Color(0xFFFFD740); // amber
    if (health >= 0.4) return const Color(0xFFFF9040); // orange
    return const Color(0xFFFF4060); // red
  }

  void _showDetails() {
    showDialog(
      context: context,
      builder: (_) => const _CortexDashboardDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CortexProvider>(
      builder: (context, cortex, _) {
        final health = cortex.health;
        final isDegraded = cortex.isDegraded;
        final color = _healthColor(health);
        final pct = (health * 100).round();

        // Manage pulse animation based on degraded state
        if (isDegraded && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        } else if (!isDegraded && _pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.value = 1.0;
        }

        return GestureDetector(
          onTap: _showDetails,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final opacity = isDegraded ? _pulseAnimation.value : 1.0;
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
                        'CTX $pct%',
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
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX DASHBOARD DIALOG — Full Nervous System Awareness (Reactive)
// ═══════════════════════════════════════════════════════════════════════════

class _CortexDashboardDialog extends StatelessWidget {
  const _CortexDashboardDialog();

  @override
  Widget build(BuildContext context) {
    return Consumer<CortexProvider>(
      builder: (context, cortex, _) {
        final health = cortex.health;
        final color = _colorForHealth(health);
        final pct = (health * 100).round();

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
                  _buildHeader(cortex, color, pct),
                  const SizedBox(height: 16),

                  // ═══ HEALTH BAR ═══
                  _buildHealthBar(health, color),
                  const SizedBox(height: 16),

                  // ═══ 7 DIMENSIONS ═══
                  _buildSectionTitle('AWARENESS DIMENSIONS'),
                  const SizedBox(height: 8),
                  _buildDimensionRow('Throughput', cortex.dimThroughput, Icons.speed),
                  _buildDimensionRow('Reliability', cortex.dimReliability, Icons.verified),
                  _buildDimensionRow('Responsiveness', cortex.dimResponsiveness, Icons.flash_on),
                  _buildDimensionRow('Coverage', cortex.dimCoverage, Icons.radar),
                  _buildDimensionRow('Cognition', cortex.dimCognition, Icons.psychology),
                  _buildDimensionRow('Efficiency', cortex.dimEfficiency, Icons.eco),
                  _buildDimensionRow('Coherence', cortex.dimCoherence, Icons.hub),
                  const SizedBox(height: 16),

                  // ═══ SIGNAL STATS ═══
                  _buildSectionTitle('NEURAL ACTIVITY'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('Signals', _formatNumber(cortex.totalSignals), const Color(0xFF60A0FF))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Rate', '${cortex.signalsPerSecond.toStringAsFixed(1)}/s', const Color(0xFF40FF90))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Drop', '${(cortex.dropRate * 100).toStringAsFixed(1)}%',
                          cortex.dropRate > 0.05 ? const Color(0xFFFF4060) : const Color(0xFF40FF90))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('Reflexes', '${cortex.activeReflexes} active', const Color(0xFFFFD740))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Fires', _formatNumber(cortex.totalReflexActions), const Color(0xFFFF9040))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Patterns', _formatNumber(cortex.totalPatterns), const Color(0xFFBB80FF))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ═══ AUTONOMIC NERVOUS SYSTEM ═══
                  _buildSectionTitle('AUTONOMIC RESPONSE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(
                        'Dispatched',
                        _formatNumber(cortex.commandsDispatched),
                        const Color(0xFF60A0FF),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard(
                        'Executed',
                        _formatNumber(cortex.commandsExecuted),
                        cortex.commandsExecuted > 0 ? const Color(0xFF40FF90) : const Color(0xFF60A0FF),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard(
                        'Healed',
                        _formatNumber(cortex.totalHealed),
                        cortex.totalHealed > 0 ? const Color(0xFF40FF90) : const Color(0xFF60A0FF),
                      )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Healing rate bar
                  _buildHealingRateBar(cortex.healingRate),
                  const SizedBox(height: 16),

                  // ═══ IMMUNE SYSTEM ═══
                  _buildSectionTitle('IMMUNE SYSTEM'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(
                        'Anomalies',
                        '${cortex.immuneActiveCount} active',
                        cortex.immuneActiveCount > 0 ? const Color(0xFFFF9040) : const Color(0xFF40FF90),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard(
                        'Escalations',
                        _formatNumber(cortex.immuneEscalations),
                        cortex.immuneEscalations > 0 ? const Color(0xFFFFD740) : const Color(0xFF40FF90),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard(
                        'Chronic',
                        cortex.hasChronic ? 'YES' : 'None',
                        cortex.hasChronic ? const Color(0xFFFF4060) : const Color(0xFF40FF90),
                      )),
                    ],
                  ),

                  // ═══ RECENT EVENTS ═══
                  if (cortex.recentEvents.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSectionTitle('RECENT EVENTS'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: ListView.builder(
                        itemCount: cortex.recentEvents.length.clamp(0, 5),
                        itemBuilder: (context, index) {
                          final event = cortex.recentEvents[cortex.recentEvents.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              _eventLabel(event),
                              style: TextStyle(
                                color: _eventColor(event).withOpacity(0.7),
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ],

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
      },
    );
  }

  Widget _buildHeader(CortexProvider cortex, Color color, int pct) {
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
        if (cortex.isDegraded)
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

  Widget _buildHealthBar(double health, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: health,
          backgroundColor: Colors.white.withOpacity(0.06),
          color: color,
        ),
      ),
    );
  }

  Widget _buildHealingRateBar(double rate) {
    final color = rate >= 0.8
        ? const Color(0xFF40FF90)
        : rate >= 0.5
            ? const Color(0xFFFFD740)
            : const Color(0xFFFF4060);
    return Row(
      children: [
        Text(
          'Healing Rate',
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: rate.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withOpacity(0.06),
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(rate * 100).round()}%',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
              isAvailable ? '$pct%' : '\u2014',
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

  String _eventLabel(CortexEvent event) {
    switch (event.eventType) {
      case 'health_changed':
        return '\u2764 Health: ${(event.value2 * 100).round()}% \u2192 ${(event.value * 100).round()}%';
      case 'degraded_changed':
        return event.value > 0 ? '\u26a0 DEGRADED' : '\u2713 Recovered';
      case 'pattern_recognized':
        return '\u2699 Pattern: ${event.name} (${(event.value * 100).round()}%)';
      case 'reflex_fired':
        return '\u26a1 Reflex: ${event.name} (#${event.value.toInt()})';
      case 'command_dispatched':
        return '\u2192 Command: ${event.name}';
      case 'immune_escalation':
        return '\u2622 Escalation: ${event.name} L${event.value.toInt()}';
      case 'chronic_changed':
        return event.value > 0 ? '\u2622 CHRONIC' : '\u2713 Chronic resolved';
      case 'awareness_updated':
        return '\u2632 Awareness: ${(event.value * 100).round()}% health';
      case 'healing_complete':
        return event.value > 0 ? '\u2713 Healed: ${event.name}' : '\u2717 Failed: ${event.name}';
      case 'signal_milestone':
        return '\u272a Milestone: ${_formatNumber(event.value.toInt())} signals';
      default:
        return event.eventType;
    }
  }

  Color _eventColor(CortexEvent event) {
    switch (event.eventType) {
      case 'health_changed':
        return event.value >= 0.8 ? const Color(0xFF40FF90) : const Color(0xFFFFD740);
      case 'degraded_changed':
        return event.value > 0 ? const Color(0xFFFF4060) : const Color(0xFF40FF90);
      case 'pattern_recognized':
        return const Color(0xFFBB80FF);
      case 'reflex_fired':
        return const Color(0xFFFF9040);
      case 'command_dispatched':
        return const Color(0xFF60A0FF);
      case 'immune_escalation':
        return const Color(0xFFFF4060);
      case 'chronic_changed':
        return event.value > 0 ? const Color(0xFFFF4060) : const Color(0xFF40FF90);
      case 'healing_complete':
        return event.value > 0 ? const Color(0xFF40FF90) : const Color(0xFFFF4060);
      default:
        return const Color(0xFF60A0FF);
    }
  }

  static Color _colorForHealth(double h) {
    if (h >= 0.8) return const Color(0xFF40FF90);
    if (h >= 0.6) return const Color(0xFFFFD740);
    if (h >= 0.4) return const Color(0xFFFF9040);
    return const Color(0xFFFF4060);
  }
}
