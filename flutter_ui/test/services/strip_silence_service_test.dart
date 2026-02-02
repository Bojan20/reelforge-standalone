import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui/services/strip_silence_service.dart';

void main() {
  group('StripSilenceService', () {
    late StripSilenceService service;

    setUp(() {
      service = StripSilenceService.instance;
      service.clearResult('test-clip');
      service.setConfig(const StripSilenceConfig()); // Reset to defaults
    });

    group('SilentRegion', () {
      test('calculates duration correctly', () {
        const region = SilentRegion(
          id: 'test',
          startTime: 1.0,
          endTime: 3.0,
          averageLevelDb: -60,
          peakLevelDb: -48,
        );
        expect(region.duration, equals(2.0));
      });

      test('serializes to JSON correctly', () {
        const region = SilentRegion(
          id: 'silent-1',
          startTime: 0.5,
          endTime: 1.5,
          averageLevelDb: -72,
          peakLevelDb: -54,
        );
        final json = region.toJson();
        final restored = SilentRegion.fromJson(json);
        expect(restored.id, equals('silent-1'));
        expect(restored.startTime, equals(0.5));
        expect(restored.endTime, equals(1.5));
        expect(restored.averageLevelDb, equals(-72));
        expect(restored.peakLevelDb, equals(-54));
      });
    });

    group('StripSilenceConfig', () {
      test('has sensible defaults', () {
        const config = StripSilenceConfig();
        expect(config.thresholdDb, equals(-48.0));
        expect(config.minSilenceDuration, equals(0.1));
        expect(config.minRegionDuration, equals(0.05));
        expect(config.preAttack, equals(0.01));
        expect(config.postRelease, equals(0.05));
        expect(config.createRegions, isTrue);
      });

      test('serializes to JSON correctly', () {
        const config = StripSilenceConfig(
          thresholdDb: -60,
          minSilenceDuration: 0.2,
          minRegionDuration: 0.1,
          preAttack: 0.02,
          postRelease: 0.1,
          createRegions: false,
        );
        final json = config.toJson();
        final restored = StripSilenceConfig.fromJson(json);
        expect(restored.thresholdDb, equals(-60));
        expect(restored.minSilenceDuration, equals(0.2));
        expect(restored.minRegionDuration, equals(0.1));
        expect(restored.preAttack, equals(0.02));
        expect(restored.postRelease, equals(0.1));
        expect(restored.createRegions, isFalse);
      });
    });

    group('StripSilenceResult', () {
      test('calculates silence percentage correctly', () {
        const result = StripSilenceResult(
          clipId: 'test',
          silentRegions: [],
          audioRegions: [],
          totalSilenceDuration: 3.0,
          totalAudioDuration: 7.0,
        );
        expect(result.silencePercentage, equals(30.0)); // 3/(3+7) * 100
      });

      test('handles zero total duration', () {
        const result = StripSilenceResult(
          clipId: 'test',
          silentRegions: [],
          audioRegions: [],
          totalSilenceDuration: 0,
          totalAudioDuration: 0,
        );
        expect(result.silencePercentage, equals(0));
      });
    });

    group('Config settings', () {
      test('setThreshold clamps value', () {
        service.setThreshold(-100);
        expect(service.config.thresholdDb, equals(-96.0)); // Min
        service.setThreshold(10);
        expect(service.config.thresholdDb, equals(0.0)); // Max
      });

      test('setMinSilenceDuration has minimum', () {
        service.setMinSilenceDuration(0.001);
        expect(service.config.minSilenceDuration, equals(0.01));
      });

      test('setMinRegionDuration has minimum', () {
        service.setMinRegionDuration(-1);
        expect(service.config.minRegionDuration, equals(0.01));
      });

      test('setPreAttack has minimum', () {
        service.setPreAttack(-0.5);
        expect(service.config.preAttack, equals(0));
      });

      test('setPostRelease has minimum', () {
        service.setPostRelease(-0.5);
        expect(service.config.postRelease, equals(0));
      });
    });

    group('Analysis', () {
      test('analyze detects silent regions', () {
        final sampleRate = 44100;
        final duration = 1.0; // 1 second
        final samples = (duration * sampleRate).toInt();

        // Create audio: loud-silent-loud pattern
        final audioData = List<double>.generate(samples, (i) {
          final time = i / sampleRate;
          if (time < 0.3 || time > 0.7) {
            // Loud section (sine wave at 0.5 amplitude)
            return 0.5 * math.sin(2 * math.pi * 440 * time);
          } else {
            // Silent section (very quiet noise)
            return 0.0001 * (math.Random(i).nextDouble() - 0.5);
          }
        });

        service.setConfig(const StripSilenceConfig(
          thresholdDb: -40, // -40 dB threshold
          minSilenceDuration: 0.1,
        ));

        final result = service.analyze('test-clip', audioData, sampleRate);

        expect(result.silentRegions, isNotEmpty);
        expect(result.audioRegions, isNotEmpty);
        expect(result.totalSilenceDuration, greaterThan(0));
        expect(result.totalAudioDuration, greaterThan(0));
      });

      test('analyze detects silence at start', () {
        final sampleRate = 44100;
        final samples = 44100; // 1 second

        // Create audio: silent-loud pattern
        final audioData = List<double>.generate(samples, (i) {
          final time = i / sampleRate;
          if (time < 0.5) {
            return 0.0001; // Silent
          } else {
            return 0.5 * math.sin(2 * math.pi * 440 * time);
          }
        });

        service.setConfig(const StripSilenceConfig(
          thresholdDb: -40,
          minSilenceDuration: 0.1,
        ));

        final result = service.analyze('test-clip', audioData, sampleRate);
        expect(result.silentRegions.any((r) => r.startTime < 0.1), isTrue);
      });

      test('analyze respects minimum duration settings', () {
        final sampleRate = 44100;
        final samples = 44100;

        // Create audio with very short silence (should be ignored)
        final audioData = List<double>.generate(samples, (i) {
          final time = i / sampleRate;
          // Short 30ms silent gaps every 200ms
          if ((time * 1000).floor() % 200 < 30) {
            return 0.0001;
          }
          return 0.5 * math.sin(2 * math.pi * 440 * time);
        });

        service.setConfig(const StripSilenceConfig(
          thresholdDb: -40,
          minSilenceDuration: 0.05, // 50ms min (gaps are 30ms)
        ));

        final result = service.analyze('test-clip', audioData, sampleRate);
        // Short gaps should not be detected as silence
        expect(result.silentRegions.length, lessThan(5));
      });
    });

    group('Result retrieval', () {
      test('getResult returns null for unknown clip', () {
        expect(service.getResult('nonexistent'), isNull);
      });

      test('getResult returns analysis result', () {
        final audioData = List<double>.filled(44100, 0.5);
        service.analyze('test-clip', audioData, 44100);
        expect(service.getResult('test-clip'), isNotNull);
      });

      test('getRegionsToKeep returns audio regions', () {
        final audioData = List<double>.filled(44100, 0.5);
        service.analyze('test-clip', audioData, 44100);
        final regions = service.getRegionsToKeep('test-clip');
        expect(regions, isA<List<AudioRegion>>());
      });

      test('getRegionsToRemove returns silent regions', () {
        final audioData = List<double>.filled(44100, 0.0001); // All silent
        service.setConfig(const StripSilenceConfig(
          thresholdDb: -40,
          minSilenceDuration: 0.1,
        ));
        service.analyze('test-clip', audioData, 44100);
        final regions = service.getRegionsToRemove('test-clip');
        expect(regions, isA<List<SilentRegion>>());
      });

      test('clearResult removes result', () {
        final audioData = List<double>.filled(44100, 0.5);
        service.analyze('test-clip', audioData, 44100);
        service.clearResult('test-clip');
        expect(service.getResult('test-clip'), isNull);
      });
    });

    group('Constants', () {
      test('threshold constants are valid', () {
        expect(kMinThresholdDb, lessThan(kMaxThresholdDb));
        expect(kDefaultThresholdDb, greaterThanOrEqualTo(kMinThresholdDb));
        expect(kDefaultThresholdDb, lessThanOrEqualTo(kMaxThresholdDb));
      });

      test('duration constants are positive', () {
        expect(kMinSilenceDuration, greaterThan(0));
        expect(kDefaultSilenceDuration, greaterThan(0));
        expect(kDefaultPreAttack, greaterThanOrEqualTo(0));
        expect(kDefaultPostRelease, greaterThanOrEqualTo(0));
      });
    });
  });
}
