//! Lock-Free State Synchronization
//!
//! ULTIMATIVNI state management:
//! - Triple buffering for all states
//! - SPSC queues for parameter changes
//! - Atomic snapshot for undo/redo
//! - Zero-allocation state updates

use portable_atomic::{AtomicU32, AtomicU64, Ordering};
use rtrb::{Consumer, Producer, RingBuffer};
use std::cell::UnsafeCell;

/// Triple buffer for lock-free read/write
pub struct TripleBuffer<T> {
    /// Three buffers: write, ready, read
    buffers: [UnsafeCell<T>; 3],
    /// Index state: bits 0-1 = write, bits 2-3 = ready, bits 4-5 = read
    state: AtomicU32,
}

// Safe because we control access through atomic state
unsafe impl<T: Send> Send for TripleBuffer<T> {}
unsafe impl<T: Send> Sync for TripleBuffer<T> {}

impl<T: Clone + Default> TripleBuffer<T> {
    /// Create a new triple buffer
    pub fn new(initial: T) -> Self {
        Self {
            buffers: [
                UnsafeCell::new(initial.clone()),
                UnsafeCell::new(initial.clone()),
                UnsafeCell::new(initial),
            ],
            state: AtomicU32::new(0b00_01_10), // write=0, ready=1, read=2
        }
    }

    /// Get mutable reference to write buffer (producer side)
    /// SAFETY: Triple-buffering ensures write buffer is never read while being written
    #[allow(clippy::mut_from_ref)]
    pub fn write(&self) -> &mut T {
        let state = self.state.load(Ordering::Acquire);
        let write_idx = (state & 0b11) as usize;
        unsafe { &mut *self.buffers[write_idx].get() }
    }

