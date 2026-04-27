/// EventRegistrationService — single point that turns a SlotCompositeEvent
/// into AudioEvent registrations inside the central [EventRegistry].
///
/// ## Why this exists
///
/// Before this service we had **three** parallel registration paths writing
/// into `EventRegistry._stageToEvent` with different ID formats:
///
///   1. `slot_lab_screen.dart::_syncEventToRegistry`
///        → `event.id` keyed (`audio_REEL_STOP`, `evt_<uuid>`)
///   2. `helix_screen.dart::_registerToEventRegistry`
///        → `event.id` keyed (same shape, different code path)
///   3. `EventAutoRegistrar.registerAll` (template gallery)
///        → `evt_<stage_lower>` keyed
///
/// `_stageToEvent` is keyed by stage, with **one event per stage**. When two
/// of those paths register events for the same stage with different IDs,
/// the second write silently evicts the first — no error, no log, just
/// silent audio dropout (FLUX_MASTER_TODO 1.2.1, P0). Triggering a stage
/// then plays whichever event won the race, or nothing if the loser was
/// the one that owned the audio assignment.
///
/// ## Contract
///
/// All UI surfaces (SlotLab, HELIX, future contenders) MUST call
/// [registerComposite] / [unregisterComposite] instead of poking
/// `EventRegistry.registerEvent` directly. Direct callers are still
/// allowed but must use **non-stage IDs** (e.g. template-gallery prefix)
/// so they can't collide with composite-event registrations.
///
/// CLAUDE.md "SlotLab — EventRegistry registracija (KRITIČNO)" rule is
/// enforced by routing every composite registration through this single
/// method. The method is idempotent: calling it twice with the same
/// composite event leaves the registry in the same state as one call.
library;

import '../models/slot_audio_events.dart';
import 'event_registry.dart';

/// Shared logic for translating SlotCompositeEvent → AudioEvent + register.
class EventRegistrationService {
  EventRegistrationService._();
  static final EventRegistrationService instance = EventRegistrationService._();

  EventRegistry get _registry => EventRegistry.instance;

  /// Register one composite event under all of its trigger stages.
  ///
  /// Behavior matches the canonical implementation that lived in
  /// `slot_lab_screen.dart::_syncEventToRegistry` before consolidation:
  ///
  /// * No layers ⇒ no-op (nothing to play).
  /// * If `triggerStages` is non-empty ⇒ uppercase, register one AudioEvent
  ///   per stage. First stage uses `event.id`; subsequent stages append
  ///   `_stage_<i>` so each can be unregistered independently.
  /// * If `triggerStages` is empty and [fallbackStage] is non-null ⇒ register
  ///   under that single stage with `event.id`. Useful for HELIX / SlotLab
  ///   where the screen knows the effective stage even when the model has
  ///   none.
  /// * If both are empty ⇒ no-op (nothing routes to it).
  ///
  /// Returns the list of AudioEvent IDs that were written. Empty list means
  /// no-op. Pass [skipNotify] when registering in a batch — the caller is
  /// responsible for emitting the final notification.
  List<String> registerComposite(
    SlotCompositeEvent? event, {
    String? fallbackStage,
    bool skipNotify = false,
  }) {
    if (event == null || event.layers.isEmpty) return const [];

    // Resolve effective stages (uppercase, normalized).
    final List<String> stages;
    if (event.triggerStages.isNotEmpty) {
      stages = event.triggerStages
          .map((s) => s.toUpperCase())
          .toList(growable: false);
    } else if (fallbackStage != null && fallbackStage.isNotEmpty) {
      stages = [fallbackStage.toUpperCase()];
    } else {
      return const [];
    }

    // Build AudioLayer list once — same shape used by both former call sites.
    final layers = event.layers.map((l) => AudioLayer(
          id: l.id,
          audioPath: l.audioPath,
          name: l.name,
          volume: l.volume,
          pan: l.pan,
          panRight: l.panRight,
          stereoWidth: l.stereoWidth,
          inputGain: l.inputGain,
          phaseInvert: l.phaseInvert,
          delay: l.offsetMs,
          busId: l.busId ?? 2, // SFX default
          fadeInMs: l.fadeInMs,
          fadeOutMs: l.fadeOutMs,
          trimStartMs: l.trimStartMs,
          trimEndMs: l.trimEndMs,
          actionType: l.actionType,
          loop: l.loop,
          targetAudioPath: l.targetAudioPath,
        )).toList();

    final fallbackBus = event.targetBusId ?? (layers.isNotEmpty ? layers.first.busId : 2);

    final ids = <String>[];
    for (int i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final eventId = i == 0 ? event.id : '${event.id}_stage_$i';
      final audioEvent = AudioEvent(
        id: eventId,
        name: event.name,
        stage: stage,
        layers: layers,
        loop: event.looping,
        overlap: event.overlap,
        crossfadeMs: event.crossfadeMs,
        targetBusId: fallbackBus,
      );
      _registry.registerEvent(audioEvent, skipNotify: skipNotify);
      ids.add(eventId);
    }
    return ids;
  }

  /// Unregister one composite event from all of its trigger-stage slots.
  ///
  /// Mirrors [registerComposite] so a former register call can be undone
  /// without leaving zombie stage entries that would later silently shadow
  /// a fresh registration.
  void unregisterComposite(SlotCompositeEvent? event) {
    if (event == null) return;
    _registry.unregisterEvent(event.id);
    final extra = event.triggerStages.length;
    for (int i = 1; i < extra; i++) {
      _registry.unregisterEvent('${event.id}_stage_$i');
    }
  }
}
