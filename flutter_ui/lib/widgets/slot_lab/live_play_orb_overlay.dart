/// PHASE 9 — Live Play Companion Mode (ULTIMATE REWRITE)
///
/// Floating OrbMixer overlay that sits on top of PremiumSlotPreview so the
/// player/sound-designer can mix audio in real time while the slot is playing.
///
/// Layout architecture (SYMMETRIC EAR — guaranteed zero hitbox conflicts):
///
///   ┌────────────────────────────────────┐
///   │  [Drag⠿]     ear     [Focus⊕]     │  ← top ear (earPx)
///   ├────────────────────────────────────┤
///   │                                    │
///   │          OrbMixer circle           │  ← orbPx × orbPx
///   │         (audio bus mixer)          │
///   │                                    │
///   ├────────────────────────────────────┤
///   │  [Mark⚐]     ear     [Inbox📥]     │  ← bottom ear (earPx)
///   └────────────────────────────────────┘
///   │     [SFX] [Loud] [Recent] [NoMute]  │  ← chips (outside bounds, Clip.none)
///
///   Resize handle: tiny dot at bottom-right corner of outer bounds.
///   All 4 corner buttons sit fully OUTSIDE the OrbMixer circle →
///   guaranteed hit-testable without gesture-arena conflicts.
///
/// Features:
///   • Draggable + snaps to the nearest edge when released.
///   • Smooth resize via bottom-right corner handle (60 → 320 px).
///   • 3 LOD size modes: mini (60px) / standard (140px) / full (220px).
///   • Transparency: 0.85 idle, 1.0 while interacting, fades to 0.55 dormant.
///   • Keyboard dismiss: Escape toggles visibility.
///   • Persisted across restarts (SharedPreferences).
///   • Re-uses MixerDSPProvider singleton — every change persists automatically.
library;

import 'dart:async';
import 'package:flutter/material.dart';
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
  mini(60.0, 'Mini'),
  standard(140.0, 'Standard'),
  full(220.0, 'Full');

  final double px;
  final String label;
  const LivePlayOrbSize(this.px, this.label);
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

class LivePlayOrbOverlayState extends State<LivePlayOrbOverlay> {
  // ─── Global accessor ────────────────────────────────────────────────────────
  static LivePlayOrbOverlayState? _current;
  static LivePlayOrbOverlayState? get current => _current;

  // ─── Persistence keys ────────────────────────────────────────────────────────
  static const _prefKeyX       = 'psp_orb_overlay_x';
  static const _prefKeyY       = 'psp_orb_overlay_y';
  static const _prefKeyMode    = 'psp_orb_overlay_mode';
  static const _prefKeySizePx  = 'psp_orb_overlay_size_px';
  static const _prefKeyVisible = 'psp_orb_overlay_visible';

  // ─── Sizing constants ───────────────────────────────────────────────────────
  /// Space AROUND the orb on all sides.  Buttons live here — fully outside
  /// the orb circle — so no gesture-arena conflicts with OrbMixer.
  static const double _earPx = 32.0;

  /// Visible button size inside each ear cell.
  static const double _btnPx = 26.0;

  /// Padding between button edge and ear boundary.
  static const double _btnPad = (_earPx - _btnPx) / 2; // 3 px

  /// Resize handle corner size (tiny dot, bottom-right of total bounds).
  static const double _resizePx = 16.0;

  static const double _minOrbPx = 60.0;
  static const double _maxOrbPx = 320.0;
  static const double _maxViewportFraction = 0.42;

  // ─── Autohide / opacity ─────────────────────────────────────────────────────
  static const Duration _autoHideDelay  = Duration(seconds: 3);
  static const Duration _opacityDur    = Duration(milliseconds: 220);
  static const Duration _snapDur       = Duration(milliseconds: 180);

  static const double _opacityIdle    = 0.87;
  static const double _opacityActive  = 1.0;
  static const double _opacityDormant = 0.55; // raised from 0.40 — buttons stay readable

