/// FluxForge Container Service
///
/// Wwise/FMOD-style container playback:
/// - BlendContainer: RTPC-based crossfade between sounds
/// - RandomContainer: Weighted random/shuffle selection
/// - SequenceContainer: Timed sound sequences
///
/// Usage:
/// 1. Register container with EventRegistry
/// 2. When triggered, container determines which sound(s) to play
/// 3. Supports per-play variation (random, RTPC-based selection)
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/middleware_models.dart';
import '../providers/middleware_provider.dart';

/// Service for container-based audio playback
class ContainerService {
  static final ContainerService _instance = ContainerService._();
  static ContainerService get instance => _instance;

  ContainerService._();

  // Reference to middleware provider
  MiddlewareProvider? _middleware;

  // Random number generator
  final _random = math.Random();

  // Round-robin state per container (containerId → currentIndex)
  final Map<int, int> _roundRobinState = {};

  // Shuffle history per container (containerId → played indices)
  final Map<int, List<int>> _shuffleHistory = {};

  /// Initialize with middleware provider
  void init(MiddlewareProvider middleware) {
    _middleware = middleware;
    debugPrint('[ContainerService] Initialized');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BLEND CONTAINER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get active blend children with their volumes based on current RTPC value
  /// Returns map of childId → volume (0.0-1.0)
  Map<int, double> evaluateBlendContainer(BlendContainer container) {
    if (!container.enabled || container.children.isEmpty) return {};
    if (_middleware == null) return {};

    final rtpcDef = _middleware!.getRtpc(container.rtpcId);
    if (rtpcDef == null) return {};

    final rtpcValue = rtpcDef.normalizedValue; // 0-1
    final result = <int, double>{};

    for (final child in container.children) {
      // Check if RTPC value is within this child's range
      if (rtpcValue < child.rtpcStart || rtpcValue > child.rtpcEnd) continue;

      // Calculate volume based on position within range and crossfade width
      double volume = 1.0;

      // Fade in at start of range
      if (rtpcValue < child.rtpcStart + child.crossfadeWidth) {
        final fadePos = (rtpcValue - child.rtpcStart) / child.crossfadeWidth;
        volume = _applyCrossfadeCurve(fadePos, container.crossfadeCurve);
      }
      // Fade out at end of range
      else if (rtpcValue > child.rtpcEnd - child.crossfadeWidth) {
        final fadePos = (child.rtpcEnd - rtpcValue) / child.crossfadeWidth;
        volume = _applyCrossfadeCurve(fadePos, container.crossfadeCurve);
      }

      result[child.id] = volume.clamp(0.0, 1.0);
    }

    return result;
  }

  /// Apply crossfade curve to a 0-1 value
  double _applyCrossfadeCurve(double t, CrossfadeCurve curve) {
    switch (curve) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.equalPower:
        return math.sqrt(t);
      case CrossfadeCurve.sCurve:
        return t * t * (3.0 - 2.0 * t);
      case CrossfadeCurve.sinCos:
        return math.sin(t * math.pi / 2);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANDOM CONTAINER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select which child to play from a random container
  /// Returns the selected child index, or -1 if none
  int selectRandomChild(RandomContainer container) {
    if (!container.enabled || container.children.isEmpty) return -1;

    switch (container.mode) {
      case RandomMode.random:
        return _selectWeightedRandom(container);
      case RandomMode.shuffle:
        return _selectShuffle(container, useHistory: false);
      case RandomMode.shuffleWithHistory:
        return _selectShuffle(container, useHistory: true);
      case RandomMode.roundRobin:
        return _selectRoundRobin(container);
    }
  }

  /// Weighted random selection
  int _selectWeightedRandom(RandomContainer container) {
    double totalWeight = 0.0;
    for (final child in container.children) {
      totalWeight += child.weight;
    }

    if (totalWeight <= 0) return 0;

    double roll = _random.nextDouble() * totalWeight;
    double cumulative = 0.0;

    for (int i = 0; i < container.children.length; i++) {
      cumulative += container.children[i].weight;
      if (roll <= cumulative) return i;
    }

    return container.children.length - 1;
  }

  /// Shuffle selection (optionally avoiding recent plays)
  int _selectShuffle(RandomContainer container, {required bool useHistory}) {
    final history = _shuffleHistory[container.id] ?? [];

    if (!useHistory || history.length >= container.children.length) {
      // Reset history if full or not using history
      _shuffleHistory[container.id] = [];
    }

    // Get available indices (not in recent history)
    final available = <int>[];
    for (int i = 0; i < container.children.length; i++) {
      if (!history.contains(i)) available.add(i);
    }

    if (available.isEmpty) {
      // Fallback to first
      return 0;
    }

    // Select random from available
    final selected = available[_random.nextInt(available.length)];

    // Add to history if using history
    if (useHistory) {
      _shuffleHistory[container.id] = [...history, selected];
    }

    return selected;
  }

  /// Round-robin selection
  int _selectRoundRobin(RandomContainer container) {
    final current = _roundRobinState[container.id] ?? 0;
    final next = (current + 1) % container.children.length;
    _roundRobinState[container.id] = next;
    return current;
  }

  /// Apply pitch and volume variation to selected child
  /// Returns map with 'pitch' and 'volume' modifiers
  Map<String, double> applyRandomVariation(RandomChild child) {
    // Pitch variation: random between pitchMin and pitchMax
    final pitchRange = child.pitchMax - child.pitchMin;
    final pitch = child.pitchMin + _random.nextDouble() * pitchRange;

    // Volume variation: random between volumeMin and volumeMax
    final volumeRange = child.volumeMax - child.volumeMin;
    final volume = child.volumeMin + _random.nextDouble() * volumeRange;

    return {
      'pitch': pitch,
      'volume': volume,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEQUENCE CONTAINER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the steps that should play at a given time (ms from start)
  /// Uses delayMs as the start time for each step
  List<SequenceStep> getActiveSteps(SequenceContainer container, double timeMs) {
    if (!container.enabled || container.steps.isEmpty) return [];

    final result = <SequenceStep>[];
    for (final step in container.steps) {
      // Step active if timeMs is between delay and delay+duration
      if (timeMs >= step.delayMs && timeMs < step.delayMs + step.durationMs) {
        result.add(step);
      }
    }
    return result;
  }

  /// Get total duration of sequence container
  double getSequenceDuration(SequenceContainer container) {
    if (container.steps.isEmpty) return 0.0;

    double maxEnd = 0.0;
    for (final step in container.steps) {
      final end = step.delayMs + step.durationMs;
      if (end > maxEnd) maxEnd = end;
    }
    return maxEnd;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reset all container state (shuffle history, round-robin positions)
  void resetState() {
    _roundRobinState.clear();
    _shuffleHistory.clear();
  }

  /// Clear all data
  void clear() {
    resetState();
    _middleware = null;
  }
}
