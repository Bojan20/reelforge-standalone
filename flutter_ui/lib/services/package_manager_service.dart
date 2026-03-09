/// Package Manager Service (#33)
/// Marketplace for scripts, effects, themes. Auto-update. Custom repositories.
library;

import 'package:flutter/foundation.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

/// Package content type
enum PackageType {
  dspScript,
  effect,
  theme,
  preset,
  template,
  extension,
}

extension PackageTypeX on PackageType {
  String get label => switch (this) {
    PackageType.dspScript => 'DSP Script',
    PackageType.effect => 'Effect',
    PackageType.theme => 'Theme',
    PackageType.preset => 'Preset',
    PackageType.template => 'Template',
    PackageType.extension => 'Extension',
  };
  String get pluralLabel => switch (this) {
    PackageType.dspScript => 'DSP Scripts',
    PackageType.effect => 'Effects',
    PackageType.theme => 'Themes',
    PackageType.preset => 'Presets',
    PackageType.template => 'Templates',
    PackageType.extension => 'Extensions',
  };
}

/// Package installation status
enum PackageStatus {
  available,
  installed,
  updateAvailable,
  installing,
  uninstalling,
}

extension PackageStatusX on PackageStatus {
  String get label => switch (this) {
    PackageStatus.available => 'Available',
    PackageStatus.installed => 'Installed',
    PackageStatus.updateAvailable => 'Update',
    PackageStatus.installing => 'Installing...',
    PackageStatus.uninstalling => 'Removing...',
  };
}

/// Package source
enum PackageSource {
  builtIn,
  official,
  community,
  custom,
}

extension PackageSourceX on PackageSource {
  String get label => switch (this) {
    PackageSource.builtIn => 'Built-in',
    PackageSource.official => 'Official',
    PackageSource.community => 'Community',
    PackageSource.custom => 'Custom',
  };
}

/// Sort order for package list
enum PackageSortOrder {
  nameAsc,
  nameDesc,
  dateNewest,
  dateOldest,
  rating,
  downloads,
}

extension PackageSortOrderX on PackageSortOrder {
  String get label => switch (this) {
    PackageSortOrder.nameAsc => 'Name (A-Z)',
    PackageSortOrder.nameDesc => 'Name (Z-A)',
    PackageSortOrder.dateNewest => 'Newest First',
    PackageSortOrder.dateOldest => 'Oldest First',
    PackageSortOrder.rating => 'Top Rated',
    PackageSortOrder.downloads => 'Most Popular',
  };
}

// ─── Models ──────────────────────────────────────────────────────────────────

/// A repository source for packages
class PackageRepository {
  final String id;
  final String name;
  final String url;
  final PackageSource source;
  final bool enabled;
  final DateTime? lastSync;

  const PackageRepository({
    required this.id,
    required this.name,
    required this.url,
    required this.source,
    this.enabled = true,
    this.lastSync,
  });

