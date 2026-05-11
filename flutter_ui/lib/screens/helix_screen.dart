// HELIX — Neural Slot Design Environment
//
// Flutter translation of helix-mockup.html — the complete visual shell
// for the FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.
//
// Layout (mirrors the HTML mockup exactly):
//   ┌─────────────────────────────────────────────┐  48px
//   │              HELIX OMNIBAR                  │
//   ├──┬──────────────────────────────────────────┤
//   │  │                                          │
//   │S │          NEURAL CANVAS                   │
//   │P │   (slot machine + stage strip + glow)    │
//   │I │                                          │
//   │N │                                          │
//   │E │                                          │
//   ├──┴──────────────────────────────────────────┤  300px
//   │  FLOW │ AUDIO │ MATH │ TIMELINE │INTEL│EXPORT│
//   │       COMMAND DOCK (resizable)              │
//   └─────────────────────────────────────────────┘
//
// All panels wire to real providers — zero fake data.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';

import 'package:desktop_drop/desktop_drop.dart';

import '../theme/fluxforge_theme.dart';
import '../theme/flux_motion.dart';
import 'helix/helpers/slot_rect_resolver.dart';
import '../providers/engine_provider.dart';
import '../providers/slot_lab/game_flow_provider.dart';
import '../providers/slot_lab/rgai_provider.dart';
import '../providers/slot_lab_project_provider.dart';
import '../providers/slot_lab/neuro_audio_provider.dart';
import '../providers/slot_export_provider.dart';
import '../providers/middleware_provider.dart';
import '../providers/slot_lab/feature_composer_provider.dart';
import '../providers/slot_lab/slot_lab_coordinator.dart';
// AleProvider import removed — wiring moved into `GridResizePipeline`
// (FLUX_MASTER_TODO 2.1.7); helix_screen.dart no longer references the
// type directly. CortexEye + ServiceLocator still register it.
import '../providers/slot_lab/helix_bt_canvas_provider.dart';
import '../services/native_file_picker.dart';
import '../services/gdd_import_service.dart';
import '../src/rust/native_ffi.dart' show ForcedOutcome;
import '../widgets/slot_lab/live_play_orb_overlay.dart';
import '../widgets/slot_lab/premium_slot_preview.dart';
// ── SPRINT 1 imports ──
import '../widgets/common/command_palette.dart';
import '../widgets/common/flux_tooltip.dart';
import '../utils/error_log.dart'; // H-011
import '../utils/path_validator.dart'; // 2026-05-09 — auto-bind sandbox extension
import '../widgets/helix/math_hud_overlay.dart';
// import '../widgets/helix/stub_tab_placeholder.dart'; // removed — no stubs remain
// ── SPEC-14: Panel Focus ──
import '../providers/panel_focus_provider.dart';
import '../widgets/helix/quick_assign_hotbar.dart';
import '../models/game_flow_models.dart';
import '../models/slot_audio_events.dart';
// ── Faza 3 imports ──
import '../providers/sfx_pipeline_provider.dart';
import '../providers/ab_sim_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/ai_generation_service.dart';
import '../services/cortex_vision_service.dart';
import '../services/cortex_eye_server.dart';
import '../services/audio_playback_service.dart';
import '../services/command_registry.dart';
import '../services/event_registry.dart';
import '../services/event_registration_service.dart';
import '../services/stage_configuration_service.dart';
// `GddGridConfig` ushtow-import removed — direct usage moved into
// `GridResizePipeline` (FLUX_MASTER_TODO 2.1.7); the unqualified
// `gdd_import_service.dart` import above still resolves
// `GddImportService` for the CortexEye `slot_load_sample` path.
import '../services/grid_resize_pipeline.dart';
import '../models/slot_lab_models.dart' show SymbolDefinition, SymbolType;
import '../models/game_config_models.dart';

import '../src/rust/native_ffi.dart';
import '../widgets/slot_lab/auto_bind_dialog_v2.dart';
import '../widgets/slot_lab/neural_bind_orb.dart';
import '../widgets/slot_lab/orb_mixer.dart';
import '../widgets/helix/audio_coverage_badge.dart';
import '../widgets/helix/helix_event_nexus.dart';
import '../widgets/helix/compliance_lights_badge.dart';
import '../widgets/helix/session_recorder_panel.dart';
import '../widgets/helix/stage_flow_strip.dart';
import '../widgets/helix/timeline_intelligence.dart';
import '../widgets/helix/ai_composer_panel.dart'; // Model 3 — multi-provider AI Composer
import '../providers/mixer_dsp_provider.dart';
import '../providers/orb_mixer_provider.dart';
import '../providers/rgai_ffi_provider.dart';
import '../providers/slot_lab/live_compliance_provider.dart';
import 'slot_lab_screen.dart' show SlotLabScreen;

// ── Part files (FAZA 2.3 monolith split) ─────────────────────────────────────
// Each part file extracts a self-contained widget group while keeping all
// `_` private classes accessible within this library scope.
part 'helix/helix_omnibar_atoms.dart';
part 'helix/helix_dock_widgets.dart';
part 'helix/helix_minimode_widgets.dart';
// Sprint 15 Faza 4.C — dock panel splits (one part-file per panel).
part 'helix/panels/flow_panel.dart';
part 'helix/panels/sfx_panel.dart';
part 'helix/panels/bt_panel.dart';
part 'helix/panels/audio_dna_panel.dart';
part 'helix/panels/ai_gen_panel.dart';
part 'helix/panels/cloud_panel.dart';
part 'helix/panels/ab_panel.dart';
part 'helix/panels/audio_panel.dart';
part 'helix/panels/math_panel.dart';
part 'helix/panels/timeline_panel.dart';
part 'helix/panels/intel_panel.dart';
part 'helix/panels/export_panel.dart';
// Sprint 15 batch 4 — spine overlay widgets.
part 'helix/panels/spine_chrome.dart';
part 'helix/spine/spine_audio_assign.dart';
part 'helix/spine/spine_game_config.dart';
part 'helix/spine/spine_misc.dart';
// Sprint 15 batch 5 — helper widget extracts.
part 'helix/helpers/timeline_helpers.dart';
part 'helix/helpers/context_lenses.dart';
part 'helix/helpers/dock_chrome.dart';
part 'helix/helpers/quick_actions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELIX SCREEN
// ─────────────────────────────────────────────────────────────────────────────

/// Standardised error fallback for HELIX dock panels. Replaces ad-hoc
/// `Center(child: Text('FOO ERR: $e'))` snippets that previously swallowed
/// errors silently into the UI without logging (audit nalaz #8, P1).
///
/// - Logs through `debugPrint` so the error reaches the dev console / IDE.
/// - Wraps the message in `assert(...)` to fail-fast in debug mode (caught
///   exception still surfaces in tests / CI), but is a no-op in release.
/// - Visual style is consistent across panels: red text, monospace label,
///   small font so it doesn't push surrounding layout.
Widget _renderHelixErrorFallback(String tag, Object error, {double fontSize = 10}) {
  assert(() {
    // Debug-only: fail-fast so the error surfaces in tests + CI, not silent.
    debugPrint('[HELIX ERROR][$tag] $error');
    return true;
  }());
  return Center(
    child: Text(
      '$tag ERR: $error',
      style: FluxForgeTheme.dockMono(size: fontSize, color: const Color(0xFFFF4444)),
    ),
  );
}

// Layout constants for slot-grid-relative overlays (anticipation glow,
// stage triggers, future win-line painters). PremiumSlotPreview is centered
// at this ratio/offset; if its layout changes, update here in one place.
//
// TODO(URP-future): Make these dynamic via a GlobalKey lookup of the live
// PremiumSlotPreview RenderBox so layout-preset changes don't drift overlays.
const double _kSlotGridWidthRatio = 0.6;     // PremiumSlotPreview width / screen width
const double _kSlotGridLeftOffsetPx = 60.0;  // horizontal margin on the screen
const double _kSlotGridVInsetPx = 60.0;      // vertical inset (top == bottom)

// ─── Win-line overlay timing (Sprint 14 Faza 4.G) ────────────────────────────
//
// Pre-fix: magic numbers 2500 / 3000 / 60 hardkodirani u Timer.periodic
// pozivima.  Imenovani konstante daju semantičko značenje + jedno mesto
// za podešavanje ako se vremenska politika promeni.
//
// Win-line fade pipeline:
//   1. show lines (full opacity) for `_kWinLineHoldMs` (2500 ms)
//   2. start fade — runs for `_kWinLineClearMs - _kWinLineHoldMs` = 500 ms
//   3. clear at `_kWinLineClearMs` (3000 ms) → lines disappear
const int _kWinLineHoldMs = 2500;
const int _kWinLineClearMs = 3000;

// ─── Playhead refresh (Sprint 14 Faza 4.G) ───────────────────────────────────
//
// Pre-fix: `Timer.periodic(Duration(milliseconds: 60))` magic.  60 ms ≈
// 16.7 Hz, which is a deliberate undersample of 60 FPS display: the
// playhead doesn't need per-frame precision (slot game tempo is BPM-
// driven, not sample-accurate playback).  Named const documents the
// chosen tradeoff between latency and CPU usage.
const int _kPlayheadRefreshMs = 60;

// ─── Grid pill flash (Sprint 14 Faza 4.G) ────────────────────────────────────
//
// Pre-fix: `Duration(milliseconds: 2500)` reused from win-line hold.
// They happen to share the same number but are unrelated UX events;
// separating into named constants prevents accidental coupling if one
// timing is tuned independently.
const int _kGridFlashMs = 2500;

class HelixScreen extends StatefulWidget {
  final VoidCallback? onClose;
  final List<Map<String, dynamic>>? audioPool;

  const HelixScreen({super.key, this.onClose, this.audioPool});

  @override
  State<HelixScreen> createState() => _HelixScreenState();
}

