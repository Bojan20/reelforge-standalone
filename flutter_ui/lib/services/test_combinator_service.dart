// test_combinator_service.dart
// Multi-condition test case combinator service
// Generates exhaustive test cases for all combinations of win tiers, features, cascades, anticipation

import 'dart:convert';

/// Test condition dimension
enum TestDimension {
  winTier,
  feature,
  cascade,
  anticipation,
  betLevel,
  balanceState,
}

/// Win tier test values
enum WinTierTest {
  noWin,
  smallWin,
  bigWin,
  superWin,
  megaWin,
  epicWin,
  ultraWin,
}

/// Feature test values
enum FeatureTest {
  none,
  freeSpins,
  bonus,
  holdWin,
  jackpotMini,
  jackpotGrand,
}

/// Cascade test values
enum CascadeTest {
  none,
  single,
  double,
  triple,
  chain5plus,
}

/// Anticipation test values
enum AnticipationTest {
  none,
  nearMiss,
  twoScatters,
  threeScatters,
}

/// Bet level test values
enum BetLevelTest {
  minimum,
  low,
  medium,
  high,
  maximum,
}

/// Balance state test values
enum BalanceStateTest {
  lowBalance,
  normal,
  highRoller,
}

/// Single test case
class TestCase {
  final int id;
  final Map<TestDimension, dynamic> conditions;
  final String description;
  final Set<String> expectedStages;
  final Duration estimatedDuration;

  const TestCase({
    required this.id,
    required this.conditions,
    required this.description,
    required this.expectedStages,
    required this.estimatedDuration,
  });

  T? getCondition<T>(TestDimension dimension) {
    return conditions[dimension] as T?;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conditions': conditions.map(
          (k, v) => MapEntry(k.name, v.toString().split('.').last),
        ),
        'description': description,
        'expectedStages': expectedStages.toList(),
        'estimatedDurationMs': estimatedDuration.inMilliseconds,
      };

  factory TestCase.fromJson(Map<String, dynamic> json) {
    return TestCase(
      id: json['id'] as int,
      conditions: (json['conditions'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          TestDimension.values.firstWhere((d) => d.name == k),
          v,
        ),
      ),
      description: json['description'] as String,
      expectedStages: (json['expectedStages'] as List).cast<String>().toSet(),
      estimatedDuration: Duration(milliseconds: json['estimatedDurationMs'] as int),
    );
  }
}

/// Test suite with multiple cases
class TestSuite {
  final String name;
  final List<TestCase> cases;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  const TestSuite({
    required this.name,
    required this.cases,
    required this.createdAt,
    required this.metadata,
  });

  int get totalCases => cases.length;

  Duration get estimatedTotalDuration {
    return cases.fold(
      Duration.zero,
      (sum, test) => sum + test.estimatedDuration,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'cases': cases.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'metadata': metadata,
      };

  factory TestSuite.fromJson(Map<String, dynamic> json) {
    return TestSuite(
      name: json['name'] as String,
      cases: (json['cases'] as List).map((c) => TestCase.fromJson(c)).toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      metadata: json['metadata'] as Map<String, dynamic>,
    );
  }
}

/// Test combinator service
class TestCombinatorService {
  static final TestCombinatorService instance = TestCombinatorService._();

  TestCombinatorService._();

  /// Generate all combinations for selected dimensions
  TestSuite generateCombinations({
    required String suiteName,
    required Set<TestDimension> dimensions,
    Map<String, dynamic>? metadata,
  }) {
    final List<TestCase> cases = [];
    int caseId = 1;

    // Get all value combinations
    final dimensionValues = _getDimensionValues(dimensions);

    // Generate cartesian product
    _generateCartesianProduct(
      dimensionValues: dimensionValues,
      currentConditions: {},
      cases: cases,
      caseId: caseId,
    );

    return TestSuite(
      name: suiteName,
      cases: cases,
      createdAt: DateTime.now(),
      metadata: metadata ?? {},
    );
  }

  /// Generate quick test suite (common combinations only)
  TestSuite generateQuickSuite({String? name}) {
    return generateCombinations(
      suiteName: name ?? 'Quick Test Suite',
      dimensions: {
        TestDimension.winTier,
        TestDimension.feature,
      },
      metadata: {'type': 'quick'},
    );
  }

  /// Generate comprehensive test suite (all dimensions)
  TestSuite generateComprehensiveSuite({String? name}) {
    return generateCombinations(
      suiteName: name ?? 'Comprehensive Test Suite',
      dimensions: TestDimension.values.toSet(),
      metadata: {'type': 'comprehensive'},
    );
  }

