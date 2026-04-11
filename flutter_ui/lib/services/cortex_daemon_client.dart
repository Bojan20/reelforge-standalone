// file: flutter_ui/lib/services/cortex_daemon_client.dart
/// CORTEX Daemon Client — SSE streaming connection to cortex-daemon HTTP API.
///
/// Communicates with the daemon at http://127.0.0.1:9743:
///   POST /stream  → SSE streaming (real-time chunks from Claude CLI)
///   POST /query   → Full response (blocking)
///   GET  /status  → Daemon + brain health
///
/// Usage:
/// ```dart
/// final client = CortexDaemonClient();
/// await for (final event in client.streamQuery('Analiziraj ovaj kod')) {
///   if (event.isChunk) print(event.text);  // real-time
///   if (event.isResult) print(event.content); // final
/// }
/// ```

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// A single SSE event from the daemon stream.
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
  String toString() => 'DaemonStreamEvent($type, ${text.isNotEmpty ? "${text.length} chars" : content.length > 0 ? "${content.length} chars" : errorMessage})';
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

  factory DaemonStatus.fromJson(Map<String, dynamic> json) {
    final brain = json['brain'] as Map<String, dynamic>? ?? {};
    return DaemonStatus(
      running: json['daemon'] == 'running',
      uptimeSecs: (json['uptime_secs'] as num?)?.toInt() ?? 0,
      browserConnected: json['browser_connected'] as bool? ?? false,
      browserModel: json['browser_model'] as String?,
      totalQueries: (json['total_queries'] as num?)?.toInt() ?? 0,
      totalBrainQueries: (json['total_brain_queries'] as num?)?.toInt() ?? 0,
      totalErrors: (json['total_errors'] as num?)?.toInt() ?? 0,
      availableProviders: (brain['available_providers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLIENT
// ═══════════════════════════════════════════════════════════════════════════════

/// HTTP + SSE client for the cortex-daemon API.
///
/// Singleton — use [CortexDaemonClient.instance].
class CortexDaemonClient {
  static final CortexDaemonClient instance = CortexDaemonClient._();

  final HttpClient _http = HttpClient();
  final String _host = '127.0.0.1';
  final int _port = 9743;

  bool _daemonReachable = false;

  /// Whether the daemon responded to the last health check.
  bool get isDaemonReachable => _daemonReachable;

  CortexDaemonClient._() {
    _http.connectionTimeout = const Duration(seconds: 5);
  }

  /// Check if daemon is alive.
  Future<DaemonStatus?> getStatus() async {
    try {
      final req = await _http.get(_host, _port, '/status');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        _daemonReachable = false;
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      _daemonReachable = true;
      return DaemonStatus.fromJson(json);
    } catch (_) {
      _daemonReachable = false;
      return null;
    }
  }

  /// Send a blocking query (waits for full response).
  Future<DaemonQueryResponse> query(
    String content, {
    String context = '',
    String? systemPrompt,
    int timeoutSecs = 300,
  }) async {
    final payload = jsonEncode({
      'content': content,
      'context': context,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      'timeout_secs': timeoutSecs,
    });

    final req = await _http.post(_host, _port, '/query');
    req.headers.contentType = ContentType.json;
    req.write(payload);
    final resp = await req.close();

    final body = await resp.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    if (resp.statusCode != 200) {
      throw DaemonClientException(
        json['error'] as String? ?? 'Unknown error',
        resp.statusCode,
      );
    }

    _daemonReachable = true;
    return DaemonQueryResponse.fromJson(json);
  }

  /// Stream a query — returns SSE events as they arrive.
  ///
  /// Events:
  ///   - chunk: partial text (real-time as Claude streams)
  ///   - result: final complete response with metadata
  ///   - error: something went wrong
  Stream<DaemonStreamEvent> streamQuery(
    String content, {
    String context = '',
    String? systemPrompt,
  }) async* {
    final payload = jsonEncode({
      'content': content,
      'context': context,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
    });

    HttpClientResponse resp;
    try {
      final req = await _http.post(_host, _port, '/stream');
      req.headers.contentType = ContentType.json;
      req.write(payload);
      resp = await req.close();
    } catch (e) {
      _daemonReachable = false;
      yield DaemonStreamEvent(
        type: 'error',
        data: {'message': 'Daemon not reachable: $e'},
      );
      return;
    }

    _daemonReachable = true;

    if (resp.statusCode != 200) {
      final body = await resp.transform(utf8.decoder).join();
      yield DaemonStreamEvent(
        type: 'error',
        data: {'message': 'HTTP ${resp.statusCode}: $body'},
      );
      return;
    }

    // Parse SSE stream: each event is "data: {...}\n\n"
    var buffer = '';
    await for (final chunk in resp.transform(utf8.decoder)) {
      buffer += chunk;

      // Process complete SSE events (terminated by double newline)
      while (buffer.contains('\n\n')) {
        final idx = buffer.indexOf('\n\n');
        final eventStr = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 2);

        if (eventStr.isEmpty) continue;

        // Parse "data: <json>" lines
        for (final line in eventStr.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final jsonStr = line.substring(6);
          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = json['type'] as String? ?? 'unknown';
            yield DaemonStreamEvent(type: type, data: json);
          } catch (_) {
            // Malformed JSON — skip
          }
        }
      }
    }
  }

  /// Dispose the HTTP client.
  void dispose() {
    _http.close();
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
