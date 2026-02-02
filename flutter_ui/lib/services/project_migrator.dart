// Project Migrator
//
// Comprehensive project file migration with:
// - Step-by-step version upgrades
// - Backup before migration
// - Rollback support
// - Detailed migration logging
// - Safe defaults for missing fields

import 'dart:convert';
import '../models/project_schema.dart';
import '../models/validation_error.dart';
import 'project_schema_validator.dart';

/// Migration strategy for a specific version upgrade
typedef VersionMigrator = Map<String, dynamic> Function(Map<String, dynamic> data);

/// Result of a migration attempt
class ProjectMigrationResult {
  /// Whether the migration was successful
  final bool success;

  /// Original data (for rollback)
  final Map<String, dynamic>? originalData;

  /// Migrated data (if successful)
  final Map<String, dynamic>? migratedData;

  /// From version
  final int fromVersion;

  /// To version
  final int toVersion;

  /// Error message (if failed)
  final String? error;

  /// Warnings generated during migration
  final List<String> warnings;

  /// Changes made during migration
  final List<MigrationChange> changes;

  /// Validation result after migration
  final ValidationResult? validationResult;

  const ProjectMigrationResult({
    required this.success,
    this.originalData,
    this.migratedData,
    required this.fromVersion,
    required this.toVersion,
    this.error,
    this.warnings = const [],
    this.changes = const [],
    this.validationResult,
  });

  factory ProjectMigrationResult.success({
    required Map<String, dynamic> originalData,
    required Map<String, dynamic> migratedData,
    required int fromVersion,
    required int toVersion,
    List<String> warnings = const [],
    List<MigrationChange> changes = const [],
    ValidationResult? validationResult,
  }) {
    return ProjectMigrationResult(
      success: true,
      originalData: originalData,
      migratedData: migratedData,
      fromVersion: fromVersion,
      toVersion: toVersion,
      warnings: warnings,
      changes: changes,
      validationResult: validationResult,
    );
  }

  factory ProjectMigrationResult.failure({
    required Map<String, dynamic> originalData,
    required int fromVersion,
    required String error,
  }) {
    return ProjectMigrationResult(
      success: false,
      originalData: originalData,
      fromVersion: fromVersion,
      toVersion: fromVersion,
      error: error,
    );
  }

  /// Rollback to original data
  Map<String, dynamic>? rollback() => originalData;
}

/// Single change made during migration
class MigrationChange {
  final String path;
  final MigrationChangeType type;
  final dynamic oldValue;
  final dynamic newValue;
  final String description;

  const MigrationChange({
    required this.path,
    required this.type,
    this.oldValue,
    this.newValue,
    required this.description,
  });

  @override
  String toString() => '[$type] $path: $description';

  Map<String, dynamic> toJson() => {
        'path': path,
        'type': type.name,
        if (oldValue != null) 'oldValue': oldValue,
        if (newValue != null) 'newValue': newValue,
        'description': description,
      };
}

enum MigrationChangeType {
  added,
  removed,
  modified,
  renamed,
  typeChanged,
}

/// Project migration service with version-specific migrations
class ProjectMigrator {
  // Singleton
  static final ProjectMigrator _instance = ProjectMigrator._internal();
  static ProjectMigrator get instance => _instance;
  ProjectMigrator._internal();

  // Version-specific migration functions
  final Map<int, _MigrationDefinition> _migrations = {
    // v1 → v2: Add bus hierarchy
    2: _MigrationDefinition(
      description: 'Add bus hierarchy and effect chains',
      migrate: _migrateV1toV2,
    ),

    // v2 → v3: Add RTPC system
    3: _MigrationDefinition(
      description: 'Add RTPC definitions and bindings',
      migrate: _migrateV2toV3,
    ),

    // v3 → v4: Add aux sends
    4: _MigrationDefinition(
      description: 'Add aux send routing system',
      migrate: _migrateV3toV4,
    ),

    // v4 → v5: Add STAGES protocol
    5: _MigrationDefinition(
      description: 'Add STAGES protocol and stage mappings',
      migrate: _migrateV4toV5,
    ),
  };

