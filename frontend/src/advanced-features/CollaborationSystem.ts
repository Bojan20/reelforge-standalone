/**
 * ReelForge Collaboration System
 *
 * Real-time collaboration infrastructure for multi-user editing.
 * Implements CRDT-based conflict resolution and presence awareness.
 *
 * @module advanced-features/CollaborationSystem
 */

// ============ Types ============

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting';
export type UserRole = 'owner' | 'editor' | 'viewer';
export type EditLockType = 'none' | 'soft' | 'hard';

export interface CollaborationConfig {
  serverUrl: string;
  reconnectInterval: number;
  maxReconnectAttempts: number;
  heartbeatInterval: number;
  presenceTimeout: number;
}

export interface User {
  id: string;
  name: string;
  avatar?: string;
  color: string;
  role: UserRole;
}

export interface UserPresence {
  userId: string;
  cursor?: CursorPosition;
  selection?: Selection;
  viewport?: Viewport;
  activeTrack?: string;
  lastActivity: number;
  isIdle: boolean;
}

export interface CursorPosition {
  trackId: string;
  time: number; // in seconds
  y: number; // normalized 0-1
}

export interface Selection {
  trackId: string;
  startTime: number;
  endTime: number;
  type: 'time' | 'region' | 'clip';
  clipIds?: string[];
}

export interface Viewport {
  startTime: number;
  endTime: number;
  zoom: number;
  scrollY: number;
}

export interface EditLock {
  resourceId: string;
  resourceType: 'track' | 'clip' | 'region' | 'parameter';
  userId: string;
  lockType: EditLockType;
  timestamp: number;
  expiresAt: number;
}

export interface CollaborationSession {
  id: string;
  projectId: string;
  createdAt: number;
  users: User[];
  host: string;
}

// ============ CRDT Operations ============

export type OperationType =
  | 'clip:add'
  | 'clip:delete'
  | 'clip:move'
  | 'clip:resize'
  | 'clip:split'
  | 'track:add'
  | 'track:delete'
  | 'track:reorder'
  | 'track:rename'
  | 'track:volume'
  | 'track:pan'
  | 'track:mute'
  | 'track:solo'
  | 'automation:add'
  | 'automation:delete'
  | 'automation:update'
  | 'marker:add'
  | 'marker:delete'
  | 'marker:move'
  | 'project:tempo'
  | 'project:signature';

export interface Operation {
  id: string;
  type: OperationType;
  userId: string;
  timestamp: number;
  lamportClock: number;
  data: Record<string, unknown>;
  dependencies: string[]; // IDs of operations this depends on
}

export interface OperationResult {
  success: boolean;
  operation: Operation;
  conflicts?: Operation[];
  merged?: Operation;
}

// ============ Messages ============

export type MessageType =
  | 'join'
  | 'leave'
  | 'presence'
  | 'operation'
  | 'ack'
  | 'sync'
  | 'lock'
  | 'unlock'
  | 'chat'
  | 'ping'
  | 'pong';

export interface Message {
  type: MessageType;
  sessionId: string;
  userId: string;
  timestamp: number;
  payload: unknown;
}

// ============ Collaboration Client ============

export class CollaborationClient {
  private config: CollaborationConfig;
  private ws: WebSocket | null = null;
  private status: ConnectionStatus = 'disconnected';
  private session: CollaborationSession | null = null;
  private currentUser: User | null = null;

  private lamportClock = 0;
  private pendingOperations = new Map<string, Operation>();
  private appliedOperations = new Map<string, Operation>();
  private operationBuffer: Operation[] = [];

  private locks = new Map<string, EditLock>();
  private presence = new Map<string, UserPresence>();

  private reconnectAttempts = 0;
  private reconnectTimer: number | null = null;
  private heartbeatTimer: number | null = null;
  private presenceTimer: number | null = null;

  private listeners = {
    status: new Set<(status: ConnectionStatus) => void>(),
    presence: new Set<(presence: Map<string, UserPresence>) => void>(),
    operation: new Set<(op: Operation) => void>(),
    lock: new Set<(locks: Map<string, EditLock>) => void>(),
    users: new Set<(users: User[]) => void>(),
    chat: new Set<(message: ChatMessage) => void>()
  };

