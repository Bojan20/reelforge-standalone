// ═══════════════════════════════════════════════════════════════════════════
// P3.5: AUDIO SUGGESTION SERVICE — Auto-generate audio recommendations
// ═══════════════════════════════════════════════════════════════════════════
//
// Provides intelligent audio suggestions based on stage type:
// - Recommended audio characteristics (duration, intensity)
// - Suggested file name patterns
// - Bus routing recommendations
// - Volume/pan suggestions
//
library;

import '../config/stage_config.dart';

/// P3.5: Audio suggestion for a stage
class AudioSuggestion {
  final String stageType;
  final String description;
  final double suggestedDurationMs;
  final double suggestedVolume;
  final double suggestedPan;
  final String suggestedBus;
  final List<String> fileNamePatterns;
  final List<String> keywords;
  final bool isLooping;
  final bool isPooled;

  const AudioSuggestion({
    required this.stageType,
    required this.description,
    required this.suggestedDurationMs,
    this.suggestedVolume = 1.0,
    this.suggestedPan = 0.0,
    this.suggestedBus = 'sfx',
    this.fileNamePatterns = const [],
    this.keywords = const [],
    this.isLooping = false,
    this.isPooled = false,
  });
}

/// P3.5: Audio Suggestion Service Singleton
class AudioSuggestionService {
  AudioSuggestionService._();
  static final AudioSuggestionService instance = AudioSuggestionService._();

  /// Get audio suggestion for a stage type
  AudioSuggestion getSuggestion(String stageType) {
    final normalized = stageType.toLowerCase();
    final config = StageConfig.instance.getConfig(normalized);
    final category = config?.category ?? StageCategory.custom;

    return _getSuggestionForCategory(normalized, category);
  }

  /// Get suggestions for multiple stages
  List<AudioSuggestion> getSuggestionsForStages(List<String> stages) {
    return stages.map((s) => getSuggestion(s)).toList();
  }

  AudioSuggestion _getSuggestionForCategory(String stage, StageCategory category) {
    switch (category) {
      case StageCategory.spin:
        return _getSpinSuggestion(stage);
      case StageCategory.anticipation:
        return _getAnticipationSuggestion(stage);
      case StageCategory.win:
        return _getWinSuggestion(stage);
      case StageCategory.rollup:
        return _getRollupSuggestion(stage);
      case StageCategory.bigwin:
        return _getBigWinSuggestion(stage);
      case StageCategory.feature:
        return _getFeatureSuggestion(stage);
      case StageCategory.cascade:
        return _getCascadeSuggestion(stage);
      case StageCategory.jackpot:
        return _getJackpotSuggestion(stage);
      case StageCategory.bonus:
        return _getBonusSuggestion(stage);
      case StageCategory.gamble:
        return _getGambleSuggestion(stage);
      case StageCategory.music:
        return _getMusicSuggestion(stage);
      case StageCategory.ui:
        return _getUiSuggestion(stage);
      case StageCategory.system:
        return _getSystemSuggestion(stage);
      case StageCategory.custom:
        return _getGenericSuggestion(stage);
    }
  }

  AudioSuggestion _getSpinSuggestion(String stage) {
    if (stage.contains('start')) {
      return AudioSuggestion(
        stageType: stage,
        description: 'Spin initiation - button click or lever pull',
        suggestedDurationMs: 200,
        suggestedVolume: 0.8,
        suggestedBus: 'ui',
        fileNamePatterns: ['spin_start', 'spin_button', 'lever_pull'],
        keywords: ['click', 'mechanical', 'satisfying'],
      );
    }
    if (stage.contains('spinning') || stage.contains('reel_spin')) {
      return AudioSuggestion(
        stageType: stage,
        description: 'Reel spinning loop - continuous motion',
        suggestedDurationMs: 500,
        suggestedVolume: 0.6,
        suggestedBus: 'reels',
        fileNamePatterns: ['reel_spin', 'spinning_loop', 'reel_motion'],
        keywords: ['loop', 'whoosh', 'spinning'],
        isLooping: true,
        isPooled: true,
      );
    }
    if (stage.contains('stop')) {
      final reelIndex = _extractReelIndex(stage);
      final pan = reelIndex != null ? (reelIndex - 2) * 0.4 : 0.0;
      return AudioSuggestion(
        stageType: stage,
        description: 'Reel stop impact - mechanical thud',
        suggestedDurationMs: 150,
        suggestedVolume: 0.9,
        suggestedPan: pan.clamp(-1.0, 1.0),
        suggestedBus: 'reels',
        fileNamePatterns: ['reel_stop', 'reel_land', 'stop_thud'],
        keywords: ['impact', 'thud', 'mechanical', 'satisfying'],
        isPooled: true,
      );
    }
    return _getGenericSuggestion(stage);
  }

