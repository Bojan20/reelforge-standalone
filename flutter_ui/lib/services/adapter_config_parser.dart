/// Adapter Config Parser — YAML/TOML Configuration for Stage Adapters
///
/// Parses adapter configuration files that define how engine events
/// map to canonical STAGES. Supports:
/// - YAML format (preferred)
/// - TOML format (alternative)
/// - JSON format (for runtime/debugging)
///
/// Example YAML:
/// ```yaml
/// adapter:
///   id: "company_x_engine_v2"
///   company: "Company X"
///   engine: "SlotEngine v2.0"
///   version: "1.0.0"
///
/// layer: direct_event
///
/// mappings:
///   - event: "onSpinStart"
///     stage: spin_start
///   - event: "onReelStopped"
///     stage: reel_stop
///     extract:
///       reel_index: "$.reelIndex"
///       symbols: "$.symbols"
/// ```
library;

import '../models/stage_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ADAPTER CONFIG MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Complete adapter configuration
class AdapterConfig {
  final String id;
  final String company;
  final String engine;
  final String version;
  final IngestLayer layer;
  final List<EventMapping> mappings;
  final Map<String, String> fieldAliases;
  final List<DerivedStageRule> derivedRules;

  const AdapterConfig({
    required this.id,
    required this.company,
    required this.engine,
    this.version = '1.0.0',
    this.layer = IngestLayer.directEvent,
    this.mappings = const [],
    this.fieldAliases = const {},
    this.derivedRules = const [],
  });

  factory AdapterConfig.fromYaml(String yamlContent) {
    return AdapterConfigParser.parseYaml(yamlContent);
  }

  factory AdapterConfig.fromJson(Map<String, dynamic> json) {
    return AdapterConfigParser.parseJson(json);
  }

  Map<String, dynamic> toJson() => {
    'adapter': {
      'id': id,
      'company': company,
      'engine': engine,
      'version': version,
    },
    'layer': layer.toJson(),
    'mappings': mappings.map((m) => m.toJson()).toList(),
    if (fieldAliases.isNotEmpty) 'field_aliases': fieldAliases,
    if (derivedRules.isNotEmpty) 'derived_rules': derivedRules.map((r) => r.toJson()).toList(),
  };

  String toYaml() => AdapterConfigParser.toYaml(this);

  /// Find mapping for an event name
  EventMapping? findMapping(String eventName) {
    for (final mapping in mappings) {
      if (mapping.event == eventName) return mapping;
      if (mapping.eventPattern != null) {
        final regex = RegExp(mapping.eventPattern!);
        if (regex.hasMatch(eventName)) return mapping;
      }
    }
    return null;
  }

  /// Get all stage types this adapter can produce
  Set<String> get supportedStages =>
      mappings.map((m) => m.stage).toSet();
}

/// Single event-to-stage mapping
class EventMapping {
  final String event;
  final String? eventPattern;
  final String stage;
  final Map<String, String> extract;
  final Map<String, dynamic> defaults;
  final String? condition;

  const EventMapping({
    required this.event,
    this.eventPattern,
    required this.stage,
    this.extract = const {},
    this.defaults = const {},
    this.condition,
  });

