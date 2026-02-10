/// Group Batch Import Panel
///
/// Drop zone UI for batch importing audio files into stage groups.
/// Features:
/// - 3 group selection (Spins & Reels, Wins, Music & Features)
/// - Multi-file and folder drop support
/// - Fuzzy matching with confidence scores
/// - Unmatched file handling with suggestions

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/stage_group_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Callback for when events should be created
typedef OnEventsCreated = void Function(List<BatchEventSpec> events);

/// Specification for a single event to create
class BatchEventSpec {
  final String eventName;
  final String stage;
  final String audioPath;
  final double volume;
  final double pan;

  const BatchEventSpec({
    required this.eventName,
    required this.stage,
    required this.audioPath,
    this.volume = 0.8,
    this.pan = 0.0,
  });
}

/// Panel state for a matched/unmatched file
class _FileEntry {
  final String audioPath;
  final String fileName;
  String? selectedStage;
  double confidence;
  List<StageSuggestion> suggestions;
  bool isAccepted;
  bool isSkipped;

  _FileEntry({
    required this.audioPath,
    required this.fileName,
    this.selectedStage,
    this.confidence = 0.0,
    this.suggestions = const [],
    this.isAccepted = false,
    this.isSkipped = false,
  });

  bool get needsAction => selectedStage == null && !isSkipped;
  bool get isReady => (selectedStage != null && isAccepted) || isSkipped;
}

class GroupBatchImportPanel extends StatefulWidget {
  final OnEventsCreated? onEventsCreated;
  final VoidCallback? onClose;

  const GroupBatchImportPanel({
    super.key,
    this.onEventsCreated,
    this.onClose,
  });

  @override
  State<GroupBatchImportPanel> createState() => _GroupBatchImportPanelState();
}

class _GroupBatchImportPanelState extends State<GroupBatchImportPanel> {
  final _service = StageGroupService.instance;

