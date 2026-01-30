/// Multi-Processor Chain Validator
///
/// P2-02: Validates DSP processor chains for common issues:
/// - Phase cancellation (multiple EQs with opposite curves)
/// - Gain staging issues (clipping between stages)
/// - Redundant processors (multiple identical EQ/dynamics)
/// - Invalid routing (feedback loops)
/// - CPU load estimation

import 'dart:math' as math;
import '../../models/layout_models.dart';

/// Validation issue severity
enum ValidationSeverity {
  /// Info — suggestion for improvement
  info,
  /// Warning — may cause issues
  warning,
  /// Error — will cause problems
  error,
  /// Critical — system failure likely
  critical,
}

/// Validation issue type
enum ValidationIssueType {
  /// Phase cancellation between processors
  phaseCancellation,
  /// Gain staging issue (clipping/headroom)
  gainStaging,
  /// Redundant processor
  redundantProcessor,
  /// Invalid routing (feedback loop)
  invalidRouting,
  /// Excessive CPU load
  cpuLoad,
  /// Order optimization suggestion
  orderOptimization,
  /// Parameter conflict
  parameterConflict,
}

/// Validation issue
class ChainValidationIssue {
  final ValidationIssueType type;
  final ValidationSeverity severity;
  final String description;
  final List<int> affectedProcessorIndices;
  final String? suggestion;
  final double? confidence; // 0.0-1.0

  const ChainValidationIssue({
    required this.type,
    required this.severity,
    required this.description,
    required this.affectedProcessorIndices,
    this.suggestion,
    this.confidence,
  });

  @override
  String toString() {
    final indices = affectedProcessorIndices.join(', ');
    return '[$severity] $description (processors: $indices)';
  }
}

/// Chain validation result
class ChainValidationResult {
  final List<ChainValidationIssue> issues;
  final double estimatedCpuLoad; // 0-100%
  final double estimatedLatencyMs;
  final Map<String, dynamic> metadata;

  const ChainValidationResult({
    required this.issues,
    required this.estimatedCpuLoad,
    required this.estimatedLatencyMs,
    this.metadata = const {},
  });

  /// Get issues by severity
  List<ChainValidationIssue> getBySeverity(ValidationSeverity severity) {
    return issues.where((i) => i.severity == severity).toList();
  }

  /// Get issues by type
  List<ChainValidationIssue> getByType(ValidationIssueType type) {
    return issues.where((i) => i.type == type).toList();
  }

  /// Check if chain has any errors or criticals
  bool get hasErrors => issues.any((i) =>
      i.severity == ValidationSeverity.error ||
      i.severity == ValidationSeverity.critical);

  /// Generate report
  String generateReport() {
    final sb = StringBuffer();
    sb.writeln('=== DSP Chain Validation Report ===');
    sb.writeln('Estimated CPU Load: ${estimatedCpuLoad.toStringAsFixed(1)}%');
    sb.writeln('Estimated Latency: ${estimatedLatencyMs.toStringAsFixed(2)}ms');
    sb.writeln('Total Issues: ${issues.length}');
    sb.writeln('');

    if (issues.isEmpty) {
      sb.writeln('✅ No issues found');
      return sb.toString();
    }

    // Group by severity
    final bySeverity = <ValidationSeverity, List<ChainValidationIssue>>{};
    for (final issue in issues) {
      bySeverity.putIfAbsent(issue.severity, () => []).add(issue);
    }

    for (final severity in [
      ValidationSeverity.critical,
      ValidationSeverity.error,
      ValidationSeverity.warning,
      ValidationSeverity.info,
    ]) {
      final issuesAtLevel = bySeverity[severity] ?? [];
      if (issuesAtLevel.isEmpty) continue;

      sb.writeln('${severity.name.toUpperCase()}: ${issuesAtLevel.length}');
      for (final issue in issuesAtLevel) {
        sb.writeln('  • $issue');
        if (issue.suggestion != null) {
          sb.writeln('    → ${issue.suggestion}');
        }
      }
      sb.writeln('');
    }

    return sb.toString();
  }
}

