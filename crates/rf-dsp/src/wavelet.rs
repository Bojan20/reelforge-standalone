//! Multi-resolution Analysis: Wavelet Transform & Constant-Q Transform
//!
//! Professional time-frequency analysis with optimal resolution trade-offs.
//!
//! ## Features
//! - Discrete Wavelet Transform (DWT) - Daubechies, Symlet, Coiflet wavelets
//! - Continuous Wavelet Transform (CWT) - Morlet, Mexican Hat
//! - Constant-Q Transform (CQT) - Musical frequency resolution
//! - Inverse transforms for resynthesis
//! - Multi-resolution spectrogram

use std::f64::consts::PI;
use realfft::{RealFftPlanner, RealToComplex, ComplexToReal};
use rustfft::num_complex::Complex;

/// Wavelet family types
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum WaveletType {
    /// Daubechies wavelets (db1-db20)
    Daubechies(u8),
    /// Symlet wavelets (sym2-sym20)
    Symlet(u8),
    /// Coiflet wavelets (coif1-coif5)
    Coiflet(u8),
    /// Haar wavelet (same as db1)
    Haar,
    /// Morlet wavelet (for CWT)
    Morlet { omega0: f64 },
    /// Mexican Hat / Ricker wavelet
    MexicanHat,
}

impl Default for WaveletType {
    fn default() -> Self {
        WaveletType::Daubechies(4)
    }
}

/// Wavelet filter coefficients
#[derive(Debug, Clone)]
pub struct WaveletFilter {
    /// Low-pass decomposition filter
    pub lo_d: Vec<f64>,
    /// High-pass decomposition filter
    pub hi_d: Vec<f64>,
    /// Low-pass reconstruction filter
    pub lo_r: Vec<f64>,
    /// High-pass reconstruction filter
    pub hi_r: Vec<f64>,
}

impl WaveletFilter {
    /// Create filter coefficients for wavelet type
    pub fn new(wavelet: WaveletType) -> Self {
        let lo_d = match wavelet {
            WaveletType::Haar | WaveletType::Daubechies(1) => {
                vec![0.7071067811865476, 0.7071067811865476]
            }
            WaveletType::Daubechies(2) => {
                vec![
                    0.4829629131445341, 0.8365163037378079,
                    0.2241438680420134, -0.1294095225512604,
                ]
            }
            WaveletType::Daubechies(3) => {
                vec![
                    0.3326705529500826, 0.8068915093110925,
                    0.4598775021184915, -0.1350110200102546,
                    -0.0854412738820267, 0.0352262918857095,
                ]
            }
            WaveletType::Daubechies(4) => {
                vec![
                    0.2303778133088965, 0.7148465705529156,
                    0.6308807679298589, -0.0279837694168599,
                    -0.1870348117190930, 0.0308413818355607,
                    0.0328830116668852, -0.0105974017850690,
                ]
            }
            WaveletType::Daubechies(6) => {
                vec![
                    0.1115407433501095, 0.4946238903984533,
                    0.7511339080210959, 0.3152503517091982,
                    -0.2262646939654400, -0.1297668675672625,
                    0.0975016055873225, 0.0275228655303053,
                    -0.0315820393174862, 0.0005538422011614,
                    0.0047772575109455, -0.0010773010853085,
                ]
            }
            WaveletType::Daubechies(8) => {
                vec![
                    0.0544158422431049, 0.3128715909143031,
                    0.6756307362972904, 0.5853546836541907,
                    -0.0158291052563816, -0.2840155429615702,
                    0.0004724845739124, 0.1287474266204837,
                    -0.0173693010018083, -0.0440882539307952,
                    0.0139810279173995, 0.0087460940474061,
                    -0.0048703529934518, -0.0003917403733770,
                    0.0006754494064506, -0.0001174767841248,
                ]
            }
            WaveletType::Symlet(4) => {
                vec![
                    -0.0757657147893407, -0.0296355276459541,
                    0.4976186676324578, 0.8037387518052163,
                    0.2978577956055422, -0.0992195435769354,
                    -0.0126039672622612, 0.0322231006040713,
                ]
            }
            WaveletType::Symlet(8) => {
                vec![
                    -0.0033824159513594, -0.0005421323316355,
                    0.0316950878103452, 0.0076074873252848,
                    -0.1432942383510542, -0.0612733590679088,
                    0.4813596512592012, 0.7771857516997478,
                    0.3644418948359564, -0.0519458381078751,
                    -0.0272190299168137, 0.0491371796734768,
                    0.0038087520140601, -0.0149522583367926,
                    -0.0003029205145516, 0.0018899503329007,
                ]
            }
            WaveletType::Coiflet(1) => {
                vec![
                    -0.0156557285289848, -0.0727326213410511,
                    0.3848648565381134, 0.8525720416423900,
                    0.3378976709511590, -0.0727322757411889,
                ]
            }
            WaveletType::Coiflet(2) => {
                vec![
                    0.0011945726958388, -0.0016290733601404,
                    -0.0189155298252868, 0.0211018340249299,
                    0.0997835515523118, -0.0975016055873225,
                    -0.2262646939654400, 0.3152503517091982,
                    0.7511339080210959, 0.4946238903984533,
                    0.1115407433501095, -0.0315820393174862,
                ]
            }
            _ => {
                // Default to db4
                vec![
                    0.2303778133088965, 0.7148465705529156,
                    0.6308807679298589, -0.0279837694168599,
                    -0.1870348117190930, 0.0308413818355607,
                    0.0328830116668852, -0.0105974017850690,
                ]
            }
        };

        // Generate other filters from lo_d
        let n = lo_d.len();

        // Hi_d: QMF of lo_d
        let hi_d: Vec<f64> = lo_d.iter().enumerate()
            .map(|(i, &x)| if i % 2 == 0 { -x } else { x })
            .rev()
            .collect();

        // Lo_r: time-reversed lo_d
        let lo_r: Vec<f64> = lo_d.iter().rev().copied().collect();

        // Hi_r: time-reversed hi_d
        let hi_r: Vec<f64> = hi_d.iter().rev().copied().collect();

        Self { lo_d, hi_d, lo_r, hi_r }
    }
}

