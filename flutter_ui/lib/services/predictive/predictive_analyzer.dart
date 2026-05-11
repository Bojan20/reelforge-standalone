/// FAZA 4.4 — Predictive Event Routing
///
/// `PredictiveAnalyzer` — fluent wrapper oko `SpectralDnaClassifier` koji
/// koristi `NativeFFI` da analizira audio fajlove i predloži stage bindings
/// sa confidence score-om.
///
/// Tri ulaza:
///   1. **Drag overlay** — dok korisnik vuče fajl preko event entry-ja,
///      pre-analyze sa caching-om da overlay ne blocking-uje frame.
///   2. **Gap detection** — za svaki unbound stage, nađe top-N kandidata
///      iz audio pool-a (inverz spektralne klasifikacije).
///   3. **Auto-fill** — bulk apply visokog-confidence suggestionsa.
///
/// Sve preko `SpectralDnaClassifier.analyzeFile()` (Rust FFI) i
/// `SpectralDnaClassifier.suggestBindings()`. Ovaj sloj dodaje:
///   - LRU cache (100 fajlova) za drag-overlay latency
///   - Async API (microtask) da ne blokira UI thread
///   - Confidence tier semantike (high / mid / low / unclassified)
///
/// FAZA 4.4.5 (Learning loop) se kuka kao opcioni `feedbackLog` callback —
/// kad korisnik prihvati ili odbije suggestion, log-uje se za buduće
/// kalibrisanje. MVP nema persistence; samo memory event stream.
library;

import 'dart:async';
import 'dart:collection';

import 'package:get_it/get_it.dart';

import '../../providers/slot_lab/spectral_dna_classifier.dart';
import '../../src/rust/native_ffi.dart';

/// Confidence tier — koristi se za UI color coding i auto-fill threshold.
enum ConfidenceTier {
  /// ≥ 0.75 — auto-fillable bez user confirmation
  high,

  /// 0.50 – 0.74 — suggest ali traži potvrdu
  mid,

  /// 0.25 – 0.49 — pokaži kao opciju ali ne preporučuj
  low,

  /// < 0.25 ili null candidate — ne pokazuj suggestion
  unclassified,
}

/// Helper koji mapira confidence score → tier (single source of truth).
ConfidenceTier confidenceTierOf(double? confidence) {
  if (confidence == null) return ConfidenceTier.unclassified;
  if (confidence >= 0.75) return ConfidenceTier.high;
  if (confidence >= 0.50) return ConfidenceTier.mid;
  if (confidence >= 0.25) return ConfidenceTier.low;
  return ConfidenceTier.unclassified;
}

/// Feedback event emitovan kad korisnik prihvati / odbije suggestion.
/// 4.4.5 — koristi se za learning loop (persist u SQLite).
class PredictiveFeedbackEvent {
  final String audioPath;
  final String suggestedStage;
  final double suggestedConfidence;
  final String? actualStage; // null ako je rejected bez assign
  final bool accepted;
  final DateTime timestamp;

