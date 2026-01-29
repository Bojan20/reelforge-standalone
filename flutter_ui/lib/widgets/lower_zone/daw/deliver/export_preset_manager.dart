/// Export Preset Manager (P3.7) — Save/load export configuration presets
///
/// Features:
/// - Built-in presets: Streaming, Broadcast, Archive, Stems
/// - Custom preset creation and management
/// - Format, bitrate, sample rate, normalization settings
/// - Stems export configuration
/// - Preset preview with estimated file size
///
/// Created: 2026-01-29
library;

import 'package:flutter/material.dart';
import '../../../../theme/fluxforge_theme.dart';

/// Audio export format
enum ExportFormat {
  wav16('WAV 16-bit', 'wav', false),
  wav24('WAV 24-bit', 'wav', false),
  wav32f('WAV 32-bit float', 'wav', false),
  flac('FLAC', 'flac', false),
  mp3High('MP3 320kbps', 'mp3', true),
  mp3Medium('MP3 192kbps', 'mp3', true),
  mp3Low('MP3 128kbps', 'mp3', true),
  oggHigh('OGG Q10', 'ogg', true),
  oggMedium('OGG Q7', 'ogg', true),
  aac('AAC 256kbps', 'm4a', true);

  final String displayName;
  final String extension;
  final bool isLossy;

  const ExportFormat(this.displayName, this.extension, this.isLossy);
}

/// Sample rate options
enum ExportSampleRate {
  sr44100(44100, '44.1 kHz'),
  sr48000(48000, '48 kHz'),
  sr88200(88200, '88.2 kHz'),
  sr96000(96000, '96 kHz'),
  sr176400(176400, '176.4 kHz'),
  sr192000(192000, '192 kHz');

  final int hz;
  final String displayName;

  const ExportSampleRate(this.hz, this.displayName);
}

/// Normalization mode
enum NormalizationMode {
  none('None', 'No normalization'),
  peak('Peak', 'Normalize to peak level'),
  lufsIntegrated('LUFS Integrated', 'EBU R128 integrated loudness'),
  lufsStreaming('LUFS Streaming', 'Streaming platform target (-14 LUFS)'),
  lfsBroadcast('LUFS Broadcast', 'Broadcast standard (-23 LUFS)');

  final String displayName;
  final String description;

  const NormalizationMode(this.displayName, this.description);
}

/// Dithering type for bit depth reduction
enum DitheringType {
  none('None'),
  triangular('Triangular (TPDF)'),
  shaped('Noise Shaped'),
  pow_r('POW-r');

  final String displayName;

  const DitheringType(this.displayName);
}

/// Stems export mode
enum StemsMode {
  none('Disabled'),
  allTracks('All Tracks'),
  selectedTracks('Selected Only'),
  byBus('By Bus'),
  byGroup('By Group');

  final String displayName;

  const StemsMode(this.displayName);
}

/// Export preset configuration
class ExportPreset {
  final String id;
  final String name;
  final String? description;
  final bool isBuiltIn;
  final ExportFormat format;
  final ExportSampleRate sampleRate;
  final NormalizationMode normalization;
  final double normalizationTarget; // dB or LUFS depending on mode
  final DitheringType dithering;
  final bool truePeakLimiting;
  final double truePeakCeiling; // dBTP
  final StemsMode stemsMode;
  final bool includeMarkers;
  final bool embedMetadata;
  final String? fileNamePattern;

  const ExportPreset({
    required this.id,
    required this.name,
    this.description,
    this.isBuiltIn = false,
    this.format = ExportFormat.wav24,
    this.sampleRate = ExportSampleRate.sr48000,
    this.normalization = NormalizationMode.none,
    this.normalizationTarget = -1.0,
    this.dithering = DitheringType.none,
    this.truePeakLimiting = false,
    this.truePeakCeiling = -1.0,
    this.stemsMode = StemsMode.none,
    this.includeMarkers = true,
    this.embedMetadata = true,
    this.fileNamePattern,
  });

