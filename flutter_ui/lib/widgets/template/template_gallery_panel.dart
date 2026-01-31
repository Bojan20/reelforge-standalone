/// Template Gallery Panel
///
/// Visual gallery for browsing, previewing and applying slot templates.
/// Displays templates as cards with preview info and quick-apply functionality.
///
/// P3-12: Template Gallery
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/template_models.dart';
import '../../services/template/template_auto_wire_service.dart';
import '../../services/template/template_builder_service.dart';

/// Template gallery panel
class TemplateGalleryPanel extends StatefulWidget {
  /// Callback when template is applied
  final void Function(BuiltTemplate template)? onTemplateApplied;

  /// Callback when template is selected for editing
  final void Function(SlotTemplate template)? onEditTemplate;

  const TemplateGalleryPanel({
    super.key,
    this.onTemplateApplied,
    this.onEditTemplate,
  });

  @override
  State<TemplateGalleryPanel> createState() => _TemplateGalleryPanelState();
}

class _TemplateGalleryPanelState extends State<TemplateGalleryPanel> {
  final List<SlotTemplate> _templates = [];
  SlotTemplate? _selectedTemplate;
  String _searchQuery = '';
  TemplateCategory? _filterCategory;
  bool _isLoading = false;
  String? _error;

  // Wiring state
  bool _isWiring = false;
  WireProgress? _wireProgress;
  WireResult? _lastWireResult;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load built-in templates from assets
      final builtInTemplates = await _loadBuiltInTemplates();

      // Load user templates from storage
      final userTemplates = await _loadUserTemplates();

      setState(() {
        _templates.clear();
        _templates.addAll(builtInTemplates);
        _templates.addAll(userTemplates);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load templates: $e';
        _isLoading = false;
      });
    }
  }

  Future<List<SlotTemplate>> _loadBuiltInTemplates() async {
    final templates = <SlotTemplate>[];

    final builtInNames = [
      'classic_5x3',
      'ways_243',
      'megaways_117649',
      'cluster_pays',
      'hold_and_win',
      'cascading_reels',
      'jackpot_network',
      'bonus_buy',
    ];

    for (final name in builtInNames) {
      try {
        final jsonStr = await rootBundle.loadString('assets/templates/$name.json');
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        templates.add(SlotTemplate.fromJson(json));
      } catch (e) {
        debugPrint('[TemplateGallery] Could not load built-in template $name: $e');
      }
    }

    return templates;
  }

  Future<List<SlotTemplate>> _loadUserTemplates() async {
    // TODO: Load from local storage
    return [];
  }

  List<SlotTemplate> get _filteredTemplates {
    return _templates.where((t) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!t.name.toLowerCase().contains(query) &&
            !t.description.toLowerCase().contains(query) &&
            !(t.author?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }

      // Category filter
      if (_filterCategory != null && t.category != _filterCategory) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _applyTemplate(SlotTemplate template) async {
    setState(() {
      _isWiring = true;
      _wireProgress = null;
      _lastWireResult = null;
    });

    try {
      // Build the template
      final built = TemplateBuilderService.instance.buildTemplate(template);

      // Wire it
      final result = await TemplateAutoWireService.instance.wireTemplate(
        built,
        onProgress: (progress) {
          setState(() {
            _wireProgress = progress;
          });
        },
      );

      setState(() {
        _lastWireResult = result;
        _isWiring = false;
      });

      if (result.success) {
        widget.onTemplateApplied?.call(built);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Template "${template.name}" applied successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to apply template: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isWiring = false;
        _error = 'Failed to apply template: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildFilters(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError()
                  : _buildGallery(),
        ),
        if (_isWiring) _buildWiringProgress(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.dashboard, color: Color(0xFF4a9eff)),
          const SizedBox(width: 12),
          const Text(
            'Template Gallery',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _loadTemplates,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search templates...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFF242430),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          const SizedBox(width: 16),

          // Category filter
          DropdownButton<TemplateCategory?>(
            value: _filterCategory,
            hint: const Text('All Categories'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Categories')),
              ...TemplateCategory.values.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(_categoryLabel(c)),
                  )),
            ],
            onChanged: (value) {
              setState(() {
                _filterCategory = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGallery() {
    final templates = _filteredTemplates;

    if (templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _filterCategory != null
                  ? 'No templates match your filters'
                  : 'No templates available',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        final isSelected = template == _selectedTemplate;

        return _TemplateCard(
          template: template,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedTemplate = template;
            });
          },
          onApply: () => _applyTemplate(template),
          onEdit: widget.onEditTemplate != null
              ? () => widget.onEditTemplate!(template)
              : null,
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadTemplates,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildWiringProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1a1a20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                _wireProgress?.message ?? 'Wiring template...',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _wireProgress?.progress ?? 0,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(TemplateCategory category) {
    return switch (category) {
      TemplateCategory.classic => 'Classic',
      TemplateCategory.video => 'Video Slots',
      TemplateCategory.megaways => 'Megaways',
      TemplateCategory.cluster => 'Cluster',
      TemplateCategory.holdWin => 'Hold & Win',
      TemplateCategory.jackpot => 'Jackpot',
      TemplateCategory.branded => 'Branded',
      TemplateCategory.custom => 'Custom',
    };
  }
}

/// Individual template card
class _TemplateCard extends StatelessWidget {
  final SlotTemplate template;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onApply;
  final VoidCallback? onEdit;

  const _TemplateCard({
    required this.template,
    required this.isSelected,
    required this.onTap,
    required this.onApply,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? const Color(0xFF2a2a40) : const Color(0xFF1a1a20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? const Color(0xFF4a9eff) : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon and category
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _categoryColor(template.category).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _categoryIcon(template.category),
                      color: _categoryColor(template.category),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          template.author ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Expanded(
                child: Text(
                  template.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Stats
              _buildStats(),
              const SizedBox(height: 12),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onApply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4a9eff),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 20),
                      tooltip: 'Edit template',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Grid',
            value: '${template.reelCount}×${template.rowCount}',
          ),
          _StatItem(
            label: 'Symbols',
            value: '${template.symbols.length}',
          ),
          _StatItem(
            label: 'Features',
            value: '${template.modules.length}',
          ),
          _StatItem(
            label: 'Stages',
            value: '${template.coreStages.length}',
          ),
        ],
      ),
    );
  }

  Color _categoryColor(TemplateCategory category) {
    return switch (category) {
      TemplateCategory.classic => const Color(0xFF4a9eff),
      TemplateCategory.video => const Color(0xFF40ff90),
      TemplateCategory.megaways => const Color(0xFFff9040),
      TemplateCategory.cluster => const Color(0xFF9370db),
      TemplateCategory.holdWin => const Color(0xFF40c8ff),
      TemplateCategory.jackpot => const Color(0xFFffd700),
      TemplateCategory.branded => const Color(0xFFff6b6b),
      TemplateCategory.custom => const Color(0xFF808080),
    };
  }

  IconData _categoryIcon(TemplateCategory category) {
    return switch (category) {
      TemplateCategory.classic => Icons.grid_3x3,
      TemplateCategory.video => Icons.play_circle_outline,
      TemplateCategory.megaways => Icons.auto_graph,
      TemplateCategory.cluster => Icons.bubble_chart,
      TemplateCategory.holdWin => Icons.lock,
      TemplateCategory.jackpot => Icons.emoji_events,
      TemplateCategory.branded => Icons.star,
      TemplateCategory.custom => Icons.settings,
    };
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