  /// Generate feature-focused suite
  TestSuite generateFeatureSuite({String? name}) {
    return generateCombinations(
      suiteName: name ?? 'Feature Test Suite',
      dimensions: {
        TestDimension.feature,
        TestDimension.cascade,
        TestDimension.anticipation,
      },
      metadata: {'type': 'feature'},
    );
  }

  /// Get dimension values
  Map<TestDimension, List<dynamic>> _getDimensionValues(Set<TestDimension> dimensions) {
    final Map<TestDimension, List<dynamic>> values = {};

    for (final dimension in dimensions) {
      switch (dimension) {
        case TestDimension.winTier:
          values[dimension] = WinTierTest.values;
          break;
        case TestDimension.feature:
          values[dimension] = FeatureTest.values;
          break;
        case TestDimension.cascade:
          values[dimension] = CascadeTest.values;
          break;
        case TestDimension.anticipation:
          values[dimension] = AnticipationTest.values;
          break;
        case TestDimension.betLevel:
          values[dimension] = BetLevelTest.values;
          break;
        case TestDimension.balanceState:
          values[dimension] = BalanceStateTest.values;
          break;
      }
    }

    return values;
  }

  /// Generate cartesian product recursively
  void _generateCartesianProduct({
    required Map<TestDimension, List<dynamic>> dimensionValues,
    required Map<TestDimension, dynamic> currentConditions,
    required List<TestCase> cases,
    required int caseId,
  }) {
    if (currentConditions.length == dimensionValues.length) {
      // All dimensions filled, create test case
      final testCase = _createTestCase(
        id: cases.length + 1,
        conditions: Map.from(currentConditions),
      );
      cases.add(testCase);
      return;
    }

    // Get next dimension to fill
    final remainingDimensions = dimensionValues.keys
        .where((d) => !currentConditions.containsKey(d))
        .toList();

    if (remainingDimensions.isEmpty) return;

    final nextDimension = remainingDimensions.first;
    final values = dimensionValues[nextDimension]!;

    // Recurse for each value
    for (final value in values) {
      final newConditions = Map<TestDimension, dynamic>.from(currentConditions);
      newConditions[nextDimension] = value;

      _generateCartesianProduct(
        dimensionValues: dimensionValues,
        currentConditions: newConditions,
        cases: cases,
        caseId: caseId,
      );
    }
  }

  /// Create test case from conditions
  TestCase _createTestCase({
    required int id,
    required Map<TestDimension, dynamic> conditions,
  }) {
    final description = _generateDescription(conditions);
    final expectedStages = _generateExpectedStages(conditions);
    final estimatedDuration = _estimateDuration(conditions);

    return TestCase(
      id: id,
      conditions: conditions,
      description: description,
      expectedStages: expectedStages,
      estimatedDuration: estimatedDuration,
    );
  }

  /// Generate human-readable description
  String _generateDescription(Map<TestDimension, dynamic> conditions) {
    final parts = <String>[];

    if (conditions.containsKey(TestDimension.winTier)) {
      final winTier = conditions[TestDimension.winTier] as WinTierTest;
      parts.add(_winTierToString(winTier));
    }

    if (conditions.containsKey(TestDimension.feature)) {
      final feature = conditions[TestDimension.feature] as FeatureTest;
      if (feature != FeatureTest.none) {
        parts.add('with ${_featureToString(feature)}');
      }
    }

    if (conditions.containsKey(TestDimension.cascade)) {
      final cascade = conditions[TestDimension.cascade] as CascadeTest;
      if (cascade != CascadeTest.none) {
        parts.add('and ${_cascadeToString(cascade)}');
      }
    }

    if (conditions.containsKey(TestDimension.anticipation)) {
      final anticipation = conditions[TestDimension.anticipation] as AnticipationTest;
      if (anticipation != AnticipationTest.none) {
        parts.add('with ${_anticipationToString(anticipation)}');
      }
    }

    return parts.join(' ');
  }

