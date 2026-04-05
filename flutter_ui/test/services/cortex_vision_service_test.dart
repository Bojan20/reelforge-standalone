import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/cortex_vision_service.dart';

void main() {
  group('CortexVisionService', () {
    test('singleton instance', () {
      final a = CortexVisionService.instance;
      final b = CortexVisionService.instance;
      expect(identical(a, b), isTrue);
    });

    test('register and retrieve regions', () {
      final vision = CortexVisionService.instance;

      final region = vision.registerRegion(
        name: 'test_timeline',
        description: 'Timeline test region',
      );

      expect(region.name, 'test_timeline');
      expect(region.description, 'Timeline test region');
      expect(region.boundaryKey, isNotNull);

      final retrieved = vision.getRegion('test_timeline');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'test_timeline');

      // Cleanup
      vision.unregisterRegion('test_timeline');
      expect(vision.getRegion('test_timeline'), isNull);
    });

    test('register multiple regions', () {
      final vision = CortexVisionService.instance;

      vision.registerRegion(name: 'r1', description: 'Region 1');
      vision.registerRegion(name: 'r2', description: 'Region 2');
      vision.registerRegion(name: 'r3', description: 'Region 3');

      expect(vision.regions.length, greaterThanOrEqualTo(3));
      expect(vision.regions.containsKey('r1'), isTrue);
      expect(vision.regions.containsKey('r2'), isTrue);
      expect(vision.regions.containsKey('r3'), isTrue);

      // Cleanup
      vision.unregisterRegion('r1');
      vision.unregisterRegion('r2');
      vision.unregisterRegion('r3');
    });

    test('rootBoundaryKey is stable', () {
      final vision = CortexVisionService.instance;
      final key1 = vision.rootBoundaryKey;
      final key2 = vision.rootBoundaryKey;
      expect(identical(key1, key2), isTrue);
    });

    test('record and retrieve events', () {
      final vision = CortexVisionService.instance;

      vision.recordEvent(
        type: VisionEventType.stateChange,
        description: 'Screen changed to DAW',
      );

      expect(vision.events.isNotEmpty, isTrue);
      expect(vision.events.first.type, VisionEventType.stateChange);
      expect(vision.events.first.description, 'Screen changed to DAW');
    });

    test('VisionSnapshot toString', () {
      final snapshot = VisionSnapshot(
        regionName: 'test',
        capturedAt: DateTime.now(),
        filePath: '/tmp/test.png',
        width: 1920,
        height: 1080,
        byteSize: 102400,
      );

      expect(snapshot.resolution, '1920x1080');
      expect(snapshot.sizeKB, '100.0 KB');
      expect(snapshot.toString(), contains('test'));
      expect(snapshot.toString(), contains('1920x1080'));
    });

    test('pixel ratio default', () {
      final vision = CortexVisionService.instance;
      expect(vision.pixelRatio, 2.0);
    });

    test('observing state', () {
      final vision = CortexVisionService.instance;
      expect(vision.isObserving, isFalse);
    });

    test('snapshots list is unmodifiable', () {
      final vision = CortexVisionService.instance;
      expect(() => (vision.snapshots as List).add(null), throwsA(anything));
    });

    test('regions map is unmodifiable', () {
      final vision = CortexVisionService.instance;
      expect(() => (vision.regions as Map)['x'] = null, throwsA(anything));
    });
  });
}