  ExportPreset copyWith({
    String? id,
    String? name,
    String? description,
    bool? isBuiltIn,
    ExportFormat? format,
    ExportSampleRate? sampleRate,
    NormalizationMode? normalization,
    double? normalizationTarget,
    DitheringType? dithering,
    bool? truePeakLimiting,
    double? truePeakCeiling,
    StemsMode? stemsMode,
    bool? includeMarkers,
    bool? embedMetadata,
    String? fileNamePattern,
  }) {
    return ExportPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      normalization: normalization ?? this.normalization,
      normalizationTarget: normalizationTarget ?? this.normalizationTarget,
      dithering: dithering ?? this.dithering,
      truePeakLimiting: truePeakLimiting ?? this.truePeakLimiting,
      truePeakCeiling: truePeakCeiling ?? this.truePeakCeiling,
      stemsMode: stemsMode ?? this.stemsMode,
      includeMarkers: includeMarkers ?? this.includeMarkers,
      embedMetadata: embedMetadata ?? this.embedMetadata,
      fileNamePattern: fileNamePattern ?? this.fileNamePattern,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'isBuiltIn': isBuiltIn,
    'format': format.index,
    'sampleRate': sampleRate.index,
    'normalization': normalization.index,
    'normalizationTarget': normalizationTarget,
    'dithering': dithering.index,
    'truePeakLimiting': truePeakLimiting,
    'truePeakCeiling': truePeakCeiling,
    'stemsMode': stemsMode.index,
    'includeMarkers': includeMarkers,
    'embedMetadata': embedMetadata,
    'fileNamePattern': fileNamePattern,
  };

  factory ExportPreset.fromJson(Map<String, dynamic> json) => ExportPreset(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    format: ExportFormat.values[json['format'] as int? ?? 1],
    sampleRate: ExportSampleRate.values[json['sampleRate'] as int? ?? 1],
    normalization: NormalizationMode.values[json['normalization'] as int? ?? 0],
    normalizationTarget: (json['normalizationTarget'] as num?)?.toDouble() ?? -1.0,
    dithering: DitheringType.values[json['dithering'] as int? ?? 0],
    truePeakLimiting: json['truePeakLimiting'] as bool? ?? false,
    truePeakCeiling: (json['truePeakCeiling'] as num?)?.toDouble() ?? -1.0,
    stemsMode: StemsMode.values[json['stemsMode'] as int? ?? 0],
    includeMarkers: json['includeMarkers'] as bool? ?? true,
    embedMetadata: json['embedMetadata'] as bool? ?? true,
    fileNamePattern: json['fileNamePattern'] as String?,
  );
}

/// Built-in export presets
class BuiltInExportPresets {
  BuiltInExportPresets._();

  static const streaming = ExportPreset(
    id: 'builtin_streaming',
    name: 'Streaming',
    description: 'Optimized for streaming platforms (Spotify, Apple Music)',
    isBuiltIn: true,
    format: ExportFormat.wav24,
    sampleRate: ExportSampleRate.sr44100,
    normalization: NormalizationMode.lufsStreaming,
    normalizationTarget: -14.0,
    truePeakLimiting: true,
    truePeakCeiling: -1.0,
  );

  static const broadcast = ExportPreset(
    id: 'builtin_broadcast',
    name: 'Broadcast',
    description: 'EBU R128 compliant for TV/Radio broadcast',
    isBuiltIn: true,
    format: ExportFormat.wav24,
    sampleRate: ExportSampleRate.sr48000,
    normalization: NormalizationMode.lfsBroadcast,
    normalizationTarget: -23.0,
    truePeakLimiting: true,
    truePeakCeiling: -1.0,
  );

  static const archive = ExportPreset(
    id: 'builtin_archive',
    name: 'Archive',
    description: 'Maximum quality for archival purposes',
    isBuiltIn: true,
    format: ExportFormat.wav32f,
    sampleRate: ExportSampleRate.sr96000,
    normalization: NormalizationMode.none,
    truePeakLimiting: false,
    embedMetadata: true,
    includeMarkers: true,
  );

