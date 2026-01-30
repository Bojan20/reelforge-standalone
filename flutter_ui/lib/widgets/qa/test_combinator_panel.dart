// test_combinator_panel.dart
// UI for multi-condition test case generation

import 'package:flutter/material.dart';
import '../../services/test_combinator_service.dart';

class TestCombinatorPanel extends StatefulWidget {
  const TestCombinatorPanel({Key? key}) : super(key: key);

  @override
  State<TestCombinatorPanel> createState() => _TestCombinatorPanelState();
}

class _TestCombinatorPanelState extends State<TestCombinatorPanel> {
  final _service = TestCombinatorService.instance;
  final _selectedDimensions = <TestDimension>{};
  TestSuite? _currentSuite;
  String _suiteName = 'Test Suite';
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    // Default: Win Tier + Feature
    _selectedDimensions.addAll([
      TestDimension.winTier,
      TestDimension.feature,
    ]);
  }

  void _generateSuite() {
    if (_selectedDimensions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one dimension')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    // Generate in next frame to show loading
    Future.delayed(Duration.zero, () {
      final suite = _service.generateCombinations(
        suiteName: _suiteName,
        dimensions: _selectedDimensions,
      );

      setState(() {
        _currentSuite = suite;
        _isGenerating = false;
      });
    });
  }

  void _generateQuickSuite() {
    setState(() => _isGenerating = true);

    Future.delayed(Duration.zero, () {
      final suite = _service.generateQuickSuite(name: 'Quick Suite');
      setState(() {
        _currentSuite = suite;
        _isGenerating = false;
      });
    });
  }

  void _generateComprehensiveSuite() {
    setState(() => _isGenerating = true);

    Future.delayed(Duration.zero, () {
      final suite = _service.generateComprehensiveSuite(name: 'Comprehensive Suite');
      setState(() {
        _currentSuite = suite;
        _isGenerating = false;
      });
    });
  }

  void _exportSuite() {
    if (_currentSuite == null) return;

    final json = _service.exportSuiteToJson(_currentSuite!);
    // TODO: Show save dialog or copy to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Suite exported (${_currentSuite!.totalCases} cases)'),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () {
            // Copy to clipboard
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Configuration
                SizedBox(
                  width: 300,
                  child: _buildConfiguration(),
                ),
                const SizedBox(width: 16),
                // Right: Generated test cases
                Expanded(
                  child: _buildTestCasesList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.science, size: 24, color: Colors.blueAccent),
        const SizedBox(width: 8),
        const Text(
          'TEST COMBINATOR',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (_currentSuite != null) ...[
          Text(
            '${_currentSuite!.totalCases} cases • ${_formatDuration(_currentSuite!.estimatedTotalDuration)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.download, size: 18),
            onPressed: _exportSuite,
            tooltip: 'Export Suite',
          ),
        ],
      ],
    );
  }

  Widget _buildConfiguration() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Suite name
          const Text(
            'SUITE NAME',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Enter suite name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => _suiteName = value,
            controller: TextEditingController(text: _suiteName),
          ),
          const SizedBox(height: 16),

          // Dimension selection
          const Text(
            'DIMENSIONS',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...TestDimension.values.map((dimension) {
            return CheckboxListTile(
              dense: true,
              title: Text(
                _dimensionToString(dimension),
                style: const TextStyle(fontSize: 12),
              ),
              value: _selectedDimensions.contains(dimension),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedDimensions.add(dimension);
                  } else {
                    _selectedDimensions.remove(dimension);
                  }
                });
              },
            );
          }),

          const Divider(height: 24),

          // Generate buttons
          const Text(
            'QUICK PRESETS',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.flash_on, size: 16),
            label: const Text('Quick Suite'),
            onPressed: _isGenerating ? null : _generateQuickSuite,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 36),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.all_inclusive, size: 16),
            label: const Text('Comprehensive'),
            onPressed: _isGenerating ? null : _generateComprehensiveSuite,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 36),
            ),
          ),

          const Divider(height: 24),

          // Custom generate
          ElevatedButton.icon(
            icon: const Icon(Icons.build, size: 16),
            label: const Text('Generate Custom'),
            onPressed: _isGenerating ? null : _generateSuite,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
              backgroundColor: Colors.blueAccent,
            ),
          ),

          if (_isGenerating) ...[
            const SizedBox(height: 12),
            const Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestCasesList() {
    if (_currentSuite == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.science, size: 64, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            Text(
              'No test suite generated',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Select dimensions and click Generate',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: Row(
              children: [
                Text(
                  _currentSuite!.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_currentSuite!.totalCases} CASES',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Test cases list
          Expanded(
            child: ListView.builder(
              itemCount: _currentSuite!.cases.length,
              itemBuilder: (context, index) {
                final testCase = _currentSuite!.cases[index];
                return _buildTestCaseItem(testCase);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCaseItem(TestCase testCase) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${testCase.id}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  testCase.description,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Text(
                _formatDuration(testCase.estimatedDuration),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Conditions
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: testCase.conditions.entries.map((entry) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getDimensionColor(entry.key).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _getDimensionColor(entry.key).withOpacity(0.5),
                  ),
                ),
                child: Text(
                  '${_dimensionToString(entry.key)}: ${_valueToString(entry.value)}',
                  style: TextStyle(
                    fontSize: 9,
                    color: _getDimensionColor(entry.key),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),

          // Expected stages
          Row(
            children: [
              const Icon(Icons.flag, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Expected: ${testCase.expectedStages.take(5).join(", ")}${testCase.expectedStages.length > 5 ? "..." : ""}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dimensionToString(TestDimension dimension) {
    switch (dimension) {
      case TestDimension.winTier:
        return 'Win Tier';
      case TestDimension.feature:
        return 'Feature';
      case TestDimension.cascade:
        return 'Cascade';
      case TestDimension.anticipation:
        return 'Anticipation';
      case TestDimension.betLevel:
        return 'Bet Level';
      case TestDimension.balanceState:
        return 'Balance';
    }
  }

  String _valueToString(dynamic value) {
    return value.toString().split('.').last;
  }

  Color _getDimensionColor(TestDimension dimension) {
    switch (dimension) {
      case TestDimension.winTier:
        return Colors.amber;
      case TestDimension.feature:
        return Colors.purple;
      case TestDimension.cascade:
        return Colors.red;
      case TestDimension.anticipation:
        return Colors.orange;
      case TestDimension.betLevel:
        return Colors.green;
      case TestDimension.balanceState:
        return Colors.blue;
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else if (duration.inMinutes < 60) {
      final seconds = duration.inSeconds % 60;
      return '${duration.inMinutes}m ${seconds}s';
    } else {
      final minutes = duration.inMinutes % 60;
      return '${duration.inHours}h ${minutes}m';
    }
  }
}
