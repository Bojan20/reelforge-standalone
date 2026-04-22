/// PHASE 10d — Orb Mixer Live Alerts
///
/// Real-time health monitors that "shout" visually when the mix is in
/// trouble. Drives the orb's colored outer rings so the user doesn't
/// have to listen actively — the orb tells them what's wrong.
///
///   Clipping       → red pulse    (peak ≥ 0.99 on any bus channel)
///   Headroom       → orange ring  (master truePeak > -6 dBTP)
///   Phase issue    → purple ring  (master correlation < 0.3)
///   Masking        → yellow ring  (two buses contributing to the same
///                                  broad band above threshold)
///
/// All checks operate on data already exposed through SharedMeterSnapshot,
/// so this is a pure Dart layer — no FFI / Rust changes needed.

library;

import 'dart:math' as math;

import '../providers/orb_mixer_provider.dart';
import 'shared_meter_reader.dart';

/// Alert severity — drives glow intensity in the painter.
enum OrbAlertSeverity { info, warning, critical }

/// Alert category — determines which ring color the painter uses.
enum OrbAlertType {
  clipping,
  headroom,
  phase,
  masking;

  String get label => switch (this) {
        clipping => 'CLIP',
        headroom => 'HEADROOM',
        phase => 'PHASE',
        masking => 'MASKING',
      };
}

/// Single alert occurrence. Carries enough state for the painter to draw
/// the correct ring color and for the UI to display a tooltip.
class OrbAlert {
  /// Which alert family this is.
  final OrbAlertType type;

  /// Severity (painter maps to glow + pulse rate).
  final OrbAlertSeverity severity;

  /// Which bus is the source. Null = aggregate/master alert that applies
  /// to the whole orb (typically phase / masking at master-out).
  final OrbBusId? bus;

  /// Optional secondary bus for relationship alerts (e.g. masking between
  /// two buses drawn as a connecting arc).
  final OrbBusId? otherBus;

  /// When the alert first fired. Used for hold/decay so alerts linger a
  /// short while after the condition clears (no visual flicker).
  final DateTime firstFiredAt;

  /// Last time the alert condition was observed (updated each tick).
  final DateTime lastSeenAt;

  const OrbAlert({
    required this.type,
    required this.severity,
    this.bus,
    this.otherBus,
    required this.firstFiredAt,
    required this.lastSeenAt,
  });

  /// Age of alert in seconds.
  double get ageSeconds =>
      DateTime.now().difference(firstFiredAt).inMilliseconds / 1000.0;

  /// Milliseconds since the condition was last observed.
  int get msSinceLastSeen =>
      DateTime.now().difference(lastSeenAt).inMilliseconds;

  /// Visible alpha — full while observed, decays for 500ms after condition
  /// clears so the user has time to see what happened.
  double get alpha {
    const int holdMs = 500;
    final since = msSinceLastSeen;
    if (since < holdMs) return 1.0;
    final fadeOut = 1.0 - ((since - holdMs) / 500.0);
    return fadeOut.clamp(0.0, 1.0);
  }

  bool get isExpired => alpha <= 0.01;

  /// Pulse phase 0..1 for beat animation (faster when critical).
  double pulsePhase() {
    final periodMs = severity == OrbAlertSeverity.critical ? 200 : 600;
    final ms = DateTime.now().millisecondsSinceEpoch;
    return (ms % periodMs) / periodMs;
  }
}

/// Engine that consumes a SharedMeterSnapshot each frame and emits / clears
/// OrbAlert instances. Stateful so ongoing alerts hold their firstFiredAt.
class OrbAlertsEngine {
  /// Alerts currently live (stable reference updated in-place).
  final Map<String, OrbAlert> _activeAlerts = {};

  // ─── Threshold constants ────────────────────────────────────────────────
  /// Peak level at which clipping is flagged (linear, 0.99 ≈ -0.09 dBFS).
  static const double _clipLinearThreshold = 0.99;

  /// True-peak headroom threshold (dBTP). Master truePeak above this fires
  /// an orange "HEADROOM" warning.
  static const double _headroomDbTpThreshold = -6.0;

  /// Stereo correlation threshold below which a phase problem is flagged.
  static const double _phaseCorrelationThreshold = 0.3;

  /// Minimum magnitude for a spectrum band to "count" for masking.
  static const double _maskingBandThreshold = 0.35;