  /// Migrate project data to target version (default: latest)
  ProjectMigrationResult migrate(
    Map<String, dynamic> data, {
    int? targetVersion,
  }) {
    targetVersion ??= kCurrentSchemaVersion;

    // Deep copy original for rollback
    final originalData = _deepCopy(data);
    final fromVersion = _extractVersion(data);

    // Already at target version
    if (fromVersion >= targetVersion) {
      return ProjectMigrationResult.success(
        originalData: originalData,
        migratedData: data,
        fromVersion: fromVersion,
        toVersion: fromVersion,
      );
    }

    // Too old to migrate
    if (fromVersion < kMinSupportedSchemaVersion) {
      return ProjectMigrationResult.failure(
        originalData: originalData,
        fromVersion: fromVersion,
        error: 'Schema version $fromVersion is too old. '
            'Minimum supported: $kMinSupportedSchemaVersion',
      );
    }

    // Apply migrations step by step
    var currentData = _deepCopy(data);
    final allChanges = <MigrationChange>[];
    final allWarnings = <String>[];

    for (int v = fromVersion + 1; v <= targetVersion; v++) {
      final migration = _migrations[v];
      if (migration == null) {
        return ProjectMigrationResult.failure(
          originalData: originalData,
          fromVersion: fromVersion,
          error: 'No migration defined for version $v',
        );
      }

      try {
        final result = migration.migrate(currentData);
        currentData = result.data;
        allChanges.addAll(result.changes);
        allWarnings.addAll(result.warnings);

        // Update version in data
        currentData['schema_version'] = v;
      } catch (e) {
        return ProjectMigrationResult.failure(
          originalData: originalData,
          fromVersion: fromVersion,
          error: 'Migration to v$v failed: $e',
        );
      }
    }

    // Add migration metadata
    currentData['_last_migration'] = {
      'from_version': fromVersion,
      'to_version': targetVersion,
      'migrated_at': DateTime.now().toIso8601String(),
      'changes_count': allChanges.length,
    };

    // Validate migrated data
    final validationResult = ProjectSchemaValidator.instance.validateProject(currentData);

    return ProjectMigrationResult.success(
      originalData: originalData,
      migratedData: currentData,
      fromVersion: fromVersion,
      toVersion: targetVersion,
      warnings: allWarnings,
      changes: allChanges,
      validationResult: validationResult,
    );
  }

  /// Migrate from JSON string
  ProjectMigrationResult migrateFromJson(String jsonString, {int? targetVersion}) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      return migrate(data, targetVersion: targetVersion);
    } catch (e) {
      return ProjectMigrationResult(
        success: false,
        fromVersion: 0,
        toVersion: 0,
        error: 'Invalid JSON: $e',
      );
    }
  }

  /// Check if migration is needed
  bool needsMigration(Map<String, dynamic> data) {
    final version = _extractVersion(data);
    return version < kCurrentSchemaVersion;
  }

  /// Get migration path (list of steps needed)
  List<String> getMigrationPath(Map<String, dynamic> data) {
    final fromVersion = _extractVersion(data);
    if (fromVersion >= kCurrentSchemaVersion) return [];

    final path = <String>[];
    for (int v = fromVersion + 1; v <= kCurrentSchemaVersion; v++) {
      final migration = _migrations[v];
      if (migration != null) {
        path.add('v${v - 1} → v$v: ${migration.description}');
      }
    }
    return path;
  }

  // =========================================================================
  // PRIVATE HELPERS
  // =========================================================================

  int _extractVersion(Map<String, dynamic> data) {
    if (data.containsKey('schema_version')) {
      final v = data['schema_version'];
      if (v is int) return v;
      if (v is double) return v.toInt();
    }
    if (data.containsKey('version')) {
      final v = data['version'];
      if (v is int) return v;
    }
    return 1;
  }

  Map<String, dynamic> _deepCopy(Map<String, dynamic> data) {
    return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }
}

