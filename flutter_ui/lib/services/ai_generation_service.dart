// T8.1–T8.4: AI Audio Generation Service
//
// Procedural AI audio generation pipeline:
// T8.1: Text prompt → AudioDescriptor (structured audio spec)
// T8.2: GenerationSpec → BackendRequest (AudioCraft/ElevenLabs/etc)
// T8.3: PostProcessingConfig (loudness, fade, format)
// T8.4: FFNC auto-categorization of generated assets

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────

/// Available AI generation backends (T8.2)
enum GenerationBackend { audiocraft, elevenlabs, stabilityAi, openAi, stub }

extension GenerationBackendExt on GenerationBackend {
  String get rustName {
    switch (this) {
      case GenerationBackend.audiocraft:  return 'audiocraft';
      case GenerationBackend.elevenlabs:  return 'elevenlabs';
      case GenerationBackend.stabilityAi: return 'stability_ai';
      case GenerationBackend.openAi:      return 'openai';
      case GenerationBackend.stub:        return 'stub';
    }
  }

  String get displayName {
    switch (this) {
      case GenerationBackend.audiocraft:  return 'AudioCraft (Local)';
      case GenerationBackend.elevenlabs:  return 'ElevenLabs Sound Effects';
      case GenerationBackend.stabilityAi: return 'Stability AI (Stable Audio)';
      case GenerationBackend.openAi:      return 'OpenAI Audio';
      case GenerationBackend.stub:        return 'Test Stub';
    }
  }

  bool get requiresInternet => this != GenerationBackend.audiocraft && this != GenerationBackend.stub;
}

/// Structured audio descriptor extracted from a text prompt (T8.1)
class AudioDescriptor {
  final String prompt;
  final String category;
  final String tier;
  final int durationMs;
  final int voiceCount;
  final bool canLoop;
  final bool isRequired;
  final String mood;
  final String style;
  final List<String> instruments;
  final int tempoBpm;
  final List<String> generationTags;
  final double confidence;
  final String generationPrompt; // derived from to_generation_prompt()

  const AudioDescriptor({
    required this.prompt,
    required this.category,
    required this.tier,
    required this.durationMs,
    required this.voiceCount,
    required this.canLoop,
    required this.isRequired,
    required this.mood,
    required this.style,
    required this.instruments,
    required this.tempoBpm,
    required this.generationTags,
    required this.confidence,
    this.generationPrompt = '',
  });

  factory AudioDescriptor.fromJson(Map<String, dynamic> json) => AudioDescriptor(
    prompt: json['prompt'] as String,
    category: json['category'] as String? ?? 'BaseGame',
    tier: json['tier'] as String? ?? 'standard',
    durationMs: json['duration_ms'] as int? ?? 0,
    voiceCount: json['voice_count'] as int? ?? 1,
    canLoop: json['can_loop'] as bool? ?? false,
    isRequired: json['is_required'] as bool? ?? false,
    mood: json['mood'] as String? ?? 'Neutral',
    style: json['style'] as String? ?? 'Unknown',
    instruments: (json['instruments'] as List?)?.map((e) => e.toString()).toList() ?? [],
    tempoBpm: json['tempo_bpm'] as int? ?? 0,
    generationTags: (json['generation_tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
  );

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'category': category,
    'tier': tier,
    'duration_ms': durationMs,
    'voice_count': voiceCount,
    'can_loop': canLoop,
    'is_required': isRequired,
    'mood': mood,
    'style': style,
    'instruments': instruments,
    'tempo_bpm': tempoBpm,
    'generation_tags': generationTags,
    'confidence': confidence,
  };

  String get categoryDisplay {
    switch (category) {
      case 'Win': return 'Win';
      case 'Jackpot': return 'Jackpot';
      case 'Feature': return 'Feature/Bonus';
      case 'Ambient': return 'Ambient/Music';
      case 'UI': return 'User Interface';
      case 'NearMiss': return 'Near Miss';
      case 'Transition': return 'Transition';
      default: return 'Base Game';
    }
  }
}

/// Generation spec for AI backend (T8.2)
class GenerationSpec {
  final String backend;
  final String generationPrompt;
  final String? negativePrompt;
  final int durationMs;
  final int sampleRate;
  final int numCandidates;
  final int? seed;
  final AudioDescriptor descriptor;
  final Map<String, dynamic> backendConfig;

