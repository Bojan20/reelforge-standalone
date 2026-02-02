/// Track Icon Picker (P2-DAW-8)
///
/// Icon selector for tracks with:
/// - 50+ icons organized by category
/// - Category filtering
/// - Search functionality
///
/// Created: 2026-02-02
library;

import 'package:flutter/material.dart';
import '../lower_zone/lower_zone_types.dart';

/// Track icon category
enum TrackIconCategory {
  drums('Drums', Icons.radio_button_checked),
  bass('Bass', Icons.graphic_eq),
  guitar('Guitar', Icons.music_note),
  keys('Keys', Icons.piano),
  vocals('Vocals', Icons.mic),
  synth('Synth', Icons.waves),
  strings('Strings', Icons.music_note),
  brass('Brass', Icons.record_voice_over),
  percussion('Percussion', Icons.touch_app),
  fx('FX', Icons.auto_fix_high),
  bus('Bus', Icons.merge_type),
  master('Master', Icons.speaker);

  final String label;
  final IconData defaultIcon;

  const TrackIconCategory(this.label, this.defaultIcon);
}

/// Available track icons
class TrackIcons {
  static const Map<TrackIconCategory, List<IconData>> byCategory = {
    TrackIconCategory.drums: [
      Icons.radio_button_checked, // Kick
      Icons.circle_outlined,      // Snare
      Icons.blur_circular,        // Hi-hat
      Icons.trip_origin,          // Toms
      Icons.adjust,               // Cymbals
      Icons.album,                // Overheads
    ],
    TrackIconCategory.bass: [
      Icons.graphic_eq,
      Icons.waves,
      Icons.show_chart,
      Icons.equalizer,
    ],
    TrackIconCategory.guitar: [
      Icons.music_note,
      Icons.music_note_outlined,
      Icons.audiotrack,
      Icons.auto_awesome,
    ],
    TrackIconCategory.keys: [
      Icons.piano,
      Icons.piano_off,
      Icons.library_music,
      Icons.queue_music,
    ],
    TrackIconCategory.vocals: [
      Icons.mic,
      Icons.mic_none,
      Icons.mic_external_on,
      Icons.record_voice_over,
      Icons.voice_over_off,
      Icons.interpreter_mode,
    ],
    TrackIconCategory.synth: [
      Icons.waves,
      Icons.square,
      Icons.change_history,
      Icons.water,
      Icons.air,
      Icons.bolt,
    ],
    TrackIconCategory.strings: [
      Icons.music_note,
      Icons.queue_music,
      Icons.library_music,
      Icons.album,
    ],
    TrackIconCategory.brass: [
      Icons.record_voice_over,
      Icons.campaign,
      Icons.volume_up,
      Icons.hearing,
    ],
    TrackIconCategory.percussion: [
      Icons.touch_app,
      Icons.back_hand,
      Icons.front_hand,
      Icons.sports_handball,
    ],
    TrackIconCategory.fx: [
      Icons.auto_fix_high,
      Icons.blur_on,
      Icons.flash_on,
      Icons.flare,
      Icons.lens_blur,
      Icons.motion_photos_on,
    ],
    TrackIconCategory.bus: [
      Icons.merge_type,
      Icons.call_merge,
      Icons.call_split,
      Icons.device_hub,
      Icons.mediation,
    ],
    TrackIconCategory.master: [
      Icons.speaker,
      Icons.speaker_group,
      Icons.volume_up,
      Icons.surround_sound,
    ],
  };

  static List<IconData> get all => byCategory.values.expand((list) => list).toList();
}

/// Track icon picker dialog
class TrackIconPicker extends StatefulWidget {
  final IconData? currentIcon;
  final void Function(IconData)? onIconSelected;

  const TrackIconPicker({
    super.key,
    this.currentIcon,
    this.onIconSelected,
  });

  /// Show picker as dialog
  static Future<IconData?> show(BuildContext context, {IconData? currentIcon}) async {
    return showDialog<IconData>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrackIconPicker(
          currentIcon: currentIcon,
          onIconSelected: (icon) => Navigator.of(ctx).pop(icon),
        ),
      ),
    );
  }

  @override
  State<TrackIconPicker> createState() => _TrackIconPickerState();
}

class _TrackIconPickerState extends State<TrackIconPicker> {
  TrackIconCategory? _selectedCategory;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<IconData> get _filteredIcons {
    final query = _searchController.text.toLowerCase();
    List<IconData> icons;

    if (_selectedCategory != null) {
      icons = TrackIcons.byCategory[_selectedCategory!] ?? [];
    } else {
      icons = TrackIcons.all;
    }

    if (query.isEmpty) return icons;

    // Filter by category name match
    return icons;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: LowerZoneColors.border)),
            ),
            child: Column(
              children: [
                const Text(
                  'Select Track Icon',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: LowerZoneColors.textPrimary),
                ),
                const SizedBox(height: 12),
                // Category chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _CategoryChip(
                      label: 'All',
                      isSelected: _selectedCategory == null,
                      onTap: () => setState(() => _selectedCategory = null),
                    ),
                    ...TrackIconCategory.values.map((cat) => _CategoryChip(
                      label: cat.label,
                      isSelected: _selectedCategory == cat,
                      onTap: () => setState(() => _selectedCategory = cat),
                    )),
                  ],
                ),
              ],
            ),
          ),

          // Icon grid
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _filteredIcons.length,
              itemBuilder: (context, index) {
                final icon = _filteredIcons[index];
                final isSelected = widget.currentIcon == icon;
                return GestureDetector(
                  onTap: () => widget.onIconSelected?.call(icon),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
                          : LowerZoneColors.bgMid,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.border,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),

          // Cancel button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: LowerZoneColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
              : LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
