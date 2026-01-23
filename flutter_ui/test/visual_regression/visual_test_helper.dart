// Visual Regression Test Helper
//
// Provides utilities for pixel-perfect comparison of Flutter widgets.
// Golden images are stored in test/visual_regression/goldens/

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// Configuration for visual regression tests
class VisualTestConfig {
  /// Directory where golden images are stored
  final String goldenDir;

  /// Maximum allowed pixel difference (0.0 - 1.0)
  final double maxDiffPercent;

  /// Whether to update golden images instead of comparing
  final bool updateGoldens;

  /// Size for the test surface
  final Size surfaceSize;

  /// Device pixel ratio
  final double pixelRatio;

  const VisualTestConfig({
    this.goldenDir = 'test/visual_regression/goldens',
    this.maxDiffPercent = 0.01, // 1% tolerance
    this.updateGoldens = false,
    this.surfaceSize = const Size(800, 600),
    this.pixelRatio = 1.0,
  });

  /// Check if CI environment (from env var or argument)
  static bool get isCI =>
      Platform.environment['CI'] == 'true' ||
      Platform.environment['GITHUB_ACTIONS'] == 'true';

  /// Config for CI (stricter)
  static const VisualTestConfig ci = VisualTestConfig(
    maxDiffPercent: 0.001, // 0.1%
    updateGoldens: false,
  );

  /// Config for local development (more lenient)
  static const VisualTestConfig local = VisualTestConfig(
    maxDiffPercent: 0.05, // 5%
    updateGoldens: false,
  );

  /// Config for updating golden images
  static const VisualTestConfig update = VisualTestConfig(
    updateGoldens: true,
  );
}

/// Result of a visual comparison
class VisualCompareResult {
  final String testName;
  final bool passed;
  final double diffPercent;
  final int diffPixels;
  final int totalPixels;
  final String? goldenPath;
  final String? actualPath;
  final String? diffPath;
  final String? errorMessage;

  const VisualCompareResult({
    required this.testName,
    required this.passed,
    required this.diffPercent,
    required this.diffPixels,
    required this.totalPixels,
    this.goldenPath,
    this.actualPath,
    this.diffPath,
    this.errorMessage,
  });

  @override
  String toString() {
    if (passed) {
      return 'PASS: $testName (${(diffPercent * 100).toStringAsFixed(3)}% diff)';
    } else {
      return 'FAIL: $testName - ${errorMessage ?? "${(diffPercent * 100).toStringAsFixed(3)}% diff ($diffPixels pixels)"}';
    }
  }
}

/// Visual regression test helper
class VisualTestHelper {
  final VisualTestConfig config;

  VisualTestHelper({this.config = const VisualTestConfig()});

  /// Take a golden snapshot test
  ///
  /// Usage:
  /// ```dart
  /// testWidgets('MyWidget golden test', (tester) async {
  ///   await tester.pumpWidget(MyWidget());
  ///   await visualHelper.expectGolden(tester, 'my_widget');
  /// });
  /// ```
  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    Finder? finder,
    VisualTestConfig? configOverride,
  }) async {
    final testConfig = configOverride ?? config;
    final goldenPath = path.join(testConfig.goldenDir, '$name.png');

    // Use Flutter's built-in golden test functionality
    if (finder != null) {
      await expectLater(
        finder,
        matchesGoldenFile(goldenPath),
      );
    } else {
      await expectLater(
        find.byType(MaterialApp).first.evaluate().isNotEmpty
            ? find.byType(MaterialApp)
            : find.byType(WidgetsApp).first.evaluate().isNotEmpty
                ? find.byType(WidgetsApp)
                : find.byType(Directionality),
        matchesGoldenFile(goldenPath),
      );
    }
  }

  /// Wrap a widget for golden testing with standard test scaffold
  static Widget wrapForGolden(
    Widget child, {
    Size size = const Size(800, 600),
    ThemeData? theme,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? _defaultDarkTheme(),
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    );
  }

  /// Default dark theme matching FluxForge
  static ThemeData _defaultDarkTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF0A0A0C),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4A9EFF),
        secondary: Color(0xFFFF9040),
        surface: Color(0xFF1A1A20),
        error: Color(0xFFFF4060),
      ),
    );
  }
}