  /// Evaluate and update alerts for this frame. `busStates` provides the
  /// per-bus peaks (which the snapshot already has in channelPeaks[6×2]).
  /// Returns an immutable list of current alerts (including fading-out
  /// ones) so the painter can render them.
  List<OrbAlert> evaluate({
    required SharedMeterSnapshot snapshot,
    required Map<OrbBusId, OrbBusState> busStates,
  }) {
    final now = DateTime.now();

    // ─── 1. Clipping (per bus) ────────────────────────────────────────────
    for (final bus in OrbBusId.values) {
      if (bus == OrbBusId.master) continue;
      final idx = bus.engineIndex;
      if (idx * 2 + 1 >= snapshot.channelPeaks.length) continue;
      final pL = snapshot.channelPeaks[idx * 2];
      final pR = snapshot.channelPeaks[idx * 2 + 1];
      final peak = pL > pR ? pL : pR;
      final key = 'clip_${bus.name}';
      if (peak >= _clipLinearThreshold) {
        _touch(key, OrbAlertType.clipping, OrbAlertSeverity.critical, now,
            bus: bus);
      }
    }
    // Master clipping (use master peaks directly).
    final masterPeak =
        snapshot.masterPeakL > snapshot.masterPeakR
            ? snapshot.masterPeakL
            : snapshot.masterPeakR;
    if (masterPeak >= _clipLinearThreshold) {
      _touch('clip_master', OrbAlertType.clipping, OrbAlertSeverity.critical,
          now,
          bus: OrbBusId.master);
    }

    // ─── 2. Headroom (master truePeak above -6 dBTP) ─────────────────────
    if (snapshot.truePeakMax > _headroomDbTpThreshold) {
      // Severity escalates as we approach 0 dBTP.
      final sev = snapshot.truePeakMax > -1.0
          ? OrbAlertSeverity.critical
          : OrbAlertSeverity.warning;
      _touch('headroom_master', OrbAlertType.headroom, sev, now,
          bus: OrbBusId.master);
    }

    // ─── 3. Phase (correlation < 0.3) ────────────────────────────────────
    if (snapshot.correlation < _phaseCorrelationThreshold &&
        // Only meaningful when there IS signal.
        (snapshot.masterPeakL > 0.05 || snapshot.masterPeakR > 0.05)) {
      final sev = snapshot.correlation < 0.0
          ? OrbAlertSeverity.critical
          : OrbAlertSeverity.warning;
      _touch('phase_master', OrbAlertType.phase, sev, now,
          bus: OrbBusId.master);
    }

    // ─── 4. Masking (two buses dominant in the same broad band) ──────────
    // Heuristic without per-bus FFT: any two non-master buses whose peak is
    // above threshold at the same tick — master spectrum shows energy in
    // overlapping bands — flag masking between them.
    final bands = snapshot.spectrumBands;
    if (bands.length >= 32) {
      // Find which broad region (bass 0-8, low-mid 8-16, high-mid 16-24,
      // treble 24-32) has the most energy right now.
      double bass = 0, lowMid = 0, highMid = 0, treble = 0;
      for (int i = 0; i < 8 && i < bands.length; i++) {
        bass += bands[i];
      }
      for (int i = 8; i < 16 && i < bands.length; i++) {
        lowMid += bands[i];
      }
      for (int i = 16; i < 24 && i < bands.length; i++) {
        highMid += bands[i];
      }
      for (int i = 24; i < 32 && i < bands.length; i++) {
        treble += bands[i];
      }
      final loudestBandEnergy = [bass, lowMid, highMid, treble]
          .reduce((a, b) => a > b ? a : b);
      // If the loudest broad band is hot, find the two hottest buses —
      // those are the likely maskers in that region.
      if (loudestBandEnergy > _maskingBandThreshold * 8) {
        final contenders = busStates.entries
            .where((e) => e.key != OrbBusId.master && !e.value.muted)
            .toList()
          ..sort((a, b) => b.value.peak.compareTo(a.value.peak));
        if (contenders.length >= 2 &&
            contenders[0].value.peak > 0.25 &&
            contenders[1].value.peak > 0.25) {
          final pair = [contenders[0].key.name, contenders[1].key.name]
            ..sort();
          _touch('mask_${pair[0]}_${pair[1]}', OrbAlertType.masking,
              OrbAlertSeverity.warning, now,
              bus: contenders[0].key, otherBus: contenders[1].key);
        }
      }
    }

    // ─── 5. Remove expired ───────────────────────────────────────────────
    _activeAlerts.removeWhere((_, a) => a.isExpired);

    return _activeAlerts.values.toList(growable: false);
  }

  /// Internal helper: create/refresh an alert under a stable key.
  void _touch(String key, OrbAlertType type, OrbAlertSeverity sev,
      DateTime now,
      {OrbBusId? bus, OrbBusId? otherBus}) {
    final prev = _activeAlerts[key];
    _activeAlerts[key] = OrbAlert(
      type: type,
      severity: sev,
      bus: bus,
      otherBus: otherBus,
      firstFiredAt: prev?.firstFiredAt ?? now,
      lastSeenAt: now,
    );
  }

  /// Reset all alert state (e.g., on project close).
  void clear() => _activeAlerts.clear();

  /// Count of currently active (non-expired) alerts.
  int get activeCount => _activeAlerts.length;

  /// Linear peak → dBFS helper (used by UI for tooltips).
  static double linearToDbFs(double linear) {
    if (linear <= 1e-6) return -120.0;
    return 20.0 * math.log(linear) / math.ln10;
  }
}
