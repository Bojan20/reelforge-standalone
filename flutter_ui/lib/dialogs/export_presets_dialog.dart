// Export Presets Management Dialog
//
// Manage export presets with:
// - Create/Edit/Delete presets
// - Format/quality settings
// - Naming templates
// - Default presets (CD, Streaming, Broadcast)
// - Import/Export presets

import 'dart:convert';
import 'package:flutter/material.dart';
import '../src/rust/native_ffi.dart';
import '../theme/fluxforge_theme.dart';

/// Export preset data
class ExportPreset {
  final String id;
  final String name;
  final String description;
  final ExportFormat format;
  final int sampleRate;
  final int bitDepth;
  final bool normalize;
  final double normalizeTarget; // dB
  final bool dither;
  final String ditherType;
  final String namingTemplate;
  final bool isDefault;
  final bool isBuiltIn;

  ExportPreset({
    required this.id,
    required this.name,
    this.description = '',
    this.format = ExportFormat.wav,
    this.sampleRate = 48000,
    this.bitDepth = 24,
    this.normalize = false,
    this.normalizeTarget = -1.0,
    this.dither = false,
    this.ditherType = 'triangular',
    this.namingTemplate = '{project}_{track}',
    this.isDefault = false,
    this.isBuiltIn = false,
  });

  factory ExportPreset.fromJson(Map<String, dynamic> json) {
    return ExportPreset(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      format: ExportFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => ExportFormat.wav,
      ),
      sampleRate: json['sample_rate'] ?? 48000,
      bitDepth: json['bit_depth'] ?? 24,
      normalize: json['normalize'] ?? false,
      normalizeTarget: (json['normalize_target'] ?? -1.0).toDouble(),
      dither: json['dither'] ?? false,
      ditherType: json['dither_type'] ?? 'triangular',
      namingTemplate: json['naming_template'] ?? '{project}_{track}',
      isDefault: json['is_default'] ?? false,
      isBuiltIn: json['is_built_in'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'format': format.name,
      'sample_rate': sampleRate,
      'bit_depth': bitDepth,
      'normalize': normalize,
      'normalize_target': normalizeTarget,
      'dither': dither,
      'dither_type': ditherType,
      'naming_template': namingTemplate,
      'is_default': isDefault,
      'is_built_in': isBuiltIn,
    };
  }

  ExportPreset copyWith({
    String? name,
    String? description,
    ExportFormat? format,
    int? sampleRate,
    int? bitDepth,
    bool? normalize,
    double? normalizeTarget,
    bool? dither,
    String? ditherType,
    String? namingTemplate,
    bool? isDefault,
  }) {
    return ExportPreset(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      normalize: normalize ?? this.normalize,
      normalizeTarget: normalizeTarget ?? this.normalizeTarget,
      dither: dither ?? this.dither,
      ditherType: ditherType ?? this.ditherType,
      namingTemplate: namingTemplate ?? this.namingTemplate,
      isDefault: isDefault ?? this.isDefault,
      isBuiltIn: false, // User copies are never built-in
    );
  }

  String get formatLabel => '${format.label} ${bitDepth}-bit ${sampleRate ~/ 1000}kHz';
}

enum ExportFormat {
  wav,
  aiff,
  flac,
  mp3,
  aac,
  ogg,
}

extension ExportFormatExt on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.wav: return 'WAV';
      case ExportFormat.aiff: return 'AIFF';
      case ExportFormat.flac: return 'FLAC';
      case ExportFormat.mp3: return 'MP3';
      case ExportFormat.aac: return 'AAC';
      case ExportFormat.ogg: return 'OGG';
    }
  }

  String get extension {
    switch (this) {
      case ExportFormat.wav: return '.wav';
      case ExportFormat.aiff: return '.aiff';
      case ExportFormat.flac: return '.flac';
      case ExportFormat.mp3: return '.mp3';
      case ExportFormat.aac: return '.m4a';
      case ExportFormat.ogg: return '.ogg';
    }
  }

  bool get isLossless => this == ExportFormat.wav || this == ExportFormat.aiff || this == ExportFormat.flac;
}

