/// Tests for EventRegistrationService — the single composite-event → AudioEvent
/// registration path. See FLUX_MASTER_TODO 1.2.1.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/slot_audio_events.dart';
import 'package:fluxforge_ui/services/event_registration_service.dart';
import 'package:fluxforge_ui/services/event_registry.dart';

SlotEventLayer _layer(String id, {String audio = '/tmp/a.wav', int busId = 2}) =>
    SlotEventLayer(
      id: id,
      name: id,
      audioPath: audio,
      busId: busId,
    );

SlotCompositeEvent _event(
  String id, {
  required List<String> stages,
  List<SlotEventLayer> layers = const [],
}) {
  final now = DateTime.now();
  return SlotCompositeEvent(
    id: id,
    name: id,
    color: const Color(0xFFFFFFFF),
    layers: layers.isNotEmpty ? layers : [_layer('${id}_l1')],
    triggerStages: stages,
    createdAt: now,
    modifiedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EventRegistrationService.registerComposite', () {
    setUp(() {
      EventRegistry.instance.clearAllEvents();
    });

    test('no-op when event is null', () {
      final ids = EventRegistrationService.instance.registerComposite(null);
      expect(ids, isEmpty);
      expect(EventRegistry.instance.registeredEventIds, isEmpty);
    });

    test('no-op when layers are empty', () {
      final ev = SlotCompositeEvent(
        id: 'audio_REEL_STOP',
        name: 'reel stop',
        color: const Color(0xFFFFFFFF),
        layers: const [],
        triggerStages: const ['REEL_STOP'],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      final ids = EventRegistrationService.instance.registerComposite(ev);
      expect(ids, isEmpty);
      expect(EventRegistry.instance.registeredEventIds, isEmpty);
    });

    test('single trigger stage uses event.id directly', () {
      final ev = _event('audio_REEL_STOP', stages: ['reel_stop']);
      final ids = EventRegistrationService.instance.registerComposite(ev);
      // Service returns the canonical IDs it wrote — exactly one for one stage.
      expect(ids, ['audio_REEL_STOP']);
      // The registry MAY auto-spawn per-reel variants (audio_REEL_STOP_0..4)
      // — that's a separate `_registerReelVariants` concern. We only assert
      // that our canonical ID is present.
      expect(EventRegistry.instance.registeredEventIds, contains('audio_REEL_STOP'));
    });

    test('multi-stage event registers per-stage with _stage_N suffix', () {
      final ev = _event(
        'evt_multi',
        stages: ['SPIN_START', 'REEL_STOP', 'BIG_WIN_START'],
      );
      final ids = EventRegistrationService.instance.registerComposite(ev);
      expect(ids, ['evt_multi', 'evt_multi_stage_1', 'evt_multi_stage_2']);
      // Each stage should map to one of the registered events.
      final stages = EventRegistry.instance.registeredStages.toSet();
      expect(stages, containsAll(['SPIN_START', 'REEL_STOP', 'BIG_WIN_START']));
    });

    test('uppercases trigger stages even when stored lowercase', () {
      final ev = _event('audio_reel_stop', stages: ['reel_stop']);
      EventRegistrationService.instance.registerComposite(ev);
      // Triggering with uppercase must find the event — SlotLabProvider
      // always triggers with .toUpperCase().
      expect(EventRegistry.instance.getEventIdForStage('REEL_STOP'), isNotNull);
    });

    test('fallbackStage applies only when triggerStages empty', () {
      final ev = _event('evt_fallback', stages: const []);
      final ids = EventRegistrationService.instance
          .registerComposite(ev, fallbackStage: 'WIN_END');
      expect(ids, ['evt_fallback']);
      expect(EventRegistry.instance.getEventIdForStage('WIN_END'), isNotNull);
    });

    test('no stages and no fallback ⇒ no-op (was a silent dropout source)', () {
      final ev = _event('evt_orphan', stages: const []);
      final ids = EventRegistrationService.instance.registerComposite(ev);
      expect(ids, isEmpty);
      expect(EventRegistry.instance.registeredEventIds, isEmpty);
    });

    test('idempotent — second registration leaves same state, not duplicates', () {
      final ev = _event('audio_X', stages: ['X']);
      EventRegistrationService.instance.registerComposite(ev);
      final after1 = EventRegistry.instance.registeredEventIds.toSet();
      EventRegistrationService.instance.registerComposite(ev);
      final after2 = EventRegistry.instance.registeredEventIds.toSet();
      expect(after2, equals(after1),
          reason: 'second registration must not introduce new IDs');
    });

    test('SlotLab + HELIX register same event ⇒ ONE entry, not eviction', () {
      // The exact race that 1.2.1 describes: two surfaces register the same
      // SlotCompositeEvent through what used to be two parallel code paths.
      // Now both flow through the service ⇒ second call is a no-op rewrite,
      // not an evict-and-replace with a different ID.
      final ev = _event('audio_BIG_WIN', stages: ['BIG_WIN_START']);

      // Simulate slot_lab_screen path
      EventRegistrationService.instance.registerComposite(ev);
      final firstSnapshot =
          EventRegistry.instance.registeredEventIds.toSet();

      // Simulate helix_screen path on the SAME event
      EventRegistrationService.instance.registerComposite(ev);
      final secondSnapshot =
          EventRegistry.instance.registeredEventIds.toSet();

      expect(firstSnapshot, secondSnapshot,
          reason: 'second registration must not change the registry shape');
      expect(firstSnapshot, contains('audio_BIG_WIN'));
      // And the stage still resolves to a real event — not orphaned.
      expect(EventRegistry.instance.getEventIdForStage('BIG_WIN_START'), isNotNull);
    });
  });

  group('EventRegistrationService.unregisterComposite', () {
    setUp(() {
      EventRegistry.instance.clearAllEvents();
    });

    test('clears registrations created via registerComposite', () {
      final ev = _event('evt_multi', stages: ['A', 'B', 'C']);
      EventRegistrationService.instance.registerComposite(ev);
      expect(EventRegistry.instance.registeredEventIds.length, 3);

      EventRegistrationService.instance.unregisterComposite(ev);
      expect(EventRegistry.instance.registeredEventIds, isEmpty);
    });

    test('null event is a safe no-op', () {
      EventRegistrationService.instance.unregisterComposite(null);
      expect(EventRegistry.instance.registeredEventIds, isEmpty);
    });
  });
}
