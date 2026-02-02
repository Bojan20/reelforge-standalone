/// Mix Template Service Tests (P12.1.12)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/mix_template_service.dart';

void main() {
  group('BusMixSettings', () {
    test('default values are correct', () {
      const settings = BusMixSettings(busId: 0, busName: 'Test');

      expect(settings.volume, 1.0);
      expect(settings.pan, 0.0);
      expect(settings.muted, false);
      expect(settings.soloed, false);
      expect(settings.auxSend1, 0.0);
      expect(settings.auxSend2, 0.0);
    });

    test('copyWith preserves unmodified fields', () {
      const original = BusMixSettings(busId: 0, busName: 'Test', volume: 0.8);
      final copied = original.copyWith(pan: 0.5);

      expect(copied.busId, original.busId);
      expect(copied.busName, original.busName);
      expect(copied.volume, original.volume);
      expect(copied.pan, 0.5);
    });

    test('toJson serializes all fields', () {
      const settings = BusMixSettings(
        busId: 1,
        busName: 'Music',
        volume: 0.7,
        pan: -0.3,
        auxSend1: 0.2,
      );
      final json = settings.toJson();

      expect(json['busId'], 1);
      expect(json['busName'], 'Music');
      expect(json['volume'], 0.7);
      expect(json['pan'], -0.3);
      expect(json['auxSend1'], 0.2);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'busId': 2,
        'busName': 'SFX',
        'volume': 0.9,
        'muted': true,
      };
      final settings = BusMixSettings.fromJson(json);

      expect(settings.busId, 2);
      expect(settings.busName, 'SFX');
      expect(settings.volume, 0.9);
      expect(settings.muted, true);
    });
  });

  group('MixTemplate', () {
    test('has 5 built-in templates', () {
      expect(BuiltInMixTemplates.templates.length, 5);
    });

    test('built-in templates have required bus settings', () {
      for (final template in BuiltInMixTemplates.templates) {
        expect(template.busSettings.length, greaterThanOrEqualTo(4));
        expect(template.category, 'built-in');
      }
    });

    test('template types match expected names', () {
      final names = BuiltInMixTemplates.templates.map((t) => t.id).toList();
      expect(names, contains('base_game'));
      expect(names, contains('free_spins'));
      expect(names, contains('bonus'));
      expect(names, contains('big_win'));
      expect(names, contains('jackpot'));
    });

    test('toJson/fromJson roundtrip', () {
      final template = BuiltInMixTemplates.templates.first;
      final json = template.toJson();
      final restored = MixTemplate.fromJson(json);

      expect(restored.id, template.id);
      expect(restored.name, template.name);
      expect(restored.busSettings.length, template.busSettings.length);
    });
  });
}
