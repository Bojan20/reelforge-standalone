/// CortexEyeServer — HTTP server koji daje CORTEX-u oči
///
/// Pokreće se na localhost:7735 i izlaže:
///   GET  /eye/snapshot         → PNG screenshot celog prozora
///   GET  /eye/region/:name     → PNG screenshot specifičnog regiona
///   GET  /eye/regions          → JSON lista registrovanih regiona
///   GET  /eye/state            → JSON opis trenutnog UI stanja
///   GET  /eye/latest           → putanja najnovijeg snimka (JSON)
///   POST /eye/observe          → pokretanje/zaustavljanje auto-observe
///
/// Ovo je CORTEX organ — ne debug alat.
/// Daje mi (Claude Code) pravo vizuelno razumevanje UI-a.
///
/// Koristiti sa bash skriptom:
///   curl -s localhost:7735/eye/snapshot > /tmp/cortex_eye.png
///   # Zatim Read /tmp/cortex_eye.png u Claude Code-u

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cortex_vision_service.dart';
import 'vision_diff_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX EYE SERVER
// ═══════════════════════════════════════════════════════════════════════════

class CortexEyeServer {
  CortexEyeServer._();
  static final instance = CortexEyeServer._();

  static const int port = 7735;
  static const String host = '127.0.0.1';

  HttpServer? _server;
  bool get isRunning => _server != null;

  // ─── Lifecycle ─────────────────────────────────────────────────────────

  /// Start the HTTP server
  Future<bool> start() async {
    if (_server != null) return true;

    try {
      _server = await HttpServer.bind(host, port);
      debugPrint('[CortexEye] 👁 Server started on http://$host:$port');
      _handleRequests(_server!);
      return true;
    } catch (e) {
      debugPrint('[CortexEye] Failed to start: $e');
      return false;
    }
  }

