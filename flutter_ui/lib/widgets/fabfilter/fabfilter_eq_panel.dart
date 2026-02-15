/// FabFilter Pro-Q Style EQ Panel
///
/// Professional 64-band parametric EQ with:
/// - Interactive spectrum analyzer with EQ nodes
/// - Click to create, drag to adjust bands
/// - Scroll wheel for Q adjustment
/// - Dynamic EQ per band
/// - A/B comparison
/// - EQ Match (reference matching)
/// - Auto-gain

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_panel_base.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Filter shape types (matching Pro-Q)
enum EqFilterShape {
  bell,
  lowShelf,
  highShelf,
  lowCut,
  highCut,
  notch,
  bandPass,
  tiltShelf,
  allPass,
  brickwall,
}

/// Stereo placement
enum EqPlacement {
  stereo,
  left,
  right,
  mid,
  side,
}

/// Filter slope
enum EqSlope {
  db6,
  db12,
  db18,
  db24,
  db36,
  db48,
  db72,
  db96,
  brickwall,
}

/// Analyzer display mode
enum AnalyzerMode {
  off,
  preEq,
  postEq,
  prePlusPost,
}

/// Single EQ band
class EqBand {
  int index;
  double freq;
  double gain;
  double q;
  EqFilterShape shape;
  EqPlacement placement;
  EqSlope slope;
  bool enabled;

  // Dynamic EQ
  bool dynamicEnabled;
  double dynamicThreshold;
  double dynamicRatio;
  double dynamicAttack;
  double dynamicRelease;

  EqBand({
    required this.index,
    this.freq = 1000.0,
    this.gain = 0.0,
    this.q = 1.0,
    this.shape = EqFilterShape.bell,
    this.placement = EqPlacement.stereo,
    this.slope = EqSlope.db12,
    this.enabled = true,
    this.dynamicEnabled = false,
    this.dynamicThreshold = -20.0,
    this.dynamicRatio = 2.0,
    this.dynamicAttack = 10.0,
    this.dynamicRelease = 100.0,
  });

