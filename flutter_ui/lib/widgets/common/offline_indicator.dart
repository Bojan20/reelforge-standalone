/// Offline Indicator Widget — P3-14
///
/// Visual indicators for offline status and pending operations.
///
/// Widgets:
///   - OfflineStatusBadge: Compact status badge for headers
///   - OfflineBanner: Full-width banner for offline mode
///   - OfflineSyncButton: Sync button with progress
///   - OfflineStatusPanel: Detailed status panel for settings
library;

import 'package:flutter/material.dart';

import '../../services/offline_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OFFLINE STATUS BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact status badge showing connectivity and pending operations
class OfflineStatusBadge extends StatelessWidget {
  const OfflineStatusBadge({
    super.key,
    this.showPendingCount = true,
    this.onTap,
  });

  final bool showPendingCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineService.instance,
      builder: (context, _) {
        final service = OfflineService.instance;
        final status = service.status;
        final pendingCount = service.pendingCount;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getStatusColor(status).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status icon
                Icon(
                  _getStatusIcon(status),
                  size: 14,
                  color: _getStatusColor(status),
                ),
                const SizedBox(width: 4),

                // Status text
                Text(
                  status.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _getStatusColor(status),
                  ),
                ),

                // Pending count badge
                if (showPendingCount && pendingCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$pendingCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],

