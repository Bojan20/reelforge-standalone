/// StemRoutingProvider Tests
///
/// Tests track registration, stem routing, auto-detection,
/// batch operations, and JSON serialization.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/stem_routing_provider.dart';

void main() {
  group('StemType enum', () {
    test('all stem types have labels', () {
      for (final stem in StemType.values) {
        expect(stem.label, isNotEmpty);
      }
    });

    test('all stem types have codes', () {
      for (final stem in StemType.values) {
        expect(stem.code, isNotEmpty);
      }
    });

    test('all stem types have descriptions', () {
      for (final stem in StemType.values) {
        expect(stem.description, isNotEmpty);
      }
    });

    test('codes are 2-3 characters', () {
      for (final stem in StemType.values) {
        expect(stem.code.length, inInclusiveRange(2, 3));
      }
    });

    test('has 8 stem types', () {
      expect(StemType.values.length, 8);
    });
  });

  group('StemRouting model', () {
    test('constructor preserves fields', () {
      final routing = StemRouting(
        trackId: 'track_1',
        trackName: 'Kick Drum',
        isTrack: true,
        stems: {StemType.drums, StemType.master},
      );
      expect(routing.trackId, 'track_1');
      expect(routing.trackName, 'Kick Drum');
      expect(routing.isTrack, true);
      expect(routing.stems, {StemType.drums, StemType.master});
    });

    test('defaults to empty stems', () {
      const routing = StemRouting(
        trackId: 'track_1',
        trackName: 'Test',
        isTrack: true,
      );
      expect(routing.stems, isEmpty);
    });

    test('isRoutedTo checks membership', () {
      final routing = StemRouting(
        trackId: 'track_1',
        trackName: 'Test',
        isTrack: true,
        stems: {StemType.drums},
      );
      expect(routing.isRoutedTo(StemType.drums), true);
      expect(routing.isRoutedTo(StemType.bass), false);
    });

    test('toggle adds stem when not present', () {
      const routing = StemRouting(
        trackId: 'track_1',
        trackName: 'Test',
        isTrack: true,
      );
      final toggled = routing.toggle(StemType.drums);
      expect(toggled.stems.contains(StemType.drums), true);
    });

    test('toggle removes stem when present', () {
      final routing = StemRouting(
        trackId: 'track_1',
        trackName: 'Test',
        isTrack: true,
        stems: {StemType.drums},
      );
      final toggled = routing.toggle(StemType.drums);
      expect(toggled.stems.contains(StemType.drums), false);
    });

    test('copyWith preserves unmodified fields', () {
      final routing = StemRouting(
        trackId: 'track_1',
        trackName: 'Test',
        isTrack: true,
        stems: {StemType.drums},
      );
      final copied = routing.copyWith(stems: {StemType.bass});
      expect(copied.trackId, 'track_1');
      expect(copied.trackName, 'Test');
      expect(copied.isTrack, true);
      expect(copied.stems, {StemType.bass});
    });

    test('toJson/fromJson round trip', () {
      final routing = StemRouting(
        trackId: 'track_1',
        trackName: 'Kick Drum',
        isTrack: true,
        stems: {StemType.drums, StemType.master},
      );
      final json = routing.toJson();
      final restored = StemRouting.fromJson(json);
      expect(restored.trackId, routing.trackId);
      expect(restored.trackName, routing.trackName);
      expect(restored.isTrack, routing.isTrack);
      expect(restored.stems, routing.stems);
    });

    test('fromJson handles missing stems', () {
      final routing = StemRouting.fromJson({
        'trackId': 'track_1',
        'trackName': 'Test',
      });
      expect(routing.stems, isEmpty);
    });

    test('fromJson handles unknown stem type', () {
      final routing = StemRouting.fromJson({
        'trackId': 'track_1',
        'trackName': 'Test',
        'isTrack': true,
        'stems': ['drums', 'unknown_stem_type'],
      });
      // Unknown stem maps to StemType.custom
      expect(routing.stems.contains(StemType.drums), true);
      expect(routing.stems.contains(StemType.custom), true);
    });
  });

  group('StemRoutingProvider — registration', () {
    late StemRoutingProvider provider;

    setUp(() {
      provider = StemRoutingProvider();
    });

    test('starts empty', () {
      expect(provider.allRouting, isEmpty);
      expect(provider.trackCount, 0);
      expect(provider.hasRouting, false);
      expect(provider.connectionCount, 0);
    });

    test('registerTrack adds a track', () {
      provider.registerTrack('t1', 'Kick Drum');
      expect(provider.trackCount, 1);
      expect(provider.getRouting('t1'), isNotNull);
      expect(provider.getRouting('t1')!.trackName, 'Kick Drum');
    });

    test('registerTrack defaults isTrack to true', () {
      provider.registerTrack('t1', 'Test');
      expect(provider.getRouting('t1')!.isTrack, true);
    });

    test('registerTrack with isTrack false', () {
      provider.registerTrack('b1', 'SFX Bus', isTrack: false);
      expect(provider.getRouting('b1')!.isTrack, false);
    });

    test('registerTrack does not overwrite existing', () {
      provider.registerTrack('t1', 'Original');
      provider.addStemToTrack('t1', StemType.drums);
      provider.registerTrack('t1', 'Duplicate');
      expect(provider.getRouting('t1')!.trackName, 'Original');
      expect(provider.getStems('t1').contains(StemType.drums), true);
    });

    test('registerTracks adds multiple', () {
      provider.registerTracks([
        (id: 't1', name: 'Kick', isTrack: true),
        (id: 't2', name: 'Snare', isTrack: true),
        (id: 'b1', name: 'Bus', isTrack: false),
      ]);
      expect(provider.trackCount, 3);
    });

    test('unregisterTrack removes track', () {
      provider.registerTrack('t1', 'Test');
      provider.unregisterTrack('t1');
      expect(provider.trackCount, 0);
      expect(provider.getRouting('t1'), isNull);
    });

    test('unregisterTrack no-op for unknown', () {
      provider.unregisterTrack('nonexistent');
      expect(provider.trackCount, 0);
    });

    test('clearAll removes all tracks', () {
      provider.registerTrack('t1', 'A');
      provider.registerTrack('t2', 'B');
      provider.clearAll();
      expect(provider.trackCount, 0);
    });
  });

  group('StemRoutingProvider — routing operations', () {
    late StemRoutingProvider provider;

    setUp(() {
      provider = StemRoutingProvider();
      provider.registerTrack('t1', 'Kick Drum');
      provider.registerTrack('t2', 'Bass Synth');
      provider.registerTrack('t3', 'Lead Guitar');
    });

    test('toggleStemRouting adds stem', () {
      provider.toggleStemRouting('t1', StemType.drums);
      expect(provider.isRoutedTo('t1', StemType.drums), true);
    });

    test('toggleStemRouting removes when toggled again', () {
      provider.toggleStemRouting('t1', StemType.drums);
      provider.toggleStemRouting('t1', StemType.drums);
      expect(provider.isRoutedTo('t1', StemType.drums), false);
    });

    test('setStemRouting replaces existing', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.setStemRouting('t1', {StemType.bass, StemType.master});
      expect(provider.getStems('t1'), {StemType.bass, StemType.master});
    });

    test('addStemToTrack adds without removing existing', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t1', StemType.master);
      expect(provider.getStems('t1'), {StemType.drums, StemType.master});
    });

    test('addStemToTrack no-op for duplicate', () {
      provider.addStemToTrack('t1', StemType.drums);
      int count = 0;
      provider.addListener(() => count++);
      provider.addStemToTrack('t1', StemType.drums);
      expect(count, 0); // No notification — no change
    });

    test('removeStemFromTrack removes specific stem', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t1', StemType.master);
      provider.removeStemFromTrack('t1', StemType.drums);
      expect(provider.getStems('t1'), {StemType.master});
    });

    test('clearTrackRouting removes all stems from track', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t1', StemType.master);
      provider.clearTrackRouting('t1');
      expect(provider.getStems('t1'), isEmpty);
    });

    test('clearStemRouting removes stem from all tracks', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t2', StemType.drums);
      provider.addStemToTrack('t3', StemType.drums);
      provider.clearStemRouting(StemType.drums);
      expect(provider.getTracksForStem(StemType.drums), isEmpty);
    });

    test('getTracksForStem returns correct tracks', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t3', StemType.drums);
      final tracks = provider.getTracksForStem(StemType.drums);
      expect(tracks, containsAll(['t1', 't3']));
      expect(tracks.contains('t2'), false);
    });

    test('getTrackCountForStem returns count', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t2', StemType.drums);
      expect(provider.getTrackCountForStem(StemType.drums), 2);
    });

    test('hasRouting true when connections exist', () {
      expect(provider.hasRouting, false);
      provider.addStemToTrack('t1', StemType.drums);
      expect(provider.hasRouting, true);
    });

    test('connectionCount sums all routing', () {
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t1', StemType.master);
      provider.addStemToTrack('t2', StemType.bass);
      expect(provider.connectionCount, 3);
    });

    test('getStems returns empty for unregistered track', () {
      expect(provider.getStems('unknown'), isEmpty);
    });

    test('isRoutedTo returns false for unregistered track', () {
      expect(provider.isRoutedTo('unknown', StemType.drums), false);
    });
  });

  group('StemRoutingProvider — auto-detect', () {
    late StemRoutingProvider provider;

    setUp(() {
      provider = StemRoutingProvider();
      provider.registerTracks([
        (id: 't1', name: 'Kick Drum', isTrack: true),
        (id: 't2', name: 'Snare Hit', isTrack: true),
        (id: 't3', name: 'Bass Guitar', isTrack: true),
        (id: 't4', name: 'Lead Synth', isTrack: true),
        (id: 't5', name: 'Vocal Main', isTrack: true),
        (id: 't6', name: 'SFX Riser', isTrack: true),
        (id: 't7', name: 'Ambient Pad', isTrack: true),
        (id: 't8', name: 'HiHat Loop', isTrack: true),
        (id: 't9', name: '808 Sub', isTrack: true),
      ]);
    });

    test('autoSelectDrums detects drum-related tracks', () {
      provider.autoSelectDrums();
      expect(provider.isRoutedTo('t1', StemType.drums), true); // Kick Drum
      expect(provider.isRoutedTo('t2', StemType.drums), true); // Snare Hit
      expect(provider.isRoutedTo('t8', StemType.drums), true); // HiHat Loop
      expect(provider.isRoutedTo('t3', StemType.drums), false); // Bass Guitar
    });

    test('autoSelectBass detects bass-related tracks', () {
      provider.autoSelectBass();
      expect(provider.isRoutedTo('t3', StemType.bass), true); // Bass Guitar
      expect(provider.isRoutedTo('t9', StemType.bass), true); // 808 Sub
      expect(provider.isRoutedTo('t1', StemType.bass), false);
    });

    test('autoSelectMelody detects melody-related tracks', () {
      provider.autoSelectMelody();
      expect(provider.isRoutedTo('t4', StemType.melody), true); // Lead Synth
      expect(provider.isRoutedTo('t1', StemType.melody), false);
    });

    test('autoSelectVocals detects vocal-related tracks', () {
      provider.autoSelectVocals();
      expect(provider.isRoutedTo('t5', StemType.vocals), true); // Vocal Main
      expect(provider.isRoutedTo('t1', StemType.vocals), false);
    });

    test('autoSelectFx detects FX-related tracks', () {
      provider.autoSelectFx();
      expect(provider.isRoutedTo('t6', StemType.fx), true); // SFX Riser
      expect(provider.isRoutedTo('t1', StemType.fx), false);
    });

    test('autoSelectAmbience detects ambient-related tracks', () {
      provider.autoSelectAmbience();
      expect(provider.isRoutedTo('t7', StemType.ambience), true); // Ambient Pad
      expect(provider.isRoutedTo('t1', StemType.ambience), false);
    });

    test('selectAllToMaster routes all to master', () {
      provider.selectAllToMaster();
      for (final routing in provider.allRouting) {
        expect(routing.isRoutedTo(StemType.master), true);
      }
    });

    test('autoDetectAll runs all auto-select methods', () {
      provider.autoDetectAll();
      expect(provider.isRoutedTo('t1', StemType.drums), true);
      expect(provider.isRoutedTo('t3', StemType.bass), true);
      expect(provider.isRoutedTo('t4', StemType.melody), true);
      expect(provider.isRoutedTo('t5', StemType.vocals), true);
      expect(provider.isRoutedTo('t6', StemType.fx), true);
      expect(provider.isRoutedTo('t7', StemType.ambience), true);
    });

    test('clearAllRouting removes all routing', () {
      provider.autoDetectAll();
      expect(provider.hasRouting, true);
      provider.clearAllRouting();
      expect(provider.hasRouting, false);
      expect(provider.trackCount, 9); // Tracks still registered
    });
  });

  group('StemRoutingProvider — serialization', () {
    late StemRoutingProvider provider;

    setUp(() {
      provider = StemRoutingProvider();
    });

    test('toJson/fromJson round trip', () {
      provider.registerTrack('t1', 'Kick');
      provider.registerTrack('t2', 'Bass');
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t2', StemType.bass);

      final json = provider.toJson();
      final provider2 = StemRoutingProvider();
      provider2.fromJson(json);

      expect(provider2.trackCount, 2);
      expect(provider2.isRoutedTo('t1', StemType.drums), true);
      expect(provider2.isRoutedTo('t2', StemType.bass), true);
    });

    test('getExportConfiguration returns stem→tracks map', () {
      provider.registerTrack('t1', 'Kick');
      provider.registerTrack('t2', 'Snare');
      provider.addStemToTrack('t1', StemType.drums);
      provider.addStemToTrack('t2', StemType.drums);

      final config = provider.getExportConfiguration();
      expect(config.containsKey(StemType.drums), true);
      expect(config[StemType.drums]!.length, 2);
    });

    test('getExportConfiguration excludes empty stems', () {
      provider.registerTrack('t1', 'Kick');
      provider.addStemToTrack('t1', StemType.drums);

      final config = provider.getExportConfiguration();
      expect(config.containsKey(StemType.bass), false);
    });
  });

  group('StemRoutingProvider — notifications', () {
    late StemRoutingProvider provider;

    setUp(() {
      provider = StemRoutingProvider();
    });

    test('registerTrack notifies', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.registerTrack('t1', 'Test');
      expect(count, greaterThan(0));
    });

    test('toggleStemRouting notifies', () {
      provider.registerTrack('t1', 'Test');
      int count = 0;
      provider.addListener(() => count++);
      provider.toggleStemRouting('t1', StemType.drums);
      expect(count, greaterThan(0));
    });

    test('clearAll notifies', () {
      provider.registerTrack('t1', 'Test');
      int count = 0;
      provider.addListener(() => count++);
      provider.clearAll();
      expect(count, greaterThan(0));
    });

    test('fromJson notifies', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.fromJson({'routing': [], 'customStems': []});
      expect(count, greaterThan(0));
    });
  });
}