/// Extension for easier golden testing
extension GoldenTestExtension on WidgetTester {
  /// Pump widget wrapped for golden testing
  Future<void> pumpGolden(
    Widget widget, {
    Size size = const Size(800, 600),
    ThemeData? theme,
  }) async {
    await binding.setSurfaceSize(size);
    await pumpWidget(VisualTestHelper.wrapForGolden(
      widget,
      size: size,
      theme: theme,
    ));
    await pumpAndSettle();
  }

  /// Match golden with default config
  Future<void> expectGolden(String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }
}

/// Test tags for organizing visual tests
class VisualTestTags {
  static const String all = 'visual';
  static const String widgets = 'visual-widgets';
  static const String screens = 'visual-screens';
  static const String components = 'visual-components';
}

/// Base class for visual regression test suites
abstract class VisualTestSuite {
  /// Name of this test suite
  String get suiteName;

  /// Default config for this suite
  VisualTestConfig get config => const VisualTestConfig();

  /// Run all visual tests in this suite
  void runTests();

  /// Helper for creating golden tests
  void goldenTest(
    String description,
    Widget Function() widgetBuilder, {
    Size size = const Size(800, 600),
    ThemeData? theme,
    String? goldenName,
  }) {
    testWidgets(
      description,
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(VisualTestHelper.wrapForGolden(
          widgetBuilder(),
          size: size,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        final name = goldenName ?? _sanitizeName(description);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$suiteName/$name.png'),
        );
      },
      tags: [VisualTestTags.all, VisualTestTags.widgets],
    );
  }

  String _sanitizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

/// Report generator for visual regression tests
class VisualTestReport {
  final List<VisualCompareResult> results = [];

  void addResult(VisualCompareResult result) {
    results.add(result);
  }

  int get totalTests => results.length;
  int get passedTests => results.where((r) => r.passed).length;
  int get failedTests => results.where((r) => !r.passed).length;

  double get passRate =>
      totalTests == 0 ? 1.0 : passedTests / totalTests;

  bool get allPassed => failedTests == 0;

  String generateMarkdown() {
    final buffer = StringBuffer();

    buffer.writeln('# Visual Regression Test Report');
    buffer.writeln();
    buffer.writeln('## Summary');
    buffer.writeln();
    buffer.writeln('| Metric | Value |');
    buffer.writeln('|--------|-------|');
    buffer.writeln('| Total | $totalTests |');
    buffer.writeln('| Passed | $passedTests |');
    buffer.writeln('| Failed | $failedTests |');
    buffer.writeln('| Pass Rate | ${(passRate * 100).toStringAsFixed(1)}% |');
    buffer.writeln();

    if (failedTests > 0) {
      buffer.writeln('## Failed Tests');
      buffer.writeln();
      for (final result in results.where((r) => !r.passed)) {
        buffer.writeln('### ${result.testName}');
        buffer.writeln();
        buffer.writeln('- Diff: ${(result.diffPercent * 100).toStringAsFixed(3)}%');
        buffer.writeln('- Pixels: ${result.diffPixels} / ${result.totalPixels}');
        if (result.errorMessage != null) {
          buffer.writeln('- Error: ${result.errorMessage}');
        }
        buffer.writeln();
      }
    }

    buffer.writeln('## All Results');
    buffer.writeln();
    buffer.writeln('| Test | Status | Diff |');
    buffer.writeln('|------|--------|------|');
    for (final result in results) {
      final status = result.passed ? '✅' : '❌';
      final diff = '${(result.diffPercent * 100).toStringAsFixed(3)}%';
      buffer.writeln('| ${result.testName} | $status | $diff |');
    }

    return buffer.toString();
  }

  String generateJson() {
    return '''
{
  "summary": {
    "total": $totalTests,
    "passed": $passedTests,
    "failed": $failedTests,
    "passRate": $passRate
  },
  "results": [
    ${results.map((r) => '''
    {
      "name": "${r.testName}",
      "passed": ${r.passed},
      "diffPercent": ${r.diffPercent},
      "diffPixels": ${r.diffPixels},
      "totalPixels": ${r.totalPixels}
    }''').join(',\n')}
  ]
}
''';
  }
}
