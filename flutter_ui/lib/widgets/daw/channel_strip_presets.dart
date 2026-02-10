/// P2.11: Channel Strip Presets — Save/Load channel strip configurations
///
/// Allows saving and loading complete channel strip settings including
/// volume, pan, EQ, dynamics, sends, and inserts.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Channel strip preset categories
enum ChannelStripCategory {
  vocals,
  drums,
  bass,
  guitars,
  keys,
  strings,
  brass,
  synths,
  fx,
  custom,
}

extension ChannelStripCategoryExtension on ChannelStripCategory {
  String get displayName {
    switch (this) {
      case ChannelStripCategory.vocals:
        return 'Vocals';
      case ChannelStripCategory.drums:
        return 'Drums';
      case ChannelStripCategory.bass:
        return 'Bass';
      case ChannelStripCategory.guitars:
        return 'Guitars';
      case ChannelStripCategory.keys:
        return 'Keys';
      case ChannelStripCategory.strings:
        return 'Strings';
      case ChannelStripCategory.brass:
        return 'Brass';
      case ChannelStripCategory.synths:
        return 'Synths';
      case ChannelStripCategory.fx:
        return 'FX';
      case ChannelStripCategory.custom:
        return 'Custom';
    }
  }

  IconData get icon {
    switch (this) {
      case ChannelStripCategory.vocals:
        return Icons.mic;
      case ChannelStripCategory.drums:
        return Icons.music_note;
      case ChannelStripCategory.bass:
        return Icons.graphic_eq;
      case ChannelStripCategory.guitars:
        return Icons.music_video;
      case ChannelStripCategory.keys:
        return Icons.piano;
      case ChannelStripCategory.strings:
        return Icons.library_music;
      case ChannelStripCategory.brass:
        return Icons.campaign;
      case ChannelStripCategory.synths:
        return Icons.waves;
      case ChannelStripCategory.fx:
        return Icons.auto_fix_high;
      case ChannelStripCategory.custom:
        return Icons.folder;
    }
  }

  Color get color {
    switch (this) {
      case ChannelStripCategory.vocals:
        return const Color(0xFFFF6B6B);
      case ChannelStripCategory.drums:
        return const Color(0xFFFFD93D);
      case ChannelStripCategory.bass:
        return const Color(0xFF6BCB77);
      case ChannelStripCategory.guitars:
        return const Color(0xFF4D96FF);
      case ChannelStripCategory.keys:
        return const Color(0xFFAD8CFF);
      case ChannelStripCategory.strings:
        return const Color(0xFFFF8585);
      case ChannelStripCategory.brass:
        return const Color(0xFFFFB347);
      case ChannelStripCategory.synths:
        return const Color(0xFF40C8FF);
      case ChannelStripCategory.fx:
        return const Color(0xFF9370DB);
      case ChannelStripCategory.custom:
        return const Color(0xFF808080);
    }
  }
}

/// EQ band settings within a preset
class PresetEQBand {
  final String type;
  final double frequency;
  final double gain;
  final double q;
  final bool enabled;

