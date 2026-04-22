/// PHASE 10e — Problems Inbox review panel
///
/// Bottom sheet UI showing all "Mark Problem" captures from the current
/// session. User can inspect each snapshot, delete individually, or clear
/// all at once.
///
/// Shown from the Live Play orb's "inbox" button (count badge). Lightweight
/// panel — no heavy audio playback (that comes with Phase 10e-part2 when
/// we wire the ring buffer capture).

library;

import 'package:flutter/material.dart';

import '../../models/mix_problem.dart';
import '../../providers/orb_mixer_provider.dart';
import '../../services/problems_inbox_service.dart';

/// Convenience: show the panel as a modal bottom sheet from anywhere.
Future<void> showProblemsInbox(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF0A0A12),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => const ProblemsInboxPanel(),
  );
}

class ProblemsInboxPanel extends StatefulWidget {
  const ProblemsInboxPanel({super.key});

  @override
  State<ProblemsInboxPanel> createState() => _ProblemsInboxPanelState();
}

class _ProblemsInboxPanelState extends State<ProblemsInboxPanel> {
  late final ProblemsInboxService _inbox;

  @override
  void initState() {
    super.initState();
    _inbox = ProblemsInboxService.instance;
    _inbox.addListener(_onChanged);
  }

  @override
  void dispose() {
    _inbox.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _inbox.problems;
    final viewport = MediaQuery.of(context).size;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: viewport.height * 0.7,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.flag, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Problems Inbox',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (items.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        await _inbox.clearAll();
                      },
                      icon: const Icon(Icons.delete_sweep,
                          size: 14, color: Colors.white70),
                      label: const Text(
                        'Clear all',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    icon:
                        const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF1A1A24)),

            // List
            Expanded(
              child: items.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) => _ProblemRow(
                        problem: items[i],
                        onDelete: () => _inbox.remove(items[i].id),
                        onNote: (newNote) =>
                            _inbox.setNote(items[i].id, newNote),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle,
              size: 42, color: Colors.greenAccent.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'No problems captured',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the 🚩 button on the Live Play orb while something sounds off.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProblemRow extends StatelessWidget {
  final MixProblem problem;
  final VoidCallback onDelete;
  final ValueChanged<String> onNote;

  const _ProblemRow({
    required this.problem,
    required this.onDelete,
    required this.onNote,
  });

  String _hms(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E1E28), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: time + FSM + voice count + delete
          Row(
            children: [
              Icon(Icons.flag, size: 13, color: Colors.redAccent.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(
                _hms(problem.markedAt),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 10),
              if (problem.fsmState != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    problem.fsmState!,
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '${problem.voiceCount} voices',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Colors.white38),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ),
          // Row 2: alert chips
          if (problem.alerts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: problem.alerts.map((a) {
                final color = _alertColor(a.type);
                final bus = a.busName != null ? ' ${a.busName}' : '';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: color.withValues(alpha: 0.45), width: 1),
                  ),
                  child: Text(
                    '${a.type.toUpperCase()}$bus',
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          // Row 3: bus peaks mini sparkline
          const SizedBox(height: 8),
          _BusPeaksBar(peaks: problem.busPeaks),
          // Row 4: note text field (click to edit)
          const SizedBox(height: 8),
          TextFormField(
            initialValue: problem.note,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a note…',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
              ),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2A32)),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2A32)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
            ),
            onFieldSubmitted: onNote,
          ),
        ],
      ),
    );
  }

  static Color _alertColor(String type) => switch (type) {
        'clipping' => const Color(0xFFFF3B30),
        'headroom' => const Color(0xFFFF9500),
        'phase' => const Color(0xFFC97AFF),
        'masking' => const Color(0xFFFFD60A),
        _ => Colors.white,
      };
}

class _BusPeaksBar extends StatelessWidget {
  final List<double> peaks;
  const _BusPeaksBar({required this.peaks});

  @override
  Widget build(BuildContext context) {
    // peaks layout: master L, master R, music L, music R, ...
    // Group into 6 buses (max of L/R per bus).
    final busMax = <double>[];
    for (int i = 0; i < peaks.length; i += 2) {
      final l = peaks[i];
      final r = (i + 1 < peaks.length) ? peaks[i + 1] : 0.0;
      busMax.add(l > r ? l : r);
    }
    return Row(
      children: List.generate(OrbBusId.values.length, (i) {
        final bus = OrbBusId.values[i];
        final engineIdx = bus.engineIndex;
        final m = engineIdx < busMax.length ? busMax[engineIdx] : 0.0;
        final h = (4.0 + m * 18.0).clamp(4.0, 22.0);
        final color = bus.color.withValues(alpha: 0.55 + m * 0.4);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bus.label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
