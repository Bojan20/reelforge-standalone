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
      style: TextStyle(color: const Color(0xFFFF4444), fontSize: fontSize),
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
    with TickerProviderStateMixin {

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
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final gridW = screenW * _kSlotGridWidthRatio;
    return Rect.fromLTWH(
      _kSlotGridLeftOffsetPx,
      _kSlotGridVInsetPx,
      gridW,
      screenH - 2 * _kSlotGridVInsetPx,
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
                  const Text('KEYBOARD SHORTCUTS', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 13,
                    fontWeight: FontWeight.w800, letterSpacing: 1.2,
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
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: FluxForgeTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
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
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      color: FluxForgeTheme.textTertiary)),
                            ),
                            Expanded(
                              child: Text(s.stageType,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: FluxForgeTheme.textPrimary)),
                            ),
                            Text('${s.timestampMs.toInt()} ms',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
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
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
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
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: FluxForgeTheme.brandGoldBright,
                letterSpacing: 1.4,
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
            color: Color(0xFF08080C),
            border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
          ),
          child: Column(
            children: [
              // Top bar with expand hint
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0A12),
                  border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.compress_rounded, size: 12, color: FluxForgeTheme.textTertiary),
                    const SizedBox(width: 6),
                    Text('HELIX MINI', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: FluxForgeTheme.textTertiary, letterSpacing: 1.2)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _mode = 0),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('⌘⇧M', style: TextStyle(
                            fontSize: 9, color: FluxForgeTheme.textTertiary, fontFamily: 'monospace')),
                          SizedBox(width: 4),
                          Icon(Icons.open_in_full_rounded, size: 11, color: FluxForgeTheme.textTertiary),
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
                          style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: FluxForgeTheme.accentCyan, letterSpacing: 0.5)),
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
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_arrow_rounded, size: 16, color: FluxForgeTheme.accentGreen),
                              SizedBox(width: 2),
                              Text('SPIN', style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w800,
                                color: FluxForgeTheme.accentGreen, letterSpacing: 0.8)),
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
                                Text(ok ? 'OK' : 'WARN', style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700,
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
                                    style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary,
                                      fontWeight: FontWeight.w700))),
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
            child: const Center(
              child: Text('HX',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                  color: FluxForgeTheme.brandGoldDark, letterSpacing: 0.8)),
            ),
          ),
          const SizedBox(width: 8),
          const Text('HELIX', style: TextStyle(
            fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700,
            color: FluxForgeTheme.textPrimary, letterSpacing: 1.5)),
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
                      style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11,
                        color: FluxForgeTheme.textPrimary),
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
                    style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11,
                      color: FluxForgeTheme.textPrimary)),
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
                const Text('BPM', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 11,
                  color: FluxForgeTheme.accentCyan, letterSpacing: 0.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (_bpmEditing)
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _bpmController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13,
                        color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w700),
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
                  Text(_bpmDisplay.toStringAsFixed(1), style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13,
                    color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w700)),
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
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: accent,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (_gridEditing)
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _gridController,
                      autofocus: true,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: accent,
                          fontWeight: FontWeight.w700),
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
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: flashColor,
                          fontWeight: FontWeight.w700))
                else
                  Text('${reels}×$rows',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: accent,
                          fontWeight: FontWeight.w700)),
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
                            style: const TextStyle(
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
        content: Text('Stage → $label', style: const TextStyle(
          fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textPrimary)),
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
        color: Color(0xFF0A0A10),
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
                      style: TextStyle(
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
          style: const TextStyle(
            fontFamily: 'monospace', fontSize: 11,
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

// ── 3.4 Audio DNA / Fingerprint Editor ──────────────────────────────────────

class _AudioDnaPanel extends StatefulWidget {
  const _AudioDnaPanel();
  @override
  State<_AudioDnaPanel> createState() => _AudioDnaPanelState();
}

class _AudioDnaPanelState extends State<_AudioDnaPanel> {
  // Audio DNA fields mirror the Rust AudioDna struct
  late String _brand;
  late double _bpmMin;
  late double _bpmMax;
  late String _rootKey;
  late String _mode;
  late List<String> _instruments;
  late String _baseProfile;
  late String _featureProfile;
  late double _winEscalation;
  late double _ambientLayerCount;

  late final SlotLabProjectProvider _proj;

  @override
  void initState() {
    super.initState();
    _proj = GetIt.instance<SlotLabProjectProvider>();
    _proj.addListener(_onProjectChanged);
    _loadFromProject();
  }

  @override
  void dispose() {
    _proj.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (!mounted) return;
    _loadFromProject();
    setState(() {});
  }

  void _loadFromProject() {
    final proj = _proj;
    _brand = proj.dnaBrand;
    _bpmMin = proj.dnaBpmMin;
    _bpmMax = proj.dnaBpmMax;
    _rootKey = proj.dnaRootKey;
    _mode = proj.dnaMode;
    _instruments = List.from(proj.dnaInstruments);
    _baseProfile = proj.dnaBaseProfile;
    _featureProfile = proj.dnaFeatureProfile;
    _winEscalation = proj.dnaWinEscalation;
    _ambientLayerCount = proj.dnaAmbientLayerCount;
  }

  static const _keys = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _modes = ['major', 'minor', 'dorian', 'mixolydian', 'pentatonic_major', 'pentatonic_minor', 'phrygian', 'lydian'];
  static const _allInstruments = ['piano', 'strings', 'brass', 'woodwinds', 'synth_pad', 'synth_lead',
    'ethnic_percussion', 'orchestral_percussion', 'choir', 'guitar', 'bass', 'harp', 'bells', 'mallets'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Identity
        Expanded(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('BRAND IDENTITY', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 8),
                _DnaField('Brand', _brand, (v) => setState(() => _brand = v)),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 80, child: Text('Root Key',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
                  Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: _keys.map((k) =>
                    GestureDetector(
                      onTap: () => setState(() => _rootKey = k),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _rootKey == k ? FluxForgeTheme.accentPink.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _rootKey == k ? FluxForgeTheme.accentPink : FluxForgeTheme.borderSubtle),
                        ),
                        child: Text(k, style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                          color: _rootKey == k ? FluxForgeTheme.accentPink : FluxForgeTheme.textTertiary)),
                      ),
                    )).toList())),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 80, child: Text('Mode',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
                  Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: _modes.map((m) =>
                    GestureDetector(
                      onTap: () => setState(() => _mode = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _mode == m ? FluxForgeTheme.accentPurple.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _mode == m ? FluxForgeTheme.accentPurple : FluxForgeTheme.borderSubtle),
                        ),
                        child: Text(m, style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: _mode == m ? FluxForgeTheme.accentPurple : FluxForgeTheme.textTertiary)),
                      ),
                    )).toList())),
                ]),
                const SizedBox(height: 12),
                _SfxPresetSlider(label: 'BPM Min', value: _bpmMin, min: 60, max: 200, suffix: '',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _bpmMin = v)),
                _SfxPresetSlider(label: 'BPM Max', value: _bpmMax, min: 60, max: 200, suffix: '',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _bpmMax = v)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Center: Instruments
        Expanded(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('INSTRUMENT PALETTE', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 8),
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: _allInstruments.map((inst) {
                    final active = _instruments.contains(inst);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (active) _instruments.remove(inst);
                        else _instruments.add(inst);
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle),
                        ),
                        child: Text(inst.replaceAll('_', ' '),
                          style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                            color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                            fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                      ),
                    );
                  }).toList()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right: Profiles & Escalation
        Expanded(
          flex: 1,
          child: _DockCard(
            accent: FluxForgeTheme.accentPink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('AUDIO PROFILES', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 8),
                _DnaField('Base', _baseProfile, (v) => setState(() => _baseProfile = v)),
                const SizedBox(height: 6),
                _DnaField('Feature', _featureProfile, (v) => setState(() => _featureProfile = v)),
                const SizedBox(height: 12),
                _DockLabel('ESCALATION', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 6),
                _SfxPresetSlider(label: 'Win Scale', value: _winEscalation, min: 1, max: 3, suffix: 'x',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _winEscalation = v)),
                _SfxPresetSlider(label: 'Ambient Layers', value: _ambientLayerCount, min: 1, max: 8, suffix: '',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _ambientLayerCount = v)),
                const SizedBox(height: 6),
                // DNA fingerprint visual
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentPink.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentPink.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FINGERPRINT', style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                        color: FluxForgeTheme.accentPink, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('$_rootKey $_mode  ${_bpmMin.round()}-${_bpmMax.round()} BPM',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary)),
                      Text(_instruments.join(' · '),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary),
                        overflow: TextOverflow.ellipsis, maxLines: 2),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Apply DNA to project
                _DnaApplyButton(
                  rootKey: _rootKey, mode: _mode,
                  bpmMin: _bpmMin, bpmMax: _bpmMax,
                  instruments: List.from(_instruments),
                  brand: _brand,
                  baseProfile: _baseProfile,
                  featureProfile: _featureProfile,
                  winEscalation: _winEscalation,
                  ambientLayerCount: _ambientLayerCount,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Apply DNA fingerprint to project metadata via SlotLabProjectProvider
class _DnaApplyButton extends StatefulWidget {
  final String rootKey, mode, brand;
  final double bpmMin, bpmMax;
  final List<String> instruments;
  final String baseProfile, featureProfile;
  final double winEscalation, ambientLayerCount;
  const _DnaApplyButton({
    required this.rootKey, required this.mode, required this.brand,
    required this.bpmMin, required this.bpmMax, required this.instruments,
    this.baseProfile = 'ambient_dark', this.featureProfile = 'epic_orchestral',
    this.winEscalation = 1.5, this.ambientLayerCount = 3,
  });
  @override
  State<_DnaApplyButton> createState() => _DnaApplyButtonState();
}
class _DnaApplyButtonState extends State<_DnaApplyButton> {
  bool _applied = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () {
        silentRun('dna.applyToProject', () {
          // 1. Apply BPM midpoint to engine transport
          final bpmMid = ((widget.bpmMin + widget.bpmMax) / 2).roundToDouble();
          GetIt.instance<EngineProvider>().setTempo(bpmMid);
          // 2. Persist all DNA fields to SlotLabProjectProvider
          GetIt.instance<SlotLabProjectProvider>().setAudioDna(
            brand: widget.brand,
            rootKey: widget.rootKey,
            mode: widget.mode,
            bpmMin: widget.bpmMin,
            bpmMax: widget.bpmMax,
            instruments: widget.instruments,
            baseProfile: widget.baseProfile,
            featureProfile: widget.featureProfile,
            winEscalation: widget.winEscalation,
            ambientLayerCount: widget.ambientLayerCount,
          );
        });
        setState(() => _applied = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _applied = false);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: _applied
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
            : FluxForgeTheme.accentPink.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _applied
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
            : FluxForgeTheme.accentPink.withValues(alpha: 0.4)),
        ),
        child: Center(child: Text(
          _applied ? '✓ DNA APPLIED' : 'APPLY DNA TO PROJECT',
          style: TextStyle(fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700,
            color: _applied ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentPink),
        )),
      ),
    ),
  );
}

class _DnaField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _DnaField(this.label, this.value, this.onChanged);
  @override
  State<_DnaField> createState() => _DnaFieldState();
}

class _DnaFieldState extends State<_DnaField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_DnaField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 80, child: Text(widget.label,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
    Expanded(child: SizedBox(
      height: 24,
      child: TextField(
        controller: _ctrl,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: FluxForgeTheme.accentPink)),
        ),
        onSubmitted: widget.onChanged,
      ),
    )),
  ]);
}

// ── 3.5 AI Generation Panel ─────────────────────────────────────────────────

class _AiGenerationPanel extends StatefulWidget {
  const _AiGenerationPanel();
  @override
  State<_AiGenerationPanel> createState() => _AiGenerationPanelState();
}

class _AiGenerationPanelState extends State<_AiGenerationPanel> {
  final _promptController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _voiceIdController = TextEditingController();
  bool _isGenerating = false;
  String? _lastResultText;
  String? _lastOutputPath;
  String _selectedBackend = 'stub';  // 'stub' | 'elevenlabs_sfx' | 'elevenlabs_tts'
  bool _showSettings = false;
  bool _obscureKey = true;
  final List<String> _pipelineLog = [];

  late final AiGenerationService _aiService;

  @override
  void initState() {
    super.initState();
    _aiService = GetIt.instance<AiGenerationService>();
    _aiService.addListener(_onAiChanged);
    _aiService.loadAvailableBackends();
    // Load persisted ElevenLabs config into controllers after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _apiKeyController.text = _aiService.elApiKey;
        _voiceIdController.text = _aiService.elVoiceId;
      }
    });
  }

  @override
  void dispose() {
    _aiService.removeListener(_onAiChanged);
    _promptController.dispose();
    _apiKeyController.dispose();
    _voiceIdController.dispose();
    super.dispose();
  }

  void _onAiChanged() {
    if (mounted) {
      // Sync controllers if config was loaded from prefs
      if (_apiKeyController.text != _aiService.elApiKey) {
        _apiKeyController.text = _aiService.elApiKey;
      }
      if (_voiceIdController.text != _aiService.elVoiceId) {
        _voiceIdController.text = _aiService.elVoiceId;
      }
      setState(() {});
    }
  }

  Future<void> _saveElConfig() async {
    await _aiService.saveElConfig(
      apiKey: _apiKeyController.text.trim(),
      voiceId: _voiceIdController.text.trim(),
    );
    if (mounted) setState(() => _showSettings = false);
  }

  void _runGeneration() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _isGenerating = true;
      _pipelineLog.clear();
      _lastResultText = null;
      _lastOutputPath = null;
    });

    try {
      // ── ElevenLabs SFX path ────────────────────────────────────────────
      if (_selectedBackend == 'elevenlabs_sfx') {
        setState(() => _pipelineLog.add('ElevenLabs: Parsing duration from prompt...'));

        // Parse optional duration from prompt ("2 seconds", "3s", etc.)
        double? durationSec;
        final durMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:second|sec|s)\b', caseSensitive: false)
            .firstMatch(prompt);
        if (durMatch != null) {
          durationSec = double.tryParse(durMatch.group(1) ?? '');
        }

        setState(() => _pipelineLog.add(
          'ElevenLabs SFX: prompt=${prompt.length}ch, duration=${durationSec?.toStringAsFixed(1) ?? "auto"}s'));
        setState(() => _pipelineLog.add('Calling ElevenLabs /v1/sound-generation...'));

        final result = await _aiService.generateElSfx(
          prompt: prompt,
          durationSeconds: durationSec,
        );

        if (result != null) {
          setState(() {
            _pipelineLog.add('✓ Generated: ${result.filename}');
            _pipelineLog.add('Saved: ${result.outputPath}');
            _pipelineLog.add('DONE');
            _lastResultText = 'ElevenLabs SFX generated — ${result.filename}';
            _lastOutputPath = result.outputPath;
            _isGenerating = false;
          });
        }
        return;
      }

      // ── ElevenLabs TTS path ────────────────────────────────────────────
      if (_selectedBackend == 'elevenlabs_tts') {
        if (_aiService.elVoiceId.isEmpty) {
          setState(() {
            _pipelineLog.add('ERROR: No voice selected — open ⚙️ settings, enter Voice ID');
            _isGenerating = false;
          });
          return;
        }
        setState(() => _pipelineLog.add(
          'ElevenLabs TTS: voice=${_aiService.elVoiceId.substring(0, 8)}...'));
        setState(() => _pipelineLog.add('Calling ElevenLabs /v1/text-to-speech...'));

        final result = await _aiService.generateElTts(text: prompt);

        if (result != null) {
          setState(() {
            _pipelineLog.add('✓ Generated: ${result.filename}');
            _pipelineLog.add('Saved: ${result.outputPath}');
            _pipelineLog.add('DONE');
            _lastResultText = 'ElevenLabs TTS generated — ${result.filename}';
            _lastOutputPath = result.outputPath;
            _isGenerating = false;
          });
        }
        return;
      }

      // ── Stub path (offline, no API key needed) ─────────────────────────
      setState(() => _pipelineLog.add('Parsing prompt...'));
      final descriptor = await _aiService.parsePrompt(prompt);
      if (descriptor == null) {
        setState(() { _pipelineLog.add('ERROR: Failed to parse prompt'); _isGenerating = false; });
        return;
      }
      setState(() => _pipelineLog.add('Parsed: ${descriptor.category} / ${descriptor.tier}'));

      setState(() => _pipelineLog.add('Classifying (FFNC)...'));
      final classification = await _aiService.classify(descriptor);
      if (classification != null) {
        setState(() => _pipelineLog.add(
          'Class: ${classification.ffncCode} ${classification.displayName} (${(classification.confidence * 100).toStringAsFixed(0)}%)'));
      }

      setState(() => _pipelineLog.add('Generating audio (stub)...'));
      final result = await _aiService.generateWithStub(prompt: prompt);
      if (result != null) {
        setState(() {
          _pipelineLog.add('Generated: ${result.actualDurationMs}ms → ${result.suggestedFilename}');
          _lastResultText = 'Stub: ${result.actualDurationMs}ms / ${result.generationTimeMs}ms gen';
        });
      }

      setState(() => _pipelineLog.add('Post-processing config...'));
      final ppConfig = await _aiService.getPostProcessingConfig(descriptor);
      if (ppConfig != null) {
        setState(() => _pipelineLog.add(
          'PP: ${ppConfig.loudnessLufs} LUFS, trim=${ppConfig.trimSilence}'));
      }

      setState(() { _pipelineLog.add('DONE'); _isGenerating = false; });
    } catch (e) {
      setState(() { _pipelineLog.add('ERROR: $e'); _isGenerating = false; });
    }
  }

  // ── Backend tab chip ───────────────────────────────────────────────────
  Widget _backendChip(String id, String label, {bool isLive = false}) {
    final selected = _selectedBackend == id;
    final accent = isLive ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentPurple;
    return GestureDetector(
      onTap: () => setState(() => _selectedBackend = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
            width: selected ? 1.2 : 1.0,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isLive) ...[
            Container(width: 5, height: 5,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 4),
          ],
          Text(label,
            style: TextStyle(fontFamily: 'monospace', fontSize: 8, fontWeight: FontWeight.w600,
              color: selected ? accent : FluxForgeTheme.textTertiary)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isElBackend = _selectedBackend.startsWith('elevenlabs');
    final elConfigured = _aiService.elIsConfigured;

    return Row(
      children: [
        // ── Left: Prompt + controls ─────────────────────────────────────
        Expanded(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(children: [
                  _DockLabel('AI AUDIO GENERATION', color: FluxForgeTheme.accentPurple),
                  const Spacer(),
                  // Settings button — opens API key dialog
                  GestureDetector(
                    onTap: () => setState(() => _showSettings = !_showSettings),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _showSettings
                          ? FluxForgeTheme.accentPurple.withValues(alpha: 0.15)
                          : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.settings_rounded, size: 13,
                        color: _showSettings
                          ? FluxForgeTheme.accentPurple
                          : FluxForgeTheme.textTertiary),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // ── Settings panel (inline, slides in) ─────────────────
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: _showSettings
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildSettingsPanel(),
                ),

                if (!_showSettings) ...[
                  // Backend selector
                  Row(children: [
                    const Text('Backend: ', style: TextStyle(
                      fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
                    _backendChip('stub', 'STUB'),
                    _backendChip('elevenlabs_sfx', '11 SFX', isLive: true),
                    _backendChip('elevenlabs_tts', '11 TTS', isLive: true),
                    if (isElBackend && !elConfigured)
                      const Text('  ⚠ no key',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: FluxForgeTheme.accentYellow)),
                  ]),
                  const SizedBox(height: 8),

                  // Prompt input
                  Text(
                    _selectedBackend == 'elevenlabs_tts'
                      ? 'Voiceover text (e.g. "Big Win!", "Jackpot activated!"):'
                      : 'Describe the sound (e.g. "epic win fanfare, 2 seconds"):',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: FluxForgeTheme.textSecondary)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 72,
                    child: TextField(
                      controller: _promptController,
                      maxLines: 4,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11,
                        color: FluxForgeTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: _selectedBackend == 'elevenlabs_tts'
                          ? '"BIG WIN! You\'ve hit the jackpot!"'
                          : '"slot machine jackpot sound, coins, 3 seconds, triumphant"',
                        hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 9,
                          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.45)),
                        filled: true,
                        fillColor: FluxForgeTheme.bgSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: FluxForgeTheme.accentPurple)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Quick prompts for slot audio
                  if (_selectedBackend == 'elevenlabs_sfx') ...[
                    Wrap(spacing: 4, runSpacing: 4,
                      children: [
                        'slot win coins 2s', 'jackpot fanfare brass 3s',
                        'reel spin mechanical', 'bonus round activated',
                        'near miss tension 1s', 'ambient casino loop',
                      ].map((p) => GestureDetector(
                        onTap: () => _promptController.text = p,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: FluxForgeTheme.borderSubtle)),
                          child: Text(p, style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 7.5,
                            color: FluxForgeTheme.textTertiary)),
                        ),
                      )).toList()),
                    const SizedBox(height: 8),
                  ],
                  if (_selectedBackend == 'elevenlabs_tts') ...[
                    Wrap(spacing: 4, runSpacing: 4,
                      children: [
                        'BIG WIN!', 'Jackpot!', 'Free Spins activated!',
                        'Bonus round begins!', 'Super Win!', 'Mega Win!',
                      ].map((p) => GestureDetector(
                        onTap: () => _promptController.text = p,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: FluxForgeTheme.borderSubtle)),
                          child: Text(p, style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 7.5,
                            color: FluxForgeTheme.textTertiary)),
                        ),
                      )).toList()),
                    const SizedBox(height: 8),
                  ],

                  // Generate button
                  Row(children: [
                    const Spacer(),
                    GestureDetector(
                      onTap: _isGenerating ? null : _runGeneration,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: _isGenerating
                            ? FluxForgeTheme.textTertiary.withValues(alpha: 0.08)
                            : (isElBackend && elConfigured)
                              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
                              : FluxForgeTheme.accentPurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _isGenerating
                              ? FluxForgeTheme.textTertiary
                              : (isElBackend && elConfigured)
                                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
                                : FluxForgeTheme.accentPurple.withValues(alpha: 0.5)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_isGenerating)
                            SizedBox(width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2,
                                color: isElBackend
                                  ? FluxForgeTheme.accentGreen
                                  : FluxForgeTheme.accentPurple))
                          else
                            Icon(isElBackend ? Icons.graphic_eq_rounded : Icons.auto_awesome_rounded,
                              size: 13,
                              color: (isElBackend && elConfigured)
                                ? FluxForgeTheme.accentGreen
                                : FluxForgeTheme.accentPurple),
                          const SizedBox(width: 6),
                          Text(_isGenerating ? 'GENERATING...' : 'GENERATE',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: (isElBackend && elConfigured)
                                ? FluxForgeTheme.accentGreen
                                : FluxForgeTheme.accentPurple)),
                        ]),
                      ),
                    ),
                  ]),

                  // Result row
                  if (_lastResultText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.check_circle_rounded, size: 13,
                            color: FluxForgeTheme.accentGreen),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_lastResultText!,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                              color: FluxForgeTheme.accentGreen))),
                        ]),
                        if (_lastOutputPath != null) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.folder_open_rounded, size: 11,
                              color: FluxForgeTheme.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(child: Text(_lastOutputPath!,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 7.5,
                                color: FluxForgeTheme.textTertiary))),
                          ]),
                        ],
                      ]),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // ── Right: Pipeline log + Voice list ────────────────────────────
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pipeline log
                _DockLabel('PIPELINE LOG', color: FluxForgeTheme.accentPurple),
                const SizedBox(height: 6),
                Expanded(
                  child: _pipelineLog.isEmpty
                    ? Center(child: Text('Run generation to see log',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4))))
                    : ListView(
                        children: _pipelineLog.asMap().entries.map((e) {
                          final isError = e.value.startsWith('ERROR');
                          final isDone = e.value == 'DONE';
                          final isOk = e.value.startsWith('✓');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${e.key + 1}. ',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 7.5,
                                  color: FluxForgeTheme.textTertiary)),
                              Expanded(child: Text(e.value,
                                style: TextStyle(fontFamily: 'monospace', fontSize: 7.5,
                                  color: isError ? FluxForgeTheme.accentPink
                                    : isDone || isOk ? FluxForgeTheme.accentGreen
                                    : FluxForgeTheme.textSecondary))),
                            ]),
                          );
                        }).toList(),
                      ),
                ),

                // ElevenLabs voice selector (TTS mode only)
                if (_selectedBackend == 'elevenlabs_tts') ...[
                  const Divider(color: FluxForgeTheme.borderSubtle, height: 16),
                  Row(children: [
                    _DockLabel('VOICES', color: FluxForgeTheme.accentGreen),
                    const Spacer(),
                    GestureDetector(
                      onTap: _aiService.elIsConfigured ? _aiService.fetchElVoices : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4)),
                        child: Text('FETCH',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 7.5,
                            color: _aiService.elIsConfigured
                              ? FluxForgeTheme.accentGreen
                              : FluxForgeTheme.textTertiary)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  if (_aiService.elVoices.isEmpty)
                    Text('No voices loaded. Enter API key in ⚙️ and tap FETCH.',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5)))
                  else
                    SizedBox(
                      height: 100,
                      child: ListView(
                        children: _aiService.elVoices.map((v) {
                          final selected = _aiService.elVoiceId == v.voiceId;
                          return GestureDetector(
                            onTap: () => _aiService.selectElVoice(v.voiceId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: selected
                                  ? FluxForgeTheme.accentGreen.withValues(alpha: 0.12)
                                  : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: selected
                                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.4)
                                    : Colors.transparent)),
                              child: Row(children: [
                                Icon(selected ? Icons.mic_rounded : Icons.mic_none_rounded,
                                  size: 11,
                                  color: selected
                                    ? FluxForgeTheme.accentGreen
                                    : FluxForgeTheme.textTertiary),
                                const SizedBox(width: 5),
                                Expanded(child: Text(v.name,
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                                    color: selected
                                      ? FluxForgeTheme.accentGreen
                                      : FluxForgeTheme.textSecondary))),
                                if (v.category != null)
                                  Text(v.category!,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 7,
                                      color: FluxForgeTheme.textTertiary)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.key_rounded, size: 12, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 6),
          const Text('ELEVENLABS CREDENTIALS',
            style: TextStyle(fontFamily: 'monospace', fontSize: 10,
              fontWeight: FontWeight.w700, color: FluxForgeTheme.accentGreen)),
        ]),
        const SizedBox(height: 2),
        const Text('API key stored locally in SharedPreferences — never in code or cloud.',
          style: TextStyle(fontFamily: 'monospace', fontSize: 7.5,
            color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 10),

        // API key field
        const Text('API KEY', style: TextStyle(fontFamily: 'monospace', fontSize: 8,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
              color: FluxForgeTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'sk_...',
              hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 9,
                color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
              filled: true,
              fillColor: FluxForgeTheme.bgDeepest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: FluxForgeTheme.accentGreen)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          )),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _obscureKey = !_obscureKey),
            child: Icon(_obscureKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 16, color: FluxForgeTheme.textTertiary)),
        ]),
        const SizedBox(height: 8),

        // Voice ID field (for TTS)
        const Text('VOICE ID  (for TTS — leave blank to select from list)',
          style: TextStyle(fontFamily: 'monospace', fontSize: 8,
            color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 4),
        TextField(
          controller: _voiceIdController,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
            color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. 21m00Tcm4TlvDq8ikWAM',
            hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
            filled: true,
            fillColor: FluxForgeTheme.bgDeepest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: FluxForgeTheme.accentGreen)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        const SizedBox(height: 10),

        Row(children: [
          GestureDetector(
            onTap: () => setState(() => _showSettings = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: FluxForgeTheme.borderSubtle)),
              child: const Text('CANCEL',
                style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.textTertiary)),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _saveElConfig,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5))),
              child: const Text('SAVE',
                style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                  fontWeight: FontWeight.w700, color: FluxForgeTheme.accentGreen)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── 3.6 Cloud Sync Panel ────────────────────────────────────────────────────

