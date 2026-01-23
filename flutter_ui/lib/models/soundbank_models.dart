// ═══════════════════════════════════════════════════════════════════════════════
// SOUNDBANK MODELS — Audio Bank Definition & Export System
// ═══════════════════════════════════════════════════════════════════════════════
//
// FluxForge Soundbank format (.ffbank):
// - Manifest with versioning and metadata
// - Bundled audio assets
// - Event/container/RTPC configurations
// - Platform-specific optimization hints
// - Dependency graph for incremental loading

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Target platform for soundbank export
enum SoundbankPlatform {
  universal,  // Generic JSON format
  unity,      // Unity C# + ScriptableObject
  unreal,     // Unreal C++ + DataAsset
  howler,     // Howler.js + TypeScript
  native,     // Native FluxForge runtime
  wasm,       // WebAssembly runtime
}

extension SoundbankPlatformExt on SoundbankPlatform {
  String get label {
    switch (this) {
      case SoundbankPlatform.universal: return 'Universal (JSON)';
      case SoundbankPlatform.unity: return 'Unity';
      case SoundbankPlatform.unreal: return 'Unreal Engine';
      case SoundbankPlatform.howler: return 'Howler.js';
      case SoundbankPlatform.native: return 'FluxForge Native';
      case SoundbankPlatform.wasm: return 'WebAssembly';
    }
  }

  String get fileExtension {
    switch (this) {
      case SoundbankPlatform.universal: return 'ffbank';
      case SoundbankPlatform.unity: return 'unitypackage';
      case SoundbankPlatform.unreal: return 'uasset';
      case SoundbankPlatform.howler: return 'zip';
      case SoundbankPlatform.native: return 'ffbank';
      case SoundbankPlatform.wasm: return 'wasm';
    }
  }
}

/// Audio format for exported assets
enum SoundbankAudioFormat {
  wav16,      // PCM 16-bit WAV
  wav24,      // PCM 24-bit WAV
  wav32f,     // Float 32-bit WAV
  flac,       // FLAC lossless
  mp3High,    // MP3 320kbps
  mp3Medium,  // MP3 192kbps
  mp3Low,     // MP3 128kbps
  ogg,        // OGG Vorbis
  webm,       // WebM audio (for web)
  aac,        // AAC (for mobile)
}

extension SoundbankAudioFormatExt on SoundbankAudioFormat {
  String get label {
    switch (this) {
      case SoundbankAudioFormat.wav16: return 'WAV 16-bit';
      case SoundbankAudioFormat.wav24: return 'WAV 24-bit';
      case SoundbankAudioFormat.wav32f: return 'WAV 32-bit Float';
      case SoundbankAudioFormat.flac: return 'FLAC';
      case SoundbankAudioFormat.mp3High: return 'MP3 320kbps';
      case SoundbankAudioFormat.mp3Medium: return 'MP3 192kbps';
      case SoundbankAudioFormat.mp3Low: return 'MP3 128kbps';
      case SoundbankAudioFormat.ogg: return 'OGG Vorbis';
      case SoundbankAudioFormat.webm: return 'WebM';
      case SoundbankAudioFormat.aac: return 'AAC';
    }
  }

  String get extension {
    switch (this) {
      case SoundbankAudioFormat.wav16:
      case SoundbankAudioFormat.wav24:
      case SoundbankAudioFormat.wav32f:
        return 'wav';
      case SoundbankAudioFormat.flac: return 'flac';
      case SoundbankAudioFormat.mp3High:
      case SoundbankAudioFormat.mp3Medium:
      case SoundbankAudioFormat.mp3Low:
        return 'mp3';
      case SoundbankAudioFormat.ogg: return 'ogg';
      case SoundbankAudioFormat.webm: return 'webm';
      case SoundbankAudioFormat.aac: return 'aac';
    }
  }

  bool get isLossless {
    return this == SoundbankAudioFormat.wav16 ||
           this == SoundbankAudioFormat.wav24 ||
           this == SoundbankAudioFormat.wav32f ||
           this == SoundbankAudioFormat.flac;
  }
}

/// Soundbank loading strategy
enum SoundbankLoadStrategy {
  loadAll,          // Load entire bank on init
  loadOnDemand,     // Load assets when first accessed
  streaming,        // Stream large files, cache small ones
  preloadCritical,  // Preload critical assets, lazy load rest
}

