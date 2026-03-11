// ═══════════════════════════════════════════════════════════════════════════════
// SFX PIPELINE CONFIG — Models for SlotLab SFX Pipeline Wizard
// ═══════════════════════════════════════════════════════════════════════════════
//
// Data models for the 6-step SFX Pipeline Wizard:
// - SfxPipelinePreset: Full pipeline configuration (saveable/loadable)
// - SfxPipelineResult: Batch processing result with per-file stats
// - SfxFileResult: Single file processing result
// - Enums: MonoMethod, NamingMode, ConflictResolution, FadeCurve, SfxCategory

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Mono downmix method for stereo → mono conversion
enum MonoDownmixMethod {
  /// (L+R)/2 — standard, phase-safe
  sumHalf,

  /// Left channel only
  leftOnly,

  /// Right channel only
  rightOnly,

  /// L+R (no division) — mid signal
  mid,

  /// L-R — side/difference signal
  side,
}

extension MonoDownmixMethodExt on MonoDownmixMethod {
  String get displayName {
    switch (this) {
      case MonoDownmixMethod.sumHalf:
        return 'Sum (L+R)/2';
      case MonoDownmixMethod.leftOnly:
        return 'Left Only';
      case MonoDownmixMethod.rightOnly:
        return 'Right Only';
      case MonoDownmixMethod.mid:
        return 'Mid (L+R)';
      case MonoDownmixMethod.side:
        return 'Side (L-R)';
    }
  }

  String get description {
    switch (this) {
      case MonoDownmixMethod.sumHalf:
        return 'Standard mono fold-down, phase-safe';
      case MonoDownmixMethod.leftOnly:
        return 'Use left channel only';
      case MonoDownmixMethod.rightOnly:
        return 'Use right channel only';
      case MonoDownmixMethod.mid:
        return 'Mono sum without division';
      case MonoDownmixMethod.side:
        return 'Difference signal';
    }
  }

  int get ffiId => index;
}

/// Output channel configuration
enum OutputChannelMode {
  mono,
  stereo,
  keepOriginal,
}

extension OutputChannelModeExt on OutputChannelMode {
  String get displayName {
    switch (this) {
      case OutputChannelMode.mono:
        return 'Mono';
      case OutputChannelMode.stereo:
        return 'Stereo';
      case OutputChannelMode.keepOriginal:
        return 'Keep Original';
    }
  }
}

/// Naming mode for output files
enum SfxNamingMode {
  /// sfx_{STAGE_ID}.wav — SlotLab stage naming convention
  slotLabStageId,

  /// UCS standard naming (CATsub_VENdor_Project_Descriptor)
  ucs,

  /// User-defined template with tokens
  custom,

  /// Keep original filename
  keepOriginal,
}

extension SfxNamingModeExt on SfxNamingMode {
  String get displayName {
    switch (this) {
      case SfxNamingMode.slotLabStageId:
        return 'SlotLab Stage ID';
      case SfxNamingMode.ucs:
        return 'UCS Standard';
      case SfxNamingMode.custom:
        return 'Custom Template';
      case SfxNamingMode.keepOriginal:
        return 'Keep Original';
    }
  }
}

/// Conflict resolution when assigning to stages that already have audio
enum SfxConflictResolution {
  /// Replace existing audio assignment
  replace,

  /// Add as additional layer to existing composite event
  addLayer,

  /// Skip if stage already has audio assigned
  skipIfAssigned,
}

extension SfxConflictResolutionExt on SfxConflictResolution {
  String get displayName {
    switch (this) {
      case SfxConflictResolution.replace:
        return 'Replace Existing';
      case SfxConflictResolution.addLayer:
        return 'Add as Layer';
      case SfxConflictResolution.skipIfAssigned:
        return 'Skip if Assigned';
    }
  }
}

/// Fade curve type
enum SfxFadeCurve {
  linear,
  exponential,
  logarithmic,
  sCurve,
}

extension SfxFadeCurveExt on SfxFadeCurve {
  String get displayName {
    switch (this) {
      case SfxFadeCurve.linear:
        return 'Linear';
      case SfxFadeCurve.exponential:
        return 'Exponential';
      case SfxFadeCurve.logarithmic:
        return 'Logarithmic';
      case SfxFadeCurve.sCurve:
        return 'S-Curve';
    }
  }
}

/// Normalization mode for the pipeline
enum SfxNormMode {
  lufs,
  peak,
  truePeak,
  none,
}

extension SfxNormModeExt on SfxNormMode {
  String get displayName {
    switch (this) {
      case SfxNormMode.lufs:
        return 'LUFS (EBU R128)';
      case SfxNormMode.peak:
        return 'Peak';
      case SfxNormMode.truePeak:
        return 'True Peak';
      case SfxNormMode.none:
        return 'None';
    }
  }
}

/// Output audio format
enum SfxOutputFormat {
  wav16,
  wav24,
  wav32f,
  flac,
  ogg,
  mp3High,
}

