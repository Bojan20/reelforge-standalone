/// Add Track Dialog — Cubase/Logic-style track creation
///
/// Professional dialog for creating timeline tracks with:
/// - Track type selection (Audio, Instrument, Folder, Bus, Aux)
/// - Name, count, channel config, output bus, color
/// - Template selection from TrackTemplateService
/// - Context-adaptive behavior per section
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/timeline_models.dart';
import '../../models/track_template.dart';
import '../../services/track_template_service.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RESULT TYPE
// ═══════════════════════════════════════════════════════════════════════════════

/// Section context for adaptive behavior
enum AppSection { daw, middleware, slotLab }

/// Result returned when user confirms the dialog
class AddTrackResult {
  final TrackType trackType;
  final String name;
  final int count;
  final int channels; // 1=mono, 2=stereo
  final OutputBus outputBus;
  final Color color;
  final TrackTemplate? template;
  final bool armForRecording;

  const AddTrackResult({
    required this.trackType,
    required this.name,
    this.count = 1,
    this.channels = 2,
    this.outputBus = OutputBus.master,
    this.color = const Color(0xFF5B9BD5),
    this.template,
    this.armForRecording = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const _trackColors = [
  Color(0xFF5B9BD5), // Blue (default)
  Color(0xFFFF6B6B), // Red
  Color(0xFFFFD93D), // Yellow
  Color(0xFF40FF90), // Green
  Color(0xFFFF9040), // Orange
  Color(0xFF9B59B6), // Purple
  Color(0xFF40C8FF), // Cyan
  Color(0xFFFF80B0), // Pink
];

/// Track type configuration data
class _TrackTypeInfo {
  final TrackType type;
  final String label;
  final IconData icon;
  final Color iconColor;
  final String namePrefix;
  final bool showChannels;
  final bool showOutput;
  final bool showTemplate;
  final bool showArm;
  final bool lockStereo;

  const _TrackTypeInfo({
    required this.type,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.namePrefix,
    this.showChannels = true,
    this.showOutput = true,
    this.showTemplate = false,
    this.showArm = false,
    this.lockStereo = false,
  });
}

const _trackTypes = [
  _TrackTypeInfo(
    type: TrackType.audio,
    label: 'Audio',
    icon: Icons.mic,
    iconColor: FluxForgeTheme.accentBlue,
    namePrefix: 'Audio',
    showTemplate: true,
    showArm: true,
  ),
  _TrackTypeInfo(
    type: TrackType.instrument,
    label: 'Instrument',
    icon: Icons.piano,
    iconColor: FluxForgeTheme.accentPurple,
    namePrefix: 'Instrument',
    lockStereo: true,
  ),
  _TrackTypeInfo(
    type: TrackType.folder,
    label: 'Folder',
    icon: Icons.folder_outlined,
    iconColor: FluxForgeTheme.accentOrange,
    namePrefix: 'Folder',
    showChannels: false,
    showOutput: false,
  ),
  _TrackTypeInfo(
    type: TrackType.bus,
    label: 'Bus',
    icon: Icons.call_merge,
    iconColor: FluxForgeTheme.accentGreen,
    namePrefix: 'Bus',
    lockStereo: true,
  ),
  _TrackTypeInfo(
    type: TrackType.aux,
    label: 'Aux',
    icon: Icons.alt_route,
    iconColor: FluxForgeTheme.accentCyan,
    namePrefix: 'Aux',
    lockStereo: true,
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// DIALOG WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class AddTrackDialog extends StatefulWidget {
  final int existingTrackCount;
  final AppSection section;

  const AddTrackDialog({
    super.key,
    required this.existingTrackCount,
    this.section = AppSection.daw,
  });

  /// Show the dialog and return result (null = cancelled)
  static Future<AddTrackResult?> show(
    BuildContext context, {
    required int existingTrackCount,
    AppSection section = AppSection.daw,
  }) {
    return showDialog<AddTrackResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AddTrackDialog(
        existingTrackCount: existingTrackCount,
        section: section,
      ),
    );
  }

  @override
  State<AddTrackDialog> createState() => _AddTrackDialogState();
}

class _AddTrackDialogState extends State<AddTrackDialog> {
  // ─── State ─────────────────────────────────────────────────────────────────
  int _selectedTypeIndex = 0;
  late TextEditingController _nameController;
  bool _userEditedName = false;
  int _count = 1;
  int _channels = 2; // 1=mono, 2=stereo
  OutputBus _outputBus = OutputBus.master;
  Color _selectedColor = _trackColors[0];
  TrackTemplate? _selectedTemplate;
  bool _armForRecording = false;
  bool _templateExpanded = false;

  _TrackTypeInfo get _currentType => _trackTypes[_selectedTypeIndex];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${_trackTypes[0].namePrefix} ${widget.existingTrackCount + 1}',
    );
    // Initialize template service
    TrackTemplateService.instance.init();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onTypeSelected(int index) {
    final info = _trackTypes[index];
    setState(() {
      _selectedTypeIndex = index;
      // Auto-update name if user hasn't manually edited it
      if (!_userEditedName) {
        _nameController.text =
            '${info.namePrefix} ${widget.existingTrackCount + 1}';
      }
      // Reset template when switching away from audio
      if (!info.showTemplate) {
        _selectedTemplate = null;
        _templateExpanded = false;
      }
      // Lock stereo for instrument/bus/aux
      if (info.lockStereo) {
        _channels = 2;
      }
      // Reset arm for non-audio
      if (!info.showArm) {
        _armForRecording = false;
      }
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    Navigator.of(context).pop(AddTrackResult(
      trackType: _currentType.type,
      name: name,
      count: _count,
      channels: _currentType.showChannels ? _channels : 2,
      outputBus: _currentType.showOutput ? _outputBus : OutputBus.master,
      color: _selectedColor,
      template: _selectedTemplate,
      armForRecording: _armForRecording,
    ));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTypeSelector(),
                    const SizedBox(height: 20),
                    _buildConfigSection(),
                    if (_currentType.showTemplate) ...[
                      const SizedBox(height: 16),
                      _buildTemplateSection(),
                    ],
                    if (_currentType.showArm) ...[
                      const SizedBox(height: 12),
                      _buildArmCheckbox(),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.add, size: 18, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            'Add Track',
            style: FluxForgeTheme.body.copyWith(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return InkWell(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(4),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.close, size: 16, color: FluxForgeTheme.textTertiary),
      ),
    );
  }

  // ─── Track Type Selector ───────────────────────────────────────────────────

  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRACK TYPE',
          style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_trackTypes.length, (i) {
            final info = _trackTypes[i];
            final isSelected = i == _selectedTypeIndex;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i < _trackTypes.length - 1 ? 6 : 0,
                ),
                child: _buildTypeCard(info, isSelected, i),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildTypeCard(_TrackTypeInfo info, bool isSelected, int index) {
    return GestureDetector(
      onTap: () => _onTypeSelected(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? info.iconColor.withValues(alpha: 0.15)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? info.iconColor : FluxForgeTheme.borderSubtle,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              info.icon,
              size: 22,
              color: isSelected ? info.iconColor : FluxForgeTheme.textTertiary,
            ),
            const SizedBox(height: 6),
            Text(
              info.label,
              style: FluxForgeTheme.label.copyWith(
                color: isSelected
                    ? info.iconColor
                    : FluxForgeTheme.textTertiary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Configuration Section ─────────────────────────────────────────────────

  Widget _buildConfigSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONFIGURATION',
          style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        // Name field
        _buildNameField(),
        const SizedBox(height: 12),
        // Count + Channels row
        Row(
          children: [
            Expanded(child: _buildCountField()),
            if (_currentType.showChannels) ...[
              const SizedBox(width: 12),
              Expanded(child: _buildChannelSelector()),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // Output + Color row
        Row(
          children: [
            if (_currentType.showOutput) ...[
              Expanded(child: _buildOutputSelector()),
              const SizedBox(width: 12),
            ],
            Expanded(child: _buildColorPicker()),
          ],
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return _buildFieldRow('Name', TextField(
      controller: _nameController,
      onChanged: (_) => _userEditedName = true,
      style: FluxForgeTheme.body.copyWith(color: FluxForgeTheme.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: FluxForgeTheme.bgMid,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FluxForgeTheme.accentBlue),
        ),
      ),
      onSubmitted: (_) => _submit(),
    ));
  }

  Widget _buildCountField() {
    return _buildFieldRow('Count', Container(
      height: 32,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          _buildCountButton(Icons.remove, () {
            if (_count > 1) setState(() => _count--);
          }),
          Expanded(
            child: Center(
              child: Text(
                '$_count',
                style: FluxForgeTheme.body.copyWith(
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ),
          ),
          _buildCountButton(Icons.add, () {
            if (_count < 32) setState(() => _count++);
          }),
        ],
      ),
    ));
  }

  Widget _buildCountButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 32,
        child: Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
      ),
    );
  }

  Widget _buildChannelSelector() {
    final locked = _currentType.lockStereo;
    return _buildFieldRow('Channels', Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: locked ? FluxForgeTheme.bgDeep : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _channels,
          isExpanded: true,
          isDense: true,
          dropdownColor: FluxForgeTheme.bgSurface,
          style: FluxForgeTheme.body.copyWith(
            color: locked
                ? FluxForgeTheme.textDisabled
                : FluxForgeTheme.textPrimary,
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: locked
                ? FluxForgeTheme.textDisabled
                : FluxForgeTheme.textTertiary,
          ),
          onChanged: locked ? null : (v) {
            if (v != null) setState(() => _channels = v);
          },
          items: const [
            DropdownMenuItem(value: 1, child: Text('Mono')),
            DropdownMenuItem(value: 2, child: Text('Stereo')),
          ],
        ),
      ),
    ));
  }

  Widget _buildOutputSelector() {
    return _buildFieldRow('Output', Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<OutputBus>(
          value: _outputBus,
          isExpanded: true,
          isDense: true,
          dropdownColor: FluxForgeTheme.bgSurface,
          style: FluxForgeTheme.body.copyWith(
            color: FluxForgeTheme.textPrimary,
          ),
          icon: const Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: FluxForgeTheme.textTertiary,
          ),
          onChanged: (v) {
            if (v != null) setState(() => _outputBus = v);
          },
          items: OutputBus.values.map((bus) {
            return DropdownMenuItem(
              value: bus,
              child: Text(_outputBusLabel(bus)),
            );
          }).toList(),
        ),
      ),
    ));
  }

