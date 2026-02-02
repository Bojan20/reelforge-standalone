import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents a slot configuration for A/B comparison
class SlotConfiguration {
  final String id;
  final String name;
  final DateTime lastModified;
  final SlotGridConfig grid;
  final List<SlotSymbolConfig> symbols;
  final SlotWinTierConfig winTiers;
  final Map<String, String> audioAssignments;
  final Map<String, dynamic> customData;

  const SlotConfiguration({
    required this.id,
    required this.name,
    required this.lastModified,
    required this.grid,
    required this.symbols,
    required this.winTiers,
    required this.audioAssignments,
    this.customData = const {},
  });

  SlotConfiguration copyWith({
    String? id,
    String? name,
    DateTime? lastModified,
    SlotGridConfig? grid,
    List<SlotSymbolConfig>? symbols,
    SlotWinTierConfig? winTiers,
    Map<String, String>? audioAssignments,
    Map<String, dynamic>? customData,
  }) {
    return SlotConfiguration(
      id: id ?? this.id,
      name: name ?? this.name,
      lastModified: lastModified ?? this.lastModified,
      grid: grid ?? this.grid,
      symbols: symbols ?? this.symbols,
      winTiers: winTiers ?? this.winTiers,
      audioAssignments: audioAssignments ?? this.audioAssignments,
      customData: customData ?? this.customData,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lastModified': lastModified.toIso8601String(),
    'grid': grid.toJson(),
    'symbols': symbols.map((s) => s.toJson()).toList(),
    'winTiers': winTiers.toJson(),
    'audioAssignments': audioAssignments,
    'customData': customData,
  };

  factory SlotConfiguration.fromJson(Map<String, dynamic> json) {
    return SlotConfiguration(
      id: json['id'] as String,
      name: json['name'] as String,
      lastModified: DateTime.parse(json['lastModified'] as String),
      grid: SlotGridConfig.fromJson(json['grid'] as Map<String, dynamic>),
      symbols: (json['symbols'] as List)
          .map((s) => SlotSymbolConfig.fromJson(s as Map<String, dynamic>))
          .toList(),
      winTiers: SlotWinTierConfig.fromJson(json['winTiers'] as Map<String, dynamic>),
      audioAssignments: Map<String, String>.from(json['audioAssignments'] as Map),
      customData: Map<String, dynamic>.from(json['customData'] as Map? ?? {}),
    );
  }
}

class SlotGridConfig {
  final int reels;
  final int rows;
  final int paylines;
  final String mechanic;

  const SlotGridConfig({
    required this.reels,
    required this.rows,
    required this.paylines,
    required this.mechanic,
  });

  Map<String, dynamic> toJson() => {
    'reels': reels,
    'rows': rows,
    'paylines': paylines,
    'mechanic': mechanic,
  };