  const PredictiveFeedbackEvent({
    required this.audioPath,
    required this.suggestedStage,
    required this.suggestedConfidence,
    required this.actualStage,
    required this.accepted,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'audioPath': audioPath,
        'suggestedStage': suggestedStage,
        'suggestedConfidence': suggestedConfidence,
        'actualStage': actualStage,
        'accepted': accepted,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// `PredictiveAnalyzer` — singleton kroz GetIt.
///
/// Thread-safety: cache pristup je single-threaded (Dart event loop), tako
/// da nije potreban Lock. Sve I/O kroz FFI ide preko `compute`-friendly
/// async wrapper-a (zapravo sync FFI, ali wrapped u `Future.microtask` da
/// se UI ne blocking-uje u istom frame-u).
class PredictiveAnalyzer {
  static const int _maxCacheEntries = 100;

  final SpectralDnaClassifier _classifier;

  /// LRU cache fajl path → analysis result. `LinkedHashMap` insertion
  /// order omogućava O(1) move-to-end na pristup.
  final LinkedHashMap<String, SpectralDnaResult> _cache =
      LinkedHashMap<String, SpectralDnaResult>();

  /// Inflight analiza po path-u — sprečava duplikat FFI poziva ako overlay
  /// renderuje 2 puta brzo zaredom za isti fajl.
  final Map<String, Future<SpectralDnaResult?>> _inflight = {};

  /// Stream feedback događaja — 4.4.5 hookuje se na ovo.
  final StreamController<PredictiveFeedbackEvent> _feedbackController =
      StreamController<PredictiveFeedbackEvent>.broadcast();

  Stream<PredictiveFeedbackEvent> get feedbackStream =>
      _feedbackController.stream;

  PredictiveAnalyzer(NativeFFI ffi)
      : _classifier = SpectralDnaClassifier(ffi);

  /// Convenience za GetIt: `sl<PredictiveAnalyzer>()`
  static PredictiveAnalyzer get instance =>
      GetIt.instance<PredictiveAnalyzer>();

  /// Analiziraj jedan fajl. Cache-uje rezultat. Vraća `null` ako:
  ///   - path je prazan
  ///   - FFI vrati prazan JSON
  ///   - fajl ne postoji ili je neparsibilan
  ///
  /// Latency: prvi poziv ~5-50ms (FFI + DSP), keširani <1µs.
  Future<SpectralDnaResult?> analyzeFile(String path) async {
    if (path.isEmpty) return null;

    // Cache hit — pomeri na kraj (LRU).
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }

    // Inflight — drugi caller već čeka isti FFI poziv.
    final pending = _inflight[path];
    if (pending != null) return pending;

    final future = _doAnalyze(path);
    _inflight[path] = future;
    try {
      final result = await future;
      if (result != null) {
        _cache[path] = result;
        _evictIfNeeded();
      }
      return result;
    } finally {
      _inflight.remove(path);
    }
  }

  Future<SpectralDnaResult?> _doAnalyze(String path) async {
    // Yield to event loop — sprečava jank u istom frame-u sa drag gesture.
    await Future<void>.delayed(Duration.zero);
    return _classifier.analyzeFile(path);
  }

  /// Batch analiza — za gap detection (4.4.3). Reuse-uje cache za
  /// fajlove koji su već analizirani u session-u.
  Future<Map<String, SpectralDnaResult>> analyzeBatch(
      List<String> paths) async {
    if (paths.isEmpty) return const {};

    final results = <String, SpectralDnaResult>{};
    final uncached = <String>[];

    for (final p in paths) {
      final cached = _cache.remove(p);
      if (cached != null) {
        _cache[p] = cached; // LRU touch
        results[p] = cached;
      } else {
        uncached.add(p);
      }
    }

    if (uncached.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
      final fresh = _classifier.analyzeBatch(uncached);
      for (final entry in fresh.entries) {
        _cache[entry.key] = entry.value;
        results[entry.key] = entry.value;
      }
      _evictIfNeeded();
    }

    return results;
  }

  /// Predikcija za jedan fajl + očekivani stage hint.
  ///
  /// Vraća best matching `StageCandidate`. Ako `stageHint != null`, prvo
  /// traži kandidata sa tim imenom stage-a; ako nije među candidates,
  /// fallback na top-1.
  ///
  /// Korisni za drag overlay nad event-om: znamo target stage, hoćemo
  /// confidence da audio match-uje TAJ stage.
  Future<StageCandidate?> predictFor(
    String path, {
    String? stageHint,
  }) async {
    final result = await analyzeFile(path);
    if (result == null || result.candidates.isEmpty) return null;

    if (stageHint != null && stageHint.isNotEmpty) {
      final normalized = stageHint.toUpperCase();
      for (final c in result.candidates) {
        if (c.stage.toUpperCase() == normalized) return c;
      }
      // Stage hint nije među candidates → vrati top kandidat ali umanji
      // confidence tako da overlay može da pokaže "low match" tier.
      // Ovo NIJE u Rust-u; UI sloj radi semantičku interpretaciju.
      final top = result.candidates.first;
      // Kazni confidence ako stage hint promašaj (×0.5 floor).
      return StageCandidate(
        stage: top.stage,
        confidence: top.confidence * 0.5,
      );
    }

    return result.candidates.first;
  }

  /// Gap detection — za svaki unbound stage, vrati top-N kandidata iz
  /// audio pool-a koji match-uju. (FAZA 4.4.3)
  ///
  /// `unboundStages` = svi stage-ovi bez `audioAssignment`.
  /// `audioPoolPaths` = svi raspoloživi fajlovi u audio asset manager-u.
  /// `topN` = koliko suggestionsa po stage-u (default 3).
  /// `minConfidence` = donji prag za uključivanje suggestiona (default 0.40).
  ///
  /// Output: `Map<stageName, List<(filePath, confidence)>>` — sortirano
  /// desc po confidence.
  Future<Map<String, List<({String path, double confidence})>>>
      detectGapSuggestions({
    required Set<String> unboundStages,
    required List<String> audioPoolPaths,
    int topN = 3,
    double minConfidence = 0.40,
  }) async {
    if (unboundStages.isEmpty || audioPoolPaths.isEmpty) return const {};

    // 1. Analiziraj sve audio fajlove (batch sa cache).
    final analyses = await analyzeBatch(audioPoolPaths);

    // 2. Inverz: za svaki stage → lista (path, confidence) sortiraj desc.
    final out = <String, List<({String path, double confidence})>>{};

    for (final stage in unboundStages) {
      final stageUpper = stage.toUpperCase();
      final matches = <({String path, double confidence})>[];

      for (final entry in analyses.entries) {
        final path = entry.key;
        final result = entry.value;
        for (final c in result.candidates) {
          if (c.stage.toUpperCase() == stageUpper &&
              c.confidence >= minConfidence) {
            matches.add((path: path, confidence: c.confidence));
            break; // jedan match po fajlu po stage-u
          }
        }
      }

      if (matches.isEmpty) continue;
      matches.sort((a, b) => b.confidence.compareTo(a.confidence));
      out[stage] = matches.take(topN).toList(growable: false);
    }

    return out;
  }

  /// Log feedback događaj — 4.4.5 hook. Persistence layer (SQLite)
  /// implementira `RoutingFeedbackLog` koji listenuje na ovaj stream.
  void recordFeedback({
    required String audioPath,
    required String suggestedStage,
    required double suggestedConfidence,
    required String? actualStage,
    required bool accepted,
  }) {
    _feedbackController.add(PredictiveFeedbackEvent(
      audioPath: audioPath,
      suggestedStage: suggestedStage,
      suggestedConfidence: suggestedConfidence,
      actualStage: actualStage,
      accepted: accepted,
      timestamp: DateTime.now(),
    ));
  }

  /// Manual cache clear — za test scenarije ili kad korisnik osveži pool.
  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }

  /// Diag — broj fajlova u cache-u (za debug overlay).
  int get cacheSize => _cache.length;

  void _evictIfNeeded() {
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first); // O(1) LRU evict
    }
  }

  /// Dispose — zatvara stream controller.
  Future<void> dispose() async {
    _cache.clear();
    _inflight.clear();
    await _feedbackController.close();
  }
}
