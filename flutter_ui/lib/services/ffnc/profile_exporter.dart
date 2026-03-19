/// Profile Exporter — creates FluxForge Audio Profile archives (.zip).
///
/// A profile .zip file contains:
/// - manifest.json (metadata)
/// - events.json (composite events)
/// - assignments.json (stage → audio path map)
/// - win_tiers.json (win tier configuration, optional)
/// - music_layers.json (music layer configuration, optional)
/// - README.txt (human-readable summary)

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

import '../../models/win_tier_config.dart';
import '../../models/slot_lab_models.dart';
import '../../providers/subsystems/composite_event_system_provider.dart';
import 'readme_generator.dart';

class ProfileManifest {
  final String name;
  final String version;
  final String created;
  final String? creator;
  final int? reelCount;
  final int eventCount;
  final List<String> mechanics;
  final String ffncVersion;

  const ProfileManifest({
    required this.name,
    this.version = '1.0',
    required this.created,
    this.creator,
    this.reelCount,
    required this.eventCount,
    this.mechanics = const [],
    this.ffncVersion = '1.0',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'created': created,
    if (creator != null) 'creator': creator,
    if (reelCount != null) 'reelCount': reelCount,
    'eventCount': eventCount,
    'mechanics': mechanics,
    'ffncVersion': ffncVersion,
  };

  factory ProfileManifest.fromJson(Map<String, dynamic> json) => ProfileManifest(
    name: json['name'] as String? ?? 'Untitled',
    version: json['version'] as String? ?? '1.0',
    created: json['created'] as String? ?? DateTime.now().toIso8601String(),
    creator: json['creator'] as String?,
    reelCount: json['reelCount'] as int?,
    eventCount: json['eventCount'] as int? ?? 0,
    mechanics: (json['mechanics'] as List<dynamic>?)?.cast<String>() ?? [],
    ffncVersion: json['ffncVersion'] as String? ?? '1.0',
  );
}

class ProfileExporter {
  ProfileExporter._();

  /// Export current project state as .zip profile archive.
  /// Returns the output file path.
  static Future<String> export({
    required String outputPath,
    required String profileName,
    required CompositeEventSystemProvider compositeProvider,
    required SlotWinConfiguration? winConfig,
    required MusicLayerConfig? musicConfig,
    required Map<String, String> audioAssignments,
    String? creator,
    int? reelCount,
    List<String> mechanics = const [],
  }) async {
    final events = compositeProvider.compositeEvents;
    final now = DateTime.now().toIso8601String();

    // Build manifest
    final manifest = ProfileManifest(
      name: profileName,
      created: now,
      creator: creator,
      reelCount: reelCount,
      eventCount: events.length,
      mechanics: mechanics,
    );

    // Build README
    final readme = ProfileReadmeGenerator.generate(
      profileName: profileName,
      events: events,
      winConfig: winConfig,
      musicConfig: musicConfig,
      creator: creator,
      reelCount: reelCount,
    );

    // Serialize components
    final encoder = const JsonEncoder.withIndent('  ');
    final manifestJson = encoder.convert(manifest.toJson());
    final eventsJson = encoder.convert({
      'version': 1,
      'exportedAt': now,
      'compositeEvents': events.map((e) => e.toJson()).toList(),
    });
    final winTiersJson = winConfig != null ? encoder.convert(winConfig.toJson()) : null;
    final musicLayersJson = musicConfig != null ? encoder.convert(musicConfig.toJson()) : null;
    final assignmentsJson = encoder.convert(audioAssignments);

    // Build ZIP archive
    final archive = Archive();

    archive.addFile(_textFile('manifest.json', manifestJson));
    archive.addFile(_textFile('events.json', eventsJson));
    archive.addFile(_textFile('assignments.json', assignmentsJson));
    archive.addFile(_textFile('README.txt', readme));
    if (winTiersJson != null) archive.addFile(_textFile('win_tiers.json', winTiersJson));
    if (musicLayersJson != null) archive.addFile(_textFile('music_layers.json', musicLayersJson));

    // Write to disk
    final filePath = outputPath.endsWith('.zip') ? outputPath : '$outputPath.zip';
    final zipData = ZipEncoder().encode(archive);
    await File(filePath).writeAsBytes(zipData);

    return filePath;
  }

  static ArchiveFile _textFile(String name, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(name, bytes.length, bytes);
  }
}
