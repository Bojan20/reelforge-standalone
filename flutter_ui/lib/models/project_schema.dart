// Project Schema Definitions
//
// JSON Schema definitions for FluxForge project files:
// - DAW section schema
// - Middleware section schema
// - SlotLab section schema
// - Field type definitions and constraints

/// Current schema version
const int kCurrentSchemaVersion = 5;

/// Minimum supported schema version
const int kMinSupportedSchemaVersion = 1;

/// Field type for schema validation
enum FieldType {
  string,
  number,
  integer,
  boolean,
  array,
  object,
  any,
}

/// Field constraint definition
class FieldConstraint {
  final bool required;
  final FieldType type;
  final num? min;
  final num? max;
  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final List<String>? enumValues;
  final Map<String, FieldConstraint>? properties;
  final FieldConstraint? items;
  final dynamic defaultValue;
  final String? dependsOn;
  final String? description;

  const FieldConstraint({
    this.required = false,
    this.type = FieldType.any,
    this.min,
    this.max,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.enumValues,
    this.properties,
    this.items,
    this.defaultValue,
    this.dependsOn,
    this.description,
  });

  /// Create a required string field
  const FieldConstraint.requiredString({
    this.minLength,
    this.maxLength,
    this.enumValues,
    this.defaultValue,
    this.description,
  })  : required = true,
        type = FieldType.string,
        min = null,
        max = null,
        minItems = null,
        maxItems = null,
        properties = null,
        items = null,
        dependsOn = null;

  /// Create an optional string field
  const FieldConstraint.optionalString({
    this.minLength,
    this.maxLength,
    this.enumValues,
    this.defaultValue,
    this.description,
  })  : required = false,
        type = FieldType.string,
        min = null,
        max = null,
        minItems = null,
        maxItems = null,
        properties = null,
        items = null,
        dependsOn = null;

  /// Create a required number field with range
  const FieldConstraint.requiredNumber({
    this.min,
    this.max,
    this.defaultValue,
    this.description,
  })  : required = true,
        type = FieldType.number,
        minLength = null,
        maxLength = null,
        minItems = null,
        maxItems = null,
        enumValues = null,
        properties = null,
        items = null,
        dependsOn = null;

  /// Create an optional number field with range
  const FieldConstraint.optionalNumber({
    this.min,
    this.max,
    this.defaultValue,
    this.description,
  })  : required = false,
        type = FieldType.number,
        minLength = null,
        maxLength = null,
        minItems = null,
        maxItems = null,
        enumValues = null,
        properties = null,
        items = null,
        dependsOn = null;

  /// Create a required boolean field
  const FieldConstraint.requiredBool({
    this.defaultValue,
    this.description,
  })  : required = true,
        type = FieldType.boolean,
        min = null,
        max = null,
        minLength = null,
        maxLength = null,
        minItems = null,
        maxItems = null,
        enumValues = null,
        properties = null,
        items = null,
        dependsOn = null;

  /// Create an optional boolean field
  const FieldConstraint.optionalBool({
    this.defaultValue,
    this.description,
  })  : required = false,
        type = FieldType.boolean,
        min = null,
        max = null,
        minLength = null,
        maxLength = null,
        minItems = null,
        maxItems = null,
        enumValues = null,
        properties = null,
        items = null,
        dependsOn = null;

  /// Create a required array field
  const FieldConstraint.requiredArray({
    this.minItems,
    this.maxItems,
    this.items,
    this.defaultValue,
    this.description,
  })  : required = true,
        type = FieldType.array,
        min = null,
        max = null,
        minLength = null,
        maxLength = null,
        enumValues = null,
        properties = null,
        dependsOn = null;

  /// Create an optional array field
  const FieldConstraint.optionalArray({
    this.minItems,
    this.maxItems,
    this.items,
    this.defaultValue,
    this.description,
  })  : required = false,
        type = FieldType.array,
        min = null,
        max = null,
        minLength = null,
        maxLength = null,
        enumValues = null,
        properties = null,
        dependsOn = null;

  /// Create a required object field
  const FieldConstraint.requiredObject({
    this.properties,
    this.defaultValue,
    this.description,
  })  : required = true,
        type = FieldType.object,
        min = null,
        max = null,
        minLength = null,
        maxLength = null,
        minItems = null,
        maxItems = null,
        enumValues = null,
        items = null,
        dependsOn = null;

