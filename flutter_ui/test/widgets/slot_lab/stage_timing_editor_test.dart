/// Stage Timing Editor Tests (P12.1.15)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/stage_timing_editor.dart';

void main() {
  group('StageTiming', () {
    test('totalTimeMs calculates correctly', () {
      const timing = StageTiming(
        stageId: 'stage_1',
        stageName: 'Test Stage',
        baseTimeMs: 1000,
        delayMs: 200,
      );

      expect(timing.totalTimeMs, 1200);
    });

    test('negative delay reduces total time', () {
      const timing = StageTiming(
        stageId: 'stage_1',
        stageName: 'Test Stage',
        baseTimeMs: 1000,
        delayMs: -300,
      );

      expect(timing.totalTimeMs, 700);
    });

    test('copyWith preserves unmodified fields', () {
      const original = StageTiming(
        stageId: 'stage_1',
        stageName: 'Original',
        baseTimeMs: 500,
        delayMs: 100,
      );
      final copied = original.copyWith(delayMs: 200);

      expect(copied.stageId, original.stageId);
      expect(copied.stageName, original.stageName);
      expect(copied.baseTimeMs, original.baseTimeMs);
      expect(copied.delayMs, 200);
    });

    test('default color is blue', () {
      const timing = StageTiming(
        stageId: 'stage_1',
        stageName: 'Test',
        baseTimeMs: 0,
      );

      expect(timing.color, const Color(0xFF4A9EFF));
    });
  });

  group('GridSnap', () {
    test('has all expected values', () {
      expect(GridSnap.values.length, 5);
      expect(GridSnap.off.valueMs, 0);
      expect(GridSnap.ms10.valueMs, 10);
      expect(GridSnap.ms50.valueMs, 50);
      expect(GridSnap.ms100.valueMs, 100);
      expect(GridSnap.ms250.valueMs, 250);
    });

    test('labels are human readable', () {
      expect(GridSnap.off.label, 'Off');
      expect(GridSnap.ms10.label, '10ms');
      expect(GridSnap.ms50.label, '50ms');
      expect(GridSnap.ms100.label, '100ms');
      expect(GridSnap.ms250.label, '250ms');
    });
  });
}
