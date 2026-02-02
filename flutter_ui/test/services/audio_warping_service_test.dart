import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui/services/audio_warping_service.dart';

void main() {
  group('AudioWarpingService', () {
    late AudioWarpingService service;

    setUp(() {
      service = AudioWarpingService.instance;
      // Clear test clip state
      service.clearWarpState('test-clip');
    });

    group('WarpMarker', () {
      test('calculates stretch ratio correctly', () {
        const marker = WarpMarker(
          id: 'test',
          sourcePosition: 2.0,
          timelinePosition: 4.0,
        );
        expect(marker.stretchRatio, equals(2.0)); // 4/2 = 2x stretch
      });

      test('handles zero source position', () {
        const marker = WarpMarker(
          id: 'test',
          sourcePosition: 0,
          timelinePosition: 0,
        );
        expect(marker.stretchRatio, equals(1.0));
      });

      test('serializes to JSON correctly', () {
        const marker = WarpMarker(
          id: 'test-1',
          sourcePosition: 1.5,
          timelinePosition: 2.0,
          locked: true,
          isTransient: true,
          transientStrength: 0.8,
        );
        final json = marker.toJson();
        final restored = WarpMarker.fromJson(json);
        expect(restored.id, equals('test-1'));
        expect(restored.sourcePosition, equals(1.5));
        expect(restored.timelinePosition, equals(2.0));
        expect(restored.locked, isTrue);
        expect(restored.isTransient, isTrue);
        expect(restored.transientStrength, equals(0.8));
      });
    });

    group('WarpState', () {
      test('calculates warped duration from markers', () {
        const state = WarpState(
          clipId: 'test',
          originalDuration: 10.0,
          markers: [
            WarpMarker(id: '1', sourcePosition: 0, timelinePosition: 0),
            WarpMarker(id: '2', sourcePosition: 5, timelinePosition: 6),
            WarpMarker(id: '3', sourcePosition: 10, timelinePosition: 15),
          ],
        );
        expect(state.warpedDuration, equals(15.0));
      });

      test('calculates overall stretch ratio', () {
        const state = WarpState(
          clipId: 'test',
          originalDuration: 10.0,
          markers: [
            WarpMarker(id: '1', sourcePosition: 0, timelinePosition: 0),
            WarpMarker(id: '2', sourcePosition: 10, timelinePosition: 20),
          ],
        );
        expect(state.overallStretchRatio, equals(2.0));
      });

      test('serializes all algorithms correctly', () {
        for (final algo in WarpAlgorithm.values) {
          final state = WarpState(
            clipId: 'test',
            algorithm: algo,
            originalDuration: 5.0,
          );
          final json = state.toJson();
          final restored = WarpState.fromJson(json);
          expect(restored.algorithm, equals(algo));
        }
      });
    });

    group('Service initialization', () {
      test('initializeWarp creates state with default markers', () {
        final state = service.initializeWarp('test-clip', 10.0);
        expect(state.clipId, equals('test-clip'));
        expect(state.originalDuration, equals(10.0));
        expect(state.markers.length, equals(2)); // Start and end markers
        expect(state.markers.first.sourcePosition, equals(0));
        expect(state.markers.last.sourcePosition, equals(10.0));
      });

      test('initializeWarp returns existing state', () {
        final state1 = service.initializeWarp('test-clip', 10.0);
        final state2 = service.initializeWarp('test-clip', 20.0);
        expect(state2.originalDuration, equals(10.0)); // Should not change
      });
    });

    group('Warp settings', () {
      test('setWarpEnabled updates state', () {
        service.initializeWarp('test-clip', 10.0);
        service.setWarpEnabled('test-clip', true);
        expect(service.getWarpState('test-clip')?.enabled, isTrue);
      });

      test('setAlgorithm updates algorithm', () {
        service.initializeWarp('test-clip', 10.0);
        service.setAlgorithm('test-clip', WarpAlgorithm.beats);
        expect(service.getWarpState('test-clip')?.algorithm, equals(WarpAlgorithm.beats));
      });

      test('setPreservePitch updates setting', () {
        service.initializeWarp('test-clip', 10.0);
        service.setPreservePitch('test-clip', false);
        expect(service.getWarpState('test-clip')?.preservePitch, isFalse);
      });

      test('setQuality clamps value', () {
        service.initializeWarp('test-clip', 10.0);
        service.setQuality('test-clip', 1.5);
        expect(service.getWarpState('test-clip')?.quality, equals(1.0));
        service.setQuality('test-clip', -0.5);
        expect(service.getWarpState('test-clip')?.quality, equals(0.0));
      });
    });

    group('Marker operations', () {
      test('addMarker inserts marker sorted by source position', () {
        service.initializeWarp('test-clip', 10.0);
        final marker = service.addMarker('test-clip', 5.0, 6.0);
        expect(marker, isNotNull);
        final state = service.getWarpState('test-clip');
        expect(state!.markers.length, equals(3));
        // Should be sorted: 0, 5, 10
        expect(state.markers[0].sourcePosition, equals(0));
        expect(state.markers[1].sourcePosition, equals(5.0));
        expect(state.markers[2].sourcePosition, equals(10.0));
      });

      test('moveMarker updates timeline position', () {
        service.initializeWarp('test-clip', 10.0);
        final marker = service.addMarker('test-clip', 5.0, 5.0);
        service.moveMarker('test-clip', marker!.id, 7.0);
        final state = service.getWarpState('test-clip');
        final movedMarker = state!.markers.firstWhere((m) => m.id == marker.id);
        expect(movedMarker.timelinePosition, equals(7.0));
      });

      test('moveMarker does not move locked markers', () {
        service.initializeWarp('test-clip', 10.0);
        final marker = service.addMarker('test-clip', 5.0, 5.0);
        service.setMarkerLocked('test-clip', marker!.id, true);
        service.moveMarker('test-clip', marker.id, 7.0);
        final state = service.getWarpState('test-clip');
        final lockedMarker = state!.markers.firstWhere((m) => m.id == marker.id);
        expect(lockedMarker.timelinePosition, equals(5.0)); // Unchanged
      });

      test('deleteMarker removes marker', () {
        service.initializeWarp('test-clip', 10.0);
        final marker = service.addMarker('test-clip', 5.0, 5.0);
        service.deleteMarker('test-clip', marker!.id);
        final state = service.getWarpState('test-clip');
        expect(state!.markers.length, equals(2)); // Only start and end
      });

      test('resetMarkers keeps only start and end', () {
        service.initializeWarp('test-clip', 10.0);
        service.addMarker('test-clip', 3.0, 4.0);
        service.addMarker('test-clip', 6.0, 8.0);
        service.resetMarkers('test-clip');
        final state = service.getWarpState('test-clip');
        expect(state!.markers.length, equals(2));
      });
    });

    group('Position calculations', () {
      test('getPlaybackRate returns 1.0 when disabled', () {
        service.initializeWarp('test-clip', 10.0);
        final rate = service.getPlaybackRate('test-clip', 5.0);
        expect(rate, equals(1.0));
      });

      test('getPlaybackRate calculates correct rate', () {
        service.initializeWarp('test-clip', 10.0);
        service.setWarpEnabled('test-clip', true);
        // Modify end marker to stretch 2x
        service.moveMarker(
          'test-clip',
          service.getWarpState('test-clip')!.markers.last.id,
          20.0,
        );
        final rate = service.getPlaybackRate('test-clip', 5.0);
        expect(rate, equals(2.0)); // 20/10 = 2x
      });

      test('sourceToTimeline converts positions correctly', () {
        service.initializeWarp('test-clip', 10.0);
        service.setWarpEnabled('test-clip', true);
        service.moveMarker(
          'test-clip',
          service.getWarpState('test-clip')!.markers.last.id,
          20.0,
        );
        final timeline = service.sourceToTimeline('test-clip', 5.0);
        expect(timeline, equals(10.0)); // 5 * 2 = 10
      });

      test('timelineToSource converts positions correctly', () {
        service.initializeWarp('test-clip', 10.0);
        service.setWarpEnabled('test-clip', true);
        service.moveMarker(
          'test-clip',
          service.getWarpState('test-clip')!.markers.last.id,
          20.0,
        );
        final source = service.timelineToSource('test-clip', 10.0);
        expect(source, equals(5.0)); // 10 / 2 = 5
      });
    });

    group('Algorithm names', () {
      test('warpAlgorithmName returns correct names', () {
        expect(warpAlgorithmName(WarpAlgorithm.beats), equals('Beats'));
        expect(warpAlgorithmName(WarpAlgorithm.tones), equals('Tones'));
        expect(warpAlgorithmName(WarpAlgorithm.complex), equals('Complex'));
        expect(warpAlgorithmName(WarpAlgorithm.repitch), equals('Re-Pitch'));
        expect(warpAlgorithmName(WarpAlgorithm.texture), equals('Texture'));
      });
    });
  });
}
