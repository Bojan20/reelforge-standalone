/// SlotLabGraphs — Default hook graph bindings for standard slot game events.
///
/// Each graph responds to a specific game event and plays appropriate audio.
/// These are the "factory presets" — production games will override with
/// custom graphs loaded from project files.
///
/// ## Event ID Convention:
/// - `spin_start`              — player initiated spin
/// - `reel_stop_{n}`           — reel n (0-4) came to rest
/// - `all_reels_stopped`       — all reels finished
/// - `win_line_small`          — win < 2x bet
/// - `win_line_medium`         — win 2–10x bet
/// - `win_line_big`            — win 10–50x bet
/// - `win_line_mega`           — win > 50x bet
/// - `no_win`                  — spin complete with no win
/// - `feature_enter_freespins` — entering free spins mode
/// - `feature_exit_freespins`  — free spins exhausted
/// - `feature_enter_holdandwin`— entering hold-and-win
/// - `feature_exit_holdandwin` — hold-and-win complete
/// - `feature_enter_cascading` — cascade triggered
/// - `feature_exit_cascading`  — cascade chain ended
/// - `big_win_start`           — big win presentation begins
/// - `big_win_end`             — big win presentation ends
/// - `scatter_land`            — scatter symbol landed
/// - `bonus_trigger`           — bonus game triggered

import 'dart:ui' show Offset;

import 'graph_definition.dart';
import '../../services/hook_graph/hook_graph_service.dart';

// ── Package-level helper to build simple PlaySound graphs ─────────────────

HookGraphDefinition _simpleSoundGraph({
  required String id,
  required String name,
  required String assetPath,
  String bus = 'sfx',
  double volume = 1.0,
  bool looping = false,
}) {
  const entryId = 'entry';
  const soundId = 'sound';

  return HookGraphDefinition(
    id: id,
    name: name,
    nodes: [
      GraphNodeDef(
        id: entryId,
        typeId: 'EventEntry',
        position: const Offset(100, 100),
      ),
      GraphNodeDef(
        id: soundId,
        typeId: 'PlaySound',
        position: const Offset(300, 100),
        parameters: {
          'assetPath': assetPath,
          'bus': bus,
          'volume': volume,
          'looping': looping,
          'priority': 'normal',
        },
      ),
    ],
    connections: [
      const GraphConnection(
        id: 'entry_to_sound',
        fromNodeId: entryId,
        fromPortId: 'trigger',
        toNodeId: soundId,
        toPortId: 'trigger',
      ),
    ],
  );
}

/// Register all default slot lab graphs with [service].
///
/// Pass empty asset paths — graphs without valid paths are silently skipped.
/// Production games replace these with real paths from their asset manifests.
///
/// Call once during SlotLab initialization:
/// ```dart
/// SlotLabGraphs.registerDefaults(sl<HookGraphService>());
/// ```
class SlotLabGraphs {
  SlotLabGraphs._();

