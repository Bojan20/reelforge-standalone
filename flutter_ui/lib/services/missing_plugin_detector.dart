/// Missing Plugin Detector
///
/// Detects missing third-party plugins when loading projects.
/// Provides alternative plugin suggestions and state preservation options.
///
/// Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/plugin_manifest.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MISSING PLUGIN INFO
// ═══════════════════════════════════════════════════════════════════════════

/// Information about a missing plugin
class MissingPluginInfo {
  /// Plugin reference from manifest
  final PluginReference plugin;

  /// Track/slot pairs where this plugin is used
  final List<({int trackId, int slotIndex})> usages;

  /// Whether state is preserved (can be restored if plugin is installed)
  final bool statePreserved;

  /// Whether freeze audio is available
  final bool hasFreezeAudio;

  /// Suggested alternative plugins
  final List<PluginReference> alternatives;

  const MissingPluginInfo({
    required this.plugin,
    required this.usages,
    this.statePreserved = false,
    this.hasFreezeAudio = false,
    this.alternatives = const [],
  });

  /// Number of tracks affected
  int get trackCount => usages.map((u) => u.trackId).toSet().length;

  /// Total number of insert slots affected
  int get slotCount => usages.length;
}

/// Result of missing plugin detection
class MissingPluginReport {
  /// All missing plugins
  final List<MissingPluginInfo> missingPlugins;

  /// Total plugins in project
  final int totalPlugins;

  /// Number of installed plugins
  final int installedPlugins;

  /// When detection was performed
  final DateTime detectedAt;

  const MissingPluginReport({
    required this.missingPlugins,
    required this.totalPlugins,
    required this.installedPlugins,
    required this.detectedAt,
  });

  /// Number of missing plugins
  int get missingCount => missingPlugins.length;

  /// Whether all plugins are available
  bool get allPluginsAvailable => missingPlugins.isEmpty;

  /// Missing plugins that have freeze audio available
  List<MissingPluginInfo> get withFreezeAudio =>
      missingPlugins.where((p) => p.hasFreezeAudio).toList();

  /// Missing plugins that have state preserved
  List<MissingPluginInfo> get withStatePreserved =>
      missingPlugins.where((p) => p.statePreserved).toList();

  /// Missing plugins with no fallback options
  List<MissingPluginInfo> get withNoFallback =>
      missingPlugins.where((p) => !p.hasFreezeAudio && !p.statePreserved).toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN ALTERNATIVES REGISTRY
// ═══════════════════════════════════════════════════════════════════════════

/// Registry of alternative plugins that can replace missing ones
class PluginAlternativesRegistry {
  PluginAlternativesRegistry._();
  static final instance = PluginAlternativesRegistry._();

  /// Map: plugin UID string -> list of alternative UIDs
  final Map<String, List<PluginUid>> _alternatives = {};

  /// Built-in alternatives for common plugins
  void initBuiltInAlternatives() {
    // FF-Q alternatives
    _registerAlternatives(
      PluginUid.vst3('58E595CC2C1242FB8E32F4C9D39C5F42'), // FF-Q 64
      [
        PluginUid.clap('com.toneboosters.equalizer4'),
        PluginUid.vst3('00000000000000000000000000000001'), // Example: TDR Nova
      ],
    );

    // FF-C alternatives
    _registerAlternatives(
      PluginUid.vst3('58E595CC2C1242FB8E32F4C9D39C5F43'), // FF-C
      [
        PluginUid.clap('com.toneboosters.compressor4'),
        PluginUid.vst3('00000000000000000000000000000002'), // Example: TDR Kotelnikov
      ],
    );

  }

  void _registerAlternatives(PluginUid plugin, List<PluginUid> alts) {
    _alternatives[plugin.toString()] = alts;
  }

  /// Register alternative plugins for a given plugin
  void registerAlternatives(PluginUid plugin, List<PluginUid> alternatives) {
    _alternatives[plugin.toString()] = alternatives;
  }

  /// Get alternatives for a plugin
  List<PluginUid> getAlternatives(PluginUid plugin) {
    return _alternatives[plugin.toString()] ?? [];
  }

  /// Check if a plugin has registered alternatives
  bool hasAlternatives(PluginUid plugin) {
    final alts = _alternatives[plugin.toString()];
    return alts != null && alts.isNotEmpty;
  }

