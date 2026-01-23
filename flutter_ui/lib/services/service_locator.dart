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
      () => VoicePoolProvider(),
    );
    sl.registerLazySingleton<AttenuationCurveProvider>(
      () => AttenuationCurveProvider(ffi: sl<NativeFFI>()),
    );
    sl.registerLazySingleton<MemoryManagerProvider>(
      () => MemoryManagerProvider(),
    );
    sl.registerLazySingleton<EventProfilerProvider>(
      () => EventProfilerProvider(),
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
    // LAYER 6: UX Services (search, recent/favorites)
    // ═══════════════════════════════════════════════════════════════════════════
    sl.registerLazySingleton<UnifiedSearchService>(
      () => UnifiedSearchService.instance,
    );
    sl.registerLazySingleton<RecentFavoritesService>(
      () => RecentFavoritesService.instance,
    );

    // Initialize search providers
    _initializeSearchProviders();

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
