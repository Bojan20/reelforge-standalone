// Hook Dispatcher — Event Lifecycle Observer System
//
// Central dispatcher for hook callbacks throughout FluxForge.
// Allows external code (scripts, plugins, tests) to observe events.
//
// Usage:
//   // Register a hook
//   HookDispatcher.instance.register(
//     HookType.onCreate,
//     'my-plugin',
//     (context) => print('Created: ${context.entityId}'),
//   );
//
//   // Dispatch a hook from provider
//   HookDispatcher.instance.dispatch(
//     HookContext.onCreate(entityType: EntityType.event, entityId: 'evt1'),
//   );
//
//   // Unregister
//   HookDispatcher.instance.unregister(hookId);

import 'dart:async';
import '../models/hook_models.dart';

class HookDispatcher {
  static final HookDispatcher instance = HookDispatcher._();
  HookDispatcher._();

  /// Registered hooks by type
  final Map<HookType, List<HookRegistration>> _hooks = {};

  /// Hook filters by registration ID
  final Map<String, HookFilter> _filters = {};

  /// Hook execution history (limited to last 100)
  final List<HookExecutionRecord> _history = [];
  static const int _maxHistorySize = 100;

  /// Statistics
  int _totalExecutions = 0;
  final Map<HookType, int> _executionsByType = {};

  /// Register a hook callback
  String register(
    HookType hookType,
    String ownerId,
    HookCallback callback, {
    int priority = 100,
    bool enabled = true,
    HookFilter? filter,
  }) {
    final id = '${ownerId}_${hookType.name}_${DateTime.now().millisecondsSinceEpoch}';
    final registration = HookRegistration(
      id: id,
      hookType: hookType,
      ownerId: ownerId,
      callback: callback,
      priority: priority,
      enabled: enabled,
    );

    _hooks.putIfAbsent(hookType, () => []).add(registration);
    _sortHooksByPriority(hookType);

    if (filter != null) {
      _filters[id] = filter;
    }

    return id;
  }

  /// Register an async hook callback
  String registerAsync(
    HookType hookType,
    String ownerId,
    AsyncHookCallback callback, {
    int priority = 100,
    bool enabled = true,
    HookFilter? filter,
  }) {
    final id = '${ownerId}_${hookType.name}_${DateTime.now().millisecondsSinceEpoch}';
    final registration = HookRegistration(
      id: id,
      hookType: hookType,
      ownerId: ownerId,
      asyncCallback: callback,
      priority: priority,
      enabled: enabled,
    );

    _hooks.putIfAbsent(hookType, () => []).add(registration);
    _sortHooksByPriority(hookType);

    if (filter != null) {
      _filters[id] = filter;
    }

    return id;
  }

  /// Unregister a hook by ID
  bool unregister(String hookId) {
    bool found = false;
    for (final type in _hooks.keys) {
      final hooks = _hooks[type]!;
      final index = hooks.indexWhere((h) => h.id == hookId);
      if (index != -1) {
        hooks.removeAt(index);
        found = true;
      }
    }
    _filters.remove(hookId);
    return found;
  }

  /// Unregister all hooks for an owner
  int unregisterOwner(String ownerId) {
    int count = 0;
    for (final type in _hooks.keys) {
      final hooks = _hooks[type]!;
      final toRemove = hooks.where((h) => h.ownerId == ownerId).toList();
      count += toRemove.length;
      for (final h in toRemove) {
        hooks.remove(h);
        _filters.remove(h.id);
      }
    }
    return count;
  }

  /// Enable/disable a hook
  void setEnabled(String hookId, bool enabled) {
    for (final type in _hooks.keys) {
      final hooks = _hooks[type]!;
      final index = hooks.indexWhere((h) => h.id == hookId);
      if (index != -1) {
        final hook = hooks[index];
        hooks[index] = hook.copyWith(enabled: enabled);
        return;
      }
    }
  }

  /// Dispatch a hook synchronously
  void dispatch(HookContext context) {
    final hooks = _hooks[context.hookType];
    if (hooks == null || hooks.isEmpty) return;

    _totalExecutions++;
    _executionsByType[context.hookType] =
        (_executionsByType[context.hookType] ?? 0) + 1;

    final startTime = DateTime.now();
    int executedCount = 0;
    final errors = <String, Object>{};

    for (final hook in hooks) {
      if (!hook.enabled) continue;

      // Apply filter if exists
      final filter = _filters[hook.id];
      if (filter != null && !filter.matches(context)) {
        continue;
      }

      try {
        hook.execute(context);
        executedCount++;
      } catch (e) {
        errors[hook.id] = e;
      }
    }

    final duration = DateTime.now().difference(startTime);
    _recordExecution(context, executedCount, duration, errors);
  }

