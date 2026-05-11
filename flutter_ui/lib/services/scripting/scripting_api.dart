/// Scripting API
///
/// Simple scripting interface for SlotLab automation:
/// - Event triggering
/// - Batch operations
/// - Audio control
/// - State queries
/// - Custom actions
///
/// Created: 2026-01-30 (P4.26)

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../audio_playback_service.dart';
import '../event_registry.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCRIPT COMMAND TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Script command types
enum ScriptCommandType {
  /// Trigger a stage event
  triggerStage,

  /// Set a parameter value
  setParameter,

  /// Wait for duration
  wait,

  /// Play an audio file
  playAudio,

  /// Stop audio
  stopAudio,

  /// Set volume
  setVolume,

  /// Log a message
  log,

  /// Conditional execution
  conditional,

  /// Loop execution
  loop,

  /// Call a function
  call,
}

/// Script command
class ScriptCommand {
  final ScriptCommandType type;
  final Map<String, dynamic> args;
  final String? label;

  const ScriptCommand({
    required this.type,
    this.args = const {},
    this.label,
  });

  /// Create a trigger stage command
  factory ScriptCommand.triggerStage(String stage) {
    return ScriptCommand(
      type: ScriptCommandType.triggerStage,
      args: {'stage': stage},
    );
  }

  /// Create a wait command
  factory ScriptCommand.wait(int milliseconds) {
    return ScriptCommand(
      type: ScriptCommandType.wait,
      args: {'ms': milliseconds},
    );
  }

  /// Create a set parameter command
  factory ScriptCommand.setParameter(String param, dynamic value) {
    return ScriptCommand(
      type: ScriptCommandType.setParameter,
      args: {'param': param, 'value': value},
    );
  }

  /// Create a play audio command
  factory ScriptCommand.playAudio(String path, {double volume = 1.0}) {
    return ScriptCommand(
      type: ScriptCommandType.playAudio,
      args: {'path': path, 'volume': volume},
    );
  }

  /// Create a stop audio command
  factory ScriptCommand.stopAudio({String? eventId}) {
    return ScriptCommand(
      type: ScriptCommandType.stopAudio,
      args: {'eventId': eventId},
    );
  }

  /// Create a set volume command
  factory ScriptCommand.setVolume(String target, double volume) {
    return ScriptCommand(
      type: ScriptCommandType.setVolume,
      args: {'target': target, 'volume': volume},
    );
  }

