/// Unit tests for FFIBoundsChecker utility
///
/// Tests:
/// - Index validation (negative, out-of-bounds, valid)
/// - Range validation (invalid range, out-of-bounds)
/// - Integer validation (overflow, underflow)
/// - Buffer size validation
/// - Float validation (NaN, Infinity, range)
/// - Domain-specific validators (reel, tier, jackpot, etc.)
/// - Audio parameter validators (volume, pan, frequency, etc.)

import 'package:flutter_test/flutter_test.dart';
import '../../lib/utils/ffi_bounds_checker.dart';

void main() {
  group('FFIBoundsChecker', () {
    group('Index Validation', () {
      test('accepts valid index', () {
        final result = FFIBoundsChecker.checkIndex(5, 10);

        expect(result.isValid, isTrue);
        expect(result.error, isNull);
      });

      test('rejects negative index', () {
        final result = FFIBoundsChecker.checkIndex(-1, 10);

        expect(result.isValid, isFalse);
        expect(result.error, contains('Negative index'));
      });

      test('rejects out-of-bounds index', () {
        final result = FFIBoundsChecker.checkIndex(10, 10);

        expect(result.isValid, isFalse);
        expect(result.error, contains('out of bounds'));
      });

      test('rejects unreasonably large index', () {
        final result = FFIBoundsChecker.checkIndex(9999999999, 100);

        expect(result.isValid, isFalse);
        expect(result.error, contains('out of bounds'));
      });

      test('throwIfInvalid throws on error', () {
        final result = FFIBoundsChecker.checkIndex(-1, 10);

        expect(() => result.throwIfInvalid(), throwsArgumentError);
      });
    });

    group('Range Validation', () {
      test('accepts valid range', () {
        final result = FFIBoundsChecker.checkRange(2, 5, 10);

        expect(result.isValid, isTrue);
      });

      test('rejects negative start', () {
        final result = FFIBoundsChecker.checkRange(-1, 5, 10);

        expect(result.isValid, isFalse);
        expect(result.error, contains('Negative start'));
      });

      test('rejects negative end', () {
        final result = FFIBoundsChecker.checkRange(0, -1, 10);

        expect(result.isValid, isFalse);
        expect(result.error, contains('Negative end'));
      });

      test('rejects invalid range (start > end)', () {
        final result = FFIBoundsChecker.checkRange(5, 2, 10);

        expect(result.isValid, isFalse);
        expect(result.error, contains('Invalid range'));
      });

      test('rejects out-of-bounds range', () {
        final result = FFIBoundsChecker.checkRange(5, 15, 10);

        expect(result.isValid, isFalse);
        expect(result.error, contains('exceeds array length'));
      });
    });

    group('Integer Validation', () {
      test('accepts safe integers', () {
        final result = FFIBoundsChecker.checkInt(42);

        expect(result.isValid, isTrue);
      });

      test('accepts negative safe integers', () {
        final result = FFIBoundsChecker.checkInt(-1000);

        expect(result.isValid, isTrue);
      });

      test('accepts unsigned integers', () {
        final result = FFIBoundsChecker.checkUInt(1000);

        expect(result.isValid, isTrue);
      });

      test('rejects negative unsigned integers', () {
        final result = FFIBoundsChecker.checkUInt(-1);

        expect(result.isValid, isFalse);
        expect(result.error, contains('cannot be negative'));
      });
    });

    group('Buffer Validation', () {
      test('accepts valid buffer size', () {
        final result = FFIBoundsChecker.checkBufferSize(1024);

        expect(result.isValid, isTrue);
      });

      test('rejects negative buffer size', () {
        final result = FFIBoundsChecker.checkBufferSize(-100);

        expect(result.isValid, isFalse);
        expect(result.error, contains('cannot be negative'));
      });

      test('rejects excessive buffer size', () {
        final result = FFIBoundsChecker.checkBufferSize(1000000000); // 1GB

        expect(result.isValid, isFalse);
        expect(result.error, contains('exceeds maximum'));
      });

      test('checkBufferMatch validates size equality', () {
        expect(FFIBoundsChecker.checkBufferMatch(100, 100).isValid, isTrue);
        expect(FFIBoundsChecker.checkBufferMatch(100, 50).isValid, isFalse);
      });
    });

    group('Float Validation', () {
      test('accepts finite floats', () {
        final result = FFIBoundsChecker.checkFinite(0.5, 'volume');

        expect(result.isValid, isTrue);
      });

      test('rejects NaN', () {
        final result = FFIBoundsChecker.checkFinite(double.nan, 'volume');

        expect(result.isValid, isFalse);
        expect(result.error, contains('NaN'));
      });

      test('rejects Infinity', () {
        final result = FFIBoundsChecker.checkFinite(double.infinity, 'volume');

        expect(result.isValid, isFalse);
        expect(result.error, contains('infinite'));
      });

      test('checkRange01 validates float range', () {
        expect(FFIBoundsChecker.checkRange01(0.5, 0.0, 1.0, 'value').isValid, isTrue);
        expect(FFIBoundsChecker.checkRange01(-0.1, 0.0, 1.0, 'value').isValid, isFalse);
        expect(FFIBoundsChecker.checkRange01(1.1, 0.0, 1.0, 'value').isValid, isFalse);
      });
    });

    group('Audio Parameter Validators', () {
      test('checkVolume accepts 0.0 to 4.0', () {
        expect(FFIBoundsChecker.checkVolume(0.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkVolume(1.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkVolume(4.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkVolume(-0.1).isValid, isFalse);
        expect(FFIBoundsChecker.checkVolume(4.1).isValid, isFalse);
      });

      test('checkPan accepts -1.0 to +1.0', () {
        expect(FFIBoundsChecker.checkPan(-1.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkPan(0.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkPan(1.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkPan(-1.1).isValid, isFalse);
        expect(FFIBoundsChecker.checkPan(1.1).isValid, isFalse);
      });

      test('checkGainDb accepts -60dB to +12dB', () {
        expect(FFIBoundsChecker.checkGainDb(-60.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkGainDb(0.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkGainDb(12.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkGainDb(-61.0).isValid, isFalse);
        expect(FFIBoundsChecker.checkGainDb(13.0).isValid, isFalse);
      });

      test('checkFrequency accepts 20Hz to 20kHz', () {
        expect(FFIBoundsChecker.checkFrequency(20.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkFrequency(1000.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkFrequency(20000.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkFrequency(19.0).isValid, isFalse);
        expect(FFIBoundsChecker.checkFrequency(20001.0).isValid, isFalse);
      });

      test('checkQ accepts 0.1 to 10.0', () {
        expect(FFIBoundsChecker.checkQ(0.1).isValid, isTrue);
        expect(FFIBoundsChecker.checkQ(1.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkQ(10.0).isValid, isTrue);
        expect(FFIBoundsChecker.checkQ(0.05).isValid, isFalse);
        expect(FFIBoundsChecker.checkQ(11.0).isValid, isFalse);
      });

      test('checkSampleRate accepts 44.1kHz to 384kHz', () {
        expect(FFIBoundsChecker.checkSampleRate(44100).isValid, isTrue);
        expect(FFIBoundsChecker.checkSampleRate(48000).isValid, isTrue);
        expect(FFIBoundsChecker.checkSampleRate(384000).isValid, isTrue);
        expect(FFIBoundsChecker.checkSampleRate(22050).isValid, isFalse);
        expect(FFIBoundsChecker.checkSampleRate(500000).isValid, isFalse);
      });

      test('checkAudioBufferSize validates power-of-2', () {
        expect(FFIBoundsChecker.checkAudioBufferSize(128).isValid, isTrue);
        expect(FFIBoundsChecker.checkAudioBufferSize(256).isValid, isTrue);
        expect(FFIBoundsChecker.checkAudioBufferSize(512).isValid, isTrue);
        expect(FFIBoundsChecker.checkAudioBufferSize(100).isValid, isFalse); // Not power of 2
        expect(FFIBoundsChecker.checkAudioBufferSize(8192).isValid, isFalse); // Too large
      });
    });

    group('Domain-Specific Validators', () {
      test('checkReelIndex validates reel indices', () {
        expect(FFIBoundsChecker.checkReelIndex(0, 5).isValid, isTrue);
        expect(FFIBoundsChecker.checkReelIndex(4, 5).isValid, isTrue);
        expect(FFIBoundsChecker.checkReelIndex(5, 5).isValid, isFalse);
        expect(FFIBoundsChecker.checkReelIndex(-1, 5).isValid, isFalse);
      });

      test('checkTierIndex validates win tiers', () {
        expect(FFIBoundsChecker.checkTierIndex(0).isValid, isTrue);  // WIN_LOW
        expect(FFIBoundsChecker.checkTierIndex(6).isValid, isTrue);  // WIN_6
        expect(FFIBoundsChecker.checkTierIndex(7).isValid, isFalse);
        expect(FFIBoundsChecker.checkTierIndex(-1).isValid, isFalse);
      });

      test('checkBigWinTierIndex validates big win tiers', () {
        expect(FFIBoundsChecker.checkBigWinTierIndex(0).isValid, isTrue);
        expect(FFIBoundsChecker.checkBigWinTierIndex(4).isValid, isTrue);
        expect(FFIBoundsChecker.checkBigWinTierIndex(5).isValid, isFalse);
      });

      test('checkJackpotTierIndex validates jackpot tiers', () {
        expect(FFIBoundsChecker.checkJackpotTierIndex(0).isValid, isTrue); // Mini
        expect(FFIBoundsChecker.checkJackpotTierIndex(4).isValid, isTrue); // Grand
        expect(FFIBoundsChecker.checkJackpotTierIndex(5).isValid, isFalse);
      });

      test('checkGambleChoiceIndex validates choices', () {
        expect(FFIBoundsChecker.checkGambleChoiceIndex(0).isValid, isTrue);
        expect(FFIBoundsChecker.checkGambleChoiceIndex(99).isValid, isTrue);
        expect(FFIBoundsChecker.checkGambleChoiceIndex(100).isValid, isFalse);
      });

      test('checkEqBandIndex validates EQ bands', () {
        expect(FFIBoundsChecker.checkEqBandIndex(0).isValid, isTrue);
        expect(FFIBoundsChecker.checkEqBandIndex(63).isValid, isTrue);
        expect(FFIBoundsChecker.checkEqBandIndex(64).isValid, isFalse);
      });

      test('checkInsertSlotIndex validates insert slots', () {
        expect(FFIBoundsChecker.checkInsertSlotIndex(0).isValid, isTrue);
        expect(FFIBoundsChecker.checkInsertSlotIndex(7).isValid, isTrue);
        expect(FFIBoundsChecker.checkInsertSlotIndex(8).isValid, isFalse);
      });

      test('checkBusId validates bus IDs', () {
        expect(FFIBoundsChecker.checkBusId(0).isValid, isTrue);
        expect(FFIBoundsChecker.checkBusId(15).isValid, isTrue);
        expect(FFIBoundsChecker.checkBusId(16).isValid, isFalse);
      });

      test('checkTrackId validates track IDs', () {
        expect(FFIBoundsChecker.checkTrackId(0).isValid, isTrue);
        expect(FFIBoundsChecker.checkTrackId(255).isValid, isTrue);
        expect(FFIBoundsChecker.checkTrackId(256).isValid, isFalse);
      });
    });

    group('Batch Validation', () {
      test('checkIndices validates all indices', () {
        final result = FFIBoundsChecker.checkIndices([0, 5, 9], 10);

        expect(result.isValid, isTrue);
      });

      test('checkIndices fails on first invalid', () {
        final result = FFIBoundsChecker.checkIndices([0, 5, 10], 10);

        expect(result.isValid, isFalse);
        expect(result.error, contains('index 2')); // Third element (index=2)
      });

      test('checkIndices handles empty list', () {
        final result = FFIBoundsChecker.checkIndices([], 10);

        expect(result.isValid, isTrue);
      });
    });

    group('Utility Methods', () {
      test('clampIndex clamps negative to 0', () {
        expect(FFIBoundsChecker.clampIndex(-5, 10), equals(0));
      });

      test('clampIndex clamps out-of-bounds to max', () {
        expect(FFIBoundsChecker.clampIndex(15, 10), equals(9));
      });

      test('clampIndex preserves valid index', () {
        expect(FFIBoundsChecker.clampIndex(5, 10), equals(5));
      });

      test('clampDouble clamps to range', () {
        expect(FFIBoundsChecker.clampDouble(0.5, 0.0, 1.0), equals(0.5));
        expect(FFIBoundsChecker.clampDouble(-0.5, 0.0, 1.0), equals(0.0));
        expect(FFIBoundsChecker.clampDouble(1.5, 0.0, 1.0), equals(1.0));
      });

      test('clampDouble handles NaN', () {
        expect(FFIBoundsChecker.clampDouble(double.nan, 0.0, 1.0), equals(0.0));
      });

      test('toSafeInt accepts safe values', () {
        expect(FFIBoundsChecker.toSafeInt(42), equals(42));
        expect(FFIBoundsChecker.toSafeInt(-1000), equals(-1000));
      });
    });

    group('Edge Cases', () {
      test('checkIndex with zero-length array', () {
        final result = FFIBoundsChecker.checkIndex(0, 0);

        expect(result.isValid, isFalse);
      });

      test('checkRange with zero-length array', () {
        final result = FFIBoundsChecker.checkRange(0, 0, 0);

        expect(result.isValid, isTrue); // Empty range is valid
      });

      test('checkBufferSize with zero size', () {
        final result = FFIBoundsChecker.checkBufferSize(0);

        expect(result.isValid, isTrue); // Zero-size buffer is valid
      });
    });
  });
}
