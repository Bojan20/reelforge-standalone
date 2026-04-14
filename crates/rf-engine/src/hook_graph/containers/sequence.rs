//! SequenceContainer — Sequential playback with multiple modes.
//! Modes: forward, reverse, ping-pong, random-no-repeat.

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SequenceMode {
    Forward = 0,
    Reverse = 1,
    PingPong = 2,
    RandomNoRepeat = 3,
}

impl SequenceMode {
    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => Self::Reverse,
            2 => Self::PingPong,
            3 => Self::RandomNoRepeat,
            _ => Self::Forward,
        }
    }
}

pub struct SequenceContainer {
    count: usize,
    mode: SequenceMode,
    current: usize,
    direction: i8,
    seed: u64,
    rng_state: u64,
    last_random: Option<usize>,
}

impl SequenceContainer {
    pub fn new(count: usize, mode: SequenceMode, seed: u64) -> Self {
        Self {
            count,
            mode,
            current: 0,
            direction: 1,
            seed,
            rng_state: seed,
            last_random: None,
        }
    }

    pub fn next(&mut self) -> usize {
        if self.count == 0 { return 0; }

        let result = match self.mode {
            SequenceMode::Forward => {
                let r = self.current;
                self.current = (self.current + 1) % self.count;
                r
            }
            SequenceMode::Reverse => {
                let r = self.current;
                if self.current == 0 {
                    self.current = self.count - 1;
                } else {
                    self.current -= 1;
                }
                r
            }
            SequenceMode::PingPong => {
                let r = self.current;
                let next = self.current as i8 + self.direction;
                if next < 0 || next >= self.count as i8 {
                    self.direction = -self.direction;
                    self.current = (self.current as i8 + self.direction) as usize;
                } else {
                    self.current = next as usize;
                }
                r
            }
            SequenceMode::RandomNoRepeat => {
                let mut candidate = self.next_random() % self.count;
                if self.count > 1 {
                    while Some(candidate) == self.last_random {
                        candidate = self.next_random() % self.count;
                    }
                }
                self.last_random = Some(candidate);
                candidate
            }
        };

        result
    }

    fn next_random(&mut self) -> usize {
        self.rng_state ^= self.rng_state << 13;
        self.rng_state ^= self.rng_state >> 7;
        self.rng_state ^= self.rng_state << 17;
        self.rng_state as usize
    }

    pub fn reset(&mut self) {
        self.current = 0;
        self.direction = 1;
        self.rng_state = self.seed;
        self.last_random = None;
    }
}
