/// Group Manager Panel (P10.1.20)
///
/// Visual editor for track groups with folder-style organization.
/// Enables drag-drop track grouping and linked parameter control.
///
/// Features:
/// - Visual group list with color badges
/// - Drag tracks into groups
/// - Group collapse/expand
/// - Link parameter toggles
/// - Color picker per group

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/mixer_provider.dart';

/// Preset group colors
const _groupColorPresets = [
  Color(0xFF40FF90), // Green
  Color(0xFF4A9EFF), // Blue
  Color(0xFFFF9040), // Orange
  Color(0xFFFF6B6B), // Red
  Color(0xFF9B59B6), // Purple
  Color(0xFF40C8FF), // Cyan
  Color(0xFFFFD93D), // Yellow
  Color(0xFFE91E63), // Pink
  Color(0xFF00BCD4), // Teal
  Color(0xFF8BC34A), // Light Green
  Color(0xFFFF5722), // Deep Orange
  Color(0xFF607D8B), // Blue Grey
];

/// Panel for managing track groups
class GroupManagerPanel extends StatefulWidget {
  final String? selectedGroupId;
  final ValueChanged<String?>? onGroupSelected;
  final bool compact;

  const GroupManagerPanel({
    super.key,
    this.selectedGroupId,
    this.onGroupSelected,
    this.compact = false,
  });

  @override
  State<GroupManagerPanel> createState() => _GroupManagerPanelState();
}

