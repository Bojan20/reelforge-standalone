# P3 Advanced Features — Architecture Documentation

**Date:** 2026-01-22
**Status:** ✅ ALL COMPLETE (P3.1-P3.14)

---

## Overview

P3 features focus on professional-grade sound design and live integration capabilities:

| ID | Feature | Category | Impact |
|----|---------|----------|--------|
| P3.1-4 | Performance Polish | DSP | Minor speedups |
| P3.5-7 | Documentation | Docs | Developer experience |
| P3.8-9 | Architecture | Code | Maintainability |
| P3.10 | RTPC Macro System | Sound Design | Multi-parameter control |
| P3.11 | Preset Morphing | Sound Design | Dynamic sound evolution |
| P3.12 | DSP Profiler | Diagnostics | Real-time monitoring |
| P3.13 | Live WebSocket | Integration | Engine communication |
| P3.14 | Routing Matrix UI | Visualization | Visual routing |

---

## P3.10: RTPC Macro System

### Purpose

Group multiple RTPC bindings under a single "macro" knob. Allows sound designers to:
- Control multiple parameters with one fader
- Create complex, coordinated parameter changes
- Build reusable control templates

### Architecture

```
┌─────────────────────────────────────────────────┐
│                  RtpcMacro                       │
│  name: "Tension"                                │
│  range: 0.0 - 1.0                               │
│  currentValue: 0.5                              │
│                                                  │
│  ┌─────────────────────────────────────────┐   │
│  │ RtpcMacroBinding[]                      │   │
│  │ ┌─────────────────────────────────┐     │   │
│  │ │ target: highPassFilter          │     │   │
│  │ │ curve: exponential              │     │   │
│  │ │ inverted: false                 │     │   │
│  │ └─────────────────────────────────┘     │   │
│  │ ┌─────────────────────────────────┐     │   │
│  │ │ target: reverbWetDry            │     │   │
│  │ │ curve: linear                   │     │   │
│  │ │ inverted: true                  │     │   │
│  │ └─────────────────────────────────┘     │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
              │
              ▼ evaluate()
┌─────────────────────────────────────────────────┐
│ Map<RtpcTargetParameter, double>                │
│ {                                               │
│   highPassFilter: 0.7071,  // exponential(0.5) │
│   reverbWetDry: 0.5,       // inverted linear  │
│ }                                               │
└─────────────────────────────────────────────────┘
```

### Data Models

**Location:** `flutter_ui/lib/models/middleware_models.dart`

```dart
class RtpcMacro {
  final int id;
  final String name;
  final String description;
  final double min;        // Default: 0.0
  final double max;        // Default: 1.0
  final double currentValue;
  final List<RtpcMacroBinding> bindings;
  final Color color;
  final bool enabled;

  double get normalizedValue =>
    (currentValue - min) / (max - min);

  Map<RtpcTargetParameter, double> evaluate() {
    if (!enabled) return {};
    final normalized = normalizedValue;
    final results = <RtpcTargetParameter, double>{};
    for (final binding in bindings) {
      if (binding.enabled) {
        results[binding.target] = binding.evaluate(normalized);
      }
    }
    return results;
  }
}

class RtpcMacroBinding {
  final int id;
  final RtpcTargetParameter target;
  final int? targetBusId;      // If bus-specific
  final int? targetEventId;    // If event-specific
  final RtpcCurve curve;
  final bool inverted;
  final bool enabled;

  double evaluate(double normalizedMacroValue) {
    final inputValue = inverted
      ? (1.0 - normalizedMacroValue)
      : normalizedMacroValue;
    return curve.evaluate(inputValue);
  }
}
```

### Provider API

**Location:** `flutter_ui/lib/providers/subsystems/rtpc_system_provider.dart`

```dart
// Create
RtpcMacro createMacro({
  required String name,
  String description = '',
  double min = 0.0,
  double max = 1.0,
  double initialValue = 0.5,
  List<RtpcMacroBinding> bindings = const [],
  Color? color,
});

// Control
void setMacroValue(int macroId, double value, {int interpolationMs = 0});
void addMacroBinding(int macroId, RtpcMacroBinding binding);
void removeMacroBinding(int macroId, int bindingId);
void updateMacro(int macroId, RtpcMacro updatedMacro);
void deleteMacro(int macroId);

// Query
RtpcMacro? getMacro(int macroId);
List<RtpcMacro> get allMacros;

// Serialization
List<Map<String, dynamic>> macrosToJson();
void macrosFromJson(List<dynamic> json);
```

### Use Cases

1. **Tension Macro**: HPF + Reverb + Pitch shift coordinated
2. **Energy Macro**: Volume + Compression + Saturation
3. **Space Macro**: Reverb + Delay + Width

---

## P3.11: Preset Morphing