  const GenerationSpec({
    required this.backend,
    required this.generationPrompt,
    this.negativePrompt,
    required this.durationMs,
    required this.sampleRate,
    required this.numCandidates,
    this.seed,
    required this.descriptor,
    required this.backendConfig,
  });

  factory GenerationSpec.fromJson(Map<String, dynamic> json) => GenerationSpec(
    backend: json['backend'] as String? ?? 'Stub',
    generationPrompt: json['generation_prompt'] as String,
    negativePrompt: json['negative_prompt'] as String?,
    durationMs: json['duration_ms'] as int? ?? 0,
    sampleRate: json['sample_rate'] as int? ?? 44100,
    numCandidates: json['num_candidates'] as int? ?? 3,
    seed: json['seed'] as int?,
    descriptor: AudioDescriptor.fromJson(json['descriptor'] as Map<String, dynamic>),
    backendConfig: json['backend_config'] as Map<String, dynamic>? ?? {},
  );

  Map<String, dynamic> toJson() => {
    'backend': backend,
    'generation_prompt': generationPrompt,
    if (negativePrompt != null) 'negative_prompt': negativePrompt,
    'duration_ms': durationMs,
    'sample_rate': sampleRate,
    'num_candidates': numCandidates,
    if (seed != null) 'seed': seed,
    'descriptor': descriptor.toJson(),
    'backend_config': backendConfig,
  };
}

/// Generation status
enum GenerationStatus { pending, processing, complete, failed }

/// Result of a completed generation (T8.2)
class GenerationResult {
  final GenerationSpec spec;
  final GenerationStatus status;
  final List<String> outputUrls;
  final int actualDurationMs;
  final int generationTimeMs;
  final String suggestedFilename;
  final String? failureReason;

  const GenerationResult({
    required this.spec,
    required this.status,
    required this.outputUrls,
    required this.actualDurationMs,
    required this.generationTimeMs,
    required this.suggestedFilename,
    this.failureReason,
  });

  factory GenerationResult.fromJson(Map<String, dynamic> json) {
    GenerationStatus status;
    final statusData = json['status'];
    if (statusData is String) {
      switch (statusData) {
        case 'Complete':    status = GenerationStatus.complete; break;
        case 'Processing':  status = GenerationStatus.processing; break;
        case 'Failed':      status = GenerationStatus.failed; break;
        default:            status = GenerationStatus.pending;
      }
    } else if (statusData is Map && statusData.containsKey('Failed')) {
      status = GenerationStatus.failed;
    } else {
      status = GenerationStatus.pending;
    }

    return GenerationResult(
      spec: GenerationSpec.fromJson(json['spec'] as Map<String, dynamic>),
      status: status,
      outputUrls: (json['output_urls'] as List?)?.map((e) => e.toString()).toList() ?? [],
      actualDurationMs: json['actual_duration_ms'] as int? ?? 0,
      generationTimeMs: json['generation_time_ms'] as int? ?? 0,
      suggestedFilename: json['suggested_filename'] as String? ?? 'audio.wav',
      failureReason: statusData is Map ? statusData['Failed'] != null ? (statusData['Failed'] as Map)['reason'] as String? : null : null,
    );
  }

  bool get isSuccess => status == GenerationStatus.complete;
}

/// Post-processing configuration (T8.3)
class PostProcessingConfig {
  final double loudnessLufs;
  final int fadeInMs;
  final int fadeOutMs;
  final bool detectLoopPoints;
  final bool trimSilence;
  final bool applyCompression;
  final double compressionRatio;
  final bool applyLimiter;
  final String format;
  final int sampleRate;
  final int bitDepth;
  final List<String> pipelineSteps;

  const PostProcessingConfig({
    required this.loudnessLufs,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.detectLoopPoints,
    required this.trimSilence,
    required this.applyCompression,
    required this.compressionRatio,
    required this.applyLimiter,
    required this.format,
    required this.sampleRate,
    required this.bitDepth,
    required this.pipelineSteps,
  });

