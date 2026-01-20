/// Spectral Repair Editor - iZotope RX-Style Spectral Editor
///
/// Professional spectral repair with:
/// - Spectrogram display
/// - Selection tools (rectangle, lasso)
/// - Repair modes (attenuate, replace, pattern replace, harmonic fill)
/// - Region-based processing

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Spectral selection region
class SpectralSelection {
  final int id;
  final int startSample;
  final int endSample;
  final double minFreq;
  final double maxFreq;
  SpectralRepairMode mode;
  double attenuation; // dB reduction for attenuate mode

  SpectralSelection({
    required this.id,
    required this.startSample,
    required this.endSample,
    required this.minFreq,
    required this.maxFreq,
    this.mode = SpectralRepairMode.attenuate,
    this.attenuation = -20.0,
  });

  int get durationSamples => endSample - startSample;
  double get freqRange => maxFreq - minFreq;
}

/// Repair modes
enum SpectralRepairMode {
  attenuate,      // Reduce level by dB amount
  replace,        // Replace with surrounding content
  patternReplace, // Replace with learned pattern
  harmonicFill,   // Fill with harmonic content
}

/// Main spectral repair editor widget
class SpectralRepairEditor extends StatefulWidget {
  final int clipId;
  final double sampleRate;
  final int clipDuration;
  final VoidCallback? onChanged;

  const SpectralRepairEditor({
    super.key,
    required this.clipId,
    this.sampleRate = 48000.0,
    required this.clipDuration,
    this.onChanged,
  });

  @override
  State<SpectralRepairEditor> createState() => _SpectralRepairEditorState();
}

class _SpectralRepairEditorState extends State<SpectralRepairEditor> {
  final _ffi = NativeFFI.instance;

  // Selections
  final List<SpectralSelection> _selections = [];
  int _nextSelectionId = 1;
  int? _selectedSelectionId;

  // View state
  double _horizontalZoom = 1.0;
  double _verticalZoom = 1.0;
  double _scrollOffsetX = 0.0;
  double _scrollOffsetY = 0.0;

  // Frequency range (Hz)
  double _minFreq = 20.0;
  double _maxFreq = 20000.0;

  // Current tool
  SpectralTool _currentTool = SpectralTool.select;

  // Selection drawing state
  bool _isDrawingSelection = false;
  Offset? _selectionStart;
  Offset? _selectionEnd;

