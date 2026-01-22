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

/// Controller for DAW section's Lower Zone
class DawLowerZoneController extends ChangeNotifier {
  DawLowerZoneState _state;

  DawLowerZoneController({DawLowerZoneState? initialState})
      : _state = initialState ?? DawLowerZoneState();

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  DawLowerZoneState get state => _state;
  DawSuperTab get superTab => _state.superTab;
  bool get isExpanded => _state.isExpanded;
  double get height => _state.height;
  int get currentSubTabIndex => _state.currentSubTabIndex;
  List<String> get subTabLabels => _state.subTabLabels;

  double get totalHeight => _state.isExpanded
      ? _state.height + kContextBarHeight + kActionStripHeight
      : kContextBarHeight;

  Color get accentColor => LowerZoneColors.dawAccent;

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
  Future<void> loadFromStorage() async {
    _state = await LowerZonePersistenceService.instance.loadDawState();
    notifyListeners();
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