class _HelixScreenState extends State<HelixScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── Dock ──────────────────────────────────────────────────────────────────
  int _dockTab = 0; // 0=FLOW 1=AUDIO 2=MATH 3=TIMELINE 4=INTEL 5=EXPORT 6=SFX 7=BT 8=DNA 9=AI 10=CLOUD 11=A/B

  // Per-mode dock heights — fixes audit nalaz #5 (P1).
  // Pre-fix: a single `_dockHeight` was overwritten by ARCHITECT mode's
  // `screenH * 0.5` computation, silently destroying the user's custom
  // resize when toggling COMPOSE → ARCHITECT and back. Drag-resize while
  // in ARCHITECT also did nothing because `_buildDock` ignored
  // `_dockHeight` in that mode.
  //
  // Post-fix: each mode owns its own height. Drag updates the *active*
  // mode's height. ARCHITECT starts as `-1` sentinel meaning
  // "compute 50% of screen height on first build"; once the user drags,
  // it switches to a concrete value and stops following the screen.
  double _dockHeightCompose = 380.0;
  double _dockHeightArchitect = -1.0;  // <0 sentinel → lazy 0.5 * screenH
  bool _dockExpanded = true;

  // ── Mode ──────────────────────────────────────────────────────────────────
  int _mode = 0; // 0=COMPOSE 1=FOCUS 2=ARCHITECT

  // ── Spine overlay ─────────────────────────────────────────────────────────
  int? _spineOpen; // null=closed  0=game 1=audio 2=ai 3=settings 4=analytics
  // SPRINT 1 SPEC-06 — Spine compact/expanded state.
  bool _spineExpanded = false;

  // ── Stage glow ────────────────────────────────────────────────────────────
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  // ── Waveform bars ─────────────────────────────────────────────────────────
  late Timer _waveTimer;
  final List<double> _waveBars = List.generate(36, (i) => math.Random().nextDouble() * 14 + 4);
  final _rng = math.Random();

  // ── BPM flicker ───────────────────────────────────────────────────────────
  late Timer _bpmTimer;
  double _bpmDisplay = 128.0;

  // ── Vision init delay (H-004 cancellable) ────────────────────────────────
  // Cancellable timer for the deferred CortexVision startup capture.  If the
  // HELIX screen unmounts inside the 3 s window the timer must be cancelled,
  // otherwise we leak an async chain that runs `vision.init()` +
  // `captureFullWindow()` against a dead BuildContext.
  Timer? _visionInitTimer;

  // ── FocusNode (CLAUDE.md: initState, not build) ───────────────────────────
  late final FocusNode _focusNode;

  // ── BPM inline edit ───────────────────────────────────────────────────────
  bool _bpmEditing = false;
  late final TextEditingController _bpmController;

  // ── Project name inline edit (O2) ─────────────────────────────────────────
  bool _projectNameEditing = false;
  late final TextEditingController _projectNameController;

  // ── Grid (REELS×ROWS) inline edit (implements FLUX_MASTER_TODO 2.1.7) ─────────────────
  // Closes the Definition of Done metric "klika do promene reel count-a:
  // 4 → 1". Tap the pill, type `5x3`, hit Enter — the resize routes
  // through `GridResizePipeline.apply` so engine + composer + stages
  // all stay in sync. Status string flashes for 2.5s then clears.
  bool _gridEditing = false;
  late final TextEditingController _gridController;
  String? _gridFlash; // transient toast text (✓/✗) shown after submit
  Timer? _gridFlashTimer;

  // ── Record toggle (O4) ────────────────────────────────────────────────────

  // ── Audio Context Lens (A3) ───────────────────────────────────────────────
  SlotCompositeEvent? _contextLensEvent;

  // ── Reel Cell Lens (C1/C2) ────────────────────────────────────────────────
  bool _showReelLens = false;
  int _reelLensReel = 0;
  int _reelLensRow = 0;

  // ── Playhead (T3/T4) ─────────────────────────────────────────────────────
  late Timer _playheadTimer;
  double _playheadSeconds = 0;

  // ── Win line overlay + anticipation glow ─────────────────────────────────
  // H-012 (HELIX_AUDIT 2026-05-07): live RenderBox lookup so anticipation
  // glow tracks the true PremiumSlotPreview position instead of relying on
  // the `* 0.6 + 60` magic literals that drifted whenever a layout preset
  // changed the grid width.  Key is attached to the centred preview below
  // and read in `_buildCanvas` to compute glow rectangles.
  final GlobalKey _slotPreviewKey = GlobalKey(debugLabel: 'helix_slot_preview');

  // Win lines: list of payline indices (0-based) that hit on last spin
  List<int> _lastWinLines = [];
  // H-014 (HELIX_AUDIT 2026-05-07): two-phase clear so the overlay fades
  // out in the last 500 ms instead of vanishing.  `_winLinesFading=true`
  // sets opacity → 0 via AnimatedOpacity, then a follow-up timer clears
  // the list so the next spin starts from a clean state.
  bool _winLinesFading = false;
  Timer? _winLinesFadeTimer;
  Timer? _winLinesClearTimer;
  // Anticipation: reel indices (0-based) showing scatter/bonus during spin
  Set<int> _anticipationReels = {};

  /// H-012: Resolve the live PremiumSlotPreview rect (origin + size) in
  /// the same coordinate space as the surrounding `Stack`.  Returns the
  /// hard-coded fallback rect when the GlobalKey has not yet attached to
  /// a laid-out RenderBox (first build, headless tests).
  Rect _resolveSlotPreviewRect() {
    try {
      final ctx = _slotPreviewKey.currentContext;
      if (ctx != null) {
        final ro = ctx.findRenderObject();
        if (ro is RenderBox && ro.hasSize) {
          // The Stack ancestor in `_buildCanvas` does not introduce its own
          // origin offset, so converting via the Stack's own RenderBox
          // (looked up by walking up the tree) is equivalent to the
          // ancestor.findRenderObject() result.  Use globalToLocal against
          // a Stack ancestor lookup when we can find one; fall back to
          // local Offset.zero otherwise.
          final ancestor = context.findRenderObject();
          final origin = (ancestor is RenderBox)
              ? ro.localToGlobal(Offset.zero, ancestor: ancestor)
              : ro.localToGlobal(Offset.zero);
          return Rect.fromLTWH(
              origin.dx, origin.dy, ro.size.width, ro.size.height);
        }
      }
    } catch (_) {
      // Fall through to constants below.
    }
    return computeSlotRectFallback(
      screenSize: MediaQuery.of(context).size,
      gridWidthRatio: _kSlotGridWidthRatio,
      leftOffsetPx: _kSlotGridLeftOffsetPx,
      vInsetPx: _kSlotGridVInsetPx,
    );
  }

  /// Called from spin result to show win lines
  void showWinLines(List<int> lines) {
    _winLinesFadeTimer?.cancel();
    _winLinesClearTimer?.cancel();
    setState(() {
      _lastWinLines = lines;
      _winLinesFading = false;
    });
    // Phase 1 — start fade after hold period; user has 500 ms of fade.
    _winLinesFadeTimer = Timer(const Duration(milliseconds: _kWinLineHoldMs), () {
      if (mounted) setState(() => _winLinesFading = true);
    });
    // Phase 2 — clear after the fade completes.
    _winLinesClearTimer = Timer(const Duration(milliseconds: _kWinLineClearMs), () {
      if (mounted) {
        setState(() {
          _lastWinLines = [];
          _winLinesFading = false;
        });
      }
    });
  }

  /// Called during spin to highlight reels with anticipation
  void setAnticipationReels(Set<int> reels) {
    setState(() => _anticipationReels = reels);
  }

  void clearAnticipation() {
    setState(() => _anticipationReels = {});
  }

  // ── Public API for child widgets ──────────────────────────────────────────
  void openContextLens(SlotCompositeEvent event) {
    setState(() => _contextLensEvent = event);
  }

  void setPlayhead(double seconds) {
    setState(() => _playheadSeconds = seconds);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // C.4: glow pause on app background
    _restoreSession(); // 2026-05-10 (Sprint 14) — Faza 4.A.3 state persistence
    _focusNode = FocusNode()..requestFocus();
    _bpmController = TextEditingController(text: '128.0');
    _projectNameController = TextEditingController(
      text: GetIt.instance<SlotLabProjectProvider>().projectName);

    // Grid pill — seed from current project grid (5×3 fallback). The
    // controller is only repopulated on tap so user-typed-but-not-
    // submitted values aren't overwritten by a provider notify.
    final initGrid = GetIt.instance<SlotLabProjectProvider>().gridConfig;
    _gridController = TextEditingController(
      text: '${initGrid?.columns ?? 5}x${initGrid?.rows ?? 3}',
    );
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.06, end: 0.12).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    // 2026-05-10 (Sprint 14 Faza 4.B.7) — refresh rate 120ms → 200ms.
    // 120ms = 8.3 Hz, fine for old 60Hz displays but excessive on modern
    // 120Hz displays where every refresh paints additional GPU frame.
    // 200ms = 5 Hz drives the same perceptual smoothness with ~40% less
    // GPU/CPU overhead on the waveform pipeline.
    _waveTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _waveBars.length; i++) {
          _waveBars[i] = _rng.nextDouble() * 14 + 4;
        }
      });
    });

    _bpmTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      silentRun('bpmTimer.syncDisplay', () {
        final engine = GetIt.instance<EngineProvider>();
        final t = engine.transport;
        setState(() => _bpmDisplay = t.tempo > 0 ? t.tempo : _bpmDisplay);
      });
    });

    // Seed demo composite events so panels show real data on first open
    _seedDemoEvents();

    // Implements FLUX_MASTER_TODO 3.4.1 — live compliance poll loop.
    // Idempotent — drugi `start()` poziv je no-op. Provider se sam
    // gasi u dispose-u; lazy singleton tako da multiple HELIX mount-a
    // ne pokreće 5 paralelnih poll-ova.
    GetIt.instance<LiveComplianceProvider>().start();

    // Cortex Vision auto-capture — takes screenshot of HELIX on startup.
    //
    // H-004 (HELIX_AUDIT 2026-05-07): the original implementation used
    // `await Future.delayed(...)` inside `addPostFrameCallback`, which is
    // not cancellable.  If the HELIX screen unmounts during the 3 s window
    // (e.g. user opens then immediately closes), the async chain still
    // resolves and runs `vision.init()` + `captureFullWindow()` against a
    // dead BuildContext.  Replace with a stored Timer that we cancel in
    // `dispose()`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _visionInitTimer = Timer(const Duration(seconds: 3), () async {
        if (!mounted) return;
        final vision = CortexVisionService.instance;
        await vision.init();
        if (!mounted) return; // re-check after the async gap
        await vision.captureFullWindow(
          metadata: {'trigger': 'helix_startup', 'tab': _dockTab},
        );
      });
    });

    // CortexEye: register all HELIX control callbacks for CORTEX autonomy
    final nav = CortexEyeNav.instance;
    nav.onHelixTab = (tab) {
      if (!mounted) return;
      setState(() => _dockTab = tab.clamp(0, 12));
    };
    nav.onHelixSpine = (index) {
      if (!mounted) return;
      setState(() => _spineOpen = _spineOpen == index ? null : index);
    };
    nav.onHelixMode = (mode) {
      if (!mounted) return;
      setState(() => _mode = mode.clamp(0, 2));
    };
    nav.onHelixAction = (action, params) {
      if (!mounted) return;
      switch (action) {
        case 'stage_force':
          final stage = params['stage'] as String?;
          if (stage != null) {
            silentRun('eye.stageForce', () {
              EventRegistry.instance.triggerStage(stage.toUpperCase());
            });
          }
        case 'play':
          silentRun('eye.enginePlay', () { GetIt.instance<EngineProvider>().play(); });
        case 'pause':
        case 'stop':
          silentRun('eye.engineStop', () { GetIt.instance<EngineProvider>().stop(); });
        case 'transport_toggle':
          silentRun('eye.transportToggle', () {
            final e = GetIt.instance<EngineProvider>();
            e.transport.isPlaying ? e.stop() : e.play();
          });
        // ─── TALAS 1 — Eye automation for slot flow QA ────────────────────
        case 'slot_load_sample':
          silentRun('eye.slotLoadSample', () {
            final gddJson = GddImportService.instance.createSampleGddJson();
            GetIt.instance<SlotLabCoordinator>().initEngineFromGdd(gddJson);
            // Clear "NO CONFIGURATION" overlay so SPIN button is enabled
            final composer = GetIt.instance<FeatureComposerProvider>();
            if (!composer.isConfigured) {
              composer.applyConfig(SlotMachineConfig(
                name: 'Auto QA Sample',
                reelCount: 5,
                rowCount: 3,
                paylineCount: 20,
                paylineType: PaylineType.lines,
                winTierCount: 5,
                volatilityProfile: 'medium',
              ));
            }
          });
        case 'slot_spin':
          silentRun('eye.slotSpin', () { GetIt.instance<SlotLabCoordinator>().spin(); });
        case 'slot_spin_forced':
          silentRun('eye.slotSpinForced', () {
            final name = (params['outcome'] as String? ?? 'bigWin').toLowerCase();
            final outcome = ForcedOutcome.values.firstWhere(
              (o) => o.name.toLowerCase() == name,
              orElse: () => ForcedOutcome.bigWin,
            );
            GetIt.instance<SlotLabCoordinator>().spinForced(outcome);
          });
        case 'slot_stop':
          silentRun('eye.slotStop', () {
            GetIt.instance<SlotLabCoordinator>().stopStagePlayback();
          });
        // ─── TALAS 1 β — Synthetic FSM drivers ────────────────────────────
        // These bypass the engine and drive GameFlowProvider directly so all
        // Talas 1 wires (onSpinStart/Complete, FS auto-loop, deferred BW,
        // SLAM watchdog) can be end-to-end verified via Eye even when the
        // engine lacks a full blueprint.
        case 'fsm_reset':
          silentRun('eye.fsmReset', () {
            GetIt.instance<GameFlowProvider>().resetToBaseGame();
          });
        case 'fsm_dismiss_transition':
          silentRun('eye.fsmDismissTransition', () {
            GetIt.instance<GameFlowProvider>().dismissTransition();
          });
        case 'fsm_force_transition':
          silentRun('eye.fsmForceTransition', () {
            final name = (params['to'] as String? ?? 'baseGame');
            final target = GameFlowState.values.firstWhere(
              (s) => s.name == name,
              orElse: () => GameFlowState.baseGame,
            );
            GetIt.instance<GameFlowProvider>().forceTransition(target);
          });
        // TIMELINE dock-tab quick actions — eye-automation for the
        // 2026-05-09 REPLAY / JUMP / CLEAR trio.  Used by autonomous QA
        // tests via /eye/helix_action so the same code path the user
        // taps fires through the same handlers.
        case 'timeline_replay':
          _replayLastSpin();
        case 'timeline_jump_stage':
          // Bypass the dialog when called from automation — stage name
          // is supplied directly.
          silentRun('eye.timelineJumpStage', () {
            final stage = (params['stage'] as String?)?.toUpperCase();
            if (stage == null || stage.isEmpty) return;
            EventRegistry.instance.triggerStage(stage);
          });
        case 'timeline_clear':
          _clearLastSpin();
        // Phase 9: Live Play Orb overlay eye-automation
        case 'orb_show':
          silentRun('eye.orbShow', () { LivePlayOrbOverlayState.current?.show(); });
        case 'orb_hide':
          silentRun('eye.orbHide', () { LivePlayOrbOverlayState.current?.hide(); });
        case 'orb_toggle':
          silentRun('eye.orbToggle', () { LivePlayOrbOverlayState.current?.toggleVisible(); });
        case 'orb_cycle_size':
          silentRun('eye.orbCycleSize', () { LivePlayOrbOverlayState.current?.cycleSizeMode(); });
        case 'orb_set_size':
          // Smooth-resize: params.px = target size in pixels (60..480).
          silentRun('eye.orbSetSize', () {
            final px = (params['px'] as num?)?.toDouble();
            if (px != null) {
              LivePlayOrbOverlayState.current?.setSizePx(px);
            }
          });
        case 'fsm_synthetic_spin':
          silentRun('eye.fsmSyntheticSpin', () {
            final outcome = (params['outcome'] as String? ?? 'noWin').toLowerCase();
            final bet = (params['bet'] as num?)?.toDouble() ?? 2.0;
            final gf = GetIt.instance<GameFlowProvider>();

            // Start the spin — wires onSpinStart in coordinator, but for
            // synthetic we call the FSM directly.
            gf.onSpinStart();

            // Build synthetic result shaped per outcome
            double totalWin = 0;
            double winRatio = 0;
            SlotLabWinTier? tier;
            bool featureTriggered = false;
            bool isFreeSpins = gf.currentState == GameFlowState.freeSpins;
            // Default grid = no scatters. Scatter symbol ID is 12 per SpinContext defaults.
            // For FS trigger, place 3 scatters across reels 1/3/5.
            List<List<int>> grid = const [[1,2,3],[4,5,6],[7,8,9],[1,2,3],[4,5,6]];
            switch (outcome) {
              case 'nowin':
                break;
              case 'smallwin':
                totalWin = bet * 2; winRatio = 2;
                break;
              case 'bigwin':
                totalWin = bet * 12; winRatio = 12; tier = SlotLabWinTier.bigWin;
                break;
              case 'megawin':
                totalWin = bet * 30; winRatio = 30; tier = SlotLabWinTier.megaWin;
                break;
              case 'epicwin':
                totalWin = bet * 60; winRatio = 60; tier = SlotLabWinTier.epicWin;
                break;
              case 'freespinstrigger':
                // 3 scatters (id=12) on reels 0, 2, 4 (min across reels)
                grid = const [[12,2,3],[4,5,6],[7,12,9],[1,2,3],[4,5,12]];
                totalWin = bet * 1; winRatio = 1; featureTriggered = true;
                break;
              case 'deferredbigwinexit':
                // In FS, this spin closes the feature with a cumulative
                // totalWin that triggers onDeferredBigWin (≥ 10× bet)
                totalWin = bet * 12; winRatio = 12;
                isFreeSpins = true;
                break;
            }

            final result = SlotLabSpinResult(
              spinId: 'synth_${DateTime.now().millisecondsSinceEpoch}',
              grid: grid,
              bet: bet,
              totalWin: totalWin,
              winRatio: winRatio,
              lineWins: const [],
              bigWinTier: tier,
              featureTriggered: featureTriggered,
              nearMiss: false,
              isFreeSpins: isFreeSpins,
              freeSpinIndex: null,
              multiplier: 1.0,
              cascadeCount: 0,
            );
            gf.onSpinComplete(result);
          });
      }
    };

    // Playhead sync timer — polls engine position for timeline animation
    _playheadTimer = Timer.periodic(const Duration(milliseconds: _kPlayheadRefreshMs), (_) {
      if (!mounted) return;
      silentRun('playheadTimer.sync', () {
        final t = GetIt.instance<EngineProvider>().transport;
        if (t.isPlaying && t.positionSeconds != _playheadSeconds) {
          setState(() => _playheadSeconds = t.positionSeconds);
        }
      });
    });
  }

  @override
  void dispose() {
    // Clean up CortexEye callbacks
    final nav = CortexEyeNav.instance;
    nav.onHelixTab = null;
    nav.onHelixSpine = null;
    nav.onHelixMode = null;
    nav.onHelixAction = null;

    WidgetsBinding.instance.removeObserver(this); // C.4
    _focusNode.dispose();
    _bpmController.dispose();
    _projectNameController.dispose();
    _gridController.dispose();
    _gridFlashTimer?.cancel();
    _glowCtrl.dispose();
    _waveTimer.cancel();
    _bpmTimer.cancel();
    _playheadTimer.cancel();
    _visionInitTimer?.cancel(); // H-004
    _winLinesFadeTimer?.cancel(); // H-014
    _winLinesClearTimer?.cancel(); // H-014
    _persistSession(); // 2026-05-10 (Sprint 14) — Faza 4.A.3 state persistence
    super.dispose();
  }

  // ── C.4: Pause glow animation when app goes to background ─────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_glowCtrl.isAnimating) _glowCtrl.repeat(reverse: true);
    } else {
      _glowCtrl.stop();
    }
  }

  // ── Session persistence (Sprint 14, Boki "ne radi mi") ─────────────────
  //
  // Pre-fix: every app restart reset the user back to FLOW tab / COMPOSE
  // mode / collapsed spine.  User session was completely lost between
  // launches — irritating during iterative tuning.
  //
  // Post-fix: read four ints from SharedPreferences in `initState()` and
  // write them back in `dispose()`.  Keeps spine open/closed plus chosen
  // index, dock tab, and mode across launches.  Uses fire-and-forget
  // SharedPreferences calls — failures are silently ignored (worst case:
  // session resets to defaults, which is the pre-fix behavior).
  static const _kPrefDockTab    = 'helix.dockTab';
  static const _kPrefMode       = 'helix.mode';
  static const _kPrefSpineIndex = 'helix.spineIndex';
  static const _kPrefSpineOpen  = 'helix.spineOpen';
  static const _kPrefDockExpanded = 'helix.dockExpanded';

  void _restoreSession() {
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final dockTab     = prefs.getInt(_kPrefDockTab);
      final mode        = prefs.getInt(_kPrefMode);
      final spineIdx    = prefs.getInt(_kPrefSpineIndex);
      final spineOpen   = prefs.getBool(_kPrefSpineOpen) ?? false;
      final dockExpanded = prefs.getBool(_kPrefDockExpanded);
      setState(() {
        if (dockTab != null && dockTab >= 0 && dockTab <= 12) {
          _dockTab = dockTab;
        }
        if (mode != null && mode >= 0 && mode <= 3) {
          _mode = mode;
        }
        if (spineOpen && spineIdx != null && spineIdx >= 0 && spineIdx <= 4) {
          _spineOpen = spineIdx;
        }
        if (dockExpanded != null) {
          _dockExpanded = dockExpanded;
        }
      });
    }).catchError((Object e) {
      debugPrint('[HELIX SESSION] restore failed: $e');
    });
  }

  void _persistSession() {
    // Fire-and-forget — if write fails (rare on macOS), session simply
    // doesn't persist this time; the app keeps running.  No await means
    // dispose() returns synchronously, which Flutter requires.
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_kPrefDockTab, _dockTab);
      prefs.setInt(_kPrefMode, _mode);
      prefs.setBool(_kPrefSpineOpen, _spineOpen != null);
      if (_spineOpen != null) {
        prefs.setInt(_kPrefSpineIndex, _spineOpen!);
      }
      prefs.setBool(_kPrefDockExpanded, _dockExpanded);
    }).catchError((Object e) {
      debugPrint('[HELIX SESSION] persist failed: $e');
    });
  }

  /// Submit handler for the inline REELS×ROWS pill (implements FLUX_MASTER_TODO 2.1.7).
  /// Parses `5x3` / `5×3` (case-insensitive), runs the resize through
  /// `GridResizePipeline`, flashes the result for 2.5s. The pill exits
  /// edit mode immediately on submit so the user sees the new value
  /// settle even while the engine init runs in the background.
  Future<void> _submitGridPill(String raw) async {
    final parsed = GridResizePipeline.parseGridInput(raw);
    setState(() => _gridEditing = false);
    if (parsed == null) {
      _flashGrid('✗ format: REELSxROWS (e.g. 5x3)');
      return;
    }
    final result = await GridResizePipeline.apply(
      reels: parsed.$1, rows: parsed.$2,
    );
    if (mounted) _flashGrid(result.shortStatus);
  }

  void _flashGrid(String text) {
    _gridFlashTimer?.cancel();
    setState(() => _gridFlash = text);
    _gridFlashTimer = Timer(const Duration(milliseconds: _kGridFlashMs), () {
      if (mounted) setState(() => _gridFlash = null);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Seed demo composite events so HELIX panels aren't empty
  // ─────────────────────────────────────────────────────────────────────────

  // H-005 (HELIX_AUDIT 2026-05-07): the previous guard only compared
  // `mw.compositeEvents.isNotEmpty` — but the same call also seeds 50 neuro
  // samples + 30 project spin results, which have no symmetric guard.  If
  // HELIX is mounted, dismissed, and re-mounted (e.g. dock layout swap or
  // hot-reload), those *neuro / proj* tracks get duplicate samples even
  // though the composite-events guard correctly bails.  Switch to a single
  // process-wide flag so the entire seed runs at most once per app session.
  static bool _demoSeedDone = false;

  void _seedDemoEvents() {
    if (_demoSeedDone) return;
    silentRun('seed.demoEvents', () {
      final mw = GetIt.instance<MiddlewareProvider>();
      if (mw.compositeEvents.isNotEmpty) {
        // Project already has authored events — do not seed demo data, but
        // mark as done so a later mount does not re-seed neuro/proj either.
        _demoSeedDone = true;
        return;
      }
      final now = DateTime.now();
      final demoEvents = [
        SlotCompositeEvent(
          id: 'demo_spin_start', name: 'SPIN START', category: 'spin',
          color: FluxForgeTheme.accentBlue, masterVolume: 0.85,
          triggerStages: ['spin_start', 'base_game'],
          timelinePositionMs: 0, trackIndex: 0,
          createdAt: now, modifiedAt: now,
        ),
        SlotCompositeEvent(
          id: 'demo_reel_stop', name: 'REEL STOP', category: 'spin',
          color: FluxForgeTheme.accentCyan, masterVolume: 0.75,
          triggerStages: ['reel_stop'],
          timelinePositionMs: 800, trackIndex: 0,
          createdAt: now, modifiedAt: now,
        ),
        SlotCompositeEvent(
          id: 'demo_win_small', name: 'WIN SMALL', category: 'win',
          color: FluxForgeTheme.accentGreen, masterVolume: 0.70,
          triggerStages: ['win_presentation'],
          timelinePositionMs: 1500, trackIndex: 1,
          createdAt: now, modifiedAt: now,
        ),
        SlotCompositeEvent(
          id: 'demo_win_big', name: 'WIN BIG', category: 'win',
          color: FluxForgeTheme.accentYellow, masterVolume: 0.90,
          triggerStages: ['win_presentation', 'jackpot'],
          timelinePositionMs: 2500, trackIndex: 1,
          createdAt: now, modifiedAt: now,
        ),
        SlotCompositeEvent(
          id: 'demo_freespin_intro', name: 'FREE SPIN INTRO', category: 'feature',
          color: FluxForgeTheme.accentOrange, masterVolume: 0.80,
          triggerStages: ['free_spins'],
          timelinePositionMs: 3500, trackIndex: 2,
          createdAt: now, modifiedAt: now,
        ),
        SlotCompositeEvent(
          id: 'demo_ambient_base', name: 'AMBIENT BASE', category: 'ambient',
          color: FluxForgeTheme.accentPurple, masterVolume: 0.45,
          triggerStages: ['base_game', 'idle'], looping: true,
          timelinePositionMs: 0, trackIndex: 3,
          createdAt: now, modifiedAt: now,
        ),
        SlotCompositeEvent(
          id: 'demo_bonus_trigger', name: 'BONUS TRIGGER', category: 'feature',
          color: FluxForgeTheme.accentPink, masterVolume: 0.88,
          triggerStages: ['bonus_game'],
          timelinePositionMs: 5000, trackIndex: 2,
          createdAt: now, modifiedAt: now,
        ),
        SlotCompositeEvent(
          id: 'demo_ui_click', name: 'UI CLICK', category: 'ui',
          color: FluxForgeTheme.textSecondary, masterVolume: 0.50,
          triggerStages: ['ui_interaction'],
          timelinePositionMs: 6500, trackIndex: 4,
          createdAt: now, modifiedAt: now,
        ),
      ];
      for (final e in demoEvents) {
        mw.addCompositeEvent(e, select: false, skipUndo: true);
      }
      // Also seed some neuro data so INTEL/MATH panels show values
      silentRun('seed.neuroData', () {
        final neuro = GetIt.instance<NeuroAudioProvider>();
        final rng = math.Random(42);
        for (int i = 0; i < 50; i++) {
          neuro.recordClickVelocity(500 + rng.nextDouble() * 2500);
          neuro.recordPauseDuration(300 + rng.nextDouble() * 1500);
          neuro.recordBetSize(rng.nextDouble() * 0.7 + 0.1);
          final winMult = rng.nextDouble() < 0.28 ? rng.nextDouble() * 8 : 0.0;
          neuro.recordSpinResult(winMult);
        }
      });
      // Seed some spin results into project stats
      silentRun('seed.projectSpinResults', () {
        final proj = GetIt.instance<SlotLabProjectProvider>();
        final rng = math.Random(42);
        for (int i = 0; i < 30; i++) {
          final bet = 1.0;
          final winMult = rng.nextDouble() < 0.30 ? rng.nextDouble() * 15 : 0.0;
          proj.recordSpinResult(betAmount: bet, winAmount: winMult * bet,
          tier: winMult > 5 ? 'WIN 3' : winMult > 0 ? 'WIN 1' : null);
        }
      });
      // H-005: mark seed complete so subsequent HELIX mounts don't duplicate
      // neuro/proj samples even if the composite-events guard would still bail.
      _demoSeedDone = true;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // HELIX only closes via explicit X button — never by accident
      child: KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.transparent,
        child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            // SPEC-12 Mini Mode: collapse to 200px strip
            height: _mode == 3 ? 200 : double.infinity,
            color: FluxForgeTheme.bgVoid,
            child: _mode == 3
                ? _buildMiniStrip()
                : Column(
              children: [
                _buildOmnibar(),
                // SPRINT 3 SPEC-13 — Quick Assign Hotbar (visible only in
                // AUDIO ASSIGN spine, which is index 1 after the
                // Game Config / Audio Assign reorder).
                QuickAssignHotbar(visible: _spineOpen == 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FocusablePanel(
                        id: FocusPanelId.helixSpine,
                        child: _buildSpine(),
                      ),
                      Expanded(
                        child: FocusablePanel(
                          id: FocusPanelId.helixCanvas,
                          child: _buildCanvas(),
                        ),
                      ),
                    ],
                  ),
                ),
                // Stage strip + waveform bars — OUTSIDE Canvas Stack
                // (Prevents blocking PremiumSlotPreview Control Bar clicks)
                Consumer<GameFlowProvider>(
                  builder: (ctx, flow, _) => _buildStageRow(flow),
                ),
                if (_mode != 1) FocusablePanel(
                  id: FocusPanelId.helixDock,
                  child: _buildDock(),
                ),
              ],
            ),
          ),
          // Spine overlay panel — rendered in main Stack so it floats ABOVE the canvas
          // bottom offset avoids covering the dock tab bar (dock ~300px + stage strip ~36px)
          if (_spineOpen != null)
            Positioned(
              left: 48, top: 48,
              bottom: _mode == 1 ? 48 : (_resolveDockHeight() + 48).clamp(228.0, 648.0), // Dynamic: dock height + stage strip (48px)
              child: _SpineOverlay(
                title: _spineIcons[_spineOpen!].$2,
                spineIndex: _spineOpen!,
                onClose: () => setState(() => _spineOpen = null),
              ),
            ),
          // Audio Context Lens overlay (A3)
          if (_contextLensEvent != null)
            _AudioContextLens(
              event: _contextLensEvent!,
              onClose: () => setState(() => _contextLensEvent = null),
            ),
        ],
      ),
      ),
      ),
    );
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final key = e.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isMeta  = HardwareKeyboard.instance.isMetaPressed;

    if (key == LogicalKeyboardKey.escape) {
      setState(() { _spineOpen = null; _mode = 0; _contextLensEvent = null; });
      return;
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _mode = _mode == 1 ? 0 : 1);
      return;
    } else if (key == LogicalKeyboardKey.keyA) {
      setState(() => _mode = _mode == 2 ? 0 : 2);
      return;
    } else if (key == LogicalKeyboardKey.keyM && isMeta && isShift) {
      // SPEC-12: Mini Mode — Cmd+Shift+M
      setState(() => _mode = _mode == 3 ? 0 : 3);
      return;
    }

    // SPRINT 1 SPEC-06 — Shift+Cmd+\\ toggles spine compact/expanded.
    if (isShift && isMeta && key == LogicalKeyboardKey.backslash) {
      setState(() => _spineExpanded = !_spineExpanded);
      return;
    }

    // SPEC-14 — Cmd+] / Cmd+[ cycle panel focus forward / back.
    // Mirrors Logic Pro / Final Cut / Photoshop panel-cycle bindings.
    // Tab is NOT hijacked because Tab inside a TextField (BPM, GRID,
    // project name) must keep its native traversal semantics — losing
    // focus mid-edit because of a global cycle would be a regression.
    if (isMeta && key == LogicalKeyboardKey.bracketRight) {
      _cyclePanelFocus(reverse: false);
      return;
    }
    if (isMeta && key == LogicalKeyboardKey.bracketLeft) {
      _cyclePanelFocus(reverse: true);
      return;
    }

    // SPRINT 1 SPEC-17 — Stage trigger keyboard shortcuts in HELIX FLOW tab.
    // Active only when FLOW dock tab (index 0) is selected; falls through
    // to dock-tab nav otherwise so existing 1-9 behavior is preserved.
    if (_dockTab == 0 && !isMeta) {
      try {
        final flow = context.read<GameFlowProvider>();
        // Shift+letter triggers — manual feature triggers via existing API
        if (isShift) {
          if (key == LogicalKeyboardKey.keyS) {
            flow.triggerManual(TransitionTrigger.featureBuy);
            _showStageToast('FEATURE BUY');
            return;
          }
          if (key == LogicalKeyboardKey.keyG) {
            flow.triggerManual(TransitionTrigger.playerGamble);
            _showStageToast('GAMBLE');
            return;
          }
          if (key == LogicalKeyboardKey.keyC) {
            flow.triggerManual(TransitionTrigger.playerCollect);
            _showStageToast('COLLECT');
            return;
          }
          if (key == LogicalKeyboardKey.keyJ) {
            flow.triggerManual(TransitionTrigger.jackpotTriggered);
            _showStageToast('JACKPOT');
            return;
          }
          if (key == LogicalKeyboardKey.keyR) {
            flow.triggerManual(TransitionTrigger.retrigger);
            _showStageToast('RETRIGGER');
            return;
          }
        }
      } catch (e) {
        // 2026-05-10 (Sprint 14): pre-fix je `catch (_) {}` silently progutao
        // sve greške (GameFlowProvider not registered, FFI fail, etc.).
        // Sad logujemo u debug mode da QA može detektovati zašto stage
        // shortcuts ne rade ako se dogodi regression.
        debugPrint('[HELIX KEY] stage trigger failed: $e');
      }
    }

    // 1-9,0 → dock tabs (0 = tab 10), -/= → tabs 11/12
    final digit = int.tryParse(e.character ?? '');
    if (digit != null && digit >= 1 && digit <= 9) {
      setState(() => _dockTab = digit - 1);
    } else if (digit == 0) {
      setState(() => _dockTab = 9);
    } else if (key == LogicalKeyboardKey.minus) {
      setState(() => _dockTab = 10);
    } else if (key == LogicalKeyboardKey.equal) {
      setState(() => _dockTab = 11);
    } else if (key == LogicalKeyboardKey.backquote) {
      // Backtick → AI COMPOSER tab
      setState(() => _dockTab = 12);
    } else if (key == LogicalKeyboardKey.keyK && isMeta) {
      // SPEC-01: Global Cmd+K — HELIX Quick Switcher
      _openQuickSwitcher();
      return;
    } else if (isShift && key == LogicalKeyboardKey.slash) {
      // 2026-05-10 (Sprint 14 Faza 4.B.6) — `?` opens keyboard cheatsheet.
      // Solves discoverability problem: HELIX has ~15 keyboard shortcuts
      // hidden across `_onKey` branches; new user has no way to find them.
      _openKeyboardCheatsheet();
      return;
    }
  }

  /// Sprint 14 Faza 4.B.6 — keyboard shortcut cheatsheet dialog.
  ///
  /// Activated via `?` (Shift+/).  Lists every shortcut defined in
  /// `_onKey` so the user can discover them without reading source.
  /// Grouped by category; rows are scrollable for future shortcut growth.
  void _openKeyboardCheatsheet() {
    showDialog<void>(
      context: context,
      barrierColor: FluxForgeTheme.bgVoid.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: FluxForgeTheme.bgDeepest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: FluxForgeTheme.brandGold.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(
                    color: FluxForgeTheme.borderSubtle, width: 1)),
                ),
                child: Row(children: [
                  const Icon(Icons.keyboard_rounded, size: 18,
                      color: FluxForgeTheme.brandGold),
                  const SizedBox(width: 8),
                  Text('KEYBOARD SHORTCUTS', style: FluxForgeTheme.dockMono(
                    size: 13,
                    weight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: FluxForgeTheme.brandGold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: FluxForgeTheme.textSecondary,
                    onPressed: () => Navigator.of(ctx).pop(),
                    tooltip: 'Close (Esc)',
                  ),
                ]),
              ),
              // Body — scrollable list of shortcut groups
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  children: const [
                    _KeysGroup(title: 'MODES', rows: [
                      ('F', 'Toggle FOCUS mode (hide dock)'),
                      ('A', 'Toggle ARCHITECT mode (50 % dock)'),
                      ('Esc', 'Return to COMPOSE mode'),
                      ('Shift + Cmd + M', 'Cycle to MINI mode'),
                    ]),
                    _KeysGroup(title: 'DOCK TABS', rows: [
                      ('1 – 9', 'Switch to tab 1–9 (FLOW–AI GEN)'),
                      ('0', 'Switch to tab 10 (CLOUD)'),
                      ('-', 'Switch to tab 11 (A/B)'),
                      ('=', 'Switch to tab 12 (COMPOSER)'),
                      ('`', 'Quick-jump to COMPOSER'),
                      ('Cmd + [', 'Previous dock tab'),
                      ('Cmd + ]', 'Next dock tab'),
                    ]),
                    _KeysGroup(title: 'PALETTE & UI', rows: [
                      ('Cmd + K', 'Open HELIX Quick Switcher'),
                      ('Shift + Cmd + \\', 'Toggle Spine overlay'),
                      ('?', 'Open this cheatsheet'),
                    ]),
                    _KeysGroup(title: 'STAGE TRIGGERS', rows: [
                      ('Shift + S', 'Trigger SPIN_START'),
                      ('Shift + G', 'Trigger GAME_START'),
                      ('Shift + C', 'Trigger CASCADE_STEP'),
                      ('Shift + J', 'Trigger JACKPOT'),
                      ('Shift + R', 'Trigger RETRIGGER'),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// SPEC-01 — HELIX Quick Switcher (Cmd+K).
  ///
  /// Registers all 13 dock tabs as palette commands so the user can jump
  /// to any tab via fuzzy search. Clears stale tab registrations first
  /// to avoid duplicates when the palette is opened multiple times.
  void _openQuickSwitcher() {
    CommandRegistry.instance.clearByPrefix('helix.tab.');
    CommandRegistry.instance.clearByPrefix('daw.tab.');
    CommandRegistry.instance.clearByPrefix('slotlab.tab.');
    for (var i = 0; i < _dockTabDefs.length; i++) {
      final def = _dockTabDefs[i];
      CommandRegistry.instance.register(PaletteCommand(
        // Stable id from the registry — survives index reshuffling once
        // the future DockTabRegistry plugin path lands.
        id: 'helix.tab.${def.id}',
        label: def.label,
        description: 'Switch to ${def.label} dock tab',
        category: PaletteCategory.navigate,
        icon: def.icon,
        keywords: [def.label.toLowerCase(), def.id, 'helix', 'dock'],
        onExecute: () => setState(() => _dockTab = i),
      ));
    }
    CommandPalette.showUltimate(context);
  }

  /// SPEC-14 — Panel focus cycle (Cmd+] forward, Cmd+[ back).
  ///
  /// Cycles through the three HELIX panels in visual reading order
  /// (Spine → Canvas → Dock). When no panel is currently focused the
  /// forward cycle lands on Spine and the reverse cycle lands on Dock,
  /// so the very first Cmd+] always lands somewhere predictable.
  ///
  /// The Dock panel is suppressed in FOCUS mode (`_mode == 1`) where
  /// the dock is hidden — cycling skips it so Cmd+] doesn't appear to
  /// "do nothing" when it lands on an invisible target.
  void _cyclePanelFocus({required bool reverse}) {
    final order = <FocusPanelId>[
      FocusPanelId.helixSpine,
      FocusPanelId.helixCanvas,
      if (_mode != 1) FocusPanelId.helixDock,
    ];
    final pf = GetIt.instance<PanelFocusProvider>();
    final current = pf.focused;
    final currentIdx = current == null ? -1 : order.indexOf(current);
    final next = reverse
        ? (currentIdx <= 0 ? order.length - 1 : currentIdx - 1)
        : (currentIdx + 1) % order.length;
    pf.focus(order[next]);
    // Brief toast so the user sees which panel just took focus —
    // otherwise a 1px gold border on the dock can be missed at a glance.
    _showStageToast('FOCUS: ${_panelLabel(order[next])}');
  }

  String _panelLabel(FocusPanelId id) => switch (id) {
        FocusPanelId.helixSpine => 'SPINE',
        FocusPanelId.helixCanvas => 'CANVAS',
        FocusPanelId.helixDock => 'DOCK',
        FocusPanelId.dawTimeline => 'DAW TIMELINE',
        FocusPanelId.dawLowerZone => 'DAW LOWER',
        FocusPanelId.slotLabCanvas => 'SLOTLAB',
        FocusPanelId.slotLabLowerZone => 'SLOTLAB LOWER',
      };

  /// SPRINT 1 SPEC-17 — toast shown 1.5s bottom-center after a stage shortcut.
  // ─── TIMELINE dock-tab quick actions (2026-05-09) ───────────────────────
  //
  // Replaced the old PLAY/STOP/REC/LOOP/GOTO_START placeholder strip with
  // three actions that map onto the real SlotStageProvider lifecycle.
  // All three are scaffolded with mounted guards + empty-cache toasts so
  // they fail loud instead of silently doing nothing.

  /// Re-play the cached `_lastStages` sequence.  Uses
  /// `setStages(stages, autoPlay: true)` which resets the cursor and
  /// schedules the same stage-by-stage timer the real spin uses.
  /// Toasts when there is nothing to replay.
  void _replayLastSpin() {
    silentRun('timeline.replayLastSpin', () {
      final coord = GetIt.instance<SlotLabCoordinator>();
      final stages = coord.stageProvider.lastStages;
      if (stages.isEmpty) {
        _showInfoToast('No spin recorded yet — press SPIN first');
        return;
      }
      // Stop any in-flight playback before re-arming so timers don't race.
      coord.stageProvider.stopStagePlayback();
      coord.stageProvider.setStages(stages, autoPlay: true);
      _showInfoToast('Replaying ${stages.length} stages');
    });
  }

  /// Picker dialog over the cached stages so the user can audition a
  /// single stage in isolation.  Each entry fires
  /// `EventRegistry.triggerStage(stageType)` which resolves to whatever
  /// composite is bound to that stage in the registry — the same path
  /// the live spin engine uses.
  Future<void> _showJumpToStageDialog() async {
    if (!mounted) return;
    final coord = GetIt.instance<SlotLabCoordinator>();
    final stages = coord.stageProvider.lastStages;
    if (stages.isEmpty) {
      _showInfoToast('No spin recorded yet — press SPIN first');
      return;
    }

    final picked = await showDialog<SlotLabStageEvent>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF111118),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  const Icon(Icons.skip_next_rounded,
                      size: 14, color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 6),
                  Text('Jump to stage  (${stages.length})',
                      style: FluxForgeTheme.dockMono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: FluxForgeTheme.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: FluxForgeTheme.textTertiary),
                  ),
                ]),
              ),
              const Divider(height: 1, color: Color(0xFF222230)),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: stages.length,
                  itemBuilder: (ctx, i) {
                    final s = stages[i];
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 30,
                              child: Text('${i + 1}',
                                  style: FluxForgeTheme.dockMono(
                                      size: 10,
                                      color: FluxForgeTheme.textTertiary)),
                            ),
                            Expanded(
                              child: Text(s.stageType,
                                  style: FluxForgeTheme.dockMono(
                                      size: 11,
                                      color: FluxForgeTheme.textPrimary)),
                            ),
                            Text('${s.timestampMs.toInt()} ms',
                                style: FluxForgeTheme.dockMono(
                                    size: 9,
                                    color: FluxForgeTheme.textTertiary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    silentRun('timeline.jumpToStage', () {
      EventRegistry.instance.triggerStage(picked.stageType.toUpperCase());
      _showInfoToast('Triggered ${picked.stageType}');
    });
  }

  /// Drop the cached stages so the next REPLAY/JUMP press informs the
  /// user instead of replaying stale data.  Also stops any in-flight
  /// playback so the cache and audio output go quiet together.
  void _clearLastSpin() {
    silentRun('timeline.clearLastSpin', () {
      final coord = GetIt.instance<SlotLabCoordinator>();
      coord.stageProvider.stopStagePlayback();
      coord.stageProvider.setStages(const []);
      _showInfoToast('Last spin cleared');
    });
  }

  /// Lightweight neutral toast — single-line message, 1.4 s.
  /// Used by TIMELINE quick actions (REPLAY / JUMP / CLEAR) when the
  /// outcome is informational rather than an error.
  void _showInfoToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: FluxForgeTheme.dockMono(
                size: 11,
                color: FluxForgeTheme.textPrimary)),
        backgroundColor: const Color(0xFF1A1A22),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  void _showStageToast(String stage) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 16, color: FluxForgeTheme.brandGoldBright),
            const SizedBox(width: 8),
            Text(
              'STAGE: $stage',
              style: FluxForgeTheme.dockMono(
                size: 11,
                weight: FontWeight.w700,
                letterSpacing: 1.4,
                color: FluxForgeTheme.brandGoldBright,
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1500),
        backgroundColor: const Color(0xF20D0D12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: FluxForgeTheme.brandGold.withValues(alpha: 0.45),
            width: 0.6,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 32),
        width: 200,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ─── SPEC-12: Mini Mode strip (200px) ───────────────────────────────────
  Widget _buildMiniStrip() {
    return Consumer<GameFlowProvider>(
      builder: (ctx, flow, _) {
        final fsm = flow.currentState.name.toUpperCase();
        return Container(
          height: 200,
          decoration: const BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
          ),
          child: Column(
            children: [
              // Top bar with expand hint
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  color: FluxForgeTheme.bgVoid,
                  border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.compress_rounded, size: 12, color: FluxForgeTheme.textTertiary),
                    const SizedBox(width: 6),
                    Text('HELIX MINI', style: FluxForgeTheme.dockMono(
                      size: 10, weight: FontWeight.w700,
                      letterSpacing: 1.2, color: FluxForgeTheme.textTertiary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _mode = 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('⌘⇧M', style: FluxForgeTheme.dockMono(
                            size: 9, color: FluxForgeTheme.textTertiary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_full_rounded, size: 11, color: FluxForgeTheme.textTertiary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Main content row
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // FSM state + controls
                      _MiniModeSection(
                        label: 'FSM STATE',
                        child: Text(fsm,
                          style: FluxForgeTheme.dockMono(
                            size: 13, weight: FontWeight.w800,
                            letterSpacing: 0.5, color: FluxForgeTheme.accentCyan)),
                      ),
                      const _MiniDivider(),
                      // SPIN button
                      GestureDetector(
                        onTap: () {
                          GetIt.instance<SlotLabCoordinator>().spin();
                        },
                        child: Container(
                          width: 64, height: 40,
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                            border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded, size: 16, color: FluxForgeTheme.accentGreen),
                              const SizedBox(width: 2),
                              Text('SPIN', style: FluxForgeTheme.dockMono(
                                size: 9, weight: FontWeight.w800,
                                letterSpacing: 0.8, color: FluxForgeTheme.accentGreen)),
                            ],
                          ),
                        ),
                      ),
                      const _MiniDivider(),
                      // Compliance indicator via RGAI
                      _MiniModeSection(
                        label: 'RGAI',
                        child: Consumer<RgaiFfiProvider>(
                          builder: (ctx, rgai, _) {
                            final ok = rgai.exportApproved;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  ok ? Icons.check_circle_rounded : Icons.warning_rounded,
                                  size: 14,
                                  color: ok ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange,
                                ),
                                const SizedBox(width: 4),
                                Text(ok ? 'OK' : 'WARN', style: FluxForgeTheme.dockMono(
                                  size: 10, weight: FontWeight.w700,
                                  color: ok ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange)),
                              ],
                            );
                          },
                        ),
                      ),
                      const Spacer(),
                      // Mode buttons
                      Row(
                        children: [
                          for (final m in [('C', 0), ('F', 1), ('A', 2)])
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: GestureDetector(
                                onTap: () => setState(() => _mode = m.$2),
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: FluxForgeTheme.bgSurface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                                  ),
                                  child: Center(child: Text(m.$1,
                                    style: FluxForgeTheme.dockMono(size: 10,
                                      weight: FontWeight.w700, color: FluxForgeTheme.textSecondary))),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // OMNIBAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOmnibar() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          // Logo — FluxForge brand identity (gold→ivory).
          //
          // 2026-05-10 (Sprint 14 Faza 4.B.1) — pre-fix bio je generic
          // accentBlue→accentPurple gradijent koji je delovao kao Figma
          // default ("startup AI vibes" per Boki audit).  Sada koristi
          // `FluxForgeTheme.brandGradient` (deep gold → bright gold →
          // ivory) sa subtle glow u brand boji.  Tipografija ostaje
          // monospace radi tehnicke estetike, ali boja teksta je sad
          // brandGoldDark da se prelivi u brand identity.
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: FluxForgeTheme.brandGradient,
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(color: FluxForgeTheme.brandGold.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: -2),
                BoxShadow(color: FluxForgeTheme.brandGoldBright.withValues(alpha: 0.20), blurRadius: 18, spreadRadius: -3),
              ],
              border: Border.all(color: FluxForgeTheme.brandGoldBright.withValues(alpha: 0.4), width: 0.5),
            ),
            child: Center(
              child: Text('HX',
                style: FluxForgeTheme.dockMono(size: 10, weight: FontWeight.w900,
                  letterSpacing: 0.8, color: FluxForgeTheme.brandGoldDark)),
            ),
          ),
          const SizedBox(width: 8),
          Text('HELIX', style: FluxForgeTheme.dockMono(
            size: 11, weight: FontWeight.w700,
            letterSpacing: 1.5, color: FluxForgeTheme.textPrimary)),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 8),
          // ── Mode badge (Sprint 14 Faza 4.B.4) ─────────────────────────
          // Pre-fix: korisnik je morao da gleda 3 mode dugmica desno
          // (COMPOSE/FOCUS/ARCHITECT) da bi znao gde je. Ako je u FOCUS
          // mode-u (dock sakriven) ili ARCHITECT (dock 50% screen),
          // korisnik bi se zbunio i mislio da je app broken.
          // Post-fix: persistent labela u Omnibar-u sa keyboard hint-om.
          // F = FOCUS toggle, A = ARCHITECT toggle, Esc = COMPOSE.
          _ModeIndicator(mode: _mode),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 12),
          // Project name — tap to edit inline (O2)
          GestureDetector(
            onTap: () {
              _projectNameController.text =
                GetIt.instance<SlotLabProjectProvider>().projectName;
              setState(() => _projectNameEditing = true);
            },
            child: _OmniPill(
              border: _projectNameEditing
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
                : null,
              child: Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                if (_projectNameEditing)
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _projectNameController,
                      autofocus: true,
                      style: FluxForgeTheme.dockMono(
                        size: 11, color: FluxForgeTheme.textPrimary),
                      decoration: const InputDecoration(
                        isDense: true, border: InputBorder.none,
                        contentPadding: EdgeInsets.zero),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          GetIt.instance<SlotLabProjectProvider>().newProject(v.trim());
                        }
                        setState(() => _projectNameEditing = false);
                      },
                      onTapOutside: (_) => setState(() => _projectNameEditing = false),
                    ),
                  )
                else
                  Text(GetIt.instance<SlotLabProjectProvider>().projectName,
                    overflow: TextOverflow.ellipsis,
                    style: FluxForgeTheme.dockMono(
                      size: 11, color: FluxForgeTheme.textPrimary)),
              ]),
            ),
          ),
          const Spacer(),
          // Undo/Redo — wired to SlotLabProjectProvider
          ListenableBuilder(
            listenable: GetIt.instance<SlotLabProjectProvider>(),
            builder: (ctx, _) {
              final proj = GetIt.instance<SlotLabProjectProvider>();
              return Row(children: [
                _OmniIconBtn(
                  icon: Icons.undo_rounded,
                  onTap: proj.canUndoAudioAssignment ? () { proj.undoAudioAssignment(); } : null,
                ),
                const SizedBox(width: 2),
                _OmniIconBtn(
                  icon: Icons.redo_rounded,
                  onTap: proj.canRedoAudioAssignment ? () { proj.redoAudioAssignment(); } : null,
                ),
              ]);
            },
          ),
          const SizedBox(width: 12),
          // BPM — tap to edit
          GestureDetector(
            onTap: () {
              _bpmController.text = _bpmDisplay.toStringAsFixed(1);
              setState(() => _bpmEditing = true);
            },
            child: _OmniPill(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
              border: _bpmEditing
                ? FluxForgeTheme.accentCyan.withValues(alpha: 0.7)
                : FluxForgeTheme.accentCyan.withValues(alpha: 0.35),
              child: Row(children: [
                Text('BPM', style: FluxForgeTheme.dockMono(
                  size: 11, letterSpacing: 0.5, weight: FontWeight.w700,
                  color: FluxForgeTheme.accentCyan)),
                const SizedBox(width: 8),
                if (_bpmEditing)
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _bpmController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: FluxForgeTheme.dockMono(
                        size: 13, weight: FontWeight.w700,
                        color: FluxForgeTheme.accentCyan),
                      decoration: const InputDecoration(
                        isDense: true, border: InputBorder.none,
                        contentPadding: EdgeInsets.zero),
                      onSubmitted: (v) {
                        final bpm = double.tryParse(v);
                        if (bpm != null && bpm > 20 && bpm < 300) {
                          GetIt.instance<EngineProvider>().setTempo(bpm);
                          setState(() { _bpmDisplay = bpm; _bpmEditing = false; });
                        } else {
                          setState(() => _bpmEditing = false);
                        }
                      },
                      onTapOutside: (_) => setState(() => _bpmEditing = false),
                    ),
                  )
                else
                  Text(_bpmDisplay.toStringAsFixed(1), style: FluxForgeTheme.dockMono(
                    size: 13, weight: FontWeight.w700,
                    color: FluxForgeTheme.accentCyan)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          // Implements FLUX_MASTER_TODO 2.1.7 — REELS×ROWS inline edit
          // (was 4 clicks through the GAME CONFIG spine overlay; now
          // 1 click + Enter).
          _buildGridPill(),
          const SizedBox(width: 12),
          // Implements FLUX_MASTER_TODO 3.4.1 — live compliance traffic
          // lights. Per-jurisdiction status (UKGC/MGA/...) + spin
          // counter + tooltip sa worst metric utilization%. Reaguje na
          // LiveComplianceProvider notify (200 ms poll loop).
          ComplianceLightsBadge(
            provider: GetIt.instance<LiveComplianceProvider>(),
          ),
          const SizedBox(width: 8),
          // Implements FLUX_MASTER_TODO 3.6.1 — Audio Coverage Badge.
          // Sticky pill: bound/total stages + per-category breakdown
          // tooltip.  Reaktivan na project audioAssignments change i
          // StageConfigurationService palette extension.
          const AudioCoverageBadge(),
          // Transport bar (Play/Stop/Record) intentionally removed from
          // HELIX omnibar (2026-05-09) — slot design is event-driven (SPIN
          // button on the Premium Slot Preview is the authoritative
          // playback trigger).  The DAW screen keeps the full transport
          // since DAW is timeline-driven and Record has a real bounce
          // target there.
          const SizedBox(width: 12),
          // Mode badges (H-015 HELIX_AUDIT 2026-05-07: tooltip-aware)
          ..._modeDefs.map((m) =>
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: FluxTooltip(
                message: m.tooltip,
                child: _ModeBadge(
                  label: m.label,
                  active: _mode == m.index,
                  onTap: () => setState(() => _mode = m.index),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Close button
          _OmniIconBtn(
            icon: Icons.close_rounded,
            onTap: widget.onClose,
            color: FluxForgeTheme.textTertiary,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Implements FLUX_MASTER_TODO 2.1.7 — Inline REELS×ROWS pill in the Omnibar.
  ///
  /// Two states:
  ///   * Display: shows current grid as `5×3` with a flash overlay
  ///     when the most recent submit produced a `✓` / `✗` result.
  ///   * Edit:    shows a 64px-wide TextField pre-filled with the
  ///     current `5x3`, autofocused, submitting on Enter or
  ///     onTapOutside. The format hint (✗ format) lands as a flash.
  ///
  /// Mirrors the BPM pill pattern (autofocus + onSubmitted +
  /// onTapOutside) so the muscle memory is consistent across all
  /// inline-edit affordances in the Omnibar.
  Widget _buildGridPill() {
    return ListenableBuilder(
      listenable: GetIt.instance<SlotLabProjectProvider>(),
      builder: (context, _) {
        final cfg = GetIt.instance<SlotLabProjectProvider>().gridConfig;
        final reels = cfg?.columns ?? 5;
        final rows = cfg?.rows ?? 3;
        final accent = FluxForgeTheme.accentPurple;
        final flashIsErr = (_gridFlash ?? '').startsWith('✗');
        final flashColor = flashIsErr
            ? FluxForgeTheme.accentRed
            : FluxForgeTheme.accentGreen;

        return FluxTooltip(
          message: 'Grid (REELS × ROWS)',
          shortcutHint: 'click to edit · 5x3',
          child: GestureDetector(
            onTap: () {
              // Re-seed the controller from the *current* provider value
              // so the user always edits against the latest grid, not a
              // stale value from the last edit attempt.
              _gridController.text = '${reels}x$rows';
              setState(() => _gridEditing = true);
            },
            child: _OmniPill(
              color: accent.withValues(alpha: 0.08),
              border: _gridEditing
                  ? accent.withValues(alpha: 0.7)
                  : accent.withValues(alpha: 0.35),
              child: Row(children: [
                Text('GRID',
                    style: FluxForgeTheme.dockMono(
                        size: 11,
                        letterSpacing: 0.5,
                        weight: FontWeight.w700,
                        color: accent)),
                const SizedBox(width: 8),
                if (_gridEditing)
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _gridController,
                      autofocus: true,
                      style: FluxForgeTheme.dockMono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: accent),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: _submitGridPill,
                      onTapOutside: (_) {
                        // Esc-equivalent — exit edit without applying.
                        // Submitting empty / unchanged is a no-op below
                        // because we set _gridEditing = false here.
                        if (_gridEditing) {
                          setState(() => _gridEditing = false);
                        }
                      },
                    ),
                  )
                else if (_gridFlash != null)
                  Text(_gridFlash!,
                      style: FluxForgeTheme.dockMono(
                          size: 11,
                          weight: FontWeight.w700,
                          color: flashColor))
                else
                  Text('${reels}×$rows',
                      style: FluxForgeTheme.dockMono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: accent)),
              ]),
            ),
          ),
        );
      },
    );
  }

  // _buildTransport() removed 2026-05-09 — slot design is event-driven
  // (SPIN button on the Premium Slot Preview owns playback).  DAW screen
  // still has its own transport since it's timeline-driven and Record
  // has a real bounce target there.  See `_buildOmnibar` for context.

  // ─────────────────────────────────────────────────────────────────────────
  // NEURAL SPINE
  // ─────────────────────────────────────────────────────────────────────────

  // H-015 (HELIX_AUDIT 2026-05-07): mode badge metadata in one place so the
  // tooltip stays in sync with the index-driven state machine.
  static const _modeDefs = <_HelixModeDef>[
    _HelixModeDef(
      index: 0,
      label: 'COMPOSE',
      tooltip: 'COMPOSE — full editor: spine, neural canvas and dock '
          'are all visible.  Default authoring mode.',
    ),
    _HelixModeDef(
      index: 1,
      label: 'FOCUS',
      tooltip: 'FOCUS — hides the dock so you can concentrate on the '
          'neural canvas.  Press F to cycle the panel; Tab/Shift+Tab to '
          'cycle dock tabs even while hidden.',
    ),
    _HelixModeDef(
      index: 2,
      label: 'ARCHITECT',
      tooltip: 'ARCHITECT — dock expands to fill ~50% of the screen '
          'for graph + flow editing.  Drag the dock divider to fine-tune.',
    ),
  ];

  // Spine icon definitions — shared between _buildSpine() and spine overlay in build()
  static const _spineIcons = [
    (Icons.grid_view_rounded, 'GAME CONFIG'),
    (Icons.music_note_rounded, 'AUDIO ASSIGN'),
    (Icons.psychology_rounded, 'AI / INTEL'),
    (Icons.tune_rounded, 'SETTINGS'),
    (Icons.bar_chart_rounded, 'ANALYTICS'),
  ];

  Widget _buildSpine() {
    final icons = _spineIcons;

    // SPRINT 1 SPEC-06 — Spine width animates between collapsed/expanded.
    // Collapsed: 48px (icons only). Expanded: 112px (icons + labels under).
    final spineWidth = _spineExpanded ? 112.0 : 48.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: spineWidth,
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeepest, // #08080C = --abyss
        border: Border(right: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          ...icons.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SpineItem(
              icon: e.value.$1,
              label: e.value.$2,
              shortcutHint: '⌘${e.key + 1}',
              expanded: _spineExpanded,
              active: _spineOpen == e.key,
              onTap: () => setState(() =>
                _spineOpen = _spineOpen == e.key ? null : e.key),
            ),
          )),
          const Spacer(),
          // SPRINT 1 SPEC-06 — collapse/expand toggle at the bottom.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FluxTooltip(
              message: _spineExpanded ? 'Collapse spine' : 'Expand spine',
              shortcutHint: '⇧⌘\\',
              child: GestureDetector(
                onTap: () => setState(() => _spineExpanded = !_spineExpanded),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgVoid.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: FluxForgeTheme.borderSubtle,
                        width: 0.6,
                      ),
                    ),
                    child: Icon(
                      _spineExpanded
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                      size: 18,
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NEURAL CANVAS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCanvas() {
    return Consumer<GameFlowProvider>(
      builder: (context, flow, _) {
        final stage = flow.currentState;
        final glowColor = _stageGlowColor(stage);

        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Stack(
            children: [
              // Stage glow background
              AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, child) => Center(
                  child: Container(
                    width: (MediaQuery.of(context).size.width * 0.55).clamp(400.0, 900.0),
                    height: (MediaQuery.of(context).size.height * 0.45).clamp(300.0, 600.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: glowColor.withValues(alpha: _glowAnim.value * 0.8),
                        blurRadius: 100, spreadRadius: 10,
                      )],
                    ),
                  ),
                ),
              ),

              // Slot preview — center (C1: onCellTap → Context Lens)
              // Grid dimensions read from SlotLabProjectProvider so GAME CONFIG Apply
              // actually reconfigures the visible slot machine.
              //
              // H-012: the `_slotPreviewKey` GlobalKey lives on the wrapping
              // KeyedSubtree so anticipation-glow lookup gets a stable
              // RenderObject regardless of grid resize.  PremiumSlotPreview
              // keeps its own ValueKey for the rebuild-on-resize trigger.
              Center(
                child: RepaintBoundary( // C.4: isolate slot canvas repaints from dock/omnibar rebuilds
                  child: KeyedSubtree(
                  key: _slotPreviewKey,
                  child: ListenableBuilder(
                  listenable: GetIt.instance<SlotLabProjectProvider>(),
                  builder: (ctx, _) {
                    final proj = GetIt.instance<SlotLabProjectProvider>();
                    final gridCfg = proj.gridConfig;
                    return PremiumSlotPreview(
                      key: ValueKey('slot_${gridCfg?.columns ?? 5}_${gridCfg?.rows ?? 3}'),
                      onExit: () {
                        // ESC in slot preview embedded in HELIX — close any open
                        // HELIX-level overlays instead of exiting HELIX entirely.
                        setState(() {
                          _spineOpen = null;
                          _contextLensEvent = null;
                          _mode = 0;
                          _showReelLens = false;
                        });
                      },
                      reels: gridCfg?.columns ?? 5,
                      rows: gridCfg?.rows ?? 3,
                      isFullscreen: true,
                      projectProvider: proj,
                  onCellTap: (reelIndex, rowIndex) {
                    // C1/C2: Open Reel Context Lens + Audio Context Lens
                    setState(() {
                      _reelLensReel = reelIndex;
                      _reelLensRow = rowIndex;
                      _showReelLens = true;
                    });
                    // Also try to open audio lens for matching composite event
                    silentRun('canvas.openAudioContextLens', () {
                      final mw = GetIt.instance<MiddlewareProvider>();
                      final events = mw.compositeEvents;
                      final match = events.where((e) =>
                        e.triggerStages.any((s) => s.contains('reel')) ||
                        e.name.toLowerCase().contains('reel') ||
                        e.trackIndex == reelIndex
                      ).toList();
                      if (match.isNotEmpty) {
                        openContextLens(match.first);
                      } else if (events.isNotEmpty) {
                        openContextLens(events[reelIndex % events.length]);
                      }
                    });
                  },
                  // Implements FLUX_MASTER_TODO 0.5 D.1 — Reel cell as audio bind target.
                  // Drop audio file path → bind direktno na REEL_STOP_<reelIndex>
                  // event preko `setAudioAssignment` (per-reel auto-expand
                  // takođe popunjava sve REEL_STOP_i sa stereo pan-om).
                  onAudioDropOnReel: (reelIndex, rowIndex, audioPath) {
                    final stage = 'REEL_STOP_$reelIndex';
                    proj.setAudioAssignment(stage, audioPath);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          backgroundColor: FluxForgeTheme.bgElevated,
                          content: Text(
                            '🎵 Bound to $stage',
                            style: FluxForgeTheme.dockSans(
                              color: FluxForgeTheme.brandGold,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                );
                  },
                ),
                ),
                ),
              ),

              // Info chips — top right, BELOW PremiumSlotPreview header (48px)
              // Positioned below the preview's _HeaderZone to avoid overlapping
              // balance, device sim, audio controls, settings, reload buttons
              Positioned(
                top: 56, right: 14,
                child: IgnorePointer(child: _buildInfoChips()),
              ),

              // SPRINT 1 SPEC-10 — Floating Math HUD overlay (RTP / VOL / HIT / MAX).
              // Always visible while user works in any HELIX dock tab.
              // Positioned top-left so it doesn't clash with info chips top-right.
              //
              // H-001 (HELIX_AUDIT 2026-05-07): when an in-feature banner is up
              // (Free Spins / Respin / Cascade), GameFlowOverlay places its
              // banner at top:40 spanning the full width.  Slide the Math HUD
              // down by 44 px in that case so the two never overlap.
              Positioned(
                top: flow.isInFeature ? 124 : 80,
                left: 12,
                child: const MathHudOverlay(),
              ),

              // Win line overlay — shows active paylines after spin.
              // H-014: AnimatedOpacity gives a 500 ms fade-out instead of
              // an abrupt disappearance — see `showWinLines`.
              if (_lastWinLines.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _winLinesFading ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      child: CustomPaint(
                        painter: _WinLineOverlayPainter(
                          winLines: _lastWinLines,
                          reels: GetIt.instance<SlotLabProjectProvider>().gridConfig?.columns ?? 5,
                          rows: GetIt.instance<SlotLabProjectProvider>().gridConfig?.rows ?? 3,
                        ),
                      ),
                    ),
                  ),
                ),

              // Anticipation reel glow — highlights reels with scatter/bonus during spin.
              //
              // H-012 (HELIX_AUDIT 2026-05-07): live RenderBox lookup via
              // `_slotPreviewKey`.  We resolve the centred PremiumSlotPreview's
              // actual position + size each frame so the glow tracks layout
              // changes (preset switch, window resize, ARCHITECT mode dock
              // grow that shrinks the canvas).  The pre-fix path used
              // hard-coded `_kSlotGridWidthRatio` / `_kSlotGridLeftOffsetPx`
              // constants which drifted by 4–24 px on non-default layouts.
              //
              // Falls back to the named constants when the key has not yet
              // been laid out (first frame after mount).
              if (_anticipationReels.isNotEmpty)
                ..._anticipationReels.map((reelIdx) {
                  final reels = GetIt.instance<SlotLabProjectProvider>()
                          .gridConfig
                          ?.columns ??
                      5;
                  final rect = _resolveSlotPreviewRect();
                  final reelWidth = rect.width / reels;
                  return Positioned(
                    left: rect.left + reelIdx * reelWidth,
                    top: rect.top,
                    width: reelWidth,
                    height: rect.height,
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: FluxForgeTheme.accentYellow.withValues(alpha: 0.6),
                            width: 2),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: FluxForgeTheme.accentYellow.withValues(alpha: 0.15),
                              blurRadius: 20,
                              spreadRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

              // C1/C2: Reel Context Lens (triggered via PremiumSlotPreview.onCellTap)
              // NOTE: _ReelCellOverlay removed — it blocked underlying touch events.
              // Cell taps are handled by onCellTap callback on PremiumSlotPreview above.
              if (_showReelLens)
                _ReelContextLens(
                  reel: _reelLensReel,
                  row: _reelLensRow,
                  onClose: () => setState(() => _showReelLens = false),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _stageGlowColor(GameFlowState s) => switch (s) {
    GameFlowState.idle       => FluxForgeTheme.accentBlue,
    GameFlowState.baseGame   => FluxForgeTheme.accentBlue,
    GameFlowState.cascading  => FluxForgeTheme.accentCyan,
    GameFlowState.freeSpins  => FluxForgeTheme.accentYellow,
    GameFlowState.holdAndWin => FluxForgeTheme.accentOrange,
    GameFlowState.bonusGame  => FluxForgeTheme.accentYellow,
    GameFlowState.gamble     => FluxForgeTheme.accentPurple,
    GameFlowState.jackpotPresentation => FluxForgeTheme.accentGreen,
    _ => FluxForgeTheme.accentBlue,
  };

  Widget _buildInfoChips() {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final rtp = proj.sessionStats.rtp;
    final spins = proj.sessionStats.totalSpins;
    // Show target RTP when session data is unreliable (< 100 spins)
    // Session RTP is statistically meaningless with small sample sizes
    final targetRtp = proj.targetRtp; // configured target (e.g. 96.0%)
    final rtpStr = (spins < 100 || rtp.isNaN || rtp.isInfinite)
        ? '${targetRtp.toStringAsFixed(1)}%'
        : '${rtp.toStringAsFixed(1)}%';
    final rtpLabel = spins < 100 ? 'TGT RTP' : 'RTP';
    // Color: green if within ±2% of target, yellow if off, red if way off
    final rtpColor = (spins < 100)
        ? FluxForgeTheme.textSecondary
        : (rtp - targetRtp).abs() < 2.0
            ? FluxForgeTheme.accentGreen
            : (rtp - targetRtp).abs() < 5.0
                ? FluxForgeTheme.accentYellow
                : FluxForgeTheme.accentRed;
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<GameFlowProvider>(),
        GetIt.instance<SlotLabProjectProvider>(),
      ]),
      builder: (context, _) {
        final flow = GetIt.instance<GameFlowProvider>();
        final gridCfg = GetIt.instance<SlotLabProjectProvider>().gridConfig;
        final gridStr = gridCfg != null ? '${gridCfg.columns}×${gridCfg.rows}' : '5×3';
        return Row(
          children: [
            _InfoChip(label: rtpLabel, value: rtpStr, color: rtpColor),
            const SizedBox(width: 8),
            _InfoChip(label: 'GRID', value: gridStr),
            const SizedBox(width: 8),
            _InfoChip(
              label: 'STAGE',
              value: flow.currentState.displayName.toUpperCase(),
              color: _stageGlowColor(flow.currentState),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStageStrip(GameFlowState current, GameFlowProvider flow) {
    final stages = [
      (GameFlowState.idle, 'IDLE', FluxForgeTheme.textTertiary),
      (GameFlowState.baseGame, 'BASE', FluxForgeTheme.accentBlue),
      (GameFlowState.freeSpins, 'FREE', FluxForgeTheme.accentYellow),
      (GameFlowState.bonusGame, 'BONUS', FluxForgeTheme.accentOrange),
      (GameFlowState.jackpotPresentation, 'JACKPOT', FluxForgeTheme.accentGreen),
    ];

    // C3: force transition function — switches game state + visual feedback
    void forceStage(GameFlowState target) {
      final label = target.displayName.toUpperCase();
      flow.forceTransition(target);
      // Visual feedback: switch to FLOW panel + show snackbar so user sees the change
      setState(() => _dockTab = 0);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Stage → $label', style: FluxForgeTheme.dockMono(
          size: 11, color: FluxForgeTheme.textPrimary)),
        backgroundColor: FluxForgeTheme.bgSurface,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 200, right: 200),
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.9),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: stages.asMap().entries.expand((e) {
          final (state, label, color) = e.value;
          final isActive = current == state;
          final widgets = <Widget>[
            GestureDetector(
              onTap: () => forceStage(state),
              child: _StageNode(label: label, color: color, active: isActive),
            ),
          ];
          if (e.key < stages.length - 1) {
            widgets.add(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 12, height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    FluxForgeTheme.textTertiary.withValues(alpha: 0.0),
                    FluxForgeTheme.textTertiary.withValues(alpha: 0.4),
                    FluxForgeTheme.textTertiary.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ));
          }
          return widgets;
        }).toList(),
      ),
    );
  }

  Widget _buildWaveformBars(Color color) {
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _waveBars.map((h) => Container(
          width: 3, height: h,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [color, color.withValues(alpha: 0)],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        )).toList(),
      ),
    );
  }

  /// Combined waveform + stage strip row — sits BETWEEN canvas and dock.
  /// Moved out of Canvas Stack to avoid blocking PremiumSlotPreview Control Bar.
  Widget _buildStageRow(GameFlowProvider flow) {
    final stage = flow.currentState;
    final glowColor = _stageGlowColor(stage);
    return Container(
      height: 48,
      color: FluxForgeTheme.bgDeep,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Waveform bars — decorative, behind stage strip
          IgnorePointer(child: _buildWaveformBars(glowColor)),
          // Stage strip — fully interactive (no blocking from canvas)
          _buildStageStrip(stage, flow),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMMAND DOCK
  // ─────────────────────────────────────────────────────────────────────────

  // Dock tab catalog. Migrated from positional record `(IconData, String, Color)`
  // to named record `({String id, IconData icon, String label, Color color})`
  // — fixes audit nalaz #9 readability concern.
  //
  // The `id` field is the foundation for a future `DockTabRegistry.register(...)`
  // plugin extension point: callers will be able to filter/insert by stable id
  // instead of bare list index, which lets third-party plugins inject tabs
  // without conflicting on numeric position.
  //
  // TODO(URP-future): When the plugin marketplace lands, lift this list into a
  // `DockTabRegistry` singleton with `register({id, icon, label, color, builder})`.
  // The current `switch(_dockTab)` in `_buildDockPanel` will dispatch via the
  // registry's builder for each id.
  // 2026-05-10 (Sprint 14 Faza 4.B.5+B.3) — `tooltip` i `wip` polja.
  // Pre-fix: korisnik je imao 13 ikonica + label-a bez objašnjenja čemu
  // svaki služi.  Pa kad klikne na SFX/BT/DNA/AI/CLOUD/A/B paneli su
  // izgledali funkcionalno — quick actions su međutim bili dead (() {}).
  //
  // Faza 4.B.5: svaki tab ima 1-line tooltip (hover → 600ms).
  // Faza 4.B.3: `wip: true` tabovi se vizuelno dim-uju (60 % opacity) +
  //             dobiju strikethrough na label-u tako da je očigledno da
  //             je tab work-in-progress, ali ostaju klikabilni (otvore
  //             panel + prikažu WIP toast iz Faza 4.A.2).
  static const List<({String id, IconData icon, String label, Color color, String tooltip, bool wip})> _dockTabDefs = [
    (id: 'flow',     icon: Icons.account_tree_rounded, label: 'FLOW',     color: FluxForgeTheme.accentBlue,   tooltip: 'Game state transitions + feature mechanics graph',                            wip: false),
    (id: 'audio',    icon: Icons.graphic_eq_rounded,   label: 'AUDIO',    color: FluxForgeTheme.accentCyan,   tooltip: 'Event matrix — 281 stages, per-layer parameter editor',                       wip: false),
    (id: 'math',     icon: Icons.functions_rounded,    label: 'MATH',     color: FluxForgeTheme.accentGreen,  tooltip: 'RTP verification + paytable analysis + recalc',                               wip: false),
    (id: 'timeline', icon: Icons.timeline_rounded,     label: 'TIMELINE', color: FluxForgeTheme.accentOrange, tooltip: 'Stage sequence playback + replay + jump-to-stage',                            wip: false),
    (id: 'intel',    icon: Icons.psychology_rounded,   label: 'INTEL',    color: FluxForgeTheme.accentPurple, tooltip: 'AI co-pilot + RGAI compliance + neuro audio state',                           wip: false),
    (id: 'export',   icon: Icons.upload_rounded,       label: 'EXPORT',   color: FluxForgeTheme.accentYellow, tooltip: 'Batch export → Wwise / FMOD / Unity / Unreal / Godot',                        wip: false),
    // ── FAZA 3 tabs (UI scaffolded, quick actions WIP — Sprint 15) ──
    (id: 'sfx',      icon: Icons.auto_fix_high_rounded,label: 'SFX',      color: FluxForgeTheme.accentCyan,   tooltip: 'Sound FX pipeline wizard — WIP, dock-actions Sprint 15',                      wip: true),
    (id: 'bt',       icon: Icons.hub_rounded,          label: 'BT',       color: FluxForgeTheme.accentOrange, tooltip: 'Behavior Tree visual editor — WIP, dock-actions Sprint 15',                   wip: true),
    (id: 'dna',      icon: Icons.fingerprint_rounded,  label: 'DNA',      color: FluxForgeTheme.accentPink,   tooltip: 'Audio DNA / brand fingerprint — WIP, dock-actions Sprint 15',                 wip: true),
    (id: 'ai_gen',   icon: Icons.auto_awesome_rounded, label: 'AI GEN',   color: FluxForgeTheme.accentPurple, tooltip: 'AI audio generation pipeline — WIP, dock-actions Sprint 15',                  wip: true),
    (id: 'cloud',    icon: Icons.cloud_sync_rounded,   label: 'CLOUD',    color: FluxForgeTheme.accentBlue,   tooltip: 'Cloud sync (Firebase/AWS/custom) — WIP, dock-actions Sprint 15',              wip: true),
    (id: 'ab',       icon: Icons.science_rounded,      label: 'A/B',      color: FluxForgeTheme.accentGreen,  tooltip: 'A/B split testing — WIP, dock-actions Sprint 15',                             wip: true),
    // Model 3 — multi-provider AI Composer (Local / BYOK / Azure)
    (id: 'composer', icon: Icons.smart_toy_rounded,    label: 'COMPOSER', color: FluxForgeTheme.accentGreen,  tooltip: 'Multi-provider AI Composer — Local / BYOK / Azure',                           wip: false),
  ];

  /// Resolves the active dock height for the current mode.
  ///   COMPOSE  → user-resizable, persisted across mode toggles.
  ///   FOCUS    → caller hides the dock entirely (we still return a value
  ///              so AnimatedContainer doesn't NaN; FOCUS path is gated
  ///              upstream in the layout `bottom:` calc).
  ///   ARCHITECT → lazy-init to 50% of screen on first build, then
  ///              user-resizable from there.
  double _resolveDockHeight() {
    if (_mode == 2) {
      if (_dockHeightArchitect < 0) {
        // First-time enter: seed from 50% screen height.
        return MediaQuery.of(context).size.height * 0.5;
      }
      return _dockHeightArchitect;
    }
    return _dockHeightCompose;
  }

  Widget _buildDock() {
    final dockH = _resolveDockHeight();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: dockH,
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeepest, // #08080C — matches mockup --abyss
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
      ),
      child: Column(
        children: [
          // Tab bar
          _buildDockTabBar(),
          // SPEC-09: Quick Actions Strip — contextual per dock tab
          _buildQuickActionsStrip(),
          // Panel content
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: _buildDockPanel(),
          )),
        ],
      ),
    );
  }

  // ── SPEC-09: Quick Actions Strip ─────────────────────────────────────────
  // 32px contextual strip beneath the dock tab bar.
  // Each dock tab exposes its most-used actions inline, no digging into panels.
  Widget _buildQuickActionsStrip() {
    final actions = _quickActionsForTab(_dockTab);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: actions.map((a) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _QuickActionPill(action: a),
          )).toList(),
        ),
      ),
    );
  }

  List<_QuickAction> _quickActionsForTab(int tab) {
    switch (tab) {
      case 0: // FLOW
        return [
          _QuickAction(
            icon: Icons.play_arrow_rounded, label: 'SPIN',
            color: FluxForgeTheme.accentBlue,
            onTap: () => silentRun('quickAction.flowBaseGame', () {
              GetIt.instance<GameFlowProvider>().forceTransition(GameFlowState.baseGame);
            }),
          ),
          _QuickAction(
            icon: Icons.star_rounded, label: 'FREE',
            color: FluxForgeTheme.accentYellow,
            onTap: () => silentRun('quickAction.flowFreeSpins', () {
              GetIt.instance<GameFlowProvider>().forceTransition(GameFlowState.freeSpins);
            }),
          ),
          _QuickAction(
            icon: Icons.emoji_events_rounded, label: 'JACKPOT',
            color: FluxForgeTheme.accentOrange,
            onTap: () => silentRun('quickAction.flowJackpot', () {
              GetIt.instance<GameFlowProvider>().forceTransition(GameFlowState.jackpotPresentation);
            }),
          ),
          _QuickAction(
            icon: Icons.casino_rounded, label: 'BONUS',
            color: FluxForgeTheme.accentPurple,
            onTap: () => silentRun('quickAction.flowBonus', () {
              GetIt.instance<GameFlowProvider>().forceTransition(GameFlowState.bonusGame);
            }),
          ),
          _QuickAction(
            icon: Icons.restart_alt_rounded, label: 'RESET',
            color: FluxForgeTheme.textTertiary,
            onTap: () => silentRun('quickAction.flowReset', () {
              GetIt.instance<GameFlowProvider>().forceTransition(GameFlowState.idle);
            }),
          ),
        ];
      case 1: // AUDIO
        return [
          _QuickAction(
            icon: Icons.volume_off_rounded, label: 'MUTE ALL',
            color: FluxForgeTheme.accentCyan,
            onTap: () => silentRun('quick_action MUTE ALL', () {
              final mixer = GetIt.instance<OrbMixerProvider>();
              if (!mixer.master.muted) mixer.toggleMute(OrbBusId.master);
            }),
          ),
          _QuickAction(
            icon: Icons.volume_up_rounded, label: 'UNMUTE',
            color: FluxForgeTheme.accentCyan,
            onTap: () => silentRun('quick_action UNMUTE', () {
              final mixer = GetIt.instance<OrbMixerProvider>();
              if (mixer.master.muted) mixer.toggleMute(OrbBusId.master);
            }),
          ),
          _QuickAction(
            icon: Icons.stop_rounded, label: 'STOP ALL',
            color: FluxForgeTheme.accentOrange,
            onTap: () => silentRun('quickAction.audioStopAll', () { GetIt.instance<AudioPlaybackService>().stopAll(); }),
          ),
          _QuickAction(
            icon: Icons.refresh_rounded, label: 'RELOAD',
            color: FluxForgeTheme.textTertiary,
            onTap: () => silentRun('quickAction.audioReload', () {
              // Implements FLUX_MASTER_TODO 0.5 G.7 (Sprint 11) — hot-reload audio
              // assets from disk. Validira da li svi audio path-ovi u
              // _audioAssignments još uvek postoje, uklanja broken bindings,
              // notify-uje downstream. Slot designer ne mora restartovati
              // app kad obriše/preimenuje audio file na disku.
              final proj = GetIt.instance<SlotLabProjectProvider>();
              final summary = proj.validateAndReloadAssignments();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 3),
                    backgroundColor: FluxForgeTheme.bgElevated,
                    content: Text(
                      '🔄 ${summary.summaryLine}',
                      style: FluxForgeTheme.dockSans(
                        color: summary.removed > 0
                            ? FluxForgeTheme.accentOrange
                            : FluxForgeTheme.accentGreen,
                      ),
                    ),
                  ),
                );
              }
            }),
          ),
        ];
      case 2: // MATH
        return [
          _QuickAction(
            icon: Icons.check_circle_outline_rounded, label: 'VERIFY RTP',
            color: FluxForgeTheme.accentGreen,
            onTap: () => silentRun('quickAction.mathVerifyRtp', () { EventRegistry.instance.triggerStage('MATH_VERIFY_RTP'); }),
          ),
          _QuickAction(
            icon: Icons.calculate_rounded, label: 'RECALC',
            color: FluxForgeTheme.accentCyan,
            onTap: () => silentRun('quickAction.mathRecalc', () { EventRegistry.instance.triggerStage('MATH_RECALCULATE'); }),
          ),
          _QuickAction(
            icon: Icons.compare_rounded, label: 'COMPARE',
            color: FluxForgeTheme.accentPurple,
            onTap: () => silentRun('quickAction.mathCompare', () { EventRegistry.instance.triggerStage('MATH_COMPARE_BLUEPRINT'); }),
          ),
        ];
      case 3: // TIMELINE
        // 2026-05-09 — replaced 5 placeholder dock actions (PLAY/STOP/REC/
        // LOOP/GOTO_START) that just trigger-ed unbound TIMELINE_* stages
        // and produced silence.  Slot game is event-driven (SPIN owns the
        // transport), so we expose THREE actions that actually map onto
        // the SlotStageProvider lifecycle:
        //   • REPLAY LAST SPIN  → re-play the cached _lastStages sequence
        //                         through the same engine path as a real spin.
        //   • JUMP TO STAGE     → picker dialog over the cached stages so
        //                         you can audition any single stage in
        //                         isolation without firing a full spin.
        //   • CLEAR LAST SPIN   → drop the cache so REPLAY/JUMP go quiet
        //                         until the next real spin populates them.
        return [
          _QuickAction(
            icon: Icons.replay_rounded, label: 'REPLAY',
            color: FluxForgeTheme.accentOrange,
            onTap: _replayLastSpin,
          ),
          _QuickAction(
            icon: Icons.skip_next_rounded, label: 'JUMP',
            color: FluxForgeTheme.accentCyan,
            onTap: _showJumpToStageDialog,
          ),
          _QuickAction(
            icon: Icons.delete_sweep_rounded, label: 'CLEAR',
            color: FluxForgeTheme.textTertiary,
            onTap: _clearLastSpin,
          ),
        ];
      case 4: // INTEL
        return [
          _QuickAction(
            icon: Icons.analytics_rounded, label: 'ANALYZE',
            color: FluxForgeTheme.accentPurple,
            onTap: () => silentRun('quickAction.intelAnalyze', () { EventRegistry.instance.triggerStage('INTEL_ANALYZE'); }),
          ),
          _QuickAction(
            icon: Icons.summarize_rounded, label: 'REPORT',
            color: FluxForgeTheme.accentCyan,
            onTap: () => silentRun('quickAction.intelReport', () { EventRegistry.instance.triggerStage('INTEL_GENERATE_REPORT'); }),
          ),
          _QuickAction(
            icon: Icons.delete_sweep_rounded, label: 'CLEAR',
            color: FluxForgeTheme.textTertiary,
            onTap: () => silentRun('quickAction.intelClear', () { EventRegistry.instance.triggerStage('INTEL_CLEAR'); }),
          ),
        ];
      case 5: // EXPORT
        return [
          _QuickAction(
            icon: Icons.upload_file_rounded, label: 'EXPORT',
            color: FluxForgeTheme.accentYellow,
            onTap: () => silentRun('quickAction.exportQuick', () { EventRegistry.instance.triggerStage('EXPORT_QUICK'); }),
          ),
          _QuickAction(
            icon: Icons.queue_music_rounded, label: 'STEMS',
            color: FluxForgeTheme.accentCyan,
            onTap: () => silentRun('quickAction.exportStems', () { EventRegistry.instance.triggerStage('EXPORT_STEMS'); }),
          ),
          _QuickAction(
            icon: Icons.preview_rounded, label: 'PREVIEW',
            color: FluxForgeTheme.textTertiary,
            onTap: () => silentRun('quickAction.exportPreview', () { EventRegistry.instance.triggerStage('EXPORT_PREVIEW'); }),
          ),
        ];
      default:
        // Faza 3 stubs — minimal actions.
        //
        // 2026-05-10 (Sprint 14, Boki "ne radi mi"): pre-fix je imao
        // `onTap: () {}` koji silently progutaše klik bez ikakve poruke
        // korisniku, pa je 6 tabova izgledalo broken (SFX/BT/DNA/AI/CLOUD/A/B).
        // Sad svaki klik prikaže explicit "WIP — coming in next sprint"
        // SnackBar sa imenom tab-a tako da je status providerom vidljiv.
        final tabName = _dockTabDisplayName(tab);
        return [
          _QuickAction(
            icon: Icons.play_arrow_rounded, label: 'RUN',
            color: FluxForgeTheme.textSecondary,
            onTap: () => _showFeatureWipToast(tabName, action: 'RUN'),
          ),
          _QuickAction(
            icon: Icons.refresh_rounded, label: 'RESET',
            color: FluxForgeTheme.textTertiary,
            onTap: () => _showFeatureWipToast(tabName, action: 'RESET'),
          ),
        ];
    }
  }

  /// Display name for a dock tab index — used by stub WIP toast.
  String _dockTabDisplayName(int tab) {
    switch (tab) {
      case 0: return 'FLOW';
      case 1: return 'AUDIO';
      case 2: return 'MATH';
      case 3: return 'TIMELINE';
      case 4: return 'INTEL';
      case 5: return 'EXPORT';
      case 6: return 'SFX';
      case 7: return 'BT';
      case 8: return 'DNA';
      case 9: return 'AI GEN';
      case 10: return 'CLOUD';
      case 11: return 'A/B';
      case 12: return 'COMPOSER';
      default: return 'tab #$tab';
    }
  }

  /// Toast for WIP / stub feature interactions.
  ///
  /// Replaces the previous silent `onTap: () {}` pattern that left
  /// 6 dock tabs feeling broken (Boki "ne radi mi" — Sprint 14 audit).
  /// The user now sees an explicit confirmation that the click was
  /// received and that the feature is intentionally pending.
  void _showFeatureWipToast(String featureName, {String? action}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final actionPart = action == null ? '' : '$action: ';
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${actionPart}$featureName — work-in-progress, coming in next sprint',
          style: FluxForgeTheme.dockMono(
            size: 11,
            color: FluxForgeTheme.textPrimary,
          ),
        ),
        backgroundColor: FluxForgeTheme.bgElevated,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDockTabBar() {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xB3060608), // rgba(6,6,10,0.7) — matches mockup .dock-tabbar
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16), // 16px start padding — matches mockup
          // Scrollable tab area.
          // H-017 (HELIX_AUDIT 2026-05-07): Stack overlays a 24 px gradient
          // fade on the right edge so users get a visual hint that more
          // tabs are off-screen (the SingleChildScrollView gives no native
          // affordance).  IgnorePointer keeps the gradient out of the
          // scroll/tap path.
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _dockTabDefs.asMap().entries.map((e) {
                      final def = e.value;
                      final active = _dockTab == e.key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: _DockTab(
                          icon: def.icon, label: def.label, color: def.color,
                          active: active,
                          tooltip: def.tooltip, // Sprint 14 Faza 4.B.5
                          wip: def.wip,         // Sprint 14 Faza 4.B.3
                          onTap: () => setState(() => _dockTab = e.key),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: IgnorePointer(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0x00060608),
                            Color(0xB3060608),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Resize handle — hambuger style, easy to grab.
          //
          // Updates the height belonging to the currently-active mode so
          // mode-switching never destroys a user's custom resize (fixes
          // audit nalaz #5). ARCHITECT gets a higher upper clamp because
          // it's the analyst-style large-canvas mode.
          //
          // COMPOSE upper clamp scales with screen height (audit nalaz #10):
          // small screens stay at 600px (preserves slot preview real estate),
          // large screens (multi-monitor / 4K) get up to 65% of screen height.
          // This keeps the productive lower bound while letting power users
          // on big displays actually use the space.
          GestureDetector(
            onVerticalDragUpdate: (d) => setState(() {
              final screenH = MediaQuery.of(context).size.height;
              if (_mode == 2) {
                final base = _dockHeightArchitect < 0
                    ? screenH * 0.5
                    : _dockHeightArchitect;
                final maxH = screenH * 0.9;
                _dockHeightArchitect = (base - d.delta.dy).clamp(180.0, maxH);
              } else {
                final maxComposeH = math.max(600.0, screenH * 0.65);
                _dockHeightCompose = (_dockHeightCompose - d.delta.dy).clamp(180.0, maxComposeH);
              }
            }),
            // SPEC-16 — uniform tooltip surface (150ms delay, brand-gold
            // border, optional shortcut hint). Pre-migration this was a
            // raw `Tooltip(message: ...)` with the platform default
            // long-press / 1500ms hover delay and dark grey background.
            child: FluxTooltip(
              message: 'Drag to resize',
              shortcutHint: 'drag · vertical',
              child: SizedBox(
                width: 44, height: 44,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 18, height: 2,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(1))),
                    const SizedBox(height: 3),
                    Container(width: 12, height: 2,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(1))),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildDockPanel() {
    return switch (_dockTab) {
      0 => const _FlowPanel(),
      1 => const _AudioPanel(),
      2 => const _MathPanel(),
      3 => const _TimelinePanel(),
      4 => const _IntelPanel(),
      5 => const _ExportPanel(),
      6 => const _SfxPipelinePanel(),
      7 => const _BehaviorTreePanel(),
      8 => const _AudioDnaPanel(),
      9 => const _AiGenerationPanel(),
      10 => const _CloudSyncPanel(),
      11 => const _AbTestPanel(),
      12 => const AiComposerPanel(),
      _ => const SizedBox(),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCK PANELS
// ─────────────────────────────────────────────────────────────────────────────


// ══════════════════════════════════════════════════════════════════════════════
// FAZA 3 — ADVANCED AUTHORING PANELS
// ═══════════════════════════════════════════════════════════════════════════════





// ── 3.3 PAR Import Panel (integrated into SFX Pipeline) ─────────────────────
// PAR file import is handled through the SFX Pipeline's namingAssign step
// with auto-mapping from paytable CSV/PAR files to game stages.
// The SfxPipelineProvider.setStageMappings() method handles this.






// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE COMPONENTS
// (extracted to part files — see helix/ subdirectory)
// ─────────────────────────────────────────────────────────────────────────────

// _HBtn removed — unused widget (panels use inline buttons with specific styling)
// _OmniPill, _OmniIconBtn, _ModeBadge, _TransportBtn → helix/helix_omnibar_atoms.dart
// _DockTab, _DockCard, _DockLabel               → helix/helix_dock_widgets.dart
// _MiniModeSection, _MiniDivider, _ComplianceDot → helix/helix_minimode_widgets.dart





// _DockTab, _DockCard, _DockLabel → helix/helix_dock_widgets.dart (part file)

// ─────────────────────────────────────────────────────────────────────────────
// INTERACTIVE TIMELINE TRACK (T1)
// ─────────────────────────────────────────────────────────────────────────────


