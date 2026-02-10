/// EditorModeProvider Tests
///
/// Tests mode switching, waveform generation counter,
/// config access, and keyboard shortcuts.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/editor_mode_provider.dart';

void main() {
  group('EditorMode enum', () {
    test('has two modes', () {
      expect(EditorMode.values.length, 2);
    });

    test('daw and middleware exist', () {
      expect(EditorMode.daw, isNotNull);
      expect(EditorMode.middleware, isNotNull);
    });
  });

  group('EditorModeConfig', () {
    test('DAW config has correct fields', () {
      final config = kModeConfigs[EditorMode.daw]!;
      expect(config.mode, EditorMode.daw);
      expect(config.name, 'DAW');
      expect(config.description, isNotEmpty);
      expect(config.icon, isNotEmpty);
      expect(config.shortcut, isNotEmpty);
    });

    test('Middleware config has correct fields', () {
      final config = kModeConfigs[EditorMode.middleware]!;
      expect(config.mode, EditorMode.middleware);
      expect(config.name, 'Events');
      expect(config.description, isNotEmpty);
      expect(config.icon, isNotEmpty);
      expect(config.shortcut, isNotEmpty);
    });

    test('all modes have configs', () {
      for (final mode in EditorMode.values) {
        expect(kModeConfigs[mode], isNotNull);
      }
    });
  });

  group('EditorModeProvider — initialization', () {
    test('defaults to DAW mode', () {
      final provider = EditorModeProvider();
      expect(provider.mode, EditorMode.daw);
      provider.dispose();
    });

    test('accepts custom initial mode', () {
      final provider = EditorModeProvider(initialMode: EditorMode.middleware);
      expect(provider.mode, EditorMode.middleware);
      provider.dispose();
    });

    test('config returns matching config', () {
      final provider = EditorModeProvider();
      expect(provider.config.mode, EditorMode.daw);
      provider.dispose();
    });

    test('modes list returns all configs', () {
      final provider = EditorModeProvider();
      expect(provider.modes.length, 2);
      provider.dispose();
    });

    test('waveformGeneration starts at 0', () {
      final provider = EditorModeProvider();
      expect(provider.waveformGeneration, 0);
      provider.dispose();
    });
  });

  group('EditorModeProvider — mode switching', () {
    late EditorModeProvider provider;

    setUp(() {
      provider = EditorModeProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('setMode changes mode', () {
      provider.setMode(EditorMode.middleware);
      expect(provider.mode, EditorMode.middleware);
    });

    test('setMode to same mode does not notify', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.setMode(EditorMode.daw); // Already DAW
      expect(count, 0);
    });

    test('setMode to different mode notifies', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.setMode(EditorMode.middleware);
      expect(count, 1);
    });

    test('toggleMode flips daw to middleware', () {
      provider.toggleMode();
      expect(provider.mode, EditorMode.middleware);
    });

    test('toggleMode flips middleware to daw', () {
      provider.setMode(EditorMode.middleware);
      provider.toggleMode();
      expect(provider.mode, EditorMode.daw);
    });

    test('isMode checks correctly', () {
      expect(provider.isMode(EditorMode.daw), true);
      expect(provider.isMode(EditorMode.middleware), false);
      provider.setMode(EditorMode.middleware);
      expect(provider.isMode(EditorMode.daw), false);
      expect(provider.isMode(EditorMode.middleware), true);
    });

    test('config updates after mode switch', () {
      provider.setMode(EditorMode.middleware);
      expect(provider.config.mode, EditorMode.middleware);
      expect(provider.config.name, 'Events');
    });
  });

  group('EditorModeProvider — waveform generation counter', () {
    late EditorModeProvider provider;

    setUp(() {
      provider = EditorModeProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('counter does not increment when switching away from DAW', () {
      provider.setMode(EditorMode.middleware);
      expect(provider.waveformGeneration, 0);
    });

    test('counter increments when returning TO DAW from middleware', () {
      provider.setMode(EditorMode.middleware);
      expect(provider.waveformGeneration, 0);
      provider.setMode(EditorMode.daw);
      expect(provider.waveformGeneration, 1);
    });

    test('counter does not increment switching DAW to DAW', () {
      provider.setMode(EditorMode.daw); // same mode, no change
      expect(provider.waveformGeneration, 0);
    });

    test('counter increments on each round trip', () {
      provider.setMode(EditorMode.middleware);
      provider.setMode(EditorMode.daw);
      expect(provider.waveformGeneration, 1);
      provider.setMode(EditorMode.middleware);
      provider.setMode(EditorMode.daw);
      expect(provider.waveformGeneration, 2);
      provider.setMode(EditorMode.middleware);
      provider.setMode(EditorMode.daw);
      expect(provider.waveformGeneration, 3);
    });

    test('toggleMode does not increment counter (only setMode does)', () {
      provider.toggleMode(); // DAW → middleware
      expect(provider.waveformGeneration, 0);
      provider.toggleMode(); // middleware → DAW
      // toggleMode sets _mode directly without calling setMode,
      // so waveformGeneration is NOT incremented.
      expect(provider.waveformGeneration, 0);
    });
  });

  group('EditorModeProvider — notifications', () {
    late EditorModeProvider provider;

    setUp(() {
      provider = EditorModeProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('setMode notifies on change', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.setMode(EditorMode.middleware);
      expect(count, 1);
    });

    test('toggleMode notifies', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.toggleMode();
      expect(count, 1);
    });

    test('multiple toggles notify each time', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.toggleMode();
      provider.toggleMode();
      provider.toggleMode();
      expect(count, 3);
    });
  });

  group('EditorModeProvider — dispose', () {
    test('dispose does not crash', () {
      final provider = EditorModeProvider();
      provider.dispose();
    });
  });
}
