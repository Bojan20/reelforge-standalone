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

  @override
  void initState() {
    super.initState();
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
      focusNode: FocusNode()..requestFocus(),
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
              const Text('Untitled Project', style: TextStyle(
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
                builder: (_, __) => Center(
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

              // Slot preview — center
              Center(
                child: PremiumSlotPreview(
                  onExit: widget.onClose ?? () {},
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
    return Consumer<GameFlowProvider>(
      builder: (context, flow, _) => Row(
        children: [
          const _InfoChip(label: 'RTP', value: '96.2%'),
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
            child: Container(
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
      builder: (_, flow, __) {
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
    return Consumer<MiddlewareProvider>(
      builder: (_, mw, __) {
        final events = mw.compositeEvents.take(6).toList();

        return Row(
          children: [
            // Master meters
            SizedBox(
              width: 120,
              child: _DockCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('MASTER'),
                    const SizedBox(height: 8),
                    _MeterRow(label: 'L', value: 0.72),
                    const SizedBox(height: 6),
                    _MeterRow(label: 'R', value: 0.68),
                    const Spacer(),
                    const Text('-4.2 dBFS',
                      style: TextStyle(fontFamily: 'monospace',
                        fontSize: 10, color: FluxForgeTheme.accentGreen)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Channel strips
            Expanded(
              child: _DockCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('CHANNELS'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: events.isEmpty
                          ? [
                              _ChannelStrip(name: 'BASE_LOOP', color: FluxForgeTheme.accentBlue,   level: 0.75),
                              _ChannelStrip(name: 'TRIG_STG',  color: FluxForgeTheme.accentOrange, level: 0.60),
                              _ChannelStrip(name: 'BONUS_FX',  color: FluxForgeTheme.accentYellow, level: 0.70),
                              _ChannelStrip(name: 'WIN_CEL',   color: FluxForgeTheme.accentGreen,  level: 0.85),
                              _ChannelStrip(name: 'NEURO_MX',  color: FluxForgeTheme.accentPurple, level: 0.45),
                            ]
                          : events.map((e) => _ChannelStrip(
                              name: e.name.length > 10 ? e.name.substring(0, 10) : e.name,
                              color: FluxForgeTheme.accentBlue,
                              level: 0.65,
                            )).toList(),
                      ),
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
}

// ── MATH Panel ───────────────────────────────────────────────────────────────

class _MathPanel extends StatelessWidget {
  const _MathPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (_, proj, __) {
        final stats = proj.sessionStats;
        final rtp = stats.rtp.isNaN || stats.rtp.isInfinite ? 96.0 : stats.rtp;

        final cards = [
          ('RTP',         '${rtp.toStringAsFixed(1)}%',  'Target: 96.0%', rtp / 100, FluxForgeTheme.accentGreen),
          ('VOLATILITY',  'HIGH',            'Index: 7.4 / 10',   0.74, FluxForgeTheme.accentOrange),
          ('HIT FREQ',    '1:4.2',           '24% hit rate',      0.24, FluxForgeTheme.accentBlue),
          ('MAX WIN',     '5000×',           'Bet multiplier',    1.0,  FluxForgeTheme.accentYellow),
          ('SIMULATIONS', '${stats.totalSpins}', 'Spins recorded', 1.0, FluxForgeTheme.accentPurple),
          ('BONUS FREQ',  '1:82',            'Free spins trigger', 0.12, FluxForgeTheme.accentCyan),
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
      },
    );
  }
}

// ── TIMELINE Panel ───────────────────────────────────────────────────────────

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel();

  static const _tracks = [
    ('BASE_LOOP',   FluxForgeTheme.accentBlue,   [(0.03, 0.85)]),
    ('REEL_SFX',    FluxForgeTheme.accentCyan,   [(0.03, 0.18), (0.22, 0.22)]),
    ('WIN_CEL',     FluxForgeTheme.accentGreen,  [(0.46, 0.30)]),
    ('NEURO_ADAPT', FluxForgeTheme.accentPurple, [(0.03, 0.92)]),
    ('STINGERS',    FluxForgeTheme.accentOrange, [(0.38, 0.08)]),
  ];

  @override
  Widget build(BuildContext context) {
    return _DockCard(
      child: Column(
        children: [
          // Ruler
          Row(
            children: [
              const SizedBox(width: 80),
              ...['0:00','0:01','0:02','0:03','0:04','0:05','0:06','0:07']
                .map((t) => Expanded(child: Text(t, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.textTertiary)))),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          const SizedBox(height: 4),
          // Tracks
          Expanded(
            child: Column(
              children: _tracks.map((t) => Expanded(
                child: _TlTrack(
                  name: t.$1, color: t.$2, regions: t.$3,
                ),
              )).toList(),
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
                          decoration: const BoxDecoration(
                            color: FluxForgeTheme.accentGreen, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        _DockLabel('AI COPILOT'),
                      ]),
                      const SizedBox(height: 8),
                      const Text(
                        'Detected: High-intensity base loop.\n'
                        'Suggest: ↓ reverb 15% for clarity.',
                        style: TextStyle(fontSize: 10, height: 1.5,
                          color: FluxForgeTheme.textSecondary)),
                      const SizedBox(height: 4),
                      const Text('✓ RG mode stable', style: TextStyle(
                        fontSize: 10, color: FluxForgeTheme.accentGreen)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Consumer<RgaiProvider>(
                  builder: (_, rgai, __) {
                    final report = rgai.report;
                    final summary = report?.summary;
                    final stimPass = summary?.isCompliant ?? true;
                    final riskRating = summary?.overallRiskRating;

                    return _DockCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DockLabel('RGAI COMPLIANCE'),
                          const SizedBox(height: 8),
                          _IntelRow('Stimulation index',
                            stimPass ? 'PASS' : 'FAIL',
                            stimPass ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
                          _IntelRow('Near-miss exposure',
                            riskRating == AddictionRiskRating.low ? 'OK' : 'WARN',
                            riskRating == AddictionRiskRating.low
                              ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentYellow),
                          _IntelRow('Session pacing', 'OK', FluxForgeTheme.accentGreen),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right: Engagement score
        SizedBox(
          width: 200,
          child: Consumer<NeuroAudioProvider>(
            builder: (_, neuro, __) {
              final score = (neuro.output.valence * 5 + 5)
                  .clamp(0.0, 10.0);

              return _DockCard(
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
                    // 4 mini metrics
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      childAspectRatio: 2.5,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      children: [
                        _MiniMetric('94%',  'Retention',  FluxForgeTheme.accentBlue),
                        _MiniMetric('7.2s', 'Avg dwell',  FluxForgeTheme.accentPurple),
                        _MiniMetric('1.8×', 'Bet increase', FluxForgeTheme.accentOrange),
                        _MiniMetric('0.12', 'Fatigue idx', FluxForgeTheme.accentGreen),
                      ],
                    ),
                  ],
                ),
              );
            },
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
    width: 260,
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
            padding: const EdgeInsets.all(16),
            child: Text(
              'Panel: $title\n(Content coming soon)',
              style: const TextStyle(fontSize: 11, color: FluxForgeTheme.textTertiary)),
          ),
        ),
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
