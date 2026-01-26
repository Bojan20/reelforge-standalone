// ═══════════════════════════════════════════════════════════════════════════
// P3.4: STAGE TRACE COMPARATOR — Side-by-side trace comparison
// ═══════════════════════════════════════════════════════════════════════════
//
// Compares two stage traces to identify differences:
// - Missing stages in either trace
// - Timing differences
// - Order differences
//
library;

import 'package:flutter/material.dart';
import '../../config/stage_config.dart';
import '../../src/rust/native_ffi.dart';

/// P3.4: Comparison result for a single stage
enum StageCompareResult {
  match,      // Present in both with similar timing
  onlyInA,    // Only present in trace A
  onlyInB,    // Only present in trace B
  timingDiff, // Present in both but different timing
}

/// P3.4: Compared stage entry
class ComparedStage {
  final String stageType;
  final double? timestampA;
  final double? timestampB;
  final StageCompareResult result;

  const ComparedStage({
    required this.stageType,
    this.timestampA,
    this.timestampB,
    required this.result,
  });

  double? get timingDifference {
    if (timestampA != null && timestampB != null) {
      return (timestampB! - timestampA!).abs();
    }
    return null;
  }
}

/// P3.4: Stage Trace Comparator Widget
class StageTraceComparator extends StatelessWidget {
  final List<SlotLabStageEvent> traceA;
  final List<SlotLabStageEvent> traceB;
  final String labelA;
  final String labelB;

  const StageTraceComparator({
    super.key,
    required this.traceA,
    required this.traceB,
    this.labelA = 'Trace A',
    this.labelB = 'Trace B',
  });

