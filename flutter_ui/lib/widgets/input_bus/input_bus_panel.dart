/// Input Bus Panel
///
/// Displays all input buses with:
/// - Bus name and channel count
/// - Enable/disable toggle
/// - Peak meters (L/R)
/// - Create/delete controls

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/input_bus_provider.dart';
import '../../theme/reelforge_theme.dart';

class InputBusPanel extends StatefulWidget {
  const InputBusPanel({super.key});

  @override
  State<InputBusPanel> createState() => _InputBusPanelState();
}

class _InputBusPanelState extends State<InputBusPanel> {
  @override
  void initState() {
    super.initState();
    // Update meters at 30fps
    Future.doWhile(() async {
      if (!mounted) return false;
      await Future.delayed(const Duration(milliseconds: 33));
      if (mounted) {
        context.read<InputBusProvider>().updateMeters();
      }
      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InputBusProvider>(
      builder: (context, provider, _) {
        return Container(
          color: ReelForgeTheme.bgDeep,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgMid,
                  border: Border(
                    bottom: BorderSide(color: ReelForgeTheme.bgSurface, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      'INPUT BUSES',
                      style: TextStyle(
                        color: ReelForgeTheme.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      color: ReelForgeTheme.accentBlue,
                      tooltip: 'Create Input Bus',
                      onPressed: () => _showCreateBusDialog(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      color: ReelForgeTheme.textSecondary,
                      tooltip: 'Refresh',
                      onPressed: () => provider.refresh(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                  ],
                ),
              ),

              // Bus list
              Expanded(
                child: provider.buses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.input,
                              size: 48,
                              color: ReelForgeTheme.textSecondary.withOpacity(0.3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No input buses',
                              style: TextStyle(
                                color: ReelForgeTheme.textSecondary.withOpacity(0.6),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _showCreateBusDialog(context),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Create Bus'),
                              style: TextButton.styleFrom(
                                foregroundColor: ReelForgeTheme.accentBlue,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: provider.buses.length,
                        itemBuilder: (context, index) {
                          final bus = provider.buses[index];
                          return _InputBusItem(
                            bus: bus,
                            onDelete: () => provider.deleteBus(bus.id),
                            onToggleEnabled: (enabled) =>
                                provider.setBusEnabled(bus.id, enabled),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateBusDialog(BuildContext context) async {
    String name = 'Input ${context.read<InputBusProvider>().busCount + 1}';
    bool isStereo = true;
    int hwChannel = 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: ReelForgeTheme.bgMid,
          title: const Text(
            'Create Input Bus',
            style: TextStyle(color: ReelForgeTheme.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name field
              TextField(
                controller: TextEditingController(text: name),
                decoration: const InputDecoration(
                  labelText: 'Bus Name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => name = value,
              ),
              const SizedBox(height: 16),

              // Stereo/Mono toggle
              Row(
                children: [
                  const Text(
                    'Channels:',
                    style: TextStyle(color: ReelForgeTheme.textSecondary),
                  ),
                  const SizedBox(width: 16),
                  ChoiceChip(
                    label: const Text('Stereo'),
                    selected: isStereo,
                    onSelected: (selected) {
                      setState(() => isStereo = true);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Mono'),
                    selected: !isStereo,
                    onSelected: (selected) {
                      setState(() => isStereo = false);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Hardware channel (for mono)
              if (!isStereo)
                DropdownButtonFormField<int>(
                  value: hwChannel,
                  decoration: const InputDecoration(
                    labelText: 'Hardware Input',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(
                    16,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text('Input ${i + 1}'),
                    ),
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => hwChannel = value);
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ReelForgeTheme.accentBlue,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result == true && context.mounted) {
      final provider = context.read<InputBusProvider>();
      if (isStereo) {
        await provider.createStereoBus(name);
      } else {
        await provider.createMonoBus(name, hwChannel);
      }
    }
  }
}

class _InputBusItem extends StatelessWidget {
  final InputBusInfo bus;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  const _InputBusItem({
    required this.bus,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: bus.enabled
              ? ReelForgeTheme.accentBlue.withOpacity(0.3)
              : ReelForgeTheme.bgSurface,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Enable toggle
              Switch(
                value: bus.enabled,
                onChanged: onToggleEnabled,
                activeColor: ReelForgeTheme.accentGreen,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),

              // Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bus.name,
                      style: const TextStyle(
                        color: ReelForgeTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      bus.channels == 1 ? 'Mono' : 'Stereo',
                      style: TextStyle(
                        color: ReelForgeTheme.textSecondary.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                color: ReelForgeTheme.accentRed.withOpacity(0.7),
                tooltip: 'Delete Bus',
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Peak meters
          if (bus.enabled) ...[
            _PeakMeter(label: 'L', peak: bus.peakL),
            const SizedBox(height: 4),
            if (bus.channels > 1) _PeakMeter(label: 'R', peak: bus.peakR),
          ],
        ],
      ),
    );
  }
}

class _PeakMeter extends StatelessWidget {
  final String label;
  final double peak;

  const _PeakMeter({
    required this.label,
    required this.peak,
  });

  @override
  Widget build(BuildContext context) {
    final peakDb = peak > 0 ? 20 * math.log(peak.clamp(1e-10, 1.0)) / math.ln10 : -100.0;
    final normalizedPeak = ((peakDb + 60) / 60).clamp(0.0, 1.0);

    Color meterColor;
    if (peakDb > -0.5) {
      meterColor = ReelForgeTheme.accentRed;
    } else if (peakDb > -6) {
      meterColor = ReelForgeTheme.accentOrange;
    } else if (peakDb > -18) {
      meterColor = ReelForgeTheme.accentGreen;
    } else {
      meterColor = ReelForgeTheme.accentCyan;
    }

    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: TextStyle(
              color: ReelForgeTheme.textSecondary.withOpacity(0.7),
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: normalizedPeak,
              child: Container(
                decoration: BoxDecoration(
                  color: meterColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            peakDb > -100 ? '${peakDb.toStringAsFixed(1)} dB' : '-∞',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary.withOpacity(0.7),
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
