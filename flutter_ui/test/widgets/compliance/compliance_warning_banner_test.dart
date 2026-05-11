/// FAZA 4.2.4 — `ComplianceWarningBanner` widget tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/compliance/audio_compliance_guard.dart';
import 'package:fluxforge_ui/widgets/compliance/compliance_warning_banner.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('ComplianceWarningBanner — visibility', () {
    testWidgets('no warnings → SizedBox.shrink', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_wrap(
        ComplianceWarningBanner(guard: guard),
      ));
      // Empty state — no banner content.
      expect(find.text('BLOCK'), findsNothing);
      expect(find.text('WARN'), findsNothing);
      expect(find.text('INFO'), findsNothing);
      await guard.dispose();
    });
  });

  group('ComplianceWarningBanner — tier rendering', () {
    testWidgets('BLOCK severity → red BLOCK label + rule id', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_wrap(
        ComplianceWarningBanner(guard: guard),
      ));

      guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      await tester.pump(); // schedule rebuild
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('BLOCK'), findsOneWidget);
      expect(find.text('· ldw_disguise'), findsOneWidget);
      expect(find.text('UKGC'), findsOneWidget);
      await guard.dispose();
    });

    testWidgets('WARN severity → yellow WARN label', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_wrap(
        ComplianceWarningBanner(guard: guard),
      ));

      guard.validate(
        stage: 'WIN_BIG',
        win: 100,
        bet: 1.0,
        integratedLufs: -10.0,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('WARN'), findsOneWidget);
      expect(find.text('· celebration_lufs'), findsOneWidget);
      await guard.dispose();
    });
  });

  group('ComplianceWarningBanner — dismiss', () {
    testWidgets('close icon → banner hides', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_wrap(
        ComplianceWarningBanner(guard: guard),
      ));

      guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('BLOCK'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('BLOCK'), findsNothing);

      await guard.dispose();
    });

    testWidgets('WARN auto-dismisses after 6s', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_wrap(
        ComplianceWarningBanner(guard: guard),
      ));

      guard.validate(
        stage: 'WIN_BIG',
        win: 100,
        bet: 1.0,
        integratedLufs: -10.0,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('WARN'), findsOneWidget);

      // Advance time past 6s auto-dismiss.
      await tester.pump(const Duration(milliseconds: 6500));
      expect(find.text('WARN'), findsNothing);

      await guard.dispose();
    });

    testWidgets('BLOCK does NOT auto-dismiss', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_wrap(
        ComplianceWarningBanner(guard: guard),
      ));

      guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('BLOCK'), findsOneWidget);

      // After long delay, BLOCK remains.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('BLOCK'), findsOneWidget);

      await guard.dispose();
    });
  });

  group('ComplianceWarningBanner — replacement', () {
    testWidgets('new warning replaces active warning', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_wrap(
        ComplianceWarningBanner(guard: guard),
      ));

      guard.validate(
        stage: 'WIN_BIG',
        win: 100,
        bet: 1.0,
        integratedLufs: -10.0,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('· celebration_lufs'), findsOneWidget);

      guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('· celebration_lufs'), findsNothing);
      expect(find.text('· ldw_disguise'), findsOneWidget);

      await guard.dispose();
    });
  });
}