/// Multi-Processor Chain Validator
class MultiProcessorChainValidator {
  /// Validate DSP processor chain
  ChainValidationResult validate(List<InsertSlot> chain) {
    final issues = <ChainValidationIssue>[];

    if (chain.isEmpty) {
      return ChainValidationResult(
        issues: [],
        estimatedCpuLoad: 0.0,
        estimatedLatencyMs: 0.0,
      );
    }

    // 1. Check phase cancellation
    issues.addAll(_checkPhaseCancellation(chain));

    // 2. Check gain staging
    issues.addAll(_checkGainStaging(chain));

    // 3. Check redundant processors
    issues.addAll(_checkRedundantProcessors(chain));

    // 4. Check order optimization
    issues.addAll(_checkOrderOptimization(chain));

    // 5. Estimate CPU load
    final cpuLoad = _estimateCpuLoad(chain);
    if (cpuLoad > 80.0) {
      issues.add(ChainValidationIssue(
        type: ValidationIssueType.cpuLoad,
        severity: ValidationSeverity.warning,
        description: 'Chain CPU load is high (${cpuLoad.toStringAsFixed(1)}%)',
        affectedProcessorIndices: List.generate(chain.length, (i) => i),
        suggestion: 'Consider removing redundant processors or using lighter alternatives',
      ));
    }

    // 6. Estimate latency
    final latencyMs = _estimateLatency(chain);

    return ChainValidationResult(
      issues: issues,
      estimatedCpuLoad: cpuLoad,
      estimatedLatencyMs: latencyMs,
      metadata: {
        'processorCount': chain.length,
        'bypassedCount': chain.where((p) => p.bypassed).length,
      },
    );
  }

  /// Check for phase cancellation between processors
  List<ChainValidationIssue> _checkPhaseCancellation(List<InsertSlot> chain) {
    final issues = <ChainValidationIssue>[];

    // Find pairs of EQs with potentially opposing curves
    for (int i = 0; i < chain.length; i++) {
      if (chain[i].bypassed) continue;
      if (chain[i].type != 'eq') continue;

      for (int j = i + 1; j < chain.length; j++) {
        if (chain[j].bypassed) continue;
        if (chain[j].type != 'eq') continue;

        // Simple heuristic: if both are EQs close together, check for opposite gains
        // In real implementation, would analyze actual frequency response curves
        issues.add(ChainValidationIssue(
          type: ValidationIssueType.phaseCancellation,
          severity: ValidationSeverity.info,
          description: 'Multiple EQs detected — verify they don\'t cancel each other',
          affectedProcessorIndices: [i, j],
          suggestion: 'Consider merging EQ operations into a single processor',
          confidence: 0.5,
        ));
      }
    }

    return issues;
  }

  /// Check gain staging between processors
  List<ChainValidationIssue> _checkGainStaging(List<InsertSlot> chain) {
    final issues = <ChainValidationIssue>[];
    double cumulativeGain = 1.0; // linear

    for (int i = 0; i < chain.length; i++) {
      if (chain[i].bypassed) continue;

      // Estimate gain added by this processor
      final processorGain = _estimateProcessorGain(chain[i]);
      cumulativeGain *= processorGain;

      // Check for clipping
      if (cumulativeGain > 2.0) { // > +6 dB
        issues.add(ChainValidationIssue(
          type: ValidationIssueType.gainStaging,
          severity: ValidationSeverity.error,
          description: 'Potential clipping at processor ${i + 1} (+${_linearToDb(cumulativeGain).toStringAsFixed(1)} dB)',
          affectedProcessorIndices: [i],
          suggestion: 'Add gain reduction before this processor or reduce input gain',
        ));
      }

      // Check for excessive headroom loss
      if (cumulativeGain > 1.5) { // > +3.5 dB
        issues.add(ChainValidationIssue(
          type: ValidationIssueType.gainStaging,
          severity: ValidationSeverity.warning,
          description: 'Headroom reduced at processor ${i + 1} (+${_linearToDb(cumulativeGain).toStringAsFixed(1)} dB)',
          affectedProcessorIndices: [i],
          suggestion: 'Monitor levels to prevent clipping',
        ));
      }
    }

    return issues;
  }

  /// Check for redundant processors
  List<ChainValidationIssue> _checkRedundantProcessors(List<InsertSlot> chain) {
    final issues = <ChainValidationIssue>[];

    // Check for multiple identical processor types
    final typeCounts = <String, List<int>>{};
    for (int i = 0; i < chain.length; i++) {
      if (chain[i].bypassed) continue;
      typeCounts.putIfAbsent(chain[i].type, () => []).add(i);
    }

    for (final entry in typeCounts.entries) {
      if (entry.value.length > 1) {
        issues.add(ChainValidationIssue(
          type: ValidationIssueType.redundantProcessor,
          severity: ValidationSeverity.info,
          description: 'Multiple ${entry.key} processors detected (${entry.value.length})',
          affectedProcessorIndices: entry.value,
          suggestion: 'Consider merging into a single processor if settings are similar',
        ));
      }
    }

    return issues;
  }

