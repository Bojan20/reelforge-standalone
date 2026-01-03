/**
 * DSP WASM Benchmark
 *
 * Compare JavaScript vs Rust WASM performance for audio DSP operations.
 * Run in browser console or include in a test page.
 */

import { initDspWasm, applyGain, processBiquad, processCompressor, calcLowpassCoeffs, createBiquadState, createCompressorParams, createCompressorState } from './index';

// ============ JavaScript Reference Implementations ============

function jsApplyGain(samples: Float32Array, gain: number): void {
  for (let i = 0; i < samples.length; i++) {
    samples[i] *= gain;
  }
}

function jsBiquadProcess(
  samples: Float32Array,
  b0: number, b1: number, b2: number,
  a1: number, a2: number,
  state: { z1: number; z2: number }
): void {
  for (let i = 0; i < samples.length; i++) {
    const input = samples[i];
    const output = b0 * input + state.z1;
    state.z1 = b1 * input - a1 * output + state.z2;
    state.z2 = b2 * input - a2 * output;
    samples[i] = output;
  }
}

function jsCompressorProcess(
  samples: Float32Array,
  thresholdDb: number,
  ratio: number,
  attackSec: number,
  releaseSec: number,
  sampleRate: number,
  state: { envelope: number; gainReductionDb: number }
): void {
  const attackCoeff = Math.exp(-1 / (attackSec * sampleRate));
  const releaseCoeff = Math.exp(-1 / (releaseSec * sampleRate));

  for (let i = 0; i < samples.length; i++) {
    const input = samples[i];
    const inputAbs = Math.abs(input);

    // Envelope follower
    const coeff = inputAbs > state.envelope ? attackCoeff : releaseCoeff;
    state.envelope = coeff * state.envelope + (1 - coeff) * inputAbs;

    // Calculate gain reduction
    const inputDb = state.envelope <= 1e-10 ? -200 : 20 * Math.log10(state.envelope);
    let gr = 0;
    if (inputDb > thresholdDb) {
      gr = (inputDb - thresholdDb) * (1 - 1 / ratio);
    }
    state.gainReductionDb = gr;

    // Apply gain reduction
    const gain = Math.pow(10, -gr / 20);
    samples[i] = input * gain;
  }
}

// ============ Benchmark Runner ============

interface BenchmarkResult {
  name: string;
  jsTimeMs: number;
  wasmTimeMs: number;
  speedup: number;
  bufferSize: number;
  iterations: number;
}

async function benchmarkGain(bufferSize: number, iterations: number): Promise<BenchmarkResult> {
  const samples = new Float32Array(bufferSize);
  for (let i = 0; i < bufferSize; i++) {
    samples[i] = Math.random() * 2 - 1;
  }
  const gain = 0.5;

  // JavaScript
  const jsStart = performance.now();
  for (let i = 0; i < iterations; i++) {
    jsApplyGain(samples, gain);
  }
  const jsTime = performance.now() - jsStart;

  // Reset samples
  for (let i = 0; i < bufferSize; i++) {
    samples[i] = Math.random() * 2 - 1;
  }

  // WASM
  const wasmStart = performance.now();
  for (let i = 0; i < iterations; i++) {
    applyGain(samples, gain);
  }
  const wasmTime = performance.now() - wasmStart;

  return {
    name: 'Gain',
    jsTimeMs: jsTime,
    wasmTimeMs: wasmTime,
    speedup: jsTime / wasmTime,
    bufferSize,
    iterations,
  };
}

async function benchmarkBiquad(bufferSize: number, iterations: number): Promise<BenchmarkResult> {
  const samples = new Float32Array(bufferSize);
  for (let i = 0; i < bufferSize; i++) {
    samples[i] = Math.random() * 2 - 1;
  }

  const coeffs = calcLowpassCoeffs(44100, 1000, 0.707);
  const jsState = { z1: 0, z2: 0 };
  const wasmState = createBiquadState();

  // JavaScript
  const jsStart = performance.now();
  for (let i = 0; i < iterations; i++) {
    jsBiquadProcess(samples, coeffs.b0, coeffs.b1, coeffs.b2, coeffs.a1, coeffs.a2, jsState);
  }
  const jsTime = performance.now() - jsStart;

  // Reset samples
  for (let i = 0; i < bufferSize; i++) {
    samples[i] = Math.random() * 2 - 1;
  }

  // WASM
  const wasmStart = performance.now();
  for (let i = 0; i < iterations; i++) {
    processBiquad(samples, coeffs, wasmState);
  }
  const wasmTime = performance.now() - wasmStart;

  return {
    name: 'Biquad Filter',
    jsTimeMs: jsTime,
    wasmTimeMs: wasmTime,
    speedup: jsTime / wasmTime,
    bufferSize,
    iterations,
  };
}

