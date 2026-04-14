/// ControlRateExecutor — Dart-side graph execution engine (~60Hz).
///
/// Processes control-rate nodes (conditions, logic, timing, RTPC).
/// Sends audio commands to Rust via lock-free ring buffer.
/// Does NOT process audio — that's Rust's HookGraphEngine.

import 'dart:collection';

import '../../models/hook_graph/graph_definition.dart';

/// Wire state — holds all connection values for a graph instance
class WireState {
  final List<dynamic> _values;
  final List<int> _lastWriteTick;
  final Map<String, int> _wireIndex;

  WireState._({
    required List<dynamic> values,
    required List<int> lastWriteTick,
    required Map<String, int> wireIndex,
  })  : _values = values,
        _lastWriteTick = lastWriteTick,
        _wireIndex = wireIndex;

  factory WireState.fromGraph(HookGraphDefinition graph) {
    final wireIndex = <String, int>{};
    int idx = 0;

    for (final node in graph.nodes) {
      // Index all possible wire endpoints
      wireIndex['${node.id}.trigger'] = idx++;
      wireIndex['${node.id}.out'] = idx++;
      wireIndex['${node.id}.result'] = idx++;
      for (final key in node.parameters.keys) {
        wireIndex['${node.id}.$key'] = idx++;
      }
    }

    for (final conn in graph.connections) {
      final fromKey = '${conn.fromNodeId}.${conn.fromPortId}';
      final toKey = '${conn.toNodeId}.${conn.toPortId}';
      wireIndex.putIfAbsent(fromKey, () => idx++);
      wireIndex.putIfAbsent(toKey, () => idx++);
    }

    return WireState._(
      values: List.filled(idx, null),
      lastWriteTick: List.filled(idx, -1),
      wireIndex: wireIndex,
    );
  }

  T? read<T>(String nodeId, String portId) {
    final idx = _wireIndex['$nodeId.$portId'];
    if (idx == null || _values[idx] == null) return null;
    return _values[idx] as T;
  }

  T readOr<T>(String nodeId, String portId, T defaultValue) {
    final idx = _wireIndex['$nodeId.$portId'];
    if (idx == null || _values[idx] == null) return defaultValue;
    return _values[idx] as T;
  }

  void write(String nodeId, String portId, dynamic value, int tick) {
    final idx = _wireIndex['$nodeId.$portId'];
    if (idx == null) return;
    _values[idx] = value;
    _lastWriteTick[idx] = tick;
  }

  bool isChanged(String nodeId, String portId, int sinceTick) {
    final idx = _wireIndex['$nodeId.$portId'];
    if (idx == null) return false;
    return _lastWriteTick[idx] > sinceTick;
  }

  void clear() {
    _values.fillRange(0, _values.length, null);
    _lastWriteTick.fillRange(0, _lastWriteTick.length, -1);
  }
}

/// Graph execution context
class GraphContext {
  final int tick;
  final Map<String, double> rtpcValues;
  final List<AudioCommand> pendingCommands;

  GraphContext({
    required this.tick,
    this.rtpcValues = const {},
  }) : pendingCommands = [];

  void emitCommand(AudioCommand cmd) {
    pendingCommands.add(cmd);
  }
}

/// Audio command to send to Rust engine
sealed class AudioCommand {
  const AudioCommand();
}

class StartVoiceCommand extends AudioCommand {
  final String assetPath;
  final double volume;
  final String bus;
  final String priority;
  final bool looping;
  const StartVoiceCommand({
    required this.assetPath,
    this.volume = 1.0,
    this.bus = 'sfx',
    this.priority = 'normal',
    this.looping = false,
  });
}

class StopVoiceCommand extends AudioCommand {
  final int voiceId;
  final double fadeMs;
  const StopVoiceCommand({required this.voiceId, this.fadeMs = 50.0});
}

class SetParamCommand extends AudioCommand {
  final int nodeId;
  final String paramName;
  final double value;
  const SetParamCommand({
    required this.nodeId,
    required this.paramName,
    required this.value,
  });
}

