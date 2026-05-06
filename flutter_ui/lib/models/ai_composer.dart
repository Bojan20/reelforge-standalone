// AI Composer — Dart models mirroring rf-composer JSON shapes.
//
// All these structs are produced/consumed by the FFI calls in
// `lib/src/rust/native_ffi.dart` (composer_*).
//
// Source of truth lives in Rust:
// - ProviderSelection / *Config → crates/rf-composer/src/registry.rs
// - AiProviderInfo / Capabilities → crates/rf-composer/src/provider.rs
// - StageAssetMap / StageIntent / AssetIntent → crates/rf-composer/src/schema.rs
// - ComposerOutput / ComposerJob → crates/rf-composer/src/composer.rs

import 'dart:convert';

enum AiProviderId { ollama, anthropic, azureOpenai }

extension AiProviderIdX on AiProviderId {
  String get wireName => switch (this) {
        AiProviderId.ollama => 'ollama',
        AiProviderId.anthropic => 'anthropic',
        AiProviderId.azureOpenai => 'azure_open_ai',
      };

  String get displayLabel => switch (this) {
        AiProviderId.ollama => 'Local (Ollama)',
        AiProviderId.anthropic => 'Anthropic (BYOK)',
        AiProviderId.azureOpenai => 'Azure OpenAI (Enterprise)',
      };

  /// True if this provider does NOT egress data outside customer's network.
  bool get isAirGapped => this == AiProviderId.ollama;

  static AiProviderId fromWire(String s) => switch (s) {
        'ollama' => AiProviderId.ollama,
        'anthropic' => AiProviderId.anthropic,
        'azure_open_ai' => AiProviderId.azureOpenai,
        _ => AiProviderId.ollama,
      };
}

class OllamaConfig {
  final String endpoint;
  final String model;
  const OllamaConfig({required this.endpoint, required this.model});

  factory OllamaConfig.defaults() =>
      const OllamaConfig(endpoint: 'http://127.0.0.1:11434', model: 'llama3.1:70b');

  factory OllamaConfig.fromJson(Map<String, dynamic> j) => OllamaConfig(
        endpoint: j['endpoint'] as String? ?? 'http://127.0.0.1:11434',
        model: j['model'] as String? ?? 'llama3.1:70b',
      );

  Map<String, dynamic> toJson() => {'endpoint': endpoint, 'model': model};

  OllamaConfig copyWith({String? endpoint, String? model}) =>
      OllamaConfig(endpoint: endpoint ?? this.endpoint, model: model ?? this.model);
}

class AnthropicConfig {
  final String endpoint;
  final String model;
  const AnthropicConfig({required this.endpoint, required this.model});

  factory AnthropicConfig.defaults() => const AnthropicConfig(
      endpoint: 'https://api.anthropic.com', model: 'claude-sonnet-4-5');

  factory AnthropicConfig.fromJson(Map<String, dynamic> j) => AnthropicConfig(
        endpoint: j['endpoint'] as String? ?? 'https://api.anthropic.com',
        model: j['model'] as String? ?? 'claude-sonnet-4-5',
      );

  Map<String, dynamic> toJson() => {'endpoint': endpoint, 'model': model};

  AnthropicConfig copyWith({String? endpoint, String? model}) =>
      AnthropicConfig(endpoint: endpoint ?? this.endpoint, model: model ?? this.model);
}

class AzureConfig {
  final String endpoint;
  final String deployment;
  final String apiVersion;
  const AzureConfig({
    required this.endpoint,
    required this.deployment,
    required this.apiVersion,
  });

  factory AzureConfig.defaults() => const AzureConfig(
        endpoint: '',
        deployment: '',
        apiVersion: '2024-08-01-preview',
      );

  factory AzureConfig.fromJson(Map<String, dynamic> j) => AzureConfig(
        endpoint: j['endpoint'] as String? ?? '',
        deployment: j['deployment'] as String? ?? '',
        apiVersion: j['api_version'] as String? ?? '2024-08-01-preview',
      );

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'deployment': deployment,
        'api_version': apiVersion,
      };

  AzureConfig copyWith({String? endpoint, String? deployment, String? apiVersion}) =>
      AzureConfig(
        endpoint: endpoint ?? this.endpoint,
        deployment: deployment ?? this.deployment,
        apiVersion: apiVersion ?? this.apiVersion,
      );
}

class ProviderSelection {
  final AiProviderId provider;
  final OllamaConfig ollama;
  final AnthropicConfig anthropic;
  final AzureConfig azure;

  const ProviderSelection({
    required this.provider,
    required this.ollama,
    required this.anthropic,
    required this.azure,
  });

