import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxforge_ui/widgets/slot_lab/onboarding_wizard.dart';

void main() {
  group('OnboardingWizard', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('displays welcome step initially', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OnboardingWizard()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome to SlotLab'), findsOneWidget);
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('navigates to next step on button tap', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OnboardingWizard()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Setup Your Game'), findsOneWidget);
      expect(find.text('Step 2 of 5'), findsOneWidget);
    });

    testWidgets('can navigate back to previous step', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OnboardingWizard()),
        ),
      );
      await tester.pumpAndSettle();

      // Go to step 2
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 5'), findsOneWidget);

      // Go back to step 1
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('skip button triggers onSkip callback', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool skipped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnboardingWizard(onSkip: () => skipped = true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Go to step 2 (step 1 has no skip button)
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip Tutorial'));
      await tester.pumpAndSettle();

      expect(skipped, isTrue);
    });

    testWidgets('displays setup step with two options', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OnboardingWizard()),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to setup step
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Import GDD'), findsOneWidget);
      expect(find.text('Use Template'), findsOneWidget);
      expect(find.text('OR'), findsOneWidget);
    });

    test('hasCompletedOnboarding returns false by default', () async {
      SharedPreferences.setMockInitialValues({});
      final completed = await OnboardingWizard.hasCompletedOnboarding();
      expect(completed, isFalse);
    });

    test('markOnboardingCompleted sets preference', () async {
      SharedPreferences.setMockInitialValues({});
      await OnboardingWizard.markOnboardingCompleted();
      final completed = await OnboardingWizard.hasCompletedOnboarding();
      expect(completed, isTrue);
    });

    test('resetOnboarding clears preference', () async {
      SharedPreferences.setMockInitialValues({'slotlab_onboarding_completed': true});
      await OnboardingWizard.resetOnboarding();
      final completed = await OnboardingWizard.hasCompletedOnboarding();
      expect(completed, isFalse);
    });
  });

  group('OnboardingResult', () {
    test('creates with default values', () {
      const result = OnboardingResult(completed: true);
      expect(result.completed, isTrue);
      expect(result.usedTemplate, isFalse);
      expect(result.templateId, isNull);
      expect(result.importedGdd, isFalse);
      expect(result.symbolsAssigned, 0);
      expect(result.spinsCompleted, 0);
    });

    test('creates with custom values', () {
      const result = OnboardingResult(
        completed: true,
        usedTemplate: true,
        templateId: 'classic_5x3',
        importedGdd: false,
        symbolsAssigned: 5,
        spinsCompleted: 3,
      );

      expect(result.completed, isTrue);
      expect(result.usedTemplate, isTrue);
      expect(result.templateId, 'classic_5x3');
      expect(result.symbolsAssigned, 5);
      expect(result.spinsCompleted, 3);
    });
  });

  group('OnboardingStep', () {
    test('creates with required fields', () {
      final step = OnboardingStep(
        title: 'Test Step',
        subtitle: 'Test subtitle',
        icon: Icons.star,
        contentBuilder: (_) => const SizedBox(),
      );

      expect(step.title, 'Test Step');
      expect(step.subtitle, 'Test subtitle');
      expect(step.icon, Icons.star);
      expect(step.canSkip, isTrue); // default
    });

    test('canSkip can be set to false', () {
      final step = OnboardingStep(
        title: 'Test',
        subtitle: 'Test',
        icon: Icons.star,
        contentBuilder: (_) => const SizedBox(),
        canSkip: false,
      );

      expect(step.canSkip, isFalse);
    });
  });
}
