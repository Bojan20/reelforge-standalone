/// SlotLab Project Provider
///
/// V6 Layout state management for:
/// - Symbol definitions and audio assignments
/// - Context definitions and music layer assignments
/// - Project persistence (save/load)
/// - GDD import integration

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/slot_audio_events.dart';
import '../models/slot_lab_models.dart';
import '../models/win_tier_config.dart';
import '../providers/ale_provider.dart';
import '../providers/git_provider.dart';
import '../services/gdd_import_service.dart';
import '../services/stage_configuration_service.dart';
import '../src/rust/native_ffi.dart';
import 'package:get_it/get_it.dart';
import '../services/event_registry.dart';
import 'middleware_provider.dart';
import 'slot_lab/feature_composer_provider.dart';
import 'subsystems/composite_event_system_provider.dart';

/// Provider for SlotLab V6 project state
class SlotLabProjectProvider extends ChangeNotifier {
  /// Constructor — initializes P5 win tier stages
  SlotLabProjectProvider() {
    // Register default win tier stages on construction
    _syncWinTierStages();
  }

  // Project metadata
  String _projectName = 'Untitled Project';
  bool _isDirty = false;
  String? _projectPath;

  /// Signal: auto-bind folder ready for pool sync + splash reload.
  /// Static ValueNotifier — completely independent from ChangeNotifier cascade.
  /// UltimateAudioPanel sets it on OK press, SlotLabScreen listens and consumes.
  static final autoBindReadySignal = ValueNotifier<String?>(null);

  // Symbols
  List<SymbolDefinition> _symbols = List.from(defaultSymbols);
  List<SymbolAudioAssignment> _symbolAudio = [];

  // Contexts (game chapters)
  List<ContextDefinition> _contexts = [
    ContextDefinition.base(),
    ContextDefinition.freeSpins(),
    ContextDefinition.holdWin(),
  ];
  List<MusicLayerAssignment> _musicLayers = [];

  // ==========================================================================
  // ULTIMATE AUDIO PANEL STATE (V7)
  // ==========================================================================

  /// Audio assignments: stage → audioPath
  /// Used by UltimateAudioPanel for drag-drop audio assignments
  Map<String, String> _audioAssignments = {};

  /// Expanded sections in UltimateAudioPanel
  Set<String> _expandedSections = {'spins_reels', 'symbols', 'wins'};

  /// Expanded groups within sections
  Set<String> _expandedGroups = {
    'spins_reels_spin_controls',
    'spins_reels_reel_stops',
    'symbols_land',
    'symbols_win',
    'wins_tiers',
    'wins_lines',
  };

  /// Last active tab in lower zone (optional)
  String? _lastActiveTab;

  // Optional ALE integration
  AleProvider? _aleProvider;

  // ==========================================================================
  // UI STATE PERSISTENCE (SL-INT-P1.2, SL-INT-P1.4)
  // ==========================================================================

  /// Selected event ID (synced across panels)
  String? _selectedEventId;

  /// Lower Zone height
  double? _lowerZoneHeight;

  /// Audio browser current directory
  String? _audioBrowserDirectory;

  // ==========================================================================
  // GDD IMPORT STATE (V8)
  // ==========================================================================

  /// Imported Game Design Document (if any)
  GameDesignDocument? _importedGdd;

  /// Grid configuration from GDD
  GddGridConfig? _gridConfig;

  // ==========================================================================
  // WIN TIER CONFIGURATION (P5)
  // ==========================================================================

  /// Complete win tier configuration (regular + big wins)
  SlotWinConfiguration _winConfiguration = SlotWinConfiguration.defaultConfig();

  /// Flag to track if win config was imported from GDD
  bool _winConfigFromGdd = false;

  // ==========================================================================
  // SESSION STATS (Dashboard Integration)
  // ==========================================================================

  /// Session statistics for Dashboard
  SessionStats _sessionStats = const SessionStats();

  /// Recent wins history (max 100)
  List<SessionWin> _recentWins = [];

  // ==========================================================================
  // UNDO SUPPORT FOR AUDIO ASSIGNMENTS (P3 Recommendation)
  // ==========================================================================

  /// Undo stack for audio assignment operations
  final List<_AudioAssignmentUndoEntry> _audioUndoStack = [];

  /// Redo stack for audio assignment operations
  final List<_AudioAssignmentUndoEntry> _audioRedoStack = [];

  /// Maximum undo history size
  static const int _maxAudioUndoHistory = 50;

  // ==========================================================================
  // GETTERS
  // ==========================================================================

  String get projectName => _projectName;
  bool get isDirty => _isDirty;
  String? get projectPath => _projectPath;
  List<SymbolDefinition> get symbols => _symbols;
  List<ContextDefinition> get contexts => _contexts;
  List<SymbolAudioAssignment> get symbolAudio => _symbolAudio;
  List<MusicLayerAssignment> get musicLayers => _musicLayers;

  // UltimateAudioPanel state getters
  Map<String, String> get audioAssignments => Map.unmodifiable(_audioAssignments);
  Set<String> get expandedSections => Set.unmodifiable(_expandedSections);
  Set<String> get expandedGroups => Set.unmodifiable(_expandedGroups);
  String? get lastActiveTab => _lastActiveTab;

  // GDD state getters
  GameDesignDocument? get importedGdd => _importedGdd;
  GddGridConfig? get gridConfig => _gridConfig;
  bool get hasImportedGdd => _importedGdd != null;

  // Win Tier Configuration getters (P5)
  SlotWinConfiguration get winConfiguration => _winConfiguration;
  RegularWinTierConfig get regularWinConfig => _winConfiguration.regularWins;
  BigWinConfig get bigWinConfig => _winConfiguration.bigWins;
  bool get winConfigFromGdd => _winConfigFromGdd;

  /// Get all win tier stage names (for UltimateAudioPanel)
  List<String> get allWinTierStages => _winConfiguration.allStageNames;

  /// Get regular win tier stages only
  List<String> get regularWinStages =>
      _winConfiguration.regularWins.tiers.map((t) => t.stageName).toList();

  /// Get big win tier stages only
  List<String> get bigWinStages => [
    'BIG_WIN_START',
    ..._winConfiguration.bigWins.tiers.map((t) => t.stageName),
    'BIG_WIN_END',
  ];

  // UI state getters (SL-INT-P1.2, SL-INT-P1.4)
  String? get selectedEventId => _selectedEventId;
  double? get lowerZoneHeight => _lowerZoneHeight;
  String? get audioBrowserDirectory => _audioBrowserDirectory;

