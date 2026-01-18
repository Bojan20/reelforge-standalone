/// Audio Alignment Panel - VocAlign-style alignment UI
///
/// Features:
/// - Guide/Dub selection
/// - Alignment algorithm settings
/// - Processing progress
/// - Waveform comparison view

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_alignment_provider.dart';
import '../../theme/fluxforge_theme.dart';

class AudioAlignmentPanel extends StatelessWidget {
  const AudioAlignmentPanel({super.key});

  static const _accentColor = Color(0xFF00D4AA);

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioAlignmentProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              // Header
              _buildHeader(context, provider),

              // Main content
              Expanded(
                child: provider.activeSession == null
                    ? _buildEmptyState(context, provider)
                    : _buildSessionView(context, provider),
              ),

              // Footer
              _buildFooter(context, provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AudioAlignmentProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.align_horizontal_left, size: 16, color: _accentColor),
          const SizedBox(width: 8),
          Text(
            'Audio Alignment',
            style: FluxForgeTheme.label.copyWith(
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),

          const SizedBox(width: 16),

          // Session selector
          if (provider.sessions.isNotEmpty) _buildSessionSelector(provider),

          const Spacer(),

          // New session button
          _buildHeaderButton(
            'New Session',
            Icons.add,
            () => _showNewSessionDialog(context, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionSelector(AudioAlignmentProvider provider) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: provider.activeSession?.id,
          hint: Text(
            'Select Session',
            style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary),
          ),
          isDense: true,
          dropdownColor: FluxForgeTheme.bgElevated,
          style: const TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
          items: provider.sessions.map((s) => DropdownMenuItem(
            value: s.id,
            child: Text(s.name),
          )).toList(),
          onChanged: (id) => provider.setActiveSession(id),
        ),
      ),
    );
  }

  Widget _buildHeaderButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AudioAlignmentProvider provider) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.align_horizontal_left,
            size: 48,
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Alignment Session',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new session to align audio clips',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            'Create Session',
            Icons.add,
            () => _showNewSessionDialog(context, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionView(BuildContext context, AudioAlignmentProvider provider) {
    final session = provider.activeSession!;

    return Row(
      children: [
        // Settings panel (left)
        SizedBox(
          width: 240,
          child: _buildSettingsPanel(provider, session),
        ),

        Container(width: 1, color: FluxForgeTheme.borderSubtle),

        // Waveform comparison (center)
        Expanded(
          child: _buildWaveformComparison(session),
        ),

        Container(width: 1, color: FluxForgeTheme.borderSubtle),

        // Alignment points (right)
        SizedBox(
          width: 200,
          child: _buildAlignmentPoints(provider, session),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel(AudioAlignmentProvider provider, AlignmentSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Session info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildStatusBadge(
                    session.isAnalyzed ? 'Analyzed' : 'Not Analyzed',
                    session.isAnalyzed ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(
                    session.isProcessed ? 'Processed' : 'Not Processed',
                    session.isProcessed ? _accentColor : FluxForgeTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Settings
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Algorithm selector
              _buildSectionHeader('ALGORITHM'),
              const SizedBox(height: 8),
              _buildAlgorithmSelector(provider, session),

              const SizedBox(height: 16),

              // Quality selector
              _buildSectionHeader('QUALITY'),
              const SizedBox(height: 8),
              _buildQualitySelector(provider, session),

              const SizedBox(height: 16),

              // Processing options
              _buildSectionHeader('OPTIONS'),
              const SizedBox(height: 8),
              _buildOptionToggle(
                'Align Timing',
                session.alignTiming,
                (v) => provider.updateSession(
                  session.id,
                  (s) => s.copyWith(alignTiming: v),
                ),
              ),
              _buildOptionToggle(
                'Align Pitch',
                session.alignPitch,
                (v) => provider.updateSession(
                  session.id,
                  (s) => s.copyWith(alignPitch: v),
                ),
              ),
              _buildOptionToggle(
                'Preserve Formants',
                session.preserveFormants,
                (v) => provider.updateSession(
                  session.id,
                  (s) => s.copyWith(preserveFormants: v),
                ),
              ),

              const SizedBox(height: 16),

              // Alignment strength slider
              _buildSectionHeader('ALIGNMENT STRENGTH'),
              const SizedBox(height: 8),
              _buildStrengthSlider(provider, session),

              if (session.correlationScore != null) ...[
                const SizedBox(height: 16),
                _buildSectionHeader('ANALYSIS RESULTS'),
                const SizedBox(height: 8),
                _buildAnalysisResults(session),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: FluxForgeTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildAlgorithmSelector(AudioAlignmentProvider provider, AlignmentSession session) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: AlignmentAlgorithm.values.map((algo) {
        final isSelected = session.algorithm == algo;
        return GestureDetector(
          onTap: () => provider.updateSession(
            session.id,
            (s) => s.copyWith(algorithm: algo),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? _accentColor.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? _accentColor : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Text(
              _getAlgorithmName(algo),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? _accentColor : FluxForgeTheme.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQualitySelector(AudioAlignmentProvider provider, AlignmentSession session) {
    return Row(
      children: AlignmentQuality.values.map((quality) {
        final isSelected = session.quality == quality;
        return Expanded(
          child: GestureDetector(
            onTap: () => provider.updateSession(
              session.id,
              (s) => s.copyWith(quality: quality),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? _accentColor.withValues(alpha: 0.2)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? _accentColor : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Center(
                child: Text(
                  quality.name[0].toUpperCase() + quality.name.substring(1),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? _accentColor : FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOptionToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: value ? _accentColor.withValues(alpha: 0.2) : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: value ? _accentColor : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 12, color: _accentColor)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: value ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrengthSlider(AudioAlignmentProvider provider, AlignmentSession session) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Strength',
              style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary),
            ),
            Text(
              '${(session.alignmentStrength * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: _accentColor,
            inactiveTrackColor: FluxForgeTheme.bgMid,
            thumbColor: _accentColor,
          ),
          child: Slider(
            value: session.alignmentStrength,
            onChanged: (v) => provider.updateSession(
              session.id,
              (s) => s.copyWith(alignmentStrength: v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisResults(AlignmentSession session) {
    return Column(
      children: [
        _buildResultRow(
          'Correlation',
          '${(session.correlationScore! * 100).toStringAsFixed(1)}%',
          session.correlationScore! > 0.8 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange,
        ),
        if (session.averageOffset != null)
          _buildResultRow(
            'Avg Offset',
            '${session.averageOffset!.toStringAsFixed(2)} ms',
            FluxForgeTheme.textPrimary,
          ),
        _buildResultRow(
          'Points',
          '${session.alignmentPoints.length}',
          FluxForgeTheme.textPrimary,
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformComparison(AlignmentSession session) {
    return Column(
      children: [
        // Guide waveform
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mic, size: 12, color: FluxForgeTheme.accentBlue),
                      const SizedBox(width: 6),
                      Text(
                        'Guide (Reference)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: FluxForgeTheme.accentBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Guide: ${session.guideClipId}',
                      style: TextStyle(
                        fontSize: 11,
                        color: FluxForgeTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Dub waveform
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mic_none, size: 12, color: _accentColor),
                      const SizedBox(width: 6),
                      Text(
                        'Dub (To Align)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _accentColor,
                        ),
                      ),
                      const Spacer(),
                      if (session.isProcessed)
                        _buildStatusBadge('Aligned', _accentColor),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Dub: ${session.dubClipId}',
                      style: TextStyle(
                        fontSize: 11,
                        color: FluxForgeTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlignmentPoints(AudioAlignmentProvider provider, AlignmentSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'ALIGNMENT POINTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${session.alignmentPoints.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _accentColor,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: session.alignmentPoints.isEmpty
              ? Center(
                  child: Text(
                    'No points yet\nRun analysis first',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: session.alignmentPoints.length,
                  itemBuilder: (context, index) {
                    final point = session.alignmentPoints[index];
                    return _buildPointCard(provider, session, point);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPointCard(AudioAlignmentProvider provider, AlignmentSession session, AlignmentPoint point) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: point.isManual
              ? FluxForgeTheme.accentOrange.withValues(alpha: 0.3)
              : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Type indicator
          Icon(
            point.isTransient ? Icons.flash_on : Icons.fiber_manual_record,
            size: 12,
            color: point.isManual ? FluxForgeTheme.accentOrange : _accentColor,
          ),
          const SizedBox(width: 8),
          // Position info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${point.guidePosition} → ${point.dubPosition}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                Text(
                  'Confidence: ${(point.confidence * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 9,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Delete button
          GestureDetector(
            onTap: () => provider.removeAlignmentPoint(session.id, point.id),
            child: Icon(
              Icons.close,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AudioAlignmentProvider provider) {
    final session = provider.activeSession;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Processing progress
          if (provider.isProcessing) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: provider.processingProgress,
                strokeWidth: 2,
                valueColor: const AlwaysStoppedAnimation(_accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              provider.processingMessage ?? 'Processing...',
              style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary),
            ),
          ],

          const Spacer(),

          if (session != null) ...[
            // Analyze button
            _buildFooterButton(
              'Analyze',
              Icons.search,
              provider.isProcessing
                  ? null
                  : () => provider.analyzeAlignment(session.id),
              secondary: session.isAnalyzed,
            ),

            const SizedBox(width: 8),

            // Process button
            _buildFooterButton(
              'Align',
              Icons.check,
              !session.isAnalyzed || provider.isProcessing
                  ? null
                  : () => provider.processAlignment(session.id),
            ),

            const SizedBox(width: 8),

            // Undo button
            if (session.isProcessed)
              _buildFooterButton(
                'Undo',
                Icons.undo,
                () => provider.undoAlignment(session.id),
                secondary: true,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooterButton(String label, IconData icon, VoidCallback? onTap, {bool secondary = false}) {
    final isDisabled = onTap == null;
    final color = secondary ? FluxForgeTheme.textSecondary : _accentColor;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: secondary
                ? FluxForgeTheme.bgDeep
                : _accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: secondary ? FluxForgeTheme.borderSubtle : _accentColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _accentColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _accentColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _accentColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getAlgorithmName(AlignmentAlgorithm algo) {
    switch (algo) {
      case AlignmentAlgorithm.crossCorrelation:
        return 'Cross-Corr';
      case AlignmentAlgorithm.dynamicTimeWarp:
        return 'DTW';
      case AlignmentAlgorithm.transientMatch:
        return 'Transient';
      case AlignmentAlgorithm.spectralMatch:
        return 'Spectral';
      case AlignmentAlgorithm.hybrid:
        return 'Hybrid';
    }
  }

  void _showNewSessionDialog(BuildContext context, AudioAlignmentProvider provider) {
    final nameController = TextEditingController(text: 'Alignment ${provider.sessions.length + 1}');
    final guideController = TextEditingController();
    final dubController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: const Text('New Alignment Session', style: TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Session Name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: guideController,
                decoration: const InputDecoration(
                  labelText: 'Guide Clip ID',
                  hintText: 'Reference audio',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dubController,
                decoration: const InputDecoration(
                  labelText: 'Dub Clip ID',
                  hintText: 'Audio to align',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (guideController.text.isNotEmpty && dubController.text.isNotEmpty) {
                provider.createSession(
                  guideClipId: guideController.text,
                  dubClipId: dubController.text,
                  name: nameController.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
