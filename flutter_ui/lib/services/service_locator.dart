/// Service Locator — Dependency Injection with GetIt
///
/// Centralized service registration for FluxForge Studio.
/// Replaces direct .instance singleton calls with proper DI.
///
/// Usage:
///   // In main.dart, call once before runApp():
///   await ServiceLocator.init();
///
///   // Then anywhere in the app:
///   final ffi = sl.get(NativeFFI);
///   final pool = sl.get(AudioPool);
///
/// Migration Guide (Phase 2 - future):
///   BEFORE: NativeFFI.instance.someMethod()
///   AFTER:  sl.get(NativeFFI).someMethod()
///
/// NOTE: Current implementation registers existing singletons.
/// Full DI migration (constructor injection) planned for Phase 2.
///
/// Benefits:
///   - Testability: Easy to mock services in tests
///   - Explicit dependencies: Clear what each class needs
///   - Lifecycle management: Proper initialization order
///   - Memory management: Centralized dispose

import 'package:get_it/get_it.dart';

import '../src/rust/native_ffi.dart';
import '../providers/loop_provider.dart';
import '../providers/subsystems/state_groups_provider.dart';
import '../providers/subsystems/switch_groups_provider.dart';
import '../providers/subsystems/rtpc_system_provider.dart';
import '../providers/subsystems/ducking_system_provider.dart';
import '../providers/subsystems/blend_containers_provider.dart';
import '../providers/subsystems/random_containers_provider.dart';
import '../providers/subsystems/sequence_containers_provider.dart';
import '../providers/subsystems/music_system_provider.dart';
import '../providers/subsystems/event_system_provider.dart';
import '../providers/subsystems/composite_event_system_provider.dart';
import '../providers/subsystems/bus_hierarchy_provider.dart';
import '../providers/subsystems/aux_send_provider.dart';
import '../providers/subsystems/voice_pool_provider.dart';
import '../providers/subsystems/attenuation_curve_provider.dart';
import '../providers/subsystems/memory_manager_provider.dart';
import '../providers/subsystems/event_profiler_provider.dart';
import '../providers/slot_lab_project_provider.dart';
import '../providers/git_provider.dart';
import '../providers/ale_provider.dart';
import '../providers/automation_provider.dart';
import '../providers/feature_builder_provider.dart';
import '../providers/stem_routing_provider.dart';
import '../providers/comping_provider.dart';
import 'audio_pool.dart';
import 'audio_playback_service.dart';
import 'unified_playback_controller.dart';
import 'ducking_service.dart';
import 'rtpc_modulation_service.dart';
import 'container_service.dart';
import 'waveform_cache_service.dart';
import 'audio_asset_manager.dart';
import 'shared_meter_reader.dart';
import 'slotlab_track_bridge.dart';
import 'session_persistence_service.dart';
import 'live_engine_service.dart';
import 'unified_search_service.dart';
import 'recent_favorites_service.dart';
import 'plugin_state_service.dart';
import 'missing_plugin_detector.dart';
import 'analytics_service.dart';
import '../controllers/middleware_timeline_sync_controller.dart';
import '../providers/event_folder_provider.dart';
import '../providers/aurexis_provider.dart';
import '../providers/device_preview_provider.dart';
import '../providers/dpm_provider.dart';
import '../providers/energy_governance_provider.dart';
import '../providers/spectral_allocation_provider.dart';
import '../providers/aurexis_audit_provider.dart';
import '../providers/aurexis_profile_provider.dart';
import '../providers/slot_lab/behavior_tree_provider.dart';
import '../providers/slot_lab/state_gate_provider.dart';
import '../providers/slot_lab/emotional_state_provider.dart';
import '../providers/slot_lab/slotlab_view_mode_provider.dart';
import '../providers/slot_lab/transition_system_provider.dart';
import '../providers/slot_lab/priority_engine_provider.dart';
import '../providers/slot_lab/orchestration_engine_provider.dart';
import 'autobind_engine.dart';
import '../providers/slot_lab/ail_provider.dart';
import '../providers/slot_lab/drc_provider.dart';
import '../providers/slot_lab/sam_provider.dart';
import '../providers/slot_lab/simulation_engine_provider.dart';
import '../providers/slot_lab/error_prevention_provider.dart';
import '../providers/slot_lab/slotlab_undo_provider.dart';
import '../providers/slot_lab/slotlab_notification_provider.dart';
import '../providers/slot_lab/behavior_coverage_provider.dart';
import '../providers/slot_lab/smart_collapsing_provider.dart';
import '../providers/slot_lab/inspector_context_provider.dart';
import '../providers/slot_lab/context_layer_provider.dart';
import '../providers/slot_lab/trigger_layer_provider.dart';
import '../providers/slot_lab/slotlab_template_provider.dart';
import '../providers/slot_lab/slotlab_export_provider.dart';
import '../providers/slot_lab/feature_composer_provider.dart';
import '../providers/slot_lab/pacing_engine_provider.dart';
import '../providers/slot_lab/gad_provider.dart';
import '../providers/slot_lab/sss_provider.dart';
import '../providers/slot_lab/game_flow_provider.dart';
import '../providers/fluxmacro_provider.dart';
import '../providers/slot_lab/stage_flow_provider.dart';

