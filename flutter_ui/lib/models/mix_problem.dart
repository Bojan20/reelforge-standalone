/// PHASE 10e — Mix Problem snapshot model
///
/// When the user hears something off during live play but doesn't have
/// time to fix it on the spot, they tap "Mark Problem". This captures a
/// snapshot of the current mix state so they can review + fix it later.
///
/// MVP (this commit): records FSM / bus / voice / alert state only.
/// Audio-clip capture (3-5s retrospective ring buffer) is a follow-up
/// requiring Rust-side FFI for ring buffer export.

library;

/// One mix problem marker.
class MixProblem {
  /// Unique id — epoch ms at capture (monotonic within a session).
  final int id;

  /// When the user hit "Mark Problem".
  final DateTime markedAt;

  /// Optional free-text note (user may tag later).
  final String note;

  /// Active FSM state at capture time (e.g. baseGame, freeSpins).
  final String? fsmState;

  /// Bet amount at capture time.
  final double bet;

  /// Snapshot of per-bus peaks (L then R, 6 buses = 12 entries).
  /// Order matches OrbBusId.engineIndex × 2 → master/music/sfx/voice/ambience/aux.
  final List<double> busPeaks;

  /// Active voices right at the capture moment — voice_id, bus_idx,
  /// peakL, peakR, volume, looping (1.0/0.0). 6 floats per voice.
  final List<double> voices;

  /// Spectrum snapshot — 32 log-spaced master bands, 0.0-1.0 normalized.
  final List<double> spectrumBands;

  /// Active alerts at capture — each entry: {type, severity, busName}.
  final List<MixAlertSnapshot> alerts;

  const MixProblem({
    required this.id,
    required this.markedAt,
    required this.note,
    required this.fsmState,
    required this.bet,
    required this.busPeaks,
    required this.voices,
    required this.spectrumBands,
    required this.alerts,
  });

  int get voiceCount => voices.length ~/ 6;

  /// Highest bus peak in the capture — quick sort helper.
  double get dominantBusPeak {
    double m = 0;
    for (final p in busPeaks) {
      if (p > m) m = p;
    }
    return m;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'markedAt': markedAt.toIso8601String(),
        'note': note,
        'fsmState': fsmState,
        'bet': bet,
        'busPeaks': busPeaks,
        'voices': voices,
        'spectrumBands': spectrumBands,
        'alerts': alerts.map((a) => a.toJson()).toList(),
      };

  factory MixProblem.fromJson(Map<String, dynamic> json) => MixProblem(
        id: (json['id'] as num).toInt(),
        markedAt: DateTime.parse(json['markedAt'] as String),
        note: json['note'] as String? ?? '',
        fsmState: json['fsmState'] as String?,
        bet: (json['bet'] as num?)?.toDouble() ?? 0.0,
        busPeaks: ((json['busPeaks'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        voices: ((json['voices'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        spectrumBands: ((json['spectrumBands'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        alerts: ((json['alerts'] as List?) ?? const [])
            .map((e) => MixAlertSnapshot.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Frozen copy of an OrbAlert for persistence.
class MixAlertSnapshot {
  /// clipping / headroom / phase / masking
  final String type;
  /// info / warning / critical
  final String severity;
  /// Which bus the alert was scoped to (null for master/aggregate).
  final String? busName;
  /// Secondary bus (masking pairs).
  final String? otherBusName;

  const MixAlertSnapshot({
    required this.type,
    required this.severity,
    this.busName,
    this.otherBusName,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'severity': severity,
        if (busName != null) 'bus': busName,
        if (otherBusName != null) 'otherBus': otherBusName,
      };

  factory MixAlertSnapshot.fromJson(Map<String, dynamic> json) =>
      MixAlertSnapshot(
        type: json['type'] as String,
        severity: json['severity'] as String,
        busName: json['bus'] as String?,
        otherBusName: json['otherBus'] as String?,
      );
}
