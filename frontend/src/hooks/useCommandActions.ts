/**
 * useCommandActions Hook
 *
 * Manages command CRUD operations (Add, Delete, Duplicate).
 * Extracted from EventsPage to reduce component complexity.
 */

import { useCallback } from 'react';
import type { ReelForgeProject, Command, PlayCommand, GameEvent } from '../core/types';

/** Generate unique command ID */
let commandIdCounter = 0;
export function generateCommandId(): string {
  return `cmd_${Date.now()}_${++commandIdCounter}`;
}

export interface UseCommandActionsOptions {
  project: ReelForgeProject | null;
  selectedEventId: string | null;
  selectedEvent: GameEvent | undefined;
  selectedCommandIndex: number | null;
  setProject: (project: ReelForgeProject) => void;
  setSelectedCommandIndex: (index: number | null) => void;
  saveToHistory: (project: ReelForgeProject) => void;
}

export interface UseCommandActionsReturn {
  handleAddCommand: () => void;
  handleDeleteCommand: (commandIndex: number) => void;
  handleDuplicateCommand: (commandIndex: number) => void;
  selectedCommand: Command | null;
}

export function useCommandActions({
  project,
  selectedEventId,
  selectedEvent,
  selectedCommandIndex,
  setProject,
  setSelectedCommandIndex,
  saveToHistory,
}: UseCommandActionsOptions): UseCommandActionsReturn {
  const selectedCommand = selectedEvent && selectedCommandIndex !== null
    ? selectedEvent.commands[selectedCommandIndex]
    : null;

  const handleAddCommand = useCallback(() => {
    if (!project || !selectedEventId) return;

    const newCommand: PlayCommand = {
      id: generateCommandId(),
      type: "Play",
      soundId: project.spriteItems[0]?.soundId || "",
      volume: 1,
      loop: false,
    };

    const updatedProject = {
      ...project,
      events: project.events.map((evt) =>
        evt.id === selectedEventId
          ? { ...evt, commands: [...evt.commands, newCommand] }
          : evt
      ),
    };
    setProject(updatedProject);
    saveToHistory(updatedProject);

    setSelectedCommandIndex(selectedEvent ? selectedEvent.commands.length : 0);
  }, [project, selectedEventId, selectedEvent, setProject, saveToHistory, setSelectedCommandIndex]);

  const handleDeleteCommand = useCallback((commandIndex: number) => {
    if (!project || !selectedEventId) return;

    const updatedProject = {
      ...project,
      events: project.events.map((evt) =>
        evt.id === selectedEventId
          ? { ...evt, commands: evt.commands.filter((_, idx) => idx !== commandIndex) }
          : evt
      ),
    };
    setProject(updatedProject);
    saveToHistory(updatedProject);

    if (selectedCommandIndex === commandIndex) {
      setSelectedCommandIndex(null);
    }
  }, [project, selectedEventId, selectedCommandIndex, setProject, saveToHistory, setSelectedCommandIndex]);

  const handleDuplicateCommand = useCallback((commandIndex: number) => {
    if (!project || !selectedEventId) return;

    const commandToDuplicate = selectedEvent?.commands[commandIndex];
    if (!commandToDuplicate) return;

    const newCommand: Command = {
      ...commandToDuplicate,
      id: generateCommandId(),
    };

    const updatedProject = {
      ...project,
      events: project.events.map((evt) =>
        evt.id === selectedEventId
          ? {
              ...evt,
              commands: [
                ...evt.commands.slice(0, commandIndex + 1),
                newCommand,
                ...evt.commands.slice(commandIndex + 1)
              ]
            }
          : evt
      ),
    };
    setProject(updatedProject);
    saveToHistory(updatedProject);
    setSelectedCommandIndex(commandIndex + 1);
  }, [project, selectedEventId, selectedEvent, setProject, saveToHistory, setSelectedCommandIndex]);

  return {
    handleAddCommand,
    handleDeleteCommand,
    handleDuplicateCommand,
    selectedCommand,
  };
}
