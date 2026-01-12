// Audio Export Dialog
//
// Provides a comprehensive dialog for exporting audio with:
// - Format selection (WAV, FLAC, MP3, AAC, OGG)
// - Sample rate selection
// - Bit depth selection
// - Normalization options
// - Dither options
// - Export range selection
// - Progress tracking

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/fluxforge_theme.dart';
import '../src/rust/engine_api.dart' as api;

/// Export format options
enum ExportFormat { wav, flac, mp3, aac, ogg }

/// Dither type options
enum DitherType { none, rectangular, triangular, noiseShape }

class ExportAudioDialog extends StatefulWidget {
  final String projectName;
  final double projectDuration; // in seconds

  const ExportAudioDialog({
    super.key,
    required this.projectName,
    this.projectDuration = 0,
  });

  static Future<ExportResult?> show(
    BuildContext context, {
    required String projectName,
    double projectDuration = 0,
  }) {
    return showDialog<ExportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExportAudioDialog(
        projectName: projectName,
        projectDuration: projectDuration,
      ),
    );
  }

  @override
  State<ExportAudioDialog> createState() => _ExportAudioDialogState();
}

class ExportResult {
  final String outputPath;
  final bool success;
  final String? error;
  final double durationSec;
  final int fileSizeBytes;

  ExportResult({
    required this.outputPath,
    required this.success,
    this.error,
    this.durationSec = 0,
    this.fileSizeBytes = 0,
  });
}

class _ExportAudioDialogState extends State<ExportAudioDialog> {
  // Export settings
  String _outputPath = '';
  ExportFormat _format = ExportFormat.wav;
  int _sampleRate = 48000;
  int _bitDepth = 24;
  bool _normalize = false;
  double _normalizeTarget = -1.0;
  DitherType _dither = DitherType.none;
  bool _includeMasterFx = true;
  bool _realTime = false;
  // ignore: unused_field
  double _startSec = 0;
  // ignore: unused_field
  double _endSec = 0;
  bool _exportWholeProject = true;

  // Presets
  String _selectedPreset = 'High Quality';

  // Export state
  bool _isExporting = false;
  double _progress = 0;
  String _phase = '';
  Timer? _progressTimer;

  final List<Map<String, dynamic>> _presets = [
    {'name': 'CD Quality', 'format': 0, 'sr': 44100, 'bits': 16, 'dither': 2},
    {'name': 'High Quality', 'format': 0, 'sr': 48000, 'bits': 24, 'dither': 0},
    {'name': 'Master', 'format': 0, 'sr': 96000, 'bits': 32, 'dither': 0},
    {'name': 'MP3 320k', 'format': 2, 'sr': 44100, 'bits': 16, 'dither': 0},
    {'name': 'FLAC Lossless', 'format': 1, 'sr': 48000, 'bits': 24, 'dither': 0},
    {'name': 'Broadcast (EBU R128)', 'format': 0, 'sr': 48000, 'bits': 24, 'norm': true, 'normTarget': -23.0},
  ];

  @override
  void initState() {
    super.initState();
    _endSec = widget.projectDuration;
    _outputPath = '${widget.projectName}.wav';
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  String get _formatExtension {
    switch (_format) {
      case ExportFormat.wav:
        return 'wav';
      case ExportFormat.flac:
        return 'flac';
      case ExportFormat.mp3:
        return 'mp3';
      case ExportFormat.aac:
        return 'm4a';
      case ExportFormat.ogg:
        return 'ogg';
    }
  }

  void _applyPreset(String presetName) {
    final preset = _presets.firstWhere(
      (p) => p['name'] == presetName,
      orElse: () => _presets[1],
    );

    setState(() {
      _selectedPreset = presetName;
      _format = ExportFormat.values[preset['format'] as int];
      _sampleRate = preset['sr'] as int;
      _bitDepth = preset['bits'] as int;
      _dither = DitherType.values[preset['dither'] as int? ?? 0];
      _normalize = preset['norm'] as bool? ?? false;
      _normalizeTarget = preset['normTarget'] as double? ?? -1.0;
      _updateOutputPath();
    });
  }

  void _updateOutputPath() {
    final baseName = _outputPath.replaceAll(RegExp(r'\.[^.]+$'), '');
    setState(() {
      _outputPath = '$baseName.$_formatExtension';
    });
  }

  Future<void> _startExport() async {
    if (_outputPath.isEmpty) {
      _showError('Please specify an output path');
      return;
    }

    setState(() {
      _isExporting = true;
      _progress = 0;
      _phase = 'Rendering';
    });

    // Start progress polling
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _updateProgress();
    });