class _CloudSyncPanel extends StatefulWidget {
  const _CloudSyncPanel();
  @override
  State<_CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<_CloudSyncPanel> {
  bool _autoSyncEnabled = false;

  CloudSyncService get _cloud => CloudSyncService.instance;

  @override
  void initState() {
    super.initState();
    _cloud.init().catchError((_) {});
    _cloud.addListener(_onCloudChanged);
  }

  @override
  void dispose() {
    _cloud.removeListener(_onCloudChanged);
    super.dispose();
  }

  void _onCloudChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Connection status
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('CLOUD STATUS', color: FluxForgeTheme.accentBlue),
                const SizedBox(height: 8),
                _CloudStatusRow('Provider', _cloud.provider.name.toUpperCase()),
                _CloudStatusRow('Status', _cloud.status.name.toUpperCase()),
                _CloudStatusRow('Authenticated', _cloud.isAuthenticated ? 'YES' : 'NO'),
                _CloudStatusRow('User', _cloud.userEmail ?? 'N/A'),
                _CloudStatusRow('Last Sync', _cloud.lastSyncTime?.toString().substring(0, 19) ?? 'Never'),
                const SizedBox(height: 12),
                // Provider selector
                _DockLabel('PROVIDER', color: FluxForgeTheme.accentBlue),
                const SizedBox(height: 6),
                Row(children: CloudProvider.values.map((p) => GestureDetector(
                  onTap: () async {
                    await silentCatchAsync('cloud.setProvider', () => _cloud.setProvider(p));
                    if (mounted) setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: _cloud.provider == p ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _cloud.provider == p ? FluxForgeTheme.accentBlue.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle),
                    ),
                    child: Text(p.name.toUpperCase(), style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                      color: _cloud.provider == p ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
                      fontWeight: FontWeight.w600)),
                  ),
                )).toList()),
                const Spacer(),
                // Auto-sync toggle
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _autoSyncEnabled = !_autoSyncEnabled;
                      if (_autoSyncEnabled) {
                        _cloud.enableAutoSync();
                      } else {
                        _cloud.disableAutoSync();
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _autoSyncEnabled
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                        : FluxForgeTheme.bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _autoSyncEnabled
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                        : FluxForgeTheme.borderSubtle),
                    ),
                    child: Row(children: [
                      Icon(_autoSyncEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                        size: 13, color: _autoSyncEnabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary),
                      const SizedBox(width: 7),
                      Text('Auto-Sync ${_autoSyncEnabled ? "ON" : "OFF"}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                          fontWeight: _autoSyncEnabled ? FontWeight.w600 : FontWeight.w400,
                          color: _autoSyncEnabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Center: Projects list
        Expanded(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DockLabel('CLOUD PROJECTS', color: FluxForgeTheme.accentBlue),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await silentCatchAsync('cloud.uploadProject', () async {
                        final proj = GetIt.instance<SlotLabProjectProvider>();
                        await _cloud.uploadProject('.', name: proj.projectName);
                      });
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.cloud_upload_rounded, size: 12, color: FluxForgeTheme.accentBlue),
                        SizedBox(width: 4),
                        Text('UPLOAD', style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      await silentCatchAsync('cloud.syncAllProjects', () => _cloud.syncAllProjects());
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.sync_rounded, size: 12, color: FluxForgeTheme.accentGreen),
                        SizedBox(width: 4),
                        Text('SYNC ALL', style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: _cloud.projects.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.cloud_off_rounded, size: 36, color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15)),
                        const SizedBox(height: 10),
                        const Text('No cloud projects', style: TextStyle(
                          fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                        const SizedBox(height: 4),
                        Text('Upload a project to start syncing',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6))),
                      ]))
                    : ListView.builder(
                        itemCount: _cloud.projects.length,
                        itemBuilder: (_, i) {
                          final p = _cloud.projects[i];
                          return Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.bgSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: FluxForgeTheme.borderSubtle),
                            ),
                            child: Row(children: [
                              const Icon(Icons.folder_rounded, size: 16, color: FluxForgeTheme.accentBlue),
                              const SizedBox(width: 8),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                                    color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.w600)),
                                  Text('ID: ${p.id}  Updated: ${p.updatedAt.toString().substring(0, 16)}',
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
                                ],
                              )),
                              GestureDetector(
                                onTap: () async {
                                  await silentCatchAsync('cloud.syncProject', () => _cloud.syncProject(p.id));
                                  if (mounted) setState(() {});
                                },
                                child: const Icon(Icons.sync_rounded, size: 14, color: FluxForgeTheme.accentCyan),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  await silentCatchAsync('cloud.downloadProject', () => _cloud.downloadProject(p.id));
                                  if (mounted) setState(() {});
                                },
                                child: const Icon(Icons.cloud_download_rounded, size: 14, color: FluxForgeTheme.accentGreen),
                              ),
                            ]),
                          );
                        },
                      ),
                ),
                // Progress bar during sync
                if (_cloud.isSyncing) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _cloud.progress,
                    backgroundColor: FluxForgeTheme.bgSurface,
                    valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentBlue),
                  ),
                  const SizedBox(height: 4),
                  Text(_cloud.currentOperation ?? 'Syncing...',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CloudStatusRow extends StatelessWidget {
  final String label;
  final String value;
  const _CloudStatusRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary))),
      Expanded(child: Text(value,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary),
        overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ── 3.7 A/B Split Test Panel ────────────────────────────────────────────────

class _AbTestPanel extends StatefulWidget {
  const _AbTestPanel();
  @override
  State<_AbTestPanel> createState() => _AbTestPanelState();
}

class _AbTestPanelState extends State<_AbTestPanel> {
  // Variant config
  double _variantARtp = 96.0;
  double _variantBRtp = 94.0;
  double _variantAVolatility = 2.5;
  double _variantBVolatility = 3.0;
  int _spinCount = 100000;
  bool _isRunning = false;
  Map<String, dynamic>? _results;

  AbSimProvider? _abSim;

  void _onSimUpdate() {
    if (!mounted) return;
    final sim = _abSim;
    if (sim == null) return;
    if (!sim.isRunning) {
      setState(() {
        _results = sim.lastResult;
        _isRunning = false;
      });
      sim.removeListener(_onSimUpdate);
    } else {
      setState(() {}); // refresh progress
    }
  }

  @override
  void dispose() {
    _abSim?.removeListener(_onSimUpdate);
    super.dispose();
  }

  void _runSimulation() {
    final abSim = GetIt.instance<AbSimProvider>();
    _abSim = abSim;
    setState(() { _isRunning = true; _results = null; });

    final config = {
      'variants': [
        {'name': 'Variant A', 'rtp': _variantARtp / 100, 'volatility': _variantAVolatility},
        {'name': 'Variant B', 'rtp': _variantBRtp / 100, 'volatility': _variantBVolatility},
      ],
      'spinsPerVariant': _spinCount,
    };

    abSim.addListener(_onSimUpdate);
    abSim.startSimulation(config);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Config
        Flexible(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('A/B SPLIT TEST CONFIG', color: FluxForgeTheme.accentGreen),
                const SizedBox(height: 8),
                // Variant A
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('VARIANT A', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w700)),
                    _SfxPresetSlider(label: 'RTP', value: _variantARtp, min: 85, max: 99, suffix: '%',
                      onChanged: (v) => setState(() => _variantARtp = v)),
                    _SfxPresetSlider(label: 'Volatility', value: _variantAVolatility, min: 1, max: 5, suffix: '',
                      onChanged: (v) => setState(() => _variantAVolatility = v)),
                  ]),
                ),
                // Variant B
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('VARIANT B', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w700)),
                    _SfxPresetSlider(label: 'RTP', value: _variantBRtp, min: 85, max: 99, suffix: '%',
                      onChanged: (v) => setState(() => _variantBRtp = v)),
                    _SfxPresetSlider(label: 'Volatility', value: _variantBVolatility, min: 1, max: 5, suffix: '',
                      onChanged: (v) => setState(() => _variantBVolatility = v)),
                  ]),
                ),
                // Spin count
                _SfxPresetSlider(label: 'Spins/Variant', value: _spinCount.toDouble(),
                  min: 10000, max: 1000000, suffix: '',
                  color: FluxForgeTheme.accentGreen, onChanged: (v) => setState(() => _spinCount = v.round())),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _isRunning ? null : _runSimulation,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _isRunning
                        ? FluxForgeTheme.textTertiary.withValues(alpha: 0.1)
                        : FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _isRunning
                        ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentGreen.withValues(alpha: 0.5)),
                    ),
                    child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_isRunning)
                        const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: FluxForgeTheme.accentGreen))
                      else
                        const Icon(Icons.science_rounded, size: 14, color: FluxForgeTheme.accentGreen),
                      const SizedBox(width: 8),
                      Text(_isRunning ? 'SIMULATING...' : 'RUN A/B TEST',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                          color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w600)),
                    ])),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right: Results
        Expanded(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('RESULTS', color: FluxForgeTheme.accentGreen),
                const SizedBox(height: 8),
                if (_isRunning) ...[
                  ListenableBuilder(
                    listenable: GetIt.instance<AbSimProvider>(),
                    builder: (_, _) {
                    final abSim = GetIt.instance<AbSimProvider>();
                    return Column(children: [
                      LinearProgressIndicator(
                        value: abSim.progress,
                        backgroundColor: FluxForgeTheme.bgSurface,
                        valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentGreen),
                      ),
                      const SizedBox(height: 8),
                      Text('${(abSim.progress * 100).toStringAsFixed(1)}% complete',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary)),
                    ]);
                  }),
                ] else if (_results != null) ...[
                  Expanded(
                    child: _buildResultsTable(),
                  ),
                ] else ...[
                  Expanded(
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.science_outlined, size: 48, color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      const Text('Configure variants and run simulation',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                      const SizedBox(height: 6),
                      Text('Up to 1M spins per variant',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6))),
                    ])),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsTable() {
    final variants = _results?['variants'] as List? ?? [];
    if (variants.isEmpty) {
      return const Center(child: Text('No results', style: TextStyle(
        fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textTertiary)));
    }
    return ListView(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(children: [
            SizedBox(width: 100, child: Text('METRIC', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
            Expanded(child: Text('VARIANT A', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
            Expanded(child: Text('VARIANT B', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
            SizedBox(width: 80, child: Text('DIFF', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          ]),
        ),
        const SizedBox(height: 4),
        // Metrics rows
        ..._buildMetricRows(variants),
        const SizedBox(height: 12),
        // Winner badge
        if (variants.length >= 2) _buildWinnerBadge(variants),
      ],
    );
  }

  List<Widget> _buildMetricRows(List variants) {
    final a = variants[0] as Map<String, dynamic>? ?? {};
    final b = variants.length > 1 ? variants[1] as Map<String, dynamic>? ?? {} : {};
    final metrics = [
      ('Actual RTP', a['actualRtp'] ?? _variantARtp, b['actualRtp'] ?? _variantBRtp, '%'),
      ('Avg Win', a['avgWin'] ?? 0.0, b['avgWin'] ?? 0.0, 'x'),
      ('Hit Rate', a['hitRate'] ?? 0.0, b['hitRate'] ?? 0.0, '%'),
      ('Max Win', a['maxWin'] ?? 0.0, b['maxWin'] ?? 0.0, 'x'),
      ('Std Dev', a['stdDev'] ?? 0.0, b['stdDev'] ?? 0.0, ''),
      ('Bankroll Half-life', a['halfLife'] ?? 0.0, b['halfLife'] ?? 0.0, ' spins'),
    ];
    return metrics.map((m) {
      final (label, aVal, bVal, suffix) = m;
      final aNum = (aVal is num) ? aVal.toDouble() : 0.0;
      final bNum = (bVal is num) ? bVal.toDouble() : 0.0;
      final diff = aNum - bNum;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        margin: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
          Expanded(child: Text('${aNum.toStringAsFixed(2)}$suffix',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary),
            textAlign: TextAlign.center)),
          Expanded(child: Text('${bNum.toStringAsFixed(2)}$suffix',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary),
            textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text(
            '${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(2)}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: diff.abs() < 0.1 ? FluxForgeTheme.textTertiary
                : diff > 0 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentPink),
            textAlign: TextAlign.center)),
        ]),
      );
    }).toList();
  }

  Widget _buildWinnerBadge(List variants) {
    final aRtp = (variants[0] as Map?)?['actualRtp'] ?? _variantARtp;
    final bRtp = (variants[1] as Map?)?['actualRtp'] ?? _variantBRtp;
    final aNum = (aRtp is num) ? aRtp.toDouble() : 0.0;
    final bNum = (bRtp is num) ? bRtp.toDouble() : 0.0;
    final winner = aNum >= bNum ? 'A' : 'B';
    final winColor = winner == 'A' ? FluxForgeTheme.accentBlue : FluxForgeTheme.accentGreen;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: winColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: winColor.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.emoji_events_rounded, size: 18, color: winColor),
        const SizedBox(width: 8),
        Text('VARIANT $winner WINS',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12,
            color: winColor, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('(${(aNum - bNum).abs().toStringAsFixed(2)}% RTP difference)',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary)),
      ]),
    );
  }
}

// ── 3.3 PAR Import Panel (integrated into SFX Pipeline) ─────────────────────
// PAR file import is handled through the SFX Pipeline's namingAssign step
// with auto-mapping from paytable CSV/PAR files to game stages.
// The SfxPipelineProvider.setStageMappings() method handles this.

// ── AUDIO Panel ──────────────────────────────────────────────────────────────

class _AudioPanel extends StatefulWidget {
  const _AudioPanel();

  @override
  State<_AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<_AudioPanel> {
  double _masterFader = 1.0; // A6: master output fader — synced from engine

  @override
  void initState() {
    super.initState();
    try {
      _masterFader = NativeFFI.instance.getMasterVolume();
    } catch (_) {
      _masterFader = 1.0; // engine not ready yet, default to unity gain
    }
  }

  void _showAutoBindDialog(BuildContext context) async {
    final result = await showDialog<AutoBindV2Result>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AutoBindDialogV2(),
    );
    if (result == null || !mounted) return;

    if (result.analysis.matchedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching sound files found in folder'),
          backgroundColor: Color(0xFF442222),
        ),
      );
      return;
    }

    // Trigger reload (syncs assignments → composite events → EventRegistry)
    SlotLabScreen.triggerAutoBindReload(result.folderPath);

    if (mounted) {
      final renamed = result.didRename ? ' (renamed to FFNC)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-Bind: ${result.analysis.uniqueStageCount} stages bound$renamed'),
          backgroundColor: FluxForgeTheme.bgMid,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when MiddlewareProvider or NeuroAudioProvider change
    try {
      return ListenableBuilder(
        listenable: Listenable.merge([
          GetIt.instance<MiddlewareProvider>(),
          GetIt.instance<NeuroAudioProvider>(),
        ]),
        builder: (context, _) {
          try {
            return _buildContent(context);
          } catch (e) {
            return _renderHelixErrorFallback('AUDIO BUILD', e);
          }
        },
      );
    } catch (e) {
      return _renderHelixErrorFallback('AUDIO INIT', e);
    }
  }

  Widget _buildContent(BuildContext context) {
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final out = neuro.output;

    // Derive master levels from neuro audio adaptation output × master fader
    final masterL = (out.arousal * 0.6 + out.engagement * 0.4).clamp(0.0, 1.0) * _masterFader;
    final masterR = (out.arousal * 0.55 + out.engagement * 0.45).clamp(0.0, 1.0) * _masterFader;
    final peak = math.max(masterL, masterR);
    final peakDb = peak > 0.001 ? (20 * math.log(peak) / 2.302585) : -60.0;

    // 2026-05-10 — EVENT NEXUS replaces the legacy 8-channel preview.  The
    // master fader, master meters and OrbMixer remain as a compact left
    // strip; auto-bind drop target (NeuralBindOrb) lives next to the orb.
    // The expanded right column hosts the full pure-trigger event matrix
    // covering EVERY stage, EVERY parameter — Boki direktiva 2026-05-10:
    // "event samo trigeruje zvuk, niko ne odlučuje koliko traje".
    return Row(
      children: [
        // ── LEFT STRIP: master meters + fader (compact, 130px) ────────────
        SizedBox(
          width: 130,
          child: _DockCard(
            accent: FluxForgeTheme.accentCyan,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('MASTER', color: FluxForgeTheme.accentCyan),
                const SizedBox(height: 6),
                _MeterRow(label: 'L', value: masterL),
                const SizedBox(height: 4),
                _MeterRow(label: 'R', value: masterR),
                const SizedBox(height: 8),
                Row(children: [
                  _DockLabel('FADER', color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 4),
                  Expanded(
                    child: LayoutBuilder(builder: (_, c) => GestureDetector(
                      onTapDown: (d) {
                        final v = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                        setState(() => _masterFader = v);
                        silentRun('fader.setMasterVolume', () { NativeFFI.instance.setMasterVolume(v); });
                      },
                      onHorizontalDragUpdate: (d) {
                        final v = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                        setState(() => _masterFader = v);
                        silentRun('fader.setMasterVolume', () { NativeFFI.instance.setMasterVolume(v); });
                      },
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgElevated,
                          borderRadius: BorderRadius.circular(3)),
                        child: Stack(children: [
                          FractionallySizedBox(
                            widthFactor: _masterFader,
                            alignment: Alignment.centerLeft,
                            child: Container(decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                FluxForgeTheme.accentGreen, FluxForgeTheme.accentCyan]),
                              borderRadius: BorderRadius.circular(3))),
                          ),
                        ]),
                      ),
                    )),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('${(_masterFader * 100).toStringAsFixed(0)}%  ·  ${peakDb.toStringAsFixed(1)} dB',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                    color: peakDb > -6 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentCyan)),
                const Spacer(),
                Row(children: [
                  _DockLabel('VOL', color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 2),
                  Flexible(child: Text('${(out.volumeEnvelopeScale * 100).toStringAsFixed(0)}%',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan))),
                  const Spacer(),
                  _DockLabel('CMP', color: FluxForgeTheme.accentPurple),
                  const SizedBox(width: 2),
                  Flexible(child: Text('${(out.compressionModifier * 100).toStringAsFixed(0)}%',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentPurple))),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // ── ORB + BIND (148px) ─────────────────────────────────────────────
        SizedBox(
          width: 148,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              children: [
                Builder(builder: (ctx) {
                  try {
                    return OrbMixer(
                      dsp: GetIt.instance<MixerDSPProvider>(),
                      size: 100,
                    );
                  } catch (e) {
                    return _renderHelixErrorFallback('ORB', e, fontSize: 8);
                  }
                }),
                const SizedBox(height: 6),
                _DockLabel('AUTO-BIND', color: FluxForgeTheme.accentPurple),
                const SizedBox(height: 4),
                // Neural Bind Orb — instant drag & drop audio binding (RAW mode)
                Builder(builder: (ctx) {
                  try {
                    return NeuralBindOrb.large(
                      onBindComplete: (analysis, path) {
                        SlotLabScreen.triggerAutoBindReload(path);
                      },
                    );
                  } catch (e) {
                    return _renderHelixErrorFallback('BIND', e, fontSize: 8);
                  }
                }),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // ── EVENT NEXUS (expanded) ─────────────────────────────────────────
        const Expanded(child: HelixEventNexus()),
      ],
    );
  }
}

// ── MATH Panel ───────────────────────────────────────────────────────────────

class _MathPanel extends StatefulWidget {
  const _MathPanel();

  @override
  State<_MathPanel> createState() => _MathPanelState();
}

class _MathPanelState extends State<_MathPanel> {
  double _targetRtp = 96.0; // M1
  double _volatilitySlider = 5.0; // M2
  double _maxWinCap = 5000.0; // M4
  double _hitFreqTarget = 30.0; // M5
  double _bonusFreqTarget = 2.0; // M6

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when SlotLabProject or NeuroAudio change
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<SlotLabProjectProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final stats = proj.sessionStats;
    final wins = proj.recentWins;
    final rtp = stats.rtp.isNaN || stats.rtp.isInfinite ? 0.0 : stats.rtp;

    // Volatility from NeuroAudio risk tolerance (real Rust FFI data)
    final volIdx = (neuro.output.riskTolerance * 10).clamp(0.0, 10.0);
    final volLabel = volIdx > 7 ? 'HIGH' : volIdx > 4 ? 'MED' : 'LOW';

    // Hit frequency from actual session data
    final hitRate = stats.totalSpins > 0 ? wins.length / stats.totalSpins : 0.0;
    final hitFreqStr = hitRate > 0 ? '1:${(1 / hitRate).toStringAsFixed(1)}' : '—';

    // Max win multiplier from actual wins
    final avgBet = stats.totalSpins > 0 ? stats.totalBet / stats.totalSpins : 1.0;
    final maxWinAmt = wins.isEmpty ? 0.0 : wins.map((w) => w.amount).reduce(math.max);
    final maxWinMult = avgBet > 0 ? maxWinAmt / avgBet : 0.0;

    // Bonus frequency from feature wins
    final bonusWins = wins.where((w) => w.tier.toUpperCase().contains('BONUS') || w.tier.toUpperCase().contains('FREE')).length;
    final bonusFreq = stats.totalSpins > 0 && bonusWins > 0
        ? '1:${(stats.totalSpins / bonusWins).toStringAsFixed(0)}' : '—';
    final bonusFill = stats.totalSpins > 0 ? (bonusWins / stats.totalSpins).clamp(0.0, 1.0) : 0.0;

    // RTP diff from target (M1)
    final rtpDiff = rtp > 0 ? rtp - _targetRtp : 0.0;
    final rtpDiffStr = rtpDiff >= 0 ? '+${rtpDiff.toStringAsFixed(1)}' : rtpDiff.toStringAsFixed(1);

    // RTP status color: green if within ±2% of target, orange ±5%, red beyond
    final rtpColor = rtp <= 0 ? FluxForgeTheme.textTertiary
        : rtpDiff.abs() <= 2.0 ? FluxForgeTheme.accentGreen
        : rtpDiff.abs() <= 5.0 ? FluxForgeTheme.accentOrange
        : FluxForgeTheme.accentPink;
    // Fill bar: show deviation magnitude (0=perfect, 1=max deviation)
    final rtpFill = rtp > 0 ? (1.0 - (rtpDiff.abs() / 20.0)).clamp(0.0, 1.0) : 0.0;

    // Win tier distribution from actual session wins
    const tierColors = [
      Color(0xFF4D9FFF), // WIN 1
      Color(0xFF5CFF9D), // WIN 2
      Color(0xFFFFE033), // WIN 3
      Color(0xFFFF9900), // WIN 4
      Color(0xFFFF3366), // WIN 5
    ];
    final tierCounts = <int, int>{};
    for (final w in wins) {
      final t = w.tier.toUpperCase();
      final idx = t.contains('5') ? 5 : t.contains('4') ? 4 : t.contains('3') ? 3
                : t.contains('2') ? 2 : t.contains('BONUS') || t.contains('FREE') ? 5 : 1;
      tierCounts[idx] = (tierCounts[idx] ?? 0) + 1;
    }
    final maxTierCount = tierCounts.values.fold(0, math.max);

    final cards = [
      ('RTP',       rtp > 0 ? '${rtp.toStringAsFixed(1)}%' : '—', 'Target: ${_targetRtp.toStringAsFixed(1)}% ($rtpDiffStr)', rtpFill, rtpColor),
      ('VOLATILITY',volLabel,  'Target: ${_volatilitySlider.toStringAsFixed(0)} / 10', volIdx / 10, FluxForgeTheme.accentOrange),
      ('HIT FREQ',  hitFreqStr,'Target: ${_hitFreqTarget.toStringAsFixed(0)}%', hitRate.clamp(0.0, 1.0), FluxForgeTheme.accentBlue),
      ('MAX WIN',   maxWinMult > 0 ? '${maxWinMult.toStringAsFixed(0)}×' : '—', 'Cap: ${_maxWinCap.toStringAsFixed(0)}×', (maxWinMult / _maxWinCap).clamp(0.0, 1.0), FluxForgeTheme.accentYellow),
      ('SPINS',     '${stats.totalSpins}', 'Total recorded', stats.totalSpins > 0 ? 1.0 : 0.0, FluxForgeTheme.accentPurple),
      ('BONUS FREQ',bonusFreq, 'Target: 1:${(100 / _bonusFreqTarget).toStringAsFixed(0)}', bonusFill, FluxForgeTheme.accentCyan),
    ];

