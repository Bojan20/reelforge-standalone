// VCA Fader Strip Widget
// Professional VCA control like Cubase/Pro Tools/SSL
//
// Features:
// - Spill mode (show only VCA members in mixer)
// - Nested VCA support
// - Link modes (relative/absolute)
// - Trim per track
// - VCA automation
// - Group-aware mute/solo

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// VCA DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Link mode for VCA control
enum VcaLinkMode {
  /// All tracks move to same value
  absolute,
  /// Tracks maintain relative offsets
  relative,
}

/// VCA member track data
class VcaMemberTrack {
  final int id;
  final String name;
  final Color color;
  double trimDb;
  bool bypassVca;

  VcaMemberTrack({
    required this.id,
    required this.name,
    this.color = const Color(0xFF4a9eff),
    this.trimDb = 0.0,
    this.bypassVca = false,
  });
}

/// Complete VCA data
class VcaData {
  final int id;
  String name;
  double levelDb;
  bool muted;
  bool soloed;
  Color color;
  List<VcaMemberTrack> members;
  VcaLinkMode linkMode;
  bool spillActive;
  int? parentVcaId;  // For nested VCAs
  List<int> childVcaIds;
  bool automationEnabled;
  double automationTrimDb;

  VcaData({
    required this.id,
    required this.name,
    this.levelDb = 0.0,
    this.muted = false,
    this.soloed = false,
    this.color = const Color(0xFFff9040),
    this.members = const [],
    this.linkMode = VcaLinkMode.relative,
    this.spillActive = false,
    this.parentVcaId,
    this.childVcaIds = const [],
    this.automationEnabled = false,
    this.automationTrimDb = 0.0,
  });

  /// Get effective level including parent VCA contribution
  double get effectiveLevel => levelDb + automationTrimDb;

  /// Get member track IDs
  List<int> get memberTrackIds => members.map((m) => m.id).toList();
}

// ═══════════════════════════════════════════════════════════════════════════════
// VCA FADER STRIP
// ═══════════════════════════════════════════════════════════════════════════════

/// Professional VCA Fader Strip - SSL/Neve style
class VcaFaderStrip extends StatefulWidget {
  final VcaData vca;
  final double height;
  final bool isSelected;
  final bool showAutomation;
  final void Function(double level)? onLevelChanged;
  final void Function(bool muted)? onMuteChanged;
  final void Function(bool soloed)? onSoloChanged;
  final void Function(bool active)? onSpillToggled;
  final void Function(VcaLinkMode mode)? onLinkModeChanged;
  final VoidCallback? onEditMembers;
  final VoidCallback? onShowAutomation;
  final VoidCallback? onDelete;
  final void Function(int trackId, double trimDb)? onMemberTrimChanged;

  const VcaFaderStrip({
    super.key,
    required this.vca,
    this.height = 400,
    this.isSelected = false,
    this.showAutomation = false,
    this.onLevelChanged,
    this.onMuteChanged,
    this.onSoloChanged,
    this.onSpillToggled,
    this.onLinkModeChanged,
    this.onEditMembers,
    this.onShowAutomation,
    this.onDelete,
    this.onMemberTrimChanged,
  });

  @override
  State<VcaFaderStrip> createState() => _VcaFaderStripState();
}

