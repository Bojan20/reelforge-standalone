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
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/mixer_dsp_provider.dart';
import 'orb_mixer.dart';

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
  // ─── Persistence keys ────────────────────────────────────────────────────
  static const _prefKeyX = 'psp_orb_overlay_x';
  static const _prefKeyY = 'psp_orb_overlay_y';
  static const _prefKeyMode = 'psp_orb_overlay_mode';
  static const _prefKeyVisible = 'psp_orb_overlay_visible';

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
  LivePlayOrbSize _sizeMode = LivePlayOrbSize.standard;
  bool _visible = true;
  bool _interacting = false;
  bool _dormant = false;
  Timer? _autoHideTimer;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _sizeMode = widget.initialSize;
    _loadSettings();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
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

  /// Cycle through size modes: mini → standard → full → mini.
  LivePlayOrbSize cycleSizeMode() {
    setState(() {
      final nextIdx = (_sizeMode.index + 1) % LivePlayOrbSize.values.length;
      _sizeMode = LivePlayOrbSize.values[nextIdx];
    });
    _restartAutoHide();
    _saveSettings();
    return _sizeMode;
  }

  bool get isVisible => _visible;
  LivePlayOrbSize get sizeMode => _sizeMode;

  // ─── Drag + snap ─────────────────────────────────────────────────────────

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
    // Snap to nearest edge (top/bottom/left/right) if within 48px
    final double sizePx = _sizeMode.px;
    final centerX = _position.dx + sizePx / 2;
    final centerY = _position.dy + sizePx / 2;

    final leftDist = centerX;
    final rightDist = viewport.width - centerX;
    final topDist = centerY;
    final bottomDist = viewport.height - centerY;

    final minEdge = [leftDist, rightDist, topDist, bottomDist]
        .reduce((a, b) => a < b ? a : b);

    final snapped = Offset(_position.dx, _position.dy);
    double snapX = snapped.dx;
    double snapY = snapped.dy;
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

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) return const SizedBox.shrink();
    if (!_visible) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);

        // Default position: bottom-right corner with 16px margin (first run)
        if (!_hasInitialPosition) {
          final sizePx = _sizeMode.px;
          _position = Offset(
            viewport.width - sizePx - 16.0,
            viewport.height - sizePx - 16.0,
          );
          _hasInitialPosition = true;
        }

        final double sizePx = _sizeMode.px;
        final double opacity = _interacting
            ? _opacityActive
            : (_dormant ? _opacityDormant : _opacityIdle);

        return Stack(
          children: [
            AnimatedPositioned(
              duration: _interacting ? Duration.zero : _snapDuration,
              curve: Curves.easeOutCubic,
              left: _position.dx,
              top: _position.dy,
              width: sizePx,
              height: sizePx,
              child: AnimatedOpacity(
                duration: _opacityDuration,
                opacity: opacity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () {
                    cycleSizeMode();
                  },
                  onLongPress: () {
                    // Long-press = hide (will come back via keyboard shortcut)
                    setState(() => _visible = false);
                    widget.onVisibilityChanged?.call(false);
                    _saveSettings();
                  },
                  onPanStart: _onDragStart,
                  onPanUpdate: (d) => _onDragUpdate(d, viewport),
                  onPanEnd: (d) => _onDragEnd(d, viewport),
                  child: _buildCompanion(sizePx),
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
        ),
      ),
    );
  }
}
