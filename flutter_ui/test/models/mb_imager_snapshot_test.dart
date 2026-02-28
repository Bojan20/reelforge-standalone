/// Unit tests for MbImagerSnapshot and MbImagerBandState
///
/// Validates A/B snapshot copy, equality, and data integrity
/// for the multiband stereo imager panel.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/fabfilter/fabfilter_multiband_imager_panel.dart';

void main() {
  group('MbImagerBandState', () {
    test('copy creates independent instance', () {
      final band = MbImagerBandState(
        width: 1.5,
        pan: -0.3,
        midGainDb: 2.0,
        sideGainDb: -1.5,
        rotation: 45.0,
        enableWidth: true,
        solo: true,
        mute: false,
        bypass: true,
      );

      final copy = band.copy();

      // Values match
      expect(copy.width, 1.5);
      expect(copy.pan, -0.3);
      expect(copy.midGainDb, 2.0);
      expect(copy.sideGainDb, -1.5);
      expect(copy.rotation, 45.0);
      expect(copy.enableWidth, true);
      expect(copy.solo, true);
      expect(copy.mute, false);
      expect(copy.bypass, true);

      // Mutation of copy doesn't affect original
      copy.width = 0.5;
      expect(band.width, 1.5);
    });

    test('default values', () {
      final band = MbImagerBandState();
      expect(band.width, 1.0);
      expect(band.pan, 0.0);
      expect(band.midGainDb, 0.0);
      expect(band.sideGainDb, 0.0);
      expect(band.rotation, 0.0);
      expect(band.enableWidth, true);
      expect(band.solo, false);
      expect(band.mute, false);
      expect(band.bypass, false);
    });
  });

  group('MbImagerSnapshot', () {
    MbImagerSnapshot _makeSnapshot({
      double inputGain = -3.0,
      double outputGain = 1.5,
      double globalMix = 75.0,
      bool msMode = true,
      bool stereoizeEnabled = true,
      double stereoizeAmount = 0.7,
      bool bandLink = true,
      int numBands = 4,
      int crossoverType = 2,
    }) {
      return MbImagerSnapshot(
        inputGain: inputGain,
        outputGain: outputGain,
        globalMix: globalMix,
        msMode: msMode,
        stereoizeEnabled: stereoizeEnabled,
        stereoizeAmount: stereoizeAmount,
        bandLink: bandLink,
        numBands: numBands,
        crossoverType: crossoverType,
        crossovers: [120.0, 750.0, 2500.0, 7000.0, 14000.0],
        bands: List.generate(6, (i) => MbImagerBandState(
          width: 0.5 + i * 0.2,
          pan: i * 0.1,
        )),
      );
    }

    test('copy creates deep independent copy', () {
      final snap = _makeSnapshot();
      final copy = snap.copy();

      expect(copy.inputGain, snap.inputGain);
      expect(copy.outputGain, snap.outputGain);
      expect(copy.globalMix, snap.globalMix);
      expect(copy.msMode, snap.msMode);
      expect(copy.stereoizeEnabled, snap.stereoizeEnabled);
      expect(copy.stereoizeAmount, snap.stereoizeAmount);
      expect(copy.bandLink, snap.bandLink);
      expect(copy.numBands, snap.numBands);
      expect(copy.crossoverType, snap.crossoverType);
      expect(copy.crossovers.length, 5);
      expect(copy.bands.length, 6);

      // Deep copy: changing copy bands doesn't affect original
      copy.bands[0].width = 99.0;
      expect(snap.bands[0].width, 0.5);

      // Deep copy: changing copy crossovers doesn't affect original
      copy.crossovers[0] = 999.0;
      expect(snap.crossovers[0], 120.0);
    });

    test('equals detects matching snapshots', () {
      final a = _makeSnapshot();
      final b = _makeSnapshot();
      expect(a.equals(b), true);
    });

    test('equals detects differences', () {
      final a = _makeSnapshot(inputGain: 0.0);
      final b = _makeSnapshot(inputGain: 5.0);
      expect(a.equals(b), false);

      final c = _makeSnapshot(numBands: 3);
      final d = _makeSnapshot(numBands: 5);
      expect(c.equals(d), false);
    });

    test('stereoize fields preserved in copy', () {
      final snap = _makeSnapshot(
        stereoizeEnabled: true,
        stereoizeAmount: 0.85,
        bandLink: true,
      );
      final copy = snap.copy();

      expect(copy.stereoizeEnabled, true);
      expect(copy.stereoizeAmount, 0.85);
      expect(copy.bandLink, true);
    });

    test('band state independence across 6 bands', () {
      final snap = _makeSnapshot();
      for (int i = 0; i < 6; i++) {
        expect(snap.bands[i].width, closeTo(0.5 + i * 0.2, 0.001));
        expect(snap.bands[i].pan, closeTo(i * 0.1, 0.001));
      }
    });
  });
}
