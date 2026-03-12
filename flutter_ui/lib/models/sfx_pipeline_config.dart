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
  symbolLand,       // Symbol land sounds (SymbolS01-15, SymbolB01Land) — distinct from reel mechanics
  symbolPreshow,    // Ultra-short symbol preview ticks (0.1-0.2s, too short for LUFS)
  winCelebrations,
  scatterLand,      // Scatter land per-reel (escalating loudness by count)
  wildLand,         // Wild land sounds — quieter accents (~-23 LUFS)
  coinRollup,       // Coin/rollup loops — sits under wins (~-27 LUFS)
  payline,          // Payline highlight sounds (~-20 LUFS)
  screenEffect,     // Screen shake, flash, etc. — one-shot non-looping
  ambientLoops,
  featureTriggers,
  anticipation,
  musicBigWin,      // Big win celebration music — loudest
  musicFeature,     // Free spins / bonus / hold music — louder than base
  musicBase,        // Base game background music — quietest music layer
  musicSpins,       // Spin loop music — mid-level looping (~-22 LUFS)
  musicPicker,      // Picker/bonus selection music (~-24 LUFS)
  music,            // Generic music (fallback if sub-category not detected)
  voiceOver,        // VO / narration / announcer — must be intelligible over everything
  unknown,
}

extension SfxCategoryExt on SfxCategory {
  String get displayName {
    switch (this) {
      case SfxCategory.uiClicks:
        return 'UI / Clicks';
      case SfxCategory.reelMechanics:
        return 'Reel Mechanics';
      case SfxCategory.symbolLand:
        return 'Symbol Land';
      case SfxCategory.symbolPreshow:
        return 'Symbol Preshow';
      case SfxCategory.winCelebrations:
        return 'Win Celebrations';
      case SfxCategory.scatterLand:
        return 'Scatter Land';
      case SfxCategory.wildLand:
        return 'Wild Land';
      case SfxCategory.coinRollup:
        return 'Coin / Rollup';
      case SfxCategory.payline:
        return 'Payline';
      case SfxCategory.screenEffect:
        return 'Screen Effect';
      case SfxCategory.ambientLoops:
        return 'Ambient / Loops';
      case SfxCategory.featureTriggers:
        return 'Feature Triggers';
      case SfxCategory.anticipation:
        return 'Anticipation';
      case SfxCategory.musicBigWin:
        return 'Music — Big Win';
      case SfxCategory.musicFeature:
        return 'Music — Feature';
      case SfxCategory.musicBase:
        return 'Music — Base Game';
      case SfxCategory.musicSpins:
        return 'Music — Spins';
      case SfxCategory.musicPicker:
        return 'Music — Picker';
      case SfxCategory.music:
        return 'Music';
      case SfxCategory.voiceOver:
        return 'Voice Over';
      case SfxCategory.unknown:
        return 'Unknown';
    }
  }

