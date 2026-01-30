/// Focus Management Service
///
/// Centralized focus state management for SlotLab:
/// - Focus node registration and tracking
/// - Focus history for back navigation
/// - Focus restoration after dialogs
/// - Focus scope management
/// - Tab order control
///
/// Created: 2026-01-30 (P4.23)

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FOCUS SCOPE TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Focus scope identifiers
enum FocusScopeId {
  /// Main application scope
  main,

  /// Dialog overlay scope
  dialog,

  /// Dropdown/popup scope
  popup,

  /// Context menu scope
  contextMenu,

  /// Lower zone tabs
  lowerZone,

  /// Events panel
  eventsPanel,

  /// Audio browser
  audioBrowser,

  /// Mixer
  mixer,

  /// Timeline
  timeline,
}

// ═══════════════════════════════════════════════════════════════════════════
// FOCUS NODE INFO
// ═══════════════════════════════════════════════════════════════════════════

/// Information about a registered focus node
class FocusNodeInfo {
  final String id;
  final String label;
  final FocusScopeId scope;
  final int tabOrder;
  final FocusNode node;
  final DateTime registeredAt;

  FocusNodeInfo({
    required this.id,
    required this.label,
    required this.scope,
    required this.tabOrder,
    required this.node,
  }) : registeredAt = DateTime.now();

  bool get hasFocus => node.hasFocus;
  bool get canRequestFocus => node.canRequestFocus;
}

// ═══════════════════════════════════════════════════════════════════════════
// FOCUS MANAGEMENT SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing focus state across the application
class FocusManagementService extends ChangeNotifier {
  FocusManagementService._();
  static final instance = FocusManagementService._();

  // State
  final Map<String, FocusNodeInfo> _registeredNodes = {};
  final List<String> _focusHistory = [];
  final List<FocusScopeId> _scopeStack = [];
  String? _currentFocusId;
  String? _restorationFocusId;
  FocusScopeId _currentScope = FocusScopeId.main;
  bool _initialized = false;

  static const int _maxHistorySize = 20;

  // Getters
  String? get currentFocusId => _currentFocusId;
  FocusScopeId get currentScope => _currentScope;
  bool get initialized => _initialized;
  List<String> get focusHistory => List.unmodifiable(_focusHistory);
  int get registeredNodeCount => _registeredNodes.length;

  /// Initialize the service
  void init() {
    if (_initialized) return;
    _initialized = true;
    debugPrint('[FocusManagementService] Initialized');
  }

  /// Register a focus node
  void registerNode({
    required String id,
    required String label,
    required FocusNode node,
    FocusScopeId scope = FocusScopeId.main,
    int tabOrder = 0,
  }) {
    _registeredNodes[id] = FocusNodeInfo(
      id: id,
      label: label,
      scope: scope,
      tabOrder: tabOrder,
      node: node,
    );

    // Listen for focus changes
    node.addListener(() => _onFocusChanged(id, node));

    debugPrint('[FocusManagementService] Registered: $id');
  }

  /// Unregister a focus node
  void unregisterNode(String id) {
    final info = _registeredNodes.remove(id);
    if (info != null) {
      _focusHistory.remove(id);
      debugPrint('[FocusManagementService] Unregistered: $id');
    }
  }

  void _onFocusChanged(String id, FocusNode node) {
    if (node.hasFocus) {
      _currentFocusId = id;
      _addToHistory(id);
      notifyListeners();
      debugPrint('[FocusManagementService] Focused: $id');
    }
  }

  void _addToHistory(String id) {
    // Remove if already in history
    _focusHistory.remove(id);

    // Add to front
    _focusHistory.insert(0, id);

    // Limit history size
    if (_focusHistory.length > _maxHistorySize) {
      _focusHistory.removeLast();
    }
  }

  /// Request focus on a specific node
  bool requestFocus(String id) {
    final info = _registeredNodes[id];
    if (info == null) {
      debugPrint('[FocusManagementService] Node not found: $id');
      return false;
    }

    if (!info.node.canRequestFocus) {
      debugPrint('[FocusManagementService] Cannot request focus: $id');
      return false;
    }

    info.node.requestFocus();
    return true;
  }

  /// Focus the previous item in history
  bool focusPrevious() {
    if (_focusHistory.length < 2) return false;

    final previousId = _focusHistory[1];
    return requestFocus(previousId);
  }

  /// Focus the first node in the current scope
  bool focusFirst() {
    final nodes = _getNodesInScope(_currentScope);
    if (nodes.isEmpty) return false;

    nodes.sort((a, b) => a.tabOrder.compareTo(b.tabOrder));
    return requestFocus(nodes.first.id);
  }

  /// Focus the last node in the current scope
  bool focusLast() {
    final nodes = _getNodesInScope(_currentScope);
    if (nodes.isEmpty) return false;

    nodes.sort((a, b) => a.tabOrder.compareTo(b.tabOrder));
    return requestFocus(nodes.last.id);
  }

