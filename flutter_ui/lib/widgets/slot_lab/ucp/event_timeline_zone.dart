import 'package:flutter/material.dart';

/// UCP-1: Event Timeline Zone
///
/// Displays hook events, canonical events, and segment boundaries
/// in a horizontal timeline strip.
class EventTimelineZone extends StatelessWidget {
  const EventTimelineZone({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 4),
          _buildTimeline(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.timeline, size: 12, color: Color(0xFF42A5F5)),
        const SizedBox(width: 4),
        Text(
          'Event Timeline',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        _legend('Hook', const Color(0xFFFF7043)),
        const SizedBox(width: 6),
        _legend('Event', const Color(0xFF42A5F5)),
        const SizedBox(width: 6),
        _legend('Segment', const Color(0xFF66BB6A)),
      ],
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 7)),
      ],
    );
  }

  Widget _buildTimeline() {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Text(
          'Events will appear during playback',
          style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8),
        ),
      ),
    );
  }
}