/// Discrete Wavelet Transform
pub struct DWT {
    filter: WaveletFilter,
    max_level: usize,
}

impl DWT {
    pub fn new(wavelet: WaveletType) -> Self {
        Self {
            filter: WaveletFilter::new(wavelet),
            max_level: 10,
        }
    }

    /// Set maximum decomposition level
    pub fn set_max_level(&mut self, level: usize) {
        self.max_level = level;
    }

    /// Single-level decomposition
    pub fn decompose_level(&self, signal: &[f64]) -> (Vec<f64>, Vec<f64>) {
        let n = signal.len();
        let filter_len = self.filter.lo_d.len();

        // Symmetric extension
        let extended = Self::symmetric_extend(signal, filter_len);

        // Convolve and downsample
        let approx = self.convolve_downsample(&extended, &self.filter.lo_d);
        let detail = self.convolve_downsample(&extended, &self.filter.hi_d);

        (approx, detail)
    }

    /// Multi-level decomposition
    pub fn decompose(&self, signal: &[f64], level: usize) -> WaveletDecomposition {
        let level = level.min(self.max_level);
        let mut approx = signal.to_vec();
        let mut details = Vec::with_capacity(level);

        for _ in 0..level {
            if approx.len() < self.filter.lo_d.len() {
                break;
            }
            let (a, d) = self.decompose_level(&approx);
            details.push(d);
            approx = a;
        }

        WaveletDecomposition {
            approximation: approx,
            details,
        }
    }

    /// Reconstruct from decomposition
    pub fn reconstruct(&self, decomp: &WaveletDecomposition) -> Vec<f64> {
        let mut approx = decomp.approximation.clone();

        for detail in decomp.details.iter().rev() {
            approx = self.reconstruct_level(&approx, detail);
        }

        approx
    }