  factory PostProcessingConfig.fromJson(Map<String, dynamic> json) {
    final loudness = json['loudness'];
    double lufs = -18.0;
    if (loudness is Map && loudness.containsKey('Custom')) {
      lufs = (loudness['Custom'] as num).toDouble();
    } else if (loudness == 'EbuR128') {
      lufs = -23.0;
    } else if (loudness == 'AesStreaming') {
      lufs = -16.0;
    }

    final fade = json['fade'] as Map<String, dynamic>? ?? {};
    final dynamics = json['dynamics'] as Map<String, dynamic>? ?? {};
    final format = json['format'] as Map<String, dynamic>? ?? {};

    return PostProcessingConfig(
      loudnessLufs: lufs,
      fadeInMs: fade['fade_in_ms'] as int? ?? 5,
      fadeOutMs: fade['fade_out_ms'] as int? ?? 50,
      detectLoopPoints: json['detect_loop_points'] as bool? ?? false,
      trimSilence: json['trim_silence'] as bool? ?? true,
      applyCompression: dynamics['apply_compression'] as bool? ?? false,
      compressionRatio: (dynamics['compression_ratio'] as num?)?.toDouble() ?? 1.0,
      applyLimiter: dynamics['apply_limiter'] as bool? ?? true,
      format: _parseFormatName(format['format']),
      sampleRate: format['sample_rate'] as int? ?? 44100,
      bitDepth: format['bit_depth'] as int? ?? 24,
      pipelineSteps: const [], // computed separately
    );
  }

  static String _parseFormatName(dynamic fmt) {
    if (fmt == null) return 'WAV';
    if (fmt is String) return fmt;
    if (fmt is Map) return fmt.keys.first.toString();
    return 'WAV';
  }
}

/// FFNC classification result (T8.4)
class FfncClassificationResult {
  final String category;
  final String ffncCode;
  final String displayName;
  final List<String> tags;
  final String suggestedEventName;
  final double confidence;
  final bool isRequired;
  final String tierStr;

  const FfncClassificationResult({
    required this.category,
    required this.ffncCode,
    required this.displayName,
    required this.tags,
    required this.suggestedEventName,
    required this.confidence,
    required this.isRequired,
    required this.tierStr,
  });

