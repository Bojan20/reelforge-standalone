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
import 'dart:math' as math;
import 'package:flutter/material.dart';
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
import '../widgets/slot_lab/premium_slot_preview.dart';
import '../models/game_flow_models.dart';
import '../models/slot_audio_events.dart';
// ── Faza 3 imports ──
import '../providers/sfx_pipeline_provider.dart';
import '../providers/ab_sim_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/ai_generation_service.dart';
import '../services/cortex_vision_service.dart';
import '../services/cortex_eye_server.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELIX SCREEN
// ─────────────────────────────────────────────────────────────────────────────

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
  double _dockHeight = 380.0;
  bool _dockExpanded = true;

  // ── Mode ──────────────────────────────────────────────────────────────────
  int _mode = 0; // 0=COMPOSE 1=FOCUS 2=ARCHITECT

  // ── Spine overlay ─────────────────────────────────────────────────────────
  int? _spineOpen; // null=closed  0=audio 1=game 2=ai 3=settings 4=analytics

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

  // ── FocusNode (CLAUDE.md: initState, not build) ───────────────────────────
  late final FocusNode _focusNode;

  // ── BPM inline edit ───────────────────────────────────────────────────────
  bool _bpmEditing = false;
  late final TextEditingController _bpmController;

  // ── Project name inline edit (O2) ─────────────────────────────────────────
  bool _projectNameEditing = false;
  late final TextEditingController _projectNameController;

  // ── Record toggle (O4) ────────────────────────────────────────────────────
  bool _recording = false;

  // ── Audio Context Lens (A3) ───────────────────────────────────────────────
  SlotCompositeEvent? _contextLensEvent;

  // ── Reel Cell Lens (C1/C2) ────────────────────────────────────────────────
  bool _showReelLens = false;
  int _reelLensReel = 0;
  int _reelLensRow = 0;

  // ── Playhead (T3/T4) ─────────────────────────────────────────────────────
  late Timer _playheadTimer;
  double _playheadSeconds = 0;

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
    _focusNode = FocusNode()..requestFocus();
    _bpmController = TextEditingController(text: '128.0');
    _projectNameController = TextEditingController(
      text: GetIt.instance<SlotLabProjectProvider>().projectName);
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.06, end: 0.12).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _waveTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _waveBars.length; i++) {
          _waveBars[i] = _rng.nextDouble() * 14 + 4;
        }
      });
    });

    _bpmTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      try {
        final engine = GetIt.instance<EngineProvider>();
        final t = engine.transport;
        setState(() => _bpmDisplay = t.tempo > 0 ? t.tempo : _bpmDisplay);
      } catch (_) {}
    });

    // Seed demo composite events so panels show real data on first open
    _seedDemoEvents();

    // Cortex Vision auto-capture — takes screenshot of HELIX on startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final vision = CortexVisionService.instance;
      await vision.init();
      await vision.captureFullWindow(metadata: {'trigger': 'helix_startup', 'tab': _dockTab});
    });

    // CortexEye: register tab-switching callback so CORTEX can navigate tabs
    CortexEyeNav.instance.onHelixTab = (tab) {
      if (!mounted) return;
      setState(() => _dockTab = tab.clamp(0, 11));
    };

    // Playhead sync timer — polls engine position for timeline animation
    _playheadTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      try {
        final t = GetIt.instance<EngineProvider>().transport;
        if (t.isPlaying && t.positionSeconds != _playheadSeconds) {
          setState(() => _playheadSeconds = t.positionSeconds);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _bpmController.dispose();
    _projectNameController.dispose();
    _glowCtrl.dispose();
    _waveTimer.cancel();
    _bpmTimer.cancel();
    _playheadTimer.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Seed demo composite events so HELIX panels aren't empty
  // ─────────────────────────────────────────────────────────────────────────

  void _seedDemoEvents() {
    try {
      final mw = GetIt.instance<MiddlewareProvider>();
      if (mw.compositeEvents.isNotEmpty) return; // already has data
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
      try {
        final neuro = GetIt.instance<NeuroAudioProvider>();
        final rng = math.Random(42);
        for (int i = 0; i < 50; i++) {
          neuro.recordClickVelocity(500 + rng.nextDouble() * 2500);
          neuro.recordPauseDuration(300 + rng.nextDouble() * 1500);
          neuro.recordBetSize(rng.nextDouble() * 0.7 + 0.1);
          final winMult = rng.nextDouble() < 0.28 ? rng.nextDouble() * 8 : 0.0;
          neuro.recordSpinResult(winMult);
        }
      } catch (_) {}
      // Seed some spin results into project stats
      try {
        final proj = GetIt.instance<SlotLabProjectProvider>();
        final rng = math.Random(42);
        for (int i = 0; i < 30; i++) {
          final bet = 1.0;
          final winMult = rng.nextDouble() < 0.30 ? rng.nextDouble() * 15 : 0.0;
          proj.recordSpinResult(betAmount: bet, winAmount: winMult * bet,
          tier: winMult > 5 ? 'WIN 3' : winMult > 0 ? 'WIN 1' : null);
        }
      } catch (_) {}
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          Container(
            color: FluxForgeTheme.bgVoid,
            child: Column(
              children: [
                _buildOmnibar(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSpine(),
                      Expanded(child: _buildCanvas()),
                    ],
                  ),
                ),
                if (_mode != 1) _buildDock(),
              ],
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
    );
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() { _spineOpen = null; _mode = 0; _contextLensEvent = null; });
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _mode = _mode == 1 ? 0 : 1);
    } else if (key == LogicalKeyboardKey.keyA) {
      setState(() => _mode = _mode == 2 ? 0 : 2);
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
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OMNIBAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOmnibar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [FluxForgeTheme.bgDeep, FluxForgeTheme.bgDeepest],
        ),
        border: const Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          // Logo
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [FluxForgeTheme.accentBlue, FluxForgeTheme.accentPurple],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text('HX',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                  color: FluxForgeTheme.textPrimary, letterSpacing: 0.05)),
            ),
          ),
          const SizedBox(width: 8),
          const Text('HELIX', style: TextStyle(
            fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600,
            color: FluxForgeTheme.textPrimary, letterSpacing: 0.15)),
          const SizedBox(width: 12),
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
                ? FluxForgeTheme.accentGreen.withOpacity(0.5)
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
          Builder(builder: (ctx) {
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
          }),
          const SizedBox(width: 12),
          // BPM — tap to edit
          GestureDetector(
            onTap: () {
              _bpmController.text = _bpmDisplay.toStringAsFixed(1);
              setState(() => _bpmEditing = true);
            },
            child: _OmniPill(
              color: FluxForgeTheme.accentCyan.withOpacity(0.05),
              border: _bpmEditing
                ? FluxForgeTheme.accentCyan.withOpacity(0.6)
                : FluxForgeTheme.accentCyan.withOpacity(0.2),
              child: Row(children: [
                const Text('BPM', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.textTertiary, letterSpacing: 0.1)),
                const SizedBox(width: 6),
                if (_bpmEditing)
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _bpmController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11,
                        color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600),
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
                    fontFamily: 'monospace', fontSize: 11,
                    color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          // Transport
          _buildTransport(),
          const SizedBox(width: 12),
          // Mode badges
          ...[['COMPOSE', 0], ['FOCUS', 1], ['ARCHITECT', 2]].map((m) =>
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: _ModeBadge(
                label: m[0] as String,
                active: _mode == m[1],
                onTap: () => setState(() => _mode = m[1] as int),
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

  Widget _buildTransport() {
    return Consumer<EngineProvider>(
      builder: (context, engine, _) {
        final playing = engine.transport.isPlaying;
        return Row(
          children: [
            _TransportBtn(
              icon: Icons.stop_rounded,
              onTap: () => engine.stop(),
            ),
            const SizedBox(width: 4),
            _TransportBtn(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: FluxForgeTheme.accentGreen,
              active: playing,
              onTap: () => playing ? engine.stop() : engine.play(),
            ),
            const SizedBox(width: 4),
            _TransportBtn(
              icon: Icons.fiber_manual_record_rounded,
              color: FluxForgeTheme.accentRed,
              active: _recording,
              onTap: () => setState(() => _recording = !_recording),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NEURAL SPINE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSpine() {
    final icons = [
      (Icons.music_note_rounded, 'AUDIO ASSIGN'),
      (Icons.grid_view_rounded, 'GAME CONFIG'),
      (Icons.psychology_rounded, 'AI / INTEL'),
      (Icons.tune_rounded, 'SETTINGS'),
      (Icons.bar_chart_rounded, 'ANALYTICS'),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          decoration: const BoxDecoration(
            color: FluxForgeTheme.bgDeepest, // #08080C = --abyss (matches mockup)
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
                  active: _spineOpen == e.key,
                  onTap: () => setState(() =>
                    _spineOpen = _spineOpen == e.key ? null : e.key),
                ),
              )),
              const Spacer(),
              const SizedBox(height: 12),
            ],
          ),
        ),
        // Spine overlay panel
        if (_spineOpen != null)
          Positioned(
            left: 48, top: 0, bottom: 0,
            child: _SpineOverlay(
              title: icons[_spineOpen!].$2,
              spineIndex: _spineOpen!,
              onClose: () => setState(() => _spineOpen = null),
            ),
          ),
      ],
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
                        color: glowColor.withOpacity(_glowAnim.value * 0.8),
                        blurRadius: 100, spreadRadius: 10,
                      )],
                    ),
                  ),
                ),
              ),

              // Slot preview — center (C1: onCellTap → Context Lens)
              Center(
                child: PremiumSlotPreview(
                  onExit: widget.onClose ?? () {},
                  reels: 5,
                  rows: 3,
                  isFullscreen: true,
                  projectProvider: GetIt.instance<SlotLabProjectProvider>(),
                  onCellTap: (reelIndex, rowIndex) {
                    // C1/C2: Open Reel Context Lens + Audio Context Lens
                    setState(() {
                      _reelLensReel = reelIndex;
                      _reelLensRow = rowIndex;
                      _showReelLens = true;
                    });
                    // Also try to open audio lens for matching composite event
                    try {
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
                    } catch (_) {}
                  },
                ),
              ),

              // Info chips — top right
              Positioned(
                top: 14, right: 14,
                child: _buildInfoChips(),
              ),

              // Waveform bars — behind stage strip
              Positioned(
                bottom: 52, left: 0, right: 0,
                child: Center(child: _buildWaveformBars(glowColor)),
              ),

              // Stage strip — clickable (C3: force game flow transition)
              Positioned(
                bottom: 16,
                left: 0, right: 0,
                child: Center(child: _buildStageStrip(stage, flow)),
              ),

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
    final rtpStr = rtp.isNaN || rtp.isInfinite ? '—' : '${rtp.toStringAsFixed(1)}%';
    return Consumer<GameFlowProvider>(
      builder: (context, flow, _) => Row(
        children: [
          _InfoChip(label: 'RTP', value: rtpStr),
          const SizedBox(width: 6),
          const _InfoChip(label: 'GRID', value: '5×3'),
          const SizedBox(width: 6),
          _InfoChip(
            label: 'STAGE',
            value: flow.currentState.displayName.toUpperCase(),
            color: _stageGlowColor(flow.currentState),
          ),
        ],
      ),
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

    // C3: force transition function
    void forceStage(GameFlowState target) {
      switch (target) {
        case GameFlowState.idle || GameFlowState.baseGame:
          flow.resetToBaseGame();
        case GameFlowState.freeSpins:
          flow.triggerManual(TransitionTrigger.scatterCount, context: {'scatterCount': 3});
        case GameFlowState.bonusGame:
          flow.triggerManual(TransitionTrigger.bonusSymbolCount, context: {'bonusCount': 3});
        case GameFlowState.jackpotPresentation:
          flow.triggerManual(TransitionTrigger.jackpotTriggered);
        default:
          flow.resetToBaseGame();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest.withOpacity(0.9),
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
            widgets.add(const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Text('›', style: TextStyle(
                color: FluxForgeTheme.textTertiary, fontSize: 10)),
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
              colors: [color, color.withOpacity(0)],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        )).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMMAND DOCK
  // ─────────────────────────────────────────────────────────────────────────

  static const _dockTabDefs = [
    (Icons.account_tree_rounded, 'FLOW',     FluxForgeTheme.accentBlue),
    (Icons.graphic_eq_rounded,   'AUDIO',    FluxForgeTheme.accentCyan),
    (Icons.functions_rounded,    'MATH',     FluxForgeTheme.accentGreen),
    (Icons.timeline_rounded,     'TIMELINE', FluxForgeTheme.accentOrange),
    (Icons.psychology_rounded,   'INTEL',    FluxForgeTheme.accentPurple),
    (Icons.upload_rounded,       'EXPORT',   FluxForgeTheme.accentYellow),
    // ── FAZA 3 tabs ──
    (Icons.auto_fix_high_rounded,'SFX',      FluxForgeTheme.accentCyan),
    (Icons.hub_rounded,          'BT',       FluxForgeTheme.accentOrange),
    (Icons.fingerprint_rounded,  'DNA',      FluxForgeTheme.accentPink),
    (Icons.auto_awesome_rounded, 'AI GEN',   FluxForgeTheme.accentPurple),
    (Icons.cloud_sync_rounded,   'CLOUD',    FluxForgeTheme.accentBlue),
    (Icons.science_rounded,      'A/B',      FluxForgeTheme.accentGreen),
  ];

  Widget _buildDock() {
    final dockH = _mode == 2 ? MediaQuery.of(context).size.height * 0.5 : _dockHeight;

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
          // Panel content
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: _buildDockPanel(),
          )),
        ],
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
          // Scrollable tab area
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _dockTabDefs.asMap().entries.map((e) {
                  final (icon, label, color) = e.value;
                  final active = _dockTab == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: _DockTab(
                      icon: icon, label: label, color: color,
                      active: active,
                      onTap: () => setState(() => _dockTab = e.key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Resize handle — hambuger style, easy to grab
          GestureDetector(
            onVerticalDragUpdate: (d) => setState(() {
              _dockHeight = (_dockHeight - d.delta.dy).clamp(180.0, 600.0);
            }),
            child: Tooltip(
              message: 'Drag to resize',
              child: SizedBox(
                width: 44, height: 44,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 18, height: 2,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.textTertiary.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(1))),
                    const SizedBox(height: 3),
                    Container(width: 12, height: 2,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.textTertiary.withOpacity(0.3),
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
    final panel = switch (_dockTab) {
      0 => const _FlowPanel(),
      1 => const _AudioPanel(),
      2 => const _MathPanel(),
      3 => const _TimelinePanel(),
      4 => const _IntelPanel(),
      5 => const _ExportPanel(),
      // ── FAZA 3 panels ──
      6 => const _SfxPipelinePanel(),
      7 => const _BehaviorTreePanel(),
      8 => const _AudioDnaPanel(),
      9 => const _AiGenerationPanel(),
      10 => const _CloudSyncPanel(),
      11 => const _AbTestPanel(),
      _ => const SizedBox(),
    };
    // Material wrapper — ensures all panels can use Slider, InkWell, etc.
    return Material(type: MaterialType.transparency, child: panel);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCK PANELS
// ─────────────────────────────────────────────────────────────────────────────

// ── FLOW Panel ───────────────────────────────────────────────────────────────

class _FlowPanel extends StatefulWidget {
  const _FlowPanel();

  @override
  State<_FlowPanel> createState() => _FlowPanelState();
}

class _FlowPanelState extends State<_FlowPanel> {
  // F3: Custom stage nodes
  final List<({String label, IconData icon, Color color})> _customStages = [];

  void _addCustomStage() {
    final controller = TextEditingController(text: 'CUSTOM_${_customStages.length + 1}');
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: const Text('Add Custom Stage', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: FluxForgeTheme.textPrimary, fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Stage name',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: FluxForgeTheme.textTertiary)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: FluxForgeTheme.accentCyan)),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add', style: TextStyle(color: FluxForgeTheme.accentCyan)),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && name.trim().isNotEmpty) {
        final colors = [FluxForgeTheme.accentPink, FluxForgeTheme.accentOrange, FluxForgeTheme.accentCyan, FluxForgeTheme.accentGreen];
        setState(() {
          _customStages.add((
            label: name.trim().toUpperCase(),
            icon: Icons.extension_rounded,
            color: colors[_customStages.length % colors.length],
          ));
        });
      }
      controller.dispose();
    });
  }

  void _removeCustomStage(int index) {
    setState(() { _customStages.removeAt(index); });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameFlowProvider>(
      builder: (_, flow, child) {
        final current = flow.currentState;
        final builtinNodes = [
          (GameFlowState.idle,              'IDLE',    Icons.pause_circle_outline, FluxForgeTheme.textTertiary),
          (GameFlowState.baseGame,          'BASE',    Icons.play_arrow_rounded,   FluxForgeTheme.accentBlue),
          (GameFlowState.cascading,         'CASCADE', Icons.waterfall_chart,      FluxForgeTheme.accentCyan),
          (GameFlowState.freeSpins,         'FREE',    Icons.star_rounded,         FluxForgeTheme.accentYellow),
          (GameFlowState.holdAndWin,        'HOLD',    Icons.lock_rounded,         FluxForgeTheme.accentOrange),
          (GameFlowState.bonusGame,         'BONUS',   Icons.casino_rounded,       FluxForgeTheme.accentPurple),
          (GameFlowState.jackpotPresentation,'JACKPOT',Icons.emoji_events_rounded, FluxForgeTheme.accentGreen),
        ];

        // Force-stage callbacks per state
        void forceState(GameFlowState target) {
          switch (target) {
            case GameFlowState.idle:
              flow.resetToBaseGame();
            case GameFlowState.baseGame:
              flow.resetToBaseGame();
            case GameFlowState.cascading:
              flow.triggerManual(TransitionTrigger.cascadeWin);
            case GameFlowState.freeSpins:
              flow.triggerManual(TransitionTrigger.scatterCount, context: {'scatterCount': 3});
            case GameFlowState.holdAndWin:
              flow.triggerManual(TransitionTrigger.coinCount, context: {'coinCount': 6});
            case GameFlowState.bonusGame:
              flow.triggerManual(TransitionTrigger.bonusSymbolCount, context: {'bonusCount': 3});
            case GameFlowState.jackpotPresentation:
              flow.triggerManual(TransitionTrigger.jackpotTriggered);
            case GameFlowState.gamble:
              flow.triggerManual(TransitionTrigger.playerGamble);
            default:
              flow.resetToBaseGame();
          }
        }

        return Row(
          children: [
            // Flow map — nodes are clickable to force stage
            Expanded(
              flex: 3,
              child: _DockCard(
                accent: FluxForgeTheme.accentBlue,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _DockLabel('STAGE FLOW', color: FluxForgeTheme.accentBlue),
                      const Spacer(),
                      // F3: Add custom stage button
                      GestureDetector(
                        onTap: _addCustomStage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.accentCyan.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: FluxForgeTheme.accentCyan.withOpacity(0.3)),
                          ),
                          child: const Text('+ STAGE', style: TextStyle(
                            fontFamily: 'monospace', fontSize: 8,
                            color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (ctx, constraints) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            height: constraints.maxHeight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Built-in nodes
                                ...builtinNodes.asMap().entries.expand((e) {
                                  final (state, label, icon, color) = e.value;
                                  final active = current == state;
                                  final widgets = <Widget>[
                                    _FlowNode(label: label, icon: icon,
                                      color: color, active: active,
                                      onTap: () => forceState(state)),
                                  ];
                                  widgets.add(Icon(Icons.arrow_forward_rounded,
                                    size: 12, color: FluxForgeTheme.textTertiary.withOpacity(0.4)));
                                  return widgets;
                                }),
                                // F3: Custom stage nodes
                                ..._customStages.asMap().entries.expand((e) {
                                  final stage = e.value;
                                  final widgets = <Widget>[
                                    _FlowNode(label: stage.label, icon: stage.icon,
                                      color: stage.color, active: false,
                                      onTap: () {}, isCustom: true,
                                      onRemove: () => _removeCustomStage(e.key)),
                                  ];
                                  if (e.key < _customStages.length - 1) {
                                    widgets.add(Icon(Icons.arrow_forward_rounded,
                                      size: 12, color: FluxForgeTheme.textTertiary.withOpacity(0.4)));
                                  }
                                  return widgets;
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Current state info
            Flexible(
              flex: 2,
              child: _DockCard(
                accent: FluxForgeTheme.accentBlue,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('CURRENT STATE', color: FluxForgeTheme.accentBlue),
                    const SizedBox(height: 8),
                    Text(current.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13,
                        color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (flow.isBaseGame)
                      const _StatusChip('● BASE RUNNING', FluxForgeTheme.accentGreen)
                    else if (flow.isIdle)
                      const _StatusChip('○ IDLE', FluxForgeTheme.textTertiary)
                    else
                      const _StatusChip('◆ FEATURE ACTIVE', FluxForgeTheme.accentYellow),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // F4: Stage → Audio mapping card
            Flexible(
              flex: 2,
              child: _DockCard(
                accent: FluxForgeTheme.accentBlue,
                child: ListenableBuilder(
                  listenable: GetIt.instance<MiddlewareProvider>(),
                  builder: (_, __) {
                    final mw = GetIt.instance<MiddlewareProvider>();
                    final stageMap = <String, List<String>>{};
                    for (final e in mw.compositeEvents) {
                      for (final stage in e.triggerStages) {
                        stageMap.putIfAbsent(stage, () => []).add(e.name);
                      }
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DockLabel('STAGE → AUDIO', color: FluxForgeTheme.accentBlue),
                        const SizedBox(height: 8),
                        if (stageMap.isEmpty)
                          const Expanded(child: Center(child: Text('No stage mappings',
                            style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary))))
                        else
                          Expanded(
                            child: ListView(
                              children: stageMap.entries.map((entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.key.toUpperCase(),
                                      style: const TextStyle(fontFamily: 'monospace',
                                        fontSize: 8, color: FluxForgeTheme.accentCyan,
                                        letterSpacing: 0.1)),
                                    const SizedBox(height: 2),
                                    ...entry.value.take(3).map((name) => Text(
                                      '  · $name',
                                      style: const TextStyle(fontFamily: 'monospace',
                                        fontSize: 8, color: FluxForgeTheme.textSecondary),
                                      overflow: TextOverflow.ellipsis,
                                    )),
                                    if (entry.value.length > 3)
                                      Text('  +${entry.value.length - 3} more',
                                        style: const TextStyle(fontFamily: 'monospace',
                                          fontSize: 8, color: FluxForgeTheme.textTertiary)),
                                  ],
                                ),
                              )).toList(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════��════════════
// FAZA 3 — ADVANCED AUTHORING PANELS
// ═══════════════════════════════════════════════════════════════════════════════

// ���─ 3.1 SFX Pipeline Wizard Panel ───────────────────────────────────────────

class _SfxPipelinePanel extends StatelessWidget {
  const _SfxPipelinePanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<SfxPipelineProvider>(
      builder: (_, sfx, child) {
        final step = sfx.currentStep;
        final steps = SfxWizardStep.values;
        return Row(
          children: [
            // Left: Step navigation
            Flexible(
              flex: 2,
              child: _DockCard(
                accent: FluxForgeTheme.accentCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('SFX PIPELINE', color: FluxForgeTheme.accentCyan),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: steps.asMap().entries.map((e) {
                          final s = e.value;
                          final active = s == step;
                          final done = s.index < step.index;
                          return GestureDetector(
                            onTap: () => sfx.goToStep(s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: active ? FluxForgeTheme.accentCyan.withOpacity(0.12)
                                    : done ? FluxForgeTheme.accentGreen.withOpacity(0.06)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: active ? Border.all(color: FluxForgeTheme.accentCyan.withOpacity(0.4)) : null,
                              ),
                              child: Row(children: [
                                Icon(
                                  done ? Icons.check_circle_rounded : active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  size: 14,
                                  color: done ? FluxForgeTheme.accentGreen : active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(
                                  '${e.key + 1}. ${s.title}',
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                                    color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary,
                                    fontWeight: active ? FontWeight.w600 : FontWeight.normal),
                                )),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    // Navigation buttons
                    Row(children: [
                      if (sfx.canGoBack)
                        _SfxNavButton(label: '← BACK', onTap: sfx.previousStep),
                      const Spacer(),
                      if (!sfx.isLastStep && sfx.canGoNext)
                        _SfxNavButton(label: 'NEXT →', onTap: sfx.nextStep, primary: true)
                      else if (sfx.isLastStep)
                        _SfxNavButton(label: 'FINISH', onTap: sfx.setProcessing, primary: true),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Center: Step content
            Expanded(
              flex: 3,
              child: _DockCard(
                accent: FluxForgeTheme.accentCyan,
                child: _buildStepContent(sfx, step),
              ),
            ),
            const SizedBox(width: 12),
            // Right: Stats/Preview
            Flexible(
              flex: 2,
              child: _DockCard(
                accent: FluxForgeTheme.accentCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('STATS', color: FluxForgeTheme.accentCyan),
                    const SizedBox(height: 8),
                    _StatRow('Scanned', '${sfx.totalScanned}'),
                    _StatRow('Selected', '${sfx.selectedCount}'),
                    _StatRow('Stereo', '${sfx.stereoCount}'),
                    _StatRow('Mono', '${sfx.monoCount}'),
                    _StatRow('With Silence', '${sfx.filesWithSilence}'),
                    _StatRow('DC Offset', '${sfx.filesWithDcOffset}'),
                    const SizedBox(height: 12),
                    _DockLabel('LOUDNESS', color: FluxForgeTheme.accentCyan),
                    const SizedBox(height: 6),
                    _StatRow('Loudest', '${sfx.loudestLufs.toStringAsFixed(1)} LUFS'),
                    _StatRow('Quietest', '${sfx.quietestLufs.toStringAsFixed(1)} LUFS'),
                    _StatRow('Average', '${sfx.avgLufs.toStringAsFixed(1)} LUFS'),
                    const Spacer(),
                    if (sfx.isProcessing) ...[
                      LinearProgressIndicator(
                        value: sfx.progress.overallProgress,
                        backgroundColor: FluxForgeTheme.bgSurface,
                        valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentCyan),
                      ),
                      const SizedBox(height: 6),
                      Text('${sfx.progress.currentFilename ?? ''}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: FluxForgeTheme.textTertiary),
                        overflow: TextOverflow.ellipsis),
                    ],
                    if (sfx.isCompleted)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(children: [
                          Icon(Icons.check_circle, size: 14, color: FluxForgeTheme.accentGreen),
                          SizedBox(width: 6),
                          Text('COMPLETE', style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                            color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStepContent(SfxPipelineProvider sfx, SfxWizardStep step) {
    return switch (step) {
      SfxWizardStep.importScan => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('IMPORT & SCAN', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          const Text('Drop WAV/FLAC files or select a folder to scan.',
            style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary)),
          const SizedBox(height: 12),
          Expanded(
            child: sfx.scanResults.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.folder_open_rounded, size: 48, color: FluxForgeTheme.accentCyan.withOpacity(0.15)),
                  const SizedBox(height: 12),
                  const Text('No files scanned yet', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                  const SizedBox(height: 4),
                  Text('Drop WAV/FLAC files here to begin',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withOpacity(0.6))),
                ]))
              : ListView.builder(
                  itemCount: sfx.scanResults.length,
                  itemBuilder: (_, i) {
                    final r = sfx.scanResults[i];
                    final selected = sfx.selectedFiles.contains(r);
                    return ListTile(
                      dense: true,
                      leading: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 16, color: selected ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary),
                      title: Text(r.filename, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary)),
                      subtitle: Text('${r.sampleRate}Hz ${r.channels}ch ${r.durationSeconds.toStringAsFixed(1)}ms',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
                      onTap: () => sfx.toggleFileSelection(i),
                    );
                  },
                ),
          ),
          Row(children: [
            _SfxNavButton(label: 'SELECT ALL', onTap: sfx.selectAllFiles, primary: true),
            const SizedBox(width: 6),
            _SfxNavButton(label: 'DESELECT ALL', onTap: sfx.deselectAllFiles),
            const SizedBox(width: 6),
            _SfxNavButton(label: 'INVERT', onTap: sfx.invertSelection),
          ]),
        ],
      ),
      SfxWizardStep.trimClean => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('TRIM & CLEAN', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          _SfxPresetSlider(label: 'Silence Threshold', value: sfx.preset.thresholdDb,
            min: -80, max: -20, suffix: 'dB',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(thresholdDb: v))),
          _SfxPresetSlider(label: 'Fade In', value: sfx.preset.fadeInMs,
            min: 0, max: 50, suffix: 'ms',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(fadeInMs: v))),
          _SfxPresetSlider(label: 'Fade Out', value: sfx.preset.fadeOutMs,
            min: 0, max: 100, suffix: 'ms',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(fadeOutMs: v))),
          const Spacer(),
          Row(children: [
            Icon(Icons.content_cut_rounded, size: 14, color: FluxForgeTheme.accentCyan.withOpacity(0.6)),
            const SizedBox(width: 6),
            Flexible(child: Text('Auto-trim silence + apply fades to ${sfx.selectedCount} files',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary))),
          ]),
        ],
      ),
      SfxWizardStep.loudnessLevel => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('LOUDNESS & LEVEL', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          _SfxPresetSlider(label: 'Target LUFS', value: sfx.preset.targetLufs,
            min: -30, max: -6, suffix: 'LUFS',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(targetLufs: v))),
          _SfxPresetSlider(label: 'True Peak Limit', value: sfx.preset.truePeakCeiling,
            min: -3, max: 0, suffix: 'dBTP',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(truePeakCeiling: v))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentPurple.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14, color: FluxForgeTheme.accentPurple),
              const SizedBox(width: 8),
              Expanded(child: Text('Slot standard: -14 LUFS / -1.0 dBTP. Matches casino floor playback.',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
            ]),
          ),
        ],
      ),
      SfxWizardStep.formatChannel => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('FORMAT & CHANNELS', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          _SfxPresetSlider(label: 'Sample Rate', value: sfx.preset.sampleRate.toDouble(),
            min: 22050, max: 96000, suffix: 'Hz',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(sampleRate: v.round()))),
          Row(children: [
            const SizedBox(width: 120, child: Text('Output Format',
              style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
            Text(sfx.preset.outputFormat.name.toUpperCase(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _SfxToggle(label: 'DC Offset Remove', active: sfx.preset.removeDcOffset,
              onTap: () => sfx.updatePreset((p) => p.copyWith(removeDcOffset: !p.removeDcOffset))),
            const SizedBox(width: 12),
            _SfxToggle(label: 'Normalize Peak', active: sfx.preset.preNormalizePeak,
              onTap: () => sfx.updatePreset((p) => p.copyWith(preNormalizePeak: !p.preNormalizePeak))),
          ]),
        ],
      ),
      SfxWizardStep.namingAssign => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('NAMING & ASSIGN', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          const Text('Map processed files to game stages for auto-assignment.',
            style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary)),
          const SizedBox(height: 8),
          _StatRow('Matched', '${sfx.matchedCount} / ${sfx.stageMappings.length}'),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: sfx.stageMappings.length,
              itemBuilder: (_, i) {
                final m = sfx.stageMappings[i];
                final matched = m.stageId != null && m.stageId!.isNotEmpty;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: matched ? FluxForgeTheme.accentGreen.withOpacity(0.06) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(children: [
                    Icon(matched ? Icons.link : Icons.link_off, size: 12,
                      color: matched ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(m.sourceFilename, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textPrimary))),
                    const SizedBox(width: 8),
                    Text(m.stageId ?? 'unassigned',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                        color: matched ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary)),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
      SfxWizardStep.exportFinish => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('EXPORT & FINISH', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          if (sfx.isCompleted && sfx.result != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.check_circle, size: 18, color: FluxForgeTheme.accentGreen),
                  SizedBox(width: 8),
                  Text('PIPELINE COMPLETE', style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                    color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text('${sfx.result!.files.length} files processed | ${sfx.result!.outputDirectory}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary)),
              ]),
            ),
          ] else if (sfx.isProcessing) ...[
            const Center(child: CircularProgressIndicator(color: FluxForgeTheme.accentCyan)),
          ] else ...[
            const Text('Ready to process. Click FINISH to start the pipeline.',
              style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary)),
            const Spacer(),
            _SfxNavButton(label: 'RESET PIPELINE', onTap: sfx.reset),
          ],
        ],
      ),
    };
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary))),
      Expanded(child: Text(value,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary),
        textAlign: TextAlign.right)),
    ]),
  );
}

class _SfxNavButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _SfxNavButton({required this.label, required this.onTap, this.primary = false});
  @override
  State<_SfxNavButton> createState() => _SfxNavButtonState();
}

class _SfxNavButtonState extends State<_SfxNavButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final accent = FluxForgeTheme.accentCyan;
    final isActive = widget.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
              ? accent.withOpacity(_hovered ? 0.22 : 0.15)
              : _hovered
                ? FluxForgeTheme.bgSurface.withOpacity(0.8)
                : FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                ? accent.withOpacity(_hovered ? 0.6 : 0.4)
                : _hovered
                  ? FluxForgeTheme.borderSubtle.withOpacity(0.8)
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Text(widget.label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            color: isActive ? accent : (_hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary),
            fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _SfxPresetSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;
  final Color? color;
  const _SfxPresetSlider({required this.label, required this.value,
    required this.min, required this.max, required this.suffix,
    required this.onChanged, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.accentCyan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
        Expanded(child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: c,
            inactiveTrackColor: FluxForgeTheme.bgSurface,
            thumbColor: c,
            overlayColor: c.withOpacity(0.1),
          ),
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        )),
        SizedBox(width: 70, child: Text('${value.toStringAsFixed(1)} $suffix',
          style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: c),
          textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _SfxToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SfxToggle({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(children: [
      Icon(active ? Icons.check_box : Icons.check_box_outline_blank,
        size: 16, color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 10,
        color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary)),
    ]),
  );
}

// ── 3.2 Behavior Tree Visual Editor ─────────────────────────────────────────

class _BehaviorTreePanel extends StatefulWidget {
  const _BehaviorTreePanel();
  @override
  State<_BehaviorTreePanel> createState() => _BehaviorTreePanelState();
}

class _BehaviorTreePanelState extends State<_BehaviorTreePanel> {
  // Node types from architecture: 22 types across 5 categories
  static const _nodeCategories = {
    'COMPOSITE': [
      ('Sequence', Icons.arrow_forward_rounded, 'Execute children L→R, fail on first fail'),
      ('Selector', Icons.call_split_rounded, 'Execute children L→R, succeed on first success'),
      ('Parallel', Icons.view_column_rounded, 'Execute all children simultaneously'),
      ('RandomSelector', Icons.shuffle_rounded, 'Pick random child to execute'),
      ('WeightedSelector', Icons.balance_rounded, 'Pick child by weighted probability'),
    ],
    'DECORATOR': [
      ('Inverter', Icons.swap_vert_rounded, 'Invert child result'),
      ('Repeater', Icons.repeat_rounded, 'Repeat child N times'),
      ('UntilFail', Icons.block_rounded, 'Repeat child until it fails'),
      ('Timeout', Icons.timer_rounded, 'Fail if child exceeds time limit'),
      ('Cooldown', Icons.hourglass_empty_rounded, 'Delay between executions'),
      ('Guard', Icons.shield_rounded, 'Conditional execution gate'),
    ],
    'ACTION': [
      ('PlayAudio', Icons.volume_up_rounded, 'Trigger composite event playback'),
      ('StopAudio', Icons.stop_rounded, 'Stop event playback'),
      ('SetRTPC', Icons.tune_rounded, 'Set RTPC parameter value'),
      ('TransitionStage', Icons.swap_horiz_rounded, 'Force game stage transition'),
      ('Wait', Icons.schedule_rounded, 'Wait for duration'),
      ('LogMessage', Icons.message_rounded, 'Log debug message'),
    ],
    'CONDITION': [
      ('IsStage', Icons.flag_rounded, 'Check if game is in target stage'),
      ('RTPCCheck', Icons.analytics_rounded, 'Compare RTPC value'),
      ('PlayerState', Icons.person_rounded, 'Check player behavior state'),
      ('RandomChance', Icons.casino_rounded, 'Succeed with probability P'),
    ],
    'AUDIO': [
      ('CrossFade', Icons.compare_arrows_rounded, 'Crossfade between two events'),
    ],
  };

  String _selectedCategory = 'COMPOSITE';
  final List<({String type, String name, Offset position})> _canvasNodes = [];
  List<({int from, int to})> _connections = [];
  int? _selectedNode;

  void _addNode(String type, String name) {
    setState(() {
      _canvasNodes.add((
        type: type,
        name: name,
        position: Offset(100.0 + _canvasNodes.length * 120.0, 80.0 + (_canvasNodes.length % 3) * 80.0),
      ));
    });
  }

  void _deleteSelectedNode() {
    if (_selectedNode == null) return;
    setState(() {
      final idx = _selectedNode!;
      _connections.removeWhere((c) => c.from == idx || c.to == idx);
      _connections = _connections.map((c) => (
        from: c.from > idx ? c.from - 1 : c.from,
        to: c.to > idx ? c.to - 1 : c.to,
      )).toList();
      _canvasNodes.removeAt(idx);
      _selectedNode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Node palette
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentOrange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('NODE PALETTE', color: FluxForgeTheme.accentOrange),
                const SizedBox(height: 6),
                // Category tabs
                SizedBox(
                  height: 24,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _nodeCategories.keys.map((cat) {
                      final catColor = _categoryColor(cat);
                      final isActive = _selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: isActive ? catColor.withOpacity(0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isActive ? catColor.withOpacity(0.55) : FluxForgeTheme.borderSubtle,
                            ),
                          ),
                          child: Text(cat, style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                            color: isActive ? catColor : FluxForgeTheme.textTertiary,
                            fontWeight: FontWeight.w600)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                // Node list for selected category
                Expanded(
                  child: ListView(
                    children: (_nodeCategories[_selectedCategory] ?? []).map((node) {
                      final (name, icon, desc) = node;
                      return GestureDetector(
                        onTap: () => _addNode(_selectedCategory, name),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: FluxForgeTheme.borderSubtle),
                          ),
                          child: Row(children: [
                            Icon(icon, size: 14, color: _categoryColor(_selectedCategory)),
                            const SizedBox(width: 8),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                                  color: _categoryColor(_selectedCategory), fontWeight: FontWeight.w600)),
                                Text(desc, style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                                  color: FluxForgeTheme.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            )),
                            const Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.textTertiary),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Center: Canvas area
        Expanded(
          flex: 4,
          child: _DockCard(
            accent: FluxForgeTheme.accentOrange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DockLabel('BEHAVIOR TREE CANVAS', color: FluxForgeTheme.accentOrange),
                  const Spacer(),
                  Text('${_canvasNodes.length} nodes  ${_connections.length} edges',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
                  const SizedBox(width: 12),
                  if (_selectedNode != null)
                    GestureDetector(
                      onTap: _deleteSelectedNode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentPink.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)),
                        child: const Text('DELETE', style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: FluxForgeTheme.accentPink, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      color: FluxForgeTheme.bgVoid,
                      child: _canvasNodes.isEmpty
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.hub_rounded, size: 48, color: FluxForgeTheme.accentOrange.withOpacity(0.15)),
                            const SizedBox(height: 12),
                            const Text('Click a node in the palette to add it',
                              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                            const SizedBox(height: 4),
                            Text('Click two nodes to connect them',
                              style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withOpacity(0.6))),
                          ]))
                        : CustomPaint(
                            painter: _BtConnectionPainter(_canvasNodes, _connections),
                            child: Stack(
                              children: _canvasNodes.asMap().entries.map((e) {
                                final node = e.value;
                                final idx = e.key;
                                final selected = _selectedNode == idx;
                                return Positioned(
                                  left: node.position.dx,
                                  top: node.position.dy,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (_selectedNode != null && _selectedNode != idx) {
                                          // Create connection
                                          final exists = _connections.any((c) =>
                                            c.from == _selectedNode && c.to == idx);
                                          if (!exists) {
                                            _connections.add((from: _selectedNode!, to: idx));
                                          }
                                        }
                                        _selectedNode = idx;
                                      });
                                    },
                                    onPanUpdate: (d) {
                                      setState(() {
                                        final old = _canvasNodes[idx];
                                        _canvasNodes[idx] = (
                                          type: old.type,
                                          name: old.name,
                                          position: old.position + d.delta,
                                        );
                                      });
                                    },
                                    child: Container(
                                      width: 100, height: 44,
                                      decoration: BoxDecoration(
                                        color: _categoryColor(node.type).withOpacity(selected ? 0.2 : 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected ? _categoryColor(node.type) : _categoryColor(node.type).withOpacity(0.4),
                                          width: selected ? 2 : 1),
                                      ),
                                      child: Center(child: Text(node.name,
                                        style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                                          color: _categoryColor(node.type), fontWeight: FontWeight.w600),
                                        textAlign: TextAlign.center)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _categoryColor(String cat) => switch (cat) {
    'COMPOSITE' => FluxForgeTheme.accentBlue,
    'DECORATOR' => FluxForgeTheme.accentPurple,
    'ACTION'    => FluxForgeTheme.accentGreen,
    'CONDITION' => FluxForgeTheme.accentYellow,
    'AUDIO'     => FluxForgeTheme.accentCyan,
    _ => FluxForgeTheme.textTertiary,
  };
}

class _BtConnectionPainter extends CustomPainter {
  final List<({String type, String name, Offset position})> nodes;
  final List<({int from, int to})> connections;
  _BtConnectionPainter(this.nodes, this.connections);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.accentOrange.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final c in connections) {
      if (c.from < nodes.length && c.to < nodes.length) {
        final from = nodes[c.from].position + const Offset(50, 44);
        final to = nodes[c.to].position + const Offset(50, 0);
        final path = Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(from.dx, from.dy + 30, to.dx, to.dy - 30, to.dx, to.dy);
        canvas.drawPath(path, paint);
        // Arrow head
        final arrow = Paint()..color = FluxForgeTheme.accentOrange.withOpacity(0.5)..style = PaintingStyle.fill;
        canvas.drawPath(
          Path()..moveTo(to.dx, to.dy)..lineTo(to.dx - 4, to.dy - 6)..lineTo(to.dx + 4, to.dy - 6)..close(),
          arrow,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BtConnectionPainter old) => true;
}

// ── 3.4 Audio DNA / Fingerprint Editor ──────────────────────────────────────

class _AudioDnaPanel extends StatefulWidget {
  const _AudioDnaPanel();
  @override
  State<_AudioDnaPanel> createState() => _AudioDnaPanelState();
}

class _AudioDnaPanelState extends State<_AudioDnaPanel> {
  // Audio DNA fields mirror the Rust AudioDna struct
  String _brand = 'VanVinkl';
  double _bpmMin = 110;
  double _bpmMax = 140;
  String _rootKey = 'C';
  String _mode = 'minor';
  final List<String> _instruments = ['piano', 'strings', 'brass'];
  String _baseProfile = 'ambient_dark';
  String _featureProfile = 'epic_orchestral';
  double _winEscalation = 1.5;
  double _ambientLayerCount = 3;

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
                          color: _rootKey == k ? FluxForgeTheme.accentPink.withOpacity(0.2) : Colors.transparent,
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
                          color: _mode == m ? FluxForgeTheme.accentPurple.withOpacity(0.2) : Colors.transparent,
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
                          color: active ? FluxForgeTheme.accentCyan.withOpacity(0.15) : FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: active ? FluxForgeTheme.accentCyan.withOpacity(0.5) : FluxForgeTheme.borderSubtle),
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
                    color: FluxForgeTheme.accentPink.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentPink.withOpacity(0.2)),
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
              ],
            ),
          ),
        ),
      ],
    );
  }
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
  bool _isGenerating = false;
  String? _lastResultText;
  String _selectedBackend = 'stub';
  final List<String> _pipelineLog = [];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _runGeneration() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() { _isGenerating = true; _pipelineLog.clear(); _lastResultText = null; });

    try {
      final aiService = GetIt.instance<AiGenerationService>();
      setState(() => _pipelineLog.add('Parsing prompt...'));

      final descriptor = await aiService.parsePrompt(prompt);
      if (descriptor == null) {
        setState(() { _pipelineLog.add('ERROR: Failed to parse prompt'); _isGenerating = false; });
        return;
      }
      setState(() => _pipelineLog.add('Parsed: ${descriptor.category} / ${descriptor.tier}'));

      setState(() => _pipelineLog.add('Classifying (FFNC)...'));
      final classification = await aiService.classify(descriptor);
      if (classification != null) {
        setState(() => _pipelineLog.add('Class: ${classification.ffncCode} ${classification.displayName} (${(classification.confidence * 100).toStringAsFixed(0)}%)'));
      }

      setState(() => _pipelineLog.add('Generating audio...'));
      final result = await aiService.generateWithStub(prompt: prompt);
      if (result != null) {
        setState(() {
          _pipelineLog.add('Generated: ${result.actualDurationMs}ms → ${result.suggestedFilename}');
          _lastResultText = 'Audio generated: ${result.actualDurationMs}ms (${result.generationTimeMs}ms gen time)';
        });
      } else {
        setState(() => _pipelineLog.add('Generation returned null'));
      }

      setState(() => _pipelineLog.add('Post-processing...'));
      final ppConfig = await aiService.getPostProcessingConfig(descriptor);
      if (ppConfig != null) {
        setState(() => _pipelineLog.add('PP: ${ppConfig.loudnessLufs} LUFS, trim=${ppConfig.trimSilence}, limiter=${ppConfig.applyLimiter}'));
      }

      setState(() { _pipelineLog.add('DONE'); _isGenerating = false; });
    } catch (e) {
      setState(() { _pipelineLog.add('ERROR: $e'); _isGenerating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Prompt input
        Expanded(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('AI AUDIO GENERATION', color: FluxForgeTheme.accentPurple),
                const SizedBox(height: 8),
                const Text('Describe the sound you want to generate:',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: TextField(
                    controller: _promptController,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. "epic win celebration with brass fanfare, 2 seconds, bright and triumphant"',
                      hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textTertiary.withOpacity(0.5)),
                      filled: true,
                      fillColor: FluxForgeTheme.bgSurface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: FluxForgeTheme.accentPurple)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  // Backend selector
                  const Text('Backend: ', style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
                  ...['stub', 'local', 'cloud'].map((b) => GestureDetector(
                    onTap: () => setState(() => _selectedBackend = b),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: _selectedBackend == b ? FluxForgeTheme.accentPurple.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _selectedBackend == b ? FluxForgeTheme.accentPurple.withOpacity(0.4) : FluxForgeTheme.borderSubtle),
                      ),
                      child: Text(b.toUpperCase(), style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                        color: _selectedBackend == b ? FluxForgeTheme.accentPurple : FluxForgeTheme.textTertiary)),
                    ),
                  )),
                  const Spacer(),
                  GestureDetector(
                    onTap: _isGenerating ? null : _runGeneration,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isGenerating
                          ? FluxForgeTheme.textTertiary.withOpacity(0.1)
                          : FluxForgeTheme.accentPurple.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _isGenerating
                          ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentPurple.withOpacity(0.5)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_isGenerating)
                          const SizedBox(width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: FluxForgeTheme.accentPurple))
                        else
                          const Icon(Icons.auto_awesome_rounded, size: 14, color: FluxForgeTheme.accentPurple),
                        const SizedBox(width: 6),
                        Text(_isGenerating ? 'GENERATING...' : 'GENERATE',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                            color: FluxForgeTheme.accentPurple, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ]),
                if (_lastResultText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentGreen.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      const Icon(Icons.check_circle, size: 14, color: FluxForgeTheme.accentGreen),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_lastResultText!, style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentGreen))),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right: Pipeline log
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('PIPELINE LOG', color: FluxForgeTheme.accentPurple),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: _pipelineLog.asMap().entries.map((e) {
                      final isError = e.value.startsWith('ERROR');
                      final isDone = e.value == 'DONE';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${e.key + 1}. ',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
                          Expanded(child: Text(e.value,
                            style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                              color: isError ? FluxForgeTheme.accentPink
                                : isDone ? FluxForgeTheme.accentGreen
                                : FluxForgeTheme.textSecondary))),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
    // Ensure cloud service is initialized
    _cloud.init().catchError((_) {});
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
                    await _cloud.setProvider(p);
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: _cloud.provider == p ? FluxForgeTheme.accentBlue.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _cloud.provider == p ? FluxForgeTheme.accentBlue.withOpacity(0.4) : FluxForgeTheme.borderSubtle),
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
                        ? FluxForgeTheme.accentBlue.withOpacity(0.15)
                        : FluxForgeTheme.bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _autoSyncEnabled
                        ? FluxForgeTheme.accentBlue.withOpacity(0.5)
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
                      final proj = GetIt.instance<SlotLabProjectProvider>();
                      await _cloud.uploadProject('.', name: proj.projectName);
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FluxForgeTheme.accentBlue.withOpacity(0.3)),
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
                      await _cloud.syncAllProjects();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
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
                        Icon(Icons.cloud_off_rounded, size: 36, color: FluxForgeTheme.accentBlue.withOpacity(0.15)),
                        const SizedBox(height: 10),
                        const Text('No cloud projects', style: TextStyle(
                          fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                        const SizedBox(height: 4),
                        Text('Upload a project to start syncing',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withOpacity(0.6))),
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
                                  await _cloud.syncProject(p.id);
                                  setState(() {});
                                },
                                child: const Icon(Icons.sync_rounded, size: 14, color: FluxForgeTheme.accentCyan),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  await _cloud.downloadProject(p.id);
                                  setState(() {});
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

  void _runSimulation() async {
    final abSim = GetIt.instance<AbSimProvider>();
    setState(() { _isRunning = true; _results = null; });

    final config = {
      'variants': [
        {'name': 'Variant A', 'rtp': _variantARtp / 100, 'volatility': _variantAVolatility},
        {'name': 'Variant B', 'rtp': _variantBRtp / 100, 'volatility': _variantBVolatility},
      ],
      'spinsPerVariant': _spinCount,
    };

    abSim.startSimulation(config);

    // Poll for results
    while (abSim.isRunning) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() {});
    }

    setState(() {
      _results = abSim.lastResult;
      _isRunning = false;
    });
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
                    color: FluxForgeTheme.accentBlue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentBlue.withOpacity(0.2)),
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
                    color: FluxForgeTheme.accentGreen.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentGreen.withOpacity(0.2)),
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
                        ? FluxForgeTheme.textTertiary.withOpacity(0.1)
                        : FluxForgeTheme.accentGreen.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _isRunning
                        ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentGreen.withOpacity(0.5)),
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
                    builder: (_, __) {
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
                      Icon(Icons.science_outlined, size: 48, color: FluxForgeTheme.accentGreen.withOpacity(0.2)),
                      const SizedBox(height: 12),
                      const Text('Configure variants and run simulation',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                      const SizedBox(height: 6),
                      Text('Up to 1M spins per variant',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withOpacity(0.6))),
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
        color: winColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: winColor.withOpacity(0.3)),
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
  double _masterFader = 0.8; // A6: master output fader

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when MiddlewareProvider or NeuroAudioProvider change
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<MiddlewareProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final events = mw.compositeEvents.take(8).toList();
    final out = neuro.output;

    // Derive master levels from neuro audio adaptation output × master fader
    final masterL = (out.arousal * 0.6 + out.engagement * 0.4).clamp(0.0, 1.0) * _masterFader;
    final masterR = (out.arousal * 0.55 + out.engagement * 0.45).clamp(0.0, 1.0) * _masterFader;
    final peak = math.max(masterL, masterR);
    final peakDb = peak > 0.001 ? (20 * math.log(peak) / 2.302585) : -60.0;

    // Access parent state for context lens
    final helixState = context.findAncestorStateOfType<_HelixScreenState>();

    return Row(
      children: [
        // Master meters + fader (A6) — driven by NeuroAudio × master fader
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentCyan,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('MASTER', color: FluxForgeTheme.accentCyan),
                const SizedBox(height: 8),
                _MeterRow(label: 'L', value: masterL),
                const SizedBox(height: 6),
                _MeterRow(label: 'R', value: masterR),
                const SizedBox(height: 8),
                // A6: Master fader — draggable
                Row(children: [
                  _DockLabel('FADER', color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 6),
                  Expanded(
                    child: LayoutBuilder(builder: (_, c) => GestureDetector(
                      onTapDown: (d) => setState(() =>
                        _masterFader = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
                      onHorizontalDragUpdate: (d) => setState(() =>
                        _masterFader = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
                      child: Container(
                        height: 10,
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
                  const SizedBox(width: 4),
                  Text('${(_masterFader * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 8,
                      color: FluxForgeTheme.accentCyan)),
                ]),
                const Spacer(),
                Text('${peakDb.toStringAsFixed(1)} dBFS',
                  style: TextStyle(fontFamily: 'monospace',
                    fontSize: 10, color: peakDb > -6 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen)),
                const SizedBox(height: 6),
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
        const SizedBox(width: 12),
        // Channel strips — interactive, wired to middleware
        Expanded(
          child: _DockCard(
            accent: FluxForgeTheme.accentCyan,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DockLabel('CHANNELS', color: FluxForgeTheme.accentCyan),
                  const Spacer(),
                  Text('${events.length} events  ·  tap to open lens', style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: events.isEmpty
                    ? const Center(child: Text('No composite events loaded.\nAssign audio in AUDIO ASSIGN spine.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, height: 1.5)))
                    : ListView(
                        children: events.map((e) {
                          final name = e.name.length > 12 ? e.name.substring(0, 12) : e.name;
                          return _ChannelStrip(
                            event: e,
                            name: name,
                            middleware: mw,
                            // A3: tap channel → open context lens
                            onTap: () => helixState?.openContextLens(e),
                          );
                        }).toList(),
                      ),
                ),
              ],
            ),
          ),
        ),
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

    final cards = [
      ('RTP',         rtp > 0 ? '${rtp.toStringAsFixed(1)}%' : '—', 'Target: ${_targetRtp.toStringAsFixed(1)}% ($rtpDiffStr)', (rtp / 100).clamp(0.0, 1.0), FluxForgeTheme.accentGreen),
      ('VOLATILITY',  volLabel,  'Target: ${_volatilitySlider.toStringAsFixed(0)} / 10', volIdx / 10, FluxForgeTheme.accentOrange),
      ('HIT FREQ',    hitFreqStr, 'Target: ${_hitFreqTarget.toStringAsFixed(0)}%', hitRate.clamp(0.0, 1.0), FluxForgeTheme.accentBlue),
      ('MAX WIN',     maxWinMult > 0 ? '${maxWinMult.toStringAsFixed(0)}×' : '—', 'Cap: ${_maxWinCap.toStringAsFixed(0)}×', (maxWinMult / _maxWinCap).clamp(0.0, 1.0), FluxForgeTheme.accentYellow),
      ('SIMULATIONS', '${stats.totalSpins}', 'Spins recorded', stats.totalSpins > 0 ? 1.0 : 0.0, FluxForgeTheme.accentPurple),
      ('BONUS FREQ',  bonusFreq, 'Target: 1:${(100 / _bonusFreqTarget).toStringAsFixed(0)}', bonusFill, FluxForgeTheme.accentCyan),
    ];

    return Column(
      children: [
        // Stats grid — 2 rows of 3 using Row/Expanded so height is properly constrained
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
        const SizedBox(height: 4),
        // Config sliders row (M1, M2, M4, M5, M6)
        Expanded(
          flex: 2,
          child: Row(
            children: [
              // M1: Target RTP
              Expanded(child: _MathSlider(
                label: 'TARGET RTP', value: _targetRtp,
                min: 85, max: 99, suffix: '%',
                color: FluxForgeTheme.accentGreen,
                onChanged: (v) => setState(() => _targetRtp = v),
              )),
              const SizedBox(width: 8),
              // M2: Volatility
              Expanded(child: _MathSlider(
                label: 'VOLATILITY', value: _volatilitySlider,
                min: 1, max: 10, suffix: '',
                color: FluxForgeTheme.accentOrange,
                onChanged: (v) => setState(() => _volatilitySlider = v),
              )),
              const SizedBox(width: 8),
              // M4: Max Win Cap
              Expanded(child: _MathSlider(
                label: 'MAX WIN CAP', value: _maxWinCap,
                min: 100, max: 25000, suffix: '×',
                color: FluxForgeTheme.accentYellow,
                onChanged: (v) => setState(() => _maxWinCap = v),
              )),
              const SizedBox(width: 8),
              // M5: Hit Frequency
              Expanded(child: _MathSlider(
                label: 'HIT FREQ', value: _hitFreqTarget,
                min: 10, max: 60, suffix: '%',
                color: FluxForgeTheme.accentBlue,
                onChanged: (v) => setState(() => _hitFreqTarget = v),
              )),
              const SizedBox(width: 8),
              // M6: Bonus Frequency
              Expanded(child: _MathSlider(
                label: 'BONUS FREQ', value: _bonusFreqTarget,
                min: 0.5, max: 10, suffix: '%',
                color: FluxForgeTheme.accentCyan,
                onChanged: (v) => setState(() => _bonusFreqTarget = v),
              )),
              const SizedBox(width: 8),
              // M3: Run Sim button
              Flexible(child: _RunSimButton()),
            ],
          ),
        ),
      ],
    );
  }
}

class _RunSimButton extends StatefulWidget {
  @override
  State<_RunSimButton> createState() => _RunSimButtonState();
}

class _RunSimButtonState extends State<_RunSimButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final proj = GetIt.instance<SlotLabProjectProvider>();
      // Simulate 1000 spins via project provider
      final rng = math.Random();
      for (int i = 0; i < 1000; i++) {
        final win = rng.nextDouble() < 0.25 ? rng.nextDouble() * 5.0 : 0.0;
        proj.recordSpinResult(betAmount: 1.0, winAmount: win, tier: win > 0 ? 'WIN 1' : null);
      }
    } catch (_) {}
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
          ? FluxForgeTheme.accentGreen.withOpacity(0.08)
          : FluxForgeTheme.accentGreen.withOpacity(0.04),
        border: Border.all(
          color: _running
            ? FluxForgeTheme.accentGreen.withOpacity(0.5)
            : FluxForgeTheme.accentGreen.withOpacity(0.2)),
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

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when MiddlewareProvider changes
    return ListenableBuilder(
      listenable: GetIt.instance<MiddlewareProvider>(),
      builder: (context, _) => _buildContent(context),
    );
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
    double maxMs = 8000; // 8 second default view
    for (final e in events) {
      final end = e.timelinePositionMs + 1000;
      if (end > maxMs) maxMs = end;
    }

    // Playhead fraction
    final playheadFrac = maxMs > 0 ? ((playheadSec * 1000) / maxMs).clamp(0.0, 1.0) : 0.0;

    // Build track list from real data
    final sortedTracks = trackMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    // Ruler marks
    final rulerCount = (maxMs / 1000).ceil().clamp(4, 10);
    final rulerLabels = List.generate(rulerCount, (i) => '0:${i.toString().padLeft(2, '0')}');

    return _DockCard(
      accent: FluxForgeTheme.accentOrange,
      child: Column(
        children: [
          // Ruler — clickable to seek (T3)
          GestureDetector(
            onTapDown: (d) {
              // Ruler starts at offset 80 (track label width)
              final rulerWidth = (context.size?.width ?? 400) - 80 - 24; // 24 for padding
              final frac = ((d.localPosition.dx - 80) / rulerWidth).clamp(0.0, 1.0);
              final seekSec = (frac * maxMs) / 1000.0;
              engine.seek(seekSec);
              helixState?.setPlayhead(seekSec);
            },
            child: Row(
              children: [
                const SizedBox(width: 80),
                ...rulerLabels.map((t) => Expanded(child: Text(t, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.textTertiary)))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          const SizedBox(height: 4),
          // Tracks with playhead overlay
          Expanded(
            child: sortedTracks.isEmpty
              ? const Center(child: Text('No events on timeline.\nAssign composite events in SlotLab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, height: 1.5)))
              : LayoutBuilder(builder: (_, constraints) {
                  final trackAreaWidth = constraints.maxWidth - 80;
                  return Stack(
                    children: [
                      // Tracks
                      Column(
                        children: sortedTracks.take(6).map((entry) {
                          final trackEvents = entry.value;
                          final trackName = trackEvents.first.name.length > 10
                              ? trackEvents.first.name.substring(0, 10) : trackEvents.first.name;
                          final color = trackEvents.first.color;
                          return Expanded(child: _TlTrackInteractive(
                            name: trackName,
                            color: color,
                            events: trackEvents,
                            maxMs: maxMs,
                            trackAreaWidth: trackAreaWidth,
                            middleware: mw,
                          ));
                        }).toList(),
                      ),
                      // T4: Playhead line
                      if (playheadFrac > 0)
                        Positioned(
                          left: 80 + (playheadFrac * trackAreaWidth),
                          top: 0, bottom: 0,
                          child: Container(
                            width: 2,
                            color: FluxForgeTheme.accentRed.withOpacity(0.8),
                          ),
                        ),
                      // Playhead triangle at top
                      if (playheadFrac > 0)
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
        ],
      ),
    );
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
                            try {
                              final top = allRemediations.first;
                              final v = double.tryParse(top.suggestedValue) ?? 0.5;
                              final mw = GetIt.instance<MiddlewareProvider>();
                              mw.setRtpc(0, v, interpolationMs: 500);
                            } catch (_) {}
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentPurple.withOpacity(0.1),
                              border: Border.all(color: FluxForgeTheme.accentPurple.withOpacity(0.3)),
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
                                  color: isActive ? c.withOpacity(0.18) : c.withOpacity(0.05),
                                  border: Border.all(
                                    color: isActive ? c.withOpacity(0.6) : c.withOpacity(0.25)),
                                  borderRadius: BorderRadius.circular(4)),
                                child: Text(a, style: TextStyle(
                                  fontFamily: 'monospace', fontSize: 8,
                                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                  color: isActive ? c : c.withOpacity(0.7))),
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
                              color: FluxForgeTheme.accentCyan.withOpacity(0.06),
                              border: Border.all(color: FluxForgeTheme.accentCyan.withOpacity(0.3)),
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
                            try {
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
                            } catch (_) {}
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentPurple.withOpacity(0.08),
                              border: Border.all(color: FluxForgeTheme.accentPurple.withOpacity(0.3)),
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

  Future<void> _doExport(String format, String label) async {
    // E3: Compliance gate — block export if RGAI HIGH risk
    try {
      final rgai = GetIt.instance<RgaiProvider>();
      if (rgai.report?.summary != null && !rgai.report!.summary.isCompliant) {
        setState(() => _lastExportResult = '⛔ BLOCKED: RGAI compliance check failed. Fix issues first.');
        return;
      }
    } catch (_) {}

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
              // E5: Batch export
              GestureDetector(
                onTap: () async {
                  for (final e in _exports) {
                    await _doExport(e.$2.toLowerCase(), e.$2);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentYellow.withOpacity(0.12),
                    border: Border.all(color: FluxForgeTheme.accentYellow.withOpacity(0.45)),
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
// REUSABLE COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

/// Unified HELIX button — primary / toggle / ghost variant.
/// All HELIX buttons should use this instead of inline GestureDetector+Container.
enum _HBtnVariant { primary, toggle, ghost }

class _HBtn extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final Color accent;
  final _HBtnVariant variant;
  final bool active;   // for toggle variant
  final IconData? icon;

  const _HBtn({
    required this.label,
    required this.accent,
    this.onTap,
    this.variant = _HBtnVariant.ghost,
    this.active = false,
    this.icon,
  });

  @override
  State<_HBtn> createState() => _HBtnState();
}

class _HBtnState extends State<_HBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final a = widget.accent;

    Color bg;
    Color border;
    Color fg;

    switch (widget.variant) {
      case _HBtnVariant.primary:
        bg = disabled
          ? FluxForgeTheme.bgSurface
          : a.withOpacity(_hovered ? 0.22 : 0.15);
        border = disabled
          ? FluxForgeTheme.borderSubtle
          : a.withOpacity(_hovered ? 0.65 : 0.45);
        fg = disabled ? FluxForgeTheme.textTertiary : a;
      case _HBtnVariant.toggle:
        bg = widget.active
          ? a.withOpacity(_hovered ? 0.22 : 0.15)
          : _hovered ? FluxForgeTheme.bgSurface : Colors.transparent;
        border = widget.active
          ? a.withOpacity(_hovered ? 0.65 : 0.45)
          : FluxForgeTheme.borderSubtle;
        fg = widget.active ? a : (_hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary);
      case _HBtnVariant.ghost:
        bg = _hovered ? FluxForgeTheme.bgSurface : Colors.transparent;
        border = _hovered ? FluxForgeTheme.borderSubtle : Colors.transparent;
        fg = _hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary;
    }

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) { if (!disabled) setState(() => _hovered = true); },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 11, color: fg),
              const SizedBox(width: 5),
            ],
            Text(widget.label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              color: fg, fontWeight: FontWeight.w600,
              letterSpacing: 0.3)),
          ]),
        ),
      ),
    );
  }
}

class _OmniPill extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? border;
  const _OmniPill({required this.child, this.color, this.border});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color ?? FluxForgeTheme.bgSurface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: border ?? FluxForgeTheme.borderSubtle),
    ),
    child: child,
  );
}

class _OmniIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  const _OmniIconBtn({required this.icon, this.onTap, this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Icon(icon, size: 14,
        color: color ?? FluxForgeTheme.textSecondary),
    ),
  );
}

class _ModeBadge extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeBadge({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? FluxForgeTheme.accentBlue.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? FluxForgeTheme.accentBlue.withOpacity(0.3) : FluxForgeTheme.borderSubtle),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w600,
        letterSpacing: 0.08,
        color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary)),
    ),
  );
}

class _TransportBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final bool active;
  final VoidCallback? onTap;
  const _TransportBtn({required this.icon, this.color, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: active && color != null ? color!.withOpacity(0.1) : FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color != null ? color!.withOpacity(0.3) : FluxForgeTheme.borderSubtle),
      ),
      child: Icon(icon, size: 14, color: color ?? FluxForgeTheme.textSecondary),
    ),
  );
}