  factory SlotGridConfig.fromJson(Map<String, dynamic> json) {
    return SlotGridConfig(
      reels: json['reels'] as int,
      rows: json['rows'] as int,
      paylines: json['paylines'] as int,
      mechanic: json['mechanic'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlotGridConfig &&
      other.reels == reels &&
      other.rows == rows &&
      other.paylines == paylines &&
      other.mechanic == mechanic;

  @override
  int get hashCode => Object.hash(reels, rows, paylines, mechanic);
}

class SlotSymbolConfig {
  final String id;
  final String name;
  final String type;
  final Map<int, double> payouts;

  const SlotSymbolConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.payouts,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'payouts': payouts.map((k, v) => MapEntry(k.toString(), v)),
  };

  factory SlotSymbolConfig.fromJson(Map<String, dynamic> json) {
    return SlotSymbolConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      payouts: (json['payouts'] as Map).map(
        (k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble()),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlotSymbolConfig &&
      other.id == id &&
      other.name == name &&
      other.type == type;

  @override
  int get hashCode => Object.hash(id, name, type);
}

class SlotWinTierConfig {
  final double bigWinThreshold;
  final double megaWinThreshold;
  final double epicWinThreshold;
  final int rollupDurationMs;

  const SlotWinTierConfig({
    required this.bigWinThreshold,
    required this.megaWinThreshold,
    required this.epicWinThreshold,
    required this.rollupDurationMs,
  });

  Map<String, dynamic> toJson() => {
    'bigWinThreshold': bigWinThreshold,
    'megaWinThreshold': megaWinThreshold,
    'epicWinThreshold': epicWinThreshold,
    'rollupDurationMs': rollupDurationMs,
  };

  factory SlotWinTierConfig.fromJson(Map<String, dynamic> json) {
    return SlotWinTierConfig(
      bigWinThreshold: (json['bigWinThreshold'] as num).toDouble(),
      megaWinThreshold: (json['megaWinThreshold'] as num).toDouble(),
      epicWinThreshold: (json['epicWinThreshold'] as num).toDouble(),
      rollupDurationMs: json['rollupDurationMs'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlotWinTierConfig &&
      other.bigWinThreshold == bigWinThreshold &&
      other.megaWinThreshold == megaWinThreshold &&
      other.epicWinThreshold == epicWinThreshold &&
      other.rollupDurationMs == rollupDurationMs;

  @override
  int get hashCode => Object.hash(
    bigWinThreshold, megaWinThreshold, epicWinThreshold, rollupDurationMs);
}

/// Type of difference between configurations
enum DiffType { added, removed, changed, unchanged }

/// A single difference item
class ConfigDiff {
  final String category;
  final String path;
  final DiffType type;
  final dynamic valueA;
  final dynamic valueB;

  const ConfigDiff({
    required this.category,
    required this.path,
    required this.type,
    this.valueA,
    this.valueB,
  });
}

/// A/B Configuration Comparison Panel for SlotLab
class ABConfigComparisonPanel extends StatefulWidget {
  final SlotConfiguration? configA;
  final SlotConfiguration? configB;
  final void Function(SlotConfiguration config)? onConfigAChanged;
  final void Function(SlotConfiguration config)? onConfigBChanged;
  final void Function(SlotConfiguration from, SlotConfiguration to)? onCopySettings;
  final VoidCallback? onExportReport;

  const ABConfigComparisonPanel({
    super.key,
    this.configA,
    this.configB,
    this.onConfigAChanged,
    this.onConfigBChanged,
    this.onCopySettings,
    this.onExportReport,
  });

  @override
  State<ABConfigComparisonPanel> createState() => _ABConfigComparisonPanelState();
}

class _ABConfigComparisonPanelState extends State<ABConfigComparisonPanel> {
  String _selectedCategory = 'all';
  bool _showOnlyDifferences = false;

  final List<String> _categories = [
    'all',
    'grid',
    'symbols',
    'winTiers',
    'audio',
  ];

  @override
  Widget build(BuildContext context) {
    final diffs = _computeDiffs();
    final filteredDiffs = _filterDiffs(diffs);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a30)),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Category filter
          _buildCategoryFilter(),

          // Comparison content
          Expanded(
            child: Row(
              children: [
                // Config A
                Expanded(
                  child: _buildConfigColumn(
                    config: widget.configA,
                    label: 'A',
                    color: const Color(0xFF4a9eff),
                    diffs: filteredDiffs,
                    isA: true,
                  ),
                ),

                // Divider with diff indicators
                _buildDiffDivider(filteredDiffs),

                // Config B
                Expanded(
                  child: _buildConfigColumn(
                    config: widget.configB,
                    label: 'B',
                    color: const Color(0xFF40ff90),
                    diffs: filteredDiffs,
                    isA: false,
                  ),
                ),
              ],
            ),
          ),

          // Footer with actions
          _buildFooter(diffs),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a30))),
      ),
      child: Row(
        children: [
          const Icon(Icons.compare_arrows, color: Color(0xFF4a9eff)),
          const SizedBox(width: 12),
          const Flexible(
            child: Text(
              'A/B Configuration Comparison',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Show only differences toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Differences only',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _showOnlyDifferences,
                onChanged: (value) => setState(() => _showOnlyDifferences = value),
                activeColor: const Color(0xFF4a9eff),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a30))),
      ),
      child: Row(
        children: _categories.map((category) {
          final isSelected = _selectedCategory == category;
          final label = category == 'all'
              ? 'All'
              : category == 'winTiers'
                  ? 'Win Tiers'
                  : category[0].toUpperCase() + category.substring(1);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = category),
              backgroundColor: const Color(0xFF2a2a30),
              selectedColor: const Color(0xFF4a9eff).withValues(alpha: 0.3),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF4a9eff) : Colors.white70,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected ? const Color(0xFF4a9eff) : Colors.transparent,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildConfigColumn({
    required SlotConfiguration? config,
    required String label,
    required Color color,
    required List<ConfigDiff> diffs,
    required bool isA,
  }) {
    if (config == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, color: color.withValues(alpha: 0.5), size: 48),
            const SizedBox(height: 12),
            Text(
              'No Config $label',
              style: TextStyle(color: color.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // Would trigger config selection
              },
              child: Text('Load Config', style: TextStyle(color: color)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Config header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Modified: ${_formatDate(config.lastModified)}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Config details
          Expanded(
            child: ListView(
              children: [
                _buildConfigSection(
                  'Grid',
                  [
                    _buildConfigRow('Reels', '${config.grid.reels}', diffs, 'grid.reels', isA),
                    _buildConfigRow('Rows', '${config.grid.rows}', diffs, 'grid.rows', isA),
                    _buildConfigRow('Paylines', '${config.grid.paylines}', diffs, 'grid.paylines', isA),
                    _buildConfigRow('Mechanic', config.grid.mechanic, diffs, 'grid.mechanic', isA),
                  ],
                ),
                _buildConfigSection(
                  'Win Tiers',
                  [
                    _buildConfigRow('Big Win', '${config.winTiers.bigWinThreshold}x', diffs, 'winTiers.bigWinThreshold', isA),
                    _buildConfigRow('Mega Win', '${config.winTiers.megaWinThreshold}x', diffs, 'winTiers.megaWinThreshold', isA),
                    _buildConfigRow('Epic Win', '${config.winTiers.epicWinThreshold}x', diffs, 'winTiers.epicWinThreshold', isA),
                    _buildConfigRow('Rollup', '${config.winTiers.rollupDurationMs}ms', diffs, 'winTiers.rollupDurationMs', isA),
                  ],
                ),
                _buildConfigSection(
                  'Symbols (${config.symbols.length})',
                  config.symbols.map((s) =>
                    _buildConfigRow(s.name, s.type, diffs, 'symbols.${s.id}', isA),
                  ).toList(),
                ),
                _buildConfigSection(
                  'Audio (${config.audioAssignments.length})',
                  config.audioAssignments.entries.map((e) =>
                    _buildConfigRow(e.key, e.value, diffs, 'audio.${e.key}', isA),
                  ).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection(String title, List<Widget> children) {
    if (_showOnlyDifferences && children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildConfigRow(
    String label,
    String value,
    List<ConfigDiff> diffs,
    String path,
    bool isA,
  ) {
    final diff = diffs.where((d) => d.path == path).firstOrNull;
    final diffType = diff?.type ?? DiffType.unchanged;

    if (_showOnlyDifferences && diffType == DiffType.unchanged) {
      return const SizedBox.shrink();
    }

    Color? bgColor;
    Color? textColor;
    IconData? icon;

    switch (diffType) {
      case DiffType.added:
        bgColor = isA ? null : const Color(0xFF40ff90).withValues(alpha: 0.1);
        textColor = isA ? null : const Color(0xFF40ff90);
        icon = isA ? null : Icons.add;
        break;
      case DiffType.removed:
        bgColor = isA ? const Color(0xFFff4040).withValues(alpha: 0.1) : null;
        textColor = isA ? const Color(0xFFff4040) : null;
        icon = isA ? Icons.remove : null;
        break;
      case DiffType.changed:
        bgColor = const Color(0xFFFFD700).withValues(alpha: 0.1);
        textColor = const Color(0xFFFFD700);
        icon = Icons.edit;
        break;
      case DiffType.unchanged:
        bgColor = null;
        textColor = null;
        icon = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor ?? const Color(0xFF0a0a0c),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: textColor?.withValues(alpha: 0.3) ?? const Color(0xFF2a2a30),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: textColor, size: 14),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: textColor ?? Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: textColor ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffDivider(List<ConfigDiff> diffs) {
    final addedCount = diffs.where((d) => d.type == DiffType.added).length;
    final removedCount = diffs.where((d) => d.type == DiffType.removed).length;
    final changedCount = diffs.where((d) => d.type == DiffType.changed).length;

    return Container(
      width: 48,
      decoration: const BoxDecoration(
        border: Border.symmetric(
          vertical: BorderSide(color: Color(0xFF2a2a30)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.compare_arrows, color: Colors.white24, size: 20),
          const SizedBox(height: 16),
          if (addedCount > 0)
            _buildDiffBadge('+$addedCount', const Color(0xFF40ff90)),
          if (removedCount > 0)
            _buildDiffBadge('-$removedCount', const Color(0xFFff4040)),
          if (changedCount > 0)
            _buildDiffBadge('~$changedCount', const Color(0xFFFFD700)),
          if (addedCount == 0 && removedCount == 0 && changedCount == 0)
            const Text(
              'Same',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _buildDiffBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFooter(List<ConfigDiff> diffs) {
    final hasConfigs = widget.configA != null && widget.configB != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2a2a30))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Copy buttons
            if (hasConfigs) ...[
              OutlinedButton.icon(
                onPressed: () {
                  widget.onCopySettings?.call(widget.configA!, widget.configB!);
                  HapticFeedback.mediumImpact();
                  _showCopySnackbar('A', 'B');
                },
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Copy A to B'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4a9eff),
                  side: const BorderSide(color: Color(0xFF4a9eff)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  widget.onCopySettings?.call(widget.configB!, widget.configA!);
                  HapticFeedback.mediumImpact();
                  _showCopySnackbar('B', 'A');
                },
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Copy B to A'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF40ff90),
                  side: const BorderSide(color: Color(0xFF40ff90)),
                ),
              ),
            ],
            const SizedBox(width: 16),
            // Summary
            Text(
              '${diffs.where((d) => d.type != DiffType.unchanged).length} differences',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(width: 16),
            // Export button
            ElevatedButton.icon(
              onPressed: widget.onExportReport,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2a2a30),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCopySnackbar(String from, String to) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied settings from Config $from to Config $to'),
        backgroundColor: const Color(0xFF40ff90),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<ConfigDiff> _computeDiffs() {
    final diffs = <ConfigDiff>[];
    final configA = widget.configA;
    final configB = widget.configB;

    if (configA == null || configB == null) return diffs;

    // Grid diffs
    if (configA.grid.reels != configB.grid.reels) {
      diffs.add(ConfigDiff(
        category: 'grid',
        path: 'grid.reels',
        type: DiffType.changed,
        valueA: configA.grid.reels,
        valueB: configB.grid.reels,
      ));
    }
    if (configA.grid.rows != configB.grid.rows) {
      diffs.add(ConfigDiff(
        category: 'grid',
        path: 'grid.rows',
        type: DiffType.changed,
        valueA: configA.grid.rows,
        valueB: configB.grid.rows,
      ));
    }
    if (configA.grid.paylines != configB.grid.paylines) {
      diffs.add(ConfigDiff(
        category: 'grid',
        path: 'grid.paylines',
        type: DiffType.changed,
        valueA: configA.grid.paylines,
        valueB: configB.grid.paylines,
      ));
    }
    if (configA.grid.mechanic != configB.grid.mechanic) {
      diffs.add(ConfigDiff(
        category: 'grid',
        path: 'grid.mechanic',
        type: DiffType.changed,
        valueA: configA.grid.mechanic,
        valueB: configB.grid.mechanic,
      ));
    }

    // Win tier diffs
    if (configA.winTiers.bigWinThreshold != configB.winTiers.bigWinThreshold) {
      diffs.add(ConfigDiff(
        category: 'winTiers',
        path: 'winTiers.bigWinThreshold',
        type: DiffType.changed,
        valueA: configA.winTiers.bigWinThreshold,
        valueB: configB.winTiers.bigWinThreshold,
      ));
    }
    if (configA.winTiers.megaWinThreshold != configB.winTiers.megaWinThreshold) {
      diffs.add(ConfigDiff(
        category: 'winTiers',
        path: 'winTiers.megaWinThreshold',
        type: DiffType.changed,
        valueA: configA.winTiers.megaWinThreshold,
        valueB: configB.winTiers.megaWinThreshold,
      ));
    }
    if (configA.winTiers.epicWinThreshold != configB.winTiers.epicWinThreshold) {
      diffs.add(ConfigDiff(
        category: 'winTiers',
        path: 'winTiers.epicWinThreshold',
        type: DiffType.changed,
        valueA: configA.winTiers.epicWinThreshold,
        valueB: configB.winTiers.epicWinThreshold,
      ));
    }
    if (configA.winTiers.rollupDurationMs != configB.winTiers.rollupDurationMs) {
      diffs.add(ConfigDiff(
        category: 'winTiers',
        path: 'winTiers.rollupDurationMs',
        type: DiffType.changed,
        valueA: configA.winTiers.rollupDurationMs,
        valueB: configB.winTiers.rollupDurationMs,
      ));
    }

    // Symbol diffs
    final symbolIdsA = configA.symbols.map((s) => s.id).toSet();
    final symbolIdsB = configB.symbols.map((s) => s.id).toSet();

    for (final id in symbolIdsA.difference(symbolIdsB)) {
      diffs.add(ConfigDiff(
        category: 'symbols',
        path: 'symbols.$id',
        type: DiffType.removed,
        valueA: configA.symbols.firstWhere((s) => s.id == id),
      ));
    }
    for (final id in symbolIdsB.difference(symbolIdsA)) {
      diffs.add(ConfigDiff(
        category: 'symbols',
        path: 'symbols.$id',
        type: DiffType.added,
        valueB: configB.symbols.firstWhere((s) => s.id == id),
      ));
    }
    for (final id in symbolIdsA.intersection(symbolIdsB)) {
      final symbolA = configA.symbols.firstWhere((s) => s.id == id);
      final symbolB = configB.symbols.firstWhere((s) => s.id == id);
      if (symbolA != symbolB) {
        diffs.add(ConfigDiff(
          category: 'symbols',
          path: 'symbols.$id',
          type: DiffType.changed,
          valueA: symbolA,
          valueB: symbolB,
        ));
      }
    }

    // Audio assignment diffs
    final audioKeysA = configA.audioAssignments.keys.toSet();
    final audioKeysB = configB.audioAssignments.keys.toSet();

    for (final key in audioKeysA.difference(audioKeysB)) {
      diffs.add(ConfigDiff(
        category: 'audio',
        path: 'audio.$key',
        type: DiffType.removed,
        valueA: configA.audioAssignments[key],
      ));
    }
    for (final key in audioKeysB.difference(audioKeysA)) {
      diffs.add(ConfigDiff(
        category: 'audio',
        path: 'audio.$key',
        type: DiffType.added,
        valueB: configB.audioAssignments[key],
      ));
    }
    for (final key in audioKeysA.intersection(audioKeysB)) {
      if (configA.audioAssignments[key] != configB.audioAssignments[key]) {
        diffs.add(ConfigDiff(
          category: 'audio',
          path: 'audio.$key',
          type: DiffType.changed,
          valueA: configA.audioAssignments[key],
          valueB: configB.audioAssignments[key],
        ));
      }
    }

    return diffs;
  }

  List<ConfigDiff> _filterDiffs(List<ConfigDiff> diffs) {
    if (_selectedCategory == 'all') return diffs;
    return diffs.where((d) => d.category == _selectedCategory).toList();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