class _GroupManagerPanelState extends State<GroupManagerPanel> {
  String? _selectedGroupId;
  final Map<String, bool> _expandedGroups = {};
  final TextEditingController _newGroupNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.selectedGroupId;
  }

  @override
  void dispose() {
    _newGroupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerProvider>(
      builder: (context, mixer, _) {
        final groups = mixer.groups;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2A2A30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(context, mixer),
              const Divider(height: 1, color: Color(0xFF2A2A30)),

              // Group list
              Expanded(
                child: groups.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: groups.length,
                        itemBuilder: (context, index) =>
                            _buildGroupItem(context, mixer, groups[index]),
                      ),
              ),

              // Ungrouped tracks section
              if (!widget.compact) ...[
                const Divider(height: 1, color: Color(0xFF2A2A30)),
                _buildUngroupedSection(context, mixer),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, MixerProvider mixer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: Color(0xFF4A9EFF), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Track Groups',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Add group button
          IconButton(
            onPressed: () => _showCreateGroupDialog(context, mixer),
            icon: const Icon(Icons.add, size: 18),
            color: const Color(0xFF4A9EFF),
            tooltip: 'Create Group',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 48,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 12),
            Text(
              'No Groups',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Create a group to organize tracks',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupItem(
      BuildContext context, MixerProvider mixer, MixerGroup group) {
    final isSelected = _selectedGroupId == group.id;
    final isExpanded = _expandedGroups[group.id] ?? true;
    final memberChannels = mixer.getGroupMembers(group.id);

    return DragTarget<MixerChannel>(
      onAcceptWithDetails: (details) {
        final channel = details.data;
        if (channel.groupId != group.id) {
          mixer.addChannelToGroup(channel.id, group.id);
        }
      },
      onWillAcceptWithDetails: (details) => details.data.groupId != group.id,
      builder: (context, candidateData, rejectedData) {
        final isDragTarget = candidateData.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isDragTarget
                ? group.color.withOpacity(0.2)
                : isSelected
                    ? const Color(0xFF2A2A35)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isDragTarget
                ? Border.all(color: group.color, width: 2)
                : isSelected
                    ? Border.all(color: const Color(0xFF4A9EFF), width: 1)
                    : null,
          ),
          child: Column(
            children: [
              // Group header
              InkWell(
                onTap: () {
                  setState(() => _selectedGroupId = group.id);
                  widget.onGroupSelected?.call(group.id);
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      // Expand/collapse button
                      InkWell(
                        onTap: () => setState(
                            () => _expandedGroups[group.id] = !isExpanded),
                        borderRadius: BorderRadius.circular(4),
                        child: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Color badge
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: group.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Group name
                      Expanded(
                        child: Text(
                          group.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Member count
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${memberChannels.length}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Color picker button
                      _buildColorPickerButton(context, mixer, group),

                      // Delete button
                      IconButton(
                        onPressed: () =>
                            _confirmDeleteGroup(context, mixer, group),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        color: Colors.grey[500],
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Delete Group',
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded content
              if (isExpanded) ...[
                // Link toggles
                _buildLinkToggles(mixer, group),

                // Member channels
                if (memberChannels.isNotEmpty)
                  ...memberChannels.map(
                    (channel) => _buildMemberItem(context, mixer, group, channel),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLinkToggles(MixerProvider mixer, MixerGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 8, 4),
      child: Row(
        children: [
          _buildLinkToggle(
            'Vol',
            group.linkVolume,
            () =>
                mixer.toggleGroupLink(group.id, GroupLinkParameter.volume),
          ),
          const SizedBox(width: 4),
          _buildLinkToggle(
            'Pan',
            group.linkPan,
            () => mixer.toggleGroupLink(group.id, GroupLinkParameter.pan),
          ),
          const SizedBox(width: 4),
          _buildLinkToggle(
            'M',
            group.linkMute,
            () => mixer.toggleGroupLink(group.id, GroupLinkParameter.mute),
          ),
          const SizedBox(width: 4),
          _buildLinkToggle(
            'S',
            group.linkSolo,
            () => mixer.toggleGroupLink(group.id, GroupLinkParameter.solo),
          ),
          const Spacer(),
          // Link mode toggle
          InkWell(
            onTap: () => mixer.setGroupLinkMode(
              group.id,
              group.linkMode == GroupLinkMode.relative
                  ? GroupLinkMode.absolute
                  : GroupLinkMode.relative,
            ),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                group.linkMode == GroupLinkMode.relative ? 'REL' : 'ABS',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkToggle(String label, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF4A9EFF) : const Color(0xFF2A2A30),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.grey[500],
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMemberItem(BuildContext context, MixerProvider mixer,
      MixerGroup group, MixerChannel channel) {
    return Draggable<MixerChannel>(
      data: channel,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A35),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            channel.name,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(32, 2, 8, 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF222228),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: channel.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                channel.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Remove from group
            InkWell(
              onTap: () => mixer.removeChannelFromGroup(channel.id, group.id),
              borderRadius: BorderRadius.circular(4),
              child: Icon(Icons.close, size: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPickerButton(
      BuildContext context, MixerProvider mixer, MixerGroup group) {
    return PopupMenuButton<Color>(
      tooltip: 'Group Color',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.palette_outlined, size: 16, color: Colors.grey[500]),
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      itemBuilder: (context) => [
        PopupMenuItem<Color>(
          enabled: false,
          child: SizedBox(
            width: 180,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _groupColorPresets.map((color) {
                final isSelected = group.color.value == color.value;
                return InkWell(
                  onTap: () {
                    mixer.setGroupColor(group.id, color);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUngroupedSection(BuildContext context, MixerProvider mixer) {
    final ungroupedChannels =
        mixer.channels.where((c) => c.groupId == null).toList();

    if (ungroupedChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Ungrouped Tracks (${ungroupedChannels.length})',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: ungroupedChannels.length,
              itemBuilder: (context, index) {
                final channel = ungroupedChannels[index];
                return Draggable<MixerChannel>(
                  data: channel,
                  feedback: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        channel.name,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222228),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: channel.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            channel.name,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.drag_indicator,
                            size: 14, color: Colors.grey[600]),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context, MixerProvider mixer) {
    _newGroupNameController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        title: const Text(
          'Create Group',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: _newGroupNameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Group name',
            hintStyle: TextStyle(color: Colors.grey[600]),
            filled: true,
            fillColor: const Color(0xFF2A2A30),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              mixer.createGroup(name: value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
          ),
          ElevatedButton(
            onPressed: () {
              final name = _newGroupNameController.text.trim();
              if (name.isNotEmpty) {
                mixer.createGroup(name: name);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteGroup(
      BuildContext context, MixerProvider mixer, MixerGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        title: const Text(
          'Delete Group',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          'Delete "${group.name}"? Tracks will be ungrouped.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
          ),
          ElevatedButton(
            onPressed: () {
              mixer.deleteGroup(group.id);
              if (_selectedGroupId == group.id) {
                setState(() => _selectedGroupId = null);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
