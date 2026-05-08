// file: flutter_ui/lib/services/cortex_daemon_client.dart
/// CORTEX Daemon Client — Claude CLI direct integration.
///
/// Komunikacija direktno sa Claude CLI procesom:
///   streamQuery → `claude -p "..." --output-format stream-json --verbose`
///   getStatus   → provera claude binary dostupnosti
///
/// Nema HTTP servera, nema porta — sve ide direktno kroz claude CLI.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// A single streaming event from the claude CLI.
class DaemonStreamEvent {
  final String type;
  final Map<String, dynamic> data;

  const DaemonStreamEvent({required this.type, required this.data});

  bool get isChunk => type == 'chunk';
  bool get isResult => type == 'result';
  bool get isError => type == 'error';

  /// Text chunk (for type == 'chunk').
  String get text => data['text'] as String? ?? '';

  /// Full content (for type == 'result').
  String get content => data['content'] as String? ?? '';

  /// Model name (for type == 'result').
  String get model => data['model'] as String? ?? '';

  /// Latency in ms (for type == 'result').
  int get latencyMs => (data['latency_ms'] as num?)?.toInt() ?? 0;

  /// Error message (for type == 'error').
  String get errorMessage => data['message'] as String? ?? '';

  /// Cost in USD (for type == 'result').
  double get costUsd => (data['cost_usd'] as num?)?.toDouble() ?? 0.0;

  @override
  String toString() =>
      'DaemonStreamEvent($type, ${text.isNotEmpty ? "${text.length} chars" : content.isNotEmpty ? "${content.length} chars" : errorMessage})';
}

/// Full query response (non-streaming).
class DaemonQueryResponse {
  final String requestId;
  final String content;
  final String model;
  final String source;
  final int latencyMs;
  final int inputTokens;
  final int outputTokens;
  final double costUsd;

  const DaemonQueryResponse({
    required this.requestId,
    required this.content,
    required this.model,
    required this.source,
    required this.latencyMs,
    required this.inputTokens,
    required this.outputTokens,
    required this.costUsd,
  });

