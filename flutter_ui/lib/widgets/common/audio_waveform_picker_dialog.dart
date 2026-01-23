/// Audio Waveform Picker Dialog
///
/// Modal dialog for selecting audio files with waveform preview.
/// Wraps AudioBrowserPanel in a dialog for use in container panels.
///
/// Features:
/// - File browser with search/filter
/// - Waveform preview on hover
/// - Playback preview
/// - Drag support (for future timeline integration)
///
/// Usage:
///   final path = await AudioWaveformPickerDialog.show(context);
///   if (path != null) {
///     // Use selected audio path
///   }
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../theme/fluxforge_theme.dart';
import '../slot_lab/audio_hover_preview.dart';

/// Dialog for picking audio files with waveform preview
class AudioWaveformPickerDialog extends StatefulWidget {
  /// Initial directory to browse (optional)
  final String? initialDirectory;

  /// Allowed file extensions
  final List<String> allowedExtensions;

  /// Dialog title
  final String title;

  const AudioWaveformPickerDialog({
    super.key,
    this.initialDirectory,
    this.allowedExtensions = const ['wav', 'mp3', 'ogg', 'flac', 'aiff'],
    this.title = 'Select Audio File',
  });

  /// Show the dialog and return selected file path (or null if cancelled)
  static Future<String?> show(
    BuildContext context, {
    String? initialDirectory,
    List<String> allowedExtensions = const ['wav', 'mp3', 'ogg', 'flac', 'aiff'],
    String title = 'Select Audio File',
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AudioWaveformPickerDialog(
        initialDirectory: initialDirectory,
        allowedExtensions: allowedExtensions,
        title: title,
      ),
    );
  }

  @override
  State<AudioWaveformPickerDialog> createState() =>
      _AudioWaveformPickerDialogState();
}

class _AudioWaveformPickerDialogState extends State<AudioWaveformPickerDialog> {
  late String _currentDirectory;
  List<AudioFileInfo> _audioFiles = [];
  AudioFileInfo? _selectedFile;
  bool _isLoading = true;
  String? _errorMessage;

  // Common audio directories
  static const List<String> _quickAccessPaths = [
    '~/Music',
    '~/Documents',
    '~/Downloads',
    '~/Desktop',
  ];

  @override
  void initState() {
    super.initState();
    _currentDirectory = widget.initialDirectory ??
        Platform.environment['HOME'] ??
        '/';
    _loadDirectory(_currentDirectory);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentDirectory = path;
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        setState(() {
          _errorMessage = 'Directory not found';
          _isLoading = false;
        });
        return;
      }

      final List<AudioFileInfo> files = [];
      int idCounter = 0;

      await for (final entity in dir.list()) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase().replaceAll('.', '');
          if (widget.allowedExtensions.contains(ext)) {
            final stat = await entity.stat();
            files.add(AudioFileInfo(
              id: '${idCounter++}',
              name: p.basename(entity.path),
              path: entity.path,
              duration: const Duration(seconds: 0), // Will be detected on hover
              format: ext.toUpperCase(),
              sampleRate: 48000,
              channels: 2,
              bitDepth: 24,
            ));
          }
        }
      }

      // Sort by name
      files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      setState(() {
        _audioFiles = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading directory: $e';
        _isLoading = false;
      });
    }
  }

  void _navigateUp() {
    final parent = p.dirname(_currentDirectory);
    if (parent != _currentDirectory) {
      _loadDirectory(parent);
    }
  }

  void _selectFile(AudioFileInfo file) {
    setState(() => _selectedFile = file);
  }

  void _confirmSelection() {
    if (_selectedFile != null) {
      Navigator.of(context).pop(_selectedFile!.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 700,
        height: 550,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildToolbar(),
            Expanded(child: _buildContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.audio_file,
            size: 18,
            color: FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 10),
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withOpacity(0.5),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Navigation buttons
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16, color: Colors.white54),
            onPressed: _navigateUp,
            tooltip: 'Parent directory',
            splashRadius: 14,
          ),

          // Quick access buttons
          const SizedBox(width: 8),
          ..._quickAccessPaths.map((path) {
            final expanded = path.replaceFirst('~', Platform.environment['HOME'] ?? '');
            final name = p.basename(expanded);
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _QuickAccessButton(
                label: name,
                onTap: () => _loadDirectory(expanded),
                isActive: _currentDirectory == expanded,
              ),
            );
          }),

          const Spacer(),

          // Current path
          Expanded(
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 12, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _currentDirectory,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontFamily: 'monospace',
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
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentBlue),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_audioFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.audio_file, size: 40, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'No audio files in this directory',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Supported: ${widget.allowedExtensions.join(", ")}',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Directory tree (simplified - just subdirectories)
        _buildDirectoryTree(),

        // Vertical divider
        Container(width: 1, color: FluxForgeTheme.borderSubtle),

        // File browser with waveform preview
        Expanded(
          child: AudioBrowserPanel(
            audioFiles: _audioFiles,
            height: double.infinity,
            onSelect: _selectFile,
            onPlay: (file) {
              setState(() => _selectedFile = file);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDirectoryTree() {
    return Container(
      width: 160,
      color: FluxForgeTheme.bgDeep,
      child: FutureBuilder<List<Directory>>(
        future: _getSubdirectories(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final dirs = snapshot.data!;
          if (dirs.isEmpty) {
            return Center(
              child: Text(
                'No subfolders',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(4),
            itemCount: dirs.length,
            itemBuilder: (context, index) {
              final dir = dirs[index];
              final name = p.basename(dir.path);
              return InkWell(
                onTap: () => _loadDirectory(dir.path),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder,
                        size: 14,
                        color: FluxForgeTheme.accentOrange.withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Directory>> _getSubdirectories() async {
    try {
      final dir = Directory(_currentDirectory);
      final List<Directory> dirs = [];

      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          // Skip hidden directories
          if (!name.startsWith('.')) {
            dirs.add(entity);
          }
        }
      }

      dirs.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      return dirs;
    } catch (e) {
      return [];
    }
  }

  Widget _buildFooter() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Selected file info
          if (_selectedFile != null) ...[
            Icon(Icons.audio_file, size: 14, color: FluxForgeTheme.accentGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedFile!.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                'Select an audio file',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],

          const SizedBox(width: 16),

          // Cancel button
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),

          const SizedBox(width: 8),

          // Confirm button
          ElevatedButton(
            onPressed: _selectedFile != null ? _confirmSelection : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: FluxForgeTheme.borderSubtle,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Select',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick access button for common directories
class _QuickAccessButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _QuickAccessButton({
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentBlue.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? FluxForgeTheme.accentBlue : Colors.white54,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}