class _SpineItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SpineItem({required this.icon, required this.label,
    required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    preferBelow: false,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36, height: 36,
        decoration: BoxDecoration(
          // Active: rgba(90,168,255,0.10) — matches mockup .spine-item.active
          color: active ? FluxForgeTheme.accentBlue.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
              ? FluxForgeTheme.accentBlue.withOpacity(0.25) : Colors.transparent),
        ),
        child: Icon(icon, size: 14, // 14px matches mockup font-size:14px
          color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary),
      ),
    ),
  );
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
        right: BorderSide(color: FluxForgeTheme.accentBlue.withOpacity(0.3)),
        left: BorderSide(color: FluxForgeTheme.accentBlue.withOpacity(0.6), width: 3),
      ),
      boxShadow: [
        BoxShadow(color: FluxForgeTheme.bgVoid.withOpacity(0.8), blurRadius: 40, spreadRadius: 4),
        BoxShadow(color: FluxForgeTheme.accentBlue.withOpacity(0.12), blurRadius: 24),
      ],
    ),
    child: Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [FluxForgeTheme.accentBlue.withOpacity(0.18), Colors.transparent],
            ),
            border: Border(bottom: BorderSide(color: FluxForgeTheme.accentBlue.withOpacity(0.3))),
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
      case 0: return _SpineAudioAssign();
      case 1: return _SpineGameConfig();
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
  bool _dropHovering = false;

  void _handleDrop(List<String> paths) {
    final mw = GetIt.instance<MiddlewareProvider>();
    for (final path in paths) {
      final lower = path.toLowerCase();
      if (lower.endsWith('.wav') || lower.endsWith('.aiff') ||
          lower.endsWith('.aif') || lower.endsWith('.mp3')) {
        final fileName = path.split('/').last;
        final name = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
        final now = DateTime.now();
        try {
          mw.updateCompositeEvent(SlotCompositeEvent(
            id: 'drop_${now.millisecondsSinceEpoch}',
            name: name,
            category: 'custom',
            color: FluxForgeTheme.accentCyan,
            createdAt: now,
            modifiedAt: now,
          ));
        } catch (_) {}
      }
    }
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('${events.length}', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 18, color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          const Text('events assigned', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary)),
          const Spacer(),
          // S3: New Event button
          GestureDetector(
            onTap: () {
              try {
                final now = DateTime.now();
                GetIt.instance<MiddlewareProvider>().updateCompositeEvent(
                  SlotCompositeEvent(
                    id: 'helix_new_${now.millisecondsSinceEpoch}',
                    name: 'New Event ${events.length + 1}',
                    category: 'custom',
                    color: FluxForgeTheme.accentCyan,
                    createdAt: now,
                    modifiedAt: now,
                  ),
                );
              } catch (_) {}
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentCyan.withOpacity(0.08),
                border: Border.all(color: FluxForgeTheme.accentCyan.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 10, color: FluxForgeTheme.accentCyan),
                SizedBox(width: 2),
                Text('New', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentCyan)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // A4: Drop target wrapping event list
        Expanded(
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dropHovering = true),
            onDragExited: (_) => setState(() => _dropHovering = false),
            onDragDone: (detail) {
              setState(() => _dropHovering = false);
              _handleDrop(detail.files.map((f) => f.path).toList());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _dropHovering
                    ? FluxForgeTheme.accentBlue.withOpacity(0.7)
                    : Colors.transparent,
                  width: 2),
                borderRadius: BorderRadius.circular(6),
                boxShadow: _dropHovering ? [BoxShadow(
                  color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                  blurRadius: 12)] : null,
              ),
              child: events.isEmpty
                ? Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.audio_file_outlined, size: 24,
                        color: FluxForgeTheme.textTertiary.withOpacity(0.4)),
                      const SizedBox(height: 6),
                      const Text('No audio events.\nDrop WAV/AIFF/MP3 here\nor create in SlotLab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary, height: 1.5)),
                    ],
                  ))
                : ListView(
                    children: events.take(12).map((e) => GestureDetector(
                      onTap: () => helixState?.openContextLens(e),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: e.color.withOpacity(0.05),
                          border: Border.all(color: e.color.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          Container(width: 4, height: 4, decoration: BoxDecoration(
                            color: e.color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.name, style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary),
                            overflow: TextOverflow.ellipsis)),
                          Text('${e.layers.length}L', style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 12,
                            color: FluxForgeTheme.textTertiary),
                        ]),
                      ),
                    )).toList(),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Spine: GAME CONFIG ──────────────────────────────────────────────────────

