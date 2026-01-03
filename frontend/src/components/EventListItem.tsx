/**
 * EventListItem - Optimized event row component with React.memo
 */

import { memo } from 'react';
import type { GameEvent } from '../core/types';

interface EventListItemProps {
  event: GameEvent;
  isSelected: boolean;
  isPlaying: boolean;
  onSelect: (eventId: string) => void;
  onPlay: (event: GameEvent) => void;
  onStop: (event: GameEvent) => void;
  onDragStart: (eventId: string) => void;
  onDragEnd: () => void;
  onDrop: (targetEventId: string) => void;
  onDragOver: (e: React.DragEvent) => void;
  showPlayButton?: boolean;
}

function EventListItemComponent({
  event,
  isSelected,
  isPlaying,
  onSelect,
  onPlay,
  onStop,
  onDragStart,
  onDragEnd,
  onDrop,
  onDragOver,
  showPlayButton = true,
}: EventListItemProps) {
  const commandCounts = event.commands.reduce(
    (acc, cmd) => {
      acc[cmd.type] = (acc[cmd.type] || 0) + 1;
      return acc;
    },
    {} as Record<string, number>
  );

  const commandSummary = Object.entries(commandCounts)
    .map(([type, count]) => `${count} ${type}`)
    .join(', ');

  return (
    <div
      className={`event-item ${isSelected ? 'selected' : ''}`}
      onClick={() => onSelect(event.id)}
      draggable
      onDragStart={() => onDragStart(event.id)}
      onDragEnd={onDragEnd}
      onDrop={(e) => {
        e.preventDefault();
        onDrop(event.id);
      }}
      onDragOver={onDragOver}
    >
      <div className="event-header">
        <span className="event-id">{event.id}</span>
        {showPlayButton && (
          <button
            className="play-btn"
            onClick={(e) => {
              e.stopPropagation();
              if (isPlaying) {
                onStop(event);
              } else {
                onPlay(event);
              }
            }}
            title={isPlaying ? 'Stop' : 'Play'}
          >
            {isPlaying ? '⏹' : '▶'}
          </button>
        )}
      </div>
      <div className="event-summary" title={commandSummary}>
        {commandSummary || 'No commands'}
      </div>
    </div>
  );
}

// Memoize to prevent re-renders when props don't change
export const EventListItem = memo(
  EventListItemComponent,
  (prevProps, nextProps) => {
    // Custom comparison for better performance
    return (
      prevProps.event.id === nextProps.event.id &&
      prevProps.isSelected === nextProps.isSelected &&
      prevProps.isPlaying === nextProps.isPlaying &&
      prevProps.event.commands.length === nextProps.event.commands.length &&
      prevProps.showPlayButton === nextProps.showPlayButton
    );
  }
);

EventListItem.displayName = 'EventListItem';