/// Asset priority for loading order
enum SoundbankAssetPriority {
  critical,   // Load first (UI sounds, core gameplay)
  high,       // Load early (frequent sounds)
  normal,     // Load normally
  low,        // Load last (ambient, rare sounds)
  background, // Load in background after everything else
}

// ═══════════════════════════════════════════════════════════════════════════════
// CORE MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Soundbank manifest - top-level metadata
class SoundbankManifest {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<SoundbankPlatform> targetPlatforms;
  final SoundbankAudioFormat defaultAudioFormat;
  final int defaultSampleRate;
  final SoundbankLoadStrategy loadStrategy;
  final Map<String, String> customMetadata;

  /// Total size in bytes (computed)
  final int totalSizeBytes;

  /// Number of audio assets
  final int assetCount;

  /// Number of events
  final int eventCount;

  const SoundbankManifest({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0.0',
    this.author = '',
    required this.createdAt,
    required this.modifiedAt,
    this.targetPlatforms = const [SoundbankPlatform.universal],
    this.defaultAudioFormat = SoundbankAudioFormat.wav16,
    this.defaultSampleRate = 48000,
    this.loadStrategy = SoundbankLoadStrategy.loadOnDemand,
    this.customMetadata = const {},
    this.totalSizeBytes = 0,
    this.assetCount = 0,
    this.eventCount = 0,
  });

  SoundbankManifest copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    String? author,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<SoundbankPlatform>? targetPlatforms,
    SoundbankAudioFormat? defaultAudioFormat,
    int? defaultSampleRate,
    SoundbankLoadStrategy? loadStrategy,
    Map<String, String>? customMetadata,
    int? totalSizeBytes,
    int? assetCount,
    int? eventCount,
  }) {
    return SoundbankManifest(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      targetPlatforms: targetPlatforms ?? this.targetPlatforms,
      defaultAudioFormat: defaultAudioFormat ?? this.defaultAudioFormat,
      defaultSampleRate: defaultSampleRate ?? this.defaultSampleRate,
      loadStrategy: loadStrategy ?? this.loadStrategy,
      customMetadata: customMetadata ?? this.customMetadata,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      assetCount: assetCount ?? this.assetCount,
      eventCount: eventCount ?? this.eventCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'targetPlatforms': targetPlatforms.map((p) => p.name).toList(),
    'defaultAudioFormat': defaultAudioFormat.name,
    'defaultSampleRate': defaultSampleRate,
    'loadStrategy': loadStrategy.name,
    'customMetadata': customMetadata,
    'totalSizeBytes': totalSizeBytes,
    'assetCount': assetCount,
    'eventCount': eventCount,
  };

  factory SoundbankManifest.fromJson(Map<String, dynamic> json) {
    return SoundbankManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      targetPlatforms: (json['targetPlatforms'] as List?)
          ?.map((p) => SoundbankPlatform.values.byName(p as String))
          .toList() ?? [SoundbankPlatform.universal],
      defaultAudioFormat: json['defaultAudioFormat'] != null
          ? SoundbankAudioFormat.values.byName(json['defaultAudioFormat'] as String)
          : SoundbankAudioFormat.wav16,
      defaultSampleRate: json['defaultSampleRate'] as int? ?? 48000,
      loadStrategy: json['loadStrategy'] != null
          ? SoundbankLoadStrategy.values.byName(json['loadStrategy'] as String)
          : SoundbankLoadStrategy.loadOnDemand,
      customMetadata: (json['customMetadata'] as Map?)?.cast<String, String>() ?? {},
      totalSizeBytes: json['totalSizeBytes'] as int? ?? 0,
      assetCount: json['assetCount'] as int? ?? 0,
      eventCount: json['eventCount'] as int? ?? 0,
    );
  }
}

/// Audio asset in soundbank
class SoundbankAsset {
  final String id;
  final String name;
  final String sourcePath;        // Original file path
  final String relativePath;      // Path within bank archive
  final String checksum;          // SHA-256 of original file
  final int sizeBytes;
  final double durationSeconds;
  final int sampleRate;
  final int channels;
  final int bitDepth;
  final SoundbankAssetPriority priority;
  final List<String> tags;
  final Map<String, dynamic> metadata;

