import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/sam_provider.dart';

/// SAM Authoring Panel — wizard steps, archetype selector, smart controls.
class SamAuthoringPanel extends StatefulWidget {
  const SamAuthoringPanel({super.key});

  @override
  State<SamAuthoringPanel> createState() => _SamAuthoringPanelState();
}

class _SamAuthoringPanelState extends State<SamAuthoringPanel> {
  late final SamProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<SamProvider>();
    _provider.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          _buildModeSelector(),
          const SizedBox(height: 6),
          _buildWizardProgress(),
          const SizedBox(height: 6),
          if (_provider.mode == SamAuthoringMode.smart)
            _buildSmartView()
          else if (_provider.mode == SamAuthoringMode.advanced)
            _buildAdvancedView()
          else
            _buildDebugView(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF7E57C2)),
        const SizedBox(width: 4),
        Text(
          'Smart Authoring',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        _buildResetButton(),
      ],
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: () => _provider.reset(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          'Reset',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        for (final mode in SamAuthoringMode.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => _provider.setMode(mode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _provider.mode == mode
                      ? const Color(0xFF7E57C2).withOpacity(0.2)
                      : Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _provider.mode == mode
                        ? const Color(0xFF7E57C2).withOpacity(0.5)
                        : Colors.white.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  mode.displayName,
                  style: TextStyle(
                    color: _provider.mode == mode
                        ? const Color(0xFF7E57C2)
                        : Colors.white.withOpacity(0.5),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWizardProgress() {
    final step = _provider.wizardStep;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Step ${step + 1}/9',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
            ),
            const SizedBox(width: 4),
            if (step < _provider.wizardSteps.length)
              Text(
                _provider.wizardSteps[step].name,
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w500),
              ),
            const Spacer(),
            _buildNavButton(Icons.chevron_left, step > 0, () => _provider.wizardPrev()),
            const SizedBox(width: 2),
            _buildNavButton(Icons.chevron_right, step < 8, () => _provider.wizardNext()),
          ],
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: _provider.wizardProgress,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF7E57C2)),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Icon(
        icon,
        size: 14,
        color: enabled ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.2),
      ),
    );
  }

  Widget _buildSmartView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildArchetypeSelector(),
        const SizedBox(height: 6),
        _buildVolatilitySlider(),
        const SizedBox(height: 6),
        _buildMarketSelector(),
        const SizedBox(height: 4),
        _buildAutoConfigButton(),
        const SizedBox(height: 6),
        _buildControlGroup(SamControlGroup.energy),
        const SizedBox(height: 4),
        _buildControlGroup(SamControlGroup.clarity),
        const SizedBox(height: 4),
        _buildControlGroup(SamControlGroup.stability),
        const SizedBox(height: 6),
        _buildStatusRow(),
      ],
    );
  }

  Widget _buildAdvancedView() {
    // Same as smart but shows all controls in a single list
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildArchetypeSelector(),
        const SizedBox(height: 6),
        for (final ctrl in _provider.controls)
          _buildControlSlider(ctrl),
        const SizedBox(height: 6),
        _buildStatusRow(),
      ],
    );
  }

  Widget _buildDebugView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Raw State',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        for (final ctrl in _provider.controls)
          _buildDebugRow(ctrl),
        const SizedBox(height: 4),
        _buildDebugInfoRow('Archetype', _provider.selectedArchetype >= 0
            ? _provider.archetypes[_provider.selectedArchetype].name : 'None'),
        _buildDebugInfoRow('Volatility', _provider.volatility.toStringAsFixed(4)),
        _buildDebugInfoRow('Market', _provider.market.displayName),
        _buildDebugInfoRow('AutoConfig', _provider.autoConfigured ? 'YES' : 'NO'),
        _buildDebugInfoRow('AIL', _provider.ailPassed
            ? '${_provider.ailScore.toStringAsFixed(0)}' : 'NOT RUN'),
        _buildDebugInfoRow('Certified', _provider.certified ? 'YES' : 'NO'),
      ],
    );
  }

  Widget _buildArchetypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Archetype',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final arch in _provider.archetypes)
              GestureDetector(
                onTap: () => _provider.selectArchetype(arch.index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _provider.selectedArchetype == arch.index
                        ? const Color(0xFF7E57C2).withOpacity(0.2)
                        : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: _provider.selectedArchetype == arch.index
                          ? const Color(0xFF7E57C2).withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    arch.name,
                    style: TextStyle(
                      color: _provider.selectedArchetype == arch.index
                          ? const Color(0xFF7E57C2)
                          : Colors.white.withOpacity(0.5),
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildVolatilitySlider() {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            'Volatility',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: const Color(0xFF7E57C2),
              inactiveTrackColor: Colors.white.withOpacity(0.1),
              thumbColor: const Color(0xFF7E57C2),
            ),
            child: Slider(
              value: _provider.volatility.clamp(_provider.volatilityMin, _provider.volatilityMax),
              min: _provider.volatilityMin,
              max: _provider.volatilityMax,
              onChanged: (v) => _provider.setVolatility(v),
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            _provider.volatility.toStringAsFixed(2),
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketSelector() {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            'Market',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
          ),
        ),
        for (final m in SamMarketTarget.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => _provider.setMarket(m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _provider.market == m
                      ? const Color(0xFF7E57C2).withOpacity(0.15)
                      : Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _provider.market == m
                        ? const Color(0xFF7E57C2).withOpacity(0.4)
                        : Colors.white.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  m.displayName,
                  style: TextStyle(
                    color: _provider.market == m
                        ? const Color(0xFF7E57C2)
                        : Colors.white.withOpacity(0.5),
                    fontSize: 8,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAutoConfigButton() {
    return GestureDetector(
      onTap: _provider.hasArchetype ? () => _provider.autoConfigure() : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _provider.hasArchetype
              ? const Color(0xFF7E57C2).withOpacity(0.15)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: _provider.hasArchetype
                ? const Color(0xFF7E57C2).withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _provider.autoConfigured ? Icons.check : Icons.auto_fix_high,
              size: 10,
              color: _provider.autoConfigured
                  ? const Color(0xFF66BB6A)
                  : const Color(0xFF7E57C2),
            ),
            const SizedBox(width: 4),
            Text(
              _provider.autoConfigured ? 'Auto-Configured' : 'Auto-Configure',
              style: TextStyle(
                color: _provider.hasArchetype
                    ? const Color(0xFF7E57C2)
                    : Colors.white.withOpacity(0.3),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlGroup(SamControlGroup group) {
    final controls = _provider.controlsByGroup(group);
    if (controls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.displayName,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8, fontWeight: FontWeight.w600),
        ),
        for (final ctrl in controls)
          _buildControlSlider(ctrl),
      ],
    );
  }

  Widget _buildControlSlider(SamControlInfo ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              ctrl.name,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: _groupColor(ctrl.group),
                inactiveTrackColor: Colors.white.withOpacity(0.08),
                thumbColor: _groupColor(ctrl.group),
              ),
              child: Slider(
                value: ctrl.value.clamp(0.0, 1.0),
                onChanged: (v) => _provider.setControlValue(ctrl.index, v),
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              (ctrl.value * 100).toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _groupColor(ctrl.group).withOpacity(0.7),
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugRow(SamControlInfo ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '${ctrl.group.displayName}.${ctrl.name}',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          Text(
            ctrl.value.toStringAsFixed(4),
            style: TextStyle(color: _groupColor(ctrl.group), fontSize: 8, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8)),
          ),
          Text(value, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 8, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        _statusChip('AIL', _provider.ailPassed,
            _provider.ailPassed ? '${_provider.ailScore.toStringAsFixed(0)}' : 'N/A'),
        const SizedBox(width: 4),
        _statusChip('CERT', _provider.certified, _provider.certified ? 'YES' : 'NO'),
        const SizedBox(width: 4),
        _statusChip('GDD', _provider.gddImported, _provider.gddImported ? 'YES' : 'N/A'),
      ],
    );
  }

  Widget _statusChip(String label, bool active, String value) {
    final color = active ? const Color(0xFF66BB6A) : Colors.white.withOpacity(0.3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w500),
      ),
    );
  }

  Color _groupColor(SamControlGroup group) {
    switch (group) {
      case SamControlGroup.energy: return const Color(0xFFFF7043);
      case SamControlGroup.clarity: return const Color(0xFF42A5F5);
      case SamControlGroup.stability: return const Color(0xFF66BB6A);
    }
  }
}
