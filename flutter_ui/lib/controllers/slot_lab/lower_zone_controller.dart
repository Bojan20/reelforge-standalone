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

/// Available tabs in the SlotLab lower zone
enum LowerZoneTab {
  timeline,       // Stage trace timeline
  commandBuilder, // Auto Event Builder command panel
  eventList,      // Event list browser
  meters,         // Audio bus meters
}

/// Configuration for each lower zone tab
class LowerZoneTabConfig {
  final LowerZoneTab tab;
  final String label;
  final String icon;
  final String shortcutKey;
  final String description;

  const LowerZoneTabConfig({
    required this.tab,
    required this.label,
    required this.icon,
    required this.shortcutKey,
    required this.description,
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
  ),
  LowerZoneTab.commandBuilder: LowerZoneTabConfig(
    tab: LowerZoneTab.commandBuilder,
    label: 'Command',
    icon: '🔧',
    shortcutKey: '2',
    description: 'Auto Event Builder',
  ),
  LowerZoneTab.eventList: LowerZoneTabConfig(
    tab: LowerZoneTab.eventList,
    label: 'Events',
    icon: '📋',
    shortcutKey: '3',
    description: 'Event list browser',
  ),
  LowerZoneTab.meters: LowerZoneTabConfig(
    tab: LowerZoneTab.meters,
    label: 'Meters',
    icon: '📊',
    shortcutKey: '4',
    description: 'Audio bus meters',
  ),
};

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
/// Manages tab state, expand/collapse, and resizable height.
/// Follows the same pattern as EditorModeProvider.
class LowerZoneController extends ChangeNotifier {
  LowerZoneTab _activeTab;
  bool _isExpanded;
  double _height;

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

    return KeyEventResult.ignored;
  }

  // ============ Serialization ============

  /// Export state for persistence
  Map<String, dynamic> toJson() => {
        'activeTab': _activeTab.index,
        'isExpanded': _isExpanded,
        'height': _height,
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

    notifyListeners();
  }
}
