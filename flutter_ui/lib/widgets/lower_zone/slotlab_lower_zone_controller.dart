// SlotLab Lower Zone Controller
//
// Manages state for SlotLab section's Lower Zone:
// - Super-tabs: STAGES, EVENTS, MIX, DSP, BAKE
// - Sub-tabs: 4 per super-tab
// - Expand/collapse, resizable height
// - Keyboard shortcuts (1-5 for super, Q-R for sub, ` for toggle)

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../services/lower_zone_persistence_service.dart';
import 'lower_zone_types.dart';

/// Controller for SlotLab section's Lower Zone
class SlotLabLowerZoneController extends ChangeNotifier {
  SlotLabLowerZoneState _state;

  SlotLabLowerZoneController({SlotLabLowerZoneState? initialState})
      : _state = initialState ?? SlotLabLowerZoneState();

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  SlotLabLowerZoneState get state => _state;
  SlotLabSuperTab get superTab => _state.superTab;
  bool get isExpanded => _state.isExpanded;
  double get height => _state.height;
  int get currentSubTabIndex => _state.currentSubTabIndex;
  List<String> get subTabLabels => _state.subTabLabels;

  /// Total height including all fixed-height elements
  /// When expanded: content + context bar (60px) + action strip + resize handle + spin control bar + 1px border
  /// When collapsed: just resize handle + super-tabs row (32px, no sub-tabs) + 1px border
  /// NOTE: The +1.0 accounts for the top border (BorderSide width: 1) to prevent 1px overflow
  // Border is now rendered via Positioned in Stack, doesn't affect layout height
  double get totalHeight => _state.isExpanded
      ? _state.height + kContextBarHeight + kActionStripHeight + kResizeHandleHeight + kSpinControlBarHeight
      : kResizeHandleHeight + kContextBarCollapsedHeight;

  Color get accentColor => LowerZoneColors.slotLabAccent;

  // ═══════════════════════════════════════════════════════════════════════════
  // SUPER-TAB ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void setSuperTab(SlotLabSuperTab tab) {
    if (_state.superTab == tab && _state.isExpanded) {
      _updateAndSave(_state.copyWith(isExpanded: false));
    } else {
      _updateAndSave(_state.copyWith(superTab: tab, isExpanded: true));
    }
  }

  void setSuperTabIndex(int index) {
    if (index >= 0 && index < SlotLabSuperTab.values.length) {
      setSuperTab(SlotLabSuperTab.values[index]);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUB-TAB ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void setSubTabIndex(int index) {
    _state.setSubTabIndex(index);
    final newState = _state.isExpanded ? _state : _state.copyWith(isExpanded: true);
    _updateAndSave(newState);
  }

  void setStagesSubTab(SlotLabStagesSubTab tab) {
    var newState = _state.copyWith(stagesSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.stages) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.stages);
    }
    _updateAndSave(newState);
  }

  void setEventsSubTab(SlotLabEventsSubTab tab) {
    var newState = _state.copyWith(eventsSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.events) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.events);
    }
    _updateAndSave(newState);
  }

  void setMixSubTab(SlotLabMixSubTab tab) {
    var newState = _state.copyWith(mixSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.mix) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.mix);
    }
    _updateAndSave(newState);
  }

  void setDspSubTab(SlotLabDspSubTab tab) {
    var newState = _state.copyWith(dspSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.dsp) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.dsp);
    }
    _updateAndSave(newState);
  }

  void setBakeSubTab(SlotLabBakeSubTab tab) {
    var newState = _state.copyWith(bakeSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.bake) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.bake);
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

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

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
      setSuperTab(SlotLabSuperTab.stages);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      setSuperTab(SlotLabSuperTab.events);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      setSuperTab(SlotLabSuperTab.mix);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit4) {
      setSuperTab(SlotLabSuperTab.dsp);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit5) {
      setSuperTab(SlotLabSuperTab.bake);
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
    _state = SlotLabLowerZoneState.fromJson(json);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load state from persistent storage
  Future<void> loadFromStorage() async {
    _state = await LowerZonePersistenceService.instance.loadSlotLabState();
    notifyListeners();
  }

  /// Save current state to persistent storage
  Future<void> saveToStorage() async {
    await LowerZonePersistenceService.instance.saveSlotLabState(_state);
  }

  /// Update state and auto-save
  void _updateAndSave(SlotLabLowerZoneState newState) {
    _state = newState;
    notifyListeners();
    // Save asynchronously without blocking
    saveToStorage();
  }
}
