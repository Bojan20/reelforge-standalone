/// Slot Lab Settings Panel
///
/// Configurable settings for the Slot Lab:
/// - Grid size (reels x rows)
/// - Timing profile (normal/turbo/mobile/studio)
/// - Volatility (low/medium/high)
/// - Audio settings
/// - Visual settings
library;

import 'package:flutter/material.dart';
import '../../utils/safe_file_picker.dart';
import '../../theme/fluxforge_theme.dart';
import '../../services/session_persistence_service.dart';
import 'volatility_dial.dart' show VolatilityLevel;

// ═══════════════════════════════════════════════════════════════════════════
// SLOT LAB SETTINGS DATA
// ═══════════════════════════════════════════════════════════════════════════

class SlotLabSettings {
  final int reels;
  final int rows;
  final TimingProfile timingProfile;
  final VolatilityLevel volatility;
  final double masterVolume;
  final bool enablePreviewOnHover;
  final bool enableAnimations;
  final bool enableParticles;
  final bool showDebugInfo;

  const SlotLabSettings({
    this.reels = 5,
    this.rows = 3,
    this.timingProfile = TimingProfile.normal,
    this.volatility = VolatilityLevel.medium,
    this.masterVolume = 0.8,
    this.enablePreviewOnHover = true,
    this.enableAnimations = true,
    this.enableParticles = true,
    this.showDebugInfo = false,
  });

  SlotLabSettings copyWith({
    int? reels,
    int? rows,
    TimingProfile? timingProfile,
    VolatilityLevel? volatility,
    double? masterVolume,
    bool? enablePreviewOnHover,
    bool? enableAnimations,
    bool? enableParticles,
    bool? showDebugInfo,
  }) {
    return SlotLabSettings(
      reels: reels ?? this.reels,
      rows: rows ?? this.rows,
      timingProfile: timingProfile ?? this.timingProfile,
      volatility: volatility ?? this.volatility,
      masterVolume: masterVolume ?? this.masterVolume,
      enablePreviewOnHover: enablePreviewOnHover ?? this.enablePreviewOnHover,
      enableAnimations: enableAnimations ?? this.enableAnimations,
      enableParticles: enableParticles ?? this.enableParticles,
      showDebugInfo: showDebugInfo ?? this.showDebugInfo,
    );
  }
}

enum TimingProfile {
  normal('Normal', 'Standard casino timing'),
  turbo('Turbo', 'Fast-paced mobile style'),
  mobile('Mobile', 'Optimized for mobile games'),
  studio('Studio', 'Extended for audio design');

  final String label;
  final String description;
  const TimingProfile(this.label, this.description);
}

// VolatilityLevel is imported from volatility_dial.dart

// ═══════════════════════════════════════════════════════════════════════════
// SLOT LAB SETTINGS PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class SlotLabSettingsPanel extends StatefulWidget {
  final SlotLabSettings settings;
  final ValueChanged<SlotLabSettings> onSettingsChanged;
  final VoidCallback? onClose;

  const SlotLabSettingsPanel({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onClose,
  });

  @override
  State<SlotLabSettingsPanel> createState() => _SlotLabSettingsPanelState();
}

