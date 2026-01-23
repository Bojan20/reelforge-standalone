// ═══════════════════════════════════════════════════════════════════════════════
// SOUNDBANK PANEL — Bank Builder UI
// ═══════════════════════════════════════════════════════════════════════════════
//
// Comprehensive soundbank builder interface:
// - Bank list (create, duplicate, delete)
// - Asset browser with drag-drop
// - Event/container selector from MiddlewareProvider
// - Manifest configuration
// - Multi-platform export dialog
//
// Integration: Lower Zone or dedicated Soundbank screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/soundbank_models.dart';
import '../../providers/soundbank_provider.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../services/native_file_picker.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const double _kBankListWidth = 240.0;
const double _kHeaderHeight = 36.0;
const double _kAssetRowHeight = 48.0;

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class SoundbankPanel extends StatefulWidget {
  const SoundbankPanel({super.key});

  @override
  State<SoundbankPanel> createState() => _SoundbankPanelState();
}

class _SoundbankPanelState extends State<SoundbankPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SoundbankProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.bgDeepest,
          child: Row(
            children: [
              // Bank list (left sidebar)
              SizedBox(
                width: _kBankListWidth,
                child: _BankListPanel(
                  banks: provider.banks,
                  selectedBankId: provider.selectedBankId,
                  onSelectBank: provider.selectBank,
                  onCreateBank: () => _showCreateBankDialog(context),
                  onDuplicateBank: (id) => provider.duplicateBank(id),
                  onDeleteBank: (id) => _confirmDeleteBank(context, provider, id),
                ),
              ),
              // Divider
              Container(width: 1, color: FluxForgeTheme.bgMid),
              // Bank editor (main area)
              Expanded(
                child: provider.selectedBank != null
                    ? _BankEditorPanel(
                        bank: provider.selectedBank!,
                        tabController: _tabController,
                        searchQuery: _searchQuery,
                        searchController: _searchController,
                        onSearchChanged: (q) => setState(() => _searchQuery = q),
                      )
                    : _buildEmptyState(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 64,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No soundbank selected',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new soundbank or select one from the list',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreateBankDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create Soundbank'),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateBankDialog(BuildContext context) {
    final nameController = TextEditingController(text: 'New Soundbank');
    final descController = TextEditingController();
    final authorController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: const Row(
          children: [
            Icon(Icons.library_add, color: FluxForgeTheme.accentBlue, size: 24),
            SizedBox(width: 12),
            Text('Create Soundbank', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(nameController, 'Bank Name', autofocus: true),
              const SizedBox(height: 12),
              _buildTextField(descController, 'Description'),
              const SizedBox(height: 12),
              _buildTextField(authorController, 'Author'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                context.read<SoundbankProvider>().createBank(
                  name: nameController.text.trim(),
                  description: descController.text.trim(),
                  author: authorController.text.trim(),
                );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBank(BuildContext context, SoundbankProvider provider, String bankId) {
    final bank = provider.getBank(bankId);
    if (bank == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: FluxForgeTheme.accentRed, size: 24),
            const SizedBox(width: 12),
            Text('Delete "${bank.manifest.name}"?', style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'This will permanently delete the soundbank and all its configuration.\n'
          'Audio files will not be deleted.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.deleteBank(bankId);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool autofocus = false}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        filled: true,
        fillColor: FluxForgeTheme.bgDeepest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FluxForgeTheme.accentBlue),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BANK LIST PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class _BankListPanel extends StatelessWidget {
  final List<Soundbank> banks;
  final String? selectedBankId;
  final ValueChanged<String?> onSelectBank;
  final VoidCallback onCreateBank;
  final ValueChanged<String> onDuplicateBank;
  final ValueChanged<String> onDeleteBank;

  const _BankListPanel({
    required this.banks,
    required this.selectedBankId,
    required this.onSelectBank,
    required this.onCreateBank,
    required this.onDuplicateBank,
    required this.onDeleteBank,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Header
          Container(
            height: _kHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              border: Border(bottom: BorderSide(color: FluxForgeTheme.bgMid)),
            ),
            child: Row(
              children: [
                const Icon(Icons.library_music, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  'SOUNDBANKS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${banks.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: FluxForgeTheme.accentBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: onCreateBank,
                  tooltip: 'Create Soundbank',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          // Bank list
          Expanded(
            child: banks.isEmpty
                ? _buildEmptyBankList()
                : ListView.builder(
                    itemCount: banks.length,
                    itemBuilder: (ctx, i) => _buildBankTile(banks[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBankList() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: 48,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'No soundbanks',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onCreateBank,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create'),
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.accentBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankTile(Soundbank bank) {
    final isSelected = bank.manifest.id == selectedBankId;
    final validation = Consumer<SoundbankProvider>(
      builder: (ctx, provider, _) {
        final v = provider.validateBank(bank.manifest.id);
        return _ValidationBadge(validation: v);
      },
    );

    return InkWell(
      onTap: () => onSelectBank(bank.manifest.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? FluxForgeTheme.accentBlue : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(color: FluxForgeTheme.bgMid.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            // Bank icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.folder_special,
                size: 18,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 10),
            // Bank info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bank.manifest.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${bank.assets.length} assets',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        bank.formattedTotalSize,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            validation,
            // Context menu
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 16,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                const PopupMenuItem(value: 'export', child: Text('Export...')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: FluxForgeTheme.accentRed)),
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case 'duplicate':
                    onDuplicateBank(bank.manifest.id);
                    break;
                  case 'delete':
                    onDeleteBank(bank.manifest.id);
                    break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BANK EDITOR PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class _BankEditorPanel extends StatelessWidget {
  final Soundbank bank;
  final TabController tabController;
  final String searchQuery;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const _BankEditorPanel({
    required this.bank,
    required this.tabController,
    required this.searchQuery,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Bank header
        _buildBankHeader(context),
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.bgMid)),
          ),
          child: TabBar(
            controller: tabController,
            labelColor: FluxForgeTheme.accentBlue,
            unselectedLabelColor: Colors.white54,
            indicatorColor: FluxForgeTheme.accentBlue,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabs: const [
              Tab(text: 'ASSETS'),
              Tab(text: 'EVENTS'),
              Tab(text: 'CONFIG'),
              Tab(text: 'EXPORT'),
            ],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              _AssetsTab(
                bank: bank,
                searchQuery: searchQuery,
                searchController: searchController,
                onSearchChanged: onSearchChanged,
              ),
              _EventsTab(bank: bank),
              _ConfigTab(bank: bank),
              _ExportTab(bank: bank),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBankHeader(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
            FluxForgeTheme.bgSurface,
          ],
        ),
        border: Border(bottom: BorderSide(color: FluxForgeTheme.bgMid)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_special, color: FluxForgeTheme.accentBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  bank.manifest.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'v${bank.manifest.version} • ${bank.assets.length} assets • ${bank.eventIds.length} events',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Total size
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage, size: 12, color: Colors.white54),
                const SizedBox(width: 4),
                Text(
                  bank.formattedTotalSize,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Duration
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 12, color: Colors.white54),
                const SizedBox(width: 4),
                Text(
                  bank.formattedTotalDuration,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ASSETS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _AssetsTab extends StatelessWidget {
  final Soundbank bank;
  final String searchQuery;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const _AssetsTab({
    required this.bank,
    required this.searchQuery,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filteredAssets = searchQuery.isEmpty
        ? bank.assets
        : bank.assets
            .where((a) => a.name.toLowerCase().contains(searchQuery.toLowerCase()))
            .toList();

    return Column(
      children: [
        // Toolbar
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.bgMid)),
          ),
          child: Row(
            children: [
              // Search
              SizedBox(
                width: 200,
                child: TextField(
                  controller: searchController,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search assets...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    prefixIcon: Icon(Icons.search, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: FluxForgeTheme.bgDeepest,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              const Spacer(),
              // Add assets button
              TextButton.icon(
                onPressed: () => _addAssets(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Assets', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: FluxForgeTheme.accentBlue,
                ),
              ),
            ],
          ),
        ),
        // Asset list
        Expanded(
          child: filteredAssets.isEmpty
              ? _buildEmptyAssets(context)
              : ListView.builder(
                  itemCount: filteredAssets.length,
                  itemBuilder: (ctx, i) => _buildAssetRow(context, filteredAssets[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyAssets(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.audio_file_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            searchQuery.isEmpty ? 'No assets in this bank' : 'No matching assets',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _addAssets(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Audio Files'),
              style: TextButton.styleFrom(
                foregroundColor: FluxForgeTheme.accentBlue,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssetRow(BuildContext context, SoundbankAsset asset) {
    return Container(
      height: _kAssetRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.bgMid.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // File icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.audio_file,
              size: 18,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
          const SizedBox(width: 12),
          // Asset info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  asset.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      asset.formattedDuration,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${asset.sampleRate}Hz ${asset.channels}ch',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      asset.formattedSize,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Priority dropdown
          _PriorityDropdown(
            value: asset.priority,
            onChanged: (p) {
              if (p != null) {
                context.read<SoundbankProvider>().setAssetPriority(
                  bank.manifest.id,
                  asset.id,
                  p,
                );
              }
            },
          ),
          const SizedBox(width: 8),
          // Tags
          if (asset.tags.isNotEmpty)
            Wrap(
              spacing: 4,
              children: asset.tags.take(2).map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 9,
                    color: FluxForgeTheme.accentOrange,
                  ),
                ),
              )).toList(),
            ),
          const SizedBox(width: 8),
          // Remove button
          IconButton(
            icon: Icon(
              Icons.close,
              size: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            onPressed: () {
              context.read<SoundbankProvider>().removeAsset(
                bank.manifest.id,
                asset.id,
              );
            },
            tooltip: 'Remove from bank',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Future<void> _addAssets(BuildContext context) async {
    try {
      final files = await NativeFilePicker.pickAudioFiles();
      if (files.isNotEmpty) {
        final provider = context.read<SoundbankProvider>();
        await provider.addAssets(bank.manifest.id, files);
      }
    } catch (e) {
      debugPrint('Failed to add assets: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _EventsTab extends StatelessWidget {
  final Soundbank bank;

  const _EventsTab({required this.bank});

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final availableEvents = middleware.compositeEvents;
        final includedEventIds = bank.eventIds.toSet();

        return Column(
          children: [
            // Toolbar
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                border: Border(bottom: BorderSide(color: FluxForgeTheme.bgMid)),
              ),
              child: Row(
                children: [
                  Text(
                    '${bank.eventIds.length} events included',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _selectAllEvents(context, availableEvents),
                    child: const Text('Include All', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _clearAllEvents(context),
                    child: const Text('Clear All', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
            // Event list
            Expanded(
              child: availableEvents.isEmpty
                  ? _buildNoEvents()
                  : ListView.builder(
                      itemCount: availableEvents.length,
                      itemBuilder: (ctx, i) {
                        final event = availableEvents[i];
                        final isIncluded = includedEventIds.contains(event.id);
                        return _buildEventRow(context, event, isIncluded);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoEvents() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_note_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'No events available',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create events in Slot Lab or Middleware',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventRow(BuildContext context, dynamic event, bool isIncluded) {
    return CheckboxListTile(
      value: isIncluded,
      onChanged: (value) {
        final provider = context.read<SoundbankProvider>();
        if (value == true) {
          provider.addEvent(bank.manifest.id, event.id);
        } else {
          provider.removeEvent(bank.manifest.id, event.id);
        }
      },
      title: Text(
        event.name,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      subtitle: Text(
        '${event.layers.length} layers • ${event.triggerStages.isNotEmpty ? event.triggerStages.first : 'No stage'}',
        style: TextStyle(
          fontSize: 10,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      secondary: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: event.color,
          shape: BoxShape.circle,
        ),
      ),
      activeColor: FluxForgeTheme.accentBlue,
      checkColor: Colors.white,
      dense: true,
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  void _selectAllEvents(BuildContext context, List events) {
    final provider = context.read<SoundbankProvider>();
    for (final event in events) {
      provider.addEvent(bank.manifest.id, event.id);
    }
  }

  void _clearAllEvents(BuildContext context) {
    final provider = context.read<SoundbankProvider>();
    for (final eventId in bank.eventIds.toList()) {
      provider.removeEvent(bank.manifest.id, eventId);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _ConfigTab extends StatelessWidget {
  final Soundbank bank;

  const _ConfigTab({required this.bank});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // General section
          _buildSectionHeader('General'),
          const SizedBox(height: 12),
          _buildConfigRow(
            context,
            'Name',
            bank.manifest.name,
            (value) => _updateManifest(context, (m) => m.copyWith(name: value)),
          ),
          _buildConfigRow(
            context,
            'Description',
            bank.manifest.description,
            (value) => _updateManifest(context, (m) => m.copyWith(description: value)),
            multiline: true,
          ),
          _buildConfigRow(
            context,
            'Version',
            bank.manifest.version,
            (value) => _updateManifest(context, (m) => m.copyWith(version: value)),
          ),
          _buildConfigRow(
            context,
            'Author',
            bank.manifest.author,
            (value) => _updateManifest(context, (m) => m.copyWith(author: value)),
          ),

          const SizedBox(height: 24),

          // Audio Settings section
          _buildSectionHeader('Audio Settings'),
          const SizedBox(height: 12),
          _buildDropdownRow<SoundbankAudioFormat>(
            'Default Format',
            bank.manifest.defaultAudioFormat,
            SoundbankAudioFormat.values,
            (v) => v.label,
            (value) {
              if (value != null) {
                _updateManifest(context, (m) => m.copyWith(defaultAudioFormat: value));
              }
            },
          ),
          const SizedBox(height: 8),
          _buildDropdownRow<int>(
            'Sample Rate',
            bank.manifest.defaultSampleRate,
            [44100, 48000, 96000],
            (v) => '${v}Hz',
            (value) {
              if (value != null) {
                _updateManifest(context, (m) => m.copyWith(defaultSampleRate: value));
              }
            },
          ),

          const SizedBox(height: 24),

          // Loading Strategy section
          _buildSectionHeader('Loading Strategy'),
          const SizedBox(height: 12),
          _buildDropdownRow<SoundbankLoadStrategy>(
            'Strategy',
            bank.manifest.loadStrategy,
            SoundbankLoadStrategy.values,
            (v) => v.name.replaceAllMapped(
              RegExp(r'([A-Z])'),
              (m) => ' ${m.group(0)}',
            ).trim(),
            (value) {
              if (value != null) {
                _updateManifest(context, (m) => m.copyWith(loadStrategy: value));
              }
            },
          ),

          const SizedBox(height: 24),

          // Target Platforms section
          _buildSectionHeader('Target Platforms'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SoundbankPlatform.values.map((platform) {
              final isSelected = bank.manifest.targetPlatforms.contains(platform);
              return FilterChip(
                label: Text(
                  platform.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  final platforms = bank.manifest.targetPlatforms.toList();
                  if (selected) {
                    platforms.add(platform);
                  } else {
                    platforms.remove(platform);
                  }
                  _updateManifest(context, (m) => m.copyWith(targetPlatforms: platforms));
                },
                backgroundColor: FluxForgeTheme.bgDeepest,
                selectedColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                checkmarkColor: FluxForgeTheme.accentBlue,
                side: BorderSide(
                  color: isSelected ? FluxForgeTheme.accentBlue : Colors.white24,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Metadata section
          _buildSectionHeader('Metadata'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetadataRow('Created', _formatDate(bank.manifest.createdAt)),
                _buildMetadataRow('Modified', _formatDate(bank.manifest.modifiedAt)),
                _buildMetadataRow('ID', bank.manifest.id),
                _buildMetadataRow('Checksum Assets', '${bank.assets.length}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.5),
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildConfigRow(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: value),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              maxLines: multiline ? 3 : 1,
              decoration: InputDecoration(
                filled: true,
                fillColor: FluxForgeTheme.bgDeepest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: FluxForgeTheme.accentBlue),
                ),
              ),
              onSubmitted: onChanged,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow<T>(
    String label,
    T value,
    List<T> options,
    String Function(T) labelBuilder,
    ValueChanged<T?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<T>(
                value: value,
                items: options.map((o) => DropdownMenuItem<T>(
                  value: o,
                  child: Text(
                    labelBuilder(o),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                )).toList(),
                onChanged: onChanged,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: FluxForgeTheme.bgSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateManifest(BuildContext context, SoundbankManifest Function(SoundbankManifest) update) {
    context.read<SoundbankProvider>().updateManifest(bank.manifest.id, update);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _ExportTab extends StatefulWidget {
  final Soundbank bank;

  const _ExportTab({required this.bank});

  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  SoundbankPlatform _platform = SoundbankPlatform.universal;
  SoundbankAudioFormat _audioFormat = SoundbankAudioFormat.wav16;
  int _sampleRate = 48000;
  bool _compressArchive = true;
  bool _generateManifest = true;
  String? _outputPath;
  bool _isExporting = false;
  SoundbankExportResult? _lastResult;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Validation status
          Consumer<SoundbankProvider>(
            builder: (ctx, provider, _) {
              final validation = provider.validateBank(widget.bank.manifest.id);
              return _ValidationCard(validation: validation);
            },
          ),

          const SizedBox(height: 24),

          // Platform selection
          _buildSectionHeader('Target Platform'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SoundbankPlatform.values.map((platform) {
              final isSelected = _platform == platform;
              return ChoiceChip(
                label: Text(
                  platform.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _platform = platform),
                backgroundColor: FluxForgeTheme.bgDeepest,
                selectedColor: FluxForgeTheme.accentBlue,
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Audio format
          _buildSectionHeader('Audio Format'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdown<SoundbankAudioFormat>(
                  'Format',
                  _audioFormat,
                  SoundbankAudioFormat.values,
                  (v) => v.label,
                  (v) {
                    if (v != null) setState(() => _audioFormat = v);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdown<int>(
                  'Sample Rate',
                  _sampleRate,
                  [44100, 48000, 96000],
                  (v) => '${v}Hz',
                  (v) {
                    if (v != null) setState(() => _sampleRate = v);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Options
          _buildSectionHeader('Options'),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _compressArchive,
            onChanged: (v) => setState(() => _compressArchive = v ?? true),
            title: const Text(
              'Compress archive',
              style: TextStyle(fontSize: 12, color: Colors.white),
            ),
            subtitle: Text(
              'Create a compressed ZIP archive',
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
            ),
            activeColor: FluxForgeTheme.accentBlue,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _generateManifest,
            onChanged: (v) => setState(() => _generateManifest = v ?? true),
            title: const Text(
              'Generate manifest',
              style: TextStyle(fontSize: 12, color: Colors.white),
            ),
            subtitle: Text(
              'Include JSON manifest with bank metadata',
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
            ),
            activeColor: FluxForgeTheme.accentBlue,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          const SizedBox(height: 24),

          // Output path
          _buildSectionHeader('Output Location'),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selectOutputPath,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _outputPath != null
                      ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                      : Colors.white24,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 20,
                    color: _outputPath != null ? FluxForgeTheme.accentBlue : Colors.white54,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _outputPath ?? 'Select output folder...',
                      style: TextStyle(
                        fontSize: 12,
                        color: _outputPath != null ? Colors.white : Colors.white54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Export button
          Center(
            child: SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: _outputPath != null && !_isExporting ? _startExport : null,
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.upload, size: 18),
                label: Text(_isExporting ? 'Exporting...' : 'Export Soundbank'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Last export result
          if (_lastResult != null) ...[
            const SizedBox(height: 24),
            _buildExportResult(_lastResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.5),
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    T value,
    List<T> options,
    String Function(T) labelBuilder,
    ValueChanged<T?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<T>(
            value: value,
            items: options.map((o) => DropdownMenuItem<T>(
              value: o,
              child: Text(
                labelBuilder(o),
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            )).toList(),
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: FluxForgeTheme.bgSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildExportResult(SoundbankExportResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: result.success
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.1)
            : FluxForgeTheme.accentRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.success
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.3)
              : FluxForgeTheme.accentRed.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                result.success ? 'Export Successful' : 'Export Failed',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                ),
              ),
            ],
          ),
          if (result.success) ...[
            const SizedBox(height: 8),
            Text(
              '${result.exportedAssets} assets exported (${(result.totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            Text(
              'Duration: ${result.exportDuration.inMilliseconds}ms',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.errors.map((e) => Text(
              e,
              style: const TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.accentRed,
              ),
            )),
          ],
        ],
      ),
    );
  }

  Future<void> _selectOutputPath() async {
    try {
      final directory = await NativeFilePicker.pickAudioFolder();
      if (directory != null) {
        setState(() => _outputPath = directory);
      }
    } catch (e) {
      debugPrint('Failed to select directory: $e');
    }
  }

  Future<void> _startExport() async {
    if (_outputPath == null) return;

    setState(() {
      _isExporting = true;
      _lastResult = null;
    });

    try {
      final provider = context.read<SoundbankProvider>();
      final config = SoundbankExportConfig(
        outputPath: _outputPath!,
        platform: _platform,
        audioFormat: _audioFormat,
        sampleRate: _sampleRate,
        compressArchive: _compressArchive,
        generateManifest: _generateManifest,
      );

      final result = await provider.exportBank(widget.bank.manifest.id, config);
      setState(() => _lastResult = result);
    } catch (e) {
      setState(() => _lastResult = SoundbankExportResult.failure(e.toString()));
    } finally {
      setState(() => _isExporting = false);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _ValidationBadge extends StatelessWidget {
  final SoundbankValidation validation;

  const _ValidationBadge({required this.validation});

  @override
  Widget build(BuildContext context) {
    if (validation.isValid && validation.issues.isEmpty) {
      return const Icon(
        Icons.check_circle,
        size: 16,
        color: FluxForgeTheme.accentGreen,
      );
    }

    final hasErrors = validation.errorCount > 0;
    final hasWarnings = validation.warningCount > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasErrors)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentRed.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, size: 10, color: FluxForgeTheme.accentRed),
                const SizedBox(width: 2),
                Text(
                  '${validation.errorCount}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: FluxForgeTheme.accentRed,
                  ),
                ),
              ],
            ),
          ),
        if (hasWarnings) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning, size: 10, color: FluxForgeTheme.accentOrange),
                const SizedBox(width: 2),
                Text(
                  '${validation.warningCount}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: FluxForgeTheme.accentOrange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ValidationCard extends StatelessWidget {
  final SoundbankValidation validation;

  const _ValidationCard({required this.validation});

  @override
  Widget build(BuildContext context) {
    final color = validation.isValid
        ? FluxForgeTheme.accentGreen
        : (validation.errorCount > 0 ? FluxForgeTheme.accentRed : FluxForgeTheme.accentOrange);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                validation.isValid ? Icons.check_circle : Icons.warning,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                validation.isValid ? 'Bank is valid' : 'Validation issues found',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              if (validation.errorCount > 0)
                _buildCountBadge(validation.errorCount, 'errors', FluxForgeTheme.accentRed),
              if (validation.warningCount > 0)
                _buildCountBadge(validation.warningCount, 'warnings', FluxForgeTheme.accentOrange),
              if (validation.infoCount > 0)
                _buildCountBadge(validation.infoCount, 'info', FluxForgeTheme.accentBlue),
            ],
          ),
          if (validation.issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...validation.issues.take(5).map((issue) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _iconForSeverity(issue.severity),
                    size: 12,
                    color: _colorForSeverity(issue.severity),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue.message,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            )),
            if (validation.issues.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${validation.issues.length - 5} more issues',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCountBadge(int count, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(fontSize: 9, color: color),
      ),
    );
  }

  IconData _iconForSeverity(ValidationSeverity severity) {
    return switch (severity) {
      ValidationSeverity.error => Icons.error,
      ValidationSeverity.warning => Icons.warning,
      ValidationSeverity.info => Icons.info,
    };
  }

  Color _colorForSeverity(ValidationSeverity severity) {
    return switch (severity) {
      ValidationSeverity.error => FluxForgeTheme.accentRed,
      ValidationSeverity.warning => FluxForgeTheme.accentOrange,
      ValidationSeverity.info => FluxForgeTheme.accentBlue,
    };
  }
}

class _PriorityDropdown extends StatelessWidget {
  final SoundbankAssetPriority value;
  final ValueChanged<SoundbankAssetPriority?> onChanged;

  const _PriorityDropdown({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _colorForPriority(value).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<SoundbankAssetPriority>(
        value: value,
        items: SoundbankAssetPriority.values.map((p) => DropdownMenuItem(
          value: p,
          child: Text(
            p.name,
            style: TextStyle(
              fontSize: 10,
              color: _colorForPriority(p),
            ),
          ),
        )).toList(),
        onChanged: onChanged,
        underline: const SizedBox(),
        isDense: true,
        dropdownColor: FluxForgeTheme.bgSurface,
        icon: Icon(
          Icons.arrow_drop_down,
          size: 16,
          color: _colorForPriority(value),
        ),
      ),
    );
  }

  Color _colorForPriority(SoundbankAssetPriority priority) {
    return switch (priority) {
      SoundbankAssetPriority.critical => FluxForgeTheme.accentRed,
      SoundbankAssetPriority.high => FluxForgeTheme.accentOrange,
      SoundbankAssetPriority.normal => Colors.white70,
      SoundbankAssetPriority.low => FluxForgeTheme.accentCyan,
      SoundbankAssetPriority.background => Colors.white38,
    };
  }
}