  @override
  Widget build(BuildContext context) {
    final comparison = _compareTraces();

    return Container(
      color: const Color(0xFF1a1a20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(comparison),
          Expanded(
            child: comparison.isEmpty
                ? _buildEmptyState()
                : _buildComparisonList(comparison),
          ),
        ],
      ),
    );
  }

  List<ComparedStage> _compareTraces() {
    final result = <ComparedStage>[];

    // Build maps by stage type
    final mapA = <String, double>{};
    final mapB = <String, double>{};

    for (final stage in traceA) {
      final key = stage.stageType.toLowerCase();
      mapA[key] = stage.timestampMs;
    }

    for (final stage in traceB) {
      final key = stage.stageType.toLowerCase();
      mapB[key] = stage.timestampMs;
    }

    // Find all unique stage types
    final allStages = {...mapA.keys, ...mapB.keys}.toList()..sort();

    for (final stageType in allStages) {
      final inA = mapA.containsKey(stageType);
      final inB = mapB.containsKey(stageType);

      StageCompareResult compareResult;
      if (inA && inB) {
        final diff = (mapA[stageType]! - mapB[stageType]!).abs();
        compareResult = diff > 50 ? StageCompareResult.timingDiff : StageCompareResult.match;
      } else if (inA) {
        compareResult = StageCompareResult.onlyInA;
      } else {
        compareResult = StageCompareResult.onlyInB;
      }

      result.add(ComparedStage(
        stageType: stageType,
        timestampA: mapA[stageType],
        timestampB: mapB[stageType],
        result: compareResult,
      ));
    }

    return result;
  }

  Widget _buildHeader(List<ComparedStage> comparison) {
    final matchCount = comparison.where((c) => c.result == StageCompareResult.match).length;
    final onlyACount = comparison.where((c) => c.result == StageCompareResult.onlyInA).length;
    final onlyBCount = comparison.where((c) => c.result == StageCompareResult.onlyInB).length;
    final diffCount = comparison.where((c) => c.result == StageCompareResult.timingDiff).length;

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF242430),
      child: Row(
        children: [
          const Icon(Icons.compare_arrows, color: Color(0xFF4A9EFF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Trace Comparison',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _buildBadge('Match', matchCount, const Color(0xFF40FF90)),
          const SizedBox(width: 6),
          _buildBadge('Only $labelA', onlyACount, const Color(0xFFFF9040)),
          const SizedBox(width: 6),
          _buildBadge('Only $labelB', onlyBCount, const Color(0xFF40C8FF)),
          const SizedBox(width: 6),
          _buildBadge('Timing Diff', diffCount, const Color(0xFFFF4060)),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.compare, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text(
            'No traces to compare',
            style: TextStyle(color: Colors.white54),
          ),
          SizedBox(height: 4),
          Text(
            'Both traces must have stage events',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonList(List<ComparedStage> comparison) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: comparison.length,
      itemBuilder: (context, index) {
        final item = comparison[index];
        return _buildComparisonRow(item);
      },
    );
  }

  Widget _buildComparisonRow(ComparedStage item) {
    final color = StageConfig.instance.getColor(item.stageType);
    final resultColor = _getResultColor(item.result);
    final resultIcon = _getResultIcon(item.result);

    // P3.6: Accessibility label for screen readers
    final semanticLabel = _getComparisonSemanticLabel(item);

    return Semantics(
      label: semanticLabel,
      child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: resultColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: resultColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Stage color indicator
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Stage type
          Expanded(
            flex: 2,
            child: Text(
              item.stageType,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Timestamp A
          SizedBox(
            width: 80,
            child: Text(
              item.timestampA != null
                  ? '${item.timestampA!.toStringAsFixed(0)}ms'
                  : '—',
              style: TextStyle(
                color: item.result == StageCompareResult.onlyInB
                    ? Colors.white24
                    : Colors.white54,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          // Result icon
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(resultIcon, color: resultColor, size: 16),
          ),
          // Timestamp B
          SizedBox(
            width: 80,
            child: Text(
              item.timestampB != null
                  ? '${item.timestampB!.toStringAsFixed(0)}ms'
                  : '—',
              style: TextStyle(
                color: item.result == StageCompareResult.onlyInA
                    ? Colors.white24
                    : Colors.white54,
                fontSize: 11,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          // Timing difference
          if (item.timingDifference != null)
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF3a3a45),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Δ${item.timingDifference!.toStringAsFixed(0)}ms',
                style: TextStyle(
                  color: item.result == StageCompareResult.timingDiff
                      ? const Color(0xFFFF4060)
                      : Colors.white38,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      ),
    );
  }

  /// P3.6: Generate semantic label for comparison row
  String _getComparisonSemanticLabel(ComparedStage item) {
    switch (item.result) {
      case StageCompareResult.match:
        return 'Stage ${item.stageType}: matches in both traces at '
            '${item.timestampA?.toStringAsFixed(0) ?? 0} milliseconds';
      case StageCompareResult.onlyInA:
        return 'Stage ${item.stageType}: only in $labelA at '
            '${item.timestampA?.toStringAsFixed(0) ?? 0} milliseconds';
      case StageCompareResult.onlyInB:
        return 'Stage ${item.stageType}: only in $labelB at '
            '${item.timestampB?.toStringAsFixed(0) ?? 0} milliseconds';
      case StageCompareResult.timingDiff:
        return 'Stage ${item.stageType}: timing difference of '
            '${item.timingDifference?.toStringAsFixed(0) ?? 0} milliseconds, '
            '$labelA at ${item.timestampA?.toStringAsFixed(0) ?? 0}ms, '
            '$labelB at ${item.timestampB?.toStringAsFixed(0) ?? 0}ms';
    }
  }

  Color _getResultColor(StageCompareResult result) {
    switch (result) {
      case StageCompareResult.match:
        return const Color(0xFF40FF90);
      case StageCompareResult.onlyInA:
        return const Color(0xFFFF9040);
      case StageCompareResult.onlyInB:
        return const Color(0xFF40C8FF);
      case StageCompareResult.timingDiff:
        return const Color(0xFFFF4060);
    }
  }

  IconData _getResultIcon(StageCompareResult result) {
    switch (result) {
      case StageCompareResult.match:
        return Icons.check_circle_outline;
      case StageCompareResult.onlyInA:
        return Icons.arrow_back;
      case StageCompareResult.onlyInB:
        return Icons.arrow_forward;
      case StageCompareResult.timingDiff:
        return Icons.schedule;
    }
  }
}
