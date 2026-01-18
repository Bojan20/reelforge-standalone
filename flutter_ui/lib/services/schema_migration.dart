// Schema Migration Service
//
// Automatic project file migration between schema versions:
// - Version detection from project JSON
// - Step-by-step migration through intermediate versions
// - Backup before migration
// - Rollback support on failure
// - Migration audit log

import 'dart:convert';

// =============================================================================
// SCHEMA VERSION CONSTANTS
// =============================================================================

/// Current schema version (increment when making breaking changes)
const int currentSchemaVersion = 5;

/// Minimum supported schema version for migration
const int minSupportedVersion = 1;

// =============================================================================
// MIGRATION RESULT
// =============================================================================

/// Result of a migration operation
class MigrationResult {
  final bool success;
  final int fromVersion;
  final int toVersion;
  final String? error;
  final List<String> warnings;
  final List<MigrationStep> stepsApplied;
  final Map<String, dynamic>? migratedData;

  const MigrationResult({
    required this.success,
    required this.fromVersion,
    required this.toVersion,
    this.error,
    this.warnings = const [],
    this.stepsApplied = const [],
    this.migratedData,
  });

  factory MigrationResult.failure(int fromVersion, String error) {
    return MigrationResult(
      success: false,
      fromVersion: fromVersion,
      toVersion: fromVersion,
      error: error,
    );
  }
}

/// Single migration step record
class MigrationStep {
  final int fromVersion;
  final int toVersion;
  final String description;
  final DateTime appliedAt;
  final List<String> changes;

  const MigrationStep({
    required this.fromVersion,
    required this.toVersion,
    required this.description,
    required this.appliedAt,
    this.changes = const [],
  });

  Map<String, dynamic> toJson() => {
    'from_version': fromVersion,
    'to_version': toVersion,
    'description': description,
    'applied_at': appliedAt.toIso8601String(),
    'changes': changes,
  };
}

// =============================================================================
// MIGRATION FUNCTION TYPE
// =============================================================================

/// Migration function signature
typedef MigrationFn = Map<String, dynamic> Function(Map<String, dynamic> data);

// =============================================================================
// SCHEMA MIGRATION SERVICE
// =============================================================================

/// Service for managing project schema migrations
class SchemaMigrationService {
  /// Registry of migration functions: version -> migration function
  static final Map<int, _MigrationInfo> _migrations = {
    // v1 -> v2: Added bus hierarchy
    2: _MigrationInfo(
      description: 'Added bus hierarchy and effect chains',
      migrate: _migrateV1toV2,
    ),

    // v2 -> v3: Added RTPC system
    3: _MigrationInfo(
      description: 'Added RTPC definitions and bindings',
      migrate: _migrateV2toV3,
    ),

    // v3 -> v4: Added aux sends
    4: _MigrationInfo(
      description: 'Added aux send routing system',
      migrate: _migrateV3toV4,
    ),

    // v4 -> v5: Added stage events
    5: _MigrationInfo(
      description: 'Added STAGES protocol and stage mappings',
      migrate: _migrateV4toV5,
    ),
  };

  /// Check if a project needs migration
  static bool needsMigration(Map<String, dynamic> projectData) {
    final version = _getSchemaVersion(projectData);
    return version < currentSchemaVersion;
  }

  /// Get schema version from project data
  static int _getSchemaVersion(Map<String, dynamic> data) {
    // Try multiple locations for version field
    if (data.containsKey('schema_version')) {
      return data['schema_version'] as int? ?? 1;
    }
    if (data.containsKey('version')) {
      return data['version'] as int? ?? 1;
    }
    if (data.containsKey('meta')) {
      final meta = data['meta'] as Map<String, dynamic>?;
      if (meta != null && meta.containsKey('schema_version')) {
        return meta['schema_version'] as int? ?? 1;
      }
    }
    // No version found = version 1 (legacy)
    return 1;
  }