  const PresetEQBand({
    required this.type,
    required this.frequency,
    required this.gain,
    required this.q,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'frequency': frequency,
    'gain': gain,
    'q': q,
    'enabled': enabled,
  };

  factory PresetEQBand.fromJson(Map<String, dynamic> json) => PresetEQBand(
    type: json['type'] as String,
    frequency: (json['frequency'] as num).toDouble(),
    gain: (json['gain'] as num).toDouble(),
    q: (json['q'] as num).toDouble(),
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// Dynamics settings within a preset
class PresetDynamics {
  final double threshold;
  final double ratio;
  final double attack;
  final double release;
  final double makeupGain;
  final bool enabled;

  const PresetDynamics({
    required this.threshold,
    required this.ratio,
    required this.attack,
    required this.release,
    this.makeupGain = 0.0,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'threshold': threshold,
    'ratio': ratio,
    'attack': attack,
    'release': release,
    'makeupGain': makeupGain,
    'enabled': enabled,
  };

  factory PresetDynamics.fromJson(Map<String, dynamic> json) => PresetDynamics(
    threshold: (json['threshold'] as num).toDouble(),
    ratio: (json['ratio'] as num).toDouble(),
    attack: (json['attack'] as num).toDouble(),
    release: (json['release'] as num).toDouble(),
    makeupGain: (json['makeupGain'] as num?)?.toDouble() ?? 0.0,
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// Send settings within a preset
class PresetSend {
  final String busName;
  final double level;
  final bool preFader;
  final bool enabled;

  const PresetSend({
    required this.busName,
    required this.level,
    this.preFader = false,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'busName': busName,
    'level': level,
    'preFader': preFader,
    'enabled': enabled,
  };

  factory PresetSend.fromJson(Map<String, dynamic> json) => PresetSend(
    busName: json['busName'] as String,
    level: (json['level'] as num).toDouble(),
    preFader: json['preFader'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// Complete channel strip preset
class ChannelStripPreset {
  final String id;
  final String name;
  final ChannelStripCategory category;
  final String? description;
  final DateTime createdAt;
  final bool isFactory;

  // Basic settings
  final double volume;
  final double pan;
  final double inputGain;
  final bool phaseInverted;

  // EQ
  final List<PresetEQBand> eqBands;
  final bool eqEnabled;

  // Dynamics
  final PresetDynamics? compressor;
  final PresetDynamics? gate;

  // Sends
  final List<PresetSend> sends;

  // Insert chain (processor type names)
  final List<String> inserts;

  const ChannelStripPreset({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    required this.createdAt,
    this.isFactory = false,
    this.volume = 0.0,
    this.pan = 0.0,
    this.inputGain = 0.0,
    this.phaseInverted = false,
    this.eqBands = const [],
    this.eqEnabled = true,
    this.compressor,
    this.gate,
    this.sends = const [],
    this.inserts = const [],
  });

  ChannelStripPreset copyWith({
    String? id,
    String? name,
    ChannelStripCategory? category,
    String? description,
    DateTime? createdAt,
    bool? isFactory,
    double? volume,
    double? pan,
    double? inputGain,
    bool? phaseInverted,
    List<PresetEQBand>? eqBands,
    bool? eqEnabled,
    PresetDynamics? compressor,
    PresetDynamics? gate,
    List<PresetSend>? sends,
    List<String>? inserts,
  }) {
    return ChannelStripPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      isFactory: isFactory ?? this.isFactory,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      inputGain: inputGain ?? this.inputGain,
      phaseInverted: phaseInverted ?? this.phaseInverted,
      eqBands: eqBands ?? this.eqBands,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      compressor: compressor ?? this.compressor,
      gate: gate ?? this.gate,
      sends: sends ?? this.sends,
      inserts: inserts ?? this.inserts,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.index,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'isFactory': isFactory,
    'volume': volume,
    'pan': pan,
    'inputGain': inputGain,
    'phaseInverted': phaseInverted,
    'eqBands': eqBands.map((b) => b.toJson()).toList(),
    'eqEnabled': eqEnabled,
    'compressor': compressor?.toJson(),
    'gate': gate?.toJson(),
    'sends': sends.map((s) => s.toJson()).toList(),
    'inserts': inserts,
  };

  factory ChannelStripPreset.fromJson(Map<String, dynamic> json) {
    return ChannelStripPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      category: ChannelStripCategory.values[json['category'] as int],
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isFactory: json['isFactory'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      inputGain: (json['inputGain'] as num?)?.toDouble() ?? 0.0,
      phaseInverted: json['phaseInverted'] as bool? ?? false,
      eqBands: (json['eqBands'] as List?)
          ?.map((e) => PresetEQBand.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      eqEnabled: json['eqEnabled'] as bool? ?? true,
      compressor: json['compressor'] != null
          ? PresetDynamics.fromJson(json['compressor'] as Map<String, dynamic>)
          : null,
      gate: json['gate'] != null
          ? PresetDynamics.fromJson(json['gate'] as Map<String, dynamic>)
          : null,
      sends: (json['sends'] as List?)
          ?.map((e) => PresetSend.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      inserts: (json['inserts'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// Service for managing channel strip presets
class ChannelStripPresetService {
  static final ChannelStripPresetService instance = ChannelStripPresetService._();
  ChannelStripPresetService._();

  static const String _storageKey = 'channel_strip_presets';
  final List<ChannelStripPreset> _presets = [];
  bool _initialized = false;

  List<ChannelStripPreset> get presets => List.unmodifiable(_presets);

  Future<void> init() async {
    if (_initialized) return;

    // Add factory presets
    _presets.addAll(_factoryPresets);

    // Load user presets
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        for (final item in list) {
          _presets.add(ChannelStripPreset.fromJson(item as Map<String, dynamic>));
        }
      } catch (e) { /* ignored */ }
    }

    _initialized = true;
  }

  Future<void> savePreset(ChannelStripPreset preset) async {
    // Remove existing with same ID
    _presets.removeWhere((p) => p.id == preset.id && !p.isFactory);
    _presets.add(preset);
    await _persist();
  }

  Future<void> deletePreset(String id) async {
    _presets.removeWhere((p) => p.id == id && !p.isFactory);
    await _persist();
  }

  List<ChannelStripPreset> getByCategory(ChannelStripCategory category) {
    return _presets.where((p) => p.category == category).toList();
  }

  ChannelStripPreset? getById(String id) {
    try {
      return _presets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    final userPresets = _presets.where((p) => !p.isFactory).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(userPresets.map((p) => p.toJson()).toList()),
    );
  }

  /// Factory presets
  static final List<ChannelStripPreset> _factoryPresets = [
    // Vocals
    ChannelStripPreset(
      id: 'factory_vocal_warm',
      name: 'Warm Vocal',
      category: ChannelStripCategory.vocals,
      description: 'Warm, present vocal sound',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'highpass', frequency: 80, gain: 0, q: 0.7),
        const PresetEQBand(type: 'bell', frequency: 200, gain: -2, q: 1.5),
        const PresetEQBand(type: 'bell', frequency: 3000, gain: 3, q: 1.0),
        const PresetEQBand(type: 'highshelf', frequency: 10000, gain: 2, q: 0.7),
      ],
      compressor: const PresetDynamics(
        threshold: -18,
        ratio: 3.0,
        attack: 10,
        release: 100,
        makeupGain: 3,
      ),
    ),
    ChannelStripPreset(
      id: 'factory_vocal_bright',
      name: 'Bright Vocal',
      category: ChannelStripCategory.vocals,
      description: 'Crisp, airy vocal presence',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'highpass', frequency: 100, gain: 0, q: 0.7),
        const PresetEQBand(type: 'bell', frequency: 5000, gain: 4, q: 1.2),
        const PresetEQBand(type: 'highshelf', frequency: 12000, gain: 3, q: 0.7),
      ],
      compressor: const PresetDynamics(
        threshold: -15,
        ratio: 4.0,
        attack: 5,
        release: 80,
        makeupGain: 4,
      ),
    ),
    // Drums
    ChannelStripPreset(
      id: 'factory_kick_punchy',
      name: 'Punchy Kick',
      category: ChannelStripCategory.drums,
      description: 'Tight, punchy kick drum',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'bell', frequency: 60, gain: 4, q: 1.5),
        const PresetEQBand(type: 'bell', frequency: 400, gain: -3, q: 2.0),
        const PresetEQBand(type: 'bell', frequency: 3500, gain: 3, q: 1.0),
      ],
      compressor: const PresetDynamics(
        threshold: -12,
        ratio: 4.0,
        attack: 20,
        release: 150,
        makeupGain: 2,
      ),
      gate: const PresetDynamics(
        threshold: -35,
        ratio: 10.0,
        attack: 0.5,
        release: 50,
      ),
    ),
    ChannelStripPreset(
      id: 'factory_snare_crack',
      name: 'Snare Crack',
      category: ChannelStripCategory.drums,
      description: 'Crisp snare with body',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'highpass', frequency: 100, gain: 0, q: 0.7),
        const PresetEQBand(type: 'bell', frequency: 200, gain: 3, q: 1.0),
        const PresetEQBand(type: 'bell', frequency: 5000, gain: 4, q: 1.5),
      ],
      compressor: const PresetDynamics(
        threshold: -15,
        ratio: 5.0,
        attack: 5,
        release: 100,
        makeupGain: 3,
      ),
    ),
    // Bass
    ChannelStripPreset(
      id: 'factory_bass_tight',
      name: 'Tight Bass',
      category: ChannelStripCategory.bass,
      description: 'Controlled low end',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'highpass', frequency: 30, gain: 0, q: 0.7),
        const PresetEQBand(type: 'bell', frequency: 80, gain: 3, q: 1.5),
        const PresetEQBand(type: 'bell', frequency: 800, gain: 2, q: 1.0),
      ],
      compressor: const PresetDynamics(
        threshold: -12,
        ratio: 4.0,
        attack: 15,
        release: 120,
        makeupGain: 2,
      ),
    ),
    // Guitars
    ChannelStripPreset(
      id: 'factory_guitar_clean',
      name: 'Clean Guitar',
      category: ChannelStripCategory.guitars,
      description: 'Bright, clean electric',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'highpass', frequency: 80, gain: 0, q: 0.7),
        const PresetEQBand(type: 'bell', frequency: 3000, gain: 2, q: 1.0),
        const PresetEQBand(type: 'highshelf', frequency: 8000, gain: 2, q: 0.7),
      ],
    ),
    ChannelStripPreset(
      id: 'factory_guitar_acoustic',
      name: 'Acoustic Guitar',
      category: ChannelStripCategory.guitars,
      description: 'Natural acoustic sound',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'highpass', frequency: 80, gain: 0, q: 0.7),
        const PresetEQBand(type: 'bell', frequency: 200, gain: -2, q: 1.5),
        const PresetEQBand(type: 'bell', frequency: 5000, gain: 3, q: 1.0),
      ],
      compressor: const PresetDynamics(
        threshold: -20,
        ratio: 2.5,
        attack: 15,
        release: 150,
        makeupGain: 2,
      ),
    ),
    // Keys
    ChannelStripPreset(
      id: 'factory_piano_natural',
      name: 'Natural Piano',
      category: ChannelStripCategory.keys,
      description: 'Balanced piano sound',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'highpass', frequency: 40, gain: 0, q: 0.7),
        const PresetEQBand(type: 'bell', frequency: 2500, gain: 2, q: 1.0),
      ],
      compressor: const PresetDynamics(
        threshold: -20,
        ratio: 2.0,
        attack: 25,
        release: 200,
        makeupGain: 1,
      ),
    ),
    // Synths
    ChannelStripPreset(
      id: 'factory_synth_pad',
      name: 'Synth Pad',
      category: ChannelStripCategory.synths,
      description: 'Smooth pad sound',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'lowshelf', frequency: 200, gain: -2, q: 0.7),
        const PresetEQBand(type: 'highshelf', frequency: 8000, gain: 2, q: 0.7),
      ],
    ),
    ChannelStripPreset(
      id: 'factory_synth_lead',
      name: 'Synth Lead',
      category: ChannelStripCategory.synths,
      description: 'Cutting lead synth',
      createdAt: DateTime(2024, 1, 1),
      isFactory: true,
      eqBands: [
        const PresetEQBand(type: 'bell', frequency: 3000, gain: 3, q: 1.5),
        const PresetEQBand(type: 'highshelf', frequency: 10000, gain: 2, q: 0.7),
      ],
      compressor: const PresetDynamics(
        threshold: -15,
        ratio: 3.0,
        attack: 10,
        release: 100,
        makeupGain: 2,
      ),
    ),
  ];
}

