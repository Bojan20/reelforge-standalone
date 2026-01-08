// Render in Place Dialog
//
// Professional dialog for rendering clips/tracks with FX applied.
// Similar to Cubase/Pro Tools "Render in Place" functionality:
// - Include/exclude specific FX
// - Normalize options
// - Tail handling
// - Output format options
// - Replace original or create new clip

import 'package:flutter/material.dart';
import '../theme/reelforge_theme.dart';

/// Render in Place options
class RenderInPlaceOptions {
  /// Include clip FX (per-clip processing)
  final bool includeClipFx;
  /// Include track inserts
  final bool includeInserts;
  /// Include track sends (render wet signal)
  final bool includeSends;
  /// Include track volume/pan
  final bool includeVolumePan;
  /// Include master bus processing
  final bool includeMaster;
  /// Normalize output
  final NormalizeMode normalizeMode;
  /// Target level for normalization (dB)
  final double normalizeTarget;
  /// Extra tail time for reverb/delay (seconds)
  final double tailTime;
  /// Replace original clip or create new
  final RenderDestination destination;
  /// Bit depth
  final int bitDepth;
  /// Sample rate (0 = project rate)
  final int sampleRate;
  /// Dither type for bit depth reduction
  final DitherType ditherType;

  const RenderInPlaceOptions({
    this.includeClipFx = true,
    this.includeInserts = true,
    this.includeSends = false,
    this.includeVolumePan = true,
    this.includeMaster = false,
    this.normalizeMode = NormalizeMode.none,
    this.normalizeTarget = -1,
    this.tailTime = 0,
    this.destination = RenderDestination.newClip,
    this.bitDepth = 32,
    this.sampleRate = 0,
    this.ditherType = DitherType.none,
  });
}

enum NormalizeMode {
  none,
  peak,
  lufs,
  rms,
}

enum RenderDestination {
  replaceOriginal,
  newClip,
  newTrack,
  separateFile,
}

enum DitherType {
  none,
  triangular,
  rectangular,
  shapedNoise,
  mbit,
}

class RenderInPlaceDialog extends StatefulWidget {
  /// Clip name being rendered
  final String clipName;
  /// Whether clip has FX
  final bool hasClipFx;
  /// Whether track has inserts
  final bool hasInserts;
  /// Initial options
  final RenderInPlaceOptions? initialOptions;

  const RenderInPlaceDialog({
    super.key,
    required this.clipName,
    this.hasClipFx = false,
    this.hasInserts = false,
    this.initialOptions,
  });

  /// Show the dialog and return options if confirmed
  static Future<RenderInPlaceOptions?> show(
    BuildContext context, {
    required String clipName,
    bool hasClipFx = false,
    bool hasInserts = false,
    RenderInPlaceOptions? initialOptions,
  }) {
    return showDialog<RenderInPlaceOptions>(
      context: context,
      builder: (context) => RenderInPlaceDialog(
        clipName: clipName,
        hasClipFx: hasClipFx,
        hasInserts: hasInserts,
        initialOptions: initialOptions,
      ),
    );
  }

  @override
  State<RenderInPlaceDialog> createState() => _RenderInPlaceDialogState();
}

class _RenderInPlaceDialogState extends State<RenderInPlaceDialog> {
  late bool _includeClipFx;
  late bool _includeInserts;
  late bool _includeSends;
  late bool _includeVolumePan;
  late bool _includeMaster;
  late NormalizeMode _normalizeMode;
  late double _normalizeTarget;
  late double _tailTime;
  late RenderDestination _destination;
  late int _bitDepth;
  late int _sampleRate;
  late DitherType _ditherType;

