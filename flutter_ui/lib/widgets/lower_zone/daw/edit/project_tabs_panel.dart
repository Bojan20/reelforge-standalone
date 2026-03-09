/// Project Tabs Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #35: Project Tabs — open multiple projects in tabs, switch between them.
///
/// Features:
/// - Horizontal tab bar with open projects
/// - Add (+), close (x), switch, reorder tabs
/// - Dirty indicator (unsaved changes dot)
/// - Self-contained ProjectTabsService singleton
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════════════════

class ProjectTab {
  final String id;
  String name;
  String path;
  bool isActive;
  bool isDirty;
  final DateTime createdAt;

  ProjectTab({
    required this.id,
    required this.name,
    required this.path,
    this.isActive = false,
    this.isDirty = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  ProjectTab copyWith({
    String? name,
    String? path,
    bool? isActive,
    bool? isDirty,
  }) =>
      ProjectTab(
        id: id,
        name: name ?? this.name,
        path: path ?? this.path,
        isActive: isActive ?? this.isActive,
        isDirty: isDirty ?? this.isDirty,
        createdAt: createdAt,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class ProjectTabsService extends ChangeNotifier {
  ProjectTabsService._() {
    // Start with one default tab
    final tab = ProjectTab(
      id: 'tab_default',
      name: 'Untitled Project',
      path: '',
      isActive: true,
    );
    _tabs.add(tab);
  }

  static final ProjectTabsService instance = ProjectTabsService._();

  final List<ProjectTab> _tabs = [];

  List<ProjectTab> get tabs => List.unmodifiable(_tabs);
  int get count => _tabs.length;

  ProjectTab? get activeTab {
    final index = _tabs.indexWhere((t) => t.isActive);
    return index >= 0 ? _tabs[index] : null;
  }

  int get activeIndex => _tabs.indexWhere((t) => t.isActive);

  void addTab({required String name, required String path}) {
    // Deactivate all
    for (final t in _tabs) {
      t.isActive = false;
    }
    final id = 'tab_${DateTime.now().millisecondsSinceEpoch}';
    _tabs.add(ProjectTab(id: id, name: name, path: path, isActive: true));
    notifyListeners();
  }

  void closeTab(String id) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index < 0 || _tabs.length <= 1) return;

    final wasActive = _tabs[index].isActive;
    _tabs.removeAt(index);

    if (wasActive && _tabs.isNotEmpty) {
      final newIndex = index.clamp(0, _tabs.length - 1);
      _tabs[newIndex].isActive = true;
    }
    notifyListeners();
  }

  void switchTab(String id) {
    for (final t in _tabs) {
      t.isActive = t.id == id;
    }
    notifyListeners();
  }

  void reorderTab(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex--;
    final tab = _tabs.removeAt(oldIndex);
    _tabs.insert(newIndex, tab);
    notifyListeners();
  }

  void renameTab(String id, String name) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _tabs[index].name = name;
    notifyListeners();
  }

  void markDirty(String id, {bool dirty = true}) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _tabs[index].isDirty = dirty;
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ProjectTabsPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const ProjectTabsPanel({super.key, this.onAction});

  @override
  State<ProjectTabsPanel> createState() => _ProjectTabsPanelState();
}

class _ProjectTabsPanelState extends State<ProjectTabsPanel> {
  final _service = ProjectTabsService.instance;
  bool _showAddTab = false;
  String? _renamingTabId;

  late TextEditingController _nameCtrl;
  late TextEditingController _pathCtrl;
  late TextEditingController _renameCtrl;
  late FocusNode _nameFocus;
  late FocusNode _pathFocus;
  late FocusNode _renameFocus;

  static const _kBg = Color(0xFF1A1A24);
  static const _kText = Color(0xFFE0E0E8);
  static const _kBorder = Color(0xFF2A2A32);
  static const _kSecondary = Color(0xFF808088);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _pathCtrl = TextEditingController();
    _renameCtrl = TextEditingController();
    _nameFocus = FocusNode();
    _pathFocus = FocusNode();
    _renameFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    _renameCtrl.dispose();
    _nameFocus.dispose();
    _pathFocus.dispose();
    _renameFocus.dispose();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: _kBorder),
          _buildTabBar(),
          const Divider(height: 1, color: _kBorder),
          if (_showAddTab) _buildAddTabForm(),
          Expanded(child: _buildTabDetail()),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      child: Row(
        children: [
          FabSectionLabel('PROJECT TABS', color: _kSecondary),
          const SizedBox(width: 8),
          Text(
            '${_service.count} open',
            style: const TextStyle(fontSize: 10, color: _kSecondary),
          ),
          const Spacer(),
          _iconBtn(Icons.add, 'New Tab',
              () => setState(() => _showAddTab = !_showAddTab)),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB BAR
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildTabBar() {
    final tabs = _service.tabs;
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        itemCount: tabs.length + 1, // +1 for add button
        itemBuilder: (_, i) {
          if (i == tabs.length) return _buildAddButton();
          return _buildTabChip(tabs[i], i);
        },
      ),
    );
  }

