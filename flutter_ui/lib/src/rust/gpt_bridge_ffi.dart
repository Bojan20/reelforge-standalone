/// GPT Browser Bridge FFI Bindings
///
/// Dart FFI bindings for the CORTEX ↔ ChatGPT Browser bridge.
/// Communicates with ChatGPT through a Chrome extension + WebSocket — no API key.
///
/// Functions:
///   - gpt_bridge_is_ready() → is WS server running?
///   - gpt_bridge_browser_connected() → is Chrome extension connected?
///   - gpt_bridge_send_query(query, context, intent) → send to ChatGPT
///   - gpt_bridge_drain_responses_json() → poll for ChatGPT responses
///   - gpt_bridge_stats_json() → bridge statistics
///   - gpt_bridge_update_config(json) → runtime config
///   - gpt_bridge_clear_conversation() → new chat
///   - gpt_bridge_shutdown() → graceful shutdown

import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// A response from ChatGPT received through the browser bridge.
class GptBridgeResponse {
  final String requestId;
  final String content;
  final String model;
  final int latencyMs;
  final bool fromBrowser;

  const GptBridgeResponse({
    required this.requestId,
    required this.content,
    required this.model,
    required this.latencyMs,
    required this.fromBrowser,
  });

  factory GptBridgeResponse.fromJson(Map<String, dynamic> json) {
    return GptBridgeResponse(
      requestId: json['request_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      model: json['model'] as String? ?? '',
      latencyMs: json['latency_ms'] as int? ?? 0,
      fromBrowser: json['from_browser'] as bool? ?? true,
    );
  }

  @override
  String toString() =>
      'GptBridgeResponse(model=$model, latency=${latencyMs}ms, '
      'content=${content.length > 80 ? '${content.substring(0, 80)}...' : content})';
}

/// Bridge statistics.
class GptBridgeStats {
  final int totalRequests;
  final int totalResponses;
  final int totalErrors;
  final bool browserConnected;
  final String? browserModel;
  final int pingLatencyMs;
  final int conversationExchanges;
  final int autonomousQueries;
  final int userQueries;
  final int unknownPatternStreak;

  const GptBridgeStats({
    required this.totalRequests,
    required this.totalResponses,
    required this.totalErrors,
    required this.browserConnected,
    this.browserModel,
    required this.pingLatencyMs,
    required this.conversationExchanges,
    required this.autonomousQueries,
    required this.userQueries,
    required this.unknownPatternStreak,
  });

  factory GptBridgeStats.fromJson(Map<String, dynamic> json) {
    final decision = json['decision'] as Map<String, dynamic>? ?? {};
    return GptBridgeStats(
      totalRequests: json['total_requests'] as int? ?? 0,
      totalResponses: json['total_responses'] as int? ?? 0,
      totalErrors: json['total_errors'] as int? ?? 0,
      browserConnected: json['browser_connected'] as bool? ?? false,
      browserModel: json['browser_model'] as String?,
      pingLatencyMs: json['ping_latency_ms'] as int? ?? -1,
      conversationExchanges: json['conversation_exchanges'] as int? ?? 0,
      autonomousQueries: decision['autonomous_queries'] as int? ?? 0,
      userQueries: decision['user_queries'] as int? ?? 0,
      unknownPatternStreak: decision['unknown_pattern_streak'] as int? ?? 0,
    );
  }

  bool get isActive => browserConnected;
}

/// Query intent — what kind of answer is expected.
enum GptQueryIntent {
  analysis,
  architecture,
  debugging,
  codeReview,
  insight,
  creative,
  userQuery;