  EqBand copyWith({
    int? index,
    double? freq,
    double? gain,
    double? q,
    EqFilterShape? shape,
    EqPlacement? placement,
    EqSlope? slope,
    bool? enabled,
    bool? dynamicEnabled,
    double? dynamicThreshold,
    double? dynamicRatio,
    double? dynamicAttack,
    double? dynamicRelease,
  }) {
    return EqBand(
      index: index ?? this.index,
      freq: freq ?? this.freq,
      gain: gain ?? this.gain,
      q: q ?? this.q,
      shape: shape ?? this.shape,
      placement: placement ?? this.placement,
      slope: slope ?? this.slope,
      enabled: enabled ?? this.enabled,
      dynamicEnabled: dynamicEnabled ?? this.dynamicEnabled,
      dynamicThreshold: dynamicThreshold ?? this.dynamicThreshold,
      dynamicRatio: dynamicRatio ?? this.dynamicRatio,
      dynamicAttack: dynamicAttack ?? this.dynamicAttack,
      dynamicRelease: dynamicRelease ?? this.dynamicRelease,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// FabFilter Pro-Q style EQ panel
class FabFilterEqPanel extends FabFilterPanelBase {
  const FabFilterEqPanel({
    super.key,
    required super.trackId,
    super.sampleRate,
    super.onSettingsChanged,
  }) : super(
          title: 'PRO-Q 64',
          icon: Icons.equalizer,
          accentColor: FabFilterColors.blue,
          nodeType: DspNodeType.eq,
        );

  @override
  State<FabFilterEqPanel> createState() => _FabFilterEqPanelState();
}

class _FabFilterEqPanelState extends State<FabFilterEqPanel>
    with FabFilterPanelMixin<FabFilterEqPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // DSPCHAINPROVIDER INTEGRATION (FIX: Uses real insert chain)
  // ═══════════════════════════════════════════════════════════════════════════
  String _nodeId = '';
  int _slotIndex = -1;

  @override
  int get processorSlotIndex => _slotIndex;

  /// Parameter index formula for ProEqWrapper:
  /// index = band_index * 11 + param_index
  /// Params per band:
  ///   0: Frequency (10-30000 Hz)
  ///   1: Gain (-30 to +30 dB)
  ///   2: Q (0.05 to 50)
  ///   3: Enabled (0 or 1)
  ///   4: Shape (0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut, 5=Notch, 6=Bandpass, 7=TiltShelf, 8=Allpass, 9=Brickwall)
  ///   5-10: Dynamic EQ params (enabled, threshold, ratio, attack, release, knee)
  static const int _paramsPerBand = 11;

  // EQ Bands
  final List<EqBand> _bands = [];
  int? _selectedBandIndex;
  int? _hoverBandIndex;

  // Settings
  double _outputGain = 0.0;
  AnalyzerMode _analyzerMode = AnalyzerMode.postEq;
  bool _autoGain = false;

  // Spectrum data
  List<double> _spectrumPre = [];
  List<double> _spectrumPost = [];
  List<(double, double)> _eqCurve = [];
  Timer? _spectrumTimer;

  // Interaction
  bool _isDraggingBand = false;
  Offset? _previewPosition;
  EqFilterShape _previewShape = EqFilterShape.bell;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _spectrumTimer?.cancel();
    // NOTE: Don't remove the EQ from DspChainProvider on dispose
    // The node lifecycle is managed by DspChainProvider, not by this panel.
    // Old ghost FFI cleanup removed: _ffi.proEqDestroy(widget.trackId);
    super.dispose();
  }

  /// Initialize EQ processor via DspChainProvider (FIX: Uses real insert chain)
  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    // Find existing EQ node or add one
    DspNode? eqNode;
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.eq) {
        eqNode = node;
        break;
      }
    }

    if (eqNode == null) {
      // Add EQ via DspChainProvider (calls insertLoadProcessor FFI)
      dsp.addNode(widget.trackId, DspNodeType.eq);
      final updatedChain = dsp.getChain(widget.trackId);
      if (updatedChain.nodes.isNotEmpty) {
        eqNode = updatedChain.nodes.last;
      }
    }

    if (eqNode != null) {
      _nodeId = eqNode.id;
      _slotIndex = dsp.getChain(widget.trackId).nodes.indexWhere((n) => n.id == _nodeId);
      setState(() => _initialized = true);
      _startSpectrumUpdate();
    } else {
    }
  }

  void _startSpectrumUpdate() {
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted && _initialized && _analyzerMode != AnalyzerMode.off) {
        // Use master spectrum from PlaybackEngine — real FFT data from audio stream
        // Data is already log-scaled (20Hz-20kHz) and normalized 0-1 (-80dB to 0dB)
        final rawSpectrum = _ffi.getMasterSpectrum();
        bool hasData = false;
        for (int i = 0; i < rawSpectrum.length; i++) {
          if (rawSpectrum[i] > 0.001) {
            hasData = true;
            break;
          }
        }

        // Convert normalized 0-1 to dB: 0.0 = -80dB, 1.0 = 0dB
        final spectrumDb = List<double>.filled(rawSpectrum.length, -80.0);
        for (int i = 0; i < rawSpectrum.length; i++) {
          final v = rawSpectrum[i].clamp(0.0, 1.0);
          spectrumDb[i] = v * 80.0 - 80.0;
        }

        // Smooth spectrum with decay (FabFilter-style ballistics)
        // Rise fast (0.6), fall slow (0.15) — creates smooth decay effect
        final prevLen = _spectrumPost.length;
        final newLen = spectrumDb.length;
        if (hasData || prevLen > 0) {
          final smoothed = List<double>.filled(newLen, -80.0);
          for (int i = 0; i < newLen; i++) {
            final target = spectrumDb[i];
            final prev = i < prevLen ? _spectrumPost[i] : -80.0;
            if (target > prev) {
              // Rise fast
              smoothed[i] = prev + (target - prev) * 0.6;
            } else {
              // Decay slow
              smoothed[i] = prev + (target - prev) * 0.15;
            }
          }
          // Only update if there's visible change
          bool changed = prevLen != newLen;
          if (!changed) {
            for (int i = 0; i < newLen; i++) {
              if ((smoothed[i] - _spectrumPost[i]).abs() > 0.1) {
                changed = true;
                break;
              }
            }
          }
          if (changed) {
            setState(() {
              _spectrumPost = smoothed;
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildHeader(),
          Expanded(
            child: Column(
              children: [
                // Main display area
                Expanded(flex: 3, child: _buildMainDisplay()),

                // Toolbar
                _buildToolbar(),

                // Band list
                _buildBandList(),

                // Band editor (if selected)
                if (_selectedBandIndex != null) _buildBandEditor(),
              ],
            ),
          ),
          buildBottomBar(),
        ],
      ),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN DISPLAY (Spectrum + EQ Graph)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMainDisplay() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: FabFilterDecorations.display(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return MouseRegion(
            onHover: (event) => _handleHover(event.localPosition, constraints.biggest),
            onExit: (_) => setState(() {
              _hoverBandIndex = null;
              _previewPosition = null;
            }),
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _handleScroll(event, constraints.biggest);
                }
              },
              child: GestureDetector(
                onTapDown: (d) => _handleTap(d.localPosition, constraints.biggest),
                onPanStart: (d) => _handleDragStart(d.localPosition, constraints.biggest),
                onPanUpdate: (d) => _handleDragUpdate(d.localPosition, constraints.biggest),
                onPanEnd: (_) => _handleDragEnd(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CustomPaint(
                    painter: _EqGraphPainter(
                      bands: _bands,
                      selectedIndex: _selectedBandIndex,
                      hoverIndex: _hoverBandIndex,
                      spectrumPre: _spectrumPre,
                      spectrumPost: _spectrumPost,
                      eqCurve: _eqCurve,
                      analyzerMode: _analyzerMode,
                      previewPosition: _previewPosition,
                      previewShape: _previewShape,
                      isDragging: _isDraggingBand,
                    ),
                    size: constraints.biggest,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleHover(Offset position, Size size) {
    // Check if hovering over a band
    for (int i = 0; i < _bands.length; i++) {
      final band = _bands[i];
      if (!band.enabled) continue;
      final x = _freqToX(band.freq, size.width);
      final y = _gainToY(band.gain, size.height);
      if ((Offset(x, y) - position).distance < 15) {
        setState(() {
          _hoverBandIndex = i;
          _previewPosition = null;
        });
        return;
      }
    }

    // Show preview position
    setState(() {
      _hoverBandIndex = null;
      _previewPosition = position;
    });
  }

  void _handleScroll(PointerScrollEvent event, Size size) {
    // Adjust Q of selected or hovered band
    final bandIndex = _selectedBandIndex ?? _hoverBandIndex;
    if (bandIndex == null || bandIndex >= _bands.length) return;

    final band = _bands[bandIndex];
    final delta = event.scrollDelta.dy > 0 ? -0.2 : 0.2;
    final isFine = HardwareKeyboard.instance.isShiftPressed;
    final step = isFine ? delta * 0.1 : delta;

    setState(() {
      band.q = (band.q + step).clamp(0.1, 30.0);
    });
    _updateBand(bandIndex);
  }

  void _handleTap(Offset position, Size size) {
    // Check if clicking on existing band
    for (int i = 0; i < _bands.length; i++) {
      final band = _bands[i];
      if (!band.enabled) continue;
      final x = _freqToX(band.freq, size.width);
      final y = _gainToY(band.gain, size.height);
      if ((Offset(x, y) - position).distance < 15) {
        setState(() => _selectedBandIndex = i);
        return;
      }
    }

    // Add new band
    final freq = _xToFreq(position.dx, size.width);
    _addBand(freq, _previewShape);
  }

  void _handleDragStart(Offset position, Size size) {
    // Find band being dragged
    for (int i = 0; i < _bands.length; i++) {
      final band = _bands[i];
      if (!band.enabled) continue;
      final x = _freqToX(band.freq, size.width);
      final y = _gainToY(band.gain, size.height);
      if ((Offset(x, y) - position).distance < 15) {
        setState(() {
          _selectedBandIndex = i;
          _isDraggingBand = true;
        });
        return;
      }
    }
  }

  void _handleDragUpdate(Offset position, Size size) {
    if (!_isDraggingBand || _selectedBandIndex == null) return;

    final band = _bands[_selectedBandIndex!];
    final newFreq = _xToFreq(position.dx, size.width).clamp(10.0, 30000.0);
    final newGain = _yToGain(position.dy, size.height).clamp(-30.0, 30.0);

    setState(() {
      band.freq = newFreq;
      band.gain = newGain;
    });
    _updateBand(_selectedBandIndex!);
  }

  void _handleDragEnd() {
    setState(() => _isDraggingBand = false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOOLBAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: FabFilterColors.borderSubtle),
          bottom: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Analyzer mode
          buildDropdown<AnalyzerMode>(
            'Analyzer',
            _analyzerMode,
            AnalyzerMode.values,
            (m) => _analyzerModeName(m),
            (v) {
              setState(() => _analyzerMode = v);
              _ffi.proEqSetAnalyzerMode(widget.trackId, _analyzerModeToProEq(v));
            },
          ),

          const SizedBox(width: 16),

          // Auto-gain
          buildToggle('Auto-Gain', _autoGain, (v) {
            setState(() => _autoGain = v);
            _ffi.proEqSetAutoGain(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),

          const Spacer(),

          // Output gain
          _buildOutputGain(),

          const SizedBox(width: 12),

          // Reset
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            color: FabFilterColors.textTertiary,
            onPressed: _resetEq,
            tooltip: 'Reset EQ',
          ),
        ],
      ),
    );
  }

  Widget _buildOutputGain() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('OUT', style: FabFilterText.paramLabel),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: fabFilterSliderTheme(FabFilterColors.blue),
            child: Slider(
              value: (_outputGain + 24) / 48,
              onChanged: (v) {
                setState(() => _outputGain = v * 48 - 24);
                _ffi.proEqSetOutputGain(widget.trackId, _outputGain);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${_outputGain >= 0 ? '+' : ''}${_outputGain.toStringAsFixed(1)} dB',
            style: FabFilterText.paramValue(FabFilterColors.blue),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBandList() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text('BANDS', style: FabFilterText.sectionHeader),
          const SizedBox(width: 12),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _bands.length,
              itemBuilder: (context, index) => _buildBandChip(index),
            ),
          ),
          const SizedBox(width: 8),
          // Add band menu
          PopupMenuButton<EqFilterShape>(
            icon: const Icon(
              Icons.add_circle_outline,
              color: FabFilterColors.blue,
              size: 20,
            ),
            tooltip: 'Add Band',
            color: FabFilterColors.bgMid,
            itemBuilder: (context) => EqFilterShape.values
                .map((shape) => PopupMenuItem(
                      value: shape,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getShapeColor(shape),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _shapeName(shape),
                            style: const TextStyle(
                              color: FabFilterColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
            onSelected: (shape) {
              setState(() => _previewShape = shape);
              _addBand(1000.0, shape);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBandChip(int index) {
    final band = _bands[index];
    final isSelected = index == _selectedBandIndex;
    final color = _getShapeColor(band.shape);

    return GestureDetector(
      onTap: () => setState(() => _selectedBandIndex = index),
      onLongPress: () => _removeBand(index),
      child: AnimatedOpacity(
        duration: FabFilterDurations.fast,
        opacity: band.enabled ? 1.0 : 0.5,
        child: AnimatedContainer(
          duration: FabFilterDurations.fast,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: FabFilterDecorations.chip(color, selected: isSelected),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (band.dynamicEnabled)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.flash_on,
                    size: 10,
                    color: isSelected ? FabFilterColors.textPrimary : color,
                  ),
                ),
              Text(
                _formatFreq(band.freq),
                style: TextStyle(
                  color: isSelected ? FabFilterColors.textPrimary : color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND EDITOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBandEditor() {
    if (_selectedBandIndex == null || _selectedBandIndex! >= _bands.length) {
      return const SizedBox();
    }

    final band = _bands[_selectedBandIndex!];
    final color = _getShapeColor(band.shape);

    return AnimatedContainer(
      duration: FabFilterDurations.normal,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        border: const Border(
          top: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          // Row 1: Shape, Placement, Enable, Delete
          Row(
            children: [
              // Shape selector
              Expanded(
                flex: 2,
                child: _buildShapeSelector(band),
              ),
              const SizedBox(width: 12),
              // Placement
              Expanded(
                child: _buildPlacementSelector(band),
              ),
              const SizedBox(width: 12),
              // Enable toggle
              buildToggle(
                band.enabled ? 'ON' : 'OFF',
                band.enabled,
                (v) {
                  setState(() => band.enabled = v);
                  _updateBand(_selectedBandIndex!);
                },
                activeColor: FabFilterColors.green,
              ),
              const SizedBox(width: 8),
              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: FabFilterColors.red,
                onPressed: () => _removeBand(_selectedBandIndex!),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Row 2: Freq, Gain, Q
          Row(
            children: [
              Expanded(
                flex: 2,
                child: buildSliderRow(
                  'FREQ',
                  band.freq,
                  10,
                  30000,
                  _formatFreq(band.freq),
                  (v) {
                    setState(() => band.freq = v);
                    _updateBand(_selectedBandIndex!);
                  },
                  color: color,
                  logarithmic: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: buildSliderRow(
                  'GAIN',
                  band.gain,
                  -30,
                  30,
                  '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB',
                  (v) {
                    setState(() => band.gain = v);
                    _updateBand(_selectedBandIndex!);
                  },
                  color: band.gain >= 0 ? FabFilterColors.orange : FabFilterColors.cyan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: buildSliderRow(
                  'Q',
                  band.q,
                  0.1,
                  30,
                  band.q.toStringAsFixed(2),
                  (v) {
                    setState(() => band.q = v);
                    _updateBand(_selectedBandIndex!);
                  },
                  color: color,
                  logarithmic: true,
                ),
              ),
            ],
          ),

          // Dynamic EQ section (if expert mode)
          if (showExpertMode) ...[
            const SizedBox(height: 12),
            _buildDynamicEqSection(band, color),
          ],
        ],
      ),
    );
  }

  Widget _buildShapeSelector(EqBand band) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: EqFilterShape.values.map((shape) {
          final isSelected = band.shape == shape;
          final shapeColor = _getShapeColor(shape);
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () {
                setState(() => band.shape = shape);
                _updateBand(_selectedBandIndex!);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: FabFilterDecorations.chip(shapeColor, selected: isSelected),
                child: Text(
                  _shapeName(shape),
                  style: TextStyle(
                    color: isSelected ? FabFilterColors.textPrimary : shapeColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlacementSelector(EqBand band) {
    return buildDropdown<EqPlacement>(
      '',
      band.placement,
      EqPlacement.values,
      (p) => p.name.toUpperCase(),
      (v) {
        setState(() => band.placement = v);
        _updateBand(_selectedBandIndex!);
      },
    );
  }

  Widget _buildDynamicEqSection(EqBand band, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            buildToggle(
              'Dynamic EQ',
              band.dynamicEnabled,
              (v) {
                setState(() => band.dynamicEnabled = v);
                _updateBand(_selectedBandIndex!);
              },
              activeColor: FabFilterColors.yellow,
            ),
          ],
        ),
        if (band.dynamicEnabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: buildSliderRow(
                  'Thresh',
                  band.dynamicThreshold,
                  -60,
                  0,
                  '${band.dynamicThreshold.toStringAsFixed(1)} dB',
                  (v) {
                    setState(() => band.dynamicThreshold = v);
                    _updateBand(_selectedBandIndex!);
                  },
                  color: FabFilterColors.yellow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: buildSliderRow(
                  'Ratio',
                  band.dynamicRatio,
                  1,
                  20,
                  '${band.dynamicRatio.toStringAsFixed(1)}:1',
                  (v) {
                    setState(() => band.dynamicRatio = v);
                    _updateBand(_selectedBandIndex!);
                  },
                  color: FabFilterColors.yellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: buildSliderRow(
                  'Attack',
                  band.dynamicAttack,
                  0.1,
                  500,
                  '${band.dynamicAttack.toStringAsFixed(1)} ms',
                  (v) {
                    setState(() => band.dynamicAttack = v);
                    _updateBand(_selectedBandIndex!);
                  },
                  color: FabFilterColors.yellow,
                  logarithmic: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: buildSliderRow(
                  'Release',
                  band.dynamicRelease,
                  1,
                  5000,
                  '${band.dynamicRelease.toInt()} ms',
                  (v) {
                    setState(() => band.dynamicRelease = v);
                    _updateBand(_selectedBandIndex!);
                  },
                  color: FabFilterColors.yellow,
                  logarithmic: true,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new EQ band (FIX: Uses insertSetParam)
  void _addBand(double freq, EqFilterShape shape) {
    if (_bands.length >= 64 || _slotIndex < 0) return;

    final bandIndex = _bands.length;
    final band = EqBand(index: bandIndex, freq: freq, shape: shape);

    // Set band parameters via insert chain
    _setBandParam(bandIndex, 0, freq);       // Frequency
    _setBandParam(bandIndex, 1, 0.0);        // Gain
    _setBandParam(bandIndex, 2, 1.0);        // Q
    _setBandParam(bandIndex, 3, 1.0);        // Enabled
    _setBandParam(bandIndex, 4, _shapeToParamValue(shape)); // Shape


    setState(() {
      _bands.add(band);
      _selectedBandIndex = _bands.length - 1;
    });
    widget.onSettingsChanged?.call();
  }

  /// Update an existing EQ band (FIX: Uses insertSetParam)
  void _updateBand(int index) {
    if (_slotIndex < 0 || index >= _bands.length) return;

    final band = _bands[index];

    // Set band parameters via insert chain
    _setBandParam(band.index, 0, band.freq);  // Frequency
    _setBandParam(band.index, 1, band.gain);  // Gain
    _setBandParam(band.index, 2, band.q);     // Q
    _setBandParam(band.index, 3, band.enabled ? 1.0 : 0.0); // Enabled
    _setBandParam(band.index, 4, _shapeToParamValue(band.shape)); // Shape

    // Dynamic EQ params (if enabled)
    _setBandParam(band.index, 5, band.dynamicEnabled ? 1.0 : 0.0); // Dynamic enabled
    _setBandParam(band.index, 6, band.dynamicThreshold);  // Threshold
    _setBandParam(band.index, 7, band.dynamicRatio);      // Ratio
    _setBandParam(band.index, 8, band.dynamicAttack);     // Attack
    _setBandParam(band.index, 9, band.dynamicRelease);    // Release
    // Note: Placement and Slope not exposed via InsertProcessor API

    widget.onSettingsChanged?.call();
  }

  /// Remove an EQ band (FIX: Uses insertSetParam to disable)
  void _removeBand(int index) {
    if (_slotIndex < 0 || index >= _bands.length) return;

    final band = _bands[index];
    // Disable the band instead of removing (InsertProcessor doesn't support band removal)
    _setBandParam(band.index, 3, 0.0); // Disable band

    setState(() {
      _bands.removeAt(index);
      _selectedBandIndex = _bands.isEmpty ? null : math.max(0, index - 1);
    });
    widget.onSettingsChanged?.call();
  }

  /// Reset all EQ bands (FIX: Uses insertSetParam to disable all)
  void _resetEq() {
    if (_slotIndex < 0) return;

    // Disable all bands
    for (int i = 0; i < 64; i++) {
      _setBandParam(i, 3, 0.0); // Disable
      _setBandParam(i, 1, 0.0); // Zero gain
    }

    setState(() {
      _bands.clear();
      _selectedBandIndex = null;
    });
    widget.onSettingsChanged?.call();
  }

  /// Helper: Set a single band parameter via insertSetParam
  void _setBandParam(int bandIndex, int paramIndex, double value) {
    if (_slotIndex < 0) return;
    final index = bandIndex * _paramsPerBand + paramIndex;
    _ffi.insertSetParam(widget.trackId, _slotIndex, index, value);
  }

  /// Convert EqFilterShape to ProEqWrapper param value
  double _shapeToParamValue(EqFilterShape shape) {
    return switch (shape) {
      EqFilterShape.bell => 0.0,
      EqFilterShape.lowShelf => 1.0,
      EqFilterShape.highShelf => 2.0,
      EqFilterShape.lowCut => 3.0,
      EqFilterShape.highCut => 4.0,
      EqFilterShape.notch => 5.0,
      EqFilterShape.bandPass => 6.0,
      EqFilterShape.tiltShelf => 7.0,
      EqFilterShape.allPass => 8.0,
      EqFilterShape.brickwall => 9.0,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  double _freqToX(double freq, double width) {
    const minLog = 1.0; // log10(10)
    const maxLog = 4.477; // log10(30000)
    return ((math.log(freq.clamp(10, 30000)) / math.ln10 - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.0;
    const maxLog = 4.477;
    return math.pow(10, minLog + (x / width) * (maxLog - minLog)).toDouble();
  }

  double _gainToY(double gain, double height) {
    return height / 2 - (gain / 30) * (height / 2);
  }

  double _yToGain(double y, double height) {
    return ((height / 2 - y) / (height / 2)) * 30;
  }

  String _formatFreq(double freq) {
    if (freq >= 1000) {
      return '${(freq / 1000).toStringAsFixed(freq >= 10000 ? 0 : 1)} kHz';
    }
    return '${freq.toInt()} Hz';
  }

  String _shapeName(EqFilterShape shape) {
    return switch (shape) {
      EqFilterShape.bell => 'Bell',
      EqFilterShape.lowShelf => 'Low Shelf',
      EqFilterShape.highShelf => 'High Shelf',
      EqFilterShape.lowCut => 'Low Cut',
      EqFilterShape.highCut => 'High Cut',
      EqFilterShape.notch => 'Notch',
      EqFilterShape.bandPass => 'Bandpass',
      EqFilterShape.tiltShelf => 'Tilt',
      EqFilterShape.allPass => 'Allpass',
      EqFilterShape.brickwall => 'Brickwall',
    };
  }

  Color _getShapeColor(EqFilterShape shape) {
    return switch (shape) {
      EqFilterShape.bell => FabFilterColors.blue,
      EqFilterShape.lowShelf => FabFilterColors.orange,
      EqFilterShape.highShelf => FabFilterColors.yellow,
      EqFilterShape.lowCut => FabFilterColors.red,
      EqFilterShape.highCut => FabFilterColors.red,
      EqFilterShape.notch => FabFilterColors.pink,
      EqFilterShape.bandPass => FabFilterColors.green,
      EqFilterShape.tiltShelf => FabFilterColors.cyan,
      EqFilterShape.allPass => FabFilterColors.textTertiary,
      EqFilterShape.brickwall => FabFilterColors.red,
    };
  }

  String _analyzerModeName(AnalyzerMode mode) {
    return switch (mode) {
      AnalyzerMode.off => 'OFF',
      AnalyzerMode.preEq => 'PRE',
      AnalyzerMode.postEq => 'POST',
      AnalyzerMode.prePlusPost => 'PRE+POST',
    };
  }

  // FFI enum conversions
  ProEqFilterShape _shapeToProEq(EqFilterShape shape) {
    return switch (shape) {
      EqFilterShape.bell => ProEqFilterShape.bell,
      EqFilterShape.lowShelf => ProEqFilterShape.lowShelf,
      EqFilterShape.highShelf => ProEqFilterShape.highShelf,
      EqFilterShape.lowCut => ProEqFilterShape.lowCut,
      EqFilterShape.highCut => ProEqFilterShape.highCut,
      EqFilterShape.notch => ProEqFilterShape.notch,
      EqFilterShape.bandPass => ProEqFilterShape.bandPass,
      EqFilterShape.tiltShelf => ProEqFilterShape.tiltShelf,
      EqFilterShape.allPass => ProEqFilterShape.allPass,
      EqFilterShape.brickwall => ProEqFilterShape.brickwall,
    };
  }

  ProEqPlacement _placementToProEq(EqPlacement placement) {
    return switch (placement) {
      EqPlacement.stereo => ProEqPlacement.stereo,
      EqPlacement.left => ProEqPlacement.left,
      EqPlacement.right => ProEqPlacement.right,
      EqPlacement.mid => ProEqPlacement.mid,
      EqPlacement.side => ProEqPlacement.side,
    };
  }

  ProEqSlope _slopeToProEq(EqSlope slope) {
    return switch (slope) {
      EqSlope.db6 => ProEqSlope.db6,
      EqSlope.db12 => ProEqSlope.db12,
      EqSlope.db18 => ProEqSlope.db18,
      EqSlope.db24 => ProEqSlope.db24,
      EqSlope.db36 => ProEqSlope.db36,
      EqSlope.db48 => ProEqSlope.db48,
      EqSlope.db72 => ProEqSlope.db72,
      EqSlope.db96 => ProEqSlope.db96,
      EqSlope.brickwall => ProEqSlope.brickwall,
    };
  }

  ProEqAnalyzerMode _analyzerModeToProEq(AnalyzerMode mode) {
    return switch (mode) {
      AnalyzerMode.off => ProEqAnalyzerMode.off,
      AnalyzerMode.preEq => ProEqAnalyzerMode.preEq,
      AnalyzerMode.postEq => ProEqAnalyzerMode.postEq,
      AnalyzerMode.prePlusPost => ProEqAnalyzerMode.delta, // Uses delta for combined view
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _EqGraphPainter extends CustomPainter {
  final List<EqBand> bands;
  final int? selectedIndex;
  final int? hoverIndex;
  final List<double> spectrumPre;
  final List<double> spectrumPost;
  final List<(double, double)> eqCurve;
  final AnalyzerMode analyzerMode;
  final Offset? previewPosition;
  final EqFilterShape previewShape;
  final bool isDragging;

  _EqGraphPainter({
    required this.bands,
    required this.selectedIndex,
    required this.hoverIndex,
    required this.spectrumPre,
    required this.spectrumPost,
    required this.eqCurve,
    required this.analyzerMode,
    required this.previewPosition,
    required this.previewShape,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = FabFilterColors.bgVoid,
    );

    // Grid
    _drawGrid(canvas, size);

    // Spectrum (if enabled)
    if (analyzerMode != AnalyzerMode.off) {
      if (spectrumPost.isNotEmpty) {
        _drawSpectrum(canvas, size, spectrumPost, FabFilterColors.blue.withValues(alpha: 0.3));
      }
    }

    // EQ curve
    _drawEqCurve(canvas, size);

    // Preview indicator
    if (previewPosition != null && !isDragging) {
      _drawPreviewIndicator(canvas, size, previewPosition!);
    }

    // Band markers
    _drawBandMarkers(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FabFilterColors.borderSubtle
      ..strokeWidth = 1;

    // Frequency lines (100Hz, 1kHz, 10kHz)
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // dB lines
    final centerY = size.height / 2;
    paint.color = FabFilterColors.borderMedium;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint);

    paint.color = FabFilterColors.borderSubtle;
    for (final db in [-12.0, -6.0, 6.0, 12.0]) {
      final y = centerY - (db / 30) * (size.height / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawSpectrum(Canvas canvas, Size size, List<double> spectrum, Color color) {
    if (spectrum.length < 2) return;

    // Frequency-proportional smoothing (FabFilter Pro-Q style)
    // Low frequencies get more smoothing to eliminate FFT bin stepping
    final smoothed = List<double>.from(spectrum);
    for (int pass = 0; pass < 3; pass++) {
      final prev = List<double>.from(smoothed);
      for (int i = 1; i < smoothed.length - 1; i++) {
        // Bins 0-128 are 20Hz-500Hz range (log-scaled), need most smoothing
        // Bins 128-512 are 500Hz-20kHz, need less smoothing
        final ratio = i / smoothed.length;
        final radius = ratio < 0.25
            ? 6  // Heavy smoothing for sub-500Hz
            : ratio < 0.5
                ? 3  // Medium smoothing for 500Hz-2kHz
                : 1; // Light smoothing for 2kHz+
        double sum = 0;
        int count = 0;
        for (int j = -radius; j <= radius; j++) {
          final idx = (i + j).clamp(0, prev.length - 1);
          sum += prev[idx];
          count++;
        }
        smoothed[i] = sum / count;
      }
    }

    // Pre-compute points for Catmull-Rom spline interpolation
    final points = <Offset>[];
    for (int i = 0; i < smoothed.length; i++) {
      final x = (i / (smoothed.length - 1)) * size.width;
      final db = smoothed[i].clamp(-80.0, 0.0);
      final y = size.height - ((db + 80) / 80) * size.height;
      points.add(Offset(x, y));
    }

    // Build smooth curve path using Catmull-Rom to cubic bezier conversion
    final curvePath = Path();
    curvePath.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      // Catmull-Rom control points: p0, p1, p2, p3
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

      // Convert Catmull-Rom to cubic bezier control points
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6.0,
        p1.dy + (p2.dy - p0.dy) / 6.0,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6.0,
        p2.dy - (p3.dy - p1.dy) / 6.0,
      );

      curvePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    // Fill path: close to bottom
    final fillPath = Path()..addPath(curvePath, Offset.zero);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    // Filled area with gradient for depth
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color,
          color.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Stroke line on top for definition
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawEqCurve(Canvas canvas, Size size) {
    final path = Path();
    final centerY = size.height / 2;

    // Calculate curve from bands
    for (int i = 0; i <= size.width.toInt(); i++) {
      final x = i.toDouble();
      final freq = _xToFreq(x, size.width);
      double totalDb = 0;

      for (final band in bands) {
        if (!band.enabled) continue;
        totalDb += _calculateBandResponse(freq, band);
      }

      final y = centerY - (totalDb / 30) * (size.height / 2);
      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(size.width, centerY)
      ..lineTo(0, centerY)
      ..close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        FabFilterColors.orange.withValues(alpha: 0.15),
        FabFilterColors.cyan.withValues(alpha: 0.15),
      ],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, Paint()..shader = gradient);

    // Stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = FabFilterColors.blue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawPreviewIndicator(Canvas canvas, Size size, Offset position) {
    final color = _getShapeColor(previewShape).withValues(alpha: 0.5);

    // Crosshair
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(position.dx, 0),
      Offset(position.dx, size.height),
      paint..color = color.withValues(alpha: 0.3),
    );
    canvas.drawLine(
      Offset(0, position.dy),
      Offset(size.width, position.dy),
      paint..color = color.withValues(alpha: 0.3),
    );

    // Preview dot
    canvas.drawCircle(position, 8, Paint()..color = color);
    canvas.drawCircle(
      position,
      8,
      Paint()
        ..color = FabFilterColors.textPrimary.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawBandMarkers(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      if (!band.enabled) continue;

      final x = _freqToX(band.freq, size.width);
      final y = centerY - (band.gain / 30) * (size.height / 2);
      final color = _getShapeColor(band.shape);

      final isSelected = i == selectedIndex;
      final isHover = i == hoverIndex;
      final radius = isSelected ? 10.0 : (isHover ? 8.0 : 6.0);

      // Glow for selected/hover
      if (isSelected || isHover) {
        canvas.drawCircle(
          Offset(x, y.clamp(radius, size.height - radius)),
          radius + 4,
          Paint()..color = color.withValues(alpha: 0.3),
        );
      }

      // Main dot
      canvas.drawCircle(
        Offset(x, y.clamp(radius, size.height - radius)),
        radius,
        Paint()..color = color,
      );

      // Selection ring
      if (isSelected) {
        canvas.drawCircle(
          Offset(x, y.clamp(radius, size.height - radius)),
          radius + 3,
          Paint()
            ..color = FabFilterColors.textPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      // Dynamic indicator
      if (band.dynamicEnabled) {
        canvas.drawCircle(
          Offset(x, y.clamp(radius, size.height - radius) - radius - 6),
          3,
          Paint()..color = FabFilterColors.yellow,
        );
      }
    }
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.0;
    const maxLog = 4.477;
    return ((math.log(freq.clamp(10, 30000)) / math.ln10 - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.0;
    const maxLog = 4.477;
    return math.pow(10, minLog + (x / width) * (maxLog - minLog)).toDouble();
  }

  double _calculateBandResponse(double freq, EqBand band) {
    final ratio = freq / band.freq;
    final logRatio = math.log(ratio) / math.ln2;

    return switch (band.shape) {
      EqFilterShape.bell => band.gain * math.exp(-math.pow(logRatio * band.q, 2)),
      EqFilterShape.lowShelf => band.gain * (1 - 1 / (1 + math.exp(-logRatio * 4))),
      EqFilterShape.highShelf => band.gain * (1 / (1 + math.exp(-logRatio * 4))),
      EqFilterShape.lowCut => ratio < 1 ? -30 * (1 - ratio) : 0,
      EqFilterShape.highCut => ratio > 1 ? -30 * (ratio - 1) : 0,
      EqFilterShape.notch => -math.min(30.0, 30 * math.exp(-math.pow(logRatio * band.q * 2, 2))),
      EqFilterShape.bandPass => math.exp(-math.pow(logRatio * band.q, 2)) * 12 - 6,
      EqFilterShape.tiltShelf => band.gain * logRatio.clamp(-2.0, 2.0) / 2,
      _ => 0,
    };
  }

  Color _getShapeColor(EqFilterShape shape) {
    return switch (shape) {
      EqFilterShape.bell => FabFilterColors.blue,
      EqFilterShape.lowShelf => FabFilterColors.orange,
      EqFilterShape.highShelf => FabFilterColors.yellow,
      EqFilterShape.lowCut => FabFilterColors.red,
      EqFilterShape.highCut => FabFilterColors.red,
      EqFilterShape.notch => FabFilterColors.pink,
      EqFilterShape.bandPass => FabFilterColors.green,
      EqFilterShape.tiltShelf => FabFilterColors.cyan,
      EqFilterShape.allPass => FabFilterColors.textTertiary,
      EqFilterShape.brickwall => FabFilterColors.red,
    };
  }

  @override
  bool shouldRepaint(covariant _EqGraphPainter old) {
    return bands != old.bands ||
        selectedIndex != old.selectedIndex ||
        hoverIndex != old.hoverIndex ||
        spectrumPost != old.spectrumPost ||
        analyzerMode != old.analyzerMode ||
        previewPosition != old.previewPosition ||
        isDragging != old.isDragging;
  }
}
