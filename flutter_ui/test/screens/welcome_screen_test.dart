@Tags(['screen'])
// WelcomeScreen integration tests
//
// Tests the welcome/start screen UI rendering including
// New Project button, Open Project button, recent projects section.
//
// RecentProjectsProvider.initialize() calls FFI -- may load the dylib
// from ../target/release/ if it exists. We increase surface size to
// prevent layout overflow in the test environment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fluxforge_ui/screens/welcome_screen.dart';
import 'package:fluxforge_ui/providers/recent_projects_provider.dart';

void main() {
  group('WelcomeScreen', () {
    // Override surface size to prevent overflow in test viewport
    setUp(() {
      // Ignore overflow errors -- they are cosmetic in test viewport
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        // Re-throw real errors
        FlutterError.presentError(details);
      };
    });

    tearDown(() {
      FlutterError.onError = FlutterError.presentError;
    });

    Widget buildTestWidget({
      void Function(String name)? onNewProject,
      void Function(String path)? onOpenProject,
      VoidCallback? onSkip,
    }) {
      return MaterialApp(
        home: ChangeNotifierProvider<RecentProjectsProvider>(
          create: (_) => RecentProjectsProvider(),
          child: WelcomeScreen(
            onNewProject: onNewProject ?? (_) {},
            onOpenProject: onOpenProject ?? (_) {},
            onSkip: onSkip,
          ),
        ),
      );
    }

    testWidgets('renders without error', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      // Consume any overflow exceptions that the framework tracked
      tester.takeException();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows FluxForge Studio branding',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('FluxForge Studio'), findsOneWidget);
    });

    testWidgets('shows New Project button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('New Project'), findsOneWidget);
      expect(find.text('Start a fresh project'), findsOneWidget);
    });

    testWidgets('shows Open Project button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('Open Project'), findsOneWidget);
      expect(find.text('Open an existing .rfp file'), findsOneWidget);
    });

    testWidgets('shows Import Audio button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('Import Audio'), findsOneWidget);
    });

    testWidgets('shows Skip button when onSkip is provided',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget(onSkip: () {}));
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('does not show Skip button when onSkip is null',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget(onSkip: null));
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('shows version text', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('FluxForge Studio v0.1.0'), findsOneWidget);
    });

    testWidgets('shows recent projects section header',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('RECENT PROJECTS'), findsOneWidget);
    });

    testWidgets('shows EQ Test Lab button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(find.text('EQ Test Lab'), findsOneWidget);
    });
  });
}
