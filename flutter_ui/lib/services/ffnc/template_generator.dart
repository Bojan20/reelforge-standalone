/// Template Generator — programmatically creates built-in template .zip files.
///
/// Each template contains:
/// - manifest.json — metadata
/// - events.json — composite events with Smart Default volumes (no audio paths)
/// - win_tiers.json — standard win tier configuration
/// - README.txt — human-readable description
///
/// Templates are generated on first access and cached to ~/.fluxforge/templates/builtin/

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'stage_defaults.dart';

class TemplateGenerator {
  TemplateGenerator._();

  static final _cacheDir = () {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, '.fluxforge', 'templates', 'builtin');
  }();

  /// Ensure all built-in templates exist. Creates them if missing.
  static Future<void> ensureBuiltInTemplates() async {
    final dir = Directory(_cacheDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (final spec in _templateSpecs) {
      final path = p.join(_cacheDir, '${spec.id}.zip');
      if (!File(path).existsSync()) {
        await _generateTemplate(spec, path);
      }
    }
  }

  /// Get path for a built-in template by ID.
  static String getTemplatePath(String id) => p.join(_cacheDir, '$id.zip');

  static Future<void> _generateTemplate(_TemplateSpec spec, String outputPath) async {
    final encoder = const JsonEncoder.withIndent('  ');
    final now = DateTime.now().toIso8601String();

    // Manifest
    final manifest = encoder.convert({
      'name': spec.name,
      'version': '1.0',
      'created': now,
      'creator': 'FluxForge Built-in',
      'reelCount': spec.reelCount,
      'eventCount': spec.stages.length,
      'mechanics': spec.mechanics,
      'ffncVersion': '1.0',
      'fluxforge_profile': true,
    });

    // Events — create composite events from stage list with Smart Defaults
    final events = spec.stages.map((stage) {
      final defaults = StageDefaults.getDefaultForStage(stage);
      return {
        'id': 'audio_$stage',
        'name': stage.replaceAll('_', ' '),
        'category': _categorize(stage),
        'color': 4283215696,
        'layers': <Map<String, dynamic>>[],  // No audio — template only
        'masterVolume': defaults.volume,
        'targetBusId': defaults.busId,
        'looping': defaults.loop,
        'maxInstances': 1,
        'createdAt': now,
        'modifiedAt': now,
        'triggerStages': [stage],
        'triggerConditions': <String, String>{},
        'timelinePositionMs': 0.0,
        'trackIndex': 0,
        'containerType': 'none',
        'overlap': !defaults.loop,
        'crossfadeMs': defaults.busId == 1 ? 500 : 0,
      };
    }).toList();

    final eventsJson = encoder.convert({
      'version': 1,
      'exportedAt': now,
      'compositeEvents': events,
    });

    // Win tiers — standard config
    final winTiersJson = encoder.convert(_standardWinTiers);

    // README
    final readme = StringBuffer()
      ..writeln('FluxForge Template: ${spec.name}')
      ..writeln('Reels: ${spec.reelCount}')
      ..writeln('Events: ${spec.stages.length}')
      ..writeln('Mechanics: ${spec.mechanics.join(", ")}')
      ..writeln()
      ..writeln(spec.description)
      ..writeln()
      ..writeln('Stages:')
      ..writeln(spec.stages.map((s) => '  $s').join('\n'));

    // Build ZIP
    final archive = Archive();
    _addText(archive, 'manifest.json', manifest);
    _addText(archive, 'events.json', eventsJson);
    _addText(archive, 'win_tiers.json', winTiersJson);
    _addText(archive, 'README.txt', readme.toString());

    final zipData = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipData);
  }

  static void _addText(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static String _categorize(String stage) {
    if (stage.startsWith('MUSIC_')) return 'music';
    if (stage.startsWith('AMBIENT_') || stage.startsWith('ATTRACT_') || stage.startsWith('IDLE_')) return 'ambient';
    if (stage.startsWith('TRANSITION_')) return 'transition';
    if (stage.startsWith('UI_')) return 'ui';
    if (stage.startsWith('VO_')) return 'voice';
    if (stage.startsWith('WIN_') || stage.startsWith('BIG_WIN_') || stage.startsWith('ROLLUP_')) return 'win';
    if (stage.startsWith('FEATURE_') || stage.startsWith('FREESPIN_')) return 'feature';
    if (stage.startsWith('CASCADE_')) return 'cascade';
    if (stage.startsWith('JACKPOT_')) return 'jackpot';
    return 'spin';
  }

  // ═══════════════════════════════════════════════════════════════
  // Template specifications
  // ═══════════════════════════════════════════════════════════════

  static const _templateSpecs = [
    _TemplateSpec(
      id: 'classic_5reel',
      name: 'Classic 5-Reel',
      description: 'Standard 5-reel slot with spin lifecycle, wins, big wins, free spins, and basic UI.',
      reelCount: 5,
      mechanics: ['free_spins'],
      stages: [
        'SPIN_START', 'REEL_SPIN_LOOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2',
        'REEL_STOP_3', 'REEL_STOP_4', 'SPIN_END', 'QUICK_STOP',
        'ANTICIPATION_TENSION', 'ANTICIPATION_TENSION_R3', 'ANTICIPATION_TENSION_R4', 'ANTICIPATION_OFF',
        'WIN_PRESENT_LOW', 'WIN_PRESENT_EQUAL', 'WIN_PRESENT_1', 'WIN_PRESENT_2', 'WIN_PRESENT_3',
        'WIN_PRESENT_4', 'WIN_PRESENT_5', 'WIN_PRESENT_END',
        'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END',
        'BIG_WIN_START', 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_END',
        'SCATTER_LAND', 'SCATTER_LAND_1', 'SCATTER_LAND_2', 'SCATTER_LAND_3',
        'FEATURE_ENTER', 'FEATURE_EXIT', 'FREESPIN_TRIGGER', 'FREESPIN_START', 'FREESPIN_END',
        'MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_BASE_L3',
        'MUSIC_FS_L1',
        'UI_SPIN_PRESS', 'UI_BET_UP', 'UI_BET_DOWN', 'UI_MENU_OPEN', 'UI_MENU_CLOSE',
      ],
    ),
    _TemplateSpec(
      id: 'megaways',
      name: 'Megaways',
      description: 'Megaways slot with cascade mechanics, multiplier trail, and expanding reels.',
      reelCount: 6,
      mechanics: ['cascade', 'free_spins', 'multiplier'],
      stages: [
        'SPIN_START', 'REEL_SPIN_LOOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2',
        'REEL_STOP_3', 'REEL_STOP_4', 'REEL_STOP_5', 'SPIN_END',         'ANTICIPATION_TENSION', 'ANTICIPATION_OFF',
        'WIN_PRESENT_1', 'WIN_PRESENT_2', 'WIN_PRESENT_3', 'WIN_PRESENT_4', 'WIN_PRESENT_5',
        'ROLLUP_TICK', 'ROLLUP_END',
        'BIG_WIN_START', 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_END',
        'CASCADE_START', 'CASCADE_STEP', 'CASCADE_STEP_1', 'CASCADE_STEP_2', 'CASCADE_STEP_3',
        'CASCADE_POP', 'CASCADE_END',
        'MULTIPLIER_INCREASE', 'MULTIPLIER_APPLY',
        'SCATTER_LAND', 'FEATURE_ENTER', 'FEATURE_EXIT',
        'FREESPIN_TRIGGER', 'FREESPIN_START', 'FREESPIN_END', 'FREESPIN_RETRIGGER',
        'MEGAWAYS_REVEAL', 'MEGAWAYS_EXPAND', 'MEGAWAYS_MAX',
        'MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_FS_L1',
        'TRANSITION_BASE_TO_FS', 'TRANSITION_FS_TO_BASE',
        'UI_SPIN_PRESS', 'UI_BET_UP', 'UI_BET_DOWN',
      ],
    ),
    _TemplateSpec(
      id: 'cascading',
      name: 'Cascading / Tumble',
      description: 'Tumble mechanics with progressive multiplier, cluster wins.',
      reelCount: 5,
      mechanics: ['cascade', 'free_spins'],
      stages: [
        'SPIN_START', 'REEL_SPIN_LOOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2',
        'REEL_STOP_3', 'REEL_STOP_4', 'SPIN_END',         'WIN_PRESENT_1', 'WIN_PRESENT_2', 'WIN_PRESENT_3', 'WIN_PRESENT_4', 'WIN_PRESENT_5',
        'ROLLUP_TICK', 'ROLLUP_END',
        'BIG_WIN_START', 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_END',
        'CASCADE_START', 'CASCADE_STEP', 'CASCADE_STEP_1', 'CASCADE_STEP_2',
        'CASCADE_STEP_3', 'CASCADE_STEP_4', 'CASCADE_POP', 'CASCADE_SYMBOL_POP',
        'CASCADE_END', 'CASCADE_ANTICIPATION',
        'MULTIPLIER_INCREASE', 'MULTIPLIER_APPLY',
        'SCATTER_LAND', 'FREESPIN_TRIGGER', 'FREESPIN_START', 'FREESPIN_END',
        'FEATURE_ENTER', 'FEATURE_EXIT',
        'MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_FS_L1',
        'UI_SPIN_PRESS', 'UI_BET_UP', 'UI_BET_DOWN',
        'ANTICIPATION_TENSION', 'ANTICIPATION_OFF',
      ],
    ),
    _TemplateSpec(
      id: 'hold_and_win',
      name: 'Hold & Win',
      description: 'Hold & win with respins, coin collection, and progressive jackpots.',
      reelCount: 5,
      mechanics: ['hold_and_win', 'free_spins', 'jackpot'],
      stages: [
        'SPIN_START', 'REEL_SPIN_LOOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2',
        'REEL_STOP_3', 'REEL_STOP_4', 'SPIN_END',         'WIN_PRESENT_1', 'WIN_PRESENT_2', 'WIN_PRESENT_3',
        'ROLLUP_TICK', 'ROLLUP_END',
        'BIG_WIN_START', 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_END',
        'HOLD_TRIGGER', 'HOLD_START', 'HOLD_END',
        'PRIZE_REVEAL', 'PRIZE_UPGRADE', 'GRAND_TRIGGER',
        'RESPIN_TRIGGER', 'RESPIN_START', 'RESPIN_STOP', 'RESPIN_END', 'RESPIN_LAST',
        'COIN_BURST', 'COIN_DROP', 'COIN_COLLECT', 'COIN_LOCK',
        'JACKPOT_TRIGGER', 'JACKPOT_MINI', 'JACKPOT_MINOR', 'JACKPOT_MAJOR', 'JACKPOT_GRAND',
        'JACKPOT_CELEBRATION',
        'SCATTER_LAND', 'FREESPIN_TRIGGER', 'FREESPIN_START', 'FREESPIN_END',
        'MUSIC_BASE_L1', 'MUSIC_HOLD_L1', 'MUSIC_FS_L1',
        'TRANSITION_BASE_TO_HOLD', 'TRANSITION_HOLD_TO_BASE',
        'UI_SPIN_PRESS', 'UI_BET_UP', 'UI_BET_DOWN',
      ],
    ),
    _TemplateSpec(
      id: 'bonus_wheel',
      name: 'Bonus Wheel',
      description: 'Wheel bonus + pick games with multiple bonus rounds.',
      reelCount: 5,
      mechanics: ['bonus', 'free_spins', 'wheel'],
      stages: [
        'SPIN_START', 'REEL_SPIN_LOOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2',
        'REEL_STOP_3', 'REEL_STOP_4', 'SPIN_END',         'WIN_PRESENT_1', 'WIN_PRESENT_2', 'WIN_PRESENT_3', 'WIN_PRESENT_4',
        'ROLLUP_TICK', 'ROLLUP_END',
        'BIG_WIN_START', 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_END',
        'BONUS_TRIGGER', 'BONUS_ENTER', 'BONUS_EXIT', 'BONUS_WIN',
        'WHEEL_START', 'WHEEL_SPIN', 'WHEEL_TICK', 'WHEEL_SLOW',
        'WHEEL_LAND', 'WHEEL_PRIZE', 'WHEEL_CELEBRATION',
        'PICK_BONUS_START', 'PICK_REVEAL', 'PICK_GOOD', 'PICK_BAD',
        'PICK_COLLECT', 'PICK_BONUS_END',
        'SCATTER_LAND', 'FREESPIN_TRIGGER', 'FREESPIN_START', 'FREESPIN_END',
        'MUSIC_BASE_L1', 'MUSIC_BONUS_L1', 'MUSIC_FS_L1',
        'TRANSITION_BASE_TO_BONUS', 'TRANSITION_BONUS_TO_BASE',
        'UI_SPIN_PRESS', 'UI_BET_UP', 'UI_BET_DOWN',
      ],
    ),
    _TemplateSpec(
      id: 'jackpot_progressive',
      name: 'Jackpot Progressive',
      description: 'Progressive jackpot with 4 tiers, jackpot wheel, and celebration sequences.',
      reelCount: 5,
      mechanics: ['jackpot', 'free_spins'],
      stages: [
        'SPIN_START', 'REEL_SPIN_LOOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2',
        'REEL_STOP_3', 'REEL_STOP_4', 'SPIN_END',         'WIN_PRESENT_1', 'WIN_PRESENT_2', 'WIN_PRESENT_3', 'WIN_PRESENT_4', 'WIN_PRESENT_5',
        'ROLLUP_TICK', 'ROLLUP_END',
        'BIG_WIN_START', 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_END',
        'JACKPOT_TRIGGER', 'JACKPOT_ELIGIBLE', 'JACKPOT_BUILDUP',
        'JACKPOT_REVEAL', 'JACKPOT_MINI', 'JACKPOT_MINOR', 'JACKPOT_MAJOR', 'JACKPOT_GRAND',
        'JACKPOT_MEGA', 'JACKPOT_CELEBRATION', 'JACKPOT_COLLECT', 'JACKPOT_END',
        'JACKPOT_BELLS', 'JACKPOT_SIRENS',
        'SCATTER_LAND', 'FREESPIN_TRIGGER', 'FREESPIN_START', 'FREESPIN_END',
        'FEATURE_ENTER', 'FEATURE_EXIT',
        'MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_JACKPOT_L1', 'MUSIC_FS_L1',
        'TRANSITION_BASE_TO_JACKPOT', 'TRANSITION_JACKPOT_TO_BASE',
        'ANTICIPATION_TENSION', 'ANTICIPATION_OFF',
        'UI_SPIN_PRESS', 'UI_BET_UP', 'UI_BET_DOWN',
      ],
    ),
  ];

  static const _standardWinTiers = {
    'regularWins': {
      'configId': 'standard',
      'name': 'Standard',
      'source': 'builtin',
      'tiers': [
        {'tierId': -1, 'fromMultiplier': 0.0, 'toMultiplier': 1.0, 'displayLabel': 'WIN LOW', 'rollupDurationMs': 0, 'rollupTickRate': 0, 'particleBurstCount': 0},
        {'tierId': 0, 'fromMultiplier': 1.0, 'toMultiplier': 1.001, 'displayLabel': 'WIN EQUAL', 'rollupDurationMs': 500, 'rollupTickRate': 10, 'particleBurstCount': 3},
        {'tierId': 1, 'fromMultiplier': 1.001, 'toMultiplier': 2.0, 'displayLabel': 'WIN 1', 'rollupDurationMs': 1000, 'rollupTickRate': 15, 'particleBurstCount': 5},
        {'tierId': 2, 'fromMultiplier': 2.0, 'toMultiplier': 4.0, 'displayLabel': 'WIN 2', 'rollupDurationMs': 1500, 'rollupTickRate': 15, 'particleBurstCount': 10},
        {'tierId': 3, 'fromMultiplier': 4.0, 'toMultiplier': 8.0, 'displayLabel': 'WIN 3', 'rollupDurationMs': 2000, 'rollupTickRate': 20, 'particleBurstCount': 15},
        {'tierId': 4, 'fromMultiplier': 8.0, 'toMultiplier': 13.0, 'displayLabel': 'WIN 4', 'rollupDurationMs': 3000, 'rollupTickRate': 20, 'particleBurstCount': 20},
        {'tierId': 5, 'fromMultiplier': 13.0, 'toMultiplier': 20.0, 'displayLabel': 'WIN 5', 'rollupDurationMs': 4000, 'rollupTickRate': 25, 'particleBurstCount': 25},
      ],
    },
    'bigWins': {
      'threshold': 20.0,
      'introDurationMs': 500,
      'endDurationMs': 4000,
      'fadeOutDurationMs': 1000,
      'tiers': [
        {'tierId': 1, 'fromMultiplier': 20.0, 'toMultiplier': 50.0, 'displayLabel': 'BIG WIN', 'durationMs': 4000, 'rollupTickRate': 12, 'visualIntensity': 1.0, 'particleMultiplier': 1.0, 'audioIntensity': 1.0},
        {'tierId': 2, 'fromMultiplier': 50.0, 'toMultiplier': 100.0, 'displayLabel': 'MEGA WIN', 'durationMs': 5000, 'rollupTickRate': 10, 'visualIntensity': 1.5, 'particleMultiplier': 2.0, 'audioIntensity': 1.2},
        {'tierId': 3, 'fromMultiplier': 100.0, 'toMultiplier': 'infinity', 'displayLabel': 'EPIC WIN', 'durationMs': 6000, 'rollupTickRate': 8, 'visualIntensity': 2.0, 'particleMultiplier': 3.0, 'audioIntensity': 1.5},
      ],
    },
  };
}

class _TemplateSpec {
  final String id;
  final String name;
  final String description;
  final int reelCount;
  final List<String> mechanics;
  final List<String> stages;

  const _TemplateSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.reelCount,
    required this.mechanics,
    required this.stages,
  });
}