/// Channel strip presets panel widget
class ChannelStripPresetsPanel extends StatefulWidget {
  final String? currentTrackId;
  final void Function(ChannelStripPreset preset)? onPresetSelected;
  final void Function(ChannelStripPreset preset)? onSaveCurrentAsPreset;

  const ChannelStripPresetsPanel({
    super.key,
    this.currentTrackId,
    this.onPresetSelected,
    this.onSaveCurrentAsPreset,
  });

  @override
  State<ChannelStripPresetsPanel> createState() => _ChannelStripPresetsPanelState();
}

class _ChannelStripPresetsPanelState extends State<ChannelStripPresetsPanel> {
  ChannelStripCategory? _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<ChannelStripPreset> get _filteredPresets {
    var presets = ChannelStripPresetService.instance.presets;

    if (_selectedCategory != null) {
      presets = presets.where((p) => p.category == _selectedCategory).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      presets = presets.where((p) =>
        p.name.toLowerCase().contains(query) ||
        (p.description?.toLowerCase().contains(query) ?? false)
      ).toList();
    }

    return presets;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildCategoryFilter(),
          _buildSearchBar(),
          Expanded(child: _buildPresetList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A20),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A35))),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 14, color: Color(0xFF4A9EFF)),
          const SizedBox(width: 6),
          const Text(
            'CHANNEL STRIP PRESETS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFB0B0B8),
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showSaveDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4A9EFF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save, size: 12, color: Color(0xFF4A9EFF)),
                  SizedBox(width: 4),
                  Text(
                    'Save Current',
                    style: TextStyle(fontSize: 10, color: Color(0xFF4A9EFF)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCategoryChip(null, 'All'),
          ...ChannelStripCategory.values.map(
            (c) => _buildCategoryChip(c, c.displayName),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(ChannelStripCategory? category, String label) {
    final isSelected = _selectedCategory == category;
    final color = category?.color ?? const Color(0xFF808080);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : const Color(0xFF3A3A45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (category != null) ...[
                Icon(category.icon, size: 12, color: isSelected ? color : const Color(0xFF808080)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? color : const Color(0xFF808080),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 32,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 14, color: Color(0xFF606070)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search presets...',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFF606070)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: const Icon(Icons.close, size: 14, color: Color(0xFF606070)),
            ),
        ],
      ),
    );
  }

  Widget _buildPresetList() {
    final presets = _filteredPresets;

    if (presets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tune_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 8),
            Text(
              'No presets found',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: presets.length,
      itemBuilder: (context, index) => _buildPresetItem(presets[index]),
    );
  }

  Widget _buildPresetItem(ChannelStripPreset preset) {
    return GestureDetector(
      onTap: () => widget.onPresetSelected?.call(preset),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF2A2A35)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: preset.category.color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                preset.category.icon,
                size: 16,
                color: preset.category.color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        preset.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      if (preset.isFactory) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A9EFF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text(
                            'FACTORY',
                            style: TextStyle(fontSize: 8, color: Color(0xFF4A9EFF)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (preset.description != null)
                    Text(
                      preset.description!,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Quick badges
            if (preset.compressor != null)
              _buildBadge('C', const Color(0xFFFF9040)),
            if (preset.gate != null)
              _buildBadge('G', const Color(0xFF40FF90)),
            if (preset.eqBands.isNotEmpty)
              _buildBadge('EQ', const Color(0xFF4A9EFF)),
            if (!preset.isFactory)
              GestureDetector(
                onTap: () => _deletePreset(preset),
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.delete_outline, size: 16, color: Color(0xFF606070)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  void _showSaveDialog() {
    showDialog(
      context: context,
      builder: (context) => _SavePresetDialog(
        onSave: (name, category, description) {
          final preset = ChannelStripPreset(
            id: 'user_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            category: category,
            description: description,
            createdAt: DateTime.now(),
          );
          widget.onSaveCurrentAsPreset?.call(preset);
          Navigator.of(context).pop();
          setState(() {});
        },
      ),
    );
  }

  void _deletePreset(ChannelStripPreset preset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        title: const Text('Delete Preset', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${preset.name}"?',
          style: const TextStyle(color: Color(0xFFB0B0B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF4060))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ChannelStripPresetService.instance.deletePreset(preset.id);
      setState(() {});
    }
  }
}

class _SavePresetDialog extends StatefulWidget {
  final void Function(String name, ChannelStripCategory category, String? description) onSave;

  const _SavePresetDialog({required this.onSave});

  @override
  State<_SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends State<_SavePresetDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  ChannelStripCategory _category = ChannelStripCategory.custom;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A20),
      title: const Text('Save Preset', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Name',
              labelStyle: TextStyle(color: Color(0xFF808080)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButton<ChannelStripCategory>(
            value: _category,
            isExpanded: true,
            dropdownColor: const Color(0xFF1A1A20),
            items: ChannelStripCategory.values.map((c) => DropdownMenuItem(
              value: c,
              child: Row(
                children: [
                  Icon(c.icon, size: 16, color: c.color),
                  const SizedBox(width: 8),
                  Text(c.displayName, style: const TextStyle(color: Colors.white)),
                ],
              ),
            )).toList(),
            onChanged: (value) => setState(() => _category = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              labelStyle: TextStyle(color: Color(0xFF808080)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_nameController.text.isNotEmpty) {
              widget.onSave(
                _nameController.text,
                _category,
                _descController.text.isEmpty ? null : _descController.text,
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
