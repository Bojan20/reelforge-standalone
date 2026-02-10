/// P3.1: Audio Settings Panel
///
/// Configurable audio device, sample rate, and buffer size settings.
/// Uses FFI bindings to query and configure the audio engine.
///
/// Created: 2026-01-29
library;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import '../../../../src/rust/native_ffi.dart';
import '../../lower_zone_types.dart';
import 'panel_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO DEVICE INFO MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Represents an audio device with its properties
class AudioDeviceInfo {
  final int index;
  final String name;
  final bool isDefault;
  final int channelCount;
  final List<int> supportedSampleRates;

  const AudioDeviceInfo({
    required this.index,
    required this.name,
    required this.isDefault,
    required this.channelCount,
    this.supportedSampleRates = const [],
  });

  @override
  String toString() => '$name${isDefault ? ' (Default)' : ''}';
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO SETTINGS PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Comprehensive audio settings panel for configuring devices, sample rate,
/// and buffer size with real-time latency calculation.
class AudioSettingsPanel extends StatefulWidget {
  /// Callback when settings are applied
  final VoidCallback? onSettingsApplied;

  const AudioSettingsPanel({
    super.key,
    this.onSettingsApplied,
  });

  @override
  State<AudioSettingsPanel> createState() => _AudioSettingsPanelState();
}

class _AudioSettingsPanelState extends State<AudioSettingsPanel> {
  // Device lists
  List<AudioDeviceInfo> _outputDevices = [];
  List<AudioDeviceInfo> _inputDevices = [];

  // Current selections
  String? _selectedOutputDevice;
  String? _selectedInputDevice;
  int _selectedSampleRate = 48000;
  int _selectedBufferSize = 256;

  // Current engine settings (read from FFI)
  String? _currentOutputDevice;
  String? _currentInputDevice;
  int _currentSampleRate = 48000;
  int _currentBufferSize = 256;

  // UI state
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _errorMessage;

  // Available buffer sizes (powers of 2)
  static const List<int> _bufferSizes = [32, 64, 128, 256, 512, 1024, 2048, 4096];

  // Common sample rates
  static const List<int> _commonSampleRates = [44100, 48000, 88200, 96000, 176400, 192000];

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadCurrentSettings();
  }

