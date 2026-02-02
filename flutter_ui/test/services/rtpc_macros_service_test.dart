import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ui/models/middleware_models.dart';
import 'package:flutter_ui/services/rtpc_macros_service.dart';

void main() {
  group('MacroCurveType', () {
    test('linear curve returns input unchanged', () {
      expect(MacroCurveType.linear.apply(0.0), 0.0);
      expect(MacroCurveType.linear.apply(0.5), 0.5);
      expect(MacroCurveType.linear.apply(1.0), 1.0);
    });

    test('easeIn starts slow', () {
      final mid = MacroCurveType.easeIn.apply(0.5);
      expect(mid, lessThan(0.5)); // Should be less than linear at midpoint
    });

    test('easeOut ends slow', () {
      final mid = MacroCurveType.easeOut.apply(0.5);
      expect(mid, greaterThan(0.5)); // Should be greater than linear at midpoint
    });

    test('step returns 0 or 1', () {
      expect(MacroCurveType.step.apply(0.0), 0.0);
      expect(MacroCurveType.step.apply(0.49), 0.0);
      expect(MacroCurveType.step.apply(0.5), 1.0);
      expect(MacroCurveType.step.apply(1.0), 1.0);
    });

    test('clamps input to 0-1', () {
      expect(MacroCurveType.linear.apply(-0.5), 0.0);
      expect(MacroCurveType.linear.apply(1.5), 1.0);
    });

    test('has correct display names', () {
      expect(MacroCurveType.linear.displayName, 'Linear');
      expect(MacroCurveType.easeInOut.displayName, 'Ease In/Out');
      expect(MacroCurveType.sCurve.displayName, 'S-Curve');
    });
  });

  group('RtpcMacroBinding', () {
    test('creates with default values', () {
      const binding = RtpcMacroBinding(
        rtpcId: 1,
        rtpcName: 'Test RTPC',
        target: RtpcTargetParameter.volume,
      );

      expect(binding.rtpcId, 1);
      expect(binding.rtpcName, 'Test RTPC');
      expect(binding.target, RtpcTargetParameter.volume);
      expect(binding.curve, MacroCurveType.linear);
      expect(binding.minOutput, 0.0);
      expect(binding.maxOutput, 1.0);
      expect(binding.inverted, false);
      expect(binding.enabled, true);
    });

    test('evaluate returns correct output', () {
      const binding = RtpcMacroBinding(
        rtpcId: 1,
        rtpcName: 'Test',
        target: RtpcTargetParameter.volume,
        minOutput: 0.0,
        maxOutput: 1.0,
        curve: MacroCurveType.linear,
      );

      expect(binding.evaluate(0.0), 0.0);
      expect(binding.evaluate(0.5), 0.5);
      expect(binding.evaluate(1.0), 1.0);
    });

    test('evaluate respects min/max output', () {
      const binding = RtpcMacroBinding(
        rtpcId: 1,
        rtpcName: 'Test',
        target: RtpcTargetParameter.volume,
        minOutput: 0.5,
        maxOutput: 1.5,
        curve: MacroCurveType.linear,
      );

      expect(binding.evaluate(0.0), 0.5);
      expect(binding.evaluate(0.5), 1.0);
      expect(binding.evaluate(1.0), 1.5);
    });

    test('evaluate respects inverted flag', () {
      const binding = RtpcMacroBinding(
        rtpcId: 1,
        rtpcName: 'Test',
        target: RtpcTargetParameter.volume,
        minOutput: 0.0,
        maxOutput: 1.0,
        curve: MacroCurveType.linear,
        inverted: true,
      );

      expect(binding.evaluate(0.0), 1.0);
      expect(binding.evaluate(1.0), 0.0);
    });

    test('evaluate returns minOutput when disabled', () {
      const binding = RtpcMacroBinding(
        rtpcId: 1,
        rtpcName: 'Test',
        target: RtpcTargetParameter.volume,
        minOutput: 0.5,
        maxOutput: 1.0,
        enabled: false,
      );

      expect(binding.evaluate(0.5), 0.5);
      expect(binding.evaluate(1.0), 0.5);
    });

    test('serializes to JSON and back', () {
      const binding = RtpcMacroBinding(
        rtpcId: 42,
        rtpcName: 'My RTPC',
        target: RtpcTargetParameter.pitch,
        curve: MacroCurveType.exponential,
        minOutput: -12.0,
        maxOutput: 12.0,
        inverted: true,
        enabled: false,
      );

      final json = binding.toJson();
      final restored = RtpcMacroBinding.fromJson(json);

      expect(restored.rtpcId, binding.rtpcId);
      expect(restored.rtpcName, binding.rtpcName);
      expect(restored.target, binding.target);
      expect(restored.curve, binding.curve);
      expect(restored.minOutput, binding.minOutput);
      expect(restored.maxOutput, binding.maxOutput);
      expect(restored.inverted, binding.inverted);
      expect(restored.enabled, binding.enabled);
    });
  });

  group('RtpcMacro', () {
    test('creates with default values', () {
      const macro = RtpcMacro(
        id: 1,
        name: 'Test Macro',
      );

      expect(macro.id, 1);
      expect(macro.name, 'Test Macro');
      expect(macro.min, 0.0);
      expect(macro.max, 1.0);
      expect(macro.defaultValue, 0.5);
      expect(macro.currentValue, 0.5);
      expect(macro.bindings, isEmpty);
      expect(macro.enabled, true);
    });

    test('normalizedValue calculates correctly', () {
      const macro = RtpcMacro(
        id: 1,
        name: 'Test',
        min: 0.0,
        max: 100.0,
        currentValue: 50.0,
      );

      expect(macro.normalizedValue, 0.5);
    });

    test('normalizedValue clamps to 0-1', () {
      const macro1 = RtpcMacro(
        id: 1,
        name: 'Test',
        min: 0.0,
        max: 100.0,
        currentValue: -50.0,
      );
      expect(macro1.normalizedValue, 0.0);

      const macro2 = RtpcMacro(
        id: 2,
        name: 'Test',
        min: 0.0,
        max: 100.0,
        currentValue: 150.0,
      );
      expect(macro2.normalizedValue, 1.0);
    });

    test('evaluate returns empty map when disabled', () {
      const macro = RtpcMacro(
        id: 1,
        name: 'Test',
        enabled: false,
        bindings: [
          RtpcMacroBinding(
            rtpcId: 1,
            rtpcName: 'Test',
            target: RtpcTargetParameter.volume,
          ),
        ],
      );

      expect(macro.evaluate(), isEmpty);
    });

    test('evaluate returns correct values for bindings', () {
      const macro = RtpcMacro(
        id: 1,
        name: 'Test',
        min: 0.0,
        max: 1.0,
        currentValue: 0.5,
        bindings: [
          RtpcMacroBinding(
            rtpcId: 1,
            rtpcName: 'Volume',
            target: RtpcTargetParameter.volume,
            minOutput: 0.0,
            maxOutput: 1.0,
          ),
          RtpcMacroBinding(
            rtpcId: 2,
            rtpcName: 'Pan',
            target: RtpcTargetParameter.pan,
            minOutput: -1.0,
            maxOutput: 1.0,
          ),
        ],
      );

      final result = macro.evaluate();
      expect(result[RtpcTargetParameter.volume], 0.5);
      expect(result[RtpcTargetParameter.pan], 0.0); // -1 + 2 * 0.5 = 0
    });

    test('serializes to JSON and back', () {
      const macro = RtpcMacro(
        id: 42,
        name: 'My Macro',
        description: 'Test description',
        min: 0.0,
        max: 100.0,
        defaultValue: 50.0,
        currentValue: 75.0,
        bindings: [
          RtpcMacroBinding(
            rtpcId: 1,
            rtpcName: 'Test',
            target: RtpcTargetParameter.volume,
          ),
        ],
        enabled: false,
      );

      final json = macro.toJson();
      final restored = RtpcMacro.fromJson(json);

      expect(restored.id, macro.id);
      expect(restored.name, macro.name);
      expect(restored.description, macro.description);
      expect(restored.min, macro.min);
      expect(restored.max, macro.max);
      expect(restored.defaultValue, macro.defaultValue);
      expect(restored.currentValue, macro.currentValue);
      expect(restored.bindings.length, 1);
      expect(restored.enabled, macro.enabled);
    });
  });

  group('BuiltInMacroPresets', () {
    test('intensity preset has correct bindings', () {
      final intensity = BuiltInMacroPresets.intensity(1);

      expect(intensity.name, 'Intensity');
      expect(intensity.bindings.length, 3);
      expect(intensity.bindings.any((b) => b.target == RtpcTargetParameter.volume), true);
      expect(intensity.bindings.any((b) => b.target == RtpcTargetParameter.pitch), true);
      expect(intensity.bindings.any((b) => b.target == RtpcTargetParameter.lowPassFilter), true);
    });

    test('all presets create valid macros', () {
      var id = 1;
      for (final presetFactory in BuiltInMacroPresets.all) {
        final macro = presetFactory(id++);
        expect(macro.name.isNotEmpty, true);
        expect(macro.bindings.isNotEmpty, true);
      }
    });
  });
}