/// Active graph execution instance
class GraphExecution {
  final String instanceId;
  final HookGraphDefinition graph;
  final WireState wires;
  final List<String> executionOrder;
  int tick = 0;
  bool done = false;

  GraphExecution({
    required this.instanceId,
    required this.graph,
  })  : wires = WireState.fromGraph(graph),
        executionOrder = _topologicalSort(graph);

  static List<String> _topologicalSort(HookGraphDefinition graph) {
    final adjacency = <String, List<String>>{};
    final inDegree = <String, int>{};

    for (final node in graph.nodes) {
      adjacency[node.id] = [];
      inDegree[node.id] = 0;
    }

    for (final conn in graph.connections) {
      adjacency[conn.fromNodeId]?.add(conn.toNodeId);
      inDegree[conn.toNodeId] = (inDegree[conn.toNodeId] ?? 0) + 1;
    }

    final queue = Queue<String>();
    for (final node in graph.nodes) {
      if ((inDegree[node.id] ?? 0) == 0) {
        queue.add(node.id);
      }
    }

    final sorted = <String>[];
    while (queue.isNotEmpty) {
      final nodeId = queue.removeFirst();
      sorted.add(nodeId);

      for (final neighbor in (adjacency[nodeId] ?? [])) {
        inDegree[neighbor] = (inDegree[neighbor] ?? 1) - 1;
        if (inDegree[neighbor] == 0) {
          queue.add(neighbor);
        }
      }
    }

    return sorted;
  }
}

/// Control-rate graph executor
class ControlRateExecutor {
  final Map<String, GraphExecution> _active = {};
  int _nextInstanceId = 0;

  /// Trigger a graph execution
  String trigger(HookGraphDefinition graph, {String? eventId, dynamic eventData}) {
    final id = 'inst_${_nextInstanceId++}';
    final execution = GraphExecution(instanceId: id, graph: graph);

    // Write initial event data to entry nodes
    for (final node in graph.nodes) {
      if (node.typeId == 'EventEntry') {
        execution.wires.write(node.id, 'trigger', true, 0);
        if (eventId != null) {
          execution.wires.write(node.id, 'eventId', eventId, 0);
        }
        if (eventData != null) {
          execution.wires.write(node.id, 'eventData', eventData, 0);
        }
      }
    }

    _active[id] = execution;
    return id;
  }

  /// Process one tick of all active graph instances.
  /// Returns audio commands to send to Rust.
  List<AudioCommand> tick() {
    final commands = <AudioCommand>[];
    final toRemove = <String>[];

    for (final entry in _active.entries) {
      final exec = entry.value;
      exec.tick++;

      final ctx = GraphContext(tick: exec.tick);

      // Process nodes in topological order
      for (final nodeId in exec.executionOrder) {
        final node = exec.graph.nodeById(nodeId);
        if (node == null) continue;

        _processNode(node, exec.wires, ctx, exec.tick);
      }

      commands.addAll(ctx.pendingCommands);

      // Check if graph is done (no more active nodes)
      if (exec.done) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      _active.remove(id);
    }

    return commands;
  }

