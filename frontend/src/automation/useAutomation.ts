/**
 * ReelForge Automation Hook
 *
 * State management for automation lanes:
 * - Add/remove lanes
 * - Add/update/delete points
 * - Read automation values
 * - Recording mode
 *
 * @module automation/useAutomation
 */

import { useState, useCallback, useMemo } from 'react';
import type { AutomationLaneData, AutomationPoint, CurveType } from './AutomationLane';

// ============ Types ============

export interface UseAutomationOptions {
  /** Initial lanes */
  initialLanes?: AutomationLaneData[];
  /** On lane change callback */
  onLaneChange?: (lane: AutomationLaneData) => void;
}

export interface UseAutomationReturn {
  /** All automation lanes */
  lanes: AutomationLaneData[];
  /** Add a new lane */
  addLane: (lane: Omit<AutomationLaneData, 'id' | 'points'>) => string;
  /** Remove a lane */
  removeLane: (laneId: string) => void;
  /** Update lane properties */
  updateLane: (laneId: string, updates: Partial<AutomationLaneData>) => void;
  /** Add a point to a lane */
  addPoint: (laneId: string, time: number, value: number, curve?: CurveType) => string;
  /** Update a point */
  updatePoint: (laneId: string, pointId: string, updates: Partial<AutomationPoint>) => void;
  /** Delete a point */
  deletePoint: (laneId: string, pointId: string) => void;
  /** Delete multiple points */
  deletePoints: (laneId: string, pointIds: string[]) => void;
  /** Get automation value at time */
  getValueAtTime: (laneId: string, time: number) => number;
  /** Get all lanes for a track */
  getLanesForTrack: (trackId: string) => AutomationLaneData[];
  /** Get lane by parameter ID */
  getLaneByParameter: (parameterId: string) => AutomationLaneData | undefined;
  /** Clear all points in a lane */
  clearLane: (laneId: string) => void;
  /** Set recording arm state */
  setArmed: (laneId: string, armed: boolean) => void;
  /** Set visibility */
  setVisible: (laneId: string, visible: boolean) => void;
}

// ============ Helpers ============

function generateId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

/**
 * Interpolate value between two points based on curve type.
 */
function interpolate(
  p1: AutomationPoint,
  p2: AutomationPoint,
  time: number,
  _minValue: number,
  _maxValue: number
): number {
  const t = (time - p1.time) / (p2.time - p1.time);

  switch (p1.curve) {
    case 'step':
      return p1.value;

    case 'smooth':
      // Smoothstep interpolation
      const smoothT = t * t * (3 - 2 * t);
      return lerp(p1.value, p2.value, smoothT);

    case 'bezier':
      // Cubic bezier with control points
      if (p1.controlOut && p2.controlIn) {
        // Simplified cubic bezier
        const ct1 = p1.value + p1.controlOut.y * (p2.value - p1.value);
        const ct2 = p2.value + p2.controlIn.y * (p2.value - p1.value);
        const mt = 1 - t;
        return (
          mt * mt * mt * p1.value +
          3 * mt * mt * t * ct1 +
          3 * mt * t * t * ct2 +
          t * t * t * p2.value
        );
      }
      return lerp(p1.value, p2.value, t);

    case 'linear':
    default:
      return lerp(p1.value, p2.value, t);
  }
}

// ============ Hook ============