class _SlotLabSettingsPanelState extends State<SlotLabSettingsPanel> {
  late SlotLabSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  void didUpdateWidget(SlotLabSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _settings = widget.settings;
    }
  }

  void _updateSettings(SlotLabSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grid Configuration
                  _buildSectionHeader('Grid Configuration'),
                  const SizedBox(height: 12),
                  _buildGridSettings(),
                  const SizedBox(height: 20),

                  // Timing Profile
                  _buildSectionHeader('Timing Profile'),
                  const SizedBox(height: 12),
                  _buildTimingProfileSelector(),
                  const SizedBox(height: 20),

                  // Volatility
                  _buildSectionHeader('Volatility'),
                  const SizedBox(height: 12),
                  _buildVolatilitySelector(),
                  const SizedBox(height: 20),

                  // Audio Settings
                  _buildSectionHeader('Audio'),
                  const SizedBox(height: 12),
                  _buildAudioSettings(),
                  const SizedBox(height: 20),

                  // Visual Settings
                  _buildSectionHeader('Visual'),
                  const SizedBox(height: 12),
                  _buildVisualSettings(),
                  const SizedBox(height: 20),

                  // Debug
                  _buildSectionHeader('Debug'),
                  const SizedBox(height: 12),
                  _buildDebugSettings(),
                  const SizedBox(height: 20),

                  // Export/Import
                  _buildSectionHeader('Session'),
                  const SizedBox(height: 12),
                  _buildExportImportSettings(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.settings,
            color: FluxForgeTheme.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            'Slot Lab Settings',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: FluxForgeTheme.textSecondary,
              onPressed: widget.onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: FluxForgeTheme.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildGridSettings() {
    return Row(
      children: [
        Expanded(
          child: _buildNumberSelector(
            label: 'Reels',
            value: _settings.reels,
            min: 3,
            max: 7,
            onChanged: (v) => _updateSettings(_settings.copyWith(reels: v)),
          ),
        ),
        const SizedBox(width: 16),
        const Text(
          '×',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildNumberSelector(
            label: 'Rows',
            value: _settings.rows,
            min: 3,
            max: 5,
            onChanged: (v) => _updateSettings(_settings.copyWith(rows: v)),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberSelector({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            children: [
              _buildStepButton(
                icon: Icons.remove,
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    value.toString(),
                    style: const TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _buildStepButton(
                icon: Icons.add,
                onPressed: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepButton({
    required IconData icon,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 16),
        color: onPressed != null
            ? FluxForgeTheme.accentBlue
            : FluxForgeTheme.textTertiary,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildTimingProfileSelector() {
    return Column(
      children: TimingProfile.values.map((profile) {
        final isSelected = _settings.timingProfile == profile;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildOptionTile(
            label: profile.label,
            description: profile.description,
            isSelected: isSelected,
            onTap: () => _updateSettings(_settings.copyWith(timingProfile: profile)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVolatilitySelector() {
    return Column(
      children: VolatilityLevel.values.map((level) {
        final isSelected = _settings.volatility == level;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildOptionTile(
            label: level.label,
            description: _getVolatilityDescription(level),
            isSelected: isSelected,
            onTap: () => _updateSettings(_settings.copyWith(volatility: level)),
            accentColor: level.color,
          ),
        );
      }).toList(),
    );
  }

  String _getVolatilityDescription(VolatilityLevel level) {
    return switch (level) {
      VolatilityLevel.casual => 'Very frequent small wins',
      VolatilityLevel.low => 'Frequent wins, lower variance',
      VolatilityLevel.medium => 'Balanced win frequency',
      VolatilityLevel.high => 'Less frequent, bigger wins',
      VolatilityLevel.insane => 'Rare but massive wins',
    };
  }

  Widget _buildOptionTile({
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    Color? accentColor,
  }) {
    final color = accentColor ?? FluxForgeTheme.accentBlue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.15)
              : FluxForgeTheme.surfaceDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? color : Colors.transparent,
                border: Border.all(
                  color: isSelected ? color : FluxForgeTheme.textTertiary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSettings() {
    return Column(
      children: [
        // Master Volume
        _buildSliderSetting(
          label: 'Master Volume',
          value: _settings.masterVolume,
          onChanged: (v) => _updateSettings(_settings.copyWith(masterVolume: v)),
        ),
        const SizedBox(height: 12),
        // Preview on Hover
        _buildToggleSetting(
          label: 'Preview on Hover',
          description: 'Play audio when hovering over files',
          value: _settings.enablePreviewOnHover,
          onChanged: (v) => _updateSettings(_settings.copyWith(enablePreviewOnHover: v)),
        ),
      ],
    );
  }

  Widget _buildVisualSettings() {
    return Column(
      children: [
        _buildToggleSetting(
          label: 'Animations',
          description: 'Enable reel spin animations',
          value: _settings.enableAnimations,
          onChanged: (v) => _updateSettings(_settings.copyWith(enableAnimations: v)),
        ),
        const SizedBox(height: 8),
        _buildToggleSetting(
          label: 'Particles',
          description: 'Show win celebration particles',
          value: _settings.enableParticles,
          onChanged: (v) => _updateSettings(_settings.copyWith(enableParticles: v)),
        ),
      ],
    );
  }

  Widget _buildDebugSettings() {
    return _buildToggleSetting(
      label: 'Debug Info',
      description: 'Show stage events and timing data',
      value: _settings.showDebugInfo,
      onChanged: (v) => _updateSettings(_settings.copyWith(showDebugInfo: v)),
    );
  }

  Widget _buildSliderSetting({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: const TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: FluxForgeTheme.accentBlue,
            inactiveTrackColor: FluxForgeTheme.bgElevated,
            thumbColor: FluxForgeTheme.accentBlue,
            overlayColor: FluxForgeTheme.accentBlue.withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleSetting({
    required String label,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: FluxForgeTheme.accentBlue,
          activeTrackColor: FluxForgeTheme.accentBlue.withOpacity(0.4),
          inactiveThumbColor: FluxForgeTheme.textTertiary,
          inactiveTrackColor: FluxForgeTheme.bgElevated,
        ),
      ],
    );
  }

  Widget _buildExportImportSettings() {
    return Column(
      children: [
        // Export JSON
        _buildActionButton(
          label: 'Export Session (JSON)',
          icon: Icons.file_download_outlined,
          description: 'Full session with events and audio pool',
          onTap: _exportSessionJson,
        ),
        const SizedBox(height: 8),
        // Export CSV
        _buildActionButton(
          label: 'Export Session (CSV)',
          icon: Icons.table_chart_outlined,
          description: 'Spreadsheet format for analysis',
          onTap: _exportSessionCsv,
        ),
        const SizedBox(height: 8),
        // Import JSON
        _buildActionButton(
          label: 'Import Session',
          icon: Icons.file_upload_outlined,
          description: 'Load session from JSON file',
          onTap: _importSession,
        ),
        const SizedBox(height: 8),
        // Save now
        _buildActionButton(
          label: 'Save Session Now',
          icon: Icons.save_outlined,
          description: 'Force save to default location',
          onTap: () async {
            final success = await SessionPersistenceService.instance.saveSession();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? 'Session saved' : 'Save failed'),
                  backgroundColor: success ? Colors.green : Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surfaceDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: FluxForgeTheme.accentBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: FluxForgeTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSessionJson() async {
    final result = await SafeFilePicker.saveFile(context,
      dialogTitle: 'Export Session',
      fileName: 'slotlab_session_${DateTime.now().toIso8601String().split('T').first}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null) {
      final success = await SessionPersistenceService.instance.exportSessionToFile(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Exported to $result' : 'Export failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportSessionCsv() async {
    final result = await SafeFilePicker.saveFile(context,
      dialogTitle: 'Export Session as CSV',
      fileName: 'slotlab_session_${DateTime.now().toIso8601String().split('T').first}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      final success = await SessionPersistenceService.instance.exportSessionToCsv(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Exported to $result' : 'Export failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importSession() async {
    final result = await SafeFilePicker.pickFiles(context,
      dialogTitle: 'Import Session',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      final success = await SessionPersistenceService.instance.importSessionFromFile(
        result.files.single.path!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Session imported' : 'Import failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SETTINGS BUTTON (for integration)
// ═══════════════════════════════════════════════════════════════════════════

class SlotLabSettingsButton extends StatelessWidget {
  final SlotLabSettings settings;
  final ValueChanged<SlotLabSettings> onSettingsChanged;

  const SlotLabSettingsButton({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings, size: 20),
      color: FluxForgeTheme.textSecondary,
      tooltip: 'Slot Lab Settings',
      onPressed: () => _showSettingsDialog(context),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SlotLabSettingsPanel(
          settings: settings,
          onSettingsChanged: onSettingsChanged,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
