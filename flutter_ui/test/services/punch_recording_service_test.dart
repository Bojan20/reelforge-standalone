import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui/services/punch_recording_service.dart';

void main() {
  group('PunchRecordingService', () {
    late PunchRecordingService service;

    setUp(() {
      service = PunchRecordingService.instance;
      // Reset state
      service.stopPunchRecording();
      service.clearRecordedTakes();
    });

    group('PunchRegion', () {
      test('calculates duration correctly', () {
        const region = PunchRegion(punchIn: 2.0, punchOut: 6.0);
        expect(region.duration, equals(4.0));
      });

      test('containsTime returns correct result', () {
        const region = PunchRegion(punchIn: 2.0, punchOut: 6.0);
        expect(region.containsTime(1.0), isFalse);
        expect(region.containsTime(2.0), isTrue);
        expect(region.containsTime(4.0), isTrue);
        expect(region.containsTime(6.0), isTrue);
        expect(region.containsTime(7.0), isFalse);
      });

      test('serializes to JSON correctly', () {
        const region = PunchRegion(punchIn: 1.0, punchOut: 5.0, enabled: true);
        final json = region.toJson();
        expect(json['punchIn'], equals(1.0));
        expect(json['punchOut'], equals(5.0));
        expect(json['enabled'], isTrue);

        final restored = PunchRegion.fromJson(json);
        expect(restored.punchIn, equals(1.0));
        expect(restored.punchOut, equals(5.0));
        expect(restored.enabled, isTrue);
      });
    });

    group('RollConfig', () {
      test('returns effective pre-roll when enabled', () {
        const config = RollConfig(preRoll: 2.0, preRollEnabled: true);
        expect(config.effectivePreRoll, equals(2.0));
      });

      test('returns zero pre-roll when disabled', () {
        const config = RollConfig(preRoll: 2.0, preRollEnabled: false);
        expect(config.effectivePreRoll, equals(0.0));
      });

      test('returns effective post-roll when enabled', () {
        const config = RollConfig(postRoll: 1.0, postRollEnabled: true);
        expect(config.effectivePostRoll, equals(1.0));
      });

      test('returns zero post-roll when disabled', () {
        const config = RollConfig(postRoll: 1.0, postRollEnabled: false);
        expect(config.effectivePostRoll, equals(0.0));
      });

      test('serializes to JSON correctly', () {
        const config = RollConfig(
          preRoll: 3.0,
          postRoll: 1.5,
          preRollEnabled: true,
          postRollEnabled: false,
        );
        final json = config.toJson();
        final restored = RollConfig.fromJson(json);
        expect(restored.preRoll, equals(3.0));
        expect(restored.postRoll, equals(1.5));
        expect(restored.preRollEnabled, isTrue);
        expect(restored.postRollEnabled, isFalse);
      });
    });

    group('PunchConfig', () {
      test('calculates transportStartTime with pre-roll', () {
        const config = PunchConfig(
          region: PunchRegion(punchIn: 5.0, punchOut: 10.0),
          roll: RollConfig(preRoll: 2.0, preRollEnabled: true),
        );
        expect(config.transportStartTime, equals(3.0));
      });

      test('clamps transportStartTime to zero', () {
        const config = PunchConfig(
          region: PunchRegion(punchIn: 1.0, punchOut: 5.0),
          roll: RollConfig(preRoll: 3.0, preRollEnabled: true),
        );
        expect(config.transportStartTime, equals(0.0));
      });

      test('calculates transportStopTime with post-roll', () {
        const config = PunchConfig(
          region: PunchRegion(punchIn: 5.0, punchOut: 10.0),
          roll: RollConfig(postRoll: 1.0, postRollEnabled: true),
        );
        expect(config.transportStopTime, equals(11.0));
      });

      test('serializes all modes correctly', () {
        for (final mode in PunchMode.values) {
          final config = PunchConfig(mode: mode);
          final json = config.toJson();
          final restored = PunchConfig.fromJson(json);
          expect(restored.mode, equals(mode));
        }
      });
    });

    group('PunchState', () {
      test('isActive returns correct value for phases', () {
        expect(const PunchState(phase: PunchPhase.idle).isActive, isFalse);
        expect(const PunchState(phase: PunchPhase.preRoll).isActive, isTrue);
        expect(const PunchState(phase: PunchPhase.recording).isActive, isTrue);
        expect(const PunchState(phase: PunchPhase.postRoll).isActive, isTrue);
        expect(const PunchState(phase: PunchPhase.complete).isActive, isFalse);
      });

      test('isRecording returns correct value', () {
        expect(const PunchState(phase: PunchPhase.recording).isRecording, isTrue);
        expect(const PunchState(phase: PunchPhase.preRoll).isRecording, isFalse);
        expect(const PunchState(phase: PunchPhase.postRoll).isRecording, isFalse);
      });
    });

    group('Service operations', () {
      test('configure updates config', () {
        const config = PunchConfig(
          mode: PunchMode.loop,
          countInBars: 2,
        );
        service.configure(config);
        expect(service.state.config.mode, equals(PunchMode.loop));
        expect(service.state.config.countInBars, equals(2));
      });

      test('setPunchRegion updates region', () {
        service.setPunchRegion(3.0, 8.0);
        expect(service.state.config.region.punchIn, equals(3.0));
        expect(service.state.config.region.punchOut, equals(8.0));
      });

      test('setPreRoll updates roll config', () {
        service.setPreRoll(4.0);
        expect(service.state.config.roll.preRoll, equals(4.0));
      });

      test('setPostRoll updates roll config', () {
        service.setPostRoll(2.5);
        expect(service.state.config.roll.postRoll, equals(2.5));
      });

      test('setMode updates punch mode', () {
        service.setMode(PunchMode.quick);
        expect(service.state.config.mode, equals(PunchMode.quick));
      });

      test('getRecordedTakes returns unmodifiable list', () {
        final takes = service.getRecordedTakes();
        expect(takes, isA<List>());
        expect(() => takes.add(null as dynamic), throwsUnsupportedError);
      });
    });
  });
}
