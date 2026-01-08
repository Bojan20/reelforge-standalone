// Save Project Dialog
//
// Provides project save functionality with:
// - Save location selection
// - Format selection (JSON, Binary, Compressed)
// - Overwrite confirmation

import 'package:flutter/material.dart';
import '../theme/reelforge_theme.dart';

enum ProjectFormat { json, binary, compressed }

class SaveProjectDialog extends StatefulWidget {
  final String? currentPath;
  final String projectName;
  final bool isSaveAs;

  const SaveProjectDialog({
    super.key,
    this.currentPath,
    required this.projectName,
    this.isSaveAs = false,
  });

  static Future<String?> show(
    BuildContext context, {
    String? currentPath,
    required String projectName,
    bool isSaveAs = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => SaveProjectDialog(
        currentPath: currentPath,
        projectName: projectName,
        isSaveAs: isSaveAs,
      ),
    );
  }

  @override
  State<SaveProjectDialog> createState() => _SaveProjectDialogState();
}

class _SaveProjectDialogState extends State<SaveProjectDialog> {
  final _pathController = TextEditingController();
  ProjectFormat _selectedFormat = ProjectFormat.json;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Set default path
    if (widget.currentPath != null) {
      _pathController.text = widget.currentPath!;
    } else {
      // Default to Documents folder
      _pathController.text = '~/Documents/${_sanitizeFilename(widget.projectName)}.rfproj';
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  String _getExtension() {
    switch (_selectedFormat) {
      case ProjectFormat.json:
        return 'rfproj';
      case ProjectFormat.binary:
        return 'rfprojb';
      case ProjectFormat.compressed:
        return 'rfprojz';
    }
  }

  void _updateExtension() {
    final path = _pathController.text;
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1) {
      _pathController.text = '${path.substring(0, lastDot)}.${_getExtension()}';
    }
  }

  Future<void> _browseLocation() async {
    // TODO: Use file_picker package or native dialog
    // For now, just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('File browser not yet implemented'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveProject() async {
    if (_pathController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a file path'),
          backgroundColor: ReelForgeTheme.accentRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // TODO: Call Rust API
      // await api.projectSaveSync(_pathController.text);

      await Future.delayed(const Duration(milliseconds: 500)); // Simulate save

      if (mounted) {
        Navigator.of(context).pop(_pathController.text);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving project: $e'),
            backgroundColor: ReelForgeTheme.accentRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReelForgeTheme.bgMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ReelForgeTheme.borderSubtle),
      ),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.save,
                  color: ReelForgeTheme.accentBlue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.isSaveAs ? 'Save Project As' : 'Save Project',
                  style: ReelForgeTheme.h2,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // File path
            Text(
              'Save Location',
              style: TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    style: TextStyle(
                      color: ReelForgeTheme.textPrimary,
                      fontFamily: ReelForgeTheme.monoFontFamily,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: ReelForgeTheme.bgSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: ReelForgeTheme.accentBlue),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _browseLocation,
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Browse...',
                  style: IconButton.styleFrom(
                    backgroundColor: ReelForgeTheme.bgSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: ReelForgeTheme.borderSubtle),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Format selection
            Text(
              'File Format',
              style: TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _buildFormatChip(
                  ProjectFormat.json,
                  'JSON',
                  'Human-readable, larger file size',
                ),
                _buildFormatChip(
                  ProjectFormat.binary,
                  'Binary',
                  'Smaller, includes embedded assets',
                ),
                _buildFormatChip(
                  ProjectFormat.compressed,
                  'Compressed',
                  'Smallest file size',
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveProject,
                  icon: _isSaving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ReelForgeTheme.textPrimary,
                          ),
                        )
                      : const Icon(Icons.save, size: 18),
                  label: Text(_isSaving ? 'Saving...' : 'Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ReelForgeTheme.accentBlue,
                    foregroundColor: ReelForgeTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatChip(
    ProjectFormat format,
    String label,
    String description,
  ) {
    final isSelected = _selectedFormat == format;

    return Tooltip(
      message: description,
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _selectedFormat = format);
          _updateExtension();
        },
        backgroundColor: ReelForgeTheme.bgSurface,
        selectedColor: ReelForgeTheme.accentBlue,
        labelStyle: TextStyle(
          color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textPrimary,
          fontSize: 12,
        ),
      ),
    );
  }
}
