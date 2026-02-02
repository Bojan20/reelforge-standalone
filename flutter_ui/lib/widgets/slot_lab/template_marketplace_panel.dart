/// P2-SL-2: Template Marketplace Panel (2026-02-02)
///
/// Community template marketplace for browsing, downloading, and sharing
/// SlotLab audio templates.
///
/// Features:
/// - Browse community templates
/// - Download/upload templates
/// - Rating system (1-5 stars)
/// - Category filtering
/// - Preview before download
/// - Local caching
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/template_models.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MARKETPLACE MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// A template listing in the marketplace
class MarketplaceTemplate {
  final String id;
  final SlotTemplate template;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final DateTime publishedAt;
  final DateTime? updatedAt;
  final int downloadCount;
  final double averageRating;
  final int ratingCount;
  final List<String> tags;
  final String? thumbnailUrl;
  final bool isVerified;
  final bool isFeatured;

  const MarketplaceTemplate({
    required this.id,
    required this.template,
    required this.authorId,
    required this.authorName,
    this.authorAvatarUrl,
    required this.publishedAt,
    this.updatedAt,
    this.downloadCount = 0,
    this.averageRating = 0.0,
    this.ratingCount = 0,
    this.tags = const [],
    this.thumbnailUrl,
    this.isVerified = false,
    this.isFeatured = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'template': template.toJson(),
        'authorId': authorId,
        'authorName': authorName,
        'authorAvatarUrl': authorAvatarUrl,
        'publishedAt': publishedAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'downloadCount': downloadCount,
        'averageRating': averageRating,
        'ratingCount': ratingCount,
        'tags': tags,
        'thumbnailUrl': thumbnailUrl,
        'isVerified': isVerified,
        'isFeatured': isFeatured,
      };

  factory MarketplaceTemplate.fromJson(Map<String, dynamic> json) {
    return MarketplaceTemplate(
      id: json['id'] as String,
      template: SlotTemplate.fromJson(json['template'] as Map<String, dynamic>),
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      authorAvatarUrl: json['authorAvatarUrl'] as String?,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      downloadCount: json['downloadCount'] as int? ?? 0,
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: json['ratingCount'] as int? ?? 0,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnailUrl'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      isFeatured: json['isFeatured'] as bool? ?? false,
    );
  }
}

/// User rating for a template
class TemplateRating {
  final String templateId;
  final String userId;
  final int stars; // 1-5
  final String? comment;
  final DateTime createdAt;