  /// Focus the next node in tab order
  bool focusNext() {
    final nodes = _getNodesInScope(_currentScope);
    if (nodes.isEmpty) return false;

    nodes.sort((a, b) => a.tabOrder.compareTo(b.tabOrder));

    if (_currentFocusId == null) {
      return requestFocus(nodes.first.id);
    }

    final currentIndex = nodes.indexWhere((n) => n.id == _currentFocusId);
    if (currentIndex < 0 || currentIndex >= nodes.length - 1) {
      // Wrap to first
      return requestFocus(nodes.first.id);
    }

    return requestFocus(nodes[currentIndex + 1].id);
  }

  /// Focus the previous node in tab order
  bool focusPreviousTab() {
    final nodes = _getNodesInScope(_currentScope);
    if (nodes.isEmpty) return false;

    nodes.sort((a, b) => a.tabOrder.compareTo(b.tabOrder));

    if (_currentFocusId == null) {
      return requestFocus(nodes.last.id);
    }

    final currentIndex = nodes.indexWhere((n) => n.id == _currentFocusId);
    if (currentIndex <= 0) {
      // Wrap to last
      return requestFocus(nodes.last.id);
    }

    return requestFocus(nodes[currentIndex - 1].id);
  }

  List<FocusNodeInfo> _getNodesInScope(FocusScopeId scope) {
    return _registeredNodes.values
        .where((n) => n.scope == scope && n.node.canRequestFocus)
        .toList();
  }

  /// Push a new focus scope
  void pushScope(FocusScopeId scope) {
    _scopeStack.add(_currentScope);
    _restorationFocusId = _currentFocusId;
    _currentScope = scope;
    notifyListeners();
    debugPrint('[FocusManagementService] Pushed scope: $scope');
  }

  /// Pop the current focus scope and restore previous focus
  void popScope() {
    if (_scopeStack.isEmpty) return;

    _currentScope = _scopeStack.removeLast();
    notifyListeners();

    // Restore focus
    if (_restorationFocusId != null) {
      requestFocus(_restorationFocusId!);
      _restorationFocusId = null;
    }

    debugPrint('[FocusManagementService] Popped scope, now: $_currentScope');
  }

  /// Set focus restoration point (called before dialogs)
  void saveFocusRestoration() {
    _restorationFocusId = _currentFocusId;
    debugPrint('[FocusManagementService] Saved restoration: $_restorationFocusId');
  }

  /// Restore focus to saved point
  bool restoreFocus() {
    if (_restorationFocusId == null) return false;

    final result = requestFocus(_restorationFocusId!);
    _restorationFocusId = null;
    return result;
  }

  /// Clear all focus
  void clearFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    _currentFocusId = null;
    notifyListeners();
    debugPrint('[FocusManagementService] Focus cleared');
  }

  /// Get info about a registered node
  FocusNodeInfo? getNodeInfo(String id) {
    return _registeredNodes[id];
  }

  /// Get all nodes in a scope
  List<FocusNodeInfo> getNodesInScope(FocusScopeId scope) {
    return _registeredNodes.values.where((n) => n.scope == scope).toList();
  }

  /// Check if a node is registered
  bool isRegistered(String id) {
    return _registeredNodes.containsKey(id);
  }

  /// Get current focused node info
  FocusNodeInfo? get currentFocusInfo {
    if (_currentFocusId == null) return null;
    return _registeredNodes[_currentFocusId];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FOCUS INDICATOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Widget that adds visual focus indicator
class FocusIndicator extends StatelessWidget {
  final Widget child;
  final Color focusColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final bool showOnlyWhenFocused;

  const FocusIndicator({
    super.key,
    required this.child,
    this.focusColor = const Color(0xFF4A9EFF),
    this.borderWidth = 2.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.showOnlyWhenFocused = true,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          if (!focused && showOnlyWhenFocused) {
            return child;
          }

          return Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: focused
                  ? Border.all(color: focusColor, width: borderWidth)
                  : null,
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: focusColor.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MANAGED FOCUS NODE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Widget that automatically registers/unregisters with FocusManagementService
class ManagedFocusNode extends StatefulWidget {
  final String id;
  final String label;
  final FocusScopeId scope;
  final int tabOrder;
  final Widget Function(BuildContext context, FocusNode node) builder;

  const ManagedFocusNode({
    super.key,
    required this.id,
    required this.label,
    required this.builder,
    this.scope = FocusScopeId.main,
    this.tabOrder = 0,
  });

  @override
  State<ManagedFocusNode> createState() => _ManagedFocusNodeState();
}

class _ManagedFocusNodeState extends State<ManagedFocusNode> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.label);
    FocusManagementService.instance.registerNode(
      id: widget.id,
      label: widget.label,
      node: _focusNode,
      scope: widget.scope,
      tabOrder: widget.tabOrder,
    );
  }

  @override
  void dispose() {
    FocusManagementService.instance.unregisterNode(widget.id);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _focusNode);
  }
}
