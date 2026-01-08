// Version Comparison Dialog
//
// Professional dialog for comparing two project versions:
// - Side-by-side diff view
// - Track-by-track comparison
// - Added/removed/modified indicators
// - Plugin differences
// - Mix parameter changes

import 'package:flutter/material.dart';
import '../theme/reelforge_theme.dart';

/// Types of changes
enum ChangeType {
  added,
  removed,
  modified,
  unchanged,
}

/// Single change item
class VersionChange {
  final ChangeType type;
  final String category;
  final String item;
  final String? oldValue;
  final String? newValue;
  final String? details;

  const VersionChange({
    required this.type,
    required this.category,
    required this.item,
    this.oldValue,
    this.newValue,
    this.details,
  });
}

/// Version comparison data
class VersionComparison {
  final String oldVersionId;
  final String oldVersionName;
  final String newVersionId;
  final String newVersionName;
  final DateTime oldDate;
  final DateTime newDate;
  final List<VersionChange> changes;
  final int addedCount;
  final int removedCount;
  final int modifiedCount;

  const VersionComparison({
    required this.oldVersionId,
    required this.oldVersionName,
    required this.newVersionId,
    required this.newVersionName,
    required this.oldDate,
    required this.newDate,
    required this.changes,
    required this.addedCount,
    required this.removedCount,
    required this.modifiedCount,
  });

  int get totalChanges => addedCount + removedCount + modifiedCount;
}

class VersionCompareDialog extends StatefulWidget {
  final String oldVersionId;
  final String oldVersionName;
  final String newVersionId;
  final String newVersionName;
  /// Callback to load comparison data from FFI
  final Future<VersionComparison> Function(String oldId, String newId) onLoadComparison;

  const VersionCompareDialog({
    super.key,
    required this.oldVersionId,
    required this.oldVersionName,
    required this.newVersionId,
    required this.newVersionName,
    required this.onLoadComparison,
  });

  static Future<void> show(
    BuildContext context, {
    required String oldVersionId,
    required String oldVersionName,
    required String newVersionId,
    required String newVersionName,
    required Future<VersionComparison> Function(String oldId, String newId) onLoadComparison,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => VersionCompareDialog(
        oldVersionId: oldVersionId,
        oldVersionName: oldVersionName,
        newVersionId: newVersionId,
        newVersionName: newVersionName,
        onLoadComparison: onLoadComparison,
      ),
    );
  }

  @override
  State<VersionCompareDialog> createState() => _VersionCompareDialogState();
}

class _VersionCompareDialogState extends State<VersionCompareDialog> {
  VersionComparison? _comparison;
  bool _isLoading = true;
  String? _error;
  String _selectedCategory = 'All';
  ChangeType? _filterType;

  @override
  void initState() {
    super.initState();
    _loadComparison();
  }

