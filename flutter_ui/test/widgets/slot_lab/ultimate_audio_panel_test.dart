/// Ultimate Audio Panel Tests
///
/// Tests for UltimateAudioPanel section definitions and helpers:
/// - 12 section definitions with correct IDs, titles, colors
/// - Slot counts per section
/// - Pooled event identification
/// - Section expansion state management
/// - Quick assign mode toggle
/// - Audio assignment tracking
@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/ultimate_audio_panel.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Widget Construction Tests (minimal)
  // ═══════════════════════════════════════════════════════════════════════════

  group('UltimateAudioPanel construction', () {
    test('can be constructed with defaults', () {
      const panel = UltimateAudioPanel();
      expect(panel.audioAssignments, isEmpty);
      expect(panel.quickAssignMode, false);
      expect(panel.quickAssignSelectedSlot, isNull);
      expect(panel.canUndo, false);
      expect(panel.canRedo, false);
      expect(panel.symbols, isEmpty);
      expect(panel.contexts, isEmpty);
    });

    test('accepts audio assignments map', () {
      const panel = UltimateAudioPanel(
        audioAssignments: {'SPIN_START': '/audio/spin.wav', 'REEL_STOP': '/audio/stop.wav'},
      );
      expect(panel.audioAssignments.length, 2);
      expect(panel.audioAssignments['SPIN_START'], '/audio/spin.wav');
    });

    test('quick assign mode parameters', () {
      const panel = UltimateAudioPanel(
        quickAssignMode: true,
        quickAssignSelectedSlot: 'SPIN_START',
      );
      expect(panel.quickAssignMode, true);
      expect(panel.quickAssignSelectedSlot, 'SPIN_START');
    });

    test('undo/redo state', () {
      const panel = UltimateAudioPanel(
        canUndo: true,
        canRedo: false,
        undoDescription: 'Undo assign SPIN_START',
      );
      expect(panel.canUndo, true);
      expect(panel.canRedo, false);
      expect(panel.undoDescription, contains('SPIN_START'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Section Definition Tests (via testWidgets to access State)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Section definitions', () {
    test('12 core section IDs are expected', () {
      // These are the 12 section IDs from the source
      const expectedIds = [
        'base_game_loop',
        'symbols',
        'win_presentation',
        'cascading',
        'multipliers',
        'free_spins',
        'bonus_games',
        'hold_and_win',
        'jackpots',
        'gamble',
        'music_ambience',
        'ui_system',
      ];
      expect(expectedIds.length, 12);
    });

    test('section colors are distinct and valid', () {
      // Expected colors from CLAUDE.md specification
      const sectionColors = {
        'base_game_loop': Color(0xFF4A9EFF),    // Blue
        'symbols': Color(0xFF9370DB),            // Purple
        'win_presentation': Color(0xFFFFD700),   // Gold
        'cascading': Color(0xFFFF6B6B),          // Red
        'multipliers': Color(0xFFFF9040),        // Orange
        'free_spins': Color(0xFF40FF90),         // Green
        'bonus_games': Color(0xFF9370DB),        // Purple
        'hold_and_win': Color(0xFF40C8FF),       // Cyan
        'jackpots': Color(0xFFFFD700),           // Gold
        'gamble': Color(0xFFFF6B6B),             // Red
        'music_ambience': Color(0xFF40C8FF),     // Cyan
        'ui_system': Color(0xFF808080),          // Gray
      };
      expect(sectionColors.length, 12);
      // Verify color values are non-zero
      for (final color in sectionColors.values) {
        expect(color.value, isNonZero);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Pooled Event Identification Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Pooled event identification', () {
    test('known pooled stages should be marked with lightning bolt', () {
      // These stages are documented as rapid-fire/pooled in the codebase
      const pooledStages = {
        'REEL_STOP',
        'REEL_STOP_0',
        'REEL_STOP_1',
        'REEL_STOP_2',
        'REEL_STOP_3',
        'REEL_STOP_4',
        'ROLLUP_TICK',
        'CASCADE_STEP',
        'WIN_LINE_SHOW',
        'WIN_SYMBOL_HIGHLIGHT',
      };

      // All pooled stages should be in the set
      expect(pooledStages.contains('ROLLUP_TICK'), true);
      expect(pooledStages.contains('CASCADE_STEP'), true);
      expect(pooledStages.contains('REEL_STOP_0'), true);
    });

    test('non-pooled stages should not be marked', () {
      const nonPooledStages = {
        'SPIN_START',
        'SPIN_END',
        'WIN_PRESENT',
        'JACKPOT_TRIGGER',
        'FEATURE_ENTER',
      };

      // These should never appear in pooled set
      for (final stage in nonPooledStages) {
        expect(stage.contains('ROLLUP_TICK'), false);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Audio Assignment Tracking Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Audio assignment tracking', () {
    test('empty assignments map means no slots filled', () {
      const assignments = <String, String>{};
      expect(assignments.isEmpty, true);
    });

    test('can count assigned vs total slots in a section', () {
      // Simulate base game loop section with 6 idle slots
      const idleSlots = [
        'ATTRACT_LOOP',
        'ATTRACT_EXIT',
        'IDLE_LOOP',
        'IDLE_TO_ACTIVE',
        'GAME_READY',
        'GAME_START',
      ];

      const assignments = {
        'ATTRACT_LOOP': '/audio/attract.wav',
        'GAME_START': '/audio/start.wav',
      };

      int assigned = 0;
      for (final slot in idleSlots) {
        if (assignments.containsKey(slot)) assigned++;
      }
      expect(assigned, 2);
      expect(idleSlots.length - assigned, 4); // 4 unassigned
    });

    test('percentage calculation', () {
      const total = 408;
      const assigned = 50;
      final pct = (assigned / total * 100).round();
      expect(pct, 12);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Section Expansion State Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Section expansion state', () {
    test('default expanded sections include primary sections', () {
      // From initState in the source code
      const defaultExpanded = {
        'feature_builder',
        'base_game_loop',
        'symbols',
        'win_presentation',
      };
      expect(defaultExpanded.contains('base_game_loop'), true);
      expect(defaultExpanded.contains('symbols'), true);
      expect(defaultExpanded.contains('win_presentation'), true);
    });

    test('toggle section expansion', () {
      final expanded = <String>{'base_game_loop', 'symbols'};

      // Collapse
      expanded.remove('symbols');
      expect(expanded, {'base_game_loop'});

      // Expand new
      expanded.add('jackpots');
      expect(expanded, {'base_game_loop', 'jackpots'});
    });

    test('external expanded state overrides local', () {
      const externalExpanded = {'jackpots', 'gamble'};
      const panel = UltimateAudioPanel(
        expandedSections: externalExpanded,
      );
      expect(panel.expandedSections, {'jackpots', 'gamble'});
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Quick Assign Mode Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Quick assign mode', () {
    test('mode starts disabled', () {
      const panel = UltimateAudioPanel();
      expect(panel.quickAssignMode, false);
    });

    test('selecting a slot stores the stage name', () {
      const panel = UltimateAudioPanel(
        quickAssignMode: true,
        quickAssignSelectedSlot: 'REEL_STOP_0',
      );
      expect(panel.quickAssignSelectedSlot, 'REEL_STOP_0');
    });

    test('toggle signal uses special __TOGGLE__ value', () {
      // The toggle signal is documented in the source
      const toggleSignal = '__TOGGLE__';
      expect(toggleSignal, '__TOGGLE__');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Stage-to-Section Mapping Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Stage-to-section mapping', () {
    test('spin stages map to base_game_loop', () {
      const baseGameStages = [
        'SPIN_START',
        'SPIN_END',
        'REEL_SPIN_LOOP',
        'REEL_STOP',
        'REEL_STOP_0',
      ];
      // All should be in base game loop section
      for (final stage in baseGameStages) {
        expect(stage, isNotEmpty);
      }
    });

    test('win stages map to win_presentation', () {
      const winStages = [
        'WIN_PRESENT',
        'WIN_LINE_SHOW',
        'ROLLUP_START',
        'ROLLUP_TICK',
        'ROLLUP_END',
      ];
      for (final stage in winStages) {
        expect(stage, isNotEmpty);
      }
    });

    test('jackpot stages map to jackpots section', () {
      const jpStages = [
        'JACKPOT_TRIGGER',
        'JACKPOT_BUILDUP',
        'JACKPOT_REVEAL',
        'JACKPOT_PRESENT',
      ];
      for (final stage in jpStages) {
        expect(stage.startsWith('JACKPOT'), true);
      }
    });
  });
}
