// Plugin Models
//
// Professional plugin system for DAW mixer inserts:
// - PluginInfo: Plugin metadata with categories
// - PluginCategory: EQ, Dynamics, Reverb, etc.
// - InsertState: Per-slot state (plugin + bypass)
// - Built-in plugins list (FluxForge Studio native)

import 'package:flutter/material.dart';

/// Plugin category for organization
enum PluginCategory {
  eq('EQ', Icons.graphic_eq, Color(0xFF4A9EFF)),
  dynamics('Dynamics', Icons.compress, Color(0xFFFF9040)),
  reverb('Reverb', Icons.waves, Color(0xFF40C8FF)),
  delay('Delay', Icons.timer, Color(0xFF40FF90)),
  modulation('Modulation', Icons.blur_circular, Color(0xFFFF4090)),
  saturation('Saturation', Icons.whatshot, Color(0xFFFF6B6B)),
  filter('Filter', Icons.filter_list, Color(0xFFFFD43B)),
  utility('Utility', Icons.tune, Color(0xFF94D82D)),
  analyzer('Analyzer', Icons.insights, Color(0xFF845EF7)),
  external_('External', Icons.extension, Color(0xFF748FFC));

  final String label;
  final IconData icon;
  final Color color;

  const PluginCategory(this.label, this.icon, this.color);
}

/// Plugin format (for external plugins)
enum PluginFormat { internal, vst3, au, clap }

/// Plugin information
class PluginInfo {
  final String id;
  final String name;
  final String? shortName; // For compact display (e.g., "EQ" instead of "Pro EQ")
  final PluginCategory category;
  final PluginFormat format;
  final String? vendor;
  final String? version;
  final bool isFavorite;
  final int recentUseCount;
  final DateTime? lastUsed;

  const PluginInfo({
    required this.id,
    required this.name,
    this.shortName,
    required this.category,
    this.format = PluginFormat.internal,
    this.vendor,
    this.version,
    this.isFavorite = false,
    this.recentUseCount = 0,
    this.lastUsed,
  });

  String get displayName => shortName ?? name;

