//! Main audio processor that combines graph and buses

use rf_core::{Sample, SampleRate};
use rtrb::{Consumer, Producer, RingBuffer};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::EngineConfig;
use crate::bus::{BusId, BusManager};
use crate::graph::AudioGraph;

/// Parameter change from UI to audio thread
#[derive(Debug, Clone)]
pub enum EngineCommand {
    SetBusVolume(BusId, f64),
    SetBusPan(BusId, f64),
    SetBusMute(BusId, bool),
    SetBusSolo(BusId, bool),
    SetMasterVolume(f64),
}

/// Main audio processor
pub struct AudioProcessor {
    graph: AudioGraph,
    buses: BusManager,
    config: EngineConfig,
    command_rx: Consumer<EngineCommand>,
    running: Arc<AtomicBool>,
}

impl AudioProcessor {
    pub fn new(config: EngineConfig) -> (Self, Producer<EngineCommand>) {
        let (command_tx, command_rx) = RingBuffer::new(1024);

        let mut processor = Self {
            graph: AudioGraph::new(config.block_size),
            buses: BusManager::new(config.block_size),
            config: config.clone(),
            command_rx,
            running: Arc::new(AtomicBool::new(true)),
        };

        processor.graph.set_sample_rate(config.sample_rate.as_f64());

        (processor, command_tx)
    }

    /// Process commands from UI thread (call at start of audio callback)
    fn process_commands(&mut self) {
        while let Ok(cmd) = self.command_rx.pop() {
            match cmd {
                EngineCommand::SetBusVolume(id, db) => {
                    self.buses.get_mut(id).volume = rf_core::Decibels(db);
                }
                EngineCommand::SetBusPan(id, pan) => {
                    self.buses.get_mut(id).pan = pan;
                }
                EngineCommand::SetBusMute(id, mute) => {
                    self.buses.get_mut(id).mute = mute;
                }
                EngineCommand::SetBusSolo(id, solo) => {
                    self.buses.get_mut(id).solo = solo;
                }
                EngineCommand::SetMasterVolume(db) => {
                    self.buses.master_mut().volume = rf_core::Decibels(db);
                }
            }
        }
    }

    /// Main processing function
    pub fn process(&mut self, _input: &[Sample], output: &mut [Sample]) {
        // Process any pending commands
        self.process_commands();

        // Clear buses
        self.buses.clear_all();

        // Process audio graph
        self.graph.process();

        // Process buses
        self.buses.process_all();

        // Copy master output to output buffer
        let master = self.buses.master();
        let left = master.left();
        let right = master.right();

        // Interleave stereo output
        for (i, chunk) in output.chunks_mut(2).enumerate() {
            if i < left.len() {
                chunk[0] = left[i];
                chunk[1] = right[i];
            }
        }
    }

    /// Get audio graph for modification
    pub fn graph_mut(&mut self) -> &mut AudioGraph {
        &mut self.graph
    }

    /// Get bus manager for modification
    pub fn buses_mut(&mut self) -> &mut BusManager {
        &mut self.buses
    }

    /// Check if processor is running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire)
    }

    /// Stop the processor
    pub fn stop(&self) {
        self.running.store(false, Ordering::Release);
    }

    /// Get current config
    pub fn config(&self) -> &EngineConfig {
        &self.config
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: SampleRate) {
        self.config.sample_rate = sample_rate;
        self.graph.set_sample_rate(sample_rate.as_f64());
    }

    /// Set block size
    pub fn set_block_size(&mut self, block_size: usize) {
        self.config.block_size = block_size;
        self.graph.set_block_size(block_size);
        self.buses.set_block_size(block_size);
    }

    /// Reset all processing state
    pub fn reset(&mut self) {
        self.graph.reset();
    }
}

/// Handle for controlling the processor from UI thread
pub struct ProcessorHandle {
    command_tx: Producer<EngineCommand>,
}

impl ProcessorHandle {
    pub fn new(command_tx: Producer<EngineCommand>) -> Self {
        Self { command_tx }
    }

    pub fn set_bus_volume(&mut self, bus: BusId, db: f64) {
        let _ = self.command_tx.push(EngineCommand::SetBusVolume(bus, db));
    }

    pub fn set_bus_pan(&mut self, bus: BusId, pan: f64) {
        let _ = self.command_tx.push(EngineCommand::SetBusPan(bus, pan));
    }

    pub fn set_bus_mute(&mut self, bus: BusId, mute: bool) {
        let _ = self.command_tx.push(EngineCommand::SetBusMute(bus, mute));
    }

    pub fn set_bus_solo(&mut self, bus: BusId, solo: bool) {
        let _ = self.command_tx.push(EngineCommand::SetBusSolo(bus, solo));
    }

    pub fn set_master_volume(&mut self, db: f64) {
        let _ = self.command_tx.push(EngineCommand::SetMasterVolume(db));
    }
}