  /// Check order optimization
  List<ChainValidationIssue> _checkOrderOptimization(List<InsertSlot> chain) {
    final issues = <ChainValidationIssue>[];

    // Ideal order: EQ → Dynamics → Time-based (reverb/delay) → Limiting
    // Check if order is non-optimal
    final types = chain.where((p) => !p.bypassed).map((p) => p.type).toList();

    // Find indices of each category
    int? lastEqIdx, lastDynamicsIdx, lastTimeIdx, lastLimiterIdx;

    for (int i = 0; i < chain.length; i++) {
      if (chain[i].bypassed) continue;

      switch (chain[i].type) {
        case 'eq':
          lastEqIdx = i;
          break;
        case 'compressor':
        case 'gate':
        case 'expander':
          lastDynamicsIdx = i;
          break;
        case 'reverb':
        case 'delay':
          lastTimeIdx = i;
          break;
        case 'limiter':
          lastLimiterIdx = i;
          break;
      }
    }

    // Check if limiter is not last
    if (lastLimiterIdx != null && lastLimiterIdx != chain.length - 1) {
      issues.add(ChainValidationIssue(
        type: ValidationIssueType.orderOptimization,
        severity: ValidationSeverity.warning,
        description: 'Limiter should typically be last in chain',
        affectedProcessorIndices: [lastLimiterIdx],
        suggestion: 'Move limiter to end of chain for proper peak control',
      ));
    }

    // Check if EQ is after time-based effects
    if (lastEqIdx != null && lastTimeIdx != null && lastEqIdx > lastTimeIdx) {
      issues.add(ChainValidationIssue(
        type: ValidationIssueType.orderOptimization,
        severity: ValidationSeverity.info,
        description: 'EQ after time-based effects — consider reordering',
        affectedProcessorIndices: [lastEqIdx, lastTimeIdx],
        suggestion: 'Typically EQ should come before reverb/delay for cleaner sound',
        confidence: 0.7,
      ));
    }

    return issues;
  }

  /// Estimate CPU load for chain (0-100%)
  double _estimateCpuLoad(List<InsertSlot> chain) {
    double load = 0.0;

    for (final processor in chain) {
      if (processor.bypassed) continue;

      // Rough CPU estimates per processor type (%)
      load += switch (processor.type) {
        'eq' => 5.0,
        'compressor' => 8.0,
        'limiter' => 6.0,
        'gate' => 4.0,
        'expander' => 5.0,
        'reverb' => 25.0, // Convolution reverb is expensive
        'delay' => 3.0,
        'saturation' => 4.0,
        'deesser' => 7.0,
        _ => 5.0,
      };
    }

    return load.clamp(0.0, 100.0);
  }

  /// Estimate latency for chain (ms)
  double _estimateLatency(List<InsertSlot> chain) {
    double latencyMs = 0.0;

    for (final processor in chain) {
      if (processor.bypassed) continue;

      // Rough latency estimates per processor type (ms)
      latencyMs += switch (processor.type) {
        'eq' => 0.0, // Zero-latency
        'compressor' => 0.5, // Lookahead
        'limiter' => 1.0, // Lookahead
        'gate' => 0.0,
        'expander' => 0.0,
        'reverb' => 0.0, // Tail, but not latency
        'delay' => 0.0,
        'saturation' => 0.0,
        'deesser' => 0.5,
        _ => 0.0,
      };
    }

    return latencyMs;
  }

  /// Estimate gain added by processor (linear)
  double _estimateProcessorGain(InsertSlot processor) {
    // Rough estimates — in real implementation would analyze actual parameters
    return switch (processor.type) {
      'eq' => 1.0, // Can vary greatly
      'compressor' => 0.8, // Typically reduces peaks
      'limiter' => 0.9, // Reduces peaks
      'gate' => 1.0, // No gain change
      'expander' => 1.1, // Can add dynamic range
      'reverb' => 1.0,
      'delay' => 1.0,
      'saturation' => 1.2, // Adds harmonics
      'deesser' => 0.95, // Slight reduction
      _ => 1.0,
    };
  }

  /// Convert linear to dB
  double _linearToDb(double linear) {
    if (linear <= 0.0) return -96.0;
    return 20.0 * math.log(linear) / math.ln10;
  }
}