    /// Single-level reconstruction
    fn reconstruct_level(&self, approx: &[f64], detail: &[f64]) -> Vec<f64> {
        // Upsample
        let up_approx = Self::upsample(approx);
        let up_detail = Self::upsample(detail);

        // Convolve with reconstruction filters
        let rec_approx = self.convolve(&up_approx, &self.filter.lo_r);
        let rec_detail = self.convolve(&up_detail, &self.filter.hi_r);

        // Add
        let out_len = approx.len() * 2;
        let offset = self.filter.lo_r.len() - 1;

        (0..out_len)
            .map(|i| {
                let idx = i + offset;
                let a = if idx < rec_approx.len() { rec_approx[idx] } else { 0.0 };
                let d = if idx < rec_detail.len() { rec_detail[idx] } else { 0.0 };
                a + d
            })
            .collect()
    }

    fn symmetric_extend(signal: &[f64], pad: usize) -> Vec<f64> {
        let n = signal.len();
        let mut extended = Vec::with_capacity(n + 2 * pad);

        // Left extension
        for i in (1..=pad).rev() {
            let idx = i.min(n - 1);
            extended.push(signal[idx]);
        }

        // Original signal
        extended.extend_from_slice(signal);

        // Right extension
        for i in 0..pad {
            let idx = (n - 2 - i).max(0);
            extended.push(signal[idx]);
        }

        extended
    }

    fn convolve_downsample(&self, signal: &[f64], filter: &[f64]) -> Vec<f64> {
        let n = signal.len();
        let m = filter.len();
        let out_len = (n - m + 1) / 2;

        (0..out_len)
            .map(|i| {
                let start = i * 2;
                filter.iter().enumerate()
                    .map(|(j, &f)| signal[start + j] * f)
                    .sum()
            })
            .collect()
    }

    fn convolve(&self, signal: &[f64], filter: &[f64]) -> Vec<f64> {
        let n = signal.len();
        let m = filter.len();
        let out_len = n + m - 1;

        (0..out_len)
            .map(|i| {
                let mut sum = 0.0;
                for j in 0..m {
                    if i >= j && i - j < n {
                        sum += signal[i - j] * filter[j];
                    }
                }
                sum
            })
            .collect()
    }

    fn upsample(signal: &[f64]) -> Vec<f64> {
        let mut out = vec![0.0; signal.len() * 2];
        for (i, &s) in signal.iter().enumerate() {
            out[i * 2] = s;
        }
        out
    }
}

/// Wavelet decomposition result
#[derive(Debug, Clone)]
pub struct WaveletDecomposition {
    /// Approximation coefficients (low frequency)
    pub approximation: Vec<f64>,
    /// Detail coefficients per level (high frequency)
    pub details: Vec<Vec<f64>>,
}

impl WaveletDecomposition {
    /// Get total number of levels
    pub fn levels(&self) -> usize {
        self.details.len()
    }

    /// Get energy per level
    pub fn energy_per_level(&self) -> Vec<f64> {
        let mut energies = Vec::with_capacity(self.details.len() + 1);

        // Approximation energy
        let approx_energy: f64 = self.approximation.iter()
            .map(|x| x * x)
            .sum();
        energies.push(approx_energy);

        // Detail energies
        for detail in &self.details {
            let energy: f64 = detail.iter().map(|x| x * x).sum();
            energies.push(energy);
        }

        energies
    }

    /// Denoise by thresholding detail coefficients
    pub fn denoise(&mut self, threshold: f64, soft: bool) {
        for detail in &mut self.details {
            for coeff in detail.iter_mut() {
                if soft {
                    // Soft thresholding
                    if coeff.abs() <= threshold {
                        *coeff = 0.0;
                    } else {
                        *coeff = coeff.signum() * (coeff.abs() - threshold);
                    }
                } else {
                    // Hard thresholding
                    if coeff.abs() <= threshold {
                        *coeff = 0.0;
                    }
                }
            }
        }
    }
}

/// Continuous Wavelet Transform
pub struct CWT {
    wavelet: WaveletType,
    sample_rate: f64,
    scales: Vec<f64>,
    fft_planner: RealFftPlanner<f64>,
}

impl CWT {
    pub fn new(wavelet: WaveletType, sample_rate: f64) -> Self {
        Self {
            wavelet,
            sample_rate,
            scales: Vec::new(),
            fft_planner: RealFftPlanner::new(),
        }
    }

