/**
 * Demo Panels - Extracted from LayoutDemo
 *
 * Contains demo/showcase panels that are not critical to main functionality:
 * - DragDropLabPanel - Drag & drop showcase
 * - LoadingStatesPanel - Loading components showcase
 */

import { useState } from 'react';
import {
  useDraggable,
  useDropTarget,
  useDragState,
  type DragItem,
  type DropTarget,
} from '../core/dragDropSystem';
import {
  Spinner,
  Skeleton,
  SkeletonCard,
  ProgressBar,
  LoadingButton,
  EmptyState,
} from './LoadingStates';

// ============ Drag & Drop Lab Panel ============

interface DragDropLabPanelProps {
  onLogEvent: (category: string, message: string) => void;
}

const DEMO_SOUNDS = [
  { id: 'coin_land', name: 'Coin Land', icon: '🪙', type: 'sfx' },
  { id: 'win_jingle', name: 'Win Jingle', icon: '🎵', type: 'music' },
  { id: 'reel_spin', name: 'Reel Spin', icon: '🎰', type: 'sfx' },
  { id: 'bonus_trigger', name: 'Bonus Trigger', icon: '⭐', type: 'sfx' },
];

// Individual draggable sound item
function DraggableSoundItem({ sound, onDragStart }: {
  sound: typeof DEMO_SOUNDS[0];
  onDragStart: (name: string) => void;
}) {
  const item: DragItem = {
    type: 'audio-asset',
    id: sound.id,
    label: sound.name,
    data: { icon: sound.icon, soundType: sound.type },
  };

  const { isDragging, dragHandlers } = useDraggable(item);

  return (
    <div
      {...dragHandlers}
      onMouseDown={(e) => {
        onDragStart(sound.name);
        dragHandlers.onMouseDown(e);
      }}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        padding: '8px 12px',
        marginBottom: 4,
        background: isDragging ? 'var(--rf-accent-primary)' : 'var(--rf-bg-2)',
        border: '1px solid var(--rf-border)',
        borderRadius: 6,
        cursor: 'grab',
        fontSize: 12,
        opacity: isDragging ? 0.5 : 1,
        color: isDragging ? 'white' : 'inherit',
      }}
    >
      <span>{sound.icon}</span>
      <span>{sound.name}</span>
      <span style={{ marginLeft: 'auto', fontSize: 10, color: isDragging ? 'rgba(255,255,255,0.7)' : 'var(--rf-text-secondary)' }}>
        {sound.type}
      </span>
    </div>
  );
}