  /// Filename patterns that identify this category.
  /// Patterns are matched against BOTH the original lowercase filename
  /// AND a CamelCase→snake_case normalized version (see [fromFilename]).
  List<String> get patterns {
    switch (this) {
      case SfxCategory.uiClicks:
        return ['ui_', 'click_', 'button_'];
      case SfxCategory.reelMechanics:
        return ['reel_land', 'reel_stop', 'reel_spin', 'reel_', 'spin_', 'stop_'];
      case SfxCategory.symbolLand:
        return ['symbol_s', 'symbol_b', 'symbol_land',
                'sym_hp', 'sym_mp',   // SymHp*Win, SymMp*Win
                'bonus_symbol'];
      case SfxCategory.symbolPreshow:
        return ['symbol_preshow', 'preshow_', 'sym_preshow'];
      case SfxCategory.winCelebrations:
        return ['win_', 'big_', 'fanfare_'];
      case SfxCategory.scatterLand:
        return ['scatter_land', 'sym_scatter_land', 'scatter_stop'];
      case SfxCategory.wildLand:
        return ['wild_land'];
      case SfxCategory.coinRollup:
        return ['coin_loop', 'coin_', 'rollup_low', 'rollup_'];
      case SfxCategory.payline:
        return ['payline'];
      case SfxCategory.screenEffect:
        return ['screen_shake', 'screen_flash', 'screen_effect', 'screen_'];
      case SfxCategory.ambientLoops:
        return ['amb_', 'drone_', 'amb_bg'];
      case SfxCategory.featureTriggers:
        return ['fs_', 'scatter_win', 'scatter_', 'wild_', 'bonus_',
                'symbol_w'];  // Wild symbol (SymbolW01)
      case SfxCategory.anticipation:
        return ['anticipation', 'tension_', 'near_miss_', 'near_win_'];
      case SfxCategory.musicBigWin:
        return ['big_win_loop', 'big_win_music', 'big_win_start',
                'big_win_end', 'big_win_alert', 'big_win_tier',
                'bigwin_music', 'music_bigwin', 'music_big_win',
                'bw_music', 'mus_bw',
                'bigwinloop', 'bigwinmusic', 'musicbigwin',
                'bigwinalert', 'bigwinstart', 'bigwinend', 'bigwintier'];
      case SfxCategory.musicFeature:
        return ['free_spin_music', 'freespin_music', 'fs_music', 'music_fs',
                'bonus_music', 'music_bonus', 'hold_music', 'music_hold',
                'feature_music', 'music_feature', 'mus_fs',
                'freespinmusic', 'fsmusic', 'bonusmusic', 'holdmusic',
                'featuremusic', 'musicfeature'];
      case SfxCategory.musicBase:
        return ['base_game_music', 'base_music', 'music_base', 'bgm_base',
                'main_theme', 'base_theme', 'mus_bg',
                'basegamemusic', 'basemusic', 'musicbase', 'maintheme',
                'basetheme'];
      case SfxCategory.musicSpins:
        return ['spins_loop', 'spin_loop', 'spin_music', 'spins_music',
                'spinsloop', 'spinloop'];
      case SfxCategory.musicPicker:
        return ['picker_music', 'picker_loop', 'pickermusicloop',
                'picker_music_loop'];
      case SfxCategory.music:
        return ['music_', 'bgm_', 'soundtrack_', 'theme_', 'ost_'];
      case SfxCategory.voiceOver:
        return ['vo_', 'voice_', 'narr_', 'narrator_', 'announce_',
                'announcer_', 'dialogue_',
                'voiceover', 'voice_over'];
      case SfxCategory.unknown:
        return [];
    }
  }

  /// Patterns that require prefix match (startsWith) instead of contains.
  /// Prevents false positives: 'vo_win_01.wav' should be voiceOver, not winCelebrations.
  /// Only applies to categories where filenames reliably START with the category prefix.
  List<String> get prefixPatterns {
    switch (this) {
      case SfxCategory.voiceOver:
        // VO files are named vo_*, voice_*, narr_*, etc.
        // Using prefix match prevents 'vo_stop_01.wav' from matching reelMechanics ('stop_')
        // 'speech_' excluded — too ambiguous (speech_bubble_pop.wav = UI SFX, not VO)
        return ['vo_', 'voice_', 'narr_', 'narrator_', 'announce_',
                'announcer_', 'dialogue_'];
      default:
        return [];
    }
  }