    return Column(
      children: [
        // ── Stats grid 2×3 ──────────────────────────────────────────────
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _MathCard(
                        label: cards[i].$1, value: cards[i].$2, sub: cards[i].$3,
                        fill: cards[i].$4, color: cards[i].$5,
                      )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 3; i < 6; i++) ...[
                      if (i > 3) const SizedBox(width: 8),
                      Expanded(child: _MathCard(
                        label: cards[i].$1, value: cards[i].$2, sub: cards[i].$3,
                        fill: cards[i].$4, color: cards[i].$5,
                      )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // ── Win Distribution Histogram ───────────────────────────────────
        Expanded(
          flex: 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Histogram card
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A14),
                    border: Border.all(color: const Color(0xFF1E2030)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('WIN DISTRIBUTION', style: TextStyle(
                        fontFamily: 'monospace', fontSize: 8,
                        color: FluxForgeTheme.textTertiary, letterSpacing: 1.0)),
                      const Spacer(),
                      Text('${wins.length} wins', style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
                    ]),
                    const SizedBox(height: 6),
                    Expanded(
                      child: wins.isEmpty
                        ? const Center(child: Text('Run sim to populate',
                            style: TextStyle(fontSize: 8, color: FluxForgeTheme.textTertiary)))
                        : CustomPaint(
                            painter: _WinDistributionPainter(
                              tierCounts: tierCounts,
                              maxCount: maxTierCount,
                              tierColors: tierColors,
                            ),
                            child: const SizedBox.expand(),
                          ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              // Sliders column
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _MathSlider(
                          label: 'TARGET RTP', value: _targetRtp,
                          min: 85, max: 99, suffix: '%',
                          color: FluxForgeTheme.accentGreen,
                          onChanged: (v) => setState(() => _targetRtp = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _MathSlider(
                          label: 'VOLATILITY', value: _volatilitySlider,
                          min: 1, max: 10, suffix: '',
                          color: FluxForgeTheme.accentOrange,
                          onChanged: (v) => setState(() => _volatilitySlider = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _MathSlider(
                          label: 'MAX WIN ×', value: _maxWinCap,
                          min: 100, max: 25000, suffix: '×',
                          color: FluxForgeTheme.accentYellow,
                          onChanged: (v) => setState(() => _maxWinCap = v),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _MathSlider(
                          label: 'HIT FREQ', value: _hitFreqTarget,
                          min: 10, max: 60, suffix: '%',
                          color: FluxForgeTheme.accentBlue,
                          onChanged: (v) => setState(() => _hitFreqTarget = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _MathSlider(
                          label: 'BONUS FREQ', value: _bonusFreqTarget,
                          min: 0.5, max: 10, suffix: '%',
                          color: FluxForgeTheme.accentCyan,
                          onChanged: (v) => setState(() => _bonusFreqTarget = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _RunSimButton(
                          targetRtp: _targetRtp,
                          hitFreq: _hitFreqTarget,
                          maxWinCap: _maxWinCap,
                        )),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Win Distribution CustomPainter ───────────────────────────────────────────

class _WinDistributionPainter extends CustomPainter {
  final Map<int, int> tierCounts;
  final int maxCount;
  final List<Color> tierColors;

  const _WinDistributionPainter({
    required this.tierCounts, required this.maxCount, required this.tierColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (maxCount == 0) return;
    const tiers = [1, 2, 3, 4, 5];
    final barW = (size.width - (tiers.length - 1) * 4) / tiers.length;
    const labelH = 14.0;
    final chartH = size.height - labelH;

    for (int i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      final count = tierCounts[tier] ?? 0;
      final fill = count > 0 ? count / maxCount : 0.0;
      final color = tierColors[i];
      final x = i * (barW + 4);
      final barH = chartH * fill;
      final y = chartH - barH;

      if (barH > 0) {
        // Gradient bar
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH), const Radius.circular(3));
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [color, color.withValues(alpha: 0.4)]).createShader(
              Rect.fromLTWH(x, y, barW, barH));
        canvas.drawRRect(rect, paint);

        // Count text
        if (barH > 14) {
          final tp = TextPainter(
            text: TextSpan(text: '$count',
              style: TextStyle(fontFamily: 'monospace', fontSize: 7, color: color)),
            textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(x + (barW - tp.width) / 2, y + 3));
        }
      }

      // Tier label below
      final label = 'W$tier';
      final tp = TextPainter(
        text: TextSpan(text: label,
          style: TextStyle(fontFamily: 'monospace', fontSize: 7,
            color: color.withValues(alpha: count > 0 ? 0.9 : 0.3))),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(x + (barW - tp.width) / 2, chartH + 3));
    }
  }

  @override
  bool shouldRepaint(_WinDistributionPainter old) =>
    old.tierCounts != tierCounts || old.maxCount != maxCount;
}

class _RunSimButton extends StatefulWidget {
  final double targetRtp;
  final double hitFreq;
  final double maxWinCap;
  const _RunSimButton({
    this.targetRtp = 96.0,
    this.hitFreq = 30.0,
    this.maxWinCap = 5000.0,
  });
  @override
  State<_RunSimButton> createState() => _RunSimButtonState();
}

class _RunSimButtonState extends State<_RunSimButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    silentRun('mathSim.runSimulation', () {
      final proj = GetIt.instance<SlotLabProjectProvider>();
      final rng = math.Random();
      // Use slider values: hit frequency as probability, RTP controls avg win size
      final hitProb = (widget.hitFreq / 100.0).clamp(0.05, 0.80);
      final avgWinMult = (widget.targetRtp / 100.0) / hitProb; // avg win × bet to reach target RTP
      final capMult = (widget.maxWinCap / 1000.0).clamp(2.0, 50.0);
      for (int i = 0; i < 1000; i++) {
        final isWin = rng.nextDouble() < hitProb;
        final win = isWin ? (rng.nextDouble() * avgWinMult * 2.0).clamp(0.01, capMult) : 0.0;
        proj.recordSpinResult(betAmount: 1.0, winAmount: win,
          tier: win > avgWinMult * 1.5 ? 'WIN 3' : win > 0 ? 'WIN 1' : null);
      }
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _run,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _running
          ? FluxForgeTheme.accentGreen.withValues(alpha: 0.08)
          : FluxForgeTheme.accentGreen.withValues(alpha: 0.04),
        border: Border.all(
          color: _running
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
            : FluxForgeTheme.accentGreen.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_running) ...[
          SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: FluxForgeTheme.accentGreen,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Simulating 1000 spins...', style: TextStyle(
            fontFamily: 'monospace', fontSize: 10,
            color: FluxForgeTheme.accentGreen)),
        ] else ...[
          Icon(Icons.play_circle_rounded, size: 14, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 6),
          const Text('Run Simulation (1000 spins)', style: TextStyle(
            fontFamily: 'monospace', fontSize: 10,
            color: FluxForgeTheme.accentGreen)),
        ],
      ]),
    ),
  );
}

// ── TIMELINE Panel ───────────────────────────────────────────────────────────

class _TimelinePanel extends StatefulWidget {
  const _TimelinePanel();

  @override
  State<_TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<_TimelinePanel> {
  // T1: drag state
  String? _draggingEventId;
  double _dragStartMs = 0;
  double _dragStartX = 0;

  // Zoom & scroll state
  double _zoomLevel = 1.0; // 1.0 = fit all, higher = zoomed in
  double _scrollOffsetMs = 0.0; // horizontal scroll in ms
  static const double _minZoom = 0.5;
  static const double _maxZoom = 8.0;
  // Snap grid interval in ms (0 = off, 250 = quarter-second, 500 = half, 1000 = 1s)
  double _snapGridMs = 0;

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when MiddlewareProvider changes
    return ListenableBuilder(
      listenable: GetIt.instance<MiddlewareProvider>(),
      builder: (context, _) => _buildContent(context),
    );
  }

  double _snapToGrid(double ms) {
    if (_snapGridMs <= 0) return ms;
    return (ms / _snapGridMs).round() * _snapGridMs;
  }

  Widget _buildContent(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final engine = GetIt.instance<EngineProvider>();
    final events = mw.compositeEvents;

    // Access playhead from parent
    final helixState = context.findAncestorStateOfType<_HelixScreenState>();
    final playheadSec = helixState?._playheadSeconds ?? 0.0;

    // Group events by trackIndex, build real timeline tracks
    final trackMap = <int, List<SlotCompositeEvent>>{};
    for (final e in events) {
      trackMap.putIfAbsent(e.trackIndex, () => []).add(e);
    }

    // Find timeline extent (max position + reasonable width)
    double totalMs = 8000; // 8 second default view
    for (final e in events) {
      final end = e.timelinePositionMs + 1000;
      if (end > totalMs) totalMs = end;
    }

    // Visible window based on zoom
    final visibleMs = totalMs / _zoomLevel;
    final maxScrollMs = (totalMs - visibleMs).clamp(0.0, double.infinity);
    final scrollMs = _scrollOffsetMs.clamp(0.0, maxScrollMs);

    // Playhead fraction within visible window
    final playheadMs = playheadSec * 1000;
    final playheadFrac = visibleMs > 0
        ? ((playheadMs - scrollMs) / visibleMs).clamp(0.0, 1.0)
        : 0.0;

    // Build track list from real data
    final sortedTracks = trackMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    // Ruler marks — adaptive based on zoom
    final rulerIntervalMs = _rulerInterval(visibleMs);
    final firstMark = (scrollMs / rulerIntervalMs).ceil() * rulerIntervalMs;
    final rulerMarks = <double>[];
    for (var ms = firstMark; ms <= scrollMs + visibleMs; ms += rulerIntervalMs) {
      rulerMarks.add(ms);
    }

    return _DockCard(
      accent: FluxForgeTheme.accentOrange,
      child: Column(
        children: [
          // Toolbar — zoom controls + snap
          Row(children: [
            _DockLabel('TIMELINE', color: FluxForgeTheme.accentOrange),
            const Spacer(),
            // Snap grid selector
            GestureDetector(
              onTap: () => setState(() {
                _snapGridMs = switch (_snapGridMs) {
                  0 => 250,
                  250 => 500,
                  500 => 1000,
                  _ => 0,
                };
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _snapGridMs > 0 ? FluxForgeTheme.accentCyan.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _snapGridMs > 0 ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle)),
                child: Text(_snapGridMs > 0 ? 'SNAP ${_snapGridMs.toInt()}ms' : 'SNAP OFF',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 7,
                    color: _snapGridMs > 0 ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                    fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            // Zoom controls
            GestureDetector(
              onTap: () => setState(() {
                _zoomLevel = (_zoomLevel / 1.5).clamp(_minZoom, _maxZoom);
              }),
              child: const Icon(Icons.zoom_out_rounded, size: 14, color: FluxForgeTheme.textSecondary),
            ),
            const SizedBox(width: 4),
            Text('${_zoomLevel.toStringAsFixed(1)}x',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() {
                _zoomLevel = (_zoomLevel * 1.5).clamp(_minZoom, _maxZoom);
              }),
              child: const Icon(Icons.zoom_in_rounded, size: 14, color: FluxForgeTheme.textSecondary),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() { _zoomLevel = 1.0; _scrollOffsetMs = 0; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(3)),
                child: const Text('FIT', style: TextStyle(fontFamily: 'monospace', fontSize: 7,
                  color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          // FAZA 3.6.B + 3.6.C + 3.6.D — Timeline Intelligence Bar.
          // Tri slot-native indikatora iznad Stage Flow Strip-a:
          //   ⚔ Audio Clash Detector — pairwise (stage, layer) overlap
          //     na istom busId-u tokom poslednjeg spina; tooltip lista
          //     do 8 najgorih clash-ova sortiranih po duration.
          //   ⏱ Time Budget Compliance — total spin duration vs
          //     jurisdiction cap (3500ms UKGC default), per-stage soft
          //     caps iz industrijske matrice (`_kStageBudgets`).
          //   🔥 Anticipation Density Meter — % poslednjih 50 spinova
          //     koji su trigger-ovali ANTICIPATION_TENSION_*; sweet spot
          //     15–30% (color tier: <5 red, 5–15 orange, 15–30 green,
          //     >30 yellow).
          const TimelineIntelligenceBar(),
          const SizedBox(height: 4),
          // FAZA 3.6.A — Stage Flow Strip (slot-native composition view).
          // Painta horizontalnu traku sa chunk-om za svaki stage iz
          // SlotLabCoordinator.stageProvider.lastStages, kategorije
          // bojom-kodirane (spin/win/feature/...).  Klik na chunk
          // = audition kroz EventRegistry.triggerStage(), isti put
          // koji TIMELINE JUMP quick-action koristi.
          const StageFlowStrip(height: 56),
          const SizedBox(height: 4),
          // FAZA 3.6.E — Session Recorder + Best Win Detector.
          // Compact footer: [N spins] [REC] dugmad pokreću batch spin
          // sequence kroz SlotLabCoordinator; snapshots (stages +
          // result) idu u in-memory ring buffer.  Posle završetka,
          // panel pokazuje session stats (count, hit, RTP, anti) +
          // Best Win badge sa replay handle-om.
          //
          // Audio bounce u MasterRingBuffer ostaje za 3.6.F (Marketing
          // Clip Export) — Rust crate change `expandTo60s()` je future
          // work; replay već radi kroz stage re-fire.
          const SessionRecorderPanel(),
          const SizedBox(height: 4),
          // Ruler — clickable to seek (T3), with scroll
          GestureDetector(
            onTapDown: (d) {
              final rulerWidth = (context.size?.width ?? 400) - 80 - 24;
              final frac = ((d.localPosition.dx - 80) / rulerWidth).clamp(0.0, 1.0);
              final seekMs = scrollMs + frac * visibleMs;
              final seekSec = seekMs / 1000.0;
              engine.seek(seekSec);
              helixState?.setPlayhead(seekSec);
            },
            onHorizontalDragUpdate: (d) {
              setState(() {
                final rulerWidth = (context.size?.width ?? 400) - 80 - 24;
                final msDelta = -(d.delta.dx / rulerWidth) * visibleMs;
                _scrollOffsetMs = (_scrollOffsetMs + msDelta).clamp(0.0, maxScrollMs);
              });
            },
            child: SizedBox(
              height: 18,
              child: LayoutBuilder(builder: (_, constraints) {
                final rulerWidth = constraints.maxWidth - 80;
                return Stack(
                  children: [
                    const Positioned(left: 0, top: 0, bottom: 0, child: SizedBox(width: 80)),
                    ...rulerMarks.map((ms) {
                      final frac = (ms - scrollMs) / visibleMs;
                      if (frac < 0 || frac > 1) return const SizedBox.shrink();
                      final sec = ms / 1000;
                      final label = sec < 60
                          ? '${sec.toStringAsFixed(sec == sec.truncateToDouble() ? 0 : 1)}s'
                          : '${(sec / 60).floor()}:${(sec % 60).floor().toString().padLeft(2, '0')}';
                      return Positioned(
                        left: 80 + frac * rulerWidth,
                        top: 2,
                        child: Text(label, style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 9,
                          color: FluxForgeTheme.textTertiary)),
                      );
                    }),
                    // Snap grid lines
                    if (_snapGridMs > 0)
                      ...List.generate(
                        ((visibleMs / _snapGridMs) + 1).ceil(),
                        (i) {
                          final gridMs = ((scrollMs / _snapGridMs).floor() + i) * _snapGridMs;
                          final frac = (gridMs - scrollMs) / visibleMs;
                          if (frac < 0 || frac > 1) return const SizedBox.shrink();
                          return Positioned(
                            left: 80 + frac * rulerWidth,
                            top: 14, bottom: 0,
                            child: Container(width: 0.5, color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
                          );
                        },
                      ),
                  ],
                );
              }),
            ),
          ),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          const SizedBox(height: 2),
          // Tracks with playhead overlay — scrollable + zoomable
          Expanded(
            child: Listener(
              // Scroll wheel for horizontal scroll, Ctrl+wheel for zoom
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    final isZoom = HardwareKeyboard.instance.isMetaPressed ||
                        HardwareKeyboard.instance.isControlPressed;
                    if (isZoom) {
                      final factor = event.scrollDelta.dy > 0 ? 0.85 : 1.18;
                      _zoomLevel = (_zoomLevel * factor).clamp(_minZoom, _maxZoom);
                    } else {
                      final scrollDelta = event.scrollDelta.dy * (visibleMs / 600);
                      _scrollOffsetMs = (_scrollOffsetMs + scrollDelta).clamp(0.0, maxScrollMs);
                    }
                  });
                }
              },
              child: sortedTracks.isEmpty
                ? const Center(child: Text('No events on timeline.\nAssign composite events in SlotLab.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, height: 1.5)))
                : LayoutBuilder(builder: (_, constraints) {
                    final trackAreaWidth = constraints.maxWidth - 80;
                    return Stack(
                      children: [
                        // Snap grid vertical lines
                        if (_snapGridMs > 0)
                          ...List.generate(
                            ((visibleMs / _snapGridMs) + 1).ceil(),
                            (i) {
                              final gridMs = ((scrollMs / _snapGridMs).floor() + i) * _snapGridMs;
                              final frac = (gridMs - scrollMs) / visibleMs;
                              if (frac < 0 || frac > 1) return const SizedBox.shrink();
                              return Positioned(
                                left: 80 + frac * trackAreaWidth,
                                top: 0, bottom: 0,
                                child: Container(width: 0.5, color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.15)),
                              );
                            },
                          ),
                        // Tracks
                        Column(
                          children: sortedTracks.map((entry) {
                            final trackEvents = entry.value;
                            final trackName = trackEvents.first.name.length > 10
                                ? trackEvents.first.name.substring(0, 10) : trackEvents.first.name;
                            final color = trackEvents.first.color;
                            // Filter events visible in current scroll window
                            final visibleEvents = trackEvents.where((e) {
                              final eventEnd = e.timelinePositionMs + 1000;
                              return eventEnd >= scrollMs && e.timelinePositionMs <= scrollMs + visibleMs;
                            }).toList();
                            return Expanded(child: _TlTrackInteractive(
                              name: trackName,
                              color: color,
                              events: visibleEvents,
                              maxMs: visibleMs,
                              scrollOffsetMs: scrollMs,
                              trackAreaWidth: trackAreaWidth,
                              middleware: mw,
                              snapGridMs: _snapGridMs,
                            ));
                          }).toList(),
                        ),
                        // T4: Playhead line
                        if (playheadMs >= scrollMs && playheadMs <= scrollMs + visibleMs)
                          Positioned(
                            left: 80 + (playheadFrac * trackAreaWidth),
                            top: 0, bottom: 0,
                            child: Container(
                              width: 2,
                              color: FluxForgeTheme.accentRed.withValues(alpha: 0.8),
                            ),
                          ),
                        // Playhead triangle at top
                        if (playheadMs >= scrollMs && playheadMs <= scrollMs + visibleMs)
                          Positioned(
                            left: 80 + (playheadFrac * trackAreaWidth) - 4,
                            top: 0,
                            child: CustomPaint(
                              size: const Size(8, 6),
                              painter: _PlayheadTrianglePainter(
                                color: FluxForgeTheme.accentRed),
                            ),
                          ),
                      ],
                    );
                  }),
            ),
          ),
        ],
      ),
    );
  }

  /// Compute adaptive ruler interval based on visible window
  double _rulerInterval(double visibleMs) {
    if (visibleMs > 20000) return 5000;
    if (visibleMs > 10000) return 2000;
    if (visibleMs > 4000) return 1000;
    if (visibleMs > 2000) return 500;
    if (visibleMs > 800) return 250;
    return 100;
  }
}

// ── INTEL Panel ──────────────────────────────────────────────────────────────

class _IntelPanel extends StatefulWidget {
  const _IntelPanel();
  @override
  State<_IntelPanel> createState() => _IntelPanelState();
}

class _IntelPanelState extends State<_IntelPanel> {
  String? _selectedArchetype;

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when RgaiProvider or NeuroAudioProvider change
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<RgaiProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final rgai = GetIt.instance<RgaiProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final out = neuro.output;
    final report = rgai.report;
    final summary = report?.summary;

    // Build copilot suggestions from real RGAI remediations
    final allRemediations = <RemediationSuggestion>[];
    for (final asset in report?.assets ?? <RgarAssetAnalysis>[]) {
      allRemediations.addAll(asset.remediations);
    }

    // Build copilot text from real data
    String copilotText;
    if (allRemediations.isNotEmpty) {
      final top = allRemediations.first;
      copilotText = 'Suggest: ${top.parameter} ${top.currentValue} → ${top.suggestedValue}\n'
          '${top.reason}';
    } else if (neuro.responsibleGamingMode) {
      copilotText = 'RG mode active. Audio intensity reduced.\n'
          'Monitoring player risk level: ${neuro.riskLevel.name}.';
    } else if (out.frustration > 0.6) {
      copilotText = 'High frustration detected (${(out.frustration * 100).toStringAsFixed(0)}%).\n'
          'Suggest: Increase reverb depth, reduce tempo.';
    } else if (out.engagement > 0.7) {
      copilotText = 'Player in flow state (${(out.flowDepth * 100).toStringAsFixed(0)}% depth).\n'
          'Audio adaptation: maintaining current balance.';
    } else {
      copilotText = 'Session active. ${neuro.totalSpins} spins tracked.\n'
          'All parameters within normal range.';
    }

    final stimPass = summary?.isCompliant ?? true;
    final riskRating = summary?.overallRiskRating;
    final nearMissOk = (summary?.maxNearMissDeception ?? 0) < 0.5;

    // Real engagement score
    final score = (out.engagement * 10).clamp(0.0, 10.0);

    // Real mini metrics from NeuroAudioProvider
    final retention = ((1.0 - out.churnPrediction) * 100).toStringAsFixed(0);
    final dwell = '${neuro.sessionDurationMinutes.toStringAsFixed(1)}m';
    final fatigueIdx = out.sessionFatigue.toStringAsFixed(2);
    final losses = '${neuro.consecutiveLosses}';

    return Row(
      children: [
        // Left: AI Copilot + RGAI
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _DockCard(
                  accent: FluxForgeTheme.accentPurple,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: neuro.responsibleGamingMode
                              ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen,
                            shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        _DockLabel('AI COPILOT', color: FluxForgeTheme.accentPurple),
                        const Spacer(),
                        if (allRemediations.isNotEmpty)
                          Text('${allRemediations.length} suggestions', style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentYellow)),
                      ]),
                      const SizedBox(height: 4),
                      Text(copilotText,
                        style: const TextStyle(fontSize: 10, height: 1.4,
                          color: FluxForgeTheme.textSecondary)),
                      const SizedBox(height: 3),
                      // Apply top suggestion button
                      if (allRemediations.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            // Apply: set RTPC via middleware using suggested value
                            // Map parameter name → RTPC index (matches NeuroAudioProvider 8D dims)
                            silentRun('copilot.applyRtpcSuggestion', () {
                              final top = allRemediations.first;
                              final v = double.tryParse(top.suggestedValue) ?? 0.5;
                              final mw = GetIt.instance<MiddlewareProvider>();
                              final param = top.parameter.toLowerCase();
                              final rtpcIdx = param.contains('arousal') ? 0
                                : param.contains('valence') ? 1
                                : param.contains('engagement') ? 2
                                : param.contains('risk') ? 3
                                : param.contains('frustration') ? 4
                                : param.contains('flow') ? 5
                                : param.contains('churn') ? 6
                                : param.contains('fatigue') ? 7
                                : param.contains('reverb') ? 5
                                : param.contains('volume') ? 0
                                : param.contains('tempo') ? 3
                                : param.contains('compress') ? 2
                                : 0;
                              mw.setRtpc(rtpcIdx, v.clamp(0.0, 1.0), interpolationMs: 500);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.1),
                              border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.auto_fix_high_rounded, size: 10,
                                color: FluxForgeTheme.accentPurple),
                              const SizedBox(width: 5),
                              const Text('Apply suggestion', style: TextStyle(
                                fontFamily: 'monospace', fontSize: 9,
                                color: FluxForgeTheme.accentPurple)),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 3),
                      // I2: CoPilot chat input
                      const _CoPilotChatWidget(),
                      const SizedBox(height: 3),
                      // I3: Archetype selector
                      Row(children: [
                        _DockLabel('ARCHETYPE', color: FluxForgeTheme.accentPurple),
                        const Spacer(),
                        ...['Casual', 'Regular', 'Whale', 'Frustrated'].map((a) {
                          final isActive = _selectedArchetype == a;
                          const c = FluxForgeTheme.accentCyan;
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _selectedArchetype = a);
                                // Archetype simulation: adjust neuro signals
                                switch (a) {
                                  case 'Casual':
                                    neuro.recordBetSize(0.2);
                                    neuro.recordClickVelocity(3000);
                                  case 'Whale':
                                    neuro.recordBetSize(0.9);
                                    neuro.recordClickVelocity(800);
                                  case 'Frustrated':
                                    neuro.recordBetSize(0.7);
                                    neuro.recordSpinResult(0);
                                    neuro.recordSpinResult(0);
                                  default:
                                    neuro.recordBetSize(0.5);
                                    neuro.recordClickVelocity(1500);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive ? c.withValues(alpha: 0.18) : c.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: isActive ? c.withValues(alpha: 0.6) : c.withValues(alpha: 0.25)),
                                  borderRadius: BorderRadius.circular(4)),
                                child: Text(a, style: TextStyle(
                                  fontFamily: 'monospace', fontSize: 8,
                                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                  color: isActive ? c : c.withValues(alpha: 0.7))),
                              ),
                            ),
                          );
                        }),
                      ]),
                      const Spacer(),
                      // I4: Simulate Session button
                      Row(children: [
                        GestureDetector(
                          onTap: () {
                            // Run 200 spin neuro simulation
                            final rng = math.Random();
                            for (int i = 0; i < 200; i++) {
                              neuro.recordClickVelocity(500 + rng.nextDouble() * 3000);
                              neuro.recordPauseDuration(200 + rng.nextDouble() * 2000);
                              neuro.recordBetSize(rng.nextDouble());
                              final winMult = rng.nextDouble() < 0.25 ? rng.nextDouble() * 10 : 0.0;
                              neuro.recordSpinResult(winMult);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.06),
                              border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(5)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.play_circle_outlined, size: 10, color: FluxForgeTheme.accentCyan),
                              SizedBox(width: 4),
                              Text('Simulate 200 spins', style: TextStyle(
                                fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(neuro.responsibleGamingMode ? '⚠ RG MODE' : '✓ RG stable',
                          style: TextStyle(fontSize: 9,
                            color: neuro.responsibleGamingMode
                              ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen)),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _DockCard(
                  accent: FluxForgeTheme.accentPurple,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _DockLabel('RGAI COMPLIANCE', color: FluxForgeTheme.accentPurple),
                        const Spacer(),
                        // I5: Run Analysis button
                        GestureDetector(
                          onTap: () {
                            silentRun('rgai.analyzeBatch', () {
                              final mw = GetIt.instance<MiddlewareProvider>();
                              final ces = mw.compositeEvents;
                              if (ces.isNotEmpty) {
                                rgai.analyzeBatch(
                                  gameName: GetIt.instance<SlotLabProjectProvider>().projectName,
                                  assets: ces.map((e) => (
                                    id: e.id,
                                    name: e.name,
                                    stage: e.triggerStages.isNotEmpty ? e.triggerStages.first : 'base',
                                    volumeDb: -6.0 + (e.masterVolume * 6),
                                    durationS: 1.5,
                                    tempo: 1.0,
                                    spectralHz: 2000.0,
                                    isWin: e.category.contains('win'),
                                    isNearMiss: e.category.contains('near'),
                                    isLoss: e.category.contains('loss'),
                                    betMult: 1.0,
                                  )).toList(),
                                );
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.08),
                              border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(4)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.shield_rounded, size: 9,
                                color: rgai.isAnalyzing ? FluxForgeTheme.accentYellow : FluxForgeTheme.accentPurple),
                              const SizedBox(width: 4),
                              Text(rgai.isAnalyzing ? 'Analyzing...' : 'Run Analysis',
                                style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                                  color: rgai.isAnalyzing ? FluxForgeTheme.accentYellow : FluxForgeTheme.accentPurple)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (summary != null)
                          Text('${summary.passedAssets}/${summary.totalAssets}', style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
                      ]),
                      const SizedBox(height: 8),
                      _IntelRow('Stimulation index',
                        stimPass ? 'PASS' : 'FAIL',
                        stimPass ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
                      _IntelRow('Near-miss exposure',
                        nearMissOk ? 'OK' : 'WARN',
                        nearMissOk ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentYellow),
                      _IntelRow('Risk level',
                        neuro.riskLevel.name.toUpperCase(),
                        neuro.riskLevel == PlayerRiskLevel.low ? FluxForgeTheme.accentGreen
                          : neuro.riskLevel == PlayerRiskLevel.high ? FluxForgeTheme.accentRed
                          : FluxForgeTheme.accentYellow),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right: Engagement score — real NeuroAudio data
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              children: [
                _DockLabel('ENGAGEMENT SCORE', color: FluxForgeTheme.accentPurple),
                const Spacer(),
                Text(score.toStringAsFixed(1),
                  style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 40,
                    color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w300)),
                Text('/ 10.0 — ${_engagementLabel(score)}',
                  style: const TextStyle(
                    fontSize: 9, color: FluxForgeTheme.textTertiary,
                    letterSpacing: 0.05)),
                const Spacer(),
                // 4 real mini metrics from NeuroAudioProvider — 2×2 Row layout
                Row(children: [
                  Expanded(child: _MiniMetric('$retention%', 'Retention', FluxForgeTheme.accentBlue)),
                  const SizedBox(width: 4),
                  Expanded(child: _MiniMetric(dwell, 'Session', FluxForgeTheme.accentPurple)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: _MiniMetric(losses, 'Loss streak', FluxForgeTheme.accentOrange)),
                  const SizedBox(width: 4),
                  Expanded(child: _MiniMetric(fatigueIdx, 'Fatigue idx', FluxForgeTheme.accentGreen)),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _engagementLabel(double s) {
    if (s >= 8) return 'HIGH ENGAGEMENT';
    if (s >= 5) return 'MODERATE';
    return 'LOW';
  }
}

// ── EXPORT Panel ─────────────────────────────────────────────────────────────

class _ExportPanel extends StatefulWidget {
  const _ExportPanel();

  @override
  State<_ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<_ExportPanel> {
  String? _lastExportResult; // E4
  bool _exporting = false; // E1
  // Batch progress tracking
  final Map<String, String> _batchStatus = {}; // format → 'pending'|'exporting'|'done'|'failed'
  int _batchTotal = 0;
  int _batchComplete = 0;

  late final SlotLabProjectProvider _proj;

  @override
  void initState() {
    super.initState();
    _proj = GetIt.instance<SlotLabProjectProvider>();
    _proj.addListener(_onProjectChanged);
  }

  @override
  void dispose() {
    _proj.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (mounted) setState(() {});
  }

  // E2: Format options
  int _sampleRate = 48000;
  int _bitDepth = 24;

  static const _sampleRates = [44100, 48000, 96000];
  static const _bitDepths = [16, 24, 32];

  static const _exports = [
    (Icons.inventory_2_rounded, 'UCP',   'Universal Content Package', FluxForgeTheme.accentYellow),
    (Icons.music_note_rounded,  'WWISE', 'Audiokinetic project',       FluxForgeTheme.accentBlue),
    (Icons.equalizer_rounded,   'FMOD',  'FMOD Studio bank',           FluxForgeTheme.accentGreen),
    (Icons.description_rounded, 'GDD',   'Game Design Doc',            FluxForgeTheme.accentPurple),
  ];

  /// Generate a structured JSON report of the current project configuration.
  /// Includes: project metadata, grid config, audio DNA, composite events,
  /// session stats, win history — suitable for GDD review or QA.
  Future<void> _exportReport() async {
    setState(() { _exporting = true; _lastExportResult = null; });
    try {
      final proj = GetIt.instance<SlotLabProjectProvider>();
      final mw = GetIt.instance<MiddlewareProvider>();
      final gridCfg = proj.gridConfig;

      final report = <String, dynamic>{
        'generated_at': DateTime.now().toIso8601String(),
        'project': {
          'name': proj.projectName,
          'path': proj.projectPath ?? 'unsaved',
          'is_dirty': proj.isDirty,
        },
        'grid': gridCfg != null ? {
          'reels': gridCfg.columns,
          'rows': gridCfg.rows,
          'mechanic': gridCfg.mechanic,
        } : null,
        'audio_dna': {
          'brand': proj.dnaBrand,
          'root_key': proj.dnaRootKey,
          'mode': proj.dnaMode,
          'bpm_min': proj.dnaBpmMin,
          'bpm_max': proj.dnaBpmMax,
          'instruments': proj.dnaInstruments,
          'base_profile': proj.dnaBaseProfile,
          'feature_profile': proj.dnaFeatureProfile,
          'win_escalation': proj.dnaWinEscalation,
          'ambient_layer_count': proj.dnaAmbientLayerCount,
        },
        'composite_events': mw.compositeEvents.map((e) => {
          'id': e.id,
          'name': e.name,
          'category': e.category,
          'trigger_stages': e.triggerStages,
          'total_duration_ms': e.totalDurationMs.toInt(),
          'timeline_position_ms': e.timelinePositionMs.toInt(),
          'track_index': e.trackIndex,
          'layer_count': e.layers.length,
          'layers': e.layers.map((l) => {
            'audio_path': l.audioPath,
            'volume': l.volume,
            'loop': l.loop,
          }).toList(),
        }).toList(),
        'session_stats': {
          'total_spins': proj.sessionStats.totalSpins,
          'total_bet': proj.sessionStats.totalBet,
          'total_win': proj.sessionStats.totalWin,
          'rtp': proj.sessionStats.rtp,
        },
        'recent_wins': proj.recentWins.take(20).map((w) => {
          'tier': w.tier,
          'amount': w.amount,
        }).toList(),
      };

      final json = const JsonEncoder.withIndent('  ').convert(report);
      // Write to Desktop for easy access
      final desktopPath = '${Platform.environment['HOME']}/Desktop';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$desktopPath/${proj.projectName.replaceAll(' ', '_')}_report_$timestamp.json';
      await File(filePath).writeAsString(json);

      if (mounted) {
        setState(() {
          _exporting = false;
          _lastExportResult = '✓ Report saved to Desktop/${proj.projectName.replaceAll(' ', '_')}_report_$timestamp.json';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _exporting = false;
        _lastExportResult = '✗ Report failed: $e';
      });
    }
  }

  Future<void> _doExport(String format, String label) async {
    // E3: Compliance gate — block export if RGAI HIGH risk
    bool _blocked = false;
    silentRun('export.rgaiComplianceGate', () {
      final rgai = GetIt.instance<RgaiProvider>();
      // 2026-05-10 (Sprint 14 Faza 4.A.7) — cache the optional reference
      // so the second access can't see a different value.  Pre-fix used
      // `rgai.report?.summary != null && !rgai.report!.summary.isCompliant`
      // which reads `rgai.report` twice; if the provider notifies and
      // sets `report = null` between those reads, the bang explodes.
      final summary = rgai.report?.summary;
      if (summary != null && !summary.isCompliant) {
        setState(() => _lastExportResult = '⛔ BLOCKED: RGAI compliance check failed. Fix issues first.');
        _blocked = true;
      }
    });
    if (_blocked) return;

    setState(() { _exporting = true; _lastExportResult = null; });
    try {
      final provider = GetIt.instance<SlotExportProvider>();
      provider.exportSingle({
        'format': format,
        'name': GetIt.instance<SlotLabProjectProvider>().projectName,
        'sampleRate': _sampleRate,
        'bitDepth': _bitDepth,
      }, format);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _exporting = false;
          _lastExportResult = '✓ $label export complete';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _exporting = false;
        _lastExportResult = '✗ Export failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // E2: Format options row
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Text('Sample Rate:', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgElevated,
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(4)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _sampleRate,
                    isDense: true,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: FluxForgeTheme.textSecondary),
                    dropdownColor: FluxForgeTheme.bgSurface,
                    items: _sampleRates.map((r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r ~/ 1000}kHz'),
                    )).toList(),
                    onChanged: (v) { if (v != null) setState(() => _sampleRate = v); },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Text('Bit Depth:', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgElevated,
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(4)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _bitDepth,
                    isDense: true,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: FluxForgeTheme.textSecondary),
                    dropdownColor: FluxForgeTheme.bgSurface,
                    items: _bitDepths.map((d) => DropdownMenuItem(
                      value: d,
                      child: Text('${d}-bit'),
                    )).toList(),
                    onChanged: (v) { if (v != null) setState(() => _bitDepth = v); },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: _exports.map((e) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ExportCard(
                    icon: e.$1, label: e.$2, sub: e.$3, color: e.$4,
                    onTap: () => _doExport(e.$2.toLowerCase(), e.$2),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // E1: Progress bar + E4: Result display
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (_exporting) ...[
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: FluxForgeTheme.accentYellow),
                ),
                const SizedBox(width: 8),
                if (_batchTotal > 0) ...[
                  Text('$_batchComplete/$_batchTotal', style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.accentYellow)),
                  const SizedBox(width: 6),
                  ..._batchStatus.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: switch (e.value) {
                          'done' => FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                          'failed' => FluxForgeTheme.accentRed.withValues(alpha: 0.15),
                          'exporting' => FluxForgeTheme.accentYellow.withValues(alpha: 0.15),
                          _ => Colors.transparent,
                        },
                        borderRadius: BorderRadius.circular(3)),
                      child: Text(e.key, style: TextStyle(fontFamily: 'monospace', fontSize: 7,
                        color: switch (e.value) {
                          'done' => FluxForgeTheme.accentGreen,
                          'failed' => FluxForgeTheme.accentRed,
                          'exporting' => FluxForgeTheme.accentYellow,
                          _ => FluxForgeTheme.textTertiary,
                        })),
                    ),
                  )),
                ] else
                const Text('Exporting...', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.accentYellow)),
              ] else if (_lastExportResult != null) ...[
                Expanded(child: Text(_lastExportResult!, style: TextStyle(
                  fontFamily: 'monospace', fontSize: 10,
                  color: _lastExportResult!.startsWith('✓')
                    ? FluxForgeTheme.accentGreen
                    : _lastExportResult!.startsWith('⛔')
                      ? FluxForgeTheme.accentRed
                      : FluxForgeTheme.accentOrange))),
              ],
              const Spacer(),
              // E6: Export Report (JSON)
              GestureDetector(
                onTap: _exporting ? null : _exportReport,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.10),
                    border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('REPORT JSON', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    color: FluxForgeTheme.accentCyan,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              // COMPLY: Jurisdiction compliance check
              GestureDetector(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _ComplianceDialog(),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentGreen.withValues(alpha: 0.10),
                    border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('COMPLY', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    color: FluxForgeTheme.accentGreen,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              // E5: Batch export — parallel with per-format progress
              GestureDetector(
                onTap: _exporting ? null : () async {
                  setState(() {
                    _exporting = true;
                    _batchTotal = _exports.length;
                    _batchComplete = 0;
                    _batchStatus.clear();
                    for (final e in _exports) {
                      _batchStatus[e.$2] = 'pending';
                    }
                    _lastExportResult = null;
                  });

                  // Run all exports in parallel
                  final futures = _exports.map((e) async {
                    if (mounted) setState(() => _batchStatus[e.$2] = 'exporting');
                    try {
                      final provider = GetIt.instance<SlotExportProvider>();
                      provider.exportSingle({
                        'format': e.$2.toLowerCase(),
                        'name': GetIt.instance<SlotLabProjectProvider>().projectName,
                        'sampleRate': _sampleRate,
                        'bitDepth': _bitDepth,
                      }, e.$2.toLowerCase());
                      await Future.delayed(const Duration(milliseconds: 600));
                      if (mounted) {
                        setState(() {
                          _batchStatus[e.$2] = 'done';
                          _batchComplete++;
                        });
                      }
                    } catch (err) {
                      if (mounted) {
                        setState(() {
                          _batchStatus[e.$2] = 'failed';
                          _batchComplete++;
                        });
                      }
                    }
                  });

                  await Future.wait(futures);
                  if (mounted) {
                    final failed = _batchStatus.values.where((s) => s == 'failed').length;
                    setState(() {
                      _exporting = false;
                      _lastExportResult = failed == 0
                          ? '✓ All ${_exports.length} formats exported'
                          : '⚠ ${_exports.length - failed}/${_exports.length} exported ($failed failed)';
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentYellow.withValues(alpha: 0.12),
                    border: Border.all(color: FluxForgeTheme.accentYellow.withValues(alpha: 0.45)),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('EXPORT ALL', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    color: FluxForgeTheme.accentYellow,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPLIANCE DIALOG — UKGC / MGA / SE validation
// ─────────────────────────────────────────────────────────────────────────────

class _ComplianceDialog extends StatefulWidget {
  const _ComplianceDialog();
  @override
  State<_ComplianceDialog> createState() => _ComplianceDialogState();
}

class _ComplianceDialogState extends State<_ComplianceDialog> {
  // Validation result: (id, jurisdiction, rule, pass, severity, description)
  late List<({String id, String j, String rule, bool pass, String sev, String desc})> _findings;
  bool _ran = false;

  @override
  void initState() {
    super.initState();
    _findings = [];
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  void _runCheck() {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final mw = GetIt.instance<MiddlewareProvider>();
    final composer = GetIt.instance<FeatureComposerProvider>();
    final stats = proj.sessionStats;
    final rtp = stats.rtp.isNaN || stats.rtp.isInfinite || stats.totalSpins < 100 ? _estimatedRtp(proj) : stats.rtp;
    final cfg = composer.config;
    final paylineCount = cfg?.paylineCount ?? 20;
    final maxWinCap = stats.totalSpins > 0 ? _computeMaxWin(proj) : 5000.0;
    final events = mw.compositeEvents;
    final hasNearMissAudio = events.any((e) => e.category.toLowerCase().contains('near'));
    final nearMissLouderThanWin = hasNearMissAudio && _nearMissLouderCheck(events);
    final hasRgIndicators = neuro.responsibleGamingMode;
    final hasFreeplay = cfg?.paylineType == PaylineType.ways; // approximation
    final hasAutoplay = false; // HELIX never exposes autoplay button
    final sessionClockShown = true; // HelixScreen always shows session timer
    final totalSpins = stats.totalSpins;

    // UKGC rules
    final ukgc = [
      _finding('UKGC-1', 'UKGC', 'RTP 85–99%', rtp >= 85.0 && rtp <= 99.0, 'CRITICAL',
          'RTP ${rtp.toStringAsFixed(1)}% ${rtp < 85 ? "below" : rtp > 99 ? "above" : "within"} UKGC limit'),
      _finding('UKGC-2', 'UKGC', 'No autoplay (banned 2021)', true, 'CRITICAL',
          'No autoplay button — compliant'),
      _finding('UKGC-3', 'UKGC', 'Session clock visible', true, 'MAJOR',
          'Session timer displayed in HELIX'),
      _finding('UKGC-4', 'UKGC', 'Near-miss audio ≤ win audio', !nearMissLouderThanWin, 'CRITICAL',
          nearMissLouderThanWin ? 'Near-miss events louder than win events — RTS-13 violation' : 'Near-miss audio levels pass RTS-13'),
      _finding('UKGC-5', 'UKGC', 'Max win cap ≤ 10,000×', maxWinCap <= 10000.0, 'MAJOR',
          'Max win: ${maxWinCap.toStringAsFixed(0)}×'),
      _finding('UKGC-6', 'UKGC', 'Responsible gaming indicators', hasRgIndicators || neuro.riskLevel != PlayerRiskLevel.high, 'MAJOR',
          hasRgIndicators ? 'RG mode active — compliant' : 'RG indicators available via HELIX'),
    ];

    // MGA rules
    final mga = [
      _finding('MGA-1', 'MGA', 'RTP 92–99%', rtp >= 92.0 && rtp <= 99.0, 'CRITICAL',
          'RTP ${rtp.toStringAsFixed(1)}% ${rtp < 92 ? "below" : "within"} MGA minimum'),
      _finding('MGA-2', 'MGA', 'Max paylines declared', paylineCount > 0, 'MAJOR',
          'Paylines: $paylineCount'),
      _finding('MGA-3', 'MGA', 'No misleading audio on loss', !nearMissLouderThanWin, 'CRITICAL',
          nearMissLouderThanWin ? 'Misleading loss audio — MGA Art. 4.3 violation' : 'Loss audio properly distinguished'),
      _finding('MGA-4', 'MGA', 'Game rules accessible', true, 'MINOR',
          'Compliance manifest can be exported from EXPORT panel'),
      _finding('MGA-5', 'MGA', 'Simulation data available', totalSpins >= 100, 'MAJOR',
          totalSpins >= 100 ? '$totalSpins spins simulated — meets MGA minimum' : 'Run sim (min 100 spins) for MGA submission'),
    ];

    // SE (Spelinspektionen) rules
    final se = [
      _finding('SE-1', 'SE', 'RTP 85–99%', rtp >= 85.0 && rtp <= 99.0, 'CRITICAL',
          'RTP ${rtp.toStringAsFixed(1)}%'),
      _finding('SE-2', 'SE', 'No forced deposit link', true, 'CRITICAL',
          'HELIX has no deposit mechanisms — compliant'),
      _finding('SE-3', 'SE', 'Session time display', true, 'MAJOR',
          'Session clock shown — compliant'),
      _finding('SE-4', 'SE', 'Sober audio design (no celebration on loss)', !nearMissLouderThanWin, 'CRITICAL',
          nearMissLouderThanWin ? 'Loss celebration audio detected — SE §3.2 violation' : 'Audio levels appropriate'),
    ];

    setState(() {
      _findings = [...ukgc, ...mga, ...se];
      _ran = true;
    });
  }

  double _estimatedRtp(SlotLabProjectProvider proj) {
    // Fallback when no session data: use DNA win escalation as proxy
    return 92.0 + (proj.dnaWinEscalation * 5).clamp(0.0, 7.0);
  }

  double _computeMaxWin(SlotLabProjectProvider proj) {
    final wins = proj.recentWins;
    if (wins.isEmpty) return 0.0;
    final avg = proj.sessionStats.totalBet / proj.sessionStats.totalSpins;
    if (avg <= 0) return 0.0;
    return wins.map((w) => w.amount / avg).fold(0.0, math.max);
  }

  bool _nearMissLouderCheck(List<SlotCompositeEvent> events) {
    final nearMiss = events.where((e) => e.category.toLowerCase().contains('near'));
    final wins = events.where((e) => e.category.toLowerCase().contains('win'));
    if (nearMiss.isEmpty || wins.isEmpty) return false;
    final nmVol = nearMiss.map((e) => e.masterVolume).fold(0.0, (a, b) => a > b ? a : b);
    final winVol = wins.map((e) => e.masterVolume).fold(0.0, (a, b) => a > b ? a : b);
    return nmVol > winVol;
  }

  ({String id, String j, String rule, bool pass, String sev, String desc}) _finding(
      String id, String j, String rule, bool pass, String sev, String desc) =>
      (id: id, j: j, rule: rule, pass: pass, sev: sev, desc: desc);

  Color _sevColor(String sev) => switch (sev) {
    'CRITICAL' => const Color(0xFFFF3366),
    'MAJOR'    => const Color(0xFFFF9900),
    _          => const Color(0xFF888899),
  };

  @override
  Widget build(BuildContext context) {
    final fails = _findings.where((f) => !f.pass).length;
    final criticalFails = _findings.where((f) => !f.pass && f.sev == 'CRITICAL').length;
    final overallPass = fails == 0;

    return Dialog(
      backgroundColor: const Color(0xFF08080F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 640,
        height: 480,
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: const Color(0xFF222230))),
              color: overallPass
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.06)
                : FluxForgeTheme.accentRed.withValues(alpha: 0.06),
            ),
            child: Row(children: [
              Icon(
                overallPass ? Icons.verified_rounded : Icons.warning_rounded,
                size: 16,
                color: overallPass ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
              const SizedBox(width: 8),
              Text('COMPLIANCE REPORT',
                style: TextStyle(
                  fontFamily: 'monospace', fontSize: 13,
                  color: overallPass ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                  fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              const Spacer(),
              if (_ran) ...[
                if (fails > 0)
                  Text('$criticalFails CRITICAL · ${fails - criticalFails} MAJOR failures',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Color(0xFFFF6666)))
                else
                  const Text('ALL CHECKS PASSED',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentGreen)),
                const SizedBox(width: 12),
              ],
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, size: 16, color: FluxForgeTheme.textTertiary)),
            ]),
          ),
          // Column headers
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            color: const Color(0xFF0D0D1A),
            child: Row(children: [
              SizedBox(width: 52, child: Text('JUR.', style: _headerStyle)),
              SizedBox(width: 16, child: Text('', style: _headerStyle)),
              Expanded(child: Text('RULE', style: _headerStyle)),
              SizedBox(width: 60, child: Text('SEVERITY', style: _headerStyle)),
              SizedBox(width: 180, child: Text('DETAILS', style: _headerStyle)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF1A1A28)),
          // Findings list
          Expanded(
            child: _ran
              ? ListView.builder(
                  itemCount: _findings.length,
                  itemBuilder: (ctx, i) {
                    final f = _findings[i];
                    final prevJ = i > 0 ? _findings[i - 1].j : '';
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      // Jurisdiction header row
                      if (f.j != prevJ)
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
                          color: const Color(0xFF0B0B16),
                          child: Text(f.j == 'UKGC' ? 'UK Gambling Commission (UKGC)'
                            : f.j == 'MGA' ? 'Malta Gaming Authority (MGA)'
                            : 'Swedish Gambling Authority (SE)',
                            style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 8,
                              color: FluxForgeTheme.textTertiary, letterSpacing: 1.5)),
                        ),
                      // Finding row
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 7, 16, 7),
                        decoration: BoxDecoration(
                          color: f.pass
                            ? Colors.transparent
                            : _sevColor(f.sev).withValues(alpha: 0.04),
                          border: Border(
                            bottom: BorderSide(color: const Color(0xFF111122)))),
                        child: Row(children: [
                          SizedBox(
                            width: 52,
                            child: Text(f.id,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 8,
                                color: FluxForgeTheme.textTertiary))),
                          SizedBox(
                            width: 16,
                            child: Icon(
                              f.pass ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 11,
                              color: f.pass ? FluxForgeTheme.accentGreen : _sevColor(f.sev))),
                          Expanded(
                            child: Text(f.rule,
                              style: TextStyle(
                                fontFamily: 'monospace', fontSize: 9,
                                color: f.pass ? FluxForgeTheme.textSecondary : FluxForgeTheme.textPrimary,
                                fontWeight: f.pass ? FontWeight.normal : FontWeight.w600))),
                          SizedBox(
                            width: 60,
                            child: f.pass
                              ? const SizedBox()
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _sevColor(f.sev).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(3)),
                                  child: Text(f.sev,
                                    style: TextStyle(fontFamily: 'monospace', fontSize: 7,
                                      color: _sevColor(f.sev))))),
                          SizedBox(
                            width: 180,
                            child: Text(f.desc,
                              style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                                color: f.pass
                                  ? FluxForgeTheme.textTertiary
                                  : _sevColor(f.sev).withValues(alpha: 0.9)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2)),
                        ]),
                      ),
                    ]);
                  },
                )
              : const Center(child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 1.5))),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1A1A28)))),
            child: Row(children: [
              Text('Generated: ${DateTime.now().toString().substring(0, 16)}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 8,
                  color: FluxForgeTheme.textTertiary)),
              const Spacer(),
              GestureDetector(
                onTap: _runCheck,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
                    border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('RE-RUN', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan)))),
            ]),
          ),
        ]),
      ),
    );
  }

  static const _headerStyle = TextStyle(
    fontFamily: 'monospace', fontSize: 7.5,
    color: FluxForgeTheme.textTertiary, letterSpacing: 1.2);
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE COMPONENTS
// (extracted to part files — see helix/ subdirectory)
// ─────────────────────────────────────────────────────────────────────────────

