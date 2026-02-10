// Lua Bridge — Embedded Lua Scripting for FluxForge
//
// Provides Lua scripting capabilities for:
// - Automation (batch operations, custom workflows)
// - Macros (user-defined shortcuts)
// - Analysis (custom metrics, validation)
// - Testing (QA scripts, reproducibility)
//
// Built-in FluxForge API exposed to Lua:
// - fluxforge.createEvent(name, stage)
// - fluxforge.addLayer(eventId, audioPath, volume, pan)
// - fluxforge.triggerStage(stage)
// - fluxforge.setRtpc(rtpcId, value)
// - fluxforge.saveProject(path)
//
// Usage:
//   final bridge = LuaBridge.instance;
//   await bridge.initialize();
//   final result = await bridge.execute('return fluxforge.createEvent("Test", "SPIN_START")');

import 'dart:async';
import 'fluxforge_api.dart';

/// Lua execution result
class LuaResult {
  final bool success;
  final dynamic returnValue;
  final String? error;
  final Duration executionTime;

  LuaResult({
    required this.success,
    this.returnValue,
    this.error,
    required this.executionTime,
  });

  @override
  String toString() {
    if (success) {
      return 'LuaResult(success: true, value: $returnValue, time: ${executionTime.inMilliseconds}ms)';
    } else {
      return 'LuaResult(success: false, error: $error, time: ${executionTime.inMilliseconds}ms)';
    }
  }
}

class LuaBridge {
  static final LuaBridge instance = LuaBridge._();
  LuaBridge._();

  final FluxForgeApi _api = FluxForgeApi.instance;
  bool _initialized = false;

  /// Execution statistics
  int _totalExecutions = 0;
  int _successfulExecutions = 0;
  int _failedExecutions = 0;
  Duration _totalExecutionTime = Duration.zero;

  bool get initialized => _initialized;

  /// Initialize the Lua bridge
  Future<void> initialize() async {
    if (_initialized) return;

    // TODO: Initialize Lua VM (requires lua_dardo package or FFI)
    // For now, we'll simulate Lua execution with a simple interpreter

    _initialized = true;
  }

  /// Execute a Lua script
  Future<LuaResult> execute(String script) async {
    if (!_initialized) {
      await initialize();
    }

    _totalExecutions++;
    final startTime = DateTime.now();

    try {
      // Parse and execute script
      final result = await _executeScript(script);

      final executionTime = DateTime.now().difference(startTime);
      _totalExecutionTime += executionTime;
      _successfulExecutions++;

      return LuaResult(
        success: true,
        returnValue: result,
        executionTime: executionTime,
      );
    } catch (e) {
      final executionTime = DateTime.now().difference(startTime);
      _totalExecutionTime += executionTime;
      _failedExecutions++;

      return LuaResult(
        success: false,
        error: e.toString(),
        executionTime: executionTime,
      );
    }
  }

