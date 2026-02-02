import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui/services/elastic_audio_service.dart';

void main() {
  group('ElasticAudioService', () {
    late ElasticAudioService service;

    setUp(() {
      service = ElasticAudioService.instance;
      service.clearState('test-clip');
    });

    group('PitchNote', () {
      test('calculates MIDI note from Hz', () {
        // A4 = 440Hz = MIDI 69
        const note = PitchNote(
          id: 'test',
          startTime: 0,
          duration: 1,
          detectedPitch: 440.0,
          targetPitch: 440.0,
        );
        expect(note.midiNote, equals(69));
      });

      test('calculates offset in cents', () {
        // Octave up = 1200 cents
        const note = PitchNote(
          id: 'test',
          startTime: 0,
          duration: 1,
          detectedPitch: 440.0,
          targetPitch: 880.0, // One octave up
        );
        expect(note.offsetCents, closeTo(1200, 1));
      });

      test('calculates offset in semitones', () {
        const note = PitchNote(
          id: 'test',
          startTime: 0,
          duration: 1,
          detectedPitch: 440.0,
          targetPitch: 880.0, // One octave = 12 semitones
        );
        expect(note.offsetSemitones, closeTo(12, 0.1));
      });

      test('serializes to JSON correctly', () {
        const note = PitchNote(
          id: 'note-1',
          startTime: 1.5,
          duration: 0.5,
          detectedPitch: 440.0,
          targetPitch: 466.16, // A#4
          drift: 0.5,
          confidence: 0.95,
        );
        final json = note.toJson();
        final restored = PitchNote.fromJson(json);
        expect(restored.id, equals('note-1'));
        expect(restored.startTime, equals(1.5));
        expect(restored.detectedPitch, equals(440.0));
        expect(restored.drift, equals(0.5));
        expect(restored.confidence, equals(0.95));
      });
    });

    group('PitchScale', () {
      test('major scale contains correct notes', () {
        const scale = PitchScale.major;
        // C major: C D E F G A B
        expect(scale.containsNote(60), isTrue);  // C
        expect(scale.containsNote(62), isTrue);  // D
        expect(scale.containsNote(64), isTrue);  // E
        expect(scale.containsNote(65), isTrue);  // F
        expect(scale.containsNote(67), isTrue);  // G
        expect(scale.containsNote(69), isTrue);  // A
        expect(scale.containsNote(71), isTrue);  // B
        expect(scale.containsNote(61), isFalse); // C#
        expect(scale.containsNote(63), isFalse); // D#
      });

      test('quantize snaps to nearest scale note', () {
        const scale = PitchScale.major;
        expect(scale.quantize(61), equals(60)); // C# -> C
        expect(scale.quantize(63), equals(64)); // D# -> E
        expect(scale.quantize(66), equals(67)); // F# -> G
      });

      test('quantizeHz returns Hz in scale', () {
        const scale = PitchScale.major;
        // A4 = 440Hz is in C major (it's the 6th degree)
        final quantized = scale.quantizeHz(440.0);
        expect(quantized, equals(440.0));
      });

      test('serializes to JSON correctly', () {
        const scale = PitchScale.major;
        final json = scale.toJson();
        final restored = PitchScale.fromJson(json);
        expect(restored.name, equals('Major'));
        expect(restored.rootNote, equals(0));
        expect(restored.intervals, equals([0, 2, 4, 5, 7, 9, 11]));
      });
    });

    group('ElasticAudioState', () {
      test('serializes all algorithms correctly', () {
        for (final algo in PitchAlgorithm.values) {
          final state = ElasticAudioState(
            clipId: 'test',
            algorithm: algo,
          );
          final json = state.toJson();
          final restored = ElasticAudioState.fromJson(json);
          expect(restored.algorithm, equals(algo));
        }
      });
    });

    group('Service initialization', () {
      test('initializeElastic creates state', () {
        final state = service.initializeElastic('test-clip');
        expect(state.clipId, equals('test-clip'));
        expect(state.enabled, isFalse);
        expect(state.pitchOffset, equals(0));
      });

      test('initializeElastic returns existing state', () {
        final state1 = service.initializeElastic('test-clip');
        service.setPitchOffset('test-clip', 5.0);
        final state2 = service.initializeElastic('test-clip');
        expect(state2.pitchOffset, equals(5.0));
      });
    });

    group('Pitch settings', () {
      test('setEnabled updates state', () {
        service.initializeElastic('test-clip');
        service.setEnabled('test-clip', true);
        expect(service.getState('test-clip')?.enabled, isTrue);
      });

      test('setAlgorithm updates algorithm', () {
        service.initializeElastic('test-clip');
        service.setAlgorithm('test-clip', PitchAlgorithm.monophonic);
        expect(service.getState('test-clip')?.algorithm, equals(PitchAlgorithm.monophonic));
      });

      test('setPitchOffset clamps value', () {
        service.initializeElastic('test-clip');
        service.setPitchOffset('test-clip', 30.0);
        expect(service.getState('test-clip')?.pitchOffset, equals(24.0)); // Max
        service.setPitchOffset('test-clip', -30.0);
        expect(service.getState('test-clip')?.pitchOffset, equals(-24.0)); // Min
      });

      test('setFormantPreservation clamps value', () {
        service.initializeElastic('test-clip');
        service.setFormantPreservation('test-clip', 1.5);
        expect(service.getState('test-clip')?.formantPreservation, equals(1.0));
        service.setFormantPreservation('test-clip', -0.5);
        expect(service.getState('test-clip')?.formantPreservation, equals(0.0));
      });

      test('setQuantizeStrength clamps value', () {
        service.initializeElastic('test-clip');
        service.setQuantizeStrength('test-clip', 1.5);
        expect(service.getState('test-clip')?.quantizeStrength, equals(1.0));
      });
    });

    group('Note operations', () {
      test('addDetectedNotes adds notes', () {
        service.initializeElastic('test-clip');
        final notes = [
          const PitchNote(
            id: 'note-1',
            startTime: 0,
            duration: 1,
            detectedPitch: 440.0,
            targetPitch: 440.0,
          ),
        ];
        service.addDetectedNotes('test-clip', notes);
        expect(service.getState('test-clip')?.notes.length, equals(1));
      });

      test('editNotePitch clamps pitch', () {
        service.initializeElastic('test-clip');
        service.addDetectedNotes('test-clip', [
          const PitchNote(
            id: 'note-1',
            startTime: 0,
            duration: 1,
            detectedPitch: 440.0,
            targetPitch: 440.0,
          ),
        ]);
        service.editNotePitch('test-clip', 'note-1', 50000.0);
        final note = service.getState('test-clip')?.notes.first;
        expect(note?.targetPitch, equals(20000.0)); // Clamped to max
      });

      test('transposeNotes shifts pitch correctly', () {
        service.initializeElastic('test-clip');
        service.addDetectedNotes('test-clip', [
          const PitchNote(
            id: 'note-1',
            startTime: 0,
            duration: 1,
            detectedPitch: 440.0,
            targetPitch: 440.0,
          ),
        ]);
        service.transposeNotes('test-clip', ['note-1'], 12.0); // Octave up
        final note = service.getState('test-clip')?.notes.first;
        expect(note?.targetPitch, closeTo(880.0, 1.0));
      });

      test('resetNote restores detected pitch', () {
        service.initializeElastic('test-clip');
        service.addDetectedNotes('test-clip', [
          const PitchNote(
            id: 'note-1',
            startTime: 0,
            duration: 1,
            detectedPitch: 440.0,
            targetPitch: 880.0,
          ),
        ]);
        service.resetNote('test-clip', 'note-1');
        final note = service.getState('test-clip')?.notes.first;
        expect(note?.targetPitch, equals(440.0));
      });
    });

    group('Pitch calculations', () {
      test('getPitchOffset returns 0 when disabled', () {
        service.initializeElastic('test-clip');
        final offset = service.getPitchOffset('test-clip', 0.5);
        expect(offset, equals(0));
      });

      test('getPitchOffset includes global offset', () {
        service.initializeElastic('test-clip');
        service.setEnabled('test-clip', true);
        service.setPitchOffset('test-clip', 5.0);
        final offset = service.getPitchOffset('test-clip', 0.5);
        expect(offset, equals(5.0));
      });

      test('getPitchRatio converts offset to ratio', () {
        service.initializeElastic('test-clip');
        service.setEnabled('test-clip', true);
        service.setPitchOffset('test-clip', 12.0); // One octave
        final ratio = service.getPitchRatio('test-clip', 0.5);
        expect(ratio, closeTo(2.0, 0.001)); // 2^(12/12) = 2
      });
    });

    group('Algorithm names', () {
      test('pitchAlgorithmName returns correct names', () {
        expect(pitchAlgorithmName(PitchAlgorithm.polyphonic), equals('Polyphonic'));
        expect(pitchAlgorithmName(PitchAlgorithm.monophonic), equals('Monophonic'));
        expect(pitchAlgorithmName(PitchAlgorithm.rhythmic), equals('Rhythmic'));
        expect(pitchAlgorithmName(PitchAlgorithm.speed), equals('Varispeed'));
      });
    });
  });
}