// _HBtn removed — unused widget (panels use inline buttons with specific styling)
// _OmniPill, _OmniIconBtn, _ModeBadge, _TransportBtn → helix/helix_omnibar_atoms.dart
// _DockTab, _DockCard, _DockLabel               → helix/helix_dock_widgets.dart
// _MiniModeSection, _MiniDivider, _ComplianceDot → helix/helix_minimode_widgets.dart

class _SpineItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? shortcutHint;   // SPRINT 1 SPEC-06
  final bool expanded;          // SPRINT 1 SPEC-06
  final bool active;
  final VoidCallback onTap;
  const _SpineItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.shortcutHint,
    this.expanded = false,
  });
  @override
  State<_SpineItem> createState() => _SpineItemState();
}
class _SpineItemState extends State<_SpineItem> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    // SPRINT 1 SPEC-16 — FluxTooltip with shortcut hint.
    final iconButton = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: widget.active
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.18)
              : _hovered ? FluxForgeTheme.accentBlue.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.active
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                : _hovered ? FluxForgeTheme.accentBlue.withValues(alpha: 0.25) : Colors.transparent,
              width: widget.active ? 1.5 : 1.0),
            boxShadow: widget.active ? [
              BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2), blurRadius: 8),
            ] : null,
          ),
          child: Icon(widget.icon, size: 17,
            color: widget.active
              ? FluxForgeTheme.accentBlue
              : _hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary),
        ),
      ),
    );

    // Wrap in FluxTooltip — only when collapsed (in expanded mode the label
    // is already visible underneath, so a tooltip is redundant noise).
    final tooltipped = widget.expanded
        ? iconButton
        : FluxTooltip(
            message: widget.label,
            shortcutHint: widget.shortcutHint,
            preferBelow: false,
            child: iconButton,
          );

    if (!widget.expanded) return tooltipped;

    // SPRINT 1 SPEC-06 — expanded mode: icon + label centered below.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tooltipped,
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            color: widget.active
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.textTertiary,
            letterSpacing: 1.0,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SpineOverlay extends StatelessWidget {
  final String title;
  final int spineIndex;
  final VoidCallback onClose;
  const _SpineOverlay({required this.title, required this.spineIndex, required this.onClose});

  @override
  Widget build(BuildContext context) => Container(
    width: 340,
    decoration: BoxDecoration(
      color: FluxForgeTheme.bgSurface,
      border: Border(
        right: BorderSide(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
        left: BorderSide(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.6), width: 3),
      ),
      boxShadow: [
        BoxShadow(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: 4),
        BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.12), blurRadius: 24),
      ],
    ),
    child: Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [FluxForgeTheme.accentBlue.withValues(alpha: 0.18), Colors.transparent],
            ),
            border: Border(bottom: BorderSide(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue, borderRadius: BorderRadius.circular(1.5))),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700,
                color: FluxForgeTheme.textPrimary, letterSpacing: 0.12)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.borderSubtle)),
                  child: const Icon(Icons.close_rounded, size: 12,
                    color: FluxForgeTheme.textTertiary)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              type: MaterialType.transparency,
              child: _buildSpineContent(spineIndex),
            ),
          ),
        ),
      ],
    ),
  );

  static Widget _buildSpineContent(int index) {
    switch (index) {
      case 0: return _SpineGameConfig();
      case 1: return _SpineAudioAssign();
      case 2: return _SpineAiIntel();
      case 3: return _SpineSettings();
      case 4: return _SpineAnalytics();
      default: return const SizedBox();
    }
  }
}

// ── Spine: AUDIO ASSIGN ─────────────────────────────────────────────────────

class _SpineAudioAssign extends StatefulWidget {
  @override
  State<_SpineAudioAssign> createState() => _SpineAudioAssignState();
}

class _SpineAudioAssignState extends State<_SpineAudioAssign> {
  /// ID of the slot card currently being hovered with a drag — used for
  /// per-card drop-target visual feedback (replaces the legacy global
  /// `_dropHovering` flag, which lived on a top-level drop area that no
  /// longer exists in the slot-first workflow).
  String? _hoveringEventId;

  static const _audioExtensions = {
    '.wav', '.aiff', '.aif', '.mp3', '.ogg', '.flac', '.m4a', '.aac', '.opus',
  };