  Widget _buildTabChip(ProjectTab tab, int index) {
    final isActive = tab.isActive;
    final isRenaming = _renamingTabId == tab.id;

    return GestureDetector(
      onTap: () => _service.switchTab(tab.id),
      onDoubleTap: () {
        _renameCtrl.text = tab.name;
        setState(() => _renamingTabId = tab.id);
        Future.microtask(() => _renameFocus.requestFocus());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? FabFilterColors.cyan.withValues(alpha: 0.15)
              : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? FabFilterColors.cyan.withValues(alpha: 0.5)
                : _kBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dirty indicator
            if (tab.isDirty)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: FabFilterColors.orange,
                ),
              ),
            // Name or rename field
            if (isRenaming)
              SizedBox(
                width: 100,
                height: 22,
                child: TextField(
                  controller: _renameCtrl,
                  focusNode: _renameFocus,
                  style: const TextStyle(fontSize: 11, color: _kText),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _applyTabRename(tab.id),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  tab.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive ? _kText : _kSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Close button
            if (_service.count > 1) ...[
              const SizedBox(width: 4),
              SizedBox(
                width: 18,
                height: 18,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 12),
                  padding: EdgeInsets.zero,
                  color: _kSecondary,
                  onPressed: () {
                    _service.closeTab(tab.id);
                    widget.onAction?.call('tabClose', {'tabId': tab.id});
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: () => setState(() => _showAddTab = true),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _kBorder),
        ),
        child: const Center(
          child: Icon(Icons.add, size: 14, color: _kSecondary),
        ),
      ),
    );
  }

  void _applyTabRename(String id) {
    final name = _renameCtrl.text.trim();
    if (name.isNotEmpty) {
      _service.renameTab(id, name);
    }
    setState(() => _renamingTabId = null);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ADD TAB FORM
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildAddTabForm() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: FabFilterColors.bgMid,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                style: const TextStyle(fontSize: 11, color: _kText),
                decoration: _inputDeco('Project name...'),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                controller: _pathCtrl,
                focusNode: _pathFocus,
                style: const TextStyle(fontSize: 11, color: _kText),
                decoration: _inputDeco('Path (optional)...'),
                onSubmitted: (_) => _addTab(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconBtn(Icons.check, 'Add', _addTab),
          _iconBtn(
              Icons.close, 'Cancel', () => setState(() => _showAddTab = false)),
        ],
      ),
    );
  }

  void _addTab() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    _service.addTab(name: name, path: _pathCtrl.text.trim());
    widget.onAction?.call('tabOpen', {
      'name': name,
      'path': _pathCtrl.text.trim(),
    });
    _nameCtrl.clear();
    _pathCtrl.clear();
    setState(() => _showAddTab = false);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB DETAIL
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildTabDetail() {
    final tab = _service.activeTab;
    if (tab == null) {
      return const Center(
        child: Text('No active tab',
            style: TextStyle(color: _kSecondary, fontSize: 12)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT — info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_open,
                        size: 16, color: FabFilterColors.cyan),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tab.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tab.isDirty)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FabFilterColors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('UNSAVED',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: FabFilterColors.orange)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (tab.path.isNotEmpty)
                  Text('Path: ${tab.path}',
                      style: const TextStyle(fontSize: 10, color: _kSecondary),
                      overflow: TextOverflow.ellipsis),
                Text(
                    'Created: ${_formatDateTime(tab.createdAt)}',
                    style: const TextStyle(fontSize: 10, color: _kSecondary)),
                Text('Tab index: ${_service.activeIndex + 1} of ${_service.count}',
                    style: const TextStyle(fontSize: 10, color: _kSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // RIGHT — actions
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _actionButton(Icons.save, 'Save', () {
                  _service.markDirty(tab.id, dirty: false);
                  widget.onAction
                      ?.call('tabSave', {'tabId': tab.id, 'path': tab.path});
                }),
                const SizedBox(height: 4),
                _actionButton(Icons.content_copy, 'Duplicate', () {
                  _service.addTab(
                      name: '${tab.name} (copy)', path: tab.path);
                  widget.onAction?.call('tabDuplicate', {'tabId': tab.id});
                }),
                const SizedBox(height: 4),
                _actionButton(
                  Icons.close,
                  'Close Tab',
                  _service.count > 1
                      ? () {
                          _service.closeTab(tab.id);
                          widget.onAction
                              ?.call('tabClose', {'tabId': tab.id});
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
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
      width: double.infinity,
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
            children: [
              Icon(icon,
                  size: 14,
                  color: enabled ? _kSecondary : FabFilterColors.textDisabled),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
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
