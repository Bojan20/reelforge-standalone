// ============================================================================
// P3-11: Marketplace Panel — Plugin Marketplace UI
// FluxForge Studio — Plugin and extension marketplace widgets
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/marketplace_service.dart';

// ============================================================================
// MARKETPLACE STATUS BADGE
// ============================================================================

/// Small badge showing marketplace status
class MarketplaceStatusBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const MarketplaceStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MarketplaceService.instance,
      builder: (context, _) {
        final service = MarketplaceService.instance;
        final updateCount = service.updateCount;

        return Tooltip(
          message: 'Marketplace: ${service.installedCount} installed${updateCount > 0 ? ', $updateCount updates' : ''}',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.purple.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store, size: 14, color: Colors.purple),
                  if (updateCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$updateCount',
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
// MARKETPLACE PANEL
// ============================================================================

/// Main marketplace browser panel
class MarketplacePanel extends StatefulWidget {
  const MarketplacePanel({super.key});

  @override
  State<MarketplacePanel> createState() => _MarketplacePanelState();
}

class _MarketplacePanelState extends State<MarketplacePanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  MarketplaceProductType? _selectedType;
  MarketplaceCategory? _selectedCategory;
  List<MarketplaceProduct> _searchResults = [];
  bool _isLoading = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String query) async {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isLoading = true);

      final results = await MarketplaceService.instance.searchProducts(
        filters: MarketplaceFilters(
          query: query,
          type: _selectedType,
          category: _selectedCategory,
        ),
      );

      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MarketplaceService.instance,
      builder: (context, _) {
        final service = MarketplaceService.instance;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              _buildHeader(service),
              Expanded(child: _buildContent(service)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(MarketplaceService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.store, color: Colors.purple, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Marketplace',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  service.isAuthenticated
                      ? 'Welcome, ${service.userName}'
                      : 'Browse plugins & extensions',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          if (service.isAuthenticated) ...[
            IconButton(
              icon: const Icon(Icons.shopping_cart, size: 18),
              onPressed: () => _showPurchasesDialog(context),
              tooltip: 'Purchases',
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

  Widget _buildContent(MarketplaceService service) {
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
                    hintText: 'Search plugins...',
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
              // Type filter
              PopupMenuButton<MarketplaceProductType?>(
                icon: Icon(
                  Icons.category,
                  color: _selectedType != null ? Colors.purple : null,
                  size: 18,
                ),
                tooltip: 'Filter by type',
                onSelected: (type) {
                  setState(() => _selectedType = type);
                  _search(_searchController.text);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('All Types')),
                  const PopupMenuDivider(),
                  ...MarketplaceProductType.values.map(
                    (t) => PopupMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Text(t.icon),
                          const SizedBox(width: 8),
                          Text(t.displayName),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Category filter
              PopupMenuButton<MarketplaceCategory?>(
                icon: Icon(
                  Icons.filter_list,
                  color: _selectedCategory != null ? Colors.purple : null,
                  size: 18,
                ),
                tooltip: 'Filter by category',
                onSelected: (cat) {
                  setState(() => _selectedCategory = cat);
                  _search(_searchController.text);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('All Categories')),
                  const PopupMenuDivider(),
                  ...MarketplaceCategory.values.map(
                    (c) => PopupMenuItem(
                      value: c,
                      child: Text(c.displayName),
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
            Tab(text: 'Featured'),
            Tab(text: 'Browse'),
            Tab(text: 'Installed'),
            Tab(text: 'Updates'),
          ],
          labelStyle: const TextStyle(fontSize: 12),
          indicatorSize: TabBarIndicatorSize.tab,
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFeaturedTab(service),
              _buildBrowseTab(service),
              _buildInstalledTab(service),
              _buildUpdatesTab(service),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedTab(MarketplaceService service) {
    final featured = service.featuredProducts;

    if (featured.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // Hero banner
        Container(
          height: 120,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade900, Colors.blue.shade900],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 32, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'FluxForge Marketplace',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Plugins, Extensions & More',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),

        // Featured section
        const Text(
          'Featured',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: featured.length,
            itemBuilder: (context, index) {
              final product = featured[index];
              return SizedBox(
                width: 160,
                child: ProductCard(
                  product: product,
                  onTap: () => _showProductDetails(context, product),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // Recent section
        const Text(
          'Recent',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...service.recentProducts.map(
          (product) => ProductListTile(
            product: product,
            onTap: () => _showProductDetails(context, product),
          ),
        ),
      ],
    );
  }

  Widget _buildBrowseTab(MarketplaceService service) {
    final products = _searchController.text.isNotEmpty
        ? _searchResults
        : service.featuredProducts;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (products.isEmpty) {
      return Center(
        child: Text(
          'No products found',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductCard(
          product: product,
          onTap: () => _showProductDetails(context, product),
        );
      },
    );
  }

  Widget _buildInstalledTab(MarketplaceService service) {
    final installed = service.installedProducts;

    if (installed.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No Installed Products',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 8),
            Text(
              'Browse the marketplace to install plugins',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: installed.length,
      itemBuilder: (context, index) {
        final item = installed[index];
        return InstalledProductTile(
          installed: item,
          onUninstall: () => _confirmUninstall(context, item),
          onUpdate: item.hasUpdate ? () => _updateProduct(item.productId) : null,
        );
      },
    );
  }

  Widget _buildUpdatesTab(MarketplaceService service) {
    final updates = service.installedProducts.where((p) => p.hasUpdate).toList();

    if (updates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 48, color: Colors.green[600]),
            const SizedBox(height: 16),
            Text(
              'All Up to Date!',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${updates.length} update${updates.length == 1 ? '' : 's'} available',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _updateAll(updates),
                icon: const Icon(Icons.update, size: 16),
                label: const Text('Update All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: updates.length,
            itemBuilder: (context, index) {
              final item = updates[index];
              return InstalledProductTile(
                installed: item,
                onUpdate: () => _updateProduct(item.productId),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const MarketplaceLoginDialog(),
    );
  }

  void _showPurchasesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PurchasesDialog(),
    );
  }

  void _showProductDetails(BuildContext context, MarketplaceProduct product) {
    showDialog(
      context: context,
      builder: (context) => ProductDetailsDialog(product: product),
    );
  }

  void _confirmUninstall(BuildContext context, InstalledProduct installed) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uninstall Product?'),
        content: Text('Are you sure you want to uninstall this product?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              MarketplaceService.instance.uninstallProduct(installed.productId);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateProduct(String productId) async {
    await MarketplaceService.instance.updateProduct(productId);
  }

  Future<void> _updateAll(List<InstalledProduct> updates) async {
    for (final update in updates) {
      await _updateProduct(update.productId);
    }
  }
}

// ============================================================================
// PRODUCT CARD
// ============================================================================

/// Card showing a product
class ProductCard extends StatelessWidget {
  final MarketplaceProduct product;
  final VoidCallback? onTap;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon/thumbnail
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFF1A1A20),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        product.type.icon,
                        style: const TextStyle(fontSize: 48),
                      ),
                    ),
                    // Price badge
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: product.isFree
                              ? Colors.green
                              : Colors.purple,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.formattedPrice,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.developerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star, size: 12, color: Colors.amber[600]),
                      const SizedBox(width: 2),
                      Text(
                        product.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.download, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 2),
                      Text(
                        _formatCount(product.downloadCount),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// ============================================================================
// PRODUCT LIST TILE
// ============================================================================

/// List tile showing a product
class ProductListTile extends StatelessWidget {
  final MarketplaceProduct product;
  final VoidCallback? onTap;

  const ProductListTile({
    super.key,
    required this.product,
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
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(product.type.icon, style: const TextStyle(fontSize: 24)),
          ),
        ),
        title: Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${product.developerName} • ${product.category.displayName}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: product.isFree ? Colors.green : Colors.purple,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                product.formattedPrice,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, size: 10, color: Colors.amber[600]),
                const SizedBox(width: 2),
                Text(
                  product.rating.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// INSTALLED PRODUCT TILE
// ============================================================================

/// Tile showing an installed product
class InstalledProductTile extends StatelessWidget {
  final InstalledProduct installed;
  final VoidCallback? onUninstall;
  final VoidCallback? onUpdate;

  const InstalledProductTile({
    super.key,
    required this.installed,
    this.onUninstall,
    this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.extension, color: Colors.purple),
          ),
        ),
        title: Text(
          'Product ${installed.productId}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${installed.version}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            if (installed.hasUpdate)
              Text(
                'Update available: v${installed.updateVersion}',
                style: TextStyle(fontSize: 11, color: Colors.orange[400]),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onUpdate != null)
              IconButton(
                icon: const Icon(Icons.update, color: Colors.orange, size: 18),
                onPressed: onUpdate,
                tooltip: 'Update',
              ),
            if (onUninstall != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onUninstall,
                tooltip: 'Uninstall',
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PRODUCT DETAILS DIALOG
// ============================================================================

/// Dialog showing product details
class ProductDetailsDialog extends StatelessWidget {
  final MarketplaceProduct product;

  const ProductDetailsDialog({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final service = MarketplaceService.instance;
    final isInstalled = service.isInstalled(product.id);
    final isPurchased = service.isPurchased(product.id);

    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(product.type.icon, style: const TextStyle(fontSize: 32)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          product.developerName,
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.amber[600]),
                            const SizedBox(width: 4),
                            Text('${product.rating} (${product.ratingCount} reviews)'),
                            const SizedBox(width: 16),
                            Text(product.formattedSize),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.description,
                      style: TextStyle(color: Colors.grey[300]),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: product.tags.map((tag) => Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Version', product.version),
                    _buildInfoRow('Category', product.category.displayName),
                    _buildInfoRow('License', product.license.displayName),
                    _buildInfoRow('Platforms', product.platforms.join(', ')),
                    _buildInfoRow('Downloads', product.downloadCount.toString()),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: product.isFree ? Colors.green : Colors.purple,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      product.formattedPrice,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isInstalled)
                    const Text('Installed', style: TextStyle(color: Colors.green))
                  else if (product.isFree || isPurchased)
                    ElevatedButton.icon(
                      onPressed: () => _install(context),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Install'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _purchase(context),
                      icon: const Icon(Icons.shopping_cart, size: 16),
                      label: const Text('Buy'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[500]),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  Future<void> _install(BuildContext context) async {
    Navigator.pop(context);
    await MarketplaceService.instance.installProduct(product);
  }

  Future<void> _purchase(BuildContext context) async {
    final purchase = await MarketplaceService.instance.purchaseProduct(product);
    if (purchase != null && context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase successful! You can now install the product.')),
      );
    }
  }
}

// ============================================================================
// LOGIN DIALOG
// ============================================================================

/// Dialog for marketplace login
class MarketplaceLoginDialog extends StatefulWidget {
  const MarketplaceLoginDialog({super.key});

  @override
  State<MarketplaceLoginDialog> createState() => _MarketplaceLoginDialogState();
}

class _MarketplaceLoginDialogState extends State<MarketplaceLoginDialog> {
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
      title: const Text('Sign In to Marketplace'),
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

    final success = await MarketplaceService.instance.authenticate(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
      }
    }
  }
}

// ============================================================================
// PURCHASES DIALOG
// ============================================================================

/// Dialog showing user's purchases
class PurchasesDialog extends StatelessWidget {
  const PurchasesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final purchases = MarketplaceService.instance.purchases;

    return AlertDialog(
      title: const Text('Your Purchases'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: purchases.isEmpty
            ? Center(
                child: Text(
                  'No purchases yet',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              )
            : ListView.builder(
                itemCount: purchases.length,
                itemBuilder: (context, index) {
                  final purchase = purchases[index];
                  return ListTile(
                    title: Text(purchase.productName),
                    subtitle: Text(
                      'Purchased ${_formatDate(purchase.purchasedAt)}',
                    ),
                    trailing: Text(
                      '\$${purchase.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
