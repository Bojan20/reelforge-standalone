// OrbMixer Provider — State management for the radial audio mixer
//
// Bridges MixerDSPProvider (bus state) + SharedMeterReader (real-time peaks)
// into a unified polar-coordinate model consumed by OrbMixerPainter.
//
// Bus layout (fixed angles):
//   Music: 90° (top), SFX: 0° (right), Ambience: 180° (left),
//   VO: 270° (bottom), Aux: 45° (top-right), Master: center

import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';

import '../services/shared_meter_reader.dart';
import '../theme/fluxforge_theme.dart';
import 'mixer_dsp_provider.dart';

// ============ Bus Identity ============

enum OrbBusId {
  master,
  music,
  sfx,
  voice,
  ambience,
  aux;

  /// Engine bus index (must match Rust playback.rs)
  int get engineIndex => switch (this) {
        master => 0,
        music => 1,
        sfx => 2,
        voice => 3,
        ambience => 4,
        aux => 5,
      };

  /// String ID used by MixerDSPProvider
  String get dspId => switch (this) {
        master => 'master',
        music => 'music',
        sfx => 'sfx',
        voice => 'voice',
        ambience => 'ambience',
        aux => 'aux',
      };

  /// Display name
  String get label => switch (this) {
        master => 'MST',
        music => 'MUS',
        sfx => 'SFX',
        voice => 'VO',
        ambience => 'AMB',
        aux => 'AUX',
      };

  /// Fixed angle on the orbit (radians, 0=right, counter-clockwise)
  double get baseAngle => switch (this) {
        music => math.pi / 2, // 90° top
        sfx => 0.0, // 0° right
        ambience => math.pi, // 180° left
        voice => 3 * math.pi / 2, // 270° bottom
        aux => math.pi / 4, // 45° top-right
        master => 0.0, // center (angle unused)
      };

  /// Category color
  Color get color => switch (this) {
        master => const Color(0xFFFFFFFF),
        music => FluxForgeTheme.accentBlue,
        sfx => FluxForgeTheme.accentOrange,
        voice => FluxForgeTheme.accentPurple,
        ambience => FluxForgeTheme.accentCyan,
        aux => FluxForgeTheme.accentGreen,
      };
}

// ============ Bus State ============

class OrbBusState {
  final OrbBusId id;

  /// Volume: 0.0 = -inf, 1.0 = 0dB, up to 1.5 = +3.5dB
  double volume;

  /// Pan: -1.0 left, 0.0 center, 1.0 right
  double pan;

  /// Solo state
  bool solo;

  /// Mute state
  bool muted;

  /// Real-time peak (linear, 0.0–1.0+)
  double peakL;
  double peakR;

  /// Computed position in widget-local coordinates (set by layout)
  Offset position;

  /// Computed dot radius based on peak level
  double dotRadius;

  OrbBusState({
    required this.id,
    this.volume = 0.85,
    this.pan = 0.0,
    this.solo = false,
    this.muted = false,
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.position = Offset.zero,
    this.dotRadius = 8.0,
  });

  /// Peak as max of L/R
  double get peak => math.max(peakL, peakR);

  /// Is this bus the master?
  bool get isMaster => id == OrbBusId.master;
}

// ============ Provider ============

class OrbMixerProvider extends ChangeNotifier {
  final MixerDSPProvider _dsp;
  final SharedMeterReader _meters;

  /// Bus states (all 6 buses including master)
  final Map<OrbBusId, OrbBusState> _busStates = {};

  /// Currently expanded bus (null = Nivo 1 orbit view)
  OrbBusId? expandedBus;

  /// Widget size (set by OrbMixer widget)
  double _size = 120.0;

  /// Hover state (expanded mode)
  bool isHovered = false;

  /// Currently dragging bus (null = no drag)
  OrbBusId? _draggingBus;

