import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../models/aurexis_audit.dart';
import '../../providers/aurexis_audit_provider.dart';
import 'aurexis_theme.dart';

/// AUREXIS™ Audit Trail Widget.
///
/// Shows a scrollable log of all AUREXIS operations with
/// type/severity filters and JSON export.
class AuditTrailWidget extends StatefulWidget {
  const AuditTrailWidget({super.key});

  @override
  State<AuditTrailWidget> createState() => _AuditTrailWidgetState();
}

class _AuditTrailWidgetState extends State<AuditTrailWidget> {
  late final AurexisAuditProvider _audit;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _audit = GetIt.instance<AurexisAuditProvider>();
    _audit.addListener(_onAuditUpdate);
  }

  @override
  void dispose() {
    _audit.removeListener(_onAuditUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onAuditUpdate() {
    if (mounted) {
      setState(() {});
      if (_autoScroll && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AurexisColors.bgSection,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          _buildFilterBar(),
          _buildEntryList(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AurexisColors.bgSectionHeader,
        border: Border(
          bottom: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'AUDIT TRAIL',
            style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 9),
          ),
          const SizedBox(width: 6),
          // Entry count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AurexisColors.bgInput,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '${_audit.totalCount}',
              style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel),
            ),
          ),
          // Warning/critical counts
          if (_audit.warningCount > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AurexisColors.fatigueModerate.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '${_audit.warningCount}W',
                style: AurexisTextStyles.badge.copyWith(
                  color: AurexisColors.fatigueModerate,
                  fontSize: 7,
                ),
              ),
            ),
          ],
          if (_audit.criticalCount > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AurexisColors.fatigueCritical.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '${_audit.criticalCount}C',
                style: AurexisTextStyles.badge.copyWith(
                  color: AurexisColors.fatigueCritical,
                  fontSize: 7,
                ),
              ),
            ),
          ],
          const Spacer(),
          // Recording toggle
          GestureDetector(
            onTap: _audit.toggleRecording,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _audit.recording
                    ? AurexisColors.fatigueCritical
                    : AurexisColors.textLabel,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _audit.recording ? 'REC' : 'PAUSED',
            style: AurexisTextStyles.badge.copyWith(
              color: _audit.recording
                  ? AurexisColors.fatigueCritical
                  : AurexisColors.textLabel,
              fontSize: 7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Type filter
          _buildFilterChip(
            label: _audit.filterType?.label ?? 'All',
            active: _audit.filterType != null,
            onTap: _showTypeFilter,
          ),
          const SizedBox(width: 4),
          // Severity filter
          _buildFilterChip(
            label: _audit.filterSeverity?.label ?? 'All Sev',
            active: _audit.filterSeverity != null,
            onTap: _showSeverityFilter,
          ),
          const Spacer(),
          // Auto-scroll toggle
          GestureDetector(
            onTap: () => setState(() => _autoScroll = !_autoScroll),
            child: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              size: 12,
              color: _autoScroll ? AurexisColors.accent : AurexisColors.textLabel,
            ),
          ),
          const SizedBox(width: 6),
          // Clear filters
          if (_audit.filterType != null || _audit.filterSeverity != null)
            GestureDetector(
              onTap: _audit.clearFilters,
              child: Icon(Icons.filter_alt_off, size: 12, color: AurexisColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active
              ? AurexisColors.accent.withValues(alpha: 0.1)
              : AurexisColors.bgInput,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? AurexisColors.accent : AurexisColors.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AurexisTextStyles.badge.copyWith(
            color: active ? AurexisColors.accent : AurexisColors.textSecondary,
            fontSize: 7,
          ),
        ),
      ),
    );
  }

  Widget _buildEntryList() {
    final entries = _audit.filteredEntries;

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _audit.totalCount == 0
                ? 'No audit entries yet'
                : 'No entries match filters',
            style: AurexisTextStyles.paramLabel.copyWith(
              color: AurexisColors.textLabel,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        itemCount: entries.length,
        itemBuilder: (context, index) => _buildEntryRow(entries[index]),
      ),
    );
  }

  Widget _buildEntryRow(AuditEntry entry) {
    final severityColor = switch (entry.severity) {
      AuditSeverity.info => AurexisColors.textLabel,
      AuditSeverity.warning => AurexisColors.fatigueModerate,
      AuditSeverity.critical => AurexisColors.fatigueCritical,
    };

    final actionColor = switch (entry.action) {
      AuditActionType.profileChange => AurexisColors.spatial,
      AuditActionType.behaviorChange => AurexisColors.dynamics,
      AuditActionType.jurisdictionChange => AurexisColors.fatigueCritical,
      AuditActionType.complianceCheck => AurexisColors.fatigueFresh,
      AuditActionType.cabinetChange => AurexisColors.music,
      AuditActionType.engineLifecycle => AurexisColors.accent,
      AuditActionType.configPush => AurexisColors.variation,
      AuditActionType.abComparison => AurexisColors.spatial,
      AuditActionType.reThemeApply => AurexisColors.variation,
      AuditActionType.platformChange => AurexisColors.music,
      AuditActionType.customProfileOp => AurexisColors.spatial,
      AuditActionType.sessionMarker => AurexisColors.textSecondary,
    };

    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AurexisColors.borderSubtle, width: 0.25),
        ),
      ),
      child: Row(
        children: [
          // Timestamp
          Text(
            time,
            style: AurexisTextStyles.badge.copyWith(
              color: AurexisColors.textLabel,
              fontSize: 7,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          // Severity dot
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: severityColor,
            ),
          ),
          const SizedBox(width: 4),
          // Action type badge
          Container(
            width: 20,
            alignment: Alignment.center,
            child: Text(
              entry.action.icon,
              style: AurexisTextStyles.badge.copyWith(
                color: actionColor,
                fontSize: 7,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Description
          Expanded(
            child: Text(
              entry.description,
              style: AurexisTextStyles.badge.copyWith(
                color: AurexisColors.textPrimary,
                fontSize: 8,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          // Entry ID
          Text(
            '#${entry.id}',
            style: AurexisTextStyles.badge.copyWith(
              color: AurexisColors.textLabel,
              fontSize: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Session ID
          Text(
            _audit.session.sessionId.substring(0, 20),
            style: AurexisTextStyles.badge.copyWith(
              color: AurexisColors.textLabel,
              fontSize: 6,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          // Export JSON
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _audit.exportJson()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audit trail copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AurexisColors.bgInput,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy, size: 10, color: AurexisColors.textSecondary),
                  const SizedBox(width: 2),
                  Text('Export', style: AurexisTextStyles.badge.copyWith(fontSize: 7)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Clear
          GestureDetector(
            onTap: _audit.clearAndRestart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AurexisColors.bgInput,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
              ),
              child: Text('Clear', style: AurexisTextStyles.badge.copyWith(fontSize: 7)),
            ),
          ),
        ],
      ),
    );
  }

  void _showTypeFilter() {
    final types = [null, ...AuditActionType.values];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AurexisColors.bgSection,
        title: Text('Filter by Type', style: TextStyle(color: AurexisColors.textPrimary, fontSize: 12)),
        children: types.map((t) {
          return SimpleDialogOption(
            onPressed: () {
              _audit.setFilterType(t);
              Navigator.pop(ctx);
            },
            child: Text(
              t?.label ?? 'All',
              style: TextStyle(
                color: t == _audit.filterType ? AurexisColors.accent : AurexisColors.textPrimary,
                fontSize: 11,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showSeverityFilter() {
    final severities = [null, ...AuditSeverity.values];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AurexisColors.bgSection,
        title: Text('Filter by Severity', style: TextStyle(color: AurexisColors.textPrimary, fontSize: 12)),
        children: severities.map((s) {
          return SimpleDialogOption(
            onPressed: () {
              _audit.setFilterSeverity(s);
              Navigator.pop(ctx);
            },
            child: Text(
              s?.label ?? 'All',
              style: TextStyle(
                color: s == _audit.filterSeverity ? AurexisColors.accent : AurexisColors.textPrimary,
                fontSize: 11,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
