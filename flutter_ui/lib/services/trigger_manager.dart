/// Trigger Manager — Position, Marker, and Cooldown triggers
///
/// Manages non-MIDI trigger modes for custom events:
/// - Position: trigger at specific timeline position
/// - Marker: trigger when playhead crosses a timeline marker
/// - Cooldown: per-event minimum re-trigger interval
///
/// Polled per audio buffer (~5ms) from timeline playback provider.

import 'package:flutter/foundation.dart';

import 'server_audio_bridge.dart' show EventRegistryLocator;

/// Position-based trigger binding
class PositionTrigger {
  final String eventId;
  final double positionSeconds;
  final bool oneShot; // true = fire once, false = fire every time playhead passes
  bool _fired = false;

  PositionTrigger({
    required this.eventId,
    required this.positionSeconds,
    this.oneShot = true,
  });

  /// Reset fired state (call on transport stop/seek)
  void reset() => _fired = false;

  Map<String, dynamic> toJson() => {
    'eventId': eventId, 'positionSeconds': positionSeconds, 'oneShot': oneShot,
  };

  factory PositionTrigger.fromJson(Map<String, dynamic> json) => PositionTrigger(
    eventId: json['eventId'] as String? ?? '',
    positionSeconds: (json['positionSeconds'] as num?)?.toDouble() ?? 0.0,
    oneShot: json['oneShot'] as bool? ?? true,
  );
}

/// Marker-based trigger binding
class MarkerTrigger {
  final String eventId;
  final String markerId; // Timeline marker ID to watch
  bool _fired = false;

  MarkerTrigger({required this.eventId, required this.markerId});

  void reset() => _fired = false;

  Map<String, dynamic> toJson() => {'eventId': eventId, 'markerId': markerId};
  factory MarkerTrigger.fromJson(Map<String, dynamic> json) => MarkerTrigger(
    eventId: json['eventId'] as String? ?? '',
    markerId: json['markerId'] as String? ?? '',
  );
}

/// Cooldown state per event
class _CooldownState {
  DateTime lastTrigger = DateTime(2000);
  Duration cooldown;
  _CooldownState(this.cooldown);

  bool canTrigger() => DateTime.now().difference(lastTrigger) >= cooldown;
  void markTriggered() => lastTrigger = DateTime.now();
}

/// Trigger Manager — singleton
class TriggerManager with ChangeNotifier {
  TriggerManager._();
  static final instance = TriggerManager._();

  final List<PositionTrigger> _positionTriggers = [];
  final List<MarkerTrigger> _markerTriggers = [];
  final Map<String, _CooldownState> _cooldowns = {};

  double _prevPlayheadPos = -1;
  bool _isPlaying = false;

  // Getters
  List<PositionTrigger> get positionTriggers => List.unmodifiable(_positionTriggers);
  List<MarkerTrigger> get markerTriggers => List.unmodifiable(_markerTriggers);

  // ═══════════════════════════════════════════════════════════════
  // POSITION TRIGGERS
  // ═══════════════════════════════════════════════════════════════

  void addPositionTrigger(PositionTrigger trigger) {
    _positionTriggers.add(trigger);
    notifyListeners();
  }

  void removePositionTrigger(String eventId) {
    _positionTriggers.removeWhere((t) => t.eventId == eventId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // MARKER TRIGGERS
  // ═══════════════════════════════════════════════════════════════

  void addMarkerTrigger(MarkerTrigger trigger) {
    _markerTriggers.add(trigger);
    notifyListeners();
  }

  void removeMarkerTrigger(String eventId) {
    _markerTriggers.removeWhere((t) => t.eventId == eventId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // COOLDOWN
  // ═══════════════════════════════════════════════════════════════

  /// Set cooldown for an event (0 = no cooldown)
  void setCooldown(String eventId, Duration cooldown) {
    if (cooldown <= Duration.zero) {
      _cooldowns.remove(eventId);
    } else {
      _cooldowns[eventId] = _CooldownState(cooldown);
    }
  }

  /// Check if event can fire (respects cooldown)
  bool canTrigger(String eventId) {
    final cd = _cooldowns[eventId];
    return cd == null || cd.canTrigger();
  }

  /// Trigger event with cooldown check
  bool triggerWithCooldown(String eventId) {
    if (!canTrigger(eventId)) return false;
    if (!EventRegistryLocator.isSet) return false;

    try {
      EventRegistryLocator.instance.triggerEvent(eventId);
      _cooldowns[eventId]?.markTriggered();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PLAYHEAD POLLING (call from timeline provider per frame)
  // ═══════════════════════════════════════════════════════════════

  /// Called when playback starts
  void onPlaybackStart() {
    _isPlaying = true;
    _prevPlayheadPos = -1;
  }

  /// Called when playback stops or seeks
  void onPlaybackStop() {
    _isPlaying = false;
    _prevPlayheadPos = -1;
    // Reset all one-shot position triggers
    for (final t in _positionTriggers) {
      t.reset();
    }
    for (final t in _markerTriggers) {
      t.reset();
    }
  }

  /// Called per frame/buffer with current playhead position (seconds).
  /// Checks position triggers and fires events.
  void onPlayheadUpdate(double positionSeconds) {
    if (!_isPlaying) return;
    final prev = _prevPlayheadPos;
    _prevPlayheadPos = positionSeconds;

    // Skip first update (no previous position to compare)
    if (prev < 0) return;

    // Hysteresis: only trigger on forward movement (not rewind)
    if (positionSeconds <= prev) return;

    // Seek detection: large jump (>0.5s) = seek, not continuous playback
    // Don't fire intermediate triggers on seek — only on smooth playback
    if (positionSeconds - prev > 0.5) {
      _prevPlayheadPos = positionSeconds;
      return;
    }

    // Check position triggers
    for (final trigger in _positionTriggers) {
      if (trigger._fired && trigger.oneShot) continue;
      // Did playhead cross trigger position? (prev < pos <= current)
      if (prev < trigger.positionSeconds && positionSeconds >= trigger.positionSeconds) {
        if (triggerWithCooldown(trigger.eventId)) {
          trigger._fired = true;
        }
      }
    }
  }

  /// Called when playhead crosses a timeline marker (by marker ID).
  void onMarkerCrossed(String markerId) {
    for (final trigger in _markerTriggers) {
      if (trigger.markerId == markerId && !trigger._fired) {
        if (triggerWithCooldown(trigger.eventId)) {
          trigger._fired = true;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'positionTriggers': _positionTriggers.map((t) => t.toJson()).toList(),
    'markerTriggers': _markerTriggers.map((t) => t.toJson()).toList(),
    'cooldowns': _cooldowns.map((k, v) => MapEntry(k, v.cooldown.inMilliseconds)),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _positionTriggers.clear();
    _markerTriggers.clear();
    _cooldowns.clear();

    final pos = json['positionTriggers'] as List?;
    if (pos != null) {
      _positionTriggers.addAll(pos.map((p) => PositionTrigger.fromJson(p as Map<String, dynamic>)));
    }
    final markers = json['markerTriggers'] as List?;
    if (markers != null) {
      _markerTriggers.addAll(markers.map((m) => MarkerTrigger.fromJson(m as Map<String, dynamic>)));
    }
    final cds = json['cooldowns'] as Map<String, dynamic>?;
    if (cds != null) {
      for (final entry in cds.entries) {
        _cooldowns[entry.key] = _CooldownState(Duration(milliseconds: entry.value as int));
      }
    }
  }
}