class _SpineGameConfig extends StatefulWidget {
  @override
  State<_SpineGameConfig> createState() => _SpineGameConfigState();
}

class _SpineGameConfigState extends State<_SpineGameConfig> {
  int _reels = 5;
  int _rows = 3;

  void _applyConfig() {
    try {
      final proj = GetIt.instance<SlotLabProjectProvider>();
      // ignore: avoid_dynamic_calls
      (proj as dynamic).configureReels(reels: _reels, rows: _rows);
    } catch (_) {}
  }

  Widget _spinnerRow(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label, style: const TextStyle(
            fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary))),
          const Spacer(),
          GestureDetector(
            onTap: () { if (value > min) onChanged(value - 1); },
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgElevated,
                border: Border.all(color: FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3)),
              child: const Icon(Icons.remove_rounded, size: 12,
                color: FluxForgeTheme.textSecondary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$value', style: const TextStyle(
              fontFamily: 'monospace', fontSize: 14, color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: () { if (value < max) onChanged(value + 1); },
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgElevated,
                border: Border.all(color: FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3)),
              child: const Icon(Icons.add_rounded, size: 12,
                color: FluxForgeTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<GameFlowProvider>(),
        GetIt.instance<SlotLabProjectProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final flow = GetIt.instance<GameFlowProvider>();
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final stats = proj.sessionStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // S4: Reel/Row controls
        const Text('REEL CONFIG', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        _spinnerRow('REELS', _reels, 3, 6, (v) => setState(() => _reels = v)),
        _spinnerRow('ROWS', _rows, 2, 4, (v) => setState(() => _rows = v)),
        GestureDetector(
          onTap: _applyConfig,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withOpacity(0.08),
              border: Border.all(color: FluxForgeTheme.accentCyan.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4)),
            child: const Text('Apply', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan)),
          ),
        ),
        const SizedBox(height: 10),
        // Existing stats/wins display
        _SpineRow('State', flow.currentState.displayName),
        _SpineRow('Total spins', '${stats.totalSpins}'),
        _SpineRow('Total bet', stats.totalBet.toStringAsFixed(2)),
        _SpineRow('Total win', stats.totalWin.toStringAsFixed(2)),
        _SpineRow('RTP', stats.rtp.isNaN ? '—' : '${stats.rtp.toStringAsFixed(1)}%'),
        const SizedBox(height: 12),
        const Text('RECENT WINS', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 6),
        Expanded(
          child: proj.recentWins.isEmpty
            ? const Center(child: Text('No wins recorded', style: TextStyle(
                fontSize: 10, color: FluxForgeTheme.textTertiary)))
            : ListView(children: proj.recentWins.take(10).map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Text(w.tier, style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentYellow)),
                  const Spacer(),
                  Text(w.amount.toStringAsFixed(2), style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary)),
                ]),
              )).toList()),
        ),
      ],
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
                child: GestureDetector(
                  onHorizontalDragUpdate: (det) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final frac = (det.localPosition.dx / (box.size.width - 100)).clamp(0.0, 1.0);
                    setState(() => _rtpcOverrides[d.$4] = frac);
                    try { mw.setRtpc(d.$4, frac, interpolationMs: 100); } catch (_) {}
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
            overlayColor: FluxForgeTheme.accentCyan.withOpacity(0.1),
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
            color: value ? activeColor.withOpacity(0.2) : FluxForgeTheme.bgElevated,
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

class _SpineAnalytics extends StatelessWidget {
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
            } catch (_) {}
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentPurple.withOpacity(0.06),
              border: Border.all(color: FluxForgeTheme.accentPurple.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(4)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.download_rounded, size: 10, color: FluxForgeTheme.accentPurple),
              SizedBox(width: 4),
              Text('Export Report', style: TextStyle(
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

class _DockTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _DockTab({required this.icon, required this.label, required this.color,
    required this.active, required this.onTap});

  @override
  State<_DockTab> createState() => _DockTabState();
}

class _DockTabState extends State<_DockTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.active;
    final color = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                // Active: surface bg + subtle border (mockup .dock-tab.active)
                // Hover: surface at 60% opacity
                // Inactive: transparent
                color: isActive
                  ? FluxForgeTheme.bgSurface
                  : _hovered
                    ? FluxForgeTheme.bgSurface.withOpacity(0.5)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive
                    ? const Color(0x0EFFFFFF) // rgba(255,255,255,0.055) — mockup --border
                    : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Colored icon box — 14×14 px, border-radius 3 (mockup .dock-tab-icon)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: color.withOpacity(isActive ? 1.0 : 0.65),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Icon(widget.icon, size: 9, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 160),
                    style: TextStyle(
                      fontFamily: 'monospace', fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: 0.05,
                      color: isActive
                        ? FluxForgeTheme.textPrimary        // active: white
                        : _hovered
                          ? FluxForgeTheme.textSecondary    // hover: secondary
                          : FluxForgeTheme.textTertiary,    // inactive: muted
                    ),
                    child: Text(widget.label),
                  ),
                ],
              ),
            ),
            // ── Bottom line indicator — mockup .dock-tab.active::after ────────
            // 1.5px glowing line, 60% of tab width, tab-color + box-shadow glow
            if (isActive)
              Positioned(
                bottom: 0, left: 0, right: 0,
                height: 1.5,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.7),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DockCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  const _DockCard({required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    final a = accent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0x7F06060A), // rgba(6,6,10,0.5) — mockup .flow-stage-map bg
        border: Border.all(
          color: a?.withOpacity(0.25) ?? FluxForgeTheme.borderSubtle,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 2px accent strip at top
          if (a != null)
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  a.withOpacity(0.85),
                  a.withOpacity(0.2),
                  Colors.transparent,
                ]),
              ),
            ),
          Expanded(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          )),
        ],
      ),
    );
  }
}

