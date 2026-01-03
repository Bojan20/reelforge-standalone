//! Audio bus management

use rf_core::{Decibels, Sample};

/// Bus identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BusId {
    Ui,
    Reels,
    Fx,
    Vo,
    Music,
    Ambient,
    Master,
}

impl BusId {
    pub fn all() -> &'static [BusId] {
        &[
            BusId::Ui,
            BusId::Reels,
            BusId::Fx,
            BusId::Vo,
            BusId::Music,
            BusId::Ambient,
        ]
    }

    pub fn name(&self) -> &'static str {
        match self {
            BusId::Ui => "UI",
            BusId::Reels => "REELS",
            BusId::Fx => "FX",
            BusId::Vo => "VO",
            BusId::Music => "MUSIC",
            BusId::Ambient => "AMBIENT",
            BusId::Master => "MASTER",
        }
    }

    pub fn index(&self) -> usize {
        match self {
            BusId::Ui => 0,
            BusId::Reels => 1,
            BusId::Fx => 2,
            BusId::Vo => 3,
            BusId::Music => 4,
            BusId::Ambient => 5,
            BusId::Master => 6,
        }
    }
}

/// Send configuration
#[derive(Debug, Clone)]
pub struct Send {
    pub destination: BusId,
    pub level: Decibels,
    pub pre_fader: bool,
    pub enabled: bool,
}

impl Send {
    pub fn new(destination: BusId) -> Self {
        Self {
            destination,
            level: Decibels(-6.0),
            pre_fader: false,
            enabled: true,
        }
    }
}

/// Audio bus with volume, pan, and sends
#[derive(Debug, Clone)]
pub struct Bus {
    pub id: BusId,
    pub volume: Decibels,
    pub pan: f64, // -1.0 (L) to 1.0 (R)
    pub mute: bool,
    pub solo: bool,
    pub sends: Vec<Send>,
    // Processing buffers
    left_buffer: Vec<Sample>,
    right_buffer: Vec<Sample>,
}

impl Bus {
    pub fn new(id: BusId, block_size: usize) -> Self {
        Self {
            id,
            volume: Decibels::ZERO,
            pan: 0.0,
            mute: false,
            solo: false,
            sends: Vec::new(),
            left_buffer: vec![0.0; block_size],
            right_buffer: vec![0.0; block_size],
        }
    }

    pub fn clear(&mut self) {
        self.left_buffer.fill(0.0);
        self.right_buffer.fill(0.0);
    }

    pub fn add_stereo(&mut self, left: &[Sample], right: &[Sample]) {
        for (i, (&l, &r)) in left.iter().zip(right.iter()).enumerate() {
            if i < self.left_buffer.len() {
                self.left_buffer[i] += l;
                self.right_buffer[i] += r;
            }
        }
    }

    pub fn process(&mut self) {
        if self.mute {
            self.left_buffer.fill(0.0);
            self.right_buffer.fill(0.0);
            return;
        }

        let gain = self.volume.to_gain();

        // Apply pan law (constant power)
        let pan_angle = (self.pan + 1.0) * 0.25 * std::f64::consts::PI;
        let left_gain = gain * pan_angle.cos();
        let right_gain = gain * pan_angle.sin();

        for sample in &mut self.left_buffer {
            *sample *= left_gain;
        }
        for sample in &mut self.right_buffer {
            *sample *= right_gain;
        }
    }

    pub fn left(&self) -> &[Sample] {
        &self.left_buffer
    }

    pub fn right(&self) -> &[Sample] {
        &self.right_buffer
    }

    pub fn add_send(&mut self, destination: BusId) {
        self.sends.push(Send::new(destination));
    }

    pub fn resize(&mut self, block_size: usize) {
        self.left_buffer.resize(block_size, 0.0);
        self.right_buffer.resize(block_size, 0.0);
    }
}

/// Bus manager for all buses
pub struct BusManager {
    buses: Vec<Bus>,
    master: Bus,
    block_size: usize,
    solo_active: bool,
}

impl BusManager {
    pub fn new(block_size: usize) -> Self {
        let buses = BusId::all()
            .iter()
            .map(|&id| Bus::new(id, block_size))
            .collect();

        Self {
            buses,
            master: Bus::new(BusId::Master, block_size),
            block_size,
            solo_active: false,
        }
    }

    pub fn get(&self, id: BusId) -> &Bus {
        if id == BusId::Master {
            &self.master
        } else {
            &self.buses[id.index()]
        }
    }

    pub fn get_mut(&mut self, id: BusId) -> &mut Bus {
        if id == BusId::Master {
            &mut self.master
        } else {
            &mut self.buses[id.index()]
        }
    }

    pub fn clear_all(&mut self) {
        for bus in &mut self.buses {
            bus.clear();
        }
        self.master.clear();
    }

    pub fn process_all(&mut self) {
        // Update solo state
        self.solo_active = self.buses.iter().any(|b| b.solo);

        // Process each bus
        for bus in &mut self.buses {
            // If solo is active on any bus, mute buses that aren't soloed
            if self.solo_active && !bus.solo {
                bus.left_buffer.fill(0.0);
                bus.right_buffer.fill(0.0);
            } else {
                bus.process();
            }
        }

        // Sum to master
        self.master.clear();
        for bus in &self.buses {
            self.master.add_stereo(bus.left(), bus.right());
        }
        self.master.process();
    }

    pub fn master(&self) -> &Bus {
        &self.master
    }

    pub fn master_mut(&mut self) -> &mut Bus {
        &mut self.master
    }

    pub fn set_block_size(&mut self, block_size: usize) {
        self.block_size = block_size;
        for bus in &mut self.buses {
            bus.resize(block_size);
        }
        self.master.resize(block_size);
    }
}