  const SoundbankAsset({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.relativePath,
    required this.checksum,
    required this.sizeBytes,
    required this.durationSeconds,
    required this.sampleRate,
    required this.channels,
    this.bitDepth = 16,
    this.priority = SoundbankAssetPriority.normal,
    this.tags = const [],
    this.metadata = const {},
  });

  String get formattedDuration {
    final mins = (durationSeconds / 60).floor();
    final secs = (durationSeconds % 60).toStringAsFixed(1);
    return '$mins:${secs.padLeft(4, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  SoundbankAsset copyWith({
    String? id,
    String? name,
    String? sourcePath,
    String? relativePath,
    String? checksum,
    int? sizeBytes,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
    int? bitDepth,
    SoundbankAssetPriority? priority,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    return SoundbankAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      sourcePath: sourcePath ?? this.sourcePath,
      relativePath: relativePath ?? this.relativePath,
      checksum: checksum ?? this.checksum,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      bitDepth: bitDepth ?? this.bitDepth,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourcePath': sourcePath,
    'relativePath': relativePath,
    'checksum': checksum,
    'sizeBytes': sizeBytes,
    'durationSeconds': durationSeconds,
    'sampleRate': sampleRate,
    'channels': channels,
    'bitDepth': bitDepth,
    'priority': priority.name,
    'tags': tags,
    'metadata': metadata,
  };

  factory SoundbankAsset.fromJson(Map<String, dynamic> json) {
    return SoundbankAsset(
      id: json['id'] as String,
      name: json['name'] as String,
      sourcePath: json['sourcePath'] as String,
      relativePath: json['relativePath'] as String,
      checksum: json['checksum'] as String,
      sizeBytes: json['sizeBytes'] as int,
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      sampleRate: json['sampleRate'] as int,
      channels: json['channels'] as int,
      bitDepth: json['bitDepth'] as int? ?? 16,
      priority: json['priority'] != null
          ? SoundbankAssetPriority.values.byName(json['priority'] as String)
          : SoundbankAssetPriority.normal,
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}

/// Event group for organizing events within bank
class SoundbankEventGroup {
  final String id;
  final String name;
  final String description;
  final List<String> eventIds;
  final int order;

  const SoundbankEventGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.eventIds = const [],
    this.order = 0,
  });

  SoundbankEventGroup copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? eventIds,
    int? order,
  }) {
    return SoundbankEventGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      eventIds: eventIds ?? this.eventIds,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'eventIds': eventIds,
    'order': order,
  };

  factory SoundbankEventGroup.fromJson(Map<String, dynamic> json) {
    return SoundbankEventGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      eventIds: (json['eventIds'] as List?)?.cast<String>() ?? [],
      order: json['order'] as int? ?? 0,
    );
  }
}

/// Dependency between soundbanks
class SoundbankDependency {
  final String bankId;
  final String bankName;
  final String version;
  final bool isOptional;

  const SoundbankDependency({
    required this.bankId,
    required this.bankName,
    required this.version,
    this.isOptional = false,
  });

  Map<String, dynamic> toJson() => {
    'bankId': bankId,
    'bankName': bankName,
    'version': version,
    'isOptional': isOptional,
  };

