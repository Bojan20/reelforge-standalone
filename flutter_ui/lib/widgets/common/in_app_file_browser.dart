/// In-App File Browser — Cubase/Pro Tools Style
///
/// Complete file browser dialog that uses dart:io for directory listing,
/// completely bypassing NSOpenPanel which deadlocks when iCloud
/// Desktop & Documents sync has quota exceeded.
///
/// Usage:
///   final paths = await InAppFileBrowser.pickAudioFiles(context);
///   final folder = await InAppFileBrowser.pickDirectory(context);

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Audio file extensions we support
const _audioExtensions = {
  'wav', 'wave', 'aiff', 'aif', 'aifc', 'flac', 'alac', 'mp3',
  'ogg', 'oga', 'opus', 'aac', 'm4a', 'wma', 'caf', 'w64',
  'rf64', 'bwf', 'sd2', 'au', 'snd', 'raw', 'pcm',
  'ape', 'wv', 'tta',
};

bool _isAudioFile(String path) {
  final ext = p.extension(path).toLowerCase().replaceAll('.', '');
  return _audioExtensions.contains(ext);
}

/// Entry point — static methods for easy usage
class InAppFileBrowser {
  InAppFileBrowser._();

  /// Pick one or more audio files. Returns list of absolute paths, or empty list if cancelled.
  static Future<List<String>> pickAudioFiles(
    BuildContext context, {
    String title = 'Select Audio Files',
    bool allowMultiple = true,
  }) async {
    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FileBrowserDialog(
        title: title,
        mode: _BrowseMode.pickFiles,
        allowMultiple: allowMultiple,
        fileFilter: _isAudioFile,
      ),
    );
    return result ?? [];
  }

  /// Pick a directory. Returns absolute path, or null if cancelled.
  static Future<String?> pickDirectory(
    BuildContext context, {
    String title = 'Select Folder',
  }) async {
    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FileBrowserDialog(
        title: title,
        mode: _BrowseMode.pickDirectory,
        allowMultiple: false,
        fileFilter: null,
      ),
    );
    return result?.isNotEmpty == true ? result!.first : null;
  }

  /// Pick any files with custom filter.
  static Future<List<String>> pickFiles(
    BuildContext context, {
    String title = 'Select Files',
    bool allowMultiple = true,
    Set<String>? allowedExtensions,
  }) async {
    bool filter(String path) {
      if (allowedExtensions == null) return true;
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      return allowedExtensions.contains(ext);
    }

    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FileBrowserDialog(
        title: title,
        mode: _BrowseMode.pickFiles,
        allowMultiple: allowMultiple,
        fileFilter: filter,
      ),
    );
    return result ?? [];
  }

  /// Save file — pick a directory and return full path with filename.
  static Future<String?> saveFile(
    BuildContext context, {
    String title = 'Save File',
    String? suggestedName,
  }) async {
    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FileBrowserDialog(
        title: title,
        mode: _BrowseMode.saveFile,
        allowMultiple: false,
        fileFilter: null,
        suggestedFileName: suggestedName,
      ),
    );
    return result?.isNotEmpty == true ? result!.first : null;
  }
}

enum _BrowseMode { pickFiles, pickDirectory, saveFile }

/// Quick-access bookmark
class _Bookmark {
  final String label;
  final String path;
  final IconData icon;
  const _Bookmark(this.label, this.path, this.icon);
}

class _FileBrowserDialog extends StatefulWidget {
  final String title;
  final _BrowseMode mode;
  final bool allowMultiple;
  final bool Function(String)? fileFilter;
  final String? suggestedFileName;

  const _FileBrowserDialog({
    required this.title,
    required this.mode,
    required this.allowMultiple,
    this.fileFilter,
    this.suggestedFileName,
  });

  @override
  State<_FileBrowserDialog> createState() => _FileBrowserDialogState();
}

class _FileBrowserDialogState extends State<_FileBrowserDialog> {
  late String _currentPath;
  List<FileSystemEntity> _entries = [];
  final Set<String> _selected = {};
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;
  final _searchController = TextEditingController();
  final _fileNameController = TextEditingController();
  final _pathController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showHidden = false;
  _SortMode _sortMode = _SortMode.name;
  bool _sortAscending = true;
  final List<String> _navigationHistory = [];
  int _historyIndex = -1;

