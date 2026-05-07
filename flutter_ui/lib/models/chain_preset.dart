/// Chain preset domain models — Wave 2 Front 5 + Front 6 Flutter side.
///
/// Mirrors the Rust types in `crates/rf-ml/src/assistant/chain_preset.rs`
/// and `crates/rf-ml/src/assistant/chain_history.rs`. JSON shapes are
/// the canonical wire format for the `chain_preset_*` FFI surface.
///
/// Keep these models 1:1 with the Rust definitions — schema drift would
/// silently corrupt round-tripped presets.
///
/// Wave 2 Front 6 adds:
///   * `ChainPreset.category` / `ChainPresetMeta.category`
///   * [kCanonicalChainCategories] (mirrors `CANONICAL_CATEGORIES` in Rust)
///   * [ChainPresetFilter] (mirrors `PresetFilterSpec` in Rust)
library;

// ─── Canonical categories (mirror CANONICAL_CATEGORIES in Rust) ─────────────

/// The canonical mixing categories surfaced as the chip strip in the
/// library panel. Order is meaningful — UI renders left-to-right.
///
/// Must stay in lock-step with `CANONICAL_CATEGORIES` in
/// `crates/rf-ml/src/assistant/chain_preset.rs`. A drift here just
/// re-orders chips; a drift in spelling silently shifts a category to
/// the "user-defined" tail. Tests guard this.
const List<String> kCanonicalChainCategories = <String>[
  'vocal',
  'drums',
  'bass',
  'guitar',
  'synth',
  'instrument',
  'bus',
  'fx',
  'mix',
  'mastering',
];

/// Normalise a free-form category to the on-disk shape (trim + lowercase).
/// Returns `null` for empty / whitespace-only input.
String? normaliseChainCategory(String raw) {
  final n = raw.trim().toLowerCase();
  return n.isEmpty ? null : n;
}

/// True if [cat] (after trim/lowercase) matches a canonical category.
bool chainCategoryIsCanonical(String cat) {
  final n = normaliseChainCategory(cat);
  return n != null && kCanonicalChainCategories.contains(n);
}

// ─── Snapshot leaves (mirror chain_history.rs) ──────────────────────────────

/// One captured parameter value.
class SlotParamSnapshot {
  /// Raw parameter index (stable within a loaded processor).
  final int index;

  /// Display name at capture time ("Threshold", "Frequency", …).
  final String name;

  /// Normalised or raw value — whatever Rust `get_track_insert_param` returns.
  final double value;

  const SlotParamSnapshot({
    required this.index,
    required this.name,
    required this.value,
  });

