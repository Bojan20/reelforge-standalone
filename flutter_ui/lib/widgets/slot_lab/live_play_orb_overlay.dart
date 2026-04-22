/// PHASE 9 — Live Play Companion Mode (ULTIMATE v6 — CARD LAYOUT)
///
/// Floating mixer CARD — orb + every parameter visible at once.
///
/// Layout (standard 320×480):
/// ┌──────────────────────────────────────────────┐
/// │ ▓▓ MIXER      [−] [+] [⤒] [×]               │  ← 32px title bar
/// ├──────────────────────────────────────────────┤
/// │                                              │
/// │             ┌──────────────┐                 │
/// │             │              │                 │
/// │             │  OrbMixer    │                 │  ← centered, sized to fit
/// │             │              │                 │
/// │             └──────────────┘                 │
/// │                                              │
/// ├──────────────────────────────────────────────┤
/// │ BUSES                                        │
/// │ ● MST  -6.2dB  pk -3  C    [S] [M]           │
/// │ ● MUS -12.4dB  pk-15  L12  [S] [M]           │  ← all 6 always visible
/// │ ● SFX    -∞    pk -∞  C    [S] [M]           │
/// │ ● VO     -∞    pk -∞  C    [S] [M]           │
/// │ ● AMB  -8.3dB  pk -6  R5   [S] [M]           │
/// │ ● AUX    -∞    pk -∞  C    [S] [M]           │
/// ├──────────────────────────────────────────────┤
/// │ [SFX] [Loud] [Recent] [NoMute]   [⚐] [📥 3]  │  ← filters + actions
/// └──────────────────────────────────────────────┘
///                                            [⤢] ← corner resize
///
/// Design principles:
///   - Single card, glass-style, rounded 14px, border + shadow
///   - Every control labeled, sized 32×28 min (easy click on macOS)
///   - NO hidden gestures anywhere in the card
///   - Drag from title bar (big target), resize from bottom-right corner
///   - dB panel NOT toggleable — always visible as part of layout
///   - OrbMixer inside owns ONLY its own gestures (volume/pan/solo/mute)
///   - Filter chips + mark + inbox in footer row
///
/// Gestures:
///   Title bar drag    → move card
///   [−] button        → shrink orb
///   [+] button        → grow orb
///   [⤒] button        → cycle preset size (mini/std/full)
///   [×] button        → hide card (reveal button appears bottom-right)
///   [S]/[M] per bus   → solo/mute
///   filter chip       → toggle quick-filter
///   [⚐] mark          → capture current mix as problem
///   [📥] inbox        → open problems panel
///   corner dot [⤢]    → drag to smooth-resize
///   OrbMixer surface  → drag=volume/pan, tap=solo, right-click=mute,
///                       scroll=fine volume, long-press=voice detail
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/mixer_dsp_provider.dart';
import '../../providers/orb_mixer_provider.dart';
import '../../providers/slot_lab/game_flow_provider.dart';
import '../../services/problems_inbox_service.dart';
import '../../services/shared_meter_reader.dart';
import 'orb_mixer.dart';
import 'problems_inbox_panel.dart';

// ─── Size presets ─────────────────────────────────────────────────────────────

enum LivePlayOrbSize {
  mini(90.0, 'Mini'),
  standard(160.0, 'Standard'),
  full(240.0, 'Full');

  final double px;
  final String label;
  const LivePlayOrbSize(this.px, this.label);
}

// ─── dB conversion helpers ────────────────────────────────────────────────────
String _toDb(double linear) {
  if (linear <= 0.0001) return '-∞';
  final db = 20.0 * math.log(linear) / math.ln10;
  return '${db.toStringAsFixed(1)} dB';
}

String _toPeakDb(double linear) {
  if (linear <= 0.0001) return '-∞';
  final db = 20.0 * math.log(linear) / math.ln10;
  return db.toStringAsFixed(1);
}

