/// Intent Rule Editor — Configure spatial behavior per intent
///
/// Features:
/// - List all intent rules with search/filter
/// - Per-rule configuration (weights, panning, distance, Doppler, etc.)
/// - Create/duplicate/delete rules
/// - JSON export/import

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auto_spatial_provider.dart';
import '../../spatial/auto_spatial.dart';
import 'spatial_widgets.dart';

/// Intent Rule Editor widget
class IntentRuleEditor extends StatefulWidget {
  final bool compact;

  const IntentRuleEditor({
    super.key,
    this.compact = false,
  });

  @override
  State<IntentRuleEditor> createState() => _IntentRuleEditorState();
}

class _IntentRuleEditorState extends State<IntentRuleEditor> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoSpatialProvider>(
      builder: (context, provider, _) {
        final rules = provider.allRules.values.toList();
        final filteredRules = _searchQuery.isEmpty
            ? rules
            : rules
                .where((r) =>
                    r.intent.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

        if (widget.compact) {
          return _buildCompactLayout(provider, filteredRules);
        }

        return Row(
          children: [
            // Left: Rule list
            SizedBox(
              width: 220,
              child: _buildRuleList(provider, filteredRules),
            ),

            const VerticalDivider(width: 1, color: Color(0xFF3a3a4a)),

            // Right: Rule editor
            Expanded(
              child: provider.selectedRule != null
                  ? _buildRuleEditor(provider, provider.selectedRule!)
                  : const Center(
                      child: Text(
                        'Select a rule to edit',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompactLayout(
      AutoSpatialProvider provider, List<IntentRule> rules) {
    return Column(
      children: [
        // Search
        _buildSearchBar(),

        // Rule list
        Expanded(
          child: ListView.builder(
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              final isSelected = provider.selectedRuleIntent == rule.intent;

              return _RuleListTile(
                rule: rule,
                isSelected: isSelected,
                compact: true,
                onTap: () => provider.selectRule(rule.intent),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRuleList(AutoSpatialProvider provider, List<IntentRule> rules) {
    return Column(
      children: [
        // Search & Actions
        _buildSearchBar(),

        // Actions
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _ActionButton(
                icon: Icons.add,
                tooltip: 'New Rule',
                onPressed: () => _showCreateDialog(provider),
              ),
              _ActionButton(
                icon: Icons.content_copy,
                tooltip: 'Duplicate',
                onPressed: provider.selectedRule != null
                    ? () => _showDuplicateDialog(provider)
                    : null,
              ),
              _ActionButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete',
                onPressed: provider.selectedRule != null
                    ? () => _showDeleteDialog(provider)
                    : null,
              ),
              const Spacer(),
              _ActionButton(
                icon: Icons.upload,
                tooltip: 'Export JSON',
                onPressed: () => _exportJson(provider),
              ),
              _ActionButton(
                icon: Icons.download,
                tooltip: 'Import JSON',
                onPressed: () => _importJson(provider),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFF3a3a4a)),

        // Rule list
        Expanded(
          child: ListView.builder(
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              final isSelected = provider.selectedRuleIntent == rule.intent;

              return _RuleListTile(
                rule: rule,
                isSelected: isSelected,
                onTap: () => provider.selectRule(rule.intent),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        decoration: InputDecoration(
          hintText: 'Search intents...',
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 14),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          filled: true,
          fillColor: const Color(0xFF121216),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  Widget _buildRuleEditor(AutoSpatialProvider provider, IntentRule rule) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rule.intent,
                  style: const TextStyle(
                    color: Color(0xFF4a9eff),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Reset', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                onPressed: () => provider.resetRuleToDefault(rule.intent),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Fusion Weights
          _SectionHeader(title: 'Fusion Weights'),
          Row(
            children: [
              Expanded(
                child: SpatialSlider(
                  label: 'Anchor',
                  value: rule.wAnchor,
                  onChanged: (v) => _updateRule(provider, rule, wAnchor: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Motion',
                  value: rule.wMotion,
                  onChanged: (v) => _updateRule(provider, rule, wMotion: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Intent',
                  value: rule.wIntent,
                  onChanged: (v) => _updateRule(provider, rule, wIntent: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Panning
          _SectionHeader(title: 'Panning'),
          Row(
            children: [
              Expanded(
                child: SpatialSlider(
                  label: 'Width',
                  value: rule.width,
                  onChanged: (v) => _updateRule(provider, rule, width: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Max Pan',
                  value: rule.maxPan,
                  onChanged: (v) => _updateRule(provider, rule, maxPan: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Deadzone',
                  value: rule.deadzone,
                  max: 0.2,
                  onChanged: (v) => _updateRule(provider, rule, deadzone: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Smoothing
          _SectionHeader(title: 'Smoothing'),
          Row(
            children: [
              Expanded(
                child: SpatialSlider(
                  label: 'Tau (ms)',
                  value: rule.smoothingTauMs,
                  min: 10,
                  max: 500,
                  onChanged: (v) =>
                      _updateRule(provider, rule, smoothingTauMs: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Vel Tau (ms)',
                  value: rule.velocitySmoothingTauMs,
                  min: 10,
                  max: 500,
                  onChanged: (v) =>
                      _updateRule(provider, rule, velocitySmoothingTauMs: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Distance
          _SectionHeader(title: 'Distance'),
          Row(
            children: [
              Expanded(
                child: SpatialDropdown<DistanceModel>(
                  label: 'Model',
                  value: rule.distanceModel,
                  items: DistanceModel.values,
                  onChanged: (v) =>
                      _updateRule(provider, rule, distanceModel: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Min',
                  value: rule.minDistance,
                  max: 1.0,
                  onChanged: (v) => _updateRule(provider, rule, minDistance: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Max',
                  value: rule.maxDistance,
                  max: 2.0,
                  onChanged: (v) => _updateRule(provider, rule, maxDistance: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Rolloff',
                  value: rule.rolloffFactor,
                  max: 3.0,
                  onChanged: (v) =>
                      _updateRule(provider, rule, rolloffFactor: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Doppler
          _SectionHeader(title: 'Doppler'),
          Row(
            children: [
              SpatialToggle(
                label: 'Enable',
                value: rule.enableDoppler,
                onChanged: (v) =>
                    _updateRule(provider, rule, enableDoppler: v),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SpatialSlider(
                  label: 'Scale',
                  value: rule.dopplerScale,
                  max: 2.0,
                  enabled: rule.enableDoppler,
                  onChanged: (v) =>
                      _updateRule(provider, rule, dopplerScale: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Reverb
          _SectionHeader(title: 'Reverb'),
          Row(
            children: [
              Expanded(
                child: SpatialSlider(
                  label: 'Base Send',
                  value: rule.baseReverbSend,
                  onChanged: (v) =>
                      _updateRule(provider, rule, baseReverbSend: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Distance Scale',
                  value: rule.distanceReverbScale,
                  onChanged: (v) =>
                      _updateRule(provider, rule, distanceReverbScale: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Easing & Lifetime
          _SectionHeader(title: 'Motion & Lifetime'),
          Row(
            children: [
              Expanded(
                child: SpatialDropdown<EasingFunction>(
                  label: 'Easing',
                  value: rule.motionEasing,
                  items: EasingFunction.values,
                  onChanged: (v) =>
                      _updateRule(provider, rule, motionEasing: v),
                ),
              ),
              Expanded(
                child: SpatialSlider(
                  label: 'Lifetime (ms)',
                  value: rule.lifetimeMs.toDouble(),
                  min: 100,
                  max: 10000,
                  onChanged: (v) =>
                      _updateRule(provider, rule, lifetimeMs: v.round()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Anchors
          _SectionHeader(title: 'Anchors'),
          Row(
            children: [
              Expanded(
                child: SpatialTextField(
                  label: 'Default Anchor',
                  value: rule.defaultAnchorId ?? '',
                  onChanged: (v) => _updateRule(provider, rule,
                      defaultAnchorId: v.isEmpty ? null : v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SpatialTextField(
                  label: 'Start Fallback',
                  value: rule.startAnchorFallback ?? '',
                  onChanged: (v) => _updateRule(provider, rule,
                      startAnchorFallback: v.isEmpty ? null : v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SpatialTextField(
                  label: 'End Fallback',
                  value: rule.endAnchorFallback ?? '',
                  onChanged: (v) => _updateRule(provider, rule,
                      endAnchorFallback: v.isEmpty ? null : v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _updateRule(
    AutoSpatialProvider provider,
    IntentRule rule, {
    double? wAnchor,
    double? wMotion,
    double? wIntent,
    double? width,
    double? maxPan,
    double? deadzone,
    double? smoothingTauMs,
    double? velocitySmoothingTauMs,
    DistanceModel? distanceModel,
    double? minDistance,
    double? maxDistance,
    double? rolloffFactor,
    bool? enableDoppler,
    double? dopplerScale,
    double? baseReverbSend,
    double? distanceReverbScale,
    EasingFunction? motionEasing,
    int? lifetimeMs,
    String? defaultAnchorId,
    String? startAnchorFallback,
    String? endAnchorFallback,
  }) {
    final newRule = IntentRule(
      intent: rule.intent,
      defaultAnchorId: defaultAnchorId ?? rule.defaultAnchorId,
      startAnchorFallback: startAnchorFallback ?? rule.startAnchorFallback,
      endAnchorFallback: endAnchorFallback ?? rule.endAnchorFallback,
      wAnchor: wAnchor ?? rule.wAnchor,
      wMotion: wMotion ?? rule.wMotion,
      wIntent: wIntent ?? rule.wIntent,
      width: width ?? rule.width,
      deadzone: deadzone ?? rule.deadzone,
      maxPan: maxPan ?? rule.maxPan,
      smoothingTauMs: smoothingTauMs ?? rule.smoothingTauMs,
      velocitySmoothingTauMs:
          velocitySmoothingTauMs ?? rule.velocitySmoothingTauMs,
      distanceModel: distanceModel ?? rule.distanceModel,
      minDistance: minDistance ?? rule.minDistance,
      maxDistance: maxDistance ?? rule.maxDistance,
      rolloffFactor: rolloffFactor ?? rule.rolloffFactor,
      enableDoppler: enableDoppler ?? rule.enableDoppler,
      dopplerScale: dopplerScale ?? rule.dopplerScale,
      yToLPF: rule.yToLPF,
      distanceToLPF: rule.distanceToLPF,
      yToGain: rule.yToGain,
      baseReverbSend: baseReverbSend ?? rule.baseReverbSend,
      distanceReverbScale: distanceReverbScale ?? rule.distanceReverbScale,
      lifetimeMs: lifetimeMs ?? rule.lifetimeMs,
      motionEasing: motionEasing ?? rule.motionEasing,
    );
    provider.updateRule(rule.intent, newRule);
  }

  void _showCreateDialog(AutoSpatialProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF242430),
        title: const Text('New Intent Rule',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Intent name (e.g., MY_CUSTOM_INTENT)',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Create'),
            onPressed: () {
              final intent = controller.text.trim().toUpperCase();
              if (intent.isNotEmpty) {
                provider.createRule(IntentRule(intent: intent));
                provider.selectRule(intent);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showDuplicateDialog(AutoSpatialProvider provider) {
    final controller = TextEditingController(
      text: '${provider.selectedRuleIntent}_COPY',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF242430),
        title: const Text('Duplicate Rule',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'New intent name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Duplicate'),
            onPressed: () {
              final newIntent = controller.text.trim().toUpperCase();
              if (newIntent.isNotEmpty &&
                  provider.selectedRuleIntent != null) {
                provider.duplicateRule(
                    provider.selectedRuleIntent!, newIntent);
                provider.selectRule(newIntent);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(AutoSpatialProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF242430),
        title: const Text('Delete Rule?',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Text(
          'Are you sure you want to delete "${provider.selectedRuleIntent}"?',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
            onPressed: () {
              if (provider.selectedRuleIntent != null) {
                provider.deleteRule(provider.selectedRuleIntent!);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _exportJson(AutoSpatialProvider provider) {
    final json = provider.exportRulesAsJson();
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rules exported to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _importJson(AutoSpatialProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF242430),
          title: const Text('Import Rules JSON',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: 400,
            height: 200,
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              decoration: const InputDecoration(
                hintText: 'Paste JSON here...',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Import'),
              onPressed: () {
                provider.importRulesFromJson(controller.text);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}

/// Rule list tile
class _RuleListTile extends StatelessWidget {
  final IntentRule rule;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _RuleListTile({
    required this.rule,
    required this.isSelected,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? const Color(0xFF4a9eff).withValues(alpha: 0.15)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: compact ? 28 : 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color:
                    isSelected ? const Color(0xFF4a9eff) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  rule.intent,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: compact ? 10 : 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!compact) ...[
                _TagBadge(
                  label: 'W${(rule.width * 100).round()}',
                  color: const Color(0xFF40c8ff),
                ),
                const SizedBox(width: 4),
                if (rule.enableDoppler)
                  const _TagBadge(
                    label: 'D',
                    color: Color(0xFFff9040),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tag badge
class _TagBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _TagBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Section header
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Action button
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 14,
            color: onPressed != null ? Colors.white70 : Colors.white24,
          ),
        ),
      ),
    );
  }
}
