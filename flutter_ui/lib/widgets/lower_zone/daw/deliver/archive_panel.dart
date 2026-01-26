/// DAW Archive Panel (P0.1 Extracted)
///
/// Project archive creation with:
/// - Include options (audio, presets, plugins)
/// - Compression toggle
/// - Progress tracking
/// - File picker integration
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 146-152 (state) + 2682-2883 (~220 LOC total)
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../lower_zone_types.dart';
import '../shared/panel_helpers.dart';
import '../../../../services/project_archive_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ARCHIVE PANEL
// ═══════════════════════════════════════════════════════════════════════════

class ArchivePanel extends StatefulWidget {
  const ArchivePanel({super.key});

  @override
  State<ArchivePanel> createState() => _ArchivePanelState();
}

class _ArchivePanelState extends State<ArchivePanel> {
  bool _includeAudio = true;
  bool _includePresets = true;
  bool _includePlugins = false;
  bool _compress = true;
  bool _inProgress = false;
  double _progress = 0.0;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader('PROJECT ARCHIVE', Icons.inventory_2),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildCheckbox('Include Audio', _includeAudio, (v) {
                        setState(() => _includeAudio = v);
                      }),
                      _buildCheckbox('Include Presets', _includePresets, (v) {
                        setState(() => _includePresets = v);
                      }),
                      _buildCheckbox('Include Plugins', _includePlugins, (v) {
                        setState(() => _includePlugins = v);
                      }),
                      _buildCheckbox('Compress', _compress, (v) {
                        setState(() => _compress = v);
                      }),
                      if (_inProgress) ...[
                        const SizedBox(height: 8),
                        _buildProgress(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildArchiveButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: value ? LowerZoneColors.success : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _status,
            style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: LowerZoneColors.bgMid,
            valueColor: const AlwaysStoppedAnimation<Color>(LowerZoneColors.dawAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveButton() {
    final color = _inProgress ? LowerZoneColors.textMuted : LowerZoneColors.dawAccent;
    return GestureDetector(
      onTap: _inProgress ? null : _createArchive,
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _inProgress ? Icons.hourglass_empty : Icons.archive,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 6),
            Text(
              _inProgress ? 'CREATING...' : 'ARCHIVE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createArchive() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Project Archive',
      fileName: 'project_archive.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || !mounted) return;

    final projectPath = Directory.current.path;

    setState(() {
      _inProgress = true;
      _progress = 0.0;
      _status = 'Starting...';
    });

    final archiveResult = await ProjectArchiveService.instance.createArchive(
      projectPath: projectPath,
      outputPath: result,
      config: ArchiveConfig(
        includeAudio: _includeAudio,
        includePresets: _includePresets,
        includePlugins: _includePlugins,
        compress: _compress,
      ),
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _status = status;
          });
        }
      },
    );

    if (!mounted) return;

    setState(() {
      _inProgress = false;
      _progress = 0.0;
      _status = '';
    });

    if (archiveResult.success) {
      final sizeKB = (archiveResult.totalBytes / 1024).toStringAsFixed(1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive created: ${archiveResult.fileCount} files, $sizeKB KB'),
            backgroundColor: LowerZoneColors.success,
            action: SnackBarAction(
              label: 'Open Folder',
              textColor: Colors.white,
              onPressed: () {
                final dir = Directory(result).parent.path;
                if (Platform.isMacOS) {
                  Process.run('open', [dir]);
                } else if (Platform.isWindows) {
                  Process.run('explorer', [dir]);
                } else if (Platform.isLinux) {
                  Process.run('xdg-open', [dir]);
                }
              },
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive failed: ${archiveResult.error}'),
            backgroundColor: LowerZoneColors.error,
          ),
        );
      }
    }
  }
}
