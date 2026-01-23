//! Buffer and Memory Benchmarks
//!
//! Benchmarks for memory operations: copying, allocation, ring buffers.

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use rf_bench::{generate_audio_buffer, BUFFER_SIZES};

/// Benchmark buffer copying
fn bench_buffer_copy(c: &mut Criterion) {
    let mut group = c.benchmark_group("buffer_copy");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Bytes((size * 8) as u64)); // f64 = 8 bytes

        let input = generate_audio_buffer(size, 42);
        let mut output = vec![0.0; size];

        group.bench_with_input(BenchmarkId::new("clone", size), &size, |b, _| {
            b.iter(|| black_box(input.clone()))
        });

        group.bench_with_input(BenchmarkId::new("copy_from_slice", size), &size, |b, _| {
            b.iter(|| {
                output.copy_from_slice(&input);
                black_box(&output)
            })
        });

        group.bench_with_input(BenchmarkId::new("ptr_copy", size), &size, |b, _| {
            b.iter(|| {
                unsafe {
                    std::ptr::copy_nonoverlapping(input.as_ptr(), output.as_mut_ptr(), size);
                }
                black_box(&output)
            })
        });
    }

    group.finish();
}

/// Benchmark buffer allocation
fn bench_buffer_alloc(c: &mut Criterion) {
    let mut group = c.benchmark_group("buffer_alloc");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Bytes((size * 8) as u64));

        group.bench_with_input(BenchmarkId::new("vec_zeros", size), &size, |b, _| {
            b.iter(|| black_box(vec![0.0f64; size]))
        });

        group.bench_with_input(
            BenchmarkId::new("vec_with_capacity", size),
            &size,
            |b, _| {
                b.iter(|| {
                    let mut v: Vec<f64> = Vec::with_capacity(size);
                    unsafe { v.set_len(size) };
                    black_box(v)
                })
            },
        );

        group.bench_with_input(BenchmarkId::new("box_slice", size), &size, |b, _| {
            b.iter(|| black_box(vec![0.0f64; size].into_boxed_slice()))
        });
    }

    group.finish();
}

/// Simple ring buffer for benchmarking
struct RingBuffer {
    data: Vec<f64>,
    write_pos: usize,
    read_pos: usize,
    capacity: usize,
}

impl RingBuffer {
    fn new(capacity: usize) -> Self {
        Self {
            data: vec![0.0; capacity],
            write_pos: 0,
            read_pos: 0,
            capacity,
        }
    }

    #[inline]
    fn push(&mut self, value: f64) {
        self.data[self.write_pos] = value;
        self.write_pos = (self.write_pos + 1) % self.capacity;
    }

    #[inline]
    fn pop(&mut self) -> f64 {
        let value = self.data[self.read_pos];
        self.read_pos = (self.read_pos + 1) % self.capacity;
        value
    }

    fn push_slice(&mut self, values: &[f64]) {
        for &v in values {
            self.push(v);
        }
    }

    fn pop_slice(&mut self, output: &mut [f64]) {
        for o in output.iter_mut() {
            *o = self.pop();
        }
    }
}

/// Benchmark ring buffer operations
fn bench_ring_buffer(c: &mut Criterion) {
    let mut group = c.benchmark_group("ring_buffer");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);
        let mut output = vec![0.0; size];

        // Ring buffer with 2x capacity for headroom
        let mut ring = RingBuffer::new(size * 2);

        group.bench_with_input(BenchmarkId::new("push_pop_single", size), &size, |b, _| {
            b.iter(|| {
                for &sample in &input {
                    ring.push(black_box(sample));
                }
                for o in output.iter_mut() {
                    *o = ring.pop();
                }
                black_box(&output)
            })
        });

        group.bench_with_input(BenchmarkId::new("push_pop_slice", size), &size, |b, _| {
            b.iter(|| {
                ring.push_slice(black_box(&input));
                ring.pop_slice(&mut output);
                black_box(&output)
            })
        });
    }

    group.finish();
}

/// Benchmark buffer zeroing
fn bench_buffer_zero(c: &mut Criterion) {
    let mut group = c.benchmark_group("buffer_zero");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Bytes((size * 8) as u64));

        let mut buffer = vec![1.0f64; size];

        group.bench_with_input(BenchmarkId::new("fill_zero", size), &size, |b, _| {
            b.iter(|| {
                buffer.fill(0.0);
                black_box(&buffer)
            })
        });

        group.bench_with_input(BenchmarkId::new("iter_zero", size), &size, |b, _| {
            b.iter(|| {
                for sample in buffer.iter_mut() {
                    *sample = 0.0;
                }
                black_box(&buffer)
            })
        });

        group.bench_with_input(BenchmarkId::new("write_bytes", size), &size, |b, _| {
            b.iter(|| {
                unsafe {
                    std::ptr::write_bytes(buffer.as_mut_ptr(), 0, size);
                }
                black_box(&buffer)
            })
        });
    }

    group.finish();
}

/// Benchmark in-place vs out-of-place processing
fn bench_inplace_vs_outofplace(c: &mut Criterion) {
    let mut group = c.benchmark_group("inplace_vs_outofplace");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);
        let mut output = vec![0.0; size];

        // Simple gain operation
        let gain = 0.8;

        group.bench_with_input(BenchmarkId::new("inplace", size), &size, |b, _| {
            b.iter(|| {
                let mut buffer = input.clone();
                for sample in buffer.iter_mut() {
                    *sample *= gain;
                }
                black_box(buffer)
            })
        });

        group.bench_with_input(BenchmarkId::new("outofplace", size), &size, |b, _| {
            b.iter(|| {
                for (i, &sample) in input.iter().enumerate() {
                    output[i] = sample * gain;
                }
                black_box(&output)
            })
        });
    }

    group.finish();
}

/// Benchmark buffer splitting for parallel processing
fn bench_buffer_split(c: &mut Criterion) {
    let mut group = c.benchmark_group("buffer_split");

    for &size in &[1024usize, 2048, 4096] {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);

        // Split into 4 chunks (simulate 4-core parallel processing)
        let chunk_size = size / 4;

        group.bench_with_input(BenchmarkId::new("sequential", size), &size, |b, _| {
            b.iter(|| {
                let mut buffer = input.clone();
                for sample in buffer.iter_mut() {
                    *sample *= 0.8;
                }
                black_box(buffer)
            })
        });

        group.bench_with_input(BenchmarkId::new("chunked", size), &size, |b, _| {
            b.iter(|| {
                let mut buffer = input.clone();
                for chunk in buffer.chunks_mut(chunk_size) {
                    for sample in chunk.iter_mut() {
                        *sample *= 0.8;
                    }
                }
                black_box(buffer)
            })
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_buffer_copy,
    bench_buffer_alloc,
    bench_ring_buffer,
    bench_buffer_zero,
    bench_inplace_vs_outofplace,
    bench_buffer_split,
);

criterion_main!(benches);
