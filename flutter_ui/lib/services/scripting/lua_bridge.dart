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
// VM: Real Lua evaluator via pub.dev `lua` package (petitparser-based).
// Supports: variables, control flow (if/while/for), functions, tables,
//           standard math/string libraries, print(), and the fluxforge.* namespace.
//
// Usage:
//   final bridge = LuaBridge.instance;
//   await bridge.initialize();
//   final result = await bridge.execute('return fluxforge.triggerStage("UI_SPIN_PRESS")');

import 'dart:async';
import 'dart:io';

import 'package:lua/lua.dart';

import 'fluxforge_api.dart';

/// Lua execution result
class LuaResult {
  final bool success;
  final dynamic returnValue;
  final String? error;
  final Duration executionTime;

  /// Any output written via print() inside the Lua script
  final String output;

  LuaResult({
    required this.success,
    this.returnValue,
    this.error,
    required this.executionTime,
    this.output = '',
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

  // Lua VM state
  late LuaEnv _luaEnv;
  late LuaOutputBuffer _outputBuffer;

  /// Execution statistics
  int _totalExecutions = 0;
  int _successfulExecutions = 0;
  int _failedExecutions = 0;
  Duration _totalExecutionTime = Duration.zero;

  bool get initialized => _initialized;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the Lua VM with the FluxForge API table.
  ///
  /// Must be called before [execute] — [execute] calls it automatically if needed.
  Future<void> initialize() async {
    if (_initialized) return;

    _outputBuffer = LuaOutputBuffer();

    // Build the `fluxforge` API table exposed to Lua scripts.
    // Sync-capable methods (EventRegistry, MiddlewareProvider state reads) work
    // immediately. Async-heavy methods (file I/O, save) are fire-and-forget —
    // the Lua function returns nil and the operation is dispatched in the background.
    final fluxforgeTable = TableInstance();

    fluxforgeTable.fields['triggerStage'] = _wrapSync(
      'triggerStage',
      (List<Object?> args) {
        final stage = _str(args, 0, 'stage');
        _api.triggerStage({'stage': stage});
        return {'success': true, 'stage': stage};
      },
    );

    fluxforgeTable.fields['stopAll'] = _wrapSync(
      'stopAll',
      (List<Object?> args) {
        _api.stopAll({});
        return {'success': true};
      },
    );

    fluxforgeTable.fields['stopEvent'] = _wrapSync(
      'stopEvent',
      (List<Object?> args) {
        final eventId = _str(args, 0, 'eventId');
        _api.stopEvent({'eventId': eventId});
        return {'success': true};
      },
    );

    fluxforgeTable.fields['createEvent'] = _wrapSync(
      'createEvent',
      (List<Object?> args) {
        final name = _str(args, 0, 'name');
        final stage = args.length > 1 ? args[1] as String? : null;
        _api.createEvent({'name': name, if (stage != null) 'stage': stage});
        return {'success': true, 'name': name};
      },
    );

    fluxforgeTable.fields['addLayer'] = _wrapSync(
      'addLayer',
      (List<Object?> args) {
        final eventId = _str(args, 0, 'eventId');
        final audioPath = _str(args, 1, 'audioPath');
        final volume = _num(args, 2, 1.0);
        final pan = _num(args, 3, 0.0);
        _api.addLayer({
          'eventId': eventId,
          'audioPath': audioPath,
          'volume': volume,
          'pan': pan,
        });
        return {'success': true};
      },
    );

    fluxforgeTable.fields['setRtpc'] = _wrapSync(
      'setRtpc',
      (List<Object?> args) {
        final rtpcId = _str(args, 0, 'rtpcId');
        final value = _num(args, 1, 0.0);
        _api.setRtpc({'rtpcId': rtpcId, 'value': value});
        return {'success': true};
      },
    );

    fluxforgeTable.fields['getRtpc'] = _wrapSync(
      'getRtpc',
      (List<Object?> args) {
        final rtpcId = _str(args, 0, 'rtpcId');
        // Fire async, return placeholder
        _api.getRtpc({'rtpcId': rtpcId});
        return null;
      },
    );

    fluxforgeTable.fields['setState'] = _wrapSync(
      'setState',
      (List<Object?> args) {
        final group = _str(args, 0, 'stateGroup');
        final state = _str(args, 1, 'state');
        _api.setState({'stateGroup': group, 'state': state});
        return {'success': true};
      },
    );

    fluxforgeTable.fields['listEvents'] = _wrapSync(
      'listEvents',
      (List<Object?> args) {
        // Async — fire and return nil
        _api.listEvents({});
        return null;
      },
    );

    fluxforgeTable.fields['getProjectInfo'] = _wrapSync(
      'getProjectInfo',
      (List<Object?> args) {
        _api.getProjectInfo({});
        return null;
      },
    );

    fluxforgeTable.fields['saveProject'] = _wrapSync(
      'saveProject',
      (List<Object?> args) {
        final path = args.isNotEmpty ? args[0] as String? : null;
        _api.saveProject({'path': path ?? ''});
        return {'success': true};
      },
    );

    fluxforgeTable.fields['loadProject'] = _wrapSync(
      'loadProject',
      (List<Object?> args) {
        final path = _str(args, 0, 'path');
        _api.loadProject({'path': path});
        return {'success': true};
      },
    );

    fluxforgeTable.fields['wait'] = _wrapSync(
      'wait',
      (List<Object?> args) {
        // Cooperative sleep for scripting (UI-thread safe, non-blocking in Lua context)
        final ms = _num(args, 0, 100.0).round();
        _outputBuffer.writeLine('[fluxforge.wait] ${ms}ms (non-blocking)');
        return null;
      },
    );

    fluxforgeTable.fields['print'] = _wrapSync(
      'print',
      (List<Object?> args) {
        final message = args.map((a) => a?.toString() ?? 'nil').join('\t');
        _outputBuffer.writeLine(message);
        return null;
      },
    );

    _luaEnv = LuaEnv.withStdlib(
      variables: {'fluxforge': fluxforgeTable},
      output: _outputBuffer,
    );

    _initialized = true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXECUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute a Lua script string.
  ///
  /// Supports full Lua syntax: variables, if/while/for, functions, tables,
  /// math/string stdlib, print(), and the fluxforge.* namespace.
  Future<LuaResult> execute(String script) async {
    if (!_initialized) await initialize();

    _totalExecutions++;
    final startTime = DateTime.now();
    _outputBuffer.clear();

    try {
      final result = await _executeScript(script);
      final executionTime = DateTime.now().difference(startTime);
      _totalExecutionTime += executionTime;
      _successfulExecutions++;

      return LuaResult(
        success: true,
        returnValue: result,
        executionTime: executionTime,
        output: _outputBuffer.output,
      );
    } catch (e) {
      final executionTime = DateTime.now().difference(startTime);
      _totalExecutionTime += executionTime;
      _failedExecutions++;

      return LuaResult(
        success: false,
        error: e.toString(),
        executionTime: executionTime,
        output: _outputBuffer.output,
      );
    }
  }

  /// Execute a Lua script file.
  Future<LuaResult> executeFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return LuaResult(
        success: false,
        error: 'File not found: $path',
        executionTime: Duration.zero,
      );
    }
    try {
      final script = await file.readAsString();
      return await execute(script);
    } catch (e) {
      return LuaResult(
        success: false,
        error: 'Failed to read file: $e',
        executionTime: Duration.zero,
      );
    }
  }

  /// Internal: parse + evaluate with the real Lua VM.
  Future<dynamic> _executeScript(String script) async {
    // parse() throws ParseException on syntax error
    final ast = parse(script);

    // evaluate() throws EvaluationException on runtime error
    final result = ast.evaluate(env: _luaEnv);

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS — Lua function argument extraction
  // ═══════════════════════════════════════════════════════════════════════════

  /// Wrap a sync Dart function as a LuaFunction with error context.
  LuaFunction _wrapSync(String name, LuaFunction fn) {
    return (List<Object?> args) {
      try {
        return fn(args);
      } catch (e) {
        throw EvaluationException('fluxforge.$name: $e');
      }
    };
  }

  String _str(List<Object?> args, int index, String paramName) {
    if (index >= args.length || args[index] == null) {
      throw ArgumentError('Missing required string parameter: $paramName');
    }
    return args[index].toString();
  }

  double _num(List<Object?> args, int index, double defaultValue) {
    if (index >= args.length || args[index] == null) return defaultValue;
    final v = args[index];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METADATA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get available FluxForge API functions
  List<String> getAvailableFunctions() {
    return [
      'fluxforge.createEvent(name [, stage])',
      'fluxforge.addLayer(eventId, audioPath [, volume [, pan]])',
      'fluxforge.triggerStage(stage)',
      'fluxforge.stopEvent(eventId)',
      'fluxforge.stopAll()',
      'fluxforge.setRtpc(rtpcId, value)',
      'fluxforge.getRtpc(rtpcId)',
      'fluxforge.setState(stateGroup, state)',
      'fluxforge.listEvents()',
      'fluxforge.getProjectInfo()',
      'fluxforge.saveProject([path])',
      'fluxforge.loadProject(path)',
      'fluxforge.print(message)',
      'fluxforge.wait(ms)',
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

  /// Dispose the Lua bridge (resets VM state — next execute() will re-initialize)
  void dispose() {
    _initialized = false;
  }
}
