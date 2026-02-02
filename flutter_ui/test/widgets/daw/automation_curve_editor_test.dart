/// Automation Curve Editor Tests — P2-DAW-3
///
/// Tests for visual bezier curve editor functionality.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/daw/automation_curve_editor.dart';

void main() {
  group('AutomationCurveType', () {
    test('all curve types are defined', () {
      expect(AutomationCurveType.values.length, 6);
      expect(AutomationCurveType.values, contains(AutomationCurveType.linear));
      expect(AutomationCurveType.values, contains(AutomationCurveType.exponential));
      expect(AutomationCurveType.values, contains(AutomationCurveType.logarithmic));
      expect(AutomationCurveType.values, contains(AutomationCurveType.sCurve));
      expect(AutomationCurveType.values, contains(AutomationCurveType.hold));
      expect(AutomationCurveType.values, contains(AutomationCurveType.custom));
    });

    test('curve types have name and description', () {
      expect(AutomationCurveType.linear.name, 'Linear');
      expect(AutomationCurveType.linear.description, 'Straight line between points');

      expect(AutomationCurveType.sCurve.name, 'S-Curve');
      expect(AutomationCurveType.sCurve.description, 'Smooth S-shaped curve');
    });
  });

  group('AutomationPoint', () {
    test('creates point with required fields', () {
      final point = AutomationPoint(
        id: 'ap1',
        time: 0.5,
        value: 0.75,
      );

      expect(point.id, 'ap1');
      expect(point.time, 0.5);
      expect(point.value, 0.75);
      expect(point.curveType, AutomationCurveType.linear);
      expect(point.tension, 0.5);
      expect(point.selected, false);
    });

    test('copyWith updates only specified fields', () {
      final point = AutomationPoint(
        id: 'ap1',
        time: 0.5,
        value: 0.75,
      );

      final updated = point.copyWith(
        time: 0.8,
        selected: true,
      );

      expect(updated.id, 'ap1'); // Unchanged
      expect(updated.time, 0.8);
      expect(updated.value, 0.75); // Unchanged
      expect(updated.selected, true);
    });

    test('toJson and fromJson roundtrip preserves data', () {
      final point = AutomationPoint(
        id: 'ap1',
        time: 0.3,
        value: 0.9,
        curveType: AutomationCurveType.sCurve,
        tension: 0.7,
      );

      final json = point.toJson();
      final restored = AutomationPoint.fromJson(json);

      expect(restored.id, point.id);
      expect(restored.time, point.time);
      expect(restored.value, point.value);
      expect(restored.curveType, point.curveType);
      expect(restored.tension, point.tension);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'ap1',
        'time': 0.5,
        'value': 0.5,
      };

      final point = AutomationPoint.fromJson(json);

      expect(point.curveType, AutomationCurveType.linear);
      expect(point.tension, 0.5);
    });
  });

  group('AutomationPoint sorting', () {
    test('points can be sorted by time', () {
      final points = [
        AutomationPoint(id: 'a', time: 0.8, value: 0.5),
        AutomationPoint(id: 'b', time: 0.2, value: 0.5),
        AutomationPoint(id: 'c', time: 0.5, value: 0.5),
      ];

      points.sort((a, b) => a.time.compareTo(b.time));

      expect(points[0].id, 'b');
      expect(points[1].id, 'c');
      expect(points[2].id, 'a');
    });
  });

  group('AutomationPoint validation', () {
    test('time values are in valid range', () {
      final validPoint = AutomationPoint(
        id: 'ap1',
        time: 0.5,
        value: 0.5,
      );

      expect(validPoint.time, greaterThanOrEqualTo(0.0));
      expect(validPoint.time, lessThanOrEqualTo(1.0));
    });

    test('value values are in valid range', () {
      final validPoint = AutomationPoint(
        id: 'ap1',
        time: 0.5,
        value: 0.75,
      );

      expect(validPoint.value, greaterThanOrEqualTo(0.0));
      expect(validPoint.value, lessThanOrEqualTo(1.0));
    });
  });
}