// =============================================================================
// MIGRATION DEFINITION
// =============================================================================

class _MigrationDefinition {
  final String description;
  final _MigrationResult Function(Map<String, dynamic>) migrate;

  const _MigrationDefinition({
    required this.description,
    required this.migrate,
  });
}

class _MigrationResult {
  final Map<String, dynamic> data;
  final List<MigrationChange> changes;
  final List<String> warnings;

  const _MigrationResult({
    required this.data,
    this.changes = const [],
    this.warnings = const [],
  });
}

// =============================================================================
// VERSION-SPECIFIC MIGRATIONS
// =============================================================================

/// v1 → v2: Add bus hierarchy and effect chains
_MigrationResult _migrateV1toV2(Map<String, dynamic> data) {
  final changes = <MigrationChange>[];
  final warnings = <String>[];

  // Add default bus hierarchy if missing
  if (!data.containsKey('bus_hierarchy')) {
    data['bus_hierarchy'] = {
      'buses': [
        {'id': 0, 'name': 'Master', 'parent_id': null, 'volume': 1.0, 'mute': false},
        {'id': 1, 'name': 'Music', 'parent_id': 0, 'volume': 1.0, 'mute': false},
        {'id': 2, 'name': 'SFX', 'parent_id': 0, 'volume': 1.0, 'mute': false},
        {'id': 3, 'name': 'Voice', 'parent_id': 0, 'volume': 1.0, 'mute': false},
        {'id': 4, 'name': 'UI', 'parent_id': 0, 'volume': 1.0, 'mute': false},
        {'id': 5, 'name': 'Ambience', 'parent_id': 0, 'volume': 1.0, 'mute': false},
      ],
    };
    changes.add(const MigrationChange(
      path: 'bus_hierarchy',
      type: MigrationChangeType.added,
      newValue: '6 buses',
      description: 'Added default bus hierarchy with Master, Music, SFX, Voice, UI, Ambience',
    ));
  }

  // Migrate tracks to use bus routing
  if (data.containsKey('tracks') || (data.containsKey('daw') && data['daw']?['tracks'] != null)) {
    final tracks = data['tracks'] as List? ?? (data['daw'] as Map?)?['tracks'] as List? ?? [];
    int tracksUpdated = 0;

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i] as Map<String, dynamic>?;
      if (track != null && !track.containsKey('output_bus_id')) {
        // Guess bus based on track name
        final name = (track['name'] as String? ?? '').toLowerCase();
        int busId = 2; // Default to SFX
        if (name.contains('music') || name.contains('bgm')) busId = 1;
        if (name.contains('voice') || name.contains('vo')) busId = 3;
        if (name.contains('ui') || name.contains('click')) busId = 4;
        if (name.contains('ambient') || name.contains('atmo')) busId = 5;
        track['output_bus_id'] = busId;
        tracksUpdated++;
      }
    }

    if (tracksUpdated > 0) {
      changes.add(MigrationChange(
        path: 'tracks',
        type: MigrationChangeType.modified,
        description: 'Added output_bus_id to $tracksUpdated tracks',
      ));
    }
  }

  return _MigrationResult(data: data, changes: changes, warnings: warnings);
}