  PluginInfo copyWith({
    String? id,
    String? name,
    String? shortName,
    PluginCategory? category,
    PluginFormat? format,
    String? vendor,
    String? version,
    bool? isFavorite,
    int? recentUseCount,
    DateTime? lastUsed,
  }) {
    return PluginInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      category: category ?? this.category,
      format: format ?? this.format,
      vendor: vendor ?? this.vendor,
      version: version ?? this.version,
      isFavorite: isFavorite ?? this.isFavorite,
      recentUseCount: recentUseCount ?? this.recentUseCount,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

/// Insert slot state
class InsertState {
  final int index;
  final PluginInfo? plugin;
  final bool bypassed;
  final bool isPreFader;

  const InsertState({
    required this.index,
    this.plugin,
    this.bypassed = false,
    required this.isPreFader,
  });

  bool get isEmpty => plugin == null;

  InsertState copyWith({
    int? index,
    PluginInfo? plugin,
    bool? bypassed,
    bool? isPreFader,
    bool clearPlugin = false,
  }) {
    return InsertState(
      index: index ?? this.index,
      plugin: clearPlugin ? null : (plugin ?? this.plugin),
      bypassed: bypassed ?? this.bypassed,
      isPreFader: isPreFader ?? this.isPreFader,
    );
  }
}

/// Channel insert chain (up to 8 slots: 4 pre + 4 post, dynamic display)
class InsertChain {
  final String channelId;
  final List<InsertState> slots;

  InsertChain({
    required this.channelId,
    List<InsertState>? slots,
  }) : slots = slots ?? List.generate(8, (i) => InsertState(
          index: i,
          isPreFader: i < 4,
        ));

  /// Get number of visible pre-fader slots (always show 1 empty + used)
  int get visiblePreSlots {
    int lastUsed = -1;
    for (int i = 0; i < 4; i++) {
      if (slots[i].plugin != null) lastUsed = i;
    }
    return (lastUsed + 2).clamp(1, 4); // Show last used + 1 empty, min 1
  }

  /// Get number of visible post-fader slots (always show 1 empty + used)
  int get visiblePostSlots {
    int lastUsed = -1;
    for (int i = 4; i < 8; i++) {
      if (slots[i].plugin != null) lastUsed = i - 4;
    }
    return (lastUsed + 2).clamp(1, 4); // Show last used + 1 empty, min 1
  }

  /// Get visible pre-fader slots
  List<InsertState> get visiblePreFaderSlots => slots.sublist(0, visiblePreSlots);

  /// Get visible post-fader slots
  List<InsertState> get visiblePostFaderSlots => slots.sublist(4, 4 + visiblePostSlots);

  InsertChain copyWith({
    String? channelId,
    List<InsertState>? slots,
  }) {
    return InsertChain(
      channelId: channelId ?? this.channelId,
      slots: slots ?? this.slots,
    );
  }

  /// Update a single slot
  InsertChain updateSlot(int index, InsertState slot) {
    final newSlots = List<InsertState>.from(slots);
    if (index >= 0 && index < newSlots.length) {
      newSlots[index] = slot;
    }
    return copyWith(slots: newSlots);
  }

  /// Set plugin at slot
  InsertChain setPlugin(int index, PluginInfo? plugin) {
    return updateSlot(index, slots[index].copyWith(
      plugin: plugin,
      clearPlugin: plugin == null,
    ));
  }

  /// Toggle bypass at slot
  InsertChain toggleBypass(int index) {
    return updateSlot(index, slots[index].copyWith(
      bypassed: !slots[index].bypassed,
    ));
  }

  /// Remove plugin at slot
  InsertChain removePlugin(int index) {
    return setPlugin(index, null);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN PLUGINS - FluxForge Studio Native
// ═══════════════════════════════════════════════════════════════════════════

/// All available plugins — ONLY those with Rust engine backend
///
/// Each plugin here has a corresponding InsertProcessor in
/// crates/rf-engine/src/dsp_wrappers.rs (create_processor / create_processor_extended)
class PluginRegistry {
  static const List<PluginInfo> builtIn = [
    // ═══ EQ ═══
    PluginInfo(
      id: 'rf-pro-eq',
      name: 'FF Pro EQ',
      shortName: 'EQ',
      category: PluginCategory.eq,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-ultra-eq',
      name: 'FF Ultra EQ',
      shortName: 'Ultra EQ',
      category: PluginCategory.eq,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-linear-eq',
      name: 'FF Linear Phase EQ',
      shortName: 'Lin EQ',
      category: PluginCategory.eq,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-pultec',
      name: 'FF Pultec EQP-1A',
      shortName: 'Pultec',
      category: PluginCategory.eq,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-api550',
      name: 'FF API 550A',
      shortName: 'API 550',
      category: PluginCategory.eq,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-neve1073',
      name: 'FF Neve 1073',
      shortName: '1073',
      category: PluginCategory.eq,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),

    // ═══ Dynamics ═══
    PluginInfo(
      id: 'rf-compressor',
      name: 'FF Compressor',
      shortName: 'Comp',
      category: PluginCategory.dynamics,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-limiter',
      name: 'FF Limiter',
      shortName: 'Limit',
      category: PluginCategory.dynamics,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-gate',
      name: 'FF Gate',
      category: PluginCategory.dynamics,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-expander',
      name: 'FF Expander',
      shortName: 'Exp',
      category: PluginCategory.dynamics,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
    PluginInfo(
      id: 'rf-deesser',
      name: 'FF De-Esser',
      shortName: 'DeEss',
      category: PluginCategory.dynamics,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),

    // ═══ Reverb ═══
    PluginInfo(
      id: 'rf-reverb',
      name: 'FF Reverb',
      shortName: 'Reverb',
      category: PluginCategory.reverb,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),

    // ═══ Delay ═══
    PluginInfo(
      id: 'rf-delay',
      name: 'FF Delay',
      shortName: 'Delay',
      category: PluginCategory.delay,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),

    // ═══ Saturation ═══
    PluginInfo(
      id: 'rf-saturation',
      name: 'FF Saturator',
      shortName: 'Saturn',
      category: PluginCategory.saturation,
      vendor: 'FluxForge Studio',
      version: '1.0',
    ),
  ];

  /// Get plugins by category
  static List<PluginInfo> byCategory(PluginCategory category) {
    return builtIn.where((p) => p.category == category).toList();
  }

  /// Search plugins
  static List<PluginInfo> search(String query) {
    final q = query.toLowerCase();
    return builtIn.where((p) =>
        p.name.toLowerCase().contains(q) ||
        (p.shortName?.toLowerCase().contains(q) ?? false) ||
        p.category.label.toLowerCase().contains(q)).toList();
  }

  /// Get favorites
  static List<PluginInfo> get favorites {
    return builtIn.where((p) => p.isFavorite).toList();
  }

  /// Get recent plugins (sorted by last use)
  static List<PluginInfo> get recent {
    final sorted = builtIn.where((p) => p.recentUseCount > 0).toList()
      ..sort((a, b) => (b.lastUsed ?? DateTime(0)).compareTo(a.lastUsed ?? DateTime(0)));
    return sorted.take(10).toList();
  }

  /// Get all categories with their plugins
  static Map<PluginCategory, List<PluginInfo>> get categorized {
    final map = <PluginCategory, List<PluginInfo>>{};
    for (final cat in PluginCategory.values) {
      final plugins = byCategory(cat);
      if (plugins.isNotEmpty) {
        map[cat] = plugins;
      }
    }
    return map;
  }
}
