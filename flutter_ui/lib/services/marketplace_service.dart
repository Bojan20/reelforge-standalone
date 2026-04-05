// ============================================================================
// P3-11: Plugin Marketplace Service — Store System
// FluxForge Studio — Plugin and extension marketplace
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// ENUMS
// ============================================================================

/// Product type in marketplace
enum MarketplaceProductType {
  plugin, // Audio plugins (VST/AU/CLAP)
  extension, // FluxForge extensions
  preset, // Presets/patches
  template, // Project templates
  soundbank, // Sound libraries
  theme; // UI themes

  String get displayName {
    switch (this) {
      case MarketplaceProductType.plugin:
        return 'Plugin';
      case MarketplaceProductType.extension:
        return 'Extension';
      case MarketplaceProductType.preset:
        return 'Preset';
      case MarketplaceProductType.template:
        return 'Template';
      case MarketplaceProductType.soundbank:
        return 'Sound Bank';
      case MarketplaceProductType.theme:
        return 'Theme';
    }
  }

  String get icon {
    switch (this) {
      case MarketplaceProductType.plugin:
        return '🔌';
      case MarketplaceProductType.extension:
        return '🧩';
      case MarketplaceProductType.preset:
        return '🎛️';
      case MarketplaceProductType.template:
        return '📄';
      case MarketplaceProductType.soundbank:
        return '🎵';
      case MarketplaceProductType.theme:
        return '🎨';
    }
  }
}

/// Product category
enum MarketplaceCategory {
  dynamics,
  eq,
  reverb,
  delay,
  modulation,
  distortion,
  mastering,
  synth,
  sampler,
  utility,
  slotAudio,
  gameAudio,
  other;

  String get displayName {
    switch (this) {
      case MarketplaceCategory.dynamics:
        return 'Dynamics';
      case MarketplaceCategory.eq:
        return 'EQ';
      case MarketplaceCategory.reverb:
        return 'Reverb';
      case MarketplaceCategory.delay:
        return 'Delay';
      case MarketplaceCategory.modulation:
        return 'Modulation';
      case MarketplaceCategory.distortion:
        return 'Distortion';
      case MarketplaceCategory.mastering:
        return 'Mastering';
      case MarketplaceCategory.synth:
        return 'Synthesizers';
      case MarketplaceCategory.sampler:
        return 'Samplers';
      case MarketplaceCategory.utility:
        return 'Utility';
      case MarketplaceCategory.slotAudio:
        return 'Slot Audio';
      case MarketplaceCategory.gameAudio:
        return 'Game Audio';
      case MarketplaceCategory.other:
        return 'Other';
    }
  }
}

/// License type
enum MarketplaceLicense {
  free,
  freemium,
  subscription,
  perpetual,
  rental;

  String get displayName {
    switch (this) {
      case MarketplaceLicense.free:
        return 'Free';
      case MarketplaceLicense.freemium:
        return 'Freemium';
      case MarketplaceLicense.subscription:
        return 'Subscription';
      case MarketplaceLicense.perpetual:
        return 'Perpetual';
      case MarketplaceLicense.rental:
        return 'Rental';
    }
  }
}

/// Installation status
enum InstallationStatus {
  notInstalled,
  downloading,
  installing,
  installed,
  updateAvailable,
  failed;
}

// ============================================================================
// MODELS
// ============================================================================

/// Product in marketplace
class MarketplaceProduct {
  final String id;
  final String name;
  final String description;
  final String developerName;
  final String developerId;
  final MarketplaceProductType type;
  final MarketplaceCategory category;
  final String version;
  final List<String> tags;
  final String? iconUrl;
  final List<String> screenshotUrls;
  final double price; // 0 = free
  final String currency;
  final MarketplaceLicense license;
  final double rating;
  final int ratingCount;
  final int downloadCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sizeBytes;
  final List<String> platforms; // macos, windows, linux
  final String? minFluxForgeVersion;
  final Map<String, dynamic> metadata;