  PackageRepository copyWith({
    String? id,
    String? name,
    String? url,
    PackageSource? source,
    bool? enabled,
    DateTime? lastSync,
  }) {
    return PackageRepository(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      source: source ?? this.source,
      enabled: enabled ?? this.enabled,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

/// A single package in the marketplace
class Package {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final PackageType type;
  final PackageSource source;
  final PackageStatus status;
  final String repositoryId;
  final DateTime publishedAt;
  final DateTime? updatedAt;
  final double rating; // 0.0 - 5.0
  final int downloads;
  final int sizeBytes;
  final List<String> tags;
  final List<String> dependencies;
  final String? changelog;
  final String? homepage;
  final String? license;
  final String? installedVersion;

  const Package({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.type,
    required this.source,
    this.status = PackageStatus.available,
    required this.repositoryId,
    required this.publishedAt,
    this.updatedAt,
    this.rating = 0.0,
    this.downloads = 0,
    this.sizeBytes = 0,
    this.tags = const [],
    this.dependencies = const [],
    this.changelog,
    this.homepage,
    this.license,
    this.installedVersion,
  });

  bool get isInstalled => status == PackageStatus.installed || status == PackageStatus.updateAvailable;
  bool get hasUpdate => status == PackageStatus.updateAvailable;
  bool get isBuiltIn => source == PackageSource.builtIn;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static const _unset = Object();

  /// copyWith with sentinel pattern for nullable fields.
  /// Pass explicit `null` to clear installedVersion/updatedAt/changelog/homepage/license.
  Package copyWith({
    String? id,
    String? name,
    String? description,
    String? author,
    String? version,
    PackageType? type,
    PackageSource? source,
    PackageStatus? status,
    String? repositoryId,
    DateTime? publishedAt,
    Object? updatedAt = _unset,
    double? rating,
    int? downloads,
    int? sizeBytes,
    List<String>? tags,
    List<String>? dependencies,
    Object? changelog = _unset,
    Object? homepage = _unset,
    Object? license = _unset,
    Object? installedVersion = _unset,
  }) {
    return Package(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      version: version ?? this.version,
      type: type ?? this.type,
      source: source ?? this.source,
      status: status ?? this.status,
      repositoryId: repositoryId ?? this.repositoryId,
      publishedAt: publishedAt ?? this.publishedAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime?,
      rating: rating ?? this.rating,
      downloads: downloads ?? this.downloads,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      tags: tags ?? this.tags,
      dependencies: dependencies ?? this.dependencies,
      changelog: changelog == _unset ? this.changelog : changelog as String?,
      homepage: homepage == _unset ? this.homepage : homepage as String?,
      license: license == _unset ? this.license : license as String?,
      installedVersion: installedVersion == _unset ? this.installedVersion : installedVersion as String?,
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class PackageManagerService extends ChangeNotifier {
  PackageManagerService._();
  static final instance = PackageManagerService._();

  final List<PackageRepository> _repositories = [];
  final List<Package> _packages = [];
  final Set<String> _pendingOps = {}; // Guard against duplicate install/uninstall

  // Filters
  PackageType? _filterType;
  PackageSource? _filterSource;
  PackageStatus? _filterStatus;
  PackageSortOrder _sortOrder = PackageSortOrder.nameAsc;
  String _searchQuery = '';
  String? _selectedPackageId;

  // Getters
  List<PackageRepository> get repositories => List.unmodifiable(_repositories);
  PackageType? get filterType => _filterType;
  PackageSource? get filterSource => _filterSource;
  PackageStatus? get filterStatus => _filterStatus;
  PackageSortOrder get sortOrder => _sortOrder;
  String get searchQuery => _searchQuery;
  String? get selectedPackageId => _selectedPackageId;

  Package? get selectedPackage {
    if (_selectedPackageId == null) return null;
    final idx = _packages.indexWhere((p) => p.id == _selectedPackageId);
    return idx >= 0 ? _packages[idx] : null;
  }

  int get installedCount => _packages.where((p) => p.isInstalled).length;
  int get updatesCount => _packages.where((p) => p.hasUpdate).length;
  int get totalCount => _packages.length;

  /// Filtered and sorted package list
  List<Package> get filteredPackages {
    var result = List<Package>.from(_packages);

    // Type filter
    if (_filterType != null) {
      result = result.where((p) => p.type == _filterType).toList();
    }

    // Source filter
    if (_filterSource != null) {
      result = result.where((p) => p.source == _filterSource).toList();
    }

    // Status filter
    if (_filterStatus != null) {
      switch (_filterStatus!) {
        case PackageStatus.installed:
          result = result.where((p) => p.isInstalled).toList();
        case PackageStatus.available:
          result = result.where((p) => !p.isInstalled).toList();
        case PackageStatus.updateAvailable:
          result = result.where((p) => p.hasUpdate).toList();
        default:
          break;
      }
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q) ||
        p.author.toLowerCase().contains(q) ||
        p.tags.any((t) => t.toLowerCase().contains(q))
      ).toList();
    }

    // Sort
    switch (_sortOrder) {
      case PackageSortOrder.nameAsc:
        result.sort((a, b) => a.name.compareTo(b.name));
      case PackageSortOrder.nameDesc:
        result.sort((a, b) => b.name.compareTo(a.name));
      case PackageSortOrder.dateNewest:
        result.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      case PackageSortOrder.dateOldest:
        result.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
      case PackageSortOrder.rating:
        result.sort((a, b) => b.rating.compareTo(a.rating));
      case PackageSortOrder.downloads:
        result.sort((a, b) => b.downloads.compareTo(a.downloads));
    }

    return result;
  }

  // ─── Mutations ─────────────────────────────────────────────────────────────

  void setFilterType(PackageType? type) {
    _filterType = type;
    notifyListeners();
  }

  void setFilterSource(PackageSource? source) {
    _filterSource = source;
    notifyListeners();
  }

  void setFilterStatus(PackageStatus? status) {
    _filterStatus = status;
    notifyListeners();
  }

  void setSortOrder(PackageSortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectPackage(String? id) {
    _selectedPackageId = id;
    notifyListeners();
  }

  /// Install a package
  void installPackage(String id) {
    if (_pendingOps.contains(id)) return;
    final idx = _packages.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final pkg = _packages[idx];
    if (pkg.isInstalled && !pkg.hasUpdate) return;

    _pendingOps.add(id);
    _packages[idx] = pkg.copyWith(status: PackageStatus.installing);
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 800), () {
      _pendingOps.remove(id);
      final current = _packages.indexWhere((p) => p.id == id);
      if (current < 0) return;
      _packages[current] = _packages[current].copyWith(
        status: PackageStatus.installed,
        installedVersion: _packages[current].version,
      );
      notifyListeners();
    });
  }

  /// Uninstall a package
  void uninstallPackage(String id) {
    if (_pendingOps.contains(id)) return;
    final idx = _packages.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final pkg = _packages[idx];
    if (!pkg.isInstalled || pkg.isBuiltIn) return;

    _pendingOps.add(id);
    _packages[idx] = pkg.copyWith(status: PackageStatus.uninstalling);
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 500), () {
      _pendingOps.remove(id);
      final current = _packages.indexWhere((p) => p.id == id);
      if (current < 0) return;
      _packages[current] = _packages[current].copyWith(
        status: PackageStatus.available,
        installedVersion: null,
      );
      notifyListeners();
    });
  }

  /// Update a package (reinstall latest version)
  void updatePackage(String id) {
    installPackage(id);
  }

  /// Update all packages with available updates
  void updateAll() {
    for (final pkg in _packages.where((p) => p.hasUpdate).toList()) {
      installPackage(pkg.id);
    }
  }

  // ─── Repository Management ─────────────────────────────────────────────────

  void addRepository(PackageRepository repo) {
    if (_repositories.any((r) => r.id == repo.id)) return;
    _repositories.add(repo);
    notifyListeners();
  }

  void removeRepository(String id) {
    _repositories.removeWhere((r) => r.id == id);
    _packages.removeWhere((p) => p.repositoryId == id);
    notifyListeners();
  }

  void toggleRepository(String id) {
    final idx = _repositories.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    _repositories[idx] = _repositories[idx].copyWith(enabled: !_repositories[idx].enabled);
    notifyListeners();
  }

  /// Sync all enabled repositories (simulated)
  void syncRepositories() {
    for (int i = 0; i < _repositories.length; i++) {
      if (_repositories[i].enabled) {
        _repositories[i] = _repositories[i].copyWith(lastSync: DateTime.now());
      }
    }
    notifyListeners();
  }

  // ─── Built-in Packages ─────────────────────────────────────────────────────

  /// Load factory packages
  void loadFactoryPackages() {
    if (_packages.isNotEmpty || _repositories.isNotEmpty) return;

    // Default repository
    _repositories.addAll([
      PackageRepository(
        id: 'builtin',
        name: 'FluxForge Built-in',
        url: 'local://builtin',
        source: PackageSource.builtIn,
        lastSync: DateTime.now(),
      ),
      PackageRepository(
        id: 'official',
        name: 'FluxForge Official',
        url: 'https://packages.fluxforge.dev',
        source: PackageSource.official,
        lastSync: DateTime.now(),
      ),
      PackageRepository(
        id: 'community',
        name: 'Community Hub',
        url: 'https://community.fluxforge.dev/packages',
        source: PackageSource.community,
        lastSync: DateTime.now(),
      ),
    ]);

    final now = DateTime.now();
    _packages.addAll([
      // Built-in DSP scripts
      Package(
        id: 'builtin-gain',
        name: 'Gain/Trim',
        description: 'Simple gain/trim utility with dB readout and phase invert.',
        author: 'FluxForge',
        version: '1.0.0',
        type: PackageType.dspScript,
        source: PackageSource.builtIn,
        status: PackageStatus.installed,
        repositoryId: 'builtin',
        publishedAt: now.subtract(const Duration(days: 90)),
        rating: 4.8,
        downloads: 15200,
        sizeBytes: 2048,
        tags: ['utility', 'gain', 'trim'],
        installedVersion: '1.0.0',
      ),
      Package(
        id: 'builtin-stereo-pan',
        name: 'Stereo Pan Law',
        description: 'Constant-power stereo panning with selectable pan law (-3dB, -4.5dB, -6dB).',
        author: 'FluxForge',
        version: '1.0.0',
        type: PackageType.dspScript,
        source: PackageSource.builtIn,
        status: PackageStatus.installed,
        repositoryId: 'builtin',
        publishedAt: now.subtract(const Duration(days: 90)),
        rating: 4.5,
        downloads: 8700,
        sizeBytes: 3072,
        tags: ['utility', 'pan', 'stereo'],
        installedVersion: '1.0.0',
      ),
      Package(
        id: 'builtin-test-osc',
        name: 'Test Oscillator',
        description: 'Sine/square/saw/noise test signal generator with frequency and level controls.',
        author: 'FluxForge',
        version: '1.0.0',
        type: PackageType.dspScript,
        source: PackageSource.builtIn,
        status: PackageStatus.installed,
        repositoryId: 'builtin',
        publishedAt: now.subtract(const Duration(days: 90)),
        rating: 4.3,
        downloads: 6100,
        sizeBytes: 4096,
        tags: ['utility', 'test', 'generator'],
        installedVersion: '1.0.0',
      ),

      // Official packages
      Package(
        id: 'off-vocal-strip',
        name: 'Vocal Channel Strip',
        description: 'Complete vocal processing chain: HPF → DeEsser → Comp → EQ → Saturation → Reverb send.',
        author: 'FluxForge',
        version: '2.1.0',
        type: PackageType.preset,
        source: PackageSource.official,
        status: PackageStatus.available,
        repositoryId: 'official',
        publishedAt: now.subtract(const Duration(days: 30)),
        updatedAt: now.subtract(const Duration(days: 5)),
        rating: 4.9,
        downloads: 24300,
        sizeBytes: 12288,
        tags: ['vocal', 'channel strip', 'mixing'],
        license: 'MIT',
      ),
      Package(
        id: 'off-drum-templates',
        name: 'Drum Recording Templates',
        description: '8 track templates for drum recording: kick, snare top/bottom, hat, OH L/R, room, mono room.',
        author: 'FluxForge',
        version: '1.3.0',
        type: PackageType.template,
        source: PackageSource.official,
        status: PackageStatus.available,
        repositoryId: 'official',
        publishedAt: now.subtract(const Duration(days: 60)),
        rating: 4.7,
        downloads: 18600,
        sizeBytes: 45056,
        tags: ['drums', 'recording', 'template'],
        license: 'MIT',
      ),
      Package(
        id: 'off-mastering-chain',
        name: 'Mastering FX Chain',
        description: 'Mastering-grade processing: EQ → Multiband Comp → Stereo Imager → Limiter with K-14 target.',
        author: 'FluxForge',
        version: '1.5.0',
        type: PackageType.effect,
        source: PackageSource.official,
        status: PackageStatus.installed,
        repositoryId: 'official',
        publishedAt: now.subtract(const Duration(days: 45)),
        rating: 4.8,
        downloads: 31200,
        sizeBytes: 28672,
        tags: ['mastering', 'chain', 'loudness'],
        license: 'MIT',
        installedVersion: '1.4.0',
      ),
      Package(
        id: 'off-dark-theme',
        name: 'Midnight Dark Theme',
        description: 'Ultra-dark color scheme optimized for low-light studio environments. OLED-friendly.',
        author: 'FluxForge',
        version: '1.1.0',
        type: PackageType.theme,
        source: PackageSource.official,
        status: PackageStatus.available,
        repositoryId: 'official',
        publishedAt: now.subtract(const Duration(days: 20)),
        rating: 4.6,
        downloads: 9800,
        sizeBytes: 8192,
        tags: ['theme', 'dark', 'oled'],
        license: 'MIT',
      ),

      // Community packages
      Package(
        id: 'com-lofi-fx',
        name: 'Lo-Fi FX Suite',
        description: 'Bitcrusher, vinyl noise, wow/flutter, tape saturation. All in one DSP script.',
        author: 'chillbeats_dev',
        version: '0.9.2',
        type: PackageType.dspScript,
        source: PackageSource.community,
        status: PackageStatus.available,
        repositoryId: 'community',
        publishedAt: now.subtract(const Duration(days: 15)),
        rating: 4.4,
        downloads: 3200,
        sizeBytes: 6144,
        tags: ['lo-fi', 'bitcrusher', 'vinyl', 'tape'],
        license: 'MIT',
        homepage: 'https://github.com/chillbeats/lofi-fx',
      ),
      Package(
        id: 'com-game-audio-presets',
        name: 'Game Audio Preset Pack',
        description: '50+ presets for game audio: UI sounds, footsteps, ambience, weapons, explosions.',
        author: 'gameaudio_collective',
        version: '1.2.0',
        type: PackageType.preset,
        source: PackageSource.community,
        status: PackageStatus.available,
        repositoryId: 'community',
        publishedAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 3)),
        rating: 4.7,
        downloads: 5400,
        sizeBytes: 102400,
        tags: ['game audio', 'presets', 'sfx'],
        license: 'CC-BY-4.0',
      ),
      Package(
        id: 'com-spectral-gate',
        name: 'Spectral Gate',
        description: 'FFT-based spectral noise gate with per-band threshold. 1024-point FFT, 50% overlap.',
        author: 'dsp_wizard',
        version: '0.7.0',
        type: PackageType.dspScript,
        source: PackageSource.community,
        status: PackageStatus.available,
        repositoryId: 'community',
        publishedAt: now.subtract(const Duration(days: 25)),
        rating: 4.2,
        downloads: 1800,
        sizeBytes: 8192,
        tags: ['spectral', 'gate', 'noise reduction', 'fft'],
        license: 'GPL-3.0',
      ),
      Package(
        id: 'com-wwise-export',
        name: 'Wwise Export Extension',
        description: 'Export stems with Wwise-compatible naming, metadata, and SoundBank structure.',
        author: 'middleware_tools',
        version: '1.0.0',
        type: PackageType.extension,
        source: PackageSource.community,
        status: PackageStatus.available,
        repositoryId: 'community',
        publishedAt: now.subtract(const Duration(days: 40)),
        rating: 4.5,
        downloads: 4100,
        sizeBytes: 32768,
        tags: ['wwise', 'export', 'middleware', 'game audio'],
        license: 'MIT',
      ),
    ]);

    // Mark mastering chain as having update
    final masteringIdx = _packages.indexWhere((p) => p.id == 'off-mastering-chain');
    if (masteringIdx >= 0) {
      _packages[masteringIdx] = _packages[masteringIdx].copyWith(
        status: PackageStatus.updateAvailable,
      );
    }

    notifyListeners();
  }

  /// Callback for external actions (install/uninstall hooks)
  void Function(String packageId, String action)? onPackageAction;
}