  /// Default channel mode for this category
  OutputChannelMode get defaultChannelMode {
    switch (this) {
      case SfxCategory.music:
      case SfxCategory.musicBase:
      case SfxCategory.musicFeature:
      case SfxCategory.musicBigWin:
      case SfxCategory.musicSpins:
      case SfxCategory.musicPicker:
        return OutputChannelMode.stereo;       // Music ALWAYS stereo
      case SfxCategory.featureTriggers:
      case SfxCategory.scatterLand:
      case SfxCategory.wildLand:
        return OutputChannelMode.stereo;       // Feature symbols — stereo
      case SfxCategory.ambientLoops:
        return OutputChannelMode.stereo;       // Ambience — stereo
      case SfxCategory.winCelebrations:
        return OutputChannelMode.stereo;       // Wins — stereo (production value)
      case SfxCategory.screenEffect:
        return OutputChannelMode.stereo;       // Screen effects — stereo impact
      case SfxCategory.uiClicks:
        return OutputChannelMode.mono;         // UI clicks — mono OK
      case SfxCategory.reelMechanics:
        return OutputChannelMode.mono;         // Reel mechanics — mono OK
      case SfxCategory.symbolLand:
        return OutputChannelMode.keepOriginal; // Symbol land — varies
      case SfxCategory.symbolPreshow:
        return OutputChannelMode.mono;         // Ultra-short ticks — mono
      case SfxCategory.coinRollup:
        return OutputChannelMode.stereo;       // Coin sounds — stereo shimmer
      case SfxCategory.payline:
        return OutputChannelMode.stereo;       // Payline — stereo sweep
      case SfxCategory.anticipation:
        return OutputChannelMode.keepOriginal; // Anticipation — keep as-is
      case SfxCategory.voiceOver:
        return OutputChannelMode.mono;         // VO — mono (single speaker)
      case SfxCategory.unknown:
        return OutputChannelMode.keepOriginal;
    }
  }

  /// Whether this category should skip trim by default.
  /// Only short, percussive sounds (UI clicks, reel mechanics) are safe to trim.
  /// Everything else may have intentional fades, intros, or gradual onsets.
  bool get defaultSkipTrim {
    switch (this) {
      case SfxCategory.uiClicks:
      case SfxCategory.reelMechanics:
      case SfxCategory.symbolPreshow:
        return false;         // Short percussive — safe to trim
      default:
        return true;          // Everything else: skip trim (intentional fades/intros)
    }
  }

  /// Detect category from filename.
  ///
  /// Three-phase detection:
  /// 1. **Prefix patterns** (highest priority) — categories where filenames
  ///    reliably START with the category prefix (e.g., `vo_win_01.wav` is VO,
  ///    not winCelebrations). Checked with `startsWith`, longest first.
  /// 2. **Contains patterns on original** — standard longest-match-first.
  /// 3. **Contains patterns on CamelCase-normalized** — converts CamelCase to
  ///    snake_case (e.g., `BigWinStart` → `big_win_start`) and re-runs matching.
  ///    Handles real-world asset packs that use CamelCase naming (Aztec, etc.).
  static SfxCategory fromFilename(String filename) {
    final lower = filename.toLowerCase();
    // Strip extension for pattern matching
    final dotIdx = lower.lastIndexOf('.');
    final stem = dotIdx > 0 ? lower.substring(0, dotIdx) : lower;

    // Phase 1: Prefix patterns (highest priority)
    final prefixCandidates = <(String, SfxCategory)>[];
    for (final cat in SfxCategory.values) {
      if (cat == SfxCategory.unknown) continue;
      for (final pattern in cat.prefixPatterns) {
        prefixCandidates.add((pattern, cat));
      }
    }
    prefixCandidates.sort((a, b) => b.$1.length.compareTo(a.$1.length));
    for (final (pattern, cat) in prefixCandidates) {
      if (stem.startsWith(pattern)) return cat;
    }

    // Phase 2: Contains patterns on original lowercase (longest-match-first)
    final candidates = <(String, SfxCategory)>[];
    for (final cat in SfxCategory.values) {
      if (cat == SfxCategory.unknown) continue;
      for (final pattern in cat.patterns) {
        candidates.add((pattern, cat));
      }
    }
    candidates.sort((a, b) => b.$1.length.compareTo(a.$1.length));
    for (final (pattern, cat) in candidates) {
      if (stem.contains(pattern)) return cat;
    }

    // Phase 3: CamelCase → snake_case normalization, then re-match
    // MUST use original filename (before toLowerCase) — camelToSnake needs uppercase letters
    final originalStem = filename.lastIndexOf('.') > 0
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
    final normalized = camelToSnake(originalStem);
    if (normalized != stem) {
      for (final (pattern, cat) in prefixCandidates) {
        if (normalized.startsWith(pattern)) return cat;
      }
      for (final (pattern, cat) in candidates) {
        if (normalized.contains(pattern)) return cat;
      }
    }

    return SfxCategory.unknown;
  }