  const MarketplaceProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.developerName,
    required this.developerId,
    required this.type,
    required this.category,
    required this.version,
    this.tags = const [],
    this.iconUrl,
    this.screenshotUrls = const [],
    this.price = 0,
    this.currency = 'USD',
    this.license = MarketplaceLicense.perpetual,
    this.rating = 0,
    this.ratingCount = 0,
    this.downloadCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.sizeBytes = 0,
    this.platforms = const ['macos', 'windows', 'linux'],
    this.minFluxForgeVersion,
    this.metadata = const {},
  });

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) {
    return MarketplaceProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      developerName: json['developerName'] as String,
      developerId: json['developerId'] as String,
      type: MarketplaceProductType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => MarketplaceProductType.plugin,
      ),
      category: MarketplaceCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => MarketplaceCategory.other,
      ),
      version: json['version'] as String,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      iconUrl: json['iconUrl'] as String?,
      screenshotUrls: (json['screenshotUrls'] as List<dynamic>?)?.cast<String>() ?? [],
      price: (json['price'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      license: MarketplaceLicense.values.firstWhere(
        (l) => l.name == json['license'],
        orElse: () => MarketplaceLicense.perpetual,
      ),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: json['ratingCount'] as int? ?? 0,
      downloadCount: json['downloadCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      platforms: (json['platforms'] as List<dynamic>?)?.cast<String>() ?? ['macos', 'windows', 'linux'],
      minFluxForgeVersion: json['minFluxForgeVersion'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'developerName': developerName,
        'developerId': developerId,
        'type': type.name,
        'category': category.name,
        'version': version,
        'tags': tags,
        'iconUrl': iconUrl,
        'screenshotUrls': screenshotUrls,
        'price': price,
        'currency': currency,
        'license': license.name,
        'rating': rating,
        'ratingCount': ratingCount,
        'downloadCount': downloadCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sizeBytes': sizeBytes,
        'platforms': platforms,
        'minFluxForgeVersion': minFluxForgeVersion,
        'metadata': metadata,
      };

  bool get isFree => price == 0;

  String get formattedPrice {
    if (isFree) return 'Free';
    return '\$$price $currency';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Installed product info
class InstalledProduct {
  final String productId;
  final String version;
  final String installPath;
  final DateTime installedAt;
  final DateTime? lastUsedAt;
  final InstallationStatus status;
  final String? updateVersion;

  const InstalledProduct({
    required this.productId,
    required this.version,
    required this.installPath,
    required this.installedAt,
    this.lastUsedAt,
    this.status = InstallationStatus.installed,
    this.updateVersion,
  });

  factory InstalledProduct.fromJson(Map<String, dynamic> json) {
    return InstalledProduct(
      productId: json['productId'] as String,
      version: json['version'] as String,
      installPath: json['installPath'] as String,
      installedAt: DateTime.parse(json['installedAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      status: InstallationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => InstallationStatus.installed,
      ),
      updateVersion: json['updateVersion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'version': version,
        'installPath': installPath,
        'installedAt': installedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'status': status.name,
        'updateVersion': updateVersion,
      };

  bool get hasUpdate => updateVersion != null && updateVersion != version;
}

/// Purchase record
class Purchase {
  final String id;
  final String productId;
  final String productName;
  final double amount;
  final String currency;
  final DateTime purchasedAt;
  final String licenseKey;
  final DateTime? expiresAt;

  const Purchase({
    required this.id,
    required this.productId,
    required this.productName,
    required this.amount,
    required this.currency,
    required this.purchasedAt,
    required this.licenseKey,
    this.expiresAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id'] as String,
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      purchasedAt: DateTime.parse(json['purchasedAt'] as String),
      licenseKey: json['licenseKey'] as String,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'amount': amount,
        'currency': currency,
        'purchasedAt': purchasedAt.toIso8601String(),
        'licenseKey': licenseKey,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

/// Developer/publisher info
class MarketplaceDeveloper {
  final String id;
  final String name;
  final String? description;
  final String? websiteUrl;
  final String? avatarUrl;
  final int productCount;
  final bool isVerified;
  final DateTime joinedAt;

  const MarketplaceDeveloper({
    required this.id,
    required this.name,
    this.description,
    this.websiteUrl,
    this.avatarUrl,
    this.productCount = 0,
    this.isVerified = false,
    required this.joinedAt,
  });

  factory MarketplaceDeveloper.fromJson(Map<String, dynamic> json) {
    return MarketplaceDeveloper(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      websiteUrl: json['websiteUrl'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      productCount: json['productCount'] as int? ?? 0,
      isVerified: json['isVerified'] as bool? ?? false,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
    );
  }
}

/// Review
class ProductReview {
  final String id;
  final String productId;
  final String userId;
  final String userName;
  final int rating;
  final String? title;
  final String? content;
  final DateTime createdAt;
  final int helpfulCount;

  const ProductReview({
    required this.id,
    required this.productId,
    required this.userId,
    required this.userName,
    required this.rating,
    this.title,
    this.content,
    required this.createdAt,
    this.helpfulCount = 0,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    return ProductReview(
      id: json['id'] as String,
      productId: json['productId'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      rating: json['rating'] as int,
      title: json['title'] as String?,
      content: json['content'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      helpfulCount: json['helpfulCount'] as int? ?? 0,
    );
  }
}

/// Search/filter options
class MarketplaceFilters {
  final String? query;
  final MarketplaceProductType? type;
  final MarketplaceCategory? category;
  final bool? freeOnly;
  final double? maxPrice;
  final double? minRating;
  final String? platform;
  final String? sortBy; // name, price, rating, downloads, date
  final bool ascending;

  const MarketplaceFilters({
    this.query,
    this.type,
    this.category,
    this.freeOnly,
    this.maxPrice,
    this.minRating,
    this.platform,
    this.sortBy,
    this.ascending = false,
  });
}

// ============================================================================
// MARKETPLACE SERVICE
// ============================================================================

/// Plugin and extension marketplace service
class MarketplaceService extends ChangeNotifier {
  // Singleton
  static final MarketplaceService _instance = MarketplaceService._();
  static MarketplaceService get instance => _instance;
  MarketplaceService._();

  // State
  bool _isAuthenticated = false;
  String? _userId;
  String? _userName;
  String? _authToken;
  String? _lastError;

  // Cache
  final Map<String, MarketplaceProduct> _productCache = {};
  final Map<String, InstalledProduct> _installedProducts = {};
  final List<Purchase> _purchases = [];
  List<MarketplaceProduct> _featuredProducts = [];
  List<MarketplaceProduct> _recentProducts = [];

  // Downloads
  final Map<String, double> _downloadProgress = {};

  // Configuration
  static const String _prefsKey = 'marketplace_config';
  String _apiBaseUrl = 'https://marketplace.fluxforge.io/api';

  // Streams
  final StreamController<String> _downloadController =
      StreamController<String>.broadcast();

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get lastError => _lastError;
  List<MarketplaceProduct> get featuredProducts => List.unmodifiable(_featuredProducts);
  List<MarketplaceProduct> get recentProducts => List.unmodifiable(_recentProducts);
  List<InstalledProduct> get installedProducts => _installedProducts.values.toList();
  List<Purchase> get purchases => List.unmodifiable(_purchases);
  Map<String, double> get downloadProgress => Map.unmodifiable(_downloadProgress);
  Stream<String> get downloadStream => _downloadController.stream;

  int get installedCount => _installedProducts.length;
  int get updateCount => _installedProducts.values.where((p) => p.hasUpdate).length;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize marketplace service
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_prefsKey);

      if (configJson != null) {
        final config = jsonDecode(configJson) as Map<String, dynamic>;
        _authToken = config['authToken'] as String?;
        _userId = config['userId'] as String?;
        _userName = config['userName'] as String?;
        _isAuthenticated = _authToken != null;

        // Load installed products
        final installedJson = config['installed'] as List<dynamic>?;
        if (installedJson != null) {
          for (final item in installedJson) {
            final installed = InstalledProduct.fromJson(item as Map<String, dynamic>);
            _installedProducts[installed.productId] = installed;
          }
        }

        // Load purchases
        final purchasesJson = config['purchases'] as List<dynamic>?;
        if (purchasesJson != null) {
          _purchases.addAll(
            purchasesJson.map((p) => Purchase.fromJson(p as Map<String, dynamic>)),
          );
        }
      }

      // Load featured products
      await _loadFeaturedProducts();

    } catch (e) { /* ignored */ }
  }

  /// Save configuration
  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'authToken': _authToken,
          'userId': _userId,
          'userName': _userName,
          'installed': _installedProducts.values.map((p) => p.toJson()).toList(),
          'purchases': _purchases.map((p) => p.toJson()).toList(),
        }),
      );
    } catch (e) { /* ignored */ }
  }

  Future<void> _loadFeaturedProducts() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      _featuredProducts = _generateMockProducts(10);
      _recentProducts = _generateMockProducts(5);
      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Authenticate with marketplace
  Future<bool> authenticate({
    required String email,
    required String password,
  }) async {
    try {
      _lastError = null;
      await Future.delayed(const Duration(milliseconds: 500));

      _authToken = 'mkt_token_${DateTime.now().millisecondsSinceEpoch}';
      _userId = 'user_${email.hashCode.abs()}';
      _userName = email.split('@').first;
      _isAuthenticated = true;

      await _saveConfig();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = 'Authentication failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    _authToken = null;
    _userId = null;
    _userName = null;
    _isAuthenticated = false;
    await _saveConfig();
    notifyListeners();
  }

  // ============================================================================
  // BROWSE & SEARCH
  // ============================================================================

  /// Search products
  Future<List<MarketplaceProduct>> searchProducts({
    MarketplaceFilters filters = const MarketplaceFilters(),
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      return _generateMockProducts(pageSize, filters: filters);
    } catch (e) {
      _lastError = 'Search failed: $e';
      return [];
    }
  }

  /// Get product by ID
  Future<MarketplaceProduct?> getProduct(String productId) async {
    if (_productCache.containsKey(productId)) {
      return _productCache[productId];
    }

    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final product = _generateMockProduct(productId);
      _productCache[productId] = product;
      return product;
    } catch (e) {
      _lastError = 'Failed to get product: $e';
      return null;
    }
  }

  /// Get products by category
  Future<List<MarketplaceProduct>> getProductsByCategory(
    MarketplaceCategory category,
  ) async {
    return searchProducts(filters: MarketplaceFilters(category: category));
  }

  /// Get products by developer
  Future<List<MarketplaceProduct>> getProductsByDeveloper(
    String developerId,
  ) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      return _generateMockProducts(10);
    } catch (e) {
      return [];
    }
  }

  /// Get developer info
  Future<MarketplaceDeveloper?> getDeveloper(String developerId) async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      return MarketplaceDeveloper(
        id: developerId,
        name: 'FluxForge Labs',
        description: 'Professional audio plugin developer',
        websiteUrl: 'https://fluxforge.io',
        productCount: 15,
        isVerified: true,
        joinedAt: DateTime(2020, 1, 1),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get product reviews
  Future<List<ProductReview>> getProductReviews(String productId) async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      return List.generate(
        5,
        (i) => ProductReview(
          id: 'review_$i',
          productId: productId,
          userId: 'user_$i',
          userName: 'User ${i + 1}',
          rating: 3 + (i % 3),
          title: 'Great plugin!',
          content: 'This is an amazing plugin. Highly recommended.',
          createdAt: DateTime.now().subtract(Duration(days: i * 5)),
          helpfulCount: i * 3,
        ),
      );
    } catch (e) {
      return [];
    }
  }

  // ============================================================================
  // PURCHASE
  // ============================================================================

  /// Purchase a product
  Future<Purchase?> purchaseProduct(MarketplaceProduct product) async {
    if (!_isAuthenticated) {
      _lastError = 'Not authenticated';
      return null;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 800));

      final purchase = Purchase(
        id: 'purchase_${DateTime.now().millisecondsSinceEpoch}',
        productId: product.id,
        productName: product.name,
        amount: product.price,
        currency: product.currency,
        purchasedAt: DateTime.now(),
        licenseKey: 'FF-${product.id.hashCode.abs()}-${DateTime.now().millisecondsSinceEpoch}',
      );

      _purchases.add(purchase);
      await _saveConfig();
      notifyListeners();

      return purchase;
    } catch (e) {
      _lastError = 'Purchase failed: $e';
      return null;
    }
  }

  /// Check if product is purchased
  bool isPurchased(String productId) {
    return _purchases.any((p) => p.productId == productId && !p.isExpired);
  }

  // ============================================================================
  // INSTALL/UNINSTALL
  // ============================================================================

  /// Install a product
  Future<bool> installProduct(
    MarketplaceProduct product, {
    void Function(double progress)? onProgress,
  }) async {
    if (!product.isFree && !isPurchased(product.id)) {
      _lastError = 'Product not purchased';
      return false;
    }

    try {
      _downloadProgress[product.id] = 0;
      notifyListeners();

      // Simulate download
      for (var i = 1; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        _downloadProgress[product.id] = i / 10;
        onProgress?.call(i / 10);
        _downloadController.add(product.id);
        notifyListeners();
      }

      // Create installed record
      final installed = InstalledProduct(
        productId: product.id,
        version: product.version,
        installPath: '/Applications/FluxForge/Plugins/${product.name}',
        installedAt: DateTime.now(),
      );

      _installedProducts[product.id] = installed;
      _downloadProgress.remove(product.id);

      await _saveConfig();
      notifyListeners();

      return true;
    } catch (e) {
      _downloadProgress.remove(product.id);
      _lastError = 'Installation failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Uninstall a product
  Future<bool> uninstallProduct(String productId) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      _installedProducts.remove(productId);
      await _saveConfig();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = 'Uninstall failed: $e';
      return false;
    }
  }

  /// Update a product
  Future<bool> updateProduct(String productId) async {
    final installed = _installedProducts[productId];
    if (installed == null || !installed.hasUpdate) return false;

    final product = await getProduct(productId);
    if (product == null) return false;

    return installProduct(product);
  }

  /// Check if product is installed
  bool isInstalled(String productId) {
    return _installedProducts.containsKey(productId);
  }

  /// Get installed product info
  InstalledProduct? getInstalledProduct(String productId) {
    return _installedProducts[productId];
  }

  // ============================================================================
  // REVIEWS
  // ============================================================================

  /// Submit a review
  Future<bool> submitReview({
    required String productId,
    required int rating,
    String? title,
    String? content,
  }) async {
    if (!_isAuthenticated) {
      _lastError = 'Not authenticated';
      return false;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      // Would submit to API
      return true;
    } catch (e) {
      _lastError = 'Failed to submit review: $e';
      return false;
    }
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  List<MarketplaceProduct> _generateMockProducts(
    int count, {
    MarketplaceFilters? filters,
  }) {
    final types = MarketplaceProductType.values;
    final categories = MarketplaceCategory.values;

    return List.generate(count, (i) {
      final type = filters?.type ?? types[i % types.length];
      final category = filters?.category ?? categories[i % categories.length];
      final price = (i % 3 == 0) ? 0.0 : 49.0 + (i * 10.0);

      return MarketplaceProduct(
        id: 'prod_${DateTime.now().millisecondsSinceEpoch}_$i',
        name: _getMockProductName(type, i),
        description: 'Professional ${type.displayName.toLowerCase()} for FluxForge Studio',
        developerName: i % 2 == 0 ? 'FluxForge Labs' : 'Audio Tools Inc',
        developerId: 'dev_${i % 3}',
        type: type,
        category: category,
        version: '1.${i % 5}.$i',
        tags: _getMockTags(category),
        price: price,
        license: price == 0 ? MarketplaceLicense.free : MarketplaceLicense.perpetual,
        rating: 3.5 + (i % 3) * 0.5,
        ratingCount: i * 20,
        downloadCount: i * 100,
        createdAt: DateTime.now().subtract(Duration(days: i * 10)),
        updatedAt: DateTime.now().subtract(Duration(days: i)),
        sizeBytes: 10000000 + (i * 5000000),
      );
    });
  }

  MarketplaceProduct _generateMockProduct(String id) {
    return MarketplaceProduct(
      id: id,
      name: 'Plugin $id',
      description: 'Professional audio plugin',
      developerName: 'FluxForge Labs',
      developerId: 'dev_1',
      type: MarketplaceProductType.plugin,
      category: MarketplaceCategory.dynamics,
      version: '1.0.0',
      price: 49.0,
      rating: 4.5,
      ratingCount: 100,
      downloadCount: 1000,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sizeBytes: 50000000,
    );
  }

  String _getMockProductName(MarketplaceProductType type, int index) {
    final names = <MarketplaceProductType, List<String>>{
      MarketplaceProductType.plugin: ['ProComp', 'UltraEQ', 'SpaceVerb', 'WarmTube', 'StereoMax'],
      MarketplaceProductType.extension: ['SlotLab Pro', 'ALE Editor', 'Stage Builder', 'Event Graph'],
      MarketplaceProductType.preset: ['Essential Dynamics', 'Mastering Suite', 'Vocal Pack'],
      MarketplaceProductType.template: ['Slot Game Starter', 'DAW Project', 'Podcast Template'],
      MarketplaceProductType.soundbank: ['Casino Sounds', 'Win Fanfares', 'UI Elements'],
      MarketplaceProductType.theme: ['Dark Pro', 'Light Studio', 'Neon Glow'],
    };

    final typeNames = names[type] ?? ['Item'];
    return '${typeNames[index % typeNames.length]} ${index + 1}';
  }

  List<String> _getMockTags(MarketplaceCategory category) {
    final baseTags = <String>['professional', 'high-quality'];
    final categoryTags = <MarketplaceCategory, List<String>>{
      MarketplaceCategory.dynamics: ['compressor', 'limiter', 'gate'],
      MarketplaceCategory.eq: ['parametric', 'graphic', 'linear-phase'],
      MarketplaceCategory.reverb: ['convolution', 'algorithmic', 'hall'],
      MarketplaceCategory.slotAudio: ['casino', 'slot', 'game-audio'],
    };
    return [...baseTags, ...(categoryTags[category] ?? [])];
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    _downloadController.close();
    super.dispose();
  }
}
