// HELIX dock — Cloud Sync panel (Sprint 15 Faza 4.C split #6).
//
// Provider selector (Firebase/AWS/Custom), auth status, project list
// with sync/download, upload current, sync all, auto-sync toggle,
// progress tracking.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _CloudSyncPanel(State) — root widget + sync orchestrator
//   • _CloudStatusRow         — status row helper

part of '../../helix_screen.dart';// ── 3.6 Cloud Sync Panel ────────────────────────────────────────────────────

class _CloudSyncPanel extends StatefulWidget {
  const _CloudSyncPanel();
  @override
  State<_CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<_CloudSyncPanel> {
  bool _autoSyncEnabled = false;

  CloudSyncService get _cloud => CloudSyncService.instance;

  @override
  void initState() {
    super.initState();
    _cloud.init().catchError((_) {});
    _cloud.addListener(_onCloudChanged);
  }

  @override
  void dispose() {
    _cloud.removeListener(_onCloudChanged);
    super.dispose();
  }

  void _onCloudChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Connection status
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('CLOUD STATUS', color: FluxForgeTheme.accentBlue),
                const SizedBox(height: 8),
                _CloudStatusRow('Provider', _cloud.provider.name.toUpperCase()),
                _CloudStatusRow('Status', _cloud.status.name.toUpperCase()),
                _CloudStatusRow('Authenticated', _cloud.isAuthenticated ? 'YES' : 'NO'),
                _CloudStatusRow('User', _cloud.userEmail ?? 'N/A'),
                _CloudStatusRow('Last Sync', _cloud.lastSyncTime?.toString().substring(0, 19) ?? 'Never'),
                const SizedBox(height: 12),
                // Provider selector
                _DockLabel('PROVIDER', color: FluxForgeTheme.accentBlue),
                const SizedBox(height: 6),
                Row(children: CloudProvider.values.map((p) => GestureDetector(
                  onTap: () async {
                    await silentCatchAsync('cloud.setProvider', () => _cloud.setProvider(p));
                    if (mounted) setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: _cloud.provider == p ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _cloud.provider == p ? FluxForgeTheme.accentBlue.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle),
                    ),
                    child: Text(p.name.toUpperCase(), style: FluxForgeTheme.dockMono(size: 8,
                      color: _cloud.provider == p ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
                      weight: FontWeight.w600)),
                  ),
                )).toList()),
                const Spacer(),
                // Auto-sync toggle
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _autoSyncEnabled = !_autoSyncEnabled;
                      if (_autoSyncEnabled) {
                        _cloud.enableAutoSync();
                      } else {
                        _cloud.disableAutoSync();
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _autoSyncEnabled
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                        : FluxForgeTheme.bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _autoSyncEnabled
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                        : FluxForgeTheme.borderSubtle),
                    ),
                    child: Row(children: [
                      Icon(_autoSyncEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                        size: 13, color: _autoSyncEnabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary),
                      const SizedBox(width: 7),
                      Text('Auto-Sync ${_autoSyncEnabled ? "ON" : "OFF"}',
                        style: FluxForgeTheme.dockMono(size: 9,
                          weight: _autoSyncEnabled ? FontWeight.w600 : FontWeight.w400,
                          color: _autoSyncEnabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Center: Projects list
        Expanded(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DockLabel('CLOUD PROJECTS', color: FluxForgeTheme.accentBlue),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await silentCatchAsync('cloud.uploadProject', () async {
                        final proj = GetIt.instance<SlotLabProjectProvider>();
                        await _cloud.uploadProject('.', name: proj.projectName);
                      });
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_upload_rounded, size: 12, color: FluxForgeTheme.accentBlue),
                        const SizedBox(width: 4),
                        Text('UPLOAD', style: FluxForgeTheme.dockMono(size: 8,
                          color: FluxForgeTheme.accentBlue, weight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      await silentCatchAsync('cloud.syncAllProjects', () => _cloud.syncAllProjects());
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.sync_rounded, size: 12, color: FluxForgeTheme.accentGreen),
                        const SizedBox(width: 4),
                        Text('SYNC ALL', style: FluxForgeTheme.dockMono(size: 8,
                          color: FluxForgeTheme.accentGreen, weight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: _cloud.projects.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.cloud_off_rounded, size: 36, color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15)),
                        const SizedBox(height: 10),
                        Text('No cloud projects', style: FluxForgeTheme.dockMono(
                          size: 11, color: FluxForgeTheme.textTertiary)),
                        const SizedBox(height: 4),
                        Text('Upload a project to start syncing',
                          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6))),
                      ]))
                    : ListView.builder(
                        itemCount: _cloud.projects.length,
                        itemBuilder: (_, i) {
                          final p = _cloud.projects[i];
                          return Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.bgSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: FluxForgeTheme.borderSubtle),
                            ),
                            child: Row(children: [
                              const Icon(Icons.folder_rounded, size: 16, color: FluxForgeTheme.accentBlue),
                              const SizedBox(width: 8),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: FluxForgeTheme.dockMono(size: 10,
                                    color: FluxForgeTheme.textPrimary, weight: FontWeight.w600)),
                                  Text('ID: ${p.id}  Updated: ${p.updatedAt.toString().substring(0, 16)}',
                                    style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary)),
                                ],
                              )),
                              GestureDetector(
                                onTap: () async {
                                  await silentCatchAsync('cloud.syncProject', () => _cloud.syncProject(p.id));
                                  if (mounted) setState(() {});
                                },
                                child: const Icon(Icons.sync_rounded, size: 14, color: FluxForgeTheme.accentCyan),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  await silentCatchAsync('cloud.downloadProject', () => _cloud.downloadProject(p.id));
                                  if (mounted) setState(() {});
                                },
                                child: const Icon(Icons.cloud_download_rounded, size: 14, color: FluxForgeTheme.accentGreen),
                              ),
                            ]),
                          );
                        },
                      ),
                ),
                // Progress bar during sync
                if (_cloud.isSyncing) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _cloud.progress,
                    backgroundColor: FluxForgeTheme.bgSurface,
                    valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentBlue),
                  ),
                  const SizedBox(height: 4),
                  Text(_cloud.currentOperation ?? 'Syncing...',
                    style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CloudStatusRow extends StatelessWidget {
  final String label;
  final String value;
  const _CloudStatusRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label,
        style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary))),
      Expanded(child: Text(value,
        style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary),
        overflow: TextOverflow.ellipsis)),
    ]),
  );
}
