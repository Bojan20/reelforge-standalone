/// Channel Panel Widget
///
/// Cubase/Pro Tools style channel strip panel:
/// - Channel header with name and type
/// - I/O routing section
/// - Insert slots (8)
/// - EQ enable/disable
/// - Volume/Pan controls
/// - Mute/Solo buttons

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../models/layout_models.dart';

// ════════════════════════════════════════════════════════════════════════════
// WIDGET
// ════════════════════════════════════════════════════════════════════════════

class ChannelPanel extends StatelessWidget {
  final ChannelStripData channel;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId, double pan)? onPanChange;
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final void Function(String channelId, int slotIndex)? onInsertClick;
  final void Function(String channelId, int sendIndex, double level)? onSendLevelChange;
  final void Function(String channelId)? onEQToggle;
  final void Function(String channelId)? onOutputClick;

  const ChannelPanel({
    super.key,
    required this.channel,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onInsertClick,
    this.onSendLevelChange,
    this.onEQToggle,
    this.onOutputClick,
  });

  static const _typeIcons = {
    'audio': '🎵',
    'instrument': '🎹',
    'bus': '🔈',
    'fx': '🎛️',
    'master': '🔊',
  };

  String _formatDb(double db) {
    if (db <= -60) return '-∞';
    return db >= 0 ? '+${db.toStringAsFixed(1)}' : db.toStringAsFixed(1);
  }

  String _formatPan(double v) {
    if (v == 0) return 'C';
    return v < 0 ? 'L${v.abs().round()}' : 'R${v.round()}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildIOSection(),
        _buildInsertsSection(),
        _buildEQSection(),
        _buildMixSection(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: channel.color, width: 3),
        ),
      ),
      child: Row(
        children: [
          Text(
            _typeIcons[channel.type] ?? '🎵',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                Text(
                  channel.type.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIOSection() {
    return _Section(
      title: 'I/O',
      children: [
        _IORow(label: 'In', value: channel.input),
        _IORow(
          label: 'Out',
          value: channel.output,
          onTap: () => onOutputClick?.call(channel.id),
        ),
      ],
    );
  }

  Widget _buildInsertsSection() {
    final usedCount = channel.inserts.where((i) => !i.isEmpty).length;
    return _Section(
      title: 'Inserts ($usedCount/8)',
      children: [
        ...channel.inserts.take(8).toList().asMap().entries.map((entry) {
          return _InsertSlot(
            index: entry.key,
            insert: entry.value,
            onTap: () => onInsertClick?.call(channel.id, entry.key),
          );
        }),
      ],
    );
  }

  Widget _buildEQSection() {
    return _Section(
      title: 'Equalizer',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'EQ Enabled',
              style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary),
            ),
            _ToggleButton(
              label: channel.eqEnabled ? 'ON' : 'OFF',
              active: channel.eqEnabled,
              activeColor: FluxForgeTheme.accentGreen,
              onTap: () => onEQToggle?.call(channel.id),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMixSection() {
    return _Section(
      title: 'Mix',
      children: [
        _Slider(
          label: 'Volume',
          value: channel.volume,
          min: -60,
          max: 12,
          onChanged: (v) => onVolumeChange?.call(channel.id, v),
          formatValue: _formatDb,
        ),
        _Slider(
          label: 'Pan',
          value: channel.pan * 100,
          min: -100,
          max: 100,
          onChanged: (v) => onPanChange?.call(channel.id, v / 100),
          formatValue: (v) => _formatPan(v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'M',
                active: channel.mute,
                activeColor: FluxForgeTheme.errorRed,
                onTap: () => onMuteToggle?.call(channel.id),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                label: 'S',
                active: channel.solo,
                activeColor: FluxForgeTheme.warningOrange,
                onTap: () => onSoloToggle?.call(channel.id),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _IORow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _IORow({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 11,
                        color: FluxForgeTheme.textPrimary,
                      ),
                    ),
                    if (onTap != null)
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 14,
                        color: FluxForgeTheme.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsertSlot extends StatelessWidget {
  final int index;
  final InsertSlot insert;
  final VoidCallback? onTap;

  const _InsertSlot({required this.index, required this.insert, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasPlugin = !insert.isEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hasPlugin ? FluxForgeTheme.bgElevated : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasPlugin && !insert.bypassed
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasPlugin && !insert.bypassed
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.borderSubtle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasPlugin ? insert.name : 'Insert ${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  color: hasPlugin
                      ? (insert.bypassed
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textPrimary)
                      : FluxForgeTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final String Function(double)? formatValue;

  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final displayValue = formatValue?.call(value) ?? value.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onHorizontalDragUpdate: (details) {
                  if (onChanged == null) return;
                  final width = constraints.maxWidth;
                  final delta = details.delta.dx / width;
                  final newValue = (value + delta * (max - min)).clamp(min, max);
                  onChanged!(newValue);
                },
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeepest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: percentage,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              displayValue,
              style: FluxForgeTheme.monoSmall.copyWith(fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ToggleButton({
    required this.label,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.2) : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: active ? activeColor : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.2) : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? activeColor : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ════════════════════════════════════════════════════════════════════════════

class ChannelPanelEmpty extends StatelessWidget {
  const ChannelPanelEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎚️', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            'Select a track to view channel',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