  /// Create an optional object field
  const FieldConstraint.optionalObject({
    this.properties,
    this.defaultValue,
    this.description,
  })  : required = false,
        type = FieldType.object,
        min = null,
        max = null,
        minLength = null,
        maxLength = null,
        minItems = null,
        maxItems = null,
        enumValues = null,
        items = null,
        dependsOn = null;

  /// Create a field with cross-field dependency
  FieldConstraint withDependency(String fieldName) {
    return FieldConstraint(
      required: required,
      type: type,
      min: min,
      max: max,
      minLength: minLength,
      maxLength: maxLength,
      minItems: minItems,
      maxItems: maxItems,
      enumValues: enumValues,
      properties: properties,
      items: items,
      defaultValue: defaultValue,
      dependsOn: fieldName,
      description: description,
    );
  }
}

/// Project schema definitions
class ProjectSchema {
  /// Root schema for FluxForge project file
  static const rootSchema = <String, FieldConstraint>{
    'schema_version': FieldConstraint.requiredNumber(
      min: 1,
      max: kCurrentSchemaVersion,
      description: 'Schema version number',
    ),
    'name': FieldConstraint.requiredString(
      minLength: 1,
      maxLength: 256,
      description: 'Project name',
    ),
    'created_at': FieldConstraint.optionalString(
      description: 'ISO 8601 timestamp of creation',
    ),
    'saved_at': FieldConstraint.optionalString(
      description: 'ISO 8601 timestamp of last save',
    ),
    'daw': FieldConstraint.optionalObject(
      properties: dawSchema,
      description: 'DAW section data',
    ),
    'middleware': FieldConstraint.optionalObject(
      properties: middlewareSchema,
      description: 'Middleware section data',
    ),
    'slot_lab': FieldConstraint.optionalObject(
      properties: slotLabSchema,
      description: 'SlotLab section data',
    ),
    'bus_hierarchy': FieldConstraint.optionalObject(
      description: 'Audio bus hierarchy',
    ),
    'rtpc_definitions': FieldConstraint.optionalArray(
      description: 'RTPC parameter definitions',
    ),
    'rtpc_bindings': FieldConstraint.optionalArray(
      description: 'RTPC parameter bindings',
    ),
    'aux_buses': FieldConstraint.optionalArray(
      description: 'Auxiliary bus definitions',
    ),
    'aux_sends': FieldConstraint.optionalArray(
      description: 'Auxiliary send routing',
    ),
    'stage_definitions': FieldConstraint.optionalObject(
      description: 'Stage protocol definitions',
    ),
    'stage_audio_mappings': FieldConstraint.optionalArray(
      description: 'Stage to audio mappings',
    ),
  };

  /// DAW section schema
  static const dawSchema = <String, FieldConstraint>{
    'tracks': FieldConstraint.optionalArray(
      maxItems: 256,
      items: FieldConstraint.requiredObject(
        properties: trackSchema,
      ),
      description: 'DAW tracks',
    ),
    'transport': FieldConstraint.optionalObject(
      properties: transportSchema,
      description: 'Transport state',
    ),
    'tempo': FieldConstraint.optionalNumber(
      min: 20,
      max: 999,
      defaultValue: 120.0,
      description: 'Tempo in BPM',
    ),
    'time_signature': FieldConstraint.optionalObject(
      description: 'Time signature',
    ),
  };

  /// Track schema
  static const trackSchema = <String, FieldConstraint>{
    'id': FieldConstraint.requiredString(
      minLength: 1,
      description: 'Unique track ID',
    ),
    'name': FieldConstraint.requiredString(
      minLength: 1,
      maxLength: 128,
      description: 'Track name',
    ),
    'type': FieldConstraint.requiredString(
      enumValues: ['audio', 'bus', 'aux', 'vca', 'master', 'midi', 'instrument'],
      defaultValue: 'audio',
      description: 'Track type',
    ),
    'volume': FieldConstraint.optionalNumber(
      min: 0,
      max: 4,
      defaultValue: 1.0,
      description: 'Track volume (0-4, 1=unity)',
    ),
    'pan': FieldConstraint.optionalNumber(
      min: -1,
      max: 1,
      defaultValue: 0.0,
      description: 'Track pan (-1=L, 0=C, 1=R)',
    ),
    'muted': FieldConstraint.optionalBool(
      defaultValue: false,
      description: 'Track mute state',
    ),
    'soloed': FieldConstraint.optionalBool(
      defaultValue: false,
      description: 'Track solo state',
    ),
    'armed': FieldConstraint.optionalBool(
      defaultValue: false,
      description: 'Track arm state',
    ),
    'output_bus_id': FieldConstraint.optionalNumber(
      description: 'Output bus ID',
    ),
    'regions': FieldConstraint.optionalArray(
      maxItems: 10000,
      description: 'Audio regions on track',
    ),
    'inserts': FieldConstraint.optionalArray(
      maxItems: 16,
      description: 'Insert effect slots',
    ),
    'sends': FieldConstraint.optionalArray(
      maxItems: 8,
      description: 'Send routing slots',
    ),
  };

