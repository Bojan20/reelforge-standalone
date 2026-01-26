/// DAW Track Presets Panel (P0.1 Extracted)
///
/// Displays track preset library with:
/// - Factory presets (10 built-in)
/// - Custom presets (user-created)
/// - Category filtering
/// - Search/filter
/// - Save/Load/Delete operations
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 450-819 (~370 LOC)
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../services/track_preset_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TRACK PRESETS PANEL
// ═══════════════════════════════════════════════════════════════════════════

class TrackPresetsPanel extends StatefulWidget {
  /// Callback when preset is applied
  final void Function(String action, Map<String, dynamic> data)? onPresetAction;

  /// Callback for search text changes
  final String? searchQuery;

  const TrackPresetsPanel({
    super.key,
    this.onPresetAction,
    this.searchQuery,
  });

  @override
  State<TrackPresetsPanel> createState() => _TrackPresetsPanelState();
}

class _TrackPresetsPanelState extends State<TrackPresetsPanel> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TrackPresetService.instance,
      builder: (context, _) {
        final service = TrackPresetService.instance;
        final presets = _getFilteredPresets(service.presets);

        // Initialize factory presets if empty
        if (service.presets.isEmpty && !service.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            service.initializeFactoryPresets();
          });
        }

        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Save button
              Row(
                children: [
                  _buildBrowserHeader('TRACK PRESETS', Icons.tune),
                  const Spacer(),
                  _buildPresetActionButton(
                    Icons.add,
                    'Save Current',
                    _onSaveCurrentAsPreset,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Category filter
              _buildCategoryFilter(),
              const SizedBox(height: 8),
              // Presets grid
              Expanded(
                child: service.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: LowerZoneColors.dawAccent,
                        ),
                      )
                    : presets.isEmpty
                        ? _buildEmptyState()
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2.2,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                            itemCount: presets.length,
                            itemBuilder: (context, index) {
                              return _buildPresetCard(presets[index]);
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Filtering ─────────────────────────────────────────────────────────────

  List<TrackPreset> _getFilteredPresets(List<TrackPreset> allPresets) {
    var filtered = allPresets;

    // Filter by category
    if (_selectedCategory != null) {
      filtered = filtered.where((p) => p.category == _selectedCategory).toList();
    }

    // Filter by search query
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      final query = widget.searchQuery!.toLowerCase();
      filtered = filtered.where((p) {
        return p.name.toLowerCase().contains(query) ||
            (p.description?.toLowerCase().contains(query) ?? false) ||
            (p.category?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return filtered;
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildBrowserHeader(String title, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 24,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCategoryChip('All', null),
          ...TrackPresetService.categories.map((c) => _buildCategoryChip(c, c)),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String? category) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedCategory = category);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? LowerZoneColors.dawAccent
                : LowerZoneColors.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? LowerZoneColors.dawAccent
                  : LowerZoneColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Colors.white : LowerZoneColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 32,
            color: LowerZoneColors.textTertiary,
          ),
          const SizedBox(height: 8),
          const Text(
            'No presets yet',
            style: TextStyle(
              fontSize: 11,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Save your track settings as a preset',
            style: TextStyle(
              fontSize: 9,
              color: LowerZoneColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetActionButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: LowerZoneColors.dawAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: LowerZoneColors.dawAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 4),
              Text(
                tooltip,
                style: const TextStyle(
                  fontSize: 9,
                  color: LowerZoneColors.dawAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetCard(TrackPreset preset) {
    return GestureDetector(
      onTap: () => _onPresetSelected(preset),
      onSecondaryTap: () => _showContextMenu(preset),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    preset.name,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: LowerZoneColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (preset.category != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _categoryColor(preset.category!).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      preset.category!.substring(0, math.min(3, preset.category!.length)),
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w600,
                        color: _categoryColor(preset.category!),
                      ),
                    ),
                  ),
              ],
            ),
            if (preset.description != null) ...[
              const SizedBox(height: 2),
              Text(
                preset.description!,
                style: const TextStyle(
                  fontSize: 8,
                  color: LowerZoneColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 2),
            // Settings preview
            Row(
              children: [
                _buildMiniIndicator(Icons.volume_up, '${(preset.volume * 100).toInt()}%'),
                const SizedBox(width: 4),
                _buildMiniIndicator(Icons.swap_horiz, '${(preset.pan * 100).toInt().abs()}${preset.pan >= 0 ? 'R' : 'L'}'),
                if (preset.compressor.enabled) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.compress, size: 8, color: LowerZoneColors.dawAccent),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniIndicator(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 8, color: LowerZoneColors.textTertiary),
        const SizedBox(width: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 7,
            color: LowerZoneColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'Vocals' => const Color(0xFF4A9EFF),
      'Drums' => const Color(0xFFFF6B6B),
      'Bass' => const Color(0xFF845EF7),
      'Guitar' => const Color(0xFFFF922B),
      'Keys' => const Color(0xFF51CF66),
      'Synth' => const Color(0xFF22B8CF),
      'FX' => const Color(0xFFF06595),
      'Ambience' => const Color(0xFF94D82D),
      'Master' => const Color(0xFFFFD43B),
      _ => const Color(0xFF748FFC),
    };
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  void _onSaveCurrentAsPreset() {
    // Show save dialog
    showDialog(
      context: context,
      builder: (ctx) => TrackPresetSaveDialog(
        onSave: (name, category) async {
          final preset = TrackPreset(
            name: name,
            category: category,
            createdAt: DateTime.now(),
            volume: 1.0, // TODO: Get from selected track
            pan: 0.0,
            outputBus: 'master',
          );
          final success = await TrackPresetService.instance.savePreset(preset);
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved preset: $name'),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  void _onPresetSelected(TrackPreset preset) {
    // Notify parent to apply preset
    widget.onPresetAction?.call('applyPreset', {'preset': preset.name});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied preset: ${preset.name}'),
          backgroundColor: LowerZoneColors.dawAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showContextMenu(TrackPreset preset) {
    showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 100, 100),
      items: [
        const PopupMenuItem(value: 'apply', child: Text('Apply to Track')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(value: 'export', child: Text('Export...')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.red.shade300)),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'apply':
          _onPresetSelected(preset);
          break;
        case 'duplicate':
          final newPreset = preset.copyWith(
            name: '${preset.name} Copy',
            createdAt: DateTime.now(),
          );
          await TrackPresetService.instance.savePreset(newPreset);
          break;
        case 'delete':
          await TrackPresetService.instance.deletePreset(preset.name);
          break;
      }
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK PRESET SAVE DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class TrackPresetSaveDialog extends StatefulWidget {
  final void Function(String name, String? category) onSave;

  const TrackPresetSaveDialog({super.key, required this.onSave});

  @override
  State<TrackPresetSaveDialog> createState() => _TrackPresetSaveDialogState();
}

class _TrackPresetSaveDialogState extends State<TrackPresetSaveDialog> {
  final _nameController = TextEditingController();
  String? _selectedCategory;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LowerZoneColors.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: LowerZoneColors.border),
      ),
      title: Row(
        children: [
          Icon(Icons.save_outlined, size: 20, color: LowerZoneColors.dawAccent),
          const SizedBox(width: 8),
          const Text(
            'Save Track Preset',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textPrimary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name field
            const Text(
              'Preset Name',
              style: TextStyle(
                fontSize: 11,
                color: LowerZoneColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(
                fontSize: 12,
                color: LowerZoneColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'My Track Preset',
                hintStyle: const TextStyle(color: LowerZoneColors.textTertiary),
                filled: true,
                fillColor: LowerZoneColors.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: LowerZoneColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: LowerZoneColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: LowerZoneColors.dawAccent),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            const SizedBox(height: 16),
            // Category selector
            const Text(
              'Category',
              style: TextStyle(
                fontSize: 11,
                color: LowerZoneColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: TrackPresetService.categories.map((category) {
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategory = isSelected ? null : category;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? LowerZoneColors.dawAccent
                          : LowerZoneColors.bgSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? LowerZoneColors.dawAccent
                            : LowerZoneColors.border,
                      ),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? Colors.white : LowerZoneColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: LowerZoneColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            widget.onSave(name, _selectedCategory);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: LowerZoneColors.dawAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
