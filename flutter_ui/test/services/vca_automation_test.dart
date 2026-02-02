/// VCA Automation Service Tests (P10.1.15)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/vca_automation_service.dart';

void main() {
  group('AutomationPoint', () {
    test('creates with correct values', () {
      const point = AutomationPoint(timestampMs: 100, value: 0.8);

      expect(point.timestampMs, 100);
      expect(point.value, 0.8);
    });

    test('serializes to and from JSON', () {
      const original = AutomationPoint(timestampMs: 250, value: 1.2);
      final json = original.toJson();
      final restored = AutomationPoint.fromJson(json);

      expect(restored.timestampMs, original.timestampMs);
      expect(restored.value, original.value);
    });
  });

  group('AutomationLane', () {
    test('interpolates values correctly', () {
      final lane = AutomationLane(
        id: 'lane_1',
        vcaId: 'vca_1',
        name: 'Test Lane',
        points: const [
          AutomationPoint(timestampMs: 0, value: 0.0),
          AutomationPoint(timestampMs: 100, value: 1.0),
        ],
      );

      expect(lane.valueAt(0), 0.0);
      expect(lane.valueAt(50), 0.5);
      expect(lane.valueAt(100), 1.0);
    });

    test('returns edge values outside range', () {
      final lane = AutomationLane(
        id: 'lane_1',
        vcaId: 'vca_1',
        name: 'Test Lane',
        points: const [
          AutomationPoint(timestampMs: 100, value: 0.5),
          AutomationPoint(timestampMs: 200, value: 1.0),
        ],
      );

      expect(lane.valueAt(50), 0.5); // Before first point
      expect(lane.valueAt(300), 1.0); // After last point
    });

    test('calculates duration correctly', () {
      final lane = AutomationLane(
        id: 'lane_1',
        vcaId: 'vca_1',
        name: 'Test Lane',
        points: const [
          AutomationPoint(timestampMs: 100, value: 0.5),
          AutomationPoint(timestampMs: 500, value: 1.0),
        ],
      );

      expect(lane.durationMs, 400);
    });
  });

  group('VcaAutomationService', () {
    late VcaAutomationService service;

    setUp(() {
      service = VcaAutomationService.instance;
      service.cancelRecording(); // Ensure no active recording
      service.stopPlayback(); // Ensure no active playback
      service.clearAllLanes();
    });

    tearDown(() {
      service.cancelRecording();
      service.stopPlayback();
      service.clearAllLanes();
    });

    test('starts and stops recording', () {
      expect(service.isRecording, false);

      service.startRecording('vca_1');
      expect(service.isRecording, true);
      expect(service.recordingVcaId, 'vca_1');

      service.stopRecording();
      expect(service.isRecording, false);
    });

    test('captures automation points during recording', () {
      service.startRecording('vca_1');

      service.captureAutomationPoint(0.5);
      service.captureAutomationPoint(0.7);
      service.captureAutomationPoint(1.0);

      final lane = service.stopRecording(name: 'Test Recording');

      expect(lane, isNotNull);
      expect(lane!.points.length, greaterThanOrEqualTo(1));
      expect(lane.vcaId, 'vca_1');
      expect(lane.name, 'Test Recording');
    });

    test('clamps values during capture', () {
      service.startRecording('vca_1');

      service.captureAutomationPoint(2.0); // Above max
      service.captureAutomationPoint(-1.0); // Below min

      final lane = service.stopRecording();

      expect(lane, isNotNull);
      for (final point in lane!.points) {
        expect(point.value, greaterThanOrEqualTo(0.0));
        expect(point.value, lessThanOrEqualTo(1.5));
      }
    });

    test('returns null when stopping with no points', () {
      service.startRecording('vca_1');
      final lane = service.stopRecording();

      expect(lane, isNull);
    });

    test('deletes lanes correctly', () {
      service.startRecording('vca_1');
      service.captureAutomationPoint(0.5);
      final lane = service.stopRecording()!;

      expect(service.lanes.length, 1);

      service.deleteLane(lane.id);
      expect(service.lanes.length, 0);
    });

    test('filters lanes by VCA', () async {
      // Record for vca_1
      service.startRecording('vca_1');
      service.captureAutomationPoint(0.5);
      await Future.delayed(const Duration(milliseconds: 10)); // Ensure different timestamp
      service.captureAutomationPoint(0.6);
      final lane1 = service.stopRecording();
      expect(lane1, isNotNull, reason: 'Lane 1 should be created');

      // Record for vca_2
      service.startRecording('vca_2');
      service.captureAutomationPoint(0.7);
      await Future.delayed(const Duration(milliseconds: 10));
      service.captureAutomationPoint(0.8);
      final lane2 = service.stopRecording();
      expect(lane2, isNotNull, reason: 'Lane 2 should be created');

      // Check filtering
      expect(service.lanes.length, 2, reason: 'Should have 2 total lanes');
      expect(service.getLanesForVca('vca_1').length, 1);
      expect(service.getLanesForVca('vca_2').length, 1);
      expect(service.getLanesForVca('vca_3').length, 0);
    });

    test('serializes and deserializes', () {
      service.startRecording('vca_1');
      service.captureAutomationPoint(0.5);
      service.stopRecording(name: 'Serialization Test');

      final json = service.toJson();
      service.clearAllLanes();
      expect(service.lanes.length, 0);

      service.fromJson(json);
      expect(service.lanes.length, 1);
      expect(service.lanes.first.name, 'Serialization Test');
    });
  });
}