                // Syncing indicator
                if (service.isSyncing) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.blue),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.online:
        return Colors.green;
      case ConnectivityStatus.offline:
        return Colors.red;
      case ConnectivityStatus.checking:
        return Colors.orange;
      case ConnectivityStatus.unstable:
        return Colors.amber;
    }
  }

  IconData _getStatusIcon(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.online:
        return Icons.cloud_done_outlined;
      case ConnectivityStatus.offline:
        return Icons.cloud_off_outlined;
      case ConnectivityStatus.checking:
        return Icons.cloud_sync_outlined;
      case ConnectivityStatus.unstable:
        return Icons.cloud_outlined;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OFFLINE BANNER
// ═══════════════════════════════════════════════════════════════════════════

/// Full-width banner shown when offline
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.showSyncButton = true,
    this.onDismiss,
  });

  final bool showSyncButton;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineService.instance,
      builder: (context, _) {
        final service = OfflineService.instance;

        // Only show when offline
        if (service.isOnline && !service.hasPendingOperations) {
          return const SizedBox.shrink();
        }

        final isOffline = service.isOffline;
        final pendingCount = service.pendingCount;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isOffline
                ? Colors.red.shade900.withOpacity(0.9)
                : Colors.orange.shade900.withOpacity(0.9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Icon(
                isOffline ? Icons.cloud_off : Icons.cloud_sync,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),

              // Message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isOffline
                          ? 'You are offline'
                          : 'Syncing pending operations...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (pendingCount > 0)
                      Text(
                        '$pendingCount operation${pendingCount == 1 ? '' : 's'} pending',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),

              // Sync button
              if (showSyncButton && service.isOnline && pendingCount > 0)
                TextButton.icon(
                  onPressed: service.isSyncing ? null : service.forceSync,
                  icon: service.isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: Text(service.isSyncing ? 'Syncing...' : 'Sync Now'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),

              // Dismiss button
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.white.withOpacity(0.7),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OFFLINE SYNC BUTTON
// ═══════════════════════════════════════════════════════════════════════════

/// Sync button with progress indicator
class OfflineSyncButton extends StatelessWidget {
  const OfflineSyncButton({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineService.instance,
      builder: (context, _) {
        final service = OfflineService.instance;
        final pendingCount = service.pendingCount;
        final isSyncing = service.isSyncing;
        final isOnline = service.isOnline;

        // Hide if nothing to sync
        if (pendingCount == 0 && !isSyncing) {
          return const SizedBox.shrink();
        }

        if (compact) {
          return IconButton(
            onPressed: isOnline && !isSyncing ? service.forceSync : null,
            icon: isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    label: Text('$pendingCount'),
                    isLabelVisible: pendingCount > 0,
                    child: const Icon(Icons.sync),
                  ),
            tooltip: isSyncing
                ? 'Syncing...'
                : isOnline
                    ? 'Sync $pendingCount pending'
                    : 'Offline - will sync when online',
          );
        }

        return FilledButton.icon(
          onPressed: isOnline && !isSyncing ? service.forceSync : null,
          icon: isSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.sync, size: 18),
          label: Text(
            isSyncing
                ? 'Syncing...'
                : isOnline
                    ? 'Sync ($pendingCount)'
                    : 'Offline',
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OFFLINE STATUS PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Detailed status panel for settings or debug view
class OfflineStatusPanel extends StatelessWidget {
  const OfflineStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: OfflineService.instance,
      builder: (context, _) {
        final service = OfflineService.instance;
        final queue = service.queue;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Offline Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  OfflineStatusBadge(showPendingCount: false),
                ],
              ),
              const SizedBox(height: 16),

              // Status info
              _buildInfoRow(
                context,
                'Connection',
                service.status.displayName,
                _getStatusColor(service.status),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                context,
                'Pending Operations',
                '${service.pendingCount}',
                service.pendingCount > 0 ? Colors.orange : Colors.grey,
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                context,
                'Sync Status',
                service.isSyncing ? 'Syncing...' : 'Idle',
                service.isSyncing ? Colors.blue : Colors.grey,
              ),

              // Queue list
              if (queue.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Pending Queue',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final op = queue[index];
                      return _buildQueueItem(context, op);
                    },
                  ),
                ),
              ],

              // Actions
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: service.checkConnectivity,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Check Connection'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: service.isOnline && service.hasPendingOperations
                          ? service.forceSync
                          : null,
                      icon: service.isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.sync, size: 18),
                      label: Text(service.isSyncing ? 'Syncing...' : 'Sync Now'),
                    ),
                  ),
                ],
              ),

              // Clear queue (destructive)
              if (queue.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _showClearConfirmation(context),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Clear Queue'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueItem(BuildContext context, OfflineOperation op) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            _getOperationIcon(op.type),
            size: 16,
            color: _getPriorityColor(op.priority),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  op.type.name.replaceAllMapped(
                    RegExp(r'([A-Z])'),
                    (m) => ' ${m.group(0)}',
                  ).trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (op.errorMessage != null)
                  Text(
                    op.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          if (op.retryCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${op.retryCount}x',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                ),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => OfflineService.instance.removeOperation(op.id),
            icon: const Icon(Icons.close, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.online:
        return Colors.green;
      case ConnectivityStatus.offline:
        return Colors.red;
      case ConnectivityStatus.checking:
        return Colors.orange;
      case ConnectivityStatus.unstable:
        return Colors.amber;
    }
  }

  IconData _getOperationIcon(OfflineOperationType type) {
    switch (type) {
      case OfflineOperationType.saveProject:
        return Icons.save_outlined;
      case OfflineOperationType.uploadAudio:
        return Icons.upload_file_outlined;
      case OfflineOperationType.syncEvents:
        return Icons.event_outlined;
      case OfflineOperationType.exportProject:
        return Icons.folder_zip_outlined;
      case OfflineOperationType.analytics:
        return Icons.analytics_outlined;
      case OfflineOperationType.custom:
        return Icons.extension_outlined;
    }
  }

  Color _getPriorityColor(OperationPriority priority) {
    switch (priority) {
      case OperationPriority.critical:
        return Colors.red;
      case OperationPriority.high:
        return Colors.orange;
      case OperationPriority.normal:
        return Colors.blue;
      case OperationPriority.low:
        return Colors.grey;
    }
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue?'),
        content: const Text(
          'This will remove all pending offline operations. '
          'These operations will not be synced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              OfflineService.instance.clearQueue();
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OFFLINE WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

/// Wrapper that shows offline banner above content
class OfflineAwareScaffold extends StatefulWidget {
  const OfflineAwareScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showBanner = true,
    this.bannerDismissible = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showBanner;
  final bool bannerDismissible;

  @override
  State<OfflineAwareScaffold> createState() => _OfflineAwareScaffoldState();
}

class _OfflineAwareScaffoldState extends State<OfflineAwareScaffold> {
  bool _bannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Column(
        children: [
          // Offline banner
          if (widget.showBanner && !_bannerDismissed)
            OfflineBanner(
              onDismiss: widget.bannerDismissible
                  ? () => setState(() => _bannerDismissed = true)
                  : null,
            ),

          // Main content
          Expanded(child: widget.body),
        ],
      ),
    );
  }
}
