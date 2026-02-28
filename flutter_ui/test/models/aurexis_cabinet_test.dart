import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/aurexis_cabinet.dart';

void main() {
  group('CabinetSpeakerProfile', () {
    test('all profiles have labels', () {
      for (final profile in CabinetSpeakerProfile.values) {
        expect(profile.label, isNotEmpty);
        expect(profile.shortLabel, isNotEmpty);
        expect(profile.speakerConfig, isNotEmpty);
      }
    });

    test('IGT is mono', () {
      expect(CabinetSpeakerProfile.igt.isMono, true);
    });

    test('Aristocrat is stereo', () {
      expect(CabinetSpeakerProfile.aristocrat.isMono, false);
    });

    test('Mobile is mono', () {
      expect(CabinetSpeakerProfile.mobile.isMono, true);
    });
  });

  group('CabinetSpeakerDatabase', () {
    test('all profiles have responses', () {
      for (final profile in CabinetSpeakerProfile.values) {
        final response = CabinetSpeakerDatabase.getResponse(profile);
        expect(response, isNotNull);
        expect(response.profile, profile);
      }
    });

    test('IGT has limited frequency range', () {
      final response = CabinetSpeakerDatabase.getResponse(CabinetSpeakerProfile.igt);
      expect(response.lowCutHz, greaterThanOrEqualTo(80));
      expect(response.highCutHz, lessThanOrEqualTo(12000));
    });

    test('studio reference has near-full range', () {
      final response = CabinetSpeakerDatabase.getResponse(CabinetSpeakerProfile.studioReference);
      expect(response.lowCutHz, lessThanOrEqualTo(40));
      expect(response.highCutHz, greaterThanOrEqualTo(20000));
    });

    test('mobile has narrow stereo width', () {
      final response = CabinetSpeakerDatabase.getResponse(CabinetSpeakerProfile.mobile);
      expect(response.stereoWidth, 0.0);
    });

    test('headphone has wide stereo', () {
      final response = CabinetSpeakerDatabase.getResponse(CabinetSpeakerProfile.headphone);
      expect(response.stereoWidth, greaterThanOrEqualTo(1.0));
    });
  });

  group('CabinetAmbientPreset', () {
    test('all presets have labels', () {
      for (final preset in CabinetAmbientPreset.values) {
        expect(preset.label, isNotEmpty);
      }
    });

    test('SPL values increase with noisier environments', () {
      expect(CabinetAmbientPreset.quietCasino.splDb,
          lessThan(CabinetAmbientPreset.moderateCasino.splDb));
      expect(CabinetAmbientPreset.moderateCasino.splDb,
          lessThan(CabinetAmbientPreset.busyCasino.splDb));
      expect(CabinetAmbientPreset.busyCasino.splDb,
          lessThan(CabinetAmbientPreset.noisyFloor.splDb));
    });

    test('mix levels increase with SPL', () {
      expect(CabinetAmbientPreset.quietCasino.mixLevel,
          lessThan(CabinetAmbientPreset.noisyFloor.mixLevel));
    });

    test('silent preset has zero level', () {
      expect(CabinetAmbientPreset.silent.splDb, 0.0);
      expect(CabinetAmbientPreset.silent.mixLevel, 0.0);
    });
  });

  group('CabinetSimulatorState', () {
    test('default state is disabled with generic profile', () {
      const state = CabinetSimulatorState();
      expect(state.enabled, false);
      expect(state.speakerProfile, CabinetSpeakerProfile.generic);
    });

    test('effectiveResponse returns built-in for non-custom', () {
      const state = CabinetSimulatorState(speakerProfile: CabinetSpeakerProfile.igt);
      final response = state.effectiveResponse;
      expect(response.profile, CabinetSpeakerProfile.igt);
    });

    test('effectiveResponse returns custom bands for custom profile', () {
      const state = CabinetSimulatorState(
        speakerProfile: CabinetSpeakerProfile.custom,
        customLowCutHz: 100,
        customHighCutHz: 15000,
        customBands: [
          CabinetEqBand(frequencyHz: 1000, gainDb: 3, q: 1.0),
        ],
      );
      final response = state.effectiveResponse;
      expect(response.profile, CabinetSpeakerProfile.custom);
      expect(response.lowCutHz, 100);
      expect(response.highCutHz, 15000);
      expect(response.bands.length, 1);
    });

    test('copyWith works correctly', () {
      const state = CabinetSimulatorState();
      final updated = state.copyWith(enabled: true, speakerProfile: CabinetSpeakerProfile.mobile);
      expect(updated.enabled, true);
      expect(updated.speakerProfile, CabinetSpeakerProfile.mobile);
      expect(updated.ambient.preset, CabinetAmbientPreset.silent); // unchanged
    });
  });

  group('CabinetAmbientConfig', () {
    test('effectiveLevel returns preset level for non-custom', () {
      const config = CabinetAmbientConfig(preset: CabinetAmbientPreset.busyCasino);
      expect(config.effectiveLevel, CabinetAmbientPreset.busyCasino.mixLevel);
    });

    test('effectiveLevel returns customLevel for custom preset', () {
      const config = CabinetAmbientConfig(
        preset: CabinetAmbientPreset.custom,
        customLevel: 0.42,
      );
      expect(config.effectiveLevel, 0.42);
    });
  });
}
