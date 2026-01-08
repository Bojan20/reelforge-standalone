// Batch Export Dialog
//
// Professional batch export with:
// - Export multiple tracks/stems
// - Export between markers/regions
// - Multiple format export
// - Naming templates
// - Progress tracking
// - Queue management

import 'dart:async';
import 'package:flutter/material.dart';
import '../src/rust/native_ffi.dart';
import '../theme/reelforge_theme.dart';
import 'export_presets_dialog.dart';

/// Batch export item (track/region to export)
class BatchExportItem {
  final String id;
  final String name;
  final BatchExportType type;
  final double startTime;
  final double endTime;
  final String? trackId;
  final bool isSelected;
  final ExportItemStatus status;
  final double progress;
  final String? outputPath;
  final String? error;

  BatchExportItem({
    required this.id,
    required this.name,
    required this.type,
    this.startTime = 0,
    this.endTime = 0,
    this.trackId,
    this.isSelected = true,
    this.status = ExportItemStatus.pending,
    this.progress = 0,
    this.outputPath,
    this.error,
  });

  BatchExportItem copyWith({
    bool? isSelected,
    ExportItemStatus? status,
    double? progress,
    String? outputPath,
    String? error,
  }) {
    return BatchExportItem(
      id: id,
      name: name,
      type: type,
      startTime: startTime,
      endTime: endTime,
      trackId: trackId,
      isSelected: isSelected ?? this.isSelected,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputPath: outputPath ?? this.outputPath,
      error: error ?? this.error,
    );
  }

