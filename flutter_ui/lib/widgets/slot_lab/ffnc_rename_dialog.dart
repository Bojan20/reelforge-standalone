/// FFNC Rename Tool Dialog — converts legacy audio filenames to FFNC format.
///
/// Shows a preview table of original → FFNC names with match status.
/// Unmatched files get typo suggestions via Levenshtein distance.
/// Copies files to output folder with new names (originals unchanged).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../services/ffnc/ffnc_renamer.dart';
import '../../services/native_file_picker.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

class FFNCRenameDialog extends StatefulWidget {
  final String? Function(String normalizedName, String fullName) resolveStage;

  const FFNCRenameDialog({
    super.key,
    required this.resolveStage,
  });

  @override
  State<FFNCRenameDialog> createState() => _FFNCRenameDialogState();
}

class _FFNCRenameDialogState extends State<FFNCRenameDialog> {
  String? _sourcePath;
  String? _outputPath;
  List<FFNCRenameResult> _results = [];
  bool _copyMode = true; // true = copy, false = rename in place
  bool _isProcessing = false;
  final Map<String, String> _manualOverrides = {}; // originalName → ffncName

  late final FFNCRenamer _renamer;

  @override
  void initState() {
    super.initState();
    final knownStages = StageConfigurationService.instance
        .getAllStages()
        .map((s) => s.name)
        .toSet();
    _renamer = FFNCRenamer(knownStages: knownStages);
  }

  Future<void> _pickSource() async {
    final path = await NativeFilePicker.pickDirectory(
      title: 'Select source audio folder',
    );
    if (path == null || !mounted) return;
    setState(() {
      _sourcePath = path;
      _outputPath ??= '$path/ffnc_output';
    });
    _analyze();
  }

  Future<void> _pickOutput() async {
    final path = await NativeFilePicker.pickDirectory(
      title: 'Select output folder',
    );
    if (path == null || !mounted) return;
    setState(() => _outputPath = path);
  }

  void _analyze() {
    if (_sourcePath == null) return;
    setState(() {
      _results = _renamer.analyze(_sourcePath!, widget.resolveStage);
    });
  }

  Future<void> _executeRename() async {
    if (_results.isEmpty) return;
    setState(() => _isProcessing = true);

    // Apply manual overrides
    final finalResults = _results.map((r) {
      if (_manualOverrides.containsKey(r.originalName)) {
        return FFNCRenameResult(
          originalPath: r.originalPath,
          originalName: r.originalName,
          ffncName: _manualOverrides[r.originalName],
          stage: r.stage,
          category: r.category,
          isExactMatch: true,
        );
      }
      return r;
    }).toList();

    final matched = finalResults.where((r) => r.isMatched).toList();

    if (_copyMode) {
      if (_outputPath == null) {
        setState(() => _isProcessing = false);
        return;
      }
      final count = await _renamer.copyRenamed(matched, _outputPath!);
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop(count);
      }
    } else {
      // Rename in place
      int count = 0;
      for (final result in matched) {
        if (result.ffncName == null || result.ffncName == result.originalName) continue;
        final source = File(result.originalPath);
        final dest = File(p.join(p.dirname(result.originalPath), result.ffncName!));
        if (source.existsSync() && !dest.existsSync()) {
          await source.rename(dest.path);
          count++;
        }
      }
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop(count);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchedCount = _results.where((r) => r.isMatched).length;
    final totalCount = _results.length;

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              const Text(
                'FFNC Rename Tool',
                style: TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Source / Output folders
              _buildFolderRow('Source:', _sourcePath, _pickSource),
              const SizedBox(height: 4),
              if (_copyMode) _buildFolderRow('Output:', _outputPath, _pickOutput),
              const SizedBox(height: 12),

              // Results table
              if (_results.isNotEmpty) ...[
                Text(
                  'Matched: $matchedCount/$totalCount',
                  style: TextStyle(
                    color: matchedCount == totalCount
                        ? FluxForgeTheme.accentGreen
                        : Colors.orange,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildResultsTable()),
              ] else if (_sourcePath != null) ...[
                const Text(
                  'No audio files found in source folder.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],

              const SizedBox(height: 12),

              // Options
              Row(
                children: [
                  _buildRadio('Copy to output', true),
                  const SizedBox(width: 16),
                  _buildRadio('Rename in place', false),
                ],
              ),
              if (!_copyMode)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '⚠ Original filenames will be permanently changed',
                    style: TextStyle(color: Colors.orange, fontSize: 10),
                  ),
                ),

              const SizedBox(height: 12),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _results.isEmpty || _isProcessing ? null : _executeRename,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _copyMode ? 'Rename & Copy' : 'Rename',
                            style: const TextStyle(color: FluxForgeTheme.accentCyan),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderRow(String label, String? path, VoidCallback onPick) {
    return Row(
      children: [
        SizedBox(
          width: 55,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              path ?? '—',
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 60,
          height: 24,
          child: TextButton(
            onPressed: onPick,
            child: const Text('Browse', style: TextStyle(fontSize: 10, color: FluxForgeTheme.accentCyan)),
          ),
        ),
      ],
    );
  }

  Widget _buildRadio(String label, bool value) {
    return GestureDetector(
      onTap: () => setState(() => _copyMode = value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _copyMode == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 14,
            color: _copyMode == value ? FluxForgeTheme.accentCyan : Colors.white38,
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildResultsTable() {
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        final displayName = _manualOverrides[r.originalName] ?? r.ffncName;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: index.isEven ? Colors.white.withValues(alpha: 0.02) : Colors.transparent,
          child: Row(
            children: [
              // Status icon
              Icon(
                displayName != null ? Icons.check_circle : Icons.warning,
                size: 12,
                color: displayName != null ? FluxForgeTheme.accentGreen : Colors.orange,
              ),
              const SizedBox(width: 6),

              // Original name
              Expanded(
                flex: 4,
                child: Text(
                  r.originalName,
                  style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Arrow
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('→', style: TextStyle(color: Colors.white24, fontSize: 10)),
              ),

              // FFNC name or unmatched
              Expanded(
                flex: 4,
                child: displayName != null
                    ? Text(
                        displayName,
                        style: const TextStyle(
                          color: FluxForgeTheme.accentCyan,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : _buildUnmatchedRow(r),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnmatchedRow(FFNCRenameResult r) {
    final suggestions = _renamer.suggestStage(r.originalName);

    if (suggestions.isEmpty) {
      return const Text(
        '??? (no match)',
        style: TextStyle(color: Colors.orange, fontSize: 10, fontFamily: 'monospace'),
      );
    }

    return GestureDetector(
      onTap: () {
        // Apply best suggestion
        setState(() {
          _manualOverrides[r.originalName] = suggestions.first.ffncName;
        });
      },
      child: Row(
        children: [
          Text(
            suggestions.first.ffncName,
            style: const TextStyle(color: Colors.orange, fontSize: 10, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 4),
          Text(
            '(typo? d=${suggestions.first.distance})',
            style: TextStyle(color: Colors.orange.withValues(alpha: 0.6), fontSize: 9),
          ),
        ],
      ),
    );
  }
}
