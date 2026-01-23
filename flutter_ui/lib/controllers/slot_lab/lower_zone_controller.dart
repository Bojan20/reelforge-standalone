// Lower Zone Controller — SlotLab Collapsible Bottom Panel
//
// Manages the state of SlotLab's lower zone:
// - Tab switching (Timeline, Command Builder, Event List, Meters)
// - Expand/collapse animation
// - Resizable height (100-500px)
// - Keyboard shortcuts (1-4 for tabs, ` for toggle)
//
// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 15.3

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ============ Types ============

/// Tab categories for logical grouping (M3 Sprint - P1)
enum LowerZoneCategory {
  audio,    // Events, Event Log, Meters, Command Builder
  routing,  // Buses, Aux Sends
  debug,    // Timeline, Profiler, RTPC, Resources
  advanced, // AutoSpatial, Stage Ingest, GDD Import, Game Model, Scenarios
}

/// Configuration for tab categories
class LowerZoneCategoryConfig {
  final LowerZoneCategory category;
  final String label;
  final String icon;
  final String description;

  const LowerZoneCategoryConfig({
    required this.category,
    required this.label,
    required this.icon,
    required this.description,
  });
}

/// Category configurations
const Map<LowerZoneCategory, LowerZoneCategoryConfig> kLowerZoneCategoryConfigs = {
  LowerZoneCategory.audio: LowerZoneCategoryConfig(
    category: LowerZoneCategory.audio,
    label: 'Audio',
    icon: '🎵',
    description: 'Events, containers, meters',
  ),
  LowerZoneCategory.routing: LowerZoneCategoryConfig(
    category: LowerZoneCategory.routing,
    label: 'Routing',
    icon: '🔀',
    description: 'Buses, sends, hierarchy',
  ),
  LowerZoneCategory.debug: LowerZoneCategoryConfig(
    category: LowerZoneCategory.debug,
    label: 'Debug',
    icon: '🐛',
    description: 'Profiler, RTPC, timeline',
  ),
  LowerZoneCategory.advanced: LowerZoneCategoryConfig(
    category: LowerZoneCategory.advanced,
    label: 'Advanced',
    icon: '⚙️',
    description: 'Spatial, ingest, GDD',
  ),
};

/// Available tabs in the SlotLab lower zone
enum LowerZoneTab {
  timeline,       // Stage trace timeline
  commandBuilder, // Auto Event Builder command panel
  eventList,      // Event list browser
  meters,         // Audio bus meters
  // DSP Panels (FabFilter-style)
  dspCompressor,  // Pro-C style compressor
  dspLimiter,     // Pro-L style limiter
  dspGate,        // Pro-G style gate
  dspReverb,      // Pro-R style reverb
}

/// Configuration for each lower zone tab
class LowerZoneTabConfig {
  final LowerZoneTab tab;
  final String label;
  final String icon;
  final String shortcutKey;
  final String description;
  final LowerZoneCategory category;

  const LowerZoneTabConfig({
    required this.tab,
    required this.label,
    required this.icon,
    required this.shortcutKey,
    required this.description,
    required this.category,
  });
}

// ============ Tab Configurations ============

