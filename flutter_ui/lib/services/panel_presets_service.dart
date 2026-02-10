/// Panel Presets Service — P3.3 Save/Load Panel Layouts
///
/// Professional workflow presets for panel configurations:
/// - Save current panel layout as preset
/// - Load preset to restore layout
/// - Built-in presets (Mixing, Editing, Sound Design)
/// - Custom user presets with names
/// - Persistence via SharedPreferences
///
/// Usage:
/// ```dart
/// // Save current layout
/// PanelPresetsService.instance.savePreset('My Layout', currentState);
///
/// // Load preset
/// final state = PanelPresetsService.instance.loadPreset('My Layout');
/// if (state != null) applyLayout(state);
///
/// // List presets
/// final presets = PanelPresetsService.instance.allPresets;
/// ```

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL LAYOUT STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents a complete panel layout state
class PanelLayoutState {
  /// Unique identifier
  final String id;

  /// Display name
  final String name;

  /// Description (optional)
  final String? description;

  /// Whether this is a built-in preset
  final bool isBuiltIn;

  /// DAW lower zone state
  final LowerZoneState? dawLowerZone;

  /// Middleware lower zone state
  final LowerZoneState? middlewareLowerZone;

  /// SlotLab lower zone state
  final LowerZoneState? slotLabLowerZone;

  /// Inspector panel state
  final InspectorState? inspector;

  /// Browser panel state
  final BrowserState? browser;

  /// Mixer panel state
  final MixerState? mixer;

  /// Created timestamp
  final DateTime createdAt;

  /// Last modified timestamp
  final DateTime modifiedAt;

  const PanelLayoutState({
    required this.id,
    required this.name,
    this.description,
    this.isBuiltIn = false,
    this.dawLowerZone,
    this.middlewareLowerZone,
    this.slotLabLowerZone,
    this.inspector,
    this.browser,
    this.mixer,
    required this.createdAt,
    required this.modifiedAt,
  });

