/// Symbol Art Panel — Artwork import & assignment for slot symbols
///
/// Allows users to:
/// - Browse & assign artwork images (PNG/JPG/WebP) to each symbol
/// - Preview artwork in symbol cells with shape clipping
/// - Clear artwork to revert to gradient+text fallback
/// - Bulk import from folder
///
/// Reads symbols from SlotLabProjectProvider, writes artworkPath per symbol.
/// Runtime sync: artworkPath propagates to SlotSymbol.imagePath via registry.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/slot_lab_project_provider.dart';
import '../../models/slot_lab_models.dart';
import '../../services/native_file_picker.dart';
import 'slot_preview_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYMBOL ART PANEL
// ═══════════════════════════════════════════════════════════════════════════

class SymbolArtPanel extends StatelessWidget {
  const SymbolArtPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, projectProvider, _) {
        final symbols = projectProvider.symbols;
        if (symbols.isEmpty) {
          return const Center(
            child: Text('No symbols defined',
                style: TextStyle(color: Color(0xFF888888), fontSize: 11)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(context, projectProvider, symbols),
            const Divider(height: 1, color: Color(0xFF2A2A38)),
            // Mini-reel preview
            _buildMiniReelPreview(symbols),
            const Divider(height: 1, color: Color(0xFF2A2A38)),
            // Symbol list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: symbols.length,
                itemBuilder: (context, index) =>
                    _buildSymbolRow(context, projectProvider, symbols[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, SlotLabProjectProvider provider,
      List<SymbolDefinition> symbols) {
    final assignedCount =
        symbols.where((s) => s.artworkPath != null && s.artworkPath!.isNotEmpty).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFF1A1A2E),
      child: Row(
        children: [
          const Icon(Icons.palette, size: 14, color: Color(0xFF00BCD4)),
          const SizedBox(width: 6),
          Text(
            'SYMBOL ART',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.9),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: assignedCount > 0
                  ? const Color(0xFF00BCD4).withOpacity(0.2)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$assignedCount/${symbols.length}',
              style: TextStyle(
                fontSize: 9,
                color: assignedCount > 0
                    ? const Color(0xFF00BCD4)
                    : const Color(0xFF888888),
              ),
            ),
          ),
          const Spacer(),
          // Bulk import button
          _HeaderButton(
            icon: Icons.folder_open,
            label: 'FOLDER',
            onTap: () => _bulkImportFromFolder(context, provider),
          ),
          const SizedBox(width: 4),
          // Clear all button
          if (assignedCount > 0)
            _HeaderButton(
              icon: Icons.clear_all,
              label: 'CLEAR',
              color: const Color(0xFFFF5252),
              onTap: () => _clearAllArtwork(context, provider),
            ),
        ],
      ),
    );
  }

  Widget _buildSymbolRow(BuildContext context, SlotLabProjectProvider provider,
      SymbolDefinition symbol) {
    final hasArt = symbol.artworkPath != null && symbol.artworkPath!.isNotEmpty;
    final typeColor = _colorForType(symbol.type);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasArt
              ? const Color(0xFF00BCD4).withOpacity(0.3)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _pickArtwork(context, provider, symbol),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Symbol preview (tiny)
              _buildSymbolPreview(symbol, hasArt),
              const SizedBox(width: 8),
              // Symbol info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            symbol.type.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: typeColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          symbol.name,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (hasArt)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          symbol.artworkPath!.split('/').last,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF00BCD4),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Click to assign artwork',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFF666666),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Action buttons
              if (hasArt) ...[
                _SmallIconButton(
                  icon: Icons.swap_horiz,
                  tooltip: 'Replace',
                  onTap: () => _pickArtwork(context, provider, symbol),
                ),
                const SizedBox(width: 2),
                _SmallIconButton(
                  icon: Icons.close,
                  tooltip: 'Remove artwork',
                  color: const Color(0xFFFF5252),
                  onTap: () => _clearArtwork(provider, symbol),
                ),
              ] else
                const Icon(Icons.add_photo_alternate_outlined,
                    size: 16, color: Color(0xFF555555)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSymbolPreview(SymbolDefinition symbol, bool hasArt) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: const Color(0xFF111122),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: hasArt
            ? Image.file(
                File(symbol.artworkPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Text(symbol.emoji,
                      style: const TextStyle(fontSize: 16)),
                ),
              )
            : Center(
                child: Text(symbol.emoji,
                    style: const TextStyle(fontSize: 16)),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _pickArtwork(BuildContext context,
      SlotLabProjectProvider provider, SymbolDefinition symbol) async {
    final files = await NativeFilePicker.pickFiles(
      title: 'Select artwork for "${symbol.name}"',
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'],
      allowMultiple: false,
    );
    if (files.isEmpty) return;
    provider.updateSymbolArtwork(symbol.id, files.first);
    _syncArtworkToSlotSymbols(provider);
  }

  Future<void> _bulkImportFromFolder(
      BuildContext context, SlotLabProjectProvider provider) async {
    final dir = await NativeFilePicker.pickDirectory(
      title: 'Select symbol artwork folder',
    );
    if (dir == null) return;

    final folder = Directory(dir);
    if (!folder.existsSync()) return;

    final imageFiles = folder
        .listSync()
        .whereType<File>()
        .where((f) {
          final ext = f.path.split('.').last.toLowerCase();
          return ['png', 'jpg', 'jpeg', 'webp', 'svg'].contains(ext);
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (imageFiles.isEmpty) return;

    // Auto-match: try to match filenames to symbol names/IDs
    final symbols = provider.symbols;
    final assignments = <String, String>{};
    for (final symbol in symbols) {
      final match = imageFiles.where((f) {
        final name = f.path.split('/').last.split('.').first.toLowerCase();
        return name == symbol.id.toLowerCase() ||
            name == symbol.name.toLowerCase() ||
            name.contains(symbol.id.toLowerCase()) ||
            name.contains(symbol.name.toLowerCase());
      }).firstOrNull;

      if (match != null) {
        assignments[symbol.id] = match.path;
      }
    }

    // For unmatched symbols, assign remaining files in order
    final assignedPaths = assignments.values.toSet();
    final unassignedFiles =
        imageFiles.where((f) => !assignedPaths.contains(f.path)).toList();
    final unassignedSymbols = symbols
        .where((s) => !assignments.containsKey(s.id) &&
            (s.artworkPath == null || s.artworkPath!.isEmpty))
        .toList();

    for (var i = 0;
        i < unassignedFiles.length && i < unassignedSymbols.length;
        i++) {
      assignments[unassignedSymbols[i].id] = unassignedFiles[i].path;
    }

    if (assignments.isNotEmpty) {
      provider.updateSymbolArtworkBatch(assignments);
    }

    _syncArtworkToSlotSymbols(provider);
  }

  void _clearArtwork(
      SlotLabProjectProvider provider, SymbolDefinition symbol) {
    provider.updateSymbolArtwork(symbol.id, null);
    _syncArtworkToSlotSymbols(provider);
  }

  void _clearAllArtwork(
      BuildContext context, SlotLabProjectProvider provider) {
    for (final symbol in provider.symbols) {
      if (symbol.artworkPath != null && symbol.artworkPath!.isNotEmpty) {
        provider.updateSymbolArtwork(symbol.id, null);
      }
    }
    _syncArtworkToSlotSymbols(provider);
  }

  /// Sync artworkPath from SymbolDefinition → SlotSymbol.imagePath
  /// Mini-reel preview — 5x3 grid showing all symbols with artwork
  Widget _buildMiniReelPreview(List<SymbolDefinition> symbols) {
    // Build a 5x3 grid using available symbols (cycle if fewer than 15)
    if (symbols.isEmpty) return const SizedBox.shrink();

    const cols = 5;
    const rows = 3;
    const cellSize = 36.0;

    return Container(
      padding: const EdgeInsets.all(6),
      color: const Color(0xFF0E0E18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.grid_view, color: Color(0xFF606068), size: 10),
              const SizedBox(width: 4),
              const Text(
                'REEL PREVIEW',
                style: TextStyle(
                  color: Color(0xFF606068),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: cellSize * rows + (rows - 1) * 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(cols, (col) {
                return Padding(
                  padding: EdgeInsets.only(left: col > 0 ? 2 : 0),
                  child: Column(
                    children: List.generate(rows, (row) {
                      final idx = (col * rows + row) % symbols.length;
                      final sym = symbols[idx];
                      return Padding(
                        padding: EdgeInsets.only(top: row > 0 ? 2 : 0),
                        child: _buildMiniSymbolCell(sym, cellSize),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniSymbolCell(SymbolDefinition sym, double size) {
    final hasArt = sym.artworkPath != null && sym.artworkPath!.isNotEmpty;
    final color = _colorForType(sym.type);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasArt ? color.withOpacity(0.3) : Colors.white.withOpacity(0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasArt
          ? Image.file(
              File(sym.artworkPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, e, st) => Center(
                child: Text(
                  sym.name.length > 2 ? sym.name.substring(0, 2) : sym.name,
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            )
          : Center(
              child: Text(
                sym.name.length > 2 ? sym.name.substring(0, 2) : sym.name,
                style: TextStyle(color: color.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.w700),
              ),
            ),
    );
  }

  void _syncArtworkToSlotSymbols(SlotLabProjectProvider provider) {
    final effective = SlotSymbol.effectiveSymbols;
    final updated = <int, SlotSymbol>{};
    for (final entry in effective.entries) {
      final def = provider.symbols.where((s) {
        // Match by name (case-insensitive)
        return s.name.toLowerCase() == entry.value.name.toLowerCase() ||
            s.id.toLowerCase() == entry.value.name.toLowerCase();
      }).firstOrNull;
      if (def != null &&
          def.artworkPath != null &&
          def.artworkPath!.isNotEmpty) {
        updated[entry.key] = entry.value.withImagePath(def.artworkPath);
      } else {
        updated[entry.key] = entry.value.withImagePath(null);
      }
    }
    SlotSymbol.setDynamicSymbols(updated);
  }

  Color _colorForType(SymbolType type) {
    switch (type) {
      case SymbolType.wild:
        return const Color(0xFFFFD700);
      case SymbolType.scatter:
        return const Color(0xFF00FF88);
      case SymbolType.bonus:
        return const Color(0xFF00FFFF);
      case SymbolType.mystery:
        return const Color(0xFFAA66FF);
      case SymbolType.highPay:
        return const Color(0xFFFF6644);
      case SymbolType.mediumPay:
        return const Color(0xFFDDAA44);
      case SymbolType.lowPay:
        return const Color(0xFF88AACC);
      case SymbolType.multiplier:
        return const Color(0xFFFF44FF);
      case SymbolType.collector:
        return const Color(0xFF44DDAA);
      case SymbolType.custom:
      case SymbolType.high:
      case SymbolType.low:
        return const Color(0xFF999999);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF00BCD4),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = const Color(0xFF888888),
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }
}
