/// Smart Collapsing Provider — SlotLab Middleware §18
///
/// Auto collapse/expand behavior tree sections based on context.
/// Heuristics: expand sections with recent activity, collapse idle sections,
/// auto-focus on node with validation errors, remember user overrides.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §18

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';

/// Collapse rule source
enum CollapseSource {
  /// System automatically collapsed/expanded
  auto,
  /// User manually toggled
  user,
}

class SmartCollapsingProvider extends ChangeNotifier {
  /// Per-category collapse state (true = collapsed)
  final Map<BehaviorCategory, bool> _categoryCollapsed = {};

  /// Per-node collapse state for nodes with children
  final Map<String, bool> _nodeCollapsed = {};

  /// User overrides (sticky — system won't auto-toggle these)
  final Set<String> _userOverrides = {};

  /// Last active category (used for auto-expand)
  BehaviorCategory? _lastActiveCategory;

  /// Auto-collapse idle threshold (seconds since last activity)
  int _idleThresholdSeconds = 30;

  /// Last activity timestamp per category
  final Map<BehaviorCategory, DateTime> _lastActivity = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a category is collapsed
  bool isCategoryCollapsed(BehaviorCategory category) =>
      _categoryCollapsed[category] ?? false;

  /// Check if a node is collapsed
  bool isNodeCollapsed(String nodeId) =>
      _nodeCollapsed[nodeId] ?? false;

  /// Get idle threshold
  int get idleThresholdSeconds => _idleThresholdSeconds;

  /// Get last active category
  BehaviorCategory? get lastActiveCategory => _lastActiveCategory;

  // ═══════════════════════════════════════════════════════════════════════════
  // MANUAL TOGGLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle category collapse (user action — overrides auto-collapse)
  void toggleCategory(BehaviorCategory category) {
    final current = _categoryCollapsed[category] ?? false;
    _categoryCollapsed[category] = !current;
    _userOverrides.add('cat_${category.name}');
    notifyListeners();
  }

  /// Toggle node collapse
  void toggleNode(String nodeId) {
    final current = _nodeCollapsed[nodeId] ?? false;
    _nodeCollapsed[nodeId] = !current;
    _userOverrides.add('node_$nodeId');
    notifyListeners();
  }

  /// Set category collapsed state
  void setCategoryCollapsed(BehaviorCategory category, bool collapsed) {
    _categoryCollapsed[category] = collapsed;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-COLLAPSE LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record activity in a category (expands it, potentially collapses others)
  void recordActivity(BehaviorCategory category) {
    _lastActivity[category] = DateTime.now();
    _lastActiveCategory = category;

    // Auto-expand active category (unless user pinned it collapsed)
    if (!_userOverrides.contains('cat_${category.name}')) {
      _categoryCollapsed[category] = false;
    }

    // Auto-collapse idle categories
    final now = DateTime.now();
    for (final cat in BehaviorCategory.values) {
      if (cat == category) continue;
      if (_userOverrides.contains('cat_${cat.name}')) continue;

      final lastActive = _lastActivity[cat];
      if (lastActive != null &&
          now.difference(lastActive).inSeconds > _idleThresholdSeconds) {
        _categoryCollapsed[cat] = true;
      }
    }

    notifyListeners();
  }

  /// Focus on a specific node (expand its category, scroll to it)
  void focusNode(String nodeId, BehaviorCategory category) {
    // Expand the category
    _categoryCollapsed[category] = false;
    // Expand the node
    _nodeCollapsed[nodeId] = false;
    _lastActiveCategory = category;
    _lastActivity[category] = DateTime.now();
    notifyListeners();
  }

  /// Collapse all categories
  void collapseAll() {
    for (final cat in BehaviorCategory.values) {
      _categoryCollapsed[cat] = true;
    }
    _userOverrides.clear();
    notifyListeners();
  }

  /// Expand all categories
  void expandAll() {
    for (final cat in BehaviorCategory.values) {
      _categoryCollapsed[cat] = false;
    }
    _userOverrides.clear();
    notifyListeners();
  }

  /// Set idle threshold
  void setIdleThreshold(int seconds) {
    _idleThresholdSeconds = seconds.clamp(5, 300);
    notifyListeners();
  }

  /// Clear user overrides (re-enable auto-collapse for all)
  void clearUserOverrides() {
    _userOverrides.clear();
    notifyListeners();
  }
}