  const TemplateRating({
    required this.templateId,
    required this.userId,
    required this.stars,
    this.comment,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'userId': userId,
        'stars': stars,
        'comment': comment,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TemplateRating.fromJson(Map<String, dynamic> json) {
    return TemplateRating(
      templateId: json['templateId'] as String,
      userId: json['userId'] as String,
      stars: json['stars'] as int,
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Sort options for marketplace
enum MarketplaceSortBy {
  newest('Newest', Icons.schedule),
  popular('Popular', Icons.trending_up),
  topRated('Top Rated', Icons.star),
  mostDownloaded('Most Downloaded', Icons.download);

  const MarketplaceSortBy(this.label, this.icon);
  final String label;
  final IconData icon;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKETPLACE SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for marketplace operations (simulated for offline use)
class MarketplaceService extends ChangeNotifier {
  static final MarketplaceService instance = MarketplaceService._();
  MarketplaceService._();

  // Local cache
  final List<MarketplaceTemplate> _cachedTemplates = [];
  final Map<String, List<TemplateRating>> _ratings = {};
  final Set<String> _downloadedIds = {};

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  /// Initialize with sample templates
  Future<void> initialize() async {
    if (_cachedTemplates.isNotEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Simulate loading delay
      await Future.delayed(const Duration(milliseconds: 500));

      // Add sample marketplace templates
      _cachedTemplates.addAll(_generateSampleTemplates());
      _error = null;
    } catch (e) {
      _error = 'Failed to load marketplace: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get all templates with optional filtering
  List<MarketplaceTemplate> getTemplates({
    TemplateCategory? category,
    String? searchQuery,
    MarketplaceSortBy sortBy = MarketplaceSortBy.popular,
    bool featuredOnly = false,
  }) {
    var results = _cachedTemplates.toList();

    // Filter by category
    if (category != null) {
      results = results.where((t) => t.template.category == category).toList();
    }

    // Filter featured
    if (featuredOnly) {
      results = results.where((t) => t.isFeatured).toList();
    }

    // Search filter
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      results = results.where((t) {
        return t.template.name.toLowerCase().contains(query) ||
            t.template.description.toLowerCase().contains(query) ||
            t.authorName.toLowerCase().contains(query) ||
            t.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }

    // Sort
    switch (sortBy) {
      case MarketplaceSortBy.newest:
        results.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      case MarketplaceSortBy.popular:
        results.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
      case MarketplaceSortBy.topRated:
        results.sort((a, b) => b.averageRating.compareTo(a.averageRating));
      case MarketplaceSortBy.mostDownloaded:
        results.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
    }

    return results;
  }

  /// Get featured templates
  List<MarketplaceTemplate> getFeaturedTemplates() {
    return _cachedTemplates.where((t) => t.isFeatured).toList();
  }

  /// Download a template (simulated)
  Future<SlotTemplate> downloadTemplate(String templateId) async {
    final template = _cachedTemplates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => throw Exception('Template not found'),
    );

    // Simulate download
    await Future.delayed(const Duration(milliseconds: 300));

    // Update download count
    final index = _cachedTemplates.indexWhere((t) => t.id == templateId);
    if (index >= 0) {
      final updated = MarketplaceTemplate(
        id: template.id,
        template: template.template,
        authorId: template.authorId,
        authorName: template.authorName,
        authorAvatarUrl: template.authorAvatarUrl,
        publishedAt: template.publishedAt,
        updatedAt: template.updatedAt,
        downloadCount: template.downloadCount + 1,
        averageRating: template.averageRating,
        ratingCount: template.ratingCount,
        tags: template.tags,
        thumbnailUrl: template.thumbnailUrl,
        isVerified: template.isVerified,
        isFeatured: template.isFeatured,
      );
      _cachedTemplates[index] = updated;
    }

    _downloadedIds.add(templateId);
    notifyListeners();

    return template.template;
  }

  /// Check if template is downloaded
  bool isDownloaded(String templateId) => _downloadedIds.contains(templateId);

  /// Rate a template
  Future<void> rateTemplate({
    required String templateId,
    required int stars,
    String? comment,
  }) async {
    if (stars < 1 || stars > 5) {
      throw ArgumentError('Stars must be between 1 and 5');
    }

    final rating = TemplateRating(
      templateId: templateId,
      userId: 'local_user',
      stars: stars,
      comment: comment,
      createdAt: DateTime.now(),
    );

    _ratings.putIfAbsent(templateId, () => []);
    _ratings[templateId]!.add(rating);

    // Update average rating
    final index = _cachedTemplates.indexWhere((t) => t.id == templateId);
    if (index >= 0) {
      final template = _cachedTemplates[index];
      final allRatings = _ratings[templateId]!;
      final avgRating = allRatings.map((r) => r.stars).reduce((a, b) => a + b) /
          allRatings.length;

      _cachedTemplates[index] = MarketplaceTemplate(
        id: template.id,
        template: template.template,
        authorId: template.authorId,
        authorName: template.authorName,
        authorAvatarUrl: template.authorAvatarUrl,
        publishedAt: template.publishedAt,
        updatedAt: template.updatedAt,
        downloadCount: template.downloadCount,
        averageRating: avgRating,
        ratingCount: allRatings.length,
        tags: template.tags,
        thumbnailUrl: template.thumbnailUrl,
        isVerified: template.isVerified,
        isFeatured: template.isFeatured,
      );
    }

    notifyListeners();
  }

  /// Get ratings for a template
  List<TemplateRating> getRatings(String templateId) {
    return _ratings[templateId] ?? [];
  }

  /// Upload a template (simulated - saves locally)
  Future<String> uploadTemplate(SlotTemplate template) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final marketplaceTemplate = MarketplaceTemplate(
      id: id,
      template: template,
      authorId: 'local_user',
      authorName: 'You',
      publishedAt: DateTime.now(),
      tags: [template.category.name],
    );

    _cachedTemplates.add(marketplaceTemplate);
    notifyListeners();

    return id;
  }

  /// Generate sample templates for demo
  List<MarketplaceTemplate> _generateSampleTemplates() {
    final now = DateTime.now();

    return [
      MarketplaceTemplate(
        id: 'mkt_classic_egyptian',
        template: _createSampleTemplate(
          'Egyptian Riches',
          TemplateCategory.classic,
          'Classic 5x3 Egyptian themed slot with scatter-triggered free spins',
        ),
        authorId: 'studio_official',
        authorName: 'FluxForge Studio',
        publishedAt: now.subtract(const Duration(days: 30)),
        downloadCount: 1523,
        averageRating: 4.8,
        ratingCount: 127,
        tags: ['egyptian', 'classic', 'free-spins', 'official'],
        isVerified: true,
        isFeatured: true,
      ),
      MarketplaceTemplate(
        id: 'mkt_megaways_viking',
        template: _createSampleTemplate(
          'Viking Thunder Ways',
          TemplateCategory.megaways,
          'High volatility Megaways with cascading wins and multipliers',
        ),
        authorId: 'studio_official',
        authorName: 'FluxForge Studio',
        publishedAt: now.subtract(const Duration(days: 15)),
        downloadCount: 892,
        averageRating: 4.6,
        ratingCount: 73,
        tags: ['viking', 'megaways', 'cascade', 'multiplier', 'official'],
        isVerified: true,
        isFeatured: true,
      ),
      MarketplaceTemplate(
        id: 'mkt_holdwin_crypto',
        template: _createSampleTemplate(
          'Crypto Coins',
          TemplateCategory.holdWin,
          'Hold & Win mechanic with 4-tier jackpots and coin collection',
        ),
        authorId: 'community_dev_1',
        authorName: 'AudioCraft Pro',
        publishedAt: now.subtract(const Duration(days: 7)),
        downloadCount: 456,
        averageRating: 4.3,
        ratingCount: 34,
        tags: ['crypto', 'hold-win', 'jackpot', 'coins'],
        isVerified: false,
        isFeatured: false,
      ),
      MarketplaceTemplate(
        id: 'mkt_cluster_candy',
        template: _createSampleTemplate(
          'Candy Cluster',
          TemplateCategory.cluster,
          'Sweet cluster pays with cascading symbols and candy features',
        ),
        authorId: 'community_dev_2',
        authorName: 'SlotSound Labs',
        publishedAt: now.subtract(const Duration(days: 21)),
        downloadCount: 678,
        averageRating: 4.5,
        ratingCount: 52,
        tags: ['candy', 'cluster', 'cascade', 'sweet'],
        isVerified: true,
        isFeatured: false,
      ),
      MarketplaceTemplate(
        id: 'mkt_jackpot_progressive',
        template: _createSampleTemplate(
          'Fortune Wheel Jackpot',
          TemplateCategory.jackpot,
          'Progressive jackpot with bonus wheel and multiple win tiers',
        ),
        authorId: 'studio_official',
        authorName: 'FluxForge Studio',
        publishedAt: now.subtract(const Duration(days: 45)),
        downloadCount: 2341,
        averageRating: 4.9,
        ratingCount: 198,
        tags: ['jackpot', 'progressive', 'wheel', 'bonus', 'official'],
        isVerified: true,
        isFeatured: true,
      ),
      MarketplaceTemplate(
        id: 'mkt_video_greek',
        template: _createSampleTemplate(
          'Olympus Rising',
          TemplateCategory.video,
          'Greek mythology themed video slot with expanding wilds',
        ),
        authorId: 'community_dev_3',
        authorName: 'Mythic Audio',
        publishedAt: now.subtract(const Duration(days: 3)),
        downloadCount: 234,
        averageRating: 4.2,
        ratingCount: 18,
        tags: ['greek', 'mythology', 'expanding-wilds', 'zeus'],
        isVerified: false,
        isFeatured: false,
      ),
    ];
  }

  SlotTemplate _createSampleTemplate(
    String name,
    TemplateCategory category,
    String description,
  ) {
    return SlotTemplate(
      id: name.toLowerCase().replaceAll(' ', '_'),
      name: name,
      version: '1.0.0',
      category: category,
      description: description,
      author: 'FluxForge',
      symbols: const [],
      winTiers: const [],
      coreStages: const [],
      duckingRules: const [],
      aleContexts: const [],
      winMultiplierRtpc: const TemplateRtpcDefinition(
        name: 'win_multiplier',
        min: 0,
        max: 100,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKETPLACE PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Template Marketplace Panel
class TemplateMarketplacePanel extends StatefulWidget {
  /// Callback when template is downloaded
  final void Function(SlotTemplate template)? onTemplateDownloaded;

  /// Callback when template is selected for preview
  final void Function(MarketplaceTemplate template)? onPreview;

  const TemplateMarketplacePanel({
    super.key,
    this.onTemplateDownloaded,
    this.onPreview,
  });

  @override
  State<TemplateMarketplacePanel> createState() => _TemplateMarketplacePanelState();
}

class _TemplateMarketplacePanelState extends State<TemplateMarketplacePanel> {
  final MarketplaceService _service = MarketplaceService.instance;

  String _searchQuery = '';
  TemplateCategory? _filterCategory;
  MarketplaceSortBy _sortBy = MarketplaceSortBy.popular;
  bool _showFeaturedOnly = false;
  MarketplaceTemplate? _selectedTemplate;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _service.initialize();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  List<MarketplaceTemplate> get _filteredTemplates {
    return _service.getTemplates(
      category: _filterCategory,
      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      sortBy: _sortBy,
      featuredOnly: _showFeaturedOnly,
    );
  }

  Future<void> _downloadTemplate(MarketplaceTemplate template) async {
    setState(() => _isDownloading = true);

    try {
      final downloaded = await _service.downloadTemplate(template.id);
      widget.onTemplateDownloaded?.call(downloaded);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded "${template.template.name}"'),
            backgroundColor: const Color(0xFF40ff90),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: const Color(0xFFff4060),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _showRatingDialog(MarketplaceTemplate template) async {
    int selectedStars = 5;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a20),
          title: Text('Rate "${template.template.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  return IconButton(
                    icon: Icon(
                      star <= selectedStars ? Icons.star : Icons.star_border,
                      color: const Color(0xFFffd700),
                      size: 36,
                    ),
                    onPressed: () {
                      setDialogState(() => selectedStars = star);
                    },
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                _getRatingText(selectedStars),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selectedStars),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4a9eff),
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _service.rateTemplate(templateId: template.id, stars: result);
    }
  }

  String _getRatingText(int stars) {
    return switch (stars) {
      1 => 'Poor',
      2 => 'Fair',
      3 => 'Good',
      4 => 'Very Good',
      5 => 'Excellent',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildFilters(),
        Expanded(
          child: _service.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _service.error != null
                  ? _buildError()
                  : _buildGrid(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront, color: Color(0xFF4a9eff)),
          const SizedBox(width: 12),
          const Text(
            'Template Marketplace',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF40ff90).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_filteredTemplates.length} templates',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF40ff90),
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _service.initialize(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search templates...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFF242430),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: 12),

          // Category filter
          DropdownButton<TemplateCategory?>(
            value: _filterCategory,
            hint: const Text('Category'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              ...TemplateCategory.values.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c.displayName),
                  )),
            ],
            onChanged: (value) => setState(() => _filterCategory = value),
          ),
          const SizedBox(width: 12),

          // Sort
          DropdownButton<MarketplaceSortBy>(
            value: _sortBy,
            items: MarketplaceSortBy.values
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(s.icon, size: 16),
                          const SizedBox(width: 4),
                          Text(s.label),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _sortBy = value);
            },
          ),
          const SizedBox(width: 12),

          // Featured toggle
          FilterChip(
            label: const Text('Featured'),
            selected: _showFeaturedOnly,
            onSelected: (value) => setState(() => _showFeaturedOnly = value),
            selectedColor: const Color(0xFFffd700).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final templates = _filteredTemplates;

    if (templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'No templates found',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) => _MarketplaceTemplateCard(
        template: templates[index],
        isDownloaded: _service.isDownloaded(templates[index].id),
        isDownloading: _isDownloading && _selectedTemplate?.id == templates[index].id,
        onDownload: () {
          setState(() => _selectedTemplate = templates[index]);
          _downloadTemplate(templates[index]);
        },
        onPreview: () => widget.onPreview?.call(templates[index]),
        onRate: () => _showRatingDialog(templates[index]),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Color(0xFFff4060)),
          const SizedBox(height: 16),
          Text(
            _service.error ?? 'Failed to load marketplace',
            style: const TextStyle(color: Color(0xFFff4060)),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _service.initialize(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEMPLATE CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _MarketplaceTemplateCard extends StatelessWidget {
  final MarketplaceTemplate template;
  final bool isDownloaded;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback onPreview;
  final VoidCallback onRate;

  const _MarketplaceTemplateCard({
    required this.template,
    required this.isDownloaded,
    required this.isDownloading,
    required this.onDownload,
    required this.onPreview,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1a1a20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: template.isFeatured
            ? const BorderSide(color: Color(0xFFffd700), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onPreview,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 12),

              // Description
              Expanded(
                child: Text(
                  template.template.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Tags
              if (template.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildTags(),
              ],

              const SizedBox(height: 12),

              // Stats
              _buildStats(),
              const SizedBox(height: 12),

              // Actions
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _categoryColor(template.template.category).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _categoryIcon(template.template.category),
            color: _categoryColor(template.template.category),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.template.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (template.isVerified)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.verified, size: 16, color: Color(0xFF4a9eff)),
                    ),
                  if (template.isFeatured)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.star, size: 16, color: Color(0xFFffd700)),
                    ),
                ],
              ),
              Text(
                template.authorName,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTags() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: template.tags.take(3).map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            icon: Icons.download,
            value: _formatNumber(template.downloadCount),
          ),
          GestureDetector(
            onTap: onRate,
            child: _StatItem(
              icon: Icons.star,
              value: template.averageRating.toStringAsFixed(1),
              iconColor: const Color(0xFFffd700),
            ),
          ),
          _StatItem(
            icon: Icons.grid_view,
            value: '${template.template.reelCount}x${template.template.rowCount}',
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isDownloading || isDownloaded ? null : onDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDownloaded
                  ? const Color(0xFF40ff90).withValues(alpha: 0.2)
                  : const Color(0xFF4a9eff),
              foregroundColor: isDownloaded ? const Color(0xFF40ff90) : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            icon: isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isDownloaded ? Icons.check : Icons.download, size: 18),
            label: Text(isDownloaded ? 'Downloaded' : 'Download'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onPreview,
          icon: const Icon(Icons.visibility, size: 20),
          tooltip: 'Preview',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }

  Color _categoryColor(TemplateCategory category) {
    return switch (category) {
      TemplateCategory.classic => const Color(0xFF4a9eff),
      TemplateCategory.video => const Color(0xFF40ff90),
      TemplateCategory.megaways => const Color(0xFFff9040),
      TemplateCategory.cluster => const Color(0xFF9370db),
      TemplateCategory.holdWin => const Color(0xFF40c8ff),
      TemplateCategory.jackpot => const Color(0xFFffd700),
      TemplateCategory.branded => const Color(0xFFff6b6b),
      TemplateCategory.custom => const Color(0xFF808080),
    };
  }

  IconData _categoryIcon(TemplateCategory category) {
    return switch (category) {
      TemplateCategory.classic => Icons.grid_3x3,
      TemplateCategory.video => Icons.play_circle_outline,
      TemplateCategory.megaways => Icons.auto_graph,
      TemplateCategory.cluster => Icons.bubble_chart,
      TemplateCategory.holdWin => Icons.lock,
      TemplateCategory.jackpot => Icons.emoji_events,
      TemplateCategory.branded => Icons.star,
      TemplateCategory.custom => Icons.settings,
    };
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? iconColor;

  const _StatItem({
    required this.icon,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? Colors.white.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
