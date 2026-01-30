/// P0 WF-08: Test Template Library Models (2026-01-30)
///
/// Data-driven test scenarios for slot audio QA validation.
/// Enables systematic testing of common gameplay patterns.

import 'package:flutter/material.dart';

/// Test template category
enum TestTemplateCategory {
  winSequences('Win Sequences', Icons.emoji_events, Color(0xFFFFC107)),
  featureTriggers('Feature Triggers', Icons.stars, Color(0xFF9C27B0)),
  cascadeMechanics('Cascade Mechanics', Icons.layers, Color(0xFF2196F3)),
  edgeCases('Edge Cases', Icons.warning, Color(0xFFFF5722)),
  musicTransitions('Music Transitions', Icons.music_note, Color(0xFF4CAF50)),
  fullSessions('Full Sessions', Icons.casino, Color(0xFF9E9E9E));

  final String displayName;
  final IconData icon;
  final Color color;

  const TestTemplateCategory(this.displayName, this.icon, this.color);
}

/// Stage trigger with optional delay and context
class TestStageAction {
  final String stage;
  final int delayMs;
  final Map<String, dynamic>? context;

  const TestStageAction({
    required this.stage,
    this.delayMs = 0,
    this.context,
  });

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'delayMs': delayMs,
    'context': context,
  };

  factory TestStageAction.fromJson(Map<String, dynamic> json) {
    return TestStageAction(
      stage: json['stage'] as String,
      delayMs: json['delayMs'] as int? ?? 0,
      context: json['context'] as Map<String, dynamic>?,
    );
  }
}

/// Complete test template
class TestTemplate {
  final String id;
  final String name;
  final String description;
  final TestTemplateCategory category;
  final List<TestStageAction> actions;
  final int estimatedDurationMs;
  final List<String> tags;
  final Map<String, dynamic>? expectedResults;

  const TestTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.actions,
    this.estimatedDurationMs = 0,
    this.tags = const [],
    this.expectedResults,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category.name,
    'actions': actions.map((a) => a.toJson()).toList(),
    'estimatedDurationMs': estimatedDurationMs,
    'tags': tags,
    'expectedResults': expectedResults,
  };

  factory TestTemplate.fromJson(Map<String, dynamic> json) {
    return TestTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      category: TestTemplateCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => TestTemplateCategory.edgeCases,
      ),
      actions: (json['actions'] as List)
          .map((a) => TestStageAction.fromJson(a as Map<String, dynamic>))
          .toList(),
      estimatedDurationMs: json['estimatedDurationMs'] as int? ?? 0,
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      expectedResults: json['expectedResults'] as Map<String, dynamic>?,
    );
  }
}