### Purpose

Smoothly interpolate between two audio presets with per-parameter curve control.

### Architecture

```
┌─────────────────────────────────────────────────┐
│                  PresetMorph                     │
│  presetA: "Calm"    presetB: "Intense"          │
│  position: 0.0 ◄────────────────► 1.0           │
│                                                  │
│  ┌─────────────────────────────────────────┐   │
│  │ MorphParameter[]                        │   │
│  │                                          │   │
│  │ volume:    [0.5] ──linear──► [0.9]      │   │
│  │ hpFilter:  [20] ──easeIn──► [500]       │   │
│  │ reverb:    [0.3] ──sCurve──► [0.8]      │   │
│  │ attack:    [10] ──easeOut──► [1]        │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Morph Curves

**Location:** `flutter_ui/lib/models/middleware_models.dart`

```dart
enum MorphCurve {
  linear,       // t
  easeIn,       // t²
  easeOut,      // 1-(1-t)²
  easeInOut,    // Smoothstep
  exponential,  // 2^(10t-10)
  logarithmic,  // log₂(1+t)
  sCurve,       // Hermite interpolation
  step;         // 0 if t<0.5, else 1

  double apply(double t) {
    t = t.clamp(0.0, 1.0);
    switch (this) {
      case MorphCurve.linear:
        return t;
      case MorphCurve.easeIn:
        return t * t;
      case MorphCurve.easeOut:
        return 1.0 - (1.0 - t) * (1.0 - t);
      case MorphCurve.easeInOut:
        return t < 0.5
          ? 2.0 * t * t
          : 1.0 - math.pow(-2.0 * t + 2.0, 2).toDouble() / 2.0;
      case MorphCurve.exponential:
        return t == 0 ? 0.0 : math.pow(2, 10 * t - 10).toDouble();
      case MorphCurve.logarithmic:
        return math.log(1.0 + t) / math.ln2;
      case MorphCurve.sCurve:
        return t * t * (3.0 - 2.0 * t);
      case MorphCurve.step:
        return t < 0.5 ? 0.0 : 1.0;
    }
  }
}
```

### Data Models

```dart
class MorphParameter {
  final String name;
  final RtpcTargetParameter target;
  final double startValue;    // Value at position 0.0
  final double endValue;      // Value at position 1.0
  final MorphCurve curve;
  final bool enabled;

  double valueAt(double t) {
    if (!enabled) return startValue;
    final curved = curve.apply(t);
    return startValue + (endValue - startValue) * curved;
  }
}

class PresetMorph {
  final int id;
  final String name;
  final String presetA;
  final String presetB;
  final List<MorphParameter> parameters;
  final double position;       // 0.0 = A, 1.0 = B
  final MorphCurve globalCurve;
  final bool enabled;

  /// Factory: Volume crossfade between presets
  factory PresetMorph.volumeCrossfade({
    required String name,
    required String presetA,
    required String presetB,
  });

  /// Factory: Filter sweep effect
  factory PresetMorph.filterSweep({
    required String name,
    double startHz = 20.0,
    double endHz = 20000.0,
  });

  /// Factory: Tension builder (multiple coordinated params)
  factory PresetMorph.tensionBuilder({
    required String name,
  });
}
```

### Provider API

```dart
// Create
PresetMorph createMorph({
  required String name,
  required String presetA,
  required String presetB,
  List<MorphParameter> parameters = const [],
  MorphCurve globalCurve = MorphCurve.linear,
});

// Control
void setMorphPosition(int morphId, double position);
void addMorphParameter(int morphId, MorphParameter parameter);
void removeMorphParameter(int morphId, String parameterName);
void updateMorph(int morphId, PresetMorph updatedMorph);
void deleteMorph(int morphId);

// Query
PresetMorph? getMorph(int morphId);
List<PresetMorph> get allMorphs;
Map<RtpcTargetParameter, double> evaluateMorph(int morphId);

// Serialization
List<Map<String, dynamic>> morphsToJson();
void morphsFromJson(List<dynamic> json);
```

---

## P3.12: DSP Profiler Panel

### Purpose

Real-time monitoring of DSP load with stage-by-stage breakdown.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    DspProfilerPanel                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │     LOAD: 23.4%    [████████░░░░░░░░░░░] OK        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Load History (last 100 samples)                    │   │
│  │  ▁▂▃▄▅▆▇██▇▆▅▄▃▂▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇██          │   │
│  │  ─────────────────────────────────────── 90% warn  │   │
│  │  ─────────────────────────────────────── 100%      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Stage Breakdown (μs)                               │   │
│  │  IN:  [██░░░░] 45 μs                               │   │
│  │  MIX: [████░░] 89 μs                               │   │
│  │  FX:  [██████] 156 μs                              │   │
│  │  MTR: [█░░░░░] 23 μs                               │   │
│  │  OUT: [█░░░░░] 12 μs                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Stats: avg=22.1% min=18.3% max=31.2% overloads=0        │
│                                                              │
│  [Reset] [Pause]                                            │
└─────────────────────────────────────────────────────────────┘
```

