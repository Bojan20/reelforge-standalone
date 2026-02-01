// ============================================================================
// FluxForge Studio — Wild Features Block
// ============================================================================
// P13.9.5: Feature block for Wild symbol behaviors configuration
// Defines expansion, sticky, walking, multiplier, and stacking mechanics.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Wild expansion behavior.
enum WildExpansion {
  /// No expansion.
  disabled,

  /// Wild expands to fill entire reel.
  fullReel,

  /// Wild expands in cross pattern (adjacent positions).
  cross,

  /// Wild expands to adjacent positions only.
  adjacent,
}

/// Walking direction for walking wilds.
enum WalkingDirection {
  /// Walk left each spin.
  left,

  /// Walk right each spin.
  right,

  /// Random direction each spin.
  random,

  /// Can walk both directions.
  bidirectional,
}

/// Feature block for Wild symbol behaviors.
///
/// This block configures advanced Wild symbol mechanics:
/// - Expansion: Full reel, cross pattern, adjacent
/// - Sticky: Wilds persist for multiple spins
/// - Walking: Wilds move across reels
/// - Multipliers: Wild multiplier values
/// - Stacking: Multiple Wilds stacked on reels
///
/// Requires Symbol Set block with Wild symbol enabled.
class WildFeaturesBlock extends FeatureBlockBase {
  WildFeaturesBlock() : super(enabled: false);

  @override
  String get id => 'wild_features';

  @override
  String get name => 'Wild Features';

  @override
  String get description =>
      'Advanced Wild symbol behaviors: expanding, sticky, walking, multipliers';

  @override
  BlockCategory get category => BlockCategory.bonus;

  @override
  String get iconName => 'auto_fix_high';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 12; // After symbol-related blocks

