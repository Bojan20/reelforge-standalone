// ═══════════════════════════════════════════════════════════════════════════════
// STAGE INGEST PROVIDER — Universal Stage System
// ═══════════════════════════════════════════════════════════════════════════════
//
// P5.5: Complete Flutter provider for rf-stage, rf-ingest, rf-connector.
// Slot-agnostic game engine integration via canonical STAGES.
//
// Philosophy: FluxForge never understands engine-specific events — only STAGES.
// All slot games pass through the same semantic phases:
//   Spin starts → Reels stop → Wins evaluated → Features triggered
//
// Three-layer architecture:
// - Layer 1: Direct Event (engine has event log → direct mapping)
// - Layer 2: Snapshot Diff (engine has pre/post state → diff derivation)
// - Layer 3: Rule-Based (generic events → heuristic stage reconstruction)
//
// Two operation modes:
// - OFFLINE: JSON import → Adapter Wizard → StageTrace → Audio design
// - LIVE: WebSocket/TCP → Real-time STAGES → Live audio preview

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import '../services/service_locator.dart';
import '../services/mock_engine_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Ingest layer type
enum IngestLayer {
  directEvent,   // Layer 1: Engine has event log
  snapshotDiff,  // Layer 2: Engine has pre/post state
  ruleBased,     // Layer 3: Heuristic stage derivation
}

/// Timing profile
enum TimingProfile {
  normal,   // Standard slot timing
  turbo,    // Fast spin mode
  mobile,   // Mobile-optimized
  instant,  // Instant results (testing)
  studio,   // Audio design mode
}

/// Connection state
enum ConnectorState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Connection protocol
enum ConnectorProtocol {
  websocket,
  tcp,
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Registered adapter info
class AdapterInfo {
  final String adapterId;
  final String companyName;
  final String engineName;
  final List<String> supportedLayers;

  AdapterInfo({
    required this.adapterId,
    required this.companyName,
    required this.engineName,
    required this.supportedLayers,
  });