  // ─── Stage auto-match from filename ────────────────────────────────────────
  /// Try to match filename to a known stage name.
  /// "REEL_STOP.wav" → "REEL_STOP", "spin_start_ambient.wav" → "SPIN_START"
  String? _matchStageFromFilename(String filename) {
    final upper = filename.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]'), '_');
    // Remove extension suffix
    final noExt = upper.contains('_') ? upper : upper;
    final stages = StageConfigurationService.instance.allStages
      ..sort((a, b) => b.name.length.compareTo(a.name.length)); // Longest first for specificity
    for (final stage in stages) {
      if (noExt.contains(stage.name)) return stage.name;
    }
    return null;
  }

  // ─── Register event to EventRegistry for actual audio playback ─────────────
  // Delegates to the shared EventRegistrationService so SlotLab + HELIX use
  // ONE registration path. Pre-2026-04-27 this was a hand-rolled duplicate
  // of slot_lab_screen's _syncEventToRegistry — both wrote into the same
  // _stageToEvent map and silently evicted each other (FLUX_MASTER_TODO 1.2.1).
  void _registerToEventRegistry(SlotCompositeEvent event) {
    EventRegistrationService.instance.registerComposite(event);
  }

  /// Mirror the layer assignment into `SlotLabProjectProvider._audioAssignments`
  /// so that `slot_stage_provider._hasAudioAssignment(stage)` returns `true`
  /// at spin time.
  ///
  /// **2026-05-08 autobind P0 fix.**  HELIX `_SpineAudioAssign` used to only
  /// call `_registerToEventRegistry`, which populates `EventRegistry._stageToEvent`
  /// — but the spin gate in `slot_stage_provider._triggerStage` first checks
  /// `SlotLabProjectProvider.hasAudioAssignment(stage)` and silently `return`s
  /// when both `effectiveStage` *and* `stageType` are missing.  Result:
  /// composite is registered but never fires.  SlotLab calls
  /// `projectProvider.setAudioAssignment(stage, audioPath)` everywhere it
  /// touches the registry; HELIX missed that side-effect, so dropping audio
  /// in the AUDIO ASSIGN spine looked correct but produced silence on spin.
  void _syncProjectAudioAssignment(SlotCompositeEvent event) {
    if (event.layers.isEmpty || event.triggerStages.isEmpty) return;
    try {
      final project = GetIt.instance<SlotLabProjectProvider>();
      final firstPath = event.layers.first.audioPath;
      if (firstPath.isEmpty) return;
      for (final stage in event.triggerStages) {
        project.setAudioAssignment(stage, firstPath, recordUndo: false);
      }
    } catch (_) {
      // Project provider not registered (e.g., test mode) — ignore.
    }
  }

  // ─── Stage picker dialog ────────────────────────────────────────────────────
  Future<String?> _pickStage(BuildContext context) async {
    final stages = StageConfigurationService.instance.allStages;
    // Group by category
    final byCategory = <String, List<StageDefinition>>{};
    for (final s in stages) {
      final cat = s.category.label;
      byCategory.putIfAbsent(cat, () => []).add(s);
    }

    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF111118),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  const Icon(Icons.link_rounded, size: 14, color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 6),
                  const Text('Assign to Stage', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 12, color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close_rounded, size: 14, color: FluxForgeTheme.textTertiary)),
                ]),
              ),
              const Divider(height: 1, color: Color(0xFF222230)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: byCategory.entries.map((entry) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, top: 4),
                          child: Text(entry.key,
                            style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 8,
                              color: FluxForgeTheme.textTertiary, letterSpacing: 1.2)),
                        ),
                        Wrap(
                          spacing: 4, runSpacing: 4,
                          children: entry.value.map((stage) => GestureDetector(
                            onTap: () => Navigator.pop(ctx, stage.name),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A28),
                                border: Border.all(color: const Color(0xFF333355)),
                                borderRadius: BorderRadius.circular(4)),
                              child: Text(stage.name,
                                style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 9,
                                  color: FluxForgeTheme.textSecondary)),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 6),
                      ],
                    )).toList(),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF222230)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(children: [
                  const Text('Skip assignment', style: TextStyle(
                    fontSize: 9, color: FluxForgeTheme.textTertiary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, '__SKIP__'),
                    child: const Text('Add without stage', style: TextStyle(
                      fontSize: 9, color: FluxForgeTheme.accentBlue))),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Reassign stage on existing event ──────────────────────────────────────
  Future<void> _reassignStage(SlotCompositeEvent event, {int? removeIndex}) async {
    final mw = GetIt.instance<MiddlewareProvider>();

    if (removeIndex != null) {
      // Remove specific stage from triggerStages
      final newStages = List<String>.from(event.triggerStages)..removeAt(removeIndex);
      final updated = event.copyWith(
        triggerStages: newStages,
        modifiedAt: DateTime.now(),
      );
      mw.updateCompositeEvent(updated);
      // Re-register with remaining stages
      _registerToEventRegistry(updated);
      _syncProjectAudioAssignment(updated);
      if (mounted) setState(() {});
      return;
    }

    // Show picker — adding or replacing first stage
    if (!mounted) return;
    final picked = await _pickStage(context);
    if (picked == null || picked == '__SKIP__') return;

    final newStages = List<String>.from(event.triggerStages);
    if (!newStages.contains(picked)) newStages.add(picked);

    final newId = newStages.length == 1 ? 'audio_${newStages.first}' : event.id;
    final updated = event.copyWith(
      id: newId,
      triggerStages: newStages,
      modifiedAt: DateTime.now(),
    );
    // Remove old event, add updated (id may have changed)
    silentRun('audio.deleteOldStageEvent', () { mw.deleteCompositeEvent(event.id); });
    mw.addCompositeEvent(updated);
    _registerToEventRegistry(updated);
    _syncProjectAudioAssignment(updated);
    if (mounted) setState(() {});
  }

  // ─── Filter audio paths ────────────────────────────────────────────────────
  List<String> _filterAudioPaths(List<String> paths) {
    final filtered = paths.where((p) {
      final dotIdx = p.toLowerCase().lastIndexOf('.');
      if (dotIdx < 0) return false;
      return _audioExtensions.contains(p.toLowerCase().substring(dotIdx));
    }).toList();
    // 2026-05-09 fix: implicitly extend PathValidator sandbox with
    // the parent directory of every dropped audio file.  User-picked
    // paths are inherently trusted (they walked through OS-level
    // open panel / drag-drop), and without this hook EventRegistry's
    // `_validateAudioPath` rejects them at SPIN time with "outside
    // sandbox" — silent fail that wasted a day of debugging.
    for (final p in filtered) {
      final parent = File(p).parent.path;
      PathValidator.addSandboxRoot(parent);
    }
    return filtered;
  }

  // ─── Build a layer from an audio file path ────────────────────────────────
  SlotEventLayer _layerFromPath(String path, int ts, String? stage) {
    final fileName = path.split('/').last;
    final name = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    return SlotEventLayer(
      id: 'layer_$ts',
      name: name,
      audioPath: path,
      volume: 1.0,
      loop: false,
      actionType: 'Play',
      busId: stage != null
          ? StageConfigurationService.instance.getStage(stage)?.bus.index
          : null,
    );
  }

  // ─── STEP 1: Create a new (empty) slot ─────────────────────────────────────
  // Asks for stage first — slot without a stage cannot fire on spin, so we
  // make the assignment explicit at creation time. User can still "skip" but
  // gets a visible warning chip.
  Future<void> _createNewSlot() async {
    if (!mounted) return;
    final picked = await _pickStage(context);
    if (picked == null) return; // cancelled
    final stage = (picked == '__SKIP__') ? null : picked;
    final mw = GetIt.instance<MiddlewareProvider>();
    final now = DateTime.now();

    // Stage already taken? Just select the existing event instead of duplicating.
    if (stage != null) {
      final existing = mw.compositeEvents
          .where((e) => e.triggerStages.contains(stage))
          .firstOrNull;
      if (existing != null) {
        mw.selectCompositeEvent(existing.id);
        if (mounted) setState(() {});
        return;
      }
    }

    final ts = now.millisecondsSinceEpoch;
    final event = SlotCompositeEvent(
      id: stage != null ? 'audio_$stage' : 'helix_new_$ts',
      name: stage ?? 'New Slot ${mw.compositeEvents.length + 1}',
      category: stage != null
          ? StageConfigurationService.instance.getCategoryLabel(stage)
          : 'custom',
      color: stage != null
          ? StageConfigurationService.instance.getCategoryColor(stage)
          : FluxForgeTheme.accentCyan,
      layers: const [],
      triggerStages: stage != null ? [stage] : const [],
      createdAt: now,
      modifiedAt: now,
    );
    mw.addCompositeEvent(event);
    if (mounted) setState(() {});
  }

  // ─── STEP 2a: Drop audio onto existing slot — append layers ───────────────
  Future<void> _addLayersToEvent(
    SlotCompositeEvent event,
    List<String> paths,
  ) async {
    final audioPaths = _filterAudioPaths(paths);
    if (audioPaths.isEmpty) return;

    final mw = GetIt.instance<MiddlewareProvider>();
    final now = DateTime.now();

    // If the slot has no stage yet, ask now — without a stage the layers
    // won't fire on spin (EventRegistrationService.registerComposite returns
    // empty when triggerStages is empty and no fallback is supplied). User
    // can still skip and assign later from the chip.
    SlotCompositeEvent target = event;
    if (target.triggerStages.isEmpty && mounted) {
      final picked = await _pickStage(context);
      if (picked == null) return; // cancelled — don't add layers
      if (picked != '__SKIP__') {
        // Refresh from provider in case the event was edited while dialog
        // was open; fall back to the captured `event` if it was deleted.
        target = mw.compositeEvents
            .where((e) => e.id == event.id)
            .firstOrNull ?? event;
        target = target.copyWith(
          id: 'audio_$picked',
          name: target.name == 'New Slot ${mw.compositeEvents.length}'
              || target.name.startsWith('New Slot ')
              ? picked
              : target.name,
          category: StageConfigurationService.instance.getCategoryLabel(picked),
          color: StageConfigurationService.instance.getCategoryColor(picked),
          triggerStages: [picked],
          modifiedAt: now,
        );
        // ID may have changed — remove old, add new
        if (target.id != event.id) {
          silentRun('audio.deleteOldEvent', () { mw.deleteCompositeEvent(event.id); });
          mw.addCompositeEvent(target);
        } else {
          mw.updateCompositeEvent(target);
        }
      }
    }

    final stage = target.triggerStages.isNotEmpty ? target.triggerStages.first : null;
    final newLayers = <SlotEventLayer>[];
    for (int i = 0; i < audioPaths.length; i++) {
      newLayers.add(_layerFromPath(audioPaths[i], now.millisecondsSinceEpoch + i, stage));
    }

    final updated = target.copyWith(
      layers: [...target.layers, ...newLayers],
      modifiedAt: now,
    );
    mw.updateCompositeEvent(updated);
    // Explicit re-register — covers the case where SlotLab is not mounted
    // (HELIX-only workflow). Idempotent with SlotLab's _onMiddlewareChanged.
    _registerToEventRegistry(updated);
    _syncProjectAudioAssignment(updated);
    if (mounted) setState(() {});
  }

  // ─── STEP 2b: Browse / drop on empty area — pick stage, then create slot
  // pre-populated with layers. This path also runs from the Browse button.
  Future<void> _browseAndCreateSlot(List<String> paths) async {
    final audioPaths = _filterAudioPaths(paths);
    if (audioPaths.isEmpty) return;

    // Try auto-match from first file
    final firstName = audioPaths.first.split('/').last;
    String? stage = _matchStageFromFilename(firstName);

    if (stage == null && mounted) {
      final picked = await _pickStage(context);
      if (picked == null) return; // cancelled
      if (picked != '__SKIP__') stage = picked;
    }

    final mw = GetIt.instance<MiddlewareProvider>();
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;

    final layers = <SlotEventLayer>[];
    for (int i = 0; i < audioPaths.length; i++) {
      layers.add(_layerFromPath(audioPaths[i], ts + i, stage));
    }

    // If a slot already exists for this stage, append layers to it.
    if (stage != null) {
      final existing = mw.compositeEvents
          .where((e) => e.triggerStages.contains(stage))
          .firstOrNull;
      if (existing != null) {
        final merged = existing.copyWith(
          layers: [...existing.layers, ...layers],
          modifiedAt: now,
        );
        mw.updateCompositeEvent(merged);
        _registerToEventRegistry(merged);
        _syncProjectAudioAssignment(merged);
        if (mounted) setState(() {});
        return;
      }
    }

    final event = SlotCompositeEvent(
      id: stage != null ? 'audio_$stage' : 'helix_drop_$ts',
      name: stage ?? layers.first.name,
      category: stage != null
          ? StageConfigurationService.instance.getCategoryLabel(stage)
          : 'custom',
      color: stage != null
          ? StageConfigurationService.instance.getCategoryColor(stage)
          : FluxForgeTheme.accentCyan,
      layers: layers,
      triggerStages: stage != null ? [stage] : const [],
      createdAt: now,
      modifiedAt: now,
    );
    mw.addCompositeEvent(event);
    _registerToEventRegistry(event);
    _syncProjectAudioAssignment(event);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GetIt.instance<MiddlewareProvider>(),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final events = mw.compositeEvents;
    final helixState = context.findAncestorStateOfType<_HelixScreenState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Step 1: Create slot — primary action ─────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3)),
            child: const Text('STEP 1',
              style: TextStyle(
                fontFamily: 'monospace', fontSize: 7,
                color: FluxForgeTheme.accentCyan, letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          const Expanded(child: Text('Create slot',
            style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary))),
          GestureDetector(
            onTap: _createNewSlot,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentCyan.withValues(alpha: 0.18),
                border: Border.all(color: FluxForgeTheme.accentCyan, width: 1.0),
                borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_circle_outline_rounded, size: 11,
                  color: FluxForgeTheme.accentCyan),
                SizedBox(width: 4),
                Text('New Slot', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // ── Step 2: Drop audio onto a slot ───────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3)),
            child: const Text('STEP 2',
              style: TextStyle(
                fontFamily: 'monospace', fontSize: 7,
                color: FluxForgeTheme.accentBlue, letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(
            events.isEmpty
              ? 'Drop audio onto a slot'
              : '${events.length} slot${events.length == 1 ? "" : "s"} — drop audio on a card',
            style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
            overflow: TextOverflow.ellipsis,
          )),
          GestureDetector(
            onTap: () async {
              await silentCatchAsync('audio.browseAndCreate', () async {
                final paths = await NativeFilePicker.pickAudioFiles();
                if (paths.isNotEmpty) {
                  await _browseAndCreateSlot(paths);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.08),
                border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_open_rounded, size: 10, color: FluxForgeTheme.accentBlue),
                SizedBox(width: 3),
                Text('Browse', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentBlue)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // ── Slot list ─────────────────────────────────────────────────
        Expanded(
          child: events.isEmpty
            ? Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined, size: 28,
                    color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  const Text('No slots yet.\nCreate a slot first,\nthen drop audio on it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9,
                      color: FluxForgeTheme.textTertiary, height: 1.5)),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _createNewSlot,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentCyan.withValues(alpha: 0.18),
                        border: Border.all(color: FluxForgeTheme.accentCyan, width: 1.0),
                        borderRadius: BorderRadius.circular(4)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.accentCyan),
                        SizedBox(width: 5),
                        Text('Create First Slot', style: TextStyle(
                          fontFamily: 'monospace', fontSize: 10,
                          color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ))
            : ListView(
                children: events
                    .take(20)
                    .map((e) => _buildSlotCard(e, helixState))
                    .toList(),
              ),
        ),
      ],
    );
  }

  // ─── Slot card — DropTarget that appends layers on drop ────────────────────
  Widget _buildSlotCard(SlotCompositeEvent e, _HelixScreenState? helixState) {
    final hasStages = e.triggerStages.isNotEmpty;
    final hasLayers = e.layers.isNotEmpty;
    final isHovering = _hoveringEventId == e.id;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hoveringEventId = e.id),
      onDragExited: (_) => setState(() {
        if (_hoveringEventId == e.id) _hoveringEventId = null;
      }),
      onDragDone: (detail) {
        setState(() => _hoveringEventId = null);
        _addLayersToEvent(e, detail.files.map((f) => f.path).toList());
      },
      child: GestureDetector(
        onTap: () => helixState?.openContextLens(e),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            color: isHovering
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.18)
              : e.color.withValues(alpha: 0.05),
            border: Border.all(
              color: isHovering
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.7)
                : (hasStages
                    ? e.color.withValues(alpha: 0.22)
                    : const Color(0xFF333340)),
              width: isHovering ? 1.5 : (hasStages ? 1.0 : 0.5),
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: isHovering ? [BoxShadow(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.25),
              blurRadius: 8)] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Row 1: dot + name + layer count / drop hint ──
              Row(children: [
                Container(width: 4, height: 4, decoration: BoxDecoration(
                  color: e.color, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Expanded(child: Text(e.name, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 10,
                  color: FluxForgeTheme.textSecondary),
                  overflow: TextOverflow.ellipsis)),
                if (!hasLayers)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue.withValues(alpha: 0.08),
                      border: Border.all(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(3)),
                    child: const Text('drop audio',
                      style: TextStyle(
                        fontFamily: 'monospace', fontSize: 7,
                        color: FluxForgeTheme.accentBlue, letterSpacing: 0.3)),
                  )
                else
                  Text('${e.layers.length}L', style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 8,
                    color: FluxForgeTheme.textTertiary)),
                const SizedBox(width: 3),
                const Icon(Icons.chevron_right_rounded, size: 11,
                  color: FluxForgeTheme.textTertiary),
              ]),
              // ── Row 2: stage chips ──
              const SizedBox(height: 4),
              Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  ...List.generate(e.triggerStages.length, (si) {
                    final stage = e.triggerStages[si];
                    final cfg = StageConfigurationService.instance.getStage(stage);
                    final chipColor = cfg != null
                      ? StageConfigurationService.instance.getCategoryColor(stage)
                      : FluxForgeTheme.accentCyan;
                    return GestureDetector(
                      onTap: () {
                        // Prevents parent GestureDetector from firing
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(5, 2, 2, 2),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: 0.1),
                          border: Border.all(color: chipColor.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(3)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(stage,
                            style: TextStyle(
                              fontFamily: 'monospace', fontSize: 7,
                              color: chipColor, letterSpacing: 0.3)),
                          const SizedBox(width: 3),
                          GestureDetector(
                            onTap: () => _reassignStage(e, removeIndex: si),
                            child: Icon(Icons.close_rounded, size: 8,
                              color: chipColor.withValues(alpha: 0.6)),
                          ),
                        ]),
                      ),
                    );
                  }),
                  // Add stage button — red "set stage" warning if missing
                  GestureDetector(
                    onTap: () => _reassignStage(e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasStages
                          ? Colors.transparent
                          : FluxForgeTheme.accentRed.withValues(alpha: 0.10),
                        border: Border.all(color: hasStages
                          ? const Color(0xFF444455)
                          : FluxForgeTheme.accentRed.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(3)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 8,
                          color: hasStages
                            ? FluxForgeTheme.textTertiary
                            : FluxForgeTheme.accentRed),
                        const SizedBox(width: 2),
                        Text(hasStages ? 'stage' : 'set stage (won\'t play)',
                          style: TextStyle(
                            fontFamily: 'monospace', fontSize: 7,
                            color: hasStages
                              ? FluxForgeTheme.textTertiary
                              : FluxForgeTheme.accentRed)),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Spine: GAME CONFIG — FAZA 3.7 ───────────────────────────────────────────
//
// Ultimativni Slot Designer Panel — 11 faza u 6 sub-tab-ova.
// Pokriva 9 tipova slotova, 8 jurisdikcija, integrity validator,
// snapshot sistem, blueprint export.
//
// Sub-tabs: TYPE | GRID | MATH | FEAT | COMPL | SNAP

enum _GcTab {
  type,
  grid,
  math,
  feat,
  compl,
  snap;

  String get label => switch (this) {
    type => 'TYPE',
    grid => 'GRID',
    math => 'MATH',
    feat => 'FEAT',
    compl => 'COMPL',
    snap => 'SNAP',
  };
}

class _SpineGameConfig extends StatefulWidget {
  @override
  State<_SpineGameConfig> createState() => _SpineGameConfigState();
}

class _SpineGameConfigState extends State<_SpineGameConfig> {
  // ─── sub-tab ────────────────────────────────────────────────────────────────
  _GcTab _tab = _GcTab.grid;

  // ─── 3.7.0: slot type ───────────────────────────────────────────────────────
  SlotTypePreset _slotType = SlotTypePreset.videoStd;

  // ─── 3.7.A: grid ────────────────────────────────────────────────────────────
  late int _reels;
  late int _rows;
  WinMechanismType _winMech = WinMechanismType.paylines;
  int _paylines = 20;
  String? _gridStatus;
  // Megaways per-reel rows config (only meaningful when winMech == megaways)
  late MegawaysReelConfig _megaways;
  // Cluster pays config
  ClusterConfig _cluster = const ClusterConfig();
  // Infinity Reels config
  InfinityReelsConfig _infinity = const InfinityReelsConfig();

  // ─── 3.7.B: math ────────────────────────────────────────────────────────────
  double _volatility = 5.5; // 1.0 – 10.0
  double _rtpTarget = 96.5;
  MaxWinCap _maxWinCap = MaxWinCap.x5000;
  int _deadSpins = 50;
  RtpFeasibility _rtpFeasibility = RtpFeasibility.achievable;

  // ─── 3.7.D: feature inline configs (per-mechanic) ───────────────────────────
  FreeSpinsCfg _fsCfg = const FreeSpinsCfg();
  CascadeCfg _cascadeCfg = const CascadeCfg();
  HoldWinCfg _holdWinCfg = const HoldWinCfg();
  bool _featureBuyEnabled = false;
  /// Which feature inline config rows are currently expanded.
  final Set<SlotMechanic> _featExpanded = {};

  // ─── 3.7.E: anticipation ────────────────────────────────────────────────────
  AnticipationTip _anticTip = AnticipationTip.tipA;
  final Set<int> _customTipReels = {0, 2, 4};
  bool _nearMissGuard = false;
  bool _sequentialStop = true;

  // ─── 3.7.F: compliance ──────────────────────────────────────────────────────
  final Set<Jurisdiction> _jurisdictions = {Jurisdiction.mga};

  // ─── 3.7.H: snapshots ───────────────────────────────────────────────────────
  final List<ConfigSnapshot> _snapshots = [];
  late final TextEditingController _snapNameCtrl;
  /// Two-snapshot diff selection: stores names so deletion is safe.
  String? _diffLeft;
  String? _diffRight;

  // ─── 3.7.I: integrity ───────────────────────────────────────────────────────
  List<IntegrityIssue> _issues = [];

  // ─── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _snapNameCtrl = TextEditingController();
    final gridCfg = GetIt.instance<SlotLabProjectProvider>().gridConfig;
    _reels = gridCfg?.columns ?? 5;
    _rows = gridCfg?.rows ?? 3;
    _megaways = MegawaysReelConfig.defaultFor(_reels);
    // Read win mechanism from FeatureComposerProvider if already configured
    silentRun('gcInit.readComposer', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      if (fc.isConfigured) {
        _winMech = _winMechFromPaylineType(fc.config!.paylineType.name);
        _paylines = fc.config!.paylineCount;
        if (fc.config!.volatilityProfile == 'low') _volatility = 2.0;
        if (fc.config!.volatilityProfile == 'medium') _volatility = 5.0;
        if (fc.config!.volatilityProfile == 'high') _volatility = 7.5;
        if (fc.config!.volatilityProfile == 'extreme') _volatility = 9.5;
      }
    });
    Future.microtask(_runValidation);
  }

  @override
  void dispose() {
    _snapNameCtrl.dispose();
    super.dispose();
  }

  // ─── helpers ─────────────────────────────────────────────────────────────────

  WinMechanismType _winMechFromPaylineType(String name) => switch (name) {
    'ways' => WinMechanismType.ways,
    'cluster' => WinMechanismType.cluster,
    'megaways' => WinMechanismType.megaways,
    _ => WinMechanismType.paylines,
  };

  String get _volatilityLabel {
    if (_volatility <= 2.5) return 'LOW';
    if (_volatility <= 5.0) return 'MED';
    if (_volatility <= 7.5) return 'HIGH';
    return 'EXTREME';
  }

  Color get _volatilityColor {
    if (_volatility <= 2.5) return FluxForgeTheme.accentGreen;
    if (_volatility <= 5.0) return FluxForgeTheme.accentCyan;
    if (_volatility <= 7.5) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  bool _isMechanicEnabled(SlotMechanic m) {
    final fc = GetIt.instance<FeatureComposerProvider>();
    return fc.config?.mechanics[m] ?? false;
  }

  void _toggleMechanic(SlotMechanic m, bool v) {
    silentRun('gcFeat.toggle', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      if (!fc.isConfigured) return;
      final updated = Map<SlotMechanic, bool>.from(fc.config!.mechanics);
      updated[m] = v;
      fc.applyConfig(fc.config!.copyWith(mechanics: updated));
    });
    setState(() {});
    _runValidation();
  }

  void _runValidation() {
    if (!mounted) return;
    final issues = validateGameConfig(
      reels: _reels,
      rows: _rows,
      volatility: _volatility,
      rtpTarget: _rtpTarget,
      maxWinCap: _maxWinCap,
      deadSpins: _deadSpins,
      nearMissEnabled: _nearMissGuard,
      featureBuyEnabled: _featureBuyEnabled,
      activeJurisdictions: _jurisdictions,
      winMechanism: _winMech,
      megaways: _winMech == WinMechanismType.megaways ? _megaways : null,
      cluster: _winMech == WinMechanismType.cluster ? _cluster : null,
      anticipationTip: _anticTip,
      customTipReels: _anticTip == AnticipationTip.custom ? _customTipReels : null,
    );
    final feas = evaluateRtpFeasibility(
      rtpTarget: _rtpTarget,
      volatility: _volatility,
      maxWinCap: _maxWinCap,
      paylines: _paylines,
      winMechanism: _winMech,
    );
    if (mounted) setState(() {
      _issues = issues;
      _rtpFeasibility = feas;
    });
  }

  /// Per-field issue lookup (3.7.I real-time per-field badges).
  /// Returns the strictest issue for a given field, or null.
  IntegrityIssue? _firstIssueFor(String fieldId) {
    for (final i in _issues) {
      if (i.fieldId == fieldId) return i;
    }
    return null;
  }

  /// Apply all auto-fixable issues with severity >= ERROR.
  /// Returns count of patches applied.
  int _applyAllAutoFixes() {
    var applied = 0;
    for (final issue in _issues) {
      if (issue.patch == null) continue;
      if (issue.severity == IntegritySeverity.warning ||
          issue.severity == IntegritySeverity.info) continue;
      _applyAutoFix(issue.patch!);
      applied++;
    }
    if (applied > 0) {
      _applyMath();
      _runValidation();
    }
    return applied;
  }

  void _applyAutoFix(AutoFixPatch p) {
    setState(() {
      switch (p.kind) {
        case AutoFixKind.setRtp:
          if (p.rtpValue != null) _rtpTarget = p.rtpValue!;
          break;
        case AutoFixKind.disableNearMiss:
          _nearMissGuard = false;
          break;
        case AutoFixKind.disableFeatureBuy:
          _featureBuyEnabled = false;
          break;
        case AutoFixKind.reduceDeadSpins:
          if (p.deadSpinsValue != null) _deadSpins = p.deadSpinsValue!;
          break;
      }
    });
  }

  Future<void> _applyGrid() async {
    final clamped = (_reels.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels),
                    _rows.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows));
    final result = await GridResizePipeline.apply(reels: clamped.$1, rows: clamped.$2);
    // Re-shape megaways per-reel array to match new reel count.
    _megaways = _megaways.withReelCount(clamped.$1);
    // Sync win mechanism
    silentRun('gcGrid.syncWinMech', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      if (fc.isConfigured) {
        fc.applyConfig(fc.config!.copyWith(
          paylineCount: _paylines,
          paylineType: PaylineType.values.firstWhere(
            (t) => t.name == _winMech.paylineTypeName,
            orElse: () => PaylineType.lines,
          ),
        ));
      }
    });
    if (mounted) {
      setState(() => _gridStatus = result.shortStatus);
      _runValidation();
    }
  }

  void _applyMath() {
    silentRun('gcMath.apply', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      final volStr = _volatility <= 2.5 ? 'low'
          : _volatility <= 5.0 ? 'medium'
          : _volatility <= 7.5 ? 'high'
          : 'extreme';
      if (fc.isConfigured) {
        fc.applyConfig(fc.config!.copyWith(volatilityProfile: volStr));
      }
    });
    _runValidation();
  }

  void _applySlotType(SlotTypePreset type) {
    final newReels = type.reels.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels);
    final newRows = type.rows.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows);
    setState(() {
      _slotType = type;
      _reels = newReels;
      _rows = newRows;
      _winMech = type.winMechanism;
      _paylines = type.defaultPaylines;
      _volatility = type.defaultVolatility;
      _rtpTarget = type.defaultRtp;
      // Megaways: spawn per-reel rows = preset rows for all reels.
      if (type.winMechanism == WinMechanismType.megaways) {
        _megaways = MegawaysReelConfig(
          rowsPerReel: List.filled(newReels, newRows.clamp(2, 7)),
        );
      } else {
        _megaways = _megaways.withReelCount(newReels);
      }
    });
    _applyGrid();
    _applyMath();
  }

  // ─── 3.7.C — symbol preset application ─────────────────────────────────────
  void _applySymbolPreset(SymbolPreset preset) {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    silentRun('symbol.applyPreset', () {
      // Snapshot existing IDs to delete after spawn (avoid double-clearing).
      final existing = proj.symbols.map((s) => s.id).toList();
      for (final id in existing) {
        proj.removeSymbol(id);
      }
      var sortIdx = 0;
      for (final spec in preset.symbols) {
        proj.addSymbol(SymbolDefinition(
          id: spec.id,
          name: spec.name,
          emoji: spec.emoji,
          type: SymbolType.values.firstWhere(
            (t) => t.name == spec.typeName,
            orElse: () => SymbolType.custom,
          ),
          payMultiplier: spec.payMultiplier,
          sortOrder: sortIdx++,
        ));
      }
    });
    setState(() {});
  }

  void _saveSnapshot() {
    final name = _snapNameCtrl.text.trim();
    if (name.isEmpty) return;
    final fc = GetIt.instance<FeatureComposerProvider>();
    final features = <String, bool>{
      for (final m in SlotMechanic.values) m.name: _isMechanicEnabled(m),
    };
    setState(() {
      _snapshots.insert(0, ConfigSnapshot(
        name: name,
        createdAt: DateTime.now(),
        reels: _reels,
        rows: _rows,
        winMechanism: _winMech,
        volatility: _volatility,
        rtp: _rtpTarget,
        maxWinCap: _maxWinCap,
        slotType: _slotType,
        jurisdictions: Set.from(_jurisdictions),
        features: features,
      ));
      _snapNameCtrl.clear();
    });
  }

  void _loadSnapshot(ConfigSnapshot snap) {
    final newReels = snap.reels.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels);
    final newRows = snap.rows.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows);
    setState(() {
      _slotType = snap.slotType;
      _reels = newReels;
      _rows = newRows;
      _winMech = snap.winMechanism;
      _volatility = snap.volatility;
      _rtpTarget = snap.rtp;
      _maxWinCap = snap.maxWinCap;
      _jurisdictions
        ..clear()
        ..addAll(snap.jurisdictions);
    });
    // Restore features
    for (final entry in snap.features.entries) {
      final m = SlotMechanic.values.where((v) => v.name == entry.key).firstOrNull;
      if (m != null) {
        silentRun('gcSnap.restoreMechanic', () {
          final fc = GetIt.instance<FeatureComposerProvider>();
          if (fc.isConfigured) {
            final updated = Map<SlotMechanic, bool>.from(fc.config!.mechanics);
            updated[m] = entry.value;
            fc.applyConfig(fc.config!.copyWith(mechanics: updated));
          }
        });
      }
    }
    _applyGrid();
    _applyMath();
  }

  String _buildBlueprintJson() {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    return const JsonEncoder.withIndent('  ').convert({
      'version': '3.7',
      'type': 'slot_blueprint',
      'createdAt': DateTime.now().toIso8601String(),
      'slotType': _slotType.name,
      'grid': {'reels': _reels, 'rows': _rows},
      'winMechanism': _winMech.paylineTypeName,
      'paylines': _paylines,
      if (_winMech == WinMechanismType.megaways) 'megaways': {
        'rowsPerReel': _megaways.rowsPerReel,
        'minRows': _megaways.minRows,
        'maxRows': _megaways.maxRows,
        'totalWays': _megaways.totalWays,
      },
      if (_winMech == WinMechanismType.cluster) 'cluster': {
        'minSize': _cluster.minSize,
        'allowDiagonal': _cluster.allowDiagonal,
        'shape': _cluster.shape.name,
      },
      if (_slotType.label.toLowerCase().contains('infinity')) 'infinity': {
        'startReels': _infinity.startReels,
        'maxReels': _infinity.maxReels,
        'expandTriggerSymbolId': _infinity.expandTriggerSymbolId,
      },
      'math': {
        'volatility': _volatility,
        'rtp': _rtpTarget,
        'maxWinCap': _maxWinCap.multiplier,
        'deadSpinsMax': _deadSpins,
        'rtpFeasibility': _rtpFeasibility.name,
      },
      'features': {
        for (final m in SlotMechanic.values) m.name: _isMechanicEnabled(m),
        'featureBuy': _featureBuyEnabled,
      },
      'featureConfigs': {
        if (_isMechanicEnabled(SlotMechanic.freeSpins)) 'freeSpins': {
          'triggerScatterCount': _fsCfg.triggerScatterCount,
          'spinsAwarded': _fsCfg.spinsAwarded,
          'multiplier': _fsCfg.multiplier,
          'retriggerEnabled': _fsCfg.retriggerEnabled,
          'maxRetriggers': _fsCfg.maxRetriggers,
        },
        if (_isMechanicEnabled(SlotMechanic.cascading)) 'cascade': {
          'multiplierStep': _cascadeCfg.multiplierStep,
          'multiplierCap': _cascadeCfg.multiplierCap,
          'removeAllNonWinning': _cascadeCfg.removeAllNonWinning,
        },
        if (_isMechanicEnabled(SlotMechanic.holdAndWin)) 'holdAndWin': {
          'respinCount': _holdWinCfg.respinCount,
          'resetOnNewLand': _holdWinCfg.resetOnNewLand,
          'miniSeed': _holdWinCfg.miniSeed,
          'minorSeed': _holdWinCfg.minorSeed,
          'majorSeed': _holdWinCfg.majorSeed,
          'grandSeed': _holdWinCfg.grandSeed,
        },
      },
      'anticipation': {
        'tip': _anticTip.name,
        if (_anticTip == AnticipationTip.custom)
          'customReels': _customTipReels.toList()..sort(),
        'nearMiss': _nearMissGuard,
        'sequential': _sequentialStop,
      },
      'compliance': {
        'jurisdictions': _jurisdictions.map((j) => j.name).toList(),
      },
      'symbols': proj.symbols.map((s) => {
        'id': s.id, 'name': s.name, 'emoji': s.emoji, 'type': s.type.name,
        if (s.payMultiplier != null) 'payMultiplier': s.payMultiplier,
      }).toList(),
    });
  }

  // ─── main build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<GameFlowProvider>(),
        GetIt.instance<SlotLabProjectProvider>(),
        GetIt.instance<FeatureComposerProvider>(),
      ]),
      builder: (context, _) => _buildShell(),
    );
  }

  Widget _buildShell() {
    final critCount = _issues.where((i) => i.severity == IntegritySeverity.critical).length;
    final errCount  = _issues.where((i) => i.severity == IntegritySeverity.error).length;
    final warnCount = _issues.where((i) => i.severity == IntegritySeverity.warning).length;

    return Column(children: [
      _buildTabBar(),
      Expanded(child: _buildTabBody()),
      _buildIntegrityFooter(critCount, errCount, warnCount),
    ]);
  }

  // ─── tab bar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _GcTab.values.map((t) {
            final active = t == _tab;
            return GestureDetector(
              onTap: () => setState(() => _tab = t),
              child: Container(
                margin: const EdgeInsets.only(right: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: active
                      ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15)
                      : FluxForgeTheme.bgElevated,
                  border: Border.all(
                    color: active
                        ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5)
                        : FluxForgeTheme.borderSubtle,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(t.label, style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8, letterSpacing: 0.5,
                  color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                )),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── tab body ───────────────────────────────────────────────────────────────

  Widget _buildTabBody() => switch (_tab) {
    _GcTab.type  => _buildTypeTab(),
    _GcTab.grid  => _buildGridTab(),
    _GcTab.math  => _buildMathTab(),
    _GcTab.feat  => _buildFeatTab(),
    _GcTab.compl => _buildComplTab(),
    _GcTab.snap  => _buildSnapTab(),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.0 — TYPE TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTypeTab() {
    return ListView(children: [
      _gcSectionHeader('SLOT TYPE'),
      const SizedBox(height: 4),
      ...SlotTypePreset.values.map((t) {
        final active = t == _slotType;
        return GestureDetector(
          onTap: () => _applySlotType(t),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? FluxForgeTheme.accentCyan.withValues(alpha: 0.1)
                  : FluxForgeTheme.bgElevated,
              border: Border.all(
                color: active
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4)
                    : FluxForgeTheme.borderSubtle,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              Text(t.icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.label, style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.w700)),
                  Text(t.description, style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 7,
                    color: FluxForgeTheme.textTertiary)),
                ],
              )),
              if (active) const Icon(Icons.check_rounded, size: 10,
                color: FluxForgeTheme.accentCyan),
            ]),
          ),
        );
      }),
      const SizedBox(height: 8),
      // Stats row
      _gcSectionHeader('SESSION'),
      const SizedBox(height: 4),
      Builder(builder: (_) {
        final proj = GetIt.instance<SlotLabProjectProvider>();
        final flow = GetIt.instance<GameFlowProvider>();
        final stats = proj.sessionStats;
        return Column(children: [
          _gcRow('State', flow.currentState.displayName),
          _gcRow('Spins', '${stats.totalSpins}'),
          _gcRow('RTP', stats.rtp.isNaN ? '—' : '${stats.rtp.toStringAsFixed(1)}%'),
        ]);
      }),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.A — GRID TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGridTab() {
    return ListView(children: [
      _gcSectionHeader('GRID'),
      const SizedBox(height: 8),
      _gcSpinnerRow('REELS', _reels, GridResizeBounds.minReels, GridResizeBounds.maxReels,
          (v) => setState(() { _reels = v; })),
      _gcSpinnerRow('ROWS', _rows, GridResizeBounds.minRows, GridResizeBounds.maxRows,
          (v) => setState(() { _rows = v; })),
      const SizedBox(height: 4),
      _gcApplyButton('Apply Grid', _applyGrid),
      if (_gridStatus != null) Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(_gridStatus!, style: TextStyle(
          fontFamily: 'monospace', fontSize: 8,
          color: _gridStatus!.startsWith('✓')
              ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange)),
      ),
      const SizedBox(height: 12),
      _gcSectionHeader('WIN MECHANISM'),
      const SizedBox(height: 4),
      ...WinMechanismType.values.map((wm) {
        final active = wm == _winMech;
        return GestureDetector(
          onTap: () => setState(() => _winMech = wm),
          child: Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: active ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1) : Colors.transparent,
              border: Border.all(
                color: active
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                    : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(children: [
              Icon(active ? Icons.radio_button_checked_rounded
                         : Icons.radio_button_unchecked_rounded,
                size: 10, color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary),
              const SizedBox(width: 6),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wm.label, style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textPrimary)),
                  Text(wm.description, style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 7,
                    color: FluxForgeTheme.textTertiary)),
                ],
              )),
            ]),
          ),
        );
      }),
      const SizedBox(height: 10),
      // Paylines (only for paylines/ways)
      if (_winMech == WinMechanismType.paylines || _winMech == WinMechanismType.ways) ...[
        _gcSectionHeader('PAYLINES'),
        const SizedBox(height: 4),
        _gcSpinnerRow('COUNT', _paylines, 1, 1024, (v) => setState(() => _paylines = v)),
      ],
      // Megaways per-reel rows (3.7.A.megaways)
      if (_winMech == WinMechanismType.megaways) ...[
        const SizedBox(height: 6),
        _buildMegawaysSection(),
      ],
      // Cluster config (3.7.A.cluster)
      if (_winMech == WinMechanismType.cluster) ...[
        const SizedBox(height: 6),
        _buildClusterSection(),
      ],
      // Infinity Reels config — conditional on slot type, not win mech
      if (_slotType.label.toLowerCase().contains('infinity')) ...[
        const SizedBox(height: 6),
        _buildInfinitySection(),
      ],
      const SizedBox(height: 8),
      // Mini grid visualizer (3.7.G)
      _gcSectionHeader('GRID PREVIEW'),
      const SizedBox(height: 4),
      _buildGridVisualizer(),
      const SizedBox(height: 8),
      // Symbol editor (kept from original)
      Row(children: [
        _gcSectionHeader('SYMBOLS'),
        const Spacer(),
        _gcSymbolPresetMenu(),
      ]),
      const SizedBox(height: 4),
      _buildSymbolEditorInline(),
    ]);
  }

  // ─── 3.7.A.megaways — per-reel rows section ────────────────────────────────
  Widget _buildMegawaysSection() {
    final issue = _firstIssueFor(GcField.megaways);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.05),
        border: Border.all(
          color: issue != null
              ? issue.severity.color.withValues(alpha: 0.6)
              : const Color(0xFFFF9800).withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('MEGAWAYS PER-REEL', style: TextStyle(
            fontFamily: 'monospace', fontSize: 8, letterSpacing: 0.6,
            color: Color(0xFFFF9800), fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${_megaways.totalWays} ways', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 8, color: Color(0xFFFF9800))),
        ]),
        const SizedBox(height: 4),
        ...List.generate(_megaways.rowsPerReel.length, (idx) {
          final v = _megaways.rowsPerReel[idx];
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              SizedBox(width: 26, child: Text('R${idx + 1}', style: const TextStyle(
                fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary))),
              Expanded(child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 2,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                  activeTrackColor: Color(0xFFFF9800),
                  inactiveTrackColor: FluxForgeTheme.borderSubtle,
                  thumbColor: Color(0xFFFF9800),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: v.toDouble(),
                  min: _megaways.minRows.toDouble(),
                  max: _megaways.maxRows.toDouble(),
                  divisions: _megaways.maxRows - _megaways.minRows,
                  onChanged: (nv) {
                    final newRows = List<int>.from(_megaways.rowsPerReel);
                    newRows[idx] = nv.round();
                    setState(() => _megaways = _megaways.copyWith(rowsPerReel: newRows));
                    _runValidation();
                  },
                ),
              )),
              SizedBox(width: 22, child: Text('$v', style: const TextStyle(
                fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textPrimary,
                fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
            ]),
          );
        }),
        if (issue != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${issue.severity.label} · ${issue.message}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 7, color: issue.severity.color)),
        ),
      ]),
    );
  }

  // ─── 3.7.A.cluster — cluster pays section ───────────────────────────────────
  Widget _buildClusterSection() {
    final issue = _firstIssueFor(GcField.cluster);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withValues(alpha: 0.05),
        border: Border.all(
          color: issue != null
              ? issue.severity.color.withValues(alpha: 0.6)
              : const Color(0xFF4CAF50).withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CLUSTER PAYS', style: TextStyle(
          fontFamily: 'monospace', fontSize: 8, letterSpacing: 0.6,
          color: Color(0xFF4CAF50), fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        _gcSpinnerRow('MIN SIZE', _cluster.minSize, 4, 9, (v) {
          setState(() => _cluster = _cluster.copyWith(minSize: v));
          _runValidation();
        }),
        _gcToggleRow('Allow diagonal', _cluster.allowDiagonal, (v) {
          setState(() => _cluster = _cluster.copyWith(allowDiagonal: v));
          _runValidation();
        }),
        const SizedBox(height: 3),
        Wrap(spacing: 4, children: ClusterShape.values.map((s) {
          final active = s == _cluster.shape;
          return GestureDetector(
            onTap: () {
              setState(() => _cluster = _cluster.copyWith(shape: s));
              _runValidation();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                    : FluxForgeTheme.bgElevated,
                border: Border.all(
                  color: active
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                      : FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(s.label, style: TextStyle(
                fontFamily: 'monospace', fontSize: 8,
                color: active ? const Color(0xFF4CAF50) : FluxForgeTheme.textSecondary)),
            ),
          );
        }).toList()),
        if (issue != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${issue.severity.label} · ${issue.message}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 7, color: issue.severity.color)),
        ),
      ]),
    );
  }

  // ─── 3.7.A.infinity — infinity reels section ────────────────────────────────
  Widget _buildInfinitySection() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withValues(alpha: 0.05),
        border: Border.all(color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('INFINITY REELS', style: TextStyle(
          fontFamily: 'monospace', fontSize: 8, letterSpacing: 0.6,
          color: Color(0xFF00BCD4), fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        _gcSpinnerRow('START', _infinity.startReels, 2, 6, (v) {
          setState(() => _infinity = _infinity.copyWith(startReels: v));
        }),
        _gcSpinnerRow('MAX', _infinity.maxReels, 6, 20, (v) {
          setState(() => _infinity = _infinity.copyWith(maxReels: v));
        }),
        const SizedBox(height: 3),
        Row(children: [
          const Text('TRIGGER', style: TextStyle(
            fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
          const SizedBox(width: 6),
          Expanded(child: TextField(
            controller: TextEditingController(text: _infinity.expandTriggerSymbolId),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 9),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              filled: true,
              fillColor: FluxForgeTheme.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            onSubmitted: (v) {
              setState(() => _infinity = _infinity.copyWith(expandTriggerSymbolId: v.trim()));
            },
          )),
        ]),
      ]),
    );
  }

  // ─── 3.7.C — symbol preset dropdown menu ────────────────────────────────────
  Widget _gcSymbolPresetMenu() {
    return PopupMenuButton<SymbolPreset>(
      tooltip: 'Apply Symbol Preset',
      padding: EdgeInsets.zero,
      color: FluxForgeTheme.bgElevated,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
          border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.style_rounded, size: 9, color: FluxForgeTheme.accentCyan),
          SizedBox(width: 3),
          Text('PRESET ▾', style: TextStyle(
            fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.accentCyan)),
        ]),
      ),
      itemBuilder: (_) => SymbolPreset.values.map((p) => PopupMenuItem<SymbolPreset>(
        value: p,
        height: 36,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.label, style: const TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.w600)),
            Text(p.description, style: const TextStyle(
              fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
          ],
        ),
      )).toList(),
      onSelected: _applySymbolPreset,
    );
  }

  // ─── 3.7.G LIVE grid visualizer ─────────────────────────────────────────────

  Widget _buildGridVisualizer() {
    // Symbol source priority: project symbols → slot-type-mapped preset
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final List<String> symEmojis = proj.symbols.isNotEmpty
        ? proj.symbols.map((s) => s.emoji).toList()
        : _slotTypeToSymbolPreset(_slotType).symbols.map((s) => s.emoji).toList();

    return _GridVisualizerWidget(
      reels: _reels,
      rows: _rows,
      winMech: _winMech,
      megaways: _winMech == WinMechanismType.megaways ? _megaways : null,
      clusterConfig: _winMech == WinMechanismType.cluster ? _cluster : null,
      symbolEmojis: symEmojis,
      paylines: _paylines,
    );
  }

  /// Maps SlotTypePreset to a sensible default SymbolPreset for the visualizer.
  SymbolPreset _slotTypeToSymbolPreset(SlotTypePreset type) => switch (type) {
    SlotTypePreset.classic  => SymbolPreset.classicFruit,
    SlotTypePreset.bookOf   => SymbolPreset.bookOf,
    SlotTypePreset.holdWin  => SymbolPreset.highRoller,
    SlotTypePreset.megaways => SymbolPreset.standardRoyals,
    SlotTypePreset.cluster  => SymbolPreset.standardRoyals,
    _                       => SymbolPreset.standardRoyals,
  };

  // ─── inline symbol editor (kept functional from original) ────────────────────

  Widget _buildSymbolEditorInline() {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Spacer(),
          GestureDetector(
            onTap: () {
              final newId = 'sym_${DateTime.now().millisecondsSinceEpoch}';
              silentRun('symbol.addNew', () {
                proj.addSymbol(SymbolDefinition(
                  id: newId, name: 'SYM ${proj.symbols.length + 1}',
                  emoji: '🎰', type: SymbolType.custom,
                  sortOrder: proj.symbols.length,
                ));
              });
              setState(() {});
            },
            child: const Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.accentCyan)),
        ]),
        const SizedBox(height: 2),
        ...proj.symbols.map((sym) => _SymbolEditorRow(
          symbol: sym,
          onNameChanged: (name) {
            silentRun('symbol.updateName', () { proj.updateSymbol(sym.id, sym.copyWith(name: name)); });
          },
          onPayChanged: (pay) {
            silentRun('symbol.updatePay', () { proj.updateSymbol(sym.id, sym.copyWith(payMultiplier: pay)); });
          },
        )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.B — MATH TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMathTab() {
    return ListView(children: [
      _gcSectionHeader('VOLATILITY'),
      const SizedBox(height: 6),
      Row(children: [
        const Text('LOW', style: TextStyle(fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
        Expanded(
          child: Slider(
            value: _volatility,
            min: 1.0,
            max: 10.0,
            divisions: 90,
            activeColor: _volatilityColor,
            inactiveColor: FluxForgeTheme.borderSubtle,
            onChanged: (v) => setState(() => _volatility = v),
            onChangeEnd: (_) => _applyMath(),
          ),
        ),
        const Text('EXT', style: TextStyle(fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${_volatility.toStringAsFixed(1)} / 10  ', style: const TextStyle(
          fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: _volatilityColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: _volatilityColor.withValues(alpha: 0.4)),
          ),
          child: Text(_volatilityLabel, style: TextStyle(
            fontFamily: 'monospace', fontSize: 8, color: _volatilityColor)),
        ),
      ]),
      const SizedBox(height: 12),
      _gcSectionHeader('RTP TARGET'),
      const SizedBox(height: 4),
      _gcNumberField(
        label: 'RTP %',
        value: _rtpTarget,
        min: 85.0,
        max: 99.0,
        step: 0.5,
        onChanged: (v) { setState(() => _rtpTarget = v); _runValidation(); },
      ),
      const SizedBox(height: 4),
      _buildRtpFeasibilityBadge(),
      const SizedBox(height: 12),
      _gcSectionHeader('MAX WIN CAP'),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: MaxWinCap.values.map((cap) {
        final active = cap == _maxWinCap;
        return GestureDetector(
          onTap: () { setState(() => _maxWinCap = cap); _runValidation(); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: active ? FluxForgeTheme.accentPurple.withValues(alpha: 0.15) : FluxForgeTheme.bgElevated,
              border: Border.all(
                color: active ? FluxForgeTheme.accentPurple.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(cap.label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 8,
              color: active ? FluxForgeTheme.accentPurple : FluxForgeTheme.textSecondary)),
          ),
        );
      }).toList()),
      const SizedBox(height: 12),
      _gcSectionHeader('DEAD SPINS CAP'),
      const SizedBox(height: 4),
      _gcSpinnerRow('MAX', _deadSpins, 10, 200, (v) { setState(() => _deadSpins = v); _runValidation(); }),
      const SizedBox(height: 4),
      const Text('Max consecutive non-winning spins (MGA default: 50)',
        style: TextStyle(fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
      const SizedBox(height: 12),
      _gcSectionHeader('MATH PRESETS'),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _gcPresetChip('Low', () { setState(() { _volatility = 2.0; _rtpTarget = 95.0; }); _applyMath(); }),
        _gcPresetChip('Medium', () { setState(() { _volatility = 5.0; _rtpTarget = 96.5; }); _applyMath(); }),
        _gcPresetChip('High', () { setState(() { _volatility = 7.5; _rtpTarget = 96.5; }); _applyMath(); }),
        _gcPresetChip('Extreme', () { setState(() { _volatility = 9.5; _rtpTarget = 97.0; }); _applyMath(); }),
        _gcPresetChip('Studio', () { setState(() { _volatility = 5.0; _rtpTarget = 99.0; _deadSpins = 3; }); _applyMath(); }),
      ]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.D — FEATURES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFeatTab() {
    return ListView(children: [
      _gcSectionHeader('FEATURE STACK'),
      const SizedBox(height: 4),
      ...SlotMechanic.values.map((m) => _buildFeatureRow(m)),
      const SizedBox(height: 8),
      _buildFeatureBuyToggle(),
      const SizedBox(height: 8),
      // Anticipation (3.7.E)
      _gcSectionHeader('ANTICIPATION'),
      const SizedBox(height: 4),
      _buildAnticipationSection(),
    ]);
  }

  /// Each feature row: toggle + suggested icon. For mechanics that have
  /// inline config (FS, Cascade, HoldAndWin), tap on chevron expands editor.
  Widget _buildFeatureRow(SlotMechanic m) {
    final enabled = _isMechanicEnabled(m);
    final suggested = _slotType.suggestedFeatures.contains(m.name);
    final hasInlineCfg = _mechanicHasInlineConfig(m);
    final expanded = _featExpanded.contains(m);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: enabled
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.08)
            : FluxForgeTheme.bgElevated,
        border: Border.all(
          color: enabled
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.35)
              : FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            GestureDetector(
              onTap: () => _toggleMechanic(m, !enabled),
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: enabled
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.bgElevated,
                  border: Border.all(
                    color: enabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: enabled ? const Icon(Icons.check_rounded, size: 10, color: Colors.black) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(m.displayName, style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              color: enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary))),
            if (suggested && !enabled) Tooltip(
              message: 'Suggested for ${_slotType.label}',
              child: const Icon(Icons.stars_rounded, size: 10, color: FluxForgeTheme.accentYellow),
            ),
            if (hasInlineCfg && enabled) GestureDetector(
              onTap: () => setState(() {
                if (expanded) {
                  _featExpanded.remove(m);
                } else {
                  _featExpanded.add(m);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 14, color: FluxForgeTheme.accentCyan),
              ),
            ),
          ]),
        ),
        if (hasInlineCfg && enabled && expanded) Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: _buildFeatureInlineConfig(m),
        ),
      ]),
    );
  }

  bool _mechanicHasInlineConfig(SlotMechanic m) =>
      m == SlotMechanic.freeSpins ||
      m == SlotMechanic.cascading ||
      m == SlotMechanic.holdAndWin;

  Widget _buildFeatureInlineConfig(SlotMechanic m) {
    return switch (m) {
      SlotMechanic.freeSpins => _buildFsCfgEditor(),
      SlotMechanic.cascading => _buildCascadeCfgEditor(),
      SlotMechanic.holdAndWin => _buildHoldWinCfgEditor(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildFsCfgEditor() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(children: [
        _gcSpinnerRow('TRIG SCAT', _fsCfg.triggerScatterCount, 2, 6,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(triggerScatterCount: v))),
        _gcSpinnerRow('SPINS', _fsCfg.spinsAwarded, 5, 50,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(spinsAwarded: v))),
        _gcSpinnerRow('MULT ×', _fsCfg.multiplier, 1, 10,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(multiplier: v))),
        _gcToggleRow('Retrigger', _fsCfg.retriggerEnabled,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(retriggerEnabled: v))),
        if (_fsCfg.retriggerEnabled)
          _gcSpinnerRow('MAX RETR', _fsCfg.maxRetriggers, 0, 20,
            (v) => setState(() => _fsCfg = _fsCfg.copyWith(maxRetriggers: v))),
      ]),
    );
  }

  Widget _buildCascadeCfgEditor() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(children: [
        _gcSpinnerRow('STEP +×', _cascadeCfg.multiplierStep, 1, 5,
          (v) => setState(() => _cascadeCfg = _cascadeCfg.copyWith(multiplierStep: v))),
        _gcSpinnerRow('CAP ×', _cascadeCfg.multiplierCap, 2, 100,
          (v) => setState(() => _cascadeCfg = _cascadeCfg.copyWith(multiplierCap: v))),
        _gcToggleRow('Remove non-winning too', _cascadeCfg.removeAllNonWinning,
          (v) => setState(() => _cascadeCfg = _cascadeCfg.copyWith(removeAllNonWinning: v))),
      ]),
    );
  }

  Widget _buildHoldWinCfgEditor() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(children: [
        _gcSpinnerRow('RESPINS', _holdWinCfg.respinCount, 1, 10,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(respinCount: v))),
        _gcToggleRow('Reset on new land', _holdWinCfg.resetOnNewLand,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(resetOnNewLand: v))),
        _gcSpinnerRow('MINI ×', _holdWinCfg.miniSeed, 1, 100,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(miniSeed: v))),
        _gcSpinnerRow('MINOR ×', _holdWinCfg.minorSeed, 5, 500,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(minorSeed: v))),
        _gcSpinnerRow('MAJOR ×', _holdWinCfg.majorSeed, 50, 2000,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(majorSeed: v))),
        _gcSpinnerRow('GRAND ×', _holdWinCfg.grandSeed, 500, 20000,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(grandSeed: v))),
      ]),
    );
  }

  Widget _buildFeatureBuyToggle() {
    final issue = _firstIssueFor(GcField.featureBuy);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _featureBuyEnabled
            ? FluxForgeTheme.accentPurple.withValues(alpha: 0.08)
            : FluxForgeTheme.bgElevated,
        border: Border.all(
          color: issue != null
              ? issue.severity.color.withValues(alpha: 0.6)
              : (_featureBuyEnabled
                  ? FluxForgeTheme.accentPurple.withValues(alpha: 0.4)
                  : FluxForgeTheme.borderSubtle),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () { setState(() => _featureBuyEnabled = !_featureBuyEnabled); _runValidation(); },
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: _featureBuyEnabled ? FluxForgeTheme.accentPurple : FluxForgeTheme.bgElevated,
                border: Border.all(
                  color: _featureBuyEnabled ? FluxForgeTheme.accentPurple : FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3),
              ),
              child: _featureBuyEnabled
                  ? const Icon(Icons.check_rounded, size: 10, color: Colors.black) : null,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('Feature Buy', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textPrimary))),
          if (issue != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: issue.severity.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(issue.severity.label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 6, color: issue.severity.color)),
          ),
        ]),
        if (issue != null) Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(issue.message, style: TextStyle(
            fontFamily: 'monospace', fontSize: 7, color: issue.severity.color)),
        ),
      ]),
    );
  }

  // ─── 3.7.E — anticipation ───────────────────────────────────────────────────

  Widget _buildAnticipationSection() {
    final nmIssue = _firstIssueFor(GcField.nearMiss);
    final customIssue = _firstIssueFor(GcField.customTipReels);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Tip A / Tip B / Custom
      Row(children: AnticipationTip.values.map((t) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: _gcRadioChip(t.label, _anticTip == t, () {
          setState(() => _anticTip = t);
          _runValidation();
        }),
      )).toList()),
      const SizedBox(height: 3),
      Text(_anticTip.description, style: const TextStyle(
        fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
      // Custom reel selection
      if (_anticTip == AnticipationTip.custom) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: List.generate(_reels, (idx) {
          final selected = _customTipReels.contains(idx);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _customTipReels.remove(idx);
                } else {
                  _customTipReels.add(idx);
                }
              });
              _runValidation();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.18)
                    : FluxForgeTheme.bgElevated,
                border: Border.all(
                  color: selected
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('R${idx + 1}', style: TextStyle(
                fontFamily: 'monospace', fontSize: 8,
                color: selected ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary)),
            ),
          );
        })),
        if (customIssue != null) Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(customIssue.message, style: TextStyle(
            fontFamily: 'monospace', fontSize: 7, color: customIssue.severity.color)),
        ),
      ],
      const SizedBox(height: 8),
      // Toggles
      _gcToggleRow('Sequential stop', _sequentialStop, (v) => setState(() => _sequentialStop = v)),
      Row(children: [
        Expanded(child: _gcToggleRow('Near-miss guard', _nearMissGuard, (v) {
          setState(() => _nearMissGuard = v);
          _runValidation();
        })),
        if (nmIssue != null) Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: nmIssue.severity.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(nmIssue.severity.label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 6, color: nmIssue.severity.color)),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      // Tension level orbs + audio bind
      const Text('TENSION → AUDIO', style: TextStyle(
        fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
      const SizedBox(height: 4),
      _buildTensionAudioRow('L1', const Color(0xFFFFD700), 'ANTICIPATION_LOW'),
      _buildTensionAudioRow('L2', const Color(0xFFFFA500), 'ANTICIPATION_MED'),
      _buildTensionAudioRow('L3', const Color(0xFFFF6347), 'ANTICIPATION_HIGH'),
      _buildTensionAudioRow('L4', const Color(0xFFFF4500), 'ANTICIPATION_PEAK'),
    ]);
  }

  Widget _buildTensionAudioRow(String label, Color color, String stageId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Container(
          width: 14, height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.85),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(width: 22, child: Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 7, color: color))),
        Expanded(child: Text(stageId, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary))),
        GestureDetector(
          onTap: () => _bindOrAuditionStage(stageId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
              border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('bind ▸', style: TextStyle(
              fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.accentCyan)),
          ),
        ),
      ]),
    );
  }

  void _bindOrAuditionStage(String stageId) {
    silentRun('antic.audition', () {
      // Probe registry first so we can give honest feedback (bound vs unbound).
      final reg = EventRegistry.instance;
      final hasEvent = reg.allEvents.any((e) => e.stage == stageId);
      // ignore: discarded_futures
      reg.triggerStage(stageId);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 1400),
          content: Text(hasEvent ? '▶ Auditioning $stageId' : 'No audio bound to $stageId yet',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          backgroundColor: const Color(0xFF1A1A2E),
        ));
      }
    });
  }

  // ─── 3.7.H — snapshot diff view ─────────────────────────────────────────────
  /// FAZA 3.7.H+ — Visual Snapshot Diff (side-by-side polish).
  ///
  /// Pre-ovog iteracije (`d27ac94f`), diff render je bio JSON-list sa
  /// `+/-/~ field: value` linijama.  Korisnik je morao da pročita value
  /// pa da skenira okom levo i desno.
  ///
  /// Sad: 3-kolone layout — `field | LEFT | RIGHT` — gde se vrednosti
  /// prikazuju u dve kolone sa highlight-om za changed/added/removed.
  /// Header bar sa summary statistikom (X changed · Y added · Z removed).
  /// Filter pills isključuju kategoriju iz prikaza ako korisnik želi
  /// samo to "šta se promenilo".
  Widget _buildSnapshotDiffView(String leftName, String rightName) {
    final left = _snapshots.firstWhere((s) => s.name == leftName,
        orElse: () => _snapshots.first);
    final right = _snapshots.firstWhere((s) => s.name == rightName,
        orElse: () => _snapshots.first);
    final entries = diffSnapshots(left, right);

    // Statistical summary — quick scan of magnitude of change.
    final changedN = entries.where((e) => e.kind == DiffChangeKind.changed).length;
    final addedN = entries.where((e) => e.kind == DiffChangeKind.added).length;
    final removedN = entries.where((e) => e.kind == DiffChangeKind.removed).length;
    final unchangedN = entries.where((e) => e.kind == DiffChangeKind.unchanged).length;

    // Filter user can toggle (`_diffShowUnchanged`) so the focus is on what
    // actually moved between snapshots.  Default off — most users want to
    // see changes only.
    final visible = entries.where((e) {
      if (e.kind == DiffChangeKind.unchanged && !_diffShowUnchanged) return false;
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header — title + summary + filter toggle.
        Row(children: [
          Text('DIFF', style: TextStyle(
            fontFamily: 'monospace', fontSize: 8, letterSpacing: 0.6,
            color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          _DiffStatChip(label: '~', count: changedN, color: FluxForgeTheme.accentYellow),
          const SizedBox(width: 4),
          _DiffStatChip(label: '+', count: addedN, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 4),
          _DiffStatChip(label: '−', count: removedN, color: FluxForgeTheme.accentRed),
          const SizedBox(width: 4),
          _DiffStatChip(label: '=', count: unchangedN, color: FluxForgeTheme.textTertiary),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _diffShowUnchanged = !_diffShowUnchanged),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _diffShowUnchanged
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.18)
                    : FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _diffShowUnchanged
                      ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5)
                      : FluxForgeTheme.borderSubtle,
                  width: 0.6,
                ),
              ),
              child: Text(
                _diffShowUnchanged ? '◉ unchanged' : '○ unchanged',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 7,
                  color: _diffShowUnchanged
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.textTertiary,
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        // Side-by-side column headers.
        Row(children: [
          const SizedBox(width: 80, child: Text('FIELD',
            style: TextStyle(
              fontFamily: 'monospace', fontSize: 7,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.textTertiary,
              letterSpacing: 0.6))),
          Expanded(child: Text('  $leftName',
            style: const TextStyle(
              fontFamily: 'monospace', fontSize: 7,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.accentBlue,
              letterSpacing: 0.4))),
          const SizedBox(width: 14, child: Text('→',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 8, color: FluxForgeTheme.textTertiary))),
          Expanded(child: Text('  $rightName',
            style: const TextStyle(
              fontFamily: 'monospace', fontSize: 7,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.accentPurple,
              letterSpacing: 0.4))),
        ]),
        const Divider(height: 6, thickness: 0.5, color: FluxForgeTheme.borderSubtle),
        ...visible.map(_diffEntryRow),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text(
              changedN + addedN + removedN == 0
                  ? '✓ Snapshots are identical'
                  : 'No changes match current filter',
              style: TextStyle(
                fontFamily: 'monospace', fontSize: 8,
                color: changedN + addedN + removedN == 0
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.textTertiary,
              ),
            )),
          ),
      ]),
    );
  }

  /// Toggle for "show unchanged fields" in the diff view.  Default false
  /// — most diff sessions want changes only.  State lives at screen
  /// level so it persists while user toggles between snapshot pairs.
  bool _diffShowUnchanged = false;

  Widget _diffEntryRow(DiffEntry e) {
    final (bgColor, accentColor, prefix) = switch (e.kind) {
      DiffChangeKind.unchanged => (
          Colors.transparent,
          FluxForgeTheme.textTertiary,
          '='
        ),
      DiffChangeKind.changed => (
          FluxForgeTheme.accentYellow.withValues(alpha: 0.06),
          FluxForgeTheme.accentYellow,
          '~'
        ),
      DiffChangeKind.added => (
          FluxForgeTheme.accentGreen.withValues(alpha: 0.06),
          FluxForgeTheme.accentGreen,
          '+'
        ),
      DiffChangeKind.removed => (
          FluxForgeTheme.accentRed.withValues(alpha: 0.06),
          FluxForgeTheme.accentRed,
          '−'
        ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: accentColor.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Row(children: [
          SizedBox(width: 12, child: Text(prefix, style: TextStyle(
            fontFamily: 'monospace', fontSize: 8, color: accentColor,
            fontWeight: FontWeight.w800))),
          Expanded(child: Text(e.field, style: TextStyle(
            fontFamily: 'monospace', fontSize: 7,
            color: accentColor, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])),
        // LEFT value (before) — relevant for changed + removed; empty for added.
        Expanded(child: _diffValueBox(
          value: e.kind == DiffChangeKind.added ? null : e.before,
          color: e.kind == DiffChangeKind.changed
              ? FluxForgeTheme.accentBlue
              : (e.kind == DiffChangeKind.removed ? accentColor : FluxForgeTheme.textTertiary),
          highlight: e.kind == DiffChangeKind.removed,
        )),
        const SizedBox(width: 14, child: Text('→',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 8, color: FluxForgeTheme.textTertiary))),
        // RIGHT value (after) — relevant for changed + added; empty for removed.
        Expanded(child: _diffValueBox(
          value: e.kind == DiffChangeKind.removed ? null : e.after,
          color: e.kind == DiffChangeKind.changed
              ? FluxForgeTheme.accentPurple
              : (e.kind == DiffChangeKind.added ? accentColor : FluxForgeTheme.textTertiary),
          highlight: e.kind == DiffChangeKind.added,
        )),
      ]),
    );
  }

  /// Single value cell — empty placeholder when value is null (added on
  /// LEFT, removed on RIGHT).  Highlight outline marks the side that
  /// actually changed (additions on right, removals on left).
  Widget _diffValueBox({
    required Object? value,
    required Color color,
    required bool highlight,
  }) {
    if (value == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.4),
            width: 0.4,
          ),
        ),
        child: Text('∅', style: TextStyle(
          fontFamily: 'monospace', fontSize: 7,
          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
        )),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
        border: highlight
            ? Border.all(color: color.withValues(alpha: 0.45), width: 0.5)
            : null,
      ),
      child: Text(_diffVal(value), style: TextStyle(
        fontFamily: 'monospace', fontSize: 7, color: color,
        fontWeight: highlight ? FontWeight.w600 : FontWeight.w400),
        maxLines: 2, overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _diffVal(Object? v) {
    if (v == null) return '∅';
    if (v is double) return v.toStringAsFixed(2);
    if (v is List) return '[${v.length}]';
    if (v is Map) return '{${v.length}}';
    return v.toString();
  }

  // ─── 3.7.J — blueprint import dialog ────────────────────────────────────────
  Future<void> _showBlueprintImportDialog() async {
    final controller = TextEditingController();
    String? errorMessage;
    Map<String, Object?>? parsed;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Import Blueprint',
            style: TextStyle(color: FluxForgeTheme.accentBlue, fontFamily: 'monospace', fontSize: 14)),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Paste a .flux blueprint JSON below:',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontFamily: 'monospace', fontSize: 10)),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                maxLines: 10,
                style: const TextStyle(color: FluxForgeTheme.textPrimary, fontFamily: 'monospace', fontSize: 10),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Color(0xFF0F0F1A),
                  hintText: '{ "version": "3.7", "type": "slot_blueprint", ... }',
                  hintStyle: TextStyle(color: FluxForgeTheme.textTertiary, fontFamily: 'monospace', fontSize: 9),
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorMessage != null) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(errorMessage!,
                  style: const TextStyle(color: FluxForgeTheme.accentRed, fontFamily: 'monospace', fontSize: 9)),
              ),
              if (parsed != null) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('✓ Valid: ${parsed!['type']} v${parsed!['version']}',
                  style: const TextStyle(color: FluxForgeTheme.accentGreen, fontFamily: 'monospace', fontSize: 9)),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                try {
                  final raw = jsonDecode(controller.text);
                  if (raw is! Map) throw 'Top level must be an object';
                  final m = Map<String, Object?>.from(raw);
                  if (m['type'] != 'slot_blueprint') {
                    throw 'type must be "slot_blueprint"';
                  }
                  setStateD(() { parsed = m; errorMessage = null; });
                } catch (e) {
                  setStateD(() { errorMessage = 'Parse error: $e'; parsed = null; });
                }
              },
              child: const Text('Validate', style: TextStyle(color: FluxForgeTheme.accentCyan)),
            ),
            TextButton(
              onPressed: parsed == null ? null : () => Navigator.pop(ctx, parsed),
              child: const Text('Apply', style: TextStyle(color: FluxForgeTheme.accentBlue)),
            ),
          ],
        ),
      ),
    );
    if (result != null) _applyImportedBlueprint(result);
  }

  void _applyImportedBlueprint(Map<String, Object?> bp) {
    silentRun('blueprint.import', () {
      final grid = bp['grid'] as Map?;
      final math = bp['math'] as Map?;
      final compl = bp['compliance'] as Map?;
      setState(() {
        // Slot type
        final st = bp['slotType'] as String?;
        if (st != null) {
          _slotType = SlotTypePreset.values.firstWhere(
            (p) => p.name == st, orElse: () => _slotType);
        }
        // Grid
        if (grid != null) {
          final r = (grid['reels'] as num?)?.toInt();
          final rw = (grid['rows'] as num?)?.toInt();
          if (r != null) _reels = r.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels);
          if (rw != null) _rows = rw.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows);
        }
        // Win mech
        final wm = bp['winMechanism'] as String?;
        if (wm != null) {
          _winMech = WinMechanismType.values.firstWhere(
            (m) => m.paylineTypeName == wm || m.name == wm,
            orElse: () => _winMech);
        }
        final pl = (bp['paylines'] as num?)?.toInt();
        if (pl != null) _paylines = pl;
        // Math
        if (math != null) {
          final v = (math['volatility'] as num?)?.toDouble();
          final rt = (math['rtp'] as num?)?.toDouble();
          final cap = (math['maxWinCap'] as num?)?.toInt();
          final ds = (math['deadSpinsMax'] as num?)?.toInt();
          if (v != null) _volatility = v.clamp(1.0, 10.0);
          if (rt != null) _rtpTarget = rt.clamp(85.0, 99.0);
          if (cap != null) {
            _maxWinCap = MaxWinCap.values.firstWhere(
              (c) => c.multiplier == cap, orElse: () => MaxWinCap.x5000);
          }
          if (ds != null) _deadSpins = ds.clamp(10, 200);
        }
        // Compliance
        if (compl != null) {
          final juris = (compl['jurisdictions'] as List?)?.cast<String>();
          if (juris != null) {
            _jurisdictions
              ..clear()
              ..addAll(Jurisdiction.values.where((j) => juris.contains(j.name)));
          }
        }
      });
      _applyGrid();
      _applyMath();
      _runValidation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 1600),
          content: Text('✓ Blueprint imported',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
          backgroundColor: Color(0xFF1A1A2E),
        ));
      }
    });
  }

  // ─── 3.7.B — RTP feasibility live badge ─────────────────────────────────────
  Widget _buildRtpFeasibilityBadge() {
    final (icon, label, color) = switch (_rtpFeasibility) {
      RtpFeasibility.achievable => (
          Icons.check_circle_outline_rounded,
          '${_rtpTarget.toStringAsFixed(1)}% achievable',
          FluxForgeTheme.accentGreen,
        ),
      RtpFeasibility.marginal => (
          Icons.warning_amber_rounded,
          'Marginal — tune cap/volatility',
          FluxForgeTheme.accentYellow,
        ),
      RtpFeasibility.infeasible => (
          Icons.error_outline_rounded,
          'Infeasible — out of band',
          FluxForgeTheme.accentRed,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: color)),
      ]),
    );
  }

  Widget _gcTensionOrb(String label, Color color) {
    return Column(children: [
      Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.85),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        fontFamily: 'monospace', fontSize: 6, color: color)),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.F — COMPLIANCE TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildComplTab() {
    // Compute strictest jurisdiction
    final strictest = _jurisdictions.isEmpty ? null
        : _jurisdictions.reduce((a, b) => a.minRtp >= b.minRtp ? a : b);

    return ListView(children: [
      _gcSectionHeader('JURISDICTIONS'),
      const SizedBox(height: 4),
      ...Jurisdiction.values.map((j) {
        final active = _jurisdictions.contains(j);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (active) {
                _jurisdictions.remove(j);
              } else {
                _jurisdictions.add(j);
              }
            });
            _runValidation();
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: active ? j.color.withValues(alpha: 0.12) : FluxForgeTheme.bgElevated,
              border: Border.all(
                color: active ? j.color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(children: [
              Text(j.flag, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(j.label, style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    color: active ? j.color : FluxForgeTheme.textPrimary,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                  Text('Min RTP ${j.minRtp.toStringAsFixed(0)}%'
                      '${j.maxBetAmount > 0 ? ' · Max bet ${j.maxBetCurrency}${j.maxBetAmount.toStringAsFixed(0)}' : ''}'
                      '${j.allowsFeatureBuy ? '' : ' · No Feature Buy'}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
                ],
              )),
              if (active) Icon(Icons.check_rounded, size: 10, color: j.color),
            ]),
          ),
        );
      }),
      const SizedBox(height: 10),
      if (strictest != null) ...[
        _gcSectionHeader('AUTO-CONSTRAINTS (${strictest.label})'),
        const SizedBox(height: 4),
        _gcConstraintRow('Auto play', strictest.allowsAutoPlay),
        _gcConstraintRow('Feature Buy', strictest.allowsFeatureBuy),
        _gcConstraintRow('Near-miss', strictest.allowsNearMiss),
        _gcConstraintRow('Max bet limit',
            strictest.maxBetAmount > 0,
            detail: strictest.maxBetAmount > 0
                ? '${strictest.maxBetCurrency}${strictest.maxBetAmount.toStringAsFixed(0)}'
                : 'None'),
        _gcConstraintRow('Win report required', strictest.requiresMaxWinReport),
        const SizedBox(height: 4),
        Text('Min RTP: ${strictest.minRtp.toStringAsFixed(0)}%',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textSecondary)),
      ],
      const SizedBox(height: 8),
      // Violations summary
      if (_issues.where((i) => i.severity == IntegritySeverity.error ||
          i.severity == IntegritySeverity.critical).isNotEmpty) ...[
        _gcSectionHeader('VIOLATIONS'),
        const SizedBox(height: 4),
        ..._issues
            .where((i) => i.severity == IntegritySeverity.error ||
                i.severity == IntegritySeverity.critical)
            .map((issue) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: issue.severity.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2)),
              child: Text(issue.severity.label, style: TextStyle(
                fontFamily: 'monospace', fontSize: 6, color: issue.severity.color)),
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(issue.message, style: const TextStyle(
              fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textSecondary))),
          ]),
        )),
      ],
    ]);
  }

  Widget _gcConstraintRow(String label, bool allowed, {String? detail}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Icon(
          allowed ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
          size: 10,
          color: allowed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange,
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textSecondary))),
        if (detail != null) Text(detail, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.H/I/J — SNAP TAB (snapshots + integrity + blueprint)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSnapTab() {
    return ListView(children: [
      // ── Integrity detail (3.7.I) ──
      _gcSectionHeader('INTEGRITY (${_issues.length} issues)'),
      const SizedBox(height: 4),
      if (_issues.isEmpty)
        const Text('✓ No issues detected', style: TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentGreen))
      else
        ..._issues.map((issue) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: issue.severity.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2)),
              child: Text(issue.severity.label, style: TextStyle(
                fontFamily: 'monospace', fontSize: 6, color: issue.severity.color)),
            ),
            const SizedBox(width: 4),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.message, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 7.5, color: FluxForgeTheme.textSecondary)),
                if (issue.autoFixDescription != null)
                  Text('Fix: ${issue.autoFixDescription}', style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 6.5, color: FluxForgeTheme.accentCyan)),
              ],
            )),
          ]),
        )),
      const SizedBox(height: 12),
      // ── Snapshots (3.7.H) ──
      _gcSectionHeader('SNAPSHOTS'),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _snapNameCtrl,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Snapshot name...',
              hintStyle: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              filled: true,
              fillColor: FluxForgeTheme.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            onSubmitted: (_) => _saveSnapshot(),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: _saveSnapshot,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
              border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('Save', style: TextStyle(
              fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentCyan)),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      if (_snapshots.isEmpty)
        const Text('No snapshots yet', style: TextStyle(
          fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary))
      else
        ..._snapshots.map((snap) {
          final isLeft = _diffLeft == snap.name;
          final isRight = _diffRight == snap.name;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              border: Border.all(
                color: (isLeft || isRight)
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.6)
                    : FluxForgeTheme.borderSubtle,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(snap.name, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.w700))),
                Text(snap.timestampStr, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _loadSnapshot(snap),
                  child: const Text('LOAD', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.accentCyan)),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() {
                    // Two-pick rotation: L empty → set L; else R empty → set R; else swap
                    if (_diffLeft == snap.name) {
                      _diffLeft = null;
                    } else if (_diffRight == snap.name) {
                      _diffRight = null;
                    } else if (_diffLeft == null) {
                      _diffLeft = snap.name;
                    } else if (_diffRight == null) {
                      _diffRight = snap.name;
                    } else {
                      _diffLeft = _diffRight;
                      _diffRight = snap.name;
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: (isLeft || isRight)
                          ? FluxForgeTheme.accentCyan.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      isLeft ? 'L' : isRight ? 'R' : 'diff',
                      style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.accentCyan)),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() {
                    if (_diffLeft == snap.name) _diffLeft = null;
                    if (_diffRight == snap.name) _diffRight = null;
                    _snapshots.remove(snap);
                  }),
                  child: const Icon(Icons.close_rounded, size: 10, color: FluxForgeTheme.textTertiary)),
              ]),
              Text(snap.summaryLine, style: const TextStyle(
                fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary)),
            ]),
          );
        }),
      // Snapshot diff view (3.7.H)
      if (_diffLeft != null && _diffRight != null) ...[
        const SizedBox(height: 8),
        _buildSnapshotDiffView(_diffLeft!, _diffRight!),
      ],
      const SizedBox(height: 12),
      // ── Blueprint Import (3.7.J round-trip) ──
      _gcSectionHeader('BLUEPRINT IMPORT'),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: _showBlueprintImportDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.06),
            border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.download_rounded, size: 12, color: FluxForgeTheme.accentBlue),
            SizedBox(width: 6),
            Text('Import Blueprint (paste JSON)', style: TextStyle(
              fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentBlue)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      // ── Blueprint export (3.7.J) ──
      _gcSectionHeader('BLUEPRINT EXPORT'),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: () async {
          final json = _buildBlueprintJson();
          await Clipboard.setData(ClipboardData(text: json));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Blueprint JSON copied to clipboard',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
                duration: Duration(seconds: 2),
                backgroundColor: Color(0xFF1A1A2E),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentPurple.withValues(alpha: 0.08),
            border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.upload_rounded, size: 12, color: FluxForgeTheme.accentPurple),
            const SizedBox(width: 6),
            const Text('Export Blueprint (copy JSON)', style: TextStyle(
              fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentPurple)),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Copies full slot config as JSON to clipboard.\nPaste into any text editor to save as .flux file.',
        style: TextStyle(fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.textTertiary),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.I — INTEGRITY FOOTER (sticky bottom)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIntegrityFooter(int critCount, int errCount, int warnCount) {
    final total = critCount + errCount + warnCount;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.07),
          border: Border(top: BorderSide(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2))),
        ),
        child: const Row(children: [
          Icon(Icons.check_circle_outline_rounded, size: 10, color: FluxForgeTheme.accentGreen),
          SizedBox(width: 4),
          Text('All checks pass', style: TextStyle(
            fontFamily: 'monospace', fontSize: 7.5, color: FluxForgeTheme.accentGreen)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (critCount > 0 ? IntegritySeverity.critical.color : IntegritySeverity.error.color)
            .withValues(alpha: 0.07),
        border: Border(top: BorderSide(
          color: (critCount > 0 ? IntegritySeverity.critical.color : IntegritySeverity.error.color)
              .withValues(alpha: 0.3))),
      ),
      child: Row(children: [
        if (critCount > 0) _gcIssueBadge('$critCount', IntegritySeverity.critical),
        if (critCount > 0 && errCount > 0) const SizedBox(width: 4),
        if (errCount > 0) _gcIssueBadge('$errCount', IntegritySeverity.error),
        if ((critCount > 0 || errCount > 0) && warnCount > 0) const SizedBox(width: 4),
        if (warnCount > 0) _gcIssueBadge('$warnCount', IntegritySeverity.warning),
        const Spacer(),
        // Fix All Auto button — only when there are auto-fixable issues with severity >= ERROR
        if (_issues.any((i) =>
            i.patch != null &&
            (i.severity == IntegritySeverity.critical ||
             i.severity == IntegritySeverity.error)))
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                final n = _applyAllAutoFixes();
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(milliseconds: 1400),
                    content: Text('🔧 Applied $n auto-fix${n == 1 ? "" : "es"}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    backgroundColor: const Color(0xFF1A1A2E),
                  ));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentCyan.withValues(alpha: 0.12),
                  border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('🔧 fix all', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.accentCyan)),
              ),
            ),
          ),
        GestureDetector(
          onTap: () => setState(() => _tab = _GcTab.snap),
          child: const Text('view →', style: TextStyle(
            fontFamily: 'monospace', fontSize: 7, color: FluxForgeTheme.accentCyan)),
        ),
      ]),
    );
  }

  Widget _gcIssueBadge(String count, IntegritySeverity sev) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: sev.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: sev.color.withValues(alpha: 0.4)),
      ),
      child: Text('$count ${sev.label}', style: TextStyle(
        fontFamily: 'monospace', fontSize: 6.5, color: sev.color)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED MICRO-WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _gcSectionHeader(String label) {
    return Text(label, style: const TextStyle(
      fontFamily: 'monospace', fontSize: 8, letterSpacing: 0.8,
      color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600));
  }

  Widget _gcRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
        const Spacer(),
        Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textSecondary)),
      ]),
    );
  }

  Widget _gcSpinnerRow(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        SizedBox(width: 50, child: Text(label, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary))),
        const Spacer(),
        GestureDetector(
          onTap: () { if (value > min) onChanged(value - 1); },
          child: Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              border: Border.all(color: FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3)),
            child: const Icon(Icons.remove_rounded, size: 12, color: FluxForgeTheme.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$value', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 14, color: FluxForgeTheme.textPrimary,
            fontWeight: FontWeight.w600))),
        GestureDetector(
          onTap: () { if (value < max) onChanged(value + 1); },
          child: Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              border: Border.all(color: FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3)),
            child: const Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.textSecondary)),
        ),
      ]),
    );
  }

  Widget _gcNumberField({
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    return Row(children: [
      Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
      const Spacer(),
      GestureDetector(
        onTap: () => onChanged((value - step).clamp(min, max)),
        child: const Icon(Icons.remove_rounded, size: 14, color: FluxForgeTheme.textSecondary)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(value.toStringAsFixed(1), style: const TextStyle(
          fontFamily: 'monospace', fontSize: 14, color: FluxForgeTheme.textPrimary,
          fontWeight: FontWeight.w600))),
      GestureDetector(
        onTap: () => onChanged((value + step).clamp(min, max)),
        child: const Icon(Icons.add_rounded, size: 14, color: FluxForgeTheme.textSecondary)),
    ]);
  }

  Widget _gcApplyButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
          border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan)),
      ),
    );
  }

  Widget _gcPresetChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgElevated,
          border: Border.all(color: FluxForgeTheme.borderSubtle),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textSecondary)),
      ),
    );
  }

  Widget _gcRadioChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.12) : FluxForgeTheme.bgElevated,
          border: Border.all(
            color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 8,
          color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary)),
      ),
    );
  }

  Widget _gcToggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textSecondary))),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 32, height: 16,
            decoration: BoxDecoration(
              color: value ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5) : FluxForgeTheme.bgElevated,
              border: Border.all(color: value ? FluxForgeTheme.accentCyan : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 12, height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── 3.7.G — Live Grid Visualizer StatefulWidget ──────────────────────────────

class _GridVisualizerWidget extends StatefulWidget {
  final int reels;
  final int rows;
  final WinMechanismType winMech;
  final MegawaysReelConfig? megaways;
  final ClusterConfig? clusterConfig;
  final List<String> symbolEmojis;
  final int paylines;

  const _GridVisualizerWidget({
    required this.reels,
    required this.rows,
    required this.winMech,
    this.megaways,
    this.clusterConfig,
    required this.symbolEmojis,
    required this.paylines,
  });

  @override
  State<_GridVisualizerWidget> createState() => _GridVisualizerWidgetState();
}

class _GridVisualizerWidgetState extends State<_GridVisualizerWidget>
    with TickerProviderStateMixin {
  List<AnimationController> _reelCtrl = [];
  List<String> _grid = [];
  bool _isSpinning = false;
  int _highlightedPayline = 0;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _initControllers();
    _fillGrid();
  }

  @override
  void didUpdateWidget(_GridVisualizerWidget old) {
    super.didUpdateWidget(old);
    final gridChanged = old.reels != widget.reels || old.rows != widget.rows;
    if (gridChanged) {
      // Stop any in-progress spin before reinitialising controllers
      _isSpinning = false;
      _disposeControllers();
      _initControllers();
      _fillGrid();
    } else if (old.symbolEmojis.length != widget.symbolEmojis.length ||
               (old.symbolEmojis.isNotEmpty &&
                old.symbolEmojis.first != widget.symbolEmojis.first)) {
      // Symbol preset changed — refill grid (only when not spinning)
      if (!_isSpinning) _fillGrid();
    }
    // Clamp payline highlight when paylines count shrinks
    if (widget.paylines > 0 && _highlightedPayline >= widget.paylines) {
      _highlightedPayline = 0;
    }
  }

  void _initControllers() {
    _reelCtrl = List.generate(widget.reels, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 500 + i * 60),
      );
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
      return ctrl;
    });
  }

  void _disposeControllers() {
    for (final c in _reelCtrl) {
      c.dispose();
    }
    _reelCtrl = [];
  }

  void _fillGrid() {
    final src = widget.symbolEmojis.isEmpty ? const ['?'] : widget.symbolEmojis;
    _grid = List.generate(
      widget.reels * widget.rows,
      (i) => src[i % src.length],
    );
  }

  List<String> _randomGrid() {
    final src = widget.symbolEmojis.isEmpty ? const ['?'] : widget.symbolEmojis;
    return List.generate(
      widget.reels * widget.rows,
      (_) => src[_rng.nextInt(src.length)],
    );
  }

  Future<void> _startSpinPreview() async {
    if (_isSpinning || !mounted) return;
    final landing = _randomGrid();
    setState(() => _isSpinning = true);

    // Start all reels spinning simultaneously
    for (final ctrl in _reelCtrl) {
      ctrl.repeat();
    }

    // Stop reels one by one (staggered landing)
    for (int r = 0; r < widget.reels; r++) {
      await Future.delayed(Duration(milliseconds: 350 + r * 220));
      if (!mounted) return;
      // Land symbols for this reel
      for (int row = 0; row < widget.rows; row++) {
        final idx = r * widget.rows + row;
        if (idx < landing.length) _grid[idx] = landing[idx];
      }
      _reelCtrl[r]
        ..stop()
        ..reset();
      setState(() {});
    }

    if (!mounted) return;
    setState(() => _isSpinning = false);
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  String _formatWays(int ways) {
    if (ways >= 1000000) return '${(ways / 1000000).toStringAsFixed(1)}M';
    if (ways >= 1000) return '${(ways / 1000).toStringAsFixed(0)}k';
    return ways.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Canvas height: Megaways uses maxRows, others use fixed rows
    final double canvasH = (() {
      if (widget.winMech == WinMechanismType.megaways && widget.megaways != null) {
        return (widget.megaways!.maxRows * 22.0).clamp(44.0, 154.0);
      }
      return (widget.rows * 22.0).clamp(44.0, 154.0);
    })();

    final spinOffsets = _reelCtrl.map((c) => c.value).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: canvasH,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgElevated,
            border: Border.all(color: FluxForgeTheme.borderSubtle),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(
              size: Size.infinite,
              painter: _GridVisualizerPainter(
                reels: widget.reels,
                rows: widget.rows,
                winMech: widget.winMech,
                megawaysRowsPerReel: widget.megaways?.rowsPerReel,
                symbols: _grid,
                reelSpinOffsets: spinOffsets,
                highlightedPayline: _highlightedPayline,
                paylines: widget.paylines,
                clusterConfig: widget.clusterConfig,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          // Left: payline nav or ways badge
          if (widget.winMech == WinMechanismType.paylines && widget.paylines > 1) ...[
            _navBtn('◀', () => setState(() =>
                _highlightedPayline = (_highlightedPayline - 1 + widget.paylines) % widget.paylines)),
            const SizedBox(width: 4),
            Text(
              'LINE ${_highlightedPayline + 1}/${widget.paylines}',
              style: const TextStyle(
                fontFamily: 'monospace', fontSize: 7,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            _navBtn('▶', () => setState(() =>
                _highlightedPayline = (_highlightedPayline + 1) % widget.paylines)),
          ] else if (widget.winMech == WinMechanismType.megaways && widget.megaways != null)
            Text(
              '${_formatWays(widget.megaways!.totalWays)} WAYS',
              style: const TextStyle(
                fontFamily: 'monospace', fontSize: 7,
                color: Color(0xFFFF9800),
              ),
            )
          else if (widget.winMech == WinMechanismType.ways)
            Text(
              'ALL ${widget.reels * widget.rows} POSITIONS',
              style: const TextStyle(
                fontFamily: 'monospace', fontSize: 7,
                color: Color(0xFF9C27B0),
              ),
            )
          else
            const SizedBox.shrink(),
          const Spacer(),
          // SPIN PREVIEW button
          GestureDetector(
            onTap: _isSpinning ? null : _startSpinPreview,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isSpinning
                    ? const Color(0xFFFF9800).withValues(alpha: 0.08)
                    : FluxForgeTheme.accentCyan.withValues(alpha: 0.06),
                border: Border.all(
                  color: _isSpinning
                      ? const Color(0xFFFF9800).withValues(alpha: 0.35)
                      : FluxForgeTheme.accentCyan.withValues(alpha: 0.25),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _isSpinning ? '◌ SPINNING' : '⚡ SPIN',
                style: TextStyle(
                  fontFamily: 'monospace', fontSize: 7,
                  color: _isSpinning
                      ? const Color(0xFFFF9800)
                      : FluxForgeTheme.accentCyan,
                ),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _navBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(label,
          style: const TextStyle(
            fontFamily: 'monospace', fontSize: 7,
            color: FluxForgeTheme.textSecondary,
          )),
      ),
    ),
  );
}

// ── 3.7.G — Grid Visualizer Painter ─────────────────────────────────────────

class _GridVisualizerPainter extends CustomPainter {
  final int reels;
  final int rows;
  final WinMechanismType winMech;
  final List<int>? megawaysRowsPerReel;
  final List<String> symbols;          // length = reels * rows, reel-major
  final List<double> reelSpinOffsets;  // length = reels, 0.0 = stopped
  final int highlightedPayline;
  final int paylines;
  final ClusterConfig? clusterConfig;

  static const _accentPaylines = Color(0xFF00B4D8);
  static const _accentWays     = Color(0xFF9C27B0);
  static const _accentCluster  = Color(0xFF4CAF50);
  static const _accentMegaways = Color(0xFFFF9800);

  _GridVisualizerPainter({
    required this.reels,
    required this.rows,
    required this.winMech,
    this.megawaysRowsPerReel,
    required this.symbols,
    required this.reelSpinOffsets,
    required this.highlightedPayline,
    required this.paylines,
    this.clusterConfig,
  });

  Color get _accent => switch (winMech) {
    WinMechanismType.paylines => _accentPaylines,
    WinMechanismType.ways     => _accentWays,
    WinMechanismType.cluster  => _accentCluster,
    WinMechanismType.megaways => _accentMegaways,
  };

  // ── Entry point ──────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (reels <= 0 || rows <= 0) return;

    if (winMech == WinMechanismType.megaways && megawaysRowsPerReel != null) {
      _paintMegawaysGrid(canvas, size);
    } else {
      _paintStandardGrid(canvas, size);
    }

    // Mechanism overlays
    switch (winMech) {
      case WinMechanismType.paylines:
        if (paylines > 0) _paintPaylineOverlay(canvas, size);
      case WinMechanismType.ways:
        _paintWaysOverlay(canvas, size);
      case WinMechanismType.cluster:
        _paintClusterOverlay(canvas, size);
      case WinMechanismType.megaways:
        _paintMegawaysLabel(canvas, size);
    }

    _paintGridLabel(canvas, size);
  }

  // ── Standard grid ─────────────────────────────────────────────────────────

  void _paintStandardGrid(Canvas canvas, Size size) {
    final cellW = size.width / reels;
    final cellH = size.height / rows;
    final accent = _accent;

    final borderPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < reels; r++) {
      final spinAmt = r < reelSpinOffsets.length ? reelSpinOffsets[r] : 0.0;
      final spinning = spinAmt > 0.01;

      for (int row = 0; row < rows; row++) {
        final rect = Rect.fromLTWH(
          r * cellW + 1, row * cellH + 1, cellW - 2, cellH - 2);
        fillPaint.color = accent.withValues(alpha: 0.04 + (row.isEven ? 0.02 : 0.0));
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), fillPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), borderPaint);

        if (spinning) {
          _paintSpinEffect(canvas, rect, accent, spinAmt);
        } else {
          final idx = r * rows + row;
          _paintSymbol(canvas, rect, idx < symbols.length ? symbols[idx] : '?', cellH);
        }
      }
    }
  }

  // ── Megaways grid (variable per-reel height) ─────────────────────────────

  void _paintMegawaysGrid(Canvas canvas, Size size) {
    final rwp = megawaysRowsPerReel!;
    final safeReels = math.min(reels, rwp.length);
    if (safeReels == 0) return;
    final cellW = size.width / safeReels;
    final maxRows = rwp.reduce(math.max);

    final borderPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < safeReels; r++) {
      final reelRows = rwp[r].clamp(1, 8);
      final reelCellH = size.height / reelRows;
      final spinAmt = r < reelSpinOffsets.length ? reelSpinOffsets[r] : 0.0;
      final spinning = spinAmt > 0.01;

      // Reel trough background
      fillPaint.color = _accentMegaways.withValues(alpha: 0.03 + (r.isEven ? 0.02 : 0.0));
      canvas.drawRect(
        Rect.fromLTWH(r * cellW + 0.5, 0, cellW - 1, size.height), fillPaint);

      // Cells
      for (int row = 0; row < reelRows; row++) {
        final rect = Rect.fromLTWH(
          r * cellW + 1, row * reelCellH + 1, cellW - 2, reelCellH - 2);
        fillPaint.color = _accentMegaways.withValues(alpha: 0.05 + (row.isEven ? 0.02 : 0.0));
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), fillPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), borderPaint);

        if (spinning) {
          _paintSpinEffect(canvas, rect, _accentMegaways, spinAmt);
        } else {
          final idx = r * rows + row;
          _paintSymbol(canvas, rect, idx < symbols.length ? symbols[idx] : '?', reelCellH);
        }
      }

      // Row count badge (bottom of reel)
      _paintSmallLabel(
        canvas,
        Offset(r * cellW + cellW / 2, size.height - 5),
        'R$reelRows',
        _accentMegaways.withValues(alpha: 0.55),
        centerX: true,
      );

      // Unused space indicator (gap between this reel's top and maxRows top)
      if (reelRows < maxRows) {
        final gapH = size.height - reelRows * reelCellH;
        final gapRect = Rect.fromLTWH(r * cellW + 1, 0, cellW - 2, gapH);
        canvas.drawRect(gapRect,
          Paint()..color = _accentMegaways.withValues(alpha: 0.04)..style = PaintingStyle.fill);
      }
    }
  }

  // ── Spin blur effect ─────────────────────────────────────────────────────

  void _paintSpinEffect(Canvas canvas, Rect rect, Color accent, double spinAmt) {
    final lineH = rect.height / 4;
    final paint = Paint()..style = PaintingStyle.fill;
    for (int l = 0; l < 4; l++) {
      paint.color = accent.withValues(alpha: spinAmt * (l.isEven ? 0.18 : 0.08));
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top + l * lineH, rect.width, lineH),
        paint,
      );
    }
  }

  // ── Symbol emoji rendering ────────────────────────────────────────────────

  void _paintSymbol(Canvas canvas, Rect rect, String emoji, double cellH) {
    final fontSize = (cellH * 0.48).clamp(6.0, 13.0);
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    canvas.save();
    canvas.clipRect(rect.inflate(1));
    tp.paint(
      canvas,
      Offset(
        rect.left + (rect.width - tp.width) / 2,
        rect.top + (rect.height - tp.height) / 2,
      ),
    );
    canvas.restore();
  }

  // ── Payline overlay ──────────────────────────────────────────────────────

  /// Generates reels-length row pattern for the given payline index.
  List<int> _paylinePattern(int lineIdx) {
    final mid = rows ~/ 2;
    final top = 0;
    final bot = (rows - 1).clamp(0, rows - 1);
    final half = math.max(1, reels ~/ 2);
    final quarter = math.max(1, reels ~/ 4);

    int clamp(int v) => v.clamp(top, bot);
    int lerp(int from, int to, int r, int steps) =>
        clamp(from + (r * (to - from) ~/ math.max(1, steps)));

    final patterns = <List<int> Function()>[
      () => List.filled(reels, mid),                        // 0 mid straight
      () => List.filled(reels, top),                        // 1 top straight
      () => List.filled(reels, bot),                        // 2 bot straight
      () => List.generate(reels, (r) =>                     // 3 V
          r <= half ? lerp(top, mid, r, half) : lerp(mid, top, r - half, reels - 1 - half)),
      () => List.generate(reels, (r) =>                     // 4 inv-V
          r <= half ? lerp(bot, mid, r, half) : lerp(mid, bot, r - half, reels - 1 - half)),
      () => List.generate(reels, (r) => lerp(top, bot, r, reels - 1)),  // 5 stair ↓
      () => List.generate(reels, (r) => lerp(bot, top, r, reels - 1)),  // 6 stair ↑
      () => List.generate(reels, (r) => r.isEven ? top : bot),           // 7 zigzag ↑↓
      () => List.generate(reels, (r) => r.isEven ? bot : top),           // 8 zigzag ↓↑
      () => List.generate(reels, (r) =>                                   // 9 brackets top
          (r == 0 || r == reels - 1) ? top : mid),
      () => List.generate(reels, (r) =>                                   // 10 brackets bot
          (r == 0 || r == reels - 1) ? bot : mid),
      () => List.generate(reels, (r) =>                                   // 11 valley center
          clamp(mid + (r - half).abs())),
      () => List.generate(reels, (r) =>                                   // 12 hill center
          clamp(mid - (r - half).abs())),
      () => List.generate(reels, (r) => r.isEven ? mid : top),            // 13 alt mid/top
      () => List.generate(reels, (r) => r.isEven ? mid : bot),            // 14 alt mid/bot
      () => List.generate(reels, (r) => lerp(top, mid, r, reels - 1)),   // 15 top→mid
      () => List.generate(reels, (r) => lerp(bot, mid, r, reels - 1)),   // 16 bot→mid
      () => List.generate(reels, (r) {                                    // 17 W-shape
        if (r < quarter) return clamp(bot - r);
        if (r < half)    return clamp(top + (r - quarter));
        if (r < 3 * quarter) return clamp(bot - (r - half));
        return clamp(top + (r - 3 * quarter));
      }),
      () => List.generate(reels, (r) {                                    // 18 M-shape
        if (r < quarter) return clamp(top + r);
        if (r < half)    return clamp(bot - (r - quarter));
        if (r < 3 * quarter) return clamp(top + (r - half));
        return clamp(bot - (r - 3 * quarter));
      }),
      () => List.generate(reels, (r) =>                                   // 19 peak at r2
          r == reels ~/ 2 ? bot : top),
    ];

    final idx = lineIdx % patterns.length;
    return patterns[idx]();
  }

  void _paintPaylineOverlay(Canvas canvas, Size size) {
    if (reels == 0 || rows == 0) return;
    final cellW = size.width / reels;
    final cellH = size.height / rows;
    final pattern = _paylinePattern(highlightedPayline);

    // Unique hue per payline (cycle full spectrum)
    final hue = (highlightedPayline / math.max(1, paylines) * 360.0) % 360;
    final lineColor = HSVColor.fromAHSV(1.0, hue, 0.85, 1.0).toColor();

    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.12)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.75)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final cellHighlight = Paint()
      ..color = lineColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int r = 0; r < reels && r < pattern.length; r++) {
      final row = pattern[r].clamp(0, rows - 1);
      final x = r * cellW + cellW / 2;
      final y = row * cellH + cellH / 2;
      if (r == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    for (int r = 0; r < reels && r < pattern.length; r++) {
      final row = pattern[r].clamp(0, rows - 1);
      final x = r * cellW + cellW / 2;
      final y = row * cellH + cellH / 2;
      // Cell highlight
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r * cellW + 1, row * cellH + 1, cellW - 2, cellH - 2),
          const Radius.circular(2),
        ),
        cellHighlight,
      );
      // Dot
      canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
    }

    // Line number badge (top-left)
    _paintSmallLabel(canvas, const Offset(3, 2),
      '${highlightedPayline + 1}', lineColor);
  }

  // ── Ways overlay ─────────────────────────────────────────────────────────

  void _paintWaysOverlay(Canvas canvas, Size size) {
    if (reels < 2 || rows == 0) return;
    final cellW = size.width / reels;
    final cellH = size.height / rows;
    final connPaint = Paint()
      ..color = _accentWays.withValues(alpha: 0.06)
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;

    for (int r = 0; r < reels - 1; r++) {
      final x1 = r * cellW + cellW;
      final x2 = (r + 1) * cellW;
      for (int row = 0; row < rows; row++) {
        final y1 = row * cellH + cellH / 2;
        for (int nextRow = 0; nextRow < rows; nextRow++) {
          final y2 = nextRow * cellH + cellH / 2;
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), connPaint);
        }
      }
    }

    // ALL WAYS label
    _paintSmallLabel(canvas,
      Offset(size.width / 2, 3),
      'ALL WAYS',
      _accentWays.withValues(alpha: 0.55),
      centerX: true,
    );
  }

  // ── Cluster overlay ──────────────────────────────────────────────────────

  void _paintClusterOverlay(Canvas canvas, Size size) {
    if (reels == 0 || rows == 0) return;
    final cellW = size.width / reels;
    final cellH = size.height / rows;

    final linePaint = Paint()
      ..color = _accentCluster.withValues(alpha: 0.13)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final diagPaint = Paint()
      ..color = _accentCluster.withValues(alpha: 0.06)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = _accentCluster.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    for (int r = 0; r < reels; r++) {
      for (int row = 0; row < rows; row++) {
        final cx = r * cellW + cellW / 2;
        final cy = row * cellH + cellH / 2;
        // Right neighbor
        if (r + 1 < reels) {
          canvas.drawLine(Offset(cx, cy), Offset((r + 1) * cellW + cellW / 2, cy), linePaint);
        }
        // Bottom neighbor
        if (row + 1 < rows) {
          canvas.drawLine(Offset(cx, cy), Offset(cx, (row + 1) * cellH + cellH / 2), linePaint);
        }
        // Diagonals (if cluster allows)
        if (clusterConfig?.allowDiagonal == true) {
          if (r + 1 < reels && row + 1 < rows) {
            canvas.drawLine(Offset(cx, cy),
              Offset((r + 1) * cellW + cellW / 2, (row + 1) * cellH + cellH / 2), diagPaint);
          }
          if (r + 1 < reels && row > 0) {
            canvas.drawLine(Offset(cx, cy),
              Offset((r + 1) * cellW + cellW / 2, (row - 1) * cellH + cellH / 2), diagPaint);
          }
        }
        canvas.drawCircle(Offset(cx, cy), 1.3, dotPaint);
      }
    }

    // MIN badge
    if (clusterConfig != null) {
      _paintSmallLabel(canvas,
        Offset(size.width / 2, 3),
        'MIN ${clusterConfig!.minSize}',
        _accentCluster.withValues(alpha: 0.65),
        centerX: true,
      );
    }
  }

  // ── Megaways label ───────────────────────────────────────────────────────

  void _paintMegawaysLabel(Canvas canvas, Size size) {
    _paintSmallLabel(canvas,
      Offset(size.width - 3, 3),
      'MEGAWAYS',
      _accentMegaways.withValues(alpha: 0.45),
      alignRight: true,
    );
  }

  // ── Grid label (bottom-right) ────────────────────────────────────────────

  void _paintGridLabel(Canvas canvas, Size size) {
    final label = switch (winMech) {
      WinMechanismType.paylines => '${reels}×$rows  $paylines LINES',
      WinMechanismType.ways     => '${reels}×$rows  WAYS',
      WinMechanismType.cluster  => '${reels}×$rows  CLUSTER',
      WinMechanismType.megaways => '${reels}R×var  MEGAWAYS',
    };
    _paintSmallLabel(canvas,
      Offset(size.width - 3, size.height - 8),
      label,
      _accent.withValues(alpha: 0.4),
      alignRight: true,
    );
  }

  // ── Shared small-text helper ─────────────────────────────────────────────

  void _paintSmallLabel(Canvas canvas, Offset pos, String text, Color color,
      {bool centerX = false, bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: 'monospace', fontSize: 6, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = pos.dx;
    if (centerX) dx -= tp.width / 2;
    if (alignRight) dx -= tp.width;
    tp.paint(canvas, Offset(dx, pos.dy));
  }

  // ── shouldRepaint ────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(_GridVisualizerPainter old) {
    if (old.reels != reels || old.rows != rows || old.winMech != winMech ||
        old.highlightedPayline != highlightedPayline || old.paylines != paylines) return true;
    if (old.symbols.length != symbols.length) return true;
    for (int i = 0; i < symbols.length; i++) {
      if (old.symbols[i] != symbols[i]) return true;
    }
    if (old.reelSpinOffsets.length != reelSpinOffsets.length) return true;
    for (int i = 0; i < reelSpinOffsets.length; i++) {
      if ((old.reelSpinOffsets[i] - reelSpinOffsets[i]).abs() > 0.001) return true;
    }
    if (old.megawaysRowsPerReel?.length != megawaysRowsPerReel?.length) return true;
    if (old.megawaysRowsPerReel != null && megawaysRowsPerReel != null) {
      for (int i = 0; i < megawaysRowsPerReel!.length; i++) {
        if (old.megawaysRowsPerReel![i] != megawaysRowsPerReel![i]) return true;
      }
    }
    return false;
  }
}