  factory FfncClassificationResult.fromJson(Map<String, dynamic> json) => FfncClassificationResult(
    category: json['ffnc_code'] as String? ?? '??',
    ffncCode: json['ffnc_code'] as String? ?? '??',
    displayName: json['display_name'] as String? ?? '',
    tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
    suggestedEventName: json['suggested_event_name'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    isRequired: json['is_required'] as bool? ?? false,
    tierStr: json['tier_str'] as String? ?? '',
  );
}

/// Available backend info
class BackendInfo {
  final String name;
  final String displayName;
  final bool requiresInternet;
  final bool available;
  const BackendInfo({required this.name, required this.displayName, required this.requiresInternet, required this.available});
  factory BackendInfo.fromJson(Map<String, dynamic> json) => BackendInfo(
    name: json['name'] as String,
    displayName: json['display_name'] as String,
    requiresInternet: json['requires_internet'] as bool,
    available: json['available'] as bool,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AiGenerationService (T8.1–T8.4)
// ─────────────────────────────────────────────────────────────────────────────

/// Procedural AI audio generation service.
///
/// Full pipeline from text description to categorized audio asset:
///
/// ```dart
/// final svc = sl<AiGenerationService>();
///
/// // T8.1: Parse prompt
/// final desc = await svc.parsePrompt('epic jackpot win with brass fanfare');
///
/// // T8.2: Build spec + run (stub for testing, real backend in production)
/// final result = await svc.generateWithStub(prompt: 'epic win fanfare');
///
/// // T8.3: Get post-processing config
/// final postConfig = await svc.getPostProcessingConfig(desc!);
///
/// // T8.4: Classify result
/// final classification = await svc.classify(desc!);
/// ```
class AiGenerationService extends ChangeNotifier {
  final NativeFFI _ffi;

  AudioDescriptor? _lastDescriptor;
  GenerationResult? _lastResult;
  FfncClassificationResult? _lastClassification;
  PostProcessingConfig? _lastPostProcessConfig;
  List<BackendInfo> _availableBackends = [];
  bool _isWorking = false;

  AiGenerationService(this._ffi);

  AudioDescriptor? get lastDescriptor => _lastDescriptor;
  GenerationResult? get lastResult => _lastResult;
  FfncClassificationResult? get lastClassification => _lastClassification;
  PostProcessingConfig? get lastPostProcessConfig => _lastPostProcessConfig;
  List<BackendInfo> get availableBackends => List.unmodifiable(_availableBackends);
  bool get isWorking => _isWorking;
  bool get hasResult => _lastResult != null;

  /// Load available backends from the Rust engine.
  void loadAvailableBackends() {
    final json = _ffi.aiGenAvailableBackends();
    if (json != null) {
      final list = jsonDecode(json) as List;
      _availableBackends = list.map((e) => BackendInfo.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  /// T8.1: Parse a text prompt into an AudioDescriptor.
  Future<AudioDescriptor?> parsePrompt(String prompt) async {
    _isWorking = true;
    notifyListeners();
    try {
      final desc = await Future(() {
        final json = _ffi.aiGenParsePrompt(prompt);
        if (json == null) return null;
        return AudioDescriptor.fromJson(jsonDecode(json) as Map<String, dynamic>);
      });
      _lastDescriptor = desc;
      return desc;
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  /// T8.2: Build generation spec for a specific backend.
  Future<GenerationSpec?> buildSpec(String prompt, GenerationBackend backend) async {
    return await Future(() {
      final json = _ffi.aiGenBuildSpec(prompt, backend.rustName);
      if (json == null) return null;
      return GenerationSpec.fromJson(jsonDecode(json) as Map<String, dynamic>);
    });
  }

  /// T8.2: Execute full pipeline with stub backend (offline, for testing).
  Future<GenerationResult?> generateWithStub({required String prompt}) async {
    _isWorking = true;
    notifyListeners();
    try {
      // Build spec
      final specJson = await Future(() => _ffi.aiGenBuildSpec(prompt, 'stub'));
      if (specJson == null) return null;

      // Execute stub
      final resultJson = await Future(() => _ffi.aiGenExecuteStub(specJson));
      if (resultJson == null) return null;

      final result = GenerationResult.fromJson(jsonDecode(resultJson) as Map<String, dynamic>);
      _lastResult = result;
      _lastDescriptor = result.spec.descriptor;

      // Auto-classify (T8.4)
      await _autoClassify(result.spec.descriptor);

      return result;
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  /// T8.3: Get post-processing config for a descriptor.
  Future<PostProcessingConfig?> getPostProcessingConfig(AudioDescriptor descriptor) async {
    final config = await Future(() {
      final json = _ffi.aiGenPostprocessConfig(jsonEncode(descriptor.toJson()));
      if (json == null) return null;
      return PostProcessingConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    });
    _lastPostProcessConfig = config;
    notifyListeners();
    return config;
  }

  /// T8.4: Auto-classify an audio descriptor into FFNC categories.
  Future<FfncClassificationResult?> classify(AudioDescriptor descriptor) async {
    return _autoClassify(descriptor);
  }

  Future<FfncClassificationResult?> _autoClassify(AudioDescriptor descriptor) async {
    final classification = await Future(() {
      final json = _ffi.aiGenClassifyAsset(jsonEncode(descriptor.toJson()), null);
      if (json == null) return null;
      return FfncClassificationResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    });
    _lastClassification = classification;
    notifyListeners();
    return classification;
  }

  /// Full pipeline: prompt → parse → stub generate → classify → postprocess config.
  ///
  /// Returns all results in a single call.
  Future<AiGenerationPipelineResult?> runFullPipeline(String prompt) async {
    _isWorking = true;
    notifyListeners();
    try {
      final desc = await parsePrompt(prompt);
      if (desc == null) return null;

      final result = await generateWithStub(prompt: prompt);
      if (result == null) return null;

      final classification = await classify(desc);
      final postConfig = await getPostProcessingConfig(desc);

      return AiGenerationPipelineResult(
        descriptor: desc,
        result: result,
        classification: classification,
        postProcessingConfig: postConfig,
      );
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }
}

/// Complete pipeline result
class AiGenerationPipelineResult {
  final AudioDescriptor descriptor;
  final GenerationResult result;
  final FfncClassificationResult? classification;
  final PostProcessingConfig? postProcessingConfig;

  const AiGenerationPipelineResult({
    required this.descriptor,
    required this.result,
    this.classification,
    this.postProcessingConfig,
  });
}