  constructor(config: Partial<CollaborationConfig> = {}) {
    this.config = {
      serverUrl: 'wss://collab.reelforge.io',
      reconnectInterval: 3000,
      maxReconnectAttempts: 10,
      heartbeatInterval: 30000,
      presenceTimeout: 60000,
      ...config
    };
  }

  // ============ Connection ============

  async connect(sessionId: string, user: User): Promise<boolean> {
    this.currentUser = user;
    this.setStatus('connecting');

    return new Promise((resolve) => {
      try {
        this.ws = new WebSocket(`${this.config.serverUrl}/session/${sessionId}`);

        this.ws.onopen = () => {
          this.setStatus('connected');
          this.reconnectAttempts = 0;
          this.startHeartbeat();
          this.startPresenceUpdates();

          // Send join message
          this.send({
            type: 'join',
            sessionId,
            userId: user.id,
            timestamp: Date.now(),
            payload: { user }
          });

          resolve(true);
        };

        this.ws.onclose = () => {
          this.handleDisconnect();
        };

        this.ws.onerror = () => {
          this.handleDisconnect();
          resolve(false);
        };

        this.ws.onmessage = (event) => {
          this.handleMessage(JSON.parse(event.data));
        };
      } catch {
        this.setStatus('disconnected');
        resolve(false);
      }
    });
  }

  disconnect(): void {
    if (this.ws) {
      // Send leave message
      if (this.session && this.currentUser) {
        this.send({
          type: 'leave',
          sessionId: this.session.id,
          userId: this.currentUser.id,
          timestamp: Date.now(),
          payload: {}
        });
      }

      this.ws.close();
      this.ws = null;
    }

    this.stopHeartbeat();
    this.stopPresenceUpdates();
    this.stopReconnect();
    this.setStatus('disconnected');
  }

  private handleDisconnect(): void {
    this.stopHeartbeat();

    if (this.reconnectAttempts < this.config.maxReconnectAttempts) {
      this.setStatus('reconnecting');
      this.scheduleReconnect();
    } else {
      this.setStatus('disconnected');
    }
  }

