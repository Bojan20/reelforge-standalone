/// Rolling 10-second history of recent voices for ghost-slot rendering.
///
/// Builds by diffing successive `orb_get_active_voices` results; records
/// the voice's last-seen peak/bus so the painter can fade the ghost alpha
/// based on where and how loud the voice was when it ended.
///
/// Reads (`liveGhosts`, `ghostsFor`) are cached per observe() so the
/// painter can poll every frame at zero cost. Heavy load (>100 voices)
/// optionally routes the diff through a dedicated worker `Isolate`.

library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;

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

/// Opaque payload sent to / received from the background isolate.
/// Must be sendable (primitive types + lists only).
class _IsolatePayload {
  /// Set of voice_ids active in the prior tick.
  final Set<int> prevIds;
  /// Active voice data this tick — encoded as flat parallel lists so the
  /// payload is Isolate-safe without serialising OrbVoiceState directly.
  final List<int> activeIds;
  final List<int> activeBusIndices;
  final List<double> activePeakL;
  final List<double> activePeakR;
  /// Last-seen cache (voice_id → [busIndex, peakL, peakR]).
  final Map<int, List<double>> lastSeen;
  /// Existing buffer (voice_id, busIndex, peakL, peakR, endedAtMs).
  final List<List<num>> buffer;
  /// Cutoff — ghosts with endedAt older than this are expired.
  final int nowMs;
  /// Max visible age (seconds).
  final double maxAgeSec;
  /// Hard cap on buffer length.
  final int maxBufferLength;

  const _IsolatePayload({
    required this.prevIds,
    required this.activeIds,
    required this.activeBusIndices,
    required this.activePeakL,
    required this.activePeakR,
    required this.lastSeen,
    required this.buffer,
    required this.nowMs,
    required this.maxAgeSec,
    required this.maxBufferLength,
  });
}

class _IsolateResult {
  final List<List<num>> buffer; // encoded ghost rows
  final Set<int> prevIds;
  final Map<int, List<double>> lastSeen;

  const _IsolateResult({
    required this.buffer,
    required this.prevIds,
    required this.lastSeen,
  });
}

/// Pure function used by both sync and isolate paths. Takes the current
/// state + new active set, returns new state. No side effects.
_IsolateResult _computeObserve(_IsolatePayload p) {
  final currentIds = <int>{};
  final newLastSeen = Map<int, List<double>>.from(p.lastSeen);
  for (int i = 0; i < p.activeIds.length; i++) {
    final id = p.activeIds[i];
    currentIds.add(id);
    newLastSeen[id] = [
      p.activeBusIndices[i].toDouble(),
      p.activePeakL[i],
      p.activePeakR[i],
    ];
  }

  final buffer = List<List<num>>.from(p.buffer);

  // Diff: prev - current → ended voices.
  for (final endedId in p.prevIds) {
    if (currentIds.contains(endedId)) continue;
    final last = newLastSeen[endedId];
    if (last == null) continue;
    buffer.add([
      endedId,
      last[0].toInt(),
      last[1],
      last[2],
      p.nowMs,
    ]);
    newLastSeen.remove(endedId);
  }

  // Evict expired.
  final cutoffMs = p.nowMs - (p.maxAgeSec * 1000).round();
  buffer.removeWhere((row) => row[4] < cutoffMs);

  // Hard cap.
  if (buffer.length > p.maxBufferLength) {
    final overflow = buffer.length - p.maxBufferLength;
    buffer.removeRange(0, overflow);
  }

  return _IsolateResult(
    buffer: buffer,
    prevIds: currentIds,
    lastSeen: newLastSeen,
  );
}

/// Entry point for the long-lived worker isolate (one isolate per buffer).
/// Receives observe payloads on a `ReceivePort`, sends `_IsolateResult` back.
void _workerEntry(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);
  port.listen((msg) {
    if (msg is _IsolatePayload) {
      final result = _computeObserve(msg);
      mainPort.send(result);
    } else if (msg == 'shutdown') {
      port.close();
    }
  });
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
///
/// Advanced (background processing under load):
/// ```dart
/// await history.observeInIsolate(currentlyActiveVoices);
/// ```
class VoiceHistoryBuffer {
  /// How many seconds a ghost remains visible after its voice ended.
  static const double maxAgeSeconds = 10.0;

  /// Hard cap on buffer length to avoid unbounded growth under bursty load
  /// (still rare — 128 voices × 10s rolling window is roomy).
  static const int _maxBufferLength = 128;