  @override
  void initState() {
    super.initState();
    final opts = widget.initialOptions ?? const RenderInPlaceOptions();
    _includeClipFx = opts.includeClipFx;
    _includeInserts = opts.includeInserts;
    _includeSends = opts.includeSends;
    _includeVolumePan = opts.includeVolumePan;
    _includeMaster = opts.includeMaster;
    _normalizeMode = opts.normalizeMode;
    _normalizeTarget = opts.normalizeTarget;
    _tailTime = opts.tailTime;
    _destination = opts.destination;
    _bitDepth = opts.bitDepth;
    _sampleRate = opts.sampleRate;
    _ditherType = opts.ditherType;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReelForgeTheme.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProcessingSection(),
                    const SizedBox(height: 20),
                    _buildNormalizeSection(),
                    const SizedBox(height: 20),
                    _buildTailSection(),
                    const SizedBox(height: 20),
                    _buildOutputSection(),
                    const SizedBox(height: 20),
                    _buildDestinationSection(),
                  ],
                ),
              ),
            ),
            // Actions
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: ReelForgeTheme.accentBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Render in Place',
                  style: TextStyle(
                    color: ReelForgeTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.clipName,
                  style: TextStyle(
                    color: ReelForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: ReelForgeTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingSection() {
    return _buildSection(
      title: 'Processing',
      icon: Icons.tune,
      child: Column(
        children: [
          _buildSwitchTile(
            title: 'Include Clip FX',
            subtitle: 'Per-clip effects (EQ, compression, etc.)',
            value: _includeClipFx,
            enabled: widget.hasClipFx,
            onChanged: (v) => setState(() => _includeClipFx = v),
          ),
          _buildSwitchTile(
            title: 'Include Track Inserts',
            subtitle: 'Track insert effects chain',
            value: _includeInserts,
            enabled: widget.hasInserts,
            onChanged: (v) => setState(() => _includeInserts = v),
          ),
          _buildSwitchTile(
            title: 'Include Track Sends',
            subtitle: 'Render with send effects (reverb, delay)',
            value: _includeSends,
            onChanged: (v) => setState(() => _includeSends = v),
          ),
          _buildSwitchTile(
            title: 'Include Volume/Pan',
            subtitle: 'Apply track volume and pan settings',
            value: _includeVolumePan,
            onChanged: (v) => setState(() => _includeVolumePan = v),
          ),
          _buildSwitchTile(
            title: 'Include Master Bus',
            subtitle: 'Include master bus processing',
            value: _includeMaster,
            onChanged: (v) => setState(() => _includeMaster = v),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalizeSection() {
    return _buildSection(
      title: 'Normalization',
      icon: Icons.graphic_eq,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode selector
          Wrap(
            spacing: 8,
            children: NormalizeMode.values.map((mode) {
              final isSelected = _normalizeMode == mode;
              return ChoiceChip(
                label: Text(_getNormalizeModeName(mode)),
                selected: isSelected,
                onSelected: (_) => setState(() => _normalizeMode = mode),
                backgroundColor: ReelForgeTheme.bgSurface,
                selectedColor: ReelForgeTheme.accentBlue,
                labelStyle: TextStyle(
                  color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textPrimary,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
          if (_normalizeMode != NormalizeMode.none) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Target Level',
                  style: TextStyle(color: ReelForgeTheme.textSecondary),
                ),
                const Spacer(),
                SizedBox(
                  width: 100,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      suffixText: _normalizeMode == NormalizeMode.lufs ? 'LUFS' : 'dB',
                    ),
                    controller: TextEditingController(
                      text: _normalizeTarget.toStringAsFixed(1),
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v);
                      if (val != null) {
                        setState(() => _normalizeTarget = val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTailSection() {
    return _buildSection(
      title: 'Tail Handling',
      icon: Icons.timer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add extra time for reverb/delay tails',
            style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _tailTime,
                  min: 0,
                  max: 10,
                  divisions: 100,
                  activeColor: ReelForgeTheme.accentBlue,
                  onChanged: (v) => setState(() => _tailTime = v),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '${_tailTime.toStringAsFixed(1)}s',
                  style: TextStyle(
                    color: ReelForgeTheme.textPrimary,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
            ],
          ),
          // Preset buttons
          Wrap(
            spacing: 8,
            children: [
              _buildPresetChip('0s', 0),
              _buildPresetChip('0.5s', 0.5),
              _buildPresetChip('1s', 1),
              _buildPresetChip('2s', 2),
              _buildPresetChip('5s', 5),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, double value) {
    final isSelected = (_tailTime - value).abs() < 0.01;
    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.bgSurface,
      labelStyle: TextStyle(
        color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textSecondary,
        fontSize: 11,
      ),
      onPressed: () => setState(() => _tailTime = value),
    );
  }

  Widget _buildOutputSection() {
    return _buildSection(
      title: 'Output Format',
      icon: Icons.settings,
      child: Column(
        children: [
          // Bit depth
          Row(
            children: [
              Text(
                'Bit Depth',
                style: TextStyle(color: ReelForgeTheme.textSecondary),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: _bitDepth,
                dropdownColor: ReelForgeTheme.bgMid,
                style: TextStyle(color: ReelForgeTheme.textPrimary),
                items: [16, 24, 32].map((bits) {
                  return DropdownMenuItem(
                    value: bits,
                    child: Text('$bits-bit${bits == 32 ? ' float' : ''}'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _bitDepth = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Sample rate
          Row(
            children: [
              Text(
                'Sample Rate',
                style: TextStyle(color: ReelForgeTheme.textSecondary),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: _sampleRate,
                dropdownColor: ReelForgeTheme.bgMid,
                style: TextStyle(color: ReelForgeTheme.textPrimary),
                items: [0, 44100, 48000, 88200, 96000, 192000].map((rate) {
                  return DropdownMenuItem(
                    value: rate,
                    child: Text(rate == 0 ? 'Project Rate' : '${rate ~/ 1000}kHz'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _sampleRate = v);
                },
              ),
            ],
          ),
          if (_bitDepth < 32) ...[
            const SizedBox(height: 12),
            // Dither
            Row(
              children: [
                Text(
                  'Dither',
                  style: TextStyle(color: ReelForgeTheme.textSecondary),
                ),
                const Spacer(),
                DropdownButton<DitherType>(
                  value: _ditherType,
                  dropdownColor: ReelForgeTheme.bgMid,
                  style: TextStyle(color: ReelForgeTheme.textPrimary),
                  items: DitherType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_getDitherName(type)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _ditherType = v);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDestinationSection() {
    return _buildSection(
      title: 'Destination',
      icon: Icons.save_alt,
      child: Column(
        children: RenderDestination.values.map((dest) {
          return RadioListTile<RenderDestination>(
            value: dest,
            groupValue: _destination,
            onChanged: (v) => setState(() => _destination = v!),
            title: Text(
              _getDestinationName(dest),
              style: TextStyle(color: ReelForgeTheme.textPrimary),
            ),
            subtitle: Text(
              _getDestinationDescription(dest),
              style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
            ),
            activeColor: ReelForgeTheme.accentBlue,
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: ReelForgeTheme.accentBlue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: ReelForgeTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: SwitchListTile(
        value: value && enabled,
        onChanged: enabled ? onChanged : null,
        title: Text(
          title,
          style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
        ),
        activeColor: ReelForgeTheme.accentGreen,
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _handleRender,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Render'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentBlue,
              foregroundColor: ReelForgeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _handleRender() {
    final options = RenderInPlaceOptions(
      includeClipFx: _includeClipFx,
      includeInserts: _includeInserts,
      includeSends: _includeSends,
      includeVolumePan: _includeVolumePan,
      includeMaster: _includeMaster,
      normalizeMode: _normalizeMode,
      normalizeTarget: _normalizeTarget,
      tailTime: _tailTime,
      destination: _destination,
      bitDepth: _bitDepth,
      sampleRate: _sampleRate,
      ditherType: _ditherType,
    );
    Navigator.of(context).pop(options);
  }

  String _getNormalizeModeName(NormalizeMode mode) {
    switch (mode) {
      case NormalizeMode.none:
        return 'Off';
      case NormalizeMode.peak:
        return 'Peak';
      case NormalizeMode.lufs:
        return 'LUFS';
      case NormalizeMode.rms:
        return 'RMS';
    }
  }

  String _getDestinationName(RenderDestination dest) {
    switch (dest) {
      case RenderDestination.replaceOriginal:
        return 'Replace Original';
      case RenderDestination.newClip:
        return 'New Clip (Same Track)';
      case RenderDestination.newTrack:
        return 'New Track';
      case RenderDestination.separateFile:
        return 'Export to File';
    }
  }

  String _getDestinationDescription(RenderDestination dest) {
    switch (dest) {
      case RenderDestination.replaceOriginal:
        return 'Replace the original clip with rendered version';
      case RenderDestination.newClip:
        return 'Create new clip next to original on same track';
      case RenderDestination.newTrack:
        return 'Create new track with rendered clip';
      case RenderDestination.separateFile:
        return 'Export to external audio file';
    }
  }

  String _getDitherName(DitherType type) {
    switch (type) {
      case DitherType.none:
        return 'None';
      case DitherType.triangular:
        return 'Triangular (TPDF)';
      case DitherType.rectangular:
        return 'Rectangular';
      case DitherType.shapedNoise:
        return 'Noise Shaped';
      case DitherType.mbit:
        return 'MBIT+';
    }
  }
}
