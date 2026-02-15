// Lower Zone Controller — SlotLab Collapsible Bottom Panel
//
// Manages the state of SlotLab's lower zone:
// - Super-tab switching (STAGES, EVENTS, MIX, MUSIC, DSP, BAKE, ENGINE)
// - Sub-tab navigation within each super-tab
// - Expand/collapse animation
// - Resizable height (100-500px)
// - Keyboard shortcuts (Ctrl+Shift+T/E/X/A/G for super-tabs, 1-9 for sub-tabs)
//
// Updated 2026-01-29: Super-tab restructure per MASTER_TODO.md SL-LZ-P0.2

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../widgets/slot_lab/lower_zone/lower_zone_types.dart';

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
  // DSP Panels
  dspCompressor,  // FF-C compressor
  dspLimiter,     // FF-L limiter
  dspGate,        // FF-G gate
  dspReverb,      // FF-R reverb
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
  // DSP Panels
  LowerZoneTab.dspCompressor: LowerZoneTabConfig(
    tab: LowerZoneTab.dspCompressor,
    label: 'FF-C',
    icon: '🎚',
    shortcutKey: '5',
    description: 'FF-C Compressor',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.dspLimiter: LowerZoneTabConfig(
    tab: LowerZoneTab.dspLimiter,
    label: 'FF-L',
    icon: '🔊',
    shortcutKey: '6',
    description: 'FF-L Limiter',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.dspGate: LowerZoneTabConfig(
    tab: LowerZoneTab.dspGate,
    label: 'FF-G',
    icon: '🚪',
    shortcutKey: '7',
    description: 'FF-G Gate',
    category: LowerZoneCategory.audio,
  ),
  LowerZoneTab.dspReverb: LowerZoneTabConfig(
    tab: LowerZoneTab.dspReverb,
    label: 'FF-R',
    icon: '🌊',
    shortcutKey: '8',
    description: 'FF-R Reverb',
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
/// Manages super-tab/sub-tab state, expand/collapse, resizable height.
/// Updated 2026-01-29 for super-tab architecture per SL-LZ-P0.2.
class LowerZoneController extends ChangeNotifier {
  // Legacy tab (for backward compatibility during migration)
  LowerZoneTab _activeTab;

  // NEW: Super-tab state
  SuperTab _activeSuperTab;
  final Map<SuperTab, int> _activeSubTabIndices;

  bool _isExpanded;
  double _height;

  /// Category collapse state (M3 Sprint - P1)
  final Map<LowerZoneCategory, bool> _categoryCollapsed = {
    LowerZoneCategory.audio: false,
    LowerZoneCategory.routing: false,
    LowerZoneCategory.debug: false,
    LowerZoneCategory.advanced: true, // Advanced collapsed by default
  };

  /// Selected menu panel (when [+] More menu item is chosen)
  String? _activeMenuPanel;

  LowerZoneController({
    LowerZoneTab initialTab = LowerZoneTab.timeline,
    SuperTab initialSuperTab = SuperTab.stages,
    bool initialExpanded = true,
    double initialHeight = kLowerZoneDefaultHeight,
  })  : _activeTab = initialTab,
        _activeSuperTab = initialSuperTab,
        _activeSubTabIndices = {
          for (final superTab in SuperTab.values) superTab: 0,
        },
        _isExpanded = initialExpanded,
        _height = initialHeight.clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);

  // ============ Getters ============

  /// Currently active legacy tab (for backward compatibility)
  LowerZoneTab get activeTab => _activeTab;

  /// Currently active super-tab
  SuperTab get activeSuperTab => _activeSuperTab;

  /// Index of active sub-tab within current super-tab
  int get activeSubTabIndex => _activeSubTabIndices[_activeSuperTab] ?? 0;

  /// Get active sub-tab index for a specific super-tab
  int getSubTabIndex(SuperTab superTab) => _activeSubTabIndices[superTab] ?? 0;

  /// Configuration for the active super-tab
  SuperTabConfig get activeSuperTabConfig => getSuperTabConfig(_activeSuperTab);

  /// Sub-tabs for the active super-tab
  List<SubTabConfig> get activeSubTabs => getSubTabsForSuperTab(_activeSuperTab);

  /// Active menu panel ID (when menu item is selected)
  String? get activeMenuPanel => _activeMenuPanel;

  /// Whether the lower zone content is visible
  bool get isExpanded => _isExpanded;

  /// Current height of the content area (excludes header)
  double get height => _height;

  /// Total height including header (super-tabs + sub-tabs when expanded)
  double get totalHeight {
    if (!_isExpanded) {
      return kLowerZoneHeaderHeight; // Just super-tab row
    }
    // Super-tab row (32) + Sub-tab row (28) + content
    return _height + kLowerZoneHeaderHeight + 28;
  }

  /// Configuration for the active legacy tab
  LowerZoneTabConfig get activeTabConfig => kLowerZoneTabConfigs[_activeTab]!;

  /// All available legacy tab configurations
  List<LowerZoneTabConfig> get tabs => kLowerZoneTabConfigs.values.toList();

  /// Whether a specific legacy tab is active
  bool isTabActive(LowerZoneTab tab) => _activeTab == tab;

  /// Whether a specific super-tab is active
  bool isSuperTabActive(SuperTab superTab) => _activeSuperTab == superTab;

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

  /// Switch to a specific legacy tab
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

  /// Set legacy tab directly without toggle logic (for restore/sync purposes)
  ///
  /// Unlike [switchTo], this does NOT toggle collapse when clicking the active tab.
  /// Use this when syncing from external state.
  void setTab(LowerZoneTab tab) {
    if (_activeTab != tab) {
      _activeTab = tab;
      notifyListeners();
    }
  }

  // ============ Super-Tab Actions ============

  /// Switch to a specific super-tab
  ///
  /// If the lower zone is collapsed, it will auto-expand.
  /// If switching to the same super-tab while expanded, it will collapse.
  void switchToSuperTab(SuperTab superTab) {
    // Clear menu panel when switching super-tabs
    _activeMenuPanel = null;

    if (_activeSuperTab == superTab && _isExpanded) {
      // Toggle collapse when clicking active super-tab
      _isExpanded = false;
    } else {
      _activeSuperTab = superTab;
      if (!_isExpanded) {
        _isExpanded = true;
      }
    }
    notifyListeners();
  }

  /// Set super-tab directly without toggle logic (for restore/sync purposes)
  void setSuperTab(SuperTab superTab) {
    if (_activeSuperTab != superTab) {
      _activeSuperTab = superTab;
      _activeMenuPanel = null;
      notifyListeners();
    }
  }

  /// Switch to a specific sub-tab within the current super-tab
  void switchToSubTab(int index) {
    final subTabs = getSubTabsForSuperTab(_activeSuperTab);
    if (index >= 0 && index < subTabs.length) {
      _activeSubTabIndices[_activeSuperTab] = index;
      if (!_isExpanded) {
        _isExpanded = true;
      }
      notifyListeners();
    }
  }

  /// Set sub-tab index for a specific super-tab
  void setSubTabIndex(SuperTab superTab, int index) {
    final subTabs = getSubTabsForSuperTab(superTab);
    if (index >= 0 && index < subTabs.length) {
      _activeSubTabIndices[superTab] = index;
      notifyListeners();
    }
  }

  /// Handle menu item selection from [+] More menu
  void selectMenuItem(String menuItemId) {
    _activeMenuPanel = menuItemId;
    _activeSuperTab = SuperTab.menu;
    if (!_isExpanded) {
      _isExpanded = true;
    }
    notifyListeners();
  }

  /// Clear the active menu panel (return to normal tab view)
  void clearMenuPanel() {
    if (_activeMenuPanel != null) {
      _activeMenuPanel = null;
      // Switch to a default super-tab
      _activeSuperTab = SuperTab.stages;
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
  /// Super-tabs (with Ctrl+Shift or Cmd+Shift):
  /// - Ctrl+Shift+T: STAGES
  /// - Ctrl+Shift+E: EVENTS
  /// - Ctrl+Shift+X: MIX
  /// - Ctrl+Shift+A: MUSIC/ALE
  /// - Ctrl+Shift+G: ENGINE
  ///
  /// Sub-tabs (without modifier):
  /// - 1-9: Switch to sub-tab within current super-tab
  /// - `: Toggle expand/collapse
  ///
  /// Returns [KeyEventResult.handled] if shortcut was processed.
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Check for super-tab shortcuts (Ctrl+Shift or Cmd+Shift)
    final superTab = getSuperTabForShortcut(
      event.logicalKey,
      isCtrl,
      isShift,
      isAlt,
      isMeta,
    );
    if (superTab != null) {
      switchToSuperTab(superTab);
      return KeyEventResult.handled;
    }

    // Don't process sub-tab shortcuts if any modifier is pressed
    final hasModifier = isMeta || isCtrl || isAlt || isShift;
    if (hasModifier) return KeyEventResult.ignored;

    // Backtick = Toggle lower zone
    if (event.logicalKey == LogicalKeyboardKey.backquote) {
      toggle();
      return KeyEventResult.handled;
    }

    // 1-9 = Switch to sub-tab (within current super-tab)
    final subTabIndex = getSubTabIndexForShortcut(event.logicalKey);
    if (subTabIndex != null) {
      final subTabs = getSubTabsForSuperTab(_activeSuperTab);
      if (subTabIndex < subTabs.length) {
        switchToSubTab(subTabIndex);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Handle keyboard shortcuts for legacy tabs (backward compatibility)
  ///
  /// - `1-8`: Switch to legacy tabs (without modifier)
  /// - `` ` ``: Toggle expand/collapse (without modifier)
  ///
  /// @deprecated Use handleKeyEvent instead for super-tab navigation
  KeyEventResult handleLegacyKeyEvent(KeyEvent event) {
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
        // Legacy tab (for backward compatibility)
        'activeTab': _activeTab.index,

        // New super-tab state
        'activeSuperTab': _activeSuperTab.index,
        'activeSubTabIndices': {
          for (final entry in _activeSubTabIndices.entries)
            entry.key.name: entry.value,
        },
        'activeMenuPanel': _activeMenuPanel,

        // Common state
        'isExpanded': _isExpanded,
        'height': _height,
        'categoryCollapsed': {
          for (final entry in _categoryCollapsed.entries)
            entry.key.name: entry.value,
        },
      };

  /// Import state from persistence
  void fromJson(Map<String, dynamic> json) {
    // Restore legacy tab (for backward compatibility)
    final tabIndex = json['activeTab'] as int?;
    if (tabIndex != null && tabIndex >= 0 && tabIndex < LowerZoneTab.values.length) {
      _activeTab = LowerZoneTab.values[tabIndex];
    }

    // Restore super-tab state
    final superTabIndex = json['activeSuperTab'] as int?;
    if (superTabIndex != null && superTabIndex >= 0 && superTabIndex < SuperTab.values.length) {
      _activeSuperTab = SuperTab.values[superTabIndex];
    }

    // Restore sub-tab indices
    final subTabJson = json['activeSubTabIndices'] as Map<String, dynamic>?;
    if (subTabJson != null) {
      for (final superTab in SuperTab.values) {
        final index = subTabJson[superTab.name] as int?;
        if (index != null) {
          final subTabs = getSubTabsForSuperTab(superTab);
          _activeSubTabIndices[superTab] = index.clamp(0, subTabs.length - 1);
        }
      }
    }

    // Restore menu panel
    _activeMenuPanel = json['activeMenuPanel'] as String?;

    // Restore common state
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
