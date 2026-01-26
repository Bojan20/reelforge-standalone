// ═══════════════════════════════════════════════════════════════════════════
// P3.7: STAGE OCCURRENCE STATISTICS — Compact occurrence display
// ═══════════════════════════════════════════════════════════════════════════
//
// Displays stage occurrence counts and statistics:
// - Per-stage occurrence count
// - Top N most frequent stages
// - Category breakdown
// - Session totals
//
library;

import 'package:flutter/material.dart';
import '../../config/stage_config.dart';
import '../../src/rust/native_ffi.dart';

/// P3.7: Occurrence data for a single stage type
class StageOccurrence {
  final String stageType;
  final int count;
  final double percentage;
  final StageCategory category;

  const StageOccurrence({
    required this.stageType,
    required this.count,
    required this.percentage,
    required this.category,
  });
}

/// P3.7: Aggregate occurrence statistics
class OccurrenceStatistics {
  final int totalOccurrences;
  final int uniqueStages;
  final List<StageOccurrence> occurrences;
  final Map<StageCategory, int> categoryTotals;

  const OccurrenceStatistics({
    required this.totalOccurrences,
    required this.uniqueStages,
    required this.occurrences,
    required this.categoryTotals,
  });

  factory OccurrenceStatistics.empty() => const OccurrenceStatistics(
        totalOccurrences: 0,
        uniqueStages: 0,
        occurrences: [],
        categoryTotals: {},
      );

  factory OccurrenceStatistics.fromStages(List<SlotLabStageEvent> stages) {
    if (stages.isEmpty) return OccurrenceStatistics.empty();

    final stageConfig = StageConfig.instance;
    final counts = <String, int>{};
    final categoryTotals = <StageCategory, int>{};

    // Count occurrences
    for (final stage in stages) {
      final stageType = stage.stageType.toLowerCase();
      counts[stageType] = (counts[stageType] ?? 0) + 1;

      final config = stageConfig.getConfig(stageType);
      final category = config?.category ?? StageCategory.custom;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + 1;
    }

    // Build occurrence list
    final total = stages.length;
    final occurrences = counts.entries.map((e) {
      final config = stageConfig.getConfig(e.key);
      return StageOccurrence(
        stageType: e.key,
        count: e.value,
        percentage: e.value / total * 100,
        category: config?.category ?? StageCategory.custom,
      );
    }).toList();

    // Sort by count descending
    occurrences.sort((a, b) => b.count.compareTo(a.count));

    return OccurrenceStatistics(
      totalOccurrences: total,
      uniqueStages: counts.length,
      occurrences: occurrences,
      categoryTotals: categoryTotals,
    );
  }

  /// Get top N most frequent stages
  List<StageOccurrence> topN(int n) {
    return occurrences.take(n).toList();
  }
}

/// P3.7: Compact occurrence badge for inline display
class StageOccurrenceBadge extends StatelessWidget {
  final List<SlotLabStageEvent> stages;
  final int topCount;

  const StageOccurrenceBadge({
    super.key,
    required this.stages,
    this.topCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    final stats = OccurrenceStatistics.fromStages(stages);

    if (stats.totalOccurrences == 0) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: '${stats.totalOccurrences} stage occurrences, '
          '${stats.uniqueStages} unique stages',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF3a3a45),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stacked_bar_chart, color: Color(0xFF4A9EFF), size: 14),
            const SizedBox(width: 4),
            Text(
              '${stats.totalOccurrences}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(${stats.uniqueStages} unique)',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// P3.7: Compact top stages row
class TopStagesRow extends StatelessWidget {
  final List<SlotLabStageEvent> stages;
  final int topCount;

  const TopStagesRow({
    super.key,
    required this.stages,
    this.topCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    final stats = OccurrenceStatistics.fromStages(stages);
    final topStages = stats.topN(topCount);

    if (topStages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'TOP:',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        ...topStages.map((occ) => _buildStageChip(occ)),
      ],
    );
  }

  Widget _buildStageChip(StageOccurrence occ) {
    final color = StageConfig.instance.getColor(occ.stageType);

    return Semantics(
      label: '${occ.stageType}: ${occ.count} times, ${occ.percentage.toStringAsFixed(1)} percent',
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '${occ.count}',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// P3.7: Category breakdown bar
class CategoryBreakdownBar extends StatelessWidget {
  final List<SlotLabStageEvent> stages;
  final double height;

  const CategoryBreakdownBar({
    super.key,
    required this.stages,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final stats = OccurrenceStatistics.fromStages(stages);

    if (stats.totalOccurrences == 0) {
      return SizedBox(height: height);
    }

    // Sort categories by count
    final sortedCategories = stats.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Semantics(
      label: 'Category breakdown: ${sortedCategories.map((e) =>
          '${e.key.name} ${e.value}').join(', ')}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Row(
            children: sortedCategories.map((entry) {
              final fraction = entry.value / stats.totalOccurrences;
              final color = getCategoryColor(entry.key);

              return Expanded(
                flex: (fraction * 1000).toInt().clamp(1, 1000),
                child: Tooltip(
                  message: '${entry.key.name}: ${entry.value} '
                      '(${(fraction * 100).toStringAsFixed(1)}%)',
                  child: Container(color: color),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// P3.7: Full statistics panel (compact)
class StageOccurrencePanel extends StatelessWidget {
  final List<SlotLabStageEvent> stages;

  const StageOccurrencePanel({
    super.key,
    required this.stages,
  });

  @override
  Widget build(BuildContext context) {
    final stats = OccurrenceStatistics.fromStages(stages);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3a3a45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Color(0xFF4A9EFF), size: 16),
              const SizedBox(width: 6),
              const Text(
                'Occurrence Stats',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              StageOccurrenceBadge(stages: stages),
            ],
          ),
          const SizedBox(height: 8),

          // Category breakdown bar
          CategoryBreakdownBar(stages: stages),
          const SizedBox(height: 8),

          // Top stages
          TopStagesRow(stages: stages, topCount: 5),
        ],
      ),
    );
  }
}
