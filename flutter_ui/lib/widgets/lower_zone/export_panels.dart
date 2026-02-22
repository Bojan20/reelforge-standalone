/// Export Panels — Professional Audio Export UI
///
/// P2.1: Complete export functionality for DAW and SlotLab.
///
/// Features:
/// - Format/Quality selection with preview
/// - Real-time progress with ETA
/// - Stem selection for multi-track export
/// - Batch export for SlotLab events
/// - Project archive with compression options
/// - Normalization options (Peak, LUFS)

import 'dart:async';
import 'dart:convert';
import 'dart:io' as java_io;
import 'package:flutter/material.dart';
import '../../utils/safe_file_picker.dart';

import '../../providers/subsystems/composite_event_system_provider.dart';
import '../../services/export_service.dart';
import '../../services/loudness_analysis_service.dart';
import '../../services/service_locator.dart';
import '../../src/rust/native_ffi.dart';
import '../export/loudness_analysis_panel.dart';
import 'lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DAW EXPORT PANEL — Full project/selection export
// ═══════════════════════════════════════════════════════════════════════════════

class DawExportPanel extends StatefulWidget {
  final Color accentColor;
  final double? startTime;
  final double? endTime;
  final String? projectName;

  const DawExportPanel({
    super.key,
    this.accentColor = LowerZoneColors.dawAccent,
    this.startTime,
    this.endTime,
    this.projectName,
  });

  @override
  State<DawExportPanel> createState() => _DawExportPanelState();
}

class _DawExportPanelState extends State<DawExportPanel> {
  final ExportService _exportService = ExportService.instance;
  final LoudnessAnalysisService _loudnessService = LoudnessAnalysisService.instance;
  StreamSubscription<ExportProgress>? _progressSub;

  // Export settings
  ExportFormat _format = ExportFormat.wav;
  ExportSampleRate _sampleRate = ExportSampleRate.rate48000;
  ExportBitDepth _bitDepth = ExportBitDepth.bit24;
  NormalizationMode _normalization = NormalizationMode.none;
  double _normalizationTarget = -1.0;
  bool _includeTail = true;

  // State
  String? _outputPath;
  ExportProgress _progress = const ExportProgress();
  bool _isExporting = false;