export function useAutomation(options: UseAutomationOptions = {}): UseAutomationReturn {
  const { initialLanes = [], onLaneChange } = options;

  const [lanes, setLanes] = useState<AutomationLaneData[]>(initialLanes);

  // Add a new lane
  const addLane = useCallback(
    (laneData: Omit<AutomationLaneData, 'id' | 'points'>): string => {
      const id = generateId('lane');
      const newLane: AutomationLaneData = {
        ...laneData,
        id,
        points: [],
      };

      setLanes((prev) => [...prev, newLane]);
      return id;
    },
    []
  );

  // Remove a lane
  const removeLane = useCallback((laneId: string) => {
    setLanes((prev) => prev.filter((lane) => lane.id !== laneId));
  }, []);

  // Update lane properties
  const updateLane = useCallback(
    (laneId: string, updates: Partial<AutomationLaneData>) => {
      setLanes((prev) =>
        prev.map((lane) => {
          if (lane.id === laneId) {
            const updated = { ...lane, ...updates };
            onLaneChange?.(updated);
            return updated;
          }
          return lane;
        })
      );
    },
    [onLaneChange]
  );

  // Add a point to a lane
  const addPoint = useCallback(
    (laneId: string, time: number, value: number, curve: CurveType = 'linear'): string => {
      const pointId = generateId('pt');

      setLanes((prev) =>
        prev.map((lane) => {
          if (lane.id !== laneId) return lane;

          const clampedValue = clamp(value, lane.minValue, lane.maxValue);
          const newPoint: AutomationPoint = {
            id: pointId,
            time: Math.max(0, time),
            value: clampedValue,
            curve,
          };

          const newPoints = [...lane.points, newPoint].sort((a, b) => a.time - b.time);
          const updated = { ...lane, points: newPoints };
          onLaneChange?.(updated);
          return updated;
        })
      );

      return pointId;
    },
    [onLaneChange]
  );

  // Update a point
  const updatePoint = useCallback(
    (laneId: string, pointId: string, updates: Partial<AutomationPoint>) => {
      setLanes((prev) =>
        prev.map((lane) => {
          if (lane.id !== laneId) return lane;

          const newPoints = lane.points
            .map((point) => {
              if (point.id !== pointId) return point;

              const updated = { ...point, ...updates };

              // Clamp value
              if (updates.value !== undefined) {
                updated.value = clamp(updates.value, lane.minValue, lane.maxValue);
              }

              // Ensure time is non-negative
              if (updates.time !== undefined) {
                updated.time = Math.max(0, updates.time);
              }

              return updated;
            })
            .sort((a, b) => a.time - b.time);

          const updated = { ...lane, points: newPoints };
          onLaneChange?.(updated);
          return updated;
        })
      );
    },
    [onLaneChange]
  );

  // Delete a point
  const deletePoint = useCallback(
    (laneId: string, pointId: string) => {
      setLanes((prev) =>
        prev.map((lane) => {
          if (lane.id !== laneId) return lane;

          const newPoints = lane.points.filter((p) => p.id !== pointId);
          const updated = { ...lane, points: newPoints };
          onLaneChange?.(updated);
          return updated;
        })
      );
    },
    [onLaneChange]
  );

  // Delete multiple points
  const deletePoints = useCallback(
    (laneId: string, pointIds: string[]) => {
      const idsSet = new Set(pointIds);
      setLanes((prev) =>
        prev.map((lane) => {
          if (lane.id !== laneId) return lane;

          const newPoints = lane.points.filter((p) => !idsSet.has(p.id));
          const updated = { ...lane, points: newPoints };
          onLaneChange?.(updated);
          return updated;
        })
      );
    },
    [onLaneChange]
  );

  // Get automation value at time
  const getValueAtTime = useCallback(
    (laneId: string, time: number): number => {
      const lane = lanes.find((l) => l.id === laneId);
      if (!lane) return 0;

      const points = [...lane.points].sort((a, b) => a.time - b.time);

      // No points - return default
      if (points.length === 0) {
        return lane.defaultValue;
      }

      // Before first point
      if (time <= points[0].time) {
        return points[0].value;
      }

      // After last point
      if (time >= points[points.length - 1].time) {
        return points[points.length - 1].value;
      }

      // Find surrounding points
      for (let i = 0; i < points.length - 1; i++) {
        if (time >= points[i].time && time < points[i + 1].time) {
          return interpolate(
            points[i],
            points[i + 1],
            time,
            lane.minValue,
            lane.maxValue
          );
        }
      }

      return lane.defaultValue;
    },
    [lanes]
  );

  // Get all lanes for a track
  const getLanesForTrack = useCallback(
    (trackId: string): AutomationLaneData[] => {
      return lanes.filter((lane) => lane.trackId === trackId);
    },
    [lanes]
  );

  // Get lane by parameter ID
  const getLaneByParameter = useCallback(
    (parameterId: string): AutomationLaneData | undefined => {
      return lanes.find((lane) => lane.parameterId === parameterId);
    },
    [lanes]
  );

  // Clear all points in a lane
  const clearLane = useCallback(
    (laneId: string) => {
      setLanes((prev) =>
        prev.map((lane) => {
          if (lane.id !== laneId) return lane;

          const updated = { ...lane, points: [] };
          onLaneChange?.(updated);
          return updated;
        })
      );
    },
    [onLaneChange]
  );

  // Set recording arm state
  const setArmed = useCallback((laneId: string, armed: boolean) => {
    setLanes((prev) =>
      prev.map((lane) =>
        lane.id === laneId ? { ...lane, armed } : lane
      )
    );
  }, []);

  // Set visibility
  const setVisible = useCallback((laneId: string, visible: boolean) => {
    setLanes((prev) =>
      prev.map((lane) =>
        lane.id === laneId ? { ...lane, visible } : lane
      )
    );
  }, []);

  return useMemo(
    () => ({
      lanes,
      addLane,
      removeLane,
      updateLane,
      addPoint,
      updatePoint,
      deletePoint,
      deletePoints,
      getValueAtTime,
      getLanesForTrack,
      getLaneByParameter,
      clearLane,
      setArmed,
      setVisible,
    }),
    [
      lanes,
      addLane,
      removeLane,
      updateLane,
      addPoint,
      updatePoint,
      deletePoint,
      deletePoints,
      getValueAtTime,
      getLanesForTrack,
      getLaneByParameter,
      clearLane,
      setArmed,
      setVisible,
    ]
  );
}

export default useAutomation;