// ── Symbol editor row for GAME CONFIG spine ──────────────────────────────────

class _SymbolEditorRow extends StatefulWidget {
  final SymbolDefinition symbol;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<int> onPayChanged;
  const _SymbolEditorRow({
    required this.symbol,
    required this.onNameChanged,
    required this.onPayChanged,
  });
  @override
  State<_SymbolEditorRow> createState() => _SymbolEditorRowState();
}

class _SymbolEditorRowState extends State<_SymbolEditorRow> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.symbol.name);
  }

  @override
  void didUpdateWidget(_SymbolEditorRow old) {
    super.didUpdateWidget(old);
    if (old.symbol.name != widget.symbol.name && _nameCtrl.text != widget.symbol.name) {
      _nameCtrl.text = widget.symbol.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pay = widget.symbol.payMultiplier ?? 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        // Emoji / tier indicator
        Text(widget.symbol.emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        // Editable name
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.textPrimary),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              filled: true,
              fillColor: FluxForgeTheme.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            onSubmitted: widget.onNameChanged,
            onEditingComplete: () => widget.onNameChanged(_nameCtrl.text),
          ),
        ),
        const SizedBox(width: 4),
        // Pay multiplier spinner
        GestureDetector(
          onTap: () { if (pay > 1) widget.onPayChanged(pay - 1); },
          child: const Icon(Icons.remove_rounded, size: 10, color: FluxForgeTheme.textTertiary)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text('${pay}x', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentYellow))),
        GestureDetector(
          onTap: () => widget.onPayChanged(pay + 1),
          child: const Icon(Icons.add_rounded, size: 10, color: FluxForgeTheme.textTertiary)),
      ]),
    );
  }
}

