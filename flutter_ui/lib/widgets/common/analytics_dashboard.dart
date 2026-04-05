/// Analytics Dashboard Widget
///
/// Visual dashboard for usage metrics and performance data.
///
/// P3-07: Analytics Dashboard UI (~400 LOC)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';

/// Analytics dashboard panel
class AnalyticsDashboard extends StatefulWidget {
  const AnalyticsDashboard({super.key});

  @override
  State<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends State<AnalyticsDashboard> {
  final _analytics = AnalyticsService.instance;
  late StreamSubscription<AnalyticsEvent> _subscription;
  Timer? _refreshTimer;

  SessionStats? _sessionStats;
  AggregatedMetrics? _metrics;
  List<MapEntry<String, int>> _topFeatures = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _subscription = _analytics.eventStream.listen((_) => _refresh());
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _sessionStats = _analytics.getSessionStats();
      _metrics = _analytics.getAggregatedMetrics();
      _topFeatures = _analytics.getTopFeatures(limit: 8);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121216),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSessionCard(),
                  const SizedBox(height: 16),
                  _buildMetricsGrid(),
                  const SizedBox(height: 16),
                  _buildTopFeaturesCard(),
                  const SizedBox(height: 16),
                  _buildEventTypesCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a20),
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a30))),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics, color: Color(0xFF40c8ff), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Analytics Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          // Enable/Disable toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _analytics.enabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                  color: _analytics.enabled
                      ? const Color(0xFF40ff90)
                      : const Color(0xFF888888),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _analytics.enabled,
                onChanged: (v) {
                  _analytics.setEnabled(v);
                  _refresh();
                },
                activeColor: const Color(0xFF40ff90),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            color: const Color(0xFF888888),
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 18),
            color: const Color(0xFF888888),
            tooltip: 'Export JSON',
            onPressed: () {
              final json = _analytics.exportJson();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exported ${json.length} bytes')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard() {
    final stats = _sessionStats;
    if (stats == null) return const SizedBox.shrink();

    return _buildCard(
      title: 'Current Session',
      icon: Icons.access_time,
      iconColor: const Color(0xFF40ff90),
      child: Row(
        children: [
          _buildStatItem('Duration', _formatDuration(stats.activeTime)),
          _buildStatItem('Events', stats.eventsCount.toString()),
          _buildStatItem('Features', stats.featuresUsed.toString()),
          _buildStatItem('Errors', stats.errorsCount.toString(),
              valueColor: stats.errorsCount > 0 ? const Color(0xFFff6b6b) : null),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final metrics = _metrics;
    if (metrics == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Total Sessions',
            value: metrics.totalSessions.toString(),
            icon: Icons.login,
            color: const Color(0xFF4a9eff),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'Total Events',
            value: metrics.totalEvents.toString(),
            icon: Icons.event_note,
            color: const Color(0xFFff9040),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'Total Errors',
            value: metrics.totalErrors.toString(),
            icon: Icons.error_outline,
            color: metrics.totalErrors > 0
                ? const Color(0xFFff6b6b)
                : const Color(0xFF40ff90),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopFeaturesCard() {
    if (_topFeatures.isEmpty) {
      return _buildCard(
        title: 'Top Features',
        icon: Icons.star,
        iconColor: const Color(0xFFffd700),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No feature usage data yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    final maxValue = _topFeatures.first.value.toDouble();

    return _buildCard(
      title: 'Top Features',
      icon: Icons.star,
      iconColor: const Color(0xFFffd700),
      child: Column(
        children: _topFeatures.map((entry) {
          final percent = maxValue > 0 ? entry.value / maxValue : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    entry.key,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0a0a0c),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: percent,
                        child: Container(
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4a9eff),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    entry.value.toString(),
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEventTypesCard() {
    final metrics = _metrics;
    if (metrics == null) return const SizedBox.shrink();

    final types = metrics.eventsByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _buildCard(
      title: 'Events by Type',
      icon: Icons.pie_chart,
      iconColor: const Color(0xFF9370db),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: types.take(12).map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _getTypeColor(entry.key).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _getTypeColor(entry.key).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    color: _getTypeColor(entry.key),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _getTypeColor(entry.key),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.value.toString(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2a2a30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2a2a30)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF4a9eff),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else {
      return '${d.inSeconds}s';
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'sessionStart':
      case 'sessionEnd':
        return const Color(0xFF40ff90);
      case 'featureUsed':
        return const Color(0xFF4a9eff);
      case 'tabOpened':
      case 'panelExpanded':
        return const Color(0xFFff9040);
      case 'audioImported':
      case 'audioExported':
      case 'audioPlayed':
        return const Color(0xFF9370db);
      case 'projectCreated':
      case 'projectOpened':
      case 'projectSaved':
        return const Color(0xFF40c8ff);
      case 'renderTime':
      case 'ffiLatency':
      case 'memoryUsage':
        return const Color(0xFFffd700);
      case 'errorOccurred':
      case 'warningLogged':
        return const Color(0xFFff6b6b);
      default:
        return const Color(0xFF888888);
    }
  }
}