  private scheduleReconnect(): void {
    this.stopReconnect();

    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectAttempts++;
      if (this.session && this.currentUser) {
        this.connect(this.session.id, this.currentUser);
      }
    }, this.config.reconnectInterval);
  }

  private stopReconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  // ============ Heartbeat ============

  private startHeartbeat(): void {
    this.heartbeatTimer = window.setInterval(() => {
      if (this.session && this.currentUser) {
        this.send({
          type: 'ping',
          sessionId: this.session.id,
          userId: this.currentUser.id,
          timestamp: Date.now(),
          payload: {}
        });
      }
    }, this.config.heartbeatInterval);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  // ============ Presence ============

  private startPresenceUpdates(): void {
    this.presenceTimer = window.setInterval(() => {
      this.cleanupStalePresence();
    }, 5000);
  }

  private stopPresenceUpdates(): void {
    if (this.presenceTimer) {
      clearInterval(this.presenceTimer);
      this.presenceTimer = null;
    }
  }

  private cleanupStalePresence(): void {
    const now = Date.now();
    let changed = false;

    for (const [userId, presence] of this.presence) {
      if (now - presence.lastActivity > this.config.presenceTimeout) {
        this.presence.delete(userId);
        changed = true;
      } else if (now - presence.lastActivity > 30000 && !presence.isIdle) {
        presence.isIdle = true;
        changed = true;
      }
    }

    if (changed) {
      this.notifyPresenceChange();
    }
  }

  updatePresence(update: Partial<UserPresence>): void {
    if (!this.session || !this.currentUser) return;

    const presence: UserPresence = {
      userId: this.currentUser.id,
      lastActivity: Date.now(),
      isIdle: false,
      ...update
    };

    this.presence.set(this.currentUser.id, presence);

    this.send({
      type: 'presence',
      sessionId: this.session.id,
      userId: this.currentUser.id,
      timestamp: Date.now(),
      payload: presence
    });
  }

  getPresence(): Map<string, UserPresence> {
    return new Map(this.presence);
  }

  // ============ Operations (CRDT) ============

  applyOperation(type: OperationType, data: Record<string, unknown>): Operation {
    this.lamportClock++;

    const operation: Operation = {
      id: this.generateOperationId(),
      type,
      userId: this.currentUser?.id || '',
      timestamp: Date.now(),
      lamportClock: this.lamportClock,
      data,
      dependencies: this.getRecentOperationIds()
    };

    // Apply locally
    this.pendingOperations.set(operation.id, operation);

    // Broadcast
    if (this.session && this.currentUser) {
      this.send({
        type: 'operation',
        sessionId: this.session.id,
        userId: this.currentUser.id,
        timestamp: Date.now(),
        payload: operation
      });
    }

    // Notify local listeners
    for (const listener of this.listeners.operation) {
      listener(operation);
    }

    return operation;
  }

  private handleRemoteOperation(operation: Operation): void {
    // Update lamport clock
    this.lamportClock = Math.max(this.lamportClock, operation.lamportClock) + 1;

    // Check if already applied
    if (this.appliedOperations.has(operation.id)) {
      return;
    }

    // Check dependencies
    const missingDeps = operation.dependencies.filter(
      dep => !this.appliedOperations.has(dep) && !this.pendingOperations.has(dep)
    );

    if (missingDeps.length > 0) {
      // Buffer operation until dependencies arrive
      this.operationBuffer.push(operation);
      return;
    }

    // Check for conflicts
    const conflicts = this.detectConflicts(operation);

    if (conflicts.length > 0) {
      // Resolve conflicts using CRDT rules
      const resolved = this.resolveConflicts(operation, conflicts);
      this.applyResolvedOperation(resolved);
    } else {
      this.applyResolvedOperation(operation);
    }

    // Process buffered operations
    this.processBuffer();
  }

  private detectConflicts(operation: Operation): Operation[] {
    const conflicts: Operation[] = [];

    // Check pending operations for conflicts
    for (const [, pending] of this.pendingOperations) {
      if (this.operationsConflict(operation, pending)) {
        conflicts.push(pending);
      }
    }

    return conflicts;
  }

  private operationsConflict(op1: Operation, op2: Operation): boolean {
    // Same resource conflict detection
    const resource1 = this.getOperationResource(op1);
    const resource2 = this.getOperationResource(op2);

    if (resource1 !== resource2) return false;

    // Time overlap for move/resize operations
    if (op1.type.includes('move') || op1.type.includes('resize')) {
      return true;
    }

    // Delete conflicts with any operation on same resource
    if (op1.type.includes('delete') || op2.type.includes('delete')) {
      return true;
    }

    return false;
  }

  private getOperationResource(op: Operation): string {
    return (op.data.clipId || op.data.trackId || op.data.markerId || 'unknown') as string;
  }

  private resolveConflicts(incoming: Operation, conflicts: Operation[]): Operation {
    // CRDT resolution: Last-Writer-Wins with Lamport clock tiebreaker
    const allOps = [incoming, ...conflicts];

    // Sort by lamport clock, then by timestamp, then by user ID
    allOps.sort((a, b) => {
      if (a.lamportClock !== b.lamportClock) {
        return b.lamportClock - a.lamportClock;
      }
      if (a.timestamp !== b.timestamp) {
        return b.timestamp - a.timestamp;
      }
      return b.userId.localeCompare(a.userId);
    });

    // Winner takes all
    return allOps[0];
  }

  private applyResolvedOperation(operation: Operation): void {
    this.appliedOperations.set(operation.id, operation);
    this.pendingOperations.delete(operation.id);

    // Notify listeners
    for (const listener of this.listeners.operation) {
      listener(operation);
    }
  }

  private processBuffer(): void {
    let processed = true;

    while (processed && this.operationBuffer.length > 0) {
      processed = false;

      for (let i = 0; i < this.operationBuffer.length; i++) {
        const op = this.operationBuffer[i];
        const missingDeps = op.dependencies.filter(
          dep => !this.appliedOperations.has(dep)
        );

        if (missingDeps.length === 0) {
          this.operationBuffer.splice(i, 1);
          this.handleRemoteOperation(op);
          processed = true;
          break;
        }
      }
    }
  }

  private getRecentOperationIds(): string[] {
    // Return IDs of recent operations for dependency tracking
    const recent: string[] = [];
    const ops = Array.from(this.appliedOperations.values());

    // Get last 5 operations
    ops.sort((a, b) => b.lamportClock - a.lamportClock);
    for (let i = 0; i < Math.min(5, ops.length); i++) {
      recent.push(ops[i].id);
    }

    return recent;
  }

  // ============ Edit Locks ============

  async requestLock(
    resourceId: string,
    resourceType: EditLock['resourceType'],
    lockType: EditLockType = 'soft'
  ): Promise<boolean> {
    if (!this.session || !this.currentUser) return false;

    // Check existing lock
    const existing = this.locks.get(resourceId);
    if (existing && existing.userId !== this.currentUser.id) {
      if (existing.lockType === 'hard') {
        return false;
      }
      // Soft lock - notify but allow
    }

    const lock: EditLock = {
      resourceId,
      resourceType,
      userId: this.currentUser.id,
      lockType,
      timestamp: Date.now(),
      expiresAt: Date.now() + 60000 // 1 minute
    };

    this.send({
      type: 'lock',
      sessionId: this.session.id,
      userId: this.currentUser.id,
      timestamp: Date.now(),
      payload: lock
    });

    this.locks.set(resourceId, lock);
    this.notifyLockChange();

    return true;
  }

  releaseLock(resourceId: string): void {
    if (!this.session || !this.currentUser) return;

    const lock = this.locks.get(resourceId);
    if (!lock || lock.userId !== this.currentUser.id) return;

    this.send({
      type: 'unlock',
      sessionId: this.session.id,
      userId: this.currentUser.id,
      timestamp: Date.now(),
      payload: { resourceId }
    });

    this.locks.delete(resourceId);
    this.notifyLockChange();
  }

  getLocks(): Map<string, EditLock> {
    return new Map(this.locks);
  }

  isLocked(resourceId: string): boolean {
    const lock = this.locks.get(resourceId);
    if (!lock) return false;
    if (lock.expiresAt < Date.now()) {
      this.locks.delete(resourceId);
      return false;
    }
    return true;
  }

  isLockedByOther(resourceId: string): boolean {
    const lock = this.locks.get(resourceId);
    if (!lock) return false;
    if (lock.expiresAt < Date.now()) {
      this.locks.delete(resourceId);
      return false;
    }
    return lock.userId !== this.currentUser?.id;
  }

  // ============ Chat ============

  sendChatMessage(text: string): void {
    if (!this.session || !this.currentUser) return;

    const message: ChatMessage = {
      id: this.generateMessageId(),
      userId: this.currentUser.id,
      userName: this.currentUser.name,
      text,
      timestamp: Date.now()
    };

    this.send({
      type: 'chat',
      sessionId: this.session.id,
      userId: this.currentUser.id,
      timestamp: Date.now(),
      payload: message
    });
  }

  // ============ Message Handling ============

  private send(message: Message): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  private handleMessage(message: Message): void {
    switch (message.type) {
      case 'join':
        this.handleUserJoin(message);
        break;

      case 'leave':
        this.handleUserLeave(message);
        break;

      case 'presence':
        this.handlePresenceUpdate(message);
        break;

      case 'operation':
        this.handleRemoteOperation(message.payload as Operation);
        break;

      case 'ack':
        this.handleAck(message);
        break;

      case 'sync':
        this.handleSync(message);
        break;

      case 'lock':
        this.handleLock(message);
        break;

      case 'unlock':
        this.handleUnlock(message);
        break;

      case 'chat':
        this.handleChat(message);
        break;

      case 'pong':
        // Heartbeat acknowledged
        break;
    }
  }

  private handleUserJoin(message: Message): void {
    const user = (message.payload as { user: User }).user;

    if (this.session) {
      const existing = this.session.users.find(u => u.id === user.id);
      if (!existing) {
        this.session.users.push(user);
        this.notifyUsersChange();
      }
    }
  }

  private handleUserLeave(message: Message): void {
    if (this.session) {
      this.session.users = this.session.users.filter(u => u.id !== message.userId);
      this.presence.delete(message.userId);
      this.notifyUsersChange();
      this.notifyPresenceChange();
    }

    // Release any locks held by this user
    for (const [resourceId, lock] of this.locks) {
      if (lock.userId === message.userId) {
        this.locks.delete(resourceId);
      }
    }
    this.notifyLockChange();
  }

  private handlePresenceUpdate(message: Message): void {
    const presence = message.payload as UserPresence;
    this.presence.set(presence.userId, presence);
    this.notifyPresenceChange();
  }

  private handleAck(message: Message): void {
    const opId = (message.payload as { operationId: string }).operationId;
    const pending = this.pendingOperations.get(opId);

    if (pending) {
      this.pendingOperations.delete(opId);
      this.appliedOperations.set(opId, pending);
    }
  }

  private handleSync(message: Message): void {
    const syncData = message.payload as {
      session: CollaborationSession;
      operations: Operation[];
      locks: EditLock[];
      presence: UserPresence[];
    };

    this.session = syncData.session;

    // Apply all operations in order
    for (const op of syncData.operations) {
      if (!this.appliedOperations.has(op.id)) {
        this.appliedOperations.set(op.id, op);
        for (const listener of this.listeners.operation) {
          listener(op);
        }
      }
    }

    // Update locks
    this.locks.clear();
    for (const lock of syncData.locks) {
      this.locks.set(lock.resourceId, lock);
    }

    // Update presence
    this.presence.clear();
    for (const p of syncData.presence) {
      this.presence.set(p.userId, p);
    }

    this.notifyUsersChange();
    this.notifyLockChange();
    this.notifyPresenceChange();
  }

  private handleLock(message: Message): void {
    const lock = message.payload as EditLock;
    this.locks.set(lock.resourceId, lock);
    this.notifyLockChange();
  }

  private handleUnlock(message: Message): void {
    const { resourceId } = message.payload as { resourceId: string };
    this.locks.delete(resourceId);
    this.notifyLockChange();
  }

  private handleChat(message: Message): void {
    const chatMessage = message.payload as ChatMessage;
    for (const listener of this.listeners.chat) {
      listener(chatMessage);
    }
  }

  // ============ Event Listeners ============

  onStatusChange(callback: (status: ConnectionStatus) => void): () => void {
    this.listeners.status.add(callback);
    return () => this.listeners.status.delete(callback);
  }

  onPresenceChange(callback: (presence: Map<string, UserPresence>) => void): () => void {
    this.listeners.presence.add(callback);
    return () => this.listeners.presence.delete(callback);
  }

  onOperation(callback: (op: Operation) => void): () => void {
    this.listeners.operation.add(callback);
    return () => this.listeners.operation.delete(callback);
  }

  onLockChange(callback: (locks: Map<string, EditLock>) => void): () => void {
    this.listeners.lock.add(callback);
    return () => this.listeners.lock.delete(callback);
  }

  onUsersChange(callback: (users: User[]) => void): () => void {
    this.listeners.users.add(callback);
    return () => this.listeners.users.delete(callback);
  }

  onChatMessage(callback: (message: ChatMessage) => void): () => void {
    this.listeners.chat.add(callback);
    return () => this.listeners.chat.delete(callback);
  }

  private setStatus(status: ConnectionStatus): void {
    this.status = status;
    for (const listener of this.listeners.status) {
      listener(status);
    }
  }

  private notifyPresenceChange(): void {
    for (const listener of this.listeners.presence) {
      listener(new Map(this.presence));
    }
  }

  private notifyLockChange(): void {
    for (const listener of this.listeners.lock) {
      listener(new Map(this.locks));
    }
  }

  private notifyUsersChange(): void {
    if (this.session) {
      for (const listener of this.listeners.users) {
        listener([...this.session.users]);
      }
    }
  }

  // ============ Getters ============

  getStatus(): ConnectionStatus {
    return this.status;
  }

  getSession(): CollaborationSession | null {
    return this.session;
  }

  getCurrentUser(): User | null {
    return this.currentUser;
  }

  getUsers(): User[] {
    return this.session?.users || [];
  }

  // ============ Utilities ============

  private generateOperationId(): string {
    return `op_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  private generateMessageId(): string {
    return `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
}

// ============ Chat Types ============

export interface ChatMessage {
  id: string;
  userId: string;
  userName: string;
  text: string;
  timestamp: number;
}

// ============ Session Manager ============

export class SessionManager {
  private apiUrl: string;
  private token: string | null = null;

  constructor(apiUrl: string = 'https://api.reelforge.io/v1') {
    this.apiUrl = apiUrl;
  }

  async authenticate(token: string): Promise<boolean> {
    try {
      const response = await fetch(`${this.apiUrl}/auth/validate`, {
        headers: { Authorization: `Bearer ${token}` }
      });

      if (response.ok) {
        this.token = token;
        return true;
      }
    } catch {
      // Auth failed
    }

    return false;
  }

  async createSession(projectId: string): Promise<CollaborationSession | null> {
    if (!this.token) return null;

    try {
      const response = await fetch(`${this.apiUrl}/sessions`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ projectId })
      });

      if (response.ok) {
        return response.json();
      }
    } catch {
      // Create failed
    }

    return null;
  }

  async joinSession(sessionId: string): Promise<CollaborationSession | null> {
    if (!this.token) return null;

    try {
      const response = await fetch(`${this.apiUrl}/sessions/${sessionId}/join`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.token}` }
      });

      if (response.ok) {
        return response.json();
      }
    } catch {
      // Join failed
    }

    return null;
  }

  async leaveSession(sessionId: string): Promise<boolean> {
    if (!this.token) return false;

    try {
      const response = await fetch(`${this.apiUrl}/sessions/${sessionId}/leave`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.token}` }
      });

      return response.ok;
    } catch {
      return false;
    }
  }

  async getSession(sessionId: string): Promise<CollaborationSession | null> {
    if (!this.token) return null;

    try {
      const response = await fetch(`${this.apiUrl}/sessions/${sessionId}`, {
        headers: { Authorization: `Bearer ${this.token}` }
      });

      if (response.ok) {
        return response.json();
      }
    } catch {
      // Get failed
    }

    return null;
  }

  async inviteUser(sessionId: string, email: string, role: UserRole): Promise<boolean> {
    if (!this.token) return false;

    try {
      const response = await fetch(`${this.apiUrl}/sessions/${sessionId}/invite`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ email, role })
      });

      return response.ok;
    } catch {
      return false;
    }
  }

  generateShareLink(sessionId: string): string {
    return `https://reelforge.io/collab/${sessionId}`;
  }
}

// ============ User Colors ============

const USER_COLORS = [
  '#FF6B6B', // Red
  '#4ECDC4', // Teal
  '#45B7D1', // Blue
  '#96CEB4', // Green
  '#FFEAA7', // Yellow
  '#DDA0DD', // Plum
  '#98D8C8', // Mint
  '#F7DC6F', // Gold
  '#BB8FCE', // Purple
  '#85C1E9'  // Sky
];

export function getUserColor(index: number): string {
  return USER_COLORS[index % USER_COLORS.length];
}

export function generateUserColor(userId: string): string {
  // Hash user ID to get consistent color
  let hash = 0;
  for (let i = 0; i < userId.length; i++) {
    hash = ((hash << 5) - hash) + userId.charCodeAt(i);
    hash |= 0;
  }
  return USER_COLORS[Math.abs(hash) % USER_COLORS.length];
}

// ============ Factory ============

export function createCollaborationClient(
  config?: Partial<CollaborationConfig>
): CollaborationClient {
  return new CollaborationClient(config);
}

export function createSessionManager(apiUrl?: string): SessionManager {
  return new SessionManager(apiUrl);
}
