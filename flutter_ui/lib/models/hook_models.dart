// Hook Models — Observer Pattern for Event Lifecycle
//
// Allows external code (scripts, plugins, tests) to observe and react to
// FluxForge events without modifying core providers.
//
// Hook Types:
// - onCreate: When a new entity is created (event, container, RTPC, etc.)
// - onUpdate: When an entity is modified
// - onDelete: When an entity is deleted
// - onStageTriggered: When a stage is triggered
// - onAudioPlayed: When audio playback starts
// - Custom: User-defined hooks
//
// Usage:
//   HookDispatcher.instance.register(
//     HookType.onCreate,
//     'my-plugin',
//     (context) => print('Event created: ${context.entityId}'),
//   );

enum HookType {
  /// Entity lifecycle hooks
  onCreate,
  onUpdate,
  onDelete,

  /// Audio event hooks
  onStageTriggered,
  onAudioPlayed,
  onAudioStopped,

  /// Parameter hooks
  onRtpcChanged,
  onStateChanged,
  onSwitchChanged,

  /// Project hooks
  onProjectSaved,
  onProjectLoaded,

  /// Container hooks
  onContainerEvaluated,

  /// Custom hook (user-defined)
  custom,
}

/// Entity types that can trigger hooks
enum EntityType {
  event,
  layer,
  rtpc,
  stateGroup,
  switchGroup,
  container,
  musicSegment,
  stinger,
  attenuationCurve,
  duckingRule,
  custom,
}

/// Hook context — data passed to hook callbacks
class HookContext {
  final HookType hookType;
  final EntityType entityType;
  final String entityId;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  HookContext({
    required this.hookType,
    required this.entityType,
    required this.entityId,
    this.data = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create context for onCreate hook
  factory HookContext.onCreate({
    required EntityType entityType,
    required String entityId,
    Map<String, dynamic> data = const {},
  }) {
    return HookContext(
      hookType: HookType.onCreate,
      entityType: entityType,
      entityId: entityId,
      data: data,
    );
  }

  /// Create context for onUpdate hook
  factory HookContext.onUpdate({
    required EntityType entityType,
    required String entityId,
    Map<String, dynamic> data = const {},
  }) {
    return HookContext(
      hookType: HookType.onUpdate,
      entityType: entityType,
      entityId: entityId,
      data: data,
    );
  }

  /// Create context for onDelete hook
  factory HookContext.onDelete({
    required EntityType entityType,
    required String entityId,
    Map<String, dynamic> data = const {},
  }) {
    return HookContext(
      hookType: HookType.onDelete,
      entityType: entityType,
      entityId: entityId,
      data: data,
    );
  }

  /// Create context for onStageTriggered hook
  factory HookContext.onStageTriggered({
    required String stage,
    Map<String, dynamic> data = const {},
  }) {
    return HookContext(
      hookType: HookType.onStageTriggered,
      entityType: EntityType.event,
      entityId: stage,
      data: data,
    );
  }

  /// Create context for onAudioPlayed hook
  factory HookContext.onAudioPlayed({
    required String eventId,
    required String audioPath,
    Map<String, dynamic> data = const {},
  }) {
    return HookContext(
      hookType: HookType.onAudioPlayed,
      entityType: EntityType.event,
      entityId: eventId,
      data: {'audioPath': audioPath, ...data},
    );
  }

  /// Create context for onRtpcChanged hook
  factory HookContext.onRtpcChanged({
    required String rtpcId,
    required double value,
    Map<String, dynamic> data = const {},
  }) {
    return HookContext(
      hookType: HookType.onRtpcChanged,
      entityType: EntityType.rtpc,
      entityId: rtpcId,
      data: {'value': value, ...data},
    );
  }

  /// Create context for custom hook
  factory HookContext.custom({
    required String hookName,
    required String entityId,
    EntityType entityType = EntityType.custom,
    Map<String, dynamic> data = const {},
  }) {
    return HookContext(
      hookType: HookType.custom,
      entityType: entityType,
      entityId: entityId,
      data: {'hookName': hookName, ...data},
    );
  }

  /// Get data value by key
  T? get<T>(String key) {
    final value = data[key];
    return value is T ? value : null;
  }

  /// Get data value by key with default
  T getOrDefault<T>(String key, T defaultValue) {
    final value = data[key];
    return value is T ? value : defaultValue;
  }

  @override
  String toString() {
    return 'HookContext(hookType: $hookType, entityType: $entityType, '
        'entityId: $entityId, data: $data, timestamp: $timestamp)';
  }
}

/// Hook callback function signature
typedef HookCallback = void Function(HookContext context);

/// Hook callback with async support
typedef AsyncHookCallback = Future<void> Function(HookContext context);

/// Hook registration info
class HookRegistration {
  final String id;
  final HookType hookType;
  final String? ownerId; // Optional owner ID for scoped hooks
  final HookCallback? callback;
  final AsyncHookCallback? asyncCallback;
  final int priority; // Lower = higher priority (0 = highest)
  final bool enabled;

  HookRegistration({
    required this.id,
    required this.hookType,
    this.ownerId,
    this.callback,
    this.asyncCallback,
    this.priority = 100,
    this.enabled = true,
  }) : assert(callback != null || asyncCallback != null,
            'Must provide either callback or asyncCallback');

  bool get isAsync => asyncCallback != null;

  /// Execute the hook callback
  void execute(HookContext context) {
    if (!enabled) return;
    callback?.call(context);
  }

  /// Execute the async hook callback
  Future<void> executeAsync(HookContext context) async {
    if (!enabled) return;
    if (asyncCallback != null) {
      await asyncCallback!(context);
    } else if (callback != null) {
      callback!(context);
    }
  }

  HookRegistration copyWith({
    String? id,
    HookType? hookType,
    String? ownerId,
    HookCallback? callback,
    AsyncHookCallback? asyncCallback,
    int? priority,
    bool? enabled,
  }) {
    return HookRegistration(
      id: id ?? this.id,
      hookType: hookType ?? this.hookType,
      ownerId: ownerId ?? this.ownerId,
      callback: callback ?? this.callback,
      asyncCallback: asyncCallback ?? this.asyncCallback,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// Hook filter — allows selective hook execution
class HookFilter {
  final EntityType? entityType;
  final String? entityIdPattern; // Regex pattern
  final bool Function(HookContext)? customFilter;

  HookFilter({
    this.entityType,
    this.entityIdPattern,
    this.customFilter,
  });

  /// Check if context matches filter
  bool matches(HookContext context) {
    // Entity type filter
    if (entityType != null && context.entityType != entityType) {
      return false;
    }

    // Entity ID pattern filter
    if (entityIdPattern != null) {
      final regex = RegExp(entityIdPattern!);
      if (!regex.hasMatch(context.entityId)) {
        return false;
      }
    }

    // Custom filter
    if (customFilter != null && !customFilter!(context)) {
      return false;
    }

    return true;
  }
}
