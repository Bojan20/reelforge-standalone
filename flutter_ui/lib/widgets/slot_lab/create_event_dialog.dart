/// Create Event Dialog
///
/// Popup dialog for creating new SlotCompositeEvent with:
/// - Custom name input
/// - Stage selection (multiple stages supported)
/// - Quick stage category filter

import 'package:flutter/material.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Result from the create event dialog
class CreateEventResult {
  final String name;
  final List<String> triggerStages;

  const CreateEventResult({
    required this.name,
    required this.triggerStages,
  });
}

/// Dialog for creating a new event with name and stage selection
class CreateEventDialog extends StatefulWidget {
  final String? initialName;
  final List<String>? initialStages;

  const CreateEventDialog({
    super.key,
    this.initialName,
    this.initialStages,
  });

  /// Show the dialog and return the result
  static Future<CreateEventResult?> show(
    BuildContext context, {
    String? initialName,
    List<String>? initialStages,
  }) {
    return showDialog<CreateEventResult>(
      context: context,
      builder: (ctx) => CreateEventDialog(
        initialName: initialName,
        initialStages: initialStages,
      ),
    );
  }

  @override
  State<CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends State<CreateEventDialog> {
  late final TextEditingController _nameController;
  final Set<String> _selectedStages = {};
  StageCategory? _filterCategory;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    if (widget.initialStages != null) {
      _selectedStages.addAll(widget.initialStages!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<String> get _filteredStages {
    final service = StageConfigurationService.instance;
    var stages = service.allStageNames;

    // Filter by category
    if (_filterCategory != null) {
      final categoryStages = service.getByCategory(_filterCategory!);
      final categoryNames = categoryStages.map((s) => s.name).toSet();
      stages = stages.where((s) => categoryNames.contains(s)).toList();
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      stages = stages
          .where((s) => s.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return stages;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.add_circle, color: FluxForgeTheme.accentBlue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Create New Event',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Event Name Input
            const Text(
              'Event Name',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0D0D10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: 'Enter event name...',
                hintStyle: const TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 16),

            // Stage Selection Header
            Row(
              children: [
                const Text(
                  'Trigger Stages',
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                if (_selectedStages.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_selectedStages.length} selected',
                      style: TextStyle(
                        color: FluxForgeTheme.accentBlue,
                        fontSize: 10,
                      ),
                    ),
                  ),
                const Spacer(),
                // Category filter dropdown
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<StageCategory?>(
                      value: _filterCategory,
                      isDense: true,
                      dropdownColor: const Color(0xFF1A1A22),
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                      hint: const Text('All', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Categories'),
                        ),
                        ...StageCategory.values.map((cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(_categoryLabel(cat)),
                            )),
                      ],
                      onChanged: (cat) => setState(() => _filterCategory = cat),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Search box
            TextField(
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0D0D10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                hintText: 'Search stages...',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white24),
                prefixIconConstraints: const BoxConstraints(minWidth: 28),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 8),

            // Selected stages chips
            if (_selectedStages.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _selectedStages.map((stage) {
                  return Chip(
                    label: Text(stage, style: const TextStyle(fontSize: 10, color: Colors.white)),
                    deleteIcon: const Icon(Icons.close, size: 12),
                    deleteIconColor: Colors.white54,
                    onDeleted: () => setState(() => _selectedStages.remove(stage)),
                    backgroundColor: FluxForgeTheme.accentBlue.withOpacity(0.3),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],

            // Stage list
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredStages.length,
                  itemBuilder: (ctx, i) {
                    final stage = _filteredStages[i];
                    final isSelected = _selectedStages.contains(stage);
                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedStages.remove(stage);
                          } else {
                            _selectedStages.add(stage);
                          }
                        });
                      },
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? FluxForgeTheme.accentBlue.withOpacity(0.1) : null,
                          border: Border(
                            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                              size: 14,
                              color: isSelected ? FluxForgeTheme.accentBlue : Colors.white38,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                stage,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? Colors.white : Colors.white70,
                                ),
                              ),
                            ),
                            // Category badge
                            _buildCategoryBadge(stage),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _nameController.text.trim().isNotEmpty
                      ? () {
                          Navigator.of(context).pop(CreateEventResult(
                            name: _nameController.text.trim(),
                            triggerStages: _selectedStages.toList(),
                          ));
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FluxForgeTheme.accentBlue,
                    disabledBackgroundColor: Colors.white12,
                  ),
                  child: const Text('Create Event'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(String stageName) {
    final service = StageConfigurationService.instance;
    final def = service.getStage(stageName);
    if (def == null) return const SizedBox.shrink();

    final color = _categoryColor(def.category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        _categoryLabel(def.category),
        style: TextStyle(fontSize: 8, color: color),
      ),
    );
  }

  String _categoryLabel(StageCategory cat) {
    switch (cat) {
      case StageCategory.spin:
        return 'SPIN';
      case StageCategory.win:
        return 'WIN';
      case StageCategory.feature:
        return 'FEATURE';
      case StageCategory.cascade:
        return 'CASCADE';
      case StageCategory.jackpot:
        return 'JACKPOT';
      case StageCategory.hold:
        return 'HOLD';
      case StageCategory.gamble:
        return 'GAMBLE';
      case StageCategory.ui:
        return 'UI';
      case StageCategory.music:
        return 'MUSIC';
      case StageCategory.symbol:
        return 'SYMBOL';
      case StageCategory.custom:
        return 'CUSTOM';
    }
  }

  Color _categoryColor(StageCategory cat) {
    switch (cat) {
      case StageCategory.spin:
        return const Color(0xFF40FF90);
      case StageCategory.win:
        return const Color(0xFFFFD700);
      case StageCategory.feature:
        return const Color(0xFF40C8FF);
      case StageCategory.cascade:
        return const Color(0xFFFF69B4);
      case StageCategory.jackpot:
        return const Color(0xFFFF4040);
      case StageCategory.hold:
        return const Color(0xFFFF9040);
      case StageCategory.gamble:
        return const Color(0xFF9370DB);
      case StageCategory.ui:
        return const Color(0xFF778899);
      case StageCategory.music:
        return const Color(0xFF20B2AA);
      case StageCategory.symbol:
        return const Color(0xFFE040FB);
      case StageCategory.custom:
        return Colors.white54;
    }
  }
}
