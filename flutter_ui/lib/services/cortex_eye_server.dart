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

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import 'cortex_vision_service.dart';
import 'vision_diff_engine.dart';
import '../providers/slot_lab/game_flow_provider.dart';
import '../providers/slot_lab/slot_lab_coordinator.dart';
import '../providers/slot_lab/slot_voice_mixer_provider.dart';
import '../providers/subsystems/composite_event_system_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX EYE SERVER
// ═══════════════════════════════════════════════════════════════════════════

/// Navigation callbacks registered by the Flutter app
class CortexEyeNav extends ChangeNotifier {
  CortexEyeNav._();
  static final instance = CortexEyeNav._();

  /// Called when CORTEX requests navigation
  void Function(String destination)? onNavigate;

  /// Called when CORTEX wants to change HELIX dock tab (0-11)
  void Function(int tab)? onHelixTab;

  /// Called when CORTEX wants to toggle a HELIX spine panel (0-4)
  void Function(int index)? onHelixSpine;

  /// Called when CORTEX wants to change HELIX mode (0=COMPOSE, 1=FOCUS, 2=ARCHITECT)
  void Function(int mode)? onHelixMode;

  /// Called when CORTEX wants to perform a named action
  void Function(String action, Map<String, dynamic> params)? onHelixAction;

  /// Navigate to a destination: 'slotlab', 'daw', 'helix', 'launcher'
  void navigate(String destination) {
    onNavigate?.call(destination);
  }

  /// Switch HELIX dock tab
  void setHelixTab(int tab) {
    onHelixTab?.call(tab);
  }

  /// Toggle HELIX spine panel
  void setHelixSpine(int index) {
    onHelixSpine?.call(index);
  }

  /// Set HELIX mode
  void setHelixMode(int mode) {
    onHelixMode?.call(mode);
  }