### Data Models

**Location:** `flutter_ui/lib/models/advanced_middleware_models.dart`

```dart
enum DspStage {
  input,    // Audio I/O, buffer copy
  mixing,   // Track/bus summation
  effects,  // DSP processors
  metering, // Level analysis
  output,   // Final output
  total;    // Sum of all
}

class DspTimingSample {
  final DateTime timestamp;
  final Map<DspStage, double> stageTimingsUs;
  final int blockSize;
  final double sampleRate;

  double get totalUs => stageTimingsUs[DspStage.total] ?? 0.0;
  double get availableUs => (blockSize / sampleRate) * 1_000_000;
  double get loadPercent => (totalUs / availableUs * 100).clamp(0.0, 100.0);
  bool get isOverloaded => loadPercent > 90;
}

class DspProfilerStats {
  final double averageLoad;
  final double minLoad;
  final double maxLoad;
  final int totalSamples;
  final int overloadCount;
  final Map<DspStage, double> averageStageTimings;
}

class DspProfiler {
  final int maxSamples;
  final List<DspTimingSample> _samples = [];

  void record({
    required Map<DspStage, double> stageTimingsUs,
    required int blockSize,
    required double sampleRate,
  });

  DspProfilerStats getStats();
  List<double> getLoadHistory({int count = 100});
  double get currentLoad;
  DspTimingSample? get lastSample;

  void reset();
  void simulateSample({double baseLoad = 15.0});
}
```

### Widget Implementation

**Location:** `flutter_ui/lib/widgets/middleware/dsp_profiler_panel.dart`

Key components:
- `_LoadGraphPainter`: CustomPainter for load history
- Warning threshold at 70%
- Critical threshold at 90%
- Color coding: green < 70% < yellow < 90% < red

---

## P3.13: Live WebSocket Parameter Channel

### Purpose

Real-time, throttled parameter updates to game engines via WebSocket.

### Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    FluxForge Studio                         │
│                                                              │
│  ┌─────────────────┐     ┌─────────────────────────────┐  │
│  │ MorphController │────►│   LiveParameterChannel      │  │
│  │ MacroController │────►│                             │  │
│  │ RtpcController  │────►│   throttleInterval: 33ms   │  │
│  └─────────────────┘     │   (~30 Hz max)              │  │
│                           │                             │  │
│                           │   _throttleTimers: Map      │  │
│                           └──────────────┬──────────────┘  │
│                                          │                  │
└──────────────────────────────────────────┼──────────────────┘
                                           │ WebSocket
                                           ▼
┌──────────────────────────────────────────────────────────────┐
│                      Game Engine                              │
│                                                                │
│  { "type": "rtpc",                                           │
│    "targetId": "tension",                                    │
│    "numericValue": 0.75 }                                    │
└──────────────────────────────────────────────────────────────┘
```

### Data Models

**Location:** `flutter_ui/lib/services/websocket_client.dart`

```dart
enum ParameterUpdateType {
  rtpc,
  volume,
  pan,
  mute,
  solo,
  morphPosition,
  macroValue,
  containerState,
  stateGroup,
  switchGroup,
}

class ParameterUpdate {
  final ParameterUpdateType type;
  final String targetId;
  final double? numericValue;
  final String? stringValue;
  final bool? boolValue;
  final DateTime timestamp;

  factory ParameterUpdate.rtpc(String rtpcId, double value);
  factory ParameterUpdate.volume(String targetId, double value);
  factory ParameterUpdate.pan(String targetId, double value);
  factory ParameterUpdate.mute(String targetId, bool muted);
  factory ParameterUpdate.solo(String targetId, bool soloed);
  factory ParameterUpdate.morphPosition(String morphId, double position);
  factory ParameterUpdate.macroValue(String macroId, double value);
  factory ParameterUpdate.containerState(String containerId, String state);
  factory ParameterUpdate.stateGroup(String groupId, String state);
  factory ParameterUpdate.switchGroup(String groupId, String switchId);

  Map<String, dynamic> toJson();
}

class LiveParameterChannel {
  final Duration throttleInterval;  // Default: 33ms (~30Hz)
  final Map<String, Timer> _throttleTimers = {};
  final Map<String, ParameterUpdate> _pendingUpdates = {};
  final WebSocketClient _client;

  void send(ParameterUpdate update);  // Throttled
  void sendImmediate(ParameterUpdate update);  // Bypass throttle

