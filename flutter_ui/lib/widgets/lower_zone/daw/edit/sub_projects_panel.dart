/// Sub-Projects Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #36: Sub-Projects — import .rfproj files as nested references on timeline.
///
/// Features:
/// - Import sub-project .rfproj files
/// - Position on timeline, render proxy audio
/// - Update from source, remove sub-projects
/// - Self-contained SubProjectsService singleton
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════════════════

class SubProject {
  final String id;
  String name;
  String sourcePath;
  double startTime;
  double duration;
  bool rendered;
  String? proxyPath;

  SubProject({
    required this.id,
    required this.name,
    required this.sourcePath,
    this.startTime = 0.0,
    this.duration = 0.0,
    this.rendered = false,
    this.proxyPath,
  });

  SubProject copyWith({
    String? name,
    String? sourcePath,
    double? startTime,
    double? duration,
    bool? rendered,
    String? proxyPath,
  }) =>
      SubProject(
        id: id,
        name: name ?? this.name,
        sourcePath: sourcePath ?? this.sourcePath,
        startTime: startTime ?? this.startTime,
        duration: duration ?? this.duration,
        rendered: rendered ?? this.rendered,
        proxyPath: proxyPath ?? this.proxyPath,
      );

  String get startTimeFormatted => _formatSeconds(startTime);
  String get durationFormatted => _formatSeconds(duration);

