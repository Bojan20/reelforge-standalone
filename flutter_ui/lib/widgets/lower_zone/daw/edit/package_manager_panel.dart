/// Package Manager Panel (#33)
/// 3-column UI: filters/categories | package list | package details
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../services/package_manager_service.dart';

class PackageManagerPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const PackageManagerPanel({super.key, this.onAction});

  @override
  State<PackageManagerPanel> createState() => _PackageManagerPanelState();
}

class _PackageManagerPanelState extends State<PackageManagerPanel> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    PackageManagerService.instance.loadFactoryPackages();
    _searchCtrl.addListener(() {
      PackageManagerService.instance.setSearchQuery(_searchCtrl.text);
    });
  }

  @override
  void dispose() {
    PackageManagerService.instance.setSearchQuery('');
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PackageManagerService.instance,
      builder: (context, _) {
        final svc = PackageManagerService.instance;
        final packages = svc.filteredPackages;
        final selected = svc.selectedPackage;

        return Row(
          children: [
            // Left column — Filters & Categories
            SizedBox(
              width: 200,
              child: _buildFiltersColumn(svc),
            ),
            const VerticalDivider(width: 1, color: LowerZoneColors.border),
            // Center column — Package List
            Expanded(
              child: _buildPackageList(svc, packages),
            ),
            const VerticalDivider(width: 1, color: LowerZoneColors.border),
            // Right column — Package Details
            SizedBox(
              width: 280,
              child: selected != null
                  ? _buildPackageDetails(svc, selected)
                  : _buildNoSelection(),
            ),
          ],
        );
      },
    );
  }

  // ─── Left: Filters ─────────────────────────────────────────────────────────

  Widget _buildFiltersColumn(PackageManagerService svc) {
    return Container(
      color: LowerZoneColors.bgDeepest,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, size: 14, color: LowerZoneColors.dawAccent),
                const SizedBox(width: 6),
                const Text('PACKAGES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent, letterSpacing: 1.0)),
                const Spacer(),
                _buildBadge('${svc.installedCount}', Colors.green),
                if (svc.updatesCount > 0) ...[
                  const SizedBox(width: 4),
                  _buildBadge('${svc.updatesCount}↑', Colors.orange),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: LowerZoneColors.border),

          // Status filters
          _buildFilterSection('STATUS', [
            _buildFilterChip('All', svc.filterStatus == null, () => svc.setFilterStatus(null)),
            _buildFilterChip('Installed', svc.filterStatus == PackageStatus.installed,
              () => svc.setFilterStatus(PackageStatus.installed)),
            _buildFilterChip('Available', svc.filterStatus == PackageStatus.available,
              () => svc.setFilterStatus(PackageStatus.available)),
            _buildFilterChip('Updates', svc.filterStatus == PackageStatus.updateAvailable,
              () => svc.setFilterStatus(PackageStatus.updateAvailable)),
          ]),

          // Type filters
          _buildFilterSection('TYPE', [
            _buildFilterChip('All', svc.filterType == null, () => svc.setFilterType(null)),
            ...PackageType.values.map((t) =>
              _buildFilterChip(t.label, svc.filterType == t, () => svc.setFilterType(t)),
            ),
          ]),

          // Source filters
          _buildFilterSection('SOURCE', [
            _buildFilterChip('All', svc.filterSource == null, () => svc.setFilterSource(null)),
            ...PackageSource.values.map((s) =>
              _buildFilterChip(s.label, svc.filterSource == s, () => svc.setFilterSource(s)),
            ),
          ]),

          const SizedBox(height: 16),

          // Repositories section
          Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REPOSITORIES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                  color: LowerZoneColors.textMuted, letterSpacing: 1.0)),
                const SizedBox(height: 6),
                ...svc.repositories.map((repo) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(repo.enabled ? Icons.check_circle : Icons.cancel,
                        size: 10, color: repo.enabled ? Colors.green : LowerZoneColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(child: Text(repo.name, style: TextStyle(fontSize: 9,
                        color: repo.enabled ? LowerZoneColors.textSecondary : LowerZoneColors.textMuted),
                        overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                )),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => svc.syncRepositories(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync, size: 10, color: LowerZoneColors.textSecondary),
                        SizedBox(width: 4),
                        Text('Sync All', style: TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(String title, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
            color: LowerZoneColors.textMuted, letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: chips),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? LowerZoneColors.dawAccent.withValues(alpha: 0.2) : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? LowerZoneColors.dawAccent : LowerZoneColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 9, fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          color: active ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary)),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
    );
  }

  // ─── Center: Package List ──────────────────────────────────────────────────

  Widget _buildPackageList(PackageManagerService svc, List<Package> packages) {
    return Column(
      children: [
        // Search + Sort bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: LowerZoneColors.bgMid,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search packages...',
                      hintStyle: const TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
                      prefixIcon: const Icon(Icons.search, size: 14, color: LowerZoneColors.textMuted),
                      filled: true,
                      fillColor: LowerZoneColors.bgDeepest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: LowerZoneColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: LowerZoneColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: LowerZoneColors.dawAccent)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Sort dropdown
              PopupMenuButton<PackageSortOrder>(
                tooltip: 'Sort',
                offset: const Offset(0, 30),
                color: LowerZoneColors.bgMid,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: LowerZoneColors.border)),
                onSelected: (order) => svc.setSortOrder(order),
                itemBuilder: (context) => PackageSortOrder.values.map((o) => PopupMenuItem(
                  value: o,
                  child: Row(
                    children: [
                      if (o == svc.sortOrder) const Icon(Icons.check, size: 12, color: LowerZoneColors.dawAccent)
                      else const SizedBox(width: 12),
                      const SizedBox(width: 6),
                      Text(o.label, style: const TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary)),
                    ],
                  ),
                )).toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 12, color: LowerZoneColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(svc.sortOrder.label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${packages.length} packages', style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
            ],
          ),
        ),
        const Divider(height: 1, color: LowerZoneColors.border),

        // Package list
        Expanded(
          child: packages.isEmpty
            ? const Center(child: Text('No packages found', style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted)))
            : ListView.builder(
                itemCount: packages.length,
                itemBuilder: (context, index) => _buildPackageRow(svc, packages[index]),
              ),
        ),
      ],
    );
  }

  Widget _buildPackageRow(PackageManagerService svc, Package pkg) {
    final isSelected = svc.selectedPackageId == pkg.id;
    return GestureDetector(
      onTap: () => svc.selectPackage(pkg.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : null,
          border: Border(bottom: BorderSide(color: LowerZoneColors.border.withValues(alpha: 0.3))),
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _typeColor(pkg.type).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(_typeIcon(pkg.type), size: 16, color: _typeColor(pkg.type)),
            ),
            const SizedBox(width: 10),
            // Name + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(pkg.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textPrimary),
                          overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Text('v${pkg.version}', style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                      if (pkg.isBuiltIn) ...[
                        const SizedBox(width: 4),
                        _buildBadge('Built-in', LowerZoneColors.textMuted),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(pkg.description, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Rating
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, size: 10, color: pkg.rating >= 4.0 ? Colors.amber : LowerZoneColors.textMuted),
                const SizedBox(width: 2),
                Text(pkg.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary)),
              ],
            ),
            const SizedBox(width: 12),
            // Status / Action button
            _buildStatusButton(svc, pkg),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton(PackageManagerService svc, Package pkg) {
    switch (pkg.status) {
      case PackageStatus.installed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: const Text('Installed', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.green)),
        );
      case PackageStatus.updateAvailable:
        return GestureDetector(
          onTap: () => svc.updatePackage(pkg.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: const Text('Update', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.orange)),
          ),
        );
      case PackageStatus.available:
        return GestureDetector(
          onTap: () => svc.installPackage(pkg.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: LowerZoneColors.dawAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.dawAccent.withValues(alpha: 0.3)),
            ),
            child: const Text('Install', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: LowerZoneColors.dawAccent)),
          ),
        );
      case PackageStatus.installing:
      case PackageStatus.uninstalling:
        return SizedBox(
          width: 60,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
              const SizedBox(width: 4),
              Text(pkg.status.label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
            ],
          ),
        );
    }
  }

  // ─── Right: Package Details ────────────────────────────────────────────────

  Widget _buildPackageDetails(PackageManagerService svc, Package pkg) {
    return Container(
      color: LowerZoneColors.bgDeepest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _typeColor(pkg.type).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcon(pkg.type), size: 22, color: _typeColor(pkg.type)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pkg.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                        color: LowerZoneColors.textPrimary)),
                      Text('by ${pkg.author}', style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                if (!pkg.isInstalled)
                  _buildActionButton('Install', Icons.download, LowerZoneColors.dawAccent,
                    () => svc.installPackage(pkg.id))
                else if (pkg.hasUpdate)
                  _buildActionButton('Update to v${pkg.version}', Icons.upgrade, Colors.orange,
                    () => svc.updatePackage(pkg.id))
                else
                  _buildActionButton('Installed', Icons.check_circle, Colors.green, null),
                if (pkg.isInstalled && !pkg.isBuiltIn) ...[
                  const SizedBox(width: 6),
                  _buildActionButton('Uninstall', Icons.delete_outline, Colors.red,
                    () => svc.uninstallPackage(pkg.id)),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Description
            Text(pkg.description, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary, height: 1.4)),
            const SizedBox(height: 16),

            // Info grid
            _buildInfoRow('Version', pkg.isInstalled && pkg.installedVersion != null
              ? '${pkg.installedVersion} → ${pkg.version}' : pkg.version),
            _buildInfoRow('Type', pkg.type.label),
            _buildInfoRow('Source', pkg.source.label),
            _buildInfoRow('Size', pkg.sizeLabel),
            _buildInfoRow('Downloads', _formatNumber(pkg.downloads)),
            if (pkg.license != null) _buildInfoRow('License', pkg.license!),
            const SizedBox(height: 12),

            // Rating
            Row(
              children: [
                ...List.generate(5, (i) => Icon(
                  i < pkg.rating.floor() ? Icons.star : (i < pkg.rating.ceil() ? Icons.star_half : Icons.star_border),
                  size: 14, color: Colors.amber)),
                const SizedBox(width: 6),
                Text('${pkg.rating.toStringAsFixed(1)} / 5.0', style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 12),

            // Tags
            if (pkg.tags.isNotEmpty) ...[
              const Text('TAGS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                color: LowerZoneColors.textMuted, letterSpacing: 1.0)),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4,
                children: pkg.tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(t, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textSecondary)),
                )).toList(),
              ),
            ],

            // Dependencies
            if (pkg.dependencies.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('DEPENDENCIES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                color: LowerZoneColors.textMuted, letterSpacing: 1.0)),
              const SizedBox(height: 6),
              ...pkg.dependencies.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.subdirectory_arrow_right, size: 10, color: LowerZoneColors.textMuted),
                    const SizedBox(width: 4),
                    Text(d, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary)),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoSelection() {
    return Container(
      color: LowerZoneColors.bgDeepest,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2, size: 32, color: LowerZoneColors.textMuted),
            SizedBox(height: 8),
            Text('Select a package', style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted)),
            SizedBox(height: 4),
            Text('to view details', style: TextStyle(fontSize: 9, color: LowerZoneColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: onTap != null ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80,
            child: Text(label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500,
            color: LowerZoneColors.textPrimary))),
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  IconData _typeIcon(PackageType type) => switch (type) {
    PackageType.dspScript => Icons.code,
    PackageType.effect => Icons.auto_fix_high,
    PackageType.theme => Icons.palette,
    PackageType.preset => Icons.tune,
    PackageType.template => Icons.dashboard_customize,
    PackageType.extension => Icons.extension,
  };

  Color _typeColor(PackageType type) => switch (type) {
    PackageType.dspScript => const Color(0xFF4EC9B0),
    PackageType.effect => const Color(0xFF569CD6),
    PackageType.theme => const Color(0xFFC586C0),
    PackageType.preset => const Color(0xFFDCDCAA),
    PackageType.template => const Color(0xFF4FC1FF),
    PackageType.extension => const Color(0xFFCE9178),
  };

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
