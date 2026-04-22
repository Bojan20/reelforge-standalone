/// PHASE 10 — Voice History Buffer (Ghost Slots)
///
/// Problem: SFX voices play for 300ms and disappear. With 130 sounds, you
/// can't point-and-click fast enough to catch them.
///
/// Solution: record every voice lifetime event, keep a rolling **10-second
/// history** of recent voices. Paint them as "ghost slots" — fading dots
/// in the orbital ring. Tap a ghost to replay (via solo + retrigger).
///
/// All client-side. No FFI changes needed — we diff successive
/// `orb_get_active_voices` results to detect ends; the peak recorded when
/// the voice was last seen is what drives ghost dot alpha.

library;

import '../providers/orb_mixer_provider.dart';

/// Single recorded voice lifetime snapshot.
class GhostSlot {
  /// Voice ID (engine voice slot identifier; may be reused later).
  final int voiceId;
  /// Bus the voice played on.
  final OrbBusId bus;
  /// Peak L at last observation (determines ghost dot alpha decay).
  final double peakL;
  /// Peak R at last observation.
  final double peakR;
  /// Timestamp the voice ended (DateTime.now() at diff detection).
  final DateTime endedAt;

  const GhostSlot({
    required this.voiceId,
    required this.bus,
    required this.peakL,
    required this.peakR,
    required this.endedAt,
  });

  /// Age in seconds since the voice ended.
  double get ageSeconds =>
      DateTime.now().difference(endedAt).inMilliseconds / 1000.0;

  /// Ghost alpha: fades linearly from 1.0 at end to 0.0 after 10s.
  double get alpha {
    final a = 1.0 - (ageSeconds / VoiceHistoryBuffer.maxAgeSeconds);
    return a.clamp(0.0, 1.0);
  }

  /// Peak magnitude at last observation.
  double get peak => peakL > peakR ? peakL : peakR;

  /// True if this ghost has aged past the visible window.
  bool get isExpired => ageSeconds >= VoiceHistoryBuffer.maxAgeSeconds;
}

/// Rolling voice-lifetime history.
///
/// Usage (typical):
/// ```dart
/// final history = VoiceHistoryBuffer();
/// // In poll tick, after reading new active voice list:
/// history.observe(currentlyActiveVoices);
/// // To render:
/// for (final ghost in history.liveGhosts) { painter.drawGhost(ghost); }
/// ```
class VoiceHistoryBuffer {
  /// How many seconds a ghost remains visible after its voice ended.
  static const double maxAgeSeconds = 10.0;

  /// Hard cap on buffer length to avoid unbounded growth under bursty load
  /// (still rare — 128 voices × 10s rolling window is roomy).
  static const int _maxBufferLength = 128;

  final List<GhostSlot> _buffer = [];

  /// Voice IDs we observed as **active** in the previous tick. Used to
  /// detect "ended this tick" = in prev but not in current.
  Set<int> _prevActiveIds = <int>{};

  /// Last known voice state keyed by voice_id. We keep the most recent
  /// peak / bus so we can capture the voice at its "last moment" rather
  /// than extrapolating a zero peak.
  final Map<int, OrbVoiceState> _lastSeen = {};

  /// Observe the set of currently active voices. Records ghosts for any
  /// voice that was active in the prior tick but isn't now. Cleans up
  /// expired ghosts at the same time.
  void observe(List<OrbVoiceState> active) {
    final now = DateTime.now();

    // Snapshot current voice IDs and update last-seen cache.
    final currentIds = <int>{};
    for (final v in active) {
      currentIds.add(v.voiceId);
      _lastSeen[v.voiceId] = v;
    }

    // Voices in prev but not in current → they just ended.
    for (final endedId in _prevActiveIds.difference(currentIds)) {
      final last = _lastSeen[endedId];
      if (last == null) continue;
      _buffer.add(GhostSlot(
        voiceId: endedId,
        bus: last.bus,
        peakL: last.peakL,
        peakR: last.peakR,
        endedAt: now,
      ));
      _lastSeen.remove(endedId);
    }

    _prevActiveIds = currentIds;

    // Evict expired + enforce cap.
    _buffer.removeWhere((g) => g.isExpired);
    if (_buffer.length > _maxBufferLength) {
      _buffer.removeRange(0, _buffer.length - _maxBufferLength);
    }
  }

  /// All non-expired ghosts, ordered by age (freshest first for z-order).
  List<GhostSlot> get liveGhosts {
    final live = _buffer.where((g) => !g.isExpired).toList();
    live.sort((a, b) => a.ageSeconds.compareTo(b.ageSeconds));
    return live;
  }

  /// Ghosts on a specific bus (for Nivo 2 expanded view).
  List<GhostSlot> ghostsFor(OrbBusId bus) {
    return liveGhosts.where((g) => g.bus == bus).toList();
  }

  /// Reset completely (e.g., on project close / FSM reset).
  void clear() {
    _buffer.clear();
    _prevActiveIds = <int>{};
    _lastSeen.clear();
  }

  /// Diagnostic: total live ghost count.
  int get liveCount => liveGhosts.length;
}
