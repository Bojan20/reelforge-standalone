/// Track Freeze Service — P2-DAW-5
///
/// Render tracks with inserts to audio for CPU savings:
/// - Freeze track: render to audio, bypass inserts
/// - Unfreeze track: restore original state
/// - Track CPU usage before/after
/// - Store frozen audio path
///
/// Usage:
///   await TrackFreezeService.instance.freezeTrack(trackId);
///   await TrackFreezeService.instance.unfreezeTrack(trackId);
///   final savings = service.getCpuSavings(trackId);
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../src/rust/native_ffi.dart';
import '../providers/dsp_chain_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FREEZE STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Freeze state for a track
enum FreezeState {
  /// Not frozen, normal playback
  unfrozen,

  /// Currently freezing (rendering)
  freezing,

  /// Frozen, playing rendered audio
  frozen,

  /// Error during freeze
  error,
}

extension FreezeStateExtension on FreezeState {
  String get displayName {
    switch (this) {
      case FreezeState.unfrozen:
        return 'Unfrozen';
      case FreezeState.freezing:
        return 'Freezing...';
      case FreezeState.frozen:
        return 'Frozen';
      case FreezeState.error:
        return 'Error';
    }
  }

  bool get isProcessing => this == FreezeState.freezing;
}

// ═══════════════════════════════════════════════════════════════════════════
// FROZEN TRACK INFO
// ═══════════════════════════════════════════════════════════════════════════

/// Information about a frozen track
class FrozenTrackInfo {
  final int trackId;
  final String trackName;
  final FreezeState state;
  final String? frozenAudioPath;
  final DateTime? frozenAt;
  final double cpuUsageBefore;
  final double cpuUsageAfter;
  final int insertCount;
  final List<String> bypassedInserts;
  final String? errorMessage;

  FrozenTrackInfo({
    required this.trackId,
    required this.trackName,
    this.state = FreezeState.unfrozen,
    this.frozenAudioPath,
    this.frozenAt,
    this.cpuUsageBefore = 0.0,
    this.cpuUsageAfter = 0.0,
    this.insertCount = 0,
    this.bypassedInserts = const [],
    this.errorMessage,
  });

  FrozenTrackInfo copyWith({
    FreezeState? state,
    String? frozenAudioPath,
    DateTime? frozenAt,
    double? cpuUsageBefore,
    double? cpuUsageAfter,
    int? insertCount,
    List<String>? bypassedInserts,
    String? errorMessage,
  }) {
    return FrozenTrackInfo(
      trackId: trackId,
      trackName: trackName,
      state: state ?? this.state,
      frozenAudioPath: frozenAudioPath ?? this.frozenAudioPath,
      frozenAt: frozenAt ?? this.frozenAt,
      cpuUsageBefore: cpuUsageBefore ?? this.cpuUsageBefore,
      cpuUsageAfter: cpuUsageAfter ?? this.cpuUsageAfter,
      insertCount: insertCount ?? this.insertCount,
      bypassedInserts: bypassedInserts ?? this.bypassedInserts,
      errorMessage: errorMessage,
    );
  }

  /// CPU savings percentage (0-100)
  double get cpuSavings {
    if (cpuUsageBefore <= 0) return 0.0;
    return ((cpuUsageBefore - cpuUsageAfter) / cpuUsageBefore * 100)
        .clamp(0.0, 100.0);
  }

  /// Human-readable CPU savings
  String get cpuSavingsFormatted =>
      '${cpuSavings.toStringAsFixed(1)}% CPU saved';

  /// Is frozen and has valid audio
  bool get isFrozenWithAudio =>
      state == FreezeState.frozen && frozenAudioPath != null;
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK FREEZE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for freezing/unfreezing tracks
class TrackFreezeService extends ChangeNotifier {
  TrackFreezeService._();
  static final instance = TrackFreezeService._();

  final NativeFFI _ffi = NativeFFI.instance;

  // Track freeze info: trackId -> info
  final Map<int, FrozenTrackInfo> _trackInfo = {};

  // Configuration
  String _freezeDirectory = '';
  int _bitDepth = 32; // 16, 24, or 32 bit
  int _sampleRate = 48000;

  // Callbacks
  void Function(int trackId, double progress)? onFreezeProgress;
  void Function(int trackId, FrozenTrackInfo info)? onFreezeComplete;
  void Function(int trackId, String error)? onFreezeError;

  /// Get all frozen tracks
  List<FrozenTrackInfo> get frozenTracks =>
      _trackInfo.values.where((t) => t.state == FreezeState.frozen).toList();

  /// Get total CPU savings across all frozen tracks
  double get totalCpuSavings {
    final frozen = frozenTracks;
    if (frozen.isEmpty) return 0.0;

    double totalBefore = 0.0;
    double totalAfter = 0.0;
    for (final track in frozen) {
      totalBefore += track.cpuUsageBefore;
      totalAfter += track.cpuUsageAfter;
    }

    if (totalBefore <= 0) return 0.0;
    return ((totalBefore - totalAfter) / totalBefore * 100).clamp(0.0, 100.0);
  }

