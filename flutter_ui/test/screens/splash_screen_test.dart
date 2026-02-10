@Tags(['screen'])
// SplashScreen integration tests
//
// Tests the splash screen UI rendering, animation states,
// loading messages, progress bar, and error handling.
// No FFI dependency — SplashScreen is a pure UI widget.
//
// Note: SplashScreen has 4 AnimationControllers and uses Future.delayed
// in _startAnimations(), so we need sufficient pump time to consume timers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/screens/splash_screen.dart';

void main() {
  group('SplashScreen', () {
    testWidgets('renders without error', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
          ),
        ),
      );

      // Pump enough to consume all Future.delayed timers in _startAnimations
      // (200ms + 600ms + 400ms = 1200ms total, plus animation durations)
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows FluxForge Studio text', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
          ),
        ),
      );

      // Pump enough for text animations to complete
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('FluxForge Studio'), findsOneWidget);
    });

    testWidgets('shows default loading message when none provided',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Initializing...'), findsOneWidget);
    });

    testWidgets('shows custom loading message when provided',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            loadingMessage: 'Loading audio engine...',
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Loading audio engine...'), findsOneWidget);
      expect(find.text('Initializing...'), findsNothing);
    });

    testWidgets('shows progress bar when progress is provided',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            progress: 0.5,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      // FractionallySizedBox is used for the progress indicator
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });

    testWidgets('shows error state when hasError is true',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            hasError: true,
            errorMessage: 'Engine failed to load',
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Initialization Failed'), findsOneWidget);
      expect(find.text('Engine failed to load'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows retry button when onRetry is provided',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            hasError: true,
            onRetry: () {},
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('does not show retry button when onRetry is null',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            hasError: true,
            onRetry: null,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('retry button calls onRetry callback',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            hasError: true,
            errorMessage: 'Test error',
            onRetry: () => retried = true,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      // The Retry TextButton may be partially obscured by the version text
      // in the Stack. Use warnIfMissed: false since we know the button exists.
      final retryButton = find.widgetWithText(TextButton, 'Retry');
      expect(retryButton, findsOneWidget);
      await tester.tap(retryButton, warnIfMissed: false);
      await tester.pump();

      expect(retried, isTrue);
    });

    testWidgets('shows version text', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('v0.1.0'), findsOneWidget);
    });
  });
}
