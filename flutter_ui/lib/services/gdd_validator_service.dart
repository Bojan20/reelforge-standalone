// gdd_validator_service.dart — Comprehensive GDD Validation
// Validates Game Design Documents for completeness, consistency, and audio readiness

import 'package:flutter/foundation.dart';
import 'gdd_import_service.dart';

// =============================================================================
// VALIDATION MODELS
// =============================================================================

enum GddValidationSeverity { error, warning, info }

enum GddValidationCategory {
  structure,
  grid,
  symbols,
  math,
  features,
  audio,
  paytable,
  consistency,
}

class GddValidationIssue {
  final GddValidationSeverity severity;
  final GddValidationCategory category;
  final String message;
  final String? field;
  final String? suggestion;

  const GddValidationIssue({
    required this.severity,
    required this.category,
    required this.message,
    this.field,
    this.suggestion,
  });
}

class GddValidationResult {
  final List<GddValidationIssue> issues;
  final int totalChecks;
  final DateTime timestamp;

  GddValidationResult({
    required this.issues,
    required this.totalChecks,
  }) : timestamp = DateTime.now();

  int get errorCount =>
      issues.where((i) => i.severity == GddValidationSeverity.error).length;
  int get warningCount =>
      issues.where((i) => i.severity == GddValidationSeverity.warning).length;
  int get infoCount =>
      issues.where((i) => i.severity == GddValidationSeverity.info).length;
  int get passedChecks => totalChecks - errorCount;
  double get score =>
      totalChecks > 0 ? (passedChecks / totalChecks * 100) : 0.0;
  bool get isValid => errorCount == 0;
  bool get isAudioReady => errorCount == 0 && warningCount == 0;

  List<GddValidationIssue> byCategory(GddValidationCategory cat) =>
      issues.where((i) => i.category == cat).toList();
}

// =============================================================================
// VALIDATOR SERVICE — SINGLETON
// =============================================================================

class GddValidatorService extends ChangeNotifier {
  static final instance = GddValidatorService._();
  GddValidatorService._();

  GddValidationResult? _lastResult;
  GddValidationResult? get lastResult => _lastResult;

