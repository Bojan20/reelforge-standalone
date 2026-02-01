// Audio Pool Panel - Professional Media Browser
//
// Complete audio asset management with:
// - File browser with folder navigation
// - Waveform preview
// - Metadata display (duration, sample rate, channels)
// - Search and filtering
// - Drag to timeline
// - Usage tracking (where clips are used)
// - Missing file detection
// - Audio preview playback

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/native_file_picker.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import '../debug/debug_console.dart';
import '../common/fluxforge_search_field.dart';

/// Audio file loading state
/// 0=pending, 1=loading_metadata, 2=metadata_loaded, 3=error, 10=fully_imported
enum AudioLoadState {
  pending(0),
  loadingMetadata(1),
  metadataLoaded(2),
  error(3),
  fullyImported(10);

  final int value;
  const AudioLoadState(this.value);

  static AudioLoadState fromInt(int value) {
    switch (value) {
      case 0: return AudioLoadState.pending;
      case 1: return AudioLoadState.loadingMetadata;
      case 2: return AudioLoadState.metadataLoaded;
      case 3: return AudioLoadState.error;
      case 10: return AudioLoadState.fullyImported;
      default: return AudioLoadState.pending;
    }
  }

  bool get isReady => this == AudioLoadState.metadataLoaded || this == AudioLoadState.fullyImported;
  bool get isLoading => this == AudioLoadState.pending || this == AudioLoadState.loadingMetadata;
}

/// Audio file metadata
class AudioFileInfo {
  final String id;
  final String name;
  final String path;
  final double duration; // seconds
  final int sampleRate;
  final int channels;
  final int bitDepth;
  final int fileSize; // bytes
  final String format; // wav, mp3, flac, etc.
  final AudioLoadState state; // Loading state
  final List<String> usedInClips; // Clip IDs where this file is used
  final bool isMissing;
  final String? waveformData;

  AudioFileInfo({
    required this.id,
    required this.name,
    required this.path,
    this.duration = 0,
    this.sampleRate = 48000,
    this.channels = 2,
    this.bitDepth = 24,
    this.fileSize = 0,
    this.format = 'wav',
    this.state = AudioLoadState.fullyImported,
    this.usedInClips = const [],
    this.isMissing = false,
    this.waveformData,
  });

  factory AudioFileInfo.fromJson(Map<String, dynamic> json) {
    // Extract name from path if not provided
    final path = json['path']?.toString() ?? '';
    final name = json['name']?.toString() ??
        (path.isNotEmpty ? path.split('/').last.split('\\').last : 'Unknown');

    // Parse duration - handle both int and double from JSON
    final rawDuration = json['duration'];
    final duration = rawDuration is int
        ? rawDuration.toDouble()
        : (rawDuration as num?)?.toDouble() ?? 0.0;

    // Parse state
    final stateInt = json['state'] as int? ?? 10;

    return AudioFileInfo(
      id: json['id']?.toString() ?? '',
      name: name,
      path: path,
      duration: duration,
      sampleRate: json['sample_rate'] ?? 48000,
      channels: json['channels'] ?? 2,
      bitDepth: json['bit_depth'] ?? 24,
      fileSize: json['file_size'] ?? 0,
      format: json['format']?.toString() ?? 'wav',
      state: AudioLoadState.fromInt(stateInt),
      usedInClips: List<String>.from(json['used_in_clips'] ?? []),
      isMissing: json['is_missing'] ?? false,
      waveformData: json['waveform_data'],
    );
  }

  String get formattedDuration {
    final mins = (duration / 60).floor();
    final secs = (duration % 60).floor();
    final ms = ((duration % 1) * 100).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get channelsLabel => channels == 1 ? 'Mono' : channels == 2 ? 'Stereo' : '${channels}ch';
}

/// Sort mode for audio pool
enum AudioPoolSortMode {
  nameAsc,
  nameDesc,
  durationAsc,
  durationDesc,
  dateAdded,
  usageCount,
}

/// Filter for audio pool
enum AudioPoolFilter {
  all,
  used,
  unused,
  missing,
}

/// Global notifier to trigger audio pool refresh from anywhere
/// Increment the value to trigger refresh in all listening AudioPoolPanels
final audioPoolRefreshNotifier = ValueNotifier<int>(0);

/// Call this to refresh all audio pool panels
void triggerAudioPoolRefresh() {
  audioPoolRefreshNotifier.value++;
}

/// Audio Pool Panel Widget
class AudioPoolPanel extends StatefulWidget {
  final void Function(AudioFileInfo file)? onFileSelected;
  final void Function(List<AudioFileInfo> files)? onFilesSelected;
  final void Function(AudioFileInfo file)? onFileDragStart;
  final void Function(List<AudioFileInfo> files)? onFilesDragStart;
  final void Function(AudioFileInfo file)? onFileDoubleClick;

