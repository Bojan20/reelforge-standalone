/// Integration tests for the complete Middleware event lifecycle.
///
/// Tests SlotCompositeEvent creation, layer management, serialization,
/// duplication, and stage mapping — all without FFI dependencies.
@Tags(['integration'])
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge_ui/models/slot_audio_events.dart';
import 'package:fluxforge_ui/models/middleware_models.dart';

void main() {
  group('SlotCompositeEvent — creation', () {
    test('creates event with required fields and correct defaults', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'evt_spin_start', name: 'Spin Start', category: 'spin',
        color: const Color(0xFF4A9EFF), createdAt: now, modifiedAt: now,
      );
      expect(event.id, 'evt_spin_start');
      expect(event.name, 'Spin Start');
      expect(event.category, 'spin');
      expect(event.layers, isEmpty);
      expect(event.masterVolume, 1.0);
      expect(event.looping, false);
      expect(event.maxInstances, 1);
      expect(event.triggerStages, isEmpty);
      expect(event.triggerConditions, isEmpty);
      expect(event.timelinePositionMs, 0.0);
      expect(event.trackIndex, 0);
      expect(event.overlap, true);
      expect(event.crossfadeMs, 500);
    });

    test('creates event with all optional fields', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'evt_music', name: 'Base Music', category: 'music',
        color: const Color(0xFFE91E63), masterVolume: 0.8, targetBusId: 1,
        looping: true, maxInstances: 2, createdAt: now, modifiedAt: now,
        triggerStages: const ['MUSIC_BASE'],
        triggerConditions: const {'win_multiplier': '>= 0'},
        timelinePositionMs: 500.0, trackIndex: 2, overlap: false, crossfadeMs: 250,
      );
      expect(event.masterVolume, 0.8);
      expect(event.targetBusId, 1);
      expect(event.looping, true);
      expect(event.triggerStages, ['MUSIC_BASE']);
      expect(event.overlap, false);
      expect(event.crossfadeMs, 250);
    });

    test('isMusicEvent returns true for music bus and false for SFX', () {
      final now = DateTime.now();
      final musicEvent = SlotCompositeEvent(
        id: 'e1', name: 't', color: Colors.blue,
        createdAt: now, modifiedAt: now, targetBusId: SlotBusIds.music,
      );
      final sfxEvent = SlotCompositeEvent(
        id: 'e2', name: 't', color: Colors.blue,
        createdAt: now, modifiedAt: now, targetBusId: SlotBusIds.sfx,
      );
      expect(musicEvent.isMusicEvent, true);
      expect(sfxEvent.isMusicEvent, false);
    });
  });

  group('SlotEventLayer — creation and properties', () {
    test('creates layer with defaults', () {
      const layer = SlotEventLayer(id: 'l1', name: 'SFX', audioPath: '/a.wav');
      expect(layer.volume, 1.0);
      expect(layer.pan, 0.0);
      expect(layer.offsetMs, 0.0);
      expect(layer.fadeInMs, 0.0);
      expect(layer.fadeOutMs, 0.0);
      expect(layer.fadeInCurve, CrossfadeCurve.linear);
      expect(layer.trimStartMs, 0.0);
      expect(layer.trimEndMs, 0.0);
      expect(layer.muted, false);
      expect(layer.solo, false);
      expect(layer.busId, isNull);
      expect(layer.actionType, 'Play');
      expect(layer.aleLayerId, isNull);
      expect(layer.dspChain, isEmpty);
    });

    test('creates layer with custom properties', () {
      const layer = SlotEventLayer(
        id: 'l2', name: 'Win', audioPath: '/win.wav',
        volume: 0.75, pan: -0.5, offsetMs: 200.0,
        fadeInMs: 50.0, fadeOutMs: 100.0,
        fadeInCurve: CrossfadeCurve.sCurve, fadeOutCurve: CrossfadeCurve.equalPower,
        trimStartMs: 10.0, trimEndMs: 500.0,
        busId: SlotBusIds.wins, aleLayerId: 3, durationSeconds: 2.5,
      );
      expect(layer.volume, 0.75);
      expect(layer.pan, -0.5);
      expect(layer.fadeInCurve, CrossfadeCurve.sCurve);
      expect(layer.fadeOutCurve, CrossfadeCurve.equalPower);
      expect(layer.trimStartMs, 10.0);
      expect(layer.busId, SlotBusIds.wins);
      expect(layer.aleLayerId, 3);
    });

    test('totalDurationMs calculation', () {
      const layer = SlotEventLayer(
        id: 'l1', name: 't', audioPath: '/a.wav', offsetMs: 300.0, durationSeconds: 1.5,
      );
      expect(layer.totalDurationMs, 1800.0); // 1500 + 300

      const noD = SlotEventLayer(id: 'l2', name: 't', audioPath: '/a.wav', offsetMs: 150.0);
      expect(noD.totalDurationMs, 150.0);
    });
  });

  group('SlotEventLayer — copyWith', () {
    test('preserves unchanged fields and updates specified ones', () {
      const original = SlotEventLayer(
        id: 'l1', name: 'Original', audioPath: '/a.wav', volume: 0.8, pan: -0.3, busId: 2,
      );
      final copy = original.copyWith(volume: 0.5);
      expect(copy.volume, 0.5);
      expect(copy.name, 'Original');
      expect(copy.pan, -0.3);
      expect(copy.busId, 2);
    });

    test('can change all fields independently', () {
      const original = SlotEventLayer(id: 'l1', name: 't', audioPath: '/a.wav');
      final copy = original.copyWith(
        id: 'l2', name: 'changed', audioPath: '/b.wav',
        volume: 0.2, pan: 0.8, offsetMs: 100.0,
        muted: true, solo: true, busId: 5, actionType: 'Stop',
      );
      expect(copy.id, 'l2');
      expect(copy.name, 'changed');
      expect(copy.volume, 0.2);
      expect(copy.pan, 0.8);
      expect(copy.muted, true);
      expect(copy.solo, true);
      expect(copy.busId, 5);
      expect(copy.actionType, 'Stop');
    });
  });

  group('SlotCompositeEvent — layer integration', () {
    test('adding layers via copyWith', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'e1', name: 'T', color: Colors.blue, createdAt: now, modifiedAt: now,
      );
      const l1 = SlotEventLayer(id: 'l1', name: 'SFX', audioPath: '/sfx.wav', busId: 2);
      const l2 = SlotEventLayer(id: 'l2', name: 'Mus', audioPath: '/mus.wav', busId: 1, offsetMs: 500);
      final updated = event.copyWith(layers: [l1, l2]);
      expect(updated.layers.length, 2);
      expect(updated.layers[1].offsetMs, 500.0);
    });

    test('totalDurationMs returns longest layer', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'e1', name: 'T', color: Colors.blue, createdAt: now, modifiedAt: now,
        layers: const [
          SlotEventLayer(id: 'l1', name: 'A', audioPath: '/a.wav', durationSeconds: 1.0),
          SlotEventLayer(id: 'l2', name: 'B', audioPath: '/b.wav', durationSeconds: 2.0, offsetMs: 500),
          SlotEventLayer(id: 'l3', name: 'C', audioPath: '/c.wav', durationSeconds: 1.5, offsetMs: 200),
        ],
      );
      expect(event.totalDurationMs, 2500.0); // l2: 2000+500
    });

    test('activeLayerCount excludes muted layers', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'e1', name: 'T', color: Colors.blue, createdAt: now, modifiedAt: now,
        layers: const [
          SlotEventLayer(id: 'l1', name: 'A', audioPath: '/a.wav'),
          SlotEventLayer(id: 'l2', name: 'B', audioPath: '/b.wav', muted: true),
          SlotEventLayer(id: 'l3', name: 'C', audioPath: '/c.wav'),
        ],
      );
      expect(event.activeLayerCount, 2);
    });

    test('playableLayers respects solo mode', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'e1', name: 'T', color: Colors.blue, createdAt: now, modifiedAt: now,
        layers: const [
          SlotEventLayer(id: 'l1', name: 'A', audioPath: '/a.wav'),
          SlotEventLayer(id: 'l2', name: 'B', audioPath: '/b.wav', solo: true),
          SlotEventLayer(id: 'l3', name: 'C', audioPath: '/c.wav'),
        ],
      );
      expect(event.hasSoloedLayer, true);
      expect(event.playableLayers.length, 1);
      expect(event.playableLayers[0].id, 'l2');
    });

    test('muted+soloed layer is excluded from playable', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'e1', name: 'T', color: Colors.blue, createdAt: now, modifiedAt: now,
        layers: const [
          SlotEventLayer(id: 'l1', name: 'A', audioPath: '/a.wav', solo: true, muted: true),
          SlotEventLayer(id: 'l2', name: 'B', audioPath: '/b.wav', solo: true),
        ],
      );
      expect(event.playableLayers.length, 1);
      expect(event.playableLayers[0].id, 'l2');
    });
  });

  group('SlotCompositeEvent — duplication independence', () {
    test('copyWith creates independent copy', () {
      final now = DateTime.now();
      final original = SlotCompositeEvent(
        id: 'orig', name: 'Original', color: Colors.red,
        createdAt: now, modifiedAt: now,
        layers: const [SlotEventLayer(id: 'l1', name: 'L1', audioPath: '/a.wav', volume: 0.8)],
        triggerStages: const ['SPIN_START'],
      );
      final dup = original.copyWith(id: 'dup', name: 'Dup');
      expect(dup.id, 'dup');
      expect(dup.layers[0].volume, 0.8);
      expect(original.id, 'orig');
      expect(original.name, 'Original');
    });
  });

  group('SlotCompositeEvent — layer deletion', () {
    test('removing by filter leaves correct layers', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'e1', name: 'T', color: Colors.blue, createdAt: now, modifiedAt: now,
        layers: const [
          SlotEventLayer(id: 'l1', name: 'A', audioPath: '/a.wav'),
          SlotEventLayer(id: 'l2', name: 'B', audioPath: '/b.wav'),
          SlotEventLayer(id: 'l3', name: 'C', audioPath: '/c.wav'),
        ],
      );
      final updated = event.copyWith(layers: event.layers.where((l) => l.id != 'l2').toList());
      expect(updated.layers.map((l) => l.id), ['l1', 'l3']);
    });

    test('removing all layers yields empty event', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'e1', name: 'T', color: Colors.blue, createdAt: now, modifiedAt: now,
        layers: const [SlotEventLayer(id: 'l1', name: 'A', audioPath: '/a.wav')],
      );
      final updated = event.copyWith(layers: []);
      expect(updated.layers, isEmpty);
      expect(updated.totalDurationMs, 0.0);
    });
  });

  group('SlotCompositeEvent — JSON roundtrip', () {
    test('full roundtrip preserves all fields', () {
      final now = DateTime(2026, 2, 10, 12, 0, 0);
      final original = SlotCompositeEvent(
        id: 'evt_test', name: 'Test', category: 'spin',
        color: const Color(0xFF4A9EFF),
        layers: const [
          SlotEventLayer(
            id: 'l1', name: 'SFX', audioPath: '/sfx/hit.wav',
            volume: 0.85, pan: 0.3, offsetMs: 100.0,
            fadeInMs: 20.0, fadeOutMs: 50.0,
            fadeInCurve: CrossfadeCurve.sCurve, fadeOutCurve: CrossfadeCurve.equalPower,
            trimStartMs: 5.0, trimEndMs: 800.0,
            busId: 2, aleLayerId: 2, durationSeconds: 1.5,
          ),
        ],
        masterVolume: 0.9, targetBusId: 2, looping: true, maxInstances: 3,
        createdAt: now, modifiedAt: now,
        triggerStages: const ['SPIN_START', 'REEL_STOP_0'],
        triggerConditions: const {'tension': '>= 5'},
        timelinePositionMs: 250.0, trackIndex: 1, overlap: false, crossfadeMs: 300,
      );

      final restored = SlotCompositeEvent.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.category, original.category);
      expect(restored.masterVolume, original.masterVolume);
      expect(restored.targetBusId, original.targetBusId);
      expect(restored.looping, original.looping);
      expect(restored.maxInstances, original.maxInstances);
      expect(restored.triggerStages, original.triggerStages);
      expect(restored.overlap, original.overlap);
      expect(restored.crossfadeMs, original.crossfadeMs);

      final layer = restored.layers[0];
      expect(layer.volume, 0.85);
      expect(layer.pan, 0.3);
      expect(layer.fadeInCurve, CrossfadeCurve.sCurve);
      expect(layer.trimStartMs, 5.0);
      expect(layer.aleLayerId, 2);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'minimal', 'name': 'Minimal',
        'createdAt': DateTime.now().toIso8601String(),
        'modifiedAt': DateTime.now().toIso8601String(),
      };
      final event = SlotCompositeEvent.fromJson(json);
      expect(event.category, 'general');
      expect(event.layers, isEmpty);
      expect(event.masterVolume, 1.0);
      expect(event.overlap, true);
    });
  });

  group('SlotEventLayer — DSP chain JSON', () {
    test('roundtrip with DSP chain', () {
      final original = SlotEventLayer(
        id: 'l1', name: 'P', audioPath: '/a.wav', volume: 0.7,
        dspChain: [LayerDspNode.create(LayerDspType.eq), LayerDspNode.create(LayerDspType.compressor)],
      );
      final restored = SlotEventLayer.fromJson(original.toJson());
      expect(restored.dspChain.length, 2);
      expect(restored.dspChain[0].type, LayerDspType.eq);
      expect(restored.dspChain[1].type, LayerDspType.compressor);
    });

    test('hasDsp and activeDspNodes filter bypassed', () {
      final layer = SlotEventLayer(
        id: 'l1', name: 't', audioPath: '/a.wav',
        dspChain: const [
          LayerDspNode(id: 'd1', type: LayerDspType.eq, bypass: false),
          LayerDspNode(id: 'd2', type: LayerDspType.reverb, bypass: true),
          LayerDspNode(id: 'd3', type: LayerDspType.compressor, bypass: false),
        ],
      );
      expect(layer.hasDsp, true);
      expect(layer.activeDspNodes.length, 2);
    });
  });

  group('Stage mapping — SlotEventIds', () {
    test('ID ranges are non-overlapping', () {
      expect(SlotEventIds.spinStart, inInclusiveRange(1000, 1099));
      expect(SlotEventIds.winPresent, inInclusiveRange(1200, 1299));
      expect(SlotEventIds.bigWinBase, inInclusiveRange(1300, 1399));
      expect(SlotEventIds.featureEnter, inInclusiveRange(1400, 1499));
      expect(SlotEventIds.cascadeStart, inInclusiveRange(1500, 1599));
      expect(SlotEventIds.bonusEnter, inInclusiveRange(1600, 1699));
      expect(SlotEventIds.gambleStart, inInclusiveRange(1700, 1799));
      expect(SlotEventIds.jackpotTrigger, inInclusiveRange(1800, 1899));
      expect(SlotEventIds.idleStart, inInclusiveRange(1900, 1999));
    });

    test('bus IDs are all unique', () {
      final ids = {
        SlotBusIds.master, SlotBusIds.music, SlotBusIds.sfx, SlotBusIds.voice,
        SlotBusIds.ui, SlotBusIds.reels, SlotBusIds.wins, SlotBusIds.anticipation,
      };
      expect(ids.length, 8);
    });
  });

  group('SlotAudioEventFactory', () {
    test('createAllEvents returns empty list', () {
      expect(SlotAudioEventFactory.createAllEvents(), isEmpty);
    });

    test('createFromTemplates generates all categories', () {
      final events = SlotAudioEventFactory.createFromTemplates();
      expect(events.isNotEmpty, true);
      final cats = events.map((e) => e.category).toSet();
      expect(cats, containsAll(['Slot_Gameplay', 'Slot_Win', 'Slot_BigWin',
        'Slot_Feature', 'Slot_Bonus', 'Slot_Gamble', 'Slot_Jackpot', 'Slot_UI']));
    });

    test('big win events have 5 tiers', () {
      final bw = SlotAudioEventFactory.createBigWinEvents();
      expect(bw.length, 5);
      for (final e in bw) { expect(e.category, 'Slot_BigWin'); }
    });
  });

  group('SlotEventTemplates', () {
    test('allTemplates returns 10 unique templates', () {
      final templates = SlotEventTemplates.allTemplates();
      expect(templates.length, 10);
      final ids = templates.map((t) => t.id).toSet();
      expect(ids.length, 10);
    });

    test('anticipation template loops', () {
      expect(SlotEventTemplates.anticipation().looping, true);
    });

    test('reel stop templates are numbered 1-5', () {
      for (int i = 1; i <= 5; i++) {
        final t = SlotEventTemplates.reelStop(i);
        expect(t.id, 'template_reel_stop_$i');
        expect(t.name, 'Reel $i Stop');
      }
    });
  });

  group('SlotEventCategory enum', () {
    test('all categories have distinct display names', () {
      final names = SlotEventCategory.values.map((c) => c.displayName).toSet();
      expect(names.length, SlotEventCategory.values.length);
    });

    test('all categories have non-transparent colors', () {
      for (final c in SlotEventCategory.values) {
        expect(c.color.alpha, greaterThan(0));
      }
    });
  });

  group('MiddlewareEvent and MiddlewareAction', () {
    test('ActionType covers 20+ types', () {
      expect(ActionType.values.length, greaterThanOrEqualTo(20));
      expect(ActionType.values, contains(ActionType.play));
      expect(ActionType.values, contains(ActionType.stop));
      expect(ActionType.values, contains(ActionType.setVolume));
      expect(ActionType.values, contains(ActionType.setRTPC));
    });

    test('event creation with actions', () {
      final event = MiddlewareEvent(
        id: 'test', name: 'Test', category: 'test',
        actions: [
          MiddlewareAction(id: 'a1', type: ActionType.play, assetId: 'sfx_test', bus: 'SFX'),
          MiddlewareAction(id: 'a2', type: ActionType.setVolume, bus: 'Music', gain: 0.5, fadeTime: 0.3),
        ],
      );
      expect(event.actions.length, 2);
      expect(event.actions[0].type, ActionType.play);
      expect(event.actions[1].gain, 0.5);
    });
  });
}
