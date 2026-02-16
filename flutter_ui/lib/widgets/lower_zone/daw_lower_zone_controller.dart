// DAW Lower Zone Controller
//
// Manages state for DAW section's Lower Zone:
// - Super-tabs: BROWSE, EDIT, MIX, PROCESS, DELIVER
// - Sub-tabs: 4 per super-tab
// - Expand/collapse, resizable height
// - Keyboard shortcuts (1-5 for super, Q-R for sub, ` for toggle)

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../services/lower_zone_persistence_service.dart';
import 'lower_zone_types.dart';

/// P1.5: Recent tab entry for quick access
class RecentTabEntry {
  final DawSuperTab superTab;
  final int subTabIndex;
  final String label;
  final IconData icon;

  const RecentTabEntry({
    required this.superTab,
    required this.subTabIndex,
    required this.label,
    required this.icon,
  });

  @override
  bool operator ==(Object other) =>
      other is RecentTabEntry &&
      other.superTab == superTab &&
      other.subTabIndex == subTabIndex;

  @override
  int get hashCode => Object.hash(superTab, subTabIndex);
}

/// Controller for DAW section's Lower Zone
class DawLowerZoneController extends ChangeNotifier {
  DawLowerZoneState _state;

  /// P1.5: Recent tabs list (max 5, most recent first)
  final List<RecentTabEntry> _recentTabs = [];

  // Singleton pattern to preserve state across screen rebuilds
  static DawLowerZoneController? _instance;
  static DawLowerZoneController get instance {
    _instance ??= DawLowerZoneController._();
    return _instance!;
  }

  DawLowerZoneController._({DawLowerZoneState? initialState})
      : _state = initialState ?? DawLowerZoneState();