  static const stems = ExportPreset(
    id: 'builtin_stems',
    name: 'Stems',
    description: 'Export individual tracks for remixing',
    isBuiltIn: true,
    format: ExportFormat.wav24,
    sampleRate: ExportSampleRate.sr48000,
    normalization: NormalizationMode.none,
    stemsMode: StemsMode.allTracks,
    fileNamePattern: '{project}_{track}_{date}',
  );

  static const mp3Web = ExportPreset(
    id: 'builtin_mp3_web',
    name: 'MP3 Web',
    description: 'Compressed for web delivery',
    isBuiltIn: true,
    format: ExportFormat.mp3High,
    sampleRate: ExportSampleRate.sr44100,
    normalization: NormalizationMode.lufsStreaming,
    normalizationTarget: -14.0,
    truePeakLimiting: true,
    truePeakCeiling: -1.0,
  );

  static const List<ExportPreset> all = [
    streaming,
    broadcast,
    archive,
    stems,
    mp3Web,
  ];
}

/// Callback for preset selection
typedef OnPresetSelected = void Function(ExportPreset preset);

/// Callback for preset save
typedef OnPresetSaved = void Function(ExportPreset preset);

/// Export Preset Manager Panel
class ExportPresetManager extends StatefulWidget {
  /// Currently selected preset
  final ExportPreset? selectedPreset;

  /// Custom presets list
  final List<ExportPreset> customPresets;

  /// Callback when preset is selected
  final OnPresetSelected? onPresetSelected;

  /// Callback when preset is saved
  final OnPresetSaved? onPresetSaved;

  /// Callback when preset is deleted
  final ValueChanged<String>? onPresetDeleted;

  const ExportPresetManager({
    super.key,
    this.selectedPreset,
    this.customPresets = const [],
    this.onPresetSelected,
    this.onPresetSaved,
    this.onPresetDeleted,
  });

  @override
  State<ExportPresetManager> createState() => _ExportPresetManagerState();
}