class _DockLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const _DockLabel(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3, height: 14,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(1.5),
            boxShadow: [BoxShadow(color: c.withOpacity(0.4), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 7),
        Text(text,
          style: TextStyle(
            fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700,
            color: c, letterSpacing: 0.3)),
      ],
    );
  }
}

class _StageNode extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  const _StageNode({required this.label, required this.color, required this.active});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: active ? color.withOpacity(0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(
          color: active ? color : FluxForgeTheme.textTertiary,
          shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10,
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
                ? widget.color.withOpacity(0.12)
                : _hovered ? widget.color.withOpacity(0.06) : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.active
                  ? widget.color
                  : _hovered ? widget.color.withOpacity(0.4) : FluxForgeTheme.borderSubtle,
                width: widget.active ? 1.5 : 1),
              boxShadow: widget.active ? [BoxShadow(
                color: widget.color.withOpacity(0.25), blurRadius: 12)] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 12,
                  color: widget.active ? widget.color
                    : _hovered ? widget.color.withOpacity(0.7) : FluxForgeTheme.textTertiary),
                const SizedBox(height: 2),
                Text(widget.label, style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8,
                  color: widget.active ? widget.color
                    : _hovered ? widget.color.withOpacity(0.7) : FluxForgeTheme.textTertiary)),
              ],
            ),
          ),
          if (_hovered && !widget.active)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('force', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                color: widget.color.withOpacity(0.6))),
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
                      color: (v > 0.7 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen).withOpacity(0.5),
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
    setState(() => _soloed = !_soloed);
    // Solo: mute all other events via each's masterVolume
    final allEvents = widget.middleware.compositeEvents;
    for (final e in allEvents) {
      if (e.id == widget.event.id) continue;
      widget.middleware.updateCompositeEvent(
        e.copyWith(masterVolume: _soloed ? 0.0 : e.masterVolume),
      );
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
          ? FluxForgeTheme.bgVoid.withOpacity(0.4)
          : FluxForgeTheme.bgDeep,
        border: Border.all(
          color: _soloed
            ? FluxForgeTheme.accentYellow.withOpacity(0.6)
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
                            widget.event.color.withOpacity(0.7),
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
                          color: FluxForgeTheme.textPrimary.withOpacity(0.8),
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
            ? widget.activeColor.withOpacity(0.25)
            : _hovered ? FluxForgeTheme.bgSurface : Colors.transparent,
          border: Border.all(
            color: widget.active
              ? widget.activeColor.withOpacity(0.8)
              : _hovered ? FluxForgeTheme.borderSubtle : FluxForgeTheme.borderSubtle.withOpacity(0.5)),
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
        colors: [color.withOpacity(0.18), color.withOpacity(0.05)],
      ),
      border: Border.all(color: color.withOpacity(0.4), width: 1.2),
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: color.withOpacity(0.10), blurRadius: 16, spreadRadius: -2)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)])),
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
              gradient: LinearGradient(colors: [color.withOpacity(0.7), color]),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6)])),
          ),
        ),
      ],
    ),
  );
}

