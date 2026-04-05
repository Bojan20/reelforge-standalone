/// CORTEX Neural Dashboard — Full nervous system visualization panel
///
/// 5 sub-panels accessible via DAW lower zone CORTEX super-tab:
/// 1. Overview — Health radar chart + sparkline history + status summary
/// 2. Awareness — 7-dimensional awareness with animated radar visualization
/// 3. Neural — Signal flow, reflex activity, pattern recognition monitor
/// 4. Immune — Defense grid, antibodies, escalation levels, healing tracker
/// 5. Events — Live event waterfall with filtering and timeline

import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/cortex_provider.dart';
import '../../lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CORTEX COLORS — Neural system palette
// ═══════════════════════════════════════════════════════════════════════════════

class _CortexColors {
  _CortexColors._();

  static const bg = Color(0xFF0A0A14);
  static const surface = Color(0xFF12121E);
  static const border = Color(0xFF1E1E30);
  static const textDim = Color(0x59FFFFFF); // 35%
  static const textMuted = Color(0x80FFFFFF); // 50%
  static const textLight = Color(0xE6FFFFFF); // 90%

  static const neuralPink = Color(0xFFFF60B0);
  static const healthGreen = Color(0xFF40FF90);
  static const warningAmber = Color(0xFFFFD740);
  static const dangerRed = Color(0xFFFF4060);
  static const signalBlue = Color(0xFF60A0FF);
  static const patternPurple = Color(0xFFBB80FF);
  static const reflexOrange = Color(0xFFFF9040);
  static const immuneCyan = Color(0xFF40E8FF);