  factory ProviderSelection.defaults() => ProviderSelection(
        provider: AiProviderId.ollama,
        ollama: OllamaConfig.defaults(),
        anthropic: AnthropicConfig.defaults(),
        azure: AzureConfig.defaults(),
      );

  factory ProviderSelection.fromJson(Map<String, dynamic> j) => ProviderSelection(
        provider: AiProviderIdX.fromWire(j['provider'] as String? ?? 'ollama'),
        ollama: OllamaConfig.fromJson(
            (j['ollama'] as Map?)?.cast<String, dynamic>() ?? const {}),
        anthropic: AnthropicConfig.fromJson(
            (j['anthropic'] as Map?)?.cast<String, dynamic>() ?? const {}),
        azure: AzureConfig.fromJson(
            (j['azure'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'provider': provider.wireName,
        'ollama': ollama.toJson(),
        'anthropic': anthropic.toJson(),
        'azure': azure.toJson(),
      };

  String toJsonString() => json.encode(toJson());

  ProviderSelection copyWith({
    AiProviderId? provider,
    OllamaConfig? ollama,
    AnthropicConfig? anthropic,
    AzureConfig? azure,
  }) =>
      ProviderSelection(
        provider: provider ?? this.provider,
        ollama: ollama ?? this.ollama,
        anthropic: anthropic ?? this.anthropic,
        azure: azure ?? this.azure,
      );
}

class ProviderCapabilities {
  final bool streaming;
  final bool structuredOutput;
  final bool airGapped;
  final int maxContextTokens;
  final double costPer1mInputUsd;

  const ProviderCapabilities({
    required this.streaming,
    required this.structuredOutput,
    required this.airGapped,
    required this.maxContextTokens,
    required this.costPer1mInputUsd,
  });

  factory ProviderCapabilities.fromJson(Map<String, dynamic> j) => ProviderCapabilities(
        streaming: j['streaming'] as bool? ?? false,
        structuredOutput: j['structured_output'] as bool? ?? false,
        airGapped: j['air_gapped'] as bool? ?? false,
        maxContextTokens: (j['max_context_tokens'] as num?)?.toInt() ?? 0,
        costPer1mInputUsd: (j['cost_per_1m_input_usd'] as num?)?.toDouble() ?? 0.0,
      );
}

class AiProviderInfo {
  final AiProviderId id;
  final String model;
  final String endpoint;
  final ProviderCapabilities capabilities;
  final bool healthy;

  const AiProviderInfo({
    required this.id,
    required this.model,
    required this.endpoint,
    required this.capabilities,
    required this.healthy,
  });

  factory AiProviderInfo.fromJson(Map<String, dynamic> j) => AiProviderInfo(
        id: AiProviderIdX.fromWire(j['id'] as String? ?? 'ollama'),
        model: j['model'] as String? ?? '',
        endpoint: j['endpoint'] as String? ?? '',
        capabilities: ProviderCapabilities.fromJson(
            (j['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {}),
        healthy: j['healthy'] as bool? ?? false,
      );
}

// ── Composer ────────────────────────────────────────────────────────────────

class ComposerJob {
  final String description;
  final List<String> jurisdictions;
  final bool includeBrief;
  final bool includeVoiceDirection;
  final bool includeQualityGrade;

  const ComposerJob({
    required this.description,
    required this.jurisdictions,
    this.includeBrief = true,
    this.includeVoiceDirection = true,
    this.includeQualityGrade = true,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'jurisdictions': jurisdictions,
        'include_brief': includeBrief,
        'include_voice_direction': includeVoiceDirection,
        'include_quality_grade': includeQualityGrade,
      };

  String toJsonString() => json.encode(toJson());
}

class ComposerOutput {
  final String jobId;
  final StageAssetMap assetMap;
  final String? audioBriefMarkdown;
  final String? voiceDirectionMarkdown;
  final int repairAttempts;
  final int totalTokensInput;
  final int totalTokensOutput;
  final int totalElapsedMs;

  const ComposerOutput({
    required this.jobId,
    required this.assetMap,
    required this.audioBriefMarkdown,
    required this.voiceDirectionMarkdown,
    required this.repairAttempts,
    required this.totalTokensInput,
    required this.totalTokensOutput,
    required this.totalElapsedMs,
  });

  factory ComposerOutput.fromJson(Map<String, dynamic> j) => ComposerOutput(
        jobId: j['job_id'] as String? ?? '',
        assetMap: StageAssetMap.fromJson(
            (j['asset_map'] as Map?)?.cast<String, dynamic>() ?? const {}),
        audioBriefMarkdown: j['audio_brief_markdown'] as String?,
        voiceDirectionMarkdown: j['voice_direction_markdown'] as String?,
        repairAttempts: (j['repair_attempts'] as num?)?.toInt() ?? 0,
        totalTokensInput: (j['total_tokens_input'] as num?)?.toInt() ?? 0,
        totalTokensOutput: (j['total_tokens_output'] as num?)?.toInt() ?? 0,
        totalElapsedMs: (j['total_elapsed_ms'] as num?)?.toInt() ?? 0,
      );
}

class StageAssetMap {
  final String theme;
  final String mood;
  final int targetBpm;
  final List<StageIntent> stages;
  final ComplianceHints complianceHints;
  final int selfQualityScore;
  final String selfCritique;

  const StageAssetMap({
    required this.theme,
    required this.mood,
    required this.targetBpm,
    required this.stages,
    required this.complianceHints,
    required this.selfQualityScore,
    required this.selfCritique,
  });

  factory StageAssetMap.fromJson(Map<String, dynamic> j) => StageAssetMap(
        theme: j['theme'] as String? ?? '',
        mood: j['mood'] as String? ?? '',
        targetBpm: (j['target_bpm'] as num?)?.toInt() ?? 0,
        stages: ((j['stages'] as List?) ?? const [])
            .map((e) => StageIntent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        complianceHints: ComplianceHints.fromJson(
            (j['compliance_hints'] as Map?)?.cast<String, dynamic>() ?? const {}),
        selfQualityScore: (j['self_quality_score'] as num?)?.toInt() ?? 0,
        selfCritique: j['self_critique'] as String? ?? '',
      );
}

class StageIntent {
  final String stageId;
  final List<AssetIntent> assets;
  const StageIntent({required this.stageId, required this.assets});

  factory StageIntent.fromJson(Map<String, dynamic> j) => StageIntent(
        stageId: j['stage_id'] as String? ?? '',
        assets: ((j['assets'] as List?) ?? const [])
            .map((e) => AssetIntent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class AssetIntent {
  final String kind;
  final String suggestedName;
  final String mood;
  final int dynamicLevel;
  final int? lengthMs;
  final String bus;
  final String generationPrompt;

  const AssetIntent({
    required this.kind,
    required this.suggestedName,
    required this.mood,
    required this.dynamicLevel,
    required this.lengthMs,
    required this.bus,
    required this.generationPrompt,
  });

  factory AssetIntent.fromJson(Map<String, dynamic> j) => AssetIntent(
        kind: j['kind'] as String? ?? '',
        suggestedName: j['suggested_name'] as String? ?? '',
        mood: j['mood'] as String? ?? '',
        dynamicLevel: (j['dynamic_level'] as num?)?.toInt() ?? 0,
        lengthMs: (j['length_ms'] as num?)?.toInt(),
        bus: j['bus'] as String? ?? 'sfx',
        generationPrompt: j['generation_prompt'] as String? ?? '',
      );
}

// ── Audio production batch ──────────────────────────────────────────────────

enum AudioBackendId { elevenlabs, suno, local }

extension AudioBackendIdX on AudioBackendId {
  String get wireName => switch (this) {
        AudioBackendId.elevenlabs => 'elevenlabs',
        AudioBackendId.suno => 'suno',
        AudioBackendId.local => 'local',
      };
  String get displayLabel => switch (this) {
        AudioBackendId.elevenlabs => 'ElevenLabs (SFX + TTS)',
        AudioBackendId.suno => 'Suno (Music)',
        AudioBackendId.local => 'Local (Offline)',
      };
  static AudioBackendId fromWire(String s) => switch (s) {
        'elevenlabs' => AudioBackendId.elevenlabs,
        'suno' => AudioBackendId.suno,
        'local' => AudioBackendId.local,
        _ => AudioBackendId.local,
      };
}

enum AudioKind { sfx, tts, music }

extension AudioKindX on AudioKind {
  String get wireName => switch (this) {
        AudioKind.sfx => 'sfx',
        AudioKind.tts => 'tts',
        AudioKind.music => 'music',
      };
  String get displayLabel => switch (this) {
        AudioKind.sfx => 'SFX',
        AudioKind.tts => 'Voice (TTS)',
        AudioKind.music => 'Music',
      };
  static AudioKind fromWire(String s) => switch (s) {
        'sfx' => AudioKind.sfx,
        'tts' => AudioKind.tts,
        'music' => AudioKind.music,
        _ => AudioKind.sfx,
      };
}

class AudioRoutingTable {
  final Map<AudioKind, AudioBackendId> map;
  const AudioRoutingTable(this.map);

  factory AudioRoutingTable.defaults() => const AudioRoutingTable({
        AudioKind.sfx: AudioBackendId.elevenlabs,
        AudioKind.tts: AudioBackendId.elevenlabs,
        AudioKind.music: AudioBackendId.suno,
      });

  factory AudioRoutingTable.airGapped() => const AudioRoutingTable({
        AudioKind.sfx: AudioBackendId.local,
        AudioKind.tts: AudioBackendId.local,
        AudioKind.music: AudioBackendId.local,
      });

  factory AudioRoutingTable.fromJson(Map<String, dynamic> j) {
    final raw = (j['map'] as Map?)?.cast<String, dynamic>() ?? const {};
    final out = <AudioKind, AudioBackendId>{};
    raw.forEach((k, v) {
      out[AudioKindX.fromWire(k)] = AudioBackendIdX.fromWire(v as String);
    });
    return AudioRoutingTable(out);
  }

  Map<String, dynamic> toJson() => {
        'map': {
          for (final e in map.entries) e.key.wireName: e.value.wireName,
        },
      };

  AudioRoutingTable copyWithKind(AudioKind k, AudioBackendId b) {
    final m = Map<AudioKind, AudioBackendId>.from(map);
    m[k] = b;
    return AudioRoutingTable(m);
  }
}

class AudioAssetResult {
  final String stageId;
  final String assetName;
  final AudioBackendId backend;
  final String? path;
  final String? format;
  final int bytes;
  final int durationMs;
  final String? error;

  const AudioAssetResult({
    required this.stageId,
    required this.assetName,
    required this.backend,
    required this.path,
    required this.format,
    required this.bytes,
    required this.durationMs,
    required this.error,
  });

  bool get ok => error == null && path != null;

  factory AudioAssetResult.fromJson(Map<String, dynamic> j) => AudioAssetResult(
        stageId: j['stage_id'] as String? ?? '',
        assetName: j['asset_name'] as String? ?? '',
        backend: AudioBackendIdX.fromWire(j['backend'] as String? ?? 'local'),
        path: j['path'] as String?,
        format: j['format'] as String?,
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
      );
}

class AudioBatchProgress {
  final bool active;
  final int total;
  final int completed;
  final int succeeded;
  final int failed;
  final String? current;
  final bool cancelRequested;
  final List<AudioAssetResult> partialResults;

  const AudioBatchProgress({
    required this.active,
    required this.total,
    required this.completed,
    required this.succeeded,
    required this.failed,
    required this.current,
    required this.cancelRequested,
    required this.partialResults,
  });

  factory AudioBatchProgress.idle() => const AudioBatchProgress(
        active: false,
        total: 0,
        completed: 0,
        succeeded: 0,
        failed: 0,
        current: null,
        cancelRequested: false,
        partialResults: [],
      );

  factory AudioBatchProgress.fromJson(Map<String, dynamic> j) =>
      AudioBatchProgress(
        active: j['active'] as bool? ?? false,
        total: (j['total'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        succeeded: (j['succeeded'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        current: j['current'] as String?,
        cancelRequested: j['cancel_requested'] as bool? ?? false,
        partialResults: ((j['partial_results'] as List?) ?? const [])
            .map((e) =>
                AudioAssetResult.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class AudioBatchOutput {
  final String jobId;
  final List<AudioAssetResult> results;
  final int total;
  final int succeeded;
  final int failed;
  final int elapsedMs;

  const AudioBatchOutput({
    required this.jobId,
    required this.results,
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.elapsedMs,
  });

  factory AudioBatchOutput.fromJson(Map<String, dynamic> j) => AudioBatchOutput(
        jobId: j['job_id'] as String? ?? '',
        results: ((j['results'] as List?) ?? const [])
            .map((e) =>
                AudioAssetResult.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        succeeded: (j['succeeded'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        elapsedMs: (j['elapsed_ms'] as num?)?.toInt() ?? 0,
      );
}

class ComplianceHints {
  final List<String> targetJurisdictions;
  final bool ldwAudioSuppressed;
  final bool proportionalCelebrations;
  final bool nearMissNeutralized;
  final String reviewerNotes;

  const ComplianceHints({
    required this.targetJurisdictions,
    required this.ldwAudioSuppressed,
    required this.proportionalCelebrations,
    required this.nearMissNeutralized,
    required this.reviewerNotes,
  });

  factory ComplianceHints.fromJson(Map<String, dynamic> j) => ComplianceHints(
        targetJurisdictions:
            ((j['target_jurisdictions'] as List?) ?? const []).map((e) => e.toString()).toList(),
        ldwAudioSuppressed: j['ldw_audio_suppressed'] as bool? ?? false,
        proportionalCelebrations: j['proportional_celebrations'] as bool? ?? false,
        nearMissNeutralized: j['near_miss_neutralized'] as bool? ?? false,
        reviewerNotes: j['reviewer_notes'] as String? ?? '',
      );
}
