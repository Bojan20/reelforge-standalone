// AI Composer service — single ChangeNotifier wrapping the FFI.
//
// All FFI calls are routed through here so widgets stay clean.
// Long-running operations (composer.run) are exposed as Futures.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/ai_composer.dart';
import '../src/rust/native_ffi.dart';

class AiComposerService extends ChangeNotifier {
  AiComposerService(this._ffi);

  final NativeFFI _ffi;

  ProviderSelection _selection = ProviderSelection.defaults();
  AiProviderInfo? _activeInfo;
  bool _busy = false;
  String? _lastError;
  ComposerOutput? _lastOutput;
  bool _anthropicKeyPresent = false;
  bool _azureKeyPresent = false;

  /// Current provider selection (mirror of what the Rust registry holds).
  ProviderSelection get selection => _selection;

  /// Most recent describe call (null until refreshActiveInfo() runs).
  AiProviderInfo? get activeInfo => _activeInfo;

  /// True while a long-running composer.run is in flight.
  bool get isBusy => _busy;

  /// Last error message captured from the FFI (after a failed call).
  String? get lastError => _lastError;

  /// Most recent successful ComposerOutput.
  ComposerOutput? get lastOutput => _lastOutput;

  /// Whether the Anthropic API key is stored in the OS keychain.
  bool get anthropicKeyPresent => _anthropicKeyPresent;

  /// Whether the Azure OpenAI API key is stored in the OS keychain.
  bool get azureKeyPresent => _azureKeyPresent;

  /// Pull the current selection from Rust (call once at startup).
  Future<void> refreshSelection() async {
    final raw = _ffi.composerGetSelectionJson();
    if (raw == null) return;
    try {
      final parsed = json.decode(raw) as Map<String, dynamic>;
      _selection = ProviderSelection.fromJson(parsed);
      notifyListeners();
    } catch (_) {
      // Leave previous selection in place.
    }
  }

  /// Push a new selection to Rust. Returns true on success.
  Future<bool> setSelection(ProviderSelection next) async {
    final ok = _ffi.composerSetSelectionJson(next.toJsonString());
    if (ok) {
      _selection = next;
      notifyListeners();
    } else {
      _captureError();
    }
    return ok;
  }