  /// Clear all alternatives
  void clear() {
    _alternatives.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MISSING PLUGIN DETECTOR
// ═══════════════════════════════════════════════════════════════════════════

/// Service for detecting missing plugins in a project
class MissingPluginDetector {
  MissingPluginDetector._();
  static final instance = MissingPluginDetector._();

  /// Known plugin installation paths by platform
  List<String> get _pluginPaths {
    if (Platform.isMacOS) {
      return [
        '/Library/Audio/Plug-Ins/VST3',
        '${Platform.environment['HOME']}/Library/Audio/Plug-Ins/VST3',
        '/Library/Audio/Plug-Ins/Components',
        '${Platform.environment['HOME']}/Library/Audio/Plug-Ins/Components',
        '/Library/Audio/Plug-Ins/CLAP',
        '${Platform.environment['HOME']}/Library/Audio/Plug-Ins/CLAP',
      ];
    } else if (Platform.isWindows) {
      return [
        'C:\\Program Files\\Common Files\\VST3',
        'C:\\Program Files\\Common Files\\CLAP',
      ];
    } else if (Platform.isLinux) {
      return [
        '/usr/lib/vst3',
        '${Platform.environment['HOME']}/.vst3',
        '/usr/lib/clap',
        '${Platform.environment['HOME']}/.clap',
      ];
    }
    return [];
  }

  /// Cache of installed plugins (UID -> path)
  final Map<String, String> _installedCache = {};

  /// Scan system for installed plugins
  Future<void> scanInstalledPlugins() async {
    _installedCache.clear();

    for (final basePath in _pluginPaths) {
      final dir = Directory(basePath);
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is! Directory) continue;

        final ext = path.extension(entity.path).toLowerCase();
        if (['.vst3', '.component', '.clap'].contains(ext)) {
          // Extract plugin name from path for basic matching
          final name = path.basenameWithoutExtension(entity.path);
          _installedCache[name.toLowerCase()] = entity.path;
        }
      }
    }

  }

  /// Check if a plugin is installed
  bool isPluginInstalled(PluginReference plugin) {
    // Check by exact UID
    if (_installedCache.containsKey(plugin.uid.uid.toLowerCase())) {
      return true;
    }

    // Check by name (fallback)
    if (_installedCache.containsKey(plugin.name.toLowerCase())) {
      return true;
    }

    // Check known locations from manifest
    for (final loc in plugin.locations) {
      if (File(loc.path).existsSync() || Directory(loc.path).existsSync()) {
        return true;
      }
    }

    return false;
  }

  /// Get plugin installation path
  String? getPluginPath(PluginReference plugin) {
    // Check by name
    final byName = _installedCache[plugin.name.toLowerCase()];
    if (byName != null) return byName;

    // Check known locations
    for (final loc in plugin.locations) {
      if (File(loc.path).existsSync() || Directory(loc.path).existsSync()) {
        return loc.path;
      }
    }

    return null;
  }

  /// Detect missing plugins in a manifest
  Future<MissingPluginReport> detectMissingPlugins(PluginManifest manifest) async {
    // Ensure we have scanned
    if (_installedCache.isEmpty) {
      await scanInstalledPlugins();
    }

    final missingPlugins = <MissingPluginInfo>[];
    int installedCount = 0;

    // Group slot states by plugin UID
    final pluginUsages = <String, List<({int trackId, int slotIndex})>>{};
    for (final slot in manifest.slotStates) {
      final key = slot.plugin.uid.toString();
      pluginUsages.putIfAbsent(key, () => []);
      pluginUsages[key]!.add((trackId: slot.trackId, slotIndex: slot.slotIndex));
    }

    // Check each plugin
    for (final plugin in manifest.plugins.values) {
      final isInstalled = isPluginInstalled(plugin);
      plugin.isInstalled = isInstalled;

      if (isInstalled) {
        installedCount++;
        continue;
      }

      // Plugin is missing
      final usages = pluginUsages[plugin.uid.toString()] ?? [];

      // Check for freeze audio
      bool hasFreezeAudio = false;
      for (final slot in manifest.slotStates) {
        if (slot.plugin.uid == plugin.uid && slot.freezeAudioPath != null) {
          hasFreezeAudio = true;
          break;
        }
      }

      // Check for state preservation
      bool statePreserved = usages.isNotEmpty;

      // Get alternatives
      final alternativeUids = PluginAlternativesRegistry.instance.getAlternatives(plugin.uid);
      final alternatives = <PluginReference>[];
      for (final altUid in alternativeUids) {
        final altPlugin = manifest.getPlugin(altUid);
        if (altPlugin != null && isPluginInstalled(altPlugin)) {
          alternatives.add(altPlugin);
        }
      }

      missingPlugins.add(MissingPluginInfo(
        plugin: plugin,
        usages: usages,
        statePreserved: statePreserved,
        hasFreezeAudio: hasFreezeAudio,
        alternatives: alternatives,
      ));
    }

    return MissingPluginReport(
      missingPlugins: missingPlugins,
      totalPlugins: manifest.plugins.length,
      installedPlugins: installedCount,
      detectedAt: DateTime.now(),
    );
  }

  /// Check a single plugin
  Future<MissingPluginInfo?> checkPlugin(PluginReference plugin) async {
    if (_installedCache.isEmpty) {
      await scanInstalledPlugins();
    }

    if (isPluginInstalled(plugin)) {
      return null; // Plugin is installed
    }

    final alternativeUids = PluginAlternativesRegistry.instance.getAlternatives(plugin.uid);
    final alternatives = <PluginReference>[];

    for (final altUid in alternativeUids) {
      // Would need manifest to get full PluginReference
      // For now, just track that alternatives exist
    }

    return MissingPluginInfo(
      plugin: plugin,
      usages: [],
      statePreserved: true,
      hasFreezeAudio: false,
      alternatives: alternatives,
    );
  }

  /// Clear installed plugin cache
  void clearCache() {
    _installedCache.clear();
  }
}