  /// Convert CamelCase/PascalCase to snake_case.
  /// - `BigWinStart` → `big_win_start`
  /// - `ReelLand1` → `reel_land_1`
  /// - `SymbolS01` → `symbol_s_01`
  /// - `UiSpinSlam` → `ui_spin_slam`
  /// - `SymHp1Win` → `sym_hp_1_win`
  static String camelToSnake(String input) {
    final buf = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      final code = ch.codeUnitAt(0);
      final isUpper = code >= 65 && code <= 90;  // A-Z
      final isDigit = code >= 48 && code <= 57;  // 0-9
      if (i > 0) {
        final prevCode = input[i - 1].codeUnitAt(0);
        final prevIsUpper = prevCode >= 65 && prevCode <= 90;
        final prevIsDigit = prevCode >= 48 && prevCode <= 57;
        final prevIsLower = prevCode >= 97 && prevCode <= 122;
        // Insert _ before: uppercase after lowercase, digit after letter,
        // letter after digit, or uppercase before lowercase in a run of uppers
        if (isUpper && (prevIsLower || prevIsDigit)) {
          buf.write('_');
        } else if (isUpper && prevIsUpper && i + 1 < input.length) {
          final nextCode = input[i + 1].codeUnitAt(0);
          if (nextCode >= 97 && nextCode <= 122) {
            buf.write('_');
          }
        } else if (isDigit && !prevIsDigit && prevCode != 95) {
          buf.write('_');
        } else if (!isDigit && !isUpper && prevIsDigit) {
          buf.write('_');
        }
      }
      buf.write(ch.toLowerCase());
    }
    return buf.toString();
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

  // P0.3: True peak (inter-sample peak via 4x oversampling)
  final double truePeakDbtp;

  // P1.2: Stereo imbalance detection
  final double peakLrDeltaDb;   // |L_peak - R_peak| in dB (0 = balanced)
  final double rmsLrDeltaDb;    // |L_rms - R_rms| in dB (0 = balanced)
  final bool isContentMono;     // true if L≈R content (dual-mono file)

  // P1.3: Flat factor (consecutive peak samples — pre-limiting detection)
  final double flatFactor;      // 0 = no clipping, >10 = pre-limited

  // P2.2: Audio-identical detection
  final String? duplicateOf;    // filename if audio-identical to another file