  /// Run a fresh describe (incl. health check). Slow on Anthropic/Azure
  /// because it actually hits the network — call sparingly.
  Future<void> refreshActiveInfo() async {
    _busy = true;
    notifyListeners();
    try {
      final raw = await _runOffMain(_ffi.composerDescribeActiveJson);
      if (raw != null) {
        try {
          _activeInfo =
              AiProviderInfo.fromJson(json.decode(raw) as Map<String, dynamic>);
        } catch (_) {
          _activeInfo = null;
        }
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Refresh both keychain presence flags (anthropic, azure_openai).
  Future<void> refreshCredentialsPresence() async {
    _anthropicKeyPresent = _ffi.composerCredentialExists('anthropic');
    _azureKeyPresent = _ffi.composerCredentialExists('azure_openai');
    notifyListeners();
  }

  /// Store an Anthropic API key in the keychain.
  Future<bool> putAnthropicKey(String key) async {
    final ok = _ffi.composerCredentialPut('anthropic', key);
    if (ok) {
      _anthropicKeyPresent = true;
      notifyListeners();
    } else {
      _captureError();
    }
    return ok;
  }

  /// Delete the Anthropic API key from the keychain.
  Future<bool> deleteAnthropicKey() async {
    final ok = _ffi.composerCredentialDelete('anthropic');
    if (ok) {
      _anthropicKeyPresent = false;
      notifyListeners();
    }
    return ok;
  }

  /// Store an Azure OpenAI API key in the keychain.
  Future<bool> putAzureKey(String key) async {
    final ok = _ffi.composerCredentialPut('azure_openai', key);
    if (ok) {
      _azureKeyPresent = true;
      notifyListeners();
    } else {
      _captureError();
    }
    return ok;
  }

  /// Delete the Azure OpenAI key.
  Future<bool> deleteAzureKey() async {
    final ok = _ffi.composerCredentialDelete('azure_openai');
    if (ok) {
      _azureKeyPresent = false;
      notifyListeners();
    }
    return ok;
  }

  /// Run a composer job. Returns the output on success, null on failure
  /// (use [lastError] to surface to the user).
  Future<ComposerOutput?> run(ComposerJob job) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final raw = await _runOffMain(() => _ffi.composerRunJson(job.toJsonString()));
      if (raw == null) {
        _captureError();
        return null;
      }
      try {
        final parsed = json.decode(raw) as Map<String, dynamic>;
        _lastOutput = ComposerOutput.fromJson(parsed);
        notifyListeners();
        return _lastOutput;
      } catch (e) {
        _lastError = 'parse: $e';
        return null;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Quick smoke test — health check only, no inference.
  Future<Map<String, dynamic>?> dryRun() async {
    final raw = await _runOffMain(_ffi.composerRunDryJson);
    if (raw == null) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _captureError() {
    _lastError = _ffi.composerLastErrorJson();
  }

  /// Run a sync FFI call off the main isolate via a microtask so the UI
  /// stays responsive. (FFI itself is sync — the heavy work is in Rust's
  /// tokio runtime — but the Dart→FFI boundary still blocks the main isolate
  /// briefly. Using `Future.microtask` lets the UI rebuild before the call.)
  Future<T> _runOffMain<T>(T Function() fn) async {
    await Future<void>.delayed(Duration.zero);
    return fn();
  }

  // ── Audio production batch ────────────────────────────────────────────

  AudioRoutingTable _routing = AudioRoutingTable.defaults();
  AudioBatchProgress _audioProgress = AudioBatchProgress.idle();
  AudioBatchOutput? _audioResult;
  bool _elevenlabsKeyPresent = false;
  bool _sunoKeyPresent = false;
  Timer? _audioPollTimer;

  AudioRoutingTable get routing => _routing;
  AudioBatchProgress get audioProgress => _audioProgress;
  AudioBatchOutput? get audioResult => _audioResult;
  bool get elevenlabsKeyPresent => _elevenlabsKeyPresent;
  bool get sunoKeyPresent => _sunoKeyPresent;

  Future<void> refreshRouting() async {
    final raw = _ffi.composerAudioRoutingGetJson();
    if (raw == null) return;
    try {
      _routing = AudioRoutingTable.fromJson(json.decode(raw) as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> setRouting(AudioRoutingTable next) async {
    final ok = _ffi.composerAudioRoutingSetJson(json.encode(next.toJson()));
    if (ok) {
      _routing = next;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> switchToAirGapped() async {
    final ok = _ffi.composerAudioAirGapped();
    if (ok) {
      _routing = AudioRoutingTable.airGapped();
      notifyListeners();
    }
    return ok;
  }

  Future<void> refreshAudioCredentialsPresence() async {
    _elevenlabsKeyPresent = _ffi.composerAudioCredentialExists('elevenlabs');
    _sunoKeyPresent = _ffi.composerAudioCredentialExists('suno');
    notifyListeners();
  }

  Future<bool> putElevenlabsKey(String key) async {
    final ok = _ffi.composerAudioCredentialPut('elevenlabs', key);
    if (ok) {
      _elevenlabsKeyPresent = true;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> deleteElevenlabsKey() async {
    final ok = _ffi.composerAudioCredentialDelete('elevenlabs');
    if (ok) {
      _elevenlabsKeyPresent = false;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> putSunoKey(String key) async {
    final ok = _ffi.composerAudioCredentialPut('suno', key);
    if (ok) {
      _sunoKeyPresent = true;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> deleteSunoKey() async {
    final ok = _ffi.composerAudioCredentialDelete('suno');
    if (ok) {
      _sunoKeyPresent = false;
      notifyListeners();
    }
    return ok;
  }

  /// Start a batch generation. Spawns a 200ms polling timer that drives the
  /// UI until the batch completes; final result lands in [audioResult].
  Future<bool> startAudioBatch({
    required String outDir,
    required ComposerOutput composerOutput,
    String? defaultVoiceId,
    int concurrency = 4,
  }) async {
    final payload = json.encode({
      'out_dir': outDir,
      'composer_output': {
        'asset_map': {
          'theme': composerOutput.assetMap.theme,
          'mood': composerOutput.assetMap.mood,
          'target_bpm': composerOutput.assetMap.targetBpm,
          'compliance_hints': {
            'target_jurisdictions':
                composerOutput.assetMap.complianceHints.targetJurisdictions,
            'ldw_audio_suppressed':
                composerOutput.assetMap.complianceHints.ldwAudioSuppressed,
            'proportional_celebrations':
                composerOutput.assetMap.complianceHints.proportionalCelebrations,
            'near_miss_neutralized':
                composerOutput.assetMap.complianceHints.nearMissNeutralized,
            'reviewer_notes':
                composerOutput.assetMap.complianceHints.reviewerNotes,
          },
          'self_quality_score': composerOutput.assetMap.selfQualityScore,
          'self_critique': composerOutput.assetMap.selfCritique,
          'stages': [
            for (final s in composerOutput.assetMap.stages)
              {
                'stage_id': s.stageId,
                'assets': [
                  for (final a in s.assets)
                    {
                      'kind': a.kind,
                      'suggested_name': a.suggestedName,
                      'mood': a.mood,
                      'dynamic_level': a.dynamicLevel,
                      if (a.lengthMs != null) 'length_ms': a.lengthMs,
                      'bus': a.bus,
                      'generation_prompt': a.generationPrompt,
                    },
                ],
              },
          ],
        },
      },
      if (defaultVoiceId != null) 'default_voice_id': defaultVoiceId,
      'concurrency': concurrency,
    });

    final raw = _ffi.composerAudioGenerateJson(payload);
    if (raw == null) {
      _captureError();
      return false;
    }
    _audioResult = null;
    _audioProgress = AudioBatchProgress.idle();
    notifyListeners();
    _startAudioPolling();
    return true;
  }

  void cancelAudioBatch() {
    _ffi.composerAudioCancel();
  }

  void _startAudioPolling() {
    _audioPollTimer?.cancel();
    _audioPollTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      final raw = _ffi.composerAudioProgressJson();
      if (raw == null) return;
      try {
        final progress = AudioBatchProgress.fromJson(
            json.decode(raw) as Map<String, dynamic>);
        _audioProgress = progress;
        if (!progress.active && progress.total > 0) {
          // Pull final result
          final rawRes = _ffi.composerAudioLastResultJson();
          if (rawRes != null) {
            try {
              final parsed = json.decode(rawRes) as Map<String, dynamic>;
              if (parsed.containsKey('job_id')) {
                _audioResult = AudioBatchOutput.fromJson(parsed);
              }
            } catch (_) {}
          }
          timer.cancel();
        }
        notifyListeners();
      } catch (_) {
        // Best effort.
      }
    });
  }

  @override
  void dispose() {
    _audioPollTimer?.cancel();
    super.dispose();
  }
}
