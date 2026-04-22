/// PHASE 9 — Live Play Companion Mode
///
/// Floating OrbMixer overlay that sits on top of PremiumSlotPreview so the
/// player/sound-designer can mix audio in real time while the slot is playing.
///
/// Features:
///   • Draggable + snaps to the nearest edge when released.
///   • 3 LOD size modes: mini (60px) / standard (120px) / full (200px).
///   • Transparency: 0.85 idle, 1.0 while interacting, fades to 0.40 after
///     3 seconds of no interaction (auto-hide).
///   • Keyboard dismiss hints: Escape toggles visibility.
///   • Persisted across restarts (SharedPreferences):
///       - psp_orb_overlay_x / psp_orb_overlay_y (Offset)
///       - psp_orb_overlay_mode (0=mini, 1=std, 2=full)
///       - psp_orb_overlay_visible (bool)
///   • Re-uses the same MixerDSPProvider singleton → every change made here
///     persists to the project mix automatically (no "save mix" button).
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

/// Overlay sizing modes
enum LivePlayOrbSize {
  mini(60.0, 'Mini'),
  standard(120.0, 'Standard'),
  full(200.0, 'Full');

  final double px;
  final String label;
  const LivePlayOrbSize(this.px, this.label);
}

/// LivePlayOrbOverlay — floating OrbMixer over slot preview.
///
/// Place as a [Positioned.fill] child of PremiumSlotPreview's outer Stack
/// (or wrap it in Positioned yourself). The widget positions itself
/// internally from saved prefs, so prefer `Positioned.fill`.
class LivePlayOrbOverlay extends StatefulWidget {
  /// MixerDSPProvider — should be the app-wide singleton so mix changes
  /// made via the overlay persist to the project.
  final MixerDSPProvider dsp;

  /// Initial size mode (overridden by saved prefs).
  final LivePlayOrbSize initialSize;

  /// Called when the overlay visibility toggles (e.g. keyboard Escape or
  /// programmatic hide). Lets the parent mirror the state in its own menu.
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
  // ─── Global accessor (for helix_action eye automation) ──────────────────
  /// Current mounted overlay state, if any. Used by HELIX eye-automation
  /// handlers to toggle / show / cycle the orb without touching the widget
  /// tree. Null when no PremiumSlotPreview is on screen.
  static LivePlayOrbOverlayState? _current;
  static LivePlayOrbOverlayState? get current => _current;

  // ─── Persistence keys ────────────────────────────────────────────────────
  static const _prefKeyX = 'psp_orb_overlay_x';
  static const _prefKeyY = 'psp_orb_overlay_y';
  static const _prefKeyMode = 'psp_orb_overlay_mode';
  static const _prefKeySizePx = 'psp_orb_overlay_size_px';
  static const _prefKeyVisible = 'psp_orb_overlay_visible';

  /// Smooth-resize bounds. Min = still usable (bus dots readable),
  /// max = hard cap; the effective max is also clamped against the
  /// viewport so the orb never eats more than ~40% of the screen width.
  static const double _minSizePx = 60.0;
  static const double _maxSizePx = 320.0;

  /// Maximum fraction of viewport width/height the orb is allowed to occupy.
  static const double _maxViewportFraction = 0.42;

  // ─── Autohide / opacity timings ──────────────────────────────────────────
  static const Duration _autoHideDelay = Duration(seconds: 3);
  static const Duration _opacityDuration = Duration(milliseconds: 220);
  static const Duration _snapDuration = Duration(milliseconds: 180);

  static const double _opacityIdle = 0.85;
  static const double _opacityActive = 1.0;
  static const double _opacityDormant = 0.40;

  // ─── State ───────────────────────────────────────────────────────────────
  Offset _position = const Offset(16, 16); // will be replaced on first layout
  bool _hasInitialPosition = false;
  /// Legacy discrete mode kept for Shift+O "cycle" keyboard shortcut and
  /// the helix_action `orb_cycle_size`. Smooth resize via the corner drag
  /// handle updates `_currentSizePx` directly and bypasses this.
  LivePlayOrbSize _sizeMode = LivePlayOrbSize.standard;
  /// Actual rendered size in px. Smooth-resizable via corner handle.
  double _currentSizePx = 120.0;
  /// Whether the user is actively resizing right now (opacity stays full).
  bool _isResizing = false;
  bool _visible = true;
  bool _interacting = false;
  bool _dormant = false;
  Timer? _autoHideTimer;
  bool _settingsLoaded = false;

