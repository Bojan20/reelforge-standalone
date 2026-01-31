// FluxForge Studio - CRDT Sync Panel
// P3-13: UI for Collaborative Projects with CRDT synchronization
//
// Displays sync status, conflicts, peer info, and operation history.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/crdt_sync_service.dart';

/// Status badge for CRDT sync
class CrdtSyncStatusBadge extends StatelessWidget {
  final double size;

  const CrdtSyncStatusBadge({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CrdtSyncService.instance,
      builder: (context, _) {
        final status = CrdtSyncService.instance.status;
        final pending = CrdtSyncService.instance.pendingOperations.length;
        final conflicts =
            CrdtSyncService.instance.conflicts.where((c) => !c.isResolved).length;

        Color color;
        IconData icon;
        String tooltip;

        switch (status) {
          case CrdtSyncStatus.disconnected:
            color = Colors.grey;
            icon = Icons.cloud_off;
            tooltip = 'Disconnected';
            break;
          case CrdtSyncStatus.connecting:
            color = Colors.orange;
            icon = Icons.cloud_sync;
            tooltip = 'Connecting...';
            break;
          case CrdtSyncStatus.syncing:
            color = Colors.blue;
            icon = Icons.sync;
            tooltip = 'Syncing ($pending pending)';
            break;
          case CrdtSyncStatus.synced:
            color = Colors.green;
            icon = Icons.cloud_done;
            tooltip = 'Synced';
            break;
          case CrdtSyncStatus.conflictResolution:
            color = Colors.amber;
            icon = Icons.warning;
            tooltip = '$conflicts conflicts';
            break;
          case CrdtSyncStatus.error:
            color = Colors.red;
            icon = Icons.cloud_off;
            tooltip = 'Sync error';
            break;
        }

        return Tooltip(
          message: tooltip,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: color, size: size),
              if (pending > 0 || conflicts > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: conflicts > 0 ? Colors.red : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      conflicts > 0 ? '$conflicts' : '$pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Main CRDT Sync Panel
class CrdtSyncPanel extends StatefulWidget {
  const CrdtSyncPanel({super.key});

  @override
  State<CrdtSyncPanel> createState() => _CrdtSyncPanelState();
}

class _CrdtSyncPanelState extends State<CrdtSyncPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _conflictSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Listen for new conflicts
    _conflictSubscription =
        CrdtSyncService.instance.conflictStream.listen((conflict) {
      if (mounted) {
        _showConflictNotification(conflict);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _conflictSubscription?.cancel();
    super.dispose();
  }

  void _showConflictNotification(SyncConflict conflict) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Conflict detected: ${conflict.description}'),
        backgroundColor: Colors.amber[700],
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            _tabController.animateTo(2); // Conflicts tab
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CrdtSyncService.instance,
      builder: (context, _) {
        return Column(
          children: [
            // Header with status
            _buildHeader(),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: const Color(0xFF4A9EFF),
              tabs: const [
                Tab(text: 'STATUS', icon: Icon(Icons.info_outline, size: 16)),
                Tab(text: 'OPERATIONS', icon: Icon(Icons.history, size: 16)),
                Tab(text: 'CONFLICTS', icon: Icon(Icons.warning_amber, size: 16)),
                Tab(text: 'PEERS', icon: Icon(Icons.people_outline, size: 16)),
              ],
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStatusTab(),
                  _buildOperationsTab(),
                  _buildConflictsTab(),
                  _buildPeersTab(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    final service = CrdtSyncService.instance;
    final doc = service.currentDocument;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          const CrdtSyncStatusBadge(size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc?.name ?? 'No Document',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Node: ${service.nodeId.substring(0, 8)}...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white70),
            onPressed: () => service.syncPendingOperations(),
            tooltip: 'Sync Now',
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white70),
            onPressed: () => _showNewDocumentDialog(),
            tooltip: 'New Document',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTab() {
    final stats = CrdtSyncService.instance.getStatistics();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatCard('Sync Status', [
            _buildStatRow('Status', stats['status']),
            _buildStatRow('Pending Operations', '${stats['pendingOperations']}'),
            _buildStatRow('Connected Peers', '${stats['connectedPeers']}'),
          ]),
          const SizedBox(height: 12),
          _buildStatCard('Operations', [
            _buildStatRow('Applied', '${stats['operationsApplied']}'),
            _buildStatRow('Sent', '${stats['operationsSent']}'),
            _buildStatRow('Received', '${stats['operationsReceived']}'),
            _buildStatRow('Merges', '${stats['mergesPerformed']}'),
          ]),
          const SizedBox(height: 12),
          _buildStatCard('Conflicts', [
            _buildStatRow('Detected', '${stats['conflictsDetected']}'),
            _buildStatRow('Resolved', '${stats['conflictsResolved']}'),
            _buildStatRow('Unresolved', '${stats['unresolvedConflicts']}'),
          ]),
          const SizedBox(height: 16),
          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Export'),
                  onPressed: _exportDocument,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_download),
                  label: const Text('Import'),
                  onPressed: _importDocument,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reset Statistics'),
              onPressed: () => CrdtSyncService.instance.resetStatistics(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF4A9EFF),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsTab() {
    final doc = CrdtSyncService.instance.currentDocument;
    final operations = doc?.operationLog ?? [];

    if (operations.isEmpty) {
      return const Center(
        child: Text(
          'No operations yet',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return ListView.builder(
      itemCount: operations.length,
      itemBuilder: (context, index) {
        final op = operations[operations.length - 1 - index];
        return OperationTile(operation: op);
      },
    );
  }

  Widget _buildConflictsTab() {
    final conflicts = CrdtSyncService.instance.conflicts;
    final unresolvedConflicts = conflicts.where((c) => !c.isResolved).toList();

    if (conflicts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green[400], size: 48),
            const SizedBox(height: 12),
            const Text(
              'No conflicts',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: conflicts.length,
      itemBuilder: (context, index) {
        final conflict = conflicts[conflicts.length - 1 - index];
        return ConflictTile(
          conflict: conflict,
          onResolve: unresolvedConflicts.contains(conflict)
              ? () => _showResolveConflictDialog(conflict)
              : null,
        );
      },
    );
  }

  Widget _buildPeersTab() {
    final peers = CrdtSyncService.instance.peerLastSeen;

    if (peers.isEmpty) {
      return const Center(
        child: Text(
          'No peers connected',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return ListView.builder(
      itemCount: peers.length,
      itemBuilder: (context, index) {
        final peerId = peers.keys.elementAt(index);
        final lastSeen = peers[peerId]!;
        return PeerTile(peerId: peerId, lastSeen: lastSeen);
      },
    );
  }

  void _showNewDocumentDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('New Collaborative Document',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Document Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                CrdtSyncService.instance.createDocument(nameController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showResolveConflictDialog(SyncConflict conflict) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Resolve Conflict', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflict.description,
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            const SizedBox(height: 16),
            const Text('Choose resolution:', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Keep Local', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                'Keep your changes (${conflict.localOp.type.name})',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              leading: Radio<bool>(
                value: true,
                groupValue: true,
                onChanged: (_) {},
              ),
              onTap: () {
                CrdtSyncService.instance
                    .resolveConflict(conflict.id, conflict.localOp);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Keep Remote', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                'Accept remote changes (${conflict.remoteOp.type.name})',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              leading: Radio<bool>(
                value: false,
                groupValue: true,
                onChanged: (_) {},
              ),
              onTap: () {
                CrdtSyncService.instance
                    .resolveConflict(conflict.id, conflict.remoteOp);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _exportDocument() {
    try {
      final json = CrdtSyncService.instance.exportDocument();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document exported (${json.length} bytes)'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  void _importDocument() {
    // In production, this would open file picker
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Import from file picker (not implemented in demo)'),
      ),
    );
  }
}

/// Operation tile
class OperationTile extends StatelessWidget {
  final CrdtOperation operation;

  const OperationTile({super.key, required this.operation});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (operation.type) {
      case CrdtOperationType.insert:
        icon = Icons.add;
        color = Colors.green;
        break;
      case CrdtOperationType.delete:
        icon = Icons.delete;
        color = Colors.red;
        break;
      case CrdtOperationType.update:
        icon = Icons.edit;
        color = Colors.blue;
        break;
      case CrdtOperationType.move:
        icon = Icons.swap_horiz;
        color = Colors.orange;
        break;
      case CrdtOperationType.setAttribute:
        icon = Icons.settings;
        color = Colors.purple;
        break;
      case CrdtOperationType.removeAttribute:
        icon = Icons.remove_circle;
        color = Colors.amber;
        break;
    }

    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      title: Text(
        '${operation.type.name.toUpperCase()} ${operation.dataType.name}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        'Target: ${operation.targetId.substring(0, 8)}...',
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(operation.createdAt),
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
          ),
          Text(
            operation.authorId.substring(0, 6),
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Conflict tile
class ConflictTile extends StatelessWidget {
  final SyncConflict conflict;
  final VoidCallback? onResolve;

  const ConflictTile({super.key, required this.conflict, this.onResolve});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: conflict.isResolved
              ? Colors.green.withOpacity(0.2)
              : Colors.amber.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          conflict.isResolved ? Icons.check : Icons.warning,
          color: conflict.isResolved ? Colors.green : Colors.amber,
          size: 20,
        ),
      ),
      title: Text(
        conflict.description,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        'Local: ${conflict.localOp.type.name} vs Remote: ${conflict.remoteOp.type.name}',
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
      ),
      trailing: conflict.isResolved
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : TextButton(
              onPressed: onResolve,
              child: const Text('RESOLVE'),
            ),
    );
  }
}

/// Peer tile
class PeerTile extends StatelessWidget {
  final String peerId;
  final DateTime lastSeen;

  const PeerTile({super.key, required this.peerId, required this.lastSeen});

  @override
  Widget build(BuildContext context) {
    final isOnline = DateTime.now().difference(lastSeen).inSeconds < 30;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.1),
            child: Text(
              peerId.substring(0, 2).toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1E1E2E), width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        peerId.substring(0, 12),
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        isOnline ? 'Online' : 'Last seen: ${_formatLastSeen(lastSeen)}',
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
      ),
      trailing: isOnline
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'ONLINE',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  String _formatLastSeen(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
