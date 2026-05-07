/// ChainPresetLibraryPanel — user-owned chain preset browser & manager.
///
/// Wave 2 Front 5 frontend. Pairs with the Rust `chain_preset_ffi` layer
/// (`crates/rf-bridge/src/chain_preset_ffi.rs`) and the Dart
/// `ChainPresetService` to expose the on-disk preset library
/// (`~/.fluxforge/chains/`) through a search/filter/save/load/delete
/// surface.
///
/// Designed to be shown as a modal sheet from the FX Chain panel:
///
/// ```dart
/// await ChainPresetLibraryPanel.show(
///   context,
///   trackId: 7,
///   captureCurrentChain: () => /* FullChainSnapshot from engine */,
///   onApplyPreset: (preset) async { /* push snapshot to engine */ },
/// );
/// ```
///
/// Visual language follows `chain_history_bar.dart` (purple accent, dark
/// `#1A1A22` bg) to feel like one family with the rest of the chain UI.
library;

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chain_preset.dart';
import '../../services/chain_preset_service.dart';

// ─── Colors (match chain_history_bar.dart) ──────────────────────────────────

const _kAccent = Color(0xFF7B5EA7);
const _kAccentSoft = Color(0xFF5A4280);
const _kBg = Color(0xFF1A1A22);
const _kBgRaised = Color(0xFF22222E);
const _kBorder = Color(0x14FFFFFF);
const _kBorderStrong = Color(0x2EFFFFFF);
const _kFg = Color(0xFFE6E6F0);
const _kFgDim = Color(0xFF8E8EA0);
const _kDanger = Color(0xFFE25C5C);
const _kSuccess = Color(0xFF4CAF87);

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════

class ChainPresetLibraryPanel extends StatefulWidget {
  /// Track the user is currently editing — used as the snapshot owner
  /// when saving a new preset.
  final int trackId;

  /// Capture the current engine chain on demand. Required for the
  /// "Save current as preset" flow. Return null if no chain is active.
  final FullChainSnapshot? Function() captureCurrentChain;

  /// Apply a loaded preset to the engine. The host is responsible for
  /// translating `FullChainSnapshot` → engine plan + `chain_apply_*` call.
  /// Returns a short message for the toast (success or error).
  final Future<String> Function(ChainPreset preset) onApplyPreset;

  const ChainPresetLibraryPanel({
    super.key,
    required this.trackId,
    required this.captureCurrentChain,
    required this.onApplyPreset,
  });

  /// Show the panel as a centered modal. Returns when the user dismisses.
  static Future<void> show(
    BuildContext context, {
    required int trackId,
    required FullChainSnapshot? Function() captureCurrentChain,
    required Future<String> Function(ChainPreset) onApplyPreset,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: ChainPresetLibraryPanel(
          trackId: trackId,
          captureCurrentChain: captureCurrentChain,
          onApplyPreset: onApplyPreset,
        ),
      ),
    );
  }

  @override
  State<ChainPresetLibraryPanel> createState() =>
      _ChainPresetLibraryPanelState();
}

class _ChainPresetLibraryPanelState extends State<ChainPresetLibraryPanel> {
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Currently filtered metadata. Updated either from the cached service
  /// list (empty query) or from a search() call (non-empty query).
  List<ChainPresetMeta> _filtered = const [];