extension SfxOutputFormatExt on SfxOutputFormat {
  String get displayName {
    switch (this) {
      case SfxOutputFormat.wav16:
        return 'WAV 16-bit';
      case SfxOutputFormat.wav24:
        return 'WAV 24-bit';
      case SfxOutputFormat.wav32f:
        return 'WAV 32-float';
      case SfxOutputFormat.flac:
        return 'FLAC';
      case SfxOutputFormat.ogg:
        return 'OGG Vorbis';
      case SfxOutputFormat.mp3High:
        return 'MP3 320kbps';
    }
  }

  String get fileExtension {
    switch (this) {
      case SfxOutputFormat.wav16:
      case SfxOutputFormat.wav24:
      case SfxOutputFormat.wav32f:
        return 'wav';
      case SfxOutputFormat.flac:
        return 'flac';
      case SfxOutputFormat.ogg:
        return 'ogg';
      case SfxOutputFormat.mp3High:
        return 'mp3';
    }
  }
}

/// Auto-detected SFX category based on filename patterns
enum SfxCategory {
  uiClicks,
  reelMechanics,
  winCelebrations,
  ambientLoops,
  featureTriggers,
  anticipation,
  unknown,
}

extension SfxCategoryExt on SfxCategory {
  String get displayName {
    switch (this) {
      case SfxCategory.uiClicks:
        return 'UI / Clicks';
      case SfxCategory.reelMechanics:
        return 'Reel Mechanics';
      case SfxCategory.winCelebrations:
        return 'Win Celebrations';
      case SfxCategory.ambientLoops:
        return 'Ambient / Loops';
      case SfxCategory.featureTriggers:
        return 'Feature Triggers';
      case SfxCategory.anticipation:
        return 'Anticipation';
      case SfxCategory.unknown:
        return 'Unknown';
    }
  }

  /// Filename patterns that identify this category
  List<String> get patterns {
    switch (this) {
      case SfxCategory.uiClicks:
        return ['ui_', 'click_', 'button_'];
      case SfxCategory.reelMechanics:
        return ['reel_', 'spin_', 'stop_'];
      case SfxCategory.winCelebrations:
        return ['win_', 'big_', 'rollup_', 'fanfare_'];
      case SfxCategory.ambientLoops:
        return ['amb_', 'loop_', 'music_', 'drone_'];
      case SfxCategory.featureTriggers:
        return ['fs_', 'scatter_', 'wild_', 'bonus_'];
      case SfxCategory.anticipation:
        return ['anticipation_', 'tension_', 'near_'];
      case SfxCategory.unknown:
        return [];
    }
  }

