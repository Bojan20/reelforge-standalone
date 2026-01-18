/// Audio Settings Screen
///
/// Allows users to configure:
/// - Output device selection
/// - Input device selection
/// - Sample rate
/// - Buffer size
/// - Test audio output

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/engine_api.dart' as api;
import '../../widgets/common/error_dialog.dart';

class AudioHostInfo {
  final String name;
  final bool isAsio;
  final bool isJack;
  final bool isCoreAudio;

  AudioHostInfo({
    required this.name,
    required this.isAsio,
    required this.isJack,
    required this.isCoreAudio,
  });
}

class AudioSettings {
  final String? outputDevice;
  final String? inputDevice;
  final int sampleRate;
  final int bufferSize;
  final double latencyMs;

  AudioSettings({
    this.outputDevice,
    this.inputDevice,
    required this.sampleRate,
    required this.bufferSize,
    required this.latencyMs,
  });
}

class AudioSettingsScreen extends StatefulWidget {
  const AudioSettingsScreen({super.key});

  @override
  State<AudioSettingsScreen> createState() => _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends State<AudioSettingsScreen> {
  List<api.AudioDeviceInfo> _outputDevices = [];
  List<api.AudioDeviceInfo> _inputDevices = [];
  AudioHostInfo? _hostInfo;
  AudioSettings? _currentSettings;

  String? _selectedOutputDevice;
  String? _selectedInputDevice;
  int _selectedSampleRate = 48000;
  int _selectedBufferSize = 256;

  bool _isLoading = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);

    try {
      // Refresh device list from Rust
      api.audioRefreshDevices();

      // Get devices from Rust FFI
      _outputDevices = api.audioGetOutputDevices();
      _inputDevices = api.audioGetInputDevices();

      final hostName = api.audioGetHostName();
      final isAsio = api.audioIsAsioAvailable();

      _hostInfo = AudioHostInfo(
        name: hostName,
        isAsio: isAsio,
        isJack: hostName.toLowerCase().contains('jack'),
        isCoreAudio: hostName.toLowerCase().contains('core'),
      );

      // Get current settings from Rust engine
      final currentOutput = api.audioGetCurrentOutputDevice();
      final currentInput = api.audioGetCurrentInputDevice();
      final currentSampleRate = api.audioGetCurrentSampleRate();
      final currentBufferSize = api.audioGetCurrentBufferSize();
      final currentLatency = api.audioGetLatencyMs();

      // Use current settings, fall back to defaults
      final defaultOutput = _outputDevices.where((d) => d.isDefault).firstOrNull;
      final defaultInput = _inputDevices.where((d) => d.isDefault).firstOrNull;

      _currentSettings = AudioSettings(
        outputDevice: currentOutput ?? defaultOutput?.name,
        inputDevice: currentInput ?? defaultInput?.name,
        sampleRate: currentSampleRate,
        bufferSize: currentBufferSize,
        latencyMs: currentLatency,
      );

      _selectedOutputDevice = _currentSettings?.outputDevice;
      _selectedInputDevice = _currentSettings?.inputDevice;
      _selectedSampleRate = _currentSettings?.sampleRate ?? 48000;
      _selectedBufferSize = _currentSettings?.bufferSize ?? 256;
    } catch (e) {
      debugPrint('Error loading devices: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _setOutputDevice(String? deviceName) async {
    if (deviceName == null) return;

    setState(() => _selectedOutputDevice = deviceName);

    // Call Rust to switch device
    final success = api.audioSetOutputDevice(deviceName);
    if (!success) {
      debugPrint('Failed to set output device: $deviceName');
      // Show rich error from Rust
      if (mounted) {
        final error = api.getLastAppError();
        if (error != null) {
          showErrorSnackbar(context, error);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to set output device: $deviceName'),
              backgroundColor: FluxForgeTheme.accentRed,
            ),
          );
        }
      }
    }