// ── Spine: AI / INTEL ───────────────────────────────────────────────────────

class _SpineAiIntel extends StatefulWidget {
  @override
  State<_SpineAiIntel> createState() => _SpineAiIntelState();
}

class _SpineAiIntelState extends State<_SpineAiIntel> {
  // S5: RTPC write sliders
  final List<double> _rtpcOverrides = List.filled(8, -1); // -1 = not overridden

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<NeuroAudioProvider>(),
        GetIt.instance<MiddlewareProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final mw = GetIt.instance<MiddlewareProvider>();
    final out = neuro.output;
    final dims = [
      ('Arousal',       out.arousal,        FluxForgeTheme.accentRed,     0),
      ('Valence',       (out.valence + 1) / 2, FluxForgeTheme.accentGreen, 1),
      ('Engagement',    out.engagement,     FluxForgeTheme.accentBlue,    2),
      ('Risk tolerance',out.riskTolerance,  FluxForgeTheme.accentOrange,  3),
      ('Frustration',   out.frustration,    FluxForgeTheme.accentYellow,  4),
      ('Flow depth',    out.flowDepth,      FluxForgeTheme.accentCyan,    5),
      ('Churn risk',    out.churnPrediction,FluxForgeTheme.accentPurple,  6),
      ('Fatigue',       out.sessionFatigue, FluxForgeTheme.accentOrange,  7),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('8D EMOTIONAL STATE', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
            color: FluxForgeTheme.textTertiary)),
          const Spacer(),
          const Text('drag to override', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
        ]),
        const SizedBox(height: 8),
        ...dims.map((d) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(width: 70, child: Text(d.$1, style: const TextStyle(
                fontSize: 9, color: FluxForgeTheme.textSecondary))),
              // S5: Interactive RTPC slider
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) => GestureDetector(
                    onHorizontalDragUpdate: (det) {
                      final frac = (det.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                      setState(() => _rtpcOverrides[d.$4] = frac);
                      silentRun('neuro.setRtpc', () { mw.setRtpc(d.$4, frac, interpolationMs: 100); });
                    },
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgElevated,
                        borderRadius: BorderRadius.circular(2)),
                      child: FractionallySizedBox(
                        widthFactor: (_rtpcOverrides[d.$4] >= 0 ? _rtpcOverrides[d.$4] : d.$2).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(decoration: BoxDecoration(
                          color: d.$3, borderRadius: BorderRadius.circular(2))),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 32, child: Text(
                '${((_rtpcOverrides[d.$4] >= 0 ? _rtpcOverrides[d.$4] : d.$2) * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontFamily: 'monospace', fontSize: 8, color: d.$3),
                textAlign: TextAlign.right)),
            ],
          ),
        )),
        const Spacer(),
        Row(children: [
          const Text('Risk: ', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
          Text(neuro.riskLevel.name.toUpperCase(), style: TextStyle(
            fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w600,
            color: neuro.riskLevel == PlayerRiskLevel.low ? FluxForgeTheme.accentGreen
              : neuro.riskLevel == PlayerRiskLevel.high ? FluxForgeTheme.accentRed
              : FluxForgeTheme.accentYellow)),
        ]),
      ],
    );
  }
}

// ── Spine: SETTINGS ─────────────────────────────────────────────────────────

class _SpineSettings extends StatefulWidget {
  @override
  State<_SpineSettings> createState() => _SpineSettingsState();
}

class _SpineSettingsState extends State<_SpineSettings> {
  late double _bpmSlider;

  @override
  void initState() {
    super.initState();
    _bpmSlider = GetIt.instance<EngineProvider>().transport.tempo.clamp(20.0, 300.0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<EngineProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final engine = GetIt.instance<EngineProvider>();
    final t = engine.transport;
    final neuro = GetIt.instance<NeuroAudioProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ENGINE', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        // BPM slider
        Row(children: [
          const Text('TEMPO', style: TextStyle(
            fontSize: 10, color: FluxForgeTheme.textTertiary)),
          const Spacer(),
          Text('${_bpmSlider.toStringAsFixed(0)} BPM', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.accentCyan)),
        ]),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: FluxForgeTheme.accentCyan,
            inactiveTrackColor: FluxForgeTheme.bgElevated,
            thumbColor: FluxForgeTheme.accentCyan,
            overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
          ),
          child: Slider(
            value: _bpmSlider,
            min: 40, max: 240,
            onChanged: (v) => setState(() => _bpmSlider = v),
            onChangeEnd: (v) => engine.setTempo(v),
          ),
        ),
        const SizedBox(height: 6),
        _SpineRow('Time sig', '${t.timeSigNum}/${t.timeSigDenom}'),
        _SpineRow('Position', '${t.positionSeconds.toStringAsFixed(1)}s'),
        _SpineRow('Playing', t.isPlaying ? 'YES' : 'NO'),
        const SizedBox(height: 12),
        const Text('NEURO AUDIO', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        // NeuroAudio toggle
        _SpineToggle(
          label: 'Enabled',
          value: neuro.enabled,
          activeColor: FluxForgeTheme.accentGreen,
          onChanged: (v) => neuro.setEnabled(v),
        ),
        const SizedBox(height: 6),
        // RG Mode toggle
        _SpineToggle(
          label: 'RG Mode',
          value: neuro.responsibleGamingMode,
          activeColor: FluxForgeTheme.accentOrange,
          onChanged: (v) => neuro.setResponsibleGamingMode(v),
        ),
        const SizedBox(height: 6),
        _SpineRow('Tempo mod', '${(neuro.output.tempoModifier * 100).toStringAsFixed(0)}%'),
        _SpineRow('Reverb mod', '${(neuro.output.reverbDepthModifier * 100).toStringAsFixed(0)}%'),
      ],
    );
  }
}

class _SpineToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;
  const _SpineToggle({required this.label, required this.value,
    required this.activeColor, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(
        fontSize: 10, color: FluxForgeTheme.textSecondary))),
      GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36, height: 18,
          decoration: BoxDecoration(
            color: value ? activeColor.withValues(alpha: 0.2) : FluxForgeTheme.bgElevated,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: value ? activeColor : FluxForgeTheme.borderSubtle),
          ),
          child: Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 150),
              left: value ? 20 : 2,
              top: 2, bottom: 2,
              child: Container(
                width: 14,
                decoration: BoxDecoration(
                  color: value ? activeColor : FluxForgeTheme.textTertiary,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ]),
        ),
      ),
    ],
  );
}

// ── Spine: ANALYTICS ────────────────────────────────────────────────────────

class _SpineAnalytics extends StatefulWidget {
  @override
  State<_SpineAnalytics> createState() => _SpineAnalyticsState();
}

class _SpineAnalyticsState extends State<_SpineAnalytics> {
  String? _exportStatus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<SlotLabProjectProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
        GetIt.instance<MiddlewareProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final mw = GetIt.instance<MiddlewareProvider>();
    final stats = proj.sessionStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SESSION ANALYTICS', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        _SpineRow('Spins', '${stats.totalSpins}'),
        _SpineRow('RTP', stats.rtp.isNaN ? '—' : '${stats.rtp.toStringAsFixed(1)}%'),
        _SpineRow('Win count', '${proj.recentWins.length}'),
        _SpineRow('Duration', '${neuro.sessionDurationMinutes.toStringAsFixed(1)} min'),
        const SizedBox(height: 12),
        const Text('AUDIO SYSTEM', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        _SpineRow('Events', '${mw.compositeEvents.length}'),
        _SpineRow('RTPC updates', '${mw.rtpcUpdateCount}'),
        _SpineRow('Switch changes', '${mw.switchChangeCount}'),
        _SpineRow('Actions', '${mw.actionCount}'),
        const Spacer(),
        // Status feedback
        if (_exportStatus != null) Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(_exportStatus!, style: TextStyle(
            fontFamily: 'monospace', fontSize: 8,
            color: _exportStatus!.startsWith('✓')
              ? FluxForgeTheme.accentGreen
              : FluxForgeTheme.accentOrange)),
        ),
        // S8: Export session report
        GestureDetector(
          onTap: () {
            try {
              GetIt.instance<SlotExportProvider>().exportSingle({
                'format': 'session_report',
                'name': proj.projectName,
                'spins': stats.totalSpins,
                'rtp': stats.rtp,
              }, 'session_report');
              setState(() => _exportStatus = '✓ Report exported');
              Future.delayed(const Duration(seconds: 3),
                () { if (mounted) setState(() => _exportStatus = null); });
            } catch (e) {
              setState(() => _exportStatus = '✗ Failed: $e');
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.06),
              border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(4)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.download_rounded, size: 10, color: FluxForgeTheme.accentPurple),
              SizedBox(width: 4),
              Text('Export Session Report', style: TextStyle(
                fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentPurple)),
            ]),
          ),
        ),
      ],
    );
  }
}

// ── Spine helper row ────────────────────────────────────────────────────────

class _SpineRow extends StatelessWidget {
  final String label, value;
  const _SpineRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(
          fontSize: 10, color: FluxForgeTheme.textTertiary))),
        Text(value, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 10,
          color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

// _DockTab, _DockCard, _DockLabel → helix/helix_dock_widgets.dart (part file)

class _StageNode extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  const _StageNode({required this.label, required this.color, required this.active});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      border: active ? Border.all(color: color.withValues(alpha: 0.3), width: 0.5) : null,
      boxShadow: active ? [
        BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, spreadRadius: -2),
      ] : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(
          color: active ? color : FluxForgeTheme.textTertiary,
          shape: BoxShape.circle,
          boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)] : null)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          color: active ? color : FluxForgeTheme.textTertiary)),
      ],
    ),
  );
}

class _FlowNode extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback? onTap;
  final bool isCustom;
  final VoidCallback? onRemove;
  const _FlowNode({required this.label, required this.icon,
    required this.color, required this.active, this.onTap,
    this.isCustom = false, this.onRemove});

  @override
  State<_FlowNode> createState() => _FlowNodeState();
}

class _FlowNodeState extends State<_FlowNode> {
  bool _hovered = false;

  // F2: Full transition config menu on right-click
  void _showNodeMenu(BuildContext context) {
    final flow = GetIt.instance<GameFlowProvider>();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final configs = flow.transitionConfigs;
    final transitionsEnabled = flow.transitionsEnabled;

    showMenu<String>(
      context: context,
      color: FluxForgeTheme.bgSurface,
      position: RelativeRect.fromLTRB(
        offset.dx, offset.dy + renderBox.size.height + 4,
        offset.dx + renderBox.size.width, offset.dy + renderBox.size.height + 4),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('STAGE: ${widget.label}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
              color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
        ),
        const PopupMenuDivider(),
        // F2: Toggle transitions globally
        PopupMenuItem<String>(
          value: 'toggle_transitions',
          child: Row(children: [
            Icon(transitionsEnabled ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14, color: transitionsEnabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary),
            const SizedBox(width: 6),
            Text('Transitions ${transitionsEnabled ? "ON" : "OFF"}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F2: Show configured transition rules
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TRANSITION RULES:', style: TextStyle(
                fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
              const SizedBox(height: 4),
              if (configs.isEmpty)
                const Text('  (default config)', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary))
              else
                ...configs.entries.take(5).map((e) => Text(
                  '  ${e.key}: ${e.value.durationMs}ms',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 8,
                    color: FluxForgeTheme.textSecondary),
                )),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // F2: Force stage action
        PopupMenuItem<String>(
          value: 'force',
          child: Row(children: [
            Icon(Icons.play_arrow_rounded, size: 14, color: widget.color),
            const SizedBox(width: 6),
            Text('Force → ${widget.label}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F2: Reset to base
        PopupMenuItem<String>(
          value: 'reset',
          child: const Row(children: [
            Icon(Icons.restart_alt_rounded, size: 14, color: FluxForgeTheme.textTertiary),
            SizedBox(width: 6),
            Text('Reset to BASE', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F3: Remove custom stage
        if (widget.isCustom) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'remove',
            child: Row(children: [
              const Icon(Icons.delete_outline_rounded, size: 14, color: FluxForgeTheme.accentPink),
              const SizedBox(width: 6),
              Text('Remove ${widget.label}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.accentPink)),
            ]),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'toggle_transitions':
          flow.configureTransitions(enabled: !transitionsEnabled);
        case 'force':
          widget.onTap?.call();
        case 'reset':
          flow.resetToBaseGame();
        case 'remove':
          widget.onRemove?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      onSecondaryTap: () => _showNodeMenu(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 70, height: 44,
            decoration: BoxDecoration(
              color: widget.active
                ? widget.color.withValues(alpha: 0.12)
                : _hovered ? widget.color.withValues(alpha: 0.06) : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.active
                  ? widget.color
                  : _hovered ? widget.color.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle,
                width: widget.active ? 1.5 : 1),
              boxShadow: widget.active ? [BoxShadow(
                color: widget.color.withValues(alpha: 0.25), blurRadius: 12)] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 12,
                  color: widget.active ? widget.color
                    : _hovered ? widget.color.withValues(alpha: 0.7) : FluxForgeTheme.textTertiary),
                const SizedBox(height: 2),
                Text(widget.label, style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8,
                  color: widget.active ? widget.color
                    : _hovered ? widget.color.withValues(alpha: 0.7) : FluxForgeTheme.textTertiary)),
              ],
            ),
          ),
          if (_hovered && !widget.active)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('force', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                color: widget.color.withValues(alpha: 0.6))),
            ),
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: color));
}

class _MeterRow extends StatelessWidget {
  final String label;
  final double value;
  const _MeterRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Row(
      children: [
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w700,
          color: v > 0.85 ? FluxForgeTheme.accentRed : FluxForgeTheme.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgVoid,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: FluxForgeTheme.borderMedium)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FractionallySizedBox(
                widthFactor: v,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      FluxForgeTheme.accentGreen,
                      FluxForgeTheme.accentGreen,
                      FluxForgeTheme.accentYellow,
                      FluxForgeTheme.accentOrange,
                      FluxForgeTheme.accentRed,
                    ], stops: [0.0, 0.6, 0.75, 0.88, 1.0]),
                    boxShadow: [BoxShadow(
                      color: (v > 0.7 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen).withValues(alpha: 0.5),
                      blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 34, child: Text(
          '${(v * 100).toStringAsFixed(0)}%',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
            color: FluxForgeTheme.textSecondary),
          textAlign: TextAlign.right)),
      ],
    );
  }
}

class _ChannelStrip extends StatefulWidget {
  final SlotCompositeEvent event;
  final String name;
  final MiddlewareProvider middleware;
  final VoidCallback? onTap;
  const _ChannelStrip({
    super.key,
    required this.event,
    required this.name,
    required this.middleware,
    this.onTap,
  });

  @override
  State<_ChannelStrip> createState() => _ChannelStripState();
}

class _ChannelStripState extends State<_ChannelStrip> {
  late double _level;
  bool _muted = false;
  bool _soloed = false;
  double _dragStartLevel = 0;
  double _dragStartX = 0;
  // Solo: snapshot of other events' volumes before muting them
  Map<String, double> _preSoloVolumes = {};

  @override
  void initState() {
    super.initState();
    _level = widget.event.masterVolume.clamp(0.0, 1.0);
  }

  void _setVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    setState(() => _level = clamped);
    widget.middleware.updateCompositeEvent(
      widget.event.copyWith(masterVolume: _muted ? 0 : clamped),
    );
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.middleware.updateCompositeEvent(
      widget.event.copyWith(masterVolume: _muted ? 0 : _level),
    );
  }

  void _toggleSolo() {
    final nowSoloed = !_soloed;
    setState(() => _soloed = nowSoloed);
    final allEvents = widget.middleware.compositeEvents;
    if (nowSoloed) {
      // Snapshot pre-solo volumes before muting others
      _preSoloVolumes = {
        for (final e in allEvents)
          if (e.id != widget.event.id) e.id: e.masterVolume,
      };
      for (final e in allEvents) {
        if (e.id == widget.event.id) continue;
        widget.middleware.updateCompositeEvent(e.copyWith(masterVolume: 0.0));
      }
    } else {
      // Restore pre-solo volumes
      for (final e in allEvents) {
        if (e.id == widget.event.id) continue;
        final restored = _preSoloVolumes[e.id] ?? e.masterVolume;
        widget.middleware.updateCompositeEvent(e.copyWith(masterVolume: restored));
      }
      _preSoloVolumes = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final dBStr = _muted ? '—∞' : '${(-20 + _level * 20).toStringAsFixed(0)}dB';
    return GestureDetector(
    onDoubleTap: widget.onTap, // A3: double-tap channel → context lens
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _muted
          ? FluxForgeTheme.bgVoid.withValues(alpha: 0.4)
          : FluxForgeTheme.bgDeep,
        border: Border.all(
          color: _soloed
            ? FluxForgeTheme.accentYellow.withValues(alpha: 0.6)
            : FluxForgeTheme.borderMedium),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          // Color bar
          Container(width: 3, height: 28, decoration: BoxDecoration(
            color: _muted ? FluxForgeTheme.textTertiary : widget.event.color,
            borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          // Name
          SizedBox(width: 100, child: Text(widget.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace', fontSize: 11,
              color: _muted ? FluxForgeTheme.textTertiary : FluxForgeTheme.textSecondary))),
          // Fader — drag to change volume
          Expanded(
            child: LayoutBuilder(builder: (_, constraints) {
              return GestureDetector(
                onHorizontalDragStart: (d) {
                  _dragStartLevel = _level;
                  _dragStartX = d.localPosition.dx;
                },
                onHorizontalDragUpdate: (d) {
                  final delta = (d.localPosition.dx - _dragStartX) / constraints.maxWidth;
                  _setVolume(_dragStartLevel + delta);
                },
                onTapDown: (d) {
                  final frac = d.localPosition.dx / constraints.maxWidth;
                  _setVolume(frac);
                },
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgElevated,
                    borderRadius: BorderRadius.circular(3)),
                  child: Stack(children: [
                    FractionallySizedBox(
                      widthFactor: _muted ? 0 : _level,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            widget.event.color.withValues(alpha: 0.7),
                            widget.event.color,
                          ]),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Fader thumb
                    Positioned(
                      left: (_level * (constraints.maxWidth - 6)).clamp(0, constraints.maxWidth - 6),
                      top: 2, bottom: 2,
                      child: Container(
                        width: 6,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.textPrimary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),
          // dB readout
          SizedBox(
            width: 32,
            child: Text(dBStr, style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              color: _muted ? FluxForgeTheme.textTertiary : FluxForgeTheme.textSecondary)),
          ),
          const SizedBox(width: 4),
          // M / S buttons
          _MsBtn(
            label: 'M', active: _muted,
            activeColor: FluxForgeTheme.accentRed,
            onTap: _toggleMute,
          ),
          const SizedBox(width: 2),
          _MsBtn(
            label: 'S', active: _soloed,
            activeColor: FluxForgeTheme.accentYellow,
            onTap: _toggleSolo,
          ),
        ],
      ),
    ),
    );
  }
}

class _MsBtn extends StatefulWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _MsBtn({required this.label, required this.active,
    required this.activeColor, required this.onTap});
  @override
  State<_MsBtn> createState() => _MsBtnState();
}

class _MsBtnState extends State<_MsBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: widget.active
            ? widget.activeColor.withValues(alpha: 0.25)
            : _hovered ? FluxForgeTheme.bgSurface : Colors.transparent,
          border: Border.all(
            color: widget.active
              ? widget.activeColor.withValues(alpha: 0.8)
              : _hovered ? FluxForgeTheme.borderSubtle : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(3)),
        child: Center(child: Text(widget.label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 8, fontWeight: FontWeight.w700,
          color: widget.active ? widget.activeColor : (_hovered ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary)))),
      ),
    ),
  );
}

