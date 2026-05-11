// HELIX EVENT NEXUS — pure-trigger event matrix.
//
// Central thesis (Boki, 2026-05-10):
//   "Svaki event pusti zvuk koliko taj audio fajl traje u originalu.
//    Niko ne odlučuje koliko zvuk traje. Korisnik kontroliše SVE
//    parametre — preklapanja, delay, fade, trim, sve."
//
// An event is a NAME that fires a TRIGGER. The audio file plays in
// its entirety; the registry never decides duration / fade / trim.
// Auto-bind seeds RAW-mode composites (fadeIn=fadeOut=crossfade=0,
// overlap=true, full-length playback) via [AutoBindCompositeBuilder].
// This matrix is where the user *manually* shapes layering and any
// sound-design semantics on top of that raw seed.
//
// ┌──[STAGE CONSTELLATION 240]──┬──SELECTED EVENT──┬──PARAMETER ORBIT 360──┐
// │ Categories with bound %     │ Big PLAY trigger │ LAYERS / EVENT / DSP  │
// │ Per-stage bound/silent badge│ File metadata    │ Per-layer accordion   │
// │ Long-press → audition       │ Mini waveform    │ All Slot-Lab params   │
// └─────────────────────────────┴──────────────────┴───────────────────────┘
//
// All providers reached via GetIt — no `BuildContext` lookups required;
// the widget rebuilds on `MiddlewareProvider` and `SlotLabProjectProvider`
// changes (composite event updates, autobind reload, layer edits).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/middleware_models.dart' show CrossfadeCurve;
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../services/event_registry.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC ENTRY
// ─────────────────────────────────────────────────────────────────────────────

class HelixEventNexus extends StatefulWidget {
  const HelixEventNexus({super.key});

  @override
  State<HelixEventNexus> createState() => _HelixEventNexusState();
}

