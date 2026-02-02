/// Reverb Template Browser Tests (P12.1.11)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/reverb_template_browser.dart';

void main() {
  group('ReverbSpacePreset', () {
    test('has 10 built-in presets', () {
      expect(ReverbPresets.builtIn.length, 10);
    });

    test('all presets have valid parameters', () {
      for (final preset in ReverbPresets.builtIn) {
        expect(preset.decay, greaterThan(0));
        expect(preset.decay, lessThanOrEqualTo(10));
        expect(preset.preDelay, greaterThanOrEqualTo(0));
        expect(preset.preDelay, lessThanOrEqualTo(200));
        expect(preset.damping, greaterThanOrEqualTo(0));
        expect(preset.damping, lessThanOrEqualTo(1));
        expect(preset.size, greaterThanOrEqualTo(0));
        expect(preset.size, lessThanOrEqualTo(1));
      }
    });

    test('toJson serializes all fields', () {
      final preset = ReverbPresets.builtIn.first;
      final json = preset.toJson();

      expect(json['id'], preset.id);
      expect(json['name'], preset.name);
      expect(json['decay'], preset.decay);
      expect(json['preDelay'], preset.preDelay);
      expect(json['damping'], preset.damping);
      expect(json['size'], preset.size);
    });

    test('preset types are distributed', () {
      final types = ReverbPresets.builtIn.map((p) => p.type).toSet();
      expect(types.length, greaterThan(3)); // Multiple types present
    });
  });
}
