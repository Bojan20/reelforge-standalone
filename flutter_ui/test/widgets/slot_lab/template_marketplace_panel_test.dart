/// Template Marketplace Panel Tests
///
/// Tests for the marketplace service and panel components.
/// Tests cover template browsing, filtering, rating, and download.

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge_ui/models/template_models.dart';
import 'package:fluxforge_ui/widgets/slot_lab/template_marketplace_panel.dart';

void main() {
  group('MarketplaceTemplate', () {
    test('creates from valid JSON', () {
      final json = {
        'id': 'test_template',
        'template': {
          'id': 'inner_template',
          'name': 'Test Template',
          'version': '1.0.0',
          'category': 'classic',
          'description': 'A test template',
          'symbols': [],
          'winTiers': [],
          'coreStages': [],
          'duckingRules': [],
          'aleContexts': [],
          'winMultiplierRtpc': {
            'name': 'win_mult',
            'min': 0,
            'max': 100,
          },
        },
        'authorId': 'author_1',
        'authorName': 'Test Author',
        'publishedAt': '2026-02-02T12:00:00.000Z',
        'downloadCount': 100,
        'averageRating': 4.5,
        'ratingCount': 20,
        'tags': ['test', 'sample'],
        'isVerified': true,
        'isFeatured': false,
      };

      final template = MarketplaceTemplate.fromJson(json);

      expect(template.id, 'test_template');
      expect(template.authorId, 'author_1');
      expect(template.authorName, 'Test Author');
      expect(template.downloadCount, 100);
      expect(template.averageRating, 4.5);
      expect(template.ratingCount, 20);
      expect(template.tags, ['test', 'sample']);
      expect(template.isVerified, true);
      expect(template.isFeatured, false);
      expect(template.template.name, 'Test Template');
    });

    test('toJson serializes all fields', () {
      final template = MarketplaceTemplate(
        id: 'serialize_test',
        template: SlotTemplate(
          id: 'inner',
          name: 'Inner Template',
          version: '1.0.0',
          category: TemplateCategory.megaways,
          description: 'Inner description',
          symbols: const [],
          winTiers: const [],
          coreStages: const [],
          duckingRules: const [],
          aleContexts: const [],
          winMultiplierRtpc: const TemplateRtpcDefinition(
            name: 'rtpc',
            min: 0,
            max: 100,
          ),
        ),
        authorId: 'author_x',
        authorName: 'Author X',
        publishedAt: DateTime(2026, 2, 2),
        downloadCount: 500,
        averageRating: 4.8,
        ratingCount: 50,
        tags: ['megaways', 'cascade'],
        isVerified: true,
        isFeatured: true,
      );

      final json = template.toJson();

      expect(json['id'], 'serialize_test');
      expect(json['authorId'], 'author_x');
      expect(json['authorName'], 'Author X');
      expect(json['downloadCount'], 500);
      expect(json['averageRating'], 4.8);
      expect(json['ratingCount'], 50);
      expect(json['tags'], ['megaways', 'cascade']);
      expect(json['isVerified'], true);
      expect(json['isFeatured'], true);
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 'minimal_template',
        'template': {
          'id': 'inner',
          'name': 'Minimal',
          'version': '1.0.0',
          'category': 'classic',
          'description': 'Minimal template',
          'symbols': [],
          'winTiers': [],
          'coreStages': [],
          'duckingRules': [],
          'aleContexts': [],
          'winMultiplierRtpc': {
            'name': 'rtpc',
            'min': 0,
            'max': 100,
          },
        },
        'authorId': 'author',
        'authorName': 'Author',
        'publishedAt': '2026-01-01T00:00:00.000Z',
      };

      final template = MarketplaceTemplate.fromJson(json);

      expect(template.downloadCount, 0);
      expect(template.averageRating, 0.0);
      expect(template.ratingCount, 0);
      expect(template.tags, isEmpty);
      expect(template.thumbnailUrl, isNull);
      expect(template.isVerified, false);
      expect(template.isFeatured, false);
    });
  });

  group('TemplateRating', () {
    test('creates rating with required fields', () {
      final rating = TemplateRating(
        templateId: 'template_1',
        userId: 'user_1',
        stars: 5,
        createdAt: DateTime.now(),
      );

      expect(rating.templateId, 'template_1');
      expect(rating.userId, 'user_1');
      expect(rating.stars, 5);
      expect(rating.comment, isNull);
    });

    test('serializes and deserializes correctly', () {
      final original = TemplateRating(
        templateId: 'template_1',
        userId: 'user_1',
        stars: 4,
        comment: 'Great template!',
        createdAt: DateTime(2026, 2, 2, 12, 0, 0),
      );

      final json = original.toJson();
      final restored = TemplateRating.fromJson(json);

      expect(restored.templateId, original.templateId);
      expect(restored.userId, original.userId);
      expect(restored.stars, original.stars);
      expect(restored.comment, original.comment);
    });
  });

  group('MarketplaceSortBy', () {
    test('all sort options have labels and icons', () {
      for (final sortBy in MarketplaceSortBy.values) {
        expect(sortBy.label.isNotEmpty, true);
        expect(sortBy.icon, isNotNull);
      }
    });

    test('enum values are as expected', () {
      expect(MarketplaceSortBy.values.length, 4);
      expect(MarketplaceSortBy.newest.label, 'Newest');
      expect(MarketplaceSortBy.popular.label, 'Popular');
      expect(MarketplaceSortBy.topRated.label, 'Top Rated');
      expect(MarketplaceSortBy.mostDownloaded.label, 'Most Downloaded');
    });
  });

  group('MarketplaceService', () {
    test('singleton instance exists', () {
      final service = MarketplaceService.instance;
      expect(service, isNotNull);
      expect(MarketplaceService.instance, same(service));
    });

    test('initialize loads sample templates', () async {
      final service = MarketplaceService.instance;

      await service.initialize();

      expect(service.isLoading, false);
      expect(service.error, isNull);

      final templates = service.getTemplates();
      expect(templates.isNotEmpty, true);
    });

    test('getTemplates filters by category', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final allTemplates = service.getTemplates();
      final classicTemplates = service.getTemplates(
        category: TemplateCategory.classic,
      );

      expect(classicTemplates.length, lessThanOrEqualTo(allTemplates.length));

      for (final template in classicTemplates) {
        expect(template.template.category, TemplateCategory.classic);
      }
    });

    test('getTemplates filters by search query', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final egyptianTemplates = service.getTemplates(
        searchQuery: 'egyptian',
      );

      // Should find templates matching search
      for (final template in egyptianTemplates) {
        final nameMatch = template.template.name.toLowerCase().contains('egyptian');
        final descMatch = template.template.description.toLowerCase().contains('egyptian');
        final tagMatch = template.tags.any((t) => t.toLowerCase().contains('egyptian'));
        final authorMatch = template.authorName.toLowerCase().contains('egyptian');

        expect(nameMatch || descMatch || tagMatch || authorMatch, true);
      }
    });

    test('getTemplates sorts by popularity', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final templates = service.getTemplates(
        sortBy: MarketplaceSortBy.popular,
      );

      if (templates.length > 1) {
        for (int i = 0; i < templates.length - 1; i++) {
          expect(
            templates[i].downloadCount,
            greaterThanOrEqualTo(templates[i + 1].downloadCount),
          );
        }
      }
    });

    test('getTemplates sorts by rating', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final templates = service.getTemplates(
        sortBy: MarketplaceSortBy.topRated,
      );

      if (templates.length > 1) {
        for (int i = 0; i < templates.length - 1; i++) {
          expect(
            templates[i].averageRating,
            greaterThanOrEqualTo(templates[i + 1].averageRating),
          );
        }
      }
    });

    test('getFeaturedTemplates returns only featured', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final featured = service.getFeaturedTemplates();

      for (final template in featured) {
        expect(template.isFeatured, true);
      }
    });

    test('downloadTemplate updates download count', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final templates = service.getTemplates();
      if (templates.isEmpty) return;

      final template = templates.first;
      final originalCount = template.downloadCount;

      await service.downloadTemplate(template.id);

      final updatedTemplates = service.getTemplates();
      final updated = updatedTemplates.firstWhere((t) => t.id == template.id);

      expect(updated.downloadCount, originalCount + 1);
    });

    test('isDownloaded tracks downloaded templates', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final templates = service.getTemplates();
      if (templates.isEmpty) return;

      final template = templates.first;

      // Download the template
      await service.downloadTemplate(template.id);

      expect(service.isDownloaded(template.id), true);
    });

    test('rateTemplate updates average rating', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final templates = service.getTemplates();
      if (templates.isEmpty) return;

      final template = templates.first;

      await service.rateTemplate(
        templateId: template.id,
        stars: 5,
        comment: 'Excellent!',
      );

      final ratings = service.getRatings(template.id);
      expect(ratings.isNotEmpty, true);
      expect(ratings.last.stars, 5);
      expect(ratings.last.comment, 'Excellent!');
    });

    test('rateTemplate throws for invalid stars', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final templates = service.getTemplates();
      if (templates.isEmpty) return;

      expect(
        () => service.rateTemplate(
          templateId: templates.first.id,
          stars: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.rateTemplate(
          templateId: templates.first.id,
          stars: 6,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('uploadTemplate adds to local cache', () async {
      final service = MarketplaceService.instance;
      await service.initialize();

      final initialCount = service.getTemplates().length;

      final newTemplate = SlotTemplate(
        id: 'user_template',
        name: 'User Created Template',
        version: '1.0.0',
        category: TemplateCategory.custom,
        description: 'A user-created template',
        symbols: const [],
        winTiers: const [],
        coreStages: const [],
        duckingRules: const [],
        aleContexts: const [],
        winMultiplierRtpc: const TemplateRtpcDefinition(
          name: 'rtpc',
          min: 0,
          max: 100,
        ),
      );

      final id = await service.uploadTemplate(newTemplate);

      expect(id.isNotEmpty, true);
      expect(service.getTemplates().length, initialCount + 1);
    });
  });
}