async function benchmarkCompressor(bufferSize: number, iterations: number): Promise<BenchmarkResult> {
  const samples = new Float32Array(bufferSize);
  for (let i = 0; i < bufferSize; i++) {
    samples[i] = Math.random() * 2 - 1;
  }

  const params = createCompressorParams();
  const jsState = { envelope: 0, gainReductionDb: 0 };
  const wasmState = createCompressorState();
  const sampleRate = 44100;

  // JavaScript
  const jsStart = performance.now();
  for (let i = 0; i < iterations; i++) {
    jsCompressorProcess(samples, params.thresholdDb, params.ratio, params.attackSec, params.releaseSec, sampleRate, jsState);
  }
  const jsTime = performance.now() - jsStart;

  // Reset samples
  for (let i = 0; i < bufferSize; i++) {
    samples[i] = Math.random() * 2 - 1;
  }

  // WASM
  const wasmStart = performance.now();
  for (let i = 0; i < iterations; i++) {
    processCompressor(samples, params, wasmState, sampleRate);
  }
  const wasmTime = performance.now() - wasmStart;

  return {
    name: 'Compressor',
    jsTimeMs: jsTime,
    wasmTimeMs: wasmTime,
    speedup: jsTime / wasmTime,
    bufferSize,
    iterations,
  };
}

export async function runBenchmarks(bufferSize = 4096, iterations = 10000): Promise<BenchmarkResult[]> {
  await initDspWasm();

  console.log(`\n🎯 DSP WASM Benchmark`);
  console.log(`Buffer size: ${bufferSize} samples`);
  console.log(`Iterations: ${iterations}`);
  console.log('─'.repeat(60));

  const results: BenchmarkResult[] = [];

  // Run benchmarks
  const gainResult = await benchmarkGain(bufferSize, iterations);
  results.push(gainResult);
  console.log(`\n📊 ${gainResult.name}`);
  console.log(`   JS:   ${gainResult.jsTimeMs.toFixed(2)}ms`);
  console.log(`   WASM: ${gainResult.wasmTimeMs.toFixed(2)}ms`);
  console.log(`   Speedup: ${gainResult.speedup.toFixed(1)}x`);

  const biquadResult = await benchmarkBiquad(bufferSize, iterations);
  results.push(biquadResult);
  console.log(`\n📊 ${biquadResult.name}`);
  console.log(`   JS:   ${biquadResult.jsTimeMs.toFixed(2)}ms`);
  console.log(`   WASM: ${biquadResult.wasmTimeMs.toFixed(2)}ms`);
  console.log(`   Speedup: ${biquadResult.speedup.toFixed(1)}x`);

  const compressorResult = await benchmarkCompressor(bufferSize, iterations);
  results.push(compressorResult);
  console.log(`\n📊 ${compressorResult.name}`);
  console.log(`   JS:   ${compressorResult.jsTimeMs.toFixed(2)}ms`);
  console.log(`   WASM: ${compressorResult.wasmTimeMs.toFixed(2)}ms`);
  console.log(`   Speedup: ${compressorResult.speedup.toFixed(1)}x`);

  // Summary
  const avgSpeedup = results.reduce((acc, r) => acc + r.speedup, 0) / results.length;
  console.log('\n─'.repeat(60));
  console.log(`✅ Average Speedup: ${avgSpeedup.toFixed(1)}x`);
  console.log('─'.repeat(60));

  return results;
}

// Run if called directly
if (typeof window !== 'undefined') {
  (window as unknown as { runDspBenchmark: typeof runBenchmarks }).runDspBenchmark = runBenchmarks;
}
