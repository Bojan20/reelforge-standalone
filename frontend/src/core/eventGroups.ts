/**
 * Event Groups System
 *
 * Manages mutually exclusive sound events - when one plays,
 * others in the group stop.
 *
 * Use cases:
 * - Music states (only one music track at a time)
 * - UI feedback (only one click sound at a time)
 * - Win celebrations (one win sound per tier)
 * - Voice-overs (one VO at a time)
 */

import type { BusId } from './types';

// ============ TYPES ============

export type GroupBehavior = 'stop-others' | 'block-new' | 'queue';

export interface EventGroupMember {
  /** Sound/event ID */
  id: string;
  /** Priority within group (for queue behavior) */
  priority?: number;
  /** Fade out time when stopped by group (ms) */
  fadeOutMs?: number;
  /** Delay before this member can play again after being stopped (ms) */
  cooldownMs?: number;
}

export interface EventGroup {
  /** Unique group ID */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Group behavior when member tries to play */
  behavior: GroupBehavior;
  /** Members of this group */
  members: EventGroupMember[];
  /** Default fade out time for members (ms) */
  defaultFadeOutMs?: number;
  /** Max queue size (for queue behavior) */
  maxQueueSize?: number;
  /** Cross-group exclusions (other groups that are also stopped) */
  excludes?: string[];
}

export interface ActiveGroupMember {
  memberId: string;
  groupId: string;
  voiceId: string;
  startTime: number;
  cooldownEndTime?: number;
}

export interface QueuedGroupMember {
  memberId: string;
  groupId: string;
  bus: BusId;
  volume: number;
  queueTime: number;
  priority: number;
}

// ============ EVENT GROUP MANAGER ============

export class EventGroupManager {
  private groups: Map<string, EventGroup> = new Map();
  private memberToGroup: Map<string, string> = new Map();
  private activeMembers: Map<string, ActiveGroupMember> = new Map();
  private queues: Map<string, QueuedGroupMember[]> = new Map();
  private cooldowns: Map<string, number> = new Map(); // memberId → cooldownEndTime
  private stopCallback: (voiceId: string, fadeMs: number) => void;
  private playCallback: (assetId: string, bus: BusId, volume: number) => string | null;

  constructor(
    stopCallback: (voiceId: string, fadeMs: number) => void,
    playCallback: (assetId: string, bus: BusId, volume: number) => string | null,
    groups?: EventGroup[]
  ) {
    this.stopCallback = stopCallback;
    this.playCallback = playCallback;

    // Register default groups
    DEFAULT_EVENT_GROUPS.forEach(g => this.registerGroup(g));

    // Register custom groups
    if (groups) {
      groups.forEach(g => this.registerGroup(g));
    }
  }

  /**
   * Register an event group
   */
  registerGroup(group: EventGroup): void {
    this.groups.set(group.id, group);
    this.queues.set(group.id, []);

    // Map members to group
    group.members.forEach(member => {
      this.memberToGroup.set(member.id, group.id);
    });
  }

  /**
   * Unregister an event group
   */
  unregisterGroup(groupId: string): void {
    const group = this.groups.get(groupId);
    if (group) {
      group.members.forEach(member => {
        this.memberToGroup.delete(member.id);
      });
    }
    this.groups.delete(groupId);
    this.queues.delete(groupId);
  }