/// v2 → v3: Add RTPC system
_MigrationResult _migrateV2toV3(Map<String, dynamic> data) {
  final changes = <MigrationChange>[];
  final warnings = <String>[];

  // Add empty RTPC definitions
  if (!data.containsKey('rtpc_definitions')) {
    data['rtpc_definitions'] = [];
    changes.add(const MigrationChange(
      path: 'rtpc_definitions',
      type: MigrationChangeType.added,
      newValue: '[]',
      description: 'Added empty RTPC definitions array',
    ));
  }

  // Add empty RTPC bindings
  if (!data.containsKey('rtpc_bindings')) {
    data['rtpc_bindings'] = [];
    changes.add(const MigrationChange(
      path: 'rtpc_bindings',
      type: MigrationChangeType.added,
      newValue: '[]',
      description: 'Added empty RTPC bindings array',
    ));
  }

  // Add RTPC system config
  if (!data.containsKey('rtpc_config')) {
    data['rtpc_config'] = {
      'update_rate_hz': 60,
      'interpolation_enabled': true,
      'default_curve': 'linear',
    };
    changes.add(const MigrationChange(
      path: 'rtpc_config',
      type: MigrationChangeType.added,
      description: 'Added RTPC system configuration with 60Hz update rate',
    ));
  }

  return _MigrationResult(data: data, changes: changes, warnings: warnings);
}

/// v3 → v4: Add aux sends
_MigrationResult _migrateV3toV4(Map<String, dynamic> data) {
  final changes = <MigrationChange>[];
  final warnings = <String>[];

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
      {
        'id': 103,
        'name': 'Slapback',
        'effect_type': 'delay',
        'return_level': 1.0,
        'params': {'time_ms': 80, 'feedback': 0.1, 'ping_pong': false},
      },
    ];
    changes.add(const MigrationChange(
      path: 'aux_buses',
      type: MigrationChangeType.added,
      description: 'Added 4 default aux buses: Reverb A, Reverb B, Delay, Slapback',
    ));
  }

  // Add aux sends array
  if (!data.containsKey('aux_sends')) {
    data['aux_sends'] = [];
    changes.add(const MigrationChange(
      path: 'aux_sends',
      type: MigrationChangeType.added,
      newValue: '[]',
      description: 'Added empty aux sends array',
    ));
  }

  return _MigrationResult(data: data, changes: changes, warnings: warnings);
}

/// v4 → v5: Add STAGES protocol
_MigrationResult _migrateV4toV5(Map<String, dynamic> data) {
  final changes = <MigrationChange>[];
  final warnings = <String>[];

  // Add stage definitions
  if (!data.containsKey('stage_definitions')) {
    data['stage_definitions'] = {
      'canonical_stages': [
        'SPIN_START', 'SPIN_END', 'REEL_SPIN_LOOP',
        'REEL_STOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2', 'REEL_STOP_3', 'REEL_STOP_4',
        'ANTICIPATION_ON', 'ANTICIPATION_OFF',
        'WIN_PRESENT', 'WIN_LINE_SHOW', 'WIN_LINE_HIDE',
        'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END',
        'BIGWIN_TIER', 'BIG_WIN_LOOP', 'BIG_WIN_COINS',
        'FEATURE_ENTER', 'FEATURE_STEP', 'FEATURE_EXIT',
        'CASCADE_START', 'CASCADE_STEP', 'CASCADE_END',
        'FREESPIN_START', 'FREESPIN_END',
        'JACKPOT_TRIGGER', 'JACKPOT_AWARD',
        'BONUS_ENTER', 'BONUS_EXIT',
        'GAMBLE_ENTER', 'GAMBLE_EXIT',
      ],
      'custom_stages': [],
    };
    changes.add(const MigrationChange(
      path: 'stage_definitions',
      type: MigrationChangeType.added,
      description: 'Added STAGES protocol with 30+ canonical stages',
    ));
  }

  // Add stage-to-audio mappings
  if (!data.containsKey('stage_audio_mappings')) {
    data['stage_audio_mappings'] = [];
    changes.add(const MigrationChange(
      path: 'stage_audio_mappings',
      type: MigrationChangeType.added,
      newValue: '[]',
      description: 'Added empty stage-to-audio mappings array',
    ));
  }

  // Add engine adapter config
  if (!data.containsKey('engine_adapter')) {
    data['engine_adapter'] = {
      'type': 'none',
      'config': {},
    };
    changes.add(const MigrationChange(
      path: 'engine_adapter',
      type: MigrationChangeType.added,
      description: 'Added engine adapter configuration (none by default)',
    ));
  }

  // Migrate old slot_events to stage_audio_mappings
  if (data.containsKey('slot_events')) {
    final slotEvents = data['slot_events'] as List? ?? [];
    final mappings = data['stage_audio_mappings'] as List? ?? [];
    int migratedCount = 0;

    for (final event in slotEvents) {
      if (event is Map<String, dynamic>) {
        final stageName = _convertOldEventToStage(event['type'] as String? ?? '');
        if (stageName.isNotEmpty) {
          mappings.add({
            'stage': stageName,
            'audio_asset': event['audio_path'],
            'bus_id': event['bus_id'] ?? 2,
            'volume': event['volume'] ?? 1.0,
            'migrated_from': 'slot_events',
          });
          migratedCount++;
        }
      }
    }

    if (migratedCount > 0) {
      data['stage_audio_mappings'] = mappings;
      changes.add(MigrationChange(
        path: 'stage_audio_mappings',
        type: MigrationChangeType.modified,
        description: 'Migrated $migratedCount events from slot_events to stage_audio_mappings',
      ));
    }

    // Preserve old data with deprecation marker
    data['_deprecated_slot_events'] = data['slot_events'];
    data.remove('slot_events');
    changes.add(const MigrationChange(
      path: 'slot_events',
      type: MigrationChangeType.renamed,
      newValue: '_deprecated_slot_events',
      description: 'Renamed slot_events to _deprecated_slot_events (preserved for reference)',
    ));

    warnings.add('slot_events migrated to stage_audio_mappings. '
        'Original data preserved in _deprecated_slot_events.');
  }

  return _MigrationResult(data: data, changes: changes, warnings: warnings);
}

