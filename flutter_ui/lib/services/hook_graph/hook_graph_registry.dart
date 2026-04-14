/// HookGraphRegistry — Central lookup: event patterns → hook graphs.
///
/// Supports exact match, wildcard (*), and state-scoped bindings.
/// Priority-sorted resolution with caching.

import '../../models/hook_graph/graph_definition.dart';

/// Resolved binding with priority ordering
class ResolvedGraphBinding implements Comparable<ResolvedGraphBinding> {
  final HookGraphBinding binding;
  final HookGraphDefinition graph;
  final int specificity;

  ResolvedGraphBinding({
    required this.binding,
    required this.graph,
    this.specificity = 0,
  });

  @override
  int compareTo(ResolvedGraphBinding other) {
    // Higher priority first, then higher specificity
    final pDiff = other.binding.priority - binding.priority;
    if (pDiff != 0) return pDiff;
    return other.specificity - specificity;
  }
}

class HookGraphRegistry {
  // Exact event → graph bindings
  final Map<String, List<HookGraphBinding>> _exactBindings = {};

  // Pattern-based bindings (wildcards)
  final List<HookGraphBinding> _patternBindings = [];

  // Loaded graph definitions
  final Map<String, HookGraphDefinition> _graphs = {};

  // Resolution cache (invalidated on change)
  Map<String, List<ResolvedGraphBinding>>? _resolvedCache;

  /// Register a graph definition
  void registerGraph(HookGraphDefinition graph) {
    _graphs[graph.id] = graph;
    _resolvedCache = null;
  }

  /// Remove a graph definition
  void unregisterGraph(String graphId) {
    _graphs.remove(graphId);
    _exactBindings.forEach((_, bindings) {
      bindings.removeWhere((b) => b.graphId == graphId);
    });
    _patternBindings.removeWhere((b) => b.graphId == graphId);
    _resolvedCache = null;
  }

  /// Bind an event pattern to a graph
  void bind(HookGraphBinding binding) {
    if (binding.eventPattern.contains('*') ||
        binding.eventPattern.contains('?')) {
      _patternBindings.add(binding);
    } else {
      _exactBindings
          .putIfAbsent(binding.eventPattern, () => [])
          .add(binding);
    }
    _resolvedCache = null;
  }

  /// Resolve all graphs that should execute for an event
  List<ResolvedGraphBinding> resolve(
    String eventId, {
    Map<String, String>? activeStates,
  }) {
    // Check cache
    final cacheKey = activeStates != null
        ? '$eventId|${activeStates.entries.map((e) => '${e.key}=${e.value}').join(',')}'
        : eventId;

    if (_resolvedCache != null && _resolvedCache!.containsKey(cacheKey)) {
      return _resolvedCache![cacheKey]!;
    }

    final results = <ResolvedGraphBinding>[];

    // Exact matches
    final exact = _exactBindings[eventId];
    if (exact != null) {
      for (final binding in exact) {
        if (!_stateMatches(binding, activeStates)) continue;
        final graph = _graphs[binding.graphId];
        if (graph == null) continue;
        results.add(ResolvedGraphBinding(
          binding: binding,
          graph: graph,
          specificity: 100,
        ));
      }
    }

    // Pattern matches
    for (final binding in _patternBindings) {
      if (!_patternMatches(binding.eventPattern, eventId)) continue;
      if (!_stateMatches(binding, activeStates)) continue;
      final graph = _graphs[binding.graphId];
      if (graph == null) continue;
      results.add(ResolvedGraphBinding(
        binding: binding,
        graph: graph,
        specificity: _patternSpecificity(binding.eventPattern),
      ));
    }

    // Sort by priority (descending), then specificity
    results.sort();

    // Handle exclusive bindings — first exclusive graph blocks others
    final filtered = <ResolvedGraphBinding>[];
    bool exclusiveSeen = false;
    for (final r in results) {
      if (exclusiveSeen) break;
      filtered.add(r);
      if (r.binding.exclusive) exclusiveSeen = true;
    }

    // Cache result
    _resolvedCache ??= {};
    _resolvedCache![cacheKey] = filtered;

    return filtered;
  }

  bool _stateMatches(
      HookGraphBinding binding, Map<String, String>? activeStates) {
    if (binding.stateGroup == null) return true;
    if (activeStates == null) return false;
    return activeStates[binding.stateGroup] == binding.stateValue;
  }

  bool _patternMatches(String pattern, String eventId) {
    // Simple glob: * matches any sequence, ? matches one char
    final regex = RegExp(
      '^${pattern.replaceAll('*', '.*').replaceAll('?', '.')}\$',
    );
    return regex.hasMatch(eventId);
  }

  int _patternSpecificity(String pattern) {
    // More specific patterns get higher scores
    // Exact parts count more than wildcards
    int score = 0;
    for (final char in pattern.split('')) {
      if (char != '*' && char != '?') score += 1;
    }
    return score;
  }

  /// Get all registered graphs
  Map<String, HookGraphDefinition> get graphs =>
      Map.unmodifiable(_graphs);

  /// Get all bindings for a graph
  List<HookGraphBinding> bindingsForGraph(String graphId) {
    final results = <HookGraphBinding>[];
    for (final bindings in _exactBindings.values) {
      results.addAll(bindings.where((b) => b.graphId == graphId));
    }
    results.addAll(_patternBindings.where((b) => b.graphId == graphId));
    return results;
  }

  /// Total binding count (for diagnostics)
  int get bindingCount {
    int count = 0;
    for (final bindings in _exactBindings.values) {
      count += bindings.length;
    }
    count += _patternBindings.length;
    return count;
  }

  /// Clear all bindings and graphs
  void clear() {
    _exactBindings.clear();
    _patternBindings.clear();
    _graphs.clear();
    _resolvedCache = null;
  }
}
