/**
 * useTimeline Hook Tests
 *
 * Integration tests for timeline state management.
 *
 * @module timeline/__tests__/useTimeline.test
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useTimeline } from '../useTimeline';

describe('useTimeline', () => {
  describe('initialization', () => {
    it('should initialize with default state', () => {
      const { result } = renderHook(() => useTimeline());

      expect(result.current.state.playheadPosition).toBe(0);
      expect(result.current.state.isPlaying).toBe(false);
      expect(result.current.state.pixelsPerSecond).toBe(50);
      expect(result.current.state.snapEnabled).toBe(true);
      expect(result.current.tracks).toEqual([]);
    });

    it('should accept custom initial state', () => {
      const { result } = renderHook(() =>
        useTimeline({
          initialState: {
            bpm: 140,
            pixelsPerSecond: 100,
            snapEnabled: false,
          },
        })
      );

      expect(result.current.state.bpm).toBe(140);
      expect(result.current.state.pixelsPerSecond).toBe(100);
      expect(result.current.state.snapEnabled).toBe(false);
    });
  });

  describe('playhead control', () => {
    it('should set playhead position', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setPlayhead(10);
      });

      expect(result.current.state.playheadPosition).toBe(10);
    });

    it('should clamp playhead to non-negative values', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setPlayhead(-5);
      });

      expect(result.current.state.playheadPosition).toBe(0);
    });
  });

  describe('zoom control', () => {
    it('should set zoom level', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setZoom(100);
      });

      expect(result.current.state.pixelsPerSecond).toBe(100);
    });

    it('should clamp zoom to valid range', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setZoom(3); // Below minimum (5)
      });

      expect(result.current.state.pixelsPerSecond).toBe(5);

      act(() => {
        result.current.setZoom(2000); // Above maximum (1000)
      });

      expect(result.current.state.pixelsPerSecond).toBe(1000);
    });
  });

  describe('scroll control', () => {
    it('should scroll view', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.scrollTo(15); // Scroll to center view at 15
      });

      // scrollTo centers the view, so visibleStart should be adjusted
      expect(result.current.state.visibleStart).toBeGreaterThan(0);
    });

    it('should not scroll to negative position', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.scrollTo(-10);
      });

      // visibleStart is clamped to 0 minimum
      expect(result.current.state.visibleStart).toBe(0);
    });
  });

  describe('loop control', () => {
    it('should toggle loop', () => {
      const { result } = renderHook(() => useTimeline());

      expect(result.current.state.loopEnabled).toBe(false);

      act(() => {
        result.current.setLoop(true);
      });

      expect(result.current.state.loopEnabled).toBe(true);
    });

    it('should set loop region', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setLoopRegion(5, 20);
      });

      expect(result.current.state.loopStart).toBe(5);
      expect(result.current.state.loopEnd).toBe(20);
    });

    it('should swap start/end if start > end', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setLoopRegion(20, 5);
      });

      expect(result.current.state.loopStart).toBe(5);
      expect(result.current.state.loopEnd).toBe(20);
    });
  });

  describe('snap control', () => {
    it('should toggle snap', () => {
      const { result } = renderHook(() => useTimeline());

      expect(result.current.state.snapEnabled).toBe(true);

      act(() => {
        result.current.setSnapEnabled(false);
      });

      expect(result.current.state.snapEnabled).toBe(false);
    });

    it('should set grid division', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setGridDivision(0.5);
      });

      expect(result.current.state.gridDivision).toBe(0.5);
    });
  });

  describe('track management', () => {
    it('should add track', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.addTrack({ name: 'Audio 1', type: 'audio' });
      });

      expect(result.current.tracks).toHaveLength(1);
      expect(result.current.tracks[0].name).toBe('Audio 1');
      expect(result.current.tracks[0].type).toBe('audio');
    });

    it('should update track', () => {
      const { result } = renderHook(() => useTimeline());

      let trackId: string;

      act(() => {
        const track = result.current.addTrack({ name: 'Track 1' });
        trackId = track.id;
      });

      act(() => {
        result.current.updateTrack(trackId!, { name: 'Renamed Track', muted: true });
      });

      const track = result.current.tracks.find((t) => t.id === trackId);
      expect(track?.name).toBe('Renamed Track');
      expect(track?.muted).toBe(true);
    });

    it('should delete track', () => {
      const { result } = renderHook(() => useTimeline());

      let trackId: string;

      act(() => {
        const track = result.current.addTrack({ name: 'Track 1' });
        trackId = track.id;
        result.current.addTrack({ name: 'Track 2' });
      });

      expect(result.current.tracks).toHaveLength(2);

      act(() => {
        result.current.removeTrack(trackId!);
      });

      expect(result.current.tracks).toHaveLength(1);
      expect(result.current.tracks[0].name).toBe('Track 2');
    });

    it('should reorder tracks', () => {
      const { result } = renderHook(() => useTimeline());

      let ids: string[] = [];

      act(() => {
        ids.push(result.current.addTrack({ name: 'Track 1' }).id);
        ids.push(result.current.addTrack({ name: 'Track 2' }).id);
        ids.push(result.current.addTrack({ name: 'Track 3' }).id);
      });

      act(() => {
        result.current.reorderTracks([ids[2], ids[0], ids[1]]);
      });

      expect(result.current.tracks[0].name).toBe('Track 3');
      expect(result.current.tracks[1].name).toBe('Track 1');
      expect(result.current.tracks[2].name).toBe('Track 2');
    });
  });

  describe('clip management', () => {
    it('should add clip to track', () => {
      const { result } = renderHook(() => useTimeline());

      let trackId: string;

      act(() => {
        trackId = result.current.addTrack({ name: 'Track 1' }).id;
      });

      act(() => {
        result.current.addClip(trackId, {
          name: 'Clip 1',
          startTime: 0,
          duration: 5,
        });
      });

      const track = result.current.tracks[0];
      expect(track.clips).toHaveLength(1);
      expect(track.clips[0].name).toBe('Clip 1');
      expect(track.clips[0].duration).toBe(5);
    });

    it('should update clip', () => {
      const { result } = renderHook(() => useTimeline());

      let trackId: string;
      let clipId: string;

      act(() => {
        trackId = result.current.addTrack({ name: 'Track 1' }).id;
      });

      act(() => {
        clipId = result.current.addClip(trackId, {
          name: 'Clip 1',
          startTime: 0,
          duration: 5,
        }).id;
      });

      act(() => {
        result.current.updateClip(trackId, clipId!, {
          name: 'Updated Clip',
          startTime: 2,
        });
      });

      const clip = result.current.tracks[0].clips[0];
      expect(clip.name).toBe('Updated Clip');
      expect(clip.startTime).toBe(2);
    });

    it('should delete clip', () => {
      const { result } = renderHook(() => useTimeline());

      let trackId: string;
      let clipId: string;

      act(() => {
        trackId = result.current.addTrack({ name: 'Track 1' }).id;
      });

      act(() => {
        clipId = result.current.addClip(trackId, { name: 'Clip 1', startTime: 0, duration: 5 }).id;
        result.current.addClip(trackId, { name: 'Clip 2', startTime: 10, duration: 5 });
      });

      expect(result.current.tracks[0].clips).toHaveLength(2);

      act(() => {
        result.current.removeClip(trackId, clipId!);
      });

      expect(result.current.tracks[0].clips).toHaveLength(1);
      expect(result.current.tracks[0].clips[0].name).toBe('Clip 2');
    });

    it('should move clip between tracks', () => {
      const { result } = renderHook(() => useTimeline());

      let trackId: string;
      let trackId2: string;
      let clipId: string;

      act(() => {
        trackId = result.current.addTrack({ name: 'Track 1' }).id;
        trackId2 = result.current.addTrack({ name: 'Track 2' }).id;
      });

      act(() => {
        clipId = result.current.addClip(trackId, { name: 'Clip 1', startTime: 0, duration: 5 }).id;
      });

      act(() => {
        result.current.moveClip(trackId, clipId!, 10, trackId2!);
      });

      expect(result.current.tracks[0].clips).toHaveLength(0);
      expect(result.current.tracks[1].clips).toHaveLength(1);
      expect(result.current.tracks[1].clips[0].startTime).toBe(10);
    });
  });

  describe('selection', () => {
    it('should set selection', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setSelection({ type: 'time', start: 5, end: 15 });
      });

      expect(result.current.state.selection).toEqual({
        type: 'time',
        start: 5,
        end: 15,
      });
    });

    it('should clear selection', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.setSelection({ type: 'time', start: 5, end: 15 });
      });

      act(() => {
        result.current.clearSelection();
      });

      expect(result.current.state.selection).toBeNull();
    });
  });

  describe('markers', () => {
    it('should add marker', () => {
      const { result } = renderHook(() => useTimeline());

      act(() => {
        result.current.addMarker({ name: 'Verse 1', position: 16 });
      });

      expect(result.current.markers).toHaveLength(1);
      expect(result.current.markers[0].name).toBe('Verse 1');
      expect(result.current.markers[0].position).toBe(16);
    });

    it('should delete marker', () => {
      const { result } = renderHook(() => useTimeline());

      let markerId: string;

      act(() => {
        markerId = result.current.addMarker({ name: 'Marker 1', position: 0 }).id;
        result.current.addMarker({ name: 'Marker 2', position: 10 });
      });

      act(() => {
        result.current.removeMarker(markerId!);
      });

      expect(result.current.markers).toHaveLength(1);
      expect(result.current.markers[0].name).toBe('Marker 2');
    });
  });

  describe('utility functions', () => {
    it('should convert time to pixels', () => {
      const { result } = renderHook(() =>
        useTimeline({ initialState: { pixelsPerSecond: 100, visibleStart: 0 } })
      );

      // timeToPixels = (time - visibleStart) * pixelsPerSecond
      expect(result.current.timeToPixels(5)).toBe(500);
      expect(result.current.timeToPixels(0.5)).toBe(50);
    });

    it('should convert pixels to time', () => {
      const { result } = renderHook(() =>
        useTimeline({ initialState: { pixelsPerSecond: 100, visibleStart: 0 } })
      );

      // pixelsToTime = pixels / pixelsPerSecond + visibleStart
      expect(result.current.pixelsToTime(500)).toBe(5);
      expect(result.current.pixelsToTime(50)).toBe(0.5);
    });

    it('should snap time to grid', () => {
      const { result } = renderHook(() =>
        useTimeline({ initialState: { gridDivision: 0.25, snapEnabled: true } })
      );

      // With snap enabled, values should be quantized to grid
      const snapped = result.current.snapToGrid(0.13);
      expect(snapped).toBeCloseTo(0.25, 1);
    });

    it('should not snap when disabled', () => {
      const { result } = renderHook(() =>
        useTimeline({ initialState: { gridDivision: 0.25, snapEnabled: false } })
      );

      expect(result.current.snapToGrid(0.13)).toBe(0.13);
      expect(result.current.snapToGrid(0.37)).toBe(0.37);
    });
  });
});
