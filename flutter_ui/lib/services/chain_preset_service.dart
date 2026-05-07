/// Chain Preset Service — user-owned chain preset library (Wave 2 Front 5).
///
/// Thin Flutter wrapper around the Rust `chain_preset_ffi` layer. Maintains
/// an in-memory cached metadata list (refreshed on every mutating op) so
/// browsers can paint without going to disk on every frame.
///
/// Usage:
///   final svc = ChainPresetService.instance;
///   await svc.refresh();                                  // populate cache
///   final result = svc.save(name, description, tags, snapshot);
///   final preset = svc.load("My Vocal Master");
///   final metas = svc.search("vocal");
///   svc.delete("Old Preset");
///
/// All FFI calls are synchronous (Rust is fast for these — flat JSON files,
/// no network), but the service is exposed via `Future<...>` for forward
/// compatibility with isolates and to keep call-sites async-clean.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/chain_preset.dart';
import '../src/rust/native_ffi.dart' show NativeFFI;

/// Outcome of `delete` so call-sites can disambiguate "removed" vs
/// "didn't exist" vs "errored" without inspecting raw `int`.
enum ChainPresetDeleteResult {
  removed,
  notFound,
  error,
}

class ChainPresetService extends ChangeNotifier {
  ChainPresetService._();
  static final ChainPresetService instance = ChainPresetService._();

  /// Last-known metadata list (sorted by `updated_ms` descending).
  /// Refreshed on every mutating operation; populate explicitly via
  /// [refresh] on first use.
  List<ChainPresetMeta> _presets = const [];
  List<ChainPresetMeta> get presets => List.unmodifiable(_presets);

  /// Wave 2 Front 6 — cached union of every tag in the library
  /// (lowercase, sorted). Refreshed alongside [_presets] in [refresh].
  List<String> _allTags = const [];
  List<String> get allTags => List.unmodifiable(_allTags);

  /// Wave 2 Front 6 — cached union of canonical + user-defined
  /// categories (canonicals first). Refreshed alongside [_presets].
  List<String> _allCategories = const [];
  List<String> get allCategories => List.unmodifiable(_allCategories);

  /// Cached resolved preset directory (echoed by `chain_preset_set_dir` /
  /// `chain_preset_get_dir`). Empty until first call.
  String _resolvedDir = '';
  String get resolvedDir => _resolvedDir;

  /// Last error message from any FFI call, or null. Cleared on next
  /// successful operation.
  String? _lastError;
  String? get lastError => _lastError;

  // ─── Directory management ──────────────────────────────────────────────

  /// Override the active store directory. Pass empty string to reset to
  /// env / `$HOME/.fluxforge/chains`. Refreshes the metadata list.
  Future<ChainPresetOpResult> setDir(String path) async {
    final raw = NativeFFI.instance.chainPresetSetDir(path);
    final result = _parseOpResult(raw, fallback: 'set_dir returned null');
    if (result.ok) {
      _resolvedDir = result.path;
      _lastError = null;
      await refresh();
    } else {
      _lastError = result.error;
      notifyListeners();
    }
    return result;
  }

  /// Read the currently-resolved store directory.
  Future<ChainPresetOpResult> getDir() async {
    final raw = NativeFFI.instance.chainPresetGetDir();
    final result = _parseOpResult(raw, fallback: 'get_dir returned null');
    if (result.ok) {
      _resolvedDir = result.path;
    }
    return result;
  }

  // ─── Library refresh ───────────────────────────────────────────────────

  /// Re-read the metadata list from disk. Called automatically after every
  /// mutating op; expose so first-mount UIs can populate the cache.
  ///
  /// Refreshes [presets], [allTags] and [allCategories] in one shot —
  /// the FFI calls are cheap (flat-file scan, <10ms typical) so paying
  /// the extra two roundtrips here keeps the chip strip in sync without
  /// every UI surface having to remember to refresh tags/categories.
  Future<void> refresh() async {
    final raw = NativeFFI.instance.chainPresetListJson();
    _presets = _parseList(raw);

    final tagsRaw = NativeFFI.instance.chainPresetListTags();
    _allTags = _parseStringItems(tagsRaw);

    final catsRaw = NativeFFI.instance.chainPresetListCategories();
    _allCategories = _parseStringItems(catsRaw);

    notifyListeners();
  }

  /// Filtered metadata (same shape as cache, but query-scoped).
  /// Empty query returns full list. Does NOT mutate the cache.
  Future<List<ChainPresetMeta>> search(String query) async {
    if (query.trim().isEmpty) return presets;
    final raw = NativeFFI.instance.chainPresetSearchJson(query);
    return _parseList(raw);
  }

  /// Wave 2 Front 6 — apply a structured filter. Empty filter returns
  /// the full cached list (no FFI roundtrip). Does NOT mutate the cache.
  Future<List<ChainPresetMeta>> filter(ChainPresetFilter spec) async {
    if (spec.isEmpty) return presets;
    final raw =
        NativeFFI.instance.chainPresetFilterJson(jsonEncode(spec.toJson()));
    return _parseList(raw);
  }

  // ─── Save / load / delete ──────────────────────────────────────────────

