/// Template Builder Service
///
/// Converts SlotTemplate (JSON config) into BuiltTemplate (runtime-ready).
/// Handles stage generation, audio mapping, and template compilation.
///
/// P3-12: Template Gallery
library;

import 'package:flutter/foundation.dart';

import '../../models/template_models.dart';

/// Service for building templates from JSON config
class TemplateBuilderService {
  TemplateBuilderService._();
  static final instance = TemplateBuilderService._();

  /// Build a runtime-ready template from a SlotTemplate config
  ///
  /// Note: audioFolderPath should be empty for new templates.
  /// Audio mappings are added later by the user.
  BuiltTemplate buildTemplate(SlotTemplate source, {String audioFolderPath = ''}) {
    debugPrint('[TemplateBuilder] Building template: ${source.name}');

    // Template starts with no audio mappings - user assigns them later
    final audioMappings = <AudioMapping>[];

    debugPrint('[TemplateBuilder] Generated ${source.allStages.length} stages from template');

    return BuiltTemplate(
      source: source,
      audioMappings: audioMappings,
      audioFolderPath: audioFolderPath,
      builtAt: DateTime.now(),
    );
  }

  /// Generate additional per-reel stages not already in coreStages
  ///
  /// Note: REEL_SPIN_LOOP is a single loop for all reels (not per-reel).
  /// Only REEL_STOP is per-reel for stereo panning.
  List<TemplateStageDefinition> generatePerReelStages(SlotTemplate source) {
    final stages = <TemplateStageDefinition>[];
    final reelCount = source.reelCount;

    // Single spin loop for all reels (NOT per-reel)
    stages.add(TemplateStageDefinition(
      id: 'REEL_SPIN_LOOP',
      name: 'Reel Spin Loop',
      category: TemplateStageCategory.reel,
      priority: 30,
      isPooled: false,
      isLooping: true,
      description: 'Spinning loop for all reels',
    ));

    // REEL_STOP per reel (for stereo panning)
    for (int i = 0; i < reelCount; i++) {
      stages.add(TemplateStageDefinition(
        id: 'REEL_STOP_$i',
        name: 'Reel $i Stop',
        category: TemplateStageCategory.reel,
        priority: 50,
        isPooled: true,
        isLooping: false,
        description: 'Reel $i stop sound',
      ));
    }

    return stages;
  }

  /// Generate per-symbol stages (SYMBOL_LAND_WILD, WIN_SYMBOL_HIGHLIGHT_HP1, etc.)
  List<TemplateStageDefinition> generatePerSymbolStages(SlotTemplate source) {
    final stages = <TemplateStageDefinition>[];

    for (final symbol in source.symbols) {
      final symbolId = symbol.id.toUpperCase();

      // SYMBOL_LAND
      stages.add(TemplateStageDefinition(
        id: 'SYMBOL_LAND_$symbolId',
        name: '${symbol.id} Land',
        category: TemplateStageCategory.symbol,
        priority: 40,
        isPooled: true,
        isLooping: false,
        description: '${symbol.id} land sound',
      ));

      // WIN_SYMBOL_HIGHLIGHT
      stages.add(TemplateStageDefinition(
        id: 'WIN_SYMBOL_HIGHLIGHT_$symbolId',
        name: '${symbol.id} Win Highlight',
        category: TemplateStageCategory.win,
        priority: 55,
        isPooled: true,
        isLooping: false,
        description: '${symbol.id} win highlight',
      ));

      // Special symbol stages
      if (symbol.type == SymbolType.wild) {
        stages.add(TemplateStageDefinition(
          id: 'WILD_EXPAND_$symbolId',
          name: '${symbol.id} Wild Expand',
          category: TemplateStageCategory.symbol,
          priority: 65,
          isPooled: false,
          isLooping: false,
          description: '${symbol.id} wild expansion',
        ));
      }

      if (symbol.type == SymbolType.scatter) {
        stages.add(TemplateStageDefinition(
          id: 'SCATTER_LAND_$symbolId',
          name: '${symbol.id} Scatter Land',
          category: TemplateStageCategory.symbol,
          priority: 70,
          isPooled: false,
          isLooping: false,
          description: '${symbol.id} scatter land',
        ));
      }

      if (symbol.type == SymbolType.bonus) {
        stages.add(TemplateStageDefinition(
          id: 'BONUS_SYMBOL_$symbolId',
          name: '${symbol.id} Bonus Symbol',
          category: TemplateStageCategory.symbol,
          priority: 70,
          isPooled: false,
          isLooping: false,
          description: '${symbol.id} bonus symbol',
        ));
      }
    }

    return stages;
  }

