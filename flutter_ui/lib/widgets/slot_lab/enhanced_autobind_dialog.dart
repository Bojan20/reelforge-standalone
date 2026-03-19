/// Enhanced Auto-Bind Dialog — combines folder scan, FFNC rename, Smart Defaults,
/// and bus volume configuration in one step.
///
/// Flow: Pick folder → Preview matches → Optionally rename to FFNC → Set bus volumes → Apply
///
/// This replaces the old inline AlertDialog in _showAutoBindDialog.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import '../../providers/slot_lab_project_provider.dart';
import '../../services/ffnc/ffnc_renamer.dart';
import '../../services/native_file_picker.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Result returned to caller after dialog completes.
class EnhancedAutoBindResult {
  final String folderPath;
  final Map<String, String> bindings;
  final List<String> unmapped;
  final bool didRename;
  final Map<int, double> busVolumes;

  const EnhancedAutoBindResult({
    required this.folderPath,
    required this.bindings,
    required this.unmapped,
    required this.didRename,
    required this.busVolumes,
  });
}

class EnhancedAutoBindDialog extends StatefulWidget {
  const EnhancedAutoBindDialog({super.key});

  @override
  State<EnhancedAutoBindDialog> createState() => _EnhancedAutoBindDialogState();
}

class _EnhancedAutoBindDialogState extends State<EnhancedAutoBindDialog> {
  String? _folderPath;
  List<FFNCRenameResult> _renamePreview = [];
  Map<String, String> _bindings = {};
  List<String> _unmapped = [];
  bool _analyzed = false;
  bool _applying = false;

  // Options
  bool _doRename = true;
  final Map<int, double> _busVolumes = {
    0: 1.0, // Master
    1: 1.0, // Music
    2: 1.0, // SFX
    3: 1.0, // Voice
    4: 1.0, // Ambience
  };

  static const _busNames = ['Master', 'Music', 'SFX', 'Voice', 'Ambience'];
  static const _busColors = [
    Colors.white54,             // Master
    Color(0xFF50D8FF),          // Music — cyan
    Color(0xFF50FF98),          // SFX — green
    Color(0xFFFF9850),          // Voice — orange
    Color(0xFF9080FF),          // Ambience — purple
  ];

  late final FFNCRenamer _renamer;

  @override
  void initState() {
    super.initState();
    final knownStages = StageConfigurationService.instance
        .getAllStages()
        .map((s) => s.name)
        .toSet();
    _renamer = FFNCRenamer(knownStages: knownStages);
    _pickFolder();
  }

  Future<void> _pickFolder() async {
    final path = await NativeFilePicker.pickDirectory(
      title: 'Select Sound Folder for Auto-Bind',
    );
    if (path == null) {
      if (mounted) Navigator.of(context).pop(null);
      return;
    }
    if (!mounted) return;
    setState(() => _folderPath = path);
    _analyze();
  }

  Future<void> _repickFolder() async {
    final path = await NativeFilePicker.pickDirectory(
      title: 'Select Sound Folder for Auto-Bind',
    );
    if (path == null || !mounted) return;
    setState(() {
      _folderPath = path;
      _analyzed = false;
      _renamePreview = [];
      _bindings = {};
      _unmapped = [];
    });
    _analyze();
  }

  void _analyze() {
    if (_folderPath == null) return;

    // Generate FFNC rename preview — DOES NOT apply anything
    _renamePreview = _renamer.analyze(
      _folderPath!,
      (normalized, full) => SlotLabProjectProvider.resolveStageFromFilenamePublic(normalized, full),
    );

    // Derive bindings from preview (preview only, no side effects)
    final previewBindings = <String, String>{};
    final previewUnmapped = <String>[];
    for (final r in _renamePreview) {
      if (r.stage != null && r.isMatched) {
        previewBindings.putIfAbsent(r.stage!, () => r.originalPath);
      } else {
        previewUnmapped.add(r.originalName);
      }
    }

    setState(() {
      _bindings = previewBindings;
      _unmapped = previewUnmapped;
      _analyzed = true;
    });
  }