  /// Generate expected stages
  Set<String> _generateExpectedStages(Map<TestDimension, dynamic> conditions) {
    final stages = <String>{'SPIN_START', 'SPIN_END'};

    // Win tier stages
    if (conditions.containsKey(TestDimension.winTier)) {
      final winTier = conditions[TestDimension.winTier] as WinTierTest;
      if (winTier != WinTierTest.noWin) {
        stages.addAll(['WIN_PRESENT', 'ROLLUP_START', 'ROLLUP_END']);

        if (winTier.index >= WinTierTest.bigWin.index) {
          stages.add('WIN_PRESENT_BIG');
        }
      }
    }

    // Feature stages
    if (conditions.containsKey(TestDimension.feature)) {
      final feature = conditions[TestDimension.feature] as FeatureTest;
      switch (feature) {
        case FeatureTest.freeSpins:
          stages.addAll(['FS_TRIGGER', 'FS_ENTER']);
          break;
        case FeatureTest.bonus:
          stages.addAll(['BONUS_TRIGGER', 'BONUS_ENTER']);
          break;
        case FeatureTest.holdWin:
          stages.addAll(['HOLD_TRIGGER', 'HOLD_ENTER']);
          break;
        case FeatureTest.jackpotMini:
        case FeatureTest.jackpotGrand:
          stages.addAll(['JACKPOT_TRIGGER', 'JACKPOT_REVEAL']);
          break;
        case FeatureTest.none:
          break;
      }
    }

    // Cascade stages
    if (conditions.containsKey(TestDimension.cascade)) {
      final cascade = conditions[TestDimension.cascade] as CascadeTest;
      if (cascade != CascadeTest.none) {
        stages.addAll(['CASCADE_START', 'CASCADE_STEP', 'CASCADE_END']);
      }
    }

    // Anticipation stages
    if (conditions.containsKey(TestDimension.anticipation)) {
      final anticipation = conditions[TestDimension.anticipation] as AnticipationTest;
      if (anticipation != AnticipationTest.none) {
        stages.addAll(['ANTICIPATION_ON', 'ANTICIPATION_OFF']);
      }
    }

    return stages;
  }

  /// Estimate duration
  Duration _estimateDuration(Map<TestDimension, dynamic> conditions) {
    int totalMs = 2000; // Base spin time

    // Win tier adds time
    if (conditions.containsKey(TestDimension.winTier)) {
      final winTier = conditions[TestDimension.winTier] as WinTierTest;
      totalMs += winTier.index * 500;
    }

    // Features add time
    if (conditions.containsKey(TestDimension.feature)) {
      final feature = conditions[TestDimension.feature] as FeatureTest;
      if (feature != FeatureTest.none) {
        totalMs += 1500;
      }
    }

    // Cascades add time
    if (conditions.containsKey(TestDimension.cascade)) {
      final cascade = conditions[TestDimension.cascade] as CascadeTest;
      totalMs += cascade.index * 800;
    }

    return Duration(milliseconds: totalMs);
  }

  // Helper string conversions
  String _winTierToString(WinTierTest tier) {
    switch (tier) {
      case WinTierTest.noWin:
        return 'No Win';
      case WinTierTest.smallWin:
        return 'Small Win';
      case WinTierTest.bigWin:
        return 'Big Win';
      case WinTierTest.superWin:
        return 'Super Win';
      case WinTierTest.megaWin:
        return 'Mega Win';
      case WinTierTest.epicWin:
        return 'Epic Win';
      case WinTierTest.ultraWin:
        return 'Ultra Win';
    }
  }

  String _featureToString(FeatureTest feature) {
    switch (feature) {
      case FeatureTest.none:
        return 'None';
      case FeatureTest.freeSpins:
        return 'Free Spins';
      case FeatureTest.bonus:
        return 'Bonus';
      case FeatureTest.holdWin:
        return 'Hold & Win';
      case FeatureTest.jackpotMini:
        return 'Jackpot Mini';
      case FeatureTest.jackpotGrand:
        return 'Jackpot Grand';
    }
  }

  String _cascadeToString(CascadeTest cascade) {
    switch (cascade) {
      case CascadeTest.none:
        return 'None';
      case CascadeTest.single:
        return 'Single Cascade';
      case CascadeTest.double:
        return 'Double Cascade';
      case CascadeTest.triple:
        return 'Triple Cascade';
      case CascadeTest.chain5plus:
        return '5+ Cascade Chain';
    }
  }

  String _anticipationToString(AnticipationTest anticipation) {
    switch (anticipation) {
      case AnticipationTest.none:
        return 'None';
      case AnticipationTest.nearMiss:
        return 'Near Miss';
      case AnticipationTest.twoScatters:
        return '2 Scatters';
      case AnticipationTest.threeScatters:
        return '3 Scatters';
    }
  }

  /// Export suite to JSON
  String exportSuiteToJson(TestSuite suite) {
    return const JsonEncoder.withIndent('  ').convert(suite.toJson());
  }

  /// Import suite from JSON
  TestSuite importSuiteFromJson(String json) {
    return TestSuite.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }
}