  late final List<_Bookmark> _bookmarks;

  @override
  void initState() {
    super.initState();
    final home = Platform.environment['HOME'] ?? '/Users/vanvinklstudio';

    // Build bookmarks — only include directories that exist and are NOT iCloud-controlled
    _bookmarks = [
      _Bookmark('Home', home, Icons.home),
      _Bookmark('Music', '$home/Music', Icons.music_note),
      _Bookmark('Downloads', '$home/Downloads', Icons.download),
      _Bookmark('Projects', '$home/Projects', Icons.folder_special),
      _Bookmark('Volumes', '/Volumes', Icons.storage),
    ];

    // Start in ~/Music if it exists, otherwise home
    final musicDir = Directory('$home/Music');
    _currentPath = musicDir.existsSync() ? musicDir.path : home;

    if (widget.suggestedFileName != null) {
      _fileNameController.text = widget.suggestedFileName!;
    }

    _navigateTo(_currentPath);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fileNameController.dispose();
    _pathController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateTo(String path, {bool addToHistory = true}) {
    if (addToHistory) {
      // Trim forward history
      if (_historyIndex < _navigationHistory.length - 1) {
        _navigationHistory.removeRange(_historyIndex + 1, _navigationHistory.length);
      }
      _navigationHistory.add(path);
      _historyIndex = _navigationHistory.length - 1;
    }

    setState(() {
      _currentPath = path;
      _pathController.text = path;
      _isLoading = true;
      _error = null;
    });

    _loadDirectory(path);
  }

  Future<void> _loadDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        setState(() {
          _entries = [];
          _isLoading = false;
          _error = 'Directory does not exist';
        });
        return;
      }

      final entities = <FileSystemEntity>[];
      await for (final entity in dir.list(followLinks: false)) {
        entities.add(entity);
      }

