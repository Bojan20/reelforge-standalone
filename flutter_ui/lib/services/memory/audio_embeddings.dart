/// FAZA 4.3.2 — Audio Embeddings
///
/// Vector embedding sloj nad Sonic DNA feature vector-om. Omogućava:
///   - **Cosine similarity** između dva audio fajla
///   - **k-Nearest Neighbors** query (npr. "pronađi 5 najsličnijih fajlova
///     u pool-u na ovaj reference fajl")
///   - **Persistent embedding store** (`~/Library/Application Support/
///     FluxForge Studio/memory/embeddings.json`) — re-load preko sessions
///
/// **Dimenzija:** 8 features iz Sonic DNA (duration, rms, centroid, transient
/// density, ZCR, spectral flux, envelope shape, harmonic ratio). Vrlo
/// lightweight — 32 bytes po embedding-u.
///
/// **Future (4.3.2-ext):**
///   - Učitaj 128-d sentence-transformers embeddings (via `tract` Rust ONNX)
///   - Hybrid score (Sonic DNA + transformer + filename TF-IDF)
///
/// **Privacy:** sve lokalno, isti pattern kao MemoryEventLog. GDPR-friendly.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../providers/slot_lab/spectral_dna_classifier.dart';

/// One audio fingerprint — fixed-dimension feature vector.
class AudioEmbedding {
  /// Source file path (canonical key).
  final String path;

  /// Float32 feature vector (dim = 8 za Sonic DNA MVP).
  final Float32List vector;

  /// Optional best-stage candidate from Sonic DNA classifier.
  final String? bestCandidate;
  final double? bestConfidence;

  const AudioEmbedding({
    required this.path,
    required this.vector,
    this.bestCandidate,
    this.bestConfidence,
  });

  /// Construct iz `SpectralDnaResult` — uzima 8 features.
  factory AudioEmbedding.fromDna(SpectralDnaResult dna) {
    final v = Float32List(8);
    // Normalize duration u [0, 1] sa 10s skalom (slot audio rarely > 10s).
    v[0] = (dna.durationMs / 10000.0).clamp(0.0, 1.0);
    v[1] = dna.rmsEnergy.clamp(0.0, 1.0);
    // Spectral centroid normalize 0–8000Hz → [0,1].
    v[2] = (dna.spectralCentroidHz / 8000.0).clamp(0.0, 1.0);
    v[3] = (dna.transientCount / 10.0).clamp(0.0, 1.0);
    // Attack time normalize: 200ms is max meaningful.
    v[4] = (dna.attackMs / 200.0).clamp(0.0, 1.0);
    v[5] = dna.brightness.clamp(0.0, 1.0);
    // Boolean features compress u 0/1.
    v[6] = dna.isLoopable ? 1.0 : 0.0;
    v[7] = dna.hasSustain ? 1.0 : 0.0;

    final best = dna.candidates.isNotEmpty ? dna.candidates.first : null;
    return AudioEmbedding(
      path: dna.filePath,
      vector: v,
      bestCandidate: best?.stage,
      bestConfidence: best?.confidence,
    );
  }

  /// Cosine similarity sa drugim embedding-om. Returns [-1.0, 1.0].
  ///
  /// 1.0 = identičan smer; 0.0 = ortogonalan; -1.0 = obrnut.
  /// Za normalizovane non-negative features, range ide [0.0, 1.0].
  double cosineSimilarity(AudioEmbedding other) {
    if (vector.length != other.vector.length) {
      throw ArgumentError('Embedding dim mismatch: ${vector.length} != ${other.vector.length}');
    }
    double dot = 0.0;
    double na = 0.0;
    double nb = 0.0;
    for (int i = 0; i < vector.length; i++) {
      dot += vector[i] * other.vector[i];
      na += vector[i] * vector[i];
      nb += other.vector[i] * other.vector[i];
    }
    if (na == 0.0 || nb == 0.0) return 0.0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'vector': vector.toList(),
        if (bestCandidate != null) 'best_candidate': bestCandidate,
        if (bestConfidence != null) 'best_confidence': bestConfidence,
      };