  /// Most recent transient status message, shown in the footer. Null = no
  /// message. Cleared after a few seconds.
  String? _toast;
  bool _toastIsError = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onQueryChanged);
    // Kick off async refresh + initial paint with whatever's cached.
    _filtered = ChainPresetService.instance.presets;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ChainPresetService.instance.refresh();
      if (mounted) {
        setState(() {
          _filtered = ChainPresetService.instance.presets;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtl.removeListener(_onQueryChanged);
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _onQueryChanged() async {
    final q = _searchCtl.text;
    if (q.trim().isEmpty) {
      setState(() {
        _filtered = ChainPresetService.instance.presets;
      });
      return;
    }
    final results = await ChainPresetService.instance.search(q);
    if (!mounted) return;
    setState(() {
      _filtered = results;
    });
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _toast = message;
      _toastIsError = isError;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      // Only clear if the message hasn't been replaced.
      if (_toast == message) {
        setState(() => _toast = null);
      }
    });
  }

  // ─── Actions ───────────────────────────────────────────────────────────

  Future<void> _saveCurrentChain() async {
    final snapshot = widget.captureCurrentChain();
    if (snapshot == null || snapshot.slots.isEmpty) {
      _showToast('Nema aktivnog chain-a — dodaj barem jedan slot pre snimanja.',
          isError: true);
      return;
    }
    final entry = await _showSaveDialog();
    if (entry == null) return;
    setState(() => _busy = true);
    final result = await ChainPresetService.instance.save(
      name: entry.name,
      description: entry.description,
      tags: entry.tags,
      snapshot: snapshot,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _filtered = ChainPresetService.instance.presets;
    });
    if (result.ok) {
      _showToast('Snimljeno: ${result.name}');
    } else {
      _showToast('Greška pri snimanju: ${result.error ?? "nepoznato"}',
          isError: true);
    }
  }

  Future<void> _applyPreset(ChainPresetMeta meta) async {
    setState(() => _busy = true);
    final preset = await ChainPresetService.instance.load(meta.name);
    if (!mounted) return;
    if (preset == null) {
      setState(() => _busy = false);
      _showToast(
          'Greška pri učitavanju: ${ChainPresetService.instance.lastError ?? "nepoznato"}',
          isError: true);
      return;
    }
    final hostMessage = await widget.onApplyPreset(preset);
    if (!mounted) return;
    setState(() => _busy = false);
    _showToast(hostMessage);
  }

  Future<void> _deletePreset(ChainPresetMeta meta) async {
    final confirmed = await _confirmDelete(meta.name);
    if (confirmed != true) return;
    setState(() => _busy = true);
    final outcome = await ChainPresetService.instance.delete(meta.name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _filtered = ChainPresetService.instance.presets;
    });
    switch (outcome) {
      case ChainPresetDeleteResult.removed:
        _showToast('Obrisano: ${meta.name}');
      case ChainPresetDeleteResult.notFound:
        _showToast('Već obrisan: ${meta.name}');
      case ChainPresetDeleteResult.error:
        _showToast(
            'Greška pri brisanju: ${ChainPresetService.instance.lastError ?? "nepoznato"}',
            isError: true);
    }
  }

  Future<void> _exportPreset(ChainPresetMeta meta) async {
    final destPath = await _promptForPath(
      title: 'Export preset',
      hint: '/Users/.../my_preset.json',
      initialValue:
          '${ChainPresetService.instance.resolvedDir}/${meta.filename}',
    );
    if (destPath == null) return;
    setState(() => _busy = true);
    final result = await ChainPresetService.instance.exportTo(
      name: meta.name,
      destPath: destPath,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      _showToast('Exportovano u: ${result.path}');
    } else {
      _showToast('Greška pri export-u: ${result.error ?? "nepoznato"}',
          isError: true);
    }
  }

  Future<void> _importPreset() async {
    final sourcePath = await _promptForPath(
      title: 'Import preset',
      hint: '/Users/.../shared_preset.json',
      initialValue: '',
    );
    if (sourcePath == null) return;
    if (!await File(sourcePath).exists()) {
      _showToast('Fajl ne postoji: $sourcePath', isError: true);
      return;
    }
    setState(() => _busy = true);
    final result = await ChainPresetService.instance.importFrom(sourcePath);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _filtered = ChainPresetService.instance.presets;
    });
    if (result.ok) {
      _showToast('Importovano: ${result.name}');
    } else {
      _showToast('Greška pri import-u: ${result.error ?? "nepoznato"}',
          isError: true);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChainPresetService.instance,
      builder: (context, _) {
        // Service notification → re-resolve filtered list with current query.
        // The service mutates its cached list under the hood; if no query is
        // active, just adopt it. Non-empty query: leave _filtered alone — it
        // was set by the last search() call.
        if (_searchCtl.text.trim().isEmpty) {
          _filtered = ChainPresetService.instance.presets;
        }

        return Container(
          width: 720,
          height: 560,
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorderStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              _buildSearchBar(),
              const Divider(height: 1, color: _kBorder),
              Expanded(child: _buildList()),
              const Divider(height: 1, color: _kBorder),
              _buildFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final dir = ChainPresetService.instance.resolvedDir;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.library_music, size: 18, color: _kAccent),
          const SizedBox(width: 8),
          const Text(
            'Chain Preset Library',
            style: TextStyle(
              color: _kFg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 12),
          if (dir.isNotEmpty)
            Expanded(
              child: Tooltip(
                message: dir,
                child: Text(
                  dir,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kFgDim, fontSize: 11),
                ),
              ),
            )
          else
            const Spacer(),
          IconButton(
            tooltip: 'Zatvori',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: _kFgDim,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchCtl,
                focusNode: _searchFocus,
                style: const TextStyle(color: _kFg, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search,
                      size: 16, color: _kFgDim),
                  hintText: 'Pretraga (ime, opis, tag)…',
                  hintStyle: const TextStyle(color: _kFgDim, fontSize: 12),
                  filled: true,
                  fillColor: _kBgRaised,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _kAccent, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PrimaryButton(
            label: 'Snimi trenutno',
            icon: Icons.save_outlined,
            onPressed: _busy ? null : _saveCurrentChain,
          ),
          const SizedBox(width: 6),
          _SecondaryButton(
            label: 'Import',
            icon: Icons.file_download_outlined,
            onPressed: _busy ? null : _importPreset,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 36, color: _kFgDim),
            const SizedBox(height: 10),
            Text(
              _searchCtl.text.trim().isEmpty
                  ? 'Biblioteka je prazna — snimite svoj prvi chain.'
                  : 'Nema rezultata za "${_searchCtl.text}".',
              style: const TextStyle(color: _kFgDim, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) => _PresetRow(
        meta: _filtered[i],
        busy: _busy,
        onApply: () => _applyPreset(_filtered[i]),
        onDelete: () => _deletePreset(_filtered[i]),
        onExport: () => _exportPreset(_filtered[i]),
      ),
    );
  }

  Widget _buildFooter() {
    final total = ChainPresetService.instance.presets.length;
    final visible = _filtered.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$visible / $total preseta',
            style: const TextStyle(color: _kFgDim, fontSize: 11),
          ),
          const SizedBox(width: 16),
          if (_toast != null)
            Expanded(
              child: Text(
                _toast!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _toastIsError ? _kDanger : _kSuccess,
                  fontSize: 11,
                ),
              ),
            )
          else
            const Spacer(),
          if (_busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: _kAccent),
            ),
        ],
      ),
    );
  }

  // ─── Sub-dialogs ───────────────────────────────────────────────────────

  Future<_SaveEntry?> _showSaveDialog() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final tagsCtl = TextEditingController();
    return showDialog<_SaveEntry>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _kBorderStrong),
        ),
        child: SizedBox(
          width: 420,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Snimi chain kao preset',
                  style: TextStyle(
                      color: _kFg, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                _DialogField(
                  label: 'Ime *',
                  controller: nameCtl,
                  hint: 'My Vocal Master',
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                _DialogField(
                  label: 'Opis',
                  controller: descCtl,
                  hint: 'Bright, transparent',
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                _DialogField(
                  label: 'Tagovi (zarezima razdvojeni)',
                  controller: tagsCtl,
                  hint: 'vocal, modern',
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Otkaži',
                          style: TextStyle(color: _kFgDim)),
                    ),
                    const SizedBox(width: 6),
                    _PrimaryButton(
                      label: 'Snimi',
                      onPressed: () {
                        final name = nameCtl.text.trim();
                        if (name.isEmpty) return;
                        final tags = tagsCtl.text
                            .split(',')
                            .map((t) => t.trim())
                            .where((t) => t.isNotEmpty)
                            .toList(growable: false);
                        Navigator.of(ctx).pop(
                          _SaveEntry(
                            name: name,
                            description: descCtl.text.trim(),
                            tags: tags,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _kBorderStrong),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Brisanje preseta',
                style: TextStyle(
                    color: _kFg, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Da li želite da obrišete "$name"? Ova akcija je trajna.',
                style: const TextStyle(color: _kFg, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Otkaži',
                        style: TextStyle(color: _kFgDim)),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kDanger,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    child: const Text('Obriši',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _promptForPath({
    required String title,
    required String hint,
    required String initialValue,
  }) {
    final ctl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _kBorderStrong),
        ),
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: _kFg, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                _DialogField(
                  label: 'Putanja',
                  controller: ctl,
                  hint: hint,
                  autofocus: true,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: const Text('Otkaži',
                          style: TextStyle(color: _kFgDim)),
                    ),
                    const SizedBox(width: 6),
                    _PrimaryButton(
                      label: 'OK',
                      onPressed: () {
                        final v = ctl.text.trim();
                        Navigator.of(ctx).pop(v.isEmpty ? null : v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _PresetRow extends StatelessWidget {
  final ChainPresetMeta meta;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _PresetRow({
    required this.meta,
    required this.busy,
    required this.onApply,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kBgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Name + meta column ────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          meta.name,
                          style: const TextStyle(
                            color: _kFg,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Badge(
                        text: '${meta.slotCount} slot'
                            '${meta.slotCount == 1 ? "" : "ova"}',
                      ),
                    ],
                  ),
                  if (meta.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta.description,
                      style: const TextStyle(color: _kFgDim, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (meta.tags.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children:
                          meta.tags.map((t) => _Tag(text: t)).toList(),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(meta.updatedMs),
                    style: const TextStyle(
                        color: _kFgDim, fontSize: 10, height: 1.2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Actions ───────────────────────────────────────────────
            _PrimaryButton(
              label: 'Apply',
              icon: Icons.play_arrow,
              onPressed: busy ? null : onApply,
              compact: true,
            ),
            const SizedBox(width: 4),
            _IconButton(
              tooltip: 'Export',
              icon: Icons.upload_outlined,
              onPressed: busy ? null : onExport,
            ),
            _IconButton(
              tooltip: 'Obriši',
              icon: Icons.delete_outline,
              danger: true,
              onPressed: busy ? null : onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTimestamp(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'upravo';
    if (diff.inMinutes < 60) return 'pre ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'pre ${diff.inHours} h';
    if (diff.inDays < 7) return 'pre ${diff.inDays} d';
    return '${dt.year}-${dt.month.toString().padLeft(2, "0")}-'
        '${dt.day.toString().padLeft(2, "0")}';
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kAccentSoft.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _kFg,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _kBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _kFgDim, fontSize: 9.5),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final bool autofocus;

  const _DialogField({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: _kFgDim, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          autofocus: autofocus,
          maxLines: maxLines,
          style: const TextStyle(color: _kFg, fontSize: 12),
          inputFormatters: const <TextInputFormatter>[],
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: _kFgDim, fontSize: 11),
            filled: true,
            fillColor: _kBgRaised,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _kAccent, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;

  const _PrimaryButton({
    required this.label,
    this.icon,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _kAccentSoft.withValues(alpha: 0.4),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14, vertical: compact ? 6 : 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 14 : 15),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: compact ? 11 : 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const _SecondaryButton({
    required this.label,
    this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _kFg,
        side: BorderSide(color: _kBorderStrong),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: _kFg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  const _IconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      color: danger ? _kDanger : _kFgDim,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VALUE TYPES
// ═══════════════════════════════════════════════════════════════════════════

class _SaveEntry {
  final String name;
  final String description;
  final List<String> tags;
  const _SaveEntry({
    required this.name,
    required this.description,
    required this.tags,
  });
}