  const AudioPoolPanel({
    super.key,
    this.onFileSelected,
    this.onFilesSelected,
    this.onFileDragStart,
    this.onFilesDragStart,
    this.onFileDoubleClick,
  });

  @override
  State<AudioPoolPanel> createState() => AudioPoolPanelState();
}

class AudioPoolPanelState extends State<AudioPoolPanel> {
  final _ffi = NativeFFI.instance;
  List<AudioFileInfo> _files = [];
  String _searchQuery = '';
  AudioPoolSortMode _sortMode = AudioPoolSortMode.nameAsc;
  AudioPoolFilter _filter = AudioPoolFilter.all;
  AudioFileInfo? _selectedFile;
  bool _isPlaying = false;
  bool _showPreview = true;

  // Multi-selection support
  Set<String> _selectedFileIds = {};
  int? _lastSelectedIndex;  // For Shift+click range selection

  // Global key for external refresh access
  static final globalKey = GlobalKey<AudioPoolPanelState>();

  // ═══════════════════════════════════════════════════════════════════════════
  // PERFORMANCE OPTIMIZATION: Cached filtered list + debounced updates
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cached filtered and sorted list (computed only when needed)
  List<AudioFileInfo>? _cachedFilteredFiles;

  /// Cache invalidation key (hash of filter params)
  int _filterCacheKey = 0;

  /// Debounce timer for FFI refresh
  Timer? _refreshDebounceTimer;

  /// Debounce timer for search
  Timer? _searchDebounceTimer;

  /// Last known file count (for smart refresh)
  int _lastFileCount = 0;

  /// Is initial load complete?
  bool _initialLoadComplete = false;

  /// Background loading in progress
  bool _isBackgroundRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadFilesOptimized();
    // Listen for refresh signals with debounce
    audioPoolRefreshNotifier.addListener(_onRefreshSignalDebounced);
  }

  @override
  void dispose() {
    _refreshDebounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    audioPoolRefreshNotifier.removeListener(_onRefreshSignalDebounced);
    super.dispose();
  }