class _ExportPresetManagerState extends State<ExportPresetManager> {
  ExportPreset? _editingPreset;
  bool _isCreatingNew = false;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<ExportPreset> get _allPresets => [
    ...BuiltInExportPresets.all,
    ...widget.customPresets,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Content
          Expanded(
            child: Row(
              children: [
                // Preset list
                SizedBox(
                  width: 200,
                  child: _buildPresetList(),
                ),

                // Divider
                Container(
                  width: 1,
                  color: FluxForgeTheme.borderSubtle,
                ),

                // Settings panel
                Expanded(
                  child: _buildSettingsPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.save_alt,
            size: 14,
            color: FluxForgeTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            'EXPORT PRESETS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),

          // New preset button
          _buildHeaderButton(
            icon: Icons.add,
            tooltip: 'New Preset',
            onTap: _startNewPreset,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetList() {
    return Container(
      color: FluxForgeTheme.bgDeep.withAlpha(100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Built-in section
          _buildSectionHeader('BUILT-IN'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                ...BuiltInExportPresets.all.map((p) => _buildPresetItem(p)),

                // Custom section
                if (widget.customPresets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSectionHeader('CUSTOM'),
                  ...widget.customPresets.map((p) => _buildPresetItem(p)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: FluxForgeTheme.textSecondary.withAlpha(150),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPresetItem(ExportPreset preset) {
    final isSelected = _editingPreset?.id == preset.id ||
        (!_isCreatingNew && widget.selectedPreset?.id == preset.id);

    return InkWell(
      onTap: () => _selectPreset(preset),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withAlpha(40)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? FluxForgeTheme.accentBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            // Icon
            Icon(
              preset.isBuiltIn ? Icons.lock_outline : Icons.tune,
              size: 12,
              color: isSelected
                  ? FluxForgeTheme.accentBlue
                  : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),

            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                  if (preset.description != null)
                    Text(
                      preset.description!,
                      style: TextStyle(
                        fontSize: 9,
                        color: FluxForgeTheme.textSecondary.withAlpha(150),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Format badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: preset.format.isLossy
                    ? Colors.orange.withAlpha(40)
                    : FluxForgeTheme.accentGreen.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                preset.format.extension.toUpperCase(),
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: preset.format.isLossy
                      ? Colors.orange
                      : FluxForgeTheme.accentGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    final preset = _editingPreset ?? widget.selectedPreset;

    if (preset == null && !_isCreatingNew) {
      return Center(
        child: Text(
          'Select a preset to view settings',
          style: TextStyle(
            fontSize: 11,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      child: _isCreatingNew || (_editingPreset != null && !_editingPreset!.isBuiltIn)
          ? _buildEditableSettings()
          : _buildReadOnlySettings(preset!),
    );
  }

  Widget _buildReadOnlySettings(ExportPreset preset) {
    return ListView(
      children: [
        // Preset info
        _buildSettingRow('Name', preset.name),
        if (preset.description != null)
          _buildSettingRow('Description', preset.description!),
        const SizedBox(height: 12),

        // Format section
        _buildSectionTitle('FORMAT'),
        _buildSettingRow('Format', preset.format.displayName),
        _buildSettingRow('Sample Rate', preset.sampleRate.displayName),
        if (preset.dithering != DitheringType.none)
          _buildSettingRow('Dithering', preset.dithering.displayName),
        const SizedBox(height: 12),

        // Normalization section
        _buildSectionTitle('NORMALIZATION'),
        _buildSettingRow('Mode', preset.normalization.displayName),
        if (preset.normalization != NormalizationMode.none)
          _buildSettingRow('Target', '${preset.normalizationTarget.toStringAsFixed(1)} ${_getNormalizationUnit(preset.normalization)}'),
        if (preset.truePeakLimiting)
          _buildSettingRow('True Peak Ceiling', '${preset.truePeakCeiling.toStringAsFixed(1)} dBTP'),
        const SizedBox(height: 12),

        // Stems section
        if (preset.stemsMode != StemsMode.none) ...[
          _buildSectionTitle('STEMS'),
          _buildSettingRow('Mode', preset.stemsMode.displayName),
          if (preset.fileNamePattern != null)
            _buildSettingRow('File Pattern', preset.fileNamePattern!),
          const SizedBox(height: 12),
        ],

        // Options section
        _buildSectionTitle('OPTIONS'),
        _buildSettingRow('Include Markers', preset.includeMarkers ? 'Yes' : 'No'),
        _buildSettingRow('Embed Metadata', preset.embedMetadata ? 'Yes' : 'No'),

        const SizedBox(height: 16),

        // Action buttons
        Row(
          children: [
            if (!preset.isBuiltIn) ...[
              _buildActionButton(
                label: 'Edit',
                icon: Icons.edit,
                onTap: () => _startEditing(preset),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                label: 'Delete',
                icon: Icons.delete_outline,
                isDestructive: true,
                onTap: () => _confirmDelete(preset),
              ),
              const Spacer(),
            ] else ...[
              _buildActionButton(
                label: 'Duplicate',
                icon: Icons.copy,
                onTap: () => _duplicatePreset(preset),
              ),
              const Spacer(),
            ],
            _buildActionButton(
              label: 'Apply',
              icon: Icons.check,
              isPrimary: true,
              onTap: () => widget.onPresetSelected?.call(preset),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditableSettings() {
    final preset = _editingPreset ?? ExportPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: '',
    );

    return ListView(
      children: [
        // Name field
        _buildTextField(
          label: 'Name',
          controller: _nameController,
          hint: 'Preset name',
        ),
        const SizedBox(height: 8),
        _buildTextField(
          label: 'Description',
          controller: _descriptionController,
          hint: 'Optional description',
        ),
        const SizedBox(height: 12),

        // Format section
        _buildSectionTitle('FORMAT'),
        _buildDropdown<ExportFormat>(
          label: 'Format',
          value: preset.format,
          items: ExportFormat.values,
          displayName: (f) => f.displayName,
          onChanged: (f) => _updatePreset(preset.copyWith(format: f)),
        ),
        const SizedBox(height: 8),
        _buildDropdown<ExportSampleRate>(
          label: 'Sample Rate',
          value: preset.sampleRate,
          items: ExportSampleRate.values,
          displayName: (sr) => sr.displayName,
          onChanged: (sr) => _updatePreset(preset.copyWith(sampleRate: sr)),
        ),
        const SizedBox(height: 8),
        _buildDropdown<DitheringType>(
          label: 'Dithering',
          value: preset.dithering,
          items: DitheringType.values,
          displayName: (d) => d.displayName,
          onChanged: (d) => _updatePreset(preset.copyWith(dithering: d)),
        ),
        const SizedBox(height: 12),

        // Normalization section
        _buildSectionTitle('NORMALIZATION'),
        _buildDropdown<NormalizationMode>(
          label: 'Mode',
          value: preset.normalization,
          items: NormalizationMode.values,
          displayName: (n) => n.displayName,
          onChanged: (n) => _updatePreset(preset.copyWith(normalization: n)),
        ),
        if (preset.normalization != NormalizationMode.none) ...[
          const SizedBox(height: 8),
          _buildSlider(
            label: 'Target',
            value: preset.normalizationTarget,
            min: -30.0,
            max: 0.0,
            suffix: _getNormalizationUnit(preset.normalization),
            onChanged: (v) => _updatePreset(preset.copyWith(normalizationTarget: v)),
          ),
        ],
        const SizedBox(height: 8),
        _buildSwitch(
          label: 'True Peak Limiting',
          value: preset.truePeakLimiting,
          onChanged: (v) => _updatePreset(preset.copyWith(truePeakLimiting: v)),
        ),
        if (preset.truePeakLimiting) ...[
          const SizedBox(height: 8),
          _buildSlider(
            label: 'Ceiling',
            value: preset.truePeakCeiling,
            min: -3.0,
            max: 0.0,
            suffix: 'dBTP',
            onChanged: (v) => _updatePreset(preset.copyWith(truePeakCeiling: v)),
          ),
        ],
        const SizedBox(height: 12),

        // Stems section
        _buildSectionTitle('STEMS'),
        _buildDropdown<StemsMode>(
          label: 'Mode',
          value: preset.stemsMode,
          items: StemsMode.values,
          displayName: (s) => s.displayName,
          onChanged: (s) => _updatePreset(preset.copyWith(stemsMode: s)),
        ),
        const SizedBox(height: 12),

        // Options section
        _buildSectionTitle('OPTIONS'),
        _buildSwitch(
          label: 'Include Markers',
          value: preset.includeMarkers,
          onChanged: (v) => _updatePreset(preset.copyWith(includeMarkers: v)),
        ),
        const SizedBox(height: 8),
        _buildSwitch(
          label: 'Embed Metadata',
          value: preset.embedMetadata,
          onChanged: (v) => _updatePreset(preset.copyWith(embedMetadata: v)),
        ),

        const SizedBox(height: 16),

        // Action buttons
        Row(
          children: [
            _buildActionButton(
              label: 'Cancel',
              icon: Icons.close,
              onTap: _cancelEditing,
            ),
            const Spacer(),
            _buildActionButton(
              label: 'Save',
              icon: Icons.save,
              isPrimary: true,
              onTap: () => _savePreset(preset),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: FluxForgeTheme.accentBlue,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textSecondary.withAlpha(100),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                ),
                filled: true,
                fillColor: FluxForgeTheme.bgMid,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) displayName,
    required ValueChanged<T> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: FluxForgeTheme.bgDeep,
                style: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textPrimary,
                ),
                items: items.map((item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(displayName(item)),
                )).toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentBlue,
              inactiveTrackColor: FluxForgeTheme.bgMid,
              thumbColor: FluxForgeTheme.accentBlue,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '${value.toStringAsFixed(1)} $suffix',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: FluxForgeTheme.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ),
        Transform.scale(
          scale: 0.7,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: FluxForgeTheme.accentBlue,
            activeTrackColor: FluxForgeTheme.accentBlue.withAlpha(100),
            inactiveThumbColor: FluxForgeTheme.textSecondary,
            inactiveTrackColor: FluxForgeTheme.bgMid,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? Colors.red
        : isPrimary
            ? FluxForgeTheme.accentBlue
            : FluxForgeTheme.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary ? color.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withAlpha(100)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNormalizationUnit(NormalizationMode mode) {
    switch (mode) {
      case NormalizationMode.none:
        return '';
      case NormalizationMode.peak:
        return 'dB';
      case NormalizationMode.lufsIntegrated:
      case NormalizationMode.lufsStreaming:
      case NormalizationMode.lfsBroadcast:
        return 'LUFS';
    }
  }

  void _selectPreset(ExportPreset preset) {
    setState(() {
      _editingPreset = preset;
      _isCreatingNew = false;
      _nameController.text = preset.name;
      _descriptionController.text = preset.description ?? '';
    });
  }

  void _startNewPreset() {
    setState(() {
      _isCreatingNew = true;
      _editingPreset = ExportPreset(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: 'New Preset',
      );
      _nameController.text = 'New Preset';
      _descriptionController.text = '';
    });
  }

  void _startEditing(ExportPreset preset) {
    setState(() {
      _editingPreset = preset;
      _isCreatingNew = false;
      _nameController.text = preset.name;
      _descriptionController.text = preset.description ?? '';
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingPreset = null;
      _isCreatingNew = false;
    });
  }

  void _updatePreset(ExportPreset preset) {
    setState(() {
      _editingPreset = preset;
    });
  }

  void _savePreset(ExportPreset preset) {
    final savedPreset = preset.copyWith(
      name: _nameController.text.trim().isEmpty ? 'Untitled' : _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
    );
    widget.onPresetSaved?.call(savedPreset);
    setState(() {
      _editingPreset = null;
      _isCreatingNew = false;
    });
  }

  void _duplicatePreset(ExportPreset preset) {
    final newPreset = preset.copyWith(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: '${preset.name} Copy',
      isBuiltIn: false,
    );
    setState(() {
      _editingPreset = newPreset;
      _isCreatingNew = true;
      _nameController.text = newPreset.name;
      _descriptionController.text = newPreset.description ?? '';
    });
  }

  void _confirmDelete(ExportPreset preset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text(
          'Delete Preset',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 14,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${preset.name}"?\nThis action cannot be undone.',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onPresetDeleted?.call(preset.id);
              setState(() {
                _editingPreset = null;
              });
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact preset selector for quick access
class ExportPresetSelector extends StatelessWidget {
  final ExportPreset? selectedPreset;
  final List<ExportPreset> customPresets;
  final OnPresetSelected? onPresetSelected;

  const ExportPresetSelector({
    super.key,
    this.selectedPreset,
    this.customPresets = const [],
    this.onPresetSelected,
  });

  List<ExportPreset> get _allPresets => [
    ...BuiltInExportPresets.all,
    ...customPresets,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedPreset?.id,
          isExpanded: true,
          dropdownColor: FluxForgeTheme.bgDeep,
          hint: Text(
            'Select preset...',
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          style: TextStyle(
            fontSize: 11,
            color: FluxForgeTheme.textPrimary,
          ),
          items: _allPresets.map((preset) => DropdownMenuItem<String>(
            value: preset.id,
            child: Row(
              children: [
                Icon(
                  preset.isBuiltIn ? Icons.lock_outline : Icons.tune,
                  size: 12,
                  color: FluxForgeTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(preset.name),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: preset.format.isLossy
                        ? Colors.orange.withAlpha(40)
                        : FluxForgeTheme.accentGreen.withAlpha(40),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    preset.format.extension.toUpperCase(),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: preset.format.isLossy
                          ? Colors.orange
                          : FluxForgeTheme.accentGreen,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
          onChanged: (id) {
            if (id != null) {
              final preset = _allPresets.firstWhere((p) => p.id == id);
              onPresetSelected?.call(preset);
            }
          },
        ),
      ),
    );
  }
}