  // Repair settings
  SpectralRepairMode _repairMode = SpectralRepairMode.attenuate;
  double _attenuationDb = -20.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildToolbar(),
          Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: Row(
              children: [
                // Frequency axis
                SizedBox(width: 60, child: _buildFrequencyAxis()),
                // Spectrogram canvas
                Expanded(child: _buildSpectrogramCanvas()),
                // Inspector panel
                if (_selectedSelectionId != null)
                  SizedBox(width: 200, child: _buildInspectorPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.waves, color: FluxForgeTheme.accentOrange, size: 20),
          const SizedBox(width: 8),
          const Text(
            'SPECTRAL REPAIR',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Selection count
          if (_selections.isNotEmpty) ...[
            Text(
              '${_selections.length} selections',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 16),
          ],
          // Apply all button
          _buildActionButton(
            icon: Icons.check_circle,
            label: 'Apply All',
            color: FluxForgeTheme.accentGreen,
            onTap: _applyAllRepairs,
          ),
          const SizedBox(width: 8),
          // Clear all button
          _buildActionButton(
            icon: Icons.clear_all,
            label: 'Clear',
            color: FluxForgeTheme.accentRed,
            onTap: _clearAllSelections,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: FluxForgeTheme.bgDeep,
      child: Row(
        children: [
          // Tool selection
          _buildToolButton(
            icon: Icons.crop_square,
            label: 'Select',
            isActive: _currentTool == SpectralTool.select,
            onTap: () => setState(() => _currentTool = SpectralTool.select),
          ),
          const SizedBox(width: 8),
          _buildToolButton(
            icon: Icons.gesture,
            label: 'Lasso',
            isActive: _currentTool == SpectralTool.lasso,
            onTap: () => setState(() => _currentTool = SpectralTool.lasso),
          ),
          const SizedBox(width: 8),
          _buildToolButton(
            icon: Icons.brush,
            label: 'Brush',
            isActive: _currentTool == SpectralTool.brush,
            onTap: () => setState(() => _currentTool = SpectralTool.brush),
          ),
          const SizedBox(width: 24),
          VerticalDivider(width: 1, color: FluxForgeTheme.borderMedium),
          const SizedBox(width: 24),
          // Repair mode
          const Text(
            'MODE:',
            style: TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          _buildModeDropdown(),
          const SizedBox(width: 16),
          // Attenuation slider (for attenuate mode)
          if (_repairMode == SpectralRepairMode.attenuate) ...[
            const Text(
              'LEVEL:',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: Slider(
                value: _attenuationDb,
                min: -60.0,
                max: 0.0,
                onChanged: (v) => setState(() => _attenuationDb = v),
                activeColor: FluxForgeTheme.accentOrange,
                inactiveColor: FluxForgeTheme.borderSubtle,
              ),
            ),
            Text(
              '${_attenuationDb.toStringAsFixed(1)} dB',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? FluxForgeTheme.accentOrange : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? FluxForgeTheme.accentOrange : FluxForgeTheme.borderMedium,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderMedium),
      ),
      child: DropdownButton<SpectralRepairMode>(
        value: _repairMode,
        underline: const SizedBox(),
        dropdownColor: FluxForgeTheme.bgMid,
        style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
        items: const [
          DropdownMenuItem(
            value: SpectralRepairMode.attenuate,
            child: Text('Attenuate'),
          ),
          DropdownMenuItem(
            value: SpectralRepairMode.replace,
            child: Text('Replace'),
          ),
          DropdownMenuItem(
            value: SpectralRepairMode.patternReplace,
            child: Text('Pattern Replace'),
          ),
          DropdownMenuItem(
            value: SpectralRepairMode.harmonicFill,
            child: Text('Harmonic Fill'),
          ),
        ],
        onChanged: (v) => setState(() => _repairMode = v ?? SpectralRepairMode.attenuate),
      ),
    );
  }

  Widget _buildFrequencyAxis() {
    return CustomPaint(
      painter: _FrequencyAxisPainter(
        minFreq: _minFreq,
        maxFreq: _maxFreq,
        verticalZoom: _verticalZoom,
        scrollOffset: _scrollOffsetY,
      ),
      size: Size.infinite,
    );
  }

  Widget _buildSpectrogramCanvas() {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onTapUp: _onTapUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            painter: _SpectrogramPainter(
              clipDuration: widget.clipDuration,
              sampleRate: widget.sampleRate,
              minFreq: _minFreq,
              maxFreq: _maxFreq,
              horizontalZoom: _horizontalZoom,
              verticalZoom: _verticalZoom,
              scrollOffsetX: _scrollOffsetX,
              scrollOffsetY: _scrollOffsetY,
              selections: _selections,
              selectedId: _selectedSelectionId,
              currentSelection: _isDrawingSelection && _selectionStart != null && _selectionEnd != null
                  ? Rect.fromPoints(_selectionStart!, _selectionEnd!)
                  : null,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildInspectorPanel() {
    final selection = _selections.firstWhere(
      (s) => s.id == _selectedSelectionId,
      orElse: () => SpectralSelection(
        id: 0,
        startSample: 0,
        endSample: 0,
        minFreq: 0,
        maxFreq: 0,
      ),
    );

    if (selection.id == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(left: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SELECTION',
            style: TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Time', '${(selection.startSample / widget.sampleRate * 1000).toStringAsFixed(1)}ms - ${(selection.endSample / widget.sampleRate * 1000).toStringAsFixed(1)}ms'),
          _buildInfoRow('Freq', '${selection.minFreq.toStringAsFixed(0)}Hz - ${selection.maxFreq.toStringAsFixed(0)}Hz'),
          const SizedBox(height: 16),
          const Text(
            'REPAIR MODE',
            style: TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _buildModeSelector(selection),
          const Spacer(),
          // Apply button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _applyRepair(selection),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Apply Repair'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxForgeTheme.accentGreen,
                foregroundColor: FluxForgeTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Delete button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteSelection(selection.id),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FluxForgeTheme.accentRed,
                side: const BorderSide(color: FluxForgeTheme.accentRed),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
          Text(value, style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildModeSelector(SpectralSelection selection) {
    return Column(
      children: SpectralRepairMode.values.map((mode) {
        final isSelected = selection.mode == mode;
        return GestureDetector(
          onTap: () {
            setState(() {
              selection.mode = mode;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isSelected ? FluxForgeTheme.accentOrange.withOpacity(0.2) : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? FluxForgeTheme.accentOrange : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getModeIcon(mode),
                  size: 14,
                  color: isSelected ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getModeName(mode),
                    style: TextStyle(
                      color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getModeIcon(SpectralRepairMode mode) {
    switch (mode) {
      case SpectralRepairMode.attenuate:
        return Icons.volume_down;
      case SpectralRepairMode.replace:
        return Icons.find_replace;
      case SpectralRepairMode.patternReplace:
        return Icons.pattern;
      case SpectralRepairMode.harmonicFill:
        return Icons.music_note;
    }
  }

  String _getModeName(SpectralRepairMode mode) {
    switch (mode) {
      case SpectralRepairMode.attenuate:
        return 'Attenuate';
      case SpectralRepairMode.replace:
        return 'Replace';
      case SpectralRepairMode.patternReplace:
        return 'Pattern Replace';
      case SpectralRepairMode.harmonicFill:
        return 'Harmonic Fill';
    }
  }

  // Interaction handlers
  void _onPanStart(DragStartDetails details) {
    if (_currentTool == SpectralTool.select) {
      setState(() {
        _isDrawingSelection = true;
        _selectionStart = details.localPosition;
        _selectionEnd = details.localPosition;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isDrawingSelection) {
      setState(() {
        _selectionEnd = details.localPosition;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDrawingSelection && _selectionStart != null && _selectionEnd != null) {
      _createSelection(_selectionStart!, _selectionEnd!);
    }
    setState(() {
      _isDrawingSelection = false;
      _selectionStart = null;
      _selectionEnd = null;
    });
  }

  void _onTapUp(TapUpDetails details) {
    // Check if tapping on existing selection
    // For now, deselect
    setState(() => _selectedSelectionId = null);
  }

  void _createSelection(Offset start, Offset end) {
    // This would need the actual canvas size to convert properly
    // Simplified implementation
    final rect = Rect.fromPoints(start, end);

    // Convert to time/frequency domain (simplified)
    final startSample = (rect.left / 500 * widget.clipDuration).toInt();
    final endSample = (rect.right / 500 * widget.clipDuration).toInt();
    final minFreq = _maxFreq - (rect.bottom / 300 * (_maxFreq - _minFreq));
    final maxFreq = _maxFreq - (rect.top / 300 * (_maxFreq - _minFreq));

    final selection = SpectralSelection(
      id: _nextSelectionId++,
      startSample: startSample.clamp(0, widget.clipDuration),
      endSample: endSample.clamp(0, widget.clipDuration),
      minFreq: minFreq.clamp(_minFreq, _maxFreq),
      maxFreq: maxFreq.clamp(_minFreq, _maxFreq),
      mode: _repairMode,
      attenuation: _attenuationDb,
    );

    setState(() {
      _selections.add(selection);
      _selectedSelectionId = selection.id;
    });
  }

  void _applyRepair(SpectralSelection selection) {
    // Would call FFI to apply spectral repair
    debugPrint('[SpectralRepair] Apply ${selection.mode} to selection ${selection.id}');
    widget.onChanged?.call();
  }

  void _applyAllRepairs() {
    for (final selection in _selections) {
      _applyRepair(selection);
    }
  }

  void _deleteSelection(int id) {
    setState(() {
      _selections.removeWhere((s) => s.id == id);
      if (_selectedSelectionId == id) {
        _selectedSelectionId = null;
      }
    });
  }

  void _clearAllSelections() {
    setState(() {
      _selections.clear();
      _selectedSelectionId = null;
    });
  }
}

/// Selection tool types
enum SpectralTool {
  select,
  lasso,
  brush,
}

/// Frequency axis painter
class _FrequencyAxisPainter extends CustomPainter {
  final double minFreq;
  final double maxFreq;
  final double verticalZoom;
  final double scrollOffset;

  _FrequencyAxisPainter({
    required this.minFreq,
    required this.maxFreq,
    required this.verticalZoom,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw frequency labels (log scale)
    final frequencies = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];

    for (final freq in frequencies) {
      if (freq < minFreq || freq > maxFreq) continue;

      final y = _freqToY(freq.toDouble(), size.height);

      // Label
      final label = freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(4, y - textPainter.height / 2));

      // Grid line
      canvas.drawLine(
        Offset(size.width - 5, y),
        Offset(size.width, y),
        Paint()..color = FluxForgeTheme.borderSubtle,
      );
    }
  }

  double _freqToY(double freq, double height) {
    // Log scale
    final logMin = math.log(minFreq);
    final logMax = math.log(maxFreq);
    final logFreq = math.log(freq);
    final normalized = (logFreq - logMin) / (logMax - logMin);
    return height - (normalized * height * verticalZoom) + scrollOffset;
  }

  @override
  bool shouldRepaint(_FrequencyAxisPainter oldDelegate) =>
      oldDelegate.minFreq != minFreq ||
      oldDelegate.maxFreq != maxFreq ||
      oldDelegate.verticalZoom != verticalZoom ||
      oldDelegate.scrollOffset != scrollOffset;
}

/// Spectrogram painter
class _SpectrogramPainter extends CustomPainter {
  final int clipDuration;
  final double sampleRate;
  final double minFreq;
  final double maxFreq;
  final double horizontalZoom;
  final double verticalZoom;
  final double scrollOffsetX;
  final double scrollOffsetY;
  final List<SpectralSelection> selections;
  final int? selectedId;
  final Rect? currentSelection;

  _SpectrogramPainter({
    required this.clipDuration,
    required this.sampleRate,
    required this.minFreq,
    required this.maxFreq,
    required this.horizontalZoom,
    required this.verticalZoom,
    required this.scrollOffsetX,
    required this.scrollOffsetY,
    required this.selections,
    this.selectedId,
    this.currentSelection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = FluxForgeTheme.bgVoid,
    );

    // Draw placeholder spectrogram (gradient)
    final gradientPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1a1a2e),
          Color(0xFF16213e),
          Color(0xFF0f3460),
          Color(0xFF1a1a2e),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), gradientPaint);

    // Draw horizontal grid lines (frequency)
    final frequencies = [100, 500, 1000, 5000, 10000];
    for (final freq in frequencies) {
      final y = _freqToY(freq.toDouble(), size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = FluxForgeTheme.borderSubtle.withOpacity(0.3)
          ..strokeWidth = 0.5,
      );
    }

    // Draw existing selections
    for (final selection in selections) {
      final isSelected = selection.id == selectedId;
      _drawSelection(canvas, size, selection, isSelected);
    }

    // Draw current selection being drawn
    if (currentSelection != null) {
      final paint = Paint()
        ..color = FluxForgeTheme.accentOrange.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawRect(currentSelection!, paint);

      final borderPaint = Paint()
        ..color = FluxForgeTheme.accentOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(currentSelection!, borderPaint);
    }
  }

  void _drawSelection(Canvas canvas, Size size, SpectralSelection selection, bool isSelected) {
    final x1 = (selection.startSample / clipDuration) * size.width * horizontalZoom - scrollOffsetX;
    final x2 = (selection.endSample / clipDuration) * size.width * horizontalZoom - scrollOffsetX;
    final y1 = _freqToY(selection.maxFreq, size.height);
    final y2 = _freqToY(selection.minFreq, size.height);

    final rect = Rect.fromLTRB(x1, y1, x2, y2);

    // Fill
    final fillPaint = Paint()
      ..color = (isSelected ? FluxForgeTheme.accentCyan : FluxForgeTheme.accentOrange)
          .withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // Border
    final borderPaint = Paint()
      ..color = isSelected ? FluxForgeTheme.accentCyan : FluxForgeTheme.accentOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2 : 1;
    canvas.drawRect(rect, borderPaint);
  }

  double _freqToY(double freq, double height) {
    final logMin = math.log(minFreq);
    final logMax = math.log(maxFreq);
    final logFreq = math.log(freq.clamp(minFreq, maxFreq));
    final normalized = (logFreq - logMin) / (logMax - logMin);
    return height - (normalized * height * verticalZoom) + scrollOffsetY;
  }

  @override
  bool shouldRepaint(_SpectrogramPainter oldDelegate) =>
      oldDelegate.clipDuration != clipDuration ||
      oldDelegate.sampleRate != sampleRate ||
      oldDelegate.minFreq != minFreq ||
      oldDelegate.maxFreq != maxFreq ||
      oldDelegate.horizontalZoom != horizontalZoom ||
      oldDelegate.verticalZoom != verticalZoom ||
      oldDelegate.scrollOffsetX != scrollOffsetX ||
      oldDelegate.scrollOffsetY != scrollOffsetY ||
      oldDelegate.selections != selections ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.currentSelection != currentSelection;
}
