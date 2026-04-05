/// Cloud Sync Panel — P3-01
///
/// UI widgets for cloud project synchronization:
/// - CloudSyncStatusBadge: Compact status indicator
/// - CloudSyncPanel: Full management panel
/// - CloudProjectList: Project listing with sync status
/// - CloudAuthDialog: Authentication dialog
///
/// Created: 2026-01-31 (P3-01)
library;

import 'package:flutter/material.dart';

import '../../services/cloud_sync_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD SYNC STATUS BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact cloud sync status badge for app bar
class CloudSyncStatusBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const CloudSyncStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudSyncService.instance,
      builder: (context, _) {
        final service = CloudSyncService.instance;

        return Tooltip(
          message: _getTooltip(service),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getBackgroundColor(service).withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _getBackgroundColor(service).withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcon(service),
                  const SizedBox(width: 4),
                  Text(
                    _getStatusText(service),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _getBackgroundColor(service),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIcon(CloudSyncService service) {
    if (service.isSyncing) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(_getBackgroundColor(service)),
        ),
      );
    }

    return Icon(
      _getIcon(service),
      size: 14,
      color: _getBackgroundColor(service),
    );
  }

  IconData _getIcon(CloudSyncService service) {
    if (!service.isAuthenticated) return Icons.cloud_off;

    switch (service.status) {
      case SyncStatus.idle:
      case SyncStatus.complete:
        return Icons.cloud_done;
      case SyncStatus.checking:
      case SyncStatus.uploading:
      case SyncStatus.downloading:
      case SyncStatus.resolving:
        return Icons.cloud_sync;
      case SyncStatus.error:
        return Icons.cloud_off;
    }
  }

  Color _getBackgroundColor(CloudSyncService service) {
    if (!service.isAuthenticated) return Colors.grey;

    switch (service.status) {
      case SyncStatus.idle:
      case SyncStatus.complete:
        return const Color(0xFF40FF90);
      case SyncStatus.checking:
      case SyncStatus.uploading:
      case SyncStatus.downloading:
      case SyncStatus.resolving:
        return const Color(0xFF4A9EFF);
      case SyncStatus.error:
        return const Color(0xFFFF4060);
    }
  }

  String _getStatusText(CloudSyncService service) {
    if (!service.isAuthenticated) return 'Offline';
    return service.status.displayName;
  }

  String _getTooltip(CloudSyncService service) {
    if (!service.isAuthenticated) {
      return 'Not signed in to cloud';
    }

    final projectCount = service.projects.length;
    final needsSync = service.projects.where((p) => p.status.needsSync).length;

    if (needsSync > 0) {
      return '$needsSync project(s) need sync';
    }

    return '$projectCount project(s) synced';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD SYNC PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Full cloud sync management panel
class CloudSyncPanel extends StatefulWidget {
  const CloudSyncPanel({super.key});

  @override
  State<CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<CloudSyncPanel> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudSyncService.instance,
      builder: (context, _) {
        final service = CloudSyncService.instance;

        return Container(
          color: const Color(0xFF1A1A20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(service),
              const Divider(height: 1, color: Color(0xFF2A2A30)),

              // Content
              Expanded(
                child: service.isAuthenticated
                    ? _buildProjectList(service)
                    : _buildAuthPrompt(),
              ),

              // Footer
              if (service.isAuthenticated) _buildFooter(service),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(CloudSyncService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.cloud,
            color: service.isAuthenticated
                ? const Color(0xFF4A9EFF)
                : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cloud Sync',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  service.isAuthenticated
                      ? service.userEmail ?? 'Signed in'
                      : 'Not signed in',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (service.isAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout, size: 18),
              color: Colors.white54,
              tooltip: 'Sign out',
              onPressed: () => _signOut(),
            )
          else
            TextButton(
              onPressed: () => _showAuthDialog(),
              child: const Text('Sign In'),
            ),
        ],
      ),
    );
  }

  Widget _buildAuthPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Sign in to sync your projects',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAuthDialog(),
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList(CloudSyncService service) {
    if (service.projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open,
                size: 48,
                color: Colors.white.withOpacity(0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'No projects synced yet',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _uploadNewProject(),
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: const Text('Upload Project'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: service.projects.length,
      itemBuilder: (context, index) {
        final project = service.projects[index];
        return _CloudProjectTile(
          project: project,
          onSync: () => _syncProject(project.id),
          onDelete: () => _deleteProject(project.id),
          onShare: () => _shareProject(project.id),
        );
      },
    );
  }

  Widget _buildFooter(CloudSyncService service) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Row(
        children: [
          // Sync status
          if (service.isSyncing)
            Expanded(
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      service.currentOperation ?? 'Syncing...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Text(
                '${service.projects.length} project(s)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
            ),

          // Actions
          IconButton(
            icon: const Icon(Icons.cloud_upload, size: 18),
            color: Colors.white54,
            tooltip: 'Upload project',
            onPressed: service.isSyncing ? null : () => _uploadNewProject(),
          ),
          IconButton(
            icon: const Icon(Icons.sync, size: 18),
            color: Colors.white54,
            tooltip: 'Sync all',
            onPressed: service.isSyncing ? null : () => _syncAll(),
          ),
        ],
      ),
    );
  }

  void _showAuthDialog() {
    showDialog(
      context: context,
      builder: (context) => const CloudAuthDialog(),
    );
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out from cloud sync?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CloudSyncService.instance.signOut();
    }
  }

  void _uploadNewProject() {
    // Show file picker and upload
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select a project folder to upload')),
    );
  }

  Future<void> _syncProject(String projectId) async {
    final result = await CloudSyncService.instance.syncProject(projectId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.toString())),
      );
    }
  }

  Future<void> _syncAll() async {
    final results = await CloudSyncService.instance.syncAllProjects();
    if (mounted) {
      final successCount = results.where((r) => r.success).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced $successCount/${results.length} projects'),
        ),
      );
    }
  }

  Future<void> _deleteProject(String projectId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from Cloud'),
        content: const Text(
          'This will remove the project from cloud storage. '
          'Local files will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CloudSyncService.instance.deleteCloudProject(projectId);
    }
  }

  void _shareProject(String projectId) {
    showDialog(
      context: context,
      builder: (context) => _ShareProjectDialog(projectId: projectId),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD PROJECT TILE
// ═══════════════════════════════════════════════════════════════════════════

class _CloudProjectTile extends StatelessWidget {
  final CloudProject project;
  final VoidCallback onSync;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _CloudProjectTile({
    required this.project,
    required this.onSync,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildStatusIcon(),
        title: Text(
          project.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${_formatSize(project.sizeBytes)} • ${_formatDate(project.updatedAt)}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'sync', child: Text('Sync')),
            const PopupMenuItem(value: 'share', child: Text('Share')),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'sync':
                onSync();
                break;
              case 'share':
                onShare();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    Color color;
    IconData icon;

    switch (project.status) {
      case CloudProjectStatus.synced:
        color = const Color(0xFF40FF90);
        icon = Icons.cloud_done;
        break;
      case CloudProjectStatus.localChanges:
        color = const Color(0xFFFF9040);
        icon = Icons.cloud_upload;
        break;
      case CloudProjectStatus.remoteChanges:
        color = const Color(0xFF4A9EFF);
        icon = Icons.cloud_download;
        break;
      case CloudProjectStatus.conflict:
        color = const Color(0xFFFF4060);
        icon = Icons.warning;
        break;
      case CloudProjectStatus.syncing:
        color = const Color(0xFF4A9EFF);
        icon = Icons.sync;
        break;
      case CloudProjectStatus.error:
        color = const Color(0xFFFF4060);
        icon = Icons.error;
        break;
      case CloudProjectStatus.local:
        color = Colors.grey;
        icon = Icons.folder;
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD AUTH DIALOG
// ═══════════════════════════════════════════════════════════════════════════

/// Authentication dialog for cloud sync
class CloudAuthDialog extends StatefulWidget {
  const CloudAuthDialog({super.key});

  @override
  State<CloudAuthDialog> createState() => _CloudAuthDialogState();
}

class _CloudAuthDialogState extends State<CloudAuthDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign In to Cloud'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              enabled: !_isLoading,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _signIn,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign In'),
        ),
      ],
    );
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final success = await CloudSyncService.instance.authenticate(
      email: email,
      password: password,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _isLoading = false;
        _error = 'Authentication failed. Please try again.';
      });
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARE PROJECT DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _ShareProjectDialog extends StatefulWidget {
  final String projectId;

  const _ShareProjectDialog({required this.projectId});

  @override
  State<_ShareProjectDialog> createState() => _ShareProjectDialogState();
}

class _ShareProjectDialogState extends State<_ShareProjectDialog> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share Project'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'Enter collaborator email',
                prefixIcon: Icon(Icons.person_add),
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            Text(
              'The user will receive view access to this project.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _share,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Share'),
        ),
      ],
    );
  }

  Future<void> _share() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isLoading = true);

    final success = await CloudSyncService.instance.shareProject(
      widget.projectId,
      email,
    );

    if (!mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Project shared with $email' : 'Failed to share project',
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD SYNC PROGRESS DIALOG
// ═══════════════════════════════════════════════════════════════════════════

/// Progress dialog for sync operations
class CloudSyncProgressDialog extends StatelessWidget {
  final String title;
  final VoidCallback? onCancel;

  const CloudSyncProgressDialog({
    super.key,
    this.title = 'Syncing...',
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudSyncService.instance,
      builder: (context, _) {
        final service = CloudSyncService.instance;

        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: service.progress),
              const SizedBox(height: 16),
              Text(
                service.currentOperation ?? service.status.displayName,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              if (service.progress > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${(service.progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
          ],
        );
      },
    );
  }
}
