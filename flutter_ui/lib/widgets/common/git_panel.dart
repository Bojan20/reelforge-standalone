/// Git Panel Widget
///
/// Version control UI for commit, branch, and history management.
///
/// P3-05: Version Control Integration UI (~450 LOC)
library;

import 'package:flutter/material.dart';
import '../../services/version_control_service.dart';

/// Git panel for version control operations
class GitPanel extends StatefulWidget {
  final String? repoPath;

  const GitPanel({super.key, this.repoPath});

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _vcs = VersionControlService.instance;
  final _commitMessageController = TextEditingController();

  GitRepoInfo? _repoInfo;
  List<GitStatusEntry> _status = [];
  List<GitCommit> _history = [];
  List<GitBranch> _branches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initRepo();
  }

  Future<void> _initRepo() async {
    if (widget.repoPath == null) {
      setState(() {
        _loading = false;
        _error = 'No repository path provided';
      });
      return;
    }

    try {
      final info = await _vcs.init(widget.repoPath!);
      setState(() {
        _repoInfo = info;
        _loading = false;
      });

      if (info.isRepo) {
        await _refresh();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final status = await _vcs.getStatus();
      final history = await _vcs.getHistory(limit: 20);
      final branches = await _vcs.getBranches();

      if (mounted) {
        setState(() {
          _status = status;
          _history = history;
          _branches = branches;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commitMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121216),
      child: Column(
        children: [
          _buildHeader(),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(child: _buildErrorState())
          else if (_repoInfo?.isRepo != true)
            Expanded(child: _buildNotRepoState())
          else
            Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a20),
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a30))),
      ),
      child: Row(
        children: [
          const Icon(Icons.merge_type, color: Color(0xFFff9040), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Version Control',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          if (_repoInfo?.currentBranch != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF40ff90).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call_split, size: 12, color: Color(0xFF40ff90)),
                  const SizedBox(width: 4),
                  Text(
                    _repoInfo!.currentBranch!,
                    style: const TextStyle(
                      color: Color(0xFF40ff90),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            color: const Color(0xFF888888),
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Unknown error',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotRepoState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'Not a Git repository',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              if (widget.repoPath != null) {
                await _vcs.initRepo(widget.repoPath!);
                await _initRepo();
              }
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Initialize Repository'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a9eff),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Tab bar
        Container(
          color: const Color(0xFF0a0a0c),
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF4a9eff),
            unselectedLabelColor: const Color(0xFF888888),
            indicatorColor: const Color(0xFF4a9eff),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_note, size: 16),
                    const SizedBox(width: 6),
                    const Text('Changes'),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFff9040),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_status.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 16),
                    SizedBox(width: 6),
                    Text('History'),
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.call_split, size: 16),
                    SizedBox(width: 6),
                    Text('Branches'),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildChangesTab(),
              _buildHistoryTab(),
              _buildBranchesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChangesTab() {
    final staged = _status.where((s) => s.staged).toList();
    final unstaged = _status.where((s) => !s.staged).toList();

    return Column(
      children: [
        // Commit message input
        Container(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _commitMessageController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Commit message...',
              hintStyle: const TextStyle(color: Color(0xFF888888)),
              filled: true,
              fillColor: const Color(0xFF0a0a0c),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF2a2a30)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF2a2a30)),
              ),
            ),
          ),
        ),
        // Commit button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: staged.isEmpty
                      ? null
                      : () async {
                          final msg = _commitMessageController.text.trim();
                          if (msg.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a commit message')),
                            );
                            return;
                          }
                          try {
                            await _vcs.commit(msg);
                            _commitMessageController.clear();
                            await _refresh();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Commit failed: $e')),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.check, size: 18),
                  label: Text('Commit ${staged.length} files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF40ff90),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF2a2a30),
                    disabledForegroundColor: const Color(0xFF888888),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_box, size: 20),
                color: const Color(0xFF4a9eff),
                tooltip: 'Stage All',
                onPressed: unstaged.isEmpty
                    ? null
                    : () async {
                        await _vcs.stageAll();
                        await _refresh();
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: Color(0xFF2a2a30)),
        // File lists
        Expanded(
          child: ListView(
            children: [
              if (staged.isNotEmpty) ...[
                _buildSectionHeader('Staged Changes', staged.length),
                ...staged.map((s) => _buildStatusItem(s, true)),
              ],
              if (unstaged.isNotEmpty) ...[
                _buildSectionHeader('Changes', unstaged.length),
                ...unstaged.map((s) => _buildStatusItem(s, false)),
              ],
              if (_status.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No changes',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF0a0a0c),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF2a2a30),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(GitStatusEntry entry, bool staged) {
    return ListTile(
      dense: true,
      leading: Icon(
        _getStatusIcon(entry.status),
        size: 16,
        color: _getStatusColor(entry.status),
      ),
      title: Text(
        entry.path,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (staged)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 16),
              color: const Color(0xFF888888),
              tooltip: 'Unstage',
              onPressed: () async {
                await _vcs.unstageFiles([entry.path]);
                await _refresh();
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 16),
              color: const Color(0xFF4a9eff),
              tooltip: 'Stage',
              onPressed: () async {
                await _vcs.stageFiles([entry.path]);
                await _refresh();
              },
            ),
          if (!staged && entry.status != GitFileStatus.untracked)
            IconButton(
              icon: const Icon(Icons.undo, size: 16),
              color: const Color(0xFFff6b6b),
              tooltip: 'Discard',
              onPressed: () async {
                await _vcs.discardChanges([entry.path]);
                await _refresh();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          'No commits yet',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final commit = _history[index];
        return ListTile(
          dense: true,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                commit.author[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF4a9eff),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          title: Text(
            commit.message,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${commit.shortHash} · ${commit.author} · ${_formatDate(commit.date)}',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
          ),
        );
      },
    );
  }

  Widget _buildBranchesTab() {
    final local = _branches.where((b) => !b.isRemote).toList();

    return Column(
      children: [
        // New branch button
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showNewBranchDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Branch'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4a9eff),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF2a2a30)),
        // Branch list
        Expanded(
          child: ListView.builder(
            itemCount: local.length,
            itemBuilder: (context, index) {
              final branch = local[index];
              return ListTile(
                dense: true,
                leading: Icon(
                  branch.isCurrent ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: branch.isCurrent
                      ? const Color(0xFF40ff90)
                      : const Color(0xFF888888),
                ),
                title: Text(
                  branch.name,
                  style: TextStyle(
                    color: branch.isCurrent ? const Color(0xFF40ff90) : Colors.white,
                    fontSize: 12,
                    fontWeight: branch.isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: branch.isCurrent
                    ? null
                    : PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF888888)),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'checkout',
                            child: Text('Checkout'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'checkout') {
                            await _vcs.switchBranch(branch.name);
                            await _refresh();
                            final info = await _vcs.getRepoInfo();
                            if (mounted) {
                              setState(() => _repoInfo = info);
                            }
                          } else if (value == 'delete') {
                            await _vcs.deleteBranch(branch.name);
                            await _refresh();
                          }
                        },
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showNewBranchDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: const Text('New Branch', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Branch name',
            hintStyle: TextStyle(color: Color(0xFF888888)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await _vcs.createBranch(name);
                await _refresh();
                final info = await _vcs.getRepoInfo();
                if (mounted) {
                  setState(() => _repoInfo = info);
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(GitFileStatus status) {
    switch (status) {
      case GitFileStatus.modified:
        return Icons.edit;
      case GitFileStatus.added:
        return Icons.add;
      case GitFileStatus.deleted:
        return Icons.delete;
      case GitFileStatus.renamed:
        return Icons.drive_file_rename_outline;
      case GitFileStatus.copied:
        return Icons.copy;
      case GitFileStatus.untracked:
        return Icons.help_outline;
      case GitFileStatus.ignored:
        return Icons.visibility_off;
      case GitFileStatus.conflicted:
        return Icons.warning;
    }
  }

  Color _getStatusColor(GitFileStatus status) {
    switch (status) {
      case GitFileStatus.modified:
        return const Color(0xFFff9040);
      case GitFileStatus.added:
        return const Color(0xFF40ff90);
      case GitFileStatus.deleted:
        return const Color(0xFFff6b6b);
      case GitFileStatus.renamed:
        return const Color(0xFF4a9eff);
      case GitFileStatus.copied:
        return const Color(0xFF4a9eff);
      case GitFileStatus.untracked:
        return const Color(0xFF888888);
      case GitFileStatus.ignored:
        return const Color(0xFF888888);
      case GitFileStatus.conflicted:
        return const Color(0xFFff6b6b);
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
