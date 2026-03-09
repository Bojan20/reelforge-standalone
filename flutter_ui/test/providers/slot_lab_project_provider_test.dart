// SlotLabProjectProvider — Ultimate Unit Tests
//
// Tests for the central SlotLab project state manager:
// - Project metadata (name, dirty flag)
// - Symbol management (add, update, remove, reorder, presets)
// - Audio assignments (set, remove, undo/redo, bulk expand, clear)
// - Context management (add, update, remove, reorder)
// - Music layer assignments (assign, clear, reset)
// - GDD import integration
// - Win tier configuration (P5)
// - Session stats tracking
// - UI state persistence (expanded sections, groups, active tab)
// - Notification behavior (notifyListeners on state changes)
//
// NOTE: Does NOT test FFI-dependent methods (_syncWinTierConfigToRust)
// because NativeFFI is not available in test context.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/slot_lab_models.dart';
import 'package:fluxforge_ui/models/win_tier_config.dart';
import 'package:fluxforge_ui/providers/slot_lab_project_provider.dart';

void main() {
  late SlotLabProjectProvider provider;

  setUp(() {
    provider = SlotLabProjectProvider();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIAL STATE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Initial state', () {
    test('has default project name', () {
      expect(provider.projectName, 'Untitled Project');
    });

    test('is not dirty initially', () {
      expect(provider.isDirty, false);
    });

    test('has no project path', () {
      expect(provider.projectPath, isNull);
    });

    test('has default symbols from standard preset', () {
      expect(provider.symbols, isNotEmpty);
      expect(provider.symbols.length, greaterThanOrEqualTo(8));
    });

    test('has 3 default contexts', () {
      expect(provider.contexts.length, 3);
      expect(provider.contexts.any((c) => c.id == 'base'), true);
      expect(provider.contexts.any((c) => c.id == 'freespins'), true);
      expect(provider.contexts.any((c) => c.id == 'holdwin'), true);
    });

    test('has empty symbol audio', () {
      expect(provider.symbolAudio, isEmpty);
    });

    test('has empty music layers', () {
      expect(provider.musicLayers, isEmpty);
    });

    test('has default win configuration', () {
      expect(provider.winConfiguration, isNotNull);
      expect(provider.regularWinConfig.tiers, isNotEmpty);
      expect(provider.bigWinConfig.tiers, isNotEmpty);
    });

    test('has default expanded sections', () {
      expect(provider.expandedSections, isNotEmpty);
      expect(provider.expandedSections, contains('spins_reels'));
    });

    test('has no imported GDD', () {
      expect(provider.hasImportedGdd, false);
      expect(provider.importedGdd, isNull);
    });

    test('audio assignments are empty', () {
      expect(provider.audioAssignments, isEmpty);
    });

    test('session stats are zero', () {
      expect(provider.sessionStats.totalSpins, 0);
      expect(provider.sessionStats.totalBet, 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW PROJECT
  // ═══════════════════════════════════════════════════════════════════════════

  group('newProject', () {
    test('resets project name', () {
      provider.newProject('My Game');
      expect(provider.projectName, 'My Game');
    });

    test('clears dirty flag', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      expect(provider.isDirty, true);
      provider.newProject('Fresh');
      expect(provider.isDirty, false);
    });

    test('resets symbols to defaults', () {
      provider.addSymbol(const SymbolDefinition(
        id: 'custom1',
        name: 'Custom',
        emoji: '⚡',
        type: SymbolType.custom,
      ));
      final customCount = provider.symbols.length;

      provider.newProject('Fresh');
      expect(provider.symbols.length, lessThan(customCount));
    });

    test('clears audio assignments', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      provider.newProject('Fresh');
      expect(provider.audioAssignments, isEmpty);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.newProject('Test');
      expect(notifyCount, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO ASSIGNMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Audio assignments', () {
    test('setAudioAssignment stores assignment', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/audio/spin.wav');
      expect(provider.audioAssignments['UI_SPIN_PRESS'], '/audio/spin.wav');
    });

    test('setAudioAssignment marks dirty', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      expect(provider.isDirty, true);
    });

    test('hasAudioAssignment returns true for assigned stage', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      expect(provider.hasAudioAssignment('UI_SPIN_PRESS'), true);
      expect(provider.hasAudioAssignment('NONEXISTENT'), false);
    });

    test('removeAudioAssignment removes assignment', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      provider.removeAudioAssignment('UI_SPIN_PRESS');
      expect(provider.hasAudioAssignment('UI_SPIN_PRESS'), false);
    });

    test('audioAssignments map is unmodifiable', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      expect(
        () => provider.audioAssignments['X'] = 'Y',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('overwriting assignment replaces old value', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/old.wav');
      provider.setAudioAssignment('UI_SPIN_PRESS', '/new.wav');
      expect(provider.audioAssignments['UI_SPIN_PRESS'], '/new.wav');
    });

    test('clearAllAudioAssignments removes all', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      provider.setAudioAssignment('REEL_STOP', '/b.wav');
      provider.clearAllAudioAssignments();
      expect(provider.audioAssignments, isEmpty);
    });

    test('setAudioAssignments bulk replaces', () {
      provider.setAudioAssignments({
        'UI_SPIN_PRESS': '/a.wav',
        'REEL_STOP': '/b.wav',
      });
      expect(provider.audioAssignments.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO AUDIO ASSIGNMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Audio assignment undo/redo', () {
    test('canUndoAudioAssignment is false initially', () {
      expect(provider.canUndoAudioAssignment, false);
    });

    test('undo after set restores previous state', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      expect(provider.canUndoAudioAssignment, true);

      provider.undoAudioAssignment();
      expect(provider.hasAudioAssignment('UI_SPIN_PRESS'), false);
    });

    test('redo after undo restores assignment', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      provider.undoAudioAssignment();
      expect(provider.canRedoAudioAssignment, true);

      provider.redoAudioAssignment();
      expect(provider.audioAssignments['UI_SPIN_PRESS'], '/a.wav');
    });

    test('new action clears redo stack', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      provider.undoAudioAssignment();
      expect(provider.canRedoAudioAssignment, true);

      provider.setAudioAssignment('REEL_STOP', '/b.wav');
      expect(provider.canRedoAudioAssignment, false);
    });

    test('undo after remove restores assignment', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      provider.removeAudioAssignment('UI_SPIN_PRESS');
      expect(provider.hasAudioAssignment('UI_SPIN_PRESS'), false);

      provider.undoAudioAssignment();
      expect(provider.audioAssignments['UI_SPIN_PRESS'], '/a.wav');
    });

    test('undo after clearAll restores all assignments', () {
      provider.setAudioAssignment('UI_SPIN_PRESS', '/a.wav');
      provider.setAudioAssignment('REEL_STOP', '/b.wav');
      provider.clearAllAudioAssignments();

      provider.undoAudioAssignment();
      expect(provider.audioAssignments.length, 2);
    });

    test('recordUndo: false skips undo recording', () {
      provider.setAudioAssignment('X', '/x.wav', recordUndo: false);
      expect(provider.canUndoAudioAssignment, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BULK EXPAND
  // ═══════════════════════════════════════════════════════════════════════════

  group('Bulk expand', () {
    test('canBulkExpand returns true for expandable stages', () {
      expect(provider.canBulkExpand('REEL_STOP'), true);
    });

    test('canBulkExpand returns false for non-expandable stages', () {
      expect(provider.canBulkExpand('UI_SPIN_PRESS'), false);
    });

    test('getBulkExpandCount returns correct count', () {
      expect(provider.getBulkExpandCount('REEL_STOP'), greaterThanOrEqualTo(5));
    });

    test('bulkAssignToSimilarStages creates per-index assignments', () {
      final stages = provider.bulkAssignToSimilarStages(
        'REEL_STOP',
        '/audio/reel_stop.wav',
        count: 5,
        autoPan: true,
      );

      // Should create REEL_STOP_0 through REEL_STOP_4
      expect(stages.length, 5);
      expect(provider.hasAudioAssignment('REEL_STOP_0'), true);
      expect(provider.hasAudioAssignment('REEL_STOP_4'), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // UI STATE (SECTIONS, GROUPS, TABS)
  // ═══════════════════════════════════════════════════════════════════════════

  group('UI state management', () {
    test('setSectionExpanded adds section', () {
      provider.setSectionExpanded('my_section', true);
      expect(provider.isSectionExpanded('my_section'), true);
    });

    test('setSectionExpanded removes section', () {
      provider.setSectionExpanded('spins_reels', false);
      expect(provider.isSectionExpanded('spins_reels'), false);
    });

    test('toggleSection toggles state', () {
      final initial = provider.isSectionExpanded('spins_reels');
      provider.toggleSection('spins_reels');
      expect(provider.isSectionExpanded('spins_reels'), !initial);
    });

    test('setGroupExpanded adds group', () {
      provider.setGroupExpanded('my_group', true);
      expect(provider.isGroupExpanded('my_group'), true);
    });

    test('toggleGroup toggles state', () {
      final initial = provider.isGroupExpanded('spins_reels_spin_controls');
      provider.toggleGroup('spins_reels_spin_controls');
      expect(provider.isGroupExpanded('spins_reels_spin_controls'), !initial);
    });

    test('setLastActiveTab stores and retrieves', () {
      provider.setLastActiveTab('events');
      expect(provider.lastActiveTab, 'events');
    });

    test('expandedSections set is unmodifiable', () {
      expect(
        () => provider.expandedSections.add('x'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('setExpandedSections replaces all', () {
      provider.setExpandedSections({'a', 'b'});
      expect(provider.expandedSections, {'a', 'b'});
    });

    test('setExpandedGroups replaces all', () {
      provider.setExpandedGroups({'g1', 'g2'});
      expect(provider.expandedGroups, {'g1', 'g2'});
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  group('Symbol management', () {
    test('addSymbol adds to list', () {
      final before = provider.symbols.length;
      provider.addSymbol(const SymbolDefinition(
        id: 'custom1',
        name: 'Custom',
        emoji: '⚡',
        type: SymbolType.custom,
      ));
      expect(provider.symbols.length, before + 1);
    });

    test('addSymbol marks dirty', () {
      provider.addSymbol(const SymbolDefinition(
        id: 'custom1',
        name: 'Custom',
        emoji: '⚡',
        type: SymbolType.custom,
      ));
      expect(provider.isDirty, true);
    });

    test('updateSymbol replaces matching id', () {
      final firstId = provider.symbols.first.id;
      provider.updateSymbol(
        firstId,
        provider.symbols.first.copyWith(name: 'Updated Name'),
      );
      expect(provider.symbols.first.name, 'Updated Name');
    });

    test('removeSymbol removes by id', () {
      final firstId = provider.symbols.first.id;
      final before = provider.symbols.length;
      provider.removeSymbol(firstId);
      expect(provider.symbols.length, before - 1);
      expect(provider.symbols.any((s) => s.id == firstId), false);
    });

    test('reorderSymbols swaps positions', () {
      final ids = provider.symbols.map((s) => s.id).toList();
      provider.reorderSymbols(0, 2);
      final newIds = provider.symbols.map((s) => s.id).toList();
      // First symbol should now be at position 1 (moved forward)
      expect(newIds[1], ids[0]);
    });

    test('applyPreset replaces symbols', () {
      final megawaysPreset = SymbolPreset.builtInPresets.firstWhere(
        (p) => p.type == SymbolPresetType.megaways,
      );
      provider.applyPreset(megawaysPreset);
      expect(provider.symbols.length, megawaysPreset.symbols.length);
    });

    test('applyPreset with clearAudio removes symbol audio', () {
      provider.assignSymbolAudio('hp1', 'land', '/a.wav');
      expect(provider.symbolAudio, isNotEmpty);

      final preset = SymbolPreset.builtInPresets.first;
      provider.applyPreset(preset, clearAudio: true);
      expect(provider.symbolAudio, isEmpty);
    });

    test('allSymbolStageIds returns stages for all symbols', () {
      final stages = provider.allSymbolStageIds;
      expect(stages, isNotEmpty);
      // Should contain at least *_LAND and *_WIN stages
      expect(stages.any((s) => s.endsWith('_LAND')), true);
      expect(stages.any((s) => s.endsWith('_WIN')), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL AUDIO ASSIGNMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Symbol audio assignments', () {
    test('assignSymbolAudio creates assignment', () {
      provider.assignSymbolAudio('hp1', 'land', '/audio/hp1_land.wav');
      expect(provider.symbolAudio, isNotEmpty);
      expect(provider.symbolAudio.first.symbolId, 'hp1');
      expect(provider.symbolAudio.first.context, 'land');
    });

    test('assignSymbolAudio with volume and pan', () {
      provider.assignSymbolAudio(
        'hp1',
        'win',
        '/audio/hp1_win.wav',
        volume: 0.8,
        pan: -0.5,
      );
      expect(provider.symbolAudio.first.volume, 0.8);
      expect(provider.symbolAudio.first.pan, -0.5);
    });

    test('assignSymbolAudio replaces existing for same symbol+context', () {
      provider.assignSymbolAudio('hp1', 'land', '/old.wav');
      provider.assignSymbolAudio('hp1', 'land', '/new.wav');
      final matches = provider.symbolAudio
          .where((a) => a.symbolId == 'hp1' && a.context == 'land');
      expect(matches.length, 1);
      expect(matches.first.audioPath, '/new.wav');
    });

    test('clearSymbolAudio removes specific assignment', () {
      provider.assignSymbolAudio('hp1', 'land', '/a.wav');
      provider.assignSymbolAudio('hp1', 'win', '/b.wav');
      provider.clearSymbolAudio('hp1', 'land');

      expect(
        provider.symbolAudio.any((a) => a.context == 'land'),
        false,
      );
      expect(
        provider.symbolAudio.any((a) => a.context == 'win'),
        true,
      );
    });

    test('resetSymbolAudioForSymbol clears all contexts for symbol', () {
      provider.assignSymbolAudio('hp1', 'land', '/a.wav');
      provider.assignSymbolAudio('hp1', 'win', '/b.wav');
      provider.assignSymbolAudio('hp2', 'land', '/c.wav');

      provider.resetSymbolAudioForSymbol('hp1');

      expect(
        provider.symbolAudio.any((a) => a.symbolId == 'hp1'),
        false,
      );
      expect(
        provider.symbolAudio.any((a) => a.symbolId == 'hp2'),
        true,
      );
    });

    test('resetAllSymbolAudio clears everything', () {
      provider.assignSymbolAudio('hp1', 'land', '/a.wav');
      provider.assignSymbolAudio('hp2', 'win', '/b.wav');
      provider.resetAllSymbolAudio();
      expect(provider.symbolAudio, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTEXT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  group('Context management', () {
    test('addContext adds to list', () {
      final before = provider.contexts.length;
      provider.addContext(const ContextDefinition(
        id: 'bonus',
        displayName: 'Bonus',
        icon: '🎲',
        type: ContextType.bonus,
      ));
      expect(provider.contexts.length, before + 1);
    });

    test('updateContext replaces matching id', () {
      provider.updateContext(
        'base',
        ContextDefinition.base().copyWith(displayName: 'Updated Base'),
      );
      final base = provider.contexts.firstWhere((c) => c.id == 'base');
      expect(base.displayName, 'Updated Base');
    });

    test('removeContext removes by id', () {
      provider.removeContext('holdwin');
      expect(provider.contexts.any((c) => c.id == 'holdwin'), false);
    });

    test('reorderContexts swaps positions', () {
      final ids = provider.contexts.map((c) => c.id).toList();
      provider.reorderContexts(0, 2);
      final newIds = provider.contexts.map((c) => c.id).toList();
      expect(newIds[1], ids[0]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC LAYER ASSIGNMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Music layer assignments', () {
    test('assignMusicLayer creates assignment', () {
      provider.assignMusicLayer('base', 1, '/audio/base_l1.wav');
      expect(provider.musicLayers, isNotEmpty);
      expect(provider.musicLayers.first.contextId, 'base');
      expect(provider.musicLayers.first.layer, 1);
    });

    test('assignMusicLayer replaces existing for same context+layer', () {
      provider.assignMusicLayer('base', 1, '/old.wav');
      provider.assignMusicLayer('base', 1, '/new.wav');
      final matches = provider.musicLayers
          .where((m) => m.contextId == 'base' && m.layer == 1);
      expect(matches.length, 1);
      expect(matches.first.audioPath, '/new.wav');
    });

    test('clearMusicLayer removes specific layer', () {
      provider.assignMusicLayer('base', 1, '/a.wav');
      provider.assignMusicLayer('base', 2, '/b.wav');
      provider.clearMusicLayer('base', 1);

      expect(
        provider.musicLayers.any((m) => m.layer == 1),
        false,
      );
      expect(
        provider.musicLayers.any((m) => m.layer == 2),
        true,
      );
    });

    test('resetMusicLayersForContext clears all layers for context', () {
      provider.assignMusicLayer('base', 1, '/a.wav');
      provider.assignMusicLayer('base', 2, '/b.wav');
      provider.assignMusicLayer('freespins', 1, '/c.wav');

      provider.resetMusicLayersForContext('base');

      expect(
        provider.musicLayers.any((m) => m.contextId == 'base'),
        false,
      );
      expect(
        provider.musicLayers.any((m) => m.contextId == 'freespins'),
        true,
      );
    });

    test('resetAllMusicLayers clears everything', () {
      provider.assignMusicLayer('base', 1, '/a.wav');
      provider.assignMusicLayer('freespins', 1, '/b.wav');
      provider.resetAllMusicLayers();
      expect(provider.musicLayers, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN TIER CONFIGURATION (P5)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Win tier configuration', () {
    test('default config has regular and big win tiers', () {
      expect(provider.regularWinConfig.tiers, isNotEmpty);
      expect(provider.bigWinConfig.tiers, isNotEmpty);
    });

    test('applyWinTierPreset replaces configuration', () {
      final preset = SlotWinConfigurationPresets.highVolatility;
      provider.applyWinTierPreset(preset);
      expect(
        provider.winConfiguration.bigWins.threshold,
        preset.bigWins.threshold,
      );
    });

    test('setBigWinThreshold updates threshold', () {
      provider.setBigWinThreshold(30.0);
      expect(provider.bigWinConfig.threshold, 30.0);
    });

    test('allWinTierStages returns non-empty list', () {
      expect(provider.allWinTierStages, isNotEmpty);
    });

    test('regularWinStages contains WIN_ prefixed stages', () {
      for (final stage in provider.regularWinStages) {
        expect(stage.startsWith('WIN_'), true,
            reason: 'Regular stage "$stage" should start with WIN_');
      }
    });

    test('bigWinStages contains BIG_WIN_ prefixed stages', () {
      for (final stage in provider.bigWinStages) {
        expect(stage.startsWith('BIG_WIN_'), true,
            reason: 'Big win stage "$stage" should start with BIG_WIN_');
      }
    });

    test('resetWinConfiguration restores defaults', () {
      provider.setBigWinThreshold(999.0);
      provider.resetWinConfiguration();
      expect(
        provider.bigWinConfig.threshold,
        SlotWinConfiguration.defaultConfig().bigWins.threshold,
      );
    });

    test('exportWinConfigurationJson returns valid JSON', () {
      final json = provider.exportWinConfigurationJson();
      expect(json, isNotEmpty);
      expect(json, contains('regularWins'));
      expect(json, contains('bigWins'));
    });

    test('validateWinConfiguration returns true for valid config', () {
      expect(provider.validateWinConfiguration(), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION STATS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Session stats', () {
    test('recordSpinResult increments spin count', () {
      provider.recordSpinResult(betAmount: 1.0, winAmount: 0.0);
      expect(provider.sessionStats.totalSpins, 1);
    });

    test('recordSpinResult accumulates bet and win', () {
      provider.recordSpinResult(betAmount: 2.0, winAmount: 5.0);
      provider.recordSpinResult(betAmount: 2.0, winAmount: 0.0);
      expect(provider.sessionStats.totalBet, 4.0);
      expect(provider.sessionStats.totalWin, 5.0);
    });

    test('recordWin adds to recent wins', () {
      provider.recordWin(100.0, 'BIG');
      expect(provider.recentWins.length, 1);
      expect(provider.recentWins.first.amount, 100.0);
    });

    test('recent wins limited to 100', () {
      for (int i = 0; i < 110; i++) {
        provider.recordWin(1.0, 'SMALL');
      }
      expect(provider.recentWins.length, lessThanOrEqualTo(100));
    });

    test('resetSessionStats clears all', () {
      provider.recordSpinResult(betAmount: 1.0, winAmount: 5.0);
      provider.recordWin(5.0, 'BIG');
      provider.resetSessionStats();
      expect(provider.sessionStats.totalSpins, 0);
      expect(provider.recentWins, isEmpty);
    });

    test('recentWins list is unmodifiable', () {
      expect(
        () => provider.recentWins.add(SessionWin(
          amount: 1.0,
          tier: 'test',
          time: DateTime.now(),
        )),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // UI STATE PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  group('UI state persistence', () {
    test('setSelectedEventId stores and retrieves', () {
      provider.setSelectedEventId('evt_123');
      expect(provider.selectedEventId, 'evt_123');
    });

    test('setSelectedEventId with null clears', () {
      provider.setSelectedEventId('evt_123');
      provider.setSelectedEventId(null);
      expect(provider.selectedEventId, isNull);
    });

    test('setLowerZoneHeight stores value', () {
      provider.setLowerZoneHeight(350.0);
      expect(provider.lowerZoneHeight, 350.0);
    });

    test('setAudioBrowserDirectory stores value', () {
      provider.setAudioBrowserDirectory('/path/to/audio');
      expect(provider.audioBrowserDirectory, '/path/to/audio');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NOTIFICATION BEHAVIOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('Notification behavior', () {
    test('setAudioAssignment notifies listeners', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.setAudioAssignment('X', '/x.wav');
      expect(count, 1);
    });

    test('removeAudioAssignment notifies listeners', () {
      provider.setAudioAssignment('X', '/x.wav');
      int count = 0;
      provider.addListener(() => count++);
      provider.removeAudioAssignment('X');
      expect(count, 1);
    });

    test('addSymbol notifies listeners', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.addSymbol(const SymbolDefinition(
        id: 'test_notify',
        name: 'Test',
        emoji: '?',
        type: SymbolType.custom,
      ));
      expect(count, 1);
    });

    test('assignSymbolAudio notifies listeners', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.assignSymbolAudio('hp1', 'land', '/a.wav');
      expect(count, 1);
    });

    test('setSectionExpanded notifies listeners', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.setSectionExpanded('test_section', true);
      expect(count, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT NOTES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Project notes', () {
    test('setProjectNotes stores and retrieves', () {
      provider.setProjectNotes('My notes here');
      expect(provider.projectNotes, 'My notes here');
    });

    test('initially empty', () {
      expect(provider.projectNotes, isEmpty);
    });
  });
}