  PanelLayoutState copyWith({
    String? id,
    String? name,
    String? description,
    bool? isBuiltIn,
    LowerZoneState? dawLowerZone,
    LowerZoneState? middlewareLowerZone,
    LowerZoneState? slotLabLowerZone,
    InspectorState? inspector,
    BrowserState? browser,
    MixerState? mixer,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return PanelLayoutState(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      dawLowerZone: dawLowerZone ?? this.dawLowerZone,
      middlewareLowerZone: middlewareLowerZone ?? this.middlewareLowerZone,
      slotLabLowerZone: slotLabLowerZone ?? this.slotLabLowerZone,
      inspector: inspector ?? this.inspector,
      browser: browser ?? this.browser,
      mixer: mixer ?? this.mixer,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'isBuiltIn': isBuiltIn,
    'dawLowerZone': dawLowerZone?.toJson(),
    'middlewareLowerZone': middlewareLowerZone?.toJson(),
    'slotLabLowerZone': slotLabLowerZone?.toJson(),
    'inspector': inspector?.toJson(),
    'browser': browser?.toJson(),
    'mixer': mixer?.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
  };

  factory PanelLayoutState.fromJson(Map<String, dynamic> json) {
    return PanelLayoutState(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      dawLowerZone: json['dawLowerZone'] != null
          ? LowerZoneState.fromJson(json['dawLowerZone'])
          : null,
      middlewareLowerZone: json['middlewareLowerZone'] != null
          ? LowerZoneState.fromJson(json['middlewareLowerZone'])
          : null,
      slotLabLowerZone: json['slotLabLowerZone'] != null
          ? LowerZoneState.fromJson(json['slotLabLowerZone'])
          : null,
      inspector: json['inspector'] != null
          ? InspectorState.fromJson(json['inspector'])
          : null,
      browser: json['browser'] != null
          ? BrowserState.fromJson(json['browser'])
          : null,
      mixer: json['mixer'] != null
          ? MixerState.fromJson(json['mixer'])
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPONENT STATES
// ═══════════════════════════════════════════════════════════════════════════════

/// Lower zone panel state
class LowerZoneState {
  final bool isExpanded;
  final double height;
  final int superTabIndex;
  final int subTabIndex;

  const LowerZoneState({
    required this.isExpanded,
    required this.height,
    required this.superTabIndex,
    required this.subTabIndex,
  });

  Map<String, dynamic> toJson() => {
    'isExpanded': isExpanded,
    'height': height,
    'superTabIndex': superTabIndex,
    'subTabIndex': subTabIndex,
  };

  factory LowerZoneState.fromJson(Map<String, dynamic> json) {
    return LowerZoneState(
      isExpanded: json['isExpanded'] as bool,
      height: (json['height'] as num).toDouble(),
      superTabIndex: json['superTabIndex'] as int,
      subTabIndex: json['subTabIndex'] as int,
    );
  }
}

/// Inspector panel state
class InspectorState {
  final bool isVisible;
  final double width;
  final int selectedTab;

  const InspectorState({
    required this.isVisible,
    required this.width,
    required this.selectedTab,
  });

  Map<String, dynamic> toJson() => {
    'isVisible': isVisible,
    'width': width,
    'selectedTab': selectedTab,
  };

  factory InspectorState.fromJson(Map<String, dynamic> json) {
    return InspectorState(
      isVisible: json['isVisible'] as bool,
      width: (json['width'] as num).toDouble(),
      selectedTab: json['selectedTab'] as int,
    );
  }
}

/// Browser panel state
class BrowserState {
  final bool isVisible;
  final double width;
  final String selectedFolder;
  final List<String> expandedFolders;

  const BrowserState({
    required this.isVisible,
    required this.width,
    required this.selectedFolder,
    required this.expandedFolders,
  });

  Map<String, dynamic> toJson() => {
    'isVisible': isVisible,
    'width': width,
    'selectedFolder': selectedFolder,
    'expandedFolders': expandedFolders,
  };

  factory BrowserState.fromJson(Map<String, dynamic> json) {
    return BrowserState(
      isVisible: json['isVisible'] as bool,
      width: (json['width'] as num).toDouble(),
      selectedFolder: json['selectedFolder'] as String,
      expandedFolders: (json['expandedFolders'] as List).cast<String>(),
    );
  }
}

/// Mixer panel state
class MixerState {
  final bool isVisible;
  final double stripWidth;
  final bool showMeters;
  final bool showSends;
  final List<int> visibleTracks;

  const MixerState({
    required this.isVisible,
    required this.stripWidth,
    required this.showMeters,
    required this.showSends,
    required this.visibleTracks,
  });

  Map<String, dynamic> toJson() => {
    'isVisible': isVisible,
    'stripWidth': stripWidth,
    'showMeters': showMeters,
    'showSends': showSends,
    'visibleTracks': visibleTracks,
  };

  factory MixerState.fromJson(Map<String, dynamic> json) {
    return MixerState(
      isVisible: json['isVisible'] as bool,
      stripWidth: (json['stripWidth'] as num).toDouble(),
      showMeters: json['showMeters'] as bool,
      showSends: json['showSends'] as bool,
      visibleTracks: (json['visibleTracks'] as List).cast<int>(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL PRESETS SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class PanelPresetsService extends ChangeNotifier {
  static final PanelPresetsService instance = PanelPresetsService._();
  PanelPresetsService._();

  static const String _prefsKey = 'panel_presets';

  final List<PanelLayoutState> _presets = [];
  bool _isLoaded = false;

  /// All presets (built-in + user)
  List<PanelLayoutState> get allPresets => List.unmodifiable(_presets);

  /// Built-in presets only
  List<PanelLayoutState> get builtInPresets =>
      _presets.where((p) => p.isBuiltIn).toList();

  /// User presets only
  List<PanelLayoutState> get userPresets =>
      _presets.where((p) => !p.isBuiltIn).toList();

  /// Load presets from storage
  Future<void> load() async {
    if (_isLoaded) return;

    // Add built-in presets first
    _presets.addAll(_builtInPresets);

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        for (final item in list) {
          final preset = PanelLayoutState.fromJson(item);
          // Don't duplicate built-in presets
          if (!preset.isBuiltIn) {
            _presets.add(preset);
          }
        }
      }
    } catch (e) { /* ignored */ }

    _isLoaded = true;
    notifyListeners();
  }

  /// Save presets to storage
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only save user presets (built-in are always added at load)
      final userPresetsJson = userPresets.map((p) => p.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(userPresetsJson));
    } catch (e) { /* ignored */ }
  }

  /// Get preset by ID
  PanelLayoutState? getPreset(String id) {
    try {
      return _presets.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get preset by name
  PanelLayoutState? getPresetByName(String name) {
    try {
      return _presets.firstWhere(
        (p) => p.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Save a new preset or update existing
  Future<void> savePreset(String name, {
    String? description,
    LowerZoneState? dawLowerZone,
    LowerZoneState? middlewareLowerZone,
    LowerZoneState? slotLabLowerZone,
    InspectorState? inspector,
    BrowserState? browser,
    MixerState? mixer,
  }) async {
    final now = DateTime.now();
    final existingIndex = _presets.indexWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase() && !p.isBuiltIn,
    );

    if (existingIndex >= 0) {
      // Update existing
      final existing = _presets[existingIndex];
      _presets[existingIndex] = existing.copyWith(
        description: description,
        dawLowerZone: dawLowerZone,
        middlewareLowerZone: middlewareLowerZone,
        slotLabLowerZone: slotLabLowerZone,
        inspector: inspector,
        browser: browser,
        mixer: mixer,
        modifiedAt: now,
      );
    } else {
      // Create new
      final preset = PanelLayoutState(
        id: 'user_${now.millisecondsSinceEpoch}',
        name: name,
        description: description,
        isBuiltIn: false,
        dawLowerZone: dawLowerZone,
        middlewareLowerZone: middlewareLowerZone,
        slotLabLowerZone: slotLabLowerZone,
        inspector: inspector,
        browser: browser,
        mixer: mixer,
        createdAt: now,
        modifiedAt: now,
      );
      _presets.add(preset);
    }

    await _save();
    notifyListeners();
  }

  /// Delete a user preset
  Future<void> deletePreset(String id) async {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index >= 0 && !_presets[index].isBuiltIn) {
      _presets.removeAt(index);
      await _save();
      notifyListeners();
    }
  }

  /// Rename a user preset
  Future<void> renamePreset(String id, String newName) async {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index >= 0 && !_presets[index].isBuiltIn) {
      _presets[index] = _presets[index].copyWith(
        name: newName,
        modifiedAt: DateTime.now(),
      );
      await _save();
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILT-IN PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  static final DateTime _builtInDate = DateTime(2026, 1, 1);

  static final List<PanelLayoutState> _builtInPresets = [
    // MIXING preset - focused on mixer and metering
    PanelLayoutState(
      id: 'builtin_mixing',
      name: 'Mixing',
      description: 'Optimized for mixing with large mixer and metering',
      isBuiltIn: true,
      dawLowerZone: const LowerZoneState(
        isExpanded: true,
        height: 300,
        superTabIndex: 2, // MIX tab
        subTabIndex: 0,   // Mixer
      ),
      inspector: const InspectorState(
        isVisible: true,
        width: 280,
        selectedTab: 1, // Track inspector
      ),
      mixer: const MixerState(
        isVisible: true,
        stripWidth: 80,
        showMeters: true,
        showSends: true,
        visibleTracks: [],
      ),
      createdAt: _builtInDate,
      modifiedAt: _builtInDate,
    ),

    // EDITING preset - focused on timeline and clips
    PanelLayoutState(
      id: 'builtin_editing',
      name: 'Editing',
      description: 'Optimized for timeline editing with clip details',
      isBuiltIn: true,
      dawLowerZone: const LowerZoneState(
        isExpanded: true,
        height: 250,
        superTabIndex: 1, // EDIT tab
        subTabIndex: 1,   // Clips
      ),
      inspector: const InspectorState(
        isVisible: true,
        width: 300,
        selectedTab: 2, // Clip inspector
      ),
      browser: const BrowserState(
        isVisible: false,
        width: 250,
        selectedFolder: '',
        expandedFolders: [],
      ),
      createdAt: _builtInDate,
      modifiedAt: _builtInDate,
    ),

    // SOUND DESIGN preset - focused on DSP and browser
    PanelLayoutState(
      id: 'builtin_sound_design',
      name: 'Sound Design',
      description: 'Optimized for sound design with browser and DSP',
      isBuiltIn: true,
      dawLowerZone: const LowerZoneState(
        isExpanded: true,
        height: 350,
        superTabIndex: 3, // PROCESS tab
        subTabIndex: 0,   // EQ
      ),
      browser: const BrowserState(
        isVisible: true,
        width: 300,
        selectedFolder: 'Samples',
        expandedFolders: ['Samples', 'SFX'],
      ),
      inspector: const InspectorState(
        isVisible: false,
        width: 280,
        selectedTab: 0,
      ),
      createdAt: _builtInDate,
      modifiedAt: _builtInDate,
    ),

    // RECORDING preset - focused on recording controls
    PanelLayoutState(
      id: 'builtin_recording',
      name: 'Recording',
      description: 'Optimized for recording with input monitoring',
      isBuiltIn: true,
      dawLowerZone: const LowerZoneState(
        isExpanded: true,
        height: 200,
        superTabIndex: 2, // MIX tab
        subTabIndex: 0,   // Mixer (for input monitoring)
      ),
      inspector: const InspectorState(
        isVisible: true,
        width: 280,
        selectedTab: 0, // Input settings
      ),
      mixer: const MixerState(
        isVisible: true,
        stripWidth: 64,
        showMeters: true,
        showSends: false,
        visibleTracks: [],
      ),
      createdAt: _builtInDate,
      modifiedAt: _builtInDate,
    ),

    // MASTERING preset - focused on metering and limiting
    PanelLayoutState(
      id: 'builtin_mastering',
      name: 'Mastering',
      description: 'Optimized for mastering with loudness metering',
      isBuiltIn: true,
      dawLowerZone: const LowerZoneState(
        isExpanded: true,
        height: 350,
        superTabIndex: 3, // PROCESS tab
        subTabIndex: 1,   // Limiter
      ),
      inspector: const InspectorState(
        isVisible: true,
        width: 320,
        selectedTab: 3, // Metering tab
      ),
      mixer: const MixerState(
        isVisible: true,
        stripWidth: 100,
        showMeters: true,
        showSends: false,
        visibleTracks: [],
      ),
      createdAt: _builtInDate,
      modifiedAt: _builtInDate,
    ),

    // MINIMAL preset - clean workspace
    PanelLayoutState(
      id: 'builtin_minimal',
      name: 'Minimal',
      description: 'Clean workspace with minimal panels',
      isBuiltIn: true,
      dawLowerZone: const LowerZoneState(
        isExpanded: false,
        height: 250,
        superTabIndex: 0,
        subTabIndex: 0,
      ),
      inspector: const InspectorState(
        isVisible: false,
        width: 280,
        selectedTab: 0,
      ),
      browser: const BrowserState(
        isVisible: false,
        width: 250,
        selectedFolder: '',
        expandedFolders: [],
      ),
      createdAt: _builtInDate,
      modifiedAt: _builtInDate,
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRESET PICKER WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Dropdown picker for panel presets
class PanelPresetPicker extends StatelessWidget {
  final PanelLayoutState? selectedPreset;
  final void Function(PanelLayoutState preset)? onPresetSelected;
  final VoidCallback? onSavePressed;
  final Color? accentColor;

  const PanelPresetPicker({
    super.key,
    this.selectedPreset,
    this.onPresetSelected,
    this.onSavePressed,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final service = PanelPresetsService.instance;
    final color = accentColor ?? Theme.of(context).colorScheme.primary;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preset icon
            Icon(Icons.dashboard_customize, size: 14, color: color),
            const SizedBox(width: 6),

            // Dropdown
            PopupMenuButton<PanelLayoutState>(
              tooltip: 'Select layout preset',
              onSelected: onPresetSelected,
              itemBuilder: (context) {
                final items = <PopupMenuEntry<PanelLayoutState>>[];

                // Built-in presets
                items.add(const PopupMenuItem<PanelLayoutState>(
                  enabled: false,
                  height: 28,
                  child: Text(
                    'BUILT-IN',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                ));

                for (final preset in service.builtInPresets) {
                  items.add(_buildPresetItem(preset, color));
                }

                // User presets
                if (service.userPresets.isNotEmpty) {
                  items.add(const PopupMenuDivider());
                  items.add(const PopupMenuItem<PanelLayoutState>(
                    enabled: false,
                    height: 28,
                    child: Text(
                      'CUSTOM',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                  ));

                  for (final preset in service.userPresets) {
                    items.add(_buildPresetItem(preset, color));
                  }
                }

                return items;
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selectedPreset?.name ?? 'Default',
                      style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, size: 14, color: color),
                  ],
                ),
              ),
            ),

            // Save button
            if (onSavePressed != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Save current layout as preset',
                child: InkWell(
                  onTap: onSavePressed,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.save_outlined, size: 14, color: color),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  PopupMenuItem<PanelLayoutState> _buildPresetItem(
    PanelLayoutState preset,
    Color color,
  ) {
    final isSelected = selectedPreset?.id == preset.id;

    return PopupMenuItem<PanelLayoutState>(
      value: preset,
      height: 36,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check : Icons.dashboard,
            size: 14,
            color: isSelected ? color : Colors.white54,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? color : Colors.white,
                  ),
                ),
                if (preset.description != null)
                  Text(
                    preset.description!,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white38,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!preset.isBuiltIn)
            Icon(Icons.person, size: 10, color: Colors.white24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAVE PRESET DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

/// Dialog for saving a new preset
class SavePresetDialog extends StatefulWidget {
  final String? initialName;
  final Color? accentColor;

  const SavePresetDialog({
    super.key,
    this.initialName,
    this.accentColor,
  });

  /// Show dialog and return preset name if saved
  static Future<String?> show(BuildContext context, {Color? accentColor}) {
    return showDialog<String>(
      context: context,
      builder: (context) => SavePresetDialog(accentColor: accentColor),
    );
  }

  @override
  State<SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends State<SavePresetDialog> {
  final _controller = TextEditingController();
  final _descController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) {
      _controller.text = widget.initialName!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _validateAndSave() {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }

    // Check for duplicate names (among user presets)
    final hasExisting = PanelPresetsService.instance.userPresets.any(
      (p) => p.name.toLowerCase() == name.toLowerCase(),
    );

    if (hasExisting) {
      setState(() => _error = 'A preset with this name already exists');
      return;
    }

    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      title: Row(
        children: [
          Icon(Icons.save, size: 20, color: color),
          const SizedBox(width: 8),
          const Text(
            'Save Layout Preset',
            style: TextStyle(fontSize: 14, color: Colors.white),
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
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Preset Name',
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                errorText: _error,
                errorStyle: TextStyle(color: color, fontSize: 10),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color),
                ),
                errorBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _validateAndSave(),
            ),
            const SizedBox(height: 12),

            // Description field
            TextField(
              controller: _descController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: color),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: color)),
        ),
        ElevatedButton(
          onPressed: _validateAndSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
