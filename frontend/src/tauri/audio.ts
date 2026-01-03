/**
 * Tauri Audio Engine API
 *
 * Provides TypeScript bindings for Rust audio engine commands.
 */

import { invoke } from '@tauri-apps/api/core';

// ============ Types ============

export interface AudioStatus {
  running: boolean;
  sample_rate: number;
  buffer_size: number;
}

export interface ChannelMeters {
  peak_l: number;
  peak_r: number;
  rms_l: number;
  rms_r: number;
  gain_reduction: number;
}

export interface MasterMeters {
  peak_l: number;
  peak_r: number;
  gain_reduction: number;
  lufs_short: number;
  lufs_integrated: number;
  true_peak: number;
}

export interface AllMeters {
  channels: ChannelMeters[];
  master: MasterMeters;
}

export interface TransportStatus {
  is_playing: boolean;
  is_recording: boolean;
  is_looping: boolean;
  position_samples: number;
  position_seconds: number;
  tempo: number;
}

// ============ Channel IDs ============

export const ChannelId = {
  UI: 0,
  REELS: 1,
  FX: 2,
  VO: 3,
  MUSIC: 4,
  AMBIENT: 5,
} as const;

export type ChannelId = typeof ChannelId[keyof typeof ChannelId];

export const CHANNEL_NAMES = ['UI', 'REELS', 'FX', 'VO', 'MUSIC', 'AMBIENT'] as const;

// ============ Audio Engine Commands ============

/**
 * Initialize the audio engine with given settings
 */
export async function initAudioEngine(
  sampleRate?: number,
  bufferSize?: number
): Promise<AudioStatus> {
  return invoke<AudioStatus>('init_audio_engine', {
    sampleRate,
    bufferSize,
  });
}

/**
 * Start audio playback
 */
export async function startAudio(): Promise<void> {
  return invoke('start_audio');
}

/**
 * Stop audio playback
 */
export async function stopAudio(): Promise<void> {
  return invoke('stop_audio');
}

/**
 * Get current audio status
 */
export async function getAudioStatus(): Promise<AudioStatus> {
  return invoke<AudioStatus>('get_audio_status');
}

// ============ Mixer Commands ============

/**
 * Set channel volume in dB
 */
export async function setChannelVolume(channel: ChannelId, db: number): Promise<void> {
  return invoke('set_channel_volume', { channel, db });
}

/**
 * Set channel pan (-1.0 = left, 0.0 = center, 1.0 = right)
 */
export async function setChannelPan(channel: ChannelId, pan: number): Promise<void> {
  return invoke('set_channel_pan', { channel, pan });
}

/**
 * Set channel mute state
 */
export async function setChannelMute(channel: ChannelId, mute: boolean): Promise<void> {
  return invoke('set_channel_mute', { channel, mute });
}

/**
 * Set channel solo state
 */
export async function setChannelSolo(channel: ChannelId, solo: boolean): Promise<void> {
  return invoke('set_channel_solo', { channel, solo });
}

/**
 * Set master volume in dB
 */
export async function setMasterVolume(db: number): Promise<void> {
  return invoke('set_master_volume', { db });
}

/**
 * Set master limiter settings
 */
export async function setMasterLimiter(enabled: boolean, ceiling: number): Promise<void> {
  return invoke('set_master_limiter', { enabled, ceiling });
}

// ============ Metering ============

/**
 * Get current meter values
 */
export async function getMeters(): Promise<AllMeters | null> {
  return invoke<AllMeters | null>('get_meters');
}

// ============ Transport ============

/**
 * Start playback
 */
export async function play(): Promise<void> {
  return invoke('play');
}

/**
 * Stop playback
 */
export async function stop(): Promise<void> {
  return invoke('stop');
}

/**
 * Set playback position in samples
 */
export async function setPosition(samples: number): Promise<void> {
  return invoke('set_position', { samples });
}

/**
 * Get current transport status
 */
export async function getPosition(): Promise<TransportStatus> {
  return invoke<TransportStatus>('get_position');
}

// ============ Utility ============

/**
 * Convert linear level (0-1) to dB
 */
export function linearToDb(level: number): number {
  if (level <= 0) return -60;
  return 20 * Math.log10(level);
}

/**
 * Convert dB to linear level (0-1)
 */
export function dbToLinear(db: number): number {
  return Math.pow(10, db / 20);
}

/**
 * Convert dB to meter display level (0-1)
 * Maps -60dB to 0.0, 0dB to 1.0
 */
export function dbToMeter(db: number): number {
  const normalized = (db + 60) / 60;
  return Math.max(0, Math.min(1, normalized));
}

/**
 * Check if running inside Tauri
 */
export function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI__' in window;
}