  /**
   * Request to play a group member
   */
  requestPlay(
    memberId: string,
    bus: BusId,
    volume: number
  ): { allowed: boolean; voiceId: string | null; stopped: string[] } {
    const groupId = this.memberToGroup.get(memberId);

    // Not in any group - allow
    if (!groupId) {
      const voiceId = this.playCallback(memberId, bus, volume);
      return { allowed: true, voiceId, stopped: [] };
    }

    const group = this.groups.get(groupId);
    if (!group) {
      const voiceId = this.playCallback(memberId, bus, volume);
      return { allowed: true, voiceId, stopped: [] };
    }

    const member = group.members.find(m => m.id === memberId);
    if (!member) {
      const voiceId = this.playCallback(memberId, bus, volume);
      return { allowed: true, voiceId, stopped: [] };
    }

    // Check cooldown
    const cooldownEnd = this.cooldowns.get(memberId);
    if (cooldownEnd && performance.now() < cooldownEnd) {
      return { allowed: false, voiceId: null, stopped: [] };
    }

    const stopped: string[] = [];

    switch (group.behavior) {
      case 'stop-others': {
        // Stop all other active members in this group
        this.activeMembers.forEach((active, _activeId) => {
          if (active.groupId === groupId && active.memberId !== memberId) {
            const activeMember = group.members.find(m => m.id === active.memberId);
            const fadeMs = activeMember?.fadeOutMs ?? group.defaultFadeOutMs ?? 100;
            this.stopCallback(active.voiceId, fadeMs);
            stopped.push(active.memberId);

            // Set cooldown if configured
            if (activeMember?.cooldownMs) {
              this.cooldowns.set(active.memberId, performance.now() + activeMember.cooldownMs);
            }
          }
        });

        // Stop excluded groups
        if (group.excludes) {
          group.excludes.forEach(excludedGroupId => {
            this.stopGroup(excludedGroupId);
          });
        }

        // Remove stopped members
        stopped.forEach(id => {
          this.activeMembers.forEach((active, key) => {
            if (active.memberId === id) {
              this.activeMembers.delete(key);
            }
          });
        });

        // Play the new member
        const voiceId = this.playCallback(memberId, bus, volume);
        if (voiceId) {
          const activeKey = `${groupId}_${memberId}_${Date.now()}`;
          this.activeMembers.set(activeKey, {
            memberId,
            groupId,
            voiceId,
            startTime: performance.now(),
          });
        }

        return { allowed: true, voiceId, stopped };
      }

      case 'block-new': {
        // Check if any member is active
        let hasActive = false;
        this.activeMembers.forEach(active => {
          if (active.groupId === groupId) {
            hasActive = true;
          }
        });

        if (hasActive) {
          return { allowed: false, voiceId: null, stopped: [] };
        }

        // No active member - allow
        const voiceId = this.playCallback(memberId, bus, volume);
        if (voiceId) {
          const activeKey = `${groupId}_${memberId}_${Date.now()}`;
          this.activeMembers.set(activeKey, {
            memberId,
            groupId,
            voiceId,
            startTime: performance.now(),
          });
        }

        return { allowed: true, voiceId, stopped: [] };
      }

      case 'queue': {
        // Check if any member is active
        let hasActive = false;
        this.activeMembers.forEach(active => {
          if (active.groupId === groupId) {
            hasActive = true;
          }
        });

        if (hasActive) {
          // Add to queue
          const queue = this.queues.get(groupId) ?? [];
          const maxQueue = group.maxQueueSize ?? 5;

          if (queue.length >= maxQueue) {
            return { allowed: false, voiceId: null, stopped: [] };
          }

          queue.push({
            memberId,
            groupId,
            bus,
            volume,
            queueTime: performance.now(),
            priority: member.priority ?? 0,
          });

          // Sort by priority (higher first)
          queue.sort((a, b) => b.priority - a.priority);
          this.queues.set(groupId, queue);

          return { allowed: false, voiceId: null, stopped: [] };
        }

        // No active member - play directly
        const voiceId = this.playCallback(memberId, bus, volume);
        if (voiceId) {
          const activeKey = `${groupId}_${memberId}_${Date.now()}`;
          this.activeMembers.set(activeKey, {
            memberId,
            groupId,
            voiceId,
            startTime: performance.now(),
          });
        }

        return { allowed: true, voiceId, stopped: [] };
      }

      default:
        return { allowed: false, voiceId: null, stopped: [] };
    }
  }

  /**
   * Mark a member as ended (for queue processing)
   */
  memberEnded(memberId: string, voiceId?: string): void {
    // Find and remove active member
    this.activeMembers.forEach((active, key) => {
      if (active.memberId === memberId || (voiceId && active.voiceId === voiceId)) {
        this.activeMembers.delete(key);

        // Check queue for this group
        this.processQueue(active.groupId);
      }
    });
  }

  /**
   * Process queue for a group
   */
  private processQueue(groupId: string): void {
    const queue = this.queues.get(groupId);
    if (!queue || queue.length === 0) return;

    // Get next queued item
    const next = queue.shift();
    if (!next) return;

    // Play it
    const voiceId = this.playCallback(next.memberId, next.bus, next.volume);
    if (voiceId) {
      const activeKey = `${groupId}_${next.memberId}_${Date.now()}`;
      this.activeMembers.set(activeKey, {
        memberId: next.memberId,
        groupId,
        voiceId,
        startTime: performance.now(),
      });
    }
  }

  /**
   * Stop all members of a group
   */
  stopGroup(groupId: string, fadeMs?: number): void {
    const group = this.groups.get(groupId);
    const defaultFade = fadeMs ?? group?.defaultFadeOutMs ?? 100;

    this.activeMembers.forEach((active, key) => {
      if (active.groupId === groupId) {
        const member = group?.members.find(m => m.id === active.memberId);
        const memberFade = member?.fadeOutMs ?? defaultFade;
        this.stopCallback(active.voiceId, memberFade);
        this.activeMembers.delete(key);
      }
    });

    // Clear queue
    this.queues.set(groupId, []);
  }

