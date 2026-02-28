import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/aurexis_models.dart';

void main() {
  group('AurexisParameterMap', () {
    test('default values are sane', () {
      const params = AurexisParameterMap();
      expect(params.fatigueIndex, 0.0);
      expect(params.energyDensity, 0.5);
      expect(params.stereoWidth, 1.0);
      expect(params.escalationMultiplier, 1.0);
      expect(params.attentionWeight, 0.0);
    });

    test('constructor accepts custom values', () {
      const params = AurexisParameterMap(
        fatigueIndex: 0.5,
        stereoWidth: 1.2,
        escalationMultiplier: 3.0,
      );
      expect(params.fatigueIndex, 0.5);
      expect(params.stereoWidth, 1.2);
      expect(params.escalationMultiplier, 3.0);
    });
  });

  group('AurexisPlatform', () {
    test('all platforms have labels', () {
      for (final platform in AurexisPlatform.values) {
        expect(platform.label, isNotEmpty);
      }
    });
  });
}
