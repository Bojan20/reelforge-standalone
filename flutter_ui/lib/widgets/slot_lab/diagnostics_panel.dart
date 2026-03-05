import 'package:flutter/material.dart';
import '../../services/diagnostics/diagnostics_service.dart';

/// Real-time health dashboard for FluxForge diagnostics system.
///
/// Shows:
/// - Overall health indicator (green/yellow/red)
/// - Run Full Check button
/// - Checkers results (expandable)
/// - Live monitor findings (scrolling)
/// - Auto-check toggle
class DiagnosticsPanel extends StatefulWidget {
  const DiagnosticsPanel({super.key});

  @override
  State<DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<DiagnosticsPanel> {
  final _diagnostics = DiagnosticsService.instance;

  @override
  void initState() {
    super.initState();
    _diagnostics.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _diagnostics.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          _buildHeader(),
          _buildToolbar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (_diagnostics.lastReport != null) ...[
                  _buildReportSection(),
                  const SizedBox(height: 12),
                ],
                if (_diagnostics.liveFindings.isNotEmpty) ...[
                  _buildLiveSection(),
                ],
                if (_diagnostics.lastReport == null &&
                    _diagnostics.liveFindings.isEmpty)
                  _buildEmptyState(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final health = _diagnostics.health;
    final color = _severityColor(health);
    final icon = _severityIcon(health);
    final label = switch (health) {
      DiagnosticSeverity.ok => 'HEALTHY',
      DiagnosticSeverity.warning => 'WARNINGS',
      DiagnosticSeverity.error => 'ERRORS',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border(bottom: BorderSide(color: color.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_diagnostics.lastReport != null) ...[
            Text(
              '${_diagnostics.lastReport!.totalChecks} checks',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _buildToolButton(
            'Run Check',
            Icons.play_arrow,
            const Color(0xFF4FC3F7),
            () {
              _diagnostics.runFullCheck();
            },
          ),
          const SizedBox(width: 4),
          _buildToolButton(
            _diagnostics.isMonitoring ? 'Stop' : 'Monitor',
            _diagnostics.isMonitoring ? Icons.stop : Icons.monitor_heart,
            _diagnostics.isMonitoring
                ? const Color(0xFFFF5252)
                : const Color(0xFF66BB6A),
            () {
              if (_diagnostics.isMonitoring) {
                _diagnostics.stopMonitoring();
              } else {
                _diagnostics.startMonitoring();
              }
            },
          ),
          const Spacer(),
          if (_diagnostics.liveFindings.isNotEmpty)
            _buildToolButton(
              'Clear',
              Icons.clear_all,
              Colors.white38,
              () => _diagnostics.clearFindings(),
            ),
        ],
      ),
    );
  }

  Widget _buildToolButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportSection() {
    final report = _diagnostics.lastReport!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Last Check',
          '${report.duration.inMilliseconds}ms',
        ),
        const SizedBox(height: 4),
        // Summary bar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              _buildCountBadge(report.errorCount, 'ERR', const Color(0xFFFF5252)),
              const SizedBox(width: 8),
              _buildCountBadge(report.warningCount, 'WARN', const Color(0xFFFFB74D)),
              const SizedBox(width: 8),
              _buildCountBadge(report.okCount, 'OK', const Color(0xFF66BB6A)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Findings list — errors first, then warnings, then OK
        ...report.errors.map(_buildFindingTile),
        ...report.warnings.map(_buildFindingTile),
        // Only show first 5 OK findings to avoid clutter
        ...report.findings
            .where((f) => f.isOk)
            .take(5)
            .map(_buildFindingTile),
        if (report.okCount > 5)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
              '... and ${report.okCount - 5} more OK checks',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLiveSection() {
    final findings = _diagnostics.liveFindings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Live Monitor', '${findings.length} findings'),
        const SizedBox(height: 4),
        ...findings.reversed.take(50).map(_buildFindingTile),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.health_and_safety_outlined,
              color: Colors.white.withOpacity(0.2),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No diagnostics yet',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Run a check or start monitoring',
              style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String? subtitle) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCountBadge(int count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: count > 0 ? color.withOpacity(0.15) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: count > 0 ? color : Colors.white.withOpacity(0.3),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFindingTile(DiagnosticFinding finding) {
    final color = _severityColor(finding.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(3),
          border: Border(left: BorderSide(color: color, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    finding.checker,
                    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                ),
                if (finding.affectedStage != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    finding.affectedStage!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${finding.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${finding.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${finding.timestamp.second.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              finding.message,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
            if (finding.detail != null) ...[
              const SizedBox(height: 2),
              Text(
                finding.detail!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _severityColor(DiagnosticSeverity severity) {
    return switch (severity) {
      DiagnosticSeverity.ok => const Color(0xFF66BB6A),
      DiagnosticSeverity.warning => const Color(0xFFFFB74D),
      DiagnosticSeverity.error => const Color(0xFFFF5252),
    };
  }

  IconData _severityIcon(DiagnosticSeverity severity) {
    return switch (severity) {
      DiagnosticSeverity.ok => Icons.check_circle,
      DiagnosticSeverity.warning => Icons.warning_amber,
      DiagnosticSeverity.error => Icons.error,
    };
  }
}
