/// Game Flow Integration — Bridge between GameFlowProvider and SlotLabCoordinator
///
/// Wires up GameFlowProvider to the existing SlotLab infrastructure:
/// - SlotEngineProvider.onSpinComplete → GameFlowProvider.onSpinComplete
/// - GameFlowProvider.onAudioStage → SlotStageProvider/EventRegistry
/// - GameFlowProvider.onStateChanged → SlotLabCoordinator state sync
/// - FeatureBuilder block configs → Executor registration
///
/// This class is initialized once when SlotLab is loaded and handles
/// bidirectional communication without modifying existing providers.
library;

import '../../models/game_flow_models.dart';
import '../../services/event_registry.dart';
import '../../services/service_locator.dart';
import '../feature_builder_provider.dart';
import 'game_flow_provider.dart';
import 'executors/free_spins_executor.dart';
import 'executors/cascade_executor.dart';
import 'executors/hold_and_win_executor.dart';
import 'executors/bonus_game_executor.dart';
import 'executors/gamble_executor.dart';
import 'executors/respin_executor.dart';
import 'executors/jackpot_executor.dart';
import 'executors/multiplier_executor.dart';
import 'executors/wild_features_executor.dart';
import 'executors/collector_executor.dart';

class GameFlowIntegration {
  GameFlowIntegration._();
  static GameFlowIntegration? _instance;
  static GameFlowIntegration get instance =>
      _instance ??= GameFlowIntegration._();

  bool _initialized = false;
  GameFlowProvider? _flowProvider;
  FeatureBuilderProvider? _featureBuilder;

  /// Block ID → Executor factory
  static final Map<String, FeatureExecutor Function()> _executorFactories = {
    'free_spins': FreeSpinsExecutor.new,
    'cascades': CascadeExecutor.new,
    'hold_and_win': HoldAndWinExecutor.new,
    'bonus_game': BonusGameExecutor.new,
    'gambling': GambleExecutor.new,
    'respin': RespinExecutor.new,
    'jackpot': JackpotExecutor.new,
    'multiplier': MultiplierExecutor.new,
    'wild_features': WildFeaturesExecutor.new,
    'collector': CollectorExecutor.new,
  };

  /// Initialize the integration layer
  void initialize() {
    if (_initialized) return;

    _flowProvider = sl<GameFlowProvider>();

    // Wire audio stage callback → EventRegistry
    _flowProvider!.onAudioStage = _onAudioStage;

    // Wire state change callback
    _flowProvider!.onStateChanged = _onStateChanged;

    // Wire feature state update callback
    _flowProvider!.onFeatureStateUpdated = _onFeatureStateUpdated;

    // Register default executors so forced outcomes work even without FeatureBuilder config
    _registerDefaultExecutors();

    // Listen to FeatureBuilderProvider for real-time sync (overrides defaults)
    _featureBuilder = sl<FeatureBuilderProvider>();
    _featureBuilder!.addListener(_onFeatureBuilderChanged);

    // Initial sync from FeatureBuilder (replaces defaults with user config)
    syncFromFeatureBuilder(_featureBuilder!);

    _initialized = true;
  }

  /// Register default executors with default config.
  /// Ensures forced outcomes (FREE SPINS, CASCADE, etc.) work out of the box
  /// even before user configures anything in Feature Builder.
  void _registerDefaultExecutors() {
    final flow = _flowProvider;
    if (flow == null) return;

    for (final entry in _executorFactories.entries) {
      final executor = entry.value();
      executor.configure({'enabled': true});
      flow.registerExecutor(executor);
    }
  }

  void _onFeatureBuilderChanged() {
    final fb = _featureBuilder;
    if (fb != null) {
      syncFromFeatureBuilder(fb);
    }
  }

  /// Apply Feature Builder configuration to executors
  ///
  /// Called when user changes block config in Feature Builder UI.
  /// Maps block options → executor.configure() + registers/unregisters.
  void applyFeatureBuilderConfig(Map<String, Map<String, dynamic>> blockConfigs) {
    final flow = _flowProvider;
    if (flow == null) return;

    // Clear existing executors
    flow.clearExecutors();

    // Register executors for enabled blocks
    for (final entry in blockConfigs.entries) {
      final blockId = entry.key;
      final options = entry.value;

      // Check if block is enabled
      final enabled = options['enabled'] as bool? ?? true;
      if (!enabled) continue;

      // Get executor factory
      final factory = _executorFactories[blockId];
      if (factory == null) continue;

      // Create, configure, and register
      final executor = factory();
      executor.configure(options);
      flow.registerExecutor(executor);
    }
  }

  /// Apply a single block's configuration
  void applyBlockConfig(String blockId, Map<String, dynamic> options) {
    final flow = _flowProvider;
    if (flow == null) return;

    final enabled = options['enabled'] as bool? ?? true;

    if (!enabled) {
      flow.unregisterExecutor(blockId);
      return;
    }

    // Get existing or create new
    var executor = flow.executors.getExecutor(blockId);
    if (executor == null) {
      final factory = _executorFactories[blockId];
      if (factory == null) return;
      executor = factory();
      flow.registerExecutor(executor);
    }

    executor.configure(options);
  }

