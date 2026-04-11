// f64 se čuva kao u64 bitovi — atomici ne podržavaju float
pub struct AtomicF64(AtomicU64);

impl AtomicF64 {
    pub fn store(&self, val: f64) {
        self.0.store(val.to_bits(), Ordering::Relaxed);
    }
    pub fn load(&self) -> f64 {
        f64::from_bits(self.0.load(Ordering::Relaxed))
    }
}