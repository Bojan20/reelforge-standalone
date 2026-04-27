/// FLUX_MASTER_TODO 2.2.5 / BUG #46 — byte-budget LRU regression test.
///
/// The previous LRU was count-only (max 100 clips). 100 short SFX +
/// 100 6-minute music tracks fit the same "100 entries" bucket, but
/// the second case pins ~1.5 GB of waveform peaks → Flutter
/// "oversized images" OOM. The fix tracks an estimated byte cost
/// per entry and evicts oldest until the total drops under
/// `_maxMultiResBytes`.
///
/// Direct unit-testing the cache requires producing `MultiResWaveform`
/// instances without going through `NativeFFI` or the Dart fallback
/// computation. We use the public `getOrComputeMultiRes`
/// path that takes raw `Float32List` and runs the Dart compute path,
/// then assert on `multiResTotalBytes`.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/waveform_cache.dart';

void main() {
  group('WaveformCache byte-budget LRU (FLUX_MASTER_TODO 2.2.5)', () {
    setUp(() {
      WaveformCache().clear();
    });

    test('insert tracks byte total, eviction releases bytes', () {
      final cache = WaveformCache();
      // 1 second of stereo 48 kHz audio = 48,000 samples per channel.
      // Through 6 LOD levels each cuts the bucket count by powers of
      // 2 (256 → 8192 samples per peak), so total entries are ~190
      // peaks × 4 bytes × 2 sides × 2 channels × 6 levels ≈ 18 KB.
      final left = Float32List(48000);
      final right = Float32List(48000);
      for (int i = 0; i < left.length; i++) {
        left[i] = (i % 100 - 50) / 50.0;
        right[i] = -left[i];
      }

      cache.getOrComputeMultiRes('clip_a', left, right, 48000);
      final bytesAfterFirst = cache.multiResTotalBytes;
      expect(bytesAfterFirst > 0, isTrue,
          reason: 'inserting an entry must increment byte total');

      cache.getOrComputeMultiRes('clip_b', left, right, 48000);
      final bytesAfterSecond = cache.multiResTotalBytes;
      expect(bytesAfterSecond, greaterThan(bytesAfterFirst));

      cache.removeMultiRes('clip_a');
      expect(cache.multiResTotalBytes, lessThan(bytesAfterSecond),
          reason: 'remove must decrement byte total');

      cache.clearMultiRes();
      expect(cache.multiResTotalBytes, 0,
          reason: 'clearMultiRes resets the byte counter');
    });

    test('byte total never goes negative under churn', () {
      // Pre-fix bug class: a remove() that fails to find an entry
      // could double-decrement and leave the counter < 0. Our
      // `_estimateBytes`-based decrement is guarded with a clamp to 0;
      // verify by aggressively churning.
      final cache = WaveformCache();
      final samples = Float32List(1024);
      for (int round = 0; round < 5; round++) {
        for (int i = 0; i < 10; i++) {
          cache.getOrComputeMultiRes('clip_$i', samples, null, 48000);
        }
        // Remove some that exist + some that don't.
        for (int i = 0; i < 15; i++) {
          cache.removeMultiRes('clip_$i');
        }
        expect(cache.multiResTotalBytes >= 0, isTrue,
            reason: 'byte total must never go negative '
                '(round=$round, total=${cache.multiResTotalBytes})');
      }
    });

    test('clear() also resets the byte counter', () {
      final cache = WaveformCache();
      final samples = Float32List(1024);
      cache.getOrComputeMultiRes('clip_x', samples, null, 48000);
      expect(cache.multiResTotalBytes, greaterThan(0));
      cache.clear();
      expect(cache.multiResTotalBytes, 0);
    });
  });
}
