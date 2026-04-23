/// PHASE 10 — Audio Gap Analysis Service
///
/// Problem: the Neural Bind Orb shows *some* missing types as dashed red
/// arcs, but the user has no single place to see **exactly which stages
/// have no audio binding, broken down by category**, or the actual
/// percentage of coverage. This leads to surprises in QA: "why is
/// FREE_SPIN_WIN_ROLLUP_3 silent?" — because it was never assigned.
///
/// Solution: a stateless service that takes the current `audioAssignments`
/// map (stage → asset path) plus the full stage registry from
/// `StageConfigurationService`, and produces an `AudioGapReport` containing:
///
/// - overall coverage ratio (bound / total)
/// - per-category breakdown (spin/win/feature/... bound vs total)
/// - sorted list of missing stages per category
///
/// The report is cheap to compute (<1 ms for 200 stages) so callers can
/// regenerate it whenever the binding map changes. No caching in the
/// service itself — the caller owns lifecycle.
///
/// This powers the **Ghost Stage Indicator** UI inside the Neural Bind
/// Orb bottom sheet and can be used by any other widget that wants to
/// display coverage stats without plumbing the whole assignment map.

library;

import 'stage_configuration_service.dart';

/// Per-category breakdown of bound vs total stages.
class AudioGapCategorySlice {
  final StageCategory category;
  final int total;
  final int bound;

  /// Missing stage names in this category (alphabetical, suitable for
  /// direct display in a picker). Empty if fully covered.
  final List<String> missing;

  const AudioGapCategorySlice({
    required this.category,
    required this.total,
    required this.bound,
    required this.missing,
  });

  int get missingCount => total - bound;

  double get coverage => total > 0 ? bound / total : 0.0;

  bool get isFull => total > 0 && bound >= total;

  /// Convenience for UI sorting — most critical gap first.
  int get gapSeverity => missingCount;
}

/// Full gap analysis result — immutable snapshot.
class AudioGapReport {
  /// Total stages across ALL categories.
  final int totalStages;

  /// Stages that have at least one audio asset assigned.
  final int boundStages;

  /// Per-category slices, sorted by category enum order (display-friendly).
  final List<AudioGapCategorySlice> categorySlices;

  /// Flat list of ALL missing stages (unassigned). Sorted alphabetically.
  /// Handy for "Missing (40)" expanders without reflowing the categories.
  final List<String> allMissing;

  const AudioGapReport({
    required this.totalStages,
    required this.boundStages,
    required this.categorySlices,
    required this.allMissing,
  });

  /// Overall coverage ratio (0..1). Returns 0 when there are no stages.
  double get coverage => totalStages > 0 ? boundStages / totalStages : 0.0;

  /// Count of stages with no assignment.
  int get missingCount => totalStages - boundStages;

  /// True when every stage has at least one binding.
  bool get isFull => totalStages > 0 && boundStages >= totalStages;

  /// Empty report (for default states / initial UI / tests).
  static const AudioGapReport empty = AudioGapReport(
    totalStages: 0,
    boundStages: 0,
    categorySlices: [],
    allMissing: [],
  );

  /// Human-readable short summary, e.g. "142 / 182 bound (78%), 40 gaps".
  String get summary {
    if (totalStages == 0) return 'No stages defined';
    final pct = (coverage * 100).toStringAsFixed(0);
    return '$boundStages / $totalStages bound ($pct%), $missingCount gap${missingCount == 1 ? '' : 's'}';
  }
}

/// Analysis service — stateless. Call `analyze()` whenever assignments change.
class AudioGapAnalysisService {
  AudioGapAnalysisService._();
  static final AudioGapAnalysisService instance = AudioGapAnalysisService._();

  /// Analyse current assignment map against the full stage registry.
  ///
  /// - `audioAssignments`: map of stage name → asset path. Only the KEYS are
  ///   used. An empty string value counts as unassigned (caller should not
  ///   include empty values, but we defensively skip them).
  /// - `stageSource`: optional override for dependency injection in tests.
  ///   When null, the live `StageConfigurationService` registry is used.
  AudioGapReport analyze(
    Map<String, String> audioAssignments, {
    List<StageDefinition>? stageSource,
  }) {
    final allStages = stageSource ??
        StageConfigurationService.instance.getAllStages();
    if (allStages.isEmpty) return AudioGapReport.empty;

    // Normalise binding keys once — stage names in the registry are already
    // canonical (UPPER_SNAKE), but the assignment map may use lowercase or
    // dotted legacy keys. We match case-insensitively.
    final boundKeys = <String>{};
    audioAssignments.forEach((k, v) {
      if (v.isEmpty) return;
      boundKeys.add(k.trim().toUpperCase());
      // Dotted-form fallback (e.g. "button.click" → "BUTTON_CLICK").
      final dotted = k.trim().replaceAll('.', '_').toUpperCase();
      if (dotted != k.trim().toUpperCase()) {
        boundKeys.add(dotted);
      }
    });

    // Partition by category.
    final buckets = <StageCategory, _Bucket>{};
    for (final cat in StageCategory.values) {
      buckets[cat] = _Bucket(cat);
    }
    int totalBound = 0;
    final flatMissing = <String>[];

    for (final stage in allStages) {
      final bucket = buckets[stage.category]!;
      bucket.total += 1;
      final isBound = boundKeys.contains(stage.name.toUpperCase());
      if (isBound) {
        bucket.bound += 1;
        totalBound += 1;
      } else {
        bucket.missing.add(stage.name);
        flatMissing.add(stage.name);
      }
    }

    // Finalise: sort missing lists, build slices in enum order.
    final slices = <AudioGapCategorySlice>[];
    for (final cat in StageCategory.values) {
      final b = buckets[cat]!;
      if (b.total == 0) continue; // hide categories with no stages
      b.missing.sort();
      slices.add(AudioGapCategorySlice(
        category: cat,
        total: b.total,
        bound: b.bound,
        missing: List.unmodifiable(b.missing),
      ));
    }
    flatMissing.sort();

    return AudioGapReport(
      totalStages: allStages.length,
      boundStages: totalBound,
      categorySlices: List.unmodifiable(slices),
      allMissing: List.unmodifiable(flatMissing),
    );
  }
}

class _Bucket {
  final StageCategory category;
  int total = 0;
  int bound = 0;
  final List<String> missing = [];

  _Bucket(this.category);
}