  void _onRefreshSignalDebounced() {
    // Debounce refresh signals — avoid excessive FFI calls
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) _loadFilesOptimized();
    });
  }

  /// Public method to refresh the audio pool list
  void refresh() {
    debugLog('AudioPoolPanel.refresh() called', source: 'AudioPool');
    _loadFilesOptimized();
  }

  /// OPTIMIZED: Load files with smart caching and background refresh
  void _loadFilesOptimized() {
    // Prevent concurrent loads
    if (_isBackgroundRefreshing) return;
    _isBackgroundRefreshing = true;

    // Run FFI call in microtask to not block UI
    Future.microtask(() {
      if (!mounted) {
        _isBackgroundRefreshing = false;
        return;
      }

      try {
        // Get data from FFI
        final json = _ffi.audioPoolListAll();
        final list = jsonDecode(json) as List;
        final newFiles = list.map((e) => AudioFileInfo.fromJson(e)).toList();

        // Check if any pending files are still loading
        final hasLoadingFiles = newFiles.any((f) => f.state.isLoading);

        // Smart update: only setState if data actually changed
        final filesChanged = newFiles.length != _lastFileCount ||
            !_filesListEqual(_files, newFiles);

        if (filesChanged) {
          _lastFileCount = newFiles.length;
          _invalidateFilterCache();

          if (mounted) {
            setState(() {
              _files = newFiles;
              _initialLoadComplete = true;
            });
          }
        }

        _isBackgroundRefreshing = false;

        // Schedule next refresh if files still loading (with longer interval)
        if (hasLoadingFiles && mounted) {
          _refreshDebounceTimer?.cancel();
          _refreshDebounceTimer = Timer(const Duration(milliseconds: 250), () {
            if (mounted) _loadFilesOptimized();
          });
        }
      } catch (e) {
        debugLog('AudioPool load error: $e', source: 'AudioPool');
        _isBackgroundRefreshing = false;
      }
    });
  }

  /// Fast equality check for file lists (by ID only)
  bool _filesListEqual(List<AudioFileInfo> a, List<AudioFileInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].state != b[i].state) return false;
    }
    return true;
  }

  /// Invalidate filter cache (call when filter/sort/search changes)
  void _invalidateFilterCache() {
    _cachedFilteredFiles = null;
    _filterCacheKey++;
  }

  /// Stored hash of last computed filter state
  int _lastComputedCacheHash = 0;

  /// OPTIMIZED: Cached filtered files getter
  List<AudioFileInfo> get _filteredFiles {
    // Compute cache key from current filter state
    final currentCacheKey = Object.hash(
      _filter,
      _sortMode,
      _searchQuery,
      _files.length,
      _filterCacheKey,
    );

    // Return cached if valid (compare hash with stored hash, not with counter)
    if (_cachedFilteredFiles != null && _lastComputedCacheHash == currentCacheKey) {
      return _cachedFilteredFiles!;
    }

    // Compute filtered list
    var result = _files.where((f) {
      // Apply filter
      switch (_filter) {
        case AudioPoolFilter.all:
          break;
        case AudioPoolFilter.used:
          if (f.usedInClips.isEmpty) return false;
          break;
        case AudioPoolFilter.unused:
          if (f.usedInClips.isNotEmpty) return false;
          break;
        case AudioPoolFilter.missing:
          if (!f.isMissing) return false;
          break;
      }

      // Apply search
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return f.name.toLowerCase().contains(query) ||
            f.path.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    // Apply sort
    switch (_sortMode) {
      case AudioPoolSortMode.nameAsc:
        result.sort((a, b) => a.name.compareTo(b.name));
        break;
      case AudioPoolSortMode.nameDesc:
        result.sort((a, b) => b.name.compareTo(a.name));
        break;
      case AudioPoolSortMode.durationAsc:
        result.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case AudioPoolSortMode.durationDesc:
        result.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case AudioPoolSortMode.dateAdded:
        // Would need dateAdded field
        break;
      case AudioPoolSortMode.usageCount:
        result.sort((a, b) => b.usedInClips.length.compareTo(a.usedInClips.length));
        break;
    }

    // Cache result
    _cachedFilteredFiles = result;
    _lastComputedCacheHash = currentCacheKey;

    return result;
  }

  /// DEBOUNCED search handler — waits 150ms before filtering
  void _onSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && _searchQuery != value) {
        _invalidateFilterCache();
        setState(() => _searchQuery = value);
      }
    });
  }

  Future<void> _importFiles() async {
    // Use native file picker for multiple file selection
    final paths = await NativeFilePicker.pickAudioFiles();
    if (paths.isEmpty) return;

    debugLog('Importing ${paths.length} files instantly...', source: 'AudioPool');

    // Use new batch instant import — returns immediately (<1ms per file)
    final ids = _ffi.audioPoolRegisterBatch(paths);
    debugLog('Registered ${ids.length} files instantly', source: 'AudioPool');

    // Immediately refresh UI — files will show with "loading" state
    _loadFilesOptimized();
  }

  /// Get all currently selected files
  List<AudioFileInfo> get selectedFiles {
    return _files.where((f) => _selectedFileIds.contains(f.id)).toList();
  }

  /// Handle file selection with modifier keys
  void _handleFileSelection(AudioFileInfo file, int index, {bool isCtrlPressed = false, bool isShiftPressed = false}) {
    setState(() {
      if (isShiftPressed && _lastSelectedIndex != null) {
        // Range selection: select all files between last selected and current
        final files = _filteredFiles;
        final start = _lastSelectedIndex!.clamp(0, files.length - 1);
        final end = index.clamp(0, files.length - 1);
        final rangeStart = start < end ? start : end;
        final rangeEnd = start < end ? end : start;

        for (var i = rangeStart; i <= rangeEnd; i++) {
          _selectedFileIds.add(files[i].id);
        }
      } else if (isCtrlPressed) {
        // Toggle selection
        if (_selectedFileIds.contains(file.id)) {
          _selectedFileIds.remove(file.id);
        } else {
          _selectedFileIds.add(file.id);
        }
        _lastSelectedIndex = index;
      } else {
        // Single selection - clear others
        _selectedFileIds.clear();
        _selectedFileIds.add(file.id);
        _lastSelectedIndex = index;
      }

      // Update single selected file for preview
      _selectedFile = file;
    });

    // Notify callbacks
    widget.onFileSelected?.call(file);
    if (_selectedFileIds.length > 1) {
      widget.onFilesSelected?.call(selectedFiles);
    }
  }

  /// Select all files (Ctrl+A)
  void _selectAll() {
    setState(() {
      _selectedFileIds = _filteredFiles.map((f) => f.id).toSet();
      if (_filteredFiles.isNotEmpty) {
        _selectedFile = _filteredFiles.first;
      }
    });
    widget.onFilesSelected?.call(selectedFiles);
  }

  /// Clear selection
  void _clearSelection() {
    setState(() {
      _selectedFileIds.clear();
      _selectedFile = null;
      _lastSelectedIndex = null;
    });
  }

  /// Remove multiple selected files
  void _removeSelectedFiles() {
    final filesToRemove = selectedFiles;
    if (filesToRemove.isEmpty) return;

    final usedCount = filesToRemove.where((f) => f.usedInClips.isNotEmpty).length;

    if (usedCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          title: const Text('Files In Use', style: TextStyle(color: Colors.white)),
          content: Text(
            '$usedCount of ${filesToRemove.length} files are in use. Remove all ${filesToRemove.length} files anyway?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                for (final file in filesToRemove) {
                  final clipId = int.tryParse(file.id) ?? 0;
                  _ffi.audioPoolRemove(clipId);
                }
                _clearSelection();
                _loadFilesOptimized();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: FluxForgeTheme.accentRed),
              child: Text('Remove ${filesToRemove.length}'),
            ),
          ],
        ),
      );
    } else {
      // No files in use, just confirm
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          title: const Text('Remove Files', style: TextStyle(color: Colors.white)),
          content: Text(
            'Remove ${filesToRemove.length} selected files from pool?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                for (final file in filesToRemove) {
                  final clipId = int.tryParse(file.id) ?? 0;
                  _ffi.audioPoolRemove(clipId);
                }
                _clearSelection();
                _loadFilesOptimized();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: FluxForgeTheme.accentRed),
              child: Text('Remove ${filesToRemove.length}'),
            ),
          ],
        ),
      );
    }
  }

  void _removeFile(AudioFileInfo file) {
    if (file.usedInClips.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          title: const Text('File In Use', style: TextStyle(color: Colors.white)),
          content: Text(
            '"${file.name}" is used in ${file.usedInClips.length} clip(s). Remove anyway?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final clipId = int.tryParse(file.id) ?? 0;
                _ffi.audioPoolRemove(clipId);
                _loadFilesOptimized();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: FluxForgeTheme.accentRed),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
    } else {
      final clipId = int.tryParse(file.id) ?? 0;
      _ffi.audioPoolRemove(clipId);
      _loadFilesOptimized();
    }
  }

  void _togglePreview(AudioFileInfo file) {
    final clipId = int.tryParse(file.id) ?? 0;
    if (_isPlaying && _selectedFile?.id == file.id) {
      _ffi.audioPoolStopPreview();
      setState(() => _isPlaying = false);
    } else {
      _ffi.audioPoolPlayPreview(clipId);
      setState(() {
        _selectedFile = file;
        _isPlaying = true;
      });
    }
  }

  Future<void> _locateMissingFile(AudioFileInfo file) async {
    // TODO: Open file picker dialog to locate new path
    const newPath = '/path/to/located/audio.wav'; // Placeholder until file picker integration
    final clipId = int.tryParse(file.id) ?? 0;
    _ffi.audioPoolLocate(clipId, newPath);
    _loadFilesOptimized();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          _buildToolbar(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          _buildFilterBar(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildFileList()),
                if (_showPreview && _selectedFile != null) ...[
                  const VerticalDivider(width: 1, color: FluxForgeTheme.borderSubtle),
                  SizedBox(
                    width: 240,
                    child: _buildPreviewPanel(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final missingCount = _files.where((f) => f.isMissing).length;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.folder_special, color: FluxForgeTheme.accentBlue, size: 18),
          const SizedBox(width: 8),
          const Text(
            'AUDIO POOL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_selectedFileIds.length > 1) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_selectedFileIds.length} selected',
                style: const TextStyle(color: FluxForgeTheme.accentBlue, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${_filteredFiles.length} of ${_files.length} files',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (missingCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning, size: 12, color: FluxForgeTheme.accentRed),
                  const SizedBox(width: 4),
                  Text(
                    '$missingCount missing',
                    style: const TextStyle(color: FluxForgeTheme.accentRed, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(
              _showPreview ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              size: 16,
            ),
            color: _showPreview ? FluxForgeTheme.accentBlue : Colors.white54,
            onPressed: () => setState(() => _showPreview = !_showPreview),
            tooltip: 'Toggle Preview',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
      child: Row(
        children: [
          // Import button
          ElevatedButton.icon(
            onPressed: _importFiles,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Import', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 26),
            ),
          ),
          const SizedBox(width: 8),
          // Search — DEBOUNCED for performance
          Expanded(
            child: FluxForgeSearchField(
              hintText: 'Search files...',
              onChanged: _onSearchChanged,
              onCleared: () {
                _searchDebounceTimer?.cancel();
                setState(() {
                  _searchQuery = '';
                  _invalidateFilterCache();
                });
              },
              style: FluxForgeSearchFieldStyle.compact,
            ),
          ),
          const SizedBox(width: 8),
          // Sort dropdown
          PopupMenuButton<AudioPoolSortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort, size: 16, color: Colors.white54),
            color: FluxForgeTheme.bgMid,
            onSelected: (mode) {
              _invalidateFilterCache();
              setState(() => _sortMode = mode);
            },
            itemBuilder: (ctx) => [
              _buildSortMenuItem(AudioPoolSortMode.nameAsc, 'Name (A-Z)'),
              _buildSortMenuItem(AudioPoolSortMode.nameDesc, 'Name (Z-A)'),
              _buildSortMenuItem(AudioPoolSortMode.durationAsc, 'Duration (Short)'),
              _buildSortMenuItem(AudioPoolSortMode.durationDesc, 'Duration (Long)'),
              _buildSortMenuItem(AudioPoolSortMode.usageCount, 'Usage Count'),
            ],
          ),
          // Delete selected (visible when multiple selected)
          if (_selectedFileIds.length > 1) ...[
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: _removeSelectedFiles,
              icon: const Icon(Icons.delete_outline, size: 14),
              label: Text('Delete (${_selectedFileIds.length})', style: const TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxForgeTheme.accentRed.withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 26),
              ),
            ),
          ],
          const SizedBox(width: 4),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            color: Colors.white54,
            onPressed: _loadFilesOptimized,
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<AudioPoolSortMode> _buildSortMenuItem(AudioPoolSortMode mode, String label) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Text(label, style: TextStyle(
            color: _sortMode == mode ? FluxForgeTheme.accentBlue : Colors.white,
            fontSize: 12,
          )),
          if (_sortMode == mode) ...[
            const Spacer(),
            const Icon(Icons.check, size: 14, color: FluxForgeTheme.accentBlue),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.bgMid.withValues(alpha: 0.3),
      child: Row(
        children: AudioPoolFilter.values.map((filter) {
          final isSelected = _filter == filter;
          final count = _getFilterCount(filter);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Text('${filter.name.toUpperCase()} ($count)', style: const TextStyle(fontSize: 10)),
              onSelected: (_) {
                _invalidateFilterCache();
                setState(() => _filter = filter);
              },
              backgroundColor: FluxForgeTheme.bgDeep,
              selectedColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
              checkmarkColor: FluxForgeTheme.accentBlue,
              labelStyle: TextStyle(
                color: isSelected ? FluxForgeTheme.accentBlue : Colors.white70,
              ),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  int _getFilterCount(AudioPoolFilter filter) {
    switch (filter) {
      case AudioPoolFilter.all:
        return _files.length;
      case AudioPoolFilter.used:
        return _files.where((f) => f.usedInClips.isNotEmpty).length;
      case AudioPoolFilter.unused:
        return _files.where((f) => f.usedInClips.isEmpty).length;
      case AudioPoolFilter.missing:
        return _files.where((f) => f.isMissing).length;
    }
  }

  Widget _buildFileList() {
    final files = _filteredFiles;

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? 'No files match your search' : 'No audio files in pool',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Click "Import" to add audio files',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Ctrl+A / Cmd+A to select all
          if ((HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) &&
              event.logicalKey == LogicalKeyboardKey.keyA) {
            _selectAll();
            return KeyEventResult.handled;
          }
          // Delete/Backspace to remove selected
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_selectedFileIds.isNotEmpty) {
              _removeSelectedFiles();
              return KeyEventResult.handled;
            }
          }
          // Escape to clear selection
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _clearSelection();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      // PERFORMANCE: Use fixed itemExtent for O(1) layout calculation
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: files.length,
        itemExtent: 68, // Fixed height: 60px content + 4px margin + 4px padding
        // PERFORMANCE: Use addAutomaticKeepAlives: false to reduce memory
        addAutomaticKeepAlives: false,
        // PERFORMANCE: Use addRepaintBoundaries for isolation
        addRepaintBoundaries: true,
        itemBuilder: (context, index) => _AudioFileListItem(
          key: ValueKey(files[index].id),
          file: files[index],
          index: index,
          isSelected: _selectedFileIds.contains(files[index].id),
          isMultiSelected: _selectedFileIds.length > 1,
          isPlaying: _isPlaying && _selectedFile?.id == files[index].id,
          selectedFiles: _selectedFileIds.length > 1 ? selectedFiles : null,
          onSelect: _handleFileSelection,
          onDoubleClick: widget.onFileDoubleClick,
          onTogglePreview: _togglePreview,
          onRemove: _removeFile,
          onLocate: _locateMissingFile,
          onDragStart: (files) {
            if (files.length > 1) {
              widget.onFilesDragStart?.call(files);
            } else {
              widget.onFileDragStart?.call(files.first);
            }
          },
        ),
      ),
    );
  }

  // _buildFileItem removed - replaced with _AudioFileListItem widget below

  Widget _buildPreviewPanel() {
    final file = _selectedFile!;
    final isPlayingThis = _isPlaying && _selectedFile?.id == file.id;

    return Container(
      color: FluxForgeTheme.bgSurface,
      child: Column(
        children: [
          // Waveform preview
          Container(
            height: 80,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: Center(
              child: Icon(
                Icons.graphic_eq,
                size: 32,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          // Play controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    isPlayingThis ? Icons.stop : Icons.play_arrow,
                    size: 32,
                  ),
                  color: isPlayingThis ? FluxForgeTheme.accentGreen : Colors.white,
                  onPressed: () => _togglePreview(file),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // File info
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Duration', file.formattedDuration),
                  _buildInfoRow('Sample Rate', '${file.sampleRate} Hz'),
                  _buildInfoRow('Channels', file.channelsLabel),
                  _buildInfoRow('Bit Depth', '${file.bitDepth}-bit'),
                  _buildInfoRow('File Size', file.formattedSize),
                  const SizedBox(height: 12),
                  const Text('Path', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    file.path,
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (file.usedInClips.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Used in ${file.usedInClips.length} clip(s)',
                      style: const TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'JetBrains Mono')),
        ],
      ),
    );
  }
}

/// PERFORMANCE OPTIMIZED: Extracted to separate StatelessWidget
/// - Uses const constructors where possible
/// - Avoids rebuilding parent on hover/selection
/// - Deferred drag feedback creation (only when dragging)
/// - RepaintBoundary isolation
class _AudioFileListItem extends StatelessWidget {
  final AudioFileInfo file;
  final int index;
  final bool isSelected;
  final bool isMultiSelected;
  final bool isPlaying;
  final List<AudioFileInfo>? selectedFiles;
  final void Function(AudioFileInfo file, int index, {bool isCtrlPressed, bool isShiftPressed}) onSelect;
  final void Function(AudioFileInfo file)? onDoubleClick;
  final void Function(AudioFileInfo file) onTogglePreview;
  final void Function(AudioFileInfo file) onRemove;
  final void Function(AudioFileInfo file) onLocate;
  final void Function(List<AudioFileInfo> files) onDragStart;

  const _AudioFileListItem({
    super.key,
    required this.file,
    required this.index,
    required this.isSelected,
    required this.isMultiSelected,
    required this.isPlaying,
    required this.selectedFiles,
    required this.onSelect,
    required this.onDoubleClick,
    required this.onTogglePreview,
    required this.onRemove,
    required this.onLocate,
    required this.onDragStart,
  });

  @override
  Widget build(BuildContext context) {
    // PERFORMANCE: Calculate once, reuse
    final filesToDrag = isSelected && isMultiSelected && selectedFiles != null
        ? selectedFiles!
        : [file];

    return RepaintBoundary(
      child: Draggable<List<AudioFileInfo>>(
        data: filesToDrag,
        // PERFORMANCE: Deferred feedback - only created when actually dragging
        feedback: _DragFeedback(files: filesToDrag, fileName: file.name),
        onDragStarted: () {
          onDragStart(filesToDrag);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            // PERFORMANCE: Check modifiers synchronously
            final isCtrl = HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed;
            final isShift = HardwareKeyboard.instance.isShiftPressed;
            onSelect(file, index, isCtrlPressed: isCtrl, isShiftPressed: isShift);
          },
          onDoubleTap: () => onDoubleClick?.call(file),
          child: Container(
            height: 60,
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isMultiSelected
                      ? const Color(0xFF2A4A6A) // FluxForgeTheme.accentBlue @ 0.25
                      : const Color(0xFF1E3A5A)) // FluxForgeTheme.accentBlue @ 0.15
                  : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: file.isMissing
                    ? const Color(0x80FF4060) // FluxForgeTheme.accentRed @ 0.5
                    : isSelected
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.borderSubtle,
                width: isSelected && isMultiSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Play button - isolated with its own GestureDetector
                _PlayButton(
                  isPlaying: isPlaying,
                  onTap: () => onTogglePreview(file),
                ),
                const SizedBox(width: 10),
                // File info - const where possible
                Expanded(
                  child: _FileInfo(file: file),
                ),
                // Actions - only shown when needed
                if (file.isMissing)
                  _ActionButton(
                    icon: Icons.search,
                    color: FluxForgeTheme.accentOrange,
                    tooltip: 'Locate File',
                    onTap: () => onLocate(file),
                  ),
                _ActionButton(
                  icon: Icons.delete_outline,
                  color: Colors.white38,
                  tooltip: 'Remove',
                  onTap: () => onRemove(file),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// PERFORMANCE: Isolated play button to minimize repaints
class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isPlaying ? FluxForgeTheme.accentGreen : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          isPlaying ? Icons.stop : Icons.play_arrow,
          size: 16,
          color: isPlaying ? Colors.black : Colors.white54,
        ),
      ),
    );
  }
}

/// PERFORMANCE: File info extracted - mostly static content
class _FileInfo extends StatelessWidget {
  final AudioFileInfo file;

  const _FileInfo({required this.file});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            if (file.isMissing)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.warning, size: 12, color: FluxForgeTheme.accentRed),
              ),
            Expanded(
              child: Text(
                file.name,
                style: TextStyle(
                  color: file.isMissing ? FluxForgeTheme.accentRed : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              file.formattedDuration,
              style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'JetBrains Mono'),
            ),
            const SizedBox(width: 8),
            Text(
              '${file.sampleRate ~/ 1000}kHz',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(width: 8),
            Text(
              file.channelsLabel,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const Spacer(),
            if (file.usedInClips.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${file.usedInClips.length}x',
                  style: const TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 9),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// PERFORMANCE: Minimal action button
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

/// PERFORMANCE: Drag feedback - only created when actually dragging
class _DragFeedback extends StatelessWidget {
  final List<AudioFileInfo> files;
  final String fileName;

  const _DragFeedback({required this.files, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(Icons.audiotrack, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: files.length > 1
                  ? Text(
                      '${files.length} files',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      fileName,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            if (files.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${files.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