  /// PHASE 10: OrbMixer provider reference (received via onProviderReady).
  /// Null until the nested OrbMixer mounts. Used for Quick Filter toggling
  /// and Auto-Focus zoom from the overlay's UI chrome.
  OrbMixerProvider? _orbProvider;

  @override
  void initState() {
    super.initState();
    _sizeMode = widget.initialSize;
    _current = this;
    _loadSettings();
    // Phase 10e: ensure inbox is hydrated so the badge count is correct
    // on first render.
    ProblemsInboxService.instance.init();
    ProblemsInboxService.instance.addListener(_onInboxChanged);
  }

  void _onInboxChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _orbProvider?.removeListener(_onOrbProviderChanged);
    _orbProvider = null;
    ProblemsInboxService.instance.removeListener(_onInboxChanged);
    if (_current == this) _current = null;
    super.dispose();
  }

  /// Phase 10e: Capture current mix state as a new Problem entry.
  Future<void> _markProblem() async {
    final orb = _orbProvider;
    if (orb == null) return;
    final snapshot = SharedMeterReader.instance.readMeters();
    String? fsmState;
    double bet = 0;
    try {
      final gf = GetIt.instance<GameFlowProvider>();
      fsmState = gf.currentState.name;
    } catch (_) {}
    await ProblemsInboxService.instance.capture(
      orb: orb,
      snapshot: snapshot,
      fsmState: fsmState,
      bet: bet,
    );
    _restartAutoHide();
  }

  /// Explicit show (public API — used by eye automation + menu).
  void show() {
    if (_visible) return;
    setState(() => _visible = true);
    widget.onVisibilityChanged?.call(true);
    _restartAutoHide();
    _saveSettings();
  }

  /// Explicit hide (public API).
  void hide() {
    if (!_visible) return;
    setState(() => _visible = false);
    widget.onVisibilityChanged?.call(false);
    _saveSettings();
  }

  // ─── Persistence ─────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final savedX = prefs.getDouble(_prefKeyX);
      final savedY = prefs.getDouble(_prefKeyY);
      if (savedX != null && savedY != null) {
        _position = Offset(savedX, savedY);
        _hasInitialPosition = true;
      }
      final savedMode = prefs.getInt(_prefKeyMode);
      if (savedMode != null &&
          savedMode >= 0 &&
          savedMode < LivePlayOrbSize.values.length) {
        _sizeMode = LivePlayOrbSize.values[savedMode];
      }
      // Smooth-resize override: if user has saved a custom size, prefer it.
      final savedSize = prefs.getDouble(_prefKeySizePx);
      if (savedSize != null) {
        _currentSizePx = savedSize.clamp(_minSizePx, _maxSizePx);
      } else {
        _currentSizePx = _sizeMode.px;
      }
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
    await prefs.setDouble(_prefKeySizePx, _currentSizePx);
    await prefs.setBool(_prefKeyVisible, _visible);
  }

  // ─── Auto-hide timer ─────────────────────────────────────────────────────

  void _restartAutoHide() {
    _autoHideTimer?.cancel();
    if (!_visible) return;
    if (_dormant) {
      setState(() => _dormant = false);
    }
    _autoHideTimer = Timer(_autoHideDelay, () {
      if (!mounted) return;
      setState(() => _dormant = true);
    });
  }

  // ─── Public API (used via GlobalKey from PremiumSlotPreview) ─────────────

  /// Toggle visibility. Returns the new visibility state.
  bool toggleVisible() {
    setState(() {
      _visible = !_visible;
      if (_visible) {
        _dormant = false;
      }
    });
    widget.onVisibilityChanged?.call(_visible);
    _restartAutoHide();
    _saveSettings();
    return _visible;
  }

  /// Cycle through preset sizes: mini → standard → full → mini.
  /// Snaps _currentSizePx to the new preset for the keyboard/menu shortcut.
  LivePlayOrbSize cycleSizeMode() {
    setState(() {
      final nextIdx = (_sizeMode.index + 1) % LivePlayOrbSize.values.length;
      _sizeMode = LivePlayOrbSize.values[nextIdx];
      _currentSizePx = _sizeMode.px;
    });
    _restartAutoHide();
    _saveSettings();
    return _sizeMode;
  }

  /// Set exact size in px (60..480). Used by the resize handle drag +
  /// eye-automation for headless UI tests.
  void setSizePx(double px) {
    final clamped = px.clamp(_minSizePx, _maxSizePx);
    setState(() => _currentSizePx = clamped);
    _restartAutoHide();
    _saveSettings();
  }

  bool get isVisible => _visible;
  LivePlayOrbSize get sizeMode => _sizeMode;
  double get sizePx => _currentSizePx;

  // ─── Drag + snap (handle-only, inner orb gestures pass through) ─────────

  /// Reposition handle size (px). Handle sits in the top-left of the backdrop
  /// so the entire inner orb stays available for bus taps / drags / long-press.
  static const double _handleSize = 22.0;

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _interacting = true;
      _dormant = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, Size viewport) {
    final double sizePx = _sizeMode.px;
    final maxX = viewport.width - sizePx;
    final maxY = viewport.height - sizePx;
    setState(() {
      _position = Offset(
        (_position.dx + details.delta.dx).clamp(0.0, maxX < 0 ? 0.0 : maxX),
        (_position.dy + details.delta.dy).clamp(0.0, maxY < 0 ? 0.0 : maxY),
      );
    });
  }

  void _onDragEnd(DragEndDetails details, Size viewport) {
    // Snap to nearest edge (top/bottom/left/right) when within 96px.
    final double sizePx = _sizeMode.px;
    final centerX = _position.dx + sizePx / 2;
    final centerY = _position.dy + sizePx / 2;

    final leftDist = centerX;
    final rightDist = viewport.width - centerX;
    final topDist = centerY;
    final bottomDist = viewport.height - centerY;

    final minEdge = [leftDist, rightDist, topDist, bottomDist]
        .reduce((a, b) => a < b ? a : b);

    double snapX = _position.dx;
    double snapY = _position.dy;
    const double margin = 12.0;
    if (minEdge < 96.0) {
      if (minEdge == leftDist) snapX = margin;
      if (minEdge == rightDist) snapX = viewport.width - sizePx - margin;
      if (minEdge == topDist) snapY = margin;
      if (minEdge == bottomDist) snapY = viewport.height - sizePx - margin;
    }

    setState(() {
      _position = Offset(snapX, snapY);
      _interacting = false;
    });
    _restartAutoHide();
    _saveSettings();
  }

  /// Any pointer touching the orb at all — wakes it from dormant + resets
  /// the autohide timer. Does NOT capture the event (Listener is transparent
  /// to gesture arena), so the inner OrbMixer still receives its taps/drags.
  void _onAnyPointerDown(PointerDownEvent _) {
    if (_dormant || !_interacting) {
      setState(() => _dormant = false);
    }
    _restartAutoHide();
  }

  /// Pointer up inside the orb — restart autohide so the 3s count runs
  /// cleanly from the last touch rather than from drag start.
  void _onAnyPointerUp(PointerUpEvent _) {
    _restartAutoHide();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) return const SizedBox.shrink();

    // When hidden, render a tiny "show orb" reveal button in the bottom-
    // right corner so the user can always bring the orb back without
    // remembering the keyboard shortcut.
    if (!_visible) return _buildRevealButton();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);

        // Clamp current size to viewport: orb never exceeds 42% of the
        // narrower viewport dimension. This protects users who resize
        // the slot window smaller or load a saved size that used to fit.
        final double viewportMin = viewport.width < viewport.height
            ? viewport.width
            : viewport.height;
        final double effectiveMax =
            (viewportMin * _maxViewportFraction).clamp(_minSizePx, _maxSizePx);
        if (_currentSizePx > effectiveMax) {
          _currentSizePx = effectiveMax;
        }

        // Default position: TOP-RIGHT ispod HELIX header-a (80px down +
        // 16px right) — ne preklapa SPIN button area u donjem desnom uglu.
        if (!_hasInitialPosition) {
          final sizePx = _currentSizePx;
          _position = Offset(
            viewport.width - sizePx - 16.0,
            80.0,
          );
          _hasInitialPosition = true;
        }

        // If saved position would push the orb outside the viewport
        // (e.g. user resized the window, or saved at a different size),
        // clamp it into the safe area so it's always reachable + on-screen.
        final double maxX = (viewport.width - _currentSizePx - 4).clamp(0.0,
            double.infinity);
        final double maxY = (viewport.height - _currentSizePx - 4).clamp(0.0,
            double.infinity);
        if (_position.dx > maxX) _position = Offset(maxX, _position.dy);
        if (_position.dy > maxY) _position = Offset(_position.dx, maxY);

        final double sizePx = _currentSizePx;
        // Show full UI chrome only when the orb is big enough to absorb it.
        // Below ~80px the orb degrades into a compact indicator.
        final bool showChrome = sizePx >= 80.0;
        final double opacity = (_interacting || _isResizing)
            ? _opacityActive
            : (_dormant ? _opacityDormant : _opacityIdle);

        return Stack(
          children: [
            AnimatedPositioned(
              duration:
                  (_interacting || _isResizing) ? Duration.zero : _snapDuration,
              curve: Curves.easeOutCubic,
              left: _position.dx,
              top: _position.dy,
              width: sizePx,
              height: sizePx,
              child: AnimatedOpacity(
                duration: _opacityDuration,
                opacity: opacity,
                child: Listener(
                  // Transparent pointer listener: wakes orb + resets autohide
                  // but does NOT win the gesture arena, so inner OrbMixer
                  // bus-tap / drag-volume / long-press-expand all keep working.
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onAnyPointerDown,
                  onPointerUp: _onAnyPointerUp,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Layer 1: inner orb (full gesture pass-through)
                      Positioned.fill(child: _buildCompanion(sizePx)),
                      // Layer 2: dedicated drag handle (top-left corner).
                      // Only this zone captures pan gestures for reposition,
                      // so bus drags inside the orb stay untouched.
                      Positioned(
                        left: 0,
                        top: 0,
                        width: _handleSize,
                        height: _handleSize,
                        child: _buildDragHandle(viewport),
                      ),
                      // Layer 2b: resize handle (outside bottom-right corner).
                      // Drag diagonally to smooth-resize the orb. Always
                      // available so user can grow / shrink freely.
                      Positioned(
                        right: -6,
                        bottom: -6,
                        width: _handleSize,
                        height: _handleSize,
                        child: _buildResizeHandle(viewport),
                      ),
                      // Layer 3 (Phase 10): Auto-Focus button (top-right).
                      // Zooms into the loudest voice right now. Only shown
                      // when chrome fits; mini hides it to save space.
                      if (showChrome)
                        Positioned(
                          right: 0,
                          top: 0,
                          width: _handleSize,
                          height: _handleSize,
                          child: _buildFocusButton(),
                        ),
                      // Layer 4 (Phase 10): Quick Filter chip strip below
                      // the orb — pushed further down so the inner Mark
                      // and Inbox corner buttons never overlap the chips.
                      if (showChrome && _orbProvider != null)
                        Positioned(
                          // Chip strip horizontally centered wider than
                          // the orb so even long chip labels breathe.
                          left: -40,
                          right: -40,
                          bottom: -44,
                          child: _buildFilterChips(),
                        ),
                      // Layer 5 (Phase 10e): Mark Problem button (bottom-left).
                      if (showChrome)
                        Positioned(
                          left: 0,
                          bottom: 0,
                          width: _handleSize,
                          height: _handleSize,
                          child: _buildMarkButton(),
                        ),
                      // Layer 6 (Phase 10e): Inbox button w/ count badge
                      // (bottom-right — INSIDE corner).
                      if (showChrome)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          width: _handleSize,
                          height: _handleSize,
                          child: _buildInboxButton(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompanion(double sizePx) {
    // A faint drop shadow + circular backdrop helps the orb read over the
    // slot game art without obscuring it.
    return AnimatedContainer(
      duration: _snapDuration,
      curve: Curves.easeOutCubic,
      width: sizePx,
      height: sizePx,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.45),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 14,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: OrbMixer(
          dsp: widget.dsp,
          size: sizePx - 4, // inset for backdrop
          expandOnHover: false, // compact mode — no label expansion
          onProviderReady: (p) {
            if (!mounted) return;
            setState(() => _orbProvider = p);
            // Repaint chip strip when filters change.
            p.addListener(_onOrbProviderChanged);
          },
        ),
      ),
    );
  }

  void _onOrbProviderChanged() {
    if (mounted) setState(() {});
  }

  /// Small reveal button shown when the orb is hidden. Lives in the bottom-
  /// right corner so the user can always reopen the companion by clicking a
  /// clearly visible icon, even if they don't remember the keyboard shortcut.
  Widget _buildRevealButton() {
    return Stack(
      children: [
        Positioned(
          right: 16,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.graphic_eq,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Dedicated drag handle (small grip dots). Only this zone captures pan
  /// gestures for reposition, so inner OrbMixer gestures (bus drag, long-press,
  /// tap) remain untouched. Tap on handle cycles size; double-tap hides.
  Widget _buildDragHandle(Size viewport) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        cycleSizeMode();
      },
      onDoubleTap: () {
        // Explicit UI hide — user can bring it back via keyboard O.
        setState(() => _visible = false);
        widget.onVisibilityChanged?.call(false);
        _saveSettings();
      },
      onPanStart: _onDragStart,
      onPanUpdate: (d) => _onDragUpdate(d, viewport),
      onPanEnd: (d) => _onDragEnd(d, viewport),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.drag_indicator,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// PHASE 10: Auto-Focus button. Tap → provider.autoFocusLoudest() which
  /// opens Nivo 3 on the loudest active voice. One-shot "which sound is too
  /// loud" shortcut.
  Widget _buildFocusButton() {
    final hasAny = (_orbProvider?.loudestVoice() != null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final p = _orbProvider;
        if (p == null) return;
        p.autoFocusLoudest();
        _restartAutoHide();
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasAny
              ? Colors.redAccent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: hasAny
                ? Colors.redAccent.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.center_focus_strong,
            size: 13,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// Smooth resize handle — drag diagonally to grow / shrink the orb
  /// between 60 and 480 px. Sits just outside the bottom-right perimeter
  /// so it doesn't collide with the inbox button inside the corner.
  /// Drag delta is averaged between dx & dy so diagonal motion feels
  /// natural regardless of direction.
  Widget _buildResizeHandle(Size viewport) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        setState(() => _isResizing = true);
      },
      onPanUpdate: (d) {
        // Average of dx + dy gives symmetric growth.
        final double delta = (d.delta.dx + d.delta.dy) / 2;
        // Respect the 42%-of-viewport cap so orb never dominates the slot UI.
        final double viewportMin = viewport.width < viewport.height
            ? viewport.width
            : viewport.height;
        final double effectiveMax =
            (viewportMin * _maxViewportFraction).clamp(_minSizePx, _maxSizePx);
        final double nextSize = (_currentSizePx + delta * 2)
            .clamp(_minSizePx, effectiveMax);
        // Don't let the orb grow past the viewport — leave 12px margin.
        final double maxByViewport =
            (viewport.width - _position.dx - 12).clamp(_minSizePx, effectiveMax);
        final double maxByViewportY =
            (viewport.height - _position.dy - 12).clamp(_minSizePx, effectiveMax);
        final double safe = [nextSize, maxByViewport, maxByViewportY]
            .reduce((a, b) => a < b ? a : b);
        setState(() => _currentSizePx = safe);
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
            color: Colors.cyanAccent.withValues(alpha: 0.18),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.open_in_full,
              size: 11,
              color: Colors.cyanAccent,
            ),
          ),
        ),
      ),
    );
  }

  /// Phase 10e: Mark Problem button — flags the current mix state for
  /// later review. Uses a subtle red flag so user notices when fresh alerts
  /// are active, but stays unobtrusive when the mix is healthy.
  Widget _buildMarkButton() {
    final hasAlerts = (_orbProvider?.activeAlerts.isNotEmpty ?? false);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _markProblem,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasAlerts
              ? Colors.redAccent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: hasAlerts
                ? Colors.redAccent.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: const Center(
          child: Icon(Icons.flag, size: 13, color: Colors.white),
        ),
      ),
    );
  }

  /// Phase 10e: Inbox button — opens the Problems panel. Small numeric
  /// badge in the corner shows how many captures are queued.
  Widget _buildInboxButton() {
    final count = ProblemsInboxService.instance.count;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showProblemsInbox(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: const Center(
              child: Icon(Icons.inbox, size: 13, color: Colors.white),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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

  /// PHASE 10: Quick Filter chip strip under the orb. 4 chips (SFX, Loud,
  /// Recent, NoMute) AND-combine. Active chip cyan-bordered, inactive is
  /// subtle so it doesn't distract during play.
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
          final isOn = active.contains(f);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              p.toggleFilter(f);
              _restartAutoHide();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isOn
                    ? Colors.cyanAccent.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isOn
                      ? Colors.cyanAccent.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Text(
                f.label,
                style: TextStyle(
                  color: isOn
                      ? Colors.cyanAccent
                      : Colors.white.withValues(alpha: 0.75),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