  // Convenience methods
  void sendRtpc(String rtpcId, double value);
  void sendMorphPosition(String morphId, double position);
  void sendMacroValue(String macroId, double value);
  void sendVolume(String targetId, double value);
  void sendPan(String targetId, double value);
  void sendMute(String targetId, bool muted);
  void sendSolo(String targetId, bool soloed);

  void dispose();
}
```

### Throttling Algorithm

```dart
void send(ParameterUpdate update) {
  final key = '${update.type.name}:${update.targetId}';
  _pendingUpdates[key] = update;

  if (_throttleTimers.containsKey(key)) {
    return; // Already scheduled
  }

  _throttleTimers[key] = Timer(throttleInterval, () {
    final pending = _pendingUpdates.remove(key);
    _throttleTimers.remove(key);
    if (pending != null) {
      _client.send(jsonEncode(pending.toJson()));
    }
  });
}
```

---

## P3.14: Visual Routing Matrix UI

### Purpose

Visual track→bus routing matrix with click-to-route functionality.

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    RoutingMatrixPanel                           │
├────────────────────────────────────────────────────────────────┤
│                                                                  │
│        │ SFX │ Music │ Voice │ Amb │ Aux1 │ Aux2 │ Master │    │
│   ─────┼─────┼───────┼───────┼─────┼──────┼──────┼────────┤    │
│ Track1 │  ●  │       │       │     │ -6dB │      │   ●    │    │
│ Track2 │     │   ●   │       │     │      │ -3dB │   ●    │    │
│ Track3 │     │       │   ●   │     │ -12dB│      │   ●    │    │
│ Track4 │     │       │       │  ●  │      │      │   ●    │    │
│   ─────┼─────┼───────┼───────┼─────┼──────┼──────┼────────┤    │
│                                                                  │
│  Legend:  ● = Direct route   -XdB = Aux send level             │
│                                                                  │
│  Click: Toggle route                                            │
│  Long-press on Aux: Adjust send level                          │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
```

### Data Models

**Location:** `flutter_ui/lib/widgets/routing/routing_matrix_panel.dart`

```dart
enum RoutingNodeType { track, bus, aux, master }

class RoutingNode {
  final int id;
  final String name;
  final RoutingNodeType type;
  final double volume;
  final double pan;
  final bool muted;
  final bool soloed;
  final Color color;
}

class RoutingConnection {
  final int sourceId;
  final int targetId;
  final double sendLevel;  // 0.0 to 1.0 (or -inf to +12dB)
  final bool preFader;
  final bool enabled;
}
```

### Widget Features

- **Grid Layout**: Tracks as rows, buses as columns
- **Cell States**:
  - Empty: No route
  - Filled circle: Direct route
  - dB value: Aux send with level
- **Interactions**:
  - Tap: Toggle route on/off
  - Long-press on aux: Opens send level dialog
- **Visual Feedback**:
  - Hover highlight
  - Color-coded by bus type
  - Mute/solo state indication

---

## File Locations Summary

| Feature | Model File | Provider File | Widget File |
|---------|------------|---------------|-------------|
| P3.10 Macros | `middleware_models.dart` | `rtpc_system_provider.dart` | (TBD) |
| P3.11 Morphing | `middleware_models.dart` | `rtpc_system_provider.dart` | (TBD) |
| P3.12 DSP Profiler | `advanced_middleware_models.dart` | — | `dsp_profiler_panel.dart` |
| P3.13 WebSocket | `websocket_client.dart` | — | — |
| P3.14 Routing Matrix | `routing_matrix_panel.dart` | — | `routing_matrix_panel.dart` |

---

## Integration Points

### With MiddlewareProvider

```dart
// Macros and Morphs are in RtpcSystemProvider
// which is a subsystem of MiddlewareProvider
final rtpc = sl<RtpcSystemProvider>();
rtpc.createMacro(name: 'Tension', bindings: [...]);
rtpc.createMorph(name: 'CalmToIntense', presetA: 'Calm', presetB: 'Intense');
```

### With EventRegistry

```dart
// DSP profiler records timing during event playback
EventRegistry.instance.onEventTriggered.listen((event) {
  DspProfiler.instance.record(
    stageTimingsUs: measureStageTimings(),
    blockSize: currentBlockSize,
    sampleRate: currentSampleRate,
  );
});
```

### With WebSocketClient

```dart
// Live parameter updates during real-time preview
final channel = LiveParameterChannel(
  client: WebSocketClient.instance,
  throttleInterval: Duration(milliseconds: 33),
);

rtpc.addListener(() {
  for (final macro in rtpc.allMacros) {
    channel.sendMacroValue(macro.id.toString(), macro.currentValue);
  }
});
```

---

*Generated by Claude Code — P3 Session Complete*
*Last Updated: 2026-01-22*