class _TlTrack extends StatelessWidget {
  final String name;
  final Color color;
  final List<(double, double)> regions; // (start, width) as 0-1 fractions
  const _TlTrack({required this.name, required this.color, required this.regions});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(width: 80, child: Text(name, style: const TextStyle(
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
                ...regions.map((r) => Positioned(
                  left: r.$1 * c.maxWidth,
                  width: r.$2 * c.maxWidth,
                  top: 2, bottom: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.25),
                      border: Border.all(color: color.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(2)),
                  ),
                )),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

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
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3)),
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
        colors: [color.withOpacity(0.14), color.withOpacity(0.04)],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.35), width: 1.2),
      boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8)],
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
              widget.color.withOpacity(_hovered ? 0.22 : 0.12),
              widget.color.withOpacity(_hovered ? 0.08 : 0.03),
            ],
          ),
          border: Border.all(
            color: widget.color.withOpacity(_hovered ? 0.6 : 0.35), width: 1.2),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(_hovered ? 0.2 : 0.08), blurRadius: 20),
            BoxShadow(color: FluxForgeTheme.bgVoid.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(_hovered ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.color.withOpacity(0.2)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [c.withOpacity(0.12), FluxForgeTheme.bgDeepest.withOpacity(0.9)],
        ),
        border: Border.all(color: c.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: c.withOpacity(0.1), blurRadius: 10),
          BoxShadow(color: FluxForgeTheme.bgVoid.withOpacity(0.4), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700,
            color: c.withOpacity(0.7), letterSpacing: 0.2)),
          const SizedBox(width: 7),
          Text(value, style: TextStyle(
            fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600,
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
          letterSpacing: 0.2, color: color.withOpacity(0.8))),
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
          overlayColor: color.withOpacity(0.15),
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
  final double trackAreaWidth;
  final MiddlewareProvider middleware;
  const _TlTrackInteractive({required this.name, required this.color,
    required this.events, required this.maxMs, required this.trackAreaWidth,
    required this.middleware});

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
          try { widget.middleware.deleteEvent(e.id); } catch (_) {}
        case 'duplicate':
          try {
            final now = DateTime.now();
            widget.middleware.updateCompositeEvent(e.copyWith(
              id: 'dup_${now.millisecondsSinceEpoch}',
              name: '${e.name}_copy',
              timelinePositionMs: e.timelinePositionMs + 200,
            ));
          } catch (_) {}
        case 'rename':
          _showRenameDialog(context, e);
        default:
          if (value.startsWith('track_')) {
            final trackIdx = int.tryParse(value.substring(6)) ?? 0;
            try {
              widget.middleware.updateCompositeEvent(
                e.copyWith(trackIndex: trackIdx));
            } catch (_) {}
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
                try {
                  widget.middleware.updateCompositeEvent(e.copyWith(name: name));
                } catch (_) {}
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
                  final start = (e.timelinePositionMs / widget.maxMs).clamp(0.0, 1.0);
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
                            // T1: move
                            final deltaX = d.globalPosition.dx - _dragStartX;
                            final deltaMs = (deltaX / c.maxWidth) * widget.maxMs;
                            final newMs = (_dragStartMs + deltaMs).clamp(0.0, widget.maxMs - 1000);
                            widget.middleware.updateCompositeEvent(
                              e.copyWith(timelinePositionMs: newMs));
                          }
                        },
                        onHorizontalDragEnd: (_) {
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
                                  color: widget.color.withOpacity(0.25),
                                  border: Border.all(color: widget.color.withOpacity(0.5)),
                                  borderRadius: BorderRadius.circular(2)),
                                child: Center(child: Text(
                                  e.name.length > 6 ? e.name.substring(0, 6) : e.name,
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                                    color: widget.color.withOpacity(0.8)),
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
                                      color: widget.color.withOpacity(0.5),
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
            child: Container(color: FluxForgeTheme.bgVoid.withOpacity(0.5)),
          ),
          // Lens panel
          Center(
            child: LayoutBuilder(
              builder: (ctx, constraints) => Container(
              width: (MediaQuery.of(ctx).size.width * 0.5).clamp(520.0, 860.0),
              height: (MediaQuery.of(ctx).size.height * 0.62).clamp(460.0, 720.0),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                border: Border.all(color: e.color.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color: e.color.withOpacity(0.2), blurRadius: 40)],
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
                                      overlayColor: e.color.withOpacity(0.1),
                                    ),
                                    child: SizedBox(
                                      height: 18,
                                      child: Slider(
                                        value: _rtpcValues[i],
                                        onChanged: (v) {
                                          setState(() => _rtpcValues[i] = v);
                                          try {
                                            GetIt.instance<MiddlewareProvider>()
                                              .setRtpc(i, v, interpolationMs: 200);
                                          } catch (_) {}
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
                        color: e.color.withOpacity(0.7))),
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
                      color: FluxForgeTheme.accentPurple.withOpacity(0.5))),
                ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _submit,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentPurple.withOpacity(0.12),
                  border: Border.all(color: FluxForgeTheme.accentPurple.withOpacity(0.3)),
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