  /// Map FeatureBuilderProvider blocks to GameFlowProvider executors
  void syncFromFeatureBuilder(FeatureBuilderProvider featureBuilder) {
    final blockConfigs = <String, Map<String, dynamic>>{};

    for (final block in featureBuilder.enabledBlocks) {
      final blockId = _mapFeatureBuilderBlockId(block.id);
      if (blockId == null) continue;

      // Convert List<BlockOption> → Map<String, dynamic>
      final optionsMap = <String, dynamic>{};
      for (final option in block.options) {
        optionsMap[option.id] = option.value;
      }
      optionsMap['enabled'] = block.isEnabled;

      blockConfigs[blockId] = optionsMap;
    }

    applyFeatureBuilderConfig(blockConfigs);

    // Sync transition config from 'transitions' block
    _syncTransitionConfig(featureBuilder);
  }

  /// Sync transition configuration from Feature Builder transitions block
  void _syncTransitionConfig(FeatureBuilderProvider fb) {
    final flow = _flowProvider;
    if (flow == null) return;

    final transitionsBlock = fb.allBlocks
        .where((b) => b.id == 'transitions')
        .firstOrNull;

    if (transitionsBlock == null || !transitionsBlock.isEnabled) {
      flow.configureTransitions(enabled: false);
      return;
    }

    // Read transition options from block config
    final optionsMap = <String, dynamic>{};
    for (final option in transitionsBlock.options) {
      optionsMap[option.id] = option.value;
    }

    final durationMs = optionsMap['transitionDuration'] as int? ?? 3000;
    final dismissModeStr = optionsMap['dismissMode'] as String? ?? 'timedOrClick';
    final styleStr = optionsMap['transitionStyle'] as String? ?? 'fade';

    final dismissMode = switch (dismissModeStr) {
      'timed' => TransitionDismissMode.timed,
      'click' || 'clickToContinue' => TransitionDismissMode.clickToContinue,
      _ => TransitionDismissMode.timedOrClick,
    };

    final style = switch (styleStr) {
      'slideUp' => TransitionStyle.slideUp,
      'slideDown' => TransitionStyle.slideDown,
      'zoom' => TransitionStyle.zoom,
      'swoosh' => TransitionStyle.swoosh,
      _ => TransitionStyle.fade,
    };

    final defaultConfig = SceneTransitionConfig(
      durationMs: durationMs,
      dismissMode: dismissMode,
      style: style,
    );

    flow.configureTransitions(
      enabled: true,
      defaultConfig: defaultConfig,
    );
  }

  /// Map Feature Builder block IDs to executor block IDs
  String? _mapFeatureBuilderBlockId(String featureBuilderBlockId) {
    return switch (featureBuilderBlockId) {
      'free_spins' => 'free_spins',
      'cascades' || 'tumble' || 'avalanche' => 'cascades',
      'hold_and_win' || 'cash_on_reels' || 'coin_lock' => 'hold_and_win',
      'bonus_game' || 'pick_bonus' || 'wheel_bonus' => 'bonus_game',
      'gambling' || 'gamble' || 'double_up' => 'gambling',
      'respin' || 'nudge' => 'respin',
      'jackpot' || 'progressive_jackpot' => 'jackpot',
      'multiplier' || 'random_multiplier' => 'multiplier',
      'wild_features' || 'wilds' || 'sticky_wilds' => 'wild_features',
      'collector' || 'meter' || 'collection' => 'collector',
      _ => null,
    };
  }

  // ─── Callbacks ────────────────────────────────────────────────────────────

  void _onAudioStage(String stageId) {
    try {
      EventRegistry.instance.triggerStage(stageId);
    } catch (_) {
      // EventRegistry may not be initialized
    }
  }

  void _onStateChanged(GameFlowState oldState, GameFlowState newState) {
    // Returning to base game → fade in base game layer 1 music
    if ((newState == GameFlowState.baseGame || newState == GameFlowState.idle) &&
        oldState != GameFlowState.baseGame && oldState != GameFlowState.idle) {
      _onAudioStage('MUSIC_BASE_L1');
    }
  }

  void _onFeatureStateUpdated(String featureId, FeatureState state) {
    // Notify UI components that feature state changed
    // GameFlowProvider.notifyListeners() already handles this
  }

  /// Dispose integration
  void dispose() {
    _featureBuilder?.removeListener(_onFeatureBuilderChanged);
    _featureBuilder = null;
    _flowProvider?.onAudioStage = null;
    _flowProvider?.onStateChanged = null;
    _flowProvider?.onFeatureStateUpdated = null;
    _flowProvider = null;
    _initialized = false;
    _instance = null;
  }
}
