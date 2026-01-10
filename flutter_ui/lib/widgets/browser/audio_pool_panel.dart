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

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';
import '../debug/debug_console.dart';

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

    // Debug log to verify duration parsing
    debugLog('Parsing: $name, duration=$duration (raw=$rawDuration)', source: 'AudioPool');

    return AudioFileInfo(
      id: json['id']?.toString() ?? '',
      name: name,
      path: path,
      duration: duration,
      sampleRate: json['sample_rate'] ?? 48000,
      channels: json['channels'] ?? 2,
      bitDepth: json['bit_depth'] ?? 24,
      fileSize: json['file_size'] ?? 0,
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
  final void Function(AudioFileInfo file)? onFileDragStart;
  final void Function(AudioFileInfo file)? onFileDoubleClick;

  const AudioPoolPanel({
    super.key,
    this.onFileSelected,
    this.onFileDragStart,
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

  // Global key for external refresh access
  static final globalKey = GlobalKey<AudioPoolPanelState>();

  @override
  void initState() {
    super.initState();
    _loadFiles();
    // Listen for refresh signals
    audioPoolRefreshNotifier.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    audioPoolRefreshNotifier.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    _loadFiles();
  }

  /// Public method to refresh the audio pool list
  void refresh() {
    debugLog('AudioPoolPanel.refresh() called', source: 'AudioPool');
    _loadFiles();
  }

  void _loadFiles() {
    final json = _ffi.audioPoolList();
    debugLog('AudioPool JSON: $json', source: 'AudioPool');
    final list = jsonDecode(json) as List;
    debugLog('AudioPool parsed ${list.length} entries', source: 'AudioPool');
    setState(() {
      _files = list.map((e) => AudioFileInfo.fromJson(e)).toList();
    });
  }

  List<AudioFileInfo> get _filteredFiles {
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

    return result;
  }

  Future<void> _importFiles() async {
    // TODO: Open file picker dialog and get path
    const path = '/path/to/audio.wav'; // Placeholder until file picker integration
    _ffi.audioPoolImport(path);
    _loadFiles();
  }

  void _removeFile(AudioFileInfo file) {
    if (file.usedInClips.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ReelForgeTheme.bgMid,
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
                _loadFiles();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: ReelForgeTheme.accentRed),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
    } else {
      final clipId = int.tryParse(file.id) ?? 0;
      _ffi.audioPoolRemove(clipId);
      _loadFiles();
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
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          _buildToolbar(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          _buildFilterBar(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildFileList()),
                if (_showPreview && _selectedFile != null) ...[
                  const VerticalDivider(width: 1, color: ReelForgeTheme.borderSubtle),
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
      color: ReelForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.folder_special, color: ReelForgeTheme.accentBlue, size: 18),
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
          Text(
            '${_filteredFiles.length} of ${_files.length} files',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (missingCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ReelForgeTheme.accentRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning, size: 12, color: ReelForgeTheme.accentRed),
                  const SizedBox(width: 4),
                  Text(
                    '$missingCount missing',
                    style: const TextStyle(color: ReelForgeTheme.accentRed, fontSize: 10),
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
            color: _showPreview ? ReelForgeTheme.accentBlue : Colors.white54,
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
      color: ReelForgeTheme.bgMid.withValues(alpha: 0.5),
      child: Row(
        children: [
          // Import button
          ElevatedButton.icon(
            onPressed: _importFiles,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Import', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 26),
            ),
          ),
          const SizedBox(width: 8),
          // Search
          Expanded(
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Search files...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  prefixIcon: Icon(Icons.search, size: 14, color: Colors.white38),
                  prefixIconConstraints: BoxConstraints(minWidth: 24),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sort dropdown
          PopupMenuButton<AudioPoolSortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort, size: 16, color: Colors.white54),
            color: ReelForgeTheme.bgMid,
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (ctx) => [
              _buildSortMenuItem(AudioPoolSortMode.nameAsc, 'Name (A-Z)'),
              _buildSortMenuItem(AudioPoolSortMode.nameDesc, 'Name (Z-A)'),
              _buildSortMenuItem(AudioPoolSortMode.durationAsc, 'Duration (Short)'),
              _buildSortMenuItem(AudioPoolSortMode.durationDesc, 'Duration (Long)'),
              _buildSortMenuItem(AudioPoolSortMode.usageCount, 'Usage Count'),
            ],
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            color: Colors.white54,
            onPressed: _loadFiles,
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
            color: _sortMode == mode ? ReelForgeTheme.accentBlue : Colors.white,
            fontSize: 12,
          )),
          if (_sortMode == mode) ...[
            const Spacer(),
            const Icon(Icons.check, size: 14, color: ReelForgeTheme.accentBlue),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: ReelForgeTheme.bgMid.withValues(alpha: 0.3),
      child: Row(
        children: AudioPoolFilter.values.map((filter) {
          final isSelected = _filter == filter;
          final count = _getFilterCount(filter);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Text('${filter.name.toUpperCase()} ($count)', style: const TextStyle(fontSize: 10)),
              onSelected: (_) => setState(() => _filter = filter),
              backgroundColor: ReelForgeTheme.bgDeep,
              selectedColor: ReelForgeTheme.accentBlue.withValues(alpha: 0.3),
              checkmarkColor: ReelForgeTheme.accentBlue,
              labelStyle: TextStyle(
                color: isSelected ? ReelForgeTheme.accentBlue : Colors.white70,
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

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: files.length,
      itemBuilder: (context, index) => _buildFileItem(files[index]),
    );
  }

  Widget _buildFileItem(AudioFileInfo file) {
    final isSelected = file.id == _selectedFile?.id;
    final isPlayingThis = _isPlaying && isSelected;

    return Draggable<AudioFileInfo>(
      data: file,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ReelForgeTheme.accentBlue.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Icon(Icons.audiotrack, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.name,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      onDragStarted: () => widget.onFileDragStart?.call(file),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedFile = file);
          widget.onFileSelected?.call(file);
        },
        onDoubleTap: () {
          // Double-click creates track + clip in timeline
          widget.onFileDoubleClick?.call(file);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15)
                : ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: file.isMissing
                  ? ReelForgeTheme.accentRed.withValues(alpha: 0.5)
                  : isSelected
                      ? ReelForgeTheme.accentBlue
                      : ReelForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              // Play button
              GestureDetector(
                onTap: () => _togglePreview(file),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isPlayingThis
                        ? ReelForgeTheme.accentGreen
                        : ReelForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isPlayingThis ? Icons.stop : Icons.play_arrow,
                    size: 16,
                    color: isPlayingThis ? Colors.black : Colors.white54,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (file.isMissing)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.warning, size: 12, color: ReelForgeTheme.accentRed),
                          ),
                        Expanded(
                          child: Text(
                            file.name,
                            style: TextStyle(
                              color: file.isMissing ? ReelForgeTheme.accentRed : Colors.white,
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
                              color: ReelForgeTheme.accentGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${file.usedInClips.length}x',
                              style: const TextStyle(color: ReelForgeTheme.accentGreen, fontSize: 9),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              if (file.isMissing)
                IconButton(
                  icon: const Icon(Icons.search, size: 16),
                  color: ReelForgeTheme.accentOrange,
                  onPressed: () => _locateMissingFile(file),
                  tooltip: 'Locate File',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                color: Colors.white38,
                onPressed: () => _removeFile(file),
                tooltip: 'Remove',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final file = _selectedFile!;
    final isPlayingThis = _isPlaying && _selectedFile?.id == file.id;

    return Container(
      color: ReelForgeTheme.bgSurface,
      child: Column(
        children: [
          // Waveform preview
          Container(
            height: 80,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ReelForgeTheme.borderSubtle),
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
                  color: isPlayingThis ? ReelForgeTheme.accentGreen : Colors.white,
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
                      style: const TextStyle(color: ReelForgeTheme.accentGreen, fontSize: 10),
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
