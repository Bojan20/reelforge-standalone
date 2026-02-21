/// Spill Controller — VCA/Folder channel filtering (Pro Tools Spill Mode)
///
/// When a VCA is "spilled", only its member tracks are visible.
/// When a folder is "spilled", only its child tracks are visible.
/// Dart-only UI filtering — no engine FFI needed.

import 'package:flutter/foundation.dart';
import '../../providers/mixer_provider.dart';

class SpillController extends ChangeNotifier {
  final MixerProvider _mixerProvider;

  String? _spillTargetId;
  Set<String> _spilledChannelIds = {};

  SpillController(this._mixerProvider);

  // ═══════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════

  String? get spillTargetId => _spillTargetId;
  Set<String> get spilledChannelIds => _spilledChannelIds;
  bool get isActive => _spillTargetId != null;

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Spill a VCA — show only its member tracks
  void spillVca(String vcaId) {
    final vcas = _mixerProvider.vcas;
    final vca = vcas.cast<VcaFader?>().firstWhere(
      (v) => v!.id == vcaId,
      orElse: () => null,
    );
    if (vca == null) return;

    _spillTargetId = vcaId;
    _spilledChannelIds = Set<String>.from(vca.memberIds);
    notifyListeners();
  }

  /// Spill a folder — show only its child tracks
  void spillFolder(String folderId) {
    // Folder children would come from MixerProvider folder system
    // For now, set the target and empty set (folders not yet populated)
    _spillTargetId = folderId;
    _spilledChannelIds = {};
    notifyListeners();
  }

  /// Clear spill — show all tracks again
  void unspill() {
    if (_spillTargetId == null) return;
    _spillTargetId = null;
    _spilledChannelIds = {};
    notifyListeners();
  }

  /// Toggle spill on a VCA — if already spilled, unspill
  void toggleSpillVca(String vcaId) {
    if (_spillTargetId == vcaId) {
      unspill();
    } else {
      spillVca(vcaId);
    }
  }

  /// Check if a channel is visible under current spill
  bool isChannelVisible(String channelId) {
    if (!isActive) return true;
    return _spilledChannelIds.contains(channelId);
  }
}