  OrbMixerProvider({
    required MixerDSPProvider dsp,
    required SharedMeterReader meters,
  })  : _dsp = dsp,
        _meters = meters {
    // Initialize bus states from DSP provider
    _syncFromDsp();
    // Listen for DSP state changes
    _dsp.addListener(_syncFromDsp);
  }

  @override
  void dispose() {
    _dsp.removeListener(_syncFromDsp);
    super.dispose();
  }

  // ── Getters ──

  Map<OrbBusId, OrbBusState> get busStates => _busStates;
  double get size => isHovered ? 180.0 : _size;
  double get baseSize => _size;
  bool get isDragging => _draggingBus != null;
  OrbBusId? get draggingBus => _draggingBus;

  OrbBusState? getBus(OrbBusId id) => _busStates[id];
  OrbBusState get master =>
      _busStates[OrbBusId.master] ?? OrbBusState(id: OrbBusId.master);

  /// All non-master buses (orbit dots)
  Iterable<OrbBusState> get orbitBuses =>
      _busStates.values.where((b) => !b.isMaster);

  // ── Sync from DSP provider ──

  void _syncFromDsp() {
    for (final orbId in OrbBusId.values) {
      final dspBus = _dsp.getBus(orbId.dspId);
      final state = _busStates.putIfAbsent(
          orbId, () => OrbBusState(id: orbId));

      if (dspBus != null) {
        state.volume = dspBus.volume;
        state.pan = dspBus.pan;
        state.solo = dspBus.solo;
        state.muted = dspBus.muted;
      } else if (orbId == OrbBusId.aux) {
        // Aux may not be in DSP provider defaults — use defaults
        state.volume = 0.75;
      }
    }
    _updateLayout();
    notifyListeners();
  }

  // ── Meter update (called from animation tick) ──

  /// Returns true if any values changed (worth repainting)
  bool updateMeters() {
    if (!_meters.hasChanged) return false;

    final snapshot = _meters.readMeters();
    bool changed = false;

    for (final orbId in OrbBusId.values) {
      final state = _busStates[orbId];
      if (state == null) continue;

      final idx = orbId.engineIndex;
      final newPeakL = snapshot.channelPeaks[idx * 2];
      final newPeakR = snapshot.channelPeaks[idx * 2 + 1];

      if ((state.peakL - newPeakL).abs() > 0.001 ||
          (state.peakR - newPeakR).abs() > 0.001) {
        state.peakL = newPeakL;
        state.peakR = newPeakR;
        changed = true;
      }
    }

    // Also update master from master peaks
    final masterState = _busStates[OrbBusId.master];
    if (masterState != null) {
      masterState.peakL = snapshot.masterPeakL;
      masterState.peakR = snapshot.masterPeakR;
    }

    if (changed) {
      _updateDotRadii();
    }
    return changed;
  }

  // ── Layout computation ──

  void setSize(double size) {
    if (_size == size) return;
    _size = size;
    _updateLayout();
  }

  void _updateLayout() {
    final center = Offset(size / 2, size / 2);
    final orbitRadius = size * 0.35; // 0dB reference orbit

    for (final state in _busStates.values) {
      if (state.isMaster) {
        // Master always at center
        state.position = center;
        state.dotRadius = 12.0 + state.peak * 6.0;
      } else {
        // Volume → distance: 0=center (-inf), volume=orbitRadius (0dB), >1=beyond orbit
        final distance = _volumeToRadius(state.volume, orbitRadius);
        // Pan offsets the base angle slightly (±15° max)
        final panOffset = state.pan * (math.pi / 12); // ±15°
        final angle = state.id.baseAngle + panOffset;

        state.position = Offset(
          center.dx + distance * math.cos(angle),
          center.dy - distance * math.sin(angle), // Y flipped (screen coords)
        );
        _updateDotRadius(state);
      }
    }
  }

  void _updateDotRadii() {
    for (final state in _busStates.values) {
      _updateDotRadius(state);
    }
  }

  void _updateDotRadius(OrbBusState state) {
    if (state.isMaster) {
      state.dotRadius = 12.0 + state.peak * 6.0;
    } else {
      // Base 6px, expands with peak up to 14px
      state.dotRadius = 6.0 + state.peak * 8.0;
    }
  }