  /// Set selected event ID and notify listeners (SL-INT-P1.2)
  void setSelectedEventId(String? id) {
    if (_selectedEventId != id) {
      _selectedEventId = id;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Set lower zone height and notify listeners (SL-INT-P1.4)
  void setLowerZoneHeight(double? height) {
    if (_lowerZoneHeight != height) {
      _lowerZoneHeight = height;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Set audio browser directory and notify listeners (SL-INT-P1.4)
  void setAudioBrowserDirectory(String? dir) {
    if (_audioBrowserDirectory != dir) {
      _audioBrowserDirectory = dir;
      _isDirty = true;
      notifyListeners();
    }
  }

  /// Get complete project for serialization
  SlotLabProject get project {
    // V11: Read current config from FeatureComposerProvider
    SlotMachineConfig? machineConfig;
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      machineConfig = GetIt.instance<FeatureComposerProvider>().config;
    }
    return SlotLabProject(
        name: _projectName,
        symbols: _symbols,
        contexts: _contexts,
        symbolAudio: _symbolAudio,
        musicLayers: _musicLayers,
        // V7: Include audio panel state
        audioAssignments: _audioAssignments,
        expandedSections: _expandedSections,
        expandedGroups: _expandedGroups,
        lastActiveTab: _lastActiveTab,
        // V8: Include GDD data
        gridConfig: _gridConfig,
        importedGdd: _importedGdd,
        // V9: Include UI state (SL-INT-P1.2, P1.4)
        selectedEventId: _selectedEventId,
        lowerZoneHeight: _lowerZoneHeight,
        audioBrowserDirectory: _audioBrowserDirectory,
        // V11: Slot machine config
        slotMachineConfig: machineConfig,
        // V12: Audio persistence — composite events + EventRegistry
        compositeEventsJson: _snapshotCompositeEvents(),
        eventRegistryJson: _snapshotEventRegistry(),
      );
  }

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================

  /// Connect ALE provider for music layer sync
  void connectAle(AleProvider aleProvider) {
    _aleProvider = aleProvider;
  }

  /// Create new project with default content
  void newProject(String name) {
    _projectName = name;
    _projectPath = null;
    _symbols = List.from(defaultSymbols);
    _contexts = [
      ContextDefinition.base(),
      ContextDefinition.freeSpins(),
      ContextDefinition.holdWin(),
    ];
    _symbolAudio = [];
    _musicLayers = [];
    // Reset audio panel state
    _audioAssignments = {};
    _expandedSections = {'spins_reels', 'symbols', 'wins'};
    _expandedGroups = {
      'spins_reels_spin_controls',
      'spins_reels_reel_stops',
      'symbols_land',
      'symbols_win',
      'wins_tiers',
      'wins_lines',
    };
    _lastActiveTab = null;
    // V8: Reset GDD data
    _importedGdd = null;
    _gridConfig = null;
    // V11: Reset slot machine config (force wizard)
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      GetIt.instance<FeatureComposerProvider>().resetConfig();
    }
    // Clear EventRegistry — all audio events/stage mappings/playing voices
    try {
      EventRegistry.instance.clearAllEvents();
    } catch (e) {
      assert(() { debugPrint('EventRegistry clear error: $e'); return true; }());
    }
    // Clear Middleware events & composite events (DAW section sync)
    if (GetIt.instance.isRegistered<MiddlewareProvider>()) {
      GetIt.instance<MiddlewareProvider>().clearAllEvents();
    }
    _isDirty = false;
    _syncSymbolStages(); // Sync stages for default symbols
    notifyListeners();
  }

  // ==========================================================================
  // ULTIMATE AUDIO PANEL STATE MANAGEMENT
  // ==========================================================================

  /// Set audio assignment for a stage (with undo support)
  void setAudioAssignment(String stage, String audioPath, {bool recordUndo = true}) {
    if (recordUndo) {
      _pushAudioUndo(_AudioAssignmentUndoEntry(
        type: _AudioUndoType.set,
        stage: stage,
        previousPath: _audioAssignments[stage],
        newPath: audioPath,
        description: 'Assign audio to $stage',
      ));
    }
    _audioAssignments[stage] = audioPath;
    _markDirty();

    // Auto-create/update GAME_START composite when any base music layer is assigned
    if (stage.startsWith('MUSIC_BASE_L')) {
      _createBaseGameMusicComposite(_audioAssignments);
    }
  }

  /// Remove audio assignment for a stage (with undo support)
  void removeAudioAssignment(String stage, {bool recordUndo = true}) {
    final previousPath = _audioAssignments[stage];
    if (previousPath == null) return; // Nothing to remove

    if (recordUndo) {
      _pushAudioUndo(_AudioAssignmentUndoEntry(
        type: _AudioUndoType.remove,
        stage: stage,
        previousPath: previousPath,
        newPath: null,
        description: 'Remove audio from $stage',
      ));
    }
    _audioAssignments.remove(stage);
    _markDirty();

    // Rebuild GAME_START composite when a base music layer is removed
    if (stage.startsWith('MUSIC_BASE_L')) {
      _createBaseGameMusicComposite(_audioAssignments);
    }
  }

  /// Bulk assign audio to similar stages (P3 Recommendation #1)
  ///
  /// When a file is assigned to a generic stage like REEL_STOP, this method
  /// can auto-expand it to REEL_STOP_0..4 with appropriate stereo panning.
  ///
  /// Returns the list of stages that were assigned.
  List<String> bulkAssignToSimilarStages(String baseStage, String audioPath, {
    int count = 5,
    bool autoPan = true,
  }) {
    final assignedStages = <String>[];
    final undoEntries = <_AudioAssignmentUndoEntry>[];

    // Determine if this is an expandable stage
    final expandablePatterns = {
      'REEL_STOP': (int i) => 'REEL_STOP_$i',
      'REEL_LAND': (int i) => 'REEL_STOP_$i', // Alias
      'CASCADE_STEP': (int i) => 'CASCADE_STEP_$i',
      'WIN_LINE_SHOW': (int i) => 'WIN_LINE_SHOW_$i',
      'WIN_LINE_HIDE': (int i) => 'WIN_LINE_HIDE_$i',
      'SYMBOL_LAND': (int i) => 'SYMBOL_LAND_$i',
      'ROLLUP_TICK': (int i) => 'ROLLUP_TICK_$i',
    };

    String Function(int)? stageGenerator;
    for (final entry in expandablePatterns.entries) {
      if (baseStage.toUpperCase() == entry.key ||
          baseStage.toUpperCase().startsWith('${entry.key}_')) {
        stageGenerator = entry.value;
        break;
      }
    }

    if (stageGenerator == null) {
      // Not an expandable stage, just assign to the single stage
      setAudioAssignment(baseStage, audioPath);
      return [baseStage];
    }

    // Generate expanded stages
    for (int i = 0; i < count; i++) {
      final String stage = stageGenerator(i);
      final previousPath = _audioAssignments[stage];

      undoEntries.add(_AudioAssignmentUndoEntry(
        type: _AudioUndoType.set,
        stage: stage,
        previousPath: previousPath,
        newPath: audioPath,
        description: 'Bulk assign to $stage',
      ));

      _audioAssignments[stage] = audioPath;
      assignedStages.add(stage);
    }

    // Record as single bulk undo operation
    if (undoEntries.isNotEmpty) {
      _pushAudioUndo(_AudioAssignmentUndoEntry(
        type: _AudioUndoType.bulk,
        stage: baseStage,
        previousPath: null,
        newPath: audioPath,
        description: 'Bulk assign to ${assignedStages.length} stages',
        bulkEntries: undoEntries,
      ));
    }

    _markDirty();
    return assignedStages;
  }

  /// Check if a stage can be bulk-expanded
  bool canBulkExpand(String stage) {
    final expandablePatterns = [
      'REEL_STOP', 'REEL_LAND', 'CASCADE_STEP',
      'WIN_LINE_SHOW', 'WIN_LINE_HIDE', 'SYMBOL_LAND', 'ROLLUP_TICK',
    ];
    final upperStage = stage.toUpperCase();
    return expandablePatterns.any((p) => upperStage == p || upperStage.startsWith('${p}_'));
  }

  /// Get the number of stages that would be created by bulk expand
  int getBulkExpandCount(String stage, {int defaultCount = 5}) {
    // For REEL_STOP/REEL_LAND, use reel count from grid config if available
    if (stage.toUpperCase().contains('REEL')) {
      return _gridConfig?.columns ?? defaultCount;
    }
    return defaultCount;
  }

  // ==========================================================================
  // UNDO/REDO OPERATIONS
  // ==========================================================================

  /// Check if undo is available
  bool get canUndoAudioAssignment => _audioUndoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedoAudioAssignment => _audioRedoStack.isNotEmpty;

  /// Get undo description
  String? get undoAudioDescription =>
      _audioUndoStack.isNotEmpty ? _audioUndoStack.last.description : null;

  /// Get redo description
  String? get redoAudioDescription =>
      _audioRedoStack.isNotEmpty ? _audioRedoStack.last.description : null;

  /// Undo last audio assignment operation
  bool undoAudioAssignment() {
    if (_audioUndoStack.isEmpty) return false;

    final entry = _audioUndoStack.removeLast();
    _audioRedoStack.add(entry);

    // Apply undo
    if (entry.type == _AudioUndoType.bulk && entry.bulkEntries != null) {
      // Undo bulk operation (reverse order)
      for (final subEntry in entry.bulkEntries!.reversed) {
        if (subEntry.previousPath != null) {
          _audioAssignments[subEntry.stage] = subEntry.previousPath!;
        } else {
          _audioAssignments.remove(subEntry.stage);
        }
      }
    } else {
      // Single operation
      if (entry.previousPath != null) {
        _audioAssignments[entry.stage] = entry.previousPath!;
      } else {
        _audioAssignments.remove(entry.stage);
      }
    }

    _markDirty();
    return true;
  }

  /// Redo last undone audio assignment operation
  bool redoAudioAssignment() {
    if (_audioRedoStack.isEmpty) return false;

    final entry = _audioRedoStack.removeLast();
    _audioUndoStack.add(entry);

    // Apply redo
    if (entry.type == _AudioUndoType.bulk && entry.bulkEntries != null) {
      // Redo bulk operation
      for (final subEntry in entry.bulkEntries!) {
        if (subEntry.newPath != null) {
          _audioAssignments[subEntry.stage] = subEntry.newPath!;
        } else {
          _audioAssignments.remove(subEntry.stage);
        }
      }
    } else {
      // Single operation
      if (entry.newPath != null) {
        _audioAssignments[entry.stage] = entry.newPath!;
      } else {
        _audioAssignments.remove(entry.stage);
      }
    }

    _markDirty();
    return true;
  }

  /// Push entry to undo stack
  void _pushAudioUndo(_AudioAssignmentUndoEntry entry) {
    _audioUndoStack.add(entry);
    _audioRedoStack.clear(); // Clear redo on new action

    // Trim if exceeds max size
    while (_audioUndoStack.length > _maxAudioUndoHistory) {
      _audioUndoStack.removeAt(0);
    }
  }

  /// Clear all audio assignments (with optional undo support)
  void clearAllAudioAssignments({bool recordUndo = true}) {
    if (_audioAssignments.isEmpty) return;

    if (recordUndo) {
      // Record all current assignments for undo
      final entries = <_AudioAssignmentUndoEntry>[];
      for (final entry in _audioAssignments.entries) {
        entries.add(_AudioAssignmentUndoEntry(
          type: _AudioUndoType.remove,
          stage: entry.key,
          previousPath: entry.value,
          newPath: null,
          description: 'Clear ${entry.key}',
        ));
      }

      _pushAudioUndo(_AudioAssignmentUndoEntry(
        type: _AudioUndoType.bulk,
        stage: 'ALL',
        previousPath: null,
        newPath: null,
        description: 'Clear all audio assignments (${entries.length} stages)',
        bulkEntries: entries,
      ));
    }

    _audioAssignments.clear();
    _markDirty();
  }

  /// Auto-bind audio files from a folder to stages based on filename patterns.
  /// Returns record with bindings (stage→filePath) and unmapped file names.
  ({Map<String, String> bindings, List<String> unmapped}) autoBindFromFolder(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return (bindings: {}, unmapped: []);

    final files = dir.listSync()
        .whereType<File>()
        .where((f) => _isAudioFile(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final bindings = <String, String>{};
    final mappedPaths = <String>{};

    for (final file in files) {
      final name = file.uri.pathSegments.last.split('.').first.toLowerCase();
      // Strip numeric prefix (e.g., "004_" or "043_" or "048_")
      final stripped = name.replaceFirst(RegExp(r'^\d+_'), '');
      // Strip trailing variant number (e.g., "_2" or "_1")
      final base = stripped.replaceFirst(RegExp(r'_\d+$'), '');

      final stage = _resolveStageFromFilename(base, stripped);
      if (stage != null) {
        mappedPaths.add(file.path);
        // For variant stages (e.g., REEL_SPIN_LOOP with 3 variants),
        // only bind the first variant as the primary
        if (!bindings.containsKey(stage)) {
          bindings[stage] = file.path;
        }
      }
    }

    // Collect unmapped filenames
    final unmapped = files
        .where((f) => !mappedPaths.contains(f.path))
        .map((f) => f.uri.pathSegments.last)
        .toList();

    // WIN_PRESENT_LOW and WIN_PRESENT_EQUAL share the same sound
    if (bindings.containsKey('WIN_PRESENT_LOW') && !bindings.containsKey('WIN_PRESENT_EQUAL')) {
      bindings['WIN_PRESENT_EQUAL'] = bindings['WIN_PRESENT_LOW']!;
    }

    // Apply all bindings
    for (final entry in bindings.entries) {
      setAudioAssignment(entry.key, entry.value, recordUndo: false);
    }

    // ─── GAME_START composite: sync-start all base game music layers ───
    // All layers start simultaneously on GAME_START trigger.
    // L1 at full volume, L2/L3 at 0 — crossfade by adjusting layer volumes.
    _createBaseGameMusicComposite(bindings);

    if (bindings.isNotEmpty) {
      _markDirty();
    }

    return (bindings: bindings, unmapped: unmapped);
  }

  /// Create GAME_START composite event with synchronized base game music layers.
  /// L1 plays at full volume, L2/L3 start at volume 0 for crossfade readiness.
  void _createBaseGameMusicComposite(Map<String, String> bindings) {
    final l1Path = bindings['MUSIC_BASE_L1'];
    if (l1Path == null) return; // No base music, skip

    final sl = GetIt.instance;
    if (!sl.isRegistered<CompositeEventSystemProvider>()) return;
    final compositeProvider = sl<CompositeEventSystemProvider>();

    // Check if GAME_START composite already exists — update instead of duplicate
    final existing = compositeProvider.compositeEvents
        .where((e) => e.triggerStages.contains('GAME_START') && e.name == 'Base Game Music')
        .toList();
    for (final old in existing) {
      compositeProvider.deleteCompositeEvent(old.id);
    }

    // Build layers — all loop, all on music bus, sync-started
    // L1 at full volume, L2-L5 silent (crossfade-ready)
    final layers = <SlotEventLayer>[];
    final musicStages = ['MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_BASE_L3', 'MUSIC_BASE_L4', 'MUSIC_BASE_L5'];
    for (int i = 0; i < musicStages.length; i++) {
      final path = bindings[musicStages[i]];
      if (path == null) continue;
      layers.add(SlotEventLayer(
        id: 'game_start_l${i + 1}',
        name: 'Base L${i + 1}',
        audioPath: path,
        volume: i == 0 ? 1.0 : 0.0, // L1 = full, L2/L3 = silent
        loop: true,
        busId: SlotBusIds.music,
        actionType: 'Play',
      ));
    }

    if (layers.isEmpty) return;

    final now = DateTime.now();
    final event = SlotCompositeEvent(
      id: 'event_game_start_music_${now.millisecondsSinceEpoch}',
      name: 'Base Game Music',
      category: 'music',
      color: const Color(0xFF4CAF50),
      layers: layers,
      masterVolume: 1.0,
      targetBusId: SlotBusIds.music,
      looping: true,
      triggerStages: const ['GAME_START'],
      overlap: false,
      crossfadeMs: 500,
      createdAt: now,
      modifiedAt: now,
    );

    compositeProvider.addCompositeEvent(event, select: false);
  }

  static bool _isAudioFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return const {'wav', 'mp3', 'ogg', 'flac', 'aiff', 'aif'}.contains(ext);
  }

  static String? _resolveStageFromFilename(String base, String full) {
    // ─── REELS ───
    if (base == 'spins_loop_1of3' || base == 'spins_loop_2of3' || base == 'spins_loop_3of3') return 'REEL_SPIN_LOOP';
    if (base == 'spins_stop_1of5') return 'REEL_STOP_0';
    if (base == 'spins_stop_2of5') return 'REEL_STOP_1';
    if (base == 'spins_stop_3of5') return 'REEL_STOP_2';
    if (base == 'spins_stop_4of5') return 'REEL_STOP_3';
    if (base == 'spins_stop_5of5') return 'REEL_STOP_4';

    // ─── ANTICIPATION (sequential per-reel: short→R2, med→R3, long→R4) ───
    if (base == 'spins_susp_short') return 'ANTICIPATION_TENSION_R2';
    if (base == 'spins_susp_med') return 'ANTICIPATION_TENSION_R3';
    if (base == 'spins_susp_long') return 'ANTICIPATION_TENSION_R4';

    // ─── SYMBOLS — High Pay ───
    if (base == 'hp_sym_1' || full.startsWith('hp_sym_1')) return 'WIN_SYMBOL_HIGHLIGHT_HP1';
    if (base == 'hp_sym_2' || full.startsWith('hp_sym_2')) return 'WIN_SYMBOL_HIGHLIGHT_HP2';
    if (base == 'hp_sym_3' || full.startsWith('hp_sym_3')) return 'WIN_SYMBOL_HIGHLIGHT_HP3';
    if (base == 'hp_sym_4' || full.startsWith('hp_sym_4')) return 'WIN_SYMBOL_HIGHLIGHT_HP4';

    // ─── SYMBOLS — Medium Pay ───
    if (base == 'mp1' || full.startsWith('mp1')) return 'WIN_SYMBOL_HIGHLIGHT_MP1';
    if (base == 'mp2' || full.startsWith('mp2')) return 'WIN_SYMBOL_HIGHLIGHT_MP2';
    if (base == 'mp3' || full.startsWith('mp3')) return 'WIN_SYMBOL_HIGHLIGHT_MP3';
    if (base == 'mp4' || full.startsWith('mp4')) return 'WIN_SYMBOL_HIGHLIGHT_MP4';
    if (base == 'mp5' || full.startsWith('mp5')) return 'WIN_SYMBOL_HIGHLIGHT_MP5';

    // ─── SYMBOLS — Low Pay ───
    if (base == 'lp_sym_1of3' || full.startsWith('lp_sym_1of3')) return 'WIN_SYMBOL_HIGHLIGHT_LP1';
    if (base == 'lp_sym_2of3' || full.startsWith('lp_sym_2of3')) return 'WIN_SYMBOL_HIGHLIGHT_LP2';
    if (base == 'lp_sym_3of3' || full.startsWith('lp_sym_3of3')) return 'WIN_SYMBOL_HIGHLIGHT_LP3';

    // ─── WIN HIGHLIGHTS ───
    if (base == 'reel_highlight') return 'PAYLINE_HIGHLIGHT';
    // linewin = duplicate of reel_highlight, skip

    // ─── WINS (bet multiplier tiers) ───
    if (base == 'winlessthanequal') return 'WIN_PRESENT_LOW';
    if (base == 'win_2x') return 'WIN_PRESENT_1';
    if (base == 'win_3x') return 'WIN_PRESENT_2';
    if (base == 'win_4x') return 'WIN_PRESENT_3';
    if (base == 'win_5x') return 'WIN_PRESENT_4';
    if (base == 'win_6x') return 'WIN_PRESENT_5';
    // win_7x, win_8x = surplus, skip

    // ─── BIG WIN ───
    if (base == 'bw_alert') return 'BIG_WIN_TRIGGER';
    if (base == 'coin_loop') return 'BIG_WIN_TICK_START';
    if (base == 'coin_loop_end') return 'BIG_WIN_TICK_END';
    if (base == 'mus_bw') return 'BIG_WIN_START';
    if (base == 'mus_bw_end') return 'BIG_WIN_END';

    // ─── SCATTER / FREE SPINS ───
    if (base == 'scatter_land_1of5') return 'SCATTER_LAND_1';
    if (base == 'scatter_land_2of5') return 'SCATTER_LAND_2';
    if (base == 'scatter_land_3of5') return 'SCATTER_LAND_3';
    if (base == 'scatter_land_4of5') return 'SCATTER_LAND_4';
    if (base == 'scatter_land_5of5') return 'SCATTER_LAND_5';
    if (base == 'scatter_win') return 'SCATTER_WIN';
    if (base == 'panels_appear') return 'FS_HOLD_INTRO';
    if (base == 'trn_fs_intro') return 'CONTEXT_BASE_TO_FS';
    if (base == 'trn_fs_outro_panel') return 'FS_END';
    if (base == 'trn_return_to_base') return 'CONTEXT_FS_TO_BASE';
    if (base == 'mus_fs') return 'MUSIC_FS_L1';
    if (base == 'mus_fs_end') return 'MUSIC_FS_OUTRO';

    // ─── WILD ───
    if (base == 'wild_land' || base == 'wildland') return 'WILD_LAND';
    if (base == 'wild_expand' || base == 'wild_expand_start') return 'WILD_EXPAND_START';
    if (base == 'wild_expand_step') return 'WILD_EXPAND_STEP';
    if (base == 'wild_expand_end') return 'WILD_EXPAND_END';
    if (base == 'wild_stick' || base == 'wild_sticky') return 'WILD_STICK';
    if (base == 'wild_walk_left' || base == 'wild_walk_l') return 'WILD_WALK_LEFT';
    if (base == 'wild_walk_right' || base == 'wild_walk_r') return 'WILD_WALK_RIGHT';
    if (base == 'wild_transform') return 'WILD_TRANSFORM';
    if (base == 'wild_multiply' || base == 'wild_multiplier') return 'WILD_MULTIPLY';
    if (base == 'wild_nudge') return 'WILD_NUDGE';
    if (base == 'wild_stack') return 'WILD_STACK';
    if (base == 'wild_upgrade') return 'WILD_UPGRADE';

    // ─── UI ───
    if (base == 'ui_spin_button') return 'UI_SPIN_PRESS';
    if (base == 'ui_open') return 'UI_MENU_OPEN';
    if (base == 'ui_close') return 'UI_MENU_CLOSE';
    if (base == 'ui_interact_1of3' || base == 'ui_interact_2of3' || base == 'ui_interact_3of3') return 'UI_BUTTON_PRESS';

    // ─── MUSIC (base game layers — all on GAME_START composite) ───
    if (base == 'mus_bg_lvl_1') return 'MUSIC_BASE_L1';
    if (base == 'mus_bg_lvl_2') return 'MUSIC_BASE_L2';
    if (base == 'mus_bg_lvl_3') return 'MUSIC_BASE_L3';

    return null;
  }

  /// Get audio path for a stage (null if not assigned)
  String? getAudioAssignment(String stage) => _audioAssignments[stage];

  /// Check if stage has audio assigned
  bool hasAudioAssignment(String stage) => _audioAssignments.containsKey(stage);

  /// Set expanded state for a section
  void setSectionExpanded(String sectionId, bool expanded) {
    if (expanded) {
      _expandedSections.add(sectionId);
    } else {
      _expandedSections.remove(sectionId);
    }
    notifyListeners();
  }

  /// Toggle section expanded state
  /// NOTE: Does NOT call notifyListeners() — section expand/collapse is purely
  /// UI state handled by local setState in UltimateAudioPanel. The provider only
  /// persists the state for save/load. This prevents expensive full-panel rebuilds
  /// via Consumer of SlotLabProjectProvider when toggling sections.
  void toggleSection(String sectionId) {
    if (_expandedSections.contains(sectionId)) {
      _expandedSections.remove(sectionId);
    } else {
      _expandedSections.add(sectionId);
    }
    // No notifyListeners() — local setState in panel handles UI instantly
  }

  /// Check if section is expanded
  bool isSectionExpanded(String sectionId) => _expandedSections.contains(sectionId);

  /// Set expanded state for a group
  /// NOTE: No notifyListeners() — same as toggleSection, UI state only.
  void setGroupExpanded(String groupId, bool expanded) {
    if (expanded) {
      _expandedGroups.add(groupId);
    } else {
      _expandedGroups.remove(groupId);
    }
  }

  /// Toggle group expanded state
  /// NOTE: No notifyListeners() — same as toggleSection, UI state only.
  void toggleGroup(String groupId) {
    if (_expandedGroups.contains(groupId)) {
      _expandedGroups.remove(groupId);
    } else {
      _expandedGroups.add(groupId);
    }
  }

  /// Check if group is expanded
  bool isGroupExpanded(String groupId) => _expandedGroups.contains(groupId);

  /// Set last active tab
  void setLastActiveTab(String? tabId) {
    _lastActiveTab = tabId;
    notifyListeners();
  }

  /// Bulk update expanded sections (for restoring state)
  void setExpandedSections(Set<String> sections) {
    _expandedSections = Set.from(sections);
    notifyListeners();
  }

  /// Bulk update expanded groups (for restoring state)
  void setExpandedGroups(Set<String> groups) {
    _expandedGroups = Set.from(groups);
    notifyListeners();
  }

  /// Bulk update audio assignments (for restoring state)
  void setAudioAssignments(Map<String, String> assignments) {
    _audioAssignments = Map.from(assignments);
    _sanitizeNofMVariantAssignments(); // Clean false positives on bulk set
    _markDirty();
  }

  // ==========================================================================
  // GDD IMPORT MANAGEMENT (V8)
  // ==========================================================================

  /// Import GDD and store it in the project
  /// This method stores the full GDD for later reference and updates the grid config.
  void importGdd(GameDesignDocument gdd, {List<SymbolDefinition>? generatedSymbols}) {
    _importedGdd = gdd;
    _gridConfig = gdd.grid;
    _projectName = gdd.name;

    // Optionally replace symbols with generated ones from GDD
    if (generatedSymbols != null && generatedSymbols.isNotEmpty) {
      _symbols = List.from(generatedSymbols);
      _symbolAudio = []; // Clear audio assignments when replacing symbols
      _syncSymbolStages();
    }

    // P5: Convert GDD win tiers to SlotWinConfiguration
    if (gdd.math.winTiers.isNotEmpty) {
      final winConfig = convertGddWinTiersToP5(gdd.math);
      setWinConfigurationFromGdd(winConfig);
    }


    _markDirty();
  }

  /// Update grid configuration (can be called independently of full GDD import)
  void setGridConfig(GddGridConfig config) {
    _gridConfig = config;
    _markDirty();
  }

  /// Clear imported GDD data
  void clearGdd() {
    _importedGdd = null;
    _gridConfig = null;
    _markDirty();
  }

  /// Get GDD symbols (if GDD is imported)
  List<GddSymbol> get gddSymbols => _importedGdd?.symbols ?? [];

  /// Get GDD features (if GDD is imported)
  List<GddFeature> get gddFeatures => _importedGdd?.features ?? [];

  /// Get GDD math model (if GDD is imported)
  GddMathModel? get gddMath => _importedGdd?.math;

  // Session stats getters (Dashboard Integration)
  SessionStats get sessionStats => _sessionStats;
  List<SessionWin> get recentWins => List.unmodifiable(_recentWins);

  /// Record a spin result (updates session stats)
  void recordSpinResult({required double betAmount, required double winAmount, String? tier}) {
    _sessionStats = _sessionStats.copyWith(
      totalSpins: _sessionStats.totalSpins + 1,
      totalBet: _sessionStats.totalBet + betAmount,
      totalWin: _sessionStats.totalWin + winAmount,
    );

    if (winAmount > 0) {
      _recentWins.insert(0, SessionWin(
        amount: winAmount,
        tier: tier ?? 'WIN',
        time: DateTime.now(),
      ));
      // Keep max 100 wins
      if (_recentWins.length > 100) {
        _recentWins = _recentWins.sublist(0, 100);
      }
    }

    notifyListeners();
  }

  /// Record a standalone win (e.g., jackpot award, not from regular spin)
  void recordWin(double amount, String tier) {
    if (amount <= 0) return;

    _sessionStats = _sessionStats.copyWith(
      totalWin: _sessionStats.totalWin + amount,
    );

    _recentWins.insert(0, SessionWin(
      amount: amount,
      tier: tier,
      time: DateTime.now(),
    ));
    // Keep max 100 wins
    if (_recentWins.length > 100) {
      _recentWins = _recentWins.sublist(0, 100);
    }

    notifyListeners();
  }

  /// Reset session stats
  void resetSessionStats() {
    _sessionStats = const SessionStats();
    _recentWins = [];
    notifyListeners();
  }

  // ==========================================================================
  // SYMBOL PRESETS
  // ==========================================================================

  /// Apply a symbol preset, replacing all current symbols
  void applyPreset(SymbolPreset preset, {bool clearAudio = true}) {
    _symbols = List.from(preset.symbols);
    if (clearAudio) {
      _symbolAudio = [];
    }
    _syncSymbolStages(); // Sync stages for new preset symbols
    _markDirty();
  }

  /// Apply preset by ID
  void applyPresetById(String presetId, {bool clearAudio = true}) {
    final preset = SymbolPreset.getById(presetId);
    if (preset != null) {
      applyPreset(preset, clearAudio: clearAudio);
    }
  }

  /// Get all available presets
  List<SymbolPreset> get availablePresets => SymbolPreset.builtInPresets;

  /// Check if current symbols match a preset
  SymbolPresetType? get currentPresetType {
    for (final preset in SymbolPreset.builtInPresets) {
      if (_symbolsMatchPreset(preset)) {
        return preset.type;
      }
    }
    return null;
  }

  bool _symbolsMatchPreset(SymbolPreset preset) {
    if (_symbols.length != preset.symbols.length) return false;
    final currentIds = _symbols.map((s) => s.id).toSet();
    final presetIds = preset.symbols.map((s) => s.id).toSet();
    return currentIds.difference(presetIds).isEmpty;
  }

  /// Replace all symbols with a new list
  void replaceSymbols(List<SymbolDefinition> newSymbols, {bool clearAudio = true}) {
    _symbols = List.from(newSymbols);
    if (clearAudio) {
      _symbolAudio = [];
    }
    _syncSymbolStages(); // Sync stages for new symbols
    _markDirty();
  }

  /// Get symbols filtered by type
  List<SymbolDefinition> getSymbolsByType(SymbolType type) {
    return _symbols.where((s) => s.type == type).toList();
  }

  /// Get symbols sorted by value (highest first)
  List<SymbolDefinition> get symbolsSortedByValue {
    return sortSymbolsByValue(_symbols);
  }

  /// Get all stage IDs for current symbols
  List<String> get allSymbolStageIds => getAllSymbolStageIds(_symbols);

  /// Find symbol by ID
  SymbolDefinition? getSymbolById(String id) => findSymbolById(_symbols, id);

  // ==========================================================================
  // SYMBOL CRUD
  // ==========================================================================

  /// Add a new symbol
  void addSymbol(SymbolDefinition symbol) {
    _symbols = [..._symbols, symbol];
    _syncSymbolStages(); // Sync stages for new symbol
    _markDirty();
  }

  /// Update existing symbol
  void updateSymbol(String id, SymbolDefinition symbol) {
    final index = _symbols.indexWhere((s) => s.id == id);
    if (index != -1) {
      _symbols = [
        ..._symbols.sublist(0, index),
        symbol,
        ..._symbols.sublist(index + 1),
      ];
      _syncSymbolStages(); // Sync stages for updated symbol
      _markDirty();
    }
  }

  /// Update artwork path for a symbol
  void updateSymbolArtwork(String id, String? artworkPath) {
    final index = _symbols.indexWhere((s) => s.id == id);
    if (index != -1) {
      _symbols = [
        ..._symbols.sublist(0, index),
        _symbols[index].copyWith(artworkPath: artworkPath),
        ..._symbols.sublist(index + 1),
      ];
      _markDirty();
    }
  }

  /// Batch update multiple symbol artworks — single notifyListeners at end
  void updateSymbolArtworkBatch(Map<String, String> assignments) {
    var symbols = _symbols;
    for (final entry in assignments.entries) {
      final index = symbols.indexWhere((s) => s.id == entry.key);
      if (index != -1) {
        symbols = [
          ...symbols.sublist(0, index),
          symbols[index].copyWith(artworkPath: entry.value),
          ...symbols.sublist(index + 1),
        ];
      }
    }
    _symbols = symbols;
    _markDirty();
  }

  /// Remove symbol and its audio assignments
  void removeSymbol(String id) {
    _symbols = _symbols.where((s) => s.id != id).toList();
    _symbolAudio = _symbolAudio.where((a) => a.symbolId != id).toList();
    _syncSymbolStages(); // Sync stages after removal
    _markDirty();
  }

  /// Reorder symbols
  void reorderSymbols(int oldIndex, int newIndex) {
    final symbols = List<SymbolDefinition>.from(_symbols);
    final symbol = symbols.removeAt(oldIndex);
    symbols.insert(newIndex < oldIndex ? newIndex : newIndex - 1, symbol);
    _symbols = symbols;
    // Note: Reorder doesn't need stage sync - stages don't depend on order
    _markDirty();
  }

  // ==========================================================================
  // SYMBOL AUDIO ASSIGNMENTS
  // ==========================================================================

  /// Assign audio to symbol context slot
  void assignSymbolAudio(String symbolId, String context, String audioPath, {double volume = 1.0, double pan = 0.0}) {
    // Remove existing assignment
    _symbolAudio = _symbolAudio.where((a) => !(a.symbolId == symbolId && a.context == context)).toList();
    // Add new assignment
    _symbolAudio = [
      ..._symbolAudio,
      SymbolAudioAssignment(
        symbolId: symbolId,
        context: context,
        audioPath: audioPath,
        volume: volume,
        pan: pan,
      ),
    ];
    _markDirty();
  }

  /// Clear symbol audio assignment
  void clearSymbolAudio(String symbolId, String context) {
    _symbolAudio = _symbolAudio.where((a) => !(a.symbolId == symbolId && a.context == context)).toList();
    _markDirty();
  }

  /// Get audio assignment for symbol context
  SymbolAudioAssignment? getSymbolAudio(String symbolId, String context) {
    final matches = _symbolAudio.where((a) => a.symbolId == symbolId && a.context == context);
    return matches.isNotEmpty ? matches.first : null;
  }

  // ==========================================================================
  // CONTEXT CRUD
  // ==========================================================================

  /// Add a new context
  void addContext(ContextDefinition context) {
    _contexts = [..._contexts, context];
    _markDirty();
    // Sync to ALE if connected
    _syncContextToAle(context);
  }

  /// Update existing context
  void updateContext(String id, ContextDefinition context) {
    final index = _contexts.indexWhere((c) => c.id == id);
    if (index != -1) {
      _contexts = [
        ..._contexts.sublist(0, index),
        context,
        ..._contexts.sublist(index + 1),
      ];
      _markDirty();
    }
  }

  /// Remove context and its music layer assignments
  void removeContext(String id) {
    // Don't allow removing base context
    if (id == 'base') return;
    _contexts = _contexts.where((c) => c.id != id).toList();
    _musicLayers = _musicLayers.where((a) => a.contextId != id).toList();
    _markDirty();
  }

  /// Reorder contexts
  void reorderContexts(int oldIndex, int newIndex) {
    final contexts = List<ContextDefinition>.from(_contexts);
    final context = contexts.removeAt(oldIndex);
    contexts.insert(newIndex < oldIndex ? newIndex : newIndex - 1, context);
    _contexts = contexts;
    _markDirty();
  }

  // ==========================================================================
  // MUSIC LAYER ASSIGNMENTS
  // ==========================================================================

  /// Assign audio to music layer slot
  void assignMusicLayer(String contextId, int layer, String audioPath, {double volume = 1.0, bool loop = true}) {
    // Remove existing assignment
    _musicLayers = _musicLayers.where((a) => !(a.contextId == contextId && a.layer == layer)).toList();
    // Add new assignment
    final assignment = MusicLayerAssignment(
      contextId: contextId,
      layer: layer,
      audioPath: audioPath,
      volume: volume,
      loop: loop,
    );
    _musicLayers = [..._musicLayers, assignment];
    _markDirty();
    // Sync to ALE if connected
    _syncMusicLayerToAle(assignment);
  }

  /// Clear music layer assignment
  void clearMusicLayer(String contextId, int layer) {
    _musicLayers = _musicLayers.where((a) => !(a.contextId == contextId && a.layer == layer)).toList();
    _markDirty();
  }

  /// Get music layer assignment
  MusicLayerAssignment? getMusicLayer(String contextId, int layer) {
    final matches = _musicLayers.where((a) => a.contextId == contextId && a.layer == layer);
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Get all layers for a context
  List<MusicLayerAssignment> getContextLayers(String contextId) {
    return _musicLayers.where((a) => a.contextId == contextId).toList()
      ..sort((a, b) => a.layer.compareTo(b.layer));
  }

  // ==========================================================================
  // ALE INTEGRATION
  // ==========================================================================

  /// Sync context definition to ALE provider
  void _syncContextToAle(ContextDefinition context) {
    if (_aleProvider == null) return;

    // Build layer configuration for this context
    final contextLayers = getContextLayers(context.id);

    // Note: Full ALE integration would require generating a profile JSON
    // and loading it via AleProvider.loadProfile(). For now, we log the sync.
  }

  /// Sync music layer assignment to ALE provider
  void _syncMusicLayerToAle(MusicLayerAssignment assignment) {
    if (_aleProvider == null) return;


    // Note: Full ALE integration would require:
    // 1. Register audio path as ALE asset ID
    // 2. Update context layer in ALE profile
    // 3. Reload profile or hot-update layer
  }

  /// Generate ALE-compatible profile JSON for all contexts and layers
  Map<String, dynamic> generateAleProfile() {
    final contextsJson = <String, dynamic>{};

    for (final context in _contexts) {
      final layersList = <Map<String, dynamic>>[];
      final layers = getContextLayers(context.id);

      for (int i = 0; i < context.layerCount; i++) {
        final layer = layers.firstWhere(
          (l) => l.layer == i + 1,
          orElse: () => MusicLayerAssignment(
            contextId: context.id,
            layer: i + 1,
            audioPath: '',
          ),
        );
        layersList.add({
          'index': i,
          'asset_id': layer.audioPath.isNotEmpty
              ? 'slotlab_${context.id}_L${i + 1}'
              : '',
          'audio_path': layer.audioPath,
          'base_volume': layer.volume,
          'loop': layer.loop,
        });
      }

      contextsJson[context.id] = {
        'id': context.id,
        'name': context.displayName,
        'type': context.type.name,
        'layers': layersList,
      };
    }

    return {
      'game_name': _projectName,
      'version': '1.0',
      'contexts': contextsJson,
      'slotlab_source': true,
    };
  }

  /// Get all layer audio paths for a context (for playback)
  Map<int, String> getContextAudioPaths(String contextId) {
    final result = <int, String>{};
    for (final layer in getContextLayers(contextId)) {
      if (layer.audioPath.isNotEmpty) {
        result[layer.layer] = layer.audioPath;
      }
    }
    return result;
  }

  // ==========================================================================
  // WIN TIER CONFIGURATION MANAGEMENT (P5)
  // ==========================================================================

  /// Set complete win tier configuration
  void setWinConfiguration(SlotWinConfiguration config, {bool syncStages = true}) {
    _winConfiguration = config;
    _winConfigFromGdd = false;
    if (syncStages) _syncWinTierStages();
    _markDirty();
  }

  /// Set win configuration from GDD import
  void setWinConfigurationFromGdd(SlotWinConfiguration config) {
    _winConfiguration = config;
    _winConfigFromGdd = true;
    _syncWinTierStages();
    _markDirty();
  }

  /// Add a new regular win tier
  void addRegularWinTier(WinTierDefinition tier) {
    final currentTiers = List<WinTierDefinition>.from(_winConfiguration.regularWins.tiers);

    // Check for ID collision
    if (currentTiers.any((t) => t.tierId == tier.tierId)) {
      return;
    }

    currentTiers.add(tier);
    currentTiers.sort((a, b) => a.tierId.compareTo(b.tierId));

    _winConfiguration = _winConfiguration.copyWith(
      regularWins: _winConfiguration.regularWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
  }

  /// Update existing regular win tier
  void updateRegularWinTier(int tierId, WinTierDefinition tier, {bool syncStages = true}) {
    final currentTiers = List<WinTierDefinition>.from(_winConfiguration.regularWins.tiers);
    final index = currentTiers.indexWhere((t) => t.tierId == tierId);

    if (index == -1) {
      return;
    }

    currentTiers[index] = tier;

    _winConfiguration = _winConfiguration.copyWith(
      regularWins: _winConfiguration.regularWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    if (syncStages) _syncWinTierStages();
    _markDirty();
  }

  /// Remove regular win tier
  void removeRegularWinTier(int tierId) {
    final currentTiers = List<WinTierDefinition>.from(_winConfiguration.regularWins.tiers);
    final removed = currentTiers.where((t) => t.tierId == tierId).firstOrNull;

    if (removed == null) {
      return;
    }

    currentTiers.removeWhere((t) => t.tierId == tierId);

    _winConfiguration = _winConfiguration.copyWith(
      regularWins: _winConfiguration.regularWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
  }

  /// Update big win tier
  void updateBigWinTier(int tierId, BigWinTierDefinition tier, {bool syncStages = true}) {
    final currentTiers = List<BigWinTierDefinition>.from(_winConfiguration.bigWins.tiers);
    final index = currentTiers.indexWhere((t) => t.tierId == tierId);

    if (index == -1) {
      return;
    }

    currentTiers[index] = tier;

    _winConfiguration = _winConfiguration.copyWith(
      bigWins: _winConfiguration.bigWins.copyWith(tiers: currentTiers),
    );
    _winConfigFromGdd = false;
    if (syncStages) _syncWinTierStages();
    _markDirty();
  }

  /// Update big win threshold
  void setBigWinThreshold(double threshold) {
    _winConfiguration = _winConfiguration.copyWith(
      bigWins: _winConfiguration.bigWins.copyWith(threshold: threshold),
    );
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
  }

  /// Get win tier for a specific win amount and bet
  /// Returns null if no win, or the tier definition
  WinTierResult? getWinTierForAmount(double winAmount, double betAmount) {
    if (winAmount <= 0 || betAmount <= 0) return null;

    final multiplier = winAmount / betAmount;

    // Check if it's a big win first
    if (_winConfiguration.bigWins.isBigWin(winAmount, betAmount)) {
      final maxTier = _winConfiguration.bigWins.getMaxTierForWin(winAmount, betAmount);
      final bigTier = _winConfiguration.bigWins.tiers.firstWhere(
        (t) => t.tierId == maxTier,
        orElse: () => _winConfiguration.bigWins.tiers.first,
      );
      return WinTierResult(
        isBigWin: true,
        multiplier: multiplier,
        regularTier: null,
        bigWinTier: bigTier,
        bigWinMaxTier: maxTier,
      );
    }

    // Regular win
    final regularTier = _winConfiguration.regularWins.getTierForWin(winAmount, betAmount);
    if (regularTier != null) {
      return WinTierResult(
        isBigWin: false,
        multiplier: multiplier,
        regularTier: regularTier,
        bigWinTier: null,
        bigWinMaxTier: null,
      );
    }

    return null;
  }

  /// Validate current win tier configuration
  bool validateWinConfiguration() {
    return _winConfiguration.regularWins.validate() &&
           _winConfiguration.bigWins.validate();
  }

  /// Reset win configuration to defaults
  void resetWinConfiguration() {
    _winConfiguration = SlotWinConfiguration.defaultConfig();
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
  }

  /// Sync win tier stages to StageConfigurationService AND Rust engine
  /// Public entry point for deferred win tier sync (e.g. slider onChangeEnd)
  void syncWinTierStages() => _syncWinTierStages();

  void _syncWinTierStages() {
    // 1. Register all win tier stages with StageConfigurationService (Dart side)
    StageConfigurationService.instance.registerWinTierStages(_winConfiguration);
    final stages = _winConfiguration.allStageNames;

    // 2. Sync P5 win tier config to Rust engine (FFI)
    _syncWinTierConfigToRust();
  }

  /// Sync P5 win tier config to Rust SlotLab engine
  void _syncWinTierConfigToRust() {
    try {
      final ffi = NativeFFI.instance;

      // Convert SlotWinConfiguration to Rust JSON format
      final jsonConfig = _winConfiguration.toJson();

      // Convert Dart model names to Rust model names:
      // Dart: regularWins.tiers[].tierId, fromMultiplier, toMultiplier, displayLabel, rollupDurationMs, rollupTickRate
      // Rust: regular_wins.tiers[].tier_id, from_multiplier, to_multiplier, display_label, rollup_duration_ms, rollup_tick_rate
      final rustJson = _convertToRustJson(jsonConfig);
      final jsonStr = _jsonEncode(rustJson);

      ffi.winTierSetConfigJson(jsonStr);
    } catch (e) { /* ignored */ }
  }

  /// Convert Dart JSON format to Rust JSON format (snake_case)
  Map<String, dynamic> _convertToRustJson(Map<String, dynamic> dartJson) {
    final regularWins = dartJson['regularWins'] as Map<String, dynamic>?;
    final bigWins = dartJson['bigWins'] as Map<String, dynamic>?;

    return {
      'regular_wins': {
        'tiers': (regularWins?['tiers'] as List?)?.map((t) => {
          'tier_id': t['tierId'],
          'from_multiplier': t['fromMultiplier'],
          'to_multiplier': t['toMultiplier'],
          'display_label': t['displayLabel'] ?? '',
          'rollup_duration_ms': t['rollupDurationMs'] ?? 1000,
          'rollup_tick_rate': t['rollupTickRate'] ?? 15,
          'particle_burst_count': t['particleBurstCount'] ?? 0,
        }).toList() ?? [],
      },
      'big_wins': {
        'threshold': bigWins?['threshold'] ?? 20.0,
        'intro_duration_ms': bigWins?['introDurationMs'] ?? 500,
        'end_duration_ms': bigWins?['endDurationMs'] ?? 4000,
        'fade_out_duration_ms': bigWins?['fadeOutDurationMs'] ?? 1000,
        'tiers': (bigWins?['tiers'] as List?)?.map((t) => {
          'tier_id': t['tierId'],
          'from_multiplier': t['fromMultiplier'],
          'to_multiplier': t['toMultiplier'],
          'display_label': t['displayLabel'] ?? '',
          'duration_ms': t['durationMs'] ?? 4000,
          'rollup_tick_rate': t['rollupTickRate'] ?? 10,
          'particle_burst_count': t['particleBurstCount'] ?? 20,
        }).toList() ?? [],
      },
    };
  }

  /// Simple JSON encode without importing dart:convert (already in scope via other imports)
  String _jsonEncode(Map<String, dynamic> map) {
    // Use the same encoder as toJsonString
    return _winConfiguration.toJsonString().isNotEmpty
        ? _encodeMap(map)
        : '{}';
  }

  String _encodeMap(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';
    if (value is List) {
      return '[${value.map(_encodeMap).join(',')}]';
    }
    if (value is Map) {
      final entries = value.entries.map((e) => '"${e.key}":${_encodeMap(e.value)}');
      return '{${entries.join(',')}}';
    }
    return '"$value"';
  }

  /// Apply a win tier preset configuration
  void applyWinTierPreset(SlotWinConfiguration preset) {
    _winConfiguration = preset;
    _winConfigFromGdd = false;
    _syncWinTierStages();
    _markDirty();
  }

  /// Export win configuration to JSON string
  String exportWinConfigurationJson() {
    return _winConfiguration.toJsonString();
  }

  /// Import win configuration from JSON string
  /// Returns true if import was successful
  bool importWinConfigurationJson(String jsonString) {
    try {
      final config = SlotWinConfiguration.fromJsonString(jsonString);
      if (!config.regularWins.validate() || !config.bigWins.validate()) {
        return false;
      }
      _winConfiguration = config;
      _winConfigFromGdd = false;
      _syncWinTierStages();
      _markDirty();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==========================================================================
  // PERSISTENCE
  // ==========================================================================

  /// Save project to file
  ///
  /// If [autoCommit] is true (default), changes will be auto-committed
  /// to the git repository after saving.
  Future<void> saveProject(String path, {bool autoCommit = true}) async {
    final file = File(path);
    await file.writeAsString(project.toJsonString());
    _projectPath = path;
    _isDirty = false;
    notifyListeners();

    // P3-05: Auto-commit on project save
    if (autoCommit) {
      final repoPath = file.parent.path;
      try {
        final gitProvider = GitProvider.instance;
        if (!gitProvider.isInitialized || gitProvider.repoPath != repoPath) {
          await gitProvider.init(repoPath);
        }
        if (gitProvider.state.isRepo && gitProvider.state.hasChanges) {
          await gitProvider.autoCommit(
            customMessage: 'Auto-save: $_projectName',
          );
        }
      } catch (e) { /* ignored */ }
    }
  }

  /// Load project from file
  Future<void> loadProject(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Project file not found: $path');
    }
    final content = await file.readAsString();
    final loaded = SlotLabProject.fromJsonString(content);

    _projectName = loaded.name;
    _projectPath = path;
    _symbols = List.from(loaded.symbols);
    _contexts = List.from(loaded.contexts);
    _symbolAudio = List.from(loaded.symbolAudio);
    _musicLayers = List.from(loaded.musicLayers);
    // V7: Restore audio panel state
    _audioAssignments = Map.from(loaded.audioAssignments);
    _expandedSections = Set.from(loaded.expandedSections);
    _expandedGroups = Set.from(loaded.expandedGroups);
    _lastActiveTab = loaded.lastActiveTab;
    // V8: Restore GDD data
    _gridConfig = loaded.gridConfig;
    _importedGdd = loaded.importedGdd;
    // V11: Restore slot machine config
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      final composer = GetIt.instance<FeatureComposerProvider>();
      if (loaded.slotMachineConfig != null) {
        composer.applyConfig(loaded.slotMachineConfig!);
      } else {
        composer.resetConfig();
      }
    }
    // V12: Restore composite events + EventRegistry
    _restoreCompositeEvents(loaded.compositeEventsJson);
    _restoreEventRegistry(loaded.eventRegistryJson);
    _isDirty = false;
    _sanitizeNofMVariantAssignments(); // Fix persisted NofM variant paths
    _syncSymbolStages(); // Sync stages for loaded symbols
    notifyListeners();
  }

  // ── V12: Audio persistence helpers ──────────────────────────────────────

  List<Map<String, dynamic>>? _snapshotCompositeEvents() {
    try {
      if (!GetIt.instance.isRegistered<MiddlewareProvider>()) return null;
      final middleware = GetIt.instance<MiddlewareProvider>();
      final exported = middleware.exportCompositeEventsToJson();
      final events = exported['compositeEvents'] as List<dynamic>?;
      return events?.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>>? _snapshotEventRegistry() {
    try {
      final registry = EventRegistry.instance;
      final exported = registry.toJson();
      final events = exported['events'] as List<dynamic>?;
      return events?.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  void _restoreCompositeEvents(List<Map<String, dynamic>>? eventsJson) {
    if (eventsJson == null || eventsJson.isEmpty) return;
    try {
      if (!GetIt.instance.isRegistered<MiddlewareProvider>()) return;
      final middleware = GetIt.instance<MiddlewareProvider>();
      middleware.importCompositeEventsFromJson({
        'version': 1,
        'compositeEvents': eventsJson,
      });
    } catch (e) {
      assert(() { debugPrint('Restore composite events error: $e'); return true; }());
    }
  }

  void _restoreEventRegistry(List<Map<String, dynamic>>? eventsJson) {
    if (eventsJson == null || eventsJson.isEmpty) return;
    try {
      final registry = EventRegistry.instance;
      registry.loadFromJson({'events': eventsJson});
    } catch (e) {
      assert(() { debugPrint('Restore event registry error: $e'); return true; }());
    }
  }

  /// Sanitize audio assignments: remove false positives and fix NofM variants.
  ///
  /// Two passes:
  /// 1. Remove OBVIOUSLY WRONG assignments — filename shares zero tokens with stage name
  ///    (e.g., "abacuses_fs_appear" assigned to REEL_SPIN_LOOP)
  /// 2. Fix NofM variant paths on non-indexed stages
  ///    (e.g., "spins_loop_2of3_1.wav" on REEL_SPIN_LOOP → try 1of3 or base file)
  void _sanitizeNofMVariantAssignments() {
    final removals = <String>[];
    final updates = <String, String>{};
    final nofmPattern = RegExp(r'(\d+)of(\d+)');

    // Known abbreviation mappings: short form → full stage token
    // These prevent sanitization from removing valid alias-based matches
    const knownAbbreviations = <String, String>{
      'mus': 'music',
      'bw': 'bigwin',
      'bg': 'base',
      'bgm': 'music',
      'sfx': 'sfx',
      'amb': 'ambience',
      'vo': 'voice',
      'fs': 'freespin',
      'rs': 'spin',
      'trn': 'transition',
      'btn': 'button',
      'ui': 'ui',
      'anx': 'anticipation',
      'ant': 'anticipation',
    };

    for (final entry in _audioAssignments.entries) {
      final stage = entry.key;
      final audioPath = entry.value;

      // Skip indexed stages (REEL_STOP_0, CASCADE_STEP_1, etc.)
      if (RegExp(r'_\d+$').hasMatch(stage)) continue;

      // ── PASS 1: False positive detection ──
      // Tokenize both stage name and filename, check for ANY overlap.
      // If zero tokens match → this is a false positive from fuzzy matching.
      final stageTokens = stage.toLowerCase().split('_').where((t) => t.isNotEmpty).toSet();
      final fileName = audioPath.split('/').last.split('.').first.toLowerCase();
      final fileTokens = fileName
          .replaceAll(RegExp(r'[\d]+of\d+'), '') // strip NofM
          .replaceAll(RegExp(r'^\d+[-_]'), '') // strip numeric prefix
          .split(RegExp(r'[-_\s]+'))
          .where((t) => t.length > 1) // skip single chars
          .toSet();

      // Expand file tokens with known abbreviations
      final expandedFileTokens = <String>{...fileTokens};
      for (final ft in fileTokens) {
        final expansion = knownAbbreviations[ft];
        if (expansion != null) expandedFileTokens.add(expansion);
      }

      // Count how many stage tokens are covered by file tokens (including expanded)
      int overlapCount = 0;
      for (final st in stageTokens) {
        for (final ft in expandedFileTokens) {
          if (ft == st || ft == '${st}s' || '${ft}s' == st) {
            overlapCount++;
            break;
          }
          if (ft.length >= 4 && st.length >= 4 &&
              (ft.startsWith(st) || st.startsWith(ft))) {
            overlapCount++;
            break;
          }
        }
      }

      // Require coverage proportional to stage complexity:
      // 1-2 token stages: at least 1 overlap
      // 3+ token stages (e.g. REEL_SPIN_LOOP): at least 2 overlaps
      final minRequired = stageTokens.length >= 3 ? 2 : 1;
      if (overlapCount < minRequired && fileTokens.isNotEmpty) {
        removals.add(stage);
        continue;
      }

      // ── PASS 2: NofM variant fix ──
      final match = nofmPattern.firstMatch(audioPath);
      if (match == null) continue;

      final n = int.tryParse(match.group(1)!) ?? 1;
      if (n == 1) continue; // First variant (1ofN) is acceptable

      // Try to find the 1ofN variant file
      final basePath = audioPath.replaceFirst(
        match.group(0)!,
        '1of${match.group(2)}',
      );
      if (File(basePath).existsSync()) {
        updates[stage] = basePath;
        continue;
      }

      // Try to find a file without any NofM notation
      final cleanPath = audioPath.replaceAll(RegExp(r'_?\d+of\d+(_\d+)?'), '');
      if (cleanPath != audioPath && File(cleanPath).existsSync()) {
        updates[stage] = cleanPath;
      }
    }

    // Apply removals
    for (final stage in removals) {
      _audioAssignments.remove(stage);
    }
    // Apply updates
    for (final entry in updates.entries) {
      _audioAssignments[entry.key] = entry.value;
    }
  }

  /// Public API: sanitize audio assignments (remove false positives, fix NofM)
  /// Call on app startup or screen init to clean up stale/wrong assignments.
  void sanitizeAssignments() {
    final beforeCount = _audioAssignments.length;
    _sanitizeNofMVariantAssignments();
    if (_audioAssignments.length < beforeCount) {
      notifyListeners();
    }
  }

  /// Import from JSON string (for GDD import, etc.)
  void importFromJson(String jsonString) {
    final loaded = SlotLabProject.fromJsonString(jsonString);
    _projectName = loaded.name;
    _symbols = List.from(loaded.symbols);
    _contexts = List.from(loaded.contexts);
    _symbolAudio = List.from(loaded.symbolAudio);
    _musicLayers = List.from(loaded.musicLayers);
    // V7: Restore audio panel state
    _audioAssignments = Map.from(loaded.audioAssignments);
    _expandedSections = Set.from(loaded.expandedSections);
    _expandedGroups = Set.from(loaded.expandedGroups);
    _lastActiveTab = loaded.lastActiveTab;
    // V8: Restore GDD data
    _gridConfig = loaded.gridConfig;
    _importedGdd = loaded.importedGdd;
    // V11: Restore slot machine config
    if (GetIt.instance.isRegistered<FeatureComposerProvider>()) {
      final composer = GetIt.instance<FeatureComposerProvider>();
      if (loaded.slotMachineConfig != null) {
        composer.applyConfig(loaded.slotMachineConfig!);
      } else {
        composer.resetConfig();
      }
    }
    _sanitizeNofMVariantAssignments(); // Fix persisted NofM variant paths
    _syncSymbolStages(); // Sync stages for imported symbols
    _markDirty();
  }

  /// Export to JSON string
  String exportToJson() => project.toJsonString();

  // ==========================================================================
  // GDD IMPORT
  // ==========================================================================

  /// Import symbols from Game Design Document
  void importSymbolsFromGdd(List<Map<String, dynamic>> gddSymbols) {
    for (final gdd in gddSymbols) {
      final id = (gdd['id'] ?? gdd['name'] ?? 'sym_${_symbols.length}').toString().toLowerCase().replaceAll(' ', '_');
      final name = gdd['name']?.toString() ?? 'Symbol ${_symbols.length + 1}';
      final type = _parseSymbolType(gdd['type']?.toString());
      final emoji = gdd['emoji']?.toString() ?? _defaultEmojiForType(type);

      // Check if symbol already exists
      if (_symbols.any((s) => s.id == id)) continue;

      addSymbol(SymbolDefinition(
        id: id,
        name: name,
        emoji: emoji,
        type: type,
        payMultiplier: gdd['payMultiplier'] as int?,
      ));
    }
  }

  SymbolType _parseSymbolType(String? typeStr) {
    if (typeStr == null) return SymbolType.lowPay;
    final lower = typeStr.toLowerCase();
    if (lower.contains('wild')) return SymbolType.wild;
    if (lower.contains('scatter')) return SymbolType.scatter;
    if (lower.contains('bonus')) return SymbolType.bonus;
    if (lower.contains('high') || lower.contains('premium') || lower.contains('hp')) {
      return SymbolType.highPay;
    }
    if (lower.contains('medium') || lower.contains('mid') || lower.contains('mp')) {
      return SymbolType.mediumPay;
    }
    if (lower.contains('mult')) return SymbolType.multiplier;
    if (lower.contains('collect') || lower.contains('coin')) return SymbolType.collector;
    if (lower.contains('mystery')) return SymbolType.mystery;
    return SymbolType.lowPay;
  }

  String _defaultEmojiForType(SymbolType type) {
    return type.defaultEmoji;
  }

  // ==========================================================================
  // BULK RESET METHODS
  // ==========================================================================

  /// Reset all symbol audio assignments for a specific context (land, win, expand)
  void resetSymbolAudioForContext(String context) {
    final before = _symbolAudio.length;
    _symbolAudio = _symbolAudio.where((a) => a.context != context).toList();
    final removed = before - _symbolAudio.length;
    _markDirty();
  }

  /// Reset all symbol audio assignments for a specific symbol
  void resetSymbolAudioForSymbol(String symbolId) {
    final before = _symbolAudio.length;
    _symbolAudio = _symbolAudio.where((a) => a.symbolId != symbolId).toList();
    final removed = before - _symbolAudio.length;
    _markDirty();
  }

  /// Reset ALL symbol audio assignments
  void resetAllSymbolAudio() {
    final count = _symbolAudio.length;
    _symbolAudio = [];
    _markDirty();
  }

  /// Reset all music layers for a specific context (base, freeSpins, etc.)
  void resetMusicLayersForContext(String contextId) {
    final before = _musicLayers.length;
    _musicLayers = _musicLayers.where((a) => a.contextId != contextId).toList();
    final removed = before - _musicLayers.length;
    _markDirty();
  }

  /// Reset ALL music layer assignments
  void resetAllMusicLayers() {
    final count = _musicLayers.length;
    _musicLayers = [];
    _markDirty();
  }

  /// Get count of audio assignments per section (for UI display)
  Map<String, int> getAudioAssignmentCounts() {
    final counts = <String, int>{};

    // Symbol audio by context
    for (final assignment in _symbolAudio) {
      final key = 'symbol_${assignment.context}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // Music layers by context
    for (final assignment in _musicLayers) {
      final key = 'music_${assignment.contextId}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // Totals
    counts['symbol_total'] = _symbolAudio.length;
    counts['music_total'] = _musicLayers.length;

    return counts;
  }

  // ==========================================================================
  // PROJECT NOTES (Dashboard P1)
  // ==========================================================================

  String _projectNotes = '';

  /// Project notes for Dashboard
  String get projectNotes => _projectNotes;

  /// Set project notes
  void setProjectNotes(String notes) {
    if (_projectNotes != notes) {
      _projectNotes = notes;
      _markDirty();
    }
  }

  // ==========================================================================
  // COVERAGE BY SECTION (Dashboard P0)
  // ==========================================================================

  /// Section definitions matching UltimateAudioPanel V8.1
  static const List<(String id, String name, int slotCount, List<String> stagePrefixes)> _sectionDefinitions = [
    ('base_game_loop', 'Base Game Loop', 44, ['ATTRACT', 'IDLE', 'GAME_', 'SPIN_', 'REEL_', 'ANTICIPATION', 'NEAR_MISS', 'NO_WIN', 'QUICK_STOP', 'SLAM_STOP', 'AUTOPLAY', 'UI_TURBO', 'UI_STOP', 'TURBO_SPIN']),
    ('symbols', 'Symbols & Lands', 46, ['SYMBOL_', 'WILD_', 'SCATTER_', 'BONUS_SYMBOL', 'MYSTERY_', 'COLLECT_', 'TRANSFORM_']),
    ('win_presentation', 'Win Presentation', 41, ['WIN_', 'ROLLUP_', 'BIG_WIN', 'CELEBRATION', 'COIN_']),
    ('cascading', 'Cascading Mechanics', 24, ['CASCADE_', 'TUMBLE_', 'AVALANCHE_', 'CLUSTER_']),
    ('multipliers', 'Multipliers', 18, ['MULT_', 'MULTIPLIER_']),
    ('free_spins', 'Free Spins', 24, ['FS_']),
    ('bonus', 'Bonus Games', 32, ['BONUS_', 'PICK_', 'WHEEL_', 'TRAIL_']),
    ('hold_win', 'Hold & Win', 23, ['HOLD_', 'RESPIN_', 'LOCK_', 'COIN_LAND', 'RESPINS_']),
    ('jackpots', 'Jackpots', 26, ['JACKPOT_', 'JP_', 'GRAND_', 'MAJOR_', 'MINOR_', 'MINI_']),
    ('gamble', 'Gamble', 16, ['GAMBLE_', 'DOUBLE_', 'RISK_']),
    ('music', 'Music & Ambience', 25, ['MUSIC_', 'AMBIENT_', 'BGM_', 'TENSION_MUSIC', 'STINGER_']),
    ('ui_system', 'UI & System', 18, ['UI_', 'MENU_', 'BUTTON_', 'NOTIFICATION_', 'ERROR_', 'SYSTEM_']),
  ];

  /// Get coverage breakdown by section
  /// Returns map: sectionId → { 'assigned': X, 'total': Y, 'percent': Z }
  Map<String, Map<String, int>> getCoverageBySection() {
    final result = <String, Map<String, int>>{};

    for (final (id, _, slotCount, prefixes) in _sectionDefinitions) {
      // Count assigned stages matching this section's prefixes
      int assigned = 0;
      for (final entry in _audioAssignments.entries) {
        final stage = entry.key.toUpperCase();
        for (final prefix in prefixes) {
          if (stage.startsWith(prefix)) {
            assigned++;
            break;
          }
        }
      }

      // Also count symbol audio if section is 'symbols'
      if (id == 'symbols') {
        assigned += _symbolAudio.length;
      }

      // Also count music layers if section is 'music'
      if (id == 'music') {
        assigned += _musicLayers.length;
      }

      final percent = slotCount > 0 ? (assigned / slotCount * 100).round() : 0;
      result[id] = {
        'assigned': assigned,
        'total': slotCount,
        'percent': percent.clamp(0, 100),
      };
    }

    return result;
  }

  /// Get section info for Dashboard
  static List<(String id, String name, int slotCount)> getSectionInfo() {
    return _sectionDefinitions.map((s) => (s.$1, s.$2, s.$3)).toList();
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  void _markDirty() {
    _isDirty = true;
    notifyListeners();
  }

  /// Sync symbol stages to StageConfigurationService
  /// Call this whenever symbols are added, removed, or modified
  void _syncSymbolStages() {
    StageConfigurationService.instance.syncSymbolStages(_symbols);
  }

  /// Debug: print current state
  void debugPrintState() {
  }
}

// =============================================================================
// UNDO SUPPORT TYPES (P3 Recommendation #3)
// =============================================================================

/// Type of audio assignment undo operation
enum _AudioUndoType {
  set,    // Single stage assignment
  remove, // Single stage removal
  bulk,   // Bulk operation (multiple stages)
}

/// Entry in the audio assignment undo stack
class _AudioAssignmentUndoEntry {
  final _AudioUndoType type;
  final String stage;
  final String? previousPath;
  final String? newPath;
  final String description;
  final List<_AudioAssignmentUndoEntry>? bulkEntries;

  const _AudioAssignmentUndoEntry({
    required this.type,
    required this.stage,
    required this.previousPath,
    required this.newPath,
    required this.description,
    this.bulkEntries,
  });
}

// =============================================================================
// SESSION STATS MODELS (Dashboard Integration)
// =============================================================================

/// Session statistics for Dashboard Stats tab
class SessionStats {
  final int totalSpins;
  final double totalBet;
  final double totalWin;

  const SessionStats({
    this.totalSpins = 0,
    this.totalBet = 0.0,
    this.totalWin = 0.0,
  });

  double get rtp => totalBet > 0 ? (totalWin / totalBet) * 100 : 0.0;

  SessionStats copyWith({int? totalSpins, double? totalBet, double? totalWin}) {
    return SessionStats(
      totalSpins: totalSpins ?? this.totalSpins,
      totalBet: totalBet ?? this.totalBet,
      totalWin: totalWin ?? this.totalWin,
    );
  }
}

/// Single win record for Dashboard history
class SessionWin {
  final double amount;
  final String tier;
  final DateTime time;

  const SessionWin({
    required this.amount,
    required this.tier,
    required this.time,
  });
}
