/// Recording Settings Screen
///
/// Configure recording options:
/// - Input device selection
/// - Output directory
/// - File format and bit depth
/// - Pre-roll settings
/// - Input monitoring

import 'dart:async';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/recording_provider.dart';
import '../../src/rust/native_ffi.dart';

/// Audio input device info
class AudioInputDevice {
  final int index;
  final String name;
  final int channels;
  final bool isDefault;

  const AudioInputDevice({
    required this.index,
    required this.name,
    required this.channels,
    required this.isDefault,
  });
}

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
  bool _autoDisarm = true;

  // Input device selection
  List<AudioInputDevice> _inputDevices = [];
  String? _selectedInputDevice;
  bool _loadingDevices = true;

  // Real-time meter refresh
  Timer? _meterTimer;
  double _peakL = 0.0;
  double _peakR = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadCurrentSettings();
    _startMeterTimer();
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    super.dispose();
  }

  void _startMeterTimer() {
    // Refresh meters at 30fps (33ms) for smooth visual feedback
    _meterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;

      final api = NativeFFI.instance;
      if (!api.isLoaded) return;

      final peaks = api.getInputPeaks();
      // Only rebuild if peaks changed significantly (avoid unnecessary rebuilds)
      if ((peaks.$1 - _peakL).abs() > 0.001 || (peaks.$2 - _peakR).abs() > 0.001) {
        setState(() {
          _peakL = peaks.$1;
          _peakR = peaks.$2;
        });
      }
    });
  }

  Future<void> _loadDevices() async {
    final api = NativeFFI.instance;
    if (!api.isLoaded) {
      setState(() => _loadingDevices = false);
      return;
    }

    // Refresh device list
    api.audioRefreshDevices();

    // Get input devices
    final count = api.audioGetInputDeviceCount();
    final devices = <AudioInputDevice>[];

    for (var i = 0; i < count; i++) {
      final namePtr = api.audioGetInputDeviceName(i);
      final name = namePtr.toDartString();
      api.freeString(namePtr);

      final channels = api.audioGetInputDeviceChannels(i);
      final isDefault = api.audioIsInputDeviceDefault(i) == 1;

      devices.add(AudioInputDevice(
        index: i,
        name: name,
        channels: channels,
        isDefault: isDefault,
      ));
    }

    // Get current input device
    final currentPtr = api.audioGetCurrentInputDevice();
    final currentName = currentPtr.address != 0 ? currentPtr.toDartString() : null;
    if (currentPtr.address != 0) {
      api.freeString(currentPtr);
    }

    setState(() {
      _inputDevices = devices;
      _selectedInputDevice = currentName;
      _loadingDevices = false;
    });
  }

  void _loadCurrentSettings() {
    final recording = context.read<RecordingProvider>();
    setState(() {
      _outputDir = recording.outputDir;
      _preRollSecs = recording.preRollSeconds;
      _capturePreRoll = recording.preRollEnabled;
      _autoDisarm = recording.autoDisarmAfterPunchOut;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('Recording Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Devices',
            onPressed: () {
              setState(() => _loadingDevices = true);
              _loadDevices();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInputDeviceSection(),
            const SizedBox(height: 32),
            _buildOutputSection(),
            const SizedBox(height: 32),
            _buildFormatSection(),
            const SizedBox(height: 32),
            _buildPreRollSection(),
            const SizedBox(height: 32),
            _buildPunchSection(),
            const SizedBox(height: 32),
            _buildMonitoringSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputDeviceSection() {
    return _buildSection(
      title: 'Input Device',
      icon: Icons.mic,
      children: [
        if (_loadingDevices)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_inputDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FluxForgeTheme.accentOrange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: FluxForgeTheme.accentOrange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No input devices found. Check your audio interface connection.',
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else ...[
          DropdownButtonFormField<String>(
            value: _selectedInputDevice,
            decoration: InputDecoration(
              filled: true,
              fillColor: FluxForgeTheme.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            dropdownColor: FluxForgeTheme.bgMid,
            style: TextStyle(color: FluxForgeTheme.textPrimary),
            items: _inputDevices.map((device) {
              return DropdownMenuItem(
                value: device.name,
                child: Row(
                  children: [
                    if (device.isDefault)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.star, color: FluxForgeTheme.accentGreen, size: 14),
                      ),
                    Expanded(
                      child: Text(
                        device.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${device.channels}ch',
                      style: TextStyle(
                        color: FluxForgeTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) => _setInputDevice(value),
          ),
          const SizedBox(height: 12),
          // Input level meter placeholder
          _buildInputLevelMeter(),
        ],
      ],
    );
  }

  Widget _buildInputLevelMeter() {
    // Use cached peak values (updated by timer)
    final peakL = _peakL;
    final peakR = _peakR;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Input Level',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('L', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(child: _buildMeterBar(peakL)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('R', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(child: _buildMeterBar(peakR)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeterBar(double level) {
    // Clamp to 0-1
    final clamped = level.clamp(0.0, 1.0);
    // Convert to dB for color (-60 to 0 dB range)
    final db = clamped > 0.001 ? 20 * math.log(clamped) / math.ln10 : -60.0;

    Color getColor() {
      if (db > -3) return FluxForgeTheme.accentRed;
      if (db > -12) return FluxForgeTheme.accentOrange;
      return FluxForgeTheme.accentGreen;
    }

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: clamped,
        child: Container(
          decoration: BoxDecoration(
            color: getColor(),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  void _setInputDevice(String? deviceName) async {
    if (deviceName == null) return;

    final api = NativeFFI.instance;
    if (!api.isLoaded) return;

    final namePtr = deviceName.toNativeUtf8();
    final result = api.audioSetInputDevice(namePtr);
    calloc.free(namePtr);

    if (result == 1) {
      setState(() => _selectedInputDevice = deviceName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Input device set to: $deviceName'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FluxForgeTheme.bgMid,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set input device'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FluxForgeTheme.accentRed,
          ),
        );
      }
    }
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: FluxForgeTheme.accentRed, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
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
            color: FluxForgeTheme.textSecondary,
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
                  color: FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                ),
                child: Text(
                  _outputDir,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontFamily: FluxForgeTheme.monoFontFamily,
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
                backgroundColor: FluxForgeTheme.bgSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'File Name Prefix',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: _filePrefix),
          onChanged: (value) => _filePrefix = value,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: FluxForgeTheme.bgSurface,
            hintText: 'e.g., Recording',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
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
            color: FluxForgeTheme.textSecondary,
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
              backgroundColor: FluxForgeTheme.bgSurface,
              selectedColor: FluxForgeTheme.accentBlue,
              labelStyle: TextStyle(
                color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textPrimary,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: FluxForgeTheme.textTertiary),
            const SizedBox(width: 8),
            Text(
              _bitDepth == 16
                  ? 'CD quality - smaller files'
                  : _bitDepth == 24
                      ? 'Studio quality - recommended'
                      : 'Maximum quality - largest files',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
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
              color: FluxForgeTheme.textSecondary,
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
              color: FluxForgeTheme.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPunchSection() {
    return _buildSection(
      title: 'Punch Recording',
      icon: Icons.fiber_manual_record,
      children: [
        _buildSwitch(
          label: 'Auto-disarm after punch-out',
          value: _autoDisarm,
          onChanged: (v) {
            setState(() => _autoDisarm = v);
            context.read<RecordingProvider>().setAutoDisarmAfterPunchOut(v);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Automatically disarm all tracks when punch-out completes',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
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
            NativeFFI.instance.setInputMonitoring(v);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Hear input signal through output while recording',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
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
                color: FluxForgeTheme.accentOrange,
              ),
              const SizedBox(width: 8),
              Text(
                'Use headphones to avoid feedback',
                style: TextStyle(
                  color: FluxForgeTheme.accentOrange,
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
            color: FluxForgeTheme.textPrimary,
            fontSize: 13,
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: FluxForgeTheme.accentBlue,
        ),
      ],
    );
  }

  void _browseOutputDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Recording Output Directory',
    );

    if (result != null) {
      setState(() => _outputDir = result);

      // Update recording provider
      final recording = context.read<RecordingProvider>();
      await recording.setOutputDir(result);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Output directory set to: $result'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: FluxForgeTheme.bgMid,
          ),
        );
      }
    }
  }
}