String _toPan(double pan) {
  if (pan.abs() < 0.02) return 'C';
  final pct = (pan * 100).round().abs();
  return pan < 0 ? 'L$pct' : 'R$pct';
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class LivePlayOrbOverlay extends StatefulWidget {
  final MixerDSPProvider dsp;
  final LivePlayOrbSize initialSize;
  final ValueChanged<bool>? onVisibilityChanged;

  const LivePlayOrbOverlay({
    super.key,
    required this.dsp,
    this.initialSize = LivePlayOrbSize.standard,
    this.onVisibilityChanged,
  });

  @override
  State<LivePlayOrbOverlay> createState() => LivePlayOrbOverlayState();
}

class LivePlayOrbOverlayState extends State<LivePlayOrbOverlay>
    with SingleTickerProviderStateMixin {
  // ─── Global accessor ────────────────────────────────────────────────────────
  static LivePlayOrbOverlayState? _current;
  static LivePlayOrbOverlayState? get current => _current;

  // ─── Persistence keys ────────────────────────────────────────────────────────
  static const _prefKeyX       = 'psp_orb_overlay_x';
  static const _prefKeyY       = 'psp_orb_overlay_y';
  static const _prefKeyMode    = 'psp_orb_overlay_mode';
  static const _prefKeySizePx  = 'psp_orb_overlay_size_px';
  static const _prefKeyVisible = 'psp_orb_overlay_visible';

  // ─── Card dimensions ────────────────────────────────────────────────────────
  /// Horizontal padding inside card
  static const double _cardPadH   = 10.0;
  /// Title bar height (big drag target)
  static const double _titleH     = 34.0;
  /// Bus row height
  static const double _busRowH    = 22.0;
  /// Header label height ("BUSES")
  static const double _busHdrH    = 16.0;
  /// Footer row height (filters + actions)
  static const double _footerH    = 34.0;
  /// Resize handle (bottom-right corner)
  static const double _resizePx   = 16.0;
  /// Card content vertical gap
  static const double _vGap       = 6.0;

  /// Minimum orb diameter inside the card
  static const double _minOrbPx = 90.0;
  /// Maximum orb diameter inside the card
  static const double _maxOrbPx = 320.0;

  /// Max card fraction of viewport (so card doesn't eat screen)
  static const double _maxViewportFraction = 0.7;

  // ─── Autohide / opacity ─────────────────────────────────────────────────────
  static const Duration _autoHideDelay = Duration(seconds: 6);
  static const Duration _opacityDur    = Duration(milliseconds: 220);
  static const Duration _snapDur       = Duration(milliseconds: 180);

  static const double _opacityIdle    = 0.94;
  static const double _opacityActive  = 1.0;
  static const double _opacityDormant = 0.65;

  // ─── State ───────────────────────────────────────────────────────────────────
  Offset _position         = const Offset(16, 16);
  bool   _hasInitialPos    = false;
  LivePlayOrbSize _sizeMode  = LivePlayOrbSize.standard;
  double _orbPx            = 160.0;
  bool   _isResizing       = false;
  bool   _visible          = true;
  bool   _interacting      = false;
  bool   _dormant          = false;
  Timer? _autoHideTimer;
  bool   _settingsLoaded   = false;

  OrbMixerProvider? _orbProvider;

  /// Frame counter — driven by Ticker → forces bus rows to refresh at 60fps
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _meterTicker;

  // ─── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _sizeMode = widget.initialSize;
    _orbPx    = _sizeMode.px;
    _current  = this;
    _loadSettings();
    ProblemsInboxService.instance.init();
    ProblemsInboxService.instance.addListener(_onInboxChanged);
    // Drive bus-row meter refresh at display rate.
    // Only increments while visible — dormant state stays frozen to save GPU.
    _meterTicker = createTicker((_) {
      if (_visible && !_dormant && mounted) _frame.value++;
    });
    _meterTicker.start();
  }

  void _onInboxChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _meterTicker.dispose();
    _frame.dispose();
    _autoHideTimer?.cancel();
    _orbProvider?.removeListener(_onOrbProviderChanged);
    _orbProvider = null;
    ProblemsInboxService.instance.removeListener(_onInboxChanged);
    if (_current == this) _current = null;
    super.dispose();
  }

  // ─── Persistence ─────────────────────────────────────────────────────────────
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final sx = prefs.getDouble(_prefKeyX);
      final sy = prefs.getDouble(_prefKeyY);
      if (sx != null && sy != null) {
        _position = Offset(sx, sy);
        _hasInitialPos = true;
      }
      final sm = prefs.getInt(_prefKeyMode);
      if (sm != null && sm >= 0 && sm < LivePlayOrbSize.values.length) {
        _sizeMode = LivePlayOrbSize.values[sm];
      }
      final ss = prefs.getDouble(_prefKeySizePx);
      _orbPx = (ss != null) ? ss.clamp(_minOrbPx, _maxOrbPx) : _sizeMode.px;
      _visible = prefs.getBool(_prefKeyVisible) ?? true;
      _settingsLoaded = true;
    });
    widget.onVisibilityChanged?.call(_visible);
    _restartAutoHide();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKeyX, _position.dx);
    await prefs.setDouble(_prefKeyY, _position.dy);
    await prefs.setInt(_prefKeyMode, _sizeMode.index);
    await prefs.setDouble(_prefKeySizePx, _orbPx);
    await prefs.setBool(_prefKeyVisible, _visible);
  }

  // ─── Autohide ────────────────────────────────────────────────────────────────
  void _restartAutoHide() {
    _autoHideTimer?.cancel();
    if (!_visible) return;
    if (_dormant) setState(() => _dormant = false);
    _autoHideTimer = Timer(_autoHideDelay, () {
      if (!mounted) return;
      setState(() => _dormant = true);
    });
  }

  // ─── Public API ──────────────────────────────────────────────────────────────
  void show() {
    if (_visible) return;
    setState(() => _visible = true);
    widget.onVisibilityChanged?.call(true);
    _restartAutoHide();
    _saveSettings();
  }

  void hide() {
    if (!_visible) return;
    setState(() => _visible = false);
    widget.onVisibilityChanged?.call(false);
    _saveSettings();
  }

  bool toggleVisible() {
    setState(() {
      _visible = !_visible;
      if (_visible) _dormant = false;
    });
    widget.onVisibilityChanged?.call(_visible);
    _restartAutoHide();
    _saveSettings();
    return _visible;
  }

  LivePlayOrbSize cycleSizeMode() {
    setState(() {
      _sizeMode = LivePlayOrbSize.values[
          (_sizeMode.index + 1) % LivePlayOrbSize.values.length];
      _orbPx = _sizeMode.px;
    });
    _restartAutoHide();
    _saveSettings();
    return _sizeMode;
  }

  void setSizePx(double px) {
    setState(() => _orbPx = px.clamp(_minOrbPx, _maxOrbPx));
    _restartAutoHide();
    _saveSettings();
  }

  bool get isVisible  => _visible;
  LivePlayOrbSize get sizeMode => _sizeMode;
  double get sizePx   => _orbPx;

  // ─── Step size +/- ───────────────────────────────────────────────────────────
  static const double _sizeStep = 24.0;

  void _shrinkStep() {
    final next = (_orbPx - _sizeStep).clamp(_minOrbPx, _maxOrbPx);
    setSizePx(next);
  }

  void _growStep() {
    final next = (_orbPx + _sizeStep).clamp(_minOrbPx, _maxOrbPx);
    setSizePx(next);
  }

  // ─── Mark problem ────────────────────────────────────────────────────────────
  Future<void> _markProblem() async {
    final orb = _orbProvider;
    if (orb == null) return;
    final snapshot = SharedMeterReader.instance.readMeters();
    String? fsmState;
    try { fsmState = GetIt.instance<GameFlowProvider>().currentState.name; } catch (_) {}
    await ProblemsInboxService.instance.capture(
      orb: orb, snapshot: snapshot, fsmState: fsmState, bet: 0,
    );
    _restartAutoHide();
  }

  void _onOrbProviderChanged() { if (mounted) setState(() {}); }

  // ─── Card geometry ───────────────────────────────────────────────────────────
  /// Card width based on orb size (ensures minimum for readable bus rows)
  double _cardW(double orbPx) {
    const minCardW = 320.0;
    return math.max(minCardW, orbPx + 2 * _cardPadH);
  }

  /// Card height: title + gap + orb + gap + busHdr + 6×busRow + gap + footer + gap
  double _cardH(double orbPx) {
    return _titleH
         + _vGap + orbPx
         + _vGap + _busHdrH
         + 6 * _busRowH
         + _vGap + _footerH
         + _cardPadH; // bottom padding
  }

  // ─── Drag (title bar) ────────────────────────────────────────────────────────
  void _onDragStart(DragStartDetails _) {
    setState(() { _interacting = true; _dormant = false; });
  }

  void _onDragUpdate(DragUpdateDetails d, Size vp, double cardW, double cardH) {
    final maxX = (vp.width  - cardW - 8).clamp(0.0, double.infinity);
    final maxY = (vp.height - cardH - 8).clamp(0.0, double.infinity);
    setState(() {
      _position = Offset(
        (_position.dx + d.delta.dx).clamp(0.0, maxX),
        (_position.dy + d.delta.dy).clamp(0.0, maxY),
      );
    });
  }

  void _onDragEnd(DragEndDetails _, Size vp, double cardW, double cardH) {
    setState(() => _interacting = false);
    _restartAutoHide();
    _saveSettings();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (_dormant) setState(() => _dormant = false);
    _restartAutoHide();
  }

  void _onPointerUp(PointerUpEvent _) { _restartAutoHide(); }

  // ─── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) return const SizedBox.shrink();
    if (!_visible) return _buildRevealButton();

    return LayoutBuilder(builder: (ctx, constraints) {
      final vp = Size(constraints.maxWidth, constraints.maxHeight);

      // Clamp orb size to viewport
      final vpMin = vp.width < vp.height ? vp.width : vp.height;
      final effMax = (vpMin * _maxViewportFraction).clamp(_minOrbPx, _maxOrbPx);
      if (_orbPx > effMax) _orbPx = effMax;

      final double orbPx = _orbPx;
      final double cardW = _cardW(orbPx);
      final double cardH = _cardH(orbPx);

      // Default position: top-right below header
      if (!_hasInitialPos) {
        _position = Offset(vp.width - cardW - 14, 80.0);
        _hasInitialPos = true;
      }

      // Clamp position to viewport
      final maxX = (vp.width  - cardW - 8).clamp(0.0, double.infinity);
      final maxY = (vp.height - cardH - 8).clamp(0.0, double.infinity);
      if (_position.dx > maxX) _position = Offset(maxX, _position.dy);
      if (_position.dy > maxY) _position = Offset(_position.dx, maxY);

      final double opacity = (_interacting || _isResizing)
          ? _opacityActive
          : (_dormant ? _opacityDormant : _opacityIdle);

      // Resize handle center sits at (cardW, cardH) relative to card origin.
      // It MUST be on the outer Stack so Flutter's hit-test covers it —
      // Clip.none on inner Stack renders outside bounds but hit-test is blocked.
      final double resizeLeft = _position.dx + cardW - _resizePx / 2;
      final double resizeTop  = _position.dy + cardH - _resizePx / 2;

      return Stack(
        children: [
          AnimatedPositioned(
            duration: (_interacting || _isResizing) ? Duration.zero : _snapDur,
            curve: Curves.easeOutCubic,
            left: _position.dx,
            top:  _position.dy,
            width:  cardW,
            height: cardH,
            child: AnimatedOpacity(
              duration: _opacityDur,
              opacity: opacity,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerUp:   _onPointerUp,
                child: _buildCard(orbPx, cardW, cardH, vp),
              ),
            ),
          ),
          // ─── Resize dot — outer Stack, always hit-testable ──────────────
          AnimatedPositioned(
            duration: (_interacting || _isResizing) ? Duration.zero : _snapDur,
            curve: Curves.easeOutCubic,
            left:   resizeLeft,
            top:    resizeTop,
            width:  _resizePx,
            height: _resizePx,
            child: AnimatedOpacity(
              duration: _opacityDur,
              opacity: opacity,
              child: _buildResizeHandle(vp),
            ),
          ),
        ],
      );
    });
  }

  // ─── Card (glass panel with title + orb + busses + footer) ─────────────────
  // Resize handle has been moved to the outer Stack — do NOT add it here.
  Widget _buildCard(double orbPx, double cardW, double cardH, Size vp) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0070710),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 18, spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTitleBar(cardW, cardH, vp),
            SizedBox(height: _vGap),
            _buildOrbSection(orbPx),
            SizedBox(height: _vGap),
            _buildBussesSection(),
            SizedBox(height: _vGap),
            _buildFooter(),
            SizedBox(height: _cardPadH),
          ],
        ),
      ),
    );
  }

  // ─── Title bar ───────────────────────────────────────────────────────────────
  Widget _buildTitleBar(double cardW, double cardH, Size vp) {
    return SizedBox(
      height: _titleH,
      child: Row(
        children: [
          // Drag zone: everything left of action buttons
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart:  _onDragStart,
              onPanUpdate: (d) => _onDragUpdate(d, vp, cardW, cardH),
              onPanEnd:    (d) => _onDragEnd(d, vp, cardW, cardH),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.06),
                        Colors.white.withValues(alpha: 0.02),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft:  Radius.circular(14),
                      topRight: Radius.circular(14),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(Icons.drag_indicator,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.55)),
                      const SizedBox(width: 6),
                      Text('MIXER',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 10, fontWeight: FontWeight.w800,
                          letterSpacing: 1.4, fontFamily: 'SpaceGrotesk',
                        )),
                      const SizedBox(width: 8),
                      Text(_sizeMode.label,
                        style: TextStyle(
                          color: Colors.cyanAccent.withValues(alpha: 0.70),
                          fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 0.8, fontFamily: 'SpaceGrotesk',
                        )),
                      const Spacer(),
                      Text('${_orbPx.toInt()}px',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 9, fontFamily: 'SpaceGrotesk',
                        )),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Action buttons: shrink, grow, preset-cycle, hide
          _titleBtn(
            icon: Icons.remove,
            tooltip: 'Shrink orb',
            onTap: _orbPx > _minOrbPx + 0.5 ? _shrinkStep : null,
          ),
          _titleBtn(
            icon: Icons.add,
            tooltip: 'Grow orb',
            onTap: _orbPx < _maxOrbPx - 0.5 ? _growStep : null,
          ),
          _titleBtn(
            icon: Icons.aspect_ratio,
            tooltip: 'Cycle preset size\n(Mini → Standard → Full)',
            onTap: () => cycleSizeMode(),
          ),
          _titleBtn(
            icon: Icons.close,
            tooltip: 'Hide mixer',
            onTap: hide,
            danger: true,
          ),
        ],
      ),
    );
  }

  Widget _titleBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final enabled = onTap != null;
    final color = danger
        ? (enabled ? Colors.redAccent : Colors.redAccent.withValues(alpha: 0.30))
        : (enabled ? Colors.white    : Colors.white.withValues(alpha: 0.25));
    return Tooltip(
      message: tooltip,
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            width: 34, height: _titleH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: danger && enabled
                  ? Colors.redAccent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: danger
                  ? const BorderRadius.only(topRight: Radius.circular(14))
                  : null,
              border: Border(
                left: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08), width: 1),
              ),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }

  // ─── Orb section (centered) ─────────────────────────────────────────────────
  Widget _buildOrbSection(double orbPx) {
    return SizedBox(
      height: orbPx,
      child: Center(
        child: Container(
          width:  orbPx,
          height: orbPx,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF0C0C18),
                const Color(0xFF060610),
              ],
              radius: 0.85,
            ),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.60),
              blurRadius: 14, spreadRadius: 1,
            )],
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: OrbMixer(
              dsp:               widget.dsp,
              size:              orbPx - 4,
              expandOnHover:     false,
              alwaysShowLabels:  true,
              onProviderReady:   (p) {
                if (!mounted) return;
                setState(() => _orbProvider = p);
                p.addListener(_onOrbProviderChanged);
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── Busses section (all 6 always visible, with dB/peak/pan/S/M) ───────────
  Widget _buildBussesSection() {
    // ValueListenableBuilder ensures bus rows repaint at ticker rate (60fps)
    // so dB values and peak bars stay live even without DSP state changes.
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (_, __, ___) => Padding(
        padding: EdgeInsets.symmetric(horizontal: _cardPadH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _busHdrH,
              child: Row(
                children: [
                  Text('BUSES',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 9, fontWeight: FontWeight.w800,
                      letterSpacing: 1.4, fontFamily: 'SpaceGrotesk',
                    )),
                  const SizedBox(width: 8),
                  Expanded(child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  )),
                ],
              ),
            ),
            ...OrbBusId.values.map(_buildBusRow),
          ],
        ),
      ),
    );
  }

  Widget _buildBusRow(OrbBusId busId) {
    final provider = _orbProvider;
    final bus = provider?.getBus(busId);
    final volume = bus?.volume ?? 0.0;
    final pan    = bus?.pan ?? 0.0;
    final peak   = bus?.peak ?? 0.0;
    final muted  = bus?.muted ?? false;
    final solo   = bus?.solo ?? false;

    final db      = _toDb(volume);
    final peakDb  = _toPeakDb(peak);
    final panTxt  = _toPan(pan);

    return SizedBox(
      height: _busRowH,
      child: Row(
        children: [
          // Color dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busId.color,
              boxShadow: peak > 0.4 ? [BoxShadow(
                color: busId.color.withValues(alpha: 0.8),
                blurRadius: 6,
              )] : null,
            ),
          ),
          const SizedBox(width: 6),
          // Bus label (3 chars)
          SizedBox(
            width: 30,
            child: Text(busId.label,
              style: TextStyle(
                color: busId.color,
                fontSize: 10, fontWeight: FontWeight.w800,
                fontFamily: 'SpaceGrotesk',
              )),
          ),
          // dB volume
          SizedBox(
            width: 56,
            child: Text(db,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: muted
                    ? Colors.white.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.92),
                fontSize: 10, fontWeight: FontWeight.w600,
                fontFamily: 'SpaceGrotesk',
              )),
          ),
          const SizedBox(width: 6),
          // Peak mini-meter
          _peakBar(peak),
          const SizedBox(width: 6),
          // Peak dB
          SizedBox(
            width: 30,
            child: Text('pk $peakDb',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 8, fontFamily: 'SpaceGrotesk',
              )),
          ),
          const SizedBox(width: 4),
          // Pan
          SizedBox(
            width: 22,
            child: Text(panTxt,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.75),
                fontSize: 9, fontWeight: FontWeight.w700,
                fontFamily: 'SpaceGrotesk',
              )),
          ),
          const Spacer(),
          // Solo
          _busChip(
            label: 'S',
            active: solo,
            activeColor: Colors.yellowAccent,
            tooltip: 'Solo',
            onTap: provider == null ? null : () {
              provider.toggleSolo(busId);
              _restartAutoHide();
            },
          ),
          const SizedBox(width: 3),
          // Mute
          _busChip(
            label: 'M',
            active: muted,
            activeColor: Colors.redAccent,
            tooltip: 'Mute',
            onTap: provider == null ? null : () {
              provider.toggleMute(busId);
              _restartAutoHide();
            },
          ),
        ],
      ),
    );
  }

  Widget _peakBar(double peak) {
    const w = 40.0, h = 4.0;
    final p = peak.clamp(0.0, 1.2);
    Color color;
    if (p < 0.6) {
      color = const Color(0xFF39D98A); // green
    } else if (p < 0.85) {
      color = const Color(0xFFF5C542); // yellow
    } else if (p < 1.0) {
      color = const Color(0xFFF58E42); // orange
    } else {
      color = const Color(0xFFE44D4D); // red (clip)
    }
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10), width: 0.5),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: w * p.clamp(0.0, 1.0),
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _busChip({
    required String label,
    required bool active,
    required Color activeColor,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            width: 18, height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: active
                  ? activeColor.withValues(alpha: 0.80)
                  : Colors.white.withValues(alpha: 0.07),
              border: Border.all(
                color: active
                    ? activeColor
                    : Colors.white.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: Text(label,
              style: TextStyle(
                color: active
                    ? (activeColor == Colors.yellowAccent ? Colors.black : Colors.white)
                    : Colors.white.withValues(alpha: 0.55),
                fontSize: 9, fontWeight: FontWeight.w900,
              )),
          ),
        ),
      ),
    );
  }

  // ─── Footer (filters + mark + inbox) ────────────────────────────────────────
  Widget _buildFooter() {
    final p = _orbProvider;
    final count = ProblemsInboxService.instance.count;
    final hasAlerts = (p?.activeAlerts.isNotEmpty ?? false);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _cardPadH),
      child: SizedBox(
        height: _footerH,
        child: Row(
          children: [
            // Filter chips (expand scroll if needed)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: OrbQuickFilter.values.map((f) {
                    final on = p?.activeFilters.contains(f) ?? false;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _filterChip(
                        label: f.label,
                        active: on,
                        onTap: p == null ? null : () {
                          p.toggleFilter(f);
                          _restartAutoHide();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Mark button
            _footerAction(
              icon: Icons.flag,
              tooltip: 'Mark current mix as problem',
              onTap: p == null ? null : _markProblem,
              highlight: hasAlerts,
              highlightColor: Colors.redAccent,
            ),
            const SizedBox(width: 4),
            // Inbox button (with count badge)
            _footerAction(
              icon: Icons.inbox,
              tooltip: 'Open problems inbox',
              onTap: () => showProblemsInbox(context),
              badge: count > 0 ? count : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: 'Filter: $label',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: active
                  ? Colors.cyanAccent.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: active
                    ? Colors.cyanAccent.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Text(label,
              style: TextStyle(
                color: active
                    ? Colors.cyanAccent
                    : Colors.white.withValues(alpha: 0.80),
                fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 0.4, fontFamily: 'SpaceGrotesk',
              )),
          ),
        ),
      ),
    );
  }

  Widget _footerAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    int? badge,
    bool highlight = false,
    Color? highlightColor,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34, height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: highlight
                      ? (highlightColor ?? Colors.white).withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: highlight
                        ? (highlightColor ?? Colors.white).withValues(alpha: 0.75)
                        : Colors.white.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                child: Icon(icon,
                  size: 14,
                  color: onTap != null
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.30)),
              ),
              if (badge != null)
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 14),
                    child: Text('$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8, fontWeight: FontWeight.w800,
                      )),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Resize handle (bottom-right corner, hangs half outside card) ───────────
  Widget _buildResizeHandle(Size vp) {
    return Tooltip(
      message: 'Drag to resize orb',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _isResizing = true),
        onPanUpdate: (d) {
          final delta = (d.delta.dx + d.delta.dy) / 2;
          final vpMin = vp.width < vp.height ? vp.width : vp.height;
          final effMax = (vpMin * _maxViewportFraction).clamp(_minOrbPx, _maxOrbPx);
          final maxByVP = [
            vp.width  - _position.dx - 2 * _cardPadH - 12,
            vp.height - _position.dy - (_titleH + _busHdrH + 6 * _busRowH + _footerH + 4 * _vGap + _cardPadH) - 12,
          ].reduce((a, b) => a < b ? a : b).clamp(_minOrbPx, effMax);
          setState(() => _orbPx = (_orbPx + delta * 2).clamp(_minOrbPx, maxByVP));
        },
        onPanEnd: (_) {
          setState(() => _isResizing = false);
          _restartAutoHide();
          _saveSettings();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeDownRight,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.cyanAccent.withValues(alpha: 0.30),
              border: Border.all(
                color: Colors.cyanAccent.withValues(alpha: 0.70), width: 1.2),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 6,
              )],
            ),
            child: const Center(
              child: Icon(Icons.open_in_full,
                size: 9, color: Colors.cyanAccent)),
          ),
        ),
      ),
    );
  }

  // ─── Reveal button (when card is hidden) ────────────────────────────────────
  Widget _buildRevealButton() {
    return Stack(children: [
      Positioned(
        right: 16, bottom: 16,
        child: Tooltip(
          message: 'Show mixer',
          waitDuration: const Duration(milliseconds: 500),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _visible = true);
              widget.onVisibilityChanged?.call(true);
              _restartAutoHide();
              _saveSettings();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.72),
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.55), width: 1.2),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 16,
                  )],
                ),
                child: const Center(
                  child: Icon(Icons.graphic_eq,
                    size: 20, color: Colors.cyanAccent)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// Suppress unused-import warning when not using ui.*
// ignore: unused_element
ui.ImageFilter _unused() => ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1);
