/// Routing Panel
///
/// Displays:
/// - Channel list (audio, bus, aux, VCA)
/// - Output routing configuration
/// - Send/return matrix
/// - Channel properties
/// - Real-time routing graph visualization

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/routing_provider.dart';
import '../../theme/fluxforge_theme.dart';

class RoutingPanel extends StatefulWidget {
  const RoutingPanel({super.key});

  @override
  State<RoutingPanel> createState() => _RoutingPanelState();
}

class _RoutingPanelState extends State<RoutingPanel> {
  Timer? _refreshTimer;
  int? _selectedChannelId;

  @override
  void initState() {
    super.initState();
    // Refresh at 10 Hz
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        context.read<RoutingProvider>().refresh();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoutingProvider>(
      builder: (context, routing, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Row(
            children: [
              // Left: Channel list
              SizedBox(
                width: 300,
                child: _buildChannelList(routing),
              ),

              // Divider
              Container(
                width: 1,
                color: FluxForgeTheme.bgSurface,
              ),

              // Right: Selected channel details
              Expanded(
                child: _selectedChannelId != null
                    ? _buildChannelDetails(routing, _selectedChannelId!)
                    : _buildEmptyState(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelList(RoutingProvider routing) {
    return Column(
      children: [
        // Header with create button
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border(
              bottom: BorderSide(color: FluxForgeTheme.bgSurface, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                'ROUTING CHANNELS',
                style: FluxForgeTheme.dockSans(
                  size: 11,
                  weight: FontWeight.w600,
                  color: FluxForgeTheme.textPrimary,
                ).copyWith(letterSpacing: 1.2),
              ),
              const Spacer(),
              Text(
                '${routing.channelCount} channels',
                style: FluxForgeTheme.dockSans(
                  size: 10,
                  color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                color: FluxForgeTheme.accentBlue,
                tooltip: 'Create Channel',
                onPressed: () => _showCreateChannelDialog(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),

        // Channel list
        Expanded(
          child: routing.channelCount > 0
              ? ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: routing.channels.length,
                  itemBuilder: (context, index) {
                    final channel = routing.channels[index];
                    return _ChannelListItem(
                      channel: channel,
                      isSelected: _selectedChannelId == channel.id,
                      onTap: () {
                        setState(() {
                          _selectedChannelId = channel.id;
                        });
                      },
                      onDelete: () async {
                        final success = await routing.deleteChannel(channel.id);
                        if (success && _selectedChannelId == channel.id) {
                          setState(() {
                            _selectedChannelId = null;
                          });
                        }
                      },
                    );
                  },
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.device_hub,
                        size: 64,
                        color: FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Routing Channels',
                        style: FluxForgeTheme.dockSans(
                          size: 14,
                          weight: FontWeight.w500,
                          color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Click + to create a channel',
                        style: FluxForgeTheme.dockSans(
                          size: 12,
                          color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildChannelDetails(RoutingProvider routing, int channelId) {
    final channel = routing.getChannel(channelId);
    if (channel == null) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel header
          Row(
            children: [
              _getChannelIcon(channel.kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: FluxForgeTheme.dockSans(
                        size: 18,
                        weight: FontWeight.w600,
                        color: FluxForgeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Channel ${channel.id} · ${_getChannelTypeName(channel.kind)}',
                      style: FluxForgeTheme.dockSans(
                        size: 12,
                        color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Output routing section
          _buildSection(
            title: 'OUTPUT ROUTING',
            child: _buildOutputRoutingControls(routing, channelId),
          ),

          const SizedBox(height: 24),

          // Sends section
          _buildSection(
            title: 'SENDS',
            child: _buildSendsControls(routing, channelId),
          ),

          const SizedBox(height: 24),

          // Channel properties section
          _buildSection(
            title: 'CHANNEL PROPERTIES',
            child: _buildChannelPropertiesControls(routing, channelId),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: FluxForgeTheme.dockSans(
            size: 11,
            weight: FontWeight.w600,
            color: FluxForgeTheme.textPrimary,
          ).copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.bgSurface),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildOutputRoutingControls(RoutingProvider routing, int channelId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Master output button
        ElevatedButton.icon(
          onPressed: () => routing.setOutputToMaster(channelId),
          icon: const Icon(Icons.volume_up, size: 16),
          label: const Text('Route to Master'),
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.bgSurface,
            foregroundColor: FluxForgeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // Channel output selector
        ElevatedButton.icon(
          onPressed: () => _showChannelOutputDialog(routing, channelId),
          icon: const Icon(Icons.device_hub, size: 16),
          label: const Text('Route to Channel'),
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.bgSurface,
            foregroundColor: FluxForgeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // Disable output button
        ElevatedButton.icon(
          onPressed: () => routing.disableOutput(channelId),
          icon: const Icon(Icons.block, size: 16),
          label: const Text('Disable Output'),
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.bgSurface,
            foregroundColor: FluxForgeTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSendsControls(RoutingProvider routing, int channelId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: () => _showAddSendDialog(routing, channelId),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Send'),
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentBlue,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No sends configured',
          style: FluxForgeTheme.dockSans(
            size: 12,
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelPropertiesControls(RoutingProvider routing, int channelId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mute button
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => routing.setMute(channelId, true),
                icon: const Icon(Icons.volume_off, size: 16),
                label: const Text('Mute'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.bgSurface,
                  foregroundColor: FluxForgeTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => routing.setSolo(channelId, true),
                icon: const Icon(Icons.headset, size: 16),
                label: const Text('Solo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.bgSurface,
                  foregroundColor: FluxForgeTheme.accentOrange,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.device_hub,
            size: 64,
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Channel Selected',
            style: FluxForgeTheme.dockSans(
              size: 14,
              weight: FontWeight.w500,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a channel from the list',
            style: FluxForgeTheme.dockSans(
              size: 12,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateChannelDialog(),
    );
  }

  void _showChannelOutputDialog(RoutingProvider routing, int channelId) {
    showDialog(
      context: context,
      builder: (context) => _ChannelOutputDialog(
        routing: routing,
        sourceChannelId: channelId,
      ),
    );
  }

  void _showAddSendDialog(RoutingProvider routing, int fromChannelId) {
    showDialog(
      context: context,
      builder: (context) => _AddSendDialog(
        routing: routing,
        fromChannelId: fromChannelId,
      ),
    );
  }

  Icon _getChannelIcon(ChannelKind kind) {
    switch (kind) {
      case ChannelKind.audio:
        return const Icon(Icons.audiotrack, color: FluxForgeTheme.accentBlue, size: 32);
      case ChannelKind.bus:
        return const Icon(Icons.storage, color: FluxForgeTheme.accentGreen, size: 32);
      case ChannelKind.aux:
        return const Icon(Icons.send, color: FluxForgeTheme.accentOrange, size: 32);
      case ChannelKind.vca:
        return const Icon(Icons.tune, color: FluxForgeTheme.accentPurple, size: 32);
      case ChannelKind.master:
        return const Icon(Icons.speaker, color: FluxForgeTheme.accentRed, size: 32);
    }
  }

  String _getChannelTypeName(ChannelKind kind) {
    switch (kind) {
      case ChannelKind.audio:
        return 'Audio Track';
      case ChannelKind.bus:
        return 'Bus';
      case ChannelKind.aux:
        return 'Aux/FX';
      case ChannelKind.vca:
        return 'VCA';
      case ChannelKind.master:
        return 'Master';
    }
  }
}

class _ChannelListItem extends StatelessWidget {
  final ChannelInfo channel;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChannelListItem({
    required this.channel,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? FluxForgeTheme.bgSurface : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
              : FluxForgeTheme.bgSurface,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: _getChannelIcon(channel.kind),
        title: Text(
          channel.name,
          style: FluxForgeTheme.dockSans(
            size: 13,
            weight: FontWeight.w500,
            color: FluxForgeTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          'ID: ${channel.id}',
          style: FluxForgeTheme.dockMono(
            size: 11,
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
          ),
        ),
        trailing: channel.kind != ChannelKind.master
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: FluxForgeTheme.accentRed,
                tooltip: 'Delete Channel',
                onPressed: onDelete,
              )
            : null,
      ),
    );
  }

  Icon _getChannelIcon(ChannelKind kind) {
    switch (kind) {
      case ChannelKind.audio:
        return const Icon(Icons.audiotrack, color: FluxForgeTheme.accentBlue, size: 20);
      case ChannelKind.bus:
        return const Icon(Icons.storage, color: FluxForgeTheme.accentGreen, size: 20);
      case ChannelKind.aux:
        return const Icon(Icons.send, color: FluxForgeTheme.accentOrange, size: 20);
      case ChannelKind.vca:
        return const Icon(Icons.tune, color: FluxForgeTheme.accentPurple, size: 20);
      case ChannelKind.master:
        return const Icon(Icons.speaker, color: FluxForgeTheme.accentRed, size: 20);
    }
  }
}

class _CreateChannelDialog extends StatefulWidget {
  @override
  State<_CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<_CreateChannelDialog> {
  ChannelKind _selectedKind = ChannelKind.audio;
  final _nameController = TextEditingController(text: 'New Channel');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routing = context.read<RoutingProvider>();

    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgMid,
      title: Text('Create Channel',
          style: FluxForgeTheme.dockSans(
              size: 16,
              weight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Channel Type:',
                style: FluxForgeTheme.dockSans(
                    size: 13, color: FluxForgeTheme.textSecondary)),
            const SizedBox(height: 8),
            DropdownButton<ChannelKind>(
              value: _selectedKind,
              isExpanded: true,
              dropdownColor: FluxForgeTheme.bgDeep,
              style: FluxForgeTheme.dockSans(
                  size: 13, color: FluxForgeTheme.textPrimary),
              items: [
                ChannelKind.audio,
                ChannelKind.bus,
                ChannelKind.aux,
                ChannelKind.vca,
              ].map((kind) {
                return DropdownMenuItem(
                  value: kind,
                  child: Text(_getChannelTypeName(kind)),
                );
              }).toList(),
              onChanged: (kind) {
                if (kind != null) {
                  setState(() => _selectedKind = kind);
                }
              },
            ),
            const SizedBox(height: 16),
            Text('Channel Name:',
                style: FluxForgeTheme.dockSans(
                    size: 13, color: FluxForgeTheme.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: FluxForgeTheme.dockSans(
                  size: 13, color: FluxForgeTheme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: FluxForgeTheme.bgDeep,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: FluxForgeTheme.bgSurface),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final callbackId = await routing.createChannel(_selectedKind, _nameController.text);
            if (callbackId > 0 && context.mounted) {
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }

  String _getChannelTypeName(ChannelKind kind) {
    switch (kind) {
      case ChannelKind.audio:
        return 'Audio Track';
      case ChannelKind.bus:
        return 'Bus';
      case ChannelKind.aux:
        return 'Aux/FX';
      case ChannelKind.vca:
        return 'VCA';
      case ChannelKind.master:
        return 'Master';
    }
  }
}

class _ChannelOutputDialog extends StatelessWidget {
  final RoutingProvider routing;
  final int sourceChannelId;

  const _ChannelOutputDialog({
    required this.routing,
    required this.sourceChannelId,
  });

  @override
  Widget build(BuildContext context) {
    final channels = routing.channels.where((ch) => ch.id != sourceChannelId).toList();

    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgMid,
      title: Text('Route to Channel',
          style: FluxForgeTheme.dockSans(
              size: 16,
              weight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary)),
      content: SizedBox(
        width: 300,
        height: 400,
        child: ListView.builder(
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final channel = channels[index];
            return ListTile(
              title: Text(
                channel.name,
                style: FluxForgeTheme.dockSans(
                    size: 13, color: FluxForgeTheme.textPrimary),
              ),
              subtitle: Text(
                'ID: ${channel.id}',
                style: FluxForgeTheme.dockMono(
                    size: 11,
                    color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6)),
              ),
              onTap: () async {
                await routing.setOutputToChannel(sourceChannelId, channel.id);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _AddSendDialog extends StatefulWidget {
  final RoutingProvider routing;
  final int fromChannelId;

  const _AddSendDialog({
    required this.routing,
    required this.fromChannelId,
  });

  @override
  State<_AddSendDialog> createState() => _AddSendDialogState();
}

class _AddSendDialogState extends State<_AddSendDialog> {
  bool _preFader = false;

  @override
  Widget build(BuildContext context) {
    final channels = widget.routing.channels
        .where((ch) => ch.id != widget.fromChannelId)
        .toList();

    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgMid,
      title: Text('Add Send',
          style: FluxForgeTheme.dockSans(
              size: 16,
              weight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: Text('Pre-Fader',
                  style: FluxForgeTheme.dockSans(
                      size: 13, color: FluxForgeTheme.textPrimary)),
              subtitle: Text(
                _preFader
                    ? 'Send before fader (independent)'
                    : 'Send after fader (follows volume)',
                style: FluxForgeTheme.dockSans(
                    size: 11,
                    color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6)),
              ),
              value: _preFader,
              onChanged: (value) {
                setState(() => _preFader = value ?? false);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Send to:',
              style: FluxForgeTheme.dockSans(
                  size: 13, color: FluxForgeTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return ListTile(
                    title: Text(
                      channel.name,
                      style: FluxForgeTheme.dockSans(
                          size: 13, color: FluxForgeTheme.textPrimary),
                    ),
                    subtitle: Text(
                      'ID: ${channel.id}',
                      style: FluxForgeTheme.dockMono(
                          size: 11,
                          color: FluxForgeTheme.textSecondary
                              .withValues(alpha: 0.6)),
                    ),
                    onTap: () async {
                      await widget.routing.addSend(
                        fromChannel: widget.fromChannelId,
                        toChannel: channel.id,
                        preFader: _preFader,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
