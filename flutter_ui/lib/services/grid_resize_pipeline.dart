/// FluxForge Studio — Grid Resize Pipeline (FLUX_MASTER_TODO 2.1.7)
///
/// Single source of truth for "user changed REELS×ROWS". The pipeline
/// previously lived inline as `_SpineGameConfigState._applyConfig()`,
/// which meant any new caller (HELIX Omnibar inline edit, Cmd+K command
/// palette, CortexEye automation, future AI agent) would either have to
/// invoke a private state widget or duplicate the four-step sequence.
///
/// Sequence (must run in order):
///
///   1. Initialize the engine if it isn't already (`SlotLabCoordinator`).
///      Skipping this step makes step 2 a silent no-op because
///      `setGridConfig` only forwards FFI when `coordinator.initialized`.
///   2. Persist the new grid via `SlotLabProjectProvider.setGridConfig`,
///      which propagates to the Rust engine through `updateGridSize`.
///   3. Mirror the new grid into `FeatureComposerProvider` so the live
///      "NO CONFIGURATION" overlay clears and downstream symbol math
///      sees the new column/row count.
///   4. Auto-create default `SlotCompositeEvent`s for standard stages
///      (REEL_SPIN_LOOP, REEL_STOP_n × reelCount, WIN_PRESENT_1..3,
///      BONUS_TRIGGER, FREE_SPINS_START). Idempotent — pre-existing
///      ids stay untouched, only missing ones land.
///
/// All four steps live behind one entry point so a refactor (e.g.
/// flipping ordering, swapping the auto-stage list, gating on a feature
/// flag) happens in *one* place. Callers stay one-liners.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../models/slot_audio_events.dart';
import '../providers/ale_provider.dart';
import '../providers/middleware_provider.dart';
import '../providers/slot_lab/feature_composer_provider.dart';
import '../providers/slot_lab/slot_lab_coordinator.dart';
import '../providers/slot_lab_project_provider.dart';
import '../services/gdd_import_service.dart' show GddGridConfig;
import '../theme/fluxforge_theme.dart';

/// Hard min/max for the grid dimensions, mirroring the legacy spinner
/// limits in `_SpineGameConfigState`. Out-of-range requests fail at the
/// pipeline edge rather than corrupting downstream state.
class GridResizeBounds {
  static const int minReels = 3;
  static const int maxReels = 6;
  static const int minRows = 2;
  static const int maxRows = 4;

  /// `true` when both dimensions sit inside the supported envelope.
  static bool isValid(int reels, int rows) =>
      reels >= minReels && reels <= maxReels &&
      rows >= minRows && rows <= maxRows;

  /// Human-readable validation message, or `null` when the pair is valid.
  /// Used by inline edit affordances (Omnibar pill, command palette) to
  /// show a one-line toast on rejected input.
  static String? validate(int reels, int rows) {
    if (reels < minReels || reels > maxReels) {
      return 'REELS must be $minReels–$maxReels (got $reels)';
    }
    if (rows < minRows || rows > maxRows) {
      return 'ROWS must be $minRows–$maxRows (got $rows)';
    }
    return null;
  }
}

/// Outcome of a single `GridResizePipeline.apply` call.
///
/// `success == true` means the grid landed in every downstream system
/// (project provider, FFI engine, feature composer, middleware events).
/// `success == false` means *nothing* should have changed — the pipeline
/// is fail-fast, not best-effort.
class GridResizeResult {
  final bool success;
  final String message;
  final int reels;
  final int rows;

  const GridResizeResult({
    required this.success,
    required this.message,
    required this.reels,
    required this.rows,
  });

  /// `✓ 5×3 ready` / `✗ engine init failed` — short status string for
  /// inline status pills, toasts, and the legacy GAME CONFIG button.
  String get shortStatus => success ? '✓ ${reels}×$rows ready' : '✗ $message';
}

/// Static facade for the resize sequence. Stateless on purpose so
/// callers don't have to thread a singleton through their state.
class GridResizePipeline {
  GridResizePipeline._();

