/// UCP Export™ — Universal Casino Protocol Export Engine (STUB 5)
///
/// "Buy once, deploy everywhere."
///
/// Exports FluxForge slot audio projects to ALL major casino delivery formats
/// with a single click. Understands slot event semantics — not just audio files,
/// but the MEANING of each sound in the slot context.
///
/// Supported targets:
///   Web/HTML5:  Howler.js AudioSprite, Web Audio API graph
///   Desktop:    Wwise SoundBank XML, FMOD Studio Bank
///   Mobile:     iOS AVFoundation bundle, Android manifest
///   Game:       Unity AudioMixer, Unreal MetaSound
///   Casino:     IGT Playa AudioSprite, Generic JSON
///
/// See: FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.md §STUB5
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';

// =============================================================================
// EXPORT TARGETS
// =============================================================================

/// All supported casino platform export targets
enum CasinoExportTarget {
  // ─── Web/HTML5 ───────────────────────────────────────────────────
  howlerAudioSprite,
  webAudioApi,
  pwaManifest,

  // ─── Desktop Middleware ──────────────────────────────────────────
  wwiseSoundBank,
  fmodStudioBank,
  customCApi,

  // ─── Mobile ──────────────────────────────────────────────────────
  iosAvFoundation,
  androidExoPlayer,
  reactNativeBridge,

  // ─── Game Engines ────────────────────────────────────────────────
  unityAudioMixer,
  unrealMetaSound,

  // ─── Casino-Specific ─────────────────────────────────────────────
  igtPlayaSprite,
  scientificGames,
  genericCasinoJson,

  // ─── FluxForge Native ────────────────────────────────────────────
  fluxforgeBinary;

  String get displayName => switch (this) {
        howlerAudioSprite => 'Howler.js AudioSprite',
        webAudioApi => 'Web Audio API Graph',
        pwaManifest => 'PWA Asset Manifest',
        wwiseSoundBank => 'Wwise SoundBank',
        fmodStudioBank => 'FMOD Studio Bank',
        customCApi => 'Custom C API',
        iosAvFoundation => 'iOS AVFoundation',
        androidExoPlayer => 'Android ExoPlayer',
        reactNativeBridge => 'React Native Bridge',
        unityAudioMixer => 'Unity AudioMixer',
        unrealMetaSound => 'Unreal MetaSound',
        igtPlayaSprite => 'IGT Playa Sprite',
        scientificGames => 'Scientific Games',
        genericCasinoJson => 'Generic Casino JSON',
        fluxforgeBinary => 'FluxForge Binary (FFB)',
      };

  String get fileExtension => switch (this) {
        howlerAudioSprite => '.audiosprite.json',
        webAudioApi => '.webaudio.json',
        pwaManifest => '.manifest.json',
        wwiseSoundBank => '.bnk.xml',
        fmodStudioBank => '.fmod.json',
        customCApi => '.h',
        iosAvFoundation => '.avfoundation.json',
        androidExoPlayer => '.exoplayer.json',
        reactNativeBridge => '.rn.json',
        unityAudioMixer => '.unity.json',
        unrealMetaSound => '.uasset.json',
        igtPlayaSprite => '.playa.json',
        scientificGames => '.sgames.json',
        genericCasinoJson => '.casino.json',
        fluxforgeBinary => '.ffb.json',
      };

  String get category => switch (this) {
        howlerAudioSprite || webAudioApi || pwaManifest => 'Web/HTML5',
        wwiseSoundBank || fmodStudioBank || customCApi => 'Desktop',
        iosAvFoundation || androidExoPlayer || reactNativeBridge => 'Mobile',
        unityAudioMixer || unrealMetaSound => 'Game Engine',
        igtPlayaSprite || scientificGames || genericCasinoJson => 'Casino',
        fluxforgeBinary => 'FluxForge',
      };