  Widget _buildColorPicker() {
    return _buildFieldRow('Color', SizedBox(
      height: 32,
      child: Row(
        children: _trackColors.map((color) {
          final isSelected = color == _selectedColor;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => setState(() => _selectedColor = color),
              child: Container(
                width: isSelected ? 26 : 22,
                height: isSelected ? 26 : 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ));
  }

  Widget _buildFieldRow(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: FluxForgeTheme.bodySmall.copyWith(
            color: FluxForgeTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  // ─── Template Section ──────────────────────────────────────────────────────

  Widget _buildTemplateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _templateExpanded = !_templateExpanded),
          child: Row(
            children: [
              Icon(
                _templateExpanded
                    ? Icons.expand_more
                    : Icons.chevron_right,
                size: 16,
                color: FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                'TEMPLATE',
                style: FluxForgeTheme.label.copyWith(
                  color: FluxForgeTheme.textTertiary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              if (_selectedTemplate != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _selectedTemplate!.name,
                    style: FluxForgeTheme.labelTiny.copyWith(
                      color: FluxForgeTheme.accentBlue,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_templateExpanded) ...[
          const SizedBox(height: 8),
          _buildTemplateChips(),
        ],
      ],
    );
  }

  Widget _buildTemplateChips() {
    final templates = TrackTemplateService.instance.templates;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        // "None" chip
        _buildTemplateChip(null, 'None', null),
        // Template chips
        ...templates.map((t) => _buildTemplateChip(
              t,
              t.name,
              Color(t.colorValue),
            )),
      ],
    );
  }

  Widget _buildTemplateChip(
    TrackTemplate? template,
    String label,
    Color? chipColor,
  ) {
    final isSelected = _selectedTemplate == template;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTemplate = template;
          // Apply template color
          if (template != null) {
            _selectedColor = Color(template.colorValue);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (chipColor ?? FluxForgeTheme.accentBlue).withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? (chipColor ?? FluxForgeTheme.accentBlue)
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: FluxForgeTheme.bodySmall.copyWith(
            color: isSelected
                ? (chipColor ?? FluxForgeTheme.accentBlue)
                : FluxForgeTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ─── Arm Checkbox ──────────────────────────────────────────────────────────

  Widget _buildArmCheckbox() {
    return GestureDetector(
      onTap: () => setState(() => _armForRecording = !_armForRecording),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: _armForRecording,
              onChanged: (v) => setState(() => _armForRecording = v ?? false),
              activeColor: FluxForgeTheme.accentRed,
              side: const BorderSide(color: FluxForgeTheme.textTertiary),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Arm for Recording',
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Cancel
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          // Add Track
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              _count > 1 ? 'Add $_count Tracks' : 'Add Track',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _outputBusLabel(OutputBus bus) {
    switch (bus) {
      case OutputBus.master:
        return 'Master';
      case OutputBus.music:
        return 'Music';
      case OutputBus.sfx:
        return 'SFX';
      case OutputBus.ambience:
        return 'Ambience';
      case OutputBus.voice:
        return 'Voice';
    }
  }
}
