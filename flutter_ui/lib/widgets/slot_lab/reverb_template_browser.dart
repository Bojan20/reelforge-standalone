/// Reverb Template Browser (P12.1.11)
///
/// UI for browsing, previewing, and applying reverb space presets.
/// 10 built-in reverb space presets with drag-to-timeline support.
library;

import 'package:flutter/material.dart';

// =============================================================================
// REVERB SPACE PRESET MODEL
// =============================================================================

/// Reverb space type classification
enum ReverbSpaceType {
  room,
  hall,
  plate,
  chamber,
  ambient,
  special,
}

/// A reverb space preset definition
class ReverbSpacePreset {
  final String id;
  final String name;
  final String description;
  final ReverbSpaceType type;
  final double decay;      // 0.1 - 10.0 seconds
  final double preDelay;   // 0 - 200 ms
  final double damping;    // 0.0 - 1.0
  final double size;       // 0.0 - 1.0
  final double diffusion;  // 0.0 - 1.0
  final double earlyLevel; // -60 to 0 dB
  final double lateLevel;  // -60 to 0 dB
  final double highCut;    // 1000 - 20000 Hz
  final double lowCut;     // 20 - 500 Hz
  final IconData icon;
  final Color color;

  const ReverbSpacePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.decay,
    required this.preDelay,
    required this.damping,
    required this.size,
    required this.diffusion,
    required this.earlyLevel,
    required this.lateLevel,
    required this.highCut,
    required this.lowCut,
    required this.icon,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'decay': decay,
    'preDelay': preDelay,
    'damping': damping,
    'size': size,
    'diffusion': diffusion,
    'earlyLevel': earlyLevel,
    'lateLevel': lateLevel,
    'highCut': highCut,
    'lowCut': lowCut,
  };
}

// =============================================================================
// BUILT-IN REVERB PRESETS (10 presets)
// =============================================================================

class ReverbPresets {
  static const List<ReverbSpacePreset> builtIn = [
    // Small spaces
    ReverbSpacePreset(
      id: 'small_room',
      name: 'Small Room',
      description: 'Tight, intimate room reverb for close sounds',
      type: ReverbSpaceType.room,
      decay: 0.4,
      preDelay: 5,
      damping: 0.7,
      size: 0.2,
      diffusion: 0.6,
      earlyLevel: -6,
      lateLevel: -12,
      highCut: 8000,
      lowCut: 80,
      icon: Icons.meeting_room,
      color: Color(0xFF4A9EFF),
    ),
    ReverbSpacePreset(
      id: 'medium_room',
      name: 'Medium Room',
      description: 'Balanced room reverb for general use',
      type: ReverbSpaceType.room,
      decay: 0.8,
      preDelay: 12,
      damping: 0.5,
      size: 0.4,
      diffusion: 0.7,
      earlyLevel: -8,
      lateLevel: -14,
      highCut: 10000,
      lowCut: 60,
      icon: Icons.home,
      color: Color(0xFF40C8FF),
    ),
    // Halls
    ReverbSpacePreset(
      id: 'concert_hall',
      name: 'Concert Hall',
      description: 'Large concert hall with rich reflections',
      type: ReverbSpaceType.hall,
      decay: 2.5,
      preDelay: 35,
      damping: 0.4,
      size: 0.85,
      diffusion: 0.9,
      earlyLevel: -10,
      lateLevel: -8,
      highCut: 12000,
      lowCut: 40,
      icon: Icons.stadium,
      color: Color(0xFFFFD700),
    ),
    ReverbSpacePreset(
      id: 'large_hall',
      name: 'Large Hall',
      description: 'Expansive hall with long tail',
      type: ReverbSpaceType.hall,
      decay: 4.0,
      preDelay: 50,
      damping: 0.3,
      size: 1.0,
      diffusion: 0.95,
      earlyLevel: -12,
      lateLevel: -6,
      highCut: 14000,
      lowCut: 30,
      icon: Icons.church,
      color: Color(0xFFFF9040),
    ),
    // Plates
    ReverbSpacePreset(
      id: 'bright_plate',
      name: 'Bright Plate',
      description: 'Classic bright plate reverb',
      type: ReverbSpaceType.plate,
      decay: 1.8,
      preDelay: 0,
      damping: 0.2,
      size: 0.6,
      diffusion: 1.0,
      earlyLevel: -4,
      lateLevel: -6,
      highCut: 16000,
      lowCut: 100,
      icon: Icons.blur_on,
      color: Color(0xFF9370DB),
    ),
    ReverbSpacePreset(
      id: 'dark_plate',
      name: 'Dark Plate',
      description: 'Warm, dark plate reverb',
      type: ReverbSpaceType.plate,
      decay: 2.2,
      preDelay: 10,
      damping: 0.7,
      size: 0.7,
      diffusion: 0.9,
      earlyLevel: -6,
      lateLevel: -8,
      highCut: 6000,
      lowCut: 80,
      icon: Icons.blur_circular,
      color: Color(0xFF8B5CF6),
    ),
    // Chamber
    ReverbSpacePreset(
      id: 'echo_chamber',
      name: 'Echo Chamber',
      description: 'Vintage echo chamber sound',
      type: ReverbSpaceType.chamber,
      decay: 1.2,
      preDelay: 20,
      damping: 0.5,
      size: 0.5,
      diffusion: 0.8,
      earlyLevel: -5,
      lateLevel: -10,
      highCut: 9000,
      lowCut: 100,
      icon: Icons.surround_sound,
      color: Color(0xFF40FF90),
    ),
    // Ambient/Special
    ReverbSpacePreset(
      id: 'shimmer',
      name: 'Shimmer',
      description: 'Ethereal shimmer reverb with pitch shifting',
      type: ReverbSpaceType.special,
      decay: 6.0,
      preDelay: 80,
      damping: 0.2,
      size: 1.0,
      diffusion: 1.0,
      earlyLevel: -20,
      lateLevel: -4,
      highCut: 18000,
      lowCut: 200,
      icon: Icons.auto_awesome,
      color: Color(0xFFFF6B6B),
    ),
    ReverbSpacePreset(
      id: 'ambient_wash',
      name: 'Ambient Wash',
      description: 'Soft ambient wash for background texture',
      type: ReverbSpaceType.ambient,
      decay: 8.0,
      preDelay: 100,
      damping: 0.6,
      size: 1.0,
      diffusion: 1.0,
      earlyLevel: -30,
      lateLevel: -6,
      highCut: 8000,
      lowCut: 150,
      icon: Icons.waves,
      color: Color(0xFF00CED1),
    ),
    ReverbSpacePreset(
      id: 'cathedral',
      name: 'Cathedral',
      description: 'Massive cathedral space with epic decay',
      type: ReverbSpaceType.hall,
      decay: 10.0,
      preDelay: 120,
      damping: 0.25,
      size: 1.0,
      diffusion: 0.98,
      earlyLevel: -15,
      lateLevel: -4,
      highCut: 10000,
      lowCut: 50,
      icon: Icons.account_balance,
      color: Color(0xFFE91E63),
    ),
  ];
}

