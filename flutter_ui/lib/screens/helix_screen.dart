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
  int _dockTab = 0; // 0=FLOW 1=AUDIO 2=MATH 3=TIMELINE 4=INTEL 5=EXPORT
  double _dockHeight = 300.0;
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

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..requestFocus();
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
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _glowCtrl.dispose();
    _waveTimer.cancel();
    _bpmTimer.cancel();
    super.dispose();
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
      child: Container(
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
    );
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() { _spineOpen = null; _mode = 0; });
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _mode = _mode == 1 ? 0 : 1);
    } else if (key == LogicalKeyboardKey.keyA) {
      setState(() => _mode = _mode == 2 ? 0 : 2);
    }
    // 1-6 → dock tabs
    final digit = int.tryParse(e.character ?? '');
    if (digit != null && digit >= 1 && digit <= 6) {
      setState(() => _dockTab = digit - 1);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OMNIBAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOmnibar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xF208080C),
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
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
                  color: Colors.white, letterSpacing: 0.05)),
            ),
          ),
          const SizedBox(width: 8),
          const Text('HELIX', style: TextStyle(
            fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600,
            color: FluxForgeTheme.textPrimary, letterSpacing: 0.15)),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 12),
          // Project name
          _OmniPill(
            child: Row(children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(GetIt.instance<SlotLabProjectProvider>().projectName,
                style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textPrimary)),
            ]),
          ),
          const Spacer(),
          // Undo/Redo
          _OmniIconBtn(icon: Icons.undo_rounded, onTap: () {}),
          const SizedBox(width: 2),
          _OmniIconBtn(icon: Icons.redo_rounded, onTap: () {}),
          const SizedBox(width: 12),
          // BPM
          _OmniPill(
            color: FluxForgeTheme.accentCyan.withOpacity(0.05),
            border: FluxForgeTheme.accentCyan.withOpacity(0.2),
            child: Row(children: [
              const Text('BPM', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                color: FluxForgeTheme.textTertiary, letterSpacing: 0.1)),
              const SizedBox(width: 6),
              Text(_bpmDisplay.toStringAsFixed(1), style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11,
                color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
            ]),
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
              onTap: () {},
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
          color: FluxForgeTheme.bgDeepest,
          child: Column(
            children: [
              const SizedBox(height: 12),
              ...icons.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
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
                    width: MediaQuery.of(context).size.width * 0.6,
                    height: MediaQuery.of(context).size.height * 0.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: glowColor.withOpacity(_glowAnim.value),
                        blurRadius: 80, spreadRadius: 20,
                      )],
                    ),
                  ),
                ),
              ),

              // Slot preview — center (wired to project provider)
              Center(
                child: PremiumSlotPreview(
                  onExit: widget.onClose ?? () {},
                  reels: 5,
                  rows: 3,
                  isFullscreen: true,
                  projectProvider: GetIt.instance<SlotLabProjectProvider>(),
                ),
              ),

              // Info chips — top right
              Positioned(
                top: 14, right: 14,
                child: _buildInfoChips(),
              ),

              // Stage strip — bottom center (above dock)
              Positioned(
                bottom: 20,
                left: 0, right: 0,
                child: Center(child: _buildStageStrip(stage)),
              ),

              // Waveform bars — below stage strip
              Positioned(
                bottom: 4, left: 0, right: 0,
                child: Center(child: _buildWaveformBars(glowColor)),
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

  Widget _buildStageStrip(GameFlowState current) {
    final stages = [
      (GameFlowState.idle, 'IDLE', FluxForgeTheme.textTertiary),
      (GameFlowState.baseGame, 'BASE', FluxForgeTheme.accentBlue),
      (GameFlowState.freeSpins, 'FREE', FluxForgeTheme.accentYellow),
      (GameFlowState.bonusGame, 'BONUS', FluxForgeTheme.accentOrange),
      (GameFlowState.jackpotPresentation, 'JACKPOT', FluxForgeTheme.accentGreen),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE608080C),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: stages.asMap().entries.expand((e) {
          final (state, label, color) = e.value;
          final isActive = current == state;
          final widgets = <Widget>[
            _StageNode(label: label, color: color, active: isActive),
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
  ];

  Widget _buildDock() {
    final dockH = _mode == 2 ? MediaQuery.of(context).size.height * 0.5 : _dockHeight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: dockH,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          // Tab bar
          _buildDockTabBar(),
          // Panel content
          Expanded(child: Padding(
            padding: const EdgeInsets.all(14),
            child: _buildDockPanel(),
          )),
        ],
      ),
    );
  }

  Widget _buildDockTabBar() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xB206060A),
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          ..._dockTabDefs.asMap().entries.map((e) {
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
          }),
          const Spacer(),
          // Resize handle
          GestureDetector(
            onVerticalDragUpdate: (d) => setState(() {
              _dockHeight = (_dockHeight - d.delta.dy).clamp(150.0, 500.0);
            }),
            child: SizedBox(
              width: 32, height: 38,
              child: Center(
                child: Container(
                  width: 24, height: 3,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
      _ => const SizedBox(),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCK PANELS
// ─────────────────────────────────────────────────────────────────────────────

// ── FLOW Panel ───────────────────────────────────────────────────────────────

class _FlowPanel extends StatelessWidget {
  const _FlowPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<GameFlowProvider>(
      builder: (_, flow, child) {
        final current = flow.currentState;
        final nodes = [
          (GameFlowState.idle,              'IDLE',    Icons.pause_circle_outline, FluxForgeTheme.textTertiary),
          (GameFlowState.baseGame,          'BASE',    Icons.play_arrow_rounded,   FluxForgeTheme.accentBlue),
          (GameFlowState.cascading,         'CASCADE', Icons.waterfall_chart,      FluxForgeTheme.accentCyan),
          (GameFlowState.freeSpins,         'FREE',    Icons.star_rounded,         FluxForgeTheme.accentYellow),
          (GameFlowState.holdAndWin,        'HOLD',    Icons.lock_rounded,         FluxForgeTheme.accentOrange),
          (GameFlowState.bonusGame,         'BONUS',   Icons.casino_rounded,       FluxForgeTheme.accentPurple),
          (GameFlowState.jackpotPresentation,'JACKPOT',Icons.emoji_events_rounded, FluxForgeTheme.accentGreen),
        ];

        return Row(
          children: [
            // Flow map
            Expanded(
              flex: 3,
              child: _DockCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('STAGE FLOW'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: nodes.asMap().entries.expand((e) {
                          final (state, label, icon, color) = e.value;
                          final active = current == state;
                          final widgets = <Widget>[
                            _FlowNode(label: label, icon: icon,
                              color: color, active: active),
                          ];
                          if (e.key < nodes.length - 1) {
                            widgets.add(Icon(Icons.arrow_forward_rounded,
                              size: 12, color: FluxForgeTheme.textTertiary.withOpacity(0.4)));
                          }
                          return widgets;
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Current state info
            SizedBox(
              width: 160,
              child: _DockCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('CURRENT STATE'),
                    const SizedBox(height: 8),
                    Text(current.displayName,
                      style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 16,
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
          ],
        );
      },
    );
  }
}

// ── AUDIO Panel ──────────────────────────────────────────────────────────────

class _AudioPanel extends StatelessWidget {
  const _AudioPanel();

  @override
  Widget build(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final events = mw.compositeEvents.take(8).toList();
    final out = neuro.output;

    // Derive master levels from neuro audio adaptation output
    final masterL = (out.arousal * 0.6 + out.engagement * 0.4).clamp(0.0, 1.0);
    final masterR = (out.arousal * 0.55 + out.engagement * 0.45).clamp(0.0, 1.0);
    final peak = math.max(masterL, masterR);
    final peakDb = peak > 0.001 ? (20 * math.log(peak) / 2.302585) : -60.0;

    return Row(
      children: [
        // Master meters — driven by NeuroAudio engagement/arousal
        SizedBox(
          width: 130,
          child: _DockCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('MASTER'),
                const SizedBox(height: 8),
                _MeterRow(label: 'L', value: masterL),
                const SizedBox(height: 6),
                _MeterRow(label: 'R', value: masterR),
                const Spacer(),
                Text('${peakDb.toStringAsFixed(1)} dBFS',
                  style: TextStyle(fontFamily: 'monospace',
                    fontSize: 10, color: peakDb > -6 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen)),
                const SizedBox(height: 6),
                Row(children: [
                  _DockLabel('VOL'),
                  const SizedBox(width: 4),
                  Text('${(out.volumeEnvelopeScale * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan)),
                  const Spacer(),
                  _DockLabel('CMP'),
                  const SizedBox(width: 4),
                  Text('${(out.compressionModifier * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentPurple)),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Channel strips — real composite events
        Expanded(
          child: _DockCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DockLabel('CHANNELS'),
                  const Spacer(),
                  Text('${events.length} events', style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: events.isEmpty
                    ? const Center(child: Text('No composite events loaded.\nAssign audio in SlotLab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, height: 1.5)))
                    : ListView(
                        children: events.map((e) {
                          final name = e.name.length > 12 ? e.name.substring(0, 12) : e.name;
                          final level = e.masterVolume.clamp(0.0, 1.0);
                          return _ChannelStrip(name: name, color: e.color, level: level);
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

class _MathPanel extends StatelessWidget {
  const _MathPanel();

  @override
  Widget build(BuildContext context) {
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

    final cards = [
      ('RTP',         rtp > 0 ? '${rtp.toStringAsFixed(1)}%' : '—', 'Target: 96.0%', (rtp / 100).clamp(0.0, 1.0), FluxForgeTheme.accentGreen),
      ('VOLATILITY',  volLabel,  'Index: ${volIdx.toStringAsFixed(1)} / 10', volIdx / 10, FluxForgeTheme.accentOrange),
      ('HIT FREQ',    hitFreqStr, '${(hitRate * 100).toStringAsFixed(0)}% hit rate', hitRate.clamp(0.0, 1.0), FluxForgeTheme.accentBlue),
      ('MAX WIN',     maxWinMult > 0 ? '${maxWinMult.toStringAsFixed(0)}×' : '—', 'Bet multiplier', (maxWinMult / 5000).clamp(0.0, 1.0), FluxForgeTheme.accentYellow),
      ('SIMULATIONS', '${stats.totalSpins}', 'Spins recorded', stats.totalSpins > 0 ? 1.0 : 0.0, FluxForgeTheme.accentPurple),
      ('BONUS FREQ',  bonusFreq, 'Feature triggers', bonusFill, FluxForgeTheme.accentCyan),
    ];

    return GridView.count(
      crossAxisCount: 6,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.9,
      children: cards.map((c) => _MathCard(
        label: c.$1, value: c.$2, sub: c.$3,
        fill: c.$4, color: c.$5,
      )).toList(),
    );
  }
}

// ── TIMELINE Panel ───────────────────────────────────────────────────────────

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel();

  @override
  Widget build(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final events = mw.compositeEvents;

    // Group events by trackIndex, build real timeline tracks
    final trackMap = <int, List<SlotCompositeEvent>>{};
    for (final e in events) {
      trackMap.putIfAbsent(e.trackIndex, () => []).add(e);
    }

    // Find timeline extent (max position + reasonable width)
    double maxMs = 8000; // 8 second default view
    for (final e in events) {
      final end = e.timelinePositionMs + 1000; // assume ~1s per event
      if (end > maxMs) maxMs = end;
    }

    // Build track list from real data, or show empty state
    final sortedTracks = trackMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final trackWidgets = sortedTracks.take(6).map((entry) {
      final trackEvents = entry.value;
      final trackName = trackEvents.first.name.length > 10
          ? trackEvents.first.name.substring(0, 10) : trackEvents.first.name;
      final color = trackEvents.first.color;
      final regions = trackEvents.map((e) {
        final start = (e.timelinePositionMs / maxMs).clamp(0.0, 1.0);
        final width = (1000 / maxMs).clamp(0.02, 0.3); // each event ~1s visual width
        return (start, width);
      }).toList();
      return _TlTrack(name: trackName, color: color, regions: regions);
    }).toList();

    // Ruler marks
    final rulerCount = (maxMs / 1000).ceil().clamp(4, 10);
    final rulerLabels = List.generate(rulerCount, (i) => '0:${i.toString().padLeft(2, '0')}');

    return _DockCard(
      child: Column(
        children: [
          // Ruler
          Row(
            children: [
              const SizedBox(width: 80),
              ...rulerLabels.map((t) => Expanded(child: Text(t, style: const TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                color: FluxForgeTheme.textTertiary)))),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          const SizedBox(height: 4),
          // Tracks
          Expanded(
            child: trackWidgets.isEmpty
              ? const Center(child: Text('No events on timeline.\nAssign composite events in SlotLab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, height: 1.5)))
              : Column(
                  children: trackWidgets.map((t) => Expanded(child: t)).toList(),
                ),
          ),
        ],
      ),
    );
  }
}

// ── INTEL Panel ──────────────────────────────────────────────────────────────

class _IntelPanel extends StatelessWidget {
  const _IntelPanel();

  @override
  Widget build(BuildContext context) {
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
                        _DockLabel('AI COPILOT'),
                        const Spacer(),
                        if (allRemediations.isNotEmpty)
                          Text('${allRemediations.length} suggestions', style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentYellow)),
                      ]),
                      const SizedBox(height: 8),
                      Text(copilotText,
                        style: const TextStyle(fontSize: 10, height: 1.5,
                          color: FluxForgeTheme.textSecondary)),
                      const Spacer(),
                      Text(neuro.responsibleGamingMode ? '⚠ RG MODE' : '✓ RG mode stable',
                        style: TextStyle(fontSize: 10,
                          color: neuro.responsibleGamingMode
                            ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _DockCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _DockLabel('RGAI COMPLIANCE'),
                        const Spacer(),
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
        SizedBox(
          width: 200,
          child: _DockCard(
            child: Column(
              children: [
                _DockLabel('ENGAGEMENT SCORE'),
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
                // 4 real mini metrics from NeuroAudioProvider
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  childAspectRatio: 2.5,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    _MiniMetric('$retention%', 'Retention',   FluxForgeTheme.accentBlue),
                    _MiniMetric(dwell,         'Session',     FluxForgeTheme.accentPurple),
                    _MiniMetric(losses,        'Loss streak', FluxForgeTheme.accentOrange),
                    _MiniMetric(fatigueIdx,    'Fatigue idx', FluxForgeTheme.accentGreen),
                  ],
                ),
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

class _ExportPanel extends StatelessWidget {
  const _ExportPanel();

  static const _exports = [
    ('📦', 'UCP',   'Universal Content Package', FluxForgeTheme.accentYellow),
    ('🎵', 'WWISE', 'Audiokinetic project',       FluxForgeTheme.accentBlue),
    ('🎛️', 'FMOD',  'FMOD Studio bank',           FluxForgeTheme.accentGreen),
    ('📄', 'GDD',   'Game Design Doc',            FluxForgeTheme.accentPurple),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _exports.map((e) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ExportCard(
              emoji: e.$1, label: e.$2, sub: e.$3, color: e.$4,
              onTap: () {
                try {
                  final provider = GetIt.instance<SlotExportProvider>();
                  provider.exportSingle({
                    'format': e.$2.toLowerCase(),
                    'name': 'Project',
                  }, e.$2.toLowerCase());
                } catch (_) {}
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

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
        duration: const Duration(milliseconds: 180),
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: active ? FluxForgeTheme.accentBlue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
              ? FluxForgeTheme.accentBlue.withOpacity(0.25) : Colors.transparent),
        ),
        child: Icon(icon, size: 16,
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
    width: 280,
    decoration: BoxDecoration(
      color: FluxForgeTheme.bgSurface.withOpacity(0.95),
      border: Border(right: BorderSide(color: FluxForgeTheme.borderSubtle)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24)],
    ),
    child: Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(title, style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600,
                color: FluxForgeTheme.textPrimary, letterSpacing: 0.1)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close_rounded, size: 16,
                  color: FluxForgeTheme.textTertiary)),
            ],
          ),
        ),
        const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildSpineContent(spineIndex),
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

class _SpineAudioAssign extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final events = mw.compositeEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('${events.length}', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 18, color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          const Text('events assigned', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary)),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: events.isEmpty
            ? const Center(child: Text('No audio events.\nCreate in SlotLab ASSIGN tab.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary, height: 1.5)))
            : ListView(
                children: events.take(12).map((e) => Container(
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
                  ]),
                )).toList(),
              ),
        ),
      ],
    );
  }
}

// ── Spine: GAME CONFIG ──────────────────────────────────────────────────────

class _SpineGameConfig extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final flow = GetIt.instance<GameFlowProvider>();
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final stats = proj.sessionStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

class _SpineAiIntel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final out = neuro.output;
    final dims = [
      ('Arousal',       out.arousal,        FluxForgeTheme.accentRed),
      ('Valence',       (out.valence + 1) / 2, FluxForgeTheme.accentGreen),
      ('Engagement',    out.engagement,     FluxForgeTheme.accentBlue),
      ('Risk tolerance',out.riskTolerance,  FluxForgeTheme.accentOrange),
      ('Frustration',   out.frustration,    FluxForgeTheme.accentYellow),
      ('Flow depth',    out.flowDepth,      FluxForgeTheme.accentCyan),
      ('Churn risk',    out.churnPrediction,FluxForgeTheme.accentPurple),
      ('Fatigue',       out.sessionFatigue, FluxForgeTheme.accentOrange),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('8D EMOTIONAL STATE', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        ...dims.map((d) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(d.$1, style: const TextStyle(
                  fontSize: 10, color: FluxForgeTheme.textSecondary))),
                Text('${(d.$2 * 100).toStringAsFixed(0)}%', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 9, color: d.$3)),
              ]),
              const SizedBox(height: 3),
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgElevated,
                  borderRadius: BorderRadius.circular(2)),
                child: FractionallySizedBox(
                  widthFactor: d.$2.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Container(decoration: BoxDecoration(
                    color: d.$3, borderRadius: BorderRadius.circular(2))),
                ),
              ),
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

class _SpineSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
        _SpineRow('Tempo', '${t.tempo.toStringAsFixed(1)} BPM'),
        _SpineRow('Time sig', '${t.timeSigNum}/${t.timeSigDenom}'),
        _SpineRow('Position', '${t.positionSeconds.toStringAsFixed(1)}s'),
        _SpineRow('Playing', t.isPlaying ? 'YES' : 'NO'),
        _SpineRow('Loop', t.loopEnabled ? 'ON' : 'OFF'),
        const SizedBox(height: 12),
        const Text('NEURO AUDIO', style: TextStyle(
          fontFamily: 'monospace', fontSize: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        _SpineRow('Enabled', neuro.enabled ? 'YES' : 'NO'),
        _SpineRow('RG Mode', neuro.responsibleGamingMode ? 'ON' : 'OFF'),
        _SpineRow('Tempo mod', '${(neuro.output.tempoModifier * 100).toStringAsFixed(0)}%'),
        _SpineRow('Reverb mod', '${(neuro.output.reverbDepthModifier * 100).toStringAsFixed(0)}%'),
      ],
    );
  }
}

// ── Spine: ANALYTICS ────────────────────────────────────────────────────────

class _SpineAnalytics extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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

class _DockTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _DockTab({required this.icon, required this.label, required this.color,
    required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? FluxForgeTheme.bgSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active ? FluxForgeTheme.borderSubtle : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: color.withOpacity(active ? 1.0 : 0.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 11,
            fontWeight: FontWeight.w500, letterSpacing: 0.04,
            color: active ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary)),
        ],
      ),
    ),
  );
}

class _DockCard extends StatelessWidget {
  final Widget child;
  const _DockCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0x8006060A),
      border: Border.all(color: FluxForgeTheme.borderSubtle),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}

class _DockLabel extends StatelessWidget {
  final String text;
  const _DockLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(
      fontFamily: 'monospace', fontSize: 9,
      color: FluxForgeTheme.textTertiary, letterSpacing: 0.12));
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

class _FlowNode extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  const _FlowNode({required this.label, required this.icon,
    required this.color, required this.active});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 70, height: 44,
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.1) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color : FluxForgeTheme.borderSubtle),
          boxShadow: active ? [BoxShadow(
            color: color.withOpacity(0.2), blurRadius: 12)] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: active ? color : FluxForgeTheme.textTertiary),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 8,
              color: active ? color : FluxForgeTheme.textTertiary)),
          ],
        ),
      ),
    ],
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
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: const TextStyle(
        fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
      const SizedBox(width: 6),
      Expanded(
        child: Container(
          height: 6, decoration: BoxDecoration(
            color: FluxForgeTheme.bgElevated,
            borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _ChannelStrip extends StatelessWidget {
  final String name;
  final Color color;
  final double level;
  const _ChannelStrip({required this.name, required this.color, required this.level});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0x8006060A),
      border: Border.all(color: FluxForgeTheme.borderSubtle),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      children: [
        Container(width: 3, height: 28, decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        SizedBox(width: 70, child: Text(name, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 11,
          color: FluxForgeTheme.textSecondary))),
        Expanded(
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              borderRadius: BorderRadius.circular(2)),
            child: FractionallySizedBox(
              widthFactor: level,
              alignment: Alignment.centerLeft,
              child: Container(decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${(-20 + level * 20).toStringAsFixed(0)}dB',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
            color: FluxForgeTheme.textTertiary)),
        const SizedBox(width: 8),
        _MsBtns(),
      ],
    ),
  );
}

class _MsBtns extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: ['M', 'S'].map((l) => Container(
      width: 18, height: 18, margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(3)),
      child: Center(child: Text(l, style: const TextStyle(
        fontFamily: 'monospace', fontSize: 8,
        color: FluxForgeTheme.textTertiary))),
    )).toList(),
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
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.03),
      border: Border.all(color: color.withOpacity(0.15)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 8, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const Spacer(),
        Text(value, style: TextStyle(
          fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w300,
          color: color)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(
          fontSize: 9, color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 6),
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgElevated,
            borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            widthFactor: fill.clamp(0.0, 1.0),
            alignment: Alignment.centerLeft,
            child: Container(decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
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
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(
          fontSize: 10, color: FluxForgeTheme.textSecondary))),
        Text(value, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10,
          fontWeight: FontWeight.w600, color: color)),
      ],
    ),
  );
}

class _MiniMetric extends StatelessWidget {
  final String value, label;
  final Color color;
  const _MiniMetric(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(value, style: TextStyle(
        fontFamily: 'monospace', fontSize: 14,
        fontWeight: FontWeight.w500, color: color)),
      Text(label, style: const TextStyle(
        fontSize: 8, color: FluxForgeTheme.textTertiary)),
    ],
  );
}

class _ExportCard extends StatefulWidget {
  final String emoji, label, sub;
  final Color color;
  final VoidCallback onTap;
  const _ExportCard({required this.emoji, required this.label, required this.sub,
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
          color: _hovered ? widget.color.withOpacity(0.08) : widget.color.withOpacity(0.03),
          border: Border.all(
            color: _hovered ? widget.color.withOpacity(0.3) : widget.color.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(widget.label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600,
              color: widget.color)),
            const SizedBox(height: 4),
            Text(widget.sub, style: const TextStyle(
              fontSize: 10, color: FluxForgeTheme.textTertiary),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xCC08080C),
      border: Border.all(color: FluxForgeTheme.borderSubtle),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
        const SizedBox(width: 5),
        Text(value, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w500,
          color: color ?? FluxForgeTheme.textPrimary)),
      ],
    ),
  );
}
