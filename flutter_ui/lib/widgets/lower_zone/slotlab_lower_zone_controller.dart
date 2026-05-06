// SlotLab Lower Zone Controller
//
// Manages state for SlotLab section's Lower Zone:
// - Super-tabs: STAGES, EVENTS, MIX, DSP, LOGIC, INTEL, MONITOR, BAKE
// - Sub-tabs: 4-8 per super-tab
// - Expand/collapse, resizable height
// - Keyboard shortcuts (1-8 for super, Q-I for sub, ` for toggle)

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../services/lower_zone_persistence_service.dart';
import 'lower_zone_types.dart';

/// Controller for SlotLab section's Lower Zone
class SlotLabLowerZoneController extends ChangeNotifier {
  SlotLabLowerZoneState _state;

  // Singleton pattern to preserve state across screen rebuilds
  static SlotLabLowerZoneController? _instance;
  static SlotLabLowerZoneController get instance {
    _instance ??= SlotLabLowerZoneController._();
    return _instance!;
  }

  SlotLabLowerZoneController._({SlotLabLowerZoneState? initialState})
      : _state = initialState ?? SlotLabLowerZoneState();

  // Keep legacy constructor for backward compatibility (delegates to singleton)
  factory SlotLabLowerZoneController({SlotLabLowerZoneState? initialState}) {
    return instance;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  SlotLabLowerZoneState get state => _state;
  SlotLabSuperTab get superTab => _state.superTab;
  bool get isExpanded => _state.isExpanded;
  double get height => _state.height;
  int get currentSubTabIndex => _state.currentSubTabIndex;
  List<String> get subTabLabels => _state.subTabLabels;
  List<String> get subTabTooltips => _state.subTabTooltips;

  /// Total height including all fixed-height elements
  /// When expanded: content + context bar (60px) + action strip + resize handle + spin control bar
  /// When collapsed: resize handle + context bar (32px, includes 1px bottom border)
  double get totalHeight => _state.isExpanded
      ? _state.height + kContextBarHeight + kActionStripHeight + kResizeHandleHeight + kSpinControlBarHeight
      : kResizeHandleHeight + kContextBarCollapsedHeight;

  Color get accentColor => _state.superTab.color;

  /// Sub-tab group break indices for current super-tab.
  /// Inserts visual separators between logical groups of sub-tabs.
  List<int>? get subTabGroupBreaks => switch (_state.superTab) {
    SlotLabSuperTab.stages    => null, // 5 tabs — no grouping needed
    SlotLabSuperTab.events    => const [2, 4],    // Folder+Editor+Layers | Pool+Auto | Templates+DepGraph
    SlotLabSuperTab.mix       => const [1, 4],     // Voices | Buses+Sends+Pan | Meter+Hierarchy+Ducking
    SlotLabSuperTab.dsp       => const [5, 8],    // Chain+EQ+Comp+Rev+Gate+Lim | Atten+Sigs+DSPProf | LayerDSP+Morph+Spatial
    SlotLabSuperTab.rtpc      => null, // 4 tabs — no grouping needed
    SlotLabSuperTab.containers=> const [4, 6],    // Blend+Random+Seq+A/B+Xfade | Groups+Presets | Metrics+Timeline+Wizard
    SlotLabSuperTab.music     => null, // 5 tabs — no grouping needed
    SlotLabSuperTab.logic     => const [4, 7],    // Behavior+Triggers+Gate+Priority+Orch | Emotional+Context+Sim | PriPreset+StateMachine+StateHist
    SlotLabSuperTab.intel     => const [3],       // Build+Flow+Sim+Diag | Templates+Export+Coverage+Inspector
    // SPEC-08 — MONITOR 20→5 grupa. Source-of-truth je `SlotLabMonitorGroup`
    // enum; ovaj getter samo prosledjuje da single-place edit drži oba u sync.
    SlotLabSuperTab.monitor   => SlotLabMonitorGroup.separatorIndices(),
    SlotLabSuperTab.bake      => const [3, 6],    // Export+Stems+Variations+Package | Git+Analytics+Docs | Macro+...
  };

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

  /// Restore super-tab WITHOUT changing expand state (for persistence restore)
  void restoreSuperTab(SlotLabSuperTab tab) {
    _updateAndSave(_state.copyWith(superTab: tab));
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

  void setLogicSubTab(SlotLabLogicSubTab tab) {
    var newState = _state.copyWith(logicSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.logic) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.logic);
    }
    _updateAndSave(newState);
  }

  void setIntelSubTab(SlotLabIntelSubTab tab) {
    var newState = _state.copyWith(intelSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.intel) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.intel);
    }
    _updateAndSave(newState);
  }

  void setMonitorSubTab(SlotLabMonitorSubTab tab) {
    var newState = _state.copyWith(monitorSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.monitor) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.monitor);
    }
    _updateAndSave(newState);
  }

  void setRtpcSubTab(SlotLabRtpcSubTab tab) {
    var newState = _state.copyWith(rtpcSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.rtpc) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.rtpc);
    }
    _updateAndSave(newState);
  }

  void setContainersSubTab(SlotLabContainersSubTab tab) {
    var newState = _state.copyWith(containersSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.containers) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.containers);
    }
    _updateAndSave(newState);
  }

  void setMusicSubTab(SlotLabMusicSubTab tab) {
    var newState = _state.copyWith(musicSubTab: tab);
    if (_state.superTab != SlotLabSuperTab.music) {
      newState = newState.copyWith(superTab: SlotLabSuperTab.music);
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

  /// Clamp content height so totalHeight doesn't exceed available space.
  /// Called by parent LayoutBuilder to prevent overflow on small screens.
  void clampHeight(double maxTotalHeight) {
    if (!_state.isExpanded) return;
    final overhead = kContextBarHeight + kActionStripHeight + kResizeHandleHeight + kSpinControlBarHeight;
    final maxContent = (maxTotalHeight - overhead).clamp(kLowerZoneMinHeight, kLowerZoneMaxHeight);
    if (_state.height > maxContent) {
      _state = _state.copyWith(height: maxContent);
      // Silent update — no notifyListeners to avoid rebuild loop
    }
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

    // 1-9, 0 = Super-tabs (by enum order)
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      setSuperTabIndex(0); // STAGES
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      setSuperTabIndex(1); // EVENTS
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      setSuperTabIndex(2); // MIX
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit4) {
      setSuperTabIndex(3); // DSP
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit5) {
      setSuperTabIndex(4); // RTPC
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit6) {
      setSuperTabIndex(5); // CONTAINERS
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit7) {
      setSuperTabIndex(6); // MUSIC
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit8) {
      setSuperTabIndex(7); // LOGIC
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit9) {
      setSuperTabIndex(8); // INTEL
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit0) {
      setSuperTabIndex(9); // MONITOR
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
  /// Returns true if state was loaded from storage, false if using defaults
  Future<bool> loadFromStorage() async {
    _state = await LowerZonePersistenceService.instance.loadSlotLabState();
    // Always start on first tab (STAGES) — fresh state on each launch
    if (_state.superTab != SlotLabSuperTab.stages) {
      _state = _state.copyWith(superTab: SlotLabSuperTab.stages);
    }
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