  /// Create a log command
  factory ScriptCommand.log(String message) {
    return ScriptCommand(
      type: ScriptCommandType.log,
      args: {'message': message},
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'args': args,
        if (label != null) 'label': label,
      };

  factory ScriptCommand.fromJson(Map<String, dynamic> json) {
    return ScriptCommand(
      type: ScriptCommandType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ScriptCommandType.log,
      ),
      args: Map<String, dynamic>.from(json['args'] ?? {}),
      label: json['label'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCRIPT MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Script definition
class Script {
  final String id;
  final String name;
  final String? description;
  final List<ScriptCommand> commands;
  final Map<String, dynamic> variables;
  final DateTime createdAt;
  final DateTime modifiedAt;

  const Script({
    required this.id,
    required this.name,
    this.description,
    this.commands = const [],
    this.variables = const {},
    required this.createdAt,
    required this.modifiedAt,
  });

  Script copyWith({
    String? id,
    String? name,
    String? description,
    List<ScriptCommand>? commands,
    Map<String, dynamic>? variables,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return Script(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      commands: commands ?? this.commands,
      variables: variables ?? this.variables,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'commands': commands.map((c) => c.toJson()).toList(),
        'variables': variables,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory Script.fromJson(Map<String, dynamic> json) {
    return Script(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      commands: (json['commands'] as List?)
              ?.map((c) => ScriptCommand.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      variables: Map<String, dynamic>.from(json['variables'] ?? {}),
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCRIPT EXECUTION CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

/// Context for script execution
class ScriptContext {
  final Map<String, dynamic> variables;
  final List<String> log;
  bool _stopped = false;

  ScriptContext({Map<String, dynamic>? initialVariables})
      : variables = Map.from(initialVariables ?? {}),
        log = [];

  bool get isStopped => _stopped;

  void stop() => _stopped = true;

  void setVariable(String name, dynamic value) {
    variables[name] = value;
  }

  dynamic getVariable(String name) {
    return variables[name];
  }

  void addLog(String message) {
    log.add('[${DateTime.now().toIso8601String()}] $message');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCRIPTING API SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Command handler callback type
typedef ScriptCommandHandler = Future<void> Function(
  ScriptCommand command,
  ScriptContext context,
);

/// Service for executing scripts
class ScriptingApiService extends ChangeNotifier {
  ScriptingApiService._();
  static final instance = ScriptingApiService._();

  // Command handlers
  final Map<ScriptCommandType, ScriptCommandHandler> _handlers = {};

  // State
  final List<Script> _scripts = [];
  Script? _runningScript;
  ScriptContext? _runningContext;
  bool _initialized = false;

  // Getters
  List<Script> get scripts => List.unmodifiable(_scripts);
  Script? get runningScript => _runningScript;
  bool get isRunning => _runningScript != null;
  bool get initialized => _initialized;

  /// Initialize the service
  void init() {
    if (_initialized) return;

    // Register default handlers
    _registerDefaultHandlers();

    _initialized = true;
  }

  void _registerDefaultHandlers() {
    // Wait handler
    registerHandler(ScriptCommandType.wait, (command, context) async {
      final ms = command.args['ms'] as int? ?? 0;
      context.addLog('Waiting ${ms}ms');
      await Future.delayed(Duration(milliseconds: ms));
    });

    // Log handler
    registerHandler(ScriptCommandType.log, (command, context) async {
      final message = command.args['message'] as String? ?? '';
      context.addLog(message);
    });

    // Trigger stage handler — G.11: integrated with EventRegistry
    registerHandler(ScriptCommandType.triggerStage, (command, context) async {
      final stage = command.args['stage'] as String? ?? '';
      if (stage.isEmpty) {
        context.addLog('[WARN] triggerStage: missing stage name');
        return;
      }
      try {
        final reg = GetIt.instance<EventRegistry>();
        await reg.triggerStage(stage);
        context.addLog('Stage triggered: $stage');
      } catch (e) {
        context.addLog('[ERR] triggerStage failed: $e');
      }
    });

    // Set parameter handler
    registerHandler(ScriptCommandType.setParameter, (command, context) async {
      final param = command.args['param'] as String? ?? '';
      final value = command.args['value'];
      context.setVariable(param, value);
      context.addLog('Set $param = $value');
    });

    // Play audio handler — G.11: integrated with AudioPlaybackService
    registerHandler(ScriptCommandType.playAudio, (command, context) async {
      final path = command.args['path'] as String? ?? '';
      final volume = (command.args['volume'] as num?)?.toDouble() ?? 1.0;
      if (path.isEmpty) {
        context.addLog('[WARN] playAudio: missing path');
        return;
      }
      try {
        final svc = GetIt.instance<AudioPlaybackService>();
        final voiceId = svc.previewFile(path, volume: volume);
        if (voiceId >= 0) {
          context.addLog('Playing audio: $path (voice: $voiceId, vol: $volume)');
        } else {
          context.addLog('[ERR] playAudio: previewFile returned -1 for $path');
        }
      } catch (e) {
        context.addLog('[ERR] playAudio failed: $e');
      }
    });

    // Stop audio handler — G.11: integrated with AudioPlaybackService
    registerHandler(ScriptCommandType.stopAudio, (command, context) async {
      final eventId = command.args['eventId'] as String?;
      try {
        final svc = GetIt.instance<AudioPlaybackService>();
        if (eventId != null && eventId.isNotEmpty) {
          svc.stopEvent(eventId);
          context.addLog('Stopped audio event: $eventId');
        } else {
          svc.stopAll();
          context.addLog('Stopped all audio');
        }
      } catch (e) {
        context.addLog('[ERR] stopAudio failed: $e');
      }
    });

    // Set volume handler (placeholder)
    registerHandler(ScriptCommandType.setVolume, (command, context) async {
      final target = command.args['target'] as String? ?? '';
      final volume = (command.args['volume'] as num?)?.toDouble() ?? 1.0;
      context.addLog('Setting volume for $target: $volume');
    });
  }

  /// Register a command handler
  void registerHandler(
    ScriptCommandType type,
    ScriptCommandHandler handler,
  ) {
    _handlers[type] = handler;
  }

  /// Add a script
  void addScript(Script script) {
    _scripts.add(script);
    notifyListeners();
  }

  /// Remove a script
  void removeScript(String scriptId) {
    _scripts.removeWhere((s) => s.id == scriptId);
    notifyListeners();
  }

  /// Update a script
  void updateScript(Script script) {
    final index = _scripts.indexWhere((s) => s.id == script.id);
    if (index >= 0) {
      _scripts[index] = script;
      notifyListeners();
    }
  }

  /// Get script by ID
  Script? getScript(String scriptId) {
    return _scripts.where((s) => s.id == scriptId).firstOrNull;
  }

  /// Execute a script
  Future<ScriptContext> executeScript(
    Script script, {
    Map<String, dynamic>? initialVariables,
  }) async {
    if (_runningScript != null) {
      throw StateError('Another script is already running');
    }

    _runningScript = script;
    _runningContext = ScriptContext(
      initialVariables: {...script.variables, ...?initialVariables},
    );
    notifyListeners();

    try {
      _runningContext!.addLog('Started script: ${script.name}');

      for (final command in script.commands) {
        if (_runningContext!.isStopped) {
          _runningContext!.addLog('Script stopped by user');
          break;
        }

        final handler = _handlers[command.type];
        if (handler != null) {
          await handler(command, _runningContext!);
        } else {
          _runningContext!.addLog('No handler for: ${command.type}');
        }
      }

      _runningContext!.addLog('Script completed');
      final context = _runningContext!;
      _runningScript = null;
      _runningContext = null;
      notifyListeners();
      return context;
    } catch (e) {
      _runningContext!.addLog('Script error: $e');
      final context = _runningContext!;
      _runningScript = null;
      _runningContext = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Execute commands directly
  Future<ScriptContext> executeCommands(
    List<ScriptCommand> commands, {
    Map<String, dynamic>? initialVariables,
  }) async {
    final script = Script(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Temporary Script',
      commands: commands,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
    return executeScript(script, initialVariables: initialVariables);
  }

  /// Stop running script
  void stopScript() {
    _runningContext?.stop();
    notifyListeners();
  }

  /// Get execution log from last/current run
  List<String> getExecutionLog() {
    return _runningContext?.log ?? [];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN SCRIPTS
// ═══════════════════════════════════════════════════════════════════════════

/// Built-in script presets
class BuiltInScripts {
  BuiltInScripts._();

  /// Test spin sequence
  static Script testSpinSequence() {
    return Script(
      id: 'builtin_test_spin',
      name: 'Test Spin Sequence',
      description: 'Simulates a basic spin cycle with audio',
      commands: [
        ScriptCommand.log('Starting spin test...'),
        ScriptCommand.triggerStage('UI_SPIN_PRESS'),
        ScriptCommand.wait(500),
        ScriptCommand.triggerStage('REEL_STOP_0'),
        ScriptCommand.wait(200),
        ScriptCommand.triggerStage('REEL_STOP_1'),
        ScriptCommand.wait(200),
        ScriptCommand.triggerStage('REEL_STOP_2'),
        ScriptCommand.wait(200),
        ScriptCommand.triggerStage('REEL_STOP_3'),
        ScriptCommand.wait(200),
        ScriptCommand.triggerStage('REEL_STOP_4'),
        ScriptCommand.wait(300),
        ScriptCommand.triggerStage('SPIN_END'),
        ScriptCommand.log('Spin test complete'),
      ],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  /// Test win sequence
  static Script testWinSequence() {
    return Script(
      id: 'builtin_test_win',
      name: 'Test Win Sequence',
      description: 'Simulates a win presentation',
      commands: [
        ScriptCommand.log('Starting win test...'),
        ScriptCommand.triggerStage('WIN_EVAL'),
        ScriptCommand.wait(200),
        ScriptCommand.triggerStage('WIN_PRESENT'),
        ScriptCommand.wait(500),
        ScriptCommand.triggerStage('WIN_LINE_SHOW'),
        ScriptCommand.wait(300),
        ScriptCommand.triggerStage('WIN_LINE_SHOW'),
        ScriptCommand.wait(300),
        ScriptCommand.triggerStage('WIN_LINE_SHOW'),
        ScriptCommand.wait(500),
        ScriptCommand.triggerStage('WIN_END'),
        ScriptCommand.log('Win test complete'),
      ],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  /// Test big win sequence
  static Script testBigWinSequence() {
    return Script(
      id: 'builtin_test_big_win',
      name: 'Test Big Win Sequence',
      description: 'Simulates a big win celebration',
      commands: [
        ScriptCommand.log('Starting big win test...'),
        ScriptCommand.triggerStage('WIN_EVAL'),
        ScriptCommand.wait(200),
        ScriptCommand.triggerStage('WIN_PRESENT_BIG'),
        ScriptCommand.wait(1000),
        ScriptCommand.triggerStage('ROLLUP_START'),
        ScriptCommand.wait(100),
        for (int i = 0; i < 10; i++) ...[
          ScriptCommand.triggerStage('ROLLUP_TICK'),
          ScriptCommand.wait(100),
        ],
        ScriptCommand.triggerStage('ROLLUP_END'),
        ScriptCommand.wait(500),
        ScriptCommand.triggerStage('WIN_END'),
        ScriptCommand.log('Big win test complete'),
      ],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  /// Get all built-in scripts
  static List<Script> all() {
    return [
      testSpinSequence(),
      testWinSequence(),
      testBigWinSequence(),
    ];
  }
}