  @override
  List<BlockOption> createOptions() => [
        // ========== Expansion Settings ==========
        BlockOptionFactory.dropdown(
          id: 'expansion',
          name: 'Expansion Type',
          description: 'How Wild symbols expand when they land',
          choices: const [
            OptionChoice(
              value: 'disabled',
              label: 'Disabled',
              description: 'No expansion',
            ),
            OptionChoice(
              value: 'full_reel',
              label: 'Full Reel',
              description: 'Expands to cover entire reel',
            ),
            OptionChoice(
              value: 'cross',
              label: 'Cross Pattern',
              description: 'Expands in + shape',
            ),
            OptionChoice(
              value: 'adjacent',
              label: 'Adjacent',
              description: 'Expands to neighboring positions',
            ),
          ],
          defaultValue: 'disabled',
          group: 'Expansion',
          order: 1,
        ),

        // ========== Sticky Settings ==========
        BlockOptionFactory.range(
          id: 'sticky_duration',
          name: 'Sticky Duration',
          description: 'Number of spins Wild remains sticky (0 = not sticky)',
          min: 0,
          max: 10,
          step: 1,
          defaultValue: 0,
          group: 'Sticky',
          order: 2,
        ),

        // ========== Walking Settings ==========
        BlockOptionFactory.dropdown(
          id: 'walking_direction',
          name: 'Walking Direction',
          description: 'Direction Wild symbols walk each spin',
          choices: const [
            OptionChoice(
              value: 'none',
              label: 'None',
              description: 'No walking behavior',
            ),
            OptionChoice(
              value: 'left',
              label: 'Left',
              description: 'Walk left one position per spin',
            ),
            OptionChoice(
              value: 'right',
              label: 'Right',
              description: 'Walk right one position per spin',
            ),
            OptionChoice(
              value: 'random',
              label: 'Random',
              description: 'Random direction each spin',
            ),
            OptionChoice(
              value: 'bidirectional',
              label: 'Bidirectional',
              description: 'Can walk in either direction',
            ),
          ],
          defaultValue: 'none',
          group: 'Walking',
          order: 3,
        ),

        // ========== Multiplier Settings ==========
        BlockOptionFactory.multiSelect(
          id: 'multiplier_range',
          name: 'Multiplier Values',
          description: 'Possible Wild multiplier values',
          choices: const [
            OptionChoice(value: 2, label: '×2'),
            OptionChoice(value: 3, label: '×3'),
            OptionChoice(value: 5, label: '×5'),
            OptionChoice(value: 10, label: '×10'),
          ],
          defaultValue: <int>[],
          group: 'Multiplier',
          order: 4,
        ),

        // ========== Stack Settings ==========
        BlockOptionFactory.range(
          id: 'stack_height',
          name: 'Stack Height',
          description: 'Maximum height of stacked Wilds on a reel',
          min: 2,
          max: 7,
          step: 1,
          defaultValue: 3,
          group: 'Stacking',
          order: 5,
        ),

        // ========== Audio Settings ==========
        BlockOptionFactory.toggle(
          id: 'has_expansion_sound',
          name: 'Expansion Sound',
          description: 'Play sound when Wild expands',
          defaultValue: true,
          group: 'Audio',
          order: 6,
          visibleWhen: {'expansion': 'full_reel'},
        ),

        BlockOptionFactory.toggle(
          id: 'has_sticky_sound',
          name: 'Sticky Sound',
          description: 'Play sound when Wild sticks',
          defaultValue: true,
          group: 'Audio',
          order: 7,
        ),

        BlockOptionFactory.toggle(
          id: 'has_walking_sound',
          name: 'Walking Sound',
          description: 'Play sound when Wild walks',
          defaultValue: true,
          group: 'Audio',
          order: 8,
        ),

        BlockOptionFactory.toggle(
          id: 'has_multiplier_sound',
          name: 'Multiplier Sound',
          description: 'Play sound when Wild multiplier applies',
          defaultValue: true,
          group: 'Audio',
          order: 9,
        ),

        BlockOptionFactory.toggle(
          id: 'has_stack_sound',
          name: 'Stack Sound',
          description: 'Play sound when stacked Wilds form',
          defaultValue: true,
          group: 'Audio',
          order: 10,
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Requires Symbol Set with Wild enabled
        BlockDependency.requires(
          source: id,
          target: 'symbol_set',
          targetOption: 'hasWild',
          description: 'Needs Wild symbol enabled in Symbol Set',
          autoResolvable: true,
          autoResolveAction: const AutoResolveAction(
            type: AutoResolveType.setOption,
            targetBlockId: 'symbol_set',
            optionId: 'hasWild',
            value: true,
            description: 'Enable Wild symbol in Symbol Set',
          ),
        ),

        // Modifies Win Presentation
        BlockDependency.modifies(
          source: id,
          target: 'win_presentation',
          description: 'Wild multipliers affect win calculation display',
        ),

        // Enables Multiplier system if Wild multipliers used
        BlockDependency.enables(
          source: id,
          target: 'multiplier',
          description: 'Enables multiplier system if Wild multipliers are used',
          condition: {'multiplier_range': []}, // When list is not empty
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final expansion = getOptionValue<String>('expansion') ?? 'disabled';
    final stickyDuration = getOptionValue<num>('sticky_duration')?.toInt() ?? 0;
    final walkingDirection =
        getOptionValue<String>('walking_direction') ?? 'none';
    final multipliers =
        getOptionValue<List<dynamic>>('multiplier_range')?.cast<int>() ?? [];
    final stackHeight = getOptionValue<num>('stack_height')?.toInt() ?? 3;

    final hasExpansionSound =
        getOptionValue<bool>('has_expansion_sound') ?? true;
    final hasStickySound = getOptionValue<bool>('has_sticky_sound') ?? true;
    final hasWalkingSound = getOptionValue<bool>('has_walking_sound') ?? true;
    final hasMultiplierSound =
        getOptionValue<bool>('has_multiplier_sound') ?? true;
    final hasStackSound = getOptionValue<bool>('has_stack_sound') ?? true;

    // ========== Base Wild Landing ==========
    stages.add(const GeneratedStage(
      name: 'WILD_LAND',
      description: 'Wild symbol lands on reel',
      bus: 'sfx',
      priority: 70,
      pooled: true,
      sourceBlockId: 'wild_features',
      category: 'Wild Features',
    ));

    // ========== Expansion Stages ==========
    if (expansion != 'disabled') {
      if (hasExpansionSound) {
        stages.add(const GeneratedStage(
          name: 'WILD_EXPAND_START',
          description: 'Wild expansion animation begins',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));

        stages.add(const GeneratedStage(
          name: 'WILD_EXPAND_COMPLETE',
          description: 'Wild expansion animation complete',
          bus: 'sfx',
          priority: 73,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));

        stages.add(const GeneratedStage(
          name: 'WILD_EXPAND_REVERT',
          description: 'Expanded Wild reverts to normal',
          bus: 'sfx',
          priority: 68,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));
      }

      // Expansion type-specific stage
      final expansionStage = 'WILD_EXPAND_${expansion.toUpperCase()}';
      stages.add(GeneratedStage(
        name: expansionStage,
        description: '${_getExpansionLabel(expansion)} expansion effect',
        bus: 'sfx',
        priority: 71,
        sourceBlockId: id,
        category: 'Wild Features',
      ));
    }

    // ========== Sticky Stages ==========
    if (stickyDuration > 0) {
      if (hasStickySound) {
        stages.add(const GeneratedStage(
          name: 'WILD_STICK_APPLY',
          description: 'Wild becomes sticky',
          bus: 'sfx',
          priority: 69,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));

        stages.add(const GeneratedStage(
          name: 'WILD_STICK_PERSIST',
          description: 'Sticky Wild persists for another spin',
          bus: 'sfx',
          priority: 65,
          pooled: true,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));

        stages.add(const GeneratedStage(
          name: 'WILD_STICK_EXPIRE',
          description: 'Sticky Wild duration ends',
          bus: 'sfx',
          priority: 64,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));
      }
    }

    // ========== Walking Stages ==========
    if (walkingDirection != 'none') {
      if (hasWalkingSound) {
        stages.add(const GeneratedStage(
          name: 'WILD_WALK_MOVE',
          description: 'Walking Wild moves to new position',
          bus: 'sfx',
          priority: 67,
          pooled: true,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));

        stages.add(const GeneratedStage(
          name: 'WILD_WALK_ARRIVE',
          description: 'Walking Wild arrives at new position',
          bus: 'sfx',
          priority: 66,
          pooled: true,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));

        stages.add(const GeneratedStage(
          name: 'WILD_WALK_EXIT',
          description: 'Walking Wild exits the grid',
          bus: 'sfx',
          priority: 63,
          sourceBlockId: 'wild_features',
          category: 'Wild Features',
        ));
      }
    }

    // ========== Multiplier Stages ==========
    if (multipliers.isNotEmpty && hasMultiplierSound) {
      for (final mult in multipliers) {
        stages.add(GeneratedStage(
          name: 'WILD_MULT_APPLY_X$mult',
          description: 'Wild ×$mult multiplier applied to win',
          bus: 'sfx',
          priority: 74 + (mult ~/ 2).clamp(0, 5), // Higher mult = higher priority
          sourceBlockId: id,
          category: 'Wild Features',
        ));
      }

      // Generic multiplier apply stage (fallback)
      stages.add(const GeneratedStage(
        name: 'WILD_MULT_APPLY',
        description: 'Wild multiplier applied (generic)',
        bus: 'sfx',
        priority: 74,
        pooled: true,
        sourceBlockId: 'wild_features',
        category: 'Wild Features',
      ));
    }

    // ========== Stack Stages ==========
    if (hasStackSound) {
      // Per-height stack formation stages
      for (int height = 2; height <= stackHeight; height++) {
        stages.add(GeneratedStage(
          name: 'WILD_STACK_FORM_${height}STACK',
          description: '$height stacked Wilds formed',
          bus: 'sfx',
          priority: 70 + height,
          sourceBlockId: id,
          category: 'Wild Features',
        ));
      }

      // Full stack stage
      stages.add(GeneratedStage(
        name: 'WILD_STACK_FULL',
        description: 'Full Wild stack on reel',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
        category: 'Wild Features',
      ));
    }

    return stages;
  }

  String _getExpansionLabel(String expansion) {
    switch (expansion) {
      case 'full_reel':
        return 'Full reel';
      case 'cross':
        return 'Cross pattern';
      case 'adjacent':
        return 'Adjacent';
      default:
        return expansion;
    }
  }

  @override
  List<String> get pooledStages => [
        'WILD_LAND',
        'WILD_STICK_PERSIST',
        'WILD_WALK_MOVE',
        'WILD_WALK_ARRIVE',
        'WILD_MULT_APPLY',
      ];

  @override
  String getBusForStage(String stageName) => 'sfx';

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('MULT_APPLY_X10')) return 79;
    if (stageName.contains('MULT_APPLY_X5')) return 77;
    if (stageName.contains('MULT')) return 74;
    if (stageName.contains('STACK_FULL')) return 78;
    if (stageName.contains('STACK_FORM')) return 72;
    if (stageName.contains('EXPAND_COMPLETE')) return 73;
    if (stageName.contains('EXPAND')) return 71;
    if (stageName.contains('STICK_APPLY')) return 69;
    if (stageName.contains('WALK')) return 66;
    return 70;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get expansion type.
  WildExpansion get expansion {
    final value = getOptionValue<String>('expansion') ?? 'disabled';
    return WildExpansion.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WildExpansion.disabled,
    );
  }