const Map<LowerZoneTab, LowerZoneTabConfig> kLowerZoneTabConfigs = {
  LowerZoneTab.timeline: LowerZoneTabConfig(
    tab: LowerZoneTab.timeline,
    label: 'Timeline',
    icon: '⏱',
    shortcutKey: '1',
    description: 'Stage trace timeline',
    category: LowerZoneCategory.debug,
  ),
  LowerZoneTab.commandBuilder: LowerZoneTabConfig(
    tab: LowerZoneTab.commandBuilder,
    label: 'Command',
    icon: '🔧',
    shortcutKey: '2',
    description: 'Auto Event Builder',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.eventList: LowerZoneTabConfig(
    tab: LowerZoneTab.eventList,
    label: 'Events',
    icon: '📋',
    shortcutKey: '3',
    description: 'Event list browser',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.meters: LowerZoneTabConfig(
    tab: LowerZoneTab.meters,
    label: 'Meters',
    icon: '📊',
    shortcutKey: '4',
    description: 'Audio bus meters',
    category: LowerZoneCategory.audio,
  ),
  // DSP Panels (FabFilter-style)
  LowerZoneTab.dspCompressor: LowerZoneTabConfig(
    tab: LowerZoneTab.dspCompressor,
    label: 'Compressor',
    icon: '🎚',
    shortcutKey: '5',
    description: 'Pro-C style compressor',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.dspLimiter: LowerZoneTabConfig(
    tab: LowerZoneTab.dspLimiter,
    label: 'Limiter',
    icon: '🔊',
    shortcutKey: '6',
    description: 'Pro-L style limiter',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.dspGate: LowerZoneTabConfig(
    tab: LowerZoneTab.dspGate,
    label: 'Gate',
    icon: '🚪',
    shortcutKey: '7',
    description: 'Pro-G style gate',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.dspReverb: LowerZoneTabConfig(
    tab: LowerZoneTab.dspReverb,
    label: 'Reverb',
    icon: '🌊',
    shortcutKey: '8',
    description: 'Pro-R style reverb',
    category: LowerZoneCategory.audio,
  ),
};

// ============ Category Helpers ============

/// Get all tabs in a specific category
List<LowerZoneTabConfig> getTabsInCategory(LowerZoneCategory category) {
  return kLowerZoneTabConfigs.values
      .where((config) => config.category == category)
      .toList();
}

/// Get tabs grouped by category
Map<LowerZoneCategory, List<LowerZoneTabConfig>> getTabsByCategory() {
  final result = <LowerZoneCategory, List<LowerZoneTabConfig>>{};
  for (final category in LowerZoneCategory.values) {
    result[category] = getTabsInCategory(category);
  }
  return result;
}

/// Get category for a specific tab
LowerZoneCategory? getCategoryForTab(LowerZoneTab tab) {
  return kLowerZoneTabConfigs[tab]?.category;
}

// ============ Constants ============

/// Minimum height of the lower zone when expanded
const double kLowerZoneMinHeight = 100.0;

/// Maximum height of the lower zone
const double kLowerZoneMaxHeight = 500.0;

/// Default height of the lower zone
const double kLowerZoneDefaultHeight = 250.0;

/// Height of the lower zone header (always visible)
const double kLowerZoneHeaderHeight = 36.0;

/// Animation duration for expand/collapse
const Duration kLowerZoneAnimationDuration = Duration(milliseconds: 200);

// ============ Controller ============

/// Controller for SlotLab's lower zone panel
///
/// Manages tab state, expand/collapse, resizable height, and category collapse state.
/// Follows the same pattern as EditorModeProvider.
class LowerZoneController extends ChangeNotifier {
  LowerZoneTab _activeTab;
  bool _isExpanded;
  double _height;

  /// Category collapse state (M3 Sprint - P1)
  final Map<LowerZoneCategory, bool> _categoryCollapsed = {
    LowerZoneCategory.audio: false,
    LowerZoneCategory.routing: false,
    LowerZoneCategory.debug: false,
    LowerZoneCategory.advanced: true, // Advanced collapsed by default
  };

  LowerZoneController({
    LowerZoneTab initialTab = LowerZoneTab.timeline,
    bool initialExpanded = true,
    double initialHeight = kLowerZoneDefaultHeight,
  })  : _activeTab = initialTab,
        _isExpanded = initialExpanded,
        _height = initialHeight.clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);

  // ============ Getters ============

  /// Currently active tab
  LowerZoneTab get activeTab => _activeTab;

  /// Whether the lower zone content is visible
  bool get isExpanded => _isExpanded;

  /// Current height of the content area (excludes header)
  double get height => _height;

  /// Total height including header
  double get totalHeight => _isExpanded ? _height + kLowerZoneHeaderHeight : kLowerZoneHeaderHeight;

  /// Configuration for the active tab
  LowerZoneTabConfig get activeTabConfig => kLowerZoneTabConfigs[_activeTab]!;

  /// All available tab configurations
  List<LowerZoneTabConfig> get tabs => kLowerZoneTabConfigs.values.toList();

  /// Whether a specific tab is active
  bool isTabActive(LowerZoneTab tab) => _activeTab == tab;

  // ============ Category Getters (M3 Sprint - P1) ============

  /// Get collapse state for a category
  bool isCategoryCollapsed(LowerZoneCategory category) =>
      _categoryCollapsed[category] ?? false;

  /// Get all category collapse states
  Map<LowerZoneCategory, bool> get categoryCollapseStates =>
      Map.unmodifiable(_categoryCollapsed);

  /// Get tabs in a category
  List<LowerZoneTabConfig> tabsInCategory(LowerZoneCategory category) =>
      getTabsInCategory(category);

  /// Get all category configurations
  List<LowerZoneCategoryConfig> get categoryConfigs =>
      kLowerZoneCategoryConfigs.values.toList();

  /// Get category config for a category
  LowerZoneCategoryConfig getCategoryConfig(LowerZoneCategory category) =>
      kLowerZoneCategoryConfigs[category]!;

  /// Get category for the active tab
  LowerZoneCategory? get activeTabCategory =>
      kLowerZoneTabConfigs[_activeTab]?.category;

  // ============ Actions ============

  /// Switch to a specific tab
  ///
  /// If the lower zone is collapsed, it will auto-expand.
  /// If switching to the same tab while expanded, it will collapse.
  void switchTo(LowerZoneTab tab) {
    if (_activeTab == tab && _isExpanded) {
      // Toggle collapse when clicking active tab
      _isExpanded = false;
    } else {
      _activeTab = tab;
      if (!_isExpanded) {
        _isExpanded = true;
      }
    }
    notifyListeners();
  }

  /// Set tab directly without toggle logic (for restore/sync purposes)
  ///
  /// Unlike [switchTo], this does NOT toggle collapse when clicking the active tab.
  /// Use this when syncing from external state.
  void setTab(LowerZoneTab tab) {
    if (_activeTab != tab) {
      _activeTab = tab;
      notifyListeners();
    }
  }

  /// Toggle expand/collapse state
  void toggle() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  /// Expand the lower zone (if collapsed)
  void expand() {
    if (!_isExpanded) {
      _isExpanded = true;
      notifyListeners();
    }
  }

  /// Collapse the lower zone (if expanded)
  void collapse() {
    if (_isExpanded) {
      _isExpanded = false;
      notifyListeners();
    }
  }

  /// Set the height of the content area
  ///
  /// Height is clamped to [kLowerZoneMinHeight, kLowerZoneMaxHeight].
  void setHeight(double newHeight) {
    final clamped = newHeight.clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);
    if (_height != clamped) {
      _height = clamped;
      notifyListeners();
    }
  }

  /// Adjust height by delta (for drag resize)
  void adjustHeight(double delta) {
    setHeight(_height + delta);
  }

  // ============ Category Actions (M3 Sprint - P1) ============

  /// Toggle collapse state for a category
  void toggleCategory(LowerZoneCategory category) {
    _categoryCollapsed[category] = !(_categoryCollapsed[category] ?? false);
    notifyListeners();
  }

  /// Set collapse state for a category
  void setCategoryCollapsed(LowerZoneCategory category, bool collapsed) {
    if (_categoryCollapsed[category] != collapsed) {
      _categoryCollapsed[category] = collapsed;
      notifyListeners();
    }
  }

  /// Expand all categories
  void expandAllCategories() {
    for (final category in LowerZoneCategory.values) {
      _categoryCollapsed[category] = false;
    }
    notifyListeners();
  }

  /// Collapse all categories
  void collapseAllCategories() {
    for (final category in LowerZoneCategory.values) {
      _categoryCollapsed[category] = true;
    }
    notifyListeners();
  }

  // ============ Keyboard Shortcuts ============

  /// Handle keyboard shortcuts for tab switching and toggle
  ///
  /// - `1-4`: Switch to tabs (without modifier)
  /// - `` ` ``: Toggle expand/collapse (without modifier)
  ///
  /// Returns [KeyEventResult.handled] if shortcut was processed.
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Don't handle if any modifier is pressed (let other handlers process)
    final hasModifier = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed;

    if (hasModifier) return KeyEventResult.ignored;

    // Backtick = Toggle lower zone
    if (event.logicalKey == LogicalKeyboardKey.backquote) {
      toggle();
      return KeyEventResult.handled;
    }

    // 1 = Timeline
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      switchTo(LowerZoneTab.timeline);
      return KeyEventResult.handled;
    }

    // 2 = Command Builder
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      switchTo(LowerZoneTab.commandBuilder);
      return KeyEventResult.handled;
    }

    // 3 = Event List
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      switchTo(LowerZoneTab.eventList);
      return KeyEventResult.handled;
    }

    // 4 = Meters
    if (event.logicalKey == LogicalKeyboardKey.digit4) {
      switchTo(LowerZoneTab.meters);
      return KeyEventResult.handled;
    }

    // 5 = Compressor
    if (event.logicalKey == LogicalKeyboardKey.digit5) {
      switchTo(LowerZoneTab.dspCompressor);
      return KeyEventResult.handled;
    }

    // 6 = Limiter
    if (event.logicalKey == LogicalKeyboardKey.digit6) {
      switchTo(LowerZoneTab.dspLimiter);
      return KeyEventResult.handled;
    }

    // 7 = Gate
    if (event.logicalKey == LogicalKeyboardKey.digit7) {
      switchTo(LowerZoneTab.dspGate);
      return KeyEventResult.handled;
    }

    // 8 = Reverb
    if (event.logicalKey == LogicalKeyboardKey.digit8) {
      switchTo(LowerZoneTab.dspReverb);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ============ Serialization ============

  /// Export state for persistence
  Map<String, dynamic> toJson() => {
        'activeTab': _activeTab.index,
        'isExpanded': _isExpanded,
        'height': _height,
        'categoryCollapsed': {
          for (final entry in _categoryCollapsed.entries)
            entry.key.name: entry.value,
        },
      };

  /// Import state from persistence
  void fromJson(Map<String, dynamic> json) {
    final tabIndex = json['activeTab'] as int?;
    if (tabIndex != null && tabIndex >= 0 && tabIndex < LowerZoneTab.values.length) {
      _activeTab = LowerZoneTab.values[tabIndex];
    }

    _isExpanded = json['isExpanded'] as bool? ?? true;
    _height = (json['height'] as num?)?.toDouble() ?? kLowerZoneDefaultHeight;
    _height = _height.clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);

    // Restore category collapse state
    final categoryJson = json['categoryCollapsed'] as Map<String, dynamic>?;
    if (categoryJson != null) {
      for (final category in LowerZoneCategory.values) {
        final collapsed = categoryJson[category.name] as bool?;
        if (collapsed != null) {
          _categoryCollapsed[category] = collapsed;
        }
      }
    }

    notifyListeners();
  }
}