    /// Set scales for analysis
    pub fn set_scales(&mut self, min_scale: f64, max_scale: f64, num_scales: usize) {
        self.scales = (0..num_scales)
            .map(|i| {
                let t = i as f64 / (num_scales - 1) as f64;
                min_scale * (max_scale / min_scale).powf(t)
            })
            .collect();
    }

    /// Set scales from frequency range
    pub fn set_frequency_range(&mut self, min_freq: f64, max_freq: f64, num_scales: usize) {
        // Scale is inversely proportional to frequency
        let min_scale = self.sample_rate / (2.0 * PI * max_freq);
        let max_scale = self.sample_rate / (2.0 * PI * min_freq);
        self.set_scales(min_scale, max_scale, num_scales);
    }

    /// Compute CWT using FFT-based convolution
    pub fn transform(&mut self, signal: &[f64]) -> CWTResult {
        let n = signal.len();
        let fft_size = n.next_power_of_two() * 2; // Zero-pad for linear convolution

        let fft = self.fft_planner.plan_fft_forward(fft_size);
        let ifft = self.fft_planner.plan_fft_inverse(fft_size);

        // FFT of signal
        let mut signal_padded = vec![0.0; fft_size];
        signal_padded[..n].copy_from_slice(signal);
        let mut signal_fft = vec![Complex::new(0.0, 0.0); fft_size / 2 + 1];
        fft.process(&mut signal_padded, &mut signal_fft).unwrap();

        // Compute scalogram
        let mut scalogram = Vec::with_capacity(self.scales.len());
        let mut frequencies = Vec::with_capacity(self.scales.len());

        for &scale in &self.scales {
            // Generate wavelet in frequency domain
            let wavelet_fft = self.wavelet_fft(scale, fft_size);

            // Multiply in frequency domain
            let mut product: Vec<Complex<f64>> = signal_fft.iter()
                .zip(wavelet_fft.iter())
                .map(|(&s, &w)| s * w)
                .collect();

            // IFFT
            let mut result = vec![0.0; fft_size];
            ifft.process(&mut product, &mut result).unwrap();

            // Normalize and extract
            let norm = 1.0 / (fft_size as f64);
            let coeffs: Vec<Complex<f64>> = result[..n].iter()
                .map(|&r| Complex::new(r * norm, 0.0))
                .collect();

            scalogram.push(coeffs);

            // Frequency for this scale
            let freq = match self.wavelet {
                WaveletType::Morlet { omega0 } => omega0 * self.sample_rate / (2.0 * PI * scale),
                WaveletType::MexicanHat => self.sample_rate / (2.5 * scale),
                _ => self.sample_rate / (2.0 * PI * scale),
            };
            frequencies.push(freq);
        }

        CWTResult {
            scalogram,
            scales: self.scales.clone(),
            frequencies,
            sample_rate: self.sample_rate,
        }
    }

    fn wavelet_fft(&self, scale: f64, fft_size: usize) -> Vec<Complex<f64>> {
        let n = fft_size / 2 + 1;
        let df = self.sample_rate / fft_size as f64;

        match self.wavelet {
            WaveletType::Morlet { omega0 } => {
                (0..n)
                    .map(|k| {
                        let f = k as f64 * df;
                        let omega = 2.0 * PI * f;
                        let omega_scaled = scale * omega;

                        // Morlet wavelet FT
                        let val = (PI.powf(0.25)) *
                            (-0.5 * (omega_scaled - omega0).powi(2)).exp() *
                            scale.sqrt();

                        Complex::new(val, 0.0)
                    })
                    .collect()
            }
            WaveletType::MexicanHat => {
                (0..n)
                    .map(|k| {
                        let f = k as f64 * df;
                        let omega = 2.0 * PI * f;
                        let omega_scaled = scale * omega;

                        // Mexican hat FT
                        let val = (2.0 / 3.0_f64.sqrt() * PI.powf(0.25)) *
                            omega_scaled.powi(2) *
                            (-0.5 * omega_scaled.powi(2)).exp() *
                            scale.sqrt();

                        Complex::new(val, 0.0)
                    })
                    .collect()
            }
            _ => {
                // For discrete wavelets, use Morlet as fallback for CWT
                let omega0 = 6.0;
                (0..n)
                    .map(|k| {
                        let f = k as f64 * df;
                        let omega = 2.0 * PI * f;
                        let omega_scaled = scale * omega;
                        let val = (PI.powf(0.25)) *
                            (-0.5 * (omega_scaled - omega0).powi(2)).exp() *
                            scale.sqrt();
                        Complex::new(val, 0.0)
                    })
                    .collect()
            }
        }
    }
}