  String get ffiValue {
    switch (this) {
      case GptQueryIntent.analysis:
        return 'analysis';
      case GptQueryIntent.architecture:
        return 'architecture';
      case GptQueryIntent.debugging:
        return 'debugging';
      case GptQueryIntent.codeReview:
        return 'code_review';
      case GptQueryIntent.insight:
        return 'insight';
      case GptQueryIntent.creative:
        return 'creative';
      case GptQueryIntent.userQuery:
        return 'user_query';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FFI BINDINGS (extension on NativeFFI)
// ═══════════════════════════════════════════════════════════════════════════════

extension GptBridgeFFI on NativeFFI {
  // --- Function lookups (lazy, cached) ---

  static final _isReady = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(),
      int Function()>('gpt_bridge_is_ready');

  static final _browserConnected = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(),
      int Function()>('gpt_bridge_browser_connected');

  static final _statsJson = NativeFFI.instance.lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('gpt_bridge_stats_json');

  static final _sendQuery = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
      int Function(
          Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>('gpt_bridge_send_query');

  static final _drainResponsesJson = NativeFFI.instance.lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('gpt_bridge_drain_responses_json');

  static final _updateConfig = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('gpt_bridge_update_config');

  static final _clearConversation = NativeFFI.instance.lib.lookupFunction<
      Void Function(),
      void Function()>('gpt_bridge_clear_conversation');

  static final _shutdown = NativeFFI.instance.lib.lookupFunction<
      Void Function(),
      void Function()>('gpt_bridge_shutdown');

  static final _freeString = NativeFFI.instance.lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('gpt_bridge_free_string');

  // --- Public API ---

  /// Is the GPT Browser Bridge ready (WebSocket server running)?
  bool gptBridgeIsReady() => _isReady() != 0;

  /// Is the Chrome extension / browser tab connected?
  bool gptBridgeBrowserConnected() => _browserConnected() != 0;

  /// Get bridge statistics.
  GptBridgeStats gptBridgeStats() {
    final ptr = _statsJson();
    try {
      final json = ptr.toDartString();
      final map = jsonDecode(json) as Map<String, dynamic>;
      return GptBridgeStats.fromJson(map);
    } finally {
      _freeString(ptr);
    }
  }

  /// Send a query to ChatGPT via the browser bridge.
  /// Returns true if the query was sent successfully.
  bool gptBridgeSendQuery(
    String query, {
    String context = '',
    GptQueryIntent intent = GptQueryIntent.userQuery,
  }) {
    final pQuery = query.toNativeUtf8();
    final pContext = context.toNativeUtf8();
    final pIntent = intent.ffiValue.toNativeUtf8();
    try {
      return _sendQuery(pQuery, pContext, pIntent) != 0;
    } finally {
      calloc.free(pQuery);
      calloc.free(pContext);
      calloc.free(pIntent);
    }
  }

  /// Drain all pending GPT responses.
  /// Call this periodically (e.g., every 500ms) to receive ChatGPT answers.
  List<GptBridgeResponse> gptBridgeDrainResponses() {
    final ptr = _drainResponsesJson();
    try {
      final json = ptr.toDartString();
      if (json == '[]') return const [];
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => GptBridgeResponse.fromJson(e as Map<String, dynamic>))
          .toList();
    } finally {
      _freeString(ptr);
    }
  }

  /// Update bridge configuration at runtime.
  bool gptBridgeUpdateConfig({
    bool? autonomousEnabled,
    int? minQueryIntervalSecs,
    int? responseTimeoutSecs,
  }) {
    final config = <String, dynamic>{};
    if (autonomousEnabled != null) {
      config['autonomous_enabled'] = autonomousEnabled;
    }
    if (minQueryIntervalSecs != null) {
      config['min_query_interval_secs'] = minQueryIntervalSecs;
    }
    if (responseTimeoutSecs != null) {
      config['response_timeout_secs'] = responseTimeoutSecs;
    }

    final pJson = jsonEncode(config).toNativeUtf8();
    try {
      return _updateConfig(pJson) != 0;
    } finally {
      calloc.free(pJson);
    }
  }

  /// Clear conversation memory and start new chat in browser.
  void gptBridgeClearConversation() => _clearConversation();

  /// Shutdown the bridge gracefully.
  void gptBridgeShutdown() => _shutdown();
}
