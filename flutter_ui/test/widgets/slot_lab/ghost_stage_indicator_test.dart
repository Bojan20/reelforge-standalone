/// Widget tests for GhostStageIndicator — NeuralBindOrb Phase 2 integration.
///
/// Verifies the ghost-stage chip that lives inside the NeuralBindOrb bottom
/// sheet and surfaces at-a-glance gap analysis after every auto-bind:
///
///   • Collapsed header shows bound/total + coverage% + gap count
///   • Expanded body shows per-category rows with missing stage names
///   • onMissingStageTap fires the callback with the correct stage key
///   • Full coverage toggles the emoji from 🫥 to ✨
///   • Compact mode renders without overflow in tight toolbars
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/stage_configuration_service.dart';
import 'package:fluxforge_ui/spatial/auto_spatial.dart';
import 'package:fluxforge_ui/widgets/slot_lab/ghost_stage_indicator.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

StageDefinition _stage(String name, StageCategory cat) => StageDefinition(
      name: name,
      category: cat,
      bus: SpatialBus.sfx,
    );

/// Minimal stage set: 3 spin, 2 win, 2 feature (7 total).
final _stages = [
  _stage('SPIN_START',    StageCategory.spin),
  _stage('SPIN_STOP',     StageCategory.spin),
  _stage('REEL_STOP_1',   StageCategory.spin),
  _stage('WIN_SMALL',     StageCategory.win),
  _stage('WIN_BIG',       StageCategory.win),
  _stage('FEATURE_START', StageCategory.feature),
  _stage('FEATURE_END',   StageCategory.feature),
];

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A12),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('GhostStageIndicator — collapsed header', () {
    testWidgets('shows 0/7 bound and 7 gaps when no assignments', (tester) async {
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {},
        stageSource: _stages,
      )));

      expect(find.textContaining('0 / 7 bound'), findsOneWidget);
      expect(find.textContaining('7 gaps'),     findsOneWidget);
      expect(find.textContaining('0%'),         findsOneWidget);
    });

    testWidgets('shows 3/7 bound, 4 gaps, 42%  with partial assignments', (tester) async {
      final assignments = {
        'SPIN_START': '/audio/spin_start.wav',
        'SPIN_STOP':  '/audio/spin_stop.wav',
        'WIN_SMALL':  '/audio/win_small.wav',
      };

      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: assignments,
        stageSource: _stages,
      )));

      expect(find.textContaining('3 / 7 bound'), findsOneWidget);
      expect(find.textContaining('4 gaps'),      findsOneWidget);
      // 3/7 = 42.857% → rounds to 43%.
      expect(find.textContaining('43%'),         findsOneWidget);
    });

    testWidgets('full coverage shows ✨ and no gap pill', (tester) async {
      final all = { for (final s in _stages) s.name: '/audio/${s.name}.wav' };

      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: all,
        stageSource: _stages,
      )));

      // Full coverage emoji
      expect(find.text('✨'), findsOneWidget);
      // 7/7 bound
      expect(find.textContaining('7 / 7 bound'), findsOneWidget);
      // 100% — using textContaining so we don't worry about suffix
      expect(find.textContaining('100%'), findsOneWidget);
      // No gap pill
      expect(find.textContaining('gaps'), findsNothing);
    });

    testWidgets('ghost emoji shown when not all stages are bound', (tester) async {
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {},
        stageSource: _stages,
      )));

      expect(find.text('🫥'), findsOneWidget);
    });
  });

  group('GhostStageIndicator — expand / collapse', () {
    testWidgets('starts collapsed — category rows not visible', (tester) async {
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {},
        stageSource: _stages,
      )));

      // Category labels are hidden until expanded.
      expect(find.textContaining('Spin'),    findsNothing);
      expect(find.textContaining('Win'),     findsNothing);
      expect(find.textContaining('Feature'), findsNothing);
    });

    testWidgets('tap header → expands and shows category rows', (tester) async {
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {},
        stageSource: _stages,
      )));

      // Tap the header (InkWell wraps the whole header row).
      await tester.tap(find.textContaining('0 / 7 bound'));
      await tester.pumpAndSettle();

      // Category rows must now be visible.
      expect(find.textContaining('Spin'),    findsOneWidget);
      expect(find.textContaining('Win'),     findsOneWidget);
      expect(find.textContaining('Feature'), findsOneWidget);
    });

    testWidgets('initiallyExpanded:true shows categories immediately', (tester) async {
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {},
        stageSource: _stages,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('Spin'),    findsOneWidget);
      expect(find.textContaining('Win'),     findsOneWidget);
      expect(find.textContaining('Feature'), findsOneWidget);
    });

    testWidgets('expand then collapse hides category rows again', (tester) async {
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {},
        stageSource: _stages,
      )));

      final header = find.textContaining('0 / 7 bound');
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.textContaining('Spin'), findsOneWidget);

      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.textContaining('Spin'), findsNothing);
    });
  });

  group('GhostStageIndicator — missing stage chips', () {
    testWidgets('expanded category shows missing stage names', (tester) async {
      // WIN_SMALL is bound; WIN_BIG is missing.
      final assignments = {'WIN_SMALL': '/audio/win_small.wav'};

      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: assignments,
        stageSource: _stages,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      // Tap the Win category row to expand it.
      await tester.tap(find.textContaining('Win'));
      await tester.pumpAndSettle();

      // Missing stage chip for WIN_BIG should appear.
      expect(find.text('WIN_BIG'), findsOneWidget);
      // WIN_SMALL was bound, should NOT appear in missing list.
      expect(find.text('WIN_SMALL'), findsNothing);
    });

    testWidgets('onMissingStageTap fires with correct stage key', (tester) async {
      String? tappedStage;
      final assignments = {'WIN_SMALL': '/audio/win_small.wav'};

      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: assignments,
        stageSource: _stages,
        initiallyExpanded: true,
        onMissingStageTap: (s) => tappedStage = s,
      )));
      await tester.pumpAndSettle();

      // Expand the Win category.
      await tester.tap(find.textContaining('Win'));
      await tester.pumpAndSettle();

      // Tap WIN_BIG chip.
      await tester.tap(find.text('WIN_BIG'));
      await tester.pump();

      expect(tappedStage, equals('WIN_BIG'));
    });

    testWidgets('fully bound category shows dash instead of missing count', (tester) async {
      // Bind ALL spin stages.
      final assignments = {
        'SPIN_START':  '/audio/s.wav',
        'SPIN_STOP':   '/audio/s.wav',
        'REEL_STOP_1': '/audio/s.wav',
      };

      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: assignments,
        stageSource: _stages,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      // "—" indicates zero missing for the Spin category.
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('GhostStageIndicator — compact mode', () {
    testWidgets('renders without overflow in 320×56 box', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A12),
          body: SizedBox(
            width: 320,
            height: 56,
            child: GhostStageIndicator(
              audioAssignments: const {},
              stageSource: _stages,
              compact: true,
            ),
          ),
        ),
      ));

      // No overflow exception.
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact widget still shows bound count', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A12),
          body: SizedBox(
            width: 400,
            height: 80,
            child: GhostStageIndicator(
              audioAssignments: {
                'SPIN_START': '/audio/s.wav',
                'WIN_BIG':    '/audio/w.wav',
              },
              stageSource: _stages,
              compact: true,
            ),
          ),
        ),
      ));

      expect(find.textContaining('2 / 7 bound'), findsOneWidget);
    });
  });

  group('GhostStageIndicator — edge cases', () {
    testWidgets('empty stage source renders without crash', (tester) async {
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {},
        stageSource: const [],
      )));

      // Should render OK (AudioGapReport.empty path).
      expect(tester.takeException(), isNull);
      expect(find.textContaining('0 / 0 bound'), findsOneWidget);
    });

    testWidgets('unknown assignment key is ignored gracefully', (tester) async {
      // ALIEN_STAGE is not in _stages → coverage stays 0.
      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: const {'ALIEN_STAGE': '/audio/alien.wav'},
        stageSource: _stages,
      )));

      expect(find.textContaining('0 / 7 bound'), findsOneWidget);
      expect(find.textContaining('7 gaps'),      findsOneWidget);
    });

    testWidgets('single missing stage shows singular gap label', (tester) async {
      // Bind 6 out of 7 → exactly 1 gap.
      final assignments = { for (final s in _stages.take(6)) s.name: '/a.wav' };

      await tester.pumpWidget(_wrap(GhostStageIndicator(
        audioAssignments: assignments,
        stageSource: _stages,
      )));

      // Singular "1 gap" not "1 gaps".
      expect(find.text('1 gap'), findsOneWidget);
    });
  });
}