/// CWT result
#[derive(Debug, Clone)]
pub struct CWTResult {
    /// Scalogram: complex coefficients [scale][time]
    pub scalogram: Vec<Vec<Complex<f64>>>,
    /// Scales used
    pub scales: Vec<f64>,
    /// Corresponding frequencies
    pub frequencies: Vec<f64>,
    /// Sample rate
    pub sample_rate: f64,
}

impl CWTResult {
    /// Get magnitude scalogram
    pub fn magnitude(&self) -> Vec<Vec<f64>> {
        self.scalogram.iter()
            .map(|row| row.iter().map(|c| c.norm()).collect())
            .collect()
    }

    /// Get power scalogram
    pub fn power(&self) -> Vec<Vec<f64>> {
        self.scalogram.iter()
            .map(|row| row.iter().map(|c| c.norm_sqr()).collect())
            .collect()
    }

    /// Get phase scalogram
    pub fn phase(&self) -> Vec<Vec<f64>> {
        self.scalogram.iter()
            .map(|row| row.iter().map(|c| c.arg()).collect())
            .collect()
    }
}

/// Constant-Q Transform - Musical frequency resolution
pub struct CQT {
    sample_rate: f64,
    min_freq: f64,
    max_freq: f64,
    bins_per_octave: usize,
    /// Precomputed kernels
    kernels: Vec<CQTKernel>,
    fft_planner: RealFftPlanner<f64>,
}

#[derive(Clone)]
struct CQTKernel {
    freq: f64,
    length: usize,
    kernel: Vec<Complex<f64>>,
    sparse_kernel: Vec<(usize, Complex<f64>)>, // For sparse computation
}

impl CQT {
    pub fn new(sample_rate: f64, min_freq: f64, max_freq: f64, bins_per_octave: usize) -> Self {
        let mut cqt = Self {
            sample_rate,
            min_freq,
            max_freq,
            bins_per_octave,
            kernels: Vec::new(),
            fft_planner: RealFftPlanner::new(),
        };
        cqt.compute_kernels();
        cqt
    }

    /// Create with standard musical settings (C1 to C8, 12 bins/octave)
    pub fn musical(sample_rate: f64) -> Self {
        Self::new(sample_rate, 32.7, 4186.0, 12) // C1 to C8
    }

    fn compute_kernels(&mut self) {
        let num_octaves = (self.max_freq / self.min_freq).log2();
        let num_bins = (num_octaves * self.bins_per_octave as f64).ceil() as usize;

        // Q factor (constant across all bins)
        let q = 1.0 / (2.0_f64.powf(1.0 / self.bins_per_octave as f64) - 1.0);

        self.kernels.clear();

        for k in 0..num_bins {
            let freq = self.min_freq * 2.0_f64.powf(k as f64 / self.bins_per_octave as f64);
            if freq > self.max_freq {
                break;
            }

            // Window length for this frequency
            let n_k = (q * self.sample_rate / freq).ceil() as usize;
            let n_k = n_k.max(4); // Minimum kernel size

            // Generate kernel (complex sinusoid * window)
            let kernel: Vec<Complex<f64>> = (0..n_k)
                .map(|n| {
                    let t = n as f64 / n_k as f64;
                    // Hann window
                    let window = 0.5 * (1.0 - (2.0 * PI * t).cos());
                    // Complex sinusoid
                    let phase = 2.0 * PI * freq * n as f64 / self.sample_rate;
                    let sinusoid = Complex::new(phase.cos(), -phase.sin());
                    sinusoid * window / n_k as f64
                })
                .collect();

            // Create sparse kernel (only significant values)
            let threshold = 1e-6;
            let sparse_kernel: Vec<(usize, Complex<f64>)> = kernel.iter()
                .enumerate()
                .filter(|(_, c)| c.norm() > threshold)
                .map(|(i, &c)| (i, c))
                .collect();

            self.kernels.push(CQTKernel {
                freq,
                length: n_k,
                kernel,
                sparse_kernel,
            });
        }
    }