  /// Get sticky duration in spins.
  int get stickyDuration =>
      getOptionValue<num>('sticky_duration')?.toInt() ?? 0;

  /// Whether sticky Wilds are enabled.
  bool get hasStickyWilds => stickyDuration > 0;

  /// Get walking direction.
  WalkingDirection? get walkingDirection {
    final value = getOptionValue<String>('walking_direction');
    if (value == null || value == 'none') return null;
    return WalkingDirection.values.firstWhere(
      (d) => d.name == value,
      orElse: () => WalkingDirection.left,
    );
  }

  /// Whether walking Wilds are enabled.
  bool get hasWalkingWilds =>
      getOptionValue<String>('walking_direction') != 'none';

  /// Get multiplier values.
  List<int> get multiplierRange {
    final values = getOptionValue<List<dynamic>>('multiplier_range');
    if (values == null) return [];
    return values.cast<int>();
  }

  /// Whether Wild multipliers are enabled.
  bool get hasWildMultipliers => multiplierRange.isNotEmpty;

  /// Get stack height.
  int get stackHeight => getOptionValue<num>('stack_height')?.toInt() ?? 3;

  /// Count of active Wild features.
  int get activeFeatureCount {
    int count = 0;
    if (expansion != WildExpansion.disabled) count++;
    if (hasStickyWilds) count++;
    if (hasWalkingWilds) count++;
    if (hasWildMultipliers) count++;
    return count;
  }