  static Color forHealth(double h) {
    if (h >= 0.8) return healthGreen;
    if (h >= 0.6) return warningAmber;
    if (h >= 0.4) return reflexOrange;
    return dangerRed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN DASHBOARD — Routes to sub-panels
// ═══════════════════════════════════════════════════════════════════════════════

class CortexNeuralDashboard extends StatelessWidget {
  final DawCortexSubTab subTab;

  const CortexNeuralDashboard({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _CortexColors.bg,
      child: switch (subTab) {
        DawCortexSubTab.overview => const _OverviewPanel(),
        DawCortexSubTab.awareness => const _AwarenessPanel(),
        DawCortexSubTab.neural => const _NeuralPanel(),
        DawCortexSubTab.immune => const _ImmunePanel(),
        DawCortexSubTab.events => const _EventsPanel(),
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 1. OVERVIEW PANEL — Radar chart + Health sparkline + Status summary
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewPanel extends StatefulWidget {
  const _OverviewPanel();

  @override
  State<_OverviewPanel> createState() => _OverviewPanelState();
}

class _OverviewPanelState extends State<_OverviewPanel> {
  final List<double> _healthHistory = [];
  static const int _maxHistory = 120; // 120 * 200ms = 24 seconds of history
  StreamSubscription<CortexEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final cortex = context.read<CortexProvider>();
    _healthHistory.add(cortex.health);
    _sub = cortex.eventStream.listen((event) {
      if (event.isHealthChanged || event.isAwarenessUpdated) {
        setState(() {
          _healthHistory.add(cortex.health);
          if (_healthHistory.length > _maxHistory) {
            _healthHistory.removeAt(0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CortexProvider>(
      builder: (context, cortex, _) {
        // Keep history updated even without events
        if (_healthHistory.isEmpty || _healthHistory.last != cortex.health) {
          _healthHistory.add(cortex.health);
          if (_healthHistory.length > _maxHistory) {
            _healthHistory.removeAt(0);
          }
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT — Radar chart (7 dimensions)
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _sectionTitle('AWARENESS RADAR'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: CustomPaint(
                        painter: _AwarenessRadarPainter(
                          dimensions: [
                            cortex.dimThroughput,
                            cortex.dimReliability,
                            cortex.dimResponsiveness,
                            cortex.dimCoverage,
                            cortex.dimCognition,
                            cortex.dimEfficiency,
                            cortex.dimCoherence,
                          ],
                          labels: ['THR', 'REL', 'RSP', 'COV', 'COG', 'EFF', 'COH'],
                          health: cortex.health,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // CENTER — Health sparkline + Status
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('HEALTH TIMELINE'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: CustomPaint(
                        painter: _HealthSparklinePainter(
                          values: _healthHistory,
                          currentHealth: cortex.health,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Status cards row
                    _sectionTitle('VITAL SIGNS'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildVitalSigns(cortex),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // RIGHT — Status summary
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('ORGANISM STATUS'),
                    const SizedBox(height: 8),
                    _buildOrganismStatus(cortex),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVitalSigns(CortexProvider cortex) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _vitalCard('Health', '${(cortex.health * 100).round()}%',
            _CortexColors.forHealth(cortex.health)),
        _vitalCard('Signals', _fmt(cortex.totalSignals), _CortexColors.signalBlue),
        _vitalCard('Rate', '${cortex.signalsPerSecond.toStringAsFixed(1)}/s',
            _CortexColors.healthGreen),
        _vitalCard('Drop', '${(cortex.dropRate * 100).toStringAsFixed(1)}%',
            cortex.dropRate > 0.05 ? _CortexColors.dangerRed : _CortexColors.healthGreen),
        _vitalCard('Reflexes', '${cortex.activeReflexes}', _CortexColors.reflexOrange),
        _vitalCard('Patterns', _fmt(cortex.totalPatterns), _CortexColors.patternPurple),
        _vitalCard('Healed', _fmt(cortex.totalHealed), _CortexColors.immuneCyan),
        _vitalCard('Immune', '${cortex.immuneActiveCount}',
            cortex.immuneActiveCount > 0 ? _CortexColors.dangerRed : _CortexColors.healthGreen),
      ],
    );
  }

  Widget _buildOrganismStatus(CortexProvider cortex) {
    final statusColor = _CortexColors.forHealth(cortex.health);
    final statusLabel = switch (cortex.status) {
      CortexStatus.healthy => 'HEALTHY',
      CortexStatus.warning => 'WARNING',
      CortexStatus.degraded => 'DEGRADED',
      CortexStatus.critical => 'CRITICAL',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Big status indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (cortex.isDegraded)
          _statusLine(Icons.warning_amber, 'Degraded state active', _CortexColors.dangerRed),
        if (cortex.hasChronic)
          _statusLine(Icons.error_outline, 'Chronic condition detected', _CortexColors.dangerRed),
        if (cortex.immuneActiveCount > 0)
          _statusLine(Icons.shield, '${cortex.immuneActiveCount} active anomalies',
              _CortexColors.reflexOrange),
        if (cortex.healingRate < 1.0)
          _statusLine(Icons.healing, 'Healing: ${(cortex.healingRate * 100).round()}%',
              _CortexColors.warningAmber),
        _statusLine(Icons.bolt, '${_fmt(cortex.totalReflexActions)} reflex fires',
            _CortexColors.reflexOrange),
        _statusLine(Icons.send, '${_fmt(cortex.commandsDispatched)} commands dispatched',
            _CortexColors.signalBlue),
        _statusLine(Icons.check_circle_outline, '${_fmt(cortex.commandsExecuted)} executed',
            _CortexColors.healthGreen),
      ],
    );
  }

  Widget _statusLine(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color.withOpacity(0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. AWARENESS PANEL — 7-dimension deep dive with animated radar
// ═══════════════════════════════════════════════════════════════════════════════

class _AwarenessPanel extends StatelessWidget {
  const _AwarenessPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<CortexProvider>(
      builder: (context, cortex, _) {
        final dims = [
          _DimInfo('Throughput', cortex.dimThroughput, Icons.speed,
              'Signal processing capacity and bandwidth utilization'),
          _DimInfo('Reliability', cortex.dimReliability, Icons.verified,
              'Error-free operation rate and consistency'),
          _DimInfo('Responsiveness', cortex.dimResponsiveness, Icons.flash_on,
              'Reaction time to signals and events'),
          _DimInfo('Coverage', cortex.dimCoverage, Icons.radar,
              'Monitoring reach across subsystems'),
          _DimInfo('Cognition', cortex.dimCognition, Icons.psychology,
              'Pattern recognition and learning capability'),
          _DimInfo('Efficiency', cortex.dimEfficiency, Icons.eco,
              'Resource utilization relative to output'),
          _DimInfo('Coherence', cortex.dimCoherence, Icons.hub,
              'Internal consistency across all dimensions'),
        ];

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT — Large radar
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _sectionTitle('AWARENESS DIMENSIONS'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: CustomPaint(
                        painter: _AwarenessRadarPainter(
                          dimensions: dims.map((d) => d.value).toList(),
                          labels: ['THR', 'REL', 'RSP', 'COV', 'COG', 'EFF', 'COH'],
                          health: cortex.health,
                          showGrid: true,
                          showValues: true,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // RIGHT — Dimension details
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('DIMENSION DETAILS'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: dims.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) => _buildDimensionDetail(dims[i]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDimensionDetail(_DimInfo dim) {
    final isAvailable = dim.value >= 0;
    final displayValue = isAvailable ? dim.value.clamp(0.0, 1.0) : 0.0;
    final color = isAvailable ? _CortexColors.forHealth(displayValue) : _CortexColors.textDim;
    final pct = isAvailable ? (displayValue * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(dim.icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                dim.label,
                style: TextStyle(
                  color: _CortexColors.textLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                isAvailable ? '$pct%' : '\u2014',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
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
          const SizedBox(height: 4),
          Text(
            dim.description,
            style: TextStyle(
              color: _CortexColors.textDim,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _DimInfo {
  final String label;
  final double value;
  final IconData icon;
  final String description;
  const _DimInfo(this.label, this.value, this.icon, this.description);
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. NEURAL PANEL — Signal flow, reflex activity, pattern recognition
// ═══════════════════════════════════════════════════════════════════════════════

class _NeuralPanel extends StatefulWidget {
  const _NeuralPanel();

  @override
  State<_NeuralPanel> createState() => _NeuralPanelState();
}

class _NeuralPanelState extends State<_NeuralPanel> {
  final List<double> _signalRateHistory = [];
  final List<double> _dropRateHistory = [];
  static const int _maxHistory = 120;
  StreamSubscription<CortexEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final cortex = context.read<CortexProvider>();
    _signalRateHistory.add(cortex.signalsPerSecond);
    _dropRateHistory.add(cortex.dropRate);
    _sub = cortex.eventStream.listen((_) {
      if (mounted) {
        setState(() {
          _signalRateHistory.add(cortex.signalsPerSecond);
          _dropRateHistory.add(cortex.dropRate);
          if (_signalRateHistory.length > _maxHistory) {
            _signalRateHistory.removeAt(0);
          }
          if (_dropRateHistory.length > _maxHistory) {
            _dropRateHistory.removeAt(0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CortexProvider>(
      builder: (context, cortex, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT — Signal rate sparkline + Drop rate sparkline
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('SIGNAL THROUGHPUT'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 70,
                      child: CustomPaint(
                        painter: _SignalRateSparklinePainter(
                          values: _signalRateHistory,
                          color: _CortexColors.signalBlue,
                          label: '${cortex.signalsPerSecond.toStringAsFixed(1)}/s',
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionTitle('DROP RATE'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: CustomPaint(
                        painter: _SignalRateSparklinePainter(
                          values: _dropRateHistory,
                          color: _dropRateHistory.isNotEmpty && _dropRateHistory.last > 0.05
                              ? _CortexColors.dangerRed
                              : _CortexColors.healthGreen,
                          label: '${(cortex.dropRate * 100).toStringAsFixed(1)}%',
                          maxValue: 0.2,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionTitle('NEURAL STATS'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildNeuralStats(cortex),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // RIGHT — Reflex & Pattern monitor
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('REFLEX ARC'),
                    const SizedBox(height: 8),
                    _statRow('Active Reflexes', '${cortex.activeReflexes}',
                        _CortexColors.reflexOrange),
                    _statRow('Total Fires', _fmt(cortex.totalReflexActions),
                        _CortexColors.reflexOrange),
                    const SizedBox(height: 16),
                    _sectionTitle('PATTERN RECOGNITION'),
                    const SizedBox(height: 8),
                    _statRow('Detected', _fmt(cortex.totalPatterns),
                        _CortexColors.patternPurple),
                    const SizedBox(height: 16),
                    _sectionTitle('AUTONOMIC COMMANDS'),
                    const SizedBox(height: 8),
                    _statRow('Dispatched', _fmt(cortex.commandsDispatched),
                        _CortexColors.signalBlue),
                    _statRow('Executed', _fmt(cortex.commandsExecuted),
                        _CortexColors.healthGreen),
                    if (cortex.commandsDispatched > 0)
                      _statRow(
                        'Success Rate',
                        '${(cortex.commandsExecuted / cortex.commandsDispatched * 100).round()}%',
                        _CortexColors.healthGreen,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNeuralStats(CortexProvider cortex) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _vitalCard('Total Signals', _fmt(cortex.totalSignals), _CortexColors.signalBlue),
        _vitalCard('Signal Rate', '${cortex.signalsPerSecond.toStringAsFixed(1)}/s',
            _CortexColors.healthGreen),
        _vitalCard('Drop Rate', '${(cortex.dropRate * 100).toStringAsFixed(1)}%',
            cortex.dropRate > 0.05 ? _CortexColors.dangerRed : _CortexColors.healthGreen),
        _vitalCard('Alive', cortex.isAlive ? 'YES' : 'NO',
            cortex.isAlive ? _CortexColors.healthGreen : _CortexColors.dangerRed),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. IMMUNE PANEL — Defense grid, antibodies, escalation, healing
// ═══════════════════════════════════════════════════════════════════════════════

class _ImmunePanel extends StatelessWidget {
  const _ImmunePanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<CortexProvider>(
      builder: (context, cortex, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT — Defense status
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('IMMUNE DEFENSE STATUS'),
                    const SizedBox(height: 12),
                    // Defense grid visualization
                    Expanded(
                      child: CustomPaint(
                        painter: _ImmuneGridPainter(
                          activeCount: cortex.immuneActiveCount,
                          escalations: cortex.immuneEscalations,
                          hasChronic: cortex.hasChronic,
                          healingRate: cortex.healingRate,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // RIGHT — Stats and healing
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('DEFENSE METRICS'),
                    const SizedBox(height: 8),
                    _immuneStatCard(
                      'Active Anomalies',
                      '${cortex.immuneActiveCount}',
                      cortex.immuneActiveCount > 0 ? _CortexColors.dangerRed : _CortexColors.healthGreen,
                      cortex.immuneActiveCount > 0 ? Icons.warning : Icons.check_circle,
                    ),
                    const SizedBox(height: 8),
                    _immuneStatCard(
                      'Escalations',
                      _fmt(cortex.immuneEscalations),
                      cortex.immuneEscalations > 0 ? _CortexColors.warningAmber : _CortexColors.healthGreen,
                      Icons.trending_up,
                    ),
                    const SizedBox(height: 8),
                    _immuneStatCard(
                      'Chronic Status',
                      cortex.hasChronic ? 'ACTIVE' : 'Clear',
                      cortex.hasChronic ? _CortexColors.dangerRed : _CortexColors.healthGreen,
                      cortex.hasChronic ? Icons.error : Icons.check,
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('HEALING'),
                    const SizedBox(height: 8),
                    _buildHealingBar(cortex.healingRate),
                    const SizedBox(height: 8),
                    _statRow('Total Healed', _fmt(cortex.totalHealed),
                        _CortexColors.healthGreen),
                    _statRow('Commands Executed', _fmt(cortex.commandsExecuted),
                        _CortexColors.signalBlue),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHealingBar(double rate) {
    final color = _CortexColors.forHealth(rate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Healing Rate',
              style: TextStyle(color: _CortexColors.textMuted, fontSize: 11),
            ),
            const Spacer(),
            Text(
              '${(rate * 100).round()}%',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: rate.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.06),
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

Widget _immuneStatCard(String label, String value, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.15)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: _CortexColors.textMuted, fontSize: 11),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5. EVENTS PANEL — Live event waterfall with filtering
// ═══════════════════════════════════════════════════════════════════════════════

class _EventsPanel extends StatefulWidget {
  const _EventsPanel();

  @override
  State<_EventsPanel> createState() => _EventsPanelState();
}

class _EventsPanelState extends State<_EventsPanel> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    return Consumer<CortexProvider>(
      builder: (context, cortex, _) {
        final events = cortex.recentEvents.reversed.toList();
        final filtered = _filter == null
            ? events
            : events.where((e) => e.eventType == _filter).toList();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filter bar
              Row(
                children: [
                  _sectionTitle('EVENT STREAM'),
                  const SizedBox(width: 12),
                  Text(
                    '${filtered.length} events',
                    style: TextStyle(color: _CortexColors.textDim, fontSize: 10),
                  ),
                  const Spacer(),
                  _filterChip('ALL', null),
                  _filterChip('HEALTH', 'health_changed'),
                  _filterChip('REFLEX', 'reflex_fired'),
                  _filterChip('PATTERN', 'pattern_recognized'),
                  _filterChip('IMMUNE', 'immune_escalation'),
                  _filterChip('HEAL', 'healing_complete'),
                ],
              ),
              const SizedBox(height: 8),
              // Event list
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No events yet',
                          style: TextStyle(color: _CortexColors.textDim, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _buildEventRow(filtered[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, String? eventType) {
    final isActive = _filter == eventType;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: GestureDetector(
        onTap: () => setState(() => _filter = eventType),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isActive
                ? _CortexColors.neuralPink.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                  ? _CortexColors.neuralPink.withOpacity(0.4)
                  : _CortexColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? _CortexColors.neuralPink : _CortexColors.textDim,
              fontSize: 9,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventRow(CortexEvent event) {
    final color = _eventColor(event);
    final icon = _eventIcon(event);
    final label = _eventLabel(event);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(icon, size: 10, color: color.withOpacity(0.6)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              event.eventType.replaceAll('_', ' ').toUpperCase(),
              style: TextStyle(
                color: color.withOpacity(0.6),
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _CortexColors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _eventLabel(CortexEvent event) {
    return switch (event.eventType) {
      'health_changed' => '${(event.value2 * 100).round()}% \u2192 ${(event.value * 100).round()}%',
      'degraded_changed' => event.value > 0 ? 'DEGRADED' : 'Recovered',
      'pattern_recognized' => '${event.name} (${(event.value * 100).round()}%)',
      'reflex_fired' => '${event.name} #${event.value.toInt()}',
      'command_dispatched' => event.name,
      'immune_escalation' => '${event.name} L${event.value.toInt()}',
      'chronic_changed' => event.value > 0 ? 'CHRONIC' : 'Resolved',
      'awareness_updated' => '${(event.value * 100).round()}% health',
      'healing_complete' => event.value > 0 ? 'Healed: ${event.name}' : 'Failed: ${event.name}',
      'signal_milestone' => '${_fmt(event.value.toInt())} signals',
      _ => event.eventType,
    };
  }

  Color _eventColor(CortexEvent event) {
    return switch (event.eventType) {
      'health_changed' => _CortexColors.forHealth(event.value),
      'degraded_changed' => event.value > 0 ? _CortexColors.dangerRed : _CortexColors.healthGreen,
      'pattern_recognized' => _CortexColors.patternPurple,
      'reflex_fired' => _CortexColors.reflexOrange,
      'command_dispatched' => _CortexColors.signalBlue,
      'immune_escalation' => _CortexColors.dangerRed,
      'chronic_changed' => event.value > 0 ? _CortexColors.dangerRed : _CortexColors.healthGreen,
      'healing_complete' => event.value > 0 ? _CortexColors.healthGreen : _CortexColors.dangerRed,
      _ => _CortexColors.signalBlue,
    };
  }

  IconData _eventIcon(CortexEvent event) {
    return switch (event.eventType) {
      'health_changed' => Icons.favorite,
      'degraded_changed' => Icons.warning_amber,
      'pattern_recognized' => Icons.hub,
      'reflex_fired' => Icons.bolt,
      'command_dispatched' => Icons.send,
      'immune_escalation' => Icons.shield,
      'chronic_changed' => Icons.error,
      'healing_complete' => Icons.healing,
      'signal_milestone' => Icons.star,
      _ => Icons.circle,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

/// 7-Dimensional Awareness Radar Chart
class _AwarenessRadarPainter extends CustomPainter {
  final List<double> dimensions;
  final List<String> labels;
  final double health;
  final bool showGrid;
  final bool showValues;

  _AwarenessRadarPainter({
    required this.dimensions,
    required this.labels,
    required this.health,
    this.showGrid = false,
    this.showValues = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 30;
    final n = dimensions.length;
    if (n == 0 || radius <= 0) return;

    final angleStep = 2 * math.pi / n;
    final startAngle = -math.pi / 2; // Start from top

    // Draw grid rings
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withOpacity(0.06);

    for (int ring = 1; ring <= 5; ring++) {
      final r = radius * ring / 5;
      final path = Path();
      for (int i = 0; i <= n; i++) {
        final angle = startAngle + angleStep * (i % n);
        final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, gridPaint);
    }

    // Draw axis lines
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withOpacity(0.08);

    for (int i = 0; i < n; i++) {
      final angle = startAngle + angleStep * i;
      final end = Offset(center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle));
      canvas.drawLine(center, end, axisPaint);
    }

    // Draw filled shape
    final fillColor = _CortexColors.forHealth(health);
    final fillPath = Path();
    for (int i = 0; i <= n; i++) {
      final idx = i % n;
      final value = (dimensions[idx].clamp(0.0, 1.0));
      final angle = startAngle + angleStep * idx;
      final r = radius * value;
      final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
      if (i == 0) {
        fillPath.moveTo(p.dx, p.dy);
      } else {
        fillPath.lineTo(p.dx, p.dy);
      }
    }

    // Fill with gradient
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor.withOpacity(0.15);
    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = fillColor.withOpacity(0.7);
    canvas.drawPath(fillPath, strokePaint);

    // Draw dots at vertices
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    for (int i = 0; i < n; i++) {
      final value = dimensions[i].clamp(0.0, 1.0);
      final angle = startAngle + angleStep * i;
      final r = radius * value;
      final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
      canvas.drawCircle(p, 3, dotPaint);

      // Glow
      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor.withOpacity(0.2);
      canvas.drawCircle(p, 6, glowPaint);
    }

    // Draw labels
    for (int i = 0; i < n; i++) {
      final angle = startAngle + angleStep * i;
      final labelR = radius + 18;
      final p = Offset(center.dx + labelR * math.cos(angle),
          center.dy + labelR * math.sin(angle));

      final tp = TextPainter(
        text: TextSpan(
          text: showValues
              ? '${labels[i]} ${(dimensions[i].clamp(0.0, 1.0) * 100).round()}%'
              : labels[i],
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _AwarenessRadarPainter old) {
    if (old.health != health) return true;
    for (int i = 0; i < dimensions.length; i++) {
      if ((old.dimensions[i] - dimensions[i]).abs() > 0.01) return true;
    }
    return false;
  }
}

/// Health sparkline — time-series of health score
class _HealthSparklinePainter extends CustomPainter {
  final List<double> values;
  final double currentHealth;

  _HealthSparklinePainter({required this.values, required this.currentHealth});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final n = values.length;
    final w = size.width;
    final h = size.height;

    // Background threshold zones
    _drawThresholdZone(canvas, size, 0.8, 1.0, _CortexColors.healthGreen.withOpacity(0.03));
    _drawThresholdZone(canvas, size, 0.6, 0.8, _CortexColors.warningAmber.withOpacity(0.03));
    _drawThresholdZone(canvas, size, 0.0, 0.6, _CortexColors.dangerRed.withOpacity(0.03));

    // Threshold lines
    final threshPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withOpacity(0.08);
    canvas.drawLine(Offset(0, h * 0.2), Offset(w, h * 0.2), threshPaint); // 80%
    canvas.drawLine(Offset(0, h * 0.4), Offset(w, h * 0.4), threshPaint); // 60%

    // Draw sparkline
    final path = Path();
    final fillPath = Path();
    fillPath.moveTo(0, h);

    for (int i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : (i / (n - 1)) * w;
      final y = h - (values[i].clamp(0.0, 1.0) * h);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(w, h);
    fillPath.close();

    // Fill gradient
    final color = _CortexColors.forHealth(currentHealth);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.15), color.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withOpacity(0.8);
    canvas.drawPath(path, strokePaint);

    // Current value dot
    if (n > 0) {
      final lastX = n == 1 ? w / 2 : w;
      final lastY = h - (values.last.clamp(0.0, 1.0) * h);
      canvas.drawCircle(Offset(lastX, lastY), 3, Paint()..color = color);
      canvas.drawCircle(
          Offset(lastX, lastY), 6, Paint()..color = color.withOpacity(0.2));

      // Value label
      final tp = TextPainter(
        text: TextSpan(
          text: '${(currentHealth * 100).round()}%',
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(lastX - tp.width - 8, lastY - tp.height / 2));
    }
  }

  void _drawThresholdZone(Canvas canvas, Size size, double from, double to, Color color) {
    final rect = Rect.fromLTRB(
      0, size.height * (1 - to),
      size.width, size.height * (1 - from),
    );
    canvas.drawRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HealthSparklinePainter old) =>
      old.values.length != values.length || old.currentHealth != currentHealth;
}

/// Signal rate sparkline — generic time-series
class _SignalRateSparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final String label;
  final double? maxValue;

  _SignalRateSparklinePainter({
    required this.values,
    required this.color,
    required this.label,
    this.maxValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final n = values.length;
    final w = size.width;
    final h = size.height;

    // Auto-scale or use provided max
    final max = maxValue ?? (values.reduce(math.max).clamp(1.0, double.infinity));

    // Draw sparkline
    final path = Path();
    final fillPath = Path();
    fillPath.moveTo(0, h);

    for (int i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : (i / (n - 1)) * w;
      final y = h - ((values[i] / max).clamp(0.0, 1.0) * h);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(w, h);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.1), color.withOpacity(0.01)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withOpacity(0.7));

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(w - tp.width - 4, 2));
  }

  @override
  bool shouldRepaint(covariant _SignalRateSparklinePainter old) =>
      old.values.length != values.length || old.color != color;
}

/// Immune System defense grid visualization
class _ImmuneGridPainter extends CustomPainter {
  final int activeCount;
  final int escalations;
  final bool hasChronic;
  final double healingRate;

  _ImmuneGridPainter({
    required this.activeCount,
    required this.escalations,
    required this.hasChronic,
    required this.healingRate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw hexagonal defense grid
    const cols = 8;
    const rows = 5;
    final cellW = w / cols;
    final cellH = h / rows;
    final cellR = math.min(cellW, cellH) * 0.4;

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withOpacity(0.06);

    final activePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _CortexColors.dangerRed.withOpacity(0.3);

    final healthyPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _CortexColors.healthGreen.withOpacity(0.06);

    final healingPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _CortexColors.immuneCyan.withOpacity(0.15);

    final chronicPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _CortexColors.dangerRed.withOpacity(0.5);

    int cellIndex = 0;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final offset = (row % 2 == 1) ? cellW / 2 : 0.0;
        final cx = cellW / 2 + col * cellW + offset;
        final cy = cellH / 2 + row * cellH;

        if (cx > w + cellR || cy > h + cellR) continue;

        // Draw hexagon
        final hexPath = _hexPath(cx, cy, cellR);

        // Choose fill based on status
        if (hasChronic && cellIndex == 0) {
          canvas.drawPath(hexPath, chronicPaint);
        } else if (cellIndex < activeCount) {
          canvas.drawPath(hexPath, activePaint);
        } else if (cellIndex < activeCount + (healingRate * 5).round()) {
          canvas.drawPath(hexPath, healingPaint);
        } else {
          canvas.drawPath(hexPath, healthyPaint);
        }

        canvas.drawPath(hexPath, gridPaint);
        cellIndex++;
      }
    }

    // Legend
    _drawLegend(canvas, size);
  }

  Path _hexPath(double cx, double cy, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  void _drawLegend(Canvas canvas, Size size) {
    const legends = [
      ('Healthy', _CortexColors.healthGreen),
      ('Active', _CortexColors.dangerRed),
      ('Healing', _CortexColors.immuneCyan),
      ('Chronic', _CortexColors.dangerRed),
    ];

    double x = 8;
    final y = size.height - 16;

    for (final (label, color) in legends) {
      canvas.drawCircle(Offset(x + 4, y + 4), 3, Paint()..color = color.withOpacity(0.6));
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x + 10, y));
      x += tp.width + 20;
    }
  }

  @override
  bool shouldRepaint(covariant _ImmuneGridPainter old) =>
      old.activeCount != activeCount ||
      old.escalations != escalations ||
      old.hasChronic != hasChronic ||
      old.healingRate != healingRate;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS — Used across sub-panels
// ═══════════════════════════════════════════════════════════════════════════════

Widget _sectionTitle(String title) {
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

Widget _vitalCard(String label, String value, Color color) {
  return Container(
    width: 100,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Widget _statRow(String label, String value, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(color: _CortexColors.textMuted, fontSize: 11),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}
