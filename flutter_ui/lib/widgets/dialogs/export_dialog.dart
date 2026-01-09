/// Export/Bounce Dialog
///
/// Professional export dialog with:
/// - Format selection (WAV, FLAC, MP3)
/// - Bit depth (16/24/32-bit)
/// - Sample rate (project rate or custom)
/// - Time range (full timeline, selection, loop region)
/// - Normalization options
/// - Real-time progress tracking
/// - ETA and speed display

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../theme/reelforge_theme.dart';
import '../../src/rust/engine_api.dart' as api;

class ExportDialog extends StatefulWidget {
  final double currentTime;
  final double totalDuration;
  final double? selectionStart;
  final double? selectionEnd;
  final double? loopStart;
  final double? loopEnd;

  const ExportDialog({
    super.key,
    required this.currentTime,
    required this.totalDuration,
    this.selectionStart,
    this.selectionEnd,
    this.loopStart,
    this.loopEnd,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  // Export settings
  api.ExportFormat _format = api.ExportFormat.wav;
  api.ExportBitDepth _bitDepth = api.ExportBitDepth.int24;
  int _sampleRate = 0; // 0 = project rate
  _TimeRange _timeRange = _TimeRange.fullTimeline;
  bool _normalize = false;
  double _normalizeTarget = -0.1;
  String? _outputPath;

  // Progress tracking
  bool _isExporting = false;
  Timer? _progressTimer;
  api.BounceProgress? _progress;

  @override
  void initState() {
    super.initState();

    // Auto-select time range based on available regions
    if (widget.selectionStart != null && widget.selectionEnd != null) {
      _timeRange = _TimeRange.selection;
    } else if (widget.loopStart != null && widget.loopEnd != null) {
      _timeRange = _TimeRange.loopRegion;
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectOutputPath() async {
    final extension = _format == api.ExportFormat.wav
        ? 'wav'
        : _format == api.ExportFormat.flac
            ? 'flac'
            : 'mp3';

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Audio',
      fileName: 'export.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
    );

    if (result != null) {
      setState(() => _outputPath = result);
    }
  }

  (double, double) _getTimeRange() {
    switch (_timeRange) {
      case _TimeRange.fullTimeline:
        return (0.0, widget.totalDuration);
      case _TimeRange.selection:
        return (
          widget.selectionStart ?? 0.0,
          widget.selectionEnd ?? widget.totalDuration,
        );
      case _TimeRange.loopRegion:
        return (
          widget.loopStart ?? 0.0,
          widget.loopEnd ?? widget.totalDuration,
        );
      case _TimeRange.custom:
        return (0.0, widget.totalDuration); // TODO: custom range input
    }
  }

  Future<void> _startExport() async {
    if (_outputPath == null) {
      await _selectOutputPath();
      if (_outputPath == null) return;
    }

    final (startTime, endTime) = _getTimeRange();

    final success = api.bounceStart(
      outputPath: _outputPath!,
      format: _format,
      bitDepth: _bitDepth,
      sampleRate: _sampleRate,
      startTime: startTime,
      endTime: endTime,
      normalize: _normalize,
      normalizeTarget: _normalizeTarget,
    );

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start export')),
        );
      }
      return;
    }

    setState(() => _isExporting = true);

    // Poll progress
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;

      final progress = api.bounceGetProgress();
      setState(() => _progress = progress);

      if (progress.isComplete) {
        _onExportComplete();
      } else if (progress.wasCancelled) {
        _onExportCancelled();
      }
    });
  }

  void _onExportComplete() {
    _progressTimer?.cancel();
    api.bounceClear();

    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export complete: $_outputPath'),
          backgroundColor: ReelForgeTheme.accentGreen,
        ),
      );
    }
  }

  void _onExportCancelled() {
    _progressTimer?.cancel();
    api.bounceClear();

    setState(() {
      _isExporting = false;
      _progress = null;
    });
  }

  void _cancelExport() {
    api.bounceCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReelForgeTheme.bgElevated,
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: _isExporting
            ? _buildProgressView()
            : _buildSettingsView(),
      ),
    );
  }

  Widget _buildSettingsView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.file_download, color: ReelForgeTheme.accentBlue),
            const SizedBox(width: 12),
            const Text(
              'Export Audio',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ReelForgeTheme.textPrimary,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: ReelForgeTheme.textSecondary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Output file
        _buildOutputFileSection(),
        const SizedBox(height: 16),

        // Format selection
        _buildFormatSection(),
        const SizedBox(height: 16),

        // Quality settings
        _buildQualitySection(),
        const SizedBox(height: 16),

        // Time range
        _buildTimeRangeSection(),
        const SizedBox(height: 16),

        // Normalize option
        _buildNormalizeSection(),
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
              onPressed: _outputPath != null ? _startExport : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Export'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ReelForgeTheme.accentGreen,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressView() {
    final progress = _progress;
    if (progress == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Exporting Audio',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: ReelForgeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 32),

        // Progress bar
        LinearProgressIndicator(
          value: progress.percent / 100.0,
          backgroundColor: ReelForgeTheme.bgMid,
          valueColor: const AlwaysStoppedAnimation(ReelForgeTheme.accentGreen),
          minHeight: 8,
        ),
        const SizedBox(height: 16),

        // Progress stats
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${progress.percent.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: ReelForgeTheme.textPrimary,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Speed: ${progress.speedFactor.toStringAsFixed(1)}x',
                  style: const TextStyle(color: ReelForgeTheme.textSecondary),
                ),
                Text(
                  'ETA: ${_formatTime(progress.etaSecs)}',
                  style: const TextStyle(color: ReelForgeTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Peak level
        Row(
          children: [
            const Icon(
              Icons.graphic_eq,
              size: 16,
              color: ReelForgeTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Peak: ${_formatDb(progress.peakLevel)}',
              style: const TextStyle(color: ReelForgeTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Cancel button
        OutlinedButton.icon(
          onPressed: _cancelExport,
          icon: const Icon(Icons.cancel),
          label: const Text('Cancel Export'),
          style: OutlinedButton.styleFrom(
            foregroundColor: ReelForgeTheme.errorRed,
            side: const BorderSide(color: ReelForgeTheme.errorRed),
          ),
        ),
      ],
    );
  }

  Widget _buildOutputFileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Output File',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: ReelForgeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectOutputPath,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ReelForgeTheme.borderSubtle),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder, color: ReelForgeTheme.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _outputPath ?? 'Click to select output file...',
                    style: TextStyle(
                      color: _outputPath != null
                          ? ReelForgeTheme.textPrimary
                          : ReelForgeTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Format',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: ReelForgeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildFormatChip('WAV', api.ExportFormat.wav, Icons.music_note),
            const SizedBox(width: 8),
            _buildFormatChip('FLAC', api.ExportFormat.flac, Icons.compress),
            const SizedBox(width: 8),
            _buildFormatChip('MP3', api.ExportFormat.mp3, Icons.headphones),
          ],
        ),
      ],
    );
  }

  Widget _buildFormatChip(String label, api.ExportFormat format, IconData icon) {
    final isSelected = _format == format;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _format = format),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15) : ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.borderSubtle,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quality',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: ReelForgeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Bit depth
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bit Depth',
                    style: TextStyle(
                      fontSize: 12,
                      color: ReelForgeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButton<api.ExportBitDepth>(
                    value: _bitDepth,
                    isExpanded: true,
                    dropdownColor: ReelForgeTheme.bgElevated,
                    style: const TextStyle(color: ReelForgeTheme.textPrimary),
                    items: const [
                      DropdownMenuItem(
                        value: api.ExportBitDepth.int16,
                        child: Text('16-bit (CD Quality)'),
                      ),
                      DropdownMenuItem(
                        value: api.ExportBitDepth.int24,
                        child: Text('24-bit (Professional)'),
                      ),
                      DropdownMenuItem(
                        value: api.ExportBitDepth.float32,
                        child: Text('32-bit Float (Maximum)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _bitDepth = value);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Sample rate
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sample Rate',
                    style: TextStyle(
                      fontSize: 12,
                      color: ReelForgeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButton<int>(
                    value: _sampleRate,
                    isExpanded: true,
                    dropdownColor: ReelForgeTheme.bgElevated,
                    style: const TextStyle(color: ReelForgeTheme.textPrimary),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Project Rate')),
                      DropdownMenuItem(value: 44100, child: Text('44.1 kHz (CD)')),
                      DropdownMenuItem(value: 48000, child: Text('48 kHz')),
                      DropdownMenuItem(value: 96000, child: Text('96 kHz')),
                      DropdownMenuItem(value: 192000, child: Text('192 kHz')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sampleRate = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeRangeSection() {
    final hasSelection = widget.selectionStart != null && widget.selectionEnd != null;
    final hasLoop = widget.loopStart != null && widget.loopEnd != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Time Range',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: ReelForgeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _buildTimeRangeOption(
          _TimeRange.fullTimeline,
          'Full Timeline',
          '${_formatTime(widget.totalDuration)}',
        ),
        if (hasSelection)
          _buildTimeRangeOption(
            _TimeRange.selection,
            'Selection',
            '${_formatTime(widget.selectionEnd! - widget.selectionStart!)}',
          ),
        if (hasLoop)
          _buildTimeRangeOption(
            _TimeRange.loopRegion,
            'Loop Region',
            '${_formatTime(widget.loopEnd! - widget.loopStart!)}',
          ),
      ],
    );
  }

  Widget _buildTimeRangeOption(_TimeRange range, String label, String duration) {
    final isSelected = _timeRange == range;
    return InkWell(
      onTap: () => setState(() => _timeRange = range),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15) : ReelForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Text(
              duration,
              style: const TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalizeSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: _normalize,
                onChanged: (value) => setState(() => _normalize = value ?? false),
                activeColor: ReelForgeTheme.accentGreen,
              ),
              const Text(
                'Normalize Audio',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ReelForgeTheme.textPrimary,
                ),
              ),
            ],
          ),
          if (_normalize) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Target Level (dBFS)',
                    style: TextStyle(
                      fontSize: 12,
                      color: ReelForgeTheme.textSecondary,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _normalizeTarget,
                          min: -6.0,
                          max: -0.1,
                          divisions: 59,
                          label: '${_normalizeTarget.toStringAsFixed(1)} dB',
                          activeColor: ReelForgeTheme.accentGreen,
                          onChanged: (value) => setState(() => _normalizeTarget = value),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          '${_normalizeTarget.toStringAsFixed(1)} dB',
                          style: const TextStyle(color: ReelForgeTheme.textPrimary),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDb(double linear) {
    if (linear == 0) return '-∞ dB';
    final db = 20 * math.log(linear.abs().clamp(0.0001, 1.0)) / math.ln10;
    return '${db.toStringAsFixed(1)} dB';
  }
}

enum _TimeRange {
  fullTimeline,
  selection,
  loopRegion,
  custom,
}
