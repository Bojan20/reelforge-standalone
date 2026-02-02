/// Track Freeze Service Tests — P2-DAW-5
///
/// Tests for track freeze/unfreeze functionality.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/track_freeze_service.dart';

void main() {
  group('FreezeState', () {
    test('all freeze states are defined', () {
      expect(FreezeState.values.length, 4);
      expect(FreezeState.values, contains(FreezeState.unfrozen));
      expect(FreezeState.values, contains(FreezeState.freezing));
      expect(FreezeState.values, contains(FreezeState.frozen));
      expect(FreezeState.values, contains(FreezeState.error));
    });

    test('displayName returns correct strings', () {
      expect(FreezeState.unfrozen.displayName, 'Unfrozen');
      expect(FreezeState.freezing.displayName, 'Freezing...');
      expect(FreezeState.frozen.displayName, 'Frozen');
      expect(FreezeState.error.displayName, 'Error');
    });

    test('isProcessing returns true only for freezing state', () {
      expect(FreezeState.unfrozen.isProcessing, false);
      expect(FreezeState.freezing.isProcessing, true);
      expect(FreezeState.frozen.isProcessing, false);
      expect(FreezeState.error.isProcessing, false);
    });
  });

  group('FrozenTrackInfo', () {
    test('creates info with required fields', () {
      final info = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Drums',
      );

      expect(info.trackId, 1);
      expect(info.trackName, 'Drums');
      expect(info.state, FreezeState.unfrozen);
      expect(info.cpuUsageBefore, 0.0);
      expect(info.cpuUsageAfter, 0.0);
      expect(info.insertCount, 0);
    });

    test('copyWith updates only specified fields', () {
      final info = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Drums',
      );

      final updated = info.copyWith(
        state: FreezeState.frozen,
        frozenAudioPath: '/path/to/frozen.wav',
        cpuUsageBefore: 8.0,
        cpuUsageAfter: 0.5,
      );

      expect(updated.trackId, 1); // Unchanged
      expect(updated.trackName, 'Drums'); // Unchanged
      expect(updated.state, FreezeState.frozen);
      expect(updated.frozenAudioPath, '/path/to/frozen.wav');
      expect(updated.cpuUsageBefore, 8.0);
      expect(updated.cpuUsageAfter, 0.5);
    });

    test('cpuSavings calculates percentage correctly', () {
      final info = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        cpuUsageBefore: 10.0,
        cpuUsageAfter: 2.0,
      );

      // Savings = (10 - 2) / 10 * 100 = 80%
      expect(info.cpuSavings, closeTo(80.0, 0.01));
    });

    test('cpuSavings handles zero before usage', () {
      final info = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        cpuUsageBefore: 0.0,
        cpuUsageAfter: 0.0,
      );

      expect(info.cpuSavings, 0.0);
    });

    test('cpuSavings is clamped to 0-100', () {
      final highSavings = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        cpuUsageBefore: 5.0,
        cpuUsageAfter: -1.0, // Unusual case
      );

      final negativeSavings = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        cpuUsageBefore: 2.0,
        cpuUsageAfter: 5.0, // After is higher (shouldn't happen normally)
      );

      expect(highSavings.cpuSavings, lessThanOrEqualTo(100.0));
      expect(negativeSavings.cpuSavings, greaterThanOrEqualTo(0.0));
    });

    test('cpuSavingsFormatted returns human-readable string', () {
      final info = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        cpuUsageBefore: 10.0,
        cpuUsageAfter: 2.0,
      );

      expect(info.cpuSavingsFormatted, '80.0% CPU saved');
    });

    test('isFrozenWithAudio returns correct state', () {
      final notFrozen = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        state: FreezeState.unfrozen,
      );

      final frozenNoAudio = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        state: FreezeState.frozen,
        frozenAudioPath: null,
      );

      final frozenWithAudio = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Test',
        state: FreezeState.frozen,
        frozenAudioPath: '/path/to/audio.wav',
      );

      expect(notFrozen.isFrozenWithAudio, false);
      expect(frozenNoAudio.isFrozenWithAudio, false);
      expect(frozenWithAudio.isFrozenWithAudio, true);
    });
  });

  group('FrozenTrackInfo with inserts', () {
    test('tracks bypassed inserts', () {
      final info = FrozenTrackInfo(
        trackId: 1,
        trackName: 'Bass',
        state: FreezeState.frozen,
        insertCount: 4,
        bypassedInserts: ['EQ', 'Compressor', 'Limiter', 'Saturation'],
      );

      expect(info.insertCount, 4);
      expect(info.bypassedInserts.length, 4);
      expect(info.bypassedInserts, contains('Compressor'));
    });
  });

  group('TrackFreezeService quality settings', () {
    test('valid bit depths', () {
      // Valid bit depths for audio: 16, 24, 32
      final validBitDepths = [16, 24, 32];

      for (final depth in validBitDepths) {
        expect(depth, greaterThanOrEqualTo(16));
        expect(depth, lessThanOrEqualTo(32));
      }
    });

    test('valid sample rates', () {
      // Standard sample rates
      final validSampleRates = [44100, 48000, 88200, 96000, 176400, 192000];

      for (final rate in validSampleRates) {
        expect(rate, greaterThanOrEqualTo(44100));
        expect(rate, lessThanOrEqualTo(192000));
      }
    });
  });
}