  /// Generate win tier stages
  List<TemplateStageDefinition> generateWinTierStages(SlotTemplate source) {
    final stages = <TemplateStageDefinition>[];

    for (final tier in source.winTiers) {
      final tierLabel = tier.label.toUpperCase().replaceAll(' ', '_');

      stages.add(TemplateStageDefinition(
        id: 'WIN_PRESENT_$tierLabel',
        name: '${tier.label} Present',
        category: TemplateStageCategory.win,
        priority: 75 + (tier.tier.index * 2),
        isPooled: false,
        isLooping: false,
        description: '${tier.label} presentation',
      ));

      stages.add(TemplateStageDefinition(
        id: 'WIN_CELEBRATE_$tierLabel',
        name: '${tier.label} Celebrate',
        category: TemplateStageCategory.win,
        priority: 76 + (tier.tier.index * 2),
        isPooled: false,
        isLooping: tier.tier.index >= WinTier.tier3.index, // Loop for big wins
        description: '${tier.label} celebration',
      ));
    }

    return stages;
  }

  /// Generate feature-specific stages
  List<TemplateStageDefinition> generateFeatureStages(FeatureModule module) {
    final stages = <TemplateStageDefinition>[];
    final featurePrefix = module.type.name.toUpperCase();

    // Common feature stages
    stages.addAll([
      TemplateStageDefinition(
        id: '${featurePrefix}_TRIGGER',
        name: '${module.name} Trigger',
        category: TemplateStageCategory.feature,
        priority: 80,
        isPooled: false,
        isLooping: false,
        description: '${module.name} trigger',
      ),
      TemplateStageDefinition(
        id: '${featurePrefix}_ENTER',
        name: '${module.name} Enter',
        category: TemplateStageCategory.feature,
        priority: 81,
        isPooled: false,
        isLooping: false,
        description: '${module.name} enter',
      ),
      TemplateStageDefinition(
        id: '${featurePrefix}_EXIT',
        name: '${module.name} Exit',
        category: TemplateStageCategory.feature,
        priority: 82,
        isPooled: false,
        isLooping: false,
        description: '${module.name} exit',
      ),
      TemplateStageDefinition(
        id: '${featurePrefix}_MUSIC',
        name: '${module.name} Music',
        category: TemplateStageCategory.music,
        priority: 20,
        isPooled: false,
        isLooping: true,
        description: '${module.name} background music',
      ),
    ]);

    // Feature-specific stages
    switch (module.type) {
      case FeatureModuleType.freeSpins:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_SPIN',
            name: 'Free Spin Start',
            category: TemplateStageCategory.feature,
            priority: 83,
            isPooled: true,
            isLooping: false,
            description: 'Free spin start',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_RETRIGGER',
            name: 'Free Spins Retrigger',
            category: TemplateStageCategory.feature,
            priority: 84,
            isPooled: false,
            isLooping: false,
            description: 'Free spins retrigger',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_LAST_SPIN',
            name: 'Last Free Spin',
            category: TemplateStageCategory.feature,
            priority: 85,
            isPooled: false,
            isLooping: false,
            description: 'Last free spin',
          ),
        ]);

      case FeatureModuleType.holdWin:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_RESPIN',
            name: 'Hold & Win Respin',
            category: TemplateStageCategory.feature,
            priority: 83,
            isPooled: true,
            isLooping: false,
            description: 'Hold & Win respin',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_LOCK',
            name: 'Symbol Lock',
            category: TemplateStageCategory.feature,
            priority: 84,
            isPooled: true,
            isLooping: false,
            description: 'Symbol lock',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_RESPINS_RESET',
            name: 'Respins Reset',
            category: TemplateStageCategory.feature,
            priority: 85,
            isPooled: false,
            isLooping: false,
            description: 'Respins reset',
          ),
        ]);

      case FeatureModuleType.cascade:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_STEP',
            name: 'Cascade Step',
            category: TemplateStageCategory.feature,
            priority: 60,
            isPooled: true,
            isLooping: false,
            description: 'Cascade step',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_POP',
            name: 'Symbol Pop',
            category: TemplateStageCategory.feature,
            priority: 61,
            isPooled: true,
            isLooping: false,
            description: 'Symbol pop',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_DROP',
            name: 'Symbols Drop',
            category: TemplateStageCategory.feature,
            priority: 62,
            isPooled: true,
            isLooping: false,
            description: 'Symbols drop',
          ),
        ]);

      case FeatureModuleType.jackpot:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_MINI',
            name: 'Mini Jackpot',
            category: TemplateStageCategory.feature,
            priority: 90,
            isPooled: false,
            isLooping: false,
            description: 'Mini jackpot',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_MINOR',
            name: 'Minor Jackpot',
            category: TemplateStageCategory.feature,
            priority: 91,
            isPooled: false,
            isLooping: false,
            description: 'Minor jackpot',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_MAJOR',
            name: 'Major Jackpot',
            category: TemplateStageCategory.feature,
            priority: 92,
            isPooled: false,
            isLooping: false,
            description: 'Major jackpot',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_GRAND',
            name: 'Grand Jackpot',
            category: TemplateStageCategory.feature,
            priority: 95,
            isPooled: false,
            isLooping: false,
            description: 'Grand jackpot',
          ),
        ]);

      case FeatureModuleType.gamble:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_START',
            name: 'Gamble Start',
            category: TemplateStageCategory.feature,
            priority: 50,
            isPooled: false,
            isLooping: false,
            description: 'Gamble start',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_WIN',
            name: 'Gamble Win',
            category: TemplateStageCategory.feature,
            priority: 55,
            isPooled: false,
            isLooping: false,
            description: 'Gamble win',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_LOSE',
            name: 'Gamble Lose',
            category: TemplateStageCategory.feature,
            priority: 55,
            isPooled: false,
            isLooping: false,
            description: 'Gamble lose',
          ),
        ]);

      case FeatureModuleType.multiplier:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_INCREASE',
            name: 'Multiplier Increase',
            category: TemplateStageCategory.feature,
            priority: 70,
            isPooled: true,
            isLooping: false,
            description: 'Multiplier increase',
          ),
          TemplateStageDefinition(
            id: '${featurePrefix}_MAX',
            name: 'Max Multiplier',
            category: TemplateStageCategory.feature,
            priority: 75,
            isPooled: false,
            isLooping: false,
            description: 'Max multiplier reached',
          ),
        ]);

      case FeatureModuleType.mystery:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_REVEAL',
            name: 'Mystery Reveal',
            category: TemplateStageCategory.feature,
            priority: 65,
            isPooled: true,
            isLooping: false,
            description: 'Mystery reveal',
          ),
        ]);

      case FeatureModuleType.buyBonus:
        stages.addAll([
          TemplateStageDefinition(
            id: '${featurePrefix}_PURCHASE',
            name: 'Bonus Purchase',
            category: TemplateStageCategory.feature,
            priority: 50,
            isPooled: false,
            isLooping: false,
            description: 'Bonus purchase',
          ),
        ]);

      // Other module types use their own stages from the module definition
      default:
        break;
    }

    return stages;
  }

  /// Generate anticipation stages
  ///
  /// Note: Anticipation NEVER triggers on reel 0 (first reel).
  /// It only activates on reels 1+ when 2+ scatters have landed.
  List<TemplateStageDefinition> generateAnticipationStages(SlotTemplate source) {
    final stages = <TemplateStageDefinition>[];
    final reelCount = source.reelCount;

    // Per-reel anticipation with tension levels
    // Start from reel 1 (NOT reel 0 - anticipation never on first reel)
    for (int reel = 1; reel < reelCount; reel++) {
      for (int level = 1; level <= 4; level++) {
        stages.add(TemplateStageDefinition(
          id: 'ANTICIPATION_TENSION_R${reel}_L$level',
          name: 'Anticipation R$reel L$level',
          category: TemplateStageCategory.feature,
          priority: 68 + level,
          isPooled: false,
          isLooping: true,
          description: 'Reel $reel anticipation level $level',
        ));
      }
    }

    // Generic anticipation
    stages.addAll([
      TemplateStageDefinition(
        id: 'ANTICIPATION_ON',
        name: 'Anticipation Start',
        category: TemplateStageCategory.feature,
        priority: 68,
        isPooled: false,
        isLooping: true,
        description: 'Anticipation start',
      ),
      TemplateStageDefinition(
        id: 'ANTICIPATION_OFF',
        name: 'Anticipation End',
        category: TemplateStageCategory.feature,
        priority: 67,
        isPooled: false,
        isLooping: false,
        description: 'Anticipation end',
      ),
    ]);

    return stages;
  }

  /// Build with audio mappings (for importing complete templates)
  BuiltTemplate buildWithMappings(
    SlotTemplate source,
    List<AudioMapping> mappings,
    String audioFolderPath,
  ) {
    return BuiltTemplate(
      source: source,
      audioMappings: mappings,
      audioFolderPath: audioFolderPath,
      builtAt: DateTime.now(),
    );
  }

  /// Get all generated stages for a template (core + generated)
  List<TemplateStageDefinition> getAllGeneratedStages(SlotTemplate source) {
    final stages = <TemplateStageDefinition>[];

    // 1. Core stages from template
    stages.addAll(source.coreStages);

    // 2. Per-reel stages
    stages.addAll(generatePerReelStages(source));

    // 3. Per-symbol stages
    stages.addAll(generatePerSymbolStages(source));

    // 4. Win tier stages
    stages.addAll(generateWinTierStages(source));

    // 5. Feature-specific stages
    for (final module in source.modules) {
      stages.addAll(generateFeatureStages(module));
    }

    // 6. Anticipation stages
    stages.addAll(generateAnticipationStages(source));

    return stages;
  }
}
