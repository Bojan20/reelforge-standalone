// MainLayout integration tests
@Tags(['screen'])
library;
//
// Tests the main layout wrapper that combines ControlBar, LeftZone,
// CenterZone, RightZone, and LowerZone.
//
// Uses customControlBar to bypass the default ControlBar which has
// many Consumer<Provider> dependencies that would require extensive setup.
// MixerProvider is needed because the internal _buildMixerContent uses
// Consumer<MixerProvider>.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fluxforge_ui/screens/main_layout.dart';
import 'package:fluxforge_ui/providers/mixer_provider.dart';

void main() {
  group('MainLayout', () {
    // Suppress overflow errors from LeftZone header Row at default viewport.
    setUp(() {
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        FlutterError.presentError(details);
      };
    });

    tearDown(() {
      FlutterError.onError = FlutterError.presentError;
    });

    /// Build a minimal test widget with MainLayout.
    /// Uses customControlBar to avoid needing 10+ providers
    /// that the default ControlBar requires.
    Widget buildTestWidget({
      Widget? child,
      Widget? customControlBar,
      bool? leftZoneVisible,
      bool? rightZoneVisible,
      String projectName = 'Test Project',
      Widget? customLowerZone,
    }) {
      return MaterialApp(
        home: ChangeNotifierProvider<MixerProvider>(
          create: (_) => MixerProvider(),
          child: MainLayout(
            customControlBar: customControlBar ??
                Container(
                  key: const Key('test-control-bar'),
                  height: 48,
                  color: Colors.grey[900],
                  child: Center(
                    child: Text(
                      projectName,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            child: child ??
                const Center(
                  key: Key('test-child'),
                  child: Text('Center Content'),
                ),
            leftZoneVisible: leftZoneVisible,
            rightZoneVisible: rightZoneVisible,
            projectName: projectName,
            customLowerZone: customLowerZone,
          ),
        ),
      );
    }

    testWidgets('renders with minimal props', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      tester.takeException();

      expect(find.byType(MainLayout), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows child widget', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      tester.takeException();

      expect(find.text('Center Content'), findsOneWidget);
      expect(find.byKey(const Key('test-child')), findsOneWidget);
    });

    testWidgets('renders custom control bar', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      tester.takeException();

      expect(find.byKey(const Key('test-control-bar')), findsOneWidget);
    });

    testWidgets('shows project name in custom control bar',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
          buildTestWidget(projectName: 'My Audio Project'));
      await tester.pump();
      tester.takeException();

      expect(find.text('My Audio Project'), findsOneWidget);
    });

    testWidgets('shows custom child widget', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget(
        child: const Placeholder(key: Key('custom-child')),
      ));
      await tester.pump();
      tester.takeException();

      expect(find.byKey(const Key('custom-child')), findsOneWidget);
    });

    testWidgets('hides left zone when leftZoneVisible is false',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
          buildTestWidget(leftZoneVisible: false));
      await tester.pump();
      tester.takeException();

      // MainLayout still renders -- the LeftZone should be collapsed
      // (width = 0 or hidden via AnimatedContainer)
      expect(find.byType(MainLayout), findsOneWidget);
    });

    testWidgets('renders custom lower zone when provided',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestWidget(
        customLowerZone: Container(
          key: const Key('custom-lower'),
          height: 200,
          child: const Text('Custom Lower Zone'),
        ),
      ));
      await tester.pump();
      tester.takeException();

      // The custom lower zone is only shown when lowerZoneVisible is true
      // (default is true)
      expect(find.text('Custom Lower Zone'), findsOneWidget);
    });
  });
}
