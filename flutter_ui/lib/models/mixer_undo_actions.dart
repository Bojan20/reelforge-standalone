/// Mixer Undo Actions (P10.0.4)
///
/// Complete undo/redo support for all mixer operations:
/// - Volume changes
/// - Pan changes (including stereo dual-pan)
/// - Mute/Solo toggles
/// - Send level changes
/// - Routing changes
/// - Insert operations (load/unload/bypass)
///
/// All actions implement UndoableAction from undo_manager.dart
library;

import 'dart:math' as math;
import '../providers/undo_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BASE CLASS
// ═══════════════════════════════════════════════════════════════════════════

/// Base class for all mixer undo actions
/// Provides common functionality for channel identification and description formatting
abstract class MixerUndoAction extends UndoableAction {
  final String channelId;
  final String channelName;

  MixerUndoAction({
    required this.channelId,
    required this.channelName,
  });

  /// Convert linear volume (0-1.5) to dB string for display
  String volumeToDb(double volume) {
    if (volume <= 0) return '-∞ dB';
    final db = 20 * math.log(volume) / math.ln10;
    if (db <= -60) return '-∞ dB';
    return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
  }

  /// Convert pan (-1 to +1) to L/R string for display
  String panToString(double pan) {
    if (pan == 0) return 'C';
    if (pan < 0) return 'L${(-pan * 100).round()}';
    return 'R${(pan * 100).round()}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VOLUME CHANGE ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for volume fader changes
class VolumeChangeAction extends MixerUndoAction {
  final double oldVolume;
  final double newVolume;
  final void Function(String channelId, double volume) applyVolume;

  VolumeChangeAction({
    required super.channelId,
    required super.channelName,
    required this.oldVolume,
    required this.newVolume,
    required this.applyVolume,
  });

  @override
  String get description =>
      'Volume: $channelName ${volumeToDb(oldVolume)} → ${volumeToDb(newVolume)}';

  @override
  void execute() => applyVolume(channelId, newVolume);

  @override
  void undo() => applyVolume(channelId, oldVolume);
}

// ═══════════════════════════════════════════════════════════════════════════
// PAN CHANGE ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for pan knob changes (supports mono pan and stereo dual-pan)
class PanChangeAction extends MixerUndoAction {
  final double oldPan;
  final double newPan;
  final bool isRightChannel; // For stereo dual-pan (Pro Tools style)
  final void Function(String channelId, double pan) applyPan;

  PanChangeAction({
    required super.channelId,
    required super.channelName,
    required this.oldPan,
    required this.newPan,
    required this.applyPan,
    this.isRightChannel = false,
  });

  @override
  String get description {
    final side = isRightChannel ? 'Pan R' : 'Pan';
    return '$side: $channelName ${panToString(oldPan)} → ${panToString(newPan)}';
  }

  @override
  void execute() => applyPan(channelId, newPan);

  @override
  void undo() => applyPan(channelId, oldPan);
}

// ═══════════════════════════════════════════════════════════════════════════
// MUTE TOGGLE ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for mute button toggles
class MuteToggleAction extends MixerUndoAction {
  final bool wasMuted;
  final void Function(String channelId, bool muted) applyMute;

  MuteToggleAction({
    required super.channelId,
    required super.channelName,
    required this.wasMuted,
    required this.applyMute,
  });

  @override
  String get description =>
      'Mute: $channelName ${wasMuted ? 'ON → OFF' : 'OFF → ON'}';

  @override
  void execute() => applyMute(channelId, !wasMuted);

  @override
  void undo() => applyMute(channelId, wasMuted);
}

// ═══════════════════════════════════════════════════════════════════════════
// SOLO TOGGLE ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for solo button toggles
class SoloToggleAction extends MixerUndoAction {
  final bool wasSoloed;
  final void Function(String channelId, bool soloed) applySolo;

  SoloToggleAction({
    required super.channelId,
    required super.channelName,
    required this.wasSoloed,
    required this.applySolo,
  });

  @override
  String get description =>
      'Solo: $channelName ${wasSoloed ? 'ON → OFF' : 'OFF → ON'}';

  @override
  void execute() => applySolo(channelId, !wasSoloed);

  @override
  void undo() => applySolo(channelId, wasSoloed);
}

// ═══════════════════════════════════════════════════════════════════════════
// SEND LEVEL CHANGE ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for aux send level changes
class SendLevelChangeAction extends MixerUndoAction {
  final String sendId;
  final int sendIndex;
  final double oldLevel;
  final double newLevel;
  final void Function(String channelId, String sendId, double level) applyLevel;

  SendLevelChangeAction({
    required super.channelId,
    required super.channelName,
    required this.sendId,
    required this.sendIndex,
    required this.oldLevel,
    required this.newLevel,
    required this.applyLevel,
  });

  @override
  String get description {
    final oldDb = volumeToDb(oldLevel);
    final newDb = volumeToDb(newLevel);
    return 'Send ${sendIndex + 1}: $channelName $oldDb → $newDb';
  }

  @override
  void execute() => applyLevel(channelId, sendId, newLevel);

  @override
  void undo() => applyLevel(channelId, sendId, oldLevel);
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTE CHANGE ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for output routing changes
class RouteChangeAction extends MixerUndoAction {
  final String? oldBusId;
  final String? newBusId;
  final String? oldBusName;
  final String? newBusName;
  final void Function(String channelId, String? busId) applyRoute;

  RouteChangeAction({
    required super.channelId,
    required super.channelName,
    this.oldBusId,
    this.newBusId,
    this.oldBusName,
    this.newBusName,
    required this.applyRoute,
  });

  @override
  String get description {
    final oldName = oldBusName ?? oldBusId ?? 'None';
    final newName = newBusName ?? newBusId ?? 'None';
    return 'Route: $channelName $oldName → $newName';
  }

  @override
  void execute() => applyRoute(channelId, newBusId);

  @override
  void undo() => applyRoute(channelId, oldBusId);
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT LOAD ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for loading a processor into an insert slot
class InsertLoadAction extends MixerUndoAction {
  final int slotIndex;
  final String processorName;
  final String processorId;
  final String processorType;
  final void Function(String channelId, int slotIndex, String processorId,
      String processorName, String processorType) applyLoad;
  final void Function(String channelId, int slotIndex) applyUnload;

  InsertLoadAction({
    required super.channelId,
    required super.channelName,
    required this.slotIndex,
    required this.processorName,
    required this.processorId,
    required this.processorType,
    required this.applyLoad,
    required this.applyUnload,
  });

  @override
  String get description =>
      'Insert: $channelName slot ${slotIndex + 1} ← $processorName';

  @override
  void execute() =>
      applyLoad(channelId, slotIndex, processorId, processorName, processorType);

  @override
  void undo() => applyUnload(channelId, slotIndex);
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT UNLOAD ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for removing a processor from an insert slot
class InsertUnloadAction extends MixerUndoAction {
  final int slotIndex;
  final String processorName;
  final String processorId;
  final String processorType;
  final void Function(String channelId, int slotIndex) applyUnload;
  final void Function(String channelId, int slotIndex, String processorId,
      String processorName, String processorType) applyLoad;

  InsertUnloadAction({
    required super.channelId,
    required super.channelName,
    required this.slotIndex,
    required this.processorName,
    required this.processorId,
    required this.processorType,
    required this.applyUnload,
    required this.applyLoad,
  });

  @override
  String get description =>
      'Remove: $channelName slot ${slotIndex + 1} $processorName';

  @override
  void execute() => applyUnload(channelId, slotIndex);

  @override
  void undo() =>
      applyLoad(channelId, slotIndex, processorId, processorName, processorType);
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT BYPASS ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for toggling insert bypass state
class InsertBypassAction extends MixerUndoAction {
  final int slotIndex;
  final String processorName;
  final bool wasBypassed;
  final void Function(String channelId, int slotIndex, bool bypassed)
      applyBypass;

  InsertBypassAction({
    required super.channelId,
    required super.channelName,
    required this.slotIndex,
    required this.processorName,
    required this.wasBypassed,
    required this.applyBypass,
  });

  @override
  String get description {
    final state = wasBypassed ? 'ON → OFF' : 'OFF → ON';
    return 'Bypass: $channelName $processorName $state';
  }

  @override
  void execute() => applyBypass(channelId, slotIndex, !wasBypassed);

  @override
  void undo() => applyBypass(channelId, slotIndex, wasBypassed);
}

// ═══════════════════════════════════════════════════════════════════════════
// INPUT GAIN CHANGE ACTION
// ═══════════════════════════════════════════════════════════════════════════

/// Undo action for input gain/trim changes
class InputGainChangeAction extends MixerUndoAction {
  final double oldGain;
  final double newGain;
  final void Function(String channelId, double gain) applyGain;

  InputGainChangeAction({
    required super.channelId,
    required super.channelName,
    required this.oldGain,
    required this.newGain,
    required this.applyGain,
  });

  @override
  String get description {
    final oldDb = '${oldGain >= 0 ? '+' : ''}${oldGain.toStringAsFixed(1)} dB';
    final newDb = '${newGain >= 0 ? '+' : ''}${newGain.toStringAsFixed(1)} dB';
    return 'Gain: $channelName $oldDb → $newDb';
  }

  @override
  void execute() => applyGain(channelId, newGain);

  @override
  void undo() => applyGain(channelId, oldGain);
}
