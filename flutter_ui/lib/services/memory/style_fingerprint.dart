/// FAZA 4.3.3 — `.style` Fingerprint Export/Import
///
/// Portable JSON dokument koji enkapsulira korisničku "audio ličnost"
/// projekta. Omogućava:
///   - **Reuse stila** na novom projektu (import .style → primeni audio
///     palette + AudioDna polja)
///   - **Share između studio-a** (Dropbox/email .style fajl)
///   - **Version-controlled style** (komituješ .style sa game source)
///
/// **Sadržaj:**
///   - `version` semver (kompatibilnost provera)
///   - `name` — display label (npr. "FluxForge Signature Cinematic")
///   - `audio_dna` — root/key/mode/instruments/profiles iz SlotLab AudioDna
///   - `assignments_template` — generic stage→audio NAME pattern (path
///     je vezan za projekat; ovde samo NAZIV za matching), npr.
///     `{ "REEL_STOP": "*reel_stop*.wav", "WIN_BIG": "*big_win*.wav" }`
///   - `bus_profile` — per-bus volume/pan defaults
///   - `compliance_targets` — jurisdiction list + LDW/near-miss caps
///   - `metadata` — author, created_at, updated_at, projects_used
///
/// **Storage:** user može da snimi bilo gde; default `~/Library/Application
/// Support/FluxForge Studio/styles/{name}.style`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// Style fingerprint — immutable JSON dokument.
class StyleFingerprint {
  /// Semver. Increment minor za new optional field, major za breaking.
  final String version;

  final String name;

  /// AudioDna polja (mirror SlotLab dnaBrand/dnaBpmMin/etc).
  final Map<String, dynamic> audioDna;

  /// Generic stage→pattern mapping (filename glob, ne actual path).
  /// Npr. `{"REEL_STOP_*": "*reel_stop*.wav"}`.
  final Map<String, String> assignmentsTemplate;

  /// Per-bus profile (npr. `{"sfx": {"volume": 0.85, "pan": 0.0}}`).
  final Map<String, Map<String, dynamic>> busProfile;

  /// Compliance targets za jurisdikcije.
  final Map<String, dynamic> complianceTargets;

  /// Author + lifecycle metadata.
  final Map<String, dynamic> metadata;

  const StyleFingerprint({
    required this.version,
    required this.name,
    required this.audioDna,
    required this.assignmentsTemplate,
    required this.busProfile,
    required this.complianceTargets,
    required this.metadata,
  });

  /// Kanonska current verzija schema.
  static const String currentVersion = '1.0.0';

  Map<String, dynamic> toJson() => {
        'version': version,
        'name': name,
        'audio_dna': audioDna,
        'assignments_template': assignmentsTemplate,
        'bus_profile': busProfile,
        'compliance_targets': complianceTargets,
        'metadata': metadata,
      };

  factory StyleFingerprint.fromJson(Map<String, dynamic> json) {
    final v = json['version'] as String? ?? '0.0.0';
    if (!_isVersionCompatible(v)) {
      throw FormatException(
        'Incompatible .style version "$v" (current: $currentVersion). '
        'Major-version mismatch — fingerprint requires migration.',
      );
    }
    return StyleFingerprint(
      version: v,
      name: json['name'] as String? ?? 'Unnamed Style',
      audioDna: Map<String, dynamic>.from(
          json['audio_dna'] as Map? ?? <String, dynamic>{}),
      assignmentsTemplate: Map<String, String>.from(
          json['assignments_template'] as Map? ?? <String, String>{}),
      busProfile: (json['bus_profile'] as Map?)?.map<String, Map<String, dynamic>>(
            (k, v) => MapEntry(
              k as String,
              Map<String, dynamic>.from(v as Map),
            ),
          ) ??
          {},
      complianceTargets: Map<String, dynamic>.from(
          json['compliance_targets'] as Map? ?? <String, dynamic>{}),
      metadata: Map<String, dynamic>.from(
          json['metadata'] as Map? ?? <String, dynamic>{}),
    );
  }

  /// Major-version compatibility check.
  static bool _isVersionCompatible(String v) {
    final parts = v.split('.');
    if (parts.isEmpty) return false;
    final currentMajor = currentVersion.split('.').first;
    return parts.first == currentMajor;
  }
}

/// Static service za read/write .style fajlova.
class StyleFingerprintService {
  StyleFingerprintService._();

  /// Eksportuj fingerprint kao pretty-printed JSON na disk.
  static Future<bool> export({
    required StyleFingerprint fingerprint,
    required String outPath,
  }) async {
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      final content = encoder.convert(fingerprint.toJson());
      File(outPath).writeAsStringSync(content, flush: true);
      return true;
    } catch (e, st) {
      debugPrint('[StyleFingerprintService] export fail: $e\n$st');
      return false;
    }
  }

  /// Importuj iz disk fajla. Vraća null ako fajl ne postoji ili je
  /// neparsibilan / incompatible version.
  static StyleFingerprint? import(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return StyleFingerprint.fromJson(json);
    } catch (e, st) {
      debugPrint('[StyleFingerprintService] import fail: $e\n$st');
      return null;
    }
  }

  /// Default styles directory.
  static Directory? defaultStylesDir() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    final basePath = Platform.isMacOS
        ? '$home/Library/Application Support/FluxForge Studio'
        : '$home/.fluxforge';
    final dir = Directory('$basePath/styles');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {
        return null;
      }
    }
    return dir;
  }

  /// Lista svih .style fajlova u default dir-u (newest first).
  static List<File> listAll() {
    final dir = defaultStylesDir();
    if (dir == null || !dir.existsSync()) return const [];
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.style'))
          .toList()
        ..sort((a, b) =>
            b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (_) {
      return const [];
    }
  }

  /// Generiše safe filename iz user-supplied name-a.
  static String safeFilenameFor(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_{2,}'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${cleaned}_$ts.style';
  }
}