  /// Migrate project data to current schema version
  static MigrationResult migrate(Map<String, dynamic> projectData) {
    final fromVersion = _getSchemaVersion(projectData);

    // Already current
    if (fromVersion >= currentSchemaVersion) {
      return MigrationResult(
        success: true,
        fromVersion: fromVersion,
        toVersion: fromVersion,
        migratedData: projectData,
      );
    }

    // Too old to migrate
    if (fromVersion < minSupportedVersion) {
      return MigrationResult.failure(
        fromVersion,
        'Schema version $fromVersion is too old. Minimum supported: $minSupportedVersion',
      );
    }

    // Deep copy to avoid modifying original
    var data = _deepCopy(projectData);
    final stepsApplied = <MigrationStep>[];
    final warnings = <String>[];

    // Apply migrations step by step
    for (int v = fromVersion + 1; v <= currentSchemaVersion; v++) {
      final migration = _migrations[v];
      if (migration == null) {
        return MigrationResult.failure(
          fromVersion,
          'No migration found for version $v',
        );
      }

      try {
        final changes = <String>[];
        final beforeKeys = data.keys.toSet();

        // Apply migration
        data = migration.migrate(data);

        // Track changes
        final afterKeys = data.keys.toSet();
        final added = afterKeys.difference(beforeKeys);
        final removed = beforeKeys.difference(afterKeys);

        for (final key in added) {
          changes.add('Added: $key');
        }
        for (final key in removed) {
          changes.add('Removed: $key');
        }

        // Update schema version in data
        data['schema_version'] = v;

        stepsApplied.add(MigrationStep(
          fromVersion: v - 1,
          toVersion: v,
          description: migration.description,
          appliedAt: DateTime.now(),
          changes: changes,
        ));

      } catch (e) {
        return MigrationResult.failure(
          fromVersion,
          'Migration to v$v failed: $e',
        );
      }
    }

    // Add migration history to project
    data['_migration_history'] = stepsApplied.map((s) => s.toJson()).toList();

    return MigrationResult(
      success: true,
      fromVersion: fromVersion,
      toVersion: currentSchemaVersion,
      warnings: warnings,
      stepsApplied: stepsApplied,
      migratedData: data,
    );
  }

  /// Migrate from JSON string
  static MigrationResult migrateJson(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      return migrate(data);
    } catch (e) {
      return MigrationResult.failure(0, 'Invalid JSON: $e');
    }
  }

  /// Get migration path description
  static List<String> getMigrationPath(int fromVersion) {
    final path = <String>[];
    for (int v = fromVersion + 1; v <= currentSchemaVersion; v++) {
      final migration = _migrations[v];
      if (migration != null) {
        path.add('v${v - 1} → v$v: ${migration.description}');
      }
    }
    return path;
  }

  /// Deep copy a map
  static Map<String, dynamic> _deepCopy(Map<String, dynamic> data) {
    return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }
}

// =============================================================================
// MIGRATION INFO
// =============================================================================

class _MigrationInfo {
  final String description;
  final MigrationFn migrate;

  const _MigrationInfo({
    required this.description,
    required this.migrate,
  });
}

// =============================================================================
// MIGRATION FUNCTIONS
// =============================================================================

/// v1 -> v2: Add bus hierarchy
Map<String, dynamic> _migrateV1toV2(Map<String, dynamic> data) {
  // Add default bus hierarchy if not present
  if (!data.containsKey('bus_hierarchy')) {
    data['bus_hierarchy'] = {
      'buses': [
        {'id': 0, 'name': 'Master', 'parent_id': null, 'volume': 1.0, 'mute': false},
        {'id': 1, 'name': 'Music', 'parent_id': 0, 'volume': 1.0, 'mute': false},
        {'id': 2, 'name': 'SFX', 'parent_id': 0, 'volume': 1.0, 'mute': false},
        {'id': 3, 'name': 'Voice', 'parent_id': 0, 'volume': 1.0, 'mute': false},
        {'id': 4, 'name': 'UI', 'parent_id': 0, 'volume': 1.0, 'mute': false},
      ],
    };
  }

  // Migrate old 'tracks' to use bus routing
  if (data.containsKey('tracks')) {
    final tracks = data['tracks'] as List? ?? [];
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i] as Map<String, dynamic>?;
      if (track != null && !track.containsKey('output_bus_id')) {
        // Guess bus based on track name
        final name = (track['name'] as String? ?? '').toLowerCase();
        int busId = 2; // Default to SFX
        if (name.contains('music') || name.contains('bgm')) busId = 1;
        if (name.contains('voice') || name.contains('vo')) busId = 3;
        if (name.contains('ui') || name.contains('click')) busId = 4;
        track['output_bus_id'] = busId;
      }
    }
  }

  return data;
}