  /// Stop the server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    debugPrint('[CortexEye] Server stopped');
  }

  // ─── Request Handling ──────────────────────────────────────────────────

  void _handleRequests(HttpServer server) {
    server.listen(
      (HttpRequest request) => _dispatch(request),
      onError: (e) => debugPrint('[CortexEye] Server error: $e'),
    );
  }

  Future<void> _dispatch(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // CORS headers for any future web tooling
    request.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

    if (method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    try {
      if (method == 'GET' && path == '/eye/snapshot') {
        await _handleSnapshot(request);
      } else if (method == 'GET' && path.startsWith('/eye/region/')) {
        final name = path.substring('/eye/region/'.length);
        await _handleRegionSnapshot(request, name);
      } else if (method == 'GET' && path == '/eye/regions') {
        await _handleRegions(request);
      } else if (method == 'GET' && path == '/eye/state') {
        await _handleState(request);
      } else if (method == 'GET' && path == '/eye/latest') {
        await _handleLatest(request);
      } else if (method == 'POST' && path == '/eye/observe') {
        await _handleObserve(request);
      } else if (method == 'GET' && path == '/eye/ping') {
        await _json(request, {'status': 'alive', 'port': port});
      } else {
        request.response.statusCode = 404;
        await _json(request, {
          'error': 'Not found',
          'endpoints': [
            'GET /eye/snapshot',
            'GET /eye/region/:name',
            'GET /eye/regions',
            'GET /eye/state',
            'GET /eye/latest',
            'POST /eye/observe',
            'GET /eye/ping',
          ],
        });
      }
    } catch (e) {
      request.response.statusCode = 500;
      await _json(request, {'error': e.toString()});
    }
  }

  // ─── Endpoints ─────────────────────────────────────────────────────────

  /// GET /eye/snapshot — capture full window as PNG
  Future<void> _handleSnapshot(HttpRequest request) async {
    final vision = CortexVisionService.instance;
    final snapshot = await vision.captureFullWindow(
      metadata: {'trigger': 'cortex_eye_http', 'ts': DateTime.now().toIso8601String()},
    );

    if (snapshot == null) {
      request.response.statusCode = 503;
      await _json(request, {
        'error': 'Capture failed — RepaintBoundary may not be mounted yet',
        'hint': 'Ensure app is fully initialized and rootBoundaryKey is attached',
      });
      return;
    }

    // Return raw PNG bytes
    final file = File(snapshot.filePath);
    if (!await file.exists()) {
      request.response.statusCode = 500;
      await _json(request, {'error': 'PNG file not found after capture'});
      return;
    }

    final bytes = await file.readAsBytes();
    request.response.headers
      ..contentType = ContentType('image', 'png')
      ..add('X-Cortex-File', snapshot.filePath)
      ..add('X-Cortex-Resolution', snapshot.resolution)
      ..add('X-Cortex-Size', snapshot.sizeKB)
      ..add('X-Cortex-Timestamp', snapshot.capturedAt.toIso8601String());
    request.response.statusCode = 200;
    request.response.add(bytes);
    await request.response.close();
  }

  /// GET /eye/region/:name — capture specific named region
  Future<void> _handleRegionSnapshot(HttpRequest request, String name) async {
    final vision = CortexVisionService.instance;
    final snapshot = await vision.capture(
      name,
      metadata: {'trigger': 'cortex_eye_http', 'ts': DateTime.now().toIso8601String()},
    );

    if (snapshot == null) {
      request.response.statusCode = 404;
      await _json(request, {
        'error': 'Region "$name" not found or capture failed',
        'available': vision.regions.keys.toList(),
      });
      return;
    }

    final file = File(snapshot.filePath);
    final bytes = await file.readAsBytes();
    request.response.headers
      ..contentType = ContentType('image', 'png')
      ..add('X-Cortex-Region', name)
      ..add('X-Cortex-Resolution', snapshot.resolution)
      ..add('X-Cortex-Size', snapshot.sizeKB);
    request.response.statusCode = 200;
    request.response.add(bytes);
    await request.response.close();
  }

  /// GET /eye/regions — list registered regions
  Future<void> _handleRegions(HttpRequest request) async {
    final vision = CortexVisionService.instance;
    await _json(request, {
      'isObserving': vision.isObserving,
      'pixelRatio': vision.pixelRatio,
      'outputDirectory': vision.outputDirectory,
      'regions': vision.regions.values.map((r) => {
        'name': r.name,
        'description': r.description,
        'registeredAt': r.registeredAt.toIso8601String(),
        'hasKey': r.boundaryKey.currentContext != null,
      }).toList(),
      'snapshots': vision.snapshots.take(5).map((s) => {
        'region': s.regionName,
        'resolution': s.resolution,
        'size': s.sizeKB,
        'capturedAt': s.capturedAt.toIso8601String(),
        'file': s.filePath,
      }).toList(),
    });
  }

  /// GET /eye/state — full UI state description
  Future<void> _handleState(HttpRequest request) async {
    final vision = CortexVisionService.instance;
    final diffs = VisionDiffEngine.instance.allDiffs;

    final regionStates = <Map<String, dynamic>>[];
    for (final r in vision.regions.values) {
      final diff = diffs[r.name];
      final latest = vision.latestFor(r.name);
      regionStates.add({
        'name': r.name,
        'description': r.description,
        'mounted': r.boundaryKey.currentContext != null,
        'lastCapture': latest?.capturedAt.toIso8601String(),
        'lastResolution': latest?.resolution,
        'isFrozen': VisionDiffEngine.instance.isRegionFrozen(r.name),
        'changePercent': diff != null
            ? (diff.changePercent * 100).toStringAsFixed(1)
            : null,
      });
    }

    await _json(request, {
      'timestamp': DateTime.now().toIso8601String(),
      'isObserving': vision.isObserving,
      'totalSnapshots': vision.snapshots.length,
      'frozenRegions': VisionDiffEngine.instance.frozenRegions,
      'recentEvents': vision.events.take(10).map((e) => {
        'type': e.type.name,
        'description': e.description,
        'timestamp': e.timestamp.toIso8601String(),
      }).toList(),
      'regions': regionStates,
    });
  }

  /// GET /eye/latest — path to most recent snapshot file
  Future<void> _handleLatest(HttpRequest request) async {
    final vision = CortexVisionService.instance;
    final latest = vision.snapshots.firstOrNull;

    if (latest == null) {
      await _json(request, {'error': 'No snapshots yet'});
      return;
    }

    await _json(request, {
      'file': latest.filePath,
      'region': latest.regionName,
      'resolution': latest.resolution,
      'size': latest.sizeKB,
      'capturedAt': latest.capturedAt.toIso8601String(),
    });
  }

  /// POST /eye/observe — toggle auto-observation
  Future<void> _handleObserve(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try {
      params = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    final vision = CortexVisionService.instance;
    final action = params['action'] as String? ?? 'toggle';
    final intervalSec = params['intervalSeconds'] as int? ?? 10;

    if (action == 'start' || (action == 'toggle' && !vision.isObserving)) {
      vision.startObserving(interval: Duration(seconds: intervalSec));
      await _json(request, {'status': 'observing', 'intervalSeconds': intervalSec});
    } else {
      vision.stopObserving();
      await _json(request, {'status': 'stopped'});
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  Future<void> _json(HttpRequest request, Map<String, dynamic> data) async {
    request.response.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    request.response.write(const JsonEncoder.withIndent('  ').convert(data));
    await request.response.close();
  }
}
