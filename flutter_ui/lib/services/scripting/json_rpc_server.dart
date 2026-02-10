// JSON-RPC Server — External API for Tooling
//
// Provides JSON-RPC 2.0 server for external tools, scripts, and automation.
// Runs on localhost HTTP server (default port 8765).
//
// Supported methods:
// - createEvent, addLayer, deleteEvent
// - setRtpc, setState, triggerStage
// - saveProject, getProjectInfo
// - executeScript (Lua)
//
// Usage:
//   await JsonRpcServer.instance.start();
//   // External tool: curl -X POST http://localhost:8765 -d '{"jsonrpc":"2.0","method":"createEvent","params":{"name":"Test"},"id":1}'
//   await JsonRpcServer.instance.stop();

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'fluxforge_api.dart';

class JsonRpcServer {
  static final JsonRpcServer instance = JsonRpcServer._();
  JsonRpcServer._();

  HttpServer? _server;
  int _port = 8765;
  bool _isRunning = false;
  final FluxForgeApi _api = FluxForgeApi.instance;

  /// Request statistics
  int _totalRequests = 0;
  int _successfulRequests = 0;
  int _failedRequests = 0;
  final Map<String, int> _requestsByMethod = {};

  bool get isRunning => _isRunning;
  int get port => _port;

  /// Start the JSON-RPC server
  Future<void> start({int port = 8765}) async {
    if (_isRunning) {
      throw StateError('Server is already running on port $_port');
    }

    _port = port;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      _isRunning = true;


      _server!.listen(_handleRequest);
    } catch (e) {
      rethrow;
    }
  }

  /// Stop the JSON-RPC server
  Future<void> stop() async {
    if (!_isRunning) return;

    await _server?.close(force: true);
    _server = null;
    _isRunning = false;

  }

  /// Handle incoming HTTP request
  void _handleRequest(HttpRequest request) async {
    _totalRequests++;

    // Set CORS headers for browser clients
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    // Handle OPTIONS preflight
    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    // Only accept POST
    if (request.method != 'POST') {
      _sendError(request.response, -32600, 'Invalid Request', null, 'Only POST method is allowed');
      _failedRequests++;
      return;
    }

    // Parse request body
    String body;
    try {
      body = await utf8.decoder.bind(request).join();
    } catch (e) {
      _sendError(request.response, -32700, 'Parse error', null, 'Failed to read request body');
      _failedRequests++;
      return;
    }

    // Parse JSON
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      _sendError(request.response, -32700, 'Parse error', null, 'Invalid JSON');
      _failedRequests++;
      return;
    }

    // Validate JSON-RPC request
    if (json is! Map<String, dynamic>) {
      _sendError(request.response, -32600, 'Invalid Request', null, 'Request must be an object');
      _failedRequests++;
      return;
    }

    final jsonrpc = json['jsonrpc'];
    final method = json['method'];
    final params = json['params'];
    final id = json['id'];

    if (jsonrpc != '2.0') {
      _sendError(request.response, -32600, 'Invalid Request', id, 'Must specify jsonrpc: "2.0"');
      _failedRequests++;
      return;
    }

    if (method is! String) {
      _sendError(request.response, -32600, 'Invalid Request', id, 'Method must be a string');
      _failedRequests++;
      return;
    }

    // Execute method
    try {
      final result = await _executeMethod(method, params);
      _sendResult(request.response, result, id);
      _successfulRequests++;
      _requestsByMethod[method] = (_requestsByMethod[method] ?? 0) + 1;
    } catch (e) {
      _sendError(request.response, -32603, 'Internal error', id, e.toString());
      _failedRequests++;
    }
  }

  /// Execute a JSON-RPC method
  Future<dynamic> _executeMethod(String method, dynamic params) async {
    final paramsMap = params is Map<String, dynamic> ? params : <String, dynamic>{};

    switch (method) {
      // Event methods
      case 'createEvent':
        return await _api.createEvent(paramsMap);
      case 'deleteEvent':
        return await _api.deleteEvent(paramsMap);
      case 'getEvent':
        return await _api.getEvent(paramsMap);
      case 'listEvents':
        return await _api.listEvents(paramsMap);
      case 'addLayer':
        return await _api.addLayer(paramsMap);
      case 'removeLayer':
        return await _api.removeLayer(paramsMap);
      case 'updateLayer':
        return await _api.updateLayer(paramsMap);

      // RTPC methods
      case 'setRtpc':
        return await _api.setRtpc(paramsMap);
      case 'getRtpc':
        return await _api.getRtpc(paramsMap);
      case 'listRtpcs':
        return await _api.listRtpcs(paramsMap);

      // State methods
      case 'setState':
        return await _api.setState(paramsMap);
      case 'getState':
        return await _api.getState(paramsMap);
      case 'listStates':
        return await _api.listStates(paramsMap);

      // Audio playback
      case 'triggerStage':
        return await _api.triggerStage(paramsMap);
      case 'stopEvent':
        return await _api.stopEvent(paramsMap);
      case 'stopAll':
        return await _api.stopAll(paramsMap);

      // Project methods
      case 'saveProject':
        return await _api.saveProject(paramsMap);
      case 'loadProject':
        return await _api.loadProject(paramsMap);
      case 'getProjectInfo':
        return await _api.getProjectInfo(paramsMap);

      // Container methods
      case 'createContainer':
        return await _api.createContainer(paramsMap);
      case 'deleteContainer':
        return await _api.deleteContainer(paramsMap);
      case 'evaluateContainer':
        return await _api.evaluateContainer(paramsMap);

      // Scripting
      case 'executeScript':
        return await _api.executeScript(paramsMap);

      // System
      case 'ping':
        return {'pong': true, 'timestamp': DateTime.now().toIso8601String()};
      case 'getStats':
        return getStats();

      default:
        throw Exception('Method not found: $method');
    }
  }

  /// Send JSON-RPC success response
  void _sendResult(HttpResponse response, dynamic result, dynamic id) {
    final json = {
      'jsonrpc': '2.0',
      'result': result,
      'id': id,
    };

    response.headers.contentType = ContentType.json;
    response.statusCode = 200;
    response.write(jsonEncode(json));
    response.close();
  }

  /// Send JSON-RPC error response
  void _sendError(
    HttpResponse response,
    int code,
    String message,
    dynamic id,
    String? data,
  ) {
    final json = {
      'jsonrpc': '2.0',
      'error': {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      },
      'id': id,
    };

    response.headers.contentType = ContentType.json;
    response.statusCode = 200; // JSON-RPC errors still return 200
    response.write(jsonEncode(json));
    response.close();
  }

  /// Get server statistics
  Map<String, dynamic> getStats() {
    return {
      'isRunning': _isRunning,
      'port': _port,
      'totalRequests': _totalRequests,
      'successfulRequests': _successfulRequests,
      'failedRequests': _failedRequests,
      'successRate': _totalRequests > 0
          ? '${(_successfulRequests / _totalRequests * 100).toStringAsFixed(1)}%'
          : '0%',
      'requestsByMethod': _requestsByMethod,
    };
  }

  /// Reset statistics
  void resetStats() {
    _totalRequests = 0;
    _successfulRequests = 0;
    _failedRequests = 0;
    _requestsByMethod.clear();
  }
}
