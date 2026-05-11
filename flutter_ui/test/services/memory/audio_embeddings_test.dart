/// FAZA 4.3.2 — `AudioEmbedding` + `AudioEmbeddingStore` unit tests.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/slot_lab/spectral_dna_classifier.dart';
import 'package:fluxforge_ui/services/memory/audio_embeddings.dart';

AudioEmbedding _emb(String path, List<double> v, {String? best}) =>
    AudioEmbedding(
      path: path,
      vector: Float32List.fromList(v),
      bestCandidate: best,
    );

void main() {
  group('AudioEmbedding — cosine similarity', () {
    test('identical vectors → 1.0', () {
      final a = _emb('a', [1.0, 0.0, 0.0]);
      final b = _emb('b', [1.0, 0.0, 0.0]);
      expect(a.cosineSimilarity(b), closeTo(1.0, 1e-9));
    });

    test('orthogonal vectors → 0.0', () {
      final a = _emb('a', [1.0, 0.0]);
      final b = _emb('b', [0.0, 1.0]);
      expect(a.cosineSimilarity(b), closeTo(0.0, 1e-9));
    });

    test('zero vector vs other → 0.0 (no division by zero)', () {
      final a = _emb('a', [0.0, 0.0]);
      final b = _emb('b', [1.0, 0.0]);
      expect(a.cosineSimilarity(b), 0.0);
    });

    test('similar but not identical → high but < 1.0', () {
      final a = _emb('a', [1.0, 0.1, 0.0]);
      final b = _emb('b', [1.0, 0.0, 0.0]);
      final sim = a.cosineSimilarity(b);
      expect(sim, greaterThan(0.99));
      expect(sim, lessThan(1.0));
    });

    test('dim mismatch → ArgumentError', () {
      final a = _emb('a', [1.0, 0.0]);
      final b = _emb('b', [1.0, 0.0, 0.0]);
      expect(() => a.cosineSimilarity(b), throwsArgumentError);
    });
  });

  group('AudioEmbedding — fromDna conversion', () {
    test('builds 8-dim vector iz SpectralDnaResult', () {
      final dna = SpectralDnaResult(
        filePath: '/audio/sample.wav',
        durationMs: 5000,
        attackMs: 10,
        rmsEnergy: 0.5,
        peakAmplitude: 0.9,
        spectralCentroidHz: 4000,
        isLoopable: true,
        transientCount: 3,
        hasSustain: false,
        brightness: 0.5,
        candidates: [
          StageCandidate(stage: 'REEL_STOP', confidence: 0.85),
        ],
      );
      final emb = AudioEmbedding.fromDna(dna);
      expect(emb.path, '/audio/sample.wav');
      expect(emb.vector.length, 8);
      expect(emb.bestCandidate, 'REEL_STOP');
      expect(emb.bestConfidence, 0.85);
      // Duration 5000ms / 10000ms = 0.5
      expect(emb.vector[0], closeTo(0.5, 1e-6));
      // RMS = 0.5
      expect(emb.vector[1], closeTo(0.5, 1e-6));
      // Loopable = 1.0
      expect(emb.vector[6], 1.0);
      // hasSustain = 0.0
      expect(emb.vector[7], 0.0);
    });

    test('clamps out-of-range values', () {
      final dna = SpectralDnaResult(
        filePath: '/a.wav',
        durationMs: 999999, // very long
        attackMs: 9999,
        rmsEnergy: 5.0, // out of [0,1]
        peakAmplitude: 0.9,
        spectralCentroidHz: 99999, // > 8000
        isLoopable: false,
        transientCount: 100, // > 10
        hasSustain: true,
        brightness: 2.0, // out of [0,1]
        candidates: const [],
      );
      final emb = AudioEmbedding.fromDna(dna);
      for (final v in emb.vector) {
        expect(v >= 0.0 && v <= 1.0, isTrue,
            reason: 'vector element $v out of [0,1]');
      }
    });
  });

  group('AudioEmbedding — JSON roundtrip', () {
    test('toJson + fromJson preserves all fields', () {
      final emb = _emb('/x.wav', [0.5, 0.7, 0.2], best: 'WIN_BIG');
      final json = emb.toJson();
      final back = AudioEmbedding.fromJson(json);
      expect(back.path, emb.path);
      expect(back.vector.length, 3);
      expect(back.vector[0], closeTo(0.5, 1e-6));
      expect(back.bestCandidate, 'WIN_BIG');
    });
  });

  group('AudioEmbeddingStore — basic ops', () {
    late AudioEmbeddingStore store;
    setUp(() {
      store = AudioEmbeddingStore.instance;
      store.clearForTest();
      store.setMemoryDirForTest(null); // no disk I/O
    });

    test('upsert + get + length', () {
      store.upsert(_emb('/a', [1, 0]));
      store.upsert(_emb('/b', [0, 1]));
      expect(store.length, 2);
      expect(store.get('/a'), isNotNull);
      expect(store.get('/c'), isNull);
    });

    test('upsert overwrites duplicate path', () {
      store.upsert(_emb('/a', [1, 0]));
      store.upsert(_emb('/a', [0, 1]));
      expect(store.length, 1);
      expect(store.get('/a')!.vector[0], 0.0);
    });

    test('clear resets store', () {
      store.upsert(_emb('/a', [1, 0]));
      store.clear();
      expect(store.length, 0);
    });
  });

  group('AudioEmbeddingStore — nearest k-NN', () {
    late AudioEmbeddingStore store;
    setUp(() {
      store = AudioEmbeddingStore.instance;
      store.clearForTest();
      store.setMemoryDirForTest(null);
    });

    test('nearest returns top-k sorted by similarity desc', () {
      store.upsert(_emb('/exact', [1.0, 0.0, 0.0]));
      store.upsert(_emb('/close', [0.95, 0.05, 0.0]));
      store.upsert(_emb('/far', [0.0, 1.0, 0.0]));
      store.upsert(_emb('/very_far', [0.0, 0.0, 1.0]));

      final query = _emb('/query', [1.0, 0.0, 0.0]);
      final results = store.nearest(query, k: 3);
      expect(results.length, 3);
      expect(results[0].embedding.path, '/exact');
      expect(results[1].embedding.path, '/close');
      // results[0].similarity > results[1].similarity
      expect(results[0].similarity, greaterThanOrEqualTo(results[1].similarity));
      expect(results[1].similarity, greaterThanOrEqualTo(results[2].similarity));
    });

    test('nearest excludes self-match (same path)', () {
      store.upsert(_emb('/q', [1.0, 0.0]));
      store.upsert(_emb('/other', [0.9, 0.1]));

      final query = _emb('/q', [1.0, 0.0]);
      final results = store.nearest(query, k: 5);
      expect(results.length, 1);
      expect(results.first.embedding.path, '/other');
    });

    test('minSimilarity filter', () {
      store.upsert(_emb('/a', [1.0, 0.0]));
      store.upsert(_emb('/b', [0.7, 0.7]));
      store.upsert(_emb('/c', [0.0, 1.0]));

      final query = _emb('/q', [1.0, 0.0]);
      final results = store.nearest(query, k: 10, minSimilarity: 0.5);
      // /a: cos = 1.0, /b: cos ≈ 0.707, /c: cos = 0.0
      expect(results.length, 2);
      expect(results.every((m) => m.similarity >= 0.5), isTrue);
    });
  });

  group('AudioEmbeddingStore — persistence', () {
    late AudioEmbeddingStore store;
    late Directory tempDir;

    setUp(() async {
      store = AudioEmbeddingStore.instance;
      store.clearForTest();
      tempDir = await Directory.systemTemp.createTemp('emb_persist_');
      store.setMemoryDirForTest(tempDir);
    });

    tearDown(() async {
      store.clearForTest();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('save → load roundtrip preserves embeddings', () async {
      store.upsert(_emb('/a', [0.1, 0.2, 0.3], best: 'REEL_STOP'));
      store.upsert(_emb('/b', [0.4, 0.5, 0.6]));
      await store.save();

      store.clearForTest();
      store.setMemoryDirForTest(tempDir);
      await store.load();

      expect(store.length, 2);
      final a = store.get('/a');
      expect(a, isNotNull);
      expect(a!.bestCandidate, 'REEL_STOP');
      expect(a.vector[0], closeTo(0.1, 1e-6));
    });

    test('load is idempotent', () async {
      store.upsert(_emb('/a', [1, 0]));
      await store.save();
      store.clearForTest();
      store.setMemoryDirForTest(tempDir);
      await store.load();
      await store.load(); // second call should no-op
      expect(store.length, 1);
    });

    test('load handles missing file gracefully', () async {
      store.setMemoryDirForTest(tempDir);
      await store.load();
      expect(store.length, 0);
    });
  });

  group('upsertBatch from DNA results', () {
    test('inserts all results, returns count', () {
      final store = AudioEmbeddingStore.instance;
      store.clearForTest();
      store.setMemoryDirForTest(null);
      final results = [
        SpectralDnaResult(
          filePath: '/a.wav',
          durationMs: 100,
          attackMs: 5,
          rmsEnergy: 0.4,
          peakAmplitude: 0.8,
          spectralCentroidHz: 2000,
          isLoopable: false,
          transientCount: 1,
          hasSustain: false,
          brightness: 0.5,
          candidates: const [],
        ),
        SpectralDnaResult(
          filePath: '/b.wav',
          durationMs: 200,
          attackMs: 8,
          rmsEnergy: 0.6,
          peakAmplitude: 0.95,
          spectralCentroidHz: 4000,
          isLoopable: true,
          transientCount: 3,
          hasSustain: false,
          brightness: 0.7,
          candidates: const [],
        ),
      ];
      final count = store.upsertBatch(results);
      expect(count, 2);
      expect(store.length, 2);
    });
  });
}