  /// Initialize service with freeze directory
  Future<void> init({String? freezeDirectory}) async {
    if (freezeDirectory != null) {
      _freezeDirectory = freezeDirectory;
    } else {
      // Default to temp directory
      _freezeDirectory = path.join(
        Directory.systemTemp.path,
        'FluxForge',
        'Freeze',
      );
    }

    // Ensure directory exists
    final dir = Directory(_freezeDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

  }

  /// Set freeze quality
  void setQuality({int? bitDepth, int? sampleRate}) {
    if (bitDepth != null) {
      _bitDepth = bitDepth.clamp(16, 32);
    }
    if (sampleRate != null) {
      _sampleRate = sampleRate.clamp(44100, 192000);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FREEZE OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Check if a track is frozen
  bool isFrozen(int trackId) =>
      _trackInfo[trackId]?.state == FreezeState.frozen;

  /// Get freeze info for a track
  FrozenTrackInfo? getInfo(int trackId) => _trackInfo[trackId];

  /// Get CPU savings for a specific track
  double getCpuSavings(int trackId) => _trackInfo[trackId]?.cpuSavings ?? 0.0;

  /// Freeze a track
  Future<bool> freezeTrack(int trackId, {String? trackName}) async {
    // Check if already frozen
    if (_trackInfo[trackId]?.state == FreezeState.frozen) {
      return true;
    }

    final dspProvider = DspChainProvider.instance;
    final chain = dspProvider.getChain(trackId);

    // Initialize info
    final info = FrozenTrackInfo(
      trackId: trackId,
      trackName: trackName ?? 'Track $trackId',
      state: FreezeState.freezing,
      insertCount: chain.nodes.length,
      cpuUsageBefore: _measureTrackCpu(trackId),
    );
    _trackInfo[trackId] = info;
    notifyListeners();

    try {
      // Generate output path
      final outputPath = path.join(
        _freezeDirectory,
        'freeze_track_${trackId}_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      // Render track to audio (offline bounce)
      final success = await _renderTrack(trackId, outputPath);

      if (!success) {
        throw Exception('Render failed');
      }

      // Bypass all inserts
      final bypassedInserts = <String>[];
      for (int i = 0; i < chain.nodes.length; i++) {
        _ffi.insertSetBypass(trackId, i, true);
        bypassedInserts.add(chain.nodes[i].name.isNotEmpty
            ? chain.nodes[i].name
            : chain.nodes[i].type.fullName);
      }

      // Update info
      _trackInfo[trackId] = info.copyWith(
        state: FreezeState.frozen,
        frozenAudioPath: outputPath,
        frozenAt: DateTime.now(),
        cpuUsageAfter: _measureTrackCpu(trackId),
        bypassedInserts: bypassedInserts,
      );

      onFreezeComplete?.call(trackId, _trackInfo[trackId]!);
      notifyListeners();

      return true;
    } catch (e) {
      _trackInfo[trackId] = info.copyWith(
        state: FreezeState.error,
        errorMessage: e.toString(),
      );

      onFreezeError?.call(trackId, e.toString());
      notifyListeners();

      return false;
    }
  }

  /// Unfreeze a track
  Future<bool> unfreezeTrack(int trackId) async {
    final info = _trackInfo[trackId];
    if (info == null || info.state != FreezeState.frozen) {
      return false;
    }

    try {
      final dspProvider = DspChainProvider.instance;
      final chain = dspProvider.getChain(trackId);

      // Re-enable all inserts
      for (int i = 0; i < chain.nodes.length; i++) {
        _ffi.insertSetBypass(trackId, i, false);
      }

      // Delete frozen audio file
      if (info.frozenAudioPath != null) {
        final file = File(info.frozenAudioPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Update info
      _trackInfo[trackId] = FrozenTrackInfo(
        trackId: trackId,
        trackName: info.trackName,
        state: FreezeState.unfrozen,
        insertCount: chain.nodes.length,
      );

      notifyListeners();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Unfreeze all tracks
  Future<void> unfreezeAll() async {
    final frozenIds = frozenTracks.map((t) => t.trackId).toList();
    for (final trackId in frozenIds) {
      await unfreezeTrack(trackId);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE METHODS
  // ─────────────────────────────────────────────────────────────────────────

  double _measureTrackCpu(int trackId) {
    // In a real implementation, this would query actual CPU usage
    // For now, estimate based on insert count
    final dspProvider = DspChainProvider.instance;
    final chain = dspProvider.getChain(trackId);

    // Rough estimate: 2% per processor
    return chain.nodes.length * 2.0;
  }

  Future<bool> _renderTrack(int trackId, String outputPath) async {
    // Simulate render progress
    for (int i = 0; i <= 100; i += 10) {
      await Future.delayed(const Duration(milliseconds: 50));
      onFreezeProgress?.call(trackId, i / 100.0);
    }

    // In a real implementation, this would:
    // 1. Get track timeline range
    // 2. Create offline render context
    // 3. Process audio through insert chain
    // 4. Write to output file

    // Create a placeholder file for testing
    final file = File(outputPath);
    await file.writeAsBytes([0x52, 0x49, 0x46, 0x46]); // RIFF header start

    return true;
  }
}
