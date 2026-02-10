/// Stage Auto Registrar
///
/// Registers all template stages with StageConfigurationService.
/// Maps template stage definitions to the system's StageDefinition format.
///
/// P3-12: Template Gallery
library;

import 'package:flutter/foundation.dart';

import '../../models/template_models.dart';
import '../../spatial/auto_spatial.dart';
import '../stage_configuration_service.dart';

/// Registers template stages with the stage configuration service
class StageAutoRegistrar {
  /// Register all stages from a built template
  ///
  /// Returns the number of stages registered
  int registerAll(BuiltTemplate template) {
    final stageService = StageConfigurationService.instance;
    int count = 0;

    for (final stage in template.source.allStages) {
      try {
        stageService.registerCustomStage(_convertToStageDefinition(stage, template));
        count++;
      } catch (e) { /* ignored */ }
    }

    // Also register symbol stages
    for (final symbol in template.source.symbols) {
      for (final context in symbol.audioContexts) {
        final stageId = context.stageForSymbol(symbol.id);
        try {
          stageService.registerCustomStage(StageDefinition(
            name: stageId,
            category: _categoryFromContext(context),
            priority: _priorityForSymbol(symbol, context),
            bus: SpatialBus.sfx,
            spatialIntent: 'CENTER',
            isPooled: context == SymbolAudioContext.land, // Pool land sounds
            isLooping: false,
            description: '${symbol.id} ${context.id}',
          ));
          count++;
        } catch (e) { /* ignored */ }
      }
    }

    // Register win tier stages
    for (final tier in template.source.winTiers) {
      for (final stageId in [tier.stageStart, tier.stageLoop, tier.stageEnd]) {
        try {
          stageService.registerCustomStage(StageDefinition(
            name: stageId,
            category: StageCategory.win,
            priority: _priorityForWinTier(tier.tier),
            bus: SpatialBus.sfx,
            spatialIntent: 'CENTER',
            isPooled: false,
            isLooping: stageId.endsWith('_LOOP'),
            description: '${tier.label} ${_stageTypeFromId(stageId)}',
          ));
          count++;
        } catch (e) { /* ignored */ }
      }
    }

    return count;
  }

  /// Convert template stage definition to system StageDefinition
  StageDefinition _convertToStageDefinition(
    TemplateStageDefinition stage,
    BuiltTemplate template,
  ) {
    return StageDefinition(
      name: stage.id,
      category: _convertCategory(stage.category),
      priority: stage.priority,
      bus: _convertBus(stage.bus),
      spatialIntent: _inferSpatialIntent(stage.id, template),
      isPooled: stage.isPooled,
      isLooping: stage.isLooping,
      ducksMusic: stage.ducksMusic,
      description: stage.description,
    );
  }

  /// Convert template category to system category
  StageCategory _convertCategory(TemplateStageCategory category) {
    return switch (category) {
      TemplateStageCategory.spin => StageCategory.spin,
      TemplateStageCategory.reel => StageCategory.spin,
      TemplateStageCategory.symbol => StageCategory.symbol,
      TemplateStageCategory.win => StageCategory.win,
      TemplateStageCategory.feature => StageCategory.feature,
      TemplateStageCategory.music => StageCategory.music,
      TemplateStageCategory.ui => StageCategory.ui,
      TemplateStageCategory.ambient => StageCategory.music,
    };
  }

  /// Convert template bus to system SpatialBus
  SpatialBus _convertBus(TemplateBus bus) {
    return switch (bus) {
      TemplateBus.master => SpatialBus.sfx,
      TemplateBus.music => SpatialBus.music,
      TemplateBus.sfx => SpatialBus.sfx,
      TemplateBus.reels => SpatialBus.reels,
      TemplateBus.wins => SpatialBus.sfx,
      TemplateBus.vo => SpatialBus.vo,
      TemplateBus.ui => SpatialBus.ui,
      TemplateBus.ambience => SpatialBus.ambience,
    };
  }

  /// Infer spatial intent from stage ID
  String _inferSpatialIntent(String stageId, BuiltTemplate template) {
    // Per-reel stages get spatial intent with reel index
    final reelStopMatch = RegExp(r'REEL_STOP_(\d+)').firstMatch(stageId);
    if (reelStopMatch != null) {
      final reelIndex = int.parse(reelStopMatch.group(1)!);
      return 'reel_stop_$reelIndex';
    }

    // REEL_SPIN_LOOP is center (single loop for all reels)
    if (stageId == 'REEL_SPIN_LOOP') {
      return 'CENTER';
    }

    // Feature intents
    if (stageId.contains('FS_') || stageId.contains('FREE_SPIN')) {
      return 'freespins';
    }
    if (stageId.contains('HOLD_') || stageId.contains('RESPIN')) {
      return 'holdwin';
    }
    if (stageId.contains('JACKPOT_')) {
      return 'jackpot';
    }
    if (stageId.contains('BIG_WIN') || stageId.contains('MEGA_WIN')) {
      return 'bigwin';
    }
    if (stageId.contains('CASCADE_')) {
      return 'cascade';
    }
    if (stageId.contains('BONUS_')) {
      return 'bonus';
    }

    // Win line spatial intent (will be calculated per win)
    if (stageId.contains('WIN_LINE_')) {
      return 'win_line';
    }

    return 'CENTER';
  }

  /// Get stage category from symbol audio context
  StageCategory _categoryFromContext(SymbolAudioContext context) {
    return switch (context) {
      SymbolAudioContext.land => StageCategory.symbol,
      SymbolAudioContext.win => StageCategory.win,
      SymbolAudioContext.expand => StageCategory.symbol,
      SymbolAudioContext.lock => StageCategory.symbol,
      SymbolAudioContext.transform => StageCategory.symbol,
      SymbolAudioContext.collect => StageCategory.symbol,
    };
  }

  /// Calculate priority for symbol based on type and context
  int _priorityForSymbol(TemplateSymbol symbol, SymbolAudioContext context) {
    // Base priority by symbol type
    final basePriority = switch (symbol.type) {
      SymbolType.wild => 70,
      SymbolType.scatter => 75,
      SymbolType.bonus => 75,
      SymbolType.jackpotGrand => 90,
      SymbolType.jackpotMajor => 85,
      SymbolType.jackpotMinor => 80,
      SymbolType.jackpotMini => 75,
      SymbolType.multiplier => 65,
      SymbolType.mystery => 60,
      SymbolType.coin => 55,
      SymbolType.highPay => 50,
      SymbolType.mediumPay => 45,
      SymbolType.lowPay => 40,
    };

    // Adjust by context
    final contextAdjust = switch (context) {
      SymbolAudioContext.win => 10,
      SymbolAudioContext.expand => 5,
      SymbolAudioContext.lock => 5,
      SymbolAudioContext.transform => 5,
      SymbolAudioContext.collect => 5,
      SymbolAudioContext.land => 0,
    };

    return (basePriority + contextAdjust).clamp(0, 100);
  }

  /// Calculate priority for win tier
  int _priorityForWinTier(WinTier tier) {
    return switch (tier) {
      WinTier.tier1 => 60,
      WinTier.tier2 => 65,
      WinTier.tier3 => 75,
      WinTier.tier4 => 80,
      WinTier.tier5 => 85,
      WinTier.tier6 => 90,
    };
  }

  /// Get stage type suffix from ID
  String _stageTypeFromId(String stageId) {
    if (stageId.endsWith('_START')) return 'Start';
    if (stageId.endsWith('_LOOP')) return 'Loop';
    if (stageId.endsWith('_END')) return 'End';
    return '';
  }
}