  factory DaemonQueryResponse.fromJson(Map<String, dynamic> json) =>
      DaemonQueryResponse(
        requestId: json['request_id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        model: json['model'] as String? ?? '',
        source: json['source'] as String? ?? '',
        latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
        inputTokens: (json['input_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['output_tokens'] as num?)?.toInt() ?? 0,
        costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Daemon status snapshot.
class DaemonStatus {
  final bool running;
  final int uptimeSecs;
  final bool browserConnected;
  final String? browserModel;
  final int totalQueries;
  final int totalBrainQueries;
  final int totalErrors;
  final List<String> availableProviders;

  const DaemonStatus({
    required this.running,
    required this.uptimeSecs,
    required this.browserConnected,
    this.browserModel,
    required this.totalQueries,
    required this.totalBrainQueries,
    required this.totalErrors,
    required this.availableProviders,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLIENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Claude CLI client — direktno poziva claude binary bez HTTP servera.
///
/// Singleton — use [CortexDaemonClient.instance].
class CortexDaemonClient {
  static final CortexDaemonClient instance = CortexDaemonClient._();

  bool _claudeAvailable = false;
  String _claudePath = '';
  String _projectRoot = '';
  Process? _activeProcess;

  /// Whether claude CLI is available.
  bool get isDaemonReachable => _claudeAvailable;

  /// Detected FluxForge repo root (working directory for claude calls).
  /// Empty until first resolution; safe to read after [_ensureProjectRoot].
  // ignore: unnecessary_getters_setters
  String get projectRoot => _projectRoot;

  /// Override the auto-detected project root. Useful when the user opens
  /// a different project — pass its path so Claude has correct context.
  // ignore: unnecessary_getters_setters
  set projectRoot(String value) {
    _projectRoot = value;
  }

  CortexDaemonClient._();

  /// Pronadje putanju do claude binary.
  Future<String?> _findClaude() async {
    // Probaj poznate lokacije
    const candidates = [
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
      '/usr/bin/claude',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    // Probaj 'which claude'
    try {
      final result = await Process.run('which', ['claude'],
          environment: {'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin'});
      final out = (result.stdout as String).trim();
      if (out.isNotEmpty && await File(out).exists()) return out;
    } catch (_) {}
    return null;
  }

  /// Resolve the FluxForge repo root so Claude runs with correct working dir.
  ///
  /// Detection strategy (first hit wins):
  ///   1. Env override: `FLUXFORGE_REPO`
  ///   2. Walk parents of [Platform.resolvedExecutable] looking for repo
  ///      markers (`pubspec.yaml` + `flutter_ui` ili `Cargo.toml` + `crates/`).
  ///   3. Walk parents of [Directory.current.path] same way.
  ///   4. Probe known fallback: `$HOME/Projects/fluxforge-studio`.
  ///   5. Final fallback: `$HOME` (better than `/`).
  ///
  /// Cached on first call.
  Future<String> _ensureProjectRoot() async {
    if (_projectRoot.isNotEmpty) return _projectRoot;

    // 1. Env override
    final envRepo = Platform.environment['FLUXFORGE_REPO'];
    if (envRepo != null && envRepo.isNotEmpty && await Directory(envRepo).exists()) {
      _projectRoot = envRepo;
      return _projectRoot;
    }

    // Helper: walk up checking markers
    Future<String?> walkForMarkers(String start) async {
      var dir = Directory(start);
      // Cap walk at 12 levels to avoid runaway loops on weird FS.
      for (var i = 0; i < 12; i++) {
        final pubspec = File('${dir.path}/pubspec.yaml');
        final flutterUi = Directory('${dir.path}/flutter_ui');
        final crates = Directory('${dir.path}/crates');
        final cargo = File('${dir.path}/Cargo.toml');
        final git = Directory('${dir.path}/.git');

        // Strong match: FluxForge repo top (has crates/ AND flutter_ui/)
        if (await crates.exists() && await flutterUi.exists()) {
          return dir.path;
        }
        // Workspace Cargo.toml at root
        if (await cargo.exists() && await crates.exists()) {
          return dir.path;
        }
        // flutter_ui dir itself
        if (await pubspec.exists() && await flutterUi.exists()) {
          return dir.path;
        }
        // Generic git root
        if (await git.exists()) {
          return dir.path;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break; // hit FS root
        dir = parent;
      }
      return null;
    }

    // 2. Walk from executable path (works in dev `flutter run`)
    try {
      final exe = Platform.resolvedExecutable;
      if (exe.isNotEmpty) {
        final found = await walkForMarkers(File(exe).parent.path);
        if (found != null) {
          _projectRoot = found;
          return _projectRoot;
        }
      }
    } catch (_) {}

    // 3. Walk from current working directory
    try {
      final cwd = Directory.current.path;
      if (cwd.isNotEmpty && cwd != '/') {
        final found = await walkForMarkers(cwd);
        if (found != null) {
          _projectRoot = found;
          return _projectRoot;
        }
      }
    } catch (_) {}

    // 4. Known fallback path
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      const knownPaths = [
        '/Projects/fluxforge-studio',
        '/Documents/fluxforge-studio',
        '/fluxforge-studio',
      ];
      for (final rel in knownPaths) {
        final candidate = '$home$rel';
        if (await Directory(candidate).exists()) {
          _projectRoot = candidate;
          return _projectRoot;
        }
      }
    }

    // 5. Last resort: $HOME (NEVER `/` — that's what caused the original bug)
    _projectRoot = home.isNotEmpty ? home : Directory.current.path;
    return _projectRoot;
  }

  /// Check if claude CLI is available.
  Future<DaemonStatus?> getStatus() async {
    final path = await _findClaude();
    if (path == null) {
      _claudeAvailable = false;
      return null;
    }
    _claudePath = path;
    _claudeAvailable = true;
    return DaemonStatus(
      running: true,
      uptimeSecs: 0,
      browserConnected: false,
      totalQueries: 0,
      totalBrainQueries: 0,
      totalErrors: 0,
      availableProviders: ['claude-cli'],
    );
  }

  /// Stream a query — yields events as they arrive from claude CLI.
  ///
  /// Events:
  ///   - chunk: partial text (real-time as Claude streams)
  ///   - result: final complete response with metadata
  ///   - error: something went wrong
  ///
  /// [workingDirectory] overrides the auto-detected FluxForge repo root.
  /// If null, the resolved project root is used so Claude has correct context.
  Stream<DaemonStreamEvent> streamQuery(
    String content, {
    String context = '',
    String? systemPrompt,
    String? workingDirectory,
  }) async* {
    // Nađi claude binary ako nismo
    if (_claudePath.isEmpty) {
      final found = await _findClaude();
      if (found == null) {
        _claudeAvailable = false;
        yield DaemonStreamEvent(
          type: 'error',
          data: {'message': 'claude CLI nije pronađen. Instaliraj Claude Code.'},
        );
        return;
      }
      _claudePath = found;
    }
    _claudeAvailable = true;

    // Resolve working directory — NEVER let claude run from `/`.
    final cwd = workingDirectory ?? await _ensureProjectRoot();

    // Sagradi prompt — ubaci context ako postoji + repo info
    final repoHint = 'WORKING_DIR: $cwd\n';
    final fullContent = context.isNotEmpty
        ? '$repoHint\nKONTEKST:\n$context\n\nPITANJE:\n$content'
        : '$repoHint\n$content';

    // Napravi argumente
    final args = <String>[
      '--print',
      '--output-format',
      'stream-json',
      '--verbose',
    ];

    // System prompt via --system-prompt flag ako postoji
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      args.addAll(['--system-prompt', systemPrompt]);
    }

    // Prompt
    args.add(fullContent);

    Process process;
    try {
      process = await Process.start(
        _claudePath,
        args,
        workingDirectory: cwd,
        environment: {
          'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${Platform.environment['PATH'] ?? ''}',
          'HOME': Platform.environment['HOME'] ?? '',
          'USER': Platform.environment['USER'] ?? '',
          'PWD': cwd,
        },
        runInShell: false,
      );
      _activeProcess = process;
    } catch (e) {
      _claudeAvailable = false;
      yield DaemonStreamEvent(
        type: 'error',
        data: {'message': 'Ne mogu da pokrenem claude: $e'},
      );
      return;
    }

    // Buffer za akumulaciju teksta (za finalni result event)
    final buffer = StringBuffer();
    String finalModel = 'claude';
    int durationMs = 0;
    double totalCost = 0.0;

    // Parsiraj stdout — svaka linija je JSON event
    final stdoutStream = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in stdoutStream) {
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'assistant') {
            // Streaming text chunk
            final message = json['message'] as Map<String, dynamic>?;
            final contentBlocks = message?['content'] as List<dynamic>?;
            for (final block in contentBlocks ?? []) {
              if (block is Map && block['type'] == 'text') {
                final text = block['text'] as String? ?? '';
                if (text.isNotEmpty) {
                  buffer.write(text);
                  yield DaemonStreamEvent(
                    type: 'chunk',
                    data: {'text': text},
                  );
                }
              }
            }
            // Izvuci model ime
            if (message?['model'] is String) {
              finalModel = message!['model'] as String;
            }
          } else if (type == 'result') {
            // Finalni rezultat
            durationMs = (json['duration_ms'] as num?)?.toInt() ?? 0;
            totalCost = (json['total_cost_usd'] as num?)?.toDouble() ?? 0.0;
            final resultText = json['result'] as String?;
            final finalContent = resultText ?? buffer.toString();

            yield DaemonStreamEvent(
              type: 'result',
              data: {
                'content': finalContent,
                'model': finalModel,
                'latency_ms': durationMs,
                'cost_usd': totalCost,
              },
            );
            break; // Gotovo
          } else if (type == 'system') {
            // Ignore init/hook events
          }
        } catch (_) {
          // Malformed JSON — skip
        }
      }
    } catch (e) {
      yield DaemonStreamEvent(
        type: 'error',
        data: {'message': 'Stream error: $e'},
      );
    } finally {
      _activeProcess = null;
      // Cleanup process
      try {
        process.kill();
      } catch (_) {}
    }

    // Ako nismo dobili result event ali imamo buffer
    if (buffer.isNotEmpty && durationMs == 0) {
      yield DaemonStreamEvent(
        type: 'result',
        data: {
          'content': buffer.toString(),
          'model': finalModel,
          'latency_ms': 0,
          'cost_usd': totalCost,
        },
      );
    }
  }

  /// Cancel the active streaming query.
  void cancelActive() {
    try {
      _activeProcess?.kill();
    } catch (_) {}
    _activeProcess = null;
  }

  /// Send a blocking query (waits for full response).
  Future<DaemonQueryResponse> query(
    String content, {
    String context = '',
    String? systemPrompt,
    String? workingDirectory,
    int timeoutSecs = 300,
  }) async {
    final cwd = workingDirectory ?? await _ensureProjectRoot();
    final repoHint = 'WORKING_DIR: $cwd\n';
    final fullContent = context.isNotEmpty
        ? '$repoHint\nKONTEKST:\n$context\n\nPITANJE:\n$content'
        : '$repoHint\n$content';

    if (_claudePath.isEmpty) {
      final found = await _findClaude();
      if (found == null) throw DaemonClientException('claude CLI nije pronađen', 0);
      _claudePath = found;
    }

    final args = ['--print', '--output-format', 'stream-json', '--verbose', fullContent];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      args.insertAll(0, ['--system-prompt', systemPrompt]);
    }

    final result = await Process.run(
      _claudePath,
      args,
      workingDirectory: cwd,
      environment: {
        'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${Platform.environment['PATH'] ?? ''}',
        'HOME': Platform.environment['HOME'] ?? '',
        'USER': Platform.environment['USER'] ?? '',
        'PWD': cwd,
      },
    ).timeout(Duration(seconds: timeoutSecs));

    final lines = (result.stdout as String).split('\n');
    String content2 = '';
    String model = 'claude';
    int latencyMs = 0;
    double costUsd = 0.0;

    for (final line in lines) {
      if (line.isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final type = json['type'] as String?;
        if (type == 'result') {
          content2 = json['result'] as String? ?? '';
          latencyMs = (json['duration_ms'] as num?)?.toInt() ?? 0;
          costUsd = (json['total_cost_usd'] as num?)?.toDouble() ?? 0.0;
        } else if (type == 'assistant') {
          final message = json['message'] as Map<String, dynamic>?;
          if (message?['model'] is String) model = message!['model'] as String;
        }
      } catch (_) {}
    }

    return DaemonQueryResponse(
      requestId: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content2,
      model: model,
      source: 'claude-cli',
      latencyMs: latencyMs,
      inputTokens: 0,
      outputTokens: 0,
      costUsd: costUsd,
    );
  }

  /// Dispose.
  void dispose() {
    cancelActive();
  }
}

/// Exception from daemon client operations.
class DaemonClientException implements Exception {
  final String message;
  final int statusCode;
  const DaemonClientException(this.message, this.statusCode);

  @override
  String toString() => 'DaemonClientException($statusCode): $message';
}