/// v2 -> v3: Add RTPC system
Map<String, dynamic> _migrateV2toV3(Map<String, dynamic> data) {
  // Add empty RTPC definitions
  if (!data.containsKey('rtpc_definitions')) {
    data['rtpc_definitions'] = [];
  }

  // Add empty RTPC bindings
  if (!data.containsKey('rtpc_bindings')) {
    data['rtpc_bindings'] = [];
  }

  // Add RTPC system config
  if (!data.containsKey('rtpc_config')) {
    data['rtpc_config'] = {
      'update_rate_hz': 60,
      'interpolation_enabled': true,
      'default_curve': 'linear',
    };
  }

  return data;
}

/// v3 -> v4: Add aux sends
Map<String, dynamic> _migrateV3toV4(Map<String, dynamic> data) {
  // Add aux buses
  if (!data.containsKey('aux_buses')) {
    data['aux_buses'] = [
      {
        'id': 100,
        'name': 'Reverb A',
        'effect_type': 'reverb',
        'return_level': 1.0,
        'params': {'room_size': 0.5, 'damping': 0.4, 'decay': 1.8},
      },
      {
        'id': 101,
        'name': 'Reverb B',
        'effect_type': 'reverb',
        'return_level': 1.0,
        'params': {'room_size': 0.8, 'damping': 0.3, 'decay': 4.0},
      },
      {
        'id': 102,
        'name': 'Delay',
        'effect_type': 'delay',
        'return_level': 1.0,
        'params': {'time_ms': 250, 'feedback': 0.3, 'ping_pong': true},
      },
    ];
  }

  // Add aux sends array
  if (!data.containsKey('aux_sends')) {
    data['aux_sends'] = [];
  }

  return data;
}

/// v4 -> v5: Add STAGES protocol
Map<String, dynamic> _migrateV4toV5(Map<String, dynamic> data) {
  // Add stage definitions
  if (!data.containsKey('stage_definitions')) {
    data['stage_definitions'] = {
      'canonical_stages': [
        'SPIN_START', 'SPIN_STOP', 'REEL_STOP',
        'ANTICIPATION_ON', 'ANTICIPATION_OFF',
        'WIN_PRESENT', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END',
        'BIGWIN_TIER', 'FEATURE_ENTER', 'FEATURE_STEP', 'FEATURE_EXIT',
        'CASCADE_STEP', 'JACKPOT_TRIGGER', 'BONUS_ENTER', 'BONUS_EXIT',
      ],
      'custom_stages': [],
    };
  }

  // Add stage-to-audio mappings
  if (!data.containsKey('stage_audio_mappings')) {
    data['stage_audio_mappings'] = [];
  }

  // Add engine adapter config
  if (!data.containsKey('engine_adapter')) {
    data['engine_adapter'] = {
      'type': 'none',
      'config': {},
    };
  }

  // Migrate old slot events to stage mappings
  if (data.containsKey('slot_events')) {
    final slotEvents = data['slot_events'] as List? ?? [];
    final mappings = data['stage_audio_mappings'] as List? ?? [];

    for (final event in slotEvents) {
      if (event is Map<String, dynamic>) {
        final stageName = _convertOldEventToStage(event['type'] as String? ?? '');
        if (stageName.isNotEmpty) {
          mappings.add({
            'stage': stageName,
            'audio_asset': event['audio_path'],
            'bus_id': event['bus_id'] ?? 2,
            'volume': event['volume'] ?? 1.0,
          });
        }
      }
    }

    data['stage_audio_mappings'] = mappings;
    // Keep old slot_events for backward compatibility, mark as deprecated
    data['_deprecated_slot_events'] = data['slot_events'];
    data.remove('slot_events');
  }

  return data;
}