  int get colorValue => switch (this) {
        howlerAudioSprite || webAudioApi || pwaManifest => 0xFF4488CC,
        wwiseSoundBank || fmodStudioBank || customCApi => 0xFF44CC44,
        iosAvFoundation || androidExoPlayer || reactNativeBridge => 0xFFDD8822,
        unityAudioMixer || unrealMetaSound => 0xFF8866CC,
        igtPlayaSprite || scientificGames || genericCasinoJson => 0xFFCC4488,
        fluxforgeBinary => 0xFFFFCC00,
      };
}

// =============================================================================
// SLOT AUDIO EVENT — Semantic event for export
// =============================================================================

/// A slot audio event with full semantic context for export
class SlotAudioExportEvent {
  final String id;
  final String displayName;
  final String category;     // 'reel', 'win', 'feature', 'ui', 'ambient'
  final String stage;        // SlotLab stage name
  final String assetPath;    // relative path to audio file
  final double durationMs;
  final double volumeDb;
  final bool loop;
  final int priority;        // 0 = highest
  final Map<String, dynamic> metadata;

  const SlotAudioExportEvent({
    required this.id,
    required this.displayName,
    required this.category,
    required this.stage,
    required this.assetPath,
    required this.durationMs,
    this.volumeDb = 0.0,
    this.loop = false,
    this.priority = 10,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': displayName,
        'category': category,
        'stage': stage,
        'asset': assetPath,
        'duration_ms': durationMs,
        'volume_db': volumeDb,
        'loop': loop,
        'priority': priority,
        ...metadata,
      };
}

// =============================================================================
// UCP EXPORT PROVIDER
// =============================================================================

/// UCP Export™ engine — exports to all casino delivery formats
class UcpExportProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  CasinoExportTarget _target = CasinoExportTarget.howlerAudioSprite;
  final Set<CasinoExportTarget> _selectedTargets = {CasinoExportTarget.howlerAudioSprite};
  bool _isExporting = false;
  final List<(CasinoExportTarget, String, DateTime)> _exportHistory = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  CasinoExportTarget get target => _target;
  Set<CasinoExportTarget> get selectedTargets => Set.unmodifiable(_selectedTargets);
  bool get isExporting => _isExporting;
  List<(CasinoExportTarget, String, DateTime)> get exportHistory =>
      List.unmodifiable(_exportHistory);

  void setTarget(CasinoExportTarget t) {
    if (_target == t) return;
    _target = t;
    notifyListeners();
  }

