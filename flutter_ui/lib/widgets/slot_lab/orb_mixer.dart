// OrbMixer — Radial Audio Mixer Widget
//
// Compact futuristic mixer in a single circle (120×120px).
// All audio controls visible at a glance — volume, pan, solo, mute.
// No faders, no strips — pure polar visualization.
//
// Nivo 1: Orbit View (6 bus dots + master center)
// Gestovi: drag radial=volume, drag angular=pan, click=solo,
//          right-click=mute, scroll=fine volume, hover=labels
//
// 60fps animation via Ticker (meter updates from SharedMeterReader).
// Wired to MixerDSPProvider for engine FFI control.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../providers/mixer_dsp_provider.dart';
import '../../providers/orb_mixer_provider.dart';
import '../../services/shared_meter_reader.dart';
import 'orb_mixer_painter.dart';

/// Radial audio mixer — the OrbMixer.
///
/// Place in any layout (minimum 80×80px, optimal 120×120px).
/// Expands to 180×180px on hover to show dB labels.
///
/// Usage:
/// ```dart
/// OrbMixer(
///   dsp: sl<MixerDSPProvider>(),
///   size: 120,
/// )
/// ```
class OrbMixer extends StatefulWidget {
  /// MixerDSPProvider instance (from GetIt)
  final MixerDSPProvider dsp;

  /// Base size in pixels (default 120)
  final double size;

  /// If true, expand on hover to show dB labels
  final bool expandOnHover;

  /// Optional callback when a bus is tapped (for Nivo 2 expand)
  final ValueChanged<OrbBusId>? onBusTap;

  const OrbMixer({
    super.key,
    required this.dsp,
    this.size = 120.0,
    this.expandOnHover = true,
    this.onBusTap,
  });

  @override
  State<OrbMixer> createState() => _OrbMixerState();
}

class _OrbMixerState extends State<OrbMixer>
    with SingleTickerProviderStateMixin {
  late final OrbMixerProvider _provider;
  late final Ticker _ticker;

  OrbBusId? _hoveredBus;
  bool _isHovered = false;

  // Tooltip
  OverlayEntry? _tooltipOverlay;
  OrbBusId? _tooltipBus;

  @override
  void initState() {
    super.initState();

    _provider = OrbMixerProvider(
      dsp: widget.dsp,
      meters: SharedMeterReader.instance,
    );
    _provider.setSize(widget.size);

    // 60fps animation ticker for real-time meter updates
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void didUpdateWidget(OrbMixer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size) {
      _provider.setSize(widget.size);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _dismissTooltip();
    _provider.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // Update meter values from shared memory
    if (_provider.updateMeters()) {
      // Only rebuild if meters actually changed
      if (mounted) setState(() {});
    }
  }

  // ── Gesture handling ──

  void _onPointerDown(PointerDownEvent event) {
    final localPos = event.localPosition;
    final hit = _provider.hitTest(localPos);
    if (hit == null) return;

    if (event.buttons == kSecondaryMouseButton) {
      // Right-click → mute toggle
      _provider.toggleMute(hit);
      HapticFeedback.lightImpact();
      setState(() {});
    } else if (event.buttons == kPrimaryMouseButton) {
      // Left-click → start drag (solo on release if no movement)
      _provider.startDrag(hit);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_provider.isDragging) {
      _provider.updateDrag(event.localPosition);
      setState(() {});
    } else {
      // Hover hit test
      final hit = _provider.hitTest(event.localPosition);
      if (hit != _hoveredBus) {
        setState(() {
          _hoveredBus = hit;
        });
        if (hit != null) {
          _showTooltip(hit, event.position);
        } else {
          _dismissTooltip();
        }
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_provider.isDragging) {
      final wasDragging = _provider.draggingBus;
      // Check if this was a tap (very small movement) vs drag
      final hit = _provider.hitTest(event.localPosition);

      _provider.endDrag();

      // If released on the same dot without significant drag → solo toggle
      if (hit == wasDragging) {
        _provider.toggleSolo(hit!);
        HapticFeedback.selectionClick();

        // Notify parent (for Nivo 2 expand)
        widget.onBusTap?.call(hit);
      }
      setState(() {});
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final hit = _provider.hitTest(event.localPosition);
      if (hit != null) {
        // Scroll → fine volume (0.5dB steps)
        final delta = event.scrollDelta.dy > 0 ? -1.0 : 1.0;
        _provider.adjustVolume(hit, delta);
        setState(() {});
      }
    }
  }

  void _onHoverEnter(PointerEnterEvent event) {
    if (!widget.expandOnHover) return;
    setState(() {
      _isHovered = true;
      _provider.isHovered = true;
      _provider.setSize(widget.size); // triggers layout recalc with new size
    });
  }

  void _onHoverExit(PointerExitEvent event) {
    setState(() {
      _isHovered = false;
      _hoveredBus = null;
      _provider.isHovered = false;
      _provider.setSize(widget.size);
    });
    _dismissTooltip();
  }

  // ── Tooltip ──

  void _showTooltip(OrbBusId busId, Offset globalPos) {
    _dismissTooltip();
    _tooltipBus = busId;

    final state = _provider.getBus(busId);
    if (state == null) return;

    final db = state.volume <= 0.0001
        ? '-∞ dB'
        : '${(20.0 * math.log(state.volume) / math.ln10).toStringAsFixed(1)} dB';
    final peakDb = state.peak <= 0.0001
        ? '-∞'
        : '${(20.0 * math.log(state.peak) / math.ln10).toStringAsFixed(1)}';

    final status = [
      if (state.solo) 'S',
      if (state.muted) 'M',
    ].join(' ');

    final text = '${busId.label}  $db  pk:$peakDb${status.isNotEmpty ? '  [$status]' : ''}';

    _tooltipOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: globalPos.dx + 12,
        top: globalPos.dy - 28,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xE0101020),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: busId.color.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_tooltipOverlay!);
  }

  void _dismissTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
    _tooltipBus = null;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final currentSize = _provider.size;

    return MouseRegion(
      onEnter: _onHoverEnter,
      onExit: _onHoverExit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: currentSize,
        height: currentSize,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerSignal: _onPointerSignal,
          child: ClipOval(
            child: CustomPaint(
              size: Size(currentSize, currentSize),
              painter: OrbMixerPainter(
                provider: _provider,
                showLabels: _isHovered,
                hoveredBus: _hoveredBus,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