      if (!mounted) return;
      setState(() {
        _entries = entities;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _isLoading = false;
        _error = 'Cannot access: ${e.toString().split('\n').first}';
      });
    }
  }

  void _goBack() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _navigateTo(_navigationHistory[_historyIndex], addToHistory: false);
    }
  }

  void _goForward() {
    if (_historyIndex < _navigationHistory.length - 1) {
      _historyIndex++;
      _navigateTo(_navigationHistory[_historyIndex], addToHistory: false);
    }
  }

  void _goUp() {
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath) {
      _navigateTo(parent);
    }
  }

  List<FileSystemEntity> get _filteredEntries {
    var filtered = _entries.where((e) {
      final name = p.basename(e.path);
      // Hide hidden files unless toggled
      if (!_showHidden && name.startsWith('.')) return false;
      // Hide AppleDouble files
      if (name.startsWith('._')) return false;
      // Search filter
      if (_searchQuery.isNotEmpty) {
        if (!name.toLowerCase().contains(_searchQuery.toLowerCase())) return false;
      }
      // In pickFiles mode, show directories always + filtered files
      if (widget.mode == _BrowseMode.pickFiles && e is File) {
        return widget.fileFilter?.call(e.path) ?? true;
      }
      return true;
    }).toList();

    // Sort: directories first, then by selected mode
    filtered.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) return aIsDir ? -1 : 1;

      final aName = p.basename(a.path);
      final bName = p.basename(b.path);
      int cmp;
      switch (_sortMode) {
        case _SortMode.name:
          cmp = aName.toLowerCase().compareTo(bName.toLowerCase());
        case _SortMode.size:
          final aSize = a is File ? (a.statSync().size) : 0;
          final bSize = b is File ? (b.statSync().size) : 0;
          cmp = aSize.compareTo(bSize);
        case _SortMode.date:
          final aMod = a.statSync().modified;
          final bMod = b.statSync().modified;
          cmp = aMod.compareTo(bMod);
        case _SortMode.type:
          final aExt = p.extension(aName).toLowerCase();
          final bExt = p.extension(bName).toLowerCase();
          cmp = aExt.compareTo(bExt);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        if (!widget.allowMultiple) _selected.clear();
        _selected.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final e in _filteredEntries) {
        if (e is File) _selected.add(e.path);
      }
    });
  }

  void _confirm() {
    if (widget.mode == _BrowseMode.pickDirectory) {
      Navigator.of(context).pop([_currentPath]);
    } else if (widget.mode == _BrowseMode.saveFile) {
      final name = _fileNameController.text.trim();
      if (name.isNotEmpty) {
        Navigator.of(context).pop([p.join(_currentPath, name)]);
      }
    } else {
      if (_selected.isNotEmpty) {
        Navigator.of(context).pop(_selected.toList());
      }
    }
  }

  void _cancel() {
    Navigator.of(context).pop(null);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  IconData _iconForFile(String path) {
    if (_isAudioFile(path)) return Icons.audiotrack;
    final ext = p.extension(path).toLowerCase();
    if (ext == '.json') return Icons.data_object;
    if (ext == '.pdf') return Icons.picture_as_pdf;
    if ({'.png', '.jpg', '.jpeg', '.gif', '.bmp'}.contains(ext)) return Icons.image;
    return Icons.insert_drive_file;
  }

  Color _colorForExt(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'wav':
      case 'wave':
        return const Color(0xFF4A9EFF);
      case 'mp3':
        return const Color(0xFFFF9040);
      case 'flac':
        return const Color(0xFF40FF90);
      case 'ogg':
      case 'oga':
      case 'opus':
        return const Color(0xFF9370DB);
      case 'aiff':
      case 'aif':
        return const Color(0xFF40C8FF);
      case 'aac':
      case 'm4a':
        return const Color(0xFFFFD700);
      default:
        return const Color(0xFF808080);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF4A9EFF);
    final bgDeep = const Color(0xFF121216);
    final bgMid = const Color(0xFF1a1a20);
    final bgSurface = const Color(0xFF242430);
    final textPrimary = Colors.white;
    final textSecondary = Colors.white60;

    return Dialog(
      backgroundColor: bgDeep,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _cancel();
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              _confirm();
            } else if (event.logicalKey == LogicalKeyboardKey.backspace &&
                HardwareKeyboard.instance.isMetaPressed) {
              _goUp();
            }
          }
        },
        child: SizedBox(
          width: 900,
          height: 620,
          child: Column(
            children: [
              // ═══ TITLE BAR ═══
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.mode == _BrowseMode.pickDirectory
                          ? Icons.folder_open
                          : widget.mode == _BrowseMode.saveFile
                              ? Icons.save
                              : Icons.audiotrack,
                      color: accentColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(widget.title,
                        style: TextStyle(
                            color: textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    // Close button
                    InkWell(
                      onTap: _cancel,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, color: textSecondary, size: 18),
                      ),
                    ),
                  ],
                ),
              ),

              // ═══ TOOLBAR ═══
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: bgMid,
                child: Row(
                  children: [
                    // Nav buttons
                    _toolButton(Icons.arrow_back, 'Back', _goBack,
                        enabled: _historyIndex > 0),
                    _toolButton(Icons.arrow_forward, 'Forward', _goForward,
                        enabled: _historyIndex < _navigationHistory.length - 1),
                    _toolButton(Icons.arrow_upward, 'Up', _goUp),
                    const SizedBox(width: 8),
                    // Path bar
                    Expanded(
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: bgDeep,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          controller: _pathController,
                          style: TextStyle(color: textPrimary, fontSize: 12),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                          ),
                          onSubmitted: (path) {
                            if (Directory(path).existsSync()) {
                              _navigateTo(path);
                            } else if (File(path).existsSync()) {
                              _navigateTo(p.dirname(path));
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Search
                    SizedBox(
                      width: 160,
                      height: 28,
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(color: textSecondary, fontSize: 12),
                          prefixIcon: Icon(Icons.search, size: 16, color: textSecondary),
                          filled: true,
                          fillColor: bgDeep,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.white12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.white12),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ],
                ),
              ),

              // ═══ MAIN CONTENT ═══
              Expanded(
                child: Row(
                  children: [
                    // ── Sidebar (bookmarks) ──
                    Container(
                      width: 160,
                      color: bgMid.withOpacity(0.5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                            child: Text('LOCATIONS',
                                style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1)),
                          ),
                          for (final bm in _bookmarks)
                            if (Directory(bm.path).existsSync())
                              _bookmarkItem(bm, accentColor, textPrimary, textSecondary),
                          const Divider(color: Colors.white12, height: 16),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                            child: Text('VOLUMES',
                                style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1)),
                          ),
                          // List mounted volumes
                          FutureBuilder<List<FileSystemEntity>>(
                            future: Directory('/Volumes').list().toList(),
                            builder: (ctx, snap) {
                              if (!snap.hasData) return const SizedBox.shrink();
                              return Column(
                                children: snap.data!
                                    .whereType<Directory>()
                                    .where((d) => !p.basename(d.path).startsWith('.'))
                                    .map((d) => _bookmarkItem(
                                          _Bookmark(p.basename(d.path), d.path, Icons.storage),
                                          accentColor,
                                          textPrimary,
                                          textSecondary,
                                        ))
                                    .toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // ── File list ──
                    Expanded(
                      child: Column(
                        children: [
                          // Column headers
                          Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            color: bgSurface,
                            child: Row(
                              children: [
                                _columnHeader('Name', _SortMode.name, flex: 4),
                                _columnHeader('Size', _SortMode.size, flex: 1),
                                _columnHeader('Date', _SortMode.date, flex: 2),
                                _columnHeader('Type', _SortMode.type, flex: 1),
                              ],
                            ),
                          ),
                          // File list
                          Expanded(
                            child: _isLoading
                                ? Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: accentColor))
                                : _error != null
                                    ? Center(
                                        child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.error_outline,
                                              color: Colors.red[300], size: 32),
                                          const SizedBox(height: 8),
                                          Text(_error!,
                                              style: TextStyle(
                                                  color: Colors.red[300], fontSize: 12)),
                                        ],
                                      ))
                                    : _filteredEntries.isEmpty
                                        ? Center(
                                            child: Text(
                                            widget.mode == _BrowseMode.pickFiles
                                                ? 'No audio files in this folder'
                                                : 'Empty folder',
                                            style: TextStyle(color: textSecondary, fontSize: 13),
                                          ))
                                        : ListView.builder(
                                            controller: _scrollController,
                                            itemCount: _filteredEntries.length,
                                            itemExtent: 30,
                                            itemBuilder: (ctx, i) {
                                              final entity = _filteredEntries[i];
                                              return _fileRow(entity, accentColor, bgDeep,
                                                  bgSurface, textPrimary, textSecondary);
                                            },
                                          ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ═══ SAVE FILE NAME (save mode only) ═══
              if (widget.mode == _BrowseMode.saveFile)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: bgMid,
                  child: Row(
                    children: [
                      Text('File name: ',
                          style: TextStyle(color: textSecondary, fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 28,
                          child: TextField(
                            controller: _fileNameController,
                            style: TextStyle(color: textPrimary, fontSize: 12),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: bgDeep,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: Colors.white12),
                              ),
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ═══ BOTTOM BAR ═══
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    // Hidden files toggle
                    InkWell(
                      onTap: () => setState(() => _showHidden = !_showHidden),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showHidden ? Icons.visibility : Icons.visibility_off,
                            size: 14,
                            color: textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text('Hidden',
                              style: TextStyle(color: textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Selection count
                    if (widget.mode == _BrowseMode.pickFiles) ...[
                      Text(
                        _selected.isEmpty
                            ? 'No files selected'
                            : '${_selected.length} file${_selected.length > 1 ? 's' : ''} selected',
                        style: TextStyle(color: textSecondary, fontSize: 11),
                      ),
                      if (widget.allowMultiple && _filteredEntries.any((e) => e is File)) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _selectAll,
                          child: Text('Select All',
                              style: TextStyle(
                                  color: accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                    if (widget.mode == _BrowseMode.pickDirectory)
                      Text(
                        'Current: ${p.basename(_currentPath)}',
                        style: TextStyle(color: textSecondary, fontSize: 11),
                      ),
                    const Spacer(),
                    // Cancel
                    TextButton(
                      onPressed: _cancel,
                      child:
                          Text('Cancel', style: TextStyle(color: textSecondary, fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    // Confirm
                    ElevatedButton(
                      onPressed: _canConfirm ? _confirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: accentColor.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text(
                        widget.mode == _BrowseMode.pickDirectory
                            ? 'Select Folder'
                            : widget.mode == _BrowseMode.saveFile
                                ? 'Save'
                                : 'Open',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canConfirm {
    if (widget.mode == _BrowseMode.pickDirectory) return true;
    if (widget.mode == _BrowseMode.saveFile) {
      return _fileNameController.text.trim().isNotEmpty;
    }
    return _selected.isNotEmpty;
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback onTap,
      {bool enabled = true}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon,
              size: 18, color: enabled ? Colors.white70 : Colors.white24),
        ),
      ),
    );
  }

  Widget _bookmarkItem(
      _Bookmark bm, Color accent, Color textPrimary, Color textSecondary) {
    final isActive = _currentPath == bm.path;
    return InkWell(
      onTap: () => _navigateTo(bm.path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: isActive ? accent.withOpacity(0.15) : null,
        child: Row(
          children: [
            Icon(bm.icon, size: 15, color: isActive ? accent : textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                bm.label,
                style: TextStyle(
                  color: isActive ? accent : textPrimary,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _columnHeader(String label, _SortMode mode, {int flex = 1}) {
    final isActive = _sortMode == mode;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_sortMode == mode) {
              _sortAscending = !_sortAscending;
            } else {
              _sortMode = mode;
              _sortAscending = true;
            }
          });
        },
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                )),
            if (isActive)
              Icon(
                _sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 14,
                color: Colors.white70,
              ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(FileSystemEntity entity, Color accent, Color bgDeep,
      Color bgSurface, Color textPrimary, Color textSecondary) {
    final isDir = entity is Directory;
    final name = p.basename(entity.path);
    final isSelected = _selected.contains(entity.path);
    final isAudio = !isDir && _isAudioFile(entity.path);

    FileStat? stat;
    try {
      stat = entity.statSync();
    } catch (_) {}

    return InkWell(
      onTap: () {
        if (isDir) {
          // Single-click on folder: select/highlight only (no navigation)
        } else if (widget.mode == _BrowseMode.pickFiles) {
          _toggleSelection(entity.path);
        }
      },
      onDoubleTap: () {
        if (isDir) {
          _navigateTo(entity.path);
        } else if (widget.mode == _BrowseMode.pickFiles) {
          // Double-click on file = select and confirm
          _selected.clear();
          _selected.add(entity.path);
          _confirm();
        }
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: isSelected
            ? accent.withOpacity(0.2)
            : null,
        child: Row(
          children: [
            // Checkbox (only for file pick mode)
            if (widget.mode == _BrowseMode.pickFiles && !isDir) ...[
              SizedBox(
                width: 18,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(entity.path),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: Colors.white30, width: 1),
                  activeColor: accent,
                ),
              ),
              const SizedBox(width: 4),
            ] else
              const SizedBox(width: 22),

            // Icon
            Icon(
              isDir ? Icons.folder : _iconForFile(entity.path),
              size: 16,
              color: isDir
                  ? const Color(0xFFFFD700)
                  : isAudio
                      ? _colorForExt(entity.path)
                      : textSecondary,
            ),
            const SizedBox(width: 6),

            // Name
            Expanded(
              flex: 4,
              child: Text(
                name,
                style: TextStyle(
                  color: isDir ? textPrimary : (isAudio ? textPrimary : textSecondary),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Size
            Expanded(
              flex: 1,
              child: Text(
                isDir ? '--' : (stat != null ? _formatSize(stat.size) : ''),
                style: TextStyle(color: textSecondary, fontSize: 11),
              ),
            ),

            // Date
            Expanded(
              flex: 2,
              child: Text(
                stat != null ? _formatDate(stat.modified) : '',
                style: TextStyle(color: textSecondary, fontSize: 11),
              ),
            ),

            // Type
            Expanded(
              flex: 1,
              child: isDir
                  ? Text('Folder',
                      style: TextStyle(color: textSecondary, fontSize: 11))
                  : isAudio
                      ? Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _colorForExt(entity.path).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            p.extension(name).replaceAll('.', '').toUpperCase(),
                            style: TextStyle(
                              color: _colorForExt(entity.path),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : Text(
                          p.extension(name).replaceAll('.', '').toUpperCase(),
                          style: TextStyle(color: textSecondary, fontSize: 11),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SortMode { name, size, date, type }