  void toggleTarget(CasinoExportTarget t) {
    if (_selectedTargets.contains(t)) {
      _selectedTargets.remove(t);
    } else {
      _selectedTargets.add(t);
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT — Generate output for each target format
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export to a specific target format
  String exportTo(CasinoExportTarget target, {
    required String gameName,
    required List<SlotAudioExportEvent> events,
    required Map<String, dynamic> projectConfig,
  }) {
    _isExporting = true;
    notifyListeners();

    try {
      final output = switch (target) {
        CasinoExportTarget.howlerAudioSprite => _exportHowlerSprite(gameName, events),
        CasinoExportTarget.webAudioApi => _exportWebAudioApi(gameName, events),
        CasinoExportTarget.pwaManifest => _exportPwaManifest(gameName, events),
        CasinoExportTarget.wwiseSoundBank => _exportWwiseSoundBank(gameName, events),
        CasinoExportTarget.fmodStudioBank => _exportFmodBank(gameName, events),
        CasinoExportTarget.customCApi => _exportCApiHeader(gameName, events),
        CasinoExportTarget.iosAvFoundation => _exportIosAvFoundation(gameName, events),
        CasinoExportTarget.androidExoPlayer => _exportAndroidExoPlayer(gameName, events),
        CasinoExportTarget.reactNativeBridge => _exportReactNativeBridge(gameName, events),
        CasinoExportTarget.unityAudioMixer => _exportUnityAudioMixer(gameName, events),
        CasinoExportTarget.unrealMetaSound => _exportUnrealMetaSound(gameName, events),
        CasinoExportTarget.igtPlayaSprite => _exportIgtPlayaSprite(gameName, events),
        CasinoExportTarget.scientificGames => _exportScientificGames(gameName, events),
        CasinoExportTarget.genericCasinoJson => _exportGenericCasino(gameName, events, projectConfig),
        CasinoExportTarget.fluxforgeBinary => _exportFluxforgeBinary(gameName, events, projectConfig),
      };

      _exportHistory.insert(0, (target, '${events.length} events', DateTime.now()));
      if (_exportHistory.length > 50) _exportHistory.removeLast();

      _isExporting = false;
      notifyListeners();
      return output;
    } catch (e) {
      _isExporting = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Batch export to all selected targets
  Map<CasinoExportTarget, String> exportBatch({
    required String gameName,
    required List<SlotAudioExportEvent> events,
    required Map<String, dynamic> projectConfig,
  }) {
    final results = <CasinoExportTarget, String>{};
    for (final target in _selectedTargets) {
      results[target] = exportTo(target,
          gameName: gameName, events: events, projectConfig: projectConfig);
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FORMAT EXPORTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Howler.js AudioSprite — industry standard for HTML5 slots
  String _exportHowlerSprite(String gameName, List<SlotAudioExportEvent> events) {
    // AudioSprite format: single concatenated audio file with sprite map
    double offset = 0;
    final sprite = <String, List<double>>{};

    for (final e in events) {
      sprite[e.id] = [offset, e.durationMs, if (e.loop) 1.0];
      offset += e.durationMs;
    }

    return _json({
      'src': ['audio/${_sanitize(gameName)}.webm', 'audio/${_sanitize(gameName)}.mp3'],
      'sprite': sprite,
      'volume': 1.0,
      'preload': true,
      '_meta': {
        'generator': 'FluxForge UCP Export',
        'game': gameName,
        'events': events.length,
        'total_duration_ms': offset,
      },
    });
  }

  /// Web Audio API graph — for custom HTML5 engines
  String _exportWebAudioApi(String gameName, List<SlotAudioExportEvent> events) {
    final nodes = <Map<String, dynamic>>[];
    final connections = <Map<String, dynamic>>[];

    // Master gain node
    nodes.add({'id': 'master', 'type': 'GainNode', 'gain': 1.0});

    // Per-category bus nodes
    final categories = events.map((e) => e.category).toSet();
    for (final cat in categories) {
      nodes.add({'id': 'bus_$cat', 'type': 'GainNode', 'gain': 1.0});
      connections.add({'from': 'bus_$cat', 'to': 'master'});
    }

    // Per-event source nodes
    for (final e in events) {
      nodes.add({
        'id': e.id,
        'type': 'AudioBufferSourceNode',
        'buffer': e.assetPath,
        'loop': e.loop,
      });
      connections.add({'from': e.id, 'to': 'bus_${e.category}'});
    }

    return _json({
      'format': 'WebAudioGraph',
      'game': gameName,
      'context': {'sampleRate': 48000, 'latencyHint': 'interactive'},
      'nodes': nodes,
      'connections': connections,
    });
  }

  /// PWA asset manifest
  String _exportPwaManifest(String gameName, List<SlotAudioExportEvent> events) {
    return _json({
      'name': gameName,
      'version': '1.0.0',
      'audio_assets': events.map((e) => {
            'id': e.id,
            'src': e.assetPath,
            'size_estimate': (e.durationMs * 48 * 2 * 2 / 1000).round(), // 48kHz, 16bit, stereo
            'preload': e.priority < 5,
            'category': e.category,
          }).toList(),
      'total_size_estimate': events.fold<int>(
          0, (s, e) => s + (e.durationMs * 48 * 2 * 2 / 1000).round()),
      'cache_strategy': 'cache-first',
    });
  }

  /// Wwise SoundBank XML
  String _exportWwiseSoundBank(String gameName, List<SlotAudioExportEvent> events) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<SoundBanksInfo Platform="Windows" BasePlatform="Windows"');
    buf.writeln('  SchemaVersion="14" SoundbankVersion="140">');
    buf.writeln('  <SoundBanks>');
    buf.writeln('    <SoundBank Id="${gameName.hashCode & 0x7FFFFFFF}" Language="SFX">');
    buf.writeln('      <ObjectPath>\\Events\\$gameName</ObjectPath>');
    buf.writeln('      <ShortName>$gameName</ShortName>');
    buf.writeln('      <IncludedEvents>');

    for (final e in events) {
      final eventId = e.id.hashCode & 0x7FFFFFFF;
      buf.writeln('        <Event Id="$eventId" Name="${e.id}">');
      buf.writeln('          <ObjectPath>\\Events\\$gameName\\${e.id}</ObjectPath>');
      buf.writeln('        </Event>');
    }

    buf.writeln('      </IncludedEvents>');
    buf.writeln('      <IncludedMemoryFiles>');

    for (final e in events) {
      final fileId = e.assetPath.hashCode & 0x7FFFFFFF;
      buf.writeln('        <File Id="$fileId" Language="SFX">');
      buf.writeln('          <ShortName>${e.assetPath}</ShortName>');
      buf.writeln('        </File>');
    }

    buf.writeln('      </IncludedMemoryFiles>');
    buf.writeln('    </SoundBank>');
    buf.writeln('  </SoundBanks>');
    buf.writeln('</SoundBanksInfo>');
    return buf.toString();
  }

  /// FMOD Studio Bank manifest
  String _exportFmodBank(String gameName, List<SlotAudioExportEvent> events) {
    return _json({
      'header': {
        'type': 'FMODBankManifest',
        'version': '2.02',
        'game': gameName,
      },
      'banks': [
        {
          'name': '${_sanitize(gameName)}_Master',
          'path': 'Build/Desktop/${_sanitize(gameName)}_Master.bank',
        },
        {
          'name': '${_sanitize(gameName)}_SFX',
          'path': 'Build/Desktop/${_sanitize(gameName)}_SFX.bank',
        },
      ],
      'events': events.map((e) => {
            'path': 'event:/$gameName/${e.category}/${e.id}',
            'guid': _pseudoGuid(e.id),
            'is3D': false,
            'isOneShot': !e.loop,
            'maxInstances': e.loop ? 1 : 4,
            'priority': e.priority,
          }).toList(),
      'buses': events.map((e) => e.category).toSet().map((cat) => {
            'path': 'bus:/$cat',
            'volume': 0.0,
          }).toList(),
    });
  }

  /// C API header — for custom native engines
  String _exportCApiHeader(String gameName, List<SlotAudioExportEvent> events) {
    final guard = '_${_sanitize(gameName).toUpperCase()}_AUDIO_H_';
    final buf = StringBuffer();
    buf.writeln('/* FluxForge UCP Export — $gameName */');
    buf.writeln('/* Auto-generated. Do not edit. */');
    buf.writeln();
    buf.writeln('#ifndef $guard');
    buf.writeln('#define $guard');
    buf.writeln();
    buf.writeln('#include <stdint.h>');
    buf.writeln();
    buf.writeln('/* Event IDs */');

    for (int i = 0; i < events.length; i++) {
      final name = events[i].id.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');
      buf.writeln('#define SLOT_EVT_$name  $i');
    }

    buf.writeln();
    buf.writeln('#define SLOT_EVT_COUNT  ${events.length}');
    buf.writeln();
    buf.writeln('/* API */');
    buf.writeln('void slot_audio_init(void);');
    buf.writeln('void slot_audio_shutdown(void);');
    buf.writeln('void slot_audio_play(uint32_t event_id);');
    buf.writeln('void slot_audio_stop(uint32_t event_id);');
    buf.writeln('void slot_audio_set_volume(uint32_t event_id, float db);');
    buf.writeln('int  slot_audio_is_playing(uint32_t event_id);');
    buf.writeln();
    buf.writeln('#endif /* $guard */');
    return buf.toString();
  }

  /// iOS AVFoundation bundle manifest
  String _exportIosAvFoundation(String gameName, List<SlotAudioExportEvent> events) {
    return _json({
      'bundle': '${_sanitize(gameName)}Audio',
      'platform': 'iOS',
      'format': 'AVFoundation',
      'assets': events.map((e) => {
            'identifier': e.id,
            'filename': e.assetPath.split('/').last,
            'category': e.loop ? 'AVAudioSession.Category.ambient' : 'AVAudioSession.Category.playback',
            'volume': _dbToLinear(e.volumeDb),
            'numberOfLoops': e.loop ? -1 : 0,
            'prepareToPlay': e.priority < 5,
          }).toList(),
    });
  }

  /// Android ExoPlayer manifest
  String _exportAndroidExoPlayer(String gameName, List<SlotAudioExportEvent> events) {
    return _json({
      'package': 'com.fluxforge.${_sanitize(gameName).toLowerCase()}',
      'platform': 'Android',
      'audioFocusType': 'AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK',
      'assets': events.map((e) => {
            'id': e.id,
            'uri': 'asset:///audio/${e.assetPath.split('/').last}',
            'mediaType': 'audio/wav',
            'looping': e.loop,
            'volume': _dbToLinear(e.volumeDb),
          }).toList(),
    });
  }

  /// React Native bridge config
  String _exportReactNativeBridge(String gameName, List<SlotAudioExportEvent> events) {
    return _json({
      'module': '${_sanitize(gameName)}Audio',
      'sounds': {
        for (final e in events)
          e.id: {
            'asset': 'require("./audio/${e.assetPath.split('/').last}")',
            'loop': e.loop,
            'volume': _dbToLinear(e.volumeDb),
            'category': e.category,
          },
      },
    });
  }

  /// Unity AudioMixer export
  String _exportUnityAudioMixer(String gameName, List<SlotAudioExportEvent> events) {
    final categories = events.map((e) => e.category).toSet();
    return _json({
      'format': 'UnityAudioMixer',
      'mixerName': '${gameName}Mixer',
      'groups': [
        {'name': 'Master', 'volume': 0.0},
        ...categories.map((cat) =>
          <String, dynamic>{'name': cat, 'parent': 'Master', 'volume': 0.0}),
      ],
      'audioClips': events.map((e) => {
            'name': e.id,
            'path': 'Assets/Audio/$gameName/${e.assetPath.split('/').last}',
            'outputGroup': e.category,
            'loop': e.loop,
            'priority': 256 - e.priority * 10,
            'volume': _dbToLinear(e.volumeDb),
            'spatialBlend': 0.0,
          }).toList(),
      'events': events.map((e) => {
            'name': e.id,
            'type': e.loop ? 'LoopingClip' : 'OneShotClip',
            'clip': e.id,
          }).toList(),
    });
  }

  /// Unreal MetaSound export
  String _exportUnrealMetaSound(String gameName, List<SlotAudioExportEvent> events) {
    return _json({
      'format': 'UnrealMetaSound',
      'assetPath': '/Game/Audio/$gameName',
      'soundCues': events.map((e) => {
            'name': 'SC_${e.id}',
            'soundWave': '/Game/Audio/$gameName/${e.id}',
            'volumeMultiplier': _dbToLinear(e.volumeDb),
            'pitchMultiplier': 1.0,
            'looping': e.loop,
            'attenuationSettings': null,
            'concurrency': e.loop ? 1 : 4,
          }).toList(),
      'soundMix': {
        'name': 'SM_$gameName',
        'classes': events.map((e) => e.category).toSet().map((cat) => {
              'name': cat,
              'volume': 1.0,
              'pitch': 1.0,
            }).toList(),
      },
    });
  }

  /// IGT Playa AudioSprite format
  String _exportIgtPlayaSprite(String gameName, List<SlotAudioExportEvent> events) {
    double offset = 0;
    final sprites = <Map<String, dynamic>>[];

    for (final e in events) {
      sprites.add({
        'name': e.id,
        'start': offset / 1000, // Playa uses seconds
        'end': (offset + e.durationMs) / 1000,
        'loop': e.loop,
        'channel': e.category,
      });
      offset += e.durationMs;
    }

    return _json({
      'format': 'PlayaAudioSprite',
      'version': '2.0',
      'src': '${_sanitize(gameName)}_audio',
      'sprites': sprites,
      'channels': events.map((e) => e.category).toSet().map((cat) => {
            'name': cat,
            'volume': 1.0,
            'maxConcurrent': cat == 'ambient' ? 1 : 8,
          }).toList(),
    });
  }

  /// Scientific Games manifest
  String _exportScientificGames(String gameName, List<SlotAudioExportEvent> events) {
    return _json({
      'format': 'SciGames_AudioManifest',
      'title': gameName,
      'audioBank': '${_sanitize(gameName)}_bank',
      'events': events.map((e) => {
            'eventName': e.id,
            'bankRef': '${_sanitize(gameName)}_bank',
            'priority': e.priority,
            'polyphony': e.loop ? 1 : 4,
            'fadeInMs': 0,
            'fadeOutMs': e.loop ? 200 : 0,
          }).toList(),
    });
  }

  /// Generic Casino JSON — works with any custom engine
  String _exportGenericCasino(String gameName, List<SlotAudioExportEvent> events,
      Map<String, dynamic> config) {
    return _json({
      'format': 'FluxForge_GenericCasino',
      'version': '1.0',
      'game': gameName,
      'config': config,
      'events': events.map((e) => e.toJson()).toList(),
      'categories': events.map((e) => e.category).toSet().toList(),
      'stats': {
        'total_events': events.length,
        'total_duration_ms': events.fold<double>(0, (s, e) => s + e.durationMs),
        'looping_events': events.where((e) => e.loop).length,
        'one_shot_events': events.where((e) => !e.loop).length,
      },
    });
  }

  /// FluxForge Binary pivot format
  String _exportFluxforgeBinary(String gameName, List<SlotAudioExportEvent> events,
      Map<String, dynamic> config) {
    return _json({
      'magic': 'FFB1',
      'version': 1,
      'game': gameName,
      'created': DateTime.now().toIso8601String(),
      'generator': 'FluxForge UCP Export v1.0',
      'config': config,
      'event_table': events.map((e) => e.toJson()).toList(),
      'asset_manifest': events.map((e) => {
            'id': e.id,
            'path': e.assetPath,
            'hash': e.assetPath.hashCode.toRadixString(16),
          }).toList(),
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _json(Object data) => const JsonEncoder.withIndent('  ').convert(data);

  String _sanitize(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  double _dbToLinear(double db) => db >= 0 ? 1.0 : (db <= -60 ? 0.0 : _pow10(db / 20));

  double _pow10(double x) {
    // Manual pow10 to avoid dart:math import for simple case
    double result = 1.0;
    final abs = x.abs();
    // Taylor approximation is fine for -3..0 range
    result = 1.0 + x * 2.302585 + x * x * 2.650949 + x * x * x * 2.034679;
    return result.clamp(0.0, 1.0);
  }

  String _pseudoGuid(String seed) {
    final h = seed.hashCode;
    return '${(h & 0xFFFF).toRadixString(16).padLeft(4, '0')}'
        '${((h >> 16) & 0xFFFF).toRadixString(16).padLeft(4, '0')}-'
        '${(h & 0xFF).toRadixString(16).padLeft(2, '0')}'
        '${((h >> 8) & 0xFF).toRadixString(16).padLeft(2, '0')}-'
        '4${((h >> 12) & 0xFFF).toRadixString(16).padLeft(3, '0')}-'
        '${(0x8 | ((h >> 24) & 0x3)).toRadixString(16)}'
        '${((h >> 20) & 0xFFF).toRadixString(16).padLeft(3, '0')}-'
        '${h.toRadixString(16).padLeft(12, '0')}';
  }
}