  /// Register default graphs and bindings with the given service.
  ///
  /// [assetResolver] — optional callback to map event IDs to asset paths.
  /// If null, graphs are registered with empty paths (no audio playback until
  /// paths are set via project load or asset assignment).
  static void registerDefaults(
    HookGraphService service, {
    String Function(String eventId)? assetResolver,
  }) {
    String pathFor(String eventId) =>
        assetResolver?.call(eventId) ?? '';

    // ── Spin lifecycle ──────────────────────────────────────────────────
    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_spin_start',
        name: 'Spin Start',
        assetPath: pathFor('spin_start'),
        bus: 'sfx',
        volume: 0.9,
      ),
      eventPattern: 'spin_start',
      priority: 0,
    );

    // ── Per-reel stop (wildcard — matches reel_stop_0 through reel_stop_9) ─
    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_reel_stop',
        name: 'Reel Stop',
        assetPath: pathFor('reel_stop'),
        bus: 'sfx',
        volume: 0.85,
      ),
      eventPattern: 'reel_stop_*',
      priority: 0,
    );

    // ── Win tiers ───────────────────────────────────────────────────────
    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_win_small',
        name: 'Win — Small',
        assetPath: pathFor('win_line_small'),
        bus: 'sfx',
        volume: 0.7,
      ),
      eventPattern: 'win_line_small',
      priority: 0,
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_win_medium',
        name: 'Win — Medium',
        assetPath: pathFor('win_line_medium'),
        bus: 'sfx',
        volume: 0.85,
      ),
      eventPattern: 'win_line_medium',
      priority: 0,
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_win_big',
        name: 'Win — Big',
        assetPath: pathFor('win_line_big'),
        bus: 'sfx',
        volume: 1.0,
      ),
      eventPattern: 'win_line_big',
      priority: 0,
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_win_mega',
        name: 'Win — Mega',
        assetPath: pathFor('win_line_mega'),
        bus: 'sfx',
        volume: 1.0,
      ),
      eventPattern: 'win_line_mega',
      priority: 0,
    );

    // ── Feature transitions ─────────────────────────────────────────────
    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_freespins_enter',
        name: 'Free Spins — Enter',
        assetPath: pathFor('feature_enter_freespins'),
        bus: 'music',
        volume: 0.9,
      ),
      eventPattern: 'feature_enter_freespins',
      priority: 10, // higher than generic win sounds
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_freespins_exit',
        name: 'Free Spins — Exit',
        assetPath: pathFor('feature_exit_freespins'),
        bus: 'music',
        volume: 0.8,
      ),
      eventPattern: 'feature_exit_freespins',
      priority: 10,
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_holdandwin_enter',
        name: 'Hold & Win — Enter',
        assetPath: pathFor('feature_enter_holdandwin'),
        bus: 'music',
        volume: 0.9,
      ),
      eventPattern: 'feature_enter_holdandwin',
      priority: 10,
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_holdandwin_exit',
        name: 'Hold & Win — Exit',
        assetPath: pathFor('feature_exit_holdandwin'),
        bus: 'music',
        volume: 0.8,
      ),
      eventPattern: 'feature_exit_holdandwin',
      priority: 10,
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_cascade_start',
        name: 'Cascade — Start',
        assetPath: pathFor('feature_enter_cascading'),
        bus: 'sfx',
        volume: 0.8,
      ),
      eventPattern: 'feature_enter_cascading',
      priority: 5,
    );

    // ── Big Win ──────────────────────────────────────────────────────────
    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_bigwin_start',
        name: 'Big Win — Start',
        assetPath: pathFor('big_win_start'),
        bus: 'sfx',
        volume: 1.0,
      ),
      eventPattern: 'big_win_start',
      priority: 20,
      exclusive: true, // Block lower-priority win sounds during big win
    );

    // ── Scatter / Bonus ──────────────────────────────────────────────────
    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_scatter_land',
        name: 'Scatter Land',
        assetPath: pathFor('scatter_land'),
        bus: 'sfx',
        volume: 0.9,
      ),
      eventPattern: 'scatter_land',
      priority: 5,
    );

    service.registerAndBind(
      _simpleSoundGraph(
        id: 'default_bonus_trigger',
        name: 'Bonus Trigger',
        assetPath: pathFor('bonus_trigger'),
        bus: 'sfx',
        volume: 1.0,
      ),
      eventPattern: 'bonus_trigger',
      priority: 15,
      exclusive: true,
    );
  }

  /// All standard event IDs emitted by the SlotLab hook graph integration.
  static const List<String> standardEventIds = [
    'spin_start',
    'reel_stop_0',
    'reel_stop_1',
    'reel_stop_2',
    'reel_stop_3',
    'reel_stop_4',
    'all_reels_stopped',
    'win_line_small',
    'win_line_medium',
    'win_line_big',
    'win_line_mega',
    'no_win',
    'feature_enter_freespins',
    'feature_exit_freespins',
    'feature_enter_holdandwin',
    'feature_exit_holdandwin',
    'feature_enter_cascading',
    'feature_exit_cascading',
    'big_win_start',
    'big_win_end',
    'scatter_land',
    'bonus_trigger',
  ];
}
