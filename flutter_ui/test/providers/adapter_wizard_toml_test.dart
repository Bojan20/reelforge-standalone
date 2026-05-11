/// Tests for AdapterWizardProvider._applyOverridesToToml (G.3)
///
/// Verifies that event_mapping overrides are correctly injected into
/// a TOML config string without corrupting other sections.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/stage_provider.dart';

// _applyOverridesToToml is package-private static — expose via reflection
// helper that calls AdapterWizardProvider.applyOverridesToTomlForTest
// (we add a thin test-only shim below).
String _apply(String toml, Map<String, String> overrides) =>
    AdapterWizardProvider.applyOverridesToTomlForTest(toml, overrides);

void main() {
  group('AdapterWizardProvider._applyOverridesToToml (G.3)', () {
    test('empty overrides returns toml unchanged', () {
      const input = '[adapter]\nid = "igt"\n';
      expect(_apply(input, {}), equals(input));
    });

    test('no [event_mapping] section → appends new section', () {
      const base = '[adapter]\nid = "igt"\n';
      final result = _apply(base, {'cmd_spin': 'UiSpinPress'});
      expect(result, contains('[event_mapping]'));
      expect(result, contains('cmd_spin = "UiSpinPress"'));
      expect(result, contains('[adapter]')); // original intact
    });

    test('existing [event_mapping] section — adds new key', () {
      const base = '[adapter]\nid = "igt"\n\n[event_mapping]\nexisting = "Old"\n';
      final result = _apply(base, {'new_key': 'NewStage'});
      expect(result, contains('existing = "Old"'));
      expect(result, contains('new_key = "NewStage"'));
    });

    test('existing [event_mapping] section — replaces existing key', () {
      const base = '[adapter]\nid = "igt"\n\n[event_mapping]\ncmd_spin = "OldStage"\n';
      final result = _apply(base, {'cmd_spin': 'UiSpinPress'});
      expect(result, contains('cmd_spin = "UiSpinPress"'));
      expect(result, isNot(contains('OldStage')));
    });

    test('multiple overrides applied in one pass', () {
      const base = '[event_mapping]\na = "A"\n\n[other]\nx = 1\n';
      final result = _apply(base, {'a': 'A2', 'b': 'B1', 'c': 'C1'});
      expect(result, contains('a = "A2"'));
      expect(result, contains('b = "B1"'));
      expect(result, contains('c = "C1"'));
      expect(result, contains('[other]')); // subsequent section preserved
    });

    test('section at end of file (no trailing newline) handled gracefully', () {
      const base = '[event_mapping]\ncmd = "Old"';
      final result = _apply(base, {'cmd': 'New'});
      expect(result, contains('cmd = "New"'));
      expect(result, isNot(contains('cmd = "Old"')));
    });

    test('empty base toml — appends section', () {
      final result = _apply('', {'key': 'val'});
      expect(result, contains('[event_mapping]'));
      expect(result, contains('key = "val"'));
    });
  });
}