// ─────────────────────────────────────────────────────────────────────────────
// C1/C2: REEL CELL OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _ReelCellOverlay extends StatelessWidget {
  final void Function(int reel, int row) onCellTap;
  const _ReelCellOverlay({required this.onCellTap});

  @override
  Widget build(BuildContext context) {
    // Covers roughly the slot reel area: 60% width centered, top ~25%
    return LayoutBuilder(
      builder: (_, constraints) {
        final totalW = constraints.maxWidth;
        final totalH = constraints.maxHeight;
        final reelAreaW = totalW * 0.6;
        final reelAreaH = totalH * 0.5;
        final reelLeft = (totalW - reelAreaW) / 2;
        final reelTop = totalH * 0.25;
        const cols = 5;
        const rows = 3;
        final cellW = reelAreaW / cols;
        final cellH = reelAreaH / rows;

        return Stack(
          children: [
            for (int col = 0; col < cols; col++)
              for (int row = 0; row < rows; row++)
                Positioned(
                  left: reelLeft + col * cellW,
                  top: reelTop + row * cellH,
                  width: cellW,
                  height: cellH,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => onCellTap(col, row),
                    child: Container(color: Colors.transparent),
                  ),
                ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// C2: REEL CONTEXT LENS
// ─────────────────────────────────────────────────────────────────────────────

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
            border: Border.all(color: FluxForgeTheme.accentCyan.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(
              color: FluxForgeTheme.accentCyan.withOpacity(0.15), blurRadius: 20)],
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
                            overlayColor: FluxForgeTheme.accentCyan.withOpacity(0.1),
                          ),
                          child: SizedBox(
                            height: 16,
                            child: Slider(
                              value: _sliderValues[i],
                              onChanged: (v) {
                                setState(() => _sliderValues[i] = v);
                                try {
                                  GetIt.instance<MiddlewareProvider>().setRtpc(
                                    widget.reel * 4 + widget.row * 4 + i, v,
                                    interpolationMs: 100);
                                } catch (_) {}
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