  factory AdapterInfo.fromJson(Map<String, dynamic> json) {
    return AdapterInfo(
      adapterId: json['adapter_id'] as String? ?? '',
      companyName: json['company_name'] as String? ?? '',
      engineName: json['engine_name'] as String? ?? '',
      supportedLayers: (json['supported_layers'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// Stage trace wrapper
class StageTraceHandle {
  final int handle;
  final String traceId;
  final String gameId;
  int _eventCount = 0;
  double _durationMs = 0;

  StageTraceHandle({
    required this.handle,
    required this.traceId,
    required this.gameId,
  });

  int get eventCount => _eventCount;
  double get durationMs => _durationMs;

  void updateStats(int eventCount, double durationMs) {
    _eventCount = eventCount;
    _durationMs = durationMs;
  }
}

/// Timed trace wrapper
class TimedTraceHandle {
  final int handle;
  final int sourceTraceHandle;
  final TimingProfile profile;
  double totalDurationMs = 0;

  TimedTraceHandle({
    required this.handle,
    required this.sourceTraceHandle,
    required this.profile,
  });
}

/// Ingest config wrapper
class IngestConfig {
  final int configId;
  final String adapterId;
  final String companyName;
  final String engineName;

  IngestConfig({
    required this.configId,
    required this.adapterId,
    required this.companyName,
    required this.engineName,
  });
}

/// Wizard analysis result
class WizardResult {
  final IngestConfig? config;
  final List<String> detectedFields;
  final List<String> suggestedMappings;
  final double confidence;
  final String? recommendedLayer;

  WizardResult({
    this.config,
    this.detectedFields = const [],
    this.suggestedMappings = const [],
    this.confidence = 0.0,
    this.recommendedLayer,
  });

  factory WizardResult.fromJson(Map<String, dynamic> json, int? configId) {
    return WizardResult(
      config: configId != null
          ? IngestConfig(
              configId: configId,
              adapterId: json['adapter_id'] as String? ?? 'auto',
              companyName: json['company_name'] as String? ?? 'Unknown',
              engineName: json['engine_name'] as String? ?? 'Unknown',
            )
          : null,
      detectedFields: (json['detected_fields'] as List?)?.cast<String>() ?? [],
      suggestedMappings: (json['suggested_mappings'] as List?)?.cast<String>() ?? [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      recommendedLayer: json['recommended_layer'] as String?,
    );
  }
}

/// Live connector handle
class ConnectorHandle {
  final int connectorId;
  final ConnectorProtocol protocol;
  final String address;
  ConnectorState state = ConnectorState.disconnected;
  bool isPolling = false;

  ConnectorHandle({
    required this.connectorId,
    required this.protocol,
    required this.address,
  });
}

/// Stage event from ingest system (decoded from JSON)
/// Named IngestStageEvent to avoid collision with stage_models.dart StageEvent
class IngestStageEvent {
  final String stage;
  final double timestampMs;
  final Map<String, dynamic> data;

  IngestStageEvent({
    required this.stage,
    required this.timestampMs,
    this.data = const {},
  });

  factory IngestStageEvent.fromJson(Map<String, dynamic> json) {
    return IngestStageEvent(
      stage: json['stage']?.toString() ?? 'Unknown',
      timestampMs: (json['timestamp_ms'] as num?)?.toDouble() ?? 0.0,
      data: json,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE INGEST PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for Stage Ingest System
///
/// Manages:
/// - Adapter registration and detection
/// - Ingest config creation and management
/// - Stage trace creation and manipulation
/// - Timing resolution
/// - Wizard for auto-config generation
/// - Live engine connections
class StageIngestProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Registered adapters
  final Map<String, AdapterInfo> _adapters = {};

  /// Active traces
  final Map<int, StageTraceHandle> _traces = {};

  /// Active timed traces
  final Map<int, TimedTraceHandle> _timedTraces = {};

  /// Active configs
  final Map<int, IngestConfig> _configs = {};

  /// Active wizards (wizard_id → sample count)
  final Map<int, int> _wizards = {};

  /// Active Rule Engines for Layer 3
  final Map<int, int> _ruleEngines = {}; // engine_id → event count

  /// Active connectors
  final Map<int, ConnectorHandle> _connectors = {};

  /// Current timing profile
  TimingProfile _timingProfile = TimingProfile.studio;

  /// Live event stream controller
  final StreamController<IngestStageEvent> _liveEventController =
      StreamController<IngestStageEvent>.broadcast();

  /// Polling timer for live events
  Timer? _pollingTimer;

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGING MODE STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Whether staging mode (mock engine) is active
  bool _isStagingMode = false;

  /// Mock engine subscription
  StreamSubscription<MockStageEvent>? _mockEngineSubscription;

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.2 URL VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validate WebSocket URL for security and format compliance
  bool _validateWebSocketUrl(String url) {
    if (url.isEmpty) {
      return false;
    }

    // Must have valid scheme
    final lowerUrl = url.toLowerCase();
    if (!lowerUrl.startsWith('ws://') && !lowerUrl.startsWith('wss://')) {
      return false;
    }

    // Try to parse as URI
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        return false;
      }
      // Validate port if specified
      if (uri.port < 0 || uri.port > 65535) {
        return false;
      }
    } catch (e) {
      return false;
    }

    // Block suspicious characters
    if (url.contains('\n') || url.contains('\r') || url.contains('\x00')) {
      return false;
    }

    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<AdapterInfo> get adapters => _adapters.values.toList();
  List<StageTraceHandle> get traces => _traces.values.toList();
  List<TimedTraceHandle> get timedTraces => _timedTraces.values.toList();
  List<IngestConfig> get configs => _configs.values.toList();
  List<ConnectorHandle> get connectors => _connectors.values.toList();
  TimingProfile get timingProfile => _timingProfile;
  int get adapterCount => _adapters.length;
  int get traceCount => _traces.length;
  int get configCount => _configs.length;
  int get connectorCount => _connectors.length;

  /// Stream of live stage events
  Stream<IngestStageEvent> get liveEvents => _liveEventController.stream;

  /// Whether staging mode is active
  bool get isStagingMode => _isStagingMode;

  /// Whether mock engine is running
  bool get isMockEngineRunning => MockEngineService.instance.isRunning;

  /// Mock engine mode
  MockEngineMode get mockEngineMode => MockEngineService.instance.mode;

  /// Mock engine context
  MockGameContext get mockGameContext => MockEngineService.instance.currentContext;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  StageIngestProvider(this._ffi) {
    _loadAdapters();
  }

  factory StageIngestProvider.fromServiceLocator() {
    return StageIngestProvider(sl<NativeFFI>());
  }

  @override
  void dispose() {
    // Clean up staging mode
    _mockEngineSubscription?.cancel();
    if (_isStagingMode) {
      MockEngineService.instance.stop();
    }

    // Clean up all resources
    _pollingTimer?.cancel();
    _liveEventController.close();

    // Destroy all traces
    for (final handle in _traces.keys.toList()) {
      _ffi.stageTraceDestroy(handle);
    }
    _traces.clear();

    // Destroy all timed traces
    for (final handle in _timedTraces.keys.toList()) {
      _ffi.stageTimedTraceDestroy(handle);
    }
    _timedTraces.clear();

    // Destroy all configs
    for (final id in _configs.keys.toList()) {
      _ffi.ingestConfigDestroy(id);
    }
    _configs.clear();

    // Destroy all wizards
    for (final id in _wizards.keys.toList()) {
      _ffi.ingestWizardDestroy(id);
    }
    _wizards.clear();

    // Destroy all rule engines
    for (final id in _ruleEngines.keys.toList()) {
      _ffi.ingestLayer3DestroyEngine(id);
    }
    _ruleEngines.clear();

    // Destroy all connectors
    for (final id in _connectors.keys.toList()) {
      _ffi.connectorDestroy(id);
    }
    _connectors.clear();

    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADAPTER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void _loadAdapters() {
    final ids = _ffi.ingestListAdapters();
    _adapters.clear();
    for (final id in ids) {
      final info = _ffi.ingestGetAdapterInfo(id);
      if (info != null) {
        _adapters[id] = AdapterInfo.fromJson(info);
      }
    }
  }

  /// Register adapter from JSON config
  bool registerAdapterJson(String jsonConfig) {
    final result = _ffi.ingestRegisterAdapterJson(jsonConfig);
    if (result) {
      _loadAdapters();
      notifyListeners();
    }
    return result;
  }

  /// Register adapter from TOML config
  bool registerAdapterToml(String tomlConfig) {
    final result = _ffi.ingestRegisterAdapterToml(tomlConfig);
    if (result) {
      _loadAdapters();
      notifyListeners();
    }
    return result;
  }

  /// Unregister adapter
  bool unregisterAdapter(String adapterId) {
    final result = _ffi.ingestUnregisterAdapter(adapterId);
    if (result) {
      _adapters.remove(adapterId);
      notifyListeners();
    }
    return result;
  }

  /// Auto-detect adapter for JSON sample
  String? detectAdapter(String sampleJson) {
    return _ffi.ingestDetectAdapter(sampleJson);
  }

  /// Check if adapter exists
  bool adapterExists(String adapterId) {
    return _ffi.ingestAdapterExists(adapterId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new stage trace
  StageTraceHandle? createTrace(String traceId, String gameId) {
    final handle = _ffi.stageTraceCreate(traceId, gameId);
    if (handle == 0) return null;

    final traceHandle = StageTraceHandle(
      handle: handle,
      traceId: traceId,
      gameId: gameId,
    );
    _traces[handle] = traceHandle;
    notifyListeners();
    return traceHandle;
  }

  /// Load trace from JSON
  StageTraceHandle? loadTraceFromJson(String json) {
    final handle = _ffi.stageTraceFromJson(json);
    if (handle == 0) return null;

    // Parse JSON to get trace ID and game ID
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final traceHandle = StageTraceHandle(
        handle: handle,
        traceId: data['trace_id'] as String? ?? 'imported',
        gameId: data['game_id'] as String? ?? 'unknown',
      );
      traceHandle.updateStats(
        _ffi.stageTraceEventCount(handle),
        _ffi.stageTraceDurationMs(handle),
      );
      _traces[handle] = traceHandle;
      notifyListeners();
      return traceHandle;
    } catch (e) {
      _ffi.stageTraceDestroy(handle);
      return null;
    }
  }

  /// Destroy a trace
  void destroyTrace(int handle) {
    _ffi.stageTraceDestroy(handle);
    _traces.remove(handle);
    notifyListeners();
  }

  /// Add event to trace
  bool addEventToTrace(int handle, String eventJson) {
    final result = _ffi.stageTraceAddEvent(handle, eventJson);
    if (result && _traces.containsKey(handle)) {
      _traces[handle]!.updateStats(
        _ffi.stageTraceEventCount(handle),
        _ffi.stageTraceDurationMs(handle),
      );
      notifyListeners();
    }
    return result;
  }

  /// Add stage to trace
  bool addStageToTrace(int handle, String stageJson, double timestampMs) {
    final result = _ffi.stageTraceAddStage(handle, stageJson, timestampMs);
    if (result && _traces.containsKey(handle)) {
      _traces[handle]!.updateStats(
        _ffi.stageTraceEventCount(handle),
        _ffi.stageTraceDurationMs(handle),
      );
      notifyListeners();
    }
    return result;
  }

  /// Get trace as JSON
  String? getTraceJson(int handle) => _ffi.stageTraceToJson(handle);

  /// Get trace events
  List<IngestStageEvent> getTraceEvents(int handle) {
    final events = _ffi.stageTraceGetEventsJson(handle);
    if (events == null) return [];
    return events.map((e) => IngestStageEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Validate trace
  Map<String, dynamic>? validateTrace(int handle) => _ffi.stageTraceValidate(handle);

  /// Get trace summary
  Map<String, dynamic>? getTraceSummary(int handle) => _ffi.stageTraceSummary(handle);

  /// Check if trace has feature
  bool traceHasFeature(int handle) => _ffi.stageTraceHasFeature(handle);

  /// Check if trace has jackpot
  bool traceHasJackpot(int handle) => _ffi.stageTraceHasJackpot(handle);

  /// Get total win from trace
  double traceTotalWin(int handle) => _ffi.stageTraceTotalWin(handle);

  /// Get trace duration in ms
  double stageTraceDurationMs(int handle) => _ffi.stageTraceDurationMs(handle);

  // ═══════════════════════════════════════════════════════════════════════════
  // INGEST API (JSON → Stage Trace)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ingest JSON using specific adapter
  StageTraceHandle? ingestJson(String adapterId, String jsonData) {
    final handle = _ffi.ingestParseJson(adapterId, jsonData);
    if (handle == 0) return null;

    final traceHandle = StageTraceHandle(
      handle: handle,
      traceId: 'ingest-${DateTime.now().millisecondsSinceEpoch}',
      gameId: adapterId,
    );
    traceHandle.updateStats(
      _ffi.stageTraceEventCount(handle),
      _ffi.stageTraceDurationMs(handle),
    );
    _traces[handle] = traceHandle;
    notifyListeners();
    return traceHandle;
  }

  /// Ingest JSON using auto-detected adapter
  StageTraceHandle? ingestJsonAuto(String jsonData) {
    final handle = _ffi.ingestParseJsonAuto(jsonData);
    if (handle == 0) return null;

    final traceHandle = StageTraceHandle(
      handle: handle,
      traceId: 'auto-${DateTime.now().millisecondsSinceEpoch}',
      gameId: 'auto-detected',
    );
    traceHandle.updateStats(
      _ffi.stageTraceEventCount(handle),
      _ffi.stageTraceDurationMs(handle),
    );
    _traces[handle] = traceHandle;
    notifyListeners();
    return traceHandle;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER-SPECIFIC INGEST
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse JSON using Layer 1 (Direct Event)
  StageTraceHandle? ingestLayer1(String jsonData, int configId) {
    final handle = _ffi.ingestLayer1Parse(jsonData, configId);
    if (handle == 0) return null;

    final traceHandle = StageTraceHandle(
      handle: handle,
      traceId: 'layer1-${DateTime.now().millisecondsSinceEpoch}',
      gameId: 'direct-event',
    );
    traceHandle.updateStats(
      _ffi.stageTraceEventCount(handle),
      _ffi.stageTraceDurationMs(handle),
    );
    _traces[handle] = traceHandle;
    notifyListeners();
    return traceHandle;
  }

  /// Parse JSON using Layer 2 (Snapshot Diff)
  StageTraceHandle? ingestLayer2(List<Map<String, dynamic>> snapshots, int configId) {
    final json = jsonEncode(snapshots);
    final handle = _ffi.ingestLayer2Parse(json, configId);
    if (handle == 0) return null;

    final traceHandle = StageTraceHandle(
      handle: handle,
      traceId: 'layer2-${DateTime.now().millisecondsSinceEpoch}',
      gameId: 'snapshot-diff',
    );
    traceHandle.updateStats(
      _ffi.stageTraceEventCount(handle),
      _ffi.stageTraceDurationMs(handle),
    );
    _traces[handle] = traceHandle;
    notifyListeners();
    return traceHandle;
  }

  /// Create a Rule Engine for Layer 3
  int createRuleEngine() {
    final engineId = _ffi.ingestLayer3CreateEngine();
    if (engineId > 0) {
      _ruleEngines[engineId] = 0;
      notifyListeners();
    }
    return engineId;
  }

  /// Destroy a Rule Engine
  void destroyRuleEngine(int engineId) {
    _ffi.ingestLayer3DestroyEngine(engineId);
    _ruleEngines.remove(engineId);
    notifyListeners();
  }

  /// Process data through Rule Engine
  List<IngestStageEvent> processLayer3(int engineId, String jsonData, double timestampMs) {
    final events = _ffi.ingestLayer3Process(engineId, jsonData, timestampMs);
    if (events == null) return [];

    if (_ruleEngines.containsKey(engineId)) {
      _ruleEngines[engineId] = _ruleEngines[engineId]! + events.length;
    }

    return events.map((e) => IngestStageEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Reset Rule Engine state
  void resetRuleEngine(int engineId) {
    _ffi.ingestLayer3Reset(engineId);
    if (_ruleEngines.containsKey(engineId)) {
      _ruleEngines[engineId] = 0;
    }
    notifyListeners();
  }

  /// Get all detected stages from Rule Engine
  List<IngestStageEvent> getRuleEngineStages(int engineId) {
    final stages = _ffi.ingestLayer3GetStages(engineId);
    if (stages == null) return [];
    return stages.map((e) => IngestStageEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Build trace from Rule Engine stages
  StageTraceHandle? buildTraceFromRuleEngine(int engineId, String traceId, String gameId) {
    final handle = _ffi.ingestLayer3BuildTrace(engineId, traceId, gameId);
    if (handle == 0) return null;

    final traceHandle = StageTraceHandle(
      handle: handle,
      traceId: traceId,
      gameId: gameId,
    );
    traceHandle.updateStats(
      _ffi.stageTraceEventCount(handle),
      _ffi.stageTraceDurationMs(handle),
    );
    _traces[handle] = traceHandle;
    notifyListeners();
    return traceHandle;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIG MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create config from JSON
  IngestConfig? createConfigFromJson(String jsonConfig) {
    final configId = _ffi.ingestConfigCreateJson(jsonConfig);
    if (configId == 0) return null;

    try {
      final data = jsonDecode(jsonConfig) as Map<String, dynamic>;
      final config = IngestConfig(
        configId: configId,
        adapterId: data['adapter_id'] as String? ?? 'custom',
        companyName: data['company_name'] as String? ?? 'Unknown',
        engineName: data['engine_name'] as String? ?? 'Unknown',
      );
      _configs[configId] = config;
      notifyListeners();
      return config;
    } catch (e) {
      _ffi.ingestConfigDestroy(configId);
      return null;
    }
  }

  /// Create default config
  IngestConfig createDefaultConfig() {
    final configId = _ffi.ingestConfigCreateDefault();
    final config = IngestConfig(
      configId: configId,
      adapterId: 'default',
      companyName: 'Default',
      engineName: 'Generic',
    );
    _configs[configId] = config;
    notifyListeners();
    return config;
  }

  /// Create config with basic info
  IngestConfig? createConfig(String adapterId, String companyName, String engineName) {
    final configId = _ffi.ingestConfigCreate(adapterId, companyName, engineName);
    if (configId == 0) return null;

    final config = IngestConfig(
      configId: configId,
      adapterId: adapterId,
      companyName: companyName,
      engineName: engineName,
    );
    _configs[configId] = config;
    notifyListeners();
    return config;
  }

  /// Destroy config
  void destroyConfig(int configId) {
    _ffi.ingestConfigDestroy(configId);
    _configs.remove(configId);
    notifyListeners();
  }

  /// Get config as JSON
  String? getConfigJson(int configId) => _ffi.ingestConfigToJson(configId);

  /// Get config as TOML
  String? getConfigToml(int configId) => _ffi.ingestConfigToToml(configId);

  /// Add event mapping to config
  bool addEventMapping(int configId, String eventName, String stageName) {
    return _ffi.ingestConfigAddEventMapping(configId, eventName, stageName);
  }

  /// Set payload path in config
  bool setPayloadPath(int configId, String pathType, String jsonPath) {
    return _ffi.ingestConfigSetPayloadPath(configId, pathType, jsonPath);
  }

  /// Set snapshot path in config
  bool setSnapshotPath(int configId, String pathType, String jsonPath) {
    return _ffi.ingestConfigSetSnapshotPath(configId, pathType, jsonPath);
  }

  /// Set big win thresholds
  bool setBigwinThresholds(int configId, {
    double win = 5.0,
    double bigWin = 15.0,
    double megaWin = 30.0,
    double epicWin = 50.0,
    double ultraWin = 100.0,
  }) {
    return _ffi.ingestConfigSetBigwinThresholds(
      configId, win, bigWin, megaWin, epicWin, ultraWin,
    );
  }

  /// Validate config
  bool validateConfig(int configId) => _ffi.ingestConfigValidate(configId);

  // ═══════════════════════════════════════════════════════════════════════════
  // WIZARD API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create wizard instance
  int createWizard() {
    final wizardId = _ffi.ingestWizardCreate();
    if (wizardId > 0) {
      _wizards[wizardId] = 0;
      notifyListeners();
    }
    return wizardId;
  }

  /// Destroy wizard instance
  void destroyWizard(int wizardId) {
    _ffi.ingestWizardDestroy(wizardId);
    _wizards.remove(wizardId);
    notifyListeners();
  }

  /// Add sample to wizard
  bool addSampleToWizard(int wizardId, Map<String, dynamic> sample) {
    final json = jsonEncode(sample);
    final result = _ffi.ingestWizardAddSample(wizardId, json);
    if (result && _wizards.containsKey(wizardId)) {
      _wizards[wizardId] = _wizards[wizardId]! + 1;
      notifyListeners();
    }
    return result;
  }

  /// Add multiple samples to wizard
  int addSamplesToWizard(int wizardId, List<Map<String, dynamic>> samples) {
    final count = _ffi.ingestWizardAddSamples(wizardId, samples);
    if (count > 0 && _wizards.containsKey(wizardId)) {
      _wizards[wizardId] = _wizards[wizardId]! + count;
      notifyListeners();
    }
    return count;
  }

  /// Clear samples from wizard
  void clearWizardSamples(int wizardId) {
    _ffi.ingestWizardClearSamples(wizardId);
    if (_wizards.containsKey(wizardId)) {
      _wizards[wizardId] = 0;
      notifyListeners();
    }
  }

  /// Get wizard sample count
  int getWizardSampleCount(int wizardId) => _wizards[wizardId] ?? 0;

  /// Run wizard analysis
  WizardResult? analyzeWizard(int wizardId) {
    final result = _ffi.ingestWizardAnalyze(wizardId);
    if (result == null) return null;

    final configId = _ffi.ingestWizardGenerateConfig(wizardId);
    return WizardResult.fromJson(result, configId > 0 ? configId : null);
  }

  /// Generate config from wizard (returns config ID)
  int generateConfigFromWizard(int wizardId) {
    final configId = _ffi.ingestWizardGenerateConfig(wizardId);
    if (configId > 0) {
      final json = _ffi.ingestConfigToJson(configId);
      if (json != null) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          _configs[configId] = IngestConfig(
            configId: configId,
            adapterId: data['adapter_id'] as String? ?? 'wizard',
            companyName: data['company_name'] as String? ?? 'Auto-detected',
            engineName: data['engine_name'] as String? ?? 'Auto-detected',
          );
          notifyListeners();
        } catch (_) { /* ignored */ }
      }
    }
    return configId;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING RESOLVER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set timing profile
  void setTimingProfile(TimingProfile profile) {
    _timingProfile = profile;
    notifyListeners();
  }

  /// Get timing config for a profile
  Map<String, dynamic>? getTimingConfig(TimingProfile profile) {
    return _ffi.stageTimingGetConfig(_profileToString(profile));
  }

  /// Set custom timing config
  bool setTimingConfig(Map<String, dynamic> config) {
    return _ffi.stageTimingSetConfig(config);
  }

  /// Resolve timing for a trace
  TimedTraceHandle? resolveTiming(int traceHandle, {TimingProfile? profile}) {
    profile ??= _timingProfile;
    final handle = _ffi.stageTimingResolve(traceHandle, _profileToString(profile));
    if (handle == 0) return null;

    final timedHandle = TimedTraceHandle(
      handle: handle,
      sourceTraceHandle: traceHandle,
      profile: profile,
    );
    timedHandle.totalDurationMs = _ffi.stageTimedTraceDurationMs(handle);
    _timedTraces[handle] = timedHandle;
    notifyListeners();
    return timedHandle;
  }

  /// Destroy timed trace
  void destroyTimedTrace(int handle) {
    _ffi.stageTimedTraceDestroy(handle);
    _timedTraces.remove(handle);
    notifyListeners();
  }

  /// Get timed trace as JSON
  String? getTimedTraceJson(int handle) => _ffi.stageTimedTraceToJson(handle);

  /// Get timed trace duration
  double getTimedTraceDuration(int handle) => _ffi.stageTimedTraceDurationMs(handle);

  /// Get events at specific time
  List<IngestStageEvent> getEventsAt(int handle, double timeMs) {
    final events = _ffi.stageTimedTraceEventsAt(handle, timeMs);
    if (events == null) return [];
    return events.map((e) => IngestStageEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get stage at specific time
  IngestStageEvent? getStageAt(int handle, double timeMs) {
    final event = _ffi.stageTimedTraceStageAt(handle, timeMs);
    if (event == null) return null;
    return IngestStageEvent.fromJson(event);
  }

  String _profileToString(TimingProfile profile) {
    switch (profile) {
      case TimingProfile.normal: return 'normal';
      case TimingProfile.turbo: return 'turbo';
      case TimingProfile.mobile: return 'mobile';
      case TimingProfile.instant: return 'instant';
      case TimingProfile.studio: return 'studio';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIVE CONNECTION API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create WebSocket connector (P2.2 FIX: validates URL before connecting)
  ConnectorHandle? createWebSocketConnector(String url) {
    // P2.2 SECURITY: Validate URL before creating connector
    if (!_validateWebSocketUrl(url)) {
      return null;
    }

    final connectorId = _ffi.connectorCreateWebsocket(url);
    if (connectorId == 0) return null;

    final handle = ConnectorHandle(
      connectorId: connectorId,
      protocol: ConnectorProtocol.websocket,
      address: url,
    );
    _connectors[connectorId] = handle;
    notifyListeners();
    return handle;
  }

  /// Create TCP connector
  ConnectorHandle? createTcpConnector(String host, int port) {
    final connectorId = _ffi.connectorCreateTcp(host, port);
    if (connectorId == 0) return null;

    final handle = ConnectorHandle(
      connectorId: connectorId,
      protocol: ConnectorProtocol.tcp,
      address: '$host:$port',
    );
    _connectors[connectorId] = handle;
    notifyListeners();
    return handle;
  }

  /// Destroy connector
  void destroyConnector(int connectorId) {
    _ffi.connectorDestroy(connectorId);
    _connectors.remove(connectorId);
    notifyListeners();
  }

  /// Connect to engine
  bool connect(int connectorId) {
    final result = _ffi.connectorConnect(connectorId);
    if (result && _connectors.containsKey(connectorId)) {
      _connectors[connectorId]!.state = ConnectorState.connecting;
      notifyListeners();
    }
    return result;
  }

  /// Disconnect from engine
  bool disconnect(int connectorId) {
    final result = _ffi.connectorDisconnect(connectorId);
    if (result && _connectors.containsKey(connectorId)) {
      _connectors[connectorId]!.state = ConnectorState.disconnected;
      _connectors[connectorId]!.isPolling = false;
      notifyListeners();
    }
    return result;
  }

  /// Check if connected
  bool isConnected(int connectorId) => _ffi.connectorIsConnected(connectorId);

  /// Get connection state
  ConnectorState getConnectionState(int connectorId) {
    final state = _ffi.connectorGetState(connectorId);
    if (state == null) return ConnectorState.disconnected;

    if (state['is_connected'] == true) return ConnectorState.connected;
    if (state['is_connecting'] == true) return ConnectorState.connecting;
    if (state['is_reconnecting'] == true) return ConnectorState.reconnecting;
    if (state['is_error'] == true) return ConnectorState.error;
    return ConnectorState.disconnected;
  }

  /// Update connection state
  void updateConnectionState(int connectorId) {
    if (!_connectors.containsKey(connectorId)) return;

    final newState = getConnectionState(connectorId);
    if (_connectors[connectorId]!.state != newState) {
      _connectors[connectorId]!.state = newState;
      notifyListeners();
    }
  }

  /// Start event polling
  void startEventPolling(int connectorId, {Duration interval = const Duration(milliseconds: 16)}) {
    if (!_connectors.containsKey(connectorId)) return;

    _ffi.connectorStartEventPolling(connectorId);
    _connectors[connectorId]!.isPolling = true;

    // Start polling timer
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) {
      _pollEvents(connectorId);
    });

    notifyListeners();
  }

  /// Stop event polling
  void stopEventPolling(int connectorId) {
    if (!_connectors.containsKey(connectorId)) return;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _connectors[connectorId]!.isPolling = false;
    notifyListeners();
  }

  /// Max events to process per poll tick (P2.1 FIX: prevents UI jank)
  static const int _kMaxEventsPerPoll = 100;

  void _pollEvents(int connectorId) {
    // P2.1 FIX: Bounded loop to prevent UI jank with many events
    var processed = 0;
    while (processed < _kMaxEventsPerPoll) {
      final event = _ffi.connectorPollEvent(connectorId);
      if (event == null) break;

      final stageEvent = IngestStageEvent.fromJson(event);
      _liveEventController.add(stageEvent);
      processed++;
    }

    // Log if we hit the limit (may indicate backpressure)
    if (processed >= _kMaxEventsPerPoll) {
    }
  }

  /// Get pending event count
  int getEventCount(int connectorId) => _ffi.connectorEventCount(connectorId);

  // --- Commands ---

  /// Send play spin command
  bool playSpin(int connectorId, String spinId) {
    return _ffi.connectorPlaySpin(connectorId, spinId);
  }

  /// Send pause command
  bool pauseEngine(int connectorId) => _ffi.connectorPause(connectorId);

  /// Send resume command
  bool resumeEngine(int connectorId) => _ffi.connectorResume(connectorId);

  /// Send stop command
  bool stopEngine(int connectorId) => _ffi.connectorStop(connectorId);

  /// Send seek command
  bool seekEngine(int connectorId, double timestampMs) {
    return _ffi.connectorSeek(connectorId, timestampMs);
  }

  /// Set playback speed
  bool setSpeed(int connectorId, double speed) {
    return _ffi.connectorSetSpeed(connectorId, speed);
  }

  /// Set timing profile on connected engine
  bool setEngineTimingProfile(int connectorId, TimingProfile profile) {
    return _ffi.connectorSetTimingProfile(connectorId, _profileToString(profile));
  }

  /// Trigger event (for testing)
  bool triggerEvent(int connectorId, String eventName, {Map<String, dynamic>? payload}) {
    return _ffi.connectorTriggerEvent(connectorId, eventName, payload);
  }

  /// Set parameter
  bool setParameter(int connectorId, String name, dynamic value) {
    return _ffi.connectorSetParameter(connectorId, name, value);
  }

  /// Get capabilities
  Map<String, dynamic>? getCapabilities(int connectorId) {
    return _ffi.connectorGetCapabilities(connectorId);
  }

  /// Check if command is supported
  bool supportsCommand(int connectorId, String commandName) {
    return _ffi.connectorSupportsCommand(connectorId, commandName);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get supported ingest layers
  List<String> getSupportedLayers() => _ffi.ingestGetLayers();

  /// Validate JSON structure
  Map<String, dynamic>? validateJson(String jsonData) {
    return _ffi.ingestValidateJson(jsonData);
  }

  /// Create stage event helpers
  String? createSpinStartEvent(double timestampMs) =>
      _ffi.stageCreateSpinStart(timestampMs);

  String? createSpinEndEvent(double timestampMs) =>
      _ffi.stageCreateSpinEnd(timestampMs);

  String? createReelStopEvent(int reelIndex, List<String> symbols, double timestampMs) =>
      _ffi.stageCreateReelStop(reelIndex, symbols, timestampMs);

  String? createWinPresentEvent(double winAmount, int lineCount, double timestampMs) =>
      _ffi.stageCreateWinPresent(winAmount, lineCount, timestampMs);

  /// Clear all resources
  void clearAll() {
    // Destroy all traces
    for (final handle in _traces.keys.toList()) {
      _ffi.stageTraceDestroy(handle);
    }
    _traces.clear();

    // Destroy all timed traces
    for (final handle in _timedTraces.keys.toList()) {
      _ffi.stageTimedTraceDestroy(handle);
    }
    _timedTraces.clear();

    // Destroy all connectors
    for (final id in _connectors.keys.toList()) {
      _ffi.connectorDestroy(id);
    }
    _connectors.clear();

    _pollingTimer?.cancel();
    _pollingTimer = null;

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGING MODE API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable staging mode (mock engine)
  /// This disconnects any live connections and starts the mock engine
  void enableStagingMode() {
    if (_isStagingMode) return;

    // Disconnect any live connectors
    for (final connector in _connectors.values) {
      disconnect(connector.connectorId);
    }

    _isStagingMode = true;

    // Subscribe to mock engine events
    _mockEngineSubscription = MockEngineService.instance.events.listen((event) {
      // Convert MockStageEvent to IngestStageEvent and emit
      final ingestEvent = IngestStageEvent(
        stage: event.stage,
        timestampMs: event.timestampMs,
        data: event.data,
      );
      _liveEventController.add(ingestEvent);
    });

    notifyListeners();
  }

  /// Disable staging mode
  void disableStagingMode() {
    if (!_isStagingMode) return;

    _isStagingMode = false;

    // Stop mock engine
    MockEngineService.instance.stop();

    // Unsubscribe from mock events
    _mockEngineSubscription?.cancel();
    _mockEngineSubscription = null;

    notifyListeners();
  }

  /// Toggle staging mode
  void toggleStagingMode() {
    if (_isStagingMode) {
      disableStagingMode();
    } else {
      enableStagingMode();
    }
  }

  /// Start mock engine (only if staging mode is enabled)
  void startMockEngine() {
    if (!_isStagingMode) {
      enableStagingMode();
    }
    MockEngineService.instance.start();
    notifyListeners();
  }

  /// Stop mock engine
  void stopMockEngine() {
    MockEngineService.instance.stop();
    notifyListeners();
  }

  /// Set mock engine mode
  void setMockEngineMode(MockEngineMode mode) {
    MockEngineService.instance.setMode(mode);
    notifyListeners();
  }

  /// Set mock engine context
  void setMockEngineContext(MockGameContext context) {
    MockEngineService.instance.setContext(context);
    notifyListeners();
  }

  /// Set mock engine config
  void setMockEngineConfig(MockEngineConfig config) {
    MockEngineService.instance.config = config;
    notifyListeners();
  }

  /// Trigger manual spin in mock engine
  void triggerMockSpin() {
    if (!_isStagingMode) return;
    MockEngineService.instance.triggerSpin();
  }

  /// Trigger spin with specific outcome
  void triggerMockSpinWithOutcome(MockWinTier outcome) {
    if (!_isStagingMode) return;
    MockEngineService.instance.triggerSpinWithOutcome(outcome);
  }

  /// Play predefined sequence
  void playMockSequence(MockEventSequence sequence) {
    if (!_isStagingMode) return;
    MockEngineService.instance.playSequence(sequence);
  }
}