  /// Voice count above which automatic isolate offload kicks in.
  static const int _isolateAutoThreshold = 100;

  /// Buffer of ghost slots, newest at the END (insertion-ordered).
  final List<GhostSlot> _buffer = [];

  /// Voice IDs we observed as **active** in the previous tick. Used to
  /// detect "ended this tick" = in prev but not in current.
  Set<int> _prevActiveIds = <int>{};

  /// Last known voice state keyed by voice_id. We keep the most recent
  /// peak / bus so we can capture the voice at its "last moment" rather
  /// than extrapolating a zero peak.
  final Map<int, OrbVoiceState> _lastSeen = {};

  // ── Caches (invalidated on every observe) ──────────────────────────────
  List<GhostSlot>? _cachedLive;
  final Map<OrbBusId, List<GhostSlot>> _cachedByBus = {};

  // ── Isolate worker (lazy) ──────────────────────────────────────────────
  Isolate? _worker;
  SendPort? _workerPort;
  final ReceivePort _responsePort = ReceivePort();
  Completer<_IsolateResult>? _pendingResult;
  bool _workerStarting = false;

  VoiceHistoryBuffer() {
    _responsePort.listen(_handleIsolateResponse);
  }

  /// Observe the set of currently active voices. Records ghosts for any
  /// voice that was active in the prior tick but isn't now. Cleans up
  /// expired ghosts at the same time. Synchronous fast path.
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

    // Evict expired + enforce cap in a single head-trim pass — insertion-
    // ordered buffer (newest at end) means `ageSeconds` decreases monotonically
    // from index 0, so all expired entries are a contiguous prefix.
    int dropFront = 0;
    while (dropFront < _buffer.length && _buffer[dropFront].isExpired) {
      dropFront++;
    }
    final overflow = (_buffer.length - dropFront) - _maxBufferLength;
    if (overflow > 0) dropFront += overflow;
    if (dropFront > 0) _buffer.removeRange(0, dropFront);

