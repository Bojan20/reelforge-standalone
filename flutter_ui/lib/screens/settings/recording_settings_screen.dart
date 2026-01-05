/// Recording Settings Screen
///
/// Configure recording options:
/// - Output directory
/// - File format and bit depth
/// - Pre-roll settings
/// - Input monitoring

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

class RecordingSettingsScreen extends StatefulWidget {
  const RecordingSettingsScreen({super.key});

  @override
  State<RecordingSettingsScreen> createState() => _RecordingSettingsScreenState();
}

class _RecordingSettingsScreenState extends State<RecordingSettingsScreen> {
  String _outputDir = '~/Documents/Recordings';
  String _filePrefix = 'Recording';
  int _bitDepth = 24;
  double _preRollSecs = 2.0;
  bool _inputMonitoring = true;
  bool _autoIncrement = true;
  bool _capturePreRoll = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReelForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: ReelForgeTheme.bgMid,
        title: const Text('Recording Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOutputSection(),
            const SizedBox(height: 32),
            _buildFormatSection(),
            const SizedBox(height: 32),
            _buildPreRollSection(),
            const SizedBox(height: 32),
            _buildMonitoringSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ReelForgeTheme.accentRed, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildOutputSection() {
    return _buildSection(
      title: 'Output Location',
      icon: Icons.folder,
      children: [
        Text(
          'Recording Directory',
          style: TextStyle(
            color: ReelForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ReelForgeTheme.borderSubtle),
                ),
                child: Text(
                  _outputDir,
                  style: TextStyle(
                    color: ReelForgeTheme.textPrimary,
                    fontFamily: ReelForgeTheme.monoFontFamily,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _browseOutputDir,
              icon: const Icon(Icons.folder_open),
              tooltip: 'Browse...',
              style: IconButton.styleFrom(
                backgroundColor: ReelForgeTheme.bgSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'File Name Prefix',
          style: TextStyle(
            color: ReelForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: _filePrefix),
          onChanged: (value) => _filePrefix = value,
          style: TextStyle(color: ReelForgeTheme.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: ReelForgeTheme.bgSurface,
            hintText: 'e.g., Recording',
            hintStyle: TextStyle(color: ReelForgeTheme.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSwitch(
          label: 'Auto-increment file names',
          value: _autoIncrement,
          onChanged: (v) => setState(() => _autoIncrement = v),
        ),
      ],
    );
  }

  Widget _buildFormatSection() {
    return _buildSection(
      title: 'Recording Format',
      icon: Icons.audio_file,
      children: [
        Text(
          'Bit Depth',
          style: TextStyle(
            color: ReelForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [16, 24, 32].map((bits) {
            final isSelected = bits == _bitDepth;
            return ChoiceChip(
              label: Text('$bits-bit'),
              selected: isSelected,
              onSelected: (_) => setState(() => _bitDepth = bits),
              backgroundColor: ReelForgeTheme.bgSurface,
              selectedColor: ReelForgeTheme.accentBlue,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : ReelForgeTheme.textPrimary,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: ReelForgeTheme.textTertiary),
            const SizedBox(width: 8),
            Text(
              _bitDepth == 16
                  ? 'CD quality - smaller files'
                  : _bitDepth == 24
                      ? 'Studio quality - recommended'
                      : 'Maximum quality - largest files',
              style: TextStyle(
                color: ReelForgeTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreRollSection() {
    return _buildSection(
      title: 'Pre-Roll Buffer',
      icon: Icons.history,
      children: [
        _buildSwitch(
          label: 'Capture pre-roll audio',
          value: _capturePreRoll,
          onChanged: (v) => setState(() => _capturePreRoll = v),
        ),
        const SizedBox(height: 12),
        if (_capturePreRoll) ...[
          Text(
            'Pre-roll duration: ${_preRollSecs.toStringAsFixed(1)} seconds',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Slider(
            value: _preRollSecs,
            min: 0.5,
            max: 10.0,
            divisions: 19,
            onChanged: (v) => setState(() => _preRollSecs = v),
          ),
          Text(
            'Audio before pressing record will be captured',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMonitoringSection() {
    return _buildSection(
      title: 'Monitoring',
      icon: Icons.headphones,
      children: [
        _buildSwitch(
          label: 'Enable input monitoring',
          value: _inputMonitoring,
          onChanged: (v) {
            setState(() => _inputMonitoring = v);
            // TODO: Call API
            // api.recordingSetMonitoring(v);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Hear input signal through output while recording',
          style: TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
        if (_inputMonitoring) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 14,
                color: ReelForgeTheme.accentOrange,
              ),
              const SizedBox(width: 8),
              Text(
                'Use headphones to avoid feedback',
                style: TextStyle(
                  color: ReelForgeTheme.accentOrange,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 13,
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: ReelForgeTheme.accentBlue,
        ),
      ],
    );
  }

  void _browseOutputDir() {
    // TODO: Use file_picker to select directory
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Directory browser not yet implemented'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