  // Loudness analysis state
  LoudnessResult? _loudnessResult;
  LoudnessTarget _loudnessTarget = LoudnessTarget.streaming;
  bool _isAnalyzing = false;
  double _analysisProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _progressSub = _exportService.progressStream.listen((progress) {
      setState(() => _progress = progress);
      if (progress.isComplete || progress.wasCancelled) {
        _isExporting = false;
      }
    });
    _exportService.addListener(_onExportServiceChanged);
    _loudnessService.addListener(_onLoudnessServiceChanged);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _exportService.removeListener(_onExportServiceChanged);
    _loudnessService.removeListener(_onLoudnessServiceChanged);
    super.dispose();
  }

  void _onLoudnessServiceChanged() {
    setState(() {
      _loudnessResult = _loudnessService.lastResult;
      _isAnalyzing = _loudnessService.isAnalyzing;
      _analysisProgress = _loudnessService.progress;
    });
  }

  Future<void> _startLoudnessAnalysis() async {
    // TODO: Pass actual audio buffer from project
    // For now, simulate analysis with representative values
    setState(() => _isAnalyzing = true);
    await Future.delayed(const Duration(milliseconds: 800));

    final durationSeconds = (widget.endTime ?? 180.0) - (widget.startTime ?? 0.0);
    setState(() {
      _isAnalyzing = false;
      // Simulated result for UI demo
      _loudnessResult = LoudnessResult(
        integratedLufs: -14.2,
        shortTermLufs: -13.8,
        momentaryLufs: -12.5,
        truePeak: -0.8,
        samplePeak: -1.2,
        loudnessRange: 8.5,
        duration: Duration(milliseconds: (durationSeconds * 1000).round()),
        isValid: true,
      );
    });
  }

  void _onExportServiceChanged() {
    setState(() {
      _isExporting = _exportService.isExporting;
      _progress = _exportService.progress;
    });
  }

  Future<void> _selectOutputPath() async {
    final result = await SafeFilePicker.saveFile(context,
      dialogTitle: 'Export Audio',
      fileName: _exportService.suggestFilename(
        widget.projectName ?? 'Project',
        _format,
      ),
      allowedExtensions: [_format.extension.substring(1)],
      type: FileType.custom,
    );
    if (result != null) {
      setState(() => _outputPath = result);
    }
  }

  Future<void> _startExport() async {
    if (_outputPath == null) {
      await _selectOutputPath();
      if (_outputPath == null) return;
    }

    final config = ExportConfig(
      outputPath: _outputPath!,
      format: _format,
      sampleRate: _sampleRate,
      bitDepth: _bitDepth,
      normalization: _normalization,
      normalizationTarget: _normalizationTarget,
      startTime: widget.startTime ?? 0.0,
      endTime: widget.endTime ?? -1.0,
      includeTail: _includeTail,
    );

    setState(() => _isExporting = true);
    await _exportService.startExport(config);
  }

  void _cancelExport() {
    _exportService.cancelExport();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Settings
                Expanded(
                  flex: 3,
                  child: _buildSettings(),
                ),
                const SizedBox(width: 16),
                // Center: Preview / Progress
                Expanded(
                  flex: 2,
                  child: _isExporting ? _buildProgress() : _buildPreview(),
                ),
                const SizedBox(width: 16),
                // Right: Export button
                SizedBox(
                  width: 100,
                  child: _buildExportButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.upload, size: 16, color: widget.accentColor),
        const SizedBox(width: 8),
        Text(
          'EXPORT AUDIO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 1.0,
          ),
        ),
        const Spacer(),
        if (_outputPath != null)
          Flexible(
            child: Text(
              _outputPath!.split('/').last,
              style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Format row
          Row(
            children: [
              Expanded(child: _buildDropdown<ExportFormat>(
                'Format',
                ExportFormat.values,
                _format,
                (f) => f.label,
                (f) => setState(() => _format = f),
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildDropdown<ExportSampleRate>(
                'Sample Rate',
                ExportSampleRate.values,
                _sampleRate,
                (s) => s.label,
                (s) => setState(() => _sampleRate = s),
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Quality row
          Row(
            children: [
              Expanded(child: _buildDropdown<ExportBitDepth>(
                'Bit Depth',
                ExportBitDepth.values,
                _bitDepth,
                (b) => b.label,
                (b) => setState(() => _bitDepth = b),
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildDropdown<NormalizationMode>(
                'Normalize',
                NormalizationMode.values,
                _normalization,
                (n) => n.label,
                (n) => setState(() => _normalization = n),
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Options row
          Row(
            children: [
              if (_normalization != NormalizationMode.none)
                Expanded(child: _buildTargetSlider()),
              if (_normalization == NormalizationMode.none)
                Expanded(child: _buildToggle('Include Tail', _includeTail, (v) => setState(() => _includeTail = v))),
              const SizedBox(width: 8),
              Expanded(child: _buildOutputSelector()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    List<T> items,
    T value,
    String Function(T) labelFn,
    void Function(T) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              isExpanded: true,
              dropdownColor: LowerZoneColors.bgDeep,
              icon: Icon(Icons.arrow_drop_down, size: 14, color: widget.accentColor),
              items: items.map((item) => DropdownMenuItem(
                value: item,
                child: Text(labelFn(item), style: TextStyle(fontSize: 10, color: widget.accentColor)),
              )).toList(),
              onChanged: _isExporting ? null : (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSlider() {
    final label = _normalization == NormalizationMode.peak ? 'Peak (dB)' : 'LUFS';
    final min = _normalization == NormalizationMode.peak ? -12.0 : -24.0;
    final max = _normalization == NormalizationMode.peak ? 0.0 : -8.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              const Spacer(),
              Text(
                '${_normalizationTarget.toStringAsFixed(1)} ${_normalization == NormalizationMode.peak ? 'dB' : 'LUFS'}',
                style: TextStyle(fontSize: 9, color: widget.accentColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: widget.accentColor,
              inactiveTrackColor: LowerZoneColors.border,
              thumbColor: widget.accentColor,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _normalizationTarget,
              min: min,
              max: max,
              onChanged: _isExporting ? null : (v) => setState(() => _normalizationTarget = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: _isExporting ? null : () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: value ? widget.accentColor.withValues(alpha: 0.1) : LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? widget.accentColor : LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: value ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 10,
              color: value ? widget.accentColor : LowerZoneColors.textPrimary,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputSelector() {
    return GestureDetector(
      onTap: _isExporting ? null : _selectOutputPath,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, size: 14, color: widget.accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _outputPath?.split('/').last ?? 'Choose Location...',
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    // Calculate estimated file size
    final estimatedDuration = (widget.endTime ?? 180.0) - (widget.startTime ?? 0.0);
    final config = ExportConfig(
      outputPath: '',
      format: _format,
      sampleRate: _sampleRate,
      bitDepth: _bitDepth,
    );
    final estimatedSize = _exportService.estimateFileSize(config, estimatedDuration);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PREVIEW', style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 0.5,
          )),
          const SizedBox(height: 12),
          _buildPreviewRow('Format', '${_format.label} ${_sampleRate.label}/${_bitDepth.label}'),
          _buildPreviewRow('Duration', _formatDuration(estimatedDuration)),
          _buildPreviewRow('Est. Size', _exportService.formatFileSize(estimatedSize)),
          if (_normalization != NormalizationMode.none)
            _buildPreviewRow('Normalize', '${_normalization.label} @ ${_normalizationTarget.toStringAsFixed(1)}'),
          const SizedBox(height: 8),
          // Loudness Analysis Section
          _buildLoudnessSection(),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: widget.accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _format.description,
                    style: TextStyle(fontSize: 8, color: widget.accentColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoudnessSection() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 12, color: LowerZoneColors.textMuted),
              const SizedBox(width: 6),
              const Text(
                'LOUDNESS',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: LowerZoneColors.textMuted),
              ),
              const Spacer(),
              // Target selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgDeepest,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<LoudnessTarget>(
                    value: _loudnessTarget,
                    isDense: true,
                    dropdownColor: LowerZoneColors.bgDeep,
                    icon: Icon(Icons.arrow_drop_down, size: 12, color: widget.accentColor),
                    items: LoudnessTarget.values.where((t) => t != LoudnessTarget.custom).map((target) {
                      return DropdownMenuItem(
                        value: target,
                        child: Text(target.name, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (t) => setState(() => _loudnessTarget = t ?? LoudnessTarget.streaming),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isAnalyzing)
            // Analyzing indicator
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(widget.accentColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Analyzing... ${(_analysisProgress * 100).toInt()}%',
                  style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                ),
              ],
            )
          else if (_loudnessResult != null)
            // Show result badge
            LoudnessBadge(
              result: _loudnessResult,
              target: _loudnessTarget,
              compact: true,
            )
          else
            // Analyze button
            GestureDetector(
              onTap: _startLoudnessAnalysis,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_outlined, size: 12, color: widget.accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'Analyze Loudness',
                      style: TextStyle(fontSize: 9, color: widget.accentColor),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('EXPORTING', style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: widget.accentColor,
                letterSpacing: 0.5,
              )),
              const Spacer(),
              Text(_progress.progressPercent, style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: widget.accentColor,
              )),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _progress.progress,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.accentColor, widget.accentColor.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildProgressRow('Speed', _progress.speedFormatted),
          _buildProgressRow('ETA', _progress.etaFormatted),
          _buildProgressRow('Peak', '${_progress.peakLevel.toStringAsFixed(1)} dB'),
          const Spacer(),
          if (_progress.isComplete)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: LowerZoneColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 14, color: LowerZoneColors.success),
                  SizedBox(width: 6),
                  Text('Export Complete!', style: TextStyle(fontSize: 10, color: LowerZoneColors.success)),
                ],
              ),
            ),
          if (_progress.wasCancelled)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: LowerZoneColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel, size: 14, color: LowerZoneColors.warning),
                  SizedBox(width: 6),
                  Text('Export Cancelled', style: TextStyle(fontSize: 10, color: LowerZoneColors.warning)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    if (_isExporting) {
      return GestureDetector(
        onTap: _cancelExport,
        child: Container(
          decoration: BoxDecoration(
            color: LowerZoneColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: LowerZoneColors.error),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stop, size: 32, color: LowerZoneColors.error),
              SizedBox(height: 8),
              Text(
                'CANCEL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.error,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _startExport,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              widget.accentColor.withValues(alpha: 0.2),
              widget.accentColor.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: widget.accentColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload, size: 32, color: widget.accentColor),
            const SizedBox(height: 8),
            Text(
              'EXPORT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: widget.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 1000).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DAW STEMS PANEL — Multi-track stem export
// ═══════════════════════════════════════════════════════════════════════════════

class DawStemsPanel extends StatefulWidget {
  final Color accentColor;
  final List<StemItem> tracks;
  final List<StemItem> buses;

  const DawStemsPanel({
    super.key,
    this.accentColor = LowerZoneColors.dawAccent,
    this.tracks = const [],
    this.buses = const [],
  });

  @override
  State<DawStemsPanel> createState() => _DawStemsPanelState();
}

class StemItem {
  final int id;
  final String name;
  bool selected;

  StemItem({required this.id, required this.name, this.selected = true});
}

class _DawStemsPanelState extends State<DawStemsPanel> {
  final ExportService _exportService = ExportService.instance;

  late List<StemItem> _tracks;
  late List<StemItem> _buses;

  ExportFormat _format = ExportFormat.wav;
  ExportSampleRate _sampleRate = ExportSampleRate.rate48000;
  String? _outputDirectory;
  String _filePrefix = 'stem';
  bool _isExporting = false;
  int _exportedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _tracks = widget.tracks.isEmpty ? _getDefaultTracks() : widget.tracks;
    _buses = widget.buses.isEmpty ? _getDefaultBuses() : widget.buses;
  }

  List<StemItem> _getDefaultTracks() => [
    StemItem(id: 0, name: 'Track 1', selected: true),
    StemItem(id: 1, name: 'Track 2', selected: true),
    StemItem(id: 2, name: 'Track 3', selected: true),
    StemItem(id: 3, name: 'Track 4', selected: false),
  ];

  List<StemItem> _getDefaultBuses() => [
    StemItem(id: 0, name: 'Master', selected: true),
    StemItem(id: 1, name: 'SFX Bus', selected: true),
    StemItem(id: 2, name: 'Music Bus', selected: true),
    StemItem(id: 3, name: 'Voice Bus', selected: false),
  ];

  Future<void> _selectOutputDirectory() async {
    final result = await SafeFilePicker.getDirectoryPath(context,
      dialogTitle: 'Select Stems Output Folder',
    );
    if (result != null) {
      setState(() => _outputDirectory = result);
    }
  }

  Future<void> _startExport() async {
    if (_outputDirectory == null) {
      await _selectOutputDirectory();
      if (_outputDirectory == null) return;
    }

    final selectedTracks = _tracks.where((t) => t.selected).map((t) => t.id).toList();
    final selectedBuses = _buses.where((b) => b.selected).map((b) => b.id).toList();

    _totalCount = selectedTracks.length + selectedBuses.length;
    if (_totalCount == 0) return;

    setState(() {
      _isExporting = true;
      _exportedCount = 0;
    });

    final config = StemsExportConfig(
      outputDirectory: _outputDirectory!,
      filePrefix: _filePrefix,
      format: _format,
      sampleRate: _sampleRate,
      exportTracks: selectedTracks.isNotEmpty,
      exportBuses: selectedBuses.isNotEmpty,
      selectedTrackIds: selectedTracks,
      selectedBusIds: selectedBuses,
    );

    final result = await _exportService.exportStems(config);

    setState(() {
      _isExporting = false;
      _exportedCount = result >= 0 ? result : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Track/Bus selection
                Expanded(
                  flex: 2,
                  child: _buildStemSelection(),
                ),
                const SizedBox(width: 16),
                // Center: Settings
                Expanded(
                  flex: 2,
                  child: _buildSettings(),
                ),
                const SizedBox(width: 16),
                // Right: Export button
                SizedBox(
                  width: 100,
                  child: _buildExportButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final selectedCount = _tracks.where((t) => t.selected).length + _buses.where((b) => b.selected).length;
    return Row(
      children: [
        Icon(Icons.account_tree, size: 16, color: widget.accentColor),
        const SizedBox(width: 8),
        Text(
          'STEM EXPORT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$selectedCount items selected',
          style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildStemSelection() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectionHeader('TRACKS', _tracks),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(4),
              children: [
                ..._tracks.map((t) => _buildStemItem(t, _tracks)),
                const Divider(height: 16, color: LowerZoneColors.border),
                _buildSelectionHeader('BUSES', _buses),
                ..._buses.map((b) => _buildStemItem(b, _buses)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader(String label, List<StemItem> items) {
    final allSelected = items.every((i) => i.selected);
    final noneSelected = items.every((i) => !i.selected);

    return GestureDetector(
      onTap: () {
        setState(() {
          final newState = !allSelected;
          for (final item in items) {
            item.selected = newState;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgMid,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              allSelected ? Icons.check_box : (noneSelected ? Icons.check_box_outline_blank : Icons.indeterminate_check_box),
              size: 14,
              color: widget.accentColor,
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: widget.accentColor,
              letterSpacing: 0.5,
            )),
            const Spacer(),
            Text('${items.where((i) => i.selected).length}/${items.length}',
              style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildStemItem(StemItem item, List<StemItem> list) {
    return GestureDetector(
      onTap: () => setState(() => item.selected = !item.selected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: item.selected ? widget.accentColor.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Icon(
              item.selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 12,
              color: item.selected ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(item.name, style: TextStyle(
              fontSize: 10,
              color: item.selected ? LowerZoneColors.textPrimary : LowerZoneColors.textMuted,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildDropdown<ExportFormat>(
              'Format',
              ExportFormat.values,
              _format,
              (f) => f.label,
              (f) => setState(() => _format = f),
            )),
            const SizedBox(width: 8),
            Expanded(child: _buildDropdown<ExportSampleRate>(
              'Sample Rate',
              ExportSampleRate.values,
              _sampleRate,
              (s) => s.label,
              (s) => setState(() => _sampleRate = s),
            )),
          ],
        ),
        const SizedBox(height: 8),
        _buildPrefixInput(),
        const SizedBox(height: 8),
        _buildDirectorySelector(),
        const Spacer(),
        if (_exportedCount > 0)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LowerZoneColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 14, color: LowerZoneColors.success),
                const SizedBox(width: 6),
                Text('$_exportedCount stems exported', style: const TextStyle(fontSize: 10, color: LowerZoneColors.success)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDropdown<T>(
    String label,
    List<T> items,
    T value,
    String Function(T) labelFn,
    void Function(T) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              isExpanded: true,
              dropdownColor: LowerZoneColors.bgDeep,
              icon: Icon(Icons.arrow_drop_down, size: 14, color: widget.accentColor),
              items: items.map((item) => DropdownMenuItem(
                value: item,
                child: Text(labelFn(item), style: TextStyle(fontSize: 10, color: widget.accentColor)),
              )).toList(),
              onChanged: _isExporting ? null : (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrefixInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('File Prefix', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          TextField(
            controller: TextEditingController(text: _filePrefix),
            style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) => _filePrefix = v,
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorySelector() {
    return GestureDetector(
      onTap: _isExporting ? null : _selectOutputDirectory,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, size: 14, color: widget.accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _outputDirectory?.split('/').last ?? 'Choose Folder...',
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return GestureDetector(
      onTap: _isExporting ? null : _startExport,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _isExporting ? [
              LowerZoneColors.bgMid,
              LowerZoneColors.bgDeepest,
            ] : [
              widget.accentColor.withValues(alpha: 0.2),
              widget.accentColor.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _isExporting ? LowerZoneColors.border : widget.accentColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isExporting)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.account_tree, size: 32, color: widget.accentColor),
            const SizedBox(height: 8),
            Text(
              _isExporting ? 'EXPORTING...' : 'STEMS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isExporting ? LowerZoneColors.textMuted : widget.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DAW BOUNCE PANEL — Realtime bounce with progress
// ═══════════════════════════════════════════════════════════════════════════════

class DawBouncePanel extends StatefulWidget {
  final Color accentColor;
  final double? projectLength;
  final String? projectName;

  const DawBouncePanel({
    super.key,
    this.accentColor = LowerZoneColors.dawAccent,
    this.projectLength,
    this.projectName,
  });

  @override
  State<DawBouncePanel> createState() => _DawBouncePanelState();
}

class _DawBouncePanelState extends State<DawBouncePanel> {
  final ExportService _exportService = ExportService.instance;
  StreamSubscription<ExportProgress>? _progressSub;

  ExportFormat _format = ExportFormat.wav;
  double _tailSeconds = 2.0;
  String? _outputPath;
  ExportProgress _progress = const ExportProgress();
  bool _isBouncing = false;

  @override
  void initState() {
    super.initState();
    _progressSub = _exportService.progressStream.listen((progress) {
      setState(() => _progress = progress);
      if (progress.isComplete || progress.wasCancelled) {
        _isBouncing = false;
      }
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _selectOutputPath() async {
    final result = await SafeFilePicker.saveFile(context,
      dialogTitle: 'Bounce Audio',
      fileName: _exportService.suggestFilename(
        widget.projectName ?? 'Bounce',
        _format,
      ),
    );
    if (result != null) {
      setState(() => _outputPath = result);
    }
  }

  Future<void> _startBounce() async {
    if (_outputPath == null) {
      await _selectOutputPath();
      if (_outputPath == null) return;
    }

    final length = widget.projectLength ?? 180.0;

    setState(() => _isBouncing = true);

    await _exportService.exportAudio(
      outputPath: _outputPath!,
      format: _format,
      startTime: 0.0,
      endTime: length + _tailSeconds,
    );
  }

  void _cancelBounce() {
    _exportService.cancelExport();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Settings
                Expanded(
                  flex: 2,
                  child: _buildSettings(),
                ),
                const SizedBox(width: 16),
                // Center: Progress/Status
                Expanded(
                  flex: 2,
                  child: _buildStatusPanel(),
                ),
                const SizedBox(width: 16),
                // Right: Bounce button
                SizedBox(
                  width: 100,
                  child: _buildBounceButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.speed, size: 16, color: LowerZoneColors.success),
        const SizedBox(width: 8),
        const Text(
          'REALTIME BOUNCE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.success,
            letterSpacing: 1.0,
          ),
        ),
        const Spacer(),
        Text(
          'Master Output',
          style: TextStyle(fontSize: 9, color: widget.accentColor),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    final projectLength = widget.projectLength ?? 180.0;
    final totalLength = projectLength + _tailSeconds;

    return Column(
      children: [
        _buildInfoRow('Source', 'Master Output'),
        _buildInfoRow('Length', _formatDuration(projectLength)),
        const SizedBox(height: 8),
        _buildTailSlider(),
        _buildInfoRow('Total', _formatDuration(totalLength)),
        const SizedBox(height: 8),
        _buildFormatSelector(),
        const Spacer(),
        _buildOutputSelector(),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTailSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Tail', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              const Spacer(),
              Text('${_tailSeconds.toStringAsFixed(1)} sec', style: const TextStyle(fontSize: 9, color: LowerZoneColors.textPrimary)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: LowerZoneColors.success,
              inactiveTrackColor: LowerZoneColors.border,
              thumbColor: LowerZoneColors.success,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _tailSeconds,
              min: 0,
              max: 10,
              onChanged: _isBouncing ? null : (v) => setState(() => _tailSeconds = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: ExportFormat.values.map((f) => Expanded(
          child: GestureDetector(
            onTap: _isBouncing ? null : () => setState(() => _format = f),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: _format == f ? LowerZoneColors.success.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: _format == f ? FontWeight.bold : FontWeight.normal,
                    color: _format == f ? LowerZoneColors.success : LowerZoneColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildOutputSelector() {
    return GestureDetector(
      onTap: _isBouncing ? null : _selectOutputPath,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, size: 14, color: LowerZoneColors.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _outputPath?.split('/').last ?? 'Choose Location...',
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel() {
    if (!_isBouncing && !_progress.isComplete && !_progress.wasCancelled) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_outline, size: 48, color: LowerZoneColors.textMuted),
            SizedBox(height: 12),
            Text('Ready to Bounce', style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted)),
            SizedBox(height: 4),
            Text(
              'Bouncing plays the project in realtime\nand captures the audio output',
              style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _isBouncing ? LowerZoneColors.success : LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_isBouncing) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('RECORDING', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
              ] else if (_progress.isComplete) ...[
                const Icon(Icons.check_circle, size: 14, color: LowerZoneColors.success),
                const SizedBox(width: 6),
                const Text('COMPLETE', style: TextStyle(fontSize: 10, color: LowerZoneColors.success, fontWeight: FontWeight.bold)),
              ] else ...[
                const Icon(Icons.cancel, size: 14, color: LowerZoneColors.warning),
                const SizedBox(width: 6),
                const Text('CANCELLED', style: TextStyle(fontSize: 10, color: LowerZoneColors.warning, fontWeight: FontWeight.bold)),
              ],
              const Spacer(),
              Text(_progress.progressPercent, style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _isBouncing ? LowerZoneColors.success : LowerZoneColors.textPrimary,
              )),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _progress.progress,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [LowerZoneColors.success, LowerZoneColors.success.withValues(alpha: 0.7)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildProgressRow('Speed', _progress.speedFormatted),
          _buildProgressRow('ETA', _progress.etaFormatted),
          _buildProgressRow('Peak', '${_progress.peakLevel.toStringAsFixed(1)} dB'),
          const Spacer(),
          // Peak meter visualization
          _buildPeakMeter(),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildPeakMeter() {
    final peak = _progress.peakLevel;
    final normalized = ((peak + 60) / 60).clamp(0.0, 1.0);
    final isClipping = peak > -0.5;

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: normalized,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isClipping
                  ? [Colors.red, Colors.red]
                  : [Colors.green, Colors.yellow, Colors.orange],
              stops: isClipping ? null : const [0.0, 0.7, 1.0],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildBounceButton() {
    if (_isBouncing) {
      return GestureDetector(
        onTap: _cancelBounce,
        child: Container(
          decoration: BoxDecoration(
            color: LowerZoneColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: LowerZoneColors.error),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stop, size: 32, color: LowerZoneColors.error),
              SizedBox(height: 8),
              Text('STOP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LowerZoneColors.error)),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _startBounce,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              LowerZoneColors.success.withValues(alpha: 0.3),
              LowerZoneColors.success.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.success),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle, size: 32, color: LowerZoneColors.success),
            SizedBox(height: 8),
            Text('BOUNCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: LowerZoneColors.success)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 1000).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SLOTLAB BATCH EXPORT PANEL — Event batch export
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// P4.1: SLOTLAB EVENT DATA EXPORT PANEL — JSON/XML Event Definitions Export
// ═══════════════════════════════════════════════════════════════════════════════

/// Export format for event data
enum EventDataExportFormat {
  json('JSON', '.json', 'Structured JSON format, human-readable'),
  xml('XML', '.xml', 'XML format for game engine integration'),
  jsonMinified('JSON (Minified)', '.json', 'Compact JSON for production');

  final String label;
  final String extension;
  final String description;

  const EventDataExportFormat(this.label, this.extension, this.description);
}

/// What to include in the export
enum EventDataExportScope {
  all('All Events', 'Export all events'),
  selected('Selected Events', 'Export only selected events'),
  byStage('By Stage', 'Export events grouped by stage');

  final String label;
  final String description;

  const EventDataExportScope(this.label, this.description);
}

class SlotLabEventDataExportPanel extends StatefulWidget {
  final Color accentColor;
  final List<SlotLabEventItem> events;

  const SlotLabEventDataExportPanel({
    super.key,
    this.accentColor = LowerZoneColors.slotLabAccent,
    this.events = const [],
  });

  @override
  State<SlotLabEventDataExportPanel> createState() => _SlotLabEventDataExportPanelState();
}

class _SlotLabEventDataExportPanelState extends State<SlotLabEventDataExportPanel> {
  late List<SlotLabEventItem> _events;

  // Export settings
  EventDataExportFormat _format = EventDataExportFormat.json;
  EventDataExportScope _scope = EventDataExportScope.all;
  bool _includeMetadata = true;
  bool _includeLayers = true;
  bool _includeAudioPaths = true;
  bool _includeTimestamps = false;

  // State
  String? _outputPath;
  bool _isExporting = false;
  String? _lastExportPath;
  int _exportedCount = 0;

  @override
  void initState() {
    super.initState();
    _events = widget.events.isEmpty ? _getDefaultEvents() : widget.events;
  }

  List<SlotLabEventItem> _getDefaultEvents() => [
    SlotLabEventItem(id: '1', name: 'SPIN_START', stage: 'SPIN_START', selected: true),
    SlotLabEventItem(id: '2', name: 'REEL_SPIN', stage: 'REEL_SPIN', selected: true),
    SlotLabEventItem(id: '3', name: 'REEL_STOP', stage: 'REEL_STOP', selected: true),
    SlotLabEventItem(id: '4', name: 'WIN_SMALL', stage: 'WIN_SMALL', selected: true),
    SlotLabEventItem(id: '5', name: 'WIN_BIG', stage: 'WIN_BIG', selected: false),
  ];

  Future<void> _selectOutputPath() async {
    final result = await SafeFilePicker.saveFile(context,
      dialogTitle: 'Export Event Data',
      fileName: 'events${_format.extension}',
      allowedExtensions: [_format.extension.substring(1)],
      type: FileType.custom,
    );
    if (result != null) {
      setState(() => _outputPath = result);
    }
  }

  Future<void> _startExport() async {
    if (_outputPath == null) {
      await _selectOutputPath();
      if (_outputPath == null) return;
    }

    setState(() => _isExporting = true);

    try {
      final eventsToExport = _scope == EventDataExportScope.selected
          ? _events.where((e) => e.selected).toList()
          : _events;

      final exportData = _buildExportData(eventsToExport);
      final content = _format == EventDataExportFormat.xml
          ? _toXml(exportData)
          : _toJson(exportData, minified: _format == EventDataExportFormat.jsonMinified);

      // Write file
      final file = java_io.File(_outputPath!);
      await file.writeAsString(content);

      setState(() {
        _isExporting = false;
        _lastExportPath = _outputPath;
        _exportedCount = eventsToExport.length;
      });
    } catch (e) {
      setState(() => _isExporting = false);
    }
  }

  Map<String, dynamic> _buildExportData(List<SlotLabEventItem> events) {
    final data = <String, dynamic>{
      'version': '1.0',
      'exportedAt': _includeTimestamps ? DateTime.now().toIso8601String() : null,
      'format': _format.label,
      'events': events.map((e) => _eventToMap(e)).toList(),
    };

    if (_includeMetadata) {
      data['metadata'] = {
        'totalEvents': events.length,
        'stages': events.map((e) => e.stage).toSet().toList(),
      };
    }

    // Remove null values
    data.removeWhere((key, value) => value == null);
    return data;
  }

  Map<String, dynamic> _eventToMap(SlotLabEventItem event) {
    final map = <String, dynamic>{
      'id': event.id,
      'name': event.name,
      'stage': event.stage,
    };

    if (_includeLayers) {
      // Placeholder for layers data - would come from provider in real implementation
      map['layers'] = <Map<String, dynamic>>[];
    }

    if (_includeAudioPaths) {
      // Placeholder for audio paths - would come from provider in real implementation
      map['audioPaths'] = <String>[];
    }

    return map;
  }

  String _toJson(Map<String, dynamic> data, {bool minified = false}) {
    if (minified) {
      return jsonEncode(data);
    }
    final encoder = const JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  String _toXml(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<EventExport version="${data['version']}">');

    if (data['metadata'] != null) {
      buffer.writeln('  <Metadata>');
      final meta = data['metadata'] as Map<String, dynamic>;
      buffer.writeln('    <TotalEvents>${meta['totalEvents']}</TotalEvents>');
      buffer.writeln('    <Stages>');
      for (final stage in (meta['stages'] as List)) {
        buffer.writeln('      <Stage>$stage</Stage>');
      }
      buffer.writeln('    </Stages>');
      buffer.writeln('  </Metadata>');
    }

    buffer.writeln('  <Events>');
    for (final event in (data['events'] as List)) {
      final e = event as Map<String, dynamic>;
      buffer.writeln('    <Event id="${e['id']}">');
      buffer.writeln('      <Name>${e['name']}</Name>');
      buffer.writeln('      <Stage>${e['stage']}</Stage>');
      if (e['layers'] != null) {
        buffer.writeln('      <Layers/>');
      }
      if (e['audioPaths'] != null) {
        buffer.writeln('      <AudioPaths/>');
      }
      buffer.writeln('    </Event>');
    }
    buffer.writeln('  </Events>');
    buffer.writeln('</EventExport>');

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Event selection
                Expanded(
                  flex: 2,
                  child: _buildEventSelection(),
                ),
                const SizedBox(width: 16),
                // Center: Settings
                Expanded(
                  flex: 2,
                  child: _buildSettings(),
                ),
                const SizedBox(width: 16),
                // Right: Export button + Preview
                SizedBox(
                  width: 120,
                  child: _buildExportSection(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final selectedCount = _events.where((e) => e.selected).length;
    final exportCount = _scope == EventDataExportScope.selected ? selectedCount : _events.length;

    return Row(
      children: [
        Icon(Icons.code, size: 16, color: widget.accentColor),
        const SizedBox(width: 8),
        Text(
          'EVENT DATA EXPORT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: widget.accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _format.label,
            style: TextStyle(fontSize: 8, color: widget.accentColor, fontWeight: FontWeight.bold),
          ),
        ),
        const Spacer(),
        Text(
          '$exportCount events',
          style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildEventSelection() {
    final allSelected = _events.every((e) => e.selected);

    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                final newState = !allSelected;
                for (final event in _events) {
                  event.selected = newState;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: LowerZoneColors.bgMid,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: widget.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text('EVENTS', style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                    letterSpacing: 0.5,
                  )),
                  const Spacer(),
                  Text('${_events.where((e) => e.selected).length}/${_events.length}',
                    style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(4),
              children: _events.map((e) => _buildEventItem(e)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(SlotLabEventItem event) {
    return GestureDetector(
      onTap: () => setState(() => event.selected = !event.selected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: event.selected ? widget.accentColor.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Icon(
              event.selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 12,
              color: event.selected ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(event.name, style: TextStyle(
                fontSize: 10,
                color: event.selected ? LowerZoneColors.textPrimary : LowerZoneColors.textMuted,
              )),
            ),
            Text(event.stage, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Format selection
          _buildDropdown<EventDataExportFormat>(
            'Format',
            EventDataExportFormat.values,
            _format,
            (f) => f.label,
            (f) => setState(() => _format = f),
          ),
          const SizedBox(height: 8),

          // Scope selection
          _buildDropdown<EventDataExportScope>(
            'Scope',
            EventDataExportScope.values,
            _scope,
            (s) => s.label,
            (s) => setState(() => _scope = s),
          ),
          const SizedBox(height: 8),

          // Options
          Text('INCLUDE', style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 0.5,
          )),
          const SizedBox(height: 4),
          _buildToggle('Metadata', _includeMetadata, (v) => setState(() => _includeMetadata = v)),
          _buildToggle('Layers', _includeLayers, (v) => setState(() => _includeLayers = v)),
          _buildToggle('Audio Paths', _includeAudioPaths, (v) => setState(() => _includeAudioPaths = v)),
          _buildToggle('Timestamps', _includeTimestamps, (v) => setState(() => _includeTimestamps = v)),

          const SizedBox(height: 8),
          _buildOutputSelector(),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    List<T> items,
    T value,
    String Function(T) labelFn,
    void Function(T) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              isExpanded: true,
              dropdownColor: LowerZoneColors.bgDeep,
              icon: Icon(Icons.arrow_drop_down, size: 14, color: widget.accentColor),
              items: items.map((item) => DropdownMenuItem(
                value: item,
                child: Text(labelFn(item), style: TextStyle(fontSize: 10, color: widget.accentColor)),
              )).toList(),
              onChanged: _isExporting ? null : (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: _isExporting ? null : () => onChanged(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: value ? widget.accentColor.withValues(alpha: 0.1) : LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? widget.accentColor.withValues(alpha: 0.5) : LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 12,
              color: value ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 9,
              color: value ? widget.accentColor : LowerZoneColors.textPrimary,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputSelector() {
    return GestureDetector(
      onTap: _isExporting ? null : _selectOutputPath,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, size: 14, color: widget.accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _outputPath?.split('/').last ?? 'Choose Location...',
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportSection() {
    return Column(
      children: [
        // Format info
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: LowerZoneColors.bgDeepest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: LowerZoneColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FORMAT', style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: widget.accentColor,
              )),
              const SizedBox(height: 4),
              Text(
                _format.description,
                style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Export button
        Expanded(child: _buildExportButton()),

        // Success message
        if (_lastExportPath != null && _exportedCount > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: LowerZoneColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, size: 14, color: LowerZoneColors.success),
                const SizedBox(height: 4),
                Text(
                  '$_exportedCount events',
                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.success),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExportButton() {
    return GestureDetector(
      onTap: _isExporting ? null : _startExport,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _isExporting ? [
              LowerZoneColors.bgMid,
              LowerZoneColors.bgDeepest,
            ] : [
              widget.accentColor.withValues(alpha: 0.2),
              widget.accentColor.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _isExporting ? LowerZoneColors.border : widget.accentColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isExporting)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(widget.accentColor),
                ),
              )
            else
              Icon(Icons.code, size: 32, color: widget.accentColor),
            const SizedBox(height: 8),
            Text(
              _isExporting ? 'EXPORTING...' : 'EXPORT\n${_format.label.toUpperCase()}',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: _isExporting ? LowerZoneColors.textMuted : widget.accentColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SLOTLAB BATCH EXPORT PANEL — Event batch export (audio files)
// ═══════════════════════════════════════════════════════════════════════════════

class SlotLabBatchExportPanel extends StatefulWidget {
  final Color accentColor;
  final List<SlotLabEventItem> events;

  const SlotLabBatchExportPanel({
    super.key,
    this.accentColor = LowerZoneColors.slotLabAccent,
    this.events = const [],
  });

  @override
  State<SlotLabBatchExportPanel> createState() => _SlotLabBatchExportPanelState();
}

class SlotLabEventItem {
  final String id;
  final String name;
  final String stage;
  bool selected;

  SlotLabEventItem({
    required this.id,
    required this.name,
    required this.stage,
    this.selected = true,
  });
}

class _SlotLabBatchExportPanelState extends State<SlotLabBatchExportPanel> {
  final ExportService _exportService = ExportService.instance;

  late List<SlotLabEventItem> _events;
  ExportFormat _format = ExportFormat.wav;
  ExportSampleRate _sampleRate = ExportSampleRate.rate48000;
  NormalizationMode _normalization = NormalizationMode.peak;
  double _normalizationTarget = -1.0;
  bool _includeVariations = false;
  int _variationCount = 4;
  String? _outputDirectory;
  bool _isExporting = false;
  int _exportedCount = 0;

  @override
  void initState() {
    super.initState();
    _events = widget.events.isEmpty ? _getDefaultEvents() : widget.events;
  }

  List<SlotLabEventItem> _getDefaultEvents() => [
    SlotLabEventItem(id: '1', name: 'SPIN_START', stage: 'SPIN_START', selected: true),
    SlotLabEventItem(id: '2', name: 'REEL_SPIN', stage: 'REEL_SPIN', selected: true),
    SlotLabEventItem(id: '3', name: 'REEL_STOP', stage: 'REEL_STOP', selected: true),
    SlotLabEventItem(id: '4', name: 'WIN_SMALL', stage: 'WIN_SMALL', selected: true),
    SlotLabEventItem(id: '5', name: 'WIN_BIG', stage: 'WIN_BIG', selected: false),
  ];

  Future<void> _selectOutputDirectory() async {
    final result = await SafeFilePicker.getDirectoryPath(context,
      dialogTitle: 'Select Export Folder',
    );
    if (result != null) {
      setState(() => _outputDirectory = result);
    }
  }

  Future<void> _startExport() async {
    if (_outputDirectory == null) {
      await _selectOutputDirectory();
      if (_outputDirectory == null) return;
    }

    final selectedEvents = _events.where((e) => e.selected).toList();
    if (selectedEvents.isEmpty) return;

    setState(() {
      _isExporting = true;
      _exportedCount = 0;
    });

    final config = SlotLabBatchExportConfig(
      outputDirectory: _outputDirectory!,
      format: _format,
      sampleRate: _sampleRate,
      normalization: _normalization,
      normalizationTarget: _normalizationTarget,
      eventIds: selectedEvents.map((e) => e.id).toList(),
      includeVariations: _includeVariations,
      variationCount: _variationCount,
    );

    final results = await _exportService.exportSlotLabEvents(config);

    setState(() {
      _isExporting = false;
      _exportedCount = results.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Event selection
                Expanded(
                  flex: 2,
                  child: _buildEventSelection(),
                ),
                const SizedBox(width: 16),
                // Center: Settings
                Expanded(
                  flex: 2,
                  child: _buildSettings(),
                ),
                const SizedBox(width: 16),
                // Right: Export button
                SizedBox(
                  width: 100,
                  child: _buildExportButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final selectedCount = _events.where((e) => e.selected).length;
    final totalEvents = _includeVariations ? selectedCount * _variationCount : selectedCount;

    return Row(
      children: [
        Icon(Icons.upload, size: 16, color: widget.accentColor),
        const SizedBox(width: 8),
        Text(
          'BATCH EXPORT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$totalEvents files to export',
          style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildEventSelection() {
    final allSelected = _events.every((e) => e.selected);

    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                final newState = !allSelected;
                for (final event in _events) {
                  event.selected = newState;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: LowerZoneColors.bgMid,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: widget.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text('EVENTS', style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                    letterSpacing: 0.5,
                  )),
                  const Spacer(),
                  Text('${_events.where((e) => e.selected).length}/${_events.length}',
                    style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(4),
              children: _events.map((e) => _buildEventItem(e)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(SlotLabEventItem event) {
    return GestureDetector(
      onTap: () => setState(() => event.selected = !event.selected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: event.selected ? widget.accentColor.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Icon(
              event.selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 12,
              color: event.selected ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(event.name, style: TextStyle(
                fontSize: 10,
                color: event.selected ? LowerZoneColors.textPrimary : LowerZoneColors.textMuted,
              )),
            ),
            Text(event.stage, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildDropdown<ExportFormat>(
                'Format',
                ExportFormat.values,
                _format,
                (f) => f.label,
                (f) => setState(() => _format = f),
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildDropdown<ExportSampleRate>(
                'Sample Rate',
                ExportSampleRate.values,
                _sampleRate,
                (s) => s.label,
                (s) => setState(() => _sampleRate = s),
              )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildDropdown<NormalizationMode>(
                'Normalize',
                NormalizationMode.values,
                _normalization,
                (n) => n.label,
                (n) => setState(() => _normalization = n),
              )),
              const SizedBox(width: 8),
              if (_normalization != NormalizationMode.none)
                Expanded(child: _buildTargetInput()),
            ],
          ),
          const SizedBox(height: 8),
          _buildVariationsToggle(),
          if (_includeVariations) ...[
            const SizedBox(height: 8),
            _buildVariationCountSlider(),
          ],
          const SizedBox(height: 8),
          _buildDirectorySelector(),
          if (_exportedCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: LowerZoneColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: LowerZoneColors.success),
                  const SizedBox(width: 6),
                  Text('$_exportedCount events exported', style: const TextStyle(fontSize: 10, color: LowerZoneColors.success)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    List<T> items,
    T value,
    String Function(T) labelFn,
    void Function(T) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              isExpanded: true,
              dropdownColor: LowerZoneColors.bgDeep,
              icon: Icon(Icons.arrow_drop_down, size: 14, color: widget.accentColor),
              items: items.map((item) => DropdownMenuItem(
                value: item,
                child: Text(labelFn(item), style: TextStyle(fontSize: 10, color: widget.accentColor)),
              )).toList(),
              onChanged: _isExporting ? null : (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          const Text('Target', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(
            '${_normalizationTarget.toStringAsFixed(1)} dB',
            style: TextStyle(fontSize: 10, color: widget.accentColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildVariationsToggle() {
    return GestureDetector(
      onTap: _isExporting ? null : () => setState(() => _includeVariations = !_includeVariations),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _includeVariations ? widget.accentColor.withValues(alpha: 0.1) : LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _includeVariations ? widget.accentColor : LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(
              _includeVariations ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: _includeVariations ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text('Include Variations', style: TextStyle(
              fontSize: 10,
              color: _includeVariations ? widget.accentColor : LowerZoneColors.textPrimary,
            )),
            const Spacer(),
            if (_includeVariations)
              Text('×$_variationCount', style: TextStyle(fontSize: 10, color: widget.accentColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildVariationCountSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Variations', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              const Spacer(),
              Text('$_variationCount', style: TextStyle(fontSize: 10, color: widget.accentColor, fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: widget.accentColor,
              inactiveTrackColor: LowerZoneColors.border,
              thumbColor: widget.accentColor,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _variationCount.toDouble(),
              min: 2,
              max: 16,
              divisions: 7,
              onChanged: _isExporting ? null : (v) => setState(() => _variationCount = v.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorySelector() {
    return GestureDetector(
      onTap: _isExporting ? null : _selectOutputDirectory,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, size: 14, color: widget.accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _outputDirectory?.split('/').last ?? 'Choose Folder...',
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return GestureDetector(
      onTap: _isExporting ? null : _startExport,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _isExporting ? [
              LowerZoneColors.bgMid,
              LowerZoneColors.bgDeepest,
            ] : [
              widget.accentColor.withValues(alpha: 0.2),
              widget.accentColor.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _isExporting ? LowerZoneColors.border : widget.accentColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isExporting)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(widget.accentColor),
                ),
              )
            else
              Icon(Icons.upload, size: 32, color: widget.accentColor),
            const SizedBox(height: 8),
            Text(
              _isExporting ? 'EXPORTING...' : 'EXPORT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isExporting ? LowerZoneColors.textMuted : widget.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P4.2: SLOTLAB AUDIO PACK EXPORT PANEL — Structured Audio Package Export
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio format for pack export
enum AudioPackFormat {
  wav16('WAV 16-bit', '.wav', 'Uncompressed PCM, 16-bit'),
  wav24('WAV 24-bit', '.wav', 'Uncompressed PCM, 24-bit'),
  wav32f('WAV 32-bit Float', '.wav', 'Uncompressed PCM, 32-bit float'),
  mp3High('MP3 High (320kbps)', '.mp3', 'Compressed audio, high quality'),
  mp3Med('MP3 Medium (192kbps)', '.mp3', 'Compressed audio, medium quality'),
  mp3Low('MP3 Low (128kbps)', '.mp3', 'Compressed audio, smaller size'),
  oggHigh('OGG High (Q8)', '.ogg', 'Open format, high quality'),
  oggMed('OGG Medium (Q5)', '.ogg', 'Open format, medium quality'),
  oggLow('OGG Low (Q2)', '.ogg', 'Open format, smaller size');

  final String label;
  final String extension;
  final String description;

  const AudioPackFormat(this.label, this.extension, this.description);
}

/// Folder structure options
enum AudioPackStructure {
  flat('Flat', 'All files in one folder'),
  byStage('By Stage', 'Organize by stage name'),
  byCategory('By Category', 'Organize by event category'),
  byBus('By Bus', 'Organize by audio bus routing');

  final String label;
  final String description;

  const AudioPackStructure(this.label, this.description);
}

class SlotLabAudioPackExportPanel extends StatefulWidget {
  final Color accentColor;
  final List<SlotLabEventItem> events;
  final String? projectName;

  const SlotLabAudioPackExportPanel({
    super.key,
    this.accentColor = LowerZoneColors.slotLabAccent,
    this.events = const [],
    this.projectName,
  });

  @override
  State<SlotLabAudioPackExportPanel> createState() => _SlotLabAudioPackExportPanelState();
}

class _SlotLabAudioPackExportPanelState extends State<SlotLabAudioPackExportPanel> {
  final ExportService _exportService = ExportService.instance;

  late List<SlotLabEventItem> _events;

  // Export settings
  AudioPackFormat _format = AudioPackFormat.wav24;
  AudioPackStructure _structure = AudioPackStructure.byStage;
  NormalizationMode _normalization = NormalizationMode.peak;
  double _normalizationTarget = -1.0;
  bool _includeManifest = true;
  bool _createZip = false;
  String _packName = 'audio_pack';

  // State
  String? _outputDirectory;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';
  int _exportedCount = 0;
  String? _lastExportPath;

  @override
  void initState() {
    super.initState();
    _events = widget.events.isEmpty ? _getDefaultEvents() : widget.events;
    _packName = widget.projectName ?? 'audio_pack';
  }

  List<SlotLabEventItem> _getDefaultEvents() => [
    SlotLabEventItem(id: '1', name: 'SPIN_START', stage: 'SPIN_START', selected: true),
    SlotLabEventItem(id: '2', name: 'REEL_SPIN', stage: 'REEL_SPIN', selected: true),
    SlotLabEventItem(id: '3', name: 'REEL_STOP', stage: 'REEL_STOP', selected: true),
    SlotLabEventItem(id: '4', name: 'WIN_SMALL', stage: 'WIN_SMALL', selected: true),
    SlotLabEventItem(id: '5', name: 'WIN_BIG', stage: 'WIN_BIG', selected: false),
  ];

  Future<void> _selectOutputDirectory() async {
    final result = await SafeFilePicker.getDirectoryPath(context,
      dialogTitle: 'Select Audio Pack Output Folder',
    );
    if (result != null) {
      setState(() => _outputDirectory = result);
    }
  }

  Future<void> _startExport() async {
    if (_outputDirectory == null) {
      await _selectOutputDirectory();
      if (_outputDirectory == null) return;
    }

    final selectedEvents = _events.where((e) => e.selected).toList();
    if (selectedEvents.isEmpty) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportStatus = 'Preparing...';
      _exportedCount = 0;
    });

    try {
      // Create pack directory
      final packDir = java_io.Directory('$_outputDirectory/$_packName');
      if (!await packDir.exists()) {
        await packDir.create(recursive: true);
      }

      // Create subdirectories based on structure
      if (_structure != AudioPackStructure.flat) {
        final subDirs = _getSubDirectories(selectedEvents);
        for (final subDir in subDirs) {
          final dir = java_io.Directory('${packDir.path}/$subDir');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        }
      }

      // Export manifest if enabled
      if (_includeManifest) {
        setState(() => _exportStatus = 'Creating manifest...');
        await _createManifest(packDir.path, selectedEvents);
      }

      // Export audio files via offline pipeline
      final compositeProvider = sl<CompositeEventSystemProvider>();
      final ffi = sl<NativeFFI>();
      int exported = 0;
      int failed = 0;

      for (final event in selectedEvents) {
        if (!mounted) break;
        setState(() {
          _exportProgress = exported / selectedEvents.length;
          _exportStatus = 'Exporting ${event.name}...';
        });

        // Find composite event matching this stage
        final compositeEvents = compositeProvider.getEventsForStage(event.stage);
        if (compositeEvents.isEmpty) {
          failed++;
          exported++;
          continue;
        }

        final composite = compositeEvents.first;
        final validLayers = composite.layers.where((l) => l.audioPath.isNotEmpty).toList();
        if (validLayers.isEmpty) {
          failed++;
          exported++;
          continue;
        }

        // Determine output subdirectory based on structure
        final subDir = _structure != AudioPackStructure.flat
            ? _getSubDirForEvent(event)
            : '';
        final outputDir = subDir.isNotEmpty
            ? '${packDir.path}/$subDir'
            : packDir.path;

        // Process primary layer through offline pipeline
        final primaryLayer = validLayers.first;
        final safeName = event.name
            .replaceAll(RegExp(r'[^\w\-.]'), '_')
            .replaceAll(RegExp(r'_+'), '_');
        final outputPath = '$outputDir/$safeName${_format.extension}';

        final sourceFile = java_io.File(primaryLayer.audioPath);
        if (await sourceFile.exists()) {
          final handle = ffi.offlinePipelineCreate();
          if (handle >= 0) {
            try {
              ffi.offlinePipelineSetFormat(handle, _formatToCode(_format));
              final result = ffi.offlineProcessFile(handle, primaryLayer.audioPath, outputPath);
              if (result != 0) failed++;
            } finally {
              ffi.offlinePipelineDestroy(handle);
            }
          } else {
            // FFI not available — copy source file as fallback
            await sourceFile.copy(outputPath);
          }
        } else {
          failed++;
        }

        exported++;
      }

      // Create ZIP if enabled
      if (_createZip && mounted) {
        setState(() {
          _exportProgress = 0.95;
          _exportStatus = 'Creating ZIP archive...';
        });
        // ZIP creation via dart:io Process (zip command)
        try {
          final zipPath = '${packDir.path}.zip';
          await java_io.Process.run('zip', ['-r', zipPath, packDir.path]);
        } catch (_) {
          // ZIP creation optional — don't fail export
        }
      }

      setState(() {
        _isExporting = false;
        _exportProgress = 1.0;
        _exportStatus = 'Complete!';
        _exportedCount = selectedEvents.length;
        _lastExportPath = packDir.path;
      });
    } catch (e) {
      setState(() {
        _isExporting = false;
        _exportStatus = 'Error: $e';
      });
    }
  }

  Set<String> _getSubDirectories(List<SlotLabEventItem> events) {
    switch (_structure) {
      case AudioPackStructure.flat:
        return {};
      case AudioPackStructure.byStage:
        return events.map((e) => e.stage).toSet();
      case AudioPackStructure.byCategory:
        return events.map((e) => _categorizeStage(e.stage)).toSet();
      case AudioPackStructure.byBus:
        return {'sfx', 'music', 'voice', 'ui', 'ambience'};
    }
  }

  String _categorizeStage(String stage) {
    if (stage.contains('SPIN') || stage.contains('REEL')) return 'spins';
    if (stage.contains('WIN') || stage.contains('ROLLUP')) return 'wins';
    if (stage.contains('FEATURE') || stage.contains('FREE') || stage.contains('BONUS')) return 'features';
    if (stage.contains('JACKPOT')) return 'jackpots';
    if (stage.contains('UI') || stage.contains('BUTTON')) return 'ui';
    if (stage.contains('MUSIC') || stage.contains('AMBIENT')) return 'music';
    return 'misc';
  }

  String _getSubDirForEvent(SlotLabEventItem event) {
    switch (_structure) {
      case AudioPackStructure.flat:
        return '';
      case AudioPackStructure.byStage:
        return event.stage;
      case AudioPackStructure.byCategory:
        return _categorizeStage(event.stage);
      case AudioPackStructure.byBus:
        final stage = event.stage.toUpperCase();
        if (stage.contains('MUSIC') || stage.contains('AMBIENT')) return 'music';
        if (stage.contains('UI') || stage.contains('BUTTON')) return 'ui';
        if (stage.contains('VO') || stage.contains('VOICE')) return 'voice';
        return 'sfx';
    }
  }

  int _formatToCode(AudioPackFormat format) {
    switch (format) {
      case AudioPackFormat.wav16:
      case AudioPackFormat.wav24:
      case AudioPackFormat.wav32f:
        return 0; // WAV
      case AudioPackFormat.mp3High:
      case AudioPackFormat.mp3Med:
      case AudioPackFormat.mp3Low:
        return 2; // MP3
      case AudioPackFormat.oggHigh:
      case AudioPackFormat.oggMed:
      case AudioPackFormat.oggLow:
        return 3; // OGG
    }
  }

  Future<void> _createManifest(String packPath, List<SlotLabEventItem> events) async {
    final manifest = {
      'name': _packName,
      'version': '1.0',
      'createdAt': DateTime.now().toIso8601String(),
      'format': _format.label,
      'structure': _structure.label,
      'normalization': _normalization != NormalizationMode.none
          ? {'mode': _normalization.label, 'target': _normalizationTarget}
          : null,
      'files': events.map((e) {
        String path;
        switch (_structure) {
          case AudioPackStructure.flat:
            path = '${e.name}${_format.extension}';
          case AudioPackStructure.byStage:
            path = '${e.stage}/${e.name}${_format.extension}';
          case AudioPackStructure.byCategory:
            path = '${_categorizeStage(e.stage)}/${e.name}${_format.extension}';
          case AudioPackStructure.byBus:
            path = 'sfx/${e.name}${_format.extension}';
        }
        return {
          'id': e.id,
          'name': e.name,
          'stage': e.stage,
          'path': path,
        };
      }).toList(),
    };

    // Remove null values
    manifest.removeWhere((key, value) => value == null);

    final file = java_io.File('$packPath/manifest.json');
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(manifest));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Event selection
                Expanded(
                  flex: 2,
                  child: _buildEventSelection(),
                ),
                const SizedBox(width: 16),
                // Center: Settings
                Expanded(
                  flex: 3,
                  child: _buildSettings(),
                ),
                const SizedBox(width: 16),
                // Right: Export button + Status
                SizedBox(
                  width: 120,
                  child: _buildExportSection(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final selectedCount = _events.where((e) => e.selected).length;

    return Row(
      children: [
        Icon(Icons.inventory_2, size: 16, color: widget.accentColor),
        const SizedBox(width: 8),
        Text(
          'AUDIO PACK EXPORT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: widget.accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _format.extension.toUpperCase().substring(1),
            style: TextStyle(fontSize: 8, color: widget.accentColor, fontWeight: FontWeight.bold),
          ),
        ),
        const Spacer(),
        Text(
          '$selectedCount events → $_packName/',
          style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildEventSelection() {
    final allSelected = _events.every((e) => e.selected);

    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                final newState = !allSelected;
                for (final event in _events) {
                  event.selected = newState;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: LowerZoneColors.bgMid,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: widget.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text('EVENTS', style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                    letterSpacing: 0.5,
                  )),
                  const Spacer(),
                  Text('${_events.where((e) => e.selected).length}/${_events.length}',
                    style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(4),
              children: _events.map((e) => _buildEventItem(e)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(SlotLabEventItem event) {
    return GestureDetector(
      onTap: () => setState(() => event.selected = !event.selected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: event.selected ? widget.accentColor.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Icon(
              event.selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 12,
              color: event.selected ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(event.name, style: TextStyle(
                fontSize: 10,
                color: event.selected ? LowerZoneColors.textPrimary : LowerZoneColors.textMuted,
              )),
            ),
            Text(event.stage, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Pack name
          _buildPackNameInput(),
          const SizedBox(height: 8),

          // Format & Structure row
          Row(
            children: [
              Expanded(child: _buildDropdown<AudioPackFormat>(
                'Format',
                AudioPackFormat.values,
                _format,
                (f) => f.label,
                (f) => setState(() => _format = f),
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildDropdown<AudioPackStructure>(
                'Structure',
                AudioPackStructure.values,
                _structure,
                (s) => s.label,
                (s) => setState(() => _structure = s),
              )),
            ],
          ),
          const SizedBox(height: 8),

          // Normalization row
          Row(
            children: [
              Expanded(child: _buildDropdown<NormalizationMode>(
                'Normalize',
                NormalizationMode.values,
                _normalization,
                (n) => n.label,
                (n) => setState(() => _normalization = n),
              )),
              const SizedBox(width: 8),
              if (_normalization != NormalizationMode.none)
                Expanded(child: _buildTargetSlider())
              else
                const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 8),

          // Options row
          Row(
            children: [
              Expanded(child: _buildToggle('Include Manifest', _includeManifest,
                  (v) => setState(() => _includeManifest = v))),
              const SizedBox(width: 8),
              Expanded(child: _buildToggle('Create ZIP', _createZip,
                  (v) => setState(() => _createZip = v))),
            ],
          ),
          const SizedBox(height: 8),

          // Output directory
          _buildDirectorySelector(),
        ],
      ),
    );
  }

  Widget _buildPackNameInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pack Name', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          TextField(
            controller: TextEditingController(text: _packName),
            style: TextStyle(fontSize: 10, color: widget.accentColor),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) => _packName = v.isNotEmpty ? v : 'audio_pack',
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    List<T> items,
    T value,
    String Function(T) labelFn,
    void Function(T) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              isExpanded: true,
              dropdownColor: LowerZoneColors.bgDeep,
              icon: Icon(Icons.arrow_drop_down, size: 14, color: widget.accentColor),
              items: items.map((item) => DropdownMenuItem(
                value: item,
                child: Text(labelFn(item), style: TextStyle(fontSize: 10, color: widget.accentColor)),
              )).toList(),
              onChanged: _isExporting ? null : (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSlider() {
    final label = _normalization == NormalizationMode.peak ? 'Peak (dB)' : 'LUFS';
    final min = _normalization == NormalizationMode.peak ? -12.0 : -24.0;
    final max = _normalization == NormalizationMode.peak ? 0.0 : -8.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              const Spacer(),
              Text(
                '${_normalizationTarget.toStringAsFixed(1)}',
                style: TextStyle(fontSize: 9, color: widget.accentColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: widget.accentColor,
              inactiveTrackColor: LowerZoneColors.border,
              thumbColor: widget.accentColor,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _normalizationTarget,
              min: min,
              max: max,
              onChanged: _isExporting ? null : (v) => setState(() => _normalizationTarget = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: _isExporting ? null : () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: value ? widget.accentColor.withValues(alpha: 0.1) : LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? widget.accentColor.withValues(alpha: 0.5) : LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 12,
              color: value ? widget.accentColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: TextStyle(
                fontSize: 9,
                color: value ? widget.accentColor : LowerZoneColors.textPrimary,
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectorySelector() {
    return GestureDetector(
      onTap: _isExporting ? null : _selectOutputDirectory,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, size: 14, color: widget.accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _outputDirectory?.split('/').last ?? 'Choose Output Folder...',
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportSection() {
    return Column(
      children: [
        // Format info
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: LowerZoneColors.bgDeepest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: LowerZoneColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 10, color: widget.accentColor),
                  const SizedBox(width: 4),
                  Text('FORMAT', style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                  )),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _format.description,
                style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                _structure.description,
                style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Progress indicator (when exporting)
        if (_isExporting) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: widget.accentColor.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Text(
                  '${(_exportProgress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _exportProgress,
                  backgroundColor: LowerZoneColors.bgMid,
                  valueColor: AlwaysStoppedAnimation(widget.accentColor),
                ),
                const SizedBox(height: 4),
                Text(
                  _exportStatus,
                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Export button
        Expanded(child: _buildExportButton()),

        // Success message
        if (_lastExportPath != null && _exportedCount > 0 && !_isExporting) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: LowerZoneColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, size: 14, color: LowerZoneColors.success),
                const SizedBox(height: 4),
                Text(
                  '$_exportedCount files',
                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.success),
                ),
                Text(
                  _createZip ? '+ ZIP' : '',
                  style: const TextStyle(fontSize: 7, color: LowerZoneColors.success),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExportButton() {
    return GestureDetector(
      onTap: _isExporting ? null : _startExport,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _isExporting ? [
              LowerZoneColors.bgMid,
              LowerZoneColors.bgDeepest,
            ] : [
              widget.accentColor.withValues(alpha: 0.2),
              widget.accentColor.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _isExporting ? LowerZoneColors.border : widget.accentColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isExporting)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(widget.accentColor),
                ),
              )
            else
              Icon(Icons.inventory_2, size: 32, color: widget.accentColor),
            const SizedBox(height: 8),
            Text(
              _isExporting ? 'EXPORTING...' : 'CREATE\nPACK',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: _isExporting ? LowerZoneColors.textMuted : widget.accentColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
