/// FAZA 4.4 — `PredictiveConfidenceBadge` widget tests.
///
/// Pokriva:
/// - null candidate → SizedBox.shrink (no badge)
/// - unclassified candidate (< 0.25 confidence) → no badge
/// - high tier rendering (🎯 emoji + green accent)
/// - mid tier rendering (👍 emoji + yellow accent)
/// - low tier rendering (🤔 emoji + orange accent)
/// - mismatch stageHint → "↪" prefix + red ≠ tag
/// - long stage name clamping (24 char limit)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/slot_lab/spectral_dna_classifier.dart';
import 'package:fluxforge_ui/widgets/predictive/predictive_confidence_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('PredictiveConfidenceBadge — visibility', () {
    testWidgets('null candidate → SizedBox.shrink', (tester) async {
      await tester.pumpWidget(_wrap(
        const PredictiveConfidenceBadge(candidate: null),
      ));
      // No text should be visible (badge collapsed).
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('unclassified (0.10) → no badge', (tester) async {
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'REEL_STOP',
            confidence: 0.10,
          ),
        ),
      ));
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('PredictiveConfidenceBadge — tier rendering', () {
    testWidgets('high tier (0.87) → 🎯 + HIGH label', (tester) async {
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'REEL_STOP',
            confidence: 0.87,
          ),
        ),
      ));
      expect(find.text('🎯'), findsOneWidget);
      expect(find.text('87%'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('reel_stop'), findsOneWidget);
    });

    testWidgets('mid tier (0.62) → 👍 + MID label', (tester) async {
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'WIN_BIG',
            confidence: 0.62,
          ),
        ),
      ));
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('MID'), findsOneWidget);
    });

    testWidgets('low tier (0.38) → 🤔 + LOW label', (tester) async {
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'UI_CLICK',
            confidence: 0.38,
          ),
        ),
      ));
      expect(find.text('🤔'), findsOneWidget);
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
    });
  });

  group('PredictiveConfidenceBadge — mismatch styling', () {
    testWidgets(
        'stageHint != candidate.stage → ↪ prefix + ≠ mismatch tag',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'WIN_BIG',
            confidence: 0.40, // already halved by predictFor mismatch logic
          ),
          stageHint: 'REEL_STOP_3',
        ),
      ));
      // ↪ replaces tier icon when mismatch
      expect(find.text('↪'), findsOneWidget);
      // Red ≠ tag with short hint
      expect(find.textContaining('≠'), findsOneWidget);
    });

    testWidgets('matching stageHint → tier icon (no ↪)', (tester) async {
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'REEL_STOP_3',
            confidence: 0.80,
          ),
          stageHint: 'REEL_STOP_3',
        ),
      ));
      expect(find.text('🎯'), findsOneWidget);
      expect(find.text('↪'), findsNothing);
    });

    testWidgets('case-insensitive stage match', (tester) async {
      // candidate.stage may differ in case from stageHint
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'reel_stop',
            confidence: 0.80,
          ),
          stageHint: 'REEL_STOP',
        ),
      ));
      // Should be treated as MATCH, not mismatch.
      expect(find.text('↪'), findsNothing);
      expect(find.text('🎯'), findsOneWidget);
    });
  });

  group('PredictiveConfidenceBadge — long stage clamping', () {
    testWidgets('stage > 24 chars truncated with ellipsis', (tester) async {
      await tester.pumpWidget(_wrap(
        PredictiveConfidenceBadge(
          candidate: StageCandidate(
            stage: 'VERY_LONG_STAGE_NAME_THAT_EXCEEDS_LIMIT_BY_FAR',
            confidence: 0.85,
          ),
        ),
      ));
      // Truncated to 23 + ellipsis = 24 chars
      expect(find.textContaining('…'), findsOneWidget);
    });
  });
}