  /// Dispatch a hook asynchronously
  Future<void> dispatchAsync(HookContext context) async {
    final hooks = _hooks[context.hookType];
    if (hooks == null || hooks.isEmpty) return;

    _totalExecutions++;
    _executionsByType[context.hookType] =
        (_executionsByType[context.hookType] ?? 0) + 1;

    final startTime = DateTime.now();
    int executedCount = 0;
    final errors = <String, Object>{};

    for (final hook in hooks) {
      if (!hook.enabled) continue;

      // Apply filter if exists
      final filter = _filters[hook.id];
      if (filter != null && !filter.matches(context)) {
        continue;
      }

      try {
        await hook.executeAsync(context);
        executedCount++;
      } catch (e) {
        errors[hook.id] = e;
      }
    }

    final duration = DateTime.now().difference(startTime);
    _recordExecution(context, executedCount, duration, errors);
  }

  /// Sort hooks by priority
  void _sortHooksByPriority(HookType hookType) {
    final hooks = _hooks[hookType];
    if (hooks == null) return;
    hooks.sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Record execution history
  void _recordExecution(
    HookContext context,
    int executedCount,
    Duration duration,
    Map<String, Object> errors,
  ) {
    _history.add(HookExecutionRecord(
      context: context,
      executedCount: executedCount,
      duration: duration,
      errors: errors,
    ));

    // Keep history limited
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }
  }

  /// Get registered hooks for a type
  List<HookRegistration> getHooks(HookType hookType) {
    return List.unmodifiable(_hooks[hookType] ?? []);
  }

  /// Get all registered hooks
  Map<HookType, List<HookRegistration>> getAllHooks() {
    return Map<HookType, List<HookRegistration>>.unmodifiable(_hooks.map(
      (type, hooks) => MapEntry(type, List<HookRegistration>.unmodifiable(hooks)),
    ));
  }

  /// Get execution history
  List<HookExecutionRecord> getHistory({int? limit}) {
    if (limit == null) return List<HookExecutionRecord>.unmodifiable(_history);
    final start = _history.length - limit;
    return List<HookExecutionRecord>.unmodifiable(_history.sublist(start.clamp(0, _history.length)));
  }

  /// Get statistics
  HookDispatcherStats getStats() {
    return HookDispatcherStats(
      totalExecutions: _totalExecutions,
      executionsByType: Map.unmodifiable(_executionsByType),
      registeredHooks: _hooks.values.fold(0, (sum, hooks) => sum + hooks.length),
      enabledHooks: _hooks.values.fold(
        0,
        (sum, hooks) => sum + hooks.where((h) => h.enabled).length,
      ),
    );
  }

  /// Clear all hooks
  void clear() {
    _hooks.clear();
    _filters.clear();
  }

  /// Clear history
  void clearHistory() {
    _history.clear();
  }

  /// Reset statistics
  void resetStats() {
    _totalExecutions = 0;
    _executionsByType.clear();
  }
}

/// Hook execution record for history
class HookExecutionRecord {
  final HookContext context;
  final int executedCount;
  final Duration duration;
  final Map<String, Object> errors;
  final DateTime timestamp;

  HookExecutionRecord({
    required this.context,
    required this.executedCount,
    required this.duration,
    required this.errors,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() {
    return 'HookExecutionRecord('
        'type: ${context.hookType}, '
        'entity: ${context.entityId}, '
        'executed: $executedCount, '
        'duration: ${duration.inMilliseconds}ms, '
        'errors: ${errors.length})';
  }
}

/// Hook dispatcher statistics
class HookDispatcherStats {
  final int totalExecutions;
  final Map<HookType, int> executionsByType;
  final int registeredHooks;
  final int enabledHooks;

  HookDispatcherStats({
    required this.totalExecutions,
    required this.executionsByType,
    required this.registeredHooks,
    required this.enabledHooks,
  });

  double get avgExecutionsPerHook {
    if (registeredHooks == 0) return 0;
    return totalExecutions / registeredHooks;
  }

  @override
  String toString() {
    return 'HookDispatcherStats('
        'totalExecutions: $totalExecutions, '
        'registeredHooks: $registeredHooks, '
        'enabledHooks: $enabledHooks)';
  }
}
