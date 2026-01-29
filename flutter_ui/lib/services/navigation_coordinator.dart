/// Navigation Coordinator Service
///
/// Central service for cross-panel navigation in SlotLab.
/// Enables navigation from one panel to related content in another panel.
///
/// SL-INT-P1.3: Cross-Panel Navigation
///
/// Examples:
/// - Click stage in Timeline → navigate to Events panel, select event using that stage
/// - Click event in Events Folder → navigate to Timeline, highlight regions
/// - Click layer → navigate to Composite Editor with that layer selected

import 'package:flutter/foundation.dart';

/// Navigation target specifies which panel to navigate to
enum NavigationTarget {
  eventsFolder,     // Events panel (right side)
  timeline,         // Timeline (center)
  compositeEditor,  // Composite editor in Events panel
  ultimateAudio,    // Ultimate Audio Panel (left side)
  lowerZone,        // Specific lower zone tab
}

/// Navigation context provides data for the target panel
class NavigationContext {
  final NavigationTarget target;
  final Map<String, dynamic> data;

  const NavigationContext({
    required this.target,
    required this.data,
  });

  /// Convenience constructors for common navigation patterns

  /// Navigate to event in Events panel
  factory NavigationContext.toEvent(String eventId) {
    return NavigationContext(
      target: NavigationTarget.eventsFolder,
      data: {'eventId': eventId, 'scrollTo': true},
    );
  }

  /// Navigate to stage in Ultimate Audio Panel
  factory NavigationContext.toStage(String stage) {
    return NavigationContext(
      target: NavigationTarget.ultimateAudio,
      data: {'stage': stage, 'expand': true, 'highlight': true},
    );
  }

  /// Navigate to layer in Composite Editor
  factory NavigationContext.toLayer(String eventId, String layerId) {
    return NavigationContext(
      target: NavigationTarget.compositeEditor,
      data: {'eventId': eventId, 'layerId': layerId, 'expand': true},
    );
  }

  /// Navigate to timeline with specific event highlighted
  factory NavigationContext.toTimeline(String eventId) {
    return NavigationContext(
      target: NavigationTarget.timeline,
      data: {'eventId': eventId, 'highlight': true, 'scrollTo': true},
    );
  }

  /// Navigate to lower zone tab
  factory NavigationContext.toLowerZoneTab(String tabId) {
    return NavigationContext(
      target: NavigationTarget.lowerZone,
      data: {'tabId': tabId, 'activate': true},
    );
  }
}

/// Navigation Coordinator — ChangeNotifier for cross-panel navigation
class NavigationCoordinator extends ChangeNotifier {
  static final NavigationCoordinator instance = NavigationCoordinator._();
  NavigationCoordinator._();

  NavigationContext? _pendingNavigation;
  final List<NavigationContext> _history = [];
  static const int _maxHistory = 20;

  /// Get pending navigation (consumed by panels)
  NavigationContext? get pendingNavigation => _pendingNavigation;

  /// Get navigation history
  List<NavigationContext> get history => List.unmodifiable(_history);

  /// Navigate to a target with data
  void navigate(NavigationContext context) {
    _pendingNavigation = context;
    _addToHistory(context);
    debugPrint('[NavigationCoordinator] Navigate to ${context.target} with data: ${context.data}');
    notifyListeners();
  }

  /// Convenience method: Navigate to event
  void navigateToEvent(String eventId) {
    navigate(NavigationContext.toEvent(eventId));
  }

  /// Convenience method: Navigate to stage
  void navigateToStage(String stage) {
    navigate(NavigationContext.toStage(stage));
  }

  /// Convenience method: Navigate to layer
  void navigateToLayer(String eventId, String layerId) {
    navigate(NavigationContext.toLayer(eventId, layerId));
  }

  /// Convenience method: Navigate to timeline
  void navigateToTimeline(String eventId) {
    navigate(NavigationContext.toTimeline(eventId));
  }

  /// Convenience method: Navigate to lower zone tab
  void navigateToLowerZoneTab(String tabId) {
    navigate(NavigationContext.toLowerZoneTab(tabId));
  }

  /// Clear pending navigation (called by consuming panel)
  void clearPending() {
    _pendingNavigation = null;
  }

  /// Go back in history
  void goBack() {
    if (_history.length > 1) {
      _history.removeLast(); // Remove current
      final previous = _history.last;
      _pendingNavigation = previous;
      debugPrint('[NavigationCoordinator] Go back to ${previous.target}');
      notifyListeners();
    }
  }

  /// Clear history
  void clearHistory() {
    _history.clear();
    debugPrint('[NavigationCoordinator] History cleared');
  }

  /// Add to history
  void _addToHistory(NavigationContext context) {
    // Avoid duplicates if same target+data
    if (_history.isNotEmpty) {
      final last = _history.last;
      if (last.target == context.target && _mapsEqual(last.data, context.data)) {
        return; // Skip duplicate
      }
    }

    _history.add(context);
    if (_history.length > _maxHistory) {
      _history.removeAt(0); // Remove oldest
    }
  }

  /// Compare two maps for equality
  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  /// Get history count
  int get historyCount => _history.length;

  /// Check if can go back
  bool get canGoBack => _history.length > 1;
}