  // P1.1: Loudness group membership
  final String? loudnessGroup;  // e.g. "Win", "ScatterLand", "B01Land" — null if not in a group

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
    this.truePeakDbtp = -100.0,
    this.peakLrDeltaDb = 0.0,
    this.rmsLrDeltaDb = 0.0,
    this.isContentMono = false,
    this.flatFactor = 0.0,
    this.duplicateOf,
    this.loudnessGroup,
  });

  bool get isStereo => channels >= 2;
  bool get isMono => channels == 1;
  bool get hasSilence => silenceStartMs > 50 || silenceEndMs > 50;
  bool get hasDcOffset => dcOffset.abs() > 0.005;
  bool get isQuiet => integratedLufs < -30;

  /// True if this file has ISP (inter-sample peak) issues above -1.0 dBTP
  bool get hasIspIssue => truePeakDbtp > -1.0;

  /// True if this file was pre-limited at source (flat factor indicates brick-wall limiting)
  bool get isPreLimited => flatFactor > 10.0;

  /// True if L/R stereo imbalance exceeds 3 dB (worth flagging)
  bool get hasStereoImbalance => peakLrDeltaDb > 3.0;

  /// True if this file is a duplicate of another
  bool get isDuplicate => duplicateOf != null;

  /// True if this file belongs to an escalating loudness group
  bool get isInLoudnessGroup => loudnessGroup != null;

  String get formatLabel {
    final bitLabel = bitDepth == 32 ? '32f' : '$bitDepth';
    final srLabel = sampleRate >= 1000 ? '${(sampleRate / 1000).toStringAsFixed(1)}kHz' : '${sampleRate}Hz';
    return 'WAV$bitLabel/$srLabel';
  }

  String get channelLabel => isStereo ? 'St' : 'Mo';

  SfxScanResult copyWith({
    bool? selected,
    SfxCategory? detectedCategory,
    double? truePeakDbtp,
    double? peakLrDeltaDb,
    double? rmsLrDeltaDb,
    bool? isContentMono,
    double? flatFactor,
    String? duplicateOf,
    String? loudnessGroup,
  }) {
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
      detectedCategory: detectedCategory ?? this.detectedCategory,
      selected: selected ?? this.selected,
      truePeakDbtp: truePeakDbtp ?? this.truePeakDbtp,
      peakLrDeltaDb: peakLrDeltaDb ?? this.peakLrDeltaDb,
      rmsLrDeltaDb: rmsLrDeltaDb ?? this.rmsLrDeltaDb,
      isContentMono: isContentMono ?? this.isContentMono,
      flatFactor: flatFactor ?? this.flatFactor,
      duplicateOf: duplicateOf ?? this.duplicateOf,
      loudnessGroup: loudnessGroup ?? this.loudnessGroup,
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

  // Step 2: Category-specific trim skip
  final Set<SfxCategory> noTrimCategories;

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
  final Set<String> stereoOverrideStages;
  final Map<SfxCategory, OutputChannelMode> perCategoryChannels;
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
    // Step 2: Category-specific trim skip
    this.noTrimCategories = const {
      SfxCategory.music, SfxCategory.musicBase, SfxCategory.musicFeature,
      SfxCategory.musicBigWin, SfxCategory.musicSpins, SfxCategory.musicPicker,
      SfxCategory.ambientLoops, SfxCategory.anticipation,
      SfxCategory.winCelebrations, SfxCategory.featureTriggers,
      SfxCategory.scatterLand, SfxCategory.wildLand, SfxCategory.symbolLand,
      SfxCategory.coinRollup, SfxCategory.payline, SfxCategory.screenEffect,
      SfxCategory.voiceOver, SfxCategory.unknown,
    },
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
    this.stereoOverrideStages = const {},
    this.perCategoryChannels = const {},
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
    Set<SfxCategory>? noTrimCategories,
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
    Set<String>? stereoOverrideStages,
    Map<SfxCategory, OutputChannelMode>? perCategoryChannels,
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
      noTrimCategories: noTrimCategories ?? this.noTrimCategories,
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
      stereoOverrideStages: stereoOverrideStages ?? this.stereoOverrideStages,
      perCategoryChannels: perCategoryChannels ?? this.perCategoryChannels,
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
      'noTrimCategories': noTrimCategories.map((c) => c.name).toList(),
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
      'stereoOverrideStages': stereoOverrideStages.toList(),
      'perCategoryChannels': perCategoryChannels.map(
        (k, v) => MapEntry(k.name, v.name),
      ),
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
      noTrimCategories: (json['noTrimCategories'] as List<dynamic>?)
              ?.map((e) => _enumFromName(SfxCategory.values, e as String))
              .whereType<SfxCategory>()
              .toSet() ??
          {SfxCategory.music, SfxCategory.musicBase, SfxCategory.musicFeature,
           SfxCategory.musicBigWin, SfxCategory.musicSpins, SfxCategory.musicPicker,
           SfxCategory.ambientLoops, SfxCategory.anticipation,
           SfxCategory.winCelebrations, SfxCategory.featureTriggers,
           SfxCategory.scatterLand, SfxCategory.wildLand, SfxCategory.symbolLand,
           SfxCategory.coinRollup, SfxCategory.payline, SfxCategory.screenEffect,
           SfxCategory.voiceOver, SfxCategory.unknown},
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
      stereoOverrideStages: (json['stereoOverrideStages'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      perCategoryChannels: _parseCategoryChannels(json['perCategoryChannels'] as Map<String, dynamic>?),
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

  static Map<SfxCategory, OutputChannelMode> _parseCategoryChannels(Map<String, dynamic>? json) {
    if (json == null) return {};
    final result = <SfxCategory, OutputChannelMode>{};
    for (final entry in json.entries) {
      final cat = _enumFromName(SfxCategory.values, entry.key);
      final mode = _enumFromName(OutputChannelMode.values, entry.value as String?);
      if (cat != null && mode != null) {
        result[cat] = mode;
      }
    }
    return result;
  }

  /// Resolve channel mode for a given category.
  /// Priority: perCategoryChannels > category default > global outputChannels
  OutputChannelMode resolveChannelMode(SfxCategory category) {
    return perCategoryChannels[category] ?? category.defaultChannelMode;
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
  /// Industry-standard per-category LUFS targets for iGaming SFX.
  /// UI clicks must cut through; ambient/music stays underneath.
  /// Public so wizard can use defaults when enabling per-category toggles.
  static const slotCategoryLufs = <SfxCategory, double?>{
    SfxCategory.uiClicks: -12.0,        // Short, precise — must be heard over everything
    SfxCategory.reelMechanics: -16.0,    // Constant presence — must not fatigue
    SfxCategory.symbolLand: -20.0,       // Symbol land — mid-level SFX
    SfxCategory.symbolPreshow: -20.0,    // Ultra-short ticks — RMS-based (too short for LUFS)
    SfxCategory.winCelebrations: -14.0,  // Exciting but controlled
    SfxCategory.scatterLand: -17.0,      // Scatter — escalating, prominent
    SfxCategory.wildLand: -23.0,         // Wild land — quiet accent
    SfxCategory.coinRollup: -27.0,       // Coin — sits under wins
    SfxCategory.payline: -20.0,          // Payline — mid-level indicator
    SfxCategory.screenEffect: -18.0,     // Screen shake/flash — impact moment
    SfxCategory.ambientLoops: -23.0,     // Background bed — quiet foundation
    SfxCategory.featureTriggers: -14.0,  // Key moments — must grab attention
    SfxCategory.anticipation: -18.0,     // Gradual build-up — mid level
    SfxCategory.musicBigWin: -18.0,     // Big win music — loudest music, must feel epic
    SfxCategory.musicFeature: -20.0,    // Feature music (FS/bonus) — louder than base
    SfxCategory.musicBase: -23.0,       // Base game music — quiet background bed
    SfxCategory.musicSpins: -22.0,      // Spin loop music — mid-level
    SfxCategory.musicPicker: -24.0,     // Picker selection music — quiet
    SfxCategory.music: -23.0,           // Generic music fallback — same as base
    SfxCategory.voiceOver: -14.0,      // VO must be intelligible — cut through mix
  };

  /// Realistic Slot Mix preset — derived from Aztec theme production analysis (2026-03).
  /// Based on actual measured LUFS values from a real iGaming sound package.
  /// More nuanced than "Slot Game Standard" — matches what sound designers actually deliver.
  static const realisticSlotMixLufs = <SfxCategory, double?>{
    SfxCategory.uiClicks: -25.0,          // Real UI sounds are -22 to -33 LUFS
    SfxCategory.reelMechanics: -31.0,     // Reel lands are very quiet (~-31 LUFS)
    SfxCategory.symbolLand: -20.0,        // Symbol lands ~-20 LUFS
    SfxCategory.symbolPreshow: -24.0,     // Preshow ticks (RMS-based)
    SfxCategory.winCelebrations: -15.0,   // Win1→Win7 center (~-15, escalating)
    SfxCategory.scatterLand: -17.5,       // Scatter lands (~-17.5, escalating)
    SfxCategory.wildLand: -23.0,          // Wild lands (~-23 LUFS)
    SfxCategory.coinRollup: -27.0,        // Coin loops (~-27 LUFS)
    SfxCategory.payline: -20.0,           // Payline sounds (~-20 LUFS)
    SfxCategory.screenEffect: -18.0,      // Screen shake (~-18 LUFS)
    SfxCategory.ambientLoops: -35.0,      // Ambient bed (~-35 LUFS, much quieter!)
    SfxCategory.featureTriggers: -17.0,   // Scatter win, bonus triggers (~-17)
    SfxCategory.anticipation: -15.0,      // Anticipation builds (~-14 to -16)
    SfxCategory.musicBigWin: -14.0,       // BigWin music (~-14 LUFS)
    SfxCategory.musicFeature: -20.0,      // Feature music (~-20)
    SfxCategory.musicBase: -17.0,         // Base game loops are ~-17 LUFS (NOT -23!)
    SfxCategory.musicSpins: -22.0,        // Spin loops (~-22 LUFS)
    SfxCategory.musicPicker: -24.0,       // Picker loop (~-24 LUFS)
    SfxCategory.music: -20.0,             // Generic music fallback
    SfxCategory.voiceOver: -14.0,         // VO intelligibility
  };

  static final slotGameStandard = SfxPipelinePreset(
    id: 'builtin_slot_standard',
    name: 'Slot Game Standard',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
    perCategoryOverrides: slotCategoryLufs,
    categoryDetection: true,
  );

  /// Mobile preset — 2 LUFS louder per category (small speakers need more headroom)
  static const _mobileCategoryLufs = <SfxCategory, double?>{
    SfxCategory.uiClicks: -10.0,
    SfxCategory.reelMechanics: -14.0,
    SfxCategory.symbolLand: -18.0,
    SfxCategory.symbolPreshow: -18.0,
    SfxCategory.winCelebrations: -12.0,
    SfxCategory.scatterLand: -15.0,
    SfxCategory.wildLand: -21.0,
    SfxCategory.coinRollup: -25.0,
    SfxCategory.payline: -18.0,
    SfxCategory.screenEffect: -16.0,
    SfxCategory.ambientLoops: -21.0,
    SfxCategory.featureTriggers: -12.0,
    SfxCategory.anticipation: -16.0,
    SfxCategory.musicBigWin: -16.0,
    SfxCategory.musicFeature: -18.0,
    SfxCategory.musicBase: -21.0,
    SfxCategory.musicSpins: -20.0,
    SfxCategory.musicPicker: -22.0,
    SfxCategory.music: -21.0,
    SfxCategory.voiceOver: -12.0,
  };

  static final slotGameMobile = SfxPipelinePreset(
    id: 'builtin_slot_mobile',
    name: 'Slot Game Mobile',
    createdAt: DateTime(2026, 1, 1),
    isBuiltIn: true,
    targetLufs: -16.0,
    outputFormat: SfxOutputFormat.ogg,
    multiFormat: true,
    multiFormatPresets: {SfxOutputFormat.ogg, SfxOutputFormat.wav24},
    perCategoryOverrides: _mobileCategoryLufs,
    categoryDetection: true,
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

  /// Realistic Slot Mix — derived from analyzing real production sound packages.
  /// Values match what professional sound designers actually deliver.
  /// Unlike "Slot Game Standard" which is theoretical, this preset preserves
  /// the natural loudness hierarchy found in production iGaming assets.
  static final realisticSlotMix = SfxPipelinePreset(
    id: 'builtin_realistic_slot',
    name: 'Realistic Slot Mix',
    createdAt: DateTime(2026, 3, 12),
    isBuiltIn: true,
    perCategoryOverrides: realisticSlotMixLufs,
    categoryDetection: true,
    highPassFreq: 20.0,  // Lower HP filter (some assets have useful sub-bass)
  );

  static final all = [
    slotGameStandard,
    realisticSlotMix,
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