/// Global service locator instance
final GetIt sl = GetIt.instance;

/// Service Locator configuration
class ServiceLocator {
  ServiceLocator._();

  static bool _initialized = false;

  /// Initialize all services in correct order
  /// Call this once in main.dart before runApp()
  static Future<void> init() async {
    if (_initialized) return;

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 1: Core FFI (no dependencies)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<NativeFFI>(() => NativeFFI.instance);

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 2: Low-level services (depend only on FFI)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SharedMeterReader>(
      () => SharedMeterReader.instance,
    );
    sl.registerLazySingleton<WaveformCacheService>(
      () => WaveformCacheService.instance,
    );
    sl.registerLazySingleton<AudioAssetManager>(
      () => AudioAssetManager.instance,
    );
    sl.registerLazySingleton<LiveEngineService>(
      () => LiveEngineService.instance,
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 3: Playback services (depend on FFI)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<UnifiedPlaybackController>(
      () => UnifiedPlaybackController.instance,
    );
    sl.registerLazySingleton<AudioPlaybackService>(
      () => AudioPlaybackService.instance,
    );
    sl.registerLazySingleton<AudioPool>(() => AudioPool.instance);
    sl.registerLazySingleton<SlotLabTrackBridge>(
      () => SlotLabTrackBridge.instance,
    );
    sl.registerLazySingleton<SessionPersistenceService>(
      () => SessionPersistenceService.instance,
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 4: Audio processing services (depend on playback)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<DuckingService>(() => DuckingService.instance);
    sl.registerLazySingleton<RtpcModulationService>(
      () => RtpcModulationService.instance,
    );
    sl.registerLazySingleton<ContainerService>(() => ContainerService.instance);

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5: Middleware subsystem providers (extracted from MiddlewareProvider)
    // These are ChangeNotifiers that manage specific middleware domains.
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<StateGroupsProvider>(
      () => StateGroupsProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<SwitchGroupsProvider>(
      () => SwitchGroupsProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<RtpcSystemProvider>(
      () => RtpcSystemProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<DuckingSystemProvider>(
      () => DuckingSystemProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<BlendContainersProvider>(
      () => BlendContainersProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<RandomContainersProvider>(
      () => RandomContainersProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<SequenceContainersProvider>(
      () => SequenceContainersProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<MusicSystemProvider>(
      () => MusicSystemProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<EventSystemProvider>(
      () => EventSystemProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<CompositeEventSystemProvider>(
      () => CompositeEventSystemProvider(
        ffi: sl<NativeFFI>(),
        eventSystemProvider: sl<EventSystemProvider>(),
      ),
    );
    sl.registerLazySingleton<BusHierarchyProvider>(
      () => BusHierarchyProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<AuxSendProvider>(
      () => AuxSendProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<VoicePoolProvider>(
      () => VoicePoolProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<AttenuationCurveProvider>(
      () => AttenuationCurveProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<MemoryManagerProvider>(
      () => MemoryManagerProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<EventProfilerProvider>(
      () => EventProfilerProvider(ffi: sl<NativeFFI>()),
    );

    // NOTE: EventRegistry is a ChangeNotifier created per-screen via Provider,
    // not registered here.

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.5: SlotLab Project Provider
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabProjectProvider>(
      () => SlotLabProjectProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.5.1: ALE Provider (Adaptive Layer Engine)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AleProvider>(
      () => AleProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.5.2: Automation Provider (DAW parameter automation)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AutomationProvider>(
      () => AutomationProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.6: Git Provider (P3-05 Version Control)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<GitProvider>(
      () => GitProvider.instance,
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.7: Feature Builder Provider (P13 Feature Builder Panel)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<FeatureBuilderProvider>(
      () => FeatureBuilderProvider.instance,
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.8: Stem Routing Provider (P10.1.2 Stem Export)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<StemRoutingProvider>(
      () => StemRoutingProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9: Comping Provider (Multi-take recording & comp editing)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<CompingProvider>(
      () => CompingProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.1: Middleware ↔ DAW Timeline Sync Bridge
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<MiddlewareTimelineSyncController>(
      () => MiddlewareTimelineSyncController(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.2: Event Folder Provider (DAW ↔ SlotLab Unified Track Graph)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<EventFolderProvider>(
      () => EventFolderProvider(
        compositeProvider: sl<CompositeEventSystemProvider>(),
      ),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.3: AUREXIS™ Provider (Slot Audio Intelligence Engine)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AurexisProvider>(
      () => AurexisProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.4: AUREXIS™ Profile Provider (Profile-driven intelligence)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AurexisProfileProvider>(
      () => AurexisProfileProvider(engine: sl<AurexisProvider>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.5: AUREXIS™ Audit Provider (Session audit trail)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AurexisAuditProvider>(
      () => AurexisAuditProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.5b: Device Preview Provider (monitoring-only device simulation)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<DevicePreviewProvider>(
      () => DevicePreviewProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 6.0: Energy Governance Provider (GEG — Global Energy Governance)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<EnergyGovernanceProvider>(
      () => EnergyGovernanceProvider(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 6.1: DPM Provider (Dynamic Priority Matrix)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<DpmProvider>(
      () => DpmProvider(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 6.2: Spectral Allocation Provider (SAMCL — Spectral Allocation & Masking)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SpectralAllocationProvider>(
      () => SpectralAllocationProvider(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.6: Behavior Tree Provider (SlotLab Middleware §5)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<BehaviorTreeProvider>(
      () => BehaviorTreeProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.7: State Gate Provider (SlotLab Middleware §4)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<StateGateProvider>(
      () => StateGateProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.8: AutoBind Engine (SlotLab Middleware §6)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AutoBindEngine>(
      () => AutoBindEngine.instance,
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.9: Emotional State Provider (SlotLab Middleware §9)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<EmotionalStateProvider>(
      () => EmotionalStateProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10: SlotLab View Mode Provider (Middleware §16 + §19)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabViewModeProvider>(
      () => SlotLabViewModeProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.11: Transition System Provider (SlotLab Middleware §25)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<TransitionSystemProvider>(
      () => TransitionSystemProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.12: Priority Engine Provider (SlotLab Middleware §8)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<PriorityEngineProvider>(
      () => PriorityEngineProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.13: Orchestration Engine Provider (SlotLab Middleware §10)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<OrchestrationEngineProvider>(
      () => OrchestrationEngineProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.14: Simulation Engine Provider (SlotLab Middleware §13)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SimulationEngineProvider>(
      () => SimulationEngineProvider(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 6.3: AIL Provider (Authoring Intelligence Layer §9)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AilProvider>(
      () => AilProvider(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 6.4: DRC Provider (Deterministic Replay Core §10)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<DrcProvider>(
      () => DrcProvider(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 7: SAM Provider (Smart Authoring Mode §13)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SamProvider>(
      () => SamProvider(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.15: Error Prevention Provider (SlotLab Middleware §15)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<ErrorPreventionProvider>(
      () => ErrorPreventionProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.16: SlotLab Undo Provider (SlotLab Middleware §30)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabUndoProvider>(
      () => SlotLabUndoProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.17: SlotLab Notification Provider (SlotLab Middleware §36)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabNotificationProvider>(
      () => SlotLabNotificationProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.18: Behavior Coverage Provider (SlotLab Middleware §17)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<BehaviorCoverageProvider>(
      () => BehaviorCoverageProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.19: Smart Collapsing Provider (SlotLab Middleware §18)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SmartCollapsingProvider>(
      () => SmartCollapsingProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.20: Inspector Context Provider (SlotLab Middleware §20)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<InspectorContextProvider>(
      () => InspectorContextProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.21: Context Layer Provider (SlotLab Middleware §21)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<ContextLayerProvider>(
      () => ContextLayerProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.22: Trigger Layer Provider (SlotLab Middleware §3)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<TriggerLayerProvider>(
      () => TriggerLayerProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.23: Feature Composer Provider (Trostepeni Stage System Layer 2)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<FeatureComposerProvider>(
      () => FeatureComposerProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.24: Pacing Engine Provider (Generate Audio Map From Math)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<PacingEngineProvider>(
      () => PacingEngineProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.25: SlotLab Template Provider (SlotLab Middleware §31)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabTemplateProvider>(
      () => SlotLabTemplateProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.26: SlotLab Export Provider (SlotLab Middleware §32)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabExportProvider>(
      () => SlotLabExportProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 6: UX Services (search, recent/favorites, analytics)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<UnifiedSearchService>(
      () => UnifiedSearchService.instance,
    );
    sl.registerLazySingleton<RecentFavoritesService>(
      () => RecentFavoritesService.instance,
    );
    sl.registerLazySingleton<AnalyticsService>(
      () => AnalyticsService.instance,
    );

    // Initialize search providers
    _initializeSearchProviders();

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 7.1: GAD Provider (Gameplay-Aware DAW §15)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<GadProvider>(
      () => GadProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 7.2: SSS Provider (Scale & Stability Suite §16)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SssProvider>(
      () => SssProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 7.3: Game Flow Provider (L3 Modular Slot Machine FSM)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<GameFlowProvider>(
      () => GameFlowProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 7.4: FluxMacro Provider (P-FMC Orchestration Engine)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<FluxMacroProvider>(
      () => FluxMacroProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 6.5: Advanced Loop System (depends on FFI)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<LoopProvider>(
      () => LoopProvider.instance,
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 7: Plugin State System (depends on FFI)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<PluginStateService>(
      () => PluginStateService.instance,
    );
    sl.registerLazySingleton<MissingPluginDetector>(
      () => MissingPluginDetector.instance,
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 7.5: Stage Flow Provider (P-DSF Dynamic Stage Flow Editor)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<StageFlowProvider>(
      () => StageFlowProvider(),
    );

    // Initialize plugin alternatives registry
    PluginAlternativesRegistry.instance.initBuiltInAlternatives();

    _initialized = true;
  }

  /// Reset all services (for testing)
  static Future<void> reset() async {
    await sl.reset();
    _initialized = false;
  }

  /// Check if initialized
  static bool get isInitialized => _initialized;

  /// Initialize search providers (P0.1 fix)
  static void _initializeSearchProviders() {
    final search = sl<UnifiedSearchService>();

    // Register built-in providers (no init required)
    search.registerProvider(HelpSearchProvider());
    search.registerProvider(RecentSearchProvider());

    // P2: Register data-driven providers (init() called later in EngineConnectedLayout)
    // These need callbacks to access Provider data, so we register empty instances here
    // and call init() in engine_connected_layout.dart when context is available.
    search.registerProvider(FileSearchProvider());
    search.registerProvider(TrackSearchProvider());
    search.registerProvider(PresetSearchProvider());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVENIENCE EXTENSIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Extension for easy service access in any class
extension ServiceLocatorExtension on Object {
  /// Get a registered service
  T getService<T extends Object>() => sl<T>();
}
