// FAZA 5.1.5 — EmotionalArcEditor logic + smoke widget tests.
//
// The pure-data layer (`EmotionalArcOps`) is exercised exhaustively so a
// regression in editor math fails CI without needing a WidgetTester. A
// smoke widget test confirms the widget pumps without throwing and that
// gestures wire to the data layer end-to-end.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/generative_audio_service.dart';
import 'package:fluxforge_ui/widgets/generative/emotional_arc_editor.dart';

void main() {
  group('EmotionalArcOps.normalize', () {
    test('inserts endpoints when missing', () {
      final out = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.5, intensity: 0.7),
      ]);
      expect(out.first.t, 0.0);
      expect(out.last.t, 1.0);
      // Middle endpoint preserved.
      expect(out.any((p) => p.t == 0.5 && p.intensity == 0.7), isTrue);
    });

    test('clamps out-of-range fields', () {
      final out = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: -0.2, intensity: 1.5),
        EmotionalArcPoint(t: 1.3, intensity: -0.4),
      ]);
      expect(out.first.t, 0.0);
      expect(out.first.intensity, 1.0);
      expect(out.last.t, 1.0);
      expect(out.last.intensity, 0.0);
    });

    test('drops non-finite values', () {
      final out = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.5),
        EmotionalArcPoint(t: double.nan, intensity: 0.5),
        EmotionalArcPoint(t: 0.5, intensity: double.infinity),
        EmotionalArcPoint(t: 1.0, intensity: 0.8),
      ]);
      // NaN + Inf points must be dropped, only the 2 valid endpoints remain.
      expect(out.length, 2);
    });

    test('sorts unordered input', () {
      final out = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.8, intensity: 0.4),
        EmotionalArcPoint(t: 0.2, intensity: 0.9),
        EmotionalArcPoint(t: 0.0, intensity: 0.1),
        EmotionalArcPoint(t: 1.0, intensity: 0.5),
      ]);
      for (var i = 1; i < out.length; i++) {
        expect(out[i].t, greaterThanOrEqualTo(out[i - 1].t));
      }
    });

    test('empty input yields default 0.5 endpoints', () {
      final out = EmotionalArcOps.normalize(const []);
      expect(out.length, 2);
      expect(out.first.t, 0.0);
      expect(out.first.intensity, 0.5);
      expect(out.last.t, 1.0);
      expect(out.last.intensity, 0.5);
    });
  });

  group('EmotionalArcOps.insertPoint', () {
    final base = EmotionalArcOps.normalize(const [
      EmotionalArcPoint(t: 0.0, intensity: 0.1),
      EmotionalArcPoint(t: 1.0, intensity: 0.9),
    ]);

    test('inserts in sorted order', () {
      final out = EmotionalArcOps.insertPoint(
        base,
        const EmotionalArcPoint(t: 0.5, intensity: 0.7),
      );
      expect(out.length, 3);
      expect(out[1].t, 0.5);
    });

    test('replaces near-duplicate t instead of double-inserting', () {
      final mid = EmotionalArcOps.insertPoint(
        base,
        const EmotionalArcPoint(t: 0.5, intensity: 0.2),
      );
      final out = EmotionalArcOps.insertPoint(
        mid,
        const EmotionalArcPoint(t: 0.502, intensity: 0.8),
      );
      // Should still be 3 points, the middle one updated to intensity=0.8.
      expect(out.length, 3);
      expect(out[1].intensity, 0.8);
    });

    test('clamps out-of-range coordinates', () {
      final out = EmotionalArcOps.insertPoint(
        base,
        const EmotionalArcPoint(t: 2.0, intensity: -1.0),
      );
      expect(out.length, 2);
      // t=2.0 collapses onto the existing endpoint at t=1.0 (within eps).
      expect(out.last.t, 1.0);
      expect(out.last.intensity, 0.0);
    });
  });

  group('EmotionalArcOps.movePoint', () {
    test('first endpoint t stays at 0', () {
      final pts = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.1),
        EmotionalArcPoint(t: 0.5, intensity: 0.5),
        EmotionalArcPoint(t: 1.0, intensity: 0.9),
      ]);
      final out = EmotionalArcOps.movePoint(pts, 0, 0.4, 0.8);
      expect(out.first.t, 0.0);
      expect(out.first.intensity, 0.8);
    });

    test('last endpoint t stays at 1', () {
      final pts = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.1),
        EmotionalArcPoint(t: 1.0, intensity: 0.9),
      ]);
      final out = EmotionalArcOps.movePoint(pts, 1, 0.5, 0.5);
      expect(out.last.t, 1.0);
      expect(out.last.intensity, 0.5);
    });

    test('interior point cannot cross neighbours', () {
      final pts = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.1),
        EmotionalArcPoint(t: 0.3, intensity: 0.5),
        EmotionalArcPoint(t: 0.7, intensity: 0.5),
        EmotionalArcPoint(t: 1.0, intensity: 0.9),
      ]);
      // Try to drag middle-1 way past middle-2.
      final out = EmotionalArcOps.movePoint(pts, 1, 0.95, 0.5);
      expect(out[1].t, lessThan(out[2].t));
      // ... and the other direction.
      final out2 = EmotionalArcOps.movePoint(out, 2, -0.5, 0.5);
      expect(out2[2].t, greaterThan(out2[1].t));
    });

    test('out-of-range index is a no-op', () {
      final pts = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.0),
        EmotionalArcPoint(t: 1.0, intensity: 1.0),
      ]);
      final out = EmotionalArcOps.movePoint(pts, 99, 0.5, 0.5);
      expect(out, pts);
    });
  });

  group('EmotionalArcOps.deletePoint', () {
    test('cannot delete first endpoint', () {
      final pts = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.1),
        EmotionalArcPoint(t: 0.5, intensity: 0.5),
        EmotionalArcPoint(t: 1.0, intensity: 0.9),
      ]);
      final out = EmotionalArcOps.deletePoint(pts, 0);
      expect(out, pts);
    });

    test('cannot delete last endpoint', () {
      final pts = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.1),
        EmotionalArcPoint(t: 1.0, intensity: 0.9),
      ]);
      final out = EmotionalArcOps.deletePoint(pts, pts.length - 1);
      expect(out, pts);
    });

    test('deletes interior point', () {
      final pts = EmotionalArcOps.normalize(const [
        EmotionalArcPoint(t: 0.0, intensity: 0.1),
        EmotionalArcPoint(t: 0.4, intensity: 0.5),
        EmotionalArcPoint(t: 0.7, intensity: 0.9),
        EmotionalArcPoint(t: 1.0, intensity: 0.5),
      ]);
      final out = EmotionalArcOps.deletePoint(pts, 1);
      expect(out.length, 3);
      expect(out.any((p) => p.t == 0.4), isFalse);
    });
  });

  group('EmotionalArcOps.hitTest', () {
    test('returns -1 when nothing within threshold', () {
      final pts = const [
        EmotionalArcPoint(t: 0.0, intensity: 0.0),
        EmotionalArcPoint(t: 1.0, intensity: 1.0),
      ];
      final hit = EmotionalArcOps.hitTest(
        pts,
        0.5,
        0.5,
        tScale: 400,
        intensityScale: 200,
      );
      expect(hit, -1);
    });

    test('returns nearest within threshold', () {
      final pts = const [
        EmotionalArcPoint(t: 0.0, intensity: 0.0),
        EmotionalArcPoint(t: 0.5, intensity: 0.5),
        EmotionalArcPoint(t: 1.0, intensity: 1.0),
      ];
      // 5px from middle point at 400×200 canvas → within threshold.
      final hit = EmotionalArcOps.hitTest(
        pts,
        0.5 + 5 / 400,
        0.5,
        tScale: 400,
        intensityScale: 200,
      );
      expect(hit, 1);
    });
  });

  group('EmotionalArcOps.sample (Rust parity)', () {
    test('matches Rust EmotionalArc::sample on canonical inputs', () {
      // Same test case as `rf-generative::request::arc_sample_clamps_and_interpolates`.
      final pts = const [
        EmotionalArcPoint(t: 0.0, intensity: 0.0),
        EmotionalArcPoint(t: 0.5, intensity: 1.0),
        EmotionalArcPoint(t: 1.0, intensity: 0.5),
      ];
      expect(EmotionalArcOps.sample(pts, 0.0), closeTo(0.0, 1e-6));
      expect(EmotionalArcOps.sample(pts, 0.25), closeTo(0.5, 1e-6));
      expect(EmotionalArcOps.sample(pts, 0.5), closeTo(1.0, 1e-6));
      expect(EmotionalArcOps.sample(pts, 0.75), closeTo(0.75, 1e-6));
      expect(EmotionalArcOps.sample(pts, 1.0), closeTo(0.5, 1e-6));
      expect(EmotionalArcOps.sample(pts, -1.0), closeTo(0.0, 1e-6));
      expect(EmotionalArcOps.sample(pts, 2.0), closeTo(0.5, 1e-6));
    });

    test('empty input yields 0.0', () {
      expect(EmotionalArcOps.sample(const [], 0.5), 0.0);
    });
  });

  group('EmotionalArcPreset.build', () {
    test('every preset starts at t=0 and ends at t=1', () {
      for (final preset in EmotionalArcPreset.values) {
        final arc = preset.build();
        expect(arc.points.first.t, 0.0, reason: 'preset=$preset start');
        expect(arc.points.last.t, 1.0, reason: 'preset=$preset end');
      }
    });

    test('every preset has monotonic t and in-range intensity', () {
      for (final preset in EmotionalArcPreset.values) {
        final arc = preset.build();
        for (var i = 1; i < arc.points.length; i++) {
          expect(arc.points[i].t,
              greaterThanOrEqualTo(arc.points[i - 1].t),
              reason: 'preset=$preset monotonic at $i');
        }
        for (final p in arc.points) {
          expect(p.intensity, inInclusiveRange(0.0, 1.0),
              reason: 'preset=$preset intensity');
        }
      }
    });

    test('crescendo strictly rises', () {
      final arc = EmotionalArcPreset.crescendo.build();
      expect(arc.points.last.intensity,
          greaterThan(arc.points.first.intensity));
    });

    test('decrescendo strictly falls', () {
      final arc = EmotionalArcPreset.decrescendo.build();
      expect(arc.points.last.intensity,
          lessThan(arc.points.first.intensity));
    });

    test('spike has interior peak', () {
      final arc = EmotionalArcPreset.spike.build();
      final peak = arc.points
          .map((p) => p.intensity)
          .reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(arc.points.first.intensity));
      expect(peak, greaterThan(arc.points.last.intensity));
    });

    test('dip has interior trough', () {
      final arc = EmotionalArcPreset.dip.build();
      final trough = arc.points
          .map((p) => p.intensity)
          .reduce((a, b) => a < b ? a : b);
      expect(trough, lessThan(arc.points.first.intensity));
      expect(trough, lessThan(arc.points.last.intensity));
    });
  });

  group('EmotionalArcEditor widget', () {
    testWidgets('builds without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 240,
              child: EmotionalArcEditor(
                initial: EmotionalArcPreset.crescendo.build(),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(EmotionalArcEditor), findsOneWidget);
      expect(find.text('Crescendo'), findsOneWidget); // preset chip
      expect(find.textContaining('points'), findsWidgets);
    });

    testWidgets('preset chip tap fires onChanged with new arc',
        (tester) async {
      EmotionalArc? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 240,
              child: EmotionalArcEditor(
                initial: EmotionalArcPreset.flat.build(),
                onChanged: (arc) => captured = arc,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Spike'));
      await tester.pump();
      expect(captured, isNotNull);
      // Spike preset has 5 points (after normalize keeps existing endpoints).
      expect(captured!.points.length, greaterThanOrEqualTo(5));
    });

    testWidgets('hides preset strip when showPresets=false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: EmotionalArcEditor(
                initial: EmotionalArcPreset.flat.build(),
                showPresets: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Crescendo'), findsNothing);
    });
  });
}