  factory SoundbankDependency.fromJson(Map<String, dynamic> json) {
    return SoundbankDependency(
      bankId: json['bankId'] as String,
      bankName: json['bankName'] as String,
      version: json['version'] as String,
      isOptional: json['isOptional'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SOUNDBANK — COMPLETE BANK DEFINITION
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete soundbank definition
class Soundbank {
  final SoundbankManifest manifest;
  final List<SoundbankAsset> assets;
  final List<String> eventIds;           // Composite event IDs included
  final List<String> containerIds;       // Container IDs included
  final List<String> stateGroupIds;      // State group IDs included
  final List<String> switchGroupIds;     // Switch group IDs included
  final List<String> rtpcIds;            // RTPC IDs included
  final List<SoundbankEventGroup> groups;
  final List<SoundbankDependency> dependencies;

  const Soundbank({
    required this.manifest,
    this.assets = const [],
    this.eventIds = const [],
    this.containerIds = const [],
    this.stateGroupIds = const [],
    this.switchGroupIds = const [],
    this.rtpcIds = const [],
    this.groups = const [],
    this.dependencies = const [],
  });

  /// Total size in bytes
  int get totalSizeBytes => assets.fold(0, (sum, a) => sum + a.sizeBytes);

  /// Total duration in seconds
  double get totalDurationSeconds => assets.fold(0.0, (sum, a) => sum + a.durationSeconds);

  /// Formatted total size
  String get formattedTotalSize {
    final mb = totalSizeBytes / (1024 * 1024);
    if (mb < 1) return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  /// Formatted total duration
  String get formattedTotalDuration {
    final mins = (totalDurationSeconds / 60).floor();
    final secs = (totalDurationSeconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  Soundbank copyWith({
    SoundbankManifest? manifest,
    List<SoundbankAsset>? assets,
    List<String>? eventIds,
    List<String>? containerIds,
    List<String>? stateGroupIds,
    List<String>? switchGroupIds,
    List<String>? rtpcIds,
    List<SoundbankEventGroup>? groups,
    List<SoundbankDependency>? dependencies,
  }) {
    return Soundbank(
      manifest: manifest ?? this.manifest,
      assets: assets ?? this.assets,
      eventIds: eventIds ?? this.eventIds,
      containerIds: containerIds ?? this.containerIds,
      stateGroupIds: stateGroupIds ?? this.stateGroupIds,
      switchGroupIds: switchGroupIds ?? this.switchGroupIds,
      rtpcIds: rtpcIds ?? this.rtpcIds,
      groups: groups ?? this.groups,
      dependencies: dependencies ?? this.dependencies,
    );
  }

  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'assets': assets.map((a) => a.toJson()).toList(),
    'eventIds': eventIds,
    'containerIds': containerIds,
    'stateGroupIds': stateGroupIds,
    'switchGroupIds': switchGroupIds,
    'rtpcIds': rtpcIds,
    'groups': groups.map((g) => g.toJson()).toList(),
    'dependencies': dependencies.map((d) => d.toJson()).toList(),
  };

  factory Soundbank.fromJson(Map<String, dynamic> json) {
    return Soundbank(
      manifest: SoundbankManifest.fromJson(json['manifest'] as Map<String, dynamic>),
      assets: (json['assets'] as List?)
          ?.map((a) => SoundbankAsset.fromJson(a as Map<String, dynamic>))
          .toList() ?? [],
      eventIds: (json['eventIds'] as List?)?.cast<String>() ?? [],
      containerIds: (json['containerIds'] as List?)?.cast<String>() ?? [],
      stateGroupIds: (json['stateGroupIds'] as List?)?.cast<String>() ?? [],
      switchGroupIds: (json['switchGroupIds'] as List?)?.cast<String>() ?? [],
      rtpcIds: (json['rtpcIds'] as List?)?.cast<String>() ?? [],
      groups: (json['groups'] as List?)
          ?.map((g) => SoundbankEventGroup.fromJson(g as Map<String, dynamic>))
          .toList() ?? [],
      dependencies: (json['dependencies'] as List?)
          ?.map((d) => SoundbankDependency.fromJson(d as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  /// Create empty soundbank with default manifest
  factory Soundbank.create({
    required String name,
    String? description,
    String? author,
  }) {
    final now = DateTime.now();
    return Soundbank(
      manifest: SoundbankManifest(
        id: 'bank_${now.millisecondsSinceEpoch}',
        name: name,
        description: description ?? '',
        author: author ?? '',
        createdAt: now,
        modifiedAt: now,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT CONFIG
// ═══════════════════════════════════════════════════════════════════════════════

/// Configuration for soundbank export
class SoundbankExportConfig {
  final String outputPath;
  final SoundbankPlatform platform;
  final SoundbankAudioFormat audioFormat;
  final int sampleRate;
  final bool includeSourcePaths;
  final bool generateManifest;
  final bool compressArchive;
  final bool stripMetadata;
  final String? customPrefix;
  final Map<String, String> platformOptions;

  const SoundbankExportConfig({
    required this.outputPath,
    this.platform = SoundbankPlatform.universal,
    this.audioFormat = SoundbankAudioFormat.wav16,
    this.sampleRate = 48000,
    this.includeSourcePaths = false,
    this.generateManifest = true,
    this.compressArchive = true,
    this.stripMetadata = false,
    this.customPrefix,
    this.platformOptions = const {},
  });

  SoundbankExportConfig copyWith({
    String? outputPath,
    SoundbankPlatform? platform,
    SoundbankAudioFormat? audioFormat,
    int? sampleRate,
    bool? includeSourcePaths,
    bool? generateManifest,
    bool? compressArchive,
    bool? stripMetadata,
    String? customPrefix,
    Map<String, String>? platformOptions,
  }) {
    return SoundbankExportConfig(
      outputPath: outputPath ?? this.outputPath,
      platform: platform ?? this.platform,
      audioFormat: audioFormat ?? this.audioFormat,
      sampleRate: sampleRate ?? this.sampleRate,
      includeSourcePaths: includeSourcePaths ?? this.includeSourcePaths,
      generateManifest: generateManifest ?? this.generateManifest,
      compressArchive: compressArchive ?? this.compressArchive,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      customPrefix: customPrefix ?? this.customPrefix,
      platformOptions: platformOptions ?? this.platformOptions,
    );
  }

  Map<String, dynamic> toJson() => {
    'outputPath': outputPath,
    'platform': platform.name,
    'audioFormat': audioFormat.name,
    'sampleRate': sampleRate,
    'includeSourcePaths': includeSourcePaths,
    'generateManifest': generateManifest,
    'compressArchive': compressArchive,
    'stripMetadata': stripMetadata,
    'customPrefix': customPrefix,
    'platformOptions': platformOptions,
  };

  factory SoundbankExportConfig.fromJson(Map<String, dynamic> json) {
    return SoundbankExportConfig(
      outputPath: json['outputPath'] as String,
      platform: SoundbankPlatform.values.byName(json['platform'] as String),
      audioFormat: SoundbankAudioFormat.values.byName(json['audioFormat'] as String),
      sampleRate: json['sampleRate'] as int? ?? 48000,
      includeSourcePaths: json['includeSourcePaths'] as bool? ?? false,
      generateManifest: json['generateManifest'] as bool? ?? true,
      compressArchive: json['compressArchive'] as bool? ?? true,
      stripMetadata: json['stripMetadata'] as bool? ?? false,
      customPrefix: json['customPrefix'] as String?,
      platformOptions: (json['platformOptions'] as Map?)?.cast<String, String>() ?? {},
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT RESULT
// ═══════════════════════════════════════════════════════════════════════════════

/// Result of soundbank export operation
class SoundbankExportResult {
  final bool success;
  final String? outputPath;
  final int totalAssets;
  final int exportedAssets;
  final int failedAssets;
  final int totalSizeBytes;
  final Duration exportDuration;
  final List<String> warnings;
  final List<String> errors;

  const SoundbankExportResult({
    required this.success,
    this.outputPath,
    this.totalAssets = 0,
    this.exportedAssets = 0,
    this.failedAssets = 0,
    this.totalSizeBytes = 0,
    this.exportDuration = Duration.zero,
    this.warnings = const [],
    this.errors = const [],
  });

  factory SoundbankExportResult.failure(String error) {
    return SoundbankExportResult(
      success: false,
      errors: [error],
    );
  }

  factory SoundbankExportResult.fromJson(Map<String, dynamic> json) {
    return SoundbankExportResult(
      success: json['success'] as bool,
      outputPath: json['outputPath'] as String?,
      totalAssets: json['totalAssets'] as int? ?? 0,
      exportedAssets: json['exportedAssets'] as int? ?? 0,
      failedAssets: json['failedAssets'] as int? ?? 0,
      totalSizeBytes: json['totalSizeBytes'] as int? ?? 0,
      exportDuration: Duration(milliseconds: json['exportDurationMs'] as int? ?? 0),
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
      errors: (json['errors'] as List?)?.cast<String>() ?? [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VALIDATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Validation result for soundbank
class SoundbankValidation {
  final bool isValid;
  final List<SoundbankValidationIssue> issues;

  const SoundbankValidation({
    required this.isValid,
    this.issues = const [],
  });

  int get errorCount => issues.where((i) => i.severity == ValidationSeverity.error).length;
  int get warningCount => issues.where((i) => i.severity == ValidationSeverity.warning).length;
  int get infoCount => issues.where((i) => i.severity == ValidationSeverity.info).length;
}

enum ValidationSeverity { info, warning, error }

class SoundbankValidationIssue {
  final ValidationSeverity severity;
  final String message;
  final String? assetId;
  final String? eventId;

  const SoundbankValidationIssue({
    required this.severity,
    required this.message,
    this.assetId,
    this.eventId,
  });
}
