/// AutoBindCompositeBuilder — UI-independent composite event creator.
///
/// ## Why this exists
///
/// Before this builder, post-bind composite-event creation lived inside
/// `SlotLabScreen._ensureCompositeEventForStage`, which can only run when
/// the user is actively on the SlotLab tab.  In HELIX (where the
/// `NeuralBindOrb` is also rendered) `_SlotLabScreenState._activeInstance`
/// is `null`, so `SlotLabScreen.triggerAutoBindReload(...)` becomes a
/// silent no-op — `applyAutoBindTransaction` writes the project provider
/// audio assignments, but nothing ever creates the `SlotCompositeEvent`s
/// that the `EventRegistry` plays from.
///
/// The result is the well-known "auto-bind succeeded but SPIN is silent"
/// bug: `_lastTriggerError = 'No audio layers'`, `voices count = 0`,
/// `byStage[REEL_STOP] = {}`.
///
/// This service runs the *same* layer-building logic as
/// `_ensureCompositeEventForStage`, but without a `BuildContext` —
/// providers are reached through `GetIt`, registration goes through
/// [EventRegistrationService] (the single point that owns
/// `EventRegistry._stageToEvent`).  Calling `buildAndRegister` from any
/// thread that has the GetIt registry produces a fully playable composite
/// event, so the orb works identically in SlotLab and HELIX.
///
/// CLAUDE.md "SlotLab — EventRegistry registracija (KRITIČNO)" still holds:
/// every register call goes through [EventRegistrationService.registerComposite],
/// no second registration path is introduced.
library;

import 'dart:ui' show Color;

import 'package:get_it/get_it.dart';

import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../event_registration_service.dart';
import '../ffnc/stage_defaults.dart';
import '../stage_configuration_service.dart';

/// Builds and registers `SlotCompositeEvent`s from auto-bind primary
/// bindings without any UI state.
class AutoBindCompositeBuilder {
  AutoBindCompositeBuilder._();
  static final AutoBindCompositeBuilder instance = AutoBindCompositeBuilder._();

