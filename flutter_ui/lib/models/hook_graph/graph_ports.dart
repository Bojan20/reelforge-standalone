/// Port types and directions for the Hook Graph System.
///
/// Ports are typed connection points on graph nodes.
/// Wire transforms handle implicit type coercion between compatible ports.

enum PortType {
  trigger, // Bang/pulse — no data, just "fire"
  boolean,
  integer,
  float,
  string,
  audio, // Stereo audio buffer reference
  bus, // Bus routing identifier
  rtpc, // RTPC parameter reference
  any, // Accepts any type (debug/utility nodes)
}

enum PortDirection {
  input,
  output,
}

class GraphPort {
  final String id;
  final String label;
  final PortType type;
  final PortDirection direction;
  final dynamic defaultValue;
  final bool required;

  const GraphPort({
    required this.id,
    required this.label,
    required this.type,
    required this.direction,
    this.defaultValue,
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'direction': direction.name,
        if (defaultValue != null) 'default': defaultValue,
        'required': required,
      };

  factory GraphPort.fromJson(Map<String, dynamic> json) {
    return GraphPort(
      id: json['id'] as String,
      label: json['label'] as String,
      type: PortType.values.byName(json['type'] as String),
      direction: PortDirection.values.byName(json['direction'] as String),
      defaultValue: json['default'],
      required: json['required'] as bool? ?? false,
    );
  }
}

/// Check if two port types are compatible (with implicit coercion)
bool arePortsCompatible(PortType from, PortType to) {
  if (from == to) return true;
  if (to == PortType.any || from == PortType.any) return true;

  // Implicit coercions
  switch ((from, to)) {
    case (PortType.integer, PortType.float):
    case (PortType.boolean, PortType.integer):
    case (PortType.boolean, PortType.float):
    case (PortType.trigger, PortType.boolean):
    case (PortType.integer, PortType.string):
    case (PortType.float, PortType.string):
    case (PortType.boolean, PortType.string):
      return true;
    default:
      return false;
  }
}