  /**
   * Stop all groups
   */
  stopAll(fadeMs?: number): void {
    this.groups.forEach((_, groupId) => {
      this.stopGroup(groupId, fadeMs);
    });
  }

  /**
   * Check if a group has active members
   */
  isGroupActive(groupId: string): boolean {
    let hasActive = false;
    this.activeMembers.forEach(active => {
      if (active.groupId === groupId) {
        hasActive = true;
      }
    });
    return hasActive;
  }

  /**
   * Get active member for a group
   */
  getActiveMember(groupId: string): string | null {
    let activeMember: string | null = null;
    this.activeMembers.forEach(active => {
      if (active.groupId === groupId) {
        activeMember = active.memberId;
      }
    });
    return activeMember;
  }

  /**
   * Get queue for a group
   */
  getQueue(groupId: string): QueuedGroupMember[] {
    return this.queues.get(groupId) ?? [];
  }

  /**
   * Add member to existing group
   */
  addMemberToGroup(groupId: string, member: EventGroupMember): boolean {
    const group = this.groups.get(groupId);
    if (!group) return false;

    // Check if already exists
    if (group.members.some(m => m.id === member.id)) {
      return false;
    }

    group.members.push(member);
    this.memberToGroup.set(member.id, groupId);
    return true;
  }

  /**
   * Remove member from group
   */
  removeMemberFromGroup(memberId: string): boolean {
    const groupId = this.memberToGroup.get(memberId);
    if (!groupId) return false;

    const group = this.groups.get(groupId);
    if (!group) return false;

    group.members = group.members.filter(m => m.id !== memberId);
    this.memberToGroup.delete(memberId);
    return true;
  }

  /**
   * Get all groups
   */
  getGroups(): EventGroup[] {
    return Array.from(this.groups.values());
  }

  /**
   * Get group for a member
   */
  getGroupForMember(memberId: string): EventGroup | null {
    const groupId = this.memberToGroup.get(memberId);
    if (!groupId) return null;
    return this.groups.get(groupId) ?? null;
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopAll(0);
    this.groups.clear();
    this.memberToGroup.clear();
    this.activeMembers.clear();
    this.queues.clear();
    this.cooldowns.clear();
  }
}

// ============ DEFAULT GROUPS ============

export const DEFAULT_EVENT_GROUPS: EventGroup[] = [
  {
    id: 'music_state',
    name: 'Music State',
    description: 'Only one music state at a time',
    behavior: 'stop-others',
    defaultFadeOutMs: 500,
    members: [
      { id: 'music_base', fadeOutMs: 1000 },
      { id: 'music_freespins', fadeOutMs: 500 },
      { id: 'music_bigwin', fadeOutMs: 300 },
      { id: 'music_bonus', fadeOutMs: 500 },
      { id: 'music_anticipation', fadeOutMs: 200 },
    ],
  },
  {
    id: 'win_celebration',
    name: 'Win Celebration',
    description: 'Only one win celebration at a time',
    behavior: 'stop-others',
    defaultFadeOutMs: 100,
    members: [
      { id: 'win_small', priority: 1 },
      { id: 'win_medium', priority: 2 },
      { id: 'win_big', priority: 3 },
      { id: 'win_mega', priority: 4 },
      { id: 'win_epic', priority: 5 },
    ],
  },
  {
    id: 'voice_over',
    name: 'Voice Over',
    description: 'Only one voice-over at a time, with queue',
    behavior: 'queue',
    defaultFadeOutMs: 100,
    maxQueueSize: 3,
    members: [
      { id: 'vo_freespins', priority: 3 },
      { id: 'vo_bigwin', priority: 2 },
      { id: 'vo_feature', priority: 2 },
      { id: 'vo_bonus', priority: 1 },
    ],
  },
  {
    id: 'button_click',
    name: 'Button Click',
    description: 'Only one button click at a time',
    behavior: 'stop-others',
    defaultFadeOutMs: 0,
    members: [
      { id: 'click_spin' },
      { id: 'click_bet' },
      { id: 'click_menu' },
      { id: 'click_info' },
      { id: 'click_generic' },
    ],
  },
  {
    id: 'anticipation',
    name: 'Anticipation',
    description: 'One anticipation sound at a time',
    behavior: 'stop-others',
    defaultFadeOutMs: 50,
    excludes: ['win_celebration'], // Stop when win starts
    members: [
      { id: 'anticipation_low' },
      { id: 'anticipation_medium' },
      { id: 'anticipation_high' },
      { id: 'anticipation_climax' },
    ],
  },
  {
    id: 'reel_spin',
    name: 'Reel Spin',
    description: 'Block new spin sounds while spinning',
    behavior: 'block-new',
    members: [
      { id: 'spin_loop' },
      { id: 'spin_turbo' },
    ],
  },
];