  /// Build, persist, and register a composite event for one stage→audio
  /// mapping.  Idempotent per stage (re-call replaces the previous
  /// composite + re-registers the same `EventRegistry` slot).
  ///
  /// * Skips `GAME_START` — that composite is already produced inside
  ///   `SlotLabProjectProvider._createBaseGameMusicComposite` because
  ///   it needs the multi-layer L1..L5 fan-out (different shape).
  /// * `BIG_WIN_START` / `BIG_WIN_END` are also skipped here to keep
  ///   their music-layer ducking semantics owned by the SlotLab path.
  ///   When that screen is mounted it will replace this composite with
  ///   the richer one; when it isn't, the simple play-the-clip variant
  ///   is still better than silence.
  ///
  /// Returns the registered composite event id, or `null` if no event
  /// was created (provider missing, stage filtered, audio path empty).
  String? buildAndRegister({
    required String stage,
    required String audioPath,
    bool skipNotify = false,
  }) {
    if (audioPath.isEmpty) return null;
    if (stage == 'GAME_START') return null;

    final sl = GetIt.instance;
    if (!sl.isRegistered<MiddlewareProvider>()) return null;
    final mw = sl<MiddlewareProvider>();

    // ─── 2026-05-09 — RAW MODE ────────────────────────────────────────
    //
    // Boki: "čuju se zvukovi, ali se seku, neki kraći, neki tiši —
    // moraju da se puste kakvi su u originalnom stanju".
    //
    // Smart-defaults (`StageDefaults`) primenjuju fadeOut=100ms, smart
    // pan, ducking, crossfade — sve to MENJA original.  Auto-bind je
    // import putanja, ne mixing decision: korisnik je pažljivo nasnimio
    // fajl, naš posao je da ga emitujemo neoštećenog.  Sve modifikacije
    // ide kroz manual layer edit, ne kroz auto-build.
    //
    // Pošto REEL_STOP_<i> u StageConfigurationService ima `isPooled=true`
    // (pool steal-ovanje sečaše prvi voice kad par reels stane u rapid
    // succession), takođe overlap=true tako da druga voice ne ubija prvu.
    final stageCfg = StageConfigurationService.instance;
    final stageDef = stageCfg.getStage(stage);
    final isMusicBus = stageDef?.bus.toString().toLowerCase().contains('music') ?? false;
    final shouldLoop = stageCfg.isLooping(stage);

    // ─── 2026-05-09 — Disable pool steal for raw playback ────────────
    //
    // REEL_STOP_<i>, ROLLUP_TICK*, CASCADE_STEP*, SYMBOL_WIN... ship with
    // `isPooled=true` so rapid retriggers reuse a small voice pool.  But
    // pool reuse runs through `AudioPool._playVoice` which spawns a
    // fresh FFI voice without resetting the previous one's fade/trim
    // state — and pool steal can truncate the voice that's still
    // playing when 5 reels stop in quick succession (Boki's "neki kraći,
    // neki tiši").  Auto-bind import is by definition not rapid-fire
    // (one play per stage trigger), so we override the stage definition
    // to pool=false ONLY for stages we just bound.  Manual edits in the
    // ASSIGN spine still see the original stage config — this is a
    // builder-time toggle.
    if (stageDef != null && stageDef.isPooled) {
      stageCfg.registerCustomStage(
        stageDef.copyWith(isPooled: false),
        silent: true,
      );
    }
    final isBigWinTransition =
        stage == 'BIG_WIN_START' || stage == 'BIG_WIN_END';
    // Bus selection: stick with the StageDefault bus assignment so
    // routing/mixer settings still apply, but everything else is RAW.
    final busId = StageDefaults.getDefaultForStage(stage).busId;
    final crossfadeMs = isBigWinTransition ? 500 : 0;
    final effectiveTargetBus = isBigWinTransition ? SlotBusIds.music : busId;
    final effectiveLoop = stage == 'BIG_WIN_START' ? true : shouldLoop;
    // overlap=true so a second REEL_STOP_<i> (or rapid retrigger of any
    // pooled stage) doesn't truncate the previous voice — every clip
    // plays out to its natural end at full length.
    const shouldOverlap = true;

    // Build layers — primary Play layer ONLY, raw playback.
    // No fadeIn, no fadeOut, no per-reel pan, no music ducking.  The
    // file plays at its native volume/pan/length so import sounds match
    // their on-disk state byte-for-byte (modulo bus + master volume,
    // which are user-controlled in the mixer).
    final layers = <SlotEventLayer>[
      SlotEventLayer(
        id: 'layer_$stage',
        name: _layerNameFromPath(audioPath),
        audioPath: audioPath,
        actionType: 'Play',
        volume: 1.0,
        pan: 0.0,
        panRight: 0.0,
        busId: busId,
        loop: effectiveLoop,
        fadeInMs: 0.0,
        fadeOutMs: 0.0,
      ),
    ];
    // Suppress unused warning while keeping isMusicBus available for
    // future tweaks (e.g. per-bus crossfade decisions).
    // ignore: unused_local_variable
    final _isMusicBus = isMusicBus;

    final eventId = 'audio_$stage';
    final now = DateTime.now();
    final category = _categoryForStage(stage);
    final color = _colorForCategory(category);
    final displayName =
        StageConfigurationService.instance.getDisplayLabel(stage);

    // Replace policy: if a composite already targets this stage (by id or
    // by trigger-stage match) update it instead of duplicating.  Mirrors
    // `_ensureCompositeEventForStage` so the SlotLab / HELIX paths are
    // observationally identical.
    SlotCompositeEvent? existing =
        mw.compositeEvents.where((e) => e.id == eventId).firstOrNull;
    existing ??= mw.compositeEvents
        .where((e) => e.triggerStages
            .any((s) => s.toUpperCase() == stage.toUpperCase()))
        .firstOrNull;

    if (existing != null) {
      // Preserve manual layers (anything that's not one of ours)
      final autoIds = layers.map((l) => l.id).toSet();
      final manual = existing.layers
          .where((l) => !autoIds.contains(l.id) && l.id != 'layer_$stage')
          .toList();
      final merged = [...layers, ...manual];

      final updated = existing.copyWith(
        name: displayName,
        layers: merged,
        overlap: shouldOverlap,
        targetBusId: effectiveTargetBus,
        looping: effectiveLoop,
        crossfadeMs: crossfadeMs,
        modifiedAt: now,
      );
      mw.updateCompositeEvent(updated, skipUndo: true, skipNotify: true);
      EventRegistrationService.instance
          .registerComposite(updated, skipNotify: skipNotify);
      return updated.id;
    }

    final created = SlotCompositeEvent(
      id: eventId,
      name: displayName,
      category: category,
      color: color,
      layers: layers,
      triggerStages: [stage],
      targetBusId: effectiveTargetBus,
      looping: effectiveLoop,
      overlap: shouldOverlap,
      crossfadeMs: crossfadeMs,
      createdAt: now,
      modifiedAt: now,
    );
    mw.addCompositeEvent(created,
        select: false, skipUndo: true, skipNotify: true);
    EventRegistrationService.instance
        .registerComposite(created, skipNotify: skipNotify);
    return created.id;
  }