// =============================================================================
// REVERB TEMPLATE BROWSER WIDGET
// =============================================================================

class ReverbTemplateBrowser extends StatefulWidget {
  final void Function(ReverbSpacePreset preset)? onPresetSelected;
  final void Function(ReverbSpacePreset preset)? onPreviewPressed;

  const ReverbTemplateBrowser({
    super.key,
    this.onPresetSelected,
    this.onPreviewPressed,
  });

  @override
  State<ReverbTemplateBrowser> createState() => _ReverbTemplateBrowserState();
}

class _ReverbTemplateBrowserState extends State<ReverbTemplateBrowser> {
  ReverbSpaceType? _filterType;
  ReverbSpacePreset? _selectedPreset;
  String? _previewingId;

  List<ReverbSpacePreset> get _filteredPresets {
    if (_filterType == null) return ReverbPresets.builtIn;
    return ReverbPresets.builtIn.where((p) => p.type == _filterType).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1),
        Expanded(child: _buildPresetGrid()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1a1a20),
      child: Row(
        children: [
          const Icon(Icons.spatial_audio, size: 20, color: Color(0xFF9370DB)),
          const SizedBox(width: 8),
          const Text(
            'Reverb Spaces',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          _buildTypeFilter(),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<ReverbSpaceType?>(
        value: _filterType,
        hint: const Text('All', style: TextStyle(fontSize: 11)),
        underline: const SizedBox(),
        isDense: true,
        style: const TextStyle(fontSize: 11, color: Colors.white),
        dropdownColor: const Color(0xFF242430),
        items: [
          const DropdownMenuItem(value: null, child: Text('All Types')),
          ...ReverbSpaceType.values.map((type) => DropdownMenuItem(
            value: type,
            child: Text(_typeLabel(type)),
          )),
        ],
        onChanged: (value) => setState(() => _filterType = value),
      ),
    );
  }

  Widget _buildPresetGrid() {
    final presets = _filteredPresets;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: presets.length,
      itemBuilder: (context, index) => _buildPresetCard(presets[index]),
    );
  }

  Widget _buildPresetCard(ReverbSpacePreset preset) {
    final isSelected = _selectedPreset?.id == preset.id;
    final isPreviewing = _previewingId == preset.id;

    return Draggable<ReverbSpacePreset>(
      data: preset,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: preset.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(preset.icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(preset.name, style: const TextStyle(fontSize: 11, color: Colors.white)),
            ],
          ),
        ),
      ),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedPreset = preset);
          widget.onPresetSelected?.call(preset);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? preset.color.withValues(alpha: 0.15) : const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? preset.color : const Color(0xFF333340),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: preset.color.withValues(alpha: 0.2),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                ),
                child: Row(
                  children: [
                    Icon(preset.icon, size: 14, color: preset.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        preset.name,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Preview button
                    GestureDetector(
                      onTap: () {
                        setState(() => _previewingId = isPreviewing ? null : preset.id);
                        widget.onPreviewPressed?.call(preset);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isPreviewing ? preset.color : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          isPreviewing ? Icons.stop : Icons.play_arrow,
                          size: 14,
                          color: isPreviewing ? Colors.white : preset.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Parameters
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.description,
                        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _paramBadge('${preset.decay.toStringAsFixed(1)}s', 'Decay'),
                          _paramBadge('${preset.preDelay.toInt()}ms', 'Pre'),
                          _paramBadge('${(preset.size * 100).toInt()}%', 'Size'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paramBadge(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
        Text(label, style: TextStyle(fontSize: 8, color: Colors.grey[600])),
      ],
    );
  }

  String _typeLabel(ReverbSpaceType type) {
    return switch (type) {
      ReverbSpaceType.room => 'Room',
      ReverbSpaceType.hall => 'Hall',
      ReverbSpaceType.plate => 'Plate',
      ReverbSpaceType.chamber => 'Chamber',
      ReverbSpaceType.ambient => 'Ambient',
      ReverbSpaceType.special => 'Special',
    };
  }
}
