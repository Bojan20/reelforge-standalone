/// FX Chain Panel Tests (P0.4)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/process/fx_chain_panel.dart';
import 'package:fluxforge_ui/providers/dsp_chain_provider.dart';

void main() {
  group('FxChainPanel', () {
    testWidgets('shows chain header when no track selected (defaults to track 0)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FxChainPanel(selectedTrackId: null),
          ),
        ),
      );
      // FxChainPanel uses selectedTrackId ?? 0, so it always renders the chain view
      // Use pump(Duration) instead of pumpAndSettle because
      // ProcessorCpuMeterInline has a Timer.periodic(100ms) that never settles.
      await tester.pump(const Duration(milliseconds: 500));

      // It renders "FX CHAIN — Track 0" when selectedTrackId is null
      expect(find.text('FX CHAIN — Track 0'), findsOneWidget);
      expect(find.text('INPUT'), findsOneWidget);
      expect(find.text('OUTPUT'), findsOneWidget);
    });

    testWidgets('shows chain when track selected', (tester) async {
      const trackId = 10;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FxChainPanel(selectedTrackId: trackId),
          ),
        ),
      );
      // Use pump(Duration) instead of pumpAndSettle because
      // ProcessorCpuMeterInline has a Timer.periodic(100ms) that never settles.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('FX CHAIN — Track 10'), findsOneWidget);
      expect(find.text('INPUT'), findsOneWidget);
      expect(find.text('OUTPUT'), findsOneWidget);
    });

    testWidgets('shows empty placeholder when no processors', (tester) async {
      const trackId = 11;
      DspChainProvider.instance.clearChain(trackId);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FxChainPanel(selectedTrackId: trackId),
          ),
        ),
      );
      // Use pump(Duration) instead of pumpAndSettle because
      // ProcessorCpuMeterInline has a Timer.periodic(100ms) that never settles.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Drop here\nor click Add'), findsOneWidget);
    });
  });
}
