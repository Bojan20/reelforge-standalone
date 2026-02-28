import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/aurexis_profile.dart';

void main() {
  group('AurexisBehaviorConfig', () {
    test('default values match class defaults', () {
      const config = AurexisBehaviorConfig();
      expect(config.spatial.width, 0.6);
      expect(config.spatial.depth, 0.5);
      expect(config.spatial.movement, 0.3);
      expect(config.dynamics.escalation, 0.5);
      expect(config.dynamics.fatigue, 0.4);
      expect(config.music.reactivity, 0.5);
      expect(config.music.transition, 0.6);
      expect(config.variation.panDrift, 0.3);
      expect(config.variation.widthVar, 0.2);
    });

    test('scaledBy 0.0 returns neutral values', () {
      const config = AurexisBehaviorConfig(
        spatial: SpatialBehavior(width: 1.0, depth: 0.0, movement: 0.8),
      );
      final scaled = config.scaledBy(0.0);
      expect(scaled.spatial.width, 0.5);
      expect(scaled.spatial.depth, 0.5);
      expect(scaled.spatial.movement, 0.5);
    });

    test('scaledBy 1.0 returns original values', () {
      const config = AurexisBehaviorConfig(
        spatial: SpatialBehavior(width: 1.0, depth: 0.0, movement: 0.8),
      );
      final scaled = config.scaledBy(1.0);
      expect(scaled.spatial.width, 1.0);
      expect(scaled.spatial.depth, 0.0);
      expect(scaled.spatial.movement, 0.8);
    });
  });

  group('AurexisProfile', () {
    test('built-in profiles generate valid engine configs', () {
      for (final profile in AurexisBuiltInProfiles.all) {
        final config = profile.generateEngineConfig();
        expect(config, isNotEmpty, reason: 'Profile ${profile.name} should generate config');
        expect(config.containsKey('volatility'), true);
        expect(config.containsKey('rtp'), true);
        expect(config.containsKey('fatigue'), true);
        expect(config.containsKey('collision'), true);
        expect(config.containsKey('escalation'), true);
        expect(config.containsKey('variation'), true);
        expect(config.containsKey('platform'), true);
      }
    });

    test('12 built-in profiles exist', () {
      expect(AurexisBuiltInProfiles.all.length, 12);
    });

    test('all profiles have unique IDs', () {
      final ids = AurexisBuiltInProfiles.all.map((p) => p.id).toSet();
      expect(ids.length, AurexisBuiltInProfiles.all.length);
    });

    test('intensity scaling works', () {
      final profile = AurexisBuiltInProfiles.calmClassic;
      final config0 = profile.copyWith(intensity: 0.0).generateEngineConfig();
      final config1 = profile.copyWith(intensity: 1.0).generateEngineConfig();
      // Different intensities should produce different configs
      expect(config0, isNot(equals(config1)));
    });
  });

  group('AurexisProfileSnapshot', () {
    test('can capture and restore profile', () {
      final profile = AurexisBuiltInProfiles.standardVideo;
      final snapshot = AurexisProfileSnapshot(
        profile: profile,
        engineConfig: profile.generateEngineConfig(),
      );
      expect(snapshot.profile.id, profile.id);
      expect(snapshot.profile.intensity, profile.intensity);
      expect(snapshot.engineConfig, isNotEmpty);
    });
  });

  group('autoSelectFromGdd', () {
    test('high volatility selects appropriate profile', () {
      final profile = AurexisBuiltInProfiles.autoSelectFromGdd(
        volatility: 'high',
        rtp: 95.0,
        mechanic: 'megaways',
      );
      expect(profile, isNotNull);
    });

    test('low volatility selects calm profile', () {
      final profile = AurexisBuiltInProfiles.autoSelectFromGdd(
        volatility: 'low',
        rtp: 96.0,
      );
      expect(profile, isNotNull);
    });
  });
}
