/**
 * useEventActions Hook
 *
 * Manages event CRUD operations (Add, Rename, Delete).
 * Extracted from EventsPage to reduce component complexity.
 */

import { useCallback } from 'react';
import type { ReelForgeProject, GameEvent } from '../core/types';

export interface UseEventActionsOptions {
  project: ReelForgeProject | null;
  selectedEventId: string | null;
  setProject: (project: ReelForgeProject) => void;
  setSelectedEventId: (id: string | null) => void;
  setSelectedCommandIndex: (index: number | null) => void;
  saveToHistory: (project: ReelForgeProject) => void;
  onStopAudio?: () => void;
}

export interface UseEventActionsReturn {
  handleAddEvent: () => void;
  handleRenameEvent: () => void;
  handleDeleteEvent: () => void;
  selectedEvent: GameEvent | undefined;
}

export function useEventActions({
  project,
  selectedEventId,
  setProject,
  setSelectedEventId,
  setSelectedCommandIndex,
  saveToHistory,
  onStopAudio,
}: UseEventActionsOptions): UseEventActionsReturn {
  const selectedEvent = project?.events.find((e) => e.id === selectedEventId);

  const handleAddEvent = useCallback(() => {
    if (!project) return;

    const newEventName = prompt("Enter new event name:");
    if (!newEventName) return;

    const newEvent: GameEvent = {
      id: newEventName,
      eventName: newEventName,
      description: `Triggered for ${newEventName}`,
      commands: [],
    };

    const updatedProject = {
      ...project,
      events: [...project.events, newEvent],
    };
    setProject(updatedProject);
    saveToHistory(updatedProject);

    setSelectedEventId(newEvent.id);
  }, [project, setProject, saveToHistory, setSelectedEventId]);

  const handleRenameEvent = useCallback(() => {
    if (!project || !selectedEventId) return;

    const newName = prompt("Enter new event name:", selectedEventId);
    if (!newName || newName === selectedEventId) return;

    const updatedProject = {
      ...project,
      events: project.events.map((evt) =>
        evt.id === selectedEventId ? { ...evt, id: newName, eventName: newName } : evt
      ),
    };
    setProject(updatedProject);
    saveToHistory(updatedProject);

    setSelectedEventId(newName);
  }, [project, selectedEventId, setProject, saveToHistory, setSelectedEventId]);

  const handleDeleteEvent = useCallback(() => {
    if (!project || !selectedEventId) return;

    const confirmed = window.confirm(`Are you sure you want to delete event "${selectedEventId}"?`);
    if (!confirmed) return;

    // Stop any playing audio
    onStopAudio?.();

    const newEvents = project.events.filter((evt) => evt.id !== selectedEventId);
    const updatedProject = {
      ...project,
      events: newEvents,
    };
    setProject(updatedProject);
    saveToHistory(updatedProject);

    setSelectedEventId(newEvents.length > 0 ? newEvents[0].id : null);
    setSelectedCommandIndex(null);
  }, [project, selectedEventId, setProject, saveToHistory, setSelectedEventId, setSelectedCommandIndex, onStopAudio]);

  return {
    handleAddEvent,
    handleRenameEvent,
    handleDeleteEvent,
    selectedEvent,
  };
}