/// Export Presets Dialog
class ExportPresetsDialog extends StatefulWidget {
  final ExportPreset? selectedPreset;
  final void Function(ExportPreset preset)? onPresetSelected;

  const ExportPresetsDialog({
    super.key,
    this.selectedPreset,
    this.onPresetSelected,
  });

  @override
  State<ExportPresetsDialog> createState() => _ExportPresetsDialogState();
}

class _ExportPresetsDialogState extends State<ExportPresetsDialog> {
  final _ffi = NativeFFI.instance;
  List<ExportPreset> _presets = [];
  ExportPreset? _selectedPreset;
  bool _isEditing = false;

  // Built-in presets
  static final List<ExportPreset> _builtInPresets = [
    ExportPreset(
      id: 'cd_master',
      name: 'CD Master',
      description: 'Red Book CD standard',
      format: ExportFormat.wav,
      sampleRate: 44100,
      bitDepth: 16,
      normalize: true,
      normalizeTarget: -0.3,
      dither: true,
      ditherType: 'triangular',
      isBuiltIn: true,
    ),
    ExportPreset(
      id: 'hd_master',
      name: 'HD Master',
      description: 'High-resolution master',
      format: ExportFormat.wav,
      sampleRate: 96000,
      bitDepth: 24,
      normalize: true,
      normalizeTarget: -1.0,
      isBuiltIn: true,
    ),
    ExportPreset(
      id: 'streaming',
      name: 'Streaming',
      description: 'Optimized for streaming platforms',
      format: ExportFormat.flac,
      sampleRate: 48000,
      bitDepth: 24,
      normalize: true,
      normalizeTarget: -14.0, // LUFS target
      isBuiltIn: true,
    ),
    ExportPreset(
      id: 'mp3_320',
      name: 'MP3 320kbps',
      description: 'High quality MP3',
      format: ExportFormat.mp3,
      sampleRate: 48000,
      bitDepth: 16,
      isBuiltIn: true,
    ),
    ExportPreset(
      id: 'broadcast',
      name: 'Broadcast',
      description: 'EBU R128 broadcast standard',
      format: ExportFormat.wav,
      sampleRate: 48000,
      bitDepth: 24,
      normalize: true,
      normalizeTarget: -23.0, // LUFS
      isBuiltIn: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadPresets();
    _selectedPreset = widget.selectedPreset;
  }

  void _loadPresets() {
    final json = _ffi.exportPresetsList();
    final list = jsonDecode(json) as List;
    final userPresets = list.map((e) => ExportPreset.fromJson(e)).toList();

    setState(() {
      _presets = [..._builtInPresets, ...userPresets];
    });
  }

  void _savePreset(ExportPreset preset) {
    _ffi.exportPresetSave(jsonEncode(preset.toJson()));
    _loadPresets();
  }

  void _deletePreset(ExportPreset preset) {
    if (preset.isBuiltIn) return;
    _ffi.exportPresetDelete(preset.id);
    _loadPresets();
    if (_selectedPreset?.id == preset.id) {
      setState(() => _selectedPreset = null);
    }
  }

  void _duplicatePreset(ExportPreset preset) {
    final newPreset = preset.copyWith(
      name: '${preset.name} (Copy)',
    );
    _savePreset(ExportPreset(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: newPreset.name,
      description: newPreset.description,
      format: newPreset.format,
      sampleRate: newPreset.sampleRate,
      bitDepth: newPreset.bitDepth,
      normalize: newPreset.normalize,
      normalizeTarget: newPreset.normalizeTarget,
      dither: newPreset.dither,
      ditherType: newPreset.ditherType,
      namingTemplate: newPreset.namingTemplate,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: _buildPresetList(),
                  ),
                  const VerticalDivider(width: 1, color: FluxForgeTheme.borderSubtle),
                  Expanded(
                    child: _selectedPreset != null
                        ? _buildPresetDetails()
                        : _buildEmptyState(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Icon(Icons.tune, color: FluxForgeTheme.accentBlue, size: 20),
          const SizedBox(width: 10),
          const Text(
            'Export Presets',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            color: FluxForgeTheme.textSecondary,
            onPressed: _createNewPreset,
            tooltip: 'New Preset',
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: FluxForgeTheme.textSecondary,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetList() {
    final builtIn = _presets.where((p) => p.isBuiltIn).toList();
    final user = _presets.where((p) => !p.isBuiltIn).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'BUILT-IN',
          style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        ...builtIn.map((p) => _buildPresetItem(p)),
        if (user.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'USER PRESETS',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          ...user.map((p) => _buildPresetItem(p)),
        ],
      ],
    );
  }

  Widget _buildPresetItem(ExportPreset preset) {
    final isSelected = _selectedPreset?.id == preset.id;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedPreset = preset;
        _isEditing = false;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: preset.format.isLossless
                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                    : FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  preset.format.label,
                  style: TextStyle(
                    color: preset.format.isLossless
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.accentOrange,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preset.name,
                          style: const TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (preset.isBuiltIn)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.textPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'BUILT-IN',
                            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 7),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${preset.bitDepth}-bit ${preset.sampleRate ~/ 1000}kHz',
                    style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetDetails() {
    final preset = _selectedPreset!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: const TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (preset.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preset.description,
                        style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              if (!preset.isBuiltIn) ...[
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  color: FluxForgeTheme.textSecondary,
                  onPressed: () => setState(() => _isEditing = true),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: FluxForgeTheme.textTertiary,
                  onPressed: () => _deletePreset(preset),
                  tooltip: 'Delete',
                ),
              ],
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                color: FluxForgeTheme.textSecondary,
                onPressed: () => _duplicatePreset(preset),
                tooltip: 'Duplicate',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDetailSection('Format', [
            _buildDetailRow('Type', preset.format.label),
            _buildDetailRow('Extension', preset.format.extension),
            _buildDetailRow('Quality', preset.format.isLossless ? 'Lossless' : 'Lossy'),
          ]),
          const SizedBox(height: 16),
          _buildDetailSection('Audio', [
            _buildDetailRow('Sample Rate', '${preset.sampleRate} Hz'),
            _buildDetailRow('Bit Depth', '${preset.bitDepth}-bit'),
          ]),
          if (preset.normalize) ...[
            const SizedBox(height: 16),
            _buildDetailSection('Normalization', [
              _buildDetailRow('Target', '${preset.normalizeTarget.toStringAsFixed(1)} dB'),
            ]),
          ],
          if (preset.dither) ...[
            const SizedBox(height: 16),
            _buildDetailSection('Dithering', [
              _buildDetailRow('Type', preset.ditherType),
            ]),
          ],
          const SizedBox(height: 16),
          _buildDetailSection('Naming', [
            _buildDetailRow('Template', preset.namingTemplate),
          ]),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 48, color: FluxForgeTheme.textDisabled),
          SizedBox(height: 16),
          Text(
            'Select a preset',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () {
              // Import presets from file
            },
            icon: const Icon(Icons.file_download, size: 16),
            label: const Text('Import'),
          ),
          TextButton.icon(
            onPressed: () {
              // Export presets to file
            },
            icon: const Icon(Icons.file_upload, size: 16),
            label: const Text('Export'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _selectedPreset != null
                ? () {
                    widget.onPresetSelected?.call(_selectedPreset!);
                    Navigator.pop(context);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
              foregroundColor: FluxForgeTheme.textPrimary,
            ),
            child: const Text('Use Preset'),
          ),
        ],
      ),
    );
  }

  void _createNewPreset() {
    final newPreset = ExportPreset(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Preset',
    );
    _savePreset(newPreset);
    setState(() {
      _selectedPreset = newPreset;
      _isEditing = true;
    });
  }
}
