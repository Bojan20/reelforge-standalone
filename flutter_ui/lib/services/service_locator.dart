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
import '../providers/slot_lab/slot_voice_mixer_provider.dart';
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
import '../providers/slot_lab/helix_bt_canvas_provider.dart';
import '../providers/slot_lab/state_gate_provider.dart';
import '../providers/slot_lab/emotional_state_provider.dart';
import '../providers/slot_lab/transition_system_provider.dart';
import '../providers/slot_lab/tempo_state_provider.dart';
import '../providers/slot_lab/priority_engine_provider.dart';
import '../providers/slot_lab/orchestration_engine_provider.dart';
import '../providers/slot_lab/ail_provider.dart';
import '../providers/slot_lab/drc_provider.dart';
import '../providers/slot_lab/sam_provider.dart';
import '../providers/slot_lab/simulation_engine_provider.dart';
import '../providers/slot_lab/error_prevention_provider.dart';
import '../providers/slot_lab/config_undo_manager.dart';
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
import '../providers/slot_lab/neuro_audio_provider.dart';
import '../providers/slot_lab/math_audio_bridge_provider.dart';
import '../providers/slot_lab/rgai_provider.dart';
import '../providers/slot_lab/ucp_export_provider.dart';
import '../providers/slot_lab/ab_test_provider.dart';
import '../providers/slot_lab/neural_fingerprint_provider.dart';
import '../providers/slot_lab/spatial_audio_provider.dart';
import '../providers/slot_lab/ai_copilot_provider.dart';
import '../providers/slot_lab/game_flow_provider.dart';
import '../providers/rgai_ffi_provider.dart';
import '../providers/slot_spatial_provider.dart';
import '../providers/ab_sim_provider.dart';
import '../providers/slot_export_provider.dart';
import '../providers/sfx_pipeline_provider.dart';
import 'rgar_report_service.dart';
import '../providers/fluxmacro_provider.dart';
import '../providers/slot_lab/stage_flow_provider.dart';
import '../providers/video_provider.dart';
import '../providers/middleware_provider.dart';
import '../providers/slot_lab/slot_lab_coordinator.dart';
import 'video_export_service.dart';
import 'video_playback_service.dart';
import '../providers/custom_event_provider.dart';
import '../providers/cortex_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/timeline_playback_provider.dart';
import '../providers/mixer_dsp_provider.dart';
import '../providers/meter_provider.dart';
import '../providers/mixer_provider.dart';
import '../providers/orb_mixer_provider.dart';
import '../providers/editor_mode_provider.dart';
import '../providers/global_shortcuts_provider.dart';
import '../providers/project_history_provider.dart';
import '../providers/auto_save_provider.dart';
import '../providers/recent_projects_provider.dart';
import '../providers/audio_export_provider.dart';
import '../providers/session_persistence_provider.dart';
import '../providers/input_bus_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/routing_provider.dart';
import '../providers/keyboard_focus_provider.dart';
import '../providers/edit_mode_pro_provider.dart';
import '../providers/smart_tool_provider.dart';
import '../providers/razor_edit_provider.dart';
import '../providers/direct_offline_processing_provider.dart';
import '../providers/modulator_provider.dart';
import '../providers/arranger_track_provider.dart';
import '../providers/chord_track_provider.dart';
import '../providers/expression_map_provider.dart';
import '../providers/macro_control_provider.dart';
import '../providers/track_versions_provider.dart';
import '../providers/clip_gain_envelope_provider.dart';
import '../providers/logical_editor_provider.dart';
import '../providers/groove_quantize_provider.dart';
import '../providers/audio_alignment_provider.dart';
import '../providers/scale_assistant_provider.dart';
import '../providers/error_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/control_room_provider.dart';
import '../providers/stage_provider.dart';
import '../providers/stage_ingest_provider.dart';
import '../providers/soundbank_provider.dart';
import '../providers/warp_state_provider.dart';
import 'extension_sdk_service.dart';
import 'hook_graph/hook_graph_service.dart';
import '../models/slot_audio_events.dart' show SlotCompositeEvent;
import 'par_import_service.dart'; // T2.1
import 'batch_sim_service.dart'; // T2.3
import 'math_audio_bridge_service.dart'; // T2.5+T2.8
import 'voice_budget_analyzer_service.dart'; // T2.6
import 'slot_lab_export_service.dart'; // T3.1–T3.6
import 'neuro_audio_service.dart'; // T4.1–T4.2
import 'ai_copilot_service.dart'; // T5.1–T5.4
import 'fingerprint_service.dart'; // T6.1–T6.5
import 'project_history_service.dart'; // T7.1
import 'spatial_audio_service.dart'; // T7.2–T7.4
import 'ai_generation_service.dart'; // T8.1–T8.4

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
    // LAYER 1b: Hook Graph Engine (initialized immediately after FFI)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<HookGraphService>(() {
      final svc = HookGraphService.instance;
      svc.initialize(); // starts 60Hz Ticker
      return svc;
    });

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
    sl.registerLazySingleton<SlotVoiceMixerProvider>(
      () => SlotVoiceMixerProvider(
        compositeProvider: sl<CompositeEventSystemProvider>(),
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
    // LAYER 5.5.0: MiddlewareProvider (States, Switches, RTPC, Ducking)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<MiddlewareProvider>(
      () => MiddlewareProvider(NativeFFI.instance),
    );

    // T1.4+T1.6: CompositeEventAccessor — thin bridge for RgarReportService
    sl.registerLazySingleton<CompositeEventAccessor>(
      () => _MiddlewareCompositeEventAccessor(sl<MiddlewareProvider>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.5.0b: SlotLabCoordinator (Slot Lab main coordinator)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabCoordinator>(
      () => SlotLabCoordinator(),
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

    sl.registerLazySingleton<HelixBtCanvasProvider>(
      () => HelixBtCanvasProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.7: State Gate Provider (SlotLab Middleware §4)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<StateGateProvider>(
      () => StateGateProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.9: Emotional State Provider (SlotLab Middleware §9)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<EmotionalStateProvider>(
      () => EmotionalStateProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10: NeuroAudio™ Provider (STUB1 — AI Player Behavioral Adaptation)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<NeuroAudioProvider>(
      () => NeuroAudioProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10b: MathAudio Bridge™ Provider (STUB2 — Math → Audio Map)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<MathAudioBridgeProvider>(
      () => MathAudioBridgeProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10c: RGAI™ Provider (STUB3 — Responsible Gaming Audio Intelligence)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<RgaiProvider>(
      () => RgaiProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10c-2: RGAR Report Service (T1.4 + T1.6 — auto-analysis + export)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<RgarReportService>(
      () => RgarReportService(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10d: UCP Export™ Provider (STUB5 — Universal Casino Protocol)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<UcpExportProvider>(
      () => UcpExportProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10e: PAR Import Service (T2.1 + T2.2)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<ParImportService>(() => ParImportService());

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10f: Batch Simulation Service (T2.3 + T2.4)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<BatchSimService>(() => BatchSimService());

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10g-BRIDGE: MathAudio Bridge Service (T2.5 + T2.8)
    // PAR → AudioEventMap + change notification system
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<MathAudioBridgeService>(
      () => MathAudioBridgeService(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10h-VOICE: Voice Budget Analyzer Service (T2.6)
    // Analytical peak voice prediction from AudioEventMap (Little's Law)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<VoiceBudgetAnalyzerService>(
      () => VoiceBudgetAnalyzerService(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10i-EXPORT: SlotLab Export Service (T3.1–T3.6)
    // UCP Export Engine — Howler.js / Wwise / FMOD / Generic JSON
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SlotLabExportService>(
      () => SlotLabExportService(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10j-NEURO: NeuroAudio Service (T4.1–T4.2)
    // Player Behavioral Signal Processor — 8D PSV + AudioAdaptation
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<NeuroAudioService>(
      () => NeuroAudioService(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10k-COPILOT: AI Co-Pilot Service (T5.1–T5.4)
    // Rule-based suggestion engine with industry benchmark database
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AiCopilotService>(
      () => AiCopilotService(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10l-FINGERPRINT: Neural Fingerprint™ Service (T6.1–T6.5)
    // SHA-256 bundle fingerprinting, A/B analytics, honeypot leak tracing
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<FingerprintService>(
      () => FingerprintService(sl<NativeFFI>()),
    );
    sl.registerLazySingleton<AbTestService>(
      () => AbTestService(sl<NativeFFI>()),
    );
    sl.registerLazySingleton<HoneypotService>(
      () => HoneypotService(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10m-HISTORY: Project History Service (T7.1)
    // Rust-backed Git-like versioning — commit/diff/checkout/log
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<ProjectHistoryService>(
      () => ProjectHistoryService(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10n-SPATIAL: Spatial Audio Service (T7.2–T7.4)
    // 3D slot audio scene + HRTF binaural + Ambisonics export
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SpatialAudioService>(
      () => SpatialAudioService(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10o-AI-GEN: AI Generation Service (T8.1–T8.4)
    // Procedural AI audio: prompt parsing, backend adapters, post-processing, FFNC classify
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AiGenerationService>(
      () => AiGenerationService(sl<NativeFFI>()),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10e: A/B Test™ Provider (STUB7 — A/B Testing Analytics Engine)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AbTestProvider>(
      () => AbTestProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10f: Neural Fingerprint™ Provider (STUB8 — Audio Watermarking)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<NeuralFingerprintProvider>(
      () => NeuralFingerprintProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10g: 3D Spatial Audio™ Provider (STUB9 — VR/AR Slot Audio)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<SpatialAudioProvider>(
      () => SpatialAudioProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10h: AI Co-Pilot™ Provider (STUB10 — Slot Audio AI Assistant)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<AiCopilotProvider>(
      () => AiCopilotProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.10-FFI: Real Rust FFI-backed providers (rf-rgai, rf-slot-spatial,
    // rf-ab-sim, rf-slot-export) — delegate to actual Rust engines via C FFI.
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<RgaiFfiProvider>(
      () => RgaiFfiProvider(ffi: sl.get<NativeFFI>()),
    );
    sl.registerLazySingleton<SlotSpatialProvider>(
      () => SlotSpatialProvider(ffi: sl.get<NativeFFI>()),
    );
    sl.registerLazySingleton<AbSimProvider>(
      () => AbSimProvider(ffi: sl.get<NativeFFI>()),
    );
    sl.registerLazySingleton<SlotExportProvider>(
      () => SlotExportProvider(ffi: sl.get<NativeFFI>()),
    );
    sl.registerLazySingleton<SfxPipelineProvider>(
      () => SfxPipelineProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.11: Transition System Provider (SlotLab Middleware §25)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<TransitionSystemProvider>(
      () => TransitionSystemProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 5.9.11b: Tempo State Provider (Rust TempoStateEngine bridge)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<TempoStateProvider>(
      () => TempoStateProvider(ffi: sl.get<NativeFFI>()),
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
    // LAYER 5.9.16b: Config Undo Manager (CONFIG tab undo/redo)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<ConfigUndoManager>(
      () => ConfigUndoManager(),
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

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 8: Video System
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<VideoProvider>(
      () => VideoProvider(),
    );
    sl.registerLazySingleton<VideoExportService>(
      () => VideoExportService.instance,
    );
    sl.registerLazySingleton<VideoPlaybackService>(
      () => VideoPlaybackService(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 8.1: Custom Event Provider (SlotLab CUSTOM tab)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<CustomEventProvider>(
      () => CustomEventProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 8.2: Extension SDK Service
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<ExtensionSdkService>(
      () => ExtensionSdkService.instance,
    );

    // =============================================================================
    // LAYER 9: CORTEX Provider (Reactive Nervous System State)
    // =============================================================================
    sl.registerLazySingleton<CortexProvider>(
      () => CortexProvider(),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER 10: DAW Core Providers (GetIt singletons — CLAUDE.md mandate)
    // These were previously created via ChangeNotifierProvider(create:) in main.dart.
    // Per CLAUDE.md: "Provideri MORAJU biti GetIt singletoni" to prevent
    // FFI resource duplication in Split View Lower Zone.
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<EngineProvider>(() => EngineProvider());
    sl.registerLazySingleton<TimelinePlaybackProvider>(
      () => TimelinePlaybackProvider(),
    );
    sl.registerLazySingleton<MixerDSPProvider>(() => MixerDSPProvider());
    sl.registerLazySingleton<MeterProvider>(() => MeterProvider());
    sl.registerLazySingleton<MixerProvider>(() => MixerProvider());
    sl.registerLazySingleton<OrbMixerProvider>(() => OrbMixerProvider(
          dsp: sl<MixerDSPProvider>(),
          meters: SharedMeterReader.instance,
        ));
    sl.registerLazySingleton<EditorModeProvider>(() => EditorModeProvider());
    sl.registerLazySingleton<GlobalShortcutsProvider>(
      () => GlobalShortcutsProvider(),
    );
    sl.registerLazySingleton<ProjectHistoryProvider>(
      () => ProjectHistoryProvider(),
    );
    sl.registerLazySingleton<AutoSaveProvider>(() => AutoSaveProvider());
    sl.registerLazySingleton<RecentProjectsProvider>(
      () => RecentProjectsProvider(),
    );
    sl.registerLazySingleton<AudioExportProvider>(() => AudioExportProvider());
    sl.registerLazySingleton<SessionPersistenceProvider>(
      () => SessionPersistenceProvider(),
    );
    sl.registerLazySingleton<InputBusProvider>(() => InputBusProvider());
    sl.registerLazySingleton<RecordingProvider>(() => RecordingProvider());
    sl.registerLazySingleton<RoutingProvider>(() => RoutingProvider());
    sl.registerLazySingleton<KeyboardFocusProvider>(
      () => KeyboardFocusProvider(),
    );
    sl.registerLazySingleton<EditModeProProvider>(() => EditModeProProvider());
    sl.registerLazySingleton<SmartToolProvider>(() => SmartToolProvider());
    sl.registerLazySingleton<RazorEditProvider>(() => RazorEditProvider());
    sl.registerLazySingleton<DirectOfflineProcessingProvider>(
      () => DirectOfflineProcessingProvider(),
    );
    sl.registerLazySingleton<ModulatorProvider>(() => ModulatorProvider());
    sl.registerLazySingleton<ArrangerTrackProvider>(
      () => ArrangerTrackProvider(),
    );
    sl.registerLazySingleton<ChordTrackProvider>(() => ChordTrackProvider());
    sl.registerLazySingleton<ExpressionMapProvider>(
      () => ExpressionMapProvider(),
    );
    sl.registerLazySingleton<MacroControlProvider>(
      () => MacroControlProvider(),
    );
    sl.registerLazySingleton<TrackVersionsProvider>(
      () => TrackVersionsProvider(),
    );
    sl.registerLazySingleton<ClipGainEnvelopeProvider>(
      () => ClipGainEnvelopeProvider(),
    );
    sl.registerLazySingleton<LogicalEditorProvider>(
      () => LogicalEditorProvider(),
    );
    sl.registerLazySingleton<GrooveQuantizeProvider>(
      () => GrooveQuantizeProvider(),
    );
    sl.registerLazySingleton<AudioAlignmentProvider>(
      () => AudioAlignmentProvider(),
    );
    sl.registerLazySingleton<ScaleAssistantProvider>(
      () => ScaleAssistantProvider(),
    );
    sl.registerLazySingleton<ErrorProvider>(() => ErrorProvider());
    sl.registerLazySingleton<PluginProvider>(() => PluginProvider());
    sl.registerLazySingleton<ControlRoomProvider>(() => ControlRoomProvider());
    sl.registerLazySingleton<StageProvider>(() => StageProvider());
    sl.registerLazySingleton<StageIngestProvider>(
      () => StageIngestProvider(sl<NativeFFI>()),
    );
    sl.registerLazySingleton<SoundbankProvider>(
      () => SoundbankProvider(sl<NativeFFI>()),
    );

    // Warp Markers State (Phase 4-5)
    sl.registerLazySingleton<WarpStateProvider>(() => WarpStateProvider());

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

// =============================================================================
// INTERNAL — CompositeEventAccessor implementation (T1.4 / T1.6)
// =============================================================================

/// Thin wrapper that lets RgarReportService read live composite events
/// from MiddlewareProvider without creating a circular dependency.
class _MiddlewareCompositeEventAccessor implements CompositeEventAccessor {
  final MiddlewareProvider _middleware;

  const _MiddlewareCompositeEventAccessor(this._middleware);

  @override
  List<SlotCompositeEvent> get events => _middleware.compositeEvents;
}
