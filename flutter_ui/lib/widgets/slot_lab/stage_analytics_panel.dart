// ═══════════════════════════════════════════════════════════════════════════
// P3.3: STAGE ANALYTICS DASHBOARD — Statistics and insights
// ═══════════════════════════════════════════════════════════════════════════
//
// Displays analytics about stage events:
// - Stage occurrence counts
// - Timing statistics (min/max/avg duration)
// - Category distribution
// - Session timeline summary
//
library;

import 'package:flutter/material.dart';
import '../../config/stage_config.dart';
import '../../src/rust/native_ffi.dart';

/// P3.3: Analytics data for a single stage type
class StageAnalytics {
  final String stageType;
  final int count;
  final double minDurationMs;
  final double maxDurationMs;
  final double avgDurationMs;
  final double totalDurationMs;
  final StageCategory category;

  const StageAnalytics({
    required this.stageType,
    required this.count,
    required this.minDurationMs,
    required this.maxDurationMs,
    required this.avgDurationMs,
    required this.totalDurationMs,
    required this.category,
  });
}

/// P3.3: Session-level analytics
class SessionAnalytics {
  final int totalStages;
  final int uniqueStages;
  final double sessionDurationMs;
  final Map<StageCategory, int> categoryDistribution;
  final List<StageAnalytics> stageStats;

  const SessionAnalytics({
    required this.totalStages,
    required this.uniqueStages,
    required this.sessionDurationMs,
    required this.categoryDistribution,
    required this.stageStats,
  });

  factory SessionAnalytics.empty() => const SessionAnalytics(
        totalStages: 0,
        uniqueStages: 0,
        sessionDurationMs: 0,
        categoryDistribution: {},
        stageStats: [],
      );

  factory SessionAnalytics.fromStages(List<SlotLabStageEvent> stages) {
    if (stages.isEmpty) return SessionAnalytics.empty();

    final stageConfig = StageConfig.instance;
    final Map<String, List<double>> stageTimes = {};
    final Map<StageCategory, int> catDistribution = {};

    // Calculate durations between consecutive stages
    for (int i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final stageType = stage.stageType.toLowerCase();
      final config = stageConfig.getConfig(stageType);
      final category = config?.category ?? StageCategory.custom;

      // Track category distribution
      catDistribution[category] = (catDistribution[category] ?? 0) + 1;

      // Calculate duration to next stage
      final duration = i < stages.length - 1
          ? stages[i + 1].timestampMs - stage.timestampMs
          : 0.0;

      stageTimes.putIfAbsent(stageType, () => []);
      stageTimes[stageType]!.add(duration);
    }

    // Build per-stage analytics
    final stageStats = <StageAnalytics>[];
    for (final entry in stageTimes.entries) {
      final times = entry.value;
      final config = stageConfig.getConfig(entry.key);

      stageStats.add(StageAnalytics(
        stageType: entry.key,
        count: times.length,
        minDurationMs: times.reduce((a, b) => a < b ? a : b),
        maxDurationMs: times.reduce((a, b) => a > b ? a : b),
        avgDurationMs: times.reduce((a, b) => a + b) / times.length,
        totalDurationMs: times.reduce((a, b) => a + b),
        category: config?.category ?? StageCategory.custom,
      ));
    }

    // Sort by count descending
    stageStats.sort((a, b) => b.count.compareTo(a.count));

    return SessionAnalytics(
      totalStages: stages.length,
      uniqueStages: stageTimes.length,
      sessionDurationMs: stages.last.timestampMs - stages.first.timestampMs,
      categoryDistribution: catDistribution,
      stageStats: stageStats,
    );
  }
}

/// P3.3: Stage Analytics Dashboard Panel
class StageAnalyticsPanel extends StatelessWidget {
  final List<SlotLabStageEvent> stages;

  const StageAnalyticsPanel({
    super.key,
    required this.stages,
  });

  @override
  Widget build(BuildContext context) {
    final analytics = SessionAnalytics.fromStages(stages);

    return Container(
      color: const Color(0xFF1a1a20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(analytics),

          // Content
          Expanded(
            child: analytics.totalStages == 0
                ? _buildEmptyState()
                : _buildContent(analytics),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(SessionAnalytics analytics) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF242430),
      child: Row(
        children: [
          const Icon(Icons.analytics, color: Color(0xFF4A9EFF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Stage Analytics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _buildMetricChip('Total', analytics.totalStages.toString()),
          const SizedBox(width: 8),
          _buildMetricChip('Unique', analytics.uniqueStages.toString()),
          const SizedBox(width: 8),
          _buildMetricChip(
            'Duration',
            '${(analytics.sessionDurationMs / 1000).toStringAsFixed(1)}s',
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3a3a45),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics_outlined, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text(
            'No stage data to analyze',
            style: TextStyle(color: Colors.white54),
          ),
          SizedBox(height: 4),
          Text(
            'Run a spin to generate stage events',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SessionAnalytics analytics) {
    return Row(
      children: [
        // Category distribution (left)
        SizedBox(
          width: 180,
          child: _buildCategoryDistribution(analytics),
        ),
        Container(width: 1, color: const Color(0xFF3a3a45)),
        // Stage list (right)
        Expanded(
          child: _buildStageList(analytics),
        ),
      ],
    );
  }

  Widget _buildCategoryDistribution(SessionAnalytics analytics) {
    final categories = analytics.categoryDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CATEGORY DISTRIBUTION',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final entry = categories[index];
                final percentage =
                    (entry.value / analytics.totalStages * 100).toStringAsFixed(1);
                final color = getCategoryColor(entry.key);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              entry.key.name.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.value} ($percentage%)',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Progress bar
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3a3a45),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: entry.value / analytics.totalStages,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageList(SessionAnalytics analytics) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: const [
              SizedBox(
                width: 24,
                child: Text('#', style: _headerStyle),
              ),
              Expanded(
                flex: 3,
                child: Text('STAGE', style: _headerStyle),
              ),
              SizedBox(
                width: 50,
                child: Text('COUNT', style: _headerStyle, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 60,
                child: Text('AVG', style: _headerStyle, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 60,
                child: Text('MIN', style: _headerStyle, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 60,
                child: Text('MAX', style: _headerStyle, textAlign: TextAlign.right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF3a3a45), height: 1),
          const SizedBox(height: 8),
          // Stage rows
          Expanded(
            child: ListView.builder(
              itemCount: analytics.stageStats.length,
              itemBuilder: (context, index) {
                final stat = analytics.stageStats[index];
                final color = StageConfig.instance.getColor(stat.stageType);

                return Semantics(
                  label: 'Stage ${stat.stageType}: ${stat.count} occurrences, '
                      'average ${stat.avgDurationMs.toStringAsFixed(0)} milliseconds, '
                      'minimum ${stat.minDurationMs.toStringAsFixed(0)} milliseconds, '
                      'maximum ${stat.maxDurationMs.toStringAsFixed(0)} milliseconds',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  stat.stageType,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text(
                            '${stat.count}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '${stat.avgDurationMs.toStringAsFixed(0)}ms',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '${stat.minDurationMs.toStringAsFixed(0)}ms',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '${stat.maxDurationMs.toStringAsFixed(0)}ms',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static const TextStyle _headerStyle = TextStyle(
    color: Colors.white54,
    fontSize: 9,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );
}
