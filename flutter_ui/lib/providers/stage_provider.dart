/// Stage Provider — Universal Stage Ingest System for FluxForge
///
/// Manages:
/// - Offline mode: JSON import → Adapter Wizard → StageTrace
/// - Live mode: Engine connection → Real-time STAGES
/// - Timing resolution for audio preview
/// - Adapter registry management
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/stage_models.dart';
import '../services/live_engine_service.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STAGE PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Central provider for the Universal Stage Ingest System
class StageProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // ─── Current State ────────────────────────────────────────────────────────
  StageTrace? _currentTrace;
  TimedStageTrace? _currentTimedTrace;
  WizardResult? _wizardResult;
  List<AdapterInfo> _adapters = [];

  // ─── Live Mode State ──────────────────────────────────────────────────────
  final LiveEngineService _liveEngine = LiveEngineService.instance;
  EngineConnectionState _connectionState = EngineConnectionState.disconnected;
  ConnectionConfig? _connectionConfig;
  final List<StageEvent> _liveEvents = [];
  StreamSubscription<StageEvent>? _eventSubscription;
  StreamSubscription<EngineConnectionState>? _stateSubscription;

  // ─── Playback State ───────────────────────────────────────────────────────
  TimingProfile _timingProfile = TimingProfile.normal;
  double _playbackPosition = 0.0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  // ─── Throttling ───────────────────────────────────────────────────────────
  DateTime _lastNotifyTime = DateTime.now();
  static const _notifyThrottleMs = 50; // 20fps max

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  StageTrace? get currentTrace => _currentTrace;
  TimedStageTrace? get currentTimedTrace => _currentTimedTrace;
  WizardResult? get wizardResult => _wizardResult;
  List<AdapterInfo> get adapters => List.unmodifiable(_adapters);

  EngineConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == EngineConnectionState.connected;
  List<StageEvent> get liveEvents => List.unmodifiable(_liveEvents);

  TimingProfile get timingProfile => _timingProfile;
  double get playbackPosition => _playbackPosition;
  bool get isPlaying => _isPlaying;

  double get traceDuration => _currentTimedTrace?.totalDurationMs ?? 0.0;

  /// Get events at current playback position
  List<TimedStageEvent> get currentEvents {
    if (_currentTimedTrace == null) return [];
    return _currentTimedTrace!.eventsAt(_playbackPosition);
  }

  /// Get current stage at playback position
  TimedStageEvent? get currentStage =>
      _currentTimedTrace?.stageAt(_playbackPosition);

  // ═══════════════════════════════════════════════════════════════════════════
  // OFFLINE MODE — JSON IMPORT & WIZARD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import JSON data and run wizard analysis
  Future<WizardResult?> analyzeJson(String jsonString) async {
    try {
      // Call FFI wizard
      final success = _ffi.wizardAnalyzeJson(jsonString);
      if (!success) {
        debugPrint('[Stage] Wizard analysis failed');
        return null;
      }

      // Get wizard result
      _wizardResult = _getWizardResult();
      notifyListeners();
      return _wizardResult;
    } catch (e) {
      debugPrint('[Stage] Error analyzing JSON: $e');
      return null;
    }
  }

  /// Parse JSON with adapter and get StageTrace
  Future<StageTrace?> parseJson(String jsonString, {String? adapterId}) async {
    try {
      // Use wizard result's adapter if not specified
      final id = adapterId ?? _wizardResult?.detectedCompany ?? 'generic';

      final resultJson = _ffi.stageParseJson(jsonString, id);
      if (resultJson == null) {
        debugPrint('[Stage] Failed to parse JSON with adapter: $id');
        return null;
      }

      // Check for error in result
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        debugPrint('[Stage] Parse error: ${result['error']}');
        return null;
      }

      // Get trace from FFI
      _currentTrace = _getTraceFromFfi();
      if (_currentTrace != null) {
        _resolveTiming();
      }

      notifyListeners();
      return _currentTrace;
    } catch (e) {
      debugPrint('[Stage] Error parsing JSON: $e');
      return null;
    }
  }

  /// Import JSON file
  Future<StageTrace?> importJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[Stage] File not found: $filePath');
        return null;
      }

      final jsonString = await file.readAsString();

      // First run wizard to detect adapter
      await analyzeJson(jsonString);

      // Then parse with detected adapter
      return parseJson(jsonString);
    } catch (e) {
      debugPrint('[Stage] Error importing file: $e');
      return null;
    }
  }

  /// Get wizard result from FFI
  WizardResult _getWizardResult() {
    final confidence = _ffi.wizardGetConfidence();
    final layerStr = _ffi.wizardGetRecommendedLayer();
    final company = _ffi.wizardGetDetectedCompany();
    final engine = _ffi.wizardGetDetectedEngine();
    final configToml = _ffi.wizardGetConfigToml();
    final eventCount = _ffi.wizardGetDetectedEventCount();

    final events = <DetectedEvent>[];
    for (var i = 0; i < eventCount; i++) {
      final eventJson = _ffi.wizardGetDetectedEventJson(i);
      if (eventJson != null) {
        try {
          final map = jsonDecode(eventJson) as Map<String, dynamic>;
          events.add(DetectedEvent.fromJson(map));
        } catch (e) {
          debugPrint('[Stage] Error parsing detected event $i: $e');
        }
      }
    }

    return WizardResult(
      detectedCompany: company,
      detectedEngine: engine,
      recommendedLayer: IngestLayer.fromJson(layerStr) ?? IngestLayer.directEvent,
      confidence: confidence,
      detectedEvents: events,
      configToml: configToml,
    );
  }

  /// Get trace from FFI
  StageTrace? _getTraceFromFfi() {
    final traceJson = _ffi.stageGetTraceJson();
    if (traceJson == null) return null;

    try {
      final map = jsonDecode(traceJson) as Map<String, dynamic>;
      return StageTrace.fromJson(map);
    } catch (e) {
      debugPrint('[Stage] Error parsing trace JSON: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING RESOLUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set timing profile and re-resolve
  void setTimingProfile(TimingProfile profile) {
    _timingProfile = profile;
    _resolveTiming();
    notifyListeners();
  }

  /// Resolve timing for current trace
  void _resolveTiming() {
    if (_currentTrace == null) {
      _currentTimedTrace = null;
      return;
    }

    // profile: 0=Normal, 1=Turbo, 2=Mobile, 3=Studio, 4=Instant
    final success = _ffi.stageResolveTiming(_timingProfile.index);
    if (!success) {
      debugPrint('[Stage] Failed to resolve timing');
      return;
    }

    final timedJson = _ffi.stageGetTimedTraceJson();
    if (timedJson == null) return;

    try {
      final map = jsonDecode(timedJson) as Map<String, dynamic>;
      _currentTimedTrace = TimedStageTrace.fromJson(map);
    } catch (e) {
      debugPrint('[Stage] Error parsing timed trace: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start playback
  void play() {
    if (_currentTimedTrace == null) return;
    if (_isPlaying) return;

    _isPlaying = true;
    _playbackTimer?.cancel();

    // 60fps playback timer
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      _onPlaybackTick,
    );

    notifyListeners();
  }

  /// Pause playback
  void pause() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    notifyListeners();
  }

  /// Stop playback (reset to start)
  void stop() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackPosition = 0.0;
    notifyListeners();
  }

  /// Seek to position
  void seek(double positionMs) {
    _playbackPosition = positionMs.clamp(0.0, traceDuration);
    _throttledNotify();
  }

  /// Playback tick
  void _onPlaybackTick(Timer timer) {
    if (!_isPlaying || _currentTimedTrace == null) {
      timer.cancel();
      return;
    }

    // Advance by 16ms (approx 60fps)
    _playbackPosition += 16.0;

    // Check for end
    if (_playbackPosition >= traceDuration) {
      _playbackPosition = traceDuration;
      _isPlaying = false;
      timer.cancel();
      notifyListeners();
      return;
    }

    // Fire stage events at current position
    _fireEventsAtPosition();

    _throttledNotify();
  }

  /// Fire events that should trigger at current position
  void _fireEventsAtPosition() {
    // TODO: Trigger audio for events at this position
    // This will integrate with the audio engine
  }

  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotifyTime).inMilliseconds >= _notifyThrottleMs) {
      _lastNotifyTime = now;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADAPTER REGISTRY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load adapter from TOML config
  Future<bool> loadAdapterConfig(String tomlContent) async {
    try {
      final success = _ffi.adapterLoadConfig(tomlContent);
      if (success) {
        _refreshAdapterList();
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('[Stage] Error loading adapter config: $e');
      return false;
    }
  }

  /// Refresh adapter list from FFI
  void _refreshAdapterList() {
    final count = _ffi.adapterGetCount();
    _adapters = [];

    for (var i = 0; i < count; i++) {
      final infoJson = _ffi.adapterGetInfoJson(i);
      if (infoJson != null) {
        try {
          final map = jsonDecode(infoJson) as Map<String, dynamic>;
          _adapters.add(AdapterInfo.fromJson(map));
        } catch (e) {
          debugPrint('[Stage] Error parsing adapter info $i: $e');
        }
      }
    }
  }

  /// Get adapter count
  int get adapterCount => _ffi.adapterGetCount();

  /// Get adapter by index
  AdapterInfo? getAdapter(int index) {
    if (index < 0 || index >= _adapters.length) return null;
    return _adapters[index];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIVE MODE — ENGINE CONNECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Connect to game engine
  Future<bool> connect(ConnectionConfig config) async {
    if (_connectionState == EngineConnectionState.connecting ||
        _connectionState == EngineConnectionState.connected) {
      return false;
    }

    _connectionConfig = config;
    _connectionState = EngineConnectionState.connecting;
    notifyListeners();

    try {
      // Subscribe to state changes
      _stateSubscription?.cancel();
      _stateSubscription = _liveEngine.stateStream.listen((state) {
        _connectionState = state;
        notifyListeners();
      });

      // Connect via LiveEngineService
      final success = await _liveEngine.connect(config);

      if (success) {
        _startLiveEventStream();
      } else {
        _connectionState = EngineConnectionState.error;
      }

      notifyListeners();
      return success;
    } catch (e) {
      debugPrint('[Stage] Connection failed: $e');
      _connectionState = EngineConnectionState.error;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from game engine
  Future<void> disconnect() async {
    if (_connectionState == EngineConnectionState.disconnected) return;

    _connectionState = EngineConnectionState.disconnecting;
    notifyListeners();

    _eventSubscription?.cancel();
    _eventSubscription = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _liveEvents.clear();

    await _liveEngine.disconnect();

    _connectionState = EngineConnectionState.disconnected;
    notifyListeners();
  }

  /// Start listening to live events
  void _startLiveEventStream() {
    _eventSubscription?.cancel();
    _eventSubscription = _liveEngine.eventStream.listen(_onLiveEvent);
  }

  /// Handle incoming live event
  void _onLiveEvent(StageEvent event) {
    _liveEvents.add(event);

    // Keep last 1000 events
    if (_liveEvents.length > 1000) {
      _liveEvents.removeRange(0, _liveEvents.length - 1000);
    }

    // Trigger audio for this event
    _triggerAudioForEvent(event);
    _throttledNotify();
  }

  /// Trigger audio based on stage event
  void _triggerAudioForEvent(StageEvent event) {
    // TODO: Connect to audio engine via FFI
    // _ffi.triggerStageAudio(event.stage.typeName, event.toJson());
    debugPrint('[Stage] Audio trigger: ${event.stage.typeName}');
  }

  /// Send command to engine
  Future<void> sendCommand(EngineCommand command) async {
    if (!isConnected) return;
    await _liveEngine.sendCommand(command);
  }

  // ─── Recording ──────────────────────────────────────────────────────────────

  /// Check if recording is active
  bool get isRecording => _liveEngine.isRecording;

  /// Start recording live events
  void startRecording() {
    _liveEngine.startRecording();
    notifyListeners();
  }

  /// Stop recording and get events
  List<RecordedEvent> stopRecording() {
    final events = _liveEngine.stopRecording();
    notifyListeners();
    return events;
  }

  /// Export recording to JSON
  String exportRecordingJson() {
    return _liveEngine.exportRecordingJson();
  }

  /// Clear live events
  void clearLiveEvents() {
    _liveEvents.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clear current trace
  void clearTrace() {
    _currentTrace = null;
    _currentTimedTrace = null;
    _playbackPosition = 0.0;
    _isPlaying = false;
    _playbackTimer?.cancel();
    notifyListeners();
  }

  /// Clear wizard result
  void clearWizard() {
    _wizardResult = null;
    notifyListeners();
  }

  /// Get events at specific time
  List<String> getEventsAtTime(double timeMs) {
    final jsonStr = _ffi.stageGetEventsAtTime(timeMs);
    if (jsonStr == null) return [];

    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      return [];
    }
  }

  /// Get trace duration from FFI
  double get ffiDuration => _ffi.stageGetDurationMs();

  /// Get event count from FFI
  int get ffiEventCount => _ffi.stageGetEventCount();

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _eventSubscription?.cancel();
    _stateSubscription?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ADAPTER WIZARD PROVIDER (Separate for UI Wizard Flow)
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the Adapter Wizard UI flow
class AdapterWizardProvider extends ChangeNotifier {
  final StageProvider _stageProvider;

  AdapterWizardProvider(this._stageProvider);

  // ─── Wizard State ─────────────────────────────────────────────────────────
  WizardStep _currentStep = WizardStep.selectSource;
  String? _jsonContent;
  String? _errorMessage;
  bool _isAnalyzing = false;

  // ─── User Overrides ───────────────────────────────────────────────────────
  IngestLayer? _selectedLayer;
  Map<String, String> _eventMappingOverrides = {};

  // ─── Getters ──────────────────────────────────────────────────────────────
  WizardStep get currentStep => _currentStep;
  String? get jsonContent => _jsonContent;
  String? get errorMessage => _errorMessage;
  bool get isAnalyzing => _isAnalyzing;
  WizardResult? get result => _stageProvider.wizardResult;
  IngestLayer get selectedLayer =>
      _selectedLayer ?? result?.recommendedLayer ?? IngestLayer.directEvent;

  // ═══════════════════════════════════════════════════════════════════════════
  // WIZARD FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set JSON content for analysis
  void setJsonContent(String json) {
    _jsonContent = json;
    _errorMessage = null;
    notifyListeners();
  }

  /// Analyze the JSON
  Future<bool> analyze() async {
    if (_jsonContent == null || _jsonContent!.isEmpty) {
      _errorMessage = 'No JSON content provided';
      notifyListeners();
      return false;
    }

    _isAnalyzing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _stageProvider.analyzeJson(_jsonContent!);
      _isAnalyzing = false;

      if (result == null) {
        _errorMessage = 'Analysis failed. Check JSON format.';
        notifyListeners();
        return false;
      }

      _currentStep = WizardStep.reviewDetection;
      notifyListeners();
      return true;
    } catch (e) {
      _isAnalyzing = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Override selected layer
  void setSelectedLayer(IngestLayer layer) {
    _selectedLayer = layer;
    notifyListeners();
  }

  /// Override event mapping
  void setEventMapping(String eventName, String stageName) {
    _eventMappingOverrides[eventName] = stageName;
    notifyListeners();
  }

  /// Go to next step
  void nextStep() {
    final nextIndex = WizardStep.values.indexOf(_currentStep) + 1;
    if (nextIndex < WizardStep.values.length) {
      _currentStep = WizardStep.values[nextIndex];
      notifyListeners();
    }
  }

  /// Go to previous step
  void previousStep() {
    final prevIndex = WizardStep.values.indexOf(_currentStep) - 1;
    if (prevIndex >= 0) {
      _currentStep = WizardStep.values[prevIndex];
      notifyListeners();
    }
  }

  /// Go to specific step
  void goToStep(WizardStep step) {
    _currentStep = step;
    notifyListeners();
  }

  /// Finish wizard and generate config
  Future<String?> finish() async {
    // Generate final config with overrides
    final baseToml = result?.configToml ?? '';

    // TODO: Apply _eventMappingOverrides to config
    // For now, return base config

    _currentStep = WizardStep.complete;
    notifyListeners();

    return baseToml;
  }

  /// Reset wizard
  void reset() {
    _currentStep = WizardStep.selectSource;
    _jsonContent = null;
    _errorMessage = null;
    _isAnalyzing = false;
    _selectedLayer = null;
    _eventMappingOverrides.clear();
    _stageProvider.clearWizard();
    notifyListeners();
  }
}

/// Wizard steps
enum WizardStep {
  selectSource,     // Choose JSON file or paste
  reviewDetection,  // Review auto-detected mappings
  configureMapping, // Fine-tune event→stage mapping
  selectLayer,      // Choose ingest layer
  testParse,        // Test parsing with sample data
  complete,         // Done
}

// ═══════════════════════════════════════════════════════════════════════════
// ENGINE CONNECTION PROVIDER (Separate for Live Mode UI)
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for engine connection management
class EngineConnectionProvider extends ChangeNotifier {
  final StageProvider _stageProvider;

  EngineConnectionProvider(this._stageProvider);

  // ─── Connection Form State ────────────────────────────────────────────────
  ConnectionProtocol _protocol = ConnectionProtocol.webSocket;
  String _host = 'localhost';
  int _port = 8080;
  String _url = 'ws://localhost:8080';
  String _adapterId = 'generic';
  String? _authToken;
  int _timeoutMs = 5000;

  // ─── History ──────────────────────────────────────────────────────────────
  List<ConnectionConfig> _recentConnections = [];

  // ─── Getters ──────────────────────────────────────────────────────────────
  ConnectionProtocol get protocol => _protocol;
  String get host => _host;
  int get port => _port;
  String get url => _url;
  String get adapterId => _adapterId;
  String? get authToken => _authToken;
  int get timeoutMs => _timeoutMs;
  List<ConnectionConfig> get recentConnections =>
      List.unmodifiable(_recentConnections);

  EngineConnectionState get connectionState => _stageProvider.connectionState;
  bool get isConnected => _stageProvider.isConnected;
  List<StageEvent> get liveEvents => _stageProvider.liveEvents;

  // ═══════════════════════════════════════════════════════════════════════════
  // FORM SETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  void setProtocol(ConnectionProtocol protocol) {
    _protocol = protocol;
    notifyListeners();
  }

  void setHost(String host) {
    _host = host;
    notifyListeners();
  }

  void setPort(int port) {
    _port = port;
    notifyListeners();
  }

  void setUrl(String url) {
    _url = url;
    notifyListeners();
  }

  void setAdapterId(String adapterId) {
    _adapterId = adapterId;
    notifyListeners();
  }

  void setAuthToken(String? token) {
    _authToken = token;
    notifyListeners();
  }

  void setTimeoutMs(int timeout) {
    _timeoutMs = timeout;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONNECTION ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build config from current form state
  ConnectionConfig buildConfig() {
    if (_protocol == ConnectionProtocol.webSocket) {
      return ConnectionConfig(
        protocol: _protocol,
        url: _url,
        adapterId: _adapterId,
        authToken: _authToken,
        timeoutMs: _timeoutMs,
      );
    } else {
      return ConnectionConfig(
        protocol: _protocol,
        host: _host,
        port: _port,
        adapterId: _adapterId,
        authToken: _authToken,
        timeoutMs: _timeoutMs,
      );
    }
  }

  /// Connect with current form settings
  Future<bool> connect() async {
    final config = buildConfig();
    final success = await _stageProvider.connect(config);

    if (success) {
      _addToRecent(config);
    }

    notifyListeners();
    return success;
  }

  /// Connect with specific config
  Future<bool> connectWith(ConnectionConfig config) async {
    // Update form state
    _protocol = config.protocol;
    _host = config.host;
    _port = config.port;
    _url = config.url ?? 'ws://${config.host}:${config.port}';
    _adapterId = config.adapterId;
    _authToken = config.authToken;
    _timeoutMs = config.timeoutMs;

    final success = await _stageProvider.connect(config);

    if (success) {
      _addToRecent(config);
    }

    notifyListeners();
    return success;
  }

  /// Disconnect
  Future<void> disconnect() async {
    await _stageProvider.disconnect();
    notifyListeners();
  }

  /// Add to recent connections
  void _addToRecent(ConnectionConfig config) {
    _recentConnections.removeWhere(
      (c) => c.displayUrl == config.displayUrl,
    );
    _recentConnections.insert(0, config);

    // Keep last 10
    if (_recentConnections.length > 10) {
      _recentConnections = _recentConnections.sublist(0, 10);
    }
  }

  /// Clear recent connections
  void clearRecent() {
    _recentConnections.clear();
    notifyListeners();
  }

  /// Send command to connected engine
  Future<void> sendCommand(EngineCommand command) async {
    await _stageProvider.sendCommand(command);
  }

  /// Clear live event log
  void clearEvents() {
    _stageProvider.clearLiveEvents();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if recording
  bool get isRecording => _stageProvider.isRecording;

  /// Start recording events
  void startRecording() {
    _stageProvider.startRecording();
    notifyListeners();
  }

  /// Stop recording
  List<RecordedEvent> stopRecording() {
    final events = _stageProvider.stopRecording();
    notifyListeners();
    return events;
  }

  /// Export recording to JSON string
  String exportRecordingJson() {
    return _stageProvider.exportRecordingJson();
  }
}
