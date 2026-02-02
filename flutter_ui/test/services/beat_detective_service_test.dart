import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui/services/beat_detective_service.dart';

void main() {
  group('BeatDetectiveService', () {
    late BeatDetectiveService service;

    setUp(() {
      service = BeatDetectiveService.instance;
      service.clearState('test-clip');
    });

    group('BeatMarker', () {
      test('calculates offset correctly', () {
        const marker = BeatMarker(
          id: 'test',
          position: 2.0,
          strength: 0.8,
          quantizedPosition: 2.5,
        );
        expect(marker.offset, equals(0.5));
      });

      test('returns zero offset when not quantized', () {
        const marker = BeatMarker(
          id: 'test',
          position: 2.0,
          strength: 0.8,
        );
        expect(marker.offset, equals(0));
      });

      test('serializes to JSON correctly', () {
        const marker = BeatMarker(
          id: 'marker-1',
          position: 1.5,
          strength: 0.9,
          locked: true,
          quantizedPosition: 1.75,
          gridPosition: 3.0,
        );
        final json = marker.toJson();
        final restored = BeatMarker.fromJson(json);
        expect(restored.id, equals('marker-1'));
        expect(restored.position, equals(1.5));
        expect(restored.strength, equals(0.9));
        expect(restored.locked, isTrue);
        expect(restored.quantizedPosition, equals(1.75));
        expect(restored.gridPosition, equals(3.0));
      });
    });

    group('BeatDetectiveConfig', () {
      test('calculates grid interval correctly', () {
        const config = BeatDetectiveConfig(
          tempo: 120,
          gridResolution: 0.25, // 16th notes
        );
        // At 120 BPM, quarter = 0.5s, 16th = 0.125s
        expect(config.gridIntervalSeconds, equals(0.125));
      });

      test('serializes all modes correctly', () {
        for (final mode in QuantizeMode.values) {
          final config = BeatDetectiveConfig(mode: mode);
          final json = config.toJson();
          final restored = BeatDetectiveConfig.fromJson(json);
          expect(restored.mode, equals(mode));
        }
      });

      test('serializes all settings correctly', () {
        const config = BeatDetectiveConfig(
          sensitivity: 0.7,
          minInterval: 0.08,
          quantizeStrength: 0.5,
          gridResolution: 0.5,
          tempo: 140,
          mode: QuantizeMode.elastic,
          preserveGroove: true,
          grooveAmount: 0.3,
        );
        final json = config.toJson();
        final restored = BeatDetectiveConfig.fromJson(json);
        expect(restored.sensitivity, equals(0.7));
        expect(restored.minInterval, equals(0.08));
        expect(restored.quantizeStrength, equals(0.5));
        expect(restored.gridResolution, equals(0.5));
        expect(restored.tempo, equals(140));
        expect(restored.mode, equals(QuantizeMode.elastic));
        expect(restored.preserveGroove, isTrue);
        expect(restored.grooveAmount, equals(0.3));
      });
    });

    group('Service initialization', () {
      test('initialize creates state', () {
        final state = service.initialize('test-clip');
        expect(state.clipId, equals('test-clip'));
        expect(state.analyzed, isFalse);
        expect(state.markers, isEmpty);
      });

      test('initialize with custom config', () {
        const config = BeatDetectiveConfig(tempo: 140);
        final state = service.initialize('test-clip', config: config);
        expect(state.config.tempo, equals(140));
      });
    });

    group('Config settings', () {
      test('setSensitivity clamps value', () {
        service.initialize('test-clip');
        service.setSensitivity('test-clip', 1.5);
        expect(service.getState('test-clip')?.config.sensitivity, equals(1.0));
        service.setSensitivity('test-clip', -0.5);
        expect(service.getState('test-clip')?.config.sensitivity, equals(0.0));
      });

      test('setQuantizeStrength clamps value', () {
        service.initialize('test-clip');
        service.setQuantizeStrength('test-clip', 1.5);
        expect(service.getState('test-clip')?.config.quantizeStrength, equals(1.0));
      });

      test('setTempo clamps value', () {
        service.initialize('test-clip');
        service.setTempo('test-clip', 10);
        expect(service.getState('test-clip')?.config.tempo, equals(20)); // Min
        service.setTempo('test-clip', 500);
        expect(service.getState('test-clip')?.config.tempo, equals(300)); // Max
      });

      test('setGridResolution updates config', () {
        service.initialize('test-clip');
        service.setGridResolution('test-clip', 0.5);
        expect(service.getState('test-clip')?.config.gridResolution, equals(0.5));
      });
    });

    group('Transient detection', () {
      test('analyzeTransients detects peaks in audio', () {
        service.initialize('test-clip');

        // Create simple audio with transients
        final sampleRate = 44100;
        final audioData = List<double>.filled(sampleRate, 0.0);

        // Add transients at 0.1s, 0.5s, 0.9s
        for (int i = 4410; i < 4500; i++) {
          audioData[i] = 0.8; // Transient at 0.1s
        }
        for (int i = 22050; i < 22140; i++) {
          audioData[i] = 0.9; // Transient at 0.5s
        }
        for (int i = 39690; i < 39780; i++) {
          audioData[i] = 0.7; // Transient at 0.9s
        }

        final markers = service.analyzeTransients('test-clip', audioData, sampleRate);
        expect(markers, isNotEmpty);
        expect(service.getState('test-clip')?.analyzed, isTrue);
      });

      test('addMarkers sets markers directly', () {
        service.initialize('test-clip');
        final markers = [
          const BeatMarker(id: '1', position: 1.0, strength: 0.8),
          const BeatMarker(id: '2', position: 2.0, strength: 0.9),
        ];
        service.addMarkers('test-clip', markers);
        expect(service.getState('test-clip')?.markers.length, equals(2));
        expect(service.getState('test-clip')?.analyzed, isTrue);
      });

      test('addManualMarker adds marker', () {
        service.initialize('test-clip');
        final marker = service.addManualMarker('test-clip', 1.5);
        expect(marker, isNotNull);
        expect(marker!.position, equals(1.5));
        expect(marker.strength, equals(1.0)); // Manual = full strength
      });

      test('deleteMarker removes marker', () {
        service.initialize('test-clip');
        service.addMarkers('test-clip', [
          const BeatMarker(id: '1', position: 1.0, strength: 0.8),
          const BeatMarker(id: '2', position: 2.0, strength: 0.9),
        ]);
        service.deleteMarker('test-clip', '1');
        expect(service.getState('test-clip')?.markers.length, equals(1));
        expect(service.getState('test-clip')?.markers.first.id, equals('2'));
      });

      test('setMarkerLocked updates locked state', () {
        service.initialize('test-clip');
        service.addMarkers('test-clip', [
          const BeatMarker(id: '1', position: 1.0, strength: 0.8),
        ]);
        service.setMarkerLocked('test-clip', '1', true);
        expect(service.getState('test-clip')?.markers.first.locked, isTrue);
      });
    });

    group('Quantization', () {
      test('quantize applies quantization to markers', () {
        service.initialize('test-clip');
        service.setTempo('test-clip', 120);
        service.setGridResolution('test-clip', 1.0); // Quarter notes
        service.setQuantizeStrength('test-clip', 1.0);

        // Add marker slightly off the beat
        service.addMarkers('test-clip', [
          const BeatMarker(id: '1', position: 0.52, strength: 0.8), // Should quantize to 0.5
        ]);

        service.quantize('test-clip');
        final marker = service.getState('test-clip')?.markers.first;
        expect(marker?.quantizedPosition, closeTo(0.5, 0.01));
      });

      test('clearQuantization removes quantized positions', () {
        service.initialize('test-clip');
        service.addMarkers('test-clip', [
          const BeatMarker(id: '1', position: 0.52, strength: 0.8, quantizedPosition: 0.5),
        ]);
        service.clearQuantization('test-clip');
        final marker = service.getState('test-clip')?.markers.first;
        expect(marker?.quantizedPosition, isNull);
      });

      test('getWarpPoints returns quantized positions', () {
        service.initialize('test-clip');
        service.addMarkers('test-clip', [
          const BeatMarker(id: '1', position: 0.52, strength: 0.8, quantizedPosition: 0.5),
          const BeatMarker(id: '2', position: 1.03, strength: 0.9, quantizedPosition: 1.0),
        ]);
        final warpPoints = service.getWarpPoints('test-clip');
        expect(warpPoints.length, equals(2));
        expect(warpPoints[0].$1, equals(0.52)); // Original
        expect(warpPoints[0].$2, equals(0.5));  // Quantized
      });
    });

    group('Constants', () {
      test('kGridResolutions contains common values', () {
        expect(kGridResolutions, contains(1.0));    // Quarter
        expect(kGridResolutions, contains(0.5));    // Eighth
        expect(kGridResolutions, contains(0.25));   // Sixteenth
        expect(kGridResolutions, contains(0.333));  // Triplet
      });
    });
  });
}
