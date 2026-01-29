/// Auto Event Builder Provider — STUB (Deprecated)
///
/// This provider is deprecated and has been replaced by EventListPanel
/// which directly uses MiddlewareProvider for event management.
///
/// This stub remains to prevent breaking existing imports while the
/// migration to EventListPanel completes.
///
/// STATUS: Functionality moved to:
/// - Event management → MiddlewareProvider (SSoT)
/// - Event list UI → EventListPanel (lower_zone/)
/// - Audio assets → Local state in slot_lab_screen
library;

import 'package:flutter/foundation.dart';
import '../models/auto_event_builder_models.dart';
import '../models/middleware_models.dart' show ActionType;

/// Stub EventDraft class for quick_sheet compatibility
class EventDraft {
  final String targetId;
  final String stage;
  const EventDraft({required this.targetId, required this.stage});
}

/// Stub CommittedEvent class - preserved for compatibility
class CommittedEvent {
  final String eventId;
  final String intent;
  final String assetPath;
  final String bus;
  final String presetId;
  final Map<String, dynamic> parameters;
  final ActionType actionType;
  final String? stopTarget;
  final double pan;

  CommittedEvent({
    required this.eventId,
    required this.intent,
    required this.assetPath,
    required this.bus,
    required this.presetId,
    this.parameters = const {},
    this.actionType = ActionType.play,
    this.stopTarget,
    this.pan = 0.0,
  });
}

/// Stub provider - no longer functional
class AutoEventBuilderProvider extends ChangeNotifier {
  // Empty audio assets
  List<AudioAsset> get audioAssets => const [];
  List<String> get allAssetTags => const [];
  bool get hasSelection => false;
  int get selectionCount => 0;
  List<AudioAsset> get selectedAssets => const [];
  List<AudioAsset> get recentAssets => const [];
  List<CommittedEvent> get events => const [];
  List<CommittedEvent> get committedEvents => const []; // Alias
  List<String> get presets => const []; // Stub for quick_sheet.dart

  EventDraft? createDraft(AudioAsset asset, DropTarget target) => null; // Stub
  void updateDraft({String? trigger, String? presetId, Map<String, dynamic>? parameters}) {} // Stub

  void clearAudioAssets() {}
  void addAudioAssets(List<AudioAsset> assets) {}
  void clearSelection() {}
  void selectAssets(Iterable<String> ids) {}
  void toggleAssetSelection(String id) {}
  bool isAssetSelected(String id) => false;
  int getEventCountForTarget(String targetId) => 0;
  void deleteEvent(String eventId) {}

  // Draft workflow stubs
  CommittedEvent? commitDraft() => null;
  void cancelDraft() {}

  @override
  void dispose() {
    super.dispose();
  }
}
