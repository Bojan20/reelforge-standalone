# FluxForge Studio — Automatic Event Discovery System

## Complete Technical Specification

**Version:** 1.0
**Status:** Architecture Blueprint
**Depends on:** EventRegistry, HookDispatcher, MiddlewareProvider, rf-event crate, rf-bridge FFI

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Core Philosophy](#2-core-philosophy)
3. [System Architecture](#3-system-architecture)
4. [Adapter Layer](#4-adapter-layer)
5. [Event Sniffer Engine](#5-event-sniffer-engine)
6. [Event Interception Methods](#6-event-interception-methods)
7. [Slot Game Heuristics Engine](#7-slot-game-heuristics-engine)
8. [Dynamic Event Registry Integration](#8-dynamic-event-registry-integration)
9. [Learning Mode](#9-learning-mode)
10. [Event Inspector UI](#10-event-inspector-ui)
11. [Hook Creation Pipeline](#11-hook-creation-pipeline)
12. [Payload Schema Discovery](#12-payload-schema-discovery)
13. [Conditional Event Logic](#13-conditional-event-logic)
14. [Event Frequency Analysis](#14-event-frequency-analysis)
15. [Event Categorization Engine](#15-event-categorization-engine)
16. [Persistent Event Library](#16-persistent-event-library)
17. [Audio Designer Workflow](#17-audio-designer-workflow)
18. [Integration with Existing Systems](#18-integration-with-existing-systems)
19. [Rust FFI Discovery Bridge](#19-rust-ffi-discovery-bridge)
20. [File Structure](#20-file-structure)
21. [Implementation Phases](#21-implementation-phases)
22. [Data Structures](#22-data-structures)
23. [Critical Rules](#23-critical-rules)
24. [Advanced Interception: OpenTelemetry-Inspired Auto-Instrumentation](#24-advanced-interception-opentelemetry-inspired-auto-instrumentation)
25. [Wire Protocol: Binary Event Streaming](#25-wire-protocol-binary-event-streaming)
26. [Profiler: Wwise/FMOD Capture Log Parity](#26-profiler-wwisefmod-capture-log-parity)
27. [ML-Powered Event Pattern Recognition](#27-ml-powered-event-pattern-recognition)
28. [Session Replay System](#28-session-replay-system)
29. [Security & Sandboxing](#29-security--sandboxing)
30. [Export/Import: Cross-Tool Compatibility](#30-exportimport-cross-tool-compatibility)
31. [Multi-Adapter Concurrent Connection](#31-multi-adapter-concurrent-connection)
32. [Performance Characteristics](#32-performance-characteristics)

---

## 1. Purpose

FluxForge Studio must implement an Automatic Event Discovery System that eliminates the traditional audio middleware dependency chain:

```
TRADITIONAL (Wwise/FMOD):
Game Developer → defines event → registers event → audio designer attaches sound
                 ^^^^^^^^^^^^   ^^^^^^^^^^^^^^^^
                 developer work  developer work

FLUXFORGE:
Game Runtime → emits signals → FluxForge detects them → audio designer attaches sound
               ^^^^^^^^^^^^^   ^^^^^^^^^^^^^^^^^^^^^
               already exists   AUTOMATIC (zero developer work)
```

The system allows audio designers to build complete audio logic without requiring a single line of developer integration code for each event.

FluxForge becomes a runtime gameplay observer — it watches the game as it runs and constructs its own event vocabulary from observed signals.

---

## 2. Core Philosophy

FluxForge does NOT rely on a predefined list of events.

Events are dynamically discovered during runtime using interception layers.

FluxForge becomes an observer of gameplay runtime signals.

The system observes:

| Signal Source | Discovery Method | Example Events |
|---|---|---|
| EventBus calls | Function wrapping | `SpinStart`, `ReelStop`, `Win` |
| Game state transitions | State machine observation | `StateEnter:Spin`, `StateExit:Win` |
| Animation markers | Timeline marker extraction | `reelStop`, `scatterLand`, `bonusReveal` |
| Network/game messages | Message bus interception | `{type: "reel_stop", reel: 3}` |
| Audio trigger calls | Play function wrapping | `AudioTrigger:reelStop` |
| UI interaction signals | DOM/framework event capture | `SpinButtonPressed`, `CollectClicked` |
| Runtime value changes | Property observation | `creditsBefore < creditsAfter` → `Win` |

From these signals FluxForge constructs a **Dynamic Event Registry** that merges seamlessly with the existing `EventRegistry` singleton (`event_registry.dart:564`).

---

## 3. System Architecture

### Three-Tier Discovery Pipeline

```
TIER 1: ADAPTER LAYER
┌─────────────────────────────────────────────────────────────────┐
│                    Game Engine Runtime                           │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐      │
│  │ EventBus  │ │  State    │ │ Animation │ │   Audio   │      │
│  │  Signals  │ │ Machine   │ │  Markers  │ │  Triggers │      │
│  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘      │
│        │              │              │              │            │
│        └──────────────┼──────────────┼──────────────┘            │
│                       ▼                                          │
│              FluxForge Adapter Layer                             │
│        (Engine-specific interception code)                       │
│                       │                                          │
│              observe(eventName, payload, source)                 │
└───────────────────────┼─────────────────────────────────────────┘
                        │
TIER 2: SNIFFER ENGINE  │
┌───────────────────────┼─────────────────────────────────────────┐
│                       ▼                                          │
│            ┌─────────────────────┐                               │
│            │  Event Sniffer      │                               │
│            │  Engine             │                               │
│            │  ─────────────────  │                               │
│            │  Deduplication      │                               │
│            │  Frequency counter  │                               │
│            │  Payload analysis   │                               │
│            │  Category inference │                               │
│            │  Schema extraction  │                               │
│            │  Heuristics engine  │                               │
│            └────────┬────────────┘                               │
│                     │                                            │
│         ┌───────────┼───────────┐                                │
│         ▼           ▼           ▼                                │
│  ┌────────────┐ ┌────────┐ ┌─────────────┐                     │
│  │ Discovery  │ │ Schema │ │ Frequency   │                     │
│  │ Registry   │ │ Store  │ │ Histogram   │                     │
│  └────────────┘ └────────┘ └─────────────┘                     │
└───────────────────────┬─────────────────────────────────────────┘
                        │
TIER 3: STUDIO UI       │
┌───────────────────────┼─────────────────────────────────────────┐
│                       ▼                                          │
│  ┌────────────────────────────────────────┐                     │
│  │          Event Inspector Panel          │                     │
│  │  ┌──────────────────────────────────┐  │                     │
│  │  │  LIVE: SpinStart [Game]     0.3s │  │                     │
│  │  │  LIVE: ReelStop  [Reel] reel:0   │  │  ← Real-time feed  │
│  │  │  LIVE: ReelStop  [Reel] reel:1   │  │                     │
│  │  │  LIVE: ReelStop  [Reel] reel:2   │  │                     │
│  │  │  LIVE: SymbolLand [Symbol] x:2   │  │                     │
│  │  │  LIVE: WinStart  [Win] amt:50    │  │                     │
│  │  └──────────────────────────────────┘  │                     │
│  │                                         │                     │
│  │  [Attach Audio] [Create Hook] [Ignore]  │                     │
│  └────────────────────────────────────────┘                     │
│                       │                                          │
│                       ▼                                          │
│  ┌────────────────────────────────────────┐                     │
│  │       Existing EventRegistry           │                     │
│  │       (event_registry.dart)            │  ← Merge point      │
│  │       _stageToEvent mapping            │                     │
│  │       _syncEventToRegistry()           │                     │
│  └────────────────────────────────────────┘                     │
│                       │                                          │
│                       ▼                                          │
│  ┌────────────────────────────────────────┐                     │
│  │       HookDispatcher                   │                     │
│  │       (hook_dispatcher.dart)           │  ← Observer chain   │
│  │       Hook execution pipeline          │                     │
│  └────────────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow: End-to-End

```
1. Game emits runtime signal (EventBus.emit, state change, animation marker)
       │
2. Adapter Layer intercepts signal via function wrapping
       │
3. Adapter calls: FluxForgeSniffer.capture(eventName, payload, source)
       │
4. Sniffer Engine processes:
       ├─ Deduplicate (same event within 16ms window = single event)
       ├─ Extract payload schema (reel: number, amount: number)
       ├─ Increment frequency counter
       ├─ Infer category (SlotEventCategory matching)
       ├─ Run heuristics (slot-specific pattern detection)
       └─ Store in DiscoveryRegistry
       │
5. Discovery Registry persists to discoveredEvents.json
       │
6. Event Inspector UI shows discovered event in real-time
       │
7. Audio designer clicks event → action menu:
       ├─ "Attach Audio" → creates SlotCompositeEvent + layers
       ├─ "Create Hook" → registers HookDispatcher callback
       ├─ "Create Automation" → creates RTPC binding
       ├─ "Ignore" → adds to ignore list
       └─ "Map to Stage" → maps to existing stage in EventRegistry
       │
8. Created event syncs via _syncEventToRegistry() (SINGLE SYNC POINT)
       │
9. Next time game emits same signal → EventRegistry triggers audio
```

---

## 4. Adapter Layer

The Adapter Layer connects FluxForge to the game runtime. Each game technology stack requires a specific adapter implementation.

### Adapter Interface Contract

```dart
/// Base contract for all game engine adapters
abstract class FluxForgeAdapter {
  /// Human-readable adapter name
  String get name;

  /// Game engine identifier (unity, unreal, pixijs, custom)
  String get engineType;

  /// Connection status
  AdapterStatus get status;

  /// Start intercepting runtime signals
  Future<void> attach();

  /// Stop intercepting
  Future<void> detach();

  /// Register a signal observer
  void onSignalCaptured(void Function(CapturedSignal signal) callback);

  /// Supported interception methods
  Set<InterceptionMethod> get supportedMethods;

  /// Active interception methods (user can disable specific ones)
  Set<InterceptionMethod> get activeMethods;

  /// Enable/disable specific interception method
  void setMethodActive(InterceptionMethod method, bool active);
}

enum AdapterStatus {
  disconnected,   // Not attached to game runtime
  connecting,     // Handshake in progress
  attached,       // Actively intercepting signals
  learning,       // In learning mode (recording all signals)
  error,          // Connection failure
}

enum InterceptionMethod {
  eventBus,           // EventBus.emit() wrapping
  messageBus,         // MessageBus.dispatch() wrapping
  animationMarkers,   // Animation timeline marker extraction
  stateMachine,       // State transition observation
  audioTriggers,      // Audio play() call interception
  uiInteraction,      // UI event capture
  valueObservation,   // Runtime value change detection
  heuristics,         // Slot-specific pattern detection
}
```

### Adapter Implementations

#### JavaScript/PixiJS Adapter (Slot Games)

```dart
class PixiJSAdapter extends FluxForgeAdapter {
  @override
  String get name => 'PixiJS Slot Adapter';

  @override
  String get engineType => 'pixijs';

  @override
  Set<InterceptionMethod> get supportedMethods => {
    InterceptionMethod.eventBus,
    InterceptionMethod.messageBus,
    InterceptionMethod.animationMarkers,
    InterceptionMethod.stateMachine,
    InterceptionMethod.audioTriggers,
    InterceptionMethod.uiInteraction,
    InterceptionMethod.valueObservation,
    InterceptionMethod.heuristics,
  };

  @override
  Future<void> attach() async {
    // Inject interceptors into PixiJS runtime
    // Wrap EventBus.emit, MessageBus.dispatch, AudioEngine.play
    // Register animation marker listeners
    // Start state machine observer
    // Start value change monitors
  }
}
```

#### Unity Adapter

```dart
class UnityAdapter extends FluxForgeAdapter {
  @override
  String get name => 'Unity Bridge Adapter';

  @override
  String get engineType => 'unity';

  @override
  Future<void> attach() async {
    // Connect via Unity Native Plugin Interface
    // Intercept UnityEvent.Invoke calls
    // Observe Animator state transitions
    // Capture SendMessage calls
    // Monitor Addressables loading (for audio asset triggers)
  }
}
```

#### Unreal Adapter

```dart
class UnrealAdapter extends FluxForgeAdapter {
  @override
  String get name => 'Unreal Engine Adapter';

  @override
  String get engineType => 'unreal';

  @override
  Future<void> attach() async {
    // Connect via Unreal Plugin Module
    // Intercept UGameplayStatics::PlaySound2D calls
    // Observe Blueprint Event Dispatchers
    // Capture Gameplay Ability System events
    // Monitor Niagara particle events
    // Intercept Animation Notifies
  }
}
```

#### Generic TCP/WebSocket Adapter

```dart
class GenericTCPAdapter extends FluxForgeAdapter {
  @override
  String get name => 'Generic TCP Adapter';

  @override
  String get engineType => 'custom';

  @override
  Future<void> attach() async {
    // Connect via TCP/WebSocket to game runtime
    // Game sends JSON messages: { "event": "name", "payload": {...} }
    // Zero game-side integration — game sends messages to FluxForge port
  }
}
```

### Adapter Registry

```dart
class AdapterRegistry {
  static final AdapterRegistry instance = AdapterRegistry._();
  AdapterRegistry._();

  final Map<String, FluxForgeAdapter> _adapters = {};

  /// Register a new adapter
  void register(FluxForgeAdapter adapter) {
    _adapters[adapter.engineType] = adapter;
  }

  /// Get adapter by engine type
  FluxForgeAdapter? getAdapter(String engineType) => _adapters[engineType];

  /// All registered adapters
  List<FluxForgeAdapter> get all => _adapters.values.toList();

  /// Auto-detect adapter based on runtime environment
  Future<FluxForgeAdapter?> autoDetect() async {
    for (final adapter in _adapters.values) {
      try {
        await adapter.attach();
        if (adapter.status == AdapterStatus.attached) return adapter;
      } catch (_) {
        // Try next adapter
      }
    }
    return null;
  }
}
```

---

## 5. Event Sniffer Engine

The Event Sniffer Engine is the central processing unit that receives raw signals from adapters, processes them, and feeds the Discovery Registry.

### Core Architecture

```dart
class EventSnifferEngine {
  static final EventSnifferEngine instance = EventSnifferEngine._();
  EventSnifferEngine._();

  /// Active adapter
  FluxForgeAdapter? _adapter;

  /// Discovery registry (discovered events)
  final DiscoveryRegistry _discoveryRegistry = DiscoveryRegistry.instance;

  /// Frequency histogram
  final FrequencyHistogram _histogram = FrequencyHistogram();

  /// Schema store
  final PayloadSchemaStore _schemaStore = PayloadSchemaStore();

  /// Heuristics engine (slot-specific)
  final SlotHeuristicsEngine _heuristics = SlotHeuristicsEngine();

  /// Category inference engine
  final CategoryInferenceEngine _categoryEngine = CategoryInferenceEngine();

  /// Deduplication window (signals within this window = single event)
  static const Duration _deduplicationWindow = Duration(milliseconds: 16);

  /// Recent captures for deduplication
  final Map<String, DateTime> _recentCaptures = {};

  /// Capture counter (total signals processed)
  int _totalCaptured = 0;
  int _totalDeduplicated = 0;

  /// Learning mode state
  bool _isLearning = false;
  LearningSession? _currentSession;

  /// Signal processing pipeline
  void capture(CapturedSignal signal) {
    _totalCaptured++;

    // Stage 1: Deduplication
    final dedupeKey = '${signal.eventName}_${signal.source}';
    final now = DateTime.now();
    final lastCapture = _recentCaptures[dedupeKey];
    if (lastCapture != null && now.difference(lastCapture) < _deduplicationWindow) {
      _totalDeduplicated++;
      return; // Duplicate within window — skip
    }
    _recentCaptures[dedupeKey] = now;

    // Stage 2: Payload schema extraction
    if (signal.payload != null && signal.payload!.isNotEmpty) {
      _schemaStore.analyze(signal.eventName, signal.payload!);
    }

    // Stage 3: Frequency tracking
    _histogram.record(signal.eventName, now);

    // Stage 4: Category inference
    final inferredCategory = _categoryEngine.infer(signal.eventName, signal.payload);

    // Stage 5: Heuristic evaluation (slot-specific)
    final heuristicEvents = _heuristics.evaluate(signal);

    // Stage 6: Register in Discovery Registry
    _discoveryRegistry.registerDiscoveredEvent(DiscoveredEvent(
      eventName: signal.eventName,
      payload: signal.payload,
      source: signal.source,
      interceptionMethod: signal.method,
      category: inferredCategory,
      timestamp: now,
      frequency: _histogram.getFrequency(signal.eventName),
      payloadSchema: _schemaStore.getSchema(signal.eventName),
    ));

    // Stage 7: Register any heuristic-derived events
    for (final hEvent in heuristicEvents) {
      _discoveryRegistry.registerDiscoveredEvent(hEvent);
    }

    // Stage 8: Learning mode recording
    if (_isLearning && _currentSession != null) {
      _currentSession!.addSignal(signal);
    }

    // Stage 9: Notify UI observers
    _discoveryRegistry.notifyListeners();
  }

  /// Periodic cleanup of deduplication cache
  void _cleanupDeduplicationCache() {
    final cutoff = DateTime.now().subtract(_deduplicationWindow * 10);
    _recentCaptures.removeWhere((_, time) => time.isBefore(cutoff));
  }
}
```

### Captured Signal Model

```dart
class CapturedSignal {
  final String eventName;
  final Map<String, dynamic>? payload;
  final String source;                    // 'EventBus', 'StateMachine', 'Animation', etc.
  final InterceptionMethod method;
  final DateTime timestamp;
  final String? adapterType;              // 'pixijs', 'unity', 'unreal', 'custom'

  const CapturedSignal({
    required this.eventName,
    this.payload,
    required this.source,
    required this.method,
    required this.timestamp,
    this.adapterType,
  });

  Map<String, dynamic> toJson() => {
    'eventName': eventName,
    'payload': payload,
    'source': source,
    'method': method.name,
    'timestamp': timestamp.toIso8601String(),
    'adapterType': adapterType,
  };
}
```

---

## 6. Event Interception Methods

Each interception method wraps a specific game runtime mechanism.

### 6.1 EventBus Interception

Most game engines use an EventBus pattern for inter-component communication.

**Runtime code (game-side):**
```javascript
EventBus.emit("SpinStart");
EventBus.emit("ReelStop", { reel: 3 });
EventBus.emit("Win", { amount: 50, tier: "big" });
```

**Interception (FluxForge adapter-side):**
```javascript
// Wrap the original emit function
const originalEmit = EventBus.emit;

EventBus.emit = function(eventName, payload) {
    // Forward to FluxForge sniffer
    FluxForgeSniffer.capture({
        eventName: eventName,
        payload: payload,
        source: 'EventBus',
        method: 'eventBus',
        timestamp: performance.now()
    });

    // Call original — game behavior unchanged
    return originalEmit.call(this, eventName, payload);
};
```

**Detected events:**
```
SpinStart         source:EventBus  payload:{}
ReelStop          source:EventBus  payload:{reel:3}
Win               source:EventBus  payload:{amount:50, tier:"big"}
```

### 6.2 Message Bus Interception

Games often use internal message systems with typed messages.

**Runtime code (game-side):**
```javascript
MessageBus.dispatch({ type: "reel_stop", reel: 3, symbol: "cherry" });
MessageBus.dispatch({ type: "win_evaluated", totalWin: 150, lines: [1, 4, 7] });
```

**Interception:**
```javascript
const originalDispatch = MessageBus.dispatch;

MessageBus.dispatch = function(message) {
    FluxForgeSniffer.capture({
        eventName: message.type,
        payload: message,
        source: 'MessageBus',
        method: 'messageBus',
        timestamp: performance.now()
    });

    return originalDispatch.call(this, message);
};
```

**Schema discovery from messages:**
```
reel_stop:
  reel: number (0-4)
  symbol: string ("cherry", "bar", "seven")

win_evaluated:
  totalWin: number
  lines: array<number>
```

### 6.3 Animation Marker Detection

Game animations contain timeline markers at key moments.

**Spine/PixiJS example:**
```javascript
spine.state.addListener({
    event: function(entry, event) {
        // event.data.name = "reelStop", "scatterLand", "bonusReveal"
    }
});
```

**Interception:**
```javascript
// Wrap spine animation event listener
const originalAddListener = spine.state.addListener;

spine.state.addListener = function(listener) {
    const wrappedListener = {
        ...listener,
        event: function(entry, event) {
            FluxForgeSniffer.capture({
                eventName: 'Animation:' + event.data.name,
                payload: {
                    animationName: entry.animation.name,
                    trackIndex: entry.trackIndex,
                    time: entry.trackTime,
                    markerName: event.data.name,
                    intValue: event.intValue,
                    floatValue: event.floatValue,
                    stringValue: event.stringValue,
                },
                source: 'AnimationMarker',
                method: 'animationMarkers',
                timestamp: performance.now()
            });

            if (listener.event) listener.event(entry, event);
        }
    };

    return originalAddListener.call(this, wrappedListener);
};
```

**Detected events:**
```
Animation:reelStop      payload:{animationName:"reel_0", trackIndex:0, time:1.234}
Animation:scatterLand   payload:{animationName:"symbol_scatter", markerName:"scatterLand"}
Animation:bonusReveal   payload:{animationName:"bonus_door", floatValue:3.0}
```

### 6.4 State Machine Observation

Most games use finite state machines for game flow.

**State transitions to observe:**
```
Idle → Spin → Stopping → Evaluating → Win → Collecting → Idle
                                       └→ NoWin → Idle
Idle → Spin → Feature → FeatureSpin → FeatureWin → FeatureEnd → Idle
```

**Interception pattern:**
```javascript
const originalSetState = GameStateMachine.setState;

GameStateMachine.setState = function(newState) {
    const oldState = this.currentState;

    // Generate synthetic enter/exit events
    FluxForgeSniffer.capture({
        eventName: 'StateExit:' + oldState,
        payload: { from: oldState, to: newState },
        source: 'StateMachine',
        method: 'stateMachine',
        timestamp: performance.now()
    });

    FluxForgeSniffer.capture({
        eventName: 'StateEnter:' + newState,
        payload: { from: oldState, to: newState },
        source: 'StateMachine',
        method: 'stateMachine',
        timestamp: performance.now()
    });

    // Generate transition event
    FluxForgeSniffer.capture({
        eventName: 'StateTransition:' + oldState + '->' + newState,
        payload: { from: oldState, to: newState },
        source: 'StateMachine',
        method: 'stateMachine',
        timestamp: performance.now()
    });

    return originalSetState.call(this, newState);
};
```

**Detected events:**
```
StateEnter:Spin          payload:{from:"Idle", to:"Spin"}
StateExit:Spin           payload:{from:"Spin", to:"Stopping"}
StateEnter:Win            payload:{from:"Evaluating", to:"Win"}
StateTransition:Idle->Spin    payload:{from:"Idle", to:"Spin"}
StateTransition:Win->Collecting payload:{from:"Win", to:"Collecting"}
```

### 6.5 Audio Trigger Interception

If the game already has audio triggers, FluxForge can detect them and either replace or augment them.

**Runtime code (game-side):**
```javascript
AudioEngine.play("reelStop");
AudioEngine.play("bigWin", { volume: 0.8, loop: true });
AudioEngine.stop("bgMusic");
```

**Interception:**
```javascript
const originalPlay = AudioEngine.play;
const originalStop = AudioEngine.stop;

AudioEngine.play = function(soundId, options) {
    FluxForgeSniffer.capture({
        eventName: 'AudioTrigger:Play:' + soundId,
        payload: { soundId: soundId, options: options },
        source: 'AudioTrigger',
        method: 'audioTriggers',
        timestamp: performance.now()
    });

    // Optionally: let FluxForge handle playback instead
    if (FluxForge.shouldOverride(soundId)) {
        return FluxForge.play(soundId, options);
    }

    return originalPlay.call(this, soundId, options);
};

AudioEngine.stop = function(soundId) {
    FluxForgeSniffer.capture({
        eventName: 'AudioTrigger:Stop:' + soundId,
        payload: { soundId: soundId },
        source: 'AudioTrigger',
        method: 'audioTriggers',
        timestamp: performance.now()
    });

    return originalStop.call(this, soundId);
};
```

### 6.6 UI Interaction Detection

UI events represent player actions that often need audio feedback.

**Interception targets:**
```
DOM events          → click, hover, scroll, drag
PixiJS events       → pointerdown, pointerup, pointermove
React state changes → useState updates, useReducer dispatches
Button components   → SpinButton.onClick, CollectButton.onClick
```

**Interception pattern:**
```javascript
// PixiJS interactive objects
const originalOn = PIXI.DisplayObject.prototype.on;

PIXI.DisplayObject.prototype.on = function(event, fn, context) {
    const wrappedFn = function(...args) {
        FluxForgeSniffer.capture({
            eventName: 'UI:' + event + ':' + (this.name || this.constructor.name),
            payload: {
                event: event,
                objectName: this.name,
                objectType: this.constructor.name,
                position: { x: this.x, y: this.y },
            },
            source: 'UIInteraction',
            method: 'uiInteraction',
            timestamp: performance.now()
        });

        return fn.apply(context || this, args);
    };

    return originalOn.call(this, event, wrappedFn, context);
};
```

### 6.7 Runtime Value Observation

Monitor game variables for meaningful changes.

```javascript
class ValueObserver {
    constructor(target, propertyPath, eventName) {
        this.target = target;
        this.propertyPath = propertyPath;
        this.eventName = eventName;
        this.lastValue = this._getValue();
    }

    _getValue() {
        return this.propertyPath.split('.').reduce((obj, key) => obj?.[key], this.target);
    }

    poll() {
        const currentValue = this._getValue();
        if (currentValue !== this.lastValue) {
            FluxForgeSniffer.capture({
                eventName: this.eventName,
                payload: {
                    property: this.propertyPath,
                    oldValue: this.lastValue,
                    newValue: currentValue,
                    delta: typeof currentValue === 'number'
                        ? currentValue - this.lastValue
                        : null,
                },
                source: 'ValueObservation',
                method: 'valueObservation',
                timestamp: performance.now()
            });

            this.lastValue = currentValue;
        }
    }
}

// Usage:
const observers = [
    new ValueObserver(game, 'credits', 'CreditsChanged'),
    new ValueObserver(game, 'betLevel', 'BetChanged'),
    new ValueObserver(game, 'multiplier', 'MultiplierChanged'),
    new ValueObserver(game, 'freeSpinsRemaining', 'FreeSpinsChanged'),
];

// Poll at 60fps (via requestAnimationFrame)
function pollValues() {
    for (const observer of observers) observer.poll();
    requestAnimationFrame(pollValues);
}
```

---

## 7. Slot Game Heuristics Engine

FluxForge implements slot-specific detection logic that generates synthetic events from observable patterns, even when the game engine does NOT explicitly emit them.

### Heuristic Rules

```dart
class SlotHeuristicsEngine {
  /// Evaluate a captured signal and generate additional synthetic events
  List<DiscoveredEvent> evaluate(CapturedSignal signal) {
    final results = <DiscoveredEvent>[];

    // Apply all heuristic rules
    for (final rule in _rules) {
      final events = rule.evaluate(signal, _gameState);
      results.addAll(events);
    }

    return results;
  }

  /// Observed game state (built from captured signals)
  final _GameState _gameState = _GameState();

  /// All heuristic rules
  final List<HeuristicRule> _rules = [
    ReelStopDetectionRule(),
    SymbolLandDetectionRule(),
    WinDetectionRule(),
    NearMissDetectionRule(),
    CascadeDetectionRule(),
    MultiplierChangeRule(),
    FreeSpinTriggerRule(),
    BonusEntryRule(),
    BigWinTierRule(),
    JackpotDetectionRule(),
    AnticipationDetectionRule(),
    GambleDetectionRule(),
  ];
}
```

### Heuristic Rule Definitions

#### Reel Stop Detection
```
Trigger:    reelVelocity reaches zero OR reel position snaps to grid
Generates:  REEL_STOP_{index} with payload {reel: index, symbol: visibleSymbol}
Confidence: 99% (velocity-based), 95% (position-based)
Mapping:    → SlotEventCategory.reelStop
```

#### Symbol Land Detection
```
Trigger:    Symbol grid state changes between frames
Generates:  SYMBOL_LAND with payload {x, y, symbol, isSpecial}
            SCATTER_LAND if symbol is scatter type
            WILD_LAND if symbol is wild type
            BONUS_LAND if symbol is bonus type
Confidence: 98%
Mapping:    → SlotEventCategory.anticipation (for scatter/wild/bonus)
            → 'symbol' category (for regular symbols)
```

#### Win Detection
```
Trigger:    credits_after > credits_before (within evaluation window)
Generates:  WIN_PRESENT with payload {amount, ratio, lines}
            Tier classification:
              ratio < 2    → WIN_SMALL
              ratio 2-5    → WIN_MEDIUM
              ratio 5-15   → WIN_BIG
              ratio 15-50  → WIN_MEGA
              ratio > 50   → WIN_EPIC
Confidence: 99%
Mapping:    → SlotEventCategory.win / SlotEventCategory.bigWin
```

#### Near Miss Detection
```
Trigger:    scatter_count == trigger_threshold - 1
            OR bonus_symbol_count == trigger_threshold - 1
Generates:  NEAR_MISS with payload {symbolType, count, needed}
Confidence: 97%
Mapping:    → SlotEventCategory.anticipation
Note:       Critical for anticipation audio (tension building)
```

#### Cascade/Tumble Detection
```
Trigger:    Winning symbols removed AND new symbols fall into grid
Generates:  CASCADE_START, CASCADE_STEP_{n}, CASCADE_END
            payload: {cascadeLevel, symbolsRemoved, newSymbols}
Confidence: 95%
Mapping:    → 'cascade' category
```

#### Multiplier Change Detection
```
Trigger:    Multiplier value increases
Generates:  MULTIPLIER_INCREASE with payload {from, to, delta}
            MULTIPLIER_RESET when multiplier returns to 1
Confidence: 99%
Mapping:    → 'feature' category
```

#### Free Spin Trigger Detection
```
Trigger:    Free spin counter appears OR increases from zero
Generates:  FREE_SPIN_TRIGGERED with payload {count, retrigger}
            FREE_SPIN_START, FREE_SPIN_END
Confidence: 96%
Mapping:    → SlotEventCategory.feature
```

#### Big Win Tier Classification
```
Trigger:    Win detected + win ratio calculated
Generates:  BIGWIN_TIER_{1-5} based on FluxForge tier system
            Uses WinTierConfig (data-driven, NOT hardcoded)
            payload: {amount, ratio, tier, tierLabel}
Confidence: 99%
Mapping:    → SlotEventCategory.bigWin
Note:       NEVER hardcode tier labels/thresholds — use WinTierConfig
```

#### Anticipation Detection
```
Trigger:    2+ scatters landed AND remaining reels still spinning
Generates:  ANTICIPATION_ON with payload {scatterCount, reelsRemaining}
            ANTICIPATION_MISS if final scatter does not land
Confidence: 94%
Mapping:    → SlotEventCategory.anticipation
```

### Game State Tracker

```dart
class _GameState {
  double credits = 0;
  double previousCredits = 0;
  double betLevel = 0;
  int multiplier = 1;
  int freeSpinsRemaining = 0;
  List<List<String>> symbolGrid = [];
  List<List<String>> previousSymbolGrid = [];
  List<double> reelVelocities = [];
  List<bool> reelsStopped = [];
  int scatterCount = 0;
  String currentState = 'Idle';
  String previousState = 'Idle';
  int cascadeLevel = 0;
  bool isFeatureActive = false;
  bool isBonusActive = false;
  DateTime? lastSpinTime;
  DateTime? lastWinTime;

  /// Update state from captured signal
  void updateFromSignal(CapturedSignal signal) {
    final payload = signal.payload;
    if (payload == null) return;

    // Track credits
    if (payload.containsKey('credits')) {
      previousCredits = credits;
      credits = (payload['credits'] as num).toDouble();
    }

    // Track symbol grid
    if (payload.containsKey('symbolGrid')) {
      previousSymbolGrid = List.from(symbolGrid);
      symbolGrid = (payload['symbolGrid'] as List).map(
        (row) => (row as List).map((s) => s.toString()).toList()
      ).toList();
    }

    // Track reel velocities
    if (payload.containsKey('reelVelocity')) {
      final reel = payload['reel'] as int;
      while (reelVelocities.length <= reel) reelVelocities.add(0);
      reelVelocities[reel] = (payload['reelVelocity'] as num).toDouble();
    }

    // Track state
    if (signal.source == 'StateMachine' && payload.containsKey('to')) {
      previousState = currentState;
      currentState = payload['to'] as String;
    }

    // Track multiplier
    if (payload.containsKey('multiplier')) {
      multiplier = payload['multiplier'] as int;
    }

    // Track scatter count
    if (payload.containsKey('scatterCount')) {
      scatterCount = payload['scatterCount'] as int;
    }
  }
}
```

---

## 8. Dynamic Event Registry Integration

Discovered events merge with the existing `EventRegistry` singleton (`event_registry.dart:564`).

### Discovery Registry

```dart
class DiscoveryRegistry extends ChangeNotifier {
  static final DiscoveryRegistry instance = DiscoveryRegistry._();
  DiscoveryRegistry._();

  /// All discovered events (by event name)
  final Map<String, DiscoveredEvent> _discoveredEvents = {};

  /// Events the user has explicitly ignored
  final Set<String> _ignoredEvents = {};

  /// Events the user has mapped to existing stages
  final Map<String, String> _eventToStageMapping = {};

  /// Events the user has attached audio to (promoted to full events)
  final Set<String> _promotedEvents = {};

  /// Live feed (most recent N events for inspector UI)
  final List<DiscoveredEvent> _liveFeed = [];
  static const int _maxLiveFeedSize = 500;

  /// Register a discovered event
  void registerDiscoveredEvent(DiscoveredEvent event) {
    final existing = _discoveredEvents[event.eventName];

    if (existing != null) {
      // Update frequency and last seen timestamp
      _discoveredEvents[event.eventName] = existing.copyWith(
        frequency: existing.frequency + 1,
        lastSeenTimestamp: event.timestamp,
        // Merge payload schemas
        payloadSchema: _mergeSchemas(existing.payloadSchema, event.payloadSchema),
      );
    } else {
      // New event — first time seen
      _discoveredEvents[event.eventName] = event;
    }

    // Add to live feed
    _liveFeed.insert(0, event);
    if (_liveFeed.length > _maxLiveFeedSize) {
      _liveFeed.removeRange(_maxLiveFeedSize, _liveFeed.length);
    }

    notifyListeners();
  }

  /// Promote a discovered event to a full SlotCompositeEvent
  /// This creates the event in MiddlewareProvider and syncs via _syncEventToRegistry()
  SlotCompositeEvent promoteToCompositeEvent(
    String discoveredEventName, {
    required String category,
    required String displayName,
    List<String>? triggerStages,
  }) {
    final discovered = _discoveredEvents[discoveredEventName];
    if (discovered == null) throw ArgumentError('Event not found: $discoveredEventName');

    // Map discovered event name to a stage name
    final stageName = _eventNameToStageName(discoveredEventName);

    // Create composite event
    final event = SlotCompositeEvent(
      id: 'discovered_${discoveredEventName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')}',
      name: displayName,
      category: category,
      color: _categoryToColor(category),
      triggerStages: triggerStages ?? [stageName],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

    _promotedEvents.add(discoveredEventName);
    notifyListeners();

    return event;
  }

  /// Map a discovered event to an existing stage
  void mapToStage(String discoveredEventName, String existingStageName) {
    _eventToStageMapping[discoveredEventName] = existingStageName;
    notifyListeners();
  }

  /// Ignore a discovered event (hide from inspector)
  void ignoreEvent(String eventName) {
    _ignoredEvents.add(eventName);
    notifyListeners();
  }

  /// Unignore a previously ignored event
  void unignoreEvent(String eventName) {
    _ignoredEvents.remove(eventName);
    notifyListeners();
  }

  /// Get all discovered events, excluding ignored
  List<DiscoveredEvent> get activeEvents =>
    _discoveredEvents.values
      .where((e) => !_ignoredEvents.contains(e.eventName))
      .toList()
    ..sort((a, b) => b.frequency.compareTo(a.frequency));

  /// Get live feed for inspector UI
  List<DiscoveredEvent> get liveFeed => List.unmodifiable(_liveFeed);

  /// Get events grouped by category
  Map<String, List<DiscoveredEvent>> get eventsByCategory {
    final grouped = <String, List<DiscoveredEvent>>{};
    for (final event in activeEvents) {
      (grouped[event.category] ??= []).add(event);
    }
    return grouped;
  }

  /// Get unmapped events (discovered but not yet attached to audio)
  List<DiscoveredEvent> get unmappedEvents =>
    activeEvents.where((e) =>
      !_promotedEvents.contains(e.eventName) &&
      !_eventToStageMapping.containsKey(e.eventName)
    ).toList();

  /// Persist to JSON
  Future<void> save(String path) async {
    final json = {
      'discoveredEvents': _discoveredEvents.map((k, v) => MapEntry(k, v.toJson())),
      'ignoredEvents': _ignoredEvents.toList(),
      'eventToStageMapping': _eventToStageMapping,
      'promotedEvents': _promotedEvents.toList(),
    };
    // Write to discoveredEvents.json
  }

  /// Load from JSON
  Future<void> load(String path) async {
    // Read discoveredEvents.json and populate state
  }

  /// Convert discovered event name to FluxForge stage name
  String _eventNameToStageName(String eventName) {
    // Remove prefixes: 'StateEnter:', 'Animation:', 'UI:', 'AudioTrigger:'
    String clean = eventName
      .replaceFirst(RegExp(r'^StateEnter:'), '')
      .replaceFirst(RegExp(r'^StateExit:'), '')
      .replaceFirst(RegExp(r'^Animation:'), '')
      .replaceFirst(RegExp(r'^UI:'), '')
      .replaceFirst(RegExp(r'^AudioTrigger:Play:'), '')
      .replaceFirst(RegExp(r'^AudioTrigger:Stop:'), '');

    // Convert to UPPER_SNAKE_CASE
    return clean
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toUpperCase();
  }
}
```

### Discovered Event Model

```dart
class DiscoveredEvent {
  final String eventName;
  final Map<String, dynamic>? payload;
  final String source;
  final InterceptionMethod interceptionMethod;
  final String category;
  final DateTime timestamp;
  final DateTime? lastSeenTimestamp;
  final int frequency;
  final PayloadSchema? payloadSchema;

  const DiscoveredEvent({
    required this.eventName,
    this.payload,
    required this.source,
    required this.interceptionMethod,
    required this.category,
    required this.timestamp,
    this.lastSeenTimestamp,
    this.frequency = 1,
    this.payloadSchema,
  });

  DiscoveredEvent copyWith({
    int? frequency,
    DateTime? lastSeenTimestamp,
    PayloadSchema? payloadSchema,
  }) => DiscoveredEvent(
    eventName: eventName,
    payload: payload,
    source: source,
    interceptionMethod: interceptionMethod,
    category: category,
    timestamp: timestamp,
    lastSeenTimestamp: lastSeenTimestamp ?? this.lastSeenTimestamp,
    frequency: frequency ?? this.frequency,
    payloadSchema: payloadSchema ?? this.payloadSchema,
  );

  Map<String, dynamic> toJson() => {
    'eventName': eventName,
    'source': source,
    'method': interceptionMethod.name,
    'category': category,
    'firstSeen': timestamp.toIso8601String(),
    'lastSeen': (lastSeenTimestamp ?? timestamp).toIso8601String(),
    'frequency': frequency,
    'payloadSchema': payloadSchema?.toJson(),
  };
}
```

---

## 9. Learning Mode

FluxForge Studio includes a Learning Mode that records all runtime signals during a game session and builds an event library automatically.

### Learning Session Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                        LEARNING MODE                             │
│                                                                  │
│  1. User clicks "Start Learning" in Event Inspector              │
│     └─ Adapter enters AdapterStatus.learning                    │
│     └─ Sniffer engine creates new LearningSession                │
│     └─ UI shows recording indicator (red dot + elapsed time)     │
│                                                                  │
│  2. User plays the slot game (mock or real)                      │
│     └─ All signals captured and recorded                         │
│     └─ Live feed shows real-time events                          │
│     └─ Frequency histogram builds in real-time                   │
│                                                                  │
│  3. User clicks "Stop Learning"                                  │
│     └─ Session finalized                                         │
│     └─ Category inference runs on all captured events            │
│     └─ Payload schemas extracted                                 │
│     └─ Duplicate events merged                                   │
│     └─ Frequency analysis completed                              │
│                                                                  │
│  4. Learning Report generated:                                   │
│     ├─ Total signals captured: 847                               │
│     ├─ Unique events discovered: 23                              │
│     ├─ Categories detected: 8                                    │
│     ├─ Payload schemas extracted: 15                             │
│     ├─ Heuristic events generated: 7                             │
│     └─ Recommended stage mappings: 18                            │
│                                                                  │
│  5. User reviews report and promotes events:                     │
│     ├─ SpinStart → promote (category: spin)                      │
│     ├─ ReelStop → promote (category: reelStop)                   │
│     ├─ Win → promote (category: win)                             │
│     ├─ internal_timer → ignore                                   │
│     └─ debug_log → ignore                                        │
│                                                                  │
│  6. Promoted events become SlotCompositeEvents                   │
│     └─ Synced via _syncEventToRegistry() (SINGLE SYNC POINT)    │
│     └─ Audio designer can now attach sounds                      │
└─────────────────────────────────────────────────────────────────┘
```

### Learning Session Model

```dart
class LearningSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  final List<CapturedSignal> signals = [];
  final String adapterType;
  LearningSessionStatus status = LearningSessionStatus.recording;

  LearningSession({
    required this.id,
    required this.startTime,
    required this.adapterType,
  });

  void addSignal(CapturedSignal signal) {
    signals.add(signal);
  }

  /// Finalize session — run analysis
  LearningReport finalize() {
    endTime = DateTime.now();
    status = LearningSessionStatus.completed;

    // Analyze captured signals
    final uniqueEvents = <String, _EventAccumulator>{};
    for (final signal in signals) {
      final acc = uniqueEvents.putIfAbsent(
        signal.eventName,
        () => _EventAccumulator(signal.eventName),
      );
      acc.addOccurrence(signal);
    }

    // Generate report
    return LearningReport(
      sessionId: id,
      duration: endTime!.difference(startTime),
      totalSignals: signals.length,
      uniqueEvents: uniqueEvents.values.map((acc) => acc.toDiscoveredEvent()).toList(),
      categorySummary: _buildCategorySummary(uniqueEvents),
      recommendations: _generateRecommendations(uniqueEvents),
    );
  }

  /// Generate stage mapping recommendations
  List<StageRecommendation> _generateRecommendations(
    Map<String, _EventAccumulator> events,
  ) {
    final recommendations = <StageRecommendation>[];

    for (final entry in events.entries) {
      final name = entry.key;
      final acc = entry.value;

      // Skip low-frequency noise events
      if (acc.count < 2) continue;

      // Find best matching existing stage
      final matchedStage = _findBestStageMatch(name);

      recommendations.add(StageRecommendation(
        discoveredEventName: name,
        suggestedStageName: matchedStage ?? name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_'),
        suggestedCategory: acc.inferredCategory,
        confidence: matchedStage != null ? 0.95 : 0.7,
        frequency: acc.count,
      ));
    }

    // Sort by confidence (highest first)
    recommendations.sort((a, b) => b.confidence.compareTo(a.confidence));
    return recommendations;
  }

  /// Match discovered event name to existing stage name
  String? _findBestStageMatch(String eventName) {
    final normalized = eventName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Check against known FluxForge stages
    const knownStages = {
      'spinstart': 'UI_SPIN_PRESS',
      'spinend': 'SPIN_END',
      'reelstop': 'REEL_STOP',
      'symbolland': 'SYMBOL_LAND',
      'win': 'WIN_PRESENT',
      'winstart': 'WIN_PRESENT',
      'winend': 'WIN_END',
      'bigwin': 'BIGWIN_TIER_1',
      'bonusstart': 'BONUS_ENTER',
      'bonusend': 'BONUS_EXIT',
      'featurestart': 'FEATURE_ENTER',
      'featureend': 'FEATURE_EXIT',
      'anticipation': 'ANTICIPATION_ON',
      'freespin': 'FEATURE_ENTER',
      'cascade': 'CASCADE_START',
      'multiplier': 'MULTIPLIER_INCREASE',
      'gamble': 'GAMBLE_ENTER',
      'collect': 'WIN_COLLECT',
    };

    for (final entry in knownStages.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }

    return null;
  }
}

enum LearningSessionStatus {
  recording,
  completed,
  analyzed,
}
```

### Learning Report

```dart
class LearningReport {
  final String sessionId;
  final Duration duration;
  final int totalSignals;
  final List<DiscoveredEvent> uniqueEvents;
  final Map<String, int> categorySummary;
  final List<StageRecommendation> recommendations;

  const LearningReport({
    required this.sessionId,
    required this.duration,
    required this.totalSignals,
    required this.uniqueEvents,
    required this.categorySummary,
    required this.recommendations,
  });

  /// Events grouped by recommendation confidence
  List<DiscoveredEvent> get highConfidenceEvents =>
    uniqueEvents.where((e) {
      final rec = recommendations.firstWhere(
        (r) => r.discoveredEventName == e.eventName,
        orElse: () => StageRecommendation.empty(),
      );
      return rec.confidence >= 0.9;
    }).toList();
}

class StageRecommendation {
  final String discoveredEventName;
  final String suggestedStageName;
  final String suggestedCategory;
  final double confidence;
  final int frequency;

  const StageRecommendation({
    required this.discoveredEventName,
    required this.suggestedStageName,
    required this.suggestedCategory,
    required this.confidence,
    required this.frequency,
  });

  factory StageRecommendation.empty() => const StageRecommendation(
    discoveredEventName: '',
    suggestedStageName: '',
    suggestedCategory: 'general',
    confidence: 0,
    frequency: 0,
  );
}
```

---

## 10. Event Inspector UI

Real-time event inspector panel integrated into FluxForge Studio.

### Panel Location

- **SlotLab:** Lower Zone sub-tab under MONITOR super-tab
- **DAW:** Lower Zone sub-tab under BROWSE super-tab
- **Standalone:** Detachable floating panel (Cmd+Shift+I)

### Panel Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ EVENT DISCOVERY                                      [Learn] [x] │
│ ── Adapter: PixiJS Slot ── Status: Attached ── 847 signals ──── │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ FILTER: [All ▼] [Category ▼] [Source ▼]  🔍 _______________     │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ LIVE FEED                                    [Pause] [Clear] │ │
│ │──────────────────────────────────────────────────────────────│ │
│ │ 14:23:01.234  SpinStart     [Game]  EventBus        ×47     │ │
│ │ 14:23:02.567  ReelStop      [Reel]  EventBus  reel:0 ×141  │ │
│ │ 14:23:02.789  ReelStop      [Reel]  EventBus  reel:1 ×141  │ │
│ │ 14:23:03.012  ReelStop      [Reel]  EventBus  reel:2 ×141  │ │
│ │ 14:23:03.234  ReelStop      [Reel]  EventBus  reel:3 ×141  │ │
│ │ 14:23:03.456  ReelStop      [Reel]  EventBus  reel:4 ×141  │ │
│ │ 14:23:03.678  SymbolLand    [Sym]   Heuristic x:2,y:1 ×705 │ │
│ │ 14:23:04.123  WinPresent    [Win]   Heuristic amt:50  ×23   │ │
│ │ 14:23:04.567  ANTICIPATION  [Ant]   Heuristic sc:2    ×8    │ │
│ │                                                              │ │
│ │ ▸ 14:23:01.234  StateEnter:Spin   [State] StateMachine      │ │
│ │ ▸ 14:23:03.456  StateEnter:Stop   [State] StateMachine      │ │
│ │ ▸ 14:23:04.000  StateEnter:Win    [State] StateMachine      │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ SELECTED: ReelStop  ×141  Source: EventBus                       │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ Payload Schema:                                              │ │
│ │   reel: number (0-4)                                         │ │
│ │   symbol: string? ("cherry", "bar", "seven", "scatter")      │ │
│ │   velocity: number? (0.0)                                    │ │
│ │                                                              │ │
│ │ Frequency: 28.2/spin (5 per spin × 141 occurrences)          │ │
│ │ First seen: 14:20:03.123                                     │ │
│ │ Mapped stage: REEL_STOP (95% confidence)                     │ │
│ │                                                              │ │
│ │ Conditions available:                                        │ │
│ │   reel == 0  →  REEL_STOP_0                                  │ │
│ │   reel == 1  →  REEL_STOP_1                                  │ │
│ │   reel == 2  →  REEL_STOP_2                                  │ │
│ │   reel == 3  →  REEL_STOP_3                                  │ │
│ │   reel == 4  →  REEL_STOP_4                                  │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ [Attach Audio] [Create Hook] [Map to Stage] [Create RTPC] [Ign] │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│ DISCOVERY SUMMARY                                                │
│ ┌────────────┬────────┬────────────┬──────────┐                  │
│ │  Category  │ Events │  Signals   │  Mapped  │                  │
│ ├────────────┼────────┼────────────┼──────────┤                  │
│ │  Game      │    3   │     94     │   2/3    │                  │
│ │  Reel      │    5   │    705     │   5/5    │                  │
│ │  Symbol    │    4   │   3525     │   0/4    │                  │
│ │  Win       │    3   │     69     │   2/3    │                  │
│ │  Feature   │    2   │      8     │   0/2    │                  │
│ │  UI        │    4   │    187     │   0/4    │                  │
│ │  System    │    2   │     46     │   0/2    │                  │
│ └────────────┴────────┴────────────┴──────────┘                  │
│                                                                  │
│ 23 events discovered · 7 mapped · 14 unmapped · 2 ignored        │
└──────────────────────────────────────────────────────────────────┘
```

### Event Inspector Actions

When the user selects a discovered event, these actions are available:

| Action | Result | Integration Point |
|---|---|---|
| **Attach Audio** | Creates `SlotCompositeEvent` with empty layers, opens layer editor | `MiddlewareProvider.addEvent()` → `_syncEventToRegistry()` |
| **Create Hook** | Registers `HookDispatcher` callback for this event | `HookDispatcher.instance.register()` |
| **Map to Stage** | Maps discovered event to existing FluxForge stage name | `DiscoveryRegistry.mapToStage()` → `EventRegistry._stageToEvent` |
| **Create RTPC** | Creates RTPC binding from payload parameter | `MiddlewareProvider.addRtpc()` with payload field |
| **Create Automation** | Creates automation lane driven by payload parameter | Automation engine integration |
| **Ignore** | Hides event from inspector, persists across sessions | `DiscoveryRegistry.ignoreEvent()` |
| **Expand Conditions** | Auto-generates conditional sub-events from payload values | Multiple `SlotCompositeEvent` per condition value |

---

## 11. Hook Creation Pipeline

When the user clicks "Create Hook" on a discovered event:

### Hook Generation Flow

```
1. User selects discovered event "ReelStop" in inspector
       │
2. User clicks "Create Hook"
       │
3. Hook Creation Dialog opens:
       │
       ├─ Hook Type: [onStageTriggered ▼]
       ├─ Event:     ReelStop
       ├─ Action:    [Play ▼] [Stop ▼] [SetVolume ▼] [SetRTPC ▼]
       ├─ Target:    [Select Audio ▼] or [Select Event ▼]
       ├─ Condition: [Always ▼] or [reel == 3 ▼] or [Custom...]
       └─ Priority:  [Normal ▼] [High ▼] [Highest ▼]
       │
4. Generated hook:
       │
       event: ReelStop
       hookType: onStageTriggered
       action: Play
       target: audio://reel_stop_sfx.wav
       condition: null (always)
       priority: Normal
       │
5. Hook registered via HookDispatcher:
       │
       HookDispatcher.instance.register(
         HookType.onStageTriggered,
         'discovery_ReelStop',
         (context) {
           if (context.data['stageName'] == 'REEL_STOP') {
             EventRegistry.instance.triggerStage('REEL_STOP', context.data);
           }
         },
         filter: HookFilter(stagePattern: 'REEL_STOP*'),
       );
       │
6. Hook persisted in project:
       │
       authoringProject.json → hooks[] array
```

### Hook Storage Format

```json
{
  "hooks": [
    {
      "id": "hook_discovery_ReelStop_1709812345",
      "type": "onStageTriggered",
      "ownerId": "discovery_ReelStop",
      "eventName": "ReelStop",
      "stageName": "REEL_STOP",
      "action": "Play",
      "target": "reel_stop_sfx",
      "condition": null,
      "priority": 100,
      "enabled": true,
      "createdAt": "2026-03-07T14:23:01.234Z"
    },
    {
      "id": "hook_discovery_Win_1709812346",
      "type": "onStageTriggered",
      "ownerId": "discovery_Win",
      "eventName": "Win",
      "stageName": "WIN_PRESENT",
      "action": "Play",
      "target": "win_celebration",
      "condition": "payload.amount > 20",
      "priority": 100,
      "enabled": true,
      "createdAt": "2026-03-07T14:23:04.567Z"
    }
  ]
}
```

---

## 12. Payload Schema Discovery

FluxForge analyzes event payloads over time to detect parameter structures.

### Schema Extraction Engine

```dart
class PayloadSchemaStore {
  final Map<String, PayloadSchema> _schemas = {};

  /// Analyze a payload and update schema
  void analyze(String eventName, Map<String, dynamic> payload) {
    final existing = _schemas[eventName];
    if (existing != null) {
      _schemas[eventName] = existing.mergeWith(payload);
    } else {
      _schemas[eventName] = PayloadSchema.fromPayload(payload);
    }
  }

  PayloadSchema? getSchema(String eventName) => _schemas[eventName];
}

class PayloadSchema {
  final Map<String, PayloadField> fields;

  const PayloadSchema({required this.fields});

  factory PayloadSchema.fromPayload(Map<String, dynamic> payload) {
    return PayloadSchema(
      fields: payload.map((key, value) => MapEntry(
        key,
        PayloadField.fromValue(key, value),
      )),
    );
  }

  /// Merge with another payload to refine schema (track min/max, optionality)
  PayloadSchema mergeWith(Map<String, dynamic> payload) {
    final merged = Map<String, PayloadField>.from(fields);

    for (final entry in payload.entries) {
      final existing = merged[entry.key];
      if (existing != null) {
        merged[entry.key] = existing.mergeWith(entry.value);
      } else {
        // New field — mark as optional (wasn't in previous payloads)
        merged[entry.key] = PayloadField.fromValue(entry.key, entry.value)
          .copyWith(optional: true);
      }
    }

    // Mark missing fields as optional
    for (final key in merged.keys) {
      if (!payload.containsKey(key)) {
        merged[key] = merged[key]!.copyWith(optional: true);
      }
    }

    return PayloadSchema(fields: merged);
  }

  Map<String, dynamic> toJson() => {
    'fields': fields.map((k, v) => MapEntry(k, v.toJson())),
  };
}

class PayloadField {
  final String name;
  final PayloadFieldType type;
  final bool optional;
  final Set<dynamic> observedValues;  // Track distinct values
  final double? minValue;             // For numeric fields
  final double? maxValue;             // For numeric fields
  final int occurrences;              // How many payloads contained this field

  const PayloadField({
    required this.name,
    required this.type,
    this.optional = false,
    this.observedValues = const {},
    this.minValue,
    this.maxValue,
    this.occurrences = 1,
  });

  factory PayloadField.fromValue(String name, dynamic value) {
    if (value is int) {
      return PayloadField(
        name: name,
        type: PayloadFieldType.integer,
        observedValues: {value},
        minValue: value.toDouble(),
        maxValue: value.toDouble(),
      );
    } else if (value is double) {
      return PayloadField(
        name: name,
        type: PayloadFieldType.number,
        observedValues: {value},
        minValue: value,
        maxValue: value,
      );
    } else if (value is String) {
      return PayloadField(
        name: name,
        type: PayloadFieldType.string,
        observedValues: {value},
      );
    } else if (value is bool) {
      return PayloadField(
        name: name,
        type: PayloadFieldType.boolean,
        observedValues: {value},
      );
    } else if (value is List) {
      return PayloadField(
        name: name,
        type: PayloadFieldType.array,
        observedValues: {},
      );
    } else if (value is Map) {
      return PayloadField(
        name: name,
        type: PayloadFieldType.object,
        observedValues: {},
      );
    }
    return PayloadField(name: name, type: PayloadFieldType.unknown);
  }

  PayloadField mergeWith(dynamic value) {
    final newValues = Set<dynamic>.from(observedValues)..add(value);
    double? newMin = minValue;
    double? newMax = maxValue;

    if (value is num) {
      newMin = minValue == null ? value.toDouble() : (value < minValue! ? value.toDouble() : minValue);
      newMax = maxValue == null ? value.toDouble() : (value > maxValue! ? value.toDouble() : maxValue);
    }

    return PayloadField(
      name: name,
      type: type,
      optional: optional,
      observedValues: newValues.length > 100 ? {} : newValues, // Cap for memory
      minValue: newMin,
      maxValue: newMax,
      occurrences: occurrences + 1,
    );
  }

  PayloadField copyWith({bool? optional}) => PayloadField(
    name: name,
    type: type,
    optional: optional ?? this.optional,
    observedValues: observedValues,
    minValue: minValue,
    maxValue: maxValue,
    occurrences: occurrences,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'optional': optional,
    'observedValues': observedValues.length <= 20 ? observedValues.toList() : [],
    if (minValue != null) 'min': minValue,
    if (maxValue != null) 'max': maxValue,
    'occurrences': occurrences,
  };
}

enum PayloadFieldType {
  integer,
  number,
  string,
  boolean,
  array,
  object,
  unknown,
}
```

### Schema Usage in Conditional Logic

Discovered payload schemas enable conditional event routing:

```
Event: ReelStop
Payload schema:
  reel: integer (0-4)
  symbol: string ("cherry", "bar", "seven", "scatter", "wild", "bonus")

Auto-generated conditions:
  reel == 0 → REEL_STOP_0 (play reel_stop_0.wav)
  reel == 1 → REEL_STOP_1 (play reel_stop_1.wav)
  reel == 2 → REEL_STOP_2 (play reel_stop_2.wav)
  reel == 3 → REEL_STOP_3 (play reel_stop_3.wav)
  reel == 4 → REEL_STOP_4 (play reel_stop_4.wav)

  symbol == "scatter" → SCATTER_LAND (play scatter_land.wav)
  symbol == "wild"    → WILD_LAND (play wild_land.wav)
  symbol == "bonus"   → BONUS_LAND (play bonus_land.wav)
```

---

## 13. Conditional Event Logic

Hooks and promoted events can include runtime conditions evaluated against payload data.

### Condition Evaluation Engine

```dart
class ConditionEvaluator {
  /// Evaluate a condition expression against payload data
  static bool evaluate(String condition, Map<String, dynamic> payload) {
    // Parse condition: "fieldName operator value"
    final parts = _parseCondition(condition);
    if (parts == null) return true; // Invalid condition = always true

    final fieldValue = payload[parts.field];
    if (fieldValue == null) return false; // Missing field = false

    return switch (parts.operator) {
      '==' => fieldValue == parts.value,
      '!=' => fieldValue != parts.value,
      '>'  => fieldValue is num && parts.value is num && fieldValue > parts.value,
      '>=' => fieldValue is num && parts.value is num && fieldValue >= parts.value,
      '<'  => fieldValue is num && parts.value is num && fieldValue < parts.value,
      '<=' => fieldValue is num && parts.value is num && fieldValue <= parts.value,
      'contains' => fieldValue.toString().contains(parts.value.toString()),
      'matches' => RegExp(parts.value.toString()).hasMatch(fieldValue.toString()),
      _ => true,
    };
  }

  /// Parse "field operator value" into components
  static _ConditionParts? _parseCondition(String condition) {
    final operators = ['>=', '<=', '!=', '==', '>', '<', 'contains', 'matches'];
    for (final op in operators) {
      final idx = condition.indexOf(op);
      if (idx > 0) {
        final field = condition.substring(0, idx).trim();
        final value = condition.substring(idx + op.length).trim();
        return _ConditionParts(field, op, _parseValue(value));
      }
    }
    return null;
  }

  static dynamic _parseValue(String value) {
    // Remove quotes
    if (value.startsWith('"') && value.endsWith('"')) return value.substring(1, value.length - 1);
    if (value.startsWith("'") && value.endsWith("'")) return value.substring(1, value.length - 1);
    // Try number
    final asInt = int.tryParse(value);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(value);
    if (asDouble != null) return asDouble;
    // Try boolean
    if (value == 'true') return true;
    if (value == 'false') return false;
    return value;
  }
}

class _ConditionParts {
  final String field;
  final String operator;
  final dynamic value;
  _ConditionParts(this.field, this.operator, this.value);
}
```

### Conditional Hook Example

```dart
// Condition: play different audio based on win amount
HookDispatcher.instance.register(
  HookType.onStageTriggered,
  'discovery_Win_Big',
  (context) {
    final payload = context.data;
    if (ConditionEvaluator.evaluate('amount > 20', payload)) {
      EventRegistry.instance.triggerStage('BIGWIN_TIER_1', payload);
    }
  },
  filter: HookFilter(stagePattern: 'WIN_PRESENT'),
);

// Condition: play scatter land only for specific reel positions
HookDispatcher.instance.register(
  HookType.onStageTriggered,
  'discovery_ScatterLand',
  (context) {
    final payload = context.data;
    if (ConditionEvaluator.evaluate('symbol == "scatter"', payload)) {
      final reel = payload['reel'] as int?;
      if (reel != null) {
        EventRegistry.instance.triggerStage('SCATTER_LAND_$reel', payload);
      }
    }
  },
  filter: HookFilter(stagePattern: 'SYMBOL_LAND*'),
);
```

---

## 14. Event Frequency Analysis

FluxForge records detailed frequency data for every discovered event.

### Frequency Histogram

```dart
class FrequencyHistogram {
  /// Event name → list of timestamps (most recent N)
  final Map<String, List<DateTime>> _timestamps = {};
  static const int _maxTimestampsPerEvent = 1000;

  /// Record an occurrence
  void record(String eventName, DateTime timestamp) {
    final list = _timestamps.putIfAbsent(eventName, () => []);
    list.add(timestamp);
    if (list.length > _maxTimestampsPerEvent) {
      list.removeAt(0); // Remove oldest
    }
  }

  /// Get frequency (occurrences per second, averaged over last 60s)
  double getFrequency(String eventName) {
    final list = _timestamps[eventName];
    if (list == null || list.length < 2) return 0;

    final window = const Duration(seconds: 60);
    final cutoff = DateTime.now().subtract(window);
    final recent = list.where((t) => t.isAfter(cutoff)).toList();

    if (recent.length < 2) return 0;

    final span = recent.last.difference(recent.first);
    if (span.inMilliseconds == 0) return 0;

    return recent.length / (span.inMilliseconds / 1000.0);
  }

  /// Get total occurrence count
  int getCount(String eventName) => _timestamps[eventName]?.length ?? 0;

  /// Get per-spin frequency (based on SpinStart count)
  double getPerSpinFrequency(String eventName) {
    final eventCount = getCount(eventName);
    final spinCount = getCount('SpinStart');
    if (spinCount == 0) return 0;
    return eventCount / spinCount;
  }

  /// Get burst detection (rapid consecutive fires)
  BurstInfo? detectBurst(String eventName, {Duration window = const Duration(milliseconds: 100)}) {
    final list = _timestamps[eventName];
    if (list == null || list.length < 3) return null;

    int maxBurst = 1;
    int currentBurst = 1;
    DateTime? burstStart;

    for (int i = 1; i < list.length; i++) {
      if (list[i].difference(list[i - 1]) < window) {
        currentBurst++;
        burstStart ??= list[i - 1];
      } else {
        if (currentBurst > maxBurst) maxBurst = currentBurst;
        currentBurst = 1;
        burstStart = null;
      }
    }

    if (maxBurst < 3) return null;

    return BurstInfo(
      eventName: eventName,
      maxBurstSize: maxBurst,
      averageBurstInterval: window ~/ maxBurst,
    );
  }

  /// Get frequency report for all events
  FrequencyReport generateReport() {
    final entries = _timestamps.entries.map((entry) {
      final eventName = entry.key;
      return FrequencyEntry(
        eventName: eventName,
        totalCount: getCount(eventName),
        perSecond: getFrequency(eventName),
        perSpin: getPerSpinFrequency(eventName),
        burst: detectBurst(eventName),
      );
    }).toList()
      ..sort((a, b) => b.totalCount.compareTo(a.totalCount));

    return FrequencyReport(entries: entries);
  }
}

class BurstInfo {
  final String eventName;
  final int maxBurstSize;
  final Duration averageBurstInterval;

  const BurstInfo({
    required this.eventName,
    required this.maxBurstSize,
    required this.averageBurstInterval,
  });
}

class FrequencyEntry {
  final String eventName;
  final int totalCount;
  final double perSecond;
  final double perSpin;
  final BurstInfo? burst;

  const FrequencyEntry({
    required this.eventName,
    required this.totalCount,
    required this.perSecond,
    required this.perSpin,
    this.burst,
  });
}

class FrequencyReport {
  final List<FrequencyEntry> entries;
  const FrequencyReport({required this.entries});
}
```

### Frequency Data Usage

Frequency data drives audio design decisions:

| Pattern | Implication | Audio Design Action |
|---|---|---|
| `ReelStop` × 5 per spin | Fires once per reel | Use per-reel variations (REEL_STOP_0..4) |
| `SymbolLand` × 15 per spin | Fires for every symbol | Use audio pool, keep SFX short (<200ms) |
| `WinPresent` × 0.3 per spin | Fires 30% of spins | Can use longer audio, no pool needed |
| `BonusStart` × 0.01 per spin | Fires 1% of spins | Full production audio, no optimization needed |
| `RollupTick` × 30-200 per win | Rapid-fire during rollup | Use pre-allocated audio pool, zero GC |
| `CascadeStep` burst of 5-8 | Fires in rapid succession | Layer pool with conflict resolution |

---

## 15. Event Categorization Engine

Automatic category inference based on event name pattern matching and payload analysis.

### Category Inference Rules

```dart
class CategoryInferenceEngine {
  /// Infer category from event name and payload
  String infer(String eventName, Map<String, dynamic>? payload) {
    final lower = eventName.toLowerCase();

    // Pattern matching rules (ordered by specificity)
    for (final rule in _rules) {
      if (rule.matches(lower, payload)) return rule.category;
    }

    return 'general'; // Fallback
  }

  static final List<_CategoryRule> _rules = [
    // Spin lifecycle
    _CategoryRule('spin', patterns: ['spin', 'reel_start', 'start_spin']),

    // Reel mechanics
    _CategoryRule('reelStop', patterns: ['reel_stop', 'reelstop', 'reel_land', 'reel_end']),

    // Symbol events
    _CategoryRule('symbol', patterns: ['symbol', 'scatter', 'wild', 'bonus_symbol']),

    // Anticipation
    _CategoryRule('anticipation', patterns: ['anticipat', 'near_miss', 'tension', 'build_up']),

    // Win events
    _CategoryRule('bigWin', patterns: ['big_win', 'bigwin', 'mega_win', 'super_win', 'epic_win']),
    _CategoryRule('win', patterns: ['win', 'payout', 'reward', 'collect', 'rollup']),

    // Feature/Free spins
    _CategoryRule('feature', patterns: ['feature', 'free_spin', 'freespin', 'retrigger', 'multiplier']),

    // Bonus
    _CategoryRule('bonus', patterns: ['bonus', 'pick', 'reveal', 'door', 'chest']),

    // Cascade/Tumble
    _CategoryRule('cascade', patterns: ['cascade', 'tumble', 'avalanche', 'collapse']),

    // Jackpot
    _CategoryRule('jackpot', patterns: ['jackpot', 'progressive', 'grand_prize']),

    // Hold/Respin
    _CategoryRule('hold', patterns: ['hold', 'respin', 'lock', 'nudge']),

    // Gamble
    _CategoryRule('gamble', patterns: ['gamble', 'double_up', 'risk', 'card_flip']),

    // Music
    _CategoryRule('music', patterns: ['music', 'bgm', 'soundtrack', 'theme']),

    // Ambient
    _CategoryRule('ambient', patterns: ['ambient', 'background', 'atmosphere', 'environment']),

    // UI
    _CategoryRule('ui', patterns: ['button', 'click', 'hover', 'menu', 'settings', 'ui_']),
  ];
}

class _CategoryRule {
  final String category;
  final List<String> patterns;

  const _CategoryRule(this.category, {required this.patterns});

  bool matches(String lowerEventName, Map<String, dynamic>? payload) {
    for (final pattern in patterns) {
      if (lowerEventName.contains(pattern)) return true;
    }
    return false;
  }
}
```

### Category Mapping to FluxForge System

| Inferred Category | SlotEventCategory | Color | Bus Routing |
|---|---|---|---|
| spin | `SlotEventCategory.spin` | `#4A9EFF` | SFX bus |
| reelStop | `SlotEventCategory.reelStop` | `#9B59B6` | Reels bus |
| anticipation | `SlotEventCategory.anticipation` | `#E74C3C` | Anticipation bus |
| win | `SlotEventCategory.win` | `#F1C40F` | Wins bus |
| bigWin | `SlotEventCategory.bigWin` | `#FF9040` | Wins bus |
| feature | `SlotEventCategory.feature` | `#40FF90` | SFX bus |
| bonus | `SlotEventCategory.bonus` | `#FF40FF` | SFX bus |
| cascade | — | `#00BCD4` | SFX bus |
| jackpot | — | `#FFD700` | Wins bus |
| hold | — | `#FF5722` | SFX bus |
| gamble | — | `#795548` | SFX bus |
| music | `SlotEventCategory.music` | `#E91E63` | Music bus (overlap=false) |
| ambient | `SlotEventCategory.ambient` | `#40C8FF` | Music bus |
| ui | `SlotEventCategory.ui` | `#888888` | UI bus |
| symbol | — | `#8BC34A` | SFX bus |
| general | — | `#607D8B` | SFX bus |

---

## 16. Persistent Event Library

Discovered events persist across projects as a reusable library.

### Storage Format

**Per-project:** `{projectDir}/discoveredEvents.json`

```json
{
  "version": 1,
  "adapterType": "pixijs",
  "gameTitle": "Book of Ra Deluxe",
  "lastLearningSession": "2026-03-07T14:20:00Z",
  "discoveredEvents": {
    "SpinStart": {
      "source": "EventBus",
      "method": "eventBus",
      "category": "spin",
      "firstSeen": "2026-03-07T14:20:03.123Z",
      "lastSeen": "2026-03-07T14:23:01.234Z",
      "frequency": 47,
      "payloadSchema": {
        "fields": {}
      },
      "mappedStage": "UI_SPIN_PRESS",
      "promoted": true
    },
    "ReelStop": {
      "source": "EventBus",
      "method": "eventBus",
      "category": "reelStop",
      "firstSeen": "2026-03-07T14:20:03.456Z",
      "lastSeen": "2026-03-07T14:23:03.456Z",
      "frequency": 141,
      "payloadSchema": {
        "fields": {
          "reel": { "type": "integer", "min": 0, "max": 4, "optional": false },
          "symbol": { "type": "string", "optional": true, "observedValues": ["cherry", "bar", "seven", "scatter", "wild"] }
        }
      },
      "mappedStage": "REEL_STOP",
      "promoted": true,
      "conditions": [
        { "field": "reel", "operator": "==", "value": 0, "stage": "REEL_STOP_0" },
        { "field": "reel", "operator": "==", "value": 1, "stage": "REEL_STOP_1" },
        { "field": "reel", "operator": "==", "value": 2, "stage": "REEL_STOP_2" },
        { "field": "reel", "operator": "==", "value": 3, "stage": "REEL_STOP_3" },
        { "field": "reel", "operator": "==", "value": 4, "stage": "REEL_STOP_4" }
      ]
    }
  },
  "ignoredEvents": ["internal_timer", "debug_log", "fps_counter"],
  "learningHistory": [
    {
      "sessionId": "session_001",
      "startTime": "2026-03-07T14:20:00Z",
      "endTime": "2026-03-07T14:23:30Z",
      "totalSignals": 847,
      "uniqueEvents": 23,
      "adapterType": "pixijs"
    }
  ]
}
```

**Global library:** `~/.fluxforge/eventLibrary.json`

Shared across all projects. Contains event templates that can be imported into new projects.

---

## 17. Audio Designer Workflow

### Complete End-to-End Flow

```
STEP 1: CONNECT
├─ Open FluxForge Studio
├─ Select adapter (PixiJS, Unity, Unreal, Custom)
├─ FluxForge connects to game runtime
└─ Status: "Adapter: PixiJS Slot — Status: Attached"

STEP 2: LEARN
├─ Click "Start Learning" in Event Inspector
├─ Play the slot game (5-10 spins minimum)
├─ FluxForge captures all runtime signals in real-time
├─ Live feed shows events as they fire
├─ Click "Stop Learning"
└─ Learning Report shows 23 discovered events

STEP 3: REVIEW
├─ Review discovered events in Event Inspector
├─ High-confidence events auto-mapped to FluxForge stages
├─ SpinStart → UI_SPIN_PRESS (95% confidence)
├─ ReelStop → REEL_STOP_0..4 (99% confidence)
├─ WinPresent → WIN_PRESENT (98% confidence)
├─ Ignore noise events (internal_timer, debug_log)
└─ Promote events with "Attach Audio"

STEP 4: AUTHOR
├─ Each promoted event becomes a SlotCompositeEvent
├─ Drag audio files onto event layers (same as manual authoring)
├─ Set volume, pan, bus routing, DSP chain
├─ Configure conditions (reel == 3 → specific sound)
├─ Set container types (random, blend, sequence)
└─ Audio plays automatically when game emits the signal

STEP 5: ITERATE
├─ Play game again — audio fires automatically
├─ Adjust timing, volumes, layers in real-time
├─ Event Inspector shows which events are mapped vs unmapped
├─ Discover new events from game updates
└─ No developer coordination required

TOTAL DEVELOPER WORK: ZERO
```

### Comparison with Traditional Middleware

```
TRADITIONAL (Wwise/FMOD):
──────────────────────────
1. Audio designer identifies needed events                    [Designer]
2. Audio designer creates event list document                 [Designer]
3. Developer reads event list                                 [Developer]
4. Developer implements event posting in game code            [Developer]
5. Developer compiles and deploys new build                   [Developer]
6. Audio designer receives new build                          [Designer]
7. Audio designer tests events fire correctly                 [Designer]
8. If wrong → goto step 2                                     [Both]
9. Audio designer attaches sounds                             [Designer]

Total: 9 steps, 2 people, multiple iterations, days of work

FLUXFORGE:
──────────────────────────
1. Audio designer clicks "Start Learning"                     [Designer]
2. Audio designer plays game for 2 minutes                    [Designer]
3. Audio designer reviews discovered events                   [Designer]
4. Audio designer attaches sounds                             [Designer]

Total: 4 steps, 1 person, one session, minutes of work
```

---

## 18. Integration with Existing Systems

### EventRegistry Integration

The Discovery system feeds into the existing `EventRegistry` singleton:

```
DiscoveryRegistry                    EventRegistry
(discoveredEvents.json)              (event_registry.dart:564)
       │                                    │
       │  User promotes event               │
       ├──────────────────────────────────▸ │
       │  Creates SlotCompositeEvent        │
       │  via MiddlewareProvider            │
       │                                    │
       │  _onMiddlewareChanged() fires      │
       │                                    │
       │  _syncEventToRegistry()            │
       │  (SINGLE SYNC POINT)               │
       │                                    │
       │                   _stageToEvent[stage] = audioEvent
       │                                    │
       │  Next game signal matches stage    │
       │                                    │
       │                   triggerStage(stage) → play audio
```

**CRITICAL:** Discovered events are promoted through the SAME sync path as manually created events. `_syncEventToRegistry()` in `slot_lab_screen.dart` remains the SINGLE sync point. NEVER add a parallel sync path from DiscoveryRegistry.

### HookDispatcher Integration

Discovery hooks register through the existing `HookDispatcher`:

```dart
// Existing hook types used by discovery:
HookType.onStageTriggered  // When a stage fires
HookType.onAudioPlayed     // When audio starts playing
HookType.onAudioStopped    // When audio stops

// New hook types added for discovery:
HookType.onEventDiscovered // When sniffer captures a new event
HookType.onEventPromoted   // When user promotes a discovered event
```

### DiagnosticsService Integration

Discovery system reports to existing diagnostics:

```dart
// EventFlowMonitor detects:
// - Discovered events that fire but have no audio attached
// - Discovered events with abnormal frequency
// - Discovery adapter connection issues

// New diagnostic checker:
class DiscoveryHealthChecker extends DiagnosticChecker {
  @override
  String get name => 'Discovery Health';

  @override
  List<DiagnosticFinding> check() {
    final findings = <DiagnosticFinding>[];

    // Check for unmapped high-frequency events
    for (final event in DiscoveryRegistry.instance.unmappedEvents) {
      if (event.frequency > 10) {
        findings.add(DiagnosticFinding(
          severity: DiagnosticSeverity.warning,
          message: 'High-frequency event "${event.eventName}" (×${event.frequency}) has no audio attached',
          suggestion: 'Open Event Inspector and attach audio or ignore this event',
        ));
      }
    }

    // Check adapter status
    final adapter = EventSnifferEngine.instance.adapter;
    if (adapter != null && adapter.status == AdapterStatus.error) {
      findings.add(DiagnosticFinding(
        severity: DiagnosticSeverity.error,
        message: 'Discovery adapter "${adapter.name}" is in error state',
        suggestion: 'Check game runtime connection and restart adapter',
      ));
    }

    return findings;
  }
}
```

### MiddlewareProvider Integration

Promoted events are stored as standard `SlotCompositeEvent` objects in `MiddlewareProvider.compositeEvents`:

```dart
// When user promotes a discovered event:
void _promoteDiscoveredEvent(DiscoveredEvent discovered) {
  final middleware = GetIt.instance<MiddlewareProvider>();

  // Create composite event with inferred properties
  final event = DiscoveryRegistry.instance.promoteToCompositeEvent(
    discovered.eventName,
    category: discovered.category,
    displayName: discovered.eventName,
    triggerStages: [discovered.eventName.toUpperCase()],
  );

  // Add to middleware (single source of truth)
  middleware.addEvent(event);

  // _onMiddlewareChanged() will fire automatically
  // _syncEventToRegistry() will register the stage mapping
  // Audio designer can now add layers in the right panel
}
```

---

## 19. Rust FFI Discovery Bridge

For adapters that connect via the Rust FFI bridge, a discovery channel is added to the existing `rf-bridge` crate.

### Rust-side Discovery Module

```
crates/rf-bridge/src/
├── discovery_ffi.rs      ← NEW: Discovery FFI exports
└── ...

crates/rf-event/src/
├── discovery.rs          ← NEW: Discovery event processing
└── ...
```

### Discovery FFI Functions

```rust
// crates/rf-bridge/src/discovery_ffi.rs

use std::sync::Mutex;
use lazy_static::lazy_static;

lazy_static! {
    /// Lock-free channel for discovered events (adapter → Flutter)
    static ref DISCOVERY_QUEUE: Mutex<Vec<DiscoveredSignal>> = Mutex::new(Vec::new());
}

/// Called by game adapter to report a discovered signal
#[no_mangle]
pub extern "C" fn discovery_capture(
    event_name: *const c_char,
    payload_json: *const c_char,
    source: *const c_char,
) {
    let name = unsafe { CStr::from_ptr(event_name) }.to_str().unwrap_or("");
    let payload = unsafe { CStr::from_ptr(payload_json) }.to_str().unwrap_or("{}");
    let src = unsafe { CStr::from_ptr(source) }.to_str().unwrap_or("unknown");

    if let Ok(mut queue) = DISCOVERY_QUEUE.lock() {
        queue.push(DiscoveredSignal {
            event_name: name.to_string(),
            payload_json: payload.to_string(),
            source: src.to_string(),
            timestamp_ms: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
        });
    }
}

/// Called by Flutter to drain the discovery queue
#[no_mangle]
pub extern "C" fn discovery_drain() -> *mut c_char {
    let signals = if let Ok(mut queue) = DISCOVERY_QUEUE.lock() {
        std::mem::take(&mut *queue)
    } else {
        Vec::new()
    };

    let json = serde_json::to_string(&signals).unwrap_or_else(|_| "[]".to_string());
    CString::new(json).unwrap().into_raw()
}

/// Called by Flutter to free the returned string
#[no_mangle]
pub extern "C" fn discovery_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}

#[derive(serde::Serialize)]
struct DiscoveredSignal {
    event_name: String,
    payload_json: String,
    source: String,
    timestamp_ms: u64,
}
```

### Flutter-side FFI Polling

```dart
// In NativeFFI class (native_ffi.dart)

/// Drain discovery queue from Rust bridge
List<CapturedSignal> drainDiscoveryQueue() {
  final resultPtr = _discoveryDrain();
  if (resultPtr == nullptr) return [];

  try {
    final json = resultPtr.cast<Utf8>().toDartString();
    final list = jsonDecode(json) as List;

    return list.map((entry) => CapturedSignal(
      eventName: entry['event_name'] as String,
      payload: entry['payload_json'] != '{}'
        ? jsonDecode(entry['payload_json'] as String) as Map<String, dynamic>
        : null,
      source: entry['source'] as String,
      method: InterceptionMethod.eventBus,
      timestamp: DateTime.fromMillisecondsSinceEpoch(entry['timestamp_ms'] as int),
      adapterType: 'rust_ffi',
    )).toList();
  } finally {
    _discoveryFreeString(resultPtr);
  }
}
```

---

## 20. File Structure

### New Files

```
flutter_ui/lib/
├── services/
│   ├── discovery/
│   │   ├── event_sniffer_engine.dart       # Central sniffer processor
│   │   ├── discovery_registry.dart         # Discovered events store
│   │   ├── payload_schema_store.dart       # Payload analysis
│   │   ├── frequency_histogram.dart        # Frequency tracking
│   │   ├── category_inference_engine.dart  # Auto-categorization
│   │   ├── slot_heuristics_engine.dart     # Slot-specific detection
│   │   ├── condition_evaluator.dart        # Runtime condition evaluation
│   │   └── learning_session.dart           # Learning mode session management
│   └── adapters/
│       ├── fluxforge_adapter.dart          # Base adapter contract
│       ├── adapter_registry.dart           # Adapter management
│       ├── pixijs_adapter.dart             # PixiJS slot adapter
│       ├── unity_adapter.dart              # Unity bridge adapter
│       ├── unreal_adapter.dart             # Unreal bridge adapter
│       ├── generic_tcp_adapter.dart        # Generic TCP/WebSocket adapter
│       └── mock_adapter.dart              # Mock adapter for testing/demo
│
├── widgets/
│   └── discovery/
│       ├── event_inspector_panel.dart      # Main inspector UI
│       ├── live_feed_widget.dart           # Real-time event feed
│       ├── discovery_summary_widget.dart   # Category summary table
│       ├── payload_schema_viewer.dart      # Payload field display
│       ├── frequency_chart_widget.dart     # Frequency visualization
│       ├── learning_controls_widget.dart   # Start/Stop learning UI
│       ├── learning_report_widget.dart     # Post-learning report
│       ├── event_promotion_dialog.dart     # Promote event to composite
│       └── condition_editor_widget.dart    # Condition builder UI
│
├── models/
│   └── discovery_models.dart              # CapturedSignal, DiscoveredEvent, etc.
│
├── providers/
│   └── discovery_provider.dart            # ChangeNotifier for discovery state

crates/
├── rf-bridge/src/
│   └── discovery_ffi.rs                   # Rust FFI discovery bridge
│
└── rf-event/src/
    └── discovery.rs                       # Discovery event processing
```

### Modified Files

```
flutter_ui/lib/
├── services/
│   ├── event_registry.dart                # Add discovery event support
│   └── hook_dispatcher.dart               # Add onEventDiscovered hook type
│
├── models/
│   ├── hook_models.dart                   # Add HookType.onEventDiscovered
│   └── slot_audio_events.dart             # Add discovery-related categories
│
├── widgets/lower_zone/
│   ├── slotlab_lower_zone_widget.dart     # Add DISCOVERY sub-tab
│   └── daw_lower_zone_widget.dart         # Add DISCOVERY sub-tab
│
├── screens/
│   └── slot_lab_screen.dart               # Wire discovery to _syncEventToRegistry
│
├── providers/
│   └── middleware_provider.dart            # Add promotedEvents tracking
│
└── services/diagnostics/
    └── diagnostics_service.dart           # Add DiscoveryHealthChecker
```

---

## 21. Implementation Phases

### Phase 1: Core Infrastructure (Foundation)

| Task | File | Description |
|---|---|---|
| P1.1 | `discovery_models.dart` | CapturedSignal, DiscoveredEvent, PayloadSchema models |
| P1.2 | `discovery_registry.dart` | DiscoveryRegistry singleton with persistence |
| P1.3 | `event_sniffer_engine.dart` | Central sniffer with dedup, schema extraction |
| P1.4 | `payload_schema_store.dart` | Payload analysis and schema tracking |
| P1.5 | `frequency_histogram.dart` | Frequency tracking and burst detection |
| P1.6 | `category_inference_engine.dart` | Pattern-based category inference |
| P1.7 | `fluxforge_adapter.dart` | Base adapter contract |
| P1.8 | `adapter_registry.dart` | Adapter management |

### Phase 2: Adapters

| Task | File | Description |
|---|---|---|
| P2.1 | `mock_adapter.dart` | Mock adapter for testing (simulates slot game signals) |
| P2.2 | `generic_tcp_adapter.dart` | TCP/WebSocket adapter for any game engine |
| P2.3 | `pixijs_adapter.dart` | PixiJS slot game adapter with JS injection |
| P2.4 | `unity_adapter.dart` | Unity native plugin bridge |
| P2.5 | `unreal_adapter.dart` | Unreal plugin module bridge |

### Phase 3: Slot Heuristics

| Task | File | Description |
|---|---|---|
| P3.1 | `slot_heuristics_engine.dart` | Heuristic rules engine |
| P3.2 | Rules implementation | Reel stop, symbol land, win, near miss, cascade, etc. |
| P3.3 | Game state tracker | Observable game state reconstruction |

### Phase 4: Learning Mode

| Task | File | Description |
|---|---|---|
| P4.1 | `learning_session.dart` | Session recording and finalization |
| P4.2 | Learning report generation | Analysis, recommendations, stage mapping |
| P4.3 | `learning_controls_widget.dart` | Start/Stop UI |
| P4.4 | `learning_report_widget.dart` | Post-session report display |

### Phase 5: Event Inspector UI

| Task | File | Description |
|---|---|---|
| P5.1 | `event_inspector_panel.dart` | Main panel with live feed + summary |
| P5.2 | `live_feed_widget.dart` | Real-time scrolling event feed |
| P5.3 | `payload_schema_viewer.dart` | Schema field display |
| P5.4 | `frequency_chart_widget.dart` | Histogram visualization |
| P5.5 | `discovery_summary_widget.dart` | Category summary table |
| P5.6 | `event_promotion_dialog.dart` | Promote → SlotCompositeEvent flow |
| P5.7 | `condition_editor_widget.dart` | Visual condition builder |

### Phase 6: Integration

| Task | File | Description |
|---|---|---|
| P6.1 | `condition_evaluator.dart` | Runtime condition evaluation |
| P6.2 | EventRegistry integration | Discovery → stage mapping |
| P6.3 | HookDispatcher integration | Discovery hooks |
| P6.4 | DiagnosticsService integration | Discovery health checker |
| P6.5 | Lower zone tabs | Add DISCOVERY sub-tab to SlotLab + DAW |
| P6.6 | Persistence | Save/load discovered events |

### Phase 7: Rust FFI Bridge

| Task | File | Description |
|---|---|---|
| P7.1 | `discovery_ffi.rs` | Rust FFI discovery exports |
| P7.2 | `discovery.rs` | Rust-side discovery processing |
| P7.3 | NativeFFI integration | Flutter-side polling |

---

## 22. Data Structures

### Complete Type Hierarchy

```
CapturedSignal
├── eventName: String
├── payload: Map<String, dynamic>?
├── source: String
├── method: InterceptionMethod
├── timestamp: DateTime
└── adapterType: String?

DiscoveredEvent
├── eventName: String
├── payload: Map<String, dynamic>?
├── source: String
├── interceptionMethod: InterceptionMethod
├── category: String
├── timestamp: DateTime
├── lastSeenTimestamp: DateTime?
├── frequency: int
└── payloadSchema: PayloadSchema?

PayloadSchema
└── fields: Map<String, PayloadField>
    └── PayloadField
        ├── name: String
        ├── type: PayloadFieldType
        ├── optional: bool
        ├── observedValues: Set<dynamic>
        ├── minValue: double?
        ├── maxValue: double?
        └── occurrences: int

LearningSession
├── id: String
├── startTime: DateTime
├── endTime: DateTime?
├── signals: List<CapturedSignal>
├── adapterType: String
└── status: LearningSessionStatus

LearningReport
├── sessionId: String
├── duration: Duration
├── totalSignals: int
├── uniqueEvents: List<DiscoveredEvent>
├── categorySummary: Map<String, int>
└── recommendations: List<StageRecommendation>

StageRecommendation
├── discoveredEventName: String
├── suggestedStageName: String
├── suggestedCategory: String
├── confidence: double (0.0 - 1.0)
└── frequency: int

FrequencyEntry
├── eventName: String
├── totalCount: int
├── perSecond: double
├── perSpin: double
└── burst: BurstInfo?

BurstInfo
├── eventName: String
├── maxBurstSize: int
└── averageBurstInterval: Duration

FluxForgeAdapter (abstract)
├── name: String
├── engineType: String
├── status: AdapterStatus
├── supportedMethods: Set<InterceptionMethod>
├── activeMethods: Set<InterceptionMethod>
├── attach(): Future<void>
├── detach(): Future<void>
├── onSignalCaptured(callback): void
└── setMethodActive(method, active): void
```

---

## 23. Critical Rules

### NEVER Break These Rules

1. **SINGLE SYNC POINT:** Discovered events sync to `EventRegistry` ONLY through `_syncEventToRegistry()` in `slot_lab_screen.dart`. NEVER add a parallel sync path from `DiscoveryRegistry` directly to `EventRegistry._stageToEvent`.

2. **Audio Thread Safety:** Discovery processing runs on the UI/computation thread. NEVER touch the audio thread from discovery code. Signal capture in Rust uses a lock-free queue (`discovery_ffi.rs`) drained by Flutter.

3. **No Hardcoding:** Category mappings, heuristic thresholds, and tier labels are data-driven. Use `WinTierConfig` for win tiers, `SlotEventCategory` enum for categories.

4. **Deduplication Window:** 16ms window prevents the same signal from being captured twice in the same frame. This is critical for adapters that may fire multiple interception methods for the same game event.

5. **Payload Schema Cap:** Observed values set capped at 100 entries per field to prevent memory bloat on high-cardinality fields.

6. **Learning Session Size:** Learning sessions are limited to 10,000 signals. After that, auto-finalize and start new session.

7. **Discovery Does NOT Replace Manual Authoring:** Discovery is an accelerator, not a replacement. Audio designers can always create events manually in SlotLab/Middleware. Discovery just automates the event identification step.

8. **Adapter Isolation:** Adapters NEVER modify game state. They are pure observers. Interception wrappers MUST call the original function unchanged.

9. **Hook Priority:** Discovery hooks register at priority 50 (below default 100). This ensures manually registered hooks always take precedence over discovery-generated hooks.

10. **Persistence Separation:** `discoveredEvents.json` is separate from `authoringProject.json`. Discovery data is metadata — it informs authoring but does not contain audio assignments.

### Hybrid Detection Model

For maximum reliability, FluxForge combines ALL available detection methods simultaneously:

```
EventBus interception        ─┐
Message bus interception      │
Animation marker extraction   │
State machine observation     ├─→ EventSnifferEngine → Deduplication → DiscoveryRegistry
Audio trigger interception    │
UI interaction capture        │
Runtime value observation     │
Slot heuristics engine       ─┘

Combined accuracy: 95-99% gameplay event discovery
```

---

## 24. Advanced Interception: OpenTelemetry-Inspired Auto-Instrumentation

FluxForge adapters use the same proven auto-instrumentation techniques as OpenTelemetry — the industry standard for runtime observability. This eliminates the need for game developers to write ANY integration code.

### Monkey Patching Architecture

OpenTelemetry auto-instrumentation works by intercepting module loading and wrapping functions at runtime. FluxForge adapters apply the identical technique to game engine APIs:

```
OPENTELEMETRY MODEL                    FLUXFORGE MODEL
────────────────────                    ─────────────────
require('http')                         EventBus.emit()
     │                                       │
Module loader intercepts                Adapter wraps function
     │                                       │
Wraps http.get() with span              Wraps emit() with capture
     │                                       │
Original function called                Original emit() called
     │                                       │
Span recorded to collector              Signal sent to Sniffer
```

### JavaScript Proxy-Based Interception (Zero Modification)

For modern JS game engines, FluxForge uses ES6 `Proxy` + `Reflect` — the most powerful and least invasive interception technique:

```javascript
// FluxForge Deep Interceptor — wraps ANY object tree recursively
class FluxForgeInterceptor {

    static wrapObject(target, path = '') {
        return new Proxy(target, {
            // Trap 1: Property access → recursively wrap child objects
            get(obj, prop, receiver) {
                const value = Reflect.get(obj, prop, receiver);

                // If it's a function, wrap it with an apply trap
                if (typeof value === 'function') {
                    return new Proxy(value, {
                        apply(fn, thisArg, args) {
                            const fullPath = path ? `${path}.${String(prop)}` : String(prop);

                            // Capture BEFORE execution (for timing)
                            const startTime = performance.now();

                            // Call original function
                            const result = Reflect.apply(fn, thisArg, args);

                            // Capture AFTER execution
                            const duration = performance.now() - startTime;

                            FluxForgeSniffer.capture({
                                eventName: fullPath,
                                payload: FluxForgeInterceptor._serializeArgs(args),
                                source: 'ProxyInterceptor',
                                method: 'functionCall',
                                timestamp: performance.now(),
                                metadata: {
                                    duration: duration,
                                    returnType: typeof result,
                                    argCount: args.length,
                                }
                            });

                            return result;
                        }
                    });
                }

                // If it's an object, recursively proxy it
                if (value && typeof value === 'object' && !Array.isArray(value)) {
                    return FluxForgeInterceptor.wrapObject(
                        value,
                        path ? `${path}.${String(prop)}` : String(prop)
                    );
                }

                return value;
            },

            // Trap 2: Property assignment → detect state changes
            set(obj, prop, value, receiver) {
                const oldValue = obj[prop];
                const result = Reflect.set(obj, prop, value, receiver);

                if (oldValue !== value) {
                    FluxForgeSniffer.capture({
                        eventName: `PropertyChanged:${path}.${String(prop)}`,
                        payload: {
                            property: `${path}.${String(prop)}`,
                            oldValue: oldValue,
                            newValue: value,
                            delta: typeof value === 'number' && typeof oldValue === 'number'
                                ? value - oldValue : null,
                        },
                        source: 'ProxyInterceptor',
                        method: 'valueObservation',
                        timestamp: performance.now()
                    });
                }

                return result;
            }
        });
    }

    static _serializeArgs(args) {
        try {
            // Deep-clone safe subset (avoid circular refs, DOM nodes)
            return JSON.parse(JSON.stringify(args, (key, value) => {
                if (value instanceof HTMLElement) return `[HTMLElement:${value.tagName}]`;
                if (value instanceof Function) return `[Function:${value.name}]`;
                if (typeof value === 'symbol') return `[Symbol:${value.toString()}]`;
                return value;
            }));
        } catch {
            return { _serialization_failed: true, argCount: args.length };
        }
    }
}

// Usage: wrap entire game engine object tree
window.GameEngine = FluxForgeInterceptor.wrapObject(window.GameEngine, 'GameEngine');
// Now EVERY function call and property change on GameEngine is captured
```

### Module Loading Interception (Node.js / Electron)

For Electron-based game frameworks:

```javascript
// Intercept require() to wrap modules before game code accesses them
const Module = require('module');
const originalLoad = Module._load;

// Target modules to intercept
const INTERCEPT_TARGETS = [
    'pixi.js', '@pixi/core', 'gsap', 'spine-pixi',
    'howler', 'tone', 'pizzicato',
    './game/EventBus', './game/StateMachine', './game/AudioManager'
];

Module._load = function(request, parent, isMain) {
    const result = originalLoad.call(this, request, parent, isMain);

    if (INTERCEPT_TARGETS.some(t => request.includes(t))) {
        return FluxForgeInterceptor.wrapObject(result, request);
    }

    return result;
};
```

### Adapter Injection Sequence

```
┌───────────────────────────────────────────────────────────────────┐
│                    ADAPTER INJECTION SEQUENCE                      │
│                                                                   │
│  Phase 1: PRE-LOAD (before game scripts execute)                 │
│  ├─ Inject FluxForgeSniffer global                               │
│  ├─ Inject Proxy interceptors for known API surfaces             │
│  ├─ Register module loading hooks (if Node/Electron)             │
│  └─ Start heartbeat timer (adapter → sniffer health check)       │
│                                                                   │
│  Phase 2: DISCOVERY (as game loads and initializes)              │
│  ├─ Detect EventBus pattern (emit/on/off method signatures)      │
│  ├─ Detect State Machine pattern (setState/getState methods)     │
│  ├─ Detect Audio Engine (play/stop/pause method signatures)      │
│  ├─ Detect Animation System (addListener/event handlers)         │
│  └─ Auto-wrap discovered APIs with Proxy interceptors            │
│                                                                   │
│  Phase 3: STEADY STATE (game running)                            │
│  ├─ All intercepted calls forwarded to EventSnifferEngine        │
│  ├─ Deduplication + schema extraction + frequency tracking       │
│  └─ Zero impact on game performance (< 0.1ms per intercept)      │
│                                                                   │
│  Phase 4: DETACH (optional)                                      │
│  ├─ Restore original functions (un-proxy)                        │
│  ├─ Flush remaining captured signals                             │
│  └─ Save session to discoveredEvents.json                        │
└───────────────────────────────────────────────────────────────────┘
```

---

## 25. Wire Protocol: Binary Event Streaming

For adapters that connect to FluxForge over network (TCP/WebSocket), a high-performance binary protocol is used instead of JSON to minimize latency and bandwidth.

### Protocol Selection: MessagePack

| Format | Encode Speed | Decode Speed | Payload Size | Schema Required |
|---|---|---|---|---|
| JSON | 1x baseline | 1x baseline | 100% | No |
| MessagePack | 3-5x faster | 3-5x faster | 50-70% | No |
| Protobuf | 5-10x faster | 5-10x faster | 30-50% | Yes (.proto) |

**Decision:** MessagePack — because it's schema-free (adapters don't need pre-compiled .proto files), 3-5x faster than JSON, and 50-70% smaller payloads. Game developers add no build step.

### Wire Format

```
┌──────────────────────────────────────────────────────────────────┐
│                    FLUXFORGE DISCOVERY PROTOCOL                   │
│                    Version 1.0 — MessagePack                     │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  HEADER (4 bytes)                                                │
│  ┌────────┬────────┬────────────────────┐                        │
│  │ Magic  │Version │ Payload Length     │                        │
│  │ 0xFF42 │ 0x01   │ uint16 (LE)       │                        │
│  └────────┴────────┴────────────────────┘                        │
│                                                                  │
│  PAYLOAD (MessagePack encoded)                                   │
│  {                                                               │
│    "t": 1709812345678,          // timestamp (ms since epoch)    │
│    "e": "ReelStop",             // event name (short key)        │
│    "p": {"reel": 3, "sym": "7"},// payload (nullable)            │
│    "s": "EB",                   // source code (2-char)          │
│    "m": 1                       // method enum (uint8)           │
│  }                                                               │
│                                                                  │
│  SOURCE CODES:                                                   │
│  EB = EventBus, MB = MessageBus, AM = AnimationMarker            │
│  SM = StateMachine, AT = AudioTrigger, UI = UIInteraction        │
│  VO = ValueObservation, HE = Heuristic, PX = ProxyInterceptor   │
│                                                                  │
│  METHOD ENUM:                                                    │
│  0 = eventBus, 1 = messageBus, 2 = animationMarkers             │
│  3 = stateMachine, 4 = audioTriggers, 5 = uiInteraction         │
│  6 = valueObservation, 7 = heuristics, 8 = functionCall         │
│                                                                  │
│  BATCHING:                                                       │
│  Multiple signals per WebSocket frame (array of payloads)        │
│  Flush interval: 16ms (one frame at 60fps)                       │
│  Max batch size: 64 signals per frame                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Dart-side MessagePack Decoder

```dart
class DiscoveryProtocol {
  static const int kMagic = 0xFF42;
  static const int kVersion = 0x01;

  /// Decode a binary WebSocket frame into captured signals
  static List<CapturedSignal> decode(Uint8List data) {
    // Verify header
    if (data.length < 4) return [];
    final magic = data[0] << 8 | data[1];
    if (magic != kMagic) return [];
    final version = data[2];
    if (version != kVersion) return [];

    // Decode MessagePack payload
    final payloadBytes = data.sublist(4);
    final decoded = msgpack.deserialize(payloadBytes);

    if (decoded is List) {
      // Batch: array of signals
      return decoded.map((entry) => _decodeSignal(entry as Map)).toList();
    } else if (decoded is Map) {
      // Single signal
      return [_decodeSignal(decoded)];
    }

    return [];
  }

  static CapturedSignal _decodeSignal(Map entry) {
    return CapturedSignal(
      eventName: entry['e'] as String,
      payload: entry['p'] as Map<String, dynamic>?,
      source: _expandSourceCode(entry['s'] as String),
      method: InterceptionMethod.values[entry['m'] as int],
      timestamp: DateTime.fromMillisecondsSinceEpoch(entry['t'] as int),
    );
  }

  static const _sourceCodes = {
    'EB': 'EventBus', 'MB': 'MessageBus', 'AM': 'AnimationMarker',
    'SM': 'StateMachine', 'AT': 'AudioTrigger', 'UI': 'UIInteraction',
    'VO': 'ValueObservation', 'HE': 'Heuristic', 'PX': 'ProxyInterceptor',
  };

  static String _expandSourceCode(String code) => _sourceCodes[code] ?? code;

  /// Encode a signal for transmission (adapter-side)
  static Uint8List encode(List<CapturedSignal> signals) {
    final batch = signals.map((s) => {
      't': s.timestamp.millisecondsSinceEpoch,
      'e': s.eventName,
      'p': s.payload,
      's': _compressSource(s.source),
      'm': s.method.index,
    }).toList();

    final payload = msgpack.serialize(batch);
    final header = Uint8List(4);
    header[0] = (kMagic >> 8) & 0xFF;
    header[1] = kMagic & 0xFF;
    header[2] = kVersion;
    header[3] = 0; // reserved

    return Uint8List.fromList([...header, ...payload]);
  }

  static String _compressSource(String source) {
    for (final entry in _sourceCodes.entries) {
      if (entry.value == source) return entry.key;
    }
    return source.substring(0, 2).toUpperCase();
  }
}
```

---

## 26. Profiler: Wwise/FMOD Capture Log Parity

FluxForge implements a profiler system that matches Wwise Capture Log and FMOD Studio Profiler capabilities — but goes further by being discovery-aware.

### Wwise Profiler Analysis

Wwise Profiler consists of three views:
- **Capture Log** — records ALL activities from the sound engine: events triggered, when, by which game object, voices used, if sounds didn't fire and why, voice limits reached, memory limits reached
- **Performance Monitor** — CPU, memory, streaming, voice count real-time graphs
- **Advanced Profiler** — per-voice detailed analysis, bus hierarchy visualization

FluxForge replicates ALL of this and adds discovery-specific profiling:

### FluxForge Profiler Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                    FLUXFORGE PROFILER SYSTEM                          │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  CAPTURE LOG (Wwise parity + Discovery extension)               │ │
│  │                                                                  │ │
│  │  Records:                                                        │ │
│  │  [PLAY]  14:23:01.234  REEL_STOP_0    voice:3  bus:reels        │ │
│  │  [PLAY]  14:23:01.256  REEL_STOP_0    voice:4  bus:reels        │ │
│  │  [STOP]  14:23:01.300  BG_MUSIC       voice:1  bus:music fade   │ │
│  │  [SKIP]  14:23:01.312  REEL_STOP_0    REASON: max instances (5) │ │
│  │  [DISC]  14:23:01.400  NEW: CascadeStep  source:Heuristic       │ │
│  │  [WARN]  14:23:01.450  Orphan stage: UNKNOWN_EVENT              │ │
│  │  [HOOK]  14:23:01.500  Hook fired: discovery_Win (50ms)         │ │
│  │  [RTPC]  14:23:01.550  win_ratio: 0.0 → 15.5                   │ │
│  │  [STATE] 14:23:01.600  GameState: Spin → Evaluating             │ │
│  │                                                                  │ │
│  │  Filters: [Events] [Voices] [States] [RTPCs] [Discovery] [Err]  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  PERFORMANCE MONITOR (real-time graphs)                          │ │
│  │                                                                  │ │
│  │  CPU ████████░░░░░░░░  12.3%    Voices ████████████░░  18/24    │ │
│  │  MEM ██████░░░░░░░░░░  8.2MB    Events █████░░░░░░░░░  47       │ │
│  │  DSP █████████░░░░░░░  15.1%    Streams ████░░░░░░░░░  4/16     │ │
│  │  SNF ██░░░░░░░░░░░░░░  0.8%     Disc ██████████████░  23 found │ │
│  │                         ↑                                        │ │
│  │                    Sniffer CPU budget                             │ │
│  │                                                                  │ │
│  │  Timeline: [──────────●───────────────]  14:20 → 14:25          │ │
│  │            spin  stop  win  spin  stop   (event density bars)    │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  ADVANCED PROFILER (per-voice, per-bus analysis)                 │ │
│  │                                                                  │ │
│  │  Voice Pool:                                                     │ │
│  │  ┌────────┬────────┬────────┬─────────┬──────────┬────────────┐ │ │
│  │  │ Voice  │ Event  │ Bus    │ Volume  │ Duration │ Status     │ │ │
│  │  ├────────┼────────┼────────┼─────────┼──────────┼────────────┤ │ │
│  │  │ v001   │ REEL_0 │ reels  │ -3.2dB  │ 0.45s    │ Playing    │ │ │
│  │  │ v002   │ MUSIC  │ music  │ -6.0dB  │ loop     │ Looping    │ │ │
│  │  │ v003   │ WIN    │ wins   │ 0.0dB   │ 2.30s    │ Playing    │ │ │
│  │  │ v004   │ —      │ —      │ —       │ —        │ Available  │ │ │
│  │  └────────┴────────┴────────┴─────────┴──────────┴────────────┘ │ │
│  │                                                                  │ │
│  │  Bus Hierarchy:                                                  │ │
│  │  master ─────────────────────── -0.1dB ████████████████████      │ │
│  │  ├─ music ───────────────────── -6.0dB ████████████░░░░░░       │ │
│  │  ├─ sfx ─────────────────────── -3.0dB ████████████████░░       │ │
│  │  │  ├─ reels ─────────────────── -3.2dB ███████████████░░       │ │
│  │  │  ├─ wins ──────────────────── 0.0dB ████████████████████      │ │
│  │  │  └─ ui ───────────────────── -12.0dB ████████░░░░░░░░       │ │
│  │  └─ anticipation ─────────────── muted ░░░░░░░░░░░░░░░░       │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  DISCOVERY PROFILER (FluxForge exclusive — no Wwise/FMOD equiv) │ │
│  │                                                                  │ │
│  │  Signal Rate:  847/min  │  Dedup Rate: 12.3%  │  CPU: 0.8%      │ │
│  │  Unique Events: 23     │  Mapped: 7/23       │  Ignored: 2      │ │
│  │                                                                  │ │
│  │  Interception Method Breakdown:                                  │ │
│  │  EventBus ████████████████████████ 62%  (524 signals)            │ │
│  │  Heuristic ███████████░░░░░░░░░░░ 28%  (237 signals)            │ │
│  │  StateMachine █████░░░░░░░░░░░░░░  6%   (51 signals)            │ │
│  │  UIInteraction ██░░░░░░░░░░░░░░░░  3%   (25 signals)            │ │
│  │  ValueObserv █░░░░░░░░░░░░░░░░░░  1%   (10 signals)            │ │
│  │                                                                  │ │
│  │  Adapter Health: PixiJS ● Connected (latency: 0.3ms)            │ │
│  │  Last signal: 0.02s ago  │  Queue depth: 0  │  Dropped: 0       │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

### Profiler Data Model

```dart
/// Single profiler log entry (Capture Log row)
class ProfilerEntry {
  final DateTime timestamp;
  final ProfilerEntryType type;
  final String eventName;
  final String? stageName;
  final String? busName;
  final int? voiceId;
  final double? volumeDb;
  final double? durationSeconds;
  final String? reason;             // For SKIP entries: "max instances", "cooldown", etc.
  final String? discoverySource;    // For DISC entries: adapter source
  final Map<String, dynamic>? metadata;

  const ProfilerEntry({
    required this.timestamp,
    required this.type,
    required this.eventName,
    this.stageName,
    this.busName,
    this.voiceId,
    this.volumeDb,
    this.durationSeconds,
    this.reason,
    this.discoverySource,
    this.metadata,
  });
}

enum ProfilerEntryType {
  play,       // Audio started playing
  stop,       // Audio stopped
  skip,       // Audio skipped (max instances, cooldown, etc.)
  discovery,  // New event discovered by sniffer
  warning,    // Orphan stage, missing audio, etc.
  hook,       // Hook callback executed
  rtpc,       // RTPC value changed
  state,      // State/Switch changed
  error,      // Error condition
}

/// Performance snapshot (sampled at 10Hz)
class PerformanceSnapshot {
  final DateTime timestamp;
  final double cpuPercent;
  final double dspCpuPercent;
  final double snifferCpuPercent;     // Discovery engine CPU cost
  final int memoryBytes;
  final int activeVoices;
  final int maxVoices;
  final int activeStreams;
  final int maxStreams;
  final int discoveredEventCount;
  final int signalRate;               // Signals per second
  final double deduplicationRate;     // % signals deduplicated
  final double adapterLatencyMs;      // Adapter → Sniffer latency
}
```

---

## 27. ML-Powered Event Pattern Recognition

Beyond rule-based heuristics, FluxForge implements lightweight machine learning for pattern recognition on event sequences.

### Sequence Pattern Detector

```dart
class SequencePatternDetector {
  /// Detects repeating event sequences (e.g., spin cycles)
  /// Uses suffix array approach for O(n log n) pattern detection

  final List<String> _eventHistory = [];
  final Map<String, SequencePattern> _detectedPatterns = {};
  static const int _maxHistorySize = 10000;
  static const int _minPatternOccurrences = 3;

  void addEvent(String eventName) {
    _eventHistory.add(eventName);
    if (_eventHistory.length > _maxHistorySize) {
      _eventHistory.removeAt(0);
    }

    // Detect patterns every 100 events
    if (_eventHistory.length % 100 == 0) {
      _detectPatterns();
    }
  }

  void _detectPatterns() {
    // Find repeating subsequences of length 3-20
    for (int len = 3; len <= 20 && len <= _eventHistory.length ~/ 3; len++) {
      final patternCounts = <String, int>{};

      for (int i = 0; i <= _eventHistory.length - len; i++) {
        final pattern = _eventHistory.sublist(i, i + len).join('→');
        patternCounts[pattern] = (patternCounts[pattern] ?? 0) + 1;
      }

      for (final entry in patternCounts.entries) {
        if (entry.value >= _minPatternOccurrences) {
          _detectedPatterns[entry.key] = SequencePattern(
            sequence: entry.key.split('→'),
            occurrences: entry.value,
            length: len,
          );
        }
      }
    }
  }

  /// Get detected game cycles (e.g., SpinStart → ReelStop×5 → Win → Idle)
  List<SequencePattern> get gameCycles =>
    _detectedPatterns.values
      .where((p) => p.length >= 5 && p.occurrences >= 3)
      .toList()
    ..sort((a, b) => b.occurrences.compareTo(a.occurrences));
}

class SequencePattern {
  final List<String> sequence;
  final int occurrences;
  final int length;

  const SequencePattern({
    required this.sequence,
    required this.occurrences,
    required this.length,
  });

  /// Human-readable pattern name
  String get displayName {
    if (sequence.contains('SpinStart') && sequence.contains('ReelStop')) {
      return 'Spin Cycle (${occurrences}x)';
    }
    if (sequence.contains('CascadeStep')) {
      return 'Cascade Sequence (${occurrences}x)';
    }
    return 'Pattern: ${sequence.first}...${sequence.last} (${occurrences}x)';
  }
}
```

### Anomaly Detection

```dart
class AnomalyDetector {
  /// Detects unusual event patterns that may indicate bugs or edge cases

  final Map<String, _EventStats> _stats = {};

  void recordEvent(String eventName, DateTime timestamp) {
    final stats = _stats.putIfAbsent(eventName, () => _EventStats());
    stats.record(timestamp);
  }

  /// Detect anomalies in event frequency
  List<Anomaly> detectAnomalies() {
    final anomalies = <Anomaly>[];

    for (final entry in _stats.entries) {
      final stats = entry.value;

      // Anomaly: Event stopped firing (was active, now silent for > 10s)
      if (stats.wasActive && stats.silentDuration.inSeconds > 10) {
        anomalies.add(Anomaly(
          type: AnomalyType.eventStopped,
          eventName: entry.key,
          message: '${entry.key} stopped firing (silent for ${stats.silentDuration.inSeconds}s)',
          severity: AnomalySeverity.warning,
        ));
      }

      // Anomaly: Sudden frequency spike (>3x normal rate)
      if (stats.currentRate > stats.averageRate * 3 && stats.averageRate > 0) {
        anomalies.add(Anomaly(
          type: AnomalyType.frequencySpike,
          eventName: entry.key,
          message: '${entry.key} frequency spike: ${stats.currentRate.toStringAsFixed(1)}/s (avg: ${stats.averageRate.toStringAsFixed(1)}/s)',
          severity: AnomalySeverity.info,
        ));
      }

      // Anomaly: Event fires without expected predecessor
      // (e.g., WinPresent without prior SpinStart)
      if (stats.missingPredecessorCount > 3) {
        anomalies.add(Anomaly(
          type: AnomalyType.missingPredecessor,
          eventName: entry.key,
          message: '${entry.key} fires without expected predecessor ${stats.expectedPredecessor}',
          severity: AnomalySeverity.warning,
        ));
      }
    }

    return anomalies;
  }
}

enum AnomalyType {
  eventStopped,         // Event was active but stopped
  frequencySpike,       // Sudden increase in frequency
  frequencyDrop,        // Sudden decrease in frequency
  missingPredecessor,   // Expected sequence broken
  duplicateDetection,   // Same event from multiple sources
  payloadAbnormality,   // Payload values outside observed range
}

enum AnomalySeverity { info, warning, error }

class Anomaly {
  final AnomalyType type;
  final String eventName;
  final String message;
  final AnomalySeverity severity;

  const Anomaly({
    required this.type,
    required this.eventName,
    required this.message,
    required this.severity,
  });
}
```

### Event Correlation Matrix

Automatically discovers which events tend to fire together or in sequence:

```dart
class EventCorrelationMatrix {
  /// Tracks which events fire within a time window of each other
  /// Builds a correlation graph: "ReelStop always follows SpinStart within 2s"

  final Map<String, Map<String, _CorrelationEntry>> _matrix = {};
  static const Duration _correlationWindow = Duration(seconds: 5);
  final List<_TimedEvent> _recentEvents = [];

  void recordEvent(String eventName, DateTime timestamp) {
    final timedEvent = _TimedEvent(eventName, timestamp);
    _recentEvents.add(timedEvent);

    // Correlate with recent events within window
    for (final recent in _recentEvents) {
      if (timestamp.difference(recent.timestamp) > _correlationWindow) continue;
      if (recent.eventName == eventName) continue;

      // Record: eventName follows recent.eventName
      _matrix
        .putIfAbsent(recent.eventName, () => {})
        .putIfAbsent(eventName, () => _CorrelationEntry())
        ..count++;

      final delay = timestamp.difference(recent.timestamp);
      _matrix[recent.eventName]![eventName]!.addDelay(delay);
    }

    // Cleanup old events
    _recentEvents.removeWhere(
      (e) => timestamp.difference(e.timestamp) > _correlationWindow * 2
    );
  }

  /// Get strongly correlated event pairs
  List<EventCorrelation> getCorrelations({double minConfidence = 0.8}) {
    final results = <EventCorrelation>[];

    for (final fromEntry in _matrix.entries) {
      final fromEvent = fromEntry.key;
      final totalFromCount = _matrix[fromEvent]?.values
        .fold<int>(0, (sum, e) => sum + e.count) ?? 0;

      for (final toEntry in fromEntry.value.entries) {
        final toEvent = toEntry.key;
        final correlation = toEntry.value;
        final confidence = totalFromCount > 0
          ? correlation.count / totalFromCount
          : 0.0;

        if (confidence >= minConfidence && correlation.count >= 5) {
          results.add(EventCorrelation(
            fromEvent: fromEvent,
            toEvent: toEvent,
            confidence: confidence,
            averageDelay: correlation.averageDelay,
            occurrences: correlation.count,
          ));
        }
      }
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results;
  }
}

class EventCorrelation {
  final String fromEvent;
  final String toEvent;
  final double confidence;          // 0.0-1.0
  final Duration averageDelay;
  final int occurrences;

  const EventCorrelation({
    required this.fromEvent,
    required this.toEvent,
    required this.confidence,
    required this.averageDelay,
    required this.occurrences,
  });

  String get displayName =>
    '$fromEvent → $toEvent (${(confidence * 100).toInt()}% conf, ${averageDelay.inMilliseconds}ms avg)';
}
```

---

## 28. Session Replay System

FluxForge can record complete game sessions and replay the event stream for offline authoring.

### Recording

```dart
class SessionRecorder {
  final List<CapturedSignal> _signals = [];
  DateTime? _startTime;
  DateTime? _endTime;
  bool _isRecording = false;

  void startRecording() {
    _signals.clear();
    _startTime = DateTime.now();
    _isRecording = true;
  }

  void recordSignal(CapturedSignal signal) {
    if (!_isRecording) return;
    _signals.add(signal);
  }

  SessionRecording stopRecording() {
    _endTime = DateTime.now();
    _isRecording = false;
    return SessionRecording(
      signals: List.unmodifiable(_signals),
      startTime: _startTime!,
      endTime: _endTime!,
    );
  }
}
```

### Replay (Offline Authoring Mode)

```dart
class SessionReplayer {
  /// Replays a recorded session at original speed or accelerated
  /// Feeds signals into EventSnifferEngine exactly as if adapter was live

  SessionRecording? _recording;
  double _playbackSpeed = 1.0;
  int _currentIndex = 0;
  Timer? _replayTimer;

  void load(SessionRecording recording) {
    _recording = recording;
    _currentIndex = 0;
  }

  void play({double speed = 1.0}) {
    _playbackSpeed = speed;
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_recording == null || _currentIndex >= _recording!.signals.length) return;

    final current = _recording!.signals[_currentIndex];
    final next = _currentIndex + 1 < _recording!.signals.length
      ? _recording!.signals[_currentIndex + 1]
      : null;

    // Feed signal to sniffer
    EventSnifferEngine.instance.capture(current);
    _currentIndex++;

    if (next != null) {
      final delay = next.timestamp.difference(current.timestamp);
      final adjustedDelay = Duration(
        microseconds: (delay.inMicroseconds / _playbackSpeed).round()
      );
      _replayTimer = Timer(adjustedDelay, _scheduleNext);
    }
  }

  void pause() => _replayTimer?.cancel();
  void seekTo(int index) => _currentIndex = index.clamp(0, _recording!.signals.length - 1);
  void setSpeed(double speed) => _playbackSpeed = speed;
}

class SessionRecording {
  final List<CapturedSignal> signals;
  final DateTime startTime;
  final DateTime endTime;

  Duration get duration => endTime.difference(startTime);
  int get signalCount => signals.length;

  const SessionRecording({
    required this.signals,
    required this.startTime,
    required this.endTime,
  });

  /// Save to file (MessagePack binary for efficiency)
  Future<Uint8List> serialize() async {
    return DiscoveryProtocol.encode(signals);
  }

  /// Load from file
  static Future<SessionRecording> deserialize(Uint8List data) async {
    final signals = DiscoveryProtocol.decode(data);
    return SessionRecording(
      signals: signals,
      startTime: signals.first.timestamp,
      endTime: signals.last.timestamp,
    );
  }
}
```

### Replay use case: Audio designer receives a session recording from QA → loads in FluxForge → replays at 2x speed → attaches audio to discovered events → all without needing a running game instance.

---

## 29. Security & Sandboxing

Adapter code runs in the game runtime and must be carefully sandboxed.

### Security Rules

1. **Read-only observation:** Adapters NEVER modify game state, DOM, or game object properties. They only READ through Proxy get traps and function call interception. The original function is ALWAYS called unchanged.

2. **No network access from adapter:** Adapter code does NOT make network requests. It only writes to a local SharedArrayBuffer or WebSocket connected to localhost FluxForge.

3. **Error isolation:** Adapter errors NEVER propagate to game code. All interceptor wrappers use try/catch with silent error swallowing:

```javascript
EventBus.emit = function(eventName, payload) {
    try {
        FluxForgeSniffer.capture(eventName, payload);
    } catch (e) {
        // NEVER let FluxForge errors affect game
    }
    return originalEmit.call(this, eventName, payload);
};
```

4. **Performance budget:** Adapter capture overhead MUST be < 0.1ms per signal. If accumulated adapter CPU exceeds 1% of frame budget (16.67ms at 60fps), adapter auto-throttles by increasing deduplication window.

5. **Memory cap:** Adapter-side buffer limited to 1MB. If exceeded, oldest signals dropped (FIFO).

6. **Payload sanitization:** Payloads are deep-cloned before transmission. Circular references are replaced with `[Circular]`. Functions replaced with `[Function:name]`. DOM nodes replaced with `[HTMLElement:tagName]`. This prevents memory leaks from adapter holding references to game objects.

7. **Consent marker:** Adapter injection ONLY proceeds if game runtime sets `window.__FLUXFORGE_ADAPTER_ALLOWED = true`. This prevents unauthorized instrumentation of production builds.

### Performance Budget Enforcement

```dart
class PerformanceBudget {
  static const double kMaxSnifferCpuPercent = 1.0;     // Max 1% CPU for sniffer
  static const double kMaxAdapterLatencyMs = 0.1;      // Max 0.1ms per capture
  static const int kMaxSignalsPerSecond = 5000;         // Throttle above this
  static const int kMaxMemoryBytes = 10 * 1024 * 1024;  // 10MB max for discovery

  double _currentCpuPercent = 0;
  int _signalsThisSecond = 0;
  DateTime _secondStart = DateTime.now();

  /// Check if capture should proceed or be throttled
  bool shouldCapture() {
    final now = DateTime.now();
    if (now.difference(_secondStart).inSeconds >= 1) {
      _signalsThisSecond = 0;
      _secondStart = now;
    }

    _signalsThisSecond++;

    if (_signalsThisSecond > kMaxSignalsPerSecond) return false;
    if (_currentCpuPercent > kMaxSnifferCpuPercent) return false;

    return true;
  }
}
```

---

## 30. Export/Import: Cross-Tool Compatibility

FluxForge can export discovered events in formats compatible with Wwise and FMOD for studios that use multiple tools.

### Wwise WAQL-Compatible Export

```json
{
  "WwiseDocument": {
    "Events": [
      {
        "Name": "SpinStart",
        "Notes": "Auto-discovered by FluxForge (source: EventBus, freq: 47/session)",
        "Actions": [
          {
            "ActionType": 1,
            "Target": {
              "ObjectPath": "\\Actor-Mixer Hierarchy\\SFX\\SpinStart_SFX"
            }
          }
        ]
      },
      {
        "Name": "ReelStop",
        "Notes": "Auto-discovered by FluxForge (source: EventBus, freq: 141/session)",
        "Actions": [
          {
            "ActionType": 1,
            "Target": {
              "ObjectPath": "\\Actor-Mixer Hierarchy\\SFX\\ReelStop_SFX"
            }
          }
        ]
      }
    ],
    "GameParameters": [
      {
        "Name": "ReelIndex",
        "Min": 0,
        "Max": 4,
        "Notes": "Discovered from ReelStop payload field 'reel' (range: 0-4)"
      },
      {
        "Name": "WinAmount",
        "Min": 0,
        "Max": 10000,
        "Notes": "Discovered from Win payload field 'amount'"
      }
    ],
    "StateGroups": [
      {
        "Name": "GameState",
        "States": ["Idle", "Spin", "Stopping", "Evaluating", "Win", "NoWin", "Feature"],
        "Notes": "Discovered from StateMachine observation"
      }
    ]
  }
}
```

### FMOD Bank Definition Export

```json
{
  "FMODExport": {
    "Events": [
      {
        "path": "event:/SFX/SpinStart",
        "guid": "auto-generated",
        "notes": "FluxForge discovered: EventBus, 47 occurrences"
      },
      {
        "path": "event:/SFX/ReelStop",
        "guid": "auto-generated",
        "parameters": [
          { "name": "ReelIndex", "min": 0, "max": 4, "type": "continuous" }
        ]
      }
    ],
    "Parameters": [
      {
        "name": "WinRatio",
        "min": 0,
        "max": 100,
        "type": "labeled",
        "labels": { "0": "NoWin", "2": "Small", "10": "Big", "50": "Mega" }
      }
    ],
    "Banks": [
      {
        "name": "SlotGame_Discovery",
        "events": ["event:/SFX/SpinStart", "event:/SFX/ReelStop"]
      }
    ]
  }
}
```

### FluxForge Discovery Exchange Format (FDXF)

Open standard for sharing discovered event libraries between FluxForge instances or with third-party tools:

```json
{
  "fdxf_version": "1.0",
  "generator": "FluxForge Studio 2.0",
  "game_title": "Book of Ra Deluxe",
  "adapter_type": "pixijs",
  "discovery_date": "2026-03-07",
  "session_count": 3,
  "total_signals_analyzed": 2541,

  "events": [
    {
      "name": "ReelStop",
      "category": "reelStop",
      "sources": ["EventBus", "AnimationMarker"],
      "frequency": {
        "total": 141,
        "per_spin": 5.0,
        "burst_size": 5,
        "burst_interval_ms": 200
      },
      "payload_schema": {
        "reel": { "type": "integer", "min": 0, "max": 4, "required": true },
        "symbol": { "type": "string", "required": false, "values": ["cherry","bar","seven","scatter","wild"] }
      },
      "correlations": [
        { "follows": "SpinStart", "confidence": 1.0, "delay_ms": 1500 },
        { "precedes": "SymbolLand", "confidence": 0.95, "delay_ms": 50 }
      ],
      "suggested_stages": ["REEL_STOP_0", "REEL_STOP_1", "REEL_STOP_2", "REEL_STOP_3", "REEL_STOP_4"],
      "suggested_bus": "reels",
      "suggested_container": "sequence"
    }
  ],

  "game_cycles": [
    {
      "name": "Base Game Spin",
      "sequence": ["SpinStart", "ReelStop×5", "SymbolLand×15", "WinEvaluate", "WinPresent|NoWin"],
      "average_duration_ms": 4500,
      "occurrences": 47
    }
  ],

  "state_machine": {
    "states": ["Idle", "Spin", "Stopping", "Evaluating", "Win", "NoWin", "Feature", "Bonus"],
    "transitions": [
      { "from": "Idle", "to": "Spin", "trigger": "SpinStart" },
      { "from": "Spin", "to": "Stopping", "trigger": "AllReelsStopped" },
      { "from": "Stopping", "to": "Evaluating", "trigger": "GridSettled" },
      { "from": "Evaluating", "to": "Win", "trigger": "WinDetected", "condition": "winAmount > 0" },
      { "from": "Evaluating", "to": "NoWin", "trigger": "NoWinDetected", "condition": "winAmount == 0" }
    ]
  }
}
```

---

## 31. Multi-Adapter Concurrent Connection

FluxForge supports connecting multiple adapters simultaneously for complex game architectures.

### Use Cases

| Scenario | Adapters Active | Example |
|---|---|---|
| Slot game with separate audio engine | PixiJS + AudioTrigger | Intercept game events from PixiJS, intercept existing audio calls separately |
| Unity game with custom networking | Unity + Generic TCP | Intercept Unity events + intercept custom network messages |
| Electron-based game | Module Loader + DOM | Intercept Node.js modules + intercept browser DOM events |
| A/B testing | Mock + PixiJS | Replay recorded session alongside live game for comparison |

### Concurrent Adapter Manager

```dart
class ConcurrentAdapterManager {
  final Map<String, FluxForgeAdapter> _activeAdapters = {};

  /// Attach multiple adapters simultaneously
  Future<void> attachAll(List<FluxForgeAdapter> adapters) async {
    for (final adapter in adapters) {
      try {
        await adapter.attach();
        if (adapter.status == AdapterStatus.attached) {
          _activeAdapters[adapter.engineType] = adapter;
          adapter.onSignalCaptured((signal) {
            // Tag signal with adapter source
            EventSnifferEngine.instance.capture(CapturedSignal(
              eventName: signal.eventName,
              payload: signal.payload,
              source: signal.source,
              method: signal.method,
              timestamp: signal.timestamp,
              adapterType: adapter.engineType,
            ));
          });
        }
      } catch (e) {
        // Log error, continue with other adapters
      }
    }
  }

  /// Cross-adapter deduplication
  /// If EventBus AND AnimationMarker both fire for same game event,
  /// keep only the earlier one (within 16ms window)
  // Handled by EventSnifferEngine._deduplicationWindow
}
```

---

## 32. Performance Characteristics

### Benchmarks (Target)

| Metric | Target | Budget |
|---|---|---|
| Adapter capture latency | < 0.1ms per signal | 0.6% of frame budget |
| Sniffer processing | < 0.5ms per signal | 3% of frame budget |
| Schema extraction | < 0.2ms per payload | 1.2% of frame budget |
| Deduplication lookup | < 0.01ms (HashMap) | negligible |
| Category inference | < 0.05ms (pattern match) | negligible |
| Wire protocol encode | < 0.1ms per batch (MessagePack) | 0.6% of frame budget |
| Wire protocol decode | < 0.1ms per batch (MessagePack) | 0.6% of frame budget |
| Total discovery CPU | < 1% of frame budget | HARD LIMIT |
| Memory (discovery state) | < 10MB | HARD LIMIT |
| WebSocket latency | < 1ms (localhost) | — |
| Learning session save | < 500ms for 10K signals | — |

### Scaling

| Signal Rate | Behavior |
|---|---|
| 0-1000/sec | Normal operation, all signals processed |
| 1000-5000/sec | Deduplication window doubles (32ms) |
| 5000-10000/sec | Payload schema extraction disabled (CPU saving) |
| >10000/sec | Adapter auto-throttles, sampling mode (capture every Nth) |

### Result

FluxForge becomes not only an audio middleware but a **runtime gameplay observer**.

Audio systems are authored independently from engine event implementation. The audio designer never waits for the developer. The developer never writes audio integration code. FluxForge discovers everything automatically.

**Zero developer integration overhead. Infinite audio design freedom.**
