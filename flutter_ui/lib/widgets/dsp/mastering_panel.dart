/// ReelForge Intelligent Mastering Panel
///
/// Professional mastering engine with presets, analysis, and reference matching

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Mastering preset category
enum MasteringPresetCategory {
  streaming,
  broadcast,
  vinyl,
  cd,
  custom,
}

/// Mastering Panel Widget
class MasteringPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const MasteringPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<MasteringPanel> createState() => _MasteringPanelState();
}

class _MasteringPanelState extends State<MasteringPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Enabled state
  bool _enabled = false;

  // Target settings
  double _targetLufs = -14.0;
  double _truePeakLimit = -1.0;
  double _stereoWidth = 1.0;
  double _lowCutFreq = 30.0;

  // Module enables
  bool _eqEnabled = true;
  bool _multibandEnabled = true;
  bool _limiterEnabled = true;
  bool _autoGain = true;

  // Analysis results
  double? _currentLufs;
  double? _currentTruePeak;
  double? _dynamicRange;
  String? _suggestedGenre;
  List<String> _issues = [];

  // Selected preset
  String _selectedPresetId = 'streaming';

  // Reference matching
  bool _referenceLoaded = false;
  String? _referencePath;

  // Preset data
  static const List<Map<String, dynamic>> _presets = [
    {
      'id': 'streaming',
      'name': 'Streaming',
      'genre': 'General',
      'targetLufs': -14.0,
      'icon': Icons.cloud_outlined,
      'description': 'Spotify, Apple Music, YouTube',
    },
    {
      'id': 'cd',
      'name': 'CD Master',
      'genre': 'General',
      'targetLufs': -9.0,
      'icon': Icons.album,
      'description': 'Traditional CD mastering',
    },
    {
      'id': 'broadcast',
      'name': 'Broadcast',
      'genre': 'General',
      'targetLufs': -24.0,
      'icon': Icons.tv,
      'description': 'EBU R128 compliant',
    },
    {
      'id': 'podcast',
      'name': 'Podcast',
      'genre': 'Voice',
      'targetLufs': -16.0,
      'icon': Icons.podcasts,
      'description': 'Spoken word optimization',
    },
    {
      'id': 'edm',
      'name': 'EDM',
      'genre': 'Electronic',
      'targetLufs': -8.0,
      'icon': Icons.nightlife,
      'description': 'Loud and punchy',
    },
    {
      'id': 'classical',
      'name': 'Classical',
      'genre': 'Classical',
      'targetLufs': -18.0,
      'icon': Icons.piano,
      'description': 'Dynamic preservation',
    },
    {
      'id': 'hiphop',
      'name': 'Hip-Hop',
      'genre': 'Hip-Hop',
      'targetLufs': -10.0,
      'icon': Icons.graphic_eq,
      'description': 'Heavy low-end',
    },
    {
      'id': 'rock',
      'name': 'Rock',
      'genre': 'Rock',
      'targetLufs': -11.0,
      'icon': Icons.music_note,
      'description': 'Guitar-forward mix',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPresetsTab(),
                _buildSettingsTab(),
                _buildAnalysisTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(
            color: ReelForgeTheme.accentOrange.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            color: ReelForgeTheme.accentOrange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Intelligent Mastering',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _buildEnableToggle(),
        ],
      ),
    );
  }

  Widget _buildEnableToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _enabled = !_enabled);
        // Would call: masteringSetEnabled(_enabled)
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _enabled
              ? ReelForgeTheme.accentGreen.withValues(alpha: 0.2)
              : ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _enabled
                ? ReelForgeTheme.accentGreen
                : ReelForgeTheme.bgSurface,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _enabled ? Icons.power_settings_new : Icons.power_off,
              size: 14,
              color: _enabled
                  ? ReelForgeTheme.accentGreen
                  : ReelForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              _enabled ? 'ON' : 'OFF',
              style: TextStyle(
                color: _enabled
                    ? ReelForgeTheme.accentGreen
                    : ReelForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: ReelForgeTheme.bgMid,
      child: TabBar(
        controller: _tabController,
        labelColor: ReelForgeTheme.accentOrange,
        unselectedLabelColor: ReelForgeTheme.textSecondary,
        indicatorColor: ReelForgeTheme.accentOrange,
        indicatorWeight: 2,
        tabs: const [
          Tab(text: 'Presets'),
          Tab(text: 'Settings'),
          Tab(text: 'Analysis'),
        ],
      ),
    );
  }

  Widget _buildPresetsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mastering Presets',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildPresetGrid(),
          const SizedBox(height: 24),
          _buildReferenceSection(),
        ],
      ),
    );
  }

  Widget _buildPresetGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.0,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _presets.length,
      itemBuilder: (context, index) {
        final preset = _presets[index];
        final isSelected = preset['id'] == _selectedPresetId;
        return _buildPresetCard(preset, isSelected);
      },
    );
  }

  Widget _buildPresetCard(Map<String, dynamic> preset, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPresetId = preset['id'] as String;
          _targetLufs = (preset['targetLufs'] as double?) ?? -14.0;
        });
        // Would call: masteringApplyPreset(preset['id'])
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? ReelForgeTheme.accentOrange.withValues(alpha: 0.15)
              : ReelForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? ReelForgeTheme.accentOrange
                : ReelForgeTheme.bgSurface,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  preset['icon'] as IconData,
                  size: 18,
                  color: isSelected
                      ? ReelForgeTheme.accentOrange
                      : ReelForgeTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preset['name'] as String,
                    style: TextStyle(
                      color: isSelected
                          ? ReelForgeTheme.accentOrange
                          : ReelForgeTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${preset['targetLufs']} LUFS',
                  style: TextStyle(
                    color: ReelForgeTheme.accentCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              preset['description'] as String,
              style: TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compare,
                size: 16,
                color: ReelForgeTheme.accentCyan,
              ),
              const SizedBox(width: 8),
              Text(
                'Reference Matching',
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_referenceLoaded && _referencePath != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _referencePath!.split('/').last,
                    style: TextStyle(
                      color: ReelForgeTheme.accentGreen,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: ReelForgeTheme.textSecondary,
                  ),
                  onPressed: () {
                    setState(() {
                      _referenceLoaded = false;
                      _referencePath = null;
                    });
                  },
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _loadReference,
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Load Reference'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ReelForgeTheme.accentCyan,
                side: BorderSide(color: ReelForgeTheme.accentCyan),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingSection('Target Loudness', [
            _buildLufsSlider(),
            const SizedBox(height: 12),
            _buildTruePeakSlider(),
          ]),
          const SizedBox(height: 16),
          _buildSettingSection('Stereo', [
            _buildStereoWidthSlider(),
          ]),
          const SizedBox(height: 16),
          _buildSettingSection('Low End', [
            _buildLowCutSlider(),
          ]),
          const SizedBox(height: 16),
          _buildSettingSection('Modules', [
            _buildModuleToggles(),
          ]),
        ],
      ),
    );
  }

  Widget _buildSettingSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildLufsSlider() {
    return _buildSliderWithValue(
      'Target LUFS',
      _targetLufs,
      -24.0,
      -6.0,
      '${_targetLufs.toStringAsFixed(1)} LUFS',
      (v) => setState(() => _targetLufs = v),
    );
  }

  Widget _buildTruePeakSlider() {
    return _buildSliderWithValue(
      'True Peak Limit',
      _truePeakLimit,
      -3.0,
      0.0,
      '${_truePeakLimit.toStringAsFixed(1)} dBTP',
      (v) => setState(() => _truePeakLimit = v),
    );
  }

  Widget _buildStereoWidthSlider() {
    return _buildSliderWithValue(
      'Stereo Width',
      _stereoWidth,
      0.0,
      2.0,
      '${(_stereoWidth * 100).toInt()}%',
      (v) => setState(() => _stereoWidth = v),
    );
  }

  Widget _buildLowCutSlider() {
    return _buildSliderWithValue(
      'Low Cut Frequency',
      _lowCutFreq,
      20.0,
      80.0,
      '${_lowCutFreq.toInt()} Hz',
      (v) => setState(() => _lowCutFreq = v),
    );
  }

  Widget _buildSliderWithValue(
    String label,
    double value,
    double min,
    double max,
    String valueLabel,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: ReelForgeTheme.textPrimary,
                fontSize: 12,
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: ReelForgeTheme.accentOrange,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: ReelForgeTheme.accentOrange,
            inactiveTrackColor: ReelForgeTheme.bgSurface,
            thumbColor: ReelForgeTheme.accentOrange,
            overlayColor: ReelForgeTheme.accentOrange.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildModuleToggles() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _buildModuleToggle('EQ', _eqEnabled, Icons.equalizer,
            (v) => setState(() => _eqEnabled = v)),
        _buildModuleToggle('Multiband', _multibandEnabled, Icons.tune,
            (v) => setState(() => _multibandEnabled = v)),
        _buildModuleToggle('Limiter', _limiterEnabled, Icons.compress,
            (v) => setState(() => _limiterEnabled = v)),
        _buildModuleToggle('Auto Gain', _autoGain, Icons.auto_fix_normal,
            (v) => setState(() => _autoGain = v)),
      ],
    );
  }

  Widget _buildModuleToggle(
    String label,
    bool value,
    IconData icon,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value
              ? ReelForgeTheme.accentGreen.withValues(alpha: 0.2)
              : ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value
                ? ReelForgeTheme.accentGreen
                : ReelForgeTheme.bgSurface,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: value
                  ? ReelForgeTheme.accentGreen
                  : ReelForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: value
                    ? ReelForgeTheme.accentGreen
                    : ReelForgeTheme.textPrimary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalyzeButton(),
          const SizedBox(height: 16),
          if (_currentLufs != null) ...[
            _buildAnalysisResults(),
            const SizedBox(height: 16),
            if (_issues.isNotEmpty) _buildIssuesList(),
          ] else
            _buildNoAnalysisPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return ElevatedButton.icon(
      onPressed: _runAnalysis,
      icon: const Icon(Icons.analytics, size: 18),
      label: const Text('Analyze Audio'),
      style: ElevatedButton.styleFrom(
        backgroundColor: ReelForgeTheme.accentCyan,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  Widget _buildAnalysisResults() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analysis Results',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildMetricRow('Integrated LUFS', '${_currentLufs!.toStringAsFixed(1)} LUFS'),
          _buildMetricRow('True Peak', '${_currentTruePeak!.toStringAsFixed(1)} dBTP'),
          _buildMetricRow('Dynamic Range', '${_dynamicRange!.toStringAsFixed(1)} LU'),
          if (_suggestedGenre != null)
            _buildMetricRow('Suggested Genre', _suggestedGenre!),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: ReelForgeTheme.accentCyan,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssuesList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.accentOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.accentOrange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 16,
                color: ReelForgeTheme.accentOrange,
              ),
              const SizedBox(width: 8),
              Text(
                'Issues Found',
                style: TextStyle(
                  color: ReelForgeTheme.accentOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._issues.map((issue) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(color: ReelForgeTheme.textSecondary),
                    ),
                    Expanded(
                      child: Text(
                        issue,
                        style: TextStyle(
                          color: ReelForgeTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildNoAnalysisPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 48,
              color: ReelForgeTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No analysis yet',
              style: TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Click "Analyze Audio" to get recommendations',
              style: TextStyle(
                color: ReelForgeTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _loadReference() {
    // Would open file picker and call: masteringMatchReference(path)
    setState(() {
      _referenceLoaded = true;
      _referencePath = '/path/to/reference.wav';
    });
  }

  void _runAnalysis() {
    // Would call: masteringAnalyze(inputPath)
    setState(() {
      _currentLufs = -18.5;
      _currentTruePeak = -0.3;
      _dynamicRange = 8.2;
      _suggestedGenre = 'Rock';
      _issues = [
        'True peak exceeds -1.0 dBTP',
        'Consider reducing high frequency harshness',
      ];
    });
  }
}
