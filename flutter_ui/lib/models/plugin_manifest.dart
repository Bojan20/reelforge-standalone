/// Plugin Manifest Model
///
/// Data models for third-party plugin state management.
/// Enables project portability across systems without plugin redistribution.
///
/// Architecture follows industry standards:
/// - Pro Tools: Binary chunk storage
/// - Logic Pro: AU presets + Component ID
/// - Cubase: VST3 ProcessorState + FUID
///
/// Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

import 'dart:convert';
import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN FORMAT
// ═══════════════════════════════════════════════════════════════════════════

/// Supported plugin formats
enum PluginFormat {
  vst3('VST3', 'vst3'),
  au('Audio Units', 'component'),
  clap('CLAP', 'clap'),
  aax('AAX', 'aaxplugin'),
  lv2('LV2', 'lv2');

  final String displayName;
  final String extension;

  const PluginFormat(this.displayName, this.extension);

  static PluginFormat? fromExtension(String ext) {
    final normalized = ext.toLowerCase().replaceAll('.', '');
    for (final format in values) {
      if (format.extension == normalized) return format;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN UID
// ═══════════════════════════════════════════════════════════════════════════

/// Universal Plugin Identifier
///
/// Supports multiple ID formats:
/// - VST3: 128-bit FUID (e.g., "58E595CC2C1242FB8E32F4C9D39C5F42")
/// - AU: Component ID (type/subtype/manufacturer)
/// - CLAP: String ID (e.g., "com.fabfilter.pro-q-3")
class PluginUid {
  final PluginFormat format;

  /// VST3: 32-char hex string (128-bit FUID)
  /// AU: "aufx:prQ3:FabF" format
  /// CLAP: reverse domain notation
  final String uid;

  const PluginUid({required this.format, required this.uid});

  /// Parse VST3 FUID from hex string
  factory PluginUid.vst3(String hexFuid) {
    final normalized = hexFuid.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
    if (normalized.length != 32) {
      throw ArgumentError('VST3 FUID must be 32 hex characters');
    }
    return PluginUid(format: PluginFormat.vst3, uid: normalized);
  }

  /// Parse AU Component ID
  factory PluginUid.au({
    required String type,
    required String subtype,
    required String manufacturer,
  }) {
    return PluginUid(format: PluginFormat.au, uid: '$type:$subtype:$manufacturer');
  }

  /// Parse CLAP ID
  factory PluginUid.clap(String clapId) {
    return PluginUid(format: PluginFormat.clap, uid: clapId);
  }

  /// Get AU components (returns null for non-AU)
  ({String type, String subtype, String manufacturer})? get auComponents {
    if (format != PluginFormat.au) return null;
    final parts = uid.split(':');
    if (parts.length != 3) return null;
    return (type: parts[0], subtype: parts[1], manufacturer: parts[2]);
  }

  Map<String, dynamic> toJson() => {
        'format': format.name,
        'uid': uid,
      };

  factory PluginUid.fromJson(Map<String, dynamic> json) {
    return PluginUid(
      format: PluginFormat.values.firstWhere((f) => f.name == json['format']),
      uid: json['uid'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PluginUid && format == other.format && uid == other.uid;

  @override
  int get hashCode => Object.hash(format, uid);

  @override
  String toString() => '${format.displayName}:$uid';
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN LOCATION
// ═══════════════════════════════════════════════════════════════════════════

/// Where the plugin was found
class PluginLocation {
  /// Absolute path to plugin bundle
  final String path;

  /// Bundle ID (macOS) or registry key (Windows)
  final String? bundleId;

  /// Last known modification time
  final DateTime? modifiedAt;

  /// File size in bytes (for verification)
  final int? sizeBytes;

  const PluginLocation({
    required this.path,
    this.bundleId,
    this.modifiedAt,
    this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        if (bundleId != null) 'bundleId': bundleId,
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
      };

  factory PluginLocation.fromJson(Map<String, dynamic> json) {
    return PluginLocation(
      path: json['path'] as String,
      bundleId: json['bundleId'] as String?,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : null,
      sizeBytes: json['sizeBytes'] as int?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN REFERENCE
// ═══════════════════════════════════════════════════════════════════════════

/// Complete reference to a third-party plugin
class PluginReference {
  /// Unique identifier
  final PluginUid uid;

  /// Display name (e.g., "FF-Q 64")
  final String name;

  /// Vendor/manufacturer name
  final String vendor;

  /// Version string (e.g., "3.21")
  final String version;

  /// Plugin category (EQ, Compressor, Reverb, etc.)
  final String? category;

  /// Known installation locations
  final List<PluginLocation> locations;

  /// Alternative plugins that could replace this one
  final List<PluginUid> alternatives;

  /// Whether this plugin is currently installed and available
  bool isInstalled;

  PluginReference({
    required this.uid,
    required this.name,
    required this.vendor,
    required this.version,
    this.category,
    this.locations = const [],
    this.alternatives = const [],
    this.isInstalled = false,
  });

  /// Create a copy with updated fields
  PluginReference copyWith({
    PluginUid? uid,
    String? name,
    String? vendor,
    String? version,
    String? category,
    List<PluginLocation>? locations,
    List<PluginUid>? alternatives,
    bool? isInstalled,
  }) {
    return PluginReference(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      vendor: vendor ?? this.vendor,
      version: version ?? this.version,
      category: category ?? this.category,
      locations: locations ?? this.locations,
      alternatives: alternatives ?? this.alternatives,
      isInstalled: isInstalled ?? this.isInstalled,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid.toJson(),
        'name': name,
        'vendor': vendor,
        'version': version,
        if (category != null) 'category': category,
        'locations': locations.map((l) => l.toJson()).toList(),
        'alternatives': alternatives.map((a) => a.toJson()).toList(),
        'isInstalled': isInstalled,
      };

  factory PluginReference.fromJson(Map<String, dynamic> json) {
    return PluginReference(
      uid: PluginUid.fromJson(json['uid'] as Map<String, dynamic>),
      name: json['name'] as String,
      vendor: json['vendor'] as String,
      version: json['version'] as String,
      category: json['category'] as String?,
      locations: (json['locations'] as List<dynamic>?)
              ?.map((l) => PluginLocation.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      alternatives: (json['alternatives'] as List<dynamic>?)
              ?.map((a) => PluginUid.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      isInstalled: json['isInstalled'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN SLOT STATE
// ═══════════════════════════════════════════════════════════════════════════

/// State of a plugin in a specific insert slot
class PluginSlotState {
  /// Track ID where plugin is inserted
  final int trackId;

  /// Slot index (0-7 typical)
  final int slotIndex;

  /// Reference to the plugin
  final PluginReference plugin;

  /// Path to binary state file (.ffstate) - can be null if not yet saved
  final String? stateFilePath;

  /// Is the plugin bypassed?
  final bool bypassed;

  /// Wet/dry mix (0.0 - 1.0)
  final double mix;

  /// Optional preset name
  final String? presetName;

  /// Freeze audio path (if plugin is missing)
  final String? freezeAudioPath;

  const PluginSlotState({
    required this.trackId,
    required this.slotIndex,
    required this.plugin,
    this.stateFilePath,
    this.bypassed = false,
    this.mix = 1.0,
    this.presetName,
    this.freezeAudioPath,
  });

  /// Whether this slot has frozen audio available
  bool get hasFreezeAudio => freezeAudioPath != null;

  /// Whether the plugin is missing but state is preserved
  bool get isMissing => !plugin.isInstalled;

  PluginSlotState copyWith({
    int? trackId,
    int? slotIndex,
    PluginReference? plugin,
    String? stateFilePath,
    bool? bypassed,
    double? mix,
    String? presetName,
    String? freezeAudioPath,
  }) {
    return PluginSlotState(
      trackId: trackId ?? this.trackId,
      slotIndex: slotIndex ?? this.slotIndex,
      plugin: plugin ?? this.plugin,
      stateFilePath: stateFilePath ?? this.stateFilePath,
      bypassed: bypassed ?? this.bypassed,
      mix: mix ?? this.mix,
      presetName: presetName ?? this.presetName,
      freezeAudioPath: freezeAudioPath ?? this.freezeAudioPath,
    );
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'slotIndex': slotIndex,
        'plugin': plugin.toJson(),
        'stateFilePath': stateFilePath,
        'bypassed': bypassed,
        'mix': mix,
        if (presetName != null) 'presetName': presetName,
        if (freezeAudioPath != null) 'freezeAudioPath': freezeAudioPath,
      };

  factory PluginSlotState.fromJson(Map<String, dynamic> json) {
    return PluginSlotState(
      trackId: json['trackId'] as int,
      slotIndex: json['slotIndex'] as int,
      plugin: PluginReference.fromJson(json['plugin'] as Map<String, dynamic>),
      stateFilePath: json['stateFilePath'] as String?,
      bypassed: json['bypassed'] as bool? ?? false,
      mix: (json['mix'] as num?)?.toDouble() ?? 1.0,
      presetName: json['presetName'] as String?,
      freezeAudioPath: json['freezeAudioPath'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN MANIFEST
// ═══════════════════════════════════════════════════════════════════════════

/// Complete manifest of all plugins used in a project
class PluginManifest {
  /// Manifest format version
  static const int currentVersion = 1;

  /// Format version for migration
  final int version;

  /// Project name
  final String projectName;

  /// When manifest was last updated
  final DateTime updatedAt;

  /// All plugin references used in project
  final Map<String, PluginReference> plugins; // uid.toString() -> reference

  /// All plugin slot states
  final List<PluginSlotState> slotStates;

  /// Missing plugins (detected on load)
  final List<PluginUid> missingPlugins;

  PluginManifest({
    this.version = currentVersion,
    required this.projectName,
    DateTime? updatedAt,
    Map<String, PluginReference>? plugins,
    List<PluginSlotState>? slotStates,
    List<PluginUid>? missingPlugins,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        plugins = plugins ?? {},
        slotStates = slotStates ?? [],
        missingPlugins = missingPlugins ?? [];

  /// Get all unique vendors used
  Set<String> get vendors => plugins.values.map((p) => p.vendor).toSet();

  /// Get all unique categories used
  Set<String> get categories =>
      plugins.values.where((p) => p.category != null).map((p) => p.category!).toSet();

  /// Count of installed vs missing plugins
  ({int installed, int missing}) get installStatus {
    int installed = 0;
    int missing = 0;
    for (final plugin in plugins.values) {
      if (plugin.isInstalled) {
        installed++;
      } else {
        missing++;
      }
    }
    return (installed: installed, missing: missing);
  }

  /// Add or update a plugin reference
  void addPlugin(PluginReference plugin) {
    plugins[plugin.uid.toString()] = plugin;
  }

  /// Get plugin by UID
  PluginReference? getPlugin(PluginUid uid) {
    return plugins[uid.toString()];
  }

  /// Add slot state
  void addSlotState(PluginSlotState state) {
    // Remove existing state for same track/slot
    slotStates.removeWhere(
        (s) => s.trackId == state.trackId && s.slotIndex == state.slotIndex);
    slotStates.add(state);
  }

  /// Get slot states for a track
  List<PluginSlotState> getTrackSlots(int trackId) {
    return slotStates.where((s) => s.trackId == trackId).toList()
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
  }

  /// Create updated copy
  PluginManifest copyWith({
    int? version,
    String? projectName,
    DateTime? updatedAt,
    Map<String, PluginReference>? plugins,
    List<PluginSlotState>? slotStates,
    List<PluginUid>? missingPlugins,
  }) {
    return PluginManifest(
      version: version ?? this.version,
      projectName: projectName ?? this.projectName,
      updatedAt: updatedAt ?? this.updatedAt,
      plugins: plugins ?? Map.from(this.plugins),
      slotStates: slotStates ?? List.from(this.slotStates),
      missingPlugins: missingPlugins ?? List.from(this.missingPlugins),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'projectName': projectName,
        'updatedAt': updatedAt.toIso8601String(),
        'plugins': plugins.map((k, v) => MapEntry(k, v.toJson())),
        'slotStates': slotStates.map((s) => s.toJson()).toList(),
        'missingPlugins': missingPlugins.map((p) => p.toJson()).toList(),
      };

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final pluginsMap = (json['plugins'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, PluginReference.fromJson(v as Map<String, dynamic>)),
        ) ??
        {};

    return PluginManifest(
      version: json['version'] as int? ?? currentVersion,
      projectName: json['projectName'] as String,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      plugins: pluginsMap,
      slotStates: (json['slotStates'] as List<dynamic>?)
              ?.map((s) => PluginSlotState.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      missingPlugins: (json['missingPlugins'] as List<dynamic>?)
              ?.map((p) => PluginUid.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Serialize to JSON string
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parse from JSON string
  factory PluginManifest.fromJsonString(String jsonString) {
    return PluginManifest.fromJson(
        json.decode(jsonString) as Map<String, dynamic>);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN STATE CHUNK
// ═══════════════════════════════════════════════════════════════════════════

/// Binary state chunk from a plugin
///
/// Format: .ffstate file
/// ```
/// Header (32 bytes):
///   Magic: "FFST" (4 bytes)
///   Version: u32 (4 bytes)
///   UID Length: u32 (4 bytes)
///   UID: UTF-8 string (variable)
///   Padding to 32 bytes
/// Data:
///   State Size: u64 (8 bytes)
///   State Data: binary blob (variable)
/// Footer:
///   CRC32: u32 (4 bytes)
/// ```
class PluginStateChunk {
  static const String magic = 'FFST';
  static const int version = 1;

  /// Plugin UID this state belongs to
  final PluginUid pluginUid;

  /// Raw binary state data (from plugin)
  final Uint8List stateData;

  /// When state was captured
  final DateTime capturedAt;

  /// Optional preset name
  final String? presetName;

  const PluginStateChunk({
    required this.pluginUid,
    required this.stateData,
    required this.capturedAt,
    this.presetName,
  });

  /// State data size in bytes
  int get sizeBytes => stateData.length;

  /// Serialize to .ffstate binary format
  Uint8List toBytes() {
    final uidBytes = utf8.encode(pluginUid.toString());
    final presetBytes = presetName != null ? utf8.encode(presetName!) : Uint8List(0);

    // Calculate sizes
    final headerSize = 32;
    final metadataSize = 8 + uidBytes.length + 8 + presetBytes.length + 8;
    final totalSize = headerSize + metadataSize + stateData.length + 4; // +4 for CRC

    final buffer = ByteData(totalSize);
    var offset = 0;

    // Magic
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint8(offset++, 0x53); // S
    buffer.setUint8(offset++, 0x54); // T

    // Version
    buffer.setUint32(offset, version, Endian.little);
    offset += 4;

    // Timestamp
    buffer.setInt64(offset, capturedAt.millisecondsSinceEpoch, Endian.little);
    offset += 8;

    // Padding to 32 bytes
    while (offset < headerSize) {
      buffer.setUint8(offset++, 0);
    }

    // UID length + data
    buffer.setUint32(offset, uidBytes.length, Endian.little);
    offset += 4;
    for (final b in uidBytes) {
      buffer.setUint8(offset++, b);
    }

    // Preset length + data
    buffer.setUint32(offset, presetBytes.length, Endian.little);
    offset += 4;
    for (final b in presetBytes) {
      buffer.setUint8(offset++, b);
    }

    // State size + data
    buffer.setUint64(offset, stateData.length, Endian.little);
    offset += 8;
    for (final b in stateData) {
      buffer.setUint8(offset++, b);
    }

    // CRC32 (simple checksum for now)
    final crc = _calculateCrc32(buffer.buffer.asUint8List(0, offset));
    buffer.setUint32(offset, crc, Endian.little);

    return buffer.buffer.asUint8List();
  }

  /// Parse from .ffstate binary format
  factory PluginStateChunk.fromBytes(Uint8List bytes) {
    if (bytes.length < 36) {
      throw FormatException('Invalid .ffstate file: too small');
    }

    final buffer = ByteData.sublistView(bytes);
    var offset = 0;

    // Check magic
    if (bytes[0] != 0x46 || bytes[1] != 0x46 || bytes[2] != 0x53 || bytes[3] != 0x54) {
      throw FormatException('Invalid .ffstate file: bad magic');
    }
    offset = 4;

    // Version
    final fileVersion = buffer.getUint32(offset, Endian.little);
    offset += 4;
    if (fileVersion > version) {
      throw FormatException('Unsupported .ffstate version: $fileVersion');
    }

    // Timestamp
    final timestamp = buffer.getInt64(offset, Endian.little);
    offset += 8;

    // Skip to end of header
    offset = 32;

    // UID
    final uidLength = buffer.getUint32(offset, Endian.little);
    offset += 4;
    final uidString = utf8.decode(bytes.sublist(offset, offset + uidLength));
    offset += uidLength;

    // Parse UID (format:value)
    final uidParts = uidString.split(':');
    final format = PluginFormat.values.firstWhere(
      (f) => f.displayName == uidParts[0],
      orElse: () => PluginFormat.vst3,
    );
    final pluginUid = PluginUid(format: format, uid: uidParts.sublist(1).join(':'));

    // Preset
    final presetLength = buffer.getUint32(offset, Endian.little);
    offset += 4;
    String? presetName;
    if (presetLength > 0) {
      presetName = utf8.decode(bytes.sublist(offset, offset + presetLength));
      offset += presetLength;
    }

    // State data
    final stateSize = buffer.getUint64(offset, Endian.little);
    offset += 8;
    final stateData = bytes.sublist(offset, offset + stateSize.toInt());

    return PluginStateChunk(
      pluginUid: pluginUid,
      stateData: Uint8List.fromList(stateData),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      presetName: presetName,
    );
  }

  /// Simple CRC32 calculation
  static int _calculateCrc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return ~crc & 0xFFFFFFFF;
  }
}