  // ─── State ───────────────────────────────────────────────────────────────────
  Offset _position         = const Offset(16, 16);
  bool   _hasInitialPos    = false;
  LivePlayOrbSize _sizeMode  = LivePlayOrbSize.standard;
  double _orbPx            = 140.0;
  bool   _isResizing       = false;
  bool   _visible          = true;
  bool   _interacting      = false;
  bool   _dormant          = false;
  Timer? _autoHideTimer;
  bool   _settingsLoaded   = false;

  OrbMixerProvider? _orbProvider;

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
  }

  void _onInboxChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
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
      _orbPx = (ss != null)
          ? ss.clamp(_minOrbPx, _maxOrbPx)
          : _sizeMode.px;
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
      _sizeMode = LivePlayOrbSize.values[(_sizeMode.index + 1) % LivePlayOrbSize.values.length];
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

  // ─── Drag helpers ────────────────────────────────────────────────────────────
  void _onDragStart(DragStartDetails _) {
    setState(() { _interacting = true; _dormant = false; });
  }

  void _onDragUpdate(DragUpdateDetails d, Size vp) {
    final totalW = _orbPx + 2 * _earPx;
    final totalH = _orbPx + 2 * _earPx;
    final maxX = (vp.width  - totalW - 8).clamp(0.0, double.infinity);
    final maxY = (vp.height - totalH - 8).clamp(0.0, double.infinity);
    setState(() {
      _position = Offset(
        (_position.dx + d.delta.dx).clamp(0.0, maxX),
        (_position.dy + d.delta.dy).clamp(0.0, maxY),
      );
    });
  }

  void _onDragEnd(DragEndDetails _, Size vp) {
    final totalW = _orbPx + 2 * _earPx;
    final totalH = _orbPx + 2 * _earPx;
    final cx = _position.dx + totalW / 2;
    final cy = _position.dy + totalH / 2;

    final ld = cx;
    final rd = vp.width  - cx;
    final td = cy;
    final bd = vp.height - cy;
    final minE = [ld, rd, td, bd].reduce((a, b) => a < b ? a : b);

    double sx = _position.dx, sy = _position.dy;
    const m = 12.0;
    if (minE < 96.0) {
      if (minE == ld) sx = m;
      if (minE == rd) sx = vp.width  - totalW - m;
      if (minE == td) sy = m;
      if (minE == bd) sy = vp.height - totalH - m;
    }
    setState(() { _position = Offset(sx, sy); _interacting = false; });
    _restartAutoHide();
    _saveSettings();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (_dormant) setState(() => _dormant = false);
    _restartAutoHide();
  }

  void _onPointerUp(PointerUpEvent _) { _restartAutoHide(); }

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

  // ─── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) return const SizedBox.shrink();
    if (!_visible) return _buildRevealButton();

    return LayoutBuilder(builder: (ctx, constraints) {
      final vp = Size(constraints.maxWidth, constraints.maxHeight);

      // Clamp orb size to viewport fraction
      final vpMin = vp.width < vp.height ? vp.width : vp.height;
      final effMax = (vpMin * _maxViewportFraction).clamp(_minOrbPx, _maxOrbPx);
      if (_orbPx > effMax) _orbPx = effMax;

      final double orbPx  = _orbPx;
      final double totalW = orbPx + 2 * _earPx;
      final double totalH = orbPx + 2 * _earPx;

      // Default position: top-right, below header
      if (!_hasInitialPos) {
        _position = Offset(vp.width - totalW - 12, 80.0);
        _hasInitialPos = true;
      }

      // Clamp position so entire orb stays on-screen
      final maxX = (vp.width  - totalW - 8).clamp(0.0, double.infinity);
      final maxY = (vp.height - totalH - 8).clamp(0.0, double.infinity);
      if (_position.dx > maxX) _position = Offset(maxX, _position.dy);
      if (_position.dy > maxY) _position = Offset(_position.dx, maxY);

      final bool showChrome = orbPx >= 80.0;
      final double opacity = (_interacting || _isResizing)
          ? _opacityActive
          : (_dormant ? _opacityDormant : _opacityIdle);

      return Stack(children: [
        AnimatedPositioned(
          duration: (_interacting || _isResizing) ? Duration.zero : _snapDur,
          curve: Curves.easeOutCubic,
          left: _position.dx,
          top:  _position.dy,
          width:  totalW,
          height: totalH,
          child: AnimatedOpacity(
            duration: _opacityDur,
            opacity: opacity,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerUp:   _onPointerUp,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Layer 0: orb body — centred in total bounds ────────────
                  Positioned(
                    left:   _earPx,
                    top:    _earPx,
                    width:  orbPx,
                    height: orbPx,
                    child: _buildOrbBody(orbPx),
                  ),

                  // ── Layer 1: Drag handle — top-LEFT ear ───────────────────
                  Positioned(
                    left:   _btnPad,
                    top:    _btnPad,
                    width:  _btnPx,
                    height: _btnPx,
                    child: _buildDragHandle(vp),
                  ),

                  // ── Layer 2: Focus button — top-RIGHT ear ─────────────────
                  if (showChrome)
                    Positioned(
                      right:  _btnPad,
                      top:    _btnPad,
                      width:  _btnPx,
                      height: _btnPx,
                      child: _buildFocusButton(),
                    ),

                  // ── Layer 3: Mark button — bottom-LEFT ear ────────────────
                  if (showChrome)
                    Positioned(
                      left:   _btnPad,
                      bottom: _btnPad,
                      width:  _btnPx,
                      height: _btnPx,
                      child: _buildMarkButton(),
                    ),

                  // ── Layer 4: Inbox button — bottom-RIGHT ear ──────────────
                  if (showChrome)
                    Positioned(
                      right:  _btnPad + _resizePx + 2, // leave room for resize dot
                      bottom: _btnPad,
                      width:  _btnPx,
                      height: _btnPx,
                      child: _buildInboxButton(),
                    ),

                  // ── Layer 5: Resize dot — extreme bottom-RIGHT corner ─────
                  Positioned(
                    right:  0,
                    bottom: 0,
                    width:  _resizePx,
                    height: _resizePx,
                    child: _buildResizeHandle(vp),
                  ),

                  // ── Layer 6: Filter chips — below orb, outside bounds ─────
                  if (showChrome && _orbProvider != null)
                    Positioned(
                      left:   -32,
                      right:  -32,
                      top:    totalH + 6,
                      child:  _buildFilterChips(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ]);
    });
  }

  // ─── Orb body ─────────────────────────────────────────────────────────────────
  Widget _buildOrbBody(double orbPx) {
    return Container(
      width:  orbPx,
      height: orbPx,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.60),
            blurRadius: 18,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: OrbMixer(
          dsp: widget.dsp,
          size: orbPx - 4,
          expandOnHover: false,
          onProviderReady: (p) {
            if (!mounted) return;
            setState(() => _orbProvider = p);
            p.addListener(_onOrbProviderChanged);
          },
        ),
      ),
    );
  }

  // ─── Drag handle (top-left) ───────────────────────────────────────────────────
  Widget _buildDragHandle(Size vp) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: cycleSizeMode,
      onDoubleTap: () {
        setState(() => _visible = false);
        widget.onVisibilityChanged?.call(false);
        _saveSettings();
      },
      onPanStart:  _onDragStart,
      onPanUpdate: (d) => _onDragUpdate(d, vp),
      onPanEnd:    (d) => _onDragEnd(d, vp),
      child: _earButton(
        icon: Icons.drag_indicator,
        color: Colors.white,
        bg: Colors.white.withValues(alpha: 0.15),
        border: Colors.white.withValues(alpha: 0.35),
        iconSize: 14,
      ),
    );
  }

  // ─── Auto-focus button (top-right) ────────────────────────────────────────────
  Widget _buildFocusButton() {
    final hasAny = (_orbProvider?.loudestVoice() != null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _orbProvider?.autoFocusLoudest();
        _restartAutoHide();
      },
      child: _earButton(
        icon: Icons.center_focus_strong,
        color: Colors.white,
        bg: hasAny
            ? Colors.redAccent.withValues(alpha: 0.40)
            : Colors.white.withValues(alpha: 0.10),
        border: hasAny
            ? Colors.redAccent.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.28),
        iconSize: 13,
      ),
    );
  }

  // ─── Mark problem button (bottom-left) ────────────────────────────────────────
  Widget _buildMarkButton() {
    final hasAlerts = (_orbProvider?.activeAlerts.isNotEmpty ?? false);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _markProblem,
      child: _earButton(
        icon: Icons.flag,
        color: Colors.white,
        bg: hasAlerts
            ? Colors.redAccent.withValues(alpha: 0.40)
            : Colors.white.withValues(alpha: 0.10),
        border: hasAlerts
            ? Colors.redAccent.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.28),
        iconSize: 13,
      ),
    );
  }

  // ─── Inbox button (bottom-right, left of resize dot) ─────────────────────────
  Widget _buildInboxButton() {
    final count = ProblemsInboxService.instance.count;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showProblemsInbox(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _earButton(
            icon: Icons.inbox,
            color: Colors.white,
            bg: Colors.white.withValues(alpha: 0.10),
            border: Colors.white.withValues(alpha: 0.28),
            iconSize: 13,
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top:   -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(minWidth: 14),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Resize dot (bottom-right corner) ────────────────────────────────────────
  Widget _buildResizeHandle(Size vp) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => setState(() => _isResizing = true),
      onPanUpdate: (d) {
        final delta = (d.delta.dx + d.delta.dy) / 2;
        final vpMin = vp.width < vp.height ? vp.width : vp.height;
        final effMax = (vpMin * _maxViewportFraction).clamp(_minOrbPx, _maxOrbPx);
        final maxByVP = [
          vp.width  - _position.dx - 2 * _earPx - 12,
          vp.height - _position.dy - 2 * _earPx - 12,
        ].reduce((a, b) => a < b ? a : b).clamp(_minOrbPx, effMax);
        final next = (_orbPx + delta * 2).clamp(_minOrbPx, maxByVP);
        setState(() => _orbPx = next);
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
            borderRadius: BorderRadius.circular(4),
            color: Colors.cyanAccent.withValues(alpha: 0.25),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.60),
              width: 1,
            ),
          ),
          child: const Center(
            child: Icon(Icons.open_in_full, size: 9, color: Colors.cyanAccent),
          ),
        ),
      ),
    );
  }

  // ─── Reveal button (when orb is hidden) ──────────────────────────────────────
  Widget _buildRevealButton() {
    return Stack(children: [
      Positioned(
        right:  16,
        bottom: 16,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _visible = true);
            widget.onVisibilityChanged?.call(true);
            _restartAutoHide();
            _saveSettings();
          },
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.60),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.30), width: 1),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.50), blurRadius: 12)],
            ),
            child: const Center(
              child: Icon(Icons.graphic_eq, size: 18, color: Colors.white)),
          ),
        ),
      ),
    ]);
  }

  // ─── Filter chips ─────────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    final p = _orbProvider;
    if (p == null) return const SizedBox.shrink();
    final active = p.activeFilters;
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 3,
        children: OrbQuickFilter.values.map((f) {
          final on = active.contains(f);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () { p.toggleFilter(f); _restartAutoHide(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: on
                    ? Colors.cyanAccent.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: on
                      ? Colors.cyanAccent.withValues(alpha: 0.80)
                      : Colors.white.withValues(alpha: 0.20),
                  width: 1,
                ),
              ),
              child: Text(f.label,
                style: TextStyle(
                  color: on ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.75),
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4,
                )),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Shared ear-button factory ────────────────────────────────────────────────
  Widget _earButton({
    required IconData icon,
    required Color color,
    required Color bg,
    required Color border,
    double iconSize = 13,
  }) {
    return Container(
      width:  _btnPx,
      height: _btnPx,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: border, width: 1),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.35), blurRadius: 4)],
      ),
      child: Center(child: Icon(icon, size: iconSize, color: color)),
    );
  }
}
