/// Audio Context Service
///
/// Context-aware auto-action system for SlotLab.
/// Automatically determines Play/Stop actions based on:
/// - Audio file name (base_, fs_, bonus_, hold_, jackpot_)
/// - Stage type (_TRIGGER, _ENTER, _EXIT, _END)
/// - Audio type (music, sfx, voice, ambience)

import '../models/middleware_models.dart';

/// Game context/mode
enum AudioContext {
  baseGame,
  freeSpins,
  bonus,
  holdWin,
  jackpot,
  unknown,
}

/// Audio type category
enum AudioType {
  music,
  sfx,
  voice,
  ambience,
  unknown,
}

/// Stage type for action determination
enum StageType {
  entry,  // _TRIGGER, _ENTER, _START
  exit,   // _EXIT, _END, _STOP
  step,   // _STEP, _TICK, _SPIN
  other,
}

/// Result of auto-action determination
class AutoActionResult {
  final ActionType actionType;
  final String? stopTarget; // Bus or event to stop (for Stop actions)
  final String reason;      // Human-readable explanation

  const AutoActionResult({
    required this.actionType,
    this.stopTarget,
    required this.reason,
  });

  @override
  String toString() => '$actionType: $reason';
}

/// Singleton service for context-aware auto-action
class AudioContextService {
  AudioContextService._();
  static final instance = AudioContextService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO CONTEXT DETECTION (from file name)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Detect game context from audio file name/path
  AudioContext detectContextFromAudio(String audioPath) {
    final name = audioPath.toLowerCase();

    // Free Spins context
    if (name.contains('fs_') ||
        name.contains('freespin') ||
        name.contains('free_spin') ||
        name.contains('_fs') ||
        name.contains('freegame')) {
      return AudioContext.freeSpins;
    }

    // Bonus context
    if (name.contains('bonus') ||
        name.contains('_bonus') ||
        name.contains('bonus_')) {
      return AudioContext.bonus;
    }

    // Hold & Win context
    if (name.contains('hold') ||
        name.contains('respin') ||
        name.contains('hold_win') ||
        name.contains('holdwin')) {
      return AudioContext.holdWin;
    }

    // Jackpot context
    if (name.contains('jackpot') ||
        name.contains('grand') ||
        name.contains('major') ||
        name.contains('minor') ||
        name.contains('mini_jp')) {
      return AudioContext.jackpot;
    }

    // Base game context (default for music without specific prefix)
    if (name.contains('base') ||
        name.contains('main') ||
        name.contains('_base') ||
        name.contains('base_')) {
      return AudioContext.baseGame;
    }

    return AudioContext.unknown;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO TYPE DETECTION (from file name)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Detect audio type from file name/path
  AudioType detectAudioType(String audioPath) {
    final name = audioPath.toLowerCase();

    // Voice/VO detection
    if (name.contains('vo_') ||
        name.contains('_vo') ||
        name.contains('voice') ||
        name.contains('narrator') ||
        name.contains('announce')) {
      return AudioType.voice;
    }

    // Music detection
    if (name.contains('music') ||
        name.contains('_music') ||
        name.contains('bgm') ||
        name.contains('soundtrack') ||
        name.contains('theme') ||
        name.contains('loop') && !name.contains('sfx')) {
      return AudioType.music;
    }

    // Ambience detection
    if (name.contains('amb_') ||
        name.contains('_amb') ||
        name.contains('ambience') ||
        name.contains('ambient') ||
        name.contains('atmosphere')) {
      return AudioType.ambience;
    }

    // SFX detection (default for most sounds)
    if (name.contains('sfx') ||
        name.contains('fx_') ||
        name.contains('_fx') ||
        name.contains('sound') ||
        name.contains('click') ||
        name.contains('spin') ||
        name.contains('reel') ||
        name.contains('win') ||
        name.contains('coin') ||
        name.contains('whoosh')) {
      return AudioType.sfx;
    }

    // Default to SFX for short sounds, music for longer names
    return AudioType.unknown;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE CONTEXT DETECTION (from stage name)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Detect game context from stage name
  AudioContext detectContextFromStage(String stage) {
    final s = stage.toUpperCase();

    // Free Spins stages
    if (s.contains('FREESPIN') ||
        s.contains('FREE_SPIN') ||
        s.startsWith('FS_') ||
        s.contains('_FS_')) {
      return AudioContext.freeSpins;
    }

    // Bonus stages
    if (s.contains('BONUS')) {
      return AudioContext.bonus;
    }

    // Hold & Win stages
    if (s.contains('HOLD') ||
        s.contains('RESPIN') ||
        s.contains('RESPINS')) {
      return AudioContext.holdWin;
    }

    // Jackpot stages
    if (s.contains('JACKPOT') ||
        s.contains('GRAND') ||
        s.contains('MAJOR') && !s.contains('MINOR')) {
      return AudioContext.jackpot;
    }

    // Base game (default)
    return AudioContext.baseGame;
  }

  /// Detect stage type (entry, exit, step, other)
  StageType detectStageType(String stage) {
    final s = stage.toUpperCase();

    // Entry stages
    if (s.endsWith('_TRIGGER') ||
        s.endsWith('_ENTER') ||
        s.endsWith('_START') ||
        s.endsWith('_BEGIN') ||
        s.contains('_TRIGGER_') ||
        s.contains('_ENTER_')) {
      return StageType.entry;
    }

    // Exit stages
    if (s.endsWith('_EXIT') ||
        s.endsWith('_END') ||
        s.endsWith('_STOP') ||
        s.endsWith('_COMPLETE') ||
        s.endsWith('_FINISH') ||
        s.contains('_EXIT_') ||
        s.contains('_END_')) {
      return StageType.exit;
    }

    // Step stages (continuous/tick)
    if (s.endsWith('_STEP') ||
        s.endsWith('_TICK') ||
        s.endsWith('_SPIN') ||
        s.endsWith('_SPINNING') ||
        s.contains('_STEP_') ||
        s.contains('_TICK_')) {
      return StageType.step;
    }

    return StageType.other;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-ACTION DETERMINATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Determine the automatic action for an audio drop
  ///
  /// Logic:
  /// - SFX/VO → Always Play
  /// - Music/Ambience:
  ///   - Entry stage + audio context ≠ stage context → Stop (stop old music)
  ///   - Entry stage + audio context = stage context → Play (start new music)
  ///   - Exit stage → Stop (leaving context)
  ///   - Step stage → Play (continuous feedback)
  AutoActionResult determineAutoAction({
    required String audioPath,
    required String stage,
  }) {
    final audioType = detectAudioType(audioPath);
    final audioContext = detectContextFromAudio(audioPath);
    final stageContext = detectContextFromStage(stage);
    final stageType = detectStageType(stage);

    // ─────────────────────────────────────────────────────────────────────────
    // SFX and Voice → Always Play
    // ─────────────────────────────────────────────────────────────────────────
    if (audioType == AudioType.sfx || audioType == AudioType.voice) {
      return AutoActionResult(
        actionType: ActionType.play,
        reason: 'SFX/Voice → Always Play',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Music and Ambience → Context-dependent
    // ─────────────────────────────────────────────────────────────────────────
    if (audioType == AudioType.music || audioType == AudioType.ambience) {
      // Exit stages → Stop (we're leaving this context)
      if (stageType == StageType.exit) {
        return AutoActionResult(
          actionType: ActionType.stop,
          stopTarget: _contextToBusName(audioContext),
          reason: 'Exit stage → Stop ${audioContext.name} music',
        );
      }

      // Entry stages
      if (stageType == StageType.entry) {
        // Audio context matches stage context → Play (start this context's music)
        if (audioContext == stageContext || audioContext == AudioContext.unknown) {
          return AutoActionResult(
            actionType: ActionType.play,
            reason: 'Entry stage, matching context → Play',
          );
        }

        // Audio context differs from stage context → Stop (stop the OLD music)
        // This is for "stop base music when entering FS"
        return AutoActionResult(
          actionType: ActionType.stop,
          stopTarget: _contextToBusName(audioContext),
          reason: 'Entry stage, different context → Stop ${audioContext.name} music',
        );
      }

      // Step stages → Play (usually continuous feedback)
      if (stageType == StageType.step) {
        return AutoActionResult(
          actionType: ActionType.play,
          reason: 'Step stage → Play',
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Default → Play
    // ─────────────────────────────────────────────────────────────────────────
    return AutoActionResult(
      actionType: ActionType.play,
      reason: 'Default → Play',
    );
  }

  /// Get bus name for a context (for Stop actions)
  String _contextToBusName(AudioContext context) {
    switch (context) {
      case AudioContext.baseGame:
        return 'music'; // Base game music bus
      case AudioContext.freeSpins:
        return 'music'; // FS music (same bus, different track)
      case AudioContext.bonus:
        return 'music';
      case AudioContext.holdWin:
        return 'music';
      case AudioContext.jackpot:
        return 'music';
      case AudioContext.unknown:
        return 'music';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get human-readable name for audio context
  String getContextDisplayName(AudioContext context) {
    switch (context) {
      case AudioContext.baseGame:
        return 'Base Game';
      case AudioContext.freeSpins:
        return 'Free Spins';
      case AudioContext.bonus:
        return 'Bonus';
      case AudioContext.holdWin:
        return 'Hold & Win';
      case AudioContext.jackpot:
        return 'Jackpot';
      case AudioContext.unknown:
        return 'Unknown';
    }
  }

  /// Get human-readable name for audio type
  String getTypeDisplayName(AudioType type) {
    switch (type) {
      case AudioType.music:
        return 'Music';
      case AudioType.sfx:
        return 'SFX';
      case AudioType.voice:
        return 'Voice';
      case AudioType.ambience:
        return 'Ambience';
      case AudioType.unknown:
        return 'Unknown';
    }
  }
}
