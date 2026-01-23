/// Track Preset Service (P0.1)
///
/// Save/load track presets including:
/// - Volume, Pan, Mute/Solo
/// - EQ settings (if any)
/// - Compressor settings (if any)
/// - Output bus routing
///
/// Presets are stored as `.ffxtrack` JSON files.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/timeline_models.dart';

/// Track preset schema version for forward compatibility
const int kTrackPresetSchemaVersion = 1;

/// Preset file extension
const String kTrackPresetExtension = '.ffxtrack';

/// Default presets directory name
const String kPresetsDirectory = 'FluxForge/Presets/Tracks';

// ═══════════════════════════════════════════════════════════════════════════
// TRACK PRESET DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// EQ band settings for preset
class EqBandPreset {
  final double frequency;
  final double gain;
  final double q;
  final String filterType; // 'lowShelf', 'highShelf', 'bell', 'lowCut', 'highCut'
  final bool enabled;

  const EqBandPreset({
    required this.frequency,
    required this.gain,
    required this.q,
    required this.filterType,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        'gain': gain,
        'q': q,
        'filterType': filterType,
        'enabled': enabled,
      };

  factory EqBandPreset.fromJson(Map<String, dynamic> json) {
    return EqBandPreset(
      frequency: (json['frequency'] as num?)?.toDouble() ?? 1000.0,
      gain: (json['gain'] as num?)?.toDouble() ?? 0.0,
      q: (json['q'] as num?)?.toDouble() ?? 1.0,
      filterType: json['filterType'] as String? ?? 'bell',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Compressor settings for preset
class CompressorPreset {
  final double threshold; // dB
  final double ratio;
  final double attack; // ms
  final double release; // ms
  final double knee; // dB
  final double makeupGain; // dB
  final bool enabled;

  const CompressorPreset({
    this.threshold = -20.0,
    this.ratio = 4.0,
    this.attack = 10.0,
    this.release = 100.0,
    this.knee = 6.0,
    this.makeupGain = 0.0,
    this.enabled = false,
  });

  Map<String, dynamic> toJson() => {
        'threshold': threshold,
        'ratio': ratio,
        'attack': attack,
        'release': release,
        'knee': knee,
        'makeupGain': makeupGain,
        'enabled': enabled,
      };

  factory CompressorPreset.fromJson(Map<String, dynamic> json) {
    return CompressorPreset(
      threshold: (json['threshold'] as num?)?.toDouble() ?? -20.0,
      ratio: (json['ratio'] as num?)?.toDouble() ?? 4.0,
      attack: (json['attack'] as num?)?.toDouble() ?? 10.0,
      release: (json['release'] as num?)?.toDouble() ?? 100.0,
      knee: (json['knee'] as num?)?.toDouble() ?? 6.0,
      makeupGain: (json['makeupGain'] as num?)?.toDouble() ?? 0.0,
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}

/// Complete track preset data
class TrackPreset {
  final int schemaVersion;
  final String name;
  final String? description;
  final String? category; // 'Vocals', 'Drums', 'Bass', 'Guitar', 'Keys', 'FX', 'Master'
  final DateTime createdAt;

  // Basic settings
  final double volume; // 0-2 (1 = unity)
  final double pan; // -1 to 1
  final String outputBus; // 'master', 'music', 'sfx', 'voice', 'ambience'

  // EQ settings
  final List<EqBandPreset> eqBands;
  final bool eqEnabled;

  // Compressor settings
  final CompressorPreset compressor;

  // Additional settings
  final double inputGain; // dB
  final double outputGain; // dB
  final bool phaseInvert;

  const TrackPreset({
    this.schemaVersion = kTrackPresetSchemaVersion,
    required this.name,
    this.description,
    this.category,
    required this.createdAt,
    this.volume = 1.0,
    this.pan = 0.0,
    this.outputBus = 'master',
    this.eqBands = const [],
    this.eqEnabled = true,
    this.compressor = const CompressorPreset(),
    this.inputGain = 0.0,
    this.outputGain = 0.0,
    this.phaseInvert = false,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'name': name,
        'description': description,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'volume': volume,
        'pan': pan,
        'outputBus': outputBus,
        'eqBands': eqBands.map((b) => b.toJson()).toList(),
        'eqEnabled': eqEnabled,
        'compressor': compressor.toJson(),
        'inputGain': inputGain,
        'outputGain': outputGain,
        'phaseInvert': phaseInvert,
      };

  factory TrackPreset.fromJson(Map<String, dynamic> json) {
    return TrackPreset(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String?,
      category: json['category'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      outputBus: json['outputBus'] as String? ?? 'master',
      eqBands: (json['eqBands'] as List<dynamic>?)
              ?.map((e) => EqBandPreset.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      eqEnabled: json['eqEnabled'] as bool? ?? true,
      compressor: json['compressor'] != null
          ? CompressorPreset.fromJson(json['compressor'] as Map<String, dynamic>)
          : const CompressorPreset(),
      inputGain: (json['inputGain'] as num?)?.toDouble() ?? 0.0,
      outputGain: (json['outputGain'] as num?)?.toDouble() ?? 0.0,
      phaseInvert: json['phaseInvert'] as bool? ?? false,
    );
  }

  TrackPreset copyWith({
    int? schemaVersion,
    String? name,
    String? description,
    String? category,
    DateTime? createdAt,
    double? volume,
    double? pan,
    String? outputBus,
    List<EqBandPreset>? eqBands,
    bool? eqEnabled,
    CompressorPreset? compressor,
    double? inputGain,
    double? outputGain,
    bool? phaseInvert,
  }) {
    return TrackPreset(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      outputBus: outputBus ?? this.outputBus,
      eqBands: eqBands ?? this.eqBands,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      compressor: compressor ?? this.compressor,
      inputGain: inputGain ?? this.inputGain,
      outputGain: outputGain ?? this.outputGain,
      phaseInvert: phaseInvert ?? this.phaseInvert,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK PRESET SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for track preset management (save/load/list)
class TrackPresetService extends ChangeNotifier {
  static final TrackPresetService _instance = TrackPresetService._();
  static TrackPresetService get instance => _instance;

  TrackPresetService._();

  /// Cached list of available presets
  List<TrackPreset> _presets = [];
  List<TrackPreset> get presets => List.unmodifiable(_presets);

  /// Currently loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Preset categories
  static const List<String> categories = [
    'Vocals',
    'Drums',
    'Bass',
    'Guitar',
    'Keys',
    'Synth',
    'FX',
    'Ambience',
    'Master',
    'Custom',
  ];

  // ─── Directory Management ──────────────────────────────────────────────────

  /// Get presets directory path
  Future<Directory> get _presetsDirectory async {
    final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory(path.join(homeDir, kPresetsDirectory));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ─── Load/Save Operations ──────────────────────────────────────────────────

  /// Load all presets from disk
  Future<void> loadPresets() async {
    _isLoading = true;
    notifyListeners();

    try {
      final dir = await _presetsDirectory;
      final files = await dir.list().toList();
      final presetFiles = files.whereType<File>().where(
            (f) => f.path.endsWith(kTrackPresetExtension),
          );

      _presets = [];
      for (final file in presetFiles) {
        try {
          final jsonStr = await file.readAsString();
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          _presets.add(TrackPreset.fromJson(json));
        } catch (e) {
          debugPrint('[TrackPresetService] Error loading ${file.path}: $e');
        }
      }

      // Sort by name
      _presets.sort((a, b) => a.name.compareTo(b.name));

      debugPrint('[TrackPresetService] Loaded ${_presets.length} presets');
    } catch (e) {
      debugPrint('[TrackPresetService] Error loading presets: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save preset to disk
  Future<bool> savePreset(TrackPreset preset) async {
    try {
      final dir = await _presetsDirectory;
      final safeName = preset.name.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final filePath = path.join(dir.path, '$safeName$kTrackPresetExtension');
      final file = File(filePath);

      final jsonStr = const JsonEncoder.withIndent('  ').convert(preset.toJson());
      await file.writeAsString(jsonStr);

      // Update cache
      final existingIndex = _presets.indexWhere((p) => p.name == preset.name);
      if (existingIndex >= 0) {
        _presets[existingIndex] = preset;
      } else {
        _presets.add(preset);
        _presets.sort((a, b) => a.name.compareTo(b.name));
      }

      debugPrint('[TrackPresetService] Saved preset: ${preset.name}');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[TrackPresetService] Error saving preset: $e');
      return false;
    }
  }

  /// Delete preset from disk
  Future<bool> deletePreset(String name) async {
    try {
      final dir = await _presetsDirectory;
      final safeName = name.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final filePath = path.join(dir.path, '$safeName$kTrackPresetExtension');
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      _presets.removeWhere((p) => p.name == name);

      debugPrint('[TrackPresetService] Deleted preset: $name');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[TrackPresetService] Error deleting preset: $e');
      return false;
    }
  }

  /// Export preset to custom location
  Future<bool> exportPreset(TrackPreset preset, String filePath) async {
    try {
      final file = File(filePath);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(preset.toJson());
      await file.writeAsString(jsonStr);

      debugPrint('[TrackPresetService] Exported preset: ${preset.name} → $filePath');
      return true;
    } catch (e) {
      debugPrint('[TrackPresetService] Export error: $e');
      return false;
    }
  }

  /// Import preset from file
  Future<TrackPreset?> importPreset(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[TrackPresetService] File not found: $filePath');
        return null;
      }

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final preset = TrackPreset.fromJson(json);

      // Auto-save to presets folder
      await savePreset(preset);

      debugPrint('[TrackPresetService] Imported preset: ${preset.name}');
      return preset;
    } catch (e) {
      debugPrint('[TrackPresetService] Import error: $e');
      return null;
    }
  }

  // ─── Preset Creation Helpers ───────────────────────────────────────────────

  /// Create preset from TimelineTrack
  TrackPreset createFromTrack(
    TimelineTrack track, {
    String? name,
    String? category,
    List<EqBandPreset>? eqBands,
    CompressorPreset? compressor,
  }) {
    return TrackPreset(
      name: name ?? '${track.name} Preset',
      category: category,
      createdAt: DateTime.now(),
      volume: track.volume,
      pan: track.pan,
      outputBus: track.outputBus.name,
      eqBands: eqBands ?? [],
      compressor: compressor ?? const CompressorPreset(),
    );
  }

  /// Apply preset to track (returns new track with preset settings)
  TimelineTrack applyToTrack(TimelineTrack track, TrackPreset preset) {
    OutputBus outputBus;
    try {
      outputBus = OutputBus.values.firstWhere(
        (b) => b.name == preset.outputBus,
        orElse: () => OutputBus.master,
      );
    } catch (_) {
      outputBus = OutputBus.master;
    }

    return track.copyWith(
      volume: preset.volume,
      pan: preset.pan,
      outputBus: outputBus,
    );
  }

  // ─── Filtering ─────────────────────────────────────────────────────────────

  /// Get presets by category
  List<TrackPreset> getByCategory(String? category) {
    if (category == null || category.isEmpty) {
      return presets;
    }
    return presets.where((p) => p.category == category).toList();
  }

  /// Search presets by name
  List<TrackPreset> search(String query) {
    if (query.isEmpty) return presets;
    final lowerQuery = query.toLowerCase();
    return presets
        .where((p) =>
            p.name.toLowerCase().contains(lowerQuery) ||
            (p.description?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }

  // ─── Factory Presets ───────────────────────────────────────────────────────

  /// Initialize with factory presets if no presets exist
  Future<void> initializeFactoryPresets() async {
    await loadPresets();
    if (_presets.isNotEmpty) return;

    // Create default factory presets
    final factoryPresets = [
      TrackPreset(
        name: 'Vocal Warmth',
        description: 'Warm vocal processing with gentle compression',
        category: 'Vocals',
        createdAt: DateTime.now(),
        volume: 1.0,
        pan: 0.0,
        outputBus: 'voice',
        eqBands: [
          const EqBandPreset(frequency: 80, gain: -3, q: 0.7, filterType: 'lowShelf'),
          const EqBandPreset(frequency: 3000, gain: 2, q: 1.5, filterType: 'bell'),
          const EqBandPreset(frequency: 10000, gain: 1.5, q: 0.7, filterType: 'highShelf'),
        ],
        compressor: const CompressorPreset(
          threshold: -18,
          ratio: 3,
          attack: 15,
          release: 150,
          enabled: true,
        ),
      ),
      TrackPreset(
        name: 'Punchy Drums',
        description: 'Tight compression for punchy drums',
        category: 'Drums',
        createdAt: DateTime.now(),
        volume: 1.0,
        pan: 0.0,
        outputBus: 'sfx',
        eqBands: [
          const EqBandPreset(frequency: 60, gain: 3, q: 1.0, filterType: 'bell'),
          const EqBandPreset(frequency: 5000, gain: 2, q: 2.0, filterType: 'bell'),
        ],
        compressor: const CompressorPreset(
          threshold: -12,
          ratio: 6,
          attack: 5,
          release: 80,
          enabled: true,
        ),
      ),
      TrackPreset(
        name: 'Clean Bass',
        description: 'Clean bass with tight low end',
        category: 'Bass',
        createdAt: DateTime.now(),
        volume: 1.0,
        pan: 0.0,
        outputBus: 'music',
        eqBands: [
          const EqBandPreset(frequency: 40, gain: 0, q: 1.0, filterType: 'lowCut'),
          const EqBandPreset(frequency: 80, gain: 2, q: 1.2, filterType: 'bell'),
          const EqBandPreset(frequency: 800, gain: -2, q: 1.0, filterType: 'bell'),
        ],
        compressor: const CompressorPreset(
          threshold: -16,
          ratio: 4,
          attack: 20,
          release: 120,
          enabled: true,
        ),
      ),
      TrackPreset(
        name: 'Ambient Pad',
        description: 'Spacious pad with wide stereo',
        category: 'Ambience',
        createdAt: DateTime.now(),
        volume: 0.7,
        pan: 0.0,
        outputBus: 'ambience',
        eqBands: [
          const EqBandPreset(frequency: 200, gain: -2, q: 0.7, filterType: 'lowShelf'),
          const EqBandPreset(frequency: 8000, gain: 3, q: 0.7, filterType: 'highShelf'),
        ],
        compressor: const CompressorPreset(enabled: false),
      ),
      TrackPreset(
        name: 'Unity Bypass',
        description: 'Clean pass-through with unity gain',
        category: 'Custom',
        createdAt: DateTime.now(),
        volume: 1.0,
        pan: 0.0,
        outputBus: 'master',
        eqBands: [],
        compressor: const CompressorPreset(enabled: false),
      ),
    ];

    for (final preset in factoryPresets) {
      await savePreset(preset);
    }

    debugPrint('[TrackPresetService] Initialized ${factoryPresets.length} factory presets');
  }
}
