/// Wire-up integration test — verifies ComplianceWarningBanner is actually
/// present and reactive in the overlay layer after the 4.2.4 wire-up to
/// slot_lab_screen.dart.
///
/// We test the widget in isolation (not the full 15k-line slot_lab_screen)
/// to keep the test fast and avoid FFI/GetIt dependencies. The critical
/// invariant is: AudioComplianceGuard.validate() → banner appears in UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/compliance/audio_compliance_guard.dart';
import 'package:fluxforge_ui/widgets/compliance/compliance_warning_banner.dart';

// Simulates the overlay layer that slot_lab_screen adds:
//   Stack([mainContent, Positioned(top:0, right:0, child: ComplianceWarningBanner())])
Widget _buildScreenOverlay(AudioComplianceGuard guard) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          // Main screen content placeholder
          const ColoredBox(
            color: Color(0xFF0A0A0C),
            child: SizedBox.expand(),
          ),
          // Overlay: mirrors what slot_lab_screen adds in the final Stack
          Positioned(
            top: 0,
            right: 0,
            child: ComplianceWarningBanner(guard: guard),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('ComplianceWarningBanner wire-up — overlay integration', () {
    testWidgets('Banner is initially invisible (no LDW violation)', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_buildScreenOverlay(guard));

      // No warning emitted → banner must be invisible
      expect(find.text('BLOCK'), findsNothing);
      expect(find.text('WARN'), findsNothing);
      expect(find.byType(ComplianceWarningBanner), findsOneWidget);

      await guard.dispose();
    });

    testWidgets('LDW violation → BLOCK banner appears in overlay', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_buildScreenOverlay(guard));

      // Trigger LDW violation: WIN_BIG stage, win ≤ bet (UKGC LDW rule)
      guard.validate(stage: 'WIN_BIG', win: 0.90, bet: 1.00);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // BLOCK banner must be visible in the overlay
      expect(find.text('BLOCK'), findsOneWidget);
      expect(find.text('· ldw_disguise'), findsOneWidget);

      await guard.dispose();
    });

    testWidgets('BLOCK banner does not auto-dismiss (block severity rule)', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_buildScreenOverlay(guard));

      guard.validate(stage: 'WIN_MASSIVE', win: 0.50, bet: 1.00);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('BLOCK'), findsOneWidget);

      // Advance past info (4s) and warn (6s) auto-dismiss thresholds
      await tester.pump(const Duration(seconds: 8));
      // BLOCK must still be visible — no auto-dismiss
      expect(find.text('BLOCK'), findsOneWidget);

      await guard.dispose();
    });

    testWidgets('Manual dismiss hides banner', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_buildScreenOverlay(guard));

      guard.validate(stage: 'WIN_BIG', win: 0.50, bet: 1.00);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('BLOCK'), findsOneWidget);

      // Tap the close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('BLOCK'), findsNothing);

      await guard.dispose();
    });

    testWidgets('Second warning replaces first in overlay', (tester) async {
      final guard = AudioComplianceGuard();
      await tester.pumpWidget(_buildScreenOverlay(guard));

      guard.validate(stage: 'WIN_BIG', win: 0.50, bet: 1.00);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('BLOCK'), findsOneWidget);
      expect(find.text('· ldw_disguise'), findsOneWidget);

      // Trigger a different warning — banner replaces (not stacks)
      guard.validate(
        stage: 'WIN_MEGA',
        win: 0.99,
        bet: 1.00,
        integratedLufs: -10.0, // LUFS violation
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Still one banner, but now showing the new warning
      expect(find.byType(ComplianceWarningBanner), findsOneWidget);
      // Either BLOCK (LDW) or WARN/BLOCK (LUFS) — not two banners at once
      final blockCount = tester.widgetList(find.text('BLOCK')).length;
      final warnCount = tester.widgetList(find.text('WARN')).length;
      expect(blockCount + warnCount, equals(1));

      await guard.dispose();
    });
  });
}