/// Convert old event type to STAGES canonical name
String _convertOldEventToStage(String oldType) {
  return switch (oldType.toLowerCase()) {
    'spin' || 'spin_start' => 'SPIN_START',
    'stop' || 'spin_stop' || 'spin_end' => 'SPIN_END',
    'reel_spin' || 'reel_spinning' => 'REEL_SPIN_LOOP',
    'reel_stop' || 'reel' => 'REEL_STOP',
    'anticipation' || 'anticipation_start' || 'anticipation_on' => 'ANTICIPATION_ON',
    'anticipation_end' || 'anticipation_off' => 'ANTICIPATION_OFF',
    'win' || 'win_present' => 'WIN_PRESENT',
    'win_line' || 'win_line_show' => 'WIN_LINE_SHOW',
    'rollup' || 'rollup_start' => 'ROLLUP_START',
    'rollup_tick' => 'ROLLUP_TICK',
    'rollup_end' => 'ROLLUP_END',
    'bigwin' || 'big_win' => 'BIGWIN_TIER',
    'feature' || 'feature_start' || 'feature_enter' => 'FEATURE_ENTER',
    'feature_end' || 'feature_exit' => 'FEATURE_EXIT',
    'cascade' || 'cascade_start' => 'CASCADE_START',
    'cascade_step' => 'CASCADE_STEP',
    'cascade_end' => 'CASCADE_END',
    'freespin' || 'freespin_start' || 'free_spin' => 'FREESPIN_START',
    'freespin_end' => 'FREESPIN_END',
    'jackpot' || 'jackpot_trigger' => 'JACKPOT_TRIGGER',
    'jackpot_award' => 'JACKPOT_AWARD',
    'bonus' || 'bonus_start' || 'bonus_enter' => 'BONUS_ENTER',
    'bonus_end' || 'bonus_exit' => 'BONUS_EXIT',
    'gamble' || 'gamble_start' || 'gamble_enter' => 'GAMBLE_ENTER',
    'gamble_end' || 'gamble_exit' => 'GAMBLE_EXIT',
    _ => '',
  };
}