  AudioSuggestion _getAnticipationSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'Building tension for potential win',
      suggestedDurationMs: 800,
      suggestedVolume: 0.7,
      suggestedBus: 'sfx',
      fileNamePatterns: ['anticipation', 'tension', 'buildup', 'near_win'],
      keywords: ['rising', 'tension', 'suspense', 'dramatic'],
    );
  }

  AudioSuggestion _getWinSuggestion(String stage) {
    if (stage.contains('line_show')) {
      return AudioSuggestion(
        stageType: stage,
        description: 'Win line highlight',
        suggestedDurationMs: 300,
        suggestedVolume: 0.8,
        suggestedBus: 'wins',
        fileNamePatterns: ['win_line', 'line_highlight', 'symbol_glow'],
        keywords: ['shine', 'highlight', 'sparkle'],
        isPooled: true,
      );
    }
    return AudioSuggestion(
      stageType: stage,
      description: 'Win presentation fanfare',
      suggestedDurationMs: 1500,
      suggestedVolume: 0.9,
      suggestedBus: 'wins',
      fileNamePatterns: ['win_present', 'win_fanfare', 'victory'],
      keywords: ['fanfare', 'celebration', 'positive'],
    );
  }

  AudioSuggestion _getRollupSuggestion(String stage) {
    if (stage.contains('tick')) {
      return AudioSuggestion(
        stageType: stage,
        description: 'Counter tick during rollup',
        suggestedDurationMs: 50,
        suggestedVolume: 0.6,
        suggestedBus: 'wins',
        fileNamePatterns: ['rollup_tick', 'counter_tick', 'coin_tick'],
        keywords: ['tick', 'coin', 'counter'],
        isPooled: true,
      );
    }
    return AudioSuggestion(
      stageType: stage,
      description: 'Win amount rollup',
      suggestedDurationMs: 2000,
      suggestedVolume: 0.7,
      suggestedBus: 'wins',
      fileNamePatterns: ['rollup', 'counter', 'tally'],
      keywords: ['counting', 'coins', 'accumulating'],
    );
  }

  AudioSuggestion _getBigWinSuggestion(String stage) {
    String tier = 'big';
    if (stage.contains('mega')) tier = 'mega';
    if (stage.contains('epic')) tier = 'epic';
    if (stage.contains('ultra')) tier = 'ultra';

    return AudioSuggestion(
      stageType: stage,
      description: '${tier.toUpperCase()} win celebration',
      suggestedDurationMs: tier == 'ultra' ? 8000 : tier == 'epic' ? 5000 : 3000,
      suggestedVolume: 1.0,
      suggestedBus: 'wins',
      fileNamePatterns: ['${tier}_win', 'win_$tier', '${tier}_celebration'],
      keywords: ['epic', 'celebration', 'coins', 'fanfare'],
    );
  }

  AudioSuggestion _getFeatureSuggestion(String stage) {
    if (stage.contains('enter')) {
      return AudioSuggestion(
        stageType: stage,
        description: 'Feature mode entry fanfare',
        suggestedDurationMs: 2000,
        suggestedVolume: 1.0,
        suggestedBus: 'sfx',
        fileNamePatterns: ['feature_enter', 'mode_start', 'bonus_trigger'],
        keywords: ['exciting', 'dramatic', 'transition'],
      );
    }
    if (stage.contains('exit')) {
      return AudioSuggestion(
        stageType: stage,
        description: 'Feature mode exit transition',
        suggestedDurationMs: 1500,
        suggestedVolume: 0.8,
        suggestedBus: 'sfx',
        fileNamePatterns: ['feature_exit', 'mode_end', 'return'],
        keywords: ['transition', 'resolve'],
      );
    }
    return _getGenericSuggestion(stage);
  }

  AudioSuggestion _getCascadeSuggestion(String stage) {
    if (stage.contains('step')) {
      return AudioSuggestion(
        stageType: stage,
        description: 'Cascade step - symbols falling',
        suggestedDurationMs: 300,
        suggestedVolume: 0.7,
        suggestedBus: 'sfx',
        fileNamePatterns: ['cascade_step', 'symbols_fall', 'tumble'],
        keywords: ['falling', 'tumble', 'impact'],
        isPooled: true,
      );
    }
    return AudioSuggestion(
      stageType: stage,
      description: 'Cascade sequence',
      suggestedDurationMs: 500,
      suggestedVolume: 0.8,
      suggestedBus: 'sfx',
      fileNamePatterns: ['cascade', 'avalanche', 'tumble'],
      keywords: ['cascade', 'falling', 'chain'],
    );
  }

  AudioSuggestion _getJackpotSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'JACKPOT - maximum impact celebration',
      suggestedDurationMs: 10000,
      suggestedVolume: 1.0,
      suggestedBus: 'wins',
      fileNamePatterns: ['jackpot', 'grand_win', 'mega_jackpot'],
      keywords: ['epic', 'massive', 'celebration', 'coins'],
    );
  }

  AudioSuggestion _getBonusSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'Bonus game audio',
      suggestedDurationMs: 1500,
      suggestedVolume: 0.9,
      suggestedBus: 'sfx',
      fileNamePatterns: ['bonus', 'pick_bonus', 'wheel'],
      keywords: ['exciting', 'interactive', 'reward'],
    );
  }

  AudioSuggestion _getGambleSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'Gamble feature audio',
      suggestedDurationMs: 800,
      suggestedVolume: 0.8,
      suggestedBus: 'sfx',
      fileNamePatterns: ['gamble', 'double_up', 'card_flip'],
      keywords: ['tension', 'risk', 'cards'],
    );
  }

  AudioSuggestion _getMusicSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'Background music layer',
      suggestedDurationMs: 60000,
      suggestedVolume: 0.5,
      suggestedBus: 'music',
      fileNamePatterns: ['music', 'bgm', 'ambient'],
      keywords: ['loop', 'background', 'mood'],
      isLooping: true,
    );
  }

  AudioSuggestion _getUiSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'UI interaction feedback',
      suggestedDurationMs: 100,
      suggestedVolume: 0.6,
      suggestedBus: 'ui',
      fileNamePatterns: ['ui_click', 'button', 'interface'],
      keywords: ['click', 'tap', 'subtle'],
    );
  }

  AudioSuggestion _getSystemSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'System notification',
      suggestedDurationMs: 500,
      suggestedVolume: 0.5,
      suggestedBus: 'ui',
      fileNamePatterns: ['system', 'notification', 'alert'],
      keywords: ['notification', 'system'],
    );
  }

  AudioSuggestion _getGenericSuggestion(String stage) {
    return AudioSuggestion(
      stageType: stage,
      description: 'Custom stage audio',
      suggestedDurationMs: 500,
      suggestedVolume: 0.8,
      suggestedBus: 'sfx',
      fileNamePatterns: [stage],
      keywords: [],
    );
  }

  int? _extractReelIndex(String stage) {
    final match = RegExp(r'_(\d)$').firstMatch(stage);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }
}