  factory AudioEmbedding.fromJson(Map<String, dynamic> json) {
    final list = (json['vector'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();
    return AudioEmbedding(
      path: json['path'] as String,
      vector: Float32List.fromList(list),
      bestCandidate: json['best_candidate'] as String?,
      bestConfidence: (json['best_confidence'] as num?)?.toDouble(),
    );
  }
}

/// One match result iz `nearest(k)` query.
class EmbeddingMatch {
  final AudioEmbedding embedding;
  final double similarity;
  const EmbeddingMatch({required this.embedding, required this.similarity});
}

/// Persistent embedding store. Singleton — koristi GetIt ili `instance`.
class AudioEmbeddingStore {
  AudioEmbeddingStore._();
  static final AudioEmbeddingStore instance = AudioEmbeddingStore._();

  final Map<String, AudioEmbedding> _embeddings = {};
  Directory? _memoryDir;
  bool _loadedFromDisk = false;

  /// Učitaj iz diska (lazy, only-once). Idempotent.
  Future<void> load() async {
    if (_loadedFromDisk) return;
    final dir = await _resolveMemoryDir();
    if (dir == null) {
      _loadedFromDisk = true;
      return;
    }
    final file = File('${dir.path}/embeddings.json');
    if (!file.existsSync()) {
      _loadedFromDisk = true;
      return;
    }
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is List) {
        for (final item in json) {
          if (item is Map<String, dynamic>) {
            try {
              final emb = AudioEmbedding.fromJson(item);
              _embeddings[emb.path] = emb;
            } catch (e) {
              debugPrint('[AudioEmbeddingStore] skip malformed entry: $e');
            }
          }
        }
      }
    } catch (e, st) {
      debugPrint('[AudioEmbeddingStore] load fail: $e\n$st');
    }
    _loadedFromDisk = true;
  }

  /// Insert / update embedding. NE persist-uje odmah (batch save kasnije).
  void upsert(AudioEmbedding embedding) {
    _embeddings[embedding.path] = embedding;
  }

  /// Bulk insert iz batch DNA results. Vraća broj inserted.
  int upsertBatch(Iterable<SpectralDnaResult> results) {
    int count = 0;
    for (final r in results) {
      _embeddings[r.filePath] = AudioEmbedding.fromDna(r);
      count++;
    }
    return count;
  }

  /// Vraća embedding po path-u (ili null ako ne postoji).
  AudioEmbedding? get(String path) => _embeddings[path];

  /// Sve embeddings (read-only).
  List<AudioEmbedding> get all => List.unmodifiable(_embeddings.values);

  /// Broj entry-ja u store-u.
  int get length => _embeddings.length;

  /// k-Nearest Neighbors query. Vraća top-k najsličnijih u opadajućem
  /// redosledu po cosine similarity.
  ///
  /// Excludes `query.path` from results (samo-match je trivijalan).
  ///
  /// `minSimilarity` filter — vrati samo matches sa similarity >= threshold.
  List<EmbeddingMatch> nearest(
    AudioEmbedding query, {
    int k = 5,
    double minSimilarity = 0.0,
  }) {
    final matches = <EmbeddingMatch>[];
    for (final emb in _embeddings.values) {
      if (emb.path == query.path) continue;
      try {
        final sim = query.cosineSimilarity(emb);
        if (sim >= minSimilarity) {
          matches.add(EmbeddingMatch(embedding: emb, similarity: sim));
        }
      } catch (_) {
        // Skip dim mismatch.
      }
    }
    matches.sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches.take(k).toList(growable: false);
  }

  /// Persist store-a na disk kao JSON array. Atomic write preko tmp fajla.
  Future<void> save() async {
    final dir = await _resolveMemoryDir();
    if (dir == null) return;
    final file = File('${dir.path}/embeddings.json');
    final tmpFile = File('${dir.path}/embeddings.json.tmp');
    try {
      final json = _embeddings.values.map((e) => e.toJson()).toList();
      tmpFile.writeAsStringSync(jsonEncode(json));
      tmpFile.renameSync(file.path);
    } catch (e, st) {
      debugPrint('[AudioEmbeddingStore] save fail: $e\n$st');
    }
  }

  /// Briše sve embeddings — koristi se kad korisnik reset-uje memoriju.
  void clear() {
    _embeddings.clear();
  }

  Future<Directory?> _resolveMemoryDir() async {
    if (_memoryDir != null && _memoryDir!.existsSync()) return _memoryDir;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return null;
      final basePath = Platform.isMacOS
          ? '$home/Library/Application Support/FluxForge Studio'
          : '$home/.fluxforge';
      final dir = Directory('$basePath/memory');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _memoryDir = dir;
      return dir;
    } catch (e, st) {
      debugPrint('[AudioEmbeddingStore] resolve dir fail: $e\n$st');
      return null;
    }
  }

  @visibleForTesting
  void setMemoryDirForTest(Directory? dir) {
    _memoryDir = dir;
    _loadedFromDisk = false;
  }

  @visibleForTesting
  void clearForTest() {
    _embeddings.clear();
    _loadedFromDisk = false;
  }
}