  static String _formatSeconds(double s) {
    final mins = (s / 60).floor();
    final secs = (s % 60).toStringAsFixed(1);
    return '$mins:${secs.padLeft(4, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class SubProjectsService extends ChangeNotifier {
  SubProjectsService._();

  static final SubProjectsService instance = SubProjectsService._();

  final List<SubProject> _subProjects = [];

  List<SubProject> get subProjects => List.unmodifiable(_subProjects);
  int get count => _subProjects.length;

  SubProject? getById(String id) {
    final index = _subProjects.indexWhere((s) => s.id == id);
    return index >= 0 ? _subProjects[index] : null;
  }

  void importSubProject({
    required String name,
    required String sourcePath,
    double startTime = 0.0,
    double duration = 0.0,
  }) {
    final id = 'subproj_${DateTime.now().millisecondsSinceEpoch}';
    _subProjects.add(SubProject(
      id: id,
      name: name,
      sourcePath: sourcePath,
      startTime: startTime,
      duration: duration,
    ));
    notifyListeners();
  }

  void removeSubProject(String id) {
    _subProjects.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  void updatePosition(String id, double startTime) {
    final index = _subProjects.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _subProjects[index].startTime = startTime;
    notifyListeners();
  }

  void updateDuration(String id, double duration) {
    final index = _subProjects.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _subProjects[index].duration = duration;
    notifyListeners();
  }

  void markRendered(String id, {required String proxyPath}) {
    final index = _subProjects.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _subProjects[index].rendered = true;
    _subProjects[index].proxyPath = proxyPath;
    notifyListeners();
  }

  void invalidateProxy(String id) {
    final index = _subProjects.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _subProjects[index].rendered = false;
    _subProjects[index].proxyPath = null;
    notifyListeners();
  }

  void rename(String id, String name) {
    final index = _subProjects.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _subProjects[index].name = name;
    notifyListeners();
  }

  void clearAll() {
    _subProjects.clear();
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class SubProjectsPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const SubProjectsPanel({super.key, this.onAction});

  @override
  State<SubProjectsPanel> createState() => _SubProjectsPanelState();
}

class _SubProjectsPanelState extends State<SubProjectsPanel> {
  final _service = SubProjectsService.instance;
  String? _selectedId;
  bool _showImport = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _pathCtrl;
  late TextEditingController _startCtrl;
  late TextEditingController _durationCtrl;
  late FocusNode _nameFocus;
  late FocusNode _pathFocus;
  late FocusNode _startFocus;
  late FocusNode _durationFocus;

  static const _kBg = Color(0xFF1A1A24);
  static const _kText = Color(0xFFE0E0E8);
  static const _kBorder = Color(0xFF2A2A32);
  static const _kSecondary = Color(0xFF808088);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _pathCtrl = TextEditingController();
    _startCtrl = TextEditingController(text: '0.0');
    _durationCtrl = TextEditingController(text: '0.0');
    _nameFocus = FocusNode();
    _pathFocus = FocusNode();
    _startFocus = FocusNode();
    _durationFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    _startCtrl.dispose();
    _durationCtrl.dispose();
    _nameFocus.dispose();
    _pathFocus.dispose();
    _startFocus.dispose();
    _durationFocus.dispose();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  SubProject? get _selected =>
      _selectedId != null ? _service.getById(_selectedId!) : null;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 300, child: _buildSubProjectList()),
          const VerticalDivider(width: 1, color: _kBorder),
          Expanded(child: _buildDetailPanel()),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Sub-Project List
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSubProjectList() {
    final items = _service.subProjects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('SUB-PROJECTS', color: _kSecondary),
              const SizedBox(width: 6),
              Text('${_service.count}',
                  style: const TextStyle(fontSize: 10, color: _kSecondary)),
              const Spacer(),
              _iconBtn(Icons.add, 'Import',
                  () => setState(() => _showImport = !_showImport)),
              _iconBtn(Icons.delete_sweep, 'Clear All',
                  _service.count > 0 ? () => _service.clearAll() : null),
            ],
          ),
        ),
        if (_showImport) _buildImportForm(),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'No sub-projects.\nClick + to import a .rfproj file.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: FabFilterColors.textTertiary, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildSubProjectItem(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildImportForm() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      color: FabFilterColors.bgMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            child: TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              style: const TextStyle(fontSize: 11, color: _kText),
              decoration: _inputDeco('Sub-project name...'),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 26,
            child: TextField(
              controller: _pathCtrl,
              focusNode: _pathFocus,
              style: const TextStyle(fontSize: 11, color: _kText),
              decoration: _inputDeco('Source .rfproj path...'),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    controller: _startCtrl,
                    focusNode: _startFocus,
                    style: const TextStyle(fontSize: 11, color: _kText),
                    decoration: _inputDeco('Start (sec)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    controller: _durationCtrl,
                    focusNode: _durationFocus,
                    style: const TextStyle(fontSize: 11, color: _kText),
                    decoration: _inputDeco('Duration (sec)'),
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _doImport(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _iconBtn(Icons.close, 'Cancel',
                  () => setState(() => _showImport = false)),
              const SizedBox(width: 4),
              _iconBtn(Icons.check, 'Import', _doImport),
            ],
          ),
        ],
      ),
    );
  }

  void _doImport() {
    final name = _nameCtrl.text.trim();
    final path = _pathCtrl.text.trim();
    if (name.isEmpty || path.isEmpty) return;

    final start = double.tryParse(_startCtrl.text) ?? 0.0;
    final duration = double.tryParse(_durationCtrl.text) ?? 0.0;

    _service.importSubProject(
      name: name,
      sourcePath: path,
      startTime: start,
      duration: duration,
    );
    widget.onAction?.call('subProjectImport', {
      'name': name,
      'sourcePath': path,
      'startTime': start,
      'duration': duration,
    });

    _nameCtrl.clear();
    _pathCtrl.clear();
    _startCtrl.text = '0.0';
    _durationCtrl.text = '0.0';
    setState(() => _showImport = false);
  }

  Widget _buildSubProjectItem(SubProject sp) {
    final selected = sp.id == _selectedId;
    return InkWell(
      onTap: () => setState(() => _selectedId = sp.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? FabFilterColors.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(
                  color: FabFilterColors.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              sp.rendered ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: sp.rendered
                  ? FabFilterColors.green
                  : FabFilterColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sp.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected
                            ? FabFilterColors.textPrimary
                            : FabFilterColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis),
                  Text(sp.sourcePath,
                      style: const TextStyle(
                          fontSize: 9, color: FabFilterColors.textTertiary),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(sp.startTimeFormatted,
                style: const TextStyle(fontSize: 9, color: _kSecondary)),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Detail Panel
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildDetailPanel() {
    final sp = _selected;
    if (sp == null) {
      return Center(
        child: Text('Select a sub-project to view details',
            style:
                TextStyle(color: FabFilterColors.textTertiary, fontSize: 12)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Icon(Icons.account_tree, size: 16, color: FabFilterColors.cyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(sp.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kText),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Info rows
          _infoRow('Source', sp.sourcePath),
          _infoRow('Timeline Position', sp.startTimeFormatted),
          _infoRow('Duration', sp.durationFormatted),
          _infoRow(
              'Render Status', sp.rendered ? 'Rendered' : 'Not Rendered'),
          if (sp.proxyPath != null) _infoRow('Proxy', sp.proxyPath!),

          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              Expanded(
                child: _actionButton(Icons.movie_creation, 'Render Proxy',
                    sp.rendered
                        ? null
                        : () {
                            final proxyPath =
                                '${sp.sourcePath}.proxy.wav';
                            _service.markRendered(sp.id,
                                proxyPath: proxyPath);
                            widget.onAction?.call('subProjectRender', {
                              'subProjectId': sp.id,
                              'sourcePath': sp.sourcePath,
                              'proxyPath': proxyPath,
                            });
                          }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _actionButton(Icons.refresh, 'Update from Source', () {
                  _service.invalidateProxy(sp.id);
                  widget.onAction?.call('subProjectUpdate', {
                    'subProjectId': sp.id,
                    'sourcePath': sp.sourcePath,
                  });
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _actionButton(Icons.open_in_new, 'Open Source', () {
                  widget.onAction?.call('subProjectOpenSource', {
                    'subProjectId': sp.id,
                    'sourcePath': sp.sourcePath,
                  });
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _actionButton(Icons.delete_outline, 'Remove', () {
                  _service.removeSubProject(sp.id);
                  setState(() => _selectedId = null);
                  widget.onAction
                      ?.call('subProjectRemove', {'subProjectId': sp.id});
                }),
              ),
            ],
          ),

          const Spacer(),

          // Render status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sp.rendered
                  ? FabFilterColors.green.withValues(alpha: 0.1)
                  : FabFilterColors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: sp.rendered
                    ? FabFilterColors.green.withValues(alpha: 0.3)
                    : FabFilterColors.orange.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sp.rendered ? Icons.check_circle : Icons.pending,
                  size: 12,
                  color: sp.rendered
                      ? FabFilterColors.green
                      : FabFilterColors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  sp.rendered ? 'Proxy Ready' : 'Needs Render',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: sp.rendered
                        ? FabFilterColors.green
                        : FabFilterColors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontSize: 10, color: _kSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 10, color: _kText),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: _kSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return SizedBox(
      height: 28,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? FabFilterColors.bgMid : FabFilterColors.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: enabled ? _kSecondary : FabFilterColors.textDisabled),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: enabled
                          ? _kSecondary
                          : FabFilterColors.textDisabled)),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kSecondary, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.cyan),
        ),
        filled: true,
        fillColor: FabFilterColors.bgMid,
      );
}