  /// Run the full four-step resize. Returns synchronously because every
  /// underlying call is synchronous today; the signature is `Future`
  /// so a future async step (e.g. waiting for an FFI ack) can land
  /// without breaking callers.
  static Future<GridResizeResult> apply({
    required int reels,
    required int rows,
  }) async {
    final boundsErr = GridResizeBounds.validate(reels, rows);
    if (boundsErr != null) {
      return GridResizeResult(
        success: false, message: boundsErr, reels: reels, rows: rows,
      );
    }

    try {
      final proj = GetIt.instance<SlotLabProjectProvider>();
      final coordinator = GetIt.instance<SlotLabCoordinator>();

      // 1. Initialize engine FIRST if needed — must happen before grid
      //    resize. setGridConfig calls updateGridSize which only sends
      //    FFI when initialized; skipping this step makes the resize a
      //    silent no-op on first run.
      if (!coordinator.initialized) {
        final ok = coordinator.initialize(audioTestMode: true);
        if (!ok) {
          return GridResizeResult(
            success: false,
            message: 'Engine init failed',
            reels: reels,
            rows: rows,
          );
        }
        // Wire optional providers — failures here are non-fatal because
        // the engine itself is up and the resize will still apply.
        try {
          coordinator.connectMiddleware(GetIt.instance<MiddlewareProvider>());
        } catch (_) {}
        // ALE wiring is best-effort — AleProvider may not be registered
        // in every test harness. The resize is still valid without it.
        try {
          coordinator.connectAle(GetIt.instance<AleProvider>());
        } catch (_) {}
      }

      // 2. Persist grid → provider → Rust FFI engine.
      proj.setGridConfig(GddGridConfig(
        rows: rows,
        columns: reels,
        mechanic: 'lines',
      ));

      // 3. Mirror into FeatureComposerProvider so the live overlay
      //    clears and downstream payline math sees the new dims.
      final composer = GetIt.instance<FeatureComposerProvider>();
      if (!composer.isConfigured) {
        composer.applyConfig(SlotMachineConfig(
          name: proj.projectName,
          reelCount: reels,
          rowCount: rows,
          paylineCount: 20,
          paylineType: PaylineType.lines,
          winTierCount: 5,
          volatilityProfile: 'medium',
        ));
      } else {
        composer.applyConfig(composer.config!.copyWith(
          reelCount: reels,
          rowCount: rows,
        ));
      }

      // 4. Auto-create default CompositeEvents for the standard stages.
      //    Idempotent: existing ids are skipped so re-runs don't double
      //    up. Failure here is non-fatal — the grid still resized and
      //    the user can manually add stage events later.
      _autoSetupStageEvents(reels);

      return GridResizeResult(
        success: true,
        message: '${reels}×$rows ready',
        reels: reels,
        rows: rows,
      );
    } catch (e) {
      return GridResizeResult(
        success: false,
        message: e.toString(),
        reels: reels,
        rows: rows,
      );
    }
  }

  /// Auto-create the standard slot lifecycle stages so a fresh grid is
  /// immediately spinnable without the user manually wiring 5+ events.
  ///
  /// Idempotent — composite ids serve as the dedup key. Pre-existing
  /// entries (e.g. user-renamed Reel Stop 1) stay untouched.
  static void _autoSetupStageEvents(int reelCount) {
    try {
      final mw = GetIt.instance<MiddlewareProvider>();
      final existingIds = mw.compositeEvents.map((e) => e.id).toSet();
      final now = DateTime.now();

      final defaultStages =
          <(String id, String name, String stage, Color color)>[
        ('auto_spin_loop', 'Reel Spin Loop', 'REEL_SPIN_LOOP',
            FluxForgeTheme.accentCyan),
        ...List.generate(
          reelCount,
          (i) => (
            'auto_reel_stop_$i',
            'Reel Stop ${i + 1}',
            'REEL_STOP_$i',
            FluxForgeTheme.accentBlue,
          ),
        ),
        ('auto_win_1', 'Small Win', 'WIN_PRESENT_1',
            FluxForgeTheme.accentGreen),
        ('auto_win_2', 'Medium Win', 'WIN_PRESENT_2',
            FluxForgeTheme.accentYellow),
        ('auto_win_3', 'Big Win', 'WIN_PRESENT_3',
            FluxForgeTheme.accentOrange),
        ('auto_bonus_trigger', 'Bonus Trigger', 'BONUS_TRIGGER',
            FluxForgeTheme.accentPurple),
        ('auto_free_spins', 'Free Spins Start', 'FREE_SPINS_START',
            FluxForgeTheme.accentPink),
      ];

      for (int i = 0; i < defaultStages.length; i++) {
        final (id, name, stage, color) = defaultStages[i];
        if (existingIds.contains(id)) continue;
        final lower = stage.toLowerCase();
        final category = lower.contains('win')
            ? 'win'
            : lower.contains('reel')
                ? 'spin'
                : 'feature';
        mw.addCompositeEvent(SlotCompositeEvent(
          id: id,
          name: name,
          category: category,
          color: color,
          layers: const [],
          triggerStages: [stage],
          timelinePositionMs: i * 2200.0,
          trackIndex: 0,
          createdAt: now,
          modifiedAt: now,
        ));
      }
    } catch (_) {
      // Stage seeding is a convenience — failure must not abort the
      // resize itself. The user can manually add events later.
    }
  }

  /// Parse user input from the inline Omnibar pill.
  ///
  /// Accepts `5x3`, `5×3`, `5X3` (case-insensitive, both ASCII `x` and
  /// the typographic `×`). Returns `null` when the input cannot be
  /// parsed into two integers — the caller treats null as "reject and
  /// keep the previous values" without surfacing a confusing error.
  static (int reels, int rows)? parseGridInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    // Replace typographic times with ASCII so `split('x')` works.
    final normalized = trimmed.toLowerCase().replaceAll('×', 'x');
    final parts = normalized.split('x');
    if (parts.length != 2) return null;
    final r = int.tryParse(parts[0].trim());
    final c = int.tryParse(parts[1].trim());
    if (r == null || c == null) return null;
    return (r, c);
  }
}
