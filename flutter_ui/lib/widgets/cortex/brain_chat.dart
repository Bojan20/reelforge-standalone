// file: flutter_ui/lib/widgets/cortex/brain_chat.dart
/// Brain Chat — Real-time streaming AI interaction widget.
///
/// Shows streaming Claude responses in the CORTEX lower zone tab.
/// Features:
///   - Real-time text streaming (word by word as Claude generates)
///   - Query input with submit
///   - Conversation history within session
///   - Connection status indicator
///   - Model/latency/cost metadata

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../providers/brain_provider.dart';
import '../../services/service_locator.dart';

class BrainChat extends StatefulWidget {
  const BrainChat({super.key});

  @override
  State<BrainChat> createState() => _BrainChatState();
}

class _BrainChatState extends State<BrainChat> {
  late final BrainProvider _brain;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _brain = sl.get<BrainProvider>();
    _brain.addListener(_onBrainChanged);
    // Initial daemon check
    _brain.checkDaemon();
  }

  @override
  void dispose() {
    _brain.removeListener(_onBrainChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onBrainChanged() {
    setState(() {});
    // Auto-scroll to bottom when streaming
    if (_brain.isStreaming || _brain.state == BrainQueryState.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _submitQuery() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _brain.streamQuery(text);
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // ─── Header bar ─────────────────────────────────────────────
          _buildHeader(),
          // ─── Chat area ──────────────────────────────────────────────
          Expanded(child: _buildChatArea()),
          // ─── Input bar ──────────────────────────────────────────────
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final connected = _brain.isDaemonConnected;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        border: Border(bottom: BorderSide(color: Color(0xFF3C3C3C))),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.circle : Icons.circle_outlined,
            size: 8,
            color: connected ? const Color(0xFF4EC9B0) : const Color(0xFF6C6C6C),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'Brain Online' : 'Brain Offline',
            style: TextStyle(
              fontSize: 11,
              color: connected ? const Color(0xFFCCCCCC) : const Color(0xFF6C6C6C),
            ),
          ),
          const Spacer(),
          if (_brain.lastModel.isNotEmpty)
            Text(
              _brain.lastModel,
              style: const TextStyle(fontSize: 10, color: Color(0xFF6C6C6C)),
            ),
          if (_brain.lastLatencyMs > 0) ...[
            const SizedBox(width: 8),
            Text(
              '${_brain.lastLatencyMs}ms',
              style: const TextStyle(fontSize: 10, color: Color(0xFF6C6C6C)),
            ),
          ],
          const SizedBox(width: 8),
          if (_brain.isStreaming)
            InkWell(
              onTap: _brain.cancelQuery,
              child: const Icon(Icons.stop, size: 14, color: Color(0xFFE06C75)),
            ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    final history = _brain.history;
    final hasStreaming = _brain.isStreaming && _brain.streamingText.isNotEmpty;

    if (history.isEmpty && !hasStreaming && _brain.streamingText.isEmpty) {
      return const Center(
        child: Text(
          'Ask the Brain anything...',
          style: TextStyle(fontSize: 12, color: Color(0xFF6C6C6C)),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: history.length + (hasStreaming || _brain.state == BrainQueryState.connecting ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < history.length) {
          return _buildHistoryEntry(history[index]);
        }
        // Active streaming entry
        return _buildStreamingEntry();
      },
    );
  }

  Widget _buildHistoryEntry(BrainConversationEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Query
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF264F78),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.query,
              style: const TextStyle(fontSize: 12, color: Color(0xFFD4D4D4)),
            ),
          ),
          const SizedBox(height: 4),
          // Response
          SelectableText(
            entry.response,
            style: TextStyle(
              fontSize: 12,
              color: entry.isError
                  ? const Color(0xFFE06C75)
                  : const Color(0xFFCCCCCC),
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
          // Metadata
          if (entry.model.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${entry.model} | ${entry.latencyMs}ms | \$${entry.costUsd.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 9, color: Color(0xFF4C4C4C)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStreamingEntry() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Query
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF264F78),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _brain.currentQuery,
              style: const TextStyle(fontSize: 12, color: Color(0xFFD4D4D4)),
            ),
          ),
          const SizedBox(height: 4),
          // Streaming text + cursor
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SelectableText(
                  _brain.streamingText.isEmpty ? '...' : _brain.streamingText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFCCCCCC),
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
              if (_brain.isStreaming)
                const _StreamingCursor(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        border: Border(top: BorderSide(color: Color(0xFF3C3C3C))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  _submitQuery();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                style: const TextStyle(fontSize: 12, color: Color(0xFFD4D4D4)),
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: _brain.isDaemonConnected
                      ? 'Ask the Brain... (Enter to send)'
                      : 'Daemon offline',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6C6C6C),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF264F78)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _brain.isIdle ? _submitQuery : _brain.cancelQuery,
            icon: Icon(
              _brain.isStreaming ? Icons.stop : Icons.send,
              size: 16,
              color: const Color(0xFF4EC9B0),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}

/// Blinking cursor indicator during streaming.
class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) => Container(
        width: 2,
        height: 14,
        margin: const EdgeInsets.only(left: 2, bottom: 2),
        color: Color.lerp(
          const Color(0xFF4EC9B0),
          Colors.transparent,
          _controller.value,
        ),
      ),
    );
  }
}
