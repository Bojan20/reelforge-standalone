// Middleware Lower Zone Controller
//
// Manages state for Middleware section's Lower Zone:
// - Super-tabs: EVENTS, CONTAINERS, ROUTING, RTPC, DELIVER
// - Sub-tabs: 4 per super-tab
// - Expand/collapse, resizable height
// - Keyboard shortcuts (1-5 for super, Q-R for sub, ` for toggle)

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../services/lower_zone_persistence_service.dart';
import 'lower_zone_types.dart';

/// Controller for Middleware section's Lower Zone
class MiddlewareLowerZoneController extends ChangeNotifier {
  MiddlewareLowerZoneState _state;

  // Singleton pattern to preserve state across screen rebuilds
  static MiddlewareLowerZoneController? _instance;
  static MiddlewareLowerZoneController get instance {
    _instance ??= MiddlewareLowerZoneController._();
    return _instance!;
  }

  MiddlewareLowerZoneController._({MiddlewareLowerZoneState? initialState})
      : _state = initialState ?? MiddlewareLowerZoneState();

  // Keep legacy constructor for backward compatibility (delegates to singleton)
  factory MiddlewareLowerZoneController({MiddlewareLowerZoneState? initialState}) {
    return instance;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  MiddlewareLowerZoneState get state => _state;
  MiddlewareSuperTab get superTab => _state.superTab;
  bool get isExpanded => _state.isExpanded;
  double get height => _state.height;
  int get currentSubTabIndex => _state.currentSubTabIndex;
  List<String> get subTabLabels => _state.subTabLabels;

  /// Total height including all fixed-height elements
  /// When expanded: resize handle + context bar + slot context bar + content + action strip + 1px top border
  /// When collapsed: resize handle + collapsed context bar + 1px top border
  double get totalHeight => _state.isExpanded
      ? _state.height + kContextBarHeight + kSlotContextBarHeight + kActionStripHeight + kResizeHandleHeight + 1
      : kResizeHandleHeight + kContextBarCollapsedHeight + 1;

  Color get accentColor => LowerZoneColors.middlewareAccent;

  // ═══════════════════════════════════════════════════════════════════════════
  // SUPER-TAB ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void setSuperTab(MiddlewareSuperTab tab) {
    if (_state.superTab == tab && _state.isExpanded) {
      _updateAndSave(_state.copyWith(isExpanded: false));
    } else {
      _updateAndSave(_state.copyWith(superTab: tab, isExpanded: true));
    }
  }

  void setSuperTabIndex(int index) {
    if (index >= 0 && index < MiddlewareSuperTab.values.length) {
      setSuperTab(MiddlewareSuperTab.values[index]);
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

  void setEventsSubTab(MiddlewareEventsSubTab tab) {
    var newState = _state.copyWith(eventsSubTab: tab);
    if (_state.superTab != MiddlewareSuperTab.events) {
      newState = newState.copyWith(superTab: MiddlewareSuperTab.events);
    }
    _updateAndSave(newState);
  }

  void setContainersSubTab(MiddlewareContainersSubTab tab) {
    var newState = _state.copyWith(containersSubTab: tab);
    if (_state.superTab != MiddlewareSuperTab.containers) {
      newState = newState.copyWith(superTab: MiddlewareSuperTab.containers);
    }
    _updateAndSave(newState);
  }

  void setRoutingSubTab(MiddlewareRoutingSubTab tab) {
    var newState = _state.copyWith(routingSubTab: tab);
    if (_state.superTab != MiddlewareSuperTab.routing) {
      newState = newState.copyWith(superTab: MiddlewareSuperTab.routing);
    }
    _updateAndSave(newState);
  }

  void setRtpcSubTab(MiddlewareRtpcSubTab tab) {
    var newState = _state.copyWith(rtpcSubTab: tab);
    if (_state.superTab != MiddlewareSuperTab.rtpc) {
      newState = newState.copyWith(superTab: MiddlewareSuperTab.rtpc);
    }
    _updateAndSave(newState);
  }

  void setDeliverSubTab(MiddlewareDeliverSubTab tab) {
    var newState = _state.copyWith(deliverSubTab: tab);
    if (_state.superTab != MiddlewareSuperTab.deliver) {
      newState = newState.copyWith(superTab: MiddlewareSuperTab.deliver);
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
      setSuperTab(MiddlewareSuperTab.events);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      setSuperTab(MiddlewareSuperTab.containers);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      setSuperTab(MiddlewareSuperTab.routing);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit4) {
      setSuperTab(MiddlewareSuperTab.rtpc);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit5) {
      setSuperTab(MiddlewareSuperTab.deliver);
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
    _state = MiddlewareLowerZoneState.fromJson(json);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load state from persistent storage
  /// Returns true if state was loaded from storage, false if using defaults
  Future<bool> loadFromStorage() async {
    _state = await LowerZonePersistenceService.instance.loadMiddlewareState();
    notifyListeners();
    // If height is still default, it means no persisted state was found
    return _state.height != kLowerZoneDefaultHeight;
  }

  /// Set height to half of the available screen height
  /// Call this after loadFromStorage() returns false (no persisted state)
  void setHeightToHalfScreen(double availableHeight) {
    // Calculate half screen minus fixed elements
    final halfScreen = (availableHeight * 0.5).clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);
    if (_state.height != halfScreen) {
      _updateAndSave(_state.copyWith(height: halfScreen));
    }
  }

  /// Save current state to persistent storage
  Future<void> saveToStorage() async {
    await LowerZonePersistenceService.instance.saveMiddlewareState(_state);
  }

  /// Update state and auto-save
  void _updateAndSave(MiddlewareLowerZoneState newState) {
    _state = newState;
    notifyListeners();
    // Save asynchronously without blocking
    saveToStorage();
  }
}
