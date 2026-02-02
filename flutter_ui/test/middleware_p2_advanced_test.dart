/// Middleware P2 Advanced Features Tests
///
/// Tests for 5 power features:
/// - P2-MW-1: Container Preset Browser
/// - P2-MW-2: Container Timeline Zoom
/// - P2-MW-3: Advanced Ducking Curves
/// - P2-MW-4: Multi-Target RTPC
/// - P2-MW-5: RTPC Automation

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/middleware_models.dart';
import 'package:fluxforge_ui/services/advanced_ducking_curves_service.dart';
import 'package:fluxforge_ui/services/multi_target_rtpc_service.dart';
import 'package:fluxforge_ui/services/rtpc_automation_service.dart';
import 'package:fluxforge_ui/widgets/middleware/container_preset_browser.dart';
import 'package:fluxforge_ui/widgets/middleware/container_timeline_zoom.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════════
  // P2-MW-1: Container Preset Browser Tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('P2-MW-1: Container Preset Browser', () {
    test('ContainerPresetEntry has correct type color', () {
      const blendEntry = ContainerPresetEntry(
        id: 'test1',
        name: 'Test Blend',
        category: 'Test',
        type: ContainerPresetType.blend,
        description: 'Test description',
        previewData: {},
      );
      expect(blendEntry.typeColor.value, 0xFF9C27B0); // Purple

      const randomEntry = ContainerPresetEntry(
        id: 'test2',
        name: 'Test Random',
        category: 'Test',
        type: ContainerPresetType.random,
        description: 'Test description',
        previewData: {},
      );
      expect(randomEntry.typeColor.value, 0xFFFF9800); // Orange

      const sequenceEntry = ContainerPresetEntry(
        id: 'test3',
        name: 'Test Sequence',
        category: 'Test',
        type: ContainerPresetType.sequence,
        description: 'Test description',
        previewData: {},
      );
      expect(sequenceEntry.typeColor.value, 0xFF009688); // Teal
    });

    test('ContainerPresetEntry has correct type icon', () {
      const blendEntry = ContainerPresetEntry(
        id: 'test1',
        name: 'Test',
        category: 'Test',
        type: ContainerPresetType.blend,
        description: '',
        previewData: {},
      );
      expect(blendEntry.typeIcon.codePoint, 0xe3a5); // blur_linear

      const randomEntry = ContainerPresetEntry(
        id: 'test2',
        name: 'Test',
        category: 'Test',
        type: ContainerPresetType.random,
        description: '',
        previewData: {},
      );
      expect(randomEntry.typeIcon.codePoint, 0xe043); // shuffle
    });

    test('ContainerPresetType has all values', () {
      expect(ContainerPresetType.values.length, 3);
      expect(ContainerPresetType.blend.name, 'blend');
      expect(ContainerPresetType.random.name, 'random');
      expect(ContainerPresetType.sequence.name, 'sequence');
    });

    test('Factory preset has isFactory true by default', () {
      const entry = ContainerPresetEntry(
        id: 'test',
        name: 'Test',
        category: 'Test',
        type: ContainerPresetType.blend,
        description: '',
        previewData: {},
      );
      expect(entry.isFactory, true);
    });

    test('Factory preset can be marked as user preset', () {
      const entry = ContainerPresetEntry(
        id: 'test',
        name: 'Test',
        category: 'Test',
        type: ContainerPresetType.blend,
        description: '',
        previewData: {},
        isFactory: false,
      );
      expect(entry.isFactory, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // P2-MW-2: Container Timeline Zoom Tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('P2-MW-2: Container Timeline Zoom', () {
    test('TimelineZoomController initializes with default values', () {
      final controller = TimelineZoomController();
      expect(controller.zoom, 1.0);
      expect(controller.panOffset, 0.0);
      expect(controller.snapGridMs, null);
    });

    test('TimelineZoomController zoom is clamped', () {
      final controller = TimelineZoomController();
      controller.setZoom(0.05);
      expect(controller.zoom, 0.1);

      controller.setZoom(15.0);
      expect(controller.zoom, 10.0);
    });

    test('TimelineZoomController zoom in/out works', () {
      final controller = TimelineZoomController();
      controller.zoomIn();
      expect(controller.zoom, greaterThan(1.0));

      controller.resetZoom();
      controller.zoomOut();
      expect(controller.zoom, lessThan(1.0));
    });

    test('TimelineZoomController pan offset is non-negative', () {
      final controller = TimelineZoomController();
      controller.setPanOffset(-100);
      expect(controller.panOffset, 0.0);

      controller.setPanOffset(500);
      expect(controller.panOffset, 500.0);
    });

    test('TimelineZoomController snap to grid works', () {
      final controller = TimelineZoomController();
      controller.setSnapGrid(50);

      expect(controller.snapToGrid(47), 50);
      expect(controller.snapToGrid(73), 50);
      expect(controller.snapToGrid(76), 100);
    });

    test('TimelineZoomController snap disabled returns original', () {
      final controller = TimelineZoomController();
      controller.setSnapGrid(null);
      expect(controller.snapToGrid(47), 47);
    });

    test('TimelineZoomController reset works', () {
      final controller = TimelineZoomController();
      controller.setZoom(2.5);
      controller.setPanOffset(300);
      controller.resetZoom();
      expect(controller.zoom, 1.0);
      expect(controller.panOffset, 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // P2-MW-3: Advanced Ducking Curves Tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('P2-MW-3: Advanced Ducking Curves', () {
    test('Linear curve evaluates correctly', () {
      final service = AdvancedDuckingCurvesService.instance;
      const params = DuckingCurveParams(type: AdvancedDuckingCurve.linear);

      expect(service.evaluate(0.0, params), 0.0);
      expect(service.evaluate(0.5, params), 0.5);
      expect(service.evaluate(1.0, params), 1.0);
    });

    test('Exponential curve is concave', () {
      final service = AdvancedDuckingCurvesService.instance;
      const params = DuckingCurveParams(type: AdvancedDuckingCurve.exponential);

      // At midpoint, exponential should be below linear
      expect(service.evaluate(0.5, params), lessThan(0.5));
    });

    test('Logarithmic curve is convex', () {
      final service = AdvancedDuckingCurvesService.instance;
      const params = DuckingCurveParams(type: AdvancedDuckingCurve.logarithmic);

      // At midpoint, logarithmic should be above linear
      expect(service.evaluate(0.5, params), greaterThan(0.5));
    });

    test('S-Curve has inflection at midpoint', () {
      final service = AdvancedDuckingCurvesService.instance;
      const params = DuckingCurveParams(type: AdvancedDuckingCurve.sCurve);

      // S-curve should pass through midpoint
      expect(service.evaluate(0.5, params), closeTo(0.5, 0.1));
    });

    test('Curve samples generate correct count', () {
      final service = AdvancedDuckingCurvesService.instance;
      const params = DuckingCurveParams(type: AdvancedDuckingCurve.linear);

      final samples = service.generateCurveSamples(params, sampleCount: 10);
      expect(samples.length, 11); // 0 to 10 inclusive
    });

    test('DuckingCurveParams serialization round-trips', () {
      const params = DuckingCurveParams(
        type: AdvancedDuckingCurve.exponential,
        power: 2.5,
        tension: 1.8,
      );
      final json = params.toJson();
      final restored = DuckingCurveParams.fromJson(json);

      expect(restored.type, params.type);
      expect(restored.power, params.power);
      expect(restored.tension, params.tension);
    });

    test('Legacy curve conversion works', () {
      final service = AdvancedDuckingCurvesService.instance;

      expect(
        service.fromLegacyCurve(DuckingCurve.linear).type,
        AdvancedDuckingCurve.linear,
      );
      expect(
        service.fromLegacyCurve(DuckingCurve.exponential).type,
        AdvancedDuckingCurve.exponential,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // P2-MW-4: Multi-Target RTPC Tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('P2-MW-4: Multi-Target RTPC', () {
    late MultiTargetRtpcService service;

    setUp(() {
      service = MultiTargetRtpcService.instance;
      service.clear();
    });

    test('Register multi-target RTPC', () {
      service.registerMultiTarget(const MultiTargetRtpc(
        rtpcId: 1,
        name: 'Test RTPC',
        targets: [],
      ));

      expect(service.multiTargets.length, 1);
      expect(service.getMultiTarget(1)?.name, 'Test RTPC');
    });

    test('Unregister multi-target RTPC', () {
      service.registerMultiTarget(const MultiTargetRtpc(
        rtpcId: 1,
        name: 'Test RTPC',
        targets: [],
      ));
      service.unregisterMultiTarget(1);

      expect(service.multiTargets.isEmpty, true);
    });

    test('Add target to multi-target RTPC', () {
      service.registerMultiTarget(const MultiTargetRtpc(
        rtpcId: 1,
        name: 'Test RTPC',
        targets: [],
      ));

      service.addTarget(1, const RtpcTargetBinding(
        id: 'target1',
        parameter: RtpcTargetParameter.volume,
      ));

      expect(service.getMultiTarget(1)?.targets.length, 1);
    });

    test('Evaluate target with scaling', () {
      final target = const RtpcTargetBinding(
        id: 'test',
        parameter: RtpcTargetParameter.volume,
        scale: 0.5,
        offset: 0.1,
        outputMin: 0.0,
        outputMax: 1.0,
      );

      // 0.5 * 0.5 + 0.1 = 0.35
      final result = service.evaluateTarget(target, 0.5);
      expect(result, closeTo(0.35, 0.01));
    });

    test('Evaluate inverted target', () {
      final target = const RtpcTargetBinding(
        id: 'test',
        parameter: RtpcTargetParameter.volume,
        inverted: true,
        outputMin: 0.0,
        outputMax: 1.0,
      );

      final result = service.evaluateTarget(target, 0.3);
      expect(result, closeTo(0.7, 0.01));
    });

    test('MultiTargetRtpc serialization round-trips', () {
      const config = MultiTargetRtpc(
        rtpcId: 1,
        name: 'Test',
        targets: [
          RtpcTargetBinding(
            id: 'target1',
            parameter: RtpcTargetParameter.volume,
            scale: 2.0,
          ),
        ],
      );

      final json = config.toJson();
      final restored = MultiTargetRtpc.fromJson(json);

      expect(restored.rtpcId, config.rtpcId);
      expect(restored.name, config.name);
      expect(restored.targets.length, 1);
      expect(restored.targets.first.scale, 2.0);
    });

    test('Export and import config', () {
      service.registerMultiTarget(const MultiTargetRtpc(
        rtpcId: 1,
        name: 'Test',
        targets: [],
      ));

      final exported = service.exportConfig();
      service.clear();
      expect(service.multiTargets.isEmpty, true);

      service.importConfig(exported);
      expect(service.multiTargets.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // P2-MW-5: RTPC Automation Tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('P2-MW-5: RTPC Automation', () {
    late RtpcAutomationService service;

    setUp(() {
      service = RtpcAutomationService.instance;
      service.clear();
    });

    test('Initial state is idle', () {
      expect(service.state, AutomationState.idle);
    });

    test('Start recording changes state', () {
      service.startRecording(1, 'Test');
      expect(service.state, AutomationState.recording);
    });

    test('Record values during recording', () {
      service.startRecording(1, 'Test');
      service.recordValue(0.5);
      service.recordValue(0.7);

      final lane = service.stopRecording();
      expect(lane, isNotNull);
      expect(lane!.points.length, 2);
    });

    test('Stop recording returns to idle', () {
      service.startRecording(1, 'Test');
      service.stopRecording();
      expect(service.state, AutomationState.idle);
    });

    test('AutomationLane evaluates with interpolation', () {
      const lane = AutomationLane(
        rtpcId: 1,
        name: 'Test',
        points: [
          AutomationPoint(timeMs: 0, value: 0.0),
          AutomationPoint(timeMs: 100, value: 1.0),
        ],
        durationMs: 100,
      );

      expect(lane.evaluate(0), 0.0);
      expect(lane.evaluate(50), closeTo(0.5, 0.01));
      expect(lane.evaluate(100), 1.0);
    });

    test('AutomationLane clamps before first point', () {
      const lane = AutomationLane(
        rtpcId: 1,
        name: 'Test',
        points: [
          AutomationPoint(timeMs: 50, value: 0.5),
        ],
        durationMs: 100,
      );

      expect(lane.evaluate(0), 0.5);
    });

    test('AutomationLane serialization round-trips', () {
      const lane = AutomationLane(
        rtpcId: 1,
        name: 'Test Lane',
        points: [
          AutomationPoint(timeMs: 0, value: 0.0),
          AutomationPoint(timeMs: 100, value: 1.0),
        ],
        durationMs: 100,
      );

      final json = lane.toJson();
      final restored = AutomationLane.fromJson(json);

      expect(restored.rtpcId, lane.rtpcId);
      expect(restored.name, lane.name);
      expect(restored.points.length, 2);
      expect(restored.durationMs, 100);
    });

    test('Export and import all lanes', () {
      service.startRecording(1, 'Test');
      service.recordValue(0.5);
      service.stopRecording();

      final exported = service.exportAll();
      service.clearAllLanes();
      expect(service.lanes.isEmpty, true);

      service.importAll(exported);
      expect(service.lanes.length, 1);
    });

    test('Delete lane works', () {
      service.startRecording(1, 'Test');
      service.recordValue(0.5);
      service.stopRecording();

      expect(service.lanes.length, 1);
      service.deleteLane(1);
      expect(service.lanes.isEmpty, true);
    });

    test('Playback settings', () {
      service.setLooping(true);
      expect(service.looping, true);

      service.setPlaybackSpeed(2.0);
      expect(service.playbackSpeed, 2.0);
    });
  });
}
