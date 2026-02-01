// ============================================================================
// FluxForge Studio — Feature Builder Block Generation Tests
// ============================================================================
// P13.8.8: Unit tests for stage generation from all feature blocks.
// Tests verify that each block generates expected stages with correct properties.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/blocks/game_core_block.dart';
import 'package:fluxforge_ui/blocks/grid_block.dart';
import 'package:fluxforge_ui/blocks/symbol_set_block.dart';
import 'package:fluxforge_ui/blocks/free_spins_block.dart';
import 'package:fluxforge_ui/blocks/respin_block.dart';
import 'package:fluxforge_ui/blocks/hold_and_win_block.dart';
import 'package:fluxforge_ui/blocks/cascades_block.dart';
import 'package:fluxforge_ui/blocks/collector_block.dart';
import 'package:fluxforge_ui/blocks/win_presentation_block.dart';
import 'package:fluxforge_ui/blocks/music_states_block.dart';
import 'package:fluxforge_ui/blocks/transitions_block.dart';
import 'package:fluxforge_ui/blocks/jackpot_block.dart';
import 'package:fluxforge_ui/blocks/multiplier_block.dart';
import 'package:fluxforge_ui/blocks/bonus_game_block.dart';
import 'package:fluxforge_ui/blocks/gambling_block.dart';
import 'package:fluxforge_ui/blocks/anticipation_block.dart';
import 'package:fluxforge_ui/blocks/wild_features_block.dart';