/// Built-in test templates
class BuiltInTestTemplates {
  /// Simple Win: Basic win flow with rollup
  static TestTemplate simpleWin() => const TestTemplate(
    id: 'simple_win',
    name: 'Simple Win',
    description: 'Basic win flow: spin → stop → win present → rollup',
    category: TestTemplateCategory.winSequences,
    estimatedDurationMs: 3500,
    tags: ['basic', 'win', 'rollup'],
    actions: [
      TestStageAction(stage: 'SPIN_START', delayMs: 0),
      TestStageAction(stage: 'REEL_STOP_0', delayMs: 400),
      TestStageAction(stage: 'REEL_STOP_1', delayMs: 800),
      TestStageAction(stage: 'REEL_STOP_2', delayMs: 1200),
      TestStageAction(stage: 'REEL_STOP_3', delayMs: 1600),
      TestStageAction(stage: 'REEL_STOP_4', delayMs: 2000),
      TestStageAction(stage: 'WIN_PRESENT', delayMs: 2300),
      TestStageAction(stage: 'ROLLUP_START', delayMs: 2500),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 2600),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 2700),
      TestStageAction(stage: 'ROLLUP_END', delayMs: 3300),
    ],
    expectedResults: {'audioPlays': 11, 'totalBuses': 3},
  );

  /// Cascade: Multi-step cascade sequence
  static TestTemplate cascade() => const TestTemplate(
    id: 'cascade',
    name: 'Cascade Sequence',
    description: 'Multi-step cascade with escalating audio',
    category: TestTemplateCategory.cascadeMechanics,
    estimatedDurationMs: 4500,
    tags: ['cascade', 'tumble', 'multi-step'],
    actions: [
      TestStageAction(stage: 'SPIN_START', delayMs: 0),
      TestStageAction(stage: 'REEL_STOP_4', delayMs: 2000),
      TestStageAction(stage: 'CASCADE_START', delayMs: 2300),
      TestStageAction(stage: 'CASCADE_STEP', delayMs: 2600, context: {'step_index': 0}),
      TestStageAction(stage: 'CASCADE_STEP', delayMs: 3000, context: {'step_index': 1}),
      TestStageAction(stage: 'CASCADE_STEP', delayMs: 3400, context: {'step_index': 2}),
      TestStageAction(stage: 'CASCADE_END', delayMs: 4200),
    ],
    expectedResults: {'cascadeSteps': 3, 'pitchEscalation': true},
  );

  /// Feature Trigger: Free spins trigger with anticipation
  static TestTemplate featureTrigger() => const TestTemplate(
    id: 'feature_trigger',
    name: 'Feature Trigger',
    description: 'Free spins trigger with anticipation and transition',
    category: TestTemplateCategory.featureTriggers,
    estimatedDurationMs: 5000,
    tags: ['feature', 'free-spins', 'anticipation'],
    actions: [
      TestStageAction(stage: 'SPIN_START', delayMs: 0),
      TestStageAction(stage: 'REEL_STOP_0', delayMs: 400),
      TestStageAction(stage: 'REEL_STOP_1', delayMs: 800),
      TestStageAction(stage: 'ANTICIPATION_ON', delayMs: 1100, context: {'reason': 'scatter'}),
      TestStageAction(stage: 'REEL_STOP_2', delayMs: 1400),
      TestStageAction(stage: 'REEL_STOP_3', delayMs: 2000),
      TestStageAction(stage: 'REEL_STOP_4', delayMs: 2600),
      TestStageAction(stage: 'ANTICIPATION_OFF', delayMs: 2900),
      TestStageAction(stage: 'FEATURE_TRIGGER', delayMs: 3100),
      TestStageAction(stage: 'FS_ENTER', delayMs: 3500),
    ],
    expectedResults: {'anticipationTriggered': true, 'featureEntered': true},
  );

  /// Multi-Feature: Back-to-back feature triggers
  static TestTemplate multiFeature() => const TestTemplate(
    id: 'multi_feature',
    name: 'Multi-Feature Test',
    description: 'Tests handling of multiple simultaneous features',
    category: TestTemplateCategory.edgeCases,
    estimatedDurationMs: 8000,
    tags: ['edge-case', 'multi-feature', 'stress'],
    actions: [
      TestStageAction(stage: 'SPIN_START', delayMs: 0),
      TestStageAction(stage: 'REEL_STOP_4', delayMs: 2000),
      TestStageAction(stage: 'FS_TRIGGER', delayMs: 2300),
      TestStageAction(stage: 'BONUS_TRIGGER', delayMs: 2500),
      TestStageAction(stage: 'HOLD_TRIGGER', delayMs: 2700),
      TestStageAction(stage: 'FS_ENTER', delayMs: 3000),
      TestStageAction(stage: 'BONUS_ENTER', delayMs: 3200), // Conflict!
      TestStageAction(stage: 'FS_SPIN', delayMs: 4000),
      TestStageAction(stage: 'FS_EXIT', delayMs: 7000),
    ],
    expectedResults: {'priorityConflict': true, 'voiceLimit': true},
  );

  /// Edge Cases: Rapid-fire events, voice limits
  static TestTemplate edgeCases() => const TestTemplate(
    id: 'edge_cases',
    name: 'Edge Cases',
    description: 'Rapid-fire events to test voice pooling and limits',
    category: TestTemplateCategory.edgeCases,
    estimatedDurationMs: 2000,
    tags: ['edge-case', 'voice-pool', 'polyphony'],
    actions: [
      // 20 rapid rollup ticks (should use voice pooling)
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 0),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 50),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 100),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 150),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 200),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 250),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 300),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 350),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 400),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 450),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 500),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 550),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 600),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 650),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 700),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 750),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 800),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 850),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 900),
      TestStageAction(stage: 'ROLLUP_TICK', delayMs: 950),
    ],
    expectedResults: {'poolHitRate': '>0.8', 'voicesPeaked': true},
  );

  /// Get all built-in templates
  static List<TestTemplate> getAll() => [
    simpleWin(),
    cascade(),
    featureTrigger(),
    multiFeature(),
    edgeCases(),
  ];

  /// Get templates by category
  static List<TestTemplate> getByCategory(TestTemplateCategory category) {
    return getAll().where((t) => t.category == category).toList();
  }

  /// Get templates by tag
  static List<TestTemplate> getByTag(String tag) {
    return getAll().where((t) => t.tags.contains(tag)).toList();
  }
}