  // ============================================================================
  // Validation
  // ============================================================================

  /// Validate block configuration.
  ///
  /// Returns a list of validation errors and warnings.
  List<ValidationIssue> validateConfiguration(
      Map<String, FeatureBlock> allBlocks) {
    final issues = <ValidationIssue>[];

    // Check Wild symbol is enabled in Symbol Set
    final symbolSet = allBlocks['symbol_set'];
    if (symbolSet != null) {
      final hasWild = symbolSet.getOptionValue<bool>('hasWild') ?? false;
      if (!hasWild) {
        issues.add(ValidationIssue.error(
          code: 'E004',
          message: 'Wild symbol required for Wild Features',
          suggestion: 'Enable Wild in Symbol Set block',
        ));
      }
    }

    // Warn if too many features enabled simultaneously
    if (activeFeatureCount >= 3) {
      issues.add(ValidationIssue.warning(
        code: 'W004',
        message: 'Multiple Wild features enabled may be overwhelming',
        suggestion: 'Consider limiting to 2-3 features for player clarity',
      ));
    }

    // Warn if walking and sticky combined (unusual combo)
    if (hasStickyWilds && hasWalkingWilds) {
      issues.add(ValidationIssue.info(
        code: 'I001',
        message: 'Sticky + Walking Wilds combination detected',
        suggestion:
            'Ensure animations coordinate properly for sticky walking wilds',
      ));
    }

    return issues;
  }
}

/// Validation issue severity.
enum ValidationSeverity { error, warning, info }

/// A validation issue found during block validation.
class ValidationIssue {
  final ValidationSeverity severity;
  final String code;
  final String message;
  final String? suggestion;

  const ValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.suggestion,
  });

  factory ValidationIssue.error({
    required String code,
    required String message,
    String? suggestion,
  }) =>
      ValidationIssue(
        severity: ValidationSeverity.error,
        code: code,
        message: message,
        suggestion: suggestion,
      );

  factory ValidationIssue.warning({
    required String code,
    required String message,
    String? suggestion,
  }) =>
      ValidationIssue(
        severity: ValidationSeverity.warning,
        code: code,
        message: message,
        suggestion: suggestion,
      );

  factory ValidationIssue.info({
    required String code,
    required String message,
    String? suggestion,
  }) =>
      ValidationIssue(
        severity: ValidationSeverity.info,
        code: code,
        message: message,
        suggestion: suggestion,
      );

  bool get isError => severity == ValidationSeverity.error;
  bool get isWarning => severity == ValidationSeverity.warning;
  bool get isInfo => severity == ValidationSeverity.info;

  @override
  String toString() =>
      '[$code] ${severity.name.toUpperCase()}: $message${suggestion != null ? ' ($suggestion)' : ''}';
}