    /// Compute CQT of signal
    pub fn transform(&self, signal: &[f64]) -> CQTResult {
        let n = signal.len();
        let num_bins = self.kernels.len();

        let mut coefficients = Vec::with_capacity(num_bins);
        let mut frequencies = Vec::with_capacity(num_bins);

        for kernel in &self.kernels {
            frequencies.push(kernel.freq);

            // Number of frames (hop = kernel length / 4)
            let hop = kernel.length / 4;
            let num_frames = if n > kernel.length {
                (n - kernel.length) / hop + 1
            } else {
                1
            };

            let mut bin_coeffs = Vec::with_capacity(num_frames);

            for frame in 0..num_frames {
                let start = frame * hop;
                let end = (start + kernel.length).min(n);

                // Sparse convolution
                let mut sum = Complex::new(0.0, 0.0);
                for &(i, k) in &kernel.sparse_kernel {
                    if start + i < end {
                        sum += k * signal[start + i];
                    }
                }

                bin_coeffs.push(sum);
            }

            coefficients.push(bin_coeffs);
        }

        CQTResult {
            coefficients,
            frequencies,
            bins_per_octave: self.bins_per_octave,
            sample_rate: self.sample_rate,
        }
    }

    /// Get center frequencies
    pub fn frequencies(&self) -> Vec<f64> {
        self.kernels.iter().map(|k| k.freq).collect()
    }

    /// Get MIDI note numbers for each bin
    pub fn midi_notes(&self) -> Vec<f64> {
        self.kernels.iter()
            .map(|k| 69.0 + 12.0 * (k.freq / 440.0).log2())
            .collect()
    }
}

/// CQT result
#[derive(Debug, Clone)]
pub struct CQTResult {
    /// Complex coefficients [bin][time]
    pub coefficients: Vec<Vec<Complex<f64>>>,
    /// Center frequencies per bin
    pub frequencies: Vec<f64>,
    /// Bins per octave
    pub bins_per_octave: usize,
    /// Sample rate
    pub sample_rate: f64,
}

impl CQTResult {
    /// Get magnitude spectrogram
    pub fn magnitude(&self) -> Vec<Vec<f64>> {
        self.coefficients.iter()
            .map(|row| row.iter().map(|c| c.norm()).collect())
            .collect()
    }

    /// Get power spectrogram (dB)
    pub fn power_db(&self) -> Vec<Vec<f64>> {
        self.coefficients.iter()
            .map(|row| {
                row.iter()
                    .map(|c| {
                        let power = c.norm_sqr();
                        10.0 * (power + 1e-10).log10()
                    })
                    .collect()
            })
            .collect()
    }

    /// Get chroma features (fold into 12 pitch classes)
    pub fn chroma(&self) -> Vec<Vec<f64>> {
        let num_frames = self.coefficients.first().map(|c| c.len()).unwrap_or(0);
        let mut chroma = vec![vec![0.0; num_frames]; 12];

        for (bin, coeffs) in self.coefficients.iter().enumerate() {
            // MIDI note for this bin
            let midi = 69.0 + 12.0 * (self.frequencies[bin] / 440.0).log2();
            let pitch_class = (midi.round() as usize) % 12;

            for (frame, &c) in coeffs.iter().enumerate() {
                chroma[pitch_class][frame] += c.norm_sqr();
            }
        }

        // Normalize each frame
        for frame in 0..num_frames {
            let sum: f64 = chroma.iter().map(|pc| pc[frame]).sum();
            if sum > 1e-10 {
                for pc in &mut chroma {
                    pc[frame] /= sum;
                }
            }
        }

        chroma
    }

