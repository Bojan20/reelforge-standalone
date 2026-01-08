// Bounce Dialog
//
// Professional dialog for bouncing/mixdown with full format control.
// Similar to Pro Tools/Logic/Cubase bounce functionality:
// - Time range selection
// - File format (WAV, AIFF, MP3, FLAC, etc.)
// - Bit depth and sample rate
// - Dithering options
// - Normalize options
// - Tail handling
// - Mono/Stereo/Surround modes

import 'package:flutter/material.dart';
import '../theme/reelforge_theme.dart';

/// Bounce/Export options
class BounceOptions {
  /// File format
  final AudioFormat format;
  /// Bit depth (for PCM formats)
  final int bitDepth;
  /// Sample rate (Hz)
  final int sampleRate;
  /// Dither type
  final DitherType ditherType;
  /// Noise shaping for dither
  final NoiseShaping noiseShaping;
  /// Channel mode
  final ChannelMode channelMode;
  /// Normalize mode
  final NormalizeMode normalizeMode;
  /// Normalize target level (dB or LUFS)
  final double normalizeTarget;
  /// Include tail time for effects
  final double tailTime;
  /// Start time (seconds)
  final double startTime;
  /// End time (seconds)
  final double endTime;
  /// MP3 bitrate (kbps)
  final int mp3Bitrate;
  /// MP3 VBR quality (0-10, 0 = best)
  final int mp3VbrQuality;
  /// Use VBR for MP3
  final bool mp3UseVbr;
  /// FLAC compression level (0-8)
  final int flacCompression;
  /// Create markers file
  final bool exportMarkers;
  /// Add to audio pool after bounce
  final bool addToPool;

  const BounceOptions({
    this.format = AudioFormat.wav,
    this.bitDepth = 24,
    this.sampleRate = 48000,
    this.ditherType = DitherType.none,
    this.noiseShaping = NoiseShaping.none,
    this.channelMode = ChannelMode.stereo,
    this.normalizeMode = NormalizeMode.none,
    this.normalizeTarget = -1,
    this.tailTime = 0,
    this.startTime = 0,
    this.endTime = 0,
    this.mp3Bitrate = 320,
    this.mp3VbrQuality = 2,
    this.mp3UseVbr = false,
    this.flacCompression = 5,
    this.exportMarkers = false,
    this.addToPool = true,
  });
}

enum AudioFormat {
  wav,
  aiff,
  flac,
  mp3,
  ogg,
  opus,
}

enum DitherType {
  none,
  triangular,
  rectangular,
  shapedNoise,
  powR,
  mbit,
}

enum NoiseShaping {
  none,
  light,
  medium,
  heavy,
  ultraHeavy,
}

enum ChannelMode {
  mono,
  stereo,
  monoSum,
  leftOnly,
  rightOnly,
  midSide,
}

enum NormalizeMode {
  none,
  peak,
  lufsIntegrated,
  lufsShortTerm,
  rms,
  truePeak,
}

class BounceDialog extends StatefulWidget {
  /// Project start time
  final double projectStart;
  /// Project end time (total duration)
  final double projectEnd;
  /// Current selection start (if any)
  final double? selectionStart;
  /// Current selection end (if any)
  final double? selectionEnd;
  /// Loop region (if enabled)
  final (double, double)? loopRegion;
  /// Project sample rate
  final int projectSampleRate;
  /// Initial options
  final BounceOptions? initialOptions;

  const BounceDialog({
    super.key,
    required this.projectStart,
    required this.projectEnd,
    this.selectionStart,
    this.selectionEnd,
    this.loopRegion,
    this.projectSampleRate = 48000,
    this.initialOptions,
  });

