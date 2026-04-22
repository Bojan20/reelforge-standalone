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

  /// If true, always paint dB labels regardless of hover state.
  /// Use in compact overlay mode where hover is disabled.
  final bool alwaysShowLabels;

  /// Optional callback when a bus is tapped (for Nivo 2 expand)
  final ValueChanged<OrbBusId>? onBusTap;

  /// PHASE 10: Called once after provider is constructed so parent widgets
  /// (e.g., LivePlayOrbOverlay) can reach in and toggle quick filters or
  /// trigger auto-focus. Invoked on the next frame via addPostFrameCallback.
  final ValueChanged<OrbMixerProvider>? onProviderReady;

  const OrbMixer({
    super.key,
    required this.dsp,
    this.size = 120.0,
    this.expandOnHover = true,
    this.alwaysShowLabels = false,
    this.onBusTap,
    this.onProviderReady,
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

    // PHASE 10: Hand the provider reference to any parent that wants it
    // (e.g. Live Play overlay for Quick Filter chips + Auto-Focus).
    final cb = widget.onProviderReady;
    if (cb != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cb(_provider);
      });
    }

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

  // Track drag start position for tap-vs-drag detection
  Offset? _dragStartPos;
  OrbVoiceState? _draggingVoice;

  // Nivo 3: Long-press timer + arc drag state
  DateTime? _pointerDownTime;
  OrbVoiceState? _longPressCandidate;
  bool _isArcDragging = false;
  static const _longPressDuration = Duration(milliseconds: 400);

  void _onPointerDown(PointerDownEvent event) {
    final localPos = event.localPosition;
    _dragStartPos = localPos;
    _pointerDownTime = DateTime.now();
    _longPressCandidate = null;

    // Nivo 3: If detail is open, check arc hit first
    if (_provider.isDetailOpen) {
      final arcHit = _hitTestArc(localPos);
      if (arcHit >= 0) {
        _provider.startArcDrag(arcHit);
        _isArcDragging = true;
        HapticFeedback.selectionClick();
        setState(() {});
        return;
      }

      // Tap outside param ring → close detail
      final detailPos = _provider.detailPosition;
      final ringRadius = _provider.size * 0.18;
      if ((localPos - detailPos).distance > ringRadius + 10) {
        _provider.closeDetail();
        setState(() {});
        return;
      }
    }

    // In Nivo 2: check voice dots first
    if (_provider.isExpanded) {
      final voiceHit = _provider.hitTestVoice(localPos);
      if (voiceHit != null) {
        if (event.buttons == kSecondaryMouseButton) {
          // Right-click voice → mute
          _provider.setVoiceMute(voiceHit.voiceId,
              voiceHit.status != OrbVoiceStatus.fading);
          HapticFeedback.lightImpact();
          setState(() {});
          return;
        }
        // Track as potential long-press candidate for Nivo 3
        _longPressCandidate = voiceHit;
        _draggingVoice = voiceHit;
        return;
      }
    }

    // Bus dot hit test
    final hit = _provider.hitTest(localPos);
    if (hit == null) {
      // Tap on empty space in Nivo 2 → collapse
      if (_provider.isExpanded) {
        _provider.collapseBus();
        setState(() {});
      }
      return;
    }

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
    // Nivo 3: Arc drag
    if (_isArcDragging && _provider.isDetailOpen) {
      final detailPos = _provider.detailPosition;
      final delta = event.localPosition - detailPos;
      final angle = math.atan2(delta.dy, delta.dx);
      final normalizedValue = _angleToArcNormalized(angle);
      _provider.updateArcDrag(normalizedValue);
      setState(() {});
      return;
    }

    // Check for long-press transition (voice held > 400ms without much movement)
    if (_longPressCandidate != null && _draggingVoice != null) {
      final elapsed = DateTime.now().difference(_pointerDownTime!);
      final moved = _dragStartPos != null
          ? (event.localPosition - _dragStartPos!).distance
          : 0.0;

      if (elapsed >= _longPressDuration && moved < 8) {
        // Long-press detected → open Nivo 3 detail ring
        _provider.openDetail(_longPressCandidate!);
        _draggingVoice = null;
        _longPressCandidate = null;
        HapticFeedback.heavyImpact();
        setState(() {});
        return;
      }

      // If moved too much, cancel long-press candidate — treat as normal drag
      if (moved >= 8) {
        _longPressCandidate = null;
      }
    }

    // Voice drag (Nivo 2)
    if (_draggingVoice != null) {
      final center = Offset(_provider.size / 2, _provider.size / 2);
      final delta = event.localPosition - center;
      final distance = delta.distance;
      final maxRadius = _provider.size * 0.45;

      // Radial distance → volume
      final newVol = (distance / maxRadius * 1.5).clamp(0.0, 1.5);
      _provider.setVoiceVolume(_draggingVoice!.voiceId, newVol);

      // Angle → pan
      final angle = math.atan2(-delta.dy, delta.dx);
      final pan = (angle / (math.pi / 2)).clamp(-1.0, 1.0);
      _provider.setVoicePan(_draggingVoice!.voiceId, pan);

      setState(() {});
      return;
    }

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
    _longPressCandidate = null;
    _pointerDownTime = null;

    // Nivo 3: Arc drag end
    if (_isArcDragging) {
      _provider.endArcDrag();
      _isArcDragging = false;
      setState(() {});
      return;
    }

    // Voice drag end
    if (_draggingVoice != null) {
      // Check if this was a tap (minimal movement)
      final wasTap = _dragStartPos != null &&
          (event.localPosition - _dragStartPos!).distance < 4;
      _draggingVoice = null;
      _dragStartPos = null;
      setState(() {});
      return;
    }

    _dragStartPos = null;

    if (_provider.isDragging) {
      final wasDragging = _provider.draggingBus;
      final hit = _provider.hitTest(event.localPosition);
      final wasTap = _dragStartPos == null ||
          (event.localPosition - (_dragStartPos ?? event.localPosition))
                  .distance <
              4;

      _provider.endDrag();

      // If released on the same dot with minimal movement → tap action
      if (hit == wasDragging && wasDragging != null) {
        if (_provider.isExpanded && hit == _provider.expandedBus) {
          // Tap on already-expanded bus → collapse
          _provider.collapseBus();
        } else if (hit != OrbBusId.master) {
          // Tap on bus → expand (Nivo 2) or solo toggle
          _provider.expandBus(hit!);
          HapticFeedback.selectionClick();
        } else {
          // Master tap → solo toggle
          _provider.toggleSolo(hit!);
          HapticFeedback.selectionClick();
        }
        widget.onBusTap?.call(hit!);
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

  // ── Nivo 3: Arc helpers ──

  /// Hit-test which arc slider the pointer is on (-1 if none).
  /// Tests if pointer is within the arc ring radius band and within an arc's
  /// angular span.
  int _hitTestArc(Offset localPos) {
    if (!_provider.isDetailOpen) return -1;
    final detailPos = _provider.detailPosition;
    final delta = localPos - detailPos;
    final distance = delta.distance;

    // Arc ring: inner radius 65%, outer radius 85% of param ring radius
    final ringRadius = _provider.size * 0.18;
    final innerR = ringRadius * 0.65;
    final outerR = ringRadius * 1.1;

    if (distance < innerR || distance > outerR) return -1;

    // Compute angle from detail center
    final angle = math.atan2(delta.dy, delta.dx);

    // Check each arc's angular span
    for (final arc in OrbParamArc.values) {
      final start = arc.startAngle;
      final sweep = arc.sweepAngle;
      final end = start + sweep;

      // Normalize angle to match arc range
      var a = angle;
      // Handle wrap-around
      while (a < start - math.pi) {
        a += 2 * math.pi;
      }
      while (a > start + math.pi) {
        a -= 2 * math.pi;
      }

      if (a >= start && a <= end) {
        return arc.index;
      }
    }
    return -1;
  }

  /// Convert a drag angle (relative to detail center) to normalized 0..1 value
  /// within the active arc's angular span.
  double _angleToArcNormalized(double angle) {
    if (_provider.activeArcIndex < 0) return 0.0;
    final arc = OrbParamArc.values[_provider.activeArcIndex];
    final start = arc.startAngle;
    final sweep = arc.sweepAngle;

    // Normalize angle to be relative to arc start
    var a = angle;
    while (a < start - math.pi) {
      a += 2 * math.pi;
    }
    while (a > start + math.pi) {
      a -= 2 * math.pi;
    }

    return ((a - start) / sweep).clamp(0.0, 1.0);
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
                showLabels: widget.alwaysShowLabels || _isHovered,
                hoveredBus: _hoveredBus,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
