/// Documentation Viewer Widget
///
/// In-app documentation browser with search and navigation.
///
/// P3-10: Documentation Generator UI (~350 LOC)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/documentation_generator.dart';

/// Documentation viewer panel
class DocumentationViewer extends StatefulWidget {
  final DocManifest? manifest;
  final VoidCallback? onGenerate;
  final VoidCallback? onExport;

  const DocumentationViewer({
    super.key,
    this.manifest,
    this.onGenerate,
    this.onExport,
  });

  @override
  State<DocumentationViewer> createState() => _DocumentationViewerState();
}

class _DocumentationViewerState extends State<DocumentationViewer> {
  String _searchQuery = '';
  DocSection? _selectedSection;
  DocEntry? _selectedEntry;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<DocEntry> get _filteredEntries {
    if (widget.manifest == null) return [];

    final allEntries = widget.manifest!.sections.expand((s) => s.entries).toList();

    if (_searchQuery.isEmpty) return allEntries;

    final query = _searchQuery.toLowerCase();
    return allEntries.where((e) {
      return e.name.toLowerCase().contains(query) ||
          e.description.toLowerCase().contains(query) ||
          e.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121216),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: widget.manifest == null
                ? _buildEmptyState()
                : Row(
                    children: [
                      // Sidebar
                      SizedBox(
                        width: 280,
                        child: _buildSidebar(),
                      ),
                      const VerticalDivider(width: 1),
                      // Content
                      Expanded(child: _buildContent()),
                    ],
                  ),
          ),
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
          const Icon(Icons.menu_book, color: Color(0xFF4a9eff), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Documentation',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          if (widget.manifest != null) ...[
            // Search
            SizedBox(
              width: 200,
              height: 28,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: const TextStyle(color: Color(0xFF888888)),
                  prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF888888)),
                  filled: true,
                  fillColor: const Color(0xFF0a0a0c),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            const SizedBox(width: 8),
            // Stats badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${widget.manifest!.stats['total'] ?? 0} items',
                style: const TextStyle(
                  color: Color(0xFF4a9eff),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Generate button
          _buildHeaderButton(
            icon: Icons.refresh,
            label: 'Generate',
            onTap: widget.onGenerate,
          ),
          const SizedBox(width: 4),
          // Export button
          _buildHeaderButton(
            icon: Icons.download,
            label: 'Export',
            onTap: widget.onExport,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF888888)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No documentation generated',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Generate" to scan the codebase',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: widget.onGenerate,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Generate Documentation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a9eff),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final manifest = widget.manifest!;

    return Container(
      color: const Color(0xFF0a0a0c),
      child: Column(
        children: [
          // Project info
          Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manifest.projectName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'v${manifest.version}',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2a2a30)),
          // Sections
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _searchQuery.isEmpty
                  ? manifest.sections.length
                  : 1, // Show flat list when searching
              itemBuilder: (context, index) {
                if (_searchQuery.isNotEmpty) {
                  return _buildSearchResults();
                }
                return _buildSectionItem(manifest.sections[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionItem(DocSection section) {
    final isSelected = _selectedSection == section;

    return ExpansionTile(
      title: Text(
        section.title,
        style: TextStyle(
          color: isSelected ? const Color(0xFF4a9eff) : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      leading: Icon(
        _getIconForSection(section.title),
        size: 16,
        color: isSelected ? const Color(0xFF4a9eff) : const Color(0xFF888888),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF2a2a30),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${section.entries.length}',
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 10,
          ),
        ),
      ),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: section.entries.map((e) => _buildEntryItem(e, section)).toList(),
    );
  }

  Widget _buildEntryItem(DocEntry entry, DocSection section) {
    final isSelected = _selectedEntry == entry;

    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: const Color(0xFF4a9eff).withValues(alpha: 0.1),
      title: Text(
        entry.name,
        style: TextStyle(
          color: isSelected ? const Color(0xFF4a9eff) : Colors.white,
          fontSize: 11,
        ),
      ),
      onTap: () {
        setState(() {
          _selectedSection = section;
          _selectedEntry = entry;
        });
      },
    );
  }

  Widget _buildSearchResults() {
    final results = _filteredEntries;

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No results for "$_searchQuery"',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${results.length} results',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
        ),
        ...results.map((e) => ListTile(
              dense: true,
              selected: _selectedEntry == e,
              selectedTileColor: const Color(0xFF4a9eff).withValues(alpha: 0.1),
              leading: Icon(
                _getIconForType(e.type),
                size: 14,
                color: const Color(0xFF888888),
              ),
              title: Text(
                e.name,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              subtitle: Text(
                e.type.name,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
              ),
              onTap: () => setState(() => _selectedEntry = e),
            )),
      ],
    );
  }

  Widget _buildContent() {
    if (_selectedEntry == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'Select an item from the sidebar',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final entry = _selectedEntry!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _getIconForType(entry.type),
                color: const Color(0xFF4a9eff),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      entry.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.type.name.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Copy button
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                color: const Color(0xFF888888),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: entry.name));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Description
          _buildContentSection('Description', entry.description),

          // File path
          if (entry.filePath != null)
            _buildContentSection(
              'Location',
              '${entry.filePath}${entry.lineNumber != null ? ':${entry.lineNumber}' : ''}',
              isCode: true,
            ),

          // Tags
          if (entry.tags.isNotEmpty)
            _buildTagsSection(entry.tags),

          // Parameters
          if (entry.parameters.isNotEmpty)
            _buildParametersSection(entry.parameters),

          // Return type
          if (entry.returnType != null)
            _buildContentSection('Returns', entry.returnType!, isCode: true),

          // Examples
          if (entry.examples.isNotEmpty)
            _buildExamplesSection(entry.examples),
        ],
      ),
    );
  }

  Widget _buildContentSection(String title, String content, {bool isCode = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (isCode)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0a0a0c),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2a2a30)),
              ),
              child: SelectableText(
                content,
                style: const TextStyle(
                  color: Color(0xFF40ff90),
                  fontFamily: 'SF Mono',
                  fontSize: 12,
                ),
              ),
            )
          else
            SelectableText(
              content,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildTagsSection(List<String> tags) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tags',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(
                      color: Color(0xFF4a9eff),
                      fontSize: 11,
                    ),
                  ),
                )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildParametersSection(Map<String, String> params) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parameters',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          ...params.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0a0a0c),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          color: Color(0xFFff9040),
                          fontFamily: 'SF Mono',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.value,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildExamplesSection(List<String> examples) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Examples',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          ...examples.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0a0a0c),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2a2a30)),
                ),
                child: SelectableText(
                  e,
                  style: const TextStyle(
                    color: Color(0xFF40c8ff),
                    fontFamily: 'SF Mono',
                    fontSize: 11,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  IconData _getIconForSection(String title) {
    switch (title.toLowerCase()) {
      case 'services':
        return Icons.miscellaneous_services;
      case 'providers':
        return Icons.account_tree;
      case 'widgets':
        return Icons.widgets;
      case 'models':
        return Icons.data_object;
      case 'rust crates':
        return Icons.extension;
      case 'ffi functions':
        return Icons.code;
      case 'enums':
        return Icons.list;
      default:
        return Icons.folder;
    }
  }

  IconData _getIconForType(DocEntryType type) {
    switch (type) {
      case DocEntryType.service:
        return Icons.miscellaneous_services;
      case DocEntryType.provider:
        return Icons.account_tree;
      case DocEntryType.widget:
        return Icons.widgets;
      case DocEntryType.model:
        return Icons.data_object;
      case DocEntryType.ffiFunction:
        return Icons.code;
      case DocEntryType.rustCrate:
        return Icons.extension;
      case DocEntryType.constant:
        return Icons.pin;
      case DocEntryType.enum_:
        return Icons.list;
    }
  }
}