  /// Execute named action
  void helixAction(String action, Map<String, dynamic> params) {
    onHelixAction?.call(action, params);
  }
}

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
      } else if (method == 'POST' && path == '/eye/click') {
        await _handleClick(request);
      } else if (method == 'POST' && path == '/eye/voice') {
        await _handleVoiceAction(request);
      } else if (method == 'GET' && path == '/eye/voice/list') {
        await _handleVoiceList(request);
      } else if (method == 'POST' && path == '/eye/voice/seed') {
        await _handleVoiceSeed(request);
      } else if (method == 'POST' && path == '/eye/navigate') {
        await _handleNavigate(request);
      } else if (method == 'POST' && path == '/eye/helix_tab') {
        await _handleHelixTab(request);
      } else if (method == 'POST' && path == '/eye/helix_spine') {
        await _handleHelixSpine(request);
      } else if (method == 'POST' && path == '/eye/helix_mode') {
        await _handleHelixMode(request);
      } else if (method == 'POST' && path == '/eye/helix_action') {
        await _handleHelixAction(request);
      } else if (method == 'GET' && path == '/eye/fsm_state') {
        await _handleFsmState(request);
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
            'POST /eye/navigate',
            'POST /eye/helix_tab',
            'POST /eye/helix_spine',
            'POST /eye/helix_mode',
            'POST /eye/helix_action',
            'POST /eye/click',
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

  /// GET /eye/fsm_state — read GameFlowProvider state as JSON (for QA automation)
  Future<void> _handleFsmState(HttpRequest request) async {
    try {
      // Dynamic lookup to avoid compile-time dependency cycle
      final gf = GetIt.I<GameFlowProvider>();
      final fs = gf.freeSpinsState;
      final coord = GetIt.I<SlotLabCoordinator>();
      await _json(request, {
        'currentState': gf.currentState.name,
        'isInTransition': gf.isInTransition,
        'isFsAutoLoopActive': gf.isFsAutoLoopActive,
        'transitionsEnabled': gf.transitionsEnabled,
        'totalWin': gf.totalWin,
        'freeSpins': fs == null ? null : {
          'spinsRemaining': fs.spinsRemaining,
          'spinsCompleted': fs.spinsCompleted,
          'totalSpins': fs.totalSpins,
          'accumulatedWin': fs.accumulatedWin,
          'currentMultiplier': fs.currentMultiplier,
        },
        'isSpinning': coord.isSpinning,
        'isPlayingStages': coord.isPlayingStages,
        'isWinPresentationActive': coord.isWinPresentationActive,
      });
    } catch (e) {
      request.response.statusCode = 500;
      await _json(request, {'error': e.toString()});
    }
  }

  /// POST /eye/click — simulate mouse click at screen coordinates (macOS only)
  /// Body: {"x": 450, "y": 425, "double": false}
  Future<void> _handleClick(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try {
      params = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    final x = (params['x'] as num?)?.toInt();
    final y = (params['y'] as num?)?.toInt();
    final isDouble = params['double'] as bool? ?? false;

    if (x == null || y == null) {
      request.response.statusCode = 400;
      await _json(request, {'error': 'Required: x and y coordinates'});
      return;
    }

    try {
      // macOS: osascript to simulate click at absolute screen coordinates
      final clickCmd = isDouble
          ? 'tell application "System Events" to double click at {$x, $y}'
          : 'tell application "System Events" to click at {$x, $y}';

      final result = await Process.run('osascript', ['-e', clickCmd]);

      if (result.exitCode == 0) {
        // Wait a bit then capture screenshot to confirm
        await Future.delayed(const Duration(milliseconds: 500));
        final snapshot = await CortexVisionService.instance.captureFullWindow(
          metadata: {'trigger': 'post_click', 'x': x, 'y': y},
        );
        await _json(request, {
          'success': true,
          'x': x,
          'y': y,
          'double': isDouble,
          'snapshotFile': snapshot?.filePath,
        });
      } else {
        await _json(request, {
          'success': false,
          'error': result.stderr.toString(),
          'hint': 'Ensure Accessibility permissions are granted for Terminal/Claude',
        });
      }
    } catch (e) {
      request.response.statusCode = 500;
      await _json(request, {'error': e.toString()});
    }
  }

  /// POST /eye/helix_tab — Switch HELIX dock tab
  /// Body: {"tab": 0} or {"tab": "AUDIO"}
  /// Tabs: 0=FLOW 1=AUDIO 2=MATH 3=TIMELINE 4=INTEL 5=EXPORT 6=SFX 7=BT 8=DNA 9=AI 10=CLOUD 11=A/B
  Future<void> _handleHelixTab(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try {
      params = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    const tabNames = {
      'flow': 0, 'audio': 1, 'math': 2, 'timeline': 3,
      'intel': 4, 'export': 5, 'sfx': 6, 'bt': 7,
      'dna': 8, 'ai': 9, 'cloud': 10, 'ab': 11,
    };

    int? tabIndex;
    final tabParam = params['tab'];
    if (tabParam is int) {
      tabIndex = tabParam;
    } else if (tabParam is String) {
      tabIndex = tabNames[tabParam.toLowerCase()];
    }

    if (tabIndex == null || tabIndex < 0 || tabIndex > 11) {
      request.response.statusCode = 400;
      await _json(request, {
        'error': 'Required: tab (0-11 or name)',
        'tabs': tabNames,
      });
      return;
    }

    final nav = CortexEyeNav.instance;
    if (nav.onHelixTab == null) {
      request.response.statusCode = 503;
      await _json(request, {'error': 'HELIX not open — navigate to slotlab first'});
      return;
    }

    nav.setHelixTab(tabIndex);
    await Future.delayed(const Duration(milliseconds: 600));

    final snapshot = await CortexVisionService.instance.captureFullWindow(
      metadata: {'trigger': 'helix_tab', 'tab': tabIndex},
    );

    await _json(request, {
      'success': true,
      'tab': tabIndex,
      'snapshotFile': snapshot?.filePath,
    });
  }

  /// POST /eye/helix_spine — Toggle HELIX spine panel (0-4)
  /// Body: {"index": 0} → AUDIO ASSIGN, 1=GAME CONFIG, 2=AI/INTEL, 3=SETTINGS, 4=ANALYTICS
  Future<void> _handleHelixSpine(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try { params = jsonDecode(body) as Map<String, dynamic>; } catch (_) {}

    final index = params['index'] as int?;
    if (index == null || index < 0 || index > 4) {
      request.response.statusCode = 400;
      await _json(request, {'error': 'Required: index (0-4)', 'panels': {
        0: 'AUDIO ASSIGN', 1: 'GAME CONFIG', 2: 'AI / INTEL', 3: 'SETTINGS', 4: 'ANALYTICS',
      }});
      return;
    }

    final nav = CortexEyeNav.instance;
    if (nav.onHelixSpine == null) {
      request.response.statusCode = 503;
      await _json(request, {'error': 'HELIX not open'});
      return;
    }

    nav.setHelixSpine(index);
    await Future.delayed(const Duration(milliseconds: 400));

    final snapshot = await CortexVisionService.instance.captureFullWindow(
      metadata: {'trigger': 'helix_spine', 'index': index},
    );
    await _json(request, {'success': true, 'spineIndex': index, 'snapshotFile': snapshot?.filePath});
  }

  /// POST /eye/helix_mode — Set HELIX mode (0=COMPOSE, 1=FOCUS, 2=ARCHITECT)
  Future<void> _handleHelixMode(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try { params = jsonDecode(body) as Map<String, dynamic>; } catch (_) {}

    const modeNames = {'compose': 0, 'focus': 1, 'architect': 2};
    int? mode;
    final modeParam = params['mode'];
    if (modeParam is int) mode = modeParam;
    else if (modeParam is String) mode = modeNames[modeParam.toLowerCase()];

    if (mode == null || mode < 0 || mode > 2) {
      request.response.statusCode = 400;
      await _json(request, {'error': 'Required: mode (0-2 or name)', 'modes': modeNames});
      return;
    }

    final nav = CortexEyeNav.instance;
    if (nav.onHelixMode == null) {
      request.response.statusCode = 503;
      await _json(request, {'error': 'HELIX not open'});
      return;
    }

    nav.setHelixMode(mode);
    await Future.delayed(const Duration(milliseconds: 400));

    final snapshot = await CortexVisionService.instance.captureFullWindow(
      metadata: {'trigger': 'helix_mode', 'mode': mode},
    );
    await _json(request, {'success': true, 'mode': mode, 'snapshotFile': snapshot?.filePath});
  }

  /// POST /eye/helix_action — Execute a named action in HELIX
  /// Body: {"action": "stage_force", "params": {"stage": "baseGame"}}
  Future<void> _handleHelixAction(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try { params = jsonDecode(body) as Map<String, dynamic>; } catch (_) {}

    final action = params['action'] as String?;
    if (action == null) {
      request.response.statusCode = 400;
      await _json(request, {'error': 'Required: action', 'actions': [
        'stage_force', 'spin', 'stop', 'play', 'pause', 'transport_toggle',
      ]});
      return;
    }

    final nav = CortexEyeNav.instance;
    if (nav.onHelixAction == null) {
      request.response.statusCode = 503;
      await _json(request, {'error': 'HELIX not open'});
      return;
    }

    final actionParams = (params['params'] as Map<String, dynamic>?) ?? {};
    nav.helixAction(action, actionParams);
    await Future.delayed(const Duration(milliseconds: 600));

    final snapshot = await CortexVisionService.instance.captureFullWindow(
      metadata: {'trigger': 'helix_action', 'action': action},
    );
    await _json(request, {'success': true, 'action': action, 'snapshotFile': snapshot?.filePath});
  }

  /// POST /eye/navigate — Flutter-level navigation (no OS accessibility needed)
  /// Body: {"to": "slotlab"} or {"to": "daw"} or {"to": "helix"} or {"to": "launcher"}
  Future<void> _handleNavigate(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try {
      params = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    final destination = params['to'] as String?;
    if (destination == null) {
      request.response.statusCode = 400;
      await _json(request, {'error': 'Required: to (destination name)'});
      return;
    }

    final nav = CortexEyeNav.instance;
    if (nav.onNavigate == null) {
      request.response.statusCode = 503;
      await _json(request, {
        'error': 'Navigation not registered yet — app may still be initializing',
      });
      return;
    }

    nav.navigate(destination);

    // Wait for navigation to settle
    await Future.delayed(const Duration(milliseconds: 800));

    // Capture post-navigation screenshot
    final snapshot = await CortexVisionService.instance.captureFullWindow(
      metadata: {'trigger': 'post_navigate', 'destination': destination},
    );

    await _json(request, {
      'success': true,
      'navigatedTo': destination,
      'snapshotFile': snapshot?.filePath,
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

  // ─── Voice mixer dispatch (Flutter-native, no AX needed) ───────────────────
  //
  // Lets CORTEX programmatically exercise the SlotLab voice mixer interactions
  // (focus-solo, mute, audition, duplicate, remove, open editor) without
  // relying on macOS accessibility click simulation.
  //
  // GET  /eye/voice/list            → JSON list of channels + current solo/mute/selected state
  // POST /eye/voice  body: {"action":"<name>","layerId":"<id>"}
  //   action: focus_solo | mute_toggle | audition | duplicate | remove
  //
  // This gives Claude genuine "hands" on SlotLab mix controls.

  /// POST /eye/voice/seed — create probe composite event with placeholder layers
  /// so the voice mixer has channels to test against without loading a project.
  Future<void> _handleVoiceSeed(HttpRequest request) async {
    CompositeEventSystemProvider? composite;
    try {
      composite = GetIt.I<CompositeEventSystemProvider>();
    } catch (_) {
      request.response.statusCode = 503;
      await _json(request, {'error': 'CompositeEventSystemProvider not registered'});
      return;
    }
    final event = composite.createCompositeEvent(name: '_CortexEyeProbe', category: 'voice');
    // Seed two placeholder layers — Voice + Music.
    // Non-empty paths with valid extensions so the voice mixer's rebuild
    // includes them (empty paths are filtered out even though they pass
    // security validation). Fake paths are fine: we're exercising state
    // logic, not playback.
    final voLayer    = composite.addLayerToEvent(
      event.id,
      audioPath: '/tmp/_cortex_probe_vo.wav',
      name: 'VO Probe',
    );
    final musicLayer = composite.addLayerToEvent(
      event.id,
      audioPath: '/tmp/_cortex_probe_music.wav',
      name: 'Music Probe',
    );

    // Give the voice mixer a frame to sync channels from composite event.
    await Future.delayed(const Duration(milliseconds: 250));

    SlotVoiceMixerProvider? voice;
    try {
      voice = GetIt.I<SlotVoiceMixerProvider>();
    } catch (_) { /* ignore */ }

    await _json(request, {
      'success': true,
      'eventId': event.id,
      'seededLayerIds': [voLayer.id, musicLayer.id],
      'voiceChannelCount': voice?.channels.length ?? 0,
    });
  }

  Future<void> _handleVoiceList(HttpRequest request) async {
    SlotVoiceMixerProvider? provider;
    try {
      provider = GetIt.I<SlotVoiceMixerProvider>();
    } catch (_) {
      request.response.statusCode = 503;
      await _json(request, {'error': 'SlotVoiceMixerProvider not registered'});
      return;
    }
    final channels = provider.channels.map((c) => {
      'layerId': c.layerId,
      'eventId': c.eventId,
      'displayName': c.displayName,
      'audioPath': c.audioPath,
      'busId': c.busId,
      'volume': c.volume,
      'pan': c.pan,
      'panRight': c.panRight,
      'width': c.stereoWidth,
      'inputGainDb': c.inputGain,
      'muted': c.muted,
      'soloed': c.soloed,
      'phaseInvert': c.phaseInvert,
      'isPlaying': c.isPlaying,
    }).toList();
    await _json(request, {
      'channels': channels,
      'selectedChannelId': provider.selectedChannelId,
      'hasSoloActive': provider.hasSoloActive,
      'count': channels.length,
    });
  }

  Future<void> _handleVoiceAction(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    Map<String, dynamic> params = {};
    try {
      params = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    final action  = params['action']  as String?;
    final layerId = params['layerId'] as String?;
    if (action == null || layerId == null) {
      request.response.statusCode = 400;
      await _json(request, {'error': 'Required: action, layerId'});
      return;
    }

    SlotVoiceMixerProvider? provider;
    try {
      provider = GetIt.I<SlotVoiceMixerProvider>();
    } catch (_) {
      request.response.statusCode = 503;
      await _json(request, {'error': 'SlotVoiceMixerProvider not registered'});
      return;
    }

    // Sanity: ensure channel exists
    final exists = provider.channels.any((c) => c.layerId == layerId);
    if (!exists) {
      request.response.statusCode = 404;
      await _json(request, {
        'error': 'layerId not found',
        'layerId': layerId,
        'availableCount': provider.channels.length,
      });
      return;
    }

    switch (action) {
      case 'focus_solo':
        provider.focusAndSoloChannel(layerId);
      case 'mute_toggle':
        provider.toggleMute(layerId);
      case 'audition':
        provider.auditionChannel(layerId);
      case 'duplicate':
        provider.duplicateChannel(layerId);
      case 'remove':
        provider.removeChannel(layerId);
      case 'select':
        provider.selectChannel(layerId);
      default:
        request.response.statusCode = 400;
        await _json(request, {
          'error': 'Unknown action',
          'action': action,
          'valid': ['focus_solo','mute_toggle','audition','duplicate','remove','select'],
        });
        return;
    }

    // Wait a frame for state to settle before snapshotting.
    await Future.delayed(const Duration(milliseconds: 200));

    // Re-read channel state for verification
    final ch = provider.channels.firstWhere(
      (c) => c.layerId == layerId,
      orElse: () => provider!.channels.first,
    );
    await _json(request, {
      'success': true,
      'action': action,
      'layerId': layerId,
      'channelAfter': {
        'displayName': ch.displayName,
        'soloed': ch.soloed,
        'muted': ch.muted,
        'volume': ch.volume,
      },
      'selectedChannelId': provider.selectedChannelId,
      'hasSoloActive': provider.hasSoloActive,
      'totalChannels': provider.channels.length,
    });
  }
}