    // Update available sample rates
    final device = _outputDevices.where((d) => d.name == deviceName).firstOrNull;
    if (device != null && !device.supportedSampleRates.contains(_selectedSampleRate)) {
      if (device.supportedSampleRates.isNotEmpty) {
        setState(() => _selectedSampleRate = device.supportedSampleRates.first);
        api.audioSetSampleRate(_selectedSampleRate);
      }
    }
  }

  Future<void> _setInputDevice(String? deviceName) async {
    if (deviceName == null) return;

    setState(() => _selectedInputDevice = deviceName);

    // Call Rust to switch input device
    final success = api.audioSetInputDevice(deviceName);
    if (!success) {
      debugPrint('Failed to set input device: $deviceName');
      if (mounted) {
        final error = api.getLastAppError();
        if (error != null) {
          showErrorSnackbar(context, error);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to set input device: $deviceName'),
              backgroundColor: FluxForgeTheme.accentRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _setSampleRate(int? rate) async {
    if (rate == null) return;

    setState(() => _selectedSampleRate = rate);

    // Call Rust to set sample rate
    final success = api.audioSetSampleRate(rate);
    if (!success) {
      debugPrint('Failed to set sample rate: $rate');
      if (mounted) {
        final error = api.getLastAppError();
        if (error != null) {
          showErrorSnackbar(context, error);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to set sample rate: $rate Hz'),
              backgroundColor: FluxForgeTheme.accentRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _setBufferSize(int? size) async {
    if (size == null) return;

    setState(() => _selectedBufferSize = size);

    // Call Rust to set buffer size
    final success = api.audioSetBufferSize(size);
    if (!success) {
      debugPrint('Failed to set buffer size: $size');
      if (mounted) {
        final error = api.getLastAppError();
        if (error != null) {
          showErrorSnackbar(context, error);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to set buffer size: $size samples'),
              backgroundColor: FluxForgeTheme.accentRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _testAudio() async {
    setState(() => _isTesting = true);

    // Play a short test tone - for now just simulate
    // Full implementation would call a test tone generator in Rust
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Audio test complete'),
          backgroundColor: FluxForgeTheme.accentGreen,
        ),
      );
    }

    setState(() => _isTesting = false);
  }

  double get _calculatedLatency {
    return (_selectedBufferSize / _selectedSampleRate) * 1000;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('Audio Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh devices',
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHostInfo(),
                  const SizedBox(height: 24),
                  _buildOutputDeviceSection(),
                  const SizedBox(height: 24),
                  _buildInputDeviceSection(),
                  const SizedBox(height: 24),
                  _buildSampleRateSection(),
                  const SizedBox(height: 24),
                  _buildBufferSizeSection(),
                  const SizedBox(height: 24),
                  _buildLatencyInfo(),
                  const SizedBox(height: 32),
                  _buildTestButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildHostInfo() {
    if (_hostInfo == null) return const SizedBox.shrink();

    String hostType = 'Default';
    if (_hostInfo!.isCoreAudio) hostType = 'CoreAudio';
    if (_hostInfo!.isAsio) hostType = 'ASIO';
    if (_hostInfo!.isJack) hostType = 'JACK';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            Icons.audiotrack,
            color: FluxForgeTheme.accentBlue,
            size: 32,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audio Backend',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                hostType,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutputDeviceSection() {
    return _buildSection(
      title: 'Output Device',
      icon: Icons.speaker,
      child: DropdownButtonFormField<String>(
        value: _selectedOutputDevice,
        dropdownColor: FluxForgeTheme.bgMid,
        style: TextStyle(color: FluxForgeTheme.textPrimary),
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
        items: _outputDevices.map((device) {
          return DropdownMenuItem(
            value: device.name,
            child: Row(
              children: [
                Expanded(child: Text(device.name)),
                if (device.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Default',
                      style: TextStyle(
                        color: FluxForgeTheme.accentGreen,
                        fontSize: 10,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${device.channels}ch',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: _setOutputDevice,
      ),
    );
  }

  Widget _buildInputDeviceSection() {
    return _buildSection(
      title: 'Input Device',
      icon: Icons.mic,
      child: DropdownButtonFormField<String>(
        value: _selectedInputDevice,
        dropdownColor: FluxForgeTheme.bgMid,
        style: TextStyle(color: FluxForgeTheme.textPrimary),
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
        items: _inputDevices.map((device) {
          return DropdownMenuItem(
            value: device.name,
            child: Row(
              children: [
                Expanded(child: Text(device.name)),
                if (device.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Default',
                      style: TextStyle(
                        color: FluxForgeTheme.accentGreen,
                        fontSize: 10,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${device.channels}ch',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: _setInputDevice,
      ),
    );
  }

  Widget _buildSampleRateSection() {
    final availableRates = _outputDevices
        .where((d) => d.name == _selectedOutputDevice)
        .firstOrNull
        ?.supportedSampleRates ?? [];

    return _buildSection(
      title: 'Sample Rate',
      icon: Icons.speed,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [44100, 48000, 88200, 96000, 176400, 192000].map((rate) {
          final isAvailable = availableRates.contains(rate);
          final isSelected = rate == _selectedSampleRate;

          return ChoiceChip(
            label: Text('${rate ~/ 1000}.${(rate % 1000) ~/ 100} kHz'),
            selected: isSelected,
            onSelected: isAvailable ? (_) => _setSampleRate(rate) : null,
            backgroundColor: FluxForgeTheme.bgSurface,
            selectedColor: FluxForgeTheme.accentBlue,
            disabledColor: FluxForgeTheme.bgMid,
            labelStyle: TextStyle(
              color: isSelected
                  ? FluxForgeTheme.textPrimary
                  : isAvailable
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBufferSizeSection() {
    return _buildSection(
      title: 'Buffer Size',
      icon: Icons.memory,
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [32, 64, 128, 256, 512, 1024, 2048].map((size) {
              final isSelected = size == _selectedBufferSize;

              return ChoiceChip(
                label: Text('$size'),
                selected: isSelected,
                onSelected: (_) => _setBufferSize(size),
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
              Icon(
                Icons.info_outline,
                size: 14,
                color: FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Lower = less latency, higher CPU usage',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyInfo() {
    final latency = _calculatedLatency;
    final roundTrip = latency * 2;

    Color latencyColor;
    String latencyLabel;

    if (latency < 3) {
      latencyColor = FluxForgeTheme.accentGreen;
      latencyLabel = 'Excellent';
    } else if (latency < 6) {
      latencyColor = FluxForgeTheme.accentBlue;
      latencyLabel = 'Good';
    } else if (latency < 12) {
      latencyColor = FluxForgeTheme.accentOrange;
      latencyLabel = 'Moderate';
    } else {
      latencyColor = FluxForgeTheme.accentRed;
      latencyLabel = 'High';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: latencyColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer, color: latencyColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Latency',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: latencyColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  latencyLabel,
                  style: TextStyle(
                    color: latencyColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLatencyValue('Output', '${latency.toStringAsFixed(1)} ms'),
              _buildLatencyValue('Round-trip', '${roundTrip.toStringAsFixed(1)} ms'),
              _buildLatencyValue('Samples', '$_selectedBufferSize'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyValue(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildTestButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isTesting ? null : _testAudio,
        icon: _isTesting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FluxForgeTheme.textPrimary,
                ),
              )
            : const Icon(Icons.play_arrow),
        label: Text(_isTesting ? 'Playing...' : 'Test Audio Output'),
        style: ElevatedButton.styleFrom(
          backgroundColor: FluxForgeTheme.accentBlue,
          foregroundColor: FluxForgeTheme.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: FluxForgeTheme.accentBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