  Future<void> _loadComparison() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final comparison = await widget.onLoadComparison(
        widget.oldVersionId,
        widget.newVersionId,
      );
      setState(() {
        _comparison = comparison;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<String> get _categories {
    if (_comparison == null) return ['All'];
    final cats = <String>{'All'};
    for (final c in _comparison!.changes) {
      cats.add(c.category);
    }
    return cats.toList()..sort();
  }

  List<VersionChange> get _filteredChanges {
    if (_comparison == null) return [];
    return _comparison!.changes.where((c) {
      if (_selectedCategory != 'All' && c.category != _selectedCategory) {
        return false;
      }
      if (_filterType != null && c.type != _filterType) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReelForgeTheme.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            _buildHeader(),
            if (_comparison != null) _buildSummaryBar(),
            const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
            if (_comparison != null) _buildFilterBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError()
                      : _buildDiffView(),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.compare_arrows, color: ReelForgeTheme.accentBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Version Comparison',
                  style: TextStyle(
                    color: ReelForgeTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      widget.oldVersionName,
                      style: TextStyle(color: ReelForgeTheme.accentRed, fontSize: 12),
                    ),
                    const Icon(Icons.arrow_right_alt, color: Colors.white38, size: 18),
                    Text(
                      widget.newVersionName,
                      style: TextStyle(color: ReelForgeTheme.accentGreen, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: ReelForgeTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final comp = _comparison!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: ReelForgeTheme.bgSurface,
      child: Row(
        children: [
          _buildSummaryChip(
            comp.addedCount,
            'Added',
            ReelForgeTheme.accentGreen,
            Icons.add_circle_outline,
            () => setState(() => _filterType = _filterType == ChangeType.added ? null : ChangeType.added),
            _filterType == ChangeType.added,
          ),
          const SizedBox(width: 12),
          _buildSummaryChip(
            comp.removedCount,
            'Removed',
            ReelForgeTheme.accentRed,
            Icons.remove_circle_outline,
            () => setState(() => _filterType = _filterType == ChangeType.removed ? null : ChangeType.removed),
            _filterType == ChangeType.removed,
          ),
          const SizedBox(width: 12),
          _buildSummaryChip(
            comp.modifiedCount,
            'Modified',
            ReelForgeTheme.accentOrange,
            Icons.edit,
            () => setState(() => _filterType = _filterType == ChangeType.modified ? null : ChangeType.modified),
            _filterType == ChangeType.modified,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${comp.totalChanges} total changes',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(
    int count,
    String label,
    Color color,
    IconData icon,
    VoidCallback onTap,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              '$count $label',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ReelForgeTheme.bgMid.withValues(alpha: 0.5),
      child: Row(
        children: [
          // Category filter
          const Text('Category: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _selectedCategory,
            dropdownColor: ReelForgeTheme.bgMid,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            underline: const SizedBox(),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _selectedCategory = v ?? 'All'),
          ),
          const Spacer(),
          // Clear filter
          if (_filterType != null || _selectedCategory != 'All')
            TextButton.icon(
              onPressed: () => setState(() {
                _filterType = null;
                _selectedCategory = 'All';
              }),
              icon: const Icon(Icons.clear, size: 14),
              label: const Text('Clear Filters'),
              style: TextButton.styleFrom(foregroundColor: Colors.white54),
            ),
        ],
      ),
    );
  }

  Widget _buildDiffView() {
    final changes = _filteredChanges;

    if (changes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _filterType != null || _selectedCategory != 'All'
                  ? Icons.filter_list_off
                  : Icons.check_circle_outline,
              size: 48,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              _filterType != null || _selectedCategory != 'All'
                  ? 'No changes match current filters'
                  : 'No differences found',
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ),
      );
    }

    // Group by category
    final grouped = <String, List<VersionChange>>{};
    for (final c in changes) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCategoryHeader(entry.key, entry.value.length),
            ...entry.value.map(_buildChangeItem),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildCategoryHeader(String category, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(_getCategoryIcon(category), size: 16, color: ReelForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            category,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeItem(VersionChange change) {
    final (color, icon) = _getChangeStyle(change.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  change.item,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getChangeTypeName(change.type),
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (change.oldValue != null || change.newValue != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (change.oldValue != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.accentRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.remove, size: 10, color: ReelForgeTheme.accentRed),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              change.oldValue!,
                              style: const TextStyle(
                                color: ReelForgeTheme.accentRed,
                                fontSize: 10,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (change.oldValue != null && change.newValue != null) const SizedBox(width: 8),
                if (change.newValue != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.add, size: 10, color: ReelForgeTheme.accentGreen),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              change.newValue!,
                              style: const TextStyle(
                                color: ReelForgeTheme.accentGreen,
                                fontSize: 10,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (change.details != null) ...[
            const SizedBox(height: 6),
            Text(
              change.details!,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: ReelForgeTheme.accentRed),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadComparison,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_comparison != null) ...[
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Export diff as text/markdown
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export Diff'),
            ),
            const SizedBox(width: 12),
          ],
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  (Color, IconData) _getChangeStyle(ChangeType type) {
    switch (type) {
      case ChangeType.added:
        return (ReelForgeTheme.accentGreen, Icons.add_circle);
      case ChangeType.removed:
        return (ReelForgeTheme.accentRed, Icons.remove_circle);
      case ChangeType.modified:
        return (ReelForgeTheme.accentOrange, Icons.edit);
      case ChangeType.unchanged:
        return (Colors.white38, Icons.horizontal_rule);
    }
  }

  String _getChangeTypeName(ChangeType type) {
    switch (type) {
      case ChangeType.added:
        return 'ADDED';
      case ChangeType.removed:
        return 'REMOVED';
      case ChangeType.modified:
        return 'MODIFIED';
      case ChangeType.unchanged:
        return 'UNCHANGED';
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'tracks':
        return Icons.queue_music;
      case 'clips':
        return Icons.library_music;
      case 'plugins':
        return Icons.extension;
      case 'mix':
        return Icons.tune;
      case 'automation':
        return Icons.show_chart;
      case 'markers':
        return Icons.bookmark;
      case 'settings':
        return Icons.settings;
      default:
        return Icons.folder;
    }
  }
}