    try {
      // Map format to Rust enum (0=Wav16, 1=Wav24, 2=Wav32Float)
      int rustFormat;
      if (_format == ExportFormat.wav) {
        if (_bitDepth == 16) {
          rustFormat = 0; // Wav16
        } else if (_bitDepth == 24) {
          rustFormat = 1; // Wav24
        } else {
          rustFormat = 2; // Wav32Float
        }
      } else {
        // For now, only WAV is supported in Rust
        rustFormat = 1; // Default to Wav24
      }

      final startTime = _exportWholeProject ? 0.0 : _startSec;
      final endTime = _exportWholeProject ? widget.projectDuration : _endSec;

      // Call Rust export API
      final success = api.exportAudio(
        _outputPath,
        rustFormat,
        _sampleRate,
        startTime,
        endTime,
        normalize: _normalize,
      );

      if (!success) {
        throw Exception('Export failed to start');
      }

      // Wait for export to complete
      while (api.exportIsExporting()) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) break;
      }

      if (mounted) {
        _progressTimer?.cancel();
        Navigator.of(context).pop(ExportResult(
          outputPath: _outputPath,
          success: true,
          durationSec: widget.projectDuration,
        ));
      }
    } catch (e) {
      _progressTimer?.cancel();
      setState(() {
        _isExporting = false;
      });
      _showError('Export failed: $e');
    }
  }

  void _updateProgress() {
    // Poll progress from Rust (0.0 - 100.0)
    final progressPercent = api.exportGetProgress();

    setState(() {
      _progress = (progressPercent / 100.0).clamp(0.0, 1.0);

      // Update phase based on progress
      if (_progress < 0.8) {
        _phase = 'Rendering';
      } else if (_progress < 0.95 && _normalize) {
        _phase = 'Normalizing';
      } else {
        _phase = 'Writing';
      }
    });
  }

  void _cancelExport() async {
    // TODO: api.exportCancel();
    _progressTimer?.cancel();
    setState(() {
      _isExporting = false;
      _progress = 0;
      _phase = '';
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: FluxForgeTheme.accentRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _browseOutputPath() async {
    // TODO: Use file picker
    // For now, just show a text input dialog
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: _isExporting ? _buildExportingView() : _buildSettingsView(),
      ),
    );
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.file_download, color: FluxForgeTheme.accentGreen, size: 24),
              const SizedBox(width: 12),
              Text('Export Audio', style: FluxForgeTheme.h2),
            ],
          ),
          const SizedBox(height: 24),

          // Preset selection
          _buildSection('Preset', _buildPresetSelector()),
          const SizedBox(height: 20),

          // Output path
          _buildSection('Output File', _buildOutputPathField()),
          const SizedBox(height: 20),

          // Format & Quality row
          Row(
            children: [
              Expanded(child: _buildSection('Format', _buildFormatSelector())),
              const SizedBox(width: 16),
              Expanded(child: _buildSection('Sample Rate', _buildSampleRateSelector())),
              const SizedBox(width: 16),
              Expanded(child: _buildSection('Bit Depth', _buildBitDepthSelector())),
            ],
          ),
          const SizedBox(height: 20),

          // Range selection
          _buildSection('Export Range', _buildRangeSelector()),
          const SizedBox(height: 20),

          // Advanced options
          ExpansionTile(
            title: Text(
              'Advanced Options',
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 14),
            ),
            iconColor: FluxForgeTheme.textSecondary,
            collapsedIconColor: FluxForgeTheme.textSecondary,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    _buildAdvancedOption(
                      'Normalize',
                      _normalize,
                      (v) => setState(() => _normalize = v),
                      subtitle: _normalize ? '${_normalizeTarget.toStringAsFixed(1)} dB' : null,
                    ),
                    if (_normalize) _buildNormalizeSlider(),
                    _buildAdvancedOption(
                      'Include Master FX',
                      _includeMasterFx,
                      (v) => setState(() => _includeMasterFx = v),
                    ),
                    _buildAdvancedOption(
                      'Real-time Export',
                      _realTime,
                      (v) => setState(() => _realTime = v),
                      subtitle: 'For external hardware',
                    ),
                    _buildDitherSelector(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _startExport,
                icon: const Icon(Icons.file_download, size: 18),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accentGreen,
                  foregroundColor: FluxForgeTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportingView() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.file_download,
            color: FluxForgeTheme.accentBlue,
            size: 48,
          ),
          const SizedBox(height: 24),
          Text('Exporting Audio', style: FluxForgeTheme.h2),
          const SizedBox(height: 8),
          Text(
            _phase,
            style: TextStyle(color: FluxForgeTheme.textSecondary),
          ),
          const SizedBox(height: 32),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: FluxForgeTheme.bgSurface,
            valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentGreen),
          ),
          const SizedBox(height: 12),
          Text(
            '${(_progress * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: _cancelExport,
            child: Text(
              'Cancel',
              style: TextStyle(color: FluxForgeTheme.accentRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildPresetSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presets.map((preset) {
        final name = preset['name'] as String;
        final isSelected = _selectedPreset == name;
        return FilterChip(
          label: Text(name),
          selected: isSelected,
          onSelected: (_) => _applyPreset(name),
          backgroundColor: FluxForgeTheme.bgSurface,
          selectedColor: FluxForgeTheme.accentBlue,
          labelStyle: TextStyle(
            color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textPrimary,
            fontSize: 12,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        );
      }).toList(),
    );
  }

  Widget _buildOutputPathField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: _outputPath),
            style: TextStyle(color: FluxForgeTheme.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: FluxForgeTheme.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixText: '.$_formatExtension',
              suffixStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
            onChanged: (value) => setState(() => _outputPath = value),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.folder_open, color: FluxForgeTheme.textSecondary),
          onPressed: _browseOutputPath,
          tooltip: 'Browse',
        ),
      ],
    );
  }

  Widget _buildFormatSelector() {
    return DropdownButtonFormField<ExportFormat>(
      value: _format,
      dropdownColor: FluxForgeTheme.bgMid,
      style: TextStyle(color: FluxForgeTheme.textPrimary),
      decoration: _dropdownDecoration(),
      items: ExportFormat.values.map((format) {
        return DropdownMenuItem(
          value: format,
          child: Text(format.name.toUpperCase()),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _format = value;
            _updateOutputPath();
          });
        }
      },
    );
  }

  Widget _buildSampleRateSelector() {
    return DropdownButtonFormField<int>(
      value: _sampleRate,
      dropdownColor: FluxForgeTheme.bgMid,
      style: TextStyle(color: FluxForgeTheme.textPrimary),
      decoration: _dropdownDecoration(),
      items: [44100, 48000, 88200, 96000, 176400, 192000].map((rate) {
        return DropdownMenuItem(
          value: rate,
          child: Text('${rate ~/ 1000}.${(rate % 1000) ~/ 100} kHz'),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) setState(() => _sampleRate = value);
      },
    );
  }

  Widget _buildBitDepthSelector() {
    return DropdownButtonFormField<int>(
      value: _bitDepth,
      dropdownColor: FluxForgeTheme.bgMid,
      style: TextStyle(color: FluxForgeTheme.textPrimary),
      decoration: _dropdownDecoration(),
      items: [16, 24, 32].map((bits) {
        return DropdownMenuItem(
          value: bits,
          child: Text('$bits-bit'),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) setState(() => _bitDepth = value);
      },
    );
  }

  Widget _buildRangeSelector() {
    return Column(
      children: [
        Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: _exportWholeProject,
              onChanged: (v) => setState(() => _exportWholeProject = v!),
              activeColor: FluxForgeTheme.accentBlue,
            ),
            Text('Whole project', style: TextStyle(color: FluxForgeTheme.textPrimary)),
            const SizedBox(width: 24),
            Radio<bool>(
              value: false,
              groupValue: _exportWholeProject,
              onChanged: (v) => setState(() => _exportWholeProject = v!),
              activeColor: FluxForgeTheme.accentBlue,
            ),
            Text('Selection', style: TextStyle(color: FluxForgeTheme.textPrimary)),
          ],
        ),
        if (!_exportWholeProject) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: _inputDecoration('Start (seconds)'),
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: FluxForgeTheme.textPrimary),
                  onChanged: (v) => _startSec = double.tryParse(v) ?? 0,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  decoration: _inputDecoration('End (seconds)'),
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: FluxForgeTheme.textPrimary),
                  onChanged: (v) => _endSec = double.tryParse(v) ?? widget.projectDuration,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedOption(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: FluxForgeTheme.accentBlue,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: FluxForgeTheme.textPrimary)),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalizeSlider() {
    return Padding(
      padding: const EdgeInsets.only(left: 40, right: 16, bottom: 8),
      child: Row(
        children: [
          Text('Target:', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
          Expanded(
            child: Slider(
              value: _normalizeTarget,
              min: -24,
              max: 0,
              divisions: 24,
              label: '${_normalizeTarget.toStringAsFixed(1)} dB',
              activeColor: FluxForgeTheme.accentBlue,
              onChanged: (v) => setState(() => _normalizeTarget = v),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${_normalizeTarget.toStringAsFixed(1)} dB',
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDitherSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text('Dither:', style: TextStyle(color: FluxForgeTheme.textPrimary)),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<DitherType>(
              value: _dither,
              dropdownColor: FluxForgeTheme.bgMid,
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              decoration: _dropdownDecoration(),
              items: DitherType.values.map((d) {
                final labels = {
                  DitherType.none: 'None',
                  DitherType.rectangular: 'Rectangular',
                  DitherType.triangular: 'Triangular (TPDF)',
                  DitherType.noiseShape: 'Noise Shaping',
                };
                return DropdownMenuItem(value: d, child: Text(labels[d]!));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _dither = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dropdownDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: FluxForgeTheme.bgSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
      filled: true,
      fillColor: FluxForgeTheme.bgSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}
