/**
 * EventList - Optimized events list with memoization
 */

import { memo, useMemo } from 'react';
import type { GameEvent, PlayCommand } from '../core/types';
import { EventListItem } from './EventListItem';

interface EventListProps {
  events: GameEvent[];
  selectedEventId: string | null;
  playingEvents: Set<string>;
  searchQuery: string;
  eventTab: 'all' | 'used';
  onSelectEvent: (eventId: string) => void;
  onPlayEvent: (event: GameEvent) => void;
  onStopEvent: (event: GameEvent) => void;
  onDragStart: (eventId: string) => void;
  onDragEnd: () => void;
  onDrop: (targetEventId: string) => void;
}

function EventListComponent({
  events,
  selectedEventId,
  playingEvents,
  searchQuery,
  eventTab,
  onSelectEvent,
  onPlayEvent,
  onStopEvent,
  onDragStart,
  onDragEnd,
  onDrop,
}: EventListProps) {
  // Memoize filtered events to prevent re-calculation on every render
  const filteredEvents = useMemo(() => {
    let filtered = events;

    // Filter by tab
    if (eventTab === 'used') {
      const usedSounds = new Set(
        events.flatMap((e) =>
          e.commands.filter((c) => c.type === 'Play').map((c) => (c as PlayCommand).soundId)
        )
      );
      filtered = filtered.filter((e) =>
        e.commands.some((c) => c.type === 'Play' && usedSounds.has((c as PlayCommand).soundId))
      );
    }

    // Filter by search query
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(
        (e) =>
          e.id.toLowerCase().includes(query) ||
          e.commands.some((c) => 'soundId' in c && (c as PlayCommand).soundId?.toLowerCase().includes(query))
      );
    }

    return filtered;
  }, [events, eventTab, searchQuery]);

  // Memoize event items to prevent re-renders
  const eventItems = useMemo(
    () =>
      filteredEvents.map((event) => (
        <EventListItem
          key={event.id}
          event={event}
          isSelected={selectedEventId === event.id}
          isPlaying={playingEvents.has(event.id)}
          onSelect={onSelectEvent}
          onPlay={onPlayEvent}
          onStop={onStopEvent}
          onDragStart={onDragStart}
          onDragEnd={onDragEnd}
          onDrop={onDrop}
          onDragOver={(e) => e.preventDefault()}
        />
      )),
    [filteredEvents, selectedEventId, playingEvents, onSelectEvent, onPlayEvent, onStopEvent, onDragStart, onDragEnd, onDrop]
  );

  if (filteredEvents.length === 0) {
    return (
      <div className="empty-state">
        {searchQuery ? `No events found for "${searchQuery}"` : 'No events yet'}
      </div>
    );
  }

  return <div className="events-list">{eventItems}</div>;
}

// Memoize component to prevent unnecessary re-renders
export const EventList = memo(EventListComponent);

EventList.displayName = 'EventList';