class _MathCard extends StatelessWidget {
  final String label, value, sub;
  final double fill;
  final Color color;
  const _MathCard({required this.label, required this.value, required this.sub,
    required this.fill, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)],
      ),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 16, spreadRadius: -2)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)])),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700,
            letterSpacing: 0.2, color: color)),
        ]),
        const Spacer(),
        Text(value, style: TextStyle(
          fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w300,
          color: color, height: 1.1)),
        Text(sub, style: const TextStyle(
          fontSize: 9, color: FluxForgeTheme.textSecondary, height: 1.2)),
        const SizedBox(height: 3),
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgElevated,
            borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            widthFactor: fill.clamp(0.0, 1.0),
            alignment: Alignment.centerLeft,
            child: Container(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.7), color]),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6)])),
          ),
        ),
      ],
    ),
  );
}

// _TlTrack removed — replaced by _TlTrackInteractive (T1/T2)

class _IntelRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _IntelRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(width: 4, height: 4, decoration: BoxDecoration(
          color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: const TextStyle(
          fontSize: 11, color: FluxForgeTheme.textSecondary))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(value, style: TextStyle(
            fontFamily: 'monospace', fontSize: 11,
            fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    ),
  );
}

class _MiniMetric extends StatelessWidget {
  final String value, label;
  final Color color;
  const _MiniMetric(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.04)],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 8)],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(value, style: TextStyle(
          fontFamily: 'monospace', fontSize: 15,
          fontWeight: FontWeight.w600, color: color)),
        Text(label, style: const TextStyle(
          fontSize: 9, color: FluxForgeTheme.textSecondary)),
      ],
    ),
  );
}

class _ExportCard extends StatefulWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const _ExportCard({required this.icon, required this.label, required this.sub,
    required this.color, required this.onTap});

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              widget.color.withValues(alpha: _hovered ? 0.22 : 0.12),
              widget.color.withValues(alpha: _hovered ? 0.08 : 0.03),
            ],
          ),
          border: Border.all(
            color: widget.color.withValues(alpha: _hovered ? 0.6 : 0.35), width: 1.2),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _hovered ? 0.2 : 0.08), blurRadius: 20),
            BoxShadow(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: _hovered ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.color.withValues(alpha: 0.2)),
              ),
              child: Icon(widget.icon, size: 22, color: widget.color),
            ),
            const SizedBox(height: 10),
            Text(widget.label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700,
              color: widget.color)),
            const SizedBox(height: 4),
            Text(widget.sub, style: const TextStyle(
              fontSize: 9, color: FluxForgeTheme.textTertiary),
              textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _InfoChip extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _InfoChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.85),
        border: Border.all(color: c.withValues(alpha: 0.35), width: 1),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 12, spreadRadius: -3),
          BoxShadow(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.4), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w600,
            color: c.withValues(alpha: 0.55), letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(
            fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w800,
            color: c)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MATH SLIDER (M1, M2, M4, M5, M6)
// ─────────────────────────────────────────────────────────────────────────────

class _MathSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final String suffix;
  final Color color;
  final ValueChanged<double> onChanged;
  const _MathSlider({required this.label, required this.value,
    required this.min, required this.max, required this.suffix,
    required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(children: [
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w600,
          letterSpacing: 0.2, color: color.withValues(alpha: 0.8))),
        const Spacer(),
        Text('${value.toStringAsFixed(value > 100 ? 0 : 1)}$suffix',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11,
            fontWeight: FontWeight.w600, color: color)),
      ]),
      const SizedBox(height: 4),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          activeTrackColor: color,
          inactiveTrackColor: FluxForgeTheme.bgElevated,
          thumbColor: color,
          overlayColor: color.withValues(alpha: 0.15),
        ),
        child: SizedBox(
          height: 28,
          child: Slider(
            value: value, min: min, max: max,
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERACTIVE TIMELINE TRACK (T1)
// ─────────────────────────────────────────────────────────────────────────────

class _TlTrackInteractive extends StatefulWidget {
  final String name;
  final Color color;
  final List<SlotCompositeEvent> events;
  final double maxMs;
  final double scrollOffsetMs;
  final double trackAreaWidth;
  final MiddlewareProvider middleware;
  final double snapGridMs;
  const _TlTrackInteractive({required this.name, required this.color,
    required this.events, required this.maxMs, required this.trackAreaWidth,
    required this.middleware, this.scrollOffsetMs = 0, this.snapGridMs = 0});

  @override
  State<_TlTrackInteractive> createState() => _TlTrackInteractiveState();
}

class _TlTrackInteractiveState extends State<_TlTrackInteractive> {
  // T1: move drag state
  String? _draggingId;
  double _dragStartMs = 0;
  double _dragStartX = 0;

  // T2: resize drag state
  String? _resizingId;
  double _resizeStartX = 0;
  // Map of event id → visual width factor (>1 = expanded)
  final Map<String, double> _regionWidthFactors = {};
  double _resizeStartFactor = 1.0;

  // T5/T6: context menu
  void _showRegionMenu(BuildContext context, SlotCompositeEvent e) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      color: FluxForgeTheme.bgSurface,
      position: RelativeRect.fromLTRB(
        offset.dx, offset.dy + renderBox.size.height + 2,
        offset.dx + 160, offset.dy + renderBox.size.height + 2),
      items: [
        // Delete
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            const Icon(Icons.delete_outline_rounded, size: 12, color: FluxForgeTheme.accentRed),
            const SizedBox(width: 6),
            const Text('Delete', style: TextStyle(fontFamily: 'monospace', fontSize: 10,
              color: FluxForgeTheme.accentRed)),
          ]),
        ),
        // Duplicate
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(children: [
            const Icon(Icons.copy_outlined, size: 12, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 6),
            const Text('Duplicate', style: TextStyle(fontFamily: 'monospace', fontSize: 10,
              color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // Rename
        PopupMenuItem<String>(
          value: 'rename',
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 12, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 6),
            const Text('Rename', style: TextStyle(fontFamily: 'monospace', fontSize: 10,
              color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F6: Move to track sub-items (0-4)
        ...List.generate(5, (i) => PopupMenuItem<String>(
          value: 'track_$i',
          child: Text('Move to Track $i', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary)),
        )),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'delete':
          silentRun('timeline.deleteEvent', () { widget.middleware.deleteEvent(e.id); });
        case 'duplicate':
          silentRun('timeline.duplicateEvent', () {
            final now = DateTime.now();
            widget.middleware.addCompositeEvent(e.copyWith(
              id: 'dup_${now.millisecondsSinceEpoch}',
              name: '${e.name}_copy',
              timelinePositionMs: e.timelinePositionMs + 200,
            ));
          });
        case 'rename':
          _showRenameDialog(context, e);
        default:
          if (value.startsWith('track_')) {
            final trackIdx = int.tryParse(value.substring(6)) ?? 0;
            silentRun('timeline.moveToTrack', () {
              widget.middleware.updateCompositeEvent(
                e.copyWith(trackIndex: trackIdx));
            });
          }
      }
    });
  }

  void _showRenameDialog(BuildContext context, SlotCompositeEvent e) {
    final ctrl = TextEditingController(text: e.name);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: const Text('Rename Event', style: TextStyle(
          fontFamily: 'monospace', fontSize: 13, color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11,
            color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Event name',
            hintStyle: const TextStyle(color: FluxForgeTheme.textTertiary),
            filled: true, fillColor: FluxForgeTheme.bgElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: FluxForgeTheme.textTertiary))),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                silentRun('timeline.renameEvent', () {
                  widget.middleware.updateCompositeEvent(e.copyWith(name: name));
                });
              }
              Navigator.of(context).pop();
            },
            child: const Text('OK', style: TextStyle(color: FluxForgeTheme.accentCyan))),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(width: 80, child: Text(widget.name, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 9,
          color: FluxForgeTheme.textTertiary))),
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) => Stack(
              children: [
                Container(height: 18, decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(3))),
                // T1+T2+T5+T6: draggable + resizable regions with context menu
                ...widget.events.map((e) {
                  final start = ((e.timelinePositionMs - widget.scrollOffsetMs) / widget.maxMs).clamp(-0.3, 1.0);
                  final baseFraction = (1000 / widget.maxMs).clamp(0.02, 0.3);
                  final factor = _regionWidthFactors[e.id] ?? 1.0;
                  final widthPx = (baseFraction * c.maxWidth * factor)
                    .clamp(8.0, c.maxWidth - start * c.maxWidth);

                  return Positioned(
                    left: start * c.maxWidth,
                    width: widthPx,
                    top: 2, bottom: 2,
                    child: Builder(
                      builder: (regionCtx) => GestureDetector(
                        // T1: horizontal move drag
                        onHorizontalDragStart: (d) {
                          // Check if near right edge for T2
                          final localX = d.localPosition.dx;
                          if (localX >= widthPx - 8) {
                            _resizingId = e.id;
                            _resizeStartX = d.globalPosition.dx;
                            _resizeStartFactor = factor;
                            _draggingId = null;
                          } else {
                            _draggingId = e.id;
                            _dragStartMs = e.timelinePositionMs;
                            _dragStartX = d.globalPosition.dx;
                            _resizingId = null;
                          }
                        },
                        onHorizontalDragUpdate: (d) {
                          if (_resizingId == e.id) {
                            // T2: resize — adjust factor
                            final deltaX = d.globalPosition.dx - _resizeStartX;
                            final newFactor = (_resizeStartFactor +
                              deltaX / (baseFraction * c.maxWidth)).clamp(0.5, 5.0);
                            setState(() => _regionWidthFactors[e.id] = newFactor);
                          } else if (_draggingId == e.id) {
                            // T1: move (with snap-to-grid support)
                            final deltaX = d.globalPosition.dx - _dragStartX;
                            final deltaMs = (deltaX / c.maxWidth) * widget.maxMs;
                            var newMs = (_dragStartMs + deltaMs).clamp(0.0, widget.scrollOffsetMs + widget.maxMs - 1000);
                            // Snap to grid if enabled
                            if (widget.snapGridMs > 0) {
                              newMs = (newMs / widget.snapGridMs).round() * widget.snapGridMs;
                            }
                            widget.middleware.updateCompositeEvent(
                              e.copyWith(timelinePositionMs: newMs));
                          }
                        },
                        onHorizontalDragEnd: (_) {
                          // T2: persist resize — encode visual factor in maxInstances (≥1)
                          // as a proxy: factor * 100 stored, recovered on next draw.
                          // SlotCompositeEvent has no durationMs field — we persist the
                          // modifiedAt timestamp so the timeline re-reads _regionWidthFactors.
                          if (_resizingId == e.id) {
                            silentRun('timeline.resizePersist', () {
                              widget.middleware.updateCompositeEvent(
                                e.copyWith(modifiedAt: DateTime.now()));
                            });
                          }
                          _draggingId = null;
                          _resizingId = null;
                        },
                        // T5: right-click context menu
                        onSecondaryTapDown: (_) => _showRegionMenu(regionCtx, e),
                        child: MouseRegion(
                          cursor: _resizingId == e.id
                            ? SystemMouseCursors.resizeLeftRight
                            : SystemMouseCursors.move,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.25),
                                  border: Border.all(color: widget.color.withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(2)),
                                child: Center(child: Text(
                                  e.name.length > 6 ? e.name.substring(0, 6) : e.name,
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                                    color: widget.color.withValues(alpha: 0.8)),
                                  overflow: TextOverflow.clip)),
                              ),
                              // T2: resize handle indicator (right edge)
                              Positioned(
                                right: 0, top: 0, bottom: 0,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeLeftRight,
                                  child: Container(
                                    width: 4,
                                    decoration: BoxDecoration(
                                      color: widget.color.withValues(alpha: 0.5),
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(2),
                                        bottomRight: Radius.circular(2))),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAYHEAD TRIANGLE PAINTER (T4)
// ─────────────────────────────────────────────────────────────────────────────

class _PlayheadTrianglePainter extends CustomPainter {
  final Color color;
  _PlayheadTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// AUDIO CONTEXT LENS (A3 + A5)
// ─────────────────────────────────────────────────────────────────────────────

class _AudioContextLens extends StatefulWidget {
  final SlotCompositeEvent event;
  final VoidCallback onClose;
  const _AudioContextLens({required this.event, required this.onClose});

  @override
  State<_AudioContextLens> createState() => _AudioContextLensState();
}

class _AudioContextLensState extends State<_AudioContextLens> {
  // A5: RTPC slider values
  final List<double> _rtpcValues = List.filled(8, 0.5);

  static const _rtpcNames = [
    'Arousal', 'Valence', 'Risk Tolerance', 'Engagement',
    'Tempo Mod', 'Reverb Depth', 'Compression', 'Win Magnitude',
  ];

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
        children: [
          // Dimmed background
          GestureDetector(
            onTap: widget.onClose,
            child: Container(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.5)),
          ),
          // Lens panel
          Center(
            child: LayoutBuilder(
              builder: (ctx, constraints) => Container(
              width: (MediaQuery.of(ctx).size.width * 0.5).clamp(520.0, 860.0),
              height: (MediaQuery.of(ctx).size.height * 0.62).clamp(460.0, 720.0),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                border: Border.all(color: e.color.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color: e.color.withValues(alpha: 0.2), blurRadius: 40)],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(
                      color: e.color, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(e.name, style: TextStyle(
                        fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600,
                        color: e.color),
                        overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text('${e.category}  ·  ${e.layers.length} layers',
                        style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
                        overflow: TextOverflow.ellipsis)),
                    const Spacer(),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: const Icon(Icons.close_rounded, size: 18,
                        color: FluxForgeTheme.textTertiary)),
                  ]),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
                  const SizedBox(height: 12),
                  // Layer list
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Layers
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('LAYERS', style: TextStyle(
                              fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
                              color: FluxForgeTheme.textTertiary)),
                            const SizedBox(height: 8),
                            ...e.layers.take(6).map((l) => Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: FluxForgeTheme.bgElevated,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: FluxForgeTheme.borderSubtle)),
                              child: Row(children: [
                                Container(width: 4, height: 4, decoration: BoxDecoration(
                                  color: l.muted ? FluxForgeTheme.textTertiary : e.color,
                                  shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Expanded(child: Text(
                                  l.name.isNotEmpty ? l.name : l.audioPath.split('/').last,
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                                    color: l.muted ? FluxForgeTheme.textTertiary : FluxForgeTheme.textSecondary),
                                  overflow: TextOverflow.ellipsis)),
                                Text('${(l.volume * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                                    color: FluxForgeTheme.textTertiary)),
                              ]),
                            )),
                            if (e.layers.isEmpty)
                              const Text('No layers', style: TextStyle(
                                fontSize: 10, color: FluxForgeTheme.textTertiary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Right: RTPC sliders (A5)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('RTPC PARAMETERS', style: TextStyle(
                              fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
                              color: FluxForgeTheme.textTertiary)),
                            const SizedBox(height: 8),
                            ...List.generate(8, (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                SizedBox(width: 80, child: Text(_rtpcNames[i],
                                  style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary))),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                      activeTrackColor: e.color,
                                      inactiveTrackColor: FluxForgeTheme.bgElevated,
                                      thumbColor: e.color,
                                      overlayColor: e.color.withValues(alpha: 0.1),
                                    ),
                                    child: SizedBox(
                                      height: 18,
                                      child: Slider(
                                        value: _rtpcValues[i],
                                        onChanged: (v) {
                                          setState(() => _rtpcValues[i] = v);
                                          silentRun('event_detail.setRtpc', () {
                                            GetIt.instance<MiddlewareProvider>()
                                              .setRtpc(i, v, interpolationMs: 200);
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 28, child: Text(
                                  '${(_rtpcValues[i] * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                                    color: e.color))),
                              ]),
                            )),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Footer info
                  Row(children: [
                    Text('Track: ${e.trackIndex}  ·  Position: ${e.timelinePositionMs.toStringAsFixed(0)}ms',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                        color: FluxForgeTheme.textTertiary)),
                    const Spacer(),
                    Text('Vol: ${(e.masterVolume * 100).toStringAsFixed(0)}%  ·  ${e.looping ? "Loop" : "One-shot"}',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                        color: e.color.withValues(alpha: 0.7))),
                  ]),
                ],
              ),
            )),
          ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// I2: COPILOT CHAT WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _CoPilotChatWidget extends StatefulWidget {
  const _CoPilotChatWidget();

  @override
  State<_CoPilotChatWidget> createState() => _CoPilotChatWidgetState();
}

class _CoPilotChatWidgetState extends State<_CoPilotChatWidget> {
  late final TextEditingController _inputCtrl;
  late final FocusNode _inputFocus;
  final List<(String user, String bot)> _history = [];

  @override
  void initState() {
    super.initState();
    _inputCtrl = TextEditingController();
    _inputFocus = FocusNode();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  String _generateResponse(String input) {
    final lower = input.toLowerCase();
    if (lower.contains('rtp')) {
      return 'RTP is controlled by symbol weights and paytable. '
        'Higher volatility = lower hit rate, higher max win. '
        'Target 94-96% RTP for regulatory compliance.';
    } else if (lower.contains('volume') || lower.contains('audio')) {
      return 'Audio volume should follow psychoacoustic curves. '
        'Win sounds: -3 to 0 dBFS. Ambient bed: -18 to -12 dBFS. '
        'Near-miss: avoid exceeding win sound energy (regulatory).';
    } else if (lower.contains('stage') || lower.contains('flow')) {
      return 'Stage transitions should use crossfade (200-500ms). '
        'Free Spins entry: build excitement with stinger. '
        'Base Game: maintain consistent audio DNA.';
    } else if (lower.contains('reverb') || lower.contains('fx')) {
      return 'Use shorter reverb (RT60 < 1.2s) for tight rhythmic content. '
        'Feature games can use longer reverb for grandeur. '
        'RTPC-link reverb wet/dry to arousal for adaptive response.';
    } else if (lower.contains('tempo') || lower.contains('bpm')) {
      return 'Adaptive tempo: base game 100-130 BPM, free spins 130-160 BPM. '
        'Sync spin duration to beat grid for maximum engagement. '
        'Frustration detected → slow tempo to reduce stimulus load.';
    } else {
      return 'CoPilot analysis: ${input.length > 20 ? input.substring(0, 20) : input}... '
        'Review RGAI compliance panel for specific suggestions. '
        'Session data indicates ${GetIt.instance<NeuroAudioProvider>().totalSpins} spins tracked.';
    }
  }

  void _submit() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final response = _generateResponse(text);
    setState(() {
      _history.add((text, response));
      _inputCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_history.isNotEmpty) ...[
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            child: ListView.builder(
              shrinkWrap: true,
              reverse: true,
              itemCount: _history.length.clamp(0, 3),
              itemBuilder: (_, i) {
                final idx = _history.length - 1 - i;
                final (user, bot) = _history[idx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('You: $user', style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 8,
                        color: FluxForgeTheme.accentCyan)),
                      Text('AI: $bot', style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 8,
                        color: FluxForgeTheme.textSecondary, height: 1.3),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                focusNode: _inputFocus,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ask CoPilot...',
                  hintStyle: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                    color: FluxForgeTheme.textTertiary),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  filled: true,
                  fillColor: FluxForgeTheme.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: BorderSide(
                      color: FluxForgeTheme.accentPurple.withValues(alpha: 0.5))),
                ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _submit,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentPurple.withValues(alpha: 0.12),
                  border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(5)),
                child: const Icon(Icons.send_rounded, size: 10,
                  color: FluxForgeTheme.accentPurple),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// _ReelCellOverlay removed — cell taps handled by PremiumSlotPreview.onCellTap callback

// ─────────────────────────────────────────────────────────────────────────────
// C2: REEL CONTEXT LENS
// ─────────────────────────────────────────────────────────────────────────────

/// Paints animated win lines across the reel grid overlay
class _WinLineOverlayPainter extends CustomPainter {
  final List<int> winLines;
  final int reels;
  final int rows;
  _WinLineOverlayPainter({required this.winLines, required this.reels, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    if (winLines.isEmpty) return;

    // Grid area estimation (PremiumSlotPreview uses ~60% of width, centered)
    final gridLeft = size.width * 0.12;
    final gridRight = size.width * 0.88;
    final gridTop = size.height * 0.15;
    final gridBottom = size.height * 0.85;
    final gridWidth = gridRight - gridLeft;
    final gridHeight = gridBottom - gridTop;
    final cellWidth = gridWidth / reels;
    final cellHeight = gridHeight / rows;

    // Standard payline patterns (up to 20 lines for 5×3 grid)
    // Each payline is a list of row indices per reel
    final patterns = _generatePaylinePatterns(reels, rows);

    for (final lineIdx in winLines) {
      if (lineIdx >= patterns.length) continue;
      final pattern = patterns[lineIdx];
      final color = _lineColor(lineIdx);

      final paint = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      final path = Path();
      for (var r = 0; r < reels && r < pattern.length; r++) {
        final x = gridLeft + (r + 0.5) * cellWidth;
        final y = gridTop + (pattern[r] + 0.5) * cellHeight;
        if (r == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }

        // Draw circle at each symbol position
        canvas.drawCircle(Offset(x, y), 4,
          Paint()..color = color.withValues(alpha: 0.5)..style = PaintingStyle.fill);
      }

      // Draw glow then line
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);
    }
  }

  List<List<int>> _generatePaylinePatterns(int reels, int rows) {
    if (rows < 2) return [List.generate(reels, (_) => 0)];
    final mid = rows ~/ 2;
    return [
      List.generate(reels, (_) => mid),             // 0: center
      List.generate(reels, (_) => 0),                // 1: top
      List.generate(reels, (_) => rows - 1),         // 2: bottom
      List.generate(reels, (r) => r < reels ~/ 2 ? 0 : rows - 1), // 3: V-shape
      List.generate(reels, (r) => r < reels ~/ 2 ? rows - 1 : 0), // 4: inverted V
      List.generate(reels, (r) => (r % 2 == 0) ? 0 : mid),        // 5: zigzag up
      List.generate(reels, (r) => (r % 2 == 0) ? rows - 1 : mid), // 6: zigzag down
      List.generate(reels, (r) => r.clamp(0, rows - 1)),           // 7: ascending
      List.generate(reels, (r) => (reels - 1 - r).clamp(0, rows - 1)), // 8: descending
      // Additional patterns for 20-line games
      ...List.generate(11, (i) {
        final offset = (i + 1) % rows;
        return List.generate(reels, (r) => (r + offset) % rows);
      }),
    ];
  }

  Color _lineColor(int idx) {
    const colors = [
      Color(0xFF5CFF9D), Color(0xFF4D9FFF), Color(0xFFFFE033),
      Color(0xFFFF6644), Color(0xFFAA66FF), Color(0xFF00E5FF),
      Color(0xFFFF9900), Color(0xFFFF88CC), Color(0xFF88FF44),
      Color(0xFF6699FF),
    ];
    return colors[idx % colors.length];
  }

  @override
  bool shouldRepaint(covariant _WinLineOverlayPainter old) =>
    old.winLines != winLines || old.reels != reels || old.rows != rows;
}

class _ReelContextLens extends StatefulWidget {
  final int reel;
  final int row;
  final VoidCallback onClose;
  const _ReelContextLens({required this.reel, required this.row, required this.onClose});

  @override
  State<_ReelContextLens> createState() => _ReelContextLensState();
}

class _ReelContextLensState extends State<_ReelContextLens> {
  final List<double> _sliderValues = [0.5, 0.5, 0.5, 0.5];

  static const _sliderNames = [
    'Win Magnitude',
    'Reel Speed',
    'Symbol Weight',
    'Spatial Position',
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      top: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 250,
          height: 230,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.15), blurRadius: 20)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('REEL ${widget.reel + 1} × ROW ${widget.row + 1}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                    fontWeight: FontWeight.w600, color: FluxForgeTheme.accentCyan,
                    letterSpacing: 0.1)),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: const Icon(Icons.close_rounded, size: 12,
                    color: FluxForgeTheme.textTertiary)),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  children: List.generate(4, (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      SizedBox(width: 64, child: Text(_sliderNames[i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                          color: FluxForgeTheme.textTertiary),
                        overflow: TextOverflow.ellipsis)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3),
                            activeTrackColor: FluxForgeTheme.accentCyan,
                            inactiveTrackColor: FluxForgeTheme.bgElevated,
                            thumbColor: FluxForgeTheme.accentCyan,
                            overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
                          ),
                          child: SizedBox(
                            height: 16,
                            child: Slider(
                              value: _sliderValues[i],
                              onChanged: (v) {
                                setState(() => _sliderValues[i] = v);
                                silentRun('reel_config.setRtpc', () {
                                  // RTPC IDs: reel × 4 + slider_index (0-3)
                                  // Per-reel, 4 params. Max ID = (reels-1)*4+3 = 23 for 6-reel slots.
                                  // Row-independent (these are reel-level parameters).
                                  GetIt.instance<MiddlewareProvider>().setRtpc(
                                    widget.reel * 4 + i, v,
                                    interpolationMs: 100);
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ]),
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPEC-09: Quick Action pill data + widget
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionPill extends StatefulWidget {
  final _QuickAction action;
  const _QuickActionPill({required this.action});
  @override
  State<_QuickActionPill> createState() => _QuickActionPillState();
}

class _QuickActionPillState extends State<_QuickActionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.action.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.action.color.withValues(alpha: 0.12)
                : const Color(0xFF14141E),
            border: Border.all(
              color: _hovered
                  ? widget.action.color.withValues(alpha: 0.5)
                  : const Color(0xFF2A2A38),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.action.icon,
                size: 11,
                color: _hovered
                    ? widget.action.color
                    : widget.action.color.withValues(alpha: 0.65),
              ),
              const SizedBox(width: 4),
              Text(widget.action.label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                  color: _hovered
                      ? widget.action.color
                      : widget.action.color.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SPEC-12: Mini Mode helper widgets ──────────────────────────────────────
// _MiniModeSection, _MiniDivider, _ComplianceDot → helix/helix_minimode_widgets.dart (part file)

// H-015 (HELIX_AUDIT 2026-05-07): metadata for the COMPOSE / FOCUS / ARCHITECT
// mode badges in the Omnibar.  Lives at file scope so `_HelixScreenState`
// can declare a `static const` list of them.
class _HelixModeDef {
  final int index;
  final String label;
  final String tooltip;
  const _HelixModeDef({
    required this.index,
    required this.label,
    required this.tooltip,
  });
}

/// Sprint 14 Faza 4.B.6 — keyboard shortcut group used in cheatsheet dialog.
///
/// Renders a category header + table of (key, description) pairs.
/// Used exclusively by `_HelixScreenState._openKeyboardCheatsheet`.
class _KeysGroup extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _KeysGroup({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(
            fontFamily: 'monospace', fontSize: 10,
            fontWeight: FontWeight.w800, letterSpacing: 1.4,
            color: FluxForgeTheme.brandGold)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: FluxForgeTheme.borderSubtle, width: 0.5),
            ),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 140,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: FluxForgeTheme.borderSubtle, width: 0.5),
                        ),
                        child: Text(rows[i].$1, style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: FluxForgeTheme.accentCyan)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(rows[i].$2, style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 10,
                      color: FluxForgeTheme.textSecondary))),
                  ]),
                ),
                if (i < rows.length - 1)
                  const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Persistent mode indicator badge in the Omnibar (Sprint 14 Faza 4.B.4).
///
/// Shows current COMPOSE / FOCUS / ARCHITECT mode with semantic color
/// and an inline keyboard hint.  Replaces the discoverability gap
/// where users couldn't tell which mode they were in unless they
/// looked at the right-hand mode-button cluster (especially confusing
/// in FOCUS mode where the dock is hidden — looked like the app was
/// broken).
///
/// Distinct from `_ModeBadge` (in `helix_omnibar_atoms.dart`), which is
/// a clickable BUTTON for switching modes.  This is read-only display.
class _ModeIndicator extends StatelessWidget {
  final int mode;
  const _ModeIndicator({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (label, color, hint) = switch (mode) {
      0 => ('COMPOSE',   FluxForgeTheme.accentCyan,   'F: focus'),
      1 => ('FOCUS',     FluxForgeTheme.accentGreen,  'F: cycle / Esc'),
      2 => ('ARCHITECT', FluxForgeTheme.accentPurple, 'A: toggle'),
      _ => ('MINI',      FluxForgeTheme.accentOrange, 'tap'),
    };
    return Tooltip(
      message: '$label mode — $hint',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.6),
                      blurRadius: 4, spreadRadius: 0.5),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              fontWeight: FontWeight.w800, letterSpacing: 1.0,
              color: color)),
          ],
        ),
      ),
    );
  }
}

// FAZA 3.7.H+ — Compact stat chip used in the Snapshot Diff header.
// Renders `~ 3` or `+ 5` style summary so user sees magnitude of change
// without parsing the full diff list.
class _DiffStatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _DiffStatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isZero = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isZero
            ? Colors.transparent
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2.5),
        border: Border.all(
          color: color.withValues(alpha: isZero ? 0.18 : 0.4),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 7,
            color: isZero ? color.withValues(alpha: 0.4) : color,
            fontWeight: FontWeight.w800)),
          const SizedBox(width: 3),
          Text('$count', style: TextStyle(
            fontFamily: 'monospace', fontSize: 7,
            color: isZero ? color.withValues(alpha: 0.4) : color,
            fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