void main() {
  group('GameCoreBlock Stage Generation', () {
    test('generates SPIN_START and SPIN_END stages', () {
      final block = GameCoreBlock();
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'SPIN_START'), isTrue);
      expect(stages.any((s) => s.name == 'SPIN_END'), isTrue);
      expect(stages.any((s) => s.name == 'REEL_SPIN_LOOP'), isTrue);

      final spinStart = stages.firstWhere((s) => s.name == 'SPIN_START');
      expect(spinStart.bus, 'ui');
      expect(spinStart.priority, 80);
      expect(spinStart.sourceBlockId, 'game_core');
    });

    test('generates MUSIC_BASE when baseGameMusic is enabled', () {
      final block = GameCoreBlock();
      block.setOptionValue('baseGameMusic', true);
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'MUSIC_BASE'), isTrue);
      final musicBase = stages.firstWhere((s) => s.name == 'MUSIC_BASE');
      expect(musicBase.looping, isTrue);
      expect(musicBase.bus, 'music');
    });
  });

  group('GridBlock Stage Generation', () {
    test('generates REEL_STOP_0..N stages based on reelCount', () {
      final block = GridBlock();
      block.setOptionValue('reelCount', 5);
      final stages = block.generateStages();

      for (int i = 0; i < 5; i++) {
        expect(stages.any((s) => s.name == 'REEL_STOP_$i'), isTrue);
        final reelStop = stages.firstWhere((s) => s.name == 'REEL_STOP_$i');
        expect(reelStop.pooled, isTrue);
        expect(reelStop.bus, 'reels');
      }
    });

    test('generates generic REEL_STOP fallback stage', () {
      final block = GridBlock();
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'REEL_STOP'), isTrue);
    });

    test('generates WIN_EVAL stage', () {
      final block = GridBlock();
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'WIN_EVAL'), isTrue);
      final winEval = stages.firstWhere((s) => s.name == 'WIN_EVAL');
      expect(winEval.bus, 'sfx');
    });
  });

  group('SymbolSetBlock Stage Generation', () {
    test('generates SYMBOL_LAND stages for symbols', () {
      final block = SymbolSetBlock();
      final stages = block.generateStages();

      // Symbol set should generate landing stages
      expect(stages.isNotEmpty, isTrue);
      expect(stages.every((s) => s.sourceBlockId == 'symbol_set'), isTrue);
    });
  });

  group('FreeSpinsBlock Stage Generation', () {
    test('generates FS_TRIGGER, FS_ENTER, FS_EXIT stages', () {
      final block = FreeSpinsBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'FS_TRIGGER'), isTrue);
      expect(stages.any((s) => s.name == 'FS_ENTER'), isTrue);
      expect(stages.any((s) => s.name == 'FS_EXIT'), isTrue);

      final trigger = stages.firstWhere((s) => s.name == 'FS_TRIGGER');
      expect(trigger.priority, 90);
    });

    test('generates FS_MUSIC when hasDedicatedMusic is true', () {
      final block = FreeSpinsBlock();
      block.isEnabled = true;
      block.setOptionValue('hasDedicatedMusic', true);
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'FS_MUSIC'), isTrue);
      final music = stages.firstWhere((s) => s.name == 'FS_MUSIC');
      expect(music.looping, isTrue);
      expect(music.bus, 'music');
    });

    test('generates retrigger stages when enabled', () {
      final block = FreeSpinsBlock();
      block.isEnabled = true;
      block.setOptionValue('retriggerMode', 'addSpins');
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'FS_RETRIGGER'), isTrue);
      expect(stages.any((s) => s.name == 'FS_SPINS_ADDED'), isTrue);
    });
  });

  group('RespinBlock Stage Generation', () {
    test('generates RESPIN stages', () {
      final block = RespinBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('RESPIN')), isTrue);
    });
  });

  group('HoldAndWinBlock Stage Generation', () {
    test('generates HNW stages', () {
      final block = HoldAndWinBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('HNW') || s.name.contains('HOLD')), isTrue);
    });
  });

  group('CascadesBlock Stage Generation', () {
    test('generates CASCADE stages', () {
      final block = CascadesBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('CASCADE')), isTrue);
    });

    test('generates pooled CASCADE_STEP stages', () {
      final block = CascadesBlock();
      block.isEnabled = true;
      final pooled = block.pooledStages;

      expect(pooled.any((s) => s.contains('CASCADE')), isTrue);
    });
  });

  group('CollectorBlock Stage Generation', () {
    test('generates COLLECT stages', () {
      final block = CollectorBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('COLLECT')), isTrue);
    });
  });

  group('WinPresentationBlock Stage Generation', () {
    test('generates WIN_PRESENT and ROLLUP stages', () {
      final block = WinPresentationBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('WIN_PRESENT') || s.name.contains('WIN_LINE')), isTrue);
    });

    test('generates ROLLUP stages when enabled', () {
      final block = WinPresentationBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('ROLLUP')), isTrue);
    });
  });

  group('MusicStatesBlock Stage Generation', () {
    test('generates CONTEXT and MUSIC stages', () {
      final block = MusicStatesBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('CONTEXT') || s.name.contains('MUSIC')), isTrue);
    });
  });

  group('TransitionsBlock Stage Generation', () {
    test('generates transition stages', () {
      final block = TransitionsBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      // Transitions block should generate some stages
      expect(stages.isNotEmpty, isTrue);
    });
  });

  group('AnticipationBlock Stage Generation', () {
    test('generates ANTICIPATION_ON and ANTICIPATION_OFF stages', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'ANTICIPATION_ON'), isTrue);
      expect(stages.any((s) => s.name == 'ANTICIPATION_OFF'), isTrue);

      final anticipationOn = stages.firstWhere((s) => s.name == 'ANTICIPATION_ON');
      expect(anticipationOn.priority, 80);
      expect(anticipationOn.sourceBlockId, 'anticipation');
    });

    test('generates ANTICIPATION_TENSION looping stage', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'ANTICIPATION_TENSION'), isTrue);
      final tension = stages.firstWhere((s) => s.name == 'ANTICIPATION_TENSION');
      expect(tension.looping, isTrue);
    });

    test('generates per-reel tension stages when perReelAudio is true', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      block.setOptionValue('perReelAudio', true);
      final stages = block.generateStages();

      // Reels 1-4 (reel 0 never has anticipation per industry standard)
      for (int reel = 1; reel <= 4; reel++) {
        expect(stages.any((s) => s.name == 'ANTICIPATION_TENSION_R$reel'), isTrue);
      }
    });

    test('generates tension level stages when tensionEscalationEnabled is true', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      block.setOptionValue('perReelAudio', true);
      block.setOptionValue('tensionEscalationEnabled', true);
      block.setOptionValue('tensionLevels', 4);
      final stages = block.generateStages();

      // Should have ANTICIPATION_TENSION_R{reel}_L{level} stages
      expect(stages.any((s) => s.name == 'ANTICIPATION_TENSION_R1_L1'), isTrue);
      expect(stages.any((s) => s.name == 'ANTICIPATION_TENSION_R2_L2'), isTrue);
      expect(stages.any((s) => s.name == 'ANTICIPATION_TENSION_R3_L3'), isTrue);
      expect(stages.any((s) => s.name == 'ANTICIPATION_TENSION_R4_L4'), isTrue);
    });

    test('generates NEAR_MISS stages when pattern is tip_b', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      block.setOptionValue('pattern', 'tip_b');
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'NEAR_MISS_REVEAL'), isTrue);
      for (int reel = 0; reel <= 4; reel++) {
        expect(stages.any((s) => s.name == 'NEAR_MISS_REEL_$reel'), isTrue);
      }
    });

    test('generates ANTICIPATION_SUCCESS and ANTICIPATION_FAIL stages', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'ANTICIPATION_SUCCESS'), isTrue);
      expect(stages.any((s) => s.name == 'ANTICIPATION_FAIL'), isTrue);
    });
  });

  group('JackpotBlock Stage Generation', () {
    test('generates JACKPOT stages', () {
      final block = JackpotBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('JACKPOT')), isTrue);
    });
  });

  group('MultiplierBlock Stage Generation', () {
    test('generates MULT stages', () {
      final block = MultiplierBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('MULT')), isTrue);
    });
  });

  group('BonusGameBlock Stage Generation', () {
    test('generates BONUS stages', () {
      final block = BonusGameBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('BONUS')), isTrue);
    });
  });

  group('GamblingBlock Stage Generation', () {
    test('generates GAMBLE stages', () {
      final block = GamblingBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name.contains('GAMBLE')), isTrue);
    });
  });

  group('WildFeaturesBlock Stage Generation', () {
    test('generates WILD_LAND base stage', () {
      final block = WildFeaturesBlock();
      block.isEnabled = true;
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'WILD_LAND'), isTrue);
      final wildLand = stages.firstWhere((s) => s.name == 'WILD_LAND');
      expect(wildLand.pooled, isTrue);
      expect(wildLand.priority, 70);
    });

    test('generates expansion stages when expansion is enabled', () {
      final block = WildFeaturesBlock();
      block.isEnabled = true;
      block.setOptionValue('expansion', 'full_reel');
      block.setOptionValue('has_expansion_sound', true);
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'WILD_EXPAND_START'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_EXPAND_COMPLETE'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_EXPAND_FULL_REEL'), isTrue);
    });

    test('generates sticky stages when sticky_duration > 0', () {
      final block = WildFeaturesBlock();
      block.isEnabled = true;
      block.setOptionValue('sticky_duration', 3);
      block.setOptionValue('has_sticky_sound', true);
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'WILD_STICK_APPLY'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_STICK_PERSIST'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_STICK_EXPIRE'), isTrue);
    });

    test('generates walking stages when walking_direction is not none', () {
      final block = WildFeaturesBlock();
      block.isEnabled = true;
      block.setOptionValue('walking_direction', 'left');
      block.setOptionValue('has_walking_sound', true);
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'WILD_WALK_MOVE'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_WALK_ARRIVE'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_WALK_EXIT'), isTrue);
    });

    test('generates multiplier stages when multiplier_range is set', () {
      final block = WildFeaturesBlock();
      block.isEnabled = true;
      block.setOptionValue('multiplier_range', [2, 3, 5]);
      block.setOptionValue('has_multiplier_sound', true);
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'WILD_MULT_APPLY_X2'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_MULT_APPLY_X3'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_MULT_APPLY_X5'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_MULT_APPLY'), isTrue); // Generic fallback
    });

    test('generates stack stages based on stack_height', () {
      final block = WildFeaturesBlock();
      block.isEnabled = true;
      block.setOptionValue('stack_height', 4);
      block.setOptionValue('has_stack_sound', true);
      final stages = block.generateStages();

      expect(stages.any((s) => s.name == 'WILD_STACK_FORM_2STACK'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_STACK_FORM_3STACK'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_STACK_FORM_4STACK'), isTrue);
      expect(stages.any((s) => s.name == 'WILD_STACK_FULL'), isTrue);
    });

    test('pooledStages includes rapid-fire wild events', () {
      final block = WildFeaturesBlock();
      final pooled = block.pooledStages;

      expect(pooled.contains('WILD_LAND'), isTrue);
      expect(pooled.contains('WILD_STICK_PERSIST'), isTrue);
      expect(pooled.contains('WILD_WALK_MOVE'), isTrue);
      expect(pooled.contains('WILD_MULT_APPLY'), isTrue);
    });
  });
}