    /// Get MIDI note number for frequency
    pub fn freq_to_midi(freq: f64) -> f64 {
        69.0 + 12.0 * (freq / 440.0).log2()
    }

    /// Get frequency for MIDI note
    pub fn midi_to_freq(midi: f64) -> f64 {
        440.0 * 2.0_f64.powf((midi - 69.0) / 12.0)
    }
}

/// Multi-resolution spectrogram combining multiple analysis methods
pub struct MultiResolutionAnalyzer {
    sample_rate: f64,
    dwt: DWT,
    cwt: CWT,
    cqt: CQT,
}

impl MultiResolutionAnalyzer {
    pub fn new(sample_rate: f64) -> Self {
        let mut cwt = CWT::new(WaveletType::Morlet { omega0: 6.0 }, sample_rate);
        cwt.set_frequency_range(20.0, 20000.0, 128);

        Self {
            sample_rate,
            dwt: DWT::new(WaveletType::Daubechies(4)),
            cwt,
            cqt: CQT::musical(sample_rate),
        }
    }

    /// Analyze with all methods
    pub fn analyze(&mut self, signal: &[f64]) -> MultiResolutionResult {
        MultiResolutionResult {
            dwt: self.dwt.decompose(signal, 8),
            cwt: self.cwt.transform(signal),
            cqt: self.cqt.transform(signal),
        }
    }

    /// Get optimal representation for frequency range
    pub fn analyze_adaptive(&mut self, signal: &[f64], freq_range: (f64, f64)) -> Vec<Vec<f64>> {
        let (min_freq, max_freq) = freq_range;

        if max_freq < 500.0 {
            // Low frequencies: use CWT for better frequency resolution
            self.cwt.set_frequency_range(min_freq, max_freq, 64);
            self.cwt.transform(signal).magnitude()
        } else if min_freq > 2000.0 {
            // High frequencies: use DWT for better time resolution
            let decomp = self.dwt.decompose(signal, 6);
            // Return detail levels as "spectrogram"
            decomp.details.iter()
                .map(|d| d.clone())
                .collect()
        } else {
            // Mid frequencies: use CQT for musical analysis
            self.cqt.transform(signal).magnitude()
        }
    }
}

/// Combined multi-resolution result
pub struct MultiResolutionResult {
    pub dwt: WaveletDecomposition,
    pub cwt: CWTResult,
    pub cqt: CQTResult,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dwt_reconstruct() {
        let signal: Vec<f64> = (0..256).map(|i| (i as f64 * 0.1).sin()).collect();
        let dwt = DWT::new(WaveletType::Daubechies(4));

        let decomp = dwt.decompose(&signal, 4);
        let reconstructed = dwt.reconstruct(&decomp);

        // Check reconstruction error
        let error: f64 = signal.iter().zip(reconstructed.iter())
            .map(|(a, b)| (a - b).abs())
            .sum::<f64>() / signal.len() as f64;

        assert!(error < 0.01, "Reconstruction error too high: {}", error);
    }

    #[test]
    fn test_cqt_frequencies() {
        let cqt = CQT::new(44100.0, 55.0, 1760.0, 12);
        let freqs = cqt.frequencies();

        // Should have 5 octaves * 12 bins = 60 bins (approximately)
        assert!(freqs.len() >= 48 && freqs.len() <= 72);

        // First frequency should be near min_freq
        assert!((freqs[0] - 55.0).abs() < 1.0);
    }

    #[test]
    fn test_cwt_morlet() {
        let mut cwt = CWT::new(WaveletType::Morlet { omega0: 6.0 }, 1000.0);
        cwt.set_scales(1.0, 100.0, 32);

        // Generate test signal: 10 Hz sine
        let signal: Vec<f64> = (0..1000).map(|i| {
            (2.0 * PI * 10.0 * i as f64 / 1000.0).sin()
        }).collect();

        let result = cwt.transform(&signal);
        let mag = result.magnitude();

        // Should have 32 scales
        assert_eq!(mag.len(), 32);
    }
}
