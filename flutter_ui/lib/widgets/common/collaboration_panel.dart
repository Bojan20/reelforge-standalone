// ============================================================================
// P3-04: Collaboration Panel — Remote Collaboration UI
// FluxForge Studio — Real-time collaboration widgets
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/collaboration_service.dart';

// ============================================================================
// COLLABORATION STATUS BADGE
// ============================================================================

/// Small badge showing collaboration status
class CollaborationStatusBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const CollaborationStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CollaborationService.instance,
      builder: (context, _) {
        final service = CollaborationService.instance;
        final status = service.status;
        final session = service.currentSession;

        Color color;
        IconData icon;

        switch (status) {
          case CollaborationStatus.disconnected:
            color = Colors.grey;
            icon = Icons.people_outline;
            break;
          case CollaborationStatus.connecting:
          case CollaborationStatus.reconnecting:
            color = Colors.orange;
            icon = Icons.sync;
            break;
          case CollaborationStatus.connected:
            color = Colors.green;
            icon = Icons.people;
            break;
          case CollaborationStatus.error:
            color = Colors.red;
            icon = Icons.error_outline;
            break;
        }

        return Tooltip(
          message: session != null
              ? '${status.displayName} • ${session.participants.length} users'
              : status.displayName,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  if (session != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${session.participants.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// COLLABORATION PANEL
// ============================================================================

/// Main collaboration panel with session management
class CollaborationPanel extends StatefulWidget {
  const CollaborationPanel({super.key});

  @override
  State<CollaborationPanel> createState() => _CollaborationPanelState();
}

class _CollaborationPanelState extends State<CollaborationPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CollaborationService.instance,
      builder: (context, _) {
        final service = CollaborationService.instance;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(service),

              // Content
              Expanded(
                child: service.isInSession
                    ? _buildSessionContent(service)
                    : _buildNoSessionContent(service),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(CollaborationService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.people,
            color: service.isConnected ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.isInSession
                      ? service.currentSession!.projectName
                      : 'Collaboration',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  service.status.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          if (service.isInSession) ...[
            IconButton(
              icon: const Icon(Icons.share, size: 18),
              onPressed: () => _showInviteDialog(context, service),
              tooltip: 'Invite',
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app, size: 18),
              onPressed: () => _confirmLeave(context, service),
              tooltip: 'Leave',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoSessionContent(CollaborationService service) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_add,
            size: 48,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'Start Collaborating',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create or join a session to collaborate in real-time',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showCreateDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Create'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _showJoinDialog(context),
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Join'),
              ),
            ],
          ),
          if (service.lastError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    service.lastError!,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionContent(CollaborationService service) {
    return Column(
      children: [
        // Tab bar
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Chat'),
            Tab(text: 'Activity'),
          ],
          labelStyle: const TextStyle(fontSize: 12),
          indicatorSize: TabBarIndicatorSize.tab,
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildUsersTab(service),
              _buildChatTab(service),
              _buildActivityTab(service),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUsersTab(CollaborationService service) {
    final participants = service.participants;

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final user = participants[index];
        final isLocal = user.id == service.localUser?.id;

        return CollaboratorTile(
          collaborator: user,
          isLocal: isLocal,
          canManage: service.localUser?.role.canManage ?? false,
          onKick: () => service.kickUser(user.id),
          onChangeRole: (role) => service.changeUserRole(user.id, role),
        );
      },
    );
  }

  Widget _buildChatTab(CollaborationService service) {
    return CollaborationChatPanel(service: service);
  }

  Widget _buildActivityTab(CollaborationService service) {
    return StreamBuilder<CollabOperation>(
      stream: service.operationStream,
      builder: (context, snapshot) {
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: 0, // Will show operations as they come in
          itemBuilder: (context, index) {
            // Activity item
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const CreateSessionDialog(),
    );
  }

  void _showJoinDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const JoinSessionDialog(),
    );
  }

  void _showInviteDialog(BuildContext context, CollaborationService service) {
    final link = service.getInviteLink();
    if (link == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Collaborators'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this link to invite others:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      link,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context, CollaborationService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Session?'),
        content: const Text('Are you sure you want to leave this collaboration session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              service.leaveSession();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// COLLABORATOR TILE
// ============================================================================

/// Tile showing a single collaborator
class CollaboratorTile extends StatelessWidget {
  final Collaborator collaborator;
  final bool isLocal;
  final bool canManage;
  final VoidCallback? onKick;
  final ValueChanged<CollabRole>? onChangeRole;

  const CollaboratorTile({
    super.key,
    required this.collaborator,
    this.isLocal = false,
    this.canManage = false,
    this.onKick,
    this.onChangeRole,
  });

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(collaborator.color);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLocal ? color.withOpacity(0.1) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: isLocal ? Border.all(color: color.withOpacity(0.3)) : null,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                collaborator.name.isNotEmpty
                    ? collaborator.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      collaborator.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    if (isLocal)
                      const Text(
                        ' (you)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _roleColor(collaborator.role).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        collaborator.role.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          color: _roleColor(collaborator.role),
                        ),
                      ),
                    ),
                    if (collaborator.currentSection != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '• ${collaborator.currentSection}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                    if (collaborator.isTyping) ...[
                      const SizedBox(width: 4),
                      const Text(
                        '• typing...',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Actions
          if (canManage && !isLocal) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'editor',
                  child: Text('Make Editor'),
                ),
                const PopupMenuItem(
                  value: 'viewer',
                  child: Text('Make Viewer'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'kick',
                  child: Text('Remove', style: TextStyle(color: Colors.red)),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'editor':
                    onChangeRole?.call(CollabRole.editor);
                    break;
                  case 'viewer':
                    onChangeRole?.call(CollabRole.viewer);
                    break;
                  case 'kick':
                    onKick?.call();
                    break;
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  Color _roleColor(CollabRole role) {
    switch (role) {
      case CollabRole.owner:
        return Colors.amber;
      case CollabRole.editor:
        return Colors.green;
      case CollabRole.viewer:
        return Colors.blue;
    }
  }
}

// ============================================================================
// CHAT PANEL
// ============================================================================

/// Chat panel for collaboration session
class CollaborationChatPanel extends StatefulWidget {
  final CollaborationService service;

  const CollaborationChatPanel({super.key, required this.service});

  @override
  State<CollaborationChatPanel> createState() => _CollaborationChatPanelState();
}

class _CollaborationChatPanelState extends State<CollaborationChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.service.chatMessages;

    return Column(
      children: [
        // Messages list
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return _buildMessage(message);
            },
          ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (_) => _handleTyping(),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, size: 18),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(CollabChatMessage message) {
    final isSystem = message.isSystem;
    final isLocal = message.senderId == widget.service.localUser?.id;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.grey[500],
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isLocal ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: BoxDecoration(
          color: isLocal ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isLocal)
              Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[400],
                ),
              ),
            Text(
              message.content,
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTyping() {
    widget.service.sendTypingIndicator(true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      widget.service.sendTypingIndicator(false);
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    widget.service.sendChatMessage(text);
    _messageController.clear();
    widget.service.sendTypingIndicator(false);

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// CREATE SESSION DIALOG
// ============================================================================

/// Dialog to create a new collaboration session
class CreateSessionDialog extends StatefulWidget {
  const CreateSessionDialog({super.key});

  @override
  State<CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<CreateSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _projectNameController = TextEditingController();
  final _userNameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _projectNameController.text = 'My Project';
    _userNameController.text = 'User';
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _userNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Collaboration Session'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _projectNameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                prefixIcon: Icon(Icons.folder),
              ),
              validator: (value) =>
                  value?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _userNameController,
              decoration: const InputDecoration(
                labelText: 'Your Name',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) =>
                  value?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createSession,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    final session = await CollaborationService.instance.createSession(
      projectId: 'project_${DateTime.now().millisecondsSinceEpoch}',
      projectName: _projectNameController.text,
      userName: _userNameController.text,
      userEmail: _emailController.text.isNotEmpty ? _emailController.text : null,
    );

    if (mounted) {
      setState(() => _isCreating = false);

      if (session != null) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              CollaborationService.instance.lastError ?? 'Failed to create session',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ============================================================================
// JOIN SESSION DIALOG
// ============================================================================

/// Dialog to join an existing collaboration session
class JoinSessionDialog extends StatefulWidget {
  const JoinSessionDialog({super.key});

  @override
  State<JoinSessionDialog> createState() => _JoinSessionDialogState();
}

class _JoinSessionDialogState extends State<JoinSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sessionIdController = TextEditingController();
  final _userNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _userNameController.text = 'User';
  }

  @override
  void dispose() {
    _sessionIdController.dispose();
    _userNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join Collaboration Session'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _sessionIdController,
              decoration: const InputDecoration(
                labelText: 'Session ID or Link',
                prefixIcon: Icon(Icons.link),
                hintText: 'Paste invite link or session ID',
              ),
              validator: (value) =>
                  value?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _userNameController,
              decoration: const InputDecoration(
                labelText: 'Your Name',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) =>
                  value?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _inviteCodeController,
              decoration: const InputDecoration(
                labelText: 'Invite Code (if required)',
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isJoining ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isJoining ? null : _joinSession,
          child: _isJoining
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }

  Future<void> _joinSession() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isJoining = true);

    // Parse session ID from link if necessary
    var sessionId = _sessionIdController.text.trim();
    if (sessionId.startsWith('fluxforge://collab/')) {
      sessionId = sessionId.replaceFirst('fluxforge://collab/', '');
    }

    final success = await CollaborationService.instance.joinSession(
      sessionId: sessionId,
      userName: _userNameController.text,
      inviteCode: _inviteCodeController.text.isNotEmpty
          ? _inviteCodeController.text
          : null,
    );

    if (mounted) {
      setState(() => _isJoining = false);

      if (success) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              CollaborationService.instance.lastError ?? 'Failed to join session',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ============================================================================
// LIVE CURSORS OVERLAY
// ============================================================================

/// Overlay showing other users' cursors
class LiveCursorsOverlay extends StatelessWidget {
  final CollaborationService service;

  const LiveCursorsOverlay({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final participants = service.participants
            .where((p) => p.id != service.localUser?.id && p.cursor != null)
            .toList();

        return Stack(
          children: participants.map((user) {
            final cursor = user.cursor!;
            final color = _parseColor(user.color);

            return Positioned(
              left: cursor.x,
              top: cursor.y,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cursor
                  Transform.rotate(
                    angle: -0.5,
                    child: Icon(
                      Icons.navigation,
                      color: color,
                      size: 16,
                    ),
                  ),
                  // Name tag
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      user.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }
}