    _invalidateCache();
  }

  /// Observe, but offload the diff + bookkeeping to a background isolate
  /// when voice count is large. Auto-fallback to sync path for small
  /// active sets (<= `_isolateAutoThreshold`). Awaiting this future is
  /// optional — the UI always reads the latest committed state.
  Future<void> observeInIsolate(List<OrbVoiceState> active) async {
    if (active.length <= _isolateAutoThreshold) {
      observe(active);
      return;
    }
    // Drop stale requests: if a prior observe is still in flight, skip this
    // tick rather than queue. Keeps the inbound rate at worker capacity.
    final inflight = _pendingResult;
    if (inflight != null && !inflight.isCompleted) return;

    await _ensureWorker();
    final port = _workerPort;
    if (port == null) {
      // Worker failed to start — fall back to sync path.
      observe(active);
      return;
    }

    // Build Isolate-safe payload.
    final activeIds = List<int>.filled(active.length, 0);
    final activeBusIndices = List<int>.filled(active.length, 0);
    final activePeakL = List<double>.filled(active.length, 0);
    final activePeakR = List<double>.filled(active.length, 0);
    for (int i = 0; i < active.length; i++) {
      final v = active[i];
      activeIds[i] = v.voiceId;
      activeBusIndices[i] = v.bus.engineIndex;
      activePeakL[i] = v.peakL;
      activePeakR[i] = v.peakR;
    }

    final lastSeenPayload = <int, List<double>>{};
    _lastSeen.forEach((id, v) {
      lastSeenPayload[id] = [
        v.bus.engineIndex.toDouble(),
        v.peakL,
        v.peakR,
      ];
    });

    final bufferPayload = _buffer
        .map((g) => <num>[
              g.voiceId,
              g.bus.engineIndex,
              g.peakL,
              g.peakR,
              g.endedAt.millisecondsSinceEpoch,
            ])
        .toList();

    final payload = _IsolatePayload(
      prevIds: Set<int>.of(_prevActiveIds),
      activeIds: activeIds,
      activeBusIndices: activeBusIndices,
      activePeakL: activePeakL,
      activePeakR: activePeakR,
      lastSeen: lastSeenPayload,
      buffer: bufferPayload,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      maxAgeSec: maxAgeSeconds,
      maxBufferLength: _maxBufferLength,
    );

    // Drop any previous pending result — newest observe wins.
    _pendingResult = Completer<_IsolateResult>();
    port.send(payload);
    final result = await _pendingResult!.future;
    _integrateIsolateResult(result, active);
  }

  Future<void> _ensureWorker() async {
    if (_worker != null && _workerPort != null) return;
    if (_workerStarting) {
      // Wait for the in-flight startup (spin with small delay).
      while (_workerStarting && _workerPort == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      return;
    }
    _workerStarting = true;
    try {
      // Single port handles both handshake (worker's SendPort as first msg)
      // AND subsequent _IsolateResult payloads. _handleIsolateResponse
      // distinguishes the two by message type.
      _worker = await Isolate.spawn<SendPort>(
        _workerEntry,
        _responsePort.sendPort,
        debugName: 'voice-history-worker',
      );
      // Wait for worker to publish its SendPort (first message on the port).
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (_workerPort == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      if (_workerPort == null) {
        // Worker never handshaked — treat as failure, fall back to sync.
        _worker?.kill(priority: Isolate.immediate);
        _worker = null;
      }
    } catch (_) {
      _worker = null;
      _workerPort = null;
    } finally {
      _workerStarting = false;
    }
  }

  /// Dispatcher bound to `_responsePort`:
  ///   - first `SendPort` from the worker → that is our `_workerPort`.
  ///   - subsequent `_IsolateResult` messages → complete pending future.
  void _handleIsolateResponse(Object? msg) {
    if (msg is SendPort) {
      _workerPort ??= msg;
      return;
    }
    if (msg is _IsolateResult) {
      final pending = _pendingResult;
      if (pending != null && !pending.isCompleted) {
        pending.complete(msg);
      }
    }
  }

  /// Commit a result computed off-thread into the local state.
  void _integrateIsolateResult(
      _IsolateResult r, List<OrbVoiceState> currentActive) {
    _buffer.clear();
    final busByIndex = OrbBusId.values;
    for (final row in r.buffer) {
      final busIdx = row[1].toInt();
      if (busIdx < 0 || busIdx >= busByIndex.length) continue;
      _buffer.add(GhostSlot(
        voiceId: row[0].toInt(),
        bus: busByIndex[busIdx],
        peakL: row[2].toDouble(),
        peakR: row[3].toDouble(),
        endedAt: DateTime.fromMillisecondsSinceEpoch(row[4].toInt()),
      ));
    }
    _prevActiveIds = r.prevIds;
    // Rebuild _lastSeen from current active set (freshest data).
    _lastSeen.clear();
    for (final v in currentActive) {
      _lastSeen[v.voiceId] = v;
    }
    _invalidateCache();
  }

  /// Spawn the isolate eagerly — useful to avoid startup latency on the
  /// first heavy-load observe. Safe to call multiple times.
  Future<void> warmUp() => _ensureWorker();

  /// Shutdown the worker isolate (call on project close).
  void disposeWorker() {
    try { _workerPort?.send('shutdown'); } catch (_) {/* worker may be dead */}
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _workerPort = null;
  }

  // ── Cache helpers ──────────────────────────────────────────────────────
  void _invalidateCache() {
    _cachedLive = null;
    _cachedByBus.clear();
  }

  /// All non-expired ghosts, ordered by age (freshest first for z-order).
  /// Cached per-tick; the painter can call this every frame without cost.
  List<GhostSlot> get liveGhosts {
    final cached = _cachedLive;
    if (cached != null) return cached;
    // Buffer is newest-last; reverse + filter.
    final live = <GhostSlot>[];
    for (int i = _buffer.length - 1; i >= 0; i--) {
      final g = _buffer[i];
      if (!g.isExpired) live.add(g);
    }
    _cachedLive = List.unmodifiable(live);
    return _cachedLive!;
  }

  /// Ghosts on a specific bus (for Nivo 2 expanded view).
  /// Cached on first call per observe(), O(liveGhosts) once, O(1) thereafter.
  List<GhostSlot> ghostsFor(OrbBusId bus) {
    final bucket = _cachedByBus[bus];
    if (bucket != null) return bucket;
    final all = liveGhosts;
    final filtered = <GhostSlot>[];
    for (final g in all) {
      if (g.bus == bus) filtered.add(g);
    }
    final unmodifiable = List<GhostSlot>.unmodifiable(filtered);
    _cachedByBus[bus] = unmodifiable;
    return unmodifiable;
  }

  /// Reset completely (e.g., on project close / FSM reset).
  void clear() {
    _buffer.clear();
    _prevActiveIds = <int>{};
    _lastSeen.clear();
    _invalidateCache();
  }

  /// Total live ghost count.
  int get liveCount => liveGhosts.length;

  /// True if a background isolate is running.
  @visibleForTesting
  bool get hasIsolateWorker => _worker != null;
}