  String get durationLabel {
    final duration = endTime - startTime;
    final mins = (duration / 60).floor();
    final secs = (duration % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}

enum BatchExportType {
  track,
  stem,
  region,
  marker,
  full,
}

extension BatchExportTypeExt on BatchExportType {
  String get label {
    switch (this) {
      case BatchExportType.track: return 'Track';
      case BatchExportType.stem: return 'Stem';
      case BatchExportType.region: return 'Region';
      case BatchExportType.marker: return 'Marker';
      case BatchExportType.full: return 'Full Mix';
    }
  }

  IconData get icon {
    switch (this) {
      case BatchExportType.track: return Icons.audiotrack;
      case BatchExportType.stem: return Icons.layers;
      case BatchExportType.region: return Icons.crop;
      case BatchExportType.marker: return Icons.bookmark;
      case BatchExportType.full: return Icons.album;
    }
  }

  Color get color {
    switch (this) {
      case BatchExportType.track: return ReelForgeTheme.accentBlue;
      case BatchExportType.stem: return ReelForgeTheme.accentGreen;
      case BatchExportType.region: return ReelForgeTheme.accentOrange;
      case BatchExportType.marker: return ReelForgeTheme.accentCyan;
      case BatchExportType.full: return const Color(0xFF9C27B0);
    }
  }
}

enum ExportItemStatus {
  pending,
  exporting,
  completed,
  failed,
  skipped,
}

/// Batch Export Dialog
class BatchExportDialog extends StatefulWidget {
  final List<BatchExportItem> items;
  final ExportPreset? defaultPreset;

  const BatchExportDialog({
    super.key,
    required this.items,
    this.defaultPreset,
  });

  @override
  State<BatchExportDialog> createState() => _BatchExportDialogState();
}

class _BatchExportDialogState extends State<BatchExportDialog> {
  final _ffi = NativeFFI.instance;
  late List<BatchExportItem> _items;
  ExportPreset? _selectedPreset;
  String _outputFolder = '';
  String _namingTemplate = '{name}_{format}';
  bool _isExporting = false;
  bool _isPaused = false;
  int _currentIndex = -1;
  double _overallProgress = 0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    _selectedPreset = widget.defaultPreset;
    _outputFolder = _ffi.getDefaultExportPath();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  int get _selectedCount => _items.where((i) => i.isSelected).length;
  int get _completedCount => _items.where((i) => i.status == ExportItemStatus.completed).length;
  int get _failedCount => _items.where((i) => i.status == ExportItemStatus.failed).length;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReelForgeTheme.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
            if (_isExporting)
              _buildProgressBar()
            else
              _buildSettingsBar(),
            const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
            Expanded(child: _buildItemList()),
            const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
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
          const Icon(Icons.download_for_offline, color: ReelForgeTheme.accentGreen, size: 22),
          const SizedBox(width: 10),
          const Text(
            'Batch Export',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$_selectedCount items selected',
              style: const TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          const Spacer(),
          if (_isExporting) ...[
            Text(
              '$_completedCount / $_selectedCount completed',
              style: const TextStyle(color: ReelForgeTheme.accentGreen, fontSize: 12),
            ),
            if (_failedCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                '$_failedCount failed',
                style: const TextStyle(color: ReelForgeTheme.accentRed, fontSize: 12),
              ),
            ],
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: ReelForgeTheme.textSecondary,
            onPressed: _isExporting ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: ReelForgeTheme.bgDeep,
      child: Row(
        children: [
          // Preset selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Preset', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 9)),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: _selectPreset,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ReelForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: ReelForgeTheme.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedPreset?.name ?? 'Select preset...',
                        style: TextStyle(
                          color: _selectedPreset != null ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_drop_down, size: 16, color: ReelForgeTheme.textSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Output folder
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Output Folder', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 9)),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: _selectOutputFolder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: ReelForgeTheme.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder, size: 14, color: ReelForgeTheme.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _outputFolder.isEmpty ? 'Select folder...' : _outputFolder,
                            style: TextStyle(
                              color: _outputFolder.isNotEmpty ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Naming template
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Naming', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 9)),
              const SizedBox(height: 2),
              Container(
                width: 180,
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: ReelForgeTheme.borderSubtle),
                ),
                child: TextField(
                  controller: TextEditingController(text: _namingTemplate),
                  style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 11, fontFamily: 'JetBrains Mono'),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: (v) => _namingTemplate = v,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: ReelForgeTheme.bgDeep,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(
                _currentIndex >= 0 && _currentIndex < _items.length
                    ? 'Exporting: ${_items[_currentIndex].name}'
                    : 'Preparing...',
                style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '${(_overallProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: ReelForgeTheme.accentGreen,
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _overallProgress,
              backgroundColor: ReelForgeTheme.bgMid,
              valueColor: const AlwaysStoppedAnimation(ReelForgeTheme.accentGreen),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (context, index) => _buildExportItem(_items[index], index),
    );
  }

  Widget _buildExportItem(BatchExportItem item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.status == ExportItemStatus.exporting
            ? ReelForgeTheme.accentGreen.withValues(alpha: 0.1)
            : item.status == ExportItemStatus.failed
                ? ReelForgeTheme.accentRed.withValues(alpha: 0.1)
                : ReelForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: item.status == ExportItemStatus.exporting
              ? ReelForgeTheme.accentGreen
              : item.status == ExportItemStatus.failed
                  ? ReelForgeTheme.accentRed
                  : ReelForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Checkbox
          if (!_isExporting)
            Checkbox(
              value: item.isSelected,
              onChanged: (v) {
                setState(() {
                  _items[index] = item.copyWith(isSelected: v ?? false);
                });
              },
              activeColor: ReelForgeTheme.accentBlue,
              side: const BorderSide(color: ReelForgeTheme.textTertiary),
            ),
          // Type icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: item.type.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(item.type.icon, size: 16, color: item.type.color),
          ),
          const SizedBox(width: 12),
          // Name and info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: item.isSelected || _isExporting ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      item.type.label,
                      style: TextStyle(color: item.type.color.withValues(alpha: 0.8), fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.durationLabel,
                      style: const TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10, fontFamily: 'JetBrains Mono'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Status
          _buildStatusBadge(item),
          // Progress bar for current item
          if (item.status == ExportItemStatus.exporting)
            SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor: ReelForgeTheme.bgDeep,
                  valueColor: const AlwaysStoppedAnimation(ReelForgeTheme.accentGreen),
                  minHeight: 4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BatchExportItem item) {
    IconData icon;
    Color color;
    String label;

    switch (item.status) {
      case ExportItemStatus.pending:
        return const SizedBox(width: 80);
      case ExportItemStatus.exporting:
        icon = Icons.sync;
        color = ReelForgeTheme.accentGreen;
        label = 'Exporting';
        break;
      case ExportItemStatus.completed:
        icon = Icons.check_circle;
        color = ReelForgeTheme.accentGreen;
        label = 'Done';
        break;
      case ExportItemStatus.failed:
        icon = Icons.error;
        color = ReelForgeTheme.accentRed;
        label = 'Failed';
        break;
      case ExportItemStatus.skipped:
        icon = Icons.skip_next;
        color = ReelForgeTheme.textTertiary;
        label = 'Skipped';
        break;
    }

    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
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
          // Select all / none
          if (!_isExporting) ...[
            TextButton(
              onPressed: () {
                setState(() {
                  final allSelected = _items.every((i) => i.isSelected);
                  _items = _items.map((i) => i.copyWith(isSelected: !allSelected)).toList();
                });
              },
              child: Text(_items.every((i) => i.isSelected) ? 'Deselect All' : 'Select All'),
            ),
          ],
          const Spacer(),
          if (_isExporting) ...[
            // Pause/Resume
            TextButton.icon(
              onPressed: () {
                setState(() => _isPaused = !_isPaused);
              },
              icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 16),
              label: Text(_isPaused ? 'Resume' : 'Pause'),
            ),
            const SizedBox(width: 8),
            // Cancel
            TextButton(
              onPressed: _cancelExport,
              child: const Text('Cancel'),
            ),
          ] else ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _selectedCount > 0 && _selectedPreset != null
                  ? _startExport
                  : null,
              icon: const Icon(Icons.download, size: 16),
              label: Text('Export $_selectedCount Items'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ReelForgeTheme.accentGreen,
                foregroundColor: ReelForgeTheme.bgVoid,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _selectPreset() async {
    final result = await showDialog<ExportPreset>(
      context: context,
      builder: (ctx) => ExportPresetsDialog(
        selectedPreset: _selectedPreset,
        onPresetSelected: (preset) => Navigator.pop(ctx, preset),
      ),
    );

    if (result != null) {
      setState(() => _selectedPreset = result);
    }
  }

  Future<void> _selectOutputFolder() async {
    final path = await _ffi.selectExportFolder();
    if (path != null && path.isNotEmpty) {
      setState(() => _outputFolder = path);
    }
  }

  void _startExport() {
    setState(() {
      _isExporting = true;
      _currentIndex = 0;
      _overallProgress = 0;
    });

    // Simulate export progress
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isPaused) return;

      setState(() {
        if (_currentIndex < _items.length) {
          final item = _items[_currentIndex];
          if (!item.isSelected) {
            _items[_currentIndex] = item.copyWith(status: ExportItemStatus.skipped);
            _currentIndex++;
            return;
          }

          if (item.status == ExportItemStatus.pending) {
            _items[_currentIndex] = item.copyWith(status: ExportItemStatus.exporting);
          }

          final newProgress = item.progress + 0.05;
          if (newProgress >= 1.0) {
            _items[_currentIndex] = item.copyWith(
              status: ExportItemStatus.completed,
              progress: 1.0,
            );
            _currentIndex++;
          } else {
            _items[_currentIndex] = item.copyWith(progress: newProgress);
          }

          _overallProgress = (_completedCount + (item.progress)) / _selectedCount;
        } else {
          timer.cancel();
          _isExporting = false;
        }
      });
    });
  }

  void _cancelExport() {
    _progressTimer?.cancel();
    setState(() {
      _isExporting = false;
      _isPaused = false;
      _currentIndex = -1;
      _items = _items.map((i) {
        if (i.status == ExportItemStatus.exporting) {
          return i.copyWith(status: ExportItemStatus.pending, progress: 0);
        }
        return i;
      }).toList();
    });
  }
}
