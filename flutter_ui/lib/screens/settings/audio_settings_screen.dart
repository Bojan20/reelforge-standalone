/// Audio Settings Screen
///
/// Allows users to configure:
/// - Output device selection
/// - Input device selection
/// - Sample rate
/// - Buffer size
/// - Test audio output

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

// Mock types until flutter_rust_bridge generates them
class AudioDeviceInfo {
  final String name;
  final bool isDefault;
  final int channels;
  final List<int> sampleRates;

  AudioDeviceInfo({
    required this.name,
    required this.isDefault,
    required this.channels,
    required this.sampleRates,
  });
}

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
  List<AudioDeviceInfo> _outputDevices = [];
  List<AudioDeviceInfo> _inputDevices = [];
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
      // TODO: Call actual Rust functions when bridge is generated
      // _outputDevices = await api.audioListOutputDevices();
      // _inputDevices = await api.audioListInputDevices();
      // _hostInfo = await api.audioGetHostInfo();
      // _currentSettings = await api.audioGetCurrentSettings();

      // Mock data for now
      _outputDevices = [
        AudioDeviceInfo(
          name: 'MacBook Pro Speakers',
          isDefault: true,
          channels: 2,
          sampleRates: [44100, 48000, 96000],
        ),
        AudioDeviceInfo(
          name: 'External Audio Interface',
          isDefault: false,
          channels: 8,
          sampleRates: [44100, 48000, 88200, 96000, 176400, 192000],
        ),
      ];

      _inputDevices = [
        AudioDeviceInfo(
          name: 'MacBook Pro Microphone',
          isDefault: true,
          channels: 1,
          sampleRates: [44100, 48000],
        ),
        AudioDeviceInfo(
          name: 'External Audio Interface',
          isDefault: false,
          channels: 8,
          sampleRates: [44100, 48000, 88200, 96000, 176400, 192000],
        ),
      ];

      _hostInfo = AudioHostInfo(
        name: 'CoreAudio',
        isAsio: false,
        isJack: false,
        isCoreAudio: true,
      );

      _currentSettings = AudioSettings(
        outputDevice: _outputDevices.firstWhere((d) => d.isDefault).name,
        inputDevice: _inputDevices.firstWhere((d) => d.isDefault).name,
        sampleRate: 48000,
        bufferSize: 256,
        latencyMs: 5.3,
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

    // TODO: Call Rust
    // await api.audioSetOutputDevice(deviceName);

    // Update available sample rates
    final device = _outputDevices.firstWhere(
      (d) => d.name == deviceName,
      orElse: () => _outputDevices.first,
    );

    if (!device.sampleRates.contains(_selectedSampleRate)) {
      setState(() => _selectedSampleRate = device.sampleRates.first);
    }
  }

  Future<void> _setInputDevice(String? deviceName) async {
    if (deviceName == null) return;

    setState(() => _selectedInputDevice = deviceName);

    // TODO: Call Rust
    // await api.audioSetInputDevice(deviceName);
  }

  Future<void> _setSampleRate(int? rate) async {
    if (rate == null) return;

    setState(() => _selectedSampleRate = rate);

    // TODO: Call Rust
    // await api.audioSetSampleRate(rate);
  }

  Future<void> _setBufferSize(int? size) async {
    if (size == null) return;

    setState(() => _selectedBufferSize = size);

    // TODO: Call Rust
    // await api.audioSetBufferSize(size);
  }

  Future<void> _testAudio() async {
    setState(() => _isTesting = true);

    // TODO: Call Rust
    // await api.audioTestOutput();

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() => _isTesting = false);
  }

  double get _calculatedLatency {
    return (_selectedBufferSize / _selectedSampleRate) * 1000;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReelForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: ReelForgeTheme.bgMid,
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
        color: ReelForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            Icons.audiotrack,
            color: ReelForgeTheme.accentBlue,
            size: 32,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audio Backend',
                style: TextStyle(
                  color: ReelForgeTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                hostType,
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
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
        dropdownColor: ReelForgeTheme.bgMid,
        style: TextStyle(color: ReelForgeTheme.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: ReelForgeTheme.bgSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                      color: ReelForgeTheme.accentGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Default',
                      style: TextStyle(
                        color: ReelForgeTheme.accentGreen,
                        fontSize: 10,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${device.channels}ch',
                  style: TextStyle(
                    color: ReelForgeTheme.textSecondary,
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
        dropdownColor: ReelForgeTheme.bgMid,
        style: TextStyle(color: ReelForgeTheme.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: ReelForgeTheme.bgSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                      color: ReelForgeTheme.accentGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Default',
                      style: TextStyle(
                        color: ReelForgeTheme.accentGreen,
                        fontSize: 10,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${device.channels}ch',
                  style: TextStyle(
                    color: ReelForgeTheme.textSecondary,
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
        .firstWhere(
          (d) => d.name == _selectedOutputDevice,
          orElse: () => _outputDevices.first,
        )
        .sampleRates;

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
            backgroundColor: ReelForgeTheme.bgSurface,
            selectedColor: ReelForgeTheme.accentBlue,
            disabledColor: ReelForgeTheme.bgMid,
            labelStyle: TextStyle(
              color: isSelected
                  ? ReelForgeTheme.textPrimary
                  : isAvailable
                      ? ReelForgeTheme.textPrimary
                      : ReelForgeTheme.textSecondary.withValues(alpha: 0.5),
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
                backgroundColor: ReelForgeTheme.bgSurface,
                selectedColor: ReelForgeTheme.accentBlue,
                labelStyle: TextStyle(
                  color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textPrimary,
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
                color: ReelForgeTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Lower = less latency, higher CPU usage',
                style: TextStyle(
                  color: ReelForgeTheme.textSecondary,
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
      latencyColor = ReelForgeTheme.accentGreen;
      latencyLabel = 'Excellent';
    } else if (latency < 6) {
      latencyColor = ReelForgeTheme.accentBlue;
      latencyLabel = 'Good';
    } else if (latency < 12) {
      latencyColor = ReelForgeTheme.accentOrange;
      latencyLabel = 'Moderate';
    } else {
      latencyColor = ReelForgeTheme.accentRed;
      latencyLabel = 'High';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
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
                  color: ReelForgeTheme.textSecondary,
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
            color: ReelForgeTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: ReelForgeTheme.textSecondary,
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
                  color: ReelForgeTheme.textPrimary,
                ),
              )
            : const Icon(Icons.play_arrow),
        label: Text(_isTesting ? 'Playing...' : 'Test Audio Output'),
        style: ElevatedButton.styleFrom(
          backgroundColor: ReelForgeTheme.accentBlue,
          foregroundColor: ReelForgeTheme.textPrimary,
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
            Icon(icon, color: ReelForgeTheme.accentBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: ReelForgeTheme.textPrimary,
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
