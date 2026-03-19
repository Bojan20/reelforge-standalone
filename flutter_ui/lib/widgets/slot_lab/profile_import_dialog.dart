/// Profile Import Dialog — UI for importing .ffap audio profiles.
///
/// Shows preview of profile contents, import options (events, win tiers,
/// music layers), audio path remapping, and conflict resolution.

import 'package:flutter/material.dart';
import '../../services/ffnc/profile_importer.dart';
import '../../services/native_file_picker.dart';
import '../../theme/fluxforge_theme.dart';

class ProfileImportDialog extends StatefulWidget {
  final String ffapPath;
  final Future<ProfileImportResult> Function(ProfileImportOptions options) onImport;

  const ProfileImportDialog({
    super.key,
    required this.ffapPath,
    required this.onImport,
  });

  @override
  State<ProfileImportDialog> createState() => _ProfileImportDialogState();
}

class _ProfileImportDialogState extends State<ProfileImportDialog> {
  ProfilePreview? _preview;
  bool _loading = true;
  bool _importing = false;

  bool _importEvents = true;
  bool _importWinTiers = true;
  bool _importMusicLayers = true;
  String? _remapFolder;
  ConflictResolution _conflict = ConflictResolution.overwrite;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final preview = await ProfileImporter.preview(widget.ffapPath);
    if (mounted) setState(() { _preview = preview; _loading = false; });
  }

  Future<void> _pickRemapFolder() async {
    final path = await NativeFilePicker.pickDirectory(title: 'Select audio folder for remapping');
    if (path != null && mounted) setState(() => _remapFolder = path);
  }

  Future<void> _doImport() async {
    setState(() => _importing = true);
    final result = await widget.onImport(ProfileImportOptions(
      importEvents: _importEvents,
      importWinTiers: _importWinTiers,
      importMusicLayers: _importMusicLayers,
      remapAudioFolder: _remapFolder,
      conflict: _conflict,
    ));
    if (mounted) {
      setState(() => _importing = false);
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _preview == null
                  ? const Center(child: Text('Failed to read profile', style: TextStyle(color: Colors.orange)))
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final p = _preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          'Import: ${p.manifest.name}',
          style: const TextStyle(color: FluxForgeTheme.accentCyan, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '${p.eventCount} events  •  ${p.winTierCount} win tiers  •  ${p.musicLayerCount} music layers',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 12),

        // Import options
        _buildCheckbox('Events (${p.eventCount})', _importEvents, (v) => setState(() => _importEvents = v)),
        _buildCheckbox('Win Tier Config', _importWinTiers, (v) => setState(() => _importWinTiers = v)),
        _buildCheckbox('Music Layer Config', _importMusicLayers, (v) => setState(() => _importMusicLayers = v)),
        const SizedBox(height: 12),

        // Audio remap
        const Text('Audio files:', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        _buildRadio('Keep original paths', _remapFolder == null, () => setState(() => _remapFolder = null)),
        Row(
          children: [
            _buildRadio('Remap to folder:', _remapFolder != null, _pickRemapFolder),
            if (_remapFolder != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _remapFolder!,
                  style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Conflict resolution
        const Text('Conflicts:', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildConflictRadio('Skip', ConflictResolution.skip),
            const SizedBox(width: 12),
            _buildConflictRadio('Overwrite', ConflictResolution.overwrite),
            const SizedBox(width: 12),
            _buildConflictRadio('Merge', ConflictResolution.merge),
          ],
        ),
        const SizedBox(height: 16),

        // README preview (scrollable)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: Text(
                p.readme,
                style: const TextStyle(color: Colors.white54, fontSize: 9, fontFamily: 'monospace', height: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _importing ? null : _doImport,
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
              ),
              child: _importing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Import', style: TextStyle(color: FluxForgeTheme.accentCyan)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.check_box : Icons.check_box_outline_blank, size: 16,
                color: value ? FluxForgeTheme.accentCyan : Colors.white38),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildRadio(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 14,
                color: selected ? FluxForgeTheme.accentCyan : Colors.white38),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictRadio(String label, ConflictResolution value) {
    final selected = _conflict == value;
    return GestureDetector(
      onTap: () => setState(() => _conflict = value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 14,
              color: selected ? FluxForgeTheme.accentCyan : Colors.white38),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: selected ? Colors.white70 : Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