  /// Map volume (0.0–1.5) to pixel radius from center
  double _volumeToRadius(double volume, double orbitRadius) {
    // 0.0 → 0 (center = silent)
    // 0.85 → orbitRadius (default level ≈ 0dB)
    // 1.0 → orbitRadius * 1.1
    // 1.5 → orbitRadius * 1.3
    return (volume / 0.85).clamp(0.0, 1.5) * orbitRadius;
  }

  /// Inverse: pixel radius to volume
  double _radiusToVolume(double radius, double orbitRadius) {
    return (radius / orbitRadius * 0.85).clamp(0.0, 1.5);
  }

  // ── Hit testing ──

  /// Find which bus dot is at the given local position (null if none)
  OrbBusId? hitTest(Offset localPos) {
    // Check master first (largest dot)
    final masterState = _busStates[OrbBusId.master]!;
    if ((localPos - masterState.position).distance <= masterState.dotRadius + 4) {
      return OrbBusId.master;
    }

    // Check orbit buses (closest hit within threshold)
    OrbBusId? closest;
    double closestDist = double.infinity;
    for (final state in orbitBuses) {
      final dist = (localPos - state.position).distance;
      final hitRadius = state.dotRadius + 6; // generous hit area
      if (dist <= hitRadius && dist < closestDist) {
        closest = state.id;
        closestDist = dist;
      }
    }
    return closest;
  }

  // ── Gestures ──

  /// Start dragging a bus dot
  void startDrag(OrbBusId busId) {
    _draggingBus = busId;
  }

  /// Update drag position — converts screen delta to volume/pan changes
  void updateDrag(Offset localPos) {
    final bus = _draggingBus;
    if (bus == null || bus == OrbBusId.master) return;

    final state = _busStates[bus];
    if (state == null) return;

    final center = Offset(size / 2, size / 2);
    final delta = localPos - center;
    final distance = delta.distance;
    final orbitRadius = size * 0.35;

    // Distance → volume
    final newVolume = _radiusToVolume(distance, orbitRadius);
    _dsp.setBusVolume(bus.dspId, newVolume);

    // Angle → pan (relative to base angle)
    final angle = math.atan2(-delta.dy, delta.dx); // flip Y for screen coords
    final angleDiff = _normalizeAngle(angle - bus.baseAngle);
    // Map ±15° to pan -1..+1
    final newPan = (angleDiff / (math.pi / 12)).clamp(-1.0, 1.0);
    _dsp.setBusPan(bus.dspId, newPan);
  }

  /// End drag
  void endDrag() {
    _draggingBus = null;
  }

  /// Toggle solo on a bus
  void toggleSolo(OrbBusId busId) {
    _dsp.toggleSolo(busId.dspId);
  }

  /// Toggle mute on a bus
  void toggleMute(OrbBusId busId) {
    _dsp.toggleMute(busId.dspId);
  }

  /// Fine volume adjustment (scroll wheel, ±0.5dB steps)
  void adjustVolume(OrbBusId busId, double delta) {
    final state = _busStates[busId];
    if (state == null) return;
    // 0.5dB ≈ 0.057 linear change at unity
    final step = delta > 0 ? 0.057 : -0.057;
    final newVol = (state.volume + step).clamp(0.0, 1.5);
    _dsp.setBusVolume(busId.dspId, newVol);
  }

  /// Master volume via scroll
  void adjustMasterVolume(double delta) {
    adjustVolume(OrbBusId.master, delta);
  }

  // ── Expand/collapse (Nivo 2 prep) ──

  void expandBus(OrbBusId busId) {
    if (busId == OrbBusId.master) return;
    expandedBus = busId;
    notifyListeners();
  }

  void collapseBus() {
    expandedBus = null;
    notifyListeners();
  }

  // ── Helpers ──

  /// Normalize angle to -π..+π
  double _normalizeAngle(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }
}