  Future<void> _apply() async {
    if (_folderPath == null) return;
    setState(() => _applying = true);

    try {
      String effectivePath = _folderPath!;
      bool didRename = false;

      // Step 1: Rename files if requested (copy to ffnc/ subfolder)
      if (_doRename) {
        final matched = _renamePreview.where((r) => r.isMatched).toList();
        if (matched.isNotEmpty) {
          final outputDir = p.join(_folderPath!, 'ffnc');
          final dir = Directory(outputDir);
          if (!dir.existsSync()) dir.createSync(recursive: true);
          await _renamer.copyRenamed(matched, outputDir);
          effectivePath = outputDir;
          didRename = true;
        }
      }

      // Step 2: Run autoBindFromFolder() ONCE — this is the only place it's called
      // Applies bindings to provider, creates composite events, registers in EventRegistry
      final projectProvider = GetIt.instance<SlotLabProjectProvider>();
      final result = projectProvider.autoBindFromFolder(effectivePath);

      if (mounted) {
        setState(() => _applying = false);
        Navigator.of(context).pop(EnhancedAutoBindResult(
          folderPath: effectivePath,
          bindings: result.bindings,
          unmapped: result.unmapped,
          didRename: didRename,
          busVolumes: Map.from(_busVolumes),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-Bind failed: $e'), backgroundColor: const Color(0xFF442222)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_folderPath == null) {
      // Waiting for folder picker — show minimal loading state
      return Dialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 100),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Select folder...', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    final matchedCount = _doRename
        ? _renamePreview.where((r) => r.isMatched).length
        : _bindings.length;
    final totalCount = _doRename
        ? _renamePreview.length
        : _bindings.length + _unmapped.length;

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  const Icon(Icons.auto_fix_high, color: FluxForgeTheme.accentGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Auto-Bind: $matchedCount/$totalCount files',
                    style: const TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _folderPath ?? '',
                      style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 20,
                    child: TextButton(
                      onPressed: _repickFolder,
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Change', style: TextStyle(color: FluxForgeTheme.accentCyan, fontSize: 9)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Options row
              Row(
                children: [
                  _buildCheckbox('Rename to FFNC format', _doRename, (v) => setState(() => _doRename = v)),
                  const Spacer(),
                  Text(
                    '${_bindings.length} stages bound',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
              if (_doRename)
                const Padding(
                  padding: EdgeInsets.only(left: 22, top: 2),
                  child: Text(
                    'Files will be copied to /ffnc/ subfolder with FFNC names',
                    style: TextStyle(color: Colors.white24, fontSize: 9),
                  ),
                ),
              const SizedBox(height: 12),

              // Bus volumes
              const Text('Bus Volumes:', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (int i = 0; i < _busNames.length; i++)
                _buildBusSlider(i),
              const SizedBox(height: 12),

              // Preview table
              Expanded(
                child: _analyzed ? _buildPreviewTable() : const Center(child: CircularProgressIndicator()),
              ),
              const SizedBox(height: 12),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_unmapped.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '⚠ ${_unmapped.length} unmatched',
                        style: const TextStyle(color: Colors.orange, fontSize: 10),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (!_analyzed || _applying || _bindings.isEmpty) ? null : _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
                    ),
                    child: _applying
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Auto-Bind & Apply', style: TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(value ? Icons.check_box : Icons.check_box_outline_blank, size: 16,
              color: value ? FluxForgeTheme.accentGreen : Colors.white38),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildBusSlider(int busIndex) {
    final vol = _busVolumes[busIndex] ?? 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              _busNames[busIndex],
              style: TextStyle(color: _busColors[busIndex].withValues(alpha: 0.7), fontSize: 10),
            ),
          ),
          SizedBox(
            width: 120,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                activeTrackColor: _busColors[busIndex],
                thumbColor: _busColors[busIndex],
                inactiveTrackColor: Colors.white12,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: vol,
                min: 0,
                max: 1,
                onChanged: (v) => setState(() => _busVolumes[busIndex] = v),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${(vol * 100).round()}%',
            style: TextStyle(color: _busColors[busIndex].withValues(alpha: 0.5), fontSize: 9, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewTable() {
    // Merge rename preview with bindings for display
    final items = <_PreviewItem>[];

    if (_doRename) {
      for (final r in _renamePreview) {
        items.add(_PreviewItem(
          original: r.originalName,
          ffncName: r.ffncName,
          stage: r.stage,
          isMatched: r.isMatched,
        ));
      }
    } else {
      // Show bindings directly
      for (final entry in _bindings.entries) {
        items.add(_PreviewItem(
          original: entry.value.split('/').last,
          ffncName: null,
          stage: entry.key,
          isMatched: true,
        ));
      }
      for (final file in _unmapped) {
        items.add(_PreviewItem(
          original: file,
          ffncName: null,
          stage: null,
          isMatched: false,
        ));
      }
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: index.isEven ? Colors.white.withValues(alpha: 0.02) : Colors.transparent,
          child: Row(
            children: [
              Icon(
                item.isMatched ? Icons.check_circle : Icons.warning,
                size: 10,
                color: item.isMatched ? FluxForgeTheme.accentGreen : Colors.orange,
              ),
              const SizedBox(width: 4),
              if (item.stage != null) ...[
                SizedBox(
                  width: 150,
                  child: Text(
                    item.stage!,
                    style: TextStyle(
                      color: item.isMatched ? FluxForgeTheme.accentGreen : Colors.orange,
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  item.original,
                  style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_doRename && item.ffncName != null) ...[
                const Text(' → ', style: TextStyle(color: Colors.white24, fontSize: 8)),
                SizedBox(
                  width: 140,
                  child: Text(
                    item.ffncName!,
                    style: const TextStyle(color: FluxForgeTheme.accentCyan, fontSize: 9, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PreviewItem {
  final String original;
  final String? ffncName;
  final String? stage;
  final bool isMatched;

  const _PreviewItem({
    required this.original,
    this.ffncName,
    this.stage,
    required this.isMatched,
  });
}