  /// Save a preset. Overwrites if a preset with the same slug exists
  /// (preserving `created_ms`). Refreshes the cache on success.
  ///
  /// `category` is optional and free-form; the Rust core normalises
  /// (trim + lowercase) on save. Pass `null` (or empty/whitespace) for
  /// un-classified presets.
  Future<ChainPresetOpResult> save({
    required String name,
    String description = '',
    String? category,
    List<String> tags = const [],
    required FullChainSnapshot snapshot,
  }) async {
    if (name.trim().isEmpty) {
      final err = ChainPresetOpResult.error('name is empty');
      _lastError = err.error;
      notifyListeners();
      return err;
    }
    final normCat = category == null ? null : normaliseChainCategory(category);
    final reqJson = jsonEncode({
      'name': name,
      'description': description,
      if (normCat != null) 'category': normCat,
      'tags': tags,
      'snapshot': snapshot.toJson(),
    });
    final raw = NativeFFI.instance.chainPresetSaveJson(reqJson);
    final result = _parseOpResult(raw, fallback: 'save returned null');
    if (result.ok) {
      _lastError = null;
      await refresh();
    } else {
      _lastError = result.error;
      notifyListeners();
    }
    return result;
  }

  /// Load a full preset by user-visible name. Returns null if missing or
  /// the FFI returned an error envelope (set [lastError] for diagnostics).
  Future<ChainPreset?> load(String name) async {
    if (name.trim().isEmpty) {
      _lastError = 'name is empty';
      notifyListeners();
      return null;
    }
    final raw = NativeFFI.instance.chainPresetLoadJson(name);
    if (raw == null) {
      _lastError = 'load returned null';
      notifyListeners();
      return null;
    }
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      _lastError = 'load: invalid JSON ($e)';
      notifyListeners();
      return null;
    }
    if (parsed['error'] != null) {
      _lastError = parsed['error'].toString();
      notifyListeners();
      return null;
    }
    try {
      _lastError = null;
      return ChainPreset.fromJson(parsed);
    } catch (e) {
      _lastError = 'load: parse error ($e)';
      notifyListeners();
      return null;
    }
  }

  /// Delete by name. Refreshes the cache on `removed`. `notFound` keeps
  /// the cache stable but still notifies (in case stale views need redraw).
  Future<ChainPresetDeleteResult> delete(String name) async {
    if (name.trim().isEmpty) {
      _lastError = 'name is empty';
      notifyListeners();
      return ChainPresetDeleteResult.error;
    }
    final code = NativeFFI.instance.chainPresetDelete(name);
    switch (code) {
      case 1:
        _lastError = null;
        await refresh();
        return ChainPresetDeleteResult.removed;
      case 0:
        _lastError = null;
        notifyListeners();
        return ChainPresetDeleteResult.notFound;
      default:
        _lastError = 'delete: native returned $code';
        notifyListeners();
        return ChainPresetDeleteResult.error;
    }
  }

  // ─── Export / import (for sharing) ─────────────────────────────────────

  /// Export a preset by name to an absolute file path.
  Future<ChainPresetOpResult> exportTo({
    required String name,
    required String destPath,
  }) async {
    if (name.trim().isEmpty || destPath.trim().isEmpty) {
      final err = ChainPresetOpResult.error('name or dest is empty');
      _lastError = err.error;
      notifyListeners();
      return err;
    }
    final reqJson = jsonEncode({'name': name, 'dest': destPath});
    final raw = NativeFFI.instance.chainPresetExportJson(reqJson);
    final result = _parseOpResult(raw, fallback: 'export returned null');
    if (!result.ok) {
      _lastError = result.error;
      notifyListeners();
    } else {
      _lastError = null;
    }
    return result;
  }

  /// Import a preset file from an absolute path. Refreshes the cache
  /// on success.
  Future<ChainPresetOpResult> importFrom(String sourcePath) async {
    if (sourcePath.trim().isEmpty) {
      final err = ChainPresetOpResult.error('source path is empty');
      _lastError = err.error;
      notifyListeners();
      return err;
    }
    final raw = NativeFFI.instance.chainPresetImportPath(sourcePath);
    final result = _parseOpResult(raw, fallback: 'import returned null');
    if (result.ok) {
      _lastError = null;
      await refresh();
    } else {
      _lastError = result.error;
      notifyListeners();
    }
    return result;
  }

  // ─── Internals ─────────────────────────────────────────────────────────

  ChainPresetOpResult _parseOpResult(String? raw, {required String fallback}) {
    if (raw == null) return ChainPresetOpResult.error(fallback);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ChainPresetOpResult.fromJson(j);
    } catch (e) {
      return ChainPresetOpResult.error('parse: $e');
    }
  }

  List<ChainPresetMeta> _parseList(String? raw) {
    if (raw == null) return const [];
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['error'] != null) {
        _lastError = j['error'].toString();
        return const [];
      }
      final arr = (j['presets'] as List<dynamic>?) ?? const [];
      return arr
          .map((e) => ChainPresetMeta.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      _lastError = 'list: parse error ($e)';
      return const [];
    }
  }

  /// Parse a `{"items": [...]}` envelope from `chain_preset_list_tags` /
  /// `chain_preset_list_categories`. Errors degrade to the canonical
  /// fallback (empty for tags, canonical-only for categories — the
  /// caller layers that on top).
  List<String> _parseStringItems(String? raw) {
    if (raw == null) return const [];
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['error'] != null) {
        _lastError = j['error'].toString();
        return const [];
      }
      final arr = (j['items'] as List<dynamic>?) ?? const [];
      return arr.map((e) => e.toString()).toList(growable: false);
    } catch (e) {
      _lastError = 'string list: parse error ($e)';
      return const [];
    }
  }
}
