/// DAW Files Browser — P3.1 Hover Preview Integration + P2.1 AudioAssetManager
///
/// Professional file browser for DAW lower zone with:
/// - Audio hover preview (play on 500ms hover)
/// - Folder tree navigation (file system + project pool)
/// - Format filtering
/// - Drag-and-drop to timeline
/// - Search with real-time filter
/// - File metadata display
/// - Integration with AudioAssetManager for project pool

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/audio_asset_manager.dart';
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

  // P2.1: Audio Pool integration
  bool _isPoolMode = false;
  String _selectedPoolFolder = '';
  bool _isPoolExpanded = true;

  // P2.2: Favorites/Bookmarks
  final Set<String> _favoritePaths = {};
  bool _isFavoritesExpanded = true;

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
    // P2.1: Listen to AudioAssetManager changes
    AudioAssetManager.instance.addListener(_onAssetManagerChanged);
  }

  @override
  void dispose() {
    AudioAssetManager.instance.removeListener(_onAssetManagerChanged);
    _searchController.dispose();
    _folderScrollController.dispose();
    _fileScrollController.dispose();
    super.dispose();
  }

  /// P2.1: Called when AudioAssetManager changes
  void _onAssetManagerChanged() {
    if (mounted && _isPoolMode) {
      _loadPoolFiles(_selectedPoolFolder);
    }
  }

  /// P2.1: Load files from AudioAssetManager for given folder
  void _loadPoolFiles(String folder) {
    final manager = AudioAssetManager.instance;
    final assets = folder.isEmpty
        ? manager.assets
        : manager.getByFolder(folder);

    _currentFiles = assets.map((asset) => AudioFileInfo(
      id: asset.id,
      name: asset.name,
      path: asset.path,
      duration: Duration(milliseconds: (asset.duration * 1000).round()),
      format: asset.format.toUpperCase(),
      sampleRate: asset.sampleRate,
      channels: asset.channels,
      bitDepth: 24, // Default
      tags: [],
    )).toList();

    if (mounted) setState(() {});
  }

  /// P2.1: Switch to pool mode and show pool folder
  void _selectPoolFolder(String folder) {
    setState(() {
      _isPoolMode = true;
      _selectedPoolFolder = folder;
      _currentPath = 'Project Pool${folder.isNotEmpty ? ' / $folder' : ''}';
    });
    _loadPoolFiles(folder);
  }

  /// P2.1: Switch back to file system mode
  void _switchToFileSystemMode() {
    setState(() {
      _isPoolMode = false;
      _selectedPoolFolder = '';
    });
    _initializeDirectory();
  }

  /// P2.2: Toggle favorite status of a folder
  void _toggleFavorite(String path) {
    setState(() {
      if (_favoritePaths.contains(path)) {
        _favoritePaths.remove(path);
      } else {
        _favoritePaths.add(path);
      }
    });
  }

  /// P2.2: Check if path is favorited
  bool _isFavorite(String path) => _favoritePaths.contains(path);

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
          : ListView(
              controller: _folderScrollController,
              padding: const EdgeInsets.all(8),
              children: [
                // P2.1: Project Pool section (always at top)
                _buildProjectPoolSection(),
                const Divider(height: 16, color: LowerZoneColors.border),
                // P2.2: Favorites section
                if (_favoritePaths.isNotEmpty) ...[
                  _buildFavoritesSection(),
                  const Divider(height: 16, color: LowerZoneColors.border),
                ],
                // File System section header
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.computer, size: 12, color: LowerZoneColors.textMuted),
                      const SizedBox(width: 6),
                      const Text(
                        'FILE SYSTEM',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: LowerZoneColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // File system folders
                ..._folderTree.map((node) => _buildFolderNode(node)),
              ],
            ),
    );
  }

  /// P2.1: Build the Project Pool section with folders from AudioAssetManager
  Widget _buildProjectPoolSection() {
    final manager = AudioAssetManager.instance;
    final folderNames = manager.folderNames;
    final totalAssets = manager.assetCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pool header
        GestureDetector(
          onTap: () => setState(() => _isPoolExpanded = !_isPoolExpanded),
          child: Row(
            children: [
              Icon(
                _isPoolExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 12,
                color: LowerZoneColors.textMuted,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.folder_special, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text(
                'PROJECT POOL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: LowerZoneColors.dawAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$totalAssets',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.dawAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Pool folders (when expanded)
        if (_isPoolExpanded) ...[
          const SizedBox(height: 4),
          // "All" folder
          _buildPoolFolderNode('', 'All Files', totalAssets),
          // Individual folders
          ...folderNames.map((folder) {
            final count = manager.getByFolder(folder).length;
            return _buildPoolFolderNode(folder, folder, count);
          }),
        ],
      ],
    );
  }

  /// P2.2: Build the Favorites section with bookmarked folders
  Widget _buildFavoritesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Favorites header
        GestureDetector(
          onTap: () => setState(() => _isFavoritesExpanded = !_isFavoritesExpanded),
          child: Row(
            children: [
              Icon(
                _isFavoritesExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 12,
                color: LowerZoneColors.textMuted,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.star, size: 14, color: Colors.amber),
              const SizedBox(width: 6),
              const Text(
                'FAVORITES',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_favoritePaths.length}',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Favorited folders (when expanded)
        if (_isFavoritesExpanded) ...[
          const SizedBox(height: 4),
          ..._favoritePaths.map((path) => _buildFavoriteNode(path)),
        ],
      ],
    );
  }

  /// P2.2: Build a single favorite folder node
  Widget _buildFavoriteNode(String path) {
    final name = p.basename(path);
    final isSelected = !_isPoolMode && _currentPath == path;

    return GestureDetector(
      onTap: () {
        setState(() => _isPoolMode = false);
        _loadDirectory(path);
      },
      child: Container(
        padding: const EdgeInsets.only(
          left: 20,
          top: 4,
          bottom: 4,
          right: 8,
        ),
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amber.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder,
              size: 14,
              color: isSelected
                  ? Colors.amber
                  : LowerZoneColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? LowerZoneColors.textPrimary
                      : LowerZoneColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Remove from favorites button
            GestureDetector(
              onTap: () => _toggleFavorite(path),
              child: const Icon(
                Icons.star,
                size: 12,
                color: Colors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// P2.1: Build a single pool folder node
  Widget _buildPoolFolderNode(String folderId, String name, int count) {
    final isSelected = _isPoolMode && _selectedPoolFolder == folderId;

    return GestureDetector(
      onTap: () => _selectPoolFolder(folderId),
      child: Container(
        padding: const EdgeInsets.only(
          left: 20,
          top: 4,
          bottom: 4,
          right: 8,
        ),
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? LowerZoneColors.dawAccent.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              folderId.isEmpty ? Icons.library_music : Icons.folder,
              size: 14,
              color: isSelected
                  ? LowerZoneColors.dawAccent
                  : LowerZoneColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? LowerZoneColors.textPrimary
                      : LowerZoneColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 9,
                color: isSelected
                    ? LowerZoneColors.dawAccent
                    : LowerZoneColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderNode(_FolderNode node) {
    // Only show as selected if not in pool mode and this folder is selected
    final isSelected = !_isPoolMode && node.isSelected;
    final isFavorited = _isFavorite(node.path);

    return GestureDetector(
      onTap: () {
        // Clear pool mode when selecting file system folder
        setState(() => _isPoolMode = false);
        _loadDirectory(node.path);
      },
      child: Container(
        padding: EdgeInsets.only(
          left: 8 + (node.indent * 12.0),
          top: 4,
          bottom: 4,
          right: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
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
              color: isSelected
                  ? LowerZoneColors.dawAccent
                  : LowerZoneColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? LowerZoneColors.textPrimary
                      : LowerZoneColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // P2.2: Favorite toggle (only for actual folders, not "..")
            if (node.name != '..') ...[
              GestureDetector(
                onTap: () => _toggleFavorite(node.path),
                child: Icon(
                  isFavorited ? Icons.star : Icons.star_border,
                  size: 12,
                  color: isFavorited
                      ? Colors.amber
                      : LowerZoneColors.textMuted.withOpacity(0.5),
                ),
              ),
            ],
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