  /// Build composites for an entire `primaryBindings` map (the shape that
  /// `AutoBindEngine.apply` already prepares).  Single notify at the end
  /// keeps the UI from thrashing on every stage.
  void buildAndRegisterAll(Map<String, String> primaryBindings) {
    if (primaryBindings.isEmpty) return;
    for (final entry in primaryBindings.entries) {
      buildAndRegister(
        stage: entry.key,
        audioPath: entry.value,
        skipNotify: true,
      );
    }
    final sl = GetIt.instance;
    if (sl.isRegistered<MiddlewareProvider>()) {
      sl<MiddlewareProvider>().notifyCompositeEventsChanged();
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────

  String _layerNameFromPath(String audioPath) {
    final base = audioPath.split('/').last;
    return base.replaceAll(RegExp(r'\.[^.]+$'), '');
  }

  /// Per-reel stereo spread for REEL_STOP_0..4, otherwise StageDefaults pan.
  double _panForStage(String stage, double fallback) {
    switch (stage) {
      case 'REEL_STOP_0':
        return -0.8;
      case 'REEL_STOP_1':
        return -0.4;
      case 'REEL_STOP_2':
        return 0.0;
      case 'REEL_STOP_3':
        return 0.4;
      case 'REEL_STOP_4':
        return 0.8;
    }
    return fallback;
  }

  String _categoryForStage(String stage) {
    final s = stage.toUpperCase();
    if (s.startsWith('SPIN_') || s.startsWith('REEL_')) return 'spin';
    if (s.startsWith('WIN_') || s.startsWith('ROLLUP_')) return 'win';
    if (s.startsWith('FS_')) return 'feature';
    if (s.startsWith('BONUS_')) return 'bonus';
    if (s.startsWith('CASCADE_') || s.startsWith('TUMBLE_')) return 'cascade';
    if (s.startsWith('JACKPOT_')) return 'jackpot';
    if (s.startsWith('HOLD_') || s.startsWith('RESPIN_')) return 'hold';
    if (s.startsWith('GAMBLE_')) return 'gamble';
    if (s.startsWith('UI_') || s.startsWith('BUTTON_')) return 'ui';
    if (s.startsWith('MUSIC_') ||
        s.startsWith('AMBIENT_') ||
        s.startsWith('BIG_WIN') ||
        s == 'GAME_START') {
      return 'music';
    }
    if (s.startsWith('SYMBOL_') ||
        s.startsWith('WILD_') ||
        s.startsWith('SCATTER_')) {
      return 'symbol';
    }
    if (s.startsWith('ANTICIPATION_') || s.startsWith('NEAR_MISS')) {
      return 'anticipation';
    }
    return 'general';
  }

  Color _colorForCategory(String category) {
    switch (category) {
      case 'spin':
        return const Color(0xFF4CAF50);
      case 'win':
        return const Color(0xFFFFD700);
      case 'feature':
        return const Color(0xFF9C27B0);
      case 'bonus':
        return const Color(0xFFE91E63);
      case 'cascade':
        return const Color(0xFF00BCD4);
      case 'jackpot':
        return const Color(0xFFFF5722);
      case 'hold':
        return const Color(0xFF3F51B5);
      case 'gamble':
        return const Color(0xFFFF9800);
      case 'ui':
        return const Color(0xFF607D8B);
      case 'music':
        return const Color(0xFF673AB7);
      case 'symbol':
        return const Color(0xFF2196F3);
      case 'anticipation':
        return const Color(0xFFF44336);
      default:
        return const Color(0xFF9E9E9E);
    }
  }
}
