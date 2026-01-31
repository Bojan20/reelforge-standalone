// ============================================================================
// P3-06: Asset Cloud Panel — Cloud Asset Library UI
// FluxForge Studio — Cloud audio asset browser widgets
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/asset_cloud_service.dart';

// ============================================================================
// ASSET CLOUD STATUS BADGE
// ============================================================================

/// Small badge showing cloud asset status
class AssetCloudStatusBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const AssetCloudStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AssetCloudService.instance,
      builder: (context, _) {
        final service = AssetCloudService.instance;
        final isAuth = service.isAuthenticated;
        final transfers = service.activeTransfers
            .where((t) => t.status == AssetTransferStatus.inProgress)
            .length;

        return Tooltip(
          message: isAuth
              ? 'Cloud: ${service.userName} • $transfers active transfers'
              : 'Cloud: Not connected',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isAuth ? Colors.cyan : Colors.grey).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: (isAuth ? Colors.cyan : Colors.grey).withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAuth ? Icons.cloud_done : Icons.cloud_off,
                    size: 14,
                    color: isAuth ? Colors.cyan : Colors.grey,
                  ),
                  if (transfers > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$transfers',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// ASSET CLOUD PANEL
// ============================================================================

/// Main cloud asset browser panel
class AssetCloudPanel extends StatefulWidget {
  final void Function(CloudAsset asset)? onAssetSelected;
  final void Function(CloudAsset asset, String localPath)? onAssetDownloaded;

  const AssetCloudPanel({
    super.key,
    this.onAssetSelected,
    this.onAssetDownloaded,
  });

  @override
  State<AssetCloudPanel> createState() => _AssetCloudPanelState();
}

class _AssetCloudPanelState extends State<AssetCloudPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  AssetCategory? _selectedCategory;
  List<CloudAsset> _searchResults = [];
  List<CloudAsset> _featuredAssets = [];
  bool _isLoading = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadFeaturedAssets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFeaturedAssets() async {
    setState(() => _isLoading = true);
    _featuredAssets = await AssetCloudService.instance.getFeaturedAssets();
    setState(() => _isLoading = false);
  }

  Future<void> _search(String query) async {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isLoading = true);

      final results = await AssetCloudService.instance.searchAssets(
        filters: AssetSearchFilters(
          query: query,
          category: _selectedCategory,
        ),
      );

      setState(() {
        _searchResults = results.assets;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AssetCloudService.instance,
      builder: (context, _) {
        final service = AssetCloudService.instance;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(service),

              // Content
              Expanded(
                child: service.isAuthenticated
                    ? _buildAuthenticatedContent(service)
                    : _buildLoginPrompt(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(AssetCloudService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud,
            color: service.isAuthenticated ? Colors.cyan : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cloud Asset Library',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  service.isAuthenticated
                      ? service.provider.displayName
                      : 'Not connected',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          if (service.isAuthenticated) ...[
            IconButton(
              icon: const Icon(Icons.upload, size: 18),
              onPressed: () => _showUploadDialog(context),
              tooltip: 'Upload',
            ),
            IconButton(
              icon: const Icon(Icons.logout, size: 18),
              onPressed: () => service.logout(),
              tooltip: 'Logout',
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.login, size: 18),
              onPressed: () => _showLoginDialog(context),
              tooltip: 'Login',
            ),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'Connect to Cloud',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[300],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Access thousands of professional audio assets',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showLoginDialog(context),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Sign In'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticatedContent(AssetCloudService service) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search assets...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: _search,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<AssetCategory?>(
                icon: Icon(
                  Icons.filter_list,
                  color: _selectedCategory != null ? Colors.cyan : null,
                  size: 18,
                ),
                tooltip: 'Filter by category',
                onSelected: (category) {
                  setState(() => _selectedCategory = category);
                  _search(_searchController.text);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: null,
                    child: Text('All Categories'),
                  ),
                  const PopupMenuDivider(),
                  ...AssetCategory.values.map(
                    (cat) => PopupMenuItem(
                      value: cat,
                      child: Row(
                        children: [
                          Text(cat.emoji),
                          const SizedBox(width: 8),
                          Text(cat.displayName),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Tabs
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Browse'),
            Tab(text: 'Collections'),
            Tab(text: 'Favorites'),
            Tab(text: 'Transfers'),
          ],
          labelStyle: const TextStyle(fontSize: 12),
          indicatorSize: TabBarIndicatorSize.tab,
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBrowseTab(service),
              _buildCollectionsTab(service),
              _buildFavoritesTab(service),
              _buildTransfersTab(service),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrowseTab(AssetCloudService service) {
    final assets = _searchController.text.isNotEmpty
        ? _searchResults
        : _featuredAssets;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (assets.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.isNotEmpty
              ? 'No results found'
              : 'No featured assets',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        return CloudAssetCard(
          asset: asset,
          onTap: () => widget.onAssetSelected?.call(asset),
          onDownload: () => _downloadAsset(asset),
          onFavorite: () => service.toggleFavorite(asset),
          isFavorite: service.isFavorite(asset.id),
        );
      },
    );
  }

  Widget _buildCollectionsTab(AssetCloudService service) {
    return FutureBuilder<List<AssetCollection>>(
      future: service.getMyCollections(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final collections = snapshot.data ?? [];

        if (collections.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text(
                  'No Collections',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _showCreateCollectionDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create Collection'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: collections.length,
          itemBuilder: (context, index) {
            final collection = collections[index];
            return CollectionTile(
              collection: collection,
              onTap: () {
                // Navigate to collection
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFavoritesTab(AssetCloudService service) {
    final favorites = service.favoriteAssets;

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No Favorites',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 4),
            Text(
              'Heart assets to save them here',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final asset = favorites[index];
        return CloudAssetListTile(
          asset: asset,
          onTap: () => widget.onAssetSelected?.call(asset),
          onDownload: () => _downloadAsset(asset),
          trailing: IconButton(
            icon: const Icon(Icons.favorite, color: Colors.red, size: 18),
            onPressed: () => service.toggleFavorite(asset),
          ),
        );
      },
    );
  }

  Widget _buildTransfersTab(AssetCloudService service) {
    final transfers = service.activeTransfers;

    if (transfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_vert, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No Active Transfers',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: transfers.length,
      itemBuilder: (context, index) {
        final transfer = transfers[index];
        return TransferTile(
          transfer: transfer,
          onCancel: () => service.cancelTransfer(transfer.id),
        );
      },
    );
  }

  Future<void> _downloadAsset(CloudAsset asset) async {
    final localPath = await AssetCloudService.instance.downloadAsset(asset);
    if (localPath != null) {
      widget.onAssetDownloaded?.call(asset, localPath);
    }
  }

  void _showLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AssetCloudLoginDialog(),
    );
  }

  void _showUploadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AssetUploadDialog(),
    );
  }

  void _showCreateCollectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const CreateCollectionDialog(),
    );
  }
}

// ============================================================================
// CLOUD ASSET CARD
// ============================================================================

/// Card showing a cloud asset
class CloudAssetCard extends StatelessWidget {
  final CloudAsset asset;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onFavorite;
  final bool isFavorite;

  const CloudAssetCard({
    super.key,
    required this.asset,
    this.onTap,
    this.onDownload,
    this.onFavorite,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Waveform/thumbnail placeholder
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFF1A1A20),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.audiotrack,
                        size: 32,
                        color: Colors.grey[700],
                      ),
                    ),
                    // Category badge
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          asset.category.emoji,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    // Duration
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          asset.formattedDuration,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        asset.formattedSize,
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                      const Spacer(),
                      if (asset.rating > 0) ...[
                        Icon(Icons.star, size: 10, color: Colors.amber[600]),
                        const SizedBox(width: 2),
                        Text(
                          asset.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: isFavorite ? Colors.red : null,
                    ),
                    onPressed: onFavorite,
                    constraints: const BoxConstraints(minWidth: 32),
                    padding: EdgeInsets.zero,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.download, size: 16),
                    onPressed: onDownload,
                    constraints: const BoxConstraints(minWidth: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CLOUD ASSET LIST TILE
// ============================================================================

/// List tile showing a cloud asset
class CloudAssetListTile extends StatelessWidget {
  final CloudAsset asset;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final Widget? trailing;

  const CloudAssetListTile({
    super.key,
    required this.asset,
    this.onTap,
    this.onDownload,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              asset.category.emoji,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
        title: Text(
          asset.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          '${asset.formattedDuration} • ${asset.formattedSize} • ${asset.format.toUpperCase()}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: trailing ??
            IconButton(
              icon: const Icon(Icons.download, size: 18),
              onPressed: onDownload,
            ),
      ),
    );
  }
}

// ============================================================================
// COLLECTION TILE
// ============================================================================

/// Tile showing a collection
class CollectionTile extends StatelessWidget {
  final AssetCollection collection;
  final VoidCallback? onTap;

  const CollectionTile({
    super.key,
    required this.collection,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.folder, color: Colors.cyan),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                collection.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (collection.isPublic)
              const Icon(Icons.public, size: 14, color: Colors.grey),
          ],
        ),
        subtitle: Text(
          '${collection.assetCount} assets',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

// ============================================================================
// TRANSFER TILE
// ============================================================================

/// Tile showing a transfer
class TransferTile extends StatelessWidget {
  final AssetTransfer transfer;
  final VoidCallback? onCancel;

  const TransferTile({
    super.key,
    required this.transfer,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = transfer.status == AssetTransferStatus.inProgress;
    final isFailed = transfer.status == AssetTransferStatus.failed;

    return Card(
      color: const Color(0xFF242430),
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  transfer.isUpload ? Icons.upload : Icons.download,
                  size: 16,
                  color: isFailed ? Colors.red : Colors.cyan,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    transfer.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (isActive)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: onCancel,
                    constraints: const BoxConstraints(minWidth: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: transfer.progress,
                    backgroundColor: Colors.white10,
                    color: isFailed ? Colors.red : Colors.cyan,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(transfer.progress * 100).toInt()}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
            if (isFailed && transfer.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                transfer.errorMessage!,
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LOGIN DIALOG
// ============================================================================

/// Dialog for cloud login
class AssetCloudLoginDialog extends StatefulWidget {
  const AssetCloudLoginDialog({super.key});

  @override
  State<AssetCloudLoginDialog> createState() => _AssetCloudLoginDialogState();
}

class _AssetCloudLoginDialogState extends State<AssetCloudLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign In to Cloud'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign In'),
        ),
      ],
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await AssetCloudService.instance.authenticate(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AssetCloudService.instance.lastError ?? 'Login failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ============================================================================
// UPLOAD DIALOG
// ============================================================================

/// Dialog for uploading assets
class AssetUploadDialog extends StatefulWidget {
  const AssetUploadDialog({super.key});

  @override
  State<AssetUploadDialog> createState() => _AssetUploadDialogState();
}

class _AssetUploadDialogState extends State<AssetUploadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  AssetCategory _category = AssetCategory.sfx;
  bool _isPublic = true;
  bool _isUploading = false;
  String? _selectedFilePath;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Asset'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // File selection
              InkWell(
                onTap: _selectFile,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: _selectedFilePath != null
                        ? Text(
                            _selectedFilePath!.split('/').last,
                            style: const TextStyle(fontSize: 13),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.upload_file, size: 32),
                              Text(
                                'Click to select file',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<AssetCategory>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: AssetCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.emoji} ${c.displayName}'),
                        ))
                    .toList(),
                onChanged: (c) => setState(() => _category = c!),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                ),
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                title: const Text('Public'),
                value: _isPublic,
                onChanged: (v) => setState(() => _isPublic = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isUploading || _selectedFilePath == null ? null : _upload,
          child: _isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Upload'),
        ),
      ],
    );
  }

  void _selectFile() {
    // Would use file_picker
    setState(() {
      _selectedFilePath = '/path/to/audio.wav';
      _nameController.text = 'audio';
    });
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate() || _selectedFilePath == null) return;

    setState(() => _isUploading = true);

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final asset = await AssetCloudService.instance.uploadAsset(
      filePath: _selectedFilePath!,
      name: _nameController.text,
      category: _category,
      description: _descriptionController.text.isNotEmpty
          ? _descriptionController.text
          : null,
      tags: tags,
      isPublic: _isPublic,
    );

    if (mounted) {
      setState(() => _isUploading = false);
      if (asset != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Asset uploaded successfully')),
        );
      }
    }
  }
}

// ============================================================================
// CREATE COLLECTION DIALOG
// ============================================================================

/// Dialog for creating a collection
class CreateCollectionDialog extends StatefulWidget {
  const CreateCollectionDialog({super.key});

  @override
  State<CreateCollectionDialog> createState() => _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<CreateCollectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isPublic = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Collection'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Collection Name',
                prefixIcon: Icon(Icons.folder),
              ),
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Public Collection'),
              subtitle: const Text('Others can view and download'),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _create,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    final collection = await AssetCloudService.instance.createCollection(
      name: _nameController.text,
      description: _descriptionController.text.isNotEmpty
          ? _descriptionController.text
          : null,
      isPublic: _isPublic,
    );

    if (mounted) {
      setState(() => _isCreating = false);
      if (collection != null) {
        Navigator.pop(context);
      }
    }
  }
}