export function DragDropLabPanel({ onLogEvent }: DragDropLabPanelProps) {
  const dragState = useDragState();
  const [droppedItems, setDroppedItems] = useState<Array<{ id: string; label: string; data?: Record<string, unknown> }>>([]);

  // Drop target configuration
  const dropTarget: DropTarget = {
    id: 'event-slot',
    type: 'slot',
    accepts: ['audio-asset'],
  };

  const { ref, isOver } = useDropTarget(dropTarget, (item: DragItem) => {
    setDroppedItems((prev) => [...prev, { id: item.id, label: item.label, data: item.data }]);
    onLogEvent('DROP', `Dropped: ${item.label}`);
  });

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, padding: 16, height: '100%' }}>
      {/* Source */}
      <div style={{
        padding: 12,
        background: 'var(--rf-bg-1)',
        borderRadius: 8,
        border: '1px solid var(--rf-border)',
      }}>
        <h4 style={{ margin: '0 0 12px', fontSize: 12, color: 'var(--rf-text-secondary)' }}>
          Sound Library (Drag from here)
        </h4>
        {DEMO_SOUNDS.map((item) => (
          <DraggableSoundItem
            key={item.id}
            sound={item}
            onDragStart={(name) => onLogEvent('DRAG', `Started: ${name}`)}
          />
        ))}
      </div>

      {/* Target */}
      <div
        ref={ref}
        style={{
          padding: 12,
          background: isOver ? 'rgba(14, 165, 233, 0.1)' : 'var(--rf-bg-1)',
          borderRadius: 8,
          border: isOver
            ? '2px dashed var(--rf-accent-primary)'
            : '1px solid var(--rf-border)',
          transition: 'all 0.15s ease',
        }}
      >
        <h4 style={{ margin: '0 0 12px', fontSize: 12, color: 'var(--rf-text-secondary)' }}>
          Event Slot (Drop here) — {droppedItems.length} items
        </h4>
        {droppedItems.length === 0 ? (
          <div style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            height: 100,
            border: '2px dashed var(--rf-border)',
            borderRadius: 8,
            color: 'var(--rf-text-secondary)',
            fontSize: 13,
          }}>
            Drop sounds here
          </div>
        ) : (
          droppedItems.map((item, idx) => (
            <div
              key={idx}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                padding: '8px 12px',
                marginBottom: 4,
                background: 'rgba(34, 197, 94, 0.15)',
                border: '1px solid rgba(34, 197, 94, 0.3)',
                borderRadius: 6,
                fontSize: 12,
                color: '#22c55e',
              }}
            >
              ✓ {item.label}
            </div>
          ))
        )}
      </div>

      {/* Status */}
      {dragState.isDragging && (
        <div style={{
          gridColumn: 'span 2',
          padding: 8,
          background: 'var(--rf-accent-primary)',
          borderRadius: 6,
          color: 'white',
          fontSize: 12,
          textAlign: 'center',
        }}>
          Dragging: {dragState.currentItem?.label || 'Unknown'}
        </div>
      )}
    </div>
  );
}

// ============ Loading States Demo Panel ============

export function LoadingStatesPanel() {
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState(0);

  const simulateLoading = () => {
    setLoading(true);
    setProgress(0);
    const interval = setInterval(() => {
      setProgress((p) => {
        if (p >= 100) {
          clearInterval(interval);
          setLoading(false);
          return 0;
        }
        return p + 10;
      });
    }, 200);
  };

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, padding: 16, height: '100%', overflow: 'auto' }}>
      {/* Spinners */}
      <div style={{ padding: 12, background: 'var(--rf-bg-1)', borderRadius: 8, border: '1px solid var(--rf-border)' }}>
        <h4 style={{ margin: '0 0 12px', fontSize: 12, color: 'var(--rf-text-secondary)' }}>Spinners</h4>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <Spinner size="sm" />
          <Spinner size="md" />
          <Spinner size="lg" />
        </div>
      </div>

      {/* Skeletons */}
      <div style={{ padding: 12, background: 'var(--rf-bg-1)', borderRadius: 8, border: '1px solid var(--rf-border)' }}>
        <h4 style={{ margin: '0 0 12px', fontSize: 12, color: 'var(--rf-text-secondary)' }}>Skeletons</h4>
        <Skeleton width="80%" height={14} />
        <div style={{ marginTop: 8 }}>
          <Skeleton width="60%" height={10} />
        </div>
        <div style={{ marginTop: 12 }}>
          <SkeletonCard />
        </div>
      </div>

      {/* Progress */}
      <div style={{ padding: 12, background: 'var(--rf-bg-1)', borderRadius: 8, border: '1px solid var(--rf-border)' }}>
        <h4 style={{ margin: '0 0 12px', fontSize: 12, color: 'var(--rf-text-secondary)' }}>Progress</h4>
        <ProgressBar value={progress} showLabel />
        <div style={{ marginTop: 12 }}>
          <LoadingButton
            loading={loading}
            loadingText="Processing..."
            onClick={simulateLoading}
          >
            Start Process
          </LoadingButton>
        </div>
      </div>

      {/* Empty State */}
      <div style={{ gridColumn: 'span 3', padding: 12, background: 'var(--rf-bg-1)', borderRadius: 8, border: '1px solid var(--rf-border)' }}>
        <EmptyState
          icon="📭"
          title="No Audio Files"
          description="Import audio files to get started with your project"
          action={{ label: 'Import Audio', onClick: () => { /* noop */ } }}
        />
      </div>
    </div>
  );
}
