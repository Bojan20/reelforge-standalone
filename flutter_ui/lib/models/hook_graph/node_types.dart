/// Core node type definitions for Phase 1 of the Hook Graph System.
///
/// Each node type defines its ports, parameters, and category.
/// These are registered with NodeTypeRegistry at startup.

import 'graph_ports.dart';
import 'graph_definition.dart';

/// Node type definition — metadata + port specification
class NodeTypeDefinition {
  final String typeId;
  final String displayName;
  final String description;
  final NodeCategory category;
  final List<GraphPort> inputPorts;
  final List<GraphPort> outputPorts;
  final Map<String, dynamic> defaultParameters;
  final List<String> tags;

  const NodeTypeDefinition({
    required this.typeId,
    required this.displayName,
    required this.description,
    required this.category,
    this.inputPorts = const [],
    this.outputPorts = const [],
    this.defaultParameters = const {},
    this.tags = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 1 NODE TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// EventEntry — Graph entry point, triggered by an event
final eventEntryNode = NodeTypeDefinition(
  typeId: 'EventEntry',
  displayName: 'Event Entry',
  description: 'Graph entry point — receives the triggering event',
  category: NodeCategory.event,
  outputPorts: [
    GraphPort(
      id: 'trigger',
      label: 'Trigger',
      type: PortType.trigger,
      direction: PortDirection.output,
    ),
    GraphPort(
      id: 'eventId',
      label: 'Event ID',
      type: PortType.string,
      direction: PortDirection.output,
    ),
    GraphPort(
      id: 'eventData',
      label: 'Data',
      type: PortType.any,
      direction: PortDirection.output,
    ),
  ],
  tags: ['entry', 'event', 'trigger'],
);

/// Compare — Conditional comparison node
final compareNode = NodeTypeDefinition(
  typeId: 'Compare',
  displayName: 'Compare',
  description: 'Compare two values using configurable operator',
  category: NodeCategory.condition,
  inputPorts: [
    GraphPort(
        id: 'a', label: 'A', type: PortType.any, direction: PortDirection.input, required: true),
    GraphPort(
        id: 'b', label: 'B', type: PortType.any, direction: PortDirection.input, required: true),
  ],
  outputPorts: [
    GraphPort(
        id: 'result',
        label: 'Result',
        type: PortType.boolean,
        direction: PortDirection.output),
    GraphPort(
        id: 'trueOut',
        label: 'True',
        type: PortType.trigger,
        direction: PortDirection.output),
    GraphPort(
        id: 'falseOut',
        label: 'False',
        type: PortType.trigger,
        direction: PortDirection.output),
  ],
  defaultParameters: {'operator': 'eq'},
  tags: ['condition', 'compare', 'if'],
);

/// Switch — Multi-way routing based on value
final switchNode = NodeTypeDefinition(
  typeId: 'Switch',
  displayName: 'Switch',
  description: 'Route execution based on input value matching cases',
  category: NodeCategory.logic,
  inputPorts: [
    GraphPort(
        id: 'value',
        label: 'Value',
        type: PortType.any,
        direction: PortDirection.input,
        required: true),
  ],
  outputPorts: [
    GraphPort(
        id: 'case0', label: 'Case 0', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(
        id: 'case1', label: 'Case 1', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(
        id: 'case2', label: 'Case 2', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(
        id: 'case3', label: 'Case 3', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(
        id: 'default',
        label: 'Default',
        type: PortType.trigger,
        direction: PortDirection.output),
  ],
  defaultParameters: {
    'cases': ['value0', 'value1', 'value2', 'value3'],
  },
  tags: ['logic', 'switch', 'route', 'select'],
);

/// Gate — Pass/block trigger based on condition
final gateNode = NodeTypeDefinition(
  typeId: 'Gate',
  displayName: 'Gate',
  description: 'Pass or block trigger based on boolean condition',
  category: NodeCategory.logic,
  inputPorts: [
    GraphPort(
        id: 'trigger',
        label: 'Trigger',
        type: PortType.trigger,
        direction: PortDirection.input,
        required: true),
    GraphPort(
        id: 'open',
        label: 'Open',
        type: PortType.boolean,
        direction: PortDirection.input,
        defaultValue: true),
  ],
  outputPorts: [
    GraphPort(
        id: 'out', label: 'Out', type: PortType.trigger, direction: PortDirection.output),
  ],
  tags: ['logic', 'gate', 'filter'],
);

/// PlaySound — Trigger audio playback through the Rust engine
final playSoundNode = NodeTypeDefinition(
  typeId: 'PlaySound',
  displayName: 'Play Sound',
  description: 'Play an audio file through the voice manager',
  category: NodeCategory.audio,
  inputPorts: [
    GraphPort(
        id: 'trigger',
        label: 'Trigger',
        type: PortType.trigger,
        direction: PortDirection.input,
        required: true),
    GraphPort(
        id: 'volume',
        label: 'Volume',
        type: PortType.float,
        direction: PortDirection.input,
        defaultValue: 1.0),
    GraphPort(
        id: 'bus', label: 'Bus', type: PortType.bus, direction: PortDirection.input),
  ],
  outputPorts: [
    GraphPort(
        id: 'voiceId',
        label: 'Voice ID',
        type: PortType.integer,
        direction: PortDirection.output),
    GraphPort(
        id: 'done', label: 'Done', type: PortType.trigger, direction: PortDirection.output),
  ],
  defaultParameters: {
    'assetPath': '',
    'bus': 'sfx',
    'priority': 'normal',
    'looping': false,
  },
  tags: ['audio', 'play', 'sound', 'voice'],
);

/// StopSound — Stop a playing voice
final stopSoundNode = NodeTypeDefinition(
  typeId: 'StopSound',
  displayName: 'Stop Sound',
  description: 'Stop a playing voice with optional fade-out',
  category: NodeCategory.audio,
  inputPorts: [
    GraphPort(
        id: 'trigger',
        label: 'Trigger',
        type: PortType.trigger,
        direction: PortDirection.input,
        required: true),
    GraphPort(
        id: 'voiceId',
        label: 'Voice ID',
        type: PortType.integer,
        direction: PortDirection.input),
    GraphPort(
        id: 'fadeMs',
        label: 'Fade (ms)',
        type: PortType.float,
        direction: PortDirection.input,
        defaultValue: 50.0),
  ],
  outputPorts: [
    GraphPort(
        id: 'done', label: 'Done', type: PortType.trigger, direction: PortDirection.output),
  ],
  defaultParameters: {'fadeMs': 50.0, 'stopAll': false},
  tags: ['audio', 'stop', 'sound', 'voice'],
);

/// Delay — Timing delay node
final delayNode = NodeTypeDefinition(
  typeId: 'Delay',
  displayName: 'Delay',
  description: 'Delay trigger by configurable duration',
  category: NodeCategory.timing,
  inputPorts: [
    GraphPort(
        id: 'trigger',
        label: 'Trigger',
        type: PortType.trigger,
        direction: PortDirection.input,
        required: true),
    GraphPort(
        id: 'delayMs',
        label: 'Delay (ms)',
        type: PortType.float,
        direction: PortDirection.input,
        defaultValue: 100.0),
  ],
  outputPorts: [
    GraphPort(
        id: 'out', label: 'Out', type: PortType.trigger, direction: PortDirection.output),
  ],
  defaultParameters: {'delayMs': 100.0},
  tags: ['timing', 'delay', 'wait'],
);

/// All Phase 1 node type definitions
final phase1NodeTypes = [
  eventEntryNode,
  compareNode,
  switchNode,
  gateNode,
  playSoundNode,
  stopSoundNode,
  delayNode,
];