  factory SlotParamSnapshot.fromJson(Map<String, dynamic> j) =>
      SlotParamSnapshot(
        index: (j['index'] as num).toInt(),
        name: (j['name'] as String?) ?? '',
        value: (j['value'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'value': value,
      };
}

/// One slot's full state at capture time.
class FullSlotSnapshot {
  final int slotIndex;

  /// Processor factory name ("compressor", "pro-eq", "fab-q-pro", …).
  final String processorName;

  final bool bypassed;

  /// Wet/dry mix (0.0–1.0).
  final double mix;

  /// All parameters captured in index order.
  final List<SlotParamSnapshot> params;

  const FullSlotSnapshot({
    required this.slotIndex,
    required this.processorName,
    required this.bypassed,
    required this.mix,
    required this.params,
  });

  factory FullSlotSnapshot.fromJson(Map<String, dynamic> j) => FullSlotSnapshot(
        slotIndex: (j['slot_index'] as num).toInt(),
        processorName: (j['processor_name'] as String?) ?? '',
        bypassed: (j['bypassed'] as bool?) ?? false,
        mix: (j['mix'] as num?)?.toDouble() ?? 1.0,
        params: ((j['params'] as List<dynamic>?) ?? const [])
            .map((p) => SlotParamSnapshot.fromJson(p as Map<String, dynamic>))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
        'slot_index': slotIndex,
        'processor_name': processorName,
        'bypassed': bypassed,
        'mix': mix,
        'params': params.map((p) => p.toJson()).toList(growable: false),
      };
}

/// Complete chain state for one track at one point in time.
class FullChainSnapshot {
  final int trackId;

  /// Loaded slots only (empty slots are not stored).
  final List<FullSlotSnapshot> slots;

  /// Human-readable label, e.g. "Apply Vocal Bright".
  final String label;

  /// Unix epoch milliseconds.
  final int timestampMs;

  const FullChainSnapshot({
    required this.trackId,
    required this.slots,
    required this.label,
    required this.timestampMs,
  });

  factory FullChainSnapshot.fromJson(Map<String, dynamic> j) =>
      FullChainSnapshot(
        trackId: (j['track_id'] as num).toInt(),
        slots: ((j['slots'] as List<dynamic>?) ?? const [])
            .map((s) => FullSlotSnapshot.fromJson(s as Map<String, dynamic>))
            .toList(growable: false),
        label: (j['label'] as String?) ?? '',
        timestampMs: (j['timestamp_ms'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'track_id': trackId,
        'slots': slots.map((s) => s.toJson()).toList(growable: false),
        'label': label,
        'timestamp_ms': timestampMs,
      };
}

// ─── Preset (full + meta) ───────────────────────────────────────────────────

/// One saved preset — full payload returned by `chain_preset_load_json`.
class ChainPreset {
  /// User-visible name (preserved exactly, including spaces/punctuation).
  final String name;

  /// Optional human description (a few sentences max — UI hint, not a doc).
  final String description;

  /// Single canonical mixing category (`vocal`, `drums`, `bus`, …).
  /// Always stored normalised (lowercase, trimmed). `null` for legacy
  /// or un-classified presets.
  final String? category;

  /// User-defined tags ("vocal", "vintage", "podcast"…).
  final List<String> tags;

  /// Captured chain state.
  final FullChainSnapshot snapshot;

  /// Schema version. Incremented when on-disk format changes.
  final int formatVersion;

  /// Created at — Unix epoch ms.
  final int createdMs;

  /// Updated at — Unix epoch ms.
  final int updatedMs;

  const ChainPreset({
    required this.name,
    required this.description,
    this.category,
    required this.tags,
    required this.snapshot,
    required this.formatVersion,
    required this.createdMs,
    required this.updatedMs,
  });

  factory ChainPreset.fromJson(Map<String, dynamic> j) => ChainPreset(
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        category: normaliseChainCategory((j['category'] as String?) ?? ''),
        tags: ((j['tags'] as List<dynamic>?) ?? const [])
            .map((t) => t.toString())
            .toList(growable: false),
        snapshot:
            FullChainSnapshot.fromJson(j['snapshot'] as Map<String, dynamic>),
        formatVersion: (j['format_version'] as num?)?.toInt() ?? 1,
        createdMs: (j['created_ms'] as num?)?.toInt() ?? 0,
        updatedMs: (j['updated_ms'] as num?)?.toInt() ?? 0,
      );

  /// Save-request payload shape consumed by `chain_preset_save_json`.
  /// Note: the FFI strips/replaces format_version, created_ms, updated_ms
  /// on save (`ChainPreset::new` resets them) — only name/description/
  /// category/tags/snapshot are honoured.
  Map<String, dynamic> toSaveRequest() => {
        'name': name,
        'description': description,
        if (category != null && category!.isNotEmpty) 'category': category,
        'tags': tags,
        'snapshot': snapshot.toJson(),
      };
}

/// Light metadata projection for the library browser.
///
/// Returned by `chain_preset_list_json` / `chain_preset_search_json` so
/// a UI doesn't pay full snapshot deserialisation while scrolling.
class ChainPresetMeta {
  final String name;
  final String description;

  /// Single canonical category (lowercase, trimmed) — mirrors
  /// `ChainPreset.category`. `null` when unclassified.
  final String? category;

  final List<String> tags;
  final int createdMs;
  final int updatedMs;

  /// Number of loaded slots (empty slots not counted).
  final int slotCount;

  /// On-disk filename (slug + ".json").
  final String filename;

  const ChainPresetMeta({
    required this.name,
    required this.description,
    this.category,
    required this.tags,
    required this.createdMs,
    required this.updatedMs,
    required this.slotCount,
    required this.filename,
  });

  factory ChainPresetMeta.fromJson(Map<String, dynamic> j) => ChainPresetMeta(
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        category: normaliseChainCategory((j['category'] as String?) ?? ''),
        tags: ((j['tags'] as List<dynamic>?) ?? const [])
            .map((t) => t.toString())
            .toList(growable: false),
        createdMs: (j['created_ms'] as num?)?.toInt() ?? 0,
        updatedMs: (j['updated_ms'] as num?)?.toInt() ?? 0,
        slotCount: (j['slot_count'] as num?)?.toInt() ?? 0,
        filename: (j['filename'] as String?) ?? '',
      );
}

// ─── Filter spec (mirrors PresetFilterSpec in Rust) ─────────────────────────

/// Structured filter spec — sent as JSON to `chain_preset_filter_json`.
///
/// All axes are optional; the empty filter matches every preset. Axes
/// AND-combine. Within `tagsAny` it's OR; within `tagsAll` it's AND.
class ChainPresetFilter {
  /// At most one of these categories must match (case-insensitive).
  /// Empty `null` ⇒ no category restriction.
  final List<String> categories;

  /// At least one of these tags must appear on the preset.
  final List<String> tagsAny;

  /// All of these tags must appear.
  final List<String> tagsAll;

  /// Substring query across name/description/tags/category.
  final String query;

  /// If true, only un-classified presets are returned. Mutually
  /// exclusive with [categories]; if both provided, [categories] wins.
  final bool uncategorisedOnly;

  const ChainPresetFilter({
    this.categories = const [],
    this.tagsAny = const [],
    this.tagsAll = const [],
    this.query = '',
    this.uncategorisedOnly = false,
  });

  /// True when no axis is populated → caller can fall back to the cheap
  /// cached metadata list instead of an FFI roundtrip.
  bool get isEmpty =>
      categories.isEmpty &&
      tagsAny.isEmpty &&
      tagsAll.isEmpty &&
      query.trim().isEmpty &&
      !uncategorisedOnly;

  Map<String, dynamic> toJson() => {
        if (categories.isNotEmpty) 'categories': categories,
        if (tagsAny.isNotEmpty) 'tags_any': tagsAny,
        if (tagsAll.isNotEmpty) 'tags_all': tagsAll,
        if (query.trim().isNotEmpty) 'query': query,
        if (uncategorisedOnly) 'uncategorised_only': true,
      };

  ChainPresetFilter copyWith({
    List<String>? categories,
    List<String>? tagsAny,
    List<String>? tagsAll,
    String? query,
    bool? uncategorisedOnly,
  }) =>
      ChainPresetFilter(
        categories: categories ?? this.categories,
        tagsAny: tagsAny ?? this.tagsAny,
        tagsAll: tagsAll ?? this.tagsAll,
        query: query ?? this.query,
        uncategorisedOnly: uncategorisedOnly ?? this.uncategorisedOnly,
      );
}

// ─── Result envelopes ───────────────────────────────────────────────────────

/// Common shape for save / set-dir / get-dir / export / import responses.
class ChainPresetOpResult {
  /// True if the FFI call returned `{"ok": true, ...}`.
  final bool ok;

  /// Resolved file/directory path (empty for some ops).
  final String path;

  /// Echoed user-visible name (empty for non-preset ops).
  final String name;

  /// Error message if ok==false.
  final String? error;

  const ChainPresetOpResult({
    required this.ok,
    required this.path,
    required this.name,
    this.error,
  });

  factory ChainPresetOpResult.fromJson(Map<String, dynamic> j) {
    final err = j['error'] as String?;
    if (err != null) {
      return ChainPresetOpResult(
        ok: false,
        path: '',
        name: '',
        error: err,
      );
    }
    return ChainPresetOpResult(
      ok: (j['ok'] as bool?) ?? false,
      path: (j['path'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
    );
  }

  factory ChainPresetOpResult.error(String message) =>
      ChainPresetOpResult(ok: false, path: '', name: '', error: message);
}
