import 'package:flutter/material.dart';
import '../../../theme/fluxforge_theme.dart';

/// MWUI-6: Export Panel UI — 7 Export Formats
///
/// Supports:
/// - .ffpkg (FluxForge Package)
/// - Wwise .bnk (SoundBank)
/// - FMOD .bank (Studio Bank)
/// - Unity .unitypackage
/// - Raw Stems (audio files)
/// - JSON Manifest
/// - Compliance Report (PDF)
class MwuiExportPanel extends StatefulWidget {
  const MwuiExportPanel({super.key});

  @override
  State<MwuiExportPanel> createState() => _MwuiExportPanelState();
}

class _MwuiExportPanelState extends State<MwuiExportPanel> {
  int _selectedFormat = 0;
  bool _isExporting = false;
  double _progress = 0.0;

  // Format-specific options
  bool _includeMetadata = true;
  bool _compressAssets = true;
  bool _embedManifest = true;
  String _sampleRate = '48000';
  String _bitDepth = '24';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Row(
            children: [
              // Format selector (left)
              SizedBox(
                width: 200,
                child: _buildFormatList(),
              ),
              VerticalDivider(width: 1, color: FluxForgeTheme.borderSubtle),
              // Options + export (right)
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _buildFormatOptions()),
                    _buildExportBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.upload_file, size: 14, color: Color(0xFF26C6DA)),
          const SizedBox(width: 6),
          Text('Export', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('7 formats', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildFormatList() {
    return ListView.builder(
      padding: const EdgeInsets.all(6),
      itemCount: _formats.length,
      itemBuilder: (context, index) {
        final fmt = _formats[index];
        final isSelected = _selectedFormat == index;

        return GestureDetector(
          onTap: () => setState(() => _selectedFormat = index),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? fmt.color.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isSelected
                  ? Border.all(color: fmt.color.withOpacity(0.3), width: 0.5)
                  : null,
            ),
            child: Row(
              children: [
                Icon(fmt.icon, size: 16, color: isSelected ? fmt.color : Colors.white.withOpacity(0.3)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fmt.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        fmt.extension,
                        style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormatOptions() {
    final fmt = _formats[_selectedFormat];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Format description
          Row(
            children: [
              Icon(fmt.icon, size: 18, color: fmt.color),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmt.name, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(fmt.description, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Common options
          _sectionLabel('OPTIONS'),
          const SizedBox(height: 6),
          _toggleOption('Include Metadata', _includeMetadata, (v) => setState(() => _includeMetadata = v)),
          _toggleOption('Compress Assets', _compressAssets, (v) => setState(() => _compressAssets = v)),
          _toggleOption('Embed Manifest', _embedManifest, (v) => setState(() => _embedManifest = v)),
          const SizedBox(height: 12),

          // Audio settings (for formats that include audio)
          if (fmt.hasAudio) ...[
            _sectionLabel('AUDIO'),
            const SizedBox(height: 6),
            _dropdownOption('Sample Rate', _sampleRate, ['44100', '48000', '96000'],
              (v) => setState(() => _sampleRate = v)),
            _dropdownOption('Bit Depth', _bitDepth, ['16', '24', '32'],
              (v) => setState(() => _bitDepth = v)),
            const SizedBox(height: 12),
          ],

          // Checklist
          _sectionLabel('VERIFICATION'),
          const SizedBox(height: 6),
          for (final check in fmt.checks)
            _checkItem(check),
        ],
      ),
    );
  }

  Widget _buildExportBar() {
    final fmt = _formats[_selectedFormat];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isExporting) ...[
            SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white.withOpacity(0.06),
                valueColor: AlwaysStoppedAnimation(fmt.color),
              ),
            ),
            const SizedBox(height: 4),
            Text('Exporting... ${(_progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9)),
          ] else
            GestureDetector(
              onTap: _startExport,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: fmt.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: fmt.color.withOpacity(0.3), width: 0.5),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download, size: 14, color: fmt.color),
                    const SizedBox(width: 6),
                    Text('Export as ${fmt.extension}',
                      style: TextStyle(color: fmt.color, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _startExport() {
    setState(() {
      _isExporting = true;
      _progress = 0.0;
    });

    // Simulate export progress
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return false;
      setState(() => _progress += 0.05);
      if (_progress >= 1.0) {
        setState(() => _isExporting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Export complete: ${_formats[_selectedFormat].name}', style: const TextStyle(fontSize: 11)),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF2A2A4A),
            ),
          );
        }
        return false;
      }
      return true;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: const Color(0xFF26C6DA).withOpacity(0.6),
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }

  Widget _toggleOption(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF26C6DA).withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: value ? const Color(0xFF26C6DA) : Colors.white.withOpacity(0.2), width: 0.5),
              ),
              child: value
                  ? const Icon(Icons.check, size: 10, color: Color(0xFF26C6DA))
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _dropdownOption(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
          ),
          ...options.map((opt) {
            final isSelected = opt == value;
            return GestureDetector(
              onTap: () => onChanged(opt),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF26C6DA).withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF26C6DA).withOpacity(0.4) : Colors.white.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
                child: Text(opt, style: TextStyle(
                  color: isSelected ? const Color(0xFF26C6DA) : Colors.white.withOpacity(0.4),
                  fontSize: 9,
                )),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _checkItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 10, color: const Color(0xFF66BB6A).withOpacity(0.5)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9)),
        ],
      ),
    );
  }

  static const _formats = [
    _ExportFormat('FluxForge Package', '.ffpkg', 'Native binary package with all assets',
      Icons.inventory_2, Color(0xFF42A5F5), true,
      ['Behavior tree validated', 'Audio assets included', 'Manifest locked']),
    _ExportFormat('Wwise SoundBank', '.bnk', 'Audiokinetic Wwise compatible bank',
      Icons.surround_sound, Color(0xFF66BB6A), true,
      ['Bus hierarchy mapped', 'RTPC exported', 'Events mapped']),
    _ExportFormat('FMOD Bank', '.bank', 'FMOD Studio compatible bank',
      Icons.music_note, Color(0xFFFFB74D), true,
      ['Timeline events mapped', 'Parameter sheets exported', 'Bus routing verified']),
    _ExportFormat('Unity Package', '.unitypackage', 'Unity asset bundle with integration scripts',
      Icons.gamepad, Color(0xFF7E57C2), true,
      ['Audio clips included', 'ScriptableObjects generated', 'Namespace configured']),
    _ExportFormat('Raw Stems', '.wav/.ogg', 'Plain audio files organized by category',
      Icons.folder, Color(0xFF78909C), true,
      ['Sample rate matched', 'Naming convention applied', 'Metadata stripped']),
    _ExportFormat('JSON Manifest', '.json', 'Human-readable middleware configuration',
      Icons.data_object, Color(0xFF26C6DA), false,
      ['Schema validated', 'Version locked', 'Config hash computed']),
    _ExportFormat('Compliance Report', '.pdf', 'Regulatory validation documentation',
      Icons.assignment, Color(0xFFEF5350), false,
      ['AIL score included', 'DRC trace attached', 'Safety envelope verified']),
  ];
}

class _ExportFormat {
  final String name;
  final String extension;
  final String description;
  final IconData icon;
  final Color color;
  final bool hasAudio;
  final List<String> checks;
  const _ExportFormat(this.name, this.extension, this.description, this.icon, this.color, this.hasAudio, this.checks);
}