  factory EventMapping.fromJson(Map<String, dynamic> json) => EventMapping(
    event: json['event'] as String? ?? '',
    eventPattern: json['event_pattern'] as String?,
    stage: json['stage'] as String? ?? 'custom',
    extract: (json['extract'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
    defaults: (json['defaults'] as Map<String, dynamic>?) ?? {},
    condition: json['condition'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'event': event,
    if (eventPattern != null) 'event_pattern': eventPattern,
    'stage': stage,
    if (extract.isNotEmpty) 'extract': extract,
    if (defaults.isNotEmpty) 'defaults': defaults,
    if (condition != null) 'condition': condition,
  };
}

/// Rule for deriving stages from state changes (Layer 2)
class DerivedStageRule {
  final String name;
  final String watchField;
  final String fromValue;
  final String toValue;
  final String emitStage;
  final Map<String, dynamic> params;

  const DerivedStageRule({
    required this.name,
    required this.watchField,
    required this.fromValue,
    required this.toValue,
    required this.emitStage,
    this.params = const {},
  });

  factory DerivedStageRule.fromJson(Map<String, dynamic> json) => DerivedStageRule(
    name: json['name'] as String? ?? '',
    watchField: json['watch_field'] as String? ?? '',
    fromValue: json['from_value'] as String? ?? '*',
    toValue: json['to_value'] as String? ?? '',
    emitStage: json['emit_stage'] as String? ?? '',
    params: (json['params'] as Map<String, dynamic>?) ?? {},
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'watch_field': watchField,
    'from_value': fromValue,
    'to_value': toValue,
    'emit_stage': emitStage,
    if (params.isNotEmpty) 'params': params,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// PARSER
// ═══════════════════════════════════════════════════════════════════════════

/// Parser for adapter configuration files
class AdapterConfigParser {
  AdapterConfigParser._();

  /// Parse YAML content to AdapterConfig
  static AdapterConfig parseYaml(String yamlContent) {
    // Simple YAML parser for our specific format
    // For production, use package:yaml
    final lines = yamlContent.split('\n');
    final json = _yamlLinesToJson(lines);
    return parseJson(json);
  }

  /// Parse JSON map to AdapterConfig
  static AdapterConfig parseJson(Map<String, dynamic> json) {
    final adapter = json['adapter'] as Map<String, dynamic>? ?? {};
    final mappingsList = json['mappings'] as List<dynamic>? ?? [];
    final derivedList = json['derived_rules'] as List<dynamic>? ?? [];

    return AdapterConfig(
      id: adapter['id'] as String? ?? 'unknown',
      company: adapter['company'] as String? ?? 'Unknown',
      engine: adapter['engine'] as String? ?? 'Unknown Engine',
      version: adapter['version'] as String? ?? '1.0.0',
      layer: IngestLayer.fromJson(json['layer'] as String?) ?? IngestLayer.directEvent,
      mappings: mappingsList
          .map((m) => EventMapping.fromJson(m as Map<String, dynamic>))
          .toList(),
      fieldAliases: (json['field_aliases'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      derivedRules: derivedList
          .map((r) => DerivedStageRule.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Convert AdapterConfig to YAML string
  static String toYaml(AdapterConfig config) {
    final buffer = StringBuffer();

    buffer.writeln('# FluxForge Stage Adapter Configuration');
    buffer.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    buffer.writeln('adapter:');
    buffer.writeln('  id: "${config.id}"');
    buffer.writeln('  company: "${config.company}"');
    buffer.writeln('  engine: "${config.engine}"');
    buffer.writeln('  version: "${config.version}"');
    buffer.writeln();

    buffer.writeln('layer: ${config.layer.toJson()}');
    buffer.writeln();

    if (config.mappings.isNotEmpty) {
      buffer.writeln('mappings:');
      for (final mapping in config.mappings) {
        buffer.writeln('  - event: "${mapping.event}"');
        buffer.writeln('    stage: ${mapping.stage}');
        if (mapping.eventPattern != null) {
          buffer.writeln('    event_pattern: "${mapping.eventPattern}"');
        }
        if (mapping.extract.isNotEmpty) {
          buffer.writeln('    extract:');
          for (final entry in mapping.extract.entries) {
            buffer.writeln('      ${entry.key}: "${entry.value}"');
          }
        }
        if (mapping.defaults.isNotEmpty) {
          buffer.writeln('    defaults:');
          for (final entry in mapping.defaults.entries) {
            buffer.writeln('      ${entry.key}: ${_yamlValue(entry.value)}');
          }
        }
        if (mapping.condition != null) {
          buffer.writeln('    condition: "${mapping.condition}"');
        }
      }
      buffer.writeln();
    }

    if (config.fieldAliases.isNotEmpty) {
      buffer.writeln('field_aliases:');
      for (final entry in config.fieldAliases.entries) {
        buffer.writeln('  ${entry.key}: "${entry.value}"');
      }
      buffer.writeln();
    }

    if (config.derivedRules.isNotEmpty) {
      buffer.writeln('derived_rules:');
      for (final rule in config.derivedRules) {
        buffer.writeln('  - name: "${rule.name}"');
        buffer.writeln('    watch_field: "${rule.watchField}"');
        buffer.writeln('    from_value: "${rule.fromValue}"');
        buffer.writeln('    to_value: "${rule.toValue}"');
        buffer.writeln('    emit_stage: ${rule.emitStage}');
        if (rule.params.isNotEmpty) {
          buffer.writeln('    params:');
          for (final entry in rule.params.entries) {
            buffer.writeln('      ${entry.key}: ${_yamlValue(entry.value)}');
          }
        }
      }
    }

    return buffer.toString();
  }

  /// Simple YAML to JSON converter (handles our specific format)
  static Map<String, dynamic> _yamlLinesToJson(List<String> lines) {
    final result = <String, dynamic>{};
    String? currentSection;
    Map<String, dynamic>? currentObject;
    List<dynamic>? currentList;
    int listIndent = 0;

    for (var line in lines) {
      // Skip comments and empty lines
      if (line.trim().startsWith('#') || line.trim().isEmpty) continue;

      final indent = line.length - line.trimLeft().length;
      line = line.trim();

      // Check for list item
      if (line.startsWith('- ')) {
        if (currentList != null) {
          final itemContent = line.substring(2);
          if (itemContent.contains(':')) {
            final item = <String, dynamic>{};
            _parseKeyValue(itemContent, item);
            currentList.add(item);
            currentObject = item;
            listIndent = indent;
          } else {
            currentList.add(itemContent);
          }
        }
        continue;
      }

      // Check for key: value
      if (line.contains(':')) {
        final colonIndex = line.indexOf(':');
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();

        if (indent == 0) {
          // Top-level key
          if (value.isEmpty) {
            // Section header
            currentSection = key;
            if (key == 'mappings' || key == 'derived_rules') {
              currentList = [];
              result[key] = currentList;
              currentObject = null;
            } else {
              currentObject = {};
              result[key] = currentObject;
              currentList = null;
            }
          } else {
            result[key] = _parseValue(value);
            currentSection = null;
            currentObject = null;
            currentList = null;
          }
        } else if (currentObject != null && indent > listIndent) {
          // Nested property
          currentObject[key] = _parseValue(value);
        } else if (currentObject != null) {
          currentObject[key] = _parseValue(value);
        }
      }
    }

    return result;
  }

  static void _parseKeyValue(String content, Map<String, dynamic> target) {
    final colonIndex = content.indexOf(':');
    if (colonIndex > 0) {
      final key = content.substring(0, colonIndex).trim();
      final value = content.substring(colonIndex + 1).trim();
      target[key] = _parseValue(value);
    }
  }

  static dynamic _parseValue(String value) {
    if (value.isEmpty) return null;

    // Remove quotes
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }

    // Try number
    final intVal = int.tryParse(value);
    if (intVal != null) return intVal;

    final doubleVal = double.tryParse(value);
    if (doubleVal != null) return doubleVal;

    // Try boolean
    if (value == 'true') return true;
    if (value == 'false') return false;
    if (value == 'null') return null;

    return value;
  }

  static String _yamlValue(dynamic value) {
    if (value is String) return '"$value"';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    if (value == null) return 'null';
    return '"$value"';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ADAPTER REGISTRY
// ═══════════════════════════════════════════════════════════════════════════

/// Registry for loaded adapters
class AdapterRegistry {
  final Map<String, AdapterConfig> _adapters = {};

  /// Get all registered adapters
  List<AdapterConfig> get adapters => _adapters.values.toList();

  /// Get adapter by ID
  AdapterConfig? getAdapter(String id) => _adapters[id];

  /// Register a new adapter
  void register(AdapterConfig config) {
    _adapters[config.id] = config;
  }

  /// Unregister an adapter
  void unregister(String id) {
    _adapters.remove(id);
  }

  /// Load adapter from YAML string
  AdapterConfig loadFromYaml(String yaml) {
    final config = AdapterConfig.fromYaml(yaml);
    register(config);
    return config;
  }

  /// Load adapter from JSON
  AdapterConfig loadFromJson(Map<String, dynamic> json) {
    final config = AdapterConfig.fromJson(json);
    register(config);
    return config;
  }

  /// Find adapter for company/engine combination
  AdapterConfig? findAdapter(String? company, String? engine) {
    for (final adapter in _adapters.values) {
      if (company != null && adapter.company.toLowerCase().contains(company.toLowerCase())) {
        return adapter;
      }
      if (engine != null && adapter.engine.toLowerCase().contains(engine.toLowerCase())) {
        return adapter;
      }
    }
    return null;
  }

  /// Get built-in generic adapter
  AdapterConfig get genericAdapter => const AdapterConfig(
    id: 'generic',
    company: 'Generic',
    engine: 'Any',
    layer: IngestLayer.directEvent,
    mappings: [
      EventMapping(event: 'spin_start', stage: 'spin_start'),
      EventMapping(event: 'spinStart', stage: 'spin_start'),
      EventMapping(event: 'onSpinStart', stage: 'spin_start'),
      EventMapping(event: 'spin_end', stage: 'spin_end'),
      EventMapping(event: 'spinEnd', stage: 'spin_end'),
      EventMapping(event: 'onSpinEnd', stage: 'spin_end'),
      EventMapping(event: 'reel_stop', stage: 'reel_stop'),
      EventMapping(event: 'reelStop', stage: 'reel_stop'),
      EventMapping(event: 'onReelStop', stage: 'reel_stop'),
      EventMapping(event: 'win_present', stage: 'win_present'),
      EventMapping(event: 'winPresent', stage: 'win_present'),
      EventMapping(event: 'onWinPresent', stage: 'win_present'),
      EventMapping(event: 'bigwin', stage: 'bigwin_tier'),
      EventMapping(event: 'bigWin', stage: 'bigwin_tier'),
      EventMapping(event: 'onBigWin', stage: 'bigwin_tier'),
      EventMapping(event: 'feature_enter', stage: 'feature_enter'),
      EventMapping(event: 'featureEnter', stage: 'feature_enter'),
      EventMapping(event: 'onFeatureEnter', stage: 'feature_enter'),
      EventMapping(event: 'feature_exit', stage: 'feature_exit'),
      EventMapping(event: 'featureExit', stage: 'feature_exit'),
      EventMapping(event: 'onFeatureExit', stage: 'feature_exit'),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT TRANSFORMER
// ═══════════════════════════════════════════════════════════════════════════

/// Transforms engine events to Stage events using adapter config
class EventTransformer {
  final AdapterConfig config;

  EventTransformer(this.config);

  /// Transform an engine event JSON to StageEvent
  StageEvent? transform(Map<String, dynamic> engineEvent) {
    // Get event name from common fields
    final eventName = engineEvent['event'] as String? ??
        engineEvent['type'] as String? ??
        engineEvent['name'] as String? ??
        engineEvent['eventName'] as String?;

    if (eventName == null) return null;

    // Find mapping
    final mapping = config.findMapping(eventName);
    if (mapping == null) return null;

    // Check condition if present
    if (mapping.condition != null) {
      // Simple condition evaluation (expand as needed)
      if (!_evaluateCondition(mapping.condition!, engineEvent)) {
        return null;
      }
    }

    // Extract payload
    final payload = _extractPayload(mapping, engineEvent);

    // Build stage
    final stageJson = <String, dynamic>{
      'type': mapping.stage,
      ...mapping.defaults,
      ...payload,
    };

    final stage = Stage.fromJson(stageJson);

    // Get timestamp
    final timestamp = (engineEvent['timestamp'] as num?)?.toDouble() ??
        (engineEvent['time'] as num?)?.toDouble() ??
        (engineEvent['timestampMs'] as num?)?.toDouble() ??
        0.0;

    return StageEvent(
      stage: stage,
      timestampMs: timestamp,
      sourceEvent: eventName,
    );
  }

  /// Extract payload fields based on mapping
  Map<String, dynamic> _extractPayload(EventMapping mapping, Map<String, dynamic> event) {
    final result = <String, dynamic>{};

    for (final entry in mapping.extract.entries) {
      final targetField = entry.key;
      final sourcePath = entry.value;

      final value = _extractValue(sourcePath, event);
      if (value != null) {
        result[targetField] = value;
      }
    }

    return result;
  }

  /// Extract value using JSONPath-like syntax
  dynamic _extractValue(String path, Map<String, dynamic> data) {
    if (path.startsWith(r'$.')) {
      path = path.substring(2);
    }

    final parts = path.split('.');
    dynamic current = data;

    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        // Try exact match first
        if (current.containsKey(part)) {
          current = current[part];
        } else {
          // Try case-insensitive match
          final key = current.keys.firstWhere(
            (k) => k.toLowerCase() == part.toLowerCase(),
            orElse: () => '',
          );
          if (key.isNotEmpty) {
            current = current[key];
          } else {
            return null;
          }
        }
      } else if (current is List && int.tryParse(part) != null) {
        final index = int.parse(part);
        if (index >= 0 && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    return current;
  }

  /// Simple condition evaluation
  bool _evaluateCondition(String condition, Map<String, dynamic> data) {
    // Support simple conditions like "$.hasWin == true"
    if (condition.contains('==')) {
      final parts = condition.split('==').map((s) => s.trim()).toList();
      if (parts.length == 2) {
        final value = _extractValue(parts[0], data);
        final expected = _parseConditionValue(parts[1]);
        return value == expected;
      }
    }
    if (condition.contains('!=')) {
      final parts = condition.split('!=').map((s) => s.trim()).toList();
      if (parts.length == 2) {
        final value = _extractValue(parts[0], data);
        final expected = _parseConditionValue(parts[1]);
        return value != expected;
      }
    }
    if (condition.contains('>')) {
      final parts = condition.split('>').map((s) => s.trim()).toList();
      if (parts.length == 2) {
        final value = _extractValue(parts[0], data);
        final expected = _parseConditionValue(parts[1]);
        if (value is num && expected is num) {
          return value > expected;
        }
      }
    }
    return true; // Default to true if condition can't be evaluated
  }

  dynamic _parseConditionValue(String value) {
    if (value == 'true') return true;
    if (value == 'false') return false;
    if (value == 'null') return null;
    final numVal = num.tryParse(value);
    if (numVal != null) return numVal;
    // Remove quotes
    if (value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}
