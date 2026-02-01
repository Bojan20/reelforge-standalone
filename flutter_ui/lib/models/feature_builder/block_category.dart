// ============================================================================
// FluxForge Studio — Feature Builder Block Category
// ============================================================================
// P13.0.2: Block categories for Feature Builder Panel
// Defines the four main categories of feature blocks.
// ============================================================================

/// Categories for feature blocks in the Feature Builder Panel.
///
/// Blocks are organized into categories for better UX and logical grouping.
/// Each category has a display name, icon, and color for UI rendering.
enum BlockCategory {
  /// Core blocks that define the fundamental game structure.
  /// Examples: Game Core, Grid, Symbol Set
  core,

  /// Feature blocks that add gameplay mechanics.
  /// Examples: Free Spins, Respins, Hold & Win, Cascades, Collector
  feature,

  /// Presentation blocks that control audio/visual feedback.
  /// Examples: Win Presentation, Music States, Transitions
  presentation,

  /// Bonus blocks for additional game features.
  /// Examples: Anticipation, Jackpot, Wild Features, Bonus Game
  bonus,
}

/// Extension providing display properties for [BlockCategory].
extension BlockCategoryExtension on BlockCategory {
  /// Human-readable display name for the category.
  String get displayName {
    switch (this) {
      case BlockCategory.core:
        return 'Core';
      case BlockCategory.feature:
        return 'Features';
      case BlockCategory.presentation:
        return 'Presentation';
      case BlockCategory.bonus:
        return 'Bonus';
    }
  }

  /// Short description of the category's purpose.
  String get description {
    switch (this) {
      case BlockCategory.core:
        return 'Fundamental game structure';
      case BlockCategory.feature:
        return 'Gameplay mechanics';
      case BlockCategory.presentation:
        return 'Audio/visual feedback';
      case BlockCategory.bonus:
        return 'Additional features';
    }
  }

  /// Icon name for the category (Material Icons).
  String get iconName {
    switch (this) {
      case BlockCategory.core:
        return 'settings';
      case BlockCategory.feature:
        return 'extension';
      case BlockCategory.presentation:
        return 'palette';
      case BlockCategory.bonus:
        return 'star';
    }
  }

  /// Hex color code for the category.
  int get colorValue {
    switch (this) {
      case BlockCategory.core:
        return 0xFF4A9EFF; // Blue
      case BlockCategory.feature:
        return 0xFF40FF90; // Green
      case BlockCategory.presentation:
        return 0xFFFFD700; // Gold
      case BlockCategory.bonus:
        return 0xFF9370DB; // Purple
    }
  }

  /// Sort order for display (lower = first).
  int get sortOrder {
    switch (this) {
      case BlockCategory.core:
        return 0;
      case BlockCategory.feature:
        return 1;
      case BlockCategory.presentation:
        return 2;
      case BlockCategory.bonus:
        return 3;
    }
  }

  /// Whether blocks in this category can be disabled.
  /// Core blocks are always required.
  bool get isOptional {
    switch (this) {
      case BlockCategory.core:
        return false;
      case BlockCategory.feature:
      case BlockCategory.presentation:
      case BlockCategory.bonus:
        return true;
    }
  }
}

/// Utility class for working with block categories.
class BlockCategories {
  BlockCategories._();

  /// All categories in display order.
  static List<BlockCategory> get all => BlockCategory.values.toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Only optional categories (excludes core).
  static List<BlockCategory> get optional =>
      all.where((c) => c.isOptional).toList();

  /// Get category by name (case-insensitive).
  static BlockCategory? fromName(String name) {
    final normalized = name.toLowerCase().trim();
    for (final category in BlockCategory.values) {
      if (category.name.toLowerCase() == normalized ||
          category.displayName.toLowerCase() == normalized) {
        return category;
      }
    }
    return null;
  }
}
