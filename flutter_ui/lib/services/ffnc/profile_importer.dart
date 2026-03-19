/// Profile Importer — loads FluxForge audio profile (.zip) archives and applies to project.
///
/// Supports preview (inspect without applying), audio path remapping,
/// and conflict resolution (skip, overwrite, merge).

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../models/slot_audio_events.dart';
import '../../models/win_tier_config.dart';
import '../../models/slot_lab_models.dart';
import 'profile_exporter.dart';

/// Preview of profile contents (before applying).
class ProfilePreview {
  final ProfileManifest manifest;
  final int eventCount;
  final int winTierCount;
  final int musicLayerCount;
  final String readme;
  final List<String> eventStages;

  const ProfilePreview({
    required this.manifest,
    required this.eventCount,
    required this.winTierCount,
    required this.musicLayerCount,
    required this.readme,
    required this.eventStages,
  });
}

enum ConflictResolution { skip, overwrite, merge }

class ProfileImportOptions {
  final bool importEvents;
  final bool importWinTiers;
  final bool importMusicLayers;
  final String? remapAudioFolder;
  final ConflictResolution conflict;

  const ProfileImportOptions({
    this.importEvents = true,
    this.importWinTiers = true,
    this.importMusicLayers = true,
    this.remapAudioFolder,
    this.conflict = ConflictResolution.overwrite,
  });
}

class ProfileImportResult {
  final int eventsImported;
  final int eventsSkipped;
  final int remapSucceeded;
  final int remapFailed;
  final List<String> remapMissing;
  final bool winTiersApplied;
  final bool musicLayersApplied;

  const ProfileImportResult({
    this.eventsImported = 0,
    this.eventsSkipped = 0,
    this.remapSucceeded = 0,
    this.remapFailed = 0,
    this.remapMissing = const [],
    this.winTiersApplied = false,
    this.musicLayersApplied = false,
  });
}

class ProfileImporter {
  ProfileImporter._();

  /// Preview profile contents without applying.
  static Future<ProfilePreview?> preview(String profilePath) async {
    final extracted = await _extractArchive(profilePath);
    if (extracted == null) return null;

    final manifest = _parseManifest(extracted);
    final events = _parseEvents(extracted);
    final winConfig = _parseWinTiers(extracted);
    final musicConfig = _parseMusicLayers(extracted);
    final readme = _readText(extracted, 'README.txt') ?? '(no README)';

    final stages = events
        .expand((e) => e.triggerStages)
        .toSet()
        .toList()
      ..sort();

    return ProfilePreview(
      manifest: manifest,
      eventCount: events.length,
      winTierCount: (winConfig?.regularWins.tiers.length ?? 0) +
          (winConfig?.bigWins.tiers.length ?? 0),
      musicLayerCount: musicConfig?.thresholds.length ?? 0,
      readme: readme,
      eventStages: stages,
    );
  }

