/// Batch Export Panel
///
/// Export SlotLab events/packages for game integration.
///
/// Features:
/// - Export type selection (Universal, Unity, Unreal, Howler.js)
/// - Event selection (all, selected, by category)
/// - Format settings (audio format, normalization, stems)
/// - Progress indicator during export
/// - FilePicker integration for save location
/// - Success/error feedback
///
/// Task: SL-LZ-P0.4
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../models/slot_audio_events.dart';
import '../../../../providers/middleware_provider.dart';
import '../../../../theme/fluxforge_theme.dart';
import '../../../../services/export/unity_exporter.dart';
import '../../../../services/export/unreal_exporter.dart';
import '../../../../services/export/howler_exporter.dart';

enum ExportPlatform { universal, unity, unreal, howler }
enum AudioFormat { wav16, wav24, wav32f, flac, mp3High }
enum EventSelection { all, selected, byCategory }

/// Batch Export Panel
class BatchExportPanel extends StatefulWidget {
  final List<String>? selectedEventIds;

  const BatchExportPanel({
    super.key,
    this.selectedEventIds,
  });

  @override
  State<BatchExportPanel> createState() => _BatchExportPanelState();
}

class _BatchExportPanelState extends State<BatchExportPanel> {
  ExportPlatform _platform = ExportPlatform.universal;
  AudioFormat _audioFormat = AudioFormat.wav24;
  EventSelection _eventSelection = EventSelection.all;
  String _categoryFilter = 'All';
  bool _normalizeAudio = true;
  double _lufsTarget = -14.0;
  bool _exportStems = false;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final allEvents = middleware.compositeEvents;
        final categories = _getCategories(allEvents);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Export type selector
              _buildExportTypeSelector(),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),

              // Event selection
              _buildEventSelection(allEvents, categories),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),

              // Export settings
              _buildExportSettings(),
              const Spacer(),

              // Progress indicator
              if (_isExporting) ...[
                const SizedBox(height: 16),
                _buildProgressIndicator(),
                const SizedBox(height: 16),
              ],

              // Export button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: _isExporting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.black),
                          ),
                        )
                      : Icon(Icons.file_download, size: 20),
                  label: Text(
                    _isExporting ? 'Exporting...' : 'Export Package',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _isExporting
                      ? null
                      : () => _performExport(context, middleware, allEvents),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FluxForgeTheme.accentGreen,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white.withOpacity(0.1),
                    disabledForegroundColor: Colors.white38,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExportTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('EXPORT TYPE'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final platform in ExportPlatform.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: platform != ExportPlatform.values.last ? 8 : 0),
                  child: _buildPlatformButton(platform),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlatformButton(ExportPlatform platform) {
    final isSelected = _platform == platform;
    return InkWell(
      onTap: () => setState(() => _platform = platform),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withOpacity(0.2)
              : const Color(0xFF16161C),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentBlue
                : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getPlatformIcon(platform),
              size: 24,
              color: isSelected ? FluxForgeTheme.accentBlue : Colors.white38,
            ),
            const SizedBox(height: 4),
            Text(
              _getPlatformName(platform),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? FluxForgeTheme.accentBlue : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventSelection(List<SlotCompositeEvent> allEvents, List<String> categories) {
    final selectedCount = _getSelectedEvents(allEvents).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('EVENT SELECTION ($selectedCount/${allEvents.length})'),
        const SizedBox(height: 10),

        // Selection mode
        Row(
          children: [
            for (final mode in EventSelection.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: mode != EventSelection.values.last ? 8 : 0),
                  child: _buildSelectionModeButton(mode),
                ),
              ),
          ],
        ),

        // Category filter (if byCategory mode)
        if (_eventSelection == EventSelection.byCategory) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _categoryFilter,
            items: categories.map((cat) {
              return DropdownMenuItem(value: cat, child: Text(cat));
            }).toList(),
            onChanged: (value) {
              if (value != null) setState(() => _categoryFilter = value);
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF16161C),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(Icons.category, size: 16, color: Colors.white54),
            ),
            dropdownColor: const Color(0xFF1A1A22),
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectionModeButton(EventSelection mode) {
    final isSelected = _eventSelection == mode;
    return InkWell(
      onTap: () => setState(() => _eventSelection = mode),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentGreen.withOpacity(0.2)
              : const Color(0xFF16161C),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentGreen
                : Colors.white.withOpacity(0.1),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _getSelectionModeName(mode),
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? FluxForgeTheme.accentGreen : Colors.white54,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildExportSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('EXPORT SETTINGS'),
        const SizedBox(height: 10),

        // Audio format
        _buildSettingRow(
          label: 'Audio Format',
          child: DropdownButton<AudioFormat>(
            value: _audioFormat,
            items: AudioFormat.values.map((format) {
              return DropdownMenuItem(
                value: format,
                child: Text(_getAudioFormatName(format)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) setState(() => _audioFormat = value);
            },
            dropdownColor: const Color(0xFF1A1A22),
            style: const TextStyle(fontSize: 11, color: Colors.white),
            underline: const SizedBox.shrink(),
          ),
        ),

        const SizedBox(height: 10),

        // Normalize audio
        _buildSettingRow(
          label: 'Normalize Audio',
          child: Row(
            children: [
              Switch(
                value: _normalizeAudio,
                onChanged: (v) => setState(() => _normalizeAudio = v),
                activeColor: FluxForgeTheme.accentGreen,
              ),
              if (_normalizeAudio) ...[
                const SizedBox(width: 12),
                Text(
                  'Target: ${_lufsTarget.toStringAsFixed(1)} LUFS',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Export stems
        _buildSettingRow(
          label: 'Export Stems',
          child: Switch(
            value: _exportStems,
            onChanged: (v) => setState(() => _exportStems = v),
            activeColor: FluxForgeTheme.accentGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentGreen),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _exportStatus,
                  style: TextStyle(fontSize: 11, color: FluxForgeTheme.accentGreen),
                ),
              ),
              Text(
                '${(_exportProgress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: FluxForgeTheme.accentGreen,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _exportProgress,
            backgroundColor: Colors.white.withOpacity(0.05),
            color: FluxForgeTheme.accentGreen,
            minHeight: 3,
          ),
        ],
      ),
    );
  }

  Future<void> _performExport(
    BuildContext context,
    MiddlewareProvider middleware,
    List<SlotCompositeEvent> allEvents,
  ) async {
    // Get selected events
    final eventsToExport = _getSelectedEvents(allEvents);
    if (eventsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No events to export'),
          backgroundColor: FluxForgeTheme.accentOrange,
        ),
      );
      return;
    }

    // Pick save location
    final outputPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Export Destination',
    );

    if (outputPath == null) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportStatus = 'Preparing export...';
    });

    try {
      // Get additional data from provider
      final rtpcs = middleware.rtpcDefinitions;
      final stateGroups = middleware.stateGroups;
      final switchGroups = middleware.switchGroups;
      final duckingRules = middleware.duckingRules;

      setState(() {
        _exportProgress = 0.1;
        _exportStatus = 'Collecting middleware data...';
      });

      // Create export directory
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final platformName = _platform.name;
      final exportDir = Directory('$outputPath/SlotLab_${platformName}_$timestamp');
      await exportDir.create(recursive: true);

      setState(() {
        _exportProgress = 0.2;
        _exportStatus = 'Generating code...';
      });

      // Generate export based on platform
      Map<String, String> exportedFiles = {};

      switch (_platform) {
        case ExportPlatform.universal:
          // Export all formats
          final unityResult = const UnityExporter().export(
            events: eventsToExport,
            rtpcs: rtpcs,
            stateGroups: stateGroups,
            switchGroups: switchGroups,
            duckingRules: duckingRules,
          );
          final unrealResult = const UnrealExporter().export(
            events: eventsToExport,
            rtpcs: rtpcs,
            stateGroups: stateGroups,
            switchGroups: switchGroups,
            duckingRules: duckingRules,
          );
          final howlerResult = const HowlerExporter().export(
            events: eventsToExport,
            rtpcs: rtpcs,
            stateGroups: stateGroups,
            switchGroups: switchGroups,
            duckingRules: duckingRules,
          );

          // Create subdirectories
          await Directory('${exportDir.path}/Unity').create();
          await Directory('${exportDir.path}/Unreal').create();
          await Directory('${exportDir.path}/Howler').create();

          // Write Unity files
          for (final entry in unityResult.files.entries) {
            exportedFiles['Unity/${entry.key}'] = entry.value;
          }
          // Write Unreal files
          for (final entry in unrealResult.files.entries) {
            exportedFiles['Unreal/${entry.key}'] = entry.value;
          }
          // Write Howler files
          for (final entry in howlerResult.files.entries) {
            exportedFiles['Howler/${entry.key}'] = entry.value;
          }

        case ExportPlatform.unity:
          final result = const UnityExporter().export(
            events: eventsToExport,
            rtpcs: rtpcs,
            stateGroups: stateGroups,
            switchGroups: switchGroups,
            duckingRules: duckingRules,
          );
          exportedFiles = result.files;

        case ExportPlatform.unreal:
          final result = const UnrealExporter().export(
            events: eventsToExport,
            rtpcs: rtpcs,
            stateGroups: stateGroups,
            switchGroups: switchGroups,
            duckingRules: duckingRules,
          );
          exportedFiles = result.files;

        case ExportPlatform.howler:
          final result = const HowlerExporter().export(
            events: eventsToExport,
            rtpcs: rtpcs,
            stateGroups: stateGroups,
            switchGroups: switchGroups,
            duckingRules: duckingRules,
          );
          exportedFiles = result.files;
      }

      setState(() {
        _exportProgress = 0.5;
        _exportStatus = 'Writing files...';
      });

      // Write all generated files
      int fileCount = 0;
      for (final entry in exportedFiles.entries) {
        final filePath = '${exportDir.path}/${entry.key}';
        final file = File(filePath);

        // Create parent directories if needed
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);

        fileCount++;
        setState(() {
          _exportProgress = 0.5 + (0.4 * fileCount / exportedFiles.length);
          _exportStatus = 'Writing ${entry.key}...';
        });
      }

      setState(() {
        _exportProgress = 0.95;
        _exportStatus = 'Finalizing...';
      });

      // Create summary file
      final summary = StringBuffer();
      summary.writeln('FluxForge Studio Export Summary');
      summary.writeln('================================');
      summary.writeln('Platform: ${_getPlatformName(_platform)}');
      summary.writeln('Events: ${eventsToExport.length}');
      summary.writeln('RTPCs: ${rtpcs.length}');
      summary.writeln('State Groups: ${stateGroups.length}');
      summary.writeln('Switch Groups: ${switchGroups.length}');
      summary.writeln('Ducking Rules: ${duckingRules.length}');
      summary.writeln('Files Generated: ${exportedFiles.length}');
      summary.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
      summary.writeln('');
      summary.writeln('Files:');
      for (final fileName in exportedFiles.keys) {
        summary.writeln('  - $fileName');
      }

      await File('${exportDir.path}/README.txt').writeAsString(summary.toString());

      setState(() {
        _isExporting = false;
        _exportProgress = 1.0;
        _exportStatus = 'Export complete!';
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${eventsToExport.length} events (${exportedFiles.length} files) to ${exportDir.path}',
          ),
          backgroundColor: FluxForgeTheme.accentGreen,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () {
              // Open folder in file manager (platform-specific)
              Process.run('open', [exportDir.path]);
            },
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isExporting = false;
        _exportStatus = 'Export failed: $e';
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: FluxForgeTheme.accentRed,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  List<SlotCompositeEvent> _getSelectedEvents(List<SlotCompositeEvent> allEvents) {
    switch (_eventSelection) {
      case EventSelection.all:
        return allEvents;
      case EventSelection.selected:
        if (widget.selectedEventIds == null || widget.selectedEventIds!.isEmpty) {
          return [];
        }
        return allEvents.where((e) => widget.selectedEventIds!.contains(e.id)).toList();
      case EventSelection.byCategory:
        if (_categoryFilter == 'All') return allEvents;
        return allEvents.where((e) => e.category == _categoryFilter).toList();
    }
  }

  List<String> _getCategories(List<SlotCompositeEvent> events) {
    final cats = events.map((e) => e.category).toSet().toList();
    cats.sort();
    return ['All', ...cats];
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.white54,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildSettingRow({required String label, required Widget child}) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  IconData _getPlatformIcon(ExportPlatform platform) {
    switch (platform) {
      case ExportPlatform.universal:
        return Icons.public;
      case ExportPlatform.unity:
        return Icons.games;
      case ExportPlatform.unreal:
        return Icons.videogame_asset;
      case ExportPlatform.howler:
        return Icons.web;
    }
  }

  String _getPlatformName(ExportPlatform platform) {
    switch (platform) {
      case ExportPlatform.universal:
        return 'Universal';
      case ExportPlatform.unity:
        return 'Unity';
      case ExportPlatform.unreal:
        return 'Unreal';
      case ExportPlatform.howler:
        return 'Howler.js';
    }
  }

  String _getSelectionModeName(EventSelection mode) {
    switch (mode) {
      case EventSelection.all:
        return 'All Events';
      case EventSelection.selected:
        return 'Selected Only';
      case EventSelection.byCategory:
        return 'By Category';
    }
  }

  String _getAudioFormatName(AudioFormat format) {
    switch (format) {
      case AudioFormat.wav16:
        return 'WAV 16-bit';
      case AudioFormat.wav24:
        return 'WAV 24-bit';
      case AudioFormat.wav32f:
        return 'WAV 32-bit Float';
      case AudioFormat.flac:
        return 'FLAC Lossless';
      case AudioFormat.mp3High:
        return 'MP3 320kbps';
    }
  }
}