  void _processNode(
      GraphNodeDef node, WireState wires, GraphContext ctx, int tick) {
    switch (node.typeId) {
      case 'EventEntry':
        // Already written initial values — just propagate trigger
        break;

      case 'Compare':
        final a = wires.read<dynamic>(node.id, 'a');
        final b = wires.read<dynamic>(node.id, 'b');
        final op = node.parameters['operator'] as String? ?? 'eq';
        final result = _compare(a, b, op);
        wires.write(node.id, 'result', result, tick);
        if (result) {
          wires.write(node.id, 'trueOut', true, tick);
        } else {
          wires.write(node.id, 'falseOut', true, tick);
        }

      case 'Switch':
        final value = wires.read<dynamic>(node.id, 'value');
        final cases =
            (node.parameters['cases'] as List?)?.cast<String>() ?? [];
        bool matched = false;
        for (int i = 0; i < cases.length; i++) {
          if (value?.toString() == cases[i]) {
            wires.write(node.id, 'case$i', true, tick);
            matched = true;
            break;
          }
        }
        if (!matched) {
          wires.write(node.id, 'default', true, tick);
        }

      case 'Gate':
        final trigger = wires.isChanged(node.id, 'trigger', tick - 1);
        final open = wires.readOr<bool>(node.id, 'open', true);
        if (trigger && open) {
          wires.write(node.id, 'out', true, tick);
        }

      case 'PlaySound':
        final triggered = wires.isChanged(node.id, 'trigger', tick - 1);
        if (triggered) {
          final volume = wires.readOr<double>(node.id, 'volume', 1.0);
          final assetPath =
              node.parameters['assetPath'] as String? ?? '';
          final bus = node.parameters['bus'] as String? ?? 'sfx';
          final priority =
              node.parameters['priority'] as String? ?? 'normal';
          final looping = node.parameters['looping'] as bool? ?? false;

          ctx.emitCommand(StartVoiceCommand(
            assetPath: assetPath,
            volume: volume,
            bus: bus,
            priority: priority,
            looping: looping,
          ));
        }

      case 'StopSound':
        final triggered = wires.isChanged(node.id, 'trigger', tick - 1);
        if (triggered) {
          final voiceId = wires.readOr<int>(node.id, 'voiceId', 0);
          final fadeMs = wires.readOr<double>(node.id, 'fadeMs', 50.0);
          ctx.emitCommand(StopVoiceCommand(
            voiceId: voiceId,
            fadeMs: fadeMs,
          ));
        }

      case 'Delay':
        // Tick-based delay gate.
        // Parameters: delayTicks (integer, default 1)
        // Behavior: waits N ticks after trigger fires before forwarding.
        // State stored on wire as countdown integer.
        final triggered = wires.isChanged(node.id, 'trigger', tick - 1);
        final delayTicks = (node.parameters['delayTicks'] as num?)?.toInt() ?? 1;

        if (triggered) {
          // Arm countdown: write remaining ticks
          wires.write(node.id, '_countdown', delayTicks, tick);
        }

        final countdown = wires.read<int>(node.id, '_countdown');
        if (countdown != null && countdown > 0) {
          final newCount = countdown - 1;
          wires.write(node.id, '_countdown', newCount, tick);
          if (newCount == 0) {
            // Countdown reached zero — fire output trigger
            wires.write(node.id, 'out', true, tick);
          }
        }

      case 'SetParam':
        // RTPC setter node: emits SetParamCommand to update audio parameters.
        // Inputs: trigger (optional), paramName (from parameters), value (wire or param)
        final triggered = node.parameters.containsKey('alwaysUpdate')
            ? (node.parameters['alwaysUpdate'] as bool? ?? false)
            : wires.isChanged(node.id, 'trigger', tick - 1);
        if (triggered) {
          final paramName = node.parameters['paramName'] as String? ?? '';
          if (paramName.isNotEmpty) {
            final value = wires.readOr<double>(node.id, 'value',
                (node.parameters['defaultValue'] as num?)?.toDouble() ?? 0.0);
            ctx.emitCommand(SetParamCommand(
              nodeId: int.tryParse(node.id) ?? node.id.hashCode,
              paramName: paramName,
              value: value,
            ));
          }
        }

      default:
        // Unknown node type — silently ignore (future-compatible)
        break;
    }
  }

  bool _compare(dynamic a, dynamic b, String op) {
    if (a == null || b == null) return false;

    switch (op) {
      case 'eq':
        return a == b;
      case 'neq':
        return a != b;
      case 'lt':
        return (a as num) < (b as num);
      case 'gt':
        return (a as num) > (b as num);
      case 'lte':
        return (a as num) <= (b as num);
      case 'gte':
        return (a as num) >= (b as num);
      case 'contains':
        return a.toString().contains(b.toString());
      default:
        return false;
    }
  }

  /// Stop a specific graph instance
  void stop(String instanceId) {
    _active.remove(instanceId);
  }

  /// Active instance count
  int get activeCount => _active.length;
}