  /// Transport schema
  static const transportSchema = <String, FieldConstraint>{
    'position': FieldConstraint.optionalNumber(
      min: 0,
      defaultValue: 0.0,
      description: 'Playhead position in seconds',
    ),
    'playing': FieldConstraint.optionalBool(
      defaultValue: false,
      description: 'Playback state',
    ),
    'recording': FieldConstraint.optionalBool(
      defaultValue: false,
      description: 'Recording state',
    ),
    'loop_enabled': FieldConstraint.optionalBool(
      defaultValue: false,
      description: 'Loop playback enabled',
    ),
    'loop_start': FieldConstraint.optionalNumber(
      min: 0,
      description: 'Loop start position',
    ),
    'loop_end': FieldConstraint.optionalNumber(
      min: 0,
      description: 'Loop end position',
    ),
  };

  /// Middleware section schema
  static const middlewareSchema = <String, FieldConstraint>{
    'events': FieldConstraint.optionalArray(
      maxItems: 5000,
      items: FieldConstraint.requiredObject(
        properties: middlewareEventSchema,
      ),
      description: 'Middleware events',
    ),
    'state_groups': FieldConstraint.optionalArray(
      maxItems: 100,
      description: 'State group definitions',
    ),
    'switch_groups': FieldConstraint.optionalArray(
      maxItems: 100,
      description: 'Switch group definitions',
    ),
    'ducking_rules': FieldConstraint.optionalArray(
      maxItems: 50,
      description: 'Ducking rules',
    ),
    'blend_containers': FieldConstraint.optionalArray(
      maxItems: 200,
      description: 'Blend container definitions',
    ),
    'random_containers': FieldConstraint.optionalArray(
      maxItems: 200,
      description: 'Random container definitions',
    ),
    'sequence_containers': FieldConstraint.optionalArray(
      maxItems: 200,
      description: 'Sequence container definitions',
    ),
  };

  /// Middleware event schema
  static const middlewareEventSchema = <String, FieldConstraint>{
    'id': FieldConstraint.requiredString(
      minLength: 1,
      description: 'Unique event ID',
    ),
    'name': FieldConstraint.requiredString(
      minLength: 1,
      maxLength: 256,
      description: 'Event name',
    ),
    'category': FieldConstraint.optionalString(
      maxLength: 128,
      description: 'Event category',
    ),
    'actions': FieldConstraint.optionalArray(
      maxItems: 100,
      description: 'Event actions',
    ),
  };

  /// SlotLab section schema
  static const slotLabSchema = <String, FieldConstraint>{
    'name': FieldConstraint.optionalString(
      maxLength: 256,
      description: 'SlotLab project name',
    ),
    'version': FieldConstraint.optionalString(
      description: 'SlotLab project version',
    ),
    'symbols': FieldConstraint.optionalArray(
      maxItems: 100,
      items: FieldConstraint.requiredObject(
        properties: symbolSchema,
      ),
      description: 'Symbol definitions',
    ),
    'contexts': FieldConstraint.optionalArray(
      maxItems: 20,
      description: 'Game context definitions',
    ),
    'symbol_audio': FieldConstraint.optionalArray(
      maxItems: 1000,
      description: 'Symbol audio assignments',
    ),
    'music_layers': FieldConstraint.optionalArray(
      maxItems: 100,
      description: 'Music layer assignments',
    ),
    'audio_assignments': FieldConstraint.optionalObject(
      description: 'Stage to audio path mappings',
    ),
    'composite_events': FieldConstraint.optionalArray(
      maxItems: 500,
      description: 'SlotLab composite events',
    ),
    'grid_config': FieldConstraint.optionalObject(
      description: 'Slot grid configuration',
    ),
    'win_configuration': FieldConstraint.optionalObject(
      description: 'Win tier configuration (P5)',
    ),
  };

