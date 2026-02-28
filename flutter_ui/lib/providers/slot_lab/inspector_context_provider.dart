/// Inspector Context Provider — SlotLab Middleware §20
///
/// Context-sensitive inspector panel state for behavior nodes.
/// When a behavior node is selected, the inspector shows its parameters
/// organized by disclosure tier (Basic/Advanced/Expert).
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §20

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';

/// Inspector tab for behavior node
enum InspectorTab {
  /// Basic parameters (gain, priority, bus, layer group)
  parameters,
  /// Sound assignments (primary, variants, fallback)
  sounds,
  /// Context overrides per game mode
  context,
  /// Ducking assignments for this node
  ducking,
  /// Coverage and trigger history
  coverage,
}

extension InspectorTabExtension on InspectorTab {
  String get displayName {
    switch (this) {
      case InspectorTab.parameters: return 'Parameters';
      case InspectorTab.sounds: return 'Sounds';
      case InspectorTab.context: return 'Context';
      case InspectorTab.ducking: return 'Ducking';
      case InspectorTab.coverage: return 'Coverage';
    }
  }

  int get iconCodePoint {
    switch (this) {
      case InspectorTab.parameters: return 0xe8b8; // tune
      case InspectorTab.sounds: return 0xe3a1; // music_note
      case InspectorTab.context: return 0xe574; // account_tree
      case InspectorTab.ducking: return 0xe050; // volume_down
      case InspectorTab.coverage: return 0xe876; // check_circle
    }
  }
}

class InspectorContextProvider extends ChangeNotifier {
  /// Currently selected behavior node ID
  String? _selectedNodeId;

  /// Currently selected behavior node data (cached)
  BehaviorNode? _selectedNode;

  /// Active inspector tab
  InspectorTab _activeTab = InspectorTab.parameters;

  /// Whether inspector is pinned (doesn't auto-change on selection)
  bool _pinned = false;

  /// Parameter search filter
  String _parameterFilter = '';

  /// Whether to show inherited values (from parent/defaults)
  bool _showInherited = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  String? get selectedNodeId => _selectedNodeId;
  BehaviorNode? get selectedNode => _selectedNode;
  InspectorTab get activeTab => _activeTab;
  bool get pinned => _pinned;
  String get parameterFilter => _parameterFilter;
  bool get showInherited => _showInherited;
  bool get hasSelection => _selectedNodeId != null;

  // ═══════════════════════════════════════════════════════════════════════════
  // SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select a behavior node for inspection
  void selectNode(String nodeId, BehaviorNode node) {
    if (_pinned && _selectedNodeId != null) return;
    _selectedNodeId = nodeId;
    _selectedNode = node;
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    if (_pinned) return;
    _selectedNodeId = null;
    _selectedNode = null;
    notifyListeners();
  }

  /// Force select (ignores pin)
  void forceSelect(String nodeId, BehaviorNode node) {
    _selectedNodeId = nodeId;
    _selectedNode = node;
    _pinned = false;
    notifyListeners();
  }

  /// Update cached node data (when node params change)
  void updateNodeData(BehaviorNode node) {
    if (_selectedNodeId == node.id) {
      _selectedNode = node;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void setActiveTab(InspectorTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void togglePinned() {
    _pinned = !_pinned;
    notifyListeners();
  }

  void setPinned(bool value) {
    if (_pinned == value) return;
    _pinned = value;
    notifyListeners();
  }

  void setParameterFilter(String filter) {
    _parameterFilter = filter;
    notifyListeners();
  }

  void setShowInherited(bool value) {
    if (_showInherited == value) return;
    _showInherited = value;
    notifyListeners();
  }
}