  /// Detect category from filename
  static SfxCategory fromFilename(String filename) {
    final lower = filename.toLowerCase();
    for (final cat in SfxCategory.values) {
      if (cat == SfxCategory.unknown) continue;
      for (final pattern in cat.patterns) {
        if (lower.contains(pattern)) return cat;
      }
    }
    return SfxCategory.unknown;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCAN RESULT — Per-file analysis from Step 1
// ═══════════════════════════════════════════════════════════════════════════════

/// Analysis data for a single scanned file
class SfxScanResult {
  final String path;
  final String filename;
  final int sampleRate;
  final int bitDepth;
  final int channels;
  final double durationSeconds;
  final double integratedLufs;
  final double peakDbfs;
  final double dcOffset;
  final double silenceStartMs;
  final double silenceEndMs;
  final SfxCategory detectedCategory;
  final bool selected;

  const SfxScanResult({
    required this.path,
    required this.filename,
    required this.sampleRate,
    required this.bitDepth,
    required this.channels,
    required this.durationSeconds,
    required this.integratedLufs,
    required this.peakDbfs,
    this.dcOffset = 0.0,
    this.silenceStartMs = 0.0,
    this.silenceEndMs = 0.0,
    this.detectedCategory = SfxCategory.unknown,
    this.selected = true,
  });

  bool get isStereo => channels >= 2;
  bool get isMono => channels == 1;
  bool get hasSilence => silenceStartMs > 50 || silenceEndMs > 50;
  bool get hasDcOffset => dcOffset.abs() > 0.005;
  bool get isQuiet => integratedLufs < -30;

  String get formatLabel {
    final bitLabel = bitDepth == 32 ? '32f' : '$bitDepth';
    final srLabel = sampleRate >= 1000 ? '${(sampleRate / 1000).toStringAsFixed(1)}kHz' : '${sampleRate}Hz';
    return 'WAV$bitLabel/$srLabel';
  }

  String get channelLabel => isStereo ? 'St' : 'Mo';

  SfxScanResult copyWith({bool? selected}) {
    return SfxScanResult(
      path: path,
      filename: filename,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
      durationSeconds: durationSeconds,
      integratedLufs: integratedLufs,
      peakDbfs: peakDbfs,
      dcOffset: dcOffset,
      silenceStartMs: silenceStartMs,
      silenceEndMs: silenceEndMs,
      detectedCategory: detectedCategory,
      selected: selected ?? this.selected,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE MAPPING — Filename → Stage assignment for Step 5
// ═══════════════════════════════════════════════════════════════════════════════

/// A mapping from source file to target stage
class SfxStageMapping {
  final String sourceFilename;
  final String? stageId;
  final double confidence;
  final bool isManualOverride;

  const SfxStageMapping({
    required this.sourceFilename,
    this.stageId,
    this.confidence = 0.0,
    this.isManualOverride = false,
  });

  bool get isMatched => stageId != null;
  bool get isHighConfidence => confidence >= 0.7;

  SfxStageMapping copyWith({
    String? stageId,
    double? confidence,
    bool? isManualOverride,
  }) {
    return SfxStageMapping(
      sourceFilename: sourceFilename,
      stageId: stageId ?? this.stageId,
      confidence: confidence ?? this.confidence,
      isManualOverride: isManualOverride ?? this.isManualOverride,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE PRESET — Full saveable configuration
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete pipeline configuration — saveable as JSON preset
class SfxPipelinePreset {
  final String id;
  final String name;
  final DateTime createdAt;
  final bool isBuiltIn;

  // Step 1: Import
  final String? lastSourcePath;
  final bool recursive;
  final String fileFilter;

  // Step 2: Trim & Clean
  final bool trimStart;
  final bool trimEnd;
  final double thresholdDb;
  final double minSilenceMs;
  final double paddingBeforeMs;
  final double paddingAfterMs;
  final bool removeDcOffset;
  final bool preNormalizePeak;
  final bool fadeIn;
  final double fadeInMs;
  final bool fadeOut;
  final double fadeOutMs;
  final SfxFadeCurve fadeCurve;

  // Step 2b: Filters (HP/LP)
  final bool highPassEnabled;
  final double highPassFreq;
  final bool lowPassEnabled;
  final double lowPassFreq;

  // Step 3: Loudness
  final SfxNormMode normMode;
  final double targetLufs;
  final double truePeakCeiling;
  final bool applyLimiter;
  final bool allowClipping;
  final Map<SfxCategory, double?> perCategoryOverrides;
  final bool categoryDetection;

  // Step 4: Format & Channel
  final SfxOutputFormat outputFormat;
  final int sampleRate;
  final OutputChannelMode outputChannels;
  final MonoDownmixMethod monoMethod;
  final bool skipMonoDownmix;
  final Set<String> stereoOverrideStages;
  final bool multiFormat;
  final Set<SfxOutputFormat> multiFormatPresets;
  final bool subfolderPerFormat;

  // Step 5: Naming
  final SfxNamingMode namingMode;
  final String prefix;
  final bool lowercase;
  final bool keepOriginalSuffix;
  final bool numberDuplicates;
  final bool autoAssign;
  final SfxConflictResolution conflictResolution;
  final String customTemplate;
  final String ucsVendor;
  final String ucsProject;

  // Step 6: Export
  final String? outputPath;
  final bool createDateSubfolder;
  final bool overwriteExisting;
  final bool generateManifest;
  final bool generateLufsReport;
  final bool keepIntermediateFiles;

  const SfxPipelinePreset({
    required this.id,
    required this.name,
    required this.createdAt,
    this.isBuiltIn = false,
    // Step 1
    this.lastSourcePath,
    this.recursive = true,
    this.fileFilter = '*.{wav,mp3,flac,ogg,aif,aiff}',
    // Step 2
    this.trimStart = true,
    this.trimEnd = true,
    this.thresholdDb = -40.0,
    this.minSilenceMs = 100.0,
    this.paddingBeforeMs = 5.0,
    this.paddingAfterMs = 10.0,
    this.removeDcOffset = true,
    this.preNormalizePeak = false,
    this.fadeIn = true,
    this.fadeInMs = 2.0,
    this.fadeOut = true,
    this.fadeOutMs = 10.0,
    this.fadeCurve = SfxFadeCurve.linear,
    // Step 2b: Filters
    this.highPassEnabled = true,
    this.highPassFreq = 40.0,
    this.lowPassEnabled = true,
    this.lowPassFreq = 16000.0,
    // Step 3
    this.normMode = SfxNormMode.lufs,
    this.targetLufs = -18.0,
    this.truePeakCeiling = -1.0,
    this.applyLimiter = true,
    this.allowClipping = false,
    this.perCategoryOverrides = const {},
    this.categoryDetection = true,
    // Step 4
    this.outputFormat = SfxOutputFormat.wav24,
    this.sampleRate = 48000,
    this.outputChannels = OutputChannelMode.mono,
    this.monoMethod = MonoDownmixMethod.sumHalf,
    this.skipMonoDownmix = true,
    this.stereoOverrideStages = const {},
    this.multiFormat = false,
    this.multiFormatPresets = const {SfxOutputFormat.wav24, SfxOutputFormat.ogg},
    this.subfolderPerFormat = true,
    // Step 5
    this.namingMode = SfxNamingMode.slotLabStageId,
    this.prefix = 'sfx_',
    this.lowercase = true,
    this.keepOriginalSuffix = false,
    this.numberDuplicates = true,
    this.autoAssign = true,
    this.conflictResolution = SfxConflictResolution.replace,
    this.customTemplate = '{prefix}{stage}{ext}',
    this.ucsVendor = '',
    this.ucsProject = '',
    // Step 6
    this.outputPath,
    this.createDateSubfolder = true,
    this.overwriteExisting = false,
    this.generateManifest = true,
    this.generateLufsReport = true,
    this.keepIntermediateFiles = false,
  });

  SfxPipelinePreset copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    bool? isBuiltIn,
    String? lastSourcePath,
    bool? recursive,
    String? fileFilter,
    bool? trimStart,
    bool? trimEnd,
    double? thresholdDb,
    double? minSilenceMs,
    double? paddingBeforeMs,
    double? paddingAfterMs,
    bool? removeDcOffset,
    bool? preNormalizePeak,
    bool? fadeIn,
    double? fadeInMs,
    bool? fadeOut,
    double? fadeOutMs,
    SfxFadeCurve? fadeCurve,
    bool? highPassEnabled,
    double? highPassFreq,
    bool? lowPassEnabled,
    double? lowPassFreq,
    SfxNormMode? normMode,
    double? targetLufs,
    double? truePeakCeiling,
    bool? applyLimiter,
    bool? allowClipping,
    Map<SfxCategory, double?>? perCategoryOverrides,
    bool? categoryDetection,
    SfxOutputFormat? outputFormat,
    int? sampleRate,
    OutputChannelMode? outputChannels,
    MonoDownmixMethod? monoMethod,
    bool? skipMonoDownmix,
    Set<String>? stereoOverrideStages,
    bool? multiFormat,
    Set<SfxOutputFormat>? multiFormatPresets,
    bool? subfolderPerFormat,
    SfxNamingMode? namingMode,
    String? prefix,
    bool? lowercase,
    bool? keepOriginalSuffix,
    bool? numberDuplicates,
    bool? autoAssign,
    SfxConflictResolution? conflictResolution,
    String? customTemplate,
    String? ucsVendor,
    String? ucsProject,
    String? outputPath,
    bool? createDateSubfolder,
    bool? overwriteExisting,
    bool? generateManifest,
    bool? generateLufsReport,
    bool? keepIntermediateFiles,
  }) {
    return SfxPipelinePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      lastSourcePath: lastSourcePath ?? this.lastSourcePath,
      recursive: recursive ?? this.recursive,
      fileFilter: fileFilter ?? this.fileFilter,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      thresholdDb: thresholdDb ?? this.thresholdDb,
      minSilenceMs: minSilenceMs ?? this.minSilenceMs,
      paddingBeforeMs: paddingBeforeMs ?? this.paddingBeforeMs,
      paddingAfterMs: paddingAfterMs ?? this.paddingAfterMs,
      removeDcOffset: removeDcOffset ?? this.removeDcOffset,
      preNormalizePeak: preNormalizePeak ?? this.preNormalizePeak,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOut: fadeOut ?? this.fadeOut,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      fadeCurve: fadeCurve ?? this.fadeCurve,
      highPassEnabled: highPassEnabled ?? this.highPassEnabled,
      highPassFreq: highPassFreq ?? this.highPassFreq,
      lowPassEnabled: lowPassEnabled ?? this.lowPassEnabled,
      lowPassFreq: lowPassFreq ?? this.lowPassFreq,
      normMode: normMode ?? this.normMode,
      targetLufs: targetLufs ?? this.targetLufs,
      truePeakCeiling: truePeakCeiling ?? this.truePeakCeiling,
      applyLimiter: applyLimiter ?? this.applyLimiter,
      allowClipping: allowClipping ?? this.allowClipping,
      perCategoryOverrides: perCategoryOverrides ?? this.perCategoryOverrides,
      categoryDetection: categoryDetection ?? this.categoryDetection,
      outputFormat: outputFormat ?? this.outputFormat,
      sampleRate: sampleRate ?? this.sampleRate,
      outputChannels: outputChannels ?? this.outputChannels,
      monoMethod: monoMethod ?? this.monoMethod,
      skipMonoDownmix: skipMonoDownmix ?? this.skipMonoDownmix,
      stereoOverrideStages: stereoOverrideStages ?? this.stereoOverrideStages,
      multiFormat: multiFormat ?? this.multiFormat,
      multiFormatPresets: multiFormatPresets ?? this.multiFormatPresets,
      subfolderPerFormat: subfolderPerFormat ?? this.subfolderPerFormat,
      namingMode: namingMode ?? this.namingMode,
      prefix: prefix ?? this.prefix,
      lowercase: lowercase ?? this.lowercase,
      keepOriginalSuffix: keepOriginalSuffix ?? this.keepOriginalSuffix,
      numberDuplicates: numberDuplicates ?? this.numberDuplicates,
      autoAssign: autoAssign ?? this.autoAssign,
      conflictResolution: conflictResolution ?? this.conflictResolution,
      customTemplate: customTemplate ?? this.customTemplate,
      ucsVendor: ucsVendor ?? this.ucsVendor,
      ucsProject: ucsProject ?? this.ucsProject,
      outputPath: outputPath ?? this.outputPath,
      createDateSubfolder: createDateSubfolder ?? this.createDateSubfolder,
      overwriteExisting: overwriteExisting ?? this.overwriteExisting,
      generateManifest: generateManifest ?? this.generateManifest,
      generateLufsReport: generateLufsReport ?? this.generateLufsReport,
      keepIntermediateFiles: keepIntermediateFiles ?? this.keepIntermediateFiles,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'isBuiltIn': isBuiltIn,
      'lastSourcePath': lastSourcePath,
      'recursive': recursive,
      'fileFilter': fileFilter,
      'trimStart': trimStart,
      'trimEnd': trimEnd,
      'thresholdDb': thresholdDb,
      'minSilenceMs': minSilenceMs,
      'paddingBeforeMs': paddingBeforeMs,
      'paddingAfterMs': paddingAfterMs,
      'removeDcOffset': removeDcOffset,
      'preNormalizePeak': preNormalizePeak,
      'fadeIn': fadeIn,
      'fadeInMs': fadeInMs,
      'fadeOut': fadeOut,
      'fadeOutMs': fadeOutMs,
      'fadeCurve': fadeCurve.name,
      'highPassEnabled': highPassEnabled,
      'highPassFreq': highPassFreq,
      'lowPassEnabled': lowPassEnabled,
      'lowPassFreq': lowPassFreq,
      'normMode': normMode.name,
      'targetLufs': targetLufs,
      'truePeakCeiling': truePeakCeiling,
      'applyLimiter': applyLimiter,
      'allowClipping': allowClipping,
      'perCategoryOverrides': perCategoryOverrides.map(
        (k, v) => MapEntry(k.name, v),
      ),
      'categoryDetection': categoryDetection,
      'outputFormat': outputFormat.name,
      'sampleRate': sampleRate,
      'outputChannels': outputChannels.name,
      'monoMethod': monoMethod.name,
      'skipMonoDownmix': skipMonoDownmix,
      'stereoOverrideStages': stereoOverrideStages.toList(),
      'multiFormat': multiFormat,
      'multiFormatPresets': multiFormatPresets.map((e) => e.name).toList(),
      'subfolderPerFormat': subfolderPerFormat,
      'namingMode': namingMode.name,
      'prefix': prefix,
      'lowercase': lowercase,
      'keepOriginalSuffix': keepOriginalSuffix,
      'numberDuplicates': numberDuplicates,
      'autoAssign': autoAssign,
      'conflictResolution': conflictResolution.name,
      'customTemplate': customTemplate,
      'ucsVendor': ucsVendor,
      'ucsProject': ucsProject,
      'outputPath': outputPath,
      'createDateSubfolder': createDateSubfolder,
      'overwriteExisting': overwriteExisting,
      'generateManifest': generateManifest,
      'generateLufsReport': generateLufsReport,
      'keepIntermediateFiles': keepIntermediateFiles,
    };
  }

  factory SfxPipelinePreset.fromJson(Map<String, dynamic> json) {
    return SfxPipelinePreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      lastSourcePath: json['lastSourcePath'] as String?,
      recursive: json['recursive'] as bool? ?? true,
      fileFilter: json['fileFilter'] as String? ?? '*.{wav,mp3,flac,ogg,aif,aiff}',
      trimStart: json['trimStart'] as bool? ?? true,
      trimEnd: json['trimEnd'] as bool? ?? true,
      thresholdDb: (json['thresholdDb'] as num?)?.toDouble() ?? -40.0,
      minSilenceMs: (json['minSilenceMs'] as num?)?.toDouble() ?? 100.0,
      paddingBeforeMs: (json['paddingBeforeMs'] as num?)?.toDouble() ?? 5.0,
      paddingAfterMs: (json['paddingAfterMs'] as num?)?.toDouble() ?? 10.0,
      removeDcOffset: json['removeDcOffset'] as bool? ?? true,
      preNormalizePeak: json['preNormalizePeak'] as bool? ?? false,
      fadeIn: json['fadeIn'] as bool? ?? true,
      fadeInMs: (json['fadeInMs'] as num?)?.toDouble() ?? 2.0,
      fadeOut: json['fadeOut'] as bool? ?? true,
      fadeOutMs: (json['fadeOutMs'] as num?)?.toDouble() ?? 10.0,
      fadeCurve: _enumFromName(SfxFadeCurve.values, json['fadeCurve'] as String?) ?? SfxFadeCurve.linear,
      highPassEnabled: json['highPassEnabled'] as bool? ?? true,
      highPassFreq: (json['highPassFreq'] as num?)?.toDouble() ?? 40.0,
      lowPassEnabled: json['lowPassEnabled'] as bool? ?? true,
      lowPassFreq: (json['lowPassFreq'] as num?)?.toDouble() ?? 16000.0,
      normMode: _enumFromName(SfxNormMode.values, json['normMode'] as String?) ?? SfxNormMode.lufs,
      targetLufs: (json['targetLufs'] as num?)?.toDouble() ?? -18.0,
      truePeakCeiling: (json['truePeakCeiling'] as num?)?.toDouble() ?? -1.0,
      applyLimiter: json['applyLimiter'] as bool? ?? true,
      allowClipping: json['allowClipping'] as bool? ?? false,
      perCategoryOverrides: _parseCategoryOverrides(json['perCategoryOverrides'] as Map<String, dynamic>?),
      categoryDetection: json['categoryDetection'] as bool? ?? true,
      outputFormat: _enumFromName(SfxOutputFormat.values, json['outputFormat'] as String?) ?? SfxOutputFormat.wav24,
      sampleRate: json['sampleRate'] as int? ?? 48000,
      outputChannels: _enumFromName(OutputChannelMode.values, json['outputChannels'] as String?) ?? OutputChannelMode.mono,
      monoMethod: _enumFromName(MonoDownmixMethod.values, json['monoMethod'] as String?) ?? MonoDownmixMethod.sumHalf,
      skipMonoDownmix: json['skipMonoDownmix'] as bool? ?? true,
      stereoOverrideStages: (json['stereoOverrideStages'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      multiFormat: json['multiFormat'] as bool? ?? false,
      multiFormatPresets: (json['multiFormatPresets'] as List<dynamic>?)
              ?.map((e) => _enumFromName(SfxOutputFormat.values, e as String))
              .whereType<SfxOutputFormat>()
              .toSet() ??
          {SfxOutputFormat.wav24, SfxOutputFormat.ogg},
      subfolderPerFormat: json['subfolderPerFormat'] as bool? ?? true,
      namingMode: _enumFromName(SfxNamingMode.values, json['namingMode'] as String?) ?? SfxNamingMode.slotLabStageId,
      prefix: json['prefix'] as String? ?? 'sfx_',
      lowercase: json['lowercase'] as bool? ?? true,
      keepOriginalSuffix: json['keepOriginalSuffix'] as bool? ?? false,
      numberDuplicates: json['numberDuplicates'] as bool? ?? true,
      autoAssign: json['autoAssign'] as bool? ?? true,
      conflictResolution: _enumFromName(SfxConflictResolution.values, json['conflictResolution'] as String?) ?? SfxConflictResolution.replace,
      customTemplate: json['customTemplate'] as String? ?? '{prefix}{stage}{ext}',
      ucsVendor: json['ucsVendor'] as String? ?? '',
      ucsProject: json['ucsProject'] as String? ?? '',
      outputPath: json['outputPath'] as String?,
      createDateSubfolder: json['createDateSubfolder'] as bool? ?? true,
      overwriteExisting: json['overwriteExisting'] as bool? ?? false,
      generateManifest: json['generateManifest'] as bool? ?? true,
      generateLufsReport: json['generateLufsReport'] as bool? ?? true,
      keepIntermediateFiles: json['keepIntermediateFiles'] as bool? ?? false,
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static Map<SfxCategory, double?> _parseCategoryOverrides(Map<String, dynamic>? json) {
    if (json == null) return {};
    final result = <SfxCategory, double?>{};
    for (final entry in json.entries) {
      final cat = _enumFromName(SfxCategory.values, entry.key);
      if (cat != null) {
        result[cat] = (entry.value as num?)?.toDouble();
      }
    }
    return result;
  }
}

/// Helper: parse enum from name string
T? _enumFromName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUILT-IN PRESETS
// ═══════════════════════════════════════════════════════════════════════════════

class SfxBuiltInPresets {
  static final slotGameStandard = SfxPipelinePreset(
    id: 'builtin_slot_standard',
    name: 'Slot Game Standard',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
  );

  static final slotGameMobile = SfxPipelinePreset(
    id: 'builtin_slot_mobile',
    name: 'Slot Game Mobile',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
    targetLufs: -16.0,
    outputFormat: SfxOutputFormat.ogg,
    multiFormat: true,
    multiFormatPresets: {SfxOutputFormat.ogg, SfxOutputFormat.wav24},
  );

  static final wwiseReady = SfxPipelinePreset(
    id: 'builtin_wwise',
    name: 'Wwise Import Ready',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
    namingMode: SfxNamingMode.ucs,
    autoAssign: false,
  );

  static final fmodReady = SfxPipelinePreset(
    id: 'builtin_fmod',
    name: 'FMOD Import Ready',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
    namingMode: SfxNamingMode.ucs,
    autoAssign: false,
  );

  static final quickAndDirty = SfxPipelinePreset(
    id: 'builtin_quick',
    name: 'Quick & Dirty',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
    trimStart: false,
    trimEnd: false,
    removeDcOffset: false,
    fadeIn: false,
    fadeOut: false,
    normMode: SfxNormMode.peak,
    outputFormat: SfxOutputFormat.wav24,
    outputChannels: OutputChannelMode.keepOriginal,
    namingMode: SfxNamingMode.keepOriginal,
    autoAssign: false,
  );

  static final broadcastSfx = SfxPipelinePreset(
    id: 'builtin_broadcast',
    name: 'Broadcast SFX',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
    targetLufs: -23.0,
    outputChannels: OutputChannelMode.stereo,
    namingMode: SfxNamingMode.ucs,
    autoAssign: false,
  );

  static final all = [
    slotGameStandard,
    slotGameMobile,
    wwiseReady,
    fmodReady,
    quickAndDirty,
    broadcastSfx,
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE RESULT — Output of processing
// ═══════════════════════════════════════════════════════════════════════════════

/// Result for a single file in the pipeline
class SfxFileResult {
  final String sourcePath;
  final String sourceFilename;
  final String? outputPath;
  final String? outputFilename;
  final String? stageId;
  final bool assigned;
  final bool success;
  final String? error;

  // Stats
  final double originalLufs;
  final double finalLufs;
  final double gainApplied;
  final bool limiterEngaged;
  final double trimmedStartMs;
  final double trimmedEndMs;
  final double originalDuration;
  final double finalDuration;
  final int originalChannels;
  final int finalChannels;

  const SfxFileResult({
    required this.sourcePath,
    required this.sourceFilename,
    this.outputPath,
    this.outputFilename,
    this.stageId,
    this.assigned = false,
    this.success = true,
    this.error,
    this.originalLufs = 0.0,
    this.finalLufs = 0.0,
    this.gainApplied = 0.0,
    this.limiterEngaged = false,
    this.trimmedStartMs = 0.0,
    this.trimmedEndMs = 0.0,
    this.originalDuration = 0.0,
    this.finalDuration = 0.0,
    this.originalChannels = 2,
    this.finalChannels = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'output': outputFilename,
      'source': sourceFilename,
      'stage': stageId,
      'assigned': assigned,
      'success': success,
      if (error != null) 'error': error,
      'stats': {
        'originalLufs': originalLufs,
        'finalLufs': finalLufs,
        'gainApplied': gainApplied,
        'limiterEngaged': limiterEngaged,
        'trimmedStartMs': trimmedStartMs,
        'trimmedEndMs': trimmedEndMs,
        'originalDuration': originalDuration,
        'finalDuration': finalDuration,
        'originalChannels': originalChannels,
        'finalChannels': finalChannels,
      },
    };
  }
}

/// Batch result for the entire pipeline run
class SfxPipelineResult {
  final List<SfxFileResult> files;
  final SfxPipelinePreset preset;
  final DateTime timestamp;
  final int processingTimeMs;
  final String outputDirectory;

  const SfxPipelineResult({
    required this.files,
    required this.preset,
    required this.timestamp,
    required this.processingTimeMs,
    required this.outputDirectory,
  });

  int get totalFiles => files.length;
  int get successCount => files.where((f) => f.success).length;
  int get failedCount => files.where((f) => !f.success).length;
  int get assignedCount => files.where((f) => f.assigned).length;
  int get limiterCount => files.where((f) => f.limiterEngaged).length;
  int get stereoToMonoCount => files.where((f) => f.originalChannels > 1 && f.finalChannels == 1).length;

  double get totalSilenceTrimmedMs =>
      files.fold(0.0, (sum, f) => sum + f.trimmedStartMs + f.trimmedEndMs);

  double get avgLufsDelta {
    final successful = files.where((f) => f.success).toList();
    if (successful.isEmpty) return 0.0;
    return successful.fold(0.0, (sum, f) => sum + (f.finalLufs - f.originalLufs).abs()) / successful.length;
  }

  double get maxBoost =>
      files.fold(0.0, (max, f) => f.gainApplied > max ? f.gainApplied : max);
  double get maxCut =>
      files.fold(0.0, (min, f) => f.gainApplied < min ? f.gainApplied : min);

  bool get allSucceeded => failedCount == 0;

  List<SfxFileResult> get warnings =>
      files.where((f) => !f.success || !f.assigned || f.limiterEngaged).toList();

  /// Generate manifest.json content
  Map<String, dynamic> toManifestJson() {
    return {
      'generator': 'FluxForge Studio SFX Pipeline',
      'version': '1.0',
      'date': timestamp.toIso8601String(),
      'preset': preset.name,
      'pipeline': {
        'trim': {
          'enabled': preset.trimStart || preset.trimEnd,
          'thresholdDb': preset.thresholdDb,
          'paddingMs': [preset.paddingBeforeMs, preset.paddingAfterMs],
        },
        'normalize': {
          'mode': preset.normMode.name,
          'target': preset.targetLufs,
          'ceiling': preset.truePeakCeiling,
        },
        'format': {
          'type': preset.outputFormat.name,
          'sampleRate': preset.sampleRate,
          'channels': preset.outputChannels.name,
        },
        'naming': {
          'mode': preset.namingMode.name,
          'prefix': preset.prefix,
        },
      },
      'files': files.map((f) => f.toJson()).toList(),
      'summary': {
        'totalFiles': totalFiles,
        'successCount': successCount,
        'failedCount': failedCount,
        'totalSilenceTrimmedMs': totalSilenceTrimmedMs,
        'avgLufsDelta': avgLufsDelta,
        'limiterEngagedCount': limiterCount,
        'stereoToMonoCount': stereoToMonoCount,
        'stagesAssigned': assignedCount,
        'processingTimeMs': processingTimeMs,
      },
    };
  }

  /// Generate LUFS report text
  String toLufsReport() {
    final buf = StringBuffer();
    buf.writeln('${'=' * 51}');
    buf.writeln('  FluxForge Studio — SFX Pipeline LUFS Report');
    buf.writeln('  Generated: ${timestamp.toIso8601String().substring(0, 19).replaceAll('T', ' ')}');
    buf.writeln('  Preset: ${preset.name}');
    buf.writeln('${'=' * 51}');
    buf.writeln();
    buf.writeln('Target: ${preset.targetLufs.toStringAsFixed(1)} LUFS');
    buf.writeln('True Peak Ceiling: ${preset.truePeakCeiling.toStringAsFixed(1)} dBTP');
    buf.writeln();
    buf.writeln('--- PER-FILE ANALYSIS ${'─' * 30}');
    buf.writeln();

    // Header
    buf.writeln('${'File'.padRight(30)}│ LUFS   │ Gain   │ Status');
    buf.writeln('${'─' * 30}┼────────┼────────┼────────');

    for (final f in files.where((f) => f.success)) {
      final name = (f.outputFilename ?? f.sourceFilename).padRight(30);
      final lufs = f.finalLufs.toStringAsFixed(1).padLeft(6);
      final gain = '${f.gainApplied >= 0 ? "+" : ""}${f.gainApplied.toStringAsFixed(1)}dB'.padLeft(6);
      final status = f.limiterEngaged ? 'Limiter' : 'OK';
      buf.writeln('$name│ $lufs │ $gain │ $status');
    }

    buf.writeln();
    buf.writeln('--- SUMMARY ${'─' * 40}');
    buf.writeln();
    buf.writeln('Total files:      $totalFiles');
    buf.writeln('All at target:    ${allSucceeded ? "Yes" : "No"}');
    buf.writeln('Limiter engaged:  $limiterCount files');
    buf.writeln('Max gain applied: +${maxBoost.toStringAsFixed(1)} dB');
    buf.writeln('Min gain applied: ${maxCut.toStringAsFixed(1)} dB');

    return buf.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE PROCESSING STATE — Live progress tracking
// ═══════════════════════════════════════════════════════════════════════════════

/// Processing step in the pipeline execution
enum SfxPipelineStep {
  trimAndClean,
  normalize,
  convertAndExport,
  autoAssign,
}

extension SfxPipelineStepExt on SfxPipelineStep {
  String get displayName {
    switch (this) {
      case SfxPipelineStep.trimAndClean:
        return 'Trim & Clean';
      case SfxPipelineStep.normalize:
        return 'Normalize';
      case SfxPipelineStep.convertAndExport:
        return 'Convert & Export';
      case SfxPipelineStep.autoAssign:
        return 'Auto-Assign';
    }
  }
}

/// Live progress state during pipeline execution
class SfxPipelineProgress {
  final SfxPipelineStep currentStep;
  final int currentFileIndex;
  final int totalFiles;
  final String? currentFilename;
  final double overallProgress;
  final Map<SfxPipelineStep, bool> stepCompleted;
  final Map<SfxPipelineStep, int> stepDurationMs;
  final int elapsedMs;

  const SfxPipelineProgress({
    this.currentStep = SfxPipelineStep.trimAndClean,
    this.currentFileIndex = 0,
    this.totalFiles = 0,
    this.currentFilename,
    this.overallProgress = 0.0,
    this.stepCompleted = const {},
    this.stepDurationMs = const {},
    this.elapsedMs = 0,
  });

  int? get estimatedRemainingMs {
    if (overallProgress <= 0 || elapsedMs <= 0) return null;
    return ((elapsedMs / overallProgress) * (1.0 - overallProgress)).round();
  }
}
