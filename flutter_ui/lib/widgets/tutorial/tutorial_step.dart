/// Tutorial Step Model (M4)
///
/// Defines individual steps in an interactive tutorial.
/// Each step has content, target element, and optional actions.

import 'package:flutter/material.dart';

/// Position for tutorial tooltip
enum TutorialTooltipPosition {
  top,
  bottom,
  left,
  right,
  center,
}

/// Action type for tutorial step
enum TutorialActionType {
  next,       // Go to next step
  previous,   // Go to previous step
  skip,       // Skip entire tutorial
  finish,     // Complete tutorial
  custom,     // Custom callback
}

/// Tutorial step action
class TutorialAction {
  final String label;
  final TutorialActionType type;
  final VoidCallback? onAction;
  final bool isPrimary;

  const TutorialAction({
    required this.label,
    required this.type,
    this.onAction,
    this.isPrimary = false,
  });

  static const next = TutorialAction(
    label: 'Next',
    type: TutorialActionType.next,
    isPrimary: true,
  );

  static const previous = TutorialAction(
    label: 'Back',
    type: TutorialActionType.previous,
  );

  static const skip = TutorialAction(
    label: 'Skip',
    type: TutorialActionType.skip,
  );

  static const finish = TutorialAction(
    label: 'Done',
    type: TutorialActionType.finish,
    isPrimary: true,
  );
}

/// Single tutorial step
class TutorialStep {
  /// Unique step ID
  final String id;

  /// Step title
  final String title;

  /// Step description/content
  final String content;

  /// Optional image asset path
  final String? imagePath;

  /// Optional icon
  final IconData? icon;

  /// Target GlobalKey for highlight (null = no highlight)
  final GlobalKey? targetKey;

  /// Tooltip position relative to target
  final TutorialTooltipPosition tooltipPosition;

  /// Available actions for this step
  final List<TutorialAction> actions;

  /// Highlight padding around target element
  final double highlightPadding;

  /// Whether to show spotlight effect on target
  final bool showSpotlight;

  /// Optional validation before allowing next step
  final bool Function()? canProceed;

  /// Callback when step is shown
  final VoidCallback? onShow;

  /// Callback when step is hidden
  final VoidCallback? onHide;

  const TutorialStep({
    required this.id,
    required this.title,
    required this.content,
    this.imagePath,
    this.icon,
    this.targetKey,
    this.tooltipPosition = TutorialTooltipPosition.bottom,
    this.actions = const [TutorialAction.next],
    this.highlightPadding = 8.0,
    this.showSpotlight = true,
    this.canProceed,
    this.onShow,
    this.onHide,
  });

  TutorialStep copyWith({
    String? id,
    String? title,
    String? content,
    String? imagePath,
    IconData? icon,
    GlobalKey? targetKey,
    TutorialTooltipPosition? tooltipPosition,
    List<TutorialAction>? actions,
    double? highlightPadding,
    bool? showSpotlight,
    bool Function()? canProceed,
    VoidCallback? onShow,
    VoidCallback? onHide,
  }) {
    return TutorialStep(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      imagePath: imagePath ?? this.imagePath,
      icon: icon ?? this.icon,
      targetKey: targetKey ?? this.targetKey,
      tooltipPosition: tooltipPosition ?? this.tooltipPosition,
      actions: actions ?? this.actions,
      highlightPadding: highlightPadding ?? this.highlightPadding,
      showSpotlight: showSpotlight ?? this.showSpotlight,
      canProceed: canProceed ?? this.canProceed,
      onShow: onShow ?? this.onShow,
      onHide: onHide ?? this.onHide,
    );
  }
}

/// Complete tutorial definition
class Tutorial {
  /// Unique tutorial ID
  final String id;

  /// Tutorial name
  final String name;

  /// Tutorial description
  final String description;

  /// Tutorial steps
  final List<TutorialStep> steps;

  /// Estimated completion time in minutes
  final int estimatedMinutes;

  /// Tutorial category
  final TutorialCategory category;

  /// Difficulty level
  final TutorialDifficulty difficulty;

  /// Required previous tutorials (IDs)
  final List<String> prerequisites;

  const Tutorial({
    required this.id,
    required this.name,
    required this.description,
    required this.steps,
    this.estimatedMinutes = 5,
    this.category = TutorialCategory.basics,
    this.difficulty = TutorialDifficulty.beginner,
    this.prerequisites = const [],
  });
}

/// Tutorial category
enum TutorialCategory {
  basics,
  events,
  containers,
  rtpc,
  mixing,
  advanced,
}

extension TutorialCategoryExtension on TutorialCategory {
  String get displayName {
    switch (this) {
      case TutorialCategory.basics:
        return 'Getting Started';
      case TutorialCategory.events:
        return 'Audio Events';
      case TutorialCategory.containers:
        return 'Containers';
      case TutorialCategory.rtpc:
        return 'RTPC & Parameters';
      case TutorialCategory.mixing:
        return 'Mixing & Buses';
      case TutorialCategory.advanced:
        return 'Advanced Features';
    }
  }

  IconData get icon {
    switch (this) {
      case TutorialCategory.basics:
        return Icons.school;
      case TutorialCategory.events:
        return Icons.event;
      case TutorialCategory.containers:
        return Icons.inventory_2;
      case TutorialCategory.rtpc:
        return Icons.tune;
      case TutorialCategory.mixing:
        return Icons.equalizer;
      case TutorialCategory.advanced:
        return Icons.psychology;
    }
  }
}

/// Tutorial difficulty level
enum TutorialDifficulty {
  beginner,
  intermediate,
  advanced,
}

extension TutorialDifficultyExtension on TutorialDifficulty {
  String get displayName {
    switch (this) {
      case TutorialDifficulty.beginner:
        return 'Beginner';
      case TutorialDifficulty.intermediate:
        return 'Intermediate';
      case TutorialDifficulty.advanced:
        return 'Advanced';
    }
  }

  Color get color {
    switch (this) {
      case TutorialDifficulty.beginner:
        return const Color(0xFF4CAF50);
      case TutorialDifficulty.intermediate:
        return const Color(0xFFFFC107);
      case TutorialDifficulty.advanced:
        return const Color(0xFFFF5722);
    }
  }
}