  /// Import profile and apply to project.
  static Future<ProfileImportResult> import_({
    required String profilePath,
    required ProfileImportOptions options,
    required void Function(String stage, String audioPath) setAudioAssignment,
    required void Function(SlotCompositeEvent event) addOrUpdateEvent,
    required List<SlotCompositeEvent> existingEvents,
    void Function(SlotWinConfiguration config)? applyWinTiers,
    void Function(MusicLayerConfig config)? applyMusicLayers,
  }) async {
    final extracted = await _extractArchive(profilePath);
    if (extracted == null) {
      return const ProfileImportResult();
    }

    int eventsImported = 0;
    int eventsSkipped = 0;
    int remapSucceeded = 0;
    int remapFailed = 0;
    final remapMissing = <String>[];

    // Import events
    if (options.importEvents) {
      final events = _parseEvents(extracted);
      final assignments = _parseAssignments(extracted);
      final existingIds = existingEvents.map((e) => e.id).toSet();

      for (final event in events) {
        // Conflict resolution
        if (existingIds.contains(event.id)) {
          switch (options.conflict) {
            case ConflictResolution.skip:
              eventsSkipped++;
              continue;
            case ConflictResolution.overwrite:
              break; // Continue to apply
            case ConflictResolution.merge:
              break; // TODO: merge layers
          }
        }

        // Remap audio paths if requested
        var remappedEvent = event;
        if (options.remapAudioFolder != null) {
          final remappedLayers = event.layers.map((layer) {
            if (layer.audioPath.isEmpty) return layer;
            final remapped = _remapPath(layer.audioPath, options.remapAudioFolder!);
            if (remapped != null) {
              remapSucceeded++;
              return layer.copyWith(audioPath: remapped);
            } else {
              remapFailed++;
              remapMissing.add(p.basename(layer.audioPath));
              return layer; // Keep original path
            }
          }).toList();
          remappedEvent = event.copyWith(layers: remappedLayers);
        }

        addOrUpdateEvent(remappedEvent);

        // Also set audio assignments
        for (final stage in remappedEvent.triggerStages) {
          final mainLayer = remappedEvent.layers
              .where((l) => l.actionType == 'Play' && l.audioPath.isNotEmpty)
              .firstOrNull;
          if (mainLayer != null) {
            setAudioAssignment(stage.toUpperCase(), mainLayer.audioPath);
          }
        }

        eventsImported++;
      }

      // Apply standalone assignments (stages without composite events)
      for (final entry in assignments.entries) {
        if (options.remapAudioFolder != null) {
          final remapped = _remapPath(entry.value, options.remapAudioFolder!);
          if (remapped != null) {
            setAudioAssignment(entry.key, remapped);
          }
        } else {
          setAudioAssignment(entry.key, entry.value);
        }
      }
    }

    // Import win tiers
    bool winTiersApplied = false;
    if (options.importWinTiers && applyWinTiers != null) {
      final winConfig = _parseWinTiers(extracted);
      if (winConfig != null) {
        applyWinTiers(winConfig);
        winTiersApplied = true;
      }
    }

    // Import music layers
    bool musicLayersApplied = false;
    if (options.importMusicLayers && applyMusicLayers != null) {
      final musicConfig = _parseMusicLayers(extracted);
      if (musicConfig != null) {
        applyMusicLayers(musicConfig);
        musicLayersApplied = true;
      }
    }

    return ProfileImportResult(
      eventsImported: eventsImported,
      eventsSkipped: eventsSkipped,
      remapSucceeded: remapSucceeded,
      remapFailed: remapFailed,
      remapMissing: remapMissing.toSet().toList(), // deduplicate
      winTiersApplied: winTiersApplied,
      musicLayersApplied: musicLayersApplied,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Archive extraction
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, String>?> _extractArchive(String profilePath) async {
    final file = File(profilePath);
    if (!file.existsSync()) return null;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final contents = <String, String>{};
      for (final entry in archive) {
        if (entry.isFile) {
          contents[entry.name] = utf8.decode(List<int>.from(entry.content));
        }
      }
      return contents;
    } catch (_) {
      return null;
    }
  }

  static ProfileManifest _parseManifest(Map<String, String> files) {
    final json = files['manifest.json'];
    if (json == null) return ProfileManifest(name: 'Unknown', created: '', eventCount: 0);
    return ProfileManifest.fromJson(jsonDecode(json));
  }

  static List<SlotCompositeEvent> _parseEvents(Map<String, String> files) {
    final json = files['events.json'];
    if (json == null) return [];
    try {
      final data = jsonDecode(json);
      final list = data['compositeEvents'] as List<dynamic>? ?? [];
      return list.map((e) => SlotCompositeEvent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> _parseAssignments(Map<String, String> files) {
    final json = files['assignments.json'];
    if (json == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(json));
    } catch (_) {
      return {};
    }
  }

  static SlotWinConfiguration? _parseWinTiers(Map<String, String> files) {
    final json = files['win_tiers.json'];
    if (json == null) return null;
    try {
      return SlotWinConfiguration.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  static MusicLayerConfig? _parseMusicLayers(Map<String, String> files) {
    final json = files['music_layers.json'];
    if (json == null) return null;
    try {
      return MusicLayerConfig.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  static String? _readText(Map<String, String> files, String name) => files[name];

  // ═══════════════════════════════════════════════════════════════
  // Audio path remapping
  // ═══════════════════════════════════════════════════════════════

  static String? _remapPath(String originalPath, String remapFolder) {
    final filename = p.basename(originalPath);
    final remapped = p.join(remapFolder, filename);
    if (File(remapped).existsSync()) return remapped;

    // Try case-insensitive match
    final dir = Directory(remapFolder);
    if (!dir.existsSync()) return null;
    try {
      final lowerFilename = filename.toLowerCase();
      for (final entry in dir.listSync()) {
        if (entry is File && p.basename(entry.path).toLowerCase() == lowerFilename) {
          return entry.path;
        }
      }
    } catch (_) {}
    return null;
  }
}