  /// Validate raw JSON map
  List<GddValidationIssue> validateGdd(Map<String, dynamic> gdd) {
    final issues = <GddValidationIssue>[];

    if (!gdd.containsKey('name')) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.structure,
        message: 'Missing required field: name',
        field: 'name',
      ));
    }
    if (!gdd.containsKey('grid')) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.structure,
        message: 'Missing grid configuration',
        field: 'grid',
      ));
    }
    if (!gdd.containsKey('symbols')) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.structure,
        message: 'Missing symbols array',
        field: 'symbols',
      ));
    }

    final symbols = gdd['symbols'] as List?;
    if (symbols != null && symbols.isEmpty) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.symbols,
        message: 'No symbols defined',
        field: 'symbols',
      ));
    }

    return issues;
  }

  bool isValid(Map<String, dynamic> gdd) =>
      validateGdd(gdd).where((i) => i.severity == GddValidationSeverity.error).isEmpty;

  /// Comprehensive validation of parsed GDD document
  GddValidationResult validateDocument(GameDesignDocument gdd) {
    final issues = <GddValidationIssue>[];
    int totalChecks = 0;

    // ─── STRUCTURE ───────────────────────────────────────────────────────
    totalChecks++;
    if (gdd.name.isEmpty) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.structure,
        message: 'Game name is empty',
        field: 'name',
        suggestion: 'Provide a descriptive game name',
      ));
    }

    totalChecks++;
    if (gdd.version.isEmpty) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.structure,
        message: 'Version not specified',
        field: 'version',
        suggestion: 'Use semantic versioning (e.g. 1.0.0)',
      ));
    }

    // ─── GRID ────────────────────────────────────────────────────────────
    totalChecks++;
    if (gdd.grid.rows < 1 || gdd.grid.rows > 10) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.grid,
        message: 'Invalid row count: ${gdd.grid.rows} (must be 1-10)',
        field: 'grid.rows',
      ));
    }

    totalChecks++;
    if (gdd.grid.columns < 1 || gdd.grid.columns > 8) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.grid,
        message: 'Invalid column/reel count: ${gdd.grid.columns} (must be 1-8)',
        field: 'grid.columns',
      ));
    }

    totalChecks++;
    final validMechanics = {'lines', 'ways', 'cluster', 'megaways'};
    if (!validMechanics.contains(gdd.grid.mechanic)) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.grid,
        message: 'Unknown mechanic: "${gdd.grid.mechanic}"',
        field: 'grid.mechanic',
        suggestion: 'Use one of: ${validMechanics.join(", ")}',
      ));
    }

    totalChecks++;
    if (gdd.grid.mechanic == 'lines' && (gdd.grid.paylines == null || gdd.grid.paylines! < 1)) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.grid,
        message: 'Lines mechanic but no paylines defined',
        field: 'grid.paylines',
        suggestion: 'Define paylines count for lines mechanic',
      ));
    }

    totalChecks++;
    if (gdd.grid.mechanic == 'ways' && gdd.grid.ways == null) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.info,
        category: GddValidationCategory.grid,
        message: 'Ways mechanic but ways count not specified',
        field: 'grid.ways',
        suggestion: 'Will be auto-calculated from grid dimensions',
      ));
    }

    // ─── SYMBOLS ─────────────────────────────────────────────────────────
    totalChecks++;
    if (gdd.symbols.isEmpty) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.symbols,
        message: 'No symbols defined',
        field: 'symbols',
        suggestion: 'Add at least 8 symbols (3 high, 3 low, wild, scatter)',
      ));
    }

    totalChecks++;
    if (gdd.symbols.length < 8) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.symbols,
        message: 'Only ${gdd.symbols.length} symbols defined (recommended: 8+)',
        field: 'symbols',
        suggestion: 'Most slots have 8-13 symbols for balanced gameplay',
      ));
    }

    // Check for required symbol types
    totalChecks++;
    final hasWild = gdd.symbols.any((s) => s.isWild || s.tier == SymbolTier.wild);
    if (!hasWild) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.symbols,
        message: 'No Wild symbol defined',
        field: 'symbols',
        suggestion: 'Most games include at least one Wild symbol',
      ));
    }

    totalChecks++;
    final hasScatter = gdd.symbols.any((s) => s.isScatter || s.tier == SymbolTier.scatter);
    if (!hasScatter) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.info,
        category: GddValidationCategory.symbols,
        message: 'No Scatter symbol defined',
        field: 'symbols',
      ));
    }

    // Check for duplicate symbol IDs
    totalChecks++;
    final symbolIds = gdd.symbols.map((s) => s.id).toSet();
    if (symbolIds.length != gdd.symbols.length) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.symbols,
        message: 'Duplicate symbol IDs found',
        field: 'symbols',
        suggestion: 'Each symbol must have a unique ID',
      ));
    }

    // Check tier distribution
    totalChecks++;
    final lowCount = gdd.symbols.where((s) => s.tier == SymbolTier.low).length;
    final highCount = gdd.symbols.where((s) =>
        s.tier == SymbolTier.high || s.tier == SymbolTier.premium).length;
    if (lowCount == 0 && highCount == 0) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.symbols,
        message: 'No tier distribution — all symbols have same tier',
        field: 'symbols',
        suggestion: 'Define low, mid, and high pay symbol tiers',
      ));
    }

    // ─── PAYTABLE ────────────────────────────────────────────────────────
    for (final symbol in gdd.symbols) {
      if (symbol.isWild || symbol.isScatter || symbol.isBonus) continue;

      totalChecks++;
      if (symbol.payouts.isEmpty) {
        issues.add(GddValidationIssue(
          severity: GddValidationSeverity.warning,
          category: GddValidationCategory.paytable,
          message: 'Symbol "${symbol.name}" has no payout values',
          field: 'symbols.${symbol.id}.payouts',
          suggestion: 'Define payouts for 3-of-a-kind through ${gdd.grid.columns}-of-a-kind',
        ));
      }

      totalChecks++;
      if (symbol.payouts.isNotEmpty) {
        final maxPayout = symbol.payouts.values.fold(0.0, (a, b) => a > b ? a : b);
        if (maxPayout > 10000) {
          issues.add(GddValidationIssue(
            severity: GddValidationSeverity.warning,
            category: GddValidationCategory.paytable,
            message: 'Symbol "${symbol.name}" has very high payout (${maxPayout}x)',
            field: 'symbols.${symbol.id}.payouts',
            suggestion: 'Verify this is intentional — may affect RTP',
          ));
        }

        // Check payout progression (should increase with count)
        final sorted = symbol.payouts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (int i = 1; i < sorted.length; i++) {
          if (sorted[i].value < sorted[i - 1].value) {
            issues.add(GddValidationIssue(
              severity: GddValidationSeverity.warning,
              category: GddValidationCategory.paytable,
              message:
                  '"${symbol.name}" payout decreases: ${sorted[i - 1].key}-of=${sorted[i - 1].value}x → ${sorted[i].key}-of=${sorted[i].value}x',
              field: 'symbols.${symbol.id}.payouts',
              suggestion: 'Payouts should increase with more matching symbols',
            ));
            break;
          }
        }
      }
    }

    // ─── MATH MODEL ──────────────────────────────────────────────────────
    totalChecks++;
    if (gdd.math.rtp < 0.80 || gdd.math.rtp > 1.0) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.error,
        category: GddValidationCategory.math,
        message: 'RTP ${(gdd.math.rtp * 100).toStringAsFixed(2)}% is outside valid range (80-100%)',
        field: 'math.rtp',
        suggestion: 'Standard RTP range: 94-97%',
      ));
    } else if (gdd.math.rtp < 0.90) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.math,
        message: 'RTP ${(gdd.math.rtp * 100).toStringAsFixed(2)}% is below industry minimum (90%)',
        field: 'math.rtp',
        suggestion: 'Most jurisdictions require RTP ≥ 90%',
      ));
    }

    totalChecks++;
    final validVolatilities = {'low', 'medium', 'high', 'very_high', 'extreme'};
    if (!validVolatilities.contains(gdd.math.volatility.toLowerCase())) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.math,
        message: 'Unknown volatility: "${gdd.math.volatility}"',
        field: 'math.volatility',
        suggestion: 'Use one of: ${validVolatilities.join(", ")}',
      ));
    }

    totalChecks++;
    if (gdd.math.hitFrequency <= 0 || gdd.math.hitFrequency > 1.0) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.math,
        message: 'Hit frequency ${gdd.math.hitFrequency} is outside expected range (0-1)',
        field: 'math.hitFrequency',
        suggestion: 'Typical hit frequency: 0.15-0.40 (15-40%)',
      ));
    }

    totalChecks++;
    if (gdd.math.winTiers.isEmpty) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.info,
        category: GddValidationCategory.math,
        message: 'No win tiers defined — defaults will be used',
        field: 'math.winTiers',
      ));
    }

    // Check win tier overlap
    if (gdd.math.winTiers.length >= 2) {
      totalChecks++;
      final sortedTiers = List.of(gdd.math.winTiers)
        ..sort((a, b) => a.minMultiplier.compareTo(b.minMultiplier));
      for (int i = 1; i < sortedTiers.length; i++) {
        if (sortedTiers[i].minMultiplier < sortedTiers[i - 1].maxMultiplier) {
          issues.add(GddValidationIssue(
            severity: GddValidationSeverity.warning,
            category: GddValidationCategory.math,
            message:
                'Win tiers overlap: "${sortedTiers[i - 1].name}" (max ${sortedTiers[i - 1].maxMultiplier}x) and "${sortedTiers[i].name}" (min ${sortedTiers[i].minMultiplier}x)',
            field: 'math.winTiers',
          ));
          break;
        }
      }
    }

    // ─── FEATURES ────────────────────────────────────────────────────────
    totalChecks++;
    if (gdd.features.isEmpty) {
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.info,
        category: GddValidationCategory.features,
        message: 'No bonus features defined',
        field: 'features',
        suggestion: 'Most modern slots include at least Free Spins',
      ));
    }

    // Check for duplicate feature IDs
    if (gdd.features.isNotEmpty) {
      totalChecks++;
      final featureIds = gdd.features.map((f) => f.id).toSet();
      if (featureIds.length != gdd.features.length) {
        issues.add(const GddValidationIssue(
          severity: GddValidationSeverity.error,
          category: GddValidationCategory.features,
          message: 'Duplicate feature IDs found',
          field: 'features',
        ));
      }
    }

    // Check free spins feature
    final freeSpinsFeatures = gdd.features.where((f) => f.type == GddFeatureType.freeSpins);
    for (final fs in freeSpinsFeatures) {
      totalChecks++;
      if (fs.initialSpins == null || fs.initialSpins! < 1) {
        issues.add(GddValidationIssue(
          severity: GddValidationSeverity.warning,
          category: GddValidationCategory.features,
          message: 'Free Spins feature "${fs.name}" has no initial spins count',
          field: 'features.${fs.id}.initialSpins',
          suggestion: 'Typical range: 5-25 initial free spins',
        ));
      }

      totalChecks++;
      if (fs.triggerCondition == null || fs.triggerCondition!.isEmpty) {
        issues.add(GddValidationIssue(
          severity: GddValidationSeverity.warning,
          category: GddValidationCategory.features,
          message: 'Free Spins "${fs.name}" has no trigger condition',
          field: 'features.${fs.id}.triggerCondition',
          suggestion: 'e.g., "3+ scatter symbols"',
        ));
      }
    }

    // ─── AUDIO READINESS ─────────────────────────────────────────────────
    totalChecks++;
    final estimatedStages = _estimateRequiredStages(gdd);
    if (estimatedStages < 20) {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.info,
        category: GddValidationCategory.audio,
        message: 'Estimated $estimatedStages audio stages needed',
        field: 'audio',
        suggestion: 'Simple game — fewer audio assets required',
      ));
    } else {
      issues.add(GddValidationIssue(
        severity: GddValidationSeverity.info,
        category: GddValidationCategory.audio,
        message: 'Estimated $estimatedStages audio stages needed',
        field: 'audio',
      ));
    }

    totalChecks++;
    final symbolsNeedingAudio = gdd.symbols.length * 2; // land + win per symbol
    issues.add(GddValidationIssue(
      severity: GddValidationSeverity.info,
      category: GddValidationCategory.audio,
      message: '$symbolsNeedingAudio symbol audio slots (${gdd.symbols.length} symbols × 2 contexts)',
      field: 'audio.symbols',
    ));

    // ─── CONSISTENCY ─────────────────────────────────────────────────────
    // Scatter + features consistency
    if (hasScatter && freeSpinsFeatures.isEmpty) {
      totalChecks++;
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.consistency,
        message: 'Scatter symbol defined but no Free Spins feature',
        suggestion: 'Scatter usually triggers Free Spins',
      ));
    }

    // Bonus symbol + bonus feature consistency
    final hasBonus = gdd.symbols.any((s) => s.isBonus || s.tier == SymbolTier.bonus);
    final hasBonusFeature = gdd.features.any((f) => f.type == GddFeatureType.bonus);
    if (hasBonus && !hasBonusFeature) {
      totalChecks++;
      issues.add(const GddValidationIssue(
        severity: GddValidationSeverity.warning,
        category: GddValidationCategory.consistency,
        message: 'Bonus symbol defined but no Bonus feature',
        suggestion: 'Add a Bonus Game feature triggered by bonus symbols',
      ));
    }

    _lastResult = GddValidationResult(issues: issues, totalChecks: totalChecks);
    notifyListeners();
    return _lastResult!;
  }

  int _estimateRequiredStages(GameDesignDocument gdd) {
    int count = 0;
    // Base: spin start, spin end, reel spin loop
    count += 3;
    // Per-reel: reel stop
    count += gdd.grid.columns;
    // Win presentation: win present, rollup, line show
    count += 6;
    // Per symbol: land + win highlight
    count += gdd.symbols.length * 2;
    // Per feature: enter, step, exit
    count += gdd.features.length * 3;
    // Music: base, tension, feature
    count += 3;
    // UI: button press, menu
    count += 4;
    return count;
  }
}
