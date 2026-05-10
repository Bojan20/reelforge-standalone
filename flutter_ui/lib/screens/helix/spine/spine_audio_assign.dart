// HELIX spine — AUDIO ASSIGN overlay (Sprint 15 Faza 4.C split #14).
//
// Folder drag-drop autobind + per-stage audio assignment editor +
// FFNC rename dialog + naming heuristic preview.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _SpineAudioAssign(State) — audio assignment spine overlay

part of '../../helix_screen.dart';// ── Spine: AUDIO ASSIGN ─────────────────────────────────────────────────────

class _SpineAudioAssign extends StatefulWidget {
  @override
  State<_SpineAudioAssign> createState() => _SpineAudioAssignState();
}

class _SpineAudioAssignState extends State<_SpineAudioAssign> {
  /// ID of the slot card currently being hovered with a drag — used for
  /// per-card drop-target visual feedback (replaces the legacy global
  /// `_dropHovering` flag, which lived on a top-level drop area that no
  /// longer exists in the slot-first workflow).
  String? _hoveringEventId;

  static const _audioExtensions = {
    '.wav', '.aiff', '.aif', '.mp3', '.ogg', '.flac', '.m4a', '.aac', '.opus',
  };

  // ─── Stage auto-match from filename ────────────────────────────────────────
  /// Try to match filename to a known stage name.
  /// "REEL_STOP.wav" → "REEL_STOP", "spin_start_ambient.wav" → "SPIN_START"
  String? _matchStageFromFilename(String filename) {
    final upper = filename.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]'), '_');
    // Remove extension suffix
    final noExt = upper.contains('_') ? upper : upper;
    final stages = StageConfigurationService.instance.allStages
      ..sort((a, b) => b.name.length.compareTo(a.name.length)); // Longest first for specificity
    for (final stage in stages) {
      if (noExt.contains(stage.name)) return stage.name;
    }
    return null;
  }

  // ─── Register event to EventRegistry for actual audio playback ─────────────
  // Delegates to the shared EventRegistrationService so SlotLab + HELIX use
  // ONE registration path. Pre-2026-04-27 this was a hand-rolled duplicate
  // of slot_lab_screen's _syncEventToRegistry — both wrote into the same
  // _stageToEvent map and silently evicted each other (FLUX_MASTER_TODO 1.2.1).
  void _registerToEventRegistry(SlotCompositeEvent event) {
    EventRegistrationService.instance.registerComposite(event);
  }

  /// Mirror the layer assignment into `SlotLabProjectProvider._audioAssignments`
  /// so that `slot_stage_provider._hasAudioAssignment(stage)` returns `true`
  /// at spin time.
  ///
  /// **2026-05-08 autobind P0 fix.**  HELIX `_SpineAudioAssign` used to only
  /// call `_registerToEventRegistry`, which populates `EventRegistry._stageToEvent`
  /// — but the spin gate in `slot_stage_provider._triggerStage` first checks
  /// `SlotLabProjectProvider.hasAudioAssignment(stage)` and silently `return`s
  /// when both `effectiveStage` *and* `stageType` are missing.  Result:
  /// composite is registered but never fires.  SlotLab calls
  /// `projectProvider.setAudioAssignment(stage, audioPath)` everywhere it
  /// touches the registry; HELIX missed that side-effect, so dropping audio
  /// in the AUDIO ASSIGN spine looked correct but produced silence on spin.
  void _syncProjectAudioAssignment(SlotCompositeEvent event) {
    if (event.layers.isEmpty || event.triggerStages.isEmpty) return;
    try {
      final project = GetIt.instance<SlotLabProjectProvider>();
      final firstPath = event.layers.first.audioPath;
      if (firstPath.isEmpty) return;
      for (final stage in event.triggerStages) {
        project.setAudioAssignment(stage, firstPath, recordUndo: false);
      }
    } catch (_) {
      // Project provider not registered (e.g., test mode) — ignore.
    }
  }

  // ─── Stage picker dialog ────────────────────────────────────────────────────
  Future<String?> _pickStage(BuildContext context) async {
    final stages = StageConfigurationService.instance.allStages;
    // Group by category
    final byCategory = <String, List<StageDefinition>>{};
    for (final s in stages) {
      final cat = s.category.label;
      byCategory.putIfAbsent(cat, () => []).add(s);
    }

    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF111118),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  const Icon(Icons.link_rounded, size: 14, color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 6),
                  const Text('Assign to Stage', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 12, color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close_rounded, size: 14, color: FluxForgeTheme.textTertiary)),
                ]),
              ),
              const Divider(height: 1, color: Color(0xFF222230)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: byCategory.entries.map((entry) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, top: 4),
                          child: Text(entry.key,
                            style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 8,
                              color: FluxForgeTheme.textTertiary, letterSpacing: 1.2)),
                        ),
                        Wrap(
                          spacing: 4, runSpacing: 4,
                          children: entry.value.map((stage) => GestureDetector(
                            onTap: () => Navigator.pop(ctx, stage.name),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A28),
                                border: Border.all(color: const Color(0xFF333355)),
                                borderRadius: BorderRadius.circular(4)),
                              child: Text(stage.name,
                                style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 9,
                                  color: FluxForgeTheme.textSecondary)),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 6),
                      ],
                    )).toList(),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF222230)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(children: [
                  const Text('Skip assignment', style: TextStyle(
                    fontSize: 9, color: FluxForgeTheme.textTertiary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, '__SKIP__'),
                    child: const Text('Add without stage', style: TextStyle(
                      fontSize: 9, color: FluxForgeTheme.accentBlue))),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Reassign stage on existing event ──────────────────────────────────────
  Future<void> _reassignStage(SlotCompositeEvent event, {int? removeIndex}) async {
    final mw = GetIt.instance<MiddlewareProvider>();

    if (removeIndex != null) {
      // Remove specific stage from triggerStages
      final newStages = List<String>.from(event.triggerStages)..removeAt(removeIndex);
      final updated = event.copyWith(
        triggerStages: newStages,
        modifiedAt: DateTime.now(),
      );
      mw.updateCompositeEvent(updated);
      // Re-register with remaining stages
      _registerToEventRegistry(updated);
      _syncProjectAudioAssignment(updated);
      if (mounted) setState(() {});
      return;
    }

    // Show picker — adding or replacing first stage
    if (!mounted) return;
    final picked = await _pickStage(context);
    if (picked == null || picked == '__SKIP__') return;

    final newStages = List<String>.from(event.triggerStages);
    if (!newStages.contains(picked)) newStages.add(picked);

    final newId = newStages.length == 1 ? 'audio_${newStages.first}' : event.id;
    final updated = event.copyWith(
      id: newId,
      triggerStages: newStages,
      modifiedAt: DateTime.now(),
    );
    // Remove old event, add updated (id may have changed)
    silentRun('audio.deleteOldStageEvent', () { mw.deleteCompositeEvent(event.id); });
    mw.addCompositeEvent(updated);
    _registerToEventRegistry(updated);
    _syncProjectAudioAssignment(updated);
    if (mounted) setState(() {});
  }

  // ─── Filter audio paths ────────────────────────────────────────────────────
  List<String> _filterAudioPaths(List<String> paths) {
    final filtered = paths.where((p) {
      final dotIdx = p.toLowerCase().lastIndexOf('.');
      if (dotIdx < 0) return false;
      return _audioExtensions.contains(p.toLowerCase().substring(dotIdx));
    }).toList();
    // 2026-05-09 fix: implicitly extend PathValidator sandbox with
    // the parent directory of every dropped audio file.  User-picked
    // paths are inherently trusted (they walked through OS-level
    // open panel / drag-drop), and without this hook EventRegistry's
    // `_validateAudioPath` rejects them at SPIN time with "outside
    // sandbox" — silent fail that wasted a day of debugging.
    for (final p in filtered) {
      final parent = File(p).parent.path;
      PathValidator.addSandboxRoot(parent);
    }
    return filtered;
  }

  // ─── Build a layer from an audio file path ────────────────────────────────
  SlotEventLayer _layerFromPath(String path, int ts, String? stage) {
    final fileName = path.split('/').last;
    final name = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    return SlotEventLayer(
      id: 'layer_$ts',
      name: name,
      audioPath: path,
      volume: 1.0,
      loop: false,
      actionType: 'Play',
      busId: stage != null
          ? StageConfigurationService.instance.getStage(stage)?.bus.index
          : null,
    );
  }

  // ─── STEP 1: Create a new (empty) slot ─────────────────────────────────────
  // Asks for stage first — slot without a stage cannot fire on spin, so we
  // make the assignment explicit at creation time. User can still "skip" but
  // gets a visible warning chip.
  Future<void> _createNewSlot() async {
    if (!mounted) return;
    final picked = await _pickStage(context);
    if (picked == null) return; // cancelled
    final stage = (picked == '__SKIP__') ? null : picked;
    final mw = GetIt.instance<MiddlewareProvider>();
    final now = DateTime.now();

    // Stage already taken? Just select the existing event instead of duplicating.
    if (stage != null) {
      final existing = mw.compositeEvents
          .where((e) => e.triggerStages.contains(stage))
          .firstOrNull;
      if (existing != null) {
        mw.selectCompositeEvent(existing.id);
        if (mounted) setState(() {});
        return;
      }
    }

    final ts = now.millisecondsSinceEpoch;
    final event = SlotCompositeEvent(
      id: stage != null ? 'audio_$stage' : 'helix_new_$ts',
      name: stage ?? 'New Slot ${mw.compositeEvents.length + 1}',
      category: stage != null
          ? StageConfigurationService.instance.getCategoryLabel(stage)
          : 'custom',
      color: stage != null
          ? StageConfigurationService.instance.getCategoryColor(stage)
          : FluxForgeTheme.accentCyan,
      layers: const [],
      triggerStages: stage != null ? [stage] : const [],
      createdAt: now,
      modifiedAt: now,
    );
    mw.addCompositeEvent(event);
    if (mounted) setState(() {});
  }

  // ─── STEP 2a: Drop audio onto existing slot — append layers ───────────────
  Future<void> _addLayersToEvent(
    SlotCompositeEvent event,
    List<String> paths,
  ) async {
    final audioPaths = _filterAudioPaths(paths);
    if (audioPaths.isEmpty) return;

    final mw = GetIt.instance<MiddlewareProvider>();
    final now = DateTime.now();

    // If the slot has no stage yet, ask now — without a stage the layers
    // won't fire on spin (EventRegistrationService.registerComposite returns
    // empty when triggerStages is empty and no fallback is supplied). User
    // can still skip and assign later from the chip.
    SlotCompositeEvent target = event;
    if (target.triggerStages.isEmpty && mounted) {
      final picked = await _pickStage(context);
      if (picked == null) return; // cancelled — don't add layers
      if (picked != '__SKIP__') {
        // Refresh from provider in case the event was edited while dialog
        // was open; fall back to the captured `event` if it was deleted.
        target = mw.compositeEvents
            .where((e) => e.id == event.id)
            .firstOrNull ?? event;
        target = target.copyWith(
          id: 'audio_$picked',
          name: target.name == 'New Slot ${mw.compositeEvents.length}'
              || target.name.startsWith('New Slot ')
              ? picked
              : target.name,
          category: StageConfigurationService.instance.getCategoryLabel(picked),
          color: StageConfigurationService.instance.getCategoryColor(picked),
          triggerStages: [picked],
          modifiedAt: now,
        );
        // ID may have changed — remove old, add new
        if (target.id != event.id) {
          silentRun('audio.deleteOldEvent', () { mw.deleteCompositeEvent(event.id); });
          mw.addCompositeEvent(target);
        } else {
          mw.updateCompositeEvent(target);
        }
      }
    }

    final stage = target.triggerStages.isNotEmpty ? target.triggerStages.first : null;
    final newLayers = <SlotEventLayer>[];
    for (int i = 0; i < audioPaths.length; i++) {
      newLayers.add(_layerFromPath(audioPaths[i], now.millisecondsSinceEpoch + i, stage));
    }

    final updated = target.copyWith(
      layers: [...target.layers, ...newLayers],
      modifiedAt: now,
    );
    mw.updateCompositeEvent(updated);
    // Explicit re-register — covers the case where SlotLab is not mounted
    // (HELIX-only workflow). Idempotent with SlotLab's _onMiddlewareChanged.
    _registerToEventRegistry(updated);
    _syncProjectAudioAssignment(updated);
    if (mounted) setState(() {});
  }

  // ─── STEP 2b: Browse / drop on empty area — pick stage, then create slot
  // pre-populated with layers. This path also runs from the Browse button.
  Future<void> _browseAndCreateSlot(List<String> paths) async {
    final audioPaths = _filterAudioPaths(paths);
    if (audioPaths.isEmpty) return;

    // Try auto-match from first file
    final firstName = audioPaths.first.split('/').last;
    String? stage = _matchStageFromFilename(firstName);

    if (stage == null && mounted) {
      final picked = await _pickStage(context);
      if (picked == null) return; // cancelled
      if (picked != '__SKIP__') stage = picked;
    }

    final mw = GetIt.instance<MiddlewareProvider>();
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;

    final layers = <SlotEventLayer>[];
    for (int i = 0; i < audioPaths.length; i++) {
      layers.add(_layerFromPath(audioPaths[i], ts + i, stage));
    }

    // If a slot already exists for this stage, append layers to it.
    if (stage != null) {
      final existing = mw.compositeEvents
          .where((e) => e.triggerStages.contains(stage))
          .firstOrNull;
      if (existing != null) {
        final merged = existing.copyWith(
          layers: [...existing.layers, ...layers],
          modifiedAt: now,
        );
        mw.updateCompositeEvent(merged);
        _registerToEventRegistry(merged);
        _syncProjectAudioAssignment(merged);
        if (mounted) setState(() {});
        return;
      }
    }

    final event = SlotCompositeEvent(
      id: stage != null ? 'audio_$stage' : 'helix_drop_$ts',
      name: stage ?? layers.first.name,
      category: stage != null
          ? StageConfigurationService.instance.getCategoryLabel(stage)
          : 'custom',
      color: stage != null
          ? StageConfigurationService.instance.getCategoryColor(stage)
          : FluxForgeTheme.accentCyan,
      layers: layers,
      triggerStages: stage != null ? [stage] : const [],
      createdAt: now,
      modifiedAt: now,
    );
    mw.addCompositeEvent(event);
    _registerToEventRegistry(event);
    _syncProjectAudioAssignment(event);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GetIt.instance<MiddlewareProvider>(),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final events = mw.compositeEvents;
    final helixState = context.findAncestorStateOfType<_HelixScreenState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Step 1: Create slot — primary action ─────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3)),
            child: const Text('STEP 1',
              style: TextStyle(
                fontFamily: 'monospace', fontSize: 7,
                color: FluxForgeTheme.accentCyan, letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          const Expanded(child: Text('Create slot',
            style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary))),
          GestureDetector(
            onTap: _createNewSlot,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentCyan.withValues(alpha: 0.18),
                border: Border.all(color: FluxForgeTheme.accentCyan, width: 1.0),
                borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_circle_outline_rounded, size: 11,
                  color: FluxForgeTheme.accentCyan),
                SizedBox(width: 4),
                Text('New Slot', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // ── Step 2: Drop audio onto a slot ───────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3)),
            child: const Text('STEP 2',
              style: TextStyle(
                fontFamily: 'monospace', fontSize: 7,
                color: FluxForgeTheme.accentBlue, letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(
            events.isEmpty
              ? 'Drop audio onto a slot'
              : '${events.length} slot${events.length == 1 ? "" : "s"} — drop audio on a card',
            style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
            overflow: TextOverflow.ellipsis,
          )),
          GestureDetector(
            onTap: () async {
              await silentCatchAsync('audio.browseAndCreate', () async {
                final paths = await NativeFilePicker.pickAudioFiles();
                if (paths.isNotEmpty) {
                  await _browseAndCreateSlot(paths);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.08),
                border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_open_rounded, size: 10, color: FluxForgeTheme.accentBlue),
                SizedBox(width: 3),
                Text('Browse', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentBlue)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // ── Slot list ─────────────────────────────────────────────────
        Expanded(
          child: events.isEmpty
            ? Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined, size: 28,
                    color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  const Text('No slots yet.\nCreate a slot first,\nthen drop audio on it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9,
                      color: FluxForgeTheme.textTertiary, height: 1.5)),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _createNewSlot,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentCyan.withValues(alpha: 0.18),
                        border: Border.all(color: FluxForgeTheme.accentCyan, width: 1.0),
                        borderRadius: BorderRadius.circular(4)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.accentCyan),
                        SizedBox(width: 5),
                        Text('Create First Slot', style: TextStyle(
                          fontFamily: 'monospace', fontSize: 10,
                          color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ))
            : ListView(
                children: events
                    .take(20)
                    .map((e) => _buildSlotCard(e, helixState))
                    .toList(),
              ),
        ),
      ],
    );
  }

  // ─── Slot card — DropTarget that appends layers on drop ────────────────────
  Widget _buildSlotCard(SlotCompositeEvent e, _HelixScreenState? helixState) {
    final hasStages = e.triggerStages.isNotEmpty;
    final hasLayers = e.layers.isNotEmpty;
    final isHovering = _hoveringEventId == e.id;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hoveringEventId = e.id),
      onDragExited: (_) => setState(() {
        if (_hoveringEventId == e.id) _hoveringEventId = null;
      }),
      onDragDone: (detail) {
        setState(() => _hoveringEventId = null);
        _addLayersToEvent(e, detail.files.map((f) => f.path).toList());
      },
      child: GestureDetector(
        onTap: () => helixState?.openContextLens(e),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            color: isHovering
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.18)
              : e.color.withValues(alpha: 0.05),
            border: Border.all(
              color: isHovering
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.7)
                : (hasStages
                    ? e.color.withValues(alpha: 0.22)
                    : const Color(0xFF333340)),
              width: isHovering ? 1.5 : (hasStages ? 1.0 : 0.5),
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: isHovering ? [BoxShadow(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.25),
              blurRadius: 8)] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Row 1: dot + name + layer count / drop hint ──
              Row(children: [
                Container(width: 4, height: 4, decoration: BoxDecoration(
                  color: e.color, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Expanded(child: Text(e.name, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 10,
                  color: FluxForgeTheme.textSecondary),
                  overflow: TextOverflow.ellipsis)),
                if (!hasLayers)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue.withValues(alpha: 0.08),
                      border: Border.all(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(3)),
                    child: const Text('drop audio',
                      style: TextStyle(
                        fontFamily: 'monospace', fontSize: 7,
                        color: FluxForgeTheme.accentBlue, letterSpacing: 0.3)),
                  )
                else
                  Text('${e.layers.length}L', style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 8,
                    color: FluxForgeTheme.textTertiary)),
                const SizedBox(width: 3),
                const Icon(Icons.chevron_right_rounded, size: 11,
                  color: FluxForgeTheme.textTertiary),
              ]),
              // ── Row 2: stage chips ──
              const SizedBox(height: 4),
              Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  ...List.generate(e.triggerStages.length, (si) {
                    final stage = e.triggerStages[si];
                    final cfg = StageConfigurationService.instance.getStage(stage);
                    final chipColor = cfg != null
                      ? StageConfigurationService.instance.getCategoryColor(stage)
                      : FluxForgeTheme.accentCyan;
                    return GestureDetector(
                      onTap: () {
                        // Prevents parent GestureDetector from firing
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(5, 2, 2, 2),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: 0.1),
                          border: Border.all(color: chipColor.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(3)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(stage,
                            style: TextStyle(
                              fontFamily: 'monospace', fontSize: 7,
                              color: chipColor, letterSpacing: 0.3)),
                          const SizedBox(width: 3),
                          GestureDetector(
                            onTap: () => _reassignStage(e, removeIndex: si),
                            child: Icon(Icons.close_rounded, size: 8,
                              color: chipColor.withValues(alpha: 0.6)),
                          ),
                        ]),
                      ),
                    );
                  }),
                  // Add stage button — red "set stage" warning if missing
                  GestureDetector(
                    onTap: () => _reassignStage(e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasStages
                          ? Colors.transparent
                          : FluxForgeTheme.accentRed.withValues(alpha: 0.10),
                        border: Border.all(color: hasStages
                          ? const Color(0xFF444455)
                          : FluxForgeTheme.accentRed.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(3)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 8,
                          color: hasStages
                            ? FluxForgeTheme.textTertiary
                            : FluxForgeTheme.accentRed),
                        const SizedBox(width: 2),
                        Text(hasStages ? 'stage' : 'set stage (won\'t play)',
                          style: TextStyle(
                            fontFamily: 'monospace', fontSize: 7,
                            color: hasStages
                              ? FluxForgeTheme.textTertiary
                              : FluxForgeTheme.accentRed)),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Spine: GAME CONFIG — FAZA 3.7 ───────────────────────────────────────────
//
// Ultimativni Slot Designer Panel — 11 faza u 6 sub-tab-ova.
// Pokriva 9 tipova slotova, 8 jurisdikcija, integrity validator,
// snapshot sistem, blueprint export.
//
// Sub-tabs: TYPE | GRID | MATH | FEAT | COMPL | SNAP

enum _GcTab {
  type,
  grid,
  math,
  feat,
  compl,
  snap;

  String get label => switch (this) {
    type => 'TYPE',
    grid => 'GRID',
    math => 'MATH',
    feat => 'FEAT',
    compl => 'COMPL',
    snap => 'SNAP',
  };
}