  /// Execute a Lua script (internal implementation)
  Future<dynamic> _executeScript(String script) async {
    // Simple pattern matching for FluxForge API calls
    // In production, this would use a real Lua VM

    // Pattern: fluxforge.createEvent("name", "stage")
    final createEventPattern = RegExp(
      r'fluxforge\.createEvent\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\)',
    );
    final createEventMatch = createEventPattern.firstMatch(script);
    if (createEventMatch != null) {
      final name = createEventMatch.group(1)!;
      final stage = createEventMatch.group(2)!;
      return await _api.createEvent({'name': name, 'stage': stage});
    }

    // Pattern: fluxforge.addLayer(eventId, audioPath, volume, pan)
    final addLayerPattern = RegExp(
      r'fluxforge\.addLayer\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*([\d.]+)\s*,\s*([\d.-]+)\s*\)',
    );
    final addLayerMatch = addLayerPattern.firstMatch(script);
    if (addLayerMatch != null) {
      final eventId = addLayerMatch.group(1)!;
      final audioPath = addLayerMatch.group(2)!;
      final volume = double.parse(addLayerMatch.group(3)!);
      final pan = double.parse(addLayerMatch.group(4)!);
      return await _api.addLayer({
        'eventId': eventId,
        'audioPath': audioPath,
        'volume': volume,
        'pan': pan,
      });
    }

    // Pattern: fluxforge.triggerStage("stage")
    final triggerStagePattern = RegExp(
      r'fluxforge\.triggerStage\(\s*"([^"]*)"\s*\)',
    );
    final triggerStageMatch = triggerStagePattern.firstMatch(script);
    if (triggerStageMatch != null) {
      final stage = triggerStageMatch.group(1)!;
      return await _api.triggerStage({'stage': stage});
    }

    // Pattern: fluxforge.setRtpc("rtpcId", value)
    final setRtpcPattern = RegExp(
      r'fluxforge\.setRtpc\(\s*"([^"]*)"\s*,\s*([\d.]+)\s*\)',
    );
    final setRtpcMatch = setRtpcPattern.firstMatch(script);
    if (setRtpcMatch != null) {
      final rtpcId = setRtpcMatch.group(1)!;
      final value = double.parse(setRtpcMatch.group(2)!);
      return await _api.setRtpc({'rtpcId': rtpcId, 'value': value});
    }

    // Pattern: fluxforge.saveProject("path")
    final saveProjectPattern = RegExp(
      r'fluxforge\.saveProject\(\s*"([^"]*)"\s*\)',
    );
    final saveProjectMatch = saveProjectPattern.firstMatch(script);
    if (saveProjectMatch != null) {
      final path = saveProjectMatch.group(1)!;
      return await _api.saveProject({'path': path});
    }

    // Pattern: fluxforge.getProjectInfo()
    if (script.contains('fluxforge.getProjectInfo()')) {
      return await _api.getProjectInfo({});
    }

    // Pattern: fluxforge.listEvents()
    if (script.contains('fluxforge.listEvents()')) {
      return await _api.listEvents({});
    }

    // Pattern: return "string" or return number
    final returnPattern = RegExp(r'return\s+(.+)');
    final returnMatch = returnPattern.firstMatch(script);
    if (returnMatch != null) {
      final value = returnMatch.group(1)!.trim();

      // String literal
      if (value.startsWith('"') && value.endsWith('"')) {
        return value.substring(1, value.length - 1);
      }

      // Number
      final number = double.tryParse(value);
      if (number != null) {
        return number;
      }

      // Boolean
      if (value == 'true') return true;
      if (value == 'false') return false;
      if (value == 'nil') return null;

      return value;
    }

    throw Exception('Unsupported Lua script pattern');
  }

  /// Execute a Lua file
  Future<LuaResult> executeFile(String path) async {
    // TODO: Read file and execute
    throw UnimplementedError('executeFile not yet implemented');
  }

  /// Get available FluxForge API functions
  List<String> getAvailableFunctions() {
    return [
      'fluxforge.createEvent(name, stage)',
      'fluxforge.deleteEvent(eventId)',
      'fluxforge.getEvent(eventId)',
      'fluxforge.listEvents()',
      'fluxforge.addLayer(eventId, audioPath, volume, pan)',
      'fluxforge.removeLayer(eventId, layerId)',
      'fluxforge.updateLayer(eventId, layerId, volume, pan)',
      'fluxforge.setRtpc(rtpcId, value)',
      'fluxforge.getRtpc(rtpcId)',
      'fluxforge.listRtpcs()',
      'fluxforge.setState(stateGroup, state)',
      'fluxforge.getState(stateGroup)',
      'fluxforge.listStates()',
      'fluxforge.triggerStage(stage)',
      'fluxforge.stopEvent(eventId)',
      'fluxforge.stopAll()',
      'fluxforge.saveProject(path)',
      'fluxforge.loadProject(path)',
      'fluxforge.getProjectInfo()',
      'fluxforge.createContainer(type, name)',
      'fluxforge.deleteContainer(containerId)',
      'fluxforge.evaluateContainer(containerId)',
    ];
  }

  /// Get execution statistics
  Map<String, dynamic> getStats() {
    return {
      'totalExecutions': _totalExecutions,
      'successfulExecutions': _successfulExecutions,
      'failedExecutions': _failedExecutions,
      'successRate': _totalExecutions > 0
          ? '${(_successfulExecutions / _totalExecutions * 100).toStringAsFixed(1)}%'
          : '0%',
      'avgExecutionTime': _totalExecutions > 0
          ? '${(_totalExecutionTime.inMilliseconds / _totalExecutions).toStringAsFixed(1)}ms'
          : '0ms',
      'totalExecutionTime': '${_totalExecutionTime.inMilliseconds}ms',
    };
  }

  /// Reset statistics
  void resetStats() {
    _totalExecutions = 0;
    _successfulExecutions = 0;
    _failedExecutions = 0;
    _totalExecutionTime = Duration.zero;
  }

  /// Dispose the Lua bridge
  void dispose() {
    _initialized = false;
  }
}