  /// Load available audio devices from FFI
  void _loadDevices() {
    setState(() => _isLoading = true);

    try {
      final ffi = NativeFFI.instance;

      // Refresh device cache
      ffi.audioRefreshDevices();

      // Load output devices
      final outputCount = ffi.audioGetOutputDeviceCount();
      _outputDevices = List.generate(outputCount, (i) {
        final namePtr = ffi.audioGetOutputDeviceName(i);
        final name = namePtr.address != 0 ? namePtr.toDartString() : 'Unknown Device $i';

        final isDefault = ffi.audioIsOutputDeviceDefault(i) == 1;
        final channels = ffi.audioGetOutputDeviceChannels(i);

        // Get supported sample rates
        final rateCount = ffi.audioGetOutputDeviceSampleRateCount(i);
        final rates = List.generate(rateCount, (r) => ffi.audioGetOutputDeviceSampleRate(i, r));

        return AudioDeviceInfo(
          index: i,
          name: name,
          isDefault: isDefault,
          channelCount: channels,
          supportedSampleRates: rates,
        );
      });

      // Load input devices
      final inputCount = ffi.audioGetInputDeviceCount();
      _inputDevices = List.generate(inputCount, (i) {
        final namePtr = ffi.audioGetInputDeviceName(i);
        final name = namePtr.address != 0 ? namePtr.toDartString() : 'Unknown Device $i';

        final isDefault = ffi.audioIsInputDeviceDefault(i) == 1;
        final channels = ffi.audioGetInputDeviceChannels(i);

        return AudioDeviceInfo(
          index: i,
          name: name,
          isDefault: isDefault,
          channelCount: channels,
        );
      });

      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load devices: $e';
      });
    }
  }

  /// Load current engine settings from FFI
  void _loadCurrentSettings() {
    try {
      final ffi = NativeFFI.instance;

      // Get current output device
      final outputPtr = ffi.audioGetCurrentOutputDevice();
      if (outputPtr.address != 0) {
        _currentOutputDevice = outputPtr.toDartString();
        _selectedOutputDevice = _currentOutputDevice;
      }

      // Get current input device
      final inputPtr = ffi.audioGetCurrentInputDevice();
      if (inputPtr.address != 0) {
        _currentInputDevice = inputPtr.toDartString();
        _selectedInputDevice = _currentInputDevice;
      }

      // Get current sample rate and buffer size
      _currentSampleRate = ffi.audioGetCurrentSampleRate();
      _currentBufferSize = ffi.audioGetCurrentBufferSize();

      _selectedSampleRate = _currentSampleRate;
      _selectedBufferSize = _currentBufferSize;

      setState(() {});
    } catch (e) { /* ignored */ }
  }

  /// Calculate latency in milliseconds
  double get _calculatedLatencyMs {
    return (_selectedBufferSize / _selectedSampleRate) * 1000.0;
  }

  /// Check if settings have changed from current
  void _checkForChanges() {
    final hasChanges = _selectedOutputDevice != _currentOutputDevice ||
        _selectedInputDevice != _currentInputDevice ||
        _selectedSampleRate != _currentSampleRate ||
        _selectedBufferSize != _currentBufferSize;

    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  /// Apply current settings to the audio engine
  void _applySettings() {
    try {
      final ffi = NativeFFI.instance;

      // Set output device if changed
      if (_selectedOutputDevice != null && _selectedOutputDevice != _currentOutputDevice) {
        final namePtr = _selectedOutputDevice!.toNativeUtf8();
        final result = ffi.audioSetOutputDevice(namePtr);
        calloc.free(namePtr);
        if (result != 1) {
          throw Exception('Failed to set output device');
        }
      }

      // Set input device if changed
      if (_selectedInputDevice != null && _selectedInputDevice != _currentInputDevice) {
        final namePtr = _selectedInputDevice!.toNativeUtf8();
        final result = ffi.audioSetInputDevice(namePtr);
        calloc.free(namePtr);
        if (result != 1) {
          throw Exception('Failed to set input device');
        }
      }

      // Set sample rate if changed
      if (_selectedSampleRate != _currentSampleRate) {
        final result = ffi.audioSetSampleRate(_selectedSampleRate);
        if (result != 1) {
          throw Exception('Failed to set sample rate');
        }
      }

      // Set buffer size if changed
      if (_selectedBufferSize != _currentBufferSize) {
        final result = ffi.audioSetBufferSize(_selectedBufferSize);
        if (result != 1) {
          throw Exception('Failed to set buffer size');
        }
      }

      // Update current settings
      _currentOutputDevice = _selectedOutputDevice;
      _currentInputDevice = _selectedInputDevice;
      _currentSampleRate = _selectedSampleRate;
      _currentBufferSize = _selectedBufferSize;

      setState(() {
        _hasChanges = false;
        _errorMessage = null;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Text('Audio settings applied'),
              ],
            ),
            backgroundColor: LowerZoneColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      widget.onSettingsApplied?.call();
    } catch (e) {
      setState(() => _errorMessage = e.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to apply settings: $e')),
              ],
            ),
            backgroundColor: LowerZoneColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Revert to current engine settings
  void _revertSettings() {
    setState(() {
      _selectedOutputDevice = _currentOutputDevice;
      _selectedInputDevice = _currentInputDevice;
      _selectedSampleRate = _currentSampleRate;
      _selectedBufferSize = _currentBufferSize;
      _hasChanges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_errorMessage != null && _outputDevices.isEmpty) {
      return buildEmptyState(
        icon: Icons.error_outline,
        title: 'Audio Error',
        subtitle: _errorMessage,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // Output Device Section
          _buildDeviceSection(
            title: 'OUTPUT DEVICE',
            icon: Icons.speaker,
            devices: _outputDevices,
            selectedDevice: _selectedOutputDevice,
            onDeviceChanged: (device) {
              setState(() => _selectedOutputDevice = device);
              _checkForChanges();
            },
          ),
          const SizedBox(height: 16),

          // Input Device Section
          _buildDeviceSection(
            title: 'INPUT DEVICE',
            icon: Icons.mic,
            devices: _inputDevices,
            selectedDevice: _selectedInputDevice,
            onDeviceChanged: (device) {
              setState(() => _selectedInputDevice = device);
              _checkForChanges();
            },
          ),
          const SizedBox(height: 16),

          // Sample Rate Section
          _buildSampleRateSection(),
          const SizedBox(height: 16),

          // Buffer Size Section
          _buildBufferSizeSection(),
          const SizedBox(height: 16),

          // Latency Display
          _buildLatencyDisplay(),
          const SizedBox(height: 20),

          // Action Buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        buildSectionHeader('AUDIO SETTINGS', Icons.settings_input_component),
        const Spacer(),
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh, size: 16),
          onPressed: _loadDevices,
          tooltip: 'Refresh Devices',
          style: IconButton.styleFrom(
            foregroundColor: LowerZoneColors.textMuted,
            padding: const EdgeInsets.all(4),
            minimumSize: const Size(24, 24),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceSection({
    required String title,
    required IconData icon,
    required List<AudioDeviceInfo> devices,
    required String? selectedDevice,
    required ValueChanged<String?> onDeviceChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LowerZoneColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${devices.length} device${devices.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 9,
                  color: LowerZoneColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (devices.isEmpty)
            const Text(
              'No devices found',
              style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
            )
          else
            DropdownButtonFormField<String>(
              value: selectedDevice,
              decoration: InputDecoration(
                filled: true,
                fillColor: LowerZoneColors.bgDeep,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              dropdownColor: LowerZoneColors.bgDeep,
              style: const TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary),
              items: devices.map((device) {
                return DropdownMenuItem<String>(
                  value: device.name,
                  child: Row(
                    children: [
                      if (device.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: LowerZoneColors.success.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: LowerZoneColors.success,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          device.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${device.channelCount}ch',
                        style: const TextStyle(
                          fontSize: 9,
                          color: LowerZoneColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onDeviceChanged,
            ),
        ],
      ),
    );
  }

  Widget _buildSampleRateSection() {
    // Get supported sample rates from selected output device
    List<int> supportedRates = _commonSampleRates;
    if (_selectedOutputDevice != null) {
      final device = _outputDevices.firstWhere(
        (d) => d.name == _selectedOutputDevice,
        orElse: () => const AudioDeviceInfo(
          index: 0,
          name: '',
          isDefault: false,
          channelCount: 0,
        ),
      );
      if (device.supportedSampleRates.isNotEmpty) {
        supportedRates = device.supportedSampleRates;
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LowerZoneColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text(
                'SAMPLE RATE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                _formatSampleRate(_selectedSampleRate),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: supportedRates.map((rate) {
              final isSelected = rate == _selectedSampleRate;
              return _buildOptionChip(
                label: _formatSampleRate(rate),
                isSelected: isSelected,
                onTap: () {
                  setState(() => _selectedSampleRate = rate);
                  _checkForChanges();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBufferSizeSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LowerZoneColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text(
                'BUFFER SIZE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '$_selectedBufferSize samples',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _bufferSizes.map((size) {
              final isSelected = size == _selectedBufferSize;
              return _buildOptionChip(
                label: '$size',
                isSelected: isSelected,
                onTap: () {
                  setState(() => _selectedBufferSize = size);
                  _checkForChanges();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Buffer size guidance
          Row(
            children: [
              _buildBufferGuidance('Low Latency', '32-128', Colors.orange),
              const SizedBox(width: 12),
              _buildBufferGuidance('Balanced', '256-512', Colors.green),
              const SizedBox(width: 12),
              _buildBufferGuidance('Stable', '1024+', Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBufferGuidance(String label, String range, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color, width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label ($range)',
          style: const TextStyle(
            fontSize: 8,
            color: LowerZoneColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildLatencyDisplay() {
    final latency = _calculatedLatencyMs;
    final roundTripLatency = latency * 2;

    // Determine latency quality
    Color latencyColor;
    String latencyLabel;
    if (latency < 5) {
      latencyColor = Colors.green;
      latencyLabel = 'Excellent';
    } else if (latency < 10) {
      latencyColor = Colors.lightGreen;
      latencyLabel = 'Good';
    } else if (latency < 20) {
      latencyColor = Colors.orange;
      latencyLabel = 'Moderate';
    } else {
      latencyColor = Colors.red;
      latencyLabel = 'High';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: latencyColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.timer, size: 24, color: latencyColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${latency.toStringAsFixed(2)} ms',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: latencyColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: latencyColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        latencyLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: latencyColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Buffer Latency (Round-trip: ${roundTripLatency.toStringAsFixed(2)} ms)',
                  style: const TextStyle(
                    fontSize: 9,
                    color: LowerZoneColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Revert button
        if (_hasChanges)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _revertSettings,
              icon: const Icon(Icons.undo, size: 14),
              label: const Text('Revert'),
              style: OutlinedButton.styleFrom(
                foregroundColor: LowerZoneColors.textMuted,
                side: const BorderSide(color: LowerZoneColors.border),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        if (_hasChanges) const SizedBox(width: 12),
        // Apply button
        Expanded(
          flex: _hasChanges ? 2 : 1,
          child: ElevatedButton.icon(
            onPressed: _hasChanges ? _applySettings : null,
            icon: const Icon(Icons.check, size: 14),
            label: Text(_hasChanges ? 'Apply Changes' : 'No Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasChanges
                  ? LowerZoneColors.dawAccent
                  : LowerZoneColors.bgDeep,
              foregroundColor: _hasChanges
                  ? Colors.white
                  : LowerZoneColors.textMuted,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
              : LowerZoneColors.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? LowerZoneColors.dawAccent
                : LowerZoneColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? LowerZoneColors.dawAccent
                : LowerZoneColors.textPrimary,
          ),
        ),
      ),
    );
  }

  String _formatSampleRate(int rate) {
    if (rate >= 1000) {
      final kHz = rate / 1000;
      if (kHz == kHz.truncateToDouble()) {
        return '${kHz.toInt()} kHz';
      }
      return '${kHz.toStringAsFixed(1)} kHz';
    }
    return '$rate Hz';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT AUDIO SETTINGS BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact badge showing current audio settings (sample rate + buffer)
class AudioSettingsBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const AudioSettingsBadge({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final ffi = NativeFFI.instance;
      final sampleRate = ffi.audioGetCurrentSampleRate();
      final bufferSize = ffi.audioGetCurrentBufferSize();
      final latencyMs = ffi.audioGetLatencyMs();

      return Tooltip(
        message: 'Audio Settings\nSample Rate: $sampleRate Hz\nBuffer: $bufferSize samples\nLatency: ${latencyMs.toStringAsFixed(2)} ms',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_input_component, size: 12, color: LowerZoneColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${(sampleRate / 1000).toStringAsFixed(1)}k',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 1,
                  height: 10,
                  color: LowerZoneColors.border,
                ),
                const SizedBox(width: 4),
                Text(
                  '$bufferSize',
                  style: const TextStyle(
                    fontSize: 9,
                    color: LowerZoneColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }
}