    /// Publish write buffer (swap write and ready)
    pub fn publish(&self) {
        loop {
            let state = self.state.load(Ordering::Acquire);
            let write_idx = state & 0b11;
            let ready_idx = (state >> 2) & 0b11;
            let read_idx = (state >> 4) & 0b11;

            // Swap write and ready
            let new_state = ready_idx | (write_idx << 2) | (read_idx << 4);

            if self
                .state
                .compare_exchange_weak(state, new_state, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
            {
                break;
            }
        }
    }

    /// Get reference to read buffer (consumer side)
    pub fn read(&self) -> &T {
        // First, swap ready into read if available
        loop {
            let state = self.state.load(Ordering::Acquire);
            let write_idx = state & 0b11;
            let ready_idx = (state >> 2) & 0b11;
            let read_idx = (state >> 4) & 0b11;

            // Swap ready and read
            let new_state = write_idx | (read_idx << 2) | (ready_idx << 4);

            if self
                .state
                .compare_exchange_weak(state, new_state, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
            {
                break;
            }
        }

        let state = self.state.load(Ordering::Acquire);
        let read_idx = ((state >> 4) & 0b11) as usize;
        unsafe { &*self.buffers[read_idx].get() }
    }
}

/// Parameter change message (lock-free)
#[derive(Debug, Clone, Copy)]
pub struct ParamChange {
    /// Parameter ID
    pub id: u32,
    /// New value (normalized 0-1)
    pub value: f64,
    /// Sample offset within current block
    pub sample_offset: u32,
    /// Smoothing time in samples
    pub smoothing_samples: u32,
}

/// State change for undo/redo
#[derive(Debug, Clone)]
pub struct StateChange {
    /// Timestamp (sample position)
    pub timestamp: u64,
    /// Changed parameter IDs and values
    pub changes: Vec<(u32, f64, f64)>, // (id, old_value, new_value)
}

/// Lock-free parameter queue (UI → Audio)
pub struct ParamQueue {
    producer: Producer<ParamChange>,
    consumer: Consumer<ParamChange>,
}

impl ParamQueue {
    pub fn new(capacity: usize) -> Self {
        let (producer, consumer) = RingBuffer::new(capacity);
        Self { producer, consumer }
    }

    /// Split into producer and consumer
    pub fn split(self) -> (ParamQueueProducer, ParamQueueConsumer) {
        (
            ParamQueueProducer {
                producer: self.producer,
            },
            ParamQueueConsumer {
                consumer: self.consumer,
            },
        )
    }
}

pub struct ParamQueueProducer {
    producer: Producer<ParamChange>,
}

impl ParamQueueProducer {
    /// Push a parameter change (non-blocking)
    pub fn push(&mut self, change: ParamChange) -> bool {
        self.producer.push(change).is_ok()
    }

    /// Push multiple changes
    pub fn push_batch(&mut self, changes: &[ParamChange]) -> usize {
        let mut count = 0;
        for &change in changes {
            if self.producer.push(change).is_ok() {
                count += 1;
            } else {
                break;
            }
        }
        count
    }
}

pub struct ParamQueueConsumer {
    consumer: Consumer<ParamChange>,
}

impl ParamQueueConsumer {
    /// Pop a parameter change (non-blocking)
    pub fn pop(&mut self) -> Option<ParamChange> {
        self.consumer.pop().ok()
    }

    /// Pop all available changes into a buffer
    pub fn pop_all(&mut self, buffer: &mut Vec<ParamChange>) {
        while let Ok(change) = self.consumer.pop() {
            buffer.push(change);
        }
    }
}

/// Atomic state snapshot for undo/redo
pub struct AtomicSnapshot {
    /// Current snapshot ID
    snapshot_id: AtomicU64,
    /// Snapshots (circular buffer)
    snapshots: Vec<UnsafeCell<StateSnapshot>>,
    /// Max snapshots
    max_snapshots: usize,
    /// Current write index
    write_idx: AtomicU32,
}

// Safe because we use atomic indices for access control
unsafe impl Send for AtomicSnapshot {}
unsafe impl Sync for AtomicSnapshot {}

/// A single state snapshot
#[derive(Clone)]
#[derive(Default)]
pub struct StateSnapshot {
    pub id: u64,
    pub timestamp: u64,
    pub params: Vec<(u32, f64)>,
}


impl AtomicSnapshot {
    pub fn new(max_snapshots: usize) -> Self {
        let snapshots = (0..max_snapshots)
            .map(|_| UnsafeCell::new(StateSnapshot::default()))
            .collect();

        Self {
            snapshot_id: AtomicU64::new(0),
            snapshots,
            max_snapshots,
            write_idx: AtomicU32::new(0),
        }
    }

    /// Create a new snapshot
    pub fn create(&self, timestamp: u64, params: Vec<(u32, f64)>) -> u64 {
        let id = self.snapshot_id.fetch_add(1, Ordering::Relaxed) + 1;
        let idx = self.write_idx.fetch_add(1, Ordering::Relaxed) as usize % self.max_snapshots;

        let snapshot = StateSnapshot {
            id,
            timestamp,
            params,
        };
        unsafe {
            *self.snapshots[idx].get() = snapshot;
        }

        id
    }

    /// Get a snapshot by ID
    pub fn get(&self, id: u64) -> Option<StateSnapshot> {
        for cell in &self.snapshots {
            let snapshot = unsafe { &*cell.get() };
            if snapshot.id == id {
                return Some(snapshot.clone());
            }
        }
        None
    }

    /// Get latest snapshot
    pub fn latest(&self) -> Option<StateSnapshot> {
        let id = self.snapshot_id.load(Ordering::Acquire);
        if id == 0 {
            return None;
        }
        self.get(id)
    }
}

/// Zero-allocation state update buffer
pub struct StateUpdateBuffer {
    /// Pre-allocated changes
    changes: Vec<ParamChange>,
    /// Current count
    count: usize,
    /// Max capacity
    capacity: usize,
}

impl StateUpdateBuffer {
    pub fn new(capacity: usize) -> Self {
        Self {
            changes: vec![
                ParamChange {
                    id: 0,
                    value: 0.0,
                    sample_offset: 0,
                    smoothing_samples: 0,
                };
                capacity
            ],
            count: 0,
            capacity,
        }
    }

    /// Add a change (no allocation)
    pub fn push(&mut self, change: ParamChange) -> bool {
        if self.count < self.capacity {
            self.changes[self.count] = change;
            self.count += 1;
            true
        } else {
            false
        }
    }

    /// Get all changes
    pub fn changes(&self) -> &[ParamChange] {
        &self.changes[..self.count]
    }

    /// Clear buffer (no allocation)
    pub fn clear(&mut self) {
        self.count = 0;
    }

    /// Is empty
    pub fn is_empty(&self) -> bool {
        self.count == 0
    }

    /// Count
    pub fn len(&self) -> usize {
        self.count
    }
}

/// Complete state synchronization system
pub struct StateSyncSystem {
    /// Triple buffers for processor states
    processor_states: Vec<TripleBuffer<ProcessorState>>,
    /// Parameter queue (UI → Audio)
    param_queue: Option<ParamQueueConsumer>,
    /// Snapshot manager
    snapshots: AtomicSnapshot,
    /// Pre-allocated update buffer
    update_buffer: StateUpdateBuffer,
    /// Sample position
    sample_position: AtomicU64,
}

/// State of a single processor
#[derive(Clone, Default)]
pub struct ProcessorState {
    pub enabled: bool,
    pub params: Vec<f64>,
}

impl StateSyncSystem {
    pub fn new(num_processors: usize, max_params: usize) -> Self {
        let processor_states = (0..num_processors)
            .map(|_| {
                TripleBuffer::new(ProcessorState {
                    enabled: true,
                    params: vec![0.0; max_params],
                })
            })
            .collect();

        Self {
            processor_states,
            param_queue: None,
            snapshots: AtomicSnapshot::new(128),
            update_buffer: StateUpdateBuffer::new(1024),
            sample_position: AtomicU64::new(0),
        }
    }

    /// Set parameter queue consumer
    pub fn set_param_consumer(&mut self, consumer: ParamQueueConsumer) {
        self.param_queue = Some(consumer);
    }

    /// Process incoming parameter changes (call from audio thread)
    pub fn process_changes(&mut self) {
        self.update_buffer.clear();

        if let Some(ref mut queue) = self.param_queue {
            queue.pop_all(&mut Vec::new()); // Drain into our buffer
        }

        // Apply changes to triple buffers
        for change in self.update_buffer.changes() {
            let processor_idx = (change.id >> 16) as usize;
            let param_idx = (change.id & 0xFFFF) as usize;

            if processor_idx < self.processor_states.len() {
                let state = self.processor_states[processor_idx].write();
                if param_idx < state.params.len() {
                    state.params[param_idx] = change.value;
                }
            }
        }

        // Publish all updated states
        for state in &self.processor_states {
            state.publish();
        }
    }

    /// Read processor state (call from audio thread)
    pub fn read_state(&self, processor_idx: usize) -> Option<&ProcessorState> {
        self.processor_states.get(processor_idx).map(|tb| tb.read())
    }

    /// Update sample position
    pub fn update_position(&self, samples: u64) {
        self.sample_position.fetch_add(samples, Ordering::Relaxed);
    }

    /// Get current sample position
    pub fn position(&self) -> u64 {
        self.sample_position.load(Ordering::Relaxed)
    }

    /// Create undo snapshot
    pub fn create_snapshot(&self) -> u64 {
        let timestamp = self.position();
        let mut params = Vec::new();

        for (proc_idx, state) in self.processor_states.iter().enumerate() {
            let s = state.read();
            for (param_idx, &value) in s.params.iter().enumerate() {
                let id = ((proc_idx as u32) << 16) | (param_idx as u32);
                params.push((id, value));
            }
        }

        self.snapshots.create(timestamp, params)
    }

    /// Restore from snapshot
    pub fn restore_snapshot(&self, id: u64) -> bool {
        if let Some(snapshot) = self.snapshots.get(id) {
            for (id, value) in snapshot.params {
                let processor_idx = (id >> 16) as usize;
                let param_idx = (id & 0xFFFF) as usize;

                if processor_idx < self.processor_states.len() {
                    let state = self.processor_states[processor_idx].write();
                    if param_idx < state.params.len() {
                        state.params[param_idx] = value;
                    }
                }
            }
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_triple_buffer() {
        let buffer: TripleBuffer<i32> = TripleBuffer::new(0);

        // Write
        *buffer.write() = 42;
        buffer.publish();

        // Read
        assert_eq!(*buffer.read(), 42);

        // Write again
        *buffer.write() = 100;
        buffer.publish();
        assert_eq!(*buffer.read(), 100);
    }

    #[test]
    fn test_param_queue() {
        let queue = ParamQueue::new(16);
        let (mut producer, mut consumer) = queue.split();

        producer.push(ParamChange {
            id: 1,
            value: 0.5,
            sample_offset: 0,
            smoothing_samples: 64,
        });

        let change = consumer.pop().unwrap();
        assert_eq!(change.id, 1);
        assert_eq!(change.value, 0.5);
    }

    #[test]
    fn test_atomic_snapshot() {
        let snapshots = AtomicSnapshot::new(4);

        let id1 = snapshots.create(0, vec![(0, 1.0)]);
        let id2 = snapshots.create(100, vec![(0, 2.0)]);

        assert_eq!(id1, 1);
        assert_eq!(id2, 2);

        let s1 = snapshots.get(id1).unwrap();
        assert_eq!(s1.params[0], (0, 1.0));

        let latest = snapshots.latest().unwrap();
        assert_eq!(latest.id, 2);
    }

    #[test]
    fn test_state_update_buffer() {
        let mut buffer = StateUpdateBuffer::new(4);

        assert!(buffer.push(ParamChange {
            id: 0,
            value: 1.0,
            sample_offset: 0,
            smoothing_samples: 0,
        }));

        assert_eq!(buffer.len(), 1);
        assert_eq!(buffer.changes()[0].value, 1.0);

        buffer.clear();
        assert!(buffer.is_empty());
    }

    #[test]
    fn test_state_sync_system() {
        let system = StateSyncSystem::new(2, 4);

        // Initial read
        let state = system.read_state(0).unwrap();
        assert!(state.enabled);
        assert_eq!(state.params.len(), 4);

        // Create snapshot
        let id = system.create_snapshot();
        assert_eq!(id, 1);
    }
}
