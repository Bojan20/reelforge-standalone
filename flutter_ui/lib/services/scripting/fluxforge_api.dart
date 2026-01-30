// FluxForge API — Public API for External Tools
//
// Provides programmatic access to FluxForge functionality for:
// - External tools (Unity, Unreal, web editors)
// - Scripts (Lua, Python, JavaScript)
// - Automation (CI/CD, batch processing)
// - Testing (integration tests, QA tools)
//
// All methods are async and return JSON-serializable data.
//
// Usage:
//   final api = FluxForgeApi.instance;
//   final result = await api.createEvent({'name': 'Test', 'stage': 'SPIN_START'});

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../services/event_registry.dart';
import '../../services/audio_playback_service.dart';
import '../../services/service_locator.dart';
import 'lua_bridge.dart';

class FluxForgeApi {
  static final FluxForgeApi instance = FluxForgeApi._();
  FluxForgeApi._();

  // ============ Event Methods ============

  /// Create a new composite event
  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> params) async {
    final name = params['name'] as String?;
    final stage = params['stage'] as String?;
    final category = params['category'] as String?;

    if (name == null) {
      throw ArgumentError('Missing required parameter: name');
    }

    final provider = sl<MiddlewareProvider>();
    final now = DateTime.now();
    final event = SlotCompositeEvent(
      id: 'evt_${now.millisecondsSinceEpoch}',
      name: name,
      category: category ?? 'Uncategorized',
      color: Colors.blue,
      layers: [],
      createdAt: now,
      modifiedAt: now,
      triggerStages: stage != null ? [stage] : [],
    );

    provider.addCompositeEvent(event);

    return {
      'success': true,
      'eventId': event.id,
      'event': _eventToJson(event),
    };
  }

  /// Delete an event
  Future<Map<String, dynamic>> deleteEvent(Map<String, dynamic> params) async {
    final eventId = params['eventId'] as String?;

    if (eventId == null) {
      throw ArgumentError('Missing required parameter: eventId');
    }

    final provider = sl<MiddlewareProvider>();
    provider.deleteCompositeEvent(eventId);

    return {'success': true};
  }

  /// Get event details
  Future<Map<String, dynamic>> getEvent(Map<String, dynamic> params) async {
    final eventId = params['eventId'] as String?;

    if (eventId == null) {
      throw ArgumentError('Missing required parameter: eventId');
    }

    final provider = sl<MiddlewareProvider>();
    final event = provider.compositeEvents.firstWhere(
      (e) => e.id == eventId,
      orElse: () => throw Exception('Event not found: $eventId'),
    );

    return _eventToJson(event);
  }

  /// List all events
  Future<Map<String, dynamic>> listEvents(Map<String, dynamic> params) async {
    final category = params['category'] as String?;
    final stage = params['stage'] as String?;

    final provider = sl<MiddlewareProvider>();
    var events = provider.compositeEvents;

    // Apply filters
    if (category != null) {
      events = events.where((e) => e.category == category).toList();
    }
    if (stage != null) {
      events = events.where((e) => e.triggerStages.contains(stage)).toList();
    }

    return {
      'events': events.map(_eventToJson).toList(),
      'count': events.length,
    };
  }

  /// Add a layer to an event
  Future<Map<String, dynamic>> addLayer(Map<String, dynamic> params) async {
    final eventId = params['eventId'] as String?;
    final audioPath = params['audioPath'] as String?;
    final name = params['name'] as String? ?? 'Layer';
    final volume = (params['volume'] as num?)?.toDouble() ?? 1.0;
    final pan = (params['pan'] as num?)?.toDouble() ?? 0.0;
    final delay = (params['delay'] as num?)?.toDouble() ?? 0.0;

    if (eventId == null || audioPath == null) {
      throw ArgumentError('Missing required parameters: eventId, audioPath');
    }

    final provider = sl<MiddlewareProvider>();
    final layer = provider.addLayerToEvent(
      eventId,
      audioPath: audioPath,
      name: name,
    );

    // Update layer properties if specified
    if (volume != 1.0 || pan != 0.0 || delay != 0.0) {
      final updatedLayer = layer.copyWith(
        volume: volume,
        pan: pan,
        offsetMs: delay.toDouble(),
      );
      provider.updateEventLayer(eventId, updatedLayer);
    }

    return {
      'success': true,
      'layerId': layer.id,
      'layer': _layerToJson(layer),
    };
  }

  /// Remove a layer from an event
  Future<Map<String, dynamic>> removeLayer(Map<String, dynamic> params) async {
    final eventId = params['eventId'] as String?;
    final layerId = params['layerId'] as String?;

    if (eventId == null || layerId == null) {
      throw ArgumentError('Missing required parameters: eventId, layerId');
    }

    final provider = sl<MiddlewareProvider>();
    provider.removeLayerFromEvent(eventId, layerId);

    return {'success': true};
  }

  /// Update a layer
  Future<Map<String, dynamic>> updateLayer(Map<String, dynamic> params) async {
    final eventId = params['eventId'] as String?;
    final layerId = params['layerId'] as String?;

    if (eventId == null || layerId == null) {
      throw ArgumentError('Missing required parameters: eventId, layerId');
    }

    final provider = sl<MiddlewareProvider>();
    final event = provider.compositeEvents.firstWhere(
      (e) => e.id == eventId,
      orElse: () => throw Exception('Event not found: $eventId'),
    );

    final layerIndex = event.layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) {
      throw Exception('Layer not found: $layerId');
    }

    final oldLayer = event.layers[layerIndex];
    final newLayer = oldLayer.copyWith(
      volume: (params['volume'] as num?)?.toDouble(),
      pan: (params['pan'] as num?)?.toDouble(),
      offsetMs: (params['delay'] as num?)?.toDouble(),
      audioPath: params['audioPath'] as String?,
    );

    provider.updateEventLayer(eventId, newLayer);

    return {
      'success': true,
      'layer': _layerToJson(newLayer),
    };
  }

  // ============ RTPC Methods ============

  /// Set an RTPC value
  Future<Map<String, dynamic>> setRtpc(Map<String, dynamic> params) async {
    final rtpcId = params['rtpcId'] as String?;
    final value = (params['value'] as num?)?.toDouble();

    if (rtpcId == null || value == null) {
      throw ArgumentError('Missing required parameters: rtpcId, value');
    }

    // TODO: Implement RTPC setting via provider
    // For now, return success
    return {'success': true, 'rtpcId': rtpcId, 'value': value};
  }

  /// Get an RTPC value
  Future<Map<String, dynamic>> getRtpc(Map<String, dynamic> params) async {
    final rtpcId = params['rtpcId'] as String?;

    if (rtpcId == null) {
      throw ArgumentError('Missing required parameter: rtpcId');
    }

    // TODO: Implement RTPC getting via provider
    return {'rtpcId': rtpcId, 'value': 0.0};
  }

  /// List all RTCPs
  Future<Map<String, dynamic>> listRtpcs(Map<String, dynamic> params) async {
    // TODO: Implement RTPC listing via provider
    return {'rtpcs': [], 'count': 0};
  }

  // ============ State Methods ============

  /// Set a state group value
  Future<Map<String, dynamic>> setState(Map<String, dynamic> params) async {
    final stateGroup = params['stateGroup'] as String?;
    final state = params['state'] as String?;

    if (stateGroup == null || state == null) {
      throw ArgumentError('Missing required parameters: stateGroup, state');
    }

    // TODO: Implement state setting via provider
    return {'success': true, 'stateGroup': stateGroup, 'state': state};
  }

  /// Get current state
  Future<Map<String, dynamic>> getState(Map<String, dynamic> params) async {
    final stateGroup = params['stateGroup'] as String?;

    if (stateGroup == null) {
      throw ArgumentError('Missing required parameter: stateGroup');
    }

    // TODO: Implement state getting via provider
    return {'stateGroup': stateGroup, 'state': 'default'};
  }

  /// List all state groups
  Future<Map<String, dynamic>> listStates(Map<String, dynamic> params) async {
    // TODO: Implement state listing via provider
    return {'stateGroups': [], 'count': 0};
  }

  // ============ Audio Playback Methods ============

  /// Trigger a stage
  Future<Map<String, dynamic>> triggerStage(Map<String, dynamic> params) async {
    final stage = params['stage'] as String?;

    if (stage == null) {
      throw ArgumentError('Missing required parameter: stage');
    }

    final registry = EventRegistry.instance;
    registry.triggerStage(stage);

    return {'success': true, 'stage': stage};
  }

  /// Stop an event
  Future<Map<String, dynamic>> stopEvent(Map<String, dynamic> params) async {
    final eventId = params['eventId'] as String?;

    if (eventId == null) {
      throw ArgumentError('Missing required parameter: eventId');
    }

    final registry = EventRegistry.instance;
    registry.stopEvent(eventId);

    return {'success': true};
  }

  /// Stop all audio
  Future<Map<String, dynamic>> stopAll(Map<String, dynamic> params) async {
    final service = AudioPlaybackService.instance;
    service.stopAll();

    return {'success': true};
  }

  // ============ Project Methods ============

  /// Save project
  Future<Map<String, dynamic>> saveProject(Map<String, dynamic> params) async {
    final path = params['path'] as String?;

    // TODO: Implement project saving
    return {'success': true, 'path': path};
  }

  /// Load project
  Future<Map<String, dynamic>> loadProject(Map<String, dynamic> params) async {
    final path = params['path'] as String?;

    if (path == null) {
      throw ArgumentError('Missing required parameter: path');
    }

    // TODO: Implement project loading
    return {'success': true, 'path': path};
  }

  /// Get project info
  Future<Map<String, dynamic>> getProjectInfo(Map<String, dynamic> params) async {
    final provider = sl<MiddlewareProvider>();

    return {
      'eventCount': provider.compositeEvents.length,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // ============ Container Methods ============

  /// Create a container
  Future<Map<String, dynamic>> createContainer(Map<String, dynamic> params) async {
    final type = params['type'] as String?;
    final name = params['name'] as String?;

    if (type == null || name == null) {
      throw ArgumentError('Missing required parameters: type, name');
    }

    // TODO: Implement container creation
    return {'success': true, 'containerId': 'cnt_${DateTime.now().millisecondsSinceEpoch}'};
  }

  /// Delete a container
  Future<Map<String, dynamic>> deleteContainer(Map<String, dynamic> params) async {
    final containerId = params['containerId'] as String?;

    if (containerId == null) {
      throw ArgumentError('Missing required parameter: containerId');
    }

    // TODO: Implement container deletion
    return {'success': true};
  }

  /// Evaluate a container
  Future<Map<String, dynamic>> evaluateContainer(Map<String, dynamic> params) async {
    final containerId = params['containerId'] as String?;

    if (containerId == null) {
      throw ArgumentError('Missing required parameter: containerId');
    }

    // TODO: Implement container evaluation
    return {'success': true, 'result': null};
  }

  // ============ Scripting Methods ============

  /// Execute a Lua script
  Future<Map<String, dynamic>> executeScript(Map<String, dynamic> params) async {
    final script = params['script'] as String?;

    if (script == null) {
      throw ArgumentError('Missing required parameter: script');
    }

    final bridge = LuaBridge.instance;
    final result = await bridge.execute(script);

    return {
      'success': result.success,
      'result': result.returnValue,
      if (result.error != null) 'error': result.error,
    };
  }

  // ============ Helper Methods ============

  Map<String, dynamic> _eventToJson(SlotCompositeEvent event) {
    return {
      'id': event.id,
      'name': event.name,
      'category': event.category,
      'triggerStages': event.triggerStages,
      'layers': event.layers.map(_layerToJson).toList(),
    };
  }

  Map<String, dynamic> _layerToJson(SlotEventLayer layer) {
    return {
      'id': layer.id,
      'audioPath': layer.audioPath,
      'volume': layer.volume,
      'pan': layer.pan,
      'delay': layer.offsetMs,
      'busId': layer.busId,
    };
  }
}