  /// Show the dialog and return options if confirmed
  static Future<BounceOptions?> show(
    BuildContext context, {
    required double projectStart,
    required double projectEnd,
    double? selectionStart,
    double? selectionEnd,
    (double, double)? loopRegion,
    int projectSampleRate = 48000,
    BounceOptions? initialOptions,
  }) {
    return showDialog<BounceOptions>(
      context: context,
      builder: (context) => BounceDialog(
        projectStart: projectStart,
        projectEnd: projectEnd,
        selectionStart: selectionStart,
        selectionEnd: selectionEnd,
        loopRegion: loopRegion,
        projectSampleRate: projectSampleRate,
        initialOptions: initialOptions,
      ),
    );
  }

  @override
  State<BounceDialog> createState() => _BounceDialogState();
}

class _BounceDialogState extends State<BounceDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Format options
  late AudioFormat _format;
  late int _bitDepth;
  late int _sampleRate;
  late ChannelMode _channelMode;

  // Dithering
  late DitherType _ditherType;
  late NoiseShaping _noiseShaping;

  // Normalization
  late NormalizeMode _normalizeMode;
  late double _normalizeTarget;

  // Range
  late double _startTime;
  late double _endTime;
  late double _tailTime;
  late String _rangeMode;

  // MP3/FLAC specific
  late int _mp3Bitrate;
  late int _mp3VbrQuality;
  late bool _mp3UseVbr;
  late int _flacCompression;

  // Options
  late bool _exportMarkers;
  late bool _addToPool;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final opts = widget.initialOptions ?? const BounceOptions();
    _format = opts.format;
    _bitDepth = opts.bitDepth;
    _sampleRate = opts.sampleRate == 0 ? widget.projectSampleRate : opts.sampleRate;
    _channelMode = opts.channelMode;
    _ditherType = opts.ditherType;
    _noiseShaping = opts.noiseShaping;
    _normalizeMode = opts.normalizeMode;
    _normalizeTarget = opts.normalizeTarget;
    _tailTime = opts.tailTime;
    _mp3Bitrate = opts.mp3Bitrate;
    _mp3VbrQuality = opts.mp3VbrQuality;
    _mp3UseVbr = opts.mp3UseVbr;
    _flacCompression = opts.flacCompression;
    _exportMarkers = opts.exportMarkers;
    _addToPool = opts.addToPool;

    // Initialize range
    if (widget.selectionStart != null && widget.selectionEnd != null) {
      _startTime = widget.selectionStart!;
      _endTime = widget.selectionEnd!;
      _rangeMode = 'selection';
    } else if (widget.loopRegion != null) {
      _startTime = widget.loopRegion!.$1;
      _endTime = widget.loopRegion!.$2;
      _rangeMode = 'loop';
    } else {
      _startTime = widget.projectStart;
      _endTime = widget.projectEnd;
      _rangeMode = 'all';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReelForgeTheme.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 600,
        height: 650,
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFormatTab(),
                  _buildDitheringTab(),
                  _buildNormalizeTab(),
                  _buildOptionsTab(),
                ],
              ),
            ),
            _buildRangeSection(),
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
          const Icon(Icons.album, color: ReelForgeTheme.accentOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bounce / Mixdown',
                  style: TextStyle(
                    color: ReelForgeTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Duration: ${_formatDuration(_endTime - _startTime + _tailTime)}',
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

  Widget _buildTabs() {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: TabBar(
        controller: _tabController,
        indicatorColor: ReelForgeTheme.accentBlue,
        labelColor: ReelForgeTheme.textPrimary,
        unselectedLabelColor: ReelForgeTheme.textSecondary,
        tabs: const [
          Tab(text: 'Format'),
          Tab(text: 'Dithering'),
          Tab(text: 'Normalize'),
          Tab(text: 'Options'),
        ],
      ),
    );
  }

  Widget _buildFormatTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: 'File Format',
            icon: Icons.audio_file,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AudioFormat.values.map((fmt) {
                final isSelected = _format == fmt;
                return ChoiceChip(
                  label: Text(_getFormatName(fmt)),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _format = fmt),
                  backgroundColor: ReelForgeTheme.bgSurface,
                  selectedColor: ReelForgeTheme.accentBlue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : ReelForgeTheme.textPrimary,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          if (_format == AudioFormat.wav || _format == AudioFormat.aiff)
            _buildSection(
              title: 'Bit Depth',
              icon: Icons.straighten,
              child: Wrap(
                spacing: 8,
                children: [16, 24, 32].map((bits) {
                  final isSelected = _bitDepth == bits;
                  return ChoiceChip(
                    label: Text('$bits-bit${bits == 32 ? ' float' : ''}'),
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
            ),
          if (_format == AudioFormat.mp3)
            _buildMp3Options(),
          if (_format == AudioFormat.flac)
            _buildFlacOptions(),
          const SizedBox(height: 20),
          _buildSection(
            title: 'Sample Rate',
            icon: Icons.speed,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [44100, 48000, 88200, 96000, 192000].map((rate) {
                final isSelected = _sampleRate == rate;
                final isProjectRate = rate == widget.projectSampleRate;
                return ChoiceChip(
                  label: Text(
                    '${rate ~/ 1000}kHz${isProjectRate ? ' *' : ''}',
                  ),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _sampleRate = rate),
                  backgroundColor: ReelForgeTheme.bgSurface,
                  selectedColor: ReelForgeTheme.accentBlue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : ReelForgeTheme.textPrimary,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            title: 'Channels',
            icon: Icons.surround_sound,
            child: Column(
              children: ChannelMode.values.map((mode) {
                return RadioListTile<ChannelMode>(
                  value: mode,
                  groupValue: _channelMode,
                  onChanged: (v) => setState(() => _channelMode = v!),
                  title: Text(
                    _getChannelModeName(mode),
                    style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 14),
                  ),
                  activeColor: ReelForgeTheme.accentBlue,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMp3Options() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _buildSection(
          title: 'MP3 Encoding',
          icon: Icons.compress,
          child: Column(
            children: [
              SwitchListTile(
                value: _mp3UseVbr,
                onChanged: (v) => setState(() => _mp3UseVbr = v),
                title: Text(
                  'Variable Bitrate (VBR)',
                  style: TextStyle(color: ReelForgeTheme.textPrimary),
                ),
                subtitle: Text(
                  'Better quality at smaller file size',
                  style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
                ),
                activeTrackColor: ReelForgeTheme.accentBlue,
                contentPadding: EdgeInsets.zero,
              ),
              if (_mp3UseVbr) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'VBR Quality',
                      style: TextStyle(color: ReelForgeTheme.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(0 = best, 9 = smallest)',
                      style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10),
                    ),
                    const Spacer(),
                    Text(
                      '$_mp3VbrQuality',
                      style: TextStyle(
                        color: ReelForgeTheme.textPrimary,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _mp3VbrQuality.toDouble(),
                  min: 0,
                  max: 9,
                  divisions: 9,
                  activeColor: ReelForgeTheme.accentBlue,
                  onChanged: (v) => setState(() => _mp3VbrQuality = v.round()),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Bitrate',
                      style: TextStyle(color: ReelForgeTheme.textSecondary),
                    ),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _mp3Bitrate,
                      dropdownColor: ReelForgeTheme.bgMid,
                      style: TextStyle(color: ReelForgeTheme.textPrimary),
                      items: [128, 160, 192, 224, 256, 320].map((rate) {
                        return DropdownMenuItem(
                          value: rate,
                          child: Text('$rate kbps'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _mp3Bitrate = v);
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFlacOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _buildSection(
          title: 'FLAC Compression',
          icon: Icons.compress,
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Compression Level',
                    style: TextStyle(color: ReelForgeTheme.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(0 = fastest, 8 = smallest)',
                    style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10),
                  ),
                  const Spacer(),
                  Text(
                    '$_flacCompression',
                    style: TextStyle(
                      color: ReelForgeTheme.textPrimary,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
              Slider(
                value: _flacCompression.toDouble(),
                min: 0,
                max: 8,
                divisions: 8,
                activeColor: ReelForgeTheme.accentBlue,
                onChanged: (v) => setState(() => _flacCompression = v.round()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDitheringTab() {
    final needsDither = _bitDepth < 32 &&
        (_format == AudioFormat.wav || _format == AudioFormat.aiff);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!needsDither)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ReelForgeTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ReelForgeTheme.accentBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: ReelForgeTheme.accentBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _format == AudioFormat.mp3 || _format == AudioFormat.ogg || _format == AudioFormat.opus
                          ? 'Dithering is not applicable for lossy formats'
                          : 'Dithering is only needed when reducing bit depth (32-bit float to 24/16-bit)',
                      style: TextStyle(color: ReelForgeTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          if (needsDither) ...[
            _buildSection(
              title: 'Dither Type',
              icon: Icons.blur_on,
              child: Column(
                children: DitherType.values.map((type) {
                  return RadioListTile<DitherType>(
                    value: type,
                    groupValue: _ditherType,
                    onChanged: (v) => setState(() => _ditherType = v!),
                    title: Text(
                      _getDitherName(type),
                      style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 14),
                    ),
                    subtitle: Text(
                      _getDitherDescription(type),
                      style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
                    ),
                    activeColor: ReelForgeTheme.accentBlue,
                    dense: true,
                  );
                }).toList(),
              ),
            ),
            if (_ditherType != DitherType.none) ...[
              const SizedBox(height: 20),
              _buildSection(
                title: 'Noise Shaping',
                icon: Icons.show_chart,
                child: Column(
                  children: NoiseShaping.values.map((ns) {
                    return RadioListTile<NoiseShaping>(
                      value: ns,
                      groupValue: _noiseShaping,
                      onChanged: (v) => setState(() => _noiseShaping = v!),
                      title: Text(
                        _getNoiseShapingName(ns),
                        style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 14),
                      ),
                      subtitle: Text(
                        _getNoiseShapingDescription(ns),
                        style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
                      ),
                      activeColor: ReelForgeTheme.accentBlue,
                      dense: true,
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildNormalizeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: 'Normalization Mode',
            icon: Icons.equalizer,
            child: Column(
              children: NormalizeMode.values.map((mode) {
                return RadioListTile<NormalizeMode>(
                  value: mode,
                  groupValue: _normalizeMode,
                  onChanged: (v) => setState(() => _normalizeMode = v!),
                  title: Text(
                    _getNormalizeModeName(mode),
                    style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 14),
                  ),
                  subtitle: Text(
                    _getNormalizeModeDescription(mode),
                    style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
                  ),
                  activeColor: ReelForgeTheme.accentBlue,
                  dense: true,
                );
              }).toList(),
            ),
          ),
          if (_normalizeMode != NormalizeMode.none) ...[
            const SizedBox(height: 20),
            _buildSection(
              title: 'Target Level',
              icon: Icons.volume_up,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _normalizeTarget,
                          min: _normalizeMode == NormalizeMode.lufsIntegrated ||
                                  _normalizeMode == NormalizeMode.lufsShortTerm
                              ? -24
                              : -12,
                          max: 0,
                          divisions: 48,
                          activeColor: ReelForgeTheme.accentBlue,
                          onChanged: (v) => setState(() => _normalizeTarget = v),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          '${_normalizeTarget.toStringAsFixed(1)} ${_normalizeMode == NormalizeMode.lufsIntegrated || _normalizeMode == NormalizeMode.lufsShortTerm ? 'LUFS' : 'dB'}',
                          style: TextStyle(
                            color: ReelForgeTheme.textPrimary,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _getTargetPresets().map((preset) {
                      final isSelected = (_normalizeTarget - preset).abs() < 0.1;
                      return ActionChip(
                        label: Text('${preset.toStringAsFixed(0)} ${_normalizeMode == NormalizeMode.lufsIntegrated || _normalizeMode == NormalizeMode.lufsShortTerm ? 'LUFS' : 'dB'}'),
                        backgroundColor:
                            isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.bgSurface,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : ReelForgeTheme.textSecondary,
                          fontSize: 11,
                        ),
                        onPressed: () => setState(() => _normalizeTarget = preset),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<double> _getTargetPresets() {
    if (_normalizeMode == NormalizeMode.lufsIntegrated ||
        _normalizeMode == NormalizeMode.lufsShortTerm) {
      return [-14, -16, -18, -20, -23];
    }
    return [0, -1, -3, -6, -10];
  }

  Widget _buildOptionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: 'Tail Time',
            icon: Icons.timer,
            child: Column(
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
                      width: 60,
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
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            title: 'After Bounce',
            icon: Icons.check_circle,
            child: Column(
              children: [
                SwitchListTile(
                  value: _addToPool,
                  onChanged: (v) => setState(() => _addToPool = v),
                  title: Text(
                    'Add to Audio Pool',
                    style: TextStyle(color: ReelForgeTheme.textPrimary),
                  ),
                  subtitle: Text(
                    'Import bounced file into project audio pool',
                    style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
                  ),
                  activeColor: ReelForgeTheme.accentGreen,
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: _exportMarkers,
                  onChanged: (v) => setState(() => _exportMarkers = v),
                  title: Text(
                    'Export Markers',
                    style: TextStyle(color: ReelForgeTheme.textPrimary),
                  ),
                  subtitle: Text(
                    'Create .txt file with marker positions',
                    style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
                  ),
                  activeColor: ReelForgeTheme.accentGreen,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        border: Border(top: BorderSide(color: ReelForgeTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: ReelForgeTheme.accentBlue),
              const SizedBox(width: 8),
              Text(
                'Range',
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _buildRangeChip('All', 'all'),
              if (widget.selectionStart != null) _buildRangeChip('Selection', 'selection'),
              if (widget.loopRegion != null) _buildRangeChip('Loop', 'loop'),
              _buildRangeChip('Custom', 'custom'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTimeField('Start', _startTime, (v) {
                  setState(() {
                    _startTime = v;
                    _rangeMode = 'custom';
                  });
                }),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTimeField('End', _endTime, (v) {
                  setState(() {
                    _endTime = v;
                    _rangeMode = 'custom';
                  });
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRangeChip(String label, String mode) {
    final isSelected = _rangeMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _rangeMode = mode;
          if (mode == 'all') {
            _startTime = widget.projectStart;
            _endTime = widget.projectEnd;
          } else if (mode == 'selection' && widget.selectionStart != null) {
            _startTime = widget.selectionStart!;
            _endTime = widget.selectionEnd!;
          } else if (mode == 'loop' && widget.loopRegion != null) {
            _startTime = widget.loopRegion!.$1;
            _endTime = widget.loopRegion!.$2;
          }
        });
      },
      backgroundColor: ReelForgeTheme.bgMid,
      selectedColor: ReelForgeTheme.accentBlue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : ReelForgeTheme.textSecondary,
        fontSize: 12,
      ),
    );
  }

  Widget _buildTimeField(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: ReelForgeTheme.borderSubtle),
          ),
          child: Text(
            _formatTime(value),
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ],
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
            onPressed: _handleBounce,
            icon: const Icon(Icons.album, size: 18),
            label: const Text('Bounce'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentOrange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _handleBounce() {
    final options = BounceOptions(
      format: _format,
      bitDepth: _bitDepth,
      sampleRate: _sampleRate,
      ditherType: _ditherType,
      noiseShaping: _noiseShaping,
      channelMode: _channelMode,
      normalizeMode: _normalizeMode,
      normalizeTarget: _normalizeTarget,
      tailTime: _tailTime,
      startTime: _startTime,
      endTime: _endTime,
      mp3Bitrate: _mp3Bitrate,
      mp3VbrQuality: _mp3VbrQuality,
      mp3UseVbr: _mp3UseVbr,
      flacCompression: _flacCompression,
      exportMarkers: _exportMarkers,
      addToPool: _addToPool,
    );
    Navigator.of(context).pop(options);
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 1000).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}s';
    }
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _getFormatName(AudioFormat format) {
    switch (format) {
      case AudioFormat.wav:
        return 'WAV';
      case AudioFormat.aiff:
        return 'AIFF';
      case AudioFormat.flac:
        return 'FLAC';
      case AudioFormat.mp3:
        return 'MP3';
      case AudioFormat.ogg:
        return 'OGG';
      case AudioFormat.opus:
        return 'OPUS';
    }
  }

  String _getChannelModeName(ChannelMode mode) {
    switch (mode) {
      case ChannelMode.mono:
        return 'Mono';
      case ChannelMode.stereo:
        return 'Stereo';
      case ChannelMode.monoSum:
        return 'Mono (L+R Sum)';
      case ChannelMode.leftOnly:
        return 'Left Only';
      case ChannelMode.rightOnly:
        return 'Right Only';
      case ChannelMode.midSide:
        return 'Mid/Side';
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
      case DitherType.powR:
        return 'POW-r';
      case DitherType.mbit:
        return 'MBIT+';
    }
  }

  String _getDitherDescription(DitherType type) {
    switch (type) {
      case DitherType.none:
        return 'No dithering (truncation only)';
      case DitherType.triangular:
        return 'Standard industry dither, neutral';
      case DitherType.rectangular:
        return 'Simple dither, minimal processing';
      case DitherType.shapedNoise:
        return 'Shaped noise for reduced audibility';
      case DitherType.powR:
        return 'Professional quality, transparent';
      case DitherType.mbit:
        return 'High-end mastering grade dither';
    }
  }

  String _getNoiseShapingName(NoiseShaping ns) {
    switch (ns) {
      case NoiseShaping.none:
        return 'None';
      case NoiseShaping.light:
        return 'Light';
      case NoiseShaping.medium:
        return 'Medium';
      case NoiseShaping.heavy:
        return 'Heavy';
      case NoiseShaping.ultraHeavy:
        return 'Ultra';
    }
  }

  String _getNoiseShapingDescription(NoiseShaping ns) {
    switch (ns) {
      case NoiseShaping.none:
        return 'Flat noise spectrum';
      case NoiseShaping.light:
        return 'Subtle high-frequency shift';
      case NoiseShaping.medium:
        return 'Moderate psychoacoustic shaping';
      case NoiseShaping.heavy:
        return 'Strong high-frequency shaping';
      case NoiseShaping.ultraHeavy:
        return 'Maximum noise reduction perception';
    }
  }

  String _getNormalizeModeName(NormalizeMode mode) {
    switch (mode) {
      case NormalizeMode.none:
        return 'Off';
      case NormalizeMode.peak:
        return 'Peak';
      case NormalizeMode.lufsIntegrated:
        return 'LUFS (Integrated)';
      case NormalizeMode.lufsShortTerm:
        return 'LUFS (Short-term)';
      case NormalizeMode.rms:
        return 'RMS';
      case NormalizeMode.truePeak:
        return 'True Peak';
    }
  }

  String _getNormalizeModeDescription(NormalizeMode mode) {
    switch (mode) {
      case NormalizeMode.none:
        return 'No normalization applied';
      case NormalizeMode.peak:
        return 'Normalize to peak sample value';
      case NormalizeMode.lufsIntegrated:
        return 'ITU-R BS.1770 loudness (full file)';
      case NormalizeMode.lufsShortTerm:
        return 'ITU-R BS.1770 loudness (3s window)';
      case NormalizeMode.rms:
        return 'Root Mean Square level';
      case NormalizeMode.truePeak:
        return 'Inter-sample peak detection';
    }
  }
}