class _VcaFaderStripState extends State<VcaFaderStrip>
    with SingleTickerProviderStateMixin {
  late double _levelDb;
  bool _isDragging = false;
  bool _showTrimEditor = false;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _levelDb = widget.vca.levelDb;
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    if (widget.vca.spillActive) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(VcaFaderStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _levelDb = widget.vca.levelDb;
    }

    if (widget.vca.spillActive != oldWidget.vca.spillActive) {
      if (widget.vca.spillActive) {
        _glowController.repeat(reverse: true);
      } else {
        _glowController.stop();
        _glowController.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          width: 88,
          height: widget.height,
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgMid,
            border: Border.all(
              color: widget.isSelected
                  ? widget.vca.color
                  : widget.vca.spillActive
                      ? widget.vca.color.withValues(
                          alpha: 0.3 + _glowController.value * 0.4)
                      : ReelForgeTheme.borderSubtle,
              width: widget.isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
            boxShadow: widget.vca.spillActive
                ? [
                    BoxShadow(
                      color: widget.vca.color
                          .withValues(alpha: 0.2 * _glowController.value),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              _buildHeader(),
              const Divider(color: ReelForgeTheme.borderSubtle, height: 1),
              _buildLinkModeRow(),
              const Divider(color: ReelForgeTheme.borderSubtle, height: 1),
              Expanded(child: _buildFaderSection()),
              const Divider(color: ReelForgeTheme.borderSubtle, height: 1),
              _buildControlButtons(),
              const Divider(color: ReelForgeTheme.borderSubtle, height: 1),
              _buildMemberSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      onDoubleTap: () => _showRenameDialog(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              widget.vca.color.withValues(alpha: 0.4),
              widget.vca.color.withValues(alpha: 0.15),
            ],
          ),
        ),
        child: Row(
          children: [
            // VCA indicator bar
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: widget.vca.color,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: widget.vca.color.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Name
            Expanded(
              child: Text(
                widget.vca.name,
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // VCA badge
            _buildVcaBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildVcaBadge() {
    final hasParent = widget.vca.parentVcaId != null;
    final hasChildren = widget.vca.childVcaIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: widget.vca.color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: widget.vca.color.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasParent)
            Icon(
              Icons.subdirectory_arrow_right,
              size: 8,
              color: widget.vca.color,
            ),
          Text(
            'VCA',
            style: TextStyle(
              color: widget.vca.color,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasChildren)
            Icon(
              Icons.account_tree,
              size: 8,
              color: widget.vca.color,
            ),
        ],
      ),
    );
  }

  Widget _buildLinkModeRow() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Link mode toggle
          Expanded(
            child: GestureDetector(
              onTap: () {
                final newMode = widget.vca.linkMode == VcaLinkMode.relative
                    ? VcaLinkMode.absolute
                    : VcaLinkMode.relative;
                widget.onLinkModeChanged?.call(newMode);
              },
              child: Container(
                height: 18,
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: ReelForgeTheme.borderSubtle,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.vca.linkMode == VcaLinkMode.relative
                          ? Icons.link
                          : Icons.link_off,
                      size: 10,
                      color: ReelForgeTheme.textSecondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      widget.vca.linkMode == VcaLinkMode.relative
                          ? 'REL'
                          : 'ABS',
                      style: TextStyle(
                        color: ReelForgeTheme.textSecondary,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Spill button
          GestureDetector(
            onTap: () =>
                widget.onSpillToggled?.call(!widget.vca.spillActive),
            child: Container(
              width: 36,
              height: 18,
              decoration: BoxDecoration(
                color: widget.vca.spillActive
                    ? widget.vca.color.withValues(alpha: 0.3)
                    : ReelForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: widget.vca.spillActive
                      ? widget.vca.color
                      : ReelForgeTheme.borderSubtle,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  'SPILL',
                  style: TextStyle(
                    color: widget.vca.spillActive
                        ? widget.vca.color
                        : ReelForgeTheme.textTertiary,
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaderSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          // dB scale
          _buildDbScale(),
          const SizedBox(width: 4),
          // Main fader
          Expanded(child: _buildFader()),
          const SizedBox(width: 4),
          // Value & automation
          _buildValueSection(),
        ],
      ),
    );
  }

  Widget _buildDbScale() {
    return SizedBox(
      width: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _dbLabel('+12'),
          _dbLabel('+6'),
          _dbLabel('0', highlight: true),
          _dbLabel('-6'),
          _dbLabel('-12'),
          _dbLabel('-18'),
          _dbLabel('-24'),
          _dbLabel('-36'),
          _dbLabel('-∞'),
        ],
      ),
    );
  }

  Widget _dbLabel(String text, {bool highlight = false}) {
    return Text(
      text,
      style: TextStyle(
        color: highlight
            ? ReelForgeTheme.accentBlue.withValues(alpha: 0.8)
            : ReelForgeTheme.textTertiary,
        fontSize: 7,
        fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildFader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final normalized = _dbToNormalized(_levelDb);
        final capPosition = height * (1 - normalized);

        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragUpdate: (details) {
            final newNormalized = 1 - (details.localPosition.dy / height);
            setState(() {
              _levelDb = _normalizedToDb(newNormalized.clamp(0.0, 1.0));
            });
            widget.onLevelChanged?.call(_levelDb);
          },
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onDoubleTap: () {
            setState(() => _levelDb = 0.0);
            widget.onLevelChanged?.call(0.0);
          },
          child: Container(
            width: 28,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: ReelForgeTheme.borderSubtle,
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // Track groove
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          ReelForgeTheme.bgVoid.withValues(alpha: 0.4),
                          ReelForgeTheme.bgVoid.withValues(alpha: 0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Fill bar
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: 3,
                  height: (height - 6) * normalized,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: _getFaderGradient(),
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 0dB line
                Positioned(
                  left: 0,
                  right: 0,
                  top: height * (1 - _dbToNormalized(0)),
                  child: Container(
                    height: 1,
                    color: ReelForgeTheme.accentBlue.withValues(alpha: 0.6),
                  ),
                ),
                // Automation trim indicator
                if (widget.vca.automationTrimDb != 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: height *
                        (1 -
                            _dbToNormalized(
                                _levelDb + widget.vca.automationTrimDb)),
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.accentGreen,
                        boxShadow: [
                          BoxShadow(
                            color:
                                ReelForgeTheme.accentGreen.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                // Fader cap
                Positioned(
                  left: 0,
                  right: 0,
                  top: capPosition - 10,
                  child: _buildFaderCap(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFaderCap() {
    return Container(
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.vca.color,
            widget.vca.color.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: ReelForgeTheme.textPrimary.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.vca.color.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Grip lines
          Container(
            width: 14,
            height: 1,
            color: ReelForgeTheme.textPrimary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 2),
          Container(
            width: 14,
            height: 1,
            color: ReelForgeTheme.textPrimary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 2),
          Container(
            width: 14,
            height: 1,
            color: ReelForgeTheme.textPrimary.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  List<Color> _getFaderGradient() {
    if (_levelDb > 6) {
      return [
        widget.vca.color.withValues(alpha: 0.6),
        ReelForgeTheme.accentRed.withValues(alpha: 0.6),
      ];
    } else if (_levelDb > 0) {
      return [
        widget.vca.color.withValues(alpha: 0.5),
        widget.vca.color.withValues(alpha: 0.7),
      ];
    } else {
      return [
        widget.vca.color.withValues(alpha: 0.3),
        widget.vca.color.withValues(alpha: 0.5),
      ];
    }
  }

  Widget _buildValueSection() {
    return SizedBox(
      width: 26,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Current value
          Text(
            _levelDb <= -72 ? '-∞' : _levelDb.toStringAsFixed(1),
            style: TextStyle(
              color: widget.vca.color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Text(
            'dB',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 7,
            ),
          ),
          const SizedBox(height: 8),
          // Automation indicator
          if (widget.vca.automationEnabled)
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: ReelForgeTheme.accentGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: ReelForgeTheme.accentGreen,
                  width: 1,
                ),
              ),
              child: const Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    color: ReelForgeTheme.accentGreen,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          // M / S row
          Row(
            children: [
              Expanded(
                child: _buildControlButton(
                  label: 'M',
                  active: widget.vca.muted,
                  activeColor: ReelForgeTheme.accentRed,
                  onTap: () => widget.onMuteChanged?.call(!widget.vca.muted),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildControlButton(
                  label: 'S',
                  active: widget.vca.soloed,
                  activeColor: const Color(0xFFffff40),
                  onTap: () => widget.onSoloChanged?.call(!widget.vca.soloed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Automation / Edit row
          Row(
            children: [
              Expanded(
                child: _buildControlButton(
                  label: 'AUTO',
                  active: widget.showAutomation,
                  activeColor: ReelForgeTheme.accentGreen,
                  onTap: widget.onShowAutomation,
                  fontSize: 7,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildControlButton(
                  label: 'TRIM',
                  active: _showTrimEditor,
                  activeColor: ReelForgeTheme.accentBlue,
                  onTap: () => setState(() => _showTrimEditor = !_showTrimEditor),
                  fontSize: 7,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required String label,
    required bool active,
    required Color activeColor,
    VoidCallback? onTap,
    double fontSize = 11,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 22,
        decoration: BoxDecoration(
          color: active ? activeColor : ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? activeColor : ReelForgeTheme.borderSubtle,
            width: 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? ReelForgeTheme.bgVoid : ReelForgeTheme.textTertiary,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberSection() {
    final memberCount = widget.vca.members.length;

    return GestureDetector(
      onTap: widget.onEditMembers,
      child: Container(
        height: _showTrimEditor ? 120 : 40,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: _showTrimEditor && widget.vca.members.isNotEmpty
            ? _buildTrimEditor()
            : _buildMemberSummary(memberCount),
      ),
    );
  }

  Widget _buildMemberSummary(int memberCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.people_outline,
          size: 14,
          color: widget.vca.color.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 4),
        Text(
          '$memberCount',
          style: TextStyle(
            color: widget.vca.color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.edit,
          size: 12,
          color: ReelForgeTheme.textTertiary,
        ),
      ],
    );
  }

  Widget _buildTrimEditor() {
    return ListView.builder(
      itemCount: widget.vca.members.length,
      itemBuilder: (context, index) {
        final member = widget.vca.members[index];
        return _VcaMemberTrimRow(
          member: member,
          vcaColor: widget.vca.color,
          onTrimChanged: (db) =>
              widget.onMemberTrimChanged?.call(member.id, db),
        );
      },
    );
  }

  void _showRenameDialog() {
    // Implement rename dialog
  }

  double _dbToNormalized(double db) {
    if (db <= -72) return 0;
    if (db >= 12) return 1;
    return (db + 72) / 84;
  }

  double _normalizedToDb(double normalized) {
    return normalized * 84 - 72;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VCA MEMBER TRIM ROW
// ═══════════════════════════════════════════════════════════════════════════════

class _VcaMemberTrimRow extends StatelessWidget {
  final VcaMemberTrack member;
  final Color vcaColor;
  final void Function(double db)? onTrimChanged;

  const _VcaMemberTrimRow({
    required this.member,
    required this.vcaColor,
    this.onTrimChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      margin: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          // Track color indicator
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: member.color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 4),
          // Track name
          Expanded(
            child: Text(
              member.name,
              style: TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 8,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Trim value
          SizedBox(
            width: 32,
            child: Text(
              '${member.trimDb >= 0 ? '+' : ''}${member.trimDb.toStringAsFixed(1)}',
              style: TextStyle(
                color: member.trimDb == 0
                    ? ReelForgeTheme.textTertiary
                    : vcaColor,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VCA MEMBER EDITOR DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class VcaMemberEditor extends StatefulWidget {
  final VcaData vca;
  final List<VcaMemberTrack> availableTracks;
  final void Function(List<VcaMemberTrack> members) onMembersChanged;

  const VcaMemberEditor({
    super.key,
    required this.vca,
    required this.availableTracks,
    required this.onMembersChanged,
  });

  @override
  State<VcaMemberEditor> createState() => _VcaMemberEditorState();
}

class _VcaMemberEditorState extends State<VcaMemberEditor> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.vca.memberTrackIds);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 450),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ReelForgeTheme.borderSubtle,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: ReelForgeTheme.bgVoid.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildSearchBar(),
          const SizedBox(height: 12),
          Flexible(child: _buildTrackList()),
          const SizedBox(height: 16),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.vca.color,
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(
                color: widget.vca.color.withValues(alpha: 0.4),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Edit ${widget.vca.name} Members',
          style: TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '${_selectedIds.length} selected',
          style: TextStyle(
            color: widget.vca.color,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: ReelForgeTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: TextField(
        style: TextStyle(
          color: ReelForgeTheme.textPrimary,
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: 'Search tracks...',
          hintStyle: TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 12,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: ReelForgeTheme.textTertiary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _buildTrackList() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: widget.availableTracks.length,
      itemBuilder: (context, index) {
        final track = widget.availableTracks[index];
        final isSelected = _selectedIds.contains(track.id);

        return _buildTrackRow(track, isSelected);
      },
    );
  }

  Widget _buildTrackRow(VcaMemberTrack track, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIds.remove(track.id);
          } else {
            _selectedIds.add(track.id);
          }
        });
      },
      child: Container(
        height: 36,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.vca.color.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? widget.vca.color.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: isSelected ? widget.vca.color : ReelForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color:
                      isSelected ? widget.vca.color : ReelForgeTheme.borderSubtle,
                  width: 1,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 12,
                      color: ReelForgeTheme.bgVoid,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            // Track color
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: track.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            // Track name
            Expanded(
              child: Text(
                track.name,
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            final selectedMembers = widget.availableTracks
                .where((t) => _selectedIds.contains(t.id))
                .toList();
            widget.onMembersChanged(selectedMembers);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.vca.color,
            foregroundColor: ReelForgeTheme.bgVoid,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          ),
          child: const Text(
            'Apply',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VCA CREATE DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class VcaCreateDialog extends StatefulWidget {
  final int? parentVcaId;
  final void Function(String name, Color color, int? parentVcaId) onCreate;

  const VcaCreateDialog({
    super.key,
    this.parentVcaId,
    required this.onCreate,
  });

  @override
  State<VcaCreateDialog> createState() => _VcaCreateDialogState();
}

class _VcaCreateDialogState extends State<VcaCreateDialog> {
  final _nameController = TextEditingController(text: 'VCA 1');
  Color _selectedColor = const Color(0xFFff9040);
  final _focusNode = FocusNode();

  static const _colorOptions = [
    Color(0xFFff9040), // Orange
    Color(0xFF4a9eff), // Blue
    Color(0xFF40ff90), // Green
    Color(0xFFff4060), // Red
    Color(0xFFff40ff), // Magenta
    Color(0xFFffff40), // Yellow
    Color(0xFF40c8ff), // Cyan
    Color(0xFFa040ff), // Purple
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ReelForgeTheme.bgMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: ReelForgeTheme.borderSubtle,
          width: 1,
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _selectedColor,
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                  color: _selectedColor.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            widget.parentVcaId != null ? 'Create Nested VCA' : 'Create VCA Fader',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name field
          TextField(
            controller: _nameController,
            focusNode: _focusNode,
            style: TextStyle(color: ReelForgeTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Name',
              labelStyle: TextStyle(color: ReelForgeTheme.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _selectedColor),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Color selection
          Text(
            'Color:',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colorOptions.map((color) {
              final isSelected = color == _selectedColor;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? ReelForgeTheme.textPrimary : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: ReelForgeTheme.textPrimary,
                          size: 18,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: ReelForgeTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onCreate(
              _nameController.text,
              _selectedColor,
              widget.parentVcaId,
            );
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedColor,
            foregroundColor: ReelForgeTheme.bgVoid,
          ),
          child: const Text(
            'Create',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VCA GROUP HEADER (for mixer section)
// ═══════════════════════════════════════════════════════════════════════════════

class VcaGroupHeader extends StatelessWidget {
  final List<VcaData> vcas;
  final VoidCallback? onAddVca;

  const VcaGroupHeader({
    super.key,
    required this.vcas,
    this.onAddVca,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(
            color: ReelForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tune,
            size: 14,
            color: Color(0xFFff9040),
          ),
          const SizedBox(width: 6),
          const Text(
            'VCA FADERS',
            style: TextStyle(
              color: Color(0xFFff9040),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '${vcas.length}',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAddVca,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFFff9040).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: const Color(0xFFff9040).withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.add,
                size: 12,
                color: Color(0xFFff9040),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