  /// Symbol schema
  static const symbolSchema = <String, FieldConstraint>{
    'id': FieldConstraint.requiredString(
      minLength: 1,
      maxLength: 64,
      description: 'Symbol ID',
    ),
    'name': FieldConstraint.requiredString(
      minLength: 1,
      maxLength: 128,
      description: 'Symbol display name',
    ),
    'emoji': FieldConstraint.requiredString(
      minLength: 1,
      maxLength: 8,
      description: 'Symbol emoji',
    ),
    'type': FieldConstraint.requiredString(
      enumValues: [
        'wild', 'scatter', 'bonus', 'highPay', 'mediumPay', 'lowPay',
        'multiplier', 'collector', 'mystery', 'custom', 'high', 'low'
      ],
      description: 'Symbol type',
    ),
    'contexts': FieldConstraint.optionalArray(
      description: 'Audio contexts for symbol',
    ),
    'payMultiplier': FieldConstraint.optionalNumber(
      min: 0,
      max: 10000,
      description: 'Pay multiplier',
    ),
    'sortOrder': FieldConstraint.optionalNumber(
      min: 0,
      max: 100,
      description: 'Display sort order',
    ),
  };

  /// Middleware action schema
  static const actionSchema = <String, FieldConstraint>{
    'id': FieldConstraint.requiredString(
      description: 'Action ID',
    ),
    'type': FieldConstraint.requiredString(
      enumValues: [
        'play', 'playAndContinue', 'stop', 'stopAll', 'pause', 'pauseAll',
        'resume', 'resumeAll', 'break_', 'mute', 'unmute', 'setVolume',
        'setPitch', 'setLPF', 'setHPF', 'setBusVolume', 'setState',
        'setSwitch', 'setRTPC', 'resetRTPC', 'seek', 'trigger', 'postEvent'
      ],
      defaultValue: 'play',
      description: 'Action type',
    ),
    'assetId': FieldConstraint.optionalString(
      description: 'Audio asset ID',
    ),
    'bus': FieldConstraint.optionalString(
      defaultValue: 'Master',
      description: 'Target bus',
    ),
    'gain': FieldConstraint.optionalNumber(
      min: 0,
      max: 4,
      defaultValue: 1.0,
      description: 'Gain multiplier',
    ),
    'pan': FieldConstraint.optionalNumber(
      min: -1,
      max: 1,
      defaultValue: 0.0,
      description: 'Pan position',
    ),
    'delay': FieldConstraint.optionalNumber(
      min: 0,
      max: 30,
      defaultValue: 0.0,
      description: 'Delay in seconds',
    ),
    'fadeTime': FieldConstraint.optionalNumber(
      min: 0,
      max: 30,
      defaultValue: 0.1,
      description: 'Fade time in seconds',
    ),
    'loop': FieldConstraint.optionalBool(
      defaultValue: false,
      description: 'Loop playback',
    ),
    'fadeInMs': FieldConstraint.optionalNumber(
      min: 0,
      max: 10000,
      defaultValue: 0.0,
      description: 'Fade-in duration in ms',
    ),
    'fadeOutMs': FieldConstraint.optionalNumber(
      min: 0,
      max: 10000,
      defaultValue: 0.0,
      description: 'Fade-out duration in ms',
    ),
    'trimStartMs': FieldConstraint.optionalNumber(
      min: 0,
      max: 600000,
      defaultValue: 0.0,
      description: 'Trim start in ms',
    ),
    'trimEndMs': FieldConstraint.optionalNumber(
      min: 0,
      max: 600000,
      defaultValue: 0.0,
      description: 'Trim end in ms',
    ),
  };

  /// Get schema for a specific section
  static Map<String, FieldConstraint>? getSchemaForSection(String section) {
    switch (section) {
      case 'daw':
        return dawSchema;
      case 'middleware':
        return middlewareSchema;
      case 'slot_lab':
        return slotLabSchema;
      case 'track':
        return trackSchema;
      case 'event':
        return middlewareEventSchema;
      case 'symbol':
        return symbolSchema;
      case 'action':
        return actionSchema;
      default:
        return null;
    }
  }
}