  StageGroup? _selectedGroup;
  final List<_FileEntry> _entries = [];
  bool _isDragging = false;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: _selectedGroup == null
                ? _buildGroupSelection()
                : _buildImportView(),
          ),
          if (_entries.isNotEmpty) _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          if (_selectedGroup != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: _resetToGroupSelection,
              tooltip: 'Back to groups',
              color: FluxForgeTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            Icons.library_add,
            color: FluxForgeTheme.accentBlue,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _selectedGroup == null
                ? 'Batch Import'
                : '${_selectedGroup!.icon} ${_selectedGroup!.displayName}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (_entries.isNotEmpty)
            _buildStats(),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              color: FluxForgeTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final matched = _entries.where((e) => e.selectedStage != null && !e.isSkipped).length;
    final skipped = _entries.where((e) => e.isSkipped).length;
    final pending = _entries.where((e) => e.needsAction).length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStatBadge('$matched', FluxForgeTheme.accentGreen, 'Matched'),
        const SizedBox(width: 6),
        if (pending > 0) ...[
          _buildStatBadge('$pending', FluxForgeTheme.accentOrange, 'Pending'),
          const SizedBox(width: 6),
        ],
        if (skipped > 0) ...[
          _buildStatBadge('$skipped', FluxForgeTheme.textMuted, 'Skipped'),
          const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildStatBadge(String value, Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSelection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Select a Stage Group',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a category to batch import audio files',
            style: TextStyle(
              fontSize: 13,
              color: FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: StageGroup.values.map((group) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildGroupCard(group),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(StageGroup group) {
    final isHovered = ValueNotifier(false);

    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: ValueListenableBuilder<bool>(
        valueListenable: isHovered,
        builder: (context, hover, _) {
          return GestureDetector(
            onTap: () => _selectGroup(group),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 160,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hover ? FluxForgeTheme.bgMid : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hover
                      ? FluxForgeTheme.accentBlue.withOpacity(0.5)
                      : FluxForgeTheme.borderSubtle,
                ),
                boxShadow: hover
                    ? [
                        BoxShadow(
                          color: FluxForgeTheme.accentBlue.withOpacity(0.1),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImportView() {
    return Column(
      children: [
        // Drop zone
        Expanded(
          flex: _entries.isEmpty ? 1 : 0,
          child: _buildDropZone(),
        ),
        // File list
        if (_entries.isNotEmpty)
          Expanded(
            child: _buildFileList(),
          ),
      ],
    );
  }

  Widget _buildDropZone() {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        setState(() => _isDragging = true);
        return true;
      },
      onLeave: (_) => setState(() => _isDragging = false),
      onAcceptWithDetails: (details) {
        setState(() => _isDragging = false);
        // Handle drop - this is simplified, real implementation would need platform channels
        _showFilePicker();
      },
      builder: (context, candidateData, rejectedData) {
        return GestureDetector(
          onTap: _showFilePicker,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.all(_entries.isEmpty ? 16 : 8),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _isDragging
                  ? FluxForgeTheme.accentBlue.withOpacity(0.1)
                  : FluxForgeTheme.bgMid.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isDragging
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.borderSubtle,
                width: _isDragging ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: _entries.isEmpty ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(
                  _isDragging ? Icons.file_download : Icons.cloud_upload_outlined,
                  size: _entries.isEmpty ? 48 : 32,
                  color: _isDragging
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  _isDragging
                      ? 'Drop files here'
                      : _entries.isEmpty
                          ? 'Drop audio files or folder'
                          : 'Drop more files to add',
                  style: TextStyle(
                    fontSize: _entries.isEmpty ? 16 : 13,
                    fontWeight: FontWeight.w500,
                    color: _isDragging
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.textPrimary,
                  ),
                ),
                // Add more buttons when entries exist
                if (_entries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showFilePicker(folderMode: false),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add Files'),
                        style: TextButton.styleFrom(
                          foregroundColor: FluxForgeTheme.accentBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _showFilePicker(folderMode: true),
                        icon: const Icon(Icons.folder_open, size: 14),
                        label: const Text('Add Folder'),
                        style: TextButton.styleFrom(
                          foregroundColor: FluxForgeTheme.accentBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_entries.isEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'or click to browse',
                    style: TextStyle(
                      fontSize: 13,
                      color: FluxForgeTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildActionButtonWithTooltip(
                        'Select Files',
                        Icons.queue_music,
                        'Select multiple audio files (Ctrl+Click)',
                        () => _showFilePicker(folderMode: false),
                      ),
                      const SizedBox(width: 12),
                      _buildActionButtonWithTooltip(
                        'Select Folder',
                        Icons.folder_open,
                        'Import all audio from a folder',
                        () => _showFilePicker(folderMode: true),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: FluxForgeTheme.textPrimary,
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  Widget _buildActionButtonWithTooltip(
    String label,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: FluxForgeTheme.textPrimary,
          side: BorderSide(color: FluxForgeTheme.borderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildFileList() {
    final matched = _entries.where((e) => e.selectedStage != null && !e.isSkipped).toList();
    final unmatched = _entries.where((e) => e.needsAction).toList();
    final skipped = _entries.where((e) => e.isSkipped).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        if (matched.isNotEmpty) ...[
          _buildSectionHeader('Matched (${matched.length})', FluxForgeTheme.accentGreen),
          ...matched.map(_buildFileRow),
        ],
        if (unmatched.isNotEmpty) ...[
          _buildSectionHeader('Needs Review (${unmatched.length})', FluxForgeTheme.accentOrange),
          ...unmatched.map(_buildUnmatchedRow),
        ],
        if (skipped.isNotEmpty) ...[
          _buildSectionHeader('Skipped (${skipped.length})', FluxForgeTheme.textMuted),
          ...skipped.map(_buildFileRow),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(_FileEntry entry) {
    final confidenceColor = entry.confidence >= 0.7
        ? FluxForgeTheme.accentGreen
        : entry.confidence >= 0.4
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentRed;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: entry.isSkipped
            ? FluxForgeTheme.bgMid.withOpacity(0.3)
            : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            entry.isSkipped ? Icons.skip_next : Icons.audio_file,
            size: 16,
            color: entry.isSkipped
                ? FluxForgeTheme.textMuted
                : FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.fileName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: entry.isSkipped
                        ? FluxForgeTheme.textMuted
                        : FluxForgeTheme.textPrimary,
                    decoration: entry.isSkipped
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.selectedStage != null && !entry.isSkipped)
                  Text(
                    '→ ${entry.selectedStage}',
                    style: TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.accentCyan,
                    ),
                  ),
              ],
            ),
          ),
          if (!entry.isSkipped && entry.confidence > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: confidenceColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(entry.confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: confidenceColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (!entry.isSkipped)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              onPressed: () => _skipEntry(entry),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: FluxForgeTheme.textMuted,
              tooltip: 'Skip this file',
            ),
          if (entry.isSkipped)
            IconButton(
              icon: const Icon(Icons.undo, size: 14),
              onPressed: () => _unskipEntry(entry),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: FluxForgeTheme.textMuted,
              tooltip: 'Restore',
            ),
        ],
      ),
    );
  }

  Widget _buildUnmatchedRow(_FileEntry entry) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: FluxForgeTheme.accentOrange.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 16,
                color: FluxForgeTheme.accentOrange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.fileName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FluxForgeTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _skipEntry(entry),
                style: TextButton.styleFrom(
                  foregroundColor: FluxForgeTheme.textMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Skip', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (entry.suggestions.isNotEmpty) ...[
            Text(
              'Suggestions:',
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: entry.suggestions.map((s) {
                return _buildSuggestionChip(entry, s);
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),
          _buildStageDropdown(entry),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(_FileEntry entry, StageSuggestion suggestion) {
    return InkWell(
      onTap: () => _acceptSuggestion(entry, suggestion.stage),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: FluxForgeTheme.accentBlue.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              suggestion.stage,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${(suggestion.confidence * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageDropdown(_FileEntry entry) {
    final stages = _selectedGroup != null
        ? _service.getStagesForGroup(_selectedGroup!)
        : <String>[];

    return Row(
      children: [
        Text(
          'Or select:',
          style: TextStyle(
            fontSize: 10,
            color: FluxForgeTheme.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: entry.selectedStage,
                hint: Text(
                  'Pick a stage...',
                  style: TextStyle(
                    fontSize: 11,
                    color: FluxForgeTheme.textMuted,
                  ),
                ),
                isExpanded: true,
                isDense: true,
                dropdownColor: FluxForgeTheme.bgMid,
                style: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textPrimary,
                ),
                items: stages.map((stage) {
                  return DropdownMenuItem(
                    value: stage,
                    child: Text(stage),
                  );
                }).toList(),
                onChanged: (stage) {
                  if (stage != null) {
                    _acceptSuggestion(entry, stage);
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final readyCount = _entries.where((e) => e.selectedStage != null && !e.isSkipped).length;
    final canCommit = readyCount > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _clearAll,
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('Clear All'),
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            '$readyCount files ready',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: canCommit && !_isProcessing ? _commitAll : null,
            icon: _isProcessing
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: FluxForgeTheme.textPrimary,
                    ),
                  )
                : const Icon(Icons.check, size: 16),
            label: Text(_isProcessing ? 'Creating...' : 'Create Events'),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: FluxForgeTheme.bgDeep,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _selectGroup(StageGroup group) {
    setState(() {
      _selectedGroup = group;
      _entries.clear();
    });
  }

  void _resetToGroupSelection() {
    setState(() {
      _selectedGroup = null;
      _entries.clear();
    });
  }

  Future<void> _showFilePicker({bool folderMode = false}) async {
    if (_selectedGroup == null) return;

    try {
      List<String> paths = [];

      if (folderMode) {
        final result = await FilePicker.platform.getDirectoryPath();
        if (result != null) {
          // Scan folder for audio files
          final dir = Directory(result);
          final audioExtensions = ['.wav', '.mp3', '.flac', '.ogg', '.aiff'];
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              final ext = entity.path.toLowerCase().split('.').last;
              if (audioExtensions.any((e) => e.endsWith(ext))) {
                paths.add(entity.path);
              }
            }
          }
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.audio,
          allowMultiple: true,
        );
        if (result != null) {
          paths = result.paths.whereType<String>().toList();
        }
      }

      if (paths.isNotEmpty) {
        _processFiles(paths);
      }
    } catch (e) { /* ignored */ }
  }

  void _processFiles(List<String> paths) {
    if (_selectedGroup == null) return;

    final result = _service.matchFilesToGroup(
      group: _selectedGroup!,
      audioPaths: paths,
    );

    setState(() {
      // Add matched files
      for (final match in result.matched) {
        _entries.add(_FileEntry(
          audioPath: match.audioPath,
          fileName: match.audioFileName,
          selectedStage: match.stage,
          confidence: match.confidence,
          isAccepted: true,
        ));
      }

      // Add unmatched files
      for (final unmatched in result.unmatched) {
        _entries.add(_FileEntry(
          audioPath: unmatched.audioPath,
          fileName: unmatched.audioFileName,
          suggestions: unmatched.suggestions,
        ));
      }
    });
  }

  void _acceptSuggestion(_FileEntry entry, String stage) {
    setState(() {
      entry.selectedStage = stage;
      entry.isAccepted = true;
      entry.confidence = 1.0; // Manual selection = 100%
    });
  }

  void _skipEntry(_FileEntry entry) {
    setState(() {
      entry.isSkipped = true;
      entry.isAccepted = false;
    });
  }

  void _unskipEntry(_FileEntry entry) {
    setState(() {
      entry.isSkipped = false;
    });
  }

  void _clearAll() {
    setState(() {
      _entries.clear();
    });
  }

  void _commitAll() {
    if (_isProcessing) return;

    final toCreate = _entries
        .where((e) => e.selectedStage != null && !e.isSkipped)
        .toList();

    if (toCreate.isEmpty) return;

    setState(() => _isProcessing = true);

    final specs = toCreate.map((entry) {
      // Use proper naming convention: onReelLand1, onWinBig, etc.
      final eventName = generateEventName(entry.selectedStage!);
      return BatchEventSpec(
        eventName: eventName,
        stage: entry.selectedStage!,
        audioPath: entry.audioPath,
      );
    }).toList();

    // Simulate async processing
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.onEventsCreated?.call(specs);

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _entries.clear();
        });

        // Show success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created ${specs.length} events'),
            backgroundColor: FluxForgeTheme.accentGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }
}
