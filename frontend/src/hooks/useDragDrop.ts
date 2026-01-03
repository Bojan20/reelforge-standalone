/**
 * useDragDrop Hook
 *
 * Manages drag and drop for events and commands.
 * Extracted from EventsPage to reduce component complexity.
 */

import { useState, useCallback } from 'react';
import type { ReelForgeProject } from '../core/types';

export interface UseDragDropOptions {
  project: ReelForgeProject | null;
  selectedEventId: string | null;
  selectedCommandIndex: number | null;
  setProject: (project: ReelForgeProject) => void;
  setSelectedCommandIndex: (index: number | null) => void;
  saveToHistory: (project: ReelForgeProject) => void;
  volumeSliderOpen: number | null;
  panSliderOpen: number | string | null;
}

export interface UseDragDropReturn {
  // State
  draggedCommandIndex: number | null;
  draggedEventId: string | null;

  // Command drag handlers
  handleCommandDragStart: (e: React.DragEvent, index: number) => void;
  handleDragOver: (e: React.DragEvent) => void;
  handleDrop: (e: React.DragEvent, dropIndex: number) => void;
  handleDragEnd: () => void;

  // Event drag handlers
  handleEventDragStart: (e: React.DragEvent, eventId: string) => void;
  handleEventDragOver: (e: React.DragEvent) => void;
  handleEventDrop: (e: React.DragEvent, dropEventId: string) => void;
  handleEventDragEnd: () => void;
}

export function useDragDrop({
  project,
  selectedEventId,
  selectedCommandIndex,
  setProject,
  setSelectedCommandIndex,
  saveToHistory,
  volumeSliderOpen,
  panSliderOpen,
}: UseDragDropOptions): UseDragDropReturn {
  const [draggedCommandIndex, setDraggedCommandIndex] = useState<number | null>(null);
  const [draggedEventId, setDraggedEventId] = useState<string | null>(null);

  // Command drag handlers
  const handleCommandDragStart = useCallback((e: React.DragEvent, index: number) => {
    if (volumeSliderOpen !== null || panSliderOpen !== null) {
      e.preventDefault();
      e.stopPropagation();
      return;
    }
    setDraggedCommandIndex(index);
    e.dataTransfer.effectAllowed = "move";
  }, [volumeSliderOpen, panSliderOpen]);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }, []);

  const handleDrop = useCallback((e: React.DragEvent, dropIndex: number) => {
    e.preventDefault();
    if (draggedCommandIndex === null || !project || !selectedEventId) return;
    if (draggedCommandIndex === dropIndex) {
      setDraggedCommandIndex(null);
      return;
    }

    const selectedEvent = project.events.find((evt) => evt.id === selectedEventId);
    if (!selectedEvent) return;

    const commands = [...selectedEvent.commands];
    const [draggedCommand] = commands.splice(draggedCommandIndex, 1);
    commands.splice(dropIndex, 0, draggedCommand);

    const updatedProject = {
      ...project,
      events: project.events.map((evt) =>
        evt.id === selectedEventId ? { ...evt, commands } : evt
      ),
    };

    setProject(updatedProject);
    saveToHistory(updatedProject);
    setDraggedCommandIndex(null);

    // Update selected command index if needed
    if (selectedCommandIndex === draggedCommandIndex) {
      setSelectedCommandIndex(dropIndex);
    } else if (selectedCommandIndex !== null) {
      if (draggedCommandIndex < selectedCommandIndex && dropIndex >= selectedCommandIndex) {
        setSelectedCommandIndex(selectedCommandIndex - 1);
      } else if (draggedCommandIndex > selectedCommandIndex && dropIndex <= selectedCommandIndex) {
        setSelectedCommandIndex(selectedCommandIndex + 1);
      }
    }
  }, [draggedCommandIndex, project, selectedEventId, selectedCommandIndex, setProject, saveToHistory, setSelectedCommandIndex]);

  const handleDragEnd = useCallback(() => {
    setDraggedCommandIndex(null);
  }, []);

  // Event drag handlers
  const handleEventDragStart = useCallback((e: React.DragEvent, eventId: string) => {
    setDraggedEventId(eventId);
    e.dataTransfer.effectAllowed = "move";
  }, []);

  const handleEventDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }, []);

  const handleEventDrop = useCallback((e: React.DragEvent, dropEventId: string) => {
    e.preventDefault();
    if (draggedEventId === null || !project) return;
    if (draggedEventId === dropEventId) {
      setDraggedEventId(null);
      return;
    }

    const events = [...project.events];
    const draggedIndex = events.findIndex(evt => evt.id === draggedEventId);
    const dropIndex = events.findIndex(evt => evt.id === dropEventId);

    if (draggedIndex === -1 || dropIndex === -1) {
      setDraggedEventId(null);
      return;
    }

    const [draggedEvent] = events.splice(draggedIndex, 1);
    events.splice(dropIndex, 0, draggedEvent);

    const updatedProject = {
      ...project,
      events,
    };

    setProject(updatedProject);
    saveToHistory(updatedProject);
    setDraggedEventId(null);
  }, [draggedEventId, project, setProject, saveToHistory]);

  const handleEventDragEnd = useCallback(() => {
    setDraggedEventId(null);
  }, []);

  return {
    // State
    draggedCommandIndex,
    draggedEventId,

    // Command drag handlers
    handleCommandDragStart,
    handleDragOver,
    handleDrop,
    handleDragEnd,

    // Event drag handlers
    handleEventDragStart,
    handleEventDragOver,
    handleEventDrop,
    handleEventDragEnd,
  };
}
