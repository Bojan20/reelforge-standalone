/// DAW Files Browser — P3.1 Hover Preview Integration
///
/// Professional file browser for DAW lower zone with:
/// - Audio hover preview (play on 500ms hover)
/// - Folder tree navigation
/// - Format filtering
/// - Drag-and-drop to timeline
/// - Search with real-time filter
/// - File metadata display

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../slot_lab/audio_hover_preview.dart';
import 'lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DAW FILES BROWSER PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class DawFilesBrowserPanel extends StatefulWidget {
  /// Base directory to browse (null = use last directory or default)
  final String? initialDirectory;

  /// Callback when file is selected
  final void Function(AudioFileInfo file)? onFileSelected;

  /// Callback when file is double-clicked (add to timeline)
  final void Function(AudioFileInfo file)? onFileActivated;

  /// Callback when file is dragged to timeline
  final void Function(AudioFileInfo file)? onFileDragged;

  const DawFilesBrowserPanel({
    super.key,
    this.initialDirectory,
    this.onFileSelected,
    this.onFileActivated,
    this.onFileDragged,
  });

  @override
  State<DawFilesBrowserPanel> createState() => _DawFilesBrowserPanelState();
}

class _DawFilesBrowserPanelState extends State<DawFilesBrowserPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _folderScrollController = ScrollController();
  final ScrollController _fileScrollController = ScrollController();

  String _currentPath = '';
  String _searchQuery = '';
  String _selectedFormat = 'All';
  AudioFileInfo? _selectedFile;
  String? _playingFileId;
  List<_FolderNode> _folderTree = [];
  List<AudioFileInfo> _currentFiles = [];
  bool _isLoading = false;

  static const List<String> _supportedFormats = [
    'wav', 'flac', 'mp3', 'ogg', 'aiff', 'aif', 'm4a'
  ];

  static const List<String> _formatFilters = [
    'All', 'WAV', 'FLAC', 'MP3', 'OGG', 'AIFF'
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initializeDirectory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _folderScrollController.dispose();
    _fileScrollController.dispose();
    super.dispose();
  }

  void _initializeDirectory() {
    final initialDir = widget.initialDirectory ?? _getDefaultDirectory();
    _loadDirectory(initialDir);
  }

  String _getDefaultDirectory() {
    // Try common audio directories
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/Music',
      '$home/Documents/Audio',
      '$home/Desktop',
      home,
    ];

    for (final path in candidates) {
      if (Directory(path).existsSync()) {
        return path;
      }
    }
    return home;
  }

  Future<void> _loadDirectory(String path) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _currentPath = path;
    });

    try {
      // Load folder tree
      _folderTree = await _buildFolderTree(path);

      // Load files in current directory
      _currentFiles = await _loadAudioFiles(path);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentFiles = [];
        });
      }
    }
  }

  Future<List<_FolderNode>> _buildFolderTree(String rootPath) async {
    final nodes = <_FolderNode>[];
    final rootDir = Directory(rootPath);

    if (!rootDir.existsSync()) return nodes;

    // Add parent folder if not at root
    final parentPath = p.dirname(rootPath);
    if (parentPath != rootPath) {
      nodes.add(_FolderNode(
        name: '..',
        path: parentPath,
        isExpanded: false,
        indent: 0,
      ));
    }

    // Add current folder
    nodes.add(_FolderNode(
      name: p.basename(rootPath),
      path: rootPath,
      isExpanded: true,
      indent: 0,
      isSelected: true,
    ));

    // Add subfolders
    try {
      final entries = rootDir.listSync()
        .whereType<Directory>()
        .where((d) => !p.basename(d.path).startsWith('.'))
        .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      for (final dir in entries) {
        nodes.add(_FolderNode(
          name: p.basename(dir.path),
          path: dir.path,
          isExpanded: false,
          indent: 1,
        ));
      }
    } catch (e) {
      // Ignore permission errors
    }

    return nodes;
  }

  Future<List<AudioFileInfo>> _loadAudioFiles(String dirPath) async {
    final files = <AudioFileInfo>[];
    final dir = Directory(dirPath);

    if (!dir.existsSync()) return files;

    try {
      final entries = dir.listSync()
        .whereType<File>()
        .where((f) {
          final ext = p.extension(f.path).toLowerCase().replaceFirst('.', '');
          return _supportedFormats.contains(ext);
        })
        .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      for (final file in entries) {
        final stat = file.statSync();
        final ext = p.extension(file.path).toUpperCase().replaceFirst('.', '');

        files.add(AudioFileInfo(
          id: file.path,
          name: p.basename(file.path),
          path: file.path,
          duration: const Duration(seconds: 5), // Would need FFI to get real duration
          format: ext == 'AIF' ? 'AIFF' : ext,
          sampleRate: 48000, // Would need FFI
          channels: 2, // Would need FFI
          bitDepth: 24, // Would need FFI
          tags: _extractTags(p.basename(file.path)),
        ));
      }
    } catch (e) {
      // Ignore permission errors
    }

    return files;
  }

  List<String> _extractTags(String filename) {
    final tags = <String>[];
    final lower = filename.toLowerCase();

    // Common audio tags
    if (lower.contains('loop')) tags.add('Loop');
    if (lower.contains('one') && lower.contains('shot')) tags.add('OneShot');
    if (lower.contains('drum')) tags.add('Drums');
    if (lower.contains('bass')) tags.add('Bass');
    if (lower.contains('vocal') || lower.contains('vox')) tags.add('Vocal');
    if (lower.contains('synth')) tags.add('Synth');
    if (lower.contains('sfx') || lower.contains('fx')) tags.add('SFX');
    if (lower.contains('ambient')) tags.add('Ambient');

    return tags;
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.toLowerCase());
  }

  List<AudioFileInfo> get _filteredFiles {
    return _currentFiles.where((file) {
      // Format filter
      if (_selectedFormat != 'All' && file.format != _selectedFormat) {
        return false;
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesName = file.name.toLowerCase().contains(_searchQuery);
        final matchesTags = file.tags.any(
          (tag) => tag.toLowerCase().contains(_searchQuery)
        );
        if (!matchesName && !matchesTags) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeep,
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildToolbar(),
          Expanded(
            child: Row(
              children: [
                // Folder tree
                SizedBox(
                  width: 200,
                  child: _buildFolderTreeView(),
                ),
                const VerticalDivider(
                  width: 1,
                  color: LowerZoneColors.border,
                ),
                // File list
                Expanded(child: _buildFileListView()),
              ],
            ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.border),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open, size: 14, color: LowerZoneColors.dawAccent),
          const SizedBox(width: 8),
          const Text(
            'FILES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: LowerZoneColors.dawAccent,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 12),
          // Breadcrumb path
          Expanded(
            child: Text(
              _currentPath,
              style: const TextStyle(
                fontSize: 9,
                color: LowerZoneColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, size: 14),
            color: LowerZoneColors.textMuted,
            onPressed: () => _loadDirectory(_currentPath),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeep,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.border),
        ),
      ),
      child: Row(
        children: [
          // Search field
          Expanded(
            flex: 2,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: LowerZoneColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                        fontSize: 11,
                        color: LowerZoneColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search files...',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: LowerZoneColors.textMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () => _searchController.clear(),
                      child: const Icon(
                        Icons.clear,
                        size: 12,
                        color: LowerZoneColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Format filter chips
          const Text(
            'Format:',
            style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
          ),
          const SizedBox(width: 6),
          ..._formatFilters.map((format) => _buildFormatChip(format)),
        ],
      ),
    );
  }

  Widget _buildFormatChip(String format) {
    final isSelected = _selectedFormat == format;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _selectedFormat = format),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? LowerZoneColors.dawAccent.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected
                  ? LowerZoneColors.dawAccent
                  : LowerZoneColors.border,
              width: 0.5,
            ),
          ),
          child: Text(
            format,
            style: TextStyle(
              fontSize: 9,
              color: isSelected
                  ? LowerZoneColors.dawAccent
                  : LowerZoneColors.textMuted,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderTreeView() {
    return Container(
      color: LowerZoneColors.bgDeepest,
      child: _isLoading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView.builder(
              controller: _folderScrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _folderTree.length,
              itemBuilder: (context, index) {
                final node = _folderTree[index];
                return _buildFolderNode(node);
              },
            ),
    );
  }

  Widget _buildFolderNode(_FolderNode node) {
    return GestureDetector(
      onTap: () => _loadDirectory(node.path),
      child: Container(
        padding: EdgeInsets.only(
          left: 8 + (node.indent * 12.0),
          top: 4,
          bottom: 4,
          right: 8,
        ),
        decoration: BoxDecoration(
          color: node.isSelected
              ? LowerZoneColors.dawAccent.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              node.isExpanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 12,
              color: LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 4),
            Icon(
              node.isExpanded ? Icons.folder_open : Icons.folder,
              size: 14,
              color: node.isSelected
                  ? LowerZoneColors.dawAccent
                  : LowerZoneColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  fontSize: 10,
                  color: node.isSelected
                      ? LowerZoneColors.textPrimary
                      : LowerZoneColors.textSecondary,
                  fontWeight: node.isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileListView() {
    final files = _filteredFiles;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.audio_file,
              size: 40,
              color: LowerZoneColors.textMuted.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No files match your search'
                  : 'No audio files in this folder',
              style: const TextStyle(
                fontSize: 11,
                color: LowerZoneColors.textMuted,
              ),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Supported: WAV, FLAC, MP3, OGG, AIFF',
                style: TextStyle(
                  fontSize: 9,
                  color: LowerZoneColors.textMuted.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _fileScrollController,
      padding: const EdgeInsets.all(8),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: AudioBrowserItem(
            audioInfo: file,
            isSelected: _selectedFile?.id == file.id,
            isPlaying: _playingFileId == file.id,
            onTap: () {
              setState(() => _selectedFile = file);
              widget.onFileSelected?.call(file);
            },
            onDoubleTap: () => widget.onFileActivated?.call(file),
            onPlay: () {
              setState(() => _playingFileId = file.id);
            },
            onStop: () => setState(() => _playingFileId = null),
            onDragStart: (info) => widget.onFileDragged?.call(info),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    final files = _filteredFiles;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(
          top: BorderSide(color: LowerZoneColors.border),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${files.length} files',
            style: const TextStyle(
              fontSize: 9,
              color: LowerZoneColors.textMuted,
            ),
          ),
          if (_selectedFormat != 'All') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: LowerZoneColors.dawAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _selectedFormat,
                style: const TextStyle(
                  fontSize: 8,
                  color: LowerZoneColors.dawAccent,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (_playingFileId != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: LowerZoneColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Playing',
              style: TextStyle(
                fontSize: 9,
                color: LowerZoneColors.success,
              ),
            ),
          ],
          if (_selectedFile != null && _playingFileId == null) ...[
            Text(
              _selectedFile!.name,
              style: const TextStyle(
                fontSize: 9,
                color: LowerZoneColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FOLDER NODE MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _FolderNode {
  final String name;
  final String path;
  final bool isExpanded;
  final int indent;
  final bool isSelected;

  const _FolderNode({
    required this.name,
    required this.path,
    required this.isExpanded,
    required this.indent,
    this.isSelected = false,
  });
}