  // Keep legacy constructor for backward compatibility (delegates to singleton)
  factory DawLowerZoneController({DawLowerZoneState? initialState}) {
    return instance;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  DawLowerZoneState get state => _state;
  DawSuperTab get superTab => _state.superTab;
  bool get isExpanded => _state.isExpanded;
  double get height => _state.height;
  int get currentSubTabIndex => _state.currentSubTabIndex;
  List<String> get subTabLabels => _state.subTabLabels;

  /// Total height including all fixed-height elements + 1px top border
  double get totalHeight => _state.isExpanded
      ? _state.height + kContextBarHeight + kActionStripHeight + kResizeHandleHeight + 1
      : kResizeHandleHeight + kContextBarCollapsedHeight + 1;

  Color get accentColor => LowerZoneColors.dawAccent;

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.1: SPLIT VIEW GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get splitEnabled => _state.splitEnabled;
  SplitDirection get splitDirection => _state.splitDirection;
  double get splitRatio => _state.splitRatio;
  bool get syncScrollEnabled => _state.syncScrollEnabled;

  DawSuperTab get secondPaneSuperTab => _state.secondPaneSuperTab;
  int get secondPaneCurrentSubTabIndex => _state.secondPaneCurrentSubTabIndex;
  List<String> get secondPaneSubTabLabels => _state.secondPaneSubTabLabels;

  /// P1.5: Get recent tabs (max 3 for display)
  List<RecentTabEntry> get recentTabs => _recentTabs.take(3).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.5: RECENT TABS TRACKING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record current tab state to recent tabs list
  void _recordRecentTab() {
    final subIndex = _state.currentSubTabIndex;
    final label = _getTabLabel(_state.superTab, subIndex);
    final icon = _getTabIcon(_state.superTab, subIndex);

    final entry = RecentTabEntry(
      superTab: _state.superTab,
      subTabIndex: subIndex,
      label: label,
      icon: icon,
    );

    // Remove if already exists (move to front)
    _recentTabs.remove(entry);
    // Add to front
    _recentTabs.insert(0, entry);
    // Keep max 5 recent
    if (_recentTabs.length > 5) {
      _recentTabs.removeLast();
    }
  }

  /// Get label for specific tab combination
  String _getTabLabel(DawSuperTab superTab, int subIndex) {
    switch (superTab) {
      case DawSuperTab.browse:
        return DawBrowseSubTab.values[subIndex].label;
      case DawSuperTab.edit:
        return DawEditSubTab.values[subIndex].label;
      case DawSuperTab.mix:
        return DawMixSubTab.values[subIndex].label;
      case DawSuperTab.process:
        return DawProcessSubTab.values[subIndex].label;
      case DawSuperTab.deliver:
        return DawDeliverSubTab.values[subIndex].label;
    }
  }

  /// Get icon for specific tab combination
  IconData _getTabIcon(DawSuperTab superTab, int subIndex) {
    switch (superTab) {
      case DawSuperTab.browse:
        return DawBrowseSubTab.values[subIndex].icon;
      case DawSuperTab.edit:
        return DawEditSubTab.values[subIndex].icon;
      case DawSuperTab.mix:
        return DawMixSubTab.values[subIndex].icon;
      case DawSuperTab.process:
        return DawProcessSubTab.values[subIndex].icon;
      case DawSuperTab.deliver:
        return DawDeliverSubTab.values[subIndex].icon;
    }
  }

  /// Navigate to a recent tab entry
  void goToRecentTab(RecentTabEntry entry) {
    if (_state.superTab != entry.superTab) {
      _state = _state.copyWith(superTab: entry.superTab, isExpanded: true);
    }
    _state.setSubTabIndex(entry.subTabIndex);
    if (!_state.isExpanded) {
      _state = _state.copyWith(isExpanded: true);
    }
    notifyListeners();
    saveToStorage();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUPER-TAB ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Switch to a specific super-tab
  void setSuperTab(DawSuperTab tab) {
    if (_state.superTab == tab && _state.isExpanded) {
      // Toggle collapse when clicking active tab
      _updateAndSave(_state.copyWith(isExpanded: false));
    } else {
      _updateAndSave(_state.copyWith(superTab: tab, isExpanded: true));
      _recordRecentTab(); // P1.5: Track recent tabs
    }
  }

  /// Switch super-tab by index (0-4)
  void setSuperTabIndex(int index) {
    if (index >= 0 && index < DawSuperTab.values.length) {
      setSuperTab(DawSuperTab.values[index]);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUB-TAB ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set sub-tab by index (0-3) for current super-tab
  void setSubTabIndex(int index) {
    _state.setSubTabIndex(index);
    final newState = _state.isExpanded ? _state : _state.copyWith(isExpanded: true);
    _updateAndSave(newState);
    _recordRecentTab(); // P1.5: Track recent tabs
  }

  /// Specific sub-tab setters for type safety
  void setBrowseSubTab(DawBrowseSubTab tab) {
    var newState = _state.copyWith(browseSubTab: tab);
    if (_state.superTab != DawSuperTab.browse) {
      newState = newState.copyWith(superTab: DawSuperTab.browse);
    }
    _updateAndSave(newState);
  }

  void setEditSubTab(DawEditSubTab tab) {
    var newState = _state.copyWith(editSubTab: tab);
    if (_state.superTab != DawSuperTab.edit) {
      newState = newState.copyWith(superTab: DawSuperTab.edit);
    }
    _updateAndSave(newState);
  }

  void setMixSubTab(DawMixSubTab tab) {
    var newState = _state.copyWith(mixSubTab: tab);
    if (_state.superTab != DawSuperTab.mix) {
      newState = newState.copyWith(superTab: DawSuperTab.mix);
    }
    _updateAndSave(newState);
  }

  void setProcessSubTab(DawProcessSubTab tab) {
    var newState = _state.copyWith(processSubTab: tab);
    if (_state.superTab != DawSuperTab.process) {
      newState = newState.copyWith(superTab: DawSuperTab.process);
    }
    _updateAndSave(newState);
  }

  void setDeliverSubTab(DawDeliverSubTab tab) {
    var newState = _state.copyWith(deliverSubTab: tab);
    if (_state.superTab != DawSuperTab.deliver) {
      newState = newState.copyWith(superTab: DawSuperTab.deliver);
    }
    _updateAndSave(newState);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPAND/COLLAPSE
  // ═══════════════════════════════════════════════════════════════════════════

  void toggle() {
    _updateAndSave(_state.copyWith(isExpanded: !_state.isExpanded));
  }

  void expand() {
    if (!_state.isExpanded) {
      _updateAndSave(_state.copyWith(isExpanded: true));
    }
  }

  void collapse() {
    if (_state.isExpanded) {
      _updateAndSave(_state.copyWith(isExpanded: false));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.1: SPLIT VIEW ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle split view mode on/off
  void toggleSplitView() {
    _updateAndSave(_state.copyWith(splitEnabled: !_state.splitEnabled));
  }

  /// Enable split view
  void enableSplitView() {
    if (!_state.splitEnabled) {
      _updateAndSave(_state.copyWith(splitEnabled: true, isExpanded: true));
    }
  }

  /// Disable split view
  void disableSplitView() {
    if (_state.splitEnabled) {
      _updateAndSave(_state.copyWith(splitEnabled: false));
    }
  }

  /// Set split direction (horizontal or vertical)
  void setSplitDirection(SplitDirection direction) {
    _updateAndSave(_state.copyWith(splitDirection: direction));
  }

  /// Toggle between horizontal and vertical split
  void toggleSplitDirection() {
    final newDirection = _state.splitDirection == SplitDirection.horizontal
        ? SplitDirection.vertical
        : SplitDirection.horizontal;
    _updateAndSave(_state.copyWith(splitDirection: newDirection));
  }

  /// Set split ratio (position of divider, 0.0-1.0)
  void setSplitRatio(double ratio) {
    final clamped = ratio.clamp(kSplitViewMinRatio, kSplitViewMaxRatio);
    if (_state.splitRatio != clamped) {
      _updateAndSave(_state.copyWith(splitRatio: clamped));
    }
  }

  /// Toggle sync scroll between panes
  void toggleSyncScroll() {
    _updateAndSave(_state.copyWith(syncScrollEnabled: !_state.syncScrollEnabled));
  }

  /// Set second pane's super-tab
  void setSecondPaneSuperTab(DawSuperTab tab) {
    _updateAndSave(_state.copyWith(secondPaneSuperTab: tab));
  }

  /// Set second pane's sub-tab by index
  void setSecondPaneSubTabIndex(int index) {
    _state.setSecondPaneSubTabIndex(index);
    _updateAndSave(_state);
  }

  /// Swap the content of both panes
  void swapPanes() {
    _updateAndSave(_state.copyWith(
      superTab: _state.secondPaneSuperTab,
      browseSubTab: _state.secondPaneBrowseSubTab,
      editSubTab: _state.secondPaneEditSubTab,
      mixSubTab: _state.secondPaneMixSubTab,
      processSubTab: _state.secondPaneProcessSubTab,
      deliverSubTab: _state.secondPaneDeliverSubTab,
      secondPaneSuperTab: _state.superTab,
      secondPaneBrowseSubTab: _state.browseSubTab,
      secondPaneEditSubTab: _state.editSubTab,
      secondPaneMixSubTab: _state.mixSubTab,
      secondPaneProcessSubTab: _state.processSubTab,
      secondPaneDeliverSubTab: _state.deliverSubTab,
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEIGHT
  // ═══════════════════════════════════════════════════════════════════════════

  void setHeight(double newHeight) {
    final clamped = newHeight.clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);
    if (_state.height != clamped) {
      _updateAndSave(_state.copyWith(height: clamped));
    }
  }

  void adjustHeight(double delta) {
    setHeight(_state.height + delta);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KEYBOARD SHORTCUTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handle keyboard shortcuts
  /// Returns KeyEventResult.handled if shortcut was processed
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Don't handle if modifier is pressed
    final hasModifier = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed;

    if (hasModifier) return KeyEventResult.ignored;

    // ` = Toggle
    if (event.logicalKey == LogicalKeyboardKey.backquote) {
      toggle();
      return KeyEventResult.handled;
    }

    // 1-5 = Super-tabs
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      setSuperTab(DawSuperTab.browse);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      setSuperTab(DawSuperTab.edit);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      setSuperTab(DawSuperTab.mix);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit4) {
      setSuperTab(DawSuperTab.process);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit5) {
      setSuperTab(DawSuperTab.deliver);
      return KeyEventResult.handled;
    }

    // Q, W, E, R = Sub-tabs
    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      setSubTabIndex(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      setSubTabIndex(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      setSubTabIndex(2);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      setSubTabIndex(3);
      return KeyEventResult.handled;
    }

    // P2.1: Split view shortcuts (require Shift modifier)
    return KeyEventResult.ignored;
  }

  /// Handle keyboard shortcuts with modifiers (e.g., Shift+S for split)
  KeyEventResult handleKeyEventWithModifiers(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Shift+S = Toggle split view
    if (HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyS) {
        toggleSplitView();
        return KeyEventResult.handled;
      }
      // Shift+D = Toggle split direction
      if (event.logicalKey == LogicalKeyboardKey.keyD && _state.splitEnabled) {
        toggleSplitDirection();
        return KeyEventResult.handled;
      }
      // Shift+X = Swap panes
      if (event.logicalKey == LogicalKeyboardKey.keyX && _state.splitEnabled) {
        swapPanes();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => _state.toJson();

  void fromJson(Map<String, dynamic> json) {
    _state = DawLowerZoneState.fromJson(json);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load state from persistent storage
  /// Returns true if state was loaded from storage, false if using defaults
  Future<bool> loadFromStorage() async {
    _state = await LowerZonePersistenceService.instance.loadDawState();
    // Always start with split view disabled — it's an explicit user action
    if (_state.splitEnabled) {
      _state = _state.copyWith(splitEnabled: false);
    }
    // Always start on BROWSE tab — EDIT tab panels can render blank on cold start
    // before track/DSP state is initialized. User navigates to EDIT explicitly.
    if (_state.superTab == DawSuperTab.edit) {
      _state = _state.copyWith(superTab: DawSuperTab.browse);
    }
    notifyListeners();
    // If height is still default, it means no persisted state was found
    return _state.height != kLowerZoneDefaultHeight;
  }

  /// Set height to half of the available screen height
  /// Call this after loadFromStorage() returns false (no persisted state)
  void setHeightToHalfScreen(double availableHeight) {
    // Calculate half screen minus fixed elements (context bar, action strip, resize handle)
    // Available height is the area where Lower Zone can expand
    final halfScreen = (availableHeight * 0.5).clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);
    if (_state.height != halfScreen) {
      _updateAndSave(_state.copyWith(height: halfScreen));
    }
  }

  /// Save current state to persistent storage
  Future<void> saveToStorage() async {
    await LowerZonePersistenceService.instance.saveDawState(_state);
  }

  /// Update state and auto-save
  void _updateAndSave(DawLowerZoneState newState) {
    _state = newState;
    notifyListeners();
    // Save asynchronously without blocking
    saveToStorage();
  }
}