class _HelixEventNexusState extends State<HelixEventNexus> {
  String? _selectedStage;
  String _filter = '';
  StageCategory? _categoryFilter;
  int _orbitTab = 0; // 0=LAYERS, 1=EVENT, 2=DSP
  String? _expandedLayerId;
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Reactivity ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final proj = GetIt.instance<SlotLabProjectProvider>();
    return ListenableBuilder(
      listenable: Listenable.merge([mw, proj]),
      builder: (_, _) => _buildLayout(context, mw, proj),
    );
  }

  Widget _buildLayout(
    BuildContext context,
    MiddlewareProvider mw,
    SlotLabProjectProvider proj,
  ) {
    final stagesSrv = StageConfigurationService.instance;
    final allStages = stagesSrv.allStages;

    // Build stage → event index for O(1) lookup.
    final eventByStage = <String, SlotCompositeEvent>{};
    for (final ev in mw.compositeEvents) {
      for (final st in ev.triggerStages) {
        eventByStage[st.toUpperCase()] = ev;
      }
      // Also index events by id-derived stage (audio_REEL_STOP_0 → REEL_STOP_0)
      if (ev.id.startsWith('audio_')) {
        final inferred = ev.id.substring(6).toUpperCase();
        eventByStage.putIfAbsent(inferred, () => ev);
      }
    }

    final selectedEvent = _selectedStage == null
        ? null
        : eventByStage[_selectedStage!.toUpperCase()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(mw, eventByStage, allStages),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: _StageConstellation(
                  stages: allStages,
                  eventByStage: eventByStage,
                  proj: proj,
                  selectedStage: _selectedStage,
                  filter: _filter,
                  categoryFilter: _categoryFilter,
                  onSelect: (s) => setState(() => _selectedStage = s),
                  onAudition: _audition,
                  onCategoryToggle: (c) => setState(
                    () => _categoryFilter =
                        (_categoryFilter == c) ? null : c,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SelectedEventCard(
                  stage: _selectedStage,
                  event: selectedEvent,
                  proj: proj,
                  onAudition: _audition,
                  onStopAll: _stopAll,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 360,
                child: _ParameterOrbit(
                  event: selectedEvent,
                  mw: mw,
                  tab: _orbitTab,
                  expandedLayerId: _expandedLayerId,
                  onTabChange: (t) => setState(() => _orbitTab = t),
                  onLayerExpandToggle: (id) => setState(
                    () => _expandedLayerId = _expandedLayerId == id ? null : id,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(
    MiddlewareProvider mw,
    Map<String, SlotCompositeEvent> eventByStage,
    List<StageDefinition> allStages,
  ) {
    final boundCount = allStages
        .where((s) => eventByStage.containsKey(s.name.toUpperCase()))
        .length;
    final coverage = allStages.isEmpty
        ? 0.0
        : (boundCount / allStages.length) * 100;
    final silentCount = mw.compositeEvents
        .where((e) => e.layers.isEmpty || e.layers.every((l) => l.audioPath.isEmpty))
        .length;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FluxForgeTheme.accentCyan.withValues(alpha: 0.10),
            FluxForgeTheme.accentPurple.withValues(alpha: 0.05),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded,
              size: 14, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 6),
          Text(
            'EVENT NEXUS',
            style: FluxForgeTheme.dockSans(
              size: 11,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
          const SizedBox(width: 12),
          _HeaderBadge(
              label: 'BOUND',
              value: '$boundCount/${allStages.length}',
              color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 6),
          _HeaderBadge(
              label: 'COV',
              value: '${coverage.toStringAsFixed(0)}%',
              color: coverage > 80
                  ? FluxForgeTheme.accentGreen
                  : coverage > 40
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.accentRed),
          const SizedBox(width: 6),
          _HeaderBadge(
              label: 'EVENTS',
              value: '${mw.compositeEvents.length}',
              color: FluxForgeTheme.accentPurple),
          if (silentCount > 0) ...[
            const SizedBox(width: 6),
            _HeaderBadge(
                label: 'SILENT',
                value: '$silentCount',
                color: FluxForgeTheme.accentRed),
          ],
          const Spacer(),
          SizedBox(
            width: 160,
            height: 22,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _filter = v.trim()),
              style: FluxForgeTheme.dockMono(size: 10),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                hintText: 'filter stages…',
                hintStyle: FluxForgeTheme.dockSans(
                    size: 10,
                    color: FluxForgeTheme.textTertiary
                        .withValues(alpha: 0.5)),
                filled: true,
                fillColor: FluxForgeTheme.bgElevated.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3),
                    borderSide: BorderSide(
                        color: FluxForgeTheme.accentCyan
                            .withValues(alpha: 0.4))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3),
                    borderSide: BorderSide(
                        color: FluxForgeTheme.accentCyan
                            .withValues(alpha: 0.3))),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _HeaderButton(
            label: 'STOP ALL',
            color: FluxForgeTheme.accentRed,
            tooltip: 'Stop every voice (all events, all buses)',
            onTap: _stopAll,
            icon: Icons.stop_rounded,
          ),
        ],
      ),
    );
  }

  // ── Audition / Stop ────────────────────────────────────────────────────────

  Future<void> _audition(String stage) async {
    try {
      await EventRegistry.instance.triggerStage(stage);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audition failed: $e'),
          backgroundColor: const Color(0xFF442222),
        ),
      );
    }
  }

  Future<void> _stopAll() async {
    try {
      await EventRegistry.instance.stopAll();
    } catch (_) {/* ignore */}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAGE CONSTELLATION (left column)
// ─────────────────────────────────────────────────────────────────────────────

class _StageConstellation extends StatelessWidget {
  final List<StageDefinition> stages;
  final Map<String, SlotCompositeEvent> eventByStage;
  final SlotLabProjectProvider proj;
  final String? selectedStage;
  final String filter;
  final StageCategory? categoryFilter;
  final void Function(String) onSelect;
  final Future<void> Function(String) onAudition;
  final void Function(StageCategory) onCategoryToggle;

  const _StageConstellation({
    required this.stages,
    required this.eventByStage,
    required this.proj,
    required this.selectedStage,
    required this.filter,
    required this.categoryFilter,
    required this.onSelect,
    required this.onAudition,
    required this.onCategoryToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Group stages by category, then optionally filter.
    final grouped = <StageCategory, List<StageDefinition>>{};
    for (final s in stages) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }

    final f = filter.toUpperCase();
    final visibleCategories = grouped.entries.where((e) {
      if (categoryFilter != null && e.key != categoryFilter) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.key.label.compareTo(b.key.label));

    return _NexusCard(
      accent: FluxForgeTheme.accentPurple,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category strip
          SizedBox(
            height: 22,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: 'ALL',
                  active: categoryFilter == null,
                  color: FluxForgeTheme.accentCyan,
                  onTap: () {
                    if (categoryFilter != null) {
                      onCategoryToggle(categoryFilter!);
                    }
                  },
                ),
                for (final entry in grouped.entries)
                  _CategoryChip(
                    label: entry.key.label.toUpperCase(),
                    active: categoryFilter == entry.key,
                    color: Color(entry.key.color),
                    count: entry.value.length,
                    boundCount: entry.value
                        .where((s) =>
                            eventByStage.containsKey(s.name.toUpperCase()))
                        .length,
                    onTap: () => onCategoryToggle(entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final cat in visibleCategories)
                  _buildCategoryGroup(
                    cat.key,
                    cat.value
                        .where((s) =>
                            f.isEmpty ||
                            s.name.toUpperCase().contains(f) ||
                            (s.displayLabel?.toUpperCase().contains(f) ?? false))
                        .toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGroup(
      StageCategory category, List<StageDefinition> defs) {
    if (defs.isEmpty) return const SizedBox.shrink();
    final boundCount = defs
        .where((s) => eventByStage.containsKey(s.name.toUpperCase()))
        .length;
    final color = Color(category.color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                category.label.toUpperCase(),
                style: FluxForgeTheme.dockSans(
                  size: 9,
                  weight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$boundCount/${defs.length}',
                style: FluxForgeTheme.dockMono(
                  size: 9,
                  color: FluxForgeTheme.textTertiary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        for (final s in defs) _buildStageRow(s, color),
      ],
    );
  }

  Widget _buildStageRow(StageDefinition def, Color catColor) {
    final stage = def.name.toUpperCase();
    final ev = eventByStage[stage];
    final hasEvent = ev != null;
    final hasAudio = hasEvent &&
        ev.layers.isNotEmpty &&
        ev.layers.any((l) => l.audioPath.isNotEmpty);
    final isSelected = stage == selectedStage?.toUpperCase();

    final statusColor = hasAudio
        ? FluxForgeTheme.accentGreen
        : hasEvent
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.textTertiary.withValues(alpha: 0.4);

    final bgColor = isSelected
        ? catColor.withValues(alpha: 0.18)
        : Colors.transparent;
    final borderColor = isSelected
        ? catColor.withValues(alpha: 0.6)
        : Colors.transparent;

    final layerCount = ev?.layers.length ?? 0;
    final fileName = hasAudio
        ? ev.layers.first.audioPath.split('/').last
        : '—';
    final displayName = def.displayLabel ?? def.name;

    return Tooltip(
      message: hasAudio
          ? '$stage\n$fileName\n${layerCount} layer${layerCount == 1 ? '' : 's'}'
          : hasEvent
              ? '$stage\nNo audio assigned'
              : '$stage\nUnbound',
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(def.name),
          onLongPress: hasAudio ? () => onAudition(def.name) : null,
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: hasAudio
                        ? [
                            BoxShadow(
                                color: statusColor.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 1)
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: FluxForgeTheme.dockSans(
                      size: 10,
                      weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: hasAudio
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textTertiary
                              .withValues(alpha: 0.7),
                    ),
                  ),
                ),
                if (def.isLooping)
                  const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(Icons.loop_rounded,
                        size: 10, color: FluxForgeTheme.accentPurple),
                  ),
                if (hasAudio)
                  IconButton(
                    iconSize: 12,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    icon: const Icon(Icons.play_arrow_rounded,
                        color: FluxForgeTheme.accentCyan),
                    tooltip: 'Audition (full file, pure trigger)',
                    onPressed: () => onAudition(def.name),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTED EVENT CARD (center column)
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedEventCard extends StatelessWidget {
  final String? stage;
  final SlotCompositeEvent? event;
  final SlotLabProjectProvider proj;
  final Future<void> Function(String) onAudition;
  final Future<void> Function() onStopAll;

  const _SelectedEventCard({
    required this.stage,
    required this.event,
    required this.proj,
    required this.onAudition,
    required this.onStopAll,
  });

  @override
  Widget build(BuildContext context) {
    if (stage == null) {
      return _NexusCard(
        accent: FluxForgeTheme.accentCyan,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_rounded,
                  size: 28,
                  color: FluxForgeTheme.textTertiary
                      .withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              Text(
                'Select a stage',
                style: FluxForgeTheme.dockSans(
                  size: 11,
                  color: FluxForgeTheme.textTertiary
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Long-press a row to audition without selecting',
                textAlign: TextAlign.center,
                style: FluxForgeTheme.dockSans(
                  size: 9,
                  color: FluxForgeTheme.textTertiary
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ev = event;
    final hasAudio = ev != null &&
        ev.layers.isNotEmpty &&
        ev.layers.any((l) => l.audioPath.isNotEmpty);

    return _NexusCard(
      accent: ev?.color ?? FluxForgeTheme.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ev?.color ?? FluxForgeTheme.accentCyan,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stage!,
                  overflow: TextOverflow.ellipsis,
                  style: FluxForgeTheme.dockSans(
                    size: 12,
                    weight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
              ),
              if (ev != null)
                Text(
                  ev.id,
                  style: FluxForgeTheme.dockMono(
                    size: 8,
                    color: FluxForgeTheme.textTertiary
                        .withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasAudio) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                    color: FluxForgeTheme.accentOrange
                        .withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: FluxForgeTheme.accentOrange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No audio assigned. Drop folder on Bind Orb or use AUDIO ASSIGN.',
                      style: FluxForgeTheme.dockSans(
                          size: 9, color: FluxForgeTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            _buildPrimaryFile(ev),
            const SizedBox(height: 8),
            _buildPlayBar(),
            const SizedBox(height: 8),
            _buildEventMeta(ev),
          ],
        ],
      ),
    );
  }

  Widget _buildPrimaryFile(SlotCompositeEvent ev) {
    final primary = ev.layers.firstWhere(
      (l) => l.audioPath.isNotEmpty,
      orElse: () => ev.layers.first,
    );
    final fileName = primary.audioPath.split('/').last;
    final folder = primary.audioPath.contains('/')
        ? primary.audioPath.substring(
            0, primary.audioPath.lastIndexOf('/'))
        : '';

    String? sizeStr;
    try {
      final f = File(primary.audioPath);
      if (f.existsSync()) {
        final bytes = f.lengthSync();
        sizeStr = bytes > 1024 * 1024
            ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
            : '${(bytes / 1024).toStringAsFixed(0)} KB';
      } else {
        sizeStr = 'MISSING';
      }
    } catch (_) {/* ignore */}

    final dur = primary.durationSeconds;
    final durStr = dur != null && dur > 0
        ? '${dur.toStringAsFixed(2)} s'
        : null;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
            color: ev.color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.audiotrack_rounded,
                  size: 12, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  style: FluxForgeTheme.dockSans(
                    size: 10,
                    weight: FontWeight.w600,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
              ),
              if (sizeStr != null)
                Text(
                  sizeStr,
                  style: FluxForgeTheme.dockMono(
                    size: 8,
                    color: sizeStr == 'MISSING'
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textTertiary,
                  ),
                ),
            ],
          ),
          if (folder.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                folder,
                overflow: TextOverflow.ellipsis,
                style: FluxForgeTheme.dockMono(
                  size: 8,
                  color: FluxForgeTheme.textTertiary
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
          if (durStr != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 10, color: FluxForgeTheme.accentGreen),
                const SizedBox(width: 4),
                Text(
                  'duration  $durStr',
                  style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: FluxForgeTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(plays in full — pure trigger)',
                  style: FluxForgeTheme.dockSans(
                    size: 8,
                    color: FluxForgeTheme.textTertiary
                        .withValues(alpha: 0.6),
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayBar() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text('TRIGGER',
                style: FluxForgeTheme.dockSans(
                    size: 11,
                    weight: FontWeight.w700,
                    letterSpacing: 1.2)),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  FluxForgeTheme.accentCyan.withValues(alpha: 0.18),
              foregroundColor: FluxForgeTheme.accentCyan,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
                side: BorderSide(
                    color: FluxForgeTheme.accentCyan
                        .withValues(alpha: 0.6)),
              ),
            ),
            onPressed: () => onAudition(stage!),
          ),
        ),
        const SizedBox(width: 6),
        ElevatedButton.icon(
          icon: const Icon(Icons.stop_rounded, size: 14),
          label: Text('STOP ALL',
              style: FluxForgeTheme.dockSans(
                  size: 9,
                  weight: FontWeight.w600,
                  letterSpacing: 1.0)),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                FluxForgeTheme.accentRed.withValues(alpha: 0.10),
            foregroundColor: FluxForgeTheme.accentRed,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
              side: BorderSide(
                  color:
                      FluxForgeTheme.accentRed.withValues(alpha: 0.5)),
            ),
          ),
          onPressed: onStopAll,
        ),
      ],
    );
  }

  Widget _buildEventMeta(SlotCompositeEvent ev) {
    final stagesSrv = StageConfigurationService.instance;
    final def = stagesSrv.getStage(stage!);
    final cat = def?.category.label ?? ev.category;
    final bus = def?.bus.name ?? 'default';
    final pri = def?.priority.toString() ?? '—';

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _MetaChip(label: 'CATEGORY', value: cat.toUpperCase()),
        _MetaChip(label: 'BUS', value: bus.toUpperCase()),
        _MetaChip(label: 'PRIO', value: pri),
        _MetaChip(label: 'LAYERS', value: '${ev.layers.length}'),
        _MetaChip(
            label: 'LOOP',
            value: ev.looping ? 'ON' : 'off',
            highlight: ev.looping),
        _MetaChip(
            label: 'OVERLAP',
            value: ev.overlap ? 'ON' : 'off',
            highlight: ev.overlap),
        if (ev.crossfadeMs > 0)
          _MetaChip(label: 'XFADE', value: '${ev.crossfadeMs}ms'),
        if (def?.isPooled ?? false)
          const _MetaChip(label: 'POOL', value: 'ON', highlight: true),
        if (def?.ducksMusic ?? false)
          const _MetaChip(label: 'DUCK', value: 'ON', highlight: true),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PARAMETER ORBIT (right column)
// ─────────────────────────────────────────────────────────────────────────────

class _ParameterOrbit extends StatelessWidget {
  final SlotCompositeEvent? event;
  final MiddlewareProvider mw;
  final int tab;
  final String? expandedLayerId;
  final void Function(int) onTabChange;
  final void Function(String) onLayerExpandToggle;

  const _ParameterOrbit({
    required this.event,
    required this.mw,
    required this.tab,
    required this.expandedLayerId,
    required this.onTabChange,
    required this.onLayerExpandToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _NexusCard(
      accent: FluxForgeTheme.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTabBar(),
          const SizedBox(height: 6),
          Expanded(
            child: event == null
                ? Center(
                    child: Text(
                      'select a stage to edit parameters',
                      style: FluxForgeTheme.dockSans(
                        size: 9,
                        color: FluxForgeTheme.textTertiary
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : switch (tab) {
                    0 => _buildLayersTab(event!),
                    1 => _buildEventTab(event!),
                    2 => _buildDspTab(event!),
                    _ => const SizedBox.shrink(),
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          for (final entry in const [
            (0, 'LAYERS', Icons.layers_rounded),
            (1, 'EVENT', Icons.scatter_plot_rounded),
            (2, 'DSP', Icons.tune_rounded),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _OrbitTabButton(
                label: entry.$2,
                icon: entry.$3,
                active: tab == entry.$1,
                onTap: () => onTabChange(entry.$1),
              ),
            ),
        ],
      ),
    );
  }

  // ── LAYERS tab ───────────────────────────────────────────────────────────

  Widget _buildLayersTab(SlotCompositeEvent ev) {
    if (ev.layers.isEmpty) {
      return Center(
        child: Text(
          'no layers — drop audio on Bind Orb',
          style: FluxForgeTheme.dockSans(
            size: 9,
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: ev.layers.length,
      itemBuilder: (_, i) {
        final layer = ev.layers[i];
        return _LayerCard(
          eventId: ev.id,
          layer: layer,
          mw: mw,
          expanded: expandedLayerId == layer.id,
          onToggle: () => onLayerExpandToggle(layer.id),
        );
      },
    );
  }

  // ── EVENT tab ────────────────────────────────────────────────────────────

  Widget _buildEventTab(SlotCompositeEvent ev) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _EventLevelSlider(
          label: 'Master Volume',
          value: ev.masterVolume,
          min: 0.0,
          max: 2.0,
          divisions: 40,
          display: '${(ev.masterVolume * 100).toInt()}%',
          onChanged: (v) {
            mw.updateCompositeEvent(ev.copyWith(masterVolume: v));
          },
        ),
        _EventLevelSlider(
          label: 'Crossfade',
          value: ev.crossfadeMs.toDouble(),
          min: 0.0,
          max: 5000.0,
          divisions: 100,
          display: '${ev.crossfadeMs}ms',
          onChanged: (v) {
            mw.updateCompositeEvent(ev.copyWith(crossfadeMs: v.toInt()));
          },
          tooltip:
              'Music transition only. SFX events should leave this at 0.',
        ),
        _EventToggle(
          label: 'Looping',
          value: ev.looping,
          onChanged: (v) {
            mw.updateCompositeEvent(ev.copyWith(looping: v));
          },
        ),
        _EventToggle(
          label: 'Allow overlap (retrigger does NOT kill prior voice)',
          value: ev.overlap,
          onChanged: (v) {
            mw.updateCompositeEvent(ev.copyWith(overlap: v));
          },
        ),
        const SizedBox(height: 8),
        _MetaSection(
          title: 'TRIGGER STAGES',
          rows: ev.triggerStages
              .map((s) => MapEntry(s, s.toUpperCase()))
              .toList(),
        ),
        if (ev.triggerConditions.isNotEmpty)
          _MetaSection(
            title: 'CONDITIONS',
            rows: ev.triggerConditions.entries
                .map((e) => MapEntry(e.key, '${e.key} ${e.value}'))
                .toList(),
          ),
        const SizedBox(height: 8),
        _ReadOnlyRow(
            label: 'POLY',
            value: '${ev.maxInstances} max',
            color: FluxForgeTheme.accentPurple),
        _ReadOnlyRow(
            label: 'CREATED',
            value: ev.createdAt.toIso8601String().substring(0, 19),
            color: FluxForgeTheme.textTertiary),
        _ReadOnlyRow(
            label: 'MODIFIED',
            value: ev.modifiedAt.toIso8601String().substring(0, 19),
            color: FluxForgeTheme.textTertiary),
      ],
    );
  }

  // ── DSP tab ──────────────────────────────────────────────────────────────

  Widget _buildDspTab(SlotCompositeEvent ev) {
    final layersWithDsp =
        ev.layers.where((l) => l.dspChain.isNotEmpty).toList();
    if (layersWithDsp.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No DSP nodes on any layer.\n\nAdd inserts in SlotLab → ASSIGN spine.',
            textAlign: TextAlign.center,
            style: FluxForgeTheme.dockSans(
              size: 9,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final l in layersWithDsp)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                  color: FluxForgeTheme.accentPurple
                      .withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded,
                        size: 11, color: FluxForgeTheme.accentPurple),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(l.name,
                            style: FluxForgeTheme.dockSans(
                                size: 10,
                                weight: FontWeight.w600))),
                    Text('${l.dspChain.length} nodes',
                        style: FluxForgeTheme.dockMono(
                            size: 8,
                            color: FluxForgeTheme.accentPurple
                                .withValues(alpha: 0.8))),
                  ],
                ),
                const SizedBox(height: 4),
                for (final node in l.dspChain)
                  Padding(
                    padding: const EdgeInsets.only(left: 14, top: 1),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: node.bypass
                                ? FluxForgeTheme.textTertiary
                                : FluxForgeTheme.accentPurple,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          node.type.name,
                          style: FluxForgeTheme.dockMono(
                            size: 9,
                            color: node.bypass
                                ? FluxForgeTheme.textTertiary
                                : FluxForgeTheme.textPrimary,
                          ).copyWith(
                            decoration: node.bypass
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYER CARD — collapsible row with full Slot-Lab parameter parity
// ─────────────────────────────────────────────────────────────────────────────

class _LayerCard extends StatelessWidget {
  final String eventId;
  final SlotEventLayer layer;
  final MiddlewareProvider mw;
  final bool expanded;
  final VoidCallback onToggle;

  const _LayerCard({
    required this.eventId,
    required this.layer,
    required this.mw,
    required this.expanded,
    required this.onToggle,
  });

  static const _busNames = <int?, String>{
    null: '–',
    0: 'SFX',
    1: 'MUSIC',
    2: 'VOICE',
    3: 'AMB',
    4: 'UI',
  };

  static const _curves = ['linear', 'exponential', 'logarithmic', 'sCurve'];
  static const _actions = [
    'Play',
    'Stop',
    'FadeOut',
    'FadeIn',
    'SetVolume',
    'SetPitch',
    'Pause',
    'Resume',
  ];
  static const _priorities = [
    'Highest',
    'High',
    'Above Normal',
    'Normal',
    'Below Normal',
    'Low',
    'Lowest',
  ];
  static const _scopes = [
    'Global',
    'Game Object',
    'Emitter',
    'All',
    'First Only',
  ];

  void _update(SlotEventLayer Function(SlotEventLayer) edit) {
    mw.updateEventLayer(eventId, edit(layer));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: layer.solo
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.6)
              : layer.muted
                  ? FluxForgeTheme.accentRed.withValues(alpha: 0.4)
                  : FluxForgeTheme.accentCyan.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 14,
                    color: FluxForgeTheme.accentCyan,
                  ),
                  Expanded(
                    child: Text(
                      layer.name.isEmpty ? layer.id : layer.name,
                      overflow: TextOverflow.ellipsis,
                      style: FluxForgeTheme.dockSans(
                        size: 10,
                        weight: FontWeight.w600,
                        color: layer.muted
                            ? FluxForgeTheme.textTertiary
                            : FluxForgeTheme.textPrimary,
                      ).copyWith(
                        decoration: layer.muted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  // Mute / Solo
                  _MicroToggle(
                    label: 'M',
                    active: layer.muted,
                    activeColor: FluxForgeTheme.accentRed,
                    tooltip: 'Mute',
                    onTap: () => mw.toggleLayerMute(eventId, layer.id),
                  ),
                  const SizedBox(width: 2),
                  _MicroToggle(
                    label: 'S',
                    active: layer.solo,
                    activeColor: FluxForgeTheme.accentGreen,
                    tooltip: 'Solo',
                    onTap: () => mw.toggleLayerSolo(eventId, layer.id),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(layer.volume * 100).toInt()}%',
                    style: FluxForgeTheme.dockMono(
                      size: 9,
                      color: FluxForgeTheme.accentCyan,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  if (layer.audioPath.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.audiotrack_outlined,
                              size: 10,
                              color: FluxForgeTheme.textTertiary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              layer.audioPath.split('/').last,
                              overflow: TextOverflow.ellipsis,
                              style: FluxForgeTheme.dockMono(
                                size: 8,
                                color: FluxForgeTheme.textTertiary
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          if (layer.durationSeconds != null &&
                              layer.durationSeconds! > 0)
                            Text(
                              '${layer.durationSeconds!.toStringAsFixed(2)}s',
                              style: FluxForgeTheme.dockMono(
                                size: 8,
                                color: FluxForgeTheme.accentGreen
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // ── LEVEL ─────────────────────────────────────────────
                  _ParamSlider(
                    label: 'Volume',
                    value: layer.volume,
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    display: '${(layer.volume * 100).toInt()}%',
                    color: FluxForgeTheme.accentCyan,
                    onChanged: (v) => _update((l) => l.copyWith(volume: v)),
                  ),
                  _ParamSlider(
                    label: 'Pan L',
                    value: layer.pan,
                    min: -1.0,
                    max: 1.0,
                    divisions: 20,
                    display: _panLabel(layer.pan),
                    color: FluxForgeTheme.accentPurple,
                    onChanged: (v) => _update((l) => l.copyWith(pan: v)),
                  ),
                  _ParamSlider(
                    label: 'Pan R',
                    value: layer.panRight,
                    min: -1.0,
                    max: 1.0,
                    divisions: 20,
                    display: _panLabel(layer.panRight),
                    color: FluxForgeTheme.accentPurple,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(panRight: v)),
                    tooltip:
                        'R-channel pan (stereo dual-pan). Leave at 0 for mono.',
                  ),
                  _ParamSlider(
                    label: 'Width',
                    value: layer.stereoWidth,
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    display: '${(layer.stereoWidth * 100).toInt()}%',
                    color: FluxForgeTheme.accentPurple,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(stereoWidth: v)),
                  ),
                  _ParamSlider(
                    label: 'Gain',
                    value: layer.inputGain,
                    min: -20.0,
                    max: 20.0,
                    divisions: 80,
                    display: '${layer.inputGain.toStringAsFixed(1)}dB',
                    color: FluxForgeTheme.accentOrange,
                    onChanged: (v) => _update((l) => l.copyWith(inputGain: v)),
                  ),

                  // ── TIMING (USER-OWNED) ──────────────────────────────
                  _SectionDivider(label: 'TIMING (USER-OWNED)'),
                  _ParamSlider(
                    label: 'Delay',
                    value: layer.offsetMs,
                    min: 0.0,
                    max: 5000.0,
                    divisions: 100,
                    display: '${layer.offsetMs.toInt()}ms',
                    color: FluxForgeTheme.accentGreen,
                    onChanged: (v) => _update((l) => l.copyWith(offsetMs: v)),
                  ),
                  _ParamSlider(
                    label: 'FadeIn',
                    value: layer.fadeInMs,
                    min: 0.0,
                    max: 5000.0,
                    divisions: 100,
                    display: '${layer.fadeInMs.toInt()}ms',
                    color: FluxForgeTheme.accentGreen,
                    onChanged: (v) => _update((l) => l.copyWith(fadeInMs: v)),
                    tooltip:
                        '0ms = instant attack (raw). >0 fades in over duration.',
                  ),
                  _ParamSlider(
                    label: 'FadeOut',
                    value: layer.fadeOutMs,
                    min: 0.0,
                    max: 5000.0,
                    divisions: 100,
                    display: '${layer.fadeOutMs.toInt()}ms',
                    color: FluxForgeTheme.accentGreen,
                    onChanged: (v) => _update((l) => l.copyWith(fadeOutMs: v)),
                    tooltip:
                        '0ms = file plays to its natural end. >0 fades the tail.',
                  ),
                  _ParamSlider(
                    label: 'TrimStart',
                    value: layer.trimStartMs,
                    min: 0.0,
                    max: 10000.0,
                    divisions: 200,
                    display: '${layer.trimStartMs.toInt()}ms',
                    color: FluxForgeTheme.accentRed,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(trimStartMs: v)),
                    tooltip:
                        'Skip first N ms of file. 0 = play from sample[0].',
                  ),
                  _ParamSlider(
                    label: 'TrimEnd',
                    value: layer.trimEndMs,
                    min: 0.0,
                    max: 10000.0,
                    divisions: 200,
                    display: layer.trimEndMs == 0
                        ? 'off'
                        : '${layer.trimEndMs.toInt()}ms',
                    color: FluxForgeTheme.accentRed,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(trimEndMs: v)),
                    tooltip:
                        'Cut last N ms of file. 0 = no trim (recommended).',
                  ),

                  // ── CURVES ──────────────────────────────────────────
                  _Dropdown<CrossfadeCurve>(
                    label: 'FadeIn Curve',
                    value: layer.fadeInCurve,
                    items: CrossfadeCurve.values,
                    display: (v) => v.name,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(fadeInCurve: v)),
                  ),
                  _Dropdown<CrossfadeCurve>(
                    label: 'FadeOut Curve',
                    value: layer.fadeOutCurve,
                    items: CrossfadeCurve.values,
                    display: (v) => v.name,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(fadeOutCurve: v)),
                  ),

                  // ── ROUTING ─────────────────────────────────────────
                  _SectionDivider(label: 'ROUTING'),
                  _Dropdown<int?>(
                    label: 'Bus',
                    value: layer.busId,
                    items: const [null, 0, 1, 2, 3, 4],
                    display: (v) => _busNames[v] ?? 'Bus $v',
                    onChanged: (v) => _update((l) => l.copyWith(busId: v)),
                  ),
                  _Dropdown<String>(
                    label: 'Action',
                    value: layer.actionType,
                    items: _actions,
                    display: (v) => v,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(actionType: v)),
                  ),
                  _Dropdown<String>(
                    label: 'Priority',
                    value: layer.priority,
                    items: _priorities,
                    display: (v) => v,
                    onChanged: (v) => _update((l) => l.copyWith(priority: v)),
                  ),
                  _Dropdown<String>(
                    label: 'Scope',
                    value: layer.scope,
                    items: _scopes,
                    display: (v) => v,
                    onChanged: (v) => _update((l) => l.copyWith(scope: v)),
                  ),

                  // ── BEHAVIOR ────────────────────────────────────────
                  _SectionDivider(label: 'BEHAVIOR'),
                  _MiniToggleRow(
                    label: 'Loop',
                    value: layer.loop,
                    onChanged: (v) => _update((l) => l.copyWith(loop: v)),
                  ),
                  _MiniToggleRow(
                    label: 'Overlap (don\'t kill prior voice)',
                    value: layer.overlap,
                    onChanged: (v) => _update((l) => l.copyWith(overlap: v)),
                  ),
                  _MiniToggleRow(
                    label: 'Phase Invert (Ø)',
                    value: layer.phaseInvert,
                    onChanged: (v) =>
                        _update((l) => l.copyWith(phaseInvert: v)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _panLabel(double v) {
    if (v.abs() < 0.05) return 'C';
    if (v < 0) return 'L${(v.abs() * 100).toInt()}';
    return 'R${(v * 100).toInt()}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ATOMS
// ─────────────────────────────────────────────────────────────────────────────

class _NexusCard extends StatelessWidget {
  final Color accent;
  final Widget child;

  const _NexusCard({required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _HeaderBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: FluxForgeTheme.dockSans(
                  size: 8,
                  weight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: color.withValues(alpha: 0.8))),
          const SizedBox(width: 4),
          Text(value,
              style: FluxForgeTheme.dockMono(
                  size: 9,
                  weight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(2),
            border:
                Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: FluxForgeTheme.dockSans(
                  size: 9,
                  weight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final int? count;
  final int? boundCount;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.active,
    required this.color,
    this.count,
    this.boundCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color:
                active ? color.withValues(alpha: 0.20) : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
                color: color.withValues(alpha: active ? 0.7 : 0.3),
                width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: FluxForgeTheme.dockSans(
                  size: 8,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
              if (count != null && boundCount != null) ...[
                const SizedBox(width: 3),
                Text(
                  '$boundCount/$count',
                  style: FluxForgeTheme.dockMono(
                    size: 7,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _MetaChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? FluxForgeTheme.accentGreen
        : FluxForgeTheme.textTertiary.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: FluxForgeTheme.dockSans(
              size: 7,
              weight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: FluxForgeTheme.dockMono(
              size: 8,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _OrbitTabButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? FluxForgeTheme.accentCyan
        : FluxForgeTheme.textTertiary.withValues(alpha: 0.6);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
              color: color.withValues(alpha: active ? 0.7 : 0.2),
              width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: FluxForgeTheme.dockSans(
                size: 9,
                weight: FontWeight.w700,
                letterSpacing: 1.0,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicroToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onTap;

  const _MicroToggle({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? activeColor
        : FluxForgeTheme.textTertiary.withValues(alpha: 0.5);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                active ? activeColor.withValues(alpha: 0.20) : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 0.5),
          ),
          child: Text(
            label,
            style: FluxForgeTheme.dockSans(
              size: 8,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final Color color;
  final ValueChanged<double> onChanged;
  final String? tooltip;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.color,
    required this.onChanged,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(
                size: 9,
                color: color.withValues(alpha: 0.85),
                weight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                activeTrackColor: color.withValues(alpha: 0.7),
                inactiveTrackColor: color.withValues(alpha: 0.18),
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.16),
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                valueIndicatorColor: color,
              ),
              child: Slider(
                value: clamped,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: FluxForgeTheme.dockMono(
                size: 9,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: row);
    }
    return row;
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) display;
  final ValueChanged<T> onChanged;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(
                size: 9,
                color: FluxForgeTheme.textSecondary,
                weight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgElevated.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                    color: FluxForgeTheme.accentCyan
                        .withValues(alpha: 0.3),
                    width: 0.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  isExpanded: true,
                  isDense: true,
                  value: value,
                  iconSize: 14,
                  style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: FluxForgeTheme.textPrimary,
                  ),
                  dropdownColor: FluxForgeTheme.bgSurface,
                  items: items
                      .map((it) => DropdownMenuItem<T>(
                            value: it,
                            child: Text(display(it)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _MiniToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = value
        ? FluxForgeTheme.accentGreen
        : FluxForgeTheme.textTertiary.withValues(alpha: 0.5);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(2),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 10,
              decoration: BoxDecoration(
                color: value
                    ? color.withValues(alpha: 0.6)
                    : FluxForgeTheme.bgElevated,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: color, width: 0.5),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 120),
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: value ? Colors.white : color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: FluxForgeTheme.dockSans(
                  size: 9,
                  color: value
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          Text(
            label,
            style: FluxForgeTheme.dockSans(
              size: 7,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 0.5,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventLevelSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final String? tooltip;

  const _EventLevelSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return _ParamSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      display: display,
      color: FluxForgeTheme.accentCyan,
      onChanged: onChanged,
      tooltip: tooltip,
    );
  }
}

class _EventToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _EventToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _MiniToggleRow(label: label, value: value, onChanged: onChanged);
  }
}

class _MetaSection extends StatelessWidget {
  final String title;
  final List<MapEntry<String, String>> rows;
  const _MetaSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionDivider(label: title),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 1),
            child: Text(
              r.value,
              style: FluxForgeTheme.dockMono(
                size: 9,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ReadOnlyRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(
                  size: 9, color: color.withValues(alpha: 0.7)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: FluxForgeTheme.dockMono(
                size: 9,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