/// Convert old event type to STAGES canonical name
String _convertOldEventToStage(String oldType) {
  return switch (oldType.toLowerCase()) {
    'spin' || 'spin_start' => 'SPIN_START',
    'stop' || 'spin_stop' => 'SPIN_STOP',
    'reel_stop' || 'reel' => 'REEL_STOP',
    'anticipation' || 'anticipation_start' => 'ANTICIPATION_ON',
    'anticipation_end' => 'ANTICIPATION_OFF',
    'win' || 'win_present' => 'WIN_PRESENT',
    'rollup' || 'rollup_start' => 'ROLLUP_START',
    'rollup_end' => 'ROLLUP_END',
    'bigwin' || 'big_win' => 'BIGWIN_TIER',
    'feature' || 'feature_start' => 'FEATURE_ENTER',
    'feature_end' => 'FEATURE_EXIT',
    'cascade' => 'CASCADE_STEP',
    'jackpot' => 'JACKPOT_TRIGGER',
    'bonus' || 'bonus_start' => 'BONUS_ENTER',
    'bonus_end' => 'BONUS_EXIT',
    _ => '',
  };
}

// =============================================================================
// PROJECT FILE WRAPPER
// =============================================================================

/// Wrapper for project files with version awareness
class VersionedProject {
  final int schemaVersion;
  final Map<String, dynamic> data;
  final List<MigrationStep> migrationHistory;
  final bool wasMigrated;

  const VersionedProject({
    required this.schemaVersion,
    required this.data,
    this.migrationHistory = const [],
    this.wasMigrated = false,
  });

  /// Load project from JSON with automatic migration
  static Future<VersionedProject> load(String jsonString) async {
    final rawData = jsonDecode(jsonString) as Map<String, dynamic>;

    if (SchemaMigrationService.needsMigration(rawData)) {
      final result = SchemaMigrationService.migrate(rawData);
      if (!result.success) {
        throw Exception('Migration failed: ${result.error}');
      }
      return VersionedProject(
        schemaVersion: result.toVersion,
        data: result.migratedData!,
        migrationHistory: result.stepsApplied,
        wasMigrated: true,
      );
    }

    return VersionedProject(
      schemaVersion: currentSchemaVersion,
      data: rawData,
    );
  }

  /// Save project to JSON
  String toJson() {
    final saveData = Map<String, dynamic>.from(data);
    saveData['schema_version'] = currentSchemaVersion;
    saveData['saved_at'] = DateTime.now().toIso8601String();
    return jsonEncode(saveData);
  }

  /// Create a new empty project
  factory VersionedProject.empty(String name) {
    return VersionedProject(
      schemaVersion: currentSchemaVersion,
      data: {
        'schema_version': currentSchemaVersion,
        'name': name,
        'created_at': DateTime.now().toIso8601String(),
        'tracks': [],
        'bus_hierarchy': {
          'buses': [
            {'id': 0, 'name': 'Master', 'parent_id': null, 'volume': 1.0},
            {'id': 1, 'name': 'Music', 'parent_id': 0, 'volume': 1.0},
            {'id': 2, 'name': 'SFX', 'parent_id': 0, 'volume': 1.0},
            {'id': 3, 'name': 'Voice', 'parent_id': 0, 'volume': 1.0},
            {'id': 4, 'name': 'UI', 'parent_id': 0, 'volume': 1.0},
          ],
        },
        'rtpc_definitions': [],
        'rtpc_bindings': [],
        'aux_buses': [],
        'aux_sends': [],
        'stage_definitions': {'canonical_stages': [], 'custom_stages': []},
        'stage_audio_mappings': [],
      },
    );
  }
}